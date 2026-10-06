--!strict
-- The vendors round the hub plaza: everything Coral buys. Purchases come from the
-- shop menus (opened at a stall's prompt); the server checks the player is at
-- that vendor's stall and can afford it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local WardrobeService = require(script.Parent.WardrobeService)
local WorldService = require(script.Parent.WorldService)

local Shop = Config.Shop

local ShopService = {}

local function atVendor(player: Player, vendorId: string): boolean
	local character, root = FishService.character(player)
	local stall = WorldService.vendorPosition(vendorId)
	if character == nil or root == nil or stall == nil then
		return false
	end
	local length = character:GetAttribute("Length")
	local extra = if typeof(length) == "number" then length * 0.5 else 1
	return (root.Position - stall).Magnitude <= Shop.reach + extra
end

local function fail(player: Player, text: string)
	Net.notify(player, text, "bad")
end

local function buyUpgrade(player: Player, data: DataService.PlayerData, id: string)
	local upgrade = Shop.upgradesById[id]
	if upgrade == nil or not atVendor(player, upgrade.vendor) then
		return
	end
	local level = data.upgrades[id] or 0
	local cost = upgrade.costs[level + 1]
	if cost == nil then
		return fail(player, `{upgrade.name} is maxed`)
	end
	if not EconomyService.spendCoral(player, cost) then
		return fail(player, "Not enough coral")
	end
	data.upgrades[id] = level + 1
	Net.notify(player, `{upgrade.name} → level {level + 1}`, "good")
end

local function buyCharm(player: Player, data: DataService.PlayerData, id: string)
	local charm = Shop.charmsById[id]
	if charm == nil or not atVendor(player, charm.vendor) then
		return
	end
	if charm.max and (data.charms[id] or 0) >= charm.max then
		return fail(player, `You can hold {charm.max} {charm.name}{if charm.max == 1 then "" else "s"}`)
	end
	if not EconomyService.spendCoral(player, charm.price) then
		return fail(player, "Not enough coral")
	end
	if charm.seconds then
		local now = Timing.now()
		data.boosts[id] = math.max(data.boosts[id] or 0, now) + charm.seconds
	else
		data.charms[id] = (data.charms[id] or 0) + 1
	end
	Net.notify(player, `Bought {charm.name}`, "good")
end

local function buyDye(player: Player, data: DataService.PlayerData, id: string)
	local shade = Config.Shades.byId[id]
	if shade == nil or shade.price == nil or not atVendor(player, "Dyer") then
		return
	end
	if data.shades[id] then
		return fail(player, `You already have {shade.name}`)
	end
	if not EconomyService.spendCoral(player, shade.price) then
		return fail(player, "Not enough coral")
	end
	data.shades[id] = true
	WardrobeService.equip(player, "shade", id)
	Net.notify(player, `{shade.name} shade bought and put on`, "good")
end

local function buyShells(player: Player, data: DataService.PlayerData)
	local trade = Shop.shellTrade
	if not atVendor(player, trade.vendor) then
		return
	end
	local today = EconomyService.today()
	if data.shellTrades.day ~= today then
		data.shellTrades = { day = today, count = 0 }
	end
	if data.shellTrades.count >= trade.perDay then
		return fail(player, "No more shell trades today")
	end
	if not EconomyService.spendCoral(player, trade.price) then
		return fail(player, "Not enough coral")
	end
	data.shellTrades.count += 1
	EconomyService.addShells(player, trade.shells)
	Net.notify(player, `+{trade.shells} shells`, "good")
end

local function buy(player: Player, kind: any, id: any)
	local data = DataService.get(player)
	if data == nil or typeof(kind) ~= "string" then
		return
	end
	if kind == "shells" then
		buyShells(player, data)
	elseif typeof(id) ~= "string" then
		return
	elseif kind == "upgrade" then
		buyUpgrade(player, data, id)
	elseif kind == "charm" then
		buyCharm(player, data, id)
	elseif kind == "dye" then
		buyDye(player, data, id)
	end
	DataService.markDirty(player)
end

function ShopService.start()
	Net.onRequest("Buy", buy)
end

return ShopService
