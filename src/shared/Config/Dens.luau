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
-- house dug down into the rock under the hub. The main room (the Nook, carved with
-- the cavern) runs back into the Burrow, and from the Hall on, shafts drop to two
-- big vaulted storeys below it: the Hall (and its Grotto wings), then the Sanctum,
-- the deepest. Every storey has a flat stone deck to build on, and things are
-- placed freely (Build mode) on decks, walls and ceilings, as many as the level
-- allows. Room numbers are in the den's frame: x across, y up from the main floor,
-- z toward the hub (negative = back into the rock); Shared/DenSpace turns them into
-- decks and placement rules, and the server carves them (DenCarve).
export type Level = {
	level: number,
	name: string,
	cost: number, -- coral to reach it (0 for the first)
	capacity: number, -- things that can be placed
	blurb: string,
}

-- A storey: its deck's top, the carved floor under the deck, the ceiling (local y)
export type Storey = { deck: number, floor: number, ceiling: number }

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
		capacity = 15,
		blurb = "A snug cave room: your pool, your garden and the trophy wall.",
	},
	{
		level = 2,
		name = "Burrow",
		cost = 1000,
		capacity = 30,
		blurb = "The room runs far back into the rock, with room for twice as much.",
	},
	{
		level = 3,
		name = "Hall",
		cost = 12000,
		capacity = 50,
		blurb = "A shaft drops to a great vaulted hall below, and the Coral Garden moves to its middle.",
	},
	{
		level = 4,
		name = "Grotto",
		cost = 45000,
		capacity = 75,
		blurb = "The hall opens into wide wings and a deep grotto at its back.",
	},
	{
		level = 5,
		name = "Sanctum",
		cost = 150000,
		capacity = 100,
		blurb = "A second shaft to the Sanctum, the deepest and grandest storey of all.",
	},
}

-- Main floor y 0 is world y 4 (Config/World hub.denFloorY); the Hall's deck is at
-- world -30 and the Sanctum's at -66 (the hub's rock runs solid to -80). The rock
-- floor under each deck is 5–6 studs down, on a 4-stud voxel line: Terrain draws
-- its surface up to ~4.6 studs above where it's filled, and with 1–2 studs of room
-- it came up through the flagstones (playtest 2026-10-13: none showed on the main
-- storey; sandy wedges between them below). The decks are thick slabs down to it.
-- 8 studs of rock stay between one storey's floor and the next one's ceiling.
local storeys: { Storey } = {
	{ deck = 1, floor = -4, ceiling = 24 },
	{ deck = -34, floor = -40, ceiling = -12 },
	{ deck = -70, floor = -76, ceiling = -48 },
}

-- Each room keeps 5 studs of rock from the line between it and the next den
-- (x <= (112 - z) * tan 15° - 5), and the main storey stays clear of the tunnels
local rooms: { Room } = {
	{ id = "Nook", level = 1, storey = 1, x = 12, z0 = 14, z1 = -16 },
	{ id = "Burrow", level = 2, storey = 1, x = 11, z0 = -12, z1 = -38 },
	{ id = "HallNave", level = 3, storey = 2, x = 18, z0 = 24, z1 = 0 },
	{ id = "HallMid", level = 3, storey = 2, x = 22, z0 = 0, z1 = -24 },
	{ id = "HallBack", level = 3, storey = 2, x = 26, z0 = -24, z1 = -48, pillars = 12 },
	{ id = "GrottoWings", level = 4, storey = 2, x = 29, z0 = -16, z1 = -48 },
	{ id = "GrottoDeep", level = 4, storey = 2, x = 33, z0 = -48, z1 = -74, pillars = 13 },
	{ id = "SanctumFore", level = 5, storey = 3, x = 16, z0 = 28, z1 = 0 },
	{ id = "SanctumNave", level = 5, storey = 3, x = 24, z0 = 0, z1 = -40, pillars = 10 },
	{ id = "SanctumApse", level = 5, storey = 3, x = 34, z0 = -40, z1 = -84, pillars = 11 },
}

local shafts: { Shaft } = {
	{ id = "HallShaft", level = 3, from = 1, to = 2, z = -29, radius = 7 },
	{ id = "SanctumShaft", level = 5, from = 2, to = 3, z = -62, radius = 8 },
}

local gardenSpots: { GardenSpot } = {
	{ level = 1, storey = 1, z = -13, shape = "trough", width = 16, depth = 4 },
	{ level = 2, storey = 1, z = -35, shape = "trough", width = 16, depth = 4 },
	{ level = 3, storey = 2, z = -12, shape = "bed", width = 15, depth = 11 },
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
		colors = { Color3.fromRGB(226, 228, 234), Color3.fromRGB(206, 210, 220) },
		blurb = "Polished pearl-white marble",
	},
	{
		id = "Mosaic",
		name = "Reef Mosaic",
		price = 6000,
		material = Enum.Material.Pebble,
		colors = { Color3.fromRGB(64, 156, 168), Color3.fromRGB(226, 128, 70) },
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
	glows = glows,
	glowsById = index(glows),
	floors = floors,
	floorsById = index(floors),
	-- The Den Expansion pass: this many more things placed, at any level
	expansionCapacity = 25,
	-- The main room's back wall at plaque height (local z), before and after the
	-- Burrow carves it back (the trophy wall is seated on the real rock by raycast)
	backWall = { -21, -42 },
	-- The deepest the den reaches back, and down: the safe zone (Layout.denAt) and
	-- the rock refilled when a den changes hands
	maxBack = -90,
	maxFront = 32,
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
