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
--
-- v4 (owner, 2026-10-18: "Den needs to be bigger with more space ... No reason a wall
-- lantern should be the same size as a rug or table"): every room 1.22 times as wide
-- and as long (about half as much floor again: a 74 × 72 Nook), and the things at a
-- real scale beside a fish (2 to 17 studs long): rugs 18 to 24 studs across, beds,
-- thrones and tables about twice as big, a wall lantern still a lantern. Gardens,
-- piles and clusters are built of many pieces (`cluster`, Shared/DenItems). Saves
-- from before are moved over once (DenService `relayout`, DenSpace.grow, `layout`).
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
	-- A wing's rooms (Shared/DenSpace builds them from `wings`): `cx` its middle
	-- across (0 for the house's own rooms), `cross` when it runs out sideways (its
	-- arch runs along x, so `x` is half its length and z0..z1 its width), its own
	-- `wall` over the deck and `ceiling` crown (else the storey's), the wing slot it
	-- belongs to, and whether it's the short passage in from the house
	cx: number?,
	cross: boolean?,
	wall: number?,
	ceiling: number?,
	wing: string?,
	passage: boolean?,
}

-- A wing (owner, 2026-10-28: "a coral upgrade that extends the size of your den ...
-- choice of different rooms, open layout ... a passive element"; the proposal in
-- docs/proposals/2026-10-28-den-expansion.md, approved: "i like the den changes lets
-- do that and try it out"): past the Sanctum the house grows sideways. Each of the
-- four `wingSlots` (doorways in the main storey's side walls) takes one wing, bought
-- with coral and swapped later for `wing.refund` of its price back. A wing is a room
-- running out from the side wall through a short arched passage.
export type Wing = {
	id: string,
	name: string,
	price: number,
	capacity: number, -- more things the den holds
	length: number, -- how far it runs out from the passage (along x)
	depth: number, -- its width (along z)
	wall: number, -- its upright walls over the deck
	ceiling: number, -- its crown (local y)
	tier: string, -- Config/Tiers id: its colour in the menu
	blurb: string,
}

-- A doorway in the main storey's side wall a wing is built onto: its side (-1 left,
-- 1 right, across the den) and its middle (local z)
export type WingSlot = { id: string, name: string, side: number, z: number }

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
	-- A living fire over it (Shared/Fx `hearth`, in its `lamp` colour): its bed `at`
	-- of its height over its middle, `width` of its width across, `height` of its
	-- height tall
	flame: { at: number, width: number, height: number }?,
	rug: string?, -- a rug's shape ("round", "oval", "square"); its top-down art is Config/Textures `rug<id>`
	front: number?, -- degrees its imported prop is turned to face out (Tripo props face +X: 90)
	cluster: Cluster?, -- built of many pieces (a garden, a pile, a cluster): Shared/DenItems
	-- With `glow`: its prop's texture lets the den's glow through where its alpha is low
	-- (the banner's cloth, SurfaceAppearance Overlay), so its MeshParts are colored, not
	-- the whole texture tinted
	overlay: boolean?,
}

-- A thing built of many pieces (owner, 2026-10-18: "An anemone garden is literally
-- just one anemone lmao. everything is just a single item"): an optional bed under
-- them, then `count` pieces of `kinds` (taken in turn) scattered over the thing's
-- footprint at varied sizes and turns, the tallest toward the back. Seeded by the
-- thing's id, so the ghost, the shop's photo and the placed thing are alike. Each
-- piece is the imported reef prop where there is one (WorldProps), else part-built.
--   kinds: "Anemone", "Brain", "Sponge", "Staghorn", "Fan", "Shell", "Kelp" (a
--   standing frond), "Blade" (a kelp leaf lying down), "Crystal", "Rock", "Star"
export type Cluster = {
	kinds: { string },
	count: number,
	bed: string?, -- "sand" (a sand bed in a ring of stones), "rock" (a low rock base), "kelp" or "heap" (a mound)
	colors: { Color3 }?, -- taken in turn over the pieces (default: the reef's colors)
	glow: boolean?, -- glowing tips and a light (a lamp)
	spread: number?, -- how far out the pieces go, as a share of the half-footprint (default 0.78)
}

-- A doorway style for your den's front door on the plaza (owner, 2026-10-18: "once
-- all the dens are used up too it would be hard to see ours ... Would be nice if we
-- could change the actual entrance to our den to unlockable versions to make it
-- easier to spot"). Bought once with coral when its den level (and achievement) is
-- reached, then worn or swapped in the den menu; the server builds it (DenDoor).
export type Door = {
	id: string,
	name: string,
	price: number,
	level: number?, -- the den level it needs
	achievement: string?, -- the Config/Achievements id it needs
	blurb: string,
	colors: { Color3 }, -- its swatches in the menu (stone, trim, glow)
	glow: Color3, -- its lanterns' and portal's light
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
		capacity = 24,
		blurb = "A big cave room of your own: your pool, your garden and the trophy wall.",
	},
	{
		level = 2,
		name = "Burrow",
		cost = 1000,
		capacity = 48,
		blurb = "A second great room runs far back into the rock, with room for twice as much.",
	},
	{
		level = 3,
		name = "Hall",
		cost = 12000,
		capacity = 80,
		blurb = "A shaft drops to a great vaulted hall below, and the Coral Garden moves to its middle.",
	},
	{
		level = 4,
		name = "Grotto",
		cost = 45000,
		capacity = 125,
		blurb = "The hall opens into wide wings and a deep grotto at its back.",
	},
	{
		level = 5,
		name = "Sanctum",
		cost = 150000,
		capacity = 180,
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
-- holds the way out on the main storey. v4 (2026-10-18): every number 1.22 times
-- the v3 rooms' (`GROWTH`), so an old save's things move out with their walls.
local rooms: { Room } = {
	{ id = "Nook", level = 1, storey = 1, x = 37, z0 = 36, z1 = -36 },
	{ id = "Burrow", level = 2, storey = 1, x = 34, z0 = -32, z1 = -110 },
	{ id = "HallNave", level = 3, storey = 2, x = 39, z0 = 36, z1 = -24 },
	{ id = "HallMid", level = 3, storey = 2, x = 49, z0 = -24, z1 = -86 },
	{ id = "HallBack", level = 3, storey = 2, x = 56, z0 = -86, z1 = -146, pillars = 17 },
	{ id = "GrottoWings", level = 4, storey = 2, x = 71, z0 = -36, z1 = -146 },
	{ id = "GrottoDeep", level = 4, storey = 2, x = 76, z0 = -146, z1 = -208, pillars = 17 },
	{ id = "SanctumFore", level = 5, storey = 3, x = 44, z0 = 36, z1 = -24 },
	{ id = "SanctumNave", level = 5, storey = 3, x = 61, z0 = -24, z1 = -122, pillars = 19 },
	{ id = "SanctumApse", level = 5, storey = 3, x = 80, z0 = -122, z1 = -220, pillars = 19 },
}

-- The wings (the proposal's five rooms). The Aquarium Hall's tanks, the Trophy
-- Gallery's plinths, the Grotto Pool's second Haul Pool and the Observatory's window
-- are built by DenBuilder; the Great Hall is simply big, with a high vault.
local wings: { Wing } = {
	{
		id = "AquariumHall",
		name = "Aquarium Hall",
		price = 250000,
		capacity = 40,
		length = 64,
		depth = 44,
		wall = 18,
		ceiling = 32,
		tier = "Rare",
		blurb = "A long gallery of 8 more aquarium tanks: your rare catches on show, earning coral",
	},
	{
		id = "TrophyGallery",
		name = "Trophy Gallery",
		price = 250000,
		capacity = 40,
		length = 64,
		depth = 44,
		wall = 18,
		ceiling = 32,
		tier = "Rare",
		blurb = "Your biggest catches, boss trophies and titles on plinths for visitors to see",
	},
	{
		id = "GrottoPool",
		name = "Grotto Pool",
		price = 400000,
		capacity = 40,
		length = 60,
		depth = 52,
		wall = 16,
		ceiling = 34,
		tier = "Epic",
		blurb = "A sunken grotto with a second Haul Pool to bank at and a waterfall of bubbles",
	},
	{
		id = "Observatory",
		name = "Observatory",
		price = 600000,
		capacity = 40,
		length = 58,
		depth = 56,
		wall = 14,
		ceiling = 42,
		tier = "Epic",
		blurb = "A domed room with a great window onto the deep, whales and jellies drifting by",
	},
	{
		id = "GreatHall",
		name = "Great Hall",
		price = 900000,
		capacity = 90,
		length = 80,
		depth = 60,
		wall = 26,
		ceiling = 48,
		tier = "Legendary",
		blurb = "Simply huge: room for 90 more things under a high vault for the tallest pieces",
	},
}

-- The doorways the wings open from: two down each side of the main storey, off
-- the Nook (z 0) and off the Burrow (z -78), clear of the pool, the shaft and the
-- aquarium tanks on the side walls
local wingSlots: { WingSlot } = {
	{ id = "FrontLeft", name = "Front left", side = -1, z = 0 },
	{ id = "FrontRight", name = "Front right", side = 1, z = 0 },
	{ id = "BackLeft", name = "Back left", side = -1, z = -78 },
	{ id = "BackRight", name = "Back right", side = 1, z = -78 },
}

local shafts: { Shaft } = {
	{ id = "HallShaft", level = 3, from = 1, to = 2, z = -70, radius = 10 },
	{ id = "SanctumShaft", level = 5, from = 2, to = 3, z = -110, radius = 11 },
}

local gardenSpots: { GardenSpot } = {
	{ level = 1, storey = 1, z = -32, shape = "trough", width = 30, depth = 6 },
	{ level = 2, storey = 1, z = -106, shape = "trough", width = 30, depth = 6 },
	{ level = 3, storey = 2, z = 4, shape = "bed", width = 28, depth = 20 },
}

-- Sizes (v4, owner 2026-10-18): beside a fish 2 to 17 studs long in a 74 × 72 Nook.
-- The Tripo pieces keep their own proportions (their boxes were measured off the
-- models), floor things at 1.9 times their v3 size, ceiling things 1.6, wall things
-- 1.5; rugs 18 to 24 studs across; a wall lantern stays a lantern.
local REEF = {
	Color3.fromRGB(255, 112, 130),
	Color3.fromRGB(255, 156, 84),
	Color3.fromRGB(186, 112, 236),
	Color3.fromRGB(255, 212, 96),
	Color3.fromRGB(110, 214, 200),
	Color3.fromRGB(120, 170, 255),
}

local items: { Item } = {
	-- Batch 2 of the den props (owner, 2026-10-19: "MUCH much better"; boards
	-- assets/concepts/DenPropsA.jpg and DenPropsB.jpg): the eight first pieces kept
	-- their ids (placed copies stay) and became Tripo models (`den_props2_glb`, the
	-- prop of the same name; part-built stand-ins of the same designs until it's
	-- imported, Shared/DenItems), with four new ones beside them. Sizes are the
	-- models' own proportions at a real scale; lights carry `lamp`.
	{
		id = "CoralLamp",
		name = "Coral Lamp",
		price = 250,
		kinds = { "floor" },
		size = Vector3.new(5.2, 12, 5.6),
		prop = "CoralLamp",
		color = Color3.fromRGB(240, 112, 48),
		lamp = Color3.fromRGB(255, 160, 90),
		blurb = "A branching coral trunk under a glowing fan-coral shade",
	},
	{
		id = "KelpBed",
		name = "Kelp Bed",
		price = 180,
		kinds = { "floor" },
		-- (its headboard at the back, so snapping backs it onto a wall)
		size = Vector3.new(12.4, 6.2, 16),
		prop = "KelpBed",
		color = Color3.fromRGB(98, 142, 62),
		blurb = "A woven kelp-rope bed with a moss mattress and teal pillows",
	},
	{
		id = "KelpRug",
		name = "Woven Kelp Rug",
		price = 200,
		kinds = { "floor" },
		size = Vector3.new(20, 0.2, 14),
		color = Color3.fromRGB(70, 120, 92),
		flat = true,
		blurb = "A rug of woven kelp, for under everything else",
	},
	{
		id = "ShellPile",
		name = "Shell Pile",
		price = 150,
		kinds = { "floor" },
		size = Vector3.new(8, 3.6, 7),
		color = Color3.fromRGB(242, 228, 204),
		cluster = {
			kinds = { "Shell" },
			count = 18,
			bed = "heap",
			colors = {
				Color3.fromRGB(242, 228, 204),
				Color3.fromRGB(236, 196, 160),
				Color3.fromRGB(214, 222, 236),
				Color3.fromRGB(250, 214, 170),
				Color3.fromRGB(198, 168, 140),
			},
			spread = 0.7,
		},
		blurb = "Shells you've gathered, heaped up",
	},
	{
		id = "AnemoneGarden",
		name = "Anemone Garden",
		price = 300,
		kinds = { "floor" },
		size = Vector3.new(13, 5, 11),
		color = Color3.fromRGB(240, 110, 120),
		cluster = {
			kinds = { "Anemone", "Anemone", "Anemone", "Rock", "Anemone", "Star" },
			count = 12,
			bed = "sand",
			colors = REEF,
		},
		blurb = "Swaying anemones in a bed of sand",
	},
	{
		id = "BrainCoral",
		name = "Brain Coral",
		price = 220,
		kinds = { "floor" },
		size = Vector3.new(9, 6, 8),
		color = Color3.fromRGB(250, 220, 110),
		cluster = {
			kinds = { "Brain", "Brain", "Rock", "Brain", "Anemone" },
			count = 5,
			bed = "rock",
			colors = {
				Color3.fromRGB(250, 220, 110),
				Color3.fromRGB(240, 186, 90),
				Color3.fromRGB(150, 140, 126),
				Color3.fromRGB(255, 232, 150),
				Color3.fromRGB(110, 214, 200),
			},
			spread = 0.55,
		},
		blurb = "Fat yellow brain corals on a reef rock",
	},
	{
		id = "TubeSponges",
		name = "Tube Sponges",
		price = 200,
		kinds = { "floor" },
		size = Vector3.new(7, 10, 6),
		color = Color3.fromRGB(170, 110, 220),
		cluster = {
			kinds = { "Sponge" },
			count = 7,
			bed = "rock",
			colors = {
				Color3.fromRGB(170, 110, 220),
				Color3.fromRGB(196, 130, 236),
				Color3.fromRGB(140, 90, 200),
			},
			spread = 0.55,
		},
		blurb = "Tall purple sponges",
	},
	{
		id = "DriftwoodTable",
		name = "Driftwood Table",
		price = 350,
		kinds = { "floor" },
		size = Vector3.new(14, 7.2, 7.1),
		prop = "DriftwoodTable",
		front = 180,
		color = Color3.fromRGB(134, 128, 116),
		blurb = "Driftwood planks on crossed trestles, a bowl of pearls and a jar candle on top",
	},
	{
		id = "SpongeSofa",
		name = "Sponge Sofa",
		price = 750,
		kinds = { "floor" },
		size = Vector3.new(17, 9.3, 8),
		prop = "SpongeSofa",
		color = Color3.fromRGB(56, 160, 166),
		blurb = "Three teal kelp-cloth seats on driftwood, with sponge bolsters and scallop shells",
	},
	{
		id = "ShipwreckBookshelf",
		name = "Shipwreck Bookshelf",
		price = 800,
		kinds = { "floor" },
		size = Vector3.new(9.4, 15, 6.4),
		prop = "ShipwreckBookshelf",
		front = 90,
		color = Color3.fromRGB(72, 58, 48),
		blurb = "Bowed hull planks with a brass porthole, full of books and bottles · backs onto a wall",
	},
	{
		id = "PearlPedestal",
		name = "Pearl Pedestal",
		price = 900,
		kinds = { "floor" },
		size = Vector3.new(3.2, 11, 3.3),
		prop = "PearlPedestal",
		color = Color3.fromRGB(150, 146, 220),
		lamp = Color3.fromRGB(200, 226, 255),
		blurb = "A great pearl in an open clam on a fluted stone column, glowing softly",
	},
	{
		id = "ConchGramophone",
		name = "Conch Gramophone",
		price = 1100,
		kinds = { "floor" },
		size = Vector3.new(4.9, 8.5, 6.5),
		prop = "ConchGramophone",
		color = Color3.fromRGB(196, 150, 64),
		blurb = "A record player on a brass-cornered cabinet, its horn a great spiral conch",
	},
	{
		id = "DecorChest",
		name = "Treasure Chest",
		price = 600,
		kinds = { "floor" },
		size = Vector3.new(9, 7.2, 6.3),
		prop = "TreasureChest",
		color = Color3.fromRGB(78, 54, 36),
		blurb = "A chest like the ones your maps lead to",
	},
	{
		id = "BubbleColumn",
		name = "Bubble Column",
		price = 500,
		kinds = { "floor" },
		size = Vector3.new(7, 2.3, 7),
		prop = "BubbleColumn",
		color = Color3.fromRGB(150, 150, 140),
		bubbles = true,
		blurb = "A bronze vent in a ring of mossy stones, bubbling up to the ceiling",
	},
	{
		id = "CrystalShard",
		name = "Crystal Cluster",
		price = 1200,
		kinds = { "floor", "wall" },
		size = Vector3.new(7, 11, 6),
		color = Color3.fromRGB(110, 230, 255),
		glow = true,
		cluster = {
			kinds = { "Crystal" },
			count = 7,
			bed = "rock",
			spread = 0.5,
		},
		blurb = "A cluster of glowing crystal, on the floor or out of a wall",
	},
	{
		id = "SeaGlassLantern",
		name = "Sea Glass Lantern",
		price = 400,
		kinds = { "wall" },
		size = Vector3.new(1.5, 5, 3.2),
		prop = "SeaGlassLantern",
		front = 90,
		color = Color3.fromRGB(90, 196, 220),
		lamp = Color3.fromRGB(120, 236, 220),
		blurb = "A small iron lantern of sea glass on a scrolled bracket",
	},
	{
		id = "JellyLamp",
		name = "Jellyfish Lamp",
		price = 650,
		kinds = { "ceiling" },
		size = Vector3.new(4.1, 9, 4.7),
		prop = "JellyLamp",
		color = Color3.fromRGB(236, 170, 56),
		lamp = Color3.fromRGB(255, 190, 100),
		blurb = "Three glowing amber jellyfish on brass chains",
	},
	{
		id = "SeaFan",
		name = "Sea Fans",
		price = 220,
		kinds = { "wall" },
		size = Vector3.new(10, 9, 1.6),
		prop = "FanCoral",
		color = Color3.fromRGB(255, 160, 80),
		blurb = "Three wide fan corals spreading over the wall",
	},
	{
		id = "Banner",
		name = "Banner",
		price = 400,
		kinds = { "wall" },
		size = Vector3.new(7.4, 13, 1.2),
		prop = "Banner",
		front = 90,
		color = Color3.fromRGB(46, 150, 150),
		glow = true,
		overlay = true,
		blurb = "A swallowtail banner with a gold fish, its cloth in your glow color",
	},
	{
		id = "TreasureChart",
		name = "Treasure Chart",
		price = 450,
		kinds = { "wall" },
		size = Vector3.new(9, 7.3, 1.5),
		prop = "TreasureChart",
		front = 90,
		color = Color3.fromRGB(124, 170, 172),
		blurb = "A sea chart with a red X, in a rope-bound driftwood frame",
	},
	-- Kelp Cottage (Kelp Shallows): cosy driftwood and woven kelp
	{
		id = "KelpArmchair",
		set = "KelpCottage",
		name = "Kelp Armchair",
		price = 600,
		kinds = { "floor" },
		size = Vector3.new(9.1, 9.5, 8.4),
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
		size = Vector3.new(19, 9.9, 5.9),
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
		size = Vector3.new(8.7, 7.2, 8.7),
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
		size = Vector3.new(4.4, 13.3, 3.6),
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
		size = Vector3.new(12.9, 8.6, 5.1),
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
		size = Vector3.new(18, 0.2, 18),
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
		size = Vector3.new(10.6, 13.3, 8.6),
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
		size = Vector3.new(15.2, 14.1, 15.8),
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
		size = Vector3.new(8, 5.5, 8),
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
		size = Vector3.new(8.5, 10.4, 8.5),
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
		size = Vector3.new(11.6, 12.4, 10.3),
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
		size = Vector3.new(24, 0.2, 16),
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
		size = Vector3.new(14.3, 7.8, 7.6),
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
		size = Vector3.new(7.8, 9, 2.9),
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
		size = Vector3.new(2.6, 8, 2.6),
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
		size = Vector3.new(7.6, 8.6, 13.9),
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
		size = Vector3.new(11.8, 10.1, 12.4),
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
		size = Vector3.new(12.4, 15.2, 10.6),
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
		size = Vector3.new(11.2, 13.3, 8.4),
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
		size = Vector3.new(4.6, 11.4, 4.8),
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
		size = Vector3.new(6.7, 9.5, 6.3),
		prop = "TealBrazier",
		front = 90,
		color = Color3.fromRGB(150, 100, 60),
		lamp = Color3.fromRGB(90, 255, 220),
		-- (its bowl's rim is just over its middle; the flames rise over the model's own
		-- still flame, owner 2026-10-28: "should actually flow like fire")
		flame = { at = 0.06, width = 0.46, height = 0.5 },
		blurb = "A bronze brazier holding a cold teal flame",
	},
	{
		id = "GlyphTablet",
		set = "SunkenTemple",
		name = "Glyph Tablet",
		price = 10000,
		kinds = { "wall" },
		size = Vector3.new(6, 10.5, 2.7),
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
		size = Vector3.new(5.9, 13.3, 7.2),
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
		size = Vector3.new(20, 0.2, 20),
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
		size = Vector3.new(11.4, 4.6, 11.4),
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
		size = Vector3.new(15.2, 4.2, 9.3),
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
		size = Vector3.new(5.9, 13.3, 5.9),
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
		size = Vector3.new(7.6, 7.6, 6.3),
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
		size = Vector3.new(6.7, 8.6, 6.5),
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
		size = Vector3.new(8.7, 8.7, 8.2),
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
		size = Vector3.new(6.7, 12.8, 6.7),
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
		size = Vector3.new(6.8, 15.2, 4.2),
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
		size = Vector3.new(17.1, 11.8, 19),
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
		size = Vector3.new(11, 15.2, 9.1),
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
		size = Vector3.new(22, 0.2, 22),
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
		size = Vector3.new(5.9, 11.4, 5.9),
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
		size = Vector3.new(26.6, 26.2, 25.8),
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
		size = Vector3.new(3.8, 9.6, 3.8),
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
		size = Vector3.new(5.3, 7.5, 2),
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
		size = Vector3.new(9.3, 13.3, 9.1),
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
		size = Vector3.new(11.4, 9.7, 11.2),
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
		size = Vector3.new(5.1, 9.5, 5.1),
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
		{ id = "KelpArmchair", x = -4.2, z = -2.8, r = -20 },
		{ id = "BarrelTable", x = 4.2, z = 0.9, r = 0 },
		{ id = "ScallopLamp", x = -11.6, z = -5.7, r = 0 },
		{ id = "DriftwoodShelf", x = 3.8, z = -10.6, r = 0 },
		{ id = "KelpHammock", x = 16.1, z = -1.9, r = 90 },
	},
	ReefPalace = {
		{ id = "CoralRug", x = 0, z = 0, r = 0 },
		{ id = "CoralThrone", x = 0, z = -4.8, r = 0 },
		{ id = "BrainOttoman", x = 6.6, z = 2.8, r = 0 },
		{ id = "FanCoralScreen", x = 0, z = -14.2, r = 0 },
		{ id = "ClamBed", x = -15.2, z = -3.8, r = -90 },
	},
	Shipwreck = {
		{ id = "CaptainsDesk", x = 0, z = -3.8, r = 0 },
		{ id = "CargoStack", x = -13.3, z = -4.8, r = 0 },
		{ id = "BronzeCannon", x = 12.3, z = 1.9, r = -90 },
		{ id = "ShipAnchor", x = -12.3, z = 7.6, r = 25 },
	},
	SunkenTemple = {
		{ id = "WaveMosaicRug", x = 0, z = 0, r = 0 },
		{ id = "RuneThrone", x = 0, z = -4.2, r = 0 },
		{ id = "TealBrazier", x = -8, z = -1.9, r = 0 },
		{ id = "ColumnPlanter", x = 8, z = -1.9, r = 0 },
		{ id = "GrouperStatue", x = 0, z = 12.3, r = 180 },
	},
	VentForge = {
		{ id = "LavaFirePit", x = 0, z = 1.9, r = 0 },
		{ id = "ObsidianTable", x = 0, z = -10.4, r = 0 },
		{ id = "LavaLamp", x = -11.4, z = -10.4, r = 0 },
		{ id = "SulfurCrystals", x = 11.4, z = -10.4, r = 0 },
		{ id = "VentCauldron", x = 9.5, z = 4.8, r = 0 },
		{ id = "TubeWormPlanter", x = -9.5, z = 4.8, r = 0 },
	},
	AbyssGlow = {
		{ id = "PlanktonRug", x = 0, z = 0, r = 0 },
		{ id = "VoidThrone", x = 0, z = -3.8, r = 0 },
		{ id = "AnglerLamp", x = -9.1, z = -1.9, r = 20 },
		{ id = "KrakenEyePedestal", x = 8.5, z = -1.9, r = 0 },
		{ id = "GlowCoralBed", x = 0, z = -19.9, r = 0 },
	},
	Trophies = {
		{ id = "MegalodonJawArch", x = 0, z = -9.5, r = 0 },
		{ id = "BronzeTentacle", x = -13.3, z = 8.5, r = 30 },
		{ id = "TreasurePile", x = 13.3, z = 8.5, r = -30 },
		{ id = "ReefGlobe", x = 0, z = 7.6, r = 0 },
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

-- Doorway styles (owner, 2026-10-18): your den's front door on the plaza, so it
-- stands out among twelve. Each is bought once (coral, at its den level, and the
-- Megalodon Jaws only after three world bosses) and can be worn or swapped back in
-- the den menu's Doorway rows. DenDoor builds each from parts; every one leaves the
-- doorway as open as the stone one (tools/preview/check_doors.luau tries them all).
local doors: { Door } = {
	{
		id = "Stone",
		name = "Stone Arch",
		price = 0,
		blurb = "Rounded sandstone over two brass lanterns",
		colors = { Color3.fromRGB(214, 186, 140), Color3.fromRGB(214, 160, 70), Color3.fromRGB(242, 162, 72) },
		glow = Color3.fromRGB(255, 186, 112),
	},
	{
		id = "KelpCurtain",
		name = "Kelp Curtain",
		price = 2000,
		blurb = "A driftwood frame hung with kelp, lit by green lanterns",
		colors = { Color3.fromRGB(132, 104, 76), Color3.fromRGB(64, 150, 74), Color3.fromRGB(170, 255, 140) },
		glow = Color3.fromRGB(170, 255, 140),
	},
	{
		id = "CoralArch",
		name = "Coral Arch",
		price = 5000,
		blurb = "An arch of living reef: brain, staghorn, fans and anemones",
		colors = {
			Color3.fromRGB(255, 118, 132),
			Color3.fromRGB(255, 160, 80),
			Color3.fromRGB(110, 214, 200),
		},
		glow = Color3.fromRGB(255, 170, 140),
	},
	{
		id = "BrassPorthole",
		name = "Brass Porthole",
		price = 12000,
		level = 2,
		blurb = "A ship's porthole the size of a door, riveted iron and brass",
		colors = { Color3.fromRGB(214, 160, 70), Color3.fromRGB(46, 52, 60), Color3.fromRGB(255, 200, 110) },
		glow = Color3.fromRGB(255, 200, 110),
	},
	{
		id = "Whalebone",
		name = "Whalebone Gate",
		price = 30000,
		level = 3,
		blurb = "Great curved ribs meeting over the door, a spine along the top",
		colors = { Color3.fromRGB(232, 226, 206), Color3.fromRGB(90, 78, 66), Color3.fromRGB(170, 240, 235) },
		glow = Color3.fromRGB(170, 240, 235),
	},
	{
		id = "CrystalGrotto",
		name = "Crystal Grotto",
		price = 60000,
		level = 4,
		blurb = "Glowing crystal growing out of the rock all round the door",
		colors = {
			Color3.fromRGB(110, 230, 255),
			Color3.fromRGB(176, 110, 236),
			Color3.fromRGB(140, 220, 255),
		},
		glow = Color3.fromRGB(140, 220, 255),
	},
	{
		id = "AbyssalGate",
		name = "Abyssal Gate",
		price = 150000,
		level = 5,
		blurb = "Black stone, violet runes and two angler lures on stalks",
		colors = { Color3.fromRGB(34, 32, 44), Color3.fromRGB(170, 90, 255), Color3.fromRGB(90, 240, 255) },
		glow = Color3.fromRGB(170, 90, 255),
	},
	{
		id = "MegalodonJaws",
		name = "Megalodon Jaws",
		price = 75000,
		achievement = "MonsterHunter",
		blurb = "Swim in through a Megalodon's open jaws",
		colors = { Color3.fromRGB(236, 232, 220), Color3.fromRGB(84, 92, 96), Color3.fromRGB(196, 255, 170) },
		glow = Color3.fromRGB(196, 255, 170),
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
	doors = doors,
	doorsById = index(doors),
	wings = wings,
	wingsById = index(wings),
	wingSlots = wingSlots,
	wingSlotsById = index(wingSlots),
	-- The wings open at `level` (the Sanctum); each slot's passage runs `passage`
	-- studs out from the side wall, `passageHalf` either side of the slot's middle,
	-- its walls `passageWall` high under a round arch to `passageCrown` (local y); a
	-- wing taken down gives back `refund` of its price
	wing = { level = 5, passage = 14, passageHalf = 8, passageWall = 13, passageCrown = 22, refund = 0.5 },
	-- Open Plan (the proposal, approved 2026-10-28): every storey's rooms take its
	-- widest room's width plus `widen`, with no pillars, so the storey reads as one
	-- great hall. Bought once with coral at `level` and then switched on or off in
	-- the den menu; wall and ceiling things go back to the tray when it changes.
	openPlan = { price = 75000, level = 3, widen = 8 },
	-- The Aquarium (the proposal's passive element, approved 2026-10-28): wall tanks
	-- each showing one rare fish from the Catch Log (a species at a rarity, as many
	-- tanks of it as you've caught), earning by its rarity every hour, online or off,
	-- up to `hours` of it (Shared/Aquarium, AquariumService). `base` + the den level
	-- tanks down the side walls (`spots`: side, local z, in order), and the Aquarium
	-- Hall's `hall` more. Feeding them (once a UTC day, `feed.dna` of `feed.biome`'s
	-- DNA a stocked tank) makes that day's earnings ×`feed.multiplier`. Swimming
	-- within `reach` of a stocked tank collects, like the Coral Garden.
	aquarium = {
		rates = {
			Silver = { coral = 15, shells = 0.5 },
			Golden = { coral = 45, shells = 1 },
			Glowing = { coral = 120, shells = 2 },
			Crystal = { coral = 300, shells = 4 },
			Prism = { coral = 700, shells = 8 },
		},
		hours = 12,
		base = 2,
		hall = 8,
		feed = { multiplier = 1.5, dna = 1, biome = "KelpShallows" },
		reach = 16,
		-- A tank: its glass front's width (along the wall), height and depth into the
		-- room, and its middle's height over the deck
		size = Vector3.new(11, 7, 4),
		height = 7,
		spots = {
			{ side = -1, z = 22 },
			{ side = 1, z = 22 },
			{ side = -1, z = -20 },
			{ side = 1, z = -20 },
			{ side = -1, z = -50 },
			{ side = 1, z = -50 },
			{ side = -1, z = -100 },
			{ side = 1, z = -100 },
		},
	},
	-- The Den Expansion pass: this many more things placed, at any level
	expansionCapacity = 25,
	-- The main room's back wall at plaque height (local z), before and after the
	-- Burrow carves it back (the trophy wall is seated on the real rock by raycast)
	backWall = { -36, -110 },
	-- The furthest the rooms reach back and forward (local z): the den's block of
	-- rock (DenCarve) and the safe zone (Layout.denAt)
	maxBack = -220,
	maxFront = 36,
	-- The Haul Pool, near the front of the Nook: you come in over it, so swimming
	-- home through your doorway banks your Haul (local z, and its radius)
	pool = { z = 14, radius = 9 },
	-- The shape the placements are saved in (`den.layout`): 3 the private interiors
	-- of 2026-10-16, 4 the bigger rooms and things of 2026-10-18. An older save is
	-- moved over once (DenService `relayout`): across and along by `growth`, the v4
	-- rooms' size over the v3 ones'.
	layout = { current = 4, growth = 1.22 },
	-- The way out: a bubble portal at the back of a round alcove in the main storey's
	-- front wall, the same shape as the doorways on the plaza (owner, 2026-10-20: "den
	-- exit needs to be more pronounced like the entrance too"; DenCarve cuts it, DenDoor
	-- dresses it in the den's doorway style): its middle's height over the deck, its
	-- radius, how far into the wall it stands and the alcove's radius (it was flat on
	-- the wall, 13 up, until then)
	exit = { y = 11, radius = 9, back = 9, alcove = 10.5 },
	-- How far the carved roof can hang under the arch DenSpace.vaultAt works out: the
	-- Terrain's voxel surface sits lower than the cylinder cut (rock 35.6 studs over
	-- the deck where the arch says 39; PC 2026-10-20). Anything placed near the vault
	-- keeps this much more clear, and checks against the arch should allow for it.
	vaultSag = 4,
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
