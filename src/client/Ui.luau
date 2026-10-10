--!strict
-- The HUD's design system: one font family, one palette, one corner radius, and
-- helpers that build elements the same way everywhere. Keep new UI on these so
-- the game reads as one product.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Ui = {}

local FAMILY = "rbxasset://fonts/families/BuilderSans.json"
Ui.FONT = Font.new(FAMILY, Enum.FontWeight.Medium)
Ui.FONT_SEMI = Font.new(FAMILY, Enum.FontWeight.SemiBold)
Ui.FONT_BOLD = Font.new(FAMILY, Enum.FontWeight.Bold)
Ui.FONT_HEAVY = Font.new(FAMILY, Enum.FontWeight.ExtraBold)

Ui.color = {
	panel = Color3.fromRGB(7, 20, 32),
	stroke = Color3.fromRGB(130, 214, 240),
	text = Color3.fromRGB(234, 247, 252),
	muted = Color3.fromRGB(146, 184, 200),
	accent = Color3.fromRGB(86, 222, 255),
	haul = Color3.fromRGB(255, 204, 92),
	danger = Color3.fromRGB(255, 96, 96),
	safe = Color3.fromRGB(112, 236, 164),
	track = Color3.fromRGB(24, 48, 64),
}
Ui.PANEL_TRANSPARENCY = 0.3
Ui.RADIUS = UDim.new(0, 12)

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
	Ui.stroke(frame)
	frame.Parent = parent
	return frame
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

local BUTTON_COLORS: { [string]: { bg: Color3, text: Color3 } } = {
	primary = { bg = Color3.fromRGB(46, 170, 214), text = Color3.fromRGB(4, 20, 30) },
	secondary = { bg = Color3.fromRGB(28, 56, 74), text = Color3.fromRGB(226, 244, 250) },
	gold = { bg = Color3.fromRGB(255, 196, 76), text = Color3.fromRGB(40, 24, 4) },
	danger = { bg = Color3.fromRGB(214, 70, 70), text = Color3.fromRGB(255, 236, 236) },
	disabled = { bg = Color3.fromRGB(30, 44, 54), text = Color3.fromRGB(110, 136, 148) },
}

-- Restyles a button made by Ui.button.
function Ui.setButtonStyle(button: TextButton, style: ButtonStyle)
	local colors = BUTTON_COLORS[style]
	button.BackgroundColor3 = colors.bg
	button.TextColor3 = colors.text
	button.AutoButtonColor = false
	button:SetAttribute("Style", style)
	button.Selectable = style ~= "disabled"
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
	Ui.setButtonStyle(button, style or "primary")
	button.MouseButton1Down:Connect(function()
		Ui.tween(scale, 0.08, { Scale = 0.94 })
	end)
	local function release()
		Ui.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.SelectionGained:Connect(function()
		Ui.tween(scale, 0.15, { Scale = 1.04 })
	end)
	button.SelectionLost:Connect(release)
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
	frame.BackgroundTransparency = 0.08
	frame.ZIndex = 30
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0.5
	end
	local heading = Ui.label(
		frame,
		"Title",
		title,
		Ui.FONT_HEAVY,
		26,
		Ui.color.text,
		UDim2.new(1, -80, 0, 30),
		UDim2.fromOffset(22, 16)
	)
	local sub = Ui.label(
		frame,
		"Subtitle",
		subtitle,
		Ui.FONT,
		15,
		Ui.color.muted,
		UDim2.new(1, -80, 0, 18),
		UDim2.fromOffset(22, 48)
	)
	local close =
		Ui.button(frame, "Close", "X", UDim2.fromOffset(38, 38), UDim2.new(1, -54, 0, 16), "secondary")
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
