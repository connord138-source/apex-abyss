--!strict
-- The Open Blue's landmarks (owner, 2026-10-21, the approved board
-- assets/concepts/biome_detail/BoardBlue.jpg: "The Whale's Rest", the pinnacle
-- included; rebuilt the same day to read like its scene,
-- assets/tripo/biome_concepts/BlueScene.png, after "really everything other than the
-- whale, ship and lighthouse needs more detail and more intricacy" and "the world should
-- feel full"). The Open Blue stays open water (owner, 2026-10-09): the floor stays
-- bare, the life is in the water.
--
--   * THE WHALE'S REST (Config/Places WhalesRest): a great whale's skeleton on the
--     floor far below, a long shaft of light down onto it (unchanged);
--   * HAMMERHEAD PINNACLE (HammerheadPinnacle): a coral-crusted spire at r 1,400 behind
--     the whale, ringed with rock ledges carrying plate corals, barrel sponges, sea
--     whips and fans, more fans and whips on its faces between them, boulders and a
--     coral garden round its foot, little schools circling it (tag `Sargassum`: the
--     client's shelter fish) and the hammerheads (LandmarkController, from PlaceMarks
--     HammerheadPinnacle / HammerheadPinnacle_Base), light shafts down onto it. Its top
--     stays under the Megalodon's patrol band (Config/Bosses `patrol.depth` starts 170
--     over the floor), so the boss cruises over it;
--   * the water column: golden sargassum rafts drifting at the surface in clusters,
--     fronds hanging under them, little fish sheltering under each (tags `Bobbing`,
--     `Sargassum`); rusty navigation buoys among them; long glowing jelly chains and
--     single jellyfish drifting at every depth (`Drifting`).
--
-- The models (biome_blue_glb: WhaleSkeleton, Sargassum, JellyChain, CoralPinnacle,
-- RustyBuoy; the corals and boulders are the cliff's and the reef's WorldProps) go over
-- part-built stand-ins (LandmarkKit.hero); the pinnacle, its ledges and its boulders are
-- solid.
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
local TAU = math.pi * 2
local HALF = math.pi / 2
local UP = Vector3.yAxis

local WHALE = { angle = 268, r = 1120, length = 120 }
-- (its tip under the Megalodon's lowest patrol, 170 studs over the floor)
local PINNACLE = { angle = 274, r = 1400, height = 160 }
local RAFTS = { clusters = 7, r = { 960, 1420 }, angles = { 234, 306 } }
local BUOYS = 2
local CHAINS = { count = 10, r = { 960, 1420 }, angles = { 234, 306 } }
local JELLYFISH = { count = 26, r = { 940, 1440 }, angles = { 232, 308 } }

-- The CoralPinnacle model's radius (a share of its height) by tenth of its height
-- (rows, foot first) and direction (every 45 degrees from its own +X toward +Z),
-- measured off the GLB, so things are set on its faces in the game and the preview
-- alike (no ray reaches a model in the previewer)
local PROFILE = {
	{ 0.41, 0.401, 0.369, 0.362, 0.394, 0.398, 0.399, 0.401 },
	{ 0.387, 0.382, 0.408, 0.343, 0.426, 0.42, 0.334, 0.359 },
	{ 0.28, 0.364, 0.344, 0.311, 0.286, 0.405, 0.357, 0.257 },
	{ 0.228, 0.309, 0.241, 0.295, 0.288, 0.384, 0.294, 0.24 },
	{ 0.204, 0.243, 0.22, 0.23, 0.232, 0.212, 0.217, 0.218 },
	{ 0.239, 0.297, 0.252, 0.197, 0.21, 0.184, 0.203, 0.193 },
	{ 0.144, 0.168, 0.134, 0.13, 0.192, 0.19, 0.22, 0.219 },
	{ 0.17, 0.123, 0.123, 0.117, 0.112, 0.17, 0.228, 0.23 },
	{ 0.142, 0.07, 0.055, 0.064, 0.077, 0.108, 0.12, 0.126 },
	{ 0.073, 0.048, 0.035, 0.053, 0.056, 0.088, 0.11, 0.102 },
}
-- Each model's box in its own axes, as Props.place fits it
local PINNACLE_BOX = Vector3.new(0.79, 1, 0.8)
local BUOY_BOX = Vector3.new(0.643, 1, 0.757)

local BONE = Color3.fromRGB(196, 200, 196)
-- (pale, as the concept's sunlit spire stands out against the blue)
local ROCK = Color3.fromRGB(134, 152, 174)
local LEDGE = Color3.fromRGB(122, 140, 164)
local SUNLIGHT = Color3.fromRGB(206, 236, 255)
local GOLD = Color3.fromRGB(176, 140, 60)
local FROND = Color3.fromRGB(196, 150, 54)
-- The jellies glow violet to blue, never pink (it reads as skin to moderation)
-- (a bright violet blooms toward pink-white, its blue clipping before its red, so the
-- violets keep their red low: they come out lavender-blue)
local JELLY = Color3.fromRGB(104, 88, 255)
local JELLY_PERIWINKLE = Color3.fromRGB(86, 124, 255)
local JELLY_BLUE = Color3.fromRGB(64, 164, 255)
local CHAIN_TINT = Color3.fromRGB(170, 176, 255)
local CHAIN_GLOW = Color3.fromRGB(96, 104, 255)
-- Shafts of sun down the water between the whale and the pinnacle: (how far along
-- from the whale to the pinnacle, studs to the side, width, strength)
local SHAFTS = {
	{ -0.08, 18, 78, 0.5 },
	{ 0.18, -56, 64, 0.42 },
	{ 0.4, 34, 90, 0.46 },
	{ 0.64, -26, 70, 0.42 },
	{ 0.9, 40, 80, 0.44 },
	{ 1.08, -40, 60, 0.38 },
}
local RUST = Color3.fromRGB(122, 52, 30)
local CHAIN = Color3.fromRGB(70, 46, 36)
local CORALS = {
	Color3.fromRGB(120, 140, 230),
	Color3.fromRGB(150, 110, 220),
	Color3.fromRGB(80, 180, 200),
	Color3.fromRGB(200, 120, 190),
}
-- The coral models' own colours pulled toward the concept's cool blues and violets
-- (a tint only darkens, so these are light)
local TINTS = { Color3.fromRGB(200, 214, 255), Color3.fromRGB(222, 204, 255), Color3.fromRGB(196, 240, 255) }

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

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

-- A frame at `position` whose up is `up`, turned `yaw` about it
local function upright(position: Vector3, up: Vector3, yaw: number): CFrame
	local u = up.Unit
	local reference = if math.abs(u.Y) > 0.95 then Vector3.xAxis else UP
	local right = reference:Cross(u).Unit
	return CFrame.fromMatrix(position, right, u) * CFrame.Angles(0, yaw, 0)
end

-- ---------------------------------------------------------------------------
-- Corals and sponges (the cliff's and the reef's WorldProps over stand-ins)
-- ---------------------------------------------------------------------------

-- A table coral: stacked plates out from its foot
local function plate(parent: Instance, frame: CFrame, size: number)
	local height = size * 0.6
	Kit.hero(
		stats,
		parent,
		"PlateCoral",
		frame * CFrame.new(0, height / 2, 0),
		Vector3.new(size, height, size),
		function(sm)
			for k = 0, 2 do
				local radius = size * 0.5 * (1 - k * 0.2)
				Kit.part(
					stats,
					sm,
					"Plate",
					Vector3.new(0.6, radius * 2, radius * 2),
					frame * CFrame.new(0, height * (0.25 + k * 0.3), 0) * CFrame.Angles(0, 0, HALF),
					pick(CORALS),
					false,
					Enum.PartType.Cylinder
				)
			end
		end,
		{ tint = pick(TINTS) }
	)
end

local function barrel(parent: Instance, frame: CFrame, size: number)
	Kit.hero(
		stats,
		parent,
		"BarrelSponge",
		frame * CFrame.new(0, size * 0.48, 0),
		Vector3.new(size * 0.82, size, size * 0.82),
		function(sm)
			Kit.part(
				stats,
				sm,
				"Barrel",
				Vector3.new(size, size * 0.7, size * 0.7),
				frame * CFrame.new(0, size * 0.48, 0) * CFrame.Angles(0, 0, HALF),
				pick(CORALS),
				false,
				Enum.PartType.Cylinder
			)
		end,
		{ tint = pick(TINTS) }
	)
end

local function whips(parent: Instance, frame: CFrame, size: number)
	Kit.hero(
		stats,
		parent,
		"SeaWhips",
		frame * CFrame.new(0, size * 0.45, 0),
		Vector3.new(size * 0.8, size, size * 0.8),
		function(sm)
			local color = pick(CORALS)
			for k = 1, 3 do
				local tip = (frame * CFrame.Angles(0.35 * (k - 2), k * 2.1, 0.3) * CFrame.new(0, size, 0)).Position
				Kit.rod(stats, sm, "Whip", frame.Position, tip, math.max(size * 0.035, 0.25), color, false)
			end
		end,
		{ tint = pick(TINTS) }
	)
end

-- A sea fan standing out from its foot, its broad face along `frame`'s look
local function fan(parent: Instance, frame: CFrame, size: number)
	local name = if rng:NextNumber() < 0.5 then "FanCoral" else "LaceFan"
	Kit.hero(
		stats,
		parent,
		name,
		frame * CFrame.new(0, size * 0.5, 0) * CFrame.Angles(0, HALF, 0),
		Vector3.new(size * 0.45, size * 0.9, size),
		function(sm)
			Kit.part(
				stats,
				sm,
				"Fan",
				Vector3.new(size, size * 0.85, 0.4),
				frame * CFrame.new(0, size * 0.5, 0),
				pick(CORALS),
				false
			)
		end,
		{ tint = pick(TINTS) }
	)
end

-- One of the reef's corals or an anemone (BrainCoral, StaghornCoral, TubeSponge,
-- Anemone), for the pinnacle's foot
local GARDEN = { "BrainCoral", "StaghornCoral", "TubeSponge", "Anemone", "FanCoral" }
local function gardenPiece(parent: Instance, ground: Vector3, size: number)
	local kind = pick(GARDEN)
	local frame = upright(ground, UP, rng:NextNumber(0, TAU))
	Kit.hero(
		stats,
		parent,
		kind,
		frame * CFrame.new(0, size * 0.7, 0),
		Vector3.new(size * 1.7, size * 1.5, size * 1.7),
		function(sm)
			Kit.part(
				stats,
				sm,
				"Coral",
				Vector3.new(size * 1.4, size * 1.2, size * 1.4),
				frame * CFrame.new(0, size * 0.6, 0) * CFrame.Angles(0, 0, HALF),
				pick(CORALS),
				false,
				Enum.PartType.Cylinder
			)
		end,
		{ solid = kind ~= "Anemone", tint = pick(TINTS) }
	)
end

local function boulder(parent: Instance, ground: Vector3, size: number)
	local frame = upright(ground, UP, rng:NextNumber(0, TAU))
	Kit.hero(
		stats,
		parent,
		"BoulderRound",
		frame * CFrame.new(0, size * 0.36, 0),
		Vector3.new(size * 1.1, size * 0.9, size * 1.1),
		function(sm)
			Kit.part(
				stats,
				sm,
				"Boulder",
				Vector3.new(size, size * 0.8, size),
				frame * CFrame.new(0, size * 0.32, 0) * CFrame.Angles(0.2, 0.4, 0.1),
				ROCK,
				true,
				nil,
				Enum.Material.Slate
			)
		end,
		{ solid = true }
	)
end

-- An invisible spot little fish circle under (the client's shelter fish, which swim
-- 9-14 studs below a `Sargassum`-tagged model's pivot)
local function school(parent: Instance, center: Vector3)
	local m = Instance.new("Model")
	m.Name = "FishSchool"
	m.WorldPivot = CFrame.new(center + Vector3.new(0, 11, 0))
	m.Parent = parent
	Kit.anchor(m, "SchoolSpot", m.WorldPivot)
	CollectionService:AddTag(m, "Sargassum")
end

-- ---------------------------------------------------------------------------
-- The Whale's Rest
-- ---------------------------------------------------------------------------

-- Pale sand round a spot, as the concept's whale lies on pale sand while the deep floor
-- round it is darker mud: the floor's Mud repainted Sand in rows of grid boxes, a
-- ragged disc. Only the material changes (Terrain:ReplaceMaterial), never its shape.
local function paleSand(center: Vector3, radius: number)
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain == nil then
		return
	end
	local z = -radius
	while z < radius do
		local half = math.sqrt(math.max(radius * radius - (z + 4) ^ 2, 0)) + rng:NextNumber(-8, 8)
		if half > 6 then
			local low = Vector3.new(center.X - half, center.Y - 24, center.Z + z)
			local high = Vector3.new(center.X + half, center.Y + 24, center.Z + z + 8)
			terrain:ReplaceMaterial(
				Region3.new(low, high):ExpandToGrid(4),
				4,
				Enum.Material.Mud,
				Enum.Material.Sand
			)
		end
		z += 8
	end
end

local function whalesRest(parent: Instance): Vector3
	local spot = at(WHALE.angle, WHALE.r)
	local ground = floorAt(spot.X, spot.Z)
	local m = Instance.new("Model")
	m.Name = "WhalesRest"
	m.Parent = parent
	Kit.clearing(stats, ground, WHALE.length * 0.6)
	local size = Vector3.new(0.37, 0.31, 1) * WHALE.length
	local yaw = math.rad(WHALE.angle + 70)
	local box = Kit.standing(ground, yaw, size, 0.12)
	paleSand(ground, 110)
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
	end, { tint = Color3.fromRGB(255, 246, 228) })
	-- The sun on its bones (the shafts down onto it are sunlight()'s)
	Kit.light(
		stats,
		Kit.anchor(m, "WhaleLight", CFrame.new(ground + Vector3.new(-10, 46, 20))),
		SUNLIGHT,
		60,
		1.2
	)
	PlaceMarks.set("WhalesRest", ground + Vector3.new(0, 30, 0))
	local out = Vector3.new(math.cos(math.rad(WHALE.angle)), 0, math.sin(math.rad(WHALE.angle)))
	table.insert(BlueDress.views, {
		name = "whale",
		from = ground - out * 110 + Vector3.new(30, 50, 0),
		to = ground + Vector3.new(0, 8, 0),
		fov = 66,
	})
	return ground
end

-- ---------------------------------------------------------------------------
-- Hammerhead Pinnacle
-- ---------------------------------------------------------------------------

-- The pinnacle's face at `t` of its height, direction `theta` (radians, its own +X
-- toward +Z): the point `inset` studs in from it and the way out
local function face(box: CFrame, height: number, t: number, theta: number, inset: number): (Vector3, Vector3)
	local row = PROFILE[math.clamp(math.floor(t * 10) + 1, 1, #PROFILE)]
	local f = (theta % TAU) / (TAU / 8)
	local i = math.floor(f)
	local a, b = row[i + 1], row[(i + 1) % 8 + 1]
	-- (the profile is the model's widest, its corals included: 0.86 of it is rock)
	local r = (a + (b - a) * (f - i)) * height * 0.86 - inset
	local out = Vector3.new(math.cos(theta), 0, math.sin(theta))
	local point = box:PointToWorldSpace(Vector3.new(out.X * r, (t - 0.5) * height, out.Z * r))
	return point, box:VectorToWorldSpace(out)
end

-- A rock shelf jutting from the pinnacle with corals on it
local function ledge(parent: Instance, box: CFrame, height: number, t: number, theta: number)
	local point, out = face(box, height, t, theta, 3)
	local width = 12 + (1 - t) * 14
	local depth = 8 + (1 - t) * 8
	local frame = CFrame.lookAt(point, point + out)
	local slab = frame * CFrame.new(0, 0, -depth / 2 + 2) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), 0, 0)
	Kit.part(
		stats,
		parent,
		"Ledge",
		Vector3.new(width, 3, depth),
		slab,
		LEDGE,
		true,
		nil,
		Enum.Material.Slate
	)
	Kit.part(
		stats,
		parent,
		"LedgeFoot",
		Vector3.new(width * 0.7, 3, depth * 0.6),
		slab * CFrame.new(0, -2.6, depth * 0.15) * CFrame.Angles(-0.25, 0, 0),
		ROCK,
		true,
		nil,
		Enum.Material.Slate
	)
	-- what grows on it: a table coral or a sponge out on its lip, whips or a fan behind
	local top = slab * CFrame.new(0, 1.5, 0)
	local lip = top * CFrame.new(rng:NextNumber(-0.2, 0.2) * width, 0, -depth * 0.2)
	if rng:NextNumber() < 0.6 then
		plate(parent, upright(lip.Position, UP, rng:NextNumber(0, TAU)), rng:NextNumber(10, 15))
	else
		barrel(parent, upright(lip.Position, UP, rng:NextNumber(0, TAU)), rng:NextNumber(7, 11))
	end
	local back = top * CFrame.new(width * (if rng:NextNumber() < 0.5 then 0.3 else -0.3), 0, depth * 0.15)
	if rng:NextNumber() < 0.5 then
		whips(parent, upright(back.Position, UP, rng:NextNumber(0, TAU)), rng:NextNumber(10, 15))
	else
		fan(parent, CFrame.lookAt(back.Position, back.Position + out), rng:NextNumber(10, 15))
	end
end

local function pinnacle(parent: Instance, whale: Vector3)
	local spot = at(PINNACLE.angle, PINNACLE.r)
	local base = floorAt(spot.X, spot.Z)
	local m = Instance.new("Model")
	m.Name = "HammerheadPinnacle"
	m.Parent = parent
	local height = PINNACLE.height
	local size = PINNACLE_BOX * height
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

	-- Ledges up its faces, each with corals on it
	local ledges = 9
	for k = 1, ledges do
		local t = 0.14 + (k - 1) / (ledges - 1) * 0.62
		ledge(m, box, height, t, k * 2.4 + rng:NextNumber(-0.3, 0.3))
	end
	-- Fans and whips on its faces between them
	for k = 1, 16 do
		local t = rng:NextNumber(0.1, 0.82)
		local theta = rng:NextNumber(0, TAU)
		local point, out = face(box, height, t, theta, 1)
		local size2 = rng:NextNumber(9, 15) * (1.15 - t * 0.5)
		if k % 2 == 0 then
			fan(m, CFrame.lookAt(point, point + out) * CFrame.Angles(0, HALF, 0), size2)
		else
			whips(m, upright(point, (out * 0.6 + UP).Unit, rng:NextNumber(0, TAU)), size2)
		end
	end
	-- Its foot: pale sand, boulders and a garden of coral round it
	local footRadius = height * 0.42
	paleSand(base, footRadius + 50)
	for k = 1, 10 do
		local angle = k / 10 * TAU + rng:NextNumber(-0.2, 0.2)
		local reach = footRadius + rng:NextNumber(2, 14)
		local p = base + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
		boulder(m, floorAt(p.X, p.Z), rng:NextNumber(10, 22))
	end
	for k = 1, 18 do
		local angle = rng:NextNumber(0, TAU)
		local reach = footRadius + rng:NextNumber(6, 40)
		local p = base + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
		gardenPiece(m, floorAt(p.X, p.Z), rng:NextNumber(3.5, 7) * (if k % 4 == 0 then 1.6 else 1))
	end
	-- Little schools circling it at every height
	for k = 1, 10 do
		local t = 0.12 + k * 0.075
		local point, out = face(box, height, t, k * 1.9, -22 - (k % 3) * 8)
		school(m, point + out * 2)
	end
	-- The sun on its whale-facing side, so its facets read pale and sculpted against
	-- the blue (lights a little out from the face)
	local toWhale = Vector3.new(whale.X - base.X, 0, whale.Z - base.Z).Unit
	for k = 1, 6 do
		local t = 0.08 + k * 0.13
		local theta = math.atan2(toWhale.Z, toWhale.X) + (if k % 2 == 0 then 0.55 else -0.35)
		local point, out = face(box, height, t, theta, -24)
		Kit.light(stats, Kit.anchor(m, "SunSide", CFrame.new(point + out * 2)), SUNLIGHT, 60, 3.6)
	end

	PlaceMarks.set("HammerheadPinnacle", base + Vector3.new(0, size.Y * 0.55, 0))
	PlaceMarks.set("HammerheadPinnacle_Base", base)
	Kit.clearing(stats, base, size.X * 0.6 + 44)
	-- The concept's view: the whale's skull in front, its body running off to the left,
	-- the pinnacle beyond it
	local toward = Vector3.new(base.X - whale.X, 0, base.Z - whale.Z).Unit
	local side = toward:Cross(UP)
	table.insert(BlueDress.views, {
		name = "concept",
		from = whale + Vector3.new(-22, 30, 112),
		to = whale:Lerp(base, 0.24) + UP * 62,
		fov = 66,
	})
	table.insert(BlueDress.views, {
		name = "pinnacle",
		from = base - toward * 170 + side * 30 + UP * 70,
		to = base + UP * 70,
		fov = 66,
	})
end

-- A wide, soft shaft of sunlight: three beams nested on one line (a wide faint one, a
-- middle, a brighter core), so its edges fade instead of ending
local function sunShaft(parent: Instance, top: Vector3, bottom: Vector3, width: number, strength: number)
	Kit.shaft(parent, top, bottom, width, strength * 0.3)
	Kit.shaft(parent, top, bottom, width * 0.6, strength * 0.32)
	Kit.shaft(parent, top, bottom, width * 0.28, strength * 0.38)
end

-- Sunlight down the clear water between the whale and the pinnacle (SHAFTS), all
-- slanting the same way, as the concept's fan of shafts from the surface
local function sunlight(parent: Instance, whale: Vector3)
	local m = Instance.new("Model")
	m.Name = "SunShafts"
	m.Parent = parent
	local spot = at(PINNACLE.angle, PINNACLE.r)
	local pin = floorAt(spot.X, spot.Z)
	local toward = Vector3.new(pin.X - whale.X, 0, pin.Z - whale.Z).Unit
	local side = toward:Cross(UP)
	-- (the sun's way down: in from behind the whale and to one side)
	local slant = toward * 0.14 + side * 0.1
	for _, shaft in SHAFTS do
		local flat = whale:Lerp(pin, shaft[1]) + side * shaft[2]
		local foot = floorAt(flat.X, flat.Z) + UP * 14
		local top = Vector3.new(foot.X, World.surfaceY - 2, foot.Z) - slant * (World.surfaceY - foot.Y)
		sunShaft(m, top, foot, shaft[3], shaft[4])
	end
end

-- ---------------------------------------------------------------------------
-- The water column: sargassum, buoys, jelly chains, jellyfish
-- ---------------------------------------------------------------------------

-- Fronds hanging under a raft: strands of golden leaves (in the raft's holder, so
-- they bob with it)
local function fronds(holder: Instance, box: CFrame, width: number)
	for k = 1, 6 do
		local start = box
			* CFrame.new(rng:NextNumber(-0.4, 0.4) * width, -width * 0.2, rng:NextNumber(-0.45, 0.45) * width)
		local y = 0
		for leaf = 1, 3 do
			local long = rng:NextNumber(3, 5) * (width / 40)
			Kit.part(
				stats,
				holder,
				"Frond",
				Vector3.new(0.3, long, long * 0.42),
				start
					* CFrame.new(0, -y - long / 2, 0)
					* CFrame.Angles(0, k + leaf, rng:NextNumber(-0.3, 0.3)),
				FROND,
				false
			)
			y += long * 0.85
		end
	end
end

local function raft(parent: Instance, spot: Vector3, width: number)
	local size = Vector3.new(0.73, 0.69, 1) * width
	local box = CFrame.new(spot.X, World.surfaceY - 3 - size.Y / 2, spot.Z)
		* CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
	local holder = Kit.hero(stats, parent, "Sargassum", box, size, function(sm)
		Kit.part(
			stats,
			sm,
			"Raft",
			Vector3.new(2, size.X, size.Z),
			box * CFrame.new(0, size.Y * 0.4, 0) * CFrame.Angles(0, 0, HALF),
			GOLD,
			false,
			Enum.PartType.Cylinder
		)
	end)
	fronds(holder, box, width)
	CollectionService:AddTag(holder, "Bobbing")
	CollectionService:AddTag(holder, "Sargassum")
end

local function buoy(parent: Instance, spot: Vector3)
	local height = 14
	local size = BUOY_BOX * height
	-- (riding low: a third of it under the surface)
	local box = CFrame.new(spot.X, World.surfaceY - height * 0.2, spot.Z)
		* CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
	local holder = Kit.hero(stats, parent, "RustyBuoy", box, size, function(sm)
		local foot = box * CFrame.new(0, -height * 0.3, 0)
		Kit.part(
			stats,
			sm,
			"Float",
			Vector3.new(height * 0.4, size.X * 0.95, size.X * 0.95),
			foot * CFrame.Angles(0, 0, HALF),
			RUST,
			false,
			Enum.PartType.Cylinder
		)
		for k = 0, 3 do
			local a = k * HALF + math.pi / 4
			local leg = foot
				* CFrame.new(math.cos(a) * size.X * 0.22, height * 0.2, math.sin(a) * size.X * 0.22)
			Kit.rod(
				stats,
				sm,
				"Leg",
				leg.Position,
				(box * CFrame.new(0, height * 0.42, 0)).Position,
				0.35,
				RUST,
				false
			)
		end
		Kit.part(
			stats,
			sm,
			"Cage",
			Vector3.new(height * 0.24, size.X * 0.42, size.X * 0.42),
			box * CFrame.new(0, height * 0.42, 0) * CFrame.Angles(0, 0, HALF),
			RUST,
			false,
			Enum.PartType.Cylinder
		)
	end)
	-- its mooring chain hanging off below it, cut short by the depth
	Kit.chain(
		stats,
		holder,
		box.Position - Vector3.new(0, height * 0.45, 0),
		box.Position - Vector3.new(4, 46, 2),
		3,
		2.2,
		CHAIN
	)
	CollectionService:AddTag(holder, "Bobbing")
	if #BlueDress.views < 4 then
		table.insert(BlueDress.views, {
			name = "buoy",
			from = box.Position + Vector3.new(-34, -16, -26),
			to = box.Position + Vector3.new(0, -4, 0),
			fov = 60,
		})
	end
end

local function sargassum(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "Sargassum"
	m.Parent = parent
	local centers = {}
	for _ = 1, RAFTS.clusters do
		local center =
			at(rng:NextNumber(RAFTS.angles[1], RAFTS.angles[2]), rng:NextNumber(RAFTS.r[1], RAFTS.r[2]))
		table.insert(centers, center)
		-- a field of 2-4 rafts drifting together
		for _ = 1, rng:NextInteger(2, 4) do
			local offset = Vector3.new(rng:NextNumber(-60, 60), 0, rng:NextNumber(-60, 60))
			raft(m, center + offset, rng:NextNumber(30, 56))
		end
	end
	for k = 1, BUOYS do
		local center = centers[(k * 3) % #centers + 1]
		buoy(m, center + Vector3.new(rng:NextNumber(70, 90), 0, rng:NextNumber(-30, 30)))
	end
	local first = centers[1]
	table.insert(BlueDress.views, {
		name = "surface",
		from = Vector3.new(first.X - 70, World.surfaceY - 80, first.Z - 60),
		to = Vector3.new(first.X, World.surfaceY - 14, first.Z),
		fov = 78,
	})
end

local function chains(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "JellyChains"
	m.Parent = parent
	for _ = 1, CHAINS.count do
		local spot =
			at(rng:NextNumber(CHAINS.angles[1], CHAINS.angles[2]), rng:NextNumber(CHAINS.r[1], CHAINS.r[2]))
		local floor = floorAt(spot.X, spot.Z)
		local length = rng:NextNumber(60, 110)
		local size = Vector3.new(0.25, 0.35, 1) * length
		local y = math.min(floor.Y + rng:NextNumber(110, 380), World.surfaceY - 60)
		local box = CFrame.new(spot.X, y, spot.Z)
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, TAU), 0)
		local holder, model = Kit.hero(stats, m, "JellyChain", box, size, function(sm)
			for k = 0, 8 do
				Kit.glow(
					stats,
					sm,
					"Bell",
					Vector3.new(size.X * 0.8, size.X * 0.6, size.X * 0.8),
					box * CFrame.new(0, 0, (k / 8 - 0.5) * size.Z),
					JELLY,
					Enum.PartType.Cylinder
				)
			end
		end, { tint = CHAIN_TINT })
		if model then
			-- (Glow / GlowTint: what the cloud previewer reads)
			model:SetAttribute("Glow", 3.2)
			model:SetAttribute("GlowTint", CHAIN_GLOW)
			for _, d in model:GetDescendants() do
				if d:IsA("SurfaceAppearance") then
					d.EmissiveStrength = 3.2
					d.EmissiveTint = CHAIN_GLOW
				elseif d:IsA("BasePart") then
					d.CastShadow = false
				end
			end
		end
		CollectionService:AddTag(holder, "Drifting")
	end
end

-- A jellyfish: a faceted bell glowing through (two stepped discs and a cap, Neon and
-- translucent), a bright rim and long glowing tentacles and oral arms (parts; no
-- sphere lumps)
local function jellyfish(parent: Instance, spot: Vector3, size: number)
	local color = pick({ JELLY, JELLY_PERIWINKLE, JELLY_BLUE })
	local frame = CFrame.new(spot)
		* CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, TAU), rng:NextNumber(-0.25, 0.25))
	local holder = Instance.new("Model")
	holder.Name = "Jellyfish"
	holder.WorldPivot = frame
	holder.Parent = parent
	local function disc(name: string, diameter: number, thick: number, y: number, transparency: number)
		local p = Kit.glow(
			stats,
			holder,
			name,
			Vector3.new(thick, diameter, diameter),
			frame * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, HALF),
			color,
			Enum.PartType.Cylinder
		)
		p.Transparency = transparency
		p.CastShadow = false
		return p
	end
	disc("Bell", size, size * 0.22, 0, 0.55)
	disc("BellTop", size * 0.72, size * 0.2, size * 0.2, 0.5)
	disc("BellCap", size * 0.4, size * 0.14, size * 0.36, 0.42)
	local glowColor = color:Lerp(Color3.new(0.8, 0.9, 1), 0.2)
	local rim = Kit.glow(
		stats,
		holder,
		"Rim",
		Vector3.new(size * 0.07, size * 1.04, size * 1.04),
		frame * CFrame.new(0, -size * 0.1, 0) * CFrame.Angles(0, 0, HALF),
		glowColor,
		Enum.PartType.Cylinder
	)
	rim.Transparency = 0.2
	local thick = math.max(0.22, size * 0.026)
	for k = 1, 8 do
		local a = k / 8 * TAU
		local long = size * rng:NextNumber(2.4, 4)
		local top = frame * CFrame.new(math.cos(a) * size * 0.42, -size * 0.12, math.sin(a) * size * 0.42)
		local tentacle = Kit.glow(
			stats,
			holder,
			"Tentacle",
			Vector3.new(thick, long, thick),
			top
				* CFrame.new(0, -long / 2, 0)
				* CFrame.Angles(rng:NextNumber(-0.12, 0.12), 0, rng:NextNumber(-0.12, 0.12)),
			glowColor
		)
		tentacle.Transparency = 0.3
	end
	for k = 1, 3 do
		local a = k / 3 * TAU + 0.5
		local long = size * rng:NextNumber(1.1, 1.7)
		local arm = Kit.glow(
			stats,
			holder,
			"OralArm",
			Vector3.new(size * 0.14, long, size * 0.08),
			frame
				* CFrame.new(math.cos(a) * size * 0.1, -size * 0.12 - long / 2, math.sin(a) * size * 0.1)
				* CFrame.Angles(0, a, 0.15),
			color
		)
		arm.Transparency = 0.45
		arm.CastShadow = false
	end
	CollectionService:AddTag(holder, "Drifting")
end

local function jellies(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "Jellyfish"
	m.Parent = parent
	for _ = 1, JELLYFISH.count do
		local spot = at(
			rng:NextNumber(JELLYFISH.angles[1], JELLYFISH.angles[2]),
			rng:NextNumber(JELLYFISH.r[1], JELLYFISH.r[2])
		)
		local floor = floorAt(spot.X, spot.Z)
		local y = math.min(floor.Y + rng:NextNumber(40, 420), World.surfaceY - 30)
		jellyfish(m, Vector3.new(spot.X, y, spot.Z), rng:NextNumber(9, 17))
	end
	-- A drift of them over the whale's way to the pinnacle, at a fish's height
	local whale = at(WHALE.angle, WHALE.r)
	local pin = at(PINNACLE.angle, PINNACLE.r)
	for k = 1, 9 do
		local flat = whale:Lerp(pin, rng:NextNumber(-0.1, 0.9))
			+ Vector3.new(rng:NextNumber(-70, 70), 0, rng:NextNumber(-70, 70))
		local floor = floorAt(flat.X, flat.Z)
		local y = floor.Y + rng:NextNumber(60, 230)
		jellyfish(m, Vector3.new(flat.X, y, flat.Z), rng:NextNumber(10, 18))
	end
end

-- Builds the Open Blue's landmarks. Returns what it made.
function BlueDress.build(parent: Instance, ground: Kit.Ground): Kit.Stats
	stats = Kit.stats()
	groundOf = ground
	rng = Random.new(World.seed + 1510)
	table.clear(BlueDress.views)
	local whale = whalesRest(parent)
	pinnacle(parent, whale)
	sunlight(parent, whale)
	sargassum(parent)
	chains(parent)
	jellies(parent)
	return stats
end

return BlueDress
