--!strict
-- The playable species (owner-approved roster, 2026-10-06). Each levels up on its
-- own (its own banked mass), has its own stats and abilities, and is unlocked its
-- own way: the Nibbler from the start, the 'Cuda by finishing the tutorial, the
-- rest with their home biome's DNA plus coral. Stats are multipliers on the shared
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
}

export type Species = {
	id: string,
	name: string,
	role: string,
	blurb: string,
	plan: string, -- body plan (Shared/FishPlans)
	home: string, -- biome id
	back: Color3,
	belly: Color3,
	fin: Color3,
	stats: Stats,
	collider: number, -- collider thickness (the eel slips through gaps)
	abilities: { string }, -- ability options (picked in its tree; the Nibbler has one)
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
		unlock = { kind = "start" },
	},
	{
		id = "Cuda",
		name = "'Cuda",
		role = "Speed hunter",
		blurb = "The fastest fish in a straight line. Hits hard, turns wide.",
		plan = "Cuda",
		home = "KelpShallows",
		-- Steel back, bright silver belly, yellow fins: plain grey vanished into the
		-- water at speed (re-test 2026-10-06)
		back = Color3.fromRGB(64, 92, 126),
		belly = Color3.fromRGB(236, 242, 246),
		fin = Color3.fromRGB(232, 188, 64),
		stats = { speed = 1.25, turn = 0.8, health = 0.85, bite = 1.1 },
		collider = 0.85,
		abilities = { "Torpedo", "RazorBite", "SilverFlash" },
		unlock = { kind = "tutorial" },
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
		unlock = { kind = "dna", biome = "CoralReef", dna = 100, coral = 2500 },
	},
	{
		id = "MorayEel",
		name = "Moray Eel",
		role = "Ambusher",
		blurb = "Quick, sneaky, and thin enough to slip through gaps nothing its size can.",
		plan = "Eel",
		home = "ShipwreckGraveyard",
		back = Color3.fromRGB(96, 150, 60),
		belly = Color3.fromRGB(192, 212, 120),
		fin = Color3.fromRGB(78, 128, 48),
		stats = { speed = 1.1, turn = 1.25, health = 0.95, bite = 1.15 },
		collider = 0.55,
		abilities = { "Strike", "Burrow", "Shock" },
		unlock = { kind = "dna", biome = "ShipwreckGraveyard", dna = 120, coral = 6000 },
	},
	{
		id = "ReefShark",
		name = "Reef Shark",
		role = "Brawler",
		blurb = "Built to bite. Wins fights it has no business winning.",
		plan = "Shark",
		home = "OpenBlue",
		back = Color3.fromRGB(96, 108, 122),
		belly = Color3.fromRGB(228, 232, 234),
		fin = Color3.fromRGB(84, 96, 110),
		stats = { speed = 1.1, turn = 0.9, health = 1.15, bite = 1.35 },
		collider = 1,
		abilities = { "Frenzy", "BloodSense", "Ram" },
		unlock = { kind = "dna", biome = "OpenBlue", dna = 150, coral = 15000 },
	},
	{
		id = "Anglerfish",
		name = "Anglerfish",
		role = "Lure hunter",
		blurb = "Lives in the dark, and lets dinner come to it.",
		plan = "Angler",
		home = "AbyssalTrench",
		back = Color3.fromRGB(42, 52, 84),
		belly = Color3.fromRGB(74, 84, 116),
		fin = Color3.fromRGB(32, 42, 70),
		stats = { speed = 0.85, turn = 0.9, health = 1.25, bite = 1.25 },
		collider = 1.1,
		abilities = { "Lure", "LanternFlash", "DeepSight" },
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
