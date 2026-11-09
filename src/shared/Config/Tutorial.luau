--!strict
-- The first-session tutorial (owner: everyone starts as the Nibbler and is led
-- through it before other species can be picked). Each step counts one kind of
-- event on the server (TutorialService); the client shows the step, its keys and
-- the way (TutorialController). Finishing pays a little coral and shells (the 'Cuda
-- is earned after, Config/Species).
--
-- A full first loop (owner, 2026-10-18: "Tutorial could be a bit longer and
-- actually show them how to complete a full cycle of hunting, storing, spinning,
-- etc."; a large share of the players are kids who need direction): eat, pick up
-- shells, fill the Haul, bank it at home (the growth sequence shows the fish getting
-- bigger), roll, use a Kelp Wrap from the item bar, open the INDEX, which says what
-- to do next, and spin the Treasure Wheel on the plaza.
--
-- Out in the sea first (owner, 2026-11-08, from the onboarding funnel: 28% of new
-- players never got out of the hub and a third of the rest never ate 5 things; half
-- were gone by 3 minutes): a new fish starts its first dive on the sand past the
-- mouth of the tunnel nearest its den (FishService), not in its den behind a loading
-- wash, the plaza and a tunnel, so it's eating within seconds; the Bank step leads it
-- home the way it came. The steps that need nothing but a button (Roll, Wrap, Index)
-- come straight after the bank, in the den, and the trip out to the plaza's wheel is
-- last (31% stopped at the wheel when it came straight after the bank).
local Tuning = require(script.Parent.Tuning)

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
	title: string, -- the goal in a few words, big on the card and the step's banner
	text: string,
	-- How many of `event` finish it ("haul": percent of the Haul target)
	goal: number,
	event: "ate" | "shells" | "haul" | "banked" | "spun" | "rolled" | "item" | "index",
	marker: string?, -- what the client points at in the world ("exits", "den")
	-- What the guide trail leads to while this step is up (TutorialController):
	-- the nearest exit, the nearest food, your den's pool, the nearest shell, the
	-- Treasure Wheel's red button
	guide: ("exits" | "food" | "den" | "shells" | "wheel")?,
	-- A HUD button the step rings instead (TutorialController): the ROLL button, the
	-- item bar's Kelp Wrap, the INDEX button
	point: ("Roll" | "Wrap" | "Index")?,
	-- What the server hands over as the step starts, when the player has none: a
	-- wheel spin, shells up to a roll, a Kelp Wrap (TutorialService `enter`)
	grant: ("spin" | "roll" | "wrap")?,
	-- The step's work is out in the sea: while it's up the fish (re)spawns there, on the
	-- sand past the tunnel nearest its den (FishService), instead of in its den
	outside: boolean?,
	controls: { Control },
}

-- Each step's card shows the keys it needs as key caps (owner, 2026-10-12:
-- "Controls need to be more obvious during the tutorial and tutorial needs to be
-- more directed instead of just a floating Ui"), and a trail of lights leads to the
-- step's target, or a ring breathes round the HUD button it needs.
local steps: { Step } = {
	{
		id = "Eat",
		-- (5, not 10: ten of the shallows' fish filled a new fish's whole Haul, so the
		-- Haul step was done the moment it showed; PC report 2026-10-20)
		title = "EAT 5 SMALL THINGS",
		text = "Swim into 5 small fish, shrimp or starfish. Smaller things are swallowed on touch, no button",
		goal = 5,
		event = "ate",
		guide = "food",
		outside = true,
		-- (on a phone UP / DOWN instead of DASH: the shrimp and starfish lie on the
		-- seabed, and the card has room for three; owner, 2026-11-08)
		controls = {
			{ keys = "W A S D", pad = "L STICK", touch = "STICK", does = "swim" },
			{ keys = "MOUSE", pad = "R STICK", touch = "DRAG", does = "look" },
			{ keys = "LEFT CLICK", pad = "RT", does = "dash" },
			{ touch = "UP / DOWN", does = "up / down" },
		},
	},
	{
		id = "Shells",
		title = "PICK UP 5 SHELLS",
		text = "Pick up 5 shells from the seabed. Every 50 shells buys a roll for a new skin",
		goal = 5,
		event = "shells",
		guide = "shells",
		outside = true,
		controls = {
			{ keys = "W A S D", pad = "L STICK", touch = "STICK", does = "swim to it" },
			{ keys = "SPACE / CTRL", pad = "A / B", touch = "UP / DOWN", does = "up / down" },
			{ keys = "LEFT CLICK", pad = "RT", touch = "DASH", does = "dash" },
		},
	},
	{
		id = "Haul",
		title = "FILL YOUR HAUL",
		text = "Keep eating to fill your Haul. It grows you now, but it's only yours for good once it's banked",
		goal = 100,
		event = "haul",
		guide = "food",
		outside = true,
		controls = {
			{ keys = "RIGHT CLICK", pad = "RB", touch = "BITE", does = "bite other fish" },
			{ keys = "LEFT CLICK", pad = "RT", touch = "DASH", does = "dash" },
		},
	},
	{
		id = "Bank",
		title = "BANK IT AT HOME",
		text = "Follow the lights home through a tunnel and your den's door into its glowing pool. Watch yourself grow!",
		goal = 1,
		event = "banked",
		marker = "den",
		guide = "den",
		controls = {
			{ keys = "M", pad = "R3", touch = "MAP", does = "map" },
			{ keys = "LEFT CLICK", pad = "RT", touch = "DASH", does = "dash home" },
		},
	},
	{
		id = "Roll",
		title = "ROLL FOR A NEW LOOK",
		text = "Roll for a new look! Every 50 shells is a roll, and here are enough for your first",
		goal = 1,
		event = "rolled",
		point = "Roll",
		grant = "roll",
		controls = {
			{ keys = "R", pad = "D-PAD ▼", touch = "ROLL", does = "roll" },
		},
	},
	{
		id = "Wrap",
		title = "USE A KELP WRAP",
		text = "Health never comes back on its own. Use your Kelp Wrap from the item bar to heal",
		goal = 1,
		event = "item",
		point = "Wrap",
		grant = "wrap",
		controls = {
			{ keys = "H or 1", pad = "LB", touch = "TAP IT", does = "use a Kelp Wrap" },
			{ keys = "G", pad = "HOLD LB", touch = "ITEMS", does = "item wheel" },
		},
	},
	{
		id = "Index",
		title = "OPEN THE INDEX",
		text = "Open the INDEX. Its NEXT FOR YOU always shows what to do next",
		goal = 1,
		event = "index",
		point = "Index",
		controls = {
			{ keys = "I", pad = "D-PAD →", touch = "INDEX", does = "open the Index" },
		},
	},
	{
		id = "Wheel",
		title = "SPIN THE TREASURE WHEEL",
		text = "Swim out to the plaza and spin the Treasure Wheel: here's a free spin! A new one comes every 4 hours",
		goal = 1,
		event = "spun",
		guide = "wheel",
		grant = "spin",
		controls = {
			{ keys = "E", pad = "Y", touch = "SPIN", does = "spin at the red button" },
		},
	},
}

-- The Haul step's target: a Haul worth this many levels once banked, from the
-- fish's banked mass (1.05 kg for a LV 1 Nibbler, 1.3 kg at LV 3): a new fish's full
-- Haul (Tuning `growth` `cap`: 5 levels, every Haul), so the step ends at MAX
-- SIZE and the bank takes the Nibbler from LV 1 to 6 (TutorialService stops it at a
-- full Haul for a fish that banked part of its first dive past LV 3). With the Haul
-- rate at LV 1 (Tuning `growth` `rate`, 0.068 since 2026-10-19; it was the whole kg)
-- the Eat and Shells steps' snacking fills ~10–25% of it, so this step is a minute or
-- so of hunting in the Kelp, not done on arrival (PC 2026-10-19: at the whole kg the
-- Haul was full before the step showed)
local HAUL_LEVELS = 5
local function haulTarget(banked: number): number
	return math.max(banked, Tuning.size.startMass) * (Tuning.size.levelGrowth ^ HAUL_LEVELS - 1)
end

-- The step list's version, stamped on the save (`tutorial.v`)
local VERSION = 3

-- Older saves' step lists, by the version stamped on them (0: none, the list before
-- 2026-10-18, and a brand-new save), so one made under an older list carries on in
-- this one (TutorialService `migrate`)
local OLD_LISTS: { [number]: { string } } = {
	[0] = { "LeaveHub", "Eat", "Bank", "Shells", "Level" },
	[2] = { "LeaveHub", "Eat", "Shells", "Haul", "Bank", "Wheel", "Roll", "Wrap", "Index" },
}

export type Save = { step: number, progress: number, done: boolean, v: number? }

-- Where a save from an older list carries on in this one: the first step here it
-- hadn't done there (a step done ahead of its new place comes round again: one at the
-- old Roll spins the wheel twice), and whether its progress carries over (the same
-- step). A save already on this list stays where it is.
local function carryOn(save: Save): (number, boolean)
	if save.v == VERSION then
		return save.step, true
	end
	local old = OLD_LISTS[save.v or 0] or OLD_LISTS[0]
	local done: { [string]: boolean } = {}
	for i = 1, math.min(save.step - 1, #old) do
		done[old[i]] = true
	end
	for index, step in steps do
		if not done[step.id] then
			return index, step.id == old[save.step]
		end
	end
	return #steps + 1, false
end

-- The step a save is on (nil once the tutorial is done), read through `carryOn`, so
-- it's right before TutorialService has moved an older save onto this list
local function current(save: Save): Step?
	if save.done then
		return nil
	end
	local index = carryOn(save)
	return steps[index]
end

return {
	steps = steps,
	-- The step list's version, stamped on the save (TutorialService maps older saves'
	-- step numbers onto this list once, by `carryOn`)
	version = VERSION,
	carryOn = carryOn,
	current = current,
	-- Whether a fish on this save starts out in the sea (its step's `outside`)
	outside = function(save: Save): boolean
		local step = current(save)
		return step ~= nil and step.outside == true
	end,
	haulLevels = HAUL_LEVELS,
	haulTarget = haulTarget,
	-- For finishing: enough shells for a first roll and some coral (the 'Cuda is
	-- earned now, Config/Species)
	reward = { shells = 50, coral = 500 },
	-- Tips on the loading wash between the hub and a den (DenDoorController), one at
	-- a time (owner, 2026-10-17: "Needs more direction for players starting out")
	tips = {
		"Swim into anything under about two thirds your size to swallow it. Other players are never swallowed: BITE them down. Higher levels bite harder.",
		"Your Haul only counts once it's banked in your den's pool. Get eaten first and it's gone.",
		"Every 50 shells is a roll for a new skin. Golden shells in the Trench are worth 5.",
		"Bigger fish are worth far more. Grow, then push into the deeper biomes.",
		"Land bites to fill your special meter. Every fish has its own special attack.",
		"The INDEX (on the HUD) shows how to get every skin, part, variant and trail.",
		"Your Nibbler at LV 15 plus Kelp Shallows DNA unlocks the 'Cuda in the FISH menu.",
		"Sparkling fish are rare: 15 Golden fish of 5 different kinds unlock the Golden skin for every fish.",
		"Kelp Wraps heal you (H). Health never comes back on its own.",
		"Too deep too soon and the pressure crushes you. Each band of depth needs a higher level.",
		"Small fish can school up: bite a big one together and your mass counts as one.",
		"Your den's Coral Garden grows coral and shells while you're away.",
		"The Tide Pass gives skins for every fish, boost trails and more just for playing.",
	} :: { string },
}
