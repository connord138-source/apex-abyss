--!strict
-- The playable species (owner-approved roster, 2026-10-06). Each levels up on its
-- own (its own banked mass), has its own stats and abilities, and is unlocked its
-- own way: the Nibbler from the start, the rest with their home biome's DNA plus
-- coral (the 'Cuda also wants a grown Nibbler; it came free with the tutorial until
-- the owner, 2026-10-17: "should take a bit longer to get cuda than just finishing
-- the tutorial ... Nobody would ever play as the nibbler if thats the case"). Stats are multipliers on the shared
-- size math (1 = the Nibbler, the all-rounder).
export type Stats = {
	speed: number, -- top speed
	turn: number, -- how fast the heading can swing
	health: number, -- in bite fights
	bite: number, -- bite damage
}

export type Unlock = {
	kind: "start" | "tutorial" | "dna",
	biome: string?, -- dna: whose DNA (Config/Biomes id)
	dna: number?,
	coral: number?,
	level: number?, -- the Nibbler must have reached this level first
}

export type Species = {
	id: string,
	name: string,
	role: string,
	-- A hunter of big game: only a predator fish can hurt a whale (Config/Ambient
	-- `whale.hunt`; owner, 2026-10-28: "Low level fish and non predator players
	-- shouldnt be able to hurt the whale")
	predator: boolean?,
	blurb: string,
	plan: string, -- body plan (Shared/FishPlans)
	home: string, -- biome id
	back: Color3,
	belly: Color3,
	fin: Color3,
	stats: Stats,
	collider: number, -- collider thickness (the eel slips through gaps)
	camera: number?, -- camera distance × this (thin fish sit closer so they read)
	abilities: { string }, -- ability options (picked in its tree; the Nibbler has one)
	signature: string, -- the ability on its button (Config/Abilities)
	-- What it's good at and what to watch out for, short and kid-readable, from its
	-- stats and signature (owner, 2026-10-18: "The perks for each fish and their
	-- drawbacks need to be listed on the ui where the player selects their fish")
	perks: { string },
	drawbacks: { string },
	unlock: Unlock,
}

local list: { Species } = {
	{
		id = "Nibbler",
		name = "Nibbler",
		role = "All-rounder",
		blurb = "Everyone's first fish. Good at everything, and its Dash gets it out of trouble.",
		plan = "Nibbler",
		home = "KelpShallows",
		back = Color3.fromRGB(246, 140, 40),
		belly = Color3.fromRGB(255, 214, 90),
		fin = Color3.fromRGB(236, 104, 40),
		stats = { speed = 1, turn = 1, health = 1, bite = 1 },
		collider = 1,
		abilities = { "Dash" },
		signature = "Dash",
		perks = {
			"Good at everything, no weak spot",
			"DASH: the quickest recharge of any fish",
			"Free from the start",
		},
		drawbacks = {
			"No special trick besides its Dash",
			"Average bite and health",
		},
		unlock = { kind = "start" },
	},
	{
		id = "Cuda",
		name = "'Cuda",
		role = "Speed hunter",
		predator = true,
		blurb = "The fastest fish in a straight line. Hits hard, turns wide.",
		plan = "Cuda",
		home = "KelpShallows",
		-- Bright silver with yellow fins: plain grey (2026-10-06) and steel blue
		-- (2026-10-07) both vanished into the water at speed
		back = Color3.fromRGB(176, 192, 204),
		belly = Color3.fromRGB(248, 250, 252),
		fin = Color3.fromRGB(240, 192, 56),
		stats = { speed = 1.25, turn = 0.8, health = 0.85, bite = 1.1 },
		collider = 0.85,
		camera = 0.8,
		abilities = { "Torpedo", "RazorBite", "SilverFlash" },
		signature = "Torpedo",
		perks = {
			"Fastest fish in a straight line",
			"TORPEDO: a long sprint nothing outruns",
			"Bites a little harder",
		},
		drawbacks = {
			"Turns wide",
			"Less health than most",
			"Can't dodge while Torpedoing",
		},
		unlock = { kind = "dna", biome = "KelpShallows", dna = 40, coral = 1500, level = 15 },
	},
	{
		id = "Pufferfish",
		name = "Pufferfish",
		role = "Tank",
		blurb = "Slow, spiny and very hard to eat.",
		plan = "Puffer",
		home = "CoralReef",
		back = Color3.fromRGB(196, 156, 96),
		belly = Color3.fromRGB(242, 228, 192),
		fin = Color3.fromRGB(176, 136, 80),
		stats = { speed = 0.8, turn = 1.05, health = 1.6, bite = 0.85 },
		collider = 1.25,
		abilities = { "PuffUp", "SpikeBurst", "ToxicCloud" },
		signature = "PuffUp",
		perks = {
			"Most health of any fish",
			"PUFF UP: bites do half, hurts biters",
			"Turns quickly",
		},
		drawbacks = {
			"Slowest swimmer",
			"Weak bite",
			"Very slow while puffed up",
		},
		unlock = { kind = "dna", biome = "CoralReef", dna = 100, coral = 2500 },
	},
	{
		id = "MorayEel",
		name = "Moray Eel",
		role = "Ambusher",
		predator = true,
		blurb = "Quick, sneaky, and thin enough to slip through gaps nothing its size can.",
		plan = "Eel",
		home = "ShipwreckGraveyard",
		back = Color3.fromRGB(96, 150, 60),
		belly = Color3.fromRGB(192, 212, 120),
		fin = Color3.fromRGB(78, 128, 48),
		stats = { speed = 1.1, turn = 1.25, health = 0.95, bite = 1.15 },
		collider = 0.55,
		camera = 0.8,
		abilities = { "Strike", "Burrow", "Shock" },
		signature = "Burrow",
		perks = {
			"Sharpest turns of any fish",
			"Thin: slips through gaps others can't",
			"BURROW: hide in rock, then ambush ×1.6",
			"Quick, with a strong bite",
		},
		drawbacks = {
			"A little less health",
			"Burrow needs rock or a wreck nearby",
		},
		unlock = { kind = "dna", biome = "ShipwreckGraveyard", dna = 120, coral = 6000 },
	},
	{
		id = "ReefShark",
		name = "Reef Shark",
		role = "Brawler",
		predator = true,
		blurb = "Built to bite. Wins fights it has no business winning.",
		plan = "Shark",
		home = "OpenBlue",
		back = Color3.fromRGB(96, 108, 122),
		belly = Color3.fromRGB(228, 232, 234),
		fin = Color3.fromRGB(84, 96, 110),
		stats = { speed = 1.1, turn = 0.9, health = 1.15, bite = 1.35 },
		collider = 1,
		abilities = { "Frenzy", "BloodSense", "Ram" },
		signature = "BloodSense",
		perks = {
			"Hardest bite of any fish",
			"BLOOD SENSE: see every fish through rock",
			"Quick and tough",
		},
		drawbacks = {
			"Turns a bit wide",
			"Blood Sense takes 24 s to recharge",
		},
		unlock = { kind = "dna", biome = "OpenBlue", dna = 150, coral = 15000 },
	},
	{
		id = "Anglerfish",
		name = "Anglerfish",
		role = "Lure hunter",
		predator = true,
		blurb = "Lives in the dark, and lets dinner come to it.",
		plan = "Angler",
		home = "AbyssalTrench",
		back = Color3.fromRGB(42, 52, 84),
		belly = Color3.fromRGB(74, 84, 116),
		fin = Color3.fromRGB(32, 42, 70),
		stats = { speed = 0.85, turn = 0.9, health = 1.25, bite = 1.25 },
		collider = 1.1,
		abilities = { "Lure", "LanternFlash", "DeepSight" },
		signature = "LanternFlash",
		perks = {
			"Big bite and lots of health",
			"LANTERN FLASH: stuns predators near you",
			"Its lure lights up dark water",
		},
		drawbacks = {
			"Slow swimmer",
			"Turns wide",
		},
		unlock = { kind = "dna", biome = "AbyssalTrench", dna = 200, coral = 40000 },
	},
}

local byId: { [string]: Species } = {}
for _, species in list do
	byId[species.id] = species
end

return {
	list = list,
	byId = byId,
	STARTER = "Nibbler",
}
