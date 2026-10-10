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
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Sfx = require(script.Parent.Parent.Sfx)
local Format = require(ReplicatedStorage.Shared.Format)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Size = require(ReplicatedStorage.Shared.Size)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Spring = require(script.Parent.Parent.Spring)
local Ui = require(script.Parent.Parent.Ui)
local ForageController = require(script.Parent.ForageController)
local HuntController = require(script.Parent.HuntController)
local PredatorController = require(script.Parent.PredatorController)
local SchoolController = require(script.Parent.SchoolController)
local ShellController = require(script.Parent.ShellController)
local StartController = require(script.Parent.StartController)
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
local safeText: TextLabel
local safeDot: Frame
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
local toastCount = 0
local popLayer: Frame
local flash: Frame

local shownHaul, haulVelocity = 0, 0
local pulse, pulseVelocity = 1, 0
local growth, growthVelocity = 0, 0
local boostAlpha = 0
local zoneSafe: boolean? = nil -- the side of the safe-zone edge we last announced
local zoneCandidate: boolean? = nil
local zoneSince = 0
local healthAlpha = 0
local lastHaul = 0

local function state(): { [string]: any }
	return ClientState.current or {}
end

-- What a Haul gain is multiplied by right now (×2 Mass, Server Frenzy), for the pops
local function growthNow(): number
	local frenzy = if (workspace:GetAttribute("FrenzyUntil") or 0) > workspace:GetServerTimeNow()
		then workspace:GetAttribute("Frenzy") or 1
		else 1
	return (state().massMultiplier or 1) * (if typeof(frenzy) == "number" then frenzy else 1)
end

local function buildLevelCard()
	local card = Ui.panel(gui, "Level", UDim2.fromOffset(232, 70), UDim2.fromOffset(18, 66))
	Ui.belowTopBar(gui, card, 66)
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
		UDim2.fromOffset(130, 18),
		UDim2.fromOffset(90, 15)
	)
	stageText.TextXAlignment = Enum.TextXAlignment.Right
	-- Long names ("MORAY EEL · JUVENILE") shrink to fit
	stageText.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = 14
	fit.Parent = stageText
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

	safeChip = Ui.panel(gui, "Safe", UDim2.fromOffset(140, 28), UDim2.new(0.5, 0, 0, 16), Vector2.new(0.5, 0))
	safeDot = Instance.new("Frame")
	safeDot.Size = UDim2.fromOffset(8, 8)
	safeDot.Position = UDim2.new(0, 12, 0.5, -4)
	safeDot.BackgroundColor3 = Ui.color.safe
	safeDot.BorderSizePixel = 0
	Ui.corner(safeDot, UDim.new(1, 0))
	safeDot.Parent = safeChip
	safeText = Ui.label(
		safeChip,
		"Text",
		"SAFE ZONE",
		Ui.FONT_BOLD,
		13,
		Ui.color.safe,
		UDim2.fromOffset(110, 28),
		UDim2.fromOffset(26, 0)
	)
	safeText.TextYAlignment = Enum.TextYAlignment.Center
end

-- A banner when the fish crosses the safe zone's edge (the dens and the vendor
-- plaza): leaving warns that other fish can eat you now; coming back says you're safe.
local function zoneBanner(leaving: boolean)
	local old = gui:FindFirstChild("ZoneBanner")
	if old then
		old:Destroy()
	end
	-- The controls hint shares this spot; the banner takes over
	local controls = gui:FindFirstChild("Controls")
	if controls then
		controls:Destroy()
	end
	local color = if leaving then Ui.color.danger else Ui.color.safe
	local holder = Instance.new("Frame")
	holder.Name = "ZoneBanner"
	-- Below the boss bar while a boss is up
	local top = math.max(56, Ui.bossBottom() + 10)
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, top - 16)
	holder.Size = UDim2.fromOffset(560, 70)
	holder.BackgroundTransparency = 1
	local title = Ui.label(
		holder,
		"Title",
		if leaving then "LEAVING THE SAFE ZONE" else "SAFE ZONE",
		Ui.FONT_HEAVY,
		30,
		color,
		UDim2.new(1, 0, 0, 34)
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextStrokeTransparency = 0.5
	title.TextTransparency = 1
	local protection = Config.Tuning.hunt.leaveHubProtection
	local sub = Ui.label(
		holder,
		"Sub",
		if leaving
			then `Other fish can eat you out here · protected for {protection}s`
			else "Nobody can eat you in the dens or the market",
		Ui.FONT_BOLD,
		17,
		Ui.color.text,
		UDim2.new(1, 0, 0, 22),
		UDim2.fromOffset(0, 36)
	)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.TextStrokeTransparency = 0.6
	sub.TextTransparency = 1
	holder.Parent = gui
	Ui.tween(holder, 0.35, { Position = UDim2.new(0.5, 0, 0, top) }, Enum.EasingStyle.Back)
	Ui.tween(title, 0.25, { TextTransparency = 0 })
	Ui.tween(sub, 0.25, { TextTransparency = 0 })
	task.delay(2.8, function()
		if holder.Parent == nil then
			return
		end
		Ui.tween(title, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
		Ui.tween(sub, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.wait(0.55)
		holder:Destroy()
	end)
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
	local item = Ui.panel(toastList, "Toast", UDim2.fromOffset(0, 36), UDim2.new())
	toastCount += 1
	item.LayoutOrder = toastCount -- the newest sits lowest, nearest the Haul card
	item.BackgroundTransparency = 1
	-- The pill grows with its text (a long one once ran out of a fixed 360 px pill)
	item.AutomaticSize = Enum.AutomaticSize.X
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingRight = UDim.new(0, 18)
	padding.Parent = item
	local label = Ui.label(item, "Text", text, Ui.FONT_BOLD, 16, color, UDim2.fromOffset(0, 36))
	label.AutomaticSize = Enum.AutomaticSize.X
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
	local leveled = typeof(summary.level) == "number"
		and typeof(summary.levelBefore) == "number"
		and summary.level > summary.levelBefore
	Sfx.play("Bank", { volume = 0.7 })
	if leveled then
		task.delay(0.45, function()
			Sfx.play("LevelUp", { volume = 0.75 })
		end)
	end
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
		if summary.doubled then `HAUL DOUBLED · +{Format.mass(amount)}` else `+{Format.mass(amount)} BANKED`,
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
	if typeof(summary.coral) == "number" and summary.coral > 0 then
		sub ..= `  ·  +{Ui.number(summary.coral)} coral`
	end
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

-- A toast from the client itself (the Shop's notes)
function HudController.toast(text: string, kind: string?)
	if toastList then
		toast(text, kind or "info")
	end
end

-- The eaten screen, with a countdown to respawning in the den.
local function eatenScreen(summary: { [string]: any })
	Sfx.play("Eaten", { volume = 0.9 })
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
	local saved = typeof(summary.saved) == "number" and summary.saved or 0
	local detail = if saved > 0
		then `by {by} · Second Chance kept your {Format.mass(saved)} Haul`
		elseif lost > 0 then `by {by} · lost {Format.mass(lost)} of Haul`
		else `by {by}`
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

-- "+0.3" floating up from where a prey was eaten (or "+1 SHELL").
local function pop(text: string, color: Color3, position: Vector3)
	local camera = workspace.CurrentCamera
	local point, visible = camera:WorldToViewportPoint(position)
	if not visible then
		return
	end
	local scale = Ui.scaleOf(gui)
	local label = Ui.label(
		popLayer,
		"Pop",
		text,
		Ui.FONT_HEAVY,
		20,
		color,
		UDim2.fromOffset(120, 24),
		UDim2.fromOffset(point.X / scale - 60, point.Y / scale - 12)
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

-- The swim stick on phones (owner, 2026-10-07: one stick): touch anywhere in the
-- lower left and push up to swim (further = faster), sideways to turn, down to back
-- up; dragging anywhere else aims up and down. The ring appears under the thumb, so
-- it's always where the thumb already is.
local function buildThumbstick()
	local RADIUS = 56
	local zone = Instance.new("Frame")
	zone.Name = "SwimStick"
	zone.BackgroundTransparency = 1
	zone.Active = true -- touches that start here don't also turn the camera
	zone.AnchorPoint = Vector2.new(0, 1)
	zone.Position = UDim2.fromScale(0, 1)
	zone.Size = UDim2.fromScale(0.4, 0.6)
	zone.Parent = gui
	-- The ring is drawn on its own layer above the HUD's panels (a thumb near the
	-- tutorial panel put the ring behind it); the zone that takes the touches stays
	-- in the HUD, under the HUD's buttons
	local layer = Ui.screen("SwimStickRing", gui.Parent :: Instance, 8)
	local overlay = Instance.new("Frame")
	overlay.Name = "Zone"
	overlay.BackgroundTransparency = 1
	overlay.AnchorPoint = zone.AnchorPoint
	overlay.Position = zone.Position
	overlay.Size = zone.Size
	overlay.Parent = layer
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Size = UDim2.fromOffset(RADIUS * 2, RADIUS * 2)
	ring.BackgroundColor3 = Ui.color.panel
	ring.BackgroundTransparency = 0.55
	Ui.corner(ring, UDim.new(1, 0))
	Ui.stroke(ring, Ui.color.stroke, 0.5, 1.5)
	ring.Parent = overlay
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(48, 48)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.BackgroundColor3 = Ui.color.text
	knob.BackgroundTransparency = 0.35
	Ui.corner(knob, UDim.new(1, 0))
	knob.Parent = ring
	-- Resting spot, faded, so new players see where to put their thumb (low enough
	-- to clear the tutorial panel once the top-left column moves below the top bar)
	local rest = UDim2.new(0, 110, 1, -90)
	ring.Position = rest
	ring.BackgroundTransparency = 0.75

	local active: InputObject? = nil
	local start = Vector2.zero
	local function screenPoint(input: InputObject): Vector2
		-- Touch positions and AbsolutePosition both count from below the top bar,
		-- even in a ScreenGui that ignores it (adding the inset drew the ring a
		-- top bar's height under the thumb, playtest 2026-10-07)
		return Vector2.new(input.Position.X, input.Position.Y)
	end
	zone.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch or active ~= nil then
			return
		end
		active = input
		start = screenPoint(input)
		local scale = Ui.scaleOf(gui)
		local localPoint = (start - zone.AbsolutePosition) / scale
		ring.Position = UDim2.fromOffset(localPoint.X, localPoint.Y)
		ring.BackgroundTransparency = 0.55
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input ~= active then
			return
		end
		local scale = Ui.scaleOf(gui)
		local delta = (screenPoint(input) - start) / scale
		if delta.Magnitude > RADIUS then
			delta = delta.Unit * RADIUS
		end
		knob.Position = UDim2.new(0.5, delta.X, 0.5, delta.Y)
		Input.setTouchMove(delta / RADIUS)
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input ~= active then
			return
		end
		active = nil
		Input.setTouchMove(Vector2.zero)
		knob.Position = UDim2.fromScale(0.5, 0.5)
		ring.Position = rest
		ring.BackgroundTransparency = 0.75
	end)
end

local function buildTouchButtons()
	buildThumbstick()
	local bite = touchButton("Bite", "BITE", 92, UDim2.new(1, -86, 1, -110))
	bite.Activated:Connect(function()
		Input.bite:fire()
	end)
	local dash = touchButton("Dash", "DASH", 70, UDim2.new(1, -190, 1, -72))
	dash.Activated:Connect(function()
		Input.ability:fire()
	end)
end

local function showControlsHint()
	local text = if Input.isTouch()
		then "Left stick: push up to swim, sideways to turn · drag to aim · swim into smaller fish to eat · BITE for fish your size"
		elseif
			Input.isGamepad()
		then "Left stick: up to swim, sideways to turn · right stick aims · swim into smaller fish to eat · RB bites fish your size · RT dash · LB heal · Y at a stall"
		else "Mouse to look · WASD swim · swim into smaller fish to eat · Click or F bites fish your size · Shift dash · Space/Ctrl up/down · E at a stall · H heal"
	local label = Ui.label(gui, "Controls", text, Ui.FONT_SEMI, 14, Ui.color.muted, UDim2.fromOffset(800, 18))
	-- Top centre under the safe-zone pill, and below the boss bar or the boss
	-- countdown while one is up (the countdown sits at the same spot and covered it,
	-- playtest 2026-10-09). Bottom left it ran into the Haul card: on phones
	-- (playtest 2026-10-07), and on PC at 1280×720 once it named the bite key
	-- (2026-10-09).
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.TextXAlignment = Enum.TextXAlignment.Center
	if Input.isTouch() then
		-- Phones: wrapped to two lines
		label.Size = UDim2.fromOffset(520, 38)
		label.TextWrapped = true
	end
	task.spawn(function()
		while label.Parent do
			label.Position = UDim2.new(0.5, 0, 0, math.max(52, Ui.bossBottom() + 6))
			task.wait(0.25)
		end
	end)
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
			else "Swim into smaller fish to swallow them"
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
	stageText.Text = `{string.upper(s.speciesName or "Nibbler")} · {string.upper(s.stage or "Fry")}`
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

	-- The safe zone: checked here every frame so the warning is instant (the server
	-- decides for real). A short settle time stops it flickering on the edge.
	local character = SwimController.character()
	local root = SwimController.root()
	if root then
		local inside = Layout.inHub(root.Position)
		if zoneSafe == nil then
			zoneSafe, zoneCandidate = inside, inside -- spawning in the den: no banner
		elseif inside ~= zoneCandidate then
			zoneCandidate, zoneSince = inside, os.clock()
		elseif inside ~= zoneSafe and os.clock() - zoneSince > 0.25 then
			zoneSafe = inside
			zoneBanner(not inside)
		end
	end
	local safeUntil = if character then character:GetAttribute("SafeUntil") else nil
	local protectedFor = if typeof(safeUntil) == "number" then safeUntil - Timing.clock() else 0
	if zoneSafe then
		safeChip.Visible = true
		safeText.Text = "SAFE ZONE"
		safeText.TextColor3 = Ui.color.safe
		safeDot.BackgroundColor3 = Ui.color.safe
	elseif protectedFor > 0 then
		safeChip.Visible = true
		safeText.Text = `PROTECTED {math.ceil(protectedFor)}s`
		safeText.TextColor3 = Ui.color.accent
		safeDot.BackgroundColor3 = Ui.color.accent
	else
		safeChip.Visible = false
	end

	-- The Dash: its bar refills while it recharges, then fades out when ready
	local bar = SwimController.dashCharge
	boostAlpha += ((if bar < 0.999 or SwimController.boosting then 1 else 0) - boostAlpha) * Spring.alpha(
		6,
		dt
	)
	boostFill.Size = UDim2.fromScale(bar, 1)
	boostTrack.BackgroundTransparency = 1 - 0.85 * boostAlpha
	boostFill.BackgroundTransparency = 1 - boostAlpha
	boostFill.BackgroundColor3 = if bar < 0.999 then Ui.color.muted else Ui.color.accent

	-- Health: shown while hurt
	local health = if character then character:GetAttribute("Health") else nil
	local fraction = if typeof(health) == "number" then math.clamp(health / hunt.health, 0, 1) else 1
	healthAlpha += ((if fraction < 0.999 then 1 else 0) - healthAlpha) * Spring.alpha(6, dt)
	healthFill.Size = UDim2.fromScale(fraction, 1)
	healthTrack.BackgroundTransparency = 1 - 0.85 * healthAlpha
	healthFill.BackgroundTransparency = 1 - healthAlpha

	-- Depth: studs below the surface
	local y = if root then root.Position.Y else workspace.CurrentCamera.Focus.Position.Y
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
	-- Above the Haul card, stacking up: the top of the screen belongs to the
	-- safe-zone and biome banners (a toast once sat between a banner's lines). Its
	-- own ScreenGui draws over the menus, so a refusal from a menu button (switching
	-- fish outside the safe zone) is seen rather than hidden behind the window.
	toastList.AnchorPoint = Vector2.new(0.5, 1)
	toastList.Position = UDim2.new(0.5, 0, 1, -130)
	toastList.Size = UDim2.fromOffset(640, 160)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = toastList
	toastList.Parent = Ui.screen("Toasts", playerGui, 12)

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
	SchoolController.ate:connect(function(_preyId: string, eaten: number, position: Vector3, rarity: string?)
		-- A rare fish (Config/Catch) pops its rarity in its colour, with its bigger Haul
		local rare = if rarity then Config.Catch.byId[rarity] else nil
		local mass = eaten * growthNow() * (if rare then rare.haul else 1)
		local amount = `+{if mass < 10 then string.format("%.1f", mass) else tostring(math.floor(mass))}`
		pop(
			if rare then `{string.upper(rare.name)} {amount}` else amount,
			if rare then rare.color else Ui.color.haul,
			position
		)
	end)
	ForageController.ate:connect(function(mass: number, position: Vector3)
		pop(`+{string.format("%.2f", mass * growthNow())}`, Ui.color.haul, position)
	end)
	PredatorController.hit:connect(function(damage: number, position: Vector3)
		pop(`-{math.floor(damage + 0.5)}`, Ui.color.danger, position)
	end)
	ShellController.collected:connect(function(value: number, position: Vector3)
		pop(`+{value} SHELL{if value == 1 then "" else "S"}`, Color3.fromRGB(242, 228, 204), position)
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
			StartController.afterStart(showControlsHint)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return HudController
