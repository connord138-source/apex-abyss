--!strict
-- Every fish's special attack on the client (Config/Specials; SpecialService owns the
-- meter): the meter on the HUD, the key and the touch button, what it does to our own
-- fish, and what every fish's special looks like, read from its character's attributes.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Bubbles = require(script.Parent.Parent.Bubbles)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Sfx = require(script.Parent.Parent.Sfx)
local Spring = require(script.Parent.Parent.Spring)
local Ui = require(script.Parent.Parent.Ui)
local CameraController = require(script.Parent.CameraController)
local HuntController = require(script.Parent.HuntController)
local SwimController = require(script.Parent.SwimController)

local Specials = Config.Specials
type Special = typeof(Config.Specials.bySpecies.Nibbler)

local SPIN_RATE = math.pi * 2 * 2.5 -- a Death Roll's turns a second, in radians
local HOLD_SOURCE = "roll"

local SpecialController = {}

local chip: Frame? = nil
local nameLabel: TextLabel? = nil
local fill: Frame? = nil
local chipStroke: UIStroke? = nil
local keyCap: Frame? = nil
local touchButton: TextButton? = nil
local shownMeter = 0
local spin = 0
local tint: ColorCorrectionEffect? = nil
local tintAlpha = 0

local function mySpecial(): Special?
	local state = ClientState.current
	local id = if state then state.species else nil
	return if typeof(id) == "string" then Specials.bySpecies[id] else nil
end

local function myCharacter(): Model?
	return Players.LocalPlayer.Character
end

local function numberAttribute(character: Instance?, name: string): number
	local value = if character then character:GetAttribute(name) else nil
	return if typeof(value) == "number" then value else 0
end

local function meter(): number
	return numberAttribute(myCharacter(), "SpecialMeter")
end

local function holder(position: Vector3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.CFrame = CFrame.new(position)
	part.Parent = workspace.CurrentCamera
	return part
end

-- A wave of water: a ball growing or shrinking between two radii as it fades
local function wave(position: Vector3, from: number, to: number, color: Color3, seconds: number)
	local ball = holder(position)
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.ForceField
	ball.Color = color
	ball.Transparency = 0
	ball.Size = Vector3.one * from * 2
	TweenService:Create(
		ball,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * to * 2, Transparency = 1 }
	):Play()
	task.delay(seconds + 0.1, function()
		ball:Destroy()
	end)
end

-- Flying spines all round a fish
local function spines(position: Vector3, radius: number, color: Color3)
	local random = Random.new()
	for _ = 1, 26 do
		local direction = random:NextUnitVector()
		local spine = holder(position)
		spine.Material = Enum.Material.Neon
		spine.Color = color
		spine.Transparency = 0
		local long = radius * 0.22
		spine.Size = Vector3.new(0.18 + radius * 0.008, 0.18 + radius * 0.008, long)
		spine.CFrame = CFrame.lookAt(position, position + direction)
		TweenService:Create(spine, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = spine.CFrame + direction * radius,
			Transparency = 1,
		}):Play()
		task.delay(0.55, function()
			spine:Destroy()
		end)
	end
end

-- The fish lit in its special's colour for a while
local function glow(character: Model, color: Color3, seconds: number)
	local body = character:FindFirstChild("Body")
	if body == nil then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "SpecialGlow"
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.72
	highlight.OutlineTransparency = 0.15
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = body
	task.delay(seconds, function()
		highlight:Destroy()
	end)
end

local function lengthOf(character: Model): number
	local length = character:GetAttribute("Length")
	return if typeof(length) == "number" then length else 2
end

-- What a fish's special looks like, whoever's it is
local function drawSpecial(character: Model, id: string)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local special: Special? = nil
	for _, entry in Specials.bySpecies do
		if entry.id == id then
			special = entry
		end
	end
	if special == nil then
		return
	end
	local length = lengthOf(character)
	local position = root.Position
	local mine = character == myCharacter()
	local color = special.color
	Sfx.play(
		"Chomp",
		{ volume = if mine then 0.9 else 0.5, parent = root :: Instance, range = 200, pitch = 0.7 }
	)
	if id == "SpineBurst" then
		local radius = (special.radius or 18) + length * (special.perLength or 2)
		wave(position, length * 0.5, radius, color, 0.5)
		spines(position, radius, color)
	elseif id == "AbyssMaw" then
		local radius = (special.radius or 24) + length * (special.perLength or 3)
		wave(position, radius, length * 0.4, color, special.seconds or 1.4)
		Bubbles.burst(position, length * 1.2, 24)
		glow(character, color, special.seconds or 1.4)
	else
		wave(position, length * 0.5, length * 2, color, 0.45)
		Bubbles.burst(position, length, 18)
		glow(character, color, special.seconds or (special.ticks or 5) * (special.every or 0.4))
	end
	if mine then
		CameraController.kick(0.6)
	end
end

local function watch(character: Model)
	local seen = numberAttribute(character, "SpecialAt")
	character:GetAttributeChangedSignal("SpecialAt"):Connect(function()
		local at = numberAttribute(character, "SpecialAt")
		local id = character:GetAttribute("SpecialId")
		if at > seen and typeof(id) == "string" then
			seen = at
			drawSpecial(character, id)
		end
	end)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(watch)
	if player.Character then
		watch(player.Character)
	end
end

-- What a special does to our own fish, when the server says it has started
local function startMine(character: Model)
	local at = numberAttribute(character, "SpecialAt")
	local id = character:GetAttribute("SpecialId")
	local special = mySpecial()
	if special == nil or id ~= special.id or Timing.clock() - at > 1 then
		return
	end
	if id == "WildThrash" then
		HuntController.holdOn(special.seconds or 4, true)
	elseif id == "SpearCharge" then
		SwimController.dash(special.seconds or 1.2, special.turn or 0.12, true)
	elseif id == "DeathRoll" then
		HuntController.holdOn((special.ticks or 5) * (special.every or 0.4), false)
	elseif id == "BloodFrenzy" then
		HuntController.holdOn(0.7, false)
	end
end

local function press()
	if Input.locked or Input.building then
		return
	end
	local character = myCharacter()
	if character == nil or meter() < 1 or character:GetAttribute("InHub") == true then
		return
	end
	ClientState.request("UseSpecial")
end

local function buildChip()
	local player = Players.LocalPlayer
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud") :: ScreenGui
	if Input.isTouch() then
		-- (a round button over BITE; its label is the meter)
		local button = Instance.new("TextButton")
		button.Name = "Special"
		button.Text = "0%"
		button.FontFace = Ui.FONT_HEAVY
		button.TextSize = 14
		button.TextColor3 = Ui.color.text
		button.AutoButtonColor = false
		button.Size = UDim2.fromOffset(56, 56)
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.new(1, -136, 1, -166)
		button.BackgroundColor3 = Ui.color.panel
		button.BackgroundTransparency = 0.35
		Ui.corner(button, UDim.new(1, 0))
		chipStroke = Ui.stroke(button, Ui.color.stroke, 0.5, 1.5)
		button.Activated:Connect(function()
			Input.special:fire()
		end)
		button.Parent = gui
		touchButton = button
		return
	end
	local panel =
		Ui.panel(gui, "Special", UDim2.fromOffset(176, 56), UDim2.new(0.5, 172, 1, -22), Vector2.new(0, 1))
	chip = panel
	chipStroke = Ui.stroke(panel, Ui.color.stroke, 0.5, 1.5)
	nameLabel = Ui.label(
		panel,
		"Name",
		"SPECIAL",
		Ui.FONT_HEAVY,
		13,
		Ui.color.text,
		UDim2.new(1, -44, 0, 18),
		UDim2.fromOffset(10, 8)
	)
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, -20, 0, 10)
	track.Position = UDim2.fromOffset(10, 34)
	track.BackgroundColor3 = Ui.color.stroke
	track.BackgroundTransparency = 0.7
	track.BorderSizePixel = 0
	Ui.corner(track, UDim.new(1, 0))
	track.Parent = panel
	local bar = Instance.new("Frame")
	bar.Name = "Fill"
	bar.Size = UDim2.fromScale(0, 1)
	bar.BackgroundColor3 = Ui.color.accent
	bar.BorderSizePixel = 0
	Ui.corner(bar, UDim.new(1, 0))
	bar.Parent = track
	fill = bar
	local cap = Ui.keycap(panel, "Key", Input.specialKey(), 20)
	cap.AnchorPoint = Vector2.new(1, 0)
	cap.Position = UDim2.new(1, -8, 0, 6)
	keyCap = cap
end

local function step(dt: number)
	local character = myCharacter()
	local special = mySpecial()
	local now = Timing.clock()
	-- The meter
	local value = meter()
	shownMeter += (value - shownMeter) * Spring.alpha(10, dt)
	local ready = value >= 1
	local color = if special then special.color else Ui.color.accent
	local breathing = 0.5 + 0.5 * math.sin(os.clock() * 5)
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(shownMeter, 0, 1), 1)
		fill.BackgroundColor3 = color
	end
	if nameLabel and special then
		local name = string.upper(special.name)
		if nameLabel.Text ~= name then
			nameLabel.Text = name
		end
	end
	if keyCap then
		keyCap.Visible = ready
	end
	if chipStroke then
		chipStroke.Color = if ready then color else Ui.color.stroke
		chipStroke.Transparency = if ready then 0.1 + 0.4 * breathing else 0.5
		chipStroke.Thickness = if ready then 2.5 else 1.5
	end
	if touchButton then
		-- (of no use in the hub, and the stalls' buttons want the room)
		touchButton.Visible = character == nil or character:GetAttribute("InHub") ~= true
		local text = if ready then "GO!" else `{math.floor(value * 100)}%`
		if touchButton.Text ~= text then
			touchButton.Text = text
		end
	end
	-- A Moray's roll spins it
	local rolling = numberAttribute(character, "Rolling") > now
	spin = if rolling then spin + SPIN_RATE * dt else 0
	SwimController.spin = spin
	-- A Moray has hold of us: dragged to its mouth, and we can't swim away
	local by = if character then character:GetAttribute("RolledBy") else nil
	local point: Vector3? = nil
	if typeof(by) == "number" then
		local other = Players:GetPlayerByUserId(by)
		local otherCharacter = other and other.Character
		local otherRoot = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
		if otherCharacter and otherRoot and otherRoot:IsA("BasePart") then
			point = otherRoot.CFrame:PointToWorldSpace(Size.mouthOffset(lengthOf(otherCharacter)))
		end
	end
	SwimController.holdBy(HOLD_SOURCE, point)
	-- A shark's frenzy reddens its own water
	local frenzied = numberAttribute(character, "FrenzyUntil") > now
	tintAlpha += ((if frenzied then 1 else 0) - tintAlpha) * Spring.alpha(5, dt)
	if tint then
		tint.Enabled = tintAlpha > 0.01
		tint.TintColor = Color3.new(1, 1 - 0.2 * tintAlpha, 1 - 0.24 * tintAlpha)
	end
end

function SpecialController.start()
	task.spawn(buildChip)
	Input.special:connect(press)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonL3 then
			Input.special:fire()
		end
	end)
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "FrenzyTint"
	effect.Enabled = false
	effect.Parent = game:GetService("Lighting")
	tint = effect
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	local function onMine(character: Model)
		character:GetAttributeChangedSignal("SpecialAt"):Connect(function()
			startMine(character)
		end)
	end
	Players.LocalPlayer.CharacterAdded:Connect(onMine)
	if Players.LocalPlayer.Character then
		onMine(Players.LocalPlayer.Character)
	end
	RunService.RenderStepped:Connect(step)
end

return SpecialController
