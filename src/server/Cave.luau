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
	-- Lifted so the Vents' floor shows its tile instead of reading near black (PC
	-- 2026-10-16 round 2, T1)
	[Enum.Material.Basalt] = Color3.fromRGB(88, 98, 110),
	-- The dens' walls (DenCarve): the tan the dens always had, on Rock's plates
	[Enum.Material.Limestone] = Color3.fromRGB(150, 138, 118),
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
local TUNNEL_WIDE = hub.tunnelWide
-- The tunnel's crown where it meets the cavern (its arch tube's top), for the EXIT
-- board over it (WorldService)
Cave.TUNNEL_TOP = TUNNEL_RADIUS + 1 + hub.tunnelArch + (TUNNEL_RADIUS - 3)

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

-- A box's worth of rock, rounded off like a pebble (owner, 2026-10-11: "rocks are
-- also still a bit too unnatural and jagged. Needs more of a toonish rounded off
-- look"): capsules (a cylinder with a ball on each end) run along the box's longest
-- side, laid side by side across its middle one, thinner and shorter toward the
-- edges, so the box's corners and flat faces become one smooth rounded lump. Use it
-- wherever a tilted block of rock would go; carve (Air) and floors stay blocks.
function Cave.pebble(ops: { Op }, material: Enum.Material, cframe: CFrame, size: Vector3)
	local axes = {
		{ size = size.X, axis = cframe.RightVector },
		{ size = size.Y, axis = cframe.UpVector },
		{ size = size.Z, axis = cframe.LookVector },
	}
	table.sort(axes, function(a, b)
		return a.size < b.size
	end)
	local thin, mid, long = axes[1].size, axes[2].size, axes[3].size
	local across, along = axes[2].axis, axes[3].axis
	local radius = thin / 2
	local span = math.max(mid / 2 - radius, 0)
	local count = if span > 0 then math.ceil(span * 2 / (radius * 1.1)) + 1 else 1
	for i = 1, count do
		local t = if count > 1 then (i - 1) / (count - 1) * 2 - 1 else 0
		local offset = t * span
		local round = math.sqrt(math.max(1 - (offset / (mid / 2)) ^ 2, 0))
		local r = radius * (0.72 + 0.28 * round)
		local half = math.max(long / 2 - r, 0) * (0.55 + 0.45 * round)
		local middle = cframe.Position + across * offset
		if half > r * 0.25 then
			cylinder(ops, material, middle, along, half * 2, r)
			ball(ops, material, middle + along * half, r)
			ball(ops, material, middle - along * half, r)
		else
			ball(ops, material, middle, r * 1.1)
		end
	end
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

-- A den's doorway on the plaza (owner, 2026-10-16: the dens are private interiors
-- now, Layout.denOrigin): a round alcove through the cavern wall with a flat sill
-- at the den floor's height, ending in a flat back where the bubble portal stands
-- (WorldService). The rest of the seamount stays solid.
function Cave.denDoor(ops: { Op }, den: number)
	local frame = Layout.doorFrame(den)
	local back = -frame.LookVector -- the frame faces the hub; the alcove runs outward
	local door = Vector3.new(frame.Position.X, 0, frame.Position.Z)
	local front = door - back * 20 -- inside the cavern
	local length = 21 -- to just behind the portal
	local middle = front + back * (length / 2)
	cylinder(ops, AIR, Vector3.new(middle.X, frame.Position.Y, middle.Z), back, length, 10.5)
	local sill = Vector3.new(middle.X, DEN_FLOOR + 5, middle.Z)
	block(ops, AIR, CFrame.lookAt(sill, sill + back), Vector3.new(18, 10, length))
end

-- A doorway's sill, put back after the carving
function Cave.denFloor(ops: { Op }, den: number)
	local frame = Layout.doorFrame(den)
	local back = -frame.LookVector
	local middle = Vector3.new(frame.Position.X, 0, frame.Position.Z) - back * 5
	local floorCenter = Vector3.new(middle.X, DEN_FLOOR / 2 - 2, middle.Z)
	block(ops, SANDSTONE, CFrame.lookAt(floorCenter, floorCenter + back), Vector3.new(24, DEN_FLOOR + 4, 22))
end

-- The fill helpers, for DenCarve
Cave.ball = ball
Cave.block = block
Cave.cylinder = cylinder

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
		{ y0 = -26, y1 = 36, r = hub.radius + hub.denDepth + 36 },
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
			Cave.pebble(ops, ROCK, CFrame.new(spot) * tilt, size)
		end
		-- A rounded lip: a ring of rock balls along the shelf's edge, so the drum's
		-- square top edge reads as a soft shoulder
		local lip = math.clamp(height * 0.35, 6, 14)
		local around = math.ceil(2 * math.pi * terrace.r / (lip * 1.3))
		for i = 1, around do
			local angle = (i / around) * 2 * math.pi
			ball(ops, ROCK, at(angle, terrace.r - 6 - lip * 0.5, terrace.y1 - lip * 0.45), lip)
		end
		for i = 1, 8 do
			-- Rounded bites out of the shelf's edge (square-on cuts read as windows)
			local angle = (i / 8) * 2 * math.pi + rng:NextNumber(-0.3, 0.3)
			ball(ops, AIR, at(angle, terrace.r + 2, terrace.y1 - rng:NextNumber(0, 4)), rng:NextNumber(6, 9))
		end
	end
	-- Soft inside corners: where each terrace stands on the one below, a ring of balls
	-- fills the step's corner
	for i = 2, #terraces do
		local upper, lower = terraces[i], terraces[i - 1]
		local fillet = math.clamp((upper.y1 - upper.y0) * 0.3, 6, 10)
		local around = math.ceil(2 * math.pi * upper.r / (fillet * 1.4))
		for k = 1, around do
			local angle = (k / around) * 2 * math.pi
			ball(ops, ROCK, at(angle, upper.r - 6 + fillet * 0.2, lower.y1 + fillet * 0.15), fillet)
		end
	end
	ball(ops, SLATE, center + Vector3.new(0, 8, 0), 122) -- the cap: top at 130
	for i = 1, 14 do
		local angle = (i / 14) * 2 * math.pi + rng:NextNumber(-0.2, 0.2)
		local spot = at(angle, rng:NextNumber(38, 78), rng:NextNumber(104, 118))
		local size = Vector3.new(rng:NextNumber(14, 26), rng:NextNumber(8, 16), rng:NextNumber(12, 22))
		Cave.pebble(
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

	-- 2. Warm stone round the den doorways, so they read as home
	for den = 1, Layout.DEN_COUNT do
		ball(ops, SANDSTONE, Layout.doorFrame(den).Position, 16)
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
	-- Bulges on the walls between the openings, up off the floor: the plaza's
	-- planter beds and their kelp stand against the wall's foot (Plaza.luau)
	for _ = 1, 12 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local y = rng:NextNumber(24, 46)
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
	-- Drips hanging from the dome: rounded knobs mostly buried in the rock, in
	-- groups, a few with a smaller drop under them
	for _ = 1, 9 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local r = rng:NextNumber(hub.oculusRadius + 8, 74)
		for _ = 1, rng:NextInteger(2, 4) do
			local spotAngle = angle + rng:NextNumber(-0.12, 0.12)
			local spotR = r + rng:NextNumber(-8, 8)
			local domeY = DOME_CENTER_Y + math.sqrt(math.max(DOME_RADIUS ^ 2 - spotR ^ 2, 0))
			local size = rng:NextNumber(3, 6)
			ball(ops, SLATE, at(spotAngle, spotR, domeY + size * 0.3), size)
			if rng:NextNumber() < 0.35 then
				ball(ops, SLATE, at(spotAngle, spotR, domeY - size * 0.7), size * 0.55)
			end
		end
	end

	-- 5. The den doorways: round alcoves ending at each den's portal
	for den = 1, Layout.DEN_COUNT do
		Cave.denDoor(ops, den)
	end

	-- 6. The tunnels: round tubes out to the shallows, roughened. Through the wall a
	-- tall arch (the dens' doorways open either side), then wider past it
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
			local wall = hub.tunnelWall
			cylinder(
				ops,
				AIR,
				at(angle, (hub.radius - 20 + wall) / 2, TUNNEL_RADIUS + 1 + hub.tunnelArch),
				outward(angle),
				wall - (hub.radius - 20),
				TUNNEL_RADIUS - 3
			)
			cylinder(
				ops,
				AIR,
				at(angle, (wall + reach) / 2, TUNNEL_WIDE + 1),
				outward(angle),
				reach - wall,
				TUNNEL_WIDE
			)
			-- (the step from the arch out to the wide tube, rounded)
			ball(ops, AIR, at(angle, wall, TUNNEL_RADIUS + 1 + hub.tunnelArch * 0.5), TUNNEL_RADIUS + 2)
			-- A flared mouth where the tube comes out on the sand, so it opens wide
			-- onto the shallows instead of ending in a lip
			ball(ops, AIR, at(angle, reach - 4, TUNNEL_WIDE + 5), TUNNEL_WIDE + 6)
			for _ = 1, 6 do
				local r = rng:NextNumber(hub.radius + 4, reach - 8)
				local side = rng:NextNumber(0, 2 * math.pi)
				local offset = Vector3.new(math.cos(side), math.sin(side), 0)
				local along = outward(angle)
				local right = along:Cross(Vector3.yAxis).Unit
				local radius = if r > hub.tunnelWall then TUNNEL_WIDE else TUNNEL_RADIUS
				local spot = at(angle, r, radius + 1) + (right * offset.X + Vector3.yAxis * offset.Y) * radius
				if spot.Y > 6 then
					ball(ops, AIR, spot, rng:NextNumber(5, 8))
				end
			end
		end
	end

	-- 7. Floors back: the cavern floor at 0, den floors at DEN_FLOOR, tunnel floors at 1.
	-- The rock under the floor goes all the way down to the shelf's hollow: the dome's
	-- ball reaches 84 under the floor, and it left a hidden void under the plaza that
	-- the dens' lower storeys would have opened into (2026-10-13)
	cylinder(ops, ROCK, center + Vector3.new(0, -44, 0), Vector3.yAxis, 88, hub.radius + hub.denDepth + 40)
	for den = 1, Layout.DEN_COUNT do
		Cave.denFloor(ops, den)
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
				Vector3.new(TUNNEL_WIDE * 2 + 6, 8, reach - (hub.radius - 20))
			)
		end
	end
	-- (The floor stays flat under the plaza's paving, Plaza.luau: the sand drifts
	-- that were banked round it poked up through the flagstones, owner 2026-10-17:
	-- "Ground still looks a bit rough in the starter zone")
	return ops
end

-- Writes the ops into the Terrain (server start). Fill order matters: later ops
-- overwrite earlier ones where they overlap.
-- A Terrain material's colour. While its toon variant is on (Config/Materials: a
-- MaterialService override; its map averages ~0.8 and darkens what wears it), the
-- colour is lifted to keep the world as bright; the toon lava carries its own colour,
-- so it isn't tinted at all.
function Cave.paint(terrain: Terrain, material: Enum.Material, color: Color3)
	local MaterialService = game:GetService("MaterialService")
	local ok, override = pcall(function()
		return MaterialService:GetBaseMaterialOverride(material)
	end)
	if ok and override ~= "" then
		if material == Enum.Material.CrackedLava then
			color = Color3.new(1, 1, 1)
		else
			local lift = Config.Materials.terrainLift
			color = Color3.new(
				math.min(color.R * lift, 1),
				math.min(color.G * lift, 1),
				math.min(color.B * lift, 1)
			)
		end
	end
	terrain:SetMaterialColor(material, color)
end

function Cave.apply(terrain: Terrain, ops: { Op })
	for material, color in Cave.COLORS do
		Cave.paint(terrain, material, color)
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
