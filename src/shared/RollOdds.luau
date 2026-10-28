--!strict
-- The roll table as exact odds. The server rolls with `pick` and the odds panel
-- shows `table`, both from the same numbers, so what players see is what they get.
--
-- Every shade, body part and variant has a "1 in N" chance; luck multiplies those
-- (coral is never boosted). Coral takes the rest, split by its tiers' shares.
--
-- A skin a fish already has never rolls again for it (owner, 2026-10-08); its share
-- goes to the skins of the same tier it hasn't got yet, so each tier's odds hold
-- until the fish has the whole tier, and only then does that tier's share become
-- coral (owner, 2026-10-20: "Ive done about 20 rolls and gotten coral everytime ...
-- obviously drop rates scale with rarity"; owned skins had all turned into coral).
local Config = require(script.Parent.Config)

local Rolls = Config.Rolls

export type Kind = "coral" | "shade" | "part" | "variant" | "shells" | "dna" | "charm" | "map"

export type Outcome = {
	id: string,
	kind: Kind,
	name: string,
	tier: string,
	chance: number?, -- "1 in N" before luck (nil for coral)
	amount: number?, -- coral
	share: number?, -- coral: its share of the coral chance
	refund: number?, -- coral a duplicate turns into
	species: string?, -- a skin: the fish whose line it's in (it only rolls for that fish; nil: every fish's)
	fixed: boolean?, -- a prize (Config/Rolls `prizes`): its chance is fixed, luck doesn't touch it
	charm: string?, -- a charm prize: the Config/Shop charm
	map: string?, -- a map prize: the Config/Treasure tier
}

export type Odds = { outcome: Outcome, probability: number }

local outcomes: { Outcome } = {}
for _, coral in Rolls.coral do
	table.insert(outcomes, {
		id = coral.id,
		kind = "coral",
		name = coral.name,
		tier = "Coral",
		amount = coral.amount,
		share = coral.share,
	})
end
for _, prize in Rolls.prizes do
	table.insert(outcomes, {
		id = prize.id,
		kind = prize.kind,
		name = prize.name,
		tier = prize.tier,
		chance = prize.chance,
		amount = prize.amount,
		refund = prize.refund,
		fixed = true,
		charm = prize.charm,
		map = prize.map,
	})
end
for _, shade in Config.Shades.list do
	-- A fish's own line and the treasure shades roll (Config/Shades.rollable); the
	-- boss trophies are won, and the catch, weekly and Tide Pass skins earned
	if not Config.Shades.rollable(shade) then
		continue
	end
	table.insert(outcomes, {
		id = shade.id,
		kind = "shade",
		name = `{shade.name} Shade`,
		tier = shade.tier,
		chance = shade.chance,
		refund = shade.refund,
		species = shade.species,
	})
end
for _, part in Config.Exotics.parts do
	table.insert(outcomes, {
		id = part.id,
		kind = "part",
		name = part.name,
		tier = "Abyssal",
		chance = part.chance,
		refund = part.refund,
	})
end
for _, variant in Config.Exotics.variants do
	table.insert(outcomes, {
		id = variant.id,
		kind = "variant",
		name = `{variant.name} Variant`,
		tier = "Abyssal",
		chance = variant.chance,
		refund = variant.refund,
		species = variant.species,
	})
end

local byKey: { [string]: Outcome } = {}
for _, outcome in outcomes do
	byKey[`{outcome.kind}:{outcome.id}`] = outcome
end

local RollOdds = {
	outcomes = outcomes,
}

function RollOdds.get(kind: string, id: string): Outcome?
	return byKey[`{kind}:{id}`]
end

-- Whether an outcome is another fish's (a skin or a variant from someone else's line)
local function otherFish(outcome: Outcome, species: string?): boolean
	if outcome.kind ~= "variant" and outcome.kind ~= "shade" then
		return false
	end
	-- (an exotic variant reshapes one fish, Config/Exotics, so it only rolls for it)
	return species ~= nil and outcome.species ~= nil and outcome.species ~= species
end

-- Whether an outcome is out of the table: another fish's, or a skin the fish already
-- has (it never rolls again for it)
local function excluded(outcome: Outcome, owned: { [string]: boolean }?, species: string?): boolean
	if otherFish(outcome, species) then
		return true
	end
	return outcome.kind == "shade" and owned ~= nil and owned[outcome.id] == true
end

-- How much more likely each skin of a tier the fish hasn't finished is: the tier's
-- whole share over the share of the skins still to get (1 with none owned)
local function tierBoosts(owned: { [string]: boolean }?, species: string?): { [string]: number }
	local all: { [string]: number } = {}
	local left: { [string]: number } = {}
	for _, outcome in outcomes do
		if outcome.kind == "shade" and outcome.chance and not otherFish(outcome, species) then
			local share = 1 / outcome.chance
			all[outcome.tier] = (all[outcome.tier] or 0) + share
			if not (owned and owned[outcome.id]) then
				left[outcome.tier] = (left[outcome.tier] or 0) + share
			end
		end
	end
	local boosts: { [string]: number } = {}
	for tier, total in all do
		local rest = left[tier]
		if rest and rest > 0 then
			boosts[tier] = total / rest
		end
	end
	return boosts
end

-- Every outcome with its probability for one roll at `luck` (1 = normal) for a fish
-- of `species` (its own line and the skins every fish can roll), leaving out the
-- skins in `owned` (the rolling fish's) and handing their share to the rest of their
-- tier. The probabilities add up to exactly 1.
function RollOdds.table(luck: number, owned: { [string]: boolean }?, species: string?): { Odds }
	local boosts = tierBoosts(owned, species)
	local function base(outcome: Outcome): number
		local chance = outcome.chance :: number
		local boost = if outcome.kind == "shade" then boosts[outcome.tier] or 1 else 1
		return luck / chance * boost
	end
	local special, fixed = 0, 0
	for _, outcome in outcomes do
		if outcome.fixed then
			fixed += 1 / (outcome.chance :: number)
		elseif outcome.chance and not excluded(outcome, owned, species) then
			special += base(outcome)
		end
	end
	-- Luck can't push coral below its floor: scale the skins, parts and variants down
	-- if it would (the prizes keep their fixed chances)
	local scale = math.min(1, (1 - fixed - Rolls.minCoralShare) / math.max(special, 1e-12))
	local coralTotal = 1 - fixed - special * scale
	local result: { Odds } = {}
	for _, outcome in outcomes do
		if excluded(outcome, owned, species) then
			continue
		end
		local probability = if outcome.fixed
			then 1 / (outcome.chance :: number)
			elseif outcome.chance then base(outcome) * scale
			else coralTotal * (outcome.share or 0)
		table.insert(result, { outcome = outcome, probability = probability })
	end
	return result
end

-- Picks an outcome for a uniform random number `r` in [0, 1).
function RollOdds.pick(luck: number, r: number, owned: { [string]: boolean }?, species: string?): Outcome
	local odds = RollOdds.table(luck, owned, species)
	local total = 0
	for _, entry in odds do
		total += entry.probability
		if r < total then
			return entry.outcome
		end
	end
	return odds[1].outcome -- float rounding at the very top: the commonest coral
end

-- "1 in 1,500" style text for a probability.
function RollOdds.oneIn(probability: number): string
	if probability <= 0 then
		return "—"
	end
	local n = 1 / probability
	if n < 10 then
		return string.format("1 in %.1f", n)
	end
	local rounded = tostring(math.floor(n + 0.5))
	local formatted = rounded:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return `1 in {formatted}`
end

-- A percentage with enough digits to show tiny odds.
function RollOdds.percent(probability: number): string
	local pct = probability * 100
	if pct >= 10 then
		return string.format("%.1f%%", pct)
	elseif pct >= 1 then
		return string.format("%.2f%%", pct)
	elseif pct >= 0.01 then
		return string.format("%.3f%%", pct)
	end
	return string.format("%.4f%%", pct)
end

return RollOdds
