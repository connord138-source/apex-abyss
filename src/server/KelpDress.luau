--!strict
-- The Kelp Shallows' landmarks (owner, 2026-10-21, the approved board
-- assets/concepts/biome_detail/BoardKelp.jpg: "The Kelp Cathedral"):
--
--   * THE KELP CATHEDRAL (Config/Places KelpCathedral): a ring of giant kelp twice the
--     forests' height round an open nave, their crowns' fronds reaching in over it as
--     a roof with a gap in the middle where the light comes down, sea grass on its
--     floor;
--   * OTTER MEADOW (OtterMeadow): sea grass, a patch of purple urchins on grey rocks,
--     sea otters floating on their backs at the surface over it (they bob: the client's
--     LandmarksController, tag `Bobbing`), and a red buoy on its line;
--   * a trail of old lobster traps and sunken rowboats leading out toward the Wreck bay.
--
-- The cathedral's kelp are ordinary kelp plants (a `Kelp` model with its `Stalk`,
-- dressed GiantKelp) in World.Biomes.Kelp, so KelpController sways them and fish push
-- through them like any other. The models (biome_kelp_glb: LobsterTrap,
-- SunkenRowboat, SeaOtter, UrchinRock, KelpBuoy, SeaGrass; KelpCanopy unused) go over
-- part-built stand-ins (LandmarkKit.hero); the urchin rocks are solid, the rest soft.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Props = require(ReplicatedStorage.Shared.Props)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Kit = require(script.Parent.LandmarkKit)
local PlaceMarks = require(script.Parent.PlaceMarks)

local KelpDress = {}

export type View = { name: string, from: Vector3, to: Vector3, fov: number }
KelpDress.views = {} :: { View }

local World = Config.World
-- (its kelp as tall as the tallest of the forests', ~210, the canopy mats on their tops:
-- giant kelp scaled to the surface 440 up drew blades the size of a house)
local CATHEDRAL = { angle = 45, r = 345, ring = 80, plants = 24, height = 210 }
local MEADOW = { angle = 300, r = 335, spread = 46 }
local TRAIL = { angle = 186, from = 250, to = 465, step = 42 }

local KELP = Color3.fromRGB(78, 116, 52)
local GRASS = Color3.fromRGB(64, 132, 84)
local FROND = Color3.fromRGB(116, 142, 58)
local ROCK = Color3.fromRGB(110, 114, 118)
local URCHIN = Color3.fromRGB(70, 40, 110)
local WOOD = Color3.fromRGB(104, 80, 58)
local BROWN = Color3.fromRGB(70, 48, 34)
local RED = Color3.fromRGB(180, 44, 40)

local stats: Kit.Stats = Kit.stats()
local groundOf: Kit.Ground = function(_x: number, _z: number): (Vector3?, Vector3?)
	return nil, nil
end
local rng = Random.new(World.seed + 1310)

local function at(angle: number, r: number): Vector3
	local a = math.rad(angle)
	return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

local function floorAt(x: number, z: number): Vector3
	local hit = groundOf(x, z)
	return hit or Vector3.new(x, Seafloor.y(x, z), z)
end

-- A giant kelp plant reaching toward the surface (the structure KelpController
-- sways: a `Kelp` model with a `Stalk` part and the dressed GiantKelp beside it).
-- The model is about half as wide as it is tall, so one fitted to a tall plant's
-- whole height drew it half as tall (the cathedral's ring stood ~100 studs under
-- its canopy): a tall plant is two stacked, each turned its own way. Returns the
-- plant and the top of its stalk.
local function giantKelp(parent: Instance, base: Vector3, height: number): (Model, Vector3)
	local plant = Instance.new("Model")
	plant.Name = "Kelp"
	plant.Parent = parent
	local lean =
		CFrame.Angles(rng:NextNumber(-0.04, 0.04), rng:NextNumber(0, 6.28), rng:NextNumber(-0.04, 0.04))
	local stalk = Kit.part(
		stats,
		plant,
		"Stalk",
		Vector3.new(1.4, height, 1.4),
		CFrame.new(base) * lean * CFrame.new(0, height / 2, 0),
		KELP,
		false
	)
	stalk.CastShadow = false
	local segments = if height > 120 then 2 else 1
	local segment = height / segments
	local dressed = false
	for k = 1, segments do
		local middle = CFrame.new(base) * lean * CFrame.new(0, segment * (k - 0.5), 0)
		local upright = CFrame.new(middle.Position) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		local holder = if k == 1
			then stalk
			else Kit.anchor(plant, "Upper", middle, Vector3.new(1, segment, 1))
		local model = Props.dress(holder, "GiantKelp", {
			cframe = upright,
			size = Vector3.new(segment * 0.5, segment, segment * 0.5),
		})
		if model then
			dressed = true
			stats.models += 1
		end
	end
	if not dressed then
		-- (blades on the bare stalk, so it reads as kelp without the model)
		for b = 1, 6 do
			Kit.part(
				stats,
				plant,
				"Blade",
				Vector3.new(0.2, 14, 3.6),
				CFrame.new(base)
					* lean
					* CFrame.new(0, height * (b / 7), 0)
					* CFrame.Angles(0, b * 2.1, math.rad(26)),
				Color3.fromRGB(122, 150, 64),
				false
			)
		end
	end
	return plant, (CFrame.new(base) * lean * CFrame.new(0, height, 0)).Position
end

local function grass(parent: Instance, ground: Vector3, height: number)
	local size = Vector3.new(0.38, 1, 0.81) * height
	local box = Kit.standing(ground, rng:NextNumber(0, 6.28), size, 0.04)
	Kit.hero(stats, parent, "SeaGrass", box, size, function(m)
		for k = 1, 3 do
			Kit.part(
				stats,
				m,
				"Blade",
				Vector3.new(0.3, height, 1.2),
				box * CFrame.new((k - 2) * 0.8, 0, 0) * CFrame.Angles(0, k, math.rad((k - 2) * 12)),
				GRASS,
				false
			)
		end
	end)
end

-- The vault: long fronds fanning out level from a ring plant's crown, most reaching
-- in over the nave (its middle left open for the light), so the ring reads as a
-- roof of kelp; they sway with the plant (the KelpCanopy model read as a spiky tuft
-- from below, so it isn't used)
local function crown(plant: Model, top: Vector3, inward: Vector3)
	for f = 1, 6 do
		local turn = (f - 3.5) * 0.55 + rng:NextNumber(-0.15, 0.15)
		local dir = CFrame.fromAxisAngle(Vector3.yAxis, turn):VectorToWorldSpace(inward)
		if f == 1 or f == 6 then
			dir = -dir -- (two reach outward)
		end
		local length = rng:NextNumber(24, 34)
		local droop = math.rad(rng:NextNumber(6, 16))
		local frame = CFrame.lookAt(top, top + dir)
			* CFrame.Angles(-droop, 0, 0)
			* CFrame.new(0, 0, -length / 2)
		Kit.part(
			stats,
			plant,
			"Frond",
			Vector3.new(rng:NextNumber(4, 6), 0.35, length),
			frame * CFrame.Angles(0, 0, rng:NextNumber(-0.3, 0.3)),
			FROND,
			false
		)
	end
end

local function cathedral(kelpFolder: Instance, parent: Instance)
	local center = at(CATHEDRAL.angle, CATHEDRAL.r)
	local ground = floorAt(center.X, center.Z)
	local m = Instance.new("Model")
	m.Name = "KelpCathedral"
	m.Parent = parent
	-- The ring: tall plants round the nave, a few doubled, gaps for the way in
	for i = 1, CATHEDRAL.plants do
		local angle = (i / CATHEDRAL.plants) * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local ring = CATHEDRAL.ring + rng:NextNumber(-6, 8)
		local p = ground + Vector3.new(math.cos(angle) * ring, 0, math.sin(angle) * ring)
		local base = floorAt(p.X, p.Z)
		local height = CATHEDRAL.height + rng:NextNumber(-12, 18)
		local plant, top = giantKelp(kelpFolder, base, height)
		crown(plant, top, Vector3.new(ground.X - base.X, 0, ground.Z - base.Z).Unit)
		if i % 3 == 0 then
			local q = base + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 9
			local qBase = floorAt(q.X, q.Z)
			giantKelp(kelpFolder, qBase, CATHEDRAL.height * rng:NextNumber(0.6, 0.8))
		end
	end
	-- Light down through the gap, and sea grass on the nave's floor
	for k = 1, 3 do
		local offset = Vector3.new(math.cos(k * 2.1) * 12, 0, math.sin(k * 2.1) * 12)
		Kit.shaft(
			m,
			Vector3.new(ground.X, World.surfaceY - 2, ground.Z) + offset,
			ground + Vector3.new(0, 6, 0) + offset * 1.6,
			18 + k * 4,
			0.38
		)
	end
	for _ = 1, 14 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local p = ground
			+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(6, CATHEDRAL.ring - 12)
		grass(m, floorAt(p.X, p.Z), rng:NextNumber(6, 10))
	end
	PlaceMarks.set("KelpCathedral", ground + Vector3.new(0, 40, 0))
	Kit.clearing(stats, ground, CATHEDRAL.ring - 12)
	local away = Vector3.new(math.cos(math.rad(CATHEDRAL.angle)), 0, math.sin(math.rad(CATHEDRAL.angle)))
	table.insert(KelpDress.views, {
		name = "cathedral",
		from = ground - away * (CATHEDRAL.ring + 230) + Vector3.new(0, 70, 0),
		to = ground + Vector3.new(0, 105, 0),
		fov = 70,
	})
	table.insert(KelpDress.views, {
		name = "nave",
		from = ground + Vector3.new(4, 14, -6),
		to = ground + Vector3.new(0, CATHEDRAL.height, 0) + away * 10,
		fov = 80,
	})
end

local function meadow(parent: Instance)
	local center = at(MEADOW.angle, MEADOW.r)
	local ground = floorAt(center.X, center.Z)
	local m = Instance.new("Model")
	m.Name = "OtterMeadow"
	m.Parent = parent
	Kit.clearing(stats, ground, MEADOW.spread + 6)
	for _ = 1, 22 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local p = ground + Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(0, MEADOW.spread)
		grass(m, floorAt(p.X, p.Z), rng:NextNumber(7, 12))
	end
	-- The urchin barren on one side: grey rocks, purple urchins (solid)
	local side = Vector3.new(math.cos(math.rad(MEADOW.angle + 90)), 0, math.sin(math.rad(MEADOW.angle + 90)))
	for k = 1, 8 do
		local p = ground
			+ side * (MEADOW.spread + rng:NextNumber(-6, 18))
			+ Vector3.new(rng:NextNumber(-22, 22), 0, rng:NextNumber(-22, 22))
		local g = floorAt(p.X, p.Z)
		local width = rng:NextNumber(7, 12)
		local size = Vector3.new(1, 0.66, 0.98) * width
		local box = Kit.standing(g, rng:NextNumber(0, 6.28), size, 0.12)
		Kit.hero(stats, m, "UrchinRock", box, size, function(sm)
			Kit.part(
				stats,
				sm,
				"Rock",
				size * Vector3.new(0.9, 0.6, 0.85),
				box * CFrame.new(0, -size.Y * 0.15, 0) * CFrame.Angles(0.1, k, 0.1),
				ROCK,
				true
			)
			for u = 1, 3 do
				Kit.part(
					stats,
					sm,
					"Urchin",
					Vector3.one * width * 0.28,
					box * CFrame.new((u - 2) * width * 0.25, size.Y * 0.2, 0) * CFrame.Angles(u, u * 0.7, 0.4),
					URCHIN,
					false
				)
			end
		end, { solid = true })
	end
	-- Otters floating on their backs at the surface over the meadow
	for k = 1, 3 do
		local p = ground + Vector3.new(math.cos(k * 2.2) * 26, 0, math.sin(k * 2.2) * 26)
		local length = rng:NextNumber(7, 9)
		local size = Vector3.new(0.42, 0.48, 1) * length
		local box = CFrame.new(p.X, World.surfaceY - 5, p.Z) * CFrame.Angles(0, k * 1.9, 0)
		local holder = Kit.hero(stats, m, "SeaOtter", box, size, function(sm)
			Kit.part(stats, sm, "Body", size * Vector3.new(0.8, 0.6, 0.9), box, BROWN, false)
		end)
		CollectionService:AddTag(holder, "Bobbing")
	end
	-- A red buoy at the surface on its line down to a block on the floor
	local b = ground - side * (MEADOW.spread + 10)
	local floor = floorAt(b.X, b.Z)
	local buoyHeight = 10
	local buoySize = Vector3.new(0.45, 1, 0.48) * buoyHeight
	local buoy = CFrame.new(b.X, World.surfaceY - buoyHeight * 0.45, b.Z)
	local buoyHolder = Kit.hero(stats, m, "KelpBuoy", buoy, buoySize, function(sm)
		Kit.part(
			stats,
			sm,
			"Float",
			Vector3.new(4, 4, 4),
			buoy * CFrame.new(0, 2, 0),
			RED,
			false,
			Enum.PartType.Cylinder
		)
	end)
	CollectionService:AddTag(buoyHolder, "Bobbing")
	Kit.rod(
		stats,
		m,
		"BuoyLine",
		Vector3.new(b.X, World.surfaceY - buoyHeight, b.Z),
		floor + Vector3.new(0, 2, 0),
		0.25,
		Color3.fromRGB(64, 58, 52),
		false
	)
	Kit.part(
		stats,
		m,
		"Sinker",
		Vector3.new(4, 3, 4),
		CFrame.new(floor + Vector3.new(0, 1, 0)) * CFrame.Angles(0.1, 0.5, 0),
		Color3.fromRGB(70, 74, 80),
		true
	)
	PlaceMarks.set("OtterMeadow", ground + Vector3.new(0, 24, 0))
	table.insert(KelpDress.views, {
		name = "meadow",
		from = ground - side * 70 + Vector3.new(0, 22, 0),
		to = ground + side * 20 + Vector3.new(0, 4, 0),
		fov = 72,
	})
	table.insert(KelpDress.views, {
		name = "otters",
		from = ground + Vector3.new(0, World.surfaceY - ground.Y - 60, 0) + side * 30,
		to = ground + Vector3.new(0, World.surfaceY - ground.Y - 4, 0),
		fov = 70,
	})
end

-- Old traps and boats out toward the Wreck bay, one every `step` studs
local function litterTrail(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "LitterTrail"
	m.Parent = parent
	local k = 0
	local r = TRAIL.from
	while r <= TRAIL.to do
		k += 1
		local spot = at(TRAIL.angle + rng:NextNumber(-5, 5), r)
		local g = floorAt(spot.X, spot.Z)
		if k % 3 == 0 then
			local length = rng:NextNumber(14, 18)
			local size = Vector3.new(1, 0.32, 1) * length
			local box = Kit.standing(
				g,
				rng:NextNumber(0, 6.28),
				size,
				0.25,
				CFrame.Angles(0, 0, rng:NextNumber(-0.25, 0.25))
			)
			Kit.hero(stats, m, "SunkenRowboat", box, size, function(sm)
				Kit.part(stats, sm, "Hull", size * Vector3.new(0.9, 0.6, 0.4), box, WOOD, false)
			end)
		else
			local length = rng:NextNumber(6, 8)
			local size = Vector3.new(0.74, 0.49, 1) * length
			local box = Kit.standing(
				g,
				rng:NextNumber(0, 6.28),
				size,
				0.1,
				CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, 0)
			)
			Kit.hero(stats, m, "LobsterTrap", box, size, function(sm)
				Kit.part(stats, sm, "Trap", size * Vector3.new(0.8, 0.8, 0.9), box, WOOD, false)
			end)
		end
		r += TRAIL.step + rng:NextNumber(-8, 8)
	end
end

-- Builds the Kelp Shallows' landmarks: the cathedral's kelp into `kelpFolder` (so it
-- sways), the rest into `parent`. Returns what it made.
function KelpDress.build(kelpFolder: Instance, parent: Instance, ground: Kit.Ground): Kit.Stats
	stats = Kit.stats()
	groundOf = ground
	rng = Random.new(World.seed + 1310)
	table.clear(KelpDress.views)
	cathedral(kelpFolder, parent)
	meadow(parent)
	litterTrail(parent)
	return stats
end

return KelpDress
