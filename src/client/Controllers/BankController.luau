--!strict
-- The bank's growth sequence (owner, 2026-10-18: "needs to be animation when they
-- drop the haul off showing the fish getting bigger too. Right now its a bit hard to
-- tell"). A Haul grows the fish live as it eats, so banking it changed nothing on
-- screen. Now, when your own Haul is banked:
--   * the camera eases round to look at the fish side-on (head left), framed for
--     its new size, while the fish holds still;
--   * the fish is drawn back at the size it started the dive at, then grows to its
--     new banked size with an overshoot pop (FishAnimator.showGrowth), with a ring
--     of light, a sparkle burst and bubbles;
--   * a card says the Haul banked, the length before and after in feet (counting up
--     as the fish grows) and the levels gained;
--   * any key, click, tap or pad button skips it; the camera eases back behind.
-- It holds the middle of the screen (Ui.holdStage), so banners wait their turn, and
-- never plays under a menu, in Build mode or on the start screen (a short toast
-- then). The server's bank summary drives it (Net.banked).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Format = require(ReplicatedStorage.Shared.Format)
local Size = require(ReplicatedStorage.Shared.Size)
local Bubbles = require(script.Parent.Parent.Bubbles)
local Input = require(script.Parent.Parent.Input)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local CameraController = require(script.Parent.CameraController)
local FishAnimator = require(script.Parent.FishAnimator)
local HudController = require(script.Parent.HudController)
local MenuController = require(script.Parent.MenuController)
local StartController = require(script.Parent.StartController)
local SwimController = require(script.Parent.SwimController)

local BankController = {}

local CAMERA_IN = 0.6 -- seconds easing round to the side
local GROW_SECONDS = 2.5 -- the fish's dip, beat and growth (FishAnimator.showGrowth)
local HOLD_AFTER = 0.7 -- the new size held before the camera goes back
local CAMERA_OUT = 0.5
local SKIP_AFTER = 0.25 -- a key pressed in the first moment isn't a skip (the swim into the pool)
local FRAME_SHARE = 0.42 -- how much of the screen's width the grown fish takes

local gui: ScreenGui
local playing = 0 -- the sequence now playing (a new bank or a skip ends the old one)
local skipRequested = false

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- How far the camera can stand off one side of the fish before rock (studs)
local function room(from: Vector3, direction: Vector3, want: number): number
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local fx = workspace:FindFirstChild("BankFx")
	if fx then
		table.insert(ignore, fx)
	end
	rayParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(from, direction * want, rayParams)
	return if hit then math.max(hit.Distance - 1, 0) else want
end

-- A ring of light, sparkles and bubbles round the fish as it grows
local function burst(center: Vector3, length: number, facing: Vector3)
	local folder = workspace:FindFirstChild("BankFx")
	if folder == nil then
		local made = Instance.new("Folder")
		made.Name = "BankFx"
		made.Parent = workspace
		folder = made
	end
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Ui.color.haul
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Transparency = 0.25
	-- A thin disc facing the camera (a cylinder's axis is its X)
	local frame = CFrame.lookAt(center, center + facing) * CFrame.Angles(0, math.rad(90), 0)
	ring.CFrame = frame
	ring.Size = Vector3.new(0.05, length * 0.6, length * 0.6)
	ring.Parent = folder
	Ui.tween(ring, 0.7, { Size = Vector3.new(0.05, length * 3.2, length * 3.2), Transparency = 1 })
	-- Sparkles
	local anchor = Instance.new("Attachment")
	anchor.Parent = workspace.Terrain
	anchor.WorldPosition = center
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Ui.color.haul, Color3.fromRGB(255, 250, 220))
	sparkle.LightEmission = 1
	sparkle.LightInfluence = 0
	sparkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, length * 0.12),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkle.Transparency = NumberSequence.new(0.1)
	sparkle.Lifetime = NumberRange.new(0.6, 1.1)
	sparkle.Speed = NumberRange.new(length * 1.2, length * 2.6)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Drag = 3
	sparkle.Rate = 0
	sparkle.Parent = anchor
	sparkle:Emit(36)
	Bubbles.burst(center, length, 24)
	task.delay(1.4, function()
		ring:Destroy()
		anchor:Destroy()
	end)
end

-- The card: the Haul banked, the length before → after (the after counting up with
-- the fish), and the levels gained
type Card = { frame: Frame, after: TextLabel, scale: UIScale }

local function card(summary: { [string]: any }, before: number): Card
	local amount = typeof(summary.amount) == "number" and summary.amount or 0
	local frame = Ui.panel(gui, "BankGrowth", UDim2.fromOffset(470, 150), UDim2.new(0.5, 0, 0, 0), Vector2.new(0.5, 0))
	frame.Position = UDim2.new(0.5, 0, 0, math.max(Ui.topBottom() + 14, 74))
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Ui.color.haul
		stroke.Transparency = 0.3
		stroke.Thickness = 1.5
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 0.7
	scale.Parent = frame
	local title = Ui.label(
		frame,
		"Title",
		if summary.doubled then `HAUL DOUBLED · +{Format.mass(amount)}` else `+{Format.mass(amount)} BANKED`,
		Ui.FONT_HEAVY,
		24,
		Ui.color.haul,
		UDim2.new(1, -32, 0, 28),
		UDim2.fromOffset(16, 10)
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	-- Before → after
	local row = Instance.new("Frame")
	row.Name = "Sizes"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(16, 42)
	row.Size = UDim2.new(1, -32, 0, 46)
	row.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local function sized(name: string, text: string, size: number, color: Color3, order: number): TextLabel
		local label = Ui.label(row, name, text, Ui.FONT_HEAVY, size, color, UDim2.fromOffset(0, 46))
		label.AutomaticSize = Enum.AutomaticSize.X
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.LayoutOrder = order
		return label
	end
	sized("Before", Format.length(before), 26, Ui.color.muted, 1)
	sized("Arrow", "→", 26, Ui.color.accent, 2)
	local afterLabel = sized("After", Format.length(before), 38, Ui.color.text, 3)
	-- Levels and coral
	local level = summary.level
	local levelBefore = summary.levelBefore
	local gained = if typeof(level) == "number" and typeof(levelBefore) == "number" then level - levelBefore else 0
	local line = if gained > 0
		then `LEVEL {levelBefore} → {level} · +{gained} LEVEL{if gained == 1 then "" else "S"} · {string.upper(
			tostring(summary.stage or "")
		)}`
		else "Your fish keeps this size now"
	if typeof(summary.coral) == "number" and summary.coral > 0 then
		line ..= `  ·  +{Ui.number(summary.coral)} coral`
	end
	local sub = Ui.label(
		frame,
		"Levels",
		line,
		Ui.FONT_BOLD,
		16,
		if gained > 0 then Ui.color.safe else Ui.color.text,
		UDim2.new(1, -32, 0, 20),
		UDim2.fromOffset(16, 94)
	)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	local skip = Ui.label(
		frame,
		"Skip",
		if Input.isTouch()
			then "tap to skip"
			elseif Input.isGamepad() then "any button to skip"
			else "any key to skip",
		Ui.FONT,
		12,
		Ui.color.muted,
		UDim2.new(1, -32, 0, 14),
		UDim2.fromOffset(16, 124)
	)
	skip.TextXAlignment = Enum.TextXAlignment.Center
	frame.Parent = gui
	Ui.tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	return { frame = frame, after = afterLabel, scale = scale }
end

local function fadeCard(c: Card, seconds: number)
	Ui.tween(c.scale, seconds, { Scale = 1.06 })
	for _, d in c.frame:GetDescendants() do
		if d:IsA("TextLabel") then
			Ui.tween(d, seconds, { TextTransparency = 1, TextStrokeTransparency = 1 })
		elseif d:IsA("UIStroke") then
			Ui.tween(d, seconds, { Transparency = 1 })
		elseif d:IsA("Frame") then
			Ui.tween(d, seconds, { BackgroundTransparency = 1 })
		end
	end
	Ui.tween(c.frame, seconds, { BackgroundTransparency = 1 })
	local stroke = c.frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		Ui.tween(stroke, seconds, { Transparency = 1 })
	end
	task.delay(seconds + 0.05, function()
		c.frame:Destroy()
	end)
end

-- Whether the whole sequence can play now
local function canPlay(): boolean
	return SwimController.root() ~= nil
		and not MenuController.isOpen()
		and not StartController.isUp()
		and not Input.editing
		and not Input.building
		and CameraController.override == nil
end

local function play(summary: { [string]: any })
	local amount = typeof(summary.amount) == "number" and summary.amount or 0
	local mass = typeof(summary.mass) == "number" and summary.mass or 0
	local leveled = typeof(summary.level) == "number"
		and typeof(summary.levelBefore) == "number"
		and summary.level > summary.levelBefore
	Sfx.play("Bank", { volume = 0.7 })
	if not canPlay() or mass <= 0 then
		-- Under a menu (or in Build mode): no camera move, a toast instead
		HudController.toast(
			`+{Format.mass(amount)} banked{if leveled then ` · LEVEL {summary.level}` else ""}`,
			"rare"
		)
		return
	end
	playing += 1
	local mine = playing
	skipRequested = false
	local before = Size.length(math.max(mass - amount, 1e-4))
	local after = Size.length(mass)
	-- A doubled Haul (bought after the bank) may be another fish's: the card only
	local grows = not summary.doubled
	Ui.holdStage(GROW_SECONDS + HOLD_AFTER + CAMERA_OUT + 0.3)
	local wasLocked = Input.locked
	Input.locked = true -- the fish holds still for its moment
	local root = SwimController.root() :: BasePart
	local camera = workspace.CurrentCamera
	local startOffset = camera.CFrame - root.Position
	local startFov = camera.FieldOfView
	-- Side-on, head to the left (the camera on the fish's left), framed for the
	-- grown fish and its pop; the other side if rock is closer on this one
	local fov = math.rad(startFov)
	local aspect = camera.ViewportSize.X / math.max(camera.ViewportSize.Y, 1)
	local halfWidth = math.tan(fov / 2) * aspect
	local peak = after * 1.12
	local want = math.max(peak / (2 * halfWidth * FRAME_SHARE), 4)
	local side = -root.CFrame.RightVector
	local center = root.Position
	local left = room(center, side, want)
	local right = room(center, -side, want)
	if right > left + 1 then
		side = -side
	end
	-- Hemmed in by rock on both sides: the camera stays behind, the rest still plays
	local distance = math.max(left, right)
	local turns = distance >= math.max(after * 0.9, 2.5)
	local blendStart = os.clock()
	local phase = "in"
	local outStart = 0
	local override: (number) -> CFrame?
	override = function(_dt: number): CFrame?
		if mine ~= playing then
			return nil
		end
		local now = os.clock()
		local live = SwimController.root()
		if live == nil then
			return nil
		end
		local at = live.Position
		local flat = Vector3.new(side.X, 0, side.Z)
		local across = if flat.Magnitude > 1e-3 then flat.Unit else side
		local behind = startOffset + at
		local sideOn = if turns
			then CFrame.lookAt(at + across * distance + Vector3.new(0, distance * 0.12, 0), at)
			else behind
		if phase == "in" then
			local t = ease((now - blendStart) / CAMERA_IN)
			return behind:Lerp(sideOn, t)
		elseif phase == "hold" then
			return sideOn
		end
		local t = ease((now - outStart) / CAMERA_OUT)
		if t >= 1 then
			return nil
		end
		return sideOn:Lerp(behind, t)
	end
	CameraController.override = override
	CameraController.overrideFov = startFov
	local shown = card(summary, before)
	local growStarts = if grows then FishAnimator.showGrowth(before, after, GROW_SECONDS) else 0
	-- The ring, sparkles and bubbles as the growth starts; the level-up sound at the pop
	task.delay(growStarts, function()
		if mine ~= playing or not grows then
			return
		end
		local live = SwimController.root()
		if live then
			burst(live.Position, after, -side)
		end
		Sfx.play("Bubbles", { volume = 0.5 })
	end)
	if leveled then
		task.delay(growStarts + GROW_SECONDS * 0.25, function()
			if mine == playing then
				Sfx.play("LevelUp", { volume = 0.75 })
			end
		end)
	end
	-- Runs the clock: the card's number counts with the fish, the phases change, a
	-- skip cuts to the end
	local started = os.clock()
	while mine == playing do
		local now = os.clock()
		local elapsed = now - started
		if phase == "in" and elapsed >= CAMERA_IN then
			phase = "hold"
		end
		local drawn = if grows then FishAnimator.drawnLength() else nil
		local shownLength = if elapsed < growStarts then before else math.clamp(drawn or after, before, after * 1.2)
		shown.after.Text = Format.length(if elapsed >= GROW_SECONDS + 0.05 then after else shownLength)
		shown.after.TextColor3 = if elapsed >= growStarts then Ui.color.haul else Ui.color.text
		local skipping = skipRequested and elapsed >= SKIP_AFTER
		if phase ~= "out" and (skipping or elapsed >= GROW_SECONDS + HOLD_AFTER) then
			phase = "out"
			outStart = now
			if skipping then
				FishAnimator.endGrowth()
				shown.after.Text = Format.length(after)
			end
			fadeCard(shown, if skipping then 0.25 else 0.5)
		end
		if phase == "out" and now - outStart >= CAMERA_OUT then
			break
		end
		task.wait()
	end
	if CameraController.override == override then
		CameraController.override = nil
		CameraController.overrideFov = nil
	end
	if mine == playing then
		Input.locked = wasLocked
		-- The stage is free again once the camera's back (a skip frees it early)
		Ui.releaseStage()
	else
		-- A newer bank took over: put the card away
		Input.locked = wasLocked
		if shown.frame.Parent then
			fadeCard(shown, 0.2)
		end
	end
end

function BankController.start()
	gui = Ui.screen("BankGrowth", Players.LocalPlayer:WaitForChild("PlayerGui"), 11)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local banked = remotes:WaitForChild("Banked") :: RemoteEvent
	banked.OnClientEvent:Connect(function(summary: { [string]: any })
		task.spawn(play, summary)
	end)
	-- Any key, click, tap or pad button skips (the sequence holds the fish still, so
	-- nothing else is lost)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		local kind = input.UserInputType
		if
			kind == Enum.UserInputType.Keyboard and not processed -- (not typing in the chat)
			or kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.MouseButton2
			or kind == Enum.UserInputType.Touch
			or kind.Name:sub(1, 7) == "Gamepad" and input.KeyCode.Name:sub(1, 6) == "Button"
		then
			skipRequested = true
		end
	end)
end

return BankController
