--!strict
-- Achievements (Config/Achievements): each opens a den furniture set (Config/Dens
-- `sets`), whose pieces are then bought one at a time with coral (DenService).
-- Measured from the save's lifetime tallies, so what a player did before achievements
-- shipped counts; each is marked done once and for good (`data.achievements`), with
-- a banner. Checked when something that could finish one happens, and every half
-- minute for anything else (an admin level, a rejoin).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Size = require(ReplicatedStorage.Shared.Size)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)

type PlayerData = DataService.PlayerData
type Achievement = typeof(Config.Achievements.list[1])

local AchievementService = {}

-- How far along an achievement is, from the save
function AchievementService.measure(data: PlayerData, achievement: Achievement): number
	local measure = achievement.measure
	if measure == "banks" then
		return data.stats.banks
	elseif measure == "catches" then
		local total = 0
		local rarity = achievement.rarity or ""
		for _, byRarity in data.catchLog do
			total += byRarity[rarity] or 0
		end
		return total
	elseif measure == "treasures" then
		return data.treasures.found
	elseif measure == "level" then
		-- The best level any fish has ever reached (kept, so it never goes back down)
		local best = math.max(1, data.stats.bestLevel or 0)
		for _, record in data.species do
			best = math.max(best, Size.level(record.mass))
		end
		if best > (data.stats.bestLevel or 0) then
			data.stats.bestLevel = best
		end
		return best
	elseif measure == "bossKills" then
		return data.stats.bossKills
	end
	return 0
end

-- Whether a den set's pieces are for sale (its achievement done; a set with no
-- achievement is open)
function AchievementService.setOpen(data: PlayerData, setId: string): boolean
	local achievement = Config.Achievements.bySet[setId]
	return achievement == nil or data.achievements[achievement.id] == true
end

-- Marks every finished achievement done, announcing each (`quiet`: just mark)
function AchievementService.check(player: Player, quiet: boolean?)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	for _, achievement in Config.Achievements.list do
		if
			data.achievements[achievement.id]
			or AchievementService.measure(data, achievement) < achievement.goal
		then
			continue
		end
		data.achievements[achievement.id] = true
		DataService.markDirty(player)
		if not quiet then
			local set = Config.Dens.setsById[achievement.set]
			Net.achievement(player, {
				id = achievement.id,
				name = achievement.name,
				blurb = achievement.blurb,
				set = if set then set.name else "",
				tier = if set then set.tier else "Common",
			})
		end
	end
end

-- Admin testing: every achievement done, or none
function AchievementService.setAll(player: Player, done: boolean)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	for _, achievement in Config.Achievements.list do
		if done then
			data.achievements[achievement.id] = true
		else
			data.achievements[achievement.id] = nil
		end
	end
	DataService.markDirty(player)
end

function AchievementService.start()
	local function soon(player: Player)
		task.defer(function()
			Guard.run("AchievementService.check", AchievementService.check, player)
		end)
	end
	Events.banked:connect(soon)
	Events.caught:connect(soon)
	Events.treasure:connect(soon)
	Events.bossKill:connect(soon)
	-- On join, after the start screen (a banner under it would go unseen)
	DataService.loaded:connect(function(player: Player)
		task.delay(25, function()
			if player.Parent then
				Guard.run("AchievementService.check", AchievementService.check, player)
			end
		end)
	end)
	Guard.loop("AchievementService", 30, function()
		for _, player in Players:GetPlayers() do
			Guard.run("AchievementService.check", AchievementService.check, player)
		end
	end)
	StateService.provide(function(_player, data, state)
		local progress: { [string]: number } = {}
		for _, achievement in Config.Achievements.list do
			progress[achievement.id] = if data.achievements[achievement.id]
				then achievement.goal
				else math.min(AchievementService.measure(data, achievement), achievement.goal)
		end
		state.achievements = progress
	end)
end

return AchievementService
