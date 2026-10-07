--!strict
-- Color shades for a fish: worn on any fish, owned per player. Common tints can
-- also be bought from the Shade Dyer; the named shades only come from rolls.
-- `chance` is "1 in N" per roll; `refund` is the coral a duplicate turns into.
-- Add new shades here (and a look in Shared/Cosmetics.luau if it needs effects).
export type Shade = {
	id: string,
	name: string,
	tier: string, -- Config/Tiers
	chance: number,
	refund: number,
	price: number?, -- coral at the Shade Dyer (nil = rolls only)
	back: Color3,
	belly: Color3,
	fin: Color3,
	accent: Color3?, -- the mid-body and tail stalk, for patterned shades
	material: Enum.Material?,
	reflectance: number?,
	transparency: number?,
	glow: Color3?, -- a soft light on the fish
	sparkle: Color3?, -- glints drifting off it
	cycle: boolean?, -- the colors cycle through the rainbow (Prismatic)
	boss: string?, -- won only by beating this world boss (never in rolls)
	treasure: string?, -- found only in this map tier's treasure (never in rolls)
	blurb: string,
}

local function tint(id: string, name: string, back: Color3, belly: Color3, fin: Color3): Shade
	return {
		id = id,
		name = name,
		tier = "Common",
		chance = 100,
		refund = 120,
		price = 1500,
		back = back,
		belly = belly,
		fin = fin,
		blurb = "A fresh tint.",
	}
end

local list: { Shade } = {
	tint(
		"Mint",
		"Mint",
		Color3.fromRGB(120, 214, 176),
		Color3.fromRGB(226, 248, 238),
		Color3.fromRGB(96, 196, 160)
	),
	tint(
		"Sunset",
		"Sunset",
		Color3.fromRGB(255, 132, 84),
		Color3.fromRGB(255, 222, 168),
		Color3.fromRGB(240, 100, 84)
	),
	tint(
		"Ink",
		"Ink",
		Color3.fromRGB(38, 44, 70),
		Color3.fromRGB(122, 132, 162),
		Color3.fromRGB(70, 82, 124)
	),
	tint(
		"Sand",
		"Sand",
		Color3.fromRGB(212, 188, 136),
		Color3.fromRGB(246, 236, 212),
		Color3.fromRGB(188, 158, 108)
	),
	tint(
		"Ember",
		"Ember",
		Color3.fromRGB(196, 58, 40),
		Color3.fromRGB(250, 182, 120),
		Color3.fromRGB(240, 112, 50)
	),
	tint(
		"Lilac",
		"Lilac",
		Color3.fromRGB(166, 136, 220),
		Color3.fromRGB(234, 226, 250),
		Color3.fromRGB(146, 118, 210)
	),
	tint(
		"Moss",
		"Moss",
		Color3.fromRGB(88, 120, 60),
		Color3.fromRGB(200, 216, 160),
		Color3.fromRGB(120, 150, 80)
	),
	tint(
		"Ocean",
		"Ocean",
		Color3.fromRGB(38, 108, 190),
		Color3.fromRGB(200, 230, 250),
		Color3.fromRGB(60, 150, 222)
	),
	{
		id = "Lunar",
		name = "Lunar",
		tier = "Rare",
		chance = 120,
		refund = 1000,
		back = Color3.fromRGB(190, 206, 236),
		belly = Color3.fromRGB(242, 247, 255),
		fin = Color3.fromRGB(150, 172, 228),
		reflectance = 0.15,
		glow = Color3.fromRGB(170, 200, 255),
		sparkle = Color3.fromRGB(220, 236, 255),
		blurb = "Pale moonlight, with a soft glow and drifting stars.",
	},
	{
		id = "Diamond",
		name = "Diamond",
		tier = "Epic",
		chance = 250,
		refund = 2000,
		back = Color3.fromRGB(206, 240, 255),
		belly = Color3.fromRGB(246, 252, 255),
		fin = Color3.fromRGB(176, 224, 250),
		material = Enum.Material.Glass,
		reflectance = 0.35,
		transparency = 0.12,
		sparkle = Color3.fromRGB(255, 255, 255),
		blurb = "Clear crystal that throws sparkles.",
	},
	{
		id = "Divine",
		name = "Divine",
		tier = "Legendary",
		chance = 500,
		refund = 4000,
		back = Color3.fromRGB(255, 244, 214),
		belly = Color3.fromRGB(255, 255, 246),
		fin = Color3.fromRGB(255, 204, 88),
		reflectance = 0.25,
		glow = Color3.fromRGB(255, 220, 140),
		sparkle = Color3.fromRGB(255, 226, 150),
		blurb = "White and gold, wrapped in a warm halo.",
	},
	{
		id = "Exotic",
		name = "Exotic",
		tier = "Mythic",
		chance = 900,
		refund = 7000,
		back = Color3.fromRGB(30, 110, 255),
		belly = Color3.fromRGB(255, 232, 60),
		fin = Color3.fromRGB(255, 108, 30),
		accent = Color3.fromRGB(110, 255, 90),
		reflectance = 0.06,
		sparkle = Color3.fromRGB(180, 255, 120),
		blurb = "Tropical neon in four colors at once.",
	},
	{
		id = "Prismatic",
		name = "Prismatic",
		tier = "Mythic",
		chance = 1500,
		refund = 12000,
		back = Color3.fromRGB(255, 120, 120),
		belly = Color3.fromRGB(255, 240, 240),
		fin = Color3.fromRGB(120, 200, 255),
		reflectance = 0.12,
		glow = Color3.fromRGB(255, 255, 255),
		sparkle = Color3.fromRGB(255, 255, 255),
		cycle = true,
		blurb = "Every color, rolling across the body.",
	},
	-- World boss trophies (owner, 2026-10-06: "specific skins unlocked from beating
	-- them... a pale green ghost skin"). Never rolled.
	{
		id = "Ghost",
		name = "Ghost",
		tier = "Trophy",
		chance = 0,
		refund = 0,
		back = Color3.fromRGB(176, 255, 196),
		belly = Color3.fromRGB(226, 255, 232),
		fin = Color3.fromRGB(140, 240, 170),
		material = Enum.Material.ForceField, -- a shimmering, see-through haunt
		glow = Color3.fromRGB(150, 255, 180),
		sparkle = Color3.fromRGB(200, 255, 210),
		boss = "Megalodon",
		blurb = "Pale green and see-through, like the drowned. Won from the Megalodon.",
	},
	{
		id = "AbyssInk",
		name = "Abyss Ink",
		tier = "Trophy",
		chance = 0,
		refund = 0,
		back = Color3.fromRGB(26, 16, 40),
		belly = Color3.fromRGB(64, 40, 96),
		fin = Color3.fromRGB(130, 64, 210),
		reflectance = 0.1,
		glow = Color3.fromRGB(150, 90, 255),
		sparkle = Color3.fromRGB(110, 230, 255),
		boss = "GiantSquid",
		blurb = "Ink-black with glowing spots. Won from the Giant Squid.",
	},
	-- Treasure-only shades (owner, 2026-10-07: "a super rare skin at a low drop
	-- rate" from treasure maps). Only a Captain's chest holds them. Never rolled.
	{
		id = "SunkenGold",
		name = "Sunken Gold",
		tier = "Mythic",
		chance = 0,
		refund = 2500,
		back = Color3.fromRGB(232, 176, 48),
		belly = Color3.fromRGB(255, 226, 140),
		fin = Color3.fromRGB(196, 132, 28),
		accent = Color3.fromRGB(120, 80, 20),
		material = Enum.Material.Metal,
		reflectance = 0.45,
		glow = Color3.fromRGB(255, 200, 90),
		sparkle = Color3.fromRGB(255, 236, 170),
		treasure = "Captain",
		blurb = "Doubloon gold with a verdigris tail. Dug up from a Captain's chest.",
	},
	{
		id = "DrownedPearl",
		name = "Drowned Pearl",
		tier = "Legendary",
		chance = 0,
		refund = 1500,
		back = Color3.fromRGB(236, 232, 240),
		belly = Color3.fromRGB(255, 252, 250),
		fin = Color3.fromRGB(200, 214, 236),
		accent = Color3.fromRGB(214, 196, 226),
		material = Enum.Material.Glass,
		reflectance = 0.3,
		glow = Color3.fromRGB(220, 230, 255),
		sparkle = Color3.fromRGB(255, 240, 255),
		treasure = "Captain",
		blurb = "Nacre white with a lilac sheen. Dug up from a Captain's chest.",
	},
}

local byId: { [string]: Shade } = {}
for _, shade in list do
	byId[shade.id] = shade
end

return {
	list = list,
	byId = byId,
}
