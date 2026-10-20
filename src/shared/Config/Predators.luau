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

export type PredatorDef = {
	id: string,
	name: string,
	model: string, -- ReplicatedStorage.PreyModels.<model> (static mesh), else a part body
	tag: string?, -- the tag's first line (default PREDATOR)
	length: number, -- studs
	health: number,
	speed: number, -- studs/s hunting (roaming is slower)
	turnRate: number, -- radians/s
	aggroRange: number, -- studs: fish inside get hunted
	biteReach: number, -- studs past the mouth
	biteFraction: number, -- of the victim's max health
	biteCooldown: number, -- seconds between bites
	telegraph: number, -- seconds the jaw shows before it bites (the tell)
	ignoreBelow: number, -- fish shorter than this × its length are left alone unless they bite it
	band: { number }, -- distance from the hub's center it roams in (min, max)
	angles: { number }?, -- the sector it keeps to (degrees from +X toward +Z, clockwise; nil = all round)
	depth: { number }, -- height above the local floor it roams in (min, max; Shared/Seafloor)
	count: number, -- alive at once
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
		health = 140,
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
			snap = 2,
			cone = 0.25,
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
		telegraph = 0.55,
		ignoreBelow = 0.25,
		band = { 300, 820 },
		depth = { 8, 120 },
		count = 4,
		respawn = 90,
		loot = { hauls = 0.3, dna = 3, coral = 40 }, -- (a solo kill ~1 min of hunting)
		back = Color3.fromRGB(176, 192, 204),
		belly = Color3.fromRGB(248, 250, 252),
	},
	{
		id = "ReefShark",
		name = "Reef Shark",
		model = "ReefShark",
		length = 14,
		health = 320,
		-- The relentless tracker: 44 studs/s sustained runs down a Nibbler through its
		-- whole water (to ~LV 70) in a straight line and a 'Cuda only under ~LV 42 (it
		-- was 24: nothing in its water was slower than it, owner 2026-10-17; 46 until
		-- the player speed curve flattened past LV 33, 2026-10-18: a LV 45 'Cuda swims
		-- 45.9, was 47.2). At 42 a juke at its tell stopped beating it (19% bitten).
		speed = 44,
		turnRate = 1.6,
		aggroRange = 80,
		style = {
			kind = "tracker",
			chase = 1,
			turnAtSpeed = 0.45,
			tellFollow = 0.95,
			tellBrake = 0.5, -- heavy: it can't pull up short (a loop past it overshoots)
			tellFacing = 0.9, -- so it lines up before it commits
			snap = 1.2,
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
		biteCooldown = 2.8,
		telegraph = 1.1,
		ignoreBelow = 0.3,
		band = { 980, 1440 },
		angles = { 228, 312 }, -- the Open Blue is shark water (owner, 2026-10-08)
		depth = { 150, 430 }, -- open water, well off the floor (owner, 2026-10-09)
		count = 4,
		respawn = 150,
		loot = { hauls = 0.6, dna = 6, coral = 120 }, -- (a solo kill ~2 min of hunting)
		back = Color3.fromRGB(110, 124, 138),
		belly = Color3.fromRGB(230, 236, 240),
	},
}

local byId: { [string]: PredatorDef } = {}
for _, def in list do
	byId[def.id] = def
end

return {
	list = list,
	byId = byId,
	tickSeconds = 0.1, -- the server simulates and streams at this rate
	roamSpeed = 0.55, -- × speed while roaming
	-- No creature comes within this many studs of the hub's center (plus half its
	-- length): the seamount, its cave and tunnels and the sand round the tunnel
	-- mouths (owner, 2026-10-11: "Starter cave should never have predator fish or
	-- anything that can hurt you in it"). A fish in there is never a target.
	hubKeepOut = 210,
	schoolBonus = 0.35, -- + per other fish that bit it in the last schoolWindow
	schoolWindow = 2.5,
	-- A player's bite on a predator: biteDamage × (their length / its length) ^ 1.5,
	-- clamped, so small fish chip and big fish chunk
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
