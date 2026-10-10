--!strict
-- Rare catches, the Catch Log, the catch tracks and the Catch of the Week (owner,
-- 2026-10-10: "random rarities of fish that can be eaten for more towards the haul
-- or like 10 total unlocks a skin", and the "pull back element").
--
-- Any prey fish can swim rare: Golden, Glowing, Crystal or Prism. A fish's rarity is
-- rolled whenever it (re)spawns and again now and then while nobody's near, at the
-- odds below times the tide's (Config/Tides). Rare fish look the part, pay more Haul,
-- coral and DNA, and count toward:
--   * the Catch Log: every prey species × rarity, with a reward for each first catch
--     and for each finished row;
--   * the catch track of the fish you're swimming as: `track` catches of a rarity
--     unlock that rarity's skin for that fish (owner: "per fish, per rarity"). Those
--     skins are Uncommon to Epic: the elite ones only come from rolls, bosses and
--     treasure (owner, 2026-10-10);
--   * the Catch of the Week: one prey and rarity, easier to find all week, that pays
--     big and unlocks the week's limited skin for the fish that catches it;
--   * the weekly leaderboard (`points`).
export type Rarity = {
	id: string,
	name: string,
	tier: string, -- Config/Tiers id (its color and how loud it is)
	chance: number, -- per spawn, before the tide's multiplier
	tide: string?, -- only spawns while this tide is up (Config/Tides id)
	haul: number, -- Haul × this
	coralPerKg: number, -- coral = max(coralMin, prey kg × coralPerKg)
	coralMin: number,
	dna: number, -- DNA × this
	points: number, -- leaderboard points (Config/Leaderboards RareCatches)
	skin: string, -- the catch-track skin (Config/Shades id)
	track: number, -- catches of this rarity (as one fish) that unlock `skin` for it
	color: Color3, -- its look on the fish (SchoolController) and its text
	announce: { spawn: boolean, catch: boolean },
}

local rarities: { Rarity } = {
	{
		id = "Golden",
		name = "Golden",
		tier = "Rare",
		chance = 1 / 35,
		haul = 3,
		coralPerKg = 6,
		coralMin = 10,
		dna = 2,
		points = 1,
		skin = "CatchGolden",
		track = 10,
		color = Color3.fromRGB(255, 196, 60),
		announce = { spawn = false, catch = false },
	},
	{
		id = "Glowing",
		name = "Glowing",
		tier = "Epic",
		chance = 1 / 180,
		haul = 6,
		coralPerKg = 15,
		coralMin = 40,
		dna = 3,
		points = 5,
		skin = "CatchGlowing",
		track = 10,
		color = Color3.fromRGB(70, 240, 220),
		announce = { spawn = false, catch = false },
	},
	{
		id = "Crystal",
		name = "Crystal",
		tier = "Legendary",
		chance = 1 / 900,
		haul = 12,
		coralPerKg = 40,
		coralMin = 150,
		dna = 5,
		points = 25,
		skin = "CatchCrystal",
		track = 5,
		color = Color3.fromRGB(170, 225, 255),
		announce = { spawn = false, catch = true },
	},
	{
		id = "Prism",
		name = "Prism",
		tier = "Mythic",
		chance = 1 / 150,
		tide = "Prism",
		haul = 25,
		coralPerKg = 100,
		coralMin = 500,
		dna = 8,
		points = 100,
		skin = "CatchPrism",
		track = 3,
		color = Color3.fromRGB(255, 120, 230),
		announce = { spawn = true, catch = true },
	},
}

local byId: { [string]: Rarity } = {}
local codes: { [string]: number } = {} -- rarity id → its number on the wire (0 = none)
for i, rarity in rarities do
	byId[rarity.id] = rarity
	codes[rarity.id] = i
end

-- The Catch of the Week: weeks run Monday to Monday (UTC). Week 1 starts `start`;
-- the list cycles when it runs out, so add a week (and its skin) to keep it fresh.
export type Weekly = {
	prey: string, -- Config/Prey id
	rarity: string,
	skin: string, -- the week's limited skin (Config/Shades id, `week` set)
	coral: number,
	shells: number,
}

local weekly: { Weekly } = {
	{ prey = "Grouper", rarity = "Crystal", skin = "WeekWave", coral = 5000, shells = 100 },
	{ prey = "Snapper", rarity = "Glowing", skin = "WeekReef", coral = 3000, shells = 75 },
	{ prey = "Barracuda", rarity = "Golden", skin = "WeekWreck", coral = 3000, shells = 75 },
	{ prey = "Wrasse", rarity = "Crystal", skin = "WeekSeaGlass", coral = 4000, shells = 100 },
}

return {
	rarities = rarities,
	byId = byId,
	codes = codes,
	-- Re-rolling fish nobody is near, so the sea keeps changing (and the tide's
	-- odds reach the fish no one eats): every `seconds`, up to `perTick` fish more
	-- than `clearance` studs from every player
	rotate = { seconds = 5, perTick = 12, clearance = 260 },
	-- The Catch Log: coral for the first catch of each prey species at each rarity
	-- ("Normal" too), and for catching every rarity of one species
	firstCatch = { Normal = 25, Golden = 120, Glowing = 400, Crystal = 1500, Prism = 5000 },
	rowComplete = { coral = 3000, shells = 60 },
	logTitle = "Master Angler", -- every species at every rarity
	weekly = {
		start = 1791158400, -- Monday 2026-10-05 00:00 UTC: week 1 (live from the first build)
		list = weekly,
		chance = 3, -- the featured fish swims rare at ×this all week
		points = 50, -- extra leaderboard points for catching it
	},
}
