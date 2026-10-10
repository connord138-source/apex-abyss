--!strict
-- The Tide Clock on this client (Config/Tides, Shared/Tides; owner, 2026-10-10: the
-- "pull back element"). A chip at the top of the screen names the tide and the
-- time left in it, and counts down to the next Prism Tide when one is within the
-- hour; when the tide turns a banner says what it brings, and the water takes a
-- faint tint of its colour (a Bioluminescent Night dims the sea). The tides are
-- arithmetic on the server's clock, so this needs nothing from the server; the
-- server's `TideChanged` only makes the banner land on time.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TideConfig = require(ReplicatedStorage.Shared.Config.Tides)
local Tides = require(ReplicatedStorage.Shared.Tides)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local OceanController = require(script.Parent.OceanController)
local StartController = require(script.Parent.StartController)

local TideController = {}

local gui: ScreenGui
local chip: Frame
local nameLabel: TextLabel
local timeLabel: TextLabel
local prismLabel: TextLabel
local dot: Frame
local shown = "" -- the tide the chip and the water show
local CHIP_TOP = 8

local function clockText(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", seconds // 3600, (seconds // 60) % 60, seconds % 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function banner(tide: TideConfig.Tide)
	if StartController.isUp() then
		return
	end
	-- A player's own banner (the tutorial's end, a skin unlock) has the spot: wait
	-- for it, and skip this one if the tide turned again meanwhile
	local waited = 0
	while Ui.centreBannerUp() and waited < 8 do
		waited += task.wait(0.25)
	end
	if shown ~= tide.id then
		return
	end
	Sfx.play("Banner", { volume = 0.5, pitch = if tide.id == "Prism" then 1.25 else 0.9 })
	local old = gui:FindFirstChild("TideBanner")
	if old then
		old:Destroy()
	end
	local holder = Instance.new("Frame")
	holder.Name = "TideBanner"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	local height = gui.AbsoluteSize.Y / Ui.scaleOf(gui)
	holder.Position = UDim2.new(0.5, 0, 0, math.max(height * 0.3, Ui.bossBottom() + 70))
	holder.Size = UDim2.fromOffset(640, 72)
	holder.BackgroundTransparency = 1
	local kicker =
		Ui.label(holder, "Kicker", "THE TIDE TURNS", Ui.FONT_BOLD, 15, Ui.color.muted, UDim2.new(1, 0, 0, 18))
	local title = Ui.label(
		holder,
		"Title",
		string.upper(tide.name),
		Ui.FONT_HEAVY,
		36,
		tide.color,
		UDim2.new(1, 0, 0, 40),
		UDim2.fromOffset(0, 16)
	)
	local sub = Ui.label(
		holder,
		"Sub",
		tide.blurb,
		Ui.FONT_BOLD,
		17,
		Ui.color.text,
		UDim2.new(1, 0, 0, 22),
		UDim2.fromOffset(0, 56)
	)
	local labels = { kicker, title, sub }
	for _, label in labels do
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextTransparency = 1
		label.TextStrokeTransparency = 1
	end
	holder.Parent = gui
	for _, label in labels do
		Ui.tween(label, 0.5, { TextTransparency = 0, TextStrokeTransparency = 0.55 })
	end
	task.delay(4, function()
		if holder.Parent == nil then
			return
		end
		for _, label in labels do
			Ui.tween(label, 0.7, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
		task.wait(0.75)
		holder:Destroy()
	end)
end

local function build(playerGui: Instance)
	gui = Ui.screen("Tides", playerGui, 6)
	chip = Ui.panel(
		gui,
		"TideChip",
		UDim2.fromOffset(250, 40),
		UDim2.new(0.5, 0, 0, CHIP_TOP),
		Vector2.new(0.5, 0)
	)
	chip.BackgroundTransparency = 0.25
	dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.fromOffset(10, 10)
	dot.Position = UDim2.fromOffset(14, 15)
	dot.BorderSizePixel = 0
	Ui.corner(dot, UDim.new(1, 0))
	dot.Parent = chip
	nameLabel = Ui.label(
		chip,
		"Name",
		"",
		Ui.FONT_HEAVY,
		15,
		Ui.color.text,
		UDim2.new(1, -110, 0, 20),
		UDim2.fromOffset(32, 4)
	)
	timeLabel = Ui.label(
		chip,
		"Time",
		"",
		Ui.FONT_SEMI,
		13,
		Ui.color.muted,
		UDim2.fromOffset(70, 20),
		UDim2.new(1, -82, 0, 4)
	)
	timeLabel.TextXAlignment = Enum.TextXAlignment.Right
	prismLabel = Ui.label(
		chip,
		"Prism",
		"",
		Ui.FONT_BOLD,
		12,
		TideConfig.byId.Prism.color,
		UDim2.new(1, -44, 0, 14),
		UDim2.fromOffset(32, 22)
	)
end

local function step()
	local unix = Timing.unix()
	local tide, _, endsAt = Tides.at(unix)
	if tide.id ~= shown then
		local first = shown == ""
		shown = tide.id
		OceanController.setTide(tide.color, tide.tint, if tide.id == "Biolum" then 1 else 0)
		dot.BackgroundColor3 = tide.color
		local stroke = chip:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = tide.color
			stroke.Transparency = 0.45
		end
		if not first then
			task.spawn(banner, tide)
		end
	end
	nameLabel.Text = string.upper(tide.name)
	nameLabel.TextColor3 = if tide.id == "Calm" then Ui.color.text else tide.color
	timeLabel.Text = clockText(endsAt - unix)
	-- The next Prism Tide, once it's within the hour
	local prismAt = Tides.nextPrism(unix)
	local untilPrism = prismAt - unix
	if tide.id == "Prism" then
		prismLabel.Text = "PRISM FISH ARE OUT"
		prismLabel.TextColor3 = Color3.fromHSV((os.clock() * 0.25) % 1, 0.55, 1)
	elseif untilPrism <= 3600 then
		prismLabel.Text = `PRISM TIDE IN {clockText(untilPrism)}`
		prismLabel.TextColor3 = TideConfig.byId.Prism.color
	else
		prismLabel.Text = ""
	end
	-- Two lines while there's a Prism note, one otherwise
	local tall = prismLabel.Text ~= ""
	chip.Size = UDim2.fromOffset(250, if tall then 40 else 28)
	nameLabel.Position = UDim2.fromOffset(32, if tall then 4 else 4)
	dot.Position = UDim2.fromOffset(14, if tall then 9 else 9)
	-- Under the boss bar while one is up; hidden on the start screen
	local bossBottom = Ui.bossBottom()
	chip.Position = UDim2.new(0.5, 0, 0, if bossBottom > 0 then bossBottom + 6 else CHIP_TOP)
	chip.Visible = not StartController.isUp()
end

-- The tide now (a Config/Tides record), for the menus
function TideController.current(): TideConfig.Tide
	return (Tides.at(Timing.unix()))
end

function TideController.start()
	build(Players.LocalPlayer:WaitForChild("PlayerGui"))
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local changed = remotes:WaitForChild("TideChanged") :: RemoteEvent
	changed.OnClientEvent:Connect(function()
		step()
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.25 then
			accumulator = 0
			step()
		end
	end)
	step()
end

return TideController
