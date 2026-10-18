--!strict
-- The Tide Pass (owner, 2026-10-12: a monetizable asset that pays on playtime;
-- Config/Pass). Seasons run on the Tide Clock's week numbers (Shared/Tides.week),
-- `weeks` each. Play earns XP (banking, catches, bounties, bosses, treasure, the
-- daily streak and the playtime gifts, through Events), every `xpPerTier` XP is a
-- tier, and each tier has a free reward and a Deep Pass reward. The Deep Pass is a
-- developer product (Config/Monetization `DeepPass`) bought for the season from the
-- PASS panel; it opens the paid row and earns XP ×`paidXp`. Rewards are claimed from
-- the panel (ClaimPass claims everything unlocked), through RewardsService.grant.
-- When a season ends, whatever a player had unlocked is claimed for them on their
-- next join or tick, and the record starts again for the new season.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Tides = require(ReplicatedStorage.Shared.Tides)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local RewardsService = require(script.Parent.RewardsService)
local StateService = require(script.Parent.StateService)

type PlayerData = DataService.PlayerData

local Pass = Config.Pass

local PassService = {}

-- Which season a Unix time is in (1 = the first), and when it ends
function PassService.seasonAt(unix: number): (number, number)
	local startWeek = Tides.week(Pass.start)
	local index = math.max(0, (Tides.week(unix) - startWeek) // Pass.weeks) + 1
	return index, Tides.weekStart(startWeek + index * Pass.weeks)
end

function PassService.seasonDef(index: number): typeof(Pass.seasons[1])
	return Pass.seasons[(index - 1) % #Pass.seasons + 1]
end

-- The tier `xp` reaches (0 = none yet)
local function tierOf(xp: number): number
	return xp // Pass.xpPerTier
end

local function season(def: typeof(Pass.seasons[1])): number
	return #def.tiers
end

-- Claims every reward unlocked on the rows the player has (the paid row only with
-- the Deep Pass), including the overtide coral past the last tier. Names what was got.
local function claimAll(player: Player, data: PlayerData): { string }
	local def = PassService.seasonDef(data.pass.season)
	local tier = tierOf(data.pass.xp)
	local got: { string } = {}
	local last = season(def)
	while data.pass.claimedFree < math.min(tier, last) do
		data.pass.claimedFree += 1
		local reward = def.tiers[data.pass.claimedFree].free
		if reward then
			for _, line in RewardsService.grant(player, data, reward) do
				table.insert(got, line)
			end
		end
	end
	if data.pass.paid then
		while data.pass.claimedPaid < math.min(tier, last) do
			data.pass.claimedPaid += 1
			local reward = def.tiers[data.pass.claimedPaid].paid
			if reward then
				for _, line in RewardsService.grant(player, data, reward) do
					table.insert(got, line)
				end
			end
		end
	end
	-- Past the last tier: the overtide, counted on the free row
	while data.pass.claimedFree < tier do
		data.pass.claimedFree += 1
		for _, line in RewardsService.grant(player, data, Pass.overtide) do
			table.insert(got, line)
		end
	end
	return got
end

-- How many rewards wait to be claimed
local function waiting(data: PlayerData): number
	local def = PassService.seasonDef(data.pass.season)
	local tier = tierOf(data.pass.xp)
	local count = math.max(0, tier - data.pass.claimedFree)
	if data.pass.paid then
		count += math.max(0, math.min(tier, season(def)) - data.pass.claimedPaid)
	end
	return count
end

-- Moves the record on to the current season, claiming what the old one had unlocked
local function settle(player: Player, data: PlayerData): boolean
	local current = PassService.seasonAt(Timing.now())
	if data.pass.season == current then
		return false
	end
	if data.pass.season > 0 then
		local got = claimAll(player, data)
		if #got > 0 then
			Net.notify(
				player,
				`Season {data.pass.season} of the Tide Pass ended: {table.concat(got, ", ")} were claimed for you`,
				"good"
			)
		end
	end
	data.pass = { season = current, xp = 0, claimedFree = 0, claimedPaid = 0, paid = false }
	return true
end

-- XP for play, ×paidXp with the Deep Pass. Tells the player at each new tier.
function PassService.addXp(player: Player, amount: number, reason: string?)
	local data = DataService.get(player)
	if data == nil or amount <= 0 then
		return
	end
	settle(player, data)
	local scaled = math.floor(amount * (if data.pass.paid then Pass.paidXp else 1) + 0.5)
	local before = tierOf(data.pass.xp)
	data.pass.xp += scaled
	local after = tierOf(data.pass.xp)
	if after > before then
		local def = PassService.seasonDef(data.pass.season)
		local last = season(def)
		Net.notify(
			player,
			if after <= last
				then `TIDE PASS · TIER {after} of {last} reached · open PASS to claim`
				else `TIDE PASS · OVERTIDE · {Pass.overtide.coral or 0} coral waits in PASS`,
			"rare"
		)
	end
	DataService.markDirty(player)
end

local function claim(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	settle(player, data)
	local got = claimAll(player, data)
	if #got == 0 then
		Net.notify(player, "Nothing to claim yet: play on for the next tier", "info")
		return
	end
	DataService.markDirty(player)
	Net.passClaimed(player, { got = got })
end

-- Testing (the admin panel)
function PassService.setPaid(player: Player, paid: boolean)
	local data = DataService.get(player)
	if data then
		settle(player, data)
		data.pass.paid = paid
		DataService.markDirty(player)
	end
end

function PassService.restart(player: Player)
	local data = DataService.get(player)
	if data then
		data.pass = { season = 0, xp = 0, claimedFree = 0, claimedPaid = 0, paid = false }
		settle(player, data)
		DataService.markDirty(player)
	end
end

function PassService.start()
	Net.onRequest("ClaimPass", claim)
	MonetizationService.onProduct(Pass.product, function(player, data)
		settle(player, data)
		data.pass.paid = true
		Net.notify(
			player,
			"Deep Pass bought: the paid row is yours this season, and 20% more pass XP!",
			"rare"
		)
	end)
	DataService.loaded:connect(function(player: Player, data: PlayerData)
		settle(player, data)
	end)
	-- XP for play
	Events.banked:connect(function(player: Player, amount: number, _level: number?, worth: number?)
		-- (the Haul before the Haul rate, so slower growth didn't cut the XP)
		local xp = math.clamp((worth or amount) * Pass.xp.bankPerKg, Pass.xp.bankMin, Pass.xp.bankMax)
		PassService.addXp(player, xp, "bank")
	end)
	Events.caught:connect(function(player: Player, _preyId: string, rarityId: string)
		PassService.addXp(player, Pass.xp.catch[rarityId] or Pass.xp.catch.Normal or 0, "catch")
	end)
	Events.bounty:connect(function(player: Player, kind: string)
		PassService.addXp(player, if kind == "chest" then Pass.xp.chest else Pass.xp.bounty, kind)
	end)
	Events.bossKill:connect(function(player: Player)
		PassService.addXp(player, Pass.xp.boss, "boss")
	end)
	Events.treasure:connect(function(player: Player)
		PassService.addXp(player, Pass.xp.treasure, "treasure")
	end)
	Events.passXp:connect(function(player: Player, amount: number, reason: string?)
		PassService.addXp(player, amount, reason)
	end)
	-- A season turning while players are online
	Guard.loop("PassService.season", 60, function()
		for player, data in DataService.loadedPlayers() do
			if settle(player, data) then
				DataService.markDirty(player)
			end
		end
	end)
	StateService.provide(function(_player, data, state)
		local def = PassService.seasonDef(math.max(data.pass.season, 1))
		local _, endsAt = PassService.seasonAt(Timing.now())
		state.pass = {
			season = data.pass.season,
			name = def.name,
			xp = data.pass.xp,
			tier = tierOf(data.pass.xp),
			per = Pass.xpPerTier,
			tiers = season(def),
			claimedFree = data.pass.claimedFree,
			claimedPaid = data.pass.claimedPaid,
			paid = data.pass.paid,
			waiting = waiting(data),
			endsAt = endsAt,
		}
	end)
end

return PassService
