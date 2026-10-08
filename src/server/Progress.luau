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

-- The shades a fish has unlocked (the current one by default). A shade works on
-- every fish, but each fish unlocks it for itself; once a fish has it, it never
-- rolls again for that fish (Shared/RollOdds `owned`).
function Progress.shades(data: DataService.PlayerData, id: string?): { [string]: boolean }
	local record = Progress.record(data, id)
	local owned = record.shades
	if owned == nil then
		local made = {}
		record.shades = made
		return made
	end
	return owned
end

function Progress.ownsShade(data: DataService.PlayerData, shadeId: string, id: string?): boolean
	return Progress.shades(data, id)[shadeId] == true
end

-- Unlocks a shade for a fish (the current one by default); false if it had it.
function Progress.grantShade(data: DataService.PlayerData, shadeId: string, id: string?): boolean
	local owned = Progress.shades(data, id)
	if owned[shadeId] then
		return false
	end
	owned[shadeId] = true
	return true
end

-- Puts a shade on the current fish ("" takes it off); the fish remembers it.
function Progress.wearShade(data: DataService.PlayerData, shadeId: string)
	Progress.record(data).shade = shadeId
	data.equipped.shade = shadeId
end

-- After a species switch: wear what this fish wore last (if it still owns it).
function Progress.syncShade(data: DataService.PlayerData)
	local worn = Progress.record(data).shade or ""
	if worn ~= "" and not Progress.ownsShade(data, worn) then
		worn = ""
	end
	data.equipped.shade = worn
end

-- Shade ids some other fish of this player has, for "unlocked on another fish"
function Progress.otherShades(data: DataService.PlayerData): { [string]: boolean }
	local current = Progress.speciesId(data)
	local others: { [string]: boolean } = {}
	for id, record in data.species do
		if id ~= current and record.shades then
			for shadeId in record.shades do
				others[shadeId] = true
			end
		end
	end
	return others
end

return Progress
