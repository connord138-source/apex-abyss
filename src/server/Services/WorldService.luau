--!strict
-- Builds the map at server start: the seafloor as Terrain (Shelf.luau: the shelf,
-- the drop-off, the deep floor, the Trench canyon, the Vents and the Ruins), the
-- surface ceiling, the map's walls, the hub cavern (Terrain carved by Cave.luau,
-- plus 12 dens' pools and signs, sconces, the plaza and beacon) and every biome's
-- dressing (kelp forests, rocks, arches, coral gardens, wrecks, ruins, vent smoke,
-- trench glow, light shafts). The dressing is placeholder geometry until the Tripo
-- props land; layout numbers live in Config/World.luau, Shared/Seafloor.luau and
-- Shared/Layout.luau.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Cave = require(script.Parent.Parent.Cave)
local Props = require(script.Parent.Parent.Props)
local Shelf = require(script.Parent.Parent.Shelf)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)

local World = Config.World
local hub = World.hub

local WorldService = {}

local root: Folder
local denSigns: { [number]: TextLabel } = {}
local vendorPositions: { [string]: Vector3 } = {}

local ROCK = Color3.fromRGB(92, 98, 104)
local ROCK_DARK = Color3.fromRGB(58, 62, 70)
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
			and child.Name ~= "OceanSky"
		then
			child:Destroy()
		end
	end
	Lighting.ClockTime = 12
	Lighting.GeographicLatitude = 20
	Lighting.Brightness = 1.7
	Lighting.Ambient = Color3.fromRGB(26, 58, 82)
	Lighting.OutdoorAmbient = Color3.fromRGB(56, 108, 136)
	Lighting.EnvironmentDiffuseScale = 0.3
	Lighting.EnvironmentSpecularScale = 0.2
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.6
	-- No sun, moon or stars: nothing above the water should read as a sky (owner,
	-- 2026-10-08: "still has that sky look, it needs to look like it's underwater")
	local sky = Instance.new("Sky")
	sky.Name = "OceanSky"
	sky.CelestialBodiesShown = false
	sky.StarCount = 0
	sky.SunAngularSize = 0
	sky.MoonAngularSize = 0
	sky.Parent = Lighting
	local atmosphere = Lighting:FindFirstChild("OceanAtmosphere") :: Atmosphere?
	if atmosphere == nil then
		local made = Instance.new("Atmosphere")
		made.Name = "OceanAtmosphere"
		made.Parent = Lighting
		atmosphere = made
	end
	assert(atmosphere)
	-- The client's OceanController grades these by depth; this is the shallows look
	atmosphere.Density = 0.56
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(44, 126, 156)
	atmosphere.Decay = Color3.fromRGB(14, 56, 88)
	atmosphere.Glare = 0
	atmosphere.Haze = 2.8
	workspace.Gravity = 0 -- everything swims
end

-- The seafloor is Terrain (Shelf.luau): the shelf, the drop-off, the deep floor,
-- the Trench canyon, the Vents' basin, the Ruins' stones. The features it returns
-- (chimneys, pinnacles, chutes, ruin anchors) are dressed with parts below.
local features: Shelf.Features

local function buildSeabed()
	local ops, made = Shelf.ops()
	features = made
	Shelf.apply(workspace.Terrain, ops)
end

-- The Terrain's height under (x, z), by raycast, plus its normal; nil over nothing
local function groundAt(x: number, z: number): (Vector3?, Vector3?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(
		Vector3.new(x, World.surfaceY - 5, z),
		Vector3.new(0, -(World.surfaceY - World.trench.floorY + 60), 0),
		params
	)
	if hit then
		return hit.Position, hit.Normal
	end
	return nil, nil
end

-- Terrain filled this frame doesn't answer a raycast until a later one (playtest
-- 2026-10-07: every kelp forest, rock, coral garden and wreck is placed by raycast,
-- and none were there; nor were the shell and forage spots placed next). Waits until
-- the shelf and the deep floor both answer, for at most a few seconds.
local function awaitTerrain()
	local probes = { Vector2.new(400, 0), Vector2.new(0, 400), Vector2.new(-400, 0), Vector2.new(0, -1150) }
	local deadline = os.clock() + 5
	repeat
		task.wait()
		local ready = true
		for _, probe in probes do
			if groundAt(probe.X, probe.Y) == nil then
				ready = false
				break
			end
		end
	until ready or os.clock() > deadline
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

	-- The surface: the map's ceiling, seen from below as a pale sheet of water (opaque:
	-- the skybox must never show through it)
	local span = r * 2 + 2800
	local surface = block(
		parent,
		"Surface",
		Vector3.new(span, 2, span),
		CFrame.new(0, World.surfaceY + 1, 0),
		Color3.fromRGB(142, 206, 224),
		Enum.Material.SmoothPlastic
	)
	surface.Transparency = 0
	surface.Reflectance = 0.08
	surface.CastShadow = false
	surface.CanCollide = false
	surface.CanQuery = false
	-- The horizon: deep-blue walls far past the barrier, so the water fades into
	-- water in every direction instead of a sky
	local horizonY = (World.trench.floorY - 200 + World.surfaceY + 20) / 2
	local horizonHeight = World.surfaceY + 20 - (World.trench.floorY - 200)
	for _, side in
		{ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }
	do
		local center = side * (span / 2) + Vector3.new(0, horizonY, 0)
		local horizon = block(
			parent,
			"Horizon",
			Vector3.new(if side.X ~= 0 then 4 else span, horizonHeight, if side.X ~= 0 then span else 4),
			CFrame.new(center),
			Color3.fromRGB(16, 62, 92),
			Enum.Material.SmoothPlastic
		)
		horizon.CastShadow = false
		horizon.CanCollide = false
		horizon.CanQuery = false
	end
end

-- One den's furniture; the room itself is carved from the Terrain (Cave.luau).
-- Its Haul Pool, a warm lamp and the sign over the round doorway.
local function buildDen(parent: Instance, index: number, segment: number)
	local angle = Layout.segmentAngle(segment)
	local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local function at(r: number, y: number): CFrame
		local position = hub.center + radial * r + Vector3.new(0, y, 0)
		return CFrame.lookAt(position, position + radial)
	end
	local den = Instance.new("Model")
	den.Name = `Den{index}`
	local top = hub.denFloorY + hub.denHeight
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
	-- A warm lamp so a den reads as home, on an invisible anchor under the room's roof
	local anchor = Instance.new("Part")
	anchor.Name = "Lamp"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = at(hub.radius + hub.denDepth / 2, top - 4)
	anchor.Parent = den
	local lamp = Instance.new("PointLight")
	lamp.Color = Color3.fromRGB(255, 196, 140)
	lamp.Range = 26
	lamp.Brightness = 0.9
	lamp.Parent = anchor
	-- The sign over the doorway, facing the hub
	local sign =
		block(den, "Sign", Vector3.new(16, 3.2, 0.6), at(hub.radius - 1.2, hub.denFloorY + 25.5), ROCK_DARK)
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

-- The hub: the cavern is Terrain (Cave.luau: the seamount, the dome and oculus,
-- the den rooms and tunnels); parts add what terrain can't (pools, lamps, signs,
-- sconces, the plaza, the beacon, light shafts).
-- The way out, built into the rock (owner, 2026-10-08: the EXIT chips were "a
-- flashing blue box that says EXIT in black on every exit"): a carved lintel over
-- each tunnel mouth with EXIT cut into it, a teal lantern either side, and lanterns
-- round the oculus. The tutorial breathes the `ExitLight` lanterns brighter when it
-- asks the player to find the way out; nothing floats and nothing flashes.
local EXIT_GLOW = Color3.fromRGB(110, 220, 235)

local function exitLantern(parent: Instance, position: Vector3)
	local lantern = Instance.new("Part")
	lantern.Name = "ExitLantern"
	lantern.Anchored = true
	lantern.CanCollide = false
	lantern.CanQuery = false
	lantern.CanTouch = false
	lantern.Shape = Enum.PartType.Ball
	lantern.Size = Vector3.one * 1.6
	lantern.CFrame = CFrame.new(position)
	lantern.Color = EXIT_GLOW
	lantern.Material = Enum.Material.Neon
	lantern.Transparency = 0.3
	lantern.Parent = parent
	local light = Instance.new("PointLight")
	light.Color = EXIT_GLOW
	light.Range = 26
	light.Brightness = 0.7
	light.Parent = lantern
	CollectionService:AddTag(lantern, "ExitLight")
	Props.dress(lantern, "Lantern", {
		cframe = CFrame.new(position),
		size = Vector3.new(2.4, 3.2, 2.4),
		keepVisible = true,
	})
end

local function exitDressing(parent: Instance, at: (number, number) -> CFrame)
	local lintel = block(
		parent,
		"ExitLintel",
		Vector3.new(28, 4, 3),
		at(hub.radius - 1, hub.tunnelHeight + 4),
		ROCK_DARK,
		Enum.Material.Slate
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- toward the plaza (the frame looks out along the tunnel)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.6
	gui.Brightness = 1.3
	gui.Parent = lintel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.SemiBold)
	label.TextScaled = true
	label.TextColor3 = EXIT_GLOW
	label.TextTransparency = 0.2
	label.Text = "E X I T"
	label.Parent = gui
	for side = -1, 1, 2 do
		local frame = at(hub.radius - 1, hub.tunnelHeight / 2 + 4) * CFrame.new(side * 21, 0, 0)
		exitLantern(parent, frame.Position)
	end
end

local function buildHub(parent: Instance)
	local hubFolder = folder("Hub", parent)
	Cave.apply(workspace.Terrain, Cave.ops())
	local denIndex = 0
	for segment = 1, hub.segments do
		local angle = Layout.segmentAngle(segment)
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local function at(r: number, y: number): CFrame
			local position = hub.center + radial * r + Vector3.new(0, y, 0)
			return CFrame.lookAt(position, position + radial)
		end
		local kind = Layout.segmentKind(segment)
		if kind == "den" then
			denIndex += 1
			buildDen(hubFolder, denIndex, segment)
		elseif kind == "tunnel" then
			exitDressing(hubFolder, at)
		elseif kind == "wall" then
			-- A sconce between openings, just proud of the rock
			local sconce =
				block(hubFolder, "Sconce", Vector3.new(2, 2, 1), at(hub.radius - 1.5, 18), ROCK_DARK)
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
	Props.dress(crystal, "CrystalCluster", {
		cframe = CFrame.new(hub.center + Vector3.new(0, 11, 0)),
		size = Vector3.new(18, 22, 18),
	})
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(110, 230, 255)
	glow.Range = 60
	glow.Brightness = 1.2
	glow.Parent = crystal

	-- Lanterns round the oculus: the way out through the roof
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		exitLantern(
			hubFolder,
			hub.center
				+ Vector3.new(
					math.cos(a) * (hub.oculusRadius + 6),
					hub.height - 4,
					math.sin(a) * (hub.oculusRadius + 6)
				)
		)
	end

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
local function keeper(parent: Instance, at: CFrame, color: Color3, vendorId: string)
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
	-- The keeper's own model (WorldProps.Keeper<VendorId>, from the approved Vendors
	-- concept) replaces the placeholder ball and eyes when it's imported. A GLB
	-- prop's front is +Z, so it's turned round to face the beacon like the stall.
	local dressed = Props.dress(body, `Keeper{vendorId}`, {
		cframe = at * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, math.pi, 0),
		size = Vector3.new(6.5, 7, 6.5),
	})
	if dressed then
		body.Transparency = 1
		return
	end
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

-- The four vendor stalls round the plaza (Config/Shop). The client shows its own
-- "E · Shop" hint near a counter (MenuController): a ProximityPrompt never showed
-- for the custom fish character (playtest 2026-10-06).
local function buildVendors(parent: Instance)
	local market = folder("Vendors", parent)
	local plazaTop = Layout.PLAZA_TOP
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
			Layout.COUNTER_SIZE,
			at(Layout.COUNTER_RADIUS, plazaTop + Layout.COUNTER_SIZE.Y / 2),
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
			Props.dress(lantern, "Lantern", {
				cframe = lantern.CFrame.Rotation + lantern.Position,
				size = Vector3.new(1.6, 2.4, 1.6),
				keepVisible = true,
			})
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
		keeper(stall, at(36.2, plazaTop + 4.2), vendor.color:Lerp(Color3.new(1, 1, 1), 0.25), vendor.id)
		-- The imported stall stands where the counter is, facing the beacon; the
		-- block posts and awning go when it's in (the sign and keeper stay)
		local stallModel = Props.dress(counter, "MarketStall", {
			cframe = at(33.5, plazaTop + 5.5) * CFrame.Angles(0, math.pi, 0),
			size = Vector3.new(15, 11, 9),
			tint = vendor.color:Lerp(Color3.new(1, 1, 1), 0.6),
		})
		if stallModel then
			for _, child in stall:GetChildren() do
				if child.Name == "Post" or child.Name == "Awning" then
					child:Destroy()
				elseif child.Name == "Lantern" and child:IsA("BasePart") then
					child.Transparency = 1
				end
			end
		end

		counter:SetAttribute("Vendor", vendor.id)
		vendorPositions[vendor.id] = Layout.counterPosition(vendor.angle)
		stall.Parent = market
	end
end

-- Where a vendor's counter is (for the server's reach check).
function WorldService.vendorPosition(id: string): Vector3?
	return vendorPositions[id]
end

local WRECK_WOOD = Color3.fromRGB(70, 52, 38)
local WRECK_WOOD_LIGHT = Color3.fromRGB(110, 86, 60)
local STONE_PALE = Color3.fromRGB(176, 166, 140)
local CORAL_COLORS = {
	Color3.fromRGB(240, 110, 120),
	Color3.fromRGB(255, 160, 80),
	Color3.fromRGB(170, 110, 220),
	Color3.fromRGB(250, 220, 110),
	Color3.fromRGB(90, 200, 190),
}

-- A random spot inside a biome's sector and radii, on the ground, clear of the hub
-- and (unless it's the Trench) of the canyon: x, z, the ground point and its normal
local function spotIn(rng: Random, biomeId: string, margin: number): (Vector3?, Vector3?)
	local biome = Config.Biomes.byId[biomeId]
	local hubClear = hub.radius + hub.wallThickness + hub.tunnelLength + 10 + margin
	for _ = 1, 40 do
		local span = (biome.angleTo - biome.angleFrom) % 360
		local angle = math.rad(biome.angleFrom + rng:NextNumber(0, if span == 0 then 360 else span))
		local r = rng:NextNumber(math.max(biome.radiusFrom + margin, hubClear), biome.radiusTo - margin)
		local x, z = math.cos(angle) * r, math.sin(angle) * r
		if biomeId ~= "AbyssalTrench" and Seafloor.inTrench(x, z, margin + 20) then
			continue
		end
		if r > World.boundsRadius - 30 then
			continue
		end
		local ground, normal = groundAt(x, z)
		if ground and normal and normal.Y > 0.55 then
			return ground, normal
		end
	end
	return nil, nil
end

-- Kelp forests: tall stalks with blades, in clusters (good cover for small fish)
local function kelpCluster(parent: Instance, rng: Random, center: Vector3, count: number, scale: number)
	for _ = 1, count do
		local x = center.X + rng:NextNumber(-34, 34)
		local z = center.Z + rng:NextNumber(-34, 34)
		local ground = groundAt(x, z)
		local base0 = ground or Vector3.new(x, center.Y, z)
		local height = rng:NextNumber(50, 190) * scale
		local lean =
			CFrame.Angles(rng:NextNumber(-0.06, 0.06), rng:NextNumber(0, 6.28), rng:NextNumber(-0.06, 0.06))
		local base = CFrame.new(base0) * lean
		local plant = Instance.new("Model")
		plant.Name = "Kelp"
		plant.Parent = parent
		local stalk = block(
			plant,
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
				plant,
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
		local upright = CFrame.new(base0 + Vector3.new(0, height / 2, 0))
			* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		local dressed = Props.dress(stalk, if rng:NextNumber() < 0.75 then "GiantKelp" else "KelpClump", {
			cframe = upright,
			size = Vector3.new(height * 0.22 + 4, height, height * 0.22 + 4),
		})
		if dressed then
			for _, child in plant:GetChildren() do
				if child.Name == "Blade" then
					child:Destroy()
				end
			end
		end
	end
end

local function rock(parent: Instance, rng: Random, ground: Vector3, scale: number, dark: boolean?)
	local size = Vector3.new(rng:NextNumber(6, 30), rng:NextNumber(5, 22), rng:NextNumber(6, 30)) * scale
	local yaw = rng:NextNumber(0, 6.28)
	local part = block(
		parent,
		"Rock",
		size,
		CFrame.new(ground + Vector3.new(0, size.Y * 0.25, 0))
			* CFrame.Angles(rng:NextNumber(-0.4, 0.4), yaw, rng:NextNumber(-0.4, 0.4)),
		if dark then ROCK_DARK else ROCK,
		Enum.Material.Rock
	)
	Props.dress(part, if rng:NextNumber() < 0.6 then "BoulderRound" else "BoulderJagged", {
		cframe = CFrame.new(ground + Vector3.new(0, size.Y * 0.42, 0)) * CFrame.Angles(0, yaw, 0),
		size = Vector3.new(size.X * 1.1, size.Y * 0.95, size.Z * 1.1),
	})
end

local function arch(parent: Instance, rng: Random, ground: Vector3)
	local gap = rng:NextNumber(5, 9)
	local height = rng:NextNumber(14, 26)
	local base = CFrame.new(ground) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	for side = -1, 1, 2 do
		block(
			parent,
			"ArchPillar",
			Vector3.new(8, height, 8),
			base * CFrame.new(side * (gap / 2 + 4), height / 2, 0),
			ROCK_DARK,
			Enum.Material.Rock
		)
	end
	block(
		parent,
		"ArchTop",
		Vector3.new(gap + 20, 7, 10),
		base * CFrame.new(0, height + 3.5, 0),
		ROCK_DARK,
		Enum.Material.Rock
	)
end

-- A coral garden: a spread of corals, sponges and anemones on and round a spot
local function coralGarden(parent: Instance, rng: Random, center: Vector3, count: number, spread: number)
	local kinds = { "BrainCoral", "FanCoral", "StaghornCoral", "TubeSponge", "Anemone" }
	for _ = 1, count do
		local x = center.X + rng:NextNumber(-spread, spread)
		local z = center.Z + rng:NextNumber(-spread, spread)
		local ground = groundAt(x, z) or Vector3.new(x, center.Y, z)
		local size = rng:NextNumber(2, 8)
		local piece = Instance.new("Part")
		piece.Name = "Coral"
		piece.Anchored = true
		piece.Shape = if rng:NextNumber() < 0.5 then Enum.PartType.Ball else Enum.PartType.Cylinder
		piece.Size = if piece.Shape == Enum.PartType.Ball
			then Vector3.one * size
			else Vector3.new(size * 1.6, size * 0.6, size * 0.6)
		piece.CFrame = CFrame.new(ground + Vector3.new(0, size * 0.3, 0))
			* CFrame.Angles(0, rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(40, 90)))
		piece.Color = CORAL_COLORS[rng:NextInteger(1, #CORAL_COLORS)]
		piece.Material = Enum.Material.SmoothPlastic
		piece.CanCollide = false
		piece.Parent = parent
		Props.dress(piece, kinds[rng:NextInteger(1, #kinds)], {
			cframe = CFrame.new(ground + Vector3.new(0, size * 0.75, 0))
				* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			size = Vector3.new(size * 1.7, size * 1.5, size * 1.7),
		})
	end
end

-- A wreck: a listing hull with ribs, a broken mast, a scatter of crates and a lantern
local function wreck(parent: Instance, rng: Random, ground: Vector3)
	local model = Instance.new("Model")
	model.Name = "Wreck"
	model.Parent = parent
	local length = rng:NextNumber(60, 110)
	local beam = length * 0.28
	local base = CFrame.new(ground)
		* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		* CFrame.Angles(0, 0, math.rad(rng:NextNumber(-28, 28)))
	block(
		model,
		"Keel",
		Vector3.new(length, 5, beam * 0.55),
		base * CFrame.new(0, 2.5, 0),
		WOOD,
		Enum.Material.WoodPlanks
	)
	for side = -1, 1, 2 do
		block(
			model,
			"Hull",
			Vector3.new(length * 0.92, beam * 0.55, 2.5),
			base * CFrame.new(0, beam * 0.24, side * beam * 0.34) * CFrame.Angles(math.rad(side * -30), 0, 0),
			WOOD,
			Enum.Material.WoodPlanks
		)
	end
	for i = 1, 7 do
		local x = -length * 0.42 + (i - 1) * (length * 0.84 / 6)
		for side = -1, 1, 2 do
			block(
				model,
				"Rib",
				Vector3.new(2, beam * 0.7, 2),
				base
					* CFrame.new(x, beam * 0.4, side * beam * 0.46)
					* CFrame.Angles(math.rad(side * -22), 0, 0),
				WRECK_WOOD_LIGHT,
				Enum.Material.Wood
			)
		end
	end
	for _ = 1, 3 do
		block(
			model,
			"Plank",
			Vector3.new(rng:NextNumber(10, 24), 1, rng:NextNumber(3, 6)),
			base
				* CFrame.new(
					rng:NextNumber(-length * 0.4, length * 0.4),
					beam * 0.55,
					rng:NextNumber(-beam * 0.3, beam * 0.3)
				)
				* CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0),
			WRECK_WOOD_LIGHT,
			Enum.Material.WoodPlanks
		)
	end
	local mast = Instance.new("Part")
	mast.Name = "Mast"
	mast.Anchored = true
	mast.Shape = Enum.PartType.Cylinder
	mast.Size = Vector3.new(beam * 1.5, 2.6, 2.6)
	mast.CFrame = base
		* CFrame.new(length * 0.1, beam * 0.9, 0)
		* CFrame.Angles(0, 0, math.rad(rng:NextNumber(55, 80)))
	mast.Color = WRECK_WOOD
	mast.Material = Enum.Material.Wood
	mast.Parent = model
	for _ = 1, 5 do
		local x = ground.X + rng:NextNumber(-length * 0.6, length * 0.6)
		local z = ground.Z + rng:NextNumber(-length * 0.6, length * 0.6)
		local crateGround = groundAt(x, z) or Vector3.new(x, ground.Y, z)
		local size = rng:NextNumber(4, 7)
		block(
			model,
			"Crate",
			Vector3.one * size,
			CFrame.new(crateGround + Vector3.new(0, size * 0.4, 0))
				* CFrame.Angles(0, rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3)),
			WRECK_WOOD_LIGHT,
			Enum.Material.WoodPlanks
		)
	end
	local lanternPart = block(
		model,
		"Lantern",
		Vector3.new(2, 3, 2),
		base * CFrame.new(-length * 0.3, beam * 0.6 + 1.5, 0),
		Color3.fromRGB(255, 200, 120),
		Enum.Material.Neon
	)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 110)
	light.Brightness = 1.4
	light.Range = 26
	light.Parent = lanternPart
	Props.dress(lanternPart, "Lantern", { cframe = lanternPart.CFrame, size = Vector3.new(3, 4.5, 3) })
end

-- A ruin: columns, a lintel, steps, a statue and a teal lantern
local function ruin(parent: Instance, rng: Random, anchor: Vector3)
	local model = Instance.new("Model")
	model.Name = "Ruin"
	model.Parent = parent
	local base = CFrame.new(anchor) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	local columns = rng:NextInteger(4, 6)
	local radius = rng:NextNumber(14, 22)
	local tallest = 0
	for i = 1, columns do
		local a = (i / columns) * 2 * math.pi
		local height = rng:NextNumber(14, 40)
		if rng:NextNumber() < 0.3 then
			height *= 0.45 -- broken
		end
		tallest = math.max(tallest, height)
		local column = Instance.new("Part")
		column.Name = "Column"
		column.Anchored = true
		column.Shape = Enum.PartType.Cylinder
		column.Size = Vector3.new(height, 5, 5)
		column.CFrame = base
			* CFrame.new(math.cos(a) * radius, height / 2, math.sin(a) * radius)
			* CFrame.Angles(0, 0, math.rad(90))
		column.Color = STONE_PALE
		column.Material = Enum.Material.Sandstone
		column.Parent = model
	end
	block(
		model,
		"Lintel",
		Vector3.new(radius * 1.6, 4, 6),
		base * CFrame.new(0, tallest + 2, radius),
		STONE_PALE,
		Enum.Material.Sandstone
	)
	for step = 1, 3 do
		block(
			model,
			"Step",
			Vector3.new(radius * 1.4, 2, 5),
			base * CFrame.new(0, step, -radius - step * 4),
			STONE_PALE,
			Enum.Material.Sandstone
		)
	end
	block(
		model,
		"Plinth",
		Vector3.new(8, 4, 8),
		base * CFrame.new(0, 2, 0),
		STONE_PALE,
		Enum.Material.Sandstone
	)
	block(
		model,
		"Statue",
		Vector3.new(4, 12, 4),
		base * CFrame.new(0, 10, 0) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-8, 8))),
		STONE_PALE,
		Enum.Material.Sandstone
	)
	local head = Instance.new("Part")
	head.Anchored = true
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.one * 4.5
	head.CFrame = base * CFrame.new(0, 18, 0)
	head.Color = STONE_PALE
	head.Material = Enum.Material.Sandstone
	head.Parent = model
	local lanternPart = block(
		model,
		"Lantern",
		Vector3.new(2, 3, 2),
		base * CFrame.new(radius * 0.6, 6, 0),
		Color3.fromRGB(120, 255, 230),
		Enum.Material.Neon
	)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(120, 255, 230)
	light.Brightness = 1.6
	light.Range = 34
	light.Parent = lanternPart
	Props.dress(lanternPart, "Lantern", { cframe = lanternPart.CFrame, size = Vector3.new(3, 4.5, 3) })
end

-- A vent chimney's dressing: the glow at its cap and the black smoke it breathes
local function ventSmoke(parent: Instance, chimney: { position: Vector3, height: number })
	local top = chimney.position + Vector3.new(0, chimney.height, 0)
	local holder = Instance.new("Part")
	holder.Name = "VentSmoke"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(4, 2, 4)
	holder.CFrame = CFrame.new(top + Vector3.new(0, 2, 0))
	holder.Parent = parent
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 130, 50)
	light.Brightness = 2.2
	light.Range = 40
	light.Parent = holder
	local smoke = Instance.new("ParticleEmitter")
	smoke.Rate = 14
	smoke.Lifetime = NumberRange.new(4, 7)
	smoke.Speed = NumberRange.new(6, 11)
	smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.Acceleration = Vector3.new(0, 2, 0)
	smoke.Drag = 0.6
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(0.5, 9),
		NumberSequenceKeypoint.new(1, 14),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.7, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Color = ColorSequence.new(Color3.fromRGB(30, 26, 30), Color3.fromRGB(14, 12, 16))
	smoke.LightInfluence = 0.3
	smoke.Parent = holder
end

-- The biomes' dressing, placed on the Terrain by raycast: dense kelp, rocks and
-- arches in the Kelp Shallows; wrecks in the Graveyard; coral gardens and reef rocks
-- in the Coral Reef; ruins to the east; glowing, smoking chimneys at the Vents;
-- bioluminescent specks down the Trench's walls; light shafts over the shallows.
local function buildBiomes(parent: Instance)
	local rng = Random.new(World.seed + 3)
	local kelpFolder = folder("Kelp", parent)
	local rocks = folder("Rocks", parent)
	local corals = folder("Coral", parent)
	local wrecks = folder("Wrecks", parent)
	local ruins = folder("Ruins", parent)
	local vents = folder("Vents", parent)
	local trenchGlow = folder("TrenchGlow", parent)
	local shafts = folder("Shafts", parent)

	-- Kelp Shallows: forests, boulder fields, arches (the open biome, by design)
	for _ = 1, 52 do
		local ground = spotIn(rng, "KelpShallows", 40)
		if ground then
			kelpCluster(kelpFolder, rng, ground, 20, 1)
		end
	end
	for _ = 1, 150 do
		local ground = spotIn(rng, "KelpShallows", 16)
		if ground then
			rock(rocks, rng, ground, 1)
		end
	end
	for _ = 1, 24 do
		local ground = spotIn(rng, "KelpShallows", 40)
		if ground then
			arch(rocks, rng, ground)
		end
	end
	for _ = 1, 10 do
		local ground = spotIn(rng, "KelpShallows", 50)
		if ground then
			coralGarden(corals, rng, ground, 24, 30)
		end
	end

	-- Shipwreck Graveyard: wrecks in a kelp fringe, dark rocks
	for _ = 1, 14 do
		local ground = spotIn(rng, "ShipwreckGraveyard", 70)
		if ground then
			wreck(wrecks, rng, ground)
		end
	end
	for _ = 1, 18 do
		local ground = spotIn(rng, "ShipwreckGraveyard", 40)
		if ground then
			kelpCluster(kelpFolder, rng, ground, 14, 0.8)
		end
	end
	for _ = 1, 100 do
		local ground = spotIn(rng, "ShipwreckGraveyard", 16)
		if ground then
			rock(rocks, rng, ground, 1.1, true)
		end
	end

	-- Coral Reef: corals grow on and round every reef head and ridge the Terrain laid
	-- (owner, 2026-10-08: "just a bunch of scattered coral laying around"), with more
	-- gardens between, reef rocks and arches
	for _, reef in features.reefRocks do
		coralGarden(corals, rng, reef.center, 36, reef.radius * 1.25)
	end
	for _ = 1, 60 do
		local ground = spotIn(rng, "CoralReef", 60)
		if ground then
			coralGarden(corals, rng, ground, 50, 60)
		end
	end
	for _ = 1, 120 do
		local ground = spotIn(rng, "CoralReef", 16)
		if ground then
			rock(rocks, rng, ground, 1.3)
		end
	end
	for _ = 1, 16 do
		local ground = spotIn(rng, "CoralReef", 40)
		if ground then
			arch(rocks, rng, ground)
		end
	end

	-- Open Blue: deep blue water over a blue floor with big dark rocks, knolls and the
	-- pinnacles; the sharks, the grouper and snapper schools and the Megalodon are its
	-- content (owner, 2026-10-08), so the water itself stays open
	for _ = 1, 40 do
		local ground = spotIn(rng, "OpenBlue", 20)
		if ground then
			rock(rocks, rng, ground, 1.8, true)
		end
	end

	-- Sunken Ruins: temples round the plinths the Terrain laid, plus a few more
	for _, anchor in features.ruinAnchors do
		ruin(ruins, rng, anchor)
	end
	for _ = 1, 8 do
		local ground = spotIn(rng, "SunkenRuins", 60)
		if ground then
			ruin(ruins, rng, ground)
		end
	end
	for _ = 1, 80 do
		local ground = spotIn(rng, "SunkenRuins", 16)
		if ground then
			rock(rocks, rng, ground, 1.3, true)
		end
	end

	-- Hydrothermal Vents: every chimney glows and smokes; basalt rubble
	for _, chimney in features.chimneys do
		ventSmoke(vents, chimney)
	end
	for _ = 1, 90 do
		local ground = spotIn(rng, "HydrothermalVents", 16)
		if ground then
			rock(rocks, rng, ground, 1.2, true)
		end
	end

	-- Abyssal Trench: bioluminescent specks down the canyon's walls, faint blue lights
	for i = 1, 130 do
		local trench = World.trench
		local r = rng:NextNumber(trench.radii[1] + 20, trench.radii[2] - 20)
		local _, width = Seafloor.trenchAxis(r)
		local halfTop, _, halfBottom = Seafloor.trenchHalfWidths(width)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local x, z = Seafloor.trenchPoint(r, side * rng:NextNumber(halfBottom + 6, halfTop - 30))
		local position = Vector3.new(x, rng:NextNumber(trench.floorY + 10, World.deep.floorY - 15), z)
		local speck = Instance.new("Part")
		speck.Name = "Glow"
		speck.Anchored = true
		speck.CanCollide = false
		speck.CanQuery = false
		speck.Shape = Enum.PartType.Ball
		speck.Size = Vector3.one * rng:NextNumber(0.8, 2.2)
		speck.CFrame = CFrame.new(position)
		speck.Color = Color3.fromRGB(110, 230, 255)
		speck.Material = Enum.Material.Neon
		speck.Parent = trenchGlow
		if i % 3 == 0 then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(110, 230, 255)
			light.Brightness = 0.9
			light.Range = 30
			light.Parent = speck
		end
		Props.dress(
			speck,
			"CrystalCluster",
			{ cframe = speck.CFrame, size = Vector3.one * speck.Size.X * 2.5 }
		)
	end

	-- Light shafts from the surface over the shelf, and a few long ones in the Open Blue
	for _ = 1, 50 do
		local ground = spotIn(rng, "KelpShallows", 0)
		if ground then
			local slant = Vector3.new(rng:NextNumber(-50, 50), 0, rng:NextNumber(-50, 50))
			lightShaft(
				shafts,
				Vector3.new(ground.X, World.surfaceY - 2, ground.Z),
				ground + Vector3.new(0, 10, 0) + slant,
				rng:NextNumber(12, 26),
				0.22
			)
		end
	end
	for _, biomeId in { "CoralReef", "ShipwreckGraveyard" } do
		for _ = 1, 16 do
			local ground = spotIn(rng, biomeId, 0)
			if ground then
				local slant = Vector3.new(rng:NextNumber(-50, 50), 0, rng:NextNumber(-50, 50))
				lightShaft(
					shafts,
					Vector3.new(ground.X, World.surfaceY - 2, ground.Z),
					ground + Vector3.new(0, 10, 0) + slant,
					rng:NextNumber(12, 26),
					0.2
				)
			end
		end
	end
	for _ = 1, 14 do
		local ground = spotIn(rng, "OpenBlue", 0)
		if ground then
			local slant = Vector3.new(rng:NextNumber(-80, 80), 0, rng:NextNumber(-80, 80))
			lightShaft(
				shafts,
				Vector3.new(ground.X, World.surfaceY - 2, ground.Z),
				Vector3.new(ground.X, -260, ground.Z) + slant,
				rng:NextNumber(18, 34),
				0.14
			)
		end
	end
	-- The pinnacles' tops catch a light
	for _, top in features.pinnacles do
		local slant = Vector3.new(rng:NextNumber(-20, 20), 0, rng:NextNumber(-20, 20))
		lightShaft(
			shafts,
			Vector3.new(top.X, World.surfaceY - 2, top.Z),
			top + Vector3.new(0, 4, 0) + slant,
			16,
			0.2
		)
	end
end

local denOwnerNames: { [number]: string? } = {}
local denLevelNames: { [number]: string? } = {}

local function refreshSign(index: number)
	local label = denSigns[index]
	if not label then
		return
	end
	local owner = denOwnerNames[index]
	local level = denLevelNames[index]
	if owner then
		label.Text = `{string.upper(owner)}'S {if level then string.upper(level) else "DEN"}`
	else
		label.Text = `DEN {index}`
	end
end

-- Shows who owns a den on its sign (nil = free).
function WorldService.setDenOwner(index: number, name: string?)
	denOwnerNames[index] = name
	refreshSign(index)
end

-- The den's level name on its sign (nil = plain)
function WorldService.setDenLevel(index: number, levelName: string?)
	denLevelNames[index] = levelName
	refreshSign(index)
end

function WorldService.start()
	setupLighting()
	root = folder("World", workspace)
	buildSeabed()
	buildBounds(folder("Bounds", root))
	buildHub(root)
	buildVendors(root:FindFirstChild("Hub") :: Folder)
	awaitTerrain()
	buildBiomes(folder("Biomes", root))
end

return WorldService
