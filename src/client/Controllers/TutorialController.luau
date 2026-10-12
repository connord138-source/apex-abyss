--!strict
-- The tutorial on this client, directed (owner, 2026-10-12: "Controls need to be
-- more obvious during the tutorial and tutorial needs to be more directed instead
-- of just a floating Ui. Alt key is used to pull up the mouse to click the ui
-- screens and that needs to be told so people arent guessing"):
--   * a card under the wallet with the current step, its progress, and the keys
--     the step needs drawn as key caps for this device (Config/Tutorial `controls`)
--   * a trail of lights from the fish to the step's target (the nearest exit, the
--     nearest food, your den's pool, the nearest shell; `guide`), with the distance
--     and an arrow on the card, so there's always somewhere to swim
--   * markers that point the way (the hub's exits breathe, BANK HERE at the pool)
--   * a cursor tip: how to free the mouse for buttons and menus
--   * a celebration when it's done (the 'Cuda unlocked, a first roll ready)
-- The server counts the steps (TutorialService).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.Tutorial)
local Format = require(ReplicatedStorage.Shared.Format)
local Layout = require(ReplicatedStorage.Shared.Layout)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local ForageController = require(script.Parent.ForageController)
local SchoolController = require(script.Parent.SchoolController)
local ShellController = require(script.Parent.ShellController)
local StartController = require(script.Parent.StartController)
local SwimController = require(script.Parent.SwimController)

local Tutorial = Config.Tutorial
local hub = Config.World.hub

local TutorialController = {}

local gui: ScreenGui
local panel: Frame
local header: TextLabel
local stepText: TextLabel
local countText: TextLabel
local fill: Frame
local capsRow: Frame
local guideLine: TextLabel
local guideArrow: TextLabel
local tipLine: TextLabel
local markers: Folder
local trail: Folder
local shownStep = 0
local shownMarker: string? = nil
local wasDone: boolean? = nil
local target: Vector3? = nil
local guideKind: string? = nil
local nextSearch = 0

local TRAIL_DOTS = 9 -- lights between the fish and the target
local TRAIL_NEAR = 14 -- studs: the trail goes out this close to the target
local TRAIL_SPAN = 90 -- studs: the trail reaches this far ahead at most
local SEARCH_RANGE = 420 -- studs: how far the guide looks for food or a shell
local PANEL_HEIGHT = 176

-- A floating label in the world, visible through walls: thin text and a short
-- line, breathing slowly (owner, 2026-10-08: the old chips were "a flashing blue
-- box ... in black"; markers must be subtle)
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
	billboard.Size = UDim2.fromOffset(160, 30)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 240
	billboard.Adornee = anchor
	billboard.Parent = anchor
	local label = Ui.label(billboard, "Text", text, Ui.FONT_BOLD, 15, Ui.color.accent, UDim2.new(1, 0, 0, 22))
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTransparency = 0.1
	local line = Instance.new("Frame")
	line.Name = "Line"
	line.BackgroundColor3 = Ui.color.accent
	line.BorderSizePixel = 0
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.new(0.5, 0, 0, 24)
	line.Size = UDim2.fromOffset(36, 2)
	line.Parent = billboard
	local info = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(label, info, { TextTransparency = 0.5 }):Play()
	TweenService:Create(line, info, { BackgroundTransparency = 0.5 }):Play()
end

-- The exits are built into the rock (lintels and lanterns, WorldService). When the
-- tutorial asks for the way out, the lanterns breathe brighter instead of a chip.
type Pulsed = { light: PointLight, brightness: number, range: number, part: BasePart, transparency: number }
local pulses: { Tween } = {}
local pulsed: { Pulsed } = {}

local function stopPulses()
	for _, tween in pulses do
		tween:Cancel()
	end
	for _, entry in pulsed do
		entry.light.Brightness = entry.brightness
		entry.light.Range = entry.range
		entry.part.Transparency = entry.transparency
	end
	table.clear(pulses)
	table.clear(pulsed)
end

local function pulseExits()
	local info = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	for _, part in CollectionService:GetTagged("ExitLight") do
		local light = if part:IsA("BasePart") then part:FindFirstChildOfClass("PointLight") else nil
		if part:IsA("BasePart") and light then
			table.insert(pulsed, {
				light = light,
				brightness = light.Brightness,
				range = light.Range,
				part = part,
				transparency = part.Transparency,
			})
			local brighter = TweenService:Create(
				light,
				info,
				{ Brightness = light.Brightness * 3.2, Range = light.Range * 1.5 }
			)
			local solid = TweenService:Create(part, info, { Transparency = 0 })
			brighter:Play()
			solid:Play()
			table.insert(pulses, brighter)
			table.insert(pulses, solid)
		end
	end
end

local function showMarkers(kind: string?, s: { [string]: any })
	if kind == shownMarker then
		return
	end
	shownMarker = kind
	markers:ClearAllChildren()
	stopPulses()
	if kind == "exits" then
		pulseExits()
	elseif kind == "den" and typeof(s.denIndex) == "number" and s.denIndex > 0 then
		-- (state.denIndex: `den` is the den's record since the den bases landed, so
		-- the BANK HERE marker had stopped showing)
		marker(Layout.poolPosition(s.denIndex) + Vector3.new(0, 4, 0), "BANK HERE")
	end
end

-- The hub's exits: the four tunnel mouths (just inside the wall, at swimming
-- height) and the hole in the roof
local exits: { Vector3 } = {}
for segment = 1, hub.segments do
	if Layout.segmentKind(segment) == "tunnel" then
		local angle = Layout.segmentAngle(segment)
		table.insert(
			exits,
			hub.center
				+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * (hub.radius + hub.wallThickness + 6)
				+ Vector3.new(0, hub.denFloorY + hub.tunnelHeight * 0.4, 0)
		)
	end
end
table.insert(exits, hub.center + Vector3.new(0, hub.height + 6, 0))

local function nearestExit(from: Vector3): Vector3?
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, exit in exits do
		local distance = (exit - from).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			best = exit
		end
	end
	return best
end

-- Where the step's trail leads right now
local function findTarget(kind: string?, from: Vector3, s: { [string]: any }): Vector3?
	if kind == "exits" then
		return nearestExit(from)
	elseif kind == "den" then
		return if typeof(s.denIndex) == "number" and s.denIndex > 0
			then Layout.poolPosition(s.denIndex) + Vector3.new(0, 2, 0)
			else nil
	elseif kind == "food" then
		local fish = SchoolController.nearestEdible(from, SwimController.length(), SEARCH_RANGE)
		local food = ForageController.nearest(from, SEARCH_RANGE)
		if fish and food then
			return if (fish - from).Magnitude <= (food - from).Magnitude + 20 then fish else food
		end
		return fish or food
	elseif kind == "shells" then
		return ShellController.nearest(from, SEARCH_RANGE)
	end
	return nil
end

-- The trail of lights: small glowing beads on a straight line from the fish to the
-- target, flowing toward it; they ride along as the fish swims
local beads: { BasePart } = {}
local beadFrames: { CFrame } = {}

local function buildTrail()
	for i = 1, TRAIL_DOTS do
		local bead = Instance.new("Part")
		bead.Name = `Bead{i}`
		bead.Shape = Enum.PartType.Ball
		bead.Size = Vector3.new(1.1, 1.1, 1.1)
		bead.Material = Enum.Material.Neon
		bead.Color = Ui.color.accent
		bead.Anchored = true
		bead.CanCollide = false
		bead.CanQuery = false
		bead.CanTouch = false
		bead.CastShadow = false
		bead.Transparency = 1
		bead.Parent = trail
		beads[i] = bead
		beadFrames[i] = CFrame.new()
	end
end

local function hideTrail()
	for _, bead in beads do
		if bead.Transparency < 1 then
			bead.Transparency = 1
		end
	end
end

local function drawTrail(from: Vector3, to: Vector3, t: number)
	local offset = to - from
	local distance = offset.Magnitude
	if distance <= TRAIL_NEAR + 4 then
		hideTrail()
		return
	end
	local direction = offset.Unit
	local span = math.min(distance - TRAIL_NEAR, TRAIL_SPAN)
	local start = from + direction * 6
	local flow = (t * 0.9) % 1 -- the beads slide toward the target
	for i, bead in beads do
		local k = ((i - 1) + flow) / TRAIL_DOTS
		local position = start + direction * (span * k)
		local fade = math.sin(k * math.pi) -- bright in the middle, fading at both ends
		bead.Transparency = 0.15 + 0.6 * (1 - fade)
		local size = 0.8 + 0.5 * fade
		bead.Size = Vector3.new(size, size, size)
		beadFrames[i] = CFrame.new(position)
	end
	workspace:BulkMoveTo(beads, beadFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

local function celebrate()
	-- The bank that finishes the tutorial has its own "+kg BANKED" in the same
	-- spot; wait for it to clear (they once drew on top of each other)
	local hud = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local hudGui = hud and hud:FindFirstChild("Hud")
	local waited = task.wait(0.3) -- the bank's own event can land just after this one
	while hudGui and hudGui:FindFirstChild("Banked") and waited < 4 do
		waited += task.wait(0.1)
	end
	Ui.clearTideBanner()
	local holder = Instance.new("Frame")
	holder.Name = "TutorialBanner"
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

-- The key for a control on this device, or nil when it has none
local function keyFor(control: TutorialConfig.Control): string?
	if Input.isTouch() then
		return control.touch
	elseif Input.isGamepad() then
		return control.pad
	end
	return control.keys
end

-- Rebuilds the row of key caps for a step
local function showControls(step: TutorialConfig.Step)
	capsRow:ClearAllChildren()
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = capsRow
	local shown = 0
	for i, control in step.controls do
		local key = keyFor(control)
		if key == nil then
			continue
		end
		shown += 1
		local holder = Instance.new("Frame")
		holder.Name = `Control{i}`
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromOffset(0, 50)
		holder.AutomaticSize = Enum.AutomaticSize.X
		holder.LayoutOrder = i
		holder.Parent = capsRow
		local cap = Ui.keycap(holder, "Cap", key, 30)
		cap.Position = UDim2.new()
		local caption = Ui.label(
			holder,
			"Does",
			control.does,
			Ui.FONT_SEMI,
			11,
			Ui.color.muted,
			UDim2.new(1, 0, 0, 14),
			UDim2.fromOffset(0, 34)
		)
		caption.TextXAlignment = Enum.TextXAlignment.Center
		caption.TextWrapped = false
	end
	capsRow.Visible = shown > 0
end

-- The cursor tip under the card, for players with a mouse
local function cursorTip(): string
	if Input.isTouch() or Input.isGamepad() then
		return ""
	end
	return "Tap ALT to free the cursor for buttons and menus · ALT again to swim"
end

local function onState(s: { [string]: any })
	local tutorial = s.tutorial
	if typeof(tutorial) ~= "table" then
		return
	end
	if tutorial.done then
		panel.Visible = false
		showMarkers(nil, s)
		guideKind = nil
		target = nil
		hideTrail()
		if wasDone == false then
			task.spawn(celebrate)
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
		-- A new step: a little bounce so it's noticed, and its keys
		if shownStep ~= 0 then
			local bounce = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			bounce.Parent = panel
			bounce.Scale = 1.08
			Ui.tween(bounce, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
			Sfx.play("Banner", { volume = 0.3 })
		end
		shownStep = tutorial.step
		showControls(step)
		tipLine.Text = cursorTip()
		guideKind = step.guide
		target = nil
		nextSearch = 0
	end
	showMarkers(step.marker, s)
end

-- Every frame: find or refresh the target, draw the trail, write the distance
local function step(_dt: number)
	if not panel.Visible or guideKind == nil then
		hideTrail()
		guideLine.Visible = false
		guideArrow.Visible = false
		return
	end
	local root = SwimController.root()
	if root == nil then
		hideTrail()
		return
	end
	local now = os.clock()
	if now >= nextSearch then
		nextSearch = now + 0.5
		target = findTarget(guideKind, root.Position, ClientState.current or {})
	end
	local to = target
	if to == nil then
		hideTrail()
		guideLine.Visible = false
		guideArrow.Visible = false
		return
	end
	drawTrail(root.Position, to, now)
	local offset = to - root.Position
	local distance = offset.Magnitude
	-- The arrow turns relative to where the camera looks
	local look = workspace.CurrentCamera.CFrame.LookVector
	local cameraYaw = math.atan2(-look.X, -look.Z)
	local targetYaw = math.atan2(-offset.X, -offset.Z)
	guideArrow.Rotation = math.deg(targetYaw - cameraYaw)
	guideArrow.Visible = true
	local what = if guideKind == "exits"
		then "the nearest exit"
		elseif guideKind == "den" then "your den's pool"
		elseif guideKind == "shells" then "the nearest shell"
		else "the nearest food"
	local vertical = if offset.Y > 8 then " · above you" elseif offset.Y < -8 then " · below you" else ""
	guideLine.Text = `{Format.distance(distance)} to {what}{vertical}`
	guideLine.Visible = true
end

function TutorialController.start()
	gui = Ui.screen("Tutorial", Players.LocalPlayer:WaitForChild("PlayerGui"), 7)
	panel = Ui.panel(gui, "Tutorial", UDim2.fromOffset(300, PANEL_HEIGHT), UDim2.fromOffset(18, 262))
	Ui.belowTopBar(gui, panel, 262)
	local stroke = panel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Ui.color.accent
		stroke.Transparency = 0.5
	end
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
		14,
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
	capsRow = Instance.new("Frame")
	capsRow.Name = "Controls"
	capsRow.BackgroundTransparency = 1
	capsRow.Position = UDim2.fromOffset(14, 70)
	capsRow.Size = UDim2.new(1, -28, 0, 50)
	capsRow.Parent = panel
	-- The guide: an arrow and the distance to the step's target
	guideArrow = Ui.label(
		panel,
		"Arrow",
		"▲",
		Ui.FONT_HEAVY,
		16,
		Ui.color.accent,
		UDim2.fromOffset(18, 18),
		UDim2.fromOffset(14, 124)
	)
	guideArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	guideArrow.Position = UDim2.fromOffset(23, 133)
	guideArrow.TextXAlignment = Enum.TextXAlignment.Center
	guideArrow.Visible = false
	guideLine = Ui.label(
		panel,
		"Guide",
		"",
		Ui.FONT_BOLD,
		12,
		Ui.color.accent,
		UDim2.new(1, -50, 0, 16),
		UDim2.fromOffset(36, 125)
	)
	guideLine.Visible = false
	tipLine = Ui.label(
		panel,
		"Tip",
		"",
		Ui.FONT,
		11,
		Ui.color.muted,
		UDim2.new(1, -28, 0, 14),
		UDim2.fromOffset(14, 142)
	)
	tipLine.TextWrapped = true
	local _, bar =
		Ui.bar(panel, "Progress", UDim2.new(1, -28, 0, 5), UDim2.new(0, 14, 1, -13), Ui.color.accent)
	fill = bar
	panel.Visible = false
	markers = Instance.new("Folder")
	markers.Name = "TutorialMarkers"
	markers.Parent = workspace
	trail = Instance.new("Folder")
	trail.Name = "TutorialTrail"
	trail.Parent = workspace
	buildTrail()
	ClientState.changed:connect(onState)
	if ClientState.current then
		onState(ClientState.current)
	end
	RunService.RenderStepped:Connect(step)
	-- After the start screen the step pops, so a new player sees where to begin
	StartController.afterStart(function()
		task.wait(0.6)
		if not panel.Visible then
			return
		end
		Sfx.play("Banner", { volume = 0.4 })
		local bounce = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		bounce.Parent = panel
		bounce.Scale = 1.14
		Ui.tween(bounce, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		if stroke then
			local was = stroke.Transparency
			stroke.Transparency = 0
			Ui.tween(stroke, 1.6, { Transparency = was })
		end
	end)
end

return TutorialController
