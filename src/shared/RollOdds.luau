--!strict
-- The roll table as exact odds. The server rolls with `pick` and the odds panel
-- shows `table`, both from the same numbers, so what players see is what they get.
--
-- Every shade, body part and variant has a "1 in N" chance; luck multiplies those
-- (coral is never boosted). Coral takes the rest, split by its tiers' shares.
local Config = require(script.Parent.Config)

local Rolls = Config.Rolls

export type Kind = "coral" | "shade" | "part" | "variant"

export type Outcome = {
	id: string,
	kind: Kind,
	name: string,
	tier: string,
	chance: number?, -- "1 in N" before luck (nil for coral)
	amount: number?, -- coral
	share: number?, -- coral: its share of the coral chance
	refund: number?, -- coral a duplicate turns into
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
for _, shade in Config.Shades.list do
	if shade.boss or shade.treasure then
		continue -- boss trophies are won and treasure shades dug up, never rolled
	end
	table.insert(outcomes, {
		id = shade.id,
		kind = "shade",
		name = `{shade.name} Shade`,
		tier = shade.tier,
		chance = shade.chance,
		refund = shade.refund,
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

-- Every outcome with its probability for one roll at `luck` (1 = normal). The
-- probabilities add up to exactly 1.
function RollOdds.table(luck: number): { Odds }
	local special = 0
	for _, outcome in outcomes do
		if outcome.chance then
			special += luck / outcome.chance
		end
	end
	-- Luck can't push coral below its floor: scale the specials down if it would
	local scale = math.min(1, (1 - Rolls.minCoralShare) / math.max(special, 1e-12))
	local coralTotal = 1 - special * scale
	local result: { Odds } = {}
	for _, outcome in outcomes do
		local probability = if outcome.chance
			then luck / outcome.chance * scale
			else coralTotal * (outcome.share or 0)
		table.insert(result, { outcome = outcome, probability = probability })
	end
	return result
end

-- Picks an outcome for a uniform random number `r` in [0, 1).
function RollOdds.pick(luck: number, r: number): Outcome
	local odds = RollOdds.table(luck)
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
