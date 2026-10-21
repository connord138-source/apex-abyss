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
local Decor = require(script.Parent.Parent.Decor)
local DenDoor = require(script.Parent.Parent.DenDoor)
local Plaza = require(script.Parent.Parent.Plaza)
local Ruins = require(script.Parent.Parent.Ruins)
local Props = require(ReplicatedStorage.Shared.Props)
local TreasureWheel = require(script.Parent.Parent.TreasureWheel)
local Shelf = require(script.Parent.Parent.Shelf)
local Vents = require(script.Parent.Parent.Vents)
local Cliff = require(script.Parent.Parent.Cliff)
local Wrecks = require(script.Parent.Parent.Wrecks)
local TrenchDress = require(script.Parent.Parent.TrenchDress)
local KelpDress = require(script.Parent.Parent.KelpDress)
local LandmarkKit = require(script.Parent.Parent.LandmarkKit)
local PlaceMarks = require(script.Parent.Parent.PlaceMarks)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)

local World = Config.World
local hub = World.hub

local WorldService = {
	-- The Treasure Wheel on the plaza (Config/Wheel; WheelService spins it), once built
	wheel = nil :: TreasureWheel.Built?,
}

local root: Folder
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
	-- Half as blue as it was, at the same brightness (playtest 2026-10-10: under
	-- (26, 58, 82) / (56, 108, 136) gold skins read lime and lilac read royal blue);
	-- the water's haze and the colour grade still carry the blue
	Lighting.Ambient = Color3.fromRGB(40, 56, 68)
	Lighting.OutdoorAmbient = Color3.fromRGB(78, 104, 118)
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
-- the Trench canyon, the Vents' basin, the Ruins' ground. The features it returns
-- (chimneys, pinnacles, chutes, reef rocks) are dressed with parts below.
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

local denModels: { [number]: Model } = {}

-- One den's parts (owner, 2026-10-16: every den is a private interior far outside
-- the play area, Layout.denOrigin). On the plaza: its front door (DenDoor.front:
-- the stone arch, the nameplate, lanterns, steps and the bubble-curtain portal at
-- the doorway's back). Inside: its Haul Pool by the way in, and the way out on the
-- front wall (DenDoor.exit). The rooms are carved from the Terrain (DenCarve) and
-- furnished by DenBuilder.
local function buildDen(parent: Instance, index: number)
	local den = Instance.new("Model")
	den.Name = `Den{index}`
	DenDoor.front(den, index)
	-- The Haul Pool: swim into it to bank (you come in over it)
	local poolRadius = Config.Dens.pool.radius
	local pool = Instance.new("Part")
	pool.Name = "HaulPool"
	pool.Anchored = true
	pool.CanCollide = false
	pool.Shape = Enum.PartType.Cylinder
	pool.Size = Vector3.new(1, poolRadius * 2, poolRadius * 2)
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
	-- The way out, on the front wall, under its TO THE HUB plaque
	DenDoor.exit(den, index)
	den.Parent = parent
	denModels[index] = den
end

-- The hub: the cavern is Terrain (Cave.luau: the seamount, the dome and oculus,
-- the doorways and tunnels); parts add what terrain can't: the dens' doors, the
-- plaza (Plaza.luau: paving, dais and beacon, gardens, lamps, stalls), the exit
-- boards and lanterns, light shafts.
-- The way out, built into the rock (owner, 2026-10-08: the EXIT chips were "a
-- flashing blue box that says EXIT in black on every exit"): a board over each
-- tunnel mouth saying EXIT, the way it goes and the biomes out there (Plaza), a teal
-- lantern either side of it, and lanterns round the oculus. The tutorial breathes
-- the `ExitLight` lanterns brighter when it asks the player to find the way out;
-- nothing floats and nothing flashes.
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

-- Where the rock face is along `radial` from inside the cavern (the nearest of a
-- few rays round `center`), or nil. The cavern wall is ragged Terrain, so a sign
-- placed at a fixed radius sank into it (playtest 2026-10-08: the EXIT lintel was
-- half inside the rock).
local wallRays = RaycastParams.new()
wallRays.FilterType = Enum.RaycastFilterType.Include
local function wallAt(radial: Vector3, right: Vector3, center: Vector3, spread: number): number?
	wallRays.FilterDescendantsInstances = { workspace.Terrain }
	local nearest: number? = nil
	for _, dx in { -spread, 0, spread } do
		for _, dy in { -2, 2 } do
			local origin = hub.center + radial * 50 + right * dx + Vector3.new(0, center.Y + dy, 0)
			local hit = workspace:Raycast(origin, radial * 90, wallRays)
			if hit then
				local r = (hit.Position - hub.center):Dot(radial)
				if r < hub.radius + 12 then
					nearest = if nearest then math.min(nearest, r) else r
				end
			end
		end
	end
	return nearest
end

-- A tunnel mouth's dressing: the board over the opening and a teal lantern at
-- either end of it, on the board's own brackets (owner, 2026-10-17: they had stood
-- at the mouth's sides, which is where the dens' doorways beside it open, so they
-- hung inside those doorways). Built once the Terrain answers raycasts.
local TUNNEL_RADIUS = hub.tunnelHeight / 2 - 2 -- Cave.luau's tube
local function exitDressing(parent: Instance, segment: number)
	local angle = Layout.segmentAngle(segment)
	local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local right = radial:Cross(Vector3.yAxis).Unit
	-- Just above the tube's top (it's centered TUNNEL_RADIUS + 1 up)
	local boardY = TUNNEL_RADIUS * 2 + 1 + 4.6
	local face = wallAt(radial, right, Vector3.new(0, boardY, 0), 11) or (hub.radius - 1)
	local board = Plaza.tunnelBoard(parent, angle, face, boardY)
	for side = -1, 1, 2 do
		local glass = Decor.lantern(
			parent,
			board * CFrame.new(side * 13.6, -0.6, -1.2),
			-side,
			true,
			26,
			EXIT_GLOW
		).glass
		glass.Name = "ExitLantern"
		glass.Transparency = 0.3
		local light = glass:FindFirstChildOfClass("PointLight")
		if light then
			light.Brightness = 0.7
		end
		CollectionService:AddTag(glass, "ExitLight")
	end
end

local tunnelSegments: { number } = {}

local function buildHub(parent: Instance)
	local hubFolder = folder("Hub", parent)
	Cave.apply(workspace.Terrain, Cave.ops())
	local denIndex = 0
	for segment = 1, hub.segments do
		local kind = Layout.segmentKind(segment)
		if kind == "den" then
			denIndex += 1
			buildDen(hubFolder, denIndex)
		elseif kind == "tunnel" then
			table.insert(tunnelSegments, segment)
		end
	end
	-- The plaza: paving, the dais and beacon, gardens, lamps and wall lanterns
	Plaza.build(hubFolder)

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

-- The vendor stalls round the plaza (Plaza.vendors builds them, part-built: the
-- imported market stall's texture read fuzzy up close, owner 2026-10-17)
local function buildVendors(parent: Instance)
	Plaza.vendors(parent)
	for _, vendor in Config.Shop.vendors do
		vendorPositions[vendor.id] = Layout.counterPosition(vendor.angle)
	end
end

-- Where a vendor's counter is (for the server's reach check).
function WorldService.vendorPosition(id: string): Vector3?
	return vendorPositions[id]
end

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
	-- Round boulders only: the jagged one read as unnatural (owner, 2026-10-11: "Needs
	-- more of a toonish rounded off look")
	rng:NextNumber() -- (keeps the scatter's random sequence where it was)
	Props.dress(part, "BoulderRound", {
		cframe = CFrame.new(ground + Vector3.new(0, size.Y * 0.42, 0)) * CFrame.Angles(0, yaw, 0),
		size = Vector3.new(size.X * 1.1, size.Y * 0.95, size.Z * 1.1),
		solid = true,
		blocksCamera = true,
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
		-- Hard corals and sponges are solid (owner, 2026-10-10: "a lot of the coral i
		-- can go right through"); anemones stay soft to swim through
		local kind = kinds[rng:NextInteger(1, #kinds)]
		local hard = kind ~= "Anemone"
		piece.CanCollide = hard
		piece.CanQuery = false -- the camera passes through coral
		piece.Parent = parent
		Props.dress(piece, kind, {
			cframe = CFrame.new(ground + Vector3.new(0, size * 0.75, 0))
				* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			size = Vector3.new(size * 1.7, size * 1.5, size * 1.7),
			solid = hard,
		})
	end
end

-- A wreck in the Graveyard (owner, 2026-10-21: the Broken Galleon board): its length,
-- heading and list are drawn here, then Wrecks.luau builds a hull, stern, steamer or
-- debris field there from the bay's models. The old part-built hull's draws are still
-- taken (44 a wreck), so everything after it on the shared Random keeps its place.
local wreckCount = 0
local function wreck(parent: Instance, rng: Random, ground: Vector3)
	local length = rng:NextNumber(60, 110)
	local yaw = rng:NextNumber(0, 6.28)
	local tilt = math.rad(rng:NextNumber(-28, 28))
	for _ = 1, 41 do
		rng:NextNumber()
	end
	wreckCount += 1
	Wrecks.scatter(parent, ground, length, yaw, tilt * 0.5, wreckCount)
end

-- A vent chimney's dressing: the glow at its cap and the black smoke it breathes
-- A column of bubbles rising from a spot (vents, seeps in the sand): the water
-- always has something moving in it (owner, 2026-10-08)
local function bubbleColumn(holder: BasePart, strength: number)
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "BubbleColumn"
	bubbles.Rate = 6 * strength
	bubbles.Lifetime = NumberRange.new(6, 10)
	bubbles.Speed = NumberRange.new(5, 9)
	bubbles.SpreadAngle = Vector2.new(6, 6)
	bubbles.Acceleration = Vector3.new(0, 1.5, 0)
	bubbles.Drag = 0.3
	bubbles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15 * strength),
		NumberSequenceKeypoint.new(0.5, 0.35 * strength),
		NumberSequenceKeypoint.new(1, 0.5 * strength),
	})
	bubbles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.85, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	bubbles.Color = ColorSequence.new(Color3.fromRGB(222, 250, 255))
	bubbles.LightEmission = 0.5
	bubbles.LightInfluence = 0.7
	bubbles.Parent = holder
end

local function ventSmoke(parent: Instance, chimney: { position: Vector3, height: number })
	-- The cap's real top, by raycast: the chimney is capped by a ball of lava rock up
	-- to 8 studs round, and a throat at the nominal top sat buried in it (retest
	-- 2026-10-09: 25 of 26 throats were inside CrackedLava, so none showed)
	-- A chimney under other rock (a basin's rubble) breathes out through that rock's
	-- top instead (retest 2026-10-09: one throat sat 22 studs inside a rubble ball)
	local top = chimney.position + Vector3.new(0, chimney.height + 8, 0)
	local hit = groundAt(chimney.position.X, chimney.position.Z)
	local nominalTop = chimney.position.Y + chimney.height
	if hit and hit.Y > nominalTop - 20 and hit.Y < nominalTop + 90 then
		top = hit
	end
	local holder = Instance.new("Part")
	holder.Name = "VentSmoke"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(4, 2, 4)
	holder.CFrame = CFrame.new(top + Vector3.new(0, 4, 0))
	holder.Parent = parent
	-- The glowing throat: a light alone didn't read through the basin's water
	-- (retest 2026-10-08: a chimney 45 studs off was only a silhouette). A hot disc set
	-- level into the cap (owner, 2026-10-20: the Vents' balls "clearly placeholders")
	local throat = Instance.new("Part")
	throat.Name = "VentGlow"
	throat.Anchored = true
	throat.CanCollide = false
	throat.CanQuery = false
	throat.CanTouch = false
	throat.Shape = Enum.PartType.Cylinder
	throat.Size = Vector3.new(1, 4.6, 4.6)
	throat.CFrame = CFrame.new(top + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	throat.Color = Color3.fromRGB(255, 112, 36)
	throat.Material = Enum.Material.Neon
	throat.Parent = parent
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 130, 50)
	light.Brightness = 3
	light.Range = 50
	light.Shadows = false
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
	bubbleColumn(holder, 1.4)
end

-- Glowing fissures across the Vents' basin floors, so the floor (and its toon tile)
-- reads in the dark instead of only the chimneys' throats (PC 2026-10-17, T3: the
-- basalt floor read near black from 50 studs, however light its colour). Since PC
-- 2026-10-17 round 2 (V1: at ~100 studs only small red slivers showed and the tile
-- didn't; wide, near black) each basin has 4–6 fissure systems instead of 6 short
-- cracks, one near its middle and the rest spread round it: a long jagged trunk (a
-- bright core over a wider deep-red rim, so it reads as a glowing seam from far
-- off) running both ways from its spot, up to three thinner branches forking off it
-- across the floor, one big warm light over the spot (fewer, bigger lights: range
-- 60, Roblox's maximum, so their pools overlap over the whole floor), embers rising
-- off the trunk and a faint warm heat haze hugging it. Small built pieces, all Neon
-- (never a toon-overridden material): about 115 parts, 5 lights and 15 emitters a
-- basin (ten basins).
local FISSURE_CORE = Color3.fromRGB(255, 150, 54)
local FISSURE_RIM = Color3.fromRGB(150, 34, 14)
local FISSURE_LIGHT = Color3.fromRGB(255, 138, 72) -- (a little less red: Lilac read magenta-pink under it)
local FISSURE = {
	perRadius = 20, -- a basin gets one system per this many studs of its radius (4 to 6)
	middle = 0.15, -- the first system's spot, × the radius from the basin's middle
	ring = { 0.55, 0.7 }, -- the others', round it (~90–99% of a floor is in a light's range)
	trunk = { segments = { 3, 5 }, length = { 7, 12 }, turn = 0.45, width = { 1.3, 2 } }, -- each way from its spot
	branch = {
		chance = 0.45,
		max = 3,
		segments = { 2, 4 },
		length = { 5, 9 },
		turn = 0.5,
		width = { 0.6, 0.95 },
	},
	rim = 2.6, -- the rim's width × the core's
	edge = 6, -- studs a crack keeps inside the basin's wall
	step = 2.5, -- a crack stops where the floor jumps more than this (a chimney, rubble)
	light = { range = 60, brightness = 2.2, height = 8 },
}

local function fissurePiece(parent: Instance, from: Vector3, to: Vector3, width: number, rim: boolean): Part
	local span = to - from
	local piece = Instance.new("Part")
	piece.Name = if rim then "CrackRim" else "Crack"
	piece.Anchored = true
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.CastShadow = false
	piece.Material = Enum.Material.Neon
	piece.Color = if rim then FISSURE_RIM else FISSURE_CORE
	-- The rim lies just under the core, a little into the rock; both overlap at the
	-- joints so a turn shows no gap
	local thickness = if rim then 0.2 else 0.3
	local lift = Vector3.new(0, if rim then 0.06 else 0.12, 0)
	piece.Size = Vector3.new(width, thickness, span.Magnitude + width * 0.6)
	piece.CFrame = CFrame.lookAt(from + span / 2 + lift, to + lift)
	piece.Parent = parent
	return piece
end

-- A jagged path over the basin floor from `start`, stopping at the basin's wall or
-- where the floor jumps
local function fissurePath(
	rng: Random,
	basin: { x: number, z: number, radius: number },
	start: Vector3,
	heading: number,
	shape: { segments: { number }, length: { number }, turn: number }
): { Vector3 }
	local points: { Vector3 } = { start }
	local at = start
	for _ = 1, rng:NextInteger(shape.segments[1], shape.segments[2]) do
		heading += rng:NextNumber(-shape.turn, shape.turn)
		local length = rng:NextNumber(shape.length[1], shape.length[2])
		local x, z = at.X + math.cos(heading) * length, at.Z + math.sin(heading) * length
		if Vector2.new(x - basin.x, z - basin.z).Magnitude > basin.radius - FISSURE.edge then
			break
		end
		local ground = groundAt(x, z)
		if ground == nil or math.abs(ground.Y - at.Y) > FISSURE.step then
			break
		end
		table.insert(points, ground)
		at = ground
	end
	return points
end

-- The heading (radians about Y, from +X toward +Z) from one point to the next
local function headingOf(from: Vector3, to: Vector3): number
	return math.atan2(to.Z - from.Z, to.X - from.X)
end

local function emberEmitter(parent: Instance)
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 196, 96), Color3.fromRGB(255, 84, 30))
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.7, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Lifetime = NumberRange.new(3, 6)
	embers.Rate = 2.5
	embers.Speed = NumberRange.new(1.5, 3.5)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.SpreadAngle = Vector2.new(25, 25)
	embers.Acceleration = Vector3.new(0, 0.8, 0)
	embers.Drag = 0.4
	embers.RotSpeed = NumberRange.new(-60, 60)
	embers.Parent = parent
end

-- A low, faint warm haze over a trunk (the box along its chord): dimly self-lit,
-- rising only a few studs, so from far off the floor shows a warm glow over its seams
local function heatHaze(parent: Instance)
	local haze = Instance.new("ParticleEmitter")
	haze.Name = "HeatHaze"
	haze.Texture = "rbxasset://textures/particles/smoke_main.dds"
	haze.Color = ColorSequence.new(Color3.fromRGB(255, 120, 60), Color3.fromRGB(160, 50, 30))
	-- (bigger and less faint: at 5-12 studs and 0.86 the PC saw no haze at all)
	haze.LightEmission = 0.6
	haze.LightInfluence = 0.1
	haze.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 9),
		NumberSequenceKeypoint.new(1, 22),
	})
	haze.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.74),
		NumberSequenceKeypoint.new(0.7, 0.82),
		NumberSequenceKeypoint.new(1, 1),
	})
	haze.Lifetime = NumberRange.new(4, 7)
	haze.Rate = 3.5
	haze.Speed = NumberRange.new(0.6, 1.6)
	haze.EmissionDirection = Enum.NormalId.Top
	haze.SpreadAngle = Vector2.new(20, 20)
	haze.Acceleration = Vector3.new(0, 0.3, 0)
	haze.Drag = 0.5
	haze.Rotation = NumberRange.new(0, 360)
	haze.RotSpeed = NumberRange.new(-8, 8)
	haze.Parent = parent
end

local function ventFissures(parent: Instance, rng: Random)
	local systems, parts = 0, 0
	for _, basin in Seafloor.ventBasins() do
		local count = math.clamp(math.floor(basin.radius / FISSURE.perRadius + 0.5), 4, 6)
		local turn = rng:NextNumber(0, 2 * math.pi)
		for k = 1, count do
			-- One near the middle, the rest spread round it, each in its own slice, so
			-- the lights pool over the whole floor
			local angle = turn + (k - 2 + rng:NextNumber(0.3, 0.7)) * 2 * math.pi / (count - 1)
			local r = basin.radius
				* (
					if k == 1
						then rng:NextNumber(0, FISSURE.middle)
						else rng:NextNumber(FISSURE.ring[1], FISSURE.ring[2])
				)
			local spot = groundAt(basin.x + math.cos(angle) * r, basin.z + math.sin(angle) * r)
			if spot == nil or spot.Y > World.deep.floorY - 40 then
				continue
			end
			-- The trunk runs both ways from the spot, so the spot is its middle
			local heading = rng:NextNumber(0, 2 * math.pi)
			local ahead = fissurePath(rng, basin, spot, heading, FISSURE.trunk)
			local behind = fissurePath(rng, basin, spot, heading + math.pi, FISSURE.trunk)
			local trunk: { Vector3 } = {}
			for i = #behind, 2, -1 do
				table.insert(trunk, behind[i])
			end
			for _, point in ahead do
				table.insert(trunk, point)
			end
			if #trunk < 4 then
				continue
			end
			local crack = Instance.new("Model")
			crack.Name = "Fissure"
			local width = rng:NextNumber(FISSURE.trunk.width[1], FISSURE.trunk.width[2])
			local segments = #trunk - 1
			for i = 1, segments do
				-- Widest in its middle, narrowing toward both ends
				local w = width * (0.5 + 0.5 * math.sin(math.pi * (i - 0.5) / segments))
				local core = fissurePiece(crack, trunk[i], trunk[i + 1], w, false)
				fissurePiece(crack, trunk[i], trunk[i + 1], w * FISSURE.rim, true)
				if i % 4 == 2 then
					emberEmitter(core)
				end
			end
			local branches = 0
			for i = 2, #trunk - 1 do
				if branches >= FISSURE.branch.max or rng:NextNumber() > FISSURE.branch.chance then
					continue
				end
				local side = if rng:NextNumber() < 0.5 then -1 else 1
				local fork = headingOf(trunk[i - 1], trunk[i]) + side * rng:NextNumber(0.6, 1.1)
				local path = fissurePath(rng, basin, trunk[i], fork, FISSURE.branch)
				local bw = rng:NextNumber(FISSURE.branch.width[1], FISSURE.branch.width[2])
				for j = 1, #path - 1 do
					local taper = 1 - 0.35 * (j - 1) / math.max(1, #path - 2)
					fissurePiece(crack, path[j], path[j + 1], bw * taper, false)
				end
				if #path > 1 then
					branches += 1
				end
			end
			-- The haze lies along the trunk's chord; the light hangs over the spot
			local first, last = trunk[1], trunk[#trunk]
			local chord = Vector3.new(last.X - first.X, 0, last.Z - first.Z)
			local glow = Instance.new("Part")
			glow.Name = "FissureGlow"
			glow.Anchored = true
			glow.CanCollide = false
			glow.CanQuery = false
			glow.CanTouch = false
			glow.Transparency = 1
			glow.Size = Vector3.new(5, 1, math.max(chord.Magnitude, 8))
			local mid = (first + last) / 2 + Vector3.new(0, 1.5, 0)
			glow.CFrame = if chord.Magnitude > 1 then CFrame.lookAt(mid, mid + chord) else CFrame.new(mid)
			glow.Parent = crack
			heatHaze(glow)
			local lamp = Instance.new("Attachment")
			lamp.Name = "FissureLight"
			lamp.Position = glow.CFrame:PointToObjectSpace(spot + Vector3.new(0, FISSURE.light.height, 0))
			lamp.Parent = glow
			local light = Instance.new("PointLight")
			light.Color = FISSURE_LIGHT
			light.Brightness = FISSURE.light.brightness
			light.Range = FISSURE.light.range
			light.Shadows = false
			light.Parent = lamp
			crack.Parent = parent
			systems += 1
			parts += #crack:GetChildren()
		end
	end
	print(`[WorldService] Vents: {systems} fissure systems ({parts} parts, {systems} lights)`)
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

	-- Shipwreck Graveyard: the Broken Galleon, the Fallen Lighthouse, two steamers and
	-- the Bay Cannon (Wrecks.luau, on its own Random), then wrecks in a kelp fringe, dark
	-- rocks
	local wreckStats = Wrecks.build(wrecks, groundAt)
	for _ = 1, 14 do
		local ground = spotIn(rng, "ShipwreckGraveyard", 70)
		if ground then
			wreck(wrecks, rng, ground)
		end
	end
	print(
		`[Wrecks] the bay: {wreckStats.parts} parts ({wreckStats.solid} solid, {wreckStats.glow} glowing), {wreckStats.models} models and {wreckStats.standins} stand-ins, {wreckStats.lights} lights`
	)
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

	-- Open Blue: open ocean (owner, 2026-10-09) over a blue floor far below with big
	-- dark rocks, knolls and low spires; the sharks, the grouper and snapper schools
	-- and the Megalodon swim the water above it (owner, 2026-10-08)
	for _ = 1, 40 do
		local ground = spotIn(rng, "OpenBlue", 20)
		if ground then
			rock(rocks, rng, ground, 1.8, true)
		end
	end

	-- (Sunken Ruins: built last, by Ruins.luau)

	-- Hydrothermal Vents: every chimney glows and smokes; basalt rubble
	for _, chimney in features.chimneys do
		ventSmoke(vents, chimney)
	end
	ventFissures(vents, Random.new(World.seed + 41))
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
		-- A glowing cluster: one bright crystal shard and a few small ones round it
		-- (Neon balls until 2026-10-21: no sphere lumps in built scenery). Never
		-- dressed as a prop: the CrystalCluster mesh doesn't glow, and swapping it in
		-- hid every speck in the dark (playtest 2026-10-08). The draws are the old
		-- beads', so nothing after it on the shared Random moves.
		local color = if i % 4 == 0 then Color3.fromRGB(150, 120, 255) else Color3.fromRGB(110, 230, 255)
		local size = rng:NextNumber(0.8, 2.2)
		local speck = TrenchDress.speck(trenchGlow, position, size, color, i)
		for b = 1, rng:NextInteger(2, 4) do
			local scale = rng:NextNumber(0.25, 0.5)
			local offset = rng:NextUnitVector() * size * rng:NextNumber(1.2, 2.4)
			TrenchDress.speck(trenchGlow, position + offset, size * scale, color, i * 7 + b)
		end
		if i % 3 == 0 then
			local light = Instance.new("PointLight")
			light.Color = color
			light.Brightness = 0.9
			light.Range = 30
			light.Shadows = false
			light.Parent = speck
		end
	end

	-- Glow gardens on the canyon's floor (owner, 2026-10-09: "a few scattered light
	-- spots on the floor"): clumps of glowing tube anemones, each casting a real pool
	-- of light, so the Trench has places to see by between the dark stretches
	local gardenColors =
		{ Color3.fromRGB(90, 255, 214), Color3.fromRGB(110, 190, 255), Color3.fromRGB(170, 120, 255) }
	for i = 1, 42 do
		local trench = World.trench
		local r = rng:NextNumber(trench.radii[1] + 15, trench.radii[2] - 15)
		local _, width = Seafloor.trenchAxis(r)
		local _, _, halfBottom = Seafloor.trenchHalfWidths(width)
		local x, z = Seafloor.trenchPoint(r, rng:NextNumber(-1, 1) * math.max(halfBottom - 10, 4))
		local ground, normal = groundAt(x, z)
		-- Only down in the canyon (its floor or a ledge), on ground that's fairly flat
		if ground == nil or normal == nil or normal.Y < 0.5 or ground.Y > World.deep.floorY - 60 then
			continue
		end
		local color = gardenColors[i % #gardenColors + 1]
		local base: Part? = nil
		for _ = 1, rng:NextInteger(4, 7) do
			local height = rng:NextNumber(1.5, 5)
			local foot = ground + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
			local tilt = CFrame.Angles(rng:NextNumber(-0.25, 0.25), 0, rng:NextNumber(-0.25, 0.25))
			local stalk = Instance.new("Part")
			stalk.Name = "GlowStalk"
			stalk.Anchored = true
			stalk.CanCollide = false
			stalk.CanQuery = false
			stalk.CanTouch = false
			stalk.Shape = Enum.PartType.Cylinder
			stalk.Size = Vector3.new(height, 0.35, 0.35)
			stalk.CFrame = CFrame.new(foot)
				* tilt
				* CFrame.new(0, height / 2, 0)
				* CFrame.Angles(0, 0, math.rad(90))
			stalk.Color = color:Lerp(Color3.new(0, 0, 0), 0.45)
			stalk.Material = Enum.Material.Neon
			stalk.Transparency = 0.2
			stalk.Parent = trenchGlow
			local tip = Instance.new("Part")
			tip.Name = "GlowTip"
			tip.Anchored = true
			tip.CanCollide = false
			tip.CanQuery = false
			tip.CanTouch = false
			-- (a flat glowing cap, not a ball)
			tip.Shape = Enum.PartType.Cylinder
			local tipSize = rng:NextNumber(0.7, 1.2)
			tip.Size = Vector3.new(0.3, tipSize * 1.3, tipSize * 1.3)
			tip.CFrame = CFrame.new(foot)
				* tilt
				* CFrame.new(0, height, 0)
				* CFrame.Angles(0, 0, math.rad(90))
			tip.Color = color
			tip.Material = Enum.Material.Neon
			tip.Parent = trenchGlow
			base = base or tip
		end
		if base then
			local light = Instance.new("PointLight")
			light.Color = color
			light.Brightness = 1.3
			light.Range = 28
			light.Shadows = false
			light.Parent = base
		end
	end

	-- Glowing plankton mats on the deepest floors (owner, 2026-10-08: "deepest depths
	-- should have light luminescense such as photoplankton etc to give very very faint
	-- light"): a patch of tiny glowing dots just off the floor, every other one faintly
	-- lit. The plankton drifting in the water round the camera is PlanktonController's.
	local mats = folder("PlanktonMats", parent)
	local matColors =
		{ Color3.fromRGB(90, 255, 214), Color3.fromRGB(86, 168, 255), Color3.fromRGB(150, 120, 255) }
	local matCounts = {
		{ id = "AbyssalTrench", count = 46 },
		{ id = "HydrothermalVents", count = 18 },
		{ id = "OpenBlue", count = 16 },
		{ id = "SunkenRuins", count = 12 },
	}
	for _, entry in matCounts do
		for i = 1, entry.count do
			local ground = spotIn(rng, entry.id, 8)
			if ground == nil or ground.Y > World.deep.floorY + 20 then
				continue
			end
			local color = matColors[rng:NextInteger(1, #matColors)]
			local spread = rng:NextNumber(4, 9)
			local first: Part? = nil
			for _ = 1, rng:NextInteger(5, 10) do
				local dot = Instance.new("Part")
				dot.Name = "Plankton"
				dot.Anchored = true
				dot.CanCollide = false
				dot.CanQuery = false
				dot.CanTouch = false
				dot.Shape = Enum.PartType.Ball
				dot.Size = Vector3.one * rng:NextNumber(0.25, 0.7)
				local offset = Vector3.new(
					rng:NextNumber(-spread, spread),
					rng:NextNumber(0.2, 2.5),
					rng:NextNumber(-spread, spread)
				)
				dot.CFrame = CFrame.new(ground + offset)
				dot.Color = color
				dot.Material = Enum.Material.Neon
				dot.Transparency = 0.25
				dot.Parent = mats
				first = first or dot
			end
			-- In the Trench every patch is lit (owner, 2026-10-09: some light to see by);
			-- elsewhere every other one, faintly
			local trenchMat = entry.id == "AbyssalTrench"
			if first and (trenchMat or i % 2 == 0) then
				local light = Instance.new("PointLight")
				light.Color = color
				light.Brightness = if trenchMat then 0.7 else 0.35
				light.Range = if trenchMat then 20 else 16
				light.Shadows = false
				light.Parent = first
			end
		end
	end

	-- Seeps: thin bubble columns out of the sand on the shelf and the deep floor
	local seeps = folder("Seeps", parent)
	for _, biomeId in { "KelpShallows", "CoralReef", "ShipwreckGraveyard", "SunkenRuins", "OpenBlue" } do
		for _ = 1, if biomeId == "OpenBlue" then 5 else 8 do
			local ground = spotIn(rng, biomeId, 10)
			if ground then
				local seep = Instance.new("Part")
				seep.Name = "Seep"
				seep.Anchored = true
				seep.CanCollide = false
				seep.CanQuery = false
				seep.CanTouch = false
				seep.Transparency = 1
				seep.Size = Vector3.new(1.5, 0.5, 1.5)
				seep.CFrame = CFrame.new(ground + Vector3.new(0, 0.4, 0))
				seep.Parent = seeps
				bubbleColumn(seep, rng:NextNumber(0.6, 1))
			end
		end
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

	-- Sunken Ruins (owner, 2026-10-18: "Sunken ruins need an extreme update with the
	-- structures and detail"): a drowned city and smaller ruins round it, built from
	-- parts (Ruins.luau, Config/Ruins); last, so it clears the seeps and plankton the
	-- loops above scattered into its stones
	Ruins.build(ruins, groundAt)
	-- (its named places: the temple at the city's middle, the theatre beside the avenue)
	do
		local out =
			Vector3.new(math.cos(math.rad(Config.Ruins.angle)), 0, math.sin(math.rad(Config.Ruins.angle)))
		local side = out:Cross(Vector3.yAxis)
		local middle = out * Config.Ruins.radius + Vector3.new(0, World.deep.floorY + 30, 0)
		PlaceMarks.set("GreatTemple", middle)
		PlaceMarks.set("SunkenTheatre", middle - out * 140 + side * 172 - Vector3.new(0, 10, 0))
	end

	-- The Hydrothermal Vents' field (owner, 2026-10-19: "The vents part of the map
	-- needs more substance too"): the Forge, black smokers, basalt columns, mineral
	-- terraces, the brine pool, tube worms and mussels on the ground VentsPlan laid
	-- out (Vents.luau); after the scatter above, so it clears plankton out of its
	-- columns and the fissures under the brine pool
	local field = features.vents
	if field then
		Vents.build(vents, field, groundAt)
		if field.forge then
			PlaceMarks.set("TheForge", field.forge.center + Vector3.new(0, 60, 0))
		end
		if field.brine then
			PlaceMarks.set("BrinePool", field.brine.center + Vector3.new(0, 12, 0))
		end
	end

	-- The Abyssal Trench's landmarks (owner, 2026-10-21: the Leviathan's Spine board):
	-- the serpent's skeleton across the canyon, the Squid's Lair in the cave Shelf.luau
	-- bit into its wall, crystals, glow tubes, glass sponges and the glowing trail
	-- (TrenchDress.luau, its own Random); under Rocks, so Shared/Ground sees the bones
	do
		local trenchStats = TrenchDress.build(folder("Trench", rocks), groundAt, features.lair)
		print(
			`[Trench] the Leviathan's Spine: {trenchStats.parts} parts ({trenchStats.solid} solid, {trenchStats.glow} glowing), {trenchStats.models} models and {trenchStats.standins} stand-ins, {trenchStats.lights} lights`
		)
	end

	-- The Kelp Shallows', the Coral Reef's and the Open Blue's landmarks (owner,
	-- 2026-10-21: the biome detail boards), each builder on its own Random; then the
	-- scatter above is taken out of the ground its landmarks stand on
	do
		local scatter: { Instance } = { kelpFolder, rocks, corals }
		for _, name in { "Seeps", "PlanktonMats" } do
			local found = parent:FindFirstChild(name)
			if found then
				table.insert(scatter, found)
			end
		end
		local function landmarks(label: string, s: LandmarkKit.Stats)
			local cleared = LandmarkKit.clearAround(scatter, s.clearings)
			print(
				`[{label}] landmarks: {s.parts} parts ({s.solid} solid, {s.glow} glowing), {s.models} models and {s.standins} stand-ins, {s.lights} lights; {cleared} scattered pieces cleared`
			)
		end
		-- the Kelp Cathedral and Otter Meadow (KelpDress.luau)
		landmarks("Kelp", KelpDress.build(kelpFolder, folder("KelpLandmarks", rocks), groundAt))
	end

	-- The drop-off's reef wall (owner, 2026-10-19: "The cliff edge needs to be dialed
	-- up more and should have coral etc on it"): coral and life on the strata, ledges,
	-- lip and foot Shelf.luau laid (Cliff.luau), seated by rays against the Terrain
	-- alone (the rock, not the dressing above)
	local cliffLayout = features.cliff
	if cliffLayout then
		local terrainOnly = RaycastParams.new()
		terrainOnly.FilterType = Enum.RaycastFilterType.Include
		terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
		local clock = os.clock()
		local stats = Cliff.build(folder("Cliff", parent), cliffLayout, function(origin, direction)
			local hit = workspace:Raycast(origin, direction, terrainOnly)
			if hit then
				return hit.Position, hit.Normal, hit.Material
			end
			return nil, nil, nil
		end)
		local seconds = string.format("%.2f", os.clock() - clock)
		print(
			`[Cliff] the reef wall: {stats.parts} parts and {stats.models} models ({stats.solid} solid, {stats.glow} glowing), {stats.lights} lights, {seconds} s`
		)
	end
end

local denOwnerNames: { [number]: string? } = {}
local denLevelNames: { [number]: string? } = {}

local function refreshSign(index: number)
	DenDoor.setSign(index, denOwnerNames[index], denLevelNames[index])
end

-- Shows who owns a den on its sign (nil = free), and tells clients (the doorway
-- portal only lets fish into a den someone lives in)
function WorldService.setDenOwner(index: number, name: string?)
	denOwnerNames[index] = name
	refreshSign(index)
	local model = denModels[index]
	if model then
		model:SetAttribute("Owner", name)
	end
end

-- The den's level name on its sign (nil = plain)
function WorldService.setDenLevel(index: number, levelName: string?)
	denLevelNames[index] = levelName
	refreshSign(index)
end

-- The den's doorway style on the plaza (Config/Dens `doors`; nil = the Stone Arch).
-- DenDoor rebuilds it only when it changes; the `Door` attribute tells clients.
function WorldService.setDenDoor(index: number, styleId: string?)
	DenDoor.restyle(index, styleId)
	local model = denModels[index]
	if model then
		model:SetAttribute("Door", styleId or "Stone")
	end
end

-- The Treasure Wheel (Config/Wheel) on the plaza, facing the beacon, standing on
-- the cave floor's highest point under its stage (by raycast down from inside the
-- cavern; its footing reaches down past the rest)
local function buildWheel(parent: Instance)
	local Wheel = Config.Wheel
	local angle = math.rad(Wheel.angle)
	local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local center = hub.center + out * Wheel.radius
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local top = -math.huge
	for ring = 0, 2 do
		for k = 0, if ring == 0 then 0 else 7 do
			local theta = k / 8 * 2 * math.pi
			local spot = center + Vector3.new(math.cos(theta), 0, math.sin(theta)) * ring * 7
			local hit = workspace:Raycast(
				Vector3.new(spot.X, hub.center.Y + 60, spot.Z),
				Vector3.new(0, -120, 0),
				params
			)
			if hit then
				top = math.max(top, hit.Position.Y)
			end
		end
	end
	-- (it stands on the plaza's paving, which covers the cave floor round it)
	top = math.max(top, hub.center.Y + Plaza.WHEEL_GROUND)
	local hours = Wheel.freeEvery / 3600
	WorldService.wheel = TreasureWheel.build(
		parent,
		Vector3.new(center.X, top, center.Z),
		hub.center,
		Wheel.segments,
		{
			{ left = `Every {hours} hours`, right = "+1" },
			{ left = "Bounty Chest", right = `+{Wheel.bountyChest}` },
			{ left = "Catch of the Week", right = `+{Wheel.weekly}` },
			{ left = "Daily streak days 3 and 6", right = "+1" },
		},
		`Free spins come online or off, up to {Wheel.maxFree} waiting. Busy? Spin anyway to join the line.`
	)
end

-- The toon materials (Config/Materials) are made in Studio and saved in the place:
-- say so when one has its image but no variant (the material stays stock)
local function checkToonMaterials()
	local MaterialService = game:GetService("MaterialService")
	for key, toon in Config.Materials.toon do
		if toon.id ~= 0 and MaterialService:FindFirstChild("Toon" .. key) == nil then
			warn(
				`[WorldService] toon material Toon{key} isn't in the place: run tools/studio/make_toon_materials.luau in Studio's Command Bar and save`
			)
		end
	end
end

function WorldService.start()
	setupLighting()
	checkToonMaterials()
	root = folder("World", workspace)
	buildSeabed()
	buildBounds(folder("Bounds", root))
	buildHub(root)
	buildVendors(root:FindFirstChild("Hub") :: Folder)
	awaitTerrain()
	local hubFolder = root:FindFirstChild("Hub") :: Folder
	for _, segment in tunnelSegments do
		exitDressing(hubFolder, segment)
	end
	buildWheel(hubFolder)
	buildBiomes(folder("Biomes", root))
	-- How many parts make the hub (the plaza, doorways, stalls, the wheel; not the
	-- dens' far interiors), for the den's way-out loading screen to wait for
	-- (DenDoorController `hubLoaded`; owner, 2026-10-20: "the loading screen back to
	-- the hub from the den ends before the hub finishes loading"). Counted again now
	-- and then: doorways light and change style as players come and go.
	task.spawn(function()
		while true do
			hubFolder:SetAttribute("PlazaParts", Layout.hubParts(hubFolder))
			task.wait(15)
		end
	end)
end

return WorldService
