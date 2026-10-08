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
	dark: boolean?, -- pitch dark: bring a light (an Anglerfish's lure, a Deep Lantern)
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
