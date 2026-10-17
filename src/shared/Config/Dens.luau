--!strict
-- Den bases (owner, 2026-10-07: "the dens being an upgradable base that gets bigger
-- and deeper as it upgrades. Other players can go in and check out your base but
-- can't take or do anything. You can display trophies from large fish killed/bosses
-- killed and set up furniture so that it's your den. Upgrades and furniture/colors
-- would cost currency. Coral lamps, etc").
--
-- v2 (owner, 2026-10-13: "The dens need to be larger and have much more depth so
-- players can build in them and show them off. It's meant to be like the players
-- house/base. We will have furniture, rugs, lamps, and tons of items"): a den is a
-- house dug down into the rock. The main room (the Nook) runs back into the Burrow,
-- and from the Hall on, shafts drop to two big vaulted storeys below it: the Hall
-- (and its Grotto wings), then the Sanctum, the deepest. Every storey has a flat
-- stone deck to build on, and things are placed freely (Build mode) on decks, walls
-- and ceilings, as many as the level allows. Room numbers are in the den's frame:
-- x across, y up from the main floor, z toward the front wall and its way out
-- (negative = back into the rock); Shared/DenSpace turns them into decks and
-- placement rules, and the server carves them (DenCarve).
--
-- v3, private interiors (owner, 2026-10-16: "Dens also still need to be
-- substantially bigger"; of three ways, "Private interiors"): a den is no longer
-- squeezed into the hub's ring of twelve. Each one is its own block of rock far
-- outside the play area (`interior`: a grid at the hub's own height, so it's lit
-- like the hub and only streams to fish inside it), reached through a bubble portal
-- in its doorway on the plaza and left by the portal on its front wall. The rooms
-- grew about four times: a 60 × 60 Nook 39 studs tall, to a Sanctum of ~50,000
-- square studs over three storeys. Every room has upright walls `wall` studs high
-- under a shallow arched ceiling (DenCarve, DenSpace.vaultAt).
export type Level = {
	level: number,
	name: string,
	cost: number, -- coral to reach it (0 for the first)
	capacity: number, -- things that can be placed
	blurb: string,
}

-- A storey: its deck's top, the carved floor under the deck, the ceiling's crown
-- (local y), and how high the upright walls stand over the deck before the arch
export type Storey = { deck: number, floor: number, ceiling: number, wall: number }

-- A room: a band of floor across the den's axis, `x` either side of it, from `z0`
-- (the hub side) back to `z1`. Rooms on one storey join into one floor.
export type Room = {
	id: string,
	level: number, -- opens at this den level
	storey: number,
	x: number,
	z0: number,
	z1: number,
	pillars: number?, -- stone columns down each side, this far apart
}

-- A round shaft from one storey's floor down to the next storey's ceiling. `radius`
-- is the opening inside its curb; the rock is cut 3 studs wider (DenCarve), since a
-- cylinder of air cut through Terrain's 4-stud voxels at a slant clears a good deal
-- less than its radius (playtest 2026-10-13: at 6 only a 2-stud box got through)
export type Shaft = { id: string, level: number, from: number, to: number, z: number, radius: number }

-- Where the Coral Garden stands at a level: a trough along the main room's back
-- wall, then a bed in the middle of the Hall
export type GardenSpot = {
	level: number, -- from this level on (the highest one reached wins)
	storey: number,
	z: number,
	shape: "trough" | "bed",
	width: number,
	depth: number,
}

export type Item = {
	id: string,
	name: string,
	price: number,
	kinds: { string }, -- where it goes: "floor", "wall", "ceiling"
	size: Vector3, -- its box as it stands (a wall item's Z is how far it stands out)
	prop: string?, -- ReplicatedStorage.WorldProps.<prop> when imported
	color: Color3,
	glow: boolean?, -- lit in the den's glow color
	bubbles: boolean?,
	flat: boolean?, -- lies on the floor (a rug): others stand on it
	blurb: string,
	set: string?, -- the furniture set it belongs to (`sets`): bought once its achievement is done
	lamp: Color3?, -- lit in its own color (not the den's glow), its prop left untinted
	rug: string?, -- a rug's shape ("round", "oval", "square"); its top-down art is Config/Textures `rug<id>`
	front: number?, -- degrees its imported prop is turned to face out (Tripo props face +X: 90)
}

-- A furniture set (owner, 2026-10-13: "Approve all"; concepts
-- assets/concepts/Furn*.jpg): one per biome plus the boss trophies. An achievement
-- (Config/Achievements) opens it; then each piece is bought on its own with coral,
-- so pieces mix and match between sets.
export type Set = {
	id: string,
	name: string,
	biome: string, -- where its look comes from (a word for the menu)
	tier: string, -- Config/Tiers id: the set's color in the menu
	blurb: string,
}

-- A deck's stone: material and two colors the tiles alternate between
export type FloorStyle = {
	id: string,
	name: string,
	price: number,
	material: Enum.Material,
	colors: { Color3 },
	seams: boolean?, -- thin lines between tiles in the den's glow color
	blurb: string,
}

local levels: { Level } = {
	{
		level = 1,
		name = "Nook",
		cost = 0,
		capacity = 20,
		blurb = "A big cave room of your own: your pool, your garden and the trophy wall.",
	},
	{
		level = 2,
		name = "Burrow",
		cost = 1000,
		capacity = 40,
		blurb = "A second great room runs far back into the rock, with room for twice as much.",
	},
	{
		level = 3,
		name = "Hall",
		cost = 12000,
		capacity = 70,
		blurb = "A shaft drops to a great vaulted hall below, and the Coral Garden moves to its middle.",
	},
	{
		level = 4,
		name = "Grotto",
		cost = 45000,
		capacity = 110,
		blurb = "The hall opens into wide wings and a deep grotto at its back.",
	},
	{
		level = 5,
		name = "Sanctum",
		cost = 150000,
		capacity = 160,
		blurb = "A second shaft to the Sanctum, the deepest and grandest storey of all.",
	},
}

-- Main floor y 0 is world y 4 (Config/World hub.denFloorY; the interiors sit at
-- the hub's height). The rock floor under each deck is 5–6 studs down, on a 4-stud
-- voxel line: Terrain draws its surface up to ~4.6 studs above where it's filled,
-- and with 1–2 studs of room it came up through the flagstones (playtest
-- 2026-10-13: none showed on the main storey; sandy wedges between them below).
-- The decks are thick slabs down to it. 8 studs of rock stay between one storey's
-- floor and the next one's ceiling.
local storeys: { Storey } = {
	{ deck = 1, floor = -4, ceiling = 40, wall = 22 },
	{ deck = -54, floor = -60, ceiling = -12, wall = 24 },
	{ deck = -114, floor = -120, ceiling = -68, wall = 26 },
}

-- Bounds on the 2-stud grid (x whole studs); the front wall (z0 of the front rooms)
-- holds the way out on the main storey
local rooms: { Room } = {
	{ id = "Nook", level = 1, storey = 1, x = 30, z0 = 30, z1 = -30 },
	{ id = "Burrow", level = 2, storey = 1, x = 28, z0 = -26, z1 = -90 },
	{ id = "HallNave", level = 3, storey = 2, x = 32, z0 = 30, z1 = -20 },
	{ id = "HallMid", level = 3, storey = 2, x = 40, z0 = -20, z1 = -70 },
	{ id = "HallBack", level = 3, storey = 2, x = 46, z0 = -70, z1 = -120, pillars = 14 },
	{ id = "GrottoWings", level = 4, storey = 2, x = 58, z0 = -30, z1 = -120 },
	{ id = "GrottoDeep", level = 4, storey = 2, x = 62, z0 = -120, z1 = -170, pillars = 14 },
	{ id = "SanctumFore", level = 5, storey = 3, x = 36, z0 = 30, z1 = -20 },
	{ id = "SanctumNave", level = 5, storey = 3, x = 50, z0 = -20, z1 = -100, pillars = 16 },
	{ id = "SanctumApse", level = 5, storey = 3, x = 66, z0 = -100, z1 = -180, pillars = 16 },
}

local shafts: { Shaft } = {
	{ id = "HallShaft", level = 3, from = 1, to = 2, z = -58, radius = 9 },
	{ id = "SanctumShaft", level = 5, from = 2, to = 3, z = -90, radius = 10 },
}

local gardenSpots: { GardenSpot } = {
	{ level = 1, storey = 1, z = -26, shape = "trough", width = 24, depth = 5 },
	{ level = 2, storey = 1, z = -86, shape = "trough", width = 24, depth = 5 },
	{ level = 3, storey = 2, z = 4, shape = "bed", width = 22, depth = 16 },
}

local items: { Item } = {
	{
		id = "CoralLamp",
		name = "Coral Lamp",
		price = 250,
		kinds = { "floor" },
		size = Vector3.new(2.5, 5, 2.5),
		prop = "Lantern",
		color = Color3.fromRGB(255, 146, 110),
		glow = true,
		blurb = "A branching coral stalk with a glowing cap",
	},
	{
		id = "KelpBed",
		name = "Kelp Bed",
		price = 180,
		kinds = { "floor" },
		size = Vector3.new(6, 1.2, 4),
		prop = "KelpClump",
		color = Color3.fromRGB(78, 116, 52),
		blurb = "A soft heap of kelp to settle into",
	},
	{
		id = "KelpRug",
		name = "Woven Kelp Rug",
		price = 200,
		kinds = { "floor" },
		size = Vector3.new(9, 0.2, 6),
		color = Color3.fromRGB(70, 120, 92),
		flat = true,
		blurb = "A rug of woven kelp, for under everything else",
	},
	{
		id = "ShellPile",
		name = "Shell Pile",
		price = 150,
		kinds = { "floor" },
		size = Vector3.new(4, 2, 4),
		prop = "Shell",
		color = Color3.fromRGB(242, 228, 204),
		blurb = "Shells you've gathered, heaped up",
	},
	{
		id = "AnemoneGarden",
		name = "Anemone Garden",
		price = 300,
		kinds = { "floor" },
		size = Vector3.new(5, 2.5, 5),
		prop = "Anemone",
		color = Color3.fromRGB(240, 110, 120),
		blurb = "Swaying anemones in a bed of sand",
	},
	{
		id = "BrainCoral",
		name = "Brain Coral",
		price = 220,
		kinds = { "floor" },
		size = Vector3.new(4.5, 3.5, 4.5),
		prop = "BrainCoral",
		color = Color3.fromRGB(250, 220, 110),
		blurb = "A fat yellow brain coral",
	},
	{
		id = "TubeSponges",
		name = "Tube Sponges",
		price = 200,
		kinds = { "floor" },
		size = Vector3.new(3, 5, 3),
		prop = "TubeSponge",
		color = Color3.fromRGB(170, 110, 220),
		blurb = "Tall purple sponges",
	},
	{
		id = "DriftwoodTable",
		name = "Driftwood Table",
		price = 350,
		kinds = { "floor" },
		size = Vector3.new(6, 3, 3.5),
		color = Color3.fromRGB(110, 86, 60),
		blurb = "A slab of driftwood on two stones",
	},
	{
		id = "PearlPedestal",
		name = "Pearl Pedestal",
		price = 900,
		kinds = { "floor" },
		size = Vector3.new(3, 5, 3),
		color = Color3.fromRGB(236, 236, 240),
		glow = true,
		blurb = "A great pearl on a stone column, lit from within",
	},
	{
		id = "DecorChest",
		name = "Treasure Chest",
		price = 600,
		kinds = { "floor" },
		size = Vector3.new(5, 4, 3.5),
		prop = "TreasureChest",
		color = Color3.fromRGB(78, 54, 36),
		blurb = "A chest like the ones your maps lead to",
	},
	{
		id = "BubbleColumn",
		name = "Bubble Column",
		price = 500,
		kinds = { "floor" },
		size = Vector3.new(2, 1, 2),
		color = Color3.fromRGB(200, 240, 255),
		bubbles = true,
		blurb = "A vent of bubbles rising to the ceiling",
	},
	{
		id = "CrystalShard",
		name = "Crystal Shard",
		price = 1200,
		kinds = { "floor", "wall" },
		size = Vector3.new(3, 6, 3),
		prop = "CrystalCluster",
		color = Color3.fromRGB(110, 230, 255),
		glow = true,
		blurb = "A cluster of glowing crystal",
	},
	{
		id = "SeaGlassLantern",
		name = "Sea Glass Lantern",
		price = 400,
		kinds = { "wall" },
		size = Vector3.new(2, 3, 2),
		prop = "Lantern",
		color = Color3.fromRGB(120, 255, 230),
		glow = true,
		blurb = "A lantern of sea glass on the wall",
	},
	{
		id = "JellyLamp",
		name = "Jellyfish Lamp",
		price = 650,
		kinds = { "ceiling" },
		size = Vector3.new(3, 5, 3),
		color = Color3.fromRGB(200, 170, 255),
		glow = true,
		blurb = "A glowing jelly hanging from the ceiling",
	},
	{
		id = "SeaFan",
		name = "Sea Fan",
		price = 220,
		kinds = { "wall" },
		size = Vector3.new(5, 5, 1),
		prop = "FanCoral",
		color = Color3.fromRGB(255, 160, 80),
		blurb = "A wide fan coral on the wall",
	},
	{
		id = "Banner",
		name = "Banner",
		price = 400,
		kinds = { "wall" },
		size = Vector3.new(4, 7, 0.4),
		color = Color3.fromRGB(46, 170, 214),
		glow = true,
		blurb = "A hanging banner in your glow color",
	},
	-- Kelp Cottage (Kelp Shallows): cosy driftwood and woven kelp
	{
		id = "KelpArmchair",
		set = "KelpCottage",
		name = "Kelp Armchair",
		price = 600,
		kinds = { "floor" },
		size = Vector3.new(4.8, 5, 4.4),
		prop = "KelpArmchair",
		front = 90,
		color = Color3.fromRGB(122, 136, 58),
		blurb = "Woven kelp over driftwood, with a moss cushion",
	},
	{
		id = "KelpHammock",
		set = "KelpCottage",
		name = "Kelp Hammock",
		price = 900,
		kinds = { "floor" },
		size = Vector3.new(10, 5.2, 3.1),
		prop = "KelpHammock",
		front = 90,
		color = Color3.fromRGB(70, 132, 92),
		blurb = "A kelp hammock strung between two posts",
	},
	{
		id = "BarrelTable",
		set = "KelpCottage",
		name = "Barrel Table",
		price = 500,
		kinds = { "floor" },
		size = Vector3.new(4.6, 3.8, 4.6),
		prop = "BarrelTable",
		front = 90,
		color = Color3.fromRGB(122, 98, 72),
		blurb = "A barnacled barrel with a driftwood top",
	},
	{
		id = "ScallopLamp",
		set = "KelpCottage",
		name = "Scallop Lamp",
		price = 700,
		kinds = { "floor" },
		size = Vector3.new(2.3, 7, 1.9),
		prop = "ScallopLamp",
		front = 90,
		color = Color3.fromRGB(240, 170, 90),
		lamp = Color3.fromRGB(255, 186, 110),
		blurb = "A driftwood pole under a glowing scallop shell",
	},
	{
		id = "DriftwoodShelf",
		set = "KelpCottage",
		name = "Driftwood Shelf",
		price = 650,
		kinds = { "floor" },
		size = Vector3.new(6.8, 4.5, 2.7),
		prop = "DriftwoodShelf",
		front = 90,
		color = Color3.fromRGB(128, 108, 84),
		blurb = "Jars, shells and kelp bundles on a driftwood shelf",
	},
	{
		id = "BraidedKelpRug",
		set = "KelpCottage",
		name = "Braided Kelp Rug",
		price = 400,
		kinds = { "floor" },
		size = Vector3.new(8, 0.2, 8),
		rug = "round",
		flat = true,
		color = Color3.fromRGB(78, 140, 88),
		blurb = "A round rug braided from kelp",
	},
	-- Reef Palace (Coral Reef): coral grown into furniture
	{
		id = "CoralThrone",
		set = "ReefPalace",
		name = "Coral Throne",
		price = 3500,
		kinds = { "floor" },
		size = Vector3.new(5.6, 7, 4.5),
		prop = "CoralThrone",
		front = 90,
		color = Color3.fromRGB(236, 120, 60),
		blurb = "A throne of branching coral with an anemone cushion",
	},
	{
		id = "ClamBed",
		set = "ReefPalace",
		name = "Giant Clam Bed",
		price = 4000,
		kinds = { "floor" },
		size = Vector3.new(8, 7.4, 8.3),
		prop = "ClamBed",
		front = 90,
		color = Color3.fromRGB(86, 82, 190),
		lamp = Color3.fromRGB(210, 236, 255),
		blurb = "A bed in a giant clam, its pearl glowing at the head",
	},
	{
		id = "BrainOttoman",
		set = "ReefPalace",
		name = "Brain Coral Ottoman",
		price = 1500,
		kinds = { "floor" },
		size = Vector3.new(4.2, 2.9, 4.2),
		prop = "BrainOttoman",
		front = 90,
		color = Color3.fromRGB(236, 196, 60),
		blurb = "A round brain coral, just the right height",
	},
	{
		id = "StaghornChandelier",
		set = "ReefPalace",
		name = "Staghorn Chandelier",
		price = 3000,
		kinds = { "ceiling" },
		size = Vector3.new(5.3, 6.5, 5.3),
		prop = "StaghornChandelier",
		front = 90,
		color = Color3.fromRGB(160, 90, 210),
		lamp = Color3.fromRGB(110, 255, 230),
		blurb = "Purple staghorn holding glowing sea-glass orbs",
	},
	{
		id = "FanCoralScreen",
		set = "ReefPalace",
		name = "Fan Coral Screen",
		price = 2500,
		kinds = { "floor" },
		size = Vector3.new(6.1, 6.5, 5.4),
		prop = "FanCoralScreen",
		front = 90,
		color = Color3.fromRGB(214, 110, 70),
		blurb = "Three fan corals in driftwood frames",
	},
	{
		id = "CoralRug",
		set = "ReefPalace",
		name = "Coral Rug",
		price = 1800,
		kinds = { "floor" },
		size = Vector3.new(10, 0.2, 7),
		rug = "oval",
		flat = true,
		color = Color3.fromRGB(50, 150, 150),
		blurb = "An oval rug of teal, orange and purple coral shapes",
	},
	-- Shipwreck Captain (Shipwreck Graveyard): a captain's cabin
	{
		id = "CaptainsDesk",
		set = "Shipwreck",
		name = "Captain's Desk",
		price = 5500,
		kinds = { "floor" },
		size = Vector3.new(7.5, 4.1, 4),
		prop = "CaptainsDesk",
		front = 90,
		color = Color3.fromRGB(70, 62, 52),
		blurb = "Dark wood and brass, a spyglass and a map on top",
	},
	{
		id = "ShipsWheel",
		set = "Shipwreck",
		name = "Ship's Wheel",
		price = 4000,
		kinds = { "wall" },
		size = Vector3.new(5.2, 6, 1.9),
		prop = "ShipsWheel",
		front = 90,
		color = Color3.fromRGB(110, 66, 44),
		blurb = "A ship's wheel mounted on the wall",
	},
	{
		id = "ShipLantern",
		set = "Shipwreck",
		name = "Ship's Lantern",
		price = 4500,
		kinds = { "ceiling" },
		size = Vector3.new(1.6, 5, 1.6),
		prop = "ShipLantern",
		front = 90,
		color = Color3.fromRGB(170, 130, 60),
		lamp = Color3.fromRGB(120, 255, 160),
		blurb = "Aged brass and green sea glass, on a chain",
	},
	{
		id = "BronzeCannon",
		set = "Shipwreck",
		name = "Bronze Cannon",
		price = 6500,
		kinds = { "floor" },
		size = Vector3.new(4, 4.5, 7.3),
		prop = "BronzeCannon",
		front = 90,
		color = Color3.fromRGB(150, 110, 60),
		blurb = "A ship's cannon on its wooden carriage",
	},
	{
		id = "CargoStack",
		set = "Shipwreck",
		name = "Barrels and Crate",
		price = 3500,
		kinds = { "floor" },
		size = Vector3.new(6.2, 5.3, 6.5),
		prop = "CargoStack",
		front = 90,
		color = Color3.fromRGB(96, 80, 60),
		blurb = "Barnacled barrels stacked on a crate",
	},
	{
		id = "ShipAnchor",
		set = "Shipwreck",
		name = "Anchor",
		price = 5000,
		kinds = { "floor" },
		size = Vector3.new(6.5, 8, 5.6),
		prop = "ShipAnchor",
		front = 90,
		color = Color3.fromRGB(80, 66, 60),
		blurb = "A rusted anchor with its rope coiled round it",
	},
	-- Sunken Temple (Sunken Ruins): carved stone and teal fire
	{
		id = "RuneThrone",
		set = "SunkenTemple",
		name = "Rune Throne",
		price = 12000,
		kinds = { "floor" },
		size = Vector3.new(5.9, 7, 4.4),
		prop = "RuneThrone",
		front = 90,
		color = Color3.fromRGB(120, 140, 120),
		lamp = Color3.fromRGB(90, 255, 220),
		blurb = "A stone throne carved with waves and glowing runes",
	},
	{
		id = "ColumnPlanter",
		set = "SunkenTemple",
		name = "Column Planter",
		price = 7000,
		kinds = { "floor" },
		size = Vector3.new(2.4, 6, 2.5),
		prop = "ColumnPlanter",
		front = 90,
		color = Color3.fromRGB(140, 150, 130),
		blurb = "A broken temple column with sea grass growing from it",
	},
	{
		id = "TealBrazier",
		set = "SunkenTemple",
		name = "Teal Brazier",
		price = 9000,
		kinds = { "floor" },
		size = Vector3.new(3.5, 5, 3.3),
		prop = "TealBrazier",
		front = 90,
		color = Color3.fromRGB(150, 100, 60),
		lamp = Color3.fromRGB(90, 255, 220),
		blurb = "A bronze brazier holding a cold teal flame",
	},
	{
		id = "GlyphTablet",
		set = "SunkenTemple",
		name = "Glyph Tablet",
		price = 10000,
		kinds = { "wall" },
		size = Vector3.new(4, 7, 1.8),
		prop = "GlyphTablet",
		front = 90,
		color = Color3.fromRGB(130, 146, 126),
		lamp = Color3.fromRGB(90, 255, 220),
		blurb = "A stone tablet of a fish and glowing glyphs",
	},
	{
		id = "GrouperStatue",
		set = "SunkenTemple",
		name = "Grouper Guardian",
		price = 14000,
		kinds = { "floor" },
		size = Vector3.new(3.1, 7, 3.8),
		prop = "GrouperStatue",
		front = 90,
		color = Color3.fromRGB(128, 140, 120),
		blurb = "A stone grouper standing guard on its plinth",
	},
	{
		id = "WaveMosaicRug",
		set = "SunkenTemple",
		name = "Wave Mosaic",
		price = 6000,
		kinds = { "floor" },
		size = Vector3.new(9, 0.2, 9),
		rug = "square",
		flat = true,
		color = Color3.fromRGB(40, 70, 140),
		blurb = "Blue and gold stone tiles in a wave pattern",
	},
	-- Vent Forge (Hydrothermal Vents): basalt, lava and sulfur
	{
		id = "LavaFirePit",
		set = "VentForge",
		name = "Lava Fire Pit",
		price = 15000,
		kinds = { "floor" },
		size = Vector3.new(6, 2.4, 6),
		prop = "LavaFirePit",
		front = 90,
		color = Color3.fromRGB(50, 44, 44),
		lamp = Color3.fromRGB(255, 120, 40),
		blurb = "A ring of basalt round glowing lava",
	},
	{
		id = "ObsidianTable",
		set = "VentForge",
		name = "Obsidian Table",
		price = 12000,
		kinds = { "floor" },
		size = Vector3.new(8, 2.2, 4.9),
		prop = "ObsidianTable",
		front = 90,
		color = Color3.fromRGB(40, 38, 44),
		blurb = "Black obsidian veined with lava on basalt legs",
	},
	{
		id = "LavaLamp",
		set = "VentForge",
		name = "Lava Lamp",
		price = 16000,
		kinds = { "floor" },
		size = Vector3.new(3.1, 7, 3.1),
		prop = "LavaLamp",
		front = 90,
		color = Color3.fromRGB(240, 100, 50),
		lamp = Color3.fromRGB(255, 96, 40),
		blurb = "Glowing lava blobs rising in a glass column",
	},
	{
		id = "SulfurCrystals",
		set = "VentForge",
		name = "Sulfur Crystals",
		price = 9000,
		kinds = { "floor", "wall" },
		size = Vector3.new(4, 4, 3.3),
		prop = "SulfurCrystals",
		front = 90,
		color = Color3.fromRGB(250, 230, 60),
		lamp = Color3.fromRGB(255, 236, 90),
		blurb = "Bright sulfur crystals growing from vent rock",
	},
	{
		id = "VentCauldron",
		set = "VentForge",
		name = "Vent Cauldron",
		price = 11000,
		kinds = { "floor" },
		size = Vector3.new(3.5, 4.5, 3.4),
		prop = "VentCauldron",
		front = 90,
		color = Color3.fromRGB(56, 52, 56),
		bubbles = true,
		blurb = "An iron cauldron warming on a little vent",
	},
	{
		id = "TubeWormPlanter",
		set = "VentForge",
		name = "Tube Worm Planter",
		price = 10000,
		kinds = { "floor" },
		size = Vector3.new(4.6, 4.6, 4.3),
		prop = "TubeWormPlanter",
		front = 90,
		color = Color3.fromRGB(200, 60, 50),
		blurb = "Red and white tube worms in a basalt pot",
	},
	-- Abyss Glow (Abyssal Trench): bioluminescence in the dark
	{
		id = "JellyChandelier",
		set = "AbyssGlow",
		name = "Jellyfish Chandelier",
		price = 30000,
		kinds = { "ceiling" },
		size = Vector3.new(4.2, 8, 4.2),
		prop = "JellyChandelier",
		front = 90,
		color = Color3.fromRGB(170, 130, 255),
		lamp = Color3.fromRGB(120, 240, 255),
		blurb = "A great violet jelly trailing glowing tentacles",
	},
	{
		id = "AnglerLamp",
		set = "AbyssGlow",
		name = "Angler Lure Lamp",
		price = 22000,
		kinds = { "floor" },
		size = Vector3.new(3.6, 8, 2.2),
		prop = "AnglerLamp",
		front = 90,
		color = Color3.fromRGB(40, 44, 54),
		lamp = Color3.fromRGB(90, 240, 255),
		blurb = "A curved stalk with a glowing lure at its tip",
	},
	{
		id = "GlowCoralBed",
		set = "AbyssGlow",
		name = "Glow Coral Bed",
		price = 35000,
		kinds = { "floor" },
		size = Vector3.new(9, 6.2, 10),
		prop = "GlowCoralBed",
		front = 90,
		color = Color3.fromRGB(40, 60, 120),
		lamp = Color3.fromRGB(70, 150, 255),
		blurb = "A bed framed in glowing blue coral",
	},
	{
		id = "VoidThrone",
		set = "AbyssGlow",
		name = "Void Throne",
		price = 40000,
		kinds = { "floor" },
		size = Vector3.new(5.8, 8, 4.8),
		prop = "VoidThrone",
		front = 90,
		color = Color3.fromRGB(34, 30, 44),
		lamp = Color3.fromRGB(170, 90, 255),
		blurb = "Black stone grown through with violet void crystal",
	},
	{
		id = "PlanktonRug",
		set = "AbyssGlow",
		name = "Plankton Swirl Rug",
		price = 18000,
		kinds = { "floor" },
		size = Vector3.new(9, 0.2, 9),
		rug = "round",
		flat = true,
		color = Color3.fromRGB(26, 36, 70),
		blurb = "Navy, with a swirl of glowing plankton",
	},
	{
		id = "KrakenEyePedestal",
		set = "AbyssGlow",
		name = "Kraken Eye Orb",
		price = 32000,
		kinds = { "floor" },
		size = Vector3.new(3.1, 6, 3.1),
		prop = "KrakenEyePedestal",
		front = 90,
		color = Color3.fromRGB(46, 44, 50),
		lamp = Color3.fromRGB(255, 170, 50),
		blurb = "A giant amber eye in a glass orb, on a stone plinth",
	},
	-- Boss Trophies: proof you were there
	{
		id = "MegalodonJawArch",
		set = "Trophies",
		name = "Megalodon Jaw Arch",
		price = 60000,
		kinds = { "floor" },
		size = Vector3.new(14, 13.8, 13.6),
		prop = "MegalodonJawArch",
		front = 90,
		color = Color3.fromRGB(170, 160, 146),
		blurb = "A Megalodon's jaws as an arch: swim through them",
	},
	{
		id = "KrakenEyeLantern",
		set = "Trophies",
		name = "Kraken-Eye Lantern",
		price = 30000,
		kinds = { "ceiling" },
		size = Vector3.new(2.4, 6, 2.4),
		prop = "KrakenEyeLantern",
		front = 90,
		color = Color3.fromRGB(60, 50, 50),
		lamp = Color3.fromRGB(190, 110, 255),
		blurb = "A squid's eye glowing in a wrought-iron lantern",
	},
	{
		id = "SharkToothPlaque",
		set = "Trophies",
		name = "Shark Tooth Plaque",
		price = 20000,
		kinds = { "wall" },
		size = Vector3.new(3.5, 5, 1.3),
		prop = "SharkToothPlaque",
		front = 90,
		color = Color3.fromRGB(110, 70, 50),
		blurb = "One giant tooth, mounted",
	},
	{
		id = "BronzeTentacle",
		set = "Trophies",
		name = "Bronze Tentacle",
		price = 35000,
		kinds = { "floor" },
		size = Vector3.new(4.9, 7, 4.8),
		prop = "BronzeTentacle",
		front = 90,
		color = Color3.fromRGB(120, 90, 60),
		blurb = "A Giant Squid's tentacle cast in bronze",
	},
	{
		id = "TreasurePile",
		set = "Trophies",
		name = "Treasure Hoard",
		price = 25000,
		kinds = { "floor" },
		size = Vector3.new(6, 5.1, 5.9),
		prop = "TreasurePile",
		front = 90,
		color = Color3.fromRGB(150, 100, 60),
		lamp = Color3.fromRGB(255, 210, 110),
		blurb = "An open chest spilling gold and pearls",
	},
	{
		id = "ReefGlobe",
		set = "Trophies",
		name = "Reef Globe",
		price = 28000,
		kinds = { "floor" },
		size = Vector3.new(2.7, 5, 2.7),
		prop = "ReefGlobe",
		front = 90,
		color = Color3.fromRGB(190, 150, 70),
		lamp = Color3.fromRGB(110, 255, 220),
		blurb = "A tiny glowing reef under a glass dome",
	},
}

local sets: { Set } = {
	{
		id = "KelpCottage",
		name = "Kelp Cottage",
		biome = "Kelp Shallows",
		tier = "Common",
		blurb = "Driftwood and woven kelp",
	},
	{
		id = "ReefPalace",
		name = "Reef Palace",
		biome = "Coral Reef",
		tier = "Uncommon",
		blurb = "Coral grown into thrones and beds",
	},
	{
		id = "Shipwreck",
		name = "Shipwreck Captain",
		biome = "Shipwreck Graveyard",
		tier = "Rare",
		blurb = "A captain's cabin raised from the wrecks",
	},
	{
		id = "SunkenTemple",
		name = "Sunken Temple",
		biome = "Sunken Ruins",
		tier = "Epic",
		blurb = "Carved stone, runes and teal fire",
	},
	{
		id = "VentForge",
		name = "Vent Forge",
		biome = "Hydrothermal Vents",
		tier = "Epic",
		blurb = "Basalt, lava and sulfur",
	},
	{
		id = "AbyssGlow",
		name = "Abyss Glow",
		biome = "Abyssal Trench",
		tier = "Legendary",
		blurb = "Bioluminescence from the deepest dark",
	},
	{
		id = "Trophies",
		name = "Boss Trophies",
		biome = "World bosses",
		tier = "Trophy",
		blurb = "Proof you were there",
	},
}

-- Starter layouts (owner, 2026-10-14: "yes add the snapping and starter layouts"):
-- each set's floor pieces as a ready arrangement round a spot, front (+z) toward
-- you. In Build mode, with a piece of the set picked, L lays out every piece of it
-- you have in the tray where you aim (DenSpace.fitLayout finds room: it tries the
-- spot, then spirals out, turned to face you first); each piece can be moved after.
-- Wall and ceiling pieces stay in the tray to hang where you like. x, z in studs
-- from the spot; r is the piece's turn (0 faces you, 90 faces your left).
export type LayoutPiece = { id: string, x: number, z: number, r: number }

local layouts: { [string]: { LayoutPiece } } = {
	KelpCottage = {
		{ id = "BraidedKelpRug", x = 0, z = 0, r = 0 },
		{ id = "KelpArmchair", x = -2.2, z = -1.5, r = -20 },
		{ id = "BarrelTable", x = 2.2, z = 0.5, r = 0 },
		{ id = "ScallopLamp", x = -5.6, z = -3, r = 0 },
		{ id = "DriftwoodShelf", x = 2, z = -5.6, r = 0 },
		{ id = "KelpHammock", x = 8.5, z = -1, r = 90 },
	},
	ReefPalace = {
		{ id = "CoralRug", x = 0, z = 0, r = 0 },
		{ id = "CoralThrone", x = 0, z = -2.5, r = 0 },
		{ id = "BrainOttoman", x = 3.5, z = 1.5, r = 0 },
		{ id = "FanCoralScreen", x = 0, z = -7.5, r = 0 },
		{ id = "ClamBed", x = -8, z = -2, r = -90 },
	},
	Shipwreck = {
		{ id = "CaptainsDesk", x = 0, z = -2, r = 0 },
		{ id = "CargoStack", x = -7, z = -2.5, r = 0 },
		{ id = "BronzeCannon", x = 6.5, z = 1, r = -90 },
		{ id = "ShipAnchor", x = -6.5, z = 4, r = 25 },
	},
	SunkenTemple = {
		{ id = "WaveMosaicRug", x = 0, z = 0, r = 0 },
		{ id = "RuneThrone", x = 0, z = -2.2, r = 0 },
		{ id = "TealBrazier", x = -4.2, z = -1, r = 0 },
		{ id = "ColumnPlanter", x = 4.2, z = -1, r = 0 },
		{ id = "GrouperStatue", x = 0, z = 6.5, r = 180 },
	},
	VentForge = {
		{ id = "LavaFirePit", x = 0, z = 1, r = 0 },
		{ id = "ObsidianTable", x = 0, z = -5.5, r = 0 },
		{ id = "LavaLamp", x = -6, z = -5.5, r = 0 },
		{ id = "SulfurCrystals", x = 6, z = -5.5, r = 0 },
		{ id = "VentCauldron", x = 5, z = 2.5, r = 0 },
		{ id = "TubeWormPlanter", x = -5, z = 2.5, r = 0 },
	},
	AbyssGlow = {
		{ id = "PlanktonRug", x = 0, z = 0, r = 0 },
		{ id = "VoidThrone", x = 0, z = -2, r = 0 },
		{ id = "AnglerLamp", x = -4.8, z = -1, r = 20 },
		{ id = "KrakenEyePedestal", x = 4.5, z = -1, r = 0 },
		{ id = "GlowCoralBed", x = 0, z = -10.5, r = 0 },
	},
	Trophies = {
		{ id = "MegalodonJawArch", x = 0, z = -5, r = 0 },
		{ id = "BronzeTentacle", x = -7, z = 4.5, r = 30 },
		{ id = "TreasurePile", x = 7, z = 4.5, r = -30 },
		{ id = "ReefGlobe", x = 0, z = 4, r = 0 },
	},
}

export type Glow = { id: string, name: string, color: Color3, price: number }

local glows: { Glow } = {
	{ id = "Teal", name = "Teal", color = Color3.fromRGB(86, 222, 255), price = 0 },
	{ id = "Gold", name = "Gold", color = Color3.fromRGB(255, 204, 92), price = 300 },
	{ id = "Rose", name = "Rose", color = Color3.fromRGB(255, 120, 170), price = 300 },
	{ id = "Violet", name = "Violet", color = Color3.fromRGB(180, 110, 255), price = 300 },
	{ id = "Lime", name = "Lime", color = Color3.fromRGB(150, 255, 120), price = 300 },
	{ id = "Ice", name = "Ice", color = Color3.fromRGB(220, 244, 255), price = 300 },
	{ id = "Ember", name = "Ember", color = Color3.fromRGB(255, 130, 50), price = 300 },
}

local floors: { FloorStyle } = {
	{
		id = "Flagstone",
		name = "Flagstone",
		price = 0,
		material = Enum.Material.Slate,
		colors = { Color3.fromRGB(118, 124, 126), Color3.fromRGB(100, 108, 112) },
		blurb = "Grey slate flags",
	},
	{
		id = "Driftwood",
		name = "Driftwood Planks",
		price = 800,
		material = Enum.Material.WoodPlanks,
		colors = { Color3.fromRGB(132, 104, 76), Color3.fromRGB(116, 90, 64) },
		blurb = "Sea-worn planks, warm underfoot",
	},
	{
		id = "Sandstone",
		name = "Sandstone Tiles",
		price = 1500,
		material = Enum.Material.Sandstone,
		colors = { Color3.fromRGB(198, 176, 132), Color3.fromRGB(180, 158, 116) },
		blurb = "Pale sandstone, cut square",
	},
	{
		id = "Marble",
		name = "Pearl Marble",
		price = 4000,
		material = Enum.Material.Marble,
		-- Toned down: pale enough to glare under the orb lamps (PC 2026-10-16 round 2)
		colors = { Color3.fromRGB(204, 206, 212), Color3.fromRGB(188, 192, 200) },
		blurb = "Polished pearl-white marble",
	},
	{
		id = "Mosaic",
		name = "Reef Mosaic",
		price = 6000,
		material = Enum.Material.Pebble,
		-- Closer in tone and less saturated: the bright orange-and-teal patchwork was
		-- loud (PC 2026-10-16 round 2)
		colors = { Color3.fromRGB(76, 140, 148), Color3.fromRGB(176, 128, 106) },
		blurb = "Teal and coral pebble mosaic",
	},
	{
		id = "Obsidian",
		name = "Glowing Obsidian",
		price = 12000,
		material = Enum.Material.Basalt,
		colors = { Color3.fromRGB(38, 42, 54), Color3.fromRGB(30, 34, 44) },
		seams = true,
		blurb = "Black volcanic glass with your glow in its seams",
	},
}

local function index<T>(list: { T }): { [string]: T }
	local map: { [string]: T } = {}
	for _, entry in list do
		map[(entry :: any).id] = entry
	end
	return map
end

return {
	levels = levels,
	storeys = storeys,
	rooms = rooms,
	roomsById = index(rooms),
	shafts = shafts,
	gardenSpots = gardenSpots,
	items = items,
	itemsById = index(items),
	sets = sets,
	setsById = index(sets),
	layouts = layouts,
	glows = glows,
	glowsById = index(glows),
	floors = floors,
	floorsById = index(floors),
	-- The Den Expansion pass: this many more things placed, at any level
	expansionCapacity = 25,
	-- The main room's back wall at plaque height (local z), before and after the
	-- Burrow carves it back (the trophy wall is seated on the real rock by raycast)
	backWall = { -30, -90 },
	-- The furthest the rooms reach back and forward (local z): the den's block of
	-- rock (DenCarve) and the safe zone (Layout.denAt)
	maxBack = -180,
	maxFront = 30,
	-- The Haul Pool, near the front of the Nook: you come in over it, so swimming
	-- home through your doorway banks your Haul (local z, and its radius)
	pool = { z = 12, radius = 8 },
	-- The way out: a bubble portal on the main storey's front wall (its middle's
	-- height over the deck, and its radius)
	exit = { y = 13, radius = 9 },
	-- Where the interiors are: a grid of blocks at the hub's height, far outside the
	-- play area (the map's rim is 1,500 out, the Horizon walls 2,900), `spacing`
	-- apart, `columns` to a row
	interior = { x = 5200, z = -640, spacing = 640, columns = 4 },
	-- The hint to open the den menu shows within this of your own Haul Pool
	hintReach = 16,
	-- The Coral Garden (owner, 2026-10-09: "an afk aspect of the game to earn
	-- something to keep players coming back"): every den grows coral and a few
	-- shells over real time, online or off, up to `hours` of growth (the Deep Garden
	-- pass: Config/Monetization). Resting in your own den grows it `rest` times
	-- faster and collects it every `collectEvery` seconds; swimming in collects it
	-- too. A bigger den grows more (per hour, by den level).
	garden = {
		coral = { 60, 100, 160, 250, 380 },
		shells = { 4, 6, 9, 12, 16 },
		hours = 8,
		rest = 2,
		collectEvery = 60,
	},
}
