-- The start screen's documentary shots, checked against the Terrain in the luau CLI
-- (run_start.sh concatenates the stubs, the modules and this). For every shot in
-- Config/Start it plans each candidate school's camera (Shared/StartShots.plan, the
-- same code the client runs) at a few moments, with rays against the Terrain's fill
-- ops (Shelf.luau and Cave.luau: what the server fills), after lifting the schools
-- over that Terrain the way the server does (Schools.settle). It prints:
--   R|shot|school|prey|t0|ok|variant|fails|distance|width|over  every plan tried (over:
--                                                             its height over the floor)
--   SUMMARY|shot|clear|tried|candidates|prey...               per shot
--   SHOT|id|biome|haze|fog|bounds|name|place                  the chosen plan, for the renders
--   CAM|id|k|position|look|fov|seconds                        its key frames (k = 0..KEYS-1)
--   FISH|id|k|position|look|length|height|color               its school's fish at each key frame
--   MARK|id|position                                          its landmark
--   PATH|id|position|clearance|s                              the camera every half second, and
--                                                             the open water round it (studs)
--   OP|{json}                                                 the Terrain's fill ops (cave_render.py's)
-- The preview's Random isn't Roblox's, so its schools, reef heads and basins sit
-- elsewhere than the game's: this checks the shots' logic against a world built the
-- same way, and the client checks the real one the same way before every shot.

local KEYS = 3
local TIMES = { 1000, 1750, 2600 } -- shared-clock moments each candidate is planned at
local MOST = START_MOST or 14 -- candidates tried per shot (run_start.sh: MOST=...)

-- ---------------------------------------------------------------------------
-- The Terrain's fill ops, indexed by 32-stud columns
-- ---------------------------------------------------------------------------
local ops = Shelf.ops()
for _, op in Cave.ops() do
	table.insert(ops, op)
end

local CELL = 32
type Shape = {
	order: number,
	solid: boolean,
	kind: string,
	c: Vector3,
	r: number,
	h: number,
	sx: number,
	sy: number,
	sz: number,
	right: Vector3,
	up: Vector3,
	look: Vector3,
	ymin: number,
	ymax: number,
}
local shapes: { Shape } = {}
local cells: { [number]: { Shape } } = {}
local function key(cx: number, cz: number): number
	return (cx + 500) * 1000 + (cz + 500)
end
for order, op in ops do
	local c = op.center
	local ext, yext
	local right, up, look = Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, -1)
	if op.cframe then
		right, up, look = op.cframe.RightVector, op.cframe.UpVector, op.cframe.LookVector
	end
	if op.kind == "ball" then
		ext, yext = op.radius, op.radius
	elseif op.kind == "block" then
		ext = math.sqrt(op.size.X ^ 2 + op.size.Y ^ 2 + op.size.Z ^ 2) / 2
		yext = ext
	else
		ext = math.sqrt(op.radius ^ 2 + (op.height / 2) ^ 2)
		yext = ext
	end
	local shape: Shape = {
		order = order,
		solid = op.material.Name ~= "Air",
		kind = op.kind,
		c = c,
		r = op.radius or 0,
		h = (op.height or 0) / 2,
		sx = if op.size then op.size.X / 2 else 0,
		sy = if op.size then op.size.Y / 2 else 0,
		sz = if op.size then op.size.Z / 2 else 0,
		right = right,
		up = up,
		look = look,
		ymin = c.Y - yext,
		ymax = c.Y + yext,
	}
	table.insert(shapes, shape)
	for cx = math.floor((c.X - ext) / CELL), math.floor((c.X + ext) / CELL) do
		for cz = math.floor((c.Z - ext) / CELL), math.floor((c.Z + ext) / CELL) do
			local k = key(cx, cz)
			local list = cells[k]
			if list == nil then
				list = {}
				cells[k] = list
			end
			table.insert(list, shape)
		end
	end
end

local function contains(s: Shape, x: number, y: number, z: number): boolean
	if y < s.ymin or y > s.ymax then
		return false
	end
	local dx, dy, dz = x - s.c.X, y - s.c.Y, z - s.c.Z
	if s.kind == "ball" then
		return dx * dx + dy * dy + dz * dz <= s.r * s.r
	end
	local lr = dx * s.right.X + dy * s.right.Y + dz * s.right.Z
	local lu = dx * s.up.X + dy * s.up.Y + dz * s.up.Z
	local ll = dx * s.look.X + dy * s.look.Y + dz * s.look.Z
	if s.kind == "block" then
		return math.abs(lr) <= s.sx and math.abs(lu) <= s.sy and math.abs(ll) <= s.sz
	end
	return math.abs(lu) <= s.h and lr * lr + ll * ll <= s.r * s.r
end

-- Whether a point is inside the Terrain (the last op over it decides, as Fill does)
local function solid(x: number, y: number, z: number): boolean
	local list = cells[key(math.floor(x / CELL), math.floor(z / CELL))]
	if list == nil then
		return false
	end
	for i = #list, 1, -1 do
		local s = list[i]
		if contains(s, x, y, z) then
			return s.solid
		end
	end
	return false
end

local RAY_STEP = 1
local casts = 0
local function cast(origin: Vector3, direction: Vector3): number?
	casts += 1
	local length = direction.Magnitude
	if length < 1e-6 then
		return nil
	end
	local d = direction / length
	local t = math.min(RAY_STEP, length)
	while t <= length do
		local p = origin + d * t
		if solid(p.X, p.Y, p.Z) then
			return t
		end
		if t >= length then
			break
		end
		t = math.min(t + RAY_STEP, length)
	end
	return nil
end

-- The ground's top in a column (for Schools.settle): the highest boundary of any op
-- over it with Terrain just under it
local function interval(s: Shape, x: number, z: number): (number?, number?)
	local dx, dz = x - s.c.X, z - s.c.Z
	if s.kind == "ball" then
		local q = s.r * s.r - dx * dx - dz * dz
		if q < 0 then
			return nil, nil
		end
		local h = math.sqrt(q)
		return s.c.Y - h, s.c.Y + h
	end
	-- The vertical line p(y) = (x, y, z): d = d0 + y * (0, 1, 0)
	local d0y = -s.c.Y
	local function along(axis: Vector3): (number, number)
		return dx * axis.X + d0y * axis.Y + dz * axis.Z, axis.Y
	end
	local lo, hi = -math.huge, math.huge
	local function slab(axis: Vector3, half: number): boolean
		local a, b = along(axis)
		if math.abs(b) < 1e-9 then
			return math.abs(a) <= half
		end
		local y1, y2 = (-half - a) / b, (half - a) / b
		if y1 > y2 then
			y1, y2 = y2, y1
		end
		lo, hi = math.max(lo, y1), math.min(hi, y2)
		return lo <= hi
	end
	if s.kind == "block" then
		if not (slab(s.right, s.sx) and slab(s.up, s.sy) and slab(s.look, s.sz)) then
			return nil, nil
		end
		return lo, hi
	end
	if not slab(s.up, s.h) then
		return nil, nil
	end
	-- Inside the radius: (a_r + y b_r)^2 + (a_l + y b_l)^2 <= r^2
	local ar, br = along(s.right)
	local al, bl = along(s.look)
	local A = br * br + bl * bl
	local B = 2 * (ar * br + al * bl)
	local C = ar * ar + al * al - s.r * s.r
	if A < 1e-9 then
		if C > 0 then
			return nil, nil
		end
		return lo, hi
	end
	local disc = B * B - 4 * A * C
	if disc < 0 then
		return nil, nil
	end
	local root = math.sqrt(disc)
	local y1, y2 = (-B - root) / (2 * A), (-B + root) / (2 * A)
	lo, hi = math.max(lo, y1), math.min(hi, y2)
	if lo > hi then
		return nil, nil
	end
	return lo, hi
end

local groundCache: { [number]: number } = {}
local wanted: { Vector3 } = {} -- only round the schools the shots can use (settle is slow here)
local function groundY(x: number, z: number): number
	local near = false
	for _, w in wanted do
		if math.abs(w.X - x) < 160 and math.abs(w.Z - z) < 160 then
			near = true
			break
		end
	end
	if not near then
		return -math.huge
	end
	local k = math.floor(x) * 100000 + math.floor(z)
	local known = groundCache[k]
	if known then
		return known
	end
	local list = cells[key(math.floor(x / CELL), math.floor(z / CELL))] or {}
	local tops: { number } = {}
	for _, s in list do
		local lo, hi = interval(s, x, z)
		if lo and hi then
			table.insert(tops, hi)
			table.insert(tops, lo)
		end
	end
	table.sort(tops, function(a, b)
		return a > b
	end)
	local top = Seafloor.y(x, z)
	for _, y in tops do
		if y < World.surfaceY and solid(x, y - 0.05, z) then
			top = y
			break
		end
	end
	groundCache[k] = top
	return top
end

-- The ops themselves, for the renders (the same JSON as cave_stub's dumpOps)
do
	local function v(x: Vector3): string
		return string.format("[%.3f,%.3f,%.3f]", x.X, x.Y, x.Z)
	end
	for _, op in ops do
		local cf = op.cframe
		print(
			string.format(
				'OP|{"kind":"%s","material":"%s","center":%s,"radius":%s,"height":%s,"size":%s,"axes":[%s]}',
				op.kind,
				op.material.Name,
				v(op.center),
				tostring(op.radius or "null"),
				tostring(op.height or "null"),
				if op.size then v(op.size) else "null",
				if cf
					then string.format("%s,%s,%s", v(cf.RightVector), v(cf.UpVector), v(cf.LookVector))
					else "null,null,null"
			)
		)
	end
end

-- A self-test of the rays: straight down onto the shelf's sand (y 0, ~50 under) and
-- out through open water (nothing within 30 of a point 200 over the deep floor)
do
	local down = cast(Vector3.new(320, 50, 40), Vector3.new(0, -120, 0))
	local open = cast(Vector3.new(0, -200, -1200), Vector3.new(30, 0, 0))
	print(
		string.format(
			"INFO|rays: down onto the shelf %s studs, open water %s",
			tostring(down),
			tostring(open)
		)
	)
	if down == nil or math.abs(down - 50) > 8 or open ~= nil then
		error("the Terrain rays don't work")
	end
end

-- ---------------------------------------------------------------------------
-- The shots
-- ---------------------------------------------------------------------------
local Start = Config.Start
local candidatesOf: { [number]: { number } } = {}
for index, shot in Start.shots do
	local list = StartShots.candidates(shot)
	-- Spread the ones tried over the list (its first prey's first)
	local picked: { number } = {}
	local step = math.max(1, #list / MOST)
	local i = 1
	while i <= #list and #picked < MOST do
		table.insert(picked, list[math.floor(i)])
		i += step
	end
	candidatesOf[index] = picked
	for _, school in picked do
		table.insert(wanted, Schools.list[school].center)
	end
end
local clock = os.clock()
Schools.settle(groundY)
print(string.format("INFO|lifted the schools in %.1f s", os.clock() - clock))

local function v3(v: Vector3): string
	return string.format("%.2f,%.2f,%.2f", v.X, v.Y, v.Z)
end

-- How much open water is round a point (studs, to 12): the shortest of 14 rays
local AROUND = {}
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
	table.insert(AROUND, Vector3.new(d[1], d[2], d[3]).Unit)
end
local function clearance(p: Vector3): number
	local least = 12
	for _, d in AROUND do
		local hit = cast(p, d * 12)
		if hit and hit < least then
			least = hit
		end
	end
	return least
end

-- The wreck shot's landmark is the nearest wreck, which the client finds once the area
-- has streamed in (WorldService places them with Roblox's Random, which the preview
-- doesn't have): here a stand-in wreck lies on the floor 110 studs off the school's
-- middle, 40 degrees off the way it swims, and the render draws a hull there
local function wreckFor(shot: any, school: number): Vector3?
	if shot.landmark ~= "wreck" then
		return nil
	end
	local s = Schools.list[school]
	local heading = Schools.schoolFrame(school, 0).LookVector
	local flatHeading = Vector3.new(heading.X, 0, heading.Z)
	flatHeading = if flatHeading.Magnitude > 1e-3 then flatHeading.Unit else Vector3.new(1, 0, 0)
	local turned = CFrame.Angles(0, math.rad(40), 0):VectorToWorldSpace(flatHeading)
	local at = s.center + turned * 110
	return Vector3.new(at.X, Seafloor.y(at.X, at.Z) + 8, at.Z)
end

local total = { clear = 0, tried = 0 }
for index, shot in Start.shots do
	local picked = candidatesOf[index]
	local all = StartShots.candidates(shot)
	local clear, tried = 0, 0
	local chosen: any = nil
	for n, school in picked do
		for _, t0 in TIMES do
			tried += 1
			local side = if (n + t0) % 2 == 0 then 1 else -1
			local plan, best = StartShots.plan(index, school, t0, cast, side, wreckFor(shot, school))
			local shown = plan or best
			print(
				string.format(
					"R|%s|%d|%s|%d|%s|%d|%d|%.1f|%.1f|%.0f",
					shot.id,
					school,
					Schools.list[school].prey,
					t0,
					if plan then "ok" else "no",
					if shown then shown.variant else 0,
					if shown then shown.fails else -1,
					if shown then shown.distance else 0,
					StartShots.width(school),
					select(2, StartShots.groundNear(school))
				)
			)
			if plan then
				clear += 1
				if chosen == nil then
					chosen = plan
				end
			end
		end
	end
	total.clear += clear
	total.tried += tried
	local preyCounts: { [string]: number } = {}
	for _, school in all do
		local id = Schools.list[school].prey
		preyCounts[id] = (preyCounts[id] or 0) + 1
	end
	local counts: { string } = {}
	for _, id in shot.prey do
		table.insert(counts, `{id} {preyCounts[id] or 0}`)
	end
	print(string.format("SUMMARY|%s|%d|%d|%d|%s", shot.id, clear, tried, #all, table.concat(counts, ", ")))
	-- The schools the client picks from (StartController pickSchool: the three gentlest
	-- of its first prey, or of those near its temple), at every moment tried
	do
		local picks: { number } = {}
		local first: string? = nil
		for _, school in all do
			local group = if shot.landmark == "temple" then "temple" else Schools.list[school].prey
			first = first or group
			if group == first and #picks < 3 then
				table.insert(picks, school)
			end
		end
		local good, asked = 0, 0
		for n, school in picks do
			for _, t0 in TIMES do
				asked += 1
				local side = if (n + t0) % 2 == 0 then 1 else -1
				if StartShots.plan(index, school, t0, cast, side, wreckFor(shot, school)) then
					good += 1
				end
			end
		end
		local ids: { string } = {}
		for _, school in picks do
			table.insert(ids, tostring(school))
		end
		print(string.format("PICKS|%s|%d|%d|%s", shot.id, good, asked, table.concat(ids, " ")))
		-- What stands behind the school in these shots: the first Terrain along the
		-- camera's line past the subject, by where it is (the drop-off's cliff, the
		-- Vents' basins, the Trench's canyon, the shelf's floor, the deep floor)
		local seen: { [string]: number } = {}
		for n, school in picks do
			local plan = StartShots.plan(
				index,
				school,
				TIMES[1],
				cast,
				if n % 2 == 0 then 1 else -1,
				wreckFor(shot, school)
			)
			if plan == nil then
				continue
			end
			for k = 0, 4 do
				local frame = StartShots.view(plan, plan.t0 + plan.seconds * k / 4)
				local hit = cast(frame.Position, frame.LookVector * 600)
				local what = "open water"
				if hit then
					local at = frame.Position + frame.LookVector * hit
					local r = Seafloor.polar(at.X, at.Z)
					local basin = false
					for _, b in Seafloor.ventBasins() do
						if math.sqrt((b.x - at.X) ^ 2 + (b.z - at.Z) ^ 2) < b.radius + 40 then
							basin = true
						end
					end
					if Seafloor.inTrench(at.X, at.Z, 20) then
						what = "the Trench's canyon"
					elseif r < World.shelf.radius - 10 and at.Y > World.seabedY - 40 then
						what = if r < 330 then "the hub's seamount" else "the shelf's floor"
					elseif
						r < World.shelf.radius + World.shelf.edge + 40
						and at.Y < World.seabedY - 5
						and at.Y > World.deep.floorY + 20
					then
						what = "the drop-off's cliff"
					elseif basin then
						what = "a Vents basin"
					else
						what = "the deep floor"
					end
				end
				seen[what] = (seen[what] or 0) + 1
			end
		end
		local parts: { string } = {}
		for what, count in seen do
			table.insert(parts, `{what} {count}`)
		end
		table.sort(parts)
		print(string.format("BACKDROP|%s|%s", shot.id, table.concat(parts, ", ")))
	end
	local plan = chosen
	if plan == nil then
		continue
	end
	local biome = Config.Biomes.byId[shot.biome]
	local water = biome.water
	local name, place = StartShots.caption(shot, plan.school)
	-- The box the render voxelizes: round the camera's path and the subject
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = Vector3.new(-math.huge, -math.huge, -math.huge)
	local function grow(p: Vector3)
		lo = Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
		hi = Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
	end
	local s = 0
	local tightest = math.huge
	while s <= plan.span + 1e-6 do
		local frame, subject = StartShots.view(plan, plan.t0 + s)
		grow(frame.Position)
		grow(subject)
		local room = clearance(frame.Position)
		tightest = math.min(tightest, room)
		print(string.format("PATH|%s|%s|%.1f|%.1f", shot.id, v3(frame.Position), room, s))
		s += 0.5
	end
	if plan.landmark then
		grow(plan.landmark :: Vector3)
		print(string.format("MARK|%s|%s", shot.id, v3(plan.landmark :: Vector3)))
	end
	-- How the school sits in the picture over the shot (16:9, between the letterbox
	-- bars): its nearest fish to the lens, the least share of it in the picture, and
	-- how big its fish are (their length against the picture's height)
	do
		local school = Schools.list[plan.school]
		local closest, least, smallest, biggest = math.huge, 1, math.huge, 0
		local tanUp = math.tan(math.rad(plan.fov) / 2)
		local visible = 1 - 2 * Start.timing.letterbox
		local u = 0
		while u <= plan.seconds + 1e-6 do
			local t = plan.t0 + u
			local frame = StartShots.view(plan, t)
			local schoolFrame = Schools.schoolFrame(plan.school, t)
			local shown, size, counted = 0, 0, 0
			for i = school.first, school.first + school.count - 1 do
				local away = Schools.fishFrame(i, schoolFrame, t).Position - frame.Position
				closest = math.min(closest, away.Magnitude)
				local depth = away:Dot(frame.LookVector)
				if depth > 0 then
					local y = away:Dot(frame.UpVector) / (depth * tanUp)
					local x = away:Dot(frame.RightVector) / (depth * tanUp * 16 / 9)
					if math.abs(y) <= visible and math.abs(x) <= 1 then
						shown += 1
						size += Schools.fish[i].length / (2 * depth * tanUp * visible)
						counted += 1
					end
				end
			end
			least = math.min(least, shown / school.count)
			if counted > 0 then
				smallest = math.min(smallest, size / counted)
				biggest = math.max(biggest, size / counted)
			end
			u += 0.5
		end
		print(
			string.format(
				"FRAME|%s|%.1f|%.1f|%.0f|%d|%.1f|%.1f",
				shot.id,
				closest,
				plan.gap,
				least * 100,
				school.count,
				smallest * 100,
				biggest * 100
			)
		)
	end
	local reach = 230
	local floorY = Seafloor.y((lo.X + hi.X) / 2, (lo.Z + hi.Z) / 2)
	print(
		string.format(
			"SHOT|%s|%s|%s|%.3f|%.0f,%.0f,%.0f,%.0f,%.0f,%.0f|%s|%s|%d|%.1f|%d",
			shot.id,
			shot.biome,
			v3(Vector3.new(water.haze.R, water.haze.G, water.haze.B)),
			water.density,
			lo.X - reach,
			hi.X + reach,
			math.min(lo.Y, floorY) - 60,
			math.min(hi.Y + 90, World.surfaceY),
			lo.Z - reach,
			hi.Z + reach,
			name,
			place,
			plan.variant,
			tightest,
			plan.school
		)
	)
	for k = 0, KEYS - 1 do
		local t = plan.t0 + plan.seconds * k / (KEYS - 1)
		local frame, _, fov = StartShots.view(plan, t)
		print(
			string.format(
				"CAM|%s|%d|%s|%s|%.1f|%.2f",
				shot.id,
				k,
				v3(frame.Position),
				v3(frame.Position + frame.LookVector * 10),
				fov,
				t - plan.t0
			)
		)
		local school = Schools.list[plan.school]
		local schoolFrame = Schools.schoolFrame(plan.school, t)
		local prey = Config.Prey.byId[school.prey]
		for i = school.first, school.first + school.count - 1 do
			local fish = Schools.fish[i]
			local f = Schools.fishFrame(i, schoolFrame, t)
			print(
				string.format(
					"FISH|%s|%d|%s|%s|%.2f|%.2f|%s",
					shot.id,
					k,
					v3(f.Position),
					v3(f.Position + f.LookVector),
					fish.length,
					fish.length * prey.slim,
					v3(Vector3.new(prey.back.R, prey.back.G, prey.back.B))
				)
			)
		end
	end
end
-- The checks have teeth: a chosen trench shot pushed far out into the canyon's walls
-- must fail them
for index, shot in Start.shots do
	if shot.id ~= "trench" then
		continue
	end
	for _, school in candidatesOf[index] do
		local plan = StartShots.plan(index, school, TIMES[1], cast, 1)
		if plan then
			local far = table.clone(plan)
			far.distance *= 9
			far.floor = 0
			local fails = StartShots.check(far, cast)
			print(string.format("INFO|a trench shot pushed 9x out fails %d checks (must be > 0)", fails))
			if fails == 0 then
				error("the shots' checks let a camera inside the canyon's walls through")
			end
			break
		end
	end
end

print(
	string.format(
		"INFO|%d of %d plans clear, %d rays, %.1f s",
		total.clear,
		total.tried,
		casts,
		os.clock() - clock
	)
)
