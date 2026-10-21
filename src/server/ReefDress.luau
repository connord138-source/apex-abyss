--!strict
-- The Coral Reef's landmarks (owner, 2026-10-21, the approved board
-- assets/concepts/biome_detail/BoardReef.jpg: "The Blue Hole"):
--
--   * THE BLUE HOLE (Config/Places BlueHole): the sinkhole Shelf.luau sinks through
--     the reef's sand (Features.blueHole), its rim a ring of coral in three colour
--     districts (fire corals one side, blue and violet the other, yellow and green
--     between), plate corals jutting from its wall going down, a faint glow at the
--     bottom;
--   * THE CLAM GARDEN (ClamGarden): giant clams lying open on the sand, each with a
--     glowing pearl a fish can bite out (LandmarkService pays it and it regrows for
--     that fish; `ReefDress.pearls`);
--   * garden eel patches that duck into the sand as a fish passes (the client's
--     LandmarksController, tag `GardenEels`), table and pillar corals round the hole.
--
-- The models (biome_reef_glb: TableCoral, GiantClam, GardenEels, PillarCoral, and the
-- older corals and cliff growth) go over part-built stand-ins (LandmarkKit.hero);
-- the hard corals and the clams are solid.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Kit = require(script.Parent.LandmarkKit)
local PlaceMarks = require(script.Parent.PlaceMarks)

local ReefDress = {}

export type View = { name: string, from: Vector3, to: Vector3, fov: number }
export type Hole = { center: Vector3, radius: number, bottom: number }
export type Rock = { center: Vector3, radius: number }

ReefDress.views = {} :: { View }
-- The clams' pearls (LandmarkService checks a bite against them)
ReefDress.pearls = {} :: { Vector3 }

local World = Config.World
local GARDEN = { angle = 320, r = 660, clams = 7, spread = 30 }
local GLB_FRONT = Kit.GLB_FRONT

local FIRE = Color3.fromRGB(255, 120, 60)
local VIOLET = Color3.fromRGB(150, 100, 230)
local LIME = Color3.fromRGB(200, 220, 70)
local SAND = Color3.fromRGB(200, 190, 150)
local SHELL = Color3.fromRGB(70, 110, 170)
local PEARL = Color3.fromRGB(255, 236, 170)
local DEEP = Color3.fromRGB(80, 160, 255)

-- The rim's districts (degrees round the hole) and what grows in each: a model, its
-- shape (x, y, z for a height of 1) and a stand-in colour
type Growth = { name: string, shape: Vector3, color: Color3, solid: boolean }
local DISTRICTS: { { from: number, growth: { Growth } } } = {
	{
		from = 0,
		growth = {
			{ name = "TableCoral", shape = Vector3.new(0.92, 1, 1.25), color = FIRE, solid = true },
			{ name = "BrainCoral", shape = Vector3.new(1.15, 1, 1.15), color = FIRE, solid = true },
			{ name = "StaghornCoral", shape = Vector3.new(1.1, 1, 1.1), color = FIRE, solid = true },
		},
	},
	{
		from = 120,
		growth = {
			{ name = "PillarCoral", shape = Vector3.new(0.72, 1, 0.77), color = VIOLET, solid = true },
			{ name = "BarrelSponge", shape = Vector3.new(0.8, 1, 0.8), color = VIOLET, solid = true },
			{ name = "LaceFan", shape = Vector3.new(0.3, 1, 1), color = VIOLET, solid = false },
		},
	},
	{
		from = 240,
		growth = {
			{ name = "SeaWhips", shape = Vector3.new(0.8, 1, 0.8), color = LIME, solid = false },
			{ name = "FanCoral", shape = Vector3.new(0.4, 1, 1), color = LIME, solid = false },
			{ name = "TubeSponge", shape = Vector3.new(0.8, 1, 0.8), color = LIME, solid = true },
		},
	},
}

local stats: Kit.Stats = Kit.stats()
local groundOf: Kit.Ground = function(_x: number, _z: number): (Vector3?, Vector3?)
	return nil, nil
end
local rng = Random.new(World.seed + 1410)

local function at(angle: number, r: number): Vector3
	local a = math.rad(angle)
	return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

local function floorAt(x: number, z: number): Vector3
	local hit = groundOf(x, z)
	return hit or Vector3.new(x, Seafloor.y(x, z), z)
end

-- A coral standing on `ground`, `height` tall
local function coral(parent: Instance, growth: Growth, ground: Vector3, height: number)
	local size = growth.shape * height
	local box = Kit.standing(ground, rng:NextNumber(0, 6.28), size, 0.06)
	Kit.hero(stats, parent, growth.name, box, size, function(m)
		Kit.part(stats, m, "Coral", size * Vector3.new(0.7, 0.85, 0.7), box, growth.color, growth.solid)
	end, { solid = growth.solid })
end

local function blueHole(parent: Instance, hole: Hole)
	local m = Instance.new("Model")
	m.Name = "BlueHole"
	m.Parent = parent
	local center = hole.center
	Kit.clearing(stats, center, hole.radius + 30)
	-- The rim: three districts round it, two rings deep
	for _, ringR in { hole.radius + 12, hole.radius + 26 } do
		local count = math.floor(ringR * 2 * math.pi / 13)
		for i = 1, count do
			local deg = i / count * 360 + rng:NextNumber(-4, 4)
			local district = DISTRICTS[1]
			for _, d in DISTRICTS do
				if deg >= d.from then
					district = d
				end
			end
			local growth = district.growth[rng:NextInteger(1, #district.growth)]
			local p = center
				+ Vector3.new(math.cos(math.rad(deg)), 0, math.sin(math.rad(deg)))
					* (ringR + rng:NextNumber(-3, 4))
			local g = floorAt(p.X, p.Z)
			if g.Y > -20 then -- (on the rim's sand, not down the hole)
				coral(m, growth, g, rng:NextNumber(5, 11) * (if ringR > hole.radius + 20 then 1.2 else 1))
			end
		end
	end
	-- Plate corals jutting from the wall on the way down, facing into the hole
	for level = 1, 4 do
		local y = -18 - level * 38
		for k = 1, 6 do
			local deg = k * 60 + level * 23
			local out = Vector3.new(math.cos(math.rad(deg)), 0, math.sin(math.rad(deg)))
			local wall = Vector3.new(center.X, y, center.Z) + out * (hole.radius - 3)
			local width = rng:NextNumber(10, 16)
			local size = Vector3.new(1, 0.55, 1.1) * width
			local frame = CFrame.lookAt(wall, wall - out)
			local box = frame * CFrame.new(0, 0, -size.X * 0.3) * GLB_FRONT
			Kit.hero(stats, m, "PlateCoral", box, size, function(sm)
				Kit.part(
					stats,
					sm,
					"Plate",
					Vector3.new(width, 1.2, width * 0.8),
					frame * CFrame.new(0, 0, -width * 0.35),
					if level % 2 == 0 then VIOLET else LIME,
					true
				)
			end, { solid = true })
		end
	end
	-- A faint glow down at the bottom, so the hole reads as deep, not empty
	local bottom = Vector3.new(center.X, hole.bottom, center.Z)
	for k = 1, 6 do
		local p = bottom + Vector3.new(math.cos(k) * 22, 1, math.sin(k) * 22)
		Kit.glow(
			stats,
			m,
			"DeepAnemone",
			Vector3.new(0.6, 3, 3),
			CFrame.new(p) * CFrame.Angles(0, 0, math.rad(90)),
			DEEP,
			Enum.PartType.Cylinder
		)
	end
	local glow = Kit.anchor(m, "HoleGlow", CFrame.new(bottom + Vector3.new(0, 16, 0)))
	Kit.light(stats, glow, DEEP, 60, 1.2)
	-- Garden eels on the sand round it
	for k = 1, 5 do
		local deg = k * 72 + 20
		local p = center
			+ Vector3.new(math.cos(math.rad(deg)), 0, math.sin(math.rad(deg)))
				* (hole.radius + rng:NextNumber(42, 70))
		local g = floorAt(p.X, p.Z)
		local width = rng:NextNumber(9, 13)
		local size = Vector3.new(1, 0.73, 1) * width
		local box = Kit.standing(g, rng:NextNumber(0, 6.28), size, 0.3)
		local holder = Kit.hero(stats, m, "GardenEels", box, size, function(sm)
			for e = 1, 5 do
				Kit.part(
					stats,
					sm,
					"Eel",
					Vector3.new(0.5, width * 0.5, 0.5),
					CFrame.new(g + Vector3.new((e - 3) * 1.6, width * 0.2, (e % 2) * 1.4)),
					Color3.fromRGB(190, 170, 90),
					false
				)
			end
		end)
		CollectionService:AddTag(holder, "GardenEels")
	end
	PlaceMarks.set("BlueHole", center + Vector3.new(0, 14, 0))
	table.insert(ReefDress.views, {
		name = "bluehole",
		from = center - Vector3.new(center.X, 0, center.Z).Unit * (hole.radius + 80) + Vector3.new(0, 46, 0),
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
	Kit.clearing(stats, ground, GARDEN.spread + 12)
	for k = 1, GARDEN.clams do
		local angle = k / GARDEN.clams * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local p = ground + Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(8, GARDEN.spread)
		local g = floorAt(p.X, p.Z)
		local width = rng:NextNumber(9, 13)
		local size = Vector3.new(0.8, 0.87, 1) * width
		local box = Kit.standing(g, angle + math.pi, size, 0.08)
		Kit.hero(stats, m, "GiantClam", box, size, function(sm)
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
			m,
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
	local glow = Kit.anchor(m, "GardenGlow", CFrame.new(ground + Vector3.new(0, 10, 0)))
	Kit.light(stats, glow, PEARL, 30, 0.9)
	-- Sand-coloured eel patches round it
	for k = 1, 3 do
		local p = ground + Vector3.new(math.cos(k * 2.1), 0, math.sin(k * 2.1)) * (GARDEN.spread + 18)
		local g = floorAt(p.X, p.Z)
		local size = Vector3.new(1, 0.73, 1) * 10
		local box = Kit.standing(g, k, size, 0.3)
		local holder = Kit.hero(stats, m, "GardenEels", box, size, function(sm)
			Kit.part(
				stats,
				sm,
				"Sand",
				Vector3.new(10, 1, 10),
				CFrame.new(g),
				SAND,
				false,
				Enum.PartType.Cylinder
			)
		end)
		CollectionService:AddTag(holder, "GardenEels")
	end
	PlaceMarks.set("ClamGarden", ground + Vector3.new(0, 12, 0))
	local out = Vector3.new(math.cos(math.rad(GARDEN.angle)), 0, math.sin(math.rad(GARDEN.angle)))
	table.insert(ReefDress.views, {
		name = "clams",
		from = ground - out * 60 + Vector3.new(0, 24, 0),
		to = ground + Vector3.new(0, 2, 0),
		fov = 66,
	})
end

-- Builds the Coral Reef's landmarks (`hole` from Shelf's Features). Returns what it made.
function ReefDress.build(parent: Instance, ground: Kit.Ground, hole: Hole?, rocks: { Rock }?): Kit.Stats
	stats = Kit.stats()
	groundOf = ground
	rng = Random.new(World.seed + 1410)
	table.clear(ReefDress.views)
	table.clear(ReefDress.pearls)
	if hole then
		blueHole(parent, hole)
	end
	clamGarden(parent, rocks or {})
	return stats
end

return ReefDress
