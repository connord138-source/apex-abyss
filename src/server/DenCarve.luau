--!strict
-- A den's rock (Config/Dens, Shared/DenSpace) as Terrain fill ops, like Cave.luau.
-- Since 2026-10-16 every den is its own interior far outside the play area (owner:
-- "Dens also still need to be substantially bigger"; Layout.denOrigin): first the
-- den's whole block goes back to warm stone (so a den changing hands, or an old
-- save's shape, starts clean), then each open storey's rooms are carved: upright
-- walls `wall` studs high under a shallow arch (a cylinder along the room whose chord
-- at the walls' top is the room's width and whose crown is the ceiling), with
-- alcoves bulging out of the walls, and the shafts drop between the storeys.
-- DenBuilder applies the ops; tools/preview/run_dens.sh checks and draws them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DensConfig = require(ReplicatedStorage.Shared.Config.Dens)
local DenSpace = require(ReplicatedStorage.Shared.DenSpace)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Cave = require(script.Parent.Cave)

local DenCarve = {}

-- The dens' own rock (Limestone wears Rock's toon plates in the dens' tan; Cave.COLORS)
local DEN_ROCK = Enum.Material.Limestone
local AIR = Enum.Material.Air

-- How much wider than its opening a shaft is cut (Config/Dens Shaft)
DenCarve.SHAFT_CUT = 3

-- The Observatory's window (2026-10-28): the rock past its far wall goes, leaving
-- WINDOW_WALL studs, and a round window WINDOW_RADIUS across is cut through it with
-- its middle WINDOW_Y over the deck; outside, a sand floor SEA_FLOOR studs under the
-- deck reaches SEA_REACH out (the client swims a deep-sea diorama past it). The bore
-- is WINDOW_BORE across, flaring to WINDOW_FLARE from 5 studs into the wall: Terrain draws a
-- round cut as a rounded square in 4-stud voxels, so it's cut wider than the glass
-- and DenWings' stone bezel covers its edge (PC 2026-11-02: rock showed between the
-- brass ring and a squarish opening). The floor sat 40 under the deck, out of sight
-- through the window, so the view read as plain blue water.
DenCarve.WINDOW_WALL = 8
DenCarve.WINDOW_RADIUS = 14
DenCarve.WINDOW_BORE = 18
DenCarve.WINDOW_FLARE = 23
DenCarve.WINDOW_Y = 19
DenCarve.SEA_FLOOR = 16
DenCarve.SEA_REACH = 150

-- The water outside either side of a den, where an Observatory looks out: cleared
-- before a den is carved and when it's freed (a sand floor left from an old
-- Observatory would hang there)
local function outside(ops: { Cave.Op }, index: number)
	local frame = DenSpace.frame(index)
	local extent = Layout.DEN_EXTENT
	local front, back = -math.huge, math.huge
	for _, slot in Config.Dens.wingSlots do
		front = math.max(front, slot.z + 130)
		back = math.min(back, slot.z - 130)
	end
	local reach = DenCarve.SEA_REACH + 16
	for _, side in { -1, 1 } do
		local x = side * (extent.half + reach / 2)
		local y = (extent.top + extent.bottom) / 2 - 20
		Cave.block(
			ops,
			AIR,
			DenSpace.spot(frame, x, y, (front + back) / 2),
			Vector3.new(reach, extent.top - extent.bottom + 60, front - back)
		)
	end
end

-- Every op for den `index` in `shape` (its level, wings and Open Plan)
function DenCarve.ops(index: number, shapeArg: DenSpace.ShapeArg): { Cave.Op }
	local shape = DenSpace.shapeOf(shapeArg)
	local ops: { Cave.Op } = {}
	local frame = DenSpace.frame(index)
	local extent = Layout.DEN_EXTENT
	local function at(x: number, y: number, z: number): Vector3
		return DenSpace.spot(frame, x, y, z).Position
	end
	-- A box in the den's frame between two corners (x across, y up, z from the
	-- front edge back), cut down to the den's block when `clip` is set: the arches
	-- reach well outside it, but outside the block there's only open water anyway
	local function span(
		material: Enum.Material,
		x0: number,
		x1: number,
		y0: number,
		y1: number,
		front: number,
		back: number,
		clip: boolean
	)
		if clip then
			x0, x1 = math.max(x0, -extent.half), math.min(x1, extent.half)
			y0, y1 = math.max(y0, extent.bottom), math.min(y1, extent.top)
			front, back = math.min(front, extent.front), math.max(back, extent.back)
		end
		if x1 <= x0 or y1 <= y0 or front <= back then
			return
		end
		Cave.block(
			ops,
			material,
			DenSpace.spot(frame, (x0 + x1) / 2, (y0 + y1) / 2, (front + back) / 2),
			Vector3.new(x1 - x0, y1 - y0, front - back)
		)
	end
	local along = -frame.LookVector -- +z in the den is toward the front wall; this runs back
	local rng = Random.new(Config.World.seed + 31 * index)
	-- Every Air op cut twice: Terrain's Air fills take occupancy away rather than
	-- clearing it, so one pass over fresh rock leaves voxels the shape only partly
	-- covers ~0.2 full, enough to plug a shaft or poke up through a deck (playtest
	-- 2026-10-13: both shafts read solid after one cut, clear after two)
	local function twice(from: number)
		for i = from, #ops do
			table.insert(ops, ops[i])
		end
	end

	-- 1. The den's whole block back to warm stone, the water either side clear
	local cleared = #ops + 1
	outside(ops, index)
	twice(cleared)
	span(DEN_ROCK, -extent.half, extent.half, extent.bottom, extent.top, extent.front, extent.back, false)

	-- 2. Each open storey, top down (an arch's cylinder reaches far below its own
	-- floor; the rock it cut is put back before the next storey is carved)
	local right = frame.RightVector -- +x across the den
	for storey = 1, DenSpace.storeys(shape) do
		local s = DenSpace.storey(storey)
		local rooms: { DensConfig.Room } = {}
		for _, room in DenSpace.rooms(shape, storey) do
			if room.wing == nil then
				table.insert(rooms, room)
			end
		end
		local wallTop = s.deck + s.wall
		-- a. The arches
		local first = #ops + 1
		for _, room in rooms do
			local radius = DenSpace.archRadius(room)
			Cave.cylinder(
				ops,
				AIR,
				at(0, s.ceiling - radius, (room.z0 + room.z1) / 2),
				along,
				room.z0 - room.z1,
				radius
			)
		end
		twice(first)
		-- b. What the arches cut too far goes back: beside the walls up to their top,
		-- and under the rock floor
		for _, room in rooms do
			local radius = DenSpace.archRadius(room)
			local bottom = s.ceiling - 2 * radius - 2
			span(DEN_ROCK, room.x, radius + 2, bottom, wallTop, room.z0, room.z1, true)
			span(DEN_ROCK, -radius - 2, -room.x, bottom, wallTop, room.z0, room.z1, true)
			span(DEN_ROCK, -radius - 2, radius + 2, bottom, s.floor, room.z0, room.z1, true)
		end
		-- c. The rooms, from the rock floor (a voxel or more under the deck: Config/Dens
		-- storeys) up to where the arch meets the walls
		first = #ops + 1
		for _, room in rooms do
			span(AIR, -room.x, room.x, s.floor, wallTop + 1, room.z0, room.z1, false)
		end
		twice(first)
		-- d. Alcoves bulging out of the walls, so it reads as a cave
		for _, room in rooms do
			local length = room.z0 - room.z1
			for _ = 1, math.max(2, math.floor(length / 12)) do
				local side = if rng:NextNumber() < 0.5 then -1 else 1
				local z = rng:NextNumber(room.z1 + 6, room.z0 - 6)
				local y = rng:NextNumber(s.deck + 5, wallTop - 4)
				local r = rng:NextNumber(3.5, 5.5)
				Cave.ball(ops, AIR, at(side * (room.x + r * 0.35), y, z), r)
			end
		end
		if storey == 1 then
			DenCarve.wings(ops, shape, frame, right, span, twice, rng)
		end
	end

	-- The way out's alcove in the main storey's front wall (Config/Dens `exit`), cut
	-- like a doorway on the plaza (Cave.denDoor): a round tunnel to just behind the
	-- portal and a flat sill from the rock floor (DenDoor lays a threshold over it,
	-- level with the deck)
	do
		local exit = Config.Dens.exit
		local s = DenSpace.storey(1)
		local middle = s.deck + exit.y
		local inner = Config.Dens.maxFront - 12 -- (inside the room: air already)
		local outer = Config.Dens.maxFront + exit.back + 1 -- just behind the portal
		local cut = #ops + 1
		Cave.cylinder(ops, AIR, at(0, middle, (inner + outer) / 2), along, outer - inner, exit.alcove)
		span(AIR, -9, 9, s.floor, s.floor + 12, outer, inner, false)
		twice(cut)
	end

	-- 3. The shafts between the storeys, cut wider than their openings (a slanted
	-- cylinder clears a good deal less than its radius of 4-stud voxels) and on well
	-- into the vault below (cut only to its ceiling, a voxel of rock stayed)
	local first = #ops + 1
	for _, shaft in DenSpace.shafts(shape) do
		local top = DenSpace.storey(shaft.from).floor + 1
		local bottom = DenSpace.storey(shaft.to).ceiling - 6
		Cave.cylinder(
			ops,
			AIR,
			at(0, (top + bottom) / 2, shaft.z),
			Vector3.yAxis,
			top - bottom,
			shaft.radius + DenCarve.SHAFT_CUT
		)
	end
	twice(first)
	return ops
end

-- The wings (Config/Dens wings, Shared/DenSpace wingPlans), carved after the main
-- storey's own rooms the same three ways round: each passage's and wing's arch (a
-- cylinder running out along x), the rock the arches cut too far put back beside
-- their long walls and under their floors (only outside the house's wall, so none
-- comes back into the house), then the rooms themselves; a passage reaches 3 studs
-- into the house so the two join. The Observatory's far wall is left thin, with the
-- sea beyond it and a round window through it.
type Span = (
	material: Enum.Material,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	front: number,
	back: number,
	clip: boolean
) -> ()
function DenCarve.wings(
	ops: { Cave.Op },
	shape: DenSpace.Shape,
	frame: CFrame,
	right: Vector3,
	span: Span,
	twice: (from: number) -> (),
	rng: Random
)
	local plans = DenSpace.wingPlans(shape)
	if #plans == 0 then
		return
	end
	local s = DenSpace.storey(1)
	local function at(x: number, y: number, z: number): Vector3
		return DenSpace.spot(frame, x, y, z).Position
	end
	-- A room's x range (signed, low to high), and the part of it outside the house
	local function range(plan: DenSpace.WingPlan, room: DensConfig.Room, outer: boolean): (number, number)
		local a, b
		if room.passage then
			a, b = if outer then plan.wall else plan.wall - 3, plan.x1
		else
			a, b = plan.x1, plan.x2
		end
		if plan.side > 0 then
			return a, b
		end
		return -b, -a
	end
	-- a. The arches
	local first = #ops + 1
	for _, plan in plans do
		for _, room in { plan.passage, plan.room } do
			local radius = DenSpace.archRadius(room)
			local _, ceiling = DenSpace.wallOf(room)
			local lo, hi = range(plan, room, false)
			Cave.cylinder(ops, AIR, at((lo + hi) / 2, ceiling - radius, plan.z), right, hi - lo, radius)
		end
	end
	twice(first)
	-- b. Rock back beside the long walls and under the floor, outside the house
	for _, plan in plans do
		for _, room in { plan.passage, plan.room } do
			local radius = DenSpace.archRadius(room)
			local wall, ceiling = DenSpace.wallOf(room)
			local wallTop = s.deck + wall
			local bottom = ceiling - 2 * radius - 2
			local lo, hi = range(plan, room, true)
			span(DEN_ROCK, lo, hi, bottom, wallTop, plan.z + radius + 2, room.z0, true)
			span(DEN_ROCK, lo, hi, bottom, wallTop, room.z1, plan.z - radius - 2, true)
			span(DEN_ROCK, lo, hi, bottom, s.floor, plan.z + radius + 2, plan.z - radius - 2, true)
		end
	end
	-- c. The rooms, from the rock floor to where their arches meet their walls
	first = #ops + 1
	for _, plan in plans do
		for _, room in { plan.passage, plan.room } do
			local wall = DenSpace.wallOf(room)
			local lo, hi = range(plan, room, false)
			span(AIR, lo, hi, s.floor, s.deck + wall + 1, room.z0, room.z1, false)
		end
	end
	twice(first)
	-- d. A few alcoves bulging out of each wing's long walls
	for _, plan in plans do
		local room = plan.room
		local wall = DenSpace.wallOf(room)
		for _ = 1, math.max(2, math.floor(plan.def.length / 16)) do
			local edge = if rng:NextNumber() < 0.5 then room.z0 else room.z1
			local out = if edge == room.z0 then 1 else -1
			local x = plan.side * rng:NextNumber(plan.x1 + 6, plan.x2 - 6)
			local y = rng:NextNumber(s.deck + 5, s.deck + wall - 4)
			local r = rng:NextNumber(3.5, 5.5)
			Cave.ball(ops, AIR, at(x, y, edge + out * r * 0.35), r)
		end
	end
	-- e. The Observatory's window onto the sea
	for _, plan in plans do
		if plan.def.id ~= "Observatory" then
			continue
		end
		local extent = Layout.DEN_EXTENT
		local far = plan.x2
		local beyond = far + DenCarve.WINDOW_WALL
		local half = plan.def.depth / 2 + 12
		first = #ops + 1
		local lo, hi = beyond, extent.half + DenCarve.SEA_REACH + 8
		if plan.side < 0 then
			lo, hi = -hi, -lo
		end
		span(AIR, lo, hi, extent.bottom - 30, extent.top + 30, plan.z + half, plan.z - half, false)
		Cave.cylinder(
			ops,
			AIR,
			at(plan.side * (far + DenCarve.WINDOW_WALL / 2), s.deck + DenCarve.WINDOW_Y, plan.z),
			right,
			DenCarve.WINDOW_WALL + 6,
			DenCarve.WINDOW_BORE
		)
		-- (its sea-side half flared, so the bore's sides don't close in on the view)
		Cave.cylinder(
			ops,
			AIR,
			at(plan.side * (far + DenCarve.WINDOW_WALL / 2 + 5), s.deck + DenCarve.WINDOW_Y, plan.z),
			right,
			DenCarve.WINDOW_WALL,
			DenCarve.WINDOW_FLARE
		)
		twice(first)
		-- A sand floor out there, and a few rounded rocks on it
		local seaY = s.deck - DenCarve.SEA_FLOOR
		local x0, x1 = beyond + 4, beyond + DenCarve.SEA_REACH
		local slo, shi = if plan.side > 0 then x0 else -x1, if plan.side > 0 then x1 else -x0
		span(Enum.Material.Sand, slo, shi, seaY - 10, seaY, plan.z + 110, plan.z - 110, false)
		local seaRng = Random.new(Config.World.seed + 977)
		-- Tall rock stacks in the window's view, 30-90 out, so the eye has something to
		-- read the water against (each two pebbles, the top one smaller and leaning)
		for k = 1, 4 do
			local out = x0 + 26 + (k - 1) * 18 + seaRng:NextNumber(-4, 4)
			local z = plan.z + (if k % 2 == 0 then 1 else -1) * seaRng:NextNumber(14, 34)
			local height = seaRng:NextNumber(24, 40)
			local width = seaRng:NextNumber(12, 18)
			local turn = CFrame.Angles(0, seaRng:NextNumber(0, math.pi), 0)
			Cave.pebble(
				ops,
				Enum.Material.Rock,
				DenSpace.spot(frame, plan.side * out, seaY + height * 0.32, z) * turn,
				Vector3.new(width, height * 0.7, width * 0.85)
			)
			Cave.pebble(
				ops,
				Enum.Material.Rock,
				DenSpace.spot(frame, plan.side * out, seaY + height * 0.72, z)
					* turn
					* CFrame.Angles(seaRng:NextNumber(-0.25, 0.25), 0, seaRng:NextNumber(-0.25, 0.25)),
				Vector3.new(width * 0.7, height * 0.45, width * 0.6)
			)
		end
		for _ = 1, 7 do
			local x = plan.side * seaRng:NextNumber(x0 + 25, x1 - 15)
			local z = plan.z + seaRng:NextNumber(-90, 90)
			local size =
				Vector3.new(seaRng:NextNumber(10, 26), seaRng:NextNumber(6, 16), seaRng:NextNumber(10, 22))
			Cave.pebble(
				ops,
				Enum.Material.Rock,
				DenSpace.spot(frame, x, seaY + size.Y * 0.3, z)
					* CFrame.Angles(0, seaRng:NextNumber(0, math.pi), 0),
				size
			)
		end
	end
end

-- The ops that take a freed den's block away (it's carved again for its next owner)
function DenCarve.clear(index: number): { Cave.Op }
	local ops: { Cave.Op } = {}
	outside(ops, index)
	local frame = DenSpace.frame(index)
	local extent = Layout.DEN_EXTENT
	local size =
		Vector3.new(extent.half * 2 + 8, extent.top - extent.bottom + 8, extent.front - extent.back + 8)
	local middle = DenSpace.spot(frame, 0, (extent.top + extent.bottom) / 2, (extent.front + extent.back) / 2)
	Cave.block(ops, AIR, middle, size)
	return ops
end

return DenCarve
