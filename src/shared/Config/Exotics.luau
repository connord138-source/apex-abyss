--!strict
-- The rarest roll outcomes: body parts (worn in a slot, one per slot) and exotic
-- body variants (reshape the whole fish). Their geometry lives in
-- Shared/Cosmetics.luau under the same ids (a Tripo model each since 2026-10-21:
-- ReplicatedStorage.PartModels / VariantModels, part-built until imported), and how
-- each part's model sits on and is tinted to each fish in Shared/PartFit.luau. `chance`
-- is "1 in N" per roll.
--
-- Each also does a little for its fish (owner, 2026-10-21, with the approved parts and
-- variants boards): a modest `bonus`, never bite damage, that Shared/Perks.exotic reads
-- for both the client and the server's checks. `kind` says what it boosts:
--   reach     how far small prey are swallowed from (× the suction reach)
--   dash      how long a Dash or a Torpedo runs, so how far it carries
--   find      how far shells are picked up and a treasure's X shows from
--   speed     top speed (SpeedService allows it)
--   turn      turn rate
--   recharge  `ability`'s recharge (its cooldown ÷ this)
--   duration  how long `ability` lasts
--   range     how far `ability` reaches
export type Bonus = {
	kind: string,
	amount: number, -- × the thing it boosts
	ability: string?, -- recharge, duration, range: the Config/Abilities id
	text: string, -- what it does, for the Wardrobe and the Index
}

export type Part = {
	id: string,
	name: string,
	slot: string, -- "Head" | "Back" | "Tail"
	chance: number,
	refund: number,
	blurb: string,
	bonus: Bonus,
}

export type Variant = {
	id: string,
	name: string,
	species: string, -- exotic variants reshape one species only (Config/Species)
	chance: number,
	refund: number,
	blurb: string,
	bonus: Bonus,
}

local parts: { Part } = {
	{
		id = "AnglerLure",
		name = "Angler Lure",
		slot = "Head",
		chance = 4000,
		refund = 15000,
		blurb = "A glowing lure on a stalk. Lights the trench.",
		bonus = {
			kind = "reach",
			amount = 1.25,
			text = "Lights dark water, and small prey drift into your mouth: +25% swallow reach",
		},
	},
	{
		id = "NarwhalHorn",
		name = "Narwhal Horn",
		slot = "Head",
		chance = 5000,
		refund = 18000,
		blurb = "A long spiral horn.",
		bonus = { kind = "dash", amount = 1.2, text = "Your Dash (or Torpedo) carries 20% further" },
	},
	{
		id = "SawSnout",
		name = "Sawblade Snout",
		slot = "Head",
		chance = 6000,
		refund = 20000,
		blurb = "A toothed blade for a nose.",
		bonus = {
			kind = "find",
			amount = 1.5,
			text = "Rakes the sand: shells and treasure found from 50% further",
		},
	},
	{
		id = "SailFin",
		name = "Sail Fin",
		slot = "Back",
		chance = 5000,
		refund = 18000,
		blurb = "A towering sail along the back.",
		bonus = { kind = "speed", amount = 1.05, text = "+5% top speed" },
	},
	{
		id = "VeilTail",
		name = "Veil Tail",
		slot = "Tail",
		chance = 5000,
		refund = 18000,
		blurb = "A long, flowing see-through tail.",
		bonus = { kind = "turn", amount = 1.15, text = "Turns 15% tighter" },
	},
}

local variants: { Variant } = {
	{
		id = "Puffball",
		name = "Puffball Nibbler",
		species = "Nibbler",
		chance = 8000,
		refund = 25000,
		blurb = "A Nibbler that ate too much air. Round, spiky and very proud of it.",
		bonus = { kind = "recharge", ability = "Dash", amount = 1.2, text = "Dash recharges 20% faster" },
	},
	{
		id = "Hammerhead",
		name = "Hammerhead",
		species = "ReefShark",
		chance = 10000,
		refund = 30000,
		blurb = "A wide hammer head with eyes at the tips.",
		bonus = {
			kind = "range",
			ability = "BloodSense",
			amount = 1.25,
			text = "Blood Sense reaches 25% further",
		},
	},
	-- One for every playable fish (owner, 2026-10-12: "Variants should also be
	-- different/upgrades from the original base fish as well. For all playable
	-- models"). Each rolls only for its own fish (RollOdds).
	{
		id = "Sabrecuda",
		name = "Sabrecuda",
		species = "Cuda",
		chance = 9000,
		refund = 28000,
		blurb = "A 'Cuda with two sabre fangs and a ridge of spines down its back. Longer, meaner.",
		bonus = { kind = "duration", ability = "Torpedo", amount = 1.25, text = "Torpedo lasts 25% longer" },
	},
	{
		id = "Porcupine",
		name = "Porcupine Puffer",
		species = "Pufferfish",
		chance = 9000,
		refund = 28000,
		blurb = "Puffed up for good, bristling with long bone quills. Nothing wants a mouthful of it.",
		bonus = { kind = "duration", ability = "PuffUp", amount = 1.25, text = "Puff Up lasts 25% longer" },
	},
	{
		id = "DragonMoray",
		name = "Dragon Moray",
		species = "MorayEel",
		chance = 9000,
		refund = 28000,
		blurb = "Horned, with a frilled crest the whole length of its back. The real dragon of the ruins.",
		bonus = { kind = "recharge", ability = "Burrow", amount = 1.25, text = "Burrow recharges 25% faster" },
	},
	{
		id = "Deepfang",
		name = "Deepfang Angler",
		species = "Anglerfish",
		chance = 9000,
		refund = 28000,
		blurb = "A crown of three lures and fangs it can't close its mouth over. Lights up a trench.",
		bonus = {
			kind = "range",
			ability = "LanternFlash",
			amount = 1.25,
			text = "Lantern Flash reaches 25% further",
		},
	},
}

local partsById: { [string]: Part } = {}
for _, part in parts do
	partsById[part.id] = part
end
local variantsById: { [string]: Variant } = {}
for _, variant in variants do
	variantsById[variant.id] = variant
end

return {
	parts = parts,
	partsById = partsById,
	variants = variants,
	variantsById = variantsById,
	SLOTS = { "Head", "Back", "Tail" },
}
