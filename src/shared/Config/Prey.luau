--!strict
-- NPC prey for the Kelp Shallows graybox. Mass is in kg; body length comes from
-- mass the same way as for players (Size.length). Schools are placed from these
-- by Shared/Schools.luau.
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
}

export type PreyDef = {
	id: string,
	name: string,
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
	respawn: number, -- seconds after being eaten
	back: Color3,
	belly: Color3,
	slim: number, -- body height / length (0.2 = eel-thin, 0.4 = deep-bodied)
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
		mass = 0.1,
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
			{ band = { 150, 340 }, schools = 22, depth = { 4, 45 } },
			{ band = { 340, 560 }, schools = 12, depth = { 6, 80 } },
			{ band = { 560, 830 }, schools = 8 },
			-- (2026-10-18, "the ocean has a pretty empty feeling") loose clouds over the
			-- wrecks' sand, tight clouds low round the reef's coral heads, flickers
			-- among the Ruins' columns and pale schools down in the Trench's canyon
			{ band = OUTER, angles = WRECKS, schools = 6, depth = { 4, 40 }, spread = 1.6 },
			{ band = OUTER, angles = REEF, schools = 14, perSchool = 18, depth = { 3, 30 }, spread = 0.8 },
			{ band = DEEP, angles = RUINS, schools = 10, depth = { 6, 50 } },
			{ band = DEEP, angles = VENTS, schools = 8, perSchool = 18, depth = { 20, 120 }, spread = 0.9 },
			{ band = TRENCH, trench = true, schools = 8, perSchool = 20, depth = { 15, 160 } },
		} :: { Zone },
		respawn = 8,
		back = Color3.fromRGB(122, 150, 160),
		belly = Color3.fromRGB(214, 226, 230),
		slim = 0.22,
	},
	{
		id = "Sardine",
		name = "Sardine",
		mass = 0.3,
		schools = 14,
		perSchool = 10,
		spread = 3,
		speed = 9,
		pathRadius = { 24, 44 },
		depth = { 30, 160 },
		zones = {
			{ band = { 150, 420 }, schools = 12, depth = { 8, 70 } },
			{ band = { 420, 830 }, schools = 12 },
			-- (2026-10-18) bait balls turning on the spot in the Open Blue's mid-water
			-- and low over the reef, loose shoals out in the blue, and schools over the
			-- Ruins, the Vents' warm basins and down the Trench
			{
				band = DEEP,
				angles = OPEN_BLUE,
				schools = 14,
				perSchool = 34,
				depth = { 150, 400 },
				round = true,
				spread = 0.55,
				pathRadius = { 10, 22 },
			},
			{ band = DEEP, angles = OPEN_BLUE, schools = 12, perSchool = 16, depth = { 140, 420 }, spread = 1.4 },
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
				schools = 10,
				perSchool = 24,
				depth = { 60, 200 },
				round = true,
				spread = 0.6,
				pathRadius = { 12, 24 },
			},
			{ band = TRENCH, trench = true, schools = 6, perSchool = 16, depth = { 30, 220 } },
		} :: { Zone },
		-- The Sardine Run's bait balls: big tight schools in the Kelp Shallows and over
		-- the reef, out only while it's up
		tideZones = {
			{ band = { 170, 470 }, schools = 5, perSchool = 36, depth = { 40, 140 }, tide = "Sardine" },
			{ band = { 520, 820 }, schools = 3, perSchool = 36, depth = { 50, 180 }, tide = "Sardine" },
		},
		respawn = 10,
		back = Color3.fromRGB(64, 104, 140),
		belly = Color3.fromRGB(205, 218, 228),
		slim = 0.24,
	},
	{
		id = "Wrasse",
		name = "Kelp Wrasse",
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
			{ band = OUTER, angles = WRECKS, schools = 6, perSchool = 8, depth = { 6, 50 }, spread = 1.5 },
			{ band = OUTER, angles = REEF, schools = 10, perSchool = 8, depth = { 5, 45 } },
			{ band = DEEP, angles = RUINS, schools = 12, perSchool = 7, depth = { 10, 80 } },
		} :: { Zone },
		respawn = 12,
		back = Color3.fromRGB(196, 120, 64),
		belly = Color3.fromRGB(236, 196, 140),
		slim = 0.32,
	},
	{
		id = "Snapper",
		name = "Snapper",
		mass = 2.5,
		schools = 5,
		perSchool = 4,
		spread = 2.4,
		speed = 8,
		pathRadius = { 26, 48 },
		depth = { 20, 120 },
		zones = {
			{ band = { 150, 830 }, schools = 8 },
			{ band = { 980, 1440 }, angles = { 228, 312 }, schools = 4, depth = { 150, 420 } }, -- Open Blue haul, mid-water
			-- (2026-10-18) every biome past the kelp has its snappers
			{ band = OUTER, angles = REEF, schools = 10, perSchool = 6, depth = { 10, 70 } },
			{ band = OUTER, angles = WRECKS, schools = 5, perSchool = 5, depth = { 10, 60 } },
			{ band = DEEP, angles = OPEN_BLUE, schools = 12, perSchool = 8, depth = { 140, 400 }, spread = 1.3 },
			{ band = DEEP, angles = RUINS, schools = 12, perSchool = 6, depth = { 20, 120 } },
			{ band = DEEP, angles = VENTS, schools = 12, perSchool = 6, depth = { 30, 160 } },
			{ band = TRENCH, trench = true, schools = 5, perSchool = 6, depth = { 30, 200 } },
			{ band = DEEP, angles = { 70, 123 }, schools = 6, perSchool = 5, depth = { 20, 140 } }, -- the Trench's rim
		} :: { Zone },
		respawn = 15,
		back = Color3.fromRGB(200, 72, 70),
		belly = Color3.fromRGB(240, 186, 170),
		slim = 0.34,
	},
	{
		id = "Grouper",
		name = "Grouper",
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
				schools = 6,
				perSchool = 1,
				depth = { 4, 30 },
				pathRadius = { 12, 24 },
			},
			{ band = OUTER, angles = REEF, schools = 5, perSchool = 3, depth = { 8, 50 } },
			{ band = DEEP, angles = RUINS, schools = 10, perSchool = 1, depth = { 6, 50 }, pathRadius = { 14, 28 } },
			{ band = DEEP, angles = OPEN_BLUE, schools = 6, perSchool = 3, depth = { 150, 400 } },
			{ band = DEEP, angles = VENTS, schools = 12, perSchool = 2, depth = { 15, 90 } },
			{ band = DEEP, angles = { 70, 123 }, schools = 4, perSchool = 2, depth = { 15, 100 } }, -- the Trench's rim
			{ band = TRENCH, trench = true, schools = 6, perSchool = 2, depth = { 20, 160 } },
		} :: { Zone },
		respawn = 20,
		back = Color3.fromRGB(96, 92, 70),
		belly = Color3.fromRGB(176, 168, 130),
		slim = 0.4,
	},
	{
		id = "Barracuda",
		name = "Barracuda",
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
		respawn = 25,
		back = Color3.fromRGB(110, 124, 132),
		belly = Color3.fromRGB(210, 216, 220),
		slim = 0.18,
	},
	{
		id = "ReefShark",
		name = "Reef Shark",
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
		respawn = 35,
		back = Color3.fromRGB(92, 104, 114),
		belly = Color3.fromRGB(222, 226, 228),
		slim = 0.26,
	},
}

local byId: { [string]: PreyDef } = {}
for _, prey in list do
	byId[prey.id] = prey
end

return {
	list = list,
	byId = byId,
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
}
