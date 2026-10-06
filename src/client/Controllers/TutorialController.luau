--!strict
-- The tutorial on this client: a panel under the wallet with the current step and
-- its progress, markers that point the way (the hub's exits, your den's pool), and
-- a celebration when it's done (the 'Cuda unlocked, a first roll ready). The
-- server counts the steps (TutorialService).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local Tutorial = Config.Tutorial
local hub = Config.World.hub

local TutorialController = {}

local gui: ScreenGui
local panel: Frame
local header: TextLabel
local stepText: TextLabel
local countText: TextLabel
local fill: Frame
local markers: Folder
local shownStep = 0
local shownMarker: string? = nil
local wasDone: boolean? = nil

-- A floating marker in the world, visible through walls, gently pulsing.
local function marker(position: Vector3, text: string)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = markers
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(150, 46)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = anchor
	billboard.Parent = anchor
	local chip = Ui.panel(billboard, "Chip", UDim2.fromScale(1, 1), UDim2.new())
	chip.BackgroundColor3 = Ui.color.accent
	chip.BackgroundTransparency = 0.1
	local label = Ui.label(chip, "Text", text, Ui.FONT_HEAVY, 18, Ui.color.panel, UDim2.fromScale(1, 1))
	label.TextXAlignment = Enum.TextXAlignment.Center
	local scale = Instance.new("UIScale")
	scale.Parent = chip
	TweenService:Create(
		scale,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = 1.12 }
	):Play()
end

local function showMarkers(kind: string?, s: { [string]: any })
	if kind == shownMarker then
		return
	end
	shownMarker = kind
	markers:ClearAllChildren()
	if kind == "exits" then
		for segment = 1, hub.segments do
			if Layout.segmentKind(segment) == "tunnel" then
				local angle = Layout.segmentAngle(segment)
				local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
				local reach = hub.radius + hub.wallThickness + hub.tunnelLength
				marker(hub.center + out * reach + Vector3.new(0, hub.tunnelHeight / 2, 0), "EXIT")
			end
		end
		marker(hub.center + Vector3.new(0, hub.height + 14, 0), "EXIT")
	elseif kind == "den" and typeof(s.den) == "number" then
		marker(Layout.poolPosition(s.den) + Vector3.new(0, 4, 0), "BANK HERE")
	end
end

local function celebrate()
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.32)
	holder.Size = UDim2.fromOffset(700, 110)
	holder.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = holder
	local title = Ui.label(
		holder,
		"Title",
		"TUTORIAL COMPLETE",
		Ui.FONT_HEAVY,
		46,
		Ui.color.haul,
		UDim2.new(1, 0, 0, 52)
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextStrokeTransparency = 0.5
	local species = Config.Species.byId[Tutorial.reward.unlock]
	local sub = Ui.label(
		holder,
		"Sub",
		`The {species.name} is yours · open FISH to swim as it · your first roll is ready`,
		Ui.FONT_BOLD,
		20,
		Ui.color.text,
		UDim2.new(1, 0, 0, 26),
		UDim2.fromOffset(0, 58)
	)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.TextStrokeTransparency = 0.6
	holder.Parent = gui
	Ui.tween(scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(5, function()
		Ui.tween(title, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1 })
		Ui.tween(sub, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.wait(0.65)
		holder:Destroy()
	end)
end

local function onState(s: { [string]: any })
	local tutorial = s.tutorial
	if typeof(tutorial) ~= "table" then
		return
	end
	if tutorial.done then
		panel.Visible = false
		showMarkers(nil, s)
		if wasDone == false then
			celebrate()
		end
		wasDone = true
		return
	end
	wasDone = false
	local step = Tutorial.steps[tutorial.step]
	if step == nil then
		return
	end
	panel.Visible = true
	header.Text = `TUTORIAL · STEP {tutorial.step} OF {#Tutorial.steps}`
	stepText.Text = step.text
	local progress = math.min(tutorial.progress or 0, step.goal)
	countText.Text = if step.goal > 1 then `{progress} / {step.goal}` else ""
	Ui.tween(fill, 0.35, { Size = UDim2.fromScale(progress / step.goal, 1) })
	if tutorial.step ~= shownStep then
		-- A new step: a little bounce so it's noticed
		if shownStep ~= 0 then
			local bounce = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			bounce.Parent = panel
			bounce.Scale = 1.08
			Ui.tween(bounce, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		shownStep = tutorial.step
	end
	showMarkers(step.marker, s)
end

function TutorialController.start()
	gui = Ui.screen("Tutorial", Players.LocalPlayer:WaitForChild("PlayerGui"), 7)
	panel = Ui.panel(gui, "Tutorial", UDim2.fromOffset(300, 92), UDim2.fromOffset(18, 262))
	header = Ui.label(
		panel,
		"Header",
		"",
		Ui.FONT_BOLD,
		12,
		Ui.color.accent,
		UDim2.new(1, -28, 0, 16),
		UDim2.fromOffset(14, 10)
	)
	stepText = Ui.label(
		panel,
		"Step",
		"",
		Ui.FONT_SEMI,
		15,
		Ui.color.text,
		UDim2.new(1, -28, 0, 38),
		UDim2.fromOffset(14, 28)
	)
	stepText.TextWrapped = true
	stepText.TextYAlignment = Enum.TextYAlignment.Top
	countText = Ui.label(
		panel,
		"Count",
		"",
		Ui.FONT_BOLD,
		12,
		Ui.color.muted,
		UDim2.fromOffset(80, 14),
		UDim2.new(1, -94, 0, 10)
	)
	countText.TextXAlignment = Enum.TextXAlignment.Right
	local _, bar =
		Ui.bar(panel, "Progress", UDim2.new(1, -28, 0, 5), UDim2.new(0, 14, 1, -15), Ui.color.accent)
	fill = bar
	panel.Visible = false
	markers = Instance.new("Folder")
	markers.Name = "TutorialMarkers"
	markers.Parent = workspace
	ClientState.changed:connect(onState)
	if ClientState.current then
		onState(ClientState.current)
	end
end

return TutorialController
