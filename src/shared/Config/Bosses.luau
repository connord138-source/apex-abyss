--!strict
-- World bosses (owner, 2026-10-06/07; GDD §8): team-first but soloable in 8–10
-- minutes, nothing one-shots, no minions, separate phases with different attacks,
-- and an undersea-horror presentation. Each boss is a `custom` predator
-- (Config/Predators, PredatorService) that BossService drives: a phase machine with
-- telegraphed attacks, health that scales with the attackers, soft spots that fill
-- a stagger meter, and rewards by damage share. Bosses are world events: one rises
-- about every half hour, announced two minutes ahead, taking turns (`rotation`).
local Predators = require(script.Parent.Predators)

export type Spot = { from: number, to: number } -- along the body, 0 = tail tip, 1 = nose

export type BossDef = {
	id: string,
	name: string,
	title: string, -- the tag line ("APEX PREDATOR")
	predator: Predators.PredatorDef, -- the body the predator system streams and bites
	rigged: boolean, -- the model is a rigged FishModels.<model> (spine swim) rather than a prey mesh
	baseHealth: number,
	healthPerAttacker: number, -- + this × base per attacker beyond the first
	attackerWindow: number, -- seconds since their last bite that count a player as attacking
	phases: { number }, -- health fractions where the next phase starts
	patrol: {
		direction: Vector3, -- the sector it roams (unit, flat)
		spread: number, -- radians either side of it
		band: { number }, -- distance from the hub's center
		depth: { number },
	},
	bite: { fraction: number, reach: number, telegraph: number, cooldown: number, trigger: number },
	charge: {
		fraction: number,
		telegraph: number,
		seconds: number,
		speedMul: number,
		radius: number,
		cooldown: number,
		minRange: number,
		maxRange: number,
	},
	sweep: {
		fraction: number,
		telegraph: number,
		radius: number,
		behindMin: number,
		push: number,
		cooldown: number,
	},
	mark: {
		seconds: number,
		cooldown: number,
		speedMul: number,
		lungeEvery: number,
		lungeTell: number,
		lungeSeconds: number,
		lungeFraction: number,
	},
	stagger: {
		need: number,
		seconds: number,
		cooldown: number,
		softMultiplier: number,
		staggerMultiplier: number,
	},
	softSpots: { Spot },
	lastStand: {
		clock: number, -- seconds before it escapes
		breachEvery: number,
		breach: {
			fraction: number,
			radius: number,
			band: number,
			telegraph: number,
			rocket: number,
			crash: number,
			push: number,
		},
		exhausted: number, -- seconds it lies still after a breach
	},
	frenzySpeed: number, -- × speed in the second phase
	rewards: {
		trophyCurrency: string, -- data.trophies key (Megalodon Teeth, Kraken Beaks)
		currencyName: string,
		each: number, -- trophies for everyone with a share
		topThree: number, -- extra for the top three damage dealers
		killer: number, -- extra for the killing bite
		haulKg: number, -- shared by damage share (at least minHaulShare each)
		minHaulShare: number,
		coral: number, -- the jackpot, by share
		coralMin: number,
		minShare: number, -- least damage share that counts
		dropChance: number, -- a trophy straight from the kill (doubled for the top dealer)
		dropShade: string, -- Config/Shades id of that trophy
		shadeRollMin: string, -- everyone gets a shade roll this tier or better
		title: string,
	},
	dread: { range: number, shakeRange: number },
	event: { interval: number, warning: number, studioInterval: number, escapeDelay: number },
}

local megalodon: BossDef = {
	id = "Megalodon",
	name = "Megalodon",
	title = "APEX PREDATOR",
	predator = {
		id = "Megalodon",
		name = "Megalodon",
		model = "Megalodon",
		tag = "APEX PREDATOR",
		length = 80,
		health = 6000,
		speed = 34,
		turnRate = 0.9,
		aggroRange = 200,
		biteReach = 10,
		biteFraction = 0.55,
		biteCooldown = 4,
		telegraph = 1.2,
		ignoreBelow = 0.035, -- a Fry (2–3 studs) is too small to bother with
		band = { 330, 620 },
		depth = { 25, 170 },
		count = 0, -- never spawned by the predator roster; BossService summons it
		respawn = 0,
		loot = { haulKg = 0, dna = 0, coral = 0 }, -- BossService pays the real rewards
		back = Color3.fromRGB(58, 72, 92),
		belly = Color3.fromRGB(214, 222, 230),
	},
	rigged = true,
	baseHealth = 6000,
	healthPerAttacker = 0.6,
	attackerWindow = 20,
	phases = { 0.6, 0.25 },
	patrol = {
		direction = Vector3.new(0, 0, -1), -- the Open Blue is north
		spread = math.rad(80),
		band = { 330, 620 },
		depth = { 25, 170 },
	},
	bite = { fraction = 0.55, reach = 10, telegraph = 1.2, cooldown = 4, trigger = 22 },
	charge = {
		fraction = 0.35,
		telegraph = 1.2,
		seconds = 2.2,
		speedMul = 2.2,
		radius = 13,
		cooldown = 9,
		minRange = 35,
		maxRange = 170,
	},
	sweep = { fraction = 0.2, telegraph = 1, radius = 40, behindMin = 3, push = 60, cooldown = 12 },
	mark = {
		seconds = 8,
		cooldown = 24,
		speedMul = 1.45,
		lungeEvery = 2.2,
		lungeTell = 0.5,
		lungeSeconds = 0.7,
		lungeFraction = 0.25,
	},
	stagger = { need = 700, seconds = 4, cooldown = 18, softMultiplier = 2, staggerMultiplier = 3 },
	softSpots = { { from = 0.6, to = 0.8 }, { from = 0, to = 0.22 } }, -- gills, tail
	lastStand = {
		clock = 60,
		breachEvery = 13,
		breach = {
			fraction = 0.3,
			radius = 48,
			band = 16,
			telegraph = 2.2,
			rocket = 1.3,
			crash = 0.9,
			push = 70,
		},
		exhausted = 5,
	},
	frenzySpeed = 1.3,
	rewards = {
		trophyCurrency = "MegalodonTeeth",
		currencyName = "Megalodon Teeth",
		each = 1,
		topThree = 1,
		killer = 1,
		haulKg = 120,
		minHaulShare = 0.1,
		coral = 5000,
		coralMin = 500,
		minShare = 0.01,
		dropChance = 1 / 15,
		dropShade = "Ghost",
		shadeRollMin = "Rare",
		title = "Megalodon Slayer",
	},
	dread = { range = 300, shakeRange = 70 },
	event = { interval = 1800, warning = 120, studioInterval = 240, escapeDelay = 900 },
}

local list: { BossDef } = { megalodon }

local byId: { [string]: BossDef } = {}
for _, def in list do
	byId[def.id] = def
end

return {
	list = list,
	byId = byId,
	rotation = { "Megalodon" }, -- the order the events take turns in (the Giant Squid joins when built)
	-- Clients: the boss HUD bar shows within this distance of a boss
	hudRange = 700,
}
