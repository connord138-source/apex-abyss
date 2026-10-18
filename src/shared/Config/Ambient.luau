--!strict
-- Sea life that isn't food (owner, 2026-10-18: "We still need so much more fish too. I
-- feel like the ocean has a pretty empty feeling", and on the water: "Think
-- Subnautica", whose biomes are busy with life everywhere). Drawn by each client on
-- its own (AmbientLifeController): nothing is sent, nothing can be eaten or hurt you.
--
-- The sea is cut into CELL-stud squares; each square's creatures come from a seed of
-- its position, and each one moves on the shared clock, so a place always holds the
-- same life doing the same thing, whenever you swim back. Only squares near the
-- camera are built, and each creature fades in and out at the edge of its `range`.
--
-- Kinds (`biomes` are Config/Biomes ids; `depth` is studs over the local floor):
--   jelly   drifting jellyfish: a pale bell, a Neon rim and trailing glowing tentacles
--   ray     rays gliding low over the sand
--   crab    crabs scuttling sideways on the floor, mostly on and beside rocks and wrecks
--   turtle  sea turtles cruising the shelf
--   cloud   clouds of tiny reef fish hovering round coral heads (found near the camera)
--   giant   a whale or a manta passing far off through the Open Blue's haze
export type Kind = {
	biomes: { string },
	perCell: number, -- creatures a square, on average
	range: number, -- studs from the camera it's drawn within
	depth: { number }?, -- over the local floor (`floor` kinds sit on it)
	size: { number }, -- studs (a jelly's bell, a ray's span, a crab's width, a turtle's shell)
	speed: { number }?, -- studs/s
	colors: { Color3 },
	max: number, -- at most this many near the camera
}

local CELL = 96

local kinds: { [string]: Kind } = {
	jelly = {
		biomes = { "OpenBlue", "SunkenRuins", "AbyssalTrench", "HydrothermalVents" },
		perCell = 2.4,
		range = 210,
		depth = { 30, 360 },
		size = { 1.6, 4.6 },
		speed = { 0.6, 1.6 },
		-- (the rims and tentacles; the bell is a paler, see-through version)
		colors = {
			Color3.fromRGB(90, 200, 255),
			Color3.fromRGB(80, 255, 210),
			Color3.fromRGB(160, 120, 255),
			Color3.fromRGB(120, 230, 255),
		},
		max = 48,
	},
	ray = {
		biomes = { "KelpShallows", "CoralReef", "ShipwreckGraveyard" },
		perCell = 0.55,
		range = 170,
		depth = { 1.5, 4 },
		size = { 4.5, 9 },
		speed = { 3, 6 },
		colors = {
			Color3.fromRGB(104, 108, 92), -- sand-grey stingray
			Color3.fromRGB(38, 50, 72), -- navy eagle ray
			Color3.fromRGB(82, 92, 104), -- slate
		},
		max = 10,
	},
	crab = {
		biomes = { "ShipwreckGraveyard", "CoralReef", "SunkenRuins", "KelpShallows" },
		perCell = 2.5,
		range = 100,
		size = { 0.9, 2.1 },
		speed = { 1.5, 3 },
		colors = {
			Color3.fromRGB(196, 72, 38),
			Color3.fromRGB(214, 112, 34),
			Color3.fromRGB(118, 70, 46),
			Color3.fromRGB(86, 78, 140),
		},
		max = 24,
	},
	turtle = {
		biomes = { "KelpShallows", "CoralReef", "ShipwreckGraveyard" },
		perCell = 0.22,
		range = 230,
		depth = { 14, 70 },
		size = { 3.5, 6 },
		speed = { 3, 4.5 },
		colors = {
			Color3.fromRGB(96, 90, 52),
			Color3.fromRGB(78, 92, 58),
			Color3.fromRGB(104, 80, 50),
		},
		max = 6,
	},
	cloud = {
		biomes = { "CoralReef", "ShipwreckGraveyard", "KelpShallows", "SunkenRuins" },
		perCell = 0, -- (round the coral heads found near the camera, not by square)
		range = 75,
		size = { 0.35, 0.6 },
		colors = {
			Color3.fromRGB(250, 210, 40),
			Color3.fromRGB(40, 120, 230),
			Color3.fromRGB(250, 132, 28),
			Color3.fromRGB(40, 200, 170),
			Color3.fromRGB(122, 84, 214),
		},
		max = 8, -- clouds
	},
	giant = {
		biomes = { "OpenBlue" },
		perCell = 0, -- (lanes across the Open Blue, below)
		range = 560,
		size = { 55, 80 }, -- a whale's length (a manta's span is a third of it)
		speed = { 5, 8 },
		colors = {
			Color3.fromRGB(44, 58, 76), -- whale
			Color3.fromRGB(30, 36, 48), -- manta
		},
		max = 3,
	},
}

return {
	CELL = CELL,
	kinds = kinds,
	-- Coral heads with a reef-fish cloud: one cloud per `cloudCell`-stud square that
	-- holds a coral piece, the nearest `kinds.cloud.max`, looked for every `cloudScan` s
	cloudCell = 22,
	cloudScan = 1,
	cloudFish = { 6, 12 },
	-- The giants: `lanes` at a time, each crossing the Open Blue on a line `lane`
	-- studs long over `period` seconds, seen only between `near` and the kind's range
	-- (part-built shapes: never close enough to look at)
	giants = { lanes = 4, period = 170, lane = 1100, near = 190 },
	-- Everything fades away while a world boss is up within `bossClear` studs (the
	-- Megalodon owns the Open Blue's dread; the squid's ink is its own)
	bossClear = 600,
}
