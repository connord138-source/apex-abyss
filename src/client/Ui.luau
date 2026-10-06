--!strict
-- The HUD's design system: one font family, one palette, one corner radius, and
-- helpers that build elements the same way everywhere. Keep new UI on these so
-- the game reads as one product.
local GuiService = game:GetService("GuiService")
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

-- The safe area's top inset (the Roblox top bar), in screen pixels.
function Ui.topInset(): number
	local inset = GuiService:GetGuiInset()
	return inset.Y
end

return Ui
