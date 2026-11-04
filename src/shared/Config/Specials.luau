--!strict
-- Every fish's special attack (owner, 2026-11-03: "Potentially add a special attack
-- ability that builds up and is different for each playable fish?"; the six designs
-- approved the same day). A meter fills as the fish lands bites, and a little as it
-- swallows; full, the special key spends all of it. Earned only, never sold.
-- SpecialService owns the meter and what each one does; SpecialController draws them.
export type Special = {
	id: string,
	name: string,
	blurb: string,
	color: Color3,
	seconds: number?, -- how long it runs
	scale: number?, -- × a normal bite's damage, each time it lands
	rate: number?, -- Wild Thrash: × how fast it bites
	turn: number?, -- Spear Charge: × the Dash's turning while it runs
	radius: number?, -- Spine Burst, Abyss Maw: studs ...
	perLength: number?, -- ... plus this × the fish's length
	push: number?, -- Spine Burst: studs/s what it hits is thrown away
	pull: number?, -- Abyss Maw: studs/s what it hits is dragged in
	stun: number?, -- seconds a predator it throws or drags is stunned
	reach: number?, -- Death Roll: lengths past the bite's reach it can grab from
	leash: number?, -- Death Roll: lengths apart before the grip breaks
	ticks: number?, -- Death Roll: how many times it bites
	every: number?, -- Death Roll: seconds between them
	bonus: number?, -- Blood Frenzy: × bite damage
	heal: number?, -- Blood Frenzy: share of max health back on each bite that lands
	suction: number?, -- Abyss Maw: × how far prey is drawn in
}

local bySpecies: { [string]: Special } = {
	Nibbler = {
		id = "WildThrash",
		name = "Wild Thrash",
		blurb = "A frenzy of tiny bites: for 4 seconds it latches on and bites three times as fast.",
		color = Color3.fromRGB(255, 196, 64),
		seconds = 4,
		rate = 3,
	},
	Cuda = {
		id = "SpearCharge",
		name = "Spear Charge",
		blurb = "A dead-straight lunge that bites everything in its line, each for three bites' damage.",
		color = Color3.fromRGB(190, 232, 255),
		seconds = 1.2,
		turn = 0.12,
		scale = 3,
	},
	Pufferfish = {
		id = "SpineBurst",
		name = "Spine Burst",
		blurb = "Spines fly out all round it, hurting everything close and throwing it clear.",
		color = Color3.fromRGB(255, 226, 120),
		radius = 18,
		perLength = 2.5,
		scale = 2.5,
		push = 90,
		stun = 1.5,
	},
	MorayEel = {
		id = "DeathRoll",
		name = "Death Roll",
		blurb = "Grabs what's in front of it and spins, holding it and biting five times.",
		color = Color3.fromRGB(120, 230, 170),
		reach = 1.2,
		leash = 3,
		ticks = 5,
		every = 0.4,
		scale = 1.3,
	},
	ReefShark = {
		id = "BloodFrenzy",
		name = "Blood Frenzy",
		blurb = "For 6 seconds its bites do double damage, and each one that lands heals it.",
		color = Color3.fromRGB(255, 70, 70),
		seconds = 6,
		bonus = 2,
		heal = 0.08,
	},
	Anglerfish = {
		id = "AbyssMaw",
		name = "Abyss Maw",
		blurb = "One enormous gulp: fish are dragged in and hurt, and small prey is swallowed from far off.",
		color = Color3.fromRGB(140, 110, 255),
		seconds = 1.4,
		radius = 24,
		perLength = 3,
		scale = 2,
		pull = 70,
		stun = 1.5,
		suction = 6,
	},
}

return {
	bySpecies = bySpecies,
	charge = {
		perBite = 0.125, -- 8 bites that land fill it
		perSwallow = 0.01, -- and a little from swallowing, so everyone finds it on a dive
	},
}
