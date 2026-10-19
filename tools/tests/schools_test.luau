-- Schools.settle (run_schools.sh): over a floor strewn with rocks, reef heads and
-- ridges, no prey fish swims into the ground once the schools are lifted, the lifts
-- survive the trip to a client (the string), and the swallow reach widened modestly.
local rbx = require("./sim_rbx")
local Vector3 = rbx.Vector3
local Config = require("./Config")
local Seafloor = require("./Seafloor")
local Schools = require("./Schools")
local Size = require("./Size")

local World = Config.World
local failures = 0
local function expect(ok: boolean, what: string)
	if not ok then
		failures += 1
		if failures <= 12 then
			print("FAIL: " .. what)
		end
	end
end

-- A strewn floor: round rocks (4–16 studs across the top, up to 40 tall) and long
-- ridges over the shelf, a few big knolls on the deep floor. Exact heights here; the
-- game's Ground.y samples one column per 4-stud cell, as settle is given below.
local rng = rbx.Random.new(4242)
type Rock = { x: number, z: number, r: number, h: number }
local rocks: { Rock } = {}
for _ = 1, 2600 do
	local angle = rng:NextNumber(0, 2 * math.pi)
	local d = rng:NextNumber(150, 840)
	table.insert(rocks, {
		x = math.cos(angle) * d,
		z = math.sin(angle) * d,
		r = rng:NextNumber(4, 16),
		h = rng:NextNumber(5, 40),
	})
end
for _ = 1, 160 do
	local angle = rng:NextNumber(0, 2 * math.pi)
	local d = rng:NextNumber(950, 1450)
	table.insert(rocks, {
		x = math.cos(angle) * d,
		z = math.sin(angle) * d,
		r = rng:NextNumber(10, 30),
		h = rng:NextNumber(20, 70),
	})
end
local BIN = 32
local bins: { [number]: { Rock } } = {}
local function binKey(bx: number, bz: number): number
	return (bx + 1000) * 4096 + (bz + 1000)
end
for _, rock in rocks do
	for bx = math.floor((rock.x - rock.r) / BIN), math.floor((rock.x + rock.r) / BIN) do
		for bz = math.floor((rock.z - rock.r) / BIN), math.floor((rock.z + rock.r) / BIN) do
			local key = binKey(bx, bz)
			bins[key] = bins[key] or {}
			table.insert(bins[key], rock)
		end
	end
end
local function exact(x: number, z: number): number
	local top = Seafloor.y(x, z)
	local near = bins[binKey(math.floor(x / BIN), math.floor(z / BIN))]
	if near then
		for _, rock in near do
			local dx, dz = x - rock.x, z - rock.z
			if dx * dx + dz * dz <= rock.r * rock.r then
				top = math.max(top, Seafloor.y(rock.x, rock.z) + rock.h)
			end
		end
	end
	return top
end
-- Shared/Ground.y: the column at the middle of a 4-stud cell
local calls, cells, seen = 0, 0, {}
local function groundY(x: number, z: number): number
	calls += 1
	local cx, cz = math.floor(x / 4), math.floor(z / 4)
	local key = (cx + 2000) * 4096 + (cz + 2000)
	if not seen[key] then
		seen[key] = true
		cells += 1 -- (Ground.y caches each cell: one raycast each)
	end
	return exact((cx + 0.5) * 4, (cz + 0.5) * 4)
end

-- How many fish samples are in the ground (each fish's middle, nose and tail)
local function sweep(label: string, strict: boolean): number
	local inside, samples, worst = 0, 0, 0
	for t = 0, 130, 0.43 do
		for schoolIndex, school in Schools.list do
			local frame = Schools.schoolFrame(schoolIndex, t)
			for index = school.first, school.first + school.count - 1 do
				local f = Schools.fish[index]
				local at = Schools.fishFrame(index, frame, t)
				local half = at.LookVector * f.length * 0.5
				for _, point in { at.Position, at.Position + half, at.Position - half } do
					samples += 1
					local under = exact(point.X, point.Z) - point.Y
					if under > 0 then
						inside += 1
						worst = math.max(worst, under)
						if strict then
							expect(
								false,
								`{label}: a {f.prey} of school {schoolIndex} is {string.format("%.1f", under)} studs into the ground at t={t}`
							)
						end
					end
					expect(point.Y < World.surfaceY, `{label}: a {f.prey} above the surface`)
				end
			end
		end
	end
	print(
		string.format(
			"%s: %d of %d fish samples in the ground (deepest %.1f studs)",
			label,
			inside,
			samples,
			worst
		)
	)
	return inside
end

local before = sweep("unlifted", false)
local started = os.clock()
local encoded = Schools.settle(groundY)
print(
	string.format(
		"settle: %d ground samples (%d cells: raycasts in the game), %.0f ms in the CLI, %d characters to send",
		calls,
		cells,
		(os.clock() - started) * 1000,
		#encoded
	)
)
local lifted, most = 0, 0
for entry in string.gmatch(encoded, "[^;]+") do
	lifted += 1
	for value in string.gmatch(string.match(entry, ":(.*)$") or "", "[^,]+") do
		most = math.max(most, tonumber(value) or 0)
	end
end
print(string.format("lifted %d of %d schools, the highest lift %d studs", lifted, #Schools.list, most))
local after = sweep("lifted", true)
expect(before > 0, "the strewn floor should have caught some fish before the lift")
expect(after == 0, "no fish in the ground after the lift")

-- A client loads the same string and draws every fish where the server checks it
local probe: { Vector3 } = {}
for index = 1, Schools.COUNT, 7 do
	table.insert(probe, Schools.position(index, 123.4))
end
Schools.load(nil)
Schools.load(encoded)
local k = 0
for index = 1, Schools.COUNT, 7 do
	k += 1
	expect((Schools.position(index, 123.4) - probe[k]).Magnitude < 1e-9, `fish {index} moved after a reload`)
end
Schools.load("")
expect((Schools.position(1, 5) - Schools.position(1, 5)).Magnitude == 0, "loads nothing")

-- The swallow reach: wider, modestly
for _, case in { { 2, "Minnow" }, { 4, "Sardine" }, { 8, "Wrasse" }, { 12, "Snapper" } } do
	local length, preyId = case[1], case[2]
	local prey = Config.Prey.byId[preyId]
	local radius = Size.length(prey.mass) * (prey.look or 1) * 0.3
	local old = Size.reach(length) + radius
	local reach = Schools.eatReach(length, radius)
	local furthest = reach * Schools.EAT_PULLED
	print(
		string.format(
			"swallow: a %d-stud fish eats a %s from %.2f studs of the mouth (was %.2f), drawn in from %.2f",
			length,
			preyId,
			furthest,
			old,
			reach * Config.Prey.eat.pull
		)
	)
	expect(furthest > old * 1.2 and furthest < old * 1.8, `{preyId}: the swallow reach should grow modestly`)
end

if failures > 0 then
	print(`{failures} failure(s)`)
	error("schools test failed")
end
print("schools: OK")
