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

-- Rooms stay 5 studs inside the line to the next den (15° either side of the axis)
local middle = Config.World.hub.radius + Config.World.hub.denDepth / 2
local tan15 = math.tan(math.rad(15))
for _, room in Dens.rooms do
	local nearest = middle - room.z0 -- the hub end is the narrowest
	local limit = nearest * tan15 - 5 / math.cos(math.rad(15))
	expect(room.x <= limit + 0.05, `{room.id}: half-width {room.x} > {string.format("%.1f", limit)} at r {nearest}`)
	expect(room.z0 % 2 == 0 and room.z1 % 2 == 0 and room.x % 1 == 0, `{room.id}: bounds on the 2-stud grid`)
end

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
					expect(DenSpace.onDeck(level, storey, x + 1, z + 1), `L{level} S{storey}: tile over a hole at {id}`)
					area += 4
				end
			end
		end
		expect(area == count * 4, `L{level} S{storey}: tiles cover {area} of {count * 4}`)
		table.insert(parts, `S{storey} {count * 4} sq ({#tiles} tiles)`)
	end
	print(`L{level} {Dens.levels[level].name}: {table.concat(parts, ", ")}; {#DenSpace.pillars(level)} pillars; garden {DenSpace.garden(level).shape} on S{DenSpace.garden(level).storey}`)
end

-- Holes
expect(not DenSpace.onDeck(1, 1, 0, DenSpace.POOL_Z), "the pool is cut out")
expect(DenSpace.onDeck(1, 1, 9, 6), "the Nook floor beside the pool is deck")
expect(not DenSpace.onDeck(3, 1, 0, -30), "the Hall shaft is cut out of the Burrow")
expect(DenSpace.onDeck(2, 1, 0, -28), "the Burrow floor is deck before the Hall")
expect(not DenSpace.onDeck(3, 2, 0, -12), "the garden bed is cut out of the Hall")
expect(not DenSpace.onDeck(4, 2, 0, -62) == false, "the Grotto floor over the Sanctum shaft is deck before L5")
expect(not DenSpace.onDeck(5, 2, 0, -62), "the Sanctum shaft is cut out of the Grotto")

-- Placement
local lamp = Dens.itemsById.CoralLamp
local lantern = Dens.itemsById.SeaGlassLantern
local jelly = Dens.itemsById.JellyLamp
local v = Vector3.new
local function ok(check: { ok: boolean, why: string? }): boolean
	return check.ok
end
expect(ok(DenSpace.check(1, lamp, "floor", v(8, 1, 6))), "a lamp on the Nook floor")
expect(not ok(DenSpace.check(1, lamp, "floor", v(0, 1, -30))), "no lamp in the Burrow before it's dug")
expect(not ok(DenSpace.check(1, lamp, "wall", v(12, 8, 0))), "a lamp isn't a wall thing")
expect(ok(DenSpace.check(1, lantern, "wall", v(12.5, 8, 0))), "a lantern on the Nook wall")
expect(not ok(DenSpace.check(1, lantern, "wall", v(40, 8, 0))), "no lantern outside the den")
expect(ok(DenSpace.check(3, lamp, "floor", v(10, -34, 10))), "a lamp on the Hall deck")
expect(not ok(DenSpace.check(2, lamp, "floor", v(10, -34, 10))), "no Hall before level 3")
expect(ok(DenSpace.check(5, jelly, "ceiling", v(0, -46, -60))), "a jelly lamp on the Sanctum's vault")
expect(not ok(DenSpace.check(5, jelly, "ceiling", v(0, -64, -60))), "a ceiling lamp needs height")
expect(ok(DenSpace.check(5, lamp, "floor", v(0, -64, -60))), "stacked on something on the Sanctum deck")

print(if failures == 0 then "dens: OK" else `dens: {failures} failed`)
if failures > 0 then
	error("dens test failed")
end
