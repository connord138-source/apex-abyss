--!strict
-- Skins for the playable fish. Every fish has its own line of 12 (owner, 2026-10-10:
-- "skins to be different for each playable fish. Common skins should be similar to
-- original just with realistic fish reshades and the rarer they get the wilder they
-- get"; `LINES` below): 4 Common realistic morphs (also sold by the Shade Dyer), 3
-- Uncommon, 2 Rare, an Epic, a Legendary and a Mythic. A few skins fit every fish:
-- boss trophies, treasure, the catch-track skins (Config/Catch) and the Catch of the
-- Week's. Each fish unlocks its own, and an unlocked one never rolls again for it.
-- `chance` is "1 in N" per roll; `refund` is the coral a duplicate turns into.
-- Add new shades here (and a look in Shared/Cosmetics.luau if it needs effects).
-- How a shade's glow moves (Cosmetics.pulse): a slow breath, a double heartbeat
-- thump, a fire's flicker, a rolling wave, blinking lights, lightning flashes, or a
-- scan sweeping past
export type Pulse = "breathe" | "heartbeat" | "flicker" | "wave" | "twinkle" | "strobe" | "scan"
-- What drifts off a fish in the shade (Cosmetics.aura)
export type Aura = "glints" | "embers" | "frost" | "sparks" | "stars" | "motes" | "bubbles" | "ink"

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
	light: Color3?, -- the colour it lights the dark with, when it glows but has no `glow` (LampController)
	lampBoost: number?, -- its light is this much brighter in the dark (a colour that reads weak there)
	sparkle: Color3?, -- glints drifting off it
	cycle: boolean?, -- the colors cycle through the rainbow (Prismatic)
	-- Living shades (owner, 2026-10-08: "much much more variance and depth"): how
	-- bright the skin's glow map burns (SurfaceAppearance.EmissiveStrength), how the
	-- glow moves, and what drifts off the fish. Cosmetics reads them.
	emissive: number?,
	pulse: Pulse?,
	aura: Aura?,
	spectral: boolean?, -- the whole fish turns ghostly: see-through, lit from within, haloed (Ghost)
	boss: string?, -- won only by beating this world boss (never in rolls)
	treasure: string?, -- found only in this map tier's treasure (never in rolls)
	-- Skin lines per fish (owner, 2026-10-10): the one fish this skin belongs to (set
	-- from `LINES` below; nil = every fish can have it: trophies, treasure, the
	-- catch-track and weekly skins)
	species: string?,
	catch: string?, -- earned on a fish's catch track for this Config/Catch rarity (never rolled)
	week: number?, -- the Catch of the Week skin of this week in the list (never rolled)
	blurb: string,
}

type Extra = { glow: Color3?, light: Color3?, emissive: number?, pulse: Pulse?, aura: Aura?, sparkle: Color3? }

local function common(
	id: string,
	name: string,
	chance: number,
	back: Color3,
	belly: Color3,
	fin: Color3,
	blurb: string,
	extra: Extra?
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
		glow = extra and extra.glow,
		light = extra and extra.light,
		emissive = extra and extra.emissive,
		pulse = extra and extra.pulse,
		aura = extra and extra.aura,
		sparkle = extra and extra.sparkle,
		blurb = blurb,
	}
end

local C = Color3.fromRGB

type Look = {
	glow: Color3?,
	light: Color3?,
	emissive: number?,
	pulse: Pulse?,
	aura: Aura?,
	sparkle: Color3?,
	material: Enum.Material?,
	reflectance: number?,
}

-- A line skin (its tier, odds and fish are set from LINES)
local function skin(
	id: string,
	name: string,
	back: Color3,
	belly: Color3,
	fin: Color3,
	blurb: string,
	look: Look?
): Shade
	return {
		id = id,
		name = name,
		tier = "Common",
		chance = 0,
		refund = 0,
		back = back,
		belly = belly,
		fin = fin,
		glow = look and look.glow,
		light = look and look.light,
		emissive = look and look.emissive,
		pulse = look and look.pulse,
		aura = look and look.aura,
		sparkle = look and look.sparkle,
		material = look and look.material,
		reflectance = look and look.reflectance,
		blurb = blurb,
	}
end

-- A skin every fish can earn (catch track, Catch of the Week), never rolled
local function earned(
	id: string,
	name: string,
	tier: string,
	how: { catch: string?, week: number? },
	back: Color3,
	belly: Color3,
	fin: Color3,
	blurb: string,
	look: Look?
): Shade
	local made = skin(id, name, back, belly, fin, blurb, look)
	made.tier = tier
	made.refund = 0
	made.catch = how.catch
	made.week = how.week
	return made
end

-- Every shade is a real skin on a mesh fish (tools/shades: patterns laid on the body
-- in 3D, ReplicatedStorage.ShadeSkins.<Fish>.<Shade>); the colors below are its
-- swatches in menus and the look on a part fish or before the skins are imported.
-- Owner, 2026-10-08: "All of the shades in general need much much more variance and
-- depth than just a slight reshape to the existing colors."
local list: { Shade } = {
	common(
		"Mint", -- the id stays for old saves
		"Seafoam",
		100,
		Color3.fromRGB(15, 128, 122),
		Color3.fromRGB(77, 199, 179),
		Color3.fromRGB(10, 97, 107),
		"Sea green spattered with rings of foam."
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
		"Ink wash pooling dark at the edges, and a glowing lateral line.",
		{ emissive = 0.8, pulse = "wave", light = Color3.fromRGB(80, 150, 255) }
	),
	common(
		"Sand",
		"Sandbar",
		100,
		Color3.fromRGB(148, 153, 128),
		Color3.fromRGB(204, 212, 209),
		Color3.fromRGB(82, 89, 71),
		"A sandbar: ripple marks, shell grit and weed shadows."
	),
	common(
		"Ember",
		"Ember",
		100,
		Color3.fromRGB(26, 20, 23),
		Color3.fromRGB(255, 110, 20),
		Color3.fromRGB(230, 61, 10),
		"Charcoal licked by flames from the belly up, the tips still glowing.",
		{ emissive = 0.9, pulse = "flicker", aura = "embers", glow = Color3.fromRGB(255, 120, 40) }
	),
	common(
		"Lilac",
		"Lilac",
		100,
		Color3.fromRGB(163, 133, 224),
		Color3.fromRGB(235, 242, 255),
		Color3.fromRGB(117, 77, 204),
		"Glossy lilac with pale bubbles rising along it."
	),
	common(
		"Moss",
		"Moss",
		100,
		Color3.fromRGB(56, 102, 41),
		Color3.fromRGB(168, 204, 51),
		Color3.fromRGB(77, 117, 46),
		"Lichen patches with bright rims, and algae trailing off the back."
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
		"Fuzzy yellow and black bands, matte as velvet."
	),
	common(
		"Tetra",
		"Neon Tetra",
		140,
		Color3.fromRGB(13, 26, 71),
		Color3.fromRGB(242, 31, 26),
		Color3.fromRGB(31, 250, 255),
		"An electric cyan stripe over a red tail half.",
		{ emissive = 0.8, pulse = "breathe", light = Color3.fromRGB(30, 245, 230) }
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
	common(
		"Rust",
		"Rust",
		140,
		Color3.fromRGB(143, 51, 0),
		Color3.fromRGB(102, 110, 120),
		Color3.fromRGB(61, 66, 77),
		"Shipwreck iron: bare gunmetal and rivets under flaking rust."
	),
	common(
		"Toxic",
		"Toxic",
		140,
		Color3.fromRGB(102, 242, 0),
		Color3.fromRGB(179, 255, 56),
		Color3.fromRGB(13, 13, 20),
		"Poison-frog lime with gloss black blotches and blue flecks."
	),
	{
		id = "Lunar",
		name = "Lunar",
		tier = "Rare",
		chance = 120,
		refund = 1000,
		back = Color3.fromRGB(128, 143, 173),
		belly = Color3.fromRGB(158, 173, 204),
		fin = Color3.fromRGB(102, 117, 158),
		glow = Color3.fromRGB(170, 200, 255),
		sparkle = Color3.fromRGB(220, 236, 255),
		emissive = 0.8,
		pulse = "breathe",
		aura = "motes",
		blurb = "The moon's face: silver dust, dark seas and craters, lit from above.",
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
		sparkle = Color3.fromRGB(150, 245, 255),
		emissive = 1.2,
		pulse = "twinkle",
		aura = "motes",
		blurb = "Deep-sea navy covered in glowing cyan spots that blink.",
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
		aura = "bubbles",
		blurb = "Ripples spreading over teal and violet.",
	},
	{
		id = "Mandarin",
		name = "Mandarin",
		tier = "Rare",
		chance = 200,
		refund = 1300,
		back = Color3.fromRGB(10, 56, 209),
		belly = Color3.fromRGB(20, 102, 235),
		fin = Color3.fromRGB(255, 115, 0),
		accent = Color3.fromRGB(26, 204, 77),
		sparkle = Color3.fromRGB(255, 190, 90),
		blurb = "The mandarinfish's maze: orange lines edged green on electric blue.",
	},
	{
		id = "Lanternfish",
		name = "Lanternfish",
		tier = "Rare",
		chance = 220,
		refund = 1400,
		back = Color3.fromRGB(15, 23, 46),
		belly = Color3.fromRGB(158, 173, 204),
		fin = Color3.fromRGB(20, 28, 51),
		glow = Color3.fromRGB(100, 190, 255),
		emissive = 1.4,
		pulse = "twinkle",
		blurb = "Navy and mirror silver, with rows of light organs that blink.",
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
		aura = "glints",
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
		emissive = 1.6,
		pulse = "heartbeat",
		aura = "embers",
		blurb = "Black basalt split by lava cracks that throb with heat.",
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
		aura = "frost",
		blurb = "Ice in layers: teal and cyan strata, a frosted cap, rime falling off it.",
	},
	{
		id = "Xray",
		name = "X-Ray",
		tier = "Epic",
		chance = 350,
		refund = 2500,
		back = Color3.fromRGB(8, 18, 41),
		belly = Color3.fromRGB(13, 31, 61),
		fin = Color3.fromRGB(51, 179, 255),
		glow = Color3.fromRGB(110, 210, 255),
		emissive = 1.4,
		pulse = "scan",
		blurb = "A dark body with its glowing skeleton showing through, swept by a scan.",
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
		aura = "glints",
		blurb = "Pearl white edged in real gold filigree, wrapped in a halo.",
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
		-- Green on the Trench's teal floor read weaker than Epic Magma (playtest 2026-10-09)
		lampBoost = 1.15,
		sparkle = Color3.fromRGB(200, 255, 230),
		emissive = 1.5,
		pulse = "wave",
		aura = "motes",
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
		emissive = 1.8,
		pulse = "strobe",
		aura = "sparks",
		blurb = "Storm slate forked with live lightning that flashes.",
	},
	{
		id = "Exotic",
		name = "Exotic",
		tier = "Mythic",
		chance = 900,
		refund = 7000,
		back = Color3.fromRGB(0, 217, 184),
		belly = Color3.fromRGB(255, 194, 0),
		fin = Color3.fromRGB(158, 41, 255),
		accent = Color3.fromRGB(107, 255, 20),
		sparkle = Color3.fromRGB(180, 255, 120),
		aura = "bubbles",
		blurb = "A parrotfish mosaic: every scale its own reef color, edged in cobalt.",
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
		emissive = 1.0,
		pulse = "breathe",
		aura = "stars",
		blurb = "Every color, rolling across the body.",
	},
	{
		id = "Nebula",
		name = "Nebula",
		tier = "Mythic",
		chance = 1800,
		refund = 14000,
		back = Color3.fromRGB(15, 8, 36),
		belly = Color3.fromRGB(235, 46, 235),
		fin = Color3.fromRGB(31, 217, 255),
		glow = Color3.fromRGB(170, 110, 255),
		sparkle = Color3.fromRGB(255, 255, 255),
		emissive = 1.4,
		pulse = "breathe",
		aura = "stars",
		blurb = "Magenta, violet and cyan gas clouds, dust lanes and newborn stars.",
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
		emissive = 1.6,
		pulse = "wave",
		aura = "ink",
		blurb = "An event horizon: a black core, a glowing spiral, a violet rim.",
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
		-- Pale green on the teal floor read below Nebula, though it's a trophy (playtest 2026-10-09)
		lampBoost = 1.25,
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
		glow = Color3.fromRGB(170, 120, 255),
		-- Its violet read level with Nebula and Void on the Trench's blue-violet floor,
		-- not above them as a trophy should (playtest 2026-10-10); at ×1.15 it still
		-- lit the floor less than Nebula's warmer pink (retest 2026-10-10), so a lighter
		-- violet and ×1.3
		lampBoost = 1.3,
		sparkle = Color3.fromRGB(110, 230, 255),
		emissive = 1.5,
		pulse = "wave",
		aura = "ink",
		boss = "GiantSquid",
		blurb = "The Kraken's skin: ink pigment, glowing violet veins, sucker rings. Won from the Giant Squid.",
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
		aura = "glints",
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
		sparkle = Color3.fromRGB(240, 246, 255),
		aura = "bubbles",
		treasure = "Captain",
		blurb = "Nacre white with a lilac sheen. Dug up from a Captain's chest.",
	},
	-- New in the per-fish lines (owner, 2026-10-10). Their tier, odds and fish come
	-- from LINES; the colours are the swatches and the look before the skins import.
	skin(
		"NibPercula",
		"Percula",
		C(255, 110, 20),
		C(255, 250, 255),
		C(255, 120, 30),
		"Bright orange with three crisp white bands, edged black."
	),
	skin(
		"NibTomato",
		"Tomato",
		C(214, 40, 20),
		C(240, 80, 30),
		C(170, 20, 20),
		"Tomato red, darkening behind, with one white band."
	),
	skin(
		"NibMaroon",
		"Maroon",
		C(110, 14, 34),
		C(150, 30, 44),
		C(80, 10, 26),
		"Deep maroon with three thin gold bands."
	),
	skin(
		"NibMidnight",
		"Midnight",
		C(18, 20, 28),
		C(235, 240, 255),
		C(255, 110, 20),
		"Glossy black with white bands and an orange face."
	),
	skin(
		"CudaGreat",
		"Great",
		C(84, 104, 124),
		C(205, 215, 230),
		C(50, 60, 74),
		"Steel silver, dark bars on the back, ink blotches behind."
	),
	skin(
		"CudaYellowtail",
		"Yellowtail",
		C(70, 110, 160),
		C(220, 228, 240),
		C(255, 210, 30),
		"Blue-silver with a bright yellow stripe and tail."
	),
	skin(
		"CudaChevron",
		"Chevron",
		C(70, 78, 90),
		C(190, 200, 214),
		C(60, 66, 76),
		"Gunmetal with dark chevrons down the flank."
	),
	skin(
		"CudaBlackfin",
		"Blackfin",
		C(150, 165, 180),
		C(225, 232, 242),
		C(14, 16, 20),
		"Polished steel with jet-black fin tips."
	),
	skin(
		"PufGuineafowl",
		"Guineafowl",
		C(28, 30, 36),
		C(60, 64, 72),
		C(24, 26, 30),
		"Charcoal black covered in small white spots."
	),
	skin(
		"PufGolden",
		"Canary", -- not "Golden": the catch skin has that name (playtest 2026-10-10)
		C(255, 216, 20),
		C(255, 232, 60),
		C(240, 190, 10),
		"Lemon-yellow all over, a few dark speckles."
	),
	skin(
		"PufStarry",
		"Starry",
		C(80, 96, 118),
		C(225, 232, 245),
		C(70, 84, 102),
		"Blue-grey with big black spots and a white belly."
	),
	skin(
		"PufGreen",
		"Green Spotted",
		C(120, 170, 30),
		C(200, 230, 120),
		C(100, 150, 40),
		"Lime-olive with dark spots and a pale green belly."
	),
	skin(
		"MorGreen",
		"Green",
		C(70, 110, 30),
		C(130, 160, 40),
		C(60, 96, 26),
		"Rich olive green, lightly mottled."
	),
	skin(
		"MorZebra",
		"Zebra",
		C(26, 24, 34),
		C(220, 228, 240),
		C(30, 28, 38),
		"Near-black, ringed with thin cool-white bands."
	),
	skin(
		"MorSnowflake",
		"Snowflake",
		C(150, 160, 175),
		C(180, 188, 200),
		C(20, 22, 28),
		"Cool grey with black star blotches and yellow eyes in them."
	),
	skin(
		"MorHoneycomb",
		"Honeycomb",
		C(240, 180, 20),
		C(250, 210, 60),
		C(30, 26, 20),
		"Gold under a dark honeycomb net."
	),
	skin(
		"ShkBlacktip",
		"Blacktip",
		C(100, 118, 138),
		C(230, 236, 246),
		C(14, 16, 20),
		"Blue-grey with black-tipped fins."
	),
	skin(
		"ShkWhitetip",
		"Whitetip",
		C(54, 62, 74),
		C(200, 210, 224),
		C(235, 242, 255),
		"Slate grey with bright white fin tips."
	),
	skin(
		"ShkGrey",
		"Grey Reef",
		C(108, 118, 130),
		C(225, 232, 242),
		C(30, 34, 40),
		"Even grey, a black edge on the tail."
	),
	skin("ShkLemon", "Lemon", C(190, 170, 40), C(220, 210, 90), C(170, 150, 30), "Mustard-olive yellow."),
	skin(
		"AngSeadevil",
		"Seadevil",
		C(12, 14, 20),
		C(22, 26, 36),
		C(10, 12, 18),
		"Velvet black with a faint blue sheen."
	),
	skin(
		"AngHumpback",
		"Humpback",
		C(52, 60, 50),
		C(78, 88, 76),
		C(40, 46, 38),
		"Dark olive-grey, darker on the back."
	),
	skin(
		"AngWarty",
		"Warty",
		C(48, 54, 64),
		C(84, 92, 104),
		C(40, 44, 52),
		"Mottled charcoal and slate, all bumps."
	),
	skin(
		"AngFootball",
		"Footballfish",
		C(16, 20, 40),
		C(24, 34, 70),
		C(14, 18, 34),
		"Cobalt-black studded with tiny points."
	),
	skin(
		"CudaChrome",
		"Chrome",
		C(200, 214, 230),
		C(240, 246, 255),
		C(20, 24, 30),
		"Mirror chrome raked with speed streaks.",
		{ material = Enum.Material.Metal, reflectance = 0.45, sparkle = C(220, 240, 255) }
	),
	skin(
		"CudaComet",
		"Comet",
		C(14, 20, 60),
		C(40, 70, 160),
		C(110, 230, 255),
		"A comet's head and a tail of sparks over deep space.",
		{ emissive = 1.4, pulse = "scan", aura = "stars", light = C(110, 220, 255) }
	),
	skin(
		"PufUrchin",
		"Urchin",
		C(40, 16, 60),
		C(70, 30, 96),
		C(40, 220, 210),
		"Purple-black with teal spines bursting outward."
	),
	skin(
		"PufCoralBloom",
		"Coral Bloom",
		C(30, 150, 150),
		C(255, 140, 40),
		C(150, 70, 220),
		"Living coral and polyps grown over it."
	),
	skin(
		"PufSunburst",
		"Sunburst",
		C(255, 120, 10),
		C(255, 200, 40),
		C(240, 160, 20),
		"Golden rays bursting from a glowing core.",
		{
			emissive = 1.6,
			pulse = "breathe",
			aura = "glints",
			light = C(255, 190, 60),
			material = Enum.Material.Metal,
			reflectance = 0.3,
		}
	),
	skin(
		"MorSerpent",
		"Serpent",
		C(20, 110, 60),
		C(40, 160, 90),
		C(200, 160, 40),
		"Emerald dragon scales edged in gold."
	),
	skin(
		"MorRibbon",
		"Ribbon",
		C(20, 60, 220),
		C(40, 100, 255),
		C(255, 220, 20),
		"Electric blue with a vivid yellow fin and snout."
	),
	skin(
		"MorJade",
		"Jade Dragon",
		C(30, 120, 80),
		C(110, 200, 150),
		C(220, 180, 60),
		"Carved jade with glowing gold filigree.",
		{ emissive = 1.0, pulse = "wave", aura = "glints", light = C(140, 255, 190) }
	),
	skin(
		"ShkWarpaint",
		"Warpaint",
		C(30, 34, 40),
		C(60, 66, 76),
		C(20, 180, 170),
		"Teal and black war stripes over charcoal."
	),
	skin(
		"ShkScarred",
		"Battle-Scarred",
		C(90, 98, 110),
		C(170, 180, 196),
		C(70, 76, 86),
		"A veteran's hide of healed scars and bite marks."
	),
	skin(
		"ShkBoneplate",
		"Bone Plate",
		C(60, 66, 76),
		C(170, 178, 190),
		C(150, 158, 170),
		"Bone-grey armour plates over gunmetal."
	),
	skin(
		"AngMurk",
		"Murk",
		C(70, 76, 80),
		C(96, 102, 106),
		C(56, 60, 64),
		"Silt grey with drifting sediment."
	),
	skin(
		"AngDriftwood",
		"Driftwood",
		C(120, 126, 132),
		C(160, 166, 172),
		C(96, 100, 106),
		"Bleached driftwood grain and barnacles."
	),
	skin(
		"AngBioglow",
		"Bioglow",
		C(10, 14, 24),
		C(20, 28, 46),
		C(60, 140, 255),
		"Near-black, freckled with faint blue lights.",
		{ emissive = 0.7, pulse = "twinkle", light = C(80, 160, 255) }
	),
	skin(
		"AngGlassveins",
		"Glassveins",
		C(30, 20, 80),
		C(50, 40, 120),
		C(60, 230, 255),
		"Deep indigo lit by glowing cyan veins.",
		{ emissive = 1.1, pulse = "heartbeat", light = C(70, 230, 255) }
	),
	skin(
		"AngAbyssEye",
		"Abyss Eye",
		C(12, 10, 14),
		C(30, 24, 30),
		C(255, 160, 30),
		"Dozens of glowing amber eyes.",
		{ emissive = 1.2, pulse = "twinkle", aura = "motes", light = C(255, 170, 60) }
	),
	skin(
		"AngLanternKing",
		"Lantern King",
		C(20, 26, 60),
		C(230, 180, 50),
		C(255, 200, 70),
		"Gold lantern filigree and a crown of glowing spines.",
		{
			emissive = 1.5,
			pulse = "flicker",
			aura = "embers",
			light = C(255, 200, 90),
			material = Enum.Material.Metal,
			reflectance = 0.3,
		}
	),
	skin(
		"AngStarfall",
		"Starfall",
		C(8, 8, 20),
		C(30, 26, 70),
		C(170, 150, 255),
		"Constellations and falling stars on black.",
		{ emissive = 1.5, pulse = "twinkle", aura = "stars", light = C(170, 150, 255) }
	),
	-- Earned on a fish's catch track (Config/Catch), never rolled: every fish can earn
	-- its own. Earned skins top out at Epic (owner, 2026-10-10: "we still don't want
	-- the most elite skins obtained that way that'll be rng and bosses/treasure
	-- chests"), and so do the weekly ones
	earned(
		"CatchGolden",
		"Golden",
		"Uncommon",
		{ catch = "Golden" },
		C(255, 196, 64),
		C(255, 226, 120),
		C(220, 160, 30),
		"Solid gold, its own pattern engraved. 10 Golden catches as this fish.",
		{ material = Enum.Material.Metal, reflectance = 0.4, sparkle = C(255, 236, 170), aura = "glints" }
	),
	earned(
		"CatchGlowing",
		"Glowing",
		"Rare",
		{ catch = "Glowing" },
		C(10, 30, 60),
		C(30, 160, 160),
		C(60, 240, 220),
		"Bioluminescent: its own markings glow. 10 Glowing catches as this fish.",
		{ emissive = 1.3, pulse = "breathe", aura = "motes", light = C(70, 240, 220) }
	),
	earned(
		"CatchCrystal",
		"Crystal",
		"Epic",
		{ catch = "Crystal" },
		C(150, 200, 240),
		C(200, 230, 255),
		C(120, 180, 230),
		"Clear crystal full of glints. 5 Crystal catches as this fish.",
		{ material = Enum.Material.Glass, reflectance = 0.35, sparkle = C(220, 240, 255), aura = "glints" }
	),
	earned(
		"CatchPrism",
		"Prism",
		"Epic",
		{ catch = "Prism" },
		C(255, 120, 230),
		C(120, 220, 255),
		C(255, 230, 90),
		"Holographic prism foil. 3 Prism catches as this fish.",
		{ emissive = 0.9, pulse = "wave", aura = "stars", light = C(255, 140, 230) }
	),
	-- The Catch of the Week's limited skins (Config/Catch weekly), never rolled
	earned(
		"WeekWave",
		"Great Wave",
		"Epic",
		{ week = 1 },
		C(20, 40, 120),
		C(200, 220, 245),
		C(30, 60, 150),
		"A woodblock great wave rolling down its flanks. Week 1's catch."
	),
	earned(
		"WeekReef",
		"Living Reef",
		"Epic",
		{ week = 2 },
		C(30, 180, 180),
		C(255, 140, 60),
		C(150, 80, 220),
		"A whole reef painted on. Week 2's catch."
	),
	earned(
		"WeekWreck",
		"Shipwreck",
		"Epic",
		{ week = 3 },
		C(80, 70, 66),
		C(200, 90, 40),
		C(60, 56, 54),
		"Riveted hull plates, rust and barnacles. Week 3's catch."
	),
	earned(
		"WeekSeaGlass",
		"Sea Glass",
		"Epic",
		{ week = 4 },
		C(40, 140, 90),
		C(60, 110, 200),
		C(200, 140, 40),
		"A mosaic of frosted sea glass. Week 4's catch."
	),
}

local byId: { [string]: Shade } = {}
for _, shade in list do
	byId[shade.id] = shade
end

-- Each fish's line, commonest first (Config/Species ids; tools/shades/lines.json
-- makes the skins): 4 Common, 3 Uncommon, 2 Rare, Epic, Legendary, Mythic
local LINES: { [string]: { string } } = {
	Nibbler = {
		"NibPercula",
		"NibTomato",
		"NibMaroon",
		"NibMidnight",
		"Bumblebee",
		"Lilac",
		"Mint",
		"Tidepool",
		"Glowspot",
		"Diamond",
		"Divine",
		"Prismatic",
	},
	Cuda = {
		"CudaGreat",
		"CudaYellowtail",
		"CudaChevron",
		"CudaBlackfin",
		"Tiger",
		"Sunset",
		"Ocean",
		"Lunar",
		"CudaChrome",
		"Xray",
		"Thunder",
		"CudaComet",
	},
	Pufferfish = {
		"PufGuineafowl",
		"PufGolden",
		"PufStarry",
		"PufGreen",
		"Toxic",
		"Leopard",
		"Tetra",
		"Mandarin",
		"PufUrchin",
		"PufCoralBloom",
		"PufSunburst",
		"Exotic",
	},
	MorayEel = {
		"MorGreen",
		"MorZebra",
		"MorSnowflake",
		"MorHoneycomb",
		"Moss",
		"Sand",
		"Rust",
		"MorSerpent",
		"MorRibbon",
		"Magma",
		"MorJade",
		"Void",
	},
	ReefShark = {
		"ShkBlacktip",
		"ShkWhitetip",
		"ShkGrey",
		"ShkLemon",
		"Ember",
		"Ink",
		"ShkWarpaint",
		"ShkScarred",
		"ShkBoneplate",
		"Glacier",
		"Aurora",
		"Nebula",
	},
	Anglerfish = {
		"AngSeadevil",
		"AngHumpback",
		"AngWarty",
		"AngFootball",
		"AngMurk",
		"AngDriftwood",
		"AngBioglow",
		"Lanternfish",
		"AngGlassveins",
		"AngAbyssEye",
		"AngLanternKing",
		"AngStarfall",
	},
}

-- Each place in a line: its tier, "1 in N" per roll, the coral a duplicate turns
-- into, and the Shade Dyer's price (Commons only). About 17% of a roll is a skin for
-- a fresh fish, as before the lines.
local PLACES: { { tier: string, chance: number, refund: number, price: number? } } = {
	{ tier = "Common", chance = 32, refund = 120, price = 1500 },
	{ tier = "Common", chance = 32, refund = 120, price = 1500 },
	{ tier = "Common", chance = 32, refund = 120, price = 1500 },
	{ tier = "Common", chance = 32, refund = 120, price = 1500 },
	{ tier = "Uncommon", chance = 100, refund = 300 },
	{ tier = "Uncommon", chance = 100, refund = 300 },
	{ tier = "Uncommon", chance = 100, refund = 300 },
	{ tier = "Rare", chance = 150, refund = 1000 },
	{ tier = "Rare", chance = 150, refund = 1000 },
	{ tier = "Epic", chance = 300, refund = 2000 },
	{ tier = "Legendary", chance = 700, refund = 5000 },
	{ tier = "Mythic", chance = 1500, refund = 12000 },
}

local lines: { [string]: { Shade } } = {}
for species, ids in LINES do
	local line: { Shade } = {}
	for i, id in ids do
		local shade = byId[id]
		assert(shade, `Config/Shades LINES: no shade {id}`)
		assert(shade.species == nil, `Config/Shades LINES: {id} is in two lines`)
		local place = PLACES[i]
		shade.species = species
		shade.tier = place.tier
		shade.chance = place.chance
		shade.refund = place.refund
		shade.price = place.price
		table.insert(line, shade)
	end
	lines[species] = line
end
for _, shade in list do
	if shade.species == nil and not (shade.boss or shade.treasure or shade.catch or shade.week) then
		error(`Config/Shades: {shade.id} is in no fish's line`)
	end
end

-- Whether a fish of `speciesId` can have a skin: one of its own line, or one every
-- fish can have ("" = no skin, which always fits)
local function fits(shadeId: string, speciesId: string): boolean
	if shadeId == "" then
		return true
	end
	local shade = byId[shadeId]
	return shade ~= nil and (shade.species == nil or shade.species == speciesId)
end

-- Whether a skin comes out of rolls (its fish's own; never trophies, treasure,
-- catch-track or weekly skins)
local function rollable(shade: Shade): boolean
	return shade.chance > 0
		and shade.species ~= nil
		and not (shade.boss or shade.treasure or shade.catch or shade.week)
end

return {
	list = list,
	byId = byId,
	lines = lines, -- species id → its 12, commonest first
	fits = fits,
	rollable = rollable,
}
