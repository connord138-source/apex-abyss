--!strict
-- The Treasure Wheel's stand, built from parts (owner, 2026-10-10: "do want a spin
-- wheel again"). Ported from Hatch & Snatch's Luck Wheel (its owner asked for "a
-- major upgrade, both looks wise as well as functionality" there, so this is the
-- rebuilt game-show wheel): true pie slices, a brass rim with pegs that a flapper
-- ticks against, a lacquered frame and an arch sign ringed with marquee bulbs between
-- two pillars, a big red button on a podium, and two boards (the prizes' odds, and
-- where spins come from). Recoloured for the sea: deep teal lacquer, brass and
-- sea-stone, on a footing that reaches down to the cave floor. There are no
-- ProximityPrompts (they never worked for the fish characters): WheelService checks
-- the distance to the button, and TreasureWheelController shows the hint.
--
-- Layout, in the wheel's own frame (`base`): the origin is the wheel's center, -Z
-- faces the plaza (the front), +Y is up, so +X is on the viewer's left. Slice i is
-- centered (i - 1) × slice counter-clockwise from the top as seen from the front,
-- and the wheel turns clockwise, so turning it by that angle brings slice i under
-- the flapper. Pegs sit every 360 / PEGS degrees, starting at the top.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WheelConfig = require(ReplicatedStorage.Shared.Config.Wheel)

local TreasureWheel = {}

TreasureWheel.TAG = "TreasureWheel" -- on the whole model; the client binds to it as it streams in
TreasureWheel.RADIUS = 9 -- the slices' radius
TreasureWheel.HEIGHT = 14 -- the wheel's center above the ground
TreasureWheel.PEGS = 24
TreasureWheel.CLEAR_RADIUS = 26 -- keep scenery this far from the wheel (stage and boards)

export type Segment = WheelConfig.Segment
-- A line on a board: what (left), how much (right), and the slice's color swatch
export type BoardRow = { left: string, right: string, color: Color3? }

export type Built = {
	model: Model, -- tagged TreasureWheel, streams in and out whole
	disc: Model, -- everything that turns; rotate with base * CFrame.Angles(0, 0, angle)
	base: CFrame,
	button: BasePart, -- the big red button (WheelService measures reach to it)
	status: TextLabel, -- RichText line on the arch sign (who's spinning, who won)
}

local R = TreasureWheel.RADIUS
local H = TreasureWheel.HEIGHT
local SLICE_STEPS = 5 -- triangles per slice; at radius 9 the edge is round to the eye
local FRAME_R = R + 1.55 -- the lacquered frame round the wheel
local PILLAR_X = 13.4
local SIGN_Y = FRAME_R + 3.4 -- the arch sign's center, above the wheel's center
local STAGE_TOP = 1.8 -- the upper step's top above the ground
local FLAPPER_PIVOT = Vector3.new(0, R + 1.4, -0.85)
local PEG_RADIUS = R - 0.55
local HUB_R = 2.2 -- the gold hub
local COLLAR_R = 3.15 -- the gold ring round it
-- Slice text (owner, 2026-10-10: "word overlap etc ... its just the details"): the
-- prize in big letters over what it is, each label as wide as its wedge is at the
-- label's inner edge (×LABEL_FILL), so no word reaches into the next slice, and its
-- letters capped (`letters`, studs) so a short word doesn't dwarf a long one
type Band = { from: number, to: number, letters: number }
local BIG_BAND: Band = { from = 5.3, to = 7.3, letters = 1.25 }
local SUB_BAND: Band = { from = 3.75, to = 4.85, letters = 0.6 }
local LABEL_FILL = 0.88
local TEXT_PIXELS = 100 -- SurfaceGui pixels per stud on the wheel
local CAP_HEIGHT = 0.72 -- a capital's height as a share of the font size

local GOLD = Color3.fromRGB(255, 196, 64)
local GOLD_LIGHT = Color3.fromRGB(255, 224, 140)
-- (deep teal lacquer for the frame and pillars, sea-stone for the stage)
local CRIMSON = Color3.fromRGB(16, 98, 112)
local CRIMSON_DARK = Color3.fromRGB(8, 56, 68)
local MARBLE = Color3.fromRGB(176, 196, 196)
local BACKING = Color3.fromRGB(10, 24, 40)
local BULB = Color3.fromRGB(255, 214, 150)
local TEXT_STROKE = Color3.fromRGB(4, 28, 36)

local function apply(p: BasePart, props: { [string]: any })
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
end

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	apply(p, props)
	p.Parent = parent
	return p
end

local function wedge(parent: Instance, props: { [string]: any }): WedgePart
	local w = Instance.new("WedgePart")
	apply(w, props)
	w.Parent = parent
	return w
end

-- A flat triangle a-b-c, `thickness` thick, as two right-angled wedges that meet
-- on the altitude from its longest edge.
local function triangle(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	thickness: number,
	props: { [string]: any }
): { WedgePart }
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	-- Now bc is the longest edge and a the corner across from it
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local first = wedge(parent, props)
	first.Size = Vector3.new(thickness, height, math.abs(ab:Dot(back)))
	first.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	local second = wedge(parent, props)
	second.Size = Vector3.new(thickness, height, math.abs(ac:Dot(back)))
	second.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	return { first, second }
end

-- A point on the wheel's face: `theta` counter-clockwise from the top (as seen
-- from the front), `radius` out from the center, `z` toward the back.
local function onFace(base: CFrame, theta: number, radius: number, z: number): Vector3
	return base * Vector3.new(math.sin(theta) * radius, math.cos(theta) * radius, z)
end

-- The frame of a piece standing on the face at `theta`: +Y points out from the center.
local function radial(base: CFrame, theta: number, radius: number, z: number): CFrame
	return base * CFrame.Angles(0, 0, -theta) * CFrame.new(0, radius, z)
end

-- A ring of short cylinders standing in for a torus, round the wheel's center.
local function ring(
	parent: Instance,
	base: CFrame,
	radius: number,
	tube: number,
	z: number,
	count: number,
	props: { [string]: any }
)
	local length = 2 * radius * math.sin(math.pi / count) + tube * 0.4
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(length, tube, tube)
	for i = 0, count - 1 do
		-- A cylinder's axis is its X, which lies along the ring here
		props.CFrame = radial(base, (i + 0.5) / count * 2 * math.pi, radius * math.cos(math.pi / count), z)
		part(parent, props)
	end
end

-- A cylinder whose axis runs front to back (a hub, a peg, a crest).
local function facing(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, math.pi / 2, 0)
end

-- A cylinder standing upright.
local function upright(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, 0, math.pi / 2)
end

local function surface(target: BasePart, face: Enum.NormalId, canvas: Vector2): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.CanvasSize = canvas
	gui.LightInfluence = 0 -- reads at night too
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.Parent = target
	return gui
end

-- A scaled TextLabel with a dark outline `stroke` canvas pixels thick.
local function text(parent: Instance, stroke: number, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	for key, value in props do
		(label :: any)[key] = value
	end
	local outline = Instance.new("UIStroke")
	outline.Color = TEXT_STROKE
	outline.Thickness = stroke
	outline.Parent = label
	label.Parent = parent
	return label
end

local function bulb(parent: Instance, cf: CFrame, size: number, group: string, index: number): Part
	local b = part(parent, {
		Name = "Bulb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size),
		CFrame = cf,
		Material = Enum.Material.Neon,
		Color = BULB,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	b:SetAttribute("Group", group)
	b:SetAttribute("Index", index)
	return b
end

-- A label lying on the slice centred at `theta` (`half` is half the slice's angle),
-- across the band and as wide as the wedge allows at the band's inner edge.
local function sliceText(
	disc: Instance,
	base: CFrame,
	theta: number,
	half: number,
	band: Band,
	words: string,
	stroke: number
): BasePart
	local holder = part(disc, {
		Name = "SliceText",
		Size = Vector3.new(2 * band.from * math.tan(half) * LABEL_FILL, band.to - band.from, 0.05),
		CFrame = radial(base, theta, (band.from + band.to) / 2, -0.2),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = TEXT_PIXELS
	gui.LightInfluence = 0
	gui.Parent = holder
	local label = text(gui, stroke, {
		Size = UDim2.fromScale(1, 1),
		Text = words,
	})
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = math.floor(band.letters / CAP_HEIGHT * TEXT_PIXELS)
	limit.Parent = label
	return holder
end

---------------------------------------------------------------------------
-- The disc: everything that turns
---------------------------------------------------------------------------

local function buildDisc(parent: Instance, base: CFrame, segments: { Segment }): Model
	local disc = Instance.new("Model")
	disc.Name = "WheelDisc"
	local loose = { CanCollide = false, CanQuery = false, CanTouch = false }

	local hub = part(disc, {
		Name = "Hub",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, HUB_R * 2, HUB_R * 2),
		CFrame = facing(base * CFrame.new(0, 0, -0.3)),
		Material = Enum.Material.Foil,
		Color = GOLD,
		CanCollide = false,
	})
	part(disc, {
		Name = "HubRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.45, 3.3, 3.3),
		CFrame = facing(base * CFrame.new(0, 0, -0.55)),
		Material = Enum.Material.SmoothPlastic,
		Color = CRIMSON,
		CanCollide = false,
	})
	local dome = part(disc, {
		Name = "HubDome",
		Size = Vector3.new(2.5, 2.5, 1.4),
		CFrame = base * CFrame.new(0, 0, -0.8),
		Material = Enum.Material.Foil,
		Color = GOLD,
		CanCollide = false,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = dome
	-- A pearl set in the gold dome (it was a pink neon jewel)
	local pearl = part(disc, {
		Name = "Pearl",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.35, 1.35, 1.35),
		CFrame = base * CFrame.new(0, 0, -1.35),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(236, 242, 252),
		Reflectance = 0.3,
		CanCollide = false,
		CastShadow = false,
	})
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(170, 230, 255)
	glow.Range = 7
	glow.Brightness = 0.8
	glow.Parent = pearl
	part(disc, {
		Name = "Backing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, R * 2 + 1, R * 2 + 1),
		CFrame = facing(base * CFrame.new(0, 0, 0.35)),
		Material = Enum.Material.SmoothPlastic,
		Color = BACKING,
		CanCollide = false,
	})

	-- Slices: true pie wedges, a fan of triangles each, meeting the rim with no gaps
	local slice = 2 * math.pi / #segments
	for i, segment in segments do
		local center = (i - 1) * slice
		local props = {
			Name = "Slice",
			Material = Enum.Material.SmoothPlastic,
			Color = segment.color,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}
		for step = 0, SLICE_STEPS - 1 do
			local from = center - slice / 2 + step * slice / SLICE_STEPS
			local to = from + slice / SLICE_STEPS
			local pieces = triangle(
				disc,
				base * Vector3.new(0, 0, 0),
				onFace(base, from, R, 0),
				onFace(base, to, R, 0),
				0.3,
				props
			)
			for _, piece in pieces do
				piece:SetAttribute("Slice", i)
			end
		end
		-- Gold divider on the slice's leading edge
		part(disc, {
			Name = "Divider",
			Size = Vector3.new(0.24, R - HUB_R, 0.2),
			CFrame = radial(base, center + slice / 2, (R + HUB_R) / 2, -0.22),
			Material = Enum.Material.Foil,
			Color = GOLD_LIGHT,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})

		-- The prize in big letters, what it is under it; upright when the slice is on
		-- top, under the flapper (no emoji: the game uses none, GDD §12)
		local prize = sliceText(disc, base, center, slice / 2, BIG_BAND, segment.big, 6)
		sliceText(disc, base, center, slice / 2, SUB_BAND, segment.sub, 3)
		if segment.kind == "skin" then
			-- The jackpot slice glitters
			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 240, 170))
			sparkle.LightEmission = 1
			sparkle.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.4),
				NumberSequenceKeypoint.new(1, 0),
			})
			sparkle.Lifetime = NumberRange.new(0.6, 1.2)
			sparkle.Rate = 4
			sparkle.Speed = NumberRange.new(0.3, 0.8)
			sparkle.SpreadAngle = Vector2.new(180, 180)
			sparkle.Parent = prize
		end
	end

	-- Rim and pegs (the pegs at slice edges have bigger, lit heads)
	local rimProps: { [string]: any } = table.clone(loose)
	rimProps.Name = "Rim"
	rimProps.Material = Enum.Material.Foil
	rimProps.Color = GOLD
	ring(disc, base, R + 0.35, 0.9, -0.05, 36, rimProps)
	local collarProps: { [string]: any } = table.clone(loose)
	collarProps.Name = "Collar"
	collarProps.Material = Enum.Material.Foil
	collarProps.Color = GOLD
	collarProps.CastShadow = false
	ring(disc, base, COLLAR_R, 0.3, -0.18, 28, collarProps)
	local perSlice = TreasureWheel.PEGS // #segments
	for k = 0, TreasureWheel.PEGS - 1 do
		local theta = k / TreasureWheel.PEGS * 2 * math.pi
		local edge = perSlice > 0 and k % perSlice == perSlice // 2
		part(disc, {
			Name = "Peg",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1, 0.32, 0.32),
			CFrame = facing(radial(base, theta, PEG_RADIUS, -0.65)),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(225, 225, 235),
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})
		local head = if edge then 0.62 else 0.46
		part(disc, {
			Name = "PegHead",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(head, head, head),
			CFrame = radial(base, theta, PEG_RADIUS, -1.2),
			Material = if edge then Enum.Material.Neon else Enum.Material.Foil,
			Color = if edge then BULB else GOLD,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})
	end

	disc.PrimaryPart = hub
	-- A model with a PrimaryPart pivots on it, so move the hub's pivot to the
	-- wheel's center (the hub itself is turned 90°)
	hub.PivotOffset = hub.CFrame:ToObjectSpace(base)
	local count = 0
	for _, descendant in disc:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	disc:SetAttribute("Parts", count) -- the client waits until it has them all
	disc.Parent = parent
	return disc
end

---------------------------------------------------------------------------
-- The flapper: pivots at its top; the client swings it as pegs pass
---------------------------------------------------------------------------

local function buildFlapper(parent: Instance, base: CFrame): Model
	local flapper = Instance.new("Model")
	flapper.Name = "Flapper"
	local loose = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	local function point(x: number, y: number, z: number): Vector3
		return base * Vector3.new(x, y, z)
	end
	local outline: { [string]: any } = table.clone(loose)
	outline.Name = "FlapperTrim"
	outline.Material = Enum.Material.Foil
	outline.Color = GOLD
	triangle(
		flapper,
		point(-1.05, R + 1.75, -0.62),
		point(1.05, R + 1.75, -0.62),
		point(0, R - 1.4, -0.62),
		0.16,
		outline
	)
	local arrow: { [string]: any } = table.clone(loose)
	arrow.Name = "FlapperArrow"
	arrow.Material = Enum.Material.SmoothPlastic
	arrow.Color = Color3.fromRGB(225, 32, 52)
	triangle(
		flapper,
		point(-0.8, R + 1.6, -0.85),
		point(0.8, R + 1.6, -0.85),
		point(0, R - 1.05, -0.85),
		0.3,
		arrow
	)
	local cap: { [string]: any } = table.clone(loose)
	cap.Name = "FlapperCap"
	cap.Shape = Enum.PartType.Cylinder
	cap.Size = Vector3.new(0.6, 0.9, 0.9)
	cap.CFrame = facing(base * CFrame.new(FLAPPER_PIVOT.X, FLAPPER_PIVOT.Y, -1.15))
	cap.Material = Enum.Material.Foil
	cap.Color = GOLD_LIGHT
	part(flapper, cap)
	flapper:SetAttribute("PivotCFrame", base * CFrame.new(FLAPPER_PIVOT))
	local count = 0
	for _, child in flapper:GetChildren() do
		if child:IsA("BasePart") then
			count += 1
		end
	end
	flapper:SetAttribute("Parts", count)
	flapper.Parent = parent
	return flapper
end

---------------------------------------------------------------------------
-- Boards beside the stage
---------------------------------------------------------------------------

-- A board: a title, a hairline, one row per line (a swatch, what, how much) and a
-- footnote. Rows are laid out on a fixed canvas, so nothing wraps or runs off the
-- panel (playtest 2026-10-10: the spins board's last line ran off the bottom).
local function board(parent: Instance, origin: CFrame, title: string, rows: { BoardRow }, footer: string)
	local folder = Instance.new("Model")
	folder.Name = "WheelBoard"
	for _, x in { -4.3, 4.3 } do
		part(folder, {
			Name = "Post",
			Size = Vector3.new(0.5, 10.8, 0.5),
			CFrame = origin * CFrame.new(x, 5.4, 0.3),
			Material = Enum.Material.Foil,
			Color = GOLD,
		})
	end
	part(folder, {
		Name = "Plate",
		Size = Vector3.new(9, 8.2, 0.25),
		CFrame = origin * CFrame.new(0, 6.3, 0.3),
		Material = Enum.Material.Foil,
		Color = GOLD,
	})
	local panel = part(folder, {
		Name = "Panel",
		Size = Vector3.new(8.4, 7.6, 0.4),
		CFrame = origin * CFrame.new(0, 6.3, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = CRIMSON_DARK,
	})
	part(folder, {
		Name = "Cap",
		Size = Vector3.new(9.3, 0.45, 1),
		CFrame = origin * CFrame.new(0, 10.6, 0.2),
		Material = Enum.Material.Foil,
		Color = GOLD,
	})
	-- 80 canvas pixels a stud
	local gui = surface(panel, Enum.NormalId.Front, Vector2.new(672, 608))
	local heading = text(gui, 4, {
		Position = UDim2.fromOffset(32, 16),
		Size = UDim2.fromOffset(608, 72),
		Font = Enum.Font.LuckiestGuy,
		Text = title,
		TextColor3 = GOLD_LIGHT,
	})
	local headingLimit = Instance.new("UITextSizeConstraint")
	headingLimit.MaxTextSize = 64
	headingLimit.Parent = heading
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.BorderSizePixel = 0
	rule.BackgroundColor3 = GOLD
	rule.Position = UDim2.fromOffset(48, 98)
	rule.Size = UDim2.fromOffset(576, 3)
	rule.Parent = gui
	-- Rows: 404 px of room, at most 60 px a row
	local top, room = 116, 404
	local rowHeight = math.min(60, math.floor(room / math.max(1, #rows)))
	for i, row in rows do
		local frame = Instance.new("Frame")
		frame.Name = "Row"
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
		frame.BackgroundTransparency = if i % 2 == 1 then 0.93 else 1
		frame.Position = UDim2.fromOffset(28, top + (i - 1) * rowHeight)
		frame.Size = UDim2.fromOffset(616, rowHeight)
		frame.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = frame
		local inset = 14
		if row.color then
			local swatch = Instance.new("Frame")
			swatch.Name = "Swatch"
			swatch.BorderSizePixel = 0
			swatch.BackgroundColor3 = row.color :: Color3
			swatch.AnchorPoint = Vector2.new(0, 0.5)
			swatch.Position = UDim2.new(0, 14, 0.5, 0)
			swatch.Size = UDim2.fromOffset(24, 24)
			swatch.Parent = frame
			local round = Instance.new("UICorner")
			round.CornerRadius = UDim.new(0, 5)
			round.Parent = swatch
			local edge = Instance.new("UIStroke")
			edge.Color = GOLD_LIGHT
			edge.Thickness = 1.5
			edge.Parent = swatch
			inset = 50
		end
		local what = text(gui, 1.5, {
			Name = "What",
			Font = Enum.Font.GothamBold,
			Text = row.left,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(28 + inset, top + (i - 1) * rowHeight + rowHeight * 0.18),
			Size = UDim2.fromOffset(452 - inset, rowHeight * 0.64),
		})
		local whatLimit = Instance.new("UITextSizeConstraint")
		whatLimit.MaxTextSize = 34
		whatLimit.Parent = what
		local much = text(gui, 1.5, {
			Name = "Much",
			Font = Enum.Font.GothamBlack,
			Text = row.right,
			TextColor3 = GOLD_LIGHT,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromOffset(488, top + (i - 1) * rowHeight + rowHeight * 0.16),
			Size = UDim2.fromOffset(146, rowHeight * 0.68),
		})
		local muchLimit = Instance.new("UITextSizeConstraint")
		muchLimit.MaxTextSize = 36
		muchLimit.Parent = much
	end
	local note = text(gui, 1, {
		Name = "Footer",
		Font = Enum.Font.GothamMedium,
		Text = footer,
		TextColor3 = Color3.fromRGB(196, 228, 228),
		TextWrapped = true,
		Position = UDim2.fromOffset(36, 528),
		Size = UDim2.fromOffset(600, 66),
	})
	local noteLimit = Instance.new("UITextSizeConstraint")
	noteLimit.MaxTextSize = 26
	noteLimit.Parent = note
	folder.Parent = parent
end

---------------------------------------------------------------------------
-- The whole wheel
---------------------------------------------------------------------------

-- Builds the wheel standing on `ground`, its face turned toward `faceToward`.
-- `spinRows` and `spinFooter` fill in the free spins board.
function TreasureWheel.build(
	parent: Instance,
	ground: Vector3,
	faceToward: Vector3,
	segments: { Segment },
	spinRows: { BoardRow },
	spinFooter: string
): Built
	local target = Vector3.new(faceToward.X, ground.Y + H, faceToward.Z)
	local base = CFrame.lookAt(ground + Vector3.new(0, H, 0), target)
	local floor = base * CFrame.new(0, -H, 0) -- the same frame, on the ground
	local model = Instance.new("Model")
	model.Name = "TreasureWheel"
	model:SetAttribute("BaseCFrame", base)
	model:SetAttribute("Pegs", TreasureWheel.PEGS)

	-- A footing down into the cave floor, so an uneven floor shows no gap under it
	part(model, {
		Name = "Footing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(8, 35.6, 35.6),
		CFrame = upright(floor * CFrame.new(0, -4, 0)),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(70, 84, 92),
	})
	-- Stage: two sea-stone steps with brass edges, and a carpet to the button
	local steps = { { 35, 0 }, { 29, STAGE_TOP / 2 } }
	for index, step in steps do
		local diameter, bottom = step[1], step[2]
		local top = bottom + STAGE_TOP / 2
		part(model, {
			Name = "Stage",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(STAGE_TOP / 2, diameter, diameter),
			CFrame = upright(floor * CFrame.new(0, bottom + STAGE_TOP / 4, 0)),
			Material = Enum.Material.Marble,
			Color = MARBLE,
		})
		part(model, {
			Name = "StageTrim",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, diameter + 0.3, diameter + 0.3),
			CFrame = upright(floor * CFrame.new(0, top - 0.12, 0)),
			Material = Enum.Material.Foil,
			Color = GOLD,
			CanCollide = false,
		})
		-- Carpet across this step's front, from the podium out
		local inner = if index == 2 then 10.8 else 29 / 2 + 0.1
		local outer = math.sqrt((diameter / 2) ^ 2 - 2.5 ^ 2) - 0.05
		part(model, {
			Name = "Carpet",
			Size = Vector3.new(5, 0.08, outer - inner),
			CFrame = floor * CFrame.new(0, top + 0.04, -(inner + outer) / 2),
			Material = Enum.Material.Fabric,
			Color = Color3.fromRGB(10, 70, 82),
			CanCollide = false,
		})
	end

	-- Back post and axle
	part(model, {
		Name = "Post",
		Size = Vector3.new(1.8, H - STAGE_TOP + 0.9, 1.4),
		CFrame = floor * CFrame.new(0, (STAGE_TOP + H + 0.9) / 2, 2.4),
		Material = Enum.Material.SmoothPlastic,
		Color = CRIMSON_DARK,
	})
	part(model, {
		Name = "Axle",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.2, 1.2, 1.2),
		CFrame = facing(base * CFrame.new(0, 0, 1.5)),
		Material = Enum.Material.Foil,
		Color = GOLD,
		CanCollide = false,
	})

	-- Frame round the wheel: lacquer tube, gold pinstripe, marquee bulbs
	local lacquer: { [string]: any } = {
		Name = "Frame",
		Material = Enum.Material.SmoothPlastic,
		Color = CRIMSON,
		Reflectance = 0.06,
		CanCollide = false,
	}
	ring(model, base, FRAME_R, 1.3, 0.15, 36, lacquer)
	ring(model, base, FRAME_R + 0.75, 0.35, 0, 36, {
		Name = "FrameTrim",
		Material = Enum.Material.Foil,
		Color = GOLD,
		CanCollide = false,
		CastShadow = false,
	})
	local bulbs = Instance.new("Model")
	bulbs.Name = "Bulbs"
	local ringBulbs = 32
	for i = 0, ringBulbs - 1 do
		-- Numbered clockwise from the top (as seen from the front), so the chase runs with the wheel
		bulb(bulbs, radial(base, -i / ringBulbs * 2 * math.pi, FRAME_R, -0.75), 0.48, "Ring", i + 1)
	end
	part(model, {
		Name = "FlapperMount", -- the client's tick sounds and confetti come from here
		Size = Vector3.new(1.8, 1.4, 1),
		CFrame = base * CFrame.new(0, FRAME_R + 0.2, -0.9),
		Material = Enum.Material.Foil,
		Color = GOLD,
		CanCollide = false,
	})

	-- Pillars either side, gold arms to the frame
	for _, side in { -1, 1 } do
		local x = side * PILLAR_X
		local bottom = -H + STAGE_TOP
		local top = SIGN_Y + 2.7
		part(model, {
			Name = "Pillar",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(top - bottom, 1.9, 1.9),
			CFrame = upright(base * CFrame.new(x, (top + bottom) / 2, 0.3)),
			Material = Enum.Material.SmoothPlastic,
			Color = CRIMSON,
			Reflectance = 0.06,
		})
		part(model, {
			Name = "PillarFoot",
			Size = Vector3.new(3, 1.6, 3),
			CFrame = base * CFrame.new(x, bottom + 0.8, 0.3),
			Material = Enum.Material.Marble,
			Color = MARBLE,
		})
		for _, y in { bottom + 1.7, -6, 2, 10, top - 0.4 } do
			part(model, {
				Name = "PillarBand",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.3, 2.15, 2.15),
				CFrame = upright(base * CFrame.new(x, y, 0.3)),
				Material = Enum.Material.Foil,
				Color = GOLD,
				CanCollide = false,
			})
		end
		part(model, {
			Name = "PillarCap",
			Size = Vector3.new(2.8, 0.9, 2.8),
			CFrame = base * CFrame.new(x, top + 0.45, 0.3),
			Material = Enum.Material.Foil,
			Color = GOLD,
		})
		part(model, {
			Name = "Finial",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.8, 1.8, 1.8),
			CFrame = base * CFrame.new(x, top + 1.8, 0.3),
			Material = Enum.Material.Foil,
			Color = GOLD,
		})
		bulb(bulbs, base * CFrame.new(x, top + 3, 0.3), 0.6, "Finial", 1)
		for i = 0, 8 do
			bulb(bulbs, base * CFrame.new(x, -9 + i * 2.6, -0.72), 0.4, "Pillar", i + 1)
		end
		part(model, {
			Name = "Arm",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(PILLAR_X - FRAME_R - 0.2, 0.7, 0.7),
			CFrame = base * CFrame.new(side * (FRAME_R + PILLAR_X) / 2, 0, 0.2),
			Material = Enum.Material.Foil,
			Color = GOLD,
			CanCollide = false,
		})
		part(model, {
			Name = "ArmJoint",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.1, 1.1, 1.1),
			CFrame = base * CFrame.new(side * (FRAME_R + 0.6), 0, 0.15),
			Material = Enum.Material.Foil,
			Color = GOLD,
			CanCollide = false,
		})
	end

	-- Arch sign across the pillars, with a crest and bulbs along both edges
	local signWidth = PILLAR_X * 2 - 1.9
	local sign = part(model, {
		Name = "Sign",
		Size = Vector3.new(signWidth, 4.4, 0.8),
		CFrame = base * CFrame.new(0, SIGN_Y, -0.3),
		Material = Enum.Material.SmoothPlastic,
		Color = CRIMSON,
	})
	part(model, {
		Name = "SignPlate",
		Size = Vector3.new(signWidth + 1, 5.4, 0.5),
		CFrame = base * CFrame.new(0, SIGN_Y, 0.1),
		Material = Enum.Material.Foil,
		Color = GOLD,
	})
	part(model, {
		Name = "CrestTrim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 8.8, 8.8),
		CFrame = facing(base * CFrame.new(0, SIGN_Y + 2.2, 0.45)),
		Material = Enum.Material.Foil,
		Color = GOLD,
	})
	local crest = part(model, {
		Name = "Crest",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 8, 8),
		CFrame = facing(base * CFrame.new(0, SIGN_Y + 2.2, 0.2)),
		Material = Enum.Material.SmoothPlastic,
		Color = CRIMSON_DARK,
	})
	-- A cylinder's flat end is its Right face, which the turn above points at the front
	text(surface(crest, Enum.NormalId.Right, Vector2.new(400, 400)), 2, {
		Position = UDim2.fromScale(0.27, 0.04),
		Size = UDim2.fromScale(0.46, 0.4),
		Font = Enum.Font.LuckiestGuy,
		Text = "★",
		TextColor3 = GOLD_LIGHT,
	})
	for i = 0, 8 do
		local theta = (i / 8 - 0.5) * math.pi * 0.9
		bulb(
			bulbs,
			base * CFrame.new(-math.sin(theta) * 4.4, SIGN_Y + 2.2 + math.cos(theta) * 4.4, -0.1),
			0.42,
			"Crest",
			i + 1
		)
	end
	local edgeBulbs = 20
	for i = 0, edgeBulbs - 1 do
		local x = (i / (edgeBulbs - 1) - 0.5) * (signWidth - 0.6)
		bulb(bulbs, base * CFrame.new(-x, SIGN_Y + 2.45, -0.45), 0.4, "Sign", i + 1)
		bulb(bulbs, base * CFrame.new(x, SIGN_Y - 2.45, -0.45), 0.4, "Sign", edgeBulbs + i + 1)
	end
	local signGui = surface(sign, Enum.NormalId.Front, Vector2.new(1245, 220))
	text(signGui, 6, {
		Position = UDim2.fromScale(0, 0.02),
		Size = UDim2.fromScale(1, 0.6),
		Font = Enum.Font.LuckiestGuy,
		Text = "TREASURE WHEEL",
		TextColor3 = Color3.fromRGB(255, 214, 90),
	})
	local status = text(signGui, 3, {
		Position = UDim2.fromScale(0.04, 0.63),
		Size = UDim2.fromScale(0.92, 0.32),
		Font = Enum.Font.GothamBold,
		RichText = true,
		Text = "Swim up to the big red button to spin!",
	})
	bulbs.Parent = model

	-- Light on the wheel's face (it reads at night)
	local lamp = part(model, {
		Name = "WheelLamp",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = base * CFrame.new(0, 2, -8),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 236, 200)
	light.Range = 20
	light.Brightness = 1.1
	light.Parent = lamp

	-- Podium with the big red button
	local podiumZ = -10
	part(model, {
		Name = "Podium",
		Size = Vector3.new(2.2, 3, 2.2),
		CFrame = floor * CFrame.new(0, STAGE_TOP + 1.5, podiumZ),
		Material = Enum.Material.SmoothPlastic,
		Color = CRIMSON,
	})
	local podiumFront = part(model, {
		Name = "PodiumFace",
		Size = Vector3.new(2, 1.2, 0.05),
		CFrame = floor * CFrame.new(0, STAGE_TOP + 1.8, podiumZ - 1.13),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	text(surface(podiumFront, Enum.NormalId.Front, Vector2.new(200, 120)), 3, {
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.LuckiestGuy,
		Text = "SPIN!",
		TextColor3 = GOLD_LIGHT,
	})
	part(model, {
		Name = "PodiumFoot",
		Size = Vector3.new(2.7, 0.3, 2.7),
		CFrame = floor * CFrame.new(0, STAGE_TOP + 0.15, podiumZ),
		Material = Enum.Material.Foil,
		Color = GOLD,
	})
	part(model, {
		Name = "PodiumCap",
		Size = Vector3.new(2.7, 0.35, 2.7),
		CFrame = floor * CFrame.new(0, STAGE_TOP + 3.175, podiumZ),
		Material = Enum.Material.Foil,
		Color = GOLD,
	})
	part(model, {
		Name = "ButtonRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 2, 2),
		CFrame = upright(floor * CFrame.new(0, STAGE_TOP + 3.5, podiumZ)),
		Material = Enum.Material.Foil,
		Color = GOLD_LIGHT,
	})
	local button = part(model, {
		Name = "SpinButton",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.45, 1.6, 1.6),
		CFrame = upright(floor * CFrame.new(0, STAGE_TOP + 3.75, podiumZ)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 40, 60),
	})
	local buttonGlow = Instance.new("PointLight")
	buttonGlow.Color = Color3.fromRGB(255, 60, 70)
	buttonGlow.Range = 6
	buttonGlow.Brightness = 1
	buttonGlow.Parent = button

	-- Boards either side: the odds (slices are drawn equal) and where spins come from
	local total = 0
	for _, segment in segments do
		total += segment.weight
	end
	local odds: { BoardRow } = {}
	for _, segment in segments do
		table.insert(odds, {
			left = segment.label,
			right = `{math.floor(segment.weight / total * 1000 + 0.5) / 10}%`,
			color = segment.color,
		})
	end
	board(
		model,
		floor * CFrame.new(-17, 0, -7) * CFrame.Angles(0, math.rad(-25), 0),
		"PRIZES & ODDS",
		odds,
		"The jackpot: a Rare-or-better skin for the fish you swim as"
	)
	board(
		model,
		floor * CFrame.new(17, 0, -7) * CFrame.Angles(0, math.rad(25), 0),
		"FREE SPINS",
		spinRows,
		spinFooter
	)

	local disc = buildDisc(model, base, segments)
	buildFlapper(model, base)

	-- Stream the wheel in and out whole, so the client never holds half a disc
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	CollectionService:AddTag(model, TreasureWheel.TAG)
	model.Parent = parent
	return {
		model = model,
		disc = disc,
		base = base,
		button = button,
		status = status,
	}
end

return TreasureWheel
