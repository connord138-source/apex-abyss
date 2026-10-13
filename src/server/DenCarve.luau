--!strict
-- A den's rock (Config/Dens, Shared/DenSpace) as Terrain fill ops, like Cave.luau:
-- first the whole house's zone goes back to warm stone (so a den changing hands, or
-- an old save's shape, starts clean), then the main room is carved again as the
-- cavern made it, the Burrow runs it back, and each open storey below is a barrel
-- vault (a cylinder along the room, its top at the ceiling) with its floor put back
-- under the deck, and the shafts drop between them. DenBuilder applies the ops; the
-- cloud preview (tools/preview/run_cave.sh, DENS=<level>) draws them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DenSpace = require(ReplicatedStorage.Shared.DenSpace)
local Cave = require(script.Parent.Cave)

local Dens = Config.Dens

local DenCarve = {}

local SANDSTONE = Enum.Material.Sandstone
local AIR = Enum.Material.Air

-- The Burrow's run back from the Nook (the main storey)
local BURROW = { x = 11, z0 = -12, z1 = -38, height = 22 }

-- Every op for den `index` at `level`
function DenCarve.ops(index: number, level: number): { Cave.Op }
	local ops: { Cave.Op } = {}
	local frame = DenSpace.frame(index)
	local function at(x: number, y: number, z: number): Vector3
		return DenSpace.spot(frame, x, y, z).Position
	end
	-- A box in the den's frame (x, y, z its middle; size across, up, along)
	local function box(material: Enum.Material, x: number, y: number, z: number, size: Vector3)
		Cave.block(ops, material, DenSpace.spot(frame, x, y, z), size)
	end
	local along = -frame.LookVector -- +z in the den is toward the hub; this runs back
	local rng = Random.new(Config.World.seed + 31 * index)

	-- 1. Back to stone: the Burrow's zone, every lower room with a margin (5 studs
	-- inside the line to the next den, so never into a neighbour), and the shafts
	box(SANDSTONE, 0, 13, -31, Vector3.new(30, 34, 26))
	for _, room in Dens.rooms do
		if room.storey > 1 then
			local s = DenSpace.storey(room.storey)
			local bottom = s.ceiling - 2 * room.x - 4
			local top = s.ceiling + 3
			box(
				SANDSTONE,
				0,
				(bottom + top) / 2,
				(room.z0 + room.z1) / 2,
				Vector3.new(2 * room.x + 8, top - bottom, room.z0 - room.z1 + 6)
			)
		end
	end
	for _, shaft in Dens.shafts do
		local top = DenSpace.storey(shaft.from).floor
		local bottom = DenSpace.storey(shaft.to).ceiling - 2
		Cave.cylinder(
			ops,
			SANDSTONE,
			at(0, (top + bottom) / 2, shaft.z),
			Vector3.yAxis,
			top - bottom,
			shaft.radius + 2
		)
	end

	-- 2. The main room as the cavern carved it, its floor, then the Burrow
	Cave.denRoom(ops, index)
	if level >= 2 then
		box(
			AIR,
			0,
			BURROW.height / 2,
			(BURROW.z0 + BURROW.z1) / 2,
			Vector3.new(BURROW.x * 2, BURROW.height, BURROW.z0 - BURROW.z1)
		)
		-- A rounded roof and back
		for _, z in { -16, -24, -32 } do
			Cave.ball(ops, AIR, at(0, 17, z), 9.5)
		end
		Cave.ball(ops, AIR, at(0, 12, -35), 7)
	end
	Cave.denFloor(ops, index)
	if level >= 2 then
		box(SANDSTONE, 0, -4, (BURROW.z0 + BURROW.z1) / 2 - 2, Vector3.new(30, 8, BURROW.z0 - BURROW.z1 + 8))
	end

	-- 3. The storeys below: barrel vaults, roughened, their floors put back under
	-- the decks (the barrel's lower half runs below the floor)
	for storey = 2, DenSpace.storeys(level) do
		local s = DenSpace.storey(storey)
		for _, room in DenSpace.rooms(level, storey) do
			local length = room.z0 - room.z1
			local mid = (room.z0 + room.z1) / 2
			Cave.cylinder(ops, AIR, at(0, s.ceiling - room.x, mid), along, length, room.x)
			-- Alcoves and bulges along the walls so it reads as a cave, kept inside
			-- the room's margin
			for _ = 1, math.max(2, math.floor(length / 10)) do
				local side = if rng:NextNumber() < 0.5 then -1 else 1
				local z = rng:NextNumber(room.z1 + 4, room.z0 - 4)
				local y = rng:NextNumber(s.deck + 4, s.deck + 10)
				local r = rng:NextNumber(3, 4.5)
				-- On the barrel's wall at that height, bulging out at most a stud past
				-- the room's half-width
				local wall = math.sqrt(math.max(room.x * room.x - (y - (s.ceiling - room.x)) ^ 2, 0))
				Cave.ball(ops, AIR, at(side * math.min(wall + r * 0.3, room.x - r + 1), y, z), r)
			end
		end
		for _, room in DenSpace.rooms(level, storey) do
			local bottom = s.ceiling - 2 * room.x - 2
			box(
				SANDSTONE,
				0,
				(bottom + s.floor) / 2,
				(room.z0 + room.z1) / 2,
				Vector3.new(2 * room.x + 4, s.floor - bottom, room.z0 - room.z1)
			)
		end
	end

	-- 4. The shafts between the storeys
	for _, shaft in DenSpace.shafts(level) do
		local top = DenSpace.storey(shaft.from).floor + 1
		local bottom = DenSpace.storey(shaft.to).ceiling - 2
		Cave.cylinder(ops, AIR, at(0, (top + bottom) / 2, shaft.z), Vector3.yAxis, top - bottom, shaft.radius)
	end
	return ops
end

-- The ops a den goes back to when it's freed (a plain Nook)
function DenCarve.reset(index: number): { Cave.Op }
	return DenCarve.ops(index, 1)
end

return DenCarve
