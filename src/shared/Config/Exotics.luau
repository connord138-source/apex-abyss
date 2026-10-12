--!strict
-- The rarest roll outcomes: body parts (worn in a slot, one per slot) and exotic
-- body variants (reshape the whole fish). Their geometry lives in
-- Shared/Cosmetics.luau under the same ids. `chance` is "1 in N" per roll.
export type Part = {
	id: string,
	name: string,
	slot: string, -- "Head" | "Back" | "Tail"
	chance: number,
	refund: number,
	blurb: string,
}

export type Variant = {
	id: string,
	name: string,
	species: string, -- exotic variants reshape one species only (Config/Species)
	chance: number,
	refund: number,
	blurb: string,
}

local parts: { Part } = {
	{
		id = "AnglerLure",
		name = "Angler Lure",
		slot = "Head",
		chance = 4000,
		refund = 15000,
		blurb = "A glowing lure on a stalk. Lights the trench.",
	},
	{
		id = "NarwhalHorn",
		name = "Narwhal Horn",
		slot = "Head",
		chance = 5000,
		refund = 18000,
		blurb = "A long spiral horn.",
	},
	{
		id = "SawSnout",
		name = "Sawblade Snout",
		slot = "Head",
		chance = 6000,
		refund = 20000,
		blurb = "A toothed blade for a nose.",
	},
	{
		id = "SailFin",
		name = "Sail Fin",
		slot = "Back",
		chance = 5000,
		refund = 18000,
		blurb = "A towering sail along the back.",
	},
	{
		id = "VeilTail",
		name = "Veil Tail",
		slot = "Tail",
		chance = 5000,
		refund = 18000,
		blurb = "A long, flowing see-through tail.",
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
	},
	{
		id = "Hammerhead",
		name = "Hammerhead",
		species = "ReefShark",
		chance = 10000,
		refund = 30000,
		blurb = "A wide hammer head with eyes at the tips.",
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
	},
	{
		id = "Porcupine",
		name = "Porcupine Puffer",
		species = "Pufferfish",
		chance = 9000,
		refund = 28000,
		blurb = "Puffed up for good, bristling with long bone quills. Nothing wants a mouthful of it.",
	},
	{
		id = "DragonMoray",
		name = "Dragon Moray",
		species = "MorayEel",
		chance = 9000,
		refund = 28000,
		blurb = "Horned, with a frilled crest the whole length of its back. The real dragon of the ruins.",
	},
	{
		id = "Deepfang",
		name = "Deepfang Angler",
		species = "Anglerfish",
		chance = 9000,
		refund = 28000,
		blurb = "A crown of three lures and fangs it can't close its mouth over. Lights up a trench.",
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
