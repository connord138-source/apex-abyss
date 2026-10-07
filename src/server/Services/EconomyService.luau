--!strict
-- Coral (the currency) and Shells (the roll currency): adding, spending, and
-- sending them to the HUD with everything that depends on them (upgrades,
-- charms, owned cosmetics). Every payout and purchase goes through here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local DataService = require(script.Parent.DataService)
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
	StateService.provide(function(_player, data, state)
		local perRoll = Config.Rolls.shellsPerRoll
		state.coral = data.coral
		state.shells = data.shells
		state.shellsPerRoll = perRoll
		state.rollsReady = math.floor(data.shells / perRoll)
		state.upgrades = data.upgrades
		state.charms = data.charms
		state.boosts = data.boosts
		state.shades = data.shades
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
