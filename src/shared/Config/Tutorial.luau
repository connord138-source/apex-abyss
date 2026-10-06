--!strict
-- The first-session tutorial (owner: everyone starts as the Nibbler and is led
-- through upgrading it before other species can be picked). Each step counts one
-- kind of event (TutorialService); finishing unlocks the 'Cuda and species select.
-- Steps for the barracuda and the upgrade tree get added when those systems land.
export type Step = {
	id: string,
	text: string,
	goal: number,
	event: "leftHub" | "ate" | "banked" | "shells" | "level",
	marker: string?, -- what the client points at ("exits", "den")
}

local steps: { Step } = {
	{
		id = "LeaveHub",
		text = "Swim out of the hub through a tunnel or the hole in the roof",
		goal = 1,
		event = "leftHub",
		marker = "exits",
	},
	{
		id = "Eat",
		text = "Eat 10 small fish, shrimp or starfish",
		goal = 10,
		event = "ate",
	},
	{
		id = "Bank",
		text = "Swim home and bank your Haul in your den's glowing pool",
		goal = 1,
		event = "banked",
		marker = "den",
	},
	{
		id = "Shells",
		text = "Pick up 5 shells from the seabed",
		goal = 5,
		event = "shells",
	},
	{
		id = "Level",
		text = "Grow your Nibbler to level 10",
		goal = 10,
		event = "level",
	},
}

return {
	steps = steps,
	-- For finishing: the 'Cuda, enough shells for a first roll, and some coral
	reward = { unlock = "Cuda", shells = 50, coral = 500 },
}
