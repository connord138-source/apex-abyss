--!strict
-- A den's space (Config/Dens rooms, storeys, shafts, garden spots) as both sides
-- need it: where its decks are (a 2-stud grid of cells, merged into tiles for the
-- server to build), what's cut out of them (the Haul Pool, the shafts down, the Coral
-- Garden, the pillars), and whether a thing may stand somewhere (Build mode checks it
-- as you aim; the server checks it again). Positions are in the den's own frame: x
-- across, y up from the main floor, z toward the front wall (negative = back).
local Config = require(script.Parent.Config)
local DensConfig = require(script.Parent.Config.Dens)
local Layout = require(script.Parent.Layout)

local Dens = Config.Dens

local DenSpace = {}

DenSpace.CELL = 2
local CELL = DenSpace.CELL

export type Tile = { x0: number, x1: number, z0: number, z1: number }
export type Pillar = { x: number, z: number, room: string }
type Hole = { round: boolean, x: number, z: number, rx: number, rz: number }

-- The Haul Pool, in the den's frame (Layout.poolPosition)
DenSpace.POOL_Z = Dens.pool.z
DenSpace.POOL_RADIUS = Dens.pool.radius

-- The den's frame at floor level (its interior, Layout.denOrigin), facing its front
-- wall
function DenSpace.frame(index: number): CFrame
	return Layout.denOrigin(index)
end

-- A spot in the den: the frame looks at the front wall and a CFrame's own +z points
-- behind it, so z is flipped (playtest 2026-10-07: the trophy wall stood out in the
-- plaza)
function DenSpace.spot(frame: CFrame, x: number, y: number, z: number): CFrame
	return frame * CFrame.new(x, y, -z)
end

-- A world position in the den's frame
function DenSpace.toLocal(frame: CFrame, world: Vector3): Vector3
	local p = frame:PointToObjectSpace(world)
	return Vector3.new(p.X, p.Y, -p.Z)
end

function DenSpace.storey(n: number): DensConfig.Storey
	return Dens.storeys[n] or Dens.storeys[1]
end

-- The rooms open at a level (on one storey, or all)
function DenSpace.rooms(level: number, storey: number?): { DensConfig.Room }
	local list: { DensConfig.Room } = {}
	for _, room in Dens.rooms do
		if room.level <= level and (storey == nil or room.storey == storey) then
			table.insert(list, room)
		end
	end
	return list
end

function DenSpace.shafts(level: number): { DensConfig.Shaft }
	local list: { DensConfig.Shaft } = {}
	for _, shaft in Dens.shafts do
		if shaft.level <= level then
			table.insert(list, shaft)
		end
	end
	return list
end

-- The deepest storey open at a level
function DenSpace.storeys(level: number): number
	local deepest = 1
	for _, room in DenSpace.rooms(level) do
		deepest = math.max(deepest, room.storey)
	end
	return deepest
end

-- Where the Coral Garden stands at a level
function DenSpace.garden(level: number): DensConfig.GardenSpot
	local best = Dens.gardenSpots[1]
	for _, spot in Dens.gardenSpots do
		if spot.level <= level and spot.level >= best.level then
			best = spot
		end
	end
	return best
end

function DenSpace.capacity(level: number, expansion: boolean): number
	local def = Dens.levels[level] or Dens.levels[1]
	return def.capacity + (if expansion then Dens.expansionCapacity else 0)
end

-- The stone columns down the sides of the big rooms (where the vault comes down)
function DenSpace.pillars(level: number): { Pillar }
	local list: { Pillar } = {}
	for _, room in DenSpace.rooms(level) do
		local spacing = room.pillars
		if spacing then
			local count = math.floor((room.z0 - room.z1) / spacing)
			local first = room.z0 - ((room.z0 - room.z1) - (count - 1) * spacing) / 2
			for i = 0, count - 1 do
				for _, side in { -1, 1 } do
					table.insert(list, { x = side * (room.x - 4), z = first - i * spacing, room = room.id })
				end
			end
		end
	end
	return list
end

-- The arch over a room (DenCarve): upright walls `wall` high, then a shallow
-- barrel whose chord is the room's width and whose crown is the storey's ceiling.
-- Its radius, from the room's half-width and the arch's rise.
function DenSpace.archRadius(room: DensConfig.Room): number
	local s = DenSpace.storey(room.storey)
	local rise = s.ceiling - s.deck - s.wall
	return (room.x * room.x + rise * rise) / (2 * rise)
end

-- The ceiling's height over a storey's deck at `x` across a room
function DenSpace.vaultAt(room: DensConfig.Room, x: number): number
	local s = DenSpace.storey(room.storey)
	local rise = s.ceiling - s.deck - s.wall
	local radius = DenSpace.archRadius(room)
	local arc = math.sqrt(math.max(radius * radius - x * x, 0)) - (radius - rise)
	return s.wall + math.max(arc, 0)
end

local function holes(level: number, storey: number): { Hole }
	local list: { Hole } = {}
	if storey == 1 then
		local r = DenSpace.POOL_RADIUS + 0.8
		table.insert(list, { round = true, x = 0, z = DenSpace.POOL_Z, rx = r, rz = r })
	end
	for _, shaft in DenSpace.shafts(level) do
		if shaft.from == storey then
			local r = shaft.radius + 1.2
			table.insert(list, { round = true, x = 0, z = shaft.z, rx = r, rz = r })
		end
	end
	local garden = DenSpace.garden(level)
	if garden.storey == storey then
		table.insert(list, {
			round = garden.shape == "bed",
			x = 0,
			z = garden.z,
			rx = garden.width / 2 + 0.6,
			rz = garden.depth / 2 + 0.6,
		})
	end
	for _, pillar in DenSpace.pillars(level) do
		local room = Dens.roomsById[pillar.room]
		if room and room.storey == storey then
			table.insert(list, { round = true, x = pillar.x, z = pillar.z, rx = 2.2, rz = 2.2 })
		end
	end
	return list
end

-- Whether a cell (its corner at x, z; CELL across) overlaps a hole
local function cut(hole: Hole, x: number, z: number): boolean
	if hole.round then
		-- The nearest point of the cell to the ellipse's middle, inside it
		local nx = math.clamp(hole.x, x, x + CELL)
		local nz = math.clamp(hole.z, z, z + CELL)
		local dx, dz = (nx - hole.x) / hole.rx, (nz - hole.z) / hole.rz
		return dx * dx + dz * dz < 1
	end
	return x < hole.x + hole.rx
		and x + CELL > hole.x - hole.rx
		and z < hole.z + hole.rz
		and z + CELL > hole.z - hole.rz
end

local function key(i: number, k: number): number
	return (i + 512) * 1024 + (k + 512)
end

-- The deck's cells on a storey: key(i, k) for the cell from (i·CELL, k·CELL)
local cellCache: { [string]: { [number]: boolean } } = {}
function DenSpace.cells(level: number, storey: number): { [number]: boolean }
	local cacheKey = `{level}:{storey}`
	local cached = cellCache[cacheKey]
	if cached then
		return cached
	end
	local cells: { [number]: boolean } = {}
	local cuts = holes(level, storey)
	for _, room in DenSpace.rooms(level, storey) do
		for i = math.ceil(-room.x / CELL), math.floor(room.x / CELL) - 1 do
			for k = math.ceil(room.z1 / CELL), math.floor(room.z0 / CELL) - 1 do
				local x, z = i * CELL, k * CELL
				local open = true
				for _, hole in cuts do
					if cut(hole, x, z) then
						open = false
						break
					end
				end
				if open then
					cells[key(i, k)] = true
				end
			end
		end
	end
	cellCache[cacheKey] = cells
	return cells
end

-- Whether (x, z) is on a storey's deck
function DenSpace.onDeck(level: number, storey: number, x: number, z: number): boolean
	return DenSpace.cells(level, storey)[key(math.floor(x / CELL), math.floor(z / CELL))] == true
end

-- Whether there's deck within a cell (2 studs) of (x, z)
function DenSpace.nearDeck(level: number, storey: number, x: number, z: number): boolean
	for dx = -CELL, CELL, CELL do
		for dz = -CELL, CELL, CELL do
			if DenSpace.onDeck(level, storey, x + dx, z + dz) then
				return true
			end
		end
	end
	return false
end

-- The deck as tiles: the cells merged greedily into rectangles at most `most` studs
-- on a side (flagstones of mixed sizes), in a fixed order
function DenSpace.tiles(level: number, storey: number, most: number): { Tile }
	local cells = DenSpace.cells(level, storey)
	local list: { { i: number, k: number } } = {}
	for id in cells do
		local i = id // 1024 - 512
		local k = id % 1024 - 512
		table.insert(list, { i = i, k = k })
	end
	table.sort(list, function(a, b)
		if a.k ~= b.k then
			return a.k > b.k
		end
		return a.i < b.i
	end)
	local used: { [number]: boolean } = {}
	local span = math.max(1, math.floor(most / CELL))
	local tiles: { Tile } = {}
	for _, cell in list do
		if used[key(cell.i, cell.k)] then
			continue
		end
		-- Across first, then back, while the whole row is free
		local width = 1
		while width < span and cells[key(cell.i + width, cell.k)] and not used[key(cell.i + width, cell.k)] do
			width += 1
		end
		local depth = 1
		while depth < span do
			local row = cell.k - depth
			local full = true
			for d = 0, width - 1 do
				if not cells[key(cell.i + d, row)] or used[key(cell.i + d, row)] then
					full = false
					break
				end
			end
			if not full then
				break
			end
			depth += 1
		end
		for d = 0, width - 1 do
			for e = 0, depth - 1 do
				used[key(cell.i + d, cell.k - e)] = true
			end
		end
		table.insert(tiles, {
			x0 = cell.i * CELL,
			x1 = (cell.i + width) * CELL,
			z0 = (cell.k + 1) * CELL,
			z1 = (cell.k + 1 - depth) * CELL,
		})
	end
	return tiles
end

-- The storey a height belongs to (nil between them, outside the shafts)
function DenSpace.storeyAt(y: number): number?
	for n, s in Dens.storeys do
		if y >= s.floor - 1 and y <= s.ceiling + 6 then
			return n
		end
	end
	return nil
end

-- Whether a point is inside the den's rooms open at a level (`pad` studs of slack
-- round each room for things set into its rough walls)
function DenSpace.inside(level: number, at: Vector3, pad: number): boolean
	local storey = DenSpace.storeyAt(at.Y)
	if storey == nil then
		return false
	end
	local s = DenSpace.storey(storey)
	if at.Y < s.deck - 0.5 then
		return false
	end
	for _, room in DenSpace.rooms(level, storey) do
		if
			math.abs(at.X) <= room.x + pad
			and at.Z <= room.z0 + pad
			and at.Z >= room.z1 - pad
			and at.Y <= s.deck + DenSpace.vaultAt(room, math.min(math.abs(at.X), room.x)) + pad
		then
			return true
		end
	end
	return false
end

export type Check = { ok: boolean, why: string? }

export type Placed = { uid: number, id: string, x: number, y: number, z: number, r: number, s: string }

-- Whether a floor thing at `at` stands on the deck or on top of another placed
-- floor thing (a lamp on a table, a table on a rug): raised off the deck, its pivot
-- must be within 0.9 of something's top and inside that thing's turned footprint
-- (playtest 2026-10-13: one stood on a pillar's sconce ledge). `except` is the uid
-- being moved.
function DenSpace.resting(level: number, placed: { Placed }, at: Vector3, except: number?): Check
	local storey = DenSpace.storeyAt(at.Y)
	if storey == nil then
		return { ok = false, why = "Put it on the floor" }
	end
	if at.Y <= DenSpace.storey(storey).deck + 0.3 then
		return { ok = true }
	end
	for _, other in placed do
		local item = Dens.itemsById[other.id]
		if other.uid == except or other.s ~= "floor" or item == nil then
			continue
		end
		if math.abs(other.y + item.size.Y - at.Y) > 0.9 then
			continue
		end
		-- Into the other thing's own frame (its turn is about y in the den's frame,
		-- whose z runs the other way to a CFrame's)
		local turn = math.rad(other.r)
		local dx, dz = at.X - other.x, at.Z - other.z
		local lx = dx * math.cos(turn) + dz * math.sin(turn)
		local lz = dx * math.sin(turn) - dz * math.cos(turn)
		if math.abs(lx) <= item.size.X / 2 + 0.4 and math.abs(lz) <= item.size.Z / 2 + 0.4 then
			return { ok = true }
		end
	end
	return { ok = false, why = "Put it on the floor, or on top of something" }
end

-- Whether `item` may go at `at` (its pivot, in the den's frame) on `surface` in a
-- den of `level`. A floor thing stands on a deck (or on something on it); a wall or
-- ceiling thing goes against the rock inside the rooms.
function DenSpace.check(level: number, item: DensConfig.Item, surface: string, at: Vector3): Check
	if not table.find(item.kinds, surface) then
		return { ok = false, why = `A {item.name} doesn't go on the {surface}` }
	end
	if surface == "floor" then
		local storey = DenSpace.storeyAt(at.Y)
		if storey == nil or storey > DenSpace.storeys(level) then
			return { ok = false, why = "Put it on the floor" }
		end
		local deck = DenSpace.storey(storey).deck
		if at.Y < deck - 0.1 or at.Y > deck + 12 then
			return { ok = false, why = "Put it on the floor" }
		end
		if not DenSpace.onDeck(level, storey, at.X, at.Z) then
			-- Standing on something (a lamp on a table by the pool) its middle may hang
			-- over a hole's edge, with deck close by (playtest 2026-10-13)
			if at.Y < deck + 0.3 or not DenSpace.nearDeck(level, storey, at.X, at.Z) then
				return { ok = false, why = "That's not on your floor" }
			end
		end
		return { ok = true }
	end
	-- (6 studs of slack: the rock bulges in and out round the rooms, and the ends of
	-- the main room and the Burrow are rounded well past their floors)
	if not DenSpace.inside(level, at, 6) then
		return { ok = false, why = "That's outside your den" }
	end
	local storey = DenSpace.storeyAt(at.Y) or 1
	local deck = DenSpace.storey(storey).deck
	if surface == "wall" and at.Y < deck + 1 then
		return { ok = false, why = "Higher up the wall" }
	end
	if surface == "ceiling" and at.Y < deck + 6 then
		return { ok = false, why = "That ceiling is too low" }
	end
	return { ok = true }
end

export type LayoutPlacement = { id: string, x: number, y: number, z: number, r: number }

-- Where a starter layout (Config/Dens `layouts`) fits on the floor round `anchor`
-- (den frame), its front turned to `facing` degrees (0 faces +z): every piece on the
-- deck to its corners, clear of the floor things already placed (rugs only clash
-- with rugs, others with others, so a chair may stand on your rug). It tries the
-- spot, then rings 2 studs apart up to 24 out, facing you; then the same turned
-- the other three ways. Nil and why when nothing fits.
function DenSpace.fitLayout(
	level: number,
	placed: { Placed },
	pieces: { DensConfig.LayoutPiece },
	anchor: Vector3,
	facing: number
): ({ LayoutPlacement }?, string?)
	local storey = DenSpace.storeyAt(anchor.Y)
	if storey == nil or storey > DenSpace.storeys(level) then
		return nil, "Aim at your floor"
	end
	local deck = DenSpace.storey(storey).deck
	type Spot = { x: number, z: number, radius: number, flat: boolean }
	local taken: { Spot } = {}
	for _, other in placed do
		local item = Dens.itemsById[other.id]
		if item and other.s == "floor" and math.abs(other.y - deck) < 0.5 then
			local radius = 0.4 * math.max(item.size.X, item.size.Z)
			table.insert(taken, { x = other.x, z = other.z, radius = radius, flat = item.flat == true })
		end
	end
	local function clear(x: number, z: number, radius: number, flat: boolean, list: { Spot }): boolean
		for _, spot in list do
			if spot.flat == flat and (x - spot.x) ^ 2 + (z - spot.z) ^ 2 < (radius + spot.radius) ^ 2 then
				return false
			end
		end
		return true
	end
	local function try(ax: number, az: number, turn: number): { LayoutPlacement }?
		local c, s = math.cos(math.rad(turn)), math.sin(math.rad(turn))
		local out: { LayoutPlacement } = {}
		for _, piece in pieces do
			local item = Dens.itemsById[piece.id]
			if item == nil then
				return nil
			end
			local x = ax + piece.x * c - piece.z * s
			local z = az + piece.x * s + piece.z * c
			local r = (piece.r + turn) % 360
			if not DenSpace.check(level, item, "floor", Vector3.new(x, deck, z)).ok then
				return nil
			end
			local rc, rs = math.cos(math.rad(r)), math.sin(math.rad(r))
			for _, corner in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
				local lx, lz = corner[1] * 0.42 * item.size.X, corner[2] * 0.42 * item.size.Z
				if not DenSpace.onDeck(level, storey, x + lx * rc + lz * rs, z + lx * rs - lz * rc) then
					return nil
				end
			end
			local radius = 0.4 * math.max(item.size.X, item.size.Z)
			local flat = item.flat == true
			if not clear(x, z, radius, flat, taken) then
				return nil
			end
			table.insert(out, { id = item.id, x = x, y = deck, z = z, r = r })
		end
		return out
	end
	local base = math.floor(facing / 90 + 0.5) * 90
	local turns = { base % 360, (base + 90) % 360, (base - 90) % 360, (base + 180) % 360 }
	-- Facing you anywhere in reach first, then turned the other ways
	for _, turn in turns do
		for ring = 0, 12 do
			for i = -ring, ring do
				for k = -ring, ring do
					if math.max(math.abs(i), math.abs(k)) ~= ring then
						continue
					end
					local fit = try(anchor.X + i * 2, anchor.Z + k * 2, turn)
					if fit then
						return fit, nil
					end
				end
			end
		end
	end
	return nil, "Not enough open floor here · aim at a roomier spot"
end

return DenSpace
