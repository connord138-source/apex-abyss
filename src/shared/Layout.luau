--!strict
-- Where things are in the hub and the dens: wall segments, den doorways, tunnels,
-- the dens' interiors (each far outside the play area, Config/Dens `interior`),
-- Haul Pools and spawn points. Shared so the server (building, banking, safe zone)
-- and clients (HUD hints) agree.
local Config = require(script.Parent.Config)

local hub = Config.World.hub

export type SegmentKind = "den" | "tunnel" | "wall"

local Layout = {}

-- Per six segments: a tunnel, then den / wall / den / wall / den, so 24 segments
-- give 12 dens and 4 tunnels.
function Layout.segmentKind(segment: number): SegmentKind
	local k = (segment - 1) % 6
	if k == 0 then
		return "tunnel"
	elseif k % 2 == 1 then
		return "den"
	end
	return "wall"
end

-- The angle (radians) of a segment's middle; segment 1 faces +X.
function Layout.segmentAngle(segment: number): number
	return (segment - 1) * 2 * math.pi / hub.segments
end

-- Segments that are dens, in den order.
local denSegments: { number } = {}
for segment = 1, hub.segments do
	if Layout.segmentKind(segment) == "den" then
		table.insert(denSegments, segment)
	end
end
Layout.DEN_COUNT = #denSegments

local function outward(angle: number): Vector3
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

-- Den `index`'s doorway on the plaza (owner, 2026-10-16: private interiors): a
-- round alcove in the cavern wall with a bubble portal at its back. The frame is the
-- portal's middle, facing out into the hub.
local DOOR_BACK = 9 -- the portal stands this far into the wall
local DOOR_Y = 11 -- its middle over the den floor's height
-- A portal takes a fish whose middle comes this close to it (a big fish's body meets
-- the rock behind the portal with its middle ~7 studs off)
local PORTAL_REACH = 8
Layout.DOOR_RADIUS = 9
function Layout.doorFrame(index: number): CFrame
	local radial = outward(Layout.segmentAngle(denSegments[index]))
	local at = hub.center + radial * (hub.radius + DOOR_BACK) + Vector3.new(0, hub.denFloorY + DOOR_Y, 0)
	return CFrame.lookAt(at, at - radial)
end

-- Where a fish comes out into the hub from its den: `out` studs in front of the
-- doorway's portal (EXIT_OUT when not given), facing the plaza
Layout.EXIT_OUT = 16
function Layout.hubExitFrame(index: number, out: number?): CFrame
	return Layout.doorFrame(index) * CFrame.new(0, 0, -(out or Layout.EXIT_OUT))
end

-- How far in front of the portal a fish `length` long comes out: far enough that its
-- camera, at its usual distance behind it (Config/Tuning `camera`; `cameraScale` is
-- the species' Config/Species `camera`), sits out on the plaza clear of the doorway's
-- arch (owner, 2026-10-28: a LV 100 Reef Shark came out 16 studs in front, its camera
-- ~43 studs back stopped at the back of the alcove, and the rock round the hole filled
-- the screen). Never past EXIT_MAX (the plaza's raised centre). DenService steps it
-- back toward the doorway while anything solid is in the way.
local EXIT_ARCH = 6 -- the camera stays this far in front of the cavern wall
Layout.EXIT_MAX = 58
function Layout.exitOut(length: number, cameraScale: number?): number
	local camera = Config.Tuning.camera
	local distance = (camera.baseDistance + camera.perLength * length) * (cameraScale or 1)
	return math.clamp(DOOR_BACK + EXIT_ARCH + distance, Layout.EXIT_OUT, Layout.EXIT_MAX)
end

-- The doorway portal a fish is passing through (its den's index), or nil
function Layout.doorAt(position: Vector3): number?
	local offset = position - hub.center
	local flat = Vector2.new(offset.X, offset.Z).Magnitude
	if flat < hub.radius - 6 or flat > hub.radius + DOOR_BACK + 10 then
		return nil
	end
	local angle = math.atan2(offset.Z, offset.X)
	for index, segment in denSegments do
		local delta = (angle - Layout.segmentAngle(segment) + math.pi) % (2 * math.pi) - math.pi
		if math.abs(delta) <= math.pi / hub.segments then
			local p = Layout.doorFrame(index):PointToObjectSpace(position)
			if p.Z >= -PORTAL_REACH and Vector2.new(p.X, p.Y).Magnitude <= Layout.DOOR_RADIUS + 2 then
				return index
			end
			return nil
		end
	end
	return nil
end

-- Den `index`'s interior (Config/Dens `interior`): its own block of rock far outside
-- the play area at the hub's height. The frame sits on the main floor's middle; its
-- front (LookVector) is the den's front wall, where the way out is.
local Dens = Config.Dens
local interior = Dens.interior
function Layout.denOrigin(index: number): CFrame
	local column = (index - 1) % interior.columns
	local row = (index - 1) // interior.columns
	return CFrame.new(
		interior.x + column * interior.spacing,
		hub.denFloorY,
		interior.z + row * interior.spacing
	)
end

-- A point in den `index`'s own frame (x across, y up, z toward the front wall)
local function denPoint(index: number, x: number, y: number, z: number): CFrame
	return Layout.denOrigin(index) * CFrame.new(x, y, -z)
end

-- The Haul Pool's center (on the Nook's floor, near the front)
function Layout.poolPosition(index: number): Vector3
	return denPoint(index, 0, 1, Dens.pool.z).Position
end

-- Where a fish appears in a den (spawning, or coming in through the doorway): over
-- the pool, facing into the den
function Layout.spawnFrame(index: number): CFrame
	return denPoint(index, 0, 7, Dens.pool.z) * CFrame.Angles(0, math.pi, 0)
end

-- The way out: the portal on the main storey's front wall, facing into the den
function Layout.exitFrame(index: number): CFrame
	local storey = Dens.storeys[1]
	return denPoint(index, 0, storey.deck + Dens.exit.y, Dens.maxFront + Dens.exit.back)
		* CFrame.Angles(0, math.pi, 0)
end

-- How far a den's block reaches round its frame (the rooms plus their walls)
-- (the front reaches past the way out's alcove, Dens.exit `back`, with rock to spare),
-- the widest it can be: Open Plan's rooms, and the longest wing out from the main
-- storey's side wall Open Plan has widened (Shared/DenSpace wingPlans)
local HALF, FRONT, BACK, TOP, BOTTOM = 0, Dens.maxFront + Dens.exit.back + 13, Dens.maxBack - 16, 0, 0
local mainWall = 0
for _, room in Dens.rooms do
	HALF = math.max(HALF, room.x + Dens.openPlan.widen + 16)
	if room.storey == 1 then
		mainWall = math.max(mainWall, room.x + Dens.openPlan.widen)
	end
end
TOP = Dens.storeys[1].ceiling + 16
for _, wing in Dens.wings do
	HALF = math.max(HALF, math.ceil((mainWall + Dens.wing.passage) / 2) * 2 + wing.length + 16)
	TOP = math.max(TOP, wing.ceiling + 16)
end
BOTTOM = Dens.storeys[#Dens.storeys].floor - 16
Layout.DEN_EXTENT = { half = HALF, front = FRONT, back = BACK, top = TOP, bottom = BOTTOM }

-- The den whose interior a position is inside (its index), or nil. The whole house
-- counts, however far an upgrade dug it back and down.
function Layout.denAt(position: Vector3): number?
	local column = math.floor((position.X - interior.x) / interior.spacing + 0.5)
	local row = math.floor((position.Z - interior.z) / interior.spacing + 0.5)
	if column < 0 or column >= interior.columns or row < 0 then
		return nil
	end
	local index = row * interior.columns + column + 1
	if index > Layout.DEN_COUNT then
		return nil
	end
	local origin = Layout.denOrigin(index).Position
	local x, y, z = position.X - origin.X, position.Y - origin.Y, origin.Z - position.Z
	if math.abs(x) > HALF or z > FRONT or z < BACK or y > TOP or y < BOTTOM then
		return nil
	end
	return index
end

-- The way out a fish inside a den is passing through (its den's index), or nil
function Layout.exitAt(position: Vector3): number?
	local index = Layout.denAt(position)
	if index == nil then
		return nil
	end
	local p = Layout.exitFrame(index):PointToObjectSpace(position)
	if p.Z >= -PORTAL_REACH and Vector2.new(p.X, p.Y).Magnitude <= Dens.exit.radius + 2 then
		return index
	end
	return nil
end

-- Where a position shows on the map: a fish in a den shows at its doorway
function Layout.mapPosition(position: Vector3): Vector3
	local index = Layout.denAt(position)
	if index then
		return Layout.doorFrame(index).Position
	end
	return position
end

-- The vendor stalls stand round the plaza's beacon (Config/Shop `angle`).
Layout.PLAZA_TOP = 1.5
Layout.COUNTER_RADIUS = 33
Layout.COUNTER_SIZE = Vector3.new(12, 3.6, 3.5)

-- The middle of a stall's counter, for the server's reach check and the client's
-- "E · Shop" hint (which works out where the stalls are without the parts, since
-- they may not have streamed in).
function Layout.counterPosition(angleDegrees: number): Vector3
	return hub.center
		+ outward(math.rad(angleDegrees)) * Layout.COUNTER_RADIUS
		+ Vector3.new(0, Layout.PLAZA_TOP + Layout.COUNTER_SIZE.Y / 2, 0)
end

-- How far a point is from a stall's counter (0 inside it): measured to the box, so
-- the long counter is as easy to reach from its ends and back as from its front.
function Layout.counterDistance(angleDegrees: number, point: Vector3): number
	local center = Layout.counterPosition(angleDegrees)
	local radial = outward(math.rad(angleDegrees))
	local frame = CFrame.lookAt(center, center - radial)
	local localPoint = frame:PointToObjectSpace(point)
	local half = Layout.COUNTER_SIZE / 2
	local closest = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	return (localPoint - closest).Magnitude
end

-- Whether a position is inside the hub (the cavern, its doorways and tunnels) or a
-- den's interior, where nobody can be eaten.
-- The parts that make the hub (under World.Hub, within the seamount's reach of the
-- centre: the plaza, doorways, stalls, the wheel, the exits' dressing; never a den's
-- far interior). The server publishes its count (World.Hub `PlazaParts`) and a
-- client leaving its den waits until it has nearly all of them.
local HUB_REACH = 210
function Layout.hubParts(folder: Instance): number
	local count = 0
	for _, item in folder:GetDescendants() do
		if item:IsA("BasePart") then
			local offset = item.Position - hub.center
			if Vector2.new(offset.X, offset.Z).Magnitude < HUB_REACH and offset.Y < hub.height + 60 then
				count += 1
			end
		end
	end
	return count
end

function Layout.inHub(position: Vector3): boolean
	local offset = position - hub.center
	local flat = Vector2.new(offset.X, offset.Z).Magnitude
	if offset.Y < hub.height + 4 and flat < hub.radius + hub.wallThickness + hub.tunnelLength * 0.5 then
		return true
	end
	return Layout.denAt(position) ~= nil
end

return Layout
