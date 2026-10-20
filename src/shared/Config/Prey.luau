--!strict
-- The NPC prey fish. Mass is in kg; body length comes from mass the same way as for
-- players (Size.length). Schools are placed from these by Shared/Schools.luau. New
-- prey go at the end of the list: Schools lays the list out in order from one seed,
-- so a prey added after the others moves none of their schools.
-- Where some of a prey's schools live: a distance band, a sector round the hub
-- (degrees from +X toward +Z, clockwise; nil = all round) and a depth band
export type Zone = {
	band: { number },
	angles: { number }?,
	schools: number,
	depth: { number }?,
	-- Only out while this tide is up (Config/Tides, `schools`): the Sardine Run's
	-- bait balls. Built after every other school, so they never move the others.
	tide: string?,
	perSchool: number?, -- fish in each of these schools (default: the prey's)
	-- The school's shape (owner, 2026-10-18: "We still need so much more fish too. I
	-- feel like the ocean has a pretty empty feeling"): `spread` × the prey's (0.55 a
	-- tight bait ball, 1.5 a loose shoal), `round` makes it a ball as deep as it is
	-- wide, `pathRadius` its own loop (a bait ball turns on the spot)
	spread: number?,
	round: boolean?,
	pathRadius: { number }?,
	-- Down in the Abyssal Trench's canyon, along its line (`band` is ignored)
	trench: boolean?,
	-- Over one of the Hydrothermal Vents' basins, inside its rim (Seafloor.ventBasins;
	-- `band` and `angles` are ignored)
	vents: boolean?,
}

export type PreyDef = {
	id: string,
	name: string, -- what players see (the Catch Log, toasts, the chase warning)
	-- Its home biome (Config/Biomes id): where it's mostly found and what the Catch Log
	-- files it under. Many swim in other biomes too (`zones`); DNA always comes from
	-- the biome a fish is eaten in (HuntService).
	biome: string,
	mass: number,
	schools: number, -- how many schools of it
	perSchool: number, -- fish in each school
	spread: number, -- school size, in body lengths
	speed: number, -- studs/s along its path
	pathRadius: { number }, -- min, max radius of its loop
	depth: { number }, -- min, max height above the local floor (Shared/Seafloor)
	band: { number }?, -- distance from the hub its schools roam (default: the shallows ring on the shelf)
	zones: { Zone }?, -- instead of one band: several places, each with its own schools (and depth)
	tideZones: { Zone }?, -- schools that only come out with a tide (each zone sets `tide`)
	-- Schools added after the layout was set (2026-10-20), built after every other
	-- school, the tides' included, from their own seed, so no school moved: the little
	-- clouds hovering low over the coral and rock (owner: "every fish should be edible
	-- and attributable to the catch log unless it is a buff fish or boost fish"; they
	-- were AmbientLife's client-only fry, which no one could eat), and more kinds in
	-- the Coral Reef ("largest variety of fish needs to be coral reef")
	laterZones: { Zone }?,
	-- Seconds after being eaten (owner, 2026-10-20: "a lvl 100 fish can absolutely
	-- decimate an ecosystem too so the fish need a high respawn rate": ~⅓ of the old
	-- 8–40 s). A fish comes back swimming in from behind its school as it grows
	-- (SchoolController `RETURN`), never popping in where it was eaten.
	respawn: number,
	back: Color3,
	belly: Color3,
	slim: number, -- body height / length (0.2 = eel-thin, 0.4 = deep-bodied)
	-- Longer than its mass makes it, × this (owner, 2026-10-19: "The smallest fish like
	-- minnows etc need to be slightly larger. They're a hard target and they're small.
	-- I think making them larger will make the scene fuller when it shows them in
	-- schools"): drawn, swallowed and hit that long (Shared/Schools `length`, `radius`),
	-- its kg the same and its school no wider, so it reads fuller. Kept under the
	-- swallow ratio of the level that hunts it (a LV 1 fish still eats Minnows, a LV 5
	-- one most Garibaldi)
	look: number?,
	-- Never turns on a smaller fish (AggroService): a drifter like the Ocean Sunfish
	-- chasing anyone down would be silly
	calm: boolean?,
}

-- Where the deep biomes are (Config/Biomes; the deep floor starts past the drop-off,
-- 850–940 out), for the zones below
local DEEP = { 980, 1440 }
local OPEN_BLUE = { 228, 312 }
local RUINS = { 318, 64 }
local VENTS = { 128, 222 }
local TRENCH = { 990, 1430 } -- (a `trench` zone runs along the canyon instead)
local WRECKS = { 138, 222 } -- the Shipwreck Graveyard's bay on the shelf, 480–850 out
local REEF = { 228, 132 } -- the Coral Reef: the rest of the shelf's outer band
local OUTER = { 500, 830 }

local list: { PreyDef } = {
	{
		id = "Minnow",
		name = "Minnow",
		biome = "KelpShallows",
		mass = 0.1,
		look = 1.25,
		schools = 14,
		perSchool = 14,
		spread = 3.2,
		speed = 7,
		pathRadius = { 18, 34 },
		depth = { 20, 120 },
		-- Plenty near the hub and low over the sand, where a new fish swims (owner,
		-- 2026-10-10: "needs a lot more smaller fish ... far too scarce"; 14 schools
		-- 20–120 up over the whole shelf were hard to find)
		zones = {
			{ band = { 150, 340 }, schools = 16, depth = { 4, 45 } }, -- (22 until the Opaleye and the Kelp Bass)
			{ band = { 340, 560 }, schools = 12, depth = { 6, 80 } },
			{ band = { 560, 830 }, schools = 8 },
			-- (2026-10-18, "the ocean has a pretty empty feeling") loose clouds over the
			-- wrecks' sand, tight clouds low round the reef's coral heads and flickers
			-- among the Ruins' columns (the Vents' and the Trench's minnow schools became
			-- Ghost Shrimp swarms and Lanternfish, the second prey batch, below)
			{ band = OUTER, angles = WRECKS, schools = 6, depth = { 4, 40 }, spread = 1.6 },
			-- (11 until the Butterflyfish came)
			{ band = OUTER, angles = REEF, schools = 6, perSchool = 18, depth = { 3, 32 }, spread = 0.8 },
			{ band = DEEP, angles = RUINS, schools = 10, depth = { 6, 50 } },
		} :: { Zone },
		respawn = 3,
		back = Color3.fromRGB(122, 150, 160),
		belly = Color3.fromRGB(214, 226, 230),
		slim = 0.22,
	},
	{
		id = "Sardine",
		name = "Sardine",
		biome = "KelpShallows",
		mass = 0.3,
		look = 1.15,
		schools = 14,
		perSchool = 10,
		spread = 3,
		speed = 9,
		pathRadius = { 24, 44 },
		depth = { 30, 160 },
		zones = {
			{ band = { 150, 420 }, schools = 8, depth = { 8, 70 } }, -- (12 until the Opaleye and the Kelp Bass)
			{ band = { 420, 830 }, schools = 12 },
			-- (2026-10-18) bait balls turning on the spot in the Open Blue's mid-water
			-- and low over the reef, loose shoals out in the blue, and schools over the
			-- Ruins, the Vents' warm basins and down the Trench
			{
				band = DEEP,
				angles = OPEN_BLUE,
				schools = 10, -- (14 until the Yellowfin Tuna came)
				perSchool = 34,
				depth = { 150, 400 },
				round = true,
				spread = 0.55,
				pathRadius = { 10, 22 },
			},
			{
				band = DEEP,
				angles = OPEN_BLUE,
				schools = 12,
				perSchool = 16,
				depth = { 140, 420 },
				spread = 1.4,
			},
			{
				band = OUTER,
				angles = REEF,
				schools = 5,
				perSchool = 28,
				depth = { 25, 90 },
				round = true,
				spread = 0.55,
				pathRadius = { 10, 20 },
			},
			{ band = DEEP, angles = RUINS, schools = 12, perSchool = 14, depth = { 40, 180 } },
			{
				band = DEEP,
				angles = VENTS,
				schools = 3, -- (10 until the Ghost Shrimp came, 6 until the Vent Eelpout)
				perSchool = 24,
				depth = { 60, 200 },
				round = true,
				spread = 0.6,
				pathRadius = { 12, 24 },
			},
			-- (the Trench's 6 schools of 16 became Gulper Eels, Oarfish and Lanternfish,
			-- the third prey batch, 2026-10-19)
		} :: { Zone },
		-- The Sardine Run's bait balls: big tight schools in the Kelp Shallows and over
		-- the reef, out only while it's up
		tideZones = {
			{ band = { 170, 470 }, schools = 5, perSchool = 36, depth = { 40, 140 }, tide = "Sardine" },
			{ band = { 520, 820 }, schools = 3, perSchool = 36, depth = { 50, 180 }, tide = "Sardine" },
		},
		respawn = 4,
		back = Color3.fromRGB(64, 104, 140),
		belly = Color3.fromRGB(205, 218, 228),
		slim = 0.24,
	},
	{
		id = "Wrasse",
		name = "Kelp Wrasse",
		biome = "KelpShallows",
		mass = 0.9,
		schools = 12,
		perSchool = 6,
		spread = 2.6,
		speed = 7,
		pathRadius = { 20, 36 },
		depth = { 10, 90 },
		zones = {
			{ band = { 150, 830 }, schools = 12 }, -- (its old single band)
			-- (2026-10-18) loose shoals over the wrecks and the reef, and in the Ruins
			{ band = OUTER, angles = WRECKS, schools = 3, perSchool = 8, depth = { 6, 50 }, spread = 1.5 }, -- (6 before the Triggerfish)
			{ band = OUTER, angles = REEF, schools = 6, perSchool = 8, depth = { 5, 45 } }, -- (10 before the Blue Tang)
			{ band = DEEP, angles = RUINS, schools = 7, perSchool = 7, depth = { 10, 80 } }, -- (12 before the Lionfish, 9 before the Humphead Wrasse)
		} :: { Zone },
		respawn = 4,
		back = Color3.fromRGB(196, 120, 64),
		belly = Color3.fromRGB(236, 196, 140),
		slim = 0.32,
	},
	{
		id = "Snapper",
		name = "Snapper",
		biome = "CoralReef",
		mass = 2.5,
		schools = 5,
		perSchool = 4,
		spread = 2.4,
		speed = 8,
		pathRadius = { 26, 48 },
		depth = { 20, 120 },
		zones = {
			{ band = { 150, 830 }, schools = 8 },
			-- (its old 4 Open Blue schools went to the Swordfish and the Ocean Sunfish, 2026-10-19)
			-- (2026-10-18) every biome past the kelp has its snappers
			{ band = OUTER, angles = REEF, schools = 10, perSchool = 6, depth = { 10, 70 } },
			{ band = OUTER, angles = WRECKS, schools = 5, perSchool = 5, depth = { 10, 60 } },
			{
				band = DEEP,
				angles = OPEN_BLUE,
				schools = 12,
				perSchool = 8,
				depth = { 140, 400 },
				spread = 1.3,
			},
			-- (2026-10-19: Ruins 12, Vents 12 and Trench 5 until the Coelacanth, the Vent
			-- Eelpout and the Gulper Eel took some over; then Vents 6 until the Rattail, and
			-- the Trench's canyon 3 until the Viperfish and the Hatchetfish)
			{ band = DEEP, angles = RUINS, schools = 10, perSchool = 6, depth = { 20, 120 } },
			{ band = DEEP, angles = VENTS, schools = 3, perSchool = 6, depth = { 30, 160 } },
			{ band = DEEP, angles = { 70, 123 }, schools = 6, perSchool = 5, depth = { 20, 140 } }, -- the Trench's rim
		} :: { Zone },
		respawn = 5,
		back = Color3.fromRGB(200, 72, 70),
		belly = Color3.fromRGB(240, 186, 170),
		slim = 0.34,
	},
	{
		id = "Grouper",
		name = "Grouper",
		biome = "ShipwreckGraveyard",
		mass = 8,
		schools = 4,
		perSchool = 2,
		spread = 2,
		speed = 5,
		pathRadius = { 20, 40 },
		depth = { 8, 60 },
		zones = {
			{ band = { 520, 830 }, schools = 5 },
			{ band = { 980, 1440 }, angles = { 228, 312 }, schools = 5, depth = { 140, 380 } }, -- Open Blue haul, mid-water
			{ band = { 980, 1440 }, angles = { 318, 64 }, schools = 2 }, -- the Ruins
			-- (2026-10-18) lone groupers lurking low round the wrecks and the ruins,
			-- small groups on the reef, pairs in the Vents and the Trench
			{
				band = OUTER,
				angles = WRECKS,
				schools = 3, -- (6 before the Lingcod)
				perSchool = 1,
				depth = { 4, 32 },
				pathRadius = { 12, 24 },
			},
			{ band = OUTER, angles = REEF, schools = 5, perSchool = 3, depth = { 8, 50 } },
			{
				band = DEEP,
				angles = RUINS,
				schools = 3, -- (10 before the Coelacanth, 6 before the Humphead Wrasse)
				perSchool = 1,
				depth = { 6, 50 },
				pathRadius = { 14, 28 },
			},
			{ band = DEEP, angles = OPEN_BLUE, schools = 6, perSchool = 3, depth = { 150, 400 } },
			{ band = DEEP, angles = VENTS, schools = 6, perSchool = 2, depth = { 15, 90 } }, -- (12 before the Rattail)
			{ band = DEEP, angles = { 70, 123 }, schools = 4, perSchool = 2, depth = { 15, 100 } }, -- the Trench's rim
			{ band = TRENCH, trench = true, schools = 3, perSchool = 2, depth = { 20, 160 } }, -- (6 before the Viperfish)
		} :: { Zone },
		respawn = 7,
		back = Color3.fromRGB(96, 92, 70),
		belly = Color3.fromRGB(176, 168, 130),
		slim = 0.4,
	},
	{
		id = "Barracuda",
		name = "Barracuda",
		biome = "CoralReef",
		mass = 20,
		schools = 4,
		perSchool = 1,
		spread = 1,
		speed = 12,
		pathRadius = { 50, 90 },
		depth = { 40, 180 },
		zones = {
			{ band = { 700, 1250 }, schools = 4 },
			{ band = { 980, 1440 }, angles = { 228, 312 }, schools = 2, depth = { 150, 400 } },
			-- (2026-10-18) lone hunters on the reef, the wrecks, the Ruins, the Vents and
			-- the Trench, and hunting packs of three in the Open Blue
			{ band = OUTER, angles = REEF, schools = 5, depth = { 20, 90 } },
			{ band = OUTER, angles = WRECKS, schools = 2, depth = { 15, 80 } },
			{ band = DEEP, angles = OPEN_BLUE, schools = 6, perSchool = 3, depth = { 150, 400 } },
			{ band = DEEP, angles = RUINS, schools = 5, depth = { 30, 160 } },
			{ band = DEEP, angles = VENTS, schools = 8, depth = { 30, 180 } },
			{
				band = TRENCH,
				trench = true,
				schools = 5,
				depth = { 30, 240 },
				pathRadius = { 30, 60 },
			},
		} :: { Zone },
		respawn = 9,
		back = Color3.fromRGB(110, 124, 132),
		belly = Color3.fromRGB(210, 216, 220),
		slim = 0.18,
	},
	{
		id = "ReefShark",
		name = "Reef Shark",
		biome = "OpenBlue",
		mass = 60,
		schools = 3,
		perSchool = 1,
		spread = 1,
		speed = 10,
		pathRadius = { 70, 120 },
		depth = { 40, 160 },
		zones = {
			{ band = { 980, 1440 }, angles = { 228, 312 }, schools = 4, depth = { 150, 430 } }, -- the Open Blue is shark water, mid-water
			{ band = { 980, 1440 }, angles = { 318, 64 }, schools = 1 },
			-- (2026-10-18) more sharks cruising the deep: the Open Blue, the Ruins, the
			-- Vents and the Trench (none on the shelf, where they'd outsize everyone)
			{ band = DEEP, angles = OPEN_BLUE, schools = 4, depth = { 150, 430 } },
			{ band = DEEP, angles = RUINS, schools = 4, depth = { 40, 180 } },
			{ band = DEEP, angles = VENTS, schools = 5, depth = { 40, 200 } },
			{
				band = TRENCH,
				trench = true,
				schools = 5,
				depth = { 40, 260 },
				pathRadius = { 40, 70 },
			},
		} :: { Zone },
		respawn = 12,
		back = Color3.fromRGB(92, 104, 114),
		belly = Color3.fromRGB(222, 226, 228),
		slim = 0.26,
	},
	-- The second batch (owner approved the PreySheetA concepts, 2026-10-18): one new fish
	-- for each biome, from the docs/ASSETS.md prey2_fbx models. Each took schools over
	-- from the Minnows, Sardines and Wrasse rather than adding to them, so the sea holds
	-- about as many fish as before (tools/tests/run_density.sh).
	{
		-- A small, bright orange damselfish keeping to its patch of kelp, low down
		id = "Garibaldi",
		name = "Garibaldi",
		biome = "KelpShallows",
		mass = 0.4, -- (a LV 5 fish can swallow most of them)
		look = 1.08,
		schools = 8,
		perSchool = 5,
		spread = 2.6,
		speed = 5,
		pathRadius = { 10, 22 },
		depth = { 3, 28 },
		zones = {
			{ band = { 160, 460 }, schools = 8, spread = 1.2 },
		} :: { Zone },
		laterZones = {
			{
				band = { 180, 460 },
				schools = 6,
				perSchool = 6,
				spread = 0.9,
				pathRadius = { 4, 9 },
				depth = { 2, 6 },
			},
		} :: { Zone },
		respawn = 4,
		back = Color3.fromRGB(240, 104, 20),
		belly = Color3.fromRGB(255, 140, 36),
		slim = 0.55,
	},
	{
		-- A chunky mottled cod lurking low among the wrecks in threes
		id = "WreckCod",
		name = "Wreck Cod",
		biome = "ShipwreckGraveyard",
		mass = 1.5, -- (swallowed from about LV 15, the Wrecks' middle)
		schools = 8,
		perSchool = 3,
		spread = 2.2,
		speed = 4,
		pathRadius = { 12, 26 },
		depth = { 4, 30 },
		zones = {
			{ band = OUTER, angles = WRECKS, schools = 8 },
		} :: { Zone },
		respawn = 6,
		back = Color3.fromRGB(106, 100, 58),
		belly = Color3.fromRGB(172, 178, 176),
		slim = 0.3,
	},
	{
		-- A bulky teal parrotfish grazing the reef's coral heads in small groups
		id = "Parrotfish",
		name = "Parrotfish",
		biome = "CoralReef",
		mass = 4,
		schools = 10,
		perSchool = 4,
		spread = 2.4,
		speed = 6,
		pathRadius = { 18, 34 },
		depth = { 4, 36 },
		zones = {
			{ band = OUTER, angles = REEF, schools = 10 },
		} :: { Zone },
		respawn = 5,
		back = Color3.fromRGB(36, 150, 140),
		belly = Color3.fromRGB(96, 196, 176),
		slim = 0.4,
	},
	{
		-- Fast, tight schools sweeping wide loops through the Open Blue's mid-water: the
		-- quickest prey in the sea, hard to run down
		id = "YellowfinTuna",
		name = "Yellowfin Tuna",
		biome = "OpenBlue",
		mass = 35,
		schools = 7,
		perSchool = 8,
		spread = 2.2,
		speed = 16,
		pathRadius = { 70, 130 },
		depth = { 160, 420 },
		zones = {
			{ band = DEEP, angles = OPEN_BLUE, schools = 7, spread = 0.7 },
		} :: { Zone },
		respawn = 8,
		back = Color3.fromRGB(32, 48, 84),
		belly = Color3.fromRGB(196, 206, 220),
		slim = 0.3,
	},
	{
		-- Gold-and-green dolphinfish cruising high in the Open Blue in threes
		id = "MahiMahi",
		name = "Mahi-mahi",
		biome = "OpenBlue",
		mass = 22,
		schools = 6,
		perSchool = 3,
		spread = 2.4,
		speed = 13,
		pathRadius = { 50, 90 },
		depth = { 180, 430 },
		zones = {
			{ band = DEEP, angles = OPEN_BLUE, schools = 6 },
		} :: { Zone },
		respawn = 8,
		back = Color3.fromRGB(56, 140, 88),
		belly = Color3.fromRGB(222, 196, 52),
		slim = 0.3,
	},
	{
		-- Hovering in pairs low among the Ruins' stones. Venomous: swallowing one stings
		-- (`venom` below, HuntService)
		id = "Lionfish",
		name = "Lionfish",
		biome = "SunkenRuins",
		mass = 10,
		schools = 12,
		perSchool = 2,
		spread = 2,
		speed = 3,
		pathRadius = { 8, 16 },
		depth = { 4, 28 },
		zones = {
			{ band = DEEP, angles = RUINS, schools = 12 },
		} :: { Zone },
		laterZones = {
			{ band = OUTER, angles = REEF, schools = 6, depth = { 3, 18 } }, -- (the Coral Reef's too)
		} :: { Zone },
		respawn = 6,
		back = Color3.fromRGB(176, 70, 32),
		belly = Color3.fromRGB(58, 46, 44),
		slim = 0.45,
	},
	{
		-- Swarms of little glowing-tipped shrimp over the Vents' warm basins (and a few in
		-- the kelp)
		id = "GhostShrimp",
		name = "Ghost Shrimp",
		biome = "HydrothermalVents",
		mass = 0.2,
		look = 1.2,
		schools = 8,
		perSchool = 26,
		spread = 2.2,
		speed = 4,
		pathRadius = { 8, 16 },
		depth = { 6, 50 },
		zones = {
			{ band = DEEP, vents = true, schools = 10, round = true, spread = 0.7 }, -- (8 until 2026-10-19)
			-- and a few smaller swarms low among the kelp, a fifth small fish for new
			-- players (the Catch Log's goals count species)
			{
				band = { 170, 460 },
				schools = 3,
				perSchool = 16,
				depth = { 4, 30 },
				round = true,
				spread = 0.8,
			},
		} :: { Zone },
		respawn = 3,
		back = Color3.fromRGB(150, 176, 198),
		belly = Color3.fromRGB(186, 206, 222),
		slim = 0.22,
	},
	{
		-- Small dark fish with glowing light spots, schooling in the Trench's dark water
		id = "Lanternfish",
		name = "Lanternfish",
		biome = "AbyssalTrench",
		mass = 0.5,
		look = 1.12,
		schools = 10,
		perSchool = 18,
		spread = 2.6,
		speed = 7,
		pathRadius = { 20, 40 },
		depth = { 20, 220 },
		zones = {
			{ band = TRENCH, trench = true, schools = 10 }, -- (8 until 2026-10-19)
		} :: { Zone },
		respawn = 3,
		back = Color3.fromRGB(30, 40, 72),
		belly = Color3.fromRGB(58, 80, 122),
		slim = 0.26,
	},
	-- The third batch (owner approved the PreySheetB concepts, 2026-10-19), from the
	-- docs/ASSETS.md prey3_fbx models: a native for the reef and the wrecks, and big
	-- natives for the deep, where the Vents and the Trench had borrowed the shelf's
	-- Sardines and Snappers. They took schools over from the Minnows, Wrasse, Sardines,
	-- Snappers and Groupers, so the sea still holds about as many fish (run_density.sh).
	{
		-- Pairs and small groups of little yellow discs flitting low round the coral
		id = "Butterflyfish",
		name = "Butterflyfish",
		biome = "CoralReef",
		mass = 1.2, -- (swallowed from about LV 13)
		schools = 12,
		perSchool = 5,
		spread = 2.4,
		speed = 5,
		pathRadius = { 8, 18 },
		depth = { 3, 30 },
		zones = {
			{ band = OUTER, angles = REEF, schools = 12 },
		} :: { Zone },
		laterZones = {
			{
				band = OUTER,
				angles = REEF,
				schools = 20,
				perSchool = 7,
				spread = 0.9,
				pathRadius = { 4, 9 },
				depth = { 2, 6 },
			},
			{
				band = OUTER,
				angles = WRECKS,
				schools = 8,
				perSchool = 6,
				spread = 0.9,
				pathRadius = { 4, 9 },
				depth = { 2, 6 },
			},
		} :: { Zone },
		respawn = 4,
		back = Color3.fromRGB(240, 196, 30),
		belly = Color3.fromRGB(250, 214, 60),
		slim = 0.6,
	},
	{
		-- Stout navy triggerfish with white-spotted bellies, picking round the wrecks
		id = "Triggerfish",
		name = "Triggerfish",
		biome = "ShipwreckGraveyard",
		mass = 2.2, -- (swallowed from about LV 19, the Wrecks' upper half)
		schools = 7,
		perSchool = 4,
		spread = 2.2,
		speed = 5,
		pathRadius = { 12, 24 },
		depth = { 4, 40 },
		zones = {
			{ band = OUTER, angles = WRECKS, schools = 7 },
		} :: { Zone },
		laterZones = {
			{ band = OUTER, angles = REEF, schools = 6 }, -- (the Coral Reef's too)
		} :: { Zone },
		respawn = 5,
		back = Color3.fromRGB(28, 36, 72),
		belly = Color3.fromRGB(226, 230, 236),
		slim = 0.5,
	},
	{
		-- Lone swordfish sweeping huge loops through the Open Blue: the fastest fish
		-- in the sea, a big meal for a fish near the top of the blue
		id = "Swordfish",
		name = "Swordfish",
		biome = "OpenBlue",
		mass = 55, -- (swallowed from about LV 51)
		schools = 6,
		perSchool = 1,
		spread = 1,
		speed = 18,
		pathRadius = { 90, 160 },
		depth = { 160, 420 },
		zones = {
			{ band = DEEP, angles = OPEN_BLUE, schools = 6 },
		} :: { Zone },
		respawn = 10,
		back = Color3.fromRGB(72, 62, 150),
		belly = Color3.fromRGB(200, 210, 222),
		slim = 0.18,
	},
	{
		-- Huge, slow, round sunfish drifting alone high in the Open Blue: the biggest
		-- meal in the blue, only for a fish at its very top
		id = "OceanSunfish",
		name = "Ocean Sunfish",
		biome = "OpenBlue",
		calm = true,
		mass = 80, -- (swallowed from about LV 54)
		schools = 5,
		perSchool = 1,
		spread = 1,
		speed = 2.5,
		pathRadius = { 40, 80 },
		depth = { 260, 410 },
		zones = {
			{ band = DEEP, angles = OPEN_BLUE, schools = 5 },
		} :: { Zone },
		respawn = 14,
		back = Color3.fromRGB(128, 140, 150),
		belly = Color3.fromRGB(176, 188, 196),
		slim = 0.75,
	},
	{
		-- Heavy, ancient lobe-finned fish lurking in pairs low among the Ruins' stones
		id = "Coelacanth",
		name = "Coelacanth",
		biome = "SunkenRuins",
		mass = 14, -- (swallowed from about LV 37)
		schools = 8,
		perSchool = 2,
		spread = 2,
		speed = 3,
		-- (a wide, low loop: on a tight one a fish this long pitches steeply enough to
		-- nose into the rocks the lift clears, run_schools.sh)
		pathRadius = { 16, 30 },
		depth = { 10, 40 },
		zones = {
			{ band = DEEP, angles = RUINS, schools = 8 },
		} :: { Zone },
		respawn = 9,
		back = Color3.fromRGB(52, 84, 112),
		belly = Color3.fromRGB(84, 116, 140),
		slim = 0.28,
	},
	{
		-- Big-headed, ember-speckled eelpouts nosing along the Vents' basin floors
		id = "VentEelpout",
		name = "Vent Eelpout",
		biome = "HydrothermalVents",
		mass = 4, -- (a small fish down there; swallowed from about LV 25)
		schools = 10,
		perSchool = 4,
		spread = 2.4,
		speed = 2.5,
		pathRadius = { 14, 26 }, -- (wide, like the Coelacanth's)
		depth = { 6, 22 },
		zones = {
			{ band = DEEP, vents = true, schools = 10 },
		} :: { Zone },
		respawn = 6,
		back = Color3.fromRGB(58, 56, 60),
		belly = Color3.fromRGB(82, 78, 80),
		slim = 0.25,
	},
	{
		-- Black gulper eels, all mouth and whip tail, hanging in threes in the Trench
		id = "GulperEel",
		name = "Gulper Eel",
		biome = "AbyssalTrench",
		mass = 4, -- (light for its length, like the Eelpout)
		schools = 8,
		perSchool = 3,
		spread = 2.6,
		speed = 4,
		pathRadius = { 20, 40 },
		depth = { 40, 260 },
		zones = {
			{ band = TRENCH, trench = true, schools = 8 },
		} :: { Zone },
		respawn = 8,
		back = Color3.fromRGB(22, 22, 28),
		belly = Color3.fromRGB(40, 36, 46),
		slim = 0.2,
	},
	{
		-- Long silver oarfish with red crests, drifting alone through the Trench's
		-- dark water: the heaviest prey in the sea
		id = "Oarfish",
		name = "Oarfish",
		calm = true,
		biome = "AbyssalTrench",
		mass = 120, -- (swallowed from about LV 58)
		schools = 3,
		perSchool = 1,
		spread = 1,
		speed = 3,
		pathRadius = { 40, 80 },
		depth = { 60, 300 },
		zones = {
			{ band = TRENCH, trench = true, schools = 3 },
		} :: { Zone },
		respawn = 60, -- (a rare meal: three of them, slower to come back; 180 until 2026-10-20)
		back = Color3.fromRGB(176, 190, 206),
		belly = Color3.fromRGB(200, 210, 222),
		slim = 0.09,
	},
	-- The fourth batch (owner approved the PreySheetC concepts, 2026-10-19), from the
	-- docs/ASSETS.md prey4_fbx models: real natives for the kelp (they took schools from
	-- its Minnows and Sardines), the reef, the wrecks and the Ruins, and more for the
	-- Vents and the Trench, where they took over the borrowed Snappers and Groupers.
	{
		-- A chunky, round olive kelp fish with two white spots, browsing low among the
		-- fronds in small groups
		id = "Opaleye",
		name = "Opaleye",
		biome = "KelpShallows",
		mass = 0.4, -- (swallowed from about LV 3: one of the five kinds a LV 5 fish eats here)
		look = 1.08,
		schools = 8,
		perSchool = 5,
		spread = 2.4,
		speed = 5,
		pathRadius = { 10, 22 },
		depth = { 4, 30 },
		zones = {
			{ band = { 160, 470 }, schools = 8 },
		} :: { Zone },
		laterZones = {
			{
				band = { 180, 460 },
				schools = 6,
				perSchool = 6,
				spread = 0.9,
				pathRadius = { 4, 9 },
				depth = { 2, 6 },
			},
		} :: { Zone },
		respawn = 4,
		back = Color3.fromRGB(112, 120, 50),
		belly = Color3.fromRGB(150, 158, 84),
		slim = 0.5,
	},
	{
		-- A big-mouthed, blotchy kelp bass hanging in pairs among the kelp: the top meal
		-- of the shallows
		id = "KelpBass",
		name = "Kelp Bass",
		biome = "KelpShallows",
		mass = 0.8, -- (swallowed from about LV 10, the kelp's top)
		schools = 5,
		perSchool = 2,
		spread = 2.4,
		speed = 6,
		pathRadius = { 14, 28 },
		depth = { 8, 60 },
		zones = {
			{ band = { 180, 470 }, schools = 5 },
		} :: { Zone },
		respawn = 4,
		back = Color3.fromRGB(100, 96, 54),
		belly = Color3.fromRGB(160, 168, 116),
		slim = 0.34,
	},
	{
		-- Royal-blue tangs with yellow tails, flitting round the reef's coral in groups
		id = "BlueTang",
		name = "Blue Tang",
		biome = "CoralReef",
		mass = 1.5, -- (swallowed from about LV 16)
		schools = 8,
		perSchool = 5,
		spread = 2.4,
		speed = 6,
		pathRadius = { 14, 28 },
		depth = { 6, 45 },
		zones = {
			{ band = OUTER, angles = REEF, schools = 8 },
		} :: { Zone },
		laterZones = {
			{
				band = OUTER,
				angles = REEF,
				schools = 16,
				perSchool = 7,
				spread = 0.9,
				pathRadius = { 4, 9 },
				depth = { 2, 6 },
			},
			{
				band = DEEP,
				angles = RUINS,
				schools = 6,
				perSchool = 6,
				spread = 0.9,
				pathRadius = { 4, 9 },
				depth = { 2, 6 },
			},
		} :: { Zone },
		respawn = 5,
		back = Color3.fromRGB(34, 84, 222),
		belly = Color3.fromRGB(60, 112, 232),
		slim = 0.6,
	},
	{
		-- A long, heavy, big-mouthed lingcod lying alone on the wrecks' sand
		id = "Lingcod",
		name = "Lingcod",
		biome = "ShipwreckGraveyard",
		mass = 3.2, -- (swallowed from about LV 23, the Wrecks' top)
		schools = 6,
		perSchool = 1,
		spread = 1,
		speed = 3,
		pathRadius = { 14, 26 }, -- (wide and low, like the Coelacanth's)
		depth = { 3, 18 },
		zones = {
			{ band = OUTER, angles = WRECKS, schools = 6 },
		} :: { Zone },
		respawn = 6,
		back = Color3.fromRGB(100, 112, 94),
		belly = Color3.fromRGB(170, 182, 164),
		slim = 0.24,
	},
	{
		-- Big-headed rattail grenadiers with ember-edged fins, nosing in threes along the
		-- Vents' basin floors
		id = "Rattail",
		name = "Rattail",
		biome = "HydrothermalVents",
		mass = 6,
		schools = 6,
		perSchool = 3,
		spread = 2.4,
		speed = 3,
		pathRadius = { 14, 26 }, -- (wide, like the Eelpout's)
		depth = { 5, 24 },
		zones = {
			{ band = DEEP, vents = true, schools = 6 },
		} :: { Zone },
		respawn = 7,
		back = Color3.fromRGB(86, 98, 118),
		belly = Color3.fromRGB(118, 130, 148),
		slim = 0.2,
	},
	{
		-- Black viperfish with glassy fangs and rows of glowing cyan spots (SchoolController
		-- GLOWS), hanging in threes in the Trench's dark water
		id = "Viperfish",
		name = "Viperfish",
		biome = "AbyssalTrench",
		mass = 1.8,
		schools = 6,
		perSchool = 3,
		spread = 2.6,
		speed = 4,
		pathRadius = { 20, 40 },
		depth = { 40, 260 },
		zones = {
			{ band = TRENCH, trench = true, schools = 6 },
		} :: { Zone },
		respawn = 6,
		back = Color3.fromRGB(24, 32, 54),
		belly = Color3.fromRGB(36, 48, 74),
		slim = 0.16,
	},
	{
		-- Little silver hatchetfish, tall as they're long, their keels lined with glowing
		-- cyan dots (GLOWS), schooling high in the Trench's canyon
		id = "Hatchetfish",
		name = "Hatchetfish",
		biome = "AbyssalTrench",
		mass = 0.25,
		look = 1.2,
		schools = 4,
		perSchool = 8,
		spread = 2.4,
		speed = 4,
		pathRadius = { 16, 32 },
		depth = { 30, 240 },
		zones = {
			{ band = TRENCH, trench = true, schools = 4 },
		} :: { Zone },
		respawn = 3,
		back = Color3.fromRGB(42, 74, 132),
		belly = Color3.fromRGB(168, 188, 212),
		slim = 0.95,
	},
	{
		-- Big, gentle blue-green humphead wrasse cruising alone among the Ruins' stones
		id = "HumpheadWrasse",
		name = "Humphead Wrasse",
		biome = "SunkenRuins",
		calm = true,
		mass = 25, -- (swallowed from about LV 43)
		schools = 4,
		perSchool = 1,
		spread = 1,
		speed = 3,
		pathRadius = { 18, 32 }, -- (a wide, low loop for a long fish)
		depth = { 10, 50 },
		zones = {
			{ band = DEEP, angles = RUINS, schools = 4 },
		} :: { Zone },
		laterZones = {
			{ band = OUTER, angles = REEF, schools = 2 }, -- (the Coral Reef's too)
		} :: { Zone },
		respawn = 10,
		back = Color3.fromRGB(38, 148, 160),
		belly = Color3.fromRGB(84, 182, 182),
		slim = 0.45,
	},
}

local byId: { [string]: PreyDef } = {}
for _, prey in list do
	byId[prey.id] = prey
end

return {
	list = list,
	byId = byId,
	-- How full the sea is (owner, 2026-10-20: "we still need so much more prey fish
	-- volume too. Too sparce"; ~3,660 fish before): every zone's `schools` × `schools`
	-- (× `deepSchools` past the drop-off, in the canyon and over the vents, where prey
	-- was thinnest), and every school of more than one fish × `perSchool` (lone
	-- hunters like the Barracuda stay alone), up to `perSchoolMax` (a bait ball already
	-- bigger keeps its size: the Open Blue's balls drew ~860 fish a frame at ×1.5).
	-- Applied by Schools.build, so the numbers
	-- in the entries above are the old ones. Rerun run_density.sh (a client's moved,
	-- waved and built fish), run_progress_sim.sh and run_catch_sim.sh after a change.
	fill = {
		schools = 1.4,
		deepSchools = 1.9,
		perSchool = 1.5,
		perSchoolMax = 30,
	},
	-- Swallowing (owner, 2026-10-17: "needs to be a bigger eat radius for eating
	-- smaller fish too. I've swam inches from one and if you don't directly hit the
	-- fish it doesn't eat it"): a fish small enough to swallow whole is eaten within
	-- the eater's reach (Size.reach, 0.42 × its length) × `scale`, plus `bonus` studs,
	-- plus the fish's own radius, of the mouth (it was the bare reach plus the radius);
	-- inside `pull` × that it's drawn toward the mouth, up to `pullShare` of the way
	-- at the lips, so it goes in from about 1.17 × that (Schools.eatReach, EAT_PULLED)
	eat = {
		scale = 1.15,
		bonus = 0.35,
		pull = 1.8,
		pullShare = 0.4,
	},
	-- Venomous prey (HuntService): swallowing one stings for `share` of the eater's max
	-- health (and heals nothing), full for a fish up to `fullRatio` × its raw length,
	-- less for a bigger one (share × fullRatio / ratio, never under `least`). A sting
	-- never kills: it stops at `floor` of max health. None in the hub (it's safe).
	venom = {
		Lionfish = { share = 0.06, fullRatio = 2.5, least = 0.01, floor = 0.05 },
	} :: { [string]: { share: number, fullRatio: number, least: number, floor: number } },
}
