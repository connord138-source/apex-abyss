--!strict
-- The seafloor as Roblox Terrain (owner, 2026-10-07: the old trench was "a giant
-- gaping hole", the map "far too open", and biomes must sit at different depths off
-- an ocean shelf; 2026-10-08: "the entirety of the map is still too small ... each
-- biome made larger ... MUCH MUCH more depth", "the lower areas are far too
-- underdeveloped", "coral reef needs more larger rock structures and arches to go
-- under"). A list of fill operations, like Cave.luau, so the same list runs in
-- Studio (Terrain:Fill*) and in the cloud preview (tools/preview/run_world.sh):
--   a mud floor slab under everything (rock only where something is carved below it,
--   so the Terrain stays light at this size);
--   the SHELF, a sandy plateau round the hub (a hollow rock drum with a thick top),
--   with dunes, outcrops, ridges and reef flats for the shallow biomes;
--   the DROP-OFF, a rock cliff round the shelf, bitten with notches and buttresses,
--   with sand chutes sloping down it;
--   the REEF's heads, ridges and arches: rocks to swim through and under;
--   the TRENCH, a winding canyon cut deep into the floor to the south, with ragged
--   walls, slate rims, ledges and basalt pillars;
--   the VENTS' basins to the south-west with basalt chimneys (glowing caps);
--   the RUINS' mounds to the east, and the ground of its city (a pale sand plain,
--   drifts and the sunken courtyard's pit; the city itself is parts, Ruins.luau);
--   and the Open Blue's ridges, knolls and pinnacles to the north.
-- Heights follow Shared/Seafloor.luau, so placement code agrees with the ground.
-- `Shelf.ops()` also returns the features WorldService dresses (chimneys,
-- pinnacles, chutes, reef rocks).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Cave = require(script.Parent.Cave)
local VentsPlan = require(script.Parent.VentsPlan)

local World = Config.World
local shelf = World.shelf
local deep = World.deep
local trench = World.trench
local Ruins = Config.Ruins

type Op = Cave.Op

export type CliffLedge = {
	top: Vector3, -- the middle of its top
	angle: number, -- degrees round the hub
	length: number, -- along the rim (studs)
	depth: number, -- how far it stands out of the face
}
export type Cliff = {
	face: number, -- the drum's face (studs from the hub)
	reach: number, -- the furthest the wall stands out of it
	chutes: { number }, -- the chutes (degrees) and half their width (studs)
	chuteHalf: number,
	ledges: { CliffLedge },
	heads: { { position: Vector3, radius: number } }, -- reef heads on the crest
	undercuts: { { number } }, -- angle runs where the lip overhangs
	caves: { { position: Vector3, radius: number } }, -- cave mouths (their middle)
	spurs: { { angle: number, half: number, top: number, extra: number } }, -- ribs (half: studs across)
	columns: { { angle: number, top: number, bottom: number } }, -- fluted column groups
	bands: { { y: number, thick: number, out: number } }, -- the strata, top down (their middles)
}

export type Features = {
	chimneys: { VentsPlan.Chimney },
	pinnacles: { Vector3 },
	chutes: { number }, -- angles (degrees)
	reefRocks: { { center: Vector3, radius: number } }, -- heads and ridges the corals grow on
	cliff: Cliff?, -- the drop-off's wall (Cliff.luau dresses it)
	vents: VentsPlan.Plan?, -- the Vents' field between the basins (Vents.luau dresses it)
	-- The Giant Squid's lair: a cave bitten into the Trench's wall at its foot (`mouth`
	-- on the canyon's side, `into` the way it runs into the rock; TrenchDress.luau)
	lair: { mouth: Vector3, into: Vector3, radius: number, depth: number }?,
	-- The Blue Hole: a sinkhole through the reef's sand into a lined shaft (ReefDress)
	blueHole: { center: Vector3, radius: number, bottom: number }?,
	-- The shelf's rock outcrops (their middles and rough radii; ReefDress keeps clear)
	outcrops: { { center: Vector3, radius: number } }?,
}

local Shelf = {}

-- Terrain material colors beyond Cave.COLORS (the deep floor and the vents' glow).
-- The deep floor is a blue-grey, never black: the Open Blue must read as deep blue
-- water over a blue floor (owner, 2026-10-08: "a large black wasteland")
Shelf.COLORS = {
	[Enum.Material.Mud] = Color3.fromRGB(44, 60, 84),
	[Enum.Material.CrackedLava] = Color3.fromRGB(255, 120, 40),
}

local SAND = Enum.Material.Sand
local ROCK = Enum.Material.Rock
local SLATE = Enum.Material.Slate
local SANDSTONE = Enum.Material.Sandstone
local BASALT = Enum.Material.Basalt
local MUD = Enum.Material.Mud
local LAVA = Enum.Material.CrackedLava
local AIR = Enum.Material.Air

local function ball(ops: { Op }, material: Enum.Material, center: Vector3, radius: number)
	table.insert(ops, { kind = "ball", material = material, center = center, radius = radius })
end

local function block(ops: { Op }, material: Enum.Material, cframe: CFrame, size: Vector3)
	table.insert(
		ops,
		{ kind = "block", material = material, center = cframe.Position, size = size, cframe = cframe }
	)
end

local function cylinder(
	ops: { Op },
	material: Enum.Material,
	center: Vector3,
	radius: number,
	height: number,
	cframe: CFrame?
)
	table.insert(ops, {
		kind = "cylinder",
		material = material,
		center = center,
		radius = radius,
		height = height,
		cframe = cframe or CFrame.new(center),
	})
end

local function outward(angleDeg: number): Vector3
	local a = math.rad(angleDeg)
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

local function at(angleDeg: number, r: number, y: number): Vector3
	return World.hub.center + outward(angleDeg) * r + Vector3.new(0, y, 0)
end

-- The Sunken Ruins' city frame (Config/Ruins): x out along its avenue, y up from
-- the deep floor, z across toward larger angles
local function ruinsFrame(floor: number): CFrame
	local out = outward(Ruins.angle)
	return CFrame.fromMatrix(
		at(Ruins.angle, Ruins.radius, floor),
		out,
		Vector3.yAxis,
		out:Cross(Vector3.yAxis)
	)
end

-- Whether a mound at `center` (`radius` round) would reach into the city's box
local function inCity(city: CFrame, center: Vector3, radius: number): boolean
	local q = city:PointToObjectSpace(center)
	local box = Ruins.keepOut
	return q.X > box.x[1] - radius
		and q.X < box.x[2] + radius
		and q.Z > box.z[1] - radius
		and q.Z < box.z[2] + radius
end

-- The city's ground: a pale sand plain (low discs a few studs proud of the mud),
-- sand drifted against its stones, and the sunken courtyard's pit cut into the
-- floor, its floor `court.depth` under the deep floor (Ruins.luau lines it with
-- walls, stairs and a paved floor; the carve's edge runs inside its walls)
local function ruinsGround(ops: { Op }, city: CFrame, floor: number)
	-- the plain: big discs, a ragged rim of smaller ones round each and a few
	-- patches beyond, so its edge wanders instead of running round in arcs
	local sandRng = Random.new(World.seed + 73)
	for _, disc in Ruins.sand do
		cylinder(ops, SAND, city * Vector3.new(disc[1], 0, disc[2]), disc[3], Ruins.sandHeight)
	end
	for _, disc in Ruins.sand do
		for k = 1, Ruins.sandRim + 2 do
			local a = sandRng:NextNumber(0, 2 * math.pi)
			local patch = k > Ruins.sandRim
			local d = disc[3]
				* (if patch then sandRng:NextNumber(1.15, 1.4) else sandRng:NextNumber(0.75, 1.05))
			local r = disc[3]
				* (if patch then sandRng:NextNumber(0.06, 0.12) else sandRng:NextNumber(0.16, 0.32))
			cylinder(
				ops,
				SAND,
				city * Vector3.new(disc[1] + math.cos(a) * d, 0, disc[2] + math.sin(a) * d),
				r,
				Ruins.sandHeight
			)
		end
	end
	for _, drift in Ruins.drifts do
		ball(ops, SAND, city * Vector3.new(drift[1], -drift[3] * 0.8, drift[2]), drift[3])
	end
	-- (twice: an Air fill takes occupancy away rather than clearing it, and one pass
	-- over the mud left some behind, as DenCarve found)
	local court = Ruins.court
	local height = court.depth + 8
	for _ = 1, 2 do
		block(
			ops,
			AIR,
			city * CFrame.new(court.x, -court.depth + height / 2, court.z),
			Vector3.new(court.inner[1] + court.wall, height, court.inner[2] + court.wall)
		)
	end
end

local function sectorAngle(rng: Random, from: number, to: number): number
	local span = (to - from) % 360
	return (from + rng:NextNumber(0, if span == 0 then 360 else span)) % 360
end

-- ---------------------------------------------------------------------------
-- The drop-off (owner, 2026-10-19: "The cliff edge needs to be dialed up more and
-- should have coral etc on it. Right now it's just bulbous spheres off the edge.
-- Now that we can see more it needs to look better"): a layered reef wall, toon
-- rounded, on the shelf's drum (its face FACE from the hub's centre), in place of
-- the balls that were stuck on and bitten out of it. From the top down:
--   * the CREST: the reef's lip, rounded blocks of rock along the rim with the
--     shelf's sand running onto them and reef heads on top. In runs it overhangs an
--     UNDERCUT (an air band under it, the wall-dive notch); elsewhere a thick
--     sandstone lip band holds it up;
--   * the STRATA: bands of rock, slate and sandstone, each a row of flattened
--     Cave.pebble slabs laid end to end round the rim, every slab standing its own
--     way out of the face (with the band, the spur it's on and a little jitter),
--     sitting a little high or low and rolled a degree or two, so the joints show,
--     over recessed grooves; thin and thick bands, a few merged, the lower wall a
--     little further out than the upper (a batter), broken by erosion;
--   * SPURS: ribs where every band stands further out, from below the lip to the
--     foot, so the wall reads in bays and buttresses, not as shelves;
--   * LEDGES: wide flat shelves at several depths (Cave.pebble slabs) where
--     Cliff.luau grows coral gardens;
--   * FLUTED COLUMNS (tall narrow capsules in groups), CREVICES (tall slots cut
--     through every band to the face) and CAVES bitten into the face;
--   * TALUS at the foot: rounded boulders on the deep floor (sandstone by the
--     chutes, whose foot fans it), never past the foot into the Trench's canyon, the
--     Ruins city's box or a Vents basin.
-- Nothing stands more than REACH studs out of the face (the caves' hollows bite ~40
-- into the drum's 110-stud wall), so Shared/Seafloor's nominal drop-off and deep
-- floor stay true. It draws on its own Random: Shelf.ops burns the shared
-- sequence's old draws.
-- ---------------------------------------------------------------------------
local CHUTES = { 20, 55, 160, 200, 250, 292, 320, 340 } -- sand chutes down the cliff (degrees)
local CHUTE_HALF = 40 -- half a chute's width (studs)
local FACE = shelf.radius + 40 -- the drum's face: the wall everything below stands on
local REACH = 25 -- the furthest anything stands out of the face (studs)
local CLIFF_SEED = 19 -- the drop-off's own Random: World.seed + this
local SEGMENT = 110 -- studs per capsule along the rim (a chord sags under 2 studs)
local EMBED = 4 -- studs a slab reaches back into the face

local function axisFrame(center: Vector3, axis: Vector3): CFrame
	local reference = if math.abs(axis.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local right = reference:Cross(axis).Unit
	return CFrame.fromMatrix(center, right, axis, right:Cross(axis))
end

-- A capsule from `a` to `b` (Cave.pebble's piece): a cylinder and, unless `open`, a
-- ball at each end
local function capsule(
	ops: { Op },
	material: Enum.Material,
	a: Vector3,
	b: Vector3,
	radius: number,
	open: boolean?
)
	local span = b - a
	local center = (a + b) / 2
	cylinder(ops, material, center, radius, span.Magnitude, axisFrame(center, span.Unit))
	if not open then
		ball(ops, material, a, radius)
		ball(ops, material, b, radius)
	end
end

-- The frame on the rim at `angle`, `r` from the hub and `y` up: x along the rim
-- (toward larger angles), y up, z outward (its look is in toward the hub)
local function rimFrame(angle: number, r: number, y: number): CFrame
	local out = outward(angle)
	local along = Vector3.yAxis:Cross(out) -- toward larger angles
	return CFrame.fromMatrix(at(angle, r, y), along, Vector3.yAxis, along:Cross(Vector3.yAxis))
end

local function angleGap(a: number, b: number): number
	return math.abs(((a - b + 180) % 360) - 180)
end

-- Whether `angle` is within `studs` of a chute's edge (measured on the face)
local function nearChute(angle: number, studs: number): boolean
	for _, chute in CHUTES do
		if math.rad(angleGap(angle, chute)) * FACE < CHUTE_HALF + studs then
			return true
		end
	end
	return false
end

-- The rim's free stretches between the chutes, `margin` studs clear of each:
-- { from, to } in degrees, `to` > `from` (it may pass 360)
local function stretches(margin: number): { { number } }
	local pad = math.deg((CHUTE_HALF + margin) / FACE)
	local list = {}
	for i, chute in CHUTES do
		local nextChute = CHUTES[i % #CHUTES + 1] + (if i == #CHUTES then 360 else 0)
		if nextChute - pad > chute + pad then
			table.insert(list, { chute + pad, nextChute - pad })
		end
	end
	return list
end

-- Each free stretch cut into runs `lengths` studs long with `gaps` between them
local function runs(cr: Random, margin: number, lengths: { number }, gaps: { number }): { { number } }
	local list = {}
	for _, stretch in stretches(margin) do
		local angle = stretch[1] + math.deg(cr:NextNumber(0, gaps[2]) / FACE)
		while angle < stretch[2] do
			local stop = math.min(angle + math.deg(cr:NextNumber(lengths[1], lengths[2]) / FACE), stretch[2])
			if math.rad(stop - angle) * FACE >= lengths[1] * 0.4 then
				table.insert(list, { angle, stop })
			end
			angle = stop + math.deg(cr:NextNumber(gaps[1], gaps[2]) / FACE)
		end
	end
	return list
end

-- A row of rounded rock round the rim from `from` to `to` degrees: capsules chained
-- along the curve (`radius` round, `r(angle)` from the hub, `y(angle)` up), a ball
-- at each end of the row; ~SEGMENT studs a capsule
local function rimRow(
	ops: { Op },
	material: Enum.Material,
	from: number,
	to: number,
	r: (number) -> number,
	y: (number) -> number,
	radius: number
)
	local count = math.max(1, math.ceil(math.rad(to - from) * FACE / SEGMENT))
	local last = at(from, r(from), y(from))
	ball(ops, material, last, radius)
	for k = 1, count do
		local angle = from + (to - from) * k / count
		local point = at(angle, r(angle), y(angle))
		-- (a little long, so the chain has no notch on the outside of each joint)
		local span = point - last
		local stretch = span.Unit * radius * 0.25
		capsule(ops, material, last - stretch, point + stretch, radius, true)
		last = point
	end
	ball(ops, material, last, radius)
end

local function dropOff(ops: { Op }, features: Features)
	local cr = Random.new(World.seed + CLIFF_SEED)
	local floor = deep.floorY
	local city = ruinsFrame(floor)
	local cliff: Cliff = {
		face = FACE,
		reach = REACH,
		chutes = CHUTES,
		chuteHalf = CHUTE_HALF,
		bands = {},
		ledges = {},
		heads = {},
		undercuts = {},
		caves = {},
		spurs = {},
		columns = {},
	}
	features.cliff = cliff

	-- The wall wanders a little in plan (bays and bulges, ±7 studs) and every band
	-- dips together round the shelf (±11 studs), so the rim is no perfect circle and
	-- the layers read as one rock
	local p1, p2, p3, p4 =
		cr:NextNumber(0, 6.28), cr:NextNumber(0, 6.28), cr:NextNumber(0, 6.28), cr:NextNumber(0, 6.28)
	local function wander(angle: number): number
		local a = math.rad(angle)
		return 4 * math.sin(a * 9 + p1) + 3 * math.sin(a * 4 + p2)
	end
	local function dip(angle: number): number
		local a = math.rad(angle)
		return 7 * math.sin(a * 5 + p3) + 4 * math.sin(a * 11 + p4)
	end

	-- What stands where (an angle span and heights), so features don't pile up
	local claims: { { angle: number, half: number, top: number, bottom: number } } = {}
	local function free(angle: number, halfStuds: number, top: number, bottom: number): boolean
		for _, c in claims do
			local apart = math.rad(angleGap(angle, c.angle)) * FACE
			if apart < halfStuds + c.half and top > c.bottom and bottom < c.top then
				return false
			end
		end
		return true
	end
	local function claim(angle: number, halfStuds: number, top: number, bottom: number)
		table.insert(claims, { angle = angle, half = halfStuds, top = top, bottom = bottom })
	end
	local function inTrenchSector(angle: number, pad: number): boolean
		return Seafloor.inSector(angle, trench.angles[1] - pad, trench.angles[2] + pad)
	end
	-- A free spot round the rim (`margin` studs clear of the chutes)
	local function rimAngle(margin: number): number
		for _ = 1, 30 do
			local angle = cr:NextNumber(0, 360)
			if not nearChute(angle, margin) then
				return angle
			end
		end
		return 0 -- (never: the chutes take a twentieth of the rim)
	end

	-- A slab of a band: a rounded roll `length` long round the rim at `angle`,
	-- `thick` tall, its front `out` studs out of the face (wander included, never past
	-- REACH), and when one roll doesn't reach back EMBED into the face a second one
	-- behind it, a little shorter: Cave.pebble's flattened shape in at most two
	-- capsules (a thin band can't stand far out: the two must overlap). Rolled `roll`
	-- radians along the rim.
	local function slab(
		material: Enum.Material,
		angle: number,
		length: number,
		y: number,
		thick: number,
		out: number,
		roll: number
	)
		local r = thick / 2
		local half = math.max(length / 2 - r * 0.6, r * 0.3)
		-- (a straight roll's ends stand out of the curved face by its chord's sag)
		local sag = half * half / (2 * FACE)
		local front = math.clamp(out + wander(angle) * 0.5, 2, math.min(REACH - sag, 3.8 * r - EMBED))
		local frame = rimFrame(angle, FACE, y) * CFrame.Angles(0, 0, roll)
		-- (the frame's z points out of the face: a roll `d` studs out sits at z = d)
		local rolls = { { d = front - r, half = half, open = false } }
		if front - 2 * r > -EMBED then
			-- (the back roll's ends hide behind the front roll's: no balls on them)
			table.insert(rolls, { d = -EMBED + r, half = half * 0.86, open = true })
		end
		for _, piece in rolls do
			capsule(
				ops,
				material,
				(frame * CFrame.new(-piece.half, 0, piece.d)).Position,
				(frame * CFrame.new(piece.half, 0, piece.d)).Position,
				r,
				piece.open
			)
		end
	end

	-- The spurs: ribs down the wall where every band stands further out (a smooth
	-- bump across the rib, coming in over 40 studs under its top), so the face reads
	-- in bays and buttresses
	for _ = 1, 64 do
		if #cliff.spurs >= 44 then
			break
		end
		local angle = rimAngle(50)
		local half = cr:NextNumber(18, 40)
		local top = cr:NextNumber(-150, -64)
		if not free(angle, half + 30, top, floor) then
			continue
		end
		claim(angle, half + 10, top, floor)
		table.insert(cliff.spurs, { angle = angle, half = half, top = top, extra = cr:NextNumber(9, 15) })
	end
	claims = {} -- (the spurs only keep each other apart: the slots and caves cut into them)
	local function spurOut(angle: number, y: number): number
		local best = 0
		for _, spur in cliff.spurs do
			local apart = math.rad(angleGap(angle, spur.angle)) * FACE
			local reach = spur.half * 1.5
			if apart < reach and y < spur.top then
				local across = 1 - (apart / reach) ^ 2
				best = math.max(best, spur.extra * across * across * math.clamp((spur.top - y) / 40, 0, 1))
			end
		end
		return best
	end

	-- The strata, from under the lip down to the foot: bands 12-36 thick, most with
	-- 4-10 stud grooves between them (a few merged with the next), each standing
	-- 6-22 studs out of the face (the thick ones further, and the lower wall up to 4
	-- more; a spur takes it to REACH), as slabs 56-150 long.
	-- The first is the sandstone lip band right under the crest, unbroken, which the
	-- undercut then bites away in places.
	type Band = {
		y: number,
		thick: number,
		out: number,
		material: Enum.Material,
		erode: number,
		k1: number,
		k2: number,
		phase: number,
	}
	local bands: { Band } = {
		{ y = -42, thick = 26, out = 12, material = SANDSTONE, erode = 0, k1 = 0, k2 = 0, phase = 0 },
	}
	local palette = { SANDSTONE, SLATE, ROCK }
	local level = -60
	local last = SANDSTONE
	while true do
		local thick = if cr:NextNumber() < 0.3 then cr:NextNumber(26, 36) else cr:NextNumber(12, 24)
		if level - thick < floor + 20 then
			break
		end
		local material = palette[cr:NextInteger(1, #palette)]
		if material == last then
			material = palette[(table.find(palette, material) :: number) % #palette + 1]
		end
		last = material
		local low = math.clamp((level - thick / 2) / floor, 0, 1)
		table.insert(bands, {
			y = level - thick / 2,
			thick = thick,
			out = cr:NextNumber(3, 9) + thick * 0.25 + 4 * low,
			material = material,
			erode = cr:NextNumber(0.03, 0.14),
			-- (it swells, pinches and stands out more or less along the rim, in slow
			-- waves of ~140-280 and ~90-190 studs, so neighbouring slabs differ little
			-- and the band reads as one layer, its joints faint)
			k1 = cr:NextNumber(20, 40),
			k2 = cr:NextNumber(30, 60),
			phase = cr:NextNumber(0, 6.28),
		})
		level -= thick + (if cr:NextNumber() < 0.15 then cr:NextNumber(1, 3) else cr:NextNumber(4, 10))
	end
	for index, band in bands do
		table.insert(cliff.bands, { y = band.y, thick = band.thick, out = band.out })
		for _, stretch in stretches(14) do
			local angle = stretch[1]
			while true do
				local length = if index == 1 then cr:NextNumber(90, 150) else cr:NextNumber(56, 150)
				local stop = math.min(angle + math.deg(length / FACE), stretch[2])
				local studs = math.rad(stop - angle) * FACE
				if studs < 12 then
					break
				end
				local middle = (angle + stop) / 2
				if cr:NextNumber() >= band.erode then
					local y = band.y
					local thick, out, roll = band.thick, band.out, 0
					if index > 1 then
						local a = math.rad(middle)
						y += dip(middle) + 2 * math.sin(a * band.k1 + band.phase) + cr:NextNumber(-0.6, 0.6)
						thick *= 1 + 0.08 * math.sin(a * band.k2 + band.phase) + cr:NextNumber(-0.04, 0.04)
						out += spurOut(middle, y) + 3.5 * math.sin(a * band.k1 + band.phase * 2) + cr:NextNumber(
							-0.8,
							0.8
						)
						roll = cr:NextNumber(-0.012, 0.012)
					end
					slab(band.material, middle, studs + thick * 0.4, y, thick, math.max(out, 5), roll)
				end
				if stop >= stretch[2] then
					break
				end
				angle = stop
			end
		end
	end

	-- The undercut: an air band under the crest in runs (about half the rim), cut
	-- twice (one Air fill over fresh rock leaves some occupancy behind, DenCarve)
	for _, span in runs(cr, 30, { 140, 460 }, { 140, 520 }) do
		table.insert(cliff.undercuts, span)
		for _ = 1, 2 do
			rimRow(ops, AIR, span[1], span[2], function(angle)
				return FACE + 2 + wander(angle) * 0.5
			end, function()
				return -43
			end, 16)
		end
	end

	-- Crevices: tall slots up the face, cut through every band in front of them to
	-- 6 studs into the face
	for _ = 1, 22 do
		local angle = rimAngle(30)
		local top = cr:NextNumber(-230, -70)
		local bottom = math.max(top - cr:NextNumber(90, 230), floor + 12)
		local radius = cr:NextNumber(7, 10)
		if not free(angle, radius + 10, top + radius, bottom - radius) then
			continue
		end
		claim(angle, radius + 6, top + radius, bottom - radius)
		local inner, outer = FACE - 6 + radius, FACE + REACH + 4 - radius
		local steps = math.max(1, math.ceil((outer - inner) / (radius * 1.2)))
		for _ = 1, 2 do
			for k = 0, steps do
				local r = inner + (outer - inner) * k / steps
				capsule(ops, AIR, at(angle, r, bottom), at(angle, r, top), radius)
			end
		end
	end

	-- Caves bitten into the face: a mouth and a darker hollow behind it
	for _ = 1, 12 do
		local angle = rimAngle(40)
		local y = cr:NextNumber(floor + 50, -110)
		local radius = cr:NextNumber(16, 26)
		if not free(angle, radius + 8, y + radius, y - radius) then
			continue
		end
		claim(angle, radius + 4, y + radius, y - radius)
		local mouth = at(angle, FACE - 2, y)
		for _ = 1, 2 do
			ball(ops, AIR, mouth, radius)
			ball(ops, AIR, at(angle, FACE + 10, y), radius * 0.9)
			ball(ops, AIR, at(angle, FACE - radius * 0.9, y - radius * 0.15), radius * 0.62)
		end
		table.insert(cliff.caves, { position = mouth, radius = radius })
	end

	-- Fluted columns: 3-6 tall narrow capsules side by side, standing on the floor
	-- or on a band partway up (organ pipes)
	for _ = 1, 16 do
		local angle = rimAngle(50)
		local foot = cr:NextNumber() < 0.6
		if foot and inTrenchSector(angle, 10) then
			continue
		end
		local radius = cr:NextNumber(4.5, 7)
		local count = cr:NextInteger(3, 6)
		local bottom = if foot then floor - 4 else bands[cr:NextInteger(3, #bands)].y
		local tall = if foot then cr:NextNumber(90, 200) else cr:NextNumber(40, 100)
		local half = radius * 1.7 * count / 2
		if not free(angle, half + 4, bottom + tall, bottom) then
			continue
		end
		claim(angle, half, bottom + tall, bottom)
		local frame = rimFrame(angle, FACE + REACH - radius - 1, 0)
		for k = 1, count do
			local x = (k - (count + 1) / 2) * radius * 1.7
			local height = tall * cr:NextNumber(0.6, 1)
			local base = frame * Vector3.new(x, bottom, 0)
			capsule(
				ops,
				if cr:NextNumber() < 0.5 then ROCK else SLATE,
				base,
				base + Vector3.new(0, height, 0),
				radius * cr:NextNumber(0.85, 1.1)
			)
		end
		table.insert(cliff.columns, { angle = angle, top = bottom + tall, bottom = bottom })
	end

	-- Ledges: wide flat shelves along a band (its top a little over it), 60-110
	-- long, standing 20-25 out of the face, for the coral gardens
	for _ = 1, 70 do
		if #cliff.ledges >= 48 then
			break
		end
		local band = bands[cr:NextInteger(3, #bands)]
		local length = cr:NextNumber(60, 110)
		local angle = rimAngle(length / 2 + 20)
		local depth = cr:NextNumber(20, 25)
		local y = band.y + dip(angle) + band.thick / 2 - 3
		if not free(angle, length / 2 + 10, y + 20, y - 14) then
			continue
		end
		claim(angle, length / 2, y + 20, y - 14)
		local slabThick = 14
		local thickness = depth + EMBED
		local r = FACE + depth - thickness / 2
		Cave.pebble(
			ops,
			band.material,
			rimFrame(angle, r, y - slabThick / 2),
			Vector3.new(length, slabThick, thickness)
		)
		table.insert(cliff.ledges, { top = at(angle, r, y), angle = angle, length = length, depth = depth })
	end

	-- The crest: the reef's lip, rounded blocks along the rim (the inner ones over the
	-- drum's step to the sand), then reef heads on it
	for _, stretch in stretches(14) do
		for _, row in { { r = -12, y = -12, size = { 12, 15 } }, { r = 6, y = -15, size = { 10, 14 } } } do
			local angle = stretch[1]
			while true do
				local length = cr:NextNumber(46, 96)
				local stop = math.min(angle + math.deg(length / FACE), stretch[2])
				local studs = math.rad(stop - angle) * FACE
				if studs < 12 then
					break
				end
				local middle = (angle + stop) / 2
				local radius = cr:NextNumber(row.size[1], row.size[2])
				local frame = rimFrame(
					middle,
					FACE + row.r + wander(middle) * 0.5,
					row.y + cr:NextNumber(-2, 2)
				) * CFrame.Angles(0, cr:NextNumber(-0.05, 0.05), cr:NextNumber(-0.04, 0.04))
				local half = studs / 2 + radius * 0.2
				capsule(
					ops,
					ROCK,
					(frame * CFrame.new(-half, 0, 0)).Position,
					(frame * CFrame.new(half, 0, 0)).Position,
					radius
				)
				if stop >= stretch[2] then
					break
				end
				angle = stop
			end
		end
	end
	for _ = 1, 70 do
		local angle = rimAngle(30)
		local size = Vector3.new(cr:NextNumber(18, 40), cr:NextNumber(12, 22), cr:NextNumber(16, 28))
		local r = FACE + cr:NextNumber(-22, 2)
		local frame = rimFrame(angle, r, cr:NextNumber(-2, 3))
			* CFrame.Angles(cr:NextNumber(-0.15, 0.15), cr:NextNumber(-0.5, 0.5), cr:NextNumber(-0.15, 0.15))
		Cave.pebble(ops, if cr:NextNumber() < 0.75 then ROCK else SANDSTONE, frame, size)
		table.insert(
			cliff.heads,
			{ position = frame.Position + Vector3.new(0, size.Y / 2, 0), radius = size.X / 2 }
		)
	end

	-- Talus at the foot: rounded boulders on the deep floor, most near the face,
	-- sandstone and smaller by a chute, where its sand fans out
	local made = 0
	for _ = 1, 260 do
		if made >= 96 then
			break
		end
		local angle = cr:NextNumber(0, 360)
		local away = 6 + 84 * cr:NextNumber() ^ 2
		local size = Vector3.new(cr:NextNumber(12, 32), cr:NextNumber(9, 20), cr:NextNumber(12, 28))
			* (1.15 - away / 120)
		local r = FACE + away + size.X * 0.3
		local spot = at(angle, r, 0)
		if
			nearChute(angle, 8)
			or inTrenchSector(angle, 8)
			or Seafloor.inTrench(spot.X, spot.Z, 40)
			or inCity(city, spot, size.Magnitude / 2 + 20)
		then
			continue
		end
		local basin = false
		for _, b in Seafloor.ventBasins() do
			if math.sqrt((spot.X - b.x) ^ 2 + (spot.Z - b.z) ^ 2) < b.radius + 30 + size.X then
				basin = true
			end
		end
		if basin then
			continue
		end
		local byChute = nearChute(angle, 110)
		local material = if byChute then SANDSTONE elseif cr:NextNumber() < 0.75 then ROCK else SLATE
		if byChute then
			size *= 0.75
		end
		Cave.pebble(
			ops,
			material,
			CFrame.new(at(angle, r, floor - size.Y * 0.3))
				* CFrame.Angles(
					cr:NextNumber(-0.35, 0.35),
					cr:NextNumber(0, 6.28),
					cr:NextNumber(-0.35, 0.35)
				),
			size
		)
		made += 1
	end
	-- The chutes' sand fans out either side of each one's foot
	for _, chute in CHUTES do
		for side = -1, 1, 2 do
			local angle = chute + side * math.deg((CHUTE_HALF + 18) / FACE)
			ball(ops, SAND, at(angle, FACE + 46, floor - 26), 36)
		end
	end
end

-- ---------------------------------------------------------------------------
-- The Hydrothermal Vents' field (owner, 2026-10-19: "The vents part of the map needs
-- more substance too"): the Terrain VentsPlan lays out between the basins, which
-- Vents.luau dresses with parts. It draws on its own Random (World.seed + 98), so
-- the shared sequence is untouched, and every top stays under VentsPlan.ceiling (no
-- prey school is carried up its side).
--   * THE FORGE: a volcano of stacked basalt rings (a voxel tall, so they round into
--     one slope) with lumps and buttresses on its flanks, crags round a crater bowl
--     holding a lava lake, a notch where it spills, lava runnels in grooves down to
--     aprons of lava at its foot, and a shoulder cone with its own small crater;
--   * the smoker complexes' SPIRES: tapering and knobbly, with flanges and a hot lip,
--     on low mounds;
--   * PILLOW LAVA (rounded basalt pillows with lava glowing between them), CRACKED
--     CRUST patches flush with the floor and long low BASALT RIDGES.
-- ---------------------------------------------------------------------------

-- A cylinder from `a` to `b`
local function ventRod(ops: { Op }, material: Enum.Material, a: Vector3, b: Vector3, radius: number)
	local span = b - a
	local axis = span.Unit
	local reference = if math.abs(axis.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local right = reference:Cross(axis).Unit
	local center = (a + b) / 2
	cylinder(
		ops,
		material,
		center,
		radius,
		span.Magnitude,
		CFrame.fromMatrix(center, right, axis, right:Cross(axis))
	)
end

local function forgeOps(ops: { Op }, forge: VentsPlan.Forge, vr: Random)
	local c, height = forge.center, forge.height
	local function onFlank(heading: number, t: number, inset: number): Vector3
		local r = VentsPlan.forgeRadius(forge, t) - inset
		return c + Vector3.new(math.cos(heading) * r, height * t, math.sin(heading) * r)
	end
	local function nearRunnel(heading: number, margin: number): boolean
		for _, runnel in forge.runnels do
			if math.abs((heading - runnel + math.pi) % (2 * math.pi) - math.pi) < margin then
				return true
			end
		end
		return false
	end
	-- The body: rings stacked up the cone, each a little narrower, a voxel (4 studs)
	-- tall, so Terrain rounds the steps into one slope (7-stud rings read as terraces)
	local layers = math.ceil(height / 4)
	for i = 0, layers - 1 do
		local t0, t1 = i / layers, (i + 1) / layers
		local bottom = if i == 0 then c.Y - 8 else c.Y + height * t0 - 1
		local top = c.Y + height * t1 + 1
		cylinder(
			ops,
			BASALT,
			Vector3.new(c.X, (bottom + top) / 2, c.Z),
			VentsPlan.forgeRadius(forge, (t0 + t1) / 2),
			top - bottom
		)
	end
	-- Lumps on the flanks (fewer and smaller up high), clear of the runnels' grooves
	for _ = 1, 40 do
		local t = vr:NextNumber() ^ 1.3 * 0.86
		local heading = vr:NextNumber(0, 2 * math.pi)
		local radius = (16 - 8 * t) * vr:NextNumber(0.8, 1.2)
		if not nearRunnel(heading, 0.42) then
			ball(
				ops,
				if vr:NextNumber() < 0.25 then SLATE else BASALT,
				onFlank(heading, t, radius * 0.45),
				radius
			)
		end
	end
	-- Buttresses down the flanks between the runnels, and a few more
	local headings: { number } = {}
	for k, runnel in forge.runnels do
		local nextRunnel = forge.runnels[k % #forge.runnels + 1]
		table.insert(headings, runnel + ((nextRunnel - runnel) % (2 * math.pi)) / 2)
	end
	for _ = 1, 3 do
		local heading = vr:NextNumber(0, 2 * math.pi)
		if not nearRunnel(heading, 0.5) then
			table.insert(headings, heading)
		end
	end
	for _, heading in headings do
		local radius = vr:NextNumber(8, 12)
		local low = onFlank(heading, 0.03, radius * 0.5)
		local high = onFlank(heading + vr:NextNumber(-0.08, 0.08), vr:NextNumber(0.5, 0.68), radius * 0.6)
		ventRod(ops, BASALT, low, high, radius)
		ball(ops, BASALT, low, radius * 1.15)
		ball(ops, BASALT, high, radius)
	end
	-- Lumps round the foot, half buried, between the runnels
	for _ = 1, 12 do
		local heading = vr:NextNumber(0, 2 * math.pi)
		local radius = vr:NextNumber(8, 14)
		local r = forge.base + vr:NextNumber(-4, 4)
		if not nearRunnel(heading, 0.3) then
			ball(
				ops,
				BASALT,
				c + Vector3.new(math.cos(heading) * r, -radius * 0.35, math.sin(heading) * r),
				radius
			)
		end
	end
	-- A broken rim: crags round the summit (inside the lumps' allowance over the
	-- cone, VentsPlan FORGE.lumps), none where it spills
	for k = 1, 6 do
		local heading = forge.runnels[1] + k * 2 * math.pi / 7 + vr:NextNumber(-0.2, 0.2)
		local radius = vr:NextNumber(5, 8)
		ball(ops, SLATE, onFlank(heading, 0.99, -radius * 0.2) + Vector3.new(0, -radius * 0.3, 0), radius)
	end
	-- The shoulder: a parasitic cone low on one flank, its own small crater glowing
	local shoulder = forge.shoulder
	if shoulder then
		local s, sh = shoulder.center, shoulder.height
		local rim = shoulder.base * 0.3
		local layers = math.ceil(sh / 4)
		for i = 0, layers - 1 do
			local t0, t1 = i / layers, (i + 1) / layers
			local bottom = if i == 0 then s.Y - 6 else s.Y + sh * t0 - 1
			local top = s.Y + sh * t1 + 1
			local radius = rim + (shoulder.base - rim) * (1 - (t0 + t1) / 2) ^ 1.35
			cylinder(ops, BASALT, Vector3.new(s.X, (bottom + top) / 2, s.Z), radius, top - bottom)
		end
		for _ = 1, 2 do
			ball(ops, AIR, Vector3.new(s.X, s.Y + sh + 2, s.Z), shoulder.crater)
		end
		cylinder(
			ops,
			LAVA,
			Vector3.new(s.X, s.Y + sh + 2 - shoulder.crater + 2, s.Z),
			shoulder.crater * 0.6,
			5
		)
	end
	-- The crater: a bowl in the summit (twice: an Air fill takes occupancy away rather
	-- than clearing it), a lava lake in its floor and a notch where it spills over the
	-- rim down the first runnel
	local summit = c.Y + height
	for _ = 1, 2 do
		ball(ops, AIR, Vector3.new(c.X, summit + 4, c.Z), forge.crater)
	end
	local bowl = summit + 4 - forge.crater
	cylinder(ops, LAVA, Vector3.new(c.X, bowl + 0.5, c.Z), forge.crater * 0.62, 9)
	local spill = forge.runnels[1]
	for _ = 1, 2 do
		ball(ops, AIR, onFlank(spill, 0.985, 2) + Vector3.new(0, -4, 0), 10)
	end
	-- The runnels: a groove down the flank with lava in its bottom, to an apron of
	-- lava at the foot
	local segments = 18
	for index, heading in forge.runnels do
		local top = if index == 1 then 0.97 else 0.9
		for k = 0, segments - 1 do
			local a = VentsPlan.runnelPoint(forge, heading, top * (1 - k / segments))
			local b = VentsPlan.runnelPoint(forge, heading, top * (1 - (k + 1) / segments))
			local outA = Vector3.new(a.X - c.X, 0, a.Z - c.Z).Unit
			local outB = Vector3.new(b.X - c.X, 0, b.Z - c.Z).Unit
			for _ = 1, 2 do
				ventRod(ops, AIR, a + outA * 0.5, b + outB * 0.5, 4.5)
			end
			ventRod(ops, LAVA, a - outA * 2.2, b - outB * 2.2, 3)
		end
		local foot = VentsPlan.runnelPoint(forge, heading, 0)
		local apron = foot + Vector3.new(foot.X - c.X, 0, foot.Z - c.Z).Unit * 9
		cylinder(ops, LAVA, Vector3.new(apron.X, c.Y - 2, apron.Z), vr:NextNumber(11, 14), 4)
	end
end

-- One smoker spire: tapering drums along its (nearly upright) axis with a bulge at
-- each joint, knobs, flanges, and a rounded lip with hot crust in it
local function spireOps(ops: { Op }, spire: VentsPlan.Spire, vr: Random)
	local axis, foot, h = spire.tilt, spire.foot, spire.height
	local function along(d: number): Vector3
		return foot + axis * d
	end
	local function radiusAt(d: number): number
		return spire.radius * (1 - 0.5 * math.clamp(d / h, 0, 1))
	end
	ball(ops, BASALT, foot - Vector3.new(0, spire.radius * 0.7, 0), spire.radius * 1.5)
	local sections = 4
	for s = 0, sections - 1 do
		local d0, d1 = h * s / sections, h * (s + 1) / sections
		ventRod(ops, BASALT, along(d0 - (if s == 0 then 4 else 1)), along(d1 + 1), radiusAt((d0 + d1) / 2))
		if s > 0 then
			ball(ops, BASALT, along(d0), radiusAt(d0) * 1.08)
		end
	end
	for _ = 1, math.floor(h / 14) + 2 do
		local d = vr:NextNumber(0.1, 0.9) * h
		local a = vr:NextNumber(0, 2 * math.pi)
		local r = radiusAt(d)
		ball(
			ops,
			BASALT,
			along(d) + Vector3.new(math.cos(a), 0, math.sin(a)) * (r * 0.85),
			vr:NextNumber(2.5, 4.5) + r * 0.15
		)
	end
	for _, d in spire.flanges do
		cylinder(ops, BASALT, along(d), radiusAt(d) + vr:NextNumber(4, 6), 4)
	end
	local lip = radiusAt(h)
	ball(ops, BASALT, along(h - 1), lip + 1.2)
	ball(ops, LAVA, along(h + 0.5), math.max(lip * 0.75, 3.5))
end

local function ventsField(ops: { Op }, plan: VentsPlan.Plan)
	local vr = Random.new(World.seed + 98)
	for _, ridge in plan.ridges do
		Cave.pebble(ops, BASALT, ridge.cframe, ridge.size)
	end
	for _, mound in plan.mounds do
		local main = mound.height / 1.35
		ball(ops, BASALT, mound.center + Vector3.new(0, main * 0.35, 0), main)
		local count = vr:NextInteger(4, 7)
		for k = 1, count do
			local a = k / count * 2 * math.pi + vr:NextNumber(-0.4, 0.4)
			local d = vr:NextNumber(0.45, 1) * mound.radius
			local r = main * vr:NextNumber(0.5, 0.8)
			ball(ops, BASALT, mound.center + Vector3.new(math.cos(a) * d, r * 0.3, math.sin(a) * d), r)
			-- Lava glowing in the seam to the next pillow
			if vr:NextNumber() < 0.55 then
				local seam = a + math.pi / count
				ball(
					ops,
					LAVA,
					mound.center + Vector3.new(math.cos(seam) * d * 0.7, 1.5, math.sin(seam) * d * 0.7),
					vr:NextNumber(3.5, 4.5)
				)
			end
		end
	end
	for _, crust in plan.crusts do
		local c = crust.center
		cylinder(ops, LAVA, Vector3.new(c.X, c.Y - 2, c.Z), crust.radius, 4)
		for _ = 1, vr:NextInteger(2, 3) do
			local a = vr:NextNumber(0, 2 * math.pi)
			local d = crust.radius * vr:NextNumber(0.8, 1.25)
			cylinder(
				ops,
				LAVA,
				Vector3.new(c.X + math.cos(a) * d, c.Y - 2, c.Z + math.sin(a) * d),
				crust.radius * vr:NextNumber(0.25, 0.45),
				4
			)
		end
	end
	local forge = plan.forge
	if forge then
		forgeOps(ops, forge, vr)
	end
	for _, smoker in plan.smokers do
		ball(ops, BASALT, smoker.center - Vector3.new(0, smoker.radius * 0.6, 0), smoker.radius * 0.85)
		for _, spire in smoker.spires do
			spireOps(ops, spire, vr)
		end
	end
end

-- Where the Squid's Lair is bitten into the Trench's wall and the Blue Hole sunk in
-- the reef (the dressing modules read them from Features)
local LAIR = { r = 1330, side = 1, radius = 24, depth = 66, rise = 26 }
local BLUE_HOLE = { angle = 40, r = 640, radius = 56, bottom = -212, lining = 26 }
-- The stretch of the canyon the Leviathan's Spine lies in (studs from the hub) and
-- how far either side of its line it reaches
local SPINE_CLEAR = { from = 1010, to = 1410, half = 76 }

local function landmarkOps(
	ops: { Op },
	features: Features,
	pillars: {
		{
			r: number,
			across: number,
			x: number,
			z: number,
			radius: number,
			height: number,
		}
	}
)
	-- The Leviathan's Spine lies down the canyon's middle (TrenchDress.luau): basalt
	-- pillars standing in its way go (Air over each, twice)
	for _, pillar in pillars do
		if
			pillar.r > SPINE_CLEAR.from
			and pillar.r < SPINE_CLEAR.to
			and math.abs(pillar.across) < SPINE_CLEAR.half
		then
			for _ = 1, 2 do
				cylinder(
					ops,
					AIR,
					Vector3.new(pillar.x, trench.floorY + pillar.height / 2 + 4, pillar.z),
					math.max(pillar.radius + 6, 18),
					pillar.height + 24
				)
			end
		end
	end

	-- The lair: a cave from the canyon's foot into its wall, its mouth rounded off.
	-- Air ops go in twice (an Air fill takes occupancy away rather than clearing it,
	-- the dens' lesson)
	local angle, width = Seafloor.trenchAxis(LAIR.r)
	local _, _, halfBottom = Seafloor.trenchHalfWidths(width)
	local radial = outward(angle)
	local into = Vector3.new(-radial.Z, 0, radial.X) * LAIR.side
	local x, z = Seafloor.trenchPoint(LAIR.r, LAIR.side * (halfBottom - 4))
	local mouth = Vector3.new(x, trench.floorY + LAIR.rise, z)
	local middle = mouth + into * (LAIR.depth / 2 - 6)
	for _ = 1, 2 do
		cylinder(ops, AIR, middle, LAIR.radius, LAIR.depth, CFrame.fromMatrix(middle, radial, into))
		ball(ops, AIR, mouth, LAIR.radius + 4)
		ball(ops, AIR, mouth + into * (LAIR.depth - 10), LAIR.radius - 2)
	end
	-- (a basalt floor under it, so its eggs sit on rock, not on the cut)
	block(
		ops,
		BASALT,
		CFrame.fromMatrix(middle - Vector3.new(0, LAIR.radius - 3, 0), radial, Vector3.yAxis),
		Vector3.new(LAIR.radius * 1.6, 6, LAIR.depth)
	)
	features.lair = { mouth = mouth, into = into, radius = LAIR.radius, depth = LAIR.depth }

	-- The Blue Hole: the shelf's drum is hollow under its 80-stud top, so the shaft is
	-- lined with rock down into the hollow first and floored, then cut, with a stepped
	-- lip in the sand
	-- (in the reef's most open stretch near its spot: the reef heads Shelf laid stand
	-- round it, not cut through by it)
	local best, bestRoom = at(BLUE_HOLE.angle, BLUE_HOLE.r, 0), -math.huge
	for a = BLUE_HOLE.angle - 25, BLUE_HOLE.angle + 25, 5 do
		for r = BLUE_HOLE.r - 50, BLUE_HOLE.r + 60, 22 do
			local spot = at(a, r, 0)
			local room = math.huge
			for _, list in { features.reefRocks, features.outcrops or {} } do
				for _, rock in list do
					local dx, dz = rock.center.X - spot.X, rock.center.Z - spot.Z
					room = math.min(room, math.sqrt(dx * dx + dz * dz) - rock.radius)
				end
			end
			if room > bestRoom then
				best, bestRoom = spot, room
			end
		end
	end
	local center = best
	local lined = BLUE_HOLE.radius + BLUE_HOLE.lining
	local liningTop, liningBottom = -60, BLUE_HOLE.bottom - 22
	cylinder(
		ops,
		ROCK,
		Vector3.new(center.X, (liningTop + liningBottom) / 2, center.Z),
		lined,
		liningTop - liningBottom
	)
	for _ = 1, 2 do
		cylinder(
			ops,
			AIR,
			Vector3.new(center.X, (8 + BLUE_HOLE.bottom) / 2, center.Z),
			BLUE_HOLE.radius,
			8 - BLUE_HOLE.bottom
		)
		cylinder(ops, AIR, Vector3.new(center.X, -3, center.Z), BLUE_HOLE.radius + 9, 14)
	end
	cylinder(ops, SAND, Vector3.new(center.X, BLUE_HOLE.bottom - 2, center.Z), BLUE_HOLE.radius + 2, 6)
	features.blueHole = { center = center, radius = BLUE_HOLE.radius, bottom = BLUE_HOLE.bottom }
end

function Shelf.ops(): ({ Op }, Features)
	local ops: { Op } = {}
	local rng = Random.new(World.seed + 7)
	local features: Features = { chimneys = {}, pinnacles = {}, chutes = {}, reefRocks = {} }
	local pillars: { { r: number, across: number, x: number, z: number, radius: number, height: number } } =
		{}
	local outcrops: { { center: Vector3, radius: number } } = {}
	features.outcrops = outcrops
	local floor = deep.floorY
	local hubClear = World.hub.radius + World.hub.wallThickness + World.hub.tunnelLength + 20
	local deepInner = shelf.radius + shelf.edge -- the foot of the drop-off
	local far = World.boundsRadius + 700 -- the floor runs past the barrier so it fades into the water, not an edge

	-- The deep floor: a mud slab (the map is big; a solid bedrock would be tens of
	-- millions of voxels). Rock goes under it only where the canyon and the basins
	-- are carved below the floor.
	local slabTop, slabBottom = floor, floor - 30
	cylinder(ops, MUD, Vector3.new(0, (slabTop + slabBottom) / 2, 0), far, slabTop - slabBottom)
	local trenchRockBottom = trench.floorY - 30
	cylinder(
		ops,
		ROCK,
		Vector3.new(trench.center.X, (slabBottom + 2 + trenchRockBottom) / 2, trench.center.Z),
		400,
		slabBottom + 2 - trenchRockBottom
	)
	for _, basin in Seafloor.ventBasins() do
		local bottom = deep.ventsFloorY - 30
		cylinder(
			ops,
			ROCK,
			Vector3.new(basin.x, (slabBottom + 2 + bottom) / 2, basin.z),
			basin.radius + 50,
			slabBottom + 2 - bottom
		)
	end

	-- The shelf: a hollow rock drum (its wall 110 thick, its top 54 thick) with a
	-- sand cap, the rim a little wider than the sand so a rock lip shows at the
	-- drop-off. Nothing can get inside the drum, so the hollow costs nothing to look at.
	local drumTop = -28
	local rim = shelf.radius + 40
	cylinder(ops, ROCK, Vector3.new(0, (floor - 2 + drumTop) / 2, 0), rim, drumTop - (floor - 2))
	cylinder(
		ops,
		AIR,
		Vector3.new(0, (floor + 4 + drumTop - 52) / 2, 0),
		rim - 110,
		(drumTop - 52) - (floor + 4)
	)
	cylinder(ops, SAND, Vector3.new(0, -16, 0), shelf.radius + 20, 32)

	-- The drop-off (owner, 2026-10-19: "The cliff edge needs to be dialed up more and
	-- should have coral etc on it. Right now it's just bulbous spheres off the edge"):
	-- a layered reef wall (dropOff, above), on its own Random. The shared sequence
	-- still takes the draws the old drop-off took (16 rim bulges, 12 bites, 140
	-- notches, 110 face boulders, 40 ledges), so everything after it (the dunes,
	-- outcrops, reef heads, ridges, arches, the Trench, the Vents, the Ruins' mounds
	-- and the Open Blue) keeps its place.
	for _ = 1, 16 * 2 do
		rng:NextNumber()
	end
	for _ = 1, 12 do
		local angle = rng:NextNumber(0, 360)
		if not Seafloor.inSector(angle, trench.angles[1] - 15, trench.angles[2] + 15) then
			rng:NextNumber()
			rng:NextNumber()
		end
	end
	for _ = 1, 140 * 4 + 110 * 4 + 40 * 4 do
		rng:NextNumber()
	end
	dropOff(ops, features)
	-- Sand chutes down the cliff (never through the trench's sector)
	for _, angle in CHUTES do
		local top = at(angle, shelf.radius - 10, -2)
		local foot = at(angle, deepInner + 110, floor + 2)
		local run = foot - top
		local center = (top + foot) / 2
		local frame = CFrame.lookAt(center, center + run.Unit)
		block(ops, SAND, frame, Vector3.new(80, 16, run.Magnitude + 20))
		ball(ops, SAND, foot + Vector3.new(0, -16, 0), 56)
		table.insert(features.chutes, angle)
	end

	-- Shelf relief: dunes everywhere, outcrops where the reef and the wrecks are,
	-- sandstone ridges through the kelp, and reef flats for the corals to sit on
	for _ = 1, 170 do
		local r = rng:NextNumber(hubClear, shelf.radius - 20)
		local radius = rng:NextNumber(24, 72)
		ball(ops, SAND, at(rng:NextNumber(0, 360), r, -radius * 0.8), radius)
	end
	for _ = 1, 70 do
		local angle = rng:NextNumber(0, 360)
		local r = rng:NextNumber(490, shelf.radius - 24)
		local size = Vector3.new(rng:NextNumber(18, 52), rng:NextNumber(10, 28), rng:NextNumber(18, 52))
		local frame = CFrame.new(at(angle, r, -size.Y * 0.35))
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3))
		Cave.pebble(ops, ROCK, frame, size) -- rounded, not a tilted box (owner, 2026-10-11)
		table.insert(outcrops, { center = frame.Position, radius = math.max(size.X, size.Z) / 2 })
	end
	for _ = 1, 26 do
		local angle = rng:NextNumber(0, 360)
		local r = rng:NextNumber(hubClear + 20, 470)
		local size = Vector3.new(rng:NextNumber(70, 160), 12, rng:NextNumber(16, 28))
		Cave.pebble(
			ops,
			SANDSTONE,
			CFrame.new(at(angle, r, -4)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			size
		)
	end
	for _ = 1, 36 do
		local angle = sectorAngle(rng, 225, 135) -- the Coral Reef's band
		local r = rng:NextNumber(500, shelf.radius - 40)
		cylinder(ops, SANDSTONE, at(angle, r, -2), rng:NextNumber(25, 55), 10)
	end
	-- Reef heads: big rocks players swim through and under (owner, 2026-10-07: "larger
	-- rocks that players can swim through and swim under"; 2026-10-08: "more larger
	-- rock structures and arches to go under"): a boulder with a tunnel bored through
	-- it and a hollow underneath, long ridges with swim-throughs, and stone arches
	for _ = 1, 44 do
		local angle = sectorAngle(rng, 228, 132)
		local r = rng:NextNumber(520, shelf.radius - 50)
		local radius = rng:NextNumber(26, 48)
		local center = at(angle, r, radius * 0.45)
		ball(ops, ROCK, center, radius)
		local yaw = rng:NextNumber(0, 6.28)
		local through = CFrame.new(center + Vector3.new(0, -radius * 0.1, 0))
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(0, 0, math.rad(90))
		cylinder(ops, AIR, through.Position, rng:NextNumber(8, 12), radius * 2.4, through)
		ball(ops, AIR, center + Vector3.new(0, -radius * 0.55, 0), radius * 0.55)
		table.insert(features.reefRocks, { center = center, radius = radius })
	end
	for _ = 1, 14 do
		local angle = sectorAngle(rng, 230, 130)
		local r = rng:NextNumber(540, shelf.radius - 60)
		local length = rng:NextNumber(80, 160)
		local height = rng:NextNumber(22, 38)
		local thick = rng:NextNumber(26, 42)
		local yaw = rng:NextNumber(0, 6.28)
		local frame = CFrame.new(at(angle, r, height * 0.35 - 4)) * CFrame.Angles(0, yaw, 0)
		Cave.pebble(ops, ROCK, frame, Vector3.new(length, height, thick))
		ball(ops, ROCK, (frame * CFrame.new(length * 0.4, height * 0.2, 0)).Position, thick * 0.7)
		ball(ops, ROCK, (frame * CFrame.new(-length * 0.4, height * 0.1, 0)).Position, thick * 0.6)
		-- One or two swim-throughs bored across the ridge
		for bore = 1, rng:NextInteger(1, 2) do
			local along = (bore - 1.5) * length * 0.4 + rng:NextNumber(-10, 10)
			local hole = frame * CFrame.new(along, height * 0.1, 0) * CFrame.Angles(math.rad(90), 0, 0)
			cylinder(ops, AIR, hole.Position, rng:NextNumber(8, 11), thick + 30, hole)
		end
		table.insert(features.reefRocks, { center = frame.Position, radius = length / 2 })
	end
	for _ = 1, 26 do
		local angle = sectorAngle(rng, 228, 132)
		local r = rng:NextNumber(520, shelf.radius - 50)
		local yaw = rng:NextNumber(0, 6.28)
		local span = rng:NextNumber(34, 60)
		local height = rng:NextNumber(22, 40)
		local frame = CFrame.new(at(angle, r, 0)) * CFrame.Angles(0, yaw, 0)
		for side = -1, 1, 2 do
			local leg = (frame * CFrame.new(side * span / 2, height / 2 - 4, 0)).Position
			cylinder(ops, ROCK, leg, rng:NextNumber(7, 11), height + 8)
		end
		Cave.pebble(ops, ROCK, frame * CFrame.new(0, height + 2, 0), Vector3.new(span + 20, 11, 16))
	end

	-- The Trench: a winding canyon carved down to its floor in three stepped cuts
	-- (Seafloor.trenchAxis and trenchHalfWidths place them), basalt at the bottom,
	-- bitten walls, slate rims, ledges jutting from the walls and basalt pillars
	-- standing in it
	local steps = 20
	local span = (floor + 10) - (trench.floorY - 10)
	for i = 0, steps do
		local t = i / steps
		local r = trench.radii[1] + t * (trench.radii[2] - trench.radii[1])
		local angle, width = Seafloor.trenchAxis(r)
		local halfTop, halfMid, halfBottom = Seafloor.trenchHalfWidths(width)
		local halves = { halfTop, halfMid, halfBottom }
		for layer = 0, 2 do
			local top = floor + 10 - layer * span / 3
			local bottom = top - span / 3
			local center = at(angle, r, (top + bottom) / 2)
			local frame = CFrame.lookAt(center, center + outward(angle))
			block(ops, AIR, frame, Vector3.new(halves[layer + 1] * 2, top - bottom + 2, 46))
		end
		if i == 0 or i == steps then
			ball(ops, AIR, at(angle, r, (floor + trench.floorY) / 2), halfMid)
		end
		block(
			ops,
			BASALT,
			CFrame.lookAt(at(angle, r, trench.floorY - 6), at(angle, r + 1, trench.floorY - 6)),
			Vector3.new(halfBottom * 2 + 40, 12, 50)
		)
		for side = -1, 1, 2 do
			local acrossDeg = math.deg((rng:NextNumber(halfBottom + 10, halfTop - 24)) / r)
			ball(
				ops,
				AIR,
				at(angle + side * acrossDeg, r, rng:NextNumber(trench.floorY + 30, floor - 50)),
				rng:NextNumber(20, 48)
			)
			local rimDeg = math.deg((halfTop + 14) / r)
			ball(
				ops,
				SLATE,
				at(angle + side * rimDeg, r + rng:NextNumber(-10, 10), floor - 6 + rng:NextNumber(0, 12)),
				rng:NextNumber(16, 34)
			)
		end
	end
	for _ = 1, 12 do
		local r = rng:NextNumber(trench.radii[1] + 40, trench.radii[2] - 40)
		local angle, width = Seafloor.trenchAxis(r)
		local _, halfMid = Seafloor.trenchHalfWidths(width)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local ledge =
			at(angle + side * math.deg((halfMid - 6) / r), r, rng:NextNumber(trench.floorY + 120, floor - 90))
		Cave.pebble(
			ops,
			SLATE,
			CFrame.lookAt(ledge, ledge + outward(angle)) * CFrame.Angles(0, 0, side * math.rad(8)),
			Vector3.new(rng:NextNumber(50, 90), 10, rng:NextNumber(40, 70))
		)
	end
	for _ = 1, 8 do
		local r = rng:NextNumber(trench.radii[1] + 60, trench.radii[2] - 60)
		local _, width = Seafloor.trenchAxis(r)
		local _, _, halfBottom = Seafloor.trenchHalfWidths(width)
		local across = rng:NextNumber(-halfBottom * 0.6, halfBottom * 0.6)
		local x, z = Seafloor.trenchPoint(r, across)
		local height = rng:NextNumber(70, 170)
		local radius = rng:NextNumber(8, 16)
		cylinder(ops, BASALT, Vector3.new(x, trench.floorY + height / 2 - 6, z), radius, height)
		table.insert(pillars, { r = r, across = across, x = x, z = z, radius = radius, height = height })
		ball(ops, BASALT, Vector3.new(x, trench.floorY + height - 8, z), rng:NextNumber(9, 15))
	end

	-- The Vents' basins: hollows sunk below the deep floor, basalt floored, with
	-- chimneys whose caps glow
	for _, basin in Seafloor.ventBasins() do
		local center = Vector3.new(basin.x, 0, basin.z)
		cylinder(
			ops,
			AIR,
			center + Vector3.new(0, (deep.ventsFloorY + floor + 4) / 2, 0),
			basin.radius,
			(floor + 4) - deep.ventsFloorY
		)
		cylinder(ops, BASALT, center + Vector3.new(0, deep.ventsFloorY - 6, 0), basin.radius + 8, 12)
		-- Rubble round the lip
		for _ = 1, 4 do
			local a = rng:NextNumber(0, 6.28)
			ball(
				ops,
				BASALT,
				center
					+ Vector3.new(
						math.cos(a) * (basin.radius + 10),
						floor - 6,
						math.sin(a) * (basin.radius + 10)
					),
				rng:NextNumber(12, 26)
			)
		end
	end
	for _ = 1, 26 do
		local angle = sectorAngle(rng, deep.ventsAngles[1] + 4, deep.ventsAngles[2] - 4)
		local r = rng:NextNumber(deep.ventsRadii[1] + 20, deep.ventsRadii[2] - 20)
		local x, z = at(angle, r, 0).X, at(angle, r, 0).Z
		local base = Seafloor.y(x, z)
		local height = rng:NextNumber(30, 95)
		-- (its radius drawn where it always was, kept for Vents.luau's dressing)
		local radius = rng:NextNumber(5, 12)
		cylinder(ops, BASALT, Vector3.new(x, base + height / 2, z), radius, height)
		ball(ops, LAVA, Vector3.new(x, base + height, z), rng:NextNumber(4, 8))
		table.insert(
			features.chimneys,
			{ position = Vector3.new(x, base, z), height = height, radius = radius }
		)
	end

	-- The Sunken Ruins' ground: buried sandstone mounds out in the biome (none under
	-- the city), then the city's sand plain, its drifts and the courtyard's pit
	-- (ruinsGround). The city and the smaller ruins are parts (Ruins.luau; owner,
	-- 2026-10-18: "Very crude down there"): the Terrain column stubs, plinths, walls
	-- and temple ring that stood here are gone, but their random draws are still
	-- taken, so the Open Blue's ridges and knolls below keep their places.
	local ruinInner, ruinOuter = deepInner + 30, World.boundsRadius - 50
	local city = ruinsFrame(floor)
	for _ = 1, 50 do
		local angle = sectorAngle(rng, 320, 62)
		local r = rng:NextNumber(ruinInner, ruinOuter)
		local radius = rng:NextNumber(18, 44)
		local center = at(angle, r, floor - radius * 0.7)
		if not inCity(city, center, radius) then
			ball(ops, SANDSTONE, center, radius)
		end
	end
	for _ = 1, 40 * 4 + 16 * 3 + 14 * 4 + 3 do
		rng:NextNumber()
	end
	ruinsGround(ops, city, floor)

	-- The Open Blue: long mud ridges, rock knolls and low rock spires on a floor lost
	-- in the blue far below; above it is open ocean (owner, 2026-10-09: "deep blue
	-- where there's no ground or anything just open ocean"), so the spires stay
	-- under ~70 studs and the Megalodon and the sharks keep to the water above
	for _ = 1, 16 do
		local angle = sectorAngle(rng, 228, 312)
		local r = rng:NextNumber(deepInner + 40, World.boundsRadius - 60)
		local radius = rng:NextNumber(60, 120)
		ball(ops, MUD, at(angle, r, floor - radius * 0.85), radius)
	end
	for _ = 1, 4 do
		local angle = sectorAngle(rng, 232, 308)
		local r = rng:NextNumber(deepInner + 80, World.boundsRadius - 120)
		local radius = rng:NextNumber(90, 150)
		ball(ops, ROCK, at(angle, r, floor - radius * 0.6), radius)
	end
	for _ = 1, 7 do
		local angle = sectorAngle(rng, 235, 305)
		local r = rng:NextNumber(deepInner + 90, World.boundsRadius - 120)
		local height = rng:NextNumber(150, 280) * 0.25
		local base = at(angle, r, floor)
		cylinder(ops, ROCK, base + Vector3.new(0, height / 2 - 4, 0), rng:NextNumber(24, 38), height)
		ball(ops, ROCK, base + Vector3.new(0, height * 0.55, 0), rng:NextNumber(30, 44))
		ball(ops, ROCK, base + Vector3.new(0, height - 4, 0), rng:NextNumber(18, 28))
		table.insert(features.pinnacles, base + Vector3.new(0, height, 0))
	end

	-- Debris that slid off the Wreck's side of the shelf: rounded boulders like the
	-- drop-off's talus (they were balls; the turn of each comes from its own Random)
	local tumble = Random.new(World.seed + CLIFF_SEED + 1)
	for _ = 1, 30 do
		local angle = sectorAngle(rng, 135, 225)
		local r = rng:NextNumber(deepInner + 10, deepInner + 130)
		local radius = rng:NextNumber(10, 28)
		Cave.pebble(
			ops,
			if tumble:NextNumber() < 0.7 then ROCK else SLATE,
			CFrame.new(at(angle, r, floor - 4 + radius * 0.45))
				* CFrame.Angles(
					tumble:NextNumber(-0.3, 0.3),
					tumble:NextNumber(0, 6.28),
					tumble:NextNumber(-0.3, 0.3)
				),
			Vector3.new(radius * 2.1, radius * 1.1, radius * 1.7)
		)
	end

	-- The Vents' field between the basins (owner, 2026-10-19: "The vents part of the
	-- map needs more substance too"): the Forge, black-smoker spires, pillow lava,
	-- crust and basalt ridges, laid out by VentsPlan round the chimneys and clear of
	-- every rock already laid (the drop-off's talus, the debris above), and dressed by
	-- Vents.luau. Last, with its own Random (ventsField), so nothing else moves.
	local field = VentsPlan.make(features.chimneys, ops)
	field.opsFrom = #ops + 1
	ventsField(ops, field)
	field.opsTo = #ops
	features.vents = field

	-- The landmarks' own Terrain (owner, 2026-10-21: the biome detail boards), after
	-- everything else so nothing above moves: the Squid's Lair and the Blue Hole
	landmarkOps(ops, features, pillars)

	return ops, features
end

function Shelf.apply(terrain: Terrain, ops: { Op })
	for material, color in Shelf.COLORS do
		Cave.paint(terrain, material, color)
	end
	Cave.apply(terrain, ops)
end

return Shelf
