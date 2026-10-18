--!strict
-- Measures the swim's feel in the plain luau CLI (run_swim.sh): the old handling
-- (2026-10-16) against the current Config/Tuning `swim`, with the same equations
-- as SwimController's step (speed, turn, brake, stop, wall glide) and Input's
-- stick shaping. It prints a table of numbers and fails on a broken rule (a speed
-- past the top, a glide that adds speed, a pitch map that isn't monotonic).
-- Keep the equations here in step with SwimController and Input.
local Tuning = require("./Tuning")
local Size = require("./Size")

local swim = Tuning.swim
local cam = Tuning.camera
local DT = 1 / 60

local failures = 0
local function check(ok: boolean, message: string)
	if not ok then
		failures += 1
		print("FAIL: " .. message)
	end
end

local function v(x: number, y: number, z: number): vector
	return vector.create(x, y, z)
end
local ZERO = v(0, 0, 0)
local UP = v(0, 1, 0)

local function mag(a: vector): number
	return vector.magnitude(a)
end
local function unit(a: vector): vector
	return vector.normalize(a)
end
local function dot(a: vector, b: vector): number
	return vector.dot(a, b)
end
local function alpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end
local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Rotates `from` toward `to` by at most `maxAngle` (Rodrigues about their cross)
local function rotateToward(from: vector, to: vector, maxAngle: number, hint: vector): vector
	local angle = math.acos(math.clamp(dot(from, to), -1, 1))
	if angle <= maxAngle or angle < 1e-4 then
		return to
	end
	local axis = vector.cross(from, to)
	if mag(axis) < 1e-5 then
		axis = vector.cross(from, hint)
		if mag(axis) < 1e-5 then
			axis = UP
		end
	end
	local k = unit(axis)
	local c, s = math.cos(maxAngle), math.sin(maxAngle)
	return unit(from * c + vector.cross(k, from) * s + k * dot(k, from) * (1 - c))
end

type Model = {
	name: string,
	accel: number,
	decel: number,
	drag: number,
	stopBrake: number,
	pivotTurn: number,
	cruiseTurn: number,
	pivotBelow: number,
	carveAbove: number,
	stepTurn: boolean, -- the old hard step from pivot to cruise at 25% of top speed
	turnSettle: number, -- 0: none
	turnBrake: number, -- 1: none
	brakeFrom: number,
	brakeTo: number,
	levelZone: number,
	levelFull: number, -- 0: the old linear ease
	glide: boolean,
	bigTurn: number,
}

local OLD: Model = {
	name = "old",
	accel = 3.1,
	decel = 3.1,
	drag = 2.3,
	stopBrake = 0,
	pivotTurn = 2.6,
	cruiseTurn = 1.2,
	pivotBelow = 0.25,
	carveAbove = 0.25,
	stepTurn = true,
	turnSettle = 0,
	turnBrake = 1,
	brakeFrom = 0,
	brakeTo = 1,
	levelZone = math.rad(12),
	levelFull = 0,
	glide = false,
	bigTurn = 0,
}

local NEW: Model = {
	name = "new",
	accel = swim.accel,
	decel = swim.decel,
	drag = swim.drag,
	stopBrake = swim.stopBrake,
	pivotTurn = swim.pivotTurn,
	cruiseTurn = swim.cruiseTurn,
	pivotBelow = swim.pivotBelow,
	carveAbove = swim.carveAbove,
	stepTurn = false,
	turnSettle = swim.turnSettle,
	turnBrake = swim.turnBrake,
	brakeFrom = swim.brakeFrom,
	brakeTo = swim.brakeTo,
	levelZone = swim.levelZone,
	levelFull = swim.levelFull,
	glide = true,
	bigTurn = swim.bigTurn,
}

-- The swim pitch for an aim pitch (SwimController `swimPitch`)
local function swimPitch(m: Model, aim: number): number
	if m.levelFull == 0 then
		local over = math.max(0, math.abs(aim) - m.levelZone)
		return math.sign(aim) * over * (math.pi / 2) / (math.pi / 2 - m.levelZone)
	end
	return aim * smoothstep((math.abs(aim) - m.levelZone) / (m.levelFull - m.levelZone))
end

type Fish = {
	pos: vector,
	vel: vector,
	heading: vector,
	top: number,
	turn: number,
	radius: number,
	length: number,
}

local function fish(level: number): Fish
	local length = Size.length(Size.massForLevel(level))
	return {
		pos = ZERO,
		vel = ZERO,
		heading = v(1, 0, 0),
		top = Size.topSpeed(length),
		turn = Size.turnRate(length),
		radius = Size.colliderDiameter(length) / 2,
		length = length,
	}
end

-- A plane wall for the glide test: points with x > wallX are rock
type Wall = { x: number }?

-- The wall glide (SwimController `glide`) against a plane: the approach speed is
-- capped at the gap over `wallEase` (never under `wallContact` × top), and at
-- contact the speed into the rock goes
local function glide(f: Fish, velocity: vector, wall: Wall): vector
	if wall == nil then
		return velocity
	end
	local speed = mag(velocity)
	if speed < 0.05 then
		return velocity
	end
	local normal = v(-1, 0, 0)
	local into = -dot(velocity, normal)
	if into <= 0 then
		return velocity
	end
	-- What the probe's cast would see along the velocity: the distance to contact
	local gapNormal = wall.x - f.pos.x - f.radius
	local reach = f.radius * 0.1 + speed * (DT + swim.wallEase) + 0.25
	local along = gapNormal * speed / into
	if along > reach then
		return velocity
	end
	local cap = if gapNormal <= swim.wallSkin
		then 0
		else math.max(gapNormal / swim.wallEase, swim.wallContact * f.top)
	if into > cap then
		velocity -= normal * -(into - cap)
	end
	return velocity
end

-- One frame of swimming toward `want` with `intent`, as SwimController's step
local function step(m: Model, f: Fish, want: vector, intent: number, wall: Wall)
	local speed = mag(f.vel)
	local top = f.top
	local velocity = f.vel
	local direction: vector? = nil
	if intent > 0.05 then
		local current = if speed > top * 0.12 then unit(velocity) else f.heading
		local angle = math.acos(math.clamp(dot(current, want), -1, 1))
		local share = math.min(speed / top, 1)
		local turnScale
		if m.stepTurn then
			turnScale = if share < m.pivotBelow then m.pivotTurn else m.cruiseTurn
		else
			local carve = smoothstep((share - m.pivotBelow) / (m.carveAbove - m.pivotBelow))
			turnScale = m.pivotTurn + (m.cruiseTurn - m.pivotTurn) * carve
		end
		local maxStep = f.turn * (Size.raw(f.length) / f.length) ^ m.bigTurn * turnScale * DT
		if m.turnSettle > 0 then
			maxStep = math.min(maxStep, angle * alpha(m.turnSettle, DT))
		end
		direction = rotateToward(current, want, maxStep, UP)
		local brake = 1 - (1 - m.turnBrake) * smoothstep((angle - m.brakeFrom) / (m.brakeTo - m.brakeFrom))
		local target = top * intent * brake
		local rate = if target < speed and speed <= top then m.decel else m.accel
		local newSpeed = speed + (target - speed) * alpha(rate, DT)
		velocity = (direction :: vector) * newSpeed
	elseif m.stopBrake > 0 then
		local s = speed * math.exp(-m.drag * DT) - m.stopBrake * top * DT
		velocity = if s > 0 then unit(velocity) * s else ZERO
	else
		velocity *= math.exp(-m.drag * DT)
	end
	local actual = velocity
	if m.glide then
		velocity = glide(f, velocity, wall)
		actual = velocity
	elseif wall then
		-- The old fish: physics stops the ball at the wall, the swim never hears of it
		local touching = f.pos.x + f.radius >= wall.x - 1e-3
		if touching and actual.x > 0 then
			actual = v(0, actual.y, actual.z)
		end
	end
	f.vel = velocity
	check(mag(velocity) <= top * 1.0001, `{m.name}: speed {mag(velocity)} past top {top}`)
	if mag(velocity) > top * 0.08 and (intent > 0.05 or dot(velocity, f.heading) > 0) then
		f.heading = unit(velocity)
	elseif m.glide and direction then
		-- Slow or blocked, the new fish still pivots toward the aim on the spot
		f.heading = direction
	end
	f.pos += actual * DT
	if wall and f.pos.x + f.radius > wall.x then
		f.pos = v(wall.x - f.radius, f.pos.y, f.pos.z)
	end
end

local function fmt(n: number, places: number?): string
	return string.format("%." .. tostring(places or 2) .. "f", n)
end

local LEVELS = { 1, 20, 40, 60, 100 }

print("== Fish sizes ==")
for _, level in LEVELS do
	local f = fish(level)
	print(
		`LV {level}: length {fmt(f.length, 1)}, top {fmt(f.top, 1)} studs/s, turn {fmt(f.turn)} rad/s, collider r {fmt(
			f.radius
		)}`
	)
end

print("\n== Let go at full speed: time to a stop (< 1 stud/s) and the coast ==")
for _, level in LEVELS do
	local line = `LV {level}:`
	for _, m in { OLD, NEW } do
		local f = fish(level)
		f.vel = v(f.top, 0, 0)
		local t, still = 0, nil :: number?
		while t < 6 do
			step(m, f, v(1, 0, 0), 0, nil)
			t += DT
			if still == nil and mag(f.vel) < 1 then
				still = t
			end
		end
		line ..= `  {m.name} {fmt(still or 6)} s, {fmt(f.pos.x, 1)} studs ({fmt(f.pos.x / f.length, 1)} lengths)`
	end
	print(line)
end

print("\n== Full speed, then the aim flicks round (U-turn 180°, turn 90°) ==")
-- `carries on`: how far the fish keeps going the old way (+x) before it comes round
for _, turnDeg in { 180, 90 } do
	for _, level in LEVELS do
		local line = `{turnDeg}° LV {level}:`
		for _, m in { OLD, NEW } do
			local f = fish(level)
			f.vel = v(f.top, 0, 0)
			local a = math.rad(turnDeg)
			-- (a hair off exactly behind, the way a mouse flick lands)
			local want = unit(v(math.cos(a), 0, math.sin(a) + (if turnDeg == 180 then 0.02 else 0)))
			local t, done = 0, nil :: number?
			local carry = 0
			local minSpeed = f.top
			while t < 8 do
				step(m, f, want, 1, nil)
				t += DT
				carry = math.max(carry, f.pos.x)
				minSpeed = math.min(minSpeed, mag(f.vel))
				if done == nil and dot(f.heading, want) > math.cos(math.rad(5)) then
					done = t
				end
			end
			line ..= `  {m.name}: {fmt(done or 8)} s, carries on {fmt(carry, 1)} studs ({fmt(
				carry / f.length,
				1
			)} L), slows to {fmt(minSpeed / f.top * 100, 0)}%`
		end
		print(line)
	end
end

print("\n== Small aim corrections at full speed (2°, 10°): time to settle within 0.5° ==")
for _, deg in { 2, 10 } do
	local line = `{deg}° LV 20:`
	for _, m in { OLD, NEW } do
		local f = fish(20)
		f.vel = v(f.top, 0, 0)
		local a = math.rad(deg)
		local want = v(math.cos(a), 0, math.sin(a))
		local t, done = 0, nil :: number?
		local lastRate, maxJerk = 0, 0
		local prev = f.heading
		while t < 2 do
			step(m, f, want, 1, nil)
			t += DT
			local rate = math.acos(math.clamp(dot(prev, f.heading), -1, 1)) / DT
			maxJerk = math.max(maxJerk, math.abs(rate - lastRate))
			lastRate, prev = rate, f.heading
			if done == nil and dot(f.heading, want) > math.cos(math.rad(0.5)) then
				done = t
			end
		end
		line ..= `  {m.name}: {fmt(done or 2)} s, biggest one-frame change in turn rate {fmt(maxJerk)} rad/s`
	end
	print(line)
end

print("\n== Aim pitch → swim pitch (degrees) ==")
local last = -math.huge
local row = "aim:  "
local oldRow = "old:  "
local newRow = "new:  "
for _, deg in { 0, 5, 8, 10, 12, 15, 20, 25, 30, 45, 60, 80 } do
	row ..= string.format("%6d", deg)
	oldRow ..= string.format("%6.1f", math.deg(swimPitch(OLD, math.rad(deg))))
	newRow ..= string.format("%6.1f", math.deg(swimPitch(NEW, math.rad(deg))))
end
print(row)
print(oldRow)
print(newRow)
for deg = -80, 80, 0.5 do
	local p = swimPitch(NEW, math.rad(deg))
	check(p >= last - 1e-9, `pitch map not monotonic at {deg}°`)
	last = p
end
check(math.abs(swimPitch(NEW, math.rad(80)) - math.rad(80)) < 1e-6, "steep aims swim where they point")
-- A shell on the sand 12 studs ahead and 6 down (26.6° down): where a fish aiming
-- at it passes
do
	local aim = math.atan2(6, 12)
	for _, m in { OLD, NEW } do
		local p = swimPitch(m, aim)
		print(
			`{m.name}: aiming 26.6° down at a shell 12 ahead, 6 down, the fish passes {fmt(
				6 - 12 * math.tan(p),
				1
			)} studs over it`
		)
	end
end

print("\n== A rock wall: swimming into it at full speed, held for 1 s ==")
for _, level in { 1, 40, 100 } do
	for _, incidence in { 0, 30, 60 } do
		local line = `LV {level}, {incidence}° off head-on:`
		for _, m in { OLD, NEW } do
			local f = fish(level)
			local wall = { x = f.radius + f.top * 0.3 }
			local a = math.rad(incidence)
			local want = v(math.cos(a), 0, math.sin(a))
			f.vel = want * f.top
			f.heading = want
			local t = 0
			local before = 0
			while t < 1.5 do
				local p = f.pos
				step(m, f, want, 1, wall)
				t += DT
				if t > 1.4 then
					before = mag(f.pos - p) / DT
				end
			end
			-- The fish's own idea of its speed and where it faces, after a second on the wall
			local facing = math.deg(math.asin(math.clamp(f.heading.x, -1, 1)))
			local gap = wall.x - f.pos.x - f.radius
			line ..= `  {m.name}: slides {fmt(before, 1)} studs/s, thinks {fmt(mag(f.vel), 1)}, faces {fmt(
				facing,
				0
			)}° in, {fmt(gap)} off`
			check(not m.glide or mag(f.vel) <= f.top * 1.0001, "glide adds speed")
			-- (it still reaches the rock: a fish noses into the sand for a starfish)
			check(gap <= swim.wallSkin + 0.02, `{m.name} LV {level}: never reaches the rock ({fmt(gap)} off)`)
		end
		print(line)
	end
end

print("\n== Pressed head-on into rock, then the aim turns 135° away: time to swim 1 length off it ==")
for _, level in { 1, 40, 100 } do
	local line = `LV {level}:`
	for _, m in { OLD, NEW } do
		local f = fish(level)
		local wall = { x = f.top * 0.5 }
		f.vel = v(f.top, 0, 0)
		for _ = 1, 90 do
			step(m, f, v(1, 0, 0), 1, wall)
		end
		local start = f.pos.x
		local a = math.rad(135)
		local want = v(math.cos(a), 0, math.sin(a))
		local t, done = 0, nil :: number?
		while t < 6 do
			step(m, f, want, 1, wall)
			t += DT
			if done == nil and start - f.pos.x >= f.length then
				done = t
			end
		end
		line ..= `  {m.name} {fmt(done or 6)} s`
	end
	print(line)
end

print("\n== Sticks: right-stick look rate (rad/s) and left-stick steer by deflection ==")
local function lookRate(deflection: number, curve: number): number
	local d = math.max(deflection - 0.15, 0) / 0.85
	return d ^ curve * cam.gamepadSpeed
end
-- Input.drive's steer for a sideways tilt `x` (past the pad's dead zone) at a throttle
local function steerOf(x: number, throttle: number): number
	local dead = cam.steerDeadZone * math.abs(throttle)
	return (math.max(math.abs(x) - dead, 0) / (1 - dead)) ^ cam.steerCurve
end
for _, d in { 0.2, 0.3, 0.5, 0.75, 1 } do
	local x = math.max(d - 0.15, 0) / 0.85
	print(
		`stick {fmt(d)}: look old {fmt(lookRate(d, 1))} new {fmt(lookRate(d, cam.gamepadCurve))} · steer old {fmt(
			x
		)} new {fmt(steerOf(x, 0))} sideways only, {fmt(steerOf(x, 1))} pushing ahead`
	)
end
check(math.abs(lookRate(1, cam.gamepadCurve) - cam.gamepadSpeed) < 1e-9, "full tilt keeps the top look speed")
check(math.abs(steerOf(1, 1) - 1) < 1e-9 and math.abs(steerOf(1, 0) - 1) < 1e-9, "full steer stays full")

-- Speeds (owner, 2026-10-18: "Speed also scales far too high from level 1 to lvl
-- 100 ... I do like how the bigger a fish is the easier they catch smaller prey"):
-- the top speed by level and species, the old curve beside it, and how long the
-- 3,000-stud map takes in a straight line, cruising and with every boost chained
print("\n== Top speed (studs/s): cruise / Dash or Torpedo (×boostMultiplier); old curve in brackets ==")
local Species = require("./Species")
local Abilities = require("./Abilities")
local Shop = require("./Shop")
local Pvp = require("./Pvp")
local size = Tuning.size
local FINS_MAX = 1 + Shop.upgradesById.Fins.per * #Shop.upgradesById.Fins.costs
local GILLS_MAX = 1 + Shop.upgradesById.Gills.per * #Shop.upgradesById.Gills.costs
local SLIP = Pvp.pods.slipstream.speed
local function oldTop(length: number): number
	return swim.baseSpeed * Size.raw(length) ^ swim.speedExponent
end
local function lengthAt(level: number): number
	return Size.length(Size.massForLevel(level))
end
local SHOWN = { "Nibbler", "Cuda", "ReefShark", "Pufferfish" }
local header = "LV   "
for _, id in SHOWN do
	header ..= string.format("%-24s", id)
end
print(header)
for _, level in { 1, 10, 25, 40, 60, 80, 100 } do
	local length = lengthAt(level)
	local line = string.format("%-5d", level)
	for _, id in SHOWN do
		local mul = Species.byId[id].stats.speed
		local top = Size.topSpeed(length) * mul
		line ..= string.format(
			"%-24s",
			string.format("%.1f / %.0f (%.0f)", top, top * swim.boostMultiplier, oldTop(length) * mul)
		)
	end
	print(line)
end
do
	local full = Size.length(Size.massForLevel(100) * size.haulLengthCap ^ 3)
	print(`LV 100 with a full Haul: {fmt(Size.topSpeed(full), 1)} (old {fmt(oldTop(full), 1)})`)
end

-- Every size is faster than any smaller one (bigger fish still catch smaller prey
-- easier), the curve under the knee is the old one, and the knee joins smoothly
do
	local last = 0
	for level = 1, 100 do
		for _, haul in { 1, 1.3, size.haulLengthCap } do
			local top = Size.topSpeed(Size.length(Size.massForLevel(level) * haul ^ 3))
			if haul == 1 then
				check(top > last, `LV {level}: no faster than LV {level - 1}`)
				last = top
			end
		end
	end
	for raw = 1, swim.speedKnee, 0.25 do
		check(math.abs(Size.topSpeed(raw) - oldTop(raw)) < 1e-9, `under the knee the curve changed at {raw}`)
	end
	local eps = 1e-4
	local k = swim.speedKnee
	local slopeIn = (oldTop(k) - oldTop(k - eps)) / eps
	local slopeOut = (Size.topSpeed(k + eps) - Size.topSpeed(k)) / eps
	check(math.abs(slopeIn - slopeOut) < 0.01, `the knee kinks: {slopeIn} → {slopeOut}`)
	check(Size.topSpeed(Size.raw(16.99)) < swim.speedCap, "past the cap")
end

-- A straight line from a standing start: cruising at `top`, and with a boost every
-- `every` seconds for `seconds` (× `mul`; a `jump` starts at that speed at once, the
-- Dash's tail flick, else the swim accelerates into it, Blood Sense). The swim's
-- own equations: up to a target at `accel`, shedding within top at `decel`.
type Boost = { mul: number, seconds: number, every: number, jump: boolean }
local MAP = 3000
local function cross(top: number, boost: Boost?): number
	local t, x, speed = 0, 0, 0
	local boostUntil, nextBoost = -1, 0
	while x < MAP and t < 600 do
		if boost and t >= nextBoost then
			boostUntil, nextBoost = t + boost.seconds, t + boost.every
			if boost.jump then
				speed = math.max(speed, top * boost.mul)
			end
		end
		local target = if boost and t < boostUntil then top * boost.mul else top
		local rate = if target < speed and speed <= top then swim.decel else swim.accel
		speed += (target - speed) * alpha(rate, DT)
		x += speed * DT
		t += DT
	end
	return t
end
local function signature(id: string, gills: number): Boost?
	local key = Species.byId[id].signature
	local ability = Abilities.byId[key]
	if key == "Dash" then
		return {
			mul = swim.boostMultiplier,
			seconds = swim.dashSeconds,
			every = swim.dashSeconds + swim.dashRecharge / gills,
			jump = true,
		}
	elseif key == "Torpedo" then
		return { mul = swim.boostMultiplier, seconds = ability.seconds, every = ability.cooldown, jump = true }
	elseif key == "BloodSense" and ability.speed then
		return { mul = ability.speed, seconds = ability.seconds, every = ability.cooldown, jump = false }
	end
	return nil
end
print(
	`\n== Across the {MAP}-stud map in a straight line (seconds): cruise / Strong Fins {#Shop.upgradesById.Fins.costs} / + its ability chained (Deep Gills {#Shop.upgradesById.Gills.costs}) / + a podmate's slipstream; old curve in brackets ==`
)
for _, level in { 40, 60, 100 } do
	for _, id in SHOWN do
		local mul = Species.byId[id].stats.speed
		local length = lengthAt(level)
		local function row(curve: (number) -> number): { number }
			local top = curve(length) * mul
			local boost = signature(id, GILLS_MAX)
			return {
				cross(top),
				cross(top * FINS_MAX),
				cross(top * FINS_MAX, boost),
				cross(top * FINS_MAX * SLIP, boost),
			}
		end
		local new, old = row(Size.topSpeed), row(oldTop)
		print(
			string.format(
				"LV %-3d %-11s %5.0f / %5.0f / %5.0f / %5.0f   (%3.0f / %3.0f / %3.0f / %3.0f)",
				level,
				id,
				new[1],
				new[2],
				new[3],
				new[4],
				old[1],
				old[2],
				old[3],
				old[4]
			)
		)
		if level == 100 and id == "Nibbler" then
			check(new[1] >= 55 and new[1] <= 75, `a LV 100 Nibbler crosses in {fmt(new[1], 0)} s (55–75 wanted)`)
		end
		if level == 100 and id == "Cuda" then
			check(new[3] >= 30, `a maxed LV 100 'Cuda crosses in {fmt(new[3], 0)} s with its Torpedo chained`)
		end
	end
end

if failures > 0 then
	error(`{failures} check(s) failed`)
end
print("\nswim: OK")
