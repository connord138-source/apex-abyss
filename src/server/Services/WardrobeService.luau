--!strict
-- Wearing shades, body parts and exotic variants. The choice is saved, and put on
-- the fish as attributes (Shade, Parts, Variant) that every client dresses it
-- from (Shared/Cosmetics).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local FishService = require(script.Parent.FishService)

local WardrobeService = {}

local function dress(player: Player)
	local data = DataService.get(player)
	local character = FishService.character(player)
	if data == nil or character == nil then
		return
	end
	character:SetAttribute("Shade", data.equipped.shade)
	-- Exotic variants reshape one species only
	local variant = Config.Exotics.variantsById[data.equipped.variant]
	local current = character:GetAttribute("Species")
	character:SetAttribute("Variant", if variant and variant.species == current then variant.id else "")
	character:SetAttribute("Parts", Cosmetics.partsText(data.equipped.parts))
end

-- Puts something on ("" takes it off; for parts, `slot` says which).
function WardrobeService.equip(player: Player, kind: string, id: string, slot: string?)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local equipped = data.equipped
	if kind == "shade" then
		if id ~= "" and not data.shades[id] then
			return
		end
		equipped.shade = id
	elseif kind == "variant" then
		if id ~= "" and not data.variants[id] then
			return
		end
		equipped.variant = id
	elseif kind == "part" then
		if id == "" then
			if typeof(slot) == "string" and table.find(Config.Exotics.SLOTS, slot) then
				equipped.parts[slot] = nil
			end
		else
			local part = Config.Exotics.partsById[id]
			if part == nil or not data.parts[id] then
				return
			end
			equipped.parts[part.slot] = id
		end
	else
		return
	end
	dress(player)
	DataService.markDirty(player)
end

function WardrobeService.start()
	FishService.spawned:connect(function(player: Player)
		dress(player)
	end)
	Net.onRequest("Equip", function(player: Player, kind: any, id: any, slot: any)
		if typeof(kind) == "string" and typeof(id) == "string" then
			WardrobeService.equip(player, kind, id, if typeof(slot) == "string" then slot else nil)
		end
	end)
end

return WardrobeService
