--!strict
-- Weekly leaderboards (Config/Leaderboards; owner, 2026-10-10). Scores live in each
-- player's save for the week (Weekly.record): rare-catch points (Config/Catch
-- `points`, the Catch of the Week's extra), their biggest single Haul banked, and
-- the damage they dealt to world bosses. Every `writeEvery` seconds (and when they
-- leave) a changed score goes to an OrderedDataStore per board per week, and every
-- `readEvery` seconds the top `show` of each come back for the whole server. The
-- server's own board is live from its players. A player who made last week's top
-- 100 gets that board's title when they next join.
--
-- Studio without API access (and any DataStore error) falls back to this server's
-- players, so nothing breaks.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Catch = require(ReplicatedStorage.Shared.Catch)
local Tides = require(ReplicatedStorage.Shared.Tides)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local Weekly = require(script.Parent.Parent.Weekly)
local DataService = require(script.Parent.DataService)

type Row = { userId: number, name: string, score: number }

local Boards = Config.Leaderboards
local CatchConfig = Config.Catch

local LeaderboardService = {}

local global: { [string]: { Row } } = {} -- board id → the game's top rows, this week
local readWeek = -1
local dirty: { [Player]: boolean } = {}
local names: { [number]: string } = {}
local lastWeek: { [string]: { [number]: number }? } = {} -- board id → userId → rank, last week
-- False once DataStores have failed, and from the start in Studio: a published place's
-- Studio session logged DataStore errors there with API access off (playtest
-- 2026-10-10), and Studio's boards show this server anyway
local storeOk = not RunService:IsStudio()

local function storeFor(boardId: string, week: number): OrderedDataStore?
	if not storeOk then
		return nil
	end
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(`{Boards.store}_{boardId}_{week}`)
	end)
	return if ok then store else nil
end

local function nameOf(userId: number): string
	local known = names[userId]
	if known then
		return known
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = if ok and typeof(name) == "string" then name else "Player"
	return names[userId]
end

local function add(player: Player, boardId: string, amount: number, best: boolean?)
	local data = DataService.get(player)
	if data == nil or amount <= 0 then
		return
	end
	local scores = Weekly.record(data).scores
	local before = scores[boardId] or 0
	scores[boardId] = if best then math.max(before, amount) else before + amount
	if scores[boardId] ~= before then
		dirty[player] = true
	end
end

local function write(player: Player)
	dirty[player] = nil
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local record = Weekly.record(data)
	for _, board in Boards.boards do
		local score = record.scores[board.id]
		local store = storeFor(board.id, record.week)
		if score and score > 0 and store then
			local ok = pcall(function()
				store:SetAsync(tostring(player.UserId), math.floor(score))
			end)
			if not ok then
				storeOk = false
				return
			end
		end
	end
end

local function top(store: OrderedDataStore, count: number): { { key: string, value: number } }?
	local ok, result = pcall(function()
		local pages = store:GetSortedAsync(false, count)
		return pages:GetCurrentPage()
	end)
	if not ok then
		storeOk = false
		return nil
	end
	return result
end

local function read()
	local week = Tides.week(Timing.unix())
	for _, board in Boards.boards do
		local store = storeFor(board.id, week)
		local page = if store then top(store, Boards.show) else nil
		if page then
			local rows: { Row } = {}
			for _, entry in page do
				local userId = tonumber(entry.key)
				if userId then
					table.insert(rows, { userId = userId, name = nameOf(userId), score = entry.value })
				end
			end
			global[board.id] = rows
		end
	end
	readWeek = week
end

-- This server's players on a board, best first
local function serverRows(boardId: string): { Row }
	local rows: { Row } = {}
	local week = Tides.week(Timing.unix())
	for player, data in DataService.loadedPlayers() do
		local score = if data.weekly.week == week then data.weekly.scores[boardId] or 0 else 0
		if score > 0 then
			table.insert(rows, { userId = player.UserId, name = player.DisplayName, score = score })
		end
	end
	table.sort(rows, function(a, b)
		return a.score > b.score
	end)
	return rows
end

-- Last week's titles for a player who made a top 100 (checked once a week each)
local function checkTitles(player: Player, data: DataService.PlayerData)
	local week = Tides.week(Timing.unix())
	if data.lbChecked >= week then
		return
	end
	data.lbChecked = week
	for _, board in Boards.boards do
		local ranks = lastWeek[board.id]
		if ranks == nil then
			ranks = {}
			local store = storeFor(board.id, week - 1)
			local page: { { key: string, value: number } } = if store
				then top(store, Boards.ranks[#Boards.ranks]) or {}
				else {}
			for i, entry in page do
				local userId = tonumber(entry.key)
				if userId then
					(ranks :: { [number]: number })[userId] = i
				end
			end
			lastWeek[board.id] = ranks
		end
		local rank = (ranks :: { [number]: number })[player.UserId]
		if rank then
			for i, limit in Boards.ranks do
				if rank <= limit then
					local title = board.titles[i]
					if title and not data.titles[title] then
						data.titles[title] = true
						Net.notify(
							player,
							`Last week you ranked #{rank} in {board.name}: the "{title}" title is yours!`,
							"rare"
						)
					end
					break
				end
			end
		end
	end
	DataService.markDirty(player)
end

-- Testing (the admin panel): add to a player's score on a board this week
function LeaderboardService.add(player: Player, boardId: string, amount: number)
	if Boards.byId[boardId] then
		add(player, boardId, amount, Boards.byId[boardId].best)
	end
end

function LeaderboardService.start()
	Events.caught:connect(function(player: Player, preyId: string, rarityId: string)
		local def = CatchConfig.byId[rarityId]
		local points = if def then def.points else 0
		local featured = Catch.weekly(Timing.unix())
		if featured and featured.prey == preyId and featured.rarity == rarityId then
			points += CatchConfig.weekly.points
		end
		add(player, "RareCatches", points)
	end)
	Events.banked:connect(function(player: Player, amount: number)
		add(player, "BiggestHaul", amount, true)
	end)
	Events.bossDamage:connect(function(player: Player, amount: number)
		add(player, "BossDamage", amount)
	end)
	DataService.loaded:connect(function(player: Player, data: DataService.PlayerData)
		task.spawn(checkTitles, player, data)
	end)
	DataService.releasing:connect(function(player: Player)
		if dirty[player] then
			write(player)
		end
	end)
	Guard.loop("LeaderboardService.write", Boards.writeEvery, function()
		for player in dirty do
			write(player)
		end
	end)
	Guard.loop("LeaderboardService.read", Boards.readEvery, read)
	Net.onGetBoards(function(player: Player): { [string]: any }
		local unix = Timing.unix()
		local week = Tides.week(unix)
		local data = DataService.get(player)
		local boards: { [string]: any } = {}
		for _, board in Boards.boards do
			local server = serverRows(board.id)
			local rows = if readWeek == week and storeOk then global[board.id] or {} else server
			boards[board.id] = {
				global = rows,
				server = server,
				mine = if data and data.weekly.week == week then data.weekly.scores[board.id] or 0 else 0,
				live = storeOk and readWeek == week,
			}
		end
		return { boards = boards, endsAt = Tides.weekStart(week + 1) }
	end)
end

return LeaderboardService
