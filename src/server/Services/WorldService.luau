--!strict
-- Builds the map at server start: the seabed with a trench, the surface ceiling,
-- the map's walls, the hub cavern (Terrain carved by Cave.luau, plus 12 dens' pools
-- and signs, sconces, the plaza and beacon) and the Kelp Shallows' dressing (kelp,
-- rocks, arches, a coral patch, light shafts). The dressing is placeholder geometry
-- until the Tripo props land; layout numbers live in Config/World.luau and
-- Shared/Layout.luau.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Cave = require(script.Parent.Parent.Cave)
local Props = require(script.Parent.Parent.Props)

local World = Config.World
local hub = World.hub

local WorldService = {}

local root: Folder
local denSigns: { [number]: TextLabel } = {}
local vendorPositions: { [string]: Vector3 } = {}

local SAND = Color3.fromRGB(196, 182, 140)
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
		keeper(stall, at(36.2, plazaTop + 4.2), vendor.color:Lerp(Color3.new(1, 1, 1), 0.25))
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
			local plant = Instance.new("Model")
			plant.Name = "Kelp"
			plant.Parent = kelp
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
			-- The imported kelp (a single stalk model) replaces the blocks
			local upright = CFrame.new(x, World.seabedY + height / 2, z)
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

	-- Rocks, and arches with gaps too tight for big fish
	local rocks = folder("Rocks", shallows)
	for _ = 1, 110 do
		local x, z = spot(20)
		local size = Vector3.new(rng:NextNumber(6, 30), rng:NextNumber(5, 22), rng:NextNumber(6, 30))
		local yaw = rng:NextNumber(0, 6.28)
		local rock = block(
			rocks,
			"Rock",
			size,
			CFrame.new(x, World.seabedY + size.Y * 0.25, z)
				* CFrame.Angles(rng:NextNumber(-0.4, 0.4), yaw, rng:NextNumber(-0.4, 0.4)),
			ROCK
		)
		rock.Material = Enum.Material.Rock
		Props.dress(rock, if rng:NextNumber() < 0.6 then "BoulderRound" else "BoulderJagged", {
			cframe = CFrame.new(x, World.seabedY + size.Y * 0.42, z) * CFrame.Angles(0, yaw, 0),
			size = Vector3.new(size.X * 1.1, size.Y * 0.95, size.Z * 1.1),
		})
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
		local kinds = { "BrainCoral", "FanCoral", "StaghornCoral", "TubeSponge", "Anemone" }
		Props.dress(piece, kinds[rng:NextInteger(1, #kinds)], {
			cframe = CFrame.new(x, World.seabedY + size * 0.75, z)
				* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			size = Vector3.new(size * 1.7, size * 1.5, size * 1.7),
		})
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
