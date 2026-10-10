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
}
