--!strict
-- The biomes, where they are round the hub, and the level each is meant for
-- (owner, 2026-10-06: layout approved "as long as areas are gated by suggested
-- level"). Entering a biome shows its name and suggested levels; entering one above
-- your fish's level warns that it's too dangerous for now (BiomeController).
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
}

local list: { Biome } = {
	{
		id = "KelpShallows",
		name = "Kelp Shallows",
		minLevel = 1,
		maxLevel = 10,
		angleFrom = 0,
		angleTo = 360,
		radiusFrom = 0,
		radiusTo = 420,
		live = true,
		color = Color3.fromRGB(150, 220, 120),
	},
	{
		id = "CoralReef",
		name = "Coral Reef",
		minLevel = 10,
		maxLevel = 25,
		angleFrom = -45,
		angleTo = 45,
		radiusFrom = 420,
		radiusTo = 1100,
		live = true,
		color = Color3.fromRGB(255, 130, 170),
	},
	{
		id = "AbyssalTrench",
		name = "Abyssal Trench",
		minLevel = 80,
		maxLevel = 100,
		angleFrom = 45,
		angleTo = 135,
		radiusFrom = 420,
		radiusTo = 1100,
		live = true,
		color = Color3.fromRGB(110, 230, 255),
	},
	{
		id = "ShipwreckGraveyard",
		name = "Shipwreck Graveyard",
		minLevel = 20,
		maxLevel = 40,
		angleFrom = 135,
		angleTo = 225,
		radiusFrom = 420,
		radiusTo = 1100,
		live = true,
		color = Color3.fromRGB(150, 200, 150),
	},
	{
		id = "OpenBlue",
		name = "Open Blue",
		minLevel = 35,
		maxLevel = 55,
		angleFrom = 225,
		angleTo = 315,
		radiusFrom = 420,
		radiusTo = 1100,
		live = true,
		color = Color3.fromRGB(100, 170, 255),
	},
	-- Later: beyond the Reef, and beyond (below) the Trench. Frozen Shelf was dropped
	-- for now (owner: not much sea life there); it may come back in an update.
	{
		id = "SunkenRuins",
		name = "Sunken Ruins",
		minLevel = 50,
		maxLevel = 70,
		angleFrom = -45,
		angleTo = 45,
		radiusFrom = 1100,
		radiusTo = 1600,
		live = false,
		color = Color3.fromRGB(120, 240, 220),
	},
	{
		id = "HydrothermalVents",
		name = "Hydrothermal Vents",
		minLevel = 65,
		maxLevel = 85,
		angleFrom = 45,
		angleTo = 135,
		radiusFrom = 1100,
		radiusTo = 1600,
		live = false,
		color = Color3.fromRGB(255, 140, 70),
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
