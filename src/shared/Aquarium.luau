--!strict
-- The den's aquarium (Config/Dens aquarium; the proposal's passive element, approved
-- 2026-10-28): what a den's stocked tanks earn an hour, how much they hold, growing a
-- saved record up to a moment (a fed day earns more), and whether a catch can go in a
-- tank. Shared so the server (AquariumService) and the den menu agree, and pure
-- enough for the luau CLI (tools/tests/run_aquarium.sh).
local Config = require(script.Parent.Config)

local tune = Config.Dens.aquarium

export type Record = { coral: number, shells: number, at: number, fed: number }
export type Stock = { [string]: { prey: string, rarity: string } }
export type Rates = {
	coralPerHour: number, -- unfed
	shellsPerHour: number,
	capCoral: number, -- what it holds (`hours` of the unfed rate: a fed day fills it sooner)
	capShells: number,
	stocked: number, -- tanks with a fish
}

local Aquarium = {}

local DAY = 86400

-- The UTC day a Unix time falls in
function Aquarium.day(unix: number): number
	return math.floor(unix / DAY)
end

-- Whether the tanks were fed today
function Aquarium.fedToday(record: Record, now: number): boolean
	return record.fed == Aquarium.day(now) and record.fed > 0
end

-- What the stocked tanks earn an hour, and hold (`open`: the tank ids the den has,
-- so a fish left in a tank a wing took with it doesn't count)
function Aquarium.rates(stock: Stock, open: { [string]: boolean }?): Rates
	local coral, shells, stocked = 0, 0, 0
	for id, fish in stock do
		if open and not open[id] then
			continue
		end
		local rate = tune.rates[fish.rarity]
		if rate then
			coral += rate.coral
			shells += rate.shells
			stocked += 1
		end
	end
	return {
		coralPerHour = coral,
		shellsPerHour = shells,
		capCoral = coral * tune.hours,
		capShells = shells * tune.hours,
		stocked = stocked,
	}
end

-- Grows a record up to `now` (Unix seconds), never past what it holds: the part of
-- the time on a fed day at ×`feed.multiplier`. A record that has never grown starts
-- now. Returns the seconds that passed.
function Aquarium.grow(record: Record, rates: Rates, now: number): number
	if record.at <= 0 then
		record.at = now
		return 0
	end
	local seconds = math.max(0, now - record.at)
	local fedHours = 0
	if record.fed > 0 then
		-- the fed day's share of [at, now]
		local from = math.max(record.at, record.fed * DAY)
		local to = math.min(now, (record.fed + 1) * DAY)
		fedHours = math.max(0, to - from) / 3600
	end
	local hours = seconds / 3600 - fedHours + fedHours * tune.feed.multiplier
	record.at = now
	record.coral = math.min(rates.capCoral, record.coral + rates.coralPerHour * hours)
	record.shells = math.min(rates.capShells, record.shells + rates.shellsPerHour * hours)
	return seconds
end

-- How many of a catch (a prey at a rarity) are in tanks, but for `except`
function Aquarium.inTanks(stock: Stock, prey: string, rarity: string, except: string?): number
	local count = 0
	for id, fish in stock do
		if id ~= except and fish.prey == prey and fish.rarity == rarity then
			count += 1
		end
	end
	return count
end

-- Whether a catch can go in tank `tank`: a rare one (it earns), and one more of it
-- caught (the Catch Log) than are already in other tanks. Nil when it can, else why.
function Aquarium.canStock(
	catchLog: { [string]: { [string]: number } },
	stock: Stock,
	tank: string,
	prey: string,
	rarity: string
): string?
	if tune.rates[rarity] == nil then
		return "Only rare catches go in the tanks"
	end
	if Config.Prey.byId[prey] == nil then
		return "No such fish"
	end
	local caught = (catchLog[prey] or {})[rarity] or 0
	if caught <= 0 then
		return "You haven't caught that one yet"
	end
	if Aquarium.inTanks(stock, prey, rarity, tank) >= caught then
		return `You've caught {caught} · they're all in tanks already`
	end
	return nil
end

-- DNA feeding costs: `feed.dna` of `feed.biome`'s a stocked tank
function Aquarium.feedCost(rates: Rates): number
	return rates.stocked * tune.feed.dna
end

return Aquarium
