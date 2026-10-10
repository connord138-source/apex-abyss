--!strict
-- Daily bounties (Config/Bounties; owner, 2026-10-10: the "pull back element").
-- Three a UTC day for every player, drawn from the pool with a seed of their id and
-- the day (so a rejoin draws the same three), different kinds, within their fish's
-- level. Game events move them on (Events: caught, bitPredator, banked, shells,
-- treasure); each pays the moment it's done, and all three open the Bounty Chest.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BountiesConfig = require(ReplicatedStorage.Shared.Config.Bounties)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Size = require(ReplicatedStorage.Shared.Size)
local Tides = require(ReplicatedStorage.Shared.Tides)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local HuntService = require(script.Parent.HuntService)
local StateService = require(script.Parent.StateService)
local TreasureService = require(script.Parent.TreasureService)

type PlayerData = DataService.PlayerData

local Bounties = Config.Bounties
local CatchConfig = Config.Catch

local BountyService = {}

-- How rare a rarity is (Normal 0, Golden 1, ...), for "Golden or rarer"
local function rank(rarityId: string): number
	return CatchConfig.codes[rarityId] or 0
end

-- Today's three, drawn once a day
local function today(player: Player, data: PlayerData): { { id: string, progress: number, done: boolean } }
	local day = Tides.day(Timing.unix())
	local record = data.bounties
	if record.day == day and #record.list > 0 then
		return record.list
	end
	local level = Size.level(Progress.mass(data))
	local hasMap = #data.maps > 0
	local candidates = {}
	for _, bounty in Bounties.pool do
		if (bounty.minLevel or 0) <= level and (not bounty.needsMap or hasMap) then
			table.insert(candidates, bounty)
		end
	end
	local rng = Random.new(player.UserId * 7919 + day * 104729)
	local picked: { { id: string, progress: number, done: boolean } } = {}
	local kinds: { [string]: boolean } = {}
	for _ = 1, 40 do
		if #picked >= Bounties.perDay or #candidates == 0 then
			break
		end
		local index = rng:NextInteger(1, #candidates)
		local bounty = candidates[index]
		table.remove(candidates, index)
		if not kinds[bounty.kind] then
			kinds[bounty.kind] = true
			table.insert(picked, { id = bounty.id, progress = 0, done = false })
		end
	end
	data.bounties = { day = day, list = picked, chest = false }
	DataService.markDirty(player)
	return picked
end

-- Pays a reward; returns what it was, for the toast
local function pay(player: Player, data: PlayerData, reward: BountiesConfig.Reward): { string }
	local got: { string } = {}
	if reward.coral then
		EconomyService.addCoral(player, reward.coral)
		table.insert(got, `{Format.number(reward.coral)} coral`)
	end
	if reward.shells then
		EconomyService.addShells(player, reward.shells)
		table.insert(got, `{reward.shells} shells`)
	end
	if reward.wraps then
		HuntService.giveWrap(player, reward.wraps)
		table.insert(got, `{reward.wraps} Kelp Wrap{if reward.wraps == 1 then "" else "s"}`)
	end
	if reward.charms then
		for id, count in reward.charms do
			data.charms[id] = (data.charms[id] or 0) + count
			local charm = Config.Shop.charmsById[id]
			table.insert(got, `{count} {if charm then charm.name else id}`)
		end
	end
	if reward.map then
		if TreasureService.give(player, reward.map) then
			table.insert(got, "a treasure map")
		else
			EconomyService.addCoral(player, 500)
			table.insert(got, "500 coral (your satchel was full)")
		end
	end
	return got
end

-- Moves every bounty of `kind` on by `amount` (`rarityId` for catches)
local function advance(player: Player, kind: string, amount: number, rarityId: string?)
	local data = DataService.get(player)
	if data == nil or not data.tutorial.done then
		return
	end
	local list = today(player, data)
	local changed = false
	for _, entry in list do
		local bounty = Bounties.byId[entry.id]
		if bounty == nil or entry.done or bounty.kind ~= kind then
			continue
		end
		if kind == "catch" and (rarityId == nil or rank(rarityId) < rank(bounty.rarity or "Golden")) then
			continue
		end
		entry.progress = math.min(entry.progress + amount, bounty.count)
		changed = true
		if entry.progress >= bounty.count then
			entry.done = true
			local got = pay(player, data, bounty.reward)
			local text = string.gsub(bounty.text, "{n}", tostring(bounty.count))
			Net.notify(player, `BOUNTY DONE · {text} · {table.concat(got, ", ")}`, "good")
		end
	end
	if changed then
		local all = #list > 0
		for _, entry in list do
			all = all and entry.done
		end
		if all and not data.bounties.chest then
			data.bounties.chest = true
			local got = pay(player, data, Bounties.chest)
			Net.notify(player, `BOUNTY CHEST · {table.concat(got, ", ")}`, "rare")
		end
		DataService.markDirty(player)
	end
end

-- Testing (the admin panel): finish today's three (each pays, then the chest)
function BountyService.finishAll(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	for _, entry in today(player, data) do
		local bounty = Bounties.byId[entry.id]
		if bounty and not entry.done then
			advance(player, bounty.kind, bounty.count, bounty.rarity)
		end
	end
end

-- Testing (the admin panel): draw today's three again
function BountyService.redraw(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	data.bounties = { day = 0, list = {}, chest = false }
	today(player, data)
end

function BountyService.start()
	Events.caught:connect(function(player: Player, _preyId: string, rarityId: string)
		advance(player, "eat", 1)
		if rarityId ~= "Normal" then
			advance(player, "catch", 1, rarityId)
		end
		local tide = Tides.at(Timing.unix())
		if tide.id ~= "Calm" then
			advance(player, "tide", 1)
		end
	end)
	Events.bitPredator:connect(function(player: Player, _id: string, boss: boolean)
		advance(player, if boss then "boss" else "bite", 1)
	end)
	Events.banked:connect(function(player: Player)
		advance(player, "banks", 1)
	end)
	Events.shells:connect(function(player: Player, count: number)
		advance(player, "shells", count)
	end)
	Events.treasure:connect(function(player: Player)
		advance(player, "treasure", 1)
	end)
	-- A new UTC day while someone's online: their board shows the new three
	Guard.loop("BountyService.day", 30, function()
		local day = Tides.day(Timing.unix())
		for player, data in DataService.loadedPlayers() do
			if data.bounties.day ~= day and data.tutorial.done then
				today(player, data)
			end
		end
	end)
	StateService.provide(function(player, data, state)
		if not data.tutorial.done then
			state.bounties = nil
			return
		end
		local list = today(player, data)
		state.bounties = {
			list = list,
			chest = data.bounties.chest,
			nextAt = (Tides.day(Timing.unix()) + 1) * 86400,
		}
	end)
end

return BountyService
