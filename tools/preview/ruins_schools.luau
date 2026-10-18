-- run_ruins.sh SCHOOLS=1 (after ruins_build.luau): whether Shared/Schools' lift
-- (`settle`, over Shared/Ground's 4-stud cells) carries prey schools over the
-- ruins' stones. Schools are laid through the city (down the avenue and through the
-- gateway, round the temple's peristyle, over the theatre, in the sunken courtyard,
-- along the colonnade and over the houses) on top of the world's own; the ground is
-- the top of the Terrain (the fill ops) and of every part that collides in each
-- column, as Ground.y's ray sees it; then every fish (its middle, nose and tail) is
-- sampled round its loop for 130 s: none may be inside a stone. K| lines.
local solidParts = {}
for _, d in folder:GetDescendants() do
	if d.IsPart and d.CanCollide ~= false then
		table.insert(solidParts, d)
	end
end
local BIN = 16
local bins = {}
local function binKey(bx, bz)
	return (bx + 4000) * 8192 + (bz + 4000)
end
for _, part in solidParts do
	local h = part.Size / 2
	local reach = math.sqrt(h.X * h.X + h.Y * h.Y + h.Z * h.Z)
	local p = part.CFrame.p
	for bx = math.floor((p.X - reach) / BIN), math.floor((p.X + reach) / BIN) do
		for bz = math.floor((p.Z - reach) / BIN), math.floor((p.Z + reach) / BIN) do
			local key = binKey(bx, bz)
			bins[key] = bins[key] or {}
			table.insert(bins[key], part)
		end
	end
end
-- The vertical line through (x, z) against a part's box: its top, or nil
local function lineTop(part, x, z)
	local cf = part.CFrame
	local o = cf:PointToObjectSpace(Vector3.new(x, 0, z))
	local d = cf:VectorToObjectSpace(Vector3.new(0, 1, 0))
	local half = part.Size / 2
	local lo, hi = -math.huge, math.huge
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
	return if lo <= hi then hi else nil
end
local function exactTop(x, z)
	local top = groundAt(x, z).Y
	local near = bins[binKey(math.floor(x / BIN), math.floor(z / BIN))]
	if near then
		for _, part in near do
			local t = lineTop(part, x, z)
			if t and t > top then
				top = t
			end
		end
	end
	return top
end
local function inside(point)
	local near = bins[binKey(math.floor(point.X / BIN), math.floor(point.Z / BIN))]
	if near then
		for _, part in near do
			local q = part.CFrame:PointToObjectSpace(point)
			local h = part.Size / 2
			if math.abs(q.X) < h.X and math.abs(q.Y) < h.Y and math.abs(q.Z) < h.Z then
				return part
			end
		end
	end
	return nil
end
-- Shared/Ground.y: the middle of a 4-stud cell, never under the nominal floor - 40
local function groundY(x, z)
	local cx, cz = math.floor(x / 4), math.floor(z / 4)
	local mx, mz = (cx + 0.5) * 4, (cz + 0.5) * 4
	return math.max(exactTop(mx, mz), Seafloor.y(mx, mz) - 40)
end

-- Schools through the city (its frame: x along the avenue, z across; y over the floor)
local RuinsLayout = Config.Ruins
local outward = Vector3.new(math.cos(math.rad(RuinsLayout.angle)), 0, math.sin(math.rad(RuinsLayout.angle)))
local cityFrame = CFrame.fromMatrix(
	outward * RuinsLayout.radius + Vector3.new(0, floorY, 0),
	outward,
	Vector3.new(0, 1, 0),
	outward:Cross(Vector3.new(0, 1, 0))
)
local template = nil
for _, f in Schools.fish do
	if f.prey == "Sardine" then
		template = f
		break
	end
end
template = template or Schools.fish[1]
local laid = {
	{ "avenue", -170, 0, 8, 60, 0.3 },
	{ "gateway", -245, 0, 10, 26, 1 },
	{ "peristyle", 0, 0, 26, 44, 0.8 },
	{ "temple front", -70, 0, 12, 30, 1 },
	{ "theatre", -140, 152, 6, 34, 1 },
	{ "courtyard", -118, -146, -8, 22, 0.8 },
	{ "colonnade", 95, 0, 10, 40, 0.25 },
	{ "house", 152, 70, 8, 22, 1 },
	{ "quarter", 170, -76, 6, 20, 1 },
	{ "head", -94, 36, 4, 18, 1 },
}
local first = #Schools.list + 1
local rng = Random.new(77)
for _, spec in laid do
	local center = cityFrame * Vector3.new(spec[2], 0, spec[3])
	center = Vector3.new(center.X, floorY + spec[4], center.Z)
	local school = {
		prey = template.prey,
		center = center,
		radius = spec[5],
		ellipse = spec[6],
		height = 4,
		angularSpeed = 9 / spec[5],
		phase = rng:NextNumber(0, 6.28),
		spread = 3,
		first = #Schools.fish + 1,
		count = 8,
		label = spec[1],
	}
	table.insert(Schools.list, school)
	for _ = 1, 8 do
		table.insert(Schools.fish, {
			school = #Schools.list,
			prey = template.prey,
			offset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.45, 0.45), rng:NextNumber(-1, 1)) * 3,
			phase = rng:NextNumber(0, 6.28),
			length = template.length,
			radius = template.radius,
			size = 1,
			mass = template.mass,
		})
	end
end

local function sweep(label)
	local count, worst, report = 0, nil, nil
	for t = 0, 130, 0.43 do
		for index = first, #Schools.list do
			local school = Schools.list[index]
			local frame = Schools.schoolFrame(index, t)
			for i = school.first, school.first + school.count - 1 do
				local f = Schools.fish[i]
				local at = Schools.fishFrame(i, frame, t)
				local half = at.LookVector * f.length * 0.5
				for _, point in { at.Position, at.Position + half, at.Position - half } do
					local hit = inside(point)
					if hit then
						count += 1
						report = report or string.format("%s: a fish inside %s (%s)", school.label, hit.Name, hit.Parent and hit.Parent.Name or "?")
					end
				end
			end
		end
	end
	print(string.format("K|%s: %d fish samples inside stone%s", label, count, if report then " (" .. report .. ")" else ""))
	return count
end
sweep("unlifted")
Schools.settle(groundY)
local lifted = sweep("lifted")
for index = first, #Schools.list do
	local school = Schools.list[index]
	local most = 0
	for k = 0, 63 do
		local a = k / 64 * 2 * math.pi
		local frame = Schools.schoolFrame(index, (a - school.phase) / school.angularSpeed)
		most = math.max(most, frame.Position.Y - (school.center.Y + math.sin(2 * a + school.phase) * school.height))
	end
	print(string.format("K|%s school: lifted up to %.0f studs", school.label, most))
end
print(if lifted == 0 then "K|schools: none inside the ruins' stones" else "K|schools: FAIL")
