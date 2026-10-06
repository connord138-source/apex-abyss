--!strict
-- Choosing which species to swim as, and unlocking new ones (owner: every species
-- levels up separately; the starter first, then the others are unlocked). Switching
-- happens in the safe zone with no Haul aboard, and respawns you in your den as the
-- new fish at that species' own size. Unlocking costs the species' home-biome DNA
-- plus coral; the 'Cuda comes from finishing the tutorial (TutorialService).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Events = require(script.Parent.Parent.Events)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local HuntService = require(script.Parent.HuntService)

local Species = Config.Species

local SpeciesService = {}

local function selectSpecies(player: Player, id: any)
	local data = DataService.get(player)
	if data == nil or typeof(id) ~= "string" then
		return
	end
	local species = Species.byId[id]
	if species == nil or not data.unlocked[id] or data.current == id then
		return
	end
	if not data.tutorial.done then
		return Net.notify(player, "Finish the tutorial to pick another fish", "bad")
	end
	local _, root = FishService.character(player)
	if root and not Layout.inHub(root.Position) then
		return Net.notify(player, "Switch fish in the safe zone (the dens and the market)", "bad")
	end
	if HuntService.haul(player) > 0 then
		return Net.notify(player, "Bank your Haul first", "bad")
	end
	data.current = id
	DataService.markDirty(player)
	FishService.spawn(player)
	Net.notify(player, `You're a {species.name} now`, "good")
end

local function unlock(player: Player, id: any)
	local data = DataService.get(player)
	if data == nil or typeof(id) ~= "string" then
		return
	end
	local species = Species.byId[id]
	if species == nil or data.unlocked[id] then
		return
	end
	local rule = species.unlock
	if rule.kind ~= "dna" or rule.biome == nil then
		return
	end
	local need, coral = rule.dna or 0, rule.coral or 0
	local have = data.dna[rule.biome] or 0
	if have < need then
		local biome = Config.Biomes.byId[rule.biome]
		return Net.notify(player, `You need {need - have} more {biome.name} DNA`, "bad")
	end
	if not EconomyService.spendCoral(player, coral) then
		return Net.notify(player, "Not enough coral", "bad")
	end
	data.dna[rule.biome] = have - need
	data.unlocked[id] = true
	DataService.markDirty(player)
	DataService.save(player)
	Events.unlocked:fire(player, id)
	Net.notify(player, `{species.name} unlocked!`, "rare")
end

function SpeciesService.start()
	Net.onRequest("SelectSpecies", selectSpecies)
	Net.onRequest("UnlockSpecies", unlock)
end

return SpeciesService
