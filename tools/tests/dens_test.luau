-- Checks Shared/DenSpace against Config/Dens (run_dens.sh): every room keeps its
-- rock margin from the next den, the decks' tiles cover their cells exactly once,
-- the pool, shafts and garden are cut out, and placement checks answer sensibly.
local Config = require("./Config")
local DenSpace = require("./DenSpace")

local Dens = Config.Dens
local failures = 0
local function expect(ok: boolean, what: string)
	if not ok then
		failures += 1
		print("FAIL: " .. what)
	end
end

-- Every den is its own block of rock (owner, 2026-10-16: private interiors): the
-- rooms stay well inside it, storeys keep 8 studs of rock between them, and each
-- shaft opens into a room on both of its storeys
local Layout = require("./Layout")
local extent = Layout.DEN_EXTENT
for _, room in Dens.rooms do
	local s = Dens.storeys[room.storey]
	expect(room.x + 12 <= extent.half, `{room.id}: half-width {room.x} too near the block's side`)
	expect(
		room.z0 + 12 <= extent.front and room.z1 - 12 >= extent.back,
		`{room.id}: too near the block's ends`
	)
	expect(
		s.ceiling + 12 <= extent.top and s.floor - 12 >= extent.bottom,
		`{room.id}: too near the block's top or bottom`
	)
	expect(room.z0 % 2 == 0 and room.z1 % 2 == 0 and room.x % 1 == 0, `{room.id}: bounds on the 2-stud grid`)
end
for n = 2, #Dens.storeys do
	local above, below = Dens.storeys[n - 1], Dens.storeys[n]
	expect(
		above.floor - below.ceiling >= 8,
		`storey {n}: only {above.floor - below.ceiling} studs under storey {n - 1}`
	)
	expect((4 + below.floor) % 4 == 0, `storey {n}: rock floor off the 4-stud voxel line`)
end
local function roomAt(level: number, storey: number, z: number, x: number): boolean
	for _, room in DenSpace.rooms(level, storey) do
		if math.abs(x) <= room.x and z <= room.z0 and z >= room.z1 then
			return true
		end
	end
	return false
end
for _, shaft in Dens.shafts do
	expect(roomAt(shaft.level, shaft.from, shaft.z - shaft.radius - 2, 0), `{shaft.id}: no room above`)
	expect(roomAt(shaft.level, shaft.from, shaft.z + shaft.radius + 2, 0), `{shaft.id}: no room above`)
	expect(roomAt(shaft.level, shaft.to, shaft.z - shaft.radius - 2, 0), `{shaft.id}: no room below`)
	expect(roomAt(shaft.level, shaft.to, shaft.z + shaft.radius + 2, 0), `{shaft.id}: no room below`)
end
expect(roomAt(1, 1, Dens.pool.z + Dens.pool.radius + 2, 0), "the pool sits in the Nook")
expect(Dens.maxFront == Dens.roomsById.Nook.z0, "the way out is on the Nook's front wall")

for level = 1, #Dens.levels do
	local parts = {}
	for storey = 1, DenSpace.storeys(level) do
		local cells = DenSpace.cells(level, storey)
		local count = 0
		for _ in cells do
			count += 1
		end
		local tiles = DenSpace.tiles(level, storey, 10)
		local covered: { [string]: boolean } = {}
		local area = 0
		for _, tile in tiles do
			expect(tile.x1 > tile.x0 and tile.z0 > tile.z1, "tile has size")
			expect(tile.x1 - tile.x0 <= 10 and tile.z0 - tile.z1 <= 10, "tile at most 10 across")
			for x = tile.x0, tile.x1 - 2, 2 do
				for z = tile.z1, tile.z0 - 2, 2 do
					local id = `{x},{z}`
					expect(not covered[id], `L{level} S{storey}: cell {id} tiled twice`)
					covered[id] = true
					expect(
						DenSpace.onDeck(level, storey, x + 1, z + 1),
						`L{level} S{storey}: tile over a hole at {id}`
					)
					area += 4
				end
			end
		end
		expect(area == count * 4, `L{level} S{storey}: tiles cover {area} of {count * 4}`)
		table.insert(parts, `S{storey} {count * 4} sq ({#tiles} tiles)`)
	end
	print(
		`L{level} {Dens.levels[level].name}: {table.concat(parts, ", ")}; {#DenSpace.pillars(level)} pillars; garden {DenSpace.garden(
			level
		).shape} on S{DenSpace.garden(level).storey}`
	)
end

-- Holes
expect(not DenSpace.onDeck(1, 1, 0, DenSpace.POOL_Z), "the pool is cut out")
expect(DenSpace.onDeck(1, 1, 9, 6), "the Nook floor beside the pool is deck")
local hallShaft, sanctumShaft = Dens.shafts[1].z, Dens.shafts[2].z
expect(not DenSpace.onDeck(3, 1, 0, hallShaft), "the Hall shaft is cut out of the Burrow")
expect(DenSpace.onDeck(2, 1, 0, hallShaft), "the Burrow floor is deck before the Hall")
expect(not DenSpace.onDeck(3, 2, 0, 4), "the garden bed is cut out of the Hall")
expect(
	not DenSpace.onDeck(4, 2, 0, sanctumShaft) == false,
	"the Grotto floor over the Sanctum shaft is deck before L5"
)
expect(not DenSpace.onDeck(5, 2, 0, sanctumShaft), "the Sanctum shaft is cut out of the Grotto")

-- Placement
local lamp = Dens.itemsById.CoralLamp
local lantern = Dens.itemsById.SeaGlassLantern
local jelly = Dens.itemsById.JellyLamp
local v = Vector3.new
local function ok(check: { ok: boolean, why: string? }): boolean
	return check.ok
end
expect(ok(DenSpace.check(1, lamp, "floor", v(16, 1, -6))), "a lamp on the Nook floor")
expect(not ok(DenSpace.check(1, lamp, "floor", v(0, 1, -50))), "no lamp in the Burrow before it's dug")
expect(not ok(DenSpace.check(1, lamp, "wall", v(30, 8, 0))), "a lamp isn't a wall thing")
local nookX = Dens.roomsById.Nook.x
expect(ok(DenSpace.check(1, lantern, "wall", v(nookX + 0.5, 8, 0))), "a lantern on the Nook wall")
expect(not ok(DenSpace.check(1, lantern, "wall", v(nookX + 8, 8, 0))), "no lantern outside the den")
expect(not ok(DenSpace.check(1, lantern, "wall", v(nookX + 0.5, 1.5, 0))), "a lantern clear of the deck")
expect(ok(DenSpace.check(3, lamp, "floor", v(24, -54, 10))), "a lamp on the Hall deck")
expect(not ok(DenSpace.check(2, lamp, "floor", v(24, -54, 10))), "no Hall before level 3")
expect(ok(DenSpace.check(5, jelly, "ceiling", v(0, -70, -60))), "a jelly lamp on the Sanctum's vault")
expect(not ok(DenSpace.check(5, jelly, "ceiling", v(0, -112, -60))), "a ceiling lamp needs height")
expect(ok(DenSpace.check(5, lamp, "floor", v(0, -112, -60))), "stacked on something on the Sanctum deck")

expect(not ok(DenSpace.check(1, lamp, "floor", v(0, 1, DenSpace.POOL_Z))), "nothing stands on the pool")
expect(
	ok(DenSpace.check(1, lamp, "floor", v(DenSpace.POOL_RADIUS + 0.2, 3.3, DenSpace.POOL_Z))),
	"a lamp on a table at the pool's edge"
)
expect(
	not ok(DenSpace.check(1, lamp, "floor", v(0, 3.3, DenSpace.POOL_Z))),
	"nothing floats over the pool's middle"
)

-- Resting: off the deck only on top of a placed floor thing, inside its footprint
local tableItem = Dens.itemsById.DriftwoodTable
local placed = { { uid = 1, id = "DriftwoodTable", x = 4, y = 1, z = 6, r = 90, s = "floor" } }
local top = 1 + tableItem.size.Y
expect(ok(DenSpace.resting(1, placed, v(4, 1, 6))), "on the deck")
expect(ok(DenSpace.resting(1, placed, v(4, top, 6))), "on the table's top")
-- turned 90°, the table's 6-stud length runs along z
expect(ok(DenSpace.resting(1, placed, v(4, top, 6 + tableItem.size.X / 2 - 1))), "along the turned table")
expect(
	not ok(DenSpace.resting(1, placed, v(4 + tableItem.size.Z / 2 + 1, top, 6))),
	"past the turned table's width"
)
expect(not ok(DenSpace.resting(1, placed, v(4, top + 2, 6))), "floating over it")
expect(not ok(DenSpace.resting(1, placed, v(4, top, 6), 1)), "not on the thing being moved")

-- Settling: a stack whose base goes away comes down onto the deck, in order
local deck1 = DenSpace.storey(1).deck
local SX, SZ = 14, -14
expect(ok(DenSpace.check(1, tableItem, "floor", v(SX, deck1, SZ))), "the settling spot is open deck")
local stack = {
	{ uid = 2, id = "DriftwoodTable", x = SX, y = deck1 + tableItem.size.Y, z = SZ, r = 90, s = "floor" },
	{ uid = 3, id = "CoralLamp", x = SX, y = deck1 + 2 * tableItem.size.Y, z = SZ, r = 0, s = "floor" },
}
expect(#DenSpace.settle(1, stack) == 0, "a stack settles with nothing sent back")
expect(math.abs(stack[1].y - deck1) < 1e-6, "the upper table falls to the deck")
expect(math.abs(stack[2].y - (deck1 + tableItem.size.Y)) < 1e-6, "the lamp follows it onto its top")
local still = {
	{ uid = 1, id = "DriftwoodTable", x = SX, y = deck1, z = SZ, r = 90, s = "floor" },
	{ uid = 3, id = "CoralLamp", x = SX, y = deck1 + tableItem.size.Y, z = SZ, r = 0, s = "floor" },
}
expect(#DenSpace.settle(1, still) == 0 and still[2].y == deck1 + tableItem.size.Y, "a supported thing stays")
local overPool = {
	{ uid = 4, id = "CoralLamp", x = 0, y = deck1 + 3, z = DenSpace.POOL_Z, r = 0, s = "floor" },
}
-- Carrying a stack: what stands on a base moves and turns with it
do
	local base = { uid = 10, id = "DriftwoodTable", x = SX, y = deck1, z = SZ, r = 0, s = "floor" }
	local onTop =
		{ uid = 11, id = "CoralLamp", x = SX + 1, y = deck1 + tableItem.size.Y, z = SZ, r = 30, s = "floor" }
	local loose = { uid = 12, id = "CoralLamp", x = SX + 8, y = deck1, z = SZ, r = 0, s = "floor" }
	local all = { base, onTop, loose }
	local stack = DenSpace.stackOn(all, 10)
	expect(#stack == 1 and stack[1].uid == 11, "the lamp on the table is its stack, the loose one isn't")
	local x, y, z, r = DenSpace.carry(onTop, base, { x = SX - 4, y = deck1, z = SZ + 2, r = 0 })
	expect(
		math.abs(x - (SX - 3)) < 1e-6 and math.abs(z - (SZ + 2)) < 1e-6 and y == onTop.y and r == 30,
		"carried straight across, it keeps its spot on the table"
	)
	local tx, _, tz, tr = DenSpace.carry(onTop, base, { x = SX, y = deck1, z = SZ, r = 180 })
	expect(
		math.abs(tx - (SX - 1)) < 1e-6 and math.abs(tz - SZ) < 1e-6 and tr == 210,
		"turned 180°, it swings round"
	)
	local fx, _, fz = DenSpace.carry(onTop, base, { x = SX, y = deck1, z = SZ, r = 90 })
	local _, _, _, back = DenSpace.carry(
		{ uid = 11, id = "CoralLamp", x = fx, y = onTop.y, z = fz, r = 120, s = "floor" },
		{ x = SX, y = deck1, z = SZ, r = 90 },
		base
	)
	expect(back == 30, "turning back undoes the turn")
	local stillOn = { uid = 11, id = "CoralLamp", x = fx, y = onTop.y, z = fz, r = 120, s = "floor" }
	local turnedBase = { uid = 10, id = "DriftwoodTable", x = SX, y = deck1, z = SZ, r = 90, s = "floor" }
	expect(
		ok(DenSpace.resting(1, { turnedBase }, v(stillOn.x, stillOn.y, stillOn.z))),
		"a carried thing still rests on the turned base"
	)
end
local back = DenSpace.settle(1, overPool)
expect(#back == 1 and back[1] == 4, "one with nowhere to land goes back to the tray")

-- Starter layouts: every set's layout fits an empty main room (level 2) and the
-- Hall (level 3), and every piece in it is a floor piece of that set
for setId, pieces in Dens.layouts do
	for _, piece in pieces do
		local item = Dens.itemsById[piece.id]
		expect(
			item ~= nil and item.set == setId and table.find(item.kinds, "floor") ~= nil,
			`{setId}: {piece.id} is a floor piece of the set`
		)
	end
	local nook = DenSpace.fitLayout(2, {}, pieces, v(0, 1, 2), 0)
	expect(nook ~= nil and #nook == #pieces, `{setId}: fits the Nook and Burrow`)
	local hall = DenSpace.fitLayout(3, {}, pieces, v(0, -34, -20), 0)
	expect(hall ~= nil and #hall == #pieces, `{setId}: fits the Hall`)
end
-- A second layout keeps clear of the first
do
	local first = DenSpace.fitLayout(3, {}, Dens.layouts.VentForge, v(0, -34, -20), 0)
	assert(first)
	local placedNow = {}
	for i, p in first do
		table.insert(placedNow, { uid = i, id = p.id, x = p.x, y = p.y, z = p.z, r = p.r, s = "floor" })
	end
	local second = DenSpace.fitLayout(3, placedNow, Dens.layouts.Shipwreck, v(0, -34, -20), 0)
	expect(second ~= nil, "a second set finds its own room")
	if second then
		for _, a in second do
			for _, b in first do
				local ia, ib = Dens.itemsById[a.id], Dens.itemsById[b.id]
				local gap = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
				expect(
					gap >= 0.4 * (math.max(ia.size.X, ia.size.Z) + math.max(ib.size.X, ib.size.Z)) - 1e-6,
					`{a.id} clear of {b.id}`
				)
			end
		end
	end
end

-- An old save moved into the v4 dens (DenSpace.grow): out with its walls, a lamp
-- that stood on a table onto the table's new top, a rug now over the wall's edge
-- nudged back onto the deck
do
	local growth = Dens.layout.growth
	local deck = DenSpace.storey(1).deck
	local old = {
		{ uid = 1, id = "DriftwoodTable", x = 4, y = deck, z = -6, r = 0, s = "floor" },
		{ uid = 2, id = "CoralLamp", x = 4.5, y = deck + 3, z = -6, r = 0, s = "floor" },
		{ uid = 3, id = "KelpRug", x = 25, y = deck, z = -14, r = 0, s = "floor" },
		{ uid = 4, id = "SeaGlassLantern", x = 30.5, y = 8, z = 0, r = 90, s = "wall" },
	}
	DenSpace.grow(1, old, growth)
	local tableTop = deck + Dens.itemsById.DriftwoodTable.size.Y
	expect(
		math.abs(old[1].x - 4 * growth) < 0.02 and math.abs(old[1].z + 6 * growth) < 0.02,
		"grow: out with the walls"
	)
	expect(
		math.abs(old[2].y - tableTop) < 0.02,
		`grow: the lamp onto the table's new top ({old[2].y} vs {tableTop})`
	)
	expect(
		ok(DenSpace.resting(1, old, v(old[2].x, old[2].y, old[2].z), 2)),
		"grow: the lamp rests on the table"
	)
	local rug = Dens.itemsById.KelpRug
	expect(
		DenSpace.footprintOnDeck(1, 1, rug, old[3].x, old[3].z, 0, 0.4),
		`grow: the rug back on the deck (x {old[3].x})`
	)
	expect(old[3].x < 25 * growth, "grow: the rug moved in, not out")
	expect(
		old[4].y == 8
			and ok(DenSpace.check(1, Dens.itemsById.SeaGlassLantern, "wall", v(old[4].x, old[4].y, old[4].z))),
		"grow: the lantern still on its wall"
	)
end

-- Den things: a cluster's kinds are pieces DenItems builds; rugs are big, a wall
-- lantern small
local KINDS = {
	Anemone = true,
	Brain = true,
	Sponge = true,
	Sponges = true,
	Staghorn = true,
	Fan = true,
	Shell = true,
	Kelp = true,
	Blade = true,
	Crystal = true,
	Rock = true,
	Star = true,
}
for _, item in Dens.items do
	local cluster = item.cluster
	if cluster then
		expect(cluster.count >= 3 or item.id == "CoralLamp", `{item.id}: a cluster of several pieces`)
		for _, kind in cluster.kinds do
			expect(KINDS[kind] == true, `{item.id}: piece kind {kind}`)
		end
	end
	if item.flat then
		expect(math.min(item.size.X, item.size.Z) >= 14, `{item.id}: a rug at least 14 studs across`)
	end
end
expect(
	Dens.itemsById.SeaGlassLantern.size.Y < Dens.itemsById.DriftwoodTable.size.Y,
	"a wall lantern smaller than a table"
)

-- The den props of batch 2 (2026-10-19) at their real sizes: a bed and a sofa fit the
-- Nook either way round, the bookshelf stands backed onto the Nook's side wall, the
-- wall things hang at a fish's height and stay small, the jellies hang from its vault
do
	local deck = DenSpace.storey(1).deck
	local nookX = Dens.roomsById.Nook.x
	for _, id in { "KelpBed", "SpongeSofa", "DriftwoodTable", "ConchGramophone" } do
		local item = Dens.itemsById[id]
		for _, r in { 0, 90 } do
			expect(
				ok(DenSpace.check(1, item, "floor", v(-12, deck, -10)))
					and DenSpace.footprintOnDeck(1, 1, item, -12, -10, r, 0.42),
				`{id} in the Nook (turned {r})`
			)
		end
	end
	local shelf = Dens.itemsById.ShipwreckBookshelf
	-- (the deck's 2-stud tiles stop a stud short of the wall)
	local backed = nookX - 1 - shelf.size.Z / 2
	expect(
		ok(DenSpace.check(1, shelf, "floor", v(backed, deck, -6)))
			and DenSpace.footprintOnDeck(1, 1, shelf, backed, -6, 90, 0.42),
		"the bookshelf backed onto the Nook's side wall"
	)
	for _, id in { "SeaGlassLantern", "Banner", "TreasureChart" } do
		local item = Dens.itemsById[id]
		expect(ok(DenSpace.check(1, item, "wall", v(nookX + 0.5, 10, -6))), `{id} on the Nook wall`)
		expect(
			item.size.Y <= 13 and math.min(item.size.X, item.size.Z) <= 1.6,
			`{id}: a wall thing stays slim`
		)
	end
	expect(Dens.itemsById.SeaGlassLantern.size.Y <= 6, "the sea glass lantern stays a small lantern")
	expect(
		ok(DenSpace.check(1, Dens.itemsById.JellyLamp, "ceiling", v(0, 30, -10))),
		"the jellyfish lamp under the Nook's vault"
	)
	for _, id in { "SpongeSofa", "ShipwreckBookshelf", "ConchGramophone", "TreasureChart" } do
		local item = Dens.itemsById[id]
		expect(
			item ~= nil and item.set == nil and item.price > 0,
			`{id}: bought in the den shop from the start`
		)
	end
end

-- Doorway styles: Stone is free, each one's level and achievement exist
expect(Dens.doorsById.Stone ~= nil and Dens.doorsById.Stone.price == 0, "the Stone Arch is free")
for _, door in Dens.doors do
	expect(#door.colors == 3, `{door.id}: three swatches`)
	expect(door.level == nil or Dens.levels[door.level] ~= nil, `{door.id}: its level exists`)
	expect(
		door.achievement == nil or Config.Achievements.byId[door.achievement] ~= nil,
		`{door.id}: its achievement exists`
	)
end

-- Wings (2026-10-28): every wing in every slot, with Open Plan and without, fits the
-- block with rock to spare, joins the house through its passage, keeps 8 studs of
-- rock from a wing in the other slot on its side, and adds its room for things;
-- the Observatory's sea never reaches another wing; tanks stay clear of the
-- passages' mouths
local wingTune = Dens.wing
for _, open in { false, true } do
	for _, def in Dens.wings do
		for _, slot in Dens.wingSlots do
			local shape = { level = wingTune.level, wings = { [slot.id] = def.id }, open = open }
			local plans = DenSpace.wingPlans(shape)
			expect(#plans == 1, `{def.id} in {slot.id}: one plan`)
			local plan = plans[1]
			if plan == nil then
				continue
			end
			local room = plan.room
			local tag = `{def.id} in {slot.id}{if open then " (open)" else ""}`
			expect(math.abs(room.cx :: number) + room.x + 12 <= extent.half, `{tag}: too near the block's side`)
			expect(room.z0 + 12 <= extent.front and room.z1 - 12 >= extent.back, `{tag}: too near the block's ends`)
			expect((room.ceiling :: number) + 12 <= extent.top, `{tag}: too near the block's top`)
			local s1 = Dens.storeys[1]
			expect(s1.floor - Dens.storeys[2].ceiling >= 8, `{tag}: rock under it`)
			-- The way through: house, passage, wing
			for _, x in { plan.wall - 2, plan.wall + 2, plan.x1 - 2, plan.x1 + 2, plan.x2 - 9 } do
				expect(DenSpace.onDeck(shape, 1, plan.side * x, slot.z + 6.5), `{tag}: deck at x {plan.side * x}`)
			end
			expect(
				DenSpace.capacity(shape, false) == Dens.levels[wingTune.level].capacity + def.capacity,
				`{tag}: holds {def.capacity} more`
			)
			-- A lamp on its floor is fine; the same spot with no wing isn't
			local lamp = Dens.itemsById.CoralLamp or Dens.items[1]
			local spot = Vector3.new(plan.side * (plan.x1 + 4), s1.deck, room.z0 - 4)
			expect(DenSpace.check(shape, lamp, "floor", spot).ok, `{tag}: a thing goes on its floor`)
			-- The passage and its mouth stay clear (PC 2026-11-02, DE7)
			for _, x in { plan.wall - 2, (plan.wall + plan.x1) / 2, plan.x1 + 1 } do
				local mouth = Vector3.new(plan.side * x, s1.deck, slot.z + 2)
				expect(not DenSpace.check(shape, lamp, "floor", mouth).ok, `{tag}: a thing in the passage at {x}`)
			end
			expect(
				not DenSpace.check({ level = wingTune.level, open = open }, lamp, "floor", spot).ok,
				`{tag}: nothing goes there with no wing`
			)
			for _, tank in DenSpace.tanks(shape) do
				if string.sub(tank.id, 1, 4) == "base" then
					expect(
						math.abs(tank.z - slot.z) >= wingTune.passageHalf + Dens.aquarium.size.X / 2 + 1
							or tank.x * plan.side < 0,
						`{tag}: tank {tank.id} in the passage's mouth`
					)
				end
			end
		end
	end
	-- Every slot full of the biggest wing, and of the Observatory: the two wings on a
	-- side keep 8 studs of rock between them, and the sea clears every other wing
	for _, fill in { "GreatHall", "Observatory", "AquariumHall" } do
		local wings: { [string]: string } = {}
		for _, slot in Dens.wingSlots do
			wings[slot.id] = fill
		end
		wings.FrontLeft = "Observatory"
		local shape = { level = wingTune.level, wings = wings, open = open }
		local plans = DenSpace.wingPlans(shape)
		expect(#plans == #Dens.wingSlots, `{fill}: a plan for every slot`)
		for _, a in plans do
			for _, b in plans do
				if a ~= b and a.side == b.side then
					local gap = math.max(a.room.z1 - b.room.z0, b.room.z1 - a.room.z0)
					expect(gap >= 8, `{fill}: {a.slot.id} and {b.slot.id} only {gap} studs apart`)
				end
				if a ~= b and a.def.id == "Observatory" and a.side == b.side then
					local half = a.def.depth / 2 + 12
					local seaFront, seaBack = a.z + half, a.z - half
					local reaches = b.x2 > a.x2 + 8
					local overlaps = b.room.z0 > seaBack - 4 and b.room.z1 < seaFront + 4
					expect(not (reaches and overlaps), `{fill}: the Observatory's sea reaches {b.slot.id}`)
				end
			end
		end
		expect(#DenSpace.tanks(shape) >= Dens.aquarium.base + wingTune.level, `{fill}: the base tanks`)
	end
	-- Open Plan widens the house and takes its pillars away
	if open then
		local shape = { level = 5, open = true }
		for _, room in DenSpace.rooms(shape) do
			expect(room.pillars == nil, `{room.id}: no pillars with Open Plan`)
		end
		expect(
			DenSpace.sideWall(shape, 0) == Dens.roomsById.Nook.x + Dens.openPlan.widen,
			"Open Plan widens the Nook"
		)
	end
end
do
	local hall = { level = 5, wings = { FrontLeft = "AquariumHall" } }
	expect(#DenSpace.tanks(hall) == Dens.aquarium.base + 5 + Dens.aquarium.hall, "the Aquarium Hall's tanks")
	-- Two halls (a stale save; the menu builds one of each): every tank its own id
	local twoHalls = {
		level = wingTune.level,
		wings = { FrontLeft = "AquariumHall", BackRight = "AquariumHall" },
	}
	local ids: { [string]: boolean } = {}
	for _, tank in DenSpace.tanks(twoHalls) do
		expect(not ids[tank.id], `tank id {tank.id} used twice`)
		ids[tank.id] = true
	end
	local pools = DenSpace.pools({ level = 5, wings = { BackRight = "GrottoPool" } })
	expect(#pools == 2, "the Grotto Pool banks too")
	local gallery = DenSpace.fixtures({ level = 5, wings = { FrontRight = "TrophyGallery" } })
	expect(#gallery == 8, `the gallery's plinths ({#gallery})`)
	for _, fixture in gallery do
		expect(
			not DenSpace.onDeck({ level = 5, wings = { FrontRight = "TrophyGallery" } }, 1, fixture.x, fixture.z),
			"a plinth's spot is cut out of the deck"
		)
	end
end
print(`wings: {#Dens.wings} wings, {#Dens.wingSlots} slots, block half-width {extent.half}, top {extent.top}`)

-- Furniture sets: each has pieces and an achievement that opens it; each piece's set
-- exists; ids are unique
local seen: { [string]: boolean } = {}
for _, item in Dens.items do
	expect(not seen[item.id], `{item.id}: one item per id`)
	seen[item.id] = true
	if item.set then
		expect(Dens.setsById[item.set] ~= nil, `{item.id}: its set {item.set} exists`)
		expect(item.price > 0, `{item.id}: has a price`)
	end
end
for _, set in Dens.sets do
	local pieces = 0
	for _, item in Dens.items do
		if item.set == set.id then
			pieces += 1
		end
	end
	expect(pieces >= 6, `{set.id}: {pieces} pieces`)
	local achievement = Config.Achievements.bySet[set.id]
	expect(achievement ~= nil and achievement.goal > 0, `{set.id}: an achievement opens it`)
	expect(Config.Tiers.byId[set.tier] ~= nil, `{set.id}: tier {set.tier} exists`)
end
print(`sets: {#Dens.sets} sets, {#Config.Achievements.list} achievements`)

print(if failures == 0 then "dens: OK" else `dens: {failures} failed`)
if failures > 0 then
	error("dens test failed")
end
