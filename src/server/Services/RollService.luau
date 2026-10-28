--!strict
-- Rolls: 50 Shells buys one. The server rolls (Shared/RollOdds, the same table
-- the odds panel shows), grants the outcome, and sends the result for the reveal.
-- Shades are per fish: one the rolling fish has is out of its table. A part or
-- variant you already own turns into coral instead, and so does a charm prize you
-- carry the most of or a map prize with the satchel full (Config/Rolls `prizes`).
-- Rare skins, parts and variants are announced to the whole server and saved
-- straight away.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local Events = require(script.Parent.Parent.Events)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local Progress = require(script.Parent.Parent.Progress)
local TreasureService = require(script.Parent.TreasureService)

local Rolls = Config.Rolls
local Tiers = Config.Tiers

local RollService = {}

local rng = Random.new()

local function owned(data: DataService.PlayerData, outcome: RollOdds.Outcome): { [string]: boolean }?
	if outcome.kind == "shade" then
		return Progress.shades(data)
	elseif outcome.kind == "part" then
		return data.parts
	elseif outcome.kind == "variant" then
		return data.variants
	end
	return nil
end

local function roll(player: Player)
	local data = DataService.get(player)
	if data == nil or data.shells < Rolls.shellsPerRoll then
		return
	end
	data.shells -= Rolls.shellsPerRoll
	data.stats.rolls += 1
	-- A Lucky Charm is used up by the next roll
	local luck = 1
	if (data.charms.Lucky or 0) > 0 then
		data.charms.Lucky -= 1
		luck = 2
	end
	-- This fish's shades are out of its table (they never roll again for it)
	local fishShades = Progress.shades(data)
	local species = Progress.speciesId(data)
	local outcome = RollOdds.pick(luck, rng:NextNumber(), fishShades, species)
	local probability = 0
	for _, entry in RollOdds.table(luck, fishShades, species) do
		if entry.outcome == outcome then
			probability = entry.probability
		end
	end

	local result: { [string]: any } = {
		id = outcome.id,
		kind = outcome.kind,
		name = outcome.name,
		tier = outcome.tier,
		probability = probability,
		luck = luck,
	}
	if outcome.kind == "coral" then
		local amount = outcome.amount or 0
		EconomyService.addCoral(player, amount)
		result.coral = amount
	elseif outcome.fixed then
		-- A prize: paid straight away, or coral when it can't be carried
		local function instead()
			result.duplicate = true
			result.coral = outcome.refund or 0
			EconomyService.addCoral(player, outcome.refund or 0)
		end
		if outcome.kind == "shells" then
			EconomyService.addShells(player, outcome.amount or 0)
			result.shells = outcome.amount
		elseif outcome.kind == "dna" then
			-- (for the rolling fish's home biome: what its unlocks and its line need)
			local home = Progress.species(data).home
			data.dna[home] = (data.dna[home] or 0) + (outcome.amount or 0)
			result.dna = outcome.amount
			local biome = Config.Biomes.byId[home]
			result.dnaBiome = if biome then biome.name else home
		elseif outcome.kind == "charm" then
			local id = outcome.charm or ""
			local charm = Config.Shop.charmsById[id]
			if charm == nil or (data.charms[id] or 0) >= (charm.max or math.huge) then
				instead()
			else
				data.charms[id] = (data.charms[id] or 0) + 1
				result.charm = id
			end
		elseif outcome.kind == "map" then
			if not TreasureService.give(player, outcome.map or "Tattered") then
				instead()
			end
		end
	else
		local collection = owned(data, outcome)
		if collection and collection[outcome.id] then
			result.duplicate = true
			result.coral = outcome.refund or 0
			EconomyService.addCoral(player, outcome.refund or 0)
		elseif collection then
			collection[outcome.id] = true
		end
	end
	result.rollsLeft = math.floor(data.shells / Rolls.shellsPerRoll)
	DataService.markDirty(player)
	Net.rollResult(player, result)
	Events.rolled:fire(player)

	local tier = Tiers.byId[outcome.tier]
	if tier and not outcome.fixed and tier.order >= Tiers.byId[Rolls.announceFrom].order then
		local text =
			`{player.DisplayName} rolled {string.upper(outcome.name)}! ({RollOdds.oneIn(probability)})`
		-- Let the roller's reveal land first
		task.delay(if tier.order >= Tiers.byId.Mythic.order then 6 else 4, function()
			Net.notifyAll(text, "rare")
		end)
		DataService.save(player)
	end
end

function RollService.start()
	Net.onRequest("Roll", roll)
end

return RollService
