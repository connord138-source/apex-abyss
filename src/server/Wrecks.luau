--!strict
-- The Shipwreck Graveyard's landmarks and wrecks (owner, 2026-10-21, the approved
-- board assets/concepts/biome_detail/BoardWreck.jpg: "The Broken Galleon"):
--
--   * THE BROKEN GALLEON (Config/Places BrokenGalleon) in the middle of the bay: a
--     galleon's two halves on the sand with the break between them to swim through,
--     the bow listing, the stern's cabin windows still lit (a treasure dig site in
--     front of them: PlaceMarks BrokenGalleon_Dig), its anchors out on chains,
--     cannons and barrels spilled from the gun deck, the figurehead fallen in front of
--     the bow, the ship's wheel and bell on a broken post behind the stern (BITE it:
--     LandmarkService rings it), lanterns on broken posts;
--   * THE FALLEN LIGHTHOUSE (FallenLighthouse) lying across the sand to the south;
--   * a rusty steamer and a little trawler further out in the haze;
--   * the BAY CANNON at the bay's inner end, aimed across it at the galleon: swim into
--     its muzzle and it fires you over the bay (LandmarkService, LandmarksController);
--   * the fourteen wrecks WorldService scatters over the bay (`Wrecks.scatter`): hulls,
--     sterns, steamers and debris fields, each with its own spill of cannons, barrels
--     and an anchor, in place of the old part-built boxes.
--
-- The models (biome_wreck_glb: GalleonBow, GalleonStern, IronSteamer,
-- ToppledLighthouse, WreckCannon, WreckAnchor, WreckFigurehead, WreckWheelBell,
-- WreckBarrels) are fitted over part-built stand-ins (LandmarkKit.hero), so the bay
-- works with nothing imported. Hulls, the lighthouse and the steamer are solid (fish
-- bump into them, the camera stays out) and live under World.Biomes.Wrecks, where
-- Shared/Ground looks; debris is soft.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Kit = require(script.Parent.LandmarkKit)
local PlaceMarks = require(script.Parent.PlaceMarks)

local Wrecks = {}

export type View = { name: string, from: Vector3, to: Vector3, fov: number }
export type Cannon = { muzzle: Vector3, direction: Vector3 }

-- What the bay's hooks need (LandmarkService reads them after the build)
Wrecks.cannons = {} :: { Cannon }
Wrecks.bells = {} :: { Vector3 }
Wrecks.views = {} :: { View }

local HALF = math.pi / 2
local GLB_FRONT = Kit.GLB_FRONT

local WOOD = Color3.fromRGB(70, 52, 38)
local WOOD_LIGHT = Color3.fromRGB(110, 86, 60)
local IRON = Color3.fromRGB(52, 56, 62)
local RUST = Color3.fromRGB(128, 74, 44)
local BRONZE = Color3.fromRGB(78, 112, 92)
local TEAL = Color3.fromRGB(60, 120, 112)
local STONE = Color3.fromRGB(150, 150, 146)
local STRIPE = Color3.fromRGB(150, 58, 46)
local CABIN_LIGHT = Color3.fromRGB(255, 176, 96)

-- Where the bay's set pieces stand (degrees round the hub, studs out)
local GALLEON = { angle = 180, r = 650 }
local LIGHTHOUSE = { angle = 196, r = 600 }
local STEAMER = { angle = 163, r = 765 }
local TRAWLER = { angle = 213, r = 735 }
local BAY_CANNON = { angle = 151, r = 600 }
-- Scattered wrecks keep this far from the set pieces
local KEEP_CLEAR = 120

local stats: Kit.Stats = Kit.stats()
local groundOf: Kit.Ground = function(_x: number, _z: number): (Vector3?, Vector3?)
	return nil, nil
end
local landmarks: { Vector3 } = {}

local function at(angle: number, r: number): Vector3
	local a = math.rad(angle)
	return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

local function floorAt(x: number, z: number): Vector3
	local hit = groundOf(x, z)
	return hit or Vector3.new(x, Seafloor.y(x, z), z)
end

-- The lowest ground under a footprint (so a hull's keel isn't left hanging off a dune)
local function lowestUnder(frame: CFrame, length: number, width: number): number
	local low = math.huge
	for _, offset in
		{
			Vector3.zero,
			Vector3.new(0, 0, length / 2),
			Vector3.new(0, 0, -length / 2),
			Vector3.new(width / 2, 0, 0),
			Vector3.new(-width / 2, 0, 0),
		}
	do
		local p = frame:PointToWorldSpace(offset)
		low = math.min(low, floorAt(p.X, p.Z).Y)
	end
	return low
end

-- ---------------------------------------------------------------------------
-- Stand-ins (what shows with nothing imported)
-- ---------------------------------------------------------------------------

-- A hull lying along the box's own X: keel, two flared sides, a deck, ribs at the open
-- end and a broken mast. `open` = the end (-1, +1) left jagged.
local function hullStandin(m: Model, box: CFrame, size: Vector3, open: number, color: Color3)
	local length, height, width = size.X, size.Y, size.Z
	Kit.part(
		stats,
		m,
		"Keel",
		Vector3.new(length * 0.92, height * 0.16, width * 0.4),
		box * CFrame.new(0, -height * 0.42, 0),
		color,
		true
	)
	for side = -1, 1, 2 do
		Kit.part(
			stats,
			m,
			"Side",
			Vector3.new(length * 0.9, height * 0.5, 1.6),
			box
				* CFrame.new(0, -height * 0.15, side * width * 0.36)
				* CFrame.Angles(math.rad(side * -18), 0, 0),
			color,
			true
		)
	end
	Kit.part(
		stats,
		m,
		"Deck",
		Vector3.new(length * 0.82, 1.2, width * 0.66),
		box * CFrame.new(0, height * 0.08, 0),
		WOOD_LIGHT,
		true
	)
	for i = 1, 3 do
		local x = open * length * (0.47 - i * 0.04)
		for side = -1, 1, 2 do
			Kit.part(
				stats,
				m,
				"Rib",
				Vector3.new(1.4, height * 0.5, 1.4),
				box
					* CFrame.new(x, -height * 0.1, side * width * 0.3)
					* CFrame.Angles(math.rad(side * -16), 0, 0),
				WOOD_LIGHT,
				false
			)
		end
	end
	Kit.rod(
		stats,
		m,
		"Mast",
		box:PointToWorldSpace(Vector3.new(-open * length * 0.1, 0, 0)),
		box:PointToWorldSpace(Vector3.new(-open * length * 0.1 + 4, height * 0.5, 0)),
		1.2,
		WOOD,
		false
	)
end

local function cannonStandin(m: Model, box: CFrame, size: Vector3)
	Kit.rod(
		stats,
		m,
		"Barrel",
		box:PointToWorldSpace(Vector3.new(-size.X * 0.45, size.Y * 0.15, 0)),
		box:PointToWorldSpace(Vector3.new(size.X * 0.5, size.Y * 0.2, 0)),
		size.Y * 0.22,
		BRONZE,
		false
	)
	Kit.part(
		stats,
		m,
		"Carriage",
		Vector3.new(size.X * 0.6, size.Y * 0.4, size.Z * 0.6),
		box * CFrame.new(-size.X * 0.1, -size.Y * 0.25, 0),
		WOOD_LIGHT,
		false
	)
	for side = -1, 1, 2 do
		for end_ = -1, 1, 2 do
			Kit.part(
				stats,
				m,
				"Wheel",
				Vector3.new(size.Z * 0.12, size.Y * 0.36, size.Y * 0.36),
				box
					* CFrame.new(end_ * size.X * 0.22, -size.Y * 0.32, side * size.Z * 0.36)
					* CFrame.Angles(0, HALF, 0),
				WOOD,
				false,
				Enum.PartType.Cylinder
			)
		end
	end
end

local function anchorStandin(m: Model, box: CFrame, size: Vector3)
	Kit.part(stats, m, "Shank", Vector3.new(size.X * 0.12, size.Y * 0.8, size.X * 0.12), box, RUST, false)
	Kit.part(
		stats,
		m,
		"Stock",
		Vector3.new(size.X * 0.7, size.Y * 0.08, size.X * 0.1),
		box * CFrame.new(0, size.Y * 0.36, 0),
		RUST,
		false
	)
	for side = -1, 1, 2 do
		Kit.part(
			stats,
			m,
			"Arm",
			Vector3.new(size.X * 0.42, size.Y * 0.1, size.X * 0.1),
			box
				* CFrame.new(side * size.X * 0.18, -size.Y * 0.32, 0)
				* CFrame.Angles(0, 0, math.rad(side * 32)),
			RUST,
			false
		)
	end
end

local function barrelsStandin(m: Model, box: CFrame, size: Vector3)
	for i = -1, 1 do
		Kit.part(
			stats,
			m,
			"Barrel",
			Vector3.new(size.Y * 0.8, size.Y * 0.6, size.Y * 0.6),
			box
				* CFrame.new(i * size.X * 0.25, -size.Y * 0.2, i * size.Z * 0.12)
				* CFrame.Angles(0, i * 0.5, HALF),
			WOOD_LIGHT,
			false,
			Enum.PartType.Cylinder
		)
	end
	Kit.part(
		stats,
		m,
		"Crate",
		Vector3.new(size.Y * 0.7, size.Y * 0.7, size.Y * 0.7),
		box * CFrame.new(size.X * 0.2, -size.Y * 0.15, -size.Z * 0.2) * CFrame.Angles(0, 0.4, 0.1),
		WOOD,
		false
	)
end

local function postStandin(m: Model, box: CFrame, size: Vector3)
	Kit.part(stats, m, "Post", Vector3.new(size.X * 0.4, size.Y, size.X * 0.4), box, WOOD, false)
	Kit.part(
		stats,
		m,
		"Wheel",
		Vector3.new(size.X * 0.15, size.Y * 0.5, size.Y * 0.5),
		box * CFrame.new(0, size.Y * 0.05, -size.Z * 0.25) * CFrame.Angles(0, 0, 0),
		WOOD_LIGHT,
		false,
		Enum.PartType.Cylinder
	)
	Kit.part(
		stats,
		m,
		"Bell",
		Vector3.new(size.Z * 0.22, size.Y * 0.18, size.Z * 0.22),
		box * CFrame.new(0, size.Y * 0.18, size.Z * 0.32),
		BRONZE,
		false
	)
end

-- ---------------------------------------------------------------------------
-- Pieces
-- ---------------------------------------------------------------------------

-- A hull model (GalleonBow, GalleonStern, IronSteamer) `length` long lying on the
-- sand at `ground`, its front looking along `yaw`, listing `roll`, pitched `pitch`
local function hull(
	parent: Instance,
	name: string,
	ground: Vector3,
	yaw: number,
	length: number,
	ratios: Vector3,
	roll: number,
	pitch: number,
	sink: number,
	color: Color3
): CFrame
	local size = Vector3.new(length, length * ratios.Y, length * ratios.Z)
	local flat = CFrame.new(ground) * CFrame.Angles(0, yaw, 0)
	local floor = lowestUnder(flat, length, size.Z)
	local frame = CFrame.new(ground.X, floor, ground.Z)
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(pitch, 0, roll)
	local box = frame * CFrame.new(0, size.Y * (0.5 - sink), 0) * GLB_FRONT
	Kit.hero(stats, parent, name, box, size, function(m)
		hullStandin(m, box, size, 1, color)
	end, { solid = true, blocksCamera = true })
	return box
end

-- A small prop on the sand: `height` tall, turned `yaw`, tipped `tilt`
local function prop(
	parent: Instance,
	name: string,
	ground: Vector3,
	yaw: number,
	size: Vector3,
	sink: number,
	tilt: CFrame?,
	build: (Model, CFrame, Vector3) -> ()
): CFrame
	local box = Kit.standing(ground, yaw, size, sink, tilt)
	Kit.hero(stats, parent, name, box, size, function(m)
		build(m, box, size)
	end)
	return box
end

local function cannon(parent: Instance, ground: Vector3, yaw: number, length: number, tip: number): CFrame
	local size = Vector3.new(length, length * 0.59, length * 0.59)
	return prop(parent, "WreckCannon", ground, yaw, size, 0.12, CFrame.Angles(0, 0, tip), cannonStandin)
end

local function barrels(parent: Instance, ground: Vector3, yaw: number, length: number)
	prop(
		parent,
		"WreckBarrels",
		ground,
		yaw,
		Vector3.new(length, length * 0.45, length * 0.81),
		0.08,
		nil,
		barrelsStandin
	)
end

-- An anchor lying on the sand with `chainTo` (if given) run from its ring
local function anchor(parent: Instance, ground: Vector3, yaw: number, height: number, chainTo: Vector3?)
	local size = Vector3.new(height * 0.97, height, height * 1.1)
	local box =
		prop(parent, "WreckAnchor", ground, yaw, size, 0.35, CFrame.Angles(0, 0, math.rad(68)), anchorStandin)
	if chainTo then
		local ring = box:PointToWorldSpace(Vector3.new(0, size.Y * 0.4, 0))
		Kit.chain(stats, parent, ring, chainTo, 6, 2.6, IRON, groundOf)
	end
end

-- A lantern on a broken post (lit ones carry a light)
local function postLantern(parent: Instance, ground: Vector3, height: number, lit: boolean)
	local top = ground + Vector3.new(0, height, 0)
	Kit.part(
		stats,
		parent,
		"LanternPost",
		Vector3.new(1.4, height, 1.4),
		CFrame.new(ground + Vector3.new(0, height / 2 - 0.5, 0)) * CFrame.Angles(0.06, 0, -0.05),
		WOOD,
		false
	)
	Kit.part(
		stats,
		parent,
		"LanternArm",
		Vector3.new(3.2, 0.5, 0.5),
		CFrame.new(top + Vector3.new(1.4, -0.4, 0)),
		IRON,
		false
	)
	local glass = Kit.lantern(stats, parent, CFrame.new(top + Vector3.new(2.6, -2.2, 0)), 1.3, lit)
	if lit then
		Kit.light(stats, glass, CABIN_LIGHT, 26, 1.1)
	end
end

-- ---------------------------------------------------------------------------
-- The set pieces
-- ---------------------------------------------------------------------------

local function brokenGalleon(parent: Instance)
	local center = at(GALLEON.angle, GALLEON.r)
	local ground = floorAt(center.X, center.Z)
	-- Lengthwise round the bay (tangent to the hub), so both halves show from the hub
	local tangent = Vector3.new(-math.sin(math.rad(GALLEON.angle)), 0, math.cos(math.rad(GALLEON.angle)))
	local frame = CFrame.lookAt(ground, ground + tangent)
	local yaw = math.atan2(-tangent.X, -tangent.Z)
	local m = Instance.new("Model")
	m.Name = "BrokenGalleon"
	m.Parent = parent
	-- The bow, listing to starboard, its broken end toward the stern
	local bowAt = frame:PointToWorldSpace(Vector3.new(0, 0, -48))
	local bow = hull(
		m,
		"GalleonBow",
		bowAt,
		yaw,
		74,
		Vector3.new(1, 0.73, 0.43),
		math.rad(16),
		math.rad(-3),
		0.16,
		WOOD
	)
	-- The stern, its windows looking away, its broken end toward the bow, nose down
	local sternAt = frame:PointToWorldSpace(Vector3.new(0, 0, 40))
	local stern = hull(
		m,
		"GalleonStern",
		sternAt,
		yaw + math.pi,
		62,
		Vector3.new(1, 0.65, 0.4),
		math.rad(-7),
		math.rad(6),
		0.14,
		WOOD
	)
	-- The break: ribs snapped off and sticking up out of the sand, planks strewn
	local snap = Random.new(Config.World.seed + 913)
	for i = 1, 9 do
		local side = if i % 2 == 0 then 1 else -1
		local p =
			frame:PointToWorldSpace(Vector3.new(side * snap:NextNumber(4, 13), 0, snap:NextNumber(-14, 8)))
		local foot = floorAt(p.X, p.Z)
		local top = foot
			+ Vector3.new(snap:NextNumber(-3, 3), snap:NextNumber(9, 20), 0)
			+ frame.RightVector * side * snap:NextNumber(2, 6)
		if i <= 6 then
			Kit.rod(
				stats,
				m,
				"BrokenRib",
				foot - Vector3.new(0, 2, 0),
				top,
				snap:NextNumber(0.8, 1.3),
				WOOD_LIGHT,
				false
			)
		else
			Kit.part(
				stats,
				m,
				"Plank",
				Vector3.new(snap:NextNumber(10, 18), 0.8, snap:NextNumber(2, 3.5)),
				CFrame.new(foot + Vector3.new(0, 0.6, 0))
					* CFrame.Angles(0, snap:NextNumber(0, 6.28), snap:NextNumber(-0.2, 0.2)),
				WOOD,
				false
			)
		end
	end
	-- The cabin's lamps: a warm light outside its windows, and the dig site under them
	local windows = stern:PointToWorldSpace(Vector3.new(-31, 8, 0))
	local lamp = Kit.anchor(m, "CabinLight", CFrame.new(windows + (windows - sternAt).Unit * 4))
	Kit.light(stats, lamp, CABIN_LIGHT, 52, 1.6)
	local behind = sternAt + (windows - sternAt) * Vector3.new(1, 0, 1) * 1.55
	local dig = floorAt(behind.X, behind.Z)
	PlaceMarks.set("BrokenGalleon_Dig", dig)
	-- Anchors out ahead of the bow and off the stern's side, on chains
	local bowRing = bow:PointToWorldSpace(Vector3.new(-30, -6, 0))
	local a1 = frame:PointToWorldSpace(Vector3.new(-30, 0, -122))
	anchor(m, floorAt(a1.X, a1.Z), yaw + 0.6, 20, bowRing)
	local sternRing = stern:PointToWorldSpace(Vector3.new(0, -8, 12))
	local a2 = frame:PointToWorldSpace(Vector3.new(46, 0, 52))
	anchor(m, floorAt(a2.X, a2.Z), yaw - 1.1, 16, sternRing)
	-- Spilled from the gun deck round the break
	for _, spot in
		{
			Vector3.new(-17, 0, -6),
			Vector3.new(19, 0, 2),
			Vector3.new(24, 0, 14),
			Vector3.new(-22, 0, 18),
			Vector3.new(6, 0, -14),
		}
	do
		local p = frame:PointToWorldSpace(spot)
		cannon(m, floorAt(p.X, p.Z), yaw + spot.X * 0.13, 13, math.rad(spot.Z * 0.6))
	end
	for _, spot in { Vector3.new(-14, 0, 6), Vector3.new(16, 0, -20), Vector3.new(30, 0, 30) } do
		local p = frame:PointToWorldSpace(spot)
		barrels(m, floorAt(p.X, p.Z), yaw + spot.Z * 0.05, 15)
	end
	-- The figurehead, fallen on its side in front of the bow
	local f = frame:PointToWorldSpace(Vector3.new(14, 0, -98))
	prop(
		m,
		"WreckFigurehead",
		floorAt(f.X, f.Z),
		yaw - 0.4,
		Vector3.new(6.3, 17, 11.6),
		0.1,
		CFrame.Angles(0, 0, math.rad(74)),
		function(sm, box, size)
			Kit.part(stats, sm, "Carving", size * Vector3.new(0.8, 0.9, 0.7), box, TEAL, false)
		end
	)
	-- The ship's wheel and bell on a broken post behind the stern: BITE the bell
	local w = frame:PointToWorldSpace(Vector3.new(-18, 0, 92))
	local wheelGround = floorAt(w.X, w.Z)
	local post =
		prop(m, "WreckWheelBell", wheelGround, yaw + HALF, Vector3.new(5.3, 15, 10.2), 0.04, nil, postStandin)
	table.insert(Wrecks.bells, post:PointToWorldSpace(Vector3.new(0, 15 * 0.18, 10.2 * 0.32)))
	-- Lanterns on broken posts round the scene; the two by the break lit
	for i, spot in
		{ Vector3.new(-26, 0, -2), Vector3.new(26, 0, 24), Vector3.new(-30, 0, 70), Vector3.new(30, 0, -70) }
	do
		local p = frame:PointToWorldSpace(spot)
		postLantern(m, floorAt(p.X, p.Z), 9 + i, i <= 3)
	end
	PlaceMarks.set("BrokenGalleon", ground + Vector3.new(0, 20, 0))
	table.insert(landmarks, ground)
	table.insert(Wrecks.views, {
		name = "galleon",
		from = frame:PointToWorldSpace(Vector3.new(-110, 34, 30)),
		to = frame:PointToWorldSpace(Vector3.new(0, 14, -4)),
		fov = 70,
	})
	table.insert(Wrecks.views, {
		name = "cabin",
		from = frame:PointToWorldSpace(Vector3.new(-30, 20, 130)),
		to = frame:PointToWorldSpace(Vector3.new(0, 16, 50)),
		fov = 68,
	})
end

local function fallenLighthouse(parent: Instance)
	local center = at(LIGHTHOUSE.angle, LIGHTHOUSE.r)
	local ground = floorAt(center.X, center.Z)
	-- Lying with its lamp toward the galleon
	local galleon = at(GALLEON.angle, GALLEON.r)
	local toward = (galleon - center) * Vector3.new(1, 0, 1)
	local yaw = math.atan2(-toward.X, -toward.Z)
	local length = 104
	local m = Instance.new("Model")
	m.Name = "FallenLighthouse"
	m.Parent = parent
	-- The model's tower leans 42° in its GLB, its lamp up and toward -Z (+Z once the
	-- importer turns it half round): turned so that line lies level along the frame's
	-- look, lamp first, its base end sunk a little in the sand
	local size = Vector3.new(length * 0.57, length, length * 0.92)
	local frame = CFrame.new(ground) * CFrame.Angles(0, yaw, 0)
	local towerLine = Vector3.new(0.16, 0.74, 0.65).Unit
	local look = Vector3.new(0, 0, -1)
	local level = CFrame.fromAxisAngle(towerLine:Cross(look).Unit, math.acos(towerLine:Dot(look)))
	local box = frame * CFrame.new(0, 11, 0) * level
	Kit.hero(stats, m, "ToppledLighthouse", box, size, function(sm)
		-- Drums of stone, red and grey in turn, then the lamp room and its dome
		local radius = 13
		for i = 0, 6 do
			local a = frame:PointToWorldSpace(Vector3.new(0, radius * 0.7, 46 - i * 12))
			local b = frame:PointToWorldSpace(Vector3.new(0, radius * 0.7, 46 - (i + 1) * 12))
			Kit.rod(stats, sm, "Drum", a, b, radius - i * 0.7, if i % 2 == 0 then STRIPE else STONE, true)
		end
		local lampRoom = frame:PointToWorldSpace(Vector3.new(0, 9, -44))
		Kit.rod(
			stats,
			sm,
			"Gallery",
			lampRoom + frame.LookVector * 2,
			lampRoom - frame.LookVector * 2,
			10,
			IRON,
			false
		)
		Kit.glow(
			stats,
			sm,
			"LampGlass",
			Vector3.new(8, 12, 12),
			CFrame.lookAt(lampRoom - frame.LookVector * 6, lampRoom - frame.LookVector * 20)
				* CFrame.Angles(0, HALF, 0),
			Color3.fromRGB(120, 200, 190),
			Enum.PartType.Cylinder
		)
		Kit.rod(
			stats,
			sm,
			"Dome",
			lampRoom - frame.LookVector * 10,
			lampRoom - frame.LookVector * 15,
			6,
			BRONZE,
			false
		)
	end, { solid = true, blocksCamera = true })
	-- Its stones broken off at the base
	for i = 1, 5 do
		local p = frame:PointToWorldSpace(Vector3.new((i - 3) * 7, 0, 58 + (i % 2) * 6))
		local g = floorAt(p.X, p.Z)
		Kit.part(
			stats,
			m,
			"Block",
			Vector3.new(6, 4, 5),
			CFrame.new(g + Vector3.new(0, 1.4, 0)) * CFrame.Angles(0.3 * i, i, 0.2),
			STONE,
			true
		)
	end
	PlaceMarks.set("FallenLighthouse", ground + Vector3.new(0, 16, 0))
	table.insert(landmarks, ground)
	table.insert(Wrecks.views, {
		name = "lighthouse",
		from = frame:PointToWorldSpace(Vector3.new(110, 34, -10)),
		to = frame:PointToWorldSpace(Vector3.new(0, 10, -4)),
		fov = 70,
	})
end

local function steamers(parent: Instance)
	for i, spot in { STEAMER, TRAWLER } do
		local center = at(spot.angle, spot.r)
		local ground = floorAt(center.X, center.Z)
		local yaw = math.rad(spot.angle * 2.3 + 40)
		local length = if i == 1 then 74 else 46
		hull(
			parent,
			"IronSteamer",
			ground,
			yaw,
			length,
			Vector3.new(1, 0.78, 0.53),
			math.rad(if i == 1 then 9 else -14),
			0,
			0.18,
			RUST
		)
		table.insert(landmarks, ground)
	end
end

-- The Bay Cannon: a big gun on the sand at the bay's inner end, aimed over it at the
-- galleon; its muzzle and aim go to LandmarkService
local function bayCannon(parent: Instance)
	local spot = at(BAY_CANNON.angle, BAY_CANNON.r)
	local ground = floorAt(spot.X, spot.Z)
	local target = at(GALLEON.angle - 6, GALLEON.r - 10)
	local flat = ((target - spot) * Vector3.new(1, 0, 1)).Unit
	local yaw = math.atan2(-flat.X, -flat.Z)
	local length = 26
	local box = cannon(parent, ground, yaw, length, math.rad(-8))
	local muzzle = box:PointToWorldSpace(Vector3.new(-length * 0.55, length * 0.12, 0))
	local direction = (flat + Vector3.new(0, 0.22, 0)).Unit
	table.insert(Wrecks.cannons, { muzzle = muzzle, direction = direction })
	-- A lit lantern on each side so it's found
	for side = -1, 1, 2 do
		local p = box:PointToWorldSpace(Vector3.new(0, 0, side * 14))
		postLantern(parent, floorAt(p.X, p.Z), 10, true)
	end
	table.insert(landmarks, ground)
	table.insert(Wrecks.views, {
		name = "cannon",
		from = muzzle + flat * 40 + Vector3.new(14, 14, 20),
		to = muzzle - flat * 4,
		fov = 66,
	})
end

-- ---------------------------------------------------------------------------
-- The bay's scattered wrecks (WorldService's `wreck`, which keeps its draws on the
-- shared Random so nothing after it moves, hands them here)
-- ---------------------------------------------------------------------------

local KINDS = { "GalleonBow", "IronSteamer", "Debris", "GalleonStern", "IronSteamer", "GalleonBow", "Debris" }

function Wrecks.scatter(
	parent: Instance,
	ground: Vector3,
	length: number,
	yaw: number,
	tilt: number,
	index: number
)
	for _, spot in landmarks do
		if ((spot - ground) * Vector3.new(1, 0, 1)).Magnitude < KEEP_CLEAR then
			return -- (too near a set piece: left as open sand)
		end
	end
	local own = Random.new(Config.World.seed + 900 + index)
	local kind = KINDS[(index - 1) % #KINDS + 1]
	local m = Instance.new("Model")
	m.Name = "Wreck"
	m.Parent = parent
	local scale = length / 110 -- (the old hulls ran 60 to 110 long)
	if kind == "GalleonBow" then
		hull(
			m,
			kind,
			ground,
			yaw,
			46 + 30 * scale,
			Vector3.new(1, 0.73, 0.43),
			tilt * 1.4,
			own:NextNumber(-0.08, 0.05),
			0.24,
			WOOD
		)
	elseif kind == "GalleonStern" then
		hull(
			m,
			kind,
			ground,
			yaw,
			40 + 26 * scale,
			Vector3.new(1, 0.65, 0.4),
			tilt * 1.2,
			own:NextNumber(0.02, 0.12),
			0.22,
			WOOD
		)
	elseif kind == "IronSteamer" then
		hull(m, kind, ground, yaw, 38 + 28 * scale, Vector3.new(1, 0.78, 0.53), tilt, 0, 0.26, RUST)
	end
	-- Its spill: cannons, barrels, an anchor (a debris field is only these)
	local spread = if kind == "Debris" then 26 else 34 + length * 0.25
	for i = 1, if kind == "Debris" then 4 else 2 do
		local angle = own:NextNumber(0, math.pi * 2)
		local p = ground
			+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * own:NextNumber(spread * 0.6, spread)
		if i % 2 == 1 then
			cannon(
				m,
				floorAt(p.X, p.Z),
				own:NextNumber(0, math.pi * 2),
				own:NextNumber(10, 14),
				own:NextNumber(-0.4, 0.4)
			)
		else
			barrels(m, floorAt(p.X, p.Z), own:NextNumber(0, math.pi * 2), own:NextNumber(11, 16))
		end
	end
	if kind == "Debris" or own:NextNumber() < 0.5 then
		local angle = own:NextNumber(0, math.pi * 2)
		local p = ground + Vector3.new(math.cos(angle), 0, math.sin(angle)) * spread * 0.8
		anchor(m, floorAt(p.X, p.Z), own:NextNumber(0, math.pi * 2), own:NextNumber(12, 18), nil)
	end
	if own:NextNumber() < 0.6 then
		local angle = own:NextNumber(0, math.pi * 2)
		local p = ground + Vector3.new(math.cos(angle), 0, math.sin(angle)) * spread * 0.5
		postLantern(m, floorAt(p.X, p.Z), own:NextNumber(7, 11), own:NextNumber() < 0.4)
	end
end

-- Builds the set pieces (before WorldService scatters the wrecks, which keep clear of
-- them). Returns what it made.
function Wrecks.build(parent: Instance, ground: Kit.Ground): Kit.Stats
	stats = Kit.stats()
	groundOf = ground
	table.clear(landmarks)
	table.clear(Wrecks.cannons)
	table.clear(Wrecks.bells)
	table.clear(Wrecks.views)
	brokenGalleon(parent)
	fallenLighthouse(parent)
	steamers(parent)
	bayCannon(parent)
	return stats
end

-- The running totals (the scattered wrecks add to them after `build`)
function Wrecks.stats(): Kit.Stats
	return stats
end

return Wrecks
