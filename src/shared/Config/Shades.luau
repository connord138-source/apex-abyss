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
	spectral: boolean?, -- the whole fish turns ghostly: see-through, lit from within, haloed (Ghost)
	boss: string?, -- won only by beating this world boss (never in rolls)
	treasure: string?, -- found only in this map tier's treasure (never in rolls)
	blurb: string,
}

local function common(
	id: string,
	name: string,
	chance: number,
	back: Color3,
	belly: Color3,
	fin: Color3,
	blurb: string
): Shade
	return {
		id = id,
		name = name,
		tier = "Common",
		chance = chance,
		refund = 120,
		price = 1500,
		back = back,
		belly = belly,
		fin = fin,
		blurb = blurb,
	}
end

-- Every shade is a real skin on a mesh fish (tools/shades: patterns laid on the body
-- in 3D, ReplicatedStorage.ShadeSkins.<Fish>.<Shade>); the colors below are its
-- swatches in menus and the look on a part fish or before the skins are imported.
-- Owner, 2026-10-08: "All of the shades in general need much much more variance and
-- depth than just a slight reshape to the existing colors."
local list: { Shade } = {
	common(
		"Mint",
		"Mint",
		100,
		Color3.fromRGB(92, 199, 158),
		Color3.fromRGB(204, 245, 235),
		Color3.fromRGB(41, 148, 138),
		"Mint green with dark saddles and freckles."
	),
	common(
		"Sunset",
		"Sunset",
		100,
		Color3.fromRGB(255, 160, 30),
		Color3.fromRGB(255, 230, 77),
		Color3.fromRGB(209, 26, 66),
		"Gold melting into red, with a crimson horizon."
	),
	common(
		"Ink",
		"Ink",
		100,
		Color3.fromRGB(23, 31, 66),
		Color3.fromRGB(102, 122, 173),
		Color3.fromRGB(46, 56, 128),
		"Midnight navy, a fine net and a glowing lateral line."
	),
	common(
		"Sand",
		"Sandbar",
		100,
		Color3.fromRGB(148, 153, 128),
		Color3.fromRGB(204, 212, 209),
		Color3.fromRGB(82, 89, 71),
		"Seabed camouflage: blotched and speckled like a flounder."
	),
	common(
		"Ember",
		"Ember",
		100,
		Color3.fromRGB(204, 23, 18),
		Color3.fromRGB(255, 148, 26),
		Color3.fromRGB(18, 15, 23),
		"Fire red with black tiger stripes."
	),
	common(
		"Lilac",
		"Lilac",
		100,
		Color3.fromRGB(163, 133, 224),
		Color3.fromRGB(235, 242, 255),
		Color3.fromRGB(117, 77, 204),
		"Lilac with white polka dots."
	),
	common(
		"Moss",
		"Moss",
		100,
		Color3.fromRGB(56, 102, 41),
		Color3.fromRGB(168, 204, 51),
		Color3.fromRGB(77, 117, 46),
		"Forest green under a lime net, like a moray."
	),
	common(
		"Ocean",
		"Ocean",
		100,
		Color3.fromRGB(20, 82, 209),
		Color3.fromRGB(148, 199, 250),
		Color3.fromRGB(255, 209, 20),
		"Royal blue with a black swoosh and a yellow tail."
	),
	common(
		"Tiger",
		"Tiger",
		140,
		Color3.fromRGB(255, 117, 10),
		Color3.fromRGB(235, 242, 255),
		Color3.fromRGB(15, 15, 23),
		"Blazing orange with bold black stripes."
	),
	common(
		"Bumblebee",
		"Bumblebee",
		140,
		Color3.fromRGB(255, 204, 13),
		Color3.fromRGB(255, 224, 64),
		Color3.fromRGB(15, 15, 23),
		"Yellow and black bands."
	),
	common(
		"Tetra",
		"Neon Tetra",
		140,
		Color3.fromRGB(13, 26, 71),
		Color3.fromRGB(242, 31, 26),
		Color3.fromRGB(31, 250, 255),
		"An electric cyan stripe over a red tail half."
	),
	common(
		"Leopard",
		"Leopard",
		140,
		Color3.fromRGB(250, 184, 26),
		Color3.fromRGB(255, 224, 112),
		Color3.fromRGB(15, 15, 23),
		"Gold with black rosettes."
	),
	{
		id = "Lunar",
		name = "Lunar",
		tier = "Rare",
		chance = 120,
		refund = 1000,
		back = Color3.fromRGB(189, 204, 240),
		belly = Color3.fromRGB(235, 242, 255),
		fin = Color3.fromRGB(140, 158, 219),
		glow = Color3.fromRGB(170, 200, 255),
		sparkle = Color3.fromRGB(220, 236, 255),
		blurb = "Pearl moonlight with crescent marks and drifting stars.",
	},
	{
		id = "Glowspot",
		name = "Glowspot",
		tier = "Rare",
		chance = 160,
		refund = 1100,
		back = Color3.fromRGB(8, 15, 46),
		belly = Color3.fromRGB(15, 51, 77),
		fin = Color3.fromRGB(51, 242, 255),
		glow = Color3.fromRGB(60, 220, 255),
		blurb = "Deep-sea navy covered in glowing cyan spots.",
	},
	{
		id = "Tidepool",
		name = "Tidepool",
		tier = "Rare",
		chance = 180,
		refund = 1200,
		back = Color3.fromRGB(10, 143, 158),
		belly = Color3.fromRGB(107, 71, 204),
		fin = Color3.fromRGB(140, 255, 242),
		sparkle = Color3.fromRGB(170, 255, 240),
		blurb = "Teal fading to violet under rippling light.",
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
		reflectance = 0.35,
		sparkle = Color3.fromRGB(255, 255, 255),
		blurb = "Cut crystal facets that throw rainbow fire.",
	},
	{
		id = "Magma",
		name = "Magma",
		tier = "Epic",
		chance = 300,
		refund = 2200,
		back = Color3.fromRGB(26, 20, 20),
		belly = Color3.fromRGB(46, 31, 26),
		fin = Color3.fromRGB(255, 140, 13),
		glow = Color3.fromRGB(255, 110, 30),
		sparkle = Color3.fromRGB(255, 170, 60),
		blurb = "Black basalt split by glowing lava cracks.",
	},
	{
		id = "Glacier",
		name = "Glacier",
		tier = "Epic",
		chance = 320,
		refund = 2300,
		back = Color3.fromRGB(61, 133, 204),
		belly = Color3.fromRGB(235, 242, 255),
		fin = Color3.fromRGB(102, 179, 240),
		reflectance = 0.2,
		sparkle = Color3.fromRGB(220, 245, 255),
		blurb = "Ice blue with frost drifts and hairline cracks.",
	},
	{
		id = "Divine",
		name = "Divine",
		tier = "Legendary",
		chance = 500,
		refund = 4000,
		back = Color3.fromRGB(235, 242, 255),
		belly = Color3.fromRGB(250, 252, 255),
		fin = Color3.fromRGB(255, 194, 41),
		reflectance = 0.25,
		glow = Color3.fromRGB(255, 220, 140),
		sparkle = Color3.fromRGB(255, 226, 150),
		blurb = "Pearl white edged in gold filigree, wrapped in a halo.",
	},
	{
		id = "Aurora",
		name = "Aurora",
		tier = "Legendary",
		chance = 650,
		refund = 4500,
		back = Color3.fromRGB(8, 26, 41),
		belly = Color3.fromRGB(51, 255, 140),
		fin = Color3.fromRGB(158, 77, 255),
		glow = Color3.fromRGB(90, 255, 170),
		sparkle = Color3.fromRGB(200, 255, 230),
		blurb = "Northern lights rippling over a night-dark body.",
	},
	{
		id = "Thunder",
		name = "Thunder",
		tier = "Legendary",
		chance = 700,
		refund = 4800,
		back = Color3.fromRGB(46, 54, 77),
		belly = Color3.fromRGB(117, 133, 163),
		fin = Color3.fromRGB(217, 242, 255),
		glow = Color3.fromRGB(120, 180, 255),
		sparkle = Color3.fromRGB(200, 230, 255),
		blurb = "Storm slate forked with live lightning.",
	},
	{
		id = "Exotic",
		name = "Exotic",
		tier = "Mythic",
		chance = 900,
		refund = 7000,
		back = Color3.fromRGB(20, 92, 255),
		belly = Color3.fromRGB(255, 219, 13),
		fin = Color3.fromRGB(255, 107, 15),
		accent = Color3.fromRGB(89, 255, 64),
		sparkle = Color3.fromRGB(180, 255, 120),
		blurb = "Tropical neon: blue, gold spots, lime stripes, orange fins.",
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
	{
		id = "Nebula",
		name = "Nebula",
		tier = "Mythic",
		chance = 1800,
		refund = 14000,
		back = Color3.fromRGB(10, 8, 26),
		belly = Color3.fromRGB(107, 51, 230),
		fin = Color3.fromRGB(26, 217, 217),
		glow = Color3.fromRGB(140, 110, 255),
		sparkle = Color3.fromRGB(255, 255, 255),
		blurb = "Deep space: violet clouds and a field of stars.",
	},
	{
		id = "Void",
		name = "Void",
		tier = "Mythic",
		chance = 2200,
		refund = 16000,
		back = Color3.fromRGB(8, 5, 15),
		belly = Color3.fromRGB(97, 26, 204),
		fin = Color3.fromRGB(158, 77, 255),
		glow = Color3.fromRGB(150, 70, 255),
		blurb = "Blacker than the Trench, cracked with violet light.",
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
		transparency = 0.3,
		spectral = true, -- the whole fish, not just its edges (owner, 2026-10-08: "a similar to ghost from sea of thieves glow")
		glow = Color3.fromRGB(150, 255, 180),
		sparkle = Color3.fromRGB(200, 255, 210),
		boss = "Megalodon",
		blurb = "Pale green and see-through, lit from within like the drowned. Won from the Megalodon.",
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
