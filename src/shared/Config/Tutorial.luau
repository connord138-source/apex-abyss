--!strict
-- The first-session tutorial (owner: everyone starts as the Nibbler and is led
-- through upgrading it before other species can be picked). Each step counts one
-- kind of event (TutorialService); finishing unlocks the 'Cuda and species select.
-- Steps for the barracuda and the upgrade tree get added when those systems land.
-- A control the step's card shows: the key on each kind of device (nil = the
-- device has no key for it, so the cap is left out) and what it does
export type Control = {
	keys: string?, -- keyboard and mouse
	pad: string?, -- controller
	touch: string?, -- the phone's buttons
	does: string,
}

export type Step = {
	id: string,
	text: string,
	goal: number,
	event: "leftHub" | "ate" | "banked" | "shells" | "level",
	marker: string?, -- what the client points at ("exits", "den")
	-- What the guide trail leads to while this step is up (TutorialController):
	-- the nearest exit, the nearest food, your den's pool, the nearest shell
	guide: ("exits" | "food" | "den" | "shells")?,
	controls: { Control },
}

-- The tutorial is directed (owner, 2026-10-12: "Controls need to be more obvious
-- during the tutorial and tutorial needs to be more directed instead of just a
-- floating Ui"): each step's card shows the keys it needs as key caps, and a
-- trail of lights leads to the step's target.
local steps: { Step } = {
	{
		id = "LeaveHub",
		text = "Follow the lights out of the hub, through a tunnel or the hole in the roof",
		goal = 1,
		event = "leftHub",
		marker = "exits",
		guide = "exits",
		controls = {
			{ keys = "W A S D", pad = "L STICK", touch = "STICK", does = "swim" },
			{ keys = "MOUSE", pad = "R STICK", touch = "DRAG", does = "look" },
			{ keys = "SPACE / CTRL", pad = "A / B", does = "up / down" },
		},
	},
	{
		id = "Eat",
		text = "Swim into 10 small fish, shrimp or starfish. They're swallowed on touch, no button",
		goal = 10,
		event = "ate",
		guide = "food",
		controls = {
			{ keys = "LEFT CLICK", pad = "RT", touch = "DASH", does = "dash" },
			{ keys = "SPACE / CTRL", pad = "A / B", does = "up / down" },
		},
	},
	{
		id = "Bank",
		text = "Swim home and into your den's glowing pool to bank your Haul",
		goal = 1,
		event = "banked",
		marker = "den",
		guide = "den",
		controls = {
			{ keys = "RIGHT CLICK", pad = "RB", touch = "BITE", does = "bite fish your size" },
			{ keys = "LEFT CLICK", pad = "RT", touch = "DASH", does = "dash away" },
		},
	},
	{
		id = "Shells",
		text = "Pick up 5 shells from the seabed. 50 shells buy a roll for a new skin",
		goal = 5,
		event = "shells",
		guide = "shells",
		controls = {
			{ keys = "ALT", does = "free the cursor for buttons" },
			{ keys = "E", pad = "Y", touch = "SHOP", does = "shop at a stall" },
		},
	},
	{
		id = "Level",
		text = "Grow your Nibbler to level 10: eat, bank, repeat. Bigger fish are worth more",
		goal = 10,
		event = "level",
		guide = "food",
		controls = {
			{ keys = "H", pad = "LB", touch = "HEAL", does = "heal (Kelp Wrap)" },
			{ keys = "G", pad = "HOLD LB", touch = "ITEMS", does = "item wheel" },
			{ keys = "ALT", does = "free the cursor" },
		},
	},
}

return {
	steps = steps,
	-- For finishing: the 'Cuda, enough shells for a first roll, and some coral
	reward = { unlock = "Cuda", shells = 50, coral = 500 },
}
