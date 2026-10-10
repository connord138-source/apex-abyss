-- Roll odds check (run with run_odds.sh): every fish's outcome table adds up to
-- exactly 100% (paid random items must show exact odds), holds only that fish's own
-- skin line (owner, 2026-10-10), and two million sample rolls land where the table
-- says.
local RollOdds = require("./RollOdds")
local Config = require("./Config")

local SPECIES = { "Nibbler", "Cuda", "Pufferfish", "MorayEel", "ReefShark", "Anglerfish" }

local function check(luck, species)
	local total, coral, special, skins = 0, 0, 0, 0
	for _, e in RollOdds.table(luck, nil, species) do
		total += e.probability
		if e.outcome.kind == "coral" then
			coral += e.probability
		else
			special += e.probability
		end
		if e.outcome.kind == "shade" then
			skins += 1
			assert(e.outcome.species == species, `{species} rolls another fish's skin {e.outcome.id}`)
		end
	end
	print(
		string.format(
			"%-11s luck %d: total=%.12f coral=%.4f%% special=%.4f%% skins=%d",
			species,
			luck,
			total,
			coral * 100,
			special * 100,
			skins
		)
	)
	assert(math.abs(total - 1) < 1e-9, "odds must add to 100%")
	assert(skins == 12, `{species} should roll its 12 line skins, got {skins}`)
end
for _, species in SPECIES do
	check(1, species)
	check(2, species)
	assert(#Config.Shades.lines[species] == 12, `{species}'s line isn't 12`)
end
for _, e in RollOdds.table(1, nil, "Cuda") do
	print(
		string.format(
			"  %-22s %-10s %10s  %s",
			e.outcome.name,
			e.outcome.tier,
			RollOdds.percent(e.probability),
			RollOdds.oneIn(e.probability)
		)
	)
end
-- Sampling agrees with the table
local counts, n = {}, 2000000
math.randomseed(7)
for _ = 1, n do
	local o = RollOdds.pick(1, math.random(), nil, "Cuda")
	counts[o.id] = (counts[o.id] or 0) + 1
end
for _, e in RollOdds.table(1, nil, "Cuda") do
	local got = (counts[e.outcome.id] or 0) / n
	if e.probability > 0.005 then
		assert(math.abs(got - e.probability) / e.probability < 0.02, e.outcome.id .. " sampling off")
	end
end
print("sampling OK")
-- A skin the fish has drops out of its table, the total is still exactly 100%,
-- every other non-coral chance is unchanged, and coral takes the freed share
local owned = {}
local ownedCount = 0
for _, e in RollOdds.table(1, nil, "Cuda") do
	if e.outcome.kind == "shade" and ownedCount < 6 then
		owned[e.outcome.id] = true
		ownedCount += 1
	end
end
local base = {}
local baseCoral, withoutCoral, total = 0, 0, 0
for _, e in RollOdds.table(1, nil, "Cuda") do
	base[e.outcome.kind .. ":" .. e.outcome.id] = e.probability
	if e.outcome.kind == "coral" then
		baseCoral += e.probability
	end
end
for _, e in RollOdds.table(1, owned, "Cuda") do
	assert(not (e.outcome.kind == "shade" and owned[e.outcome.id]), "an owned shade is still in the table")
	total += e.probability
	if e.outcome.kind == "coral" then
		withoutCoral += e.probability
	else
		local key = e.outcome.kind .. ":" .. e.outcome.id
		assert(math.abs(e.probability - base[key]) < 1e-12, key .. " changed when shades were excluded")
	end
end
assert(math.abs(total - 1) < 1e-9, "per-fish odds must add to 100%")
assert(withoutCoral > baseCoral, "coral should take the excluded shades' share")
for _ = 1, 200000 do
	local o = RollOdds.pick(1, math.random(), owned, "Cuda")
	assert(not (o.kind == "shade" and owned[o.id]), "an owned shade was rolled")
end
print(
	string.format(
		"per-fish: %d owned shades out, total=%.12f, coral %.4f%% -> %.4f%%",
		ownedCount,
		total,
		baseCoral * 100,
		withoutCoral * 100
	)
)
-- Every skin fits only its own fish (and the universal ones every fish)
for _, shade in Config.Shades.list do
	for _, species in SPECIES do
		local fits = Config.Shades.fits(shade.id, species)
		assert(fits == (shade.species == nil or shade.species == species), `fits({shade.id}, {species})`)
	end
end
print("odds_test: OK")
