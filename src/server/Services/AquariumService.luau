--!strict
-- The den's aquarium (2026-10-28; the proposal's passive element the owner approved:
-- "i like the den changes lets do that and try it out"; Config/Dens aquarium,
-- Shared/Aquarium). Wall tanks down the main storey's sides (more with the Aquarium
-- Hall wing) each show one rare fish from the player's Catch Log, and earn coral and
-- shells an hour by its rarity, online or off, up to 12 hours of it:
--
--  * stocking (`AquariumStock`, from the den menu): a rare catch you've caught, as
--    many tanks of it as you've caught; an empty name empties the tank;
--  * collecting: swimming near a stocked tank in your own den, or COLLECT ALL in the
--    den menu (`AquariumCollect`);
--  * feeding (`AquariumFeed`): once a UTC day, a Kelp DNA a stocked tank, for ×1.5
--    earnings the rest of that day.
--
-- DenBuilder draws the tanks (DenWings.tanks); the client swims the fish in them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Aquarium = require(ReplicatedStorage.Shared.Aquarium)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local DenSpace = require(ReplicatedStorage.Shared.DenSpace)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local DenService = require(script.Parent.DenService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local StateService = require(script.Parent.StateService)

type PlayerData = DataService.PlayerData

local tune = Config.Dens.aquarium
local TICK = 5
local COLLECT_EVERY = 30 -- seconds between collections while swimming by the tanks
local AWAY_NOTICE = 10 * 60

local AquariumService = {}

type Watch = { lastCollect: number, away: number? }
local watches: { [Player]: Watch } = {}

local function shapeOf(data: PlayerData): DenSpace.Shape
	return { level = data.den.level, wings = data.den.wings, open = data.den.open == true }
end

-- The den's tank ids
local function openTanks(data: PlayerData): { [string]: boolean }
	local open: { [string]: boolean } = {}
	for _, tank in DenSpace.tanks(shapeOf(data)) do
		open[tank.id] = true
	end
	return open
end

local function ratesOf(data: PlayerData): Aquarium.Rates
	return Aquarium.rates(data.den.tanks, openTanks(data))
end

-- Whether the player's fish is in their own den within reach of a stocked tank
local function byTanks(player: Player, data: PlayerData): boolean
	local _, root = FishService.character(player)
	local den = FishService.denOf(player)
	if root == nil or den == nil or Layout.denAt(root.Position) ~= den then
		return false
	end
	local frame = DenSpace.frame(den)
	local here = DenSpace.toLocal(frame, root.Position)
	for _, tank in DenSpace.tanks(shapeOf(data)) do
		if data.den.tanks[tank.id] then
			local gap = Vector3.new(here.X - tank.x, here.Y - tank.y, here.Z - tank.z).Magnitude
			if gap <= tune.reach then
				return true
			end
		end
	end
	return false
end

-- Moves what's grown (whole coral and shells) into the wallet; `loud` says so even
-- when it's little
local function collect(player: Player, data: PlayerData, loud: boolean)
	local record = data.aquarium
	local coral = math.floor(record.coral)
	local shells = math.floor(record.shells)
	if coral < 1 and shells < 1 then
		if loud then
			Net.notify(player, "Nothing to collect from the aquarium yet", "info")
		end
		return
	end
	record.coral -= coral
	record.shells -= shells
	local earned = EconomyService.earnCoral(player, coral)
	EconomyService.addShells(player, shells)
	local watch = watches[player]
	local away = if watch then watch.away else nil
	if watch then
		watch.away = nil
		watch.lastCollect = Timing.now()
	end
	local while_ = if away and away >= AWAY_NOTICE then " while you were away" else ""
	Net.notify(
		player,
		`Aquarium{while_}: +{Format.number(earned)} coral{if shells > 0
			then ` · +{Format.number(shells)} shells`
			else ""}`,
		"good"
	)
	DataService.markDirty(player)
end

local function tick()
	local now = Timing.now()
	for player, watch in watches do
		Guard.run("AquariumService.tick", function()
			local data = DataService.get(player)
			if data == nil then
				return
			end
			Aquarium.grow(data.aquarium, ratesOf(data), now)
			if byTanks(player, data) and now - watch.lastCollect >= COLLECT_EVERY then
				collect(player, data, false)
			end
		end)
	end
end

local function stock(player: Player, tankId: any, preyId: any, rarityId: any)
	local data = DataService.get(player)
	if
		data == nil
		or typeof(tankId) ~= "string"
		or typeof(preyId) ~= "string"
		or typeof(rarityId) ~= "string"
	then
		return
	end
	if not openTanks(data)[tankId] then
		return Net.notify(player, "No such tank in your den", "bad")
	end
	-- What it earned so far stays at the old rate
	Aquarium.grow(data.aquarium, ratesOf(data), Timing.now())
	if preyId == "" then
		data.den.tanks[tankId] = nil
		Net.notify(player, "Tank emptied", "info")
	else
		local why = Aquarium.canStock(data.catchLog, data.den.tanks, tankId, preyId, rarityId)
		if why then
			return Net.notify(player, why, "bad")
		end
		data.den.tanks[tankId] = { prey = preyId, rarity = rarityId }
		local prey = Config.Prey.byId[preyId]
		local rarity = Config.Catch.byId[rarityId]
		local rate = tune.rates[rarityId]
		Net.notify(
			player,
			`{if rarity then rarity.name else ""} {if prey then prey.name else preyId} in the tank · +{rate.coral} coral an hour`,
			"good"
		)
	end
	DataService.markDirty(player)
	DenService.refresh(player)
end

local function collectAll(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	Aquarium.grow(data.aquarium, ratesOf(data), Timing.now())
	collect(player, data, true)
end

local function feed(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local now = Timing.now()
	local record = data.aquarium
	if Aquarium.fedToday(record, now) then
		return Net.notify(player, "The tanks are fed for today · come back tomorrow", "info")
	end
	local rates = ratesOf(data)
	if rates.stocked == 0 then
		return Net.notify(player, "Stock a tank first", "info")
	end
	local cost = Aquarium.feedCost(rates)
	local biome = tune.feed.biome
	local have = data.dna[biome] or 0
	if have < cost then
		local def = Config.Biomes.byId[biome]
		return Net.notify(
			player,
			`Feeding takes {cost} {if def then def.name else biome} DNA (you have {have})`,
			"bad"
		)
	end
	Aquarium.grow(record, rates, now)
	data.dna[biome] = have - cost
	record.fed = Aquarium.day(now)
	DataService.markDirty(player)
	Net.notify(
		player,
		`Fed {rates.stocked} tanks · ×{tune.feed.multiplier} earnings for the rest of today`,
		"good"
	)
end

-- Admin testing: grows the aquarium as if the player had been away `hours`
function AquariumService.fastForward(player: Player, hours: number): string
	local data = DataService.get(player)
	if data == nil then
		return "No data"
	end
	local rates = ratesOf(data)
	data.aquarium.at = Timing.now() - hours * 3600
	local seconds = Aquarium.grow(data.aquarium, rates, Timing.now())
	local watch = watches[player]
	if watch then
		watch.away = seconds
		watch.lastCollect = 0
	end
	DataService.markDirty(player)
	return `Aquarium grew {hours} h: {math.floor(data.aquarium.coral)} coral, {math.floor(
		data.aquarium.shells
	)} shells waiting ({rates.stocked} tanks stocked)`
end

-- Admin testing: every tank stocked with the rarest catches the player has (or, when
-- `free`, with Golden Minnows whether caught or not), and feeding open again
function AquariumService.fill(player: Player, free: boolean): string
	local data = DataService.get(player)
	if data == nil then
		return "No data"
	end
	Aquarium.grow(data.aquarium, ratesOf(data), Timing.now())
	local tanks = DenSpace.tanks(shapeOf(data))
	local preys = {}
	for _, prey in Config.Prey.list do
		table.insert(preys, prey.id)
	end
	local rarities = {}
	for _, rarity in Config.Catch.rarities do
		table.insert(rarities, 1, rarity.id) -- rarest first
	end
	local n = 0
	for i, tank in tanks do
		if free then
			local prey = preys[(i - 1) % #preys + 1]
			local rarity = rarities[(i - 1) % #rarities + 1]
			data.catchLog[prey] = data.catchLog[prey] or {}
			data.catchLog[prey][rarity] = math.max(data.catchLog[prey][rarity] or 0, 1)
			data.den.tanks[tank.id] = { prey = prey, rarity = rarity }
			n += 1
		else
			for _, rarity in rarities do
				local found = false
				for prey in data.catchLog do
					if Aquarium.canStock(data.catchLog, data.den.tanks, tank.id, prey, rarity) == nil then
						data.den.tanks[tank.id] = { prey = prey, rarity = rarity }
						found = true
						n += 1
						break
					end
				end
				if found then
					break
				end
			end
		end
	end
	data.aquarium.fed = 0
	DataService.markDirty(player)
	DenService.refresh(player)
	return `{n} of {#tanks} tanks stocked`
end

function AquariumService.start()
	DataService.loaded:connect(function(player: Player, data: PlayerData)
		if typeof(data.aquarium) ~= "table" then
			data.aquarium = { coral = 0, shells = 0, at = 0, fed = 0 }
		end
		if typeof(data.den.tanks) ~= "table" then
			data.den.tanks = {}
		end
		local away = Aquarium.grow(data.aquarium, ratesOf(data), Timing.now())
		watches[player] = { lastCollect = 0, away = away }
	end)
	DataService.releasing:connect(function(_player: Player, data: PlayerData)
		Aquarium.grow(data.aquarium, ratesOf(data), Timing.now())
	end)
	Players.PlayerRemoving:Connect(function(player)
		watches[player] = nil
	end)
	Net.onRequest("AquariumStock", stock)
	Net.onRequest("AquariumCollect", collectAll)
	Net.onRequest("AquariumFeed", feed)
	Guard.loop("AquariumService.tick", TICK, tick)
	StateService.provide(function(_player, data, state)
		local rates = ratesOf(data)
		local now = Timing.now()
		state.aquarium = {
			coral = math.floor(data.aquarium.coral),
			shells = math.floor(data.aquarium.shells),
			capCoral = math.floor(rates.capCoral),
			coralPerHour = rates.coralPerHour,
			shellsPerHour = rates.shellsPerHour,
			stocked = rates.stocked,
			tanks = #DenSpace.tanks(shapeOf(data)),
			fed = Aquarium.fedToday(data.aquarium, now),
			feedCost = Aquarium.feedCost(rates),
		}
	end)
end

return AquariumService
