--!strict
-- The drop-off's dressing (owner, 2026-10-19: "The cliff edge needs to be dialed up
-- more and should have coral etc on it. Right now it's just bulbous spheres off the
-- edge. Now that we can see more it needs to look better"): coral and life on the
-- reef wall Shelf.luau lays (its layout comes back as Features.cliff), seated by rays
-- against the Terrain: down onto the crest, its reef heads, the bands' tops and the
-- ledges, in at the face, up under the lip.
--   * the LIP and the wall's top ~60 studs: lush reef in patches (brain, staghorn and
--     plate corals, sea fans standing out from the rock, tube and barrel sponges,
--     anemones, sea whips, a little kelp, encrusting coralline), over the Shipwreck
--     Graveyard's bay (135-225 deg) barnacles, sponges and duller growth instead;
--   * the MID FACE: big sea fans, whips and plate shelves standing out of the bands'
--     fronts, gardens along the bands' tops, a garden on every ledge, and broad
--     crusts of coralline colour over the rock;
--   * the LOWER FACE and the foot: sparse, cool deep-water growth in the colours of
--     the biome below (black coral bushes and fans, glass sponges, a few glowing
--     tips; tube worms and sulphur over the Vents), a lit glow in a few caves.
-- Every piece is a part-built stand-in (SmoothPlastic, Neon only where it glows) that
-- an imported WorldProps model replaces when there is one (Props.dress): BrainCoral,
-- StaghornCoral, FanCoral, TubeSponge, Anemone, KelpClump, and the wall's own
-- PlateCoral, BarrelSponge, SeaWhips and LaceFan (cliff_glb). Big hard pieces (brain
-- corals, plate shelves, barrel sponges) are solid like the reef's corals;
-- everything else is decor that neither collides nor takes rays or touches. All of
-- it lives under Workspace.World.Biomes.Cliff, which Shared/Ground and the Whale
-- Fall's spot finder count; nothing stands in a chute or past the foot.
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
	parts: number, -- parts left in the world (stand-ins no model replaced, crusts, glows)
	models: number, -- imported models fitted over a stand-in (its parts then removed)
	solid: number, -- parts and models fish bump into
	glow: number,
	lights: number,
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
	Color3.fromRGB(196, 70, 150),
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
local KELP = Color3.fromRGB(78, 140, 60)

type Deep = {
	corals: { Color3 }, -- black coral bushes and fans
	sponge: Color3, -- glass sponges
	glow: { Color3 },
	crust: { Color3 }, -- cool crusts low on the wall
	tint: Color3, -- a fan model darkened toward the depth
	lit: number, -- share of glow clusters with a light
}
local DEEP: { [string]: Deep } = {
	OpenBlue = {
		corals = { Color3.fromRGB(38, 52, 118), Color3.fromRGB(22, 86, 112) },
		sponge = Color3.fromRGB(118, 148, 190),
		glow = { Color3.fromRGB(90, 220, 255) },
		crust = { Color3.fromRGB(52, 78, 150), Color3.fromRGB(40, 110, 130) },
		tint = Color3.fromRGB(90, 120, 170),
		lit = 0.15,
	},
	SunkenRuins = {
		corals = { Color3.fromRGB(22, 98, 104), Color3.fromRGB(40, 70, 110) },
		sponge = Color3.fromRGB(128, 186, 180),
		glow = { Color3.fromRGB(110, 255, 220) },
		crust = { Color3.fromRGB(36, 120, 118), Color3.fromRGB(58, 90, 140) },
		tint = Color3.fromRGB(80, 150, 150),
		lit = 0.2,
	},
	HydrothermalVents = {
		corals = { Color3.fromRGB(70, 58, 64), Color3.fromRGB(96, 52, 40) },
		sponge = Color3.fromRGB(150, 140, 120),
		glow = { Color3.fromRGB(255, 150, 60) },
		crust = { Color3.fromRGB(120, 70, 48), Color3.fromRGB(150, 128, 52) },
		tint = Color3.fromRGB(150, 96, 80),
		lit = 0.3,
	},
	AbyssalTrench = {
		corals = { Color3.fromRGB(52, 40, 122), Color3.fromRGB(24, 64, 96) },
		sponge = Color3.fromRGB(108, 156, 168),
		glow = { Color3.fromRGB(150, 120, 255), Color3.fromRGB(110, 230, 255) },
		crust = { Color3.fromRGB(64, 52, 140), Color3.fromRGB(30, 92, 120) },
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
local solidParts = 0
local stats: Stats = { parts = 0, models = 0, solid = 0, glow = 0, lights = 0, pieces = {} }

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

type Weight = { kind: string, weight: number }
local function w(kind: string, weight: number): Weight
	return { kind = kind, weight = weight }
end

local function weighted(list: { Weight }): string
	local total = 0
	for _, entry in list do
		total += entry.weight
	end
	local roll = rng:NextNumber(0, total)
	for _, entry in list do
		roll -= entry.weight
		if roll <= 0 then
			return entry.kind
		end
	end
	return list[#list].kind
end

-- A piece of dressing: anchored SmoothPlastic, never fires Touched or takes rays;
-- `solid` ones collide (and so answer rays: CanQuery only counts without collision)
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
		solidParts += 1
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
-- the stand-in and its other parts go (the model is what shows and, when solid,
-- what collides: the hidden stand-in would only be one more part)
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
	if model == nil then
		return
	end
	stats.models += 1
	if solid then
		stats.solid += 1
	end
	table.insert(extra, stand)
	for _, p in extra do
		if p.CanCollide then
			solidParts -= 1
		end
		p:Destroy()
	end
	stats.parts -= #extra
end

-- Frames ---------------------------------------------------------------------------
-- A frame at `position` whose up is the surface's `normal` leaned `toUp` of the way
-- toward straight up (corals grow out and up; under an overhang, out and down),
-- turned `yaw` about it
local function grow(position: Vector3, normal: Vector3, toUp: number, yaw: number): CFrame
	local toward = if normal.Y < -0.3 then -Vector3.yAxis else Vector3.yAxis
	local up = (normal * (1 - toUp) + toward * toUp).Unit
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
-- Each takes the surface point, its normal, a size (studs) and a look
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
	local count = rng:NextInteger(2, 3)
	local hard = size >= 9
	local first: Part? = nil
	local others: { BasePart } = {}
	for k = 1, count do
		local radius = size * 0.5 * (1 - (k - 1) * 0.18)
		local disc = part(
			parent,
			"Plate",
			Vector3.new(size * 0.07 + 0.4, radius * 2, radius * 2),
			frame
				* CFrame.new(rng:NextNumber(-0.15, 0.15) * size, (k - 1) * size * 0.24, -radius * 0.55)
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
		local height = size * (0.24 * (count - 1) + 0.25)
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
-- wall, so it reads broad from the open water); the reef's purple FanCoral or the
-- wall's own LaceFan
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
		if look.deep == nil and rng:NextNumber() < 0.45 then "FanCoral" else "LaceFan",
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
	for k = 1, rng:NextInteger(3, 4) do
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

-- The frame of a crust lying on the rock at `at`, and how wide it is across for its
-- length: on the wall it runs along the band it's on (a band is a roll lying round
-- the rim, curved only up and down), long and low, so its edges stay on the rock
local function lying(at: Vector3, normal: Vector3): (CFrame, number)
	if math.abs(normal.Y) < 0.7 then
		local along = Vector3.yAxis:Cross(normal).Unit
		local up = normal - along * normal:Dot(along)
		local frame = CFrame.fromMatrix(at, along, up.Unit, along:Cross(up.Unit))
		return frame * CFrame.Angles(0, rng:NextNumber(-0.12, 0.12), 0), rng:NextNumber(0.3, 0.45)
	end
	return grow(at, normal, 0, rng:NextNumber(0, TAU)), rng:NextNumber(0.55, 0.9)
end

-- Encrusting coralline or a sponge crust: a flat patch lying on the rock, sometimes
-- a second, smaller one of another colour lapping over it
local function patch(parent: Instance, at: Vector3, normal: Vector3, size: number, look: Look)
	local frame, across = lying(at, normal)
	local color = pick(look.colors)
	-- (a thin disc pressed a little into the rock: where the rock curves away its edge
	-- sinks in, so the patch reads as a stain of growth with a ragged edge, not a pill)
	blob(
		parent,
		"Crust",
		Vector3.new(size, size * 0.07, size * across),
		frame * CFrame.new(0, -size * 0.012, 0),
		color
	)
	if rng:NextNumber() < 0.3 then
		local other = pick(look.colors)
		if other ~= color then
			blob(
				parent,
				"Crust",
				Vector3.new(size * 0.55, size * 0.07, size * across * 0.7),
				frame
					* CFrame.new(
						size * rng:NextNumber(-0.3, 0.3),
						size * 0.008,
						size * across * rng:NextNumber(-0.2, 0.2)
					),
				other
			)
		end
	end
end

local function kelp(parent: Instance, at: Vector3, _normal: Vector3, size: number, look: Look)
	local height = size * 2.4
	local frame = CFrame.new(at) * CFrame.Angles(rng:NextNumber(-0.08, 0.08), rng:NextNumber(0, TAU), 0)
	local stalk = part(
		parent,
		"Kelp",
		Vector3.new(height, 0.9, 0.9),
		frame * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		KELP,
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
	local frame, across = lying(at, normal)
	blob(
		parent,
		"Crust",
		Vector3.new(size, size * 0.08, size * across),
		frame * CFrame.new(0, -size * 0.012, 0),
		pick(look.colors)
	)
	for _ = 1, rng:NextInteger(1, 2) do
		local d = size * rng:NextNumber(0.18, 0.28)
		local spot = frame
			* CFrame.new(
				rng:NextNumber(-0.32, 0.32) * size,
				d * 0.3,
				rng:NextNumber(-0.3, 0.3) * size * across
			)
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
	for k = 1, 2 do
		local turn = CFrame.Angles(rng:NextNumber(0.35, 0.8) * (if k % 2 == 0 then 1 else -1), k * 3.1, 0)
		local fork = frame * CFrame.new(0, size * (0.3 + 0.07 * k), 0)
		local tip = (fork * turn * CFrame.new(0, size * 0.55, 0)).Position
		rod(parent, "BlackCoral", fork.Position, tip, math.max(size * 0.03, 0.25), color)
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
	for _ = 1, rng:NextInteger(3, 4) do
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
	for k = 1, rng:NextInteger(2, 3) do
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

-- What grows where, by weight: on top of rock (the crest, a band's top, a ledge), on
-- the wall, or under an overhang
local TOP: { [string]: { Weight } } = {
	reef = {
		w("brain", 16),
		w("staghorn", 17),
		w("plates", 8),
		w("fan", 11),
		w("tubes", 11),
		w("anemone", 10),
		w("whips", 10),
		w("barrel", 9),
		w("kelp", 5),
	},
	wreck = {
		w("barnacles", 20),
		w("tubes", 18),
		w("barrel", 12),
		w("anemone", 10),
		w("kelp", 18),
		w("patch", 10),
		w("fan", 10),
		w("whips", 6),
	},
	mid = {
		w("fan", 16),
		w("whips", 16),
		w("barrel", 15),
		w("tubes", 14),
		w("brain", 10),
		w("staghorn", 10),
		w("anemone", 9),
		w("plates", 10),
	},
	deep = { w("glassSponge", 40), w("blackCoral", 30), w("fan", 18), w("glowTips", 12) },
	vents = {
		w("tubeWorms", 44),
		w("glassSponge", 16),
		w("patch", 20),
		w("glowTips", 12),
		w("blackCoral", 8),
	},
}
local WALL: { [string]: { Weight } } = {
	reef = {
		w("plates", 24),
		w("fan", 24),
		w("patch", 16),
		w("whips", 14),
		w("tubes", 9),
		w("anemone", 7),
		w("brain", 6),
	},
	wreck = {
		w("barnacles", 32),
		w("patch", 24),
		w("tubes", 16),
		w("fan", 14),
		w("anemone", 8),
		w("whips", 6),
	},
	mid = {
		w("fan", 30),
		w("plates", 24),
		w("whips", 20),
		w("patch", 12),
		w("tubes", 8),
		w("anemone", 6),
	},
	deep = { w("fan", 34), w("blackCoral", 36), w("glowTips", 16), w("patch", 14) },
	vents = { w("patch", 40), w("tubeWorms", 20), w("glowTips", 20), w("blackCoral", 20) },
}
local UNDER: { Weight } = { w("patch", 40), w("tubes", 22), w("anemone", 22), w("whips", 16) }

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
	if kind == "patch" or kind == "barnacles" then
		-- (a crust lies flat on a band's front or top; on a roll's shoulder or its
		-- underside a flat patch would stand off the curve like a pill)
		if normal.Y < -0.35 or (normal.Y > 0.35 and normal.Y < 0.8) then
			return
		end
		if kind == "patch" then
			size *= 1.5 -- (crusts are cheap colour: big ones)
		end
	end
	BUILDERS[kind](parent, at, normal, size, look)
	stats.pieces[kind] = (stats.pieces[kind] or 0) + 1
end

-- Builds the drop-off's dressing under `parent` (Workspace.World.Biomes.Cliff); `cast`
-- answers rays against the Terrain
function Cliff.build(parent: Instance, layout: Shelf.Cliff, cast: Cast): Stats
	rng = Random.new(World.seed + 83)
	solidParts = 0
	stats = { parts = 0, models = 0, solid = 0, glow = 0, lights = 0, pieces = {} }
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
	local function angleOf(position: Vector3): number
		return math.deg(math.atan2(position.Z - World.hub.center.Z, position.X - World.hub.center.X)) % 360
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
	-- The crust colours at height `y` round `angle`: the reef's coralline high up,
	-- the wreck's dull growth over the graveyard, the deep's cool colours low down
	local function crustLook(angle: number, y: number): Look
		if y < -250 then
			local deep = deepAt(angle)
			return { colors = deep.crust, deep = deep }
		elseif wreck(angle) then
			return { colors = WRECK }
		end
		return { colors = COATING }
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

	-- The lip: reef patches of 3-5 pieces every 22-36 studs down onto the crest (some
	-- reaching back onto the shelf's sand), and 2-3 on each reef head
	walk({ 22, 36 }, 10, function(angle)
		local look, zone = shallowLook(angle)
		local r0 = face + rng:NextNumber(-26, 10)
		for _ = 1, rng:NextInteger(3, 5) do
			local a = angle + math.deg(rng:NextNumber(-10, 10) / face)
			if nearChute(a, 6) then
				continue
			end
			local hit, normal, material = down(a, r0 + rng:NextNumber(-7, 7), 40, 100)
			if hit == nil or normal == nil or normal.Y < 0.45 or hit.Y < -34 then
				continue
			end
			if material == Enum.Material.Sand and rng:NextNumber() < 0.4 then
				continue -- (the shelf's sand behind the crest: some)
			end
			place(lip, weighted(TOP[zone]), hit, normal, heroSize(6, 13, 0.22), look)
		end
	end)
	for _, head in layout.heads do
		local look, zone = shallowLook(angleOf(head.position))
		for _ = 1, rng:NextInteger(2, 3) do
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
		local hit, normal = inward(angle, rng:NextNumber(-68, -8))
		if hit == nil or normal == nil then
			return
		end
		local look, zone = shallowLook(angle)
		local size = heroSize(7, 15, 0.22)
		if normal.Y > 0.6 then
			place(lip, weighted(TOP[zone]), hit, normal, size, look)
		elseif normal.Y < -0.5 then
			place(lip, weighted(UNDER), hit, normal, size * 0.8, look)
		else
			place(lip, weighted(WALL[zone]), hit, normal, size, look)
		end
	end)

	-- Under the lip where it overhangs the undercut: growth hanging from its roof
	for _, span in layout.undercuts do
		local angle = span[1] + math.deg(rng:NextNumber(4, 12) / face)
		while angle < span[2] do
			local hit, normal = cast(at(angle, face + rng:NextNumber(0, 14), -54), Vector3.new(0, 40, 0))
			if hit and normal and normal.Y < -0.4 then
				place(lip, weighted(UNDER), hit, normal, rng:NextNumber(6, 12), (shallowLook(angle)))
			end
			angle += math.deg(rng:NextNumber(12, 24) / face)
		end
	end

	-- The mid face (-70 to -250): big pieces standing out of the bands' fronts (sea
	-- fans, plate shelves, whips), every 16-32 studs
	walk({ 16, 32 }, 16, function(angle)
		local look, zone = shallowLook(angle)
		local hit, normal = inward(angle, rng:NextNumber(-250, -72))
		if hit == nil or normal == nil or normal.Y < -0.5 then
			return
		end
		local list = if normal.Y > 0.6
			then (if zone == "wreck" then TOP.wreck else TOP.mid)
			else (if zone == "wreck" then WALL.wreck else WALL.mid)
		place(wall, weighted(list), hit, normal, heroSize(12, 22, 0.3), look)
	end)
	-- ... and gardens of 2-4 along a band's top, every 30-60 studs
	local midBands = {}
	for _, band in layout.bands do
		if band.y < -66 and band.y > -255 then
			table.insert(midBands, band)
		end
	end
	if #midBands > 0 then
		walk({ 30, 60 }, 16, function(angle)
			local band = pick(midBands)
			local look, zone = shallowLook(angle)
			local list = if zone == "wreck" then TOP.wreck else TOP.mid
			for _ = 1, rng:NextInteger(2, 4) do
				local a = angle + math.deg(rng:NextNumber(-14, 14) / face)
				if nearChute(a, 10) then
					continue
				end
				local hit, normal =
					down(a, face + rng:NextNumber(4, band.out), band.y + band.thick / 2 + 24, 40)
				if hit and normal and normal.Y > 0.6 then
					place(wall, weighted(list), hit, normal, heroSize(8, 15, 0.3), look)
				end
			end
		end)
	end

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
		local count = math.clamp(math.floor(ledge.length / 13), 4, 7)
		for k = 1, count do
			local t = (k - 0.5) / count - 0.5 + rng:NextNumber(-0.04, 0.04)
			local spot = ledge.top
				+ along * t * ledge.length * 0.9
				+ out * rng:NextNumber(-4, ledge.depth * 0.5)
			local hit, normal = cast(spot + Vector3.new(0, 30, 0), Vector3.new(0, -50, 0))
			if hit and normal and normal.Y > 0.4 then
				place(gardens, weighted(TOP[zone]), hit, normal, heroSize(8, 15, 0.35), look)
			end
		end
	end

	-- Crusts of coralline and sponge over the rock from the lip to the foot, every
	-- 26-50 studs: the colour that carries across the water
	walk({ 26, 50 }, 8, function(angle)
		local y = rng:NextNumber(floor + 20, -16)
		local hit, normal = inward(angle, y)
		if hit and normal then
			place(wall, "patch", hit, normal, rng:NextNumber(10, 18), crustLook(angle, hit.Y))
		end
	end)

	-- The lower face (-250 to the foot): sparse deep growth in the biome's colours
	walk({ 60, 130 }, 16, function(angle)
		local look, zone = deepLook(angle)
		local y0 = rng:NextNumber(floor + 30, -255)
		for _ = 1, rng:NextInteger(2, 4) do
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
			local angle = angleOf(cave.position)
			local look = deepLook(angle)
			local hit, normal =
				cast(cave.position + outward(angle) * 10, outward(angle) * -(cave.radius * 2 + 20))
			if hit and normal then
				place(deepFolder, "glowTips", hit, normal, 5, look)
			end
		end
	end

	stats.solid += solidParts
	return stats
end

return Cliff
