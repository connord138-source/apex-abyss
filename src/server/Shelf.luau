--!strict
-- The seafloor as Roblox Terrain (owner, 2026-10-07: the old trench was "a giant
-- gaping hole", the map "far too open", and biomes must sit at different depths off
-- an ocean shelf; 2026-10-08: "the entirety of the map is still too small ... each
-- biome made larger ... MUCH MUCH more depth", "the lower areas are far too
-- underdeveloped", "coral reef needs more larger rock structures and arches to go
-- under"). A list of fill operations, like Cave.luau, so the same list runs in
-- Studio (Terrain:Fill*) and in the cloud preview (tools/preview/run_world.sh):
--   a mud floor slab under everything (rock only where something is carved below it,
--   so the Terrain stays light at this size);
--   the SHELF, a sandy plateau round the hub (a hollow rock drum with a thick top),
--   with dunes, outcrops, ridges and reef flats for the shallow biomes;
--   the DROP-OFF, a rock cliff round the shelf, bitten with notches and buttresses,
--   with sand chutes sloping down it;
--   the REEF's heads, ridges and arches: rocks to swim through and under;
--   the TRENCH, a winding canyon cut deep into the floor to the south, with ragged
--   walls, slate rims, ledges and basalt pillars;
--   the VENTS' basins to the south-west with basalt chimneys (glowing caps);
--   the RUINS' mounds, column stubs, walls and a temple ring to the east;
--   and the Open Blue's ridges, knolls and pinnacles to the north.
-- Heights follow Shared/Seafloor.luau, so placement code agrees with the ground.
-- `Shelf.ops()` also returns the features WorldService dresses (chimneys,
-- pinnacles, chutes, ruin anchors, reef rocks).
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
	reefRocks: { { center: Vector3, radius: number } }, -- heads and ridges the corals grow on
}

local Shelf = {}

-- Terrain material colors beyond Cave.COLORS (the deep floor and the vents' glow).
-- The deep floor is a blue-grey, never black: the Open Blue must read as deep blue
-- water over a blue floor (owner, 2026-10-08: "a large black wasteland")
Shelf.COLORS = {
	[Enum.Material.Mud] = Color3.fromRGB(44, 60, 84),
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
	local span = (to - from) % 360
	return (from + rng:NextNumber(0, if span == 0 then 360 else span)) % 360
end

function Shelf.ops(): ({ Op }, Features)
	local ops: { Op } = {}
	local rng = Random.new(World.seed + 7)
	local features: Features =
		{ chimneys = {}, pinnacles = {}, chutes = {}, ruinAnchors = {}, reefRocks = {} }
	local floor = deep.floorY
	local hubClear = World.hub.radius + World.hub.wallThickness + World.hub.tunnelLength + 20
	local deepInner = shelf.radius + shelf.edge -- the foot of the drop-off
	local far = World.boundsRadius + 700 -- the floor runs past the barrier so it fades into the water, not an edge

	-- The deep floor: a mud slab (the map is big; a solid bedrock would be tens of
	-- millions of voxels). Rock goes under it only where the canyon and the basins
	-- are carved below the floor.
	local slabTop, slabBottom = floor, floor - 30
	cylinder(ops, MUD, Vector3.new(0, (slabTop + slabBottom) / 2, 0), far, slabTop - slabBottom)
	local trenchRockBottom = trench.floorY - 30
	cylinder(
		ops,
		ROCK,
		Vector3.new(trench.center.X, (slabBottom + 2 + trenchRockBottom) / 2, trench.center.Z),
		400,
		slabBottom + 2 - trenchRockBottom
	)
	for _, basin in Seafloor.ventBasins() do
		local bottom = deep.ventsFloorY - 30
		cylinder(
			ops,
			ROCK,
			Vector3.new(basin.x, (slabBottom + 2 + bottom) / 2, basin.z),
			basin.radius + 50,
			slabBottom + 2 - bottom
		)
	end

	-- The shelf: a hollow rock drum (its wall 110 thick, its top 54 thick) with a
	-- sand cap, the rim a little wider than the sand so a rock lip shows at the
	-- drop-off. Nothing can get inside the drum, so the hollow costs nothing to look at.
	local drumTop = -28
	local rim = shelf.radius + 40
	cylinder(ops, ROCK, Vector3.new(0, (floor - 2 + drumTop) / 2, 0), rim, drumTop - (floor - 2))
	cylinder(
		ops,
		AIR,
		Vector3.new(0, (floor + 4 + drumTop - 52) / 2, 0),
		rim - 110,
		(drumTop - 52) - (floor + 4)
	)
	cylinder(ops, SAND, Vector3.new(0, -16, 0), shelf.radius + 20, 32)

	-- The drop-off: the rim bulges and bays so it isn't a perfect circle, then
	-- notches bitten out of the cliff, buttresses bulging from it, and sandstone
	-- ledges clinging to it
	for _ = 1, 16 do
		local angle = rng:NextNumber(0, 360)
		local radius = rng:NextNumber(60, 100)
		ball(ops, ROCK, at(angle, rim - 10, -radius * 0.9), radius)
		ball(ops, SAND, at(angle, rim - 30, -radius * 0.95 + 8), radius * 0.8)
	end
	for _ = 1, 12 do
		local angle = rng:NextNumber(0, 360)
		if Seafloor.inSector(angle, trench.angles[1] - 15, trench.angles[2] + 15) then
			continue
		end
		ball(ops, AIR, at(angle, rim + 40, rng:NextNumber(-200, -60)), rng:NextNumber(50, 75))
	end
	for _ = 1, 140 do
		local angle = rng:NextNumber(0, 360)
		ball(
			ops,
			AIR,
			at(angle, rim + rng:NextNumber(-8, 26), rng:NextNumber(-380, -14)),
			rng:NextNumber(18, 44)
		)
	end
	for _ = 1, 110 do
		local angle = rng:NextNumber(0, 360)
		ball(
			ops,
			ROCK,
			at(angle, rim - 8 + rng:NextNumber(0, 40), rng:NextNumber(-410, -36)),
			rng:NextNumber(14, 40)
		)
	end
	for _ = 1, 40 do
		local angle = rng:NextNumber(0, 360)
		cylinder(
			ops,
			SANDSTONE,
			at(angle, rim + 6 + rng:NextNumber(0, 24), rng:NextNumber(-360, -30)),
			rng:NextNumber(18, 38),
			8
		)
	end
	-- Sand chutes down the cliff (never through the trench's sector)
	for _, angle in { 20, 55, 160, 200, 250, 292, 320, 340 } do
		local top = at(angle, shelf.radius - 10, -2)
		local foot = at(angle, deepInner + 110, floor + 2)
		local run = foot - top
		local center = (top + foot) / 2
		local frame = CFrame.lookAt(center, center + run.Unit)
		block(ops, SAND, frame, Vector3.new(80, 16, run.Magnitude + 20))
		ball(ops, SAND, foot + Vector3.new(0, -16, 0), 56)
		table.insert(features.chutes, angle)
	end

	-- Shelf relief: dunes everywhere, outcrops where the reef and the wrecks are,
	-- sandstone ridges through the kelp, and reef flats for the corals to sit on
	for _ = 1, 170 do
		local r = rng:NextNumber(hubClear, shelf.radius - 20)
		local radius = rng:NextNumber(24, 72)
		ball(ops, SAND, at(rng:NextNumber(0, 360), r, -radius * 0.8), radius)
	end
	for _ = 1, 70 do
		local angle = rng:NextNumber(0, 360)
		local r = rng:NextNumber(490, shelf.radius - 24)
		local size = Vector3.new(rng:NextNumber(18, 52), rng:NextNumber(10, 28), rng:NextNumber(18, 52))
		local frame = CFrame.new(at(angle, r, -size.Y * 0.35))
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3))
		block(ops, ROCK, frame, size)
	end
	for _ = 1, 26 do
		local angle = rng:NextNumber(0, 360)
		local r = rng:NextNumber(hubClear + 20, 470)
		local size = Vector3.new(rng:NextNumber(70, 160), 12, rng:NextNumber(16, 28))
		block(
			ops,
			SANDSTONE,
			CFrame.new(at(angle, r, -4)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			size
		)
	end
	for _ = 1, 36 do
		local angle = sectorAngle(rng, 225, 135) -- the Coral Reef's band
		local r = rng:NextNumber(500, shelf.radius - 40)
		cylinder(ops, SANDSTONE, at(angle, r, -2), rng:NextNumber(25, 55), 10)
	end
	-- Reef heads: big rocks players swim through and under (owner, 2026-10-07: "larger
	-- rocks that players can swim through and swim under"; 2026-10-08: "more larger
	-- rock structures and arches to go under"): a boulder with a tunnel bored through
	-- it and a hollow underneath, long ridges with swim-throughs, and stone arches
	for _ = 1, 44 do
		local angle = sectorAngle(rng, 228, 132)
		local r = rng:NextNumber(520, shelf.radius - 50)
		local radius = rng:NextNumber(26, 48)
		local center = at(angle, r, radius * 0.45)
		ball(ops, ROCK, center, radius)
		local yaw = rng:NextNumber(0, 6.28)
		local through = CFrame.new(center + Vector3.new(0, -radius * 0.1, 0))
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(0, 0, math.rad(90))
		cylinder(ops, AIR, through.Position, rng:NextNumber(8, 12), radius * 2.4, through)
		ball(ops, AIR, center + Vector3.new(0, -radius * 0.55, 0), radius * 0.55)
		table.insert(features.reefRocks, { center = center, radius = radius })
	end
	for _ = 1, 14 do
		local angle = sectorAngle(rng, 230, 130)
		local r = rng:NextNumber(540, shelf.radius - 60)
		local length = rng:NextNumber(80, 160)
		local height = rng:NextNumber(22, 38)
		local thick = rng:NextNumber(26, 42)
		local yaw = rng:NextNumber(0, 6.28)
		local frame = CFrame.new(at(angle, r, height * 0.35 - 4)) * CFrame.Angles(0, yaw, 0)
		block(ops, ROCK, frame, Vector3.new(length, height, thick))
		ball(ops, ROCK, (frame * CFrame.new(length * 0.4, height * 0.2, 0)).Position, thick * 0.7)
		ball(ops, ROCK, (frame * CFrame.new(-length * 0.4, height * 0.1, 0)).Position, thick * 0.6)
		-- One or two swim-throughs bored across the ridge
		for bore = 1, rng:NextInteger(1, 2) do
			local along = (bore - 1.5) * length * 0.4 + rng:NextNumber(-10, 10)
			local hole = frame * CFrame.new(along, height * 0.1, 0) * CFrame.Angles(math.rad(90), 0, 0)
			cylinder(ops, AIR, hole.Position, rng:NextNumber(8, 11), thick + 30, hole)
		end
		table.insert(features.reefRocks, { center = frame.Position, radius = length / 2 })
	end
	for _ = 1, 26 do
		local angle = sectorAngle(rng, 228, 132)
		local r = rng:NextNumber(520, shelf.radius - 50)
		local yaw = rng:NextNumber(0, 6.28)
		local span = rng:NextNumber(34, 60)
		local height = rng:NextNumber(22, 40)
		local frame = CFrame.new(at(angle, r, 0)) * CFrame.Angles(0, yaw, 0)
		for side = -1, 1, 2 do
			local leg = (frame * CFrame.new(side * span / 2, height / 2 - 4, 0)).Position
			cylinder(ops, ROCK, leg, rng:NextNumber(7, 11), height + 8)
		end
		block(ops, ROCK, frame * CFrame.new(0, height + 2, 0), Vector3.new(span + 20, 11, 16))
	end

	-- The Trench: a winding canyon carved down to its floor in three stepped cuts
	-- (Seafloor.trenchAxis and trenchHalfWidths place them), basalt at the bottom,
	-- bitten walls, slate rims, ledges jutting from the walls and basalt pillars
	-- standing in it
	local steps = 20
	local span = (floor + 10) - (trench.floorY - 10)
	for i = 0, steps do
		local t = i / steps
		local r = trench.radii[1] + t * (trench.radii[2] - trench.radii[1])
		local angle, width = Seafloor.trenchAxis(r)
		local halfTop, halfMid, halfBottom = Seafloor.trenchHalfWidths(width)
		local halves = { halfTop, halfMid, halfBottom }
		for layer = 0, 2 do
			local top = floor + 10 - layer * span / 3
			local bottom = top - span / 3
			local center = at(angle, r, (top + bottom) / 2)
			local frame = CFrame.lookAt(center, center + outward(angle))
			block(ops, AIR, frame, Vector3.new(halves[layer + 1] * 2, top - bottom + 2, 46))
		end
		if i == 0 or i == steps then
			ball(ops, AIR, at(angle, r, (floor + trench.floorY) / 2), halfMid)
		end
		block(
			ops,
			BASALT,
			CFrame.lookAt(at(angle, r, trench.floorY - 6), at(angle, r + 1, trench.floorY - 6)),
			Vector3.new(halfBottom * 2 + 40, 12, 50)
		)
		for side = -1, 1, 2 do
			local acrossDeg = math.deg((rng:NextNumber(halfBottom + 10, halfTop - 24)) / r)
			ball(
				ops,
				AIR,
				at(angle + side * acrossDeg, r, rng:NextNumber(trench.floorY + 30, floor - 50)),
				rng:NextNumber(20, 48)
			)
			local rimDeg = math.deg((halfTop + 14) / r)
			ball(
				ops,
				SLATE,
				at(angle + side * rimDeg, r + rng:NextNumber(-10, 10), floor - 6 + rng:NextNumber(0, 12)),
				rng:NextNumber(16, 34)
			)
		end
	end
	for _ = 1, 12 do
		local r = rng:NextNumber(trench.radii[1] + 40, trench.radii[2] - 40)
		local angle, width = Seafloor.trenchAxis(r)
		local _, halfMid = Seafloor.trenchHalfWidths(width)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local ledge =
			at(angle + side * math.deg((halfMid - 6) / r), r, rng:NextNumber(trench.floorY + 120, floor - 90))
		block(
			ops,
			SLATE,
			CFrame.lookAt(ledge, ledge + outward(angle)) * CFrame.Angles(0, 0, side * math.rad(8)),
			Vector3.new(rng:NextNumber(50, 90), 10, rng:NextNumber(40, 70))
		)
	end
	for _ = 1, 8 do
		local r = rng:NextNumber(trench.radii[1] + 60, trench.radii[2] - 60)
		local _, width = Seafloor.trenchAxis(r)
		local _, _, halfBottom = Seafloor.trenchHalfWidths(width)
		local x, z = Seafloor.trenchPoint(r, rng:NextNumber(-halfBottom * 0.6, halfBottom * 0.6))
		local height = rng:NextNumber(70, 170)
		cylinder(
			ops,
			BASALT,
			Vector3.new(x, trench.floorY + height / 2 - 6, z),
			rng:NextNumber(8, 16),
			height
		)
		ball(ops, BASALT, Vector3.new(x, trench.floorY + height - 8, z), rng:NextNumber(9, 15))
	end

	-- The Vents' basins: hollows sunk below the deep floor, basalt floored, with
	-- chimneys whose caps glow
	for _, basin in Seafloor.ventBasins() do
		local center = Vector3.new(basin.x, 0, basin.z)
		cylinder(
			ops,
			AIR,
			center + Vector3.new(0, (deep.ventsFloorY + floor + 4) / 2, 0),
			basin.radius,
			(floor + 4) - deep.ventsFloorY
		)
		cylinder(ops, BASALT, center + Vector3.new(0, deep.ventsFloorY - 6, 0), basin.radius + 8, 12)
		-- Rubble round the lip
		for _ = 1, 4 do
			local a = rng:NextNumber(0, 6.28)
			ball(
				ops,
				BASALT,
				center
					+ Vector3.new(
						math.cos(a) * (basin.radius + 10),
						floor - 6,
						math.sin(a) * (basin.radius + 10)
					),
				rng:NextNumber(12, 26)
			)
		end
	end
	for _ = 1, 26 do
		local angle = sectorAngle(rng, deep.ventsAngles[1] + 4, deep.ventsAngles[2] - 4)
		local r = rng:NextNumber(deep.ventsRadii[1] + 20, deep.ventsRadii[2] - 20)
		local x, z = at(angle, r, 0).X, at(angle, r, 0).Z
		local base = Seafloor.y(x, z)
		local height = rng:NextNumber(30, 95)
		cylinder(ops, BASALT, Vector3.new(x, base + height / 2, z), rng:NextNumber(5, 12), height)
		ball(ops, LAVA, Vector3.new(x, base + height, z), rng:NextNumber(4, 8))
		table.insert(features.chimneys, { position = Vector3.new(x, base, z), height = height })
	end

	-- The Sunken Ruins: buried mounds, column stubs, plinths, broken walls and a
	-- temple ring on a raised floor
	local ruinInner, ruinOuter = deepInner + 30, World.boundsRadius - 50
	for _ = 1, 50 do
		local angle = sectorAngle(rng, 320, 62)
		local r = rng:NextNumber(ruinInner, ruinOuter)
		local radius = rng:NextNumber(18, 44)
		ball(ops, SANDSTONE, at(angle, r, floor - radius * 0.7), radius)
	end
	for _ = 1, 40 do
		local angle = sectorAngle(rng, 318, 64)
		local r = rng:NextNumber(ruinInner + 10, ruinOuter - 10)
		local height = rng:NextNumber(18, 50)
		cylinder(ops, SANDSTONE, at(angle, r, floor + height / 2 - 2), rng:NextNumber(4, 7), height)
	end
	for _ = 1, 16 do
		local angle = sectorAngle(rng, 320, 62)
		local r = rng:NextNumber(ruinInner + 20, ruinOuter - 20)
		local anchor = at(angle, r, floor)
		block(
			ops,
			SANDSTONE,
			CFrame.new(anchor + Vector3.new(0, 3, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			Vector3.new(40, 8, 40)
		)
		table.insert(features.ruinAnchors, anchor)
	end
	for _ = 1, 14 do
		local angle = sectorAngle(rng, 320, 62)
		local r = rng:NextNumber(ruinInner + 10, ruinOuter - 10)
		block(
			ops,
			SANDSTONE,
			CFrame.new(at(angle, r, floor + 12))
				* CFrame.Angles(0, rng:NextNumber(0, 6.28), rng:NextNumber(-0.15, 0.15)),
			Vector3.new(60, 26, 6)
		)
	end
	do
		local templeCenter = at(12, (ruinInner + ruinOuter) / 2, floor)
		cylinder(ops, SANDSTONE, templeCenter + Vector3.new(0, 4, 0), 70, 12)
		for i = 1, 12 do
			local a = i / 12 * 2 * math.pi
			local foot = templeCenter + Vector3.new(math.cos(a) * 54, 10, math.sin(a) * 54)
			local height = if i % 4 == 0 then rng:NextNumber(14, 24) else 48
			cylinder(ops, SANDSTONE, foot + Vector3.new(0, height / 2, 0), 5, height)
			if i % 4 ~= 0 and i % 4 ~= 3 then
				local b = (i + 1) / 12 * 2 * math.pi
				local next = templeCenter + Vector3.new(math.cos(b) * 54, 10, math.sin(b) * 54)
				local mid = (foot + next) / 2 + Vector3.new(0, 50, 0)
				block(
					ops,
					SANDSTONE,
					CFrame.lookAt(mid, mid + (next - foot).Unit),
					Vector3.new(7, 5, (next - foot).Magnitude + 6)
				)
			end
		end
		table.insert(features.ruinAnchors, templeCenter + Vector3.new(0, 10, 0))
	end

	-- The Open Blue: long mud ridges, rock knolls and low rock spires on a floor lost
	-- in the blue far below; above it is open ocean (owner, 2026-10-09: "deep blue
	-- where there's no ground or anything just open ocean"), so the spires stay
	-- under ~70 studs and the Megalodon and the sharks keep to the water above
	for _ = 1, 16 do
		local angle = sectorAngle(rng, 228, 312)
		local r = rng:NextNumber(deepInner + 40, World.boundsRadius - 60)
		local radius = rng:NextNumber(60, 120)
		ball(ops, MUD, at(angle, r, floor - radius * 0.85), radius)
	end
	for _ = 1, 4 do
		local angle = sectorAngle(rng, 232, 308)
		local r = rng:NextNumber(deepInner + 80, World.boundsRadius - 120)
		local radius = rng:NextNumber(90, 150)
		ball(ops, ROCK, at(angle, r, floor - radius * 0.6), radius)
	end
	for _ = 1, 7 do
		local angle = sectorAngle(rng, 235, 305)
		local r = rng:NextNumber(deepInner + 90, World.boundsRadius - 120)
		local height = rng:NextNumber(150, 280) * 0.25
		local base = at(angle, r, floor)
		cylinder(ops, ROCK, base + Vector3.new(0, height / 2 - 4, 0), rng:NextNumber(24, 38), height)
		ball(ops, ROCK, base + Vector3.new(0, height * 0.55, 0), rng:NextNumber(30, 44))
		ball(ops, ROCK, base + Vector3.new(0, height - 4, 0), rng:NextNumber(18, 28))
		table.insert(features.pinnacles, base + Vector3.new(0, height, 0))
	end

	-- Debris that slid off the Wreck's side of the shelf
	for _ = 1, 30 do
		local angle = sectorAngle(rng, 135, 225)
		local r = rng:NextNumber(deepInner + 10, deepInner + 130)
		ball(ops, ROCK, at(angle, r, floor - 4), rng:NextNumber(10, 28))
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
