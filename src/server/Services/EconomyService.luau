--!strict
-- Coral (the currency) and Shells (the roll currency): adding, spending, and
-- sending them to the HUD with everything that depends on them (upgrades,
-- charms, owned cosmetics). Every payout and purchase goes through here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local StateService = require(script.Parent.StateService)

local EconomyService = {}

function EconomyService.addCoral(player: Player, amount: number)
	local data = DataService.get(player)
	if data == nil or amount <= 0 then
		return
	end
	amount = math.floor(amount + 0.5)
	data.coral += amount
	data.stats.coralEarned += amount
	DataService.markDirty(player)
end

-- Coral earned from play (banking, eating players, predators, bosses, the Coral
-- Garden): VIP, Premium and the group perk add their share. Fixed rewards that show
-- their amount up front (rolls, treasure, the daily streak) use addCoral. Returns
-- what was added.
function EconomyService.earnCoral(player: Player, amount: number): number
	if amount <= 0 then
		return 0
	end
	local total = math.floor(amount * MonetizationService.coralMultiplier(player) + 0.5)
	EconomyService.addCoral(player, total)
	return total
end

-- Takes coral if the player has enough; returns whether it did.
function EconomyService.spendCoral(player: Player, amount: number): boolean
	local data = DataService.get(player)
	if data == nil or amount < 0 or data.coral < amount then
		return false
	end
	data.coral -= amount
	DataService.markDirty(player)
	return true
end

function EconomyService.addShells(player: Player, amount: number)
	local data = DataService.get(player)
	if data == nil or amount <= 0 then
		return
	end
	data.shells += amount
	data.stats.shells += amount
	DataService.markDirty(player)
end

-- The UTC day number (for daily limits).
function EconomyService.today(): number
	return math.floor(Timing.now() / 86400)
end

function EconomyService.start()
	-- Shell packs (Robux): shells buy rolls, so they're paid random items (hidden
	-- where restricted, odds shown first; MonetizationService)
	local Tuning = Config.Monetization.tuning
	MonetizationService.onProduct("ShellPouch", function(player, data)
		data.shells += Tuning.shellPouch
		data.stats.shells += Tuning.shellPouch
		Net.notify(player, `+{Tuning.shellPouch} Shells! Thanks for the support.`, "rare")
	end)
	MonetizationService.onProduct("ShellChest", function(player, data)
		data.shells += Tuning.shellChest
		data.stats.shells += Tuning.shellChest
		Net.notify(player, `+{Tuning.shellChest} Shells! Thanks for the support.`, "rare")
	end)
	StateService.provide(function(_player, data, state)
		local perRoll = Config.Rolls.shellsPerRoll
		state.coral = data.coral
		state.shells = data.shells
		state.shellsPerRoll = perRoll
		state.rollsReady = math.floor(data.shells / perRoll)
		state.upgrades = data.upgrades
		state.charms = data.charms
		state.boosts = data.boosts
		state.shades = Progress.shades(data) -- the current fish's (shades are per fish)
		state.otherShades = Progress.otherShades(data)
		state.parts = data.parts
		state.variants = data.variants
		state.equipped = data.equipped
		state.trophies = data.trophies
		state.titles = data.titles
		state.title = data.title
		local trades = data.shellTrades
		local used = if trades.day == EconomyService.today() then trades.count else 0
		state.shellTradesLeft = Config.Shop.shellTrade.perDay - used
	end)
end

return EconomyService
