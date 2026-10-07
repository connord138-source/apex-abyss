--!strict
-- Treasure maps (owner, 2026-10-07: "treasure maps players randomly earn... a
-- location where they dig up a treasure for a random reward, a large kelp haul or a
-- super rare skin at a low drop rate... only the player holding the map can uncover
-- it"). Like clue scrolls: a map drops from big prey, shells or a big bank, sits in
-- the satchel, and points to a dig site on the seabed. Following it gives a hot/cold
-- sonar, an arrow when close and an X only the holder sees. Digging (a hold) opens
-- the treasure through the roll reveal. Three tiers: how far out the site is and how
-- good the loot gets.
export type RewardKind = "coral" | "shells" | "haul" | "dna" | "charm" | "wraps" | "shade" | "shaderoll"

export type Reward = {
	id: string,
	name: string,
	kind: RewardKind,
	tier: string, -- Config/Tiers, for the reveal's colors
	weight: number, -- relative odds within its map tier
	amount: number?, -- coral, shells, DNA
	levels: number?, -- haul: mass worth this many levels at the digger's level
	charm: string?, -- charm: Config/Shop charm id
	shade: string?, -- shade: Config/Shades id (treasure-only shades)
	minShadeTier: string?, -- shaderoll: the rarest tier guaranteed or better
	blurb: string,
}

export type MapTier = {
	id: string,
	name: string,
	color: Color3,
	minDistance: number, -- dig site's distance from the hub's center (studs)
	maxDistance: number,
	digSeconds: number, -- how long the dig hold takes
	rewards: { Reward },
	blurb: string,
}

local function coral(amount: number, weight: number): Reward
	return {
		id = `Coral{amount}`,
		name = "Coral Hoard",
		kind = "coral",
		tier = "Coral",
		weight = weight,
		amount = amount,
		blurb = `{amount} coral`,
	}
end

local function shells(amount: number, weight: number): Reward
	return {
		id = `Shells{amount}`,
		name = "Shell Cache",
		kind = "shells",
		tier = "Common",
		weight = weight,
		amount = amount,
		blurb = `{amount} shells`,
	}
end

local function haul(levels: number, weight: number): Reward
	return {
		id = `Haul{levels}`,
		name = "Kelp Haul",
		kind = "haul",
		tier = "Rare",
		weight = weight,
		levels = levels,
		blurb = `a Haul worth about {levels} levels, straight into your dive`,
	}
end

local function dna(amount: number, weight: number): Reward
	return {
		id = `Dna{amount}`,
		name = "DNA Vial",
		kind = "dna",
		tier = "Rare",
		weight = weight,
		amount = amount,
		blurb = `{amount} DNA of the biome you dug in`,
	}
end

local lucky: Reward = {
	id = "LuckyCharm",
	name = "Lucky Charm",
	kind = "charm",
	tier = "Epic",
	weight = 0, -- set per tier
	charm = "Lucky",
	blurb = "a Lucky Charm: your next roll's rare odds ×2",
}

local function charm(weight: number): Reward
	local copy = table.clone(lucky)
	copy.weight = weight
	return copy
end

local function wraps(amount: number, weight: number): Reward
	return {
		id = `Wraps{amount}`,
		name = "Kelp Wraps",
		kind = "wraps",
		tier = "Common",
		weight = weight,
		amount = amount,
		blurb = `{amount} Kelp Wraps (heals)`,
	}
end

local function shadeRoll(minTier: string, weight: number): Reward
	return {
		id = `ShadeRoll{minTier}`,
		name = "Shade Roll",
		kind = "shaderoll",
		tier = minTier,
		weight = weight,
		minShadeTier = minTier,
		blurb = `a shade roll, {minTier} or better guaranteed`,
	}
end

local function treasureShade(id: string, name: string, tier: string, weight: number): Reward
	return {
		id = id,
		name = `{name} Shade`,
		kind = "shade",
		tier = tier,
		weight = weight,
		shade = id,
		blurb = `the {name} shade, found only in treasure`,
	}
end

local tiers: { MapTier } = {
	{
		id = "Tattered",
		name = "Tattered",
		color = Color3.fromRGB(196, 176, 140),
		minDistance = 170,
		maxDistance = 320,
		digSeconds = 2.5,
		rewards = {
			coral(120, 48),
			shells(15, 20),
			wraps(3, 10),
			haul(1.5, 12),
			dna(10, 7),
			charm(3),
		},
		blurb = "A scrap of map. The treasure is close to the hub, under the kelp.",
	},
	{
		id = "Weathered",
		name = "Weathered",
		color = Color3.fromRGB(120, 196, 220),
		minDistance = 300,
		maxDistance = 500,
		digSeconds = 3,
		rewards = {
			coral(320, 36),
			shells(35, 18),
			wraps(3, 8),
			haul(2.5, 15),
			dna(25, 10),
			charm(7),
			shadeRoll("Rare", 6),
		},
		blurb = "Salt-stained but readable. The treasure lies out among the boulders.",
	},
	{
		id = "Captain",
		name = "Captain's",
		color = Color3.fromRGB(255, 204, 92),
		minDistance = 460,
		maxDistance = 630,
		digSeconds = 3.5,
		rewards = {
			coral(900, 28),
			shells(60, 14),
			haul(4, 15),
			dna(50, 10),
			charm(12),
			shadeRoll("Epic", 15),
			treasureShade("SunkenGold", "Sunken Gold", "Mythic", 3),
			treasureShade("DrownedPearl", "Drowned Pearl", "Legendary", 3),
		},
		blurb = "A captain's chart, wax-sealed. The treasure waits far out, where the sand meets the open blue.",
	},
}

local byId: { [string]: MapTier } = {}
for _, tier in tiers do
	byId[tier.id] = tier
end

return {
	tiers = tiers,
	byId = byId,
	maxHeld = 3, -- maps carried at once; more don't drop until one is dug up
	-- Where maps come from, with the tier odds for each source (weights)
	drops = {
		-- Eating prey: the chance scales with the prey's mass (per kg, capped)
		preyPerKg = 0.006,
		preyMax = 0.045,
		preyTiers = { Tattered = 70, Weathered = 25, Captain = 5 },
		bigPreyMass = 2, -- prey this heavy or more use the big-prey tier odds
		bigPreyTiers = { Tattered = 40, Weathered = 45, Captain = 15 },
		shell = 0.012, -- per shell picked up
		shellTiers = { Tattered = 80, Weathered = 20, Captain = 0 },
		goldenShell = 0.12,
		goldenShellTiers = { Tattered = 0, Weathered = 60, Captain = 40 },
		bankMinMass = 4, -- a Haul this big banked...
		bank = 0.04, -- ...has this chance of a map in it
		bankTiers = { Tattered = 45, Weathered = 40, Captain = 15 },
	},
	-- The hunt: the sonar word changes with distance, the arrow shows inside
	-- `arrow`, the X inside `mark`, and digging works inside `dig` of the X
	sonar = { arrow = 150, mark = 45, dig = 9 },
	hotCold = {
		{ over = 400, word = "FREEZING" },
		{ over = 250, word = "COLD" },
		{ over = 150, word = "WARM" },
		{ over = 60, word = "HOT" },
		{ over = 0, word = "BURNING" },
	},
	-- Shade finds at this tier or rarer are announced to the whole server
	announceFrom = "Epic",
}
