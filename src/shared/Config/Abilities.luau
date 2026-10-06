--!strict
-- Every species ability, by id (Config/Species lists each species' options; the
-- player picks one in that species' upgrade tree). Only the Nibbler's Dash works so
-- far; the rest arrive with the upgrade trees.
export type Ability = {
	name: string,
	blurb: string,
}

local byId: { [string]: Ability } = {
	Dash = { name = "Dash", blurb = "A short burst of speed that recharges." },
	Torpedo = { name = "Torpedo", blurb = "Charge up, then a long straight sprint." },
	RazorBite = { name = "Razor Bite", blurb = "Your bites make the target bleed." },
	SilverFlash = { name = "Silver Flash", blurb = "A flash of scales blinds a fish for a moment." },
	PuffUp = { name = "Puff Up", blurb = "Swell up: nothing can swallow you for 3 seconds." },
	SpikeBurst = { name = "Spike Burst", blurb = "Fire spines at everything close by." },
	ToxicCloud = { name = "Toxic Cloud", blurb = "Leave a poison cloud that slows and hurts." },
	Strike = { name = "Strike", blurb = "A long, lightning-fast lunge." },
	Burrow = { name = "Burrow", blurb = "Hide in rock or wreckage until you strike." },
	Shock = { name = "Shock", blurb = "Stun every fish touching you." },
	Frenzy = { name = "Frenzy", blurb = "Bite faster after every hit." },
	BloodSense = { name = "Blood Sense", blurb = "See hurt fish through the murk." },
	Ram = { name = "Ram", blurb = "Charge and knock a fish aside." },
	Lure = { name = "Lure", blurb = "Your light pulls nearby prey toward you." },
	LanternFlash = { name = "Lantern Flash", blurb = "A blinding flash that stuns." },
	DeepSight = { name = "Deep Sight", blurb = "See clearly in the darkest water." },
}

return {
	byId = byId,
}
