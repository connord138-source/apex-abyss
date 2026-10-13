--!strict
-- Free rewards that bring players back:
--
--  * The daily login streak (Config/Daily; owner, 2026-10-09): one claim a UTC day
--    from the DAILY panel (it opens by itself on joining when there's a claim). The
--    day after the last claim moves the streak on; a missed day starts it again at
--    Day 1. The seven days loop, and each finished week adds a bonus.
--  * The Roblox group perk: joining the group pays shells once (and members earn a
--    little more coral, EconomyService.earnCoral). Off while the group id is 0.
--  * RewardsService.grant pays out any reward bundle (Shared/Reward): the daily
--    streak, the playtime gifts (PlaytimeService) and the Tide Pass (PassService)
--    all use it, so a new kind of reward is added here once.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Reward = require(ReplicatedStorage.Shared.Reward)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
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

-- Pays a reward bundle out, `bonus` × its coral and shells, and names what was got
-- ("300 coral", "a treasure map"). A skin goes to the fish the player swims as (the
-- per-fish rule); a title is worn at once when none is; a den piece goes into the Build tray.
function RewardsService.grant(
	player: Player,
	data: PlayerData,
	reward: Reward.Reward,
	bonus: number?
): { string }
	local scale = bonus or 1
	local got: { string } = {}
	if reward.skin then
		local shade = Config.Shades.byId[reward.skin]
		local name = if shade then shade.name else reward.skin
		if Progress.grantShade(data, reward.skin) then
			table.insert(got, `the {name} skin ({Progress.species(data).name})`)
		else
			table.insert(got, `the {name} skin (already yours)`)
		end
	end
	if reward.title then
		data.titles[reward.title] = true
		if data.title == "" then
			data.title = reward.title
			local character = player.Character
			if character then
				character:SetAttribute("Title", reward.title)
			end
		end
		table.insert(got, `the "{reward.title}" title`)
	end
	if reward.den then
		-- One more copy in the Build tray (den v2: things are counted, not flagged)
		data.den.items[reward.den] = (data.den.items[reward.den] or 0) + 1
		local item = Config.Dens.itemsById[reward.den]
		table.insert(got, `a {if item then item.name else reward.den} for your den (in your Build tray)`)
	end
	if reward.coral then
		local coral = math.floor(reward.coral * scale + 0.5)
		EconomyService.addCoral(player, coral)
		table.insert(got, `{Format.number(coral)} coral`)
	end
	if reward.shells then
		local shells = math.floor(reward.shells * scale + 0.5)
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
	if reward.spins then
		data.wheel.spins += reward.spins
		table.insert(got, `{reward.spins} wheel spin{if reward.spins == 1 then "" else "s"}`)
	end
	if reward.map then
		if TreasureService.give(player, reward.map) then
			table.insert(got, "a treasure map")
		else
			-- The satchel is full: coral instead, so the reward still pays
			EconomyService.addCoral(player, 500)
			table.insert(got, "500 coral (your satchel was full)")
		end
	end
	if reward.xp then
		Events.passXp:fire(player, reward.xp, "reward")
		table.insert(got, `{Format.number(reward.xp)} pass XP`)
	end
	DataService.markDirty(player)
	return got
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
	local got = RewardsService.grant(player, data, reward, bonus)
	-- A claim is a day played: Tide Pass XP (Config/Pass xp.daily)
	Events.passXp:fire(player, Config.Pass.xp.daily, "daily")
	table.insert(got, `{Config.Pass.xp.daily} pass XP`)
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
