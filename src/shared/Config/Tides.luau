--!strict
-- The Tide Clock (owner, 2026-10-10: "we are still missing that pull back element").
-- The sea changes every 20 minutes on one world clock, the same on every server, so
-- players learn the schedule and come back for the tide they want: Golden Hour for
-- gold, Bioluminescent Night for glowing fish, and the Prism Tide, four times a day,
-- the only time Prism fish swim (Shared/Tides works out which tide is when;
-- Config/Catch has the rare catches the tides boost).
export type Tide = {
	id: string,
	name: string,
	blurb: string, -- one line for the chip and the forecast
	weight: number, -- how often it comes up (0 = only when scheduled)
	color: Color3, -- the chip, the banner and a faint tint in the water
	tint: number, -- how strongly the water takes its color (0..1)
	-- Rare catch chances × this (Config/Catch rarity id → multiplier); a rarity with
	-- `tide` set only spawns while that tide is up
	rarity: { [string]: number },
	haul: number?, -- every Haul gain × this
	smallHaul: number?, -- prey under `smallMass` kg × this (the Sardine Run)
	coral: number?, -- coral from rare catches × this
	hunters: { speed: number, aggro: number }?, -- AI predators faster and keener
	schools: boolean?, -- its own schools come out (Config/Prey zones with `tide`)
}

local list: { Tide } = {
	{
		id = "Calm",
		name = "Calm Waters",
		blurb = "A quiet sea. Rare fish at their usual odds.",
		weight = 4,
		color = Color3.fromRGB(120, 200, 230),
		tint = 0,
		rarity = {},
	},
	{
		id = "Golden",
		name = "Golden Hour",
		blurb = "Golden fish ×5 · coral from rare catches ×1.5",
		weight = 2,
		color = Color3.fromRGB(255, 196, 70),
		tint = 0.12,
		rarity = { Golden = 5 },
		coral = 1.5,
	},
	{
		id = "Blood",
		name = "Blood Tide",
		blurb = "Rare fish ×2 · Haul ×1.25 · hunters faster and hungrier",
		weight = 2,
		color = Color3.fromRGB(230, 60, 70),
		tint = 0.14,
		rarity = { Golden = 2, Glowing = 2, Crystal = 2 },
		haul = 1.25,
		hunters = { speed = 1.2, aggro = 1.5 },
	},
	{
		id = "Sardine",
		name = "Sardine Run",
		blurb = "Bait balls flood the shallows · small fish Haul ×1.5",
		weight = 2,
		color = Color3.fromRGB(170, 230, 255),
		tint = 0.06,
		rarity = { Golden = 1.5 },
		smallHaul = 1.5,
		schools = true,
	},
	{
		id = "Biolum",
		name = "Bioluminescent Night",
		blurb = "Glowing fish ×3 (×5 out in the deep) · the sea goes dark",
		weight = 2,
		color = Color3.fromRGB(70, 230, 210),
		tint = 0.18,
		rarity = { Glowing = 3 },
	},
	{
		id = "Prism",
		name = "Prism Tide",
		blurb = "Prism fish swim · every rare fish ×2",
		weight = 0,
		color = Color3.fromRGB(255, 120, 230),
		tint = 0.1,
		rarity = { Golden = 2, Glowing = 2, Crystal = 2, Prism = 1 },
	},
}

local byId: { [string]: Tide } = {}
for _, tide in list do
	byId[tide.id] = tide
end

return {
	list = list,
	byId = byId,
	slotSeconds = 1200, -- a tide lasts 20 minutes, on the :00, :20 and :40
	-- The Prism Tide: every `every`th slot at `at` (every 6 h at 03:00, 09:00, 15:00
	-- and 21:00 UTC)
	prism = { id = "Prism", every = 18, at = 9 },
	seed = 20261010, -- which tide each slot gets (the same on every server)
	smallMass = 1, -- kg: the Sardine Run's small fish
	deepGlow = 5 / 3, -- Bioluminescent Night: Glowing ×this more in the deep biomes
	announceAhead = 120, -- seconds: the toast before a Prism Tide
}
