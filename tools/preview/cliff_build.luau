-- run_cliff.sh builder: dresses the drop-off (src/server/Cliff.luau) on the wall
-- Shelf.luau lays, with rays answered from the fill ops (a point is the material of
-- the last op that holds it, so carves and fills come out in their order), then:
--   * counts what it made (C| line) and prints Cliff.build's own summary;
--   * prints the region's box (B| line) and its cameras (V| lines) for render_hub.py;
--   * dumps the parts and props inside the region (the whole ring would be slow).
-- REGION (an angle, degrees) is set by run_cliff.sh.
local World = Config.World
local floorY = World.deep.floorY
local ops, features = Shelf.ops()
local layout = features.cliff or { face = World.shelf.radius + 40, ledges = {}, caves = {} } -- (an older Shelf.luau)
local FACE = layout.face

-- The ops round the drop-off, indexed in 24-stud columns; the huge ones (the slab,
-- the drum, its hollow, the sand cap) are checked everywhere
local BIN = 24
local big, bins = {}, {}
local function binKey(bx, bz)
	return (bx + 4000) * 8192 + (bz + 4000)
end
for index, op in ops do
	local c = op.center
	local ext = if op.kind == "ball"
		then op.radius
		elseif op.kind == "block" then op.size.Magnitude / 2
		else math.sqrt(op.radius ^ 2 + (op.height / 2) ^ 2)
	local r = math.sqrt(c.X * c.X + c.Z * c.Z)
	local entry = { index = index, op = op, ext = ext, inv = if op.cframe then op.cframe:Inverse() else nil }
	if ext > 160 then
		table.insert(big, entry)
	elseif r + ext > 640 and r - ext < 1320 then
		for bx = math.floor((c.X - ext) / BIN), math.floor((c.X + ext) / BIN) do
			for bz = math.floor((c.Z - ext) / BIN), math.floor((c.Z + ext) / BIN) do
				local key = binKey(bx, bz)
				bins[key] = bins[key] or {}
				table.insert(bins[key], entry)
			end
		end
	end
end
local function descending(a, b)
	return a.index > b.index
end
table.sort(big, descending)
for _, list in bins do
	table.sort(list, descending)
end

local function holds(entry, p)
	local op = entry.op
	if op.kind == "ball" then
		local d = p - op.center
		return d.X * d.X + d.Y * d.Y + d.Z * d.Z <= op.radius * op.radius
	end
	local d = p - op.center
	if math.abs(d.Y) > entry.ext or math.abs(d.X) > entry.ext or math.abs(d.Z) > entry.ext then
		return false
	end
	local q = entry.inv * p
	if op.kind == "block" then
		local h = op.size / 2
		return math.abs(q.X) <= h.X and math.abs(q.Y) <= h.Y and math.abs(q.Z) <= h.Z
	end
	return math.abs(q.Y) <= op.height / 2 and q.X * q.X + q.Z * q.Z <= op.radius * op.radius
end

-- The material at `p` (nil: water)
local function materialAt(p)
	local list = bins[binKey(math.floor(p.X / BIN), math.floor(p.Z / BIN))]
	local i, j = 1, 1
	-- merge the two lists by op order, latest first
	while true do
		local a = if list then list[i] else nil
		local b = big[j]
		local entry
		if a and (b == nil or a.index > b.index) then
			entry = a
			i += 1
		elseif b then
			entry = b
			j += 1
		else
			return nil
		end
		if holds(entry, p) then
			local name = entry.op.material.Name
			return if name == "Air" then nil else entry.op.material
		end
	end
end

local DIRS = {}
for _, d in
	{
		{ 1, 0, 0 },
		{ -1, 0, 0 },
		{ 0, 1, 0 },
		{ 0, -1, 0 },
		{ 0, 0, 1 },
		{ 0, 0, -1 },
		{ 1, 1, 1 },
		{ 1, 1, -1 },
		{ 1, -1, 1 },
		{ 1, -1, -1 },
		{ -1, 1, 1 },
		{ -1, 1, -1 },
		{ -1, -1, 1 },
		{ -1, -1, -1 },
	}
do
	table.insert(DIRS, Vector3.new(d[1], d[2], d[3]).Unit)
end

-- A ray against the ops (Terrain): the first solid point, its normal (from which
-- way the water lies round it) and its material
local RAYS = 0
local function cast(origin, direction)
	RAYS += 1
	local length = direction.Magnitude
	local unit = direction.Unit
	local step = 1.5
	local t = 0
	local prev = 0
	local hit = nil
	while t <= length do
		local p = origin + unit * t
		if materialAt(p) then
			hit = t
			break
		end
		prev = t
		t += step
	end
	if hit == nil then
		return nil, nil, nil
	end
	local lo, hi = prev, hit
	for _ = 1, 7 do
		local mid = (lo + hi) / 2
		if materialAt(origin + unit * mid) then
			hi = mid
		else
			lo = mid
		end
	end
	local p = origin + unit * hi
	local n = Vector3.new(0, 0, 0)
	for _, d in DIRS do
		if materialAt(p + d * 3) == nil then
			n = n + d
		end
	end
	if n.Magnitude < 0.01 then
		n = -unit
	end
	return p, n.Unit, materialAt(origin + unit * (hi + 0.6)) or materialAt(p)
end

-- Build ----------------------------------------------------------------------
USE_PROPS = USE_PROPS_ENV
local root = Instance.new("Folder")
root.Name = "World"
local biomes = Instance.new("Folder")
biomes.Name = "Biomes"
biomes.Parent = root
local folder = Instance.new("Folder")
folder.Name = "Cliff"
folder.Parent = biomes
local clock = os.clock()
if Cliff and features.cliff then
	local stats = Cliff.build(folder, layout, cast)
	print(
		string.format(
			"[Cliff] %d parts (%d solid, %d glow), %d lights, %d props dressed, %d rays, %.1f s",
			stats.parts,
			stats.solid,
			stats.glow,
			stats.lights,
			stats.props,
			RAYS,
			os.clock() - clock
		)
	)
	local names = {}
	for name, n in stats.pieces do
		table.insert(names, `{name} {n}`)
	end
	table.sort(names)
	print("[Cliff] pieces: " .. table.concat(names, ", "))
end
local total, collide, query, shadow = countParts(folder)
print(string.format("C|%d|%d|%d|%d", total, collide, query, shadow))

-- The region and its cameras --------------------------------------------------
local A = REGION
local HALF = REGION_HALF or 17
local function polar(angle, r, y)
	local a = math.rad(angle)
	return Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
end
local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
for k = 0, 8 do
	local angle = A - HALF + 2 * HALF * k / 8
	for _, r in { 760, FACE + 320 } do
		local p = polar(angle, r, 0)
		x0, x1 = math.min(x0, p.X), math.max(x1, p.X)
		z0, z1 = math.min(z0, p.Z), math.max(z1, p.Z)
	end
end
print(string.format("B|%.0f,%.0f,%.0f,%.0f,%.0f,%.0f", x0, x1, floorY - 40, 70, z0, z1))
-- The light for render_hub.py (SUN_DIR): in from the open water, 30 degrees off the
-- vertical, so the wall's relief reads in a still (in game the sun is near the
-- zenith, and the bands' shadows and the ambient do that work)
local seaward = polar(A, 1, 0)
local sun = seaward * -math.sin(math.rad(30)) + Vector3.new(0, -math.cos(math.rad(30)), 0)
print(string.format("D|%.3f,%.3f,%.3f", sun.X, sun.Y, sun.Z))
local function view(name, from, to, fov)
	print(string.format("V|%s|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%.1f", name, from.X, from.Y, from.Z, to.X, to.Y, to.Z, fov))
end
view("wide", polar(A + 7, FACE + 300, floorY + 30), polar(A - 3, FACE, -175), 74)
view("face", polar(A + 1, FACE + 170, -190), polar(A - 1, FACE, -200), 70)
view("lip", polar(A + 3.2, FACE + 70, -24), polar(A - 1.2, FACE + 4, -22), 62)
view("over", polar(A - 1.5, FACE - 25, 75), polar(A + 1, FACE + 120, -330), 72)
-- the ledge nearest the region's middle, from a little out and over it
local best, bestD = nil, math.huge
for _, ledge in layout.ledges do
	local d = math.abs(((ledge.angle - A + 180) % 360) - 180)
	if d < bestD and d < HALF - 4 then
		best, bestD = ledge, d
	end
end
if best then
	local out = polar(best.angle, 1, 0)
	local along = Vector3.new(-out.Z, 0, out.X)
	view("ledge", best.top + out * 62 + along * 34 + Vector3.new(0, 26, 0), best.top + out * 4, 58)
end
-- a cave mouth or a buttress in the region
for _, cave in layout.caves do
	local d = math.abs(((math.deg(math.atan2(cave.position.Z, cave.position.X)) - A + 180) % 360) - 180)
	if d < HALF - 4 then
		local out = Vector3.new(cave.position.X, 0, cave.position.Z).Unit
		view("cave", cave.position + out * 80 + Vector3.new(0, 12, 0), cave.position, 60)
		break
	end
end

-- Only what's in the region goes to the renderer
local box = { x0 - 20, x1 + 20, z0 - 20, z1 + 20 }
local function inside(p)
	return p.X > box[1] and p.X < box[2] and p.Z > box[3] and p.Z < box[4]
end
for _, d in folder:GetDescendants() do
	if d.IsPart and not inside(d.CFrame.p) then
		d.Parent = nil
	end
end
for i = #PROP_PLACEMENTS, 1, -1 do
	if not inside(PROP_PLACEMENTS[i].cframe.p) then
		table.remove(PROP_PLACEMENTS, i)
	end
end
dumpParts(root)
