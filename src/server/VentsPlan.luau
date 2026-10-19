--!strict
-- Where the Hydrothermal Vents' landmarks stand (owner, 2026-10-19: "The vents part
-- of the map needs more substance too"). Between the ten basins Shared/Seafloor
-- sinks into the deep floor, the field was plain mud; this lays it out once, at
-- server start, and both builders read it: Shelf.luau turns it into Terrain (the
-- Forge, the smokers' spires, pillow lava, crust and ridges) and Vents.luau dresses
-- it with parts (lava, throats and plumes, basalt columns, terraces, the brine pool,
-- tube worms and mussels).
--
--   * THE FORGE: a volcano 140–176 studs tall with a glowing crater lake, lava
--     runnels down its flanks and a tall ash column: the biome's destination. A
--     basalt CAUSEWAY of hex columns runs from its foot toward the hub.
--   * Three BLACK-SMOKER complexes: clustered spires 40–140 tall with flanges and a
--     throat on every spire.
--   * Two COLUMNAR BASALT outcrops stepping down in terraces.
--   * Two MINERAL TERRACE cascades down basin walls and a BRINE POOL on a basin floor.
--   * PILLOW LAVA mounds, CRACKED CRUST patches and low BASALT RIDGES over the floor.
--
-- Every spot is found here at run time, not fixed: the basins, the chimneys and the
-- prey schools all come from seeded Random sequences (Roblox's in the game, an LCG in
-- the cloud previews), so a fixed spot could land in a basin or under a school.
-- Prey schools are lifted over the real ground along their loops (Shared/Schools
-- `settle`): a spire under a loop would carry its school up its side. So every solid
-- thing keeps under `ceiling` (the lowest a school's fish come over it, less a
-- clearance), and the Forge's site is the one whose cone fits under every loop.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Schools = require(ReplicatedStorage.Shared.Schools)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)

local World = Config.World
local deep = World.deep

local VentsPlan = {}

export type Chimney = { position: Vector3, height: number, radius: number }
export type Spire = {
	foot: Vector3, -- its middle on the floor
	height: number,
	radius: number, -- at its foot
	tilt: Vector3, -- its axis (unit; nearly up)
	flanges: { number }, -- heights of its flanges over its foot
}
export type Smoker = { center: Vector3, radius: number, inBasin: boolean, spires: { Spire } }
export type Forge = {
	center: Vector3, -- its middle on the deep floor
	base: number, -- its radius at the foot
	height: number, -- its summit over the deep floor
	rim: number, -- the summit's radius (the crater's rim)
	crater: number, -- the crater bowl's radius
	runnels: { number }, -- the lava runnels' headings (radians from +X toward +Z)
	-- A parasitic cone on its lower flank, breaking the silhouette: its middle on the
	-- deep floor, its foot's radius, its summit over the floor and its crater's radius
	shoulder: { center: Vector3, base: number, height: number, crater: number }?,
}
export type Column = {
	at: Vector3, -- its middle on the floor (nominal)
	height: number,
	size: number, -- the hexagon's corner radius
	yaw: number,
	group: string, -- "causeway" or "outcrop<n>"
}
export type Outcrop = { center: Vector3, radius: number, down: Vector3 } -- (`down`: its low side)
export type Terrace = { basin: number, heading: number }
export type Brine = { center: Vector3, radius: number, basin: number }
export type Mound = { center: Vector3, radius: number, height: number }
export type Crust = { center: Vector3, radius: number }
export type Ridge = { cframe: CFrame, size: Vector3 }
-- A Terrain fill op as Cave.luau lists them (the shape Shelf.ops hands over)
export type Op = {
	kind: "ball" | "block" | "cylinder",
	material: Enum.Material,
	center: Vector3,
	radius: number?,
	height: number?,
	size: Vector3?,
	cframe: CFrame?,
}
export type Plan = {
	chimneys: { Chimney },
	forge: Forge?,
	smokers: { Smoker },
	outcrops: { Outcrop },
	columns: { Column },
	causeway: { from: Vector3, to: Vector3 }?,
	terraces: { Terrace },
	brine: Brine?,
	mounds: { Mound },
	crusts: { Crust },
	ridges: { Ridge },
	glows: { Vector3 }, -- the crust patches that get a light
	-- The Terrain ops Shelf.luau added for the field: ops[opsFrom .. opsTo]
	opsFrom: number,
	opsTo: number,
	notes: { string }, -- what didn't fit, for the server's log
}

-- The field's footprint keeps inside these angles (the biome is 125–225, the
-- basins 133–207) and between INNER (off the drop-off's foot, its talus and the
-- Wreck's tumbled debris) and OUTER (inside the map's barrier)
local SECTOR = { 128, 222 }
local INNER = World.shelf.radius + World.shelf.edge + 70
local OUTER = World.boundsRadius - 30
-- Studs a solid top keeps under the lowest fish of any school over it (Schools
-- lifts a fish CLEAR_STUDS 2 plus 0.6 of its length over the ground: both are
-- inside the sampled reach, so this is spare room)
local CLEAR = 4

-- The Forge: its foot's radius, its height, the summit's rim and the crater bowl. The
-- first size whose best site keeps `fits` of its height under every school wins;
-- else the one that stands tallest. SHAPE bends its flank (a flared foot, a steep
-- top), LUMPS is how far its lumps stand proud of that cone.
local FORGE_SIZES = {
	{ base = 104, height = 176, rim = 32, crater = 23 },
	{ base = 92, height = 160, rim = 29, crater = 21 },
	{ base = 80, height = 140, rim = 26, crater = 18 },
}
local FORGE = {
	fits = 0.9,
	shape = 1.35,
	lumps = 10,
	keepBasin = 30, -- studs clear of a basin's wall (its lip rubble stands ~26 off it)
	keepChimney = 16,
	runnels = 3,
	-- Where it would rather stand: the middle of the field (studs of height a degree
	-- and a stud away from it are worth: `swing`, `reach`). The basins leave few gaps
	-- wide enough, so it may stand far out, its foot up to the barrier (the map edge's
	-- haze, OceanController EDGE_RAMP, then hides the barrier behind it).
	angle = 170,
	radius = 1220,
	swing = 1.5,
	reach = 0.25,
}
-- The shoulder cone: its middle `out` of the Forge's foot radius from its middle, its
-- foot `base` of it, `height` of the Forge's, and it must stand `proud` studs over
-- the flank there
local SHOULDER = {
	out = 0.8,
	base = 0.34,
	height = 0.48,
	proud = 14,
	rim = 0.3,
	crater = 0.2,
	facing = math.rad(110), -- (off the hub's way: the far side)
	back = 40,
}
-- The smoker complexes, tallest first: their tallest spire, how many spires and the
-- radius they stand in
local SMOKERS = {
	{ height = 140, spires = 5, radius = 34 },
	{ height = 104, spires = 4, radius = 30 },
	{ height = 78, spires = 4, radius = 26 },
}
local SMOKER = { least = 0.55, apart = 190, keepForge = 50, keepChimney = 10 }
-- The columnar basalt outcrops: their tallest column and radius
local OUTCROPS = {
	{ height = 32, radius = 22 },
	{ height = 26, radius = 19 },
}
-- (`edge`: studs inside the barrier their whole footprint keeps, out of the map
-- edge's haze; `swing`: how far their low side may turn off the hub's way)
local OUTCROP = { least = 14, apart = 180, size = 3.4, edge = 120, swing = 0.6 }
-- The causeway: from the Forge's foot toward the hub
local CAUSEWAY = { length = 150, high = 13, low = 4, rows = 5.4, size = 3.3 }
-- Scattered Terrain: pillow-lava mound clusters, cracked crust patches, basalt ridges
local SCATTER = { mounds = 24, crusts = 34, ridges = 12, glows = 2 }

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function point(angleDeg: number, r: number, y: number): Vector3
	local a = math.rad(angleDeg)
	return World.hub.center + Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
end

-- Whether a disc of `radius` round (x, z) lies inside the field's sector and band
local function inField(x: number, z: number, radius: number): boolean
	local r, angle = Seafloor.polar(x, z)
	if r - radius < INNER or r + radius > OUTER then
		return false
	end
	local half = math.deg(radius / math.max(r, 1))
	return Seafloor.inSector(angle, SECTOR[1] + half, SECTOR[2] - half)
end

-- ---------------------------------------------------------------------------
-- The prey schools over the field
-- ---------------------------------------------------------------------------

type Sample = { x: number, z: number, low: number, reach: number }
local BIN = 32
local LOOP_SAMPLES = 64
local bins: { [number]: { Sample } }? = nil
local maxReach = 0

local function binKey(bx: number, bz: number): number
	return (bx + 1000) * 4096 + (bz + 1000)
end

-- Every school whose loop comes near the field, sampled round its loop: where it is,
-- how far its fish reach from the loop (offset, body and wobble) and the lowest any
-- of them comes there (less CLEAR)
local function schoolBins(): { [number]: { Sample } }
	local known = bins
	if known then
		return known
	end
	local made: { [number]: { Sample } } = {}
	for _, school in Schools.list do
		local r, angle = Seafloor.polar(school.center.X, school.center.Z)
		if r < INNER - 260 or not Seafloor.inSector(angle, SECTOR[1] - 24, SECTOR[2] + 24) then
			continue
		end
		local reach = 0
		for i = school.first, school.first + school.count - 1 do
			local f = Schools.fish[i]
			reach = math.max(reach, f.offset.Magnitude + f.length * 1.3)
		end
		maxReach = math.max(maxReach, reach)
		for k = 0, LOOP_SAMPLES - 1 do
			local a = k / LOOP_SAMPLES * 2 * math.pi
			local x = school.center.X + math.cos(a) * school.radius
			local z = school.center.Z + math.sin(a) * school.radius * school.ellipse
			local y = school.center.Y + math.sin(2 * a + school.phase) * school.height
			local key = binKey(math.floor(x / BIN), math.floor(z / BIN))
			local list = made[key]
			if list == nil then
				list = {}
				made[key] = list
			end
			table.insert(list, { x = x, z = z, low = y - reach - CLEAR, reach = reach })
		end
	end
	bins = made
	return made
end

-- Calls `visit` with every sample whose fish come within `radius` of (x, z) and how
-- far its loop is from (x, z)
local function nearSamples(x: number, z: number, radius: number, visit: (Sample, number) -> ())
	local made = schoolBins()
	local span = radius + maxReach
	for bx = math.floor((x - span) / BIN), math.floor((x + span) / BIN) do
		for bz = math.floor((z - span) / BIN), math.floor((z + span) / BIN) do
			local list = made[binKey(bx, bz)]
			if list == nil then
				continue
			end
			for _, s in list do
				local d = math.sqrt((s.x - x) ^ 2 + (s.z - z) ^ 2)
				if d <= radius + s.reach then
					visit(s, d)
				end
			end
		end
	end
end

-- The highest a solid top may stand anywhere within `radius` of (x, z) without a
-- prey school being lifted over it (a world height; math.huge where none swims)
function VentsPlan.ceiling(x: number, z: number, radius: number): number
	local lowest = math.huge
	nearSamples(x, z, radius, function(s: Sample)
		lowest = math.min(lowest, s.low)
	end)
	return lowest
end

-- ---------------------------------------------------------------------------
-- The Forge's shape
-- ---------------------------------------------------------------------------

-- The Forge's radius at `t` of its height (0 = foot, 1 = summit)
function VentsPlan.forgeRadius(forge: Forge, t: number): number
	local u = math.clamp(1 - t, 0, 1)
	return forge.rim + (forge.base - forge.rim) * u ^ FORGE.shape
end

-- How high (0..1 of its height) the Forge's flank stands `d` studs from its middle
local function forgeRise(base: number, rim: number, d: number): number
	if d <= rim then
		return 1
	end
	if d >= base then
		return 0
	end
	return 1 - ((d - rim) / (base - rim)) ^ (1 / FORGE.shape)
end

-- A point on a lava runnel `t` of the way up the flank (0 = foot), on the cone's
-- surface (lumps aside): it meanders a little either side of its heading
function VentsPlan.runnelPoint(forge: Forge, heading: number, t: number): Vector3
	local wander = heading + 0.1 * math.sin(7 * t + heading * 3) + 0.05 * math.sin(17 * t)
	local r = VentsPlan.forgeRadius(forge, t)
	return forge.center + Vector3.new(math.cos(wander) * r, forge.height * t, math.sin(wander) * r)
end

-- The tallest a Forge `base` round may stand at (x, z) under the schools' loops
local function forgeRoom(x: number, z: number, size: { base: number, rim: number }): number
	local room = math.huge
	nearSamples(x, z, size.base + FORGE.lumps, function(s: Sample, d: number)
		local rise = forgeRise(size.base + FORGE.lumps, size.rim, math.max(d - s.reach, 0))
		if rise > 0 then
			room = math.min(room, (s.low - deep.floorY - FORGE.lumps) / rise)
		end
	end)
	return room
end

-- ---------------------------------------------------------------------------
-- Keeping things apart
-- ---------------------------------------------------------------------------

type Taken = { center: Vector3, radius: number }

-- Rock other builders laid in the field (the drop-off's talus, the Wreck's tumbled
-- debris, the basins' lip rubble, the chimneys): set by VentsPlan.make
local obstacles: { Taken } = {}

local function clearOf(list: { Taken }, x: number, z: number, radius: number, gap: number): boolean
	local here = Vector3.new(x, 0, z)
	for _, taken in list do
		if flatDistance(taken.center, here) < taken.radius + radius + gap then
			return false
		end
	end
	return true
end

-- Whether a disc keeps `gap` clear of the rock already laid
local function clearOfRock(x: number, z: number, radius: number, gap: number): boolean
	return clearOf(obstacles, x, z, radius, gap)
end

-- The rock already standing proud of the deep floor in and round the field: every
-- fill op that isn't a carve or the mud slab, under 70 studs round
local function obstaclesIn(ops: { Op }): { Taken }
	local found: { Taken } = {}
	for _, op in ops do
		local material = op.material
		if material == Enum.Material.Air or material == Enum.Material.Mud then
			continue
		end
		local c = op.center
		local reach, top
		local radius = op.radius or 0
		if op.kind == "ball" then
			reach, top = radius, c.Y + radius
		elseif op.kind == "cylinder" then
			local frame = op.cframe
			local up = if frame then math.abs(frame.UpVector.Y) else 1
			local side = math.sqrt(math.max(1 - up * up, 0))
			local half = (op.height or 0) / 2
			reach, top = radius + half * side, c.Y + half * up + radius * side
		else
			local size = op.size or Vector3.zero
			reach, top = size.Magnitude / 2, c.Y + size.Magnitude / 2
		end
		if reach > 70 or top < deep.floorY + 1.5 then
			continue
		end
		local r, angle = Seafloor.polar(c.X, c.Z)
		if r < INNER - 120 or r > OUTER + 120 then
			continue
		end
		if not Seafloor.inSector(angle, SECTOR[1] - 12, SECTOR[2] + 12) then
			continue
		end
		table.insert(found, { center = Vector3.new(c.X, 0, c.Z), radius = reach })
	end
	return found
end

-- Whether a disc lies wholly outside every basin (`gap` clear of its wall)
local function outsideBasins(x: number, z: number, radius: number, gap: number): boolean
	for _, basin in Seafloor.ventBasins() do
		local d = math.sqrt((x - basin.x) ^ 2 + (z - basin.z) ^ 2)
		if d < basin.radius + radius + gap then
			return false
		end
	end
	return true
end

-- The basin a disc lies wholly inside (`gap` clear of its wall), or nil. A disc that
-- straddles any basin's wall answers false as well.
local function basinOf(x: number, z: number, radius: number, gap: number): (number?, boolean)
	local inside: number? = nil
	for index, basin in Seafloor.ventBasins() do
		local d = math.sqrt((x - basin.x) ^ 2 + (z - basin.z) ^ 2)
		if d + radius <= basin.radius - gap then
			inside = inside or index
		elseif d < basin.radius + radius + gap then
			return nil, false
		end
	end
	return inside, true
end

local function chimneysClear(chimneys: { Chimney }, x: number, z: number, radius: number): boolean
	for _, chimney in chimneys do
		local p = chimney.position
		if (p.X - x) ^ 2 + (p.Z - z) ^ 2 < radius * radius then
			return false
		end
	end
	return true
end

-- The shortest distance from (x, z) to the segment a-b, flat
local function segmentDistance(x: number, z: number, a: Vector3, b: Vector3): number
	local abx, abz = b.X - a.X, b.Z - a.Z
	local length2 = abx * abx + abz * abz
	local t = if length2 > 0 then math.clamp(((x - a.X) * abx + (z - a.Z) * abz) / length2, 0, 1) else 0
	local px, pz = a.X + abx * t, a.Z + abz * t
	return math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
end

-- ---------------------------------------------------------------------------
-- The plan
-- ---------------------------------------------------------------------------

local function placeForge(plan: Plan, taken: { Taken })
	local best: Forge? = nil
	local bestRoom = -math.huge
	for _, size in FORGE_SIZES do
		local site: Vector3? = nil
		local siteRoom, siteScore = 0, -math.huge
		for angle = SECTOR[1], SECTOR[2], 1.5 do
			for r = INNER + size.base, World.boundsRadius - size.base, 8 do
				local p = point(angle, r, deep.floorY)
				local half = math.deg(size.base / r)
				if not Seafloor.inSector(angle, SECTOR[1] + half, SECTOR[2] - half) then
					continue
				end
				if not outsideBasins(p.X, p.Z, size.base, FORGE.keepBasin) then
					continue
				end
				if not chimneysClear(plan.chimneys, p.X, p.Z, size.base + FORGE.keepChimney) then
					continue
				end
				local room = math.min(forgeRoom(p.X, p.Z, size), size.height)
				local away = math.abs(angle - FORGE.angle) * FORGE.swing
					+ math.abs(r - FORGE.radius) * FORGE.reach
				local score = room * 4 - away
				if score > siteScore then
					site, siteRoom, siteScore = p, room, score
				end
			end
		end
		if site and siteRoom > bestRoom then
			bestRoom = siteRoom
			best = {
				center = site,
				base = size.base,
				height = math.floor(siteRoom),
				rim = size.rim,
				crater = size.crater,
				runnels = {},
			}
		end
		if site and siteRoom >= size.height * FORGE.fits then
			break
		end
	end
	local forge = best
	if forge == nil then
		table.insert(plan.notes, "no room for the Forge")
		return
	end
	if forge.height < FORGE_SIZES[#FORGE_SIZES].height * FORGE.fits then
		table.insert(plan.notes, `the Forge stands only {forge.height} studs (prey schools over every site)`)
	end
	-- Runnels round the flank, the first toward the hub (the side a fish arrives on)
	local toward = math.atan2(-forge.center.Z, -forge.center.X)
	for k = 0, FORGE.runnels - 1 do
		table.insert(forge.runnels, toward + 0.35 + k * 2 * math.pi / FORGE.runnels)
	end
	-- The shoulder: low on the flank between two runnels, where it stands tallest
	-- clear of the flank and under every school (none if nowhere does), on a side a
	-- fish from the hub sees if it can (`back`: studs of height the far side costs)
	local best: { center: Vector3, base: number, height: number, crater: number }? = nil
	local bestScore = -math.huge
	local runnels = forge.runnels
	for k, a in runnels do
		local b = runnels[k % #runnels + 1]
		local middle = a + ((b - a) % (2 * math.pi)) / 2
		for _, swing in { 0, -0.3, 0.3 } do
			local heading = middle + swing
			local d = forge.base * SHOULDER.out
			local center = forge.center + Vector3.new(math.cos(heading) * d, 0, math.sin(heading) * d)
			local base = forge.base * SHOULDER.base
			local flank = forge.height * forgeRise(forge.base, forge.rim, d)
			local room = forgeRoom(center.X, center.Z, { base = base, rim = base * SHOULDER.rim })
			local height = math.floor(math.min(forge.height * SHOULDER.height, room))
			local away = math.abs((heading - toward + math.pi) % (2 * math.pi) - math.pi)
			local score = height - (if away > SHOULDER.facing then SHOULDER.back else 0)
			if height >= flank + SHOULDER.proud and score > bestScore then
				best = { center = center, base = base, height = height, crater = base * SHOULDER.crater }
				bestScore = score
			end
		end
	end
	forge.shoulder = best
	if best == nil then
		table.insert(plan.notes, "no room for the Forge's shoulder cone")
	end
	plan.forge = forge
	local reach = forge.base
	local shoulder = forge.shoulder
	if shoulder then
		reach = math.max(reach, flatDistance(shoulder.center, forge.center) + shoulder.base)
	end
	table.insert(taken, { center = forge.center, radius = reach })
end

local function placeSmokers(plan: Plan, taken: { Taken }, rng: Random)
	local placed: { Taken } = {}
	local anyInBasin = false
	for index, want in SMOKERS do
		local best: Vector3? = nil
		local bestHeight, bestScore, bestBasin = 0, -math.huge, false
		for angle = SECTOR[1], SECTOR[2], 2 do
			for r = INNER + want.radius, OUTER - want.radius, 12 do
				local p = point(angle, r, 0)
				if not inField(p.X, p.Z, want.radius) then
					continue
				end
				if not clearOf(taken, p.X, p.Z, want.radius, SMOKER.keepForge) then
					continue
				end
				if not clearOf(placed, p.X, p.Z, 0, SMOKER.apart) then
					continue
				end
				if not clearOfRock(p.X, p.Z, want.radius, 6) then
					continue
				end
				if not chimneysClear(plan.chimneys, p.X, p.Z, want.radius + SMOKER.keepChimney) then
					continue
				end
				local basin, clean = basinOf(p.X, p.Z, want.radius, 14)
				if not clean then
					continue
				end
				local floor = if basin then deep.ventsFloorY else deep.floorY
				local room = VentsPlan.ceiling(p.X, p.Z, want.radius + 4) - floor
				local height = math.min(want.height, room)
				if height < want.height * SMOKER.least or height < 36 then
					continue
				end
				local spacing = math.huge
				for _, other in taken do
					spacing = math.min(spacing, flatDistance(other.center, p) - other.radius)
				end
				for _, other in placed do
					spacing = math.min(spacing, flatDistance(other.center, p))
				end
				local score = height * 3
					+ math.min(spacing, 500) * 0.25
					+ (if basin and not anyInBasin then 40 else 0)
				if score > bestScore then
					best, bestHeight, bestScore, bestBasin =
						Vector3.new(p.X, floor, p.Z), height, score, basin ~= nil
				end
			end
		end
		local center = best
		if center == nil then
			table.insert(plan.notes, `no room for smoker complex {index}`)
			continue
		end
		anyInBasin = anyInBasin or bestBasin
		local smoker: Smoker = { center = center, radius = want.radius, inBasin = bestBasin, spires = {} }
		local turn = rng:NextNumber(0, 2 * math.pi)
		for k = 1, want.spires do
			local core = k == 1
			local foot = center
			local height = math.floor(bestHeight)
			local radius = 9 + bestHeight / 28
			if not core then
				local a = turn + (k - 2) * 2 * math.pi / (want.spires - 1) + rng:NextNumber(-0.3, 0.3)
				radius = rng:NextNumber(5.5, 8)
				local d = rng:NextNumber(13, want.radius - radius - 2)
				foot = center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
				height = math.floor(bestHeight * rng:NextNumber(0.34, 0.68))
			end
			local lean = if core then 0 else rng:NextNumber(0.02, 0.1)
			local leanTurn = rng:NextNumber(0, 2 * math.pi)
			local tilt = Vector3.new(
				math.sin(lean) * math.cos(leanTurn),
				math.cos(lean),
				math.sin(lean) * math.sin(leanTurn)
			)
			local flanges = {}
			for f = 1, if core then 3 else rng:NextInteger(1, 2) do
				local at = if core then ({ 0.36, 0.6, 0.8 })[f] else rng:NextNumber(0.4, 0.75)
				table.insert(flanges, math.floor(height * at))
			end
			table.insert(smoker.spires, {
				foot = foot,
				height = height,
				radius = radius,
				tilt = tilt.Unit,
				flanges = flanges,
			})
		end
		table.insert(plan.smokers, smoker)
		table.insert(placed, { center = center, radius = 0 })
		table.insert(taken, { center = center, radius = want.radius })
	end
end

-- The causeway: rows of hex columns from the Forge's foot toward the hub, stepping
-- down as it goes; broken where a basin, a chimney or another landmark is in the way
local function placeCauseway(plan: Plan, taken: { Taken }, rng: Random)
	local forge = plan.forge
	if forge == nil then
		return
	end
	local c = forge.center
	local toward = Vector3.new(-c.X, 0, -c.Z).Unit
	local across = Vector3.new(-toward.Z, 0, toward.X)
	local from = c + toward * (forge.base + 8)
	local to = from + toward * CAUSEWAY.length
	plan.causeway = { from = from, to = to }
	local size = CAUSEWAY.size
	local step = size * math.sqrt(3) + 0.3
	local rows = math.floor(CAUSEWAY.length / CAUSEWAY.rows)
	local others: { Taken } = {}
	for _, t in taken do
		if t.center ~= c then
			table.insert(others, t)
		end
	end
	for row = 0, rows do
		local along = row / rows
		local base = CAUSEWAY.high + (CAUSEWAY.low - CAUSEWAY.high) * along
		-- Stepped every three rows, so it reads as terraces down toward the hub
		local tier = math.floor(row / 3) / math.max(math.floor(rows / 3), 1)
		local stepped = CAUSEWAY.high + (CAUSEWAY.low - CAUSEWAY.high) * tier
		local shift = if row % 2 == 0 then 0 else step / 2
		for k = -1, 1 do
			if row % 2 == 1 and k == 1 then
				continue
			end
			local p = from + toward * (row * CAUSEWAY.rows) + across * (k * step + shift)
			if not inField(p.X, p.Z, size) then
				continue
			end
			if
				not outsideBasins(p.X, p.Z, size, 10) or not chimneysClear(plan.chimneys, p.X, p.Z, size + 12)
			then
				continue
			end
			if not clearOf(others, p.X, p.Z, size, 6) or not clearOfRock(p.X, p.Z, size, 1) then
				continue
			end
			local height = (stepped * 0.7 + base * 0.3) + rng:NextNumber(-1.2, 1.2)
			-- (the outer columns a little lower: a crowned road)
			height -= math.abs(k * step + shift) * 0.12
			local room = VentsPlan.ceiling(p.X, p.Z, size + 1) - deep.floorY
			height = math.min(height, room)
			if height < 2.5 then
				continue
			end
			table.insert(plan.columns, {
				at = Vector3.new(p.X, deep.floorY, p.Z),
				height = height,
				size = size,
				yaw = math.atan2(toward.Z, toward.X) + math.pi / 6, -- (flat to flat across it)
				group = "causeway",
			})
		end
	end
end

-- The outcrops: hex columns packed tight, stepping down in terraces across them
local function placeOutcrops(plan: Plan, taken: { Taken }, rng: Random)
	local placed: { Taken } = {}
	for index, want in OUTCROPS do
		local best: Vector3? = nil
		local bestHeight, bestScore = 0, -math.huge
		for angle = SECTOR[1], SECTOR[2], 2 do
			for r = INNER + want.radius, World.boundsRadius - OUTCROP.edge - want.radius, 10 do
				local p = point(angle, r, deep.floorY)
				if not inField(p.X, p.Z, want.radius) then
					continue
				end
				if not outsideBasins(p.X, p.Z, want.radius, 16) then
					continue
				end
				if
					not clearOf(taken, p.X, p.Z, want.radius, 30)
					or not clearOf(placed, p.X, p.Z, 0, OUTCROP.apart)
					or not clearOfRock(p.X, p.Z, want.radius, 8)
				then
					continue
				end
				if not chimneysClear(plan.chimneys, p.X, p.Z, want.radius + 10) then
					continue
				end
				local causeway = plan.causeway
				if causeway and segmentDistance(p.X, p.Z, causeway.from, causeway.to) < want.radius + 24 then
					continue
				end
				local height = math.min(want.height, VentsPlan.ceiling(p.X, p.Z, want.radius) - deep.floorY)
				if height < OUTCROP.least then
					continue
				end
				local spacing = math.huge
				for _, other in taken do
					spacing = math.min(spacing, flatDistance(other.center, p) - other.radius)
				end
				for _, other in placed do
					spacing = math.min(spacing, flatDistance(other.center, p))
				end
				local score = height * 4 + math.min(spacing, 400) * 0.2
				if score > bestScore then
					best, bestHeight, bestScore = p, height, score
				end
			end
		end
		local center = best
		if center == nil then
			table.insert(plan.notes, `no room for basalt outcrop {index}`)
			continue
		end
		-- Packed on a hex grid; terraces step down across it along `down`, its low side
		-- toward the hub, so a fish arriving sees it climb away like a stair
		local size = OUTCROP.size
		local spacing = size * math.sqrt(3) + 0.25
		local yaw = rng:NextNumber(0, math.pi / 3)
		local axisA = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
		local axisB = Vector3.new(math.cos(yaw + math.pi / 3), 0, math.sin(yaw + math.pi / 3))
		local downAngle = math.atan2(World.hub.center.Z - center.Z, World.hub.center.X - center.X)
			+ rng:NextNumber(-OUTCROP.swing, OUTCROP.swing)
		local down = Vector3.new(math.cos(downAngle), 0, math.sin(downAngle))
		table.insert(plan.outcrops, { center = center, radius = want.radius, down = down })
		table.insert(placed, { center = center, radius = 0 })
		table.insert(taken, { center = center, radius = want.radius })
		local count = math.ceil(want.radius / spacing) + 1
		for i = -count, count do
			for j = -count, count do
				local offset = axisA * (i * spacing) + axisB * (j * spacing)
				local d = offset.Magnitude
				-- A ragged edge: the outer ring thins out
				if
					d > want.radius
					or (d > want.radius * 0.7 and rng:NextNumber() < (d / want.radius - 0.7) * 2.2)
				then
					continue
				end
				local along = offset:Dot(down) / want.radius -- -1 (high side) .. 1
				local tier = math.clamp(math.floor((along + 1) * 2.4), 0, 4)
				local height = bestHeight * (1 - tier * 0.19) + rng:NextNumber(-1.5, 1.5)
				-- A few broken stumps
				if rng:NextNumber() < 0.08 then
					height *= rng:NextNumber(0.35, 0.65)
				end
				local p = center + offset
				height = math.min(height, VentsPlan.ceiling(p.X, p.Z, size + 1) - deep.floorY)
				if height < 2.5 then
					continue
				end
				table.insert(plan.columns, {
					at = p,
					height = height,
					size = size,
					yaw = yaw,
					group = `outcrop{index}`,
				})
			end
		end
	end
end

-- Mineral terraces: two cascades down basin walls, on the side facing the hub where
-- the wall is clear
local function placeTerraces(plan: Plan, taken: { Taken })
	local basins = Seafloor.ventBasins()
	local order = {}
	for index in basins do
		table.insert(order, index)
	end
	table.sort(order, function(a, b)
		return basins[a].radius > basins[b].radius
	end)
	local used: { [number]: boolean } = {}
	if plan.brine then
		used[plan.brine.basin] = true
	end
	for _, index in order do
		if #plan.terraces >= 2 then
			break
		end
		if used[index] then
			continue
		end
		local basin = basins[index]
		local outwardHeading = math.atan2(basin.z - World.hub.center.Z, basin.x - World.hub.center.X)
		-- Facing the hub: the basin's far wall, seen by a fish coming from the drop-off
		for _, swing in { 0, 0.35, -0.35, 0.7, -0.7, 1.05, -1.05, 1.4, -1.4 } do
			local heading = outwardHeading + swing
			local wall = Vector3.new(
				basin.x + math.cos(heading) * basin.radius,
				0,
				basin.z + math.sin(heading) * basin.radius
			)
			if not inField(wall.X, wall.Z, 14) then
				continue
			end
			local alone = true
			for other, b in basins do
				if other ~= index and math.sqrt((wall.X - b.x) ^ 2 + (wall.Z - b.z) ^ 2) < b.radius + 16 then
					alone = false
				end
			end
			if not alone or not chimneysClear(plan.chimneys, wall.X, wall.Z, 30) then
				continue
			end
			if not clearOf(taken, wall.X, wall.Z, 14, 12) then
				continue
			end
			table.insert(plan.terraces, { basin = index, heading = heading })
			used[index] = true
			break
		end
	end
end

-- The brine pool: on the floor of the biggest basin with room, clear of its chimneys
local function placeBrine(plan: Plan, taken: { Taken })
	local basins = Seafloor.ventBasins()
	local order = {}
	for index in basins do
		table.insert(order, index)
	end
	table.sort(order, function(a, b)
		return basins[a].radius > basins[b].radius
	end)
	for _, index in order do
		local basin = basins[index]
		local radius = math.clamp(basin.radius * 0.34, 22, 38)
		local best: Vector3? = nil
		local bestClear = -math.huge
		for _, rho in { 0, 0.2, 0.35, 0.5 } do
			for k = 0, 7 do
				local a = k * math.pi / 4
				local x = basin.x + math.cos(a) * basin.radius * rho
				local z = basin.z + math.sin(a) * basin.radius * rho
				if math.sqrt((x - basin.x) ^ 2 + (z - basin.z) ^ 2) + radius > basin.radius - 14 then
					continue
				end
				if not clearOf(taken, x, z, radius, 10) then
					continue
				end
				local nearest = math.huge
				for _, chimney in plan.chimneys do
					local p = chimney.position
					nearest = math.min(nearest, math.sqrt((p.X - x) ^ 2 + (p.Z - z) ^ 2))
				end
				if nearest < radius + 14 then
					continue
				end
				if nearest > bestClear then
					best, bestClear = Vector3.new(x, deep.ventsFloorY, z), nearest
				end
			end
		end
		if best then
			plan.brine = { center = best, radius = radius, basin = index }
			table.insert(taken, { center = best, radius = radius + 6 })
			return
		end
	end
	table.insert(plan.notes, "no basin floor with room for the brine pool")
end

-- A spot on the field's deep floor (or, `inBasin`, on a basin's floor) for something
-- `radius` round, clear of the landmarks; nil after a few misses
local function scatterSpot(
	plan: Plan,
	taken: { Taken },
	rng: Random,
	radius: number,
	inBasin: boolean
): Vector3?
	for _ = 1, 12 do
		local angle = rng:NextNumber(SECTOR[1], SECTOR[2])
		local r = rng:NextNumber(INNER + radius, OUTER - radius)
		local p = point(angle, r, 0)
		if not inField(p.X, p.Z, radius) then
			continue
		end
		local basin, clean = basinOf(p.X, p.Z, radius, 10)
		if not clean or (basin ~= nil) ~= inBasin then
			continue
		end
		if
			not clearOf(taken, p.X, p.Z, radius, 8)
			or not chimneysClear(plan.chimneys, p.X, p.Z, radius + 12)
			or not clearOfRock(p.X, p.Z, radius, 4)
		then
			continue
		end
		local causeway = plan.causeway
		if causeway and segmentDistance(p.X, p.Z, causeway.from, causeway.to) < radius + 14 then
			continue
		end
		return Vector3.new(p.X, if basin then deep.ventsFloorY else deep.floorY, p.Z)
	end
	return nil
end

local function placeScatter(plan: Plan, taken: { Taken }, rng: Random)
	-- Basalt ridges first (long and low), then pillow-lava mounds, then crust (flush:
	-- nothing stands on it, so it may lie by the others)
	for _ = 1, SCATTER.ridges do
		local length = rng:NextNumber(50, 100)
		local center = scatterSpot(plan, taken, rng, length / 2, false)
		if center == nil then
			continue
		end
		local room = VentsPlan.ceiling(center.X, center.Z, length / 2 + 6) - deep.floorY
		local height = math.min(rng:NextNumber(10, 16), room / 0.7)
		if height < 6 then
			continue
		end
		local size = Vector3.new(length, height, rng:NextNumber(14, 24))
		table.insert(plan.ridges, {
			cframe = CFrame.new(center + Vector3.new(0, height * 0.15, 0))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			size = size,
		})
		table.insert(taken, { center = center, radius = length * 0.4 })
	end
	for _ = 1, SCATTER.mounds do
		local radius = rng:NextNumber(10, 16)
		local center = scatterSpot(plan, taken, rng, radius, false)
		if center == nil then
			continue
		end
		local height =
			math.min(rng:NextNumber(9, 15), VentsPlan.ceiling(center.X, center.Z, radius + 4) - center.Y)
		if height < 5 then
			continue
		end
		table.insert(plan.mounds, { center = center, radius = radius, height = height })
		table.insert(taken, { center = center, radius = radius })
	end
	local deepCrusts: { Crust } = {}
	for k = 1, SCATTER.crusts do
		local radius = rng:NextNumber(9, 24)
		local inBasin = k % 4 == 0
		local center = scatterSpot(plan, {}, rng, radius, inBasin)
		if center == nil then
			continue
		end
		-- (crust is flush with the floor: only the landmarks and the brine pool keep it off)
		local blocked = false
		local forge = plan.forge
		if forge and flatDistance(forge.center, center) < forge.base + radius * 0.3 then
			blocked = true
		end
		for _, smoker in plan.smokers do
			if flatDistance(smoker.center, center) < smoker.radius + radius + 4 then
				blocked = true
			end
		end
		local brine = plan.brine
		if brine and flatDistance(brine.center, center) < brine.radius + radius + 10 then
			blocked = true
		end
		if blocked then
			continue
		end
		local crust = { center = center, radius = radius }
		table.insert(plan.crusts, crust)
		if not inBasin then
			table.insert(deepCrusts, crust)
		end
	end
	table.sort(deepCrusts, function(a, b)
		return a.radius > b.radius
	end)
	for k = 1, math.min(SCATTER.glows, #deepCrusts) do
		table.insert(plan.glows, deepCrusts[k].center)
	end
end

-- Lays the field out round the chimneys Shelf.luau has already placed and clear of
-- the rock in `ops` (the same every start: its own Random)
function VentsPlan.make(chimneys: { Chimney }, ops: { Op }): Plan
	local rng = Random.new(World.seed + 97)
	obstacles = obstaclesIn(ops)
	local plan: Plan = {
		chimneys = chimneys,
		forge = nil,
		smokers = {},
		outcrops = {},
		columns = {},
		causeway = nil,
		terraces = {},
		brine = nil,
		mounds = {},
		crusts = {},
		ridges = {},
		glows = {},
		opsFrom = 0,
		opsTo = -1,
		notes = {},
	}
	local taken: { Taken } = {}
	placeForge(plan, taken)
	placeSmokers(plan, taken, rng)
	placeCauseway(plan, taken, rng)
	placeOutcrops(plan, taken, rng)
	placeBrine(plan, taken)
	placeTerraces(plan, taken)
	placeScatter(plan, taken, rng)
	return plan
end

return VentsPlan
