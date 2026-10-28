-- Checks Shared/Aquarium (run_aquarium.sh): rates by rarity, the 12-hour cap, a fed
-- day's share of the growth, and which catches can go in a tank.
local Config = require("./Config")
local Aquarium = require("./Aquarium")

local tune = Config.Dens.aquarium
local failures = 0
local function expect(ok: boolean, what: string)
	if not ok then
		failures += 1
		print("FAIL: " .. what)
	end
end
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6 * math.max(1, math.abs(b))
end

local stock = {
	base1 = { prey = "Minnow", rarity = "Golden" },
	base2 = { prey = "Sardine", rarity = "Silver" },
	gone = { prey = "Minnow", rarity = "Prism" },
}
local open = { base1 = true, base2 = true }
local rates = Aquarium.rates(stock, open)
expect(rates.stocked == 2, "a tank a wing took doesn't count")
expect(rates.coralPerHour == tune.rates.Golden.coral + tune.rates.Silver.coral, "coral an hour by rarity")
expect(rates.capCoral == rates.coralPerHour * tune.hours, "holds 12 hours")

-- Unfed: 3 hours grow 3 hours' worth; a long time away stops at the cap
local day = 20000
local start = day * 86400 + 3600
local record = { coral = 0, shells = 0, at = start, fed = 0 }
Aquarium.grow(record, rates, start + 3 * 3600)
expect(near(record.coral, rates.coralPerHour * 3), "3 hours unfed")
Aquarium.grow(record, rates, start + 40 * 3600)
expect(near(record.coral, rates.capCoral), "capped at 12 hours")

-- Fed today: ×1.5 until midnight, ×1 after it
record = { coral = 0, shells = 0, at = start, fed = day }
expect(Aquarium.fedToday(record, start), "fed today")
local midnight = (day + 1) * 86400
Aquarium.grow(record, rates, midnight + 3600)
local fedHours = (midnight - start) / 3600
local expected = math.min(rates.capCoral, rates.coralPerHour * (fedHours * tune.feed.multiplier + 1))
expect(near(record.coral, expected), `a fed day's share ({record.coral} vs {expected})`)
expect(not Aquarium.fedToday(record, midnight + 10), "a new day isn't fed")

-- Stocking: rare catches only, as many tanks as caught
local log = { Minnow = { Golden = 2, Normal = 30 }, Sardine = { Silver = 1 } }
local tanks = { base1 = { prey = "Minnow", rarity = "Golden" } }
expect(Aquarium.canStock(log, tanks, "base2", "Minnow", "Golden") == nil, "a second Golden Minnow (2 caught)")
tanks.base2 = { prey = "Minnow", rarity = "Golden" }
expect(Aquarium.canStock(log, tanks, "base3", "Minnow", "Golden") ~= nil, "not a third (2 caught)")
expect(Aquarium.canStock(log, tanks, "base1", "Minnow", "Golden") == nil, "re-stocking a tank with its own fish")
expect(Aquarium.canStock(log, tanks, "base3", "Minnow", "Normal") ~= nil, "a plain catch doesn't earn")
expect(Aquarium.canStock(log, tanks, "base3", "Sardine", "Crystal") ~= nil, "one not caught")
expect(Aquarium.feedCost(Aquarium.rates(tanks, nil)) == 2 * tune.feed.dna, "feeding costs a DNA a tank")

-- What a full aquarium earns: the base tanks at a Sanctum plus the Aquarium Hall's
local full = tune.base + 5 + tune.hall
for _, rarity in Config.Catch.rarities do
	local rate = tune.rates[rarity.id]
	expect(rate ~= nil, `{rarity.id} has a rate`)
	if rate then
		print(`{rarity.id}: {rate.coral} coral/h a tank · {full} tanks {rate.coral * full}/h, 12 h {rate.coral * full * tune.hours}`)
	end
end

print(if failures == 0 then "aquarium: OK" else `aquarium: {failures} failed`)
if failures > 0 then
	error("aquarium test failed")
end
