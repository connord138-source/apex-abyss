-- run_biome.sh builder: builds one biome's landmarks (Wrecks.luau, TrenchDress.luau,
-- KelpDress.luau, ReefDress.luau or BlueDress.luau; BIOME picks) on the Terrain
-- Shelf.luau lays, with the ground answered from the fill ops (a column's top solid
-- surface, Air carves taken out, as ruins_build.luau), then counts what it made (C|),
-- prints the module's cameras (V|) and dumps every part for render_hub.py.
-- REGION (xmin, xmax, zmin, zmax) keeps the ops to the biome's stretch.
local World = Config.World
local floorY = World.deep.floorY

local ops, features = Shelf.ops()
local near = {}
for _, op in ops do
	local c = op.center
	local ext = if op.kind == "block"
		then op.size.Magnitude / 2
		else math.sqrt(op.radius ^ 2 + ((op.height or 0) / 2) ^ 2)
	if c.X + ext > REGION[1] and c.X - ext < REGION[2] and c.Z + ext > REGION[3] and c.Z - ext < REGION[4] then
		table.insert(near, op)
	end
end

local function column(op, x, z)
	if op.kind == "ball" then
		local dx, dz = x - op.center.X, z - op.center.Z
		local d2 = dx * dx + dz * dz
		if d2 >= op.radius * op.radius then
			return nil
		end
		local h = math.sqrt(op.radius * op.radius - d2)
		return op.center.Y - h, op.center.Y + h
	end
	local cf = op.cframe
	if op.kind == "cylinder" then
		if math.abs(cf.UpVector.Y) < 0.9 then
			return nil
		end
		local dx, dz = x - op.center.X, z - op.center.Z
		if dx * dx + dz * dz >= op.radius * op.radius then
			return nil
		end
		return op.center.Y - op.height / 2, op.center.Y + op.height / 2
	end
	local o = cf:PointToObjectSpace(Vector3.new(x, 0, z))
	local d = cf:VectorToObjectSpace(Vector3.new(0, 1, 0))
	local lo, hi = -math.huge, math.huge
	local half = op.size / 2
	for _, axis in { "X", "Y", "Z" } do
		local oa, da, ha = o[axis], d[axis], half[axis]
		if math.abs(da) < 1e-6 then
			if oa < -ha or oa > ha then
				return nil
			end
		else
			local t1, t2 = (-ha - oa) / da, (ha - oa) / da
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			lo, hi = math.max(lo, t1), math.min(hi, t2)
		end
	end
	if lo > hi then
		return nil
	end
	return lo, hi
end

local cache = {}
local function groundAt(x, z)
	local key = math.floor(x) * 100000 + math.floor(z)
	local known = cache[key]
	if known == nil then
		local top = -math.huge
		for _, op in near do
			local bottom, high = column(op, x, z)
			if bottom then
				if op.material.Name == "Air" then
					if top <= high + 0.01 and top >= bottom - 0.01 then
						top = bottom
					end
				elseif high > top then
					top = high
				end
			end
		end
		known = if top == -math.huge then floorY else top
		cache[key] = known
	end
	return Vector3.new(x, known, z), Vector3.new(0, 1, 0)
end

USE_PROPS = USE_PROPS_ENV
local root = Instance.new("Folder")
root.Name = "World"
local biomes = Instance.new("Folder")
biomes.Name = "Biomes"
biomes.Parent = root
local folder = Instance.new("Folder")
folder.Name = BIOME
folder.Parent = biomes

local views = {}
local summary
if BIOME == "Wreck" then
	summary = Wrecks.build(folder, groundAt)
	-- The fourteen scattered wrecks: WorldService draws their spots on the shared
	-- Random; here they're laid on the stub's own (so not the game's spots)
	local rng = Random.new(41)
	local made = 0
	for i = 1, 40 do
		if made >= 14 then
			break
		end
		local angle = math.rad(rng:NextNumber(137, 223))
		local r = rng:NextNumber(540, 800)
		local x, z = math.cos(angle) * r, math.sin(angle) * r
		local ground = groundAt(x, z)
		made += 1
		Wrecks.scatter(folder, ground, rng:NextNumber(60, 110), rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(-14, 14)), made)
	end
	summary = Wrecks.stats()
	views = Wrecks.views
	table.insert(views, { name = "bay", from = Vector3.new(-380, 150, 120), to = Vector3.new(-660, -10, -10), fov = 70 })
elseif BIOME == "Trench" then
	summary = TrenchDress.build(folder, groundAt, features.lair)
	views = TrenchDress.views
elseif BIOME == "Kelp" then
	summary = KelpDress.build(folder, folder, groundAt)
	views = KelpDress.views
elseif BIOME == "Reef" then
	local rocks = {}
	for _, list in { features.reefRocks, features.outcrops or {} } do
		for _, rock in list do
			table.insert(rocks, rock)
		end
	end
	summary = ReefDress.build(folder, groundAt, features.blueHole, rocks)
	views = ReefDress.views
elseif BIOME == "Blue" then
	summary = BlueDress.build(folder, groundAt)
	views = BlueDress.views
end
print(
	string.format(
		"[%s] %d parts (%d solid, %d glowing), %d models, %d stand-ins, %d lights",
		BIOME,
		summary.parts,
		summary.solid,
		summary.glow,
		summary.models,
		summary.standins,
		summary.lights
	)
)
local names = {}
for name, n in summary.heroes do
	table.insert(names, name .. " x" .. n)
end
table.sort(names)
print("[" .. BIOME .. "] models: " .. table.concat(names, ", "))
local total, collide, query, shadow = countParts(folder)
print(string.format("C|%d|%d|%d|%d", total, collide, query, shadow))
for _, v in views do
	print(
		string.format(
			"V|%s|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%.1f",
			v.name,
			v.from.X,
			v.from.Y,
			v.from.Z,
			v.to.X,
			v.to.Y,
			v.to.Z,
			v.fov
		)
	)
end
dumpParts(root)
