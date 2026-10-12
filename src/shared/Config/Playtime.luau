--!strict
-- Playtime gifts (PlaytimeService; owner, 2026-10-12: "monetizable assets that pay
-- based on play time as well with rewards"). Roblox's Creator Rewards pay out when a
-- paying player spends ten minutes or more in the game each day, so the ladder
-- rewards the first minutes most and then keeps going: a gift every few minutes of
-- play today, counted from midnight UTC, claimed from the DAILY panel (the DAILY
-- button counts down to the next and lights up when one waits). Premium members'
-- coral and shells are ×`premiumBonus` (Config/Monetization `premium`). Every gift
-- adds Tide Pass XP too.
local Rewards = require(script.Parent.Rewards)

export type Gift = Rewards.Reward & { minutes: number }

local gifts: { Gift } = {
	{ minutes = 5, coral = 150, xp = 40 },
	{ minutes = 10, shells = 25, xp = 80 },
	{ minutes = 15, coral = 300, wraps = 1, xp = 80 },
	{ minutes = 25, shells = 40, spins = 1, xp = 120 },
	{ minutes = 40, coral = 600, wraps = 1, xp = 160 },
	{ minutes = 60, coral = 1000, shells = 75, spins = 1, xp = 250, big = true },
	{ minutes = 90, coral = 2000, map = "Weathered", xp = 300 },
}

return {
	gifts = gifts,
	tick = 5, -- seconds between the server counting play
}
