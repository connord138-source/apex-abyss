--!strict
-- The biomes, where they are, and the level each is meant for (owner, 2026-10-06:
-- layout approved "as long as areas are gated by suggested level"; 2026-10-07:
-- "spread out and clearly different ... some dependent on depth off of a ocean
-- shelf ... coral zone being the last of the shallower zones"). Entering a biome
-- shows its name and suggested levels; entering one above your fish's level warns
-- that it's too dangerous for now (BiomeController).
--
-- The low-level biomes sit on the shelf (Config/World `shelf.radius`): the Kelp
-- Shallows ring round the hub, the Shipwreck Graveyard in the shelf's west bay and
-- the Coral Reef as the shelf's outer band everywhere else, ending at the drop-off.
-- The high-level biomes lie on the deep floor beyond it: Open Blue north, Sunken
-- Ruins east, Hydrothermal Vents south-west, and the Abyssal Trench canyon south.
--
-- Angles are degrees round the hub, measured from +X (east) toward +Z (south):
-- 0 = east, 90 = south, 180 = west, 270 = north. Radii are studs from the hub's
-- center. `live = false` biomes are planned but not in the world yet.
export type Biome = {
	id: string,
	name: string,
	minLevel: number,
	maxLevel: number,
	angleFrom: number, -- sector start (degrees; the sector runs clockwise to angleTo)
	angleTo: number,
	radiusFrom: number,
	radiusTo: number,
	live: boolean,
	color: Color3, -- the zone banner's accent
	deep: boolean, -- below the drop-off
	dark: boolean?, -- dark and murky: a light helps (an Anglerfish's lure, a Deep Lantern)
	water: Water?, -- its own water (OceanController)
}

-- Each biome's own water, Subnautica-style (owner, 2026-10-18: "Visibility needs to be
-- turned up too. We did good on the ocean look feel but went a bit too blue and its
-- hard to see anywhere other than the kelp area. Think Subnautica"): green-teal kelp,
-- grey-green wreck murk, turquoise reef, clear deep-blue open water, teal-cyan ruins,
-- the Vents' warm murk (OceanController VENTS_GRADE, by its basins) and the Trench's
-- creepy teal (Config/Tuning `light`, under its dark). OceanController grades the
-- water by depth (light, thickness, exposure) and blends these over it by how far
-- inside each biome the camera is, easing across every border, never popping.
-- `haze` and `decay` are the Atmosphere's colours where the light is the shelf
-- floor's (y 0); the depth's light scales them, so the same reef water is brighter
-- near the surface and a deep biome's darker on its floor. `tint` multiplies the
-- colour grade every fish is seen through: keep it near white with red at 255, so
-- skins read true (a greener grade turned gold skins lime, playtest 2026-10-10).
-- `density`, `exposure` and `saturation` are added to the depth's.
export type Water = {
	haze: Color3,
	decay: Color3,
	tint: Color3,
	density: number,
	exposure: number,
	saturation: number,
}

local SHELF = 850 -- Config/World shelf.radius
local EDGE = 1500 -- Config/World boundsRadius

local list: { Biome } = {
	{
		id = "KelpShallows",
		name = "Kelp Shallows",
		minLevel = 1,
		maxLevel = 10,
		angleFrom = 0,
		angleTo = 360,
		radiusFrom = 0,
		radiusTo = 480,
		live = true,
		color = Color3.fromRGB(150, 220, 120),
		deep = false,
		-- Green-teal, a little thicker among the fronds (it read best already)
		-- Bright turquoise like its scene (owner, 2026-10-21: "Make the shallows water
		-- bluer and brighter, like the concepts? yes"; it was a green-teal haze
		-- (56, 124, 106) the owner had liked on 2026-10-18); the light's tint stays
		-- near white so skins read true
		water = {
			haze = Color3.fromRGB(46, 152, 160),
			decay = Color3.fromRGB(14, 78, 88),
			tint = Color3.fromRGB(255, 255, 250),
			density = -0.02,
			exposure = 0.08,
			saturation = 0.04,
		},
	},
	{
		id = "ShipwreckGraveyard",
		name = "Shipwreck Graveyard",
		minLevel = 10,
		maxLevel = 25,
		angleFrom = 135,
		angleTo = 225,
		radiusFrom = 480,
		radiusTo = SHELF,
		live = true,
		color = Color3.fromRGB(150, 200, 150),
		deep = false,
		-- Grey-green murk, the thickest of the shallows and a little dimmer
		water = {
			haze = Color3.fromRGB(76, 108, 98),
			decay = Color3.fromRGB(30, 48, 44),
			tint = Color3.fromRGB(255, 252, 244),
			density = 0.04,
			exposure = -0.05,
			saturation = -0.06,
		},
	},
	{
		-- The last of the shallows: the shelf's outer band, north round to south
		id = "CoralReef",
		name = "Coral Reef",
		minLevel = 25,
		maxLevel = 40,
		angleFrom = 225,
		angleTo = 135,
		radiusFrom = 480,
		radiusTo = SHELF,
		live = true,
		color = Color3.fromRGB(255, 130, 170),
		deep = false,
		-- Clear, bright turquoise (the grade stays white: a cyan grade greens skins)
		-- Bright clear turquoise like its scene (owner, 2026-10-21, as the Kelp's)
		water = {
			haze = Color3.fromRGB(44, 162, 188),
			decay = Color3.fromRGB(12, 84, 108),
			tint = Color3.fromRGB(255, 255, 255),
			density = -0.05,
			exposure = 0.1,
			saturation = 0.06,
		},
	},
	{
		id = "OpenBlue",
		name = "Open Blue",
		minLevel = 35,
		maxLevel = 55,
		angleFrom = 225,
		angleTo = 315,
		radiusFrom = SHELF,
		radiusTo = EDGE,
		live = true,
		color = Color3.fromRGB(100, 170, 255),
		deep = true,
		-- Clear deep blue: open water the Megalodon is seen coming through
		-- Clear deep blue, the clearest deep water (PC 2026-10-19, VI1: it read dark
		-- navy at density 0.58, exposure −0.39)
		water = {
			haze = Color3.fromRGB(52, 122, 168),
			decay = Color3.fromRGB(16, 60, 104),
			tint = Color3.fromRGB(255, 255, 255),
			density = -0.08,
			exposure = 0.2,
			saturation = 0.04,
		},
	},
	{
		id = "SunkenRuins",
		name = "Sunken Ruins",
		minLevel = 50,
		maxLevel = 70,
		angleFrom = 315,
		angleTo = 68,
		radiusFrom = SHELF,
		radiusTo = EDGE,
		live = true,
		color = Color3.fromRGB(120, 240, 220),
		deep = true,
		-- Teal-cyan
		-- (PC 2026-10-19, VI1: dark blue-teal at 0.61 / −0.47, so the city read only
		-- to ~100 studs)
		water = {
			haze = Color3.fromRGB(44, 134, 146),
			decay = Color3.fromRGB(12, 66, 78),
			tint = Color3.fromRGB(255, 255, 255),
			density = -0.05,
			exposure = 0.14,
			saturation = 0.03,
		},
	},
	{
		id = "AbyssalTrench",
		name = "Abyssal Trench",
		minLevel = 80,
		maxLevel = 100,
		angleFrom = 68,
		angleTo = 125,
		radiusFrom = SHELF,
		radiusTo = EDGE,
		live = true,
		color = Color3.fromRGB(110, 230, 255),
		deep = true,
		dark = true,
		-- A murkier, greener teal over the canyon, hinting at the creepy dark below
		-- (down in it the dark's own water takes over: Config/Tuning `light`)
		water = {
			haze = Color3.fromRGB(32, 98, 102),
			decay = Color3.fromRGB(8, 40, 44),
			tint = Color3.fromRGB(255, 255, 248),
			density = 0.03,
			exposure = -0.05,
			saturation = -0.06,
		},
	},
	{
		id = "HydrothermalVents",
		name = "Hydrothermal Vents",
		minLevel = 65,
		maxLevel = 85,
		angleFrom = 125,
		angleTo = 225,
		radiusFrom = SHELF,
		radiusTo = EDGE,
		live = true,
		color = Color3.fromRGB(255, 140, 70),
		deep = true,
		-- Deep water with a grey warmth over the basins; down in them the warm murk
		-- (OceanController VENTS_GRADE)
		water = {
			haze = Color3.fromRGB(62, 90, 106),
			decay = Color3.fromRGB(24, 38, 50),
			tint = Color3.fromRGB(255, 253, 250),
			density = 0.01,
			exposure = 0,
			saturation = -0.02,
		},
	},
}

local byId: { [string]: Biome } = {}
for _, biome in list do
	byId[biome.id] = biome
end

return {
	list = list,
	byId = byId,
	-- How many levels under a biome's minimum still count as "ready" (no warning)
	warnSlack = 0,
}
