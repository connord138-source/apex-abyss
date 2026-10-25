-- How fast a fish levels (run_progress_sim.sh). One hunter, dive after dive:
--   * out of its den (the loading wash), across the plaza and out a tunnel, toward the
--     biome that suits its level (Config/Biomes: the one whose middle level is
--     nearest, the deeper one on a tie);
--   * hunting: it picks the school with the most it can swallow for the distance (the
--     filler food on the shelf too: Config/Forage), swims at 0.9× its top speed
--     (Size.topSpeed × the species' speed: the PC's PG1 bot) at the nearest edible fish
--     and swallows every fish whose middle comes within the swallow reach plus the
--     suction (Schools.eatReach × EAT_PULLED, as SchoolController) along its way;
--     eaten fish come back after their `respawn`;
--   * home when the Haul is full: straight to the nearest tunnel, across the plaza,
--     through the portal, the bank, and out again.
-- No tides, rare fish, charms, ×2 Mass, upgrades, predators or deaths: an active
-- hunter's plain pace. Prints, per level band, minutes per dive (hunting and the swim
-- there and back), levels per dive, coral and Tide Pass XP a minute, and the hours
-- of play to each level, under the rules before the 2026-10-19 retune and the rules
-- in Config/Tuning `growth`.
local Config = require("./Config")
local Seafloor = require("./Seafloor")
local Schools = require("./Schools")
local Size = require("./Size")
local args = require("./simargs")

local Tuning = Config.Tuning
local World = Config.World
local PreyConfig = Config.Prey
local ForageConfig = Config.Forage
local PassXp = Config.Pass.xp
local Drops = Config.Treasure.drops
local G = Tuning.size.levelGrowth
local DT = 0.25
local CRUISE = 0.9
local RETARGET = 1.5
local INDOOR = Tuning.swim.indoorSpeed
local species = Config.Species.byId[args.species]
assert(species, `no species {args.species}`)
local SPEED = species.stats.speed
local rng = Random.new(20261019)
local mapRng = Random.new(7)

-- Fixed seconds a dive: the portal into the den, the bank's growth scene (3.7 s,
-- skippable), the loading wash coming out on the plaza (~4.1 s, CLAUDE.md)
local DEN_IN, BANK, DEN_OUT = 1.0, 2.5, 4.1
-- Studs swum inside the hub each way (indoor speed): from a doorway across the plaza
-- (~77 for the average den, 15–75° round from its tunnel) and out the tunnel to 195
local HUB_LEG = 180
local TUNNEL_R = World.hub.radius + World.hub.tunnelLength + 24
local TUNNEL_Y = World.hub.denFloorY + World.hub.tunnelHeight / 2

---------------------------------------------------------------------------------
-- The world as plain numbers (fast)
---------------------------------------------------------------------------------
local list, fish = Schools.list, Schools.fish
local NS, NF = #list, Schools.COUNT
local sCx, sCy, sCz, sRad, sEll, sH, sW, sPh, sFirst, sCount, sBound, sTilt =
	{}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
local fS, fOx, fOy, fOz, fPh, fLen, fRaw, fRad, fMass, fBack = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
local fMap = {} -- the chance a treasure map drops from it (TreasureService, by its species' mass)
for s, school in list do
	sCx[s], sCy[s], sCz[s] = school.center.X, school.center.Y, school.center.Z
	sRad[s], sEll[s], sH[s], sW[s], sPh[s] =
		school.radius, school.ellipse, school.height, school.angularSpeed, school.phase
	sFirst[s], sCount[s], sTilt[s] = school.first, school.count, school.tilt or 1
	local far = 0
	for i = school.first, school.first + school.count - 1 do
		far = math.max(far, fish[i].offset.Magnitude + fish[i].length)
	end
	sBound[s] = school.radius + school.height + far + 2
end
for i, f in fish do
	fS[i] = f.school
	fOx[i], fOy[i], fOz[i] = f.offset.X, f.offset.Y, f.offset.Z
	fPh[i], fLen[i], fRaw[i], fRad[i], fMass[i] = f.phase, f.length, Size.raw(f.length), f.radius, f.mass
	fBack[i] = PreyConfig.byId[f.prey].respawn
	fMap[i] = math.min(PreyConfig.byId[f.prey].mass * Drops.preyPerKg, Drops.preyMax)
end

-- Schools.position, inlined (no lifts: the sim has no Terrain)
local function fishPos(i: number, t: number): (number, number, number)
	local s = fS[i]
	local a = sPh[s] + sW[s] * t
	local r, h, e, w = sRad[s], sH[s], sEll[s], sW[s]
	local ca, sa = math.cos(a), math.sin(a)
	local a2 = 2 * a + sPh[s]
	local px, py, pz = sCx[s] + ca * r, sCy[s] + math.sin(a2) * h, sCz[s] + sa * r * e
	local vx, vy, vz = -sa * r * w, math.cos(a2) * 2 * h * w * sTilt[s], ca * r * e * w
	local m = math.sqrt(vx * vx + vy * vy + vz * vz)
	local lx, ly, lz = vx / m, vy / m, vz / m
	local rx, rz = -lz, lx
	local rm = math.sqrt(rx * rx + rz * rz)
	rx, rz = rx / rm, rz / rm
	local ux, uy, uz = -rz * ly, rz * lx - rx * lz, rx * ly
	-- (the sway: its length, never more studs than its speed, as Schools.fishFrame)
	local p, L = fPh[i], math.min(fLen[i], math.abs(w) * r)
	local ox = fOx[i] + math.sin(t * 1.3 + p) * 0.5 * L
	local oy = fOy[i] + math.sin(t * 1.9 + p * 2) * 0.35 * L
	local oz = fOz[i] + math.sin(t * 0.9 + p) * 0.6 * L
	return px + rx * ox + ux * oy - lx * oz, py + uy * oy - ly * oz, pz + rz * ox + uz * oy - lz * oz
end

do -- the inlined path must agree with Schools.position
	for _, i in { 1, 777, math.floor(NF / 2), NF } do
		for _, t in { 0, 12.5, 431 } do
			local x, y, z = fishPos(i, t)
			local p = Schools.position(i, t)
			assert(math.abs(p.X - x) + math.abs(p.Y - y) + math.abs(p.Z - z) < 1e-3, `fishPos {i} at {t}`)
		end
	end
end

-- Schools by 100-stud cell (each in every cell its loop can reach), for the eats
local CELL = 100
local cells: { [number]: { number } } = {}
local function key(cx: number, cz: number): number
	return (cx + 100) * 1000 + (cz + 100)
end
for s = 1, NS do
	local b = sBound[s] + sRad[s]
	for cx = math.floor((sCx[s] - b) / CELL), math.floor((sCx[s] + b) / CELL) do
		for cz = math.floor((sCz[s] - b) / CELL), math.floor((sCz[s] + b) / CELL) do
			local k = key(cx, cz)
			cells[k] = cells[k] or {}
			table.insert(cells[k], s)
		end
	end
end

-- The filler food (ForageService puts it on open floor at start; here spread evenly
-- over each band's area, on the nominal floor). A crab (Config/Forage `crab`) is laid
-- out over its biome's sector, stands its size × CRAB_HEIGHT over the floor, is in
-- reach CRAB_RADIUS of its size further out, and only a fish that can swallow its
-- size eats it (`gRaw`); its scuttle is left out (it's eaten where it sits)
local gX, gY, gZ, gMass, gBack, gRaw, gPad = {}, {}, {}, {}, {}, {}, {}
local FCELL = 40
local fcells: { [number]: { number } } = {}
local crabCount = 0
local crabRng = Random.new(20261019 + 77)
for _, def in ForageConfig.list do
	if def.mass <= 0 then
		continue
	end
	for _, band in def.bands do
		local from, to, angleFrom, span = band.from or 140, band.to or 830, 0, 360
		local biome = if band.biome then Config.Biomes.byId[band.biome] else nil
		if biome then
			from = math.max(biome.radiusFrom, band.from or 0, 215)
			to = math.min(biome.radiusTo, band.to or math.huge)
			angleFrom = biome.angleFrom
			span = (biome.angleTo - biome.angleFrom) % 360
			if span == 0 then
				span = 360
			end
		end
		-- (crabs draw on their own sequence, so everything else is laid out as before)
		local draw = if def.size then crabRng else rng
		for _ = 1, band.count do
			local r = math.sqrt(draw:NextNumber() * (to ^ 2 - from ^ 2) + from ^ 2)
			local angle = if biome
				then math.rad(angleFrom + draw:NextNumber() * span)
				else draw:NextNumber() * 2 * math.pi
			local x, z = math.cos(angle) * r, math.sin(angle) * r
			local size = def.size
			table.insert(gX, x)
			table.insert(gY, Seafloor.y(x, z) + (if size then size * ForageConfig.CRAB_HEIGHT else 0.6))
			table.insert(gZ, z)
			table.insert(gMass, def.mass)
			table.insert(gBack, def.respawn)
			table.insert(gRaw, if size then Size.raw(size) else 0)
			table.insert(gPad, if size then size * ForageConfig.CRAB_RADIUS else 0)
			if size then
				crabCount += 1
			end
			local k = key(math.floor(x / FCELL), math.floor(z / FCELL))
			fcells[k] = fcells[k] or {}
			table.insert(fcells[k], #gX)
		end
	end
end
local FORAGE_REACH = ForageConfig.REACH_SCALE
local FORAGE_BONUS = ForageConfig.REACH_BONUS
local FORAGE_PULLED = (function()
	local a, b = ForageConfig.PULL_SHARE / ForageConfig.PULL, 1 - ForageConfig.PULL_SHARE
	return (-b + math.sqrt(b * b + 4 * a)) / (2 * a)
end)()

---------------------------------------------------------------------------------
-- The biomes and which one a level hunts in
---------------------------------------------------------------------------------
type Biome = { id: string, def: any, schools: { number }, mid: number, ax: number, az: number }
local biomes: { Biome } = {}
local function inBiome(def: any, x: number, z: number): boolean
	local r, angle = Seafloor.polar(x, z)
	return r >= def.radiusFrom and r <= def.radiusTo and Seafloor.inSector(angle, def.angleFrom, def.angleTo)
end
for _, def in Config.Biomes.list do
	if def.live then
		local b: Biome = {
			id = def.id,
			def = def,
			schools = {},
			mid = (def.minLevel + def.maxLevel) / 2,
			ax = 0,
			az = 0,
		}
		for s = 1, NS do
			if list[s].tide == nil and inBiome(def, sCx[s], sCz[s]) then
				table.insert(b.schools, s)
				b.ax += sCx[s]
				b.az += sCz[s]
			end
		end
		b.ax /= math.max(#b.schools, 1)
		b.az /= math.max(#b.schools, 1)
		table.insert(biomes, b)
	end
end

-- The biome a point is in (Shared/Biomes.at: a sector first, else the ring round the
-- hub)
local function biomeAt(x: number, z: number): Biome?
	local r, angle = Seafloor.polar(x, z)
	local fallback: Biome? = nil
	for _, b in biomes do
		local def = b.def
		if r >= def.radiusFrom and r < def.radiusTo then
			if def.angleFrom == 0 and def.angleTo == 360 then
				fallback = fallback or b
			elseif Seafloor.inSector(angle, def.angleFrom, def.angleTo) then
				return b
			end
		end
	end
	return fallback
end

-- STAY=<biome id>: a player who keeps to one biome once its level opens it
local stayIn: string = args.stay
local function biomeFor(level: number): Biome
	for _, b in biomes do
		if b.id == stayIn and level >= b.def.minLevel then
			return b
		end
	end
	local best: Biome = biomes[1]
	local bestD = math.huge
	for _, b in biomes do
		if level >= b.def.minLevel and level <= b.def.maxLevel then
			local d = math.abs(level - b.mid)
			if d < bestD - 1e-9 or (math.abs(d - bestD) < 1e-9 and b.def.minLevel > best.def.minLevel) then
				best, bestD = b, d
			end
		end
	end
	return best
end

-- The tunnel mouths (segments 1, 7, 13, 19: east, south, west, north)
local tunnels: { { number } } = {}
for k = 0, 3 do
	local angle = k * math.pi / 2
	table.insert(tunnels, { math.cos(angle) * TUNNEL_R, TUNNEL_Y, math.sin(angle) * TUNNEL_R })
end
local function nearestTunnel(x: number, y: number, z: number): ({ number }, number)
	local best, bestD = tunnels[1], math.huge
	for _, p in tunnels do
		local d = math.sqrt((p[1] - x) ^ 2 + (p[2] - y) ^ 2 + (p[3] - z) ^ 2)
		if d < bestD then
			best, bestD = p, d
		end
	end
	return best, bestD
end

---------------------------------------------------------------------------------
-- The rules
---------------------------------------------------------------------------------
type Rules = {
	name: string,
	-- kg of Haul (and of worth) `raw` kg eaten gives a fish with this banked mass and Haul
	-- (`maxLevel`: the top level of the biome it's eaten in, Config/Biomes)
	add: (mass: number, haul: number, raw: number, maxLevel: number?) -> (number, number),
	full: (mass: number, haul: number) -> boolean,
	live: (mass: number, haul: number) -> number,
	coral: (worth: number, mass: number) -> number,
	mapAllowance: boolean?, -- prey maps at most `preyPerHour` (Config/Treasure, 2026-10-19)
}

-- Before 2026-10-19: every kg × 1 at LV 1 easing to × 0.35 by LV 8 (by the level of
-- the banked mass plus the Haul), no cap on the server, the size stopping at 1.5×
-- the banked length (MAX SIZE, where the PG1 bot banked); coral 7 × √worth
local OLD: Rules = {
	name = "before (Haul rate 0.35, a size cap only)",
	add = function(mass, haul, raw)
		local level = Size.level(mass + haul)
		local rate = 1 - 0.65 * math.clamp((level - 1) / 7, 0, 1)
		return raw * rate, raw
	end,
	full = function(mass, haul)
		return mass + haul >= mass * 1.5 ^ 3
	end,
	live = function(mass, haul)
		return math.min(mass + haul, mass * 1.5 ^ 3)
	end,
	coral = function(worth)
		return 7 * math.sqrt(worth)
	end,
}

-- Config/Tuning `growth` through Shared/Size, as HuntService `addHaul` does it
local NEW: Rules = {
	name = "after (Config/Tuning growth)",
	add = function(mass, haul, raw, maxLevel)
		local rate = Size.haulRate(mass)
			* (if maxLevel then Size.overLevel(Size.level(mass), maxLevel) else 1)
		local added = math.min(raw * rate, math.max(Size.haulCap(mass) - haul, 0))
		return added, added / rate
	end,
	full = function(mass, haul)
		return Size.isMaxed(mass, haul)
	end,
	live = function(mass, haul)
		return Size.liveMass(mass, haul)
	end,
	coral = function(worth)
		return Tuning.economy.bankCoral * math.sqrt(worth) -- (HuntService `bank`)
	end,
	mapAllowance = true,
}

-- Probing: every kg counts, never full (MODE=probe)
local PROBE: Rules = {
	name = "probe",
	add = function(_mass, _haul, raw)
		return raw, raw
	end,
	full = function()
		return false
	end,
	live = function(mass)
		return mass
	end,
	coral = function()
		return 0
	end,
}

local function passXp(worth: number): number
	return math.clamp(worth * PassXp.bankPerKg, PassXp.bankMin, PassXp.bankMax)
end

---------------------------------------------------------------------------------
-- The hunter
---------------------------------------------------------------------------------
type Hunter = {
	x: number,
	y: number,
	z: number,
	mass: number,
	haul: number,
	worth: number,
	eatenFish: { [number]: number }, -- fish index → when it's back
	eatenFood: { [number]: number },
	t: number, -- the world's clock (seconds)
	rules: Rules,
	-- this dive
	ate: number,
	fish: number, -- prey fish swallowed this dive (not filler food)
	fishKg: number, -- their kg
	firstAte: number?,
	maps: number, -- treasure maps from what it ate this dive (dug up as they come)
	tokens: number, -- the prey map allowance (TreasureService)
	tokensAt: number,
}

local function newHunter(rules: Rules, mass: number): Hunter
	return {
		x = 0,
		y = 0,
		z = 0,
		mass = mass,
		haul = 0,
		worth = 0,
		eatenFish = {},
		eatenFood = {},
		t = 0,
		rules = rules,
		ate = 0,
		fish = 0,
		fishKg = 0,
		firstAte = nil,
		maps = 0,
		tokens = Drops.preyBurst,
		tokensAt = 0,
	}
end

-- Distance from point p to the segment a → b
local function segDist(
	px: number,
	py: number,
	pz: number,
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number
): number
	local dx, dy, dz = bx - ax, by - ay, bz - az
	local len2 = dx * dx + dy * dy + dz * dz
	local u = 0
	if len2 > 1e-9 then
		u = math.clamp(((px - ax) * dx + (py - ay) * dy + (pz - az) * dz) / len2, 0, 1)
	end
	local qx, qy, qz = ax + dx * u - px, ay + dy * u - py, az + dz * u - pz
	return math.sqrt(qx * qx + qy * qy + qz * qz)
end

local function eat(h: Hunter, raw: number, map: number, isFish: boolean?)
	local b = biomeAt(h.x, h.z)
	local added, worth = h.rules.add(h.mass, h.haul, raw, if b then b.def.maxLevel else nil)
	h.haul += added
	h.worth += worth
	h.ate += 1
	if isFish then
		h.fish += 1
		h.fishKg += raw
	end
	-- A treasure map from it (TreasureService: by the prey's mass, within the allowance)
	if map > 0 then
		local allowed = true
		if h.rules.mapAllowance then
			h.tokens = math.min(Drops.preyBurst, h.tokens + (h.t - h.tokensAt) * Drops.preyPerHour / 3600)
			h.tokensAt = h.t
			allowed = h.tokens >= 1
		end
		if allowed and mapRng:NextNumber() < map then
			h.maps += 1
			if h.rules.mapAllowance then
				h.tokens -= 1
			end
		end
	end
	if h.firstAte == nil then
		h.firstAte = h.t
	end
end

-- Swallows everything in reach along the mouth's way from a to b
local function eatAlong(
	h: Hunter,
	length: number,
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number
)
	local t = h.t
	local limit = Size.raw(length) * Tuning.hunt.swallowRatio
	local mx, mz = (ax + bx) / 2, (az + bz) / 2
	local half = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2) / 2
	local seen: { [number]: boolean } = {}
	local reachBase = Size.reach(length) * PreyConfig.eat.scale + PreyConfig.eat.bonus
	for cx = math.floor((mx - half - 20) / CELL), math.floor((mx + half + 20) / CELL) do
		for cz = math.floor((mz - half - 20) / CELL), math.floor((mz + half + 20) / CELL) do
			local here = cells[key(cx, cz)]
			if here == nil then
				continue
			end
			for _, s in here do
				if seen[s] or list[s].tide ~= nil then
					continue
				end
				seen[s] = true
				local dcx, dcy, dcz = sCx[s] - mx, sCy[s] - (ay + by) / 2, sCz[s] - mz
				local reachOut = sBound[s] + sRad[s] + half + reachBase + 4
				if dcx * dcx + dcy * dcy + dcz * dcz > reachOut * reachOut then
					continue
				end
				for i = sFirst[s], sFirst[s] + sCount[s] - 1 do
					if (h.eatenFish[i] or 0) > t or fRaw[i] >= limit then
						continue
					end
					local x, y, z = fishPos(i, t)
					if
						segDist(x, y, z, ax, ay, az, bx, by, bz)
						<= (reachBase + fRad[i]) * Schools.EAT_PULLED
					then
						h.eatenFish[i] = t + fBack[i]
						eat(h, fMass[i] * Tuning.hunt.preyGain, fMap[i], true)
					end
				end
			end
		end
	end
	-- Filler food on the floor (a crab only if it can swallow it: `limit`)
	local reach = (Size.reach(length) * FORAGE_REACH + FORAGE_BONUS) * FORAGE_PULLED
	if math.min(ay, by) - Seafloor.y(mx, mz) > reach + 6 then
		return
	end
	for cx = math.floor((mx - half - reach) / FCELL), math.floor((mx + half + reach) / FCELL) do
		for cz = math.floor((mz - half - reach) / FCELL), math.floor((mz + half + reach) / FCELL) do
			local here = fcells[key(cx, cz)]
			if here == nil then
				continue
			end
			for _, g in here do
				if
					(h.eatenFood[g] or 0) <= t
					and gRaw[g] < limit
					and segDist(gX[g], gY[g], gZ[g], ax, ay, az, bx, by, bz) <= reach + gPad[g]
				then
					h.eatenFood[g] = t + gBack[g]
					eat(h, gMass[g], 0)
				end
			end
		end
	end
end

-- What to swim at: the school with the most it can swallow for the distance (or a
-- bit of filler food close by when that beats it)
type Target = { kind: "school" | "food", id: number }
local function pick(h: Hunter, biome: Biome, length: number): Target?
	local t = h.t
	local limit = Size.raw(length) * Tuning.hunt.swallowRatio
	local best: Target? = nil
	local bestScore = 0
	for _, s in biome.schools do
		local dx, dy, dz = sCx[s] - h.x, sCy[s] - h.y, sCz[s] - h.z
		local d = math.sqrt(dx * dx + dy * dy + dz * dz)
		local m = 0
		for i = sFirst[s], sFirst[s] + sCount[s] - 1 do
			if fRaw[i] < limit and (h.eatenFish[i] or 0) <= t then
				m += fMass[i]
			end
		end
		local score = m / (d + 40)
		if score > bestScore then
			best, bestScore = { kind = "school", id = s }, score
		end
	end
	local cx0, cz0 = math.floor(h.x / FCELL), math.floor(h.z / FCELL)
	for cx = cx0 - 2, cx0 + 2 do
		for cz = cz0 - 2, cz0 + 2 do
			local here = fcells[key(cx, cz)]
			if here == nil then
				continue
			end
			for _, g in here do
				if (h.eatenFood[g] or 0) <= t and gRaw[g] < limit then
					local d = math.sqrt((gX[g] - h.x) ^ 2 + (gY[g] - h.y) ^ 2 + (gZ[g] - h.z) ^ 2)
					local score = gMass[g] / (d + 40)
					if score > bestScore then
						best, bestScore = { kind = "food", id = g }, score
					end
				end
			end
		end
	end
	return best
end

-- Hunts until the Haul is full (or `limit` seconds pass); the clock runs on
local function hunt(h: Hunter, biome: Biome, limit: number)
	local target: Target? = nil
	local nextPick = 0
	local start = h.t
	while not h.rules.full(h.mass, h.haul) and h.t - start < limit do
		local length = Size.length(h.rules.live(h.mass, h.haul))
		local speed = Size.topSpeed(length) * SPEED * CRUISE
		if target == nil or h.t >= nextPick then
			target = pick(h, biome, length)
			nextPick = h.t + RETARGET
		end
		-- Where to: the target school's nearest fish it can swallow, or the food
		local tx, ty, tz = biome.ax, h.y, biome.az
		if target and target.kind == "school" then
			local s = target.id
			local limitRaw = Size.raw(length) * Tuning.hunt.swallowRatio
			local bestD = math.huge
			for i = sFirst[s], sFirst[s] + sCount[s] - 1 do
				if fRaw[i] < limitRaw and (h.eatenFish[i] or 0) <= h.t then
					local x, y, z = fishPos(i, h.t)
					local d = (x - h.x) ^ 2 + (y - h.y) ^ 2 + (z - h.z) ^ 2
					if d < bestD then
						tx, ty, tz, bestD = x, y, z, d
					end
				end
			end
			if bestD == math.huge then
				target = nil
			end
		elseif target then
			local g = target.id
			if (h.eatenFood[g] or 0) > h.t then
				target = nil
			else
				tx, ty, tz = gX[g], gY[g], gZ[g]
			end
		end
		local dx, dy, dz = tx - h.x, ty - h.y, tz - h.z
		local d = math.sqrt(dx * dx + dy * dy + dz * dz)
		local step = math.min(speed * DT, d)
		local ux, uy, uz = 0, 0, 0
		if d > 1e-6 then
			ux, uy, uz = dx / d, dy / d, dz / d
		end
		local half = length * 0.5
		local ax, ay, az = h.x + ux * half, h.y + uy * half, h.z + uz * half
		h.x += ux * step
		h.y += uy * step
		h.z += uz * step
		h.t += DT
		eatAlong(h, length, ax, ay, az, h.x + ux * half, h.y + uy * half, h.z + uz * half)
	end
end

---------------------------------------------------------------------------------
-- Dives
---------------------------------------------------------------------------------
type Dive = {
	level: number, -- smooth level at the start
	levels: number, -- levels banked
	hunting: number, -- seconds from the first bite to a full Haul
	travel: number, -- seconds out to the first bite and home, the hub and the den
	total: number,
	coral: number,
	xpBank: number,
	xpCatch: number,
	worth: number,
	haul: number,
	ate: number,
	fish: number,
	fishKg: number,
}

local function indoor(h: Hunter): number
	local length = Size.length(h.mass)
	return math.min(Size.topSpeed(length) * SPEED * CRUISE, INDOOR)
end

local function dive(h: Hunter, biome: Biome?, limit: number?): Dive
	local start = h.t
	local level = Size.levelAt(h.mass)
	biome = biome or biomeFor(Size.level(h.mass))
	local b = biome :: Biome
	h.haul, h.worth, h.ate, h.firstAte, h.maps, h.fish, h.fishKg = 0, 0, 0, nil, 0, 0, 0
	-- Out: the wash, the plaza and the tunnel toward the biome
	h.t += DEN_OUT + HUB_LEG / indoor(h)
	local best, bestD = tunnels[1], math.huge
	for _, p in tunnels do
		local d = (p[1] - b.ax) ^ 2 + (p[3] - b.az) ^ 2
		if b.id == "KelpShallows" then
			d = rng:NextNumber()
		end
		if d < bestD then
			best, bestD = p, d
		end
	end
	h.x, h.y, h.z = best[1], best[2], best[3]
	local out = h.t
	hunt(h, b, limit or 3600)
	local firstAte = h.firstAte or h.t
	local hunting = h.t - firstAte
	-- Home: the nearest tunnel, the tunnel and the plaza, the portal and the bank
	local length = Size.length(h.rules.live(h.mass, h.haul))
	local _, home = nearestTunnel(h.x, h.y, h.z)
	h.t += home / (Size.topSpeed(length) * SPEED * CRUISE) + HUB_LEG / indoor(h) + DEN_IN + BANK
	local before = h.mass
	local coral = h.rules.coral(h.worth, h.mass)
	h.mass += h.haul
	return {
		level = level,
		levels = Size.levelAt(h.mass) - Size.levelAt(before),
		hunting = hunting,
		travel = (h.t - start) - hunting,
		total = h.t - start,
		coral = coral,
		xpBank = passXp(h.worth),
		xpCatch = h.ate * (PassXp.catch.Normal or 0),
		worth = h.worth,
		haul = h.haul,
		ate = h.ate,
		fish = h.fish,
		fishKg = h.fishKg,
		-- treasure maps: from the prey it ate, and the bank's chance (TreasureService)
		maps = h.maps + (if h.worth >= Drops.bankMinMass then Drops.bank else 0),
		out = firstAte - out,
	} :: any
end

---------------------------------------------------------------------------------
-- Probing: kg eaten a second at each level, and the swim there and back
---------------------------------------------------------------------------------
local PROBE_LEVELS =
	{ 1, 4, 8, 10, 12, 15, 18, 21, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100 }
local DIVES = 6
local function probe(every: boolean)
	print(`PROBE ({species.name}): a hunter at each level, 4 minutes of hunting × 6 dives`)
	print("   LV  biome                 kg/s   ×mass/min  fish/s  out s  home s  fixed s")
	local rows = {}
	for _, level in PROBE_LEVELS do
		local mass = Size.massForLevel(level)
		local kg, secs, n, outs, homes, fixed, fishN, fishKg = 0, 0, 0, 0, 0, 0, 0, 0
		local b = biomeFor(level)
		for k = 1, DIVES do
			local h = newHunter(PROBE, mass)
			h.t = k * 977
			local d = dive(h, b, 240) :: any
			kg += d.worth
			secs += d.hunting
			n += d.ate
			fishN += d.fish
			fishKg += d.fishKg
			outs += d.out
			local _, home = nearestTunnel(h.x, h.y, h.z)
			homes += home / (Size.topSpeed(Size.length(mass)) * SPEED * CRUISE)
			fixed += DEN_OUT + DEN_IN + BANK + 2 * HUB_LEG / indoor(h)
		end
		local rate = kg / math.max(secs, 1e-6)
		table.insert(rows, {
			level = level,
			rate = rate,
			travel = (outs + homes + fixed) / DIVES,
			perFish = fishKg / math.max(fishN, 1), -- kg a prey fish (not filler food)
			fishRate = fishN / math.max(secs, 1e-6), -- prey fish a second
			share = fishKg / math.max(kg, 1e-6), -- of the kg eaten, the prey fish's share
		})
		print(
			string.format(
				"  %3d  %-20s %7.3f  %8.3f  %6.2f  %5.0f  %6.0f  %7.0f",
				level,
				b.id,
				rate,
				rate * 60 / mass,
				n / math.max(secs, 1e-6),
				outs / DIVES,
				homes / DIVES,
				fixed / DIVES
			)
		)
	end
	if not every then
		return rows
	end
	-- Every biome a fish of the level may hunt (its level at least the biome's
	-- lowest): kg eaten a second, so a biome much richer than the one that suits the
	-- level shows (a player would stay there)
	print("\n  kg eaten a second in every biome open to the level (hunting 3 minutes × 3)")
	local names = {}
	for _, b in biomes do
		table.insert(names, string.format("%9s", string.sub(b.id, 1, 9)))
	end
	print("   LV " .. table.concat(names, " "))
	for _, level in PROBE_LEVELS do
		local mass = Size.massForLevel(level)
		local cols = {}
		for _, b in biomes do
			if level < b.def.minLevel then
				table.insert(cols, "        —")
				continue
			end
			local kg, secs = 0, 0
			for k = 1, 3 do
				local h = newHunter(PROBE, mass)
				h.t = k * 1201
				local d = dive(h, b, 180) :: any
				kg += d.worth
				secs += d.hunting
			end
			table.insert(cols, string.format("%9.2f", kg / math.max(secs, 1e-6)))
		end
		print(string.format("  %3d ", level) .. table.concat(cols, " "))
	end
	return rows
end

---------------------------------------------------------------------------------
-- Progression: dive after dive from LV 1 to LV 100
---------------------------------------------------------------------------------
local BANDS = { { 1, 8 }, { 8, 15 }, { 15, 25 }, { 25, 40 }, { 40, 55 }, { 55, 70 }, { 70, 85 }, { 85, 100 } }
local MILESTONES = { 8, 15, 25, 40, 55, 70, 85, 100 }
local TARGET_HOURS: { [number]: string } = {}

local function progress(rules: Rules, maxHours: number)
	local h = newHunter(rules, Size.massForLevel(1))
	local dives: { Dive } = {}
	local reached: { [number]: number } = {}
	while Size.level(h.mass) < 100 and h.t < maxHours * 3600 do
		local d = dive(h)
		table.insert(dives, d)
		for _, m in MILESTONES do
			if reached[m] == nil and Size.level(h.mass) >= m then
				reached[m] = h.t
			end
		end
	end
	print(
		`\n{string.upper(rules.name)}{if stayIn ~= "" then `, STAYING IN {string.upper(stayIn)}` else ""} ({species.name}, {#dives} dives, {string.format(
			"%.1f",
			h.t / 3600
		)} h)`
	)
	print(
		"  band     dives  min/dive  (hunt + swim)  levels/dive  coral/min  XP/min (bank+catch)  Haul kg  fish/dive (eats)  maps/h"
	)
	for _, band in BANDS do
		local n, total, hunting, levels, coral, xpB, xpC, haul, ate, maps, fishN = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
		for _, d in dives do
			if d.level >= band[1] and d.level < band[2] then
				n += 1
				total += d.total
				hunting += d.hunting
				levels += d.levels
				coral += d.coral
				xpB += d.xpBank
				xpC += d.xpCatch
				haul += d.worth
				ate += d.ate
				fishN += d.fish
				maps += (d :: any).maps
			end
		end
		if n == 0 then
			print(string.format("  %3d–%-3d  %5d", band[1], band[2], 0))
			continue
		end
		local minutes = total / 60
		print(
			string.format(
				"  %3d–%-3d  %5d  %7.1f  (%4.1f + %4.1f)  %10.2f  %9.0f  %6.0f (%3.0f + %3.0f)  %7.2f  %6.0f (%4.0f)  %6.1f",
				band[1],
				band[2],
				n,
				minutes / n,
				hunting / 60 / n,
				(total - hunting) / 60 / n,
				levels / n,
				coral / minutes,
				(xpB + xpC) / minutes,
				xpB / minutes,
				xpC / minutes,
				haul / n,
				fishN / n,
				ate / n,
				maps / minutes * 60
			)
		)
	end
	local line = {}
	for _, m in MILESTONES do
		local at = reached[m]
		table.insert(
			line,
			string.format(
				"LV %d %s%s",
				m,
				if at
					then (if at < 3600
						then string.format("%.0f min", at / 60)
						else string.format("%.1f h", at / 3600))
					else "—",
				if TARGET_HOURS[m] then ` ({TARGET_HOURS[m]} h)` else ""
			)
		)
	end
	print("  reached: " .. table.concat(line, " · "))
	return dives, reached
end

---------------------------------------------------------------------------------
-- Designing the curves (MODE=design): from the probe, the pace asked for and how
-- long a full Haul should take to fill, the Haul's cap (levels' worth: the pace ×
-- a dive's minutes) and rate (that cap's kg over the kg eaten in the fill) at each
-- probed level, as Config/Tuning `growth` tables. Then run the progress to check.
---------------------------------------------------------------------------------
-- The Haul by fish (owner, 2026-10-19: "A full haul should take 15-20 fish first
-- time and hold more each time allowing them to level up faster and faster while
-- taking more risk with a larger haul"): how many of the prey a level hunts fill a
-- full Haul, and how many levels a full one banks, both by level
local FISH = { { 1, 18 }, { 6, 24 }, { 11, 35 }, { 16, 50 }, { 25, 90 }, { 40, 150 }, { 55, 220 }, { 70, 300 }, { 85, 380 }, { 100, 440 } }
-- ...and the same levels from every full Haul, the first one too (owner, 2026-10-20:
-- "a full load from lvl one ... sends you to level 8 but then it takes two more full
-- loads to get to level 10 ... the growth is linear. Less than one to one level per
-- load is far too low")
local LEVELS = { { 1, 5 }, { 100, 5 } }
local TUTORIAL_LEVELS = 5 -- a full Haul below LV 4 (Config/Tutorial HAUL_LEVELS)

local function lerpPoints(points: { { number } }, x: number): number
	if x <= points[1][1] then
		return points[1][2]
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if x <= b[1] then
			return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
		end
	end
	return points[#points][2]
end

local function design()
	local rows = probe(false)
	local rates, caps = {}, {}
	print("\n  LV  fish  kg/fish  fill min  cap (levels)  cap kg   Haul kg      rate")
	for _, row in rows do
		local level = row.level
		local mass = Size.massForLevel(level)
		local fishCount = lerpPoints(FISH, level)
		local levels = if level < 4 then TUTORIAL_LEVELS else lerpPoints(LEVELS, level)
		local capKg = mass * (G ^ levels - 1)
		-- The food kg a full Haul holds: that many prey fish, plus the filler food a
		-- hunter picks up alongside (its share of the kg eaten)
		local food = fishCount * row.perFish / math.max(row.share, 0.05)
		local rate = capKg / food
		print(
			string.format(
				"  %3d  %4.0f  %7.3f  %8.2f  %12.2f  %7.3f  %8.2f  %8.5f",
				level,
				fishCount,
				row.perFish,
				fishCount / math.max(row.fishRate, 1e-6) / 60,
				levels,
				capKg,
				food,
				rate
			)
		)
		table.insert(rates, string.format("{ %d, %.3g }", level, food))
		table.insert(caps, string.format("{ %d, %.2f }", level, levels))
	end
	print("\n  food = { " .. table.concat(rates, ", ") .. " },")
	print("  cap = { " .. table.concat(caps, ", ") .. " },")
end

if args.mode == "probe" then
	probe(true)
	return
elseif args.mode == "design" then
	design()
	return
end

print(
	`{NF} prey fish in {NS} schools; {#gX} bits of filler food ({crabCount} crabs); {species.name} at {CRUISE}× top speed`
)
if not args.quick then
	progress(OLD, 3)
	-- The PC's PG1 dives (2026-10-19): a Kelp dive at LV 10 filled in 16 s (+12
	-- levels), a Reef dive at LV 25 in 29 s
	for _, check in { { 10, "KelpShallows" }, { 25, "CoralReef" } } do
		local h = newHunter(OLD, Size.massForLevel(check[1]))
		h.t = 5000
		local b: Biome = biomeFor(check[1])
		for _, bb in biomes do
			if bb.id == check[2] then
				b = bb
			end
		end
		local d = dive(h, b)
		print(
			string.format(
				"  PG1 check, %s at LV %d: Haul full in %.0f s of hunting (%.1f kg, %.0f kg eaten), +%.1f levels",
				check[2],
				check[1],
				d.hunting,
				d.haul,
				d.worth,
				d.levels
			)
		)
	end
end
if args.mode == "old" then
	return
end
local dives, reached = progress(NEW, 40)

-- The checks (the fish the targets are for: a Nibbler moving on with its level): a
-- full Haul of 15–25 fish at first, more each band (within 40% of FISH's middle of
-- the band, which the biome's fish sizes push about), and the levels a bank gives
-- within 10% of the cap (Config/Tuning `growth`)
if species.id ~= "Nibbler" or args.stay ~= "" then
	return
end
local failures = 0
local function check(ok: boolean, text: string)
	if not ok then
		failures += 1
		print("FAIL: " .. text)
	end
end
local lastFish = 0
for _, band in BANDS do
	local n, fishN, levels = 0, 0, 0
	for _, d in dives do
		if d.level >= band[1] and d.level < band[2] then
			n += 1
			fishN += d.fish
			levels += d.levels
		end
	end
	if n == 0 then
		check(false, `LV {band[1]}–{band[2]}: no dives`)
		continue
	end
	local mid = (band[1] + band[2]) / 2
	local perDive = fishN / n
	local want = lerpPoints(FISH, mid)
	if band[1] < 8 then
		check(perDive >= 15 and perDive <= 25, `the tutorial's Haul took {string.format("%.0f", perDive)} fish, not 15–25`)
	else
		check(
			math.abs(perDive - want) <= want * 0.4,
			`LV {band[1]}–{band[2]}: {string.format("%.0f", perDive)} fish a full Haul, not ~{string.format("%.0f", want)}`
		)
		check(perDive >= lastFish * 0.9, `LV {band[1]}–{band[2]}: a full Haul holds fewer fish than the band before`)
		local cap = Size.haulLevels(Size.massForLevel(mid))
		check(
			math.abs(levels / n - cap) <= cap * 0.1,
			`LV {band[1]}–{band[2]}: {string.format("%.2f", levels / n)} levels a bank, not ~{string.format("%.2f", cap)}`
		)
	end
	lastFish = perDive
end
-- No fast lane: a fish that stays in the Open Blue (its tuna) once it may gets to LV 85
-- and 100 no sooner than 5% before one that follows the biomes (Config/Tuning
-- `growth` `overLevel`)
stayIn = "OpenBlue"
local _, stayed = progress(NEW, 40)
for _, level in { 70, 85, 100 } do
	local follow, stay = reached[level], stayed[level]
	check(
		follow ~= nil and stay ~= nil and stay >= follow * 0.95 - (if level == 70 then 0.1 * follow else 0),
		`staying in the Open Blue reaches LV {level} at {if stay
			then string.format("%.1f", stay / 3600)
			else "never"} h, following the biomes {if follow
			then string.format("%.1f", follow / 3600)
			else "never"} h`
	)
end
if failures > 0 then
	error(`progress_sim: {failures} check(s) failed`)
end
print("progress_sim: OK")
