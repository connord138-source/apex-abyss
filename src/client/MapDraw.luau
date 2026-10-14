--!strict
-- Draws the sea as a chart (owner, 2026-10-12: "need a map/mini map to show people
-- where they are"; 2026-10-14: "needs to be an actual accurate mini map not dots"):
-- the real seafloor seen from above (Config/Textures `mapChart`, made from the
-- Terrain's own fill ops by tools/map/make_chart.py: depth shading, relief,
-- contours), the biomes' borders dotted over it and the map's edge ring, north up.
-- Until the chart's id is in, every biome is a field of dots in its colour instead. The same chart serves the
-- HUD's minimap (a window that slides with the fish) and the full map (the whole
-- sea in a menu window, with the biomes' names and levels). Markers (you, your den,
-- a treasure X, the boss, other fish) sit on top and are moved every frame.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent.Ui)

local World = Config.World
local hub = World.hub

local MapDraw = {}

export type Map = {
	frame: Frame, -- the clipped square
	world: Frame, -- a point at the sea's origin; chart and markers hang off it in studs × scale
	scale: number, -- pixels per stud
	size: number, -- the frame's side in pixels
	marks: { [string]: TextLabel },
	blip: TextLabel,
}

local DOT_STEP = 95 -- studs between dots in a biome's field
local RING_STEP = 48 -- studs between dashes on a ring
local BORDER_STEP = 34 -- studs between dots on a biome's border
-- Studs from the middle to the chart image's edge (tools/map/make_chart.py SPAN)
local CHART_SPAN = 1600

local function dot(
	parent: Instance,
	x: number,
	z: number,
	scale: number,
	size: number,
	color: Color3,
	alpha: number
)
	local d = Instance.new("Frame")
	d.BackgroundColor3 = color
	d.BackgroundTransparency = alpha
	d.BorderSizePixel = 0
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Size = UDim2.fromOffset(size, size)
	d.Position = UDim2.fromOffset(x * scale, z * scale)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = d
	d.Parent = parent
end

-- Degrees round the hub from +X toward +Z (Config/Biomes), as a point
local function polar(radius: number, degrees: number): (number, number)
	local a = math.rad(degrees)
	return math.cos(a) * radius, math.sin(a) * radius
end

local function ring(
	parent: Instance,
	radius: number,
	scale: number,
	size: number,
	color: Color3,
	alpha: number
)
	local count = math.max(12, math.floor(2 * math.pi * radius / RING_STEP))
	for i = 1, count do
		local x, z = polar(radius, (i / count) * 360)
		dot(parent, x, z, scale, size, color, alpha)
	end
end

-- The chart: biome dot fields, the hub, the drop-off, the edge
local function chart(world: Frame, scale: number, dotPx: number)
	for _, biome in Config.Biomes.list do
		if not biome.live then
			continue
		end
		local from, to = biome.angleFrom, biome.angleTo
		if to <= from then
			to += 360 -- a sector that crosses 0 (the reef runs 225 round to 135)
		end
		local inner = math.max(biome.radiusFrom, hub.radius + 40)
		local r = inner + DOT_STEP * 0.5
		local alpha = if biome.deep then 0.5 else 0.42
		while r < biome.radiusTo do
			local arc = math.rad(to - from) * r
			local count = math.max(1, math.floor(arc / DOT_STEP))
			for i = 1, count do
				local degrees = from + (to - from) * ((i - 0.5) / count)
				local x, z = polar(r, degrees)
				dot(world, x, z, scale, dotPx, biome.color, alpha)
			end
			r += DOT_STEP
		end
	end
	-- The hub: a solid ring with its dens, and the drop-off and edge as dashes
	ring(world, hub.radius + hub.wallThickness, scale, math.max(2, dotPx - 1), Ui.color.text, 0.35)
	ring(world, World.shelf.radius, scale, math.max(2, dotPx - 1), Ui.color.text, 0.72)
	ring(world, World.boundsRadius, scale, math.max(2, dotPx - 1), Ui.color.danger, 0.6)
end

-- The chart image: the real seafloor, `CHART_SPAN` studs each way from the middle
-- (false while its id isn't in)
local function chartImage(world: Frame, scale: number): boolean
	local id = (Config.Textures :: any).mapChart
	if typeof(id) ~= "number" or id <= 0 then
		return false
	end
	local image = Instance.new("ImageLabel")
	image.Name = "Chart"
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = `rbxassetid://{id}`
	image.ScaleType = Enum.ScaleType.Stretch
	image.Size = UDim2.fromOffset(2 * CHART_SPAN * scale, 2 * CHART_SPAN * scale)
	image.Position = UDim2.fromOffset(-CHART_SPAN * scale, -CHART_SPAN * scale)
	image.ZIndex = 0
	image.Parent = world
	return true
end

-- The biomes' borders, dotted over the chart: the shallows' outer arc, the radial
-- edges between neighbouring sectors, and the map's edge
local function borders(world: Frame, scale: number, dotPx: number)
	local function line(r0: number, r1: number, degrees: number)
		local r = r0
		while r <= r1 do
			local x, z = polar(r, degrees)
			dot(world, x, z, scale, dotPx, Ui.color.text, 0.55)
			r += BORDER_STEP
		end
	end
	local function arc(radius: number, from: number, to: number)
		if to <= from then
			to += 360
		end
		local count = math.max(2, math.floor(math.rad(to - from) * radius / BORDER_STEP))
		for i = 0, count do
			local x, z = polar(radius, from + (to - from) * i / count)
			dot(world, x, z, scale, dotPx, Ui.color.text, 0.55)
		end
	end
	for _, biome in Config.Biomes.list do
		if not biome.live then
			continue
		end
		if biome.radiusFrom == 0 then
			arc(biome.radiusTo, 0, 360)
		elseif not (biome.angleFrom == 0 and biome.angleTo == 360) then
			line(biome.radiusFrom, biome.radiusTo, biome.angleFrom)
		end
	end
	ring(world, World.boundsRadius, scale, math.max(2, dotPx), Ui.color.danger, 0.45)
end

-- The biomes' names and levels at their sectors' middles (the full map)
local function labels(world: Frame, scale: number)
	for _, biome in Config.Biomes.list do
		if not biome.live then
			continue
		end
		local from, to = biome.angleFrom, biome.angleTo
		if to <= from then
			to += 360
		end
		local mid = (from + to) / 2
		local radius = (math.max(biome.radiusFrom, hub.radius + 40) + biome.radiusTo) / 2
		if biome.radiusFrom == 0 then
			radius = (biome.radiusTo + hub.radius + 40) / 2
			mid = 300 -- the kelp ring's name sits to the north-west of the hub
		elseif biome.id == "HydrothermalVents" then
			-- Its sector wraps round the wreck bay's: at the middle (175°) its name lay
			-- on the Shipwreck Graveyard's level line (PC playtest 2026-10-14, M1)
			mid = 150
		end
		local x, z = polar(radius, mid)
		local holder = Instance.new("Frame")
		holder.Name = biome.id
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Size = UDim2.fromOffset(150, 34)
		holder.Position = UDim2.fromOffset(x * scale, z * scale)
		holder.Parent = world
		local name = Ui.label(
			holder,
			"Name",
			string.upper(biome.name),
			Ui.FONT_HEAVY,
			13,
			biome.color,
			UDim2.new(1, 0, 0, 16)
		)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.TextStrokeTransparency = 0.4
		local level = Ui.label(
			holder,
			"Level",
			`LV {biome.minLevel}–{biome.maxLevel}`,
			Ui.FONT_BOLD,
			11,
			Ui.color.text,
			UDim2.new(1, 0, 0, 14),
			UDim2.fromOffset(0, 17)
		)
		level.TextXAlignment = Enum.TextXAlignment.Center
		level.TextStrokeTransparency = 0.5
	end
	local hubLabel = Ui.label(world, "Hub", "HUB", Ui.FONT_HEAVY, 12, Ui.color.text, UDim2.fromOffset(60, 16))
	hubLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	hubLabel.Position = UDim2.fromOffset(0, 0)
	hubLabel.TextXAlignment = Enum.TextXAlignment.Center
	hubLabel.TextStrokeTransparency = 0.4
end

-- Builds a chart `size` pixels square at `scale` pixels per stud under `parent`
-- (its position is the caller's). `named` adds the biomes' names (the full map).
function MapDraw.new(parent: Instance, size: number, scale: number, named: boolean): Map
	local frame = Instance.new("Frame")
	frame.Name = "Map"
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundColor3 = Color3.fromRGB(3, 14, 26)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	Ui.corner(frame, UDim.new(0, if named then 12 else 16))
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(10, 36, 60), Color3.fromRGB(2, 8, 16))
	gradient.Parent = frame
	local world = Instance.new("Frame")
	world.Name = "World"
	world.BackgroundTransparency = 1
	world.Size = UDim2.fromOffset(0, 0)
	world.Position = UDim2.fromOffset(size / 2, size / 2)
	world.Parent = frame
	if chartImage(world, scale) then
		borders(world, scale, if named then 2 else 3)
	else
		chart(world, scale, if named then 4 else 5)
	end
	if named then
		labels(world, scale)
	end
	-- You: an arrow at the fish, turned to its heading
	local blip = Ui.label(
		world,
		"You",
		"▲",
		Ui.FONT_HEAVY,
		if named then 18 else 20,
		Ui.color.accent,
		UDim2.fromOffset(24, 24)
	)
	blip.AnchorPoint = Vector2.new(0.5, 0.5)
	blip.TextXAlignment = Enum.TextXAlignment.Center
	blip.TextYAlignment = Enum.TextYAlignment.Center
	blip.TextStrokeTransparency = 0.3
	blip.ZIndex = 5
	frame.Parent = parent
	return { frame = frame, world = world, scale = scale, size = size, marks = {}, blip = blip }
end

-- Moves the fish's blip, and for a sliding chart (the minimap) the world under it,
-- so the fish stays in the middle
function MapDraw.update(map: Map, position: Vector3, heading: Vector3, slide: boolean)
	local x, z = position.X * map.scale, position.Z * map.scale
	map.blip.Position = UDim2.fromOffset(x, z)
	local flat = Vector2.new(heading.X, heading.Z)
	if flat.Magnitude > 1e-3 then
		-- ▲ points up (north, -Z); a heading of +X turns it clockwise a quarter
		map.blip.Rotation = math.deg(math.atan2(flat.X, -flat.Y))
	end
	if slide then
		map.world.Position = UDim2.fromOffset(map.size / 2 - x, map.size / 2 - z)
	end
end

-- Puts a marker at a position (made on first use), or moves it
function MapDraw.mark(map: Map, id: string, position: Vector3, color: Color3, text: string, size: number?)
	local label: TextLabel? = map.marks[id]
	if label == nil then
		local made = Ui.label(map.world, id, text, Ui.FONT_HEAVY, size or 14, color, UDim2.fromOffset(22, 22))
		made.AnchorPoint = Vector2.new(0.5, 0.5)
		made.TextXAlignment = Enum.TextXAlignment.Center
		made.TextYAlignment = Enum.TextYAlignment.Center
		made.TextStrokeTransparency = 0.35
		made.ZIndex = 4
		map.marks[id] = made
		label = made
	end
	assert(label)
	if label.TextColor3 ~= color then
		label.TextColor3 = color
	end
	label.Position = UDim2.fromOffset(position.X * map.scale, position.Z * map.scale)
end

function MapDraw.unmark(map: Map, id: string)
	local mark = map.marks[id]
	if mark then
		mark:Destroy()
		map.marks[id] = nil
	end
end

-- Clears every marker whose id isn't in `keep`
function MapDraw.prune(map: Map, keep: { [string]: boolean })
	for id, mark in map.marks do
		if not keep[id] then
			mark:Destroy()
			map.marks[id] = nil
		end
	end
end

return MapDraw
