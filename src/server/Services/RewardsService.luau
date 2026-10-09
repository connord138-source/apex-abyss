--!strict
-- Free rewards that bring players back:
--
--  * The daily login streak (Config/Daily; owner, 2026-10-09): one claim a UTC day
--    from the DAILY panel (it opens by itself on joining when there's a claim). The
--    day after the last claim moves the streak on; a missed day starts it again at
--    Day 1. The seven days loop, and each finished week adds a bonus.
--  * The Roblox group perk: joining the group pays shells once (and members earn a
--    little more coral, EconomyService.earnCoral). Off while the group id is 0.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local HuntService = require(script.Parent.HuntService)
local MonetizationService = require(script.Parent.MonetizationService)
local StateService = require(script.Parent.StateService)
local TreasureService = require(script.Parent.TreasureService)

type PlayerData = DataService.PlayerData

local Daily = Config.Daily
local group = Config.Monetization.tuning.group

local RewardsService = {}

-- Whether each player had a claim waiting when last sent (a new UTC day flips it)
local lastClaimable: { [Player]: boolean } = {}

-- The streak a claim today would make, and whether one is waiting
local function nextStreak(data: PlayerData, today: number): (number, boolean)
	local daily = data.daily
	if daily.day >= today then
		return daily.streak, false
	end
	return if daily.day == today - 1 then daily.streak + 1 else 1, true
end

-- The ladder's day for a streak (1..7) and that week's bonus multiplier
function RewardsService.dayOf(streak: number): (number, number)
	local length = #Daily.days
	local weeks = math.min((math.max(streak, 1) - 1) // length, Daily.maxWeeks)
	return (math.max(streak, 1) - 1) % length + 1, 1 + Daily.weekBonus * weeks
end

local function claim(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local today = EconomyService.today()
	local streak, waiting = nextStreak(data, today)
	if not waiting then
		Net.notify(player, "Today's reward is claimed. Come back tomorrow!", "info")
		return
	end
	local day, bonus = RewardsService.dayOf(streak)
	local reward = Daily.days[day]
	local got: { string } = {}
	if reward.coral then
		local coral = math.floor(reward.coral * bonus + 0.5)
		EconomyService.addCoral(player, coral)
		table.insert(got, `{Format.number(coral)} coral`)
	end
	if reward.shells then
		local shells = math.floor(reward.shells * bonus + 0.5)
		EconomyService.addShells(player, shells)
		table.insert(got, `{Format.number(shells)} shells`)
	end
	if reward.wraps then
		HuntService.giveWrap(player, reward.wraps)
		table.insert(got, `{reward.wraps} Kelp Wrap{if reward.wraps == 1 then "" else "s"}`)
	end
	if reward.charms then
		for id, count in reward.charms do
			data.charms[id] = (data.charms[id] or 0) + count
			local charm = Config.Shop.charmsById[id]
			table.insert(got, `{count} {if charm then charm.name else id}`)
		end
	end
	if reward.map then
		if TreasureService.give(player, reward.map) then
			table.insert(got, "a treasure map")
		else
			-- The satchel is full: coral instead, so the day still pays
			EconomyService.addCoral(player, 500)
			table.insert(got, "500 coral (your satchel was full)")
		end
	end
	data.daily = { day = today, streak = streak, best = math.max(data.daily.best, streak) }
	lastClaimable[player] = false
	DataService.markDirty(player)
	Net.dailyClaimed(player, { streak = streak, day = day, got = got })
	-- The Daily panel shows what was claimed (a toast covered its footer, playtest
	-- 2026-10-09)
end

-- Pays the one-time group reward
local function rewardGroup(player: Player, data: PlayerData)
	if data.groupRewarded then
		return
	end
	data.groupRewarded = true
	EconomyService.addShells(player, group.shells)
	Net.notify(player, `Thanks for joining the group! +{group.shells} Shells`, "rare")
end

function RewardsService.start()
	Net.onRequest("ClaimDaily", claim)
	DataService.loaded:connect(function(player: Player, data: PlayerData)
		local _, waiting = nextStreak(data, EconomyService.today())
		lastClaimable[player] = waiting
		task.spawn(function()
			if MonetizationService.checkGroup(player) and player.Parent == Players then
				rewardGroup(player, data)
				DataService.markDirty(player)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastClaimable[player] = nil
	end)
	-- A new UTC day while someone's online: their panel shows the new claim
	Guard.loop("RewardsService.daily", 30, function()
		local today = EconomyService.today()
		for player, data in DataService.loadedPlayers() do
			local _, waiting = nextStreak(data, today)
			if lastClaimable[player] ~= waiting then
				lastClaimable[player] = waiting
				DataService.markDirty(player)
			end
		end
	end)
	StateService.provide(function(_player, data, state)
		local today = EconomyService.today()
		local streak, waiting = nextStreak(data, today)
		local day, bonus = RewardsService.dayOf(if waiting then streak else math.max(streak, 1))
		state.daily = {
			claimable = waiting,
			streak = streak, -- the streak a claim makes (waiting) or made today
			day = day, -- its place on the ladder (1..7)
			bonus = bonus,
			best = data.daily.best,
			broken = waiting and data.daily.day > 0 and data.daily.day < today - 1,
			nextAt = (today + 1) * 86400, -- the next UTC day
		}
	end)
end

return RewardsService
