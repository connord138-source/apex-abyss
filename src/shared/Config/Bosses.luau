--!strict
-- World bosses (owner, 2026-10-06/07; GDD §8): team-first but soloable in 8–10
-- minutes, nothing one-shots, no minions, separate phases with different attacks,
-- and an undersea-horror presentation. Each boss is a `custom` predator
-- (Config/Predators, PredatorService) that BossService drives: a phase machine with
-- telegraphed attacks, health that scales with the attackers, soft spots that fill
-- a stagger meter, and rewards by damage share. Bosses are world events: one rises
-- about every half hour, announced two minutes ahead, taking turns (`rotation`).
-- Two kits: the shark (charge, bite, tail sweep, mark, breach) and the squid
-- (tentacle grab, ink, jet, whirlpool, beak slam, siphon).
local Predators = require(script.Parent.Predators)

export type Spot = { from: number, to: number } -- along the body, 0 = tail tip, 1 = nose

export type SharkKit = {
	-- (`sated`: seconds more on the cooldown after a bite that lands; it circles its
	-- fish meanwhile, so a fish that sits still is bitten no faster than before, while
	-- a miss comes round at once)
	bite: {
		fraction: number,
		reach: number,
		telegraph: number,
		cooldown: number,
		trigger: number,
		sated: number?,
	},
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
	-- Last stand: breaches on the way out to the open ocean, then lies exhausted
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
	exhausted: number,
}

export type SquidKit = {
	-- A tentacle lights, then wraps a fish and drags it to the beak: `fraction` of max
	-- health a second for up to `seconds`; mash (struggleNeed presses) or teammates'
	-- bites on the squid (biteFree) break it
	grab: {
		fraction: number,
		seconds: number,
		telegraph: number,
		range: number,
		struggleNeed: number,
		biteFree: number,
		cooldown: number,
		freeBeaks: number, -- Kraken Beaks for everyone whose bites broke a grab
		maxShare: number, -- a grab lets go once it has taken this much of a fish's health
		recover: number, -- seconds a released fish can't be grabbed again
	},
	ink: { seconds: number, radius: number, cooldown: number },
	jet: { distance: number, telegraph: number, cooldown: number },
	whirlpool: { seconds: number, radius: number, pull: number, telegraph: number, cooldown: number },
	slam: { fraction: number, telegraph: number, reach: number, cooldown: number },
	siphon: {
		fraction: number,
		telegraph: number,
		range: number,
		cosine: number,
		push: number,
		cooldown: number,
	},
	lurkDepth: { number }, -- phases 1–2: it keeps to this depth band
	mantleDepth: { number }, -- phase 3: up into open water
}

export type BossDef = {
	id: string,
	name: string,
	title: string, -- the tag line ("APEX PREDATOR")
	predator: Predators.PredatorDef, -- the body the predator system streams and bites
	rigged: boolean, -- the model is a rigged FishModels.<model> (spine swim) rather than a prey mesh
	kit: "shark" | "squid",
	shark: SharkKit?,
	squid: SquidKit?,
	baseHealth: number,
	healthPerAttacker: number, -- + this × base per attacker beyond the first
	attackerWindow: number, -- seconds since their last bite that count a player as attacking
	phases: { number }, -- health fractions where the next phase starts
	phaseNames: { string },
	patrol: {
		direction: Vector3, -- the sector it roams (unit, flat)
		spread: number, -- radians either side of it
		band: { number }, -- distance from the hub's center
		depth: { number },
		-- Keeps to the Abyssal Trench's canyon (Seafloor.trenchPoint) instead of the
		-- sector
		trench: boolean?,
		-- Gives up a chase that takes it `leash` studs out of its own water (the
		-- canyon, or the sector and band) and never takes a fish out past it
		leash: number?,
	},
	stagger: {
		-- Bites on its soft spots that stagger it (owner, 2026-10-20: "megalodon takes
		-- far too many bites to stagger": the meter filled by damage, 700, and every
		-- fish in its water bites a 175-stud boss at the minimum, ~3.8 on the gills, so
		-- it took ~180 gill bites solo); a school fills it together
		need: number,
		seconds: number,
		cooldown: number,
		softMultiplier: number,
		staggerMultiplier: number,
	},
	softSpots: { Spot },
	frenzySpeed: number, -- × speed in the second phase
	escapeClock: number, -- seconds the third phase lasts before it escapes
	rewards: {
		trophyCurrency: string, -- data.trophies key (MegalodonTeeth, KrakenBeaks)
		currencyName: string,
		each: number, -- trophies for everyone with a share
		topThree: number, -- extra for the top three damage dealers
		killer: number, -- extra for the killing bite
		-- The Haul, in full Hauls of each fish's own (Shared/Size haulCap, so it's the
		-- same share of a dive at every level): `hauls` for everyone with a share, plus
		-- `haulsShare` × their damage share; it goes on top of a full Haul. (It was
		-- 120 kg by share × the Haul rate until the 2026-10-19 pace.)
		hauls: number,
		haulsShare: number,
		coral: number, -- the jackpot, by share
		coralMin: number,
		minShare: number, -- least damage share that counts
		dropChance: number, -- a trophy straight from the kill (doubled for the top dealer)
		dropShade: string, -- Config/Shades id of that trophy
		shadeRollMin: string, -- everyone gets a shade roll this tier or better
		title: string,
	},
	dread: { range: number, shakeRange: number, warning: string },
	-- How it shows itself (owner, 2026-10-09: the Megalodon is "an eerie figure" that
	-- "slowly fades into view of players. Once he is upon them he needs to be seeable
	-- to be fightable"; "how the hell will anyone fight anything in pitch black or low
	-- visibility let alone a boss"). Distances are studs from its body: beyond `far` it
	-- can't be seen and by `near` it's solid (no fade when nil); within `light` the
	-- water round it clears (and the dark lifts), so the fight reads.
	sight: { far: number?, near: number?, light: number },
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
		-- Larger (owner, 2026-10-19: "he could definitely be made larger"; was 130):
		-- every reach and radius below grew with it (×1.35)
		length = 175,
		health = 6000,
		-- Player bites (owner, 2026-10-20: "takes far too many bites"; boss rules: solo
		-- in 8–10 min): every fish in its water bit at the plain minimum, 1.9 a bite,
		-- ~3,000 bites solo. Now a LV 45 fish bites for ~12 (LV 35 10, LV 55 14, LV 100
		-- 29), ~330 bites solo with the gills and staggers, about 9 min.
		bitten = { scale = 2.2, power = 0.5 },
		speed = 34,
		turnRate = 0.9,
		aggroRange = 240,
		biteReach = 21.5,
		biteFraction = 0.55,
		biteCooldown = 4,
		telegraph = 1.2,
		ignoreBelow = 0.026, -- a fish under ~4.5 studs is too small to bother with (0.035 at 130 long)
		band = { 1000, 1440 },
		depth = { 170, 470 },
		count = 0, -- never spawned by the predator roster; BossService summons it
		respawn = 0,
		loot = { hauls = 0, dna = 0, coral = 0 }, -- BossService pays the real rewards
		back = Color3.fromRGB(58, 72, 92),
		belly = Color3.fromRGB(214, 222, 230),
		-- Heavy and menacing, never a robot (owner, 2026-10-19: "It needs to feel like a
		-- real predator"): it cruises on slow strokes and long glides, surges into a
		-- charge, carries through a miss and banks round hard (~2 s for 180°, was a
		-- ~5 s crawl), circles a fish while its bite cools, and comes up at a far one
		-- from below
		swim = {
			turnAtSpeed = 0.7,
			comeTurn = 2.5,
			accel = 1.3,
			brake = 1.0,
			carry = 0.6,
			glide = 0.2,
			beat = 3.6,
			circle = { 270, 170 },
			under = 70,
		},
	},
	rigged = true,
	kit = "shark",
	shark = {
		bite = { fraction = 0.55, reach = 21.5, telegraph = 1.2, cooldown = 4, trigger = 43, sated = 2.2 },
		charge = {
			fraction = 0.35,
			telegraph = 1.2,
			seconds = 2.2,
			speedMul = 2.2,
			radius = 27,
			cooldown = 9,
			minRange = 65,
			maxRange = 280,
		},
		sweep = { fraction = 0.2, telegraph = 1, radius = 78, behindMin = 3, push = 60, cooldown = 12 },
		mark = {
			seconds = 8,
			cooldown = 24,
			speedMul = 1.45,
			lungeEvery = 2.2,
			lungeTell = 0.5,
			lungeSeconds = 0.7,
			lungeFraction = 0.25,
		},
		breachEvery = 13,
		breach = {
			fraction = 0.3,
			radius = 84,
			band = 27,
			telegraph = 2.2,
			rocket = 1.3,
			crash = 0.9,
			push = 70,
		},
		exhausted = 5,
	},
	squid = nil,
	baseHealth = 6000,
	healthPerAttacker = 0.6,
	attackerWindow = 20,
	phases = { 0.6, 0.25 },
	phaseNames = { "HUNTING", "FRENZY", "LAST STAND" },
	patrol = {
		direction = Vector3.new(0, 0, -1), -- the Open Blue is north, off the drop-off
		spread = math.rad(42),
		band = { 1000, 1440 },
		-- Open water (owner, 2026-10-09: "not for deepest darkest ocean just deep blue
		-- where there's no ground or anything just open ocean"): 170–470 studs over
		-- the deep floor, where the floor is lost in the blue below
		depth = { 170, 470 },
		-- Never over the shelf: a chase ends 160 studs out of the sector and band
		-- (r 840, the drop-off; PC 2026-10-25: it followed a fish to the Kelp
		-- Shallows and circled at the hub's keep-out)
		leash = 160,
	},
	stagger = { need = 12, seconds = 4, cooldown = 18, softMultiplier = 2, staggerMultiplier = 3 },
	softSpots = { { from = 0.6, to = 0.8 }, { from = 0, to = 0.22 } }, -- gills, tail
	frenzySpeed = 1.3,
	escapeClock = 60,
	rewards = {
		trophyCurrency = "MegalodonTeeth",
		currencyName = "Megalodon Teeth",
		each = 1,
		topThree = 1,
		killer = 1,
		hauls = 1.5, -- (a solo kill 2.5 full Hauls, one of six even fighters ~1.7)
		haulsShare = 1,
		coral = 5000,
		coralMin = 500,
		minShare = 0.01,
		dropChance = 1 / 15,
		dropShade = "Ghost",
		shadeRollMin = "Rare",
		title = "Megalodon Slayer",
	},
	-- Felt before it's seen: the dread (and SOMETHING CIRCLES IN THE BLUE, while it's
	-- unseen) starts well outside the fade-in (460 until `sight` grew, 2026-10-18)
	dread = { range = 760, shakeRange = 95, warning = "SOMETHING CIRCLES IN THE BLUE" },
	-- Seen from further out in the clearer Open Blue (owner, 2026-10-18: "Megalodon
	-- should be able to be seen from further out"; was 280 / 170 / 190): it starts to
	-- show at 500 and is solid by 290, the haze carrying the rest of the emergence,
	-- and the body is never part see-through while it's in plain view (playtest
	-- 2026-10-10). The bigger body (175, 2026-10-19) shows from a little further.
	sight = { far = 560, near = 330, light = 300 },
	event = { interval = 1800, warning = 120, studioInterval = 240, escapeDelay = 900 },
}

local giantSquid: BossDef = {
	id = "GiantSquid",
	name = "Giant Squid",
	title = "TERROR OF THE DEEP",
	predator = {
		id = "GiantSquid",
		name = "Giant Squid",
		model = "GiantSquid",
		tag = "TERROR OF THE DEEP",
		length = 95,
		health = 5500,
		-- (a LV 85 fish, the Trench's, bites for ~13, a LV 100 one ~17: ~8 min solo)
		bitten = { scale = 0.9, power = 0.5 },
		speed = 26,
		turnRate = 1.1,
		aggroRange = 280, -- it rises to fish well above its lurk band (190 missed one 180 up)
		biteReach = 9,
		biteFraction = 0.45,
		biteCooldown = 6,
		telegraph = 1.3,
		ignoreBelow = 0.035,
		band = { 980, 1420 },
		depth = { 15, 260 },
		count = 0,
		respawn = 0,
		loot = { hauls = 0, dna = 0, coral = 0 },
		back = Color3.fromRGB(96, 34, 70),
		belly = Color3.fromRGB(190, 140, 160),
		-- Pulses along mantle first, quick to swing round (its arms do the reaching)
		swim = {
			turnAtSpeed = 0.8,
			comeTurn = 2.2,
			accel = 1.6,
			brake = 1.4,
			carry = 0.4,
			glide = 0.3,
			beat = 2.0,
		},
	},
	rigged = true,
	kit = "squid",
	shark = nil,
	squid = {
		grab = {
			fraction = 0.15,
			seconds = 4,
			telegraph = 1,
			range = 78,
			struggleNeed = 6,
			biteFree = 3,
			cooldown = 7,
			freeBeaks = 1,
			-- Nothing one-shots (owner): two grabs back to back took a full fish to 0
			-- (playtest 2026-10-08), so a grab takes at most 45% and a fish just let go
			-- can't be grabbed again for 10 s
			maxShare = 0.45,
			recover = 10,
		},
		ink = { seconds = 6, radius = 70, cooldown = 20 },
		jet = { distance = 120, telegraph = 0.6, cooldown = 22 },
		whirlpool = { seconds = 3, radius = 88, pull = 30, telegraph = 1.2, cooldown = 18 },
		slam = { fraction = 0.45, telegraph = 1.3, reach = 20, cooldown = 6 },
		siphon = { fraction = 0.15, telegraph = 1, range = 62, cosine = 0.55, push = 85, cooldown = 10 },
		lurkDepth = { 10, 55 },
		mantleDepth = { 90, 140 },
	},
	baseHealth = 5500,
	healthPerAttacker = 0.6,
	attackerWindow = 20,
	phases = { 0.65, 0.3 },
	phaseNames = { "LURKER", "ENRAGED", "MANTLE" },
	patrol = {
		direction = Vector3.new(0, 0, 1), -- the Trench is south, off the drop-off
		spread = math.rad(70),
		band = { 980, 1420 },
		depth = { 10, 55 },
		-- The deepest dark is the squid's (owner, 2026-10-09): it rises, roams and
		-- jets inside the canyon (it rose in the Sunken Ruins and roamed far,
		-- playtest 2026-10-10)
		trench = true,
		leash = 160,
	},
	stagger = { need = 10, seconds = 4, cooldown = 18, softMultiplier = 2, staggerMultiplier = 3 },
	softSpots = { { from = 0.52, to = 0.7 }, { from = 0, to = 0.25 } }, -- the eye, the tentacles
	frenzySpeed = 1.25,
	escapeClock = 90,
	rewards = {
		trophyCurrency = "KrakenBeaks",
		currencyName = "Kraken Beaks",
		each = 1,
		topThree = 1,
		killer = 1,
		hauls = 1.5, -- (a solo kill 2.5 full Hauls, one of six even fighters ~1.7)
		haulsShare = 1,
		coral = 5000,
		coralMin = 500,
		minShare = 0.01,
		dropChance = 1 / 15,
		dropShade = "AbyssInk",
		shadeRollMin = "Rare",
		title = "Kraken Slayer",
	},
	dread = { range = 300, shakeRange = 60, warning = "SOMETHING STIRS BELOW" },
	-- The deep dark is the squid's: it doesn't fade, but near it the dark lifts
	sight = { light = 200 },
	event = { interval = 1800, warning = 120, studioInterval = 240, escapeDelay = 900 },
}

local list: { BossDef } = { megalodon, giantSquid }

local byId: { [string]: BossDef } = {}
for _, def in list do
	byId[def.id] = def
end

return {
	list = list,
	byId = byId,
	rotation = { "Megalodon", "GiantSquid" }, -- the order the events take turns in
	-- Clients: the boss HUD bar shows within this distance of a boss (a boss that
	-- fades in shows its bar once it starts to appear)
	hudRange = 1000,
	-- A grabbed fish is dragged toward the beak at this speed (studs/s); its own
	-- swimming is overridden until it breaks free
	grabPull = 22,
}
