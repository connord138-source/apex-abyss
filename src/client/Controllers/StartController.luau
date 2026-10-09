--!strict
-- The start screen (owner, 2026-10-09: "a start screen when players load into the
-- server. Just hit any button to start and then it pushes them straight to the den
-- and tutorial. Starter screen should have motion and some fish swimming by with
-- maybe some kelp").
--
-- It covers the game while it loads: a lit underwater scene in two ViewportFrames
-- (the far water hazed by depth, with a school and a shark's shadow; the near water
-- with swaying kelp and the playable fish swimming past), light shafts, marine snow
-- and rising bubbles, the APEX ABYSS title and three lines on how to play. Once the
-- fish has spawned in its den the prompt shows, and any key, click, tap or
-- controller button dives in: the scene rushes past and clears onto the fish in its
-- den, where the tutorial (or the Daily panel, or WELCOME BACK) picks up.
--
-- Other controllers hold their join-time UI until then with `afterStart`.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local FishBuilder = require(ReplicatedStorage.Shared.FishBuilder)
local Signal = require(ReplicatedStorage.Shared.Signal)
local SwimWave = require(ReplicatedStorage.Shared.SwimWave)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)

local StartController = {
	-- () — the player pressed start and the game is in front of them
	started = Signal.new(),
}

local MIN_SHOW = 2.4 -- seconds on screen before the prompt, so it never just flashes
local MAX_WAIT = 25 -- the prompt shows by then even if the fish hasn't spawned yet
local GRACE = 0.45 -- input is ignored this long after the prompt appears
local FOV = 50

local up = false
local done = false
local waiting: { () -> () } = {}

-- Whether the start screen is covering the game
function StartController.isUp(): boolean
	return up
end

-- Runs `fn` once the player has started (straight away if they already have)
function StartController.afterStart(fn: () -> ())
	if done then
		task.spawn(fn)
	else
		table.insert(waiting, fn)
	end
end

-- Scene ---------------------------------------------------------------------------

type Swimmer = {
	model: Model?, -- an imported model (rigged, or a bare mesh inside one)
	mesh: BasePart?, -- a bare static mesh
	body: BasePart?, -- or a simple ellipsoid body with a tail
	tail: BasePart?,
	offset: CFrame, -- centres the model on its swim point
	bones: { [string]: Bone },
	spine: { string },
	flip: boolean,
	length: number,
	speed: number,
	direction: number, -- +1 swims right, -1 left
	x: number,
	y: number,
	z: number,
	bob: number,
	phase: number,
	wave: number, -- tail beats per second
}

type Kelp = {
	segments: { BasePart },
	blades: { { part: BasePart, segment: number, side: number } },
	base: CFrame,
	phase: number,
	length: number,
}

local swimmers: { Swimmer } = {}
local kelps: { Kelp } = {}

local function prepare(model: Instance)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		end
	end
end

local function bonesOf(model: Instance): ({ [string]: Bone }, { string })
	local bones: { [string]: Bone } = {}
	local spine: { string } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Bone") then
			bones[descendant.Name] = descendant
		end
	end
	local i = 1
	while bones[`Spine{i}`] do
		table.insert(spine, `Spine{i}`)
		i += 1
	end
	if bones.Tail then
		table.insert(spine, "Tail")
	end
	return bones, spine
end

local function ellipsoid(parent: Instance, color: Color3, size: Vector3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	part.Size = size
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.Parent = parent
	return part
end

-- A fish `length` long from an imported model, or a simple body in `color` while
-- the model isn't imported
local function fish(
	world: WorldModel,
	template: Instance?,
	length: number,
	color: Color3,
	motion: {
		speed: number,
		direction: number,
		x: number,
		y: number,
		z: number,
		bob: number,
		wave: number,
	}
): Swimmer
	local swimmer: Swimmer = {
		offset = CFrame.identity,
		bones = {},
		spine = {},
		flip = false,
		length = length,
		speed = motion.speed,
		direction = motion.direction,
		x = motion.x,
		y = motion.y,
		z = motion.z,
		bob = motion.bob,
		phase = math.random() * 10,
		wave = motion.wave,
	}
	if template and template:IsA("Model") and template:FindFirstChildWhichIsA("BasePart", true) then
		local clone = template:Clone()
		prepare(clone)
		clone:ScaleTo(1)
		-- The fish's frame is its main mesh's (like the prey and predators): its -Z
		-- is the head on a rigged body, and its Z is the length
		local mesh: MeshPart? = nil
		for _, descendant in clone:GetDescendants() do
			if
				descendant:IsA("MeshPart")
				and (mesh == nil or descendant.Size.Magnitude > (mesh :: MeshPart).Size.Magnitude)
			then
				mesh = descendant
			end
		end
		local long = if mesh then mesh.Size.Z else clone:GetExtentsSize().Z
		clone:ScaleTo(length / math.max(long, 0.01))
		if mesh then
			swimmer.offset = clone:GetPivot():ToObjectSpace(mesh.CFrame):Inverse()
		end
		swimmer.bones, swimmer.spine = bonesOf(clone)
		-- A rigged model faces -Z; a lone static mesh may face +Z (SwimWave.needsFlip)
		swimmer.flip = #swimmer.spine == 0 and mesh ~= nil and SwimWave.needsFlip(mesh :: MeshPart)
		clone.Parent = world
		swimmer.model = clone
	elseif template and template:IsA("MeshPart") then
		local mesh = template:Clone()
		prepare(mesh)
		mesh.Size = template.Size * (length / math.max(template.Size.Z, 0.01))
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CastShadow = false
		mesh.Parent = world
		swimmer.mesh = mesh
		swimmer.flip = SwimWave.needsFlip(template)
	else
		swimmer.body = ellipsoid(world, color, Vector3.new(length * 0.3, length * 0.36, length * 0.8))
		swimmer.tail = ellipsoid(
			world,
			color:Lerp(Color3.new(1, 1, 1), 0.15),
			Vector3.new(length * 0.04, length * 0.4, length * 0.28)
		)
	end
	table.insert(swimmers, swimmer)
	return swimmer
end

-- How far either side of the middle a fish at depth `z` leaves the screen
local function halfWidth(z: number, aspect: number): number
	return -z * math.tan(math.rad(FOV / 2)) * aspect
end

local function moveSwimmer(swimmer: Swimmer, t: number, dt: number, aspect: number)
	swimmer.x += swimmer.direction * swimmer.speed * dt
	local span = halfWidth(swimmer.z, aspect) + swimmer.length
	if swimmer.x * swimmer.direction > span then
		swimmer.x = -swimmer.direction * span
	end
	local y = swimmer.y + math.sin(t * 0.55 + swimmer.phase) * swimmer.bob
	local climb = math.cos(t * 0.55 + swimmer.phase) * swimmer.bob * 0.55 * 0.25
	local position = Vector3.new(swimmer.x, y, swimmer.z)
	local frame = CFrame.lookAt(position, position + Vector3.new(swimmer.direction, climb, 0))
	if swimmer.flip then
		frame *= CFrame.Angles(0, math.pi, 0)
	end
	local wave = t * swimmer.wave * 2 * math.pi + swimmer.phase
	if swimmer.model then
		(swimmer.model :: Model):PivotTo(frame * swimmer.offset)
		if #swimmer.spine > 0 then
			SwimWave.applyBones(swimmer.bones, swimmer.spine, wave, 0.32, 0)
		end
	elseif swimmer.mesh then
		(swimmer.mesh :: BasePart).CFrame = frame * CFrame.Angles(0, math.sin(wave) * 0.08, 0)
	elseif swimmer.body and swimmer.tail then
		local body = swimmer.body :: BasePart
		local tail = swimmer.tail :: BasePart
		body.CFrame = frame * CFrame.Angles(0, math.sin(wave) * 0.06, 0)
		tail.CFrame = frame
			* CFrame.new(0, 0, body.Size.Z * 0.45)
			* CFrame.Angles(0, math.sin(wave + 1.2) * 0.45, 0)
			* CFrame.new(0, 0, tail.Size.Z * 0.4)
	end
end

local KELP_GREEN = Color3.fromRGB(70, 128, 54)

-- A stalk of kelp built from parts (low-poly, like the world's), rooted at `base`
local function kelp(world: WorldModel, base: CFrame, height: number, thickness: number): Kelp
	local count = 9
	local segment = height / count
	local stalk: Kelp =
		{ segments = {}, blades = {}, base = base, phase = math.random() * 6, length = segment }
	for i = 1, count do
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = KELP_GREEN:Lerp(Color3.fromRGB(150, 160, 70), i / count * 0.5)
		part.Size = Vector3.new(thickness, segment * 1.05, thickness)
		part.Parent = world
		table.insert(stalk.segments, part)
		if i > 1 then
			for side = -1, 1, 2 do
				local blade = Instance.new("Part")
				blade.Anchored = true
				blade.CanCollide = false
				blade.CanQuery = false
				blade.CanTouch = false
				blade.CastShadow = false
				blade.Material = Enum.Material.SmoothPlastic
				blade.Color = part.Color:Lerp(Color3.fromRGB(120, 150, 60), 0.3)
				blade.Size = Vector3.new(thickness * 3.6, segment * 0.95, 0.08)
				blade.Parent = world
				table.insert(stalk.blades, { part = blade :: BasePart, segment = i, side = side })
			end
		end
	end
	table.insert(kelps, stalk)
	return stalk
end

local function swayKelp(stalk: Kelp, t: number, parts: { BasePart }, frames: { CFrame })
	local cf = stalk.base
	local joints: { CFrame } = {}
	for i, part in stalk.segments do
		local bend = math.sin(t * 0.8 + stalk.phase - i * 0.35) * 0.05
			+ 0.012 * i * math.sin(t * 0.3 + stalk.phase)
		cf = cf * CFrame.Angles(bend * 0.4, 0, bend)
		local centre = cf * CFrame.new(0, stalk.length / 2, 0)
		table.insert(parts, part)
		table.insert(frames, centre)
		joints[i] = centre
		cf = cf * CFrame.new(0, stalk.length, 0)
	end
	for _, blade in stalk.blades do
		local at = joints[blade.segment]
		local flutter = math.sin(t * 1.7 + stalk.phase + blade.segment) * 0.25
		table.insert(parts, blade.part)
		table.insert(
			frames,
			at
				* CFrame.Angles(0, blade.side * 0.5, 0)
				* CFrame.new(blade.side * blade.part.Size.X * 0.45, 0, 0)
				* CFrame.Angles(0, 0, blade.side * (0.35 + flutter))
		)
	end
end

local function rock(world: WorldModel, cframe: CFrame, size: Vector3, color: Color3)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Slate
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Parent = world
end

local function viewport(parent: Instance, name: string, order: number): (ViewportFrame, WorldModel, Camera)
	local frame = Instance.new("ViewportFrame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.ZIndex = order
	local world = Instance.new("WorldModel")
	world.Parent = frame
	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	camera.Parent = frame
	frame.CurrentCamera = camera
	frame.Parent = parent
	return frame, world, camera
end

-- The imported model of a playable fish (named after its species or its body plan),
-- of a prey fish, or of a boss
local function speciesModel(id: string): Instance?
	local species = Config.Species.byId[id]
	return FishBuilder.meshTemplate(if species then species.plan else id)
end

local function folderModel(folderName: string, name: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild(folderName)
	return folder and folder:FindFirstChild(name)
end

-- Screen ---------------------------------------------------------------------------

-- The device, read when the screen opens and changed only by real input of another
-- kind: the Device Simulator turns its keyboard flag on ~2 s in, which flipped a
-- phone's prompt to PRESS ANY KEY (playtest 2026-10-09)
type Device = "touch" | "gamepad" | "keys"
local device: Device = "keys"

local function deviceFromInput(kind: Enum.UserInputType): Device?
	if kind == Enum.UserInputType.Touch then
		return "touch"
	elseif kind.Name:sub(1, 7) == "Gamepad" then
		return "gamepad"
	elseif
		kind == Enum.UserInputType.Keyboard
		or kind == Enum.UserInputType.MouseButton1
		or kind == Enum.UserInputType.MouseButton2
	then
		return "keys"
	end
	return nil
end

local function promptText(): string
	if device == "touch" then
		return "TAP TO START"
	elseif device == "gamepad" then
		return "PRESS ANY BUTTON"
	end
	return "PRESS ANY KEY"
end

local function biteKey(): string
	if device == "touch" then
		return "the BITE button"
	elseif device == "gamepad" then
		return "RB or X"
	end
	return "Click or F"
end

local function ready(): boolean
	local character = Players.LocalPlayer.Character
	return character ~= nil
		and character:FindFirstChild("HumanoidRootPart") ~= nil
		and ClientState.current ~= nil
end

local function gradient(
	parent: Instance,
	rotation: number,
	transparency: NumberSequence,
	color: ColorSequence?
)
	local made = Instance.new("UIGradient")
	made.Rotation = rotation
	made.Transparency = transparency
	if color then
		made.Color = color
	end
	made.Parent = parent
	return made
end

function StartController.start()
	device = (if Input.isTouch() then "touch" elseif Input.isGamepad() then "gamepad" else "keys") :: Device
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	up = true
	Input.locked = true
	Input.cursorWanted = true
	-- Chat and the player list stay out of the way until the dive
	local hiddenCore: { Enum.CoreGuiType } = {}
	for _, coreGui in { Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList } do
		local ok, enabled = pcall(function()
			return StarterGui:GetCoreGuiEnabled(coreGui)
		end)
		if ok and enabled then
			pcall(function()
				StarterGui:SetCoreGuiEnabled(coreGui, false)
			end)
			table.insert(hiddenCore, coreGui)
		end
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "StartScreen"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Edge to edge: inside the safe area, a phone's notch strips showed the game
	-- world, cutting the scene's fish off at the seam (playtest 2026-10-09)
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 100
	gui.Parent = playerGui

	-- The water: lighter toward the surface
	local cover = Instance.new("TextButton")
	cover.Name = "Cover"
	cover.Text = ""
	cover.AutoButtonColor = false
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = Color3.new(1, 1, 1)
	cover.BorderSizePixel = 0
	cover.Selectable = false
	cover.ZIndex = 0
	cover.Parent = gui
	gradient(
		cover,
		90,
		NumberSequence.new(0),
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 132, 168)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(14, 62, 98)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 16, 32)),
		})
	)

	-- Light shafts from the surface
	local shafts: { { frame: Frame, base: number, phase: number } } = {}
	for i = 1, 6 do
		local shaft = Instance.new("Frame")
		shaft.Name = "Shaft"
		shaft.AnchorPoint = Vector2.new(0.5, 0)
		shaft.Position = UDim2.new(0.08 + (i - 1) * 0.17, 0, -0.1, 0)
		shaft.Size = UDim2.new(0.05 + (i % 3) * 0.025, 0, 1.15, 0)
		shaft.BackgroundColor3 = Color3.fromRGB(190, 240, 255)
		shaft.BorderSizePixel = 0
		shaft.Rotation = -14 + (i % 2) * 6
		shaft.ZIndex = 1
		gradient(
			shaft,
			90,
			NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.55),
				NumberSequenceKeypoint.new(0.55, 0.88),
				NumberSequenceKeypoint.new(1, 1),
			})
		)
		shaft.Parent = gui
		table.insert(shafts, { frame = shaft, base = shaft.Rotation, phase = i * 1.3 })
	end

	-- The far water (hazed) and the near water
	local far, farWorld, farCamera = viewport(gui, "Far", 2)
	far.Ambient = Color3.fromRGB(70, 110, 140)
	far.LightColor = Color3.fromRGB(150, 205, 235)
	far.LightDirection = Vector3.new(-0.2, -1, -0.3)
	far.ImageColor3 = Color3.fromRGB(120, 175, 210)
	far.ImageTransparency = 0.3
	local near, nearWorld, nearCamera = viewport(gui, "Near", 4)
	near.Ambient = Color3.fromRGB(110, 150, 170)
	near.LightColor = Color3.fromRGB(215, 240, 255)
	near.LightDirection = Vector3.new(-0.25, -1, -0.35)

	-- The floor and rocks far off; kelp far and near
	local sand = Instance.new("Part")
	sand.Anchored = true
	sand.CanCollide = false
	sand.CastShadow = false
	sand.Material = Enum.Material.Sand
	sand.Color = Color3.fromRGB(150, 160, 140)
	sand.Size = Vector3.new(900, 2, 400)
	sand.CFrame = CFrame.new(0, -12, -210)
	sand.Parent = farWorld
	local rng = Random.new(7)
	for _ = 1, 14 do
		local x = rng:NextNumber(-120, 120)
		local z = rng:NextNumber(-150, -55)
		local size = rng:NextNumber(4, 14)
		rock(
			farWorld,
			CFrame.new(x, -11 + size * 0.2, z)
				* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), 0.3),
			Vector3.new(size * 1.4, size * 0.7, size),
			Color3.fromRGB(96, 110, 112)
		)
	end
	for i = 1, 9 do
		local x = -95 + (i - 1) * 24 + rng:NextNumber(-8, 8)
		kelp(farWorld, CFrame.new(x, -11, rng:NextNumber(-110, -70)), rng:NextNumber(38, 58), 0.9)
	end
	for _, spot in
		{
			Vector3.new(-17, -11, -22),
			Vector3.new(-13.5, -11, -27),
			Vector3.new(-21, -11, -30),
			Vector3.new(16, -11, -21),
			Vector3.new(20.5, -11, -28),
			Vector3.new(13, -11, -33),
		}
	do
		kelp(nearWorld, CFrame.new(spot), rng:NextNumber(20, 27), 0.45)
		rock(
			nearWorld,
			CFrame.new(spot + Vector3.new(rng:NextNumber(-1, 1), 0.3, 0.8))
				* CFrame.Angles(0.2, rng:NextNumber(0, 6), 0.1),
			Vector3.new(3.2, 1.6, 2.4),
			Color3.fromRGB(104, 112, 108)
		)
	end

	-- Who swims past: the playable fish up close, a sardine school between, minnows
	-- and a big shark's shadow far off
	local species = Config.Species.byId
	local function speciesColor(id: string): Color3
		local entry = species[id]
		return if entry then entry.back else Ui.color.accent
	end
	fish(nearWorld, speciesModel("Nibbler"), 4.6, speciesColor("Nibbler"), {
		speed = 4.2,
		direction = 1,
		x = -6,
		y = -1.2,
		z = -18,
		bob = 0.8,
		wave = 2.2,
	})
	fish(nearWorld, speciesModel("Cuda"), 8, speciesColor("Cuda"), {
		speed = 6,
		direction = -1,
		x = 12,
		y = 2.6,
		z = -27,
		bob = 0.6,
		wave = 1.6,
	})
	fish(nearWorld, speciesModel("Pufferfish"), 3.6, speciesColor("Pufferfish"), {
		speed = 2.4,
		direction = 1,
		x = 18,
		y = -4.5,
		z = -15,
		bob = 0.5,
		wave = 2.6,
	})
	local sardine = Config.Prey.byId.Sardine
	for i = 1, 11 do
		fish(
			nearWorld,
			folderModel("PreyModels", "Sardine"),
			1.5,
			if sardine then sardine.back else Color3.fromRGB(150, 170, 190),
			{
				speed = 7,
				direction = -1,
				x = 26 + (i % 4) * 2.4 + i * 1.3,
				y = 5 + (i % 3) * 1.1 - (i % 2) * 0.8,
				z = -36 - (i % 5) * 1.4,
				bob = 0.35,
				wave = 3.4,
			}
		)
	end
	local minnow = Config.Prey.byId.Minnow
	for i = 1, 16 do
		fish(
			farWorld,
			folderModel("PreyModels", "Minnow"),
			1.6,
			if minnow then minnow.back else Color3.fromRGB(150, 170, 190),
			{
				speed = 5,
				direction = 1,
				x = -70 + (i % 5) * 3 + i * 2.2,
				y = 8 + (i % 4) * 1.6,
				z = -78 - (i % 3) * 3,
				bob = 0.5,
				wave = 3,
			}
		)
	end
	local shadow = fish(farWorld, folderModel("FishModels", "Megalodon"), 46, Color3.fromRGB(70, 86, 100), {
		speed = 4.5,
		direction = -1,
		x = 60,
		y = 16,
		z = -125,
		bob = 1.4,
		wave = 0.5,
	})
	if shadow.model == nil and shadow.body then
		-- No Megalodon imported: a Reef Shark stands in, far off
		(shadow.body :: BasePart).Transparency = 1;
		(shadow.tail :: BasePart).Transparency = 1
		fish(farWorld, speciesModel("ReefShark"), 22, Color3.fromRGB(70, 86, 100), {
			speed = 5,
			direction = -1,
			x = 40,
			y = 14,
			z = -110,
			bob = 1,
			wave = 0.8,
		})
	end

	-- Marine snow and rising bubbles
	local specks: { { frame: Frame, x: number, y: number, speed: number, drift: number } } = {}
	for _ = 1, 46 do
		local speck = Instance.new("Frame")
		local size = math.random(2, 4)
		speck.Size = UDim2.fromOffset(size, size)
		speck.BackgroundColor3 = Color3.fromRGB(225, 245, 255)
		speck.BackgroundTransparency = 0.45 + math.random() * 0.4
		speck.BorderSizePixel = 0
		speck.ZIndex = 5
		Ui.corner(speck, UDim.new(1, 0))
		speck.Parent = gui
		table.insert(specks, {
			frame = speck,
			x = math.random(),
			y = math.random(),
			speed = 0.006 + math.random() * 0.014,
			drift = math.random() * 6,
		})
	end
	local bubbles: { { frame: Frame, x: number, y: number, speed: number, wobble: number } } = {}
	local function bubble(x: number, y: number, speed: number, size: number)
		local ring = Instance.new("Frame")
		ring.Size = UDim2.fromOffset(size, size)
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.BackgroundColor3 = Color3.fromRGB(200, 240, 255)
		ring.BackgroundTransparency = 0.85
		ring.BorderSizePixel = 0
		ring.ZIndex = 6
		Ui.corner(ring, UDim.new(1, 0))
		Ui.stroke(ring, Color3.fromRGB(220, 250, 255), 0.35, 1.2)
		ring.Parent = gui
		table.insert(bubbles, { frame = ring, x = x, y = y, speed = speed, wobble = math.random() * 6 })
	end
	for _ = 1, 12 do
		bubble(
			if math.random() < 0.5 then 0.06 + math.random() * 0.2 else 0.74 + math.random() * 0.2,
			math.random(),
			0.04 + math.random() * 0.05,
			math.random(5, 12)
		)
	end

	-- The top and bottom edges darken, so the middle reads
	local edges: { Frame } = {}
	local function edge(rotation: number, height: number, y: number)
		local shade = Instance.new("Frame")
		shade.Name = "Edge"
		shade.BackgroundColor3 = Color3.fromRGB(2, 8, 18)
		shade.BorderSizePixel = 0
		shade.Size = UDim2.fromScale(1, height)
		shade.Position = UDim2.fromScale(0, y)
		shade.ZIndex = 7
		gradient(shade, rotation, NumberSequence.new(1, 0.15))
		shade.Parent = gui
		table.insert(edges, shade)
	end
	edge(90, 0.3, 0.7)
	edge(270, 0.18, 0)

	-- The title, how to play and the prompt, on a scaled layer
	local layer = Instance.new("Frame")
	layer.Name = "Layer"
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 8
	layer.Parent = gui
	local layerScale = Instance.new("UIScale")
	layerScale.Parent = layer
	local function rescale()
		local size = workspace.CurrentCamera.ViewportSize
		local design = if Ui.isTouch() then Vector2.new(960, 540) else Vector2.new(1280, 720)
		local scale = math.clamp(math.min(size.X / design.X, size.Y / design.Y), 0.55, 1.4)
		layerScale.Scale = scale
		-- The layer is scaled about its corner, so size it to fill the screen
		layer.Size = UDim2.fromScale(1 / scale, 1 / scale)
	end
	rescale()
	local viewportChanged = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	local titleGroup = Instance.new("Frame")
	titleGroup.Name = "Title"
	titleGroup.BackgroundTransparency = 1
	titleGroup.AnchorPoint = Vector2.new(0.5, 0.5)
	titleGroup.Position = UDim2.fromScale(0.5, 0.3)
	titleGroup.Size = UDim2.fromOffset(820, 170)
	titleGroup.ZIndex = 8
	titleGroup.Parent = layer
	local titlePop = Instance.new("UIScale")
	titlePop.Scale = 0.82
	titlePop.Parent = titleGroup
	local title = Ui.label(
		titleGroup,
		"Name",
		"APEX ABYSS",
		Ui.FONT_HEAVY,
		100,
		Color3.new(1, 1, 1),
		UDim2.new(1, 0, 0, 112)
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.ZIndex = 9
	title.TextTransparency = 1
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(4, 26, 44)
	titleStroke.Thickness = 4
	titleStroke.Transparency = 1
	titleStroke.Parent = title
	local shine = gradient(
		title,
		100,
		NumberSequence.new(0),
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 236, 255)),
			ColorSequenceKeypoint.new(0.42, Color3.fromRGB(226, 250, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.58, Color3.fromRGB(226, 250, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(96, 200, 236)),
		})
	)
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.new(0.5, 0, 0, 116)
	rule.Size = UDim2.fromOffset(0, 2)
	rule.BackgroundColor3 = Ui.color.accent
	rule.BorderSizePixel = 0
	rule.ZIndex = 9
	gradient(
		rule,
		0,
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
	)
	rule.Parent = titleGroup
	local subtitle = Ui.label(
		titleGroup,
		"Subtitle",
		"EAT   ·   GROW   ·   BECOME THE APEX",
		Ui.FONT_BOLD,
		22,
		Ui.color.accent,
		UDim2.new(1, 0, 0, 28),
		UDim2.fromOffset(0, 128)
	)
	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	subtitle.ZIndex = 9
	subtitle.TextTransparency = 1
	subtitle.TextStrokeTransparency = 1

	-- How to play, in three lines (owner: "needs to be clear mechanics on how to
	-- actually bite fish")
	local guide = Instance.new("Frame")
	guide.Name = "HowToPlay"
	guide.BackgroundTransparency = 1
	guide.AnchorPoint = Vector2.new(0.5, 0)
	guide.Position = UDim2.fromScale(0.5, 0.58)
	guide.Size = UDim2.fromOffset(780, 76)
	guide.ZIndex = 8
	guide.Parent = layer
	local guideLayout = Instance.new("UIListLayout")
	guideLayout.FillDirection = Enum.FillDirection.Horizontal
	guideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	guideLayout.Padding = UDim.new(0, 12)
	guideLayout.SortOrder = Enum.SortOrder.LayoutOrder
	guideLayout.Parent = guide
	local guideCards: { Frame } = {}
	local guideLines: { TextLabel } = {}
	local function guideCard(order: number, heading: string, line: string, color: Color3)
		local card = Ui.panel(guide, `Step{order}`, UDim2.fromOffset(250, 74), UDim2.new())
		card.LayoutOrder = order
		card.ZIndex = 8
		card.BackgroundTransparency = 1
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
			stroke.Transparency = 1
		end
		local head = Ui.label(
			card,
			"Heading",
			heading,
			Ui.FONT_HEAVY,
			16,
			color,
			UDim2.new(1, -24, 0, 20),
			UDim2.fromOffset(12, 9)
		)
		head.ZIndex = 9
		head.TextTransparency = 1
		local body = Ui.label(
			card,
			"Line",
			line,
			Ui.FONT_SEMI,
			14,
			Ui.color.text,
			UDim2.new(1, -24, 0, 36),
			UDim2.fromOffset(12, 30)
		)
		body.TextWrapped = true
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.ZIndex = 9
		body.TextTransparency = 1
		table.insert(guideCards, card)
		table.insert(guideLines, head)
		table.insert(guideLines, body)
		return body
	end
	guideCard(1, "EAT", "Swim into smaller fish to swallow them. Too big? They chase you.", Ui.color.safe)
	local biteLine = guideCard(2, "BITE", "", Ui.color.danger)
	guideCard(3, "BANK", "Swim home to your den's pool to keep what you ate.", Ui.color.haul)
	local function refreshBite()
		biteLine.Text = `{biteKey()} bites fish your size, predators and bosses.`
	end
	refreshBite()

	local prompt = Ui.label(
		layer,
		"Prompt",
		"LOADING THE REEF",
		Ui.FONT_HEAVY,
		26,
		Ui.color.muted,
		UDim2.fromOffset(600, 32)
	)
	prompt.AnchorPoint = Vector2.new(0.5, 0)
	prompt.Position = UDim2.fromScale(0.5, 0.82)
	prompt.TextXAlignment = Enum.TextXAlignment.Center
	prompt.TextStrokeTransparency = 0.6
	prompt.ZIndex = 9

	-- Entrance
	Ui.tween(title, 0.9, { TextTransparency = 0 })
	Ui.tween(titleStroke, 0.9, { Transparency = 0.25 })
	Ui.tween(titlePop, 1.1, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(0.45, function()
		Ui.tween(rule, 0.8, { Size = UDim2.fromOffset(480, 2) })
		Ui.tween(subtitle, 0.7, { TextTransparency = 0, TextStrokeTransparency = 0.7 })
	end)
	task.delay(0.9, function()
		for i, card in guideCards do
			task.delay((i - 1) * 0.12, function()
				Ui.tween(card, 0.5, { BackgroundTransparency = 0.35 })
				local stroke = card:FindFirstChildOfClass("UIStroke")
				if stroke then
					Ui.tween(stroke, 0.5, { Transparency = 0.45 })
				end
			end)
		end
		for _, line in guideLines do
			Ui.tween(line, 0.6, { TextTransparency = 0 })
		end
	end)

	-- Motion
	local opened = os.clock()
	local promptAt: number? = nil
	local dive = 0 -- 0..1 once started: the cameras rush forward
	local leaving = false
	local renderConnection = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - opened
		local size = gui.AbsoluteSize
		local aspect = if size.Y > 0 then size.X / size.Y else 16 / 9
		-- Both cameras drift together (parallax), and rush ahead on the dive
		local eye = Vector3.new(math.sin(t * 0.13) * 1.4, 2 + math.sin(t * 0.21) * 0.6, -dive * dive * 26)
		local view = CFrame.lookAt(eye, Vector3.new(eye.X * 0.4, -1.5, -40 - dive * 26))
		nearCamera.CFrame = view
		farCamera.CFrame = view
		nearCamera.FieldOfView = FOV + dive * 18
		farCamera.FieldOfView = FOV + dive * 18
		for _, swimmer in swimmers do
			moveSwimmer(swimmer, t, dt, aspect)
		end
		local nearParts: { BasePart } = {}
		local nearFrames: { CFrame } = {}
		local farParts: { BasePart } = {}
		local farFrames: { CFrame } = {}
		for _, stalk in kelps do
			local first = stalk.segments[1]
			if first and first:IsDescendantOf(nearWorld) then
				swayKelp(stalk, t, nearParts, nearFrames)
			else
				swayKelp(stalk, t, farParts, farFrames)
			end
		end
		nearWorld:BulkMoveTo(nearParts, nearFrames, Enum.BulkMoveMode.FireCFrameChanged)
		farWorld:BulkMoveTo(farParts, farFrames, Enum.BulkMoveMode.FireCFrameChanged)
		for _, shaft in shafts do
			shaft.frame.Rotation = shaft.base + math.sin(t * 0.25 + shaft.phase) * 3
			shaft.frame.BackgroundTransparency = 0.25 + 0.2 * math.sin(t * 0.4 + shaft.phase)
		end
		for _, speck in specks do
			speck.y += speck.speed * dt
			if speck.y > 1.02 then
				speck.y = -0.02
				speck.x = math.random()
			end
			speck.frame.Position = UDim2.fromScale(speck.x + math.sin(t * 0.3 + speck.drift) * 0.01, speck.y)
		end
		for _, b in bubbles do
			b.y -= b.speed * dt * (1 + dive * 6)
			if b.y < -0.05 then
				b.y = 1.05
			end
			b.frame.Position = UDim2.fromScale(b.x + math.sin(t * 2 + b.wobble) * 0.006, b.y)
		end
		shine.Offset = Vector2.new(((t * 0.22) % 1.6) - 0.8, 0)
		if promptAt and not leaving then
			prompt.TextTransparency = 0.15 + 0.45 * (0.5 + 0.5 * math.cos((os.clock() - promptAt) * 3.2))
		elseif not leaving then
			local dots = math.floor(t * 2.5) % 4
			prompt.Text = "LOADING THE REEF" .. string.rep(".", dots)
		end
	end)

	-- Dive in
	local inputConnection: RBXScriptConnection? = nil
	local tapConnection: RBXScriptConnection? = nil
	local inputTypeConnection: RBXScriptConnection? = nil
	local function go()
		if leaving or promptAt == nil or os.clock() - (promptAt :: number) < GRACE then
			return
		end
		leaving = true
		if inputConnection then
			inputConnection:Disconnect()
		end
		if tapConnection then
			tapConnection:Disconnect()
		end
		if inputTypeConnection then
			inputTypeConnection:Disconnect()
		end
		Sfx.play("Dash", { volume = 0.7 })
		Sfx.play("Bubbles", { volume = 0.6 })
		for _ = 1, 26 do
			bubble(
				0.3 + math.random() * 0.4,
				0.95 + math.random() * 0.25,
				0.35 + math.random() * 0.4,
				math.random(8, 22)
			)
		end
		Ui.tween(titlePop, 0.7, { Scale = 1.35 }, Enum.EasingStyle.Quad)
		for _, label in { title, subtitle, prompt } do
			Ui.tween(label, 0.45, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
		Ui.tween(titleStroke, 0.45, { Transparency = 1 })
		Ui.tween(rule, 0.45, { BackgroundTransparency = 1 })
		for _, card in guideCards do
			Ui.tween(card, 0.35, { BackgroundTransparency = 1 })
			local stroke = card:FindFirstChildOfClass("UIStroke")
			if stroke then
				Ui.tween(stroke, 0.35, { Transparency = 1 })
			end
		end
		for _, line in guideLines do
			Ui.tween(line, 0.35, { TextTransparency = 1 })
		end
		task.spawn(function()
			local from = os.clock()
			while dive < 1 do
				dive = math.min(1, (os.clock() - from) / 0.9)
				RunService.RenderStepped:Wait()
			end
		end)
		-- The game shows through as the water clears
		task.delay(0.35, function()
			up = false
			Input.locked = false
			Input.cursorWanted = false
			for _, coreGui in hiddenCore do
				pcall(function()
					StarterGui:SetCoreGuiEnabled(coreGui, true)
				end)
			end
			Ui.tween(cover, 0.7, { BackgroundTransparency = 1 })
			Ui.tween(near, 0.6, { ImageTransparency = 1 })
			Ui.tween(far, 0.5, { ImageTransparency = 1 })
			for _, shaft in shafts do
				shaft.frame.Visible = false
			end
			for _, speck in specks do
				Ui.tween(speck.frame, 0.5, { BackgroundTransparency = 1 })
			end
			for _, shade in edges do
				Ui.tween(shade, 0.6, { BackgroundTransparency = 1 })
			end
			for _, b in bubbles do
				Ui.tween(b.frame, 0.7, { BackgroundTransparency = 1 })
				local stroke = b.frame:FindFirstChildOfClass("UIStroke")
				if stroke then
					Ui.tween(stroke, 0.7, { Transparency = 1 })
				end
			end
			done = true
			StartController.started:fire()
			local queued = waiting
			waiting = {}
			for _, fn in queued do
				task.spawn(fn)
			end
		end)
		task.delay(1.4, function()
			renderConnection:Disconnect()
			viewportChanged:Disconnect()
			gui:Destroy()
			table.clear(swimmers)
			table.clear(kelps)
		end)
	end

	-- Any key, click, tap or controller button (not a stick nudging, nor Escape,
	-- which opens Roblox's menu)
	local function isStart(input: InputObject): boolean
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Keyboard then
			return input.KeyCode ~= Enum.KeyCode.Escape
		elseif kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 then
			return true
		elseif kind == Enum.UserInputType.Touch then
			return true
		elseif kind.Name:sub(1, 7) == "Gamepad" then
			local name = input.KeyCode.Name
			return name:sub(1, 6) == "Button" or name:sub(1, 4) == "DPad"
		end
		return false
	end
	inputConnection = UserInputService.InputBegan:Connect(function(input)
		if isStart(input) then
			go()
		end
	end)
	tapConnection = cover.Activated:Connect(go)
	inputTypeConnection = UserInputService.LastInputTypeChanged:Connect(function(kind)
		local now = deviceFromInput(kind)
		if now == nil or now == device then
			return
		end
		device = now :: Device
		refreshBite()
		if promptAt then
			prompt.Text = promptText()
		end
	end)

	-- The prompt shows once the fish is in its den (and the screen has had a moment)
	task.spawn(function()
		while not ready() and os.clock() - opened < MAX_WAIT do
			task.wait(0.2)
		end
		local left = MIN_SHOW - (os.clock() - opened)
		if left > 0 then
			task.wait(left)
		end
		prompt.Text = promptText()
		prompt.TextColor3 = Color3.new(1, 1, 1)
		promptAt = os.clock()
	end)
end

return StartController
