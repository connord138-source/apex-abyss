--!strict
-- Weekly leaderboards (owner, 2026-10-10; LeaderboardService). Four boards, reset
-- every Monday 00:00 UTC: this server's live and the whole game's top 50. The top
-- 100 of each board earn a title when they next join (kept for good). Best Dens
-- (owner, 2026-10-28: den hearts, HeartService) also has a top-3 title, and its top 3
-- wear a gold frame on their den's signs the next week.
export type Board = {
	id: string,
	name: string,
	unit: string,
	blurb: string,
	best: boolean?, -- the week's best single value, not a running total
	titles: { string }, -- for ranks 1, top 10 and top 100 (`ranks`), or the board's own `ranks`
	ranks: { number }?, -- its own title ranks (each a "top N"), when not the usual 1 / 10 / 100
	frame: number?, -- the week's top N wear a gold frame on their den's signs the next week (HeartService)
}

local boards: { Board } = {
	{
		id = "RareCatches",
		name = "Rare Catches",
		unit = "pts",
		blurb = "Silver 0.2 · Golden 1 · Glowing 5 · Crystal 25 · Prism 100 · Catch of the Week +50",
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
	{
		id = "BestDens",
		name = "Best Dens",
		unit = "hearts",
		blurb = "Hearts from visitors this week",
		ranks = { 1, 3, 10, 100 },
		titles = { "Best Den", "Top 3 Den", "Top 10 Den", "Top 100 Den" },
		frame = 3,
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
