--!strict
-- Every species ability, by id (Config/Species lists each species' options for its
-- upgrade tree, and `signature` names the one on its ability button).
--
-- Signature abilities (owner, 2026-10-17: "each different fish should have their own
-- limitations/advantages"; "You decide how that plays"): every fish has one way out
-- of trouble, and each is a different answer to a predator:
--   Nibbler     Dash: a short burst, the quickest to recharge (the all-rounder)
--   'Cuda       Torpedo: a long straight sprint at Dash speed that barely turns
--               (outruns anything in a line; can't dodge while it runs)
--   Pufferfish  Puff Up: swells for a few seconds: nothing can swallow it, bites on it
--               do half and hurt the biter, but it swims slowly
--   Moray Eel   Burrow: against rock or wreckage it hides (predators lose it, it
--               fades from view) until it moves; its next bite is an ambush
--   Reef Shark  Blood Sense: a feeding frenzy: every fish and predator shows through
--               rock as heat, the prey round it too, and it swims faster and draws
--               prey in from further
--   Anglerfish  Lantern Flash: a blinding flash that stuns predators and whites out
--               nearby players' screens
-- AbilityController (client) runs them; AbilityService (server) owns the ones the
-- server must know about (Puff Up, Burrow, Lantern Flash, Blood Sense).
export type Ability = {
	name: string,
	blurb: string,
	label: string?, -- the ability button's word (default: the name in capitals)
	seconds: number?, -- how long it lasts
	cooldown: number?, -- seconds before it can go again (from its start)
	-- per ability
	turn: number?, -- Torpedo: turning while it runs (× the Dash's)
	slow: number?, -- Puff Up: × top speed while puffed
	scale: number?, -- Puff Up: the body drawn this much bigger
	recoil: number?, -- Puff Up: a player biting it takes this share of their max health
	damageTaken: number?, -- Puff Up: × damage from bites while puffed
	reach: number?, -- Burrow: × length to the nearest rock or wreck; Lantern Flash: studs
	stray: number?, -- Burrow: studs it may drift before it comes out
	strike: number?, -- Burrow: seconds after coming out its bite is an ambush
	strikeBonus: number?, -- Burrow: × that bite's damage
	stun: number?, -- Lantern Flash: seconds predators are stunned
	blind: number?, -- Lantern Flash: seconds a nearby player's screen is whited out
	speed: number?, -- Blood Sense: × top speed while it runs
	suction: number?, -- Blood Sense: × the reach prey are drawn in and swallowed from
	range: number?, -- Blood Sense: studs round the shark its prey are marked within
}

local byId: { [string]: Ability } = {
	Dash = { name = "Dash", blurb = "A short burst of speed that recharges quickly." },
	Torpedo = {
		name = "Torpedo",
		blurb = "A long, straight sprint at Dash speed. Outruns anything in a line, but it barely turns while it runs.",
		seconds = 1.4,
		cooldown = 7,
		turn = 0.2,
	},
	RazorBite = { name = "Razor Bite", blurb = "Your bites make the target bleed." },
	SilverFlash = { name = "Silver Flash", blurb = "A flash of scales blinds a fish for a moment." },
	PuffUp = {
		name = "Puff Up",
		label = "PUFF",
		blurb = "Swell up for 4 seconds: bites do half and hurt the biter, but you swim slowly.",
		seconds = 4,
		cooldown = 16,
		slow = 0.45,
		scale = 1.45,
		recoil = 0.1,
		damageTaken = 0.5,
	},
	SpikeBurst = { name = "Spike Burst", blurb = "Fire spines at everything close by." },
	ToxicCloud = { name = "Toxic Cloud", blurb = "Leave a poison cloud that slows and hurts." },
	Strike = { name = "Strike", blurb = "A long, lightning-fast lunge." },
	Burrow = {
		name = "Burrow",
		blurb = "Against rock or wreckage, hide: predators lose you and you fade from view until you move. Your next bite is an ambush (×1.6).",
		seconds = 30, -- at most
		cooldown = 8,
		reach = 0.9,
		stray = 4,
		strike = 1.5,
		strikeBonus = 1.6,
	},
	Shock = { name = "Shock", blurb = "Stun every fish touching you." },
	Frenzy = { name = "Frenzy", blurb = "Bite faster after every hit." },
	-- A feeding frenzy (owner, 2026-10-18: "Sharks frenzy should have him move a bit
	-- faster and should also act as a bit of a magnet towards prey fish and pull them
	-- in from a wider distance. Should also highlight both prey and predator fish"):
	-- the server sets `Sensing` on the character (AbilityService), SwimController,
	-- SchoolController, ForageController and HuntService read it (Perks.sense)
	BloodSense = {
		name = "Blood Sense",
		label = "SENSE",
		blurb = "A feeding frenzy for 7 seconds: you swim 25% faster, prey are pulled into your jaws from twice as far, and every other fish and predator shows through rock and murk as heat, the prey round you too.",
		seconds = 7,
		cooldown = 24,
		speed = 1.25,
		suction = 2,
		range = 120,
	},
	Ram = { name = "Ram", blurb = "Charge and knock a fish aside." },
	Lure = { name = "Lure", blurb = "Your light pulls nearby prey toward you." },
	LanternFlash = {
		name = "Lantern Flash",
		label = "FLASH",
		blurb = "A blinding flash: predators within 45 ft are stunned for 2.5 seconds and nearby players are dazzled.",
		cooldown = 18,
		reach = 48,
		stun = 2.5,
		blind = 1.4,
	},
	DeepSight = { name = "Deep Sight", blurb = "See clearly in the darkest water." },
}

return {
	byId = byId,
}
