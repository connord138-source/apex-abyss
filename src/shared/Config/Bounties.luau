--!strict
-- Daily bounties (owner, 2026-10-10: the "pull back element"; BountyService). Every
-- player gets three a UTC day, drawn from this pool (different kinds, within their
-- fish's level), and finishing all three opens the Bounty Chest. Progress counts on
-- its own and pays the moment a bounty is done.
export type Reward = {
	coral: number?,
	shells: number?,
	wraps: number?,
	charms: { [string]: number }?, -- Config/Shop charm id → count
	map: string?, -- a Config/Treasure tier
	spins: number?, -- Treasure Wheel spins (Config/Wheel)
}

export type Bounty = {
	id: string,
	-- catch: rare fish of `rarity` or rarer · eat: prey fish · bite: bites on AI
	-- hunters · boss: bites on a world boss · banks: Hauls banked · shells: shells
	-- picked up · tide: prey eaten while a tide (not Calm Waters) is up · treasure:
	-- chests dug up
	kind: string,
	rarity: string?,
	count: number,
	text: string, -- {n} is the count
	minLevel: number?, -- the fish's level when the day's bounties are drawn
	needsMap: boolean?, -- only for a player holding a treasure map
	reward: Reward,
}

local pool: { Bounty } = {
	{
		id = "Golden3",
		kind = "catch",
		rarity = "Golden",
		count = 3,
		text = "Catch {n} Golden fish",
		reward = { coral = 350 },
	},
	{
		id = "Golden8",
		kind = "catch",
		rarity = "Golden",
		count = 8,
		text = "Catch {n} Golden fish",
		minLevel = 15,
		reward = { coral = 700, shells = 20 },
	},
	{
		id = "Glowing1",
		kind = "catch",
		rarity = "Glowing",
		count = 1,
		text = "Catch a Glowing fish",
		reward = { shells = 40 },
	},
	{
		id = "Glowing3",
		kind = "catch",
		rarity = "Glowing",
		count = 3,
		text = "Catch {n} Glowing fish",
		minLevel = 20,
		reward = { shells = 80, charms = { Lucky = 1 } },
	},
	{ id = "Eat60", kind = "eat", count = 60, text = "Eat {n} fish", reward = { coral = 250 } },
	{
		id = "Eat150",
		kind = "eat",
		count = 150,
		text = "Eat {n} fish",
		minLevel = 10,
		reward = { coral = 500, shells = 20 },
	},
	{
		id = "Bite5",
		kind = "bite",
		count = 5,
		text = "Bite AI hunters {n} times",
		minLevel = 8,
		reward = { shells = 40 },
	},
	{
		id = "Boss10",
		kind = "boss",
		count = 10,
		text = "Bite a world boss {n} times",
		minLevel = 30,
		reward = { shells = 80, wraps = 1 },
	},
	{
		id = "Banks2",
		kind = "banks",
		count = 2,
		text = "Bank {n} Hauls at your den",
		reward = { coral = 300 },
	},
	{
		id = "Banks4",
		kind = "banks",
		count = 4,
		text = "Bank {n} Hauls at your den",
		minLevel = 10,
		reward = { coral = 600 },
	},
	{ id = "Shells25", kind = "shells", count = 25, text = "Pick up {n} shells", reward = { coral = 300 } },
	{
		id = "Tide30",
		kind = "tide",
		count = 30,
		text = "Eat {n} fish while a tide is up",
		reward = { map = "Weathered" },
	},
	{
		id = "Treasure1",
		kind = "treasure",
		count = 1,
		text = "Dig up a treasure chest",
		needsMap = true,
		reward = { coral = 600, shells = 20 },
	},
}

local byId: { [string]: Bounty } = {}
for _, bounty in pool do
	byId[bounty.id] = bounty
end

return {
	pool = pool,
	byId = byId,
	perDay = 3,
	chest = { coral = 1000, shells = 50, charms = { Lucky = 1 }, spins = 1 } :: Reward,
}
