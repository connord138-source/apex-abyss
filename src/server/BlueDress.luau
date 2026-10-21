--!strict
-- The Open Blue's landmarks (owner, 2026-10-21, the approved board
-- assets/concepts/biome_detail/BoardBlue.jpg: "The Whale's Rest", the pinnacle
-- included). The Open Blue stays open water (owner, 2026-10-09): these are few and
-- far apart.
--
--   * THE WHALE'S REST (Config/Places WhalesRest): a great whale's skeleton on the
--     floor far below, a long shaft of light down onto it;
--   * HAMMERHEAD PINNACLE (HammerheadPinnacle): one tall coral-crusted spire out at the
--     sector's far edge, past the Megalodon's patrol band (so the boss never swims
--     through it), hammerheads circling it (the client's LandmarksController, from
--     PlaceMarks HammerheadPinnacle / HammerheadPinnacle_Base);
--   * golden sargassum rafts floating at the surface, small fish sheltering under them
--     (client, tag `Sargassum`), and long glowing jelly chains drifting mid-water
--     (tag `Drifting`).
--
-- The models (biome_blue_glb: WhaleSkeleton, Sargassum, JellyChain, CoralPinnacle)
-- go over part-built stand-ins (LandmarkKit.hero); only the pinnacle is solid.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Kit = require(script.Parent.LandmarkKit)
local PlaceMarks = require(script.Parent.PlaceMarks)

local BlueDress = {}

export type View = { name: string, from: Vector3, to: Vector3, fov: number }
BlueDress.views = {} :: { View }

local World = Config.World
local WHALE = { angle = 268, r = 1120, length = 120 }
local PINNACLE = { angle = 296, r = 1455, height = 240 }
local RAFTS = { count = 9, r = { 940, 1400 }, angles = { 232, 308 } }
local JELLIES = { count = 7, r = { 960, 1380 }, angles = { 234, 306 } }

local BONE = Color3.fromRGB(196, 200, 196)
local ROCK = Color3.fromRGB(96, 116, 140)
local GOLD = Color3.fromRGB(176, 140, 60)
local JELLY = Color3.fromRGB(190, 160, 255)

local stats: Kit.Stats = Kit.stats()
local groundOf: Kit.Ground = function(_x: number, _z: number): (Vector3?, Vector3?)
	return nil, nil
end
local rng = Random.new(World.seed + 1510)

local function at(angle: number, r: number): Vector3
	local a = math.rad(angle)
	return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

local function floorAt(x: number, z: number): Vector3
	local hit = groundOf(x, z)
	return hit or Vector3.new(x, Seafloor.y(x, z), z)
end

local function whalesRest(parent: Instance)
	local spot = at(WHALE.angle, WHALE.r)
	local ground = floorAt(spot.X, spot.Z)
	local m = Instance.new("Model")
	m.Name = "WhalesRest"
	m.Parent = parent
	Kit.clearing(stats, ground, WHALE.length * 0.6)
	local size = Vector3.new(0.37, 0.31, 1) * WHALE.length
	local yaw = math.rad(WHALE.angle + 70)
	local box = Kit.standing(ground, yaw, size, 0.12)
	Kit.hero(stats, m, "WhaleSkeleton", box, size, function(sm)
		-- a spine down its length and ribs arching off it
		local a = box:PointToWorldSpace(Vector3.new(0, -size.Y * 0.1, -size.Z * 0.45))
		local b = box:PointToWorldSpace(Vector3.new(0, -size.Y * 0.1, size.Z * 0.45))
		Kit.rod(stats, sm, "Spine", a, b, 1.6, BONE, false)
		for k = 1, 8 do
			local p = a:Lerp(b, 0.3 + k * 0.05)
			for side = -1, 1, 2 do
				local tip = p + box.RightVector * side * size.X * 0.5 - Vector3.new(0, size.Y * 0.3, 0)
				Kit.rod(stats, sm, "Rib", p, tip, 0.8, BONE, false)
			end
		end
	end)
	-- A long shaft of light down onto it, and its bones' scatter
	Kit.shaft(
		m,
		Vector3.new(ground.X, World.surfaceY - 2, ground.Z) + Vector3.new(30, 0, -20),
		ground + Vector3.new(0, 20, 0),
		40,
		0.22
	)
	PlaceMarks.set("WhalesRest", ground + Vector3.new(0, 30, 0))
	local out = Vector3.new(math.cos(math.rad(WHALE.angle)), 0, math.sin(math.rad(WHALE.angle)))
	table.insert(BlueDress.views, {
		name = "whale",
		from = ground - out * 110 + Vector3.new(30, 50, 0),
		to = ground + Vector3.new(0, 8, 0),
		fov = 66,
	})
end

local function pinnacle(parent: Instance)
	local spot = at(PINNACLE.angle, PINNACLE.r)
	local base = floorAt(spot.X, spot.Z)
	local m = Instance.new("Model")
	m.Name = "HammerheadPinnacle"
	m.Parent = parent
	local size = Vector3.new(0.79, 1, 0.8) * PINNACLE.height
	local box = Kit.standing(base, rng:NextNumber(0, 6.28), size, 0.04)
	Kit.hero(stats, m, "CoralPinnacle", box, size, function(sm)
		-- stacked rock tapering up
		for k = 0, 5 do
			local t = k / 6
			local width = size.X * (0.85 - t * 0.7)
			Kit.part(
				stats,
				sm,
				"Spire",
				Vector3.new(width, size.Y / 6 + 2, width),
				CFrame.new(base + Vector3.new(0, size.Y * (t + 1 / 12), 0)) * CFrame.Angles(0, k * 0.7, 0.04),
				ROCK,
				true
			)
		end
	end, { solid = true, blocksCamera = true })
	PlaceMarks.set("HammerheadPinnacle", base + Vector3.new(0, size.Y * 0.55, 0))
	PlaceMarks.set("HammerheadPinnacle_Base", base)
	Kit.clearing(stats, base, size.X * 0.6 + 10)
	local inward = -Vector3.new(spot.X, 0, spot.Z).Unit
	table.insert(BlueDress.views, {
		name = "pinnacle",
		from = base + inward * 260 + Vector3.new(0, 140, 0),
		to = base + Vector3.new(0, 110, 0),
		fov = 64,
	})
end

local function rafts(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "Sargassum"
	m.Parent = parent
	for _ = 1, RAFTS.count do
		local spot =
			at(rng:NextNumber(RAFTS.angles[1], RAFTS.angles[2]), rng:NextNumber(RAFTS.r[1], RAFTS.r[2]))
		local width = rng:NextNumber(26, 40)
		local size = Vector3.new(0.73, 0.69, 1) * width
		local box = CFrame.new(spot.X, World.surfaceY - 3 - size.Y / 2, spot.Z)
			* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		local holder = Kit.hero(stats, m, "Sargassum", box, size, function(sm)
			Kit.part(
				stats,
				sm,
				"Raft",
				Vector3.new(2, size.X, size.Z),
				box * CFrame.new(0, size.Y * 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
				GOLD,
				false,
				Enum.PartType.Cylinder
			)
		end)
		CollectionService:AddTag(holder, "Bobbing")
		CollectionService:AddTag(holder, "Sargassum")
	end
end

local function jellies(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "JellyChains"
	m.Parent = parent
	for _ = 1, JELLIES.count do
		local spot = at(
			rng:NextNumber(JELLIES.angles[1], JELLIES.angles[2]),
			rng:NextNumber(JELLIES.r[1], JELLIES.r[2])
		)
		local floor = floorAt(spot.X, spot.Z)
		local length = rng:NextNumber(40, 70)
		local size = Vector3.new(0.25, 0.35, 1) * length
		local y = math.min(floor.Y + rng:NextNumber(120, 300), World.surfaceY - 60)
		local box = CFrame.new(spot.X, y, spot.Z)
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), 0)
		local holder = Kit.hero(stats, m, "JellyChain", box, size, function(sm)
			for k = 0, 6 do
				Kit.glow(
					stats,
					sm,
					"Bell",
					Vector3.new(size.X * 0.8, size.X * 0.6, size.X * 0.8),
					box * CFrame.new(0, 0, (k / 6 - 0.5) * size.Z),
					JELLY,
					Enum.PartType.Cylinder
				)
			end
		end)
		CollectionService:AddTag(holder, "Drifting")
	end
end

-- Builds the Open Blue's landmarks. Returns what it made.
function BlueDress.build(parent: Instance, ground: Kit.Ground): Kit.Stats
	stats = Kit.stats()
	groundOf = ground
	rng = Random.new(World.seed + 1510)
	table.clear(BlueDress.views)
	whalesRest(parent)
	pinnacle(parent)
	rafts(parent)
	jellies(parent)
	return stats
end

return BlueDress
