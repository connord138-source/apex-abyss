--!strict
-- Where things are in the hub: wall segments, dens, tunnels, Haul Pools and spawn
-- points. Shared so the server (building, banking, safe zone) and clients (HUD
-- hints) agree.
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

-- A frame at the middle of den `index`'s floor-level room, facing out into the hub.
function Layout.denFrame(index: number): CFrame
	local angle = Layout.segmentAngle(denSegments[index])
	local radial = outward(angle)
	local middle = hub.center
		+ radial * (hub.radius + hub.denDepth / 2)
		+ Vector3.new(0, hub.denFloorY + hub.denHeight / 2, 0)
	return CFrame.lookAt(middle, middle - radial)
end

-- The Haul Pool's center (on the den floor, toward the back).
function Layout.poolPosition(index: number): Vector3
	local angle = Layout.segmentAngle(denSegments[index])
	return hub.center
		+ outward(angle) * (hub.radius + hub.denDepth * 0.62)
		+ Vector3.new(0, hub.denFloorY + 1, 0)
end

-- Where a fish appears: in its den, facing the hub.
function Layout.spawnFrame(index: number): CFrame
	local frame = Layout.denFrame(index)
	return frame * CFrame.new(0, 0, -hub.denDepth * 0.1)
end

-- Whether a position is inside the hub (the cavern, its dens or its tunnels), where
-- nobody can be eaten.
function Layout.inHub(position: Vector3): boolean
	local offset = position - hub.center
	local flat = Vector2.new(offset.X, offset.Z).Magnitude
	return offset.Y < hub.height + 4 and flat < hub.radius + hub.wallThickness + hub.tunnelLength * 0.5
end

return Layout
