--!strict
-- Chum and the Whale Fall (Config/Chum, GDD §5 and §8). A fish that gets eaten bursts
-- part of its lost Haul into a cloud of chunks (HuntService fires Events.burst);
-- during a Blood Tide slicks of chum appear round players out in the biomes; about
-- every 26 minutes a dead whale sinks into a random biome and feeds the server for
-- five minutes. Chunks follow shared paths (Shared/Chum), so clients draw them and
-- eat them at once (ChumController) and this checks each eat against where the chunk
-- is; a chunk's kg goes straight onto the eater's Haul. AI predators come to a cloud
-- (PredatorService asks `nearest`).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Biomes = require(ReplicatedStorage.Shared.Biomes)
local Chum = require(ReplicatedStorage.Shared.Chum)
local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Size = require(ReplicatedStorage.Shared.Size)
local Tides = require(ReplicatedStorage.Shared.Tides)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local FishService = require(script.Parent.FishService)
local HuntService = require(script.Parent.HuntService)

local tune = Config.Chum
local Forage = Config.Forage
local World = Config.World

local ChumService = {}

-- What one fish has taken from one whale (Haul before ×2 Mass and Frenzy), and the
-- most it may (Config/Chum `whale.hauls` of its full Haul)
type Fed = { taken: number, cap: number, told: boolean }

type Entry = {
	cloud: Chum.Cloud,
	eaten: { [number]: number }, -- chunk → clock it's back (math.huge: gone)
	respawn: number?, -- a whale's chunks grow back
	fed: { [Player]: Fed }, -- a whale: each fish's share so far
}

local MAX_CLOUDS = 24

local clouds: { [number]: Entry } = {}
local nextId = 1
local rng = Random.new()
-- The Whale Fall announced or under way (`cloud`: its cloud's id once it's sinking)
local whale: {
	at: Vector3,
	floor: number,
	yaw: number,
	biome: Biomes.Biome,
	startsAt: number,
	cloud: number?,
}? =
	nil
local nextWhaleAt = 0
local warned = false -- the next whale has been announced

local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include
floorParams.FilterDescendantsInstances = { workspace.Terrain }

-- The real ground under a point (the Terrain), or the nominal floor
local function floorUnder(x: number, z: number, from: number): number
	local hit = workspace:Raycast(Vector3.new(x, from, z), Vector3.new(0, -1400, 0), floorParams)
	return if hit then hit.Position.Y else Seafloor.y(x, z)
end

-- A chunk's kg in a biome: a share of a mid-range fish's banked mass there
local function chunkKg(biome: Biomes.Biome?): number
	if biome == nil then
		return tune.minChunk
	end
	local mid = (biome.minLevel + biome.maxLevel) / 2
	return math.max(tune.minChunk, tune.biomeChunk * Size.massForLevel(mid))
end

local function payload(entry: Entry): { [string]: any }
	local cloud = entry.cloud
	local eaten: { [string]: number } = {}
	for i, backAt in entry.eaten do
		eaten[tostring(i)] = if backAt == math.huge then -1 else backAt
	end
	return {
		id = cloud.id,
		kind = cloud.kind,
		x = cloud.x,
		y = cloud.y,
		z = cloud.z,
		floor = cloud.floor,
		born = cloud.born,
		ends = cloud.ends,
		chunks = cloud.chunks,
		biome = cloud.biome,
		yaw = cloud.yaw,
		eaten = eaten,
	}
end

local function remove(id: number)
	local entry = clouds[id]
	if entry then
		clouds[id] = nil
		Net.chum("remove", { id = id })
		-- Fish full of this whale can eat the next one
		for player in entry.fed do
			if player:GetAttribute("WhaleFull") == id then
				player:SetAttribute("WhaleFull", nil)
			end
		end
	end
end

-- Adds a cloud: `count` chunks of `each` kg round (x, y, z)
local function add(
	kind: string,
	at: Vector3,
	floor: number,
	count: number,
	each: number,
	spread: number,
	seconds: number,
	biome: Biomes.Biome?,
	respawn: number?,
	yaw: number?
): number
	-- Room for it: the oldest goes
	local total, oldest, oldestBorn = 0, nil, math.huge
	for id, entry in clouds do
		total += 1
		if entry.cloud.kind ~= "whale" and entry.cloud.born < oldestBorn then
			oldest, oldestBorn = id, entry.cloud.born
		end
	end
	if total >= MAX_CLOUDS and oldest then
		remove(oldest)
	end
	local id = nextId
	nextId += 1
	local chunks: { Chum.Chunk } = {}
	for _, offset in Chum.offsets(kind, count, spread, id * 7919, yaw) do
		table.insert(chunks, { m = each, ox = offset[1], oy = offset[2], oz = offset[3] })
	end
	local now = Timing.clock()
	local cloud: Chum.Cloud = {
		id = id,
		kind = kind,
		x = at.X,
		y = at.Y,
		z = at.Z,
		floor = floor,
		born = now,
		ends = now + seconds,
		chunks = chunks,
		biome = if biome then biome.id else nil,
		yaw = yaw,
	}
	local entry: Entry = { cloud = cloud, eaten = {}, respawn = respawn, fed = {} }
	clouds[id] = entry
	Net.chum("add", payload(entry))
	return id
end

-- A lost Haul bursts into chum where its fish died
local function burst(_victim: Player, position: Vector3, haul: number, length: number)
	if haul < tune.minHaul then
		return
	end
	local count = math.clamp(math.floor(haul / tune.chunkKg + 0.5), tune.chunks.min, tune.chunks.max)
	local tide = Tides.at(Timing.unix())
	local seconds = tune.lifetime * (if tide.chum then 1.5 else 1)
	local floor = floorUnder(position.X, position.Z, position.Y + 4)
	add(
		"chum",
		position,
		floor,
		count,
		haul / count,
		tune.spread.base + tune.spread.perLength * length,
		seconds,
		Biomes.at(position)
	)
end

-- Admin: chum at a spot
function ChumService.burstAt(position: Vector3, haul: number)
	burst(Players:GetPlayers()[1], position, haul, 6)
end

-- The middle of the nearest cloud with chunks left within `range` of `position`
-- (AI predators swim to it)
function ChumService.nearest(position: Vector3, range: number): Vector3?
	local now = Timing.clock()
	local best: Vector3? = nil
	local bestDistance = range
	for _, entry in clouds do
		local left = false
		for i in entry.cloud.chunks do
			if (entry.eaten[i] or 0) <= now then
				left = true
				break
			end
		end
		if left then
			local center = Chum.center(entry.cloud, now)
			local distance = (center - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = center, distance
			end
		end
	end
	return best
end

-- Where the Whale Fall is (or is about to be), for the admin panel
function ChumService.whale(): Vector3?
	return if whale then whale.at else nil
end

local function onEat(player: Player, batch: any)
	if typeof(batch) ~= "table" or #batch > 12 then
		return
	end
	local mouth, length, slack = HuntService.mouth(player)
	if mouth == nil then
		return
	end
	local now = Timing.clock()
	-- The client's reach and suction (as forage), with room for the chunk's own size
	local reach = (Size.reach(length) * Forage.REACH_SCALE + Forage.REACH_BONUS) * 1.35 + 1.6 + slack
	local fed, fresh, whaleGain, count = 0, 0, 0, 0
	-- Whale and slick chunks are shares of the fish's own full Haul (Config/Chum
	-- `chunkHaul`), so they're worth the same share of a dive at every level; a full
	-- Haul takes no more (HuntService), so a whale's share only counts what fits
	local full = HuntService.fullHaul(player)
	local room = math.max(full - HuntService.haul(player), 0)
	for _, pair in batch do
		if typeof(pair) ~= "table" then
			continue
		end
		local id, index = pair[1], pair[2]
		local entry = if typeof(id) == "number" then clouds[id] else nil
		if entry == nil or typeof(index) ~= "number" or entry.cloud.chunks[index] == nil then
			continue
		end
		if (entry.eaten[index] or 0) > now or now >= entry.cloud.ends then
			continue
		end
		-- Where it is now, or a moment ago (the eater saw it a little in the past)
		local here = Chum.chunk(entry.cloud, index, now)
		local before = Chum.chunk(entry.cloud, index, now - 0.4)
		if math.min((here - mouth).Magnitude, (before - mouth).Magnitude) > reach then
			continue
		end
		-- A whale feeds each fish only so much (Config/Chum `whale.hauls`): a full fish
		-- leaves its chunks for the others
		if entry.cloud.kind == "whale" then
			local share = entry.fed[player]
			if share == nil then
				share = { taken = 0, cap = full * tune.whale.hauls, told = false }
				entry.fed[player] = share
			end
			-- (in Haul, before ×2 Mass and Frenzy)
			local take = math.min(full * tune.whale.chunkHaul, math.max(share.cap - share.taken, 0))
			if take > 1e-6 then
				local fits = math.min(take, room)
				room -= fits
				share.taken += fits
				whaleGain += fits
			end
			if share.cap - share.taken <= 1e-6 and not share.told then
				share.told = true
				player:SetAttribute("WhaleFull", entry.cloud.id)
				Net.notify(player, "You're full of whale! Leave the rest for the others", "info")
			end
			if take <= 1e-6 then
				continue
			end
		end
		local backAt = if entry.respawn then now + entry.respawn else math.huge
		entry.eaten[index] = backAt
		Net.chum("eat", {
			id = entry.cloud.id,
			index = index,
			backAt = if backAt == math.huge then -1 else backAt,
			by = player.UserId,
		})
		-- A dead fish's chum is Haul that was already grown (×2 Mass, Frenzy): it
		-- goes back on as it is, so kills don't compound; slicks and whales are new food
		-- (a whale's share was reckoned above)
		if entry.cloud.kind == "chum" then
			fed += entry.cloud.chunks[index].m
		elseif entry.cloud.kind ~= "whale" then
			fresh += full * tune.slick.chunkHaul
		end
		count += 1
	end
	if fed > 0 then
		HuntService.gain(player, fed, "raw")
	end
	if fresh > 0 then
		HuntService.gain(player, fresh, "rated")
	end
	if whaleGain > 0 then
		HuntService.gain(player, whaleGain, "rated")
	end
	if count > 0 then
		Events.ate:fire(player, count)
	end
end

-- How much of the world's dressing a carcass at (x, z), turned `yaw`, would lie in:
-- 0 is open, level floor. Columns every 6 studs over its whole footprint where the
-- solid ground stands over the sand (Shared/Ground) or the sand itself rises or falls
-- more than LEVEL from its middle, plus every piece of dressing, solid or soft, in the
-- box it fills (PC overnight 2026-10-14: one in the Sunken Ruins came to
-- rest under a ruin's lintel; PC 2026-10-15: five columns let the reef's sponges and
-- staghorns through the flukes and flank of a Coral Reef whale).
local DRESSING = { "Rocks", "Coral", "Wrecks", "Ruins", "Vents", "Cliff" } -- under Workspace.World.Biomes
-- Studs the sand may rise or fall under the footprint from its middle (PC 2026-10-15
-- round 2: a Coral Reef dune buried a whale's flukes, and one on a hump left its tail
-- floating ~9 studs over the sand)
local LEVEL = 3
local overlap: OverlapParams? = nil

local function dressingParams(): OverlapParams?
	if overlap then
		return overlap
	end
	local world = workspace:FindFirstChild("World")
	local biomes = if world then world:FindFirstChild("Biomes") else nil
	if biomes == nil then
		return nil
	end
	local include: { Instance } = {}
	for _, name in DRESSING do
		local folder = biomes:FindFirstChild(name)
		if folder then
			table.insert(include, folder)
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	params.RespectCanCollide = false
	overlap = params
	return params
end

-- Also answers its two parts: the columns' count (uneven sand, solid dressing) and
-- how many pieces of dressing are in the box
local function blocked(x: number, z: number, floor: number, yaw: number): (number, number, number)
	local length = tune.whale.length
	local frame = CFrame.new(x, floor, z) * CFrame.Angles(0, yaw, 0)
	local count = 0
	for along = -length * 0.5, length * 0.5 + 0.01, 6 do
		for across = -length * 0.24, length * 0.24 + 0.01, 6 do
			local p = frame:PointToWorldSpace(Vector3.new(along, 0, across))
			local terrain = floorUnder(p.X, p.Z, World.surfaceY - 5)
			if Ground.y(p.X, p.Z) > terrain + 2.5 then
				count += 3
			end
			if math.abs(terrain - floor) > LEVEL then
				count += 1
			end
		end
	end
	local parts = 0
	local params = dressingParams()
	if params then
		local box = frame * CFrame.new(0, 9, 0)
		parts = #workspace:GetPartBoundsInBox(box, Vector3.new(length, 14, length * 0.5), params)
	end
	return count + parts, count, parts
end

-- A spot in a biome on its floor, and the carcass's turn: the first of 40 tries with
-- open floor under its whole footprint, else the try with the least dressing in the
-- way (ChumController hides the small corals still poking through on each client).
-- A deep biome's whale lies on its deep floor, never on the shelf's lip above the
-- drop-off (PC 2026-10-15 round 2: a Trench whale settled at y 8 at radius ~893).
-- `crush` (an admin test) wants the opposite: level sand with the most small
-- dressing in the box, so the hiding can be seen working.
local function siteIn(biome: Biomes.Biome, crush: boolean?): (Vector3?, number, number)
	local best: Vector3?, bestYaw, bestScore = nil, 0, math.huge
	local crushAt: Vector3?, crushYaw, crushParts = nil, 0, 0
	for _ = 1, 40 do
		local span = (biome.angleTo - biome.angleFrom) % 360
		local angle = math.rad(biome.angleFrom + rng:NextNumber(0, if span == 0 then 360 else span))
		-- (never in the starter ring round the hub, Config/Chum `whale.minRadius`)
		local from = math.max(biome.radiusFrom + 40, tune.whale.minRadius)
		local to = math.min(biome.radiusTo - 40, World.boundsRadius - 80)
		if to <= from then
			continue
		end
		local r = math.sqrt(rng:NextNumber(from * from, to * to))
		local x, z = math.cos(angle) * r, math.sin(angle) * r
		local probe = Vector3.new(x, Seafloor.y(x, z) + 10, z)
		local at = Biomes.at(probe)
		if at and at.id == biome.id then
			local floor = floorUnder(x, z, World.surfaceY - 5)
			if biome.deep and floor > World.deep.floorY + 120 then
				continue
			end
			local yaw = rng:NextNumber(0, 2 * math.pi)
			local score, rough, parts = blocked(x, z, floor, yaw)
			if crush then
				if rough == 0 and parts > crushParts then
					crushAt, crushYaw, crushParts = Vector3.new(x, floor, z), yaw, parts
				end
				continue
			end
			if score == 0 then
				return Vector3.new(x, floor, z), floor, yaw
			end
			if score < bestScore then
				best, bestYaw, bestScore = Vector3.new(x, floor, z), yaw, score
			end
		end
	end
	if crushAt then
		return crushAt, crushAt.Y, crushYaw
	end
	if best then
		return best, best.Y, bestYaw
	end
	return nil, 0, 0
end

-- Picks the next Whale Fall's biome and spot, and announces it (`crush`: an admin
-- test, in the Coral Reef among its corals)
local function warnWhale(startsAt: number, crush: boolean?): boolean
	local live: { Biomes.Biome } = {}
	for _, biome in Config.Biomes.list do
		if
			biome.live
			and not table.find(tune.whale.never, biome.id)
			and (not crush or biome.id == "CoralReef")
		then
			table.insert(live, biome)
		end
	end
	if #live == 0 then
		return false
	end
	for _ = 1, 6 do
		local biome = live[rng:NextInteger(1, #live)]
		local site, floor, yaw = siteIn(biome, crush)
		if site then
			local top = math.min(floor + tune.whale.height, World.surfaceY - 30)
			whale = {
				at = Vector3.new(site.X, top, site.Z),
				floor = floor,
				yaw = yaw,
				biome = biome,
				startsAt = startsAt,
				cloud = nil,
			}
			Net.chum("warn", { x = site.X, y = top, z = site.Z, biome = biome.name, startsAt = startsAt })
			Net.notifyAll(`A WHALE FALL is coming down in the {biome.name} · it's on your map`, "rare")
			return true
		end
	end
	return false
end

local function startWhale()
	local w = whale
	if w == nil then
		return
	end
	local kg = chunkKg(w.biome) * tune.whale.chunkScale
	w.cloud = add(
		"whale",
		w.at,
		w.floor,
		tune.whale.chunks,
		kg,
		tune.whale.length * 0.45,
		tune.whale.feed,
		w.biome,
		tune.whale.respawn,
		w.yaw
	)
	Net.notifyAll(`The whale is sinking into the {w.biome.name} · feed while it lasts!`, "rare")
end

local function scheduleWhale(now: number, first: boolean)
	local studio = Timing.isStudio()
	local delay = if first
		then (if studio then tune.whale.studioFirst else tune.whale.first)
		else (if studio then tune.whale.studioEvery else tune.whale.every)
	nextWhaleAt = now + delay
end

-- Admin: a Whale Fall now (announced, sinking in a few seconds). One that's only
-- announced sinks in 5 s instead; one that's feeding ends and a fresh one comes (PC
-- overnight 2026-10-14: in Studio one was nearly always coming or under way, so the
-- button was refused most of the time)
function ChumService.whaleNow(crush: boolean?): string
	local now = Timing.clock()
	local current = whale
	if crush and current then
		-- The test always brings a fresh whale in the reef
		if current.cloud then
			remove(current.cloud)
		end
		whale = nil
		Net.chum("warn", { done = true })
		current = nil
	end
	if current and current.cloud == nil then
		current.startsAt = now + 5
		nextWhaleAt = now + 5
		warned = true
		Net.chum("warn", {
			x = current.at.X,
			y = current.at.Y,
			z = current.at.Z,
			biome = current.biome.name,
			startsAt = current.startsAt,
		})
		return `The Whale Fall in the {current.biome.name} sinks in 5 s`
	end
	if current and current.cloud then
		remove(current.cloud)
		whale = nil
		Net.chum("warn", { done = true })
	end
	if not warnWhale(now + 5, crush) then
		return if crush then "No level reef sand among corals found; try again" else "Couldn't find a spot"
	end
	warned = true
	nextWhaleAt = now + 5
	local w = whale
	return if w then `Whale Fall in the {w.biome.name} in 5 s` else "Whale Fall started"
end

-- A humpback the hunters brought down in the Open Blue (CompanionService; owner,
-- 2026-10-28: "whales should be big prey points that would draw in multiple high level
-- players"): it's the Whale Fall where it died, sinking at once from where it rolled
-- over, so everyone can feed on it. One that's only announced gives way to it; with
-- one already feeding, it bursts into a big slick instead. The carcass settles on the
-- least cluttered floor within 30 studs. Returns whether it became the Whale Fall.
function ChumService.whaleKilled(at: Vector3, yaw: number): (boolean, string?)
	local biome = Biomes.at(Vector3.new(at.X, Seafloor.y(at.X, at.Z) + 10, at.Z))
	if biome == nil then
		return false, nil
	end
	local now = Timing.clock()
	local current = whale
	if current and current.cloud then
		local floor = floorUnder(at.X, at.Z, math.min(at.Y, World.surfaceY - 5))
		add("slick", at, floor, tune.whale.chunks, chunkKg(biome), 16, tune.whale.feed * 0.4, biome)
		return false, biome.name
	end
	local spot, floor = at, floorUnder(at.X, at.Z, World.surfaceY - 5)
	local best = (blocked(at.X, at.Z, floor, yaw))
	if best > 0 then
		for i = 1, 8 do
			local angle = i * math.pi / 4
			local x, z = at.X + math.cos(angle) * 30, at.Z + math.sin(angle) * 30
			local under = floorUnder(x, z, World.surfaceY - 5)
			local score = (blocked(x, z, under, yaw))
			if score < best then
				best, spot, floor = score, Vector3.new(x, at.Y, z), under
			end
		end
	end
	local top = math.min(spot.Y, floor + tune.whale.height * 1.6, World.surfaceY - 30)
	whale = {
		at = Vector3.new(spot.X, top, spot.Z),
		floor = floor,
		yaw = yaw,
		biome = biome,
		startsAt = now,
		cloud = nil,
	}
	warned = false
	Net.chum("warn", { x = spot.X, y = top, z = spot.Z, biome = biome.name, startsAt = now })
	startWhale()
	scheduleWhale(now, false)
	return true, biome.name
end

-- A Blood Tide slick near a random player out in the biomes
local function slick()
	local out: { { player: Player, at: Vector3 } } = {}
	for player, session in HuntService.sessions() do
		local _, root = FishService.character(player)
		if root and session.alive and not session.inHub then
			table.insert(out, { player = player, at = root.Position })
		end
	end
	if #out == 0 then
		return
	end
	local pick = out[rng:NextInteger(1, #out)]
	local angle = rng:NextNumber(0, 2 * math.pi)
	local r = rng:NextNumber(tune.slick.ring[1], tune.slick.ring[2])
	local x, z = pick.at.X + math.cos(angle) * r, pick.at.Z + math.sin(angle) * r
	if Vector2.new(x, z).Magnitude > World.boundsRadius - 60 then
		return
	end
	local floor = floorUnder(x, z, math.min(pick.at.Y + 40, World.surfaceY - 5))
	local y = math.clamp(pick.at.Y + rng:NextNumber(-10, 20), floor + 4, World.surfaceY - 12)
	local at = Vector3.new(x, y, z)
	local biome = Biomes.at(at)
	if biome == nil then
		return
	end
	add("slick", at, floor, tune.slick.chunks, chunkKg(biome), 6, tune.slick.lifetime, biome)
end

function ChumService.start()
	Events.burst:connect(burst)
	Net.onRequest("EatChum", onEat)
	Net.onGetChum(function(): { [string]: any }
		local list = {}
		for _, entry in clouds do
			table.insert(list, payload(entry))
		end
		local w = whale
		return {
			clouds = list,
			warn = if w
				then { x = w.at.X, y = w.at.Y, z = w.at.Z, biome = w.biome.name, startsAt = w.startsAt }
				else nil,
		}
	end)
	scheduleWhale(Timing.clock(), true)
	local lastSlick = 0
	Guard.loop("ChumService", 1, function()
		local now = Timing.clock()
		-- Clouds run out; a whale's chunks grow back
		for id, entry in clouds do
			if now >= entry.cloud.ends then
				remove(id)
				-- (only the whale it was: the next may be announced already)
				local w = whale
				if entry.cloud.kind == "whale" and w and w.cloud == id then
					whale = nil
					Net.chum("warn", { done = true })
					-- Quiet water before the next is announced
					if not warned then
						nextWhaleAt = math.max(nextWhaleAt, now + tune.whale.rest + tune.whale.warn)
					end
				end
				continue
			end
			if entry.respawn == nil then
				local left = false
				for i in entry.cloud.chunks do
					if (entry.eaten[i] or 0) <= now then
						left = true
						break
					end
				end
				if not left then
					remove(id)
				end
			end
		end
		-- The Whale Fall's clock (one at a time: the next waits for this one to end)
		local current = whale
		if current and current.cloud and not warned then
			nextWhaleAt = math.max(nextWhaleAt, now + tune.whale.warn + 1)
		end
		if not warned and now >= nextWhaleAt - tune.whale.warn then
			warned = warnWhale(nextWhaleAt)
			if not warned then
				scheduleWhale(now, false)
			end
		end
		if warned and now >= nextWhaleAt then
			warned = false
			startWhale()
			scheduleWhale(now, false)
		end
		-- Blood Tide slicks
		local tide = Tides.at(Timing.unix())
		if tide.chum and now - lastSlick >= tune.slick.every then
			lastSlick = now
			slick()
		end
	end)
end

return ChumService
