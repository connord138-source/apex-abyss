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
local DenSpace = require(ReplicatedStorage.Shared.DenSpace)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Cave = require(script.Parent.Cave)

local DenCarve = {}

-- The dens' own rock (Limestone wears Rock's toon plates in the dens' tan; Cave.COLORS)
local DEN_ROCK = Enum.Material.Limestone
local AIR = Enum.Material.Air

-- How much wider than its opening a shaft is cut (Config/Dens Shaft)
DenCarve.SHAFT_CUT = 3

-- Every op for den `index` at `level`
function DenCarve.ops(index: number, level: number): { Cave.Op }
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

	-- 1. The den's whole block back to warm stone
	span(DEN_ROCK, -extent.half, extent.half, extent.bottom, extent.top, extent.front, extent.back, false)

	-- 2. Each open storey, top down (an arch's cylinder reaches far below its own
	-- floor; the rock it cut is put back before the next storey is carved)
	for storey = 1, DenSpace.storeys(level) do
		local s = DenSpace.storey(storey)
		local rooms = DenSpace.rooms(level, storey)
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
	for _, shaft in DenSpace.shafts(level) do
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

-- The ops that take a freed den's block away (it's carved again for its next owner)
function DenCarve.clear(index: number): { Cave.Op }
	local ops: { Cave.Op } = {}
	local frame = DenSpace.frame(index)
	local extent = Layout.DEN_EXTENT
	local size =
		Vector3.new(extent.half * 2 + 8, extent.top - extent.bottom + 8, extent.front - extent.back + 8)
	local middle = DenSpace.spot(frame, 0, (extent.top + extent.bottom) / 2, (extent.front + extent.back) / 2)
	Cave.block(ops, AIR, middle, size)
	return ops
end

return DenCarve
