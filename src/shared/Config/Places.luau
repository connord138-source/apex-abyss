--!strict
-- Named places (owner, 2026-10-21: the biome detail boards, "Each landmark is a named
-- place: on the map, and a first-visit reward in the LOG"). Two a biome: the
-- landmarks the biome builders raise (Wrecks.luau, TrenchDress.luau, KelpDress.luau,
-- ReefDress.luau, BlueDress.luau) and the Ruins' and Vents' own (Ruins.luau,
-- VentsPlan.luau). Each builder publishes where its place ended up as a Vector3
-- attribute named by the id on Workspace.Places (PlaceMarks.set), so the map, the
-- minimap's name bar and LandmarkService all read one spot, whatever the layout did.
--
-- A fish whose middle comes within `radius` of a place for the first time finds it:
-- LandmarkService marks `data.places[id]`, pays `reward` (RewardsService.grant) and
-- toasts it; the LOG's Places page lists them ("Places 3/14"). `dig` names the
-- treasure-map tiers whose dig site may be put here (TreasureService: a Captain's map
-- to the Broken Galleon's cabin).
local Rewards = require(script.Parent.Rewards)

export type Place = {
	id: string,
	name: string,
	biome: string, -- Config/Biomes id
	radius: number, -- studs from its spot that count as visiting it
	blurb: string, -- the LOG's line
	reward: Rewards.Reward,
	dig: { string }?, -- Config/Treasure tiers that may bury their chest here
	digHint: string?, -- the map's hint for a chest buried here
}

local list: { Place } = {
	{
		id = "KelpCathedral",
		name = "The Kelp Cathedral",
		biome = "KelpShallows",
		radius = 90,
		blurb = "A ring of giant kelp round an open nave, the light coming down its middle",
		reward = { coral = 150, shells = 10 },
	},
	{
		id = "OtterMeadow",
		name = "Otter Meadow",
		biome = "KelpShallows",
		radius = 60,
		blurb = "Sea grass, purple urchins and otters floating overhead",
		reward = { coral = 150, shells = 10 },
	},
	{
		id = "BrokenGalleon",
		name = "The Broken Galleon",
		biome = "ShipwreckGraveyard",
		radius = 80,
		blurb = "A galleon broken in two; its captain's cabin still burns its lamps",
		reward = { coral = 300, shells = 15 },
		dig = { "Weathered", "Captain" },
		digHint = "Under the lit windows of the Broken Galleon's stern",
	},
	{
		id = "FallenLighthouse",
		name = "The Fallen Lighthouse",
		biome = "ShipwreckGraveyard",
		radius = 60,
		blurb = "The lighthouse that warned the ships, lying across the sand",
		reward = { coral = 300, shells = 15 },
	},
	{
		id = "BlueHole",
		name = "The Blue Hole",
		biome = "CoralReef",
		radius = 80,
		blurb = "A ring of reef round a sinkhole into the dark",
		reward = { coral = 500, shells = 20 },
	},
	{
		id = "ClamGarden",
		name = "The Clam Garden",
		biome = "CoralReef",
		radius = 60,
		blurb = "Giant clams holding pearls; bite one (it grows back)",
		reward = { coral = 500, shells = 20 },
	},
	{
		id = "WhalesRest",
		name = "The Whale's Rest",
		biome = "OpenBlue",
		radius = 90,
		blurb = "The bones of a great whale on the floor of the deep blue",
		reward = { coral = 800, shells = 25 },
	},
	{
		id = "HammerheadPinnacle",
		name = "Hammerhead Pinnacle",
		biome = "OpenBlue",
		radius = 90,
		blurb = "A lone spire rising out of the deep, hammerheads circling it",
		reward = { coral = 800, shells = 25 },
	},
	{
		id = "GreatTemple",
		name = "The Great Temple",
		biome = "SunkenRuins",
		radius = 90,
		blurb = "The drowned city's temple at the end of its avenue",
		reward = { coral = 1200, shells = 30 },
	},
	{
		id = "SunkenTheatre",
		name = "The Sunken Theatre",
		biome = "SunkenRuins",
		radius = 70,
		blurb = "Tiers of stone seats round a mosaic floor",
		reward = { coral = 1200, shells = 30 },
	},
	{
		id = "TheForge",
		name = "The Forge",
		biome = "HydrothermalVents",
		radius = 110,
		blurb = "The vent mountain, its crater full of lava",
		reward = { coral = 1600, shells = 35 },
	},
	{
		id = "BrinePool",
		name = "The Brine Pool",
		biome = "HydrothermalVents",
		radius = 60,
		blurb = "A lake on the sea floor, heavier than the sea round it",
		reward = { coral = 1600, shells = 35 },
	},
	{
		id = "LeviathanSpine",
		name = "The Leviathan's Spine",
		biome = "AbyssalTrench",
		radius = 100,
		blurb = "The skeleton of an ancient serpent arching over the canyon",
		reward = { coral = 2000, shells = 40 },
	},
	{
		id = "SquidLair",
		name = "The Squid's Lair",
		biome = "AbyssalTrench",
		radius = 60,
		blurb = "The cave the Giant Squid rises from, its eggs glowing in the dark",
		reward = { coral = 2000, shells = 40, map = "Captain" },
	},
}

local byId: { [string]: Place } = {}
for _, place in list do
	byId[place.id] = place
end

return {
	list = list,
	byId = byId,
	checkSeconds = 1, -- how often LandmarkService looks where everyone is
	-- Every place found: a bonus on top of the last one's reward
	allFound = { coral = 5000, shells = 100, spins = 2 } :: Rewards.Reward,
	-- The chance a map whose tier a place lists buries its chest at that place
	digChance = 0.3,
	-- The landmarks' play (LandmarkService checks each on the server; the client's
	-- LandmarkController sends them and draws what happens)
	-- The Broken Galleon's bell: BITE it within `reach` studs and it rings for everyone
	-- near (heard to `heard` studs); a fish rings it once a `cooldown`
	bell = { reach = 9, heard = 260, cooldown = 3 },
	-- The Bay Cannon: swim into its muzzle (within `reach`) and it fires you `speed`
	-- studs a second along its aim for `seconds`; once a `cooldown` a fish
	cannon = { reach = 9, speed = 95, seconds = 1.3, cooldown = 6 },
	-- The Clam Garden's pearls: BITE one within `reach` for `reward`; it's gone for
	-- that fish for `regrow` seconds (kept in the save, so leaving doesn't reset it)
	pearl = { reach = 6, regrow = 900, reward = { coral = 120, shells = 6 } :: Rewards.Reward },
}
