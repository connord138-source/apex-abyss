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
local G = Tuning.size.levelGrowth
local DT = 0.25
local CRUISE = 0.9
local RETARGET = 1.5
local INDOOR = Tuning.swim.indoorSpeed
local species = Config.Species.byId[args.species]
assert(species, `no species {args.species}`)
local SPEED = species.stats.speed
local rng = Random.new(20261019)

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
local sCx, sCy, sCz, sRad, sEll, sH, sW, sPh, sFirst, sCount, sBound =
	{}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
local fS, fOx, fOy, fOz, fPh, fLen, fRaw, fRad, fMass, fBack = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
for s, school in list do
	sCx[s], sCy[s], sCz[s] = school.center.X, school.center.Y, school.center.Z
	sRad[s], sEll[s], sH[s], sW[s], sPh[s] =
		school.radius, school.ellipse, school.height, school.angularSpeed, school.phase
	sFirst[s], sCount[s] = school.first, school.count
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
end

-- Schools.position, inlined (no lifts: the sim has no Terrain)
local function fishPos(i: number, t: number): (number, number, number)
	local s = fS[i]
	local a = sPh[s] + sW[s] * t
	local r, h, e, w = sRad[s], sH[s], sEll[s], sW[s]
	local ca, sa = math.cos(a), math.sin(a)
	local a2 = 2 * a + sPh[s]
	local px, py, pz = sCx[s] + ca * r, sCy[s] + math.sin(a2) * h, sCz[s] + sa * r * e
	local vx, vy, vz = -sa * r * w, math.cos(a2) * 2 * h * w, ca * r * e * w
	local m = math.sqrt(vx * vx + vy * vy + vz * vz)
	local lx, ly, lz = vx / m, vy / m, vz / m
	local rx, rz = -lz, lx
	local rm = math.sqrt(rx * rx + rz * rz)
	rx, rz = rx / rm, rz / rm
	local ux, uy, uz = -rz * ly, rz * lx - rx * lz, rx * ly
	local p, L = fPh[i], fLen[i]
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
-- over each band's area, on the nominal floor)
local gX, gY, gZ, gMass, gBack = {}, {}, {}, {}, {}
local FCELL = 40
local fcells: { [number]: { number } } = {}
for _, def in ForageConfig.list do
	if def.mass <= 0 then
		continue
	end
	for _, band in def.bands do
		for _ = 1, band.count do
			local r = math.sqrt(rng:NextNumber() * (band.to ^ 2 - band.from ^ 2) + band.from ^ 2)
			local angle = rng:NextNumber() * 2 * math.pi
			local x, z = math.cos(angle) * r, math.sin(angle) * r
			table.insert(gX, x)
			table.insert(gY, Seafloor.y(x, z) + 0.6)
			table.insert(gZ, z)
			table.insert(gMass, def.mass)
			table.insert(gBack, def.respawn)
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

local function biomeFor(level: number): Biome
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
	add: (mass: number, haul: number, raw: number) -> (number, number),
	full: (mass: number, haul: number) -> boolean,
	live: (mass: number, haul: number) -> number,
	coral: (worth: number, mass: number) -> number,
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
	add = function(mass, haul, raw)
		local rate = Size.haulRate(mass)
		local added = math.min(raw * rate, math.max(Size.haulCap(mass) - haul, 0))
		return added, added / rate
	end,
	full = function(mass, haul)
		return Size.isMaxed(mass, haul)
	end,
	live = function(mass, haul)
		return Size.liveMass(mass, haul)
	end,
	coral = function(worth, mass)
		return Size.bankCoral(worth, mass)
	end,
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
	firstAte: number?,
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
		firstAte = nil,
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

local function eat(h: Hunter, raw: number)
	local added, worth = h.rules.add(h.mass, h.haul, raw)
	h.haul += added
	h.worth += worth
	h.ate += 1
	if h.firstAte == nil then
		h.firstAte = h.t
	end
end

-- Swallows everything in reach along the mouth's way from a to b
local function eatAlong(h: Hunter, length: number, ax: number, ay: number, az: number, bx: number, by: number, bz: number)
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
					if segDist(x, y, z, ax, ay, az, bx, by, bz) <= (reachBase + fRad[i]) * Schools.EAT_PULLED then
						h.eatenFish[i] = t + fBack[i]
						eat(h, fMass[i] * Tuning.hunt.preyGain)
					end
				end
			end
		end
	end
	-- Filler food on the floor
	local reach = (Size.reach(length) * FORAGE_REACH + FORAGE_BONUS) * FORAGE_PULLED
	if math.min(ay, by) - Seafloor.y(mx, mz) > reach + 2 then
		return
	end
	for cx = math.floor((mx - half - reach) / FCELL), math.floor((mx + half + reach) / FCELL) do
		for cz = math.floor((mz - half - reach) / FCELL), math.floor((mz + half + reach) / FCELL) do
			local here = fcells[key(cx, cz)]
			if here == nil then
				continue
			end
			for _, g in here do
				if (h.eatenFood[g] or 0) <= t and segDist(gX[g], gY[g], gZ[g], ax, ay, az, bx, by, bz) <= reach then
					h.eatenFood[g] = t + gBack[g]
					eat(h, gMass[g])
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
				if (h.eatenFood[g] or 0) <= t then
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
	h.haul, h.worth, h.ate, h.firstAte = 0, 0, 0, nil
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
		out = firstAte - out,
	} :: any
end

---------------------------------------------------------------------------------
-- Probing: kg eaten a second at each level, and the swim there and back
---------------------------------------------------------------------------------
local PROBE_LEVELS = { 1, 3, 5, 8, 10, 12, 15, 18, 21, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100 }
local function probe()
	print(`PROBE ({species.name}): a hunter at each level, 4 minutes of hunting × 4 dives`)
	print("   LV  biome                 kg/s   ×mass/min  fish/s  out s  home s  fixed s")
	local rows = {}
	for _, level in PROBE_LEVELS do
		local mass = Size.massForLevel(level)
		local kg, secs, n, outs, homes, fixed = 0, 0, 0, 0, 0, 0
		local b = biomeFor(level)
		for k = 1, 4 do
			local h = newHunter(PROBE, mass)
			h.t = k * 977
			local d = dive(h, b, 240) :: any
			kg += d.worth
			secs += d.hunting
			n += d.ate
			outs += d.out
			local _, home = nearestTunnel(h.x, h.y, h.z)
			homes += home / (Size.topSpeed(Size.length(mass)) * SPEED * CRUISE)
			fixed += DEN_OUT + DEN_IN + BANK + 2 * HUB_LEG / indoor(h)
		end
		local rate = kg / math.max(secs, 1e-6)
		table.insert(rows, { level = level, rate = rate, travel = (outs + homes + fixed) / 4 })
		print(
			string.format(
				"  %3d  %-20s %7.3f  %8.3f  %6.2f  %5.0f  %6.0f  %7.0f",
				level,
				b.id,
				rate,
				rate * 60 / mass,
				n / math.max(secs, 1e-6),
				outs / 4,
				homes / 4,
				fixed / 4
			)
		)
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
local TARGET_HOURS = { [15] = "0.5–0.67", [25] = "1.5", [40] = "4", [55] = "7", [70] = "11", [85] = "16", [100] = "22" }

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
	print(`\n{string.upper(rules.name)} ({species.name}, {#dives} dives, {string.format("%.1f", h.t / 3600)} h)`)
	print("  band     dives  min/dive  (hunt + swim)  levels/dive  coral/min  XP/min (bank+catch)  kg/dive  fish/dive")
	for _, band in BANDS do
		local n, total, hunting, levels, coral, xpB, xpC, haul, ate = 0, 0, 0, 0, 0, 0, 0, 0, 0
		for _, d in dives do
			if d.level >= band[1] and d.level < band[2] then
				n += 1
				total += d.total
				hunting += d.hunting
				levels += d.levels
				coral += d.coral
				xpB += d.xpBank
				xpC += d.xpCatch
				haul += d.haul
				ate += d.ate
			end
		end
		if n == 0 then
			print(string.format("  %3d–%-3d  %5d", band[1], band[2], 0))
			continue
		end
		local minutes = total / 60
		print(
			string.format(
				"  %3d–%-3d  %5d  %7.1f  (%4.1f + %4.1f)  %10.2f  %9.0f  %6.0f (%3.0f + %3.0f)  %7.2f  %8.0f",
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
				ate / n
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
				if at then (if at < 3600 then string.format("%.0f min", at / 60) else string.format("%.1f h", at / 3600)) else "—",
				if TARGET_HOURS[m] then ` ({TARGET_HOURS[m]} h)` else ""
			)
		)
	end
	print("  reached: " .. table.concat(line, " · "))
	return dives, reached
end

if args.mode == "probe" then
	probe()
	return
end

print(`{NF} prey fish in {NS} schools; {#gX} bits of filler food; {species.name} at {CRUISE}× top speed`)
if not args.quick then
	local dives = progress(OLD, 3)
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
	local _ = dives
end
if args.mode ~= "old" then progress(NEW, 40) end
