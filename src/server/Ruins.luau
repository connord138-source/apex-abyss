--!strict
-- The Sunken Ruins (owner, 2026-10-18: "Sunken ruins need an extreme update with
-- the structures and detail. Very crude down there"), after the approved concept
-- assets/concepts/BiomeSunkenRuins.jpg: a drowned city on the deep floor east of the
-- hub, built from parts on the ground Shelf.luau lays for it (a pale sand plain,
-- drifts, the courtyard's pit; Config/Ruins holds the layout).
--
--   * The GREAT TEMPLE: a stepped platform with a grand stair, a peristyle of fluted
--     columns (some whole under their architraves, some snapped, two fallen and
--     rolled off the platform), its pediment fallen in front, and a cella with a
--     doorway, windows and glyph panels round a cold glowing brazier and the broken
--     legs of the god's statue. Its head lies toppled by the steps; a giant hand
--     rises out of the sand at the corner.
--   * The PROCESSIONAL AVENUE to it: paved, lined with columns standing, broken and
--     fallen across it, four sea-dragon guardians and glowing lamp obelisks, entered
--     through a triple-arched GATEWAY by the drop-off's foot, with an obelisk
--     standing and one toppled outside it.
--   * A ruined THEATRE (tiers of seats round a mosaic orchestra, part of the cavea
--     collapsed, a stage of broken columns, arches standing behind) and the SUNKEN
--     COURTYARD (stairs down into a walled pit: niches, urns, a glowing fountain, a
--     column fallen against the wall) either side of it.
--   * The BACK QUARTER behind the temple: a colonnade, houses with windows and
--     doorways, a toppled obelisk, a shrine of glyph steles.
--   * Fifteen smaller ruins over the rest of the biome (gateways, colonnades, houses,
--     round shrines, obelisks, a colossus's feet, steles), boulders, and coral,
--     sponges, anemones, moss and sea grass growing on all of it.
--
-- Stone is solid (fish bump into it, the camera stays out, and it lives under
-- Workspace.World.Biomes.Ruins, where Shared/Ground looks: no shell, forage or dig
-- site spawns in it, predators climb over it and the prey schools are lifted over
-- it). Big stones wear the toon Marble or Slate plates; small built pieces are
-- SmoothPlastic, glyphs faint Neon, and decor neither collides nor takes camera rays.
-- Arches, the avenue, the doorways and the courtyard's stairs are wide enough for a
-- LV 100 fish (tools/preview/run_ruins.sh checks every swim line). The hero props
-- (ruins_glb: RuinHead, RuinHand, RuinGuardian, RuinUrn, RuinCapital, RuinStele) are
-- fitted over their part-built stand-ins once imported (Props.dress).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Props = require(ReplicatedStorage.Shared.Props)
local Decor = require(script.Parent.Decor)

local World = Config.World
local Layout = Config.Ruins
local COLORS = Layout.colors
local GLYPH = Layout.glyph

local Ruins = {}

export type Ground = (x: number, z: number) -> (Vector3?, Vector3?)
export type Pass = { label: string, points: { Vector3 } }
export type Stats = {
	parts: number,
	solid: number,
	glow: number,
	lights: number,
	emitters: number,
	props: number,
	standins: number,
	tidied: number,
}
type Spot = { at: CFrame, size: number, foot: boolean }
type Footprint = { frame: CFrame, hx: number, hz: number }

-- The swim lines a LV 100 fish must get through (the gateway, the avenue, the
-- temple's door, the courtyard's stairs, the doorways and gates out in the biome),
-- filled by `build` for the preview's check
Ruins.passes = {} :: { Pass }

local HALF = math.pi / 2
local TAU = math.pi * 2
local SMOOTH = Enum.Material.SmoothPlastic
local MARBLE = Enum.Material.Marble
local SLATE = Enum.Material.Slate
-- Tripo props face +X in the GLB, and Studio turns a GLB half round, so a quarter
-- turn puts their front on the frame's look (as Plaza.luau's GLB_FRONT)
local GLB_FRONT = CFrame.Angles(0, -HALF, 0)

local rng = Random.new(World.seed + 61)
local groundOf: Ground = function(_x: number, _z: number): (Vector3?, Vector3?)
	return nil, nil
end
local city = CFrame.identity
local spots: { Spot } = {}
local footprints: { Footprint } = {}
local stats: Stats =
	{ parts = 0, solid = 0, glow = 0, lights = 0, emitters = 0, props = 0, standins = 0, tidied = 0 }

-- ---------------------------------------------------------------------------
-- Parts
-- ---------------------------------------------------------------------------

local function groundY(x: number, z: number): number
	local hit = groundOf(x, z)
	return if hit then hit.Y else World.deep.floorY
end

-- The toon plates read only on big faces: a stone takes them when its two largest
-- sides are big, else it's SmoothPlastic (owner, 2026-10-17: small pieces in a toon
-- material looked "fuzzy, cheap")
local function toonFor(size: Vector3, toon: Enum.Material): Enum.Material
	local big = math.max(size.X, size.Y, size.Z)
	local small = math.min(size.X, size.Y, size.Z)
	local middle = size.X + size.Y + size.Z - big - small
	return if middle >= 8 and big >= 12 then toon else SMOOTH
end

local function setup(p: BasePart, name: string, size: Vector3, cframe: CFrame, color: Color3, solid: boolean)
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	p.CanCollide = solid
	p.CanQuery = solid
	p.CastShadow = solid and math.max(size.X, size.Y, size.Z) >= 4
	stats.parts += 1
	if solid then
		stats.solid += 1
	end
end

-- A stone: solid (fish bump into it, the camera stays out); `material` forces one,
-- else big ones take the toon Marble
local function stone(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	setup(p, name, size, cframe, color, true)
	p.Material = material or toonFor(size, MARBLE)
	p.Parent = parent
	return p
end

-- Paving and floors: Slate plates when big
local function paving(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	return stone(parent, name, size, cframe, color, toonFor(size, SLATE))
end

-- Decor: neither collides nor takes camera rays
local function trim(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	setup(p, name, size, cframe, color, false)
	p.Material = SMOOTH
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- A carved glyph or a glowing inlay: faint Neon
local function glow(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3?): Part
	local p = trim(parent, name, size, cframe, color or GLYPH.color)
	p.Material = Enum.Material.Neon
	p.Transparency = GLYPH.transparency
	stats.glow += 1
	return p
end

local function wedge(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	solid: boolean
): WedgePart
	local p = Instance.new("WedgePart")
	setup(p, name, size, cframe, color, solid)
	p.Material = SMOOTH
	p.Parent = parent
	return p
end

-- An upright cylinder standing on `base` (its up), `height` tall
local function drum(
	parent: Instance,
	name: string,
	base: CFrame,
	height: number,
	radius: number,
	color: Color3,
	solid: boolean
): Part
	local p = if solid
		then stone(
			parent,
			name,
			Vector3.new(height, radius * 2, radius * 2),
			base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, HALF),
			color,
			SMOOTH
		)
		else trim(
			parent,
			name,
			Vector3.new(height, radius * 2, radius * 2),
			base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, HALF),
			color
		)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A cylinder from `a` to `b`
local function rod(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	radius: number,
	color: Color3,
	solid: boolean
): Part
	local frame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, HALF, 0)
	local size = Vector3.new((b - a).Magnitude, radius * 2, radius * 2)
	local p = if solid
		then stone(parent, name, size, frame, color, SMOOTH)
		else trim(parent, name, size, frame, color)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(
	parent: Instance,
	name: string,
	center: Vector3,
	diameter: number,
	color: Color3,
	solid: boolean
): Part
	local p = if solid
		then stone(parent, name, Vector3.one * diameter, CFrame.new(center), color, SMOOTH)
		else trim(parent, name, Vector3.one * diameter, CFrame.new(center), color)
	p.Shape = Enum.PartType.Ball
	return p
end

-- A rounded lump filling `size` (a sphere mesh on a decor block)
local function blob(parent: Instance, name: string, cframe: CFrame, size: Vector3, color: Color3): Part
	local p = trim(parent, name, size, cframe, color)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function pick(list: { Color3 }): Color3
	return list[rng:NextInteger(1, #list)]
end

local function light(holder: BasePart, range: number?, brightness: number?)
	local made = Instance.new("PointLight")
	made.Color = Layout.light.color
	made.Range = range or Layout.light.range
	made.Brightness = brightness or Layout.light.brightness
	made.Shadows = false
	made.Parent = holder
	stats.lights += 1
end

-- Slow pale motes rising off a glow (a brazier, the fountain)
local function motes(holder: BasePart, rate: number, up: Enum.NormalId)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Motes"
	emitter.EmissionDirection = up
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(6, 10)
	emitter.Speed = NumberRange.new(0.6, 1.6)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.Acceleration = Vector3.new(0, 0.25, 0)
	emitter.Drag = 0.4
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.4, 0.32),
		NumberSequenceKeypoint.new(1, 0.08),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(Layout.light.color)
	emitter.LightEmission = 0.9
	emitter.LightInfluence = 0
	emitter.Parent = holder
	stats.emitters += 1
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- ---------------------------------------------------------------------------
-- Sites, footprints, growth
-- ---------------------------------------------------------------------------

-- A frame on the ground at (x, z) in `base`'s frame, turned `yaw` about its up, at
-- the lowest ground under a box hx by hz round it (nothing floats; stone sinks into
-- the sand instead)
local function siteAt(base: CFrame, x: number, z: number, yaw: number, hx: number?, hz: number?): CFrame
	local frame = base * CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
	local p = frame.Position
	local y = groundY(p.X, p.Z)
	if hx and hz then
		for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			local q = frame * Vector3.new(c[1] * hx, 0, c[2] * hz)
			y = math.min(y, groundY(q.X, q.Z))
		end
	end
	return CFrame.new(p.X, y, p.Z) * frame.Rotation
end

local function floorAt(p: Vector3): Vector3
	return Vector3.new(p.X, groundY(p.X, p.Z), p.Z)
end

-- The ground a ruin covers (the outlying ruins and boulders keep out of it; the
-- seeps and plankton other dressing scattered there are cleared)
local function claim(frame: CFrame, hx: number, hz: number)
	table.insert(footprints, { frame = frame, hx = hx, hz = hz })
end

local function claimed(p: Vector3, pad: number): boolean
	for _, f in footprints do
		local q = f.frame:PointToObjectSpace(p)
		if math.abs(q.X) <= f.hx + pad and math.abs(q.Z) <= f.hz + pad then
			return true
		end
	end
	return false
end

-- Somewhere coral, sponges, moss or sea grass may grow: on a stone's top (`at`
-- upright on it) or at a stone's foot on the sand
local function spot(at: CFrame, size: number, foot: boolean?)
	table.insert(spots, { at = at, size = size, foot = foot == true })
end

local function pass(label: string, points: { Vector3 })
	table.insert(Ruins.passes, { label = label, points = points })
end

-- ---------------------------------------------------------------------------
-- Glyphs
-- ---------------------------------------------------------------------------

-- Strokes on a 2 x 2 cell (x0, y0, x1, y1): a rune-like script of stems, twigs,
-- chevrons and diamonds (no crosses or plain letters: on a column a "+" read as a
-- first-aid sign)
local GLYPHS: { { { number } } } = {
	{ { -0.6, -1, -0.6, 1 }, { -0.6, 1, 0.8, 0.3 }, { -0.6, 0.2, 0.8, -0.5 } },
	{ { 0, -1, 0, 1 }, { 0, 0.2, -0.9, 1 }, { 0, 0.2, 0.9, 1 } },
	{ { -0.9, -1, -0.2, 1 }, { -0.2, 1, 0.9, -1 } },
	{ { -0.6, -1, -0.6, 1 }, { -0.6, 0.6, 0.6, 0 }, { 0.6, 0, -0.6, -0.6 } },
	{ { 0, -1, 0, 1 }, { 0, 1, -0.8, 0.4 }, { 0, 1, 0.8, 0.4 } },
	{ { -1, 0, 0, 0.8 }, { 0, 0.8, 1, 0 }, { 1, 0, 0, -0.8 }, { 0, -0.8, -1, 0 } },
	{ { -1, 1, -1, -1 }, { 1, 1, 1, -1 }, { -1, 1, 1, -1 }, { -1, -1, 1, 1 } },
	{ { 0, 1, 0, -1 }, { 0, 1, 0.7, 0.5 }, { 0, -1, -0.7, -0.5 } },
	{ { -1, 0, -0.5, 0.7 }, { -0.5, 0.7, 0, 0 }, { 0, 0, 0.5, 0.7 }, { 0.5, 0.7, 1, 0 } },
	{ { -1, -0.7, 0, 0.3 }, { 0, 0.3, 1, -0.7 }, { 0, 0.3, 0, 1 } },
	{ { -1, 1, 0.6, 1 }, { 0.6, 1, 0.6, -1 }, { 0.6, -1, -0.3, -1 }, { -0.3, -1, -0.3, 0.2 } },
	{ { -1, -1, 1, 1 }, { -1, 1, 0, 0 }, { 0.4, -0.6, 1, -1 } },
}

-- One glyph on a face (`face` on the stone's surface, looking out of it)
local function glyph(parent: Instance, face: CFrame, size: number)
	local w = GLYPH.stroke
	for _, s in GLYPHS[rng:NextInteger(1, #GLYPHS)] do
		local a = Vector3.new(s[1], s[2], 0) * (size / 2)
		local b = Vector3.new(s[3], s[4], 0) * (size / 2)
		local d = b - a
		local mid = (a + b) / 2
		glow(
			parent,
			"Glyph",
			Vector3.new(d.Magnitude + w, w, 0.24),
			face * CFrame.new(mid.X, mid.Y, -0.08) * CFrame.Angles(0, 0, math.atan2(d.Y, d.X))
		)
	end
end

-- A dark panel of glyphs cols x rows cut into a face
local function glyphPanel(parent: Instance, face: CFrame, cols: number, rows: number, size: number?)
	local s = size or GLYPH.size
	local gap = s * 0.42
	local w = cols * s + (cols + 1) * gap
	local h = rows * s + (rows + 1) * gap
	trim(parent, "GlyphPanel", Vector3.new(w, h, 0.3), face * CFrame.new(0, 0, -0.05), COLORS.inset)
	for i = 1, cols do
		for j = 1, rows do
			local x = -w / 2 + gap + s / 2 + (i - 1) * (s + gap)
			local y = h / 2 - gap - s / 2 - (j - 1) * (s + gap)
			glyph(parent, face * CFrame.new(x, y, -0.2), s)
		end
	end
end

-- A band round a column (`axis` at the band's middle, its up along the column)
-- with glowing glyphs round it
local function glyphRing(parent: Instance, axis: CFrame, radius: number, marks: number)
	drum(parent, "GlyphBand", axis * CFrame.new(0, -1.1, 0), 2.2, radius, COLORS.inset, false)
	for k = 1, marks do
		local a = (k / marks) * TAU + rng:NextNumber(-0.12, 0.12)
		glyph(parent, axis * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(radius + 0.02)), 1.3)
	end
end

-- ---------------------------------------------------------------------------
-- Building blocks
-- ---------------------------------------------------------------------------

export type ColumnOpts = { radius: number, height: number, keep: number, band: number?, color: Color3? }

-- A fluted column on `base` (on the ground or a platform): a square plinth, a round
-- base, the shaft (a cylinder with two square prisms 45 degrees apart round it:
-- eight ridges, fluting in the low-poly style) and an Ionic capital. `keep` is how
-- much of the shaft still stands (0: only the stub; under 1: snapped, its break
-- tilted on top). Returns the middle of its capital's top when it stands whole.
local function column(parent: Instance, base: CFrame, o: ColumnOpts): Vector3?
	local r, h = o.radius, o.height
	local color = o.color or COLORS.marble
	stone(parent, "Plinth", Vector3.new(r * 2.8, 2.4, r * 2.8), base * CFrame.new(0, 0.2, 0), COLORS.shade)
	drum(parent, "ColumnBase", base * CFrame.new(0, 1.4, 0), 1.2, r * 1.22, color, true)
	if o.keep <= 0 then
		drum(parent, "Stub", base * CFrame.new(0, 2.6, 0), r * 0.8, r, color, true)
		spot(base * CFrame.new(0, 2.6 + r * 0.8, 0), r)
		return nil
	end
	local y0 = 2.6
	local shaft = h * o.keep
	drum(parent, "Shaft", base * CFrame.new(0, y0, 0), shaft, r, color, true)
	for k = 0, 1 do
		stone(
			parent,
			"Flutes",
			Vector3.new(r * 1.64, shaft, r * 1.64),
			base * CFrame.new(0, y0 + shaft / 2, 0) * CFrame.Angles(0, k * math.pi / 4, 0),
			color,
			SMOOTH
		)
	end
	if o.band and o.band * h < shaft - 2 then
		glyphRing(parent, base * CFrame.new(0, y0 + o.band * h, 0), r * 1.2, 3)
	end
	local top = y0 + shaft
	if o.keep < 1 then
		local tilt =
			CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, TAU), rng:NextNumber(-0.35, 0.35))
		drum(parent, "Break", base * CFrame.new(0, top - 0.8, 0) * tilt, r * 0.9, r * 0.84, color, true)
		wedge(
			parent,
			"Shard",
			Vector3.new(r * 1.1, r * 0.9, r * 0.7),
			base * CFrame.new(r * 0.35, top + r * 0.3, 0) * tilt,
			color,
			false
		)
		spot(base * CFrame.new(0, top + r * 0.4, 0), r)
		return nil
	end
	drum(parent, "Necking", base * CFrame.new(0, top - 1.8, 0), 0.8, r * 1.1, COLORS.teal, true)
	drum(parent, "Echinus", base * CFrame.new(0, top, 0), 1.4, r * 1.3, color, true)
	stone(
		parent,
		"Abacus",
		Vector3.new(r * 2.9, 1.5, r * 2.9),
		base * CFrame.new(0, top + 2.15, 0),
		color,
		SMOOTH
	)
	for side = -1, 1, 2 do
		rod(
			parent,
			"Volute",
			base * Vector3.new(side * r * 1.22, top + 0.8, -r * 1.35),
			base * Vector3.new(side * r * 1.22, top + 0.8, r * 1.35),
			r * 0.56,
			color,
			false
		)
	end
	local capTop = base * Vector3.new(0, top + 2.9, 0)
	spot(CFrame.new(capTop), r)
	return capTop
end

-- A fluted drum lying from `a` to `b`
local function lyingDrum(parent: Instance, a: Vector3, b: Vector3, radius: number, color: Color3)
	rod(parent, "Drum", a, b, radius, color, true)
	local frame = CFrame.lookAt((a + b) / 2, b)
	local spin = rng:NextNumber(0, math.pi / 4)
	for k = 0, 1 do
		stone(
			parent,
			"Flutes",
			Vector3.new(radius * 1.64, radius * 1.64, (b - a).Magnitude),
			frame * CFrame.Angles(0, 0, spin + k * math.pi / 4),
			color,
			SMOOTH
		)
	end
end

-- A capital lying where it rolled (the RuinCapital prop over a part-built one);
-- forward declaration, defined with the other hero props
local fallenCapital: (parent: Instance, at: Vector3, dir: Vector3, radius: number) -> ()

-- A column's drums where it fell: from `foot` (on the ground) along `dir` (flat),
-- each one turned a little, rolled apart and sunk into the sand, its capital last
local function fallenColumn(
	parent: Instance,
	foot: Vector3,
	dir: Vector3,
	radius: number,
	count: number,
	band: boolean?
)
	local along = 0
	local side = Vector3.new(-dir.Z, 0, dir.X)
	for i = 1, count do
		local len = radius * rng:NextNumber(1.7, 2.3)
		local drift = side * rng:NextNumber(-0.5, 0.5) * radius * (0.4 + i * 0.25)
		local mid = foot + dir * (along + len / 2) + drift
		local center = Vector3.new(mid.X, groundY(mid.X, mid.Z) + radius * 0.72, mid.Z)
		local turned = CFrame.Angles(0, rng:NextNumber(-0.14, 0.14), 0) * dir
		local a, b = center - turned * (len / 2), center + turned * (len / 2)
		lyingDrum(parent, a, b, radius, COLORS.marble)
		if band and i == 2 then
			glyphRing(parent, CFrame.lookAt(center, b) * CFrame.Angles(-HALF, 0, 0), radius * 1.2, 3)
		end
		spot(CFrame.new(center + Vector3.new(0, radius * 1.1, 0)), radius)
		along += len + rng:NextNumber(0.4, 2)
	end
	fallenCapital(parent, foot + dir * (along + radius * 1.4) + side * rng:NextNumber(-2, 2), dir, radius)
end

-- An architrave across two column tops (the middles of their abaci), a teal cornice
-- on it; `glyphs` (+1/-1: the side of its own X, looking from `a` to `b`) carves a
-- row of glyphs on that face
local function architrave(parent: Instance, a: Vector3, b: Vector3, depth: number, glyphs: number?): CFrame
	local mid = (a + b) / 2
	local frame = CFrame.lookAt(mid, b)
	local len = (b - a).Magnitude + depth
	stone(parent, "Architrave", Vector3.new(depth, 4.4, len), frame * CFrame.new(0, 2.2, 0), COLORS.marble)
	trim(
		parent,
		"Cornice",
		Vector3.new(depth + 1.2, 1, len + 1.2),
		frame * CFrame.new(0, 4.9, 0),
		COLORS.teal
	)
	spot(frame * CFrame.new(0, 5.4, rng:NextNumber(-len / 3, len / 3)), 2.5)
	if glyphs then
		glyphPanel(
			parent,
			frame * CFrame.new(glyphs * depth / 2, 2.2, 0) * CFrame.Angles(0, -glyphs * HALF, 0),
			math.max(math.floor(len / 5), 3),
			1,
			2
		)
	end
	return frame
end

export type ArchOpts = {
	span: number, -- the opening's width
	spring: number, -- where the round of the arch begins
	depth: number, -- through the arch
	pier: number, -- each pier's width
	ring: number?, -- the voussoirs' radial depth
	broken: boolean?, -- the right half of the ring and the attic have fallen
	skipPier: number?, -- -1 or 1: that side's pier belongs to the arch beside it
	keystone: boolean?, -- a glowing glyph and a light under the keystone
}

-- A round arch on `frame` (on the ground in the opening's middle, looking through
-- it): piers on bases with imposts, nine voussoirs (the keystone teal), blocks over
-- the piers and an attic course. Returns its keystone's height.
local function arch(parent: Instance, frame: CFrame, o: ArchOpts): number
	local half = o.span / 2
	local ring = o.ring or 3.6
	local spring = o.spring + 1.7 -- the impost's top
	local radius = half + ring / 2
	for side = -1, 1, 2 do
		if o.skipPier == side then
			continue
		end
		local x = side * (half + o.pier / 2)
		stone(
			parent,
			"PierBase",
			Vector3.new(o.pier + 1.6, 2.4, o.depth + 1.6),
			frame * CFrame.new(x, 0.2, 0),
			COLORS.shade
		)
		stone(
			parent,
			"Pier",
			Vector3.new(o.pier, o.spring, o.depth),
			frame * CFrame.new(x, o.spring / 2 + 1, 0),
			COLORS.marble
		)
		stone(
			parent,
			"Impost",
			Vector3.new(o.pier + 1.2, 1.4, o.depth + 1.2),
			frame * CFrame.new(x, o.spring + 1, 0),
			COLORS.teal,
			SMOOTH
		)
		if not (o.broken and side == 1) then
			stone(
				parent,
				"Spandrel",
				Vector3.new(o.pier, radius + ring / 2, o.depth),
				frame * CFrame.new(x, spring + (radius + ring / 2) / 2, 0),
				COLORS.marble
			)
		end
	end
	local count = 9
	for i = 1, count do
		if o.broken and i <= 4 then
			continue -- the right half fell (i counts from the right springing)
		end
		local t = (i - 0.5) / count * math.pi
		local key = i == math.ceil(count / 2)
		local size = Vector3.new(
			ring + (if key then 0.8 else 0),
			math.pi * radius / count * 1.06,
			o.depth + (if key then 0.6 else 0)
		)
		stone(
			parent,
			"Voussoir",
			size,
			frame
				* CFrame.new(math.cos(t) * radius, spring + math.sin(t) * radius, 0)
				* CFrame.Angles(0, 0, t),
			if key then COLORS.teal else COLORS.marble,
			SMOOTH
		)
	end
	local crown = spring + radius + ring / 2
	if o.keystone then
		local face = frame * CFrame.new(0, spring + radius, -(o.depth / 2 + 0.3))
		glyph(parent, face, 1.8)
		local holder = glow(
			parent,
			"KeyGlow",
			Vector3.new(1.6, 0.4, 1.6),
			frame * CFrame.new(0, spring + radius - ring / 2 - 0.3, 0)
		)
		light(holder, 50, 1.1)
	end
	if not o.broken then
		stone(
			parent,
			"Attic",
			Vector3.new(o.span + o.pier * 2 + 2, 3.4, o.depth + 1),
			frame * CFrame.new(0, crown + 1.7, 0),
			COLORS.marble
		)
		spot(frame * CFrame.new(rng:NextNumber(-half, half), crown + 3.4, 0), 2.5)
	else
		spot(frame * CFrame.new(-half - o.pier / 2, crown, 0), 2.5)
		-- its fallen voussoirs
		for _ = 1, 4 do
			local p = frame
				* Vector3.new(rng:NextNumber(half * 0.2, half * 2.2), 0, rng:NextNumber(-o.depth, o.depth))
			local g = floorAt(p)
			stone(
				parent,
				"Fallen",
				Vector3.new(ring, ring * 1.3, o.depth * rng:NextNumber(0.6, 1)),
				CFrame.new(g + Vector3.new(0, ring * 0.4, 0))
					* CFrame.Angles(
						rng:NextNumber(-0.5, 0.5),
						rng:NextNumber(0, TAU),
						rng:NextNumber(-0.5, 0.5)
					),
				COLORS.marble,
				SMOOTH
			)
		end
	end
	return crown
end

export type Opening = { x: number, w: number, y: number, h: number }
export type WallOpts = {
	length: number,
	height: number,
	thick: number,
	openings: { Opening }?,
	ragged: number?, -- how much of the height the top may have lost
	color: Color3?,
}

-- A wall on `frame` (on the ground at its middle, its X along the wall), cut into
-- strips at its openings' edges: each strip is stacked from the solid spans between
-- the openings (sills, piers, the courses over doors and windows), a teal lintel
-- and sill trim every opening, and a ragged top where it has broken down
local function wall(parent: Instance, frame: CFrame, o: WallOpts)
	local openings: { Opening } = o.openings or {}
	local length, height = o.length, o.height
	local color = o.color or COLORS.shade
	local edges = { -length / 2, length / 2 }
	for _, op in openings do
		table.insert(edges, math.clamp(op.x - op.w / 2, -length / 2, length / 2))
		table.insert(edges, math.clamp(op.x + op.w / 2, -length / 2, length / 2))
	end
	table.sort(edges)
	local material = toonFor(Vector3.new(length, height, o.thick), MARBLE)
	for i = 1, #edges - 1 do
		local x0, x1 = edges[i], edges[i + 1]
		if x1 - x0 < 0.05 then
			continue
		end
		local xm = (x0 + x1) / 2
		local cuts: { { number } } = {}
		for _, op in openings do
			if xm > op.x - op.w / 2 and xm < op.x + op.w / 2 then
				table.insert(cuts, { op.y, op.y + op.h })
			end
		end
		table.sort(cuts, function(a, b)
			return a[1] < b[1]
		end)
		local y = -1.5
		local spans: { { number } } = {}
		for _, cut in cuts do
			if cut[1] > y then
				table.insert(spans, { y, cut[1] })
			end
			y = math.max(y, cut[2])
		end
		if height > y then
			table.insert(spans, { y, height })
		end
		for _, s in spans do
			local top = s[2]
			if o.ragged and top >= height - 0.01 then
				top = math.max(s[1] + 1.5, height - rng:NextNumber(0, o.ragged) * height)
			end
			if top - s[1] > 0.2 then
				stone(
					parent,
					"Wall",
					Vector3.new(x1 - x0, top - s[1], o.thick),
					frame * CFrame.new(xm, (s[1] + top) / 2, 0),
					color,
					material
				)
				if top > 4 and x1 - x0 > 3 then
					spot(frame * CFrame.new(xm, top, 0), math.min((x1 - x0) / 2, 3))
				end
			end
		end
	end
	for _, op in openings do
		if op.y + op.h < height - 1 then
			trim(
				parent,
				"Lintel",
				Vector3.new(op.w + 2, 1.2, o.thick + 0.6),
				frame * CFrame.new(op.x, op.y + op.h + 0.6, 0),
				COLORS.teal
			)
		end
		if op.y > 1 then
			trim(
				parent,
				"Sill",
				Vector3.new(op.w + 1, 0.8, o.thick + 0.8),
				frame * CFrame.new(op.x, op.y - 0.3, 0),
				COLORS.teal
			)
		end
	end
	spot(
		frame
			* CFrame.new(
				rng:NextNumber(-length / 2, length / 2),
				0,
				(o.thick / 2 + 2) * (if rng:NextNumber() < 0.5 then -1 else 1)
			),
		3,
		true
	)
end

-- Cut stone and broken blocks scattered round `center` on the ground
local function rubble(
	parent: Instance,
	center: Vector3,
	radius: number,
	count: number,
	small: number,
	big: number
)
	for _ = 1, count do
		local a = rng:NextNumber(0, TAU)
		local d = math.sqrt(rng:NextNumber()) * radius
		local x, z = center.X + math.cos(a) * d, center.Z + math.sin(a) * d
		local s = rng:NextNumber(small, big)
		local size = Vector3.new(
			s * rng:NextNumber(0.8, 1.6),
			s * rng:NextNumber(0.5, 1),
			s * rng:NextNumber(0.8, 1.4)
		)
		local cf = CFrame.new(x, groundY(x, z) + size.Y * 0.28, z)
			* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, TAU), rng:NextNumber(-0.4, 0.4))
		local color = pick({ COLORS.marble, COLORS.shade, COLORS.weathered })
		if s >= 2.6 then
			stone(parent, "Rubble", size, cf, color, SMOOTH)
		else
			trim(parent, "Rubble", size, cf, color)
		end
	end
end

-- A ring of mosaic tiles on a floor (`center` upright on its top)
local function mosaicRing(
	parent: Instance,
	center: CFrame,
	radius: number,
	count: number,
	tile: number,
	colors: { Color3 }
)
	for k = 1, count do
		if rng:NextNumber() < 0.1 then
			continue -- lost tiles
		end
		local a = (k / count) * TAU
		trim(
			parent,
			"Tile",
			Vector3.new(tile, 0.3, tile * 0.8),
			center * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.12, -radius),
			colors[(k % #colors) + 1]
		)
	end
end

-- Rays of tiles from `inner` to `outer`
local function mosaicRays(
	parent: Instance,
	center: CFrame,
	inner: number,
	outer: number,
	count: number,
	color: Color3
)
	for k = 1, count do
		local a = (k / count) * TAU
		trim(
			parent,
			"Tile",
			Vector3.new(0.9, 0.28, outer - inner),
			center * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.12, -(inner + outer) / 2),
			color
		)
	end
end

-- An obelisk on `base`: stepped base, a shaft in three tapering blocks with a glyph
-- column down its front, a pyramidion of four wedges; `lit` rings its top in a
-- faint glow with a light
local function obelisk(
	parent: Instance,
	base: CFrame,
	height: number,
	width: number,
	lit: boolean,
	lamp: boolean?
)
	stone(
		parent,
		"ObeliskBase",
		Vector3.new(width * 2.2, 2.6, width * 2.2),
		base * CFrame.new(0, 0.3, 0),
		COLORS.shade
	)
	stone(
		parent,
		"ObeliskStep",
		Vector3.new(width * 1.6, 1.6, width * 1.6),
		base * CFrame.new(0, 2.4, 0),
		COLORS.marble
	)
	local y = 3.2
	local seg = height / 3
	local w = width
	for k = 0, 2 do
		w = width * (1 - 0.06 * k)
		stone(
			parent,
			"ObeliskShaft",
			Vector3.new(w, seg, w),
			base * CFrame.new(0, y + seg / 2, 0),
			COLORS.marble,
			SMOOTH
		)
		y += seg
	end
	glyphPanel(
		parent,
		base * CFrame.new(0, 3.2 + height * 0.5, -width * 0.45),
		1,
		math.max(math.floor(height / 9), 2),
		width * 0.42
	)
	if lamp then
		-- a lamp pillar: a glowing block under its pyramidion
		local cap =
			glow(parent, "LampGlow", Vector3.new(w * 0.9, 1.8, w * 0.9), base * CFrame.new(0, y + 0.9, 0))
		cap.Transparency = 0.12
		if lit then
			light(cap, 48, 1.1)
		end
		y += 1.8
	elseif lit then
		local band =
			glow(parent, "ObeliskGlow", Vector3.new(w + 0.3, 0.6, w + 0.3), base * CFrame.new(0, y - 1.2, 0))
		light(band, 44, 1)
	end
	local cap = w * 0.95
	for k = 0, 3 do
		wedge(
			parent,
			"Pyramidion",
			Vector3.new(cap, cap * 0.9, cap / 2),
			base
				* CFrame.new(0, y + cap * 0.45, 0)
				* CFrame.Angles(0, k * HALF, 0)
				* CFrame.new(0, 0, -cap / 4),
			COLORS.teal,
			true
		)
	end
	spot(base * CFrame.new(0, 2.6 + 0.8, -width * 0.9), 2, true)
end

-- An obelisk that fell along `dir` from `foot`: its base and stub stand, the shaft
-- lies in two pieces, the pyramidion beyond
local function toppled(parent: Instance, foot: CFrame, dir: Vector3, height: number, width: number)
	stone(
		parent,
		"ObeliskBase",
		Vector3.new(width * 2.2, 2.6, width * 2.2),
		foot * CFrame.new(0, 0.3, 0),
		COLORS.shade
	)
	local stub = height * 0.18
	stone(
		parent,
		"ObeliskStub",
		Vector3.new(width, stub, width),
		foot * CFrame.new(0, 1.6 + stub / 2, 0),
		COLORS.marble,
		SMOOTH
	)
	wedge(
		parent,
		"Shard",
		Vector3.new(width, width * 0.7, width * 0.6),
		foot * CFrame.new(0, 1.6 + stub + width * 0.35, 0) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
		COLORS.marble,
		true
	)
	local at = foot.Position + dir * (width * 1.6)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	for k = 1, 2 do
		local len = height * (if k == 1 then 0.42 else 0.32)
		local w = width * (1 - 0.12 * k)
		local mid = at + dir * (len / 2) + side * rng:NextNumber(-1.5, 1.5)
		local g = groundY(mid.X, mid.Z)
		local frame = CFrame.lookAt(
			Vector3.new(mid.X, g + w * 0.32, mid.Z),
			Vector3.new(mid.X, g + w * 0.32, mid.Z) + dir
		) * CFrame.Angles(
			rng:NextNumber(-0.05, 0.05),
			rng:NextNumber(-0.12, 0.12),
			rng:NextNumber(-0.3, 0.3)
		)
		stone(parent, "ObeliskPiece", Vector3.new(w, w, len), frame, COLORS.marble)
		if k == 1 then
			glyphPanel(
				parent,
				frame * CFrame.new(0, w / 2 + 0.02, 0) * CFrame.Angles(HALF, 0, 0),
				4,
				1,
				w * 0.45
			)
		end
		spot(frame * CFrame.new(0, w / 2, 0), w / 2)
		at += dir * (len + rng:NextNumber(1, 3))
	end
	local g = floorAt(at + dir * width)
	for k = 0, 1 do
		wedge(
			parent,
			"Pyramidion",
			Vector3.new(width * 0.8, width * 0.7, width * 0.4),
			CFrame.new(g + Vector3.new(0, width * 0.3, 0))
				* CFrame.Angles(0, rng:NextNumber(0, TAU), 1.2)
				* CFrame.Angles(0, k * math.pi, 0)
				* CFrame.new(0, 0, -width * 0.2),
			COLORS.teal,
			true
		)
	end
end

-- A bronze brazier with a cold glowing flame (the eerie lights the city still has)
local function brazier(parent: Instance, base: CFrame, size: number, range: number?): Part
	drum(parent, "BrazierFoot", base * CFrame.new(0, -0.4, 0), size * 0.5, size * 0.42, COLORS.bronze, true)
	drum(
		parent,
		"BrazierStem",
		base * CFrame.new(0, size * 0.1, 0),
		size * 0.7,
		size * 0.2,
		COLORS.bronze,
		true
	)
	drum(
		parent,
		"BrazierBowl",
		base * CFrame.new(0, size * 0.8, 0),
		size * 0.42,
		size * 0.62,
		COLORS.bronze,
		true
	)
	local flame =
		drum(parent, "BrazierGlow", base * CFrame.new(0, size * 1.2, 0), 0.4, size * 0.54, GLYPH.color, false)
	flame.Material = Enum.Material.Neon
	flame.Transparency = 0.15
	stats.glow += 1
	light(flame, range)
	motes(flame, 3, Enum.NormalId.Right) -- (a cylinder's axis, its X, points up)
	return flame
end

-- A lamp pillar along the avenue: a squat obelisk with a glowing block under its
-- pyramidion (every lamp glows; `lit` ones also cast light)
local function lampPillar(parent: Instance, base: CFrame, lit: boolean)
	obelisk(parent, base, 12, 4.4, lit, true)
end

-- ---------------------------------------------------------------------------
-- Hero props and their stand-ins
-- ---------------------------------------------------------------------------

-- A hero prop over its stand-in: the stand-in is built first (in a Standin model);
-- once WorldProps.<name> is imported, Props.dress fits it into the box (`box` its
-- middle, `size` in the model's own axes) and the stand-in goes
local function hero(parent: Instance, name: string, box: CFrame, size: Vector3, build: (Model) -> ()): Model
	local holder = model(parent, name)
	local standin = model(holder, "Standin")
	local parts, solid, glows = stats.parts, stats.solid, stats.glow
	build(standin)
	local anchor = Instance.new("Part")
	anchor.Name = name .. "Box"
	anchor.Anchored = true
	anchor.Size = size
	anchor.CFrame = box
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Parent = holder
	local dressed =
		Props.dress(anchor, name, { cframe = box, size = size, solid = true, blocksCamera = true })
	if dressed then
		standin:Destroy()
		stats.parts, stats.solid, stats.glow = parts, solid, glows
		stats.props += 1
	else
		stats.standins += 1
	end
	return holder
end

-- How far a box (`frame`, `size`) reaches below its middle
local function halfHeight(frame: CFrame, size: Vector3): number
	return math.abs(frame.RightVector.Y) * size.X / 2
		+ math.abs(frame.UpVector.Y) * size.Y / 2
		+ math.abs(frame.LookVector.Y) * size.Z / 2
end

-- The colossal statue's head, toppled: `pose` is turned (its look is where the face
-- looks, its up the top of the head) and stood on the ground at `at`, sunk `sink`
-- of its height. Stand-in: a boxy carved head with a wave-band crown, closed eyes,
-- a chipped nose, the neck's break.
local function statueHead(parent: Instance, at: Vector3, pose: CFrame, scale: number)
	local W, H, D = 0.627 * scale, scale, 0.605 * scale
	local turned = pose.Rotation
	local reach = halfHeight(turned, Vector3.new(W, H, D))
	local F = CFrame.new(floorAt(at) + Vector3.new(0, reach * 0.82, 0)) * turned
	hero(parent, "RuinHead", F * GLB_FRONT, Vector3.new(D, H, W), function(m: Model)
		local c = COLORS.marble
		stone(m, "Neck", Vector3.new(W * 0.62, H * 0.2, D * 0.66), F * CFrame.new(0, -H * 0.39, D * 0.06), c)
		stone(m, "Skull", Vector3.new(W * 0.9, H * 0.6, D * 0.84), F * CFrame.new(0, H * 0.01, D * 0.06), c)
		stone(
			m,
			"Crown",
			Vector3.new(W * 0.98, H * 0.12, D * 0.92),
			F * CFrame.new(0, H * 0.26, D * 0.05),
			COLORS.teal
		)
		stone(m, "Pate", Vector3.new(W * 0.8, H * 0.13, D * 0.76), F * CFrame.new(0, H * 0.38, D * 0.07), c)
		local face = F * CFrame.new(0, 0, -D * 0.36)
		trim(m, "Brow", Vector3.new(W * 0.8, H * 0.05, D * 0.1), face * CFrame.new(0, H * 0.1, -D * 0.03), c)
		for side = -1, 1, 2 do
			trim(
				m,
				"Eyelid",
				Vector3.new(W * 0.2, H * 0.028, 0.4),
				face * CFrame.new(side * W * 0.2, H * 0.05, -0.12),
				COLORS.dark
			)
			stone(
				m,
				"Ear",
				Vector3.new(W * 0.08, H * 0.2, D * 0.18),
				F * CFrame.new(side * W * 0.47, H * 0.0, D * 0.06),
				c,
				SMOOTH
			)
		end
		wedge(
			m,
			"Nose",
			Vector3.new(W * 0.13, H * 0.18, D * 0.13),
			face * CFrame.new(0, -H * 0.02, -D * 0.06),
			c,
			true
		)
		trim(
			m,
			"Lips",
			Vector3.new(W * 0.26, H * 0.035, 0.5),
			face * CFrame.new(0, -H * 0.14, -0.2),
			COLORS.weathered
		)
		stone(
			m,
			"Chin",
			Vector3.new(W * 0.46, H * 0.12, D * 0.12),
			face * CFrame.new(0, -H * 0.21, -D * 0.02),
			c,
			SMOOTH
		)
		trim(
			m,
			"Crack",
			Vector3.new(0.35, H * 0.34, 0.4),
			face * CFrame.new(W * 0.28, H * 0.04, -0.12) * CFrame.Angles(0, 0, 0.5),
			COLORS.dark
		)
		glyphPanel(m, F * CFrame.new(0, H * 0.26, -D * 0.51), 3, 1, H * 0.06)
	end)
	-- (coral grows round it on the sand: on the model's own surface it would float)
	spot(CFrame.new(floorAt(F * Vector3.new(0, 0, D * 0.8))), 4, true)
	spot(CFrame.new(floorAt(F * Vector3.new(0, H * 0.7, 0))), 4, true)
	claim(CFrame.new(F.Position), scale * 0.6, scale * 0.6)
end

-- A giant stone hand rising out of the sand, palm up, fingers curling
local function statueHand(parent: Instance, base: CFrame, scale: number)
	local W, H, D = 0.587 * scale, 0.813 * scale, scale
	local F = base * CFrame.new(0, H / 2 - H * 0.12, 0)
	hero(parent, "RuinHand", F, Vector3.new(W, H, D), function(m: Model)
		local c = COLORS.marble
		local foot = F * CFrame.new(0, -H / 2, 0)
		drum(m, "Wrist", foot, H * 0.34, W * 0.3, c, true)
		local palm = foot * CFrame.new(0, H * 0.32, 0) * CFrame.Angles(0.35, 0, 0)
		stone(
			m,
			"Palm",
			Vector3.new(W * 0.74, H * 0.34, D * 0.24),
			palm * CFrame.new(0, H * 0.17, 0),
			c,
			SMOOTH
		)
		for i = 1, 4 do
			local x = (i - 2.5) * W * 0.18
			local len = H * (if i == 1 or i == 4 then 0.18 else 0.22)
			local knuckle = palm * CFrame.new(x, H * 0.34, 0) * CFrame.Angles(-0.25, 0, 0)
			stone(
				m,
				"Finger",
				Vector3.new(W * 0.16, len, D * 0.15),
				knuckle * CFrame.new(0, len / 2, 0),
				c,
				SMOOTH
			)
			if i ~= 3 then -- one fingertip broke off
				local tip = knuckle
					* CFrame.new(0, len, 0)
					* CFrame.Angles(-0.5 - rng:NextNumber(0, 0.5), 0, 0)
				stone(
					m,
					"Finger",
					Vector3.new(W * 0.15, len * 0.8, D * 0.14),
					tip * CFrame.new(0, len * 0.4, 0),
					c,
					SMOOTH
				)
			end
		end
		local thumb = palm * CFrame.new(-W * 0.42, H * 0.1, 0) * CFrame.Angles(0, 0, 0.8)
		stone(
			m,
			"Thumb",
			Vector3.new(W * 0.17, H * 0.22, D * 0.16),
			thumb * CFrame.new(0, H * 0.11, 0),
			c,
			SMOOTH
		)
		trim(
			m,
			"Crack",
			Vector3.new(0.35, H * 0.22, 0.35),
			palm * CFrame.new(W * 0.15, H * 0.17, -D * 0.125) * CFrame.Angles(0, 0, 0.4),
			COLORS.dark
		)
	end)
	spot(base * CFrame.new(W * 0.2, 0, -D * 0.5), 4, true)
	spot(base * CFrame.new(-W * 0.5, 0, D * 0.3), 3, true)
	claim(base, W * 0.6, D * 0.6)
end

-- A sea-dragon guardian on its plinth, looking along `base`'s look, its eyes faintly
-- lit (the stand-in's)
local function guardian(parent: Instance, base: CFrame, scale: number)
	local W, H, D = 0.582 * scale, scale, 0.779 * scale
	local F = base * CFrame.new(0, H / 2 - 0.6, 0)
	hero(parent, "RuinGuardian", F, Vector3.new(W, H, D), function(m: Model)
		local c = COLORS.weathered
		local foot = F * CFrame.new(0, -H / 2, 0)
		stone(
			m,
			"GuardianPlinth",
			Vector3.new(W, H * 0.3, D),
			foot * CFrame.new(0, H * 0.15, 0),
			COLORS.shade,
			SMOOTH
		)
		trim(
			m,
			"PlinthBand",
			Vector3.new(W + 0.4, H * 0.04, D + 0.4),
			foot * CFrame.new(0, H * 0.26, 0),
			COLORS.teal
		)
		glyphPanel(m, foot * CFrame.new(0, H * 0.13, -D / 2), 2, 1, H * 0.07)
		local top = foot * CFrame.new(0, H * 0.3, 0)
		stone(
			m,
			"Haunch",
			Vector3.new(W * 0.62, H * 0.24, D * 0.44),
			top * CFrame.new(0, H * 0.12, D * 0.2),
			c,
			SMOOTH
		)
		stone(
			m,
			"Chest",
			Vector3.new(W * 0.56, H * 0.34, D * 0.3),
			top * CFrame.new(0, H * 0.2, -D * 0.12) * CFrame.Angles(-0.25, 0, 0),
			c,
			SMOOTH
		)
		local head = top * CFrame.new(0, H * 0.46, -D * 0.22)
		stone(m, "Head", Vector3.new(W * 0.42, H * 0.18, D * 0.3), head, c, SMOOTH)
		wedge(
			m,
			"Snout",
			Vector3.new(W * 0.32, H * 0.1, D * 0.2),
			head * CFrame.new(0, -H * 0.04, -D * 0.24),
			c,
			true
		)
		for side = -1, 1, 2 do
			glow(
				m,
				"Eye",
				Vector3.new(W * 0.07, H * 0.03, 0.3),
				head * CFrame.new(side * W * 0.12, H * 0.03, -D * 0.151)
			)
			stone(
				m,
				"Paw",
				Vector3.new(W * 0.16, H * 0.08, D * 0.22),
				top * CFrame.new(side * W * 0.18, H * 0.04, -D * 0.32),
				c,
				SMOOTH
			)
			wedge(
				m,
				"Fin",
				Vector3.new(0.5, H * 0.22, D * 0.28),
				top * CFrame.new(side * W * 0.3, H * 0.34, D * 0.05) * CFrame.Angles(0, math.pi, side * 0.5),
				COLORS.teal,
				false
			)
		end
		for k = 0, 2 do
			wedge(
				m,
				"Crest",
				Vector3.new(0.6, H * (0.18 - k * 0.03), D * 0.18),
				top
					* CFrame.new(0, H * (0.52 - k * 0.1), D * (-0.06 + k * 0.16))
					* CFrame.Angles(0, math.pi, 0),
				COLORS.teal,
				false
			)
		end
		rod(
			m,
			"Tail",
			top * Vector3.new(W * 0.2, H * 0.08, D * 0.38),
			top * Vector3.new(-W * 0.3, H * 0.05, D * 0.46),
			H * 0.05,
			c,
			false
		)
	end)
	spot(base * CFrame.new(W * 0.7, 0, 0), 2.5, true)
	claim(base, W * 0.6, D * 0.6)
end

-- A teal amphora; `tipped` lays it on its side
local function urn(parent: Instance, at: Vector3, scale: number, tipped: boolean)
	local W, H, D = 0.881 * scale, scale, 0.885 * scale
	local turn = CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
	if tipped then
		turn *= CFrame.Angles(0, 0, HALF * 0.92)
	end
	local reach = halfHeight(turn, Vector3.new(W, H, D))
	local F = CFrame.new(floorAt(at) + Vector3.new(0, reach * 0.9, 0)) * turn
	hero(parent, "RuinUrn", F, Vector3.new(W, H, D), function(m: Model)
		local color = pick(COLORS.urn)
		ball(m, "UrnBody", (F * CFrame.new(0, -H * 0.08, 0)).Position, W * 0.9, color, true)
		drum(m, "UrnNeck", F * CFrame.new(0, H * 0.2, 0), H * 0.24, W * 0.18, color, false)
		drum(m, "UrnRim", F * CFrame.new(0, H * 0.42, 0), H * 0.08, W * 0.28, COLORS.urn[2], false)
		drum(m, "UrnFoot", F * CFrame.new(0, -H * 0.5, 0), H * 0.1, W * 0.24, COLORS.dark, false)
	end)
end

-- A capital lying on its side where it rolled
fallenCapital = function(parent: Instance, at: Vector3, dir: Vector3, radius: number)
	local scale = radius * 3.1
	local X, Y, Z = scale, 0.957 * scale, 0.873 * scale
	local turn = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, 0, HALF * rng:NextNumber(0.85, 1.05))
	local reach = halfHeight(turn, Vector3.new(X, Y, Z))
	local F = CFrame.new(floorAt(at) + Vector3.new(0, reach * 0.85, 0)) * turn
	hero(parent, "RuinCapital", F, Vector3.new(X, Y, Z), function(m: Model)
		local c = COLORS.marble
		drum(m, "Stub", F * CFrame.new(0, -Y / 2, 0), Y * 0.42, radius, c, true)
		drum(m, "Echinus", F * CFrame.new(0, Y * 0.0, 0), Y * 0.16, radius * 1.3, c, true)
		stone(
			m,
			"Abacus",
			Vector3.new(X * 0.95, Y * 0.18, Z * 0.85),
			F * CFrame.new(0, Y * 0.33, 0),
			c,
			SMOOTH
		)
		for side = -1, 1, 2 do
			rod(
				m,
				"Volute",
				F * Vector3.new(side * X * 0.36, Y * 0.12, -Z * 0.42),
				F * Vector3.new(side * X * 0.36, Y * 0.12, Z * 0.42),
				Y * 0.17,
				c,
				false
			)
		end
	end)
	spot(CFrame.new(F.Position + Vector3.new(0, reach, 0)), radius)
end

-- A glyph stele facing along `base`'s look
local function stele(parent: Instance, base: CFrame, scale: number)
	local W, H, D = 0.707 * scale, scale, 0.315 * scale
	local F = base * CFrame.new(0, H / 2 - 0.5, 0)
	hero(parent, "RuinStele", F * GLB_FRONT, Vector3.new(D, H, W), function(m: Model)
		local foot = F * CFrame.new(0, -H / 2, 0)
		stone(
			m,
			"SteleFoot",
			Vector3.new(W * 1.15, H * 0.12, D * 1.3),
			foot * CFrame.new(0, H * 0.06, 0),
			COLORS.shade,
			SMOOTH
		)
		local slab = H * 0.62
		stone(
			m,
			"Stele",
			Vector3.new(W, slab, D * 0.62),
			foot * CFrame.new(0, H * 0.12 + slab / 2, 0),
			COLORS.weathered,
			SMOOTH
		)
		rod(
			m,
			"SteleTop",
			foot * Vector3.new(0, H * 0.12 + slab, -D * 0.31),
			foot * Vector3.new(0, H * 0.12 + slab, D * 0.31),
			W / 2,
			COLORS.weathered,
			true
		)
		glyphPanel(m, foot * CFrame.new(0, H * 0.12 + slab * 0.55, -D * 0.31), 2, 2, W * 0.22)
	end)
	spot(base * CFrame.new(0, 0, -D * 1.5), 2.5, true)
end

-- ---------------------------------------------------------------------------
-- The great temple, the avenue and the gateway (in the temple's frame: z along the
-- avenue, the front at -z toward the hub, x across)
-- ---------------------------------------------------------------------------

local TIERS = { { 104, 130 }, { 90, 116 }, { 76, 102 } } -- width (x), depth (z)
local TIER = 6
-- The peristyle round the top tier: x, z, how much stands (1 whole, 0 fallen), a
-- glyph band
type Standing = { x: number, z: number, keep: number, band: boolean? }
local PERISTYLE: { Standing } = {
	{ x = -32, z = -45, keep = 1, band = true },
	{ x = -14, z = -45, keep = 1 },
	{ x = 14, z = -45, keep = 0.55 },
	{ x = 32, z = -45, keep = 1, band = true },
	{ x = -32, z = -27, keep = 1 },
	{ x = -32, z = -9, keep = 1 },
	{ x = -32, z = 9, keep = 0.7 },
	{ x = -32, z = 27, keep = 1 },
	{ x = 32, z = -27, keep = 0.4, band = true },
	{ x = 32, z = -9, keep = 0 },
	{ x = 32, z = 9, keep = 1 },
	{ x = 32, z = 27, keep = 1 },
	{ x = -32, z = 45, keep = 1 },
	{ x = -14, z = 45, keep = 1, band = true },
	{ x = 14, z = 45, keep = 1 },
	{ x = 32, z = 45, keep = 0 },
}
-- Architraves still lying across whole columns (PERISTYLE indices), and the side
-- whose face carries glyphs (architrave's `glyphs`)
type Beam = { a: number, b: number, glyphs: number? }
local PERISTYLE_BEAMS: { Beam } = {
	{ a = 1, b = 2, glyphs = -1 },
	{ a = 1, b = 5 },
	{ a = 5, b = 6 },
	{ a = 13, b = 14 },
	{ a = 14, b = 15 },
	{ a = 11, b = 12 },
}

local function greatTemple(parent: Instance, T0: CFrame)
	local m = model(parent, "GreatTemple")
	local T = siteAt(T0, 0, 0, 0, 52, 65)
	claim(T * CFrame.new(0, 0, -6), 56, 76)

	-- The stepped platform: each tier four slabs with seams, settled a little; the
	-- front-left corner of the lower two has slumped into a tumble of blocks
	for k, t in TIERS do
		local w, d = t[1], t[2]
		local bottom = if k == 1 then -2.5 else (k - 1) * TIER
		local h = k * TIER - bottom
		for sx = -1, 1, 2 do
			for sz = -1, 1, 2 do
				local ww, dd, ox, oz = w / 2 - 0.5, d / 2 - 0.5, sx * w / 4, sz * d / 4
				if k <= 2 and sx == -1 and sz == -1 then
					local cutX, cutZ = 9 - k * 2, 11 - k * 2
					ww -= cutX
					dd -= cutZ
					ox += cutX / 2
					oz += cutZ / 2
				end
				stone(
					m,
					"Stylobate",
					Vector3.new(ww, h, dd),
					T
						* CFrame.new(ox, bottom + h / 2 + rng:NextNumber(-0.15, 0.15), oz)
						* CFrame.Angles(rng:NextNumber(-0.008, 0.008), 0, rng:NextNumber(-0.008, 0.008)),
					COLORS.shade
				)
			end
		end
		for side = -1, 1, 2 do
			trim(
				m,
				"TierLip",
				Vector3.new(w + 0.6, 0.9, 0.9),
				T * CFrame.new(0, k * TIER - 0.5, side * (d / 2 + 0.1)),
				COLORS.teal
			)
		end
		spot(T * CFrame.new(rng:NextNumber(-w / 2, w / 2), k * TIER, -d / 2 + 2), 2.5)
		spot(T * CFrame.new(-w / 2 + 2, k * TIER, rng:NextNumber(-d / 2, d / 2)), 2.5)
		spot(T * CFrame.new(w / 2 - 2, k * TIER, rng:NextNumber(-d / 2, d / 2)), 2.5)
	end
	rubble(m, T * Vector3.new(-46, 0, -58), 12, 8, 2.4, 5.5)
	glyphPanel(m, T * CFrame.new(34, 2.6, -65.05), 6, 1)
	glyphPanel(m, T * CFrame.new(0, 2.6, 65.05) * CFrame.Angles(0, math.pi, 0), 8, 1)
	for _ = 1, 4 do
		spot(
			CFrame.new(floorAt(T * Vector3.new(rng:NextNumber(-56, 56), 0, rng:NextNumber(-70, 70)))),
			5,
			true
		)
	end

	-- The grand stair up the front (and its cheek walls)
	for k = 1, 9 do
		local z0 = -78 + (k - 1) * 3
		stone(
			m,
			"Step",
			Vector3.new(30, k * 2 + 2.5, -51 - z0),
			T * CFrame.new(0, (k * 2 - 2.5) / 2, (z0 - 51) / 2),
			COLORS.marble
		)
	end
	for side = -1, 1, 2 do
		local a, b = T * Vector3.new(side * 16.6, 2.8, -79), T * Vector3.new(side * 16.6, 20.8, -51)
		stone(
			m,
			"Cheek",
			Vector3.new(3.2, 3.6, (b - a).Magnitude + 2),
			CFrame.lookAt((a + b) / 2, b),
			COLORS.shade
		)
	end

	-- The peristyle
	local tops: { [number]: Vector3 } = {}
	for i, c in PERISTYLE do
		local top = column(
			m,
			T * CFrame.new(c.x, 3 * TIER, c.z),
			{ radius = 3, height = 40, keep = c.keep, band = if c.band then 0.36 else nil }
		)
		if top then
			tops[i] = top
		end
	end
	for _, beam in PERISTYLE_BEAMS do
		local a, b = tops[beam.a], tops[beam.b]
		if a and b then
			architrave(m, a, b, 8.7, beam.glyphs)
		end
	end
	-- The back pediment still stands over the back row's left part, its right end
	-- broken off (a gable of two wedges on the architraves)
	local back = tops[13]
	if back then
		local eaves = back.Y + 5.4 - T.Y -- the cornice's top, in T
		local ridge = -9
		local pitch = 12 / 27.5
		wedge(
			m,
			"Pediment",
			Vector3.new(8.7, 12, 27.5),
			T * CFrame.new(ridge - 13.75, eaves + 6, 45) * CFrame.Angles(0, HALF, 0),
			COLORS.marble,
			true
		)
		-- the right half, broken off 15 studs out: a course under a shorter slope
		local cut = 12 - pitch * 15
		stone(
			m,
			"Pediment",
			Vector3.new(15, cut, 8.7),
			T * CFrame.new(ridge + 7.5, eaves + cut / 2, 45),
			COLORS.marble,
			SMOOTH
		)
		wedge(
			m,
			"Pediment",
			Vector3.new(8.7, 12 - cut, 15),
			T * CFrame.new(ridge + 7.5, eaves + cut + (12 - cut) / 2, 45) * CFrame.Angles(0, -HALF, 0),
			COLORS.marble,
			true
		)
		stone(
			m,
			"PedimentBreak",
			Vector3.new(3, cut + 1.5, 8.2),
			T * CFrame.new(ridge + 15.5, eaves + (cut + 1.5) / 2, 45) * CFrame.Angles(0, 0, 0.2),
			COLORS.marble,
			SMOOTH
		)
		glyphPanel(m, T * CFrame.new(-16, eaves + 3.4, 49.4) * CFrame.Angles(0, math.pi, 0), 4, 1, 1.8)
		spot(T * CFrame.new(ridge - 1, eaves + 12, 45), 2.5)
	end
	-- Roof slabs that fell into the cella and against its right side
	stone(
		m,
		"RoofSlab",
		Vector3.new(16, 2, 26),
		T * CFrame.new(-6, 26, 14) * CFrame.Angles(0.15, 0.3, 0.55),
		COLORS.shade
	)
	stone(
		m,
		"RoofSlab",
		Vector3.new(14, 2, 22),
		T * CFrame.new(26, 24, 20) * CFrame.Angles(0.1, -0.2, -0.75),
		COLORS.shade
	)
	-- Two columns fell off the platform: one rolled off the right side, one off the back
	fallenColumn(
		m,
		floorAt(T * Vector3.new(57, 0, -14)),
		(T.RightVector + T.LookVector * 0.15).Unit,
		3,
		5,
		true
	)
	fallenColumn(m, floorAt(T * Vector3.new(36, 0, 70)), (-T.LookVector + T.RightVector * 0.3).Unit, 3, 5)
	-- An architrave slid down the front, right of the stair
	do
		local a, b = T * Vector3.new(19, 19.5, -47), T * Vector3.new(31, 2, -77)
		stone(
			m,
			"FallenBeam",
			Vector3.new(8.7, 4.4, (b - a).Magnitude),
			CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, 0, 0.18),
			COLORS.marble
		)
	end
	-- The pediment lies in two halves on the sand at the front-left, its tympanum's
	-- glyphs still lit
	for k = 0, 1 do
		local at = floorAt(T * Vector3.new(-36 - k * 21, 0, -86 - k * 4))
		local turn = T.Rotation
			* CFrame.Angles(0, (k - 0.5) * 0.6 + 0.25 + k * math.pi, 0)
			* CFrame.Angles(0, 0, HALF * 0.82)
		local size = Vector3.new(5, 14, 36)
		local frame = CFrame.new(at + Vector3.new(0, halfHeight(turn, size) * 0.8, 0)) * turn
		wedge(m, "Pediment", size, frame, COLORS.marble, true)
		glyphPanel(m, frame * CFrame.new(2.55, -1, 4) * CFrame.Angles(0, -HALF, 0), 3, 1, 2.2)
		spot(CFrame.new(frame * Vector3.new(2.5, -3, -6)), 3)
	end

	-- The cella: a doorway in its front (with glyph columns either side), windows
	-- down its left wall, its right wall fallen at the back, and at the back the god's
	-- pedestal with its legs still standing
	local floorY = 3 * TIER
	local C = T * CFrame.new(0, floorY, 0)
	wall(m, C * CFrame.new(-14.5, 0, -27), { length = 9, height = 28, thick = 3 })
	wall(m, C * CFrame.new(14.5, 0, -27), { length = 9, height = 28, thick = 3 })
	stone(m, "DoorLintel", Vector3.new(24, 4, 3.6), C * CFrame.new(0, 26, -27), COLORS.teal)
	stone(
		m,
		"DoorCourse",
		Vector3.new(38, 2.4, 3.2),
		C * CFrame.new(-2, 29.2, -27) * CFrame.Angles(0, 0, 0.03),
		COLORS.shade
	)
	for side = -1, 1, 2 do
		glyphPanel(m, C * CFrame.new(side * 14.5, 14, -28.6), 1, 5, 2.2)
	end
	wall(m, C * CFrame.new(-18, 0, 3) * CFrame.Angles(0, HALF, 0), {
		length = 60,
		height = 28,
		thick = 3,
		openings = {
			{ x = -18, w = 7, y = 11, h = 9 },
			{ x = 0, w = 7, y = 11, h = 9 },
			{ x = 18, w = 7, y = 11, h = 9 },
		},
		ragged = 0.3,
	})
	wall(m, C * CFrame.new(18, 0, -12) * CFrame.Angles(0, HALF, 0), {
		length = 30,
		height = 28,
		thick = 3,
		openings = { { x = 2, w = 7, y = 11, h = 9 } },
		ragged = 0.45,
	})
	wall(
		m,
		C * CFrame.new(18, 0, 18) * CFrame.Angles(0, HALF, 0),
		{ length = 30, height = 5, thick = 3, ragged = 0.6 }
	)
	rubble(m, C * Vector3.new(22, 0, 18), 9, 9, 2, 4.5)
	wall(m, C * CFrame.new(0, 0, 33), { length = 39, height = 28, thick = 3, ragged = 0.15 })
	trim(m, "Niche", Vector3.new(12, 16, 0.4), C * CFrame.new(0, 14, 31.4), COLORS.dark)
	for side = -1, 1, 2 do
		glyphPanel(m, C * CFrame.new(side * 11, 16, 31.45), 1, 4, 2.2)
	end
	-- The god's pedestal and what's left of the statue: feet, the robe's hem to the knees
	stone(m, "Pedestal", Vector3.new(14, 6, 11), C * CFrame.new(0, 3, 23), COLORS.marble)
	glyphPanel(m, C * CFrame.new(0, 3, 17.5), 4, 1, 1.8)
	local robe = C * CFrame.new(0, 6, 23.5) * CFrame.Angles(0.04, 0, 0.03)
	stone(m, "Robe", Vector3.new(8.5, 13, 5.5), robe * CFrame.new(0, 6.5, 0), COLORS.marble, SMOOTH)
	for k = -1, 1 do
		trim(m, "Fold", Vector3.new(0.7, 12, 0.7), robe * CFrame.new(k * 2.4, 6.2, -2.8), COLORS.shade)
	end
	for side = -1, 1, 2 do
		stone(
			m,
			"Foot",
			Vector3.new(2.6, 1.6, 3.6),
			robe * CFrame.new(side * 2, 0.8, -3.5),
			COLORS.marble,
			SMOOTH
		)
	end
	wedge(
		m,
		"Break",
		Vector3.new(8, 2.6, 5),
		robe * CFrame.new(0, 14.2, 0) * CFrame.Angles(0, 0.4, 0),
		COLORS.marble,
		true
	)
	spot(robe * CFrame.new(-2, 15.5, 0), 2)
	-- The cold fire still burning in the cella, a ring of tiles round it
	brazier(m, C * CFrame.new(0, 0, -4), 4.4, 60)
	mosaicRing(m, C * CFrame.new(0, 0, -4), 7, 14, 1.8, { COLORS.mosaic[1], COLORS.mosaic[2] })

	-- The swim line: up over the stair, between the front columns and in at the door
	pass("temple door", {
		T * Vector3.new(0, 34, -110),
		T * Vector3.new(0, 31, -60),
		T * Vector3.new(0, 31, -36),
		T * Vector3.new(0, 31, -18),
	})
end

-- The gateway: a triple arch over the avenue's start (its left arch fallen), a
-- glowing keystone, an obelisk standing outside and one toppled
local function gateway(parent: Instance, T0: CFrame)
	local m = model(parent, "Gateway")
	local G = siteAt(T0, 0, -245, 0, 38, 6)
	claim(G, 42, 10)
	local crown = arch(m, G, { span = 24, spring = 22, depth = 10, pier = 7, keystone = true })
	glyphPanel(m, G * CFrame.new(0, crown + 1.7, -5.55), 6, 1, 1.9)
	-- the right arch stands, the left one is down to its outer pier and rubble
	arch(
		m,
		G * CFrame.new(25, 0, 0),
		{ span = 12, spring = 13, depth = 8, pier = 6, skipPier = -1, ring = 3 }
	)
	stone(m, "PierBase", Vector3.new(7.6, 2.4, 9.6), G * CFrame.new(-34, 0.2, 0), COLORS.shade)
	stone(
		m,
		"Pier",
		Vector3.new(6, 8, 8),
		G * CFrame.new(-34, 5, 0) * CFrame.Angles(0, 0, 0.05),
		COLORS.marble
	)
	rubble(m, G * Vector3.new(-26, 0, 0), 10, 10, 2, 5)
	for side = -1, 1, 2 do
		glyphPanel(m, G * CFrame.new(side * 15.5, 12, -5.05), 1, 4, 2.2)
	end
	-- lamp pillars just inside it
	for side = -1, 1, 2 do
		lampPillar(m, siteAt(T0, side * 15.5, -235, 0), side == 1)
	end
	-- an obelisk standing outside, its twin toppled
	obelisk(m, siteAt(T0, -52, -258, 0.1), 34, 4.2, true)
	toppled(m, siteAt(T0, 52, -258, 0), (T0.RightVector * 0.9 - T0.LookVector * 0.4).Unit, 34, 4.2)
	claim(siteAt(T0, 0, -258, 0), 64, 14)
end

-- The processional avenue from the gateway to the stair: paving, colonnades (some
-- whole under architraves, some snapped, one fallen across the way), four
-- sea-dragon guardians, lamp pillars, the statue's head toppled at its end and its
-- hand rising from the sand by the platform
type Colonnade = { side: number, list: { Standing } }
local AVENUE: { Colonnade } = {
	{
		side = -1,
		list = {
			{ x = -25, z = -230, keep = 1, band = true },
			{ x = -25, z = -208, keep = 0.5 },
			{ x = -25, z = -186, keep = 1 },
			{ x = -25, z = -164, keep = 1 },
			{ x = -25, z = -142, keep = 0 },
			{ x = -25, z = -120, keep = 0.35 },
		},
	},
	{
		side = 1,
		list = {
			{ x = 25, z = -230, keep = 0.7 },
			{ x = 25, z = -208, keep = 1 },
			{ x = 25, z = -186, keep = 1, band = true },
			{ x = 25, z = -164, keep = 0.4 },
			{ x = 25, z = -142, keep = 1 },
			{ x = 25, z = -120, keep = 0 },
		},
	},
}

local function avenue(parent: Instance, T0: CFrame)
	local m = model(parent, "Avenue")
	claim(siteAt(T0, 0, -160, 0), 44, 86)
	-- Paving: two rows of big slabs, some sunk or tilted, a few lost under the sand
	for row = 0, 9 do
		for col = -1, 1, 2 do
			if rng:NextNumber() < 0.12 then
				continue
			end
			local p = T0 * Vector3.new(col * 8.4, 0, -238 + row * 16.2 + 8)
			local g = groundY(p.X, p.Z)
			local tilt = if rng:NextNumber() < 0.25 then rng:NextNumber(-0.06, 0.06) else 0
			paving(
				m,
				"Paving",
				Vector3.new(16.2, 1.6, 15.8),
				CFrame.new(p.X, g + 0.25 + rng:NextNumber(-0.25, 0.1), p.Z)
					* T0.Rotation
					* CFrame.Angles(tilt, 0, tilt * 0.5),
				COLORS.paving
			)
		end
	end
	for side = -1, 1, 2 do
		for k = 0, 4 do
			if rng:NextNumber() < 0.25 then
				continue
			end
			local p = T0 * Vector3.new(side * 17.6, 0, -236 + k * 32 + 16)
			trim(
				m,
				"Curb",
				Vector3.new(1.6, 1.2, 30),
				CFrame.new(p.X, groundY(p.X, p.Z) + 0.3, p.Z) * T0.Rotation,
				COLORS.teal
			)
		end
	end
	-- Colonnades
	local tops: { [string]: Vector3 } = {}
	for _, colonnade in AVENUE do
		local side = colonnade.side
		for _, c in colonnade.list do
			local base = siteAt(T0, c.x, c.z, 0, 4, 4)
			local top = column(
				m,
				base,
				{ radius = 2.6, height = 30, keep = c.keep, band = if c.band then 0.3 else nil }
			)
			if top then
				tops[`{side},{c.z}`] = top
			end
			if c.keep <= 0 then
				-- fallen: across the avenue on the left, outward on the right
				local dir = if side == -1
					then (T0.RightVector * 0.8 - T0.LookVector * 0.6).Unit
					else (T0.RightVector + T0.LookVector * 0.3).Unit
				fallenColumn(m, floorAt(base * Vector3.new(0, 0, 0) + dir * 4), dir, 2.6, 5, side == -1)
			end
		end
	end
	for _, pair in { { "-1,-186", "-1,-164" }, { "1,-208", "1,-186" } } do
		local a, b = tops[pair[1]], tops[pair[2]]
		if a and b then
			architrave(m, a, b, 7.5, if pair[1] == "-1,-186" then -1 else 1)
		end
	end
	-- Guardians face each other across the way
	for _, z in { -205, -150 } do
		for side = -1, 1, 2 do
			guardian(m, siteAt(T0, side * 37, z, side * HALF, 6, 8), 15)
		end
	end
	-- Lamp pillars at the stair's foot
	for side = -1, 1, 2 do
		lampPillar(m, siteAt(T0, side * 17, -100, 0), side == -1)
	end
	-- The head lies toppled at the avenue's end, face turned to the sky and the way
	statueHead(
		m,
		T0 * Vector3.new(-36, 0, -94),
		T0.Rotation * CFrame.Angles(0, -0.6, 0) * CFrame.Angles(0, 0, 1.2) * CFrame.Angles(-0.3, 0, 0),
		26
	)
	-- and the hand rises from the sand by the platform's front-right corner
	statueHand(m, siteAt(T0, 50, -84, -0.6), 22)
	urn(m, T0 * Vector3.new(-22, 0, -104), 6, false)
	urn(m, T0 * Vector3.new(-26, 0, -110), 5, true)
	rubble(m, T0 * Vector3.new(-30, 0, -170), 10, 6, 1.5, 4)
	rubble(m, T0 * Vector3.new(30, 0, -128), 10, 6, 1.5, 4)
	pass("gateway and avenue", { T0 * Vector3.new(0, 15, -290), T0 * Vector3.new(0, 15, -82) })
	-- (the swim line's height over the paving, wherever the sand plain lifts it)
	local points = Ruins.passes[#Ruins.passes].points
	for i, p in points do
		points[i] = Vector3.new(p.X, groundY(p.X, p.Z) + 18, p.Z)
	end
end

-- ---------------------------------------------------------------------------
-- The theatre, the sunken courtyard and the back quarter (the city's frame)
-- ---------------------------------------------------------------------------

local function theatre(parent: Instance)
	local m = model(parent, "Theatre")
	local spec = Layout.theatre
	-- Facing the avenue (-z); the cavea curves round its far side
	local H = siteAt(city, spec.x, spec.z, 0, 60, 60)
	claim(H * CFrame.new(0, 0, 18), 70, 52)
	for k = 1, 5 do
		local r0 = 24 + 7 * (k - 1)
		local top = 2.6 * k
		for j = 0, 9 do
			local deg = -100 + 20 * (j + 0.5)
			local collapsed = k >= 3 and deg > 38 and deg < 82
			if collapsed or rng:NextNumber() < 0.07 then
				continue
			end
			local cf = H
				* CFrame.Angles(0, math.rad(deg), 0)
				* CFrame.new(
					rng:NextNumber(-0.2, 0.2),
					(top + 1) / 2 - 1.2 + rng:NextNumber(-0.3, 0.15),
					r0 + 3.5
				)
				* CFrame.Angles(rng:NextNumber(-0.015, 0.015), 0, rng:NextNumber(-0.015, 0.015))
			stone(
				m,
				"Seat",
				Vector3.new((r0 + 7) * math.rad(20) * 1.02, top + 1.2, 7),
				cf,
				if k % 2 == 0 then COLORS.shade else COLORS.weathered
			)
			if rng:NextNumber() < 0.3 then
				spot(cf * CFrame.new(0, (top + 1.2) / 2, 1), 2.5)
			end
		end
	end
	rubble(m, H * Vector3.new(math.sin(math.rad(60)) * 44, 0, math.cos(math.rad(60)) * 44), 15, 12, 2.2, 5.5)
	-- The orchestra's mosaic floor round a glowing glyph circle
	local O = H * CFrame.new(0, 0.6, 0)
	local orchestra = paving(
		m,
		"Orchestra",
		Vector3.new(1.6, 46, 46),
		H * CFrame.new(0, -0.2, 0) * CFrame.Angles(0, 0, HALF),
		COLORS.paving
	)
	orchestra.Shape = Enum.PartType.Cylinder
	mosaicRing(m, O, 19.5, 22, 3.4, COLORS.mosaic)
	mosaicRing(m, O, 14, 16, 2.8, { COLORS.mosaic[2], COLORS.mosaic[1] })
	mosaicRays(m, O, 3.5, 10, 8, COLORS.mosaic[4])
	for k = 1, 8 do
		glow(
			m,
			"Glyph",
			Vector3.new(0.42, 0.2, 1.6),
			O * CFrame.Angles(0, k * TAU / 8, 0) * CFrame.new(0, 0.2, -2.4)
		)
	end
	local heart = glow(
		m,
		"OrchestraGlow",
		Vector3.new(0.3, 2.6, 2.6),
		O * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, HALF)
	)
	heart.Shape = Enum.PartType.Cylinder
	light(heart, 56, 1.1)
	-- The stage toward the avenue: a low platform with broken columns
	paving(m, "Stage", Vector3.new(50, 3.6, 10), H * CFrame.new(0, 0.6, -31), COLORS.shade)
	glyphPanel(m, H * CFrame.new(0, 1, -36.05), 7, 1, 1.8)
	for i, keep in { 1, 0.4, 1, 0.6 } do
		column(m, H * CFrame.new(-18 + (i - 1) * 12, 2.4, -31), { radius = 2.2, height = 18, keep = keep })
	end
	-- Arches behind the cavea
	for _, a in { -32, 4, 36 } do
		local frame = siteAt(H * CFrame.Angles(0, math.rad(a), 0), 0, 64, math.pi, 8, 4)
		arch(m, frame, { span = 12, spring = 12, depth = 5, pier = 4, ring = 3, broken = a > 30 })
	end
	urn(m, H * Vector3.new(-26, 0, -38), 5.5, false)
	urn(m, H * Vector3.new(24, 0, -40), 5, true)
end

local function court(parent: Instance)
	local m = model(parent, "SunkenCourt")
	local spec = Layout.court
	local ix, iz = spec.inner[1] / 2, spec.inner[2] / 2
	local w = spec.wall
	-- Its stairs come down from the avenue's side: the frame looks toward the avenue
	local C0 = city * CFrame.new(spec.x, 0, spec.z) * CFrame.Angles(0, math.pi, 0)
	local rim = math.huge
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
		local q = C0 * Vector3.new(c[1] * (ix + w + 3), 0, c[2] * (iz + w + 3))
		rim = math.min(rim, groundY(q.X, q.Z))
	end
	local C = CFrame.new(C0.X, rim, C0.Z) * C0.Rotation
	claim(C, ix + w + 3, iz + w + 3)
	local bottom = World.deep.floorY - spec.depth - C.Y -- the floor, in C
	local wallH = 2.6 - bottom + 1
	-- The paved floor and its mosaic
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			paving(
				m,
				"CourtFloor",
				Vector3.new(ix - 0.4, 1.8, iz - 0.4),
				C * CFrame.new(sx * ix / 2, bottom - 0.7, sz * iz / 2),
				COLORS.paving
			)
		end
	end
	local F = C * CFrame.new(0, bottom + 0.2, 12)
	mosaicRing(m, F, 12.5, 20, 3, COLORS.mosaic)
	mosaicRing(m, F, 16, 24, 2.6, { COLORS.mosaic[2], COLORS.mosaic[4] })
	-- The lining walls, a parapet on their rim; the stair side has its gap
	local function lining(x: number, z: number, length: number, along: boolean, niches: { number })
		local frame = C
			* CFrame.new(x, bottom - 1, z)
			* (if along then CFrame.new() else CFrame.Angles(0, HALF, 0))
		stone(
			m,
			"CourtWall",
			Vector3.new(length, wallH, w),
			frame * CFrame.new(0, wallH / 2, 0),
			COLORS.shade,
			MARBLE
		)
		-- the face toward the pit
		local inward = if along then (if z > 0 then -1 else 1) else (if x > 0 then -1 else 1)
		for _, n in niches do
			local face = frame
				* CFrame.new(n, 0, inward * (w / 2 + 0.05))
				* CFrame.Angles(0, if inward > 0 then math.pi else 0, 0)
			trim(m, "Niche", Vector3.new(8, 10, 0.4), face * CFrame.new(0, 6, 0), COLORS.dark)
			local arc = trim(
				m,
				"NicheArch",
				Vector3.new(0.4, 8, 8),
				face * CFrame.new(0, 11, 0) * CFrame.Angles(0, HALF, 0),
				COLORS.dark
			)
			arc.Shape = Enum.PartType.Cylinder
			trim(m, "NicheSill", Vector3.new(9, 0.8, 1.2), face * CFrame.new(0, 1, -0.4), COLORS.teal)
		end
		-- the parapet, broken here and there
		local pieces = math.max(math.floor(length / 14), 1)
		for k = 1, pieces do
			if rng:NextNumber() < 0.3 then
				continue
			end
			local len = length / pieces - rng:NextNumber(1, 4)
			stone(
				m,
				"Parapet",
				Vector3.new(len, 3, 1.8),
				frame
					* CFrame.new(
						-length / 2 + (k - 0.5) * length / pieces,
						wallH + 1.3,
						inward * -(w / 2 - 1.2)
					)
					* CFrame.Angles(0, 0, rng:NextNumber(-0.03, 0.03)),
				COLORS.marble,
				SMOOTH
			)
		end
		spot(frame * CFrame.new(rng:NextNumber(-length / 3, length / 3), wallH, 0), 3)
	end
	lining(0, iz + w / 2, ix * 2 + w * 2, true, { -24, 0, 24 })
	lining(ix + w / 2, 0, iz * 2, false, { -14, 14 })
	lining(-ix - w / 2, 0, iz * 2, false, { -14, 14 })
	local gap = spec.stair / 2
	local side = ix + w - gap
	lining(-(gap + side / 2), -iz - w / 2, side, true, {})
	lining(gap + side / 2, -iz - w / 2, side, true, {})
	glyphPanel(m, C * CFrame.new(0, bottom + 17.5, iz - 0.05), 7, 1, 2.2)
	-- The stairs down from the rim
	local steps = 10
	local rise = -bottom / steps
	local run = 3.2
	for i = 1, steps do
		local top = -rise * i
		local h = top - bottom + 1
		stone(
			m,
			"CourtStep",
			Vector3.new(spec.stair, h, run),
			C * CFrame.new(0, bottom - 1 + h / 2, -iz + run * (i - 0.5)),
			COLORS.marble
		)
	end
	for s = -1, 1, 2 do
		local a, b =
			C * Vector3.new(s * (gap + 0.9), 1.4, -iz - w),
			C * Vector3.new(s * (gap + 0.9), bottom + 1.4, -iz + run * steps)
		stone(
			m,
			"StairWall",
			Vector3.new(1.8, 3, (b - a).Magnitude),
			CFrame.lookAt((a + b) / 2, b),
			COLORS.shade,
			SMOOTH
		)
	end
	-- The fountain: an octagonal basin of glowing water round a glyph pillar
	for k = 0, 7 do
		stone(
			m,
			"FountainRim",
			Vector3.new(6.8, 2.6, 1.6),
			F * CFrame.Angles(0, k * math.pi / 4, 0) * CFrame.new(0, 1.1, -8.2),
			COLORS.marble,
			SMOOTH
		)
	end
	local water = glow(
		m,
		"FountainWater",
		Vector3.new(0.3, 14.8, 14.8),
		F * CFrame.new(0, 1.7, 0) * CFrame.Angles(0, 0, HALF)
	)
	water.Shape = Enum.PartType.Cylinder
	water.Transparency = 0.4
	light(water, 50, 1.3)
	motes(water, 4, Enum.NormalId.Right)
	stone(m, "FountainPillar", Vector3.new(2.8, 10, 2.8), F * CFrame.new(0, 5, 0), COLORS.marble, SMOOTH)
	for k = 0, 1 do
		glyphPanel(m, F * CFrame.Angles(0, k * math.pi, 0) * CFrame.new(0, 6, -1.45), 1, 3, 1.4)
	end
	wedge(
		m,
		"Break",
		Vector3.new(2.8, 1.6, 2.8),
		F * CFrame.new(0, 10.8, 0) * CFrame.Angles(0, 0.6, 0),
		COLORS.marble,
		true
	)
	-- A column fallen against the back-left corner, urns in the niches and corners
	do
		local a, b = C * Vector3.new(-26, bottom + 2.6, 22), C * Vector3.new(-41, 1.4, iz + 3)
		lyingDrum(m, a, b, 2.6, COLORS.marble)
		fallenCapital(m, C * Vector3.new(-20, 0, 26), (C.RightVector).Unit, 2.6)
	end
	for i, u in
		{
			Vector2.new(-24, iz - 2.6),
			Vector2.new(24, iz - 2.6),
			Vector2.new(ix - 2.6, 14),
			Vector2.new(-ix + 2.6, -14),
			Vector2.new(31, -24),
		}
	do
		urn(m, C * Vector3.new(u.X, bottom, u.Y), 5, i % 2 == 1 and i > 1)
	end
	for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local p = C * Vector3.new(corner[1] * (ix - 4), bottom + 0.2, corner[2] * (iz - 4))
		spot(CFrame.new(p), 5, true)
		spot(CFrame.new(p + C.RightVector * -corner[1] * 6), 4, true)
	end
	pass("courtyard stairs", {
		C * Vector3.new(0, 16, -iz - 34),
		C * Vector3.new(0, 14, -iz - 2),
		C * Vector3.new(0, bottom + 14, -iz + run * steps),
		C * Vector3.new(0, bottom + 12, -iz + run * steps + 2),
	})
end

-- A house: walls with windows round a floor, its front fallen; `door` cuts a
-- doorway through the back wall big enough to swim through
local function house(
	parent: Instance,
	H: CFrame,
	width: number,
	depth: number,
	height: number,
	door: boolean,
	label: string
)
	local m = model(parent, "House")
	claim(H, width / 2 + 4, depth / 2 + 4)
	paving(m, "HouseFloor", Vector3.new(width, 1.6, depth), H * CFrame.new(0, -0.5, 0), COLORS.paving)
	local back = H * CFrame.new(0, 0, depth / 2)
	local openings: { Opening } = if door
		then { { x = 3, w = 20, y = 0, h = 23 } }
		else { { x = -width / 4, w = 7, y = 10, h = 9 }, { x = width / 4, w = 7, y = 10, h = 9 } }
	if door and width >= 40 then
		table.insert(openings, { x = -width / 2 + 5, w = 5, y = 11, h = 8 })
	end
	wall(m, back, {
		length = width,
		height = height,
		thick = 3,
		openings = openings,
		ragged = if door then 0.08 else 0.2,
	})
	wall(m, H * CFrame.new(-width / 2, 0, 0) * CFrame.Angles(0, HALF, 0), {
		length = depth,
		height = height * 0.9,
		thick = 3,
		openings = { { x = -depth / 5, w = 6, y = 10, h = 8 }, { x = depth / 5, w = 6, y = 10, h = 8 } },
		ragged = 0.35,
	})
	wall(m, H * CFrame.new(width / 2, 0, depth / 4) * CFrame.Angles(0, HALF, 0), {
		length = depth / 2,
		height = height * 0.7,
		thick = 3,
		openings = { { x = 0, w = 6, y = 9, h = 8 } },
		ragged = 0.5,
	})
	wall(m, H * CFrame.new(0, 0, -depth / 2), { length = width, height = 2.5, thick = 3, ragged = 0.6 })
	rubble(m, H * Vector3.new(width / 2 + 3, 0, -depth / 4), 9, 9, 2, 4.5)
	urn(m, H * Vector3.new(-width / 2 + 4, 0, depth / 2 - 4), 5, false)
	if door then
		pass(label, { H * Vector3.new(3, 12.5, -depth / 2 - 14), H * Vector3.new(3, 12.5, depth / 2 + 16) })
		-- (a fish swims in over the fallen front wall and out through the doorway)
	end
	return m
end

local function quarter(parent: Instance)
	local m = model(parent, "BackQuarter")
	-- A colonnade facing the temple's back, on its own low platform
	local S = siteAt(city, 95, 0, HALF, 72, 8)
	claim(S, 76, 10)
	stone(m, "StoaFloor", Vector3.new(148, 3, 13), S * CFrame.new(0, 0.2, 0), COLORS.shade)
	local tops: { [number]: Vector3 } = {}
	for i, keep in { 1, 1, 0.5, 0, 1, 1, 0.35 } do
		local base = S * CFrame.new(-60 + (i - 1) * 20, 1.7, 0)
		local top =
			column(m, base, { radius = 2.6, height = 28, keep = keep, band = if i == 2 then 0.35 else nil })
		if top then
			tops[i] = top
		end
		if keep <= 0 then
			fallenColumn(m, floorAt(base * Vector3.new(0, 0, -9)), S.LookVector, 2.6, 4)
		end
	end
	for _, pair in { { 1, 2 }, { 5, 6 } } do
		local a, b = tops[pair[1]], tops[pair[2]]
		if a and b then
			architrave(m, a, b, 7.5, if pair[1] == 1 then -1 else nil)
		end
	end
	house(parent, siteAt(city, 152, 70, HALF + 0.2, 22, 18), 44, 34, 28, true, "back quarter doorway")
	house(parent, siteAt(city, 170, -76, HALF - 0.35, 18, 15), 36, 28, 22, false, "")
	toppled(m, siteAt(city, 205, 10, 0), (city.LookVector * -1 + city.RightVector * 0.3).Unit, 30, 4)
	claim(siteAt(city, 214, 20, 0), 14, 26)
	-- A shrine of glyph steles round a cold brazier
	local shrine = siteAt(city, 132, -14, 0)
	claim(shrine, 14, 14)
	brazier(m, shrine, 3.6, 48)
	for k = -1, 1 do
		local a = math.rad(180 + k * 50)
		stele(m, siteAt(shrine, math.sin(a) * 9, math.cos(a) * 9, a + math.pi), 10)
	end
	rubble(m, city * Vector3.new(120, 0, 40), 14, 8, 1.6, 4)
end

-- A patch of coral, sponges and sea grass on the sand round `center`, kept off the
-- ruins' footprints (the growth pass fills it)
local function garden(center: Vector3, radius: number, count: number)
	for _ = 1, count do
		local a = rng:NextNumber(0, TAU)
		local d = math.sqrt(rng:NextNumber()) * radius
		local p = center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		if not claimed(p, 1) then
			spot(CFrame.new(floorAt(p)), rng:NextNumber(3.5, 7), true)
		end
	end
end

-- A fragment of a building between the city's monuments: a broken wall with a
-- window, its rubble, sometimes a column still standing beside it
local function fragment(parent: Instance, x: number, z: number, yaw: number)
	local m = model(parent, "Fragment")
	local length = rng:NextNumber(14, 26)
	local height = rng:NextNumber(10, 18)
	local F = siteAt(city, x, z, yaw, length / 2, 3)
	claim(F, length / 2 + 4, 6)
	wall(m, F, {
		length = length,
		height = height,
		thick = 3,
		openings = {
			{
				x = rng:NextNumber(-length / 4, length / 4),
				w = 5,
				y = height * 0.4,
				h = math.min(6, height * 0.3),
			},
		},
		ragged = 0.45,
	})
	rubble(m, F * Vector3.new(0, 0, rng:NextNumber(4, 8)), 8, 6, 1.5, 4)
	if rng:NextNumber() < 0.5 then
		column(
			m,
			F * CFrame.new(length / 2 + 6, 0, 0),
			{ radius = 2.4, height = 24, keep = rng:NextNumber(0.3, 0.8) }
		)
	end
	spot(F * CFrame.new(-length / 2 - 2, 0, 3), 5, true)
end

-- Between the monuments: wall fragments, and coral gardens round the head, the hand,
-- the avenue's sides, the theatre, the courtyard's rim, the temple's back and the
-- gateway (the city's frame: x, z, then a turn, or a radius and a count)
local FRAGMENTS = {
	{ -205, 72, 0.3 },
	{ -95, 92, -0.4 },
	{ -225, -88, 0.2 },
	{ -52, -96, 0.5 },
	{ 35, 128, -0.2 },
	{ 30, -120, 0.1 },
	{ -30, 162, 0.8 },
	{ -252, 112, 0 },
}
local GARDENS = {
	{ -100, 54, 14, 6 },
	{ -70, -68, 12, 5 },
	{ -200, 52, 16, 6 },
	{ -150, -52, 16, 6 },
	{ -118, 52, 14, 5 },
	{ -80, 120, 18, 7 },
	{ -205, 122, 16, 6 },
	{ -118, -96, 18, 6 },
	{ 70, 72, 16, 6 },
	{ 72, -70, 16, 6 },
	{ 130, 40, 14, 5 },
	{ -278, 32, 12, 5 },
	{ -278, -34, 12, 5 },
}

local function between(parent: Instance)
	for _, f in FRAGMENTS do
		fragment(parent, f[1], f[2], f[3])
	end
	for _, g in GARDENS do
		garden(city * Vector3.new(g[1], 0, g[2]), g[3], g[4])
	end
end

-- ---------------------------------------------------------------------------
-- The smaller ruins out in the biome
-- ---------------------------------------------------------------------------

local function outGate(m: Model, O: CFrame, label: string)
	local lit = rng:NextNumber() < 0.6
	arch(m, O, { span = 22, spring = 18, depth = 8, pier = 7, keystone = lit })
	for side = -1, 1, 2 do
		local len = rng:NextNumber(10, 18)
		wall(
			m,
			O * CFrame.new(side * (11 + 7 + len / 2), 0, 0),
			{ length = len, height = rng:NextNumber(8, 16), thick = 4, ragged = 0.5 }
		)
	end
	glyphPanel(m, O * CFrame.new(-14.5, 10, -4.05), 1, 3, 2)
	for side = -1, 1, 2 do
		rubble(m, O * Vector3.new(side * 24, 0, 10), 9, 5, 1.6, 4.5)
	end
	pass(label, { O * Vector3.new(0, 13, -30), O * Vector3.new(0, 13, 30) })
end

local function outStoa(m: Model, O: CFrame)
	stone(m, "StoaFloor", Vector3.new(94, 2.6, 11), O * CFrame.new(0, 0.1, 0), COLORS.shade)
	local tops: { [number]: Vector3 } = {}
	for i = 1, 5 do
		local keep = if rng:NextNumber() < 0.5
			then 1
			elseif rng:NextNumber() < 0.6 then rng:NextNumber(0.3, 0.75)
			else 0
		local base = O * CFrame.new(-40 + (i - 1) * 20, 1.4, 0)
		local top =
			column(m, base, { radius = 2.4, height = 24, keep = keep, band = if i == 3 then 0.3 else nil })
		if top then
			tops[i] = top
		elseif keep <= 0 then
			fallenColumn(
				m,
				floorAt(base * Vector3.new(0, 0, -8)),
				(O.LookVector + O.RightVector * rng:NextNumber(-0.4, 0.4)).Unit,
				2.4,
				4
			)
		end
	end
	for i = 1, 4 do
		local a, b = tops[i], tops[i + 1]
		if a and b then
			architrave(m, a, b, 7, nil)
		end
	end
	rubble(m, O * Vector3.new(0, 0, 12), 22, 10, 1.6, 4)
end

local function outTholos(m: Model, O: CFrame)
	drum(m, "TholosStep", O * CFrame.new(0, -1.4, 0), 2.6, 21, COLORS.shade, true)
	drum(m, "TholosFloor", O * CFrame.new(0, -0.2, 0), 3.4, 18, COLORS.marble, true)
	mosaicRing(m, O * CFrame.new(0, 3.2, 0), 8, 14, 2.4, COLORS.mosaic)
	local tops: { [number]: Vector3 } = {}
	for k = 1, 6 do
		local a = k * TAU / 6
		local keep = if k % 3 == 0 then rng:NextNumber(0.25, 0.6) else 1
		local top = column(
			m,
			O * CFrame.Angles(0, a, 0) * CFrame.new(0, 3.2, -14),
			{ radius = 1.8, height = 20, keep = keep }
		)
		if top then
			tops[k] = top
		end
	end
	for k = 1, 6 do
		local a, b = tops[k], tops[k % 6 + 1]
		if a and b then
			architrave(m, a, b, 5.4, nil)
		end
	end
	if rng:NextNumber() < 0.6 then
		brazier(m, O * CFrame.new(0, 3.2, 0), 3.4, 46)
	else
		stele(m, O * CFrame.new(0, 3.2, 0), 9)
	end
end

local function outObelisks(m: Model, O: CFrame)
	obelisk(m, O * CFrame.new(-14, 0, 0), rng:NextNumber(26, 34), 3.8, rng:NextNumber() < 0.5)
	toppled(
		m,
		O * CFrame.new(14, 0, 0),
		(O.RightVector + O.LookVector * rng:NextNumber(-0.6, 0.6)).Unit,
		30,
		3.8
	)
	for k = -1, 1, 2 do
		paving(
			m,
			"Slab",
			Vector3.new(14, 1.4, 14),
			O * CFrame.new(0, -0.3, k * 9) * CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0),
			COLORS.paving
		)
	end
end

local function outColossus(m: Model, O: CFrame)
	-- The feet and shins of a colossus on its pedestal: the rest of it is long gone
	stone(m, "ColossusPedestal", Vector3.new(28, 6.5, 20), O * CFrame.new(0, 2.6, 0), COLORS.shade)
	glyphPanel(m, O * CFrame.new(0, 2.8, -10.05), 6, 1, 2)
	local top = O * CFrame.new(0, 5.85, 0)
	for side = -1, 1, 2 do
		local foot = top * CFrame.new(side * 6, 0, 0)
		stone(m, "Foot", Vector3.new(6, 3.4, 12), foot * CFrame.new(0, 1.7, -2), COLORS.marble, SMOOTH)
		for t = -1.5, 1.5 do
			stone(
				m,
				"Toe",
				Vector3.new(1.3, 1.6, 2.2),
				foot * CFrame.new(t * 1.4, 0.8, -8.6),
				COLORS.marble,
				SMOOTH
			)
		end
		local shin = rng:NextNumber(10, 18)
		drum(m, "Shin", foot * CFrame.new(0, 3, 1), shin, 3.2, COLORS.marble, true)
		wedge(
			m,
			"Break",
			Vector3.new(6, 3, 6),
			foot * CFrame.new(0, 3 + shin + 1, 1) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
			COLORS.marble,
			true
		)
		spot(foot * CFrame.new(0, 3 + shin + 1.5, 1), 2.5)
	end
	-- a knee and a fist lie where they fell
	rubble(m, O * Vector3.new(0, 0, 20), 12, 4, 4, 8)
	statueHand(m, O * CFrame.new(18, 0, 14) * CFrame.Angles(0, 2.2, 0), 14)
end

local function outSteles(m: Model, O: CFrame)
	brazier(m, O, 3.2, 44)
	local count = rng:NextInteger(3, 5)
	for k = 1, count do
		local a = k * TAU / count + rng:NextNumber(-0.2, 0.2)
		stele(m, siteAt(O, math.sin(a) * 10, math.cos(a) * 10, a + math.pi), rng:NextNumber(8, 11))
	end
	urn(m, O * Vector3.new(6, 0, 6), 5, true)
end

local OUTLYING = {
	"gate",
	"stoa",
	"house",
	"tholos",
	"obelisks",
	"colossus",
	"steles",
	"gate",
	"stoa",
	"house",
	"tholos",
	"obelisks",
	"gate",
	"house",
	"steles",
}
local OUT_RADIUS: { [string]: number } = {
	gate = 30,
	stoa = 50,
	house = 30,
	tholos = 26,
	obelisks = 26,
	colossus = 26,
	steles = 16,
}

-- Whether the ground round a spot is level enough to build on (not a mound or a
-- chute's foot)
local function level(x: number, z: number, radius: number): boolean
	local low, high = math.huge, -math.huge
	for k = 0, 6 do
		local a = k * TAU / 7
		local r = if k == 0 then 0 else radius
		local y = groundY(x + math.cos(a) * r, z + math.sin(a) * r)
		low, high = math.min(low, y), math.max(high, y)
	end
	return high - low < 4
end

local function inBox(p: Vector3, pad: number): boolean
	local q = city:PointToObjectSpace(p)
	local box = Layout.keepOut
	return q.X > box.x[1] - pad and q.X < box.x[2] + pad and q.Z > box.z[1] - pad and q.Z < box.z[2] + pad
end

local function outlying(parent: Instance)
	local spec = Layout.outlying
	local placeRng = Random.new(World.seed + 62)
	local placed: { Vector3 } = {}
	local span = (spec.angles[2] - spec.angles[1]) % 360
	for index = 1, spec.count do
		local kind = OUTLYING[(index - 1) % #OUTLYING + 1]
		local size = OUT_RADIUS[kind]
		local found: Vector3? = nil
		for _ = 1, 80 do
			local angle = math.rad(spec.angles[1] + placeRng:NextNumber(0, span))
			local r = placeRng:NextNumber(spec.radii[1] + size, spec.radii[2] - size)
			local p = World.hub.center + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
			if inBox(p, size + spec.margin) then
				continue
			end
			local near = false
			for _, other in placed do
				if (Vector3.new(other.X, 0, other.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude < spec.apart then
					near = true
					break
				end
			end
			if near or not level(p.X, p.Z, size) then
				continue
			end
			found = p
			break
		end
		if found == nil then
			continue
		end
		table.insert(placed, found)
		-- Facing roughly back toward the hub, so they read from the drop-off
		local toward = (World.hub.center - found) * Vector3.new(1, 0, 1)
		local yaw = math.atan2(-toward.X, -toward.Z) + placeRng:NextNumber(-0.7, 0.7)
		local O = siteAt(CFrame.new(found), 0, 0, yaw, size * 0.6, size * 0.3)
		local m = model(parent, `Ruin{index}`)
		m:SetAttribute("Kind", kind)
		claim(O, size, size)
		local label = `{kind} {index}`
		if kind == "gate" then
			outGate(m, O, label)
		elseif kind == "stoa" then
			outStoa(m, O)
		elseif kind == "house" then
			local door = rng:NextNumber() < 0.5
			local height = if door then rng:NextNumber(26, 28) else rng:NextNumber(20, 26)
			house(m, O, rng:NextNumber(30, 40), rng:NextNumber(24, 32), height, door, label)
		elseif kind == "tholos" then
			outTholos(m, O)
		elseif kind == "obelisks" then
			outObelisks(m, O)
		elseif kind == "colossus" then
			outColossus(m, O)
		else
			outSteles(m, O)
		end
		garden(O * Vector3.new(0, 0, size * 0.9), size * 0.5, 4)
	end
	return #placed
end

-- Rounded boulders between the ruins (the BoulderRound prop over a ball)
local function boulders(parent: Instance)
	local spec = Layout.outlying
	local span = (spec.angles[2] - spec.angles[1]) % 360
	local made = 0
	for _ = 1, Layout.boulders * 4 do
		if made >= Layout.boulders then
			break
		end
		local angle = math.rad(spec.angles[1] + rng:NextNumber(0, span))
		local r = rng:NextNumber(spec.radii[1], spec.radii[2])
		local p = World.hub.center + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		if inBox(p, 12) or claimed(p, 12) then
			continue
		end
		local size = rng:NextNumber(7, 22)
		local g = floorAt(p)
		local rock = ball(
			parent,
			"Boulder",
			g + Vector3.new(0, size * 0.3, 0),
			size,
			pick({ COLORS.weathered, COLORS.dark, COLORS.paving }),
			true
		)
		Props.dress(rock, "BoulderRound", {
			cframe = CFrame.new(g + Vector3.new(0, size * 0.4, 0))
				* CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
			size = Vector3.new(size * 1.1, size * 0.9, size * 1.1),
			solid = true,
			blocksCamera = true,
		})
		spot(CFrame.new(g + Vector3.new(size * 0.55, 0, 0)), 4, true)
		claim(CFrame.new(g), size / 2, size / 2)
		made += 1
	end
end

-- ---------------------------------------------------------------------------
-- Growth, light shafts, tidying
-- ---------------------------------------------------------------------------

local CORAL_KINDS = { "BrainCoral", "FanCoral", "StaghornCoral", "TubeSponge", "Anemone" }

-- One coral, sponge or anemone (the WorldProps model over a coloured stand-in, as
-- WorldService's coral gardens)
local function coral(parent: Instance, at: CFrame, size: number)
	local kind = CORAL_KINDS[rng:NextInteger(1, #CORAL_KINDS)]
	local hard = kind ~= "Anemone"
	local round = rng:NextNumber() < 0.5
	local piece = Instance.new("Part")
	setup(
		piece,
		"Coral",
		if round then Vector3.one * size else Vector3.new(size * 1.6, size * 0.6, size * 0.6),
		at
			* CFrame.new(0, size * 0.3, 0)
			* CFrame.Angles(0, rng:NextNumber(0, TAU), math.rad(rng:NextNumber(40, 90))),
		pick(Decor.CORALS),
		hard
	)
	piece.Shape = if round then Enum.PartType.Ball else Enum.PartType.Cylinder
	piece.Material = SMOOTH
	piece.CanQuery = false -- the camera passes through coral
	piece.Parent = parent
	Props.dress(piece, kind, {
		cframe = at * CFrame.new(0, size * 0.75, 0) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
		size = Vector3.new(size * 1.7, size * 1.5, size * 1.7),
		solid = hard,
	})
end

-- A clump of kelp on the sand (the KelpClump prop over a slim stand-in); it
-- doesn't collide
local function seaGrass(parent: Instance, at: CFrame, height: number)
	local stalk = trim(
		parent,
		"SeaGrass",
		Vector3.new(1.2, height, 1.2),
		at * CFrame.new(0, height / 2, 0),
		pick(Decor.KELP)
	)
	Props.dress(stalk, "KelpClump", {
		cframe = at * CFrame.new(0, height / 2, 0),
		size = Vector3.new(height * 0.6, height, height * 0.6),
	})
end

-- How near `p` comes to any swim line (studs)
local function passDistance(p: Vector3): number
	local best = math.huge
	for _, line in Ruins.passes do
		for i = 1, #line.points - 1 do
			local a, b = line.points[i], line.points[i + 1]
			local span = b - a
			local t = math.clamp((p - a):Dot(span) / math.max(span:Dot(span), 1e-6), 0, 1)
			best = math.min(best, (p - (a + span * t)).Magnitude)
		end
	end
	return best
end

-- Coral, sponges, anemones, moss and sea grass over the stones' tops and round
-- their feet (Config/Ruins `growth`); only moss (it doesn't collide) where a fish
-- swims through
local function grow(parent: Instance)
	local folder = model(parent, "Growth")
	for _, s in spots do
		if rng:NextNumber() > (if s.foot then Layout.growth.foot else Layout.growth.top) then
			continue
		end
		local at = CFrame.new(s.at.Position) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
		local roll = rng:NextNumber()
		if passDistance(s.at.Position) < 16 + s.size then
			blob(
				folder,
				"Moss",
				at * CFrame.new(0, 0.1, 0),
				Vector3.new(s.size * 1.4, 0.55, s.size),
				pick(COLORS.moss)
			)
		elseif s.foot then
			if roll < 0.45 then
				for _ = 1, rng:NextInteger(1, 3) do
					coral(
						folder,
						at * CFrame.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)),
						rng:NextNumber(2.2, math.max(s.size, 2.5))
					)
				end
			elseif roll < 0.65 then
				local before = #folder:GetChildren()
				Decor.sponges(folder, at, rng:NextInteger(3, 5), rng)
				stats.parts += #folder:GetChildren() - before
			elseif roll < 0.85 then
				seaGrass(folder, at, rng:NextNumber(6, 11))
			else
				blob(
					folder,
					"Moss",
					at * CFrame.new(0, 0.1, 0),
					Vector3.new(s.size * 1.6, 0.6, s.size * 1.1),
					pick(COLORS.moss)
				)
			end
		else
			if roll < 0.4 then
				blob(
					folder,
					"Moss",
					at * CFrame.new(0, 0.1, 0),
					Vector3.new(s.size * 1.4, 0.55, s.size),
					pick(COLORS.moss)
				)
				if rng:NextNumber() < 0.5 then
					blob(
						folder,
						"Moss",
						at * CFrame.new(s.size * 0.5, 0.05, 0.4),
						Vector3.new(s.size, 0.45, s.size * 0.8),
						pick(COLORS.moss)
					)
				end
			elseif roll < 0.75 then
				coral(folder, at, rng:NextNumber(1.4, math.max(s.size, 1.6)))
			else
				local before = #folder:GetChildren()
				Decor.sponges(folder, at, rng:NextInteger(2, 4), rng)
				stats.parts += #folder:GetChildren() - before
			end
		end
	end
end

-- Faint shafts of light from the surface onto the great temple
local function shafts(parent: Instance, T0: CFrame)
	for k = 1, Layout.shafts.count do
		local foot = T0 * Vector3.new((k - 1.5) * 30, 0, (k - 1.5) * -40)
		local top = Vector3.new(foot.X + 60, World.surfaceY - 4, foot.Z - 30)
		local bottom = Vector3.new(foot.X, groundY(foot.X, foot.Z) + 70, foot.Z)
		local holder = Instance.new("Part")
		holder.Name = "LightShaft"
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.CFrame = CFrame.new(top)
		holder.Parent = parent
		local a0 = Instance.new("Attachment")
		a0.Parent = holder
		a0.WorldPosition = top
		local a1 = Instance.new("Attachment")
		a1.Parent = holder
		a1.WorldPosition = bottom
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = 26
		beam.Width1 = 48
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(Color3.fromRGB(170, 236, 250))
		local s = Layout.shafts.strength
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.35, 1 - s),
			NumberSequenceKeypoint.new(0.85, 1 - s * 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Parent = holder
	end
end

-- Other dressing scattered over the biome by raycast on the Terrain alone (seeps,
-- plankton) can land inside a ruin's stones: it goes
local function tidy(biomes: Instance): number
	local removed = 0
	for _, name in { "Seeps", "PlanktonMats" } do
		local folder = biomes:FindFirstChild(name)
		if folder == nil then
			continue
		end
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") and claimed(child.Position, 1) then
				child:Destroy()
				removed += 1
			end
		end
	end
	return removed
end

-- ---------------------------------------------------------------------------

-- Builds the ruins into `parent` (Workspace.World.Biomes.Ruins: where Shared/Ground
-- looks for solid dressing) on the Terrain `ground` answers for (a ray down: the
-- top and its normal, or nil). Call it after the other biomes' dressing: it clears
-- their seeps and plankton out of its stones.
function Ruins.build(parent: Instance, ground: Ground): Stats
	rng = Random.new(World.seed + 61)
	groundOf = ground
	table.clear(spots)
	table.clear(footprints)
	table.clear(Ruins.passes)
	stats = { parts = 0, solid = 0, glow = 0, lights = 0, emitters = 0, props = 0, standins = 0, tidied = 0 }
	local out = Vector3.new(math.cos(math.rad(Layout.angle)), 0, math.sin(math.rad(Layout.angle)))
	local origin = World.hub.center + out * Layout.radius + Vector3.new(0, World.deep.floorY, 0)
	city = CFrame.fromMatrix(origin, out, Vector3.yAxis, out:Cross(Vector3.yAxis))
	-- The temple's frame: looking down the avenue toward the hub
	local T0 = city * CFrame.Angles(0, HALF, 0)

	greatTemple(parent, T0)
	gateway(parent, T0)
	avenue(parent, T0)
	theatre(parent)
	court(parent)
	quarter(parent)
	between(parent)
	local placed = outlying(parent)
	boulders(model(parent, "Boulders"))
	grow(parent)
	shafts(parent, T0)
	if parent.Parent then
		stats.tidied = tidy(parent.Parent :: Instance)
	end
	print(
		`[Ruins] the city and {placed} outlying ruins: {stats.parts} parts ({stats.solid} solid, {stats.glow} glowing), {stats.lights} lights, {stats.emitters} emitters, {stats.props} hero props ({stats.standins} part-built stand-ins); {stats.tidied} seeps and plankton cleared`
	)
	return stats
end

return Ruins
