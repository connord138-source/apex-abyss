--!strict
-- The dive HUD, kept minimal: level and stage (top left), the Haul with its growth
-- bar and a hint (bottom center), boost and health bars, a depth gauge (right),
-- toasts, the bank celebration, the eaten screen, "+kg" pops where prey are
-- eaten, and touch buttons on phones. Every number eases and every panel springs
-- in; nothing pops.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Size = require(ReplicatedStorage.Shared.Size)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Spring = require(script.Parent.Parent.Spring)
local Ui = require(script.Parent.Parent.Ui)
local HuntController = require(script.Parent.HuntController)
local SchoolController = require(script.Parent.SchoolController)
local SwimController = require(script.Parent.SwimController)

local World = Config.World
local hunt = Config.Tuning.hunt

local HudController = {}

local gui: ScreenGui
local levelText: TextLabel
local stageText: TextLabel
local levelMassText: TextLabel
local levelFill: Frame
local safeChip: Frame
local haulValue: TextLabel
local haulScale: UIScale
local haulFill: Frame
local hintText: TextLabel
local boostTrack: Frame
local boostFill: Frame
local healthTrack: Frame
local healthFill: Frame
local depthText: TextLabel
local depthMarker: Frame
local toastList: Frame
local popLayer: Frame
local flash: Frame

local shownHaul, haulVelocity = 0, 0
local pulse, pulseVelocity = 1, 0
local growth, growthVelocity = 0, 0
local boostAlpha = 0
local healthAlpha = 0
local lastHaul = 0

local function state(): { [string]: any }
	return ClientState.current or {}
end

local function buildLevelCard()
	local card = Ui.panel(gui, "Level", UDim2.fromOffset(232, 70), UDim2.fromOffset(18, 66))
	levelText = Ui.label(
		card,
		"Level",
		"LV 1",
		Ui.FONT_HEAVY,
		26,
		Ui.color.text,
		UDim2.fromOffset(110, 30),
		UDim2.fromOffset(14, 8)
	)
	stageText = Ui.label(
		card,
		"Stage",
		"FRY",
		Ui.FONT_BOLD,
		14,
		Ui.color.accent,
		UDim2.fromOffset(110, 18),
		UDim2.fromOffset(120, 15)
	)
	stageText.TextXAlignment = Enum.TextXAlignment.Right
	levelMassText = Ui.label(
		card,
		"Mass",
		"",
		Ui.FONT,
		13,
		Ui.color.muted,
		UDim2.fromOffset(204, 16),
		UDim2.fromOffset(14, 38)
	)
	local _, fill =
		Ui.bar(card, "Progress", UDim2.fromOffset(204, 5), UDim2.fromOffset(14, 56), Ui.color.accent)
	levelFill = fill

	safeChip = Ui.panel(gui, "Safe", UDim2.fromOffset(118, 28), UDim2.fromOffset(18, 144))
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(8, 8)
	dot.Position = UDim2.new(0, 12, 0.5, -4)
	dot.BackgroundColor3 = Ui.color.safe
	dot.BorderSizePixel = 0
	Ui.corner(dot, UDim.new(1, 0))
	dot.Parent = safeChip
	Ui.label(
		safeChip,
		"Text",
		"SAFE ZONE",
		Ui.FONT_BOLD,
		13,
		Ui.color.safe,
		UDim2.fromOffset(90, 28),
		UDim2.fromOffset(26, 0)
	).TextYAlignment =
		Enum.TextYAlignment.Center
end

local function buildHaulCard()
	local card =
		Ui.panel(gui, "Haul", UDim2.fromOffset(320, 92), UDim2.new(0.5, 0, 1, -22), Vector2.new(0.5, 1))
	Ui.label(
		card,
		"Title",
		"HAUL",
		Ui.FONT_BOLD,
		13,
		Ui.color.muted,
		UDim2.fromOffset(100, 16),
		UDim2.fromOffset(16, 10)
	)
	haulValue = Ui.label(
		card,
		"Value",
		"0.0 kg",
		Ui.FONT_HEAVY,
		30,
		Ui.color.haul,
		UDim2.fromOffset(288, 32),
		UDim2.fromOffset(16, 24)
	)
	haulScale = Instance.new("UIScale")
	haulScale.Parent = haulValue
	local _, fill = Ui.bar(card, "Growth", UDim2.fromOffset(288, 6), UDim2.fromOffset(16, 60), Ui.color.haul)
	haulFill = fill
	hintText = Ui.label(
		card,
		"Hint",
		"",
		Ui.FONT,
		13,
		Ui.color.muted,
		UDim2.fromOffset(288, 16),
		UDim2.fromOffset(16, 70)
	)

	local track, boost =
		Ui.bar(gui, "Boost", UDim2.fromOffset(320, 4), UDim2.new(0.5, -160, 1, -122), Ui.color.accent)
	boostTrack, boostFill = track, boost
	local healthBar, health =
		Ui.bar(gui, "Health", UDim2.fromOffset(320, 6), UDim2.new(0.5, -160, 1, -134), Ui.color.danger)
	healthTrack, healthFill = healthBar, health
end

local function buildDepthGauge()
	local card =
		Ui.panel(gui, "Depth", UDim2.fromOffset(70, 210), UDim2.new(1, -18, 0.5, 0), Vector2.new(1, 0.5))
	Ui.label(
		card,
		"Title",
		"DEPTH",
		Ui.FONT_BOLD,
		11,
		Ui.color.muted,
		UDim2.new(1, 0, 0, 14),
		UDim2.fromOffset(0, 10)
	).TextXAlignment =
		Enum.TextXAlignment.Center
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.fromOffset(4, 140)
	track.Position = UDim2.new(0.5, -2, 0, 30)
	track.BackgroundColor3 = Ui.color.track
	track.BorderSizePixel = 0
	Ui.corner(track, UDim.new(1, 0))
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(120, 230, 250), Color3.fromRGB(10, 30, 70))
	gradient.Parent = track
	track.BackgroundColor3 = Color3.new(1, 1, 1)
	track.Parent = card
	depthMarker = Instance.new("Frame")
	depthMarker.Name = "Marker"
	depthMarker.Size = UDim2.fromOffset(18, 4)
	depthMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	depthMarker.Position = UDim2.fromScale(0.5, 0)
	depthMarker.BackgroundColor3 = Ui.color.text
	depthMarker.BorderSizePixel = 0
	Ui.corner(depthMarker, UDim.new(1, 0))
	depthMarker.Parent = track
	depthText = Ui.label(
		card,
		"Value",
		"0 m",
		Ui.FONT_HEAVY,
		16,
		Ui.color.text,
		UDim2.new(1, 0, 0, 20),
		UDim2.fromOffset(0, 180)
	)
	depthText.TextXAlignment = Enum.TextXAlignment.Center
end

local function toast(text: string, kind: string)
	local color = if kind == "good"
		then Ui.color.safe
		elseif kind == "bad" then Ui.color.danger
		elseif kind == "rare" then Ui.color.haul
		else Ui.color.text
	local item = Ui.panel(toastList, "Toast", UDim2.fromOffset(360, 36), UDim2.new())
	item.BackgroundTransparency = 1
	local label = Ui.label(item, "Text", text, Ui.FONT_BOLD, 16, color, UDim2.fromScale(1, 1))
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTransparency = 1
	local stroke = item:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 1
	end
	Ui.tween(item, 0.25, { BackgroundTransparency = Ui.PANEL_TRANSPARENCY })
	Ui.tween(label, 0.25, { TextTransparency = 0 })
	task.delay(3, function()
		Ui.tween(item, 0.4, { BackgroundTransparency = 1 })
		Ui.tween(label, 0.4, { TextTransparency = 1 })
		task.wait(0.45)
		item:Destroy()
	end)
end

-- The bank celebration: "+12.4 kg BANKED", and the new level if there is one.
local function celebrate(summary: { [string]: any })
	local holder = Instance.new("Frame")
	holder.Name = "Banked"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.36)
	holder.Size = UDim2.fromOffset(600, 110)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = holder
	local amount = typeof(summary.amount) == "number" and summary.amount or 0
	local title = Ui.label(
		holder,
		"Title",
		`+{Format.mass(amount)} BANKED`,
		Ui.FONT_HEAVY,
		46,
		Ui.color.haul,
		UDim2.new(1, 0, 0, 52)
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextStrokeTransparency = 0.55
	local level = summary.level
	local before = summary.levelBefore
	local sub = if typeof(level) == "number"
			and typeof(before) == "number"
			and level > before
		then `LEVEL {level} · {string.upper(tostring(summary.stage))}`
		else "Your fish keeps this size now"
	local line = Ui.label(
		holder,
		"Sub",
		sub,
		Ui.FONT_BOLD,
		22,
		Ui.color.text,
		UDim2.new(1, 0, 0, 28),
		UDim2.fromOffset(0, 56)
	)
	line.TextXAlignment = Enum.TextXAlignment.Center
	line.TextStrokeTransparency = 0.6
	holder.Parent = gui
	Ui.tween(scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2.4, function()
		Ui.tween(title, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
		Ui.tween(line, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
		Ui.tween(scale, 0.5, { Scale = 1.08 })
		task.wait(0.55)
		holder:Destroy()
	end)
end

-- The eaten screen, with a countdown to respawning in the den.
local function eatenScreen(summary: { [string]: any })
	local overlay = Instance.new("Frame")
	overlay.Name = "Eaten"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(4, 10, 18)
	overlay.BackgroundTransparency = 1
	overlay.ZIndex = 20
	overlay.Parent = gui
	local title = Ui.label(
		overlay,
		"Title",
		"EATEN",
		Ui.FONT_HEAVY,
		64,
		Ui.color.danger,
		UDim2.new(1, 0, 0, 70),
		UDim2.new(0, 0, 0.36, 0)
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.ZIndex = 21
	local by = typeof(summary.by) == "string" and summary.by or "a bigger fish"
	local lost = typeof(summary.lost) == "number" and summary.lost or 0
	local detail = if lost > 0 then `by {by} · lost {Format.mass(lost)} of Haul` else `by {by}`
	local line = Ui.label(
		overlay,
		"Detail",
		detail,
		Ui.FONT_BOLD,
		22,
		Ui.color.text,
		UDim2.new(1, 0, 0, 28),
		UDim2.new(0, 0, 0.36, 76)
	)
	line.TextXAlignment = Enum.TextXAlignment.Center
	line.ZIndex = 21
	local countdown = Ui.label(
		overlay,
		"Countdown",
		"",
		Ui.FONT,
		18,
		Ui.color.muted,
		UDim2.new(1, 0, 0, 24),
		UDim2.new(0, 0, 0.36, 112)
	)
	countdown.TextXAlignment = Enum.TextXAlignment.Center
	countdown.ZIndex = 21
	Ui.tween(overlay, 0.35, { BackgroundTransparency = 0.35 })
	local seconds = typeof(summary.respawn) == "number" and summary.respawn or hunt.respawnSeconds
	task.spawn(function()
		for left = math.ceil(seconds), 1, -1 do
			countdown.Text = `Back in your den in {left}…`
			task.wait(1)
		end
		Ui.tween(overlay, 0.4, { BackgroundTransparency = 1 })
		Ui.tween(title, 0.4, { TextTransparency = 1 })
		Ui.tween(line, 0.4, { TextTransparency = 1 })
		Ui.tween(countdown, 0.4, { TextTransparency = 1 })
		task.wait(0.45)
		overlay:Destroy()
	end)
end

-- "+0.3" floating up from where a prey was eaten.
local function pop(mass: number, position: Vector3)
	local camera = workspace.CurrentCamera
	local point, visible = camera:WorldToViewportPoint(position)
	if not visible then
		return
	end
	local scale = Ui.scaleOf(gui)
	local label = Ui.label(
		popLayer,
		"Pop",
		`+{if mass < 10 then string.format("%.1f", mass) else tostring(math.floor(mass))}`,
		Ui.FONT_HEAVY,
		20,
		Ui.color.haul,
		UDim2.fromOffset(80, 24),
		UDim2.fromOffset(point.X / scale - 40, point.Y / scale - 12)
	)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextStrokeTransparency = 0.6
	Ui.tween(label, 0.7, {
		Position = label.Position - UDim2.fromOffset(0, 36),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	task.delay(0.72, function()
		label:Destroy()
	end)
end

local function touchButton(name: string, text: string, size: number, position: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.FontFace = Ui.FONT_HEAVY
	button.TextSize = math.floor(size * 0.22)
	button.TextColor3 = Ui.color.text
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(size, size)
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = position
	button.BackgroundColor3 = Ui.color.panel
	button.BackgroundTransparency = 0.35
	Ui.corner(button, UDim.new(1, 0))
	Ui.stroke(button, Ui.color.stroke, 0.5, 1.5)
	button.Parent = gui
	return button
end

local function holdButton(button: TextButton, inputName: string)
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			Input.setTouchButton(inputName, true)
			button.BackgroundTransparency = 0.1
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			Input.setTouchButton(inputName, false)
			button.BackgroundTransparency = 0.35
		end
	end)
end

local function buildTouchButtons()
	local bite = touchButton("Bite", "BITE", 92, UDim2.new(1, -86, 1, -110))
	bite.Activated:Connect(function()
		Input.bite:fire()
	end)
	holdButton(touchButton("Boost", "BOOST", 70, UDim2.new(1, -190, 1, -72)), "Boost")
	holdButton(touchButton("Up", "UP", 52, UDim2.new(1, -60, 1, -220)), "Up")
	holdButton(touchButton("Down", "DOWN", 52, UDim2.new(1, -124, 1, -186)), "Down")
end

local function showControlsHint()
	local text = if Input.isTouch()
		then "Stick to swim · drag to look · BITE and BOOST on the right"
		elseif
			Input.isGamepad()
		then "Left stick swim · right stick look · RT boost · RB bite · A/B up and down"
		else "Mouse to look · WASD swim · Shift boost · Click bite · Space/Ctrl up and down · hold Alt for the cursor"
	local label = Ui.label(
		gui,
		"Controls",
		text,
		Ui.FONT_SEMI,
		14,
		Ui.color.muted,
		UDim2.fromOffset(700, 18),
		UDim2.new(0, 18, 1, -36)
	)
	label.TextStrokeTransparency = 0.75
	task.delay(14, function()
		Ui.tween(label, 1, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.wait(1.1)
		label:Destroy()
	end)
end

local function hintFor(s: { [string]: any }): string
	local haul = s.haul or 0
	if haul <= 0 then
		return if s.inHub
			then "Swim out a tunnel or up through the roof to hunt"
			else "Eat smaller fish to grow"
	elseif s.maxed then
		return "MAX SIZE · bank your Haul to keep growing"
	elseif s.inHub then
		return "Swim into your den's glowing pool to bank"
	end
	return "Swim home to bank it, or lose it if you're eaten"
end

local function onState(s: { [string]: any })
	local level = s.level or 1
	levelText.Text = `LV {level}`
	stageText.Text = string.upper(s.stage or "Fry")
	local mass = s.mass or 1
	local from, to = s.levelMass or 1, s.nextLevelMass or 2
	levelMassText.Text = `{Format.mass(mass)} banked`
	Ui.tween(
		levelFill,
		0.5,
		{ Size = UDim2.fromScale(math.clamp((mass - from) / math.max(to - from, 1e-6), 0, 1), 1) }
	)
	hintText.Text = hintFor(s)
	local haul = s.haul or 0
	if haul > lastHaul then
		pulseVelocity += 6
	end
	lastHaul = haul
end

local function step(dt: number)
	local s = state()
	local haul = s.haul or 0
	shownHaul, haulVelocity = Spring.number(shownHaul, haulVelocity, haul, 14, dt)
	if haul == 0 and shownHaul < 0.05 then
		shownHaul = 0
	end
	haulValue.Text = Format.mass(math.max(shownHaul, 0))
	pulse, pulseVelocity = Spring.number(pulse, pulseVelocity, 1, 18, dt)
	haulScale.Scale = math.max(pulse, 0.8)

	local mass = s.mass or 1
	local cap = Config.Tuning.size.haulLengthCap ^ 3
	local live = Size.liveMass(mass, haul)
	local wantGrowth = math.clamp((live - mass) / (mass * (cap - 1)), 0, 1)
	growth, growthVelocity = Spring.number(growth, growthVelocity, wantGrowth, 9, dt)
	haulFill.Size = UDim2.fromScale(math.clamp(growth, 0, 1), 1)

	local character = SwimController.character()
	safeChip.Visible = s.inHub == true or (character ~= nil and HuntController.isSafe(character))

	-- Boost: shown while it isn't full
	local bar = SwimController.boostBar
	boostAlpha += ((if bar < 0.999 or SwimController.boosting then 1 else 0) - boostAlpha) * Spring.alpha(
		6,
		dt
	)
	boostFill.Size = UDim2.fromScale(bar, 1)
	boostTrack.BackgroundTransparency = 1 - 0.85 * boostAlpha
	boostFill.BackgroundTransparency = 1 - boostAlpha
	boostFill.BackgroundColor3 = if bar < Config.Tuning.swim.boostMinimum and not SwimController.boosting
		then Ui.color.muted
		else Ui.color.accent

	-- Health: shown while hurt
	local health = if character then character:GetAttribute("Health") else nil
	local fraction = if typeof(health) == "number" then math.clamp(health / hunt.health, 0, 1) else 1
	healthAlpha += ((if fraction < 0.999 then 1 else 0) - healthAlpha) * Spring.alpha(6, dt)
	healthFill.Size = UDim2.fromScale(fraction, 1)
	healthTrack.BackgroundTransparency = 1 - 0.85 * healthAlpha
	healthFill.BackgroundTransparency = 1 - healthAlpha

	-- Depth: studs below the surface
	local y = workspace.CurrentCamera.Focus.Position.Y
	local root = SwimController.root()
	if root then
		y = root.Position.Y
	end
	local below = World.surfaceY - y
	depthText.Text = Format.depth(below)
	local span = World.surfaceY - World.trench.floorY
	depthMarker.Position = UDim2.fromScale(0.5, math.clamp(below / span, 0, 1))
end

function HudController.start()
	-- Roblox's own health bar, backpack and emote wheel don't belong in a fish game
	for _, coreGui in { Enum.CoreGuiType.Health, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.EmotesMenu } do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(coreGui, false)
		end)
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.screen("Hud", playerGui, 5)
	buildLevelCard()
	buildHaulCard()
	buildDepthGauge()

	toastList = Instance.new("Frame")
	toastList.Name = "Toasts"
	toastList.BackgroundTransparency = 1
	toastList.AnchorPoint = Vector2.new(0.5, 0)
	toastList.Position = UDim2.new(0.5, 0, 0, 70)
	toastList.Size = UDim2.fromOffset(360, 200)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = toastList
	toastList.Parent = gui

	popLayer = Instance.new("Frame")
	popLayer.Name = "Pops"
	popLayer.BackgroundTransparency = 1
	popLayer.Size = UDim2.fromScale(1, 1)
	popLayer.Parent = gui

	flash = Instance.new("Frame")
	flash.Name = "HitFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Ui.color.danger
	flash.BackgroundTransparency = 1
	flash.ZIndex = 10
	local vignette = Instance.new("UIGradient")
	vignette.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.25, 0.85),
		NumberSequenceKeypoint.new(0.75, 0.85),
		NumberSequenceKeypoint.new(1, 0),
	})
	vignette.Parent = flash
	flash.Parent = gui

	if Input.isTouch() then
		buildTouchButtons()
	end

	ClientState.changed:connect(onState)
	if ClientState.current then
		onState(ClientState.current)
	end
	SchoolController.ate:connect(function(_preyId: string, mass: number, position: Vector3)
		pop(mass, position)
	end)
	HuntController.bitten:connect(function()
		flash.BackgroundTransparency = 0.45
		Ui.tween(flash, 0.6, { BackgroundTransparency = 1 })
	end)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local notify = remotes:WaitForChild("Notify") :: RemoteEvent
	notify.OnClientEvent:Connect(toast)
	local banked = remotes:WaitForChild("Banked") :: RemoteEvent
	banked.OnClientEvent:Connect(celebrate)
	local eaten = remotes:WaitForChild("Eaten") :: RemoteEvent
	eaten.OnClientEvent:Connect(eatenScreen)

	local hinted = false
	SwimController.spawned:connect(function()
		if not hinted then
			hinted = true
			showControlsHint()
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return HudController
