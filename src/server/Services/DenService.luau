--!strict
-- Den bases (Config/Dens, GDD §6): each player's den record (level, furniture in its
-- slots, what they own, the glow color) lives in their save and is built into
-- whichever den they hold this server (DenBuilder). Upgrades, furniture and colors
-- cost coral; only the den's owner can change it (visitors can swim in and look).
-- The trophy wall fills itself from the player's stats and boss trophies.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Garden = require(ReplicatedStorage.Shared.Garden)
local DenBuilder = require(script.Parent.Parent.DenBuilder)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local MonetizationService = require(script.Parent.MonetizationService)
local StateService = require(script.Parent.StateService)
local WorldService = require(script.Parent.WorldService)

local Dens = Config.Dens

local DenService = {}

local function fail(player: Player, text: string)
	Net.notify(player, text, "bad")
end

local function trophiesOf(player: Player, data: DataService.PlayerData): DenBuilder.Trophies
	return {
		bestPrey = data.stats.bestPrey,
		bestPreyMass = data.stats.bestPreyMass,
		teeth = data.trophies.MegalodonTeeth or 0,
		beaks = data.trophies.KrakenBeaks or 0,
		title = data.title,
		owner = player.DisplayName,
	}
end

-- Whether a slot is open at the den's level (or by a pass the player owns)
local function slotUnlocked(player: Player, level: number, slotId: string): boolean
	local slot = Dens.slotsById[slotId]
	if slot and slot.pass then
		return MonetizationService.hasPass(player, slot.pass)
	end
	for i = 1, level do
		local def = Dens.levels[i]
		if def and table.find(def.slots, slotId) then
			return true
		end
	end
	return false
end

-- Builds the player's den as their record says
function DenService.refresh(player: Player)
	local data = DataService.get(player)
	local den = FishService.denOf(player)
	if data == nil or den == nil then
		return
	end
	Guard.run("DenService.build", function()
		local rates = Garden.rates(data.den.level, MonetizationService.hasPass(player, "DeepGarden"))
		local shellFill = if rates.capShells > 0 then data.garden.shells / rates.capShells else 0
		-- Furniture only in spots still open (a pass refunded closes its spots)
		local record = data.den
		local furniture: { [string]: string } = {}
		for slotId, itemId in record.furniture do
			if slotUnlocked(player, record.level, slotId) then
				furniture[slotId] = itemId
			end
		end
		local shown =
			{ level = record.level, furniture = furniture, owned = record.owned, glow = record.glow }
		DenBuilder.build(den, shown, trophiesOf(player, data), Garden.fill(data.garden, rates), shellFill)
		local level = Dens.levels[data.den.level] or Dens.levels[1]
		WorldService.setDenLevel(den, level.name)
	end)
end

local function upgrade(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local next = Dens.levels[data.den.level + 1]
	if next == nil then
		return fail(player, "Your den is already a Grotto")
	end
	if not EconomyService.spendCoral(player, next.cost) then
		return fail(player, `Not enough coral ({next.cost} needed)`)
	end
	data.den.level = next.level
	DataService.markDirty(player)
	Net.notify(player, `Your den is a {next.name} now`, "good")
	DenService.refresh(player)
	Events.denChanged:fire(player, "upgrade")
end

local function place(player: Player, slotId: any, itemId: any)
	local data = DataService.get(player)
	if data == nil or typeof(slotId) ~= "string" or typeof(itemId) ~= "string" then
		return
	end
	local slot = Dens.slotsById[slotId]
	if slot == nil or not slotUnlocked(player, data.den.level, slotId) then
		return fail(player, "That spot isn't open yet")
	end
	if itemId == "" then
		data.den.furniture[slotId] = nil
		DataService.markDirty(player)
		DenService.refresh(player)
		return
	end
	local item = Dens.itemsById[itemId]
	if item == nil or not table.find(item.kinds, slot.kind) then
		return fail(player, "That doesn't go there")
	end
	if not data.den.owned[itemId] then
		if not EconomyService.spendCoral(player, item.price) then
			return fail(player, `Not enough coral ({item.price} needed)`)
		end
		data.den.owned[itemId] = true
		Net.notify(player, `Bought {item.name}`, "good")
	end
	data.den.furniture[slotId] = itemId
	DataService.markDirty(player)
	DenService.refresh(player)
end

local function color(player: Player, glowId: any)
	local data = DataService.get(player)
	if data == nil or typeof(glowId) ~= "string" then
		return
	end
	local glow = Dens.glowsById[glowId]
	if glow == nil then
		return
	end
	if glow.price > 0 and not data.den.owned[`Glow:{glow.id}`] then
		if not EconomyService.spendCoral(player, glow.price) then
			return fail(player, `Not enough coral ({glow.price} needed)`)
		end
		data.den.owned[`Glow:{glow.id}`] = true
	end
	data.den.glow = glow.id
	DataService.markDirty(player)
	DenService.refresh(player)
end

function DenService.start()
	FishService.denAssigned:connect(function(player: Player, _index: number)
		DenService.refresh(player)
	end)
	FishService.denFreed:connect(function(index: number)
		Guard.run("DenService.clear", function()
			DenBuilder.clear(index, true)
			WorldService.setDenLevel(index, nil)
		end)
	end)
	Events.trophies:connect(function(player: Player)
		DenService.refresh(player)
	end)
	-- A pass's spots (Den Expansion) and garden (Deep Garden) show at once
	MonetizationService.passAdded:connect(function(player: Player, key: string)
		if key == "DenExpansion" or key == "DeepGarden" then
			DenService.refresh(player)
		end
	end)
	Net.onRequest("DenUpgrade", upgrade)
	Net.onRequest("DenPlace", place)
	Net.onRequest("DenColor", color)
	StateService.provide(function(player, data, state)
		state.den = data.den
		state.denIndex = FishService.denOf(player) or 0
	end)
end

return DenService
