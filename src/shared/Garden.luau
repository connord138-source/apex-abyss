--!strict
-- The den's Coral Garden (Config/Dens garden): how fast it grows and how much it
-- holds for a den level, and growing a saved garden record up to a moment. Shared
-- so the server (GardenService) and the den menu agree.
local Config = require(script.Parent.Config)

local Dens = Config.Dens
local tune = Dens.garden
local deepGarden = Config.Monetization.tuning.deepGarden

export type Record = { coral: number, shells: number, at: number }

export type Rates = {
	coralPerHour: number,
	shellsPerHour: number,
	hours: number, -- of growth it holds
	capCoral: number,
	capShells: number,
}

local Garden = {}

-- Growth for a den level, with the Deep Garden pass or without.
function Garden.rates(level: number, deep: boolean): Rates
	local index = math.clamp(level, 1, #tune.coral)
	local speed = if deep then deepGarden.rate else 1
	local hours = if deep then deepGarden.hours else tune.hours
	local coral = tune.coral[index] * speed
	local shells = tune.shells[index] * speed
	return {
		coralPerHour = coral,
		shellsPerHour = shells,
		hours = hours,
		capCoral = coral * hours,
		capShells = shells * hours,
	}
end

-- Grows a record up to `now` (Unix seconds) at `multiplier` × its rate, never past
-- what it holds. A record that has never grown starts now. Returns the seconds that
-- passed.
function Garden.grow(record: Record, rates: Rates, now: number, multiplier: number): number
	if record.at <= 0 then
		record.at = now
		return 0
	end
	local seconds = math.max(0, now - record.at)
	record.at = now
	local hours = seconds / 3600 * multiplier
	record.coral = math.min(rates.capCoral, record.coral + rates.coralPerHour * hours)
	record.shells = math.min(rates.capShells, record.shells + rates.shellsPerHour * hours)
	return seconds
end

-- How full it is, 0..1, by coral.
function Garden.fill(record: Record, rates: Rates): number
	return if rates.capCoral > 0 then math.clamp(record.coral / rates.capCoral, 0, 1) else 0
end

return Garden
