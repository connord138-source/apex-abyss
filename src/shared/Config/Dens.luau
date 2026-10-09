--!strict
-- Den bases (owner, 2026-10-07: "the dens being an upgradable base that gets bigger
-- and deeper as it upgrades. Other players can go in and check out your base but
-- can't take or do anything. You can display trophies from large fish killed/bosses
-- killed and set up furniture so that it's your den. Upgrades and furniture/colors
-- would cost currency. Coral lamps, etc"). A den has a level (each carves the room
-- further back into the seamount and, from Hall, a lower chamber under the floor),
-- furniture slots on the floor, the walls and down in the chamber, a glow color for
-- its lamps, and a trophy wall that fills itself from what the fish has done.
-- DenService owns the data; DenBuilder builds it in the world.
export type Level = {
	level: number,
	name: string,
	cost: number, -- coral to reach it (0 for the first)
	extend: number, -- studs the room runs further back
	pit: number, -- depth of the lower chamber under the floor (0 = none)
	pitRadius: number,
	slots: { string }, -- slots unlocked at this level
	blurb: string,
}

export type Slot = {
	id: string,
	kind: "floor" | "wall" | "pit",
	offset: Vector3, -- in the den's frame: x right, y up from the floor, z toward the hub (negative = back)
	facing: number, -- yaw (radians) the item turns to face the room
	pass: string?, -- opened by this game pass (Config/Monetization) instead of a level
}

export type Item = {
	id: string,
	name: string,
	price: number,
	kinds: { string }, -- slot kinds it fits
	size: Vector3,
	prop: string?, -- ReplicatedStorage.WorldProps.<prop> when imported
	color: Color3,
	glow: boolean?, -- lit in the den's glow color
	bubbles: boolean?,
	blurb: string,
}

local levels: { Level } = {
	{
		level = 1,
		name = "Nook",
		cost = 0,
		extend = 0,
		pit = 0,
		pitRadius = 0,
		slots = { "A1", "A2", "A3", "A4" },
		blurb = "A snug cave with four spots for your things.",
	},
	{
		level = 2,
		name = "Burrow",
		cost = 2500,
		extend = 6,
		pit = 0,
		pitRadius = 0,
		slots = { "W1", "W2" },
		blurb = "The room runs deeper, and the walls take lanterns and banners.",
	},
	{
		level = 3,
		name = "Hall",
		cost = 12000,
		extend = 12,
		pit = 10,
		pitRadius = 9,
		slots = { "P1", "P2", "P3" },
		blurb = "Deeper again, with a chamber sunk under the floor.",
	},
	{
		level = 4,
		name = "Grotto",
		cost = 45000,
		extend = 18,
		pit = 14,
		pitRadius = 12,
		slots = { "W3", "W4", "P4" },
		blurb = "The full grotto: the longest hall, the widest chamber, every spot.",
	},
}

local slots: { Slot } = {
	{ id = "A1", kind = "floor", offset = Vector3.new(-7, 0, -4), facing = math.rad(35) },
	{ id = "A2", kind = "floor", offset = Vector3.new(7, 0, -4), facing = math.rad(-35) },
	{ id = "A3", kind = "floor", offset = Vector3.new(-7, 0, 6), facing = math.rad(55) },
	{ id = "A4", kind = "floor", offset = Vector3.new(7, 0, 6), facing = math.rad(-55) },
	{ id = "W1", kind = "wall", offset = Vector3.new(-10.5, 9, 0), facing = math.rad(90) },
	{ id = "W2", kind = "wall", offset = Vector3.new(10.5, 9, 0), facing = math.rad(-90) },
	{ id = "W3", kind = "wall", offset = Vector3.new(-10, 9, -22), facing = math.rad(90) },
	{ id = "W4", kind = "wall", offset = Vector3.new(10, 9, -22), facing = math.rad(-90) },
	{ id = "P1", kind = "pit", offset = Vector3.new(-5, -9, 2), facing = math.rad(40) },
	{ id = "P2", kind = "pit", offset = Vector3.new(5, -9, 2), facing = math.rad(-40) },
	{ id = "P3", kind = "pit", offset = Vector3.new(0, -9, -5), facing = 0 },
	{ id = "P4", kind = "pit", offset = Vector3.new(0, -13, 6), facing = math.rad(180) },
	-- The Den Expansion pass's spots, open at any level: the back corners of the
	-- floor (clear of the pool and the Coral Garden) and on the side walls between
	-- the W spots and the doorway (at z 9 a Banner's edge sank into the doorway rock,
	-- retest 2026-10-09)
	{
		id = "X1",
		kind = "floor",
		offset = Vector3.new(-8, 0, -12),
		facing = math.rad(30),
		pass = "DenExpansion",
	},
	{
		id = "X2",
		kind = "floor",
		offset = Vector3.new(8, 0, -12),
		facing = math.rad(-30),
		pass = "DenExpansion",
	},
	{
		id = "X3",
		kind = "wall",
		offset = Vector3.new(-10.3, 8, 6),
		facing = math.rad(90),
		pass = "DenExpansion",
	},
	{
		id = "X4",
		kind = "wall",
		offset = Vector3.new(10.3, 8, 6),
		facing = math.rad(-90),
		pass = "DenExpansion",
	},
}

local items: { Item } = {
	{
		id = "CoralLamp",
		name = "Coral Lamp",
		price = 250,
		kinds = { "floor", "pit" },
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
		kinds = { "floor", "pit" },
		size = Vector3.new(6, 1.2, 4),
		prop = "KelpClump",
		color = Color3.fromRGB(78, 116, 52),
		blurb = "A soft heap of kelp to settle into",
	},
	{
		id = "ShellPile",
		name = "Shell Pile",
		price = 150,
		kinds = { "floor", "pit" },
		size = Vector3.new(4, 2, 4),
		prop = "Shell",
		color = Color3.fromRGB(242, 228, 204),
		blurb = "Shells you've gathered, heaped up",
	},
	{
		id = "AnemoneGarden",
		name = "Anemone Garden",
		price = 300,
		kinds = { "floor", "pit" },
		size = Vector3.new(5, 2.5, 5),
		prop = "Anemone",
		color = Color3.fromRGB(240, 110, 120),
		blurb = "Swaying anemones in a bed of sand",
	},
	{
		id = "BrainCoral",
		name = "Brain Coral",
		price = 220,
		kinds = { "floor", "pit" },
		size = Vector3.new(4.5, 3.5, 4.5),
		prop = "BrainCoral",
		color = Color3.fromRGB(250, 220, 110),
		blurb = "A fat yellow brain coral",
	},
	{
		id = "TubeSponges",
		name = "Tube Sponges",
		price = 200,
		kinds = { "floor", "pit" },
		size = Vector3.new(3, 5, 3),
		prop = "TubeSponge",
		color = Color3.fromRGB(170, 110, 220),
		blurb = "Tall purple sponges",
	},
	{
		id = "DriftwoodTable",
		name = "Driftwood Table",
		price = 350,
		kinds = { "floor", "pit" },
		size = Vector3.new(6, 3, 3.5),
		color = Color3.fromRGB(110, 86, 60),
		blurb = "A slab of driftwood on two stones",
	},
	{
		id = "PearlPedestal",
		name = "Pearl Pedestal",
		price = 900,
		kinds = { "floor", "pit" },
		size = Vector3.new(3, 5, 3),
		color = Color3.fromRGB(236, 236, 240),
		glow = true,
		blurb = "A great pearl on a stone column, lit from within",
	},
	{
		id = "DecorChest",
		name = "Treasure Chest",
		price = 600,
		kinds = { "floor", "pit" },
		size = Vector3.new(5, 4, 3.5),
		prop = "TreasureChest",
		color = Color3.fromRGB(78, 54, 36),
		blurb = "A chest like the ones your maps lead to",
	},
	{
		id = "BubbleColumn",
		name = "Bubble Column",
		price = 500,
		kinds = { "floor", "pit" },
		size = Vector3.new(2, 1, 2),
		color = Color3.fromRGB(200, 240, 255),
		bubbles = true,
		blurb = "A vent of bubbles rising to the ceiling",
	},
	{
		id = "CrystalShard",
		name = "Crystal Shard",
		price = 1200,
		kinds = { "floor", "wall", "pit" },
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

local function index<T>(list: { T }): { [string]: T }
	local map: { [string]: T } = {}
	for _, entry in list do
		map[(entry :: any).id] = entry
	end
	return map
end

return {
	levels = levels,
	slots = slots,
	slotsById = index(slots),
	items = items,
	itemsById = index(items),
	glows = glows,
	glowsById = index(glows),
	maxExtend = 18, -- the deepest any den runs back (the rock refilled when a den changes hands)
	maxPit = 14,
	maxPitRadius = 12,
	-- The hint to open the den menu shows within this of your own Haul Pool
	hintReach = 16,
	-- The Coral Garden (owner, 2026-10-09: "an afk aspect of the game to earn
	-- something to keep players coming back"): every den grows coral and a few
	-- shells over real time, online or off, up to `hours` of growth (the Deep Garden
	-- pass: Config/Monetization). Resting in your own den grows it `rest` times
	-- faster and collects it every `collectEvery` seconds; swimming in collects it
	-- too. A bigger den grows more (per hour, by den level).
	garden = {
		coral = { 60, 100, 160, 250 },
		shells = { 4, 6, 9, 12 },
		hours = 8,
		rest = 2,
		collectEvery = 60,
		-- The bed sits on the floor this far in front of the back wall (it moves
		-- back as the den grows), under the trophy plaques
		fromBack = 8,
	},
}
