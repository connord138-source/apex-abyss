--!strict
-- The Abyssal Trench's landmarks (owner, 2026-10-21, the approved board
-- assets/concepts/biome_detail/BoardTrench.jpg: "The Leviathan's Spine"):
--
--   * THE LEVIATHAN'S SPINE (Config/Places LeviathanSpine): the skeleton of an ancient
--     serpent lying along the canyon, its spine a row of great bone arches standing
--     across it (a fish swims down the ribcage), tapering to the tail, its horned skull
--     on the floor at the head end, bones crusted with glowing worms;
--   * THE SQUID'S LAIR (SquidLair): the cave Shelf.luau bites into the canyon's wall
--     near its end (Features.lair), its floor holding the Giant Squid's glowing eggs,
--     old bones and beaks; the squid rises from in front of it (BossService reads
--     PlaceMarks SquidLair_Rise);
--   * cyan crystal clusters and violet glow tubes along the floor and the ledges, pale
--     glass sponges, bone heaps, and a trail of glowing tube-worm tufts down the
--     canyon's middle, so the way on is always lit a little.
--
-- The models (biome_trench_glb: LeviathanRibs, LeviathanSkull, TrenchCrystals,
-- TrenchGlowTubes, GlassSponge, GlowEggs, BoneHeap) go over part-built stand-ins
-- (LandmarkKit.hero). The arches keep their stand-in's rods as invisible colliders
-- (a mesh's own collision could fill an arch's opening). Glow is Neon parts and a
-- few lights: the Trench's dark keeps a little ambient light (Config/Tuning `light`),
-- so the textured bone and crystal read as dim shapes and the Neon reads from afar.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Kit = require(script.Parent.LandmarkKit)
local PlaceMarks = require(script.Parent.PlaceMarks)

local TrenchDress = {}

export type View = { name: string, from: Vector3, to: Vector3, fov: number }
export type Lair = { mouth: Vector3, into: Vector3, radius: number, depth: number }

TrenchDress.views = {} :: { View }

local World = Config.World
local trench = World.trench
local HALF = math.pi / 2

local BONE = Color3.fromRGB(176, 182, 172)
local BONE_DARK = Color3.fromRGB(120, 128, 122)
local ROCK = Color3.fromRGB(46, 56, 64)
local CYAN = Color3.fromRGB(80, 240, 230)
local VIOLET = Color3.fromRGB(170, 120, 255)
local TEAL = Color3.fromRGB(70, 210, 190)
local WORM = Color3.fromRGB(90, 255, 220)
local GLASS = Color3.fromRGB(196, 214, 220)

-- The skeleton: its head end, the arches' spans (studs across, head to tail) and the
-- gap between them as a share of the span
local SPINE = { r = 1100, spans = { 130, 124, 116, 106, 96, 84, 72 }, gap = 0.2 }
local TRAIL = { from = 1005, to = 1420, every = 26 }

local stats: Kit.Stats = Kit.stats()
local groundOf: Kit.Ground = function(_x: number, _z: number): (Vector3?, Vector3?)
	return nil, nil
end
local rng = Random.new(World.seed + 1210)

local function floorAt(x: number, z: number): Vector3
	local hit = groundOf(x, z)
	return hit or Vector3.new(x, trench.floorY, z)
end

-- The canyon's frame at `r` (studs from the hub along its line): x down-canyon, y up,
-- z across
local function canyonFrame(r: number, across: number): (CFrame, number)
	local angle, width = Seafloor.trenchAxis(r)
	local _, _, halfBottom = Seafloor.trenchHalfWidths(width)
	local x, z = Seafloor.trenchPoint(r, across)
	local radial = Vector3.new(math.cos(math.rad(angle)), 0, math.sin(math.rad(angle)))
	local ground = floorAt(x, z)
	return CFrame.fromMatrix(ground, radial, Vector3.yAxis), halfBottom
end

-- A tuft of glowing tube worms: thin Neon stalks with flat caps (no balls)
local function wormTuft(parent: Instance, at: CFrame, size: number, color: Color3, lit: boolean)
	local first: BasePart? = nil
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
		local cap = Kit.glow(
			stats,
			parent,
			"WormCap",
			Vector3.new(size * 0.12, size * 0.36, size * 0.36),
			base * CFrame.new(0, height, 0) * CFrame.Angles(0, 0, HALF),
			color,
			Enum.PartType.Cylinder
		)
		first = first or cap
	end
	if lit and first then
		Kit.light(stats, first, color, 26, 1.1)
	end
end

-- A cluster of glowing prisms on a dark rock (a crystal's stand-in, and the Trench's
-- old Neon specks' replacement)
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
	for k = 1, 5 do
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

-- ---------------------------------------------------------------------------
-- The Leviathan's Spine
-- ---------------------------------------------------------------------------

-- One arch standing across the canyon at `r`, `span` across, its rods (the stand-in,
-- kept as colliders under the model) on a half ellipse
local function arch(parent: Instance, r: number, span: number, index: number): CFrame
	local frame = canyonFrame(r, 0)
	local height = span * 0.9
	local size = Vector3.new(span * 0.33, height, span)
	-- The model's arch spans its own Z with its opening along X: X down-canyon
	local box = frame * CFrame.new(0, height / 2 - span * 0.04, 0)
	Kit.hero(stats, parent, "LeviathanRibs", box, size, function(m)
		local thick = span * 0.055
		local previous: Vector3? = nil
		for k = 0, 8 do
			local t = k / 8 * math.pi
			local point = frame:PointToWorldSpace(
				Vector3.new(0, math.sin(t) * height * 0.94, math.cos(t) * span * 0.46)
			)
			if previous then
				Kit.rod(stats, m, "Rib", previous, point, thick, if k % 2 == 0 then BONE else BONE_DARK, true)
			end
			previous = point
		end
		-- the vertebra on top
		Kit.part(
			stats,
			m,
			"Vertebra",
			Vector3.new(span * 0.22, span * 0.12, span * 0.16),
			frame * CFrame.new(0, height * 0.98, 0),
			BONE,
			true
		)
	end, { solid = true, keepColliders = true })
	-- Glowing worms along it (outside the stand-in: they stay with the model)
	for k = 1, 4 do
		local t = (k / 5) * math.pi
		local point =
			frame:PointToWorldSpace(Vector3.new(0, math.sin(t) * height * 0.94, math.cos(t) * span * 0.46))
		local up = (point - frame:PointToWorldSpace(Vector3.new(0, height * 0.3, 0))).Unit
		local at = CFrame.lookAt(point, point + up) * CFrame.Angles(-HALF, 0, 0)
		wormTuft(
			parent,
			at * CFrame.new(0, span * 0.03, 0),
			span * 0.06,
			if (k + index) % 3 == 0 then VIOLET else WORM,
			false
		)
	end
	return frame
end

local function leviathan(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "LeviathanSpine"
	m.Parent = parent
	local r = SPINE.r
	local middle: Vector3? = nil
	local first: CFrame? = nil
	for i, span in SPINE.spans do
		local frame = arch(m, r, span, i)
		first = first or frame
		if i == math.ceil(#SPINE.spans / 2) then
			middle = frame.Position + Vector3.new(0, span * 0.5, 0)
		end
		-- a light every other arch, at the top
		if i % 2 == 1 then
			local holder = Kit.anchor(m, "SpineLight", frame * CFrame.new(0, span * 0.75, 0))
			Kit.light(stats, holder, CYAN, 60, 1.3)
		end
		r += span * SPINE.gap + (SPINE.spans[i + 1] or span) * SPINE.gap
	end
	-- The tail: small vertebrae trailing off into bone heaps
	for k = 1, 3 do
		local frame = canyonFrame(r + k * 22, (k % 2 == 0 and 1 or -1) * 10)
		local heap = Vector3.new(0.72, 0.43, 1) * (26 - k * 3)
		Kit.hero(
			stats,
			m,
			"BoneHeap",
			frame * CFrame.new(0, heap.Y * 0.4, 0) * Kit.GLB_FRONT,
			heap,
			function(sm)
				Kit.part(stats, sm, "Bones", Vector3.new(18, 4, 10), frame * CFrame.new(0, 2, 0), BONE, false)
			end
		)
	end
	-- The skull at the head end, on the floor, looking up-canyon (toward the hub)
	local head = canyonFrame(SPINE.r - 78, 6)
	local skullSize = Vector3.new(58, 45, 90)
	local skullBox = head * CFrame.new(0, skullSize.Y * 0.42, 0) * CFrame.Angles(0, HALF, 0)
	Kit.hero(stats, m, "LeviathanSkull", skullBox, skullSize, function(sm)
		Kit.part(stats, sm, "Cranium", Vector3.new(45, 33, 51), skullBox * CFrame.new(0, 3, 12), BONE, true)
		Kit.part(
			stats,
			sm,
			"Snout",
			Vector3.new(30, 18, 39),
			skullBox * CFrame.new(0, -4, -30),
			BONE_DARK,
			true
		)
		for side = -1, 1, 2 do
			Kit.rod(
				stats,
				sm,
				"Horn",
				skullBox:PointToWorldSpace(Vector3.new(side * 15, 15, 21)),
				skullBox:PointToWorldSpace(Vector3.new(side * 30, 36, 51)),
				3.6,
				BONE,
				false
			)
		end
	end, { solid = true, blocksCamera = true })
	wormTuft(m, head * CFrame.new(10, 0, -16), 4, WORM, true)
	if middle then
		PlaceMarks.set("LeviathanSpine", middle)
	end
	local f = first :: CFrame
	table.insert(TrenchDress.views, {
		name = "spine",
		from = f:PointToWorldSpace(Vector3.new(-150, 60, 40)),
		to = f:PointToWorldSpace(Vector3.new(80, 50, 0)),
		fov = 70,
	})
	table.insert(TrenchDress.views, {
		name = "ribcage",
		from = f:PointToWorldSpace(Vector3.new(-36, 42, 12)),
		to = f:PointToWorldSpace(Vector3.new(160, 40, 0)),
		fov = 74,
	})
	table.insert(TrenchDress.views, {
		name = "skull",
		from = head:PointToWorldSpace(Vector3.new(-60, 24, 50)),
		to = head:PointToWorldSpace(Vector3.new(0, 14, 0)),
		fov = 66,
	})
end

-- ---------------------------------------------------------------------------
-- The Squid's Lair
-- ---------------------------------------------------------------------------

local function squidLair(parent: Instance, lair: Lair)
	local m = Instance.new("Model")
	m.Name = "SquidLair"
	m.Parent = parent
	local up = Vector3.yAxis
	local side = lair.into:Cross(up)
	for k = 1, 3 do
		local spot = lair.mouth + lair.into * (14 + k * 13) + side * ((k - 2) * 9)
		local ground = floorAt(spot.X, spot.Z)
		local box = Kit.standing(ground, k * 1.7, Vector3.new(14, 4.6, 13), 0.05)
		Kit.hero(stats, m, "GlowEggs", box, Vector3.new(14, 4.6, 13), function(sm)
			for e = 1, 5 do
				Kit.glow(
					stats,
					sm,
					"Egg",
					Vector3.new(2.6, 3.4, 2.6),
					CFrame.new(ground + Vector3.new((e - 3) * 2.2, 1.6, (e % 2) * 2 - 1))
						* CFrame.Angles(0, e, 0.2),
					TEAL
				)
			end
		end)
	end
	local glow = Kit.anchor(m, "LairGlow", CFrame.new(lair.mouth + lair.into * 30 + up * 6))
	Kit.light(stats, glow, TEAL, 46, 1.4)
	-- Old bones and beaks round the mouth
	local bones = lair.mouth + lair.into * 8 - side * 12
	local boneGround = floorAt(bones.X, bones.Z)
	local heap = Vector3.new(0.72, 0.43, 1) * 26
	Kit.hero(stats, m, "BoneHeap", Kit.standing(boneGround, 0.4, heap, 0.1), heap, function(sm)
		Kit.part(
			stats,
			sm,
			"Bones",
			Vector3.new(20, 4, 12),
			CFrame.new(boneGround + Vector3.new(0, 2, 0)),
			BONE,
			false
		)
	end)
	for k = 1, 3 do
		local spot = lair.mouth - lair.into * (4 + k * 3) + side * (k * 7 - 14)
		local g = floorAt(spot.X, spot.Z)
		local beak = CFrame.new(g + Vector3.new(0, 1.6, 0)) * CFrame.Angles(0.4, k * 2.1, 0.3)
		Kit.part(stats, m, "Beak", Vector3.new(2.4, 3.2, 4.4), beak, Color3.fromRGB(34, 30, 40), false)
		Kit.part(
			stats,
			m,
			"Beak",
			Vector3.new(2, 2.6, 3.6),
			beak * CFrame.new(0, -2, 1) * CFrame.Angles(0.8, 0, 0),
			Color3.fromRGB(34, 30, 40),
			false
		)
	end
	-- Glowing growth round the mouth so it's found
	for k = -1, 1, 2 do
		local spot = lair.mouth + side * k * (lair.radius + 2) - lair.into * 2
		wormTuft(m, CFrame.new(floorAt(spot.X, spot.Z)), 5, TEAL, k == 1)
	end
	PlaceMarks.set("SquidLair", lair.mouth + up * 10)
	PlaceMarks.set("SquidLair_Rise", lair.mouth - lair.into * 40 + up * 36)
	table.insert(TrenchDress.views, {
		name = "lair",
		from = lair.mouth - lair.into * 70 + up * 20 - side * 20,
		to = lair.mouth + lair.into * 20,
		fov = 66,
	})
end

-- ---------------------------------------------------------------------------
-- Crystals, tubes, sponges and the glowing trail
-- ---------------------------------------------------------------------------

local function scatter(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "TrenchGrowth"
	m.Parent = parent
	local kinds = {
		{
			name = "TrenchCrystals",
			count = 12,
			size = Vector3.new(0.73, 1, 0.91),
			height = { 14, 26 },
			color = CYAN,
		},
		{
			name = "TrenchGlowTubes",
			count = 9,
			size = Vector3.new(0.68, 1, 0.82),
			height = { 12, 20 },
			color = VIOLET,
		},
		{
			name = "GlassSponge",
			count = 8,
			size = Vector3.new(0.51, 1, 0.53),
			height = { 11, 18 },
			color = GLASS,
		},
	}
	for _, kind in kinds do
		for n = 1, kind.count do
			local r = rng:NextNumber(trench.radii[1] + 25, trench.radii[2] - 25)
			local _, width = Seafloor.trenchAxis(r)
			local _, _, halfBottom = Seafloor.trenchHalfWidths(width)
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local frame = canyonFrame(r, side * rng:NextNumber(halfBottom * 0.45, halfBottom - 10))
			local height = rng:NextNumber(kind.height[1], kind.height[2])
			local size = kind.size * height
			local box = Kit.standing(frame.Position, rng:NextNumber(0, 6.28), size, 0.06)
			Kit.hero(stats, m, kind.name, box, size, function(sm)
				if kind.name == "GlassSponge" then
					Kit.part(
						stats,
						sm,
						"Sponge",
						Vector3.new(size.X * 0.8, size.Y, size.X * 0.8),
						box,
						GLASS,
						false,
						Enum.PartType.Cylinder
					)
				else
					prisms(sm, CFrame.new(frame.Position), height * 0.8, kind.color, n * 31)
				end
			end)
			if kind.name ~= "GlassSponge" and n % 3 == 1 then
				local holder = Kit.anchor(
					m,
					"CrystalLight",
					CFrame.new(frame.Position + Vector3.new(0, height * 0.6, 0))
				)
				Kit.light(stats, holder, kind.color, 26, 1.5)
			end
		end
	end
	-- The trail: tufts down the canyon's middle, a little off it in turn, every third lit
	local k = 0
	local r = TRAIL.from
	while r <= TRAIL.to do
		k += 1
		local frame = canyonFrame(r, (if k % 2 == 0 then 1 else -1) * rng:NextNumber(8, 22))
		wormTuft(
			m,
			frame * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			rng:NextNumber(3.5, 5.5),
			if k % 4 == 0 then VIOLET else WORM,
			k % 4 == 0
		)
		r += TRAIL.every
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

-- Builds the Trench's landmarks on the Terrain (`lair` from Shelf's Features). Returns
-- what it made.
function TrenchDress.build(parent: Instance, ground: Kit.Ground, lair: Lair?): Kit.Stats
	stats = Kit.stats()
	groundOf = ground
	rng = Random.new(World.seed + 1210)
	table.clear(TrenchDress.views)
	leviathan(parent)
	if lair then
		squidLair(parent, lair)
	end
	scatter(parent)
	return stats
end

return TrenchDress
