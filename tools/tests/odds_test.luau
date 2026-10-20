-- Roll odds check (run with run_odds.sh): every fish's outcome table adds up to
-- exactly 100% (paid random items must show exact odds), holds only that fish's own
-- skin line (owner, 2026-10-10) plus the skins every fish rolls (the treasure shades,
-- 2026-10-20), and two million sample rolls land where the table says.
local RollOdds = require("./RollOdds")
local Config = require("./Config")

local SPECIES = { "Nibbler", "Cuda", "Pufferfish", "MorayEel", "ReefShark", "Anglerfish" }
-- Skins every fish rolls (the treasure shades)
local UNIVERSAL = 0
for _, shade in Config.Shades.list do
	if shade.species == nil and Config.Shades.rollable(shade) then
		UNIVERSAL += 1
	end
end
assert(UNIVERSAL == 2, `expected the two treasure shades to roll on every fish, got {UNIVERSAL}`)

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
			assert(
				e.outcome.species == nil or e.outcome.species == species,
				`{species} rolls another fish's skin {e.outcome.id}`
			)
			local shade = Config.Shades.byId[e.outcome.id]
			assert(
				not (shade.boss or shade.catch or shade.week or shade.pass),
				`{e.outcome.id} is won or earned, never rolled`
			)
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
	assert(skins == 12 + UNIVERSAL, `{species} should roll its 12 line skins and {UNIVERSAL} more, got {skins}`)
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
-- A skin the fish has drops out of its table and its share goes to the rest of its
-- tier (owner, 2026-10-20): the total is still exactly 100%, each tier's share and
-- coral's are unchanged while the tier has a skin left, and a finished tier's share
-- becomes coral
local function tiers(owned)
	local byTier, coral, total = {}, 0, 0
	for _, e in RollOdds.table(1, owned, "Cuda") do
		total += e.probability
		if e.outcome.kind == "coral" then
			coral += e.probability
		elseif e.outcome.kind == "shade" then
			assert(not (owned and owned[e.outcome.id]), "an owned shade is still in the table")
			byTier[e.outcome.tier] = (byTier[e.outcome.tier] or 0) + e.probability
		end
	end
	assert(math.abs(total - 1) < 1e-9, "per-fish odds must add to 100%")
	return byTier, coral
end
local baseTiers, baseCoral = tiers(nil)
-- Three of the four Commons and one Uncommon owned: the Common and Uncommon shares hold
local owned, ownedCount = {}, 0
local commons, uncommons = 0, 0
for _, shade in Config.Shades.lines.Cuda do
	if shade.tier == "Common" and commons < 3 then
		owned[shade.id], commons, ownedCount = true, commons + 1, ownedCount + 1
	elseif shade.tier == "Uncommon" and uncommons < 1 then
		owned[shade.id], uncommons, ownedCount = true, uncommons + 1, ownedCount + 1
	end
end
local someTiers, someCoral = tiers(owned)
for tier, share in baseTiers do
	assert(math.abs((someTiers[tier] or 0) - share) < 1e-12, `{tier}'s share moved with skins left in it`)
end
assert(math.abs(someCoral - baseCoral) < 1e-12, "coral moved while every tier had a skin left")
for _ = 1, 200000 do
	local o = RollOdds.pick(1, math.random(), owned, "Cuda")
	assert(not (o.kind == "shade" and owned[o.id]), "an owned shade was rolled")
end
-- Every Common owned: the Common share becomes coral, every other tier's holds
local allCommons = table.clone(owned)
for _, shade in Config.Shades.lines.Cuda do
	if shade.tier == "Common" then
		allCommons[shade.id] = true
	end
end
local doneTiers, doneCoral = tiers(allCommons)
assert(doneTiers.Common == nil, "a finished tier still rolls")
assert(math.abs(doneCoral - (baseCoral + baseTiers.Common)) < 1e-12, "a finished tier's share should be coral")
for tier, share in baseTiers do
	if tier ~= "Common" then
		assert(math.abs((doneTiers[tier] or 0) - share) < 1e-12, `{tier}'s share moved`)
	end
end
print(
	string.format(
		"per-fish: %d owned, tiers and coral hold (coral %.4f%%); every Common owned: coral %.4f%%",
		ownedCount,
		someCoral * 100,
		doneCoral * 100
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
