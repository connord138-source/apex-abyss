-- run_vents.sh builder: lays out the Hydrothermal Vents' field (src/server/VentsPlan.luau
-- through Shelf.ops) and dresses it (src/server/Vents.luau) on the Terrain Shelf.luau
-- lays, the ground answered from the fill ops (a column's top solid surface, Air
-- carves taken out), then:
--   * counts what it made (C| line) and prints Vents.build's own summary;
--   * checks the prey schools (K| lines): Shared/Schools' lift (`settle`, over 4-stud
--     cells as Shared/Ground answers) is worked out over the ground without the
--     field's Terrain and parts and over the ground with them, and every school whose
--     lift grew is listed (none should: every top stays under VentsPlan.ceiling);
--   * stands in for WorldService's own vent dressing (a glowing throat and a light on
--     each chimney) so the renders show the field as it is in the game;
--   * prints the cameras render_hub.py renders (V| lines) with the Terrain box each
--     wants (B| lines: name, x0,x1,y0,y1,z0,z1, cell) and dumps every part.
local World = Config.World
local floorY = World.deep.floorY

-- The ground from the ops ----------------------------------------------------
local ops, features = Shelf.ops()
local plan = features.vents
assert(plan, "Shelf.ops gave no vents field")

local REGION = { x = { -1700, -350 }, z = { -1200, 1450 } }
local function inRegion(x, z, pad)
	return x > REGION.x[1] - pad and x < REGION.x[2] + pad and z > REGION.z[1] - pad and z < REGION.z[2] + pad
end
local near, base = {}, {}
for index, op in ops do
	local c = op.center
	local ext = if op.kind == "block"
		then op.size.Magnitude / 2
		else math.sqrt(op.radius ^ 2 + ((op.height or 0) / 2) ^ 2)
	if
		c.X + ext > REGION.x[1]
		and c.X - ext < REGION.x[2]
		and c.Z + ext > REGION.z[1]
		and c.Z - ext < REGION.z[2]
	then
		table.insert(near, op)
		if index < plan.opsFrom or index > plan.opsTo then
			table.insert(base, op)
		end
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
	local half
	if op.kind == "cylinder" then
		-- along the line through the cylinder: its axis frame, radius in X and Z
		local o = cf:PointToObjectSpace(Vector3.new(x, 0, z))
		local d = cf:VectorToObjectSpace(Vector3.new(0, 1, 0))
		-- the line p(t) = o + d t: inside when (px^2 + pz^2) <= r^2 and |py| <= h/2
		local a = d.X * d.X + d.Z * d.Z
		local b = 2 * (o.X * d.X + o.Z * d.Z)
		local cc = o.X * o.X + o.Z * o.Z - op.radius * op.radius
		local lo, hi
		if a < 1e-9 then
			if cc > 0 then
				return nil
			end
			lo, hi = -math.huge, math.huge
		else
			local disc = b * b - 4 * a * cc
			if disc < 0 then
				return nil
			end
			local s = math.sqrt(disc)
			lo, hi = (-b - s) / (2 * a), (-b + s) / (2 * a)
		end
		local h = op.height / 2
		if math.abs(d.Y) > 1e-9 then
			local t1, t2 = (-h - o.Y) / d.Y, (h - o.Y) / d.Y
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			lo, hi = math.max(lo, t1), math.min(hi, t2)
		elseif math.abs(o.Y) > h then
			return nil
		end
		if lo > hi then
			return nil
		end
		return lo, hi
	end
	-- a block: the vertical line against its box (slabs)
	local o = cf:PointToObjectSpace(Vector3.new(x, 0, z))
	local d = cf:VectorToObjectSpace(Vector3.new(0, 1, 0))
	local lo, hi = -math.huge, math.huge
	half = op.size / 2
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

-- Ops bucketed by 32-stud columns, so a column's top asks only the ops over it
local BIN = 32
local function bucket(list)
	local bins = {}
	for _, op in list do
		local c = op.center
		local ext = if op.kind == "block"
			then op.size.Magnitude / 2
			else math.sqrt(op.radius ^ 2 + ((op.height or 0) / 2) ^ 2)
		for bx = math.floor((c.X - ext) / BIN), math.floor((c.X + ext) / BIN) do
			for bz = math.floor((c.Z - ext) / BIN), math.floor((c.Z + ext) / BIN) do
				local key = (bx + 1000) * 4096 + (bz + 1000)
				local cell = bins[key]
				if cell == nil then
					cell = {}
					bins[key] = cell
				end
				table.insert(cell, op)
			end
		end
	end
	return bins
end
local nearBins, baseBins = bucket(near), bucket(base)

local function topOf(bins, x, z)
	local top = -math.huge
	local cell = bins[(math.floor(x / BIN) + 1000) * 4096 + (math.floor(z / BIN) + 1000)]
	-- (the ops in order: a later one overwrites an earlier one, an Air carve opens
	-- the top it cuts into)
	if cell then
		for _, op in cell do
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
	end
	return if top == -math.huge then floorY else top
end

local cache = {}
local function groundAt(x, z)
	local key = math.floor(x * 2) * 1000000 + math.floor(z * 2)
	local known = cache[key]
	if known == nil then
		known = topOf(nearBins, x, z)
		cache[key] = known
	end
	return Vector3.new(x, known, z), Vector3.new(0, 1, 0)
end

-- Build ----------------------------------------------------------------------
USE_PROPS = false
local root = Instance.new("Folder")
root.Name = "World"
local biomes = Instance.new("Folder")
biomes.Name = "Biomes"
biomes.Parent = root
local folder = Instance.new("Folder")
folder.Name = "Vents"
folder.Parent = biomes
-- Test boulders (WorldService `rock`: a Rock part and its BoulderRoundProp model over
-- the same spot) on the landmarks, which Vents.build's tidy should clear, and one
-- out in the Ruins, which it must leave
local rocks = Instance.new("Folder")
rocks.Name = "Rocks"
rocks.Parent = biomes
local testSpots = {}
if plan.brine then
	table.insert(testSpots, plan.brine.center)
end
if plan.columns[1] then
	table.insert(testSpots, plan.columns[1].at)
end
if plan.forge then
	local f = plan.forge
	table.insert(testSpots, (groundAt(f.center.X, f.center.Z)))
	local q = VentsPlan.runnelPoint(f, f.runnels[2], 0.5)
	table.insert(testSpots, (groundAt(q.X, q.Z)))
end
if plan.smokers[1] then
	local spire = plan.smokers[1].spires[1]
	table.insert(testSpots, (groundAt(spire.foot.X, spire.foot.Z)))
end
local expected = #testSpots
table.insert(testSpots, Vector3.new(1100, floorY, -300))
for _, spot in testSpots do
	local part = Instance.new("Part")
	part.Name = "Rock"
	part.Size = Vector3.new(8, 6, 8)
	part.CFrame = CFrame.new(spot + Vector3.new(0, 1.5, 0))
	part.Parent = rocks
	local prop = Instance.new("Model")
	prop.Name = "BoulderRoundProp"
	prop.CFrame = CFrame.new(spot + Vector3.new(0, 2.5, 0))
	prop.Parent = rocks
end
local stats = Vents.build(folder, plan, groundAt)
local left = #rocks:GetChildren()
print(
	string.format(
		"T|boulders: %d of %d test boulders (and their models) cleared off the landmarks (want %d), %d left",
		(#testSpots * 2 - left) / 2,
		#testSpots,
		expected,
		left / 2
	)
)
rocks.Parent = nil
local total, collide, query, shadow = countParts(folder)
print(string.format("C|%d|%d|%d|%d", total, collide, query, shadow))
print(string.format("O|%d Terrain ops (%d..%d) of %d", plan.opsTo - plan.opsFrom + 1, plan.opsFrom, plan.opsTo, #ops))

-- The chimneys' own dressing (WorldService ventSmoke), for the renders only
local context = Instance.new("Folder")
context.Name = "Context"
context.Parent = root
for _, chimney in plan.chimneys do
	local p = chimney.position
	local top = groundAt(p.X, p.Z)
	local throat = Instance.new("Part")
	throat.Name = "VentGlow"
	throat.Shape = Enum.PartType.Cylinder
	throat.Size = Vector3.new(1, 4.6, 4.6)
	throat.CFrame = CFrame.new(top + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	throat.Color = Color3.fromRGB(255, 112, 36)
	throat.Material = Enum.Material.Neon
	throat.Parent = context
	local lamp = Instance.new("PointLight")
	lamp.Color = Color3.fromRGB(255, 130, 50)
	lamp.Range = 50
	lamp.Brightness = 3
	lamp.Parent = throat
end

-- Schools --------------------------------------------------------------------
if SCHOOL_CHECK then
	local solid = {}
	for _, d in folder:GetDescendants() do
		if d.IsPart and d.CanCollide ~= false then
			table.insert(solid, d)
		end
	end
	local PBIN = 16
	local pbins = {}
	for _, part in solid do
		local h = part.Size / 2
		local reach = math.sqrt(h.X * h.X + h.Y * h.Y + h.Z * h.Z)
		local p = part.CFrame.p
		for bx = math.floor((p.X - reach) / PBIN), math.floor((p.X + reach) / PBIN) do
			for bz = math.floor((p.Z - reach) / PBIN), math.floor((p.Z + reach) / PBIN) do
				local key = (bx + 4000) * 8192 + (bz + 4000)
				pbins[key] = pbins[key] or {}
				table.insert(pbins[key], part)
			end
		end
	end
	local function partTop(x, z)
		local top = -math.huge
		local list = pbins[(math.floor(x / PBIN) + 4000) * 8192 + (math.floor(z / PBIN) + 4000)]
		if list then
			for _, part in list do
				local cf = part.CFrame
				local o = cf:PointToObjectSpace(Vector3.new(x, 0, z))
				local d = cf:VectorToObjectSpace(Vector3.new(0, 1, 0))
				local half = part.Size / 2
				local lo, hi = -math.huge, math.huge
				local inside = true
				for _, axis in { "X", "Y", "Z" } do
					local oa, da, ha = o[axis], d[axis], half[axis]
					if math.abs(da) < 1e-6 then
						if oa < -ha or oa > ha then
							inside = false
							break
						end
					else
						local t1, t2 = (-ha - oa) / da, (ha - oa) / da
						if t1 > t2 then
							t1, t2 = t2, t1
						end
						lo, hi = math.max(lo, t1), math.min(hi, t2)
					end
				end
				if inside and lo <= hi and hi > top then
					top = hi
				end
			end
		end
		return top
	end
	-- Shared/Ground.y: the middle of a 4-stud cell, never under the nominal floor - 40
	local function groundY(withField)
		local memo = {}
		return function(x, z)
			local cx, cz = math.floor(x / 4), math.floor(z / 4)
			local key = (cx + 2000) * 4096 + (cz + 2000)
			local known = memo[key]
			if known then
				return known
			end
			local mx, mz = (cx + 0.5) * 4, (cz + 0.5) * 4
			if not inRegion(mx, mz, 0) then
				known = Seafloor.y(mx, mz)
			else
				local top = topOf(if withField then nearBins else baseBins, mx, mz)
				if withField then
					top = math.max(top, partTop(mx, mz))
				end
				known = math.max(top, Seafloor.y(mx, mz) - 40)
			end
			memo[key] = known
			return known
		end
	end
	local function lifts()
		local most = {}
		for index, school in Schools.list do
			local r, angle = Seafloor.polar(school.center.X, school.center.Z)
			if r < 850 or not Seafloor.inSector(angle, 100, 250) then
				continue
			end
			local m = 0
			for k = 0, 63 do
				local a = k / 64 * 2 * math.pi
				local frame = Schools.schoolFrame(index, (a - school.phase) / school.angularSpeed)
				m = math.max(m, frame.Position.Y - (school.center.Y + math.sin(2 * a + school.phase) * school.height))
			end
			most[index] = m
		end
		return most
	end
	Schools.settle(groundY(false))
	local before = lifts()
	Schools.settle(groundY(true))
	local after = lifts()
	local grew, count, worst = 0, 0, 0
	for index, m in after do
		count += 1
		local was = before[index] or 0
		if m > was + 0.5 then
			grew += 1
			worst = math.max(worst, m - was)
			local s = Schools.list[index]
			print(string.format("K|school %d (%s) lifted %.1f studs (was %.1f)", index, s.prey, m, was))
		end
	end
	print(
		if grew == 0
			then string.format("K|schools: none of the %d schools over the Vents is lifted any higher by the field", count)
			else string.format("K|schools: %d of %d lifted higher by the field (worst +%.1f)", grew, count, worst)
	)
end

-- Cameras --------------------------------------------------------------------
local function view(name, from, to, fov, box, cell, fog)
	print(string.format("V|%s|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%.1f", name, from.X, from.Y, from.Z, to.X, to.Y, to.Z, fov))
	print(
		string.format(
			"B|%s|%d,%d,%d,%d,%d,%d|%g|%g",
			name,
			box[1],
			box[2],
			box[3],
			box[4],
			box[5],
			box[6],
			cell,
			fog or 170
		)
	)
end
local function boxAround(p, half, low, high)
	return {
		math.floor(p.X - half),
		math.ceil(p.X + half),
		math.floor(low),
		math.ceil(high),
		math.floor(p.Z - half),
		math.ceil(p.Z + half),
	}
end
local up = Vector3.new(0, 1, 0)
local function flat(v)
	return Vector3.new(v.X, 0, v.Z).Unit
end
-- A camera `distance` off `target` (flat), `rise` over it, from the first of 16
-- headings (starting toward the hub, or `start`) whose spot is in open water inside the map and
-- whose line to the target clears the ground (Terrain) and every solid part
local solidParts = {}
for _, d in folder:GetDescendants() do
	if d.IsPart and d.CanCollide ~= false then
		table.insert(solidParts, d)
	end
end
local function insideSolid(p)
	for _, part in solidParts do
		local o = part.CFrame:PointToObjectSpace(p)
		local h = part.Size / 2 + Vector3.new(0.5, 0.5, 0.5)
		if math.abs(o.X) < h.X and math.abs(o.Y) < h.Y and math.abs(o.Z) < h.Z then
			return true
		end
	end
	return false
end
local function openView(target, look, distance, rise, clearance, start, riseFirst)
	local toHub = start or flat(-target)
	local function clear(k, round)
		local turn = (if k % 2 == 0 then 1 else -1) * math.ceil(k / 2) * math.pi / 8
		local dir = Vector3.new(
			toHub.X * math.cos(turn) - toHub.Z * math.sin(turn),
			0,
			toHub.X * math.sin(turn) + toHub.Z * math.cos(turn)
		)
		local from = target + dir * distance + up * (rise + round * 30)
		if Seafloor.polar(from.X, from.Z) >= World.boundsRadius - 20 then
			return nil
		end
		-- (the line stops `clearance` short of the subject itself)
		local span = (look - from).Magnitude
		local share = math.max(0, (span - (clearance or 0)) / span)
		for i = 0, 24 do
			local q = from + (look - from) * (i / 24 * share)
			if (groundAt(q.X, q.Z)).Y > q.Y - 3 or insideSolid(q) then
				return nil
			end
		end
		return from
	end
	-- Higher each round (a spot down in a basin may have open water only over its
	-- rim); `riseFirst` tries every height on a heading before turning
	for outer = 0, if riseFirst then 15 else 5 do
		for inner = 0, if riseFirst then 5 else 15 do
			local from = if riseFirst then clear(outer, inner) else clear(inner, outer)
			if from then
				return from
			end
		end
	end
	return target + toHub * distance + up * rise
end
-- The whole field: from straight over its middle (a map, no haze) and from high
-- over the drop-off's foot (a thinner haze than a fish sees, to show the layout)
local FIELD = { -1560, -560, -572, -200, -1060, 1260 }
local middle = Vector3.new(-1180, floorY, 60)
view("map", middle + Vector3.new(0.01, 1150, 0), middle, 78, FIELD, 6, 6000)
local inward = flat(-middle)
-- (looking out over the field from just past the drop-off's foot, high up, toward
-- the Forge)
local aim = if plan.forge then middle:Lerp(plan.forge.center, 0.6) else middle
view("aerial", aim + flat(-aim) * 340 + up * 520, aim + up * 30, 70, FIELD, 6, 650)
local forge = plan.forge
if forge then
	local c = forge.center
	local toHub = flat(-c)
	local side = Vector3.new(-toHub.Z, 0, toHub.X)
	-- From ~150 studs off its foot, a fish's height up, turned 35° toward its shoulder
	-- cone (if it has one) so the cone shows against the flank, on a clear line
	local turnTo = 0
	if forge.shoulder then
		local toShoulder = flat(forge.shoulder.center - c)
		turnTo = if side:Dot(toShoulder) >= 0 then 1 else -1
	end
	local a = math.rad(35) * turnTo
	local dir = Vector3.new(
		toHub.X * math.cos(a) - toHub.Z * math.sin(a),
		0,
		toHub.X * math.sin(a) + toHub.Z * math.cos(a)
	)
	local look = c + up * (forge.height * 0.45)
	view(
		"forge",
		openView(c, look, 255, 70, forge.base + 10, dir, true),
		look,
		60,
		boxAround(c + dir * 120, 270, floorY - 130, floorY + forge.height + 20),
		3
	)
	view(
		"crater",
		c + toHub * 70 + side * 30 + up * (forge.height + 45),
		c + up * (forge.height - 10),
		55,
		boxAround(c, 70, floorY + forge.height - 60, floorY + forge.height + 20),
		2
	)
	-- Down the causeway toward the Forge
	local causeway = plan.causeway
	if causeway then
		local far = causeway.to
		view(
			"causeway",
			far + flat(far - c) * 30 + side * 14 + up * 22,
			causeway.from + up * 20,
			62,
			boxAround((far + causeway.from) / 2, 140, floorY - 20, floorY + 120),
			2
		)
	end
end
-- A basin: the one with the brine pool, from over its rim
local basins = Seafloor.ventBasins()
local brine = plan.brine
if brine then
	local b = basins[brine.basin]
	local center = Vector3.new(b.x, World.deep.ventsFloorY, b.z)
	view(
		"basin",
		openView(brine.center, brine.center + up * 4, brine.radius + 55, 50, brine.radius * 0.5),
		brine.center + up * 4,
		60,
		boxAround(center, b.radius + 70, World.deep.ventsFloorY - 20, floorY + 60),
		2
	)
end
for index, terrace in plan.terraces do
	local b = basins[terrace.basin]
	local dir = Vector3.new(math.cos(terrace.heading), 0, math.sin(terrace.heading))
	local wall = Vector3.new(b.x, floorY, b.z) + dir * b.radius
	view(
		`terraces{index}`,
		wall - dir * 70 + up * -30 + Vector3.new(-dir.Z, 0, dir.X) * 20,
		wall + up * -45,
		58,
		boxAround(wall, 80, World.deep.ventsFloorY - 10, floorY + 30),
		2
	)
end
for index, smoker in plan.smokers do
	local c = smoker.center
	local tall = smoker.spires[1].height
	local look = c + up * (tall * 0.45)
	view(
		`smoker{index}`,
		openView(c, look, tall * 0.7 + 40, tall * 0.35, smoker.radius + 8),
		look,
		58,
		boxAround(c, tall * 0.7 + 70, c.Y - 20, c.Y + tall + 20),
		2
	)
end
for index, outcrop in plan.outcrops do
	local c = outcrop.center
	view(
		`basalt{index}`,
		c + outcrop.down * (outcrop.radius + 34) + up * 22,
		c + up * 8,
		60,
		boxAround(c, 70, floorY - 20, floorY + 60),
		2
	)
end
-- A basin chimney's flanges up close: the tallest dressed one (two flanges) from a
-- fish's height beside it, and a short one (one flange) from over it
local tallest, shortest = nil, nil
for _, chimney in plan.chimneys do
	local p = chimney.position
	if math.abs((groundAt(p.X, p.Z)).Y - (p.Y + chimney.height)) > 12 then
		continue
	end
	if tallest == nil or chimney.height > tallest.height then
		tallest = chimney
	end
	if chimney.height < 55 and (shortest == nil or chimney.height > shortest.height) then
		shortest = chimney
	end
end
for name, chimney in { chimney = tallest, chimney2 = shortest } do
	local p, h, r = chimney.position, chimney.height, chimney.radius
	local high = name == "chimney2"
	local look = p + up * (h * (if high then 0.45 else 0.55))
	view(
		name,
		openView(p, look, r + (if high then 30 else 38), h * (if high then 0.95 else 0.5), r + 2),
		look,
		58,
		boxAround(p, r + 80, p.Y - 20, p.Y + h + 20),
		1.5
	)
end
-- A tube-worm forest up close (the first), else a clump
local wormsAt = nil
for _, name in { "TubeWormForest", "TubeWorms" } do
	for _, d in folder:GetDescendants() do
		if d.Name == name and wormsAt == nil then
			local sum, n = Vector3.new(0, 0, 0), 0
			for _, p in d:GetChildren() do
				if p.Name == "Tube" then
					sum = sum + p.CFrame.p
					n += 1
				end
			end
			if n > 0 then
				wormsAt = sum / n
			end
		end
	end
end
if wormsAt then
	local c = wormsAt
	view("worms", openView(c, c + up * 2, 24, 8, 8), c + up * 2, 55, boxAround(c, 90, c.Y - 20, c.Y + 70), 1.5)
end

dumpParts(root)
