--!strict
-- A den's front door on the plaza, and its way out inside the den (owner,
-- 2026-10-17: "The names of the dens look rough", "Needs to be more of an entrance
-- to their den not just a hole with light coming out of it"). Each doorway in the
-- cavern wall (Cave.denDoor: a round alcove with a flat sill) gets:
--   - a chunky arch of rounded stones (the rounded-rock rule, in parts so it stays
--     crisp), standing on stacked jamb stones, clear of the opening;
--   - a nameplate on the arch's crown: a lacquered plaque in a brass frame, the
--     owner's name on one line and the den's level (NOOK ... SANCTUM) under it,
--     each line scaled to fit, so a 20-character name is never cut off;
--   - a lantern on each jamb, a stone threshold with two steps down to the plaza,
--     and a little coral and kelp growing on the stones;
--   - the portal at the alcove's back as a bubble curtain: a dark pane in a
--     stepped brass collar, a faint ForceField shimmer over it and bubbles rising
--     across it, instead of a glowing disc.
-- An empty den reads shut: a slate plaque saying EMPTY DEN, unlit lanterns and a
-- dim, still curtain (its portal lets no one in, DenDoorController).
--
-- Everything is a plain anchored part in a material the toon overrides don't touch
-- (Config/Materials re-skins Rock, Slate, Wood, Marble, ... game-wide, which turned
-- small part-built pieces into one big blurry tile). Decor never takes camera rays
-- (CanQuery false); the stones are solid, the rest isn't. Nothing reaches inside the
-- alcove's radius (10.5) or the sill's width, so a LV 100 fish (collider ~6.8)
-- swims in as before, and the portal's trigger (Layout.doorAt) is unchanged.
-- tools/preview/run_hub.sh renders it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)

local World = Config.World
local hub = World.hub

local DenDoor = {}

-- Colours: warm sea-sandstone stones, teal lacquer and brass (the Treasure Wheel's
-- palette), cream lettering
local STONES = {
	Color3.fromRGB(214, 186, 140),
	Color3.fromRGB(196, 166, 122),
	Color3.fromRGB(226, 200, 156),
	Color3.fromRGB(184, 154, 112),
}
local JAMB_STONES = {
	Color3.fromRGB(176, 148, 108),
	Color3.fromRGB(194, 164, 120),
	Color3.fromRGB(206, 178, 134),
}
local STEP = Color3.fromRGB(168, 150, 120)
local STEP_EDGE = Color3.fromRGB(196, 178, 146)
local BRASS = Color3.fromRGB(214, 160, 70)
local BRASS_LIGHT = Color3.fromRGB(246, 204, 118)
local BRASS_DARK = Color3.fromRGB(150, 104, 44)
local IRON = Color3.fromRGB(46, 52, 60)
local LACQUER = Color3.fromRGB(20, 88, 102)
local LACQUER_EMPTY = Color3.fromRGB(52, 62, 70)
local TRIM_EMPTY = Color3.fromRGB(112, 120, 126)
local TEXT = Color3.fromRGB(255, 244, 222)
local TEXT_LEVEL = Color3.fromRGB(255, 208, 104)
local TEXT_EMPTY = Color3.fromRGB(150, 168, 176)
local TEXT_STROKE = Color3.fromRGB(8, 34, 42)
local GLASS_LIT = Color3.fromRGB(255, 202, 122)
local GLASS_DARK = Color3.fromRGB(78, 74, 66)
local LANTERN_LIGHT = Color3.fromRGB(255, 186, 112)
local CURTAIN = Color3.fromRGB(150, 236, 246)
local CURTAIN_SHUT = Color3.fromRGB(70, 104, 114)
local PANE = Color3.fromRGB(12, 44, 58)
local PANE_SHUT = Color3.fromRGB(20, 30, 36)
local GLOW = Color3.fromRGB(130, 222, 232)
local KELP = { Color3.fromRGB(64, 150, 74), Color3.fromRGB(96, 178, 70), Color3.fromRGB(46, 128, 84) }
local CORALS = {
	Color3.fromRGB(255, 118, 132),
	Color3.fromRGB(255, 160, 80),
	Color3.fromRGB(176, 110, 236),
	Color3.fromRGB(255, 214, 92),
	Color3.fromRGB(96, 214, 196),
}

-- The doorway's shape (Cave.denDoor), in the door's frame (Layout.doorFrame: the
-- portal's middle, -Z toward the hub)
local WALL_Z = -9 -- the cavern wall's face (hub.radius)
local OPENING = 10.5 -- the alcove's radius
local ARCH_IN = 11 -- the arch stones' inner edge (just outside the opening)
local ARCH_OUT = 14.4
local PLAQUE = Vector2.new(16.6, 5.4)

type Lantern = { glass: BasePart, light: PointLight }
type Door = {
	model: Model,
	name: TextLabel,
	level: TextLabel,
	board: BasePart,
	trims: { BasePart },
	lanterns: { Lantern },
	curtain: BasePart,
	pane: BasePart,
	bubbles: ParticleEmitter,
	shimmer: ParticleEmitter,
	glow: PointLight,
}

local doors: { [number]: Door } = {}

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CanTouch = false
	p.CanQuery = false
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

-- A rounded stone: an ellipsoid filling `size` (a sphere mesh on a block)
local function pebble(parent: Instance, name: string, cframe: CFrame, size: Vector3, color: Color3): Part
	local p = part(parent, {
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = color,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- A disc facing along the frame's look (a cylinder's axis is its X)
local function disc(parent: Instance, name: string, cframe: CFrame, radius: number, thickness: number): Part
	return part(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, radius * 2, radius * 2),
		CFrame = cframe * CFrame.Angles(0, math.rad(90), 0),
		CanCollide = false,
		CastShadow = false,
	})
end

-- An upright cylinder standing on `base` (its axis up)
local function upright(parent: Instance, name: string, base: CFrame, height: number, radius: number): Part
	return part(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		CanCollide = false,
	})
end

-- The arch over an opening of radius `inner` (centre at `frame`, wall at local z
-- `wall`, springing at y 0) and its jambs down to `floor`: rounded stones, eight
-- round the top (the crown under the nameplate) and three a side
local function arch(parent: Instance, frame: CFrame, inner: number, outer: number, wall: number, floor: number, seed: number)
	local rng = Random.new(seed)
	local thick = outer - inner
	local depth = 3.6
	local z = wall - depth / 2 + 0.4 -- sunk a little into the rock
	local mid = (inner + outer) / 2
	local count = 9
	for i = 0, count - 1 do
		-- 0 = the right springing (local +X), up over the top to the left
		local theta = math.rad(4 + (172 / (count - 1)) * i)
		local length = mid * math.rad(172 / (count - 1)) * 1.18
		local spot = frame
			* CFrame.new(math.cos(theta) * mid, math.sin(theta) * mid, z)
			* CFrame.Angles(0, 0, theta - math.pi / 2)
		pebble(
			parent,
			"ArchStone",
			spot,
			Vector3.new(length * rng:NextNumber(0.96, 1.08), thick * rng:NextNumber(0.95, 1.08), depth),
			STONES[(i % #STONES) + 1]
		).CanCollide =
			true
	end
	-- The jambs: three stones a side from the floor to the springing, a bigger one
	-- at the foot
	local jambX = inner - 1.2 + thick / 2
	for side = -1, 1, 2 do
		local heights = { 4.4, 3.9, 3.6 }
		local total = 0
		for _, h in heights do
			total += h
		end
		local scale = (0 - floor + 1.2) / total
		local y = floor
		for k, h in heights do
			local height = h * scale
			local width = thick * (if k == 1 then 1.18 else 1.02) * rng:NextNumber(0.96, 1.05)
			pebble(
				parent,
				"JambStone",
				frame * CFrame.new(side * (jambX + (if k == 1 then 0.25 else 0)), y + height / 2, z),
				Vector3.new(width, height * 1.08, depth * (if k == 1 then 1.1 else 1)),
				JAMB_STONES[((k + (if side > 0 then 0 else 1)) % #JAMB_STONES) + 1]
			).CanCollide =
				true
			y += height * 0.94
		end
	end
	return jambX, z
end

-- The nameplate: a lacquered board in a brass frame with corner bosses, its two
-- lines of text on a SurfaceGui (unlit, so it reads from across the plaza)
local function plaque(parent: Instance, at: CFrame, size: Vector2): (TextLabel, TextLabel, BasePart, { BasePart })
	local board = part(parent, {
		Name = "Plaque",
		Size = Vector3.new(size.X, size.Y, 0.8),
		CFrame = at,
		Color = LACQUER,
		CanCollide = false,
	})
	local trims: { BasePart } = {}
	local bar = 0.55
	for _, y in { -1, 1 } do
		table.insert(
			trims,
			part(parent, {
				Name = "PlaqueTrim",
				Size = Vector3.new(size.X + bar, bar, 0.5),
				CFrame = at * CFrame.new(0, y * (size.Y / 2), -0.3),
				Color = BRASS,
				CanCollide = false,
			})
		)
	end
	for _, x in { -1, 1 } do
		table.insert(
			trims,
			part(parent, {
				Name = "PlaqueTrim",
				Size = Vector3.new(bar, size.Y + bar, 0.5),
				CFrame = at * CFrame.new(x * (size.X / 2), 0, -0.3),
				Color = BRASS,
				CanCollide = false,
			})
		)
	end
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			table.insert(
				trims,
				part(parent, {
					Name = "PlaqueBoss",
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * 0.95,
					CFrame = at * CFrame.new(x * (size.X / 2), y * (size.Y / 2), -0.45),
					Color = BRASS_LIGHT,
					CanCollide = false,
					CastShadow = false,
				})
			)
		end
	end
	-- The text sits on a thin face just in front of the board, inside the frame
	local face = part(parent, {
		Name = "PlaqueFace",
		Size = Vector3.new(size.X - 0.9, size.Y - 0.9, 0.05),
		CFrame = at * CFrame.new(0, 0, -0.45),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Brightness = 1.15
	gui.Parent = face
	local name = Instance.new("TextLabel")
	name.Name = "Owner"
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromScale(0.035, 0.05)
	name.Size = UDim2.fromScale(0.93, 0.56)
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextWrapped = false
	name.TextColor3 = TEXT
	name.Text = ""
	name.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = TEXT_STROKE
	stroke.Thickness = 4
	stroke.Parent = name
	-- The level line: the name between two short brass rules
	for _, x in { 0.07, 0.71 } do
		local rule = Instance.new("Frame")
		rule.Name = "Rule"
		rule.BorderSizePixel = 0
		rule.BackgroundColor3 = BRASS_LIGHT
		rule.AnchorPoint = Vector2.new(0, 0.5)
		rule.Position = UDim2.fromScale(x, 0.8)
		rule.Size = UDim2.new(0.22, 0, 0, 5)
		rule.Parent = gui
	end
	local level = Instance.new("TextLabel")
	level.Name = "Level"
	level.BackgroundTransparency = 1
	level.Position = UDim2.fromScale(0.3, 0.65)
	level.Size = UDim2.fromScale(0.4, 0.3)
	level.Font = Enum.Font.GothamBlack
	level.TextScaled = true
	level.TextWrapped = false
	level.TextColor3 = TEXT_LEVEL
	level.Text = ""
	level.Parent = gui
	local levelStroke = Instance.new("UIStroke")
	levelStroke.Color = TEXT_STROKE
	levelStroke.Thickness = 2.5
	levelStroke.Parent = level
	return name, level, board, trims
end

-- A brass lantern hanging from an iron arm; `at` is the glass's middle, and the arm
-- reaches 2 studs from over it toward `armToward` (a local X sign: the jamb)
local function lantern(parent: Instance, at: CFrame, armToward: number, lit: boolean): Lantern
	part(parent, {
		Name = "LanternArm",
		Size = Vector3.new(2.1, 0.32, 0.32),
		CFrame = at * CFrame.new(armToward * 1.05, 1.75, 0),
		Color = IRON,
		CanCollide = false,
		CastShadow = false,
	})
	part(parent, {
		Name = "LanternHook",
		Size = Vector3.new(0.22, 0.6, 0.22),
		CFrame = at * CFrame.new(0, 1.5, 0),
		Color = IRON,
		CanCollide = false,
		CastShadow = false,
	})
	part(parent, {
		Name = "LanternCap",
		Size = Vector3.new(1.75, 0.45, 1.75),
		CFrame = at * CFrame.new(0, 1.05, 0),
		Color = BRASS,
		CanCollide = false,
	})
	local roof = part(parent, {
		Name = "LanternRoof",
		Size = Vector3.new(1.35, 0.7, 1.35),
		CFrame = at * CFrame.new(0, 1.45, 0),
		Color = BRASS_DARK,
		CanCollide = false,
	})
	local dome = Instance.new("SpecialMesh")
	dome.MeshType = Enum.MeshType.Sphere
	dome.Parent = roof
	local glass = part(parent, {
		Name = "LanternGlass",
		Size = Vector3.new(1.2, 1.6, 1.2),
		CFrame = at,
		Color = if lit then GLASS_LIT else GLASS_DARK,
		Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		Transparency = if lit then 0.08 else 0,
		CanCollide = false,
		CastShadow = false,
	})
	part(parent, {
		Name = "LanternBase",
		Size = Vector3.new(1.55, 0.4, 1.55),
		CFrame = at * CFrame.new(0, -0.98, 0),
		Color = BRASS,
		CanCollide = false,
	})
	local light = Instance.new("PointLight")
	light.Color = LANTERN_LIGHT
	light.Range = 16
	light.Brightness = 0.85
	light.Enabled = lit
	light.Parent = glass
	return { glass = glass, light = light }
end

-- Coral and kelp on the foot of a jamb (`side` is the local X sign, `x` its outer
-- edge), varied by `rng`
local function growth(parent: Instance, frame: CFrame, side: number, x: number, floor: number, z: number, rng: Random)
	local coral = CORALS[rng:NextInteger(1, #CORALS)]
	pebble(
		parent,
		"BrainCoral",
		frame * CFrame.new(side * (x + 0.6), floor + 1.0, z - 0.6) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
		Vector3.new(2.6, 2.0, 2.4),
		coral
	)
	-- Tube sponges: two or three upright tubes, a darker rim on top
	local tubeColor = CORALS[rng:NextInteger(1, #CORALS)]
	for k = 1, rng:NextInteger(2, 3) do
		local h = rng:NextNumber(1.8, 3.4)
		local r = rng:NextNumber(0.38, 0.55)
		local base = frame
			* CFrame.new(side * (x + 1.6 + k * 0.55), floor, z - 2.0 + k * 0.7)
			* CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, side * rng:NextNumber(0.05, 0.25))
		upright(parent, "TubeSponge", base, h, r).Color = tubeColor
	end
	-- Kelp: three blades climbing beside the jamb
	local kelp = KELP[rng:NextInteger(1, #KELP)]
	local y = floor
	for k = 1, 3 do
		local length = rng:NextNumber(3.2, 4.4)
		local lean = side * rng:NextNumber(0.08, 0.22) * (if k % 2 == 0 then -1 else 1)
		local blade = part(parent, {
			Name = "KelpBlade",
			Size = Vector3.new(0.9, length, 0.22),
			CFrame = frame * CFrame.new(side * (x + 3.1), y + length / 2, z + 0.5) * CFrame.Angles(0, 0, lean),
			Color = if k == 3 then kelp:Lerp(Color3.fromRGB(200, 230, 90), 0.45) else kelp,
			CanCollide = false,
			CastShadow = false,
		})
		blade.Name = "KelpBlade"
		y += length * 0.86
	end
end

-- The portal pane: a dark pane in a stepped brass collar with rivets, a faint
-- ForceField shimmer over it, bubbles rising across it and a soft light in front
local function pane(parent: Instance, frame: CFrame, radius: number): (BasePart, BasePart, ParticleEmitter, ParticleEmitter, PointLight)
	local collar = disc(parent, "PortalCollar", frame * CFrame.new(0, 0, 0.35), radius + 1.35, 0.4)
	collar.Color = BRASS_DARK
	local ring = disc(parent, "PortalRing", frame * CFrame.new(0, 0, 0.25), radius + 0.75, 0.4)
	ring.Color = BRASS
	local backing = disc(parent, "PortalPane", frame * CFrame.new(0, 0, 0.1), radius, 0.6)
	backing.Color = PANE
	for i = 0, 7 do
		local theta = i / 8 * 2 * math.pi + math.pi / 8
		part(parent, {
			Name = "Rivet",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.55,
			CFrame = frame * CFrame.new(math.cos(theta) * (radius + 1.05), math.sin(theta) * (radius + 1.05), 0.05),
			Color = BRASS_LIGHT,
			CanCollide = false,
			CastShadow = false,
		})
	end
	local curtain = disc(parent, "Portal", frame * CFrame.new(0, 0, -0.35), radius, 0.2)
	curtain.Color = CURTAIN
	curtain.Material = Enum.Material.ForceField
	curtain.Transparency = 0.2
	-- Bubbles rise across the whole opening (any spawned outside the circle are in
	-- the rock behind it)
	local sheet = part(parent, {
		Name = "PortalBubbles",
		Size = Vector3.new(radius * 2, radius * 2, 0.4),
		CFrame = frame * CFrame.new(0, 0, -0.75),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "Bubbles"
	bubbles.Rate = 26
	bubbles.Lifetime = NumberRange.new(2.2, 3.4)
	bubbles.Speed = NumberRange.new(1.5, 3)
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.SpreadAngle = Vector2.new(8, 8)
	bubbles.Acceleration = Vector3.new(0, 1.5, 0)
	bubbles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.3, 0.42),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	bubbles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.12, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	bubbles.LightEmission = 0.45
	bubbles.Color = ColorSequence.new(Color3.fromRGB(214, 250, 255))
	bubbles.Parent = sheet
	local shimmer = Instance.new("ParticleEmitter")
	shimmer.Name = "Shimmer"
	shimmer.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	shimmer.Rate = 5
	shimmer.Lifetime = NumberRange.new(1, 1.6)
	shimmer.Speed = NumberRange.new(0.2, 0.6)
	shimmer.SpreadAngle = Vector2.new(180, 180)
	shimmer.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	shimmer.Transparency = NumberSequence.new(0.35, 1)
	shimmer.LightEmission = 1
	shimmer.Color = ColorSequence.new(Color3.fromRGB(196, 250, 255))
	shimmer.Parent = sheet
	local lamp = part(parent, {
		Name = "PortalGlow",
		Size = Vector3.one,
		CFrame = frame * CFrame.new(0, 0, -4),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	local glow = Instance.new("PointLight")
	glow.Color = GLOW
	glow.Range = 16
	glow.Brightness = 0.7
	glow.Parent = lamp
	return curtain, backing, bubbles, shimmer, glow
end

-- Which local X side of den `index`'s doorway opens onto a tunnel's mouth (the
-- doors either side of a tunnel nearly touch it), or 0
local function tunnelSide(index: number): number
	local frame = Layout.doorFrame(index)
	for _, delta in { -1, 1 } do
		local angle = math.atan2(frame.Position.Z - hub.center.Z, frame.Position.X - hub.center.X)
			+ delta * 2 * math.pi / hub.segments
		local segment = math.floor(((angle % (2 * math.pi)) / (2 * math.pi)) * hub.segments + 0.5) % hub.segments
			+ 1
		if Layout.segmentKind(segment) == "tunnel" then
			local probe = hub.center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * hub.radius
			local x = frame:PointToObjectSpace(Vector3.new(probe.X, frame.Position.Y, probe.Z)).X
			return if x > 0 then 1 else -1
		end
	end
	return 0
end

-- Den `index`'s front door on the plaza, into `parent` (its Den<i> model)
function DenDoor.front(parent: Instance, index: number)
	local frame = Layout.doorFrame(index)
	local folder = Instance.new("Model")
	folder.Name = "Doorway"
	local rng = Random.new(World.seed + index * 31)
	local floor = hub.denFloorY - frame.Position.Y -- the doorway's floor (the den floor's height)
	local jambX, stoneZ = arch(folder, frame, ARCH_IN, ARCH_OUT, WALL_Z, floor, World.seed + index)
	local name, level, board, trims =
		plaque(folder, frame * CFrame.new(0, ARCH_IN + PLAQUE.Y / 2 - 0.2, WALL_Z - 3.6), PLAQUE)

	-- Lanterns on the jambs' outer faces
	local lanterns: { Lantern } = {}
	for side = -1, 1, 2 do
		local x = side * (jambX + (ARCH_OUT - ARCH_IN) / 2 + 1.2)
		table.insert(lanterns, lantern(folder, frame * CFrame.new(x, -2.2, stoneZ - 0.4), -side, false))
	end

	-- The threshold: a slab over the sill's front (Cave.denFloor: its ledge reaches
	-- 7 in front of the wall), a rounded nose, two steps down to the plaza's paving
	local sill = floor
	local ledge = WALL_Z - 7.4
	part(folder, {
		Name = "Threshold",
		Size = Vector3.new(19.6, 1.2, WALL_Z + 0.4 - ledge),
		CFrame = frame * CFrame.new(0, sill - 0.2, (WALL_Z + 0.4 + ledge) / 2),
		Color = STEP,
		CanCollide = true,
	})
	part(folder, {
		Name = "ThresholdNose",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(19.6, 1.2, 1.2),
		CFrame = frame * CFrame.new(0, sill - 0.2, ledge),
		Color = STEP_EDGE,
		CanCollide = false,
	})
	local paving = hub.paving - frame.Position.Y
	local rise = (sill + 0.4 - paving) / 3
	for k = 1, 2 do
		local top = sill + 0.4 - rise * k
		local bottom = paving - 0.6
		local back = ledge - 0.6 - (k - 1) * 1.8
		part(folder, {
			Name = "Step",
			Size = Vector3.new(20.4 + k * 1.2, top - bottom, 1.8 + (if k == 1 then 0.6 else 0)),
			CFrame = frame * CFrame.new(0, (top + bottom) / 2, back - 0.9 + (if k == 1 then 0.3 else 0)),
			Color = if k == 1 then STEP_EDGE else STEP,
			CanCollide = true,
		})
	end

	-- Coral and kelp at the jambs' feet, on the side(s) away from a tunnel's mouth
	local open = tunnelSide(index)
	for side = -1, 1, 2 do
		if side ~= open then
			growth(folder, frame, side, jambX + (ARCH_OUT - ARCH_IN) / 2, floor, stoneZ, rng)
		end
	end

	local curtain, backing, bubbles, shimmer, glow = pane(folder, frame, Layout.DOOR_RADIUS)
	folder.Parent = parent
	doors[index] = {
		model = folder,
		name = name,
		level = level,
		board = board,
		trims = trims,
		lanterns = lanterns,
		curtain = curtain,
		pane = backing,
		bubbles = bubbles,
		shimmer = shimmer,
		glow = glow,
	}
	DenDoor.setSign(index, nil, nil)
end

-- The way out inside den `index` (on its front wall, Layout.exitFrame): the same
-- arch, curtain and lanterns as the front door, and a TO THE HUB plaque
function DenDoor.exit(parent: Instance, index: number)
	local frame = Layout.exitFrame(index)
	local radius = Config.Dens.exit.radius
	local folder = Instance.new("Model")
	folder.Name = "Exit"
	local floor = -Config.Dens.exit.y -- the deck, in the portal's frame
	-- The front wall is 0.6 behind the portal (Layout.exitFrame); its frame looks
	-- into the den, so the wall is at local +Z
	local inner = radius + 0.4
	local outer = radius + 3.6
	local wall = 0.6
	-- arch() measures toward local -Z from the wall; this frame already faces the room
	local jambX, stoneZ = arch(folder, frame, inner, outer, wall, floor, World.seed + 700 + index)
	local name, level = plaque(folder, frame * CFrame.new(0, inner + 2.5, wall - 3.6), Vector2.new(14, 4.6))
	name.Text = "TO THE HUB"
	level.Text = "THE PLAZA"
	for side = -1, 1, 2 do
		local x = side * (jambX + (outer - inner) / 2 + 1.2)
		lantern(folder, frame * CFrame.new(x, -2.2, stoneZ - 0.4), -side, true)
	end
	local rng = Random.new(World.seed + 900 + index)
	for side = -1, 1, 2 do
		growth(folder, frame, side, jambX + (outer - inner) / 2, floor, stoneZ, rng)
	end
	pane(folder, frame * CFrame.new(0, 0, 0.3), radius)
	folder.Parent = parent
end

-- Who lives in den `index` (nil: nobody) and its level's name (Config/Dens
-- levels), on its nameplate; an empty den's door reads shut
function DenDoor.setSign(index: number, owner: string?, levelName: string?)
	local door = doors[index]
	if door == nil then
		return
	end
	local lived = owner ~= nil
	if owner then
		-- One line, never wrapped: spaces in a display name become non-breaking
		local shown = string.gsub(string.upper(owner), " ", "\u{00A0}")
		door.name.Text = `{shown}'S`
		door.level.Text = string.upper(levelName or "Den")
	else
		door.name.Text = "EMPTY DEN"
		door.level.Text = "VACANT"
	end
	door.name.TextColor3 = if lived then TEXT else TEXT_EMPTY
	door.level.TextColor3 = if lived then TEXT_LEVEL else TEXT_EMPTY
	door.board.Color = if lived then LACQUER else LACQUER_EMPTY
	for _, trim in door.trims do
		trim.Color = if lived then (if trim.Name == "PlaqueBoss" then BRASS_LIGHT else BRASS) else TRIM_EMPTY
	end
	for _, light in door.lanterns do
		light.glass.Material = if lived then Enum.Material.Neon else Enum.Material.SmoothPlastic
		light.glass.Color = if lived then GLASS_LIT else GLASS_DARK
		light.glass.Transparency = if lived then 0.08 else 0
		light.light.Enabled = lived
	end
	door.curtain.Color = if lived then CURTAIN else CURTAIN_SHUT
	door.curtain.Transparency = if lived then 0.2 else 0.5
	door.pane.Color = if lived then PANE else PANE_SHUT
	door.bubbles.Rate = if lived then 26 else 4
	door.shimmer.Enabled = lived
	door.glow.Enabled = lived
end

return DenDoor
