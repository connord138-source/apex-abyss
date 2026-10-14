--!strict
-- Redeem codes (GDD §9, "Later: codes"; built 2026-10-14): typed into the Shop's
-- CODES window, each pays its reward once per player (RewardsService, `data.codes`).
-- Codes are matched without case or spaces. `ends` is a Unix time after which a code
-- stops working (nil: never). Rewards are the shared bundle (Config/Rewards), so
-- never a Robux-only thing and never bite damage; shells are fine (they're earned in
-- play too). Add a code by adding a row; retire one by setting `ends`.
local Rewards = require(script.Parent.Rewards)

export type Code = {
	code: string, -- upper case, no spaces
	reward: Rewards.Reward,
	ends: number?,
	note: string, -- where it was given out (for us; never shown)
}

local list: { Code } = {
	{ code = "APEX", reward = { coral = 1000, shells = 50 }, note = "launch: store page" },
	{ code = "DEEPDIVE", reward = { wraps = 2, spins = 1 }, note = "launch: group shout" },
	{ code = "MEGALODON", reward = { coral = 750, charms = { Lucky = 1 } }, note = "launch: boss trailer" },
	{ code = "NIBBLER", reward = { shells = 100 }, note = "launch: thumbnail" },
}

local byCode: { [string]: Code } = {}
for _, entry in list do
	byCode[entry.code] = entry
end

-- A typed code as it's stored: upper case, letters and digits only
local function normalize(text: string): string
	return (string.upper(text):gsub("[^%w]", ""))
end

return {
	list = list,
	byCode = byCode,
	normalize = normalize,
}
