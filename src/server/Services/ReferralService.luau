--!strict
-- Friend invites (Config/Social referral; owner, 2026-11-03), on Roblox's friend
-- referral system: a player who joins from someone's invite has that inviter's user
-- id in `Player:GetJoinData().ReferredByPlayerId`.
--
--  * A new player from an invite (no bank yet, tutorial not done, never invited
--    before) gets a welcome gift and is told their friend gets a reward once they
--    finish the tutorial. Someone who had already played gets nothing.
--  * When they finish it, the inviter is credited once for them, online or not: a
--    record per inviter in a DataStore (each friend counted once), paid out the
--    next time the inviter is in a server (told by MessagingService if they're in
--    another one now, and by a notification if they aren't playing).
--  * Paid for the first `rewarded` friends; the title at `title.friends`.
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local NotifyService = require(script.Parent.NotifyService)
local RewardsService = require(script.Parent.RewardsService)
local StateService = require(script.Parent.StateService)

type PlayerData = DataService.PlayerData

local tune = Config.Social.referral

local TOPIC = "ApexReferral"
local CLAIM_EVERY = 300 -- seconds: online inviters look for credit (if a message was missed)
local NUDGE_AFTER = 40 -- seconds after the tutorial: a line about inviting friends

local store =
	DataStoreService:GetDataStore(if Timing.isStudio() then "Referrals_Studio_v1" else "Referrals_v1")

-- An inviter's record: the friends counted (user id → true), how many are waiting
-- to be paid, and the last one's name
type Record = { friends: { [string]: boolean }, waiting: number, last: string? }

local ReferralService = {}

local claiming: { [Player]: boolean } = {}

local function nameOf(userId: number): string
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	return if ok and typeof(name) == "string" then name else "Your friend"
end

-- Pays `count` friends' rewards to an inviter in this server
local function pay(player: Player, data: PlayerData, count: number, last: string?)
	local got: { string } = {}
	for _ = 1, count do
		data.referral.friends += 1
		if data.referral.friends <= tune.rewarded then
			for _, line in RewardsService.grant(player, data, tune.inviter) do
				table.insert(got, line)
			end
		end
		if data.referral.friends == tune.title.friends then
			for _, line in RewardsService.grant(player, data, { title = tune.title.title }) do
				table.insert(got, line)
			end
		end
	end
	DataService.markDirty(player)
	local who = if count == 1 and last then last else `{count} friends you invited`
	local line = if #got > 0
		then `{who} finished the tutorial from your invite! +{table.concat(got, ", ")}`
		else `{who} finished the tutorial from your invite! Thanks for bringing them`
	Net.notify(player, line, "rare")
	Events.invited:fire(player)
end

-- Takes any credit waiting for this player (as an inviter) and pays it
function ReferralService.claim(player: Player)
	if claiming[player] then
		return
	end
	claiming[player] = true
	local key = tostring(player.UserId)
	local taken, last = 0, nil
	local ok, problem = pcall(store.UpdateAsync, store, key, function(old: any): any
		taken, last = 0, nil
		if typeof(old) ~= "table" or (old.waiting or 0) <= 0 then
			return nil
		end
		taken, last = old.waiting, old.last
		old.waiting = 0
		return old
	end)
	local data = DataService.get(player)
	if ok and taken > 0 then
		if data and player.Parent == Players then
			pay(player, data, taken, last)
		else
			-- Gone meanwhile: put it back for next time
			pcall(store.UpdateAsync, store, key, function(old: any): any
				local record = if typeof(old) == "table" then old else { friends = {}, waiting = 0 }
				record.waiting = (record.waiting or 0) + taken
				return record
			end)
		end
	elseif not ok then
		warn(`[Referral] couldn't read {player.Name}'s invites: {problem}`)
	end
	claiming[player] = nil
end

-- A friend this inviter brought finished the tutorial: count them (once) for the
-- inviter, wherever the inviter is
local function credit(inviterId: number, friend: Player)
	local friendKey = tostring(friend.UserId)
	local counted = false
	local ok, problem = pcall(store.UpdateAsync, store, tostring(inviterId), function(old: any): any
		counted = false
		local record: Record = if typeof(old) == "table" then old else { friends = {}, waiting = 0 }
		record.friends = record.friends or {}
		if record.friends[friendKey] then
			return nil
		end
		record.friends[friendKey] = true
		record.waiting = (record.waiting or 0) + 1
		record.last = friend.DisplayName
		counted = true
		return record
	end)
	if not ok then
		warn(`[Referral] couldn't credit {inviterId} for {friend.Name}: {problem}`)
		return
	end
	if not counted then
		return
	end
	local inviter = Players:GetPlayerByUserId(inviterId)
	if inviter and DataService.get(inviter) then
		ReferralService.claim(inviter)
		return
	end
	-- Another server, or not playing: tell both ways (the notification is dropped by
	-- Roblox for someone who hasn't allowed them)
	pcall(MessagingService.PublishAsync, MessagingService, TOPIC, inviterId)
	NotifyService.send(inviterId, "friend", { friend = friend.DisplayName })
end

-- A player joined from someone's invite (`anyway`: the admin test, for a save that
-- has played)
function ReferralService.arrived(player: Player, data: PlayerData, by: number, anyway: boolean?): boolean
	if by <= 0 or by == player.UserId or data.referral.by ~= 0 then
		return false
	end
	-- Only new players count (a rejoin through a link isn't a new friend)
	if not anyway and (data.tutorial.done or data.stats.banks > 0) then
		return false
	end
	data.referral.by = by
	local got = RewardsService.grant(player, data, tune.invitee)
	DataService.markDirty(player)
	local name = nameOf(by)
	Net.notify(
		player,
		`Welcome! {name} invited you: +{table.concat(got, ", ")}. Finish the tutorial and {name} gets a reward too`,
		"rare"
	)
	return true
end

-- The tutorial finished: credit whoever invited them (once), and point out the
-- invite a little later (after the tutorial's own messages)
local function finished(player: Player)
	local data = DataService.get(player)
	task.delay(NUDGE_AFTER, function()
		local now = DataService.get(player)
		if now and player.Parent == Players and now.referral.friends == 0 then
			Net.notify(
				player,
				"Invite friends from the Shop or POD: you get a reward when they finish the tutorial",
				"info"
			)
		end
	end)
	if data == nil or data.referral.by == 0 or data.referral.credited then
		return
	end
	data.referral.credited = true
	DataService.markDirty(player)
	credit(data.referral.by, player)
end

function ReferralService.start()
	DataService.loaded:connect(function(player: Player, data: PlayerData)
		task.spawn(Guard.run, "ReferralService.join", function()
			local ok, join = pcall(player.GetJoinData, player)
			local by = if ok and typeof(join) == "table" then join.ReferredByPlayerId else nil
			if typeof(by) == "number" then
				ReferralService.arrived(player, data, by)
			end
			ReferralService.claim(player)
		end)
	end)
	Events.tutorialDone:connect(function(player: Player)
		task.spawn(Guard.run, "ReferralService.finished", finished, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		claiming[player] = nil
	end)
	task.spawn(function()
		local ok, problem = pcall(
			MessagingService.SubscribeAsync,
			MessagingService,
			TOPIC,
			function(message: any)
				local userId = tonumber(message.Data)
				local player = if userId then Players:GetPlayerByUserId(userId) else nil
				if player and DataService.get(player) then
					Guard.run("ReferralService.message", ReferralService.claim, player)
				end
			end
		)
		if not ok then
			warn(`[Referral] no cross-server messages: {problem}`)
		end
	end)
	Guard.loop("ReferralService.claim", CLAIM_EVERY, function()
		for _, player in Players:GetPlayers() do
			if DataService.get(player) then
				task.spawn(Guard.run, "ReferralService.claim", ReferralService.claim, player)
			end
		end
	end)
	StateService.provide(function(_player, data, state)
		state.referral = { friends = data.referral.friends, by = data.referral.by ~= 0 }
	end)
end

-- Admin testing: as if this player had just joined from `by`'s invite (even on a
-- save that has played); finishing the tutorial then credits `by`
function ReferralService.testArrive(player: Player, by: number): string
	local data = DataService.get(player)
	if data == nil then
		return "No data"
	end
	if not ReferralService.arrived(player, data, by, true) then
		return "Not counted: already invited (Invites: reset first), or that's your own id"
	end
	return `{player.Name} arrived from {by}'s invite: welcome gift paid; finish the tutorial to credit {by}`
end

function ReferralService.testCredit(player: Player, friends: number): string
	local data = DataService.get(player)
	if data == nil then
		return "No data"
	end
	pay(player, data, math.clamp(friends, 1, 20), nil)
	return `{player.Name}: {friends} invited friend(s) paid, {data.referral.friends} in all`
end

-- Admin testing: forget this player's invite state (and their record as an inviter)
function ReferralService.testReset(player: Player): string
	local data = DataService.get(player)
	if data == nil then
		return "No data"
	end
	data.referral = { by = 0, credited = false, friends = 0 }
	DataService.markDirty(player)
	pcall(store.RemoveAsync, store, tostring(player.UserId))
	return `{player.Name}: invites reset`
end

return ReferralService
