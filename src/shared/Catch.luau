--!strict
-- Rare catch odds and rewards (Config/Catch), shared by the server (which rolls and
-- pays) and the client (the Catch Log, the odds in the Tides panel). Pure: no
-- Roblox services.
local CatchConfig = require(script.Parent.Config.Catch)
local TideConfig = require(script.Parent.Config.Tides)
local Tides = require(script.Parent.Tides)

local Catch = {}

-- This week's Catch of the Week (nil before week 1), its week number (1 = the first)
-- and when it ends
function Catch.weekly(unix: number): (CatchConfig.Weekly?, number, number)
	local start = CatchConfig.weekly.start
	local week = Tides.week(unix) - Tides.week(start) + 1
	local endsAt = Tides.weekStart(Tides.week(unix) + 1)
	if week < 1 then
		return nil, week, endsAt
	end
	local list = CatchConfig.weekly.list
	return list[(week - 1) % #list + 1], week, endsAt
end

-- Each rarity's chance for one spawn of `preyId` under tide `tideId`: the tide's
-- multiplier, the deep-water glow of a Bioluminescent Night, and the Catch of the
-- Week's boost on its own fish. A rarity tied to a tide is 0 outside it.
function Catch.chances(preyId: string, tideId: string, deep: boolean, unix: number): { [string]: number }
	local tide = TideConfig.byId[tideId]
	local featured = Catch.weekly(unix)
	local result: { [string]: number } = {}
	for _, rarity in CatchConfig.rarities do
		local chance = if rarity.tide and rarity.tide ~= tideId then 0 else rarity.chance
		chance *= if tide then tide.rarity[rarity.id] or 1 else 1
		if deep and tideId == "Biolum" and rarity.id == "Glowing" then
			chance *= TideConfig.deepGlow
		end
		if featured and featured.prey == preyId and featured.rarity == rarity.id then
			chance *= CatchConfig.weekly.chance
		end
		result[rarity.id] = chance
	end
	return result
end

-- A spawn's rarity from a number in [0, 1): the rarest is checked first, so the
-- chances stay exactly as listed (they're small and never add up to 1)
function Catch.roll(r: number, chances: { [string]: number }): string?
	local edge = 0
	for i = #CatchConfig.rarities, 1, -1 do
		local rarity = CatchConfig.rarities[i]
		edge += chances[rarity.id] or 0
		if r < edge then
			return rarity.id
		end
	end
	return nil
end

-- The coral a rare catch pays (before the tide's and the player's multipliers)
function Catch.coral(rarityId: string, mass: number): number
	local rarity = CatchConfig.byId[rarityId]
	if rarity == nil then
		return 0
	end
	return math.max(rarity.coralMin, math.floor(mass * rarity.coralPerKg))
end

return Catch
