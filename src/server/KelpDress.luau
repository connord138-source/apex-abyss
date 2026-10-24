--!strict
-- The Kelp Shallows' landmarks (owner, 2026-10-21, the approved board
-- assets/concepts/biome_detail/BoardKelp.jpg: "The Kelp Cathedral"; then "really
-- everything other than the whale, ship and lighthouse needs more detail and more
-- intricacy ... the world should feel full": rebuilt to read like its scene,
-- assets/tripo/biome_concepts/KelpScene.png):
--
--   * THE KELP CATHEDRAL (Config/Places KelpCathedral): a wide open nave (~165 studs
--     across) in a grove of giant kelp of every height, three loose rings of it that
--     step down outward (so from outside it reads as a grove rising to the nave, not
--     a tower), the tallest ring's crowns fanning in over the nave as a leafy roof with
--     the middle open and sun shafts coming down it; an understorey of young kelp and
--     kelp clumps round the nave's edge; on its floor patches of sea grass, rippled
--     sand, grey rocks with purple urchins and orange starfish, an old lobster trap and
--     a sunken rowboat whose float hangs on its chain over it;
--   * OTTER MEADOW (OtterMeadow): a dense sea-grass meadow, an urchin barren on a grey
--     rock pavement beside it, sea otters floating on their backs at the surface over
--     it (they bob: the client's LandmarksController, tag `Bobbing`), and a red buoy on
--     its line;
--   * a trail of old lobster traps and sunken rowboats leading out toward the Wreck bay;
--   * THE FLOOR (everywhere else in the Kelp Shallows): sea-grass patches, urchin rocks
--     and starfish scattered between the forests, so the whole biome's floor is full.
--
-- The cathedral's kelp are ordinary kelp plants (a `Kelp` model with its `Stalk`,
-- dressed GiantKelp, a piece every ~52 studs at the model's own shape: slim plants
-- with blades a fish's size) in World.Biomes.Kelp, so KelpController sways them and
-- fish push through them like any other; the young kelp too. Everything else is
-- still decor: no collisions, rays or shadows on the small pieces (the rocks are
-- solid). The models (biome_kelp_glb: LobsterTrap, SunkenRowboat, SeaOtter,
-- UrchinRock, KelpBuoy, SeaGrass; KelpCanopy unused; the forests' GiantKelp,
-- KelpClump and BoulderRound) go over part-built stand-ins (LandmarkKit.hero).
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
-- The cathedral: its nave's radius, then the rings of kelp round it (radius band,
-- plants, height band), the inner ring's crowns roofing the nave; `doors` are gaps in
-- the inner two rings (degrees from the way out from the hub) to swim in by. It
-- stands at 135°, between the 90° and 180° tunnels (PC 2026-10-22: at 45°, r 345 the
-- Blue Hole's highway, which runs back toward the hub along 45° to r ~332, ended in
-- its nave, reef corals and all), its outer ring inside r 470, short of where the
-- wreck bay's and the reef's hunters may follow a fish (their band less 60)
local CATHEDRAL = {
	angle = 135,
	r = 330,
	nave = 82,
	rings = {
		{ r = { 86, 100 }, count = 14, height = { 220, 300 }, crown = true },
		{ r = { 106, 122 }, count = 12, height = { 150, 240 }, crown = false },
		{ r = { 126, 138 }, count = 9, height = { 90, 160 }, crown = false },
	},
	doors = { 180, 20 },
}
-- (a GiantKelp piece every ~52 studs of plant, at the model's own shape: one fitted
-- to a whole tall plant drew blades the size of a house and a ring of them read as
-- one solid tower)
local SEGMENT = 52
local MEADOW = { angle = 300, r = 335, spread = 46 }
local TRAIL = { angle = 186, from = 250, to = 465, step = 42 }
-- The floor's patches across the Kelp Shallows (studs from the hub), clear of the
-- landmarks
local FLOOR = { patches = 40, from = 175, to = 465 }
-- (the most models and parts this module places)
local CAP = 900

-- (golden yellow-olive kelp and pale yellow-green grass, as KelpScene has them; the
-- models' own colour maps were lightened to match, tools/props/shallows_recolor.py)
local KELP = Color3.fromRGB(150, 134, 46)
local GRASS = Color3.fromRGB(150, 170, 78)
local FROND = Color3.fromRGB(196, 178, 58)
local ROCK = Color3.fromRGB(116, 120, 126)
local URCHIN = Color3.fromRGB(70, 40, 110)
local STAR = Color3.fromRGB(236, 110, 36)
local WOOD = Color3.fromRGB(104, 80, 58)
local BROWN = Color3.fromRGB(70, 48, 34)
local RED = Color3.fromRGB(180, 44, 40)
local IRON = Color3.fromRGB(64, 58, 52)
local CHAIN = Color3.fromRGB(96, 92, 88)
local GROOVE = Color3.fromRGB(184, 164, 122)

local stats: Kit.Stats = Kit.stats()
local groundOf: Kit.Ground = function(_x: number, _z: number): (Vector3?, Vector3?)
	return nil, nil
end
local rng = Random.new(World.seed + 1310)
local placed = 0

local function at(angle: number, r: number): Vector3
	local a = math.rad(angle)
	return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

local function floorAt(x: number, z: number): Vector3
	local hit = groundOf(x, z)
	return hit or Vector3.new(x, Seafloor.y(x, z), z)
end

local function room(): boolean
	placed += 1
	return placed <= CAP
end

-- (small decor casts no shadow)
local function quiet(model: Instance?)
	if model then
		for _, piece in model:GetDescendants() do
			if piece:IsA("BasePart") then
				piece.CastShadow = false
			end
		end
	end
end

-- A giant kelp plant reaching toward the surface (the structure KelpController
-- sways: a `Kelp` model with a `Stalk` part and the dressed GiantKelp pieces stacked
-- up it, each turned its own way). Returns the plant and the top of its stalk.
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
	local segments = math.max(1, math.round(height / SEGMENT))
	local segment = height / segments
	local dressed = false
	for k = 1, segments do
		local middle = CFrame.new(base) * lean * CFrame.new(0, segment * (k - 0.5), 0)
		local upright = CFrame.new(middle.Position) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		-- (every piece is dressed off the stalk: Props.dress only reads where it goes)
		local model = Props.dress(stalk, "GiantKelp", {
			cframe = upright,
			size = Vector3.new(segment * 0.5, segment * 1.04, segment * 0.5),
		})
		if model then
			dressed = true
			stats.models += 1
		end
	end
	if not dressed then
		-- (blades on the bare stalk, so it reads as kelp without the model)
		local blades = math.max(4, math.floor(height / 16))
		for b = 1, blades do
			Kit.part(
				stats,
				plant,
				"Blade",
				Vector3.new(0.2, 12, 3.6),
				CFrame.new(base)
					* lean
					* CFrame.new(0, height * (b / (blades + 1)), 0)
					* CFrame.Angles(0, b * 2.1, math.rad(26)),
				FROND,
				false
			)
		end
	end
	return plant, (CFrame.new(base) * lean * CFrame.new(0, height, 0)).Position
end

local function grass(parent: Instance, ground: Vector3, height: number)
	if not room() then
		return
	end
	local size = Vector3.new(0.38, 1, 0.81) * height
	local box = Kit.standing(ground, rng:NextNumber(0, 6.28), size, 0.04)
	local _, dressed = Kit.hero(stats, parent, "SeaGrass", box, size, function(m)
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
	quiet(dressed)
end

-- A patch of sea grass `count` clumps round `center`, `spread` across
local function grassPatch(
	parent: Instance,
	center: Vector3,
	spread: number,
	count: number,
	low: number,
	high: number
)
	for _ = 1, count do
		local a, d = rng:NextNumber(0, 2 * math.pi), spread * math.sqrt(rng:NextNumber())
		local p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * d
		grass(parent, floorAt(p.X, p.Z), rng:NextNumber(low, high))
	end
end

-- An orange sea star lying on the sand: a disc and five arms (decor)
local function starfish(parent: Instance, ground: Vector3, span: number)
	if not room() then
		return
	end
	local frame = CFrame.new(ground + Vector3.new(0, span * 0.05, 0))
		* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	Kit.part(
		stats,
		parent,
		"Starfish",
		Vector3.new(span * 0.12, span * 0.36, span * 0.36),
		frame * CFrame.Angles(0, 0, math.rad(90)),
		STAR,
		false,
		Enum.PartType.Cylinder
	)
	for k = 1, 5 do
		Kit.part(
			stats,
			parent,
			"StarArm",
			Vector3.new(span * 0.2, span * 0.09, span * 0.42),
			frame
				* CFrame.Angles(0, k * 2 * math.pi / 5, 0)
				* CFrame.new(0, 0, -span * 0.27)
				* CFrame.Angles(math.rad(rng:NextNumber(-6, 10)), 0, 0),
			STAR,
			false
		)
	end
end

-- A grey boulder (the forests' BoulderRound, solid) with purple urchins round its foot
-- and now and then a starfish on the sand beside it
local function urchinRock(parent: Instance, ground: Vector3, width: number)
	if not room() then
		return
	end
	local yaw = rng:NextNumber(0, 6.28)
	local size = Vector3.new(width, width * rng:NextNumber(0.45, 0.7), width * rng:NextNumber(0.8, 1))
	local box = Kit.standing(ground, yaw, size, 0.18)
	Kit.hero(stats, parent, "BoulderRound", box, size, function(m)
		Kit.part(stats, m, "Rock", size * Vector3.new(0.9, 0.8, 0.9), box, ROCK, true)
	end, { solid = true })
	for u = 1, rng:NextInteger(1, 2) do
		local a = yaw + u * 2.4
		local spot = ground + Vector3.new(math.cos(a), 0, math.sin(a)) * width * 0.55
		local g = floorAt(spot.X, spot.Z)
		local uw = width * rng:NextNumber(0.45, 0.6)
		local usize = Vector3.new(1, 0.66, 0.98) * uw
		local ubox = Kit.standing(g, rng:NextNumber(0, 6.28), usize, 0.12)
		local _, dressed = Kit.hero(stats, parent, "UrchinRock", ubox, usize, function(sm)
			for k = 1, 3 do
				Kit.part(
					stats,
					sm,
					"Urchin",
					Vector3.one * uw * 0.28,
					ubox * CFrame.new((k - 2) * uw * 0.25, usize.Y * 0.1, 0) * CFrame.Angles(k, k * 0.7, 0.4),
					URCHIN,
					false
				)
			end
		end)
		quiet(dressed)
	end
	if rng:NextNumber() < 0.6 then
		local a = yaw - 1.2
		local spot = ground + Vector3.new(math.cos(a), 0, math.sin(a)) * width * 0.75
		starfish(parent, floorAt(spot.X, spot.Z), rng:NextNumber(2.6, 4))
	end
end

-- Ripples in the sand: wavy pale crests with a darker trough behind each, running
-- across `along`
local function ripples(parent: Instance, center: Vector3, radius: number, count: number, along: Vector3)
	local across = Vector3.new(-along.Z, 0, along.X)
	for _ = 1, count do
		if not room() then
			return
		end
		local a, d = rng:NextNumber(0, 2 * math.pi), radius * math.sqrt(rng:NextNumber())
		local mid = center + Vector3.new(math.cos(a), 0, math.sin(a)) * d
		local length = rng:NextNumber(20, 34)
		local phase = rng:NextNumber(0, 6.28)
		local previous: Vector3? = nil
		-- (only the shaded trough, a little darker than the sand, in short pieces so it
		-- curves: the Terrain's toon Sand carries its own lit crests, and a lit strip
		-- beside each line read as rails)
		for k = 0, 7 do
			local t = k / 7 - 0.5
			local p = mid + across * (t * length) + along * math.sin(phase + t * 5) * 1.6
			local g = floorAt(p.X, p.Z)
			if previous then
				local prev = previous :: Vector3
				local span = Vector3.new(g.X - prev.X, 0, g.Z - prev.Z)
				local centre = (g + prev) / 2
				local frame = CFrame.lookAt(centre, centre + span)
				Kit.part(
					stats,
					parent,
					"Groove",
					Vector3.new(0.5, 0.06, span.Magnitude + 0.35),
					frame * CFrame.new(0, 0.03, 0),
					GROOVE,
					false
				)
			end
			previous = g
		end
	end
end

-- The vault: long blades fanning out from a tall plant's crown, most reaching in over
-- the nave and drooping (its middle left open for the light), so the ring reads as a
-- leafy roof; they sway with the plant (the KelpCanopy model read as a spiky tuft
-- from below, so it isn't used)
local function crown(plant: Model, top: Vector3, inward: Vector3)
	for f = 1, 4 do
		local turn = (f - 2.5) * 0.5 + rng:NextNumber(-0.15, 0.15)
		local dir = CFrame.fromAxisAngle(Vector3.yAxis, turn):VectorToWorldSpace(inward)
		if f == 4 then
			dir = -dir -- (one reaches outward)
		end
		local length = rng:NextNumber(30, 46)
		local droop = math.rad(rng:NextNumber(8, 20))
		local frame = CFrame.lookAt(top, top + dir)
			* CFrame.Angles(-droop, 0, 0)
			* CFrame.new(0, 0, -length / 2)
		local blade = Kit.part(
			stats,
			plant,
			"Frond",
			Vector3.new(rng:NextNumber(5, 7), 0.35, length),
			frame * CFrame.Angles(0, 0, rng:NextNumber(-0.3, 0.3)),
			FROND,
			false
		)
		blade.CastShadow = false
	end
end

-- Whether `angle` (degrees, measured from the way out from the hub) is in one of the
-- cathedral's doors
local function inDoor(angle: number): boolean
	for _, door in CATHEDRAL.doors do
		local apart = math.abs((angle - door + 180) % 360 - 180)
		if apart < 13 then
			return true
		end
	end
	return false
end

local function cathedral(kelpFolder: Instance, parent: Instance)
	local center = at(CATHEDRAL.angle, CATHEDRAL.r)
	local ground = floorAt(center.X, center.Z)
	local away = Vector3.new(math.cos(math.rad(CATHEDRAL.angle)), 0, math.sin(math.rad(CATHEDRAL.angle)))
	local side = Vector3.new(-away.Z, 0, away.X)
	local m = Instance.new("Model")
	m.Name = "KelpCathedral"
	m.Parent = parent
	local nave = CATHEDRAL.nave

	-- The grove: three loose rings stepping down outward, the inner one's crowns
	-- roofing the nave
	for ringIndex, ring in CATHEDRAL.rings do
		for i = 1, ring.count do
			local degrees = (i + ringIndex * 0.37) / ring.count * 360 + rng:NextNumber(-7, 7)
			local radius = rng:NextNumber(ring.r[1], ring.r[2])
			local height = rng:NextNumber(ring.height[1], ring.height[2])
			if ringIndex < 3 and inDoor(degrees) then
				continue
			end
			local a = math.rad(CATHEDRAL.angle + degrees)
			local p = ground + Vector3.new(math.cos(a), 0, math.sin(a)) * radius
			local base = floorAt(p.X, p.Z)
			local plant, top = giantKelp(kelpFolder, base, height)
			if ring.crown then
				crown(plant, top, Vector3.new(ground.X - base.X, 0, ground.Z - base.Z).Unit)
			end
		end
	end

	-- The understorey round the nave's edge: young kelp (they sway) and kelp clumps
	for k = 1, 10 do
		local a = k / 10 * 2 * math.pi + rng:NextNumber(-0.2, 0.2)
		local p = ground + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(nave - 16, nave - 4)
		giantKelp(kelpFolder, floorAt(p.X, p.Z), rng:NextNumber(40, 80))
	end
	for k = 1, 16 do
		if not room() then
			break
		end
		local a = k / 16 * 2 * math.pi + rng:NextNumber(-0.15, 0.15)
		local p = ground + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(nave - 22, nave + 2)
		local h = rng:NextNumber(14, 28)
		local size = Vector3.new(0.56, 1, 0.57) * h
		local box = Kit.standing(floorAt(p.X, p.Z), rng:NextNumber(0, 6.28), size, 0.04)
		local _, dressed = Kit.hero(stats, m, "KelpClump", box, size, function(sm)
			for b = 1, 3 do
				Kit.part(
					stats,
					sm,
					"Blade",
					Vector3.new(0.25, h, 2.4),
					box * CFrame.Angles(0, b * 2.1, math.rad(14)),
					KELP,
					false
				)
			end
		end)
		quiet(dressed)
	end

	-- The floor: patches of sea grass (thicker toward the edge), rippled sand between,
	-- rocks with urchins and starfish
	-- (small tufts scattered evenly, sand showing between, as the scene's sparse blades)
	grassPatch(m, ground, nave - 6, 120, 3, 5.5)
	for k = 1, 16 do
		local a = k / 16 * 2 * math.pi + rng:NextNumber(-0.1, 0.1)
		local p = ground + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(nave - 14, nave + 4)
		grass(m, floorAt(p.X, p.Z), rng:NextNumber(5, 8))
	end
	ripples(m, ground, nave - 16, 12, side)
	for k = 1, 6 do
		local a = k / 6 * 2 * math.pi + 0.5 + rng:NextNumber(-0.3, 0.3)
		local p = ground + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(40, nave - 8)
		urchinRock(m, floorAt(p.X, p.Z), rng:NextNumber(8, 15))
	end
	-- (the way in from the hub opens onto a pair of them either side)
	for _, sign in { -1, 1 } do
		local p = ground - away * 40 + side * sign * 17
		urchinRock(m, floorAt(p.X, p.Z), rng:NextNumber(10, 13))
	end
	for _ = 1, 4 do
		local a = rng:NextNumber(0, 2 * math.pi)
		local p = ground + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(8, nave - 20)
		starfish(m, floorAt(p.X, p.Z), rng:NextNumber(3, 4.5))
	end

	-- An old lobster trap near the way in, and a sunken rowboat across the nave whose
	-- float hangs on its chain over it
	do
		local p = ground - away * 42 - side * 8
		local g = floorAt(p.X, p.Z)
		local length = 8
		local size = Vector3.new(0.74, 0.49, 1) * length
		local box = Kit.standing(g, rng:NextNumber(0, 6.28), size, 0.1, CFrame.Angles(0.08, 0, 0))
		Kit.hero(stats, m, "LobsterTrap", box, size, function(sm)
			Kit.part(stats, sm, "Trap", size * Vector3.new(0.8, 0.8, 0.9), box, WOOD, false)
		end)
		local star = p + side * 13 + away * 3
		starfish(m, floorAt(star.X, star.Z), 5)
	end
	do
		local p = ground + away * 6 + side * 14
		local g = floorAt(p.X, p.Z)
		local length = 17
		local size = Vector3.new(1, 0.32, 1) * length
		local yaw = math.atan2(-side.X, -side.Z) + 0.5
		local box = Kit.standing(g, yaw, size, 0.22, CFrame.Angles(0, 0, 0.18))
		Kit.hero(stats, m, "SunkenRowboat", box, size, function(sm)
			Kit.part(stats, sm, "Hull", size * Vector3.new(0.9, 0.6, 0.4), box, WOOD, false)
		end)
		local bow = (box * CFrame.new(0, 0, -length * 0.4)).Position
		local float = bow + Vector3.new(4, 78, 2)
		-- (the chain stands still, so the float on it bobs a quarter as much, `Bob`, and
		-- the top link ends inside the float's body, past the eyelet under its middle:
		-- the KelpBuoy model's own side chain hangs to its box's bottom, and a chain
		-- ending there stopped 2-3 studs short of the eyelet, PC 2026-10-23/24)
		Kit.chain(stats, m, bow + Vector3.new(0, 1, 0), float + Vector3.new(0, 0.9, 0), 3, 1.8, CHAIN)
		local buoyHeight = 9
		local buoySize = Vector3.new(0.45, 1, 0.48) * buoyHeight
		local buoy = CFrame.new(float) * CFrame.Angles(0.15, 0, 0.1)
		local buoyHolder = Kit.hero(stats, m, "KelpBuoy", buoy, buoySize, function(sm)
			Kit.part(stats, sm, "Float", Vector3.new(4, 4, 4), buoy, RED, false, Enum.PartType.Cylinder)
		end)
		buoyHolder:SetAttribute("Bob", 0.25)
		CollectionService:AddTag(buoyHolder, "Bobbing")
	end

	-- Two otters floating at the surface over it, light down through the roof's gap
	for k = 1, 2 do
		local p = ground + side * (k * 2 - 3) * 16 + away * 10
		local length = rng:NextNumber(7, 9)
		local size = Vector3.new(0.42, 0.48, 1) * length
		local box = CFrame.new(p.X, World.surfaceY - 5, p.Z) * CFrame.Angles(0, k * 1.9, 0)
		local holder = Kit.hero(stats, m, "SeaOtter", box, size, function(sm)
			Kit.part(stats, sm, "Body", size * Vector3.new(0.8, 0.6, 0.9), box, BROWN, false)
		end)
		CollectionService:AddTag(holder, "Bobbing")
	end
	-- Sun shafts fanning down through the roof's gap, as the scene's: their tops close
	-- together over the nave, their feet spread over its floor, all slanting the same
	-- way (from the left of the way in), fading out just above the floor
	local sky = Vector3.new(ground.X, World.surfaceY - 2, ground.Z) - side * 70
	for k = 1, 6 do
		local a = k * 2.4 + 0.3
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		Kit.softShaft(
			m,
			sky + out * (4 + k * 2),
			ground + Vector3.new(0, 2, 0) + out * (18 + k * 7) + side * 20,
			18 + (k % 3) * 12,
			if k % 2 == 0 then 0.55 else 0.44,
			0.12
		)
	end

	PlaceMarks.set("KelpCathedral", ground + Vector3.new(0, 40, 0))
	Kit.clearing(stats, ground, nave + 4)
	-- The scene's camera: low on the nave's floor by the way in, looking across it and
	-- up into the kelp
	table.insert(KelpDress.views, {
		name = "nave",
		from = ground - away * 62 - side * 6 + Vector3.new(0, 12, 0),
		to = ground + away * 50 + Vector3.new(0, 34, 0),
		fov = 76,
	})
	table.insert(KelpDress.views, {
		name = "cathedral",
		from = ground - away * 330 + side * 60 + Vector3.new(0, 90, 0),
		to = ground + Vector3.new(0, 110, 0),
		fov = 70,
	})
	table.insert(KelpDress.views, {
		name = "roof",
		from = ground + Vector3.new(4, 14, -6),
		to = ground + Vector3.new(0, 300, 0) + away * 10,
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
	-- The meadow: sea grass thick across it
	grassPatch(m, ground, MEADOW.spread + 6, 110, 4, 7.5)
	grassPatch(m, ground, MEADOW.spread + 20, 22, 3.5, 6)
	-- The urchin barren on one side: a pavement of low grey rock, urchins all over it
	local side = Vector3.new(math.cos(math.rad(MEADOW.angle + 90)), 0, math.sin(math.rad(MEADOW.angle + 90)))
	local barren = ground + side * (MEADOW.spread + 12)
	for k = 1, 6 do
		local a = k / 6 * 2 * math.pi + rng:NextNumber(-0.3, 0.3)
		local p = barren + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(4, 20)
		local width = rng:NextNumber(16, 26)
		local size = Vector3.new(width, width * rng:NextNumber(0.3, 0.45), width * rng:NextNumber(0.8, 1))
		local box = Kit.standing(floorAt(p.X, p.Z), rng:NextNumber(0, 6.28), size, 0.35)
		Kit.hero(stats, m, "BoulderRound", box, size, function(sm)
			Kit.part(stats, sm, "Rock", size * Vector3.new(0.9, 0.8, 0.9), box, ROCK, true)
		end, { solid = true })
	end
	for k = 1, 16 do
		local a = rng:NextNumber(0, 2 * math.pi)
		local p = barren + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(0, 28)
		local g = floorAt(p.X, p.Z)
		local width = rng:NextNumber(6, 10)
		local size = Vector3.new(1, 0.66, 0.98) * width
		local box = Kit.standing(g, rng:NextNumber(0, 6.28), size, 0.12)
		local _, dressed = Kit.hero(stats, m, "UrchinRock", box, size, function(sm)
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
		quiet(dressed)
	end
	for _ = 1, 4 do
		local a = rng:NextNumber(0, 2 * math.pi)
		local p = ground + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(10, MEADOW.spread + 20)
		starfish(m, floorAt(p.X, p.Z), rng:NextNumber(3, 4.5))
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
	buoyHolder:SetAttribute("Bob", 0.25)
	CollectionService:AddTag(buoyHolder, "Bobbing")
	Kit.rod(
		stats,
		m,
		"BuoyLine",
		-- (into the float's body, past its eyelet: see the cathedral's buoy)
		Vector3.new(b.X, World.surfaceY - buoyHeight * 0.35, b.Z),
		floor + Vector3.new(0, 2, 0),
		0.25,
		IRON,
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
		from = ground + Vector3.new(side.Z, 0, -side.X) * 46 - side * 6 + Vector3.new(0, 15, 0),
		to = ground + side * 36 + Vector3.new(0, 3, 0),
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
		-- (sea grass round each)
		grassPatch(m, g, 10, 3, 3.5, 6.5)
		r += TRAIL.step + rng:NextNumber(-8, 8)
	end
end

-- The rest of the Kelp Shallows' floor: patches of sea grass between the forests,
-- some with an urchin rock or a starfish, clear of the landmarks
local function floorFill(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "KelpFloor"
	m.Parent = parent
	local keep = {
		{ at = at(CATHEDRAL.angle, CATHEDRAL.r), radius = CATHEDRAL.nave + 30 },
		{ at = at(MEADOW.angle, MEADOW.r), radius = MEADOW.spread + 40 },
	}
	for k = 1, FLOOR.patches do
		local spot = at(rng:NextNumber(0, 360), rng:NextNumber(FLOOR.from, FLOOR.to))
		local clear = true
		for _, area in keep do
			if Vector3.new(spot.X - area.at.X, 0, spot.Z - area.at.Z).Magnitude < area.radius then
				clear = false
			end
		end
		if not clear then
			continue
		end
		local g = floorAt(spot.X, spot.Z)
		grassPatch(m, g, rng:NextNumber(10, 16), rng:NextInteger(3, 5), 3.5, 7)
		if k % 3 == 0 then
			local p = g + Vector3.new(rng:NextNumber(-10, 10), 0, rng:NextNumber(-10, 10))
			urchinRock(m, floorAt(p.X, p.Z), rng:NextNumber(7, 12))
		elseif k % 2 == 0 then
			local p = g + Vector3.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-12, 12))
			starfish(m, floorAt(p.X, p.Z), rng:NextNumber(2.8, 4.2))
		end
	end
end

-- Builds the Kelp Shallows' landmarks: the cathedral's kelp into `kelpFolder` (so it
-- sways), the rest into `parent`. Returns what it made.
function KelpDress.build(kelpFolder: Instance, parent: Instance, ground: Kit.Ground): Kit.Stats
	stats = Kit.stats()
	groundOf = ground
	rng = Random.new(World.seed + 1310)
	placed = 0
	table.clear(KelpDress.views)
	cathedral(kelpFolder, parent)
	meadow(parent)
	litterTrail(parent)
	floorFill(parent)
	return stats
end

return KelpDress
