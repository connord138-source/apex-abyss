--!strict
-- A heart drawn from Frames, for den hearts (HeartService): Roblox's fonts have no
-- heart we can count on and the game uses no emoji, so it's built the classic way, a
-- square turned 45° for the point and two round frames for the lobes, in a square
-- box. Shared by the client (Ui.heart: the ADMIRE chip) and the server (the den
-- signs' SurfaceGuis: the plaza nameplate, the title board inside), so the heart is
-- the same everywhere.
local HeartGlyph = {}

-- The heart in a unit box: 1 wide, ~0.91 tall, centred. The square's side is also
-- the lobes' diameter (each lobe sits on the middle of one of the square's upper
-- edges, so it covers that edge exactly): 1 / (1 + √2 / 2) of the box.
local SIDE = 0.5858
local LOBE_X = 0.2071 -- the lobes' centres either side of the middle (SIDE · √2 / 4)
local LOBE_Y = 0.3358
local POINT_Y = 0.5429 -- the square's centre

local function piece(
	box: Frame,
	name: string,
	x: number,
	y: number,
	color: Color3,
	transparency: number
): Frame
	local made = Instance.new("Frame")
	made.Name = name
	made.AnchorPoint = Vector2.new(0.5, 0.5)
	made.Position = UDim2.fromScale(x, y)
	made.Size = UDim2.fromScale(SIDE, SIDE)
	made.BackgroundColor3 = color
	made.BackgroundTransparency = transparency
	made.BorderSizePixel = 0
	made.Parent = box
	return made
end

-- The three pieces of a heart filling `box`, at `z` (the fill over its outline
-- whether its gui sorts ZIndex by sibling or globally: a SurfaceGui made in code)
local function pieces(box: Frame, color: Color3, transparency: number, z: number)
	local point = piece(box, "Point", 0.5, POINT_Y, color, transparency)
	point.Rotation = 45
	point.ZIndex = z
	for _, x in { 0.5 - LOBE_X, 0.5 + LOBE_X } do
		local lobe = piece(box, "Lobe", x, LOBE_Y, color, transparency)
		lobe.ZIndex = z
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = lobe
	end
end

local function square(name: string, size: UDim2): Frame
	local box = Instance.new("Frame")
	box.Name = name
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.Size = size
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = box
	return box
end

-- Draws a heart in `color` into `parent`, in a square box of `size` (scale or
-- offset; kept square), and returns the box (set its Position and AnchorPoint).
-- `outline` draws a darker heart behind it, `outlineShare` of the box thick (0.1).
function HeartGlyph.draw(
	parent: Instance,
	size: UDim2,
	color: Color3,
	outline: Color3?,
	outlineShare: number?
): Frame
	local box = square("Heart", size)
	if outline then
		local back = square("Outline", UDim2.fromScale(1, 1))
		back.ZIndex = 1
		pieces(back, outline, 0, 1)
		back.Parent = box
		local share = outlineShare or 0.1
		local fill = square("Fill", UDim2.fromScale(1 - 2 * share, 1 - 2 * share))
		fill.AnchorPoint = Vector2.new(0.5, 0.5)
		fill.Position = UDim2.fromScale(0.5, 0.5 + share * 0.25)
		fill.ZIndex = 2
		pieces(fill, color, 0, 2)
		fill.Parent = box
	else
		local fill = square("Fill", UDim2.fromScale(1, 1))
		pieces(fill, color, 0, 1)
		fill.Parent = box
	end
	box.Parent = parent
	return box
end

-- Recolours a heart made by `draw` (its fill, and its outline when it has one), and
-- fades it: 0 solid, 1 gone
function HeartGlyph.paint(box: Instance, color: Color3, outline: Color3?, transparency: number?)
	local fade = transparency or 0
	local fill = box:FindFirstChild("Fill")
	if fill then
		for _, child in fill:GetChildren() do
			if child:IsA("Frame") then
				child.BackgroundColor3 = color
				child.BackgroundTransparency = fade
			end
		end
	end
	local back = box:FindFirstChild("Outline")
	if back then
		for _, child in back:GetChildren() do
			if child:IsA("Frame") then
				if outline then
					child.BackgroundColor3 = outline
				end
				child.BackgroundTransparency = fade
			end
		end
	end
end

return HeartGlyph
