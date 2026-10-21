--!strict
-- The Coral Reef's landmarks (owner, 2026-10-21, the approved board
-- assets/concepts/biome_detail/BoardReef.jpg: "The Blue Hole"; then "look how much
-- different your hole looks from the mockup": rebuilt to read like its scene,
-- assets/tripo/biome_concepts/ReefScene.png):
--
--   * THE BLUE HOLE (Config/Places BlueHole): the wide sinkhole Shelf.luau sinks
--     through the reef (Features.blueHole: sheer walls stepping down in bands with
--     ledges and overhangs, a pale stone lip, a tunnel from its floor out through the
--     drop-off). Its rim is a raised reef three rows deep in colour districts, as the
--     scene has them seen from the highway: fire corals (red and orange tables, fans,
--     tubes and domes) on the left, blue and violet on the right, yellow and green
--     across the far side; plate corals step down its ledges, a glow lights its floor
--     and a line of glowing anemones leads through the tunnel;
--   * THE HIGHWAY: a sandy road winding up to the rim between walls of reef (rock
--     mounds Shelf laid, packed with coral rows rising away from the sand), its sand
--     rippled, a clam with a glowing pearl and garden eels beside it, light shafts;
--   * THE CLAM GARDEN (ClamGarden): giant clams lying open on the sand inside a ring of
--     coral, each with a glowing pearl a fish can bite out (LandmarkService pays it and
--     it regrows for that fish; `ReefDress.pearls`);
--   * garden eel patches duck into the sand as a fish passes (the client's
--     LandmarksController, tag `GardenEels`).
--
-- The models (biome_reef_glb: TableCoral, GiantClam, GardenEels, PillarCoral;
-- biome_reef2_glb: DomeCoral and BranchFan in their colourways and the Table and
-- Pillar colourways, tools/props/coral_colorways.py; and the older corals and cliff
-- growth) go over part-built stand-ins (LandmarkKit.hero); the hard corals and the
-- clams are solid.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Kit = require(script.Parent.LandmarkKit)
local PlaceMarks = require(script.Parent.PlaceMarks)

local ReefDress = {}

export type View = { name: string, from: Vector3, to: Vector3, fov: number }
export type Hole = {
	center: Vector3,
	radius: number,
	bottom: number,
	bands: { { top: number, bottom: number, out: number } },
	path: { Vector3 },
	halfWidth: number,
	tunnel: { from: Vector3, to: Vector3, radius: number },
	ledges: { CFrame },
}
export type Rock = { center: Vector3, radius: number }

ReefDress.views = {} :: { View }
-- The clams' pearls (LandmarkService checks a bite against them)
ReefDress.pearls = {} :: { Vector3 }

local World = Config.World
local GARDEN = { angle = 320, r = 660, clams = 7, spread = 30 }
-- (the most models the Blue Hole and its highway place; the Clam Garden its own)
local HOLE_CAP = 950
local GARDEN_CAP = 260

local FIRE = Color3.fromRGB(240, 90, 50)
local ORANGE = Color3.fromRGB(250, 140, 40)
local BLUE = Color3.fromRGB(60, 110, 230)
local VIOLET = Color3.fromRGB(140, 90, 225)
local YELLOW = Color3.fromRGB(240, 196, 50)
local GREEN = Color3.fromRGB(70, 180, 70)
local ROAD = Color3.fromRGB(206, 182, 130)
local CREST = Color3.fromRGB(226, 208, 162)
local GROOVE = Color3.fromRGB(162, 132, 88)
local SHELL = Color3.fromRGB(70, 110, 170)
local PEARL = Color3.fromRGB(255, 236, 170)
local DEEP = Color3.fromRGB(80, 160, 255)

-- A coral kind: its model, its shape (length along its front, height, width, for a
-- height of 1, from the model's own box), its stand-in colour and whether fish bump it
type Growth = { name: string, shape: Vector3, color: Color3, solid: boolean }
local function g(name: string, x: number, z: number, color: Color3, solid: boolean): Growth
	return { name = name, shape = Vector3.new(x, 1, z), color = color, solid = solid }
end
local KINDS = {
	TableOrange = g("TableCoralOrange", 0.93, 1.25, ORANGE, true),
	TableRed = g("TableCoralRed", 0.93, 1.25, FIRE, true),
	TableBlue = g("TableCoralBlue", 0.93, 1.25, BLUE, true),
	TableViolet = g("TableCoralViolet", 0.93, 1.25, VIOLET, true),
	DomeRed = g("DomeCoralRed", 1.77, 1.78, FIRE, true),
	DomeOrange = g("DomeCoralOrange", 1.77, 1.78, ORANGE, true),
	DomeYellow = g("DomeCoralYellow", 1.77, 1.78, YELLOW, true),
	DomeGreen = g("DomeCoralGreen", 1.77, 1.78, GREEN, true),
	FanRed = g("BranchFanRed", 0.49, 1.1, FIRE, false),
	FanOrange = g("BranchFanOrange", 0.49, 1.1, ORANGE, false),
	FanYellow = g("BranchFanYellow", 0.49, 1.1, YELLOW, false),
	FanViolet = g("BranchFanViolet", 0.49, 1.1, VIOLET, false),
	PillarViolet = g("PillarCoral", 0.72, 0.77, VIOLET, true),
	PillarOrange = g("PillarCoralOrange", 0.72, 0.77, ORANGE, true),
	PillarBlue = g("PillarCoralBlue", 0.72, 0.77, BLUE, true),
	Staghorn = g("StaghornCoral", 0.66, 0.94, YELLOW, true),
	LaceFan = g("LaceFan", 0.43, 1.11, BLUE, false),
	Barrel = g("BarrelSponge", 0.81, 0.78, VIOLET, true),
	Whips = g("SeaWhips", 0.8, 0.78, YELLOW, false),
	Weed = g("KelpClump", 0.56, 0.57, GREEN, false),
	Anemone = g("Anemone", 0.82, 0.86, ORANGE, false),
	Plate = g("PlateCoral", 1.63, 1.53, Color3.fromRGB(80, 200, 190), true),
	Brain = g("BrainCoral", 1.15, 1.26, ORANGE, true),
}

-- The highway's walls, rows out from the road's edge (studs past its half width), how
-- many a stretch and how big, rising away from the sand (the front row is the scene's
-- big brain corals and anemones along the sand, whatever the side)
local WALL_ROWS: { { off: number, per: number, scale: number, district: string? } } = {
	{ off = 1.5, per = 2, scale = 0.9, district = "edge" },
	{ off = 6, per = 2, scale = 0.8 },
	{ off = 12, per = 1, scale = 1.0 },
	{ off = 19, per = 1, scale = 1.2 },
	{ off = 27, per = 1, scale = 1.35 },
	{ off = 36, per = 1, scale = 1.45 },
}

-- The districts round the hole and down the highway's sides, as the scene has them
-- seen from the highway: kinds by weight, and how tall each grows (studs, low and
-- high) in a row's own scale
type Pick = { kind: Growth, weight: number, height: { number } }
local function pick(kind: Growth, weight: number, low: number, high: number): Pick
	return { kind = kind, weight = weight, height = { low, high } }
end
local DISTRICTS: { [string]: { Pick } } = {
	fire = {
		pick(KINDS.TableOrange, 3, 11, 18),
		pick(KINDS.TableRed, 1, 10, 16),
		pick(KINDS.FanRed, 3, 9, 16),
		pick(KINDS.FanOrange, 2, 8, 14),
		pick(KINDS.PillarOrange, 3, 7, 12),
		pick(KINDS.DomeRed, 2, 5, 8),
		pick(KINDS.DomeOrange, 1, 5, 8),
		pick(KINDS.Anemone, 1, 3, 5),
	},
	blue = {
		pick(KINDS.TableBlue, 3, 10, 17),
		pick(KINDS.TableViolet, 2, 9, 15),
		pick(KINDS.PillarViolet, 3, 8, 14),
		pick(KINDS.PillarBlue, 3, 7, 13),
		pick(KINDS.FanViolet, 2, 8, 14),
		pick(KINDS.LaceFan, 1, 8, 13),
		pick(KINDS.Barrel, 1, 6, 10),
	},
	gold = {
		pick(KINDS.DomeYellow, 3, 5, 9),
		pick(KINDS.DomeGreen, 3, 5, 9),
		pick(KINDS.FanYellow, 2, 8, 13),
		pick(KINDS.Whips, 2, 7, 12),
		pick(KINDS.Weed, 2, 7, 12),
		pick(KINDS.Staghorn, 1, 6, 10),
		pick(KINDS.Plate, 1, 5, 8),
	},
	edge = {
		pick(KINDS.DomeYellow, 3, 5, 8),
		pick(KINDS.DomeGreen, 3, 5, 8),
		pick(KINDS.DomeRed, 2, 5, 8),
		pick(KINDS.DomeOrange, 1, 4, 7),
		pick(KINDS.Anemone, 2, 3, 5),
		pick(KINDS.FanYellow, 1, 5, 8),
	},
}

local stats: Kit.Stats = Kit.stats()
local groundOf: Kit.Ground = function(_x: number, _z: number): (Vector3?, Vector3?)
	return nil, nil
end
local rng = Random.new(World.seed + 1410)
local placed = 0

local function at(angle: number, r: number): Vector3
	local a = math.rad(angle)
	return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

local function floorAt(x: number, z: number): Vector3
	local hit = groundOf(x, z)
	return hit or Vector3.new(x, Seafloor.y(x, z), z)
end

local function choose(list: { Pick }): Pick
	local total = 0
	for _, p in list do
		total += p.weight
	end
	local roll = rng:NextNumber(0, total)
	for _, p in list do
		roll -= p.weight
		if roll <= 0 then
			return p
		end
	end
	return list[#list]
end

-- A coral standing on `ground`, `height` tall (`yaw` its turn, random if nil)
local function coral(
	parent: Instance,
	growth: Growth,
	ground: Vector3,
	height: number,
	yaw: number?,
	cap: number?
)
	if placed >= (cap or HOLE_CAP) then
		return
	end
	placed += 1
	local size = growth.shape * height
	local box = Kit.standing(ground, yaw or rng:NextNumber(0, 6.28), size, 0.06)
	Kit.hero(stats, parent, growth.name, box, size, function(m)
		local piece =
			Kit.part(stats, m, "Coral", size * Vector3.new(0.7, 0.85, 0.7), box, growth.color, growth.solid)
		piece.CastShadow = false
	end, { solid = growth.solid })
end

-- One of a district's kinds at `ground`, scaled by the row (`scale`)
local function grow(parent: Instance, district: string, ground: Vector3, scale: number, cap: number?)
	local p = choose(DISTRICTS[district])
	coral(parent, p.kind, ground, rng:NextNumber(p.height[1], p.height[2]) * scale, nil, cap)
end

-- The highway's sand, smooth and rippled as the scene draws it (the toon Sand's plates
-- read as paving under a road): a pale carpet over each stretch (the road's sand is
-- level at the shelf's top, Shelf cut it so), then wavy ripple lines across it, each
-- a dark groove with a lit crest beside it, in three kinked thirds
local function road(parent: Instance, from: Vector3, to: Vector3, width: number, spacing: number)
	local along = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = along.Magnitude
	if length < 1 then
		return
	end
	along = along.Unit
	local middle = (from + to) / 2
	local base = floorAt(middle.X, middle.Z)
	local frame = CFrame.lookAt(
		Vector3.new(middle.X, base.Y, middle.Z),
		Vector3.new(middle.X, base.Y, middle.Z) + along
	)
	local carpet = Kit.part(
		stats,
		parent,
		"Road",
		Vector3.new(width, 0.4, length + 1.5),
		frame * CFrame.new(0, 0.1, 0),
		ROAD,
		false
	)
	carpet.CastShadow = false
	local n = math.floor(length / spacing)
	for k = 0, n - 1 do
		local centre = frame * CFrame.new(0, 0, -(k + 0.5) * spacing + length / 2)
		local phase = rng:NextNumber(0, 6.28)
		local swing = rng:NextNumber(0.8, 1.6)
		local pieces = 5
		local seg = width / pieces
		for i = 1, pieces do
			-- (a wave across the road: each piece turned along the curve)
			local x = (i - 0.5) / pieces * width - width / 2
			local z = math.sin(phase + x * 0.22) * swing
			local slope = math.cos(phase + x * 0.22) * swing * 0.22
			local piece = centre * CFrame.new(x, 0, z) * CFrame.Angles(0, -math.atan(slope), 0)
			local groove = Kit.part(
				stats,
				parent,
				"Groove",
				Vector3.new(seg + 0.3, 0.06, 0.32),
				piece * CFrame.new(0, 0.33, 0),
				GROOVE,
				false
			)
			groove.CastShadow = false
			local crest = Kit.part(
				stats,
				parent,
				"Crest",
				Vector3.new(seg + 0.3, 0.06, 0.4),
				piece * CFrame.new(0, 0.33, 0.42),
				CREST,
				false
			)
			crest.CastShadow = false
		end
	end
end

local function eels(parent: Instance, ground: Vector3, width: number)
	local size = Vector3.new(1, 0.73, 1) * width
	local box = Kit.standing(ground, rng:NextNumber(0, 6.28), size, 0.3)
	local holder = Kit.hero(stats, parent, "GardenEels", box, size, function(sm)
		for e = 1, 5 do
			Kit.part(
				stats,
				sm,
				"Eel",
				Vector3.new(0.5, width * 0.5, 0.5),
				CFrame.new(ground + Vector3.new((e - 3) * 1.6, width * 0.2, (e % 2) * 1.4)),
				Color3.fromRGB(190, 170, 90),
				false
			)
		end
	end)
	CollectionService:AddTag(holder, "GardenEels")
end

-- A giant clam lying open on `ground`, facing `yaw`, with its glowing pearl
local function clam(parent: Instance, ground: Vector3, yaw: number, width: number)
	local size = Vector3.new(0.8, 0.87, 1) * width
	local box = Kit.standing(ground, yaw, size, 0.08)
	Kit.hero(stats, parent, "GiantClam", box, size, function(sm)
		for side = -1, 1, 2 do
			Kit.part(
				stats,
				sm,
				"Shell",
				Vector3.new(size.X * 0.9, 1.2, size.Z),
				box
					* CFrame.new(0, -size.Y * 0.2 + side * size.Y * 0.18, 0)
					* CFrame.Angles(side * 0.35, 0, 0),
				SHELL,
				true
			)
		end
	end, { solid = true })
	-- Its pearl (a glowing bead over the model's own; LandmarkService pays it)
	local pearl = box:PointToWorldSpace(Vector3.new(0, -size.Y * 0.12, 0))
	local bead = Kit.glow(
		stats,
		parent,
		"Pearl",
		Vector3.one * width * 0.2,
		CFrame.new(pearl),
		PEARL,
		Enum.PartType.Ball
	)
	bead:SetAttribute("Pearl", #ReefDress.pearls + 1)
	CollectionService:AddTag(bead, "ClamPearl")
	table.insert(ReefDress.pearls, pearl)
	PlaceMarks.set(`Pearl{#ReefDress.pearls}`, pearl)
end

-- Which district a point round the hole is in: the highway comes in from `entry`
-- (a unit vector from the middle); looking in from it, fire on the left, blue and
-- violet on the right, yellow and green across the far side
local function districtOf(center: Vector3, entry: Vector3, point: Vector3): string
	local d = Vector3.new(point.X - center.X, 0, point.Z - center.Z).Unit
	local cosine = d:Dot(entry)
	if cosine < -0.35 then
		return "gold"
	end
	-- (looking in, the left hand is entry × up turned: right = (-f.Z, 0, f.X) with f = -entry)
	local right = Vector3.new(entry.Z, 0, -entry.X)
	return if d:Dot(right) > 0 then "blue" else "fire"
end

local function blueHole(parent: Instance, hole: Hole)
	local m = Instance.new("Model")
	m.Name = "BlueHole"
	m.Parent = parent
	local center = hole.center
	local R = hole.radius
	local path = hole.path
	local hw = hole.halfWidth
	local entry = Vector3.new(path[1].X - center.X, 0, path[1].Z - center.Z).Unit
	Kit.clearing(stats, center, R + 46)
	for k = 1, #path, 3 do
		Kit.clearing(stats, path[k], hw + 34)
	end

	-- The rim: three rows, small growth on the lip, taller rows behind on the mounds
	local reef = Instance.new("Model")
	reef.Name = "Rim"
	reef.Parent = m
	for _, row in
		{
			{ r = R + 7, step = 7, scale = 0.6 },
			{ r = R + 18, step = 8, scale = 0.9 },
			{ r = R + 31, step = 8.5, scale = 1.15 },
		}
	do
		local count = math.floor(2 * math.pi * row.r / row.step)
		for k = 1, count do
			local angle = k / count * 2 * math.pi + rng:NextNumber(-0.02, 0.02)
			local p = center
				+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * (row.r + rng:NextNumber(-2.5, 2.5))
			local nearest = math.huge
			for _, point in path do
				nearest = math.min(nearest, Vector3.new(p.X - point.X, 0, p.Z - point.Z).Magnitude)
			end
			if nearest < hw + 1.5 then
				continue -- (the highway)
			end
			local ground = floorAt(p.X, p.Z)
			if ground.Y > -6 then
				grow(reef, districtOf(center, entry, p), ground, row.scale)
			end
		end
	end

	-- The highway's walls: rows rising away from the sand, fire on the left going in
	-- and blue and violet on the right, a little yellow and green in both
	local walls = Instance.new("Model")
	walls.Name = "Highway"
	walls.Parent = m
	for k = 2, #path do
		local here, back = path[k], path[k - 1]
		local inward = Vector3.new(back.X - here.X, 0, back.Z - here.Z).Unit
		local right = Vector3.new(-inward.Z, 0, inward.X)
		for _, sign in { -1, 1 } do
			local district = if sign > 0 then "blue" else "fire"
			for _, row in WALL_ROWS do
				for n = 1, row.per do
					local p = here
						+ right * sign * (hw + row.off + rng:NextNumber(-2, 2))
						+ inward * ((n - 0.5) / row.per * 8 - 4 + rng:NextNumber(-1.5, 1.5))
					local d = row.district or if rng:NextNumber() < 0.2 then "gold" else district
					grow(walls, d, floorAt(p.X, p.Z), row.scale)
				end
			end
		end
	end

	-- The road's sand: ripples down the middle, a clam and eels beside it
	local sand = Instance.new("Model")
	sand.Name = "Sand"
	sand.Parent = m
	for k = 2, #path do
		road(sand, path[k - 1], path[k], hw * 2 + 2, 3.2)
	end
	local clamAt = math.min(5, #path)
	do
		local here, back = path[clamAt], path[clamAt - 1]
		local inward = Vector3.new(back.X - here.X, 0, back.Z - here.Z).Unit
		local left = Vector3.new(inward.Z, 0, -inward.X)
		local spot = here + left * (hw - 4)
		clam(sand, floorAt(spot.X, spot.Z), math.atan2(-left.X, -left.Z) + math.pi, 9)
		for e = 1, 2 do
			local q = here + left * (hw - 7) - inward * (e * 7)
			eels(sand, floorAt(q.X, q.Z), 7)
		end
		local q = here - left * (hw - 4) + inward * 10
		eels(sand, floorAt(q.X, q.Z), 8)
	end

	-- Plate corals stepping down the walls: on every ledge Shelf left, and jutting
	-- from under the rim's overhang
	local wall = Instance.new("Model")
	wall.Name = "Wall"
	wall.Parent = m
	for i, ledge in hole.ledges do
		for j = 1, 3 do
			local spot = ledge * CFrame.new((j - 2) * 8 + rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-2, 4))
			local kind = if (i + j) % 3 == 0
				then KINDS.TableBlue
				elseif (i + j) % 3 == 1 then KINDS.Plate
				else KINDS.Whips
			coral(wall, kind, spot.Position, rng:NextNumber(5, 9))
		end
	end
	for k = 1, 16 do
		local angle = k / 16 * 2 * math.pi + rng:NextNumber(-0.1, 0.1)
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local y = -15 - rng:NextNumber(0, 18)
		local w = Vector3.new(center.X, y, center.Z) + out * (R + 10)
		local width = rng:NextNumber(9, 14)
		local size = Vector3.new(1.63, 1, 1.53) * width * 0.6
		local frame = CFrame.lookAt(w, w - out)
		Kit.hero(
			stats,
			wall,
			"PlateCoral",
			frame * CFrame.new(0, 0, -size.X * 0.25) * Kit.GLB_FRONT,
			size,
			function(sm)
				Kit.part(
					stats,
					sm,
					"Plate",
					Vector3.new(width, 1.2, width * 0.8),
					frame * CFrame.new(0, 0, -width * 0.35),
					if k % 2 == 0 then VIOLET else Color3.fromRGB(80, 200, 190),
					true
				)
			end,
			{ solid = true }
		)
	end

	-- Light down into it, and a glow on its floor so it reads as deep, not empty
	local surface = World.surfaceY - 2
	for k = 1, 4 do
		local offset = Vector3.new(math.cos(k * 1.6) * R * 0.45, 0, math.sin(k * 1.6) * R * 0.45)
		Kit.shaft(
			m,
			Vector3.new(center.X, surface, center.Z) + offset,
			center + offset * 1.2 + Vector3.new(0, -60, 0),
			26 + k * 4,
			0.3
		)
	end
	local bottom = Vector3.new(center.X, hole.bottom, center.Z)
	for k = 1, 9 do
		local p = bottom + Vector3.new(math.cos(k * 0.7) * (16 + k * 4), 1, math.sin(k * 0.7) * (16 + k * 4))
		Kit.glow(
			stats,
			m,
			"DeepAnemone",
			Vector3.new(0.6, 3.4, 3.4),
			CFrame.new(p) * CFrame.Angles(0, 0, math.rad(90)),
			DEEP,
			Enum.PartType.Cylinder
		)
	end
	local glow = Kit.anchor(m, "HoleGlow", CFrame.new(bottom + Vector3.new(0, 18, 0)))
	Kit.light(stats, glow, DEEP, 60, 1.3)

	-- The tunnel out: glowing anemones down its floor every so often, a light at each end
	local tunnel = hole.tunnel
	local run = tunnel.to - tunnel.from
	local steps = math.floor(run.Magnitude / 26)
	for k = 0, steps do
		local p = tunnel.from + run * (k / math.max(steps, 1)) + Vector3.new(0, -tunnel.radius + 1.2, 0)
		Kit.glow(
			stats,
			m,
			"TunnelGlow",
			Vector3.new(0.6, 2.6, 2.6),
			CFrame.new(p) * CFrame.Angles(0, 0, math.rad(90)),
			DEEP,
			Enum.PartType.Cylinder
		)
	end
	for _, p in { tunnel.from, tunnel.to } do
		local a = Kit.anchor(m, "TunnelLight", CFrame.new(p))
		Kit.light(stats, a, DEEP, 40, 1)
	end

	PlaceMarks.set("BlueHole", center + Vector3.new(0, 14, 0))
	-- The scene's camera: over the highway ~90 studs back from the rim, looking down
	-- into the hole at about the scene's angle (its far wall filling the opening)
	local eye = path[math.min(#path, 9)]
	local look = center + entry * -R * 0.1 + Vector3.new(0, -55, 0)
	table.insert(ReefDress.views, {
		name = "bluehole",
		from = floorAt(eye.X, eye.Z) + Vector3.new(0, 46, 0),
		to = look,
		fov = 72,
	})
	table.insert(ReefDress.views, {
		name = "holeabove",
		from = center + entry * (R + 70) + Vector3.new(0, 70, 0),
		to = center + Vector3.new(0, -40, 0),
		fov = 72,
	})
	table.insert(ReefDress.views, {
		name = "holedown",
		from = center + Vector3.new(6, -30, 0),
		to = Vector3.new(center.X, hole.bottom, center.Z) + Vector3.new(14, 0, 0),
		fov = 76,
	})
end

-- The most open spot near the garden's (clear of the reef heads and outcrops)
local function openSpot(angle0: number, r0: number, rocks: { Rock }): Vector3
	local best, bestRoom = at(angle0, r0), -math.huge
	for angle = angle0 - 20, angle0 + 20, 4 do
		for r = r0 - 60, r0 + 60, 20 do
			local spot = at(angle, r)
			local room = math.huge
			for _, rock in rocks do
				local dx, dz = rock.center.X - spot.X, rock.center.Z - spot.Z
				room = math.min(room, math.sqrt(dx * dx + dz * dz) - rock.radius)
			end
			if room > bestRoom then
				best, bestRoom = spot, room
			end
		end
	end
	return best
end

local function clamGarden(parent: Instance, rocks: { Rock })
	local center = openSpot(GARDEN.angle, GARDEN.r, rocks)
	local ground = floorAt(center.X, center.Z)
	local m = Instance.new("Model")
	m.Name = "ClamGarden"
	m.Parent = parent
	Kit.clearing(stats, ground, GARDEN.spread + 36)
	placed = 0
	local clams: { Vector3 } = {}
	for k = 1, GARDEN.clams do
		local angle = k / GARDEN.clams * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local p = ground + Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(8, GARDEN.spread)
		clam(m, floorAt(p.X, p.Z), angle + math.pi, rng:NextNumber(9, 13))
		table.insert(clams, p)
	end
	-- (tufts between the clams: brain corals, anemones and little fans on the sand)
	for _ = 1, 22 do
		local a, d = rng:NextNumber(0, 2 * math.pi), rng:NextNumber(4, GARDEN.spread + 2)
		local p = ground + Vector3.new(math.cos(a), 0, math.sin(a)) * d
		local clear = true
		for _, c in clams do
			if Vector3.new(p.X - c.X, 0, p.Z - c.Z).Magnitude < 9 then
				clear = false
			end
		end
		if clear then
			grow(m, "edge", floorAt(p.X, p.Z), 0.55, GARDEN_CAP)
		end
	end
	local glow = Kit.anchor(m, "GardenGlow", CFrame.new(ground + Vector3.new(0, 10, 0)))
	Kit.light(stats, glow, PEARL, 30, 0.9)
	-- A ring of reef round the clams, every district in it, and eels between
	local districts = { "fire", "gold", "blue" }
	for _, row in
		{
			{ r = GARDEN.spread + 7, step = 6, scale = 0.7, district = "edge" },
			{ r = GARDEN.spread + 16, step = 7, scale = 1.0 },
			{ r = GARDEN.spread + 27, step = 8, scale = 1.3 },
		} :: { { r: number, step: number, scale: number, district: string? } }
	do
		local count = math.floor(2 * math.pi * row.r / row.step)
		for k = 1, count do
			local angle = k / count * 2 * math.pi
			local p = ground
				+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * (row.r + rng:NextNumber(-3, 3))
			grow(
				m,
				row.district or districts[math.floor(k / count * 3) % 3 + 1],
				floorAt(p.X, p.Z),
				row.scale,
				GARDEN_CAP
			)
		end
	end
	for k = 1, 4 do
		local p = ground + Vector3.new(math.cos(k * 1.7), 0, math.sin(k * 1.7)) * (GARDEN.spread + 1)
		eels(m, floorAt(p.X, p.Z), 9)
	end
	PlaceMarks.set("ClamGarden", ground + Vector3.new(0, 12, 0))
	local out = Vector3.new(math.cos(math.rad(GARDEN.angle)), 0, math.sin(math.rad(GARDEN.angle)))
	table.insert(ReefDress.views, {
		name = "clams",
		from = ground - out * 80 + Vector3.new(0, 30, 0),
		to = ground + Vector3.new(0, 2, 0),
		fov = 66,
	})
end

-- Builds the Coral Reef's landmarks (`hole` from Shelf's Features). Returns what it made.
function ReefDress.build(parent: Instance, ground: Kit.Ground, hole: Hole?, rocks: { Rock }?): Kit.Stats
	stats = Kit.stats()
	groundOf = ground
	rng = Random.new(World.seed + 1410)
	placed = 0
	table.clear(ReefDress.views)
	table.clear(ReefDress.pearls)
	if hole then
		blueHole(parent, hole)
	end
	clamGarden(parent, rocks or {})
	return stats
end

return ReefDress
