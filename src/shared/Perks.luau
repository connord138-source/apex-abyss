--!strict
-- What a player's upgrades and charms do, in one place, so the server (checks,
-- payouts) and the client (movement, pickups) always agree. `upgrades` maps an
-- upgrade id to its level; `boosts` maps a timed charm id to the Unix time it ends.
local Config = require(script.Parent.Config)
local Exotics = require(script.Parent.Config.Exotics)

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

-- How fast every fish's own ability recharges (Quick Recovery: the Nibbler's Dash and
-- every other signature ability's cooldown, ÷ this).
function Perks.boost(upgrades: { [string]: number }?): number
	return 1 + per("Gills") * Perks.level(upgrades, "Gills")
end

-- Bite damage (Iron Jaw).
function Perks.bite(upgrades: { [string]: number }?): number
	return 1 + per("Jaw") * Perks.level(upgrades, "Jaw")
end

-- Extra levels against depth pressure (Pressure Hide).
function Perks.depth(upgrades: { [string]: number }?): number
	return per("Hide") * Perks.level(upgrades, "Hide")
end

-- Banked share of a Haul (Haul Chamber).
function Perks.bank(upgrades: { [string]: number }?): number
	return 1 + per("Chamber") * Perks.level(upgrades, "Chamber")
end

-- Haul from eating (Feast Charm).
function Perks.feast(boosts: { [string]: number }?, now: number): number
	return if Perks.active(boosts, "Feast", now) then 1.25 else 1
end

-- How far from the mouth a shell is picked up (Shell Sense, Shell Magnet, and `find`:
-- a Sawblade Snout's Perks.exotic(character).find).
function Perks.shellReach(
	length: number,
	upgrades: { [string]: number }?,
	boosts: { [string]: number }?,
	now: number,
	find: number?
): number
	local reach = (Config.Shells.reach + length * 0.5) * (1 + per("Senses") * Perks.level(upgrades, "Senses"))
	reach *= find or 1
	return if Perks.active(boosts, "Magnet", now) then reach * 2 else reach
end

-- The Reef Shark's Blood Sense (Config/Abilities BloodSense), a feeding frenzy: while
-- a fish's `Sensing` attribute (the server clock it ends at, set by AbilityService) is
-- ahead of `now` it swims × `speed` (a multiplier on Size.topSpeed, like Strong Fins)
-- and draws prey in and swallows them from × `suction` as far. `grace` keeps it on
-- that many seconds longer (the server sees a fish a little in the past). Returns the
-- speed and suction multipliers (1, 1 when it isn't sensing).
function Perks.sense(character: Instance?, now: number, grace: number?): (number, number)
	local speed, suction = 1, 1
	local untilAt = if character then character:GetAttribute("Sensing") else nil
	if typeof(untilAt) == "number" and untilAt + (grace or 0) > now then
		local sense = Config.Abilities.byId.BloodSense
		speed, suction = sense.speed or 1, sense.suction or 1
	end
	-- (an Anglerfish's Abyss Maw draws prey in from far off too)
	local maw = if character then character:GetAttribute("MawUntil") else nil
	if typeof(maw) == "number" and maw + (grace or 0) > now then
		suction *= Config.Specials.bySpecies.Anglerfish.suction or 1
	end
	return speed, suction
end

-- The seconds between a fish's bites: a Nibbler's Wild Thrash (Config/Specials) bites
-- faster. The client and the server's checks both read it.
function Perks.biteGap(character: Instance?, now: number): number
	local gap = Config.Tuning.swim.biteCooldown
	local thrash = if character then character:GetAttribute("ThrashUntil") else nil
	if typeof(thrash) == "number" and thrash > now then
		gap /= Config.Specials.bySpecies.Nibbler.rate or 1
	end
	return gap
end

-- × a fish's bite damage right now: a Reef Shark's Blood Frenzy (Config/Specials)
function Perks.biteBonus(character: Instance?, now: number): number
	local frenzy = if character then character:GetAttribute("FrenzyUntil") else nil
	if typeof(frenzy) == "number" and frenzy > now then
		return Config.Specials.bySpecies.ReefShark.bonus or 1
	end
	return 1
end

-- What a fish's rolled parts and exotic variant do for it (Config/Exotics `bonus`),
-- read from the character's Parts and Variant attributes, which only the server sets
-- (WardrobeService), so the server's checks and the client agree. Every multiplier is
-- 1 without one; `recharge`, `duration` and `range` are per ability id (Perks.of).
export type Exotic = {
	reach: number,
	dash: number,
	find: number,
	speed: number,
	turn: number,
	recharge: { [string]: number },
	duration: { [string]: number },
	range: { [string]: number },
}

local exoticCache: { [string]: Exotic } = {}

function Perks.exotic(character: Instance?): Exotic
	local parts = if character then character:GetAttribute("Parts") else nil
	local variant = if character then character:GetAttribute("Variant") else nil
	local key = `{if typeof(parts) == "string" then parts else ""}|{if typeof(variant) == "string"
		then variant
		else ""}`
	local cached = exoticCache[key]
	if cached then
		return cached
	end
	local out: Exotic = {
		reach = 1,
		dash = 1,
		find = 1,
		speed = 1,
		turn = 1,
		recharge = {},
		duration = {},
		range = {},
	}
	local function add(bonus: Exotics.Bonus?)
		if bonus == nil then
			return
		end
		local kind = bonus.kind
		if (kind == "recharge" or kind == "duration" or kind == "range") and bonus.ability then
			local map: { [string]: number } = (out :: any)[kind]
			map[bonus.ability] = (map[bonus.ability] or 1) * bonus.amount
		elseif kind == "reach" or kind == "dash" or kind == "find" or kind == "speed" or kind == "turn" then
			(out :: any)[kind] *= bonus.amount
		end
	end
	if typeof(parts) == "string" then
		for id in parts:gmatch("%w+=(%w+)") do
			local part = Exotics.partsById[id]
			add(if part then part.bonus else nil)
		end
	end
	if typeof(variant) == "string" and variant ~= "" then
		local shape = Exotics.variantsById[variant]
		add(if shape then shape.bonus else nil)
	end
	exoticCache[key] = out
	return out
end

-- One ability's share of an Exotic's per-ability bonuses (1 when it has none).
function Perks.of(map: { [string]: number }, ability: string): number
	return map[ability] or 1
end

return Perks
