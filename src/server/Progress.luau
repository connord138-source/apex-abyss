--!strict
-- Per-species progress in a player's save (owner: every species levels up on its
-- own). Each species keeps its own banked mass; the fish a player swims as is
-- `data.current`.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.Services.DataService)

local Species = Config.Species
type SpeciesDef = typeof(Species.list[1])

local Progress = {}

-- The species the player is swimming as (the starter if the save names an unknown
-- or locked one).
function Progress.speciesId(data: DataService.PlayerData): string
	local id = data.current
	if Species.byId[id] == nil or not data.unlocked[id] then
		return Species.STARTER
	end
	return id
end

function Progress.species(data: DataService.PlayerData): SpeciesDef
	return Species.byId[Progress.speciesId(data)]
end

-- A species' record, made on first use.
function Progress.record(data: DataService.PlayerData, id: string?): DataService.SpeciesRecord
	local key = id or Progress.speciesId(data)
	local record = data.species[key]
	if record == nil then
		local start = Config.Tuning.size.startMass
		record = { mass = start, bestMass = start }
		data.species[key] = record
	end
	return record
end

-- Banked mass of a species (the current one by default).
function Progress.mass(data: DataService.PlayerData, id: string?): number
	return Progress.record(data, id).mass
end

return Progress
