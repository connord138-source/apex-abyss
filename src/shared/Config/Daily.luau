--!strict
-- The daily login streak (DailyService; owner, 2026-10-09: "a daily login streak
-- reward ... to keep players coming back"). One claim a UTC day. Claiming the day
-- after the last claim moves the streak on; missing a day starts it again at Day 1.
-- The seven days loop, and every finished week adds `weekBonus` to the coral and
-- shells (up to `maxWeeks` weeks), so a long streak is worth keeping.
export type Reward = {
	coral: number?,
	shells: number?,
	wraps: number?, -- Kelp Wraps (up to the carry cap)
	charms: { [string]: number }?, -- Config/Shop charm id → count
	map: string?, -- a Config/Treasure tier
	big: boolean?, -- the day the ladder builds to (drawn larger)
}

local days: { Reward } = {
	{ coral = 300 },
	{ shells = 50 },
	{ coral = 600, wraps = 1 },
	{ shells = 100 },
	{ coral = 1000, charms = { Lucky = 1 } },
	{ shells = 150, charms = { SecondChance = 1 } },
	{ coral = 2500, shells = 100, map = "Captain", big = true },
}

return {
	days = days,
	weekBonus = 0.25,
	maxWeeks = 4,
}
