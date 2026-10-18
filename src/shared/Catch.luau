--!strict
-- Rare catches (Config/Catch), shared by the server (which spawns and pays) and the
-- client (the Catch Logbook, the INDEX, the tides). Pure: no Roblox services, so the
-- luau CLI tests it (tools/tests/run_catch.sh, run_tides.sh).
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

-- How much more often tide `tideId` sets rarity `rarityId` swimming (Config/Tides
-- `rarity`), with a Bioluminescent Night's deep glow for a player in a deep biome.
-- 0 for a tide's own rarity outside it.
function Catch.tideBoost(rarityId: string, tideId: string, deep: boolean): number
	local rarity = CatchConfig.byId[rarityId]
	if rarity == nil or (rarity.tide and rarity.tide ~= tideId) then
		return 0
	end
	local tide = TideConfig.byId[tideId]
	local boost = if tide then tide.rarity[rarityId] or 1 else 1
	if deep and tideId == "Biolum" and rarityId == "Glowing" then
		boost *= TideConfig.deepGlow
	end
	return boost
end

-- Rare fish of `rarityId` set swimming a minute round one player out in the biomes
-- (Shared/RareSpawn) while tide `tideId` is up, `sinceTide` seconds into it: the
-- rarity's rate × the tide's boost, and early in a tide the rarities it boosts come
-- ×`spawn.rush.boost` so its fish show up soon
function Catch.rate(rarityId: string, tideId: string, deep: boolean, sinceTide: number): number
	local rarity = CatchConfig.byId[rarityId]
	local boost = Catch.tideBoost(rarityId, tideId, deep)
	if rarity == nil or boost == 0 then
		return 0
	end
	local rush = CatchConfig.spawn.rush
	if sinceTide < rush.seconds and (boost > 1 or rarity.tide == tideId) then
		boost *= rush.boost
	end
	return rarity.rate * boost
end

-- This week's Catch of the Week and its own spawn rate (a minute, round one player
-- near where its species swims): `weekly.rate` × the tide's boost on its rarity
function Catch.weeklyRate(unix: number, tideId: string, deep: boolean): (CatchConfig.Weekly?, number)
	local featured = Catch.weekly(unix)
	if featured == nil then
		return nil, 0
	end
	return featured, CatchConfig.weekly.rate * Catch.tideBoost(featured.rarity, tideId, deep)
end

-- The coral a rare catch pays (before the tide's and the player's multipliers)
function Catch.coral(rarityId: string, mass: number): number
	local rarity = CatchConfig.byId[rarityId]
	if rarity == nil then
		return 0
	end
	return math.max(rarity.coralMin, math.floor(mass * rarity.coralPerKg))
end

-- A rarity's skin goal against a Catch Log (prey id → rarity id → lifetime catches):
-- how many species have `unlock.each` or more, those species (most caught first,
-- then by name), whether the goal is met, and every species caught at that rarity at
-- all with its count (for "3 / 10" next to each)
function Catch.goal(
	log: { [string]: { [string]: number } }?,
	rarityId: string
): (number, { string }, boolean, { [string]: number })
	local rarity = CatchConfig.byId[rarityId]
	local counted: { string } = {}
	local counts: { [string]: number } = {}
	if rarity == nil or log == nil then
		return 0, counted, false, counts
	end
	for preyId, row in log do
		local count = if typeof(row) == "table" then row[rarityId] or 0 else 0
		if typeof(count) == "number" and count > 0 then
			counts[preyId] = count
			if count >= rarity.unlock.each then
				table.insert(counted, preyId)
			end
		end
	end
	table.sort(counted, function(a, b)
		if counts[a] ~= counts[b] then
			return counts[a] > counts[b]
		end
		return a < b
	end)
	return #counted, counted, #counted >= rarity.unlock.species, counts
end

-- The rarities whose skin goals a Catch Log has met
function Catch.met(log: { [string]: { [string]: number } }?): { string }
	local result: { string } = {}
	for _, rarity in CatchConfig.rarities do
		local _, _, done = Catch.goal(log, rarity.id)
		if done then
			table.insert(result, rarity.id)
		end
	end
	return result
end

-- Which catch skins a save should have on every fish (the account-wide rule, owner
-- 2026-10-18): every goal its Catch Log has met, and any catch skin one of its fish
-- already earned on the old per-fish catch tracks (nothing is ever taken away).
-- `owned` is each species' shade set (species id → shade id → true).
function Catch.accountSkins(
	log: { [string]: { [string]: number } }?,
	owned: { [string]: { [string]: boolean }? }
): { string }
	local skins: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, rarity in CatchConfig.rarities do
		local _, _, done = Catch.goal(log, rarity.id)
		local had = false
		for _, shades in owned do
			if shades and shades[rarity.skin] then
				had = true
				break
			end
		end
		if (done or had) and not seen[rarity.skin] then
			seen[rarity.skin] = true
			table.insert(skins, rarity.skin)
		end
	end
	return skins
end

-- Whether a Catch Log row is done: the prey caught plain and at every rarity
-- (Silver joined the row on 2026-10-18; a row paid before that stays paid)
function Catch.rowDone(row: { [string]: number }): boolean
	if (row.Normal or 0) == 0 then
		return false
	end
	for _, rarity in CatchConfig.rarities do
		if (row[rarity.id] or 0) == 0 then
			return false
		end
	end
	return true
end

return Catch
