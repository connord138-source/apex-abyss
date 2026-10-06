-- Roll odds check (run with run_odds.sh): every outcome table adds up to exactly
-- 100% (paid random items must show exact odds), and two million sample rolls
-- land where the table says.
local RollOdds = require("./RollOdds")
local function check(luck)
	local total, coral, special = 0, 0, 0
	for _, e in RollOdds.table(luck) do
		total += e.probability
		if e.outcome.kind == "coral" then coral += e.probability else special += e.probability end
	end
	print(string.format("luck %d: total=%.12f coral=%.4f%% special=%.4f%%", luck, total, coral*100, special*100))
	assert(math.abs(total - 1) < 1e-9, "odds must add to 100%")
end
check(1); check(2)
for _, e in RollOdds.table(1) do
	print(string.format("  %-22s %-10s %10s  %s", e.outcome.name, e.outcome.tier, RollOdds.percent(e.probability), RollOdds.oneIn(e.probability)))
end
-- Sampling agrees with the table
local counts, n = {}, 2000000
local rng = math.random
math.randomseed(7)
for _ = 1, n do
	local o = RollOdds.pick(1, rng())
	counts[o.id] = (counts[o.id] or 0) + 1
end
for _, e in RollOdds.table(1) do
	local got = (counts[e.outcome.id] or 0) / n
	if e.probability > 0.005 then
		assert(math.abs(got - e.probability) / e.probability < 0.02, e.outcome.id .. " sampling off")
	end
end
print("sampling OK")
