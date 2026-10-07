--!strict
-- The hub cavern as Roblox Terrain (owner, 2026-10-07: "needs to actually resemble a
-- cave/cavern, not just straight flat edges and walls everywhere"). A seamount of
-- rock is filled, then the cavern, its dome and oculus, twelve den rooms with round
-- doorways and four tunnels are carved out, and the walls are roughened with
-- alcoves, bulges and hanging knobs. Everything is a list of fill operations, so the
-- same list runs in Studio (Terrain:Fill*) and in the cloud preview
-- (tools/preview/run_cave.sh voxelizes it and renders it in Blender).
--
-- Layout numbers (where dens, pools, tunnels and the oculus are) come from
-- Config/World and Shared/Layout, so the gameplay code keeps working unchanged.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)

local World = Config.World
local hub = World.hub

export type Op = {
	kind: "ball" | "block" | "cylinder",
	material: Enum.Material,
	center: Vector3,
	radius: number?, -- ball, cylinder
	height: number?, -- cylinder (along its axis)
	size: Vector3?, -- block
	cframe: CFrame?, -- block, cylinder (the cylinder's axis is its Y)
}

local Cave = {}

-- Terrain material colors: the concept's cool teal-grey stone, a darker dome, warm
-- den rooms and pale sand (WorldService applies these at start).
Cave.COLORS = {
	[Enum.Material.Rock] = Color3.fromRGB(96, 122, 130),
	[Enum.Material.Slate] = Color3.fromRGB(70, 92, 104),
	[Enum.Material.Sandstone] = Color3.fromRGB(150, 138, 118),
	[Enum.Material.Sand] = Color3.fromRGB(206, 194, 156),
	[Enum.Material.Basalt] = Color3.fromRGB(62, 74, 84),
}

local ROCK = Enum.Material.Rock
local SLATE = Enum.Material.Slate
local SANDSTONE = Enum.Material.Sandstone
local SAND = Enum.Material.Sand
local BASALT = Enum.Material.Basalt
local AIR = Enum.Material.Air

-- The cavern's shape: vertical walls to WALL_TOP, then a dome whose top is hub.height
local WALL_TOP = 55
local DOME_RADIUS = 97
local DOME_CENTER_Y = hub.height - DOME_RADIUS
local MOUND_TOP = hub.height - 2 -- the drum's flat top; the dome cap rises above it
local DEN_FLOOR = hub.denFloorY
local TUNNEL_RADIUS = hub.tunnelHeight / 2 - 2

local function ball(ops: { Op }, material: Enum.Material, center: Vector3, radius: number)
	table.insert(ops, { kind = "ball", material = material, center = center, radius = radius })
end

local function block(ops: { Op }, material: Enum.Material, cframe: CFrame, size: Vector3)
	table.insert(
		ops,
		{ kind = "block", material = material, center = cframe.Position, size = size, cframe = cframe }
	)
end

-- A cylinder whose axis runs along `axis` (unit) through `center`.
local function cylinder(
	ops: { Op },
	material: Enum.Material,
	center: Vector3,
	axis: Vector3,
	height: number,
	radius: number
)
	local up = axis
	local reference = if math.abs(up.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local right = reference:Cross(up).Unit
	local back = right:Cross(up)
	local cframe = CFrame.fromMatrix(center, right, up, back)
	table.insert(ops, {
		kind = "cylinder",
		material = material,
		center = center,
		radius = radius,
		height = height,
		cframe = cframe,
	})
end

local function outward(angle: number): Vector3
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

-- A point at `r` from the hub's center along `angle`, `y` up.
local function at(angle: number, r: number, y: number): Vector3
	return hub.center + outward(angle) * r + Vector3.new(0, y, 0)
end

-- Whether an angle (radians) is within `margin` of a den's or tunnel's middle.
local function nearOpening(angle: number, margin: number): boolean
	for segment = 1, hub.segments do
		if Layout.segmentKind(segment) ~= "wall" then
			local delta = (angle - Layout.segmentAngle(segment) + math.pi) % (2 * math.pi) - math.pi
			if math.abs(delta) < margin then
				return true
			end
		end
	end
	return false
end

-- Every fill, in order: fill the rock, carve the rooms, then put the floors back.
function Cave.ops(): { Op }
	local ops: { Op } = {}
	local rng = Random.new(World.seed + 7)
	local center = hub.center

	-- 1. The seamount: terraces of rock, widest at the foot (the den rooms sit inside
	-- the lowest), stepping in with height under a domed cap. Each terrace is a few
	-- offset drums so its outline wavers, and its shelf is broken up with tilted
	-- slabs and angular blocks (facets, not bubbles)
	local terraces = {
		{ y0 = -8, y1 = 36, r = hub.radius + hub.denDepth + 18 },
		{ y0 = 36, y1 = 68, r = 132 },
		{ y0 = 68, y1 = 92, r = 120 },
		{ y0 = 92, y1 = MOUND_TOP, r = 108 },
	}
	for _, terrace in terraces do
		local height = terrace.y1 - terrace.y0
		local mid = terrace.y0 + height / 2
		cylinder(ops, ROCK, center + Vector3.new(0, mid, 0), Vector3.yAxis, height, terrace.r - 6)
		for i = 1, 4 do
			local angle = (i / 4) * 2 * math.pi + rng:NextNumber(-0.4, 0.4)
			local shift = rng:NextNumber(6, 14)
			cylinder(
				ops,
				ROCK,
				at(angle, shift, mid),
				Vector3.yAxis,
				height - rng:NextNumber(0, 6),
				terrace.r - 6 + rng:NextNumber(-4, 6)
			)
		end
		for i = 1, 18 do
			local angle = (i / 18) * 2 * math.pi + rng:NextNumber(-0.15, 0.15)
			local spot = at(angle, terrace.r - rng:NextNumber(2, 12), terrace.y1 + rng:NextNumber(-4, 3))
			local size = Vector3.new(rng:NextNumber(10, 22), rng:NextNumber(5, 10), rng:NextNumber(8, 16))
			local tilt = CFrame.Angles(
				rng:NextNumber(-0.25, 0.25),
				angle + rng:NextNumber(-0.5, 0.5),
				rng:NextNumber(-0.25, 0.25)
			)
			block(ops, ROCK, CFrame.new(spot) * tilt, size)
		end
		for i = 1, 10 do
			-- Notches chipped out of the shelf's edge, tilted and mostly outside the
			-- rock (deeper, square-on cuts read as windows)
			local angle = (i / 10) * 2 * math.pi + rng:NextNumber(-0.3, 0.3)
			local spot = at(angle, terrace.r + 6, terrace.y1 - rng:NextNumber(2, 10))
			local tilt = CFrame.Angles(
				rng:NextNumber(-0.7, 0.7),
				angle + rng:NextNumber(-0.6, 0.6),
				rng:NextNumber(-0.7, 0.7)
			)
			block(
				ops,
				AIR,
				CFrame.new(spot) * tilt,
				Vector3.new(rng:NextNumber(12, 20), rng:NextNumber(8, 14), rng:NextNumber(10, 18))
			)
		end
	end
	ball(ops, SLATE, center + Vector3.new(0, 8, 0), 122) -- the cap: top at 130
	for i = 1, 14 do
		local angle = (i / 14) * 2 * math.pi + rng:NextNumber(-0.2, 0.2)
		local spot = at(angle, rng:NextNumber(38, 78), rng:NextNumber(104, 118))
		local size = Vector3.new(rng:NextNumber(14, 26), rng:NextNumber(8, 16), rng:NextNumber(12, 22))
		block(
			ops,
			SLATE,
			CFrame.new(spot)
				* CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6.28), rng:NextNumber(-0.5, 0.5)),
			size
		)
	end
	-- Sand banked against the foot, clear of the tunnel mouths
	for i = 1, 14 do
		local angle = (i / 14) * 2 * math.pi + rng:NextNumber(-0.15, 0.15)
		if not nearOpening(angle, math.rad(14)) then
			ball(ops, SAND, at(angle, terraces[1].r + rng:NextNumber(-2, 10), -16), rng:NextNumber(18, 26))
		end
	end

	-- 2. Warm stone where the den rooms will be, so their walls read as home
	for den = 1, Layout.DEN_COUNT do
		local frame = Layout.denFrame(den)
		ball(ops, SANDSTONE, frame.Position, 20)
	end
	-- Darker stone round the tunnels
	for segment = 1, hub.segments do
		if Layout.segmentKind(segment) == "tunnel" then
			local angle = Layout.segmentAngle(segment)
			cylinder(
				ops,
				BASALT,
				at(angle, hub.radius + 30, hub.tunnelHeight / 2),
				outward(angle),
				70,
				TUNNEL_RADIUS + 6
			)
		end
	end

	-- 3. Carve the cavern: straight walls, then the dome
	cylinder(ops, AIR, center + Vector3.new(0, WALL_TOP / 2, 0), Vector3.yAxis, WALL_TOP, hub.radius)
	ball(ops, AIR, center + Vector3.new(0, DOME_CENTER_Y, 0), DOME_RADIUS)
	-- The oculus, with a ragged rim
	cylinder(ops, AIR, center + Vector3.new(0, hub.height + 20, 0), Vector3.yAxis, 70, hub.oculusRadius)
	for i = 1, 7 do
		local angle = (i / 7) * 2 * math.pi + rng:NextNumber(-0.2, 0.2)
		ball(
			ops,
			AIR,
			at(angle, hub.oculusRadius + rng:NextNumber(-2, 6), hub.height + rng:NextNumber(-4, 10)),
			rng:NextNumber(9, 15)
		)
	end

	-- 4. Roughen the walls: alcoves (air) and bulges (rock), clear of the openings
	for _ = 1, 28 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local y = rng:NextNumber(WALL_TOP - 8, hub.height - 24)
		local lowWall = y < 42
		if not (lowWall and nearOpening(angle, math.rad(11))) then
			local r = rng:NextNumber(8, 15)
			-- The dome leans in above WALL_TOP: follow it
			local wallR = if y <= WALL_TOP
				then hub.radius
				else math.sqrt(math.max(DOME_RADIUS ^ 2 - (y - DOME_CENTER_Y) ^ 2, 0))
			ball(ops, AIR, at(angle, wallR + r * 0.35, y), r)
		end
	end
	for _ = 1, 12 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local y = rng:NextNumber(8, 40)
		if not nearOpening(angle, math.rad(10)) then
			ball(ops, ROCK, at(angle, hub.radius + 2, y), rng:NextNumber(6, 10))
		end
	end
	for _ = 1, 16 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local y = rng:NextNumber(WALL_TOP + 6, hub.height - 18)
		local wallR = math.sqrt(math.max(DOME_RADIUS ^ 2 - (y - DOME_CENTER_Y) ^ 2, 0))
		ball(ops, SLATE, at(angle, wallR + 2, y), rng:NextNumber(6, 11))
	end
	-- Bays in the dome: wide shallow hollows that break the perfect sphere
	for _ = 1, 6 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local r = rng:NextNumber(hub.oculusRadius + 16, 72)
		local domeY = DOME_CENTER_Y + math.sqrt(math.max(DOME_RADIUS ^ 2 - r ^ 2, 0))
		local size = rng:NextNumber(18, 26)
		ball(ops, AIR, at(angle, r, domeY + size * 0.75), size)
	end
	-- Drips hanging from the dome: angular knobs mostly buried in the rock so only
	-- a facet shows, in groups, a few stacked into short stalactites
	for _ = 1, 9 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local r = rng:NextNumber(hub.oculusRadius + 8, 74)
		for _ = 1, rng:NextInteger(2, 4) do
			local spotAngle = angle + rng:NextNumber(-0.12, 0.12)
			local spotR = r + rng:NextNumber(-8, 8)
			local domeY = DOME_CENTER_Y + math.sqrt(math.max(DOME_RADIUS ^ 2 - spotR ^ 2, 0))
			local size = Vector3.new(rng:NextNumber(5, 10), rng:NextNumber(6, 12), rng:NextNumber(5, 10))
			local spin =
				CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 6.28), rng:NextNumber(-0.6, 0.6))
			block(ops, SLATE, CFrame.new(at(spotAngle, spotR, domeY + size.Y * 0.2)) * spin, size)
			if rng:NextNumber() < 0.35 then
				block(ops, SLATE, CFrame.new(at(spotAngle, spotR, domeY - size.Y * 0.35)) * spin, size * 0.55)
			end
		end
	end

	-- 5. The den rooms: a lozenge of air with a flat floor and a round doorway
	for den = 1, Layout.DEN_COUNT do
		local frame = Layout.denFrame(den)
		local back = -frame.LookVector -- the frame faces the hub; the room runs outward
		local middle = frame.Position
		local roomY = DEN_FLOOR + hub.denHeight / 2
		local mid = Vector3.new(middle.X, roomY, middle.Z)
		ball(ops, AIR, mid, 14)
		ball(ops, AIR, mid - back * 11, 12)
		ball(ops, AIR, mid + back * 10 + Vector3.new(0, -1, 0), 11)
		block(
			ops,
			AIR,
			CFrame.lookAt(mid + Vector3.new(0, -8, 0), mid + Vector3.new(0, -8, 0) + back),
			Vector3.new(24, 12, 30)
		)
		-- The doorway through the wall, a little above the floor
		local door = mid - back * (hub.denDepth / 2) -- at hub.radius
		cylinder(ops, AIR, Vector3.new(door.X, DEN_FLOOR + 11, door.Z), back, 22, 10)
		block(
			ops,
			AIR,
			CFrame.lookAt(Vector3.new(door.X, DEN_FLOOR + 5, door.Z), door + back),
			Vector3.new(18, 10, 22)
		)
	end

	-- 6. The tunnels: round tubes out to the shallows, roughened
	for segment = 1, hub.segments do
		if Layout.segmentKind(segment) == "tunnel" then
			local angle = Layout.segmentAngle(segment)
			local reach = hub.radius + hub.wallThickness + hub.tunnelLength + 10
			local midR = (hub.radius - 20 + reach) / 2
			cylinder(
				ops,
				AIR,
				at(angle, midR, TUNNEL_RADIUS + 1),
				outward(angle),
				reach - (hub.radius - 20),
				TUNNEL_RADIUS
			)
			for _ = 1, 6 do
				local r = rng:NextNumber(hub.radius + 4, reach - 8)
				local side = rng:NextNumber(0, 2 * math.pi)
				local offset = Vector3.new(math.cos(side), math.sin(side), 0)
				local along = outward(angle)
				local right = along:Cross(Vector3.yAxis).Unit
				local spot = at(angle, r, TUNNEL_RADIUS + 1)
					+ (right * offset.X + Vector3.yAxis * offset.Y) * TUNNEL_RADIUS
				if spot.Y > 6 then
					ball(ops, AIR, spot, rng:NextNumber(5, 8))
				end
			end
		end
	end

	-- 7. Floors back: the cavern floor at 0, den floors at DEN_FLOOR, tunnel floors at 1
	cylinder(ops, ROCK, center + Vector3.new(0, -16, 0), Vector3.yAxis, 32, hub.radius + hub.denDepth + 40)
	for den = 1, Layout.DEN_COUNT do
		local frame = Layout.denFrame(den)
		local floorCenter = Vector3.new(frame.Position.X, DEN_FLOOR / 2 - 2, frame.Position.Z)
		block(
			ops,
			SANDSTONE,
			CFrame.lookAt(floorCenter, floorCenter + frame.LookVector),
			Vector3.new(32, DEN_FLOOR + 4, 42)
		)
	end
	for segment = 1, hub.segments do
		if Layout.segmentKind(segment) == "tunnel" then
			local angle = Layout.segmentAngle(segment)
			local reach = hub.radius + hub.wallThickness + hub.tunnelLength + 10
			local midR = (hub.radius - 20 + reach) / 2
			local floorCenter = at(angle, midR, -3)
			block(
				ops,
				BASALT,
				CFrame.lookAt(floorCenter, floorCenter + outward(angle)),
				Vector3.new(TUNNEL_RADIUS * 2 + 6, 8, reach - (hub.radius - 20))
			)
		end
	end
	-- Sand drifts at the foot of the walls, away from the doorways
	for _ = 1, 20 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		if not nearOpening(angle, math.rad(9)) then
			ball(ops, SAND, at(angle, rng:NextNumber(62, 84), -5), rng:NextNumber(7, 10))
		end
	end
	return ops
end

-- Writes the ops into the Terrain (server start). Fill order matters: later ops
-- overwrite earlier ones where they overlap.
function Cave.apply(terrain: Terrain, ops: { Op })
	for material, color in Cave.COLORS do
		terrain:SetMaterialColor(material, color)
	end
	for _, op in ops do
		if op.kind == "ball" then
			terrain:FillBall(op.center, op.radius :: number, op.material)
		elseif op.kind == "block" then
			terrain:FillBlock(op.cframe :: CFrame, op.size :: Vector3, op.material)
		elseif op.kind == "cylinder" then
			terrain:FillCylinder(op.cframe :: CFrame, op.height :: number, op.radius :: number, op.material)
		end
	end
end

return Cave
