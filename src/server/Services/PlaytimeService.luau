--!strict
-- Playtime gifts (owner, 2026-10-12: "monetizable assets that pay based on play time
-- as well with rewards"; Config/Playtime). Roblox's Creator Rewards pay for each
-- paying player who spends ten minutes or more in the game a day, so the game
-- rewards the minutes themselves: a ladder of gifts for time played today (UTC),
-- claimed one at a time from the DAILY panel. The server counts the time (every
-- `tick` seconds, for every loaded player), tells a player when a gift is ready and
-- pays it out through RewardsService.grant, with Premium's bonus on the coral and
-- shells. Roblox Premium also gets a free Treasure Wheel spin on the first tick of
-- each day (Config/Monetization premium.spins).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MonetizationService = require(script.Parent.MonetizationService)
local RewardsService = require(script.Parent.RewardsService)
local StateService = require(script.Parent.StateService)
local WheelService = require(script.Parent.WheelService)

type PlayerData = DataService.PlayerData

local Playtime = Config.Playtime
local premium = Config.Monetization.tuning.premium

local PlaytimeService = {}

-- Gifts the player has been told about today (a notice once per gift)
local told: { [Player]: number } = {}

-- Starts the day's count again when the UTC day has turned
local function roll(data: PlayerData, today: number): boolean
	if data.playtime.day == today then
		return false
	end
	data.playtime.day = today
	data.playtime.seconds = 0
	data.playtime.claimed = 0
	return true
end

-- How many gifts the player's time today has unlocked
local function unlocked(data: PlayerData): number
	local count = 0
	for _, gift in Playtime.gifts do
		if data.playtime.seconds >= gift.minutes * 60 then
			count += 1
		end
	end
	return count
end

local function bonusFor(player: Player): number
	return if MonetizationService.isPremium(player) then premium.gifts else 1
end

local function claim(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	roll(data, EconomyService.today())
	local index = data.playtime.claimed + 1
	local gift = Playtime.gifts[index]
	if gift == nil then
		Net.notify(player, "Every gift is claimed for today. Tomorrow brings more!", "info")
		return
	end
	if index > unlocked(data) then
		local left = gift.minutes * 60 - data.playtime.seconds
		Net.notify(player, `The next gift is ready in {math.ceil(left / 60)} min`, "info")
		return
	end
	local got = RewardsService.grant(player, data, gift, bonusFor(player))
	data.playtime.claimed = index
	told[player] = math.max(told[player] or 0, index)
	DataService.markDirty(player)
	Net.dailyClaimed(player, { kind = "gift", minutes = gift.minutes, got = got })
end

-- Testing (the admin panel): adds minutes played today, or starts the day again
function PlaytimeService.addMinutes(player: Player, minutes: number)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	roll(data, EconomyService.today())
	data.playtime.seconds = math.max(0, data.playtime.seconds + minutes * 60)
	DataService.markDirty(player)
end

function PlaytimeService.reset(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	data.playtime = { day = 0, seconds = 0, claimed = 0, premiumDay = 0 }
	told[player] = 0
	DataService.markDirty(player)
end

local function tick()
	local today = EconomyService.today()
	for player, data in DataService.loadedPlayers() do
		local rolled = roll(data, today)
		local before = unlocked(data)
		data.playtime.seconds += Playtime.tick
		local now = unlocked(data)
		-- Premium's free spin, on the first tick of each day
		if
			MonetizationService.isPremium(player)
			and data.playtime.premiumDay ~= today
			and premium.spins > 0
		then
			data.playtime.premiumDay = today
			WheelService.give(player, premium.spins)
			Net.notify(
				player,
				`Premium perk: {premium.spins} free wheel spin{if premium.spins == 1 then "" else "s"} today!`,
				"rare"
			)
		end
		if now > data.playtime.claimed and now > (told[player] or 0) then
			told[player] = now
			local gift = Playtime.gifts[now]
			Net.notify(
				player,
				`GIFT READY · {gift.minutes} minutes played · open DAILY to claim it`,
				"good"
			)
			rolled = true
		end
		if rolled or now ~= before then
			DataService.markDirty(player)
		end
	end
end

function PlaytimeService.start()
	Net.onRequest("ClaimGift", claim)
	DataService.loaded:connect(function(_player: Player, data: PlayerData)
		roll(data, EconomyService.today())
	end)
	Players.PlayerRemoving:Connect(function(player)
		told[player] = nil
	end)
	Guard.loop("PlaytimeService.tick", Playtime.tick, tick)
	StateService.provide(function(player, data, state)
		local count = unlocked(data)
		local nextGift = Playtime.gifts[math.max(data.playtime.claimed, count) + 1]
		state.playtime = {
			seconds = data.playtime.seconds,
			claimed = data.playtime.claimed,
			unlocked = count,
			claimable = count > data.playtime.claimed,
			total = #Playtime.gifts,
			-- When the next gift unlocks (server time), for the HUD's countdown
			nextAt = if nextGift
				then workspace:GetServerTimeNow() + nextGift.minutes * 60 - data.playtime.seconds
				else nil,
			bonus = bonusFor(player),
		}
	end)
end

return PlaytimeService
