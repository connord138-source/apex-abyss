--!strict
-- The drop-off's dressing (owner, 2026-10-19: "The cliff edge needs to be dialed up
-- more and should have coral etc on it. Right now it's just bulbous spheres off the
-- edge. Now that we can see more it needs to look better"): coral and life on the
-- reef wall Shelf.luau lays (its layout comes back as Features.cliff), seated by rays
-- against the Terrain: down onto the crest, its reef heads and the ledges, in at the
-- face, up under the lip.
--   * the LIP and the wall's top ~60 studs: lush reef (brain, staghorn and plate
--     corals, sea fans standing out from the rock, tube and barrel sponges,
--     anemones, sea whips, kelp, encrusting coralline), over the Shipwreck
--     Graveyard's bay (135-225 deg) barnacles, sponges and duller growth instead;
--   * the MID FACE: gardens of sea fans, whips, sponges, encrusting patches and plate
--     corals stacked as shelves, and a garden on every ledge;
--   * the LOWER FACE and the foot: sparse, cool deep-water growth in the colours of
--     the biome below (black coral bushes and fans, glass sponges, a few glowing
--     tips; tube worms and sulphur over the Vents), a lit glow in a few caves.
-- Every piece is a part-built stand-in (SmoothPlastic, Neon only where it glows) that
-- an imported WorldProps model replaces when there is one (Props.dress): BrainCoral,
-- StaghornCoral, TubeSponge, Anemone, KelpClump, and the wall's own PlateCoral,
-- BarrelSponge, SeaWhips and LaceFan (cliff_glb). Big hard pieces (brain corals, plate
-- shelves, barrel sponges) are solid like the reef's corals; everything else is decor
-- that neither collides nor takes rays. All of it lives under
-- Workspace.World.Biomes.Cliff, where Shared/Ground and the Whale Fall's spot finder
-- look for the solid ones; nothing stands in a chute or past the foot.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Props = require(ReplicatedStorage.Shared.Props)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Shelf = require(script.Parent.Shelf)

local World = Config.World

local Cliff = {}

-- A ray against the Terrain: where it hits, the surface's normal and its material
export type Cast = (origin: Vector3, direction: Vector3) -> (Vector3?, Vector3?, Enum.Material?)
export type Stats = {
	parts: number, -- stand-ins left in the world (hidden ones under a model included)
	solid: number,
	glow: number,
	lights: number,
	props: number, -- pieces an imported model was fitted over
	pieces: { [string]: number }, -- by kind
}

local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local TAU = math.pi * 2
local MAX_LIGHTS = 26

-- Palettes ---------------------------------------------------------------------
local REEF = {
	Color3.fromRGB(176, 110, 236), -- violet
	Color3.fromRGB(255, 150, 64), -- orange
	Color3.fromRGB(255, 214, 92), -- yellow
	Color3.fromRGB(64, 200, 186), -- teal
	Color3.fromRGB(232, 70, 64), -- red
	Color3.fromRGB(160, 214, 72), -- lime
	Color3.fromRGB(78, 140, 255), -- blue
	Color3.fromRGB(214, 72, 170), -- magenta
}
local COATING = { -- encrusting coralline and sponge crusts
	Color3.fromRGB(150, 90, 200),
	Color3.fromRGB(240, 120, 50),
	Color3.fromRGB(205, 60, 60),
	Color3.fromRGB(235, 200, 70),
	Color3.fromRGB(60, 170, 140),
	Color3.fromRGB(96, 120, 230),
}
local WRECK = { -- the graveyard's duller growth
	Color3.fromRGB(122, 132, 82),
	Color3.fromRGB(150, 92, 58),
	Color3.fromRGB(104, 124, 112),
	Color3.fromRGB(168, 148, 88),
	Color3.fromRGB(112, 102, 134),
	Color3.fromRGB(70, 110, 110),
}
local WRECK_TINT = Color3.fromRGB(176, 176, 160) -- a model's colours, dulled (a tint only darkens)
local BARNACLE = Color3.fromRGB(176, 182, 172)
local STALK = Color3.fromRGB(70, 78, 92)

type Deep = {
	corals: { Color3 }, -- black coral bushes and fans
	sponge: Color3, -- glass sponges
	glow: { Color3 },
	tint: Color3, -- a fan model darkened toward the depth
	lit: number, -- share of glow clusters with a light
}
local DEEP: { [string]: Deep } = {
	OpenBlue = {
		corals = { Color3.fromRGB(38, 52, 118), Color3.fromRGB(22, 86, 112) },
		sponge = Color3.fromRGB(118, 148, 190),
		glow = { Color3.fromRGB(90, 220, 255) },
		tint = Color3.fromRGB(90, 120, 170),
		lit = 0.15,
	},
	SunkenRuins = {
		corals = { Color3.fromRGB(22, 98, 104), Color3.fromRGB(40, 70, 110) },
		sponge = Color3.fromRGB(128, 186, 180),
		glow = { Color3.fromRGB(110, 255, 220) },
		tint = Color3.fromRGB(80, 150, 150),
		lit = 0.2,
	},
	HydrothermalVents = {
		corals = { Color3.fromRGB(70, 58, 64), Color3.fromRGB(96, 52, 40) },
		sponge = Color3.fromRGB(150, 140, 120),
		glow = { Color3.fromRGB(255, 150, 60) },
		tint = Color3.fromRGB(150, 96, 80),
		lit = 0.3,
	},
	AbyssalTrench = {
		corals = { Color3.fromRGB(52, 40, 122), Color3.fromRGB(24, 64, 96) },
		sponge = Color3.fromRGB(108, 156, 168),
		glow = { Color3.fromRGB(150, 120, 255), Color3.fromRGB(110, 230, 255) },
		tint = Color3.fromRGB(80, 80, 150),
		lit = 0.45,
	},
}
local TUBE_WORM = Color3.fromRGB(190, 188, 178)
local PLUME = Color3.fromRGB(196, 32, 40)
local SULPHUR = Color3.fromRGB(226, 196, 60)
local RUST = Color3.fromRGB(150, 70, 40)

-- One build's state ----------------------------------------------------------------
local rng = Random.new(World.seed + 83)
local stats: Stats = { parts = 0, solid = 0, glow = 0, lights = 0, props = 0, pieces = {} }

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function weighted(list: { { any } }): string
	local total = 0
	for _, entry in list do
		total += entry[2]
	end
	local roll = rng:NextNumber(0, total)
	for _, entry in list do
		roll -= entry[2]
		if roll <= 0 then
			return entry[1]
		end
	end
	return list[#list][1]
end

-- A piece of dressing: anchored SmoothPlastic, never fires Touched or takes rays;
-- `solid` ones collide
local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	solid: boolean?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = SMOOTH
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	p.CanQuery = false
	p.CanCollide = solid == true
	p.CastShadow = solid == true and math.max(size.X, size.Y, size.Z) >= 8
	p.Parent = parent
	stats.parts += 1
	if solid then
		stats.solid += 1
	end
	return p
end

-- An ellipsoid filling `size` (a sphere mesh on a block: decor only)
local function blob(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = part(parent, name, size, cframe, color)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- A rod from `a` to `b` (a cylinder part, its axis along X)
local function rod(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	radius: number,
	color: Color3
): Part
	local span = b - a
	local frame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	return part(
		parent,
		name,
		Vector3.new(span.Magnitude, radius * 2, radius * 2),
		frame,
		color,
		false,
		Enum.PartType.Cylinder
	)
end

local function glowBall(parent: Instance, position: Vector3, size: number, color: Color3): Part
	local p =
		part(parent, "GlowTip", Vector3.one * size, CFrame.new(position), color, false, Enum.PartType.Ball)
	p.Material = NEON
	stats.glow += 1
	return p
end

local function light(holder: BasePart, color: Color3, range: number, brightness: number)
	if stats.lights >= MAX_LIGHTS then
		return
	end
	local made = Instance.new("PointLight")
	made.Color = color
	made.Range = range
	made.Brightness = brightness
	made.Shadows = false
	made.Parent = holder
	stats.lights += 1
end

-- Fits WorldProps.<name> over `stand` (the box at `cframe`, `size`); when it's there,
-- the stand-in's other parts go
local function dress(
	stand: BasePart,
	extra: { BasePart },
	name: string,
	cframe: CFrame,
	size: Vector3,
	solid: boolean,
	tint: Color3?
)
	local model = Props.dress(stand, name, { cframe = cframe, size = size, solid = solid, tint = tint })
	if model then
		-- (the model is what shows and, when solid, what collides: the hidden stand-in
		-- would only be one more part)
		stats.props += 1
		stand:Destroy()
		for _, p in extra do
			p:Destroy()
		end
		stats.parts -= 1 + #extra
	end
end

-- Frames ---------------------------------------------------------------------------
-- A frame at `position` whose up is the surface's `normal` leaned `toUp` of the way
-- toward straight up (corals grow out and up), turned `yaw` about it
local function grow(position: Vector3, normal: Vector3, toUp: number, yaw: number): CFrame
	local up = (normal * (1 - toUp) + Vector3.yAxis * toUp).Unit
	local reference = if math.abs(up.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local right = reference:Cross(up).Unit
	return CFrame.fromMatrix(position, right, up, right:Cross(up)) * CFrame.Angles(0, yaw, 0)
end

-- A level frame at `position` looking out along `normal`'s horizontal part
local function level(position: Vector3, normal: Vector3): CFrame
	local flat = Vector3.new(normal.X, 0, normal.Z)
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(position.X, 0, position.Z)
	end
	return CFrame.lookAt(position, position + flat.Unit)
end

-- Pieces ---------------------------------------------------------------------------
-- Each takes the surface point, its normal, a size (studs) and a look; returns nothing
type Look = { colors: { Color3 }, tint: Color3?, deep: Deep? }

local function brain(parent: Instance, at: Vector3, normal: Vector3, size: number, look: Look)
	local frame = grow(at, normal, 0.6, rng:NextNumber(0, TAU))
	local hard = size >= 5
	local stand = part(
		parent,
		"BrainCoral",
		Vector3.one * size,
		frame * CFrame.new(0, size * 0.18, 0),
		pick(look.colors),
		hard,
		Enum.PartType.Ball
	)
	dress(
		stand,
		{},
		"BrainCoral",
		frame * CFrame.new(0, size * 0.42 - size * 0.12, 0),
		Vector3.new(size * 1.25, size * 0.84, size * 1.25),
		hard,
		look.tint
	)
end

local function staghorn(parent: Instance, at: Vector3, normal: Vector3, size: number, look: Look)
	local frame = grow(at, normal, 0.7, rng:NextNumber(0, TAU))
	local color = pick(look.colors)
	local trunk = rod(
		parent,
		"Staghorn",
		frame.Position,
		(frame * CFrame.new(0, size * 0.9, 0)).Position,
		size * 0.09,
		color
	)
	local branch = rod(
		parent,
		"Staghorn",
		(frame * CFrame.new(-size * 0.35, size * 0.2, 0)).Position,
		(frame * CFrame.new(size * 0.4, size * 0.75, 0)).Position,
		size * 0.07,
		color
	)
	dress(
		trunk,
		{ branch },
		"StaghornCoral",
		frame * CFrame.new(0, size * 0.5 - size * 0.08, 0),
		Vector3.new(size, size, size),
		false,
		look.tint
	)
end

-- Plate corals stacked as shelves, jutting level out of the rock
local function plates(parent: Instance, at: Vector3, normal: Vector3, size: number, look: Look)
	local frame = level(at, normal)
	local color = pick(look.colors)
	local count = rng:NextInteger(2, 4)
	local hard = size >= 9
	local first: Part? = nil
	local others: { BasePart } = {}
	for k = 1, count do
		local radius = size * 0.5 * (1 - (k - 1) * 0.16)
		local disc = part(
			parent,
			"Plate",
			Vector3.new(size * 0.07 + 0.4, radius * 2, radius * 2),
			frame
				* CFrame.new(rng:NextNumber(-0.15, 0.15) * size, (k - 1) * size * 0.22, -radius * 0.55)
				* CFrame.Angles(0, 0, math.rad(90)),
			if k % 2 == 0 then color:Lerp(Color3.new(1, 1, 1), 0.18) else color,
			hard,
			Enum.PartType.Cylinder
		)
		if first == nil then
			first = disc
		else
			table.insert(others, disc)
		end
	end
	if first then
		local height = size * (0.22 * (count - 1) + 0.25)
		dress(
			first,
			others,
			"PlateCoral",
			frame * CFrame.new(0, height / 2 - size * 0.1, -size * 0.3),
			Vector3.new(size, height + size * 0.2, size),
			hard,
			look.tint
		)
	end
end

-- A sea fan: a flat lacework standing out from the rock (its plane mostly along the
-- wall, so it reads broad from the open water)
local function fan(parent: Instance, at: Vector3, normal: Vector3, size: number, look: Look)
	local flat = Vector3.new(normal.X, 0, normal.Z)
	local wall = flat.Magnitude > 0.4
	local frame = grow(at, normal, if wall then 0.72 else 0.92, 0)
	-- the fan's thin axis (its frame's x) along the wall's normal, give or take
	if wall then
		local up = frame.UpVector
		local across = flat.Unit - up * flat.Unit:Dot(up)
		frame = CFrame.fromMatrix(at, across.Unit, up, across.Unit:Cross(up))
	end
	frame *= CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), 0)
	local color = if look.deep then pick(look.deep.corals) else pick(look.colors)
	local height = size * 0.9
	local stalk = rod(
		parent,
		"FanStalk",
		at,
		(frame * CFrame.new(0, size * 0.2, 0)).Position,
		math.max(size * 0.04, 0.3),
		STALK
	)
	local sheet = blob(
		parent,
		"SeaFan",
		Vector3.new(math.max(size * 0.05, 0.35), height, size),
		frame * CFrame.new(0, size * 0.15 + height / 2, 0),
		color
	)
	dress(
		sheet,
		{ stalk },
		"LaceFan",
		frame * CFrame.new(0, height / 2 + size * 0.05, 0),
		Vector3.new(size * 0.45, height, size),
		false,
		if look.deep then look.deep.tint else look.tint
	)
end

local function whips(parent: Instance, at: Vector3, normal: Vector3, size: number, look: Look)
	local frame = grow(at, normal, 0.65, rng:NextNumber(0, TAU))
	local color = pick(look.colors)
	local first: Part? = nil
	local others: { BasePart } = {}
	for k = 1, rng:NextInteger(3, 5) do
		local lean = CFrame.Angles(rng:NextNumber(-0.45, 0.45), k * 1.7, 0)
		local tip = (frame * lean * CFrame.new(0, size * rng:NextNumber(0.7, 1), 0)).Position
		local whip = rod(parent, "SeaWhip", at, tip, math.max(size * 0.035, 0.25), color)
		if first == nil then
			first = whip
		else
			table.insert(others, whip)
		end
	end
	if first then
		dress(
			first,
			others,
			"SeaWhips",
			frame * CFrame.new(0, size * 0.5 - size * 0.05, 0),
			Vector3.new(size * 0.8, size, size * 0.8),
			false,
			look.tint
		)
	end
end

local function barrel(parent: Instance, at: Vector3, normal: Vector3, size: number, look: Look)
	local frame = grow(at, normal, 0.85, rng:NextNumber(0, TAU))
	local hard = size >= 7
	local radius = size * 0.38
	local body = part(
		parent,
		"BarrelSponge",
		Vector3.new(size, radius * 2, radius * 2),
		frame * CFrame.new(0, size * 0.45, 0) * CFrame.Angles(0, 0, math.rad(90)),
		pick(look.colors),
		hard,
		Enum.PartType.Cylinder
	)
	local mouth = part(
		parent,
		"SpongeMouth",
		Vector3.new(0.3, radius * 1.5, radius * 1.5),
		frame * CFrame.new(0, size * 0.95 + 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(26, 30, 52),
		false,
		Enum.PartType.Cylinder
	)
	dress(
		body,
		{ mouth },
		"BarrelSponge",
		frame * CFrame.new(0, size * 0.5 - size * 0.06, 0),
		Vector3.new(size * 0.82, size, size * 0.82),
		hard,
		look.tint
	)
end

local function tubes(parent: Instance, at: Vector3, normal: Vector3, size: number, look: Look)
	local frame = grow(at, normal, 0.6, rng:NextNumber(0, TAU))
	local color = pick(look.colors)
	local first: Part? = nil
	local others: { BasePart } = {}
	for k = 1, 3 do
		local foot = frame * CFrame.new(math.cos(k * 2.1) * size * 0.2, 0, math.sin(k * 2.1) * size * 0.2)
		local tall = size * (0.55 + 0.15 * k)
		local tube = part(
			parent,
			"TubeSponge",
			Vector3.new(tall, size * 0.24, size * 0.24),
			foot * CFrame.new(0, tall / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			color,
			false,
			Enum.PartType.Cylinder
		)
		if first == nil then
			first = tube
		else
			table.insert(others, tube)
		end
	end
	if first then
		dress(
			first,
			others,
			"TubeSponge",
			frame * CFrame.new(0, size * 0.5 - size * 0.05, 0),
			Vector3.new(size * 0.8, size, size * 0.8),
			false,
			look.tint
		)
	end
end

local function anemone(parent: Instance, at: Vector3, normal: Vector3, size: number, look: Look)
	local frame = grow(at, normal, 0.5, rng:NextNumber(0, TAU))
	local stand = part(
		parent,
		"Anemone",
		Vector3.one * size * 0.7,
		frame * CFrame.new(0, size * 0.3, 0),
		pick(look.colors),
		false,
		Enum.PartType.Ball
	)
	dress(
		stand,
		{},
		"Anemone",
		frame * CFrame.new(0, size * 0.5 - size * 0.05, 0),
		Vector3.new(size, size, size),
		false,
		look.tint
	)
end

-- Encrusting coralline or a sponge crust: a flat patch lying on the rock
local function patch(parent: Instance, at: Vector3, normal: Vector3, size: number, look: Look)
	local frame = grow(at, normal, 0, rng:NextNumber(0, TAU))
	blob(
		parent,
		"Crust",
		Vector3.new(size, size * 0.14, size * rng:NextNumber(0.55, 0.9)),
		frame * CFrame.new(0, size * 0.02, 0),
		pick(look.colors)
	)
end

local function kelp(parent: Instance, at: Vector3, _normal: Vector3, size: number, look: Look)
	local height = size * 2.6
	local frame = CFrame.new(at) * CFrame.Angles(rng:NextNumber(-0.08, 0.08), rng:NextNumber(0, TAU), 0)
	local stalk = part(
		parent,
		"Kelp",
		Vector3.new(height, 0.9, 0.9),
		frame * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(78, 140, 60),
		false,
		Enum.PartType.Cylinder
	)
	dress(
		stalk,
		{},
		"KelpClump",
		frame * CFrame.new(0, height / 2, 0),
		Vector3.new(height * 0.5, height, height * 0.5),
		false,
		look.tint
	)
end

-- A crust of barnacles: a dull patch with a few cones on it
local function barnacles(parent: Instance, at: Vector3, normal: Vector3, size: number, look: Look)
	local frame = grow(at, normal, 0, rng:NextNumber(0, TAU))
	blob(parent, "Crust", Vector3.new(size, size * 0.12, size * 0.8), frame, pick(look.colors))
	for _ = 1, rng:NextInteger(2, 4) do
		local d = size * rng:NextNumber(0.14, 0.24)
		local spot = frame
			* CFrame.new(rng:NextNumber(-0.32, 0.32) * size, d * 0.3, rng:NextNumber(-0.26, 0.26) * size)
		part(
			parent,
			"Barnacle",
			Vector3.new(d * 0.8, d, d),
			spot * CFrame.Angles(0, 0, math.rad(90)),
			BARNACLE,
			false,
			Enum.PartType.Cylinder
		)
	end
end

-- A black coral bush: a dark trunk with forked branches, a few tips glowing in the
-- deep's colour
local function blackCoral(parent: Instance, at: Vector3, normal: Vector3, size: number, look: Look)
	local deep = look.deep :: Deep
	local frame = grow(at, normal, 0.6, rng:NextNumber(0, TAU))
	local color = pick(deep.corals)
	local top = (frame * CFrame.new(0, size * 0.5, 0)).Position
	rod(parent, "BlackCoral", at, top, math.max(size * 0.045, 0.35), color)
	local tips = 0
	for k = 1, 4 do
		local turn = CFrame.Angles(rng:NextNumber(0.35, 0.8) * (if k % 2 == 0 then 1 else -1), k * 1.57, 0)
		local tip = (frame * CFrame.new(0, size * (0.3 + 0.05 * k), 0) * turn * CFrame.new(0, size * 0.55, 0)).Position
		rod(
			parent,
			"BlackCoral",
			(frame * CFrame.new(0, size * (0.3 + 0.05 * k), 0)).Position,
			tip,
			math.max(size * 0.03, 0.25),
			color
		)
		if tips < 2 and rng:NextNumber() < 0.45 then
			tips += 1
			local bead = glowBall(parent, tip, math.max(size * 0.07, 0.5), pick(deep.glow))
			bead.Transparency = 0.15
		end
	end
end

-- A glass sponge: a pale cool vase, faintly lit from inside
local function glassSponge(parent: Instance, at: Vector3, normal: Vector3, size: number, look: Look)
	local deep = look.deep :: Deep
	local frame = grow(at, normal, 0.85, rng:NextNumber(0, TAU))
	local radius = size * 0.24
	local body = part(
		parent,
		"GlassSponge",
		Vector3.new(size, radius * 2, radius * 2),
		frame * CFrame.new(0, size * 0.45, 0) * CFrame.Angles(0, 0, math.rad(90)),
		deep.sponge,
		false,
		Enum.PartType.Cylinder
	)
	body.Transparency = 0.2
	local rim = part(
		parent,
		"GlassSpongeGlow",
		Vector3.new(0.3, radius * 1.6, radius * 1.6),
		frame * CFrame.new(0, size * 0.95, 0) * CFrame.Angles(0, 0, math.rad(90)),
		pick(deep.glow),
		false,
		Enum.PartType.Cylinder
	)
	rim.Material = NEON
	rim.Transparency = 0.35
	stats.glow += 1
end

-- A cluster of glowing tips (sometimes lit)
local function glowTips(parent: Instance, at: Vector3, normal: Vector3, size: number, look: Look)
	local deep = look.deep :: Deep
	local color = pick(deep.glow)
	local first: Part? = nil
	for _ = 1, rng:NextInteger(3, 5) do
		local scatter = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
		local spot = at + normal * rng:NextNumber(0.4, 1.4) + scatter * size * 0.25
		local bead = glowBall(parent, spot, rng:NextNumber(0.35, 0.9) * math.max(size * 0.25, 1), color)
		first = first or bead
	end
	if first and rng:NextNumber() < deep.lit then
		light(first, color, 26, 1.2)
	end
end

-- Tube worms over the Vents: pale tubes with crimson plumes
local function tubeWorms(parent: Instance, at: Vector3, normal: Vector3, size: number, _look: Look)
	local frame = grow(at, normal, 0.8, rng:NextNumber(0, TAU))
	for k = 1, rng:NextInteger(3, 4) do
		local foot = frame * CFrame.new(math.cos(k * 1.9) * size * 0.18, 0, math.sin(k * 1.9) * size * 0.18)
		local tall = size * rng:NextNumber(0.6, 1)
		local tip = (
			foot
			* CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2))
			* CFrame.new(0, tall, 0)
		).Position
		rod(parent, "TubeWorm", foot.Position, tip, math.max(size * 0.05, 0.3), TUBE_WORM)
		part(
			parent,
			"Plume",
			Vector3.one * math.max(size * 0.16, 0.8),
			CFrame.new(tip),
			PLUME,
			false,
			Enum.PartType.Ball
		)
	end
end

local BUILDERS: { [string]: (Instance, Vector3, Vector3, number, Look) -> () } = {
	brain = brain,
	staghorn = staghorn,
	plates = plates,
	fan = fan,
	whips = whips,
	barrel = barrel,
	tubes = tubes,
	anemone = anemone,
	patch = patch,
	kelp = kelp,
	barnacles = barnacles,
	blackCoral = blackCoral,
	glassSponge = glassSponge,
	glowTips = glowTips,
	tubeWorms = tubeWorms,
}

-- What grows where, by weight: on top of rock (a ledge, the crest), on the wall, or
-- under an overhang
local TOP = {
	reef = {
		{ "brain", 16 },
		{ "staghorn", 18 },
		{ "plates", 10 },
		{ "fan", 10 },
		{ "tubes", 11 },
		{ "anemone", 10 },
		{ "whips", 9 },
		{ "barrel", 9 },
		{ "kelp", 7 },
	},
	wreck = {
		{ "barnacles", 22 },
		{ "tubes", 18 },
		{ "barrel", 10 },
		{ "anemone", 10 },
		{ "kelp", 18 },
		{ "patch", 12 },
		{ "fan", 10 },
	},
	mid = {
		{ "fan", 18 },
		{ "whips", 16 },
		{ "barrel", 14 },
		{ "tubes", 14 },
		{ "brain", 10 },
		{ "staghorn", 10 },
		{ "anemone", 10 },
		{ "plates", 8 },
	},
	deep = { { "glassSponge", 40 }, { "blackCoral", 34 }, { "fan", 14 }, { "glowTips", 12 } },
	vents = {
		{ "tubeWorms", 44 },
		{ "glassSponge", 16 },
		{ "patch", 20 },
		{ "glowTips", 12 },
		{ "blackCoral", 8 },
	},
}
local WALL = {
	reef = {
		{ "plates", 24 },
		{ "fan", 22 },
		{ "patch", 20 },
		{ "whips", 12 },
		{ "tubes", 10 },
		{ "anemone", 8 },
		{ "brain", 6 },
	},
	wreck = { { "barnacles", 32 }, { "patch", 26 }, { "tubes", 16 }, { "fan", 14 }, { "anemone", 8 } },
	mid = {
		{ "fan", 26 },
		{ "patch", 24 },
		{ "plates", 18 },
		{ "whips", 16 },
		{ "tubes", 10 },
		{ "anemone", 6 },
	},
	deep = { { "fan", 34 }, { "blackCoral", 36 }, { "glowTips", 16 }, { "patch", 14 } },
	vents = { { "patch", 40 }, { "tubeWorms", 20 }, { "glowTips", 20 }, { "blackCoral", 20 } },
}
local UNDER = { { "patch", 50 }, { "tubes", 25 }, { "anemone", 25 } }

-- A size (studs) from `from`..`to`, or now and then (`hero` of the time) a big one
-- that reads from across the water
local function heroSize(from: number, to: number, hero: number): number
	if rng:NextNumber() < hero then
		return rng:NextNumber(to, to * 1.6)
	end
	return rng:NextNumber(from, to)
end

-- Places one piece of `kind` (counted); `size` studs
local function place(parent: Instance, kind: string, at: Vector3, normal: Vector3, size: number, look: Look)
	-- (a deep piece needs a deep look)
	if (kind == "blackCoral" or kind == "glassSponge" or kind == "glowTips") and look.deep == nil then
		kind = "fan"
	end
	if kind == "patch" then
		size *= 1.5 -- (crusts are cheap colour: big ones)
	end
	BUILDERS[kind](parent, at, normal, size, look)
	stats.pieces[kind] = (stats.pieces[kind] or 0) + 1
end

-- Builds the drop-off's dressing under `parent` (Workspace.World.Biomes.Cliff); `cast`
-- answers rays against the Terrain
function Cliff.build(parent: Instance, layout: Shelf.Cliff, cast: Cast): Stats
	rng = Random.new(World.seed + 83)
	stats = { parts = 0, solid = 0, glow = 0, lights = 0, props = 0, pieces = {} }
	local face = layout.face
	local floor = World.deep.floorY
	local biomes = Config.Biomes.byId
	local wreckBiome = biomes.ShipwreckGraveyard

	local function outward(angle: number): Vector3
		local a = math.rad(angle)
		return Vector3.new(math.cos(a), 0, math.sin(a))
	end
	local function at(angle: number, r: number, y: number): Vector3
		return World.hub.center + outward(angle) * r + Vector3.new(0, y, 0)
	end
	local function gap(a: number, b: number): number
		return math.abs(((a - b + 180) % 360) - 180)
	end
	local function nearChute(angle: number, studs: number): boolean
		for _, chute in layout.chutes do
			if math.rad(gap(angle, chute)) * face < layout.chuteHalf + studs then
				return true
			end
		end
		return false
	end
	local function wreck(angle: number): boolean
		return Seafloor.inSector(angle, wreckBiome.angleFrom, wreckBiome.angleTo)
	end
	-- The deep biome under the wall at `angle`
	local function deepAt(angle: number): (Deep, string)
		for _, biome in Config.Biomes.list do
			if biome.deep and Seafloor.inSector(angle, biome.angleFrom, biome.angleTo) and DEEP[biome.id] then
				return DEEP[biome.id], biome.id
			end
		end
		return DEEP.OpenBlue, "OpenBlue"
	end
	local function shallowLook(angle: number): (Look, string)
		if wreck(angle) then
			return { colors = WRECK, tint = WRECK_TINT }, "wreck"
		end
		return { colors = REEF }, "reef"
	end
	local function deepLook(angle: number): (Look, string)
		local deep, id = deepAt(angle)
		local colors = if id == "HydrothermalVents"
			then { SULPHUR, RUST, Color3.fromRGB(90, 70, 60) }
			else deep.corals
		return { colors = colors, deep = deep, tint = deep.tint },
			if id == "HydrothermalVents" then "vents" else "deep"
	end
	-- Every free stretch of rim (clear of the chutes) walked in steps of `step` studs
	local function walk(step: { number }, margin: number, visit: (number) -> ())
		local angle = rng:NextNumber(0, 2)
		while angle < 360 do
			if not nearChute(angle, margin) then
				visit(angle)
			end
			angle += math.deg(rng:NextNumber(step[1], step[2]) / face)
		end
	end
	local function down(
		angle: number,
		r: number,
		from: number,
		depth: number
	): (Vector3?, Vector3?, Enum.Material?)
		return cast(at(angle, r, from), Vector3.new(0, -depth, 0))
	end
	local function inward(angle: number, y: number): (Vector3?, Vector3?, Enum.Material?)
		return cast(at(angle, face + layout.reach + 30, y), outward(angle) * -(layout.reach + 75))
	end

	local lip = Instance.new("Folder")
	lip.Name = "Lip"
	lip.Parent = parent
	local wall = Instance.new("Folder")
	wall.Name = "Face"
	wall.Parent = parent
	local gardens = Instance.new("Folder")
	gardens.Name = "Ledges"
	gardens.Parent = parent
	local deepFolder = Instance.new("Folder")
	deepFolder.Name = "Deep"
	deepFolder.Parent = parent

	-- The lip: down onto the crest and its reef heads
	walk({ 9, 15 }, 10, function(angle)
		local hit, normal, material = down(angle, face + rng:NextNumber(-16, 13), 40, 100)
		if hit == nil or normal == nil or normal.Y < 0.45 or hit.Y < -34 then
			return
		end
		if material == Enum.Material.Sand and rng:NextNumber() < 0.5 then
			return -- (the shelf's sand behind the crest: some)
		end
		local look, zone = shallowLook(angle)
		place(lip, weighted(TOP[zone]), hit, normal, heroSize(6, 13, 0.25), look)
	end)
	for _, head in layout.heads do
		local angle = math.deg(math.atan2(head.position.Z, head.position.X)) % 360
		local look, zone = shallowLook(angle)
		for _ = 1, rng:NextInteger(3, 4) do
			local spot = head.position
				+ Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * head.radius * 0.8
			local hit, normal = cast(spot + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0))
			if hit and normal and normal.Y > 0.3 then
				place(lip, weighted(TOP[zone]), hit, normal, heroSize(8, 14, 0.35), look)
			end
		end
	end

	-- The crest's front and the wall's top ~60 studs: in at the rock; what faces up
	-- gets top growth, what faces down (under the lip) hangs
	walk({ 8, 13 }, 12, function(angle)
		local hit, normal = inward(angle, rng:NextNumber(-62, -8))
		if hit == nil or normal == nil then
			return
		end
		local look, zone = shallowLook(angle)
		local size = heroSize(6, 14, 0.2)
		if normal.Y > 0.6 then
			place(lip, weighted(TOP[zone]), hit, normal, size, look)
		elseif normal.Y < -0.5 then
			place(lip, weighted(UNDER), hit, normal, size * 0.8, look)
		else
			place(lip, weighted(WALL[zone]), hit, normal, size, look)
		end
	end)

	-- The mid face (-70 to -250): gardens of 3-7 pieces every 60-140 studs
	walk({ 45, 100 }, 16, function(angle)
		local y0 = rng:NextNumber(-245, -75)
		local look, zone = shallowLook(angle)
		if zone == "reef" then
			look = { colors = REEF }
		end
		local wallKind = if zone == "wreck" then WALL.wreck else WALL.mid
		local topKind = if zone == "wreck" then TOP.wreck else TOP.mid
		for _ = 1, rng:NextInteger(4, 8) do
			local a = angle + math.deg(rng:NextNumber(-28, 28) / face)
			if nearChute(a, 10) then
				continue
			end
			local hit, normal = inward(a, y0 + rng:NextNumber(-26, 26))
			if hit == nil or normal == nil then
				continue
			end
			local size = heroSize(8, 15, 0.3)
			if normal.Y > 0.6 then
				place(wall, weighted(topKind), hit, normal, size, look)
			elseif normal.Y > -0.5 then
				place(wall, weighted(wallKind), hit, normal, size, look)
			end
		end
	end)

	-- A garden on every ledge
	for _, ledge in layout.ledges do
		local out = outward(ledge.angle)
		local along = Vector3.yAxis:Cross(out)
		local deep = ledge.top.Y < -250
		local look, zone
		if deep then
			look, zone = deepLook(ledge.angle)
		else
			look, zone = shallowLook(ledge.angle)
			if zone == "reef" then
				zone = "mid"
			end
		end
		local count = math.clamp(math.floor(ledge.length / 10), 5, 10)
		for k = 1, count do
			local t = (k - 0.5) / count - 0.5 + rng:NextNumber(-0.04, 0.04)
			local spot = ledge.top
				+ along * t * ledge.length * 0.9
				+ out * rng:NextNumber(-4, ledge.depth * 0.5)
			local hit, normal = cast(spot + Vector3.new(0, 30, 0), Vector3.new(0, -50, 0))
			if hit and normal and normal.Y > 0.4 then
				place(gardens, weighted(TOP[zone]), hit, normal, heroSize(8, 14, 0.35), look)
			end
		end
	end

	-- The lower face (-250 to the foot): sparse deep growth in the biome's colours
	walk({ 60, 130 }, 16, function(angle)
		local look, zone = deepLook(angle)
		local y0 = rng:NextNumber(floor + 30, -255)
		for _ = 1, rng:NextInteger(2, 5) do
			local a = angle + math.deg(rng:NextNumber(-18, 18) / face)
			if nearChute(a, 10) then
				continue
			end
			local hit, normal = inward(a, y0 + rng:NextNumber(-20, 20))
			if hit == nil or normal == nil or normal.Y < -0.5 then
				continue
			end
			local list = if normal.Y > 0.6 then TOP[zone] else WALL[zone]
			place(deepFolder, weighted(list), hit, normal, heroSize(8, 15, 0.3), look)
		end
	end)

	-- The foot: a few pieces on the talus and the floor by the wall (never past the
	-- foot into the Trench's canyon)
	walk({ 55, 120 }, 30, function(angle)
		local r = face + rng:NextNumber(8, 70)
		local spot = at(angle, r, 0)
		if Seafloor.inTrench(spot.X, spot.Z, 10) then
			return
		end
		local hit, normal = down(angle, r, floor + 70, 90)
		if hit == nil or normal == nil or normal.Y < 0.5 then
			return
		end
		local look, zone = deepLook(angle)
		place(deepFolder, weighted(TOP[zone]), hit, normal, heroSize(9, 16, 0.3), look)
	end)

	-- The caves: a glow deep in some of them
	for _, cave in layout.caves do
		if rng:NextNumber() < 0.6 then
			local angle = math.deg(math.atan2(cave.position.Z, cave.position.X)) % 360
			local look = deepLook(angle)
			local hit, normal =
				cast(cave.position + outward(angle) * 10, outward(angle) * -(cave.radius * 2 + 20))
			if hit and normal then
				place(deepFolder, "glowTips", hit, normal, 5, look)
			end
		end
	end

	return stats
end

return Cliff
