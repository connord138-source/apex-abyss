--!strict
-- The HUD's design system: one font family, one palette, one corner radius, and
-- helpers that build elements the same way everywhere. Keep new UI on these so
-- the game reads as one product.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local HeartGlyph = require(ReplicatedStorage.Shared.HeartGlyph)

local Ui = {}

local FAMILY = "rbxasset://fonts/families/BuilderSans.json"
Ui.FONT = Font.new(FAMILY, Enum.FontWeight.Medium)
Ui.FONT_SEMI = Font.new(FAMILY, Enum.FontWeight.SemiBold)
Ui.FONT_BOLD = Font.new(FAMILY, Enum.FontWeight.Bold)
Ui.FONT_HEAVY = Font.new(FAMILY, Enum.FontWeight.ExtraBold)

-- The design (owner, 2026-10-12: "The UI's look cheap they need to be dialed up
-- design wise"): every panel is layered, a deep teal-navy glass with a lighter top
-- and a darker foot (a vertical gradient), a hairline of light along its top edge
-- and a soft stroke; buttons are gradients with a shaded foot and a light rim that
-- lift on hover; windows carry a header band with an accent line. Everything
-- comes through these helpers, so the whole game changes together.
Ui.color = {
	panel = Color3.fromRGB(12, 34, 54), -- the top of a panel; the gradient darkens it toward the foot
	panelFoot = Color3.fromRGB(4, 12, 22),
	stroke = Color3.fromRGB(130, 214, 240),
	text = Color3.fromRGB(234, 247, 252),
	muted = Color3.fromRGB(146, 184, 200),
	accent = Color3.fromRGB(86, 222, 255),
	haul = Color3.fromRGB(255, 204, 92),
	danger = Color3.fromRGB(255, 96, 96),
	safe = Color3.fromRGB(112, 236, 164),
	track = Color3.fromRGB(24, 48, 64),
}
Ui.PANEL_TRANSPARENCY = 0.16
Ui.RADIUS = UDim.new(0, 12)

-- The vertical glass gradient every panel wears (white at the top, so the panel's
-- own colour shows there, darkening toward the foot)
local function glass(parent: Instance, foot: number): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Glass"
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.55, Color3.new(0.78, 0.8, 0.84)),
		ColorSequenceKeypoint.new(1, Color3.new(foot, foot, foot + 0.03)),
	})
	gradient.Parent = parent
	return gradient
end

-- A hairline of light along a panel's top edge
local function topLight(parent: Instance, inset: number, transparency: number)
	local line = Instance.new("Frame")
	line.Name = "TopLight"
	line.BackgroundColor3 = Color3.fromRGB(220, 246, 255)
	line.BackgroundTransparency = transparency
	line.BorderSizePixel = 0
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.new(0.5, 0, 0, 1)
	line.Size = UDim2.new(1, -inset * 2, 0, 1)
	line.ZIndex = parent:IsA("GuiObject") and parent.ZIndex or 1
	line.Parent = parent
	-- A panel that lays its children out in a list or grid would give the hairline a
	-- slot of its own, sized from the panel, so an auto-sized chip grew to fit it (PC
	-- 2026-10-15: the Treasure Wheel's chip was 1,309 px wide): such a panel has none
	local function drop(child: Instance)
		if child:IsA("UIGridStyleLayout") then
			line:Destroy()
		end
	end
	for _, child in parent:GetChildren() do
		drop(child)
	end
	local watch: RBXScriptConnection
	watch = parent.ChildAdded:Connect(function(child)
		drop(child)
		if line.Parent == nil then
			watch:Disconnect()
		end
	end)
end

function Ui.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- A ScreenGui that scales its pixel layout to the screen (phones get a smaller
-- design size, so they scale down less).
function Ui.screen(name: string, parent: Instance, order: number?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = order or 0
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function rescale()
		local camera = workspace.CurrentCamera
		local size = camera.ViewportSize
		local design = if Ui.isTouch() then Vector2.new(960, 540) else Vector2.new(1280, 720)
		scale.Scale = math.clamp(math.min(size.X / design.X, size.Y / design.Y), 0.55, 1.4)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	gui.Parent = parent
	return gui
end

-- Pixels this ScreenGui's content is scaled by (for converting screen points).
function Ui.scaleOf(gui: ScreenGui): number
	local scale = gui:FindFirstChildOfClass("UIScale")
	return if scale then scale.Scale else 1
end

function Ui.corner(parent: Instance, radius: UDim?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or Ui.RADIUS
	corner.Parent = parent
end

function Ui.stroke(parent: Instance, color: Color3?, transparency: number?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Ui.color.stroke
	stroke.Transparency = transparency or 0.72
	stroke.Thickness = thickness or 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

-- A rounded, translucent panel.
function Ui.panel(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor or Vector2.zero
	frame.BackgroundColor3 = Ui.color.panel
	frame.BackgroundTransparency = Ui.PANEL_TRANSPARENCY
	frame.BorderSizePixel = 0
	Ui.corner(frame)
	Ui.stroke(frame, nil, 0.62)
	glass(frame, 0.34)
	topLight(frame, 12, 0.84)
	frame.Parent = parent
	return frame
end

-- A small section heading inside a panel or window: accent small caps over a
-- hairline, so lists and groups read as sections, not loose rows
function Ui.heading(parent: Instance, name: string, text: string, y: number, width: UDim?): TextLabel
	local label = Ui.label(
		parent,
		name,
		string.upper(text),
		Ui.FONT_BOLD,
		12,
		Ui.color.accent,
		UDim2.new(width or UDim.new(1, 0), UDim.new(0, 16)),
		UDim2.fromOffset(0, y)
	)
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.BackgroundColor3 = Ui.color.accent
	rule.BackgroundTransparency = 0.7
	rule.BorderSizePixel = 0
	rule.Position = UDim2.new(0, 0, 1, 2)
	rule.Size = UDim2.new(1, 0, 0, 1)
	rule.Parent = label
	return label
end

-- A key cap (W, SPACE, LEFT CLICK, RB) for control hints: a dark rounded cap with a
-- light top edge and bold text, sized to its label
function Ui.keycap(parent: Instance, name: string, text: string, height: number?): Frame
	local h = height or 30
	local cap = Instance.new("Frame")
	cap.Name = name
	cap.BackgroundColor3 = Color3.fromRGB(22, 52, 76)
	cap.BorderSizePixel = 0
	cap.Size = UDim2.fromOffset(h, h)
	cap.AutomaticSize = Enum.AutomaticSize.X
	Ui.corner(cap, UDim.new(0, 7))
	Ui.stroke(cap, Color3.fromRGB(170, 230, 250), 0.45, 1)
	glass(cap, 0.55)
	topLight(cap, 5, 0.6)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 9)
	padding.PaddingRight = UDim.new(0, 9)
	padding.Parent = cap
	local label =
		Ui.label(cap, "Text", text, Ui.FONT_HEAVY, math.floor(h * 0.46), Ui.color.text, UDim2.new(0, 0, 1, 0))
	label.AutomaticSize = Enum.AutomaticSize.X
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	cap.Parent = parent
	return cap
end

-- A small rounded chip of text in a colour (a tag, a count, a state)
function Ui.chip(parent: Instance, name: string, text: string, color: Color3, height: number?): TextLabel
	local h = height or 22
	local chip =
		Ui.label(parent, name, text, Ui.FONT_BOLD, math.floor(h * 0.55), color, UDim2.fromOffset(0, h))
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.BackgroundTransparency = 0.82
	chip.BackgroundColor3 = color
	chip.TextXAlignment = Enum.TextXAlignment.Center
	Ui.corner(chip, UDim.new(1, 0))
	Ui.stroke(chip, color, 0.6, 1)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = chip
	return chip
end

function Ui.label(
	parent: Instance,
	name: string,
	text: string,
	font: Font,
	textSize: number,
	color: Color3?,
	size: UDim2?,
	position: UDim2?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = text
	label.FontFace = font
	label.TextSize = textSize
	label.TextColor3 = color or Ui.color.text
	label.Size = size or UDim2.new(1, 0, 0, textSize + 4)
	label.Position = position or UDim2.new()
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

-- A thin progress bar; returns the track and its fill (set fill.Size.X.Scale).
function Ui.bar(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3): (Frame, Frame)
	local track = Instance.new("Frame")
	track.Name = name
	track.Size = size
	track.Position = position
	track.BackgroundColor3 = Ui.color.track
	track.BackgroundTransparency = 0.15
	track.BorderSizePixel = 0
	Ui.corner(track, UDim.new(1, 0))
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	Ui.corner(fill, UDim.new(1, 0))
	fill.Parent = track
	track.Parent = parent
	return track, fill
end

function Ui.tween(
	instance: Instance,
	seconds: number,
	properties: { [string]: any },
	style: Enum.EasingStyle?
)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		properties
	)
	tween:Play()
	return tween
end

-- The bottom of the boss bar or the boss countdown at the top centre, in design
-- units (every Ui.screen shares them), or 0 while neither is up. Centre banners
-- start below it (playtest 2026-10-09: on a phone the biome title touched the boss
-- bar and LEAVING THE SAFE ZONE was drawn under it).
function Ui.bossBottom(): number
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("BossHud")
	local bottom = 0
	if hud then
		for _, name in { "Boss", "Countdown" } do
			local panel = hud:FindFirstChild(name)
			if panel and panel:IsA("GuiObject") and panel.Visible then
				bottom = math.max(bottom, panel.Position.Y.Offset + panel.Size.Y.Offset)
			end
		end
	end
	return bottom
end

-- The bottom of the tide chip at the top centre (design units), or 0 while it's hidden
function Ui.tideBottom(): number
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local tides = playerGui and playerGui:FindFirstChild("Tides")
	local chip = tides and tides:FindFirstChild("TideChip")
	if chip and chip:IsA("GuiObject") and chip.Visible then
		return chip.Position.Y.Offset + chip.Size.Y.Offset
	end
	return 0
end

-- The bottom of everything stacked at the top centre: the boss bar or countdown,
-- and the tide chip under it. The SAFE ZONE chip and centre banners start below it
-- (playtest 2026-10-10: the tide chip was drawn over SAFE ZONE).
function Ui.topBottom(): number
	return math.max(Ui.bossBottom(), Ui.tideBottom())
end

-- Centre banners share the middle of the screen, so they take turns (playtest
-- 2026-10-10: TUTORIAL COMPLETE and a tide's banner drew on top of each other).
-- Whether a player's own banner (the tutorial's end, a skin unlock, the Catch of
-- the Week) is up, or anything holds the stage (below): the tide's banner waits.
function Ui.centreBannerUp(): boolean
	if Ui.stageWait() > 0 then
		return true
	end
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if playerGui == nil then
		return false
	end
	for _, name in { "TutorialBanner", "CatchBanner" } do
		if playerGui:FindFirstChild(name, true) then
			return true
		end
	end
	return false
end

-- A player's own banner takes the spot from a tide's (the tide stays on its chip)
-- The middle of the screen is one stage: a big moment (the bank celebration) holds
-- it, and a banner that comes in meanwhile waits its turn (PC overnight 2026-10-14:
-- an achievement banner drew on top of the bank celebration). Each holder has its
-- own hold, so freeing one (the bank's, skipped) leaves a banner's alone; banners
-- hold it too while they're up and queue for it in order (Ui.stageBanner; PC
-- 2026-10-19: SKIN UNLOCKED drew over TUTORIAL COMPLETE, since neither held it).
type StageHold = { untilAt: number, since: number }
local holds: { [string]: StageHold } = {}
local MOMENT = "moment" -- the holder that doesn't name itself: the bank's sequence

-- Holds the stage for `seconds` more (a holder already holding it keeps its start)
function Ui.holdStage(seconds: number, owner: string?)
	local key = owner or MOMENT
	local now = os.clock()
	local hold = holds[key]
	if hold and hold.untilAt > now then
		hold.untilAt = math.max(hold.untilAt, now + seconds)
	else
		holds[key] = { untilAt = now + seconds, since = now }
	end
end
-- Seconds until the stage is free (0 when it is)
function Ui.stageWait(): number
	local now = os.clock()
	local left = 0
	for _, hold in holds do
		left = math.max(left, hold.untilAt - now)
	end
	return left
end
-- Frees a holder's hold now (the bank's growth sequence, skipped)
function Ui.releaseStage(owner: string?)
	holds[owner or MOMENT] = nil
end
-- Whether another holder took the stage after `since` without waiting its turn (the
-- bank's sequence does): a banner up then steps aside and comes back after it
function Ui.stageTakenFrom(owner: string, since: number): boolean
	local now = os.clock()
	for key, hold in holds do
		if key ~= owner and hold.untilAt > now and hold.since > since then
			return true
		end
	end
	return false
end

-- Banners waiting for the stage, first come first served
local stageQueue: { number } = {}
local stageTickets = 0
-- Waits (yielding) until the stage is free and every banner queued before this one
-- has had its turn, then holds it for `seconds`; returns when it took it. `front`
-- puts it first in the line (a banner that stepped aside). After `patience` seconds
-- (30) it goes on anyway.
function Ui.takeStage(owner: string, seconds: number, front: boolean?, patience: number?): number
	stageTickets += 1
	local ticket = stageTickets
	if front then
		table.insert(stageQueue, 1, ticket)
	else
		table.insert(stageQueue, ticket)
	end
	local waited = 0
	local limit = patience or 30
	while (stageQueue[1] ~= ticket or Ui.stageWait() > 0) and waited < limit do
		waited += task.wait(0.1)
	end
	local index = table.find(stageQueue, ticket)
	if index then
		table.remove(stageQueue, index)
	end
	Ui.holdStage(seconds, owner)
	return os.clock()
end

-- A centre banner on the stage: it waits its turn (Ui.takeStage), then `show()`
-- builds it and returns a function that takes it down (`quick` when it steps
-- aside). It stays `seconds`, then has `fade` seconds to fade before the next one;
-- if a big moment takes the stage meanwhile (the bank's growth sequence holds it
-- without queueing) it steps aside at once and comes back first after. `still`, if
-- given, is asked each time its turn comes: false drops it (a tutorial step's banner
-- that came back after the bank's sequence when the step was already done, PC
-- 2026-10-20, TU). Doesn't yield.
function Ui.stageBanner(
	owner: string,
	seconds: number,
	fade: number,
	show: () -> (quick: boolean) -> (),
	still: (() -> boolean)?
)
	task.spawn(function()
		local front = false
		for _ = 1, 3 do
			local since = Ui.takeStage(owner, seconds + fade + 0.1, front)
			if still and not still() then
				Ui.releaseStage(owner)
				return
			end
			local hide = show()
			local stepped = false
			while os.clock() - since < seconds do
				if Ui.stageTakenFrom(owner, since) then
					stepped = true
					break
				end
				task.wait(0.1)
			end
			hide(stepped)
			if not stepped then
				return -- (its hold runs out as it finishes fading)
			end
			Ui.releaseStage(owner)
			front = true
		end
	end)
end

function Ui.clearTideBanner()
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local tides = playerGui and playerGui:FindFirstChild("Tides")
	local banner = tides and tides:FindFirstChild("TideBanner")
	if banner then
		banner:Destroy()
	end
end

-- The safe area's top inset (the Roblox top bar), in screen pixels.
function Ui.topInset(): number
	-- GetGuiInset can still read 0 while the client starts up; the top bar's own
	-- rect (which has a change signal) is set along with it
	return math.max(GuiService:GetGuiInset().Y, GuiService.TopbarInset.Max.Y)
end

-- Phones: Roblox's top bar sits over the screen's top-left corner, so the HUD's
-- top-left column (level card, wallet, HUD buttons, tutorial) moves down to start
-- just below it (its buttons covered the level card's top edge, playtest
-- 2026-10-07). `y` is the piece's design-space top; the column keeps its spacing.
local COLUMN_TOP = 66 -- the level card's top, the column's first piece
function Ui.belowTopBar(gui: ScreenGui, piece: GuiObject, y: number)
	local touch = Ui.isTouch()
	local function place()
		local shift = 0
		if touch then
			shift = math.max(math.ceil((Ui.topInset() + 6) / Ui.scaleOf(gui)) - COLUMN_TOP, 0)
		end
		piece.Position = UDim2.new(piece.Position.X, UDim.new(0, y + shift))
	end
	place()
	local scale = gui:FindFirstChildOfClass("UIScale")
	if scale then
		scale:GetPropertyChangedSignal("Scale"):Connect(place)
	end
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(place)
end

export type ButtonStyle = "primary" | "secondary" | "gold" | "danger" | "disabled"

local BUTTON_COLORS: { [string]: { bg: Color3, text: Color3, rim: number } } = {
	primary = { bg = Color3.fromRGB(58, 186, 230), text = Color3.fromRGB(4, 20, 30), rim = 0.55 },
	secondary = { bg = Color3.fromRGB(36, 70, 92), text = Color3.fromRGB(226, 244, 250), rim = 0.7 },
	gold = { bg = Color3.fromRGB(255, 204, 88), text = Color3.fromRGB(40, 24, 4), rim = 0.45 },
	danger = { bg = Color3.fromRGB(224, 78, 78), text = Color3.fromRGB(255, 236, 236), rim = 0.6 },
	disabled = { bg = Color3.fromRGB(30, 44, 54), text = Color3.fromRGB(110, 136, 148), rim = 0.9 },
}

-- Restyles a button made by Ui.button.
function Ui.setButtonStyle(button: TextButton, style: ButtonStyle)
	local colors = BUTTON_COLORS[style]
	button.BackgroundColor3 = colors.bg
	button.TextColor3 = colors.text
	button.AutoButtonColor = false
	button:SetAttribute("Style", style)
	button.Selectable = style ~= "disabled"
	local rim = button:FindFirstChildOfClass("UIStroke")
	if rim then
		rim.Transparency = colors.rim
	end
	local foot = button:FindFirstChild("Foot")
	if foot and foot:IsA("Frame") then
		foot.BackgroundTransparency = if style == "disabled" then 0.85 else 0.68
	end
end

-- A rounded button that springs a little when pressed.
function Ui.button(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2,
	style: ButtonStyle?
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.FontFace = Ui.FONT_BOLD
	button.TextSize = 16
	button.Size = size
	button.Position = position
	button.BorderSizePixel = 0
	Ui.corner(button, UDim.new(0, 10))
	local scale = Instance.new("UIScale")
	scale.Parent = button
	-- Layered: a lighter head, a shaded foot, a light rim
	glass(button, 0.72)
	Ui.stroke(button, Color3.fromRGB(230, 250, 255), 0.6, 1)
	topLight(button, 8, 0.55)
	local foot = Instance.new("Frame")
	foot.Name = "Foot"
	foot.BackgroundColor3 = Color3.new(0, 0, 0)
	foot.BackgroundTransparency = 0.68
	foot.BorderSizePixel = 0
	foot.AnchorPoint = Vector2.new(0.5, 1)
	foot.Position = UDim2.new(0.5, 0, 1, 0)
	foot.Size = UDim2.new(1, 0, 0, 3)
	Ui.corner(foot, UDim.new(0, 10))
	foot.Parent = button
	Ui.setButtonStyle(button, style or "primary")
	local hovering = false
	local function settle()
		Ui.tween(scale, 0.25, { Scale = if hovering then 1.03 else 1 }, Enum.EasingStyle.Back)
	end
	button.MouseButton1Down:Connect(function()
		Ui.tween(scale, 0.08, { Scale = 0.94 })
	end)
	button.MouseButton1Up:Connect(settle)
	button.MouseEnter:Connect(function()
		if button:GetAttribute("Style") ~= "disabled" then
			hovering = true
			settle()
		end
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		settle()
	end)
	button.SelectionGained:Connect(function()
		Ui.tween(scale, 0.15, { Scale = 1.04 })
	end)
	button.SelectionLost:Connect(settle)
	button.Parent = parent
	return button
end

export type Window = {
	frame: Frame,
	content: Frame,
	close: TextButton,
	title: TextLabel,
	subtitle: TextLabel,
}

-- A centered menu window with a title, a subtitle and a close button. Content
-- goes in `content` (a scrolling list is up to the caller).
function Ui.window(parent: Instance, title: string, subtitle: string, size: Vector2): Window
	local frame = Ui.panel(
		parent,
		"Window",
		UDim2.fromOffset(size.X, size.Y),
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5)
	)
	frame.BackgroundTransparency = 0.03
	frame.ZIndex = 30
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0.45
		stroke.Thickness = 1.5
	end
	-- The header band: a lighter strip with an accent line along its foot
	local band = Instance.new("Frame")
	band.Name = "Header"
	band.BackgroundColor3 = Color3.fromRGB(190, 236, 255)
	band.BackgroundTransparency = 0.93
	band.BorderSizePixel = 0
	band.Size = UDim2.new(1, 0, 0, 72)
	Ui.corner(band)
	band.Parent = frame
	local accentLine = Instance.new("Frame")
	accentLine.Name = "AccentLine"
	accentLine.BackgroundColor3 = Ui.color.accent
	accentLine.BackgroundTransparency = 0.35
	accentLine.BorderSizePixel = 0
	accentLine.Position = UDim2.new(0, 22, 0, 71)
	accentLine.Size = UDim2.new(1, -44, 0, 1)
	accentLine.Parent = frame
	local accentMark = Instance.new("Frame")
	accentMark.Name = "AccentMark"
	accentMark.BackgroundColor3 = Ui.color.accent
	accentMark.BorderSizePixel = 0
	accentMark.Position = UDim2.new(0, 22, 0, 70)
	accentMark.Size = UDim2.fromOffset(56, 3)
	Ui.corner(accentMark, UDim.new(1, 0))
	accentMark.Parent = frame
	local heading = Ui.label(
		frame,
		"Title",
		string.upper(title),
		Ui.FONT_HEAVY,
		24,
		Ui.color.text,
		UDim2.new(1, -80, 0, 30),
		UDim2.fromOffset(22, 14)
	)
	local sub = Ui.label(
		frame,
		"Subtitle",
		subtitle,
		Ui.FONT,
		14,
		Ui.color.muted,
		UDim2.new(1, -80, 0, 18),
		UDim2.fromOffset(22, 44)
	)
	local close =
		Ui.button(frame, "Close", "X", UDim2.fromOffset(38, 38), UDim2.new(1, -54, 0, 17), "secondary")
	close.FontFace = Ui.FONT_HEAVY
	close.TextSize = 18
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(18, 80)
	content.Size = UDim2.new(1, -36, 1, -96)
	content.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Scale = 0.92
	scale.Parent = frame
	Ui.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	-- Phones: Roblox's buttons sit over the screen's top-left corner, and a tall
	-- window's title ran under them (PC overnight 2026-10-14): while the header is
	-- in the top bar's band, the title and subtitle start right of the buttons
	if Ui.isTouch() then
		local function clear()
			local inset = GuiService.TopbarInset
			local perDesign = frame.AbsoluteSize.X / math.max(size.X, 1)
			local over = inset.Min.X - frame.AbsolutePosition.X
			local shift = if frame.AbsolutePosition.Y < inset.Max.Y
					and over > 0
					and perDesign > 0
				then math.ceil(over / perDesign) + 8
				else 0
			heading.Position = UDim2.fromOffset(22 + shift, 14)
			heading.Size = UDim2.new(1, -80 - shift, 0, 30)
			sub.Position = UDim2.fromOffset(22 + shift, 44)
			sub.Size = UDim2.new(1, -80 - shift, 0, 18)
		end
		frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(clear)
		frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(clear)
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(clear)
		task.defer(clear)
	end
	return { frame = frame, content = content, close = close, title = heading, subtitle = sub }
end

-- A vertical scrolling list that grows with its rows.
function Ui.list(parent: Instance, padding: number?): ScrollingFrame
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "List"
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.ScrollBarThickness = 4
	scroller.ScrollBarImageColor3 = Ui.color.stroke
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.CanvasSize = UDim2.new()
	scroller.Selectable = false
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding or 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroller
	scroller.Parent = parent
	return scroller
end

-- A heart drawn from frames (no emoji, no font glyph; Shared/HeartGlyph, the same
-- heart as the den signs'), `size` px square, in `color` (den hearts' rose by
-- default), with a dark outline unless `outline` is false. Returns its box: set
-- Position, AnchorPoint and LayoutOrder on it.
Ui.HEART = Color3.fromRGB(255, 96, 122)
function Ui.heart(parent: Instance, size: number, color: Color3?, outline: boolean?): Frame
	return HeartGlyph.draw(
		parent,
		UDim2.fromOffset(size, size),
		color or Ui.HEART,
		if outline == false then nil else Ui.color.panelFoot
	)
end

-- Thousands separators: 12,400.
function Ui.number(value: number): string
	local text = tostring(math.floor(value + 0.5))
	local sign = ""
	if text:sub(1, 1) == "-" then
		sign, text = "-", text:sub(2)
	end
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return sign .. formatted
end

return Ui
