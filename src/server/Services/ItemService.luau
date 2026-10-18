--!strict
-- The item wheel's server side (owner, 2026-10-11: "kelp wraps also need to be put in
-- user inventory wheel to be used when needed and not immediately, same for kelp
-- wraps won from the spin wheel"). The consumables a fish carries (Config/Shop
-- `items`): Kelp Wraps and the timed charms (Feast, Shell Magnet, Deep Lantern),
-- which used to start the moment they were bought or won. However they come (the
-- Tidecharm Trader, the Treasure Wheel, treasure, bounties, the admin panel) they go
-- into data.charms, up to each one's carry cap, and start only when used: from the
-- wheel (UseItem), a wrap also from H / the HEAL button (HuntService UseWrap).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Format = require(ReplicatedStorage.Shared.Format)
local Events = require(script.Parent.Parent.Events)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local HuntService = require(script.Parent.HuntService)
local WardrobeService = require(script.Parent.WardrobeService)

local Shop = Config.Shop

local ItemService = {}

local onWheel: { [string]: boolean } = {}
for _, id in Shop.items do
	onWheel[id] = true
end

-- How many of an item a fish can carry.
function ItemService.cap(id: string): number
	if id == "KelpWrap" then
		return Config.Tuning.heal.wrapMax
	end
	local charm = Shop.charmsById[id]
	return if charm and charm.max then charm.max else 3
end

-- Puts `count` of an item in a player's inventory, up to its cap. Returns how many
-- went in (0 when the satchel is full).
function ItemService.give(player: Player, id: string, count: number): number
	local data = DataService.get(player)
	if data == nil or count <= 0 then
		return 0
	end
	local held = data.charms[id] or 0
	local added = math.max(0, math.min(count, ItemService.cap(id) - held))
	if added > 0 then
		data.charms[id] = held + added
		DataService.markDirty(player)
	end
	return added
end

-- Uses one of an item now: a Kelp Wrap heals, a timed charm starts (or adds its time
-- to one already running).
function ItemService.use(player: Player, id: string)
	if not onWheel[id] then
		return
	end
	if id == "KelpWrap" then
		local data = DataService.get(player)
		local held = if data then data.charms.KelpWrap or 0 else 0
		if held < 1 then
			HuntService.useWrap(player) -- (it says where to get one)
			return
		end
		-- At full health the wrap stays in the bar (the item bar's H, 1 and taps
		-- come here too), and that still counts as learning where it is
		local character = player.Character
		local health = if character then character:GetAttribute("Health") else nil
		local most = if character then character:GetAttribute("MaxHealth") else nil
		if typeof(health) == "number" and typeof(most) == "number" and health >= most then
			Net.notify(
				player,
				"You're at full health: your Kelp Wrap stays in your item bar for when you're hurt",
				"info"
			)
			Events.usedItem:fire(player, id, false)
			return
		end
		HuntService.useWrap(player)
		if data and (data.charms.KelpWrap or 0) < held then
			Events.usedItem:fire(player, id, true)
		end
		return
	end
	local data = DataService.get(player)
	local charm = Shop.charmsById[id]
	if data == nil or charm == nil or charm.seconds == nil then
		return
	end
	if (data.charms[id] or 0) < 1 then
		return Net.notify(player, `No {charm.name}. The Tidecharm Trader sells them`, "bad")
	end
	data.charms[id] -= 1
	local now = Timing.now()
	local ends = math.max(data.boosts[id] or 0, now) + charm.seconds
	data.boosts[id] = ends
	WardrobeService.refresh(player)
	DataService.markDirty(player)
	Net.notify(player, `{charm.name} on · {Format.clock(ends - now)}`, "good")
	Events.usedItem:fire(player, id, true)
end

function ItemService.start()
	Net.onRequest("UseItem", function(player: Player, id: any)
		if typeof(id) == "string" then
			ItemService.use(player, id)
		end
	end)
end

return ItemService
