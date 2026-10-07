--!strict
-- The seafloor as Roblox Terrain (owner, 2026-10-07: the old trench was "a giant
-- gaping hole", the map "far too open", and biomes must sit at different depths off
-- an ocean shelf). A list of fill operations, like Cave.luau, so the same list runs
-- in Studio (Terrain:Fill*) and in the cloud preview (tools/preview/run_world.sh):
--   bedrock and a dark deep floor under everything;
--   the SHELF, a sandy plateau round the hub, with dunes, outcrops, ridges and reef
--   flats for the shallow biomes;
--   the DROP-OFF, a rock cliff round the shelf, bitten with notches and buttresses,
--   with sand chutes sloping down it;
--   the TRENCH, a winding canyon cut deep into the floor to the south, with ragged
--   walls and slate rims;
--   the VENTS' basin to the south-west with basalt chimneys (glowing caps);
--   the RUINS' mounds, column stubs and walls to the east;
--   and the Open Blue's ridges and pinnacles to the north.
-- Heights follow Shared/Seafloor.luau, so placement code agrees with the ground.
-- `Shelf.ops()` also returns the features WorldService dresses (chimneys,
-- pinnacles, chutes).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Cave = require(script.Parent.Cave)

local World = Config.World
local shelf = World.shelf
local deep = World.deep
local trench = World.trench

type Op = Cave.Op

export type Features = {
	chimneys: { { position: Vector3, height: number } },
	pinnacles: { Vector3 },
	chutes: { number }, -- angles (degrees)
	ruinAnchors: { Vector3 },
}

local Shelf = {}

-- Terrain material colors beyond Cave.COLORS (the deep floor and the vents' glow)
Shelf.COLORS = {
	[Enum.Material.Mud] = Color3.fromRGB(54, 58, 66),
	[Enum.Material.CrackedLava] = Color3.fromRGB(255, 120, 40),
}

local SAND = Enum.Material.Sand
local ROCK = Enum.Material.Rock
local SLATE = Enum.Material.Slate
local SANDSTONE = Enum.Material.Sandstone
local BASALT = Enum.Material.Basalt
local MUD = Enum.Material.Mud
local LAVA = Enum.Material.CrackedLava
local AIR = Enum.Material.Air

local function ball(ops: { Op }, material: Enum.Material, center: Vector3, radius: number)
	table.insert(ops, { kind = "ball", material = material, center = center, radius = radius })
end

local function block(ops: { Op }, material: Enum.Material, cframe: CFrame, size: Vector3)
	table.insert(
		ops,
		{ kind = "block", material = material, center = cframe.Position, size = size, cframe = cframe }
	)
end

local function cylinder(
	ops: { Op },
	material: Enum.Material,
	center: Vector3,
	radius: number,
	height: number,
	cframe: CFrame?
)
	table.insert(ops, {
		kind = "cylinder",
		material = material,
		center = center,
		radius = radius,
		height = height,
		cframe = cframe or CFrame.new(center),
	})
end

local function outward(angleDeg: number): Vector3
	local a = math.rad(angleDeg)
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

local function at(angleDeg: number, r: number, y: number): Vector3
	return World.hub.center + outward(angleDeg) * r + Vector3.new(0, y, 0)
end

local function sectorAngle(rng: Random, from: number, to: number): number
	return (from + rng:NextNumber(0, (to - from) % 360)) % 360
end

function Shelf.ops(): ({ Op }, Features)
	local ops: { Op } = {}
	local rng = Random.new(World.seed + 7)
	local features: Features = { chimneys = {}, pinnacles = {}, chutes = {}, ruinAnchors = {} }
	local floor = deep.floorY
	local hubClear = World.hub.radius + World.hub.wallThickness + World.hub.tunnelLength + 20

	-- Bedrock under everything, then the dark deep floor on top of it
	-- (they run far past the barrier, so the floor fades into the fog instead of ending)
	local far = World.boundsRadius + 700
	cylinder(
		ops,
		ROCK,
		Vector3.new(0, (trench.floorY - 30 + floor - 30) / 2, 0),
		far,
		(floor - 30) - (trench.floorY - 30)
	)
	cylinder(ops, MUD, Vector3.new(0, floor - 15, 0), far, 30)

	-- The shelf: a rock drum with a sand cap, its rim a little wider than the sand so
	-- a rock lip shows at the drop-off
	local drumTop = -28
	cylinder(
		ops,
		ROCK,
		Vector3.new(0, (floor - 2 + drumTop) / 2, 0),
		shelf.radius + 40,
		drumTop - (floor - 2)
	)
	cylinder(ops, SAND, Vector3.new(0, -16, 0), shelf.radius + 20, 32)

	-- The drop-off: the rim bulges and bays so it isn't a perfect circle, then
	-- notches bitten out of the cliff, buttresses bulging from it, and sandstone
	-- ledges clinging to it
	local rim = shelf.radius + 40
	for _ = 1, 10 do
		local angle = rng:NextNumber(0, 360)
		local radius = rng:NextNumber(55, 95)
		ball(ops, ROCK, at(angle, rim - 10, -radius * 0.9), radius)
		ball(ops, SAND, at(angle, rim - 30, -radius * 0.95 + 8), radius * 0.8)
	end
	for _ = 1, 8 do
		local angle = rng:NextNumber(0, 360)
		if Seafloor.inSector(angle, trench.angles[1] - 15, trench.angles[2] + 15) then
			continue
		end
		ball(ops, AIR, at(angle, rim + 40, rng:NextNumber(-120, -40)), rng:NextNumber(50, 75))
	end
	for _ = 1, 90 do
		local angle = rng:NextNumber(0, 360)
		ball(
			ops,
			AIR,
			at(angle, rim + rng:NextNumber(-8, 26), rng:NextNumber(-150, -14)),
			rng:NextNumber(18, 42)
		)
	end
	for _ = 1, 70 do
		local angle = rng:NextNumber(0, 360)
		ball(
			ops,
			ROCK,
			at(angle, rim - 8 + rng:NextNumber(0, 34), rng:NextNumber(-166, -36)),
			rng:NextNumber(14, 36)
		)
	end
	for _ = 1, 24 do
		local angle = rng:NextNumber(0, 360)
		cylinder(
			ops,
			SANDSTONE,
			at(angle, rim + 6 + rng:NextNumber(0, 20), rng:NextNumber(-140, -30)),
			rng:NextNumber(18, 34),
			8
		)
	end
	-- Sand chutes down the cliff (never through the trench's sector)
	for _, angle in { 20, 160, 200, 250, 292, 340 } do
		local top = at(angle, shelf.radius - 10, -2)
		local foot = at(angle, shelf.radius + shelf.edge + 70, floor + 2)
		local run = foot - top
		local center = (top + foot) / 2
		local frame = CFrame.lookAt(center, center + run.Unit)
		block(ops, SAND, frame, Vector3.new(74, 16, run.Magnitude + 20))
		ball(ops, SAND, foot + Vector3.new(0, -14, 0), 46)
		table.insert(features.chutes, angle)
	end

	-- Shelf relief: dunes everywhere, outcrops where the reef and the wrecks are,
	-- sandstone ridges through the kelp, and reef flats for the corals to sit on
	for _ = 1, 110 do
		local r = rng:NextNumber(hubClear, shelf.radius - 20)
		local radius = rng:NextNumber(24, 70)
		ball(ops, SAND, at(rng:NextNumber(0, 360), r, -radius * 0.8), radius)
	end
	for _ = 1, 44 do
		local angle = rng:NextNumber(0, 360)
		local r = rng:NextNumber(350, shelf.radius - 24)
		local size = Vector3.new(rng:NextNumber(18, 48), rng:NextNumber(10, 26), rng:NextNumber(18, 48))
		local frame = CFrame.new(at(angle, r, -size.Y * 0.35))
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3))
		block(ops, ROCK, frame, size)
	end
	for _ = 1, 18 do
		local angle = rng:NextNumber(0, 360)
		local r = rng:NextNumber(hubClear + 20, 330)
		local size = Vector3.new(rng:NextNumber(70, 150), 12, rng:NextNumber(16, 26))
		block(
			ops,
			SANDSTONE,
			CFrame.new(at(angle, r, -4)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			size
		)
	end
	for _ = 1, 20 do
		local angle = sectorAngle(rng, 225, 135) -- the Coral Reef's band
		local r = rng:NextNumber(360, shelf.radius - 40)
		cylinder(ops, SANDSTONE, at(angle, r, -2), rng:NextNumber(25, 50), 10)
	end
	-- Reef heads: big rocks players swim through and under (owner, 2026-10-07: "larger
	-- rocks that players can swim through and swim under"): a boulder with a tunnel
	-- bored through it and a hollow underneath, and stone arches on two legs
	for _ = 1, 16 do
		local angle = sectorAngle(rng, 228, 132)
		local r = rng:NextNumber(370, shelf.radius - 50)
		local radius = rng:NextNumber(24, 42)
		local center = at(angle, r, radius * 0.45)
		ball(ops, ROCK, center, radius)
		local yaw = rng:NextNumber(0, 6.28)
		local through = CFrame.new(center + Vector3.new(0, -radius * 0.1, 0))
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(0, 0, math.rad(90))
		cylinder(ops, AIR, through.Position, rng:NextNumber(7, 10), radius * 2.4, through)
		ball(ops, AIR, center + Vector3.new(0, -radius * 0.55, 0), radius * 0.55)
	end
	for _ = 1, 10 do
		local angle = sectorAngle(rng, 228, 132)
		local r = rng:NextNumber(380, shelf.radius - 50)
		local yaw = rng:NextNumber(0, 6.28)
		local span = rng:NextNumber(26, 44)
		local height = rng:NextNumber(18, 30)
		local frame = CFrame.new(at(angle, r, 0)) * CFrame.Angles(0, yaw, 0)
		for side = -1, 1, 2 do
			local leg = (frame * CFrame.new(side * span / 2, height / 2 - 4, 0)).Position
			cylinder(ops, ROCK, leg, rng:NextNumber(6, 9), height + 8)
		end
		block(ops, ROCK, frame * CFrame.new(0, height + 2, 0), Vector3.new(span + 18, 10, 14))
	end

	-- The Trench: a winding canyon carved down to its floor, basalt at the bottom,
	-- bitten walls and slate rims
	local midAngle = (trench.angles[1] + trench.angles[2]) / 2
	local steps = 14
	for i = 0, steps do
		local t = i / steps
		local r = trench.radii[1] + t * (trench.radii[2] - trench.radii[1])
		local angle = midAngle + math.sin(t * 5.5) * 3.5
		local taper = 1 - math.abs(t - 0.5) * 0.5 -- narrower at both ends
		local width = trench.width * taper
		-- A V profile: wide at the rim, narrow at the floor, in three stacked cuts
		local span = (floor + 10) - (trench.floorY - 10)
		for layer = 0, 2 do
			local top = floor + 10 - layer * span / 3
			local bottom = top - span / 3
			local layerWidth = width + 70 + (2 - layer) * 55
			local center = at(angle, r, (top + bottom) / 2)
			local frame = CFrame.lookAt(center, center + outward(angle))
			block(ops, AIR, frame, Vector3.new(layerWidth, top - bottom + 2, 46))
		end
		if i == 0 or i == steps then
			ball(ops, AIR, at(angle, r, (floor + trench.floorY) / 2), width * 0.5 + 40)
		end
		block(
			ops,
			BASALT,
			CFrame.lookAt(at(angle, r, trench.floorY - 6), at(angle, r + 1, trench.floorY - 6)),
			Vector3.new(width + 50, 12, 50)
		)
		for side = -1, 1, 2 do
			local acrossDeg = math.deg((width / 2 + 30 + rng:NextNumber(0, 24)) / r)
			ball(
				ops,
				AIR,
				at(angle + side * acrossDeg, r, rng:NextNumber(-400, -190)),
				rng:NextNumber(18, 40)
			)
			local rimDeg = math.deg((width / 2 + 62) / r)
			ball(
				ops,
				SLATE,
				at(angle + side * rimDeg, r + rng:NextNumber(-10, 10), floor - 6 + rng:NextNumber(0, 10)),
				rng:NextNumber(14, 30)
			)
		end
	end

	-- The Vents' basin: hollows sunk below the deep floor, basalt floored, with
	-- chimneys whose caps glow
	for _ = 1, 7 do
		local angle = sectorAngle(rng, deep.ventsAngles[1], deep.ventsAngles[2])
		local r = rng:NextNumber(deep.ventsRadii[1] + 40, deep.ventsRadii[2] - 40)
		local radius = rng:NextNumber(70, 120)
		cylinder(
			ops,
			AIR,
			at(angle, r, (deep.ventsFloorY + floor + 4) / 2),
			radius,
			(floor + 4) - deep.ventsFloorY
		)
		cylinder(ops, BASALT, at(angle, r, deep.ventsFloorY - 6), radius + 6, 12)
	end
	for _ = 1, 14 do
		local angle = sectorAngle(rng, deep.ventsAngles[1] + 4, deep.ventsAngles[2] - 4)
		local r = rng:NextNumber(deep.ventsRadii[1] + 20, deep.ventsRadii[2] - 20)
		local x, z = at(angle, r, 0).X, at(angle, r, 0).Z
		local base = Seafloor.y(x, z)
		local height = rng:NextNumber(26, 70)
		cylinder(ops, BASALT, Vector3.new(x, base + height / 2, z), rng:NextNumber(5, 11), height)
		ball(ops, LAVA, Vector3.new(x, base + height, z), rng:NextNumber(4, 7))
		table.insert(features.chimneys, { position = Vector3.new(x, base, z), height = height })
	end

	-- The Sunken Ruins: buried mounds, column stubs, plinths and broken walls
	for _ = 1, 30 do
		local angle = sectorAngle(rng, 320, 62)
		local r = rng:NextNumber(shelf.radius + shelf.edge + 30, World.boundsRadius - 50)
		local radius = rng:NextNumber(18, 40)
		ball(ops, SANDSTONE, at(angle, r, floor - radius * 0.7), radius)
	end
	for _ = 1, 24 do
		local angle = sectorAngle(rng, 318, 64)
		local r = rng:NextNumber(shelf.radius + shelf.edge + 40, World.boundsRadius - 60)
		local height = rng:NextNumber(18, 46)
		cylinder(ops, SANDSTONE, at(angle, r, floor + height / 2 - 2), rng:NextNumber(4, 7), height)
	end
	for _ = 1, 10 do
		local angle = sectorAngle(rng, 320, 62)
		local r = rng:NextNumber(shelf.radius + shelf.edge + 50, World.boundsRadius - 70)
		local anchor = at(angle, r, floor)
		block(
			ops,
			SANDSTONE,
			CFrame.new(anchor + Vector3.new(0, 3, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			Vector3.new(40, 8, 40)
		)
		table.insert(features.ruinAnchors, anchor)
	end
	for _ = 1, 8 do
		local angle = sectorAngle(rng, 320, 62)
		local r = rng:NextNumber(shelf.radius + shelf.edge + 40, World.boundsRadius - 60)
		block(
			ops,
			SANDSTONE,
			CFrame.new(at(angle, r, floor + 12))
				* CFrame.Angles(0, rng:NextNumber(0, 6.28), rng:NextNumber(-0.15, 0.15)),
			Vector3.new(60, 26, 6)
		)
	end

	-- The Open Blue: long mud ridges and rock pinnacles for the Megalodon to circle
	for _ = 1, 8 do
		local angle = sectorAngle(rng, 228, 312)
		local r = rng:NextNumber(shelf.radius + shelf.edge + 40, World.boundsRadius - 60)
		local radius = rng:NextNumber(60, 110)
		ball(ops, MUD, at(angle, r, floor - radius * 0.85), radius)
	end
	for _ = 1, 3 do
		local angle = sectorAngle(rng, 235, 305)
		local r = rng:NextNumber(shelf.radius + shelf.edge + 90, World.boundsRadius - 120)
		local height = rng:NextNumber(110, 140)
		local base = at(angle, r, floor)
		cylinder(ops, ROCK, base + Vector3.new(0, height / 2 - 4, 0), rng:NextNumber(22, 30), height)
		ball(ops, ROCK, base + Vector3.new(0, height - 4, 0), rng:NextNumber(18, 26))
		table.insert(features.pinnacles, base + Vector3.new(0, height, 0))
	end

	-- Debris that slid off the Wreck's side of the shelf
	for _ = 1, 20 do
		local angle = sectorAngle(rng, 135, 225)
		local r = rng:NextNumber(shelf.radius + shelf.edge + 10, shelf.radius + shelf.edge + 110)
		ball(ops, ROCK, at(angle, r, floor - 4), rng:NextNumber(10, 25))
	end

	return ops, features
end

function Shelf.apply(terrain: Terrain, ops: { Op })
	for material, color in Shelf.COLORS do
		terrain:SetMaterialColor(material, color)
	end
	Cave.apply(terrain, ops)
end

return Shelf
