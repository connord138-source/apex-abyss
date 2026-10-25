--!strict
-- The NPC prey. They are never Instances on the server: every fish follows a
-- path computed from the shared clock (Timing.clock), so the server and every
-- client agree where each one is without sending positions. Clients draw them
-- (SchoolController); the server only checks eats against the path and keeps
-- which fish are eaten until they respawn (HuntService).
--
-- Each school loops round its own center on a tilted figure-eight, and each fish
-- keeps an offset inside the school with a little wobble, so they read as a school.
--
-- A school's loop is laid out over the nominal floor (Shared/Seafloor), but rocks,
-- coral heads, wrecks, ruins, arches and the reef's ridges rise above it, and fish
-- swam through them (owner, 2026-10-17: "Ensure that no shells or shrimp or fish
-- spawn in or under items that the player cannot access"). Once the world is built
-- the server lifts each school over the real ground along its loop (`settle`, with
-- Shared/Ground: the top of the Terrain and the solid dressing in each column, so
-- never under an overhang), easing up and over in ramps, and publishes the lifts
-- (the Workspace attribute `SchoolLifts`); clients `load` the same numbers, so every
-- machine still agrees where each fish is.
local Config = require(script.Parent.Config)
local Seafloor = require(script.Parent.Seafloor)
local Size = require(script.Parent.Size)

local World = Config.World
local Prey = Config.Prey

export type School = {
	prey: string,
	center: Vector3,
	radius: number,
	ellipse: number, -- z radius / x radius
	height: number, -- figure-eight rise and fall
	angularSpeed: number, -- radians/s round the loop (sign = direction)
	tilt: number, -- how much of its rise and fall it faces along (≤ 1; TILT_RATE)
	phase: number,
	spread: number, -- studs: how far fish sit from the school's middle
	first: number, -- its fish are Schools.fish[first .. first + count - 1]
	count: number,
	tide: string?, -- only out while this tide is up (Config/Tides)
	-- Studs from its center within which a client keeps its fish built
	-- (SchoolController): its furthest-seen fish's range plus the loop and the school
	reach: number,
}

export type Fish = {
	school: number,
	prey: string,
	offset: Vector3, -- in the school's frame, studs
	phase: number,
	length: number, -- body length, studs (its own size: `size` × the species')
	radius: number, -- for eat checks
	size: number, -- how big this one is next to its species (0.82–1.18, a few trophies to 1.5)
	mass: number, -- kg: the species' mass × size³ (what eating it is worth; the Catch Log's biggest)
	-- How far from the camera a client draws it (studs; SchoolController): bigger fish
	-- further, and the back of a big school thins out before its core
	range: number,
	wave: number, -- how far its spine still swims (studs)
}

-- Where some of a prey's schools go (Config/Prey `zones`, `tideZones`)
type Zone = {
	band: { number },
	angles: { number }?,
	schools: number,
	depth: { number }?,
	tide: string?,
	perSchool: number?,
	spread: number?,
	round: boolean?,
	pathRadius: { number }?,
	trench: boolean?,
	vents: boolean?,
}

-- How far a client draws each fish (SchoolController; owner, 2026-10-18: "We still
-- need so much more fish too. I feel like the ocean has a pretty empty feeling"):
-- DRAW_BASE plus DRAW_PER_STUD per stud of its length, at most DRAW_MAX (a 1-stud
-- minnow is a few pixels at 200 studs, a reef shark reads to the haze). The first
-- THIN_CORE of a school always shows to its full range; the rest thin out with
-- distance down to THIN_LAST of it, so a far school reads as a school at half the
-- fish. Spines swim within WAVE_BASE + WAVE_PER_STUD per stud, at most WAVE_MAX.
local DRAW_BASE = 180
local DRAW_PER_STUD = 55
local DRAW_MAX = 520
local THIN_CORE = 0.4
local THIN_LAST = 0.45
local WAVE_BASE = 40
local WAVE_PER_STUD = 45
local WAVE_MAX = 160
local BUILD_MARGIN = 40 -- studs past a school's reach before a client builds its fish
-- A zone whose band starts this far out is past the drop-off (Config/Prey `fill`
-- `deepSchools`)
local DEEP_FROM = 900
local SETTLE_SLICE = 0.02 -- seconds of lifting between the server's yields (Schools.settle)
-- A school faces along its loop, but its nose never pitches faster than TILT_RATE
-- radians a second: on a small loop with a big rise and fall (a reef school 6 studs
-- round bobbing 13) the heading flipped from steeply down to steeply up in a few
-- tenths of a second at the bottom of each dip, and the whole school swung round
-- its middle with it, its fish flung at up to ~90 studs/s (the jump sim, 2026-10-27:
-- 95 schools pitched over 2 rad/s, 15 over 8; the Reef's Butterflyfish and Blue
-- Tang read 4-6× their speed on screen). Such a school faces only `tilt` of its
-- climb (the peak pitch rate is 4 × height × angular speed ÷ radius); it still rises
-- and falls as before.
local TILT_RATE = 1

local list: { School } = {}
local fish: { Fish } = {}
-- Each school's lift over the real ground at evenly spaced points round its loop
-- (studs; nil = none), from `settle` on the server or `load` on a client
local lifts: { [number]: { number } } = {}

-- Every fish its own size (owner, 2026-10-10: the Catch Log tracks "their biggest
-- eat of each species"; 2026-10-20: "All fish need to have varied sizes so that its
-- reflected accurately in the collection log for largest catch"): most from 0.68 to
-- 1.3 of the species' length (its kg ×0.31 to ×2.2), 1 in 16 a trophy 1.3–1.65 long
-- (to ×4.5 the kg). The mean kg is ~6% over the species' (it was ~3%). From its own
-- seed, so no school moves.
local sizeRng = Random.new(World.seed + 2)
local TROPHY_CHANCE = 0.0625
local function sizeOf(): number
	if sizeRng:NextNumber() < TROPHY_CHANCE then
		return 1.3 + sizeRng:NextNumber() * 0.35
	end
	return 0.68 + sizeRng:NextNumber() * 0.62
end

-- Lays out one zone's schools of a prey (rng shared, so the layout is the same
-- everywhere)
local function build(rng: Random, prey: any, zone: Zone, tide: string?)
	local length = Size.length(prey.mass)
	-- How full the sea is (Config/Prey `fill`): more schools (more again in the deep
	-- biomes) and bigger ones (a lone hunter stays alone)
	local fill = Prey.fill
	local listed = zone.perSchool or prey.perSchool
	local perSchool = if listed > 1
		then math.max(listed, math.min(math.floor(listed * fill.perSchool + 0.5), fill.perSchoolMax))
		else listed
	local deepZone = zone.trench == true or zone.vents == true or zone.band[1] >= DEEP_FROM
	local schools = math.floor(zone.schools * (if deepZone then fill.deepSchools else fill.schools) + 0.5)
	local pathRadius = zone.pathRadius or prey.pathRadius
	-- A bait ball is round (as deep as it is wide); a shoal is flatter
	local deep = if zone.round then 2 else 1
	for _ = 1, schools do
		local radius = rng:NextNumber(pathRadius[1], pathRadius[2])
		local spread = prey.spread * length * math.sqrt(perSchool) * (zone.spread or 1)
		local margin = radius + spread + 10
		local band = zone.band
		local dx, dz = 0, 0
		if zone.trench then
			-- Down in the Abyssal Trench's canyon: somewhere along its line, inside its
			-- middle cut (Seafloor's canyon), its height over the floor there; the lift
			-- keeps the loop off the steps and walls
			local trench = World.trench
			local r = rng:NextNumber(trench.radii[1] + margin, trench.radii[2] - margin)
			local _, width = Seafloor.trenchAxis(r)
			local _, halfMiddle = Seafloor.trenchHalfWidths(width)
			local x, z = Seafloor.trenchPoint(r, rng:NextNumber(-1, 1) * math.max(halfMiddle - margin, 0))
			dx, dz = x - World.hub.center.X, z - World.hub.center.Z
		elseif zone.vents then
			-- Over one of the Hydrothermal Vents' basins (Seafloor.ventBasins), its loop
			-- inside the rim; its height is over the basin's floor, and the lift carries
			-- it over the chimneys
			local basins = Seafloor.ventBasins()
			local basin = basins[rng:NextInteger(1, #basins)]
			local angle = rng:NextNumber(0, 2 * math.pi)
			local r = rng:NextNumber(0, math.max(basin.radius - margin, 0))
			dx = basin.x + math.cos(angle) * r - World.hub.center.X
			dz = basin.z + math.sin(angle) * r - World.hub.center.Z
		else
			for _ = 1, 12 do
				local angle
				if zone.angles then
					local span = (zone.angles[2] - zone.angles[1]) % 360
					angle = math.rad(zone.angles[1] + rng:NextNumber(0, if span == 0 then 360 else span))
				else
					angle = rng:NextNumber(0, 2 * math.pi)
				end
				local distance = rng:NextNumber(band[1] + margin, band[2] - margin)
				dx, dz = math.cos(angle) * distance, math.sin(angle) * distance
				if not Seafloor.inTrench(dx, dz, margin) then
					break
				end
			end
		end
		local height = rng:NextNumber(4, 14)
		local floor = Seafloor.y(dx, dz)
		local depth = zone.depth or prey.depth
		local y = floor + rng:NextNumber(depth[1] + height, depth[2] - height)
		local direction = if rng:NextInteger(0, 1) == 0 then -1 else 1
		local school: School = {
			prey = prey.id,
			center = World.hub.center + Vector3.new(dx, y, dz),
			radius = radius,
			ellipse = rng:NextNumber(0.55, 1),
			height = height,
			angularSpeed = direction * prey.speed / radius,
			tilt = math.min(1, TILT_RATE * radius * radius / (4 * height * prey.speed)),
			phase = rng:NextNumber(0, 2 * math.pi),
			spread = spread,
			first = #fish + 1,
			count = perSchool,
			tide = tide,
			reach = 0,
		}
		table.insert(list, school)
		local core = math.ceil(perSchool * THIN_CORE)
		local furthest = 0
		for k = 1, perSchool do
			local offset = Vector3.zero
			if perSchool > 1 then
				offset = Vector3.new(
					rng:NextNumber(-1, 1),
					rng:NextNumber(-0.45, 0.45) * deep,
					rng:NextNumber(-1, 1)
				)
				if zone.round and offset.Magnitude > 1 then
					offset = offset.Unit -- a ball, not a box
				end
				offset *= spread
			end
			local size = sizeOf()
			-- (its own mass's length, so a trophy eases like any other fish; × the
			-- species' `look`: the smallest are drawn and caught longer, the school
			-- no wider)
			local own = Size.length(prey.mass * size ^ 3) * (prey.look or 1)
			local keep = if k <= core
				then 1
				else 1 - (1 - THIN_LAST) * (k - core) / math.max(perSchool - core, 1)
			local range = math.min(DRAW_BASE + DRAW_PER_STUD * own, DRAW_MAX) * keep
			furthest = math.max(furthest, range)
			table.insert(fish, {
				school = #list,
				prey = prey.id,
				offset = offset,
				phase = rng:NextNumber(0, 2 * math.pi),
				length = own,
				radius = own * 0.3,
				size = size,
				mass = prey.mass * size ^ 3,
				range = range,
				wave = math.min(WAVE_BASE + WAVE_PER_STUD * own, WAVE_MAX),
			})
		end
		school.reach = furthest + radius + spread + BUILD_MARGIN
	end
end

do
	local rng = Random.new(World.seed)
	local shallows = World.shallows
	for _, prey in Prey.list do
		-- Where its schools go: the zones it lists, or one band all round the hub
		local zones: { Zone } = prey.zones
			or { { band = prey.band or { shallows.inner, shallows.outer }, schools = prey.schools } }
		for _, zone in zones do
			build(rng, prey, zone, nil)
		end
	end
	-- The tide schools last, with their own seed, so they never move the others
	local tideRng = Random.new(World.seed + 1)
	for _, prey in Prey.list do
		local tideZones: { Zone } = prey.tideZones or {}
		for _, zone in tideZones do
			build(tideRng, prey, zone, zone.tide)
		end
	end
	-- Then the schools added later (Config/Prey `laterZones`: the clouds over the coral
	-- and rock, more kinds in the Coral Reef), from their own seed too
	local cloudRng = Random.new(World.seed + 5)
	for _, prey in Prey.list do
		local laterZones: { Zone } = prey.laterZones or {}
		for _, zone in laterZones do
			build(cloudRng, prey, zone, nil)
		end
	end
end

-- The furthest a drawn-in fish is eaten from (the pull brings it the rest of the
-- way), × the swallow reach (Schools.eatReach): the server's check allows for it
local function pulledReach(): number
	local eat = Prey.eat
	local a, b = eat.pullShare / eat.pull, 1 - eat.pullShare
	return (-b + math.sqrt(b * b + 4 * a)) / (2 * a)
end

local Schools = {
	list = list,
	fish = fish,
	COUNT = #fish,
	EAT_PULLED = pulledReach(),
}

-- Whether fish `index` is out: a tide school only while its tide is up
function Schools.out(index: number, tideId: string): boolean
	local tide = list[fish[index].school].tide
	return tide == nil or tide == tideId
end

-- A school's place on its loop at loop angle `a`, before any lift, and its velocity
local function loopAt(school: School, a: number): (Vector3, Vector3)
	local r = school.radius
	local position = school.center
		+ Vector3.new(
			math.cos(a) * r,
			math.sin(2 * a + school.phase) * school.height,
			math.sin(a) * r * school.ellipse
		)
	local w = school.angularSpeed
	local velocity = Vector3.new(
		-math.sin(a) * r * w,
		math.cos(2 * a + school.phase) * 2 * school.height * w,
		math.cos(a) * r * school.ellipse * w
	)
	return position, velocity
end

-- Which way a school faces moving at `velocity` on its loop (TILT_RATE)
local function heading(school: School, velocity: Vector3): Vector3
	return Vector3.new(velocity.X, velocity.Y * school.tilt, velocity.Z)
end

-- How far school `index` is lifted at loop angle `a` (between its samples)
local function liftAt(index: number, a: number): number
	local samples = lifts[index]
	if samples == nil then
		return 0
	end
	local count = #samples
	local u = ((a / (2 * math.pi)) % 1) * count
	local i = math.floor(u)
	local low = samples[i % count + 1]
	local high = samples[(i + 1) % count + 1]
	return low + (high - low) * (u - i)
end

-- The school's frame at time t: its position on the loop, facing along it. (A lift
-- raises it without turning it: the fish rise and fall gently over the rocks.)
function Schools.schoolFrame(index: number, t: number): CFrame
	local school = list[index]
	local a = school.phase + school.angularSpeed * t
	local position, velocity = loopAt(school, a)
	position += Vector3.new(0, liftAt(index, a), 0)
	return CFrame.lookAt(position, position + heading(school, velocity))
end

-- Lifting the schools over the real ground. Each fish keeps CLEAR_STUDS plus
-- CLEAR_LENGTHS of its own length (its wobble and half its body) over the tallest
-- ground within a cell of where it swims; the loop is checked every FINE_STEP studs
-- and the lift stored every LIFT_STEP; a lift rises and falls at most SLOPE studs
-- per stud along the loop.
local CELL = 4 -- Shared/Ground's cell
-- (2 since 2026-10-19: 1.5 left a low Lionfish on a tight loop, pitched nose-down, a
-- fifth of a stud into a rock in run_schools.sh once the third prey batch moved it)
local CLEAR_STUDS = 2
local CLEAR_LENGTHS = 0.6
local FINE_STEP = 2
local LIFT_STEP = 6
local SLOPE = 0.8
-- Away from the hub's seamount and the drop-off, nothing rises more than RELIEF over
-- the nominal floor (the Trench's basalt pillars stand up to ~170, the Vents'
-- chimneys ~95, the Open Blue's spires ~70), so a fish higher than that over it needs
-- no ground rays: with the deep biomes' mid-water schools (2026-10-18) the lift's
-- rays at a server's start would have tripled
local RELIEF = 240
local SEAMOUNT_KEEP = 320 -- studs from the hub: always checked
local function nearGround(x: number, z: number, y: number): boolean
	local r = Seafloor.polar(x, z)
	local shelf = World.shelf
	if r < SEAMOUNT_KEEP or (r > shelf.radius - 30 and r < shelf.radius + shelf.edge + 60) then
		return true
	end
	return y - Seafloor.y(x, z) < RELIEF
end

-- Works out every school's lift over `groundY` (Shared/Ground.y on the server, once
-- the world's dressing is built), applies it here and returns it as the string
-- clients `load`.
function Schools.settle(groundY: (number, number) -> number, pause: (() -> ())?): string
	-- The tallest ground in the 3 × 3 cells round a point (a rock's edge can fall
	-- between two cells' sample columns)
	local tallestCache: { [number]: number } = {}
	local function tallest(x: number, z: number): number
		local cx, cz = math.floor(x / CELL), math.floor(z / CELL)
		local key = (cx + 2000) * 4096 + (cz + 2000)
		local known = tallestCache[key]
		if known then
			return known
		end
		local top = -math.huge
		for dx = -1, 1 do
			for dz = -1, 1 do
				top = math.max(top, groundY((cx + dx + 0.5) * CELL, (cz + dz + 0.5) * CELL))
			end
		end
		tallestCache[key] = top
		return top
	end
	local ceiling = World.surfaceY - 8
	local parts: { string } = {}
	table.clear(lifts)
	-- (`pause`, if given, is called between schools every SETTLE_SLICE seconds: the
	-- server yields there, since ~8,500 fish take a couple of seconds)
	local sliceFrom = os.clock()
	for index, school in list do
		if pause and os.clock() - sliceFrom > SETTLE_SLICE then
			pause()
			sliceFrom = os.clock()
		end
		-- The loop's length, roughly (an ellipse)
		local around = math.pi * school.radius * (1 + school.ellipse)
		local fine = math.clamp(math.ceil(around / FINE_STEP), 48, 720)
		local count = math.clamp(math.ceil(around / LIFT_STEP), 16, 160)
		local need = table.create(fine, 0)
		local highest = -math.huge
		for k = 0, fine - 1 do
			local a = k / fine * 2 * math.pi
			local position, velocity = loopAt(school, a)
			local frame = CFrame.lookAt(position, position + heading(school, velocity))
			local flat = Vector3.new(velocity.X, 0, velocity.Z)
			local along = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
			local most = 0
			for i = school.first, school.first + school.count - 1 do
				local f = fish[i]
				local at = frame:PointToWorldSpace(f.offset)
				highest = math.max(highest, at.Y + f.length)
				if not nearGround(at.X, at.Z, at.Y - f.length) then
					continue
				end
				local ground = tallest(at.X, at.Z)
				-- (a long fish's nose and tail, and its wobble along the loop)
				if f.length > CELL * 0.5 then
					local reach = along * f.length * 0.6
					ground = math.max(ground, tallest(at.X + reach.X, at.Z + reach.Z))
					ground = math.max(ground, tallest(at.X - reach.X, at.Z - reach.Z))
				end
				most = math.max(most, ground + CLEAR_STUDS + f.length * CLEAR_LENGTHS - at.Y)
			end
			need[k + 1] = most
		end
		if highest == -math.huge then
			continue
		end
		-- Each stored lift covers the most any checked point needs from the stored point
		-- before it to the one after, so the lift between two of them (a straight line)
		-- never dips under what's needed
		local samples = table.create(count, 0)
		local any = false
		for k = 0, fine - 1 do
			if need[k + 1] > 0 then
				local u = k / fine * count
				local low = math.floor(u)
				for j = low - 1, low + 2 do
					local slot = j % count + 1
					if math.abs(j - u) <= 1 then
						samples[slot] = math.max(samples[slot], need[k + 1])
						any = true
					end
				end
			end
		end
		if not any then
			continue
		end
		-- Ramps up and over, never a jump; and never through the surface
		local spacing = around / count
		for _ = 1, 2 do
			for k = 0, 2 * count - 1 do
				local here, before = k % count + 1, (k - 1) % count + 1
				samples[here] = math.max(samples[here], samples[before] - SLOPE * spacing)
			end
			for k = 2 * count - 1, 0, -1 do
				local here, after = k % count + 1, (k + 1) % count + 1
				samples[here] = math.max(samples[here], samples[after] - SLOPE * spacing)
			end
		end
		local cap = math.max(ceiling - highest, 0)
		local values: { string } = {}
		for k = 1, count do
			table.insert(values, tostring(math.ceil(math.min(samples[k], cap))))
		end
		table.insert(parts, `{index}:{table.concat(values, ",")}`)
	end
	local encoded = table.concat(parts, ";")
	Schools.load(encoded)
	return encoded
end

-- Takes the lifts the server worked out (`settle`'s string; "" or nil = none)
function Schools.load(encoded: string?)
	table.clear(lifts)
	if encoded == nil or encoded == "" then
		return
	end
	for entry in string.gmatch(encoded, "[^;]+") do
		local head, body = string.match(entry, "^(%d+):(.*)$")
		local index = tonumber(head)
		if index and body and list[index] then
			local samples: { number } = {}
			for value in string.gmatch(body, "[^,]+") do
				table.insert(samples, tonumber(value) or 0)
			end
			if #samples > 0 then
				lifts[index] = samples
			end
		end
	end
end

-- How close to the mouth a fish that can be swallowed whole is eaten (studs, mouth to
-- its middle), and from how far it's drawn toward the mouth first (Config/Prey `eat`)
function Schools.eatReach(eaterLength: number, preyRadius: number): (number, number)
	local eat = Prey.eat
	local reach = Size.reach(eaterLength) * eat.scale + eat.bonus + preyRadius
	return reach, reach * eat.pull
end

-- One fish's frame, given its school's frame at the same t.
function Schools.fishFrame(index: number, schoolFrame: CFrame, t: number): CFrame
	local f = fish[index]
	local school = list[f.school]
	local p = f.phase
	local wobble = Vector3.new(
		math.sin(t * 1.3 + p) * 0.5,
		math.sin(t * 1.9 + p * 2) * 0.35,
		math.sin(t * 0.9 + p) * 0.6
	)
	-- (its length, but never more studs than its speed: a big slow fish's sway along
	-- its line outran its swim, and the Ocean Sunfish and the Oarfish slid tail first a
	-- third of the time, PC 2026-10-19 round 2, PR7)
	local size = math.min(f.length, math.abs(school.angularSpeed) * school.radius)
	local position = schoolFrame:PointToWorldSpace(f.offset + wobble * size)
	local yaw = math.sin(t * 2.6 + p * 3) * 0.14
	return CFrame.new(position) * schoolFrame.Rotation * CFrame.Angles(0, yaw, 0)
end

function Schools.position(index: number, t: number): Vector3
	local f = fish[index]
	return Schools.fishFrame(index, Schools.schoolFrame(f.school, t), t).Position
end

-- A chase (AggroService): how far along the dart a fish is at `elapsed` seconds
-- into a chase of `seconds`: out to the target by `lungeAt`, a snap, then back to
-- its path. 0 = on the path, 1 = at the target.
function Schools.chaseBlend(elapsed: number, seconds: number, lungeAt: number): number
	if elapsed <= 0 or elapsed >= seconds then
		return 0
	end
	if elapsed <= lungeAt then
		local t = elapsed / lungeAt
		return t * t * (3 - 2 * t) -- ease out of the school
	end
	local back = (elapsed - lungeAt) / math.max(seconds - lungeAt, 0.01)
	return 1 - back * back
end

-- Where a chasing fish is: between its path position and a point just short of the
-- target (it stops at its own half-length plus the target's).
function Schools.chasePosition(
	index: number,
	pathPosition: Vector3,
	target: Vector3,
	targetLength: number,
	blend: number
): Vector3
	local f = fish[index]
	local toward = target - pathPosition
	local distance = toward.Magnitude
	if distance < 1e-3 then
		return pathPosition
	end
	local stop = math.max(distance - (f.length * 0.5 + targetLength * 0.35), 0)
	return pathPosition + toward.Unit * stop * blend
end

return Schools
