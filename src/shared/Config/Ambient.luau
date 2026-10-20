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
--   jelly   drifting jellyfish: a pale bell with a frilled glowing margin, frilly oral
--           arms and fine glowing tentacles that trail as it swims
--   ray     blue-spotted stingrays gliding low over the sand, now and then settling
--           into it with a puff of sand and lifting off again
--   manta   reef mantas flying slow loops over the reef and the wrecks
--   turtle  green sea turtles rowing big slow loops over the shelf
--   cloud   clouds of tiny reef fish hovering round coral heads (found near the camera)
--   giant   a humpback or a giant manta passing far off through the Open Blue's haze
--
-- Crabs are food now (Config/Forage, drawn by ForageController with the same rig).
--
-- The rays, mantas, turtles and giants are their imported models
-- (ReplicatedStorage.AmbientModels.<model>: tools/blender/rig_ambient.py, docs/ASSETS.md)
-- or, until those are in, faceted part-built stand-ins; both are posed by
-- Shared/AmbientRigs (`rig`), whose stand-ins take their colours from `look` (by role;
-- `colors` are each creature's pick for its main role, `tint`).
export type Kind = {
	biomes: { string },
	perCell: number, -- creatures a square, on average
	range: number, -- studs from the camera it's drawn within
	depth: { number }?, -- over the local floor (`floor` kinds sit on it)
	size: { number }, -- studs: a jelly's bell, a ray's or manta's span, a turtle's
	-- length beak to tail
	speed: { number }?, -- studs/s
	colors: { Color3 },
	max: number, -- at most this many near the camera
	rig: string?, -- Shared/AmbientRigs: its skeleton, motion and stand-in
	model: string?, -- ReplicatedStorage.AmbientModels.<model>
	beat: { number }?, -- seconds a flap, stroke or ripple (each creature its own)
	-- Studs from the camera within which its joints move every frame (to twice that,
	-- every other frame; past that they hold their last pose)
	animate: number?,
	look: { [string]: Color3 }?, -- the stand-in's colours by role
	tint: string?, -- the role `colors` picks for
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
		-- (a part-built ray's back, as the model's olive green: its pick of these)
		colors = {
			Color3.fromRGB(70, 100, 74), -- olive green
			Color3.fromRGB(62, 96, 82), -- sea green
			Color3.fromRGB(78, 100, 66), -- olive
		},
		max = 10,
		rig = "stingray",
		model = "Stingray",
		beat = { 1.3, 1.9 },
		animate = 90,
		tint = "top",
		look = {
			top = Color3.fromRGB(70, 100, 74),
			top2 = Color3.fromRGB(62, 90, 66),
			belly = Color3.fromRGB(118, 134, 148),
			spot = Color3.fromRGB(40, 132, 255),
			eye = Color3.fromRGB(18, 22, 28),
			dark = Color3.fromRGB(38, 46, 54),
		},
	},
	manta = {
		biomes = { "CoralReef", "ShipwreckGraveyard" },
		perCell = 0.05,
		range = 320,
		depth = { 22, 70 },
		size = { 9, 15 },
		speed = { 4, 6.5 },
		colors = { Color3.fromRGB(30, 38, 52) },
		max = 3,
		rig = "manta",
		model = "Manta",
		beat = { 3.4, 4.4 },
		animate = 320,
		tint = "top",
		look = {
			top = Color3.fromRGB(30, 38, 52),
			top2 = Color3.fromRGB(25, 32, 45),
			patch = Color3.fromRGB(88, 106, 126),
			belly = Color3.fromRGB(98, 112, 130),
			dark = Color3.fromRGB(19, 23, 31),
			eye = Color3.fromRGB(8, 10, 14),
		},
	},
	turtle = {
		biomes = { "KelpShallows", "CoralReef", "ShipwreckGraveyard" },
		perCell = 0.22,
		range = 230,
		depth = { 14, 70 },
		size = { 5, 8.5 },
		speed = { 3, 4.5 },
		colors = {
			Color3.fromRGB(86, 96, 52),
			Color3.fromRGB(78, 92, 58),
			Color3.fromRGB(96, 88, 54),
		},
		max = 6,
		rig = "turtle",
		model = "Turtle",
		beat = { 3.6, 4.6 },
		animate = 140,
		tint = "scute",
		look = {
			scute = Color3.fromRGB(86, 96, 52),
			scute2 = Color3.fromRGB(72, 82, 44),
			rim = Color3.fromRGB(60, 66, 38),
			belly = Color3.fromRGB(104, 112, 82),
			skin = Color3.fromRGB(86, 100, 70),
			skin2 = Color3.fromRGB(72, 86, 60),
			beak = Color3.fromRGB(96, 102, 78),
			eye = Color3.fromRGB(14, 16, 18),
		},
	},
	cloud = {
		biomes = { "CoralReef", "ShipwreckGraveyard", "KelpShallows", "SunkenRuins" },
		perCell = 0, -- (round the coral heads found near the camera, not by square)
		range = 75,
		size = { 0.55, 0.95 }, -- fry: smaller than any prey (a Minnow is ~1.2)
		colors = {
			Color3.fromRGB(250, 210, 40),
			Color3.fromRGB(40, 120, 230),
			Color3.fromRGB(250, 132, 28),
			Color3.fromRGB(40, 200, 170),
			Color3.fromRGB(122, 84, 214),
		},
		-- None since 2026-10-20: the clouds over the coral are real prey now (Config/Prey
		-- `laterZones`), edible and in the Catch Log (owner: "every fish should be
		-- edible ... unless it is a buff fish or boost fish")
		max = 0, -- clouds
	},
	giant = {
		biomes = { "OpenBlue" },
		perCell = 0, -- (lanes across the Open Blue, below)
		range = 460,
		size = { 55, 80 }, -- a whale's length (a manta's span is 0.42 of it)
		speed = { 5, 8 },
		colors = {
			Color3.fromRGB(44, 58, 76), -- whale
			Color3.fromRGB(30, 36, 48), -- manta
		},
		max = 3,
		animate = 1000, -- (only ever three, and big: always moving)
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
	-- The species a cloud is made of, by the biome it's in (their models from
	-- PreyModels shrunk to fry size; part-built fish while one isn't imported)
	cloudPrey = {
		KelpShallows = { "Garibaldi", "Opaleye" },
		CoralReef = { "BlueTang", "Butterflyfish" },
		ShipwreckGraveyard = { "Butterflyfish", "BlueTang" },
		SunkenRuins = { "BlueTang", "Butterflyfish" },
		default = { "BlueTang" },
	} :: { [string]: { string } },
	-- The giants: `lanes` at a time, each crossing the Open Blue on a line `lane`
	-- studs long over `period` seconds (the same on every client), seen only past
	-- `near` (part-built shapes, read as silhouettes in the haze: the Open Blue's
	-- water shows ~280 studs, Config/Bosses `sight`)
	giants = {
		lanes = 5,
		period = 170,
		lane = 1100,
		near = 140,
		-- The two giants' models, rigs, beats and stand-in looks
		whale = {
			rig = "whale",
			model = "Humpback",
			beat = { 6.5, 8.5 },
			look = {
				top = Color3.fromRGB(56, 72, 94),
				top2 = Color3.fromRGB(50, 66, 88),
				belly = Color3.fromRGB(108, 126, 146),
				belly2 = Color3.fromRGB(96, 114, 134),
			},
		},
		manta = {
			rig = "manta",
			model = "Manta",
			beat = { 4.8, 6 },
			look = {
				top = Color3.fromRGB(30, 38, 52),
				top2 = Color3.fromRGB(25, 32, 45),
				patch = Color3.fromRGB(80, 98, 118),
				belly = Color3.fromRGB(92, 106, 124),
				dark = Color3.fromRGB(19, 23, 31),
				eye = Color3.fromRGB(8, 10, 14),
			},
		},
	},
	-- A stingray's day (AmbientRigs.rayTravel): every `cycle` seconds it eases down onto
	-- the sand over `ease` s, lies `rest` s, and lifts off again; a puff of sand rises
	-- as it lands and as it leaves, within `puffRange` studs of the camera
	settle = { cycle = { 28, 44 }, rest = { 5, 9 }, ease = 2.4, puffRange = 110 },
	-- Joint turns written a frame at most, over every creature (bones and stand-ins)
	jointBudget = 380,
	-- Everything fades away while a world boss is up within `bossClear` studs, and the
	-- giants hide while one is up anywhere (the Megalodon owns the Open Blue's dread and
	-- comes out of the blue the same way; the squid's ink is its own)
	bossClear = 600,
}
