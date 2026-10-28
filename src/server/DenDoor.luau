--!strict
-- A den's front door on the plaza, and its way out inside the den (owner,
-- 2026-10-17: "The names of the dens look rough", "Needs to be more of an entrance
-- to their den not just a hole with light coming out of it"). Each doorway in the
-- cavern wall (Cave.denDoor: a round alcove with a flat sill) gets:
--   - a stone threshold with two steps down to the paving (every style);
--   - its style (Config/Dens `doors`; owner, 2026-10-18: "Would be nice if we could
--     change the actual entrance to our den to unlockable versions to make it
--     easier to spot"): the Stone Arch (a chunky arch of rounded stones on stacked
--     jamb stones, brass lanterns, coral and kelp at the feet), a Kelp Curtain, a
--     Coral Arch, a Brass Porthole, a Whalebone Gate, a Crystal Grotto, an Abyssal
--     Gate or the Megalodon Jaws, each built from parts here;
--   - a nameplate (Decor.plaque): the owner's name on one line and the den's level
--     (NOOK ... SANCTUM) under it, each line scaled to fit, so a 20-character name
--     is never cut off;
--   - the portal at the alcove's back as a bubble curtain: a dark pane in a
--     stepped collar, a faint ForceField shimmer over it and bubbles rising across
--     it, tinted by the style.
-- An empty den reads shut: a slate plaque saying EMPTY DEN, unlit lanterns and a
-- dim, still curtain (its portal lets no one in: DenDoorController). A freed den
-- goes back to the Stone Arch.
--
-- Den hearts (owner, 2026-10-28; HeartService): once a lived-in den has a heart, a
-- drawn heart and the count stand where the nameplate's lower right rule was, and
-- last week's top 3 Best Dens wear a bright gold frame round the nameplate. Both
-- are built the first time they're needed, so a den without them (and the hub's
-- previews) builds as before.
--
-- The way out inside a den (owner, 2026-10-20: "den exit needs to be more pronounced
-- like the entrance too") is the same doorway turned round: an alcove in the front
-- wall of the same shape (DenCarve), the den's own doorway style round it, a
-- threshold level with the deck, TO THE HUB · THE PLAZA on its nameplate, always lit,
-- and a stronger glow from its portal.
--
-- Nothing solid reaches inside 10 studs of the doorway's axis (the alcove's radius
-- is 10.5, the sill 18 wide), so a LV 100 fish (collider ~6.8) swims in as before,
-- and the portal's trigger (Layout.doorAt) is unchanged; what does reach in (kelp
-- fringes, teeth) doesn't collide. tools/preview/check_doors.luau tries every style;
-- tools/preview/run_hub.sh renders them. Small built pieces are SmoothPlastic (and
-- Neon or Glass where they glow), never a toon-overridden material.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HeartGlyph = require(ReplicatedStorage.Shared.HeartGlyph)
local Hearts = require(ReplicatedStorage.Shared.Hearts)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Decor = require(script.Parent.Decor)

local World = Config.World
local hub = World.hub
local part = Decor.part

local DenDoor = {}

-- Warm sea-sandstone stones (the doorways' rock is Sandstone, Cave.luau)
type Palette = { stones: { Color3 }, jambs: { Color3 }, mortar: Color3 }
local SANDSTONE: Palette = {
	stones = {
		Color3.fromRGB(214, 186, 140),
		Color3.fromRGB(196, 166, 122),
		Color3.fromRGB(226, 200, 156),
		Color3.fromRGB(184, 154, 112),
	},
	jambs = {
		Color3.fromRGB(176, 148, 108),
		Color3.fromRGB(194, 164, 120),
		Color3.fromRGB(206, 178, 134),
	},
	mortar = Color3.fromRGB(128, 104, 76),
}
local REEF_ROCK: Palette = {
	stones = {
		Color3.fromRGB(196, 128, 118),
		Color3.fromRGB(178, 112, 106),
		Color3.fromRGB(212, 150, 130),
		Color3.fromRGB(162, 106, 100),
	},
	jambs = {
		Color3.fromRGB(150, 98, 92),
		Color3.fromRGB(170, 112, 104),
		Color3.fromRGB(186, 126, 114),
	},
	mortar = Color3.fromRGB(104, 70, 66),
}
local GROTTO_ROCK: Palette = {
	stones = {
		Color3.fromRGB(84, 78, 104),
		Color3.fromRGB(98, 90, 120),
		Color3.fromRGB(74, 70, 94),
		Color3.fromRGB(110, 100, 132),
	},
	jambs = {
		Color3.fromRGB(70, 66, 88),
		Color3.fromRGB(86, 80, 106),
		Color3.fromRGB(96, 88, 116),
	},
	mortar = Color3.fromRGB(46, 42, 58),
}
local STEP = Color3.fromRGB(168, 150, 120)
local STEP_EDGE = Color3.fromRGB(196, 178, 146)
local LACQUER_EMPTY = Color3.fromRGB(52, 62, 70)
local TRIM_EMPTY = Color3.fromRGB(112, 120, 126)
local TEXT_EMPTY = Color3.fromRGB(150, 168, 176)
local CURTAIN_SHUT = Color3.fromRGB(70, 104, 114)
local PANE_SHUT = Color3.fromRGB(20, 30, 36)
local UNLIT = Color3.fromRGB(78, 74, 66)
-- Den hearts: the heart on the nameplate, and the Best Dens frame's gold and gems
local HEART = Color3.fromRGB(255, 96, 122)
local FRAME_GOLD = Color3.fromRGB(236, 172, 44)
local FRAME_GEM = Color3.fromRGB(255, 232, 150)

local DRIFT = Color3.fromRGB(132, 104, 76)
local DRIFT_DARK = Color3.fromRGB(96, 74, 52)
local ROPE = Color3.fromRGB(196, 170, 120)
local BONE = Color3.fromRGB(232, 226, 206)
local BONE_SHADE = Color3.fromRGB(204, 196, 174)
local BASALT = Color3.fromRGB(34, 32, 44)
local BASALT_LIGHT = Color3.fromRGB(56, 52, 70)
local CARTILAGE = Color3.fromRGB(84, 92, 96)
local GUM = Color3.fromRGB(118, 64, 70)
local TOOTH = Color3.fromRGB(236, 232, 220)

-- The doorway's shape (Cave.denDoor), in the door's frame (Layout.doorFrame: the
-- portal's middle, -Z toward the hub)
local WALL_Z = -9 -- the cavern wall's face (hub.radius)
local ARCH_IN = 11 -- the arch stones' inner edge (the alcove's radius is 10.5)
local ARCH_OUT = 15
local DEPTH = 3.0 -- how far the stones stand out from the wall
local PLAQUE = Vector2.new(18.6, 6.0)

-- Something that glows while someone lives in the den, and goes dark when no one
-- does: a lantern's glass, a crystal's core, a rune, a lure
type Glow = { part: BasePart, light: Light?, color: Color3, material: Enum.Material, transparency: number }

-- What a style built, for the sign and the lights
type Look = {
	curtain: Color3, -- the portal's shimmer
	pane: Color3, -- the dark behind it
	board: Color3, -- the nameplate's board, trim and corner bosses
	trim: Color3,
	boss: Color3,
}
type Built = {
	plaque: Decor.Plaque,
	glows: { Glow },
	curtain: BasePart,
	pane: BasePart,
	bubbles: ParticleEmitter,
	shimmer: ParticleEmitter,
	glow: PointLight,
	look: Look,
	badge: Frame?, -- the heart count (built with the den's first heart)
	badgeCount: TextLabel?,
	frame: { BasePart }?, -- the Best Dens frame, while it's worn
}
type Door = {
	model: Model, -- the doorway (threshold and steps, and the style under it)
	style: Model?, -- the style's parts
	styleId: string?,
	built: Built?,
	owner: string?,
	levelName: string?,
	exit: boolean?, -- the way out inside the den (DenDoor.exit)
	hearts: number?, -- den hearts (HeartService), while someone lives there
	framed: boolean?, -- the Best Dens frame this week
}

local doors: { [number]: Door } = {}
local exits: { [number]: Door } = {}

-- The way out's portal glows brighter than a doorway's (it's what you look for in
-- your den): its light's range and brightness
local EXIT_GLOW_RANGE = 30
local EXIT_GLOW = 1.4

local function glowOf(p: BasePart, light: Light?, color: Color3): Glow
	return { part = p, light = light, color = color, material = p.Material, transparency = p.Transparency }
end

-- A lantern (Decor.lantern) whose glass and light are this style's color
local function lantern(
	glows: { Glow },
	parent: Instance,
	at: CFrame,
	armToward: number,
	color: Color3,
	range: number
)
	local made = Decor.lantern(parent, at, armToward, true, range, color)
	table.insert(glows, glowOf(made.glass, made.light, color))
end

-- A cylinder from `a` to `b` (door-frame points through `frame`)
local function rod(
	parent: Instance,
	name: string,
	frame: CFrame,
	a: Vector3,
	b: Vector3,
	radius: number,
	color: Color3,
	collide: boolean
): Part?
	local from, to = frame * a, frame * b
	local length = (to - from).Magnitude
	if length < 0.05 then
		return nil
	end
	local axis = (to - from).Unit
	local ref = if math.abs(axis.Y) < 0.9 then Vector3.new(0, 1, 0) else Vector3.new(1, 0, 0)
	local back = axis:Cross(ref).Unit
	local up = back:Cross(axis)
	return part(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length + radius * 0.6, radius * 2, radius * 2),
		CFrame = CFrame.fromMatrix((from + to) / 2, axis, up, back),
		Color = color,
		CanCollide = collide,
	})
end

-- A row of rods through door-frame points, tapering from `r0` to `r1`
local function curve(
	parent: Instance,
	name: string,
	frame: CFrame,
	points: { Vector3 },
	r0: number,
	r1: number,
	color: Color3,
	collide: boolean
)
	for i = 1, #points - 1 do
		local t = (i - 1) / math.max(#points - 2, 1)
		rod(parent, name, frame, points[i], points[i + 1], r0 + (r1 - r0) * t, color, collide)
	end
end

-- The arch over an opening of radius `inner` (its middle at `frame`, the wall at
-- local z `wall`, the stones standing out toward -Z, springing at y 0) and its
-- jambs down to `floor`: eleven rounded stones over the top and four a side,
-- overlapping, on a darker band of mortar so no rock shows between them. Returns
-- the jambs' middle (x) and the stones' middle (z).
local function arch(
	parent: Instance,
	frame: CFrame,
	inner: number,
	outer: number,
	wall: number,
	floor: number,
	seed: number,
	palette: Palette?
): (number, number)
	local colors = palette or SANDSTONE
	local rng = Random.new(seed)
	local thick = outer - inner
	local z = wall - DEPTH / 2 + 0.3 -- sunk a little into the rock
	local mid = (inner + outer) / 2
	local count = 11
	local step = math.pi / (count - 1)
	-- The mortar band: flat blocks against the wall behind the stones
	local bands = 6
	for i = 0, bands - 1 do
		local theta = (i + 0.5) * math.pi / bands
		local chord = 2 * mid * math.sin(math.pi / bands / 2) + 0.6
		part(parent, {
			Name = "ArchMortar",
			Size = Vector3.new(chord, thick + 0.5, 1.2),
			CFrame = frame
				* CFrame.new(math.cos(theta) * mid, math.sin(theta) * mid, wall - 0.4)
				* CFrame.Angles(0, 0, theta - math.pi / 2),
			Color = colors.mortar,
			CanCollide = false,
		})
	end
	for i = 0, count - 1 do
		-- 0 = the right springing (local +X), up over the top to the left
		local theta = i * step
		local length = mid * step * 1.42
		local stone = Decor.pebble(
			parent,
			"ArchStone",
			frame
				* CFrame.new(math.cos(theta) * mid, math.sin(theta) * mid, z)
				* CFrame.Angles(0, 0, theta - math.pi / 2),
			Vector3.new(length * rng:NextNumber(0.95, 1.06), thick * rng:NextNumber(0.98, 1.08), DEPTH),
			colors.stones[(i % #colors.stones) + 1]
		)
		stone.CanCollide = true
	end
	-- The jambs: four stones a side from the floor up to the springing, the bottom
	-- one bigger, on their own mortar
	local jambX = inner + thick / 2 - 1.0 -- hugging the sill's straight sides (it's 18 wide)
	local heights = { 4.2, 3.6, 3.4, 3.2 }
	local total = 0
	for _, h in heights do
		total += h
	end
	local scale = (0.6 - floor) / total
	for side = -1, 1, 2 do
		part(parent, {
			Name = "ArchMortar",
			Size = Vector3.new(thick + 0.5, -floor + 0.4, 1.2),
			CFrame = frame * CFrame.new(side * jambX, floor / 2 + 0.2, wall - 0.4),
			Color = colors.mortar,
			CanCollide = false,
		})
		local y = floor
		for k, h in heights do
			local height = h * scale
			local width = thick * (if k == 1 then 1.16 else 1.04) * rng:NextNumber(0.97, 1.05)
			local stone = Decor.pebble(
				parent,
				"JambStone",
				frame * CFrame.new(side * (jambX + (if k == 1 then 0.2 else 0)), y + height / 2, z),
				Vector3.new(width, height * 1.18, DEPTH * (if k == 1 then 1.08 else 1)),
				colors.jambs[((k + (if side > 0 then 0 else 1)) % #colors.jambs) + 1]
			)
			stone.CanCollide = true
			y += height
		end
	end
	return jambX, z
end

-- Coral, sponges and kelp at a jamb's foot (`side` is the local X sign, `x` the
-- jamb's outer edge, `z` the stones' middle)
local function growth(
	parent: Instance,
	frame: CFrame,
	side: number,
	x: number,
	floor: number,
	z: number,
	rng: Random
)
	Decor.pebble(
		parent,
		"BrainCoral",
		frame * CFrame.new(side * (x + 0.6), floor + 1.0, z - 0.8) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
		Vector3.new(2.6, 2.0, 2.4),
		Decor.CORALS[rng:NextInteger(1, #Decor.CORALS)]
	).CanCollide =
		true
	Decor.sponges(parent, frame * CFrame.new(side * (x + 2.6), floor, z - 1.2), 2, rng)
	-- Kelp climbing the wall beside the arch
	Decor.kelp(parent, frame * CFrame.new(side * (x + 3.4), floor, z + 0.6), 3, 3.8, rng)
end

-- A branching staghorn coral from `base` (its up), every branch tapering
local function staghorn(
	parent: Instance,
	base: CFrame,
	length: number,
	thick: number,
	depth: number,
	color: Color3
)
	local tip = base * CFrame.new(0, length, 0)
	Decor.upright(parent, "Staghorn", base, length, thick / 2).Color = if depth == 0
		then color:Lerp(Color3.new(1, 1, 1), 0.3)
		else color
	if depth > 0 then
		for i = 1, 2 do
			local spread = math.rad(30) * (if i == 1 then 1 else -1)
			staghorn(
				parent,
				tip * CFrame.Angles(0, i * 1.7 + depth, 0) * CFrame.Angles(spread, 0, 0),
				length * 0.7,
				thick * 0.72,
				depth - 1,
				color
			)
		end
	end
end

-- A crystal shard standing on `base` (its up): a glass prism, a lit core and a
-- pointed tip. Returns its core.
local function shard(parent: Instance, base: CFrame, length: number, width: number, color: Color3): Part
	local body = length * 0.8
	part(parent, {
		Name = "Shard",
		Size = Vector3.new(width, body, width),
		CFrame = base * CFrame.new(0, body / 2, 0),
		Color = color,
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		CanCollide = false,
		CastShadow = false,
	})
	local core = part(parent, {
		Name = "ShardCore",
		Size = Vector3.new(width * 0.45, body * 0.86, width * 0.45),
		CFrame = base * CFrame.new(0, body / 2, 0),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	local tip = length - body
	for k = 0, 1 do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "ShardTip"
		wedge.Anchored = true
		wedge.CanCollide = false
		wedge.CanQuery = false
		wedge.CanTouch = false
		wedge.CastShadow = false
		wedge.Material = Enum.Material.Glass
		wedge.Transparency = 0.2
		wedge.Color = color:Lerp(Color3.new(1, 1, 1), 0.25)
		wedge.Size = Vector3.new(width, tip, width / 2)
		wedge.CFrame = base
			* CFrame.new(0, body + tip / 2, 0)
			* CFrame.Angles(0, k * math.pi, 0)
			* CFrame.new(0, 0, -width / 4)
		wedge.Parent = parent
	end
	return core
end

-- The portal: a dark pane in a stepped collar, a faint ForceField shimmer over it,
-- bubbles rising across it and a soft light in front, in the style's colors
type PaneLook = { collar: Color3, ring: Color3, curtain: Color3, pane: Color3, glow: Color3 }
local function pane(
	parent: Instance,
	frame: CFrame,
	radius: number,
	look: PaneLook
): (BasePart, BasePart, ParticleEmitter, ParticleEmitter, PointLight)
	Decor.disc(parent, "PortalCollar", frame * CFrame.new(0, 0, 0.35), radius + 1.35, 0.4).Color = look.collar
	Decor.disc(parent, "PortalRing", frame * CFrame.new(0, 0, 0.25), radius + 0.75, 0.4).Color = look.ring
	local backing = Decor.disc(parent, "PortalPane", frame * CFrame.new(0, 0, 0.1), radius, 0.6)
	backing.Color = look.pane
	local curtain = Decor.disc(parent, "Portal", frame * CFrame.new(0, 0, -0.35), radius, 0.2)
	curtain.Color = look.curtain
	curtain.Material = Enum.Material.ForceField
	curtain.Transparency = 0.55
	-- Bubbles rise across the whole opening (any that start outside the circle are
	-- in the rock behind it)
	local sheet = part(parent, {
		Name = "PortalBubbles",
		Size = Vector3.new(radius * 2, radius * 2, 0.4),
		CFrame = frame * CFrame.new(0, 0, -0.75),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "Bubbles"
	bubbles.Rate = 26
	bubbles.Lifetime = NumberRange.new(2.2, 3.4)
	bubbles.Speed = NumberRange.new(1.5, 3)
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.SpreadAngle = Vector2.new(8, 8)
	bubbles.Acceleration = Vector3.new(0, 1.5, 0)
	bubbles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.3, 0.42),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	bubbles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.12, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	bubbles.LightEmission = 0.45
	bubbles.Color = ColorSequence.new(Color3.fromRGB(214, 250, 255))
	bubbles.Parent = sheet
	local shimmer = Instance.new("ParticleEmitter")
	shimmer.Name = "Shimmer"
	shimmer.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	shimmer.Rate = 5
	shimmer.Lifetime = NumberRange.new(1, 1.6)
	shimmer.Speed = NumberRange.new(0.2, 0.6)
	shimmer.SpreadAngle = Vector2.new(180, 180)
	shimmer.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	shimmer.Transparency = NumberSequence.new(0.35, 1)
	shimmer.LightEmission = 1
	shimmer.Color = ColorSequence.new(look.curtain:Lerp(Color3.new(1, 1, 1), 0.5))
	shimmer.Parent = sheet
	local lamp = part(parent, {
		Name = "PortalGlow",
		Size = Vector3.one,
		CFrame = frame * CFrame.new(0, 0, -4),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	local glow = Instance.new("PointLight")
	glow.Color = look.glow
	glow.Range = 16
	glow.Brightness = 0.5
	glow.Parent = lamp
	return curtain, backing, bubbles, shimmer, glow
end

local STONE_PANE: PaneLook = {
	collar = Decor.BRASS_DARK,
	ring = Decor.BRASS,
	curtain = Color3.fromRGB(110, 206, 224),
	pane = Color3.fromRGB(10, 38, 52),
	glow = Color3.fromRGB(130, 222, 232),
}

-- The nameplate over a doorway: its middle `y` up, standing out in front of `z`
local function plaque(parent: Instance, frame: CFrame, y: number, z: number): Decor.Plaque
	return Decor.plaque(parent, frame * CFrame.new(0, y, z), PLAQUE, Decor.LACQUER, true)
end

-- Which local X side of den `index`'s doorway opens onto a tunnel's mouth (the
-- doors either side of a tunnel nearly touch it), or 0
local function tunnelSide(index: number): number
	local frame = Layout.doorFrame(index)
	local here = math.atan2(frame.Position.Z - hub.center.Z, frame.Position.X - hub.center.X)
	for _, delta in { -1, 1 } do
		local angle = here + delta * 2 * math.pi / hub.segments
		local segment = math.floor(((angle % (2 * math.pi)) / (2 * math.pi)) * hub.segments + 0.5)
				% hub.segments
			+ 1
		if Layout.segmentKind(segment) == "tunnel" then
			local probe = hub.center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * hub.radius
			local x = frame:PointToObjectSpace(Vector3.new(probe.X, frame.Position.Y, probe.Z)).X
			return if x > 0 then 1 else -1
		end
	end
	return 0
end

-- What a style's builder is given: where, the doorway's floor (local y), its index
-- (seeds), the side a tunnel opens on (no growth there) and a seeded Random
type Site = { frame: CFrame, floor: number, index: number, open: number, rng: Random }
type Parts = { plaque: Decor.Plaque, glows: { Glow }, pane: PaneLook, look: Look }

local STYLES: { [string]: (Model, Site) -> Parts } = {}

-- The Stone Arch: rounded sandstone over brass lanterns, coral and kelp at its feet
STYLES.Stone = function(folder: Model, site: Site): Parts
	local frame = site.frame
	local jambX, stoneZ = arch(folder, frame, ARCH_IN, ARCH_OUT, WALL_Z, site.floor, World.seed + site.index)
	local outerX = jambX + (ARCH_OUT - ARCH_IN) / 2
	local glows: { Glow } = {}
	for side = -1, 1, 2 do
		lantern(
			glows,
			folder,
			frame * CFrame.new(side * (outerX + 1.2), -2.2, stoneZ - 0.4),
			-side,
			Decor.GLASS_LIT,
			14
		)
	end
	for side = -1, 1, 2 do
		if side ~= site.open then
			growth(folder, frame, side, outerX, site.floor, stoneZ, site.rng)
		end
	end
	return {
		plaque = plaque(folder, frame, ARCH_IN + PLAQUE.Y / 2 - 0.4, WALL_Z - DEPTH - 0.1),
		glows = glows,
		pane = STONE_PANE,
		look = {
			curtain = STONE_PANE.curtain,
			pane = STONE_PANE.pane,
			board = Decor.LACQUER,
			trim = Decor.BRASS,
			boss = Decor.BRASS_LIGHT,
		},
	}
end

-- The Kelp Curtain: two crooked driftwood posts under a lintel, kelp hanging in
-- swags down the sides and a fringe across the top, green lanterns on chains
STYLES.KelpCurtain = function(folder: Model, site: Site): Parts
	local frame, floor, rng = site.frame, site.floor, site.rng
	local green = Color3.fromRGB(170, 255, 140)
	local z = WALL_Z - 1.6
	for side = -1, 1, 2 do
		rod(
			folder,
			"Post",
			frame,
			Vector3.new(side * 12.8, floor - 0.5, z),
			Vector3.new(side * 12.3, 13.4, z - 0.2),
			1.3,
			DRIFT,
			true
		)
		-- knots and a split along the post
		for k = 1, 3 do
			Decor.pebble(
				folder,
				"Knot",
				frame * CFrame.new(side * (12.6 + 0.9), floor + k * 5.2, z - 0.3),
				Vector3.new(0.9, 1.3, 1.0),
				DRIFT_DARK
			)
		end
		Decor.pebble(
			folder,
			"PostFoot",
			frame * CFrame.new(side * 12.9, floor + 0.6, z),
			Vector3.new(3.6, 1.6, 3.4),
			DRIFT_DARK
		).CanCollide =
			true
	end
	local lintel = part(folder, {
		Name = "Lintel",
		Size = Vector3.new(33, 2.2, 2.6),
		CFrame = frame * CFrame.new(0, 13.6, z - 0.3) * CFrame.Angles(0, 0, math.rad(1.2)),
		Color = DRIFT,
		CanCollide = true,
	})
	for side = -1, 1, 2 do
		Decor.pebble(
			folder,
			"LintelEnd",
			frame * CFrame.new(side * 16.5, 13.6, z - 0.3),
			Vector3.new(2.2, 2.4, 2.8),
			DRIFT
		)
		-- rope lashed round the joint
		for k = -1, 1, 2 do
			part(folder, {
				Name = "Lashing",
				Size = Vector3.new(0.35, 3.6, 3.0),
				CFrame = frame
					* CFrame.new(side * 12.4, 13.2, z - 0.3)
					* CFrame.Angles(0, 0, math.rad(k * 35)),
				Color = ROPE,
				CanCollide = false,
			})
		end
	end
	part(folder, {
		Name = "Beam",
		Size = Vector3.new(27, 1.4, 1.8),
		CFrame = frame * CFrame.new(0, 15.6, z + 0.4) * CFrame.Angles(0, 0, math.rad(-0.8)),
		Color = DRIFT_DARK,
		CanCollide = false,
	})
	local underside = lintel.CFrame * CFrame.new(0, -1.1, -0.6)
	-- Swags of kelp down each side, gathered by a rope at waist height
	for side = -1, 1, 2 do
		for k = 1, 9 do
			local x = side * (9.2 + k * 0.85)
			local length = rng:NextNumber(11, 17) - k * 0.5
			Decor.pebble(
				folder,
				"KelpSwag",
				underside
					* CFrame.new(x, -length / 2, rng:NextNumber(-0.4, 0.4))
					* CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), side * rng:NextNumber(0.02, 0.1)),
				Vector3.new(2.3, length, 0.3),
				Decor.KELP[(k % #Decor.KELP) + 1]
			).CastShadow =
				false
		end
		Decor.pebble(
			folder,
			"TieBack",
			underside * CFrame.new(side * 12.9, -9.5, -0.2),
			Vector3.new(6.2, 0.7, 1.6),
			ROPE
		)
	end
	-- The fringe over the opening (it doesn't collide: fish swim through it)
	local x = -9.2
	while x <= 9.2 do
		local length = rng:NextNumber(2.4, 4.4)
		Decor.pebble(
			folder,
			"KelpFringe",
			underside
				* CFrame.new(x, -length / 2, rng:NextNumber(-0.3, 0.3))
				* CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), rng:NextNumber(-0.12, 0.12)),
			Vector3.new(1.9, length, 0.25),
			Decor.KELP[rng:NextInteger(1, #Decor.KELP)]:Lerp(Color3.fromRGB(200, 230, 90), 0.2)
		).CastShadow =
			false
		x += 1.4
	end
	-- Lanterns on chains from the lintel's ends
	local glows: { Glow } = {}
	for side = -1, 1, 2 do
		part(folder, {
			Name = "Chain",
			Size = Vector3.new(0.18, 2.4, 0.18),
			CFrame = frame * CFrame.new(side * 16.6, 11.4, z - 0.9),
			Color = Decor.IRON,
			CanCollide = false,
		})
		lantern(glows, folder, frame * CFrame.new(side * 16.6, 8.6, z - 0.9), 0, green, 16)
		if side ~= site.open then
			Decor.kelp(folder, frame * CFrame.new(side * 16.4, floor, z + 0.4), 4, 4.2, rng)
			Decor.sponges(folder, frame * CFrame.new(side * 15.2, floor, z - 2.2), 3, rng)
		end
	end
	local look: PaneLook = {
		collar = DRIFT_DARK,
		ring = DRIFT,
		curtain = Color3.fromRGB(140, 230, 170),
		pane = Color3.fromRGB(10, 40, 30),
		glow = green,
	}
	return {
		plaque = plaque(folder, frame, 17.4, z - 2.4),
		glows = glows,
		pane = look,
		look = {
			curtain = look.curtain,
			pane = look.pane,
			board = Color3.fromRGB(34, 70, 48),
			trim = DRIFT,
			boss = ROPE,
		},
	}
end

-- The Coral Arch: reef rock grown over with brain corals, staghorn, two great
-- fans at its feet and anemones along the crown, lit by glowing anemones
STYLES.CoralArch = function(folder: Model, site: Site): Parts
	local frame, floor, rng = site.frame, site.floor, site.rng
	local jambX, stoneZ =
		arch(folder, frame, ARCH_IN, ARCH_OUT, WALL_Z, floor, World.seed + 40 + site.index, REEF_ROCK)
	local outerX = jambX + (ARCH_OUT - ARCH_IN) / 2
	local front = stoneZ - DEPTH / 2
	-- Brain corals on the arch's shoulders
	for k, deg in { 18, 52, 128, 162 } do
		local a = math.rad(deg)
		Decor.pebble(
			folder,
			"BrainCoral",
			frame * CFrame.new(math.cos(a) * 15.2, math.sin(a) * 15.2, front + 0.4) * CFrame.Angles(0, 0, a),
			Vector3.new(3.6, 3.0, 3.2) * rng:NextNumber(0.85, 1.1),
			Decor.CORALS[(k % #Decor.CORALS) + 1]
		)
	end
	-- Staghorn branching out of the arch
	for k, deg in { 35, 145 } do
		local a = math.rad(deg)
		staghorn(
			folder,
			frame
				* CFrame.new(math.cos(a) * 14.4, math.sin(a) * 14.4, front + 0.8)
				* CFrame.Angles(0, 0, a - math.pi / 2),
			2.8,
			0.7,
			2,
			Decor.CORALS[((k + 2) % #Decor.CORALS) + 1]
		)
	end
	-- Two great fans at the arch's feet, facing the plaza
	for side = -1, 1, 2 do
		local fanColor = if side < 0 then Color3.fromRGB(255, 120, 130) else Color3.fromRGB(196, 120, 236)
		local fan = Decor.disc(
			folder,
			"SeaFan",
			frame * CFrame.new(side * (outerX + 2.6), 1.4, front - 0.4) * CFrame.Angles(0, 0, side * 0.2),
			4.2,
			0.25
		)
		fan.Color = fanColor
		for r = -2, 2 do
			part(folder, {
				Name = "FanRib",
				Size = Vector3.new(0.22, 4.2, 0.32),
				CFrame = frame
					* CFrame.new(side * (outerX + 2.6), -2.4, front - 0.6)
					* CFrame.Angles(0, 0, r * 0.38 + side * 0.2)
					* CFrame.new(0, 2.1, 0),
				Color = fanColor:Lerp(Color3.new(0, 0, 0), 0.25),
				CanCollide = false,
			})
		end
	end
	-- Anemones along the crown, and two glowing ones by the opening that light it
	local glows: { Glow } = {}
	for k, deg in { 70, 110, 82, 98 } do
		local a = math.rad(deg)
		local at = frame * CFrame.new(math.cos(a) * 15.8, math.sin(a) * 15.8, front + 0.2)
		local color = Decor.CORALS[((k + 1) % #Decor.CORALS) + 1]
		Decor.upright(folder, "AnemoneStalk", at * CFrame.new(0, -0.6, 0), 1.4, 0.45).Color =
			color:Lerp(Color3.new(0, 0, 0), 0.2)
		Decor.pebble(folder, "Anemone", at * CFrame.new(0, 1.0, 0), Vector3.new(2.4, 1.3, 2.2), color)
	end
	for side = -1, 1, 2 do
		local bulb = Decor.pebble(
			folder,
			"GlowAnemone",
			frame * CFrame.new(side * (outerX + 0.6), -3.4, front - 0.6),
			Vector3.new(2.0, 1.6, 1.8),
			Color3.fromRGB(255, 170, 200)
		)
		bulb.Material = Enum.Material.Neon
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 170, 140)
		light.Range = 14
		light.Brightness = 0.9
		light.Parent = bulb
		table.insert(glows, glowOf(bulb, light, Color3.fromRGB(255, 170, 200)))
		if side ~= site.open then
			Decor.sponges(folder, frame * CFrame.new(side * (outerX + 2.2), floor, front - 1.0), 3, rng)
			Decor.starfish(
				folder,
				frame * CFrame.new(side * (outerX - 0.4), 4.8, front - 0.05),
				1.6,
				Color3.fromRGB(255, 140, 90)
			)
		end
	end
	local look: PaneLook = {
		collar = REEF_ROCK.mortar,
		ring = Color3.fromRGB(255, 160, 80),
		curtain = Color3.fromRGB(150, 220, 230),
		pane = Color3.fromRGB(16, 38, 56),
		glow = Color3.fromRGB(255, 190, 170),
	}
	return {
		plaque = plaque(folder, frame, 20.8, WALL_Z - DEPTH - 0.6),
		glows = glows,
		pane = look,
		look = {
			curtain = look.curtain,
			pane = look.pane,
			board = Decor.LACQUER,
			trim = Color3.fromRGB(255, 160, 80),
			boss = Color3.fromRGB(255, 214, 92),
		},
	}
end

-- The Brass Porthole: a ship's porthole the size of the door, a brass ring on a
-- riveted iron flange, hinges on one side and dogs to clamp it shut
STYLES.BrassPorthole = function(folder: Model, site: Site): Parts
	local frame, floor = site.frame, site.floor
	local function ring(
		name: string,
		radius: number,
		width: number,
		depth: number,
		z: number,
		count: number,
		color: Color3,
		collide: boolean
	)
		for i = 0, count - 1 do
			local a = (i + 0.5) / count * 2 * math.pi
			local y = math.sin(a) * radius
			if y < floor + 0.4 then
				continue -- under the sill
			end
			part(folder, {
				Name = name,
				Size = Vector3.new(2 * radius * math.sin(math.pi / count) + 0.12, width, depth),
				CFrame = frame
					* CFrame.new(math.cos(a) * radius, y, z)
					* CFrame.Angles(0, 0, a - math.pi / 2),
				Color = color,
				CanCollide = collide,
			})
		end
	end
	ring("Flange", 14.5, 3.0, 1.2, WALL_Z - 0.5, 36, Decor.IRON, false)
	ring("Ring", 12.3, 2.6, 2.4, WALL_Z - 1.4, 32, Decor.BRASS, true)
	ring("Lip", 11.2, 0.5, 2.9, WALL_Z - 1.5, 32, Decor.BRASS_DARK, true)
	ring("Bead", 13.7, 0.35, 0.5, WALL_Z - 2.7, 36, Decor.BRASS_LIGHT, false)
	-- Rivets round the flange and the ring
	for i = 0, 23 do
		local a = (i + 0.5) / 24 * 2 * math.pi
		for _, r in { 14.9, 12.3 } do
			local y = math.sin(a) * r
			if y > floor + 0.6 then
				part(folder, {
					Name = "Rivet",
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * (if r > 14 then 0.75 else 0.55),
					CFrame = frame * CFrame.new(math.cos(a) * r, y, WALL_Z - (if r > 14 then 1.2 else 2.65)),
					Color = Decor.BRASS_LIGHT,
					CanCollide = false,
					CastShadow = false,
				})
			end
		end
	end
	-- Hinges on the left, dogs (clamps) on the right
	for _, deg in { 150, 210 } do
		local a = math.rad(deg)
		local at = frame
			* CFrame.new(math.cos(a) * 15.6, math.sin(a) * 15.6, WALL_Z - 1.6)
			* CFrame.Angles(0, 0, a)
		part(folder, {
			Name = "Hinge",
			Size = Vector3.new(3.4, 2.6, 2.0),
			CFrame = at,
			Color = Decor.BRASS_DARK,
			CanCollide = false,
		})
		Decor.upright(folder, "HingePin", at * CFrame.new(1.7, -1.6, 0), 3.2, 0.45).Color = Decor.BRASS_LIGHT
	end
	for _, deg in { 20, 340, 62 } do
		local a = math.rad(deg)
		local at = frame
			* CFrame.new(math.cos(a) * 14.2, math.sin(a) * 14.2, WALL_Z - 2.4)
			* CFrame.Angles(0, 0, a)
		part(folder, {
			Name = "Dog",
			Size = Vector3.new(2.6, 0.9, 1.2),
			CFrame = at,
			Color = Decor.BRASS,
			CanCollide = false,
		})
		part(folder, {
			Name = "DogHandle",
			Size = Vector3.new(0.5, 2.2, 0.5),
			CFrame = at * CFrame.new(1.0, 0, -0.7),
			Color = Decor.BRASS_LIGHT,
			CanCollide = false,
		})
	end
	-- Ship's lanterns on iron arms either side
	local glows: { Glow } = {}
	local amber = Color3.fromRGB(255, 200, 110)
	for side = -1, 1, 2 do
		lantern(glows, folder, frame * CFrame.new(side * 18.6, 2.2, WALL_Z - 1.4), -side, amber, 16)
	end
	local look: PaneLook = {
		collar = Decor.IRON,
		ring = Decor.BRASS_DARK,
		curtain = Color3.fromRGB(150, 220, 230),
		pane = Color3.fromRGB(16, 44, 56),
		glow = amber,
	}
	return {
		plaque = plaque(folder, frame, 19.6, WALL_Z - 1.6),
		glows = glows,
		pane = look,
		look = {
			curtain = look.curtain,
			pane = look.pane,
			board = Color3.fromRGB(40, 46, 54),
			trim = Decor.BRASS,
			boss = Decor.BRASS_LIGHT,
		},
	}
end

-- The Whalebone Gate: two pairs of great curved ribs meeting over the door, a row
-- of vertebrae along the top, pale lanterns hung from the ribs
STYLES.Whalebone = function(folder: Model, site: Site): Parts
	local frame, floor = site.frame, site.floor
	for pair, spec in { { a = 16.6, b = 30, z = WALL_Z - 1.0 }, { a = 13.4, b = 28, z = WALL_Z - 3.6 } } do
		for side = -1, 1, 2 do
			local points: { Vector3 } = {}
			for k = 0, 9 do
				local theta = math.rad(k * 8.6)
				table.insert(
					points,
					Vector3.new(side * spec.a * math.cos(theta), floor + spec.b * math.sin(theta), spec.z)
				)
			end
			curve(
				folder,
				"Rib",
				frame,
				points,
				if pair == 1 then 1.35 else 1.2,
				0.55,
				if pair == 1 then BONE_SHADE else BONE,
				true
			)
			-- the knuckle where it meets the ground
			Decor.pebble(
				folder,
				"RibFoot",
				frame * CFrame.new(side * spec.a, floor + 0.8, spec.z),
				Vector3.new(3.4, 2.4, 3.2),
				BONE_SHADE
			).CanCollide =
				true
		end
	end
	-- Vertebrae along the top: each a disc with a spine up and wings out
	for k = -3, 3 do
		local at = frame * CFrame.new(k * 1.7, 18.9 - math.abs(k) * 0.2, WALL_Z - 2.3)
		Decor.pebble(folder, "Vertebra", at, Vector3.new(1.5, 1.6, 2.2), BONE)
		part(folder, {
			Name = "VertebraSpine",
			Size = Vector3.new(0.5, 2.4 - math.abs(k) * 0.2, 0.9),
			CFrame = at * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(k * -4)),
			Color = BONE_SHADE,
			CanCollide = false,
		})
		Decor.pebble(
			folder,
			"VertebraWing",
			at * CFrame.new(0, 0.2, -0.4),
			Vector3.new(0.6, 0.5, 3.2),
			BONE_SHADE
		)
	end
	-- Lanterns hung from the front ribs
	local glows: { Glow } = {}
	local pale = Color3.fromRGB(170, 240, 235)
	for side = -1, 1, 2 do
		lantern(glows, folder, frame * CFrame.new(side * 14.2, 2.4, WALL_Z - 4.8), -side, pale, 15)
		if side ~= site.open then
			Decor.kelp(folder, frame * CFrame.new(side * 17.4, floor, WALL_Z - 1.0), 3, 3.6, site.rng)
		end
	end
	local look: PaneLook = {
		collar = BONE_SHADE,
		ring = BONE,
		curtain = Color3.fromRGB(150, 226, 230),
		pane = Color3.fromRGB(12, 36, 46),
		glow = pale,
	}
	return {
		plaque = plaque(folder, frame, 25.2, WALL_Z - 2.6),
		glows = glows,
		pane = look,
		look = {
			curtain = look.curtain,
			pane = look.pane,
			board = Color3.fromRGB(70, 58, 46),
			trim = BONE,
			boss = BONE_SHADE,
		},
	}
end

-- The Crystal Grotto: dark violet rock with clusters of glowing crystal growing out
-- of it all round the door, cyan and violet
STYLES.CrystalGrotto = function(folder: Model, site: Site): Parts
	local frame, floor, rng = site.frame, site.floor, site.rng
	local jambX, stoneZ =
		arch(folder, frame, ARCH_IN, ARCH_OUT, WALL_Z, floor, World.seed + 80 + site.index, GROTTO_ROCK)
	local outerX = jambX + (ARCH_OUT - ARCH_IN) / 2
	local front = stoneZ - DEPTH / 2
	local cyan, violet = Color3.fromRGB(110, 230, 255), Color3.fromRGB(176, 110, 236)
	local glows: { Glow } = {}
	-- Clusters round the arch, the shards leaning out from the opening
	for k, deg in { 6, 28, 50, 130, 152, 174 } do
		local a = math.rad(deg)
		local base = frame
			* CFrame.new(math.cos(a) * 14.2, math.sin(a) * 14.2, front + 0.6)
			* CFrame.Angles(0, 0, a - math.pi / 2)
		local count = rng:NextInteger(5, 7)
		for s = 1, count do
			local color = if (s + k) % 2 == 0 then cyan else violet
			local length = rng:NextNumber(3.4, 7.2) * (if s == 1 then 1.25 else 1)
			local core = shard(
				folder,
				base
					* CFrame.new(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-0.8, 0.4))
					* CFrame.Angles(rng:NextNumber(-0.5, 0.2), 0, rng:NextNumber(-0.5, 0.5)),
				length,
				length * 0.3,
				color
			)
			if s == 1 then
				local light = Instance.new("PointLight")
				light.Color = color
				light.Range = 12
				light.Brightness = 0.8
				light.Parent = core
				table.insert(glows, glowOf(core, light, color))
			else
				table.insert(glows, glowOf(core, nil, color))
			end
		end
	end
	-- A bed of shards at each foot
	for side = -1, 1, 2 do
		for s = 1, 7 do
			local length = rng:NextNumber(2.4, 6)
			local color = if s % 2 == 0 then cyan else violet
			local core = shard(
				folder,
				frame
					* CFrame.new(
						side * (outerX + rng:NextNumber(0, 3.2)),
						floor,
						front - rng:NextNumber(0, 2.4)
					)
					* CFrame.Angles(rng:NextNumber(-0.35, 0.35), 0, -side * rng:NextNumber(0.05, 0.5)),
				length,
				length * 0.26,
				color
			)
			table.insert(glows, glowOf(core, nil, color))
		end
	end
	local look: PaneLook = {
		collar = GROTTO_ROCK.mortar,
		ring = violet,
		curtain = Color3.fromRGB(170, 150, 255),
		pane = Color3.fromRGB(16, 12, 40),
		glow = Color3.fromRGB(140, 220, 255),
	}
	return {
		plaque = plaque(folder, frame, ARCH_IN + PLAQUE.Y / 2 - 0.4, WALL_Z - DEPTH - 0.1),
		glows = glows,
		pane = look,
		look = {
			curtain = look.curtain,
			pane = look.pane,
			board = Color3.fromRGB(40, 30, 70),
			trim = Color3.fromRGB(150, 210, 240),
			boss = Color3.fromRGB(200, 240, 255),
		},
	}
end

-- The Abyssal Gate: a pointed arch of black stone on square pillars, violet runes
-- glowing in it, spines along its back and two angler lures on stalks
STYLES.AbyssalGate = function(folder: Model, site: Site): Parts
	local frame, floor = site.frame, site.floor
	local rune = Color3.fromRGB(170, 90, 255)
	local lureColor = Color3.fromRGB(90, 240, 255)
	local z = WALL_Z - 1.6
	local glows: { Glow } = {}
	local function runeBar(at: CFrame, size: Vector3)
		local bar = part(folder, {
			Name = "Rune",
			Size = size,
			CFrame = at,
			Color = rune,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
		table.insert(glows, glowOf(bar, nil, rune))
	end
	for side = -1, 1, 2 do
		part(folder, {
			Name = "Plinth",
			Size = Vector3.new(4.4, 1.8, 4.4),
			CFrame = frame * CFrame.new(side * 13.6, floor + 0.9, z),
			Color = BASALT_LIGHT,
			CanCollide = true,
		})
		part(folder, {
			Name = "Pillar",
			Size = Vector3.new(2.8, 6 - floor, 3.2),
			CFrame = frame * CFrame.new(side * 13.6, (6 + floor) / 2, z),
			Color = BASALT,
			CanCollide = true,
		})
		part(folder, {
			Name = "Capital",
			Size = Vector3.new(4.0, 1.3, 4.0),
			CFrame = frame * CFrame.new(side * 13.6, 6.4, z),
			Color = BASALT_LIGHT,
			CanCollide = true,
		})
		for k = 0, 2 do
			local y = floor + 4 + k * 4.4
			runeBar(frame * CFrame.new(side * 13.6, y, z - 1.65), Vector3.new(0.3, 1.8, 0.2))
			runeBar(
				frame
					* CFrame.new(side * 13.6, y + (k % 2) * 0.5 - 0.2, z - 1.65)
					* CFrame.Angles(0, 0, math.rad(55)),
				Vector3.new(0.25, 1.1, 0.2)
			)
		end
		-- One side of the pointed arch: an arc about a center on the other side
		local cx, r = -side * 7, 20
		local stop = math.acos(7 / r)
		local steps = 8
		for k = 0, steps - 1 do
			local a0, a1 = stop * k / steps, stop * (k + 1) / steps
			local p0 = Vector3.new(cx + side * r * math.cos(a0), 6.6 + r * math.sin(a0), z)
			local p1 = Vector3.new(cx + side * r * math.cos(a1), 6.6 + r * math.sin(a1), z)
			local mid = (p0 + p1) / 2
			local along = math.atan2(p1.Y - p0.Y, p1.X - p0.X)
			local at = frame * CFrame.new(mid) * CFrame.Angles(0, 0, along)
			part(folder, {
				Name = "GateStone",
				Size = Vector3.new((p1 - p0).Magnitude + 0.2, 2.8, 3.0),
				CFrame = at,
				Color = if k % 2 == 0 then BASALT else BASALT_LIGHT,
				CanCollide = true,
			})
			runeBar(at * CFrame.new(0, 0, -1.55), Vector3.new(0.9, 0.25, 0.2))
			-- a spine along its back, pointing out from the opening
			local tangent = (p1 - p0).Unit
			local outward = Vector3.new(tangent.Y, -tangent.X, 0) * side
			Decor.triangle(
				folder,
				frame * (mid + tangent * 0.7 + outward * 1.2 + Vector3.new(0, 0, 0.4)),
				frame * (mid - tangent * 0.7 + outward * 1.2 + Vector3.new(0, 0, 0.4)),
				frame * (mid + outward * 3.4 + Vector3.new(0, 0, 0.4)),
				1.0,
				{ Name = "Spine", Color = BASALT_LIGHT }
			)
		end
		-- An angler lure on a stalk from the capital, bending out toward the plaza
		local base = Vector3.new(side * 14.4, 7, z)
		curve(folder, "LureStalk", frame, {
			base,
			Vector3.new(side * 15.4, 10.4, z - 0.8),
			Vector3.new(side * 16.6, 13.6, z - 2.6),
			Vector3.new(side * 16.8, 15.8, z - 5),
			Vector3.new(side * 15.8, 16.2, z - 7.2),
		}, 0.42, 0.22, BASALT_LIGHT, false)
		local lure = part(folder, {
			Name = "Lure",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.6,
			CFrame = frame * CFrame.new(side * 15.6, 15.2, z - 7.6),
			Color = lureColor,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
		local light = Instance.new("PointLight")
		light.Color = lureColor
		light.Range = 18
		light.Brightness = 1.1
		light.Parent = lure
		table.insert(glows, glowOf(lure, light, lureColor))
	end
	-- The keystone with a violet eye
	local key = frame * CFrame.new(0, 6.6 + math.sqrt(20 * 20 - 49), z)
	part(folder, {
		Name = "Keystone",
		Size = Vector3.new(3.2, 3.6, 3.4),
		CFrame = key,
		Color = BASALT_LIGHT,
		CanCollide = true,
	})
	local eye =
		Decor.pebble(folder, "KeystoneEye", key * CFrame.new(0, 0, -1.75), Vector3.new(1.6, 1.0, 0.4), rune)
	eye.Material = Enum.Material.Neon
	table.insert(glows, glowOf(eye, nil, rune))
	local look: PaneLook = {
		collar = BASALT,
		ring = BASALT_LIGHT,
		curtain = Color3.fromRGB(150, 90, 255),
		pane = Color3.fromRGB(14, 8, 30),
		glow = rune,
	}
	return {
		plaque = plaque(folder, frame, 14.4, z - 2.0),
		glows = glows,
		pane = look,
		look = {
			curtain = look.curtain,
			pane = look.pane,
			board = Color3.fromRGB(24, 20, 34),
			trim = Color3.fromRGB(110, 60, 170),
			boss = rune,
		},
	}
end

-- The Megalodon Jaws: the door is an open mouth, an upper jaw arching over it with
-- two rows of teeth, a lower jaw along the sill, the hinges at its sides
STYLES.MegalodonJaws = function(folder: Model, site: Site): Parts
	local frame, floor = site.frame, site.floor
	local z = WALL_Z - 1.8
	local cy = -1
	local function jaw(t: number, rx: number, ry: number): Vector3
		return Vector3.new(math.cos(t) * rx, cy + math.sin(t) * ry, 0)
	end
	-- The upper jaw: rounded cartilage over a band of gum
	local count = 13
	for i = 0, count - 1 do
		local t0 = math.rad(4 + 172 * i / count)
		local t1 = math.rad(4 + 172 * (i + 1) / count)
		local tm = (t0 + t1) / 2
		local p = jaw(tm, 14.4, 14.6)
		local seg = (jaw(t1, 14.4, 14.6) - jaw(t0, 14.4, 14.6)).Magnitude
		Decor.pebble(
			folder,
			"Jaw",
			frame * CFrame.new(p.X, p.Y, z) * CFrame.Angles(0, 0, tm - math.pi / 2),
			Vector3.new(seg * 1.35, 3.0, 3.4),
			if i % 2 == 0 then CARTILAGE else CARTILAGE:Lerp(Color3.new(1, 1, 1), 0.08)
		).CanCollide =
			true
		local g = jaw(tm, 12.9, 13.1)
		Decor.pebble(
			folder,
			"Gum",
			frame * CFrame.new(g.X, g.Y, z - 0.4) * CFrame.Angles(0, 0, tm - math.pi / 2),
			Vector3.new(seg * 1.3, 1.2, 2.6),
			GUM
		)
	end
	-- Two rows of teeth pointing in (they don't collide: they stop at the opening's edge)
	local function tooth(t: number, base: number, reach: number, width: number, zz: number, color: Color3)
		local root = jaw(t, 12.2 * base, 12.4 * base)
		local tangent = Vector3.new(-math.sin(t), math.cos(t), 0)
		local inward = -Vector3.new(math.cos(t), math.sin(t), 0)
		local a = frame * (root + tangent * width / 2 + Vector3.new(0, 0, zz))
		local b = frame * (root - tangent * width / 2 + Vector3.new(0, 0, zz))
		local c = frame * (root + inward * reach + Vector3.new(0, 0, zz - 0.4))
		Decor.triangle(folder, a, b, c, 0.5, { Name = "Tooth", Color = color })
	end
	for i = 0, 14 do
		tooth(math.rad(14 + 152 * i / 14), 1, 2.3, 1.6, z - 1.0, TOOTH)
	end
	for i = 0, 13 do
		tooth(math.rad(19 + 142 * i / 13), 1.02, 1.6, 1.2, z - 0.2, TOOTH:Lerp(Color3.new(0, 0, 0), 0.1))
	end
	-- The lower jaw along the sill, bowed out over the threshold, small teeth up
	local lower = 9
	for i = 0, lower - 1 do
		local x = -12 + 24 * (i + 0.5) / lower
		local bow = z - 1.2 - 2.4 * (1 - (x / 12.5) ^ 2)
		Decor.pebble(
			folder,
			"LowerJaw",
			frame * CFrame.new(x, floor + 0.35, bow),
			Vector3.new(3.2, 1.1, 2.2),
			CARTILAGE
		)
		local a = frame * Vector3.new(x - 0.6, floor + 0.8, bow - 0.5)
		local b = frame * Vector3.new(x + 0.6, floor + 0.8, bow - 0.5)
		local c = frame * Vector3.new(x, floor + 2.0, bow - 0.8)
		Decor.triangle(folder, a, b, c, 0.4, { Name = "Tooth", Color = TOOTH })
	end
	-- The hinges
	for side = -1, 1, 2 do
		Decor.pebble(
			folder,
			"Hinge",
			frame * CFrame.new(side * 15.2, -3.5, z + 0.4),
			Vector3.new(4.0, 5.2, 4.0),
			CARTILAGE:Lerp(Color3.new(0, 0, 0), 0.12)
		).CanCollide =
			true
	end
	local glows: { Glow } = {}
	local ghost = Color3.fromRGB(196, 255, 170)
	for side = -1, 1, 2 do
		lantern(glows, folder, frame * CFrame.new(side * 18.8, 4.2, WALL_Z - 1.4), -side, ghost, 16)
	end
	local look: PaneLook = {
		collar = CARTILAGE,
		ring = GUM,
		curtain = Color3.fromRGB(176, 240, 190),
		pane = Color3.fromRGB(10, 30, 26),
		glow = ghost,
	}
	return {
		plaque = plaque(folder, frame, 19.2, WALL_Z - 2.4),
		glows = glows,
		pane = look,
		look = {
			curtain = look.curtain,
			pane = look.pane,
			board = Color3.fromRGB(40, 52, 56),
			trim = TOOTH,
			boss = ghost,
		},
	}
end

-- A nameplate set into the rock is moved out in front of it: the cavern wall leans
-- out over the doorways, to ~4 studs in front of WALL_Z at the taller styles' plates
-- (PC 2026-10-19, DN1: the Brass Porthole's, 1.6 out, showed only "NAIRE138'S"; the
-- Whalebone's and the Megalodon Jaws' corners were in the rock). Once the Terrain
-- answers rays (tried every half second for 10 s); never moved back.
-- With `under` (the way out) it's also lowered under the vault as carved: the voxel
-- surface hangs a few studs under the arch underVault works out (PC 2026-10-20, DX:
-- rock at 35.6 studs over the deck where the arch says 39, and the Whalebone's TO THE
-- HUB line, 31.8–36.9 up, was in it).
local ROOF_CLEAR = 0.6
local function lowerUnderRoof(frame: CFrame, plate: Decor.Plaque, params: RaycastParams)
	local board = plate.board
	local at = frame:PointToObjectSpace(board.Position)
	local top = at.Y + board.Size.Y / 2
	local roof = math.huge
	for _, fx in { -0.5, -0.25, 0, 0.25, 0.5 } do
		for _, dz in { board.Size.Z / 2 + 0.4, 2.5 } do -- (just in front of its face)
			local from = frame * Vector3.new(at.X + fx * board.Size.X, at.Y - board.Size.Y, at.Z - dz)
			local hit = workspace:Raycast(from, frame.UpVector * 40, params)
			if hit then
				roof = math.min(roof, frame:PointToObjectSpace(hit.Position).Y)
			end
		end
	end
	local drop = top - (roof - ROOF_CLEAR)
	if roof == math.huge or drop <= 0 then
		return
	end
	local down = frame.UpVector * -drop
	board.CFrame += down
	for _, trim in plate.trims do
		trim.CFrame += down
	end
	local face = plate.gui.Parent
	if face and face:IsA("BasePart") and face ~= board then
		face.CFrame += down
	end
end

local function seatPlaque(frame: CFrame, plate: Decor.Plaque, under: boolean?)
	task.spawn(function()
		local board = plate.board
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain :: Instance }
		local at = frame:PointToObjectSpace(board.Position)
		local back = at.Z + board.Size.Z / 2 -- the board's back (local +z is into the wall)
		local rock = math.huge
		for _ = 1, 20 do
			task.wait(0.5)
			if board.Parent == nil then
				return
			end
			for _, fx in { -0.5, -0.25, 0, 0.25, 0.5 } do
				for _, fy in { -0.5, 0, 0.5 } do
					local x, y = at.X + fx * board.Size.X, at.Y + fy * board.Size.Y
					local hit = workspace:Raycast(
						frame * Vector3.new(x, y, back - 30),
						frame.LookVector * -40,
						params
					)
					if hit then
						rock = math.min(rock, frame:PointToObjectSpace(hit.Position).Z)
					end
				end
			end
			if rock < math.huge then
				break
			end
		end
		local shift = back - (rock - 0.15)
		if rock < math.huge and shift > 0 then
			local out = frame.LookVector * shift
			board.CFrame += out
			for _, trim in plate.trims do
				trim.CFrame += out
			end
			local face = plate.gui.Parent
			if face and face:IsA("BasePart") then
				face.CFrame += out
			end
		end
		if under and rock < math.huge then
			lowerUnderRoof(frame, plate, params)
		end
	end)
end

-- The main storey's vault over its deck `x` studs across, at the front wall where
-- the way out is (DenSpace.vaultAt, worked out here: the hub's previews build
-- DenDoor without DenSpace)
local function frontVault(x: number): number
	local s = Config.Dens.storeys[1]
	local room = Config.Dens.rooms[1]
	for _, candidate in Config.Dens.rooms do
		if candidate.storey == 1 and candidate.z0 >= Config.Dens.maxFront then
			room = candidate
			break
		end
	end
	local rise = s.ceiling - s.deck - s.wall
	local radius = (room.x * room.x + rise * rise) / (2 * rise)
	return s.wall + math.max(math.sqrt(math.max(radius * radius - x * x, 0)) - (radius - rise), 0)
end

-- A way out's nameplate is kept under the vault: a tall style's (the Whalebone's
-- reached 40 studs over the deck, the vault 38–39 at its corners) hangs lower, a
-- little out from the wall so what's behind it stays behind it. The carved roof
-- hangs up to `vaultSag` under the arch, so that's kept clear too (seatPlaque still
-- checks against the rock once the Terrain answers rays).
local VAULT_CLEAR = 0.8
local function underVault(frame: CFrame, plate: Decor.Plaque)
	local board = plate.board
	local at = frame:PointToObjectSpace(board.Position)
	local top = at.Y + board.Size.Y / 2 + Config.Dens.exit.y -- over the deck
	local limit = frontVault(math.abs(at.X) + board.Size.X / 2) - Config.Dens.vaultSag - VAULT_CLEAR
	if top <= limit then
		return
	end
	local move = frame:VectorToWorldSpace(Vector3.new(0, limit - top, -0.9))
	board.CFrame += move
	for _, trim in plate.trims do
		trim.CFrame += move
	end
	local face = plate.gui.Parent
	if face and face:IsA("BasePart") and face ~= board then
		face.CFrame += move
	end
end

-- Where door `index` stands (its portal, -Z out of its alcove) and its floor in that
-- frame: the doorway on the plaza, or the way out inside the den
local function placeOf(door: Door, index: number): (CFrame, number)
	if door.exit then
		return Layout.exitFrame(index), -Config.Dens.exit.y -- (the deck)
	end
	local frame = Layout.doorFrame(index)
	return frame, hub.denFloorY - frame.Position.Y -- (the den floor's height)
end

-- Builds (or rebuilds) a door's style
local function build(door: Door, index: number, styleId: string)
	if door.style then
		door.style:Destroy()
	end
	local builder = STYLES[styleId] or STYLES.Stone
	local style = Instance.new("Model")
	style.Name = "Style"
	local frame, floor = placeOf(door, index)
	local site: Site = {
		frame = frame,
		floor = floor,
		index = index,
		-- (no tunnel beside the way out; its growth is seeded apart from the doorway's)
		open = if door.exit then 0 else tunnelSide(index),
		rng = Random.new(World.seed + index * 31 + (if door.exit then 500 else 0)),
	}
	local made = builder(style, site)
	if door.exit then
		underVault(frame, made.plaque)
	end
	seatPlaque(frame, made.plaque, door.exit)
	local curtain, backing, bubbles, shimmer, glow = pane(style, frame, Layout.DOOR_RADIUS, made.pane)
	if door.exit then
		glow.Range = EXIT_GLOW_RANGE
		glow.Brightness = EXIT_GLOW
	end
	style:SetAttribute("Style", if STYLES[styleId] then styleId else "Stone")
	style.Parent = door.model
	-- The nameplate's top (local to the door's frame), so YOUR DEN sits over it on
	-- every style (PC 2026-10-19, DN1: on the Megalodon Jaws it sat across the name)
	local board = made.plaque.board
	local den = door.model.Parent
	if den and not door.exit then
		den:SetAttribute("PlaqueTop", frame:PointToObjectSpace(board.Position).Y + board.Size.Y / 2)
	end
	door.style = style
	door.styleId = styleId
	door.built = {
		plaque = made.plaque,
		glows = made.glows,
		curtain = curtain,
		pane = backing,
		bubbles = bubbles,
		shimmer = shimmer,
		glow = glow,
		look = made.look,
	}
end

-- The heart count on a nameplate, where its lower right rule was: a drawn heart
-- (Shared/HeartGlyph) and the number in gold
local function heartBadge(gui: SurfaceGui): (Frame, TextLabel)
	local badge = Instance.new("Frame")
	badge.Name = "Hearts"
	badge.BackgroundTransparency = 1
	badge.Position = UDim2.fromScale(0.7, 0.655)
	badge.Size = UDim2.fromScale(0.24, 0.3)
	badge.Parent = gui
	local heart = HeartGlyph.draw(badge, UDim2.fromScale(0.4, 0.94), HEART, Decor.TEXT_STROKE)
	heart.AnchorPoint = Vector2.new(0, 0.5)
	heart.Position = UDim2.fromScale(0.02, 0.5)
	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.BackgroundTransparency = 1
	count.AnchorPoint = Vector2.new(0, 0.5)
	count.Position = UDim2.fromScale(0.42, 0.5)
	count.Size = UDim2.fromScale(0.56, 0.96)
	count.Font = Enum.Font.GothamBlack
	count.TextScaled = true
	count.TextXAlignment = Enum.TextXAlignment.Left
	count.TextColor3 = Decor.TEXT_GOLD
	count.Text = ""
	count.Parent = badge
	local stroke = Instance.new("UIStroke")
	stroke.Color = Decor.TEXT_STROKE
	stroke.Thickness = 2.5
	stroke.Parent = count
	return badge, count
end

-- The Best Dens frame (last week's top 3): a bright gold border just outside the
-- nameplate's own trim, a gem at each corner and one over the middle. Its pieces
-- join the plaque's trims, so the seating that moves the plaque onto the rock
-- (seatPlaque, underVault) moves them with it.
local function goldFrame(parent: Instance, plate: Decor.Plaque): { BasePart }
	local board = plate.board
	local at = board.CFrame
	local hx, hy = board.Size.X / 2 + 0.62, board.Size.Y / 2 + 0.62
	local bar = 0.5
	local made: { BasePart } = {}
	local function add(props: { [string]: any })
		props.Name = "PlaqueFrame"
		props.CanCollide = false
		props.CastShadow = false
		table.insert(made, part(parent, props))
	end
	for _, y in { -1, 1 } do
		add({
			Size = Vector3.new(hx * 2 + bar, bar, 0.6),
			CFrame = at * CFrame.new(0, y * hy, -0.3),
			Color = FRAME_GOLD,
			Material = Enum.Material.Neon,
		})
	end
	for _, x in { -1, 1 } do
		add({
			Size = Vector3.new(bar, hy * 2 + bar, 0.6),
			CFrame = at * CFrame.new(x * hx, 0, -0.3),
			Color = FRAME_GOLD,
			Material = Enum.Material.Neon,
		})
	end
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			add({
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 1.25,
				CFrame = at * CFrame.new(x * hx, y * hy, -0.5),
				Color = FRAME_GEM,
				Material = Enum.Material.Neon,
			})
		end
	end
	-- (a cut gem over the middle: a block turned 45° on the board's face)
	add({
		Size = Vector3.new(1.3, 1.3, 0.6),
		CFrame = at * CFrame.new(0, hy + 0.45, -0.5) * CFrame.Angles(0, 0, math.rad(45)),
		Color = FRAME_GEM,
		Material = Enum.Material.Neon,
	})
	return made
end

-- A lived-in den's hearts and Best Dens frame on its nameplate (an empty den shows
-- neither). Nothing is built until the den has a heart or the frame.
local function showHearts(door: Door, built: Built, lived: boolean)
	local hearts = if lived then door.hearts or 0 else 0
	local framed = lived and door.framed == true
	if hearts <= 0 and built.badge == nil and not framed and built.frame == nil then
		return
	end
	local plate = built.plaque
	if hearts > 0 and built.badge == nil then
		built.badge, built.badgeCount = heartBadge(plate.gui)
	end
	local badge, count = built.badge, built.badgeCount
	if badge and count then
		badge.Visible = hearts > 0
		count.Text = Hearts.short(hearts)
	end
	-- The badge stands in for the lower right rule (the rules: Decor.plaque)
	local right: GuiObject? = nil
	for _, child in plate.gui:GetChildren() do
		if child.Name == "Rule" and child:IsA("GuiObject") and child.Position.X.Scale > 0.5 then
			right = child
		end
	end
	if right then
		right.Visible = hearts <= 0
	end
	local style = door.style
	if framed and built.frame == nil and style then
		local pieces = goldFrame(style, plate)
		for _, piece in pieces do
			table.insert(plate.trims, piece)
		end
		built.frame = pieces
	elseif not framed and built.frame then
		for _, piece in built.frame do
			local at = table.find(plate.trims, piece)
			if at then
				table.remove(plate.trims, at)
			end
			piece:Destroy()
		end
		built.frame = nil
	end
end

-- Shows who lives in a door's den (or that no one does) on what its style built
local function apply(door: Door)
	local built = door.built
	if built == nil then
		return
	end
	-- (the way out is only there while someone lives in the den: always lit)
	local lived = door.exit == true or door.owner ~= nil
	local plate = built.plaque
	if door.exit then
		plate.title.Text = "TO THE HUB"
	elseif door.owner then
		plate.title.Text = `{Decor.oneLine(door.owner)}'S`
	else
		plate.title.Text = "EMPTY DEN"
	end
	plate.title.TextColor3 = if lived then Decor.TEXT else TEXT_EMPTY
	local sub = plate.sub
	if sub then
		sub.Text = if door.exit
			then "THE PLAZA"
			elseif lived then Decor.oneLine(door.levelName or "Den")
			else "VACANT"
		sub.TextColor3 = if lived then Decor.TEXT_GOLD else TEXT_EMPTY
	end
	local look = built.look
	plate.board.Color = if lived then look.board else LACQUER_EMPTY
	for _, trim in plate.trims do
		if trim.Name == "PlaqueFrame" then
			continue -- (the Best Dens frame keeps its gold: showHearts)
		end
		trim.Color = if lived
			then (if trim.Name == "PlaqueBoss" then look.boss else look.trim)
			else TRIM_EMPTY
	end
	for _, glow in built.glows do
		glow.part.Material = if lived then glow.material else Enum.Material.SmoothPlastic
		glow.part.Color = if lived then glow.color else glow.color:Lerp(UNLIT, 0.75)
		glow.part.Transparency = if lived then glow.transparency else 0
		if glow.light then
			glow.light.Enabled = lived
		end
	end
	built.curtain.Color = if lived then look.curtain else CURTAIN_SHUT
	built.curtain.Transparency = if lived then 0.55 else 0.75
	built.pane.Color = if lived then look.pane else PANE_SHUT
	built.bubbles.Rate = if lived then 26 else 4
	built.shimmer.Enabled = lived
	built.glow.Enabled = lived
	if not door.exit then
		showHearts(door, built, lived)
	end
end

-- Den `index`'s front door on the plaza, into `parent` (its Den<i> model): the
-- threshold and steps, then the Stone Arch until its owner's style is set
function DenDoor.front(parent: Instance, index: number)
	local frame = Layout.doorFrame(index)
	local folder = Instance.new("Model")
	folder.Name = "Doorway"
	local floor = hub.denFloorY - frame.Position.Y -- the doorway's floor (the den floor's height)

	-- The threshold: a slab over the sill's ledge (Cave.denFloor: it reaches 7 in
	-- front of the wall), a rounded nose, two steps down to the paving
	local ledge = WALL_Z - 7.4
	part(folder, {
		Name = "Threshold",
		Size = Vector3.new(19.6, 1.2, WALL_Z + 0.4 - ledge),
		CFrame = frame * CFrame.new(0, floor - 0.2, (WALL_Z + 0.4 + ledge) / 2),
		Color = STEP,
		CanCollide = true,
	})
	part(folder, {
		Name = "ThresholdNose",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(19.6, 1.2, 1.2),
		CFrame = frame * CFrame.new(0, floor - 0.2, ledge),
		Color = STEP_EDGE,
		CanCollide = false,
	})
	local paving = hub.paving - frame.Position.Y
	local rise = (floor + 0.4 - paving) / 3
	for k = 1, 2 do
		local top = floor + 0.4 - rise * k
		local bottom = paving - 0.6
		local depth = if k == 1 then 2.4 else 1.8
		local front = ledge - 0.6 - (k - 1) * 1.8
		part(folder, {
			Name = "Step",
			Size = Vector3.new(20.4 + k * 1.2, top - bottom, depth),
			CFrame = frame
				* CFrame.new(0, (top + bottom) / 2, front - depth / 2 + (if k == 1 then 0.6 else 0)),
			Color = if k == 1 then STEP_EDGE else STEP,
			CanCollide = true,
		})
	end
	folder.Parent = parent
	local door: Door = { model = folder }
	doors[index] = door
	build(door, index, "Stone")
	apply(door)
end

-- Den `index`'s doorway style (Config/Dens `doors`; nil or unknown: the Stone
-- Arch). Rebuilt only when it changes.
-- The way out inside the den wears the same style.
function DenDoor.restyle(index: number, styleId: string?)
	local id = if styleId and STYLES[styleId] then styleId else "Stone"
	local both: { Door } = {}
	table.insert(both, doors[index])
	table.insert(both, exits[index])
	for _, door in both do
		if door.styleId ~= id then
			build(door, index, id)
			apply(door)
		end
	end
end

-- The style ids DenDoor can build (tools/preview/check_doors.luau tries each)
function DenDoor.styles(): { string }
	local list: { string } = {}
	for _, style in Config.Dens.doors do
		if STYLES[style.id] then
			table.insert(list, style.id)
		end
	end
	return list
end

-- The way out inside den `index` (Layout.exitFrame: at the back of an alcove in its
-- front wall, DenCarve), into `parent` (its Den<i> model): a threshold over the
-- alcove's sill, level with the deck, then the Stone Arch until the den's doorway
-- style is set (DenDoor.restyle dresses both)
function DenDoor.exit(parent: Instance, index: number)
	local frame = Layout.exitFrame(index)
	local folder = Instance.new("Model")
	folder.Name = "Exit"
	local floor = -Config.Dens.exit.y -- the deck, in the portal's frame
	-- The rock floor under the deck (Config/Dens storeys): the slab reaches down to it
	local rock = Config.Dens.storeys[1].floor - Config.Dens.storeys[1].deck + floor
	part(folder, {
		Name = "Threshold",
		Size = Vector3.new(19.6, floor + 0.2 - rock, 10.2),
		CFrame = frame * CFrame.new(0, (floor + 0.2 + rock) / 2, WALL_Z / 2 + 0.2),
		Color = STEP,
		CanCollide = true,
	})
	part(folder, {
		Name = "ThresholdNose",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(19.6, 1.0, 1.0),
		CFrame = frame * CFrame.new(0, floor - 0.1, WALL_Z - 0.3),
		Color = STEP_EDGE,
		CanCollide = false,
	})
	folder.Parent = parent
	local door: Door = { model = folder, exit = true }
	exits[index] = door
	build(door, index, "Stone")
	apply(door)
end

-- Who lives in den `index` (nil: nobody) and its level's name (Config/Dens
-- levels), on its nameplate; an empty den's door reads shut
function DenDoor.setSign(index: number, owner: string?, levelName: string?)
	local door = doors[index]
	if door == nil then
		return
	end
	door.owner = owner
	door.levelName = levelName
	if owner == nil then
		door.hearts = nil
		door.framed = nil
	end
	apply(door)
end

-- Den `index`'s hearts and whether its nameplate wears the Best Dens frame this
-- week (HeartService); an empty den's door shows neither
function DenDoor.setHearts(index: number, hearts: number, framed: boolean)
	local door = doors[index]
	if door == nil then
		return
	end
	door.hearts = hearts
	door.framed = framed
	apply(door)
end

return DenDoor
