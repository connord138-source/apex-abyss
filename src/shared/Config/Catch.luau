--!strict
-- Rare catches, the Catch Logbook, the skin goals and the Catch of the Week (owner,
-- 2026-10-10: "random rarities of fish that can be eaten for more towards the haul
-- or like 10 total unlocks a skin", and the "pull back element").
--
-- Any prey fish can swim rare: Silver, Golden, Glowing, Crystal or Prism. Rare fish
-- look the part, pay more Haul, coral and DNA, and count toward:
--   * the Catch Logbook: every prey species × rarity, the biggest of each and how
--     many, with a reward for each first catch and for each finished row;
--   * the skin goals (owner, 2026-10-18: "They will need atleast 10 gold of 5
--     different species to unlock the skin. Once the skin is unlocked, it is unlocked
--     for all of their fish"): `unlock.each` catches of a rarity from each of
--     `unlock.species` prey species unlock its skin for every fish the player has or
--     will have (Shared/Catch `goal`). Those skins are Common to Epic: the elite ones
--     only come from rolls, bosses and treasure (owner, 2026-10-10);
--   * the Catch of the Week: one prey and rarity, easier to find all week, that pays
--     big and unlocks the week's limited skin for the fish that catches it;
--   * the weekly leaderboard (`points`).
--
-- How often they swim (owner, 2026-10-18: "I caught three crystal fish in about 5
-- minutes. But rerun the spawn rates"): every fish in the sea used to roll its
-- rarity, so the rare fish alive at once grew with the ~4,100 fish (4–5 Crystals at
-- any moment, their glints seen from 240 studs). Now each rarity has a spawn `rate`
-- for each player out in the biomes: a rare fish is set swimming in a school
-- 340–1,000 studs from that player (one they can swallow, out of everyone's sight),
-- lives about `life` seconds, then quietly turns plain once no one's near it
-- (Shared/RareSpawn). So how often a player meets one doesn't depend on how many fish
-- or players there are. `every` is what tools/tests/run_catch_sim.sh measures for an
-- active hunter, averaged over the tides (the LOG and the INDEX show it); rerun it
-- after changing a rate, a life or `spawn`.
export type Rarity = {
	id: string,
	name: string,
	tier: string, -- Config/Tiers id (its color and how loud it is)
	rate: number, -- rare fish set swimming a minute round each player out in the biomes, before the tide
	life: number, -- seconds one swims rare (±25%), then it turns plain once no one's near
	every: number, -- minutes between catches for an active hunter (the sim's figure; the Prism: in its tide)
	tide: string?, -- only swims while this tide is up (Config/Tides id)
	haul: number, -- Haul × this
	coralPerKg: number, -- coral = max(coralMin, prey kg × coralPerKg)
	coralMin: number,
	dna: number, -- DNA × this
	points: number, -- leaderboard points (Config/Leaderboards RareCatches)
	skin: string, -- the skin its goal unlocks for every fish (Config/Shades id)
	-- The goal: `each` catches of this rarity from each of `species` prey species
	unlock: { each: number, species: number },
	color: Color3, -- its look on the fish (SchoolController) and its text
	announce: { spawn: boolean, catch: boolean },
}

local rarities: { Rarity } = {
	{
		id = "Silver",
		name = "Silver",
		tier = "Uncommon",
		-- (×2 and lives ×1.5 since 2026-10-28, owner: "still need more silver and gold
		-- fish. went across the whole server and saw 2 silver sardines": ~2.5 swam round
		-- a player at once, ~7.5 now)
		rate = 2.5,
		life = 180,
		every = 0.4,
		haul = 2,
		coralPerKg = 3,
		coralMin = 5,
		dna = 1,
		points = 0.2,
		skin = "CatchSilver",
		unlock = { each = 10, species = 5 },
		color = Color3.fromRGB(214, 230, 245),
		announce = { spawn = false, catch = false },
	},
	{
		id = "Golden",
		name = "Golden",
		tier = "Rare",
		-- (×2.7 since 2026-10-20, owner: "i havent seen a single gold or crystal fish spawn
		-- today"; ×2 and lives ×1.33 since 2026-10-28: ~1.1 swam round a player at once,
		-- ~3 now)
		rate = 0.5,
		life = 360,
		every = 0.9,
		haul = 3,
		coralPerKg = 6,
		coralMin = 10,
		dna = 2,
		points = 1,
		skin = "CatchGolden",
		-- (10 until 2026-10-28; with twice the Golden fish 15 keeps the goal near two
		-- hours of hunting, owner: "atleast 10 gold of 5 different species")
		unlock = { each = 15, species = 5 },
		color = Color3.fromRGB(255, 196, 60),
		announce = { spawn = false, catch = false },
	},
	{
		id = "Glowing",
		name = "Glowing",
		tier = "Epic",
		rate = 0.06,
		life = 330,
		every = 10,
		haul = 6,
		coralPerKg = 15,
		coralMin = 40,
		dna = 3,
		points = 5,
		skin = "CatchGlowing",
		unlock = { each = 5, species = 5 },
		color = Color3.fromRGB(70, 240, 220),
		announce = { spawn = false, catch = false },
	},
	{
		id = "Crystal",
		name = "Crystal",
		tier = "Legendary",
		rate = 0.025,
		life = 480,
		every = 30,
		haul = 12,
		coralPerKg = 40,
		coralMin = 150,
		dna = 5,
		points = 25,
		skin = "CatchCrystal",
		unlock = { each = 2, species = 5 },
		color = Color3.fromRGB(170, 225, 255),
		announce = { spawn = false, catch = true },
	},
	{
		id = "Prism",
		name = "Prism",
		tier = "Mythic",
		-- (0.08, was 0.10: the PC's bot caught 4 in one tide, PC 2026-10-19, RT2)
		rate = 0.08,
		life = 300,
		every = 10,
		tide = "Prism",
		haul = 25,
		coralPerKg = 100,
		coralMin = 500,
		dna = 8,
		points = 100,
		skin = "CatchPrism",
		unlock = { each = 1, species = 5 },
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
	-- Where and how rare fish are set swimming (Shared/RareSpawn), checked every
	-- `tick` seconds: in a school `near`–`far` studs from the player they're for and
	-- never within `clearance` of anyone (a glint shows from 240 studs off the camera,
	-- which sits up to ~70 behind a big fish), so nothing turns rare in sight; one past
	-- its life turns plain only when no one's within `clearance` either. With no such
	-- school (a full server crowding one biome), an eaten fish there comes back rare.
	-- In the first `rush.seconds` of a tide the rarities it boosts spawn ×`rush.boost`,
	-- so its fish show up early in its 20 minutes.
	spawn = {
		tick = 1,
		near = 340,
		far = 750,
		clearance = 320,
		rush = { seconds = 120, boost = 3 },
		cap = 3, -- at most this × the expected number of one rarity swimming at once
	},
	-- The Catch Log: coral for the first catch of each prey species at each rarity
	-- ("Normal" too), and for catching every rarity of one species
	firstCatch = { Normal = 25, Silver = 60, Golden = 120, Glowing = 400, Crystal = 1500, Prism = 5000 },
	rowComplete = { coral = 3000, shells = 60 },
	logTitle = "Master Angler", -- every species at every rarity
	weekly = {
		start = 1791158400, -- Monday 2026-10-05 00:00 UTC: week 1 (live from the first build)
		list = weekly,
		-- Its own stream of rare fish all week, on top of the usual ones: this many a
		-- minute round each player near where its species swims (Shared/RareSpawn), so
		-- a hunter there finds one in about `every` minutes (the sim's figure)
		rate = 0.012,
		every = 45,
		points = 50, -- extra leaderboard points for catching it
	},
}
