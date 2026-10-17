--!strict
-- The hub's plaza as a lived-in underwater town square (owner, 2026-10-17: "Ground
-- still looks a bit rough in the starter zone ... Details need to be dialed up a bit
-- in the starter safe zone as well", and the stalls looked "fuzzy, cheap"). Built
-- from parts over the cavern's Terrain floor (Cave.luau keeps it flat under here):
--   - the raised centre (Layout.PLAZA_TOP): a two-tier dais under the crystal
--     beacon, a compass rose (north is -Z, as on the map) and rings of flagstones;
--   - a sandstone curb round it, then rings of bigger flagstones out to the walls
--     (hub.paving), warm stone where a path runs out to a den's steps or a tunnel,
--     cool grey-teal between, and nothing under the Treasure Wheel's stage;
--   - raised planter beds against the walls between the doorways, full of coral,
--     sponges and kelp, a brass lantern on the wall over each, and a lamp post on
--     the curb in front of each;
--   - over every tunnel, a board that says EXIT, which way it goes and the biomes
--     that lie out there with their levels (Config/Biomes);
--   - the five vendor stalls, part-built: a counter with a dyed apron, a striped
--     awning with a scalloped valance, a lettered sign on top, hanging lanterns,
--     a shelf and goods that say what each sells. The keeper models stand beside
--     them (WorldProps.Keeper<id>).
-- The flagstones are what fish rest on, so they collide and take camera rays; the
-- rest is decor (CanQuery false). Layout's numbers (the plaza's top, the counters,
-- the safe zone) are unchanged. tools/preview/run_hub.sh renders it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BiomesConfig = require(ReplicatedStorage.Shared.Config.Biomes)
local ShopConfig = require(ReplicatedStorage.Shared.Config.Shop)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Props = require(ReplicatedStorage.Shared.Props)
local Decor = require(script.Parent.Decor)

local World = Config.World
local hub = World.hub
local part = Decor.part

local Plaza = {}

local PLAZA_TOP = Layout.PLAZA_TOP
local PAVING = hub.paving
local INNER = 45 -- the raised centre's edge
local CURB = 47.7 -- the curb ring round it
local OUTER = 86 -- the paving's outer edge (the doorways' steps start at ~84)
local GAP = 0.32 -- grout between flagstones
local DAIS = 7.6
local ROSE = 19.6

local GROUT = Color3.fromRGB(70, 84, 90)
local GROUT_INNER = Color3.fromRGB(96, 104, 104)
local CURB_STONE = Color3.fromRGB(190, 170, 132)
local INNER_STONES = {
	Color3.fromRGB(214, 204, 176),
	Color3.fromRGB(202, 192, 164),
	Color3.fromRGB(222, 212, 186),
	Color3.fromRGB(194, 186, 160),
}
local ACCENT_STONES = { Color3.fromRGB(150, 184, 184), Color3.fromRGB(138, 172, 174) }
local OUTER_STONES = {
	Color3.fromRGB(122, 142, 148),
	Color3.fromRGB(134, 152, 156),
	Color3.fromRGB(114, 134, 142),
	Color3.fromRGB(128, 146, 150),
}
local PATH_STONES = {
	Color3.fromRGB(186, 166, 128),
	Color3.fromRGB(176, 156, 120),
	Color3.fromRGB(196, 176, 138),
}
local TEAL = Color3.fromRGB(30, 104, 116)
local DAIS_STONE = Color3.fromRGB(214, 204, 176)
local SAND = Color3.fromRGB(222, 204, 156)
local PLANTER = Color3.fromRGB(176, 156, 120)
local PLANTER_CAP = Color3.fromRGB(200, 182, 146)
local WOOD = Color3.fromRGB(118, 80, 52)
local WOOD_LIGHT = Color3.fromRGB(184, 134, 86)
local WOOD_DARK = Color3.fromRGB(84, 56, 38)
local CANVAS = Color3.fromRGB(244, 236, 216)
local EXIT_GLOW = Color3.fromRGB(110, 220, 235)

-- Treasure Wheel's stage (Config/Wheel): no paving under it, nothing in its way
local WHEEL_STAGE = 17.8
local WHEEL_CLEAR = 26

local function outward(angle: number): Vector3
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

-- A spot `r` out along `angle`, `y` up, facing the hub's centre (local -Z inward)
local function facingIn(angle: number, r: number, y: number): CFrame
	local position = hub.center + outward(angle) * r + Vector3.new(0, y, 0)
	return CFrame.lookAt(position, position - outward(angle))
end

-- A round slab whose top is at `top`
local function slab(
	parent: Instance,
	name: string,
	radius: number,
	top: number,
	thickness: number,
	color: Color3
): Part
	return part(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, radius * 2, radius * 2),
		CFrame = CFrame.new(hub.center + Vector3.new(0, top - thickness / 2, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		CanCollide = true,
		CanQuery = true,
		CastShadow = false,
	})
end

local wheelAt = hub.center + outward(math.rad(Config.Wheel.angle)) * Config.Wheel.radius

-- The doorways and tunnels round the wall: their angles and the path's half-width
type Opening = { angle: number, half: number, kind: string }
local openings: { Opening } = {}
local walls: { number } = {}
for segment = 1, hub.segments do
	local kind = Layout.segmentKind(segment)
	local angle = Layout.segmentAngle(segment)
	if kind == "wall" then
		table.insert(walls, angle)
	else
		table.insert(openings, { angle = angle, half = if kind == "tunnel" then 11.5 else 5.6, kind = kind })
	end
end

-- Whether a wall segment has the wheel in front of it (no bed or post there)
local function wheelWall(angle: number): boolean
	return (hub.center + outward(angle) * 62 - wheelAt).Magnitude < WHEEL_CLEAR
end

-- How far `p` is from `angle`'s line out from the centre (and whether it's on it)
local function lateral(p: Vector3, angle: number): (number, number)
	local flat = Vector3.new(p.X - hub.center.X, 0, p.Z - hub.center.Z)
	local along = flat:Dot(outward(angle))
	local across = math.abs(flat:Dot(Vector3.new(-math.sin(angle), 0, math.cos(angle))))
	return across, along
end

local function onPath(p: Vector3): boolean
	for _, opening in openings do
		local across, along = lateral(p, opening.angle)
		if along > 0 and across < opening.half then
			return true
		end
	end
	return false
end

-- Planter beds stand against the walls between the doorways
local BED_HALF = 8.4
local BED_FRONT = 80.5
local function inBed(p: Vector3): boolean
	for _, angle in walls do
		if not wheelWall(angle) then
			local across, along = lateral(p, angle)
			if along > BED_FRONT - 1 and across < BED_HALF + 0.8 then
				return true
			end
		end
	end
	return false
end

-- One ring of flagstones between `rIn` and `rOut`, `length` long round the ring,
-- their tops at `top`. A ring's stones are cut to its outer edge, so they meet
-- there with a thin seam and tuck under one another toward the inside (cut to the
-- middle, the gaps opened into dark teeth); every other stone stands a hair
-- higher, so the overlaps never flicker. `pick` gives a stone's colour, or nil.
local function stoneRing(
	parent: Instance,
	rIn: number,
	rOut: number,
	top: number,
	thickness: number,
	length: number,
	offset: number,
	pick: (Vector3, number) -> Color3?
): number
	local mid = (rIn + rOut) / 2
	local n = math.max(8, math.floor(2 * math.pi * mid / length + 0.5))
	local step = 2 * math.pi / n
	local chord = 2 * rOut * math.sin(step / 2)
	local made = 0
	for i = 0, n - 1 do
		local angle = (i + offset) * step
		local at = hub.center + outward(angle) * mid
		local color = pick(at, i)
		if color then
			-- (an odd count would put two stones of the same height side by side at
			-- the ring's seam: the last one gets a height of its own)
			local raise = if i == n - 1 and n % 2 == 1 then 0.02 elseif i % 2 == 0 then 0 else 0.04
			local height = thickness + raise
			local center = at + Vector3.new(0, top + raise - height / 2, 0)
			part(parent, {
				Name = "Flagstone",
				Size = Vector3.new(chord - GAP, height, rOut - rIn - GAP),
				CFrame = CFrame.lookAt(center, center + outward(angle)),
				Color = color,
				CanCollide = true,
				CanQuery = true,
				CastShadow = false, -- flat paving shadows nothing
			})
			made += 1
		end
	end
	return made
end

-- The compass rose round the dais: eight points (north red, the other cardinal
-- points gold, the diagonals cream), each a light and a dark half
local function compass(parent: Instance)
	slab(parent, "RoseRim", ROSE, PLAZA_TOP - 0.02, 0.5, Decor.BRASS)
	slab(parent, "Rose", ROSE - 0.6, PLAZA_TOP, 0.5, TEAL)
	slab(parent, "RoseRing", 13.6, PLAZA_TOP + 0.005, 0.3, Decor.BRASS_LIGHT)
	slab(parent, "Rose", 13.2, PLAZA_TOP + 0.01, 0.3, TEAL)
	local y = PLAZA_TOP + 0.05
	for k = 0, 7 do
		local angle = k * math.pi / 4
		local cardinal = k % 2 == 0
		local tip = if cardinal then ROSE - 1.4 else 12.6
		local shoulder = if cardinal then 6.4 else 5.6
		local spread = if cardinal then math.rad(24) else math.rad(20)
		local north = k == 6 -- -Z
		local light = if north
			then Color3.fromRGB(236, 100, 86)
			elseif cardinal then Color3.fromRGB(246, 208, 116)
			else Color3.fromRGB(232, 226, 204)
		local dark = if north
			then Color3.fromRGB(176, 58, 54)
			elseif cardinal then Color3.fromRGB(190, 142, 60)
			else Color3.fromRGB(170, 166, 150)
		local c = hub.center + Vector3.new(0, y, 0)
		local t = c + outward(angle) * tip
		for side = -1, 1, 2 do
			local s = c + outward(angle + side * spread) * shoulder
			Decor.triangle(parent, c, s, t, 0.1, {
				Name = "RosePoint",
				Color = if side < 0 then light else dark,
			})
		end
	end
end

-- The dais under the beacon: a cream drum and a teal one on it, brass bands, four
-- glowing pearls; the crystal on top
local function dais(parent: Instance): number
	local lower = PLAZA_TOP + 1.3
	local upper = lower + 1.0
	slab(parent, "Dais", DAIS, lower, 1.6, DAIS_STONE)
	slab(parent, "DaisBand", DAIS + 0.15, lower - 0.25, 0.35, Decor.BRASS)
	slab(parent, "Dais", DAIS - 1.5, upper, 1.2, TEAL)
	slab(parent, "DaisBand", DAIS - 1.35, upper - 0.1, 0.25, Decor.BRASS_LIGHT)
	for k = 0, 3 do
		local angle = math.rad(45 + k * 90)
		local pearl = part(parent, {
			Name = "DaisPearl",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.1,
			CFrame = CFrame.new(hub.center + outward(angle) * (DAIS - 0.8) + Vector3.new(0, lower + 0.45, 0)),
			Color = Color3.fromRGB(190, 246, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
		pearl.Transparency = 0.1
	end
	return upper
end

-- The crystal beacon (the Evolution Shrine's placeholder), on the dais
local function beacon(parent: Instance, base: number)
	local crystal = part(parent, {
		Name = "Beacon",
		Size = Vector3.new(6, 26, 6),
		CFrame = CFrame.new(hub.center + Vector3.new(0, base + 13, 0))
			* CFrame.Angles(0, math.rad(45), math.rad(12)),
		Color = Color3.fromRGB(110, 230, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CanCollide = true,
		CanQuery = true,
	})
	Props.dress(crystal, "CrystalCluster", {
		cframe = CFrame.new(hub.center + Vector3.new(0, base + 11, 0)),
		size = Vector3.new(18, 22, 18),
	})
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(110, 230, 255)
	glow.Range = 60
	glow.Brightness = 1.2
	glow.Parent = crystal
end

-- The floor: the raised centre (compass, flagstones), the curb and the outer
-- flagstones with their paths
local function floor(parent: Instance)
	local folder = Instance.new("Model")
	folder.Name = "Paving"
	local rng = Random.new(World.seed + 41)
	-- Grout under everything, and the curb between the two levels
	slab(folder, "Grout", OUTER + 0.6, PAVING - 0.3, 1.2, GROUT)
	slab(folder, "Curb", CURB, PLAZA_TOP - 0.14, 1.4, CURB_STONE)
	slab(folder, "CurbInlay", INNER + 0.4, PLAZA_TOP - 0.11, 0.6, Decor.BRASS)
	slab(folder, "Grout", INNER, PLAZA_TOP - 0.08, 1.0, GROUT_INNER)
	-- The centre's rings, narrow by the rose and wider out; the vendors' ring is a
	-- little teal
	local rings = { ROSE + 0.3, 23.4, 27.4, 31.6, 36.0, 40.4, INNER }
	for k = 1, #rings - 1 do
		local accent = k == 4
		stoneRing(
			folder,
			rings[k],
			rings[k + 1],
			PLAZA_TOP,
			0.5,
			6.4,
			(k % 2) * 0.5,
			function(_: Vector3, _: number)
				local palette = if accent then ACCENT_STONES else INNER_STONES
				return palette[rng:NextInteger(1, #palette)]
			end
		)
	end
	-- The outer rings: paths of warm stone toward each opening, grey-teal between
	local outer = { CURB + 0.2, 54.0, 60.4, 66.8, 73.2, 79.6, OUTER }
	for k = 1, #outer - 1 do
		local outermost = k == #outer - 1
		stoneRing(
			folder,
			outer[k],
			outer[k + 1],
			PAVING,
			0.7,
			8.6,
			(k % 2) * 0.5,
			function(at: Vector3, _: number)
				if (at - wheelAt).Magnitude < WHEEL_STAGE - 4 then
					return nil
				end
				if outermost and inBed(at) then
					return nil
				end
				if k >= 3 and onPath(at) then
					return PATH_STONES[rng:NextInteger(1, #PATH_STONES)]
				end
				return OUTER_STONES[rng:NextInteger(1, #OUTER_STONES)]
			end
		)
	end
	compass(folder)
	folder.Parent = parent
end

-- A lamp post on the curb: an iron post on a brass-capped foot, a globe lamp
local function lampPost(parent: Instance, at: CFrame)
	local base = at
	Decor.upright(parent, "LampFoot", base, 1.3, 0.95).Color = Decor.IRON
	Decor.upright(parent, "LampFootCap", base * CFrame.new(0, 1.3, 0), 0.35, 0.72).Color = Decor.BRASS
	local pole = Decor.upright(parent, "LampPost", base * CFrame.new(0, 1.6, 0), 8.2, 0.26)
	pole.Color = Decor.IRON
	pole.CanCollide = true
	Decor.upright(parent, "LampCollar", base * CFrame.new(0, 6.4, 0), 0.4, 0.42).Color = Decor.BRASS
	Decor.upright(parent, "LampCup", base * CFrame.new(0, 9.7, 0), 0.5, 0.75).Color = Decor.BRASS
	local globe = part(parent, {
		Name = "LampGlobe",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.9,
		CFrame = base * CFrame.new(0, 11.0, 0),
		Color = Decor.GLASS_LIT,
		Material = Enum.Material.Neon,
		Transparency = 0.06,
		CanCollide = false,
		CastShadow = false,
	})
	Decor.pebble(
		parent,
		"LampHat",
		base * CFrame.new(0, 12.05, 0),
		Vector3.new(1.7, 0.75, 1.7),
		Decor.BRASS_DARK
	)
	Decor.pebble(parent, "LampFinial", base * CFrame.new(0, 12.55, 0), Vector3.one * 0.5, Decor.BRASS_LIGHT)
	local light = Instance.new("PointLight")
	light.Color = Decor.LAMP_LIGHT
	light.Range = 22
	light.Brightness = 0.9
	light.Parent = globe
end

-- A raised bed against the wall: a sandstone curb with a rounded cap, sand banked
-- up to the wall, coral, sponges, an anemone and kelp (`at` faces the hub, on the
-- bed's front edge at paving height)
local function planter(parent: Instance, at: CFrame, rng: Random, starfish: boolean)
	local depth = 13
	local height = 1.9
	part(parent, {
		Name = "PlanterCurb",
		Size = Vector3.new(BED_HALF * 2, height, 1.2),
		CFrame = at * CFrame.new(0, height / 2 - 0.3, 0),
		Color = PLANTER,
		CanCollide = true,
	})
	part(parent, {
		Name = "PlanterCap",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(BED_HALF * 2 + 0.4, 1.4, 1.4),
		CFrame = at * CFrame.new(0, height - 0.3, 0),
		Color = PLANTER_CAP,
		CanCollide = false,
	})
	for side = -1, 1, 2 do
		part(parent, {
			Name = "PlanterCurb",
			Size = Vector3.new(1.2, height, depth),
			CFrame = at * CFrame.new(side * BED_HALF, height / 2 - 0.3, depth / 2),
			Color = PLANTER,
			CanCollide = true,
		})
		part(parent, {
			Name = "PlanterCap",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(depth, 1.4, 1.4),
			CFrame = at
				* CFrame.new(side * BED_HALF, height - 0.3, depth / 2)
				* CFrame.Angles(0, math.rad(90), 0),
			Color = PLANTER_CAP,
			CanCollide = false,
		})
	end
	-- Sand inside, banked up toward the wall
	part(parent, {
		Name = "PlanterSand",
		Size = Vector3.new(BED_HALF * 2 - 1, 1.2, depth - 0.6),
		CFrame = at * CFrame.new(0, height - 0.75, depth / 2),
		Color = SAND,
		CanCollide = false,
	})
	local bank = Instance.new("WedgePart")
	bank.Name = "PlanterSand"
	bank.Anchored = true
	bank.CanCollide = false
	bank.CanQuery = false
	bank.CanTouch = false
	bank.Material = Enum.Material.SmoothPlastic
	bank.Color = SAND
	bank.Size = Vector3.new(BED_HALF * 2 - 1, 2.2, depth * 0.55)
	-- a wedge rises toward its back (+Z): the wall
	bank.CFrame = at * CFrame.new(0, height - 0.15 + 1.1, depth - depth * 0.55 / 2 - 0.3)
	bank.Parent = parent
	local soil = height - 0.15
	-- Kelp up the wall, two stalks
	for _, x in { -4.6, 3.8 } do
		Decor.kelp(
			parent,
			at * CFrame.new(x + rng:NextNumber(-0.6, 0.6), soil + 0.6, depth - 3.2),
			4,
			3.8,
			rng
		)
	end
	-- Corals and sponges along the front
	Decor.pebble(
		parent,
		"BrainCoral",
		at * CFrame.new(4.8, soil + 0.9, 3.4) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
		Vector3.new(3.0, 2.2, 2.8),
		Decor.CORALS[rng:NextInteger(1, #Decor.CORALS)]
	).CanCollide =
		true
	Decor.sponges(parent, at * CFrame.new(-4.4, soil, 3.2), 3, rng)
	-- A fan coral: two flat discs edge-on to the wall
	local fan = Decor.CORALS[rng:NextInteger(1, #Decor.CORALS)]
	for k, r in { 2.4, 1.7 } do
		local disc = Decor.disc(
			parent,
			"FanCoral",
			at
				* CFrame.new(0.4 + (k - 1) * 1.6, soil + r * 0.95, 6.0 + (k - 1) * 0.8)
				* CFrame.Angles(0, rng:NextNumber(-0.35, 0.35), 0),
			r,
			0.25
		)
		disc.Color = if k == 1 then fan else fan:Lerp(Color3.new(1, 1, 1), 0.25)
		disc.CastShadow = true
		disc.CanCollide = true
	end
	-- An anemone: a squat body with a glowing crown
	local anemone = Decor.CORALS[rng:NextInteger(1, #Decor.CORALS)]
	Decor.pebble(
		parent,
		"Anemone",
		at * CFrame.new(-0.6, soil + 0.6, 2.4),
		Vector3.new(1.9, 1.3, 1.9),
		anemone
	)
	local crown = part(parent, {
		Name = "AnemoneCrown",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.1,
		CFrame = at * CFrame.new(-0.6, soil + 1.25, 2.4),
		Color = anemone:Lerp(Color3.new(1, 1, 1), 0.45),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	crown.Transparency = 0.15
	if starfish then
		Decor.starfish(
			parent,
			at * CFrame.new(rng:NextNumber(-5, 5), height * 0.5 - 0.3, -0.62),
			1.4,
			Color3.fromRGB(255, 176, 66)
		)
	end
end

-- The wall's dressing at each plain wall segment: a planter, a lantern over it and a
-- lamp post on the curb in front
local function wallDressing(parent: Instance)
	local folder = Instance.new("Model")
	folder.Name = "Gardens"
	local rng = Random.new(World.seed + 53)
	for k, angle in walls do
		local wheel = wheelWall(angle)
		if not wheel then
			planter(folder, facingIn(angle, BED_FRONT, PAVING), rng, k % 2 == 1)
			lampPost(folder, facingIn(angle, (INNER + CURB) / 2 + 0.2, PLAZA_TOP - 0.14))
		end
		-- The wall lantern (it was a glowing cube)
		Decor.lantern(
			folder,
			facingIn(angle, hub.radius - 2.4, 18) * CFrame.Angles(0, math.rad(90), 0),
			-1,
			true,
			26
		)
	end
	folder.Parent = parent
end

-- Builds the plaza (floor, dais, beacon, gardens) into `parent`
function Plaza.build(parent: Instance)
	floor(parent)
	local top = dais(parent)
	beacon(parent, top)
	wallDressing(parent)
end

-- Where the Treasure Wheel's stage stands on the paving
Plaza.WHEEL_GROUND = PAVING

---------------------------------------------------------------------------
-- Tunnel boards
---------------------------------------------------------------------------

-- The biomes that lie out a tunnel along `angle` (radians), easiest first
local function biomesToward(angle: number): { BiomesConfig.Biome }
	local degrees = math.deg(angle) % 360
	local found = {}
	for _, biome in Config.Biomes.list do
		local from, to = biome.angleFrom % 360, biome.angleTo % 360
		local span = (to - from) % 360
		if span == 0 then
			span = 360
		end
		if biome.live and (degrees - from) % 360 <= span then
			table.insert(found, biome)
		end
	end
	table.sort(found, function(a, b)
		return a.minLevel < b.minLevel
	end)
	return found
end

local COMPASS = { [0] = "EAST", [90] = "SOUTH", [180] = "WEST", [270] = "NORTH" }

-- The board over a tunnel's mouth (WorldService finds the rock face, `face` studs
-- out, and the height `y`): EXIT and the way it leads, then the biomes out there
-- with their levels, each in its colour. Returns the board's frame (facing the hub).
function Plaza.tunnelBoard(parent: Instance, angle: number, face: number, y: number): CFrame
	local at = facingIn(angle, face - 0.9, y)
	local size = Vector2.new(24, 7.6)
	local plaque = Decor.plaque(parent, at, size, Color3.fromRGB(16, 58, 70), false)
	plaque.board.Name = "ExitBoard"
	local degrees = math.floor(math.deg(angle) + 0.5) % 360
	plaque.title.Text = `EXIT · {COMPASS[degrees] or "OUT"}`
	plaque.title.TextColor3 = EXIT_GLOW
	plaque.title.Position = UDim2.fromScale(0.04, 0.03)
	plaque.title.Size = UDim2.fromScale(0.92, 0.42)
	local biomes = biomesToward(angle)
	local rowHeight = 0.5 / math.max(#biomes, 1)
	for i, biome in biomes do
		local row = Instance.new("TextLabel")
		row.Name = "Biome"
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromScale(0.06, 0.48 + (i - 1) * rowHeight)
		row.Size = UDim2.fromScale(0.88, rowHeight * 0.92)
		row.Font = Enum.Font.GothamBlack
		row.TextScaled = true
		row.TextColor3 = biome.color
		row.Text = `{Decor.oneLine(biome.name)}  ·  LV {biome.minLevel}+`
		row.Parent = plaque.gui
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 64
		limit.Parent = row
		local stroke = Instance.new("UIStroke")
		stroke.Color = Decor.TEXT_STROKE
		stroke.Thickness = 3
		stroke.Parent = row
	end
	return at
end

---------------------------------------------------------------------------
-- Vendor stalls
---------------------------------------------------------------------------

-- The stall and keeper models face the GLB's +X, and Roblox's importer turns a GLB
-- half round, so they arrive facing -X. A quarter turn puts their fronts on -Z.
local GLB_FRONT = CFrame.Angles(0, -math.pi / 2, 0)
-- A keeper stands beside its counter (on the right as you face the stall), turned
-- part way toward the plaza in front of the counter
local KEEPER_SIDE = 10.5
local KEEPER_TURN = math.rad(-25)

-- A shopkeeper: its model (WorldProps.Keeper<VendorId>) stands on the plaza beside
-- the counter at full height, facing the plaza; until it's imported, a ball with
-- eyes sits behind the counter
local function keeper(parent: Instance, at: CFrame, stand: CFrame, color: Color3, vendorId: string)
	local body = part(parent, {
		Name = "Keeper",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 4,
		CFrame = at,
		Color = color,
		CanCollide = false,
	})
	local dressed = Props.dress(body, `Keeper{vendorId}`, {
		cframe = stand * GLB_FRONT,
		size = Vector3.new(8, 7.5, 7.5), -- turned: X runs front to back, Z side to side
		solid = true,
	})
	if dressed then
		body.Transparency = 1
		return
	end
	for side = -1, 1, 2 do
		part(parent, {
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.1,
			CFrame = at * CFrame.new(side * 0.8, 0.6, -1.55),
			Color = Color3.new(1, 1, 1),
			CanCollide = false,
		})
		part(parent, {
			Name = "Pupil",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.55,
			CFrame = at * CFrame.new(side * 0.8, 0.6, -2.02),
			Color = Color3.fromRGB(20, 22, 28),
			CanCollide = false,
		})
	end
end

-- Goods on the counter (`at` is the counter top's middle, facing the plaza), by
-- what the vendor sells
local function goods(parent: Instance, vendorId: string, at: CFrame, color: Color3)
	if vendorId == "Outfitter" then
		-- A brass diving helmet, a pair of fins and a coil of rope
		Decor.pebble(parent, "Helmet", at * CFrame.new(-3.4, 1.15, 0.2), Vector3.one * 2.2, Decor.BRASS)
		Decor.disc(parent, "HelmetPort", at * CFrame.new(-3.4, 1.15, -0.95), 0.7, 0.3).Color =
			Color3.fromRGB(150, 220, 236)
		Decor.upright(parent, "HelmetCollar", at * CFrame.new(-3.4, 0, 0.2), 0.4, 1.0).Color =
			Decor.BRASS_DARK
		for k = 0, 1 do
			Decor.triangle(
				parent,
				(at * CFrame.new(-0.4 + k * 1.3, 0.1, 0.6)).Position,
				(at * CFrame.new(0.6 + k * 1.3, 0.1, 0.6)).Position,
				(at * CFrame.new(0.1 + k * 1.3, 2.6, 0.2)).Position,
				0.3,
				{ Name = "Fin", Color = color:Lerp(Color3.new(0, 0, 0), 0.1 * k) }
			)
		end
		Decor.upright(parent, "Rope", at * CFrame.new(3.6, 0, 0), 0.7, 1.15).Color =
			Color3.fromRGB(206, 176, 118)
		Decor.upright(parent, "RopeCore", at * CFrame.new(3.6, 0.05, 0), 0.72, 0.5).Color =
			Color3.fromRGB(150, 120, 78)
	elseif vendorId == "Mason" then
		-- Bricks, a mallet and a chisel in a block
		for k = 0, 2 do
			part(parent, {
				Name = "Brick",
				Size = Vector3.new(1.8, 0.7, 0.9),
				CFrame = at
					* CFrame.new(-3.6 + (k % 2) * 0.4, 0.35 + k * 0.72, 0)
					* CFrame.Angles(0, 0.2 * k, 0),
				Color = Color3.fromRGB(196, 96, 66):Lerp(Color3.fromRGB(230, 140, 90), k * 0.3),
				CanCollide = false,
			})
		end
		Decor.upright(
			parent,
			"MalletHandle",
			at * CFrame.new(0.4, 0, 0) * CFrame.Angles(0, 0, math.rad(70)),
			2.6,
			0.16
		).Color =
			WOOD_LIGHT
		part(parent, {
			Name = "MalletHead",
			Size = Vector3.new(0.9, 0.9, 1.6),
			CFrame = at * CFrame.new(-1.9, 0.75, 0) * CFrame.Angles(0, 0, math.rad(-20)),
			Color = WOOD_DARK,
			CanCollide = false,
		})
		part(parent, {
			Name = "Block",
			Size = Vector3.new(1.6, 1.3, 1.4),
			CFrame = at * CFrame.new(3.4, 0.65, 0),
			Color = Color3.fromRGB(200, 196, 186),
			CanCollide = false,
		})
		Decor.upright(parent, "Chisel", at * CFrame.new(3.4, 1.3, 0) * CFrame.Angles(0.3, 0, 0), 1.4, 0.14).Color =
			Decor.IRON
	elseif vendorId == "Charms" then
		-- Three jars of glowing charms and a pile of shells
		for k, glow in
			{ Color3.fromRGB(255, 214, 90), Color3.fromRGB(120, 240, 150), Color3.fromRGB(190, 130, 255) }
		do
			local jar = at * CFrame.new(-3.8 + (k - 1) * 1.7, 0, 0)
			local glass = Decor.upright(parent, "Jar", jar, 1.6, 0.6)
			glass.Color = Color3.fromRGB(200, 236, 236)
			glass.Material = Enum.Material.Glass
			glass.Transparency = 0.45
			Decor.upright(parent, "JarLid", jar * CFrame.new(0, 1.6, 0), 0.3, 0.66).Color = Decor.BRASS
			local charm = part(parent, {
				Name = "Charm",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.75,
				CFrame = jar * CFrame.new(0, 0.6, 0),
				Color = glow,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CastShadow = false,
			})
			charm.Transparency = 0.05
		end
		for k, shell in
			{ Color3.fromRGB(250, 236, 220), Color3.fromRGB(244, 196, 150), Color3.fromRGB(226, 214, 250) }
		do
			Decor.pebble(
				parent,
				"Shell",
				at * CFrame.new(2.6 + (k - 1) * 0.9, 0.35 + (if k == 2 then 0.5 else 0), (k - 2) * 0.4),
				Vector3.new(1.2, 0.7, 1.0),
				shell
			)
		end
	elseif vendorId == "Dyer" then
		-- Paint pots in four colours, a brush and a palette
		for k, paint in
			{
				Color3.fromRGB(236, 72, 92),
				Color3.fromRGB(255, 206, 64),
				Color3.fromRGB(70, 150, 255),
				Color3.fromRGB(90, 210, 120),
			}
		do
			local pot = at * CFrame.new(-4.4 + (k - 1) * 1.45, 0, (k % 2) * 0.5 - 0.2)
			Decor.upright(parent, "Pot", pot, 1.1, 0.6).Color = Color3.fromRGB(70, 74, 82)
			Decor.upright(parent, "Paint", pot * CFrame.new(0, 1.1, 0), 0.12, 0.52).Color = paint
		end
		Decor.upright(
			parent,
			"Brush",
			at * CFrame.new(1.9, 0.2, 0) * CFrame.Angles(0, 0, math.rad(-62)),
			2.2,
			0.13
		).Color =
			WOOD_LIGHT
		part(parent, {
			Name = "Bristles",
			Size = Vector3.new(0.5, 0.7, 0.4),
			CFrame = at * CFrame.new(3.85, 1.25, 0) * CFrame.Angles(0, 0, math.rad(-62)),
			Color = color,
			CanCollide = false,
		})
		Decor.upright(parent, "Palette", at * CFrame.new(4.0, 0, -0.2), 0.2, 1.1).Color =
			Color3.fromRGB(214, 176, 120)
	elseif vendorId == "Trophies" then
		-- Three great teeth on a dark board, and a squid's beak
		part(parent, {
			Name = "TrophyBoard",
			Size = Vector3.new(4.2, 0.4, 1.8),
			CFrame = at * CFrame.new(-2.2, 0.2, 0),
			Color = WOOD_DARK,
			CanCollide = false,
		})
		for k = 0, 2 do
			local h = if k == 1 then 2.4 else 1.8
			Decor.triangle(
				parent,
				(at * CFrame.new(-3.4 + k * 1.2 - 0.45, 0.4, 0)).Position,
				(at * CFrame.new(-3.4 + k * 1.2 + 0.45, 0.4, 0)).Position,
				(at * CFrame.new(-3.4 + k * 1.2, 0.4 + h, 0)).Position,
				0.6,
				{ Name = "Tooth", Color = Color3.fromRGB(240, 236, 224) }
			)
		end
		Decor.pebble(
			parent,
			"Beak",
			at * CFrame.new(2.8, 0.7, 0),
			Vector3.new(1.8, 1.4, 1.4),
			Color3.fromRGB(46, 36, 44)
		)
		Decor.pebble(
			parent,
			"BeakTip",
			at * CFrame.new(3.7, 0.5, 0),
			Vector3.new(0.9, 0.7, 0.7),
			Color3.fromRGB(70, 56, 64)
		)
	end
end

-- One vendor's stall, in the frame `stall` (on the plaza at the counter's middle,
-- -Z toward the beacon)
local function stallParts(parent: Instance, vendor: ShopConfig.Vendor, stall: CFrame): Part
	local color = vendor.color
	local size = Layout.COUNTER_SIZE
	local counter = part(parent, {
		Name = "Counter",
		Size = size,
		CFrame = stall * CFrame.new(0, size.Y / 2, 0),
		Color = WOOD,
		CanCollide = true,
		CanQuery = true,
	})
	part(parent, {
		Name = "CounterTop",
		Size = Vector3.new(size.X + 0.8, 0.5, size.Z + 0.8),
		CFrame = stall * CFrame.new(0, size.Y + 0.25, -0.1),
		Color = WOOD_LIGHT,
		CanCollide = false,
	})
	part(parent, {
		Name = "CounterKick",
		Size = Vector3.new(size.X + 0.5, 0.5, size.Z + 0.3),
		CFrame = stall * CFrame.new(0, 0.25, 0),
		Color = WOOD_DARK,
		CanCollide = false,
	})
	-- The dyed apron across the front, brass along its top, a brass boss in the middle
	part(parent, {
		Name = "Apron",
		Size = Vector3.new(size.X - 0.8, size.Y - 1.3, 0.3),
		CFrame = stall * CFrame.new(0, size.Y / 2 + 0.05, -size.Z / 2 - 0.1),
		Color = color,
		CanCollide = false,
	})
	part(parent, {
		Name = "ApronTrim",
		Size = Vector3.new(size.X - 0.4, 0.3, 0.4),
		CFrame = stall * CFrame.new(0, size.Y - 0.45, -size.Z / 2 - 0.15),
		Color = Decor.BRASS,
		CanCollide = false,
	})
	Decor.disc(parent, "ApronBoss", stall * CFrame.new(0, size.Y / 2 + 0.05, -size.Z / 2 - 0.3), 0.8, 0.25).Color =
		Decor.BRASS_LIGHT
	-- Back posts with brass bands, and a shelf between them
	local postZ = size.Z / 2 + 1.4
	local top = 11.6
	for side = -1, 1, 2 do
		local post = Decor.upright(parent, "Post", stall * CFrame.new(side * 6.1, 0, postZ), top, 0.42)
		post.Color = WOOD_DARK
		post.CanCollide = true
		for _, y in { 4.2, 9.2 } do
			Decor.upright(parent, "PostBand", stall * CFrame.new(side * 6.1, y, postZ), 0.35, 0.5).Color =
				Decor.BRASS
		end
	end
	for _, y in { 5.6, 7.9 } do
		part(parent, {
			Name = "Shelf",
			Size = Vector3.new(11.6, 0.35, 1.5),
			CFrame = stall * CFrame.new(0, y, postZ),
			Color = WOOD_LIGHT,
			CanCollide = false,
		})
	end
	-- Jars and bolts of colour on the shelves
	local shelfRng = Random.new(World.seed + #vendor.id * 7 + vendor.angle)
	for _, y in { 5.6, 7.9 } do
		for k = 0, 3 do
			local x = -4.2 + k * 2.8 + shelfRng:NextNumber(-0.4, 0.4)
			local h = shelfRng:NextNumber(0.9, 1.5)
			local tint = color:Lerp(
				Decor.CORALS[shelfRng:NextInteger(1, #Decor.CORALS)],
				shelfRng:NextNumber(0.2, 0.7)
			)
			Decor.upright(
				parent,
				"ShelfJar",
				stall * CFrame.new(x, y + 0.18, postZ),
				h,
				shelfRng:NextNumber(0.35, 0.5)
			).Color =
				tint
		end
	end
	-- The awning: stripes in the vendor's colour and canvas, sloping to the front
	local stripes = 6
	local width = 13.6
	local back, front = postZ + 0.6, -size.Z / 2 - 2.2
	local high, low = top, 9.6
	local run = back - front
	local slope = math.atan2(high - low, run)
	local span = math.sqrt(run * run + (high - low) ^ 2)
	local middle = stall * CFrame.new(0, (high + low) / 2, (back + front) / 2) * CFrame.Angles(-slope, 0, 0)
	for k = 0, stripes - 1 do
		local x = -width / 2 + (k + 0.5) * width / stripes
		part(parent, {
			Name = "Awning",
			Size = Vector3.new(width / stripes, 0.35, span),
			CFrame = middle * CFrame.new(x, 0, 0),
			Color = if k % 2 == 0 then color else CANVAS,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
	end
	Decor.disc(
		parent,
		"AwningRidge",
		stall * CFrame.new(0, high + 0.1, back) * CFrame.Angles(0, math.rad(-90), 0),
		0.35,
		width + 0.6
	).Color =
		Decor.BRASS
	-- The valance: a band along the front edge with scallops hanging under it
	local edge = stall * CFrame.new(0, low - 0.25, front - 0.05)
	part(parent, {
		Name = "Valance",
		Size = Vector3.new(width + 0.2, 1.0, 0.3),
		CFrame = edge,
		Color = color:Lerp(Color3.new(0, 0, 0), 0.15),
		CanCollide = false,
	})
	local scallops = 7
	for k = 0, scallops - 1 do
		local x = -width / 2 + (k + 0.5) * width / scallops
		Decor.disc(parent, "Scallop", edge * CFrame.new(x, -0.5, 0.1), width / scallops / 2 - 0.05, 0.2).Color = if k
					% 2
				== 0
			then CANVAS
			else color
	end
	-- Lanterns hanging at the front corners
	for side = -1, 1, 2 do
		Decor.lantern(parent, edge * CFrame.new(side * (width / 2 - 0.8), -2.6, 0.6), 0, true, 14)
		part(parent, {
			Name = "LanternRope",
			Size = Vector3.new(0.14, 1.1, 0.14),
			CFrame = edge * CFrame.new(side * (width / 2 - 0.8), -0.75, 0.6),
			Color = Decor.IRON,
			CanCollide = false,
			CastShadow = false,
		})
	end
	-- The sign standing on the awning's front edge, leaning back a little
	local sign = Decor.plaque(
		parent,
		stall * CFrame.new(0, low + 1.85, front + 0.6) * CFrame.Angles(math.rad(-10), 0, 0),
		Vector2.new(11.4, 2.9),
		color:Lerp(Color3.fromRGB(10, 30, 40), 0.55),
		false
	)
	sign.title.Text = string.upper(vendor.name)
	sign.board.Name = "Sign"
	goods(parent, vendor.id, stall * CFrame.new(0, size.Y + 0.5, -0.2), color)
	return counter
end

-- The vendor stalls round the plaza (Config/Shop). The client shows its own
-- "E · Shop" hint near a counter (MenuController): a ProximityPrompt never showed
-- for the custom fish character (playtest 2026-10-06).
function Plaza.vendors(parent: Instance)
	local market = Instance.new("Folder")
	market.Name = "Vendors"
	for _, vendor in Config.Shop.vendors do
		local angle = math.rad(vendor.angle)
		local stall = Instance.new("Model")
		stall.Name = vendor.id
		local frame = facingIn(angle, Layout.COUNTER_RADIUS, PLAZA_TOP)
		local counter = stallParts(stall, vendor, frame)
		counter:SetAttribute("Vendor", vendor.id)
		keeper(
			stall,
			facingIn(angle, 36.2, PLAZA_TOP + 4.2),
			facingIn(angle, 32, PLAZA_TOP + 3.75)
				* CFrame.new(-KEEPER_SIDE, 0, 0)
				* CFrame.Angles(0, KEEPER_TURN, 0),
			vendor.color:Lerp(Color3.new(1, 1, 1), 0.25),
			vendor.id
		)
		stall.Parent = market
	end
	market.Parent = parent
end

return Plaza
