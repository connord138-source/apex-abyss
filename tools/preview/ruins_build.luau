-- run_ruins.sh builder: builds the Sunken Ruins (src/server/Ruins.luau) on the
-- Terrain Shelf.luau lays, with the ground answered from the fill ops (a column's
-- top solid surface, Air carves taken out), then:
--   * counts what it made (C| line) and prints Ruins.build's own summary;
--   * checks every swim line it registered (the gateway and avenue, the temple's
--     door, the courtyard's stairs, the doorways and gates out in the biome) for a
--     LV 100 fish: spheres of radius 6.8 every half stud along it and 2.5 studs off
--     it each way, against every part that collides (a block or wedge as its box, a
--     ball as a ball, a cylinder as its box: never optimistic). S| lines, then a
--     verdict;
--   * prints the cameras render_hub.py renders (V| lines) and dumps every part.
local FISH = 6.8
local World = Config.World
local floorY = World.deep.floorY

-- The ground from the ops ----------------------------------------------------
local ops = Shelf.ops()
local near = {}
for _, op in ops do
	local c = op.center
	local ext = if op.kind == "block" then op.size.Magnitude / 2 else math.sqrt(op.radius ^ 2 + ((op.height or 0) / 2) ^ 2)
	if c.X + ext > 400 and c.X - ext < 1700 and c.Z + ext > -1300 and c.Z - ext < 1600 then
		table.insert(near, op)
	end
end

local function column(op, x, z)
	-- (bottom, top) of the op along the vertical line through (x, z), or nil
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
	-- a block: the vertical line against its box (slabs)
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

-- Build ----------------------------------------------------------------------
USE_PROPS = USE_PROPS_ENV
local root = Instance.new("Folder")
root.Name = "World"
local biomes = Instance.new("Folder")
biomes.Name = "Biomes"
biomes.Parent = root
local folder = Instance.new("Folder")
folder.Name = "Ruins"
folder.Parent = biomes
Ruins.build(folder, groundAt)
local total, collide, query, shadow = countParts(folder)
print(string.format("C|%d|%d|%d|%d", total, collide, query, shadow))

-- Swim lines -----------------------------------------------------------------
local solid = {}
for _, d in folder:GetDescendants() do
	if d.IsPart and d.CanCollide ~= false and (d.Transparency or 0) < 1 then
		table.insert(solid, d)
	end
end
local function boxDistance(center, part)
	local p = part.CFrame:PointToObjectSpace(center)
	local h = part.Size / 2
	if part.Shape and part.Shape.Name == "Ball" then
		return p.Magnitude - math.min(part.Size.X, part.Size.Y, part.Size.Z) / 2
	end
	local q = Vector3.new(math.clamp(p.X, -h.X, h.X), math.clamp(p.Y, -h.Y, h.Y), math.clamp(p.Z, -h.Z, h.Z))
	return (p - q).Magnitude
end
local failures = 0
for _, line in Ruins.passes do
	local worst, blocked = math.huge, nil
	for i = 1, #line.points - 1 do
		local a, b = line.points[i], line.points[i + 1]
		local span = b - a
		local along = span.Unit
		local side = along:Cross(Vector3.new(0, 1, 0))
		side = if side.Magnitude < 1e-3 then Vector3.new(1, 0, 0) else side.Unit
		local up = side:Cross(along).Unit
		local mid = (a + b) / 2
		local reach = span.Magnitude / 2 + 40
		local nearby = {}
		for _, part in solid do
			if (part.CFrame.p - mid).Magnitude < reach + part.Size.Magnitude / 2 then
				table.insert(nearby, part)
			end
		end
		local steps = math.ceil(span.Magnitude / 0.5)
		for s = 0, steps do
			local base = a + span * (s / steps)
			for _, off in { Vector3.new(0, 0, 0), side * 2.5, side * -2.5, up * 2.5, up * -2.5 } do
				local center = base + off
				for _, part in nearby do
					local d = boxDistance(center, part) - FISH
					if d < worst then
						worst = d
					end
					if d < 0 and blocked == nil then
						blocked = string.format("%s (%s) at %.0f, %.0f, %.0f", part.Name, part.Parent and part.Parent.Name or "?", center.X, center.Y, center.Z)
					end
				end
			end
		end
	end
	if blocked then
		failures += 1
	end
	print(string.format("S|%s|clearance %.2f|%s", line.label, worst, blocked or "clear"))
end
print(if failures == 0 then "S|every swim line clear for a LV 100 fish" else `S|{failures} BLOCKED`)

-- Cameras (the city's frame: x along the avenue toward the temple, z across) ----
local Layout = Config.Ruins
local out = Vector3.new(math.cos(math.rad(Layout.angle)), 0, math.sin(math.rad(Layout.angle)))
local origin = out * Layout.radius + Vector3.new(0, floorY, 0)
local city = CFrame.fromMatrix(origin, out, Vector3.new(0, 1, 0), out:Cross(Vector3.new(0, 1, 0)))
local function view(name, from, to, fov)
	local a, b = city * from, city * to
	print(string.format("V|%s|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%.1f", name, a.X, a.Y, a.Z, b.X, b.Y, b.Z, fov))
end
view("approach", Vector3.new(-305, 22, 10), Vector3.new(-60, 30, 0), 70)
view("avenue", Vector3.new(-205, 15, -8), Vector3.new(-40, 26, 2), 70)
view("temple", Vector3.new(-150, 42, -95), Vector3.new(0, 24, 0), 70)
view("cella", Vector3.new(-72, 34, 14), Vector3.new(10, 26, -2), 72)
view("head", Vector3.new(-128, 16, 4), Vector3.new(-88, 8, 40), 70)
view("court", Vector3.new(-118, 34, -84), Vector3.new(-118, -10, -150), 72)
view("theatre", Vector3.new(-140, 28, 78), Vector3.new(-140, 4, 172), 72)
view("quarter", Vector3.new(30, 32, -70), Vector3.new(160, 10, 30), 72)
view("aerial", Vector3.new(-330, 260, -300), Vector3.new(-40, -10, 20), 58)

dumpParts(root)
