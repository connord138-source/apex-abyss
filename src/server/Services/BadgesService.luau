--!strict
-- Roblox badges (Config/Social badges; owner, 2026-11-03). Each is measured from the
-- save like an achievement, so what a player did before a badge was made counts on
-- their next visit; it's awarded once (`data.badges`) and Roblox shows its own toast.
-- A badge whose id is still 0, or that's switched off in Creator Hub, is skipped.
-- Other games (Hatch & Snatch) can read these badges to reward Apex Tide players.
local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local AchievementService = require(script.Parent.AchievementService)
local DataService = require(script.Parent.DataService)

type PlayerData = DataService.PlayerData
type Badge = typeof(Config.Social.badges[1])

local RETRY = 60 -- seconds before a failed award is tried again

local BadgesService = {}

-- Badge id → whether it's switched on (looked up once a server; a failed look-up
-- isn't kept, so it's tried again)
local enabled: { [number]: boolean } = {}
local checking: { [Player]: boolean } = {}
local again: { [Player]: boolean } = {}
local lastTry: { [Player]: { [string]: number } } = {}

-- How far along a badge is, from the save
function BadgesService.measure(data: PlayerData, badge: Badge): number
	local measure = badge.measure
	if measure == "joined" then
		return 1
	elseif measure == "tutorial" then
		return if data.tutorial.done then 1 else 0
	elseif measure == "friends" then
		return data.referral.friends
	elseif measure == "apexKills" then
		return data.stats.apexKills or 0
	end
	-- catches, bossKills, level and treasures are measured the way achievements are
	return AchievementService.measure(data, badge :: any)
end

local function isEnabled(id: number): boolean
	local known = enabled[id]
	if known ~= nil then
		return known
	end
	local ok, info = pcall(BadgeService.GetBadgeInfoAsync, BadgeService, id)
	if not ok or typeof(info) ~= "table" then
		return false
	end
	enabled[id] = info.IsEnabled == true
	return enabled[id]
end

-- Awards one badge; true if the player has it now
local function award(player: Player, badge: Badge): boolean
	local ok, result = pcall(BadgeService.AwardBadgeAsync, BadgeService, player.UserId, badge.id)
	if ok and result == true then
		return true
	end
	-- (an award fails for a badge they already have: ask)
	local has, owned = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, badge.id)
	if has and owned == true then
		return true
	end
	if Timing.isStudio() then
		print(
			`[Badges] {player.Name}: {badge.name} not awarded ({if ok then "refused" else tostring(result)})`
		)
	end
	return false
end

-- Awards every badge the player has earned and doesn't have. One check at a time per
-- player (awards wait on Roblox); one asked for meanwhile runs after it.
function BadgesService.check(player: Player)
	if checking[player] then
		again[player] = true
		return
	end
	checking[player] = true
	local ok, problem = pcall(function()
		repeat
			again[player] = nil
			local data = DataService.get(player)
			if data == nil then
				break
			end
			local tries = lastTry[player] or {}
			lastTry[player] = tries
			for _, badge in Config.Social.badges do
				if badge.id == 0 or data.badges[badge.key] or player.Parent ~= Players then
					continue
				end
				if BadgesService.measure(data, badge) < badge.goal then
					continue
				end
				local now = os.clock()
				if now - (tries[badge.key] or -math.huge) < RETRY or not isEnabled(badge.id) then
					continue
				end
				tries[badge.key] = now
				if award(player, badge) and DataService.get(player) == data then
					data.badges[badge.key] = true
					DataService.markDirty(player)
				end
			end
		until not again[player]
	end)
	-- (cleared even after an error, or this player's badges would stop for good)
	checking[player] = nil
	if not ok then
		error(problem, 0)
	end
end

function BadgesService.start()
	local function soon(player: Player)
		task.spawn(Guard.run, "BadgesService.check", BadgesService.check, player)
	end
	-- The welcome badge as they dive in (Roblox's toast would be lost under the
	-- start screen), and anything else they'd earned before badges existed
	Events.dived:connect(soon)
	Events.tutorialDone:connect(soon)
	Events.banked:connect(soon)
	Events.caught:connect(soon)
	Events.treasure:connect(soon)
	Events.bossKill:connect(soon)
	Events.invited:connect(soon)
	Events.atePlayer:connect(soon)
	DataService.loaded:connect(function(player: Player)
		task.delay(30, function()
			if player.Parent then
				soon(player)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		checking[player] = nil
		again[player] = nil
		lastTry[player] = nil
	end)
	Guard.loop("BadgesService", 60, function()
		for _, player in Players:GetPlayers() do
			soon(player)
		end
	end)
end

return BadgesService
