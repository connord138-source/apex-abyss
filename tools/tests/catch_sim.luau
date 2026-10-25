-- How often players meet rare fish (run_catch_sim.sh). Swimmers cruise each biome at
-- the speed of a fish at the biome's middle level (Size.topSpeed), wandering inside
-- it at the heights its schools swim, on the real school layout (Shared/Schools), the
-- real tide clock (Shared/Tides: Golden Hour, Blood Tide, Bioluminescent Night, the
-- Prism Tide, the Sardine Run's own schools) and the real spawner (Shared/RareSpawn,
-- Config/Catch), and eat rare fish:
--   * a hunter sees a rare fish's glint within 240 studs (SchoolController
--     GLINT_RANGE), a quarter of them hidden by rock at any moment, and detours to it;
--   * a casual player only takes the rare fish that swim by within 60 studs of its
--     way, and cruises a little slower.
-- Both eat plain fish as they go (one every 2 s from a school beside them), so eaten
-- fish are about as in play. Prints minutes per catch for each rarity (averaged over
-- the normal tides; the Prism per Prism Tide), the Catch of the Week, the species
-- mix, the hours each skin goal takes (Config/Catch `unlock`), the old per-fish rolls
-- for comparison (owner, 2026-10-18: "I caught three crystal fish in about 5
-- minutes"), and twelve players hunting one biome. Fails if a hunter's rate is far
-- from Config/Catch `every`.
local Config = require("./Config")
local Seafloor = require("./Seafloor")
local Schools = require("./Schools")
local Size = require("./Size")
local Tides = require("./Tides")
local Catch = require("./Catch")
local RareSpawn = require("./RareSpawn")
local args = require("./simargs")

local CatchConfig = Config.Catch
local TideConfig = Config.Tides
local START = 1791763200 -- Monday 2026-10-12 00:00 UTC (week 2 of the Catch of the Week)
local DT = 1
local GLINT = 240
local BLOCKED = 0.25
local RECHECK = 5
local HOURS = args.hours
local rng = Random.new(20261018)

type Kind = { name: string, detect: number, cruise: number, chase: number }
local HUNTER: Kind = { name = "hunter", detect = GLINT, cruise = 0.9, chase = 1.0 }
local CASUAL: Kind = { name = "casual", detect = 60, cruise = 0.8, chase = 0.85 }

type Region = {
	id: string,
	level: number,
	heights: { number },
	r0: number,
	r1: number,
	a0: number,
	a1: number,
	deep: boolean,
}
local REGIONS: { Region } = {}
local LEVELS: { [string]: { level: number, heights: { number } } } = {
	KelpShallows = { level = 5, heights = { 8, 45 } },
	ShipwreckGraveyard = { level = 17, heights = { 10, 50 } },
	CoralReef = { level = 32, heights = { 10, 55 } },
	OpenBlue = { level = 45, heights = { 140, 400 } },
	SunkenRuins = { level = 60, heights = { 20, 120 } },
	HydrothermalVents = { level = 75, heights = { 20, 150 } },
	AbyssalTrench = { level = 90, heights = { 30, 200 } },
}
for _, biome in Config.Biomes.list do
	local plan = LEVELS[biome.id]
	if plan then
		table.insert(REGIONS, {
			id = biome.id,
			level = plan.level,
			heights = plan.heights,
			r0 = math.max(biome.radiusFrom, 170),
			r1 = math.min(biome.radiusTo, 1450),
			a0 = biome.angleFrom,
			a1 = biome.angleTo,
			deep = biome.deep,
		})
	end
end

-- Each school's middle and how far its fish stray (as RareSpawn sees it)
type Info = { x: number, y: number, z: number, loop: number, deep: boolean }
local infos: { Info } = {}
for _, school in Schools.list do
	local r = Seafloor.polar(school.center.X, school.center.Z)
	table.insert(infos, {
		x = school.center.X,
		y = school.center.Y,
		z = school.center.Z,
		loop = school.radius + school.spread + school.height,
		deep = r > Config.World.shelf.radius,
	})
end

-- The tide at a moment (Shared/Tides works each slot out from the last Prism Tide:
-- kept per slot here, since the sim asks every second)
local tideCache: { [number]: { id: string, startsAt: number } } = {}
local function tideAt(unix: number): (string, number)
	local slot = unix // TideConfig.slotSeconds
	local known = tideCache[slot]
	if known == nil then
		local tide, startsAt = Tides.at(unix)
		known = { id = tide.id, startsAt = startsAt }
		tideCache[slot] = known
	end
	return known.id, known.startsAt
end

local function apart(ax: number, ay: number, az: number, bx: number, by: number, bz: number): number
	local dx, dy, dz = ax - bx, ay - by, az - bz
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---------------------------------------------------------------------------------
-- The models: the new spawner, and the old per-fish rolls
---------------------------------------------------------------------------------
type Model = {
	step: (now: number, unix: number, swimmers: { any }) -> (),
	each: (fn: (index: number, rarity: string) -> ()) -> (),
	rarityOf: (index: number) -> string?,
	take: (index: number, now: number) -> string?,
	eaten: { [number]: number },
}

local spawned: { [string]: number } = {} -- rare fish set swimming (the new spawner)
local function newModel(seed: number): Model
	local spawner = RareSpawn.new(seed)
	local eaten: { [number]: number } = {}
	local function eatenUntil(index: number): number?
		return eaten[index]
	end
	return {
		eaten = eaten,
		step = function(now, unix, swimmers)
			for index, back in eaten do
				if back <= now then
					eaten[index] = nil
					RareSpawn.respawned(spawner, index, now)
				end
			end
			local hunters, everyone = {}, {}
			for i, s in swimmers do
				local p = Vector3.new(s.x, s.y, s.z)
				table.insert(everyone, p)
				table.insert(hunters, { id = i, position = p, length = s.length, deep = s.region.deep })
			end
			local tideId, startsAt = tideAt(unix)
			local changes =
				RareSpawn.step(spawner, DT, now, unix, tideId, unix - startsAt, hunters, everyone, eatenUntil)
			for _, change in changes do
				if change.rarity then
					spawned[change.rarity] = (spawned[change.rarity] or 0) + 1
				end
			end
		end,
		each = function(fn)
			for index, rare in spawner.rare do
				fn(index, rare.rarity)
			end
		end,
		rarityOf = function(index)
			return RareSpawn.rarityOf(spawner, index)
		end,
		take = function(index, now)
			local prey = Config.Prey.byId[Schools.fish[index].prey]
			eaten[index] = now + prey.respawn
			return RareSpawn.take(spawner, index)
		end,
	}
end

-- The rules before 2026-10-18: every fish rolled at these odds when it spawned, and
-- 36 fish no one was within 260 of re-rolled every 5 s (×3 in a tide's first 2 min)
local OLD = { Golden = 1 / 35, Glowing = 1 / 180, Crystal = 1 / 900, Prism = 1 / 150 }
local OLD_ORDER = { "Prism", "Crystal", "Glowing", "Golden" }
local function oldModel(seed: number): Model
	local oldRng = Random.new(seed)
	local rarity: { [number]: string } = {}
	local eaten: { [number]: number } = {}
	local cursor = 0
	local nextRotate = 0
	local started = false
	local function roll(index: number, tideId: string, unix: number): string?
		local fish = Schools.fish[index]
		local tide = TideConfig.byId[tideId]
		local featured = Catch.weekly(unix)
		local r = oldRng:NextNumber()
		local edge = 0
		for _, id in OLD_ORDER do
			local chance = if id == "Prism" and tideId ~= "Prism" then 0 else OLD[id]
			chance *= tide.rarity[id] or 1
			if infos[fish.school].deep and tideId == "Biolum" and id == "Glowing" then
				chance *= TideConfig.deepGlow
			end
			if featured and featured.prey == fish.prey and featured.rarity == id then
				chance *= 3
			end
			edge += chance
			if r < edge then
				return id
			end
		end
		return nil
	end
	return {
		eaten = eaten,
		step = function(now, unix, swimmers)
			local tideId, startedAt = tideAt(unix)
			local tide = TideConfig.byId[tideId]
			if not started then
				started = true
				for index = 1, Schools.COUNT do
					if Schools.out(index, tide.id) then
						rarity[index] = roll(index, tide.id, unix)
					end
				end
			end
			for index, back in eaten do
				if back <= now then
					eaten[index] = nil
					rarity[index] = if Schools.out(index, tide.id) then roll(index, tide.id, unix) else nil
				end
			end
			if now < nextRotate then
				return
			end
			nextRotate = now + 5
			local quota = 36 * (if unix - startedAt < 120 then 3 else 1)
			local done = 0
			for _ = 1, Schools.COUNT do
				if done >= quota then
					break
				end
				cursor = cursor % Schools.COUNT + 1
				local index = cursor
				if eaten[index] then
					continue
				end
				if not Schools.out(index, tide.id) then
					rarity[index] = nil
					continue
				end
				local info = infos[Schools.fish[index].school]
				local close = false
				for _, s in swimmers do
					if apart(s.x, s.y, s.z, info.x, info.y, info.z) < 260 + info.loop then
						local p = Schools.position(index, now)
						if apart(s.x, s.y, s.z, p.X, p.Y, p.Z) < 260 then
							close = true
							break
						end
					end
				end
				if not close then
					done += 1
					rarity[index] = roll(index, tide.id, unix)
				end
			end
		end,
		each = function(fn)
			for index, id in rarity do
				fn(index, id)
			end
		end,
		rarityOf = function(index)
			return rarity[index]
		end,
		take = function(index, now)
			local prey = Config.Prey.byId[Schools.fish[index].prey]
			eaten[index] = now + prey.respawn
			local id = rarity[index]
			rarity[index] = nil
			return id
		end,
	}
end

---------------------------------------------------------------------------------
-- Swimmers
---------------------------------------------------------------------------------
local function inRegion(region: Region, x: number, z: number): boolean
	local r, angle = Seafloor.polar(x, z)
	return r >= region.r0 and r <= region.r1 and Seafloor.inSector(angle, region.a0, region.a1)
end

local function pointIn(region: Region): (number, number)
	for _ = 1, 200 do
		local r = rng:NextNumber(region.r0, region.r1)
		local span = (region.a1 - region.a0) % 360
		if span == 0 then
			span = 360
		end
		local angle = math.rad(region.a0 + rng:NextNumber(0, span))
		local x, z = math.cos(angle) * r, math.sin(angle) * r
		if inRegion(region, x, z) then
			return x, z
		end
	end
	return region.r0, 0
end

-- A spot 250–700 studs from (x, z) in the biome with the straight way to it inside
-- the biome too (anywhere in it, failing that)
local function waypoint(region: Region, x: number, z: number): (number, number)
	for _ = 1, 60 do
		local tx, tz = pointIn(region)
		local d = math.sqrt((tx - x) ^ 2 + (tz - z) ^ 2)
		if d >= 250 and d <= 700 then
			local clear = true
			for k = 1, 7 do
				local f = k / 8
				if not inRegion(region, x + (tx - x) * f, z + (tz - z) * f) then
					clear = false
					break
				end
			end
			if clear then
				return tx, tz
			end
		end
	end
	return pointIn(region)
end

type Tally = {
	minutes: { [string]: number }, -- tide id → minutes swum
	catches: { [string]: { [string]: number } }, -- tide id → rarity → catches
	species: { [string]: { [string]: number } }, -- rarity → prey → catches
	featured: number,
	featuredMinutes: number, -- minutes near where the featured prey swims
}

local function newTally(): Tally
	return { minutes = {}, catches = {}, species = {}, featured = 0, featuredMinutes = 0 }
end

local function newSwimmer(region: Region, kind: Kind)
	local mass = Size.massForLevel(region.level)
	local length = Size.length(mass)
	local speed = Size.topSpeed(length)
	local x, z = pointIn(region)
	local h = rng:NextNumber(region.heights[1], region.heights[2])
	return {
		region = region,
		kind = kind,
		length = length,
		speed = speed,
		x = x,
		z = z,
		y = Seafloor.y(x, z) + h,
		h = h,
		heading = rng:NextNumber(0, 2 * math.pi),
		nextTurn = 0,
		wx = nil :: number?,
		wz = nil :: number?,
		nextHeight = 0,
		nextBite = 0,
		target = nil :: number?,
		seen = {} :: { [number]: { visible: boolean, untilAt: number } },
		tally = newTally(),
	}
end

local function visible(s: any, index: number, now: number): boolean
	local entry = s.seen[index]
	if entry == nil or now >= entry.untilAt then
		entry = { visible = rng:NextNumber() >= BLOCKED, untilAt = now + RECHECK }
		s.seen[index] = entry
	end
	return entry.visible
end

-- Eats a plain fish beside it now and then (so eaten fish are in play)
local function snack(s: any, model: Model, now: number)
	if now < s.nextBite then
		return
	end
	s.nextBite = now + 2
	for schoolIndex, info in infos do
		if apart(s.x, s.y, s.z, info.x, info.y, info.z) < 40 + info.loop * 0.5 then
			local school = Schools.list[schoolIndex]
			local index = school.first + rng:NextInteger(0, school.count - 1)
			if
				model.eaten[index] == nil
				and model.rarityOf(index) == nil
				and Size.canSwallow(s.length, Schools.fish[index].length)
			then
				local prey = Config.Prey.byId[Schools.fish[index].prey]
				model.eaten[index] = now + prey.respawn
			end
			return
		end
	end
end

local function record(s: any, rarityId: string, index: number, tideId: string, unix: number)
	local tally: Tally = s.tally
	-- (the Catch of the Week's fish are counted apart: its own stream would skew the
	-- rarity's rate for the week the sim runs in)
	local featured = Catch.weekly(unix)
	if featured and featured.prey == Schools.fish[index].prey and featured.rarity == rarityId then
		tally.featured += 1
		return
	end
	local byTide = tally.catches[tideId] or {}
	tally.catches[tideId] = byTide
	byTide[rarityId] = (byTide[rarityId] or 0) + 1
	local preyId = Schools.fish[index].prey
	local bySpecies = tally.species[rarityId] or {}
	tally.species[rarityId] = bySpecies
	bySpecies[preyId] = (bySpecies[preyId] or 0) + 1
end

local function move(s: any, model: Model, now: number, unix: number, tideId: string)
	local kind: Kind = s.kind
	local tally: Tally = s.tally
	tally.minutes[tideId] = (tally.minutes[tideId] or 0) + DT / 60
	-- Time near where the featured prey swims (the Catch of the Week's own stream)
	local featured = Catch.weekly(unix)
	if now >= (s.featuredCheck or 0) then
		s.featuredCheck = now + 10
		s.nearFeatured = false
		if featured then
			for schoolIndex, info in infos do
				local school = Schools.list[schoolIndex]
				if
					school.prey == featured.prey
					and (school.tide == nil or school.tide == tideId)
					and apart(s.x, s.y, s.z, info.x, info.y, info.z) < CatchConfig.spawn.far
				then
					s.nearFeatured = true
					break
				end
			end
		end
	end
	if s.nearFeatured then
		tally.featuredMinutes += DT / 60
	end
	snack(s, model, now)
	-- Chasing a rare fish
	if s.target then
		local index = s.target :: number
		local rarityId = model.rarityOf(index)
		if rarityId == nil then
			s.target = nil
		else
			local p = Schools.position(index, now)
			local d = apart(s.x, s.y, s.z, p.X, p.Y, p.Z)
			local step = s.speed * kind.chase * DT
			if d <= step + 2 then
				s.x, s.y, s.z = p.X, p.Y, p.Z
				model.take(index, now)
				record(s, rarityId, index, tideId, unix)
				s.target = nil
			else
				local k = step / d
				s.x += (p.X - s.x) * k
				s.y += (p.Y - s.y) * k
				s.z += (p.Z - s.z) * k
			end
			return
		end
	end
	-- Cruising: from one spot in the biome to another 250–700 studs off (the way
	-- there kept inside it, so a ring-shaped biome is swum round, not across the
	-- hub), drifting a little, a new spot when it's reached or after a while
	local region: Region = s.region
	if now >= s.nextTurn or s.wx == nil or (s.wx - s.x) ^ 2 + (s.wz - s.z) ^ 2 < 60 * 60 then
		s.wx, s.wz = waypoint(region, s.x, s.z)
		s.nextTurn = now + rng:NextNumber(40, 90)
	end
	if now >= s.nextHeight then
		s.h = rng:NextNumber(region.heights[1], region.heights[2])
		s.nextHeight = now + rng:NextNumber(20, 60)
	end
	local want = math.atan2(s.wz - s.z, s.wx - s.x)
	local turn = (want - s.heading + math.pi) % (2 * math.pi) - math.pi
	s.heading += math.clamp(turn, -0.5, 0.5) + rng:NextNumber(-1, 1) * 0.08
	local v = s.speed * kind.cruise * DT
	local nx, nz = s.x + math.cos(s.heading) * v, s.z + math.sin(s.heading) * v
	if not inRegion(region, nx, nz) then
		-- (outside it, after a chase: straight back in toward the new spot)
		s.wx, s.wz = waypoint(region, s.x, s.z)
		s.heading = math.atan2(s.wz - s.z, s.wx - s.x)
		nx, nz = s.x + math.cos(s.heading) * v, s.z + math.sin(s.heading) * v
	end
	local wantY = Seafloor.y(nx, nz) + s.h
	s.x, s.z = nx, nz
	s.y += math.clamp(wantY - s.y, -v, v)
	-- A glint in sight?
	local best: number? = nil
	local bestD = math.huge
	model.each(function(index, _rarityId)
		local fish = Schools.fish[index]
		local info = infos[fish.school]
		if apart(s.x, s.y, s.z, info.x, info.y, info.z) > kind.detect + info.loop + 5 then
			return
		end
		if not Size.canSwallow(s.length, fish.length) then
			return
		end
		local p = Schools.position(index, now)
		local d = apart(s.x, s.y, s.z, p.X, p.Y, p.Z)
		if d <= kind.detect and d < bestD and visible(s, index, now) then
			best, bestD = index, d
		end
	end)
	s.target = best
end

-- Runs `swimmers` for `hours` against a model; returns their tallies
local function run(model: Model, swimmers: { any }, hours: number, startUnix: number)
	local steps = math.floor(hours * 3600 / DT)
	for i = 0, steps - 1 do
		local now = i * DT
		local unix = startUnix + now
		local tideId = tideAt(unix)
		model.step(now, unix, swimmers)
		for _, s in swimmers do
			move(s, model, now, unix, tideId)
		end
	end
end

---------------------------------------------------------------------------------
-- Reading the tallies
---------------------------------------------------------------------------------
local RARITIES: { string } = {}
for _, rarity in CatchConfig.rarities do
	table.insert(RARITIES, rarity.id)
end

-- Minutes per catch of a rarity over the normal tides (not the Prism Tide), and the
-- Prism's catches per Prism Tide, from tallies added together
local function rates(tallies: { Tally }): ({ [string]: number }, number, { [string]: number })
	local minutes, prismMinutes = 0, 0
	local counts: { [string]: number } = {}
	local all: { [string]: number } = {}
	local totalMinutes = 0
	for _, tally in tallies do
		for tideId, m in tally.minutes do
			totalMinutes += m
			if tideId == "Prism" then
				prismMinutes += m
			else
				minutes += m
			end
		end
		for tideId, byRarity in tally.catches do
			for rarityId, n in byRarity do
				all[rarityId] = (all[rarityId] or 0) + n
				if tideId ~= "Prism" or rarityId == "Prism" then
					local key = if tideId == "Prism" then "Prism" else rarityId
					counts[key] = (counts[key] or 0) + n
				end
			end
		end
	end
	local result: { [string]: number } = {}
	for _, id in RARITIES do
		local n = counts[id] or 0
		result[id] = if n > 0 then (if id == "Prism" then prismMinutes else minutes) / n else math.huge
	end
	local perTide = (counts.Prism or 0) / math.max(prismMinutes / 20, 1e-9)
	local perMinute: { [string]: number } = {}
	for _, id in RARITIES do
		perMinute[id] = (all[id] or 0) / math.max(totalMinutes, 1e-9)
	end
	return result, perTide, perMinute
end

local function fmt(minutes: number): string
	if minutes == math.huge then
		return "    —"
	elseif minutes >= 100 then
		return string.format("%5.0f", minutes)
	end
	return string.format("%5.1f", minutes)
end

-- Hours of hunting (in that biome) until `species` prey species have `each` catches of
-- a rarity: catches arrive at `perMinute`, their species drawn by the mix seen
local function unlockHours(
	perMinute: number,
	mix: { [string]: number },
	each: number,
	species: number
): (number, number)
	local names, weights, total = {}, {}, 0
	for preyId, n in mix do
		table.insert(names, preyId)
		table.insert(weights, n)
		total += n
	end
	if #names < species or perMinute <= 0 then
		return math.huge, math.huge
	end
	local trials: { number } = {}
	for _ = 1, 1500 do
		local counts: { number } = table.create(#names, 0)
		local done, catches = 0, 0
		while done < species do
			catches += 1
			local pick = rng:NextNumber() * total
			local k = #names
			for i, w in weights do
				pick -= w
				if pick < 0 then
					k = i
					break
				end
			end
			counts[k] += 1
			if counts[k] == each then
				done += 1
			end
		end
		table.insert(trials, catches / perMinute / 60)
	end
	table.sort(trials)
	return trials[math.floor(#trials * 0.5)], trials[math.floor(#trials * 0.8)]
end

---------------------------------------------------------------------------------
-- The runs
---------------------------------------------------------------------------------
local failures = 0
local function check(ok: boolean, text: string)
	if not ok then
		failures += 1
		print("FAIL: " .. text)
	end
end

local header = "                       LV  speed |  Silver Golden Glowing Crystal (min/catch) | Prism/tide"
print(
	`{Schools.COUNT} prey fish in {#Schools.list} schools; {HOURS} h per biome and player; normal tides averaged`
)

-- 1. The old rules, to check the sim against what the owner saw
print("\nOLD RULES (per-fish rolls), a hunter:")
print(header)
for _, region in REGIONS do
	if region.id ~= "KelpShallows" and region.id ~= "CoralReef" then
		continue
	end
	local s = newSwimmer(region, HUNTER)
	run(oldModel(7), { s }, math.min(HOURS, 6), START)
	local r, prism = rates({ s.tally })
	print(
		string.format(
			"  %-20s %3d %6.1f | %s  %s  %s  %s %s | %4.1f",
			region.id,
			region.level,
			s.speed,
			fmt(r.Silver),
			fmt(r.Golden),
			fmt(r.Glowing),
			fmt(r.Crystal),
			"                ",
			prism
		)
	)
end

-- 2. The new spawner, a hunter and a casual player in each biome
local hunterTallies: { Tally } = {}
local casualTallies: { Tally } = {}
local mixes: {
	[string]: {
		perMinute: { [string]: number },
		species: { [string]: { [string]: number } },
		all: { [string]: number },
	},
} =
	{}
local featuredCatches, featuredMinutes = 0, 0
for _, kind in { HUNTER, CASUAL } do
	print(`\nNEW SPAWNER, a {kind.name}:`)
	print(header)
	for r, region in REGIONS do
		if
			args.quick
			and region.id ~= "KelpShallows"
			and region.id ~= "CoralReef"
			and region.id ~= "SunkenRuins"
		then
			continue
		end
		local s = newSwimmer(region, kind)
		table.clear(spawned)
		run(newModel(100 + r), { s }, HOURS, START)
		local result, prism, perMinute = rates({ s.tally })
		local found = {}
		for _, id in RARITIES do
			local caught = 0
			for _, byRarity in s.tally.catches do
				caught += byRarity[id] or 0
			end
			table.insert(
				found,
				string.format("%s %.0f%%", string.sub(id, 1, 2), caught / math.max(spawned[id] or 0, 1) * 100)
			)
		end
		table.insert(if kind == HUNTER then hunterTallies else casualTallies, s.tally)
		if kind == HUNTER then
			-- (the Prism's rate is per minute of Prism Tide)
			perMinute.Prism = prism / 20
			local all: { [string]: number } = {}
			for _, bySpecies in s.tally.species do
				for preyId, n in bySpecies do
					all[preyId] = (all[preyId] or 0) + n
				end
			end
			mixes[region.id] = { perMinute = perMinute, species = s.tally.species, all = all }
			featuredCatches += s.tally.featured
			featuredMinutes += s.tally.featuredMinutes
		end
		print(
			string.format(
				"  %-20s %3d %6.1f | %s  %s  %s  %s %s | %4.1f",
				region.id,
				region.level,
				s.speed,
				fmt(result.Silver),
				fmt(result.Golden),
				fmt(result.Glowing),
				fmt(result.Crystal),
				"                ",
				prism
			) .. `   found {table.concat(found, " ")}`
		)
	end
end

-- More Prism Tides for the hunter: in HOURS a biome sees ~5, a few catches each, so
-- the Prism figure swung with the seed (2026-10-27: 1.2 to 2.0 a tide over four
-- seeds on the same rules). Each biome's hunter swims PRISM_EXTRA more, each from the
-- tide's start on its own seed, and the Prism a tide pools them all.
local PRISM_EXTRA = 6
local prismTallies: { Tally } = {}
do
	local starts: { number } = {}
	local slot = TideConfig.slotSeconds
	local unix = START + math.ceil(HOURS * 3600 / slot) * slot
	while #starts < PRISM_EXTRA do
		local tideId, startsAt = tideAt(unix)
		if tideId == TideConfig.prism.id and startsAt == unix then
			table.insert(starts, unix)
		end
		unix += slot
	end
	for r, region in REGIONS do
		if
			args.quick
			and region.id ~= "KelpShallows"
			and region.id ~= "CoralReef"
			and region.id ~= "SunkenRuins"
		then
			continue
		end
		for k, startsAt in starts do
			local s = newSwimmer(region, HUNTER)
			run(newModel(700 + r * 10 + k), { s }, slot / 3600, startsAt)
			table.insert(prismTallies, s.tally)
		end
	end
end
local hunter = rates(hunterTallies)
local _, hunterPrism =
	rates(table.move(prismTallies, 1, #prismTallies, #hunterTallies + 1, table.clone(hunterTallies)))
local casual, casualPrism = rates(casualTallies)
print("\nALL BIOMES, minutes per catch (normal tides) · Prism per Prism Tide:")
for _, id in RARITIES do
	local want = CatchConfig.byId[id].every
	if id == "Prism" then
		print(
			string.format(
				"  %-8s hunter %4.1f a tide (want ~%.0f)   casual %4.1f a tide (%.0f%%)",
				id,
				hunterPrism,
				20 / want,
				casualPrism,
				casualPrism / math.max(hunterPrism, 1e-9) * 100
			)
		)
		check(
			math.abs(hunterPrism - 20 / want) / (20 / want) < 0.35,
			`Prism: {hunterPrism} a tide vs Config/Catch every {want}`
		)
	else
		print(
			string.format(
				"  %-8s hunter %6.1f min (Config every %g)   casual %6.1f min (%.0f%% of the hunter's catches)",
				id,
				hunter[id],
				want,
				casual[id],
				hunter[id] / casual[id] * 100
			)
		)
		check(
			math.abs(hunter[id] - want) / want < 0.3,
			`{id}: a hunter every {hunter[id]} min vs Config/Catch every {want}`
		)
	end
end
if featuredCatches > 0 then
	print(
		string.format(
			"  Catch of the Week (%s): one every %.0f min of hunting near where it swims (Config weekly.every %g)",
			(function()
				local f = Catch.weekly(START)
				return if f then `{f.rarity} {f.prey}` else "?"
			end)(),
			featuredMinutes / featuredCatches,
			CatchConfig.weekly.every
		)
	)
end

-- Each tide on its own (a hunter, every biome)
do
	local minutes: { [string]: number } = {}
	local catches: { [string]: { [string]: number } } = {}
	for _, tally in hunterTallies do
		for tideId, m in tally.minutes do
			minutes[tideId] = (minutes[tideId] or 0) + m
		end
		for tideId, byRarity in tally.catches do
			catches[tideId] = catches[tideId] or {}
			for rarityId, n in byRarity do
				catches[tideId][rarityId] = (catches[tideId][rarityId] or 0) + n
			end
		end
	end
	print("  a hunter in each tide, minutes per catch:")
	for _, tide in TideConfig.list do
		local m = minutes[tide.id] or 0
		if m <= 0 then
			continue
		end
		local line = string.format("    %-22s", tide.name)
		for _, id in RARITIES do
			local n = (catches[tide.id] or {})[id] or 0
			line ..= string.format(" %s %s", string.sub(id, 1, 2), fmt(if n > 0 then m / n else math.huge))
		end
		print(line)
	end
end

-- 3. The skin goals: hours of hunting in one biome
print("  (a found share counts every rare fish set swimming; the week's own stream's are caught apart)")
print("\nSKIN GOALS, hours of hunting in one biome (median / 80th percentile):")
for _, id in RARITIES do
	local rarity = CatchConfig.byId[id]
	local line = string.format("  %-8s %d × %d species:", id, rarity.unlock.each, rarity.unlock.species)
	for _, region in REGIONS do
		local mix = mixes[region.id]
		if mix == nil then
			continue
		end
		-- (the species mix over every rarity: a rare fish's species is picked the same
		-- way whatever its rarity, and the rare tiers alone are too few to read it)
		local median, p80 =
			unlockHours(mix.perMinute[id] or 0, mix.all, rarity.unlock.each, rarity.unlock.species)
		local short = string.sub(region.id, 1, 6)
		if median == math.huge then
			line ..= ` {short} n/a`
		elseif id == "Prism" then
			-- (hours of Prism Tide: 3 a tide)
			line ..= string.format(" %s %.0f/%.0f tides", short, median * 3, p80 * 3)
		else
			line ..= string.format(" %s %.1f/%.1f", short, median, p80)
		end
	end
	print(line)
end
print("  species mix (hunter, all rarities):")
for _, region in REGIONS do
	local mix = mixes[region.id]
	if mix == nil then
		continue
	end
	local total: { [string]: number } = {}
	for _, bySpecies in mix.species do
		for preyId, n in bySpecies do
			total[preyId] = (total[preyId] or 0) + n
		end
	end
	local parts = {}
	for preyId, n in total do
		table.insert(parts, `{preyId} {n}`)
	end
	table.sort(parts)
	print(`    {region.id}: {table.concat(parts, ", ")}`)
end

-- 4. Twelve players hunting the Kelp Shallows together
do
	local region = REGIONS[1]
	for _, candidate in REGIONS do
		if candidate.id == "KelpShallows" then
			region = candidate
		end
	end
	local swimmers = {}
	for _ = 1, 12 do
		table.insert(swimmers, newSwimmer(region, HUNTER))
	end
	run(newModel(999), swimmers, math.min(HOURS, 8), START)
	local tallies = {}
	for _, s in swimmers do
		table.insert(tallies, s.tally)
	end
	local crowd = rates(tallies)
	local solo = mixes.KelpShallows
	print("\nTWELVE HUNTERS in the Kelp Shallows, minutes per catch each (solo in brackets):")
	local line = " "
	for _, id in RARITIES do
		if id ~= "Prism" then
			local alone = if solo and (solo.perMinute[id] or 0) > 0 then 1 / solo.perMinute[id] else math.huge
			line ..= string.format(" %s %s (%s)", id, fmt(crowd[id]), fmt(alone))
		end
	end
	print(line)
	check(crowd.Golden < hunter.Golden * 3, "twelve hunters starve each other of Golden fish")
end

if failures == 0 then
	print("\ncatch_sim: OK")
else
	error(`catch_sim: {failures} failures`)
end
