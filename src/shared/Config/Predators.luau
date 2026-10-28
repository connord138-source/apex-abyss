--!strict
-- Aggressive AI predators (owner, 2026-10-06: "aggressive AI fish, not controlled by
-- players, worth more than the smaller or calmer fish"). They're simulated on the
-- server (PredatorService): each roams a band of water round the hub, hunts fish big
-- enough to be worth it, telegraphs every bite, and can be bitten back. Killing one
-- pays a Haul, DNA and coral to everyone who helped, by damage share. The world
-- bosses (GDD §8) run on the same system with phases on top.
--
-- Damage to players is a share of the victim's max health: nothing one-shots (owner,
-- 2026-10-07).
--
-- Every biome has its own (owner, 2026-10-21: "we need more predator fish too that
-- felt pretty scattered", then the eight on assets/concepts/PredatorsBoard.jpg):
-- Sea Lions in the kelp, Barracuda and Goliath Groupers in the wreck bay, packs of
-- Giant Trevally and Reef Sharks on the reef, Reef Sharks and Makos in the Open Blue,
-- Sixgills in the Ruins, Wolf Eels in the Vents, Goblin Sharks and Black Dragonfish
-- down the Trench. Each is tuned to a level (`level`), and a fight with one goes by
-- level like a fight between players (`fight`; owner: "Ensure ease of eating them
-- scales with levels as well").
-- How a hunter hunts (owner, 2026-10-17: "shark should be able to catch fish with
-- speed but each different fish should have their own limitations/advantages").
-- Every number is optional except `kind`, `chase`, `turnAtSpeed` and `tellFollow`;
-- PredatorService reads only the ones its kind uses.
--   ambush:  lurks low by rocks and kelp, stalks a fish, bursts at it from mid range
--            leading its swim, snaps at once from close and whips round on a fish
--            beside or behind it; briefly out of breath after a burst. Outlasting the
--            burst (a faster fish, or a Dash) escapes it; a juke only sometimes
--            (owner, 2026-10-20: "a lot more aggressive and more accurate").
--   tracker: a sustained fast chase that runs most fish in its water down, a long
--            leash and a nose for blood; but wide turns (a tight loop or doubling
--            back makes it overshoot and swing round), too big for kelp, and a Dash
--            during its tell still escapes.
--   plain:   the old all-rounder (a predator with no style)
export type Style = {
	kind: string, -- "ambush" | "tracker" | "plain"
	chase: number, -- × speed while it closes in (an ambusher's stalk)
	turnAtSpeed: number, -- × turn rate it keeps at full speed (1.25 when still)
	tellFollow: number, -- × speed: the fastest it keeps up during its tell
	tellBrake: number?, -- × speed per second it can slow by during its tell (default strike.brake)
	tellFacing: number?, -- how squarely (cosine) it must face the fish to start a tell (default strike.facing)
	snap: number?, -- × biteReach its snap reaches past its mouth when the tell ends (default 1.6)
	cone: number?, -- how far off its nose (cosine) its snap still catches a fish (default strike.cone)
	commit: number?, -- share of its tell after which it stops turning and lunges on its line
	slowsToTurn: number?, -- × chase it slows to when the fish is off its nose up close
	roam: number?, -- × speed roaming (default Predators.roamSpeed)
	recover: number?, -- × speed peeling off after a strike (default 0.8)
	-- Ambush
	lurk: { number }?, -- height over the ground it lurks at (min, max)
	trigger: number?, -- studs from its mouth: a fish this close sets off a burst
	burst: number?, -- × speed in a burst (it keeps it through a tell begun in one)
	burstSeconds: number?,
	burstTurn: number?, -- × turn rate in a burst (wide)
	burstFacing: number?, -- how squarely (cosine) it lines up before it bursts (default 0.92)
	burstLead: number?, -- share of the time to close it leads a fish by in a burst (0: where it is)
	whip: number?, -- × turn rate it snaps round at, nearly stopping, on a fish beside or behind it
	winded: number?, -- seconds out of breath after a burst: slow, no tell, no bite
	giveUp: number?, -- failed bursts on one fish before it gives that fish up
	forget: number?, -- seconds it leaves a fish it gave up on alone
	-- Tracker
	leash: number?, -- × aggroRange: how far it keeps a chase going (default loseRange)
	blood: number?, -- × aggroRange on a fish under `bloodBelow` of its health
	bloodBelow: number?,
	kelpShy: boolean?, -- too big for a kelp forest: a fish in one is out of its reach
	-- Coming round after a strike (owner, 2026-10-19: "If he misses the player he just
	-- slowly turns around and goes at them again"): it carries through `carry` s at
	-- speed, then turns back hard (× `comeTurn` its turn rate) at `comePace` × speed
	-- onto a loop round the fish a run-in's length out, on the side it peeled to, and
	-- turns in from there once its bite is ready, so each pass comes from a new angle.
	-- A bite that lands sates it a little: `sated` s more before the next pass (it
	-- swings wide with its mouthful), so a fish that sits still is bitten no faster
	-- than before; a miss comes round at once.
	carry: number?,
	comeTurn: number?,
	comePace: number?,
	sated: number?,
	-- How it opens a hunt on a fish that isn't running (owner: "It needs to feel like a
	-- real predator"): circling in and tightening (`circle`: the chance, for up to
	-- `circleSeconds`), or stalking up from below (`under`: the chance, `underDepth`
	-- studs under the fish at the most), else straight in. A `feint` (the chance, once
	-- a hunt) swerves off a run without a tell and comes round again.
	circle: number?,
	circleSeconds: number?,
	under: number?,
	underDepth: number?,
	feint: number?,
	-- Burst and glide (owner: "his actual movements are very stiff"): its pace swings
	-- ± `glide` over a `beat`-second cycle of a few strong strokes and a coast
	glide: number?,
	beat: number?,
	-- Its own ways (the 2026-10-21 eight)
	pack: { size: number, spread: number }?, -- hunts in packs: one drives, the rest swing out to its flanks
	gulp: { pull: number, reach: number, breakAt: number }?, -- its tell sucks a fish in (`pull` studs/s² within `reach` of its mouth) until the fish swims off faster than `breakAt` × its top speed (a Dash)
	tether: number?, -- studs it strays from its hole (its home, picked at spawn)
	lure: { radius: number, pull: number }?, -- a glowing lure that draws in the fish it stalks
	trench: boolean?, -- lives down in the Trench's canyon (its waypoints follow the canyon)
	spareLearners: boolean?, -- never hunts a fish still in the tutorial
	nips: number?, -- bites that land on one fish (within `forget` s of each other) before it lets that fish go for `forget` s
	warn: string?, -- the words after its name when its tell is on you (default INCOMING)
}

-- How a boss's body moves (Config/Bosses `predator.swim`): it swims along its heading
-- with momentum like any fish (PredatorService.steer), only bigger and heavier
export type Swim = {
	turnAtSpeed: number, -- × turn rate it keeps at full speed (1.4 when slow)
	comeTurn: number, -- × turn rate in a burst-turn: a fish well off its nose, or coming round after a miss
	accel: number, -- × speed per second it speeds up by (× 2.5 when a move asks for a surge)
	brake: number, -- × speed per second it slows by (× 2.5 in a tell)
	carry: number, -- seconds it carries through after a strike before it comes round
	glide: number, -- the burst-and-glide swing in pace (±)
	beat: number, -- seconds a burst-and-glide cycle takes
	circle: { number }?, -- radius it circles a fish at while its bite cools (start, closest)
	under: number?, -- studs under a far fish it comes up from (a lunge from below)
}

-- A group's water: its band round the hub, its sector, its height off the floor and
-- how many of it are alive at once
export type Water = { band: { number }, angles: { number }?, depth: { number }, count: number, level: number? }

export type PredatorDef = {
	id: string,
	name: string,
	model: string, -- ReplicatedStorage.PreyModels.<model> (static mesh), else a part body
	tag: string?, -- the tag's first line (default PREDATOR)
	length: number, -- studs
	-- Its body's radius as a share of its length, for biting it and bumping into it
	-- (default 0.18), and where its jaws are, as a share of its length ahead of its
	-- middle (default 0.45; the Goblin Shark's sit behind its long snout)
	girth: number?,
	mouth: number?,
	health: number,
	speed: number, -- studs/s hunting (roaming is slower)
	turnRate: number, -- radians/s
	aggroRange: number, -- studs: fish inside get hunted
	biteReach: number, -- studs past the mouth
	biteFraction: number, -- of the victim's max health
	biteCooldown: number, -- seconds between bites
	telegraph: number, -- seconds the jaw shows before it bites (the tell)
	-- The level it's tuned for (a Water can set its own): a player's bite on it and its
	-- bite on a player go by the gap, like a fight between players (`fight`). Bosses
	-- have none (their bites scale by `bitten`).
	level: number?,
	ignoreBelow: number, -- fish shorter than this × its length are left alone unless they bite it
	band: { number }, -- distance from the hub's center it roams in (min, max)
	angles: { number }?, -- the sector it keeps to (degrees from +X toward +Z, clockwise; nil = all round)
	depth: { number }, -- height above the local floor it roams in (min, max; Shared/Seafloor)
	count: number, -- alive at once
	-- More waters it hunts, each its own group of the same fish, at its own level (the
	-- Reef Shark cruises the reef at LV 34 and the Open Blue at LV 45)
	also: { Water }?,
	respawn: number, -- seconds after a kill
	-- A kill's loot, split by damage share (PredatorService): `hauls` in full Hauls of
	-- each fish's own (Shared/Size haulCap, the same share of a dive at every level;
	-- it was kg × the Haul rate until the 2026-10-19 pace), stopping at a full Haul
	loot: { hauls: number, dna: number, coral: number },
	back: Color3, -- part-body colors while the model is missing
	belly: Color3,
	-- How a player's bite on it scales (a boss's): `scale` × (the biter's raw length /
	-- its length) ^ `power`, in Predators' biteRatioMin..biteRatioMax, instead of the
	-- plain ^ biteRatioPower, which put every fish at the minimum against a boss
	bitten: { scale: number, power: number }?,
	style: Style?, -- how it hunts (nil = plain; bosses have none)
	swim: Swim?, -- a boss's body (nil = the plain fish model)
}

local list: { PredatorDef } = {
	{
		id = "Barracuda",
		name = "Barracuda",
		model = "Barracuda",
		length = 9,
		health = 192, -- (8 bites from a fish of its level)
		level = 18,
		speed = 26,
		turnRate = 2.6,
		aggroRange = 90,
		-- The ambush sprinter: ~49 studs/s for 1.6 s from mid range, a snap from close,
		-- then winded 1.2 s (owner, 2026-10-20: "predator fish need to be a lot more
		-- aggressive and more accurate ... Easily killed a barracuda at lvl 16 by just
		-- going back and forth at it. It wouldnt attack unless I sat still for a second
		-- or two": it had needed a 32-stud line-up within 25° to burst, swam off for a
		-- second whenever a fish got beside it, and was winded 3 s after each try)
		style = {
			kind = "ambush",
			chase = 0.8,
			turnAtSpeed = 0.85,
			tellFollow = 1.9,
			slowsToTurn = 0.3,
			roam = 0.3,
			recover = 0.8,
			lurk = { 4, 16 },
			trigger = 44,
			burst = 1.9,
			burstSeconds = 1.6,
			burstTurn = 0.8,
			burstFacing = 0.75,
			burstLead = 0.7,
			whip = 3.2,
			snap = 1.6,
			cone = 0.45,
			commit = 0.6, -- (a juke late in its tell gets away about half the time)
			winded = 1.2,
			giveUp = 6,
			forget = 8,
			-- Out of breath, it still swings round to face the fish (a glide and a hard
			-- C-turn), so it can burst again the moment it has its wind
			carry = 0.35,
			comeTurn = 2.6,
			comePace = 0.45,
			sated = 1,
			glide = 0.3,
			beat = 2.6,
		},
		biteReach = 3,
		biteFraction = 0.2,
		biteCooldown = 1.4,
		telegraph = 0.7,
		ignoreBelow = 0.25,
		-- The wrecks are its water: an ambusher among the hulls
		band = { 500, 830 },
		angles = { 135, 225 },
		depth = { 6, 80 },
		count = 6,
		respawn = 60,
		loot = { hauls = 0.3, dna = 3, coral = 40 }, -- (a solo kill ~1 min of hunting)
		back = Color3.fromRGB(176, 192, 204),
		belly = Color3.fromRGB(248, 250, 252),
	},
	{
		id = "ReefShark",
		name = "Reef Shark",
		model = "ReefShark",
		length = 14,
		health = 288, -- (12 bites from a fish of its level)
		level = 45,
		-- The relentless tracker: 44 studs/s sustained runs down a Nibbler through its
		-- whole water (to ~LV 70) in a straight line and a 'Cuda only under ~LV 42 (it
		-- was 24: nothing in its water was slower than it, owner 2026-10-17; 46 until
		-- the player speed curve flattened past LV 33, 2026-10-18: a LV 45 'Cuda swims
		-- 45.9, was 47.2). At 42 a juke at its tell stopped beating it (19% bitten).
		speed = 44,
		turnRate = 1.6,
		aggroRange = 110,
		style = {
			kind = "tracker",
			chase = 1,
			turnAtSpeed = 0.6,
			tellFollow = 0.95,
			tellBrake = 0.5, -- heavy: it can't pull up short (a loop past it overshoots)
			tellFacing = 0.75, -- so it lines up before it commits
			snap = 1.5,
			cone = 0.3,
			commit = 0.7,
			whip = 1.8, -- (a fish darting round its head is turned on, not circled)
			slowsToTurn = 0.35,
			roam = 0.3,
			recover = 0.5,
			leash = 3,
			blood = 2,
			bloodBelow = 0.5,
			kelpShy = true,
			-- A missed pass: carries through, then a fast banked loop back in from the
			-- side (~2 s, was a ~4.5 s crawl round at its cruising turn rate)
			carry = 0.45,
			comeTurn = 2.4,
			comePace = 0.8,
			sated = 2.4,
			circle = 0.4,
			circleSeconds = 2.6,
			under = 0.35,
			underDepth = 28,
			feint = 0.2,
			glide = 0.1,
			beat = 2.2,
		},
		biteReach = 4,
		biteFraction = 0.3,
		biteCooldown = 2,
		telegraph = 0.8,
		ignoreBelow = 0.3,
		band = { 980, 1440 },
		angles = { 228, 312 }, -- the Open Blue is shark water (owner, 2026-10-08)
		depth = { 150, 430 }, -- open water, well off the floor (owner, 2026-10-09)
		count = 5,
		-- ...and its namesake: cruising the Coral Reef's outer half, over the heads
		also = { { band = { 600, 840 }, angles = { 225, 135 }, depth = { 18, 90 }, count = 4, level = 34 } },
		respawn = 100,
		loot = { hauls = 0.6, dna = 6, coral = 120 }, -- (a solo kill ~2 min of hunting)
		back = Color3.fromRGB(110, 124, 138),
		belly = Color3.fromRGB(230, 236, 240),
	},
	{
		-- The kelp's harrier: darts in, nips and loops back to come again. Its nip is
		-- light and its tell long, so it's where a new fish learns to juke; it leaves a
		-- fish still in the tutorial alone, and lets a fish go after two nips (owner,
		-- 2026-10-21: a warning, not a kill)
		id = "SeaLion",
		name = "Sea Lion",
		model = "SeaLion",
		girth = 0.13,
		length = 6,
		health = 144, -- (6 bites from a fish of its level)
		level = 6,
		speed = 27, -- (a LV 6 fish swims 21.6: it runs one down, a juke or a Dash beats it)
		turnRate = 3.2,
		aggroRange = 70,
		style = {
			kind = "tracker",
			chase = 1,
			turnAtSpeed = 0.95,
			tellFollow = 1,
			tellBrake = 1.6,
			tellFacing = 0.7,
			snap = 1.5,
			cone = 0.38,
			commit = 0.62,
			whip = 2.4,
			slowsToTurn = 0.45,
			roam = 0.45,
			recover = 0.9,
			leash = 2,
			carry = 0.35,
			comeTurn = 2.8,
			comePace = 1,
			sated = 1.2,
			circle = 0.5,
			circleSeconds = 2,
			feint = 0.35,
			glide = 0.25,
			beat = 1.8,
			spareLearners = true,
			nips = 2,
			forget = 30,
			warn = "NIP · JUKE SIDEWAYS",
		},
		biteReach = 2.2,
		biteFraction = 0.08,
		biteCooldown = 1.1,
		telegraph = 0.75,
		ignoreBelow = 0.2,
		band = { 260, 470 },
		depth = { 6, 60 },
		count = 5,
		respawn = 45,
		loot = { hauls = 0.25, dna = 2, coral = 25 },
		back = Color3.fromRGB(92, 64, 46),
		belly = Color3.fromRGB(138, 102, 72),
	},
	{
		-- The wreck bay's lurker: waits low by a hull and gulps, its open mouth sucking
		-- a fish in through its tell. Slow and tough; a Dash breaks the pull
		id = "GoliathGrouper",
		name = "Goliath Grouper",
		model = "GoliathGrouper",
		girth = 0.25,
		length = 13,
		health = 336, -- (14 bites)
		level = 18,
		speed = 18,
		turnRate = 1.6,
		aggroRange = 60,
		style = {
			kind = "ambush",
			chase = 0.6,
			turnAtSpeed = 0.9,
			tellFollow = 0.25,
			tellBrake = 4,
			tellFacing = 0.5,
			slowsToTurn = 0.4,
			roam = 0.3,
			recover = 0.5,
			lurk = { 3, 10 },
			trigger = 0, -- (no burst: it waits and gulps)
			snap = 1.8,
			cone = 0.35,
			commit = 0.7,
			winded = 1.6,
			giveUp = 4,
			forget = 10,
			carry = 0.3,
			comeTurn = 2,
			comePace = 0.5,
			sated = 1.5,
			glide = 0.15,
			beat = 3.2,
			gulp = { pull = 34, reach = 26, breakAt = 1.4 },
			warn = "GULP · DASH OUT",
		},
		biteReach = 5,
		biteFraction = 0.28,
		biteCooldown = 2.4,
		telegraph = 1.2,
		ignoreBelow = 0.15,
		band = { 500, 830 },
		angles = { 135, 225 },
		depth = { 4, 40 },
		count = 3,
		respawn = 90,
		loot = { hauls = 0.5, dna = 5, coral = 80 },
		back = Color3.fromRGB(104, 100, 58),
		belly = Color3.fromRGB(148, 138, 88),
	},
	{
		-- The reef's pack hunters, three together: one drives the fish, the other two
		-- swing out wide and come in from its flanks. Arches and tunnels hide you
		id = "GiantTrevally",
		name = "Giant Trevally",
		model = "GiantTrevally",
		girth = 0.22,
		length = 7,
		health = 144, -- (6 bites each)
		level = 32,
		speed = 36, -- (a LV 32 Nibbler swims 31.3, a 'Cuda 39.2)
		turnRate = 2.6,
		aggroRange = 90,
		style = {
			kind = "tracker",
			chase = 1,
			turnAtSpeed = 0.8,
			tellFollow = 0.9,
			tellBrake = 2,
			tellFacing = 0.7,
			snap = 1.5,
			cone = 0.4,
			commit = 0.6,
			whip = 2,
			slowsToTurn = 0.4,
			roam = 0.45,
			recover = 0.8,
			leash = 2.2,
			carry = 0.4,
			comeTurn = 2.4,
			comePace = 0.9,
			sated = 1.4,
			glide = 0.2,
			beat = 2,
			pack = { size = 3, spread = 16 },
			warn = "PACK · HIDE IN THE ARCHES",
		},
		biteReach = 2.6,
		biteFraction = 0.12,
		biteCooldown = 1.4,
		telegraph = 0.65,
		ignoreBelow = 0.2,
		band = { 520, 840 },
		angles = { 225, 135 },
		depth = { 8, 70 },
		count = 3, -- (packs)
		respawn = 75,
		loot = { hauls = 0.2, dna = 2, coral = 40 },
		back = Color3.fromRGB(138, 150, 160),
		belly = Color3.fromRGB(205, 212, 218),
	},
	{
		-- The Open Blue's missile: the fastest thing in the sea, it comes up from
		-- below. It turns wide, so a juke the moment its jaw flashes beats it; a late
		-- one doesn't, and nothing outruns it but a Dash
		id = "MakoShark",
		name = "Mako Shark",
		model = "MakoShark",
		girth = 0.16,
		length = 16,
		health = 240, -- (10 bites)
		level = 45,
		speed = 54, -- (a LV 45 'Cuda swims 45.9; a Dash 77)
		turnRate = 1.8,
		aggroRange = 130,
		style = {
			kind = "tracker",
			chase = 1,
			turnAtSpeed = 0.7,
			tellFollow = 1,
			tellBrake = 0.9,
			tellFacing = 0.75,
			snap = 1.5,
			cone = 0.5,
			commit = 0.6,
			slowsToTurn = 0.5,
			roam = 0.35,
			recover = 0.6,
			leash = 2.5,
			carry = 0.6,
			comeTurn = 2.2,
			comePace = 0.85,
			sated = 2.4,
			under = 0.75,
			underDepth = 45,
			circle = 0.1,
			circleSeconds = 2,
			feint = 0.15,
			glide = 0.1,
			beat = 2,
			warn = "FROM BELOW · JUKE NOW",
		},
		biteReach = 4,
		biteFraction = 0.3,
		biteCooldown = 2.2,
		telegraph = 0.8,
		ignoreBelow = 0.3,
		band = { 980, 1440 },
		angles = { 230, 310 },
		depth = { 120, 420 },
		count = 3,
		respawn = 120,
		loot = { hauls = 0.6, dna = 6, coral = 130 },
		back = Color3.fromRGB(52, 64, 140),
		belly = Color3.fromRGB(232, 236, 244),
	},
	{
		-- The Ruins' patroller: huge and slow, glowing green eyes in the gloom, a heavy
		-- bite. Any fish of its level outswims it
		id = "SixgillShark",
		name = "Sixgill Shark",
		model = "SixgillShark",
		girth = 0.16,
		length = 26,
		health = 384, -- (16 bites)
		level = 60,
		speed = 27, -- (a LV 60 Nibbler swims 41.5)
		turnRate = 1.1,
		aggroRange = 110,
		style = {
			kind = "tracker",
			chase = 1,
			turnAtSpeed = 0.6,
			tellFollow = 0.8,
			tellBrake = 0.6,
			tellFacing = 0.75,
			snap = 1.4,
			cone = 0.35,
			commit = 0.65,
			slowsToTurn = 0.4,
			roam = 0.5,
			recover = 0.6,
			leash = 1.6,
			carry = 0.6,
			comeTurn = 2,
			comePace = 0.7,
			sated = 2.5,
			circle = 0.35,
			circleSeconds = 3,
			glide = 0.12,
			beat = 3.4,
			warn = "HEAVY BITE · SWIM CLEAR",
		},
		biteReach = 6,
		biteFraction = 0.4,
		biteCooldown = 2.6,
		telegraph = 1,
		ignoreBelow = 0.25,
		band = { 960, 1440 },
		angles = { 320, 63 },
		depth = { 8, 60 },
		count = 4,
		respawn = 120,
		loot = { hauls = 0.8, dna = 8, coral = 180 },
		back = Color3.fromRGB(72, 66, 60),
		belly = Color3.fromRGB(112, 106, 98),
	},
	{
		-- The Vents' crevice striker: it lies in a basalt hole and lunges out with a
		-- long reach, never straying far from it. Keep your distance, or Dash
		id = "WolfEel",
		name = "Wolf Eel",
		model = "WolfEel",
		girth = 0.16,
		length = 22,
		health = 240, -- (10 bites)
		level = 75,
		speed = 40,
		turnRate = 2.4,
		aggroRange = 60,
		style = {
			kind = "ambush",
			chase = 0.9,
			turnAtSpeed = 1,
			tellFollow = 1.4,
			tellBrake = 2,
			tellFacing = 0.6,
			slowsToTurn = 0.5,
			roam = 0.2,
			recover = 0.8,
			lurk = { 2, 6 },
			trigger = 30,
			burst = 1.6,
			burstSeconds = 0.8,
			burstTurn = 0.9,
			burstFacing = 0.7,
			burstLead = 0.5,
			snap = 2.2,
			cone = 0.4,
			commit = 0.55,
			winded = 1.2,
			giveUp = 5,
			forget = 8,
			carry = 0.3,
			comeTurn = 2.6,
			comePace = 0.6,
			sated = 1,
			glide = 0.15,
			beat = 2.4,
			tether = 36,
			warn = "LUNGE · BACK OFF",
		},
		biteReach = 6,
		biteFraction = 0.3,
		biteCooldown = 1.8,
		telegraph = 0.7,
		ignoreBelow = 0.2,
		band = { 900, 1440 },
		angles = { 130, 220 },
		depth = { 2, 12 },
		count = 6,
		respawn = 90,
		loot = { hauls = 0.6, dna = 6, coral = 150 },
		back = Color3.fromRGB(88, 108, 128),
		belly = Color3.fromRGB(138, 156, 170),
	},
	{
		-- The Trench's jaw launcher: a slow cruiser whose jaws shoot out for a long
		-- bite. The tell is long and its jaws stay on their line: dodge sideways
		id = "GoblinShark",
		name = "Goblin Shark",
		model = "GoblinShark",
		girth = 0.15,
		mouth = 0.2, -- (its jaws launch from under its snout)
		length = 22,
		health = 336, -- (14 bites)
		level = 90,
		speed = 32,
		turnRate = 1.3,
		aggroRange = 110,
		style = {
			kind = "tracker",
			chase = 1,
			turnAtSpeed = 0.6,
			tellFollow = 0.5,
			tellBrake = 3,
			tellFacing = 0.8,
			snap = 2.4,
			cone = 0.55,
			commit = 0.4,
			slowsToTurn = 0.4,
			roam = 0.5,
			recover = 0.6,
			leash = 1.6,
			carry = 0.5,
			comeTurn = 2,
			comePace = 0.7,
			sated = 2.2,
			glide = 0.12,
			beat = 3,
			trench = true,
			warn = "JAW THROW · DODGE SIDEWAYS",
		},
		biteReach = 7,
		biteFraction = 0.35,
		biteCooldown = 2.4,
		telegraph = 1.1,
		ignoreBelow = 0.25,
		band = { 1000, 1420 },
		angles = { 68, 125 },
		depth = { 10, 90 },
		count = 3,
		respawn = 120,
		loot = { hauls = 0.9, dna = 9, coral = 240 },
		back = Color3.fromRGB(100, 120, 140),
		belly = Color3.fromRGB(150, 166, 180),
	},
	{
		-- The Trench's lure: a glowing bulb in the dark that draws in the fish it
		-- stalks, then a short, fast lunge. Swim off when you feel the pull
		id = "BlackDragonfish",
		name = "Black Dragonfish",
		model = "BlackDragonfish",
		girth = 0.11,
		length = 12,
		health = 144, -- (6 bites)
		level = 88,
		speed = 30,
		turnRate = 2.8,
		aggroRange = 90,
		style = {
			kind = "ambush",
			chase = 0.5,
			turnAtSpeed = 1,
			tellFollow = 2,
			tellBrake = 2,
			tellFacing = 0.6,
			slowsToTurn = 0.4,
			roam = 0.25,
			recover = 0.8,
			trigger = 22,
			burst = 2.4,
			burstSeconds = 0.7,
			burstTurn = 0.9,
			burstFacing = 0.75,
			burstLead = 0.6,
			snap = 1.8,
			cone = 0.45,
			commit = 0.6,
			winded = 1.4,
			giveUp = 5,
			forget = 8,
			carry = 0.35,
			comeTurn = 2.4,
			comePace = 0.6,
			sated = 1.2,
			glide = 0.2,
			beat = 2.6,
			trench = true,
			lure = { radius = 45, pull = 9 },
			warn = "IT'S A LURE · DASH OFF",
		},
		biteReach = 4,
		biteFraction = 0.25,
		biteCooldown = 1.6,
		telegraph = 0.6,
		ignoreBelow = 0.15,
		band = { 1000, 1420 },
		angles = { 68, 125 },
		depth = { 30, 160 },
		count = 5,
		respawn = 90,
		loot = { hauls = 0.5, dna = 6, coral = 160 },
		back = Color3.fromRGB(24, 24, 32),
		belly = Color3.fromRGB(36, 36, 46),
	},
	{
		-- The Open Blue's top hunters (owner, 2026-10-28: "hammerheads ... appear to be
		-- impervious to players ... Hammerhead should be a top tier predator"): a pack
		-- of three round Hammerhead Pinnacle, the highest level of any plain predator.
		-- They turn on a coin (the wide head), circle a fish before they come in, and
		-- swing out to its flanks like the trevally. A Dash away or the pinnacle's
		-- ledges break a pack's run; only a fish near their level should take them on
		id = "Hammerhead",
		name = "Great Hammerhead",
		model = "Hammerhead", -- (VariantModels.Hammerhead, the Reef Shark's variant)
		girth = 0.16,
		length = 20,
		health = 360, -- (15 bites at its level)
		level = 72,
		speed = 52, -- (a LV 72 'Cuda swims ~58, a Nibbler ~44; a Dash outruns it)
		turnRate = 2.6,
		aggroRange = 140,
		style = {
			kind = "tracker",
			chase = 1,
			turnAtSpeed = 0.85,
			tellFollow = 1,
			tellBrake = 1.2,
			tellFacing = 0.75,
			snap = 1.5,
			cone = 0.45,
			commit = 0.65,
			whip = 2.2,
			slowsToTurn = 0.35,
			roam = 0.4,
			recover = 0.7,
			leash = 2.4,
			carry = 0.45,
			comeTurn = 2.6,
			comePace = 0.9,
			sated = 2,
			circle = 0.35,
			circleSeconds = 2.4,
			feint = 0.1,
			glide = 0.15,
			beat = 2.2,
			pack = { size = 3, spread = 22 },
			warn = "HAMMERHEADS · DASH CLEAR",
		},
		biteReach = 4,
		biteFraction = 0.26, -- (three of them: a still fish of its level lasts ~10 s)
		biteCooldown = 2,
		telegraph = 0.75,
		ignoreBelow = 0.25,
		band = { 1240, 1490 },
		angles = { 256, 292 },
		depth = { 20, 170 },
		count = 2, -- (packs)
		respawn = 150,
		loot = { hauls = 0.9, dna = 10, coral = 300 },
		back = Color3.fromRGB(104, 116, 128),
		belly = Color3.fromRGB(214, 220, 226),
	},
}

local byId: { [string]: PredatorDef } = {}
for _, def in list do
	byId[def.id] = def
end

-- Every group to spawn: each kind in its home water, then a copy of it for each of
-- its `also` waters (the same id, so clients draw it the same)
local groups: { PredatorDef } = {}
for _, def in list do
	table.insert(groups, def)
	for _, water in (def.also or {}) :: { Water } do
		local copy = table.clone(def)
		copy.band, copy.angles, copy.depth, copy.count = water.band, water.angles, water.depth, water.count
		copy.level = water.level or def.level
		copy.also = nil
		table.insert(groups, copy)
	end
end

return {
	list = list,
	byId = byId,
	groups = groups,
	-- A player is streamed the creatures within this many studs of their fish (and
	-- any hunting them, and every boss); past it the water hides them anyway
	streamRange = 700,
	-- Spread and crowding (owner, 2026-10-22: "Predators should be more spread out.
	-- And they shouldn't mob a player either"). A group's `count` share its water out,
	-- a patch each: the sector (or the whole ring) cut into `count` arcs with `overlap`
	-- of an arc either side (the Trench's canyon is cut along its length), and each
	-- roams and lurks in its own. Roaming, it eases off any other creature within
	-- `spacing` studs (its packmates aside).
	spread = { overlap = 0.15, spacing = 70 },
	-- At most `hunters` hunt one fish at a time (a pack counts as one, a boss too; a
	-- fish that bit it is always fair game); the rest keep `gap` studs clear of a fish
	-- that's taken, and at most `chum` make for one chum cloud.
	mob = { hunters = 2, gap = 60, chum = 2 },
	tickSeconds = 0.1, -- the server simulates and streams at this rate
	roamSpeed = 0.55, -- × speed while roaming
	-- No creature comes within this many studs of the hub's center (plus half its
	-- length): the seamount, its cave and tunnels and the sand round the tunnel
	-- mouths (owner, 2026-10-11: "Starter cave should never have predator fish or
	-- anything that can hurt you in it"). A fish in there is never a target.
	hubKeepOut = 210,
	schoolBonus = 0.35, -- + per other fish that bit it in the last schoolWindow
	schoolWindow = 2.5,
	-- A fight with a plain predator goes by level, like a fight between players
	-- (Config/Pvp `fight`; owner, 2026-10-21: "Ensure ease of eating them scales with
	-- levels as well"): (the mass at one level ÷ the other's) ^ `power`, about ×1.07 a
	-- level. A player's bite on it is Tuning hunt.biteDamage × that, within `yours`,
	-- so a fish 10 levels up bites about twice as hard (a few bites) and one 10 down
	-- half as hard; `swallow` levels up, one bite swallows it whole. Its bite on a
	-- player is its biteFraction × the same the other way, within `theirs` (a fish
	-- under its level takes up to 1.5×, one well above it a nip). It won't hunt a fish
	-- `shy` levels above it (it shies off unless bitten), and a kill pays each biter
	-- × (its strength over theirs) ^ `pay` when they're above it, down to `payMin`, so
	-- farming low predators pays little.
	fight = {
		power = 2 / 3,
		yours = { min = 0.05, max = 4 },
		theirs = { min = 0.15, max = 1.5 },
		swallow = 20,
		shy = 12,
		pay = 1.5,
		payMin = 0.05,
	},
	-- A boss's bite scale (`bitten`) is clamped to these; biteRatioPower is the old
	-- length rule for a creature with neither `level` nor `bitten`
	biteRatioPower = 1.5,
	biteRatioMin = 0.08,
	biteRatioMax = 1.2,
	loseRange = 1.7, -- × aggroRange: a target this far away is dropped
	-- The strike (owner, 2026-10-17: "Predator fish have horrible aim and are barely a
	-- threat; even sitting still they can't hit me"): a hunter opens its jaw (the
	-- tell) a little way out and glides in, timed to hold its mouth just off the fish
	-- as the tell ends, then snaps. It had come in at a sprint, opened its jaw already
	-- on top of the fish and slid ~15 studs past before the snap, so a fish that sat
	-- still was missed 85-100% of the time (tools/tests/run_predators.sh).
	strike = {
		hold = 0.5, -- × biteReach, plus half the fish's length: where the open jaw waits
		closing = 0.5, -- the tell starts this × speed × telegraph further out than that
		brake = 3, -- × speed per second: how hard it can pull up during the tell (a style's `tellBrake`)
		facing = 0.4, -- the fish must be in front of it (cosine of the angle) for a tell
		cone = 0.45, -- ...and still in front of its jaws (cosine) when it snaps
	},
	-- A puffed fish (the Pufferfish's Puff Up: character attribute `Puffed`, the clock
	-- it deflates at) takes `puffDamage` of a bite, and a plain predator that bites one
	-- takes `puffRecoil` of its own max health and flinches (stunned) `puffFlinch` s
	puffDamage = 0.5,
	puffRecoil = 0.12,
	puffFlinch = 2.5,
	interpolationDelay = 0.15, -- clients draw this far behind the stream
}
