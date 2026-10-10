--!strict
-- Weekly leaderboards (owner, 2026-10-10; LeaderboardService). Three boards, reset
-- every Monday 00:00 UTC: this server's live and the whole game's top 50. The top
-- 100 of each board earn a title when they next join (kept for good).
export type Board = {
	id: string,
	name: string,
	unit: string,
	blurb: string,
	best: boolean?, -- the week's best single value, not a running total
	titles: { string }, -- for ranks 1, top 10 and top 100 (`ranks`)
}

local boards: { Board } = {
	{
		id = "RareCatches",
		name = "Rare Catches",
		unit = "pts",
		blurb = "Golden 1 · Glowing 5 · Crystal 25 · Prism 100 · Catch of the Week +50",
		titles = { "Rarest Catch", "Top 10 Angler", "Top 100 Angler" },
	},
	{
		id = "BiggestHaul",
		name = "Biggest Haul",
		unit = "kg",
		blurb = "Your biggest single Haul banked this week",
		best = true,
		titles = { "Biggest Haul", "Top 10 Hauler", "Top 100 Hauler" },
	},
	{
		id = "BossDamage",
		name = "Boss Damage",
		unit = "dmg",
		blurb = "Damage dealt to world bosses this week",
		titles = { "Boss Breaker", "Top 10 Boss Hunter", "Top 100 Boss Hunter" },
	},
}

local byId: { [string]: Board } = {}
for _, board in boards do
	byId[board.id] = board
end

return {
	boards = boards,
	byId = byId,
	ranks = { 1, 10, 100 },
	show = 50, -- rows of the global board
	readEvery = 120, -- seconds between reads of the global boards
	writeEvery = 60, -- seconds between a player's score writes (and on leaving)
	store = "Weekly_v1", -- the OrderedDataStores are <store>_<board>_<week>
}
