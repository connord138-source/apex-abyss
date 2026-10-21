--!strict
-- The Abyssal Trench's landmarks (owner, 2026-10-21, the approved board
-- assets/concepts/biome_detail/BoardTrench.jpg: "The Leviathan's Spine"; rebuilt the
-- same day to read like its scene, assets/tripo/biome_concepts/TrenchScene.png, after
-- "look how much different your hole looks from the mockup" and "really everything
-- other than the whale, ship and lighthouse needs more detail and more intricacy"):
--
--   * THE LEVIATHAN'S SPINE (Config/Places LeviathanSpine): one long serpent skeleton
--     lying down the canyon. Its horned skull rests on a ledge of the right wall
--     (Shelf.luau's Features.skullLedge), its neck curves off the ledge into a spine of
--     ~45 vertebrae (LeviathanVertebra, dorsal spines tipped with glowing tube worms)
--     ~100 studs over the floor, ribs (LeviathanRib, bent into quarter ellipses) hang
--     from it to the floor either side as a ribcage to swim down, and the tail tapers
--     off to the floor in small vertebrae and bone heaps;
--   * THE SQUID'S LAIR (SquidLair): the big cave mouth Shelf bites into the right wall
--     near the canyon's end (Features.lair), glowing teal egg clutches inside and
--     spilling out, strands of eggs hanging from its roof, scattered beaks
--     (SquidBeak) and bones, tentacle drag marks with sucker rings across the floor,
--     a cold teal glow; the squid rises in front of it (BossService reads PlaceMarks
--     SquidLair_Rise);
--   * the walls: glowing crystal clusters and glow tubes in cyan and violet growing out
--     of both walls at many heights (seated by rays against the rock, `wall`), egg
--     clutches in wall pockets, glass sponges and crystals on the floor, loose bones,
--     and two lines of small glowing growth leading down the canyon.
--
-- The models (biome_trench_glb: LeviathanVertebra, LeviathanRib, LeviathanSkull,
-- SquidBeak, TrenchCrystals, TrenchCrystalsViolet, TrenchGlowTubes,
-- TrenchGlowTubesCyan, GlassSponge, GlowEggs, BoneHeap; tools/props/trench_prep.py)
-- go over part-built stand-ins (LandmarkKit.hero). The glowing ones carry glow maps
-- (`shine` sets their strength), so they light up the dark like the concept; the
-- ribs keep their stand-ins' rods as invisible colliders (a bent bone's own hull
-- would fill the ribcage). A few lights only: the Trench's dark keeps some ambient
-- light (Config/Tuning `light`) and the glow maps read without lights.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Kit = require(script.Parent.LandmarkKit)
local PlaceMarks = require(script.Parent.PlaceMarks)

local TrenchDress = {}

export type View = { name: string, from: Vector3, to: Vector3, fov: number }
export type Lair = { mouth: Vector3, into: Vector3, radius: number, depth: number }
export type Ledge = { top: Vector3, into: Vector3 }
-- A ray against the rock (Terrain): the hit and its normal
export type Ray = (origin: Vector3, direction: Vector3) -> (Vector3?, Vector3?)

TrenchDress.views = {} :: { View }

local World = Config.World
local trench = World.trench
local HALF = math.pi / 2
local UP = Vector3.yAxis

local BONE = Color3.fromRGB(176, 182, 172)
local BONE_DARK = Color3.fromRGB(120, 128, 122)
local ROCK = Color3.fromRGB(46, 56, 64)
local DRAG = Color3.fromRGB(22, 28, 34)
local BEAK = Color3.fromRGB(34, 30, 40)
-- (saturated, as the concept's glow: its crystals light the walls round them)
local CYAN = Color3.fromRGB(40, 255, 236)
local VIOLET = Color3.fromRGB(124, 72, 255)
local TEAL = Color3.fromRGB(50, 240, 200)
local WORM = Color3.fromRGB(60, 255, 230)
-- What the glowing models' pale colour maps are multiplied by (SurfaceAppearance
-- Color and EmissiveTint) to come out saturated, and the bones' warm white
local CYAN_TINT = Color3.fromRGB(70, 255, 240)
-- (red kept low: a bright violet glow clips toward magenta)
local VIOLET_TINT = Color3.fromRGB(136, 96, 255)
local WORM_TINT = Color3.fromRGB(110, 255, 240)
local BONE_WARM = Color3.fromRGB(255, 232, 196)
local GLASS = Color3.fromRGB(196, 214, 220)

-- Each model's box in its own axes, as Props.place fits it (tools/props/trench_prep.py
-- prints them): the vertebra's side wings run along its own Z, the rib's arc spans X
-- (its knob at the top on +X) and Y
local VERTEBRA = Vector3.new(0.48, 1, 0.78)
local RIB = Vector3.new(0.771, 1, 0.143)
local SKULL = Vector3.new(0.64, 0.5, 1)
local CRYSTALS = Vector3.new(0.73, 1, 0.91)
local TUBES = Vector3.new(0.68, 1, 0.82)
local EGGS = Vector3.new(1, 0.33, 0.94)
local HEAP = Vector3.new(0.72, 0.43, 1)
local SPONGE = Vector3.new(0.51, 1, 0.53)
local BEAKBOX = Vector3.new(0.63, 1, 0.93)

-- The spine's line from the skull's neck to the tail tip: (studs along the canyon,
-- across its line, height over the floor)
local SPINE = {
	{ 1292, 60, 100 },
	{ 1322, 46, 110 },
	{ 1352, 28, 114 },
	{ 1380, 12, 106 },
	{ 1402, -2, 86 },
	{ 1420, -14, 56 },
	{ 1432, -22, 28 },
	{ 1442, -28, 8 },
}
local VERTEBRA_HEIGHT = 30 -- a full-size vertebra, dorsal spine included
local RIB_EVERY = 12 -- studs of spine between rib pairs
local WALL = { from = 1000, to = 1425, every = 12, reach = 360 }
local TRAIL = { from = 1000, to = 1425, every = 13 }
local MAX_LIGHTS = 28
-- The worm tubes' mouths on a vertebra (the model's glowing tuft, measured off its
-- glow map in its own fitted box, -0.5..0.5): Neon tips over them, so the spine's
-- crest reads bright cyan from down the canyon as in the concept
local WORM_TIPS = { Vector3.new(0.18, 0.49, 0), Vector3.new(0.27, 0.43, -0.07), Vector3.new(0.1, 0.45, 0.08) }
-- The big clusters that frame the way (3-4 times a wall cluster): along the canyon
-- (studs from the hub), across it (of the floor's half-width; + toward the skull's
-- wall), height, kind (GROWTH index)
local HEROES = {
	{ 1104, 0.3, 30, 1 },
	{ 1132, 0.5, 46, 1 },
	{ 1108, -0.56, 40, 3 },
	{ 1150, -0.78, 54, 1 },
	{ 1176, 0.62, 44, 4 },
	{ 1214, -0.66, 48, 2 },
	{ 1300, -0.94, 50, 1 },
	{ 1338, 0.96, 46, 4 },
	{ 1392, -0.9, 52, 2 },
}

local stats: Kit.Stats = Kit.stats()
local groundOf: Kit.Ground = function(_x: number, _z: number): (Vector3?, Vector3?)
	return nil, nil
end
local wallOf: Ray? = nil
local rng = Random.new(World.seed + 1210)

local function floorAt(x: number, z: number): Vector3
	local hit = groundOf(x, z)
	return hit or Vector3.new(x, trench.floorY, z)
end

-- The canyon at `r` (studs from the hub along its line), `across` its line: the floor
-- there, the way down the canyon and the way toward its right wall (+across)
local function canyonAt(r: number, across: number): (Vector3, Vector3, Vector3)
	local angle = Seafloor.trenchAxis(r)
	local x, z = Seafloor.trenchPoint(r, across)
	local x1, z1 = Seafloor.trenchPoint(r, across + 1)
	local radial = Vector3.new(math.cos(math.rad(angle)), 0, math.sin(math.rad(angle)))
	return floorAt(x, z), radial, Vector3.new(x1 - x, 0, z1 - z).Unit
end

local function point(r: number, across: number, height: number): Vector3
	local floor = canyonAt(r, across)
	return floor + Vector3.new(0, height, 0)
end

local function halfBottom(r: number): number
	local _, width = Seafloor.trenchAxis(r)
	local _, _, half = Seafloor.trenchHalfWidths(width)
	return half
end

local function light(holder: Instance, color: Color3, range: number, brightness: number)
	if stats.lights < MAX_LIGHTS then
		Kit.light(stats, holder, color, range, brightness)
	end
end

-- A model's glow map at `strength`, tinted `tint` (the imported SurfaceAppearances
-- keep their emissive map; its strength and tint are the game's to set). The model
-- carries them as Glow / GlowTint attributes too, which the cloud previewer reads.
local function shine(model: Model?, strength: number, tint: Color3?)
	if model == nil then
		return
	end
	model:SetAttribute("Glow", strength)
	if tint then
		model:SetAttribute("GlowTint", tint)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("SurfaceAppearance") then
			d.EmissiveStrength = strength
			if tint then
				d.EmissiveTint = tint
			end
		elseif d:IsA("BasePart") then
			d.CastShadow = false
		end
	end
end

-- A frame at `at` whose up is `up` (and a look at right angles to it)
local function upright(at: Vector3, up: Vector3, yaw: number): CFrame
	local u = up.Unit
	local side = if math.abs(u.Y) > 0.95 then Vector3.xAxis else UP
	local right = side:Cross(u).Unit
	return CFrame.fromMatrix(at, right, u) * CFrame.Angles(0, yaw, 0)
end

-- A tuft of glowing tube worms: thin Neon stalks with flat caps (the stand-ins' glow)
local function wormTuft(parent: Instance, at: CFrame, size: number, color: Color3)
	for k = 1, 3 do
		local lean = CFrame.Angles(math.rad(k * 23 - 46), 0, math.rad(k * 17 - 30))
		local height = size * (0.7 + 0.25 * k)
		local base = at * lean
		local stalk = Kit.part(
			stats,
			parent,
			"WormStalk",
			Vector3.new(height, size * 0.14, size * 0.14),
			base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, HALF),
			color:Lerp(Color3.new(0, 0, 0), 0.45),
			false,
			Enum.PartType.Cylinder
		)
		stalk.Transparency = 0.15
		Kit.glow(
			stats,
			parent,
			"WormCap",
			Vector3.new(size * 0.12, size * 0.36, size * 0.36),
			base * CFrame.new(0, height, 0) * CFrame.Angles(0, 0, HALF),
			color,
			Enum.PartType.Cylinder
		)
	end
end

-- A cluster of glowing prisms on a dark rock (a crystal's or tube's stand-in)
local function prisms(parent: Instance, at: CFrame, size: number, color: Color3, seed: number)
	local own = Random.new(seed)
	Kit.part(
		stats,
		parent,
		"CrystalRock",
		Vector3.new(size * 1.1, size * 0.35, size * 0.9),
		at * CFrame.new(0, size * 0.1, 0) * CFrame.Angles(0, own:NextNumber(0, 3), 0.1),
		ROCK,
		false
	)
	for k = 1, 4 do
		local height = size * own:NextNumber(0.5, 1.2) * (if k == 1 then 1.3 else 1)
		local tilt =
			CFrame.Angles(own:NextNumber(-0.45, 0.45), own:NextNumber(0, 6.28), own:NextNumber(-0.45, 0.45))
		local base = at
			* CFrame.new(own:NextNumber(-0.3, 0.3) * size, 0, own:NextNumber(-0.3, 0.3) * size)
			* tilt
		Kit.glow(
			stats,
			parent,
			"Prism",
			Vector3.new(height * 0.22, height, height * 0.22),
			base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, math.pi / 4, 0),
			color
		)
	end
end

-- The glowing growth kinds, their colours and boxes
local GROWTH = {
	{ name = "TrenchCrystals", color = CYAN, tint = CYAN_TINT, glow = 3.6, box = CRYSTALS, weight = 0.32 },
	{
		name = "TrenchCrystalsViolet",
		color = VIOLET,
		tint = VIOLET_TINT,
		glow = 3.6,
		box = CRYSTALS,
		weight = 0.2,
	},
	{ name = "TrenchGlowTubes", color = VIOLET, tint = VIOLET_TINT, glow = 3, box = TUBES, weight = 0.26 },
	{ name = "TrenchGlowTubesCyan", color = CYAN, tint = CYAN_TINT, glow = 3, box = TUBES, weight = 0.22 },
}
local function pickGrowth()
	local roll = rng:NextNumber()
	for _, kind in GROWTH do
		roll -= kind.weight
		if roll <= 0 then
			return kind
		end
	end
	return GROWTH[1]
end

-- One glowing cluster standing on `frame` (its foot), `height` tall, in its kind's
-- saturated colour; `lit` gives it a light that washes the rock round it (a big one's
-- reaches further)
local function growth(parent: Instance, frame: CFrame, height: number, kind: any, lit: boolean)
	local size = kind.box * height
	local box = frame * CFrame.new(0, size.Y * 0.44, 0) * Kit.GLB_FRONT
	local _, model = Kit.hero(stats, parent, kind.name, box, size, function(sm)
		prisms(sm, frame, height * 0.8, kind.color, math.floor(frame.Position.X * 7 + frame.Position.Z))
	end, { tint = kind.tint })
	shine(model, if height > 30 then kind.glow * 1.25 else kind.glow, kind.color)
	if lit then
		local holder = Kit.anchor(parent, "GrowthLight", frame * CFrame.new(0, height * 0.55, 0))
		if height > 30 then
			light(holder, kind.color, 60, 2.6)
		else
			light(holder, kind.color, 40, 1.8)
		end
	end
end

-- ---------------------------------------------------------------------------
-- The Leviathan's Spine
-- ---------------------------------------------------------------------------

-- Catmull-Rom through `points`, `steps` samples a span
local function curve(points: { Vector3 }, steps: number): { Vector3 }
	local out = {}
	for i = 1, #points - 1 do
		local p0 = points[math.max(i - 1, 1)]
		local p1, p2 = points[i], points[i + 1]
		local p3 = points[math.min(i + 2, #points)]
		for s = 0, steps - 1 do
			local t = s / steps
			local t2, t3 = t * t, t * t * t
			table.insert(
				out,
				0.5
					* (
						(2 * p1)
						+ (-p0 + p2) * t
						+ (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
						+ (-p0 + 3 * p1 - 3 * p2 + p3) * t3
					)
			)
		end
	end
	table.insert(out, points[#points])
	return out
end

-- Size along the spine (0 at the neck, 1 at the tail's tip)
local function spineScale(u: number): number
	if u < 0.12 then
		return 0.82 + u / 0.12 * 0.18
	elseif u < 0.6 then
		return 1
	end
	return 1 - (u - 0.6) / 0.4 * 0.7
end

local function vertebra(parent: Instance, at: Vector3, tangent: Vector3, scale: number, lit: boolean)
	local right = tangent:Cross(UP).Unit
	local up = right:Cross(tangent).Unit
	local frame = CFrame.fromMatrix(at, right, up)
	local height = VERTEBRA_HEIGHT * scale
	local size = VERTEBRA * height
	-- the centrum sits on the spine's line, a quarter up the model's box
	local box = frame * CFrame.new(0, height * 0.25, 0) * CFrame.Angles(0, HALF, 0)
	local _, model = Kit.hero(stats, parent, "LeviathanVertebra", box, size, function(sm)
		Kit.part(
			stats,
			sm,
			"Centrum",
			Vector3.new(height * 0.36, height * 0.4, height * 0.4),
			frame * CFrame.Angles(0, HALF, 0),
			BONE,
			true,
			Enum.PartType.Cylinder
		)
		Kit.part(
			stats,
			sm,
			"Wings",
			Vector3.new(height * 0.78, height * 0.1, height * 0.14),
			frame,
			BONE_DARK,
			false
		)
		Kit.part(
			stats,
			sm,
			"Dorsal",
			Vector3.new(height * 0.12, height * 0.62, height * 0.18),
			frame * CFrame.new(0, height * 0.48, 0) * CFrame.Angles(-0.25, 0, 0),
			BONE,
			false
		)
		wormTuft(sm, frame * CFrame.new(0, height * 0.78, height * 0.08), height * 0.14, WORM)
	end, { solid = true, tint = BONE_WARM })
	shine(model, 1.6, WORM_TINT)
	if model then
		-- bright Neon mouths on the model's own worm tubes
		for k, tip in WORM_TIPS do
			local mouth = box:PointToWorldSpace(Vector3.new(tip.X * size.X, tip.Y * size.Y, tip.Z * size.Z))
			local tube = height * (if k == 1 then 0.11 else 0.085)
			Kit.glow(
				stats,
				parent,
				"WormTip",
				Vector3.new(tube * 1.3, tube, tube),
				CFrame.new(mouth + UP * tube * 0.3) * CFrame.Angles(0, 0, HALF),
				WORM,
				Enum.PartType.Cylinder
			)
		end
	end
	if lit then
		local holder = Kit.anchor(parent, "SpineLight", frame * CFrame.new(0, height * 1.2, 0))
		light(holder, CYAN, 50, 1.6)
	end
end

-- A rib from the spine at `at` (`height` over the floor) curving out and down to the
-- floor on side `toward`; its stand-in's rods stay as colliders
local function rib(parent: Instance, at: Vector3, height: number, toward: Vector3)
	local h = height + 3
	local w = RIB.X * h
	local floor = at - Vector3.new(0, height, 0)
	local center = floor + toward * (w / 2 + 2) + Vector3.new(0, h / 2 - 3, 0)
	-- its own +X (the knob end) back toward the spine
	local box = CFrame.fromMatrix(center, -toward, UP)
	local _, model = Kit.hero(stats, parent, "LeviathanRib", box, RIB * h, function(sm)
		local previous: Vector3? = nil
		for k = 0, 4 do
			local t = k / 4 * HALF
			local p = floor + toward * (2 + w * math.sin(t)) + Vector3.new(0, h * math.cos(t) - 3, 0)
			if previous then
				Kit.rod(
					stats,
					sm,
					"Rib",
					previous,
					p,
					h * 0.045,
					if k % 2 == 0 then BONE else BONE_DARK,
					true
				)
			end
			previous = p
		end
	end, { solid = true, keepColliders = true, tint = BONE_WARM })
	-- (the bone glows faintly, the worms on it fully: the glow map)
	shine(model, 1.2, WORM_TINT)
end

-- A rib lying loose on the floor
local function looseRib(parent: Instance, at: Vector3, length: number, yaw: number)
	local size = RIB * length
	local box = CFrame.new(at + Vector3.new(0, size.Z * 0.4, 0))
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(HALF, 0, 0)
	local _, model = Kit.hero(stats, parent, "LeviathanRib", box, size, function(sm)
		Kit.rod(
			stats,
			sm,
			"Rib",
			at + Vector3.new(-length * 0.35, 1, 0),
			at + Vector3.new(length * 0.35, 1, length * 0.15),
			length * 0.05,
			BONE,
			false
		)
	end, { tint = BONE_WARM })
	shine(model, 1.2, WORM_TINT)
end

local function boneHeap(parent: Instance, at: Vector3, size: number, yaw: number)
	local box = Kit.standing(at, yaw, HEAP * size, 0.1)
	local _, model = Kit.hero(stats, parent, "BoneHeap", box, HEAP * size, function(sm)
		Kit.part(
			stats,
			sm,
			"Bones",
			Vector3.new(size * 0.7, size * 0.16, size * 0.4),
			CFrame.new(at + Vector3.new(0, size * 0.08, 0)) * CFrame.Angles(0, yaw, 0),
			BONE,
			false
		)
	end, { tint = BONE_WARM })
	shine(model, 1.3, WORM_TINT)
end

-- A pale glass sponge standing on `ground`, `height` tall (its glow map lifts it in the dark)
local function sponge(parent: Instance, ground: Vector3, height: number)
	local box = Kit.standing(ground, rng:NextNumber(0, 6.28), SPONGE * height, 0.06)
	local _, model = Kit.hero(stats, parent, "GlassSponge", box, SPONGE * height, function(sm)
		Kit.part(
			stats,
			sm,
			"Sponge",
			Vector3.new(SPONGE.X * height * 0.8, height, SPONGE.X * height * 0.8),
			box,
			GLASS,
			false,
			Enum.PartType.Cylinder
		)
	end)
	shine(model, 1.3, Color3.fromRGB(200, 240, 255))
end

local function leviathan(parent: Instance, ledge: Ledge?)
	local m = Instance.new("Model")
	m.Name = "LeviathanSpine"
	m.Parent = parent

	-- The skull on its rock (or the floor, without one), looking back up the canyon
	-- and in across it, so whoever comes down the canyon meets its stare
	local headR = 1240
	local _, radial, side = canyonAt(headR, 0)
	local seat = if ledge then ledge.top else point(headR, halfBottom(headR) - 60, 0)
	local inward = if ledge then -ledge.into else -side
	local look = (-radial * 0.8 + inward * 0.6).Unit
	local skullSize = SKULL * 86
	local skullCenter = seat + Vector3.new(0, skullSize.Y * 0.5 - 4, 0)
	local skullBox = CFrame.lookAt(skullCenter, skullCenter + look)
	-- (the model's snout is on its own +Z, the box's back)
	local _, skull = Kit.hero(
		stats,
		m,
		"LeviathanSkull",
		skullBox * CFrame.Angles(0, math.pi, 0),
		skullSize,
		function(sm)
			Kit.part(
				stats,
				sm,
				"Cranium",
				Vector3.new(45, 33, 51),
				skullBox * CFrame.new(0, 3, 12),
				BONE,
				true
			)
			Kit.part(
				stats,
				sm,
				"Snout",
				Vector3.new(30, 18, 39),
				skullBox * CFrame.new(0, -4, -30),
				BONE_DARK,
				true
			)
			for s = -1, 1, 2 do
				Kit.rod(
					stats,
					sm,
					"Horn",
					skullBox:PointToWorldSpace(Vector3.new(s * 15, 15, 21)),
					skullBox:PointToWorldSpace(Vector3.new(s * 30, 36, 51)),
					3.6,
					BONE,
					false
				)
			end
		end,
		{ solid = true, blocksCamera = true, tint = BONE_WARM }
	)
	-- (its tube worms glow bright cyan, the bone round them faintly)
	shine(skull, 3, WORM)
	light(Kit.anchor(m, "SkullLight", skullBox * CFrame.new(0, 30, 10)), WORM, 54, 1.8)

	-- The spine: the neck from the back of the skull, then the body and the tail
	local points = { skullCenter - look * (skullSize.Z * 0.46) + Vector3.new(0, 6, 0) }
	for _, p in SPINE do
		table.insert(points, point(p[1], p[2], p[3]))
	end
	local line = curve(points, 16)
	local lengths = { 0 }
	for i = 2, #line do
		lengths[i] = lengths[i - 1] + (line[i] - line[i - 1]).Magnitude
	end
	local total = lengths[#line]
	local function sample(s: number): (Vector3, Vector3)
		local i = 2
		while i < #line and lengths[i] < s do
			i += 1
		end
		local a, b = line[i - 1], line[i]
		local t = math.clamp((s - lengths[i - 1]) / math.max(lengths[i] - lengths[i - 1], 1e-3), 0, 1)
		return a:Lerp(b, t), (b - a).Unit
	end

	local s, count = 0, 0
	while s <= total do
		local u = s / total
		local scale = spineScale(u)
		local at, tangent = sample(s)
		count += 1
		vertebra(m, at, tangent, scale, count % 8 == 3)
		s += VERTEBRA_HEIGHT * scale * 0.38 + 0.6
	end

	-- The ribcage: pairs from the body's stretch, each reaching the floor
	local middle: Vector3? = nil
	s = total * 0.16
	local pairs = 0
	while s <= total * 0.74 do
		local at, tangent = sample(s)
		local below = floorAt(at.X, at.Z)
		local height = at.Y - below.Y
		if height > 24 then
			pairs += 1
			local across = tangent:Cross(UP).Unit
			for _, toward in { across, -across } do
				-- (not into a wall: the neck runs close to the right one)
				local foot = below + toward * (height * RIB.X + 4)
				local r = (Vector3.new(foot.X, 0, foot.Z) - Vector3.new(
					World.hub.center.X,
					0,
					World.hub.center.Z
				)).Magnitude
				local _, _, sideway = canyonAt(r, 0)
				local axis = canyonAt(r, 0)
				if math.abs((foot - axis):Dot(sideway)) < halfBottom(r) - 8 then
					rib(m, at, height, toward)
				end
			end
			if pairs == 6 then
				middle = at
			end
		end
		s += RIB_EVERY
	end

	-- A cyan glow inside the ribcage, so it reads as a lit tunnel down the canyon
	for _, u in { 0.34, 0.6 } do
		local at = sample(total * u)
		local below = floorAt(at.X, at.Z)
		light(Kit.anchor(m, "RibcageGlow", CFrame.new(below + UP * 22)), WORM, 60, 2)
	end

	-- Under the ribcage: glass sponges, crystals at the ribs' feet, a heap of bones
	for k = 1, 9 do
		local at, tangent = sample(total * (0.16 + 0.055 * k))
		local across = tangent:Cross(UP).Unit
		local below = floorAt(at.X, at.Z)
		local reach = (at.Y - below.Y) * RIB.X
		local spot = below + across * ((if k % 2 == 0 then 1 else -1) * reach * rng:NextNumber(0.2, 0.55))
		local ground = floorAt(spot.X, spot.Z)
		sponge(m, ground, rng:NextNumber(10, 20))
		-- a cluster at a rib's foot
		local foot = below + across * ((if k % 2 == 0 then -1 else 1) * (reach + rng:NextNumber(4, 12)))
		local footGround = floorAt(foot.X, foot.Z)
		growth(
			m,
			upright(footGround, UP, rng:NextNumber(0, 6.28)),
			rng:NextNumber(9, 15),
			pickGrowth(),
			false
		)
	end
	-- The tail's end: small vertebrae scattered and heaps of bone
	for k = 1, 4 do
		local at = sample(total * (0.86 + 0.035 * k))
		local spot = at + Vector3.new(rng:NextNumber(-14, 14), 0, rng:NextNumber(-14, 14))
		boneHeap(m, floorAt(spot.X, spot.Z), rng:NextNumber(14, 22), rng:NextNumber(0, 6.28))
	end
	for k = 1, 4 do
		local at = sample(total * (0.25 + 0.12 * k))
		local spot = at + Vector3.new(rng:NextNumber(-30, 30), 0, rng:NextNumber(-30, 30))
		looseRib(m, floorAt(spot.X, spot.Z), rng:NextNumber(26, 40), rng:NextNumber(0, 6.28))
	end

	-- Up the canyon from the skull, the approach: ribs and bones the currents carried
	-- off, glass sponges, a heap of vertebrae
	for k = 1, 9 do
		local r = 1096 + k * 12 + rng:NextNumber(-4, 4)
		local spot = canyonAt(r, rng:NextNumber(-70, 30))
		if k % 3 == 1 then
			looseRib(m, spot, rng:NextNumber(24, 38), rng:NextNumber(0, 6.28))
		elseif k % 3 == 2 then
			sponge(m, spot, rng:NextNumber(9, 16))
		else
			boneHeap(m, spot, rng:NextNumber(12, 18), rng:NextNumber(0, 6.28))
		end
	end

	if middle then
		PlaceMarks.set("LeviathanSpine", middle)
	end
	-- The concept's view: from the canyon's head end near the floor, the skull on its
	-- ledge to the right, the ribcage running away down the canyon
	table.insert(TrenchDress.views, {
		name = "spine",
		from = point(1074, 26, 36),
		to = point(1370, 14, 74),
		fov = 68,
	})
	table.insert(TrenchDress.views, {
		name = "ribcage",
		from = point(1300, 10, 36),
		to = point(1430, -20, 56),
		fov = 74,
	})
	table.insert(TrenchDress.views, {
		name = "skull",
		from = point(1150, 10, 84),
		to = skullCenter,
		fov = 56,
	})
	table.insert(TrenchDress.views, {
		name = "walls",
		from = point(1230, -70, 40),
		to = point(1300, -halfBottom(1300), 70),
		fov = 70,
	})
end

-- ---------------------------------------------------------------------------
-- The Squid's Lair
-- ---------------------------------------------------------------------------

local function eggs(parent: Instance, ground: Vector3, size: number, yaw: number, up: Vector3?)
	local frame = upright(ground, up or UP, yaw)
	local box = frame * CFrame.new(0, EGGS.Y * size * 0.35, 0) * Kit.GLB_FRONT
	local _, model = Kit.hero(stats, parent, "GlowEggs", box, EGGS * size, function(sm)
		for e = 1, 5 do
			Kit.glow(
				stats,
				sm,
				"Egg",
				Vector3.new(size * 0.16, size * 0.22, size * 0.16),
				frame
					* CFrame.new((e - 3) * size * 0.15, size * 0.11, (e % 2) * size * 0.12 - size * 0.06)
					* CFrame.Angles(0, e, 0.2),
				TEAL,
				Enum.PartType.Cylinder
			)
		end
	end)
	-- (its glow map is its whole colour map, the dark rock included: the teal tint keeps
	-- the rock dark and the eggs bright)
	shine(model, 3.4, TEAL)
end

local function beak(parent: Instance, ground: Vector3, size: number)
	local box =
		Kit.standing(ground, rng:NextNumber(0, 6.28), BEAKBOX * size, 0.12, CFrame.Angles(0.3, 0, 0.5))
	Kit.hero(stats, parent, "SquidBeak", box, BEAKBOX * size, function(sm)
		Kit.part(stats, sm, "Beak", Vector3.new(size * 0.4, size * 0.55, size * 0.75), box, BEAK, false)
	end)
end

-- A drag mark: a dark groove from `a` to `b` bowed sideways by `bow`, sucker rings along
-- its edges (the squid hauls prey back to its cave)
local function dragMark(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	bow: Vector3,
	width: number,
	floorY: (Vector3) -> number
)
	local previous: Vector3? = nil
	local steps = 12
	for k = 0, steps do
		local t = k / steps
		local flat = a:Lerp(b, t) + bow * math.sin(t * math.pi)
		local p = Vector3.new(flat.X, floorY(flat) + 0.15, flat.Z)
		if previous then
			local w = width * (1 - t * 0.6)
			local mid = (previous + p) / 2
			local span = p - previous
			local frame = CFrame.lookAt(mid, mid + span)
			Kit.part(stats, parent, "Drag", Vector3.new(w, 0.4, span.Magnitude + 0.6), frame, DRAG, false)
			if k % 2 == 0 then
				for s = -1, 1, 2 do
					local ring = frame * CFrame.new(s * w * 0.62, 0.1, 0) * CFrame.Angles(0, 0, HALF)
					Kit.part(
						stats,
						parent,
						"Sucker",
						Vector3.new(0.3, w * 0.42, w * 0.42),
						ring,
						DRAG,
						false,
						Enum.PartType.Cylinder
					)
				end
			end
		end
		previous = p
	end
end

local function squidLair(parent: Instance, lair: Lair)
	local m = Instance.new("Model")
	m.Name = "SquidLair"
	m.Parent = parent
	local into = lair.into
	local side = into:Cross(UP).Unit
	local caveFloor = lair.mouth.Y - lair.radius + 6
	local function floorHere(p: Vector3): number
		-- inside the cave (past its mouth) the floor is its own; outside, the canyon's
		if (p - lair.mouth):Dot(into) > 2 then
			return caveFloor
		end
		return floorAt(p.X, p.Z).Y
	end
	local function ground(p: Vector3): Vector3
		return Vector3.new(p.X, floorHere(p), p.Z)
	end

	-- Clutches deep inside and spilling out of the mouth
	for k = 1, 6 do
		local spot = lair.mouth
			+ into * (12 + k * 11)
			+ side * ((if k % 2 == 0 then 1 else -1) * rng:NextNumber(4, 18))
		eggs(m, ground(spot), rng:NextNumber(12, 17), rng:NextNumber(0, 6.28))
	end
	for k = 1, 3 do
		local spot = lair.mouth - into * rng:NextNumber(6, 22) + side * ((k - 2) * 16)
		eggs(m, ground(spot), rng:NextNumber(9, 13), rng:NextNumber(0, 6.28))
	end
	-- Strands of eggs hanging from the roof just inside the mouth
	local roof = lair.mouth.Y + lair.radius - 4
	for k = 1, 9 do
		local top = lair.mouth
			+ into * rng:NextNumber(3, 34)
			+ side * rng:NextNumber(-lair.radius * 0.6, lair.radius * 0.6)
		local beads = rng:NextInteger(4, 7)
		local y = roof - math.abs((top - lair.mouth):Dot(side)) * 0.35
		Kit.part(
			stats,
			m,
			"Strand",
			Vector3.new(0.35, beads * 2.6, 0.35),
			CFrame.new(top.X, y - beads * 1.3, top.Z),
			TEAL:Lerp(Color3.new(0, 0, 0), 0.5),
			false
		)
		for b = 1, beads do
			Kit.glow(
				stats,
				m,
				"StrandEgg",
				Vector3.new(1.5, 1.9, 1.5),
				CFrame.new(top.X, y - b * 2.5, top.Z) * CFrame.Angles(0, b, 0),
				TEAL,
				Enum.PartType.Cylinder
			)
		end
	end
	-- Beaks and bones
	for k = 1, 6 do
		local spot = lair.mouth + into * rng:NextNumber(-30, 40) + side * rng:NextNumber(-30, 30)
		beak(m, ground(spot), rng:NextNumber(5, 9))
	end
	for k = 1, 2 do
		local spot = lair.mouth - into * rng:NextNumber(16, 34) + side * ((k - 1.5) * 44)
		boneHeap(m, ground(spot), rng:NextNumber(16, 24), rng:NextNumber(0, 6.28))
	end
	for k = 1, 3 do
		local spot = lair.mouth - into * rng:NextNumber(26, 60) + side * rng:NextNumber(-50, 50)
		looseRib(m, ground(spot), rng:NextNumber(18, 30), rng:NextNumber(0, 6.28))
	end
	-- Tentacle drag marks out of the cave across the floor
	for k = 1, 5 do
		local a = lair.mouth + into * rng:NextNumber(28, 54) + side * rng:NextNumber(-14, 14)
		local b = lair.mouth - into * rng:NextNumber(70, 130) + side * ((k - 3) * rng:NextNumber(14, 26))
		dragMark(m, a, b, side * rng:NextNumber(-22, 22), rng:NextNumber(3.5, 5.5), floorHere)
	end
	-- Two big clusters flanking the mouth (each lighting the rock round it) and smaller
	-- growth round it, so it's found from down the canyon
	for k = 1, 2 do
		local sign = if k == 1 then 1 else -1
		local spot = lair.mouth + side * sign * (lair.radius + 16) - into * 8
		growth(m, upright(ground(spot), UP, rng:NextNumber(0, 6.28)), 40 - k * 6, GROWTH[k], true)
	end
	for k = 1, 6 do
		local spot = lair.mouth
			+ side * ((if k % 2 == 0 then 1 else -1) * (lair.radius + rng:NextNumber(2, 14)))
			- into * rng:NextNumber(0, 10)
		growth(
			m,
			upright(ground(spot), UP, rng:NextNumber(0, 6.28)),
			rng:NextNumber(10, 18),
			pickGrowth(),
			false
		)
	end
	-- A dark rim of rock round the mouth's arch, so the cave reads as a clear dark
	-- shape against the lit wall with its eggs glowing inside (no haze at the mouth)
	-- (broken: each block its own size, reach and tilt, a few doubled)
	local rim = Color3.fromRGB(24, 30, 36)
	for k = 0, 13 do
		local a = k / 13 * math.pi + rng:NextNumber(-0.06, 0.06)
		local out = side * math.cos(a) + UP * math.sin(a)
		local at = lair.mouth + out * (lair.radius + rng:NextNumber(1, 7)) - into * rng:NextNumber(0, 4)
		local tangent = side * -math.sin(a) + UP * math.cos(a)
		local frame = CFrame.fromMatrix(at, tangent, out)
			* CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.2, 0.2))
		Kit.part(
			stats,
			m,
			"LairRim",
			Vector3.new(lair.radius * rng:NextNumber(0.3, 0.45), rng:NextNumber(5, 11), rng:NextNumber(7, 12)),
			frame,
			rim,
			false
		)
		if k % 3 == 1 then
			Kit.part(
				stats,
				m,
				"LairRim",
				Vector3.new(lair.radius * 0.22, rng:NextNumber(4, 7), 8),
				frame * CFrame.new(rng:NextNumber(-2, 2), rng:NextNumber(4, 7), 2) * CFrame.Angles(0, 0, 0.4),
				rim,
				false
			)
		end
	end
	-- A cold teal glow low over the clutches inside (short, so the cave's walls stay dark
	-- round the glowing eggs, as the concept's egg niche)
	light(Kit.anchor(m, "LairGlow", CFrame.new(lair.mouth + into * 30 + UP * 4)), TEAL, 40, 2.2)
	light(Kit.anchor(m, "LairGlowDeep", CFrame.new(lair.mouth + into * 64 + UP * 3)), TEAL, 34, 1.6)

	PlaceMarks.set("SquidLair", lair.mouth + UP * 10)
	PlaceMarks.set("SquidLair_Rise", lair.mouth - into * 30 + UP * 70)
	table.insert(TrenchDress.views, {
		name = "lair",
		from = lair.mouth - into * 120 + UP * 26 - side * 40,
		to = lair.mouth + into * 10 - UP * 4,
		fov = 64,
	})
end

-- ---------------------------------------------------------------------------
-- The walls, the floor and the glowing trail
-- ---------------------------------------------------------------------------

-- The big clusters framing the way down the canyon (HEROES), each lighting the rock
-- round it: they close the wide canyon in to the concept's narrow one
local function heroes(parent: Instance, ledge: Ledge?)
	local m = Instance.new("Model")
	m.Name = "TrenchHeroes"
	m.Parent = parent
	for _, h in HEROES do
		local r, across, height = h[1], h[2], h[3]
		local ground = canyonAt(r, across * halfBottom(r))
		if ledge then
			local flat = Vector3.new(ground.X - ledge.top.X, 0, ground.Z - ledge.top.Z)
			if flat.Magnitude < 60 then
				continue
			end
		end
		growth(m, upright(ground, UP, rng:NextNumber(0, 6.28)), height, GROWTH[h[4]], true)
	end
end

local function walls(parent: Instance, lair: Lair?, ledge: Ledge?)
	local m = Instance.new("Model")
	m.Name = "TrenchWalls"
	m.Parent = parent
	local ray = wallOf
	if ray == nil then
		return
	end
	local placed = 0
	local r = WALL.from
	while r <= WALL.to do
		for _, sign in { -1, 1 } do
			local _, _, side = canyonAt(r, 0)
			local heights = { rng:NextNumber(4, 40), rng:NextNumber(30, 100) }
			if rng:NextNumber() < 0.45 then
				table.insert(heights, rng:NextNumber(90, 155))
			end
			for _, h in heights do
				local origin = point(r + rng:NextNumber(-5, 5), 0, h)
				local hit, normal = ray(origin, side * sign * WALL.reach)
				if hit == nil or normal == nil then
					continue
				end
				if lair and (hit - lair.mouth).Magnitude < lair.radius + 26 then
					continue
				end
				-- (nothing round the skull or over it on its rock)
				if ledge then
					local flat = Vector3.new(hit.X - ledge.top.X, 0, hit.Z - ledge.top.Z)
					if flat.Magnitude < 74 and hit.Y > ledge.top.Y - 24 then
						continue
					end
				end
				placed += 1
				-- out of the wall and up, leaning out a little
				local up = (normal * 0.55 + UP).Unit
				local size = if h < 40
					then rng:NextNumber(18, 32)
					elseif h < 100 then rng:NextNumber(14, 25)
					else rng:NextNumber(10, 18)
				local frame = upright(hit - normal * size * 0.12, up, rng:NextNumber(0, 6.28))
				if placed % 9 == 4 and h < 70 then
					eggs(m, hit - normal * 2, size * 0.9, rng:NextNumber(0, 6.28), up)
				else
					growth(m, frame, size, pickGrowth(), placed % 5 == 0)
				end
			end
		end
		r += WALL.every
	end
end

local function floorGrowth(parent: Instance, lair: Lair?, ledge: Ledge?)
	local m = Instance.new("Model")
	m.Name = "TrenchFloor"
	m.Parent = parent
	local function clear(spot: Vector3): boolean
		if lair and (spot - lair.mouth).Magnitude < lair.radius + 30 then
			return false
		end
		if ledge then
			local flat = Vector3.new(spot.X - ledge.top.X, 0, spot.Z - ledge.top.Z)
			if flat.Magnitude < 60 then
				return false
			end
		end
		return true
	end
	-- Two lines of small glowing growth down the canyon, either side of its middle
	local k = 0
	local r = TRAIL.from
	while r <= TRAIL.to do
		k += 1
		for _, sign in { -1, 1 } do
			local across = sign * halfBottom(r) * rng:NextNumber(0.55, 0.68)
			local ground = canyonAt(r + rng:NextNumber(-3, 3), across)
			local kind = if k % 2 == 0 then GROWTH[4] else GROWTH[1]
			if clear(ground) then
				growth(m, upright(ground, UP, rng:NextNumber(0, 6.28)), rng:NextNumber(7, 12), kind, false)
			end
		end
		r += TRAIL.every
	end
	-- Big clusters thick along the foot of both walls and in toward the middle, so the
	-- canyon's floor is lined with glow and reads as narrow as the concept's
	r = TRAIL.from + 6
	while r <= TRAIL.to do
		for _, sign in { -1, 1 } do
			local across = sign * halfBottom(r) * rng:NextNumber(0.68, 0.92)
			local ground = canyonAt(r + rng:NextNumber(-6, 6), across)
			if clear(ground) then
				growth(
					m,
					upright(ground, UP, rng:NextNumber(0, 6.28)),
					rng:NextNumber(18, 32),
					pickGrowth(),
					false
				)
			end
		end
		r += rng:NextNumber(17, 25)
	end
	-- Sponges and clusters on the floor beyond the skeleton
	for n = 1, 8 do
		local rr = rng:NextNumber(trench.radii[1] + 20, trench.radii[2] - 20)
		local sign = if n % 2 == 0 then 1 else -1
		local ground = canyonAt(rr, sign * halfBottom(rr) * rng:NextNumber(0.72, 0.9))
		sponge(m, ground, rng:NextNumber(10, 18))
	end
end

-- The old Neon speck clusters down the canyon's walls, as crystal shards (WorldService
-- draws their spots on the shared Random and hands them here, no draws taken)
function TrenchDress.speck(
	parent: Instance,
	position: Vector3,
	size: number,
	color: Color3,
	index: number
): BasePart
	local tilt = CFrame.Angles(
		math.rad((index * 37) % 50 - 25),
		math.rad(index * 53),
		math.rad((index * 23) % 40 - 20)
	)
	local shard = Kit.glow(
		stats,
		parent,
		"Glow",
		Vector3.new(size * 0.5, size * 1.8, size * 0.5),
		CFrame.new(position) * tilt * CFrame.Angles(0, math.pi / 4, 0),
		color
	)
	return shard
end

-- Builds the Trench's landmarks on the Terrain (`lair` and `ledge` from Shelf's
-- Features; `wall` a ray against the rock, for the walls' growth). Returns what it made.
function TrenchDress.build(
	parent: Instance,
	ground: Kit.Ground,
	lair: Lair?,
	wall: Ray?,
	ledge: Ledge?
): Kit.Stats
	stats = Kit.stats()
	groundOf = ground
	wallOf = wall
	rng = Random.new(World.seed + 1210)
	table.clear(TrenchDress.views)
	leviathan(parent, ledge)
	heroes(parent, ledge)
	if lair then
		squidLair(parent, lair)
	end
	walls(parent, lair, ledge)
	floorGrowth(parent, lair, ledge)
	return stats
end

return TrenchDress
