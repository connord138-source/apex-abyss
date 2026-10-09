--!strict
-- The treasure hunt on this client (Config/Treasure): while a map is followed, a
-- sonar card on the HUD beats faster the closer you get and says how hot you are;
-- inside `arrow` studs an arrow points the way; inside `mark` an X glows on the
-- seabed that only you see (the site is in your own state); on the X, hold E (Y on
-- a pad, DIG on touch) to dig. The server checks the map and the spot and sends the
-- treasure, which the roll reveal opens.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Sfx = require(script.Parent.Parent.Sfx)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Ui = require(script.Parent.Parent.Ui)
local MenuController = require(script.Parent.MenuController)
local RollController = require(script.Parent.RollController)
local SwimController = require(script.Parent.SwimController)

local Treasure = Config.Treasure

local TreasureController = {}

local gui: ScreenGui
local card: Frame
local tierLabel: TextLabel
local wordLabel: TextLabel
local arrow: TextLabel
local pulse: Frame
local digHint: TextLabel
local digRing: Frame
local digFill: Frame
local digButton: TextButton? = nil
local marker: Model? = nil
local markerLight: PointLight? = nil

local pulseClock = 0
local digging = false
local digStart = 0
local digSeconds = 3
local atSite = false

type Map = { id: string, tier: string, site: { x: number, y: number, z: number }, hint: string }

local function activeMap(): Map?
	local s = ClientState.current
	if s == nil or typeof(s.maps) ~= "table" or typeof(s.activeMap) ~= "string" or s.activeMap == "" then
		return nil
	end
	for _, map in s.maps do
		if map.id == s.activeMap then
			return map
		end
	end
	return nil
end

-- The chest at the dig site, half out of the sand, only on this client (owner,
-- 2026-10-07: "a chest partially sticking out of the ground to show them an actual
-- physical spot"). The imported TreasureChest prop when it exists, else a chunky
-- part-built chest in the same spirit: dark planks, brass bands, a domed lid.
local chestLid: BasePart? = nil
local chestHinge: CFrame? = nil
local openUntil = 0

local function buildMarker(position: Vector3, color: Color3)
	local model = Instance.new("Model")
	model.Name = "TreasureChest"
	local yaw = (position.X * 0.37 + position.Z * 0.61) % (2 * math.pi)
	local base = CFrame.new(position + Vector3.new(0, -0.9, 0))
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(math.rad(-9), 0, math.rad(6))
	local function part(
		name: string,
		size: Vector3,
		cframe: CFrame,
		partColor: Color3,
		material: Enum.Material
	): Part
		local made = Instance.new("Part")
		made.Name = name
		made.Anchored = true
		made.CanCollide = false
		made.CanQuery = false
		made.CanTouch = false
		made.CastShadow = false
		made.Size = size
		made.CFrame = cframe
		made.Color = partColor
		made.Material = material
		made.Parent = model
		return made
	end
	local wood = Color3.fromRGB(78, 54, 36)
	local brass = Color3.fromRGB(212, 160, 70)
	-- The sand it sits in
	local mound = part(
		"Mound",
		Vector3.new(11, 2.6, 9),
		base * CFrame.new(0, -0.6, 0),
		Color3.fromRGB(206, 194, 156),
		Enum.Material.Sand
	)
	mound.Shape = Enum.PartType.Ball
	local body =
		part("Body", Vector3.new(6.4, 3.4, 4.4), base * CFrame.new(0, 1.7, 0), wood, Enum.Material.WoodPlanks)
	for _, x in { -2.2, 2.2 } do
		part("Band", Vector3.new(0.6, 3.6, 4.6), base * CFrame.new(x, 1.7, 0), brass, Enum.Material.Metal)
	end
	part("Lock", Vector3.new(1.2, 1.3, 0.4), base * CFrame.new(0, 2.2, -2.3), brass, Enum.Material.Metal)
	-- The lid hinges at the back edge
	local hinge = base * CFrame.new(0, 3.4, 2.2)
	local lid = part(
		"Lid",
		Vector3.new(6.6, 2.2, 4.6),
		hinge * CFrame.new(0, 0.9, -2.2),
		wood,
		Enum.Material.WoodPlanks
	)
	lid.Shape = Enum.PartType.Cylinder
	lid.Size = Vector3.new(6.6, 4.6, 4.6)
	lid.CFrame = hinge * CFrame.new(0, 0, -2.2) * CFrame.Angles(0, 0, 0)
	-- A seam of light where the lid meets the body, in the map's tier color
	local seam =
		part("Seam", Vector3.new(6.2, 0.15, 4.2), base * CFrame.new(0, 3.45, 0), color, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 18
	light.Brightness = 1.4
	light.Parent = seam
	-- The imported prop replaces the planks when it exists
	local props = ReplicatedStorage:FindFirstChild("WorldProps")
	local template = props and props:FindFirstChild("TreasureChest")
	if template and template:IsA("Model") and template:FindFirstChildWhichIsA("BasePart", true) then
		local clone = template:Clone()
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
			end
		end
		clone:ScaleTo(1)
		clone:ScaleTo(7 / math.max(clone:GetExtentsSize().X, 0.01))
		clone:PivotTo(base * CFrame.new(0, clone:GetExtentsSize().Y * 0.3, 0))
		clone.Parent = model
		body.Transparency = 1
		lid.Transparency = 1
		for _, child in model:GetChildren() do
			if child.Name == "Band" or child.Name == "Lock" then
				child:Destroy()
			end
		end
	end
	local sand = Instance.new("ParticleEmitter")
	sand.Name = "Sand"
	sand.Rate = 0
	sand.Lifetime = NumberRange.new(0.6, 1.1)
	sand.Speed = NumberRange.new(3, 7)
	sand.SpreadAngle = Vector2.new(60, 60)
	sand.Size = NumberSequence.new(0.6, 1.4)
	sand.Transparency = NumberSequence.new(0.3, 1)
	sand.Color = ColorSequence.new(Color3.fromRGB(214, 200, 160))
	sand.Parent = mound
	model.Parent = workspace
	marker = model
	markerLight = light
	chestLid = lid
	chestHinge = hinge
end

-- The chest opens: the lid swings back and gold light spills out
local function openChest()
	local lid, hinge = chestLid, chestHinge
	if lid == nil or hinge == nil then
		return
	end
	openUntil = os.clock() + 2.5
	Sfx.play("ChestOpen", { volume = 0.8, parent = lid :: Instance, range = 140 })
	local target = hinge * CFrame.Angles(math.rad(-105), 0, 0) * CFrame.new(0, 0, -2.2)
	Ui.tween(lid, 0.5, { CFrame = target }, Enum.EasingStyle.Back)
	local glow = Instance.new("ParticleEmitter")
	glow.Rate = 0
	glow.Lifetime = NumberRange.new(0.8, 1.6)
	glow.Speed = NumberRange.new(4, 12)
	glow.SpreadAngle = Vector2.new(50, 50)
	glow.Size = NumberSequence.new(0.5, 0.1)
	glow.Transparency = NumberSequence.new(0, 1)
	glow.LightEmission = 1
	glow.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120))
	glow.Parent = lid
	glow:Emit(40)
	if markerLight then
		Ui.tween(markerLight, 0.4, { Brightness = 4, Range = 30 })
	end
end

local function clearMarker()
	if openUntil > os.clock() then
		return -- the lid is still swinging open
	end
	if marker then
		marker:Destroy()
		marker = nil
		markerLight = nil
		chestLid = nil
		chestHinge = nil
	end
end

local function stopDig(finished: boolean)
	if not digging then
		return
	end
	digging = false
	digFill.Size = UDim2.fromScale(0, 1)
	digRing.Visible = false
	if marker then
		local sand = marker:FindFirstChild("Sand", true)
		if sand and sand:IsA("ParticleEmitter") then
			sand.Rate = 0
		end
	end
	if finished then
		openChest()
		ClientState.request("FinishDig")
	end
end

local function startDig()
	if digging or not atSite or activeMap() == nil then
		return
	end
	digging = true
	digStart = os.clock()
	Sfx.play("Dig", { volume = 0.6 })
	digRing.Visible = true
	ClientState.request("StartDig")
	if marker then
		local sand = marker:FindFirstChild("Sand", true)
		if sand and sand:IsA("ParticleEmitter") then
			sand.Rate = 40
		end
	end
end

local function step(dt: number)
	local map = activeMap()
	local root = SwimController.root()
	if map == nil or root == nil then
		card.Visible = false
		digHint.Visible = false
		if digButton then
			digButton.Visible = false
		end
		atSite = false
		stopDig(false)
		clearMarker()
		return
	end
	local tier = Treasure.byId[map.tier]
	local site = Vector3.new(map.site.x, map.site.y, map.site.z)
	local offset = site - root.Position
	local distance = offset.Magnitude
	local flat = Vector2.new(offset.X, offset.Z).Magnitude
	card.Visible = true
	tierLabel.Text = string.upper(`{if tier then tier.name else map.tier} MAP`)
	tierLabel.TextColor3 = if tier then tier.color else Ui.color.text
	-- Hot and cold
	local word = "COLD"
	for _, band in Treasure.hotCold do
		if distance >= band.over then
			word = band.word
			break
		end
	end
	-- The sonar beat: a ring that swells and fades, quicker when closer
	local period = math.clamp(distance / 110, 0.3, 2.4)
	pulseClock += dt
	if pulseClock >= period then
		pulseClock -= period
		pulse.Size = UDim2.fromOffset(16, 16)
		pulse.BackgroundTransparency = 0.1
		Ui.tween(pulse, period * 0.9, { Size = UDim2.fromOffset(64, 64), BackgroundTransparency = 1 })
	end
	-- The arrow, relative to where the camera looks, inside the arrow range
	if flat <= Treasure.sonar.arrow then
		arrow.Visible = true
		local look = workspace.CurrentCamera.CFrame.LookVector
		local cameraYaw = math.atan2(-look.X, -look.Z)
		local targetYaw = math.atan2(-offset.X, -offset.Z)
		arrow.Rotation = math.deg(targetYaw - cameraYaw)
		-- Up or down too (the arrow glyph is ▲; fancier ones don't render in Roblox fonts)
		if offset.Y < -6 then
			word ..= " · BELOW"
		elseif offset.Y > 6 then
			word ..= " · ABOVE"
		end
	else
		arrow.Visible = false
	end
	wordLabel.Text = word
	-- The X, inside the mark range
	if distance <= Treasure.sonar.mark then
		if marker == nil then
			buildMarker(site, if tier then tier.color else Ui.color.haul)
		end
		if markerLight then
			markerLight.Brightness = 1 + math.sin(os.clock() * 4) * 0.5
		end
	else
		clearMarker()
	end
	-- Digging
	atSite = distance <= Treasure.sonar.dig + SwimController.length() * 0.5
	digSeconds = if tier then tier.digSeconds else 3
	local showHint = atSite and not digging and not MenuController.isOpen()
	digHint.Visible = showHint
	if showHint then
		digHint.Text = if Input.isTouch()
			then "HOLD DIG TO UNCOVER THE TREASURE"
			elseif Input.isGamepad() then "HOLD Y TO DIG"
			else "HOLD E TO DIG"
	end
	if digButton then
		digButton.Visible = atSite
	end
	if digging then
		if not atSite then
			stopDig(false)
		else
			local progress = math.clamp((os.clock() - digStart) / digSeconds, 0, 1)
			digFill.Size = UDim2.fromScale(progress, 1)
			if progress >= 1 then
				stopDig(true)
			end
		end
	end
end

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.screen("Treasure", playerGui, 6)
	-- The sonar card, above the depth gauge on the right
	card = Ui.panel(gui, "Sonar", UDim2.fromOffset(92, 118), UDim2.new(1, -18, 0.5, -120), Vector2.new(1, 1))
	if Ui.isTouch() then
		-- Phones: beside the depth gauge's top, clear of the biome chip above the
		-- gauge (the sonar sat on it) and of the boss bar (playtest 2026-10-09)
		card.AnchorPoint = Vector2.new(1, 0)
		card.Position = UDim2.new(1, -96, 0.5, -105)
	end
	tierLabel = Ui.label(
		card,
		"Tier",
		"",
		Ui.FONT_BOLD,
		10,
		Ui.color.haul,
		UDim2.new(1, 0, 0, 14),
		UDim2.fromOffset(0, 8)
	)
	tierLabel.TextXAlignment = Enum.TextXAlignment.Center
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.new(0.5, 0, 0, 54)
	ring.Size = UDim2.fromOffset(64, 64)
	ring.BackgroundTransparency = 1
	ring.Parent = card
	pulse = Instance.new("Frame")
	pulse.Name = "Pulse"
	pulse.AnchorPoint = Vector2.new(0.5, 0.5)
	pulse.Position = UDim2.fromScale(0.5, 0.5)
	pulse.Size = UDim2.fromOffset(16, 16)
	pulse.BackgroundColor3 = Ui.color.accent
	pulse.BackgroundTransparency = 1
	pulse.BorderSizePixel = 0
	Ui.corner(pulse, UDim.new(1, 0))
	pulse.Parent = ring
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(8, 8)
	dot.BackgroundColor3 = Ui.color.text
	dot.BorderSizePixel = 0
	Ui.corner(dot, UDim.new(1, 0))
	dot.Parent = ring
	arrow = Ui.label(ring, "Arrow", "▲", Ui.FONT_HEAVY, 34, Ui.color.haul, UDim2.fromScale(1, 1))
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	arrow.Visible = false
	wordLabel = Ui.label(
		card,
		"Word",
		"",
		Ui.FONT_HEAVY,
		13,
		Ui.color.text,
		UDim2.new(1, 0, 0, 16),
		UDim2.new(0, 0, 1, -24)
	)
	wordLabel.TextXAlignment = Enum.TextXAlignment.Center
	card.Visible = false

	-- The dig hint and progress, bottom center above the Haul card
	digHint = Ui.label(
		gui,
		"DigHint",
		"",
		Ui.FONT_HEAVY,
		18,
		Ui.color.haul,
		UDim2.fromOffset(420, 24),
		UDim2.new(0.5, -210, 1, -160)
	)
	digHint.TextXAlignment = Enum.TextXAlignment.Center
	digHint.TextStrokeTransparency = 0.5
	digHint.Visible = false
	local track, fill =
		Ui.bar(gui, "Dig", UDim2.fromOffset(260, 10), UDim2.new(0.5, -130, 1, -132), Ui.color.haul)
	digRing = track
	digFill = fill
	digRing.Visible = false

	if Input.isTouch() then
		local button = Instance.new("TextButton")
		button.Name = "Dig"
		button.Text = "DIG"
		button.FontFace = Ui.FONT_HEAVY
		button.TextSize = 18
		button.TextColor3 = Ui.color.panel
		button.AutoButtonColor = false
		button.Selectable = false
		button.Size = UDim2.fromOffset(84, 84)
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.new(1, -86, 1, -240)
		button.BackgroundColor3 = Ui.color.haul
		Ui.corner(button, UDim.new(1, 0))
		Ui.stroke(button, Ui.color.stroke, 0.5, 1.5)
		button.Visible = false
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				startDig()
			end
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				stopDig(false)
			end
		end)
		button.Parent = gui
		digButton = button
	end
end

function TreasureController.start()
	build()
	ContextActionService:BindAction("ApexDig", function(_, inputState)
		if not atSite or MenuController.isOpen() then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			startDig()
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			stopDig(false)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonY)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local result = remotes:WaitForChild("TreasureResult") :: RemoteEvent
	result.OnClientEvent:Connect(function(payload: { [string]: any })
		clearMarker()
		task.spawn(RollController.revealTreasure, payload)
	end)
	RunService.RenderStepped:Connect(step)
end

return TreasureController
