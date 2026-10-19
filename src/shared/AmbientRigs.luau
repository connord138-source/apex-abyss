--!strict
-- The ambient sea life's skeletons, motions and part-built stand-ins (owner, 2026-10-19:
-- "the sea turtles and manta rays/stingrays need to be dialed up they're essentially
-- just circles put together"). AmbientLifeController draws each creature as its
-- imported model (ReplicatedStorage.AmbientModels.<Name>, rigged by
-- tools/blender/rig_ambient.py) or, until that's imported, as the faceted stand-in
-- built here; both are posed by the same functions, by joint name, so they move alike.
-- tools/preview/run_ambient.sh runs this module in the luau CLI and renders the same
-- poses in Blender. Pure math (Vector3, CFrame, Color3 only), no Instances.
--
-- Axes are the creature's own: X to its right, Y up, -Z ahead (a rigged Model faces -Z
-- and is never turned). A pose is each joint's turn about its own pivot in those rest
-- axes: a bone takes it as R:Inverse() * turn * R (R its rest rotation), a stand-in's
-- Motor6D as its Transform. Left is -X; a joint's "L"/"R" is the creature's own side.
--
-- Rigs (the bone names rig_ambient.py writes):
--   manta     Body; WingL1 > WingL2 > WingL3 (and R); HornL, HornR; Tail1 > Tail2
--   stingray  Body; Fin<L|R><F|M|B>1 > ..2 (front, middle and back of each margin);
--             Tail1 > Tail2 > Tail3
--   turtle    Shell; Neck > Head; FinL1 > FinL2 > FinL3 (and R); HindL1 > HindL2
--             (and R); Tail
--   whale     Body > Spine1 > Spine2 > Spine3 > Flukes; PecL1 > PecL2 (and R)
--   crab      Body; ClawL1 > ClawL2 (and R); LegL1, LegL2, LegL3 (and R); EyeL, EyeR
local AmbientRigs = {}

export type Pose = { [string]: CFrame }

-- What a creature is doing this frame (the controller fills it in)
export type Motion = {
	t: number, -- the shared clock, seconds
	phase: number, -- its own offset, radians
	period: number, -- seconds a beat (a flap, a stroke, a ripple)
	bank: number, -- radians, + rolling to its right (into a right turn)
	turn: number, -- -1 .. 1, + turning right
	rest: number, -- a stingray: 0 swimming .. 1 settled on the floor
	settled: number, -- seconds since it last touched down (-1: it's swimming)
	moving: boolean, -- a crab scuttling
	alarm: number?, -- a crab: 0 .. 1, squaring up to a fish that can't eat it
}

-- A stand-in's joint: where it pivots at rest, unit size, and what it hangs from
export type Joint = { name: string, parent: string?, at: Vector3 }
-- A stand-in's piece. `tri`: a flat triangle (a, b, c), drawn as two WedgeParts;
-- `block`, `wedge`, `ball` and `cyl`: one part of that shape and `size` at `cframe`
-- (`cyl` lies along its X like a Roblox cylinder). `role` picks its colour from the
-- kind's look (Config/Ambient), `thick` a triangle's thickness. All unit size.
export type Piece = {
	joint: string,
	role: string,
	shape: string,
	a: Vector3?,
	b: Vector3?,
	c: Vector3?,
	thick: number?,
	size: Vector3?,
	cframe: CFrame?,
}
export type Plan = {
	joints: { Joint },
	pieces: { Piece },
	measure: string, -- "X" or "Z": the extent `size` means (span or length)
	floor: number, -- unit studs from its middle down to what it stands or rests on
}

local TAU = 2 * math.pi

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- A wing, flipper or leg raised by `e` (radians, + up) on side `side` (-1 left, +1 right)
local function raise(side: number, e: number): CFrame
	return CFrame.Angles(0, 0, side * e)
end

-- Swept back by `s` (+ the tip toward the tail)
local function sweep(side: number, s: number): CFrame
	return CFrame.Angles(0, -side * s, 0)
end

local function sides(): { { side: number, tag: string } }
	return { { side = -1, tag = "L" }, { side = 1, tag = "R" } }
end

----------------------------------------------------------------------------------
-- Travel: how far along its path a creature has gone by time t, in seconds of its
-- cruise (a turtle surges on each stroke and coasts; a stingray stops to settle)

-- A turtle's speed through one stroke (power stroke, coast, recovery), mean 1
local TURTLE_SPEED =
	{ { 0, 0.8 }, { 0.12, 1.5 }, { 0.3, 1.4 }, { 0.45, 1.05 }, { 0.65, 0.78 }, { 0.85, 0.68 }, { 1, 0.8 } }
local turtleTable: { number } = {}
do
	local steps = 128
	local function at(u: number): number
		for i = 1, #TURTLE_SPEED - 1 do
			local a, b = TURTLE_SPEED[i], TURTLE_SPEED[i + 1]
			if u <= b[1] then
				local s = (u - a[1]) / (b[1] - a[1])
				return a[2] + (b[2] - a[2]) * (s * s * (3 - 2 * s))
			end
		end
		return TURTLE_SPEED[#TURTLE_SPEED][2]
	end
	local total = 0
	turtleTable[1] = 0
	for k = 1, steps do
		total += at((k - 0.5) / steps) / steps
		turtleTable[k + 1] = total
	end
	for k = 1, #turtleTable do
		turtleTable[k] /= total
	end
end

-- Seconds of cruise a turtle has covered by `t` (its strokes `period` s apart)
function AmbientRigs.turtleTravel(t: number, period: number, phase: number): number
	local x = t / period + phase / TAU
	local n = math.floor(x)
	local u = (x - n) * (#turtleTable - 1)
	local i = math.floor(u)
	local cum = turtleTable[i + 1]
		+ (turtleTable[math.min(i + 2, #turtleTable)] - turtleTable[i + 1]) * (u - i)
	return (n + cum) * period
end

-- A stingray's day: it glides for most of a `cycle`, eases down onto the floor over
-- `ease` s, lies there `rest` s and eases up again. Returns the seconds of glide it has
-- covered, how settled it is (0 .. 1) and how long it has lain there (-1 when not)
function AmbientRigs.rayTravel(
	t: number,
	cycle: number,
	rest: number,
	ease: number,
	phase: number
): (number, number, number)
	local x = t + phase / TAU * cycle
	local n = math.floor(x / cycle)
	local u = x - n * cycle
	local glide = cycle - rest - 2 * ease
	local per = glide + ease -- (each ease covers half its time)
	local covered, settled, since
	if u < glide then
		covered, settled, since = u, 0, -1
	elseif u < glide + ease then
		local s = (u - glide) / ease
		covered = glide + ease * (s / 2 + math.sin(math.pi * s) / (2 * math.pi))
		settled, since = smooth(s), -1
	elseif u < glide + ease + rest then
		covered, settled, since = glide + ease / 2, 1, u - glide - ease
	else
		local s = (u - glide - ease - rest) / ease
		covered = glide + ease / 2 + ease * (s / 2 - math.sin(math.pi * s) / (2 * math.pi))
		settled, since = 1 - smooth(s), -1
	end
	return n * per + covered, settled, since
end

----------------------------------------------------------------------------------
-- Poses. Each fills `out` with the joints' turns and returns the body's own offset
-- (heave in unit studs, pitch, bank) for the controller to put on the creature's frame.

-- Manta: a slow, powerful flap, the wave travelling out along each wing (the tip lags
-- the shoulder), the outer wing feathering through the stroke; the body heaves up as
-- the wings beat down and noses up a touch; the tail trails, the cephalic fins curl.
local MANTA_LIFT = { 0.2, 0.44, 0.66 }
local MANTA_FEATHER = { 0.04, 0.09, 0.15 }
local MANTA_LAG = 0.55
function AmbientRigs.manta(m: Motion, out: Pose): CFrame
	local base = m.t * TAU / m.period + m.phase
	local before = 0
	for k = 1, 3 do
		local e = MANTA_LIFT[k] * math.sin(base - k * MANTA_LAG) + 0.04 * k
		local f = MANTA_FEATHER[k] * math.cos(base - k * MANTA_LAG)
		for _, s in sides() do
			out[`Wing{s.tag}{k}`] = raise(s.side, e - before) * CFrame.Angles(f, 0, 0)
		end
		before = e
	end
	for _, s in sides() do
		out[`Horn{s.tag}`] =
			CFrame.Angles(0.12 * math.sin(base * 0.5 + 1), -s.side * 0.06 * math.sin(base * 0.5), 0)
	end
	out.Tail1 = CFrame.Angles(0.06 * math.sin(base - 1.6), 0.08 * math.sin(base * 0.5 - 0.8), 0)
	out.Tail2 = CFrame.Angles(0.1 * math.sin(base - 2.2), 0.14 * math.sin(base * 0.5 - 1.6), 0)
	out.Body = CFrame.Angles(0.05 * math.cos(base - 0.3), 0, 0)
	local heave = -0.035 * math.sin(base - 2 * MANTA_LAG)
	return CFrame.new(0, heave, 0) * CFrame.Angles(0, 0, -m.bank)
end

-- Stingray: a ripple running head to tail along each edge of the disc (both sides in
-- step), the outer bone lagging the inner one; gliding, the tail sways. Settling, the
-- ripple dies away and the disc flutters for a moment as it beds into the sand.
local RAY_STATIONS = { "F", "M", "B" }
function AmbientRigs.stingray(m: Motion, out: Pose): CFrame
	local base = m.t * TAU / m.period + m.phase
	local calm = 1 - 0.85 * m.rest
	local flutter = 0
	if m.settled >= 0 then
		flutter = math.max(0, 1 - m.settled / 1.4) * 0.12 * math.sin(m.t * 22 + m.phase)
	end
	for j, station in RAY_STATIONS do
		local wave = base - (j - 1) * 1.15
		local inner = 0.1 * calm * math.sin(wave) + flutter
		local outer = 0.24 * calm * math.sin(wave - 0.7) + flutter * 1.5
		for _, s in sides() do
			out[`Fin{s.tag}{station}1`] = raise(s.side, inner)
			out[`Fin{s.tag}{station}2`] = raise(s.side, outer - inner)
		end
	end
	local slow = m.t * 0.9 + m.phase
	local sway = 1 - 0.7 * m.rest
	out.Tail1 = CFrame.Angles(0.04 * m.rest, (0.06 * math.sin(slow) - 0.2 * m.turn) * sway, 0)
	out.Tail2 = CFrame.Angles(0, (0.1 * math.sin(slow - 0.9) - 0.15 * m.turn) * sway, 0)
	out.Tail3 = CFrame.Angles(0, 0.15 * math.sin(slow - 1.8) * sway, 0)
	out.Body = CFrame.Angles(0.02 * math.sin(base) * calm, 0, 0)
	return CFrame.Angles(0, 0, -m.bank)
end

-- A turtle's front flipper through one stroke: (u, raised, swept back, feathered).
-- The power stroke sweeps it down and back with the blade flat, it coasts held back
-- along the body, then the recovery brings it up and forward turned edge-on.
local STROKE = {
	{ 0.0, 0.5, -0.3, 0.12 },
	{ 0.17, 0.02, 0.22, 0.28 },
	{ 0.34, -0.42, 0.82, 0.08 },
	{ 0.6, -0.3, 0.95, 0.0 },
	{ 0.8, 0.12, 0.45, 1.05 },
}

local function stroke(u: number): (number, number, number)
	u %= 1
	local n = #STROKE
	local i = n
	for k = 1, n do
		if STROKE[k][1] <= u then
			i = k
		end
	end
	local function key(k: number): ({ number }, number)
		-- (wrapped round the cycle, with the u it sits at)
		local wraps = math.floor((k - 1) / n)
		local entry = STROKE[(k - 1) % n + 1]
		return entry, entry[1] + wraps
	end
	local p1, u1 = key(i)
	local p2, u2 = key(i + 1)
	local p0 = key(i - 1 + n)
	local p3 = key(i + 2)
	local s = (u - u1) / (u2 - u1)
	local s2, s3 = s * s, s * s * s
	local function cr(c: number): number
		local a, b, cc, d = p0[c], p1[c], p2[c], p3[c]
		return 0.5
			* (2 * b + (-a + cc) * s + (2 * a - 5 * b + 4 * cc - d) * s2 + (-a + 3 * b - 3 * cc + d) * s3)
	end
	return cr(2), cr(3), cr(4)
end

function AmbientRigs.turtle(m: Motion, out: Pose): CFrame
	local u = m.t / m.period + m.phase / TAU
	local raised, back, feather = stroke(u)
	-- (the flipper bends: the wrist and tip trail the shoulder through the stroke)
	local lag1 = stroke(u - 0.05) - raised
	local lag2 = stroke(u - 0.1) - raised
	for _, s in sides() do
		local tag, side = s.tag, s.side
		-- Turning, the outside flipper works a little harder than the inside one
		local reach = 1 + 0.15 * side * m.turn
		out[`Fin{tag}1`] = sweep(side, back * reach)
			* raise(side, raised * reach)
			* CFrame.Angles(feather, 0, 0)
		out[`Fin{tag}2`] = raise(side, 0.6 * lag1 - 0.04) * CFrame.Angles(0.15 * feather, 0, 0)
		out[`Fin{tag}3`] = sweep(side, 0.12) * raise(side, 0.8 * (lag2 - lag1) - 0.05)
		-- Hind flippers: rudders, held back, steering and paddling a little
		local paddle = 0.08 * math.sin(TAU * u - 0.6)
		out[`Hind{tag}1`] = sweep(side, 0.25 - side * 0.3 * m.turn)
			* raise(side, paddle - 0.05)
			* CFrame.Angles(-0.25 * m.turn * side, 0, 0)
		out[`Hind{tag}2`] = raise(side, 0.5 * paddle)
	end
	-- The head bobs with the strokes, looks into turns and now and then about
	local look = 0.12 * math.sin(m.t * 0.13 + m.phase) + 0.3 * m.turn
	out.Neck = CFrame.Angles(0.05 * math.sin(TAU * u + 1), -look, 0)
	out.Head = CFrame.Angles(0.04 * math.sin(TAU * u + 2), -0.4 * look, 0)
	out.Tail = CFrame.Angles(0, 0.1 * math.sin(TAU * u) - 0.25 * m.turn, 0)
	out.Shell = CFrame.identity
	local heave = 0.012 * math.sin(TAU * (u - 0.08))
	local pitch = 0.025 * math.sin(TAU * (u - 0.2))
	return CFrame.new(0, heave, 0) * CFrame.Angles(pitch, 0, -m.bank)
end

-- Whale: a slow vertical stroke of the flukes, the wave growing down the body; the
-- long pectorals held out and a little down, sweeping gently.
local WHALE_SPINE = { "Body", "Spine1", "Spine2", "Spine3", "Flukes" }
local WHALE_AMP = { 0.012, 0.045, 0.09, 0.15, 0.3 }
function AmbientRigs.whale(m: Motion, out: Pose): CFrame
	local base = m.t * TAU / m.period + m.phase
	local before = 0
	for k, name in WHALE_SPINE do
		local a = WHALE_AMP[k] * math.sin(base - (k - 1) * 0.65)
		out[name] = CFrame.Angles(a - before, 0, 0)
		before = a
	end
	local slow = base * 0.5
	for _, s in sides() do
		out[`Pec{s.tag}1`] = sweep(s.side, 0.06 * math.sin(slow))
			* raise(s.side, -0.08 + 0.1 * math.sin(slow - 0.4))
		out[`Pec{s.tag}2`] = raise(s.side, 0.08 * math.sin(slow - 1.1))
	end
	local heave = 0.004 * math.sin(base + math.pi)
	return CFrame.new(0, heave, 0) * CFrame.Angles(0, 0, -m.bank)
end

-- Crab: scuttling, the legs lift and reach in a wave (the two sides out of step), the
-- claws held up and a little open and the body bobs; resting, it tidies its claws,
-- picks at the floor and lifts one now and then, its eye stalks looking about.
-- `alarm` (0 .. 1: a fish too small to eat it has come close) raises it on its legs,
-- claws up, spread and snapping, eyes up.
function AmbientRigs.crab(m: Motion, out: Pose): CFrame
	local p = m.phase
	local alarm = m.alarm or 0
	local up = math.max(if m.moving then 0.6 else 0, alarm)
	for _, s in sides() do
		local tag, side = s.tag, s.side
		for k = 1, 3 do
			local name = `Leg{tag}{k}`
			if m.moving then
				local g = m.t * 15 + k * 2.1 + (if side < 0 then 0 else math.pi) + p
				local lift = math.max(0, math.sin(g)) * 0.42
				out[name] = sweep(side, 0.2 * math.cos(g)) * raise(side, lift)
			else
				out[name] = raise(side, 0.03 * math.sin(m.t * 0.7 + k + p) - 0.1 * alarm)
			end
		end
		-- Claws: at rest picking at the floor in turns and lifting one now and then;
		-- up, spread and open while it scuttles or squares up to a fish
		local pick = math.max(0, math.sin(m.t * 1.1 + p + (if side < 0 then 0 else 2.2))) ^ 3
		local wave = math.max(0, math.sin(m.t * 0.23 + p * 3 + side)) ^ 12
		local pitch = 0.3 * pick * (1 - up) + 0.75 * up
		local arm = (0.22 * pick + 0.55 * wave) * (1 - up) + 0.3 * up
		out[`Claw{tag}1`] = sweep(side, 0.28 * up) * raise(side, arm) * CFrame.Angles(pitch, 0, 0)
		local snap = math.max(0, math.sin(m.t * (3.1 + 6 * alarm) + p * 2 + side)) ^ 6
		out[`Claw{tag}2`] = CFrame.Angles(0, side * (0.35 * snap + 0.25 * up), 0)
		-- Eye stalks: looking about, straight up when alarmed
		local calm = 1 - 0.7 * alarm
		out[`Eye{tag}`] = CFrame.Angles(
			(0.18 * math.sin(m.t * 0.6 + p + side) - 0.15 * alarm) * calm,
			0,
			side * 0.22 * math.sin(m.t * 0.37 + p * 2 + side) * calm
		)
	end
	local bob = if m.moving then math.abs(math.sin(m.t * 15 + p)) * 0.02 else 0
	out.Body = CFrame.identity
	return CFrame.new(0, bob + 0.03 * alarm, 0) * CFrame.Angles(0.07 * alarm, 0, 0)
end

local POSERS: { [string]: (Motion, Pose) -> CFrame } = {
	manta = AmbientRigs.manta,
	stingray = AmbientRigs.stingray,
	turtle = AmbientRigs.turtle,
	whale = AmbientRigs.whale,
	crab = AmbientRigs.crab,
}

-- Poses rig `rig` into `out`; returns the body's offset (unit studs)
function AmbientRigs.pose(rig: string, m: Motion, out: Pose): CFrame
	return POSERS[rig](m, out)
end

----------------------------------------------------------------------------------
-- The part-built stand-ins: low-poly bodies of flat triangles and a few blocks, on
-- the same joints. Built once per kind at unit size; the controller clones and scales.

-- Two WedgeParts that fill triangle abc (thickness `thick` across it)
function AmbientRigs.wedges(
	a: Vector3,
	b: Vector3,
	c: Vector3,
	thick: number
): { { size: Vector3, cframe: CFrame } }
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	return {
		{
			size = Vector3.new(thick, height, math.abs(ab:Dot(back))),
			cframe = CFrame.fromMatrix((a + b) / 2, right, up, back),
		},
		{
			size = Vector3.new(thick, height, math.abs(ac:Dot(back))),
			cframe = CFrame.fromMatrix((a + c) / 2, -right, up, -back),
		},
	}
end

-- A builder: joints and pieces, a left half written once and mirrored onto the right
-- (names carry "{S}" for the side's tag; a point's X is negated on the right)
type Builder = {
	joints: { Joint },
	pieces: { Piece },
}

local function newBuilder(): Builder
	return { joints = {}, pieces = {} }
end

local function sided(name: string, tag: string): string
	return (string.gsub(name, "{S}", tag))
end

local function flip(v: Vector3, side: number): Vector3
	return Vector3.new(math.abs(v.X) * side, v.Y, v.Z)
end

local function joint(b: Builder, name: string, parent: string?, at: Vector3)
	if string.find(name, "{S}", 1, true) then
		for _, s in sides() do
			table.insert(b.joints, {
				name = sided(name, s.tag),
				parent = if parent then sided(parent, s.tag) else nil,
				at = flip(at, s.side),
			})
		end
	else
		table.insert(b.joints, { name = name, parent = parent, at = at })
	end
end

-- Points by name: "{S}" names are the left half's (X <= 0), mirrored for the right
local function tri(
	b: Builder,
	points: { [string]: Vector3 },
	jointName: string,
	role: string,
	names: { string },
	thick: number?
)
	local mirrored = string.find(jointName, "{S}", 1, true) ~= nil
	for _, n in names do
		if string.find(n, "{S}", 1, true) then
			mirrored = true
		end
	end
	local list = if mirrored then sides() else { { side = -1, tag = "" } }
	for _, s in list do
		-- (on a mirrored piece every point goes to its side: a point on the middle line
		-- stays there, a left-half point named without "{S}" is mirrored too)
		local function at(n: string): Vector3
			local p = points[(string.gsub(n, "{S}", ""))]
			assert(p, n)
			return if mirrored then flip(p, s.side) else p
		end
		table.insert(b.pieces, {
			joint = sided(jointName, s.tag),
			role = role,
			shape = "tri",
			a = at(names[1]),
			b = at(names[2]),
			c = at(names[3]),
			thick = thick or 0.012,
		})
	end
end

-- One part (mirrored when the joint name has "{S}": its CFrame reflected across X)
local function part(b: Builder, jointName: string, role: string, shape: string, size: Vector3, cframe: CFrame)
	if string.find(jointName, "{S}", 1, true) then
		for _, s in sides() do
			local frame = cframe
			if s.side > 0 then
				-- Reflect across the X = 0 plane: mirror the position and the axes
				local p = cframe.Position
				local r, u, k = cframe.RightVector, cframe.UpVector, -cframe.LookVector
				local function m(v: Vector3): Vector3
					return Vector3.new(-v.X, v.Y, v.Z)
				end
				-- (a reflection flips handedness; turning its right axis back keeps it a
				-- rotation, which for these symmetric pieces is the same shape)
				frame = CFrame.fromMatrix(m(p), -m(r), m(u), m(k))
			end
			table.insert(b.pieces, {
				joint = sided(jointName, s.tag),
				role = role,
				shape = shape,
				size = size,
				cframe = frame,
			})
		end
	else
		table.insert(
			b.pieces,
			{ joint = jointName, role = role, shape = shape, size = size, cframe = cframe }
		)
	end
end

local function V(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- Manta, unit span: a ridged diamond body, triangular wings of three panels each (the
-- shoulder panels in the pale chevron), curled cephalic fins, a whip tail
local function mantaPlan(): Plan
	local b = newBuilder()
	joint(b, "Body", nil, V(0, 0, 0))
	joint(b, "Wing{S}1", "Body", V(-0.1, 0, -0.02))
	joint(b, "Wing{S}2", "Wing{S}1", V(-0.235, 0, 0.03))
	joint(b, "Wing{S}3", "Wing{S}2", V(-0.37, 0, 0.08))
	joint(b, "Horn{S}", "Body", V(-0.07, 0, -0.24))
	joint(b, "Tail1", "Body", V(0, 0.005, 0.17))
	joint(b, "Tail2", "Tail1", V(0, 0.005, 0.3))
	local p: { [string]: Vector3 } = {
		N = V(0, 0.015, -0.27),
		R1 = V(0, 0.07, -0.11),
		R2 = V(0, 0.065, 0.07),
		T = V(0, 0.025, 0.18),
		M = V(-0.075, 0, -0.25),
		S = V(-0.105, 0.018, -0.13),
		B = V(-0.1, 0.018, 0.1),
		W1f = V(-0.235, 0.008, -0.07),
		W1b = V(-0.235, 0.008, 0.1),
		W2f = V(-0.37, 0.004, 0.02),
		W2b = V(-0.37, 0.004, 0.13),
		Tip = V(-0.5, 0, 0.11),
		Hb = V(-0.105, 0.005, -0.21),
		Hm = V(-0.11, 0, -0.31),
		Ht = V(-0.07, -0.012, -0.36),
	}
	tri(b, p, "Body", "top", { "N", "M{S}", "R1" })
	tri(b, p, "Body", "top", { "M{S}", "S{S}", "R1" })
	tri(b, p, "Body", "top2", { "S{S}", "R2", "R1" })
	tri(b, p, "Body", "top", { "S{S}", "B{S}", "R2" })
	tri(b, p, "Body", "top2", { "B{S}", "T", "R2" })
	tri(b, p, "Wing{S}1", "patch", { "S{S}", "W1f{S}", "B{S}" })
	tri(b, p, "Wing{S}1", "top", { "B{S}", "W1f{S}", "W1b{S}" })
	tri(b, p, "Wing{S}2", "top", { "W1f{S}", "W2f{S}", "W1b{S}" })
	tri(b, p, "Wing{S}2", "top2", { "W1b{S}", "W2f{S}", "W2b{S}" })
	tri(b, p, "Wing{S}3", "top", { "W2f{S}", "Tip{S}", "W2b{S}" })
	tri(b, p, "Horn{S}", "dark", { "M{S}", "Hb{S}", "Hm{S}" }, 0.02)
	tri(b, p, "Horn{S}", "dark", { "M{S}", "Hm{S}", "Ht{S}" }, 0.02)
	-- The pale belly under the body, the mouth, eyes, a little dorsal fin and the tail
	part(b, "Body", "belly", "block", V(0.19, 0.02, 0.36), CFrame.new(0, -0.012, -0.06))
	part(b, "Body", "dark", "block", V(0.13, 0.03, 0.03), CFrame.new(0, -0.004, -0.265))
	part(b, "Horn{S}", "eye", "ball", V(0.022, 0.022, 0.022), CFrame.new(-0.112, 0.008, -0.2))
	part(b, "Body", "top", "wedge", V(0.008, 0.045, 0.06), CFrame.new(0, 0.085, 0.13))
	part(b, "Tail1", "dark", "block", V(0.014, 0.012, 0.14), CFrame.new(0, 0.01, 0.24))
	part(b, "Tail2", "dark", "block", V(0.008, 0.008, 0.16), CFrame.new(0, 0.01, 0.38))
	return { joints = b.joints, pieces = b.pieces, measure = "X", floor = 0.03 }
end

-- The height of the stand-in's top surface at (x, z): the plane of whichever of the
-- named triangles (left half; the right is the mirror) holds that point, for setting
-- spots on the skin
local function surfaceY(points: { [string]: Vector3 }, tris: { { string } }, x: number, z: number): number
	local ax = -math.abs(x)
	for _, t in tris do
		local a = points[(string.gsub(t[1], "{S}", ""))]
		local b = points[(string.gsub(t[2], "{S}", ""))]
		local c = points[(string.gsub(t[3], "{S}", ""))]
		local a2, b2, c2 =
			Vector3.new(-math.abs(a.X), a.Y, a.Z),
			Vector3.new(-math.abs(b.X), b.Y, b.Z),
			Vector3.new(-math.abs(c.X), c.Y, c.Z)
		local d = (b2.Z - c2.Z) * (a2.X - c2.X) + (c2.X - b2.X) * (a2.Z - c2.Z)
		if math.abs(d) > 1e-9 then
			local u = ((b2.Z - c2.Z) * (ax - c2.X) + (c2.X - b2.X) * (z - c2.Z)) / d
			local v = ((c2.Z - a2.Z) * (ax - c2.X) + (a2.X - c2.X) * (z - c2.Z)) / d
			local w = 1 - u - v
			if u >= -1e-6 and v >= -1e-6 and w >= -1e-6 then
				return u * a2.Y + v * b2.Y + w * c2.Y
			end
		end
	end
	return 0
end

-- A block from `from` to `to` (a leg's segment, a claw's arm), `w` wide and `h` tall
local function seg(
	b: Builder,
	jointName: string,
	role: string,
	from: Vector3,
	to: Vector3,
	w: number,
	h: number
)
	local span = to - from
	local up = if math.abs(span.Unit.Y) > 0.95 then Vector3.new(0, 0, -1) else Vector3.new(0, 1, 0)
	part(
		b,
		jointName,
		role,
		"block",
		Vector3.new(w, h, span.Magnitude),
		CFrame.lookAt((from + to) / 2, to, up)
	)
end

-- A row of triangles, each { a, b, c, joint, role }
local function tris(b: Builder, points: { [string]: Vector3 }, list: { { string } }, thick: number?)
	for _, t in list do
		tri(b, points, t[4], t[5], { t[1], t[2], t[3] }, thick)
	end
end

-- Stingray, unit disc width (span), its middle where the model's is (the disc from
-- 0.8 ahead of it to 0.16 behind, the tail to 0.8): a faceted dome over a heart-shaped
-- disc whose margin is in three stations a side (each two bones, inner and outer), a
-- pale underside, eyes on the dome, blue spots, and a tapering tail with a blue stripe
-- and its barb
local function stingrayPlan(): Plan
	local b = newBuilder()
	joint(b, "Body", nil, V(0, 0, 0))
	for _, st in { { name = "F", z = -0.58 }, { name = "M", z = -0.3 }, { name = "B", z = -0.04 } } do
		local name, z = st.name, st.z
		joint(b, `Fin\{S}{name}1`, "Body", V(-0.17, 0.02, z))
		joint(b, `Fin\{S}{name}2`, `Fin\{S}{name}1`, V(-0.33, 0.01, z))
	end
	joint(b, "Tail1", "Body", V(0, 0.03, 0.15))
	joint(b, "Tail2", "Tail1", V(0, 0.03, 0.42))
	joint(b, "Tail3", "Tail2", V(0, 0.03, 0.62))
	local p: { [string]: Vector3 } = {
		N = V(0, 0.01, -0.8),
		C = V(0, 0.1, -0.32),
		T0 = V(0, 0.035, 0.15),
		I1 = V(-0.14, 0.055, -0.58),
		I2 = V(-0.19, 0.065, -0.3),
		I3 = V(-0.15, 0.055, -0.02),
		P1 = V(-0.2, 0.004, -0.74),
		P2 = V(-0.39, 0, -0.57),
		P3 = V(-0.5, 0, -0.32),
		P4 = V(-0.46, 0, -0.05),
		P5 = V(-0.24, 0.01, 0.13),
	}
	local list = {
		{ "N", "I1{S}", "C", "Body", "top" },
		{ "I1{S}", "I2{S}", "C", "Body", "top2" },
		{ "I2{S}", "I3{S}", "C", "Body", "top" },
		{ "I3{S}", "T0", "C", "Body", "top2" },
		{ "N", "P1{S}", "I1{S}", "Fin{S}F2", "top2" },
		{ "I1{S}", "P1{S}", "P2{S}", "Fin{S}F2", "top" },
		{ "I1{S}", "P2{S}", "I2{S}", "Fin{S}F1", "top2" },
		{ "I2{S}", "P2{S}", "P3{S}", "Fin{S}M2", "top" },
		{ "I2{S}", "P3{S}", "P4{S}", "Fin{S}M2", "top2" },
		{ "I2{S}", "P4{S}", "I3{S}", "Fin{S}M1", "top" },
		{ "I3{S}", "P4{S}", "P5{S}", "Fin{S}B2", "top2" },
		{ "I3{S}", "P5{S}", "T0", "Fin{S}B1", "top" },
	}
	tris(b, p, list, 0.014)
	-- The pale underside, a little inside the outline
	part(b, "Body", "belly", "block", V(0.5, 0.025, 0.62), CFrame.new(0, -0.012, -0.31))
	part(b, "Body", "belly", "block", V(0.22, 0.02, 0.16), CFrame.new(0, -0.01, -0.67))
	-- Eyes up on the dome, behind the snout
	for _, x in { -0.065, 0.065 } do
		part(
			b,
			"Body",
			"eye",
			"ball",
			V(0.04, 0.03, 0.045),
			CFrame.new(x, surfaceY(p, list, x, -0.5) + 0.012, -0.5)
		)
	end
	-- Blue spots, flat on the skin wherever they fall (each on the panel under it)
	local spots = {
		{ -0.06, -0.38, "Body" },
		{ -0.1, -0.16, "Body" },
		{ -0.05, -0.02, "Body" },
		{ -0.24, -0.62, "Fin{S}F2" },
		{ -0.21, -0.47, "Fin{S}F1" },
		{ -0.34, -0.5, "Fin{S}F2" },
		{ -0.3, -0.33, "Fin{S}M2" },
		{ -0.42, -0.25, "Fin{S}M2" },
		{ -0.28, -0.14, "Fin{S}M1" },
		{ -0.36, -0.06, "Fin{S}M2" },
		{ -0.26, 0.05, "Fin{S}B2" },
	}
	for i, s in spots do
		local x, z, j = s[1], s[2], s[3]
		local d = if i % 3 == 0 then 0.055 else 0.04
		local y = surfaceY(p, list, x, z) + 0.009
		-- (a panel's spot is mirrored with its joint; one on the body is set on each side)
		for _, at in if j == "Body" then { x, -x } else { x } do
			part(b, j, "spot", "cyl", V(0.006, d, d), CFrame.new(at, y, z) * CFrame.Angles(0, 0, math.pi / 2))
		end
	end
	-- The tail: tapering, a blue stripe along its top, the barb
	part(b, "Tail1", "top", "block", V(0.075, 0.045, 0.28), CFrame.new(0, 0.03, 0.29))
	part(b, "Tail1", "spot", "block", V(0.022, 0.012, 0.26), CFrame.new(0, 0.056, 0.29))
	part(b, "Tail2", "top", "block", V(0.045, 0.032, 0.21), CFrame.new(0, 0.03, 0.52))
	part(b, "Tail2", "spot", "block", V(0.016, 0.01, 0.2), CFrame.new(0, 0.048, 0.52))
	part(b, "Tail2", "dark", "wedge", V(0.012, 0.035, 0.1), CFrame.new(0, 0.06, 0.5))
	part(b, "Tail3", "top", "block", V(0.024, 0.02, 0.19), CFrame.new(0, 0.03, 0.715))
	return { joints = b.joints, pieces = b.pieces, measure = "X", floor = 0.03 }
end

-- Turtle, unit length beak to tail, its middle where the model's is: a domed shell of
-- scute plates (the central row and the side rows in two greens, a darker rim) over a
-- flat pale plastron, a short neck and a beaked head, long tapering paddle front
-- flippers in three panels swept a little back, short hind paddles, a stub of a tail
local function turtlePlan(): Plan
	local b = newBuilder()
	joint(b, "Shell", nil, V(0, 0, 0))
	joint(b, "Neck", "Shell", V(0, 0.0, -0.31))
	joint(b, "Head", "Neck", V(0, 0.0, -0.39))
	joint(b, "Fin{S}1", "Shell", V(-0.23, -0.02, -0.2))
	joint(b, "Fin{S}2", "Fin{S}1", V(-0.37, -0.03, -0.21))
	joint(b, "Fin{S}3", "Fin{S}2", V(-0.5, -0.04, -0.2))
	joint(b, "Hind{S}1", "Shell", V(-0.15, -0.04, 0.3))
	joint(b, "Hind{S}2", "Hind{S}1", V(-0.22, -0.05, 0.38))
	joint(b, "Tail", "Shell", V(0, -0.03, 0.36))
	local p: { [string]: Vector3 } = {
		A = V(0, 0.16, 0.02),
		M0 = V(0, 0.13, -0.2),
		M1 = V(-0.16, 0.12, -0.1),
		M2 = V(-0.17, 0.11, 0.13),
		M3 = V(0, 0.115, 0.25),
		E0 = V(0, 0.03, -0.33),
		E1 = V(-0.23, 0.03, -0.22),
		E2 = V(-0.3, 0.02, 0.0),
		E3 = V(-0.25, 0.01, 0.23),
		E4 = V(0, 0.0, 0.37),
		-- the front flipper's leading and trailing edges, and its tip
		L0 = V(-0.22, -0.02, -0.25),
		L1 = V(-0.37, -0.03, -0.265),
		L2 = V(-0.5, -0.04, -0.24),
		T = V(-0.63, -0.05, -0.12),
		R0 = V(-0.22, -0.02, -0.14),
		R1 = V(-0.37, -0.03, -0.165),
		R2 = V(-0.5, -0.04, -0.165),
		-- the hind paddle
		H0 = V(-0.12, -0.04, 0.28),
		H1 = V(-0.2, -0.045, 0.27),
		H2 = V(-0.25, -0.05, 0.37),
		H3 = V(-0.27, -0.055, 0.48),
		H4 = V(-0.14, -0.045, 0.37),
	}
	tris(b, p, {
		{ "A", "M0", "M1{S}", "Shell", "scute" },
		{ "A", "M1{S}", "M2{S}", "Shell", "scute2" },
		{ "A", "M2{S}", "M3", "Shell", "scute" },
		{ "M0", "E0", "E1{S}", "Shell", "rim" },
		{ "M0", "E1{S}", "M1{S}", "Shell", "scute2" },
		{ "M1{S}", "E1{S}", "E2{S}", "Shell", "rim" },
		{ "M1{S}", "E2{S}", "M2{S}", "Shell", "scute" },
		{ "M2{S}", "E2{S}", "E3{S}", "Shell", "rim" },
		{ "M2{S}", "E3{S}", "M3", "Shell", "scute2" },
		{ "M3", "E3{S}", "E4", "Shell", "rim" },
	})
	tris(b, p, {
		{ "L0", "L1", "R0", "Fin{S}1", "skin" },
		{ "L1", "R1", "R0", "Fin{S}1", "skin2" },
		{ "L1", "L2", "R1", "Fin{S}2", "skin2" },
		{ "L2", "R2", "R1", "Fin{S}2", "skin" },
		{ "L2", "T", "R2", "Fin{S}3", "skin2" },
		{ "H0", "H1", "H4", "Hind{S}1", "skin" },
		{ "H1", "H2", "H4", "Hind{S}1", "skin2" },
		{ "H2", "H3", "H4", "Hind{S}2", "skin" },
	}, 0.022)
	-- The plastron under it, the neck, a beaked head with eyes, the tail
	part(b, "Shell", "belly", "block", V(0.44, 0.05, 0.54), CFrame.new(0, -0.02, 0.02))
	part(
		b,
		"Neck",
		"skin",
		"block",
		V(0.1, 0.075, 0.13),
		CFrame.new(0, -0.005, -0.35) * CFrame.Angles(0.1, 0, 0)
	)
	part(b, "Head", "skin", "block", V(0.12, 0.08, 0.11), CFrame.new(0, 0.005, -0.435))
	part(
		b,
		"Head",
		"skin2",
		"wedge",
		V(0.12, 0.035, 0.07),
		CFrame.new(0, 0.062, -0.45) * CFrame.Angles(0, math.pi, 0)
	)
	part(
		b,
		"Head",
		"beak",
		"wedge",
		V(0.08, 0.06, 0.05),
		CFrame.new(0, -0.012, -0.513) * CFrame.Angles(0, math.pi, 0)
	)
	part(b, "Head", "eye", "ball", V(0.026, 0.026, 0.026), CFrame.new(-0.058, 0.02, -0.46))
	part(b, "Head", "eye", "ball", V(0.026, 0.026, 0.026), CFrame.new(0.058, 0.02, -0.46))
	part(
		b,
		"Tail",
		"skin",
		"wedge",
		V(0.04, 0.03, 0.08),
		CFrame.new(0, -0.03, 0.4) * CFrame.Angles(0, math.pi, 0)
	)
	return { joints = b.joints, pieces = b.pieces, measure = "Z", floor = 0.07 }
end

-- Humpback, unit length: a faceted body of diamond sections (dark back, pale grooved
-- belly), long pectorals, broad flukes, a small dorsal fin
local function whalePlan(): Plan
	local b = newBuilder()
	joint(b, "Body", nil, V(0, 0, -0.18))
	joint(b, "Spine1", "Body", V(0, 0, -0.04))
	joint(b, "Spine2", "Spine1", V(0, 0, 0.1))
	joint(b, "Spine3", "Spine2", V(0, 0, 0.22))
	joint(b, "Flukes", "Spine3", V(0, 0, 0.34))
	joint(b, "Pec{S}1", "Body", V(-0.1, -0.06, -0.16))
	joint(b, "Pec{S}2", "Pec{S}1", V(-0.2, -0.08, -0.06))
	local function ring(
		name: string,
		z: number,
		w: number,
		top: number,
		bottom: number
	): { [string]: Vector3 }
		return {
			[name .. "t"] = V(0, top, z),
			[name .. "s"] = V(-w, (top + bottom) * 0.35, z),
			[name .. "b"] = V(0, bottom, z),
		}
	end
	local p: { [string]: Vector3 } = { N = V(0, -0.01, -0.5) }
	for _, r in
		{
			ring("A", -0.34, 0.085, 0.07, -0.085),
			ring("B", -0.08, 0.115, 0.095, -0.105),
			ring("C", 0.16, 0.075, 0.07, -0.06),
			ring("D", 0.34, 0.03, 0.03, -0.025),
		}
	do
		for k, v in r do
			p[k] = v
		end
	end
	p.Ft = V(-0.17, 0.0, 0.47)
	p.Fn = V(0, 0.0, 0.45)
	p.Fb = V(-0.06, 0.0, 0.52)
	p.Pr = V(-0.1, -0.06, -0.19)
	p.Pq = V(-0.1, -0.07, -0.12)
	p.Pm = V(-0.21, -0.09, -0.08)
	p.Pn = V(-0.2, -0.09, -0.02)
	p.Pt = V(-0.33, -0.11, 0.05)
	tri(b, p, "Body", "top", { "N", "At", "As{S}" })
	tri(b, p, "Body", "belly", { "N", "As{S}", "Ab" })
	local spans = { { "A", "B", "Body" }, { "B", "C", "Spine1" }, { "C", "D", "Spine2" } }
	for _, sp in spans do
		local f, k, j = sp[1], sp[2], sp[3]
		tri(b, p, j, "top", { f .. "t", k .. "t", f .. "s{S}" })
		tri(b, p, j, "top2", { k .. "t", k .. "s{S}", f .. "s{S}" })
		tri(b, p, j, "belly", { f .. "b", f .. "s{S}", k .. "b" })
		tri(b, p, j, "belly2", { k .. "b", f .. "s{S}", k .. "s{S}" })
	end
	tri(b, p, "Spine3", "top", { "Dt", "Ds{S}", "Fn" })
	tri(b, p, "Spine3", "belly", { "Db", "Ds{S}", "Fn" })
	tri(b, p, "Flukes", "top", { "Fn", "Ft{S}", "Fb{S}" })
	tri(b, p, "Pec{S}1", "top", { "Pr{S}", "Pm{S}", "Pq{S}" })
	tri(b, p, "Pec{S}1", "top2", { "Pq{S}", "Pm{S}", "Pn{S}" })
	tri(b, p, "Pec{S}2", "top", { "Pm{S}", "Pt{S}", "Pn{S}" })
	part(b, "Spine1", "top", "wedge", V(0.012, 0.04, 0.07), CFrame.new(0, 0.1, 0.1))
	return { joints = b.joints, pieces = b.pieces, measure = "Z", floor = 0.1 }
end

-- The crab's shell (unit width across the legs, as the model): an apex over a rim of
-- five points a side; what it carries sits on these facets (AmbientRigs.extras)
local CRAB_SHELL: { [string]: Vector3 } = {
	A = V(0, 0.27, 0.08),
	E0 = V(0, 0.1, -0.16),
	E1 = V(-0.25, 0.08, -0.12),
	E2 = V(-0.37, 0.06, 0.05),
	E3 = V(-0.29, 0.05, 0.26),
	E4 = V(0, 0.07, 0.36),
}
local CRAB_FACETS = {
	{ "A", "E0", "E1{S}", "Body", "top" },
	{ "A", "E1{S}", "E2{S}", "Body", "top2" },
	{ "A", "E2{S}", "E3{S}", "Body", "top" },
	{ "A", "E3{S}", "E4", "Body", "top2" },
}

-- Crab, unit width across the legs, its middle where the model's is (feet 0.27 below
-- it): a faceted shell domed over a pale underside, eye stalks, three jointed legs a
-- side and two big claws (arm, palm and dark-tipped fingers)
local function crabPlan(): Plan
	local b = newBuilder()
	joint(b, "Body", nil, V(0, 0, 0))
	joint(b, "Claw{S}1", "Body", V(-0.19, 0.04, -0.1))
	joint(b, "Claw{S}2", "Claw{S}1", V(-0.27, 0.03, -0.25))
	joint(b, "Eye{S}", "Body", V(-0.08, 0.1, -0.14))
	local legs = {
		{ z = -0.02, knee = -0.07, foot = -0.13 },
		{ z = 0.1, knee = 0.11, foot = 0.13 },
		{ z = 0.22, knee = 0.29, foot = 0.37 },
	}
	for k, leg in legs do
		joint(b, `Leg\{S}{k}`, "Body", V(-0.3, 0.04, leg.z))
	end
	tris(b, CRAB_SHELL, CRAB_FACETS, 0.03)
	-- The underside, the mouth, a little spike at each front corner
	part(b, "Body", "belly", "block", V(0.52, 0.1, 0.4), CFrame.new(0, 0.02, 0.1))
	part(
		b,
		"Body",
		"dark",
		"wedge",
		V(0.12, 0.06, 0.05),
		CFrame.new(0, 0.05, -0.15) * CFrame.Angles(0, math.pi, 0)
	)
	for _, side in { -1, 1 } do
		part(
			b,
			"Body",
			"top2",
			"wedge",
			V(0.03, 0.04, 0.08),
			CFrame.new(0.36 * side, 0.07, -0.03) * CFrame.Angles(0, math.rad(-60 * side), 0)
		)
	end
	-- Eye stalks
	part(b, "Eye{S}", "top", "block", V(0.026, 0.08, 0.026), CFrame.new(-0.08, 0.14, -0.15))
	part(b, "Eye{S}", "eye", "ball", V(0.045, 0.045, 0.045), CFrame.new(-0.08, 0.185, -0.155))
	-- Claws: an arm out and forward, a big palm, two dark-tipped fingers
	seg(b, "Claw{S}1", "top", V(-0.19, 0.04, -0.1), V(-0.27, 0.03, -0.25), 0.075, 0.06)
	part(
		b,
		"Claw{S}2",
		"claw",
		"block",
		V(0.12, 0.1, 0.17),
		CFrame.new(-0.28, 0.04, -0.33) * CFrame.Angles(0, -0.2, 0)
	)
	part(
		b,
		"Claw{S}2",
		"dark",
		"wedge",
		V(0.06, 0.05, 0.1),
		CFrame.new(-0.3, 0.02, -0.45) * CFrame.Angles(math.pi, -0.2, 0)
	)
	part(
		b,
		"Claw{S}2",
		"dark",
		"wedge",
		V(0.045, 0.04, 0.08),
		CFrame.new(-0.25, 0.075, -0.44) * CFrame.Angles(0, -0.2, 0)
	)
	-- Legs: up and out to the knee, down to the foot
	for k, leg in legs do
		local hip = V(-0.3, 0.04, leg.z)
		local knee = V(-0.44, 0.1, leg.knee)
		local foot = V(-0.53, -0.27, leg.foot)
		seg(b, `Leg\{S}{k}`, "top", hip, knee, 0.05, 0.045)
		seg(b, `Leg\{S}{k}`, "top2", knee, foot, 0.04, 0.035)
	end
	return { joints = b.joints, pieces = b.pieces, measure = "X", floor = 0.27 }
end

local plans: { [string]: Plan } = {}

function AmbientRigs.plan(rig: string): Plan
	local known = plans[rig]
	if known then
		return known
	end
	local made: Plan
	if rig == "manta" then
		made = mantaPlan()
	elseif rig == "stingray" then
		made = stingrayPlan()
	elseif rig == "turtle" then
		made = turtlePlan()
	elseif rig == "whale" then
		made = whalePlan()
	else
		made = crabPlan()
	end
	plans[rig] = made
	return made
end

-- What a crab carries on its shell (Config/Forage `extras`), unit width like the crab:
-- built onto its "Body" (an imported crab's mesh, or the stand-in's shell; a stand-in
-- also takes the pieces on its claws). "sponge": a decorator crab's garden of tube
-- sponges, a ball sponge, a fan and weed; "barnacles": a stone crab's; "fuzz": a yeti
-- crab's teal bristles (on the shell's front and, part-built, its claws); "spikes": a
-- king crab's
function AmbientRigs.extras(name: string): { Piece }
	local b = newBuilder()
	local function on(x: number, z: number): number
		return surfaceY(CRAB_SHELL, CRAB_FACETS, x, z)
	end
	if name == "sponge" then
		for _, s in { { -0.1, 0.12, 0.13, 0.06 }, { -0.04, 0.17, 0.09, 0.05 }, { 0.14, 0.22, 0.1, 0.05 } } do
			local x, z, h, d = s[1], s[2], s[3], s[4]
			part(
				b,
				"Body",
				"extra",
				"cyl",
				V(h, d, d),
				CFrame.new(x, on(x, z) + h * 0.4, z) * CFrame.Angles(0, 0, math.pi / 2)
			)
		end
		part(b, "Body", "extra2", "ball", V(0.09, 0.09, 0.09), CFrame.new(0.1, on(0.1, 0.06) + 0.025, 0.06))
		part(
			b,
			"Body",
			"extra3",
			"wedge",
			V(0.015, 0.11, 0.08),
			CFrame.new(-0.2, on(-0.2, 0.05) + 0.04, 0.05) * CFrame.Angles(0, 0.4, 0.25)
		)
		part(
			b,
			"Body",
			"extra3",
			"wedge",
			V(0.015, 0.09, 0.07),
			CFrame.new(0.22, on(0.22, 0.14) + 0.03, 0.14) * CFrame.Angles(0, -0.7, -0.3)
		)
		part(
			b,
			"Body",
			"extra2",
			"wedge",
			V(0.012, 0.1, 0.1),
			CFrame.new(0.02, on(0.02, 0.27) + 0.04, 0.27) * CFrame.Angles(0, 1.2, 0)
		)
	elseif name == "barnacles" then
		for _, s in { { -0.12, 0.0 }, { 0.08, 0.1 }, { -0.04, 0.24 }, { 0.2, 0.2 }, { -0.22, 0.14 } } do
			local x, z = s[1], s[2]
			part(
				b,
				"Body",
				"barnacle",
				"cyl",
				V(0.045, 0.06, 0.06),
				CFrame.new(x, on(x, z) + 0.015, z) * CFrame.Angles(0, 0, math.pi / 2)
			)
			part(
				b,
				"Body",
				"dark",
				"cyl",
				V(0.05, 0.022, 0.022),
				CFrame.new(x, on(x, z) + 0.02, z) * CFrame.Angles(0, 0, math.pi / 2)
			)
		end
	elseif name == "fuzz" then
		for _, s in
			{
				{ -0.24, -0.11 },
				{ -0.12, -0.15 },
				{ 0.12, -0.15 },
				{ 0.24, -0.11 },
				{ -0.33, 0.04 },
				{ 0.33, 0.04 },
			}
		do
			local x, z = s[1], s[2]
			part(
				b,
				"Body",
				"bristle",
				"wedge",
				V(0.06, 0.05, 0.035),
				CFrame.new(x, on(x, z) + 0.012, z) * CFrame.Angles(0, math.atan2(x, -z), 0)
			)
		end
		part(
			b,
			"Claw{S}2",
			"bristle",
			"block",
			V(0.13, 0.03, 0.15),
			CFrame.new(-0.29, 0.03, -0.33) * CFrame.Angles(0, -0.2, 0)
		)
		part(
			b,
			"Claw{S}1",
			"bristle",
			"block",
			V(0.08, 0.025, 0.12),
			CFrame.new(-0.23, 0.04, -0.18) * CFrame.Angles(0, 0.45, 0)
		)
	elseif name == "spikes" then
		for _, s in
			{
				{ 0, -0.06 },
				{ -0.12, 0.02 },
				{ 0.12, 0.02 },
				{ -0.2, 0.16 },
				{ 0.2, 0.16 },
				{ 0, 0.22 },
				{ -0.28, -0.04 },
				{ 0.28, -0.04 },
			}
		do
			local x, z = s[1], s[2]
			part(
				b,
				"Body",
				"spike",
				"wedge",
				V(0.045, 0.09, 0.06),
				CFrame.new(x, on(x, z) + 0.035, z) * CFrame.Angles(0, math.atan2(x, -z), 0)
			)
		end
	end
	return b.pieces
end

-- Where each joint is posed, for a pose (forward kinematics from the rest positions):
-- the joint's frame in the creature's own space, unit size
function AmbientRigs.solve(plan: Plan, pose: Pose): { [string]: CFrame }
	local frames: { [string]: CFrame } = {}
	local rest: { [string]: Vector3 } = {}
	for _, j in plan.joints do
		rest[j.name] = j.at
	end
	for _, j in plan.joints do
		local parent = j.parent
		local base = if parent then frames[parent] * CFrame.new(j.at - rest[parent]) else CFrame.new(j.at)
		frames[j.name] = base * (pose[j.name] or CFrame.identity)
	end
	return frames
end

-- Every piece's parts where a pose puts them: { shape, size, cframe, role, joint } in
-- the creature's own space at `size` (the preview draws these; the game builds the same
-- parts once, at rest, and moves them with Motor6Ds). `pieces` (default the plan's own)
-- can be other pieces on the same joints: what a crab carries (AmbientRigs.extras).
export type Built = { shape: string, size: Vector3, cframe: CFrame, role: string, joint: string }
function AmbientRigs.parts(plan: Plan, pose: Pose, size: number, pieces: { Piece }?): { Built }
	local frames = AmbientRigs.solve(plan, pose)
	local rest: { [string]: Vector3 } = {}
	for _, j in plan.joints do
		rest[j.name] = j.at
	end
	local out: { Built } = {}
	for _, piece in pieces or plan.pieces do
		local frame = frames[piece.joint]
		if frame == nil then
			continue -- (a piece for a joint this plan hasn't got)
		end
		-- (the joint's rest frame, undone, then its posed frame)
		local local_ = CFrame.new(-rest[piece.joint])
		if piece.shape == "tri" then
			for _, w in
				AmbientRigs.wedges(
					piece.a :: Vector3,
					piece.b :: Vector3,
					piece.c :: Vector3,
					piece.thick or 0.012
				)
			do
				local at = frame * local_ * w.cframe
				table.insert(out, {
					shape = "wedge",
					size = w.size * size,
					cframe = CFrame.new(at.Position * size) * at.Rotation,
					role = piece.role,
					joint = piece.joint,
				})
			end
		else
			local at = frame * local_ * (piece.cframe :: CFrame)
			table.insert(out, {
				shape = piece.shape,
				size = (piece.size :: Vector3) * size,
				cframe = CFrame.new(at.Position * size) * at.Rotation,
				role = piece.role,
				joint = piece.joint,
			})
		end
	end
	return out
end

return AmbientRigs
