--!strict
-- Builds the graybox map at server start: the seabed with a trench, the surface
-- ceiling, the map's walls, the hub cavern (wall ring, 12 dens with Haul Pools,
-- 4 tunnels, a roof with an oculus) and the Kelp Shallows' dressing (kelp, rocks,
-- arches, a coral patch, light shafts). Everything is placeholder geometry for
-- judging feel; layout numbers live in Config/World.luau and Shared/Layout.luau.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)

local World = Config.World
local hub = World.hub

local WorldService = {}

local root: Folder
local denSigns: { [number]: TextLabel } = {}
local vendorPositions: { [string]: Vector3 } = {}

local SAND = Color3.fromRGB(196, 182, 140)
local ROCK = Color3.fromRGB(92, 98, 104)
local ROCK_DARK = Color3.fromRGB(58, 62, 70)
local HUB_STONE = Color3.fromRGB(84, 92, 102)
local KELP = Color3.fromRGB(78, 116, 52)
local KELP_LIGHT = Color3.fromRGB(122, 150, 64)
local POOL = Color3.fromRGB(80, 230, 255)

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.Slate
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A soft shaft of light from `top` down to `bottom` (a Beam between two attachments).
local function lightShaft(parent: Instance, top: Vector3, bottom: Vector3, width: number, strength: number)
	local holder = Instance.new("Part")
	holder.Name = "LightShaft"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(top)
	holder.Parent = parent
	local a0 = Instance.new("Attachment")
	a0.Parent = holder
	a0.WorldPosition = top
	local a1 = Instance.new("Attachment")
	a1.Parent = holder
	a1.WorldPosition = bottom
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = width
	beam.Width1 = width * 1.6
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(Color3.fromRGB(190, 240, 255))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 - strength),
		NumberSequenceKeypoint.new(0.6, 1 - strength * 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Parent = holder
end

local function setupLighting()
	-- The place template's own effects stack on ours (a lesson from Hatch & Snatch),
	-- so anything that isn't ours goes
	for _, child in Lighting:GetChildren() do
		if
			(child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("Clouds"))
			and child.Name ~= "OceanAtmosphere"
		then
			child:Destroy()
		end
	end
	Lighting.ClockTime = 13.5
	Lighting.GeographicLatitude = 20
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(34, 62, 80)
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 120, 140)
	Lighting.EnvironmentDiffuseScale = 0.35
	Lighting.EnvironmentSpecularScale = 0.25
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.45
	local atmosphere = Lighting:FindFirstChild("OceanAtmosphere") :: Atmosphere?
	if atmosphere == nil then
		local made = Instance.new("Atmosphere")
		made.Name = "OceanAtmosphere"
		made.Parent = Lighting
		atmosphere = made
	end
	assert(atmosphere)
	-- The client's OceanController grades these by depth; this is the shallows look
	atmosphere.Density = 0.42
	atmosphere.Offset = 0.12
	atmosphere.Color = Color3.fromRGB(56, 140, 168)
	atmosphere.Decay = Color3.fromRGB(18, 64, 96)
	atmosphere.Glare = 0
	atmosphere.Haze = 1.6
	workspace.Gravity = 0 -- everything swims
end

local function buildSeabed(parent: Instance)
	local extent = World.boundsRadius + 120
	local trench = World.trench
	local xMin = trench.center.X - trench.size.X / 2
	local xMax = trench.center.X + trench.size.X / 2
	local zMin = trench.center.Z - trench.size.Z / 2
	local zMax = trench.center.Z + trench.size.Z / 2
	local y = World.seabedY - 4
	local function slab(x0: number, x1: number, z0: number, z1: number)
		if x1 - x0 < 1 or z1 - z0 < 1 then
			return
		end
		local slabPart = block(
			parent,
			"Seabed",
			Vector3.new(x1 - x0, 8, z1 - z0),
			CFrame.new((x0 + x1) / 2, y, (z0 + z1) / 2),
			SAND,
			Enum.Material.Sand
		)
		slabPart.CastShadow = false
	end
	-- The seabed is four slabs round the trench's mouth
	slab(-extent, extent, -extent, zMin)
	slab(-extent, extent, zMax, extent)
	slab(-extent, xMin, zMin, zMax)
	slab(xMax, extent, zMin, zMax)

	-- The trench: walls down to a dark floor
	local depth = World.seabedY - trench.floorY
	local mid = World.seabedY - depth / 2
	block(
		parent,
		"TrenchWall",
		Vector3.new(trench.size.X, depth, 8),
		CFrame.new(trench.center.X, mid, zMin - 4),
		ROCK_DARK
	)
	block(
		parent,
		"TrenchWall",
		Vector3.new(trench.size.X, depth, 8),
		CFrame.new(trench.center.X, mid, zMax + 4),
		ROCK_DARK
	)
	block(
		parent,
		"TrenchWall",
		Vector3.new(8, depth, trench.size.Z),
		CFrame.new(xMin - 4, mid, trench.center.Z),
		ROCK_DARK
	)
	block(
		parent,
		"TrenchWall",
		Vector3.new(8, depth, trench.size.Z),
		CFrame.new(xMax + 4, mid, trench.center.Z),
		ROCK_DARK
	)
	block(
		parent,
		"TrenchFloor",
		Vector3.new(trench.size.X + 16, 8, trench.size.Z + 16),
		CFrame.new(trench.center.X, trench.floorY - 4, trench.center.Z),
		Color3.fromRGB(40, 44, 52),
		Enum.Material.Basalt
	)

	-- Gentle dunes so the floor isn't a table top
	local rng = Random.new(World.seed + 1)
	for _ = 1, 70 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local distance = rng:NextNumber(hub.radius + 40, World.boundsRadius - 20)
		local x = math.cos(angle) * distance
		local z = math.sin(angle) * distance
		if not (x > xMin - 30 and x < xMax + 30 and z > zMin - 30 and z < zMax + 30) then
			local size = rng:NextNumber(40, 110)
			local dune = Instance.new("Part")
			dune.Name = "Dune"
			dune.Anchored = true
			dune.Shape = Enum.PartType.Ball
			dune.Size = Vector3.one * size
			dune.CFrame = CFrame.new(x, World.seabedY - size * 0.42, z)
			dune.Color = SAND
			dune.Material = Enum.Material.Sand
			dune.CastShadow = false
			dune.Parent = parent
		end
	end
end

local function buildBounds(parent: Instance)
	local r = World.boundsRadius
	local bottom = World.trench.floorY - 20
	local height = World.surfaceY - bottom + 40
	local midY = bottom + height / 2
	local function wall(size: Vector3, position: Vector3)
		local part =
			block(parent, "Bounds", size, CFrame.new(position), Color3.new(), Enum.Material.SmoothPlastic)
		part.Transparency = 1
		part.CastShadow = false
	end
	wall(Vector3.new(8, height, r * 2 + 16), Vector3.new(r + 4, midY, 0))
	wall(Vector3.new(8, height, r * 2 + 16), Vector3.new(-r - 4, midY, 0))
	wall(Vector3.new(r * 2 + 16, height, 8), Vector3.new(0, midY, r + 4))
	wall(Vector3.new(r * 2 + 16, height, 8), Vector3.new(0, midY, -r - 4))

	-- The surface: the map's ceiling, seen from below as a bright, rippling sheet
	local surface = block(
		parent,
		"Surface",
		Vector3.new(r * 2 + 240, 2, r * 2 + 240),
		CFrame.new(0, World.surfaceY + 1, 0),
		Color3.fromRGB(150, 224, 236),
		Enum.Material.SmoothPlastic
	)
	surface.Transparency = 0.25
	surface.CastShadow = false
end

-- One den: a room cut back into the wall, with its Haul Pool and sign.
local function buildDen(parent: Instance, index: number, segment: number, width: number)
	local angle = Layout.segmentAngle(segment)
	local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local function at(r: number, y: number): CFrame
		local position = hub.center + radial * r + Vector3.new(0, y, 0)
		return CFrame.lookAt(position, position + radial)
	end
	local den = Instance.new("Model")
	den.Name = `Den{index}`
	local roomWidth = width * 0.88
	local top = hub.denFloorY + hub.denHeight
	local back = hub.radius + hub.denDepth
	local midR = hub.radius + hub.denDepth / 2
	-- Floor, ceiling, back and sides
	block(den, "Floor", Vector3.new(roomWidth, 2, hub.denDepth), at(midR, hub.denFloorY - 1), HUB_STONE)
	block(den, "Ceiling", Vector3.new(roomWidth + 4, 3, hub.denDepth + 2), at(midR, top + 1.5), HUB_STONE)
	block(
		den,
		"Back",
		Vector3.new(roomWidth + 4, hub.denHeight + 6, 3),
		at(back + 1.5, top / 2 + 1),
		HUB_STONE
	)
	for side = -1, 1, 2 do
		local wall = block(
			den,
			"Side",
			Vector3.new(2, hub.denHeight + 6, hub.denDepth),
			at(midR, top / 2 + 1) * CFrame.new(side * (roomWidth / 2 + 1), 0, 0),
			HUB_STONE
		)
		wall.Name = "Side"
	end
	-- The Haul Pool: swim into it to bank
	local pool = Instance.new("Part")
	pool.Name = "HaulPool"
	pool.Anchored = true
	pool.CanCollide = false
	pool.Shape = Enum.PartType.Cylinder
	pool.Size = Vector3.new(1, hub.poolRadius * 2, hub.poolRadius * 2)
	pool.CFrame = CFrame.new(Layout.poolPosition(index)) * CFrame.Angles(0, 0, math.rad(90))
	pool.Color = POOL
	pool.Material = Enum.Material.Neon
	pool.Transparency = 0.25
	pool.CastShadow = false
	pool.Parent = den
	local light = Instance.new("PointLight")
	light.Color = POOL
	light.Range = 22
	light.Brightness = 1.6
	light.Shadows = true
	light.Parent = pool
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "Bubbles"
	bubbles.Rate = 6
	bubbles.Lifetime = NumberRange.new(2, 3.5)
	bubbles.Speed = NumberRange.new(3, 6)
	bubbles.SpreadAngle = Vector2.new(12, 12)
	bubbles.EmissionDirection = Enum.NormalId.Right -- the cylinder's axis points up
	bubbles.Size = NumberSequence.new(0.25, 0.1)
	bubbles.Transparency = NumberSequence.new(0.3, 1)
	bubbles.LightEmission = 0.6
	bubbles.Color = ColorSequence.new(Color3.fromRGB(210, 250, 255))
	bubbles.Parent = pool
	-- A warm lamp so a den reads as home
	local lamp = Instance.new("PointLight")
	lamp.Color = Color3.fromRGB(255, 196, 140)
	lamp.Range = 26
	lamp.Brightness = 0.9
	lamp.Parent = den:FindFirstChild("Ceiling") :: BasePart
	-- The sign over the opening, facing the hub
	local sign =
		block(den, "Sign", Vector3.new(roomWidth * 0.8, 4, 0.6), at(hub.radius - 0.5, top + 3.5), ROCK_DARK)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- the face toward the hub
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(200, 236, 245)
	label.Text = `DEN {index}`
	label.Parent = gui
	denSigns[index] = label
	den.Parent = parent
end

local function buildHub(parent: Instance)
	local hubFolder = folder("Hub", parent)
	local segments = hub.segments
	local outerR = hub.radius + hub.wallThickness
	local midR = hub.radius + hub.wallThickness / 2
	local arc = 2 * math.pi / segments
	local width = 2 * midR * math.tan(arc / 2) * 1.08
	local denIndex = 0
	for segment = 1, segments do
		local angle = Layout.segmentAngle(segment)
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local function at(r: number, y: number): CFrame
			local position = hub.center + radial * r + Vector3.new(0, y, 0)
			return CFrame.lookAt(position, position + radial)
		end
		local kind = Layout.segmentKind(segment)
		local openTop = 0
		if kind == "den" then
			denIndex += 1
			openTop = hub.denFloorY + hub.denHeight
			block(
				hubFolder,
				"Wall",
				Vector3.new(width, hub.denFloorY, hub.wallThickness),
				at(midR, hub.denFloorY / 2),
				HUB_STONE
			)
			buildDen(hubFolder, denIndex, segment, width)
		elseif kind == "tunnel" then
			openTop = hub.tunnelHeight
			-- The tunnel runs out through the wall to the shallows
			local length = hub.wallThickness + hub.tunnelLength
			local tunnelMid = hub.radius + length / 2
			for side = -1, 1, 2 do
				block(
					hubFolder,
					"TunnelSide",
					Vector3.new(3, hub.tunnelHeight + 4, length),
					at(tunnelMid, (hub.tunnelHeight + 4) / 2) * CFrame.new(side * (width * 0.45 + 1.5), 0, 0),
					HUB_STONE
				)
			end
			block(
				hubFolder,
				"TunnelRoof",
				Vector3.new(width * 0.9 + 6, 4, length),
				at(tunnelMid, hub.tunnelHeight + 2),
				HUB_STONE
			)
		end
		-- The wall above any opening (or the whole height)
		local wallHeight = hub.height - openTop
		block(
			hubFolder,
			"Wall",
			Vector3.new(width, wallHeight, hub.wallThickness),
			at(midR, openTop + wallHeight / 2),
			HUB_STONE
		)
		-- Roof, in two rings so the blocks overlap without gaps; the oculus stays open
		local innerR = hub.oculusRadius
		local splitR = (innerR + outerR) / 2
		for _, ring in { { innerR, splitR }, { splitR, outerR + 2 } } do
			local r0, r1 = ring[1], ring[2]
			local ringWidth = 2 * r1 * math.tan(arc / 2) * 1.1
			block(
				hubFolder,
				"Roof",
				Vector3.new(ringWidth, 10, r1 - r0),
				at((r0 + r1) / 2, hub.height + 5),
				ROCK
			)
		end
		-- A sconce between openings
		if kind == "wall" then
			local sconce =
				block(hubFolder, "Sconce", Vector3.new(2, 2, 1), at(hub.radius - 0.5, 18), ROCK_DARK)
			sconce.Material = Enum.Material.Neon
			sconce.Color = Color3.fromRGB(255, 190, 120)
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 190, 120)
			light.Range = 30
			light.Brightness = 0.8
			light.Parent = sconce
		end
	end

	-- The plaza: a raised ring floor and a crystal beacon in the middle (the
	-- Evolution Shrine's placeholder)
	local plaza = Instance.new("Part")
	plaza.Name = "Plaza"
	plaza.Anchored = true
	plaza.Shape = Enum.PartType.Cylinder
	plaza.Size = Vector3.new(2, 90, 90)
	plaza.CFrame = CFrame.new(hub.center + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	plaza.Color = Color3.fromRGB(120, 126, 132)
	plaza.Material = Enum.Material.Slate
	plaza.Parent = hubFolder
	local crystal = block(
		hubFolder,
		"Beacon",
		Vector3.new(6, 26, 6),
		CFrame.new(hub.center + Vector3.new(0, 16, 0)) * CFrame.Angles(0, math.rad(45), math.rad(12)),
		Color3.fromRGB(110, 230, 255),
		Enum.Material.Neon
	)
	crystal.Transparency = 0.15
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(110, 230, 255)
	glow.Range = 60
	glow.Brightness = 1.2
	glow.Parent = crystal

	-- Light falling through the oculus
	local rng = Random.new(World.seed + 2)
	for _ = 1, 5 do
		local offset = Vector3.new(rng:NextNumber(-14, 14), 0, rng:NextNumber(-14, 14))
		lightShaft(
			hubFolder,
			hub.center + offset + Vector3.new(0, World.surfaceY - 4, 0),
			hub.center + offset * 1.6 + Vector3.new(0, 4, 0),
			rng:NextNumber(8, 14),
			0.28
		)
	end
end

local WOOD = Color3.fromRGB(132, 96, 66)
local LANTERN = Color3.fromRGB(255, 196, 120)

-- A placeholder shopkeeper until the vendor models arrive: a round body with eyes.
local function keeper(parent: Instance, at: CFrame, color: Color3)
	local body = Instance.new("Part")
	body.Name = "Keeper"
	body.Anchored = true
	body.CanCollide = false
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.one * 4
	body.CFrame = at
	body.Color = color
	body.Material = Enum.Material.SmoothPlastic
	body.Parent = parent
	for side = -1, 1, 2 do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Anchored = true
		eye.CanCollide = false
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.one * 1.1
		eye.CFrame = at * CFrame.new(side * 0.8, 0.6, -1.55)
		eye.Color = Color3.new(1, 1, 1)
		eye.Material = Enum.Material.SmoothPlastic
		eye.Parent = parent
		local pupil = eye:Clone()
		pupil.Name = "Pupil"
		pupil.Size = Vector3.one * 0.55
		pupil.CFrame = at * CFrame.new(side * 0.8, 0.6, -2.02)
		pupil.Color = Color3.fromRGB(20, 22, 28)
		pupil.Parent = parent
	end
end

-- The four vendor stalls round the plaza (Config/Shop), each with a prompt that
-- opens its shop menu on the client.
local function buildVendors(parent: Instance)
	local market = folder("Vendors", parent)
	local plazaTop = 1.5
	for _, vendor in Config.Shop.vendors do
		local angle = math.rad(vendor.angle)
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local function at(r: number, y: number): CFrame
			local position = hub.center + radial * r + Vector3.new(0, y, 0)
			-- Facing the beacon
			return CFrame.lookAt(position, position - radial)
		end
		local stall = Instance.new("Model")
		stall.Name = vendor.id
		local counter = block(
			stall,
			"Counter",
			Vector3.new(12, 3.6, 3.5),
			at(33, plazaTop + 1.8),
			WOOD,
			Enum.Material.Wood
		)
		for side = -1, 1, 2 do
			block(
				stall,
				"Post",
				Vector3.new(0.8, 10, 0.8),
				at(36, plazaTop + 5) * CFrame.new(side * 6, 0, 0),
				WOOD,
				Enum.Material.Wood
			)
			local lantern = Instance.new("Part")
			lantern.Name = "Lantern"
			lantern.Anchored = true
			lantern.CanCollide = false
			lantern.Shape = Enum.PartType.Ball
			lantern.Size = Vector3.one * 1.1
			lantern.CFrame = at(31.2, plazaTop + 8.6) * CFrame.new(side * 6.4, 0, 0)
			lantern.Color = LANTERN
			lantern.Material = Enum.Material.Neon
			lantern.Parent = stall
			local light = Instance.new("PointLight")
			light.Color = LANTERN
			light.Range = 14
			light.Brightness = 0.9
			light.Parent = lantern
		end
		local awning = block(
			stall,
			"Awning",
			Vector3.new(14, 0.6, 8),
			at(33.5, plazaTop + 10) * CFrame.Angles(math.rad(-12), 0, 0),
			vendor.color,
			Enum.Material.Fabric
		)
		awning.CastShadow = true
		local sign =
			block(stall, "Sign", Vector3.new(11, 2, 0.4), at(29.6, plazaTop + 8.8), WOOD, Enum.Material.Wood)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front -- toward the beacon
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = sign
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 240, 214)
		label.Text = string.upper(vendor.name)
		label.Parent = gui
		keeper(stall, at(36.2, plazaTop + 4.2), vendor.color:Lerp(Color3.new(1, 1, 1), 0.25))

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ShopPrompt"
		prompt.ActionText = "Shop"
		prompt.ObjectText = vendor.name
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 18
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonY -- X bites
		prompt:SetAttribute("Vendor", vendor.id)
		prompt.Parent = counter
		vendorPositions[vendor.id] = counter.Position
		stall.Parent = market
	end
end

-- Where a vendor's counter is (for the server's reach check).
function WorldService.vendorPosition(id: string): Vector3?
	return vendorPositions[id]
end

local function inTrench(x: number, z: number, margin: number): boolean
	local trench = World.trench
	return math.abs(x - trench.center.X) < trench.size.X / 2 + margin
		and math.abs(z - trench.center.Z) < trench.size.Z / 2 + margin
end

local function buildShallows(parent: Instance)
	local shallows = folder("Shallows", parent)
	local rng = Random.new(World.seed + 3)
	local inner, outer = World.shallows.inner, World.shallows.outer

	local function spot(margin: number): (number, number)
		for _ = 1, 30 do
			local angle = rng:NextNumber(0, 2 * math.pi)
			local distance = rng:NextNumber(inner, outer)
			local x, z = math.cos(angle) * distance, math.sin(angle) * distance
			if not inTrench(x, z, margin) then
				return x, z
			end
		end
		return inner, 0
	end

	-- Kelp forests: tall stalks with blades, in clusters (good cover for small fish)
	local kelp = folder("Kelp", shallows)
	for _ = 1, 12 do
		local cx, cz = spot(40)
		for _ = 1, 20 do
			local x = cx + rng:NextNumber(-34, 34)
			local z = cz + rng:NextNumber(-34, 34)
			local height = rng:NextNumber(50, 190)
			local lean = CFrame.Angles(
				rng:NextNumber(-0.06, 0.06),
				rng:NextNumber(0, 6.28),
				rng:NextNumber(-0.06, 0.06)
			)
			local base = CFrame.new(x, World.seabedY, z) * lean
			local stalk = block(
				kelp,
				"Stalk",
				Vector3.new(1.1, height, 1.1),
				base * CFrame.new(0, height / 2, 0),
				KELP,
				Enum.Material.Grass
			)
			stalk.CastShadow = false
			stalk.CanCollide = false
			stalk.CanQuery = false -- the camera passes through kelp
			for b = 1, 3 do
				local y = height * (b / 4)
				local blade = block(
					kelp,
					"Blade",
					Vector3.new(0.2, rng:NextNumber(8, 16), rng:NextNumber(2.5, 4)),
					base * CFrame.new(0, y, 0) * CFrame.Angles(0, b * 2.1, math.rad(rng:NextNumber(18, 34))),
					KELP_LIGHT,
					Enum.Material.Grass
				)
				blade.CastShadow = false
				blade.CanCollide = false
				blade.CanQuery = false
			end
		end
	end

	-- Rocks, and arches with gaps too tight for big fish
	local rocks = folder("Rocks", shallows)
	for _ = 1, 110 do
		local x, z = spot(20)
		local size = Vector3.new(rng:NextNumber(6, 30), rng:NextNumber(5, 22), rng:NextNumber(6, 30))
		local rock = block(
			rocks,
			"Rock",
			size,
			CFrame.new(x, World.seabedY + size.Y * 0.25, z)
				* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6.28), rng:NextNumber(-0.4, 0.4)),
			ROCK
		)
		rock.Material = Enum.Material.Rock
	end
	for _ = 1, 10 do
		local x, z = spot(40)
		local gap = rng:NextNumber(5, 9)
		local height = rng:NextNumber(14, 26)
		local yaw = CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		local base = CFrame.new(x, World.seabedY, z) * yaw
		for side = -1, 1, 2 do
			block(
				rocks,
				"ArchPillar",
				Vector3.new(8, height, 8),
				base * CFrame.new(side * (gap / 2 + 4), height / 2, 0),
				ROCK_DARK,
				Enum.Material.Rock
			)
		end
		block(
			rocks,
			"ArchTop",
			Vector3.new(gap + 20, 7, 10),
			base * CFrame.new(0, height + 3.5, 0),
			ROCK_DARK,
			Enum.Material.Rock
		)
	end

	-- A coral patch, for color
	local coral = folder("Coral", shallows)
	local colors = {
		Color3.fromRGB(240, 110, 120),
		Color3.fromRGB(255, 160, 80),
		Color3.fromRGB(170, 110, 220),
		Color3.fromRGB(250, 220, 110),
		Color3.fromRGB(90, 200, 190),
	}
	local cx, cz = spot(60)
	for _ = 1, 90 do
		local x = cx + rng:NextNumber(-60, 60)
		local z = cz + rng:NextNumber(-60, 60)
		local size = rng:NextNumber(2, 7)
		local piece = Instance.new("Part")
		piece.Name = "Coral"
		piece.Anchored = true
		piece.Shape = if rng:NextNumber() < 0.5 then Enum.PartType.Ball else Enum.PartType.Cylinder
		piece.Size = if piece.Shape == Enum.PartType.Ball
			then Vector3.one * size
			else Vector3.new(size * 1.6, size * 0.6, size * 0.6)
		piece.CFrame = CFrame.new(x, World.seabedY + size * 0.3, z)
			* CFrame.Angles(0, rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(40, 90)))
		piece.Color = colors[rng:NextInteger(1, #colors)]
		piece.Material = Enum.Material.SmoothPlastic
		piece.Parent = coral
	end

	-- Light shafts from the surface
	local shafts = folder("Shafts", shallows)
	for _ = 1, 22 do
		local x, z = spot(0)
		local top = Vector3.new(x, World.surfaceY - 2, z)
		local slant = Vector3.new(rng:NextNumber(-40, 40), 0, rng:NextNumber(-40, 40))
		lightShaft(shafts, top, Vector3.new(x, World.seabedY + 10, z) + slant, rng:NextNumber(10, 22), 0.22)
	end
end

-- Shows who owns a den on its sign (nil = free).
function WorldService.setDenOwner(index: number, name: string?)
	local label = denSigns[index]
	if label then
		label.Text = if name then `{string.upper(name)}'S DEN` else `DEN {index}`
	end
end

function WorldService.start()
	setupLighting()
	root = folder("World", workspace)
	buildSeabed(folder("Seabed", root))
	buildBounds(folder("Bounds", root))
	buildHub(root)
	buildVendors(root:FindFirstChild("Hub") :: Folder)
	buildShallows(root)
end

return WorldService
