--!strict
-- What a player's upgrades and charms do, in one place, so the server (checks,
-- payouts) and the client (movement, pickups) always agree. `upgrades` maps an
-- upgrade id to its level; `boosts` maps a timed charm id to the Unix time it ends.
local Config = require(script.Parent.Config)

local Shop = Config.Shop

local Perks = {}

function Perks.level(upgrades: { [string]: number }?, id: string): number
	return if upgrades then upgrades[id] or 0 else 0
end

local function per(id: string): number
	return Shop.upgradesById[id].per
end

function Perks.active(boosts: { [string]: number }?, id: string, now: number): boolean
	return boosts ~= nil and (boosts[id] or 0) > now
end

-- Top speed (Strong Fins).
function Perks.speed(upgrades: { [string]: number }?): number
	return 1 + per("Fins") * Perks.level(upgrades, "Fins")
end

-- Dash recharge speed (Deep Gills).
function Perks.boost(upgrades: { [string]: number }?): number
	return 1 + per("Gills") * Perks.level(upgrades, "Gills")
end

-- Bite damage (Iron Jaw).
function Perks.bite(upgrades: { [string]: number }?): number
	return 1 + per("Jaw") * Perks.level(upgrades, "Jaw")
end

-- Banked share of a Haul (Haul Chamber).
function Perks.bank(upgrades: { [string]: number }?): number
	return 1 + per("Chamber") * Perks.level(upgrades, "Chamber")
end

-- Haul from eating (Feast Charm).
function Perks.feast(boosts: { [string]: number }?, now: number): number
	return if Perks.active(boosts, "Feast", now) then 1.25 else 1
end

-- How far from the mouth a shell is picked up (Shell Sense, Shell Magnet).
function Perks.shellReach(
	length: number,
	upgrades: { [string]: number }?,
	boosts: { [string]: number }?,
	now: number
): number
	local reach = (Config.Shells.reach + length * 0.5) * (1 + per("Senses") * Perks.level(upgrades, "Senses"))
	return if Perks.active(boosts, "Magnet", now) then reach * 2 else reach
end

return Perks
