--!strict
-- The start screen's documentary shots (Config/Start): which school a shot can frame,
-- where its camera goes at any moment, and whether that path stays in open water.
-- Everything here is a pure function of the shared clock and the world's config, so
-- the client (StartController, raycasting the real world), the server (StartService:
-- is this school the shot's, where to stream) and the cloud preview
-- (tools/preview/run_start.sh, raycasting the Terrain's fill ops) agree.
--
-- A shot's subject is its school's middle (Schools.schoolFrame, lifted over the
-- ground like every client draws it), averaged over a moment either side so the
-- camera never jitters on the loop's figure-eight. The camera sits in a frame fixed
-- for the whole shot (along the school's travel, or toward a landmark), so it never
-- swings round with the loop: it travels with the school by `follow` (at least
-- enough that the school drifts no more than `drift` of the distance through the
-- frame) and pans to keep it framed, pushing in a little as the shot goes on. Its
-- distance keeps the school's furthest fish a few of its lengths clear of the lens
-- after the push-in (a lone fish: `lengths` of it). `plan` tries the shot's variants
-- (either side, higher, further, closer) until one keeps the camera in open water for
-- the whole shot and the time it may run over (`cast`: a ray against the world, the
-- distance to what it hit or nil), no fish of the school ever comes within that gap
-- of the lens, at least half of them stay in the picture between the letterbox bars
-- at every moment, and the school swims fairly level meanwhile (a small loop with a
-- tall figure-eight climbs at 60-70 degrees; `candidates` puts gentle ones first).
local Config = require(script.Parent.Config)
local Schools = require(script.Parent.Schools)
local Seafloor = require(script.Parent.Seafloor)

local World = Config.World
local Start = Config.Start

export type Shot = typeof(Config.Start.shots[1])
export type Cast = (origin: Vector3, direction: Vector3) -> number?

export type Plan = {
	shot: number,
	school: number,
	t0: number, -- shared-clock time the shot starts
	seconds: number,
	span: number, -- seconds it was checked for (its length and how long it may run over)
	style: string,
	side: number, -- +1 / -1: which side of the school the camera keeps
	distance: number,
	height: number,
	rise: number,
	push: number,
	follow: number,
	sweep: number,
	fov: number,
	floor: number,
	window: number,
	gap: number, -- studs every fish of the school keeps from the lens
	forward: Vector3, -- the shot's fixed frame: along the school's travel or toward the landmark
	right: Vector3,
	anchor: Vector3, -- the subject at t0
	landmark: Vector3?,
	variant: number,
	fails: number, -- checks the path failed (0 for a plan `plan` returns)
}

local StartShots = {}

local UP = Vector3.new(0, 1, 0)
local SURFACE_KEEP = 12 -- studs the camera keeps under the surface
local EDGE_KEEP = 170 -- studs from the map's edge (the water thickens past 240: OceanController)
local PAD = 1.5 -- studs past the camera a ray must also find clear (the near plane)
local STEP = 0.5 -- seconds between the path's checks
local SIDE_RAY = 3 -- studs of open water round the camera
local GAP_LENGTHS = 2.5 -- a fish keeps this many of its lengths from the lens...
local GAP_MIN = 5 -- ...and at least this many studs
local DRIFT = 0.3 -- share of the distance the school may drift through the frame over a shot
local STEEP = 50 -- degrees the school may climb or dive at any moment of a shot
local STEEP_SINE = math.sin(math.rad(STEEP))
local LOOK_ABOVE = 0.05 -- the camera aims this share of its distance over the subject (it sits a little low, clear of the title)
local IN_FRAME = 0.5 -- share of the school that must be in the picture at every moment
-- The picture a fish must be in: the screen between the letterbox bars, a little in
-- from its edges, on a screen at least this wide for its height (16:9 is 1.78; a 4:3
-- tablet's 1.33 trims the sides of a shot, never the school's middle)
local FRAME_HEIGHT = 0.8
local FRAME_ASPECT = 1.5

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function unit(v: Vector3, fallback: Vector3): Vector3
	local m = v.Magnitude
	if m < 1e-6 then
		return fallback
	end
	return v / m
end

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function polar(position: Vector3): (number, number)
	return Seafloor.polar(position.X, position.Z)
end

-- Whether `angle` lies in the sector `from` → `to` (clockwise), `margin` degrees in
-- from both ends
local function inSector(angle: number, from: number, to: number, margin: number): boolean
	local span = (to - from) % 360
	if span == 0 then
		return true
	end
	if span <= 2 * margin then
		return false
	end
	return (angle - from - margin) % 360 < span - 2 * margin
end

-- The shot's place: its biome's sector and radii (narrowed by the shot's own), a
-- margin in from every edge so the camera stays in that biome's water
function StartShots.inPlace(shot: Shot, position: Vector3): boolean
	local biome = Config.Biomes.byId[shot.biome]
	if biome == nil then
		return false
	end
	local r, angle = polar(position)
	local margin = 40
	local low, high = biome.radiusFrom, math.min(biome.radiusTo, World.boundsRadius - EDGE_KEEP)
	if shot.radii then
		low, high = math.max(low, shot.radii[1]), math.min(high, shot.radii[2])
	end
	if r < low + margin or r > high - margin then
		return false
	end
	local degrees = math.deg(margin / math.max(r, 1))
	if not inSector(angle, biome.angleFrom, biome.angleTo, degrees) then
		return false
	end
	if shot.angles and not inSector(angle, shot.angles[1], shot.angles[2], degrees) then
		return false
	end
	-- (the Trench's canyon is its own place: other biomes' shots keep off it)
	if shot.biome ~= "AbyssalTrench" and Seafloor.inTrench(position.X, position.Z, 30) then
		return false
	end
	return true
end

-- The great temple's middle, a little over its platform (Config/Ruins: the city's
-- middle stands `radius` out at `angle`, on the deep floor)
local function templeAt(): Vector3
	local ruins = Config.Ruins
	local a = math.rad(ruins.angle)
	return World.hub.center
		+ Vector3.new(math.cos(a) * ruins.radius, World.deep.floorY + 24, math.sin(a) * ruins.radius)
end

-- What stands behind a shot's school, or nil (a wreck is found by the client, once
-- the area is in, and handed to `plan`)
function StartShots.landmark(shot: Shot, school: number): Vector3?
	local center = Schools.list[school].center
	if shot.landmark == "temple" then
		return templeAt()
	elseif shot.landmark == "basin" then
		local best: { x: number, z: number, radius: number }? = nil
		local bestDistance = math.huge
		for _, basin in Seafloor.ventBasins() do
			local d = math.sqrt((basin.x - center.X) ^ 2 + (basin.z - center.Z) ^ 2)
			if d < bestDistance then
				best, bestDistance = basin, d
			end
		end
		if best == nil or bestDistance < 25 or bestDistance > best.radius + 60 then
			return nil -- (right over its middle: no "beyond" to look toward)
		end
		return Vector3.new(best.x, World.deep.ventsFloorY + 30, best.z)
	elseif shot.landmark == "canyon" then
		-- Further along the canyon's line, toward its middle so it stays inside it
		local trench = World.trench
		local r = polar(center)
		local middle = (trench.radii[1] + trench.radii[2]) / 2
		local along = math.clamp(r + (if r < middle then 170 else -170), trench.radii[1], trench.radii[2])
		local x, z = Seafloor.trenchPoint(along, 0)
		return Vector3.new(x, center.Y, z)
	end
	return nil
end

-- Whether school `index` can be shot `shot`'s subject (the server checks a request
-- with this): one of its prey, out every tide, in its place
function StartShots.fits(shot: Shot, index: number): boolean
	local school = Schools.list[index]
	if school == nil or school.tide ~= nil or table.find(shot.prey, school.prey) == nil then
		return false
	end
	return StartShots.inPlace(shot, school.center)
end

-- How steeply a school climbs and dives on its loop at most (degrees): a small loop
-- with a tall figure-eight has its fish swimming nose-up at 60-70 degrees, which
-- reads oddly in a close shot
local steep: { [number]: number } = {}
function StartShots.steepness(index: number): number
	local known = steep[index]
	if known then
		return known
	end
	local school = Schools.list[index]
	local most = 0
	for k = 0, 47 do
		local a = k / 48 * 2 * math.pi
		local look = Schools.schoolFrame(index, (a - school.phase) / school.angularSpeed).LookVector
		most = math.max(most, math.deg(math.asin(math.clamp(math.abs(look.Y), 0, 1))))
	end
	steep[index] = most
	return most
end

-- Every school shot `shot` can frame, its first prey's first (then the next prey's),
-- the gentlest swimmers of each first. A temple shot takes the schools within
-- `within` of its temple first, whatever their prey (its temple is lost in the haze
-- from further), but not those whose loop runs through the temple itself (it can't
-- stand beyond them), then those, then the rest.
local TEMPLE_CLEAR = 90 -- studs from the temple's middle a school's loop must keep (its platform is ~130 long)
function StartShots.candidates(shot: Shot): { number }
	local found: { { index: number, rank: number, key: number } } = {}
	local temple = if shot.landmark == "temple" then templeAt() else nil
	local within = shot.within or 330
	for index, school in Schools.list do
		local rank = table.find(shot.prey, school.prey)
		if rank and StartShots.fits(shot, index) then
			local away = if temple then (flat(school.center) - flat(temple)).Magnitude else math.huge
			if away <= within then
				rank = if away - school.radius >= TEMPLE_CLEAR then -1 else 0
			end
			table.insert(found, { index = index, rank = rank, key = StartShots.steepness(index) })
		end
	end
	table.sort(found, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.key < b.key
	end)
	local list: { number } = {}
	for _, entry in found do
		table.insert(list, entry.index)
	end
	return list
end

-- Where the school's fish sit on average, in its own frame (a school of four can
-- have its fish mostly to one side of its middle)
local middles: { [number]: Vector3 } = {}
local function middleOf(index: number): Vector3
	local known = middles[index]
	if known then
		return known
	end
	local school = Schools.list[index]
	local sum = Vector3.new(0, 0, 0)
	for i = school.first, school.first + school.count - 1 do
		sum += Schools.fish[i].offset
	end
	local middle = sum / math.max(school.count, 1)
	middles[index] = middle
	return middle
end

-- The school's width (studs): its spread both ways plus one of its fish
function StartShots.width(index: number): number
	local school = Schools.list[index]
	local total = 0
	for i = school.first, school.first + school.count - 1 do
		total += Schools.fish[i].length
	end
	return 2 * school.spread + total / math.max(school.count, 1)
end

-- How far its furthest fish sits from the middle of them all (studs)
function StartShots.furthest(index: number): number
	local school = Schools.list[index]
	local middle = middleOf(index)
	local most = 0
	for i = school.first, school.first + school.count - 1 do
		local fish = Schools.fish[i]
		most = math.max(most, (fish.offset - middle).Magnitude + fish.length * 0.5)
	end
	return most
end

-- Its fish's average length (studs)
function StartShots.fishLength(index: number): number
	local school = Schools.list[index]
	local total = 0
	for i = school.first, school.first + school.count - 1 do
		total += Schools.fish[i].length
	end
	return total / math.max(school.count, 1)
end

-- The subject at time t: the middle of the school's fish, averaged over `window`
-- seconds either side (weights 1-2-3-2-1)
local WEIGHTS = { { -1, 1 }, { -0.5, 2 }, { 0, 3 }, { 0.5, 2 }, { 1, 1 } }
function StartShots.subject(index: number, t: number, window: number): Vector3
	local middle = middleOf(index)
	local sum = Vector3.new(0, 0, 0)
	for _, w in WEIGHTS do
		sum += Schools.schoolFrame(index, t + w[1] * window):PointToWorldSpace(middle) * w[2]
	end
	return sum / 9
end

-- Where the streaming goes for a shot asked for at time t (the server streams round
-- these): the school along its loop until the shot is surely over (it's cut to once
-- the one on screen ends, and runs until the next is in), every `STREAM_APART` studs,
-- and its landmark when that's near enough to be in the picture
local STREAM_AHEAD = { 0, 7, 14, 21 } -- seconds
local STREAM_APART = 60
function StartShots.streamPoints(shot: Shot, index: number, t: number): { Vector3 }
	local points: { Vector3 } = {}
	for _, ahead in STREAM_AHEAD do
		local at = Schools.schoolFrame(index, t + ahead).Position
		local near = false
		for _, point in points do
			if (point - at).Magnitude < STREAM_APART then
				near = true
				break
			end
		end
		if not near then
			table.insert(points, at)
		end
	end
	local landmark = StartShots.landmark(shot, index)
	if landmark and (landmark - points[1]).Magnitude < 420 then
		table.insert(points, landmark)
	end
	return points
end

-- How many of the built world's parts stand within AREA_RADIUS of `at`: the server
-- counts them round a shot's school when it has streamed the area, and the client
-- counts the ones that have reached it, so a cut waits until nearly all have
-- (spatial queries see only parts with CanQuery on: rock, wrecks, the ruins' stones;
-- the rest stream in with them)
StartShots.AREA_RADIUS = 110
function StartShots.partsNear(at: Vector3): number
	local world = workspace:FindFirstChild("World")
	if world == nil then
		return 0
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { world }
	return #workspace:GetPartBoundsInRadius(at, StartShots.AREA_RADIUS, params)
end

-- Whether the ground should be in reach under the school once its area has streamed
-- in (a mid-water school in the Open Blue has nothing under it for hundreds of studs)
function StartShots.groundNear(index: number): (boolean, number)
	local center = Schools.list[index].center
	local over = center.Y - Seafloor.y(center.X, center.Z)
	return over < 160, over
end

-- The lower third: the featured fish's name, then its place and levels
function StartShots.caption(shot: Shot, index: number): (string, string)
	local school = Schools.list[index]
	local prey = Config.Prey.byId[school.prey]
	local biome = Config.Biomes.byId[shot.biome]
	local name = if prey then prey.name else school.prey
	local place = if biome then `{biome.name}  ·  LV {biome.minLevel}–{biome.maxLevel}` else shot.biome
	return name, place
end

-- The camera at shared-clock time t: its frame (looking at the subject), the subject
-- and the lens
function StartShots.view(plan: Plan, t: number): (CFrame, Vector3, number)
	local s = t - plan.t0
	local e = smooth(s / plan.seconds)
	local subject = StartShots.subject(plan.school, t, plan.window)
	local base = plan.anchor:Lerp(subject, plan.follow)
	local d = plan.distance * (1 - plan.push * e)
	local f, r, side = plan.forward, plan.right, plan.side
	local h = plan.height
	local offset: Vector3
	local look = subject
	if plan.style == "lead" and plan.landmark == nil then
		offset = f * (0.95 * d) + r * (side * 0.42 * d)
	elseif plan.style == "glide" then
		offset = f * ((-0.9 + 1.5 * e) * d) + r * (side * d)
		look = subject + f * (0.15 * d)
	elseif plan.style == "orbit" then
		-- round the school from its home side: opposite the landmark, else beside it
		local home = if plan.landmark then -f else r * side
		local across = UP:Cross(home)
		local a = side * plan.sweep * (e - 0.5)
		offset = (home * math.cos(a) + across * math.sin(a)) * d
	elseif plan.style == "rise" then
		h = plan.height + (plan.rise - plan.height) * e
		offset = r * (side * 0.8 * d) - f * (0.3 * d)
	elseif plan.landmark then
		-- behind the school, the landmark beyond it (a little to one side)
		offset = -f * (0.94 * d) + r * (side * 0.34 * d)
	else -- track
		offset = r * (side * d) - f * (0.2 * d)
		look = subject + f * (0.12 * d)
	end
	local position = base + offset + UP * (h * d)
	look += UP * (LOOK_ABOVE * d)
	-- Over the nominal floor and under the surface
	local floorY = Seafloor.y(position.X, position.Z) + plan.floor
	position =
		Vector3.new(position.X, math.clamp(position.Y, floorY, World.surfaceY - SURFACE_KEEP), position.Z)
	local toward = look - position
	if toward.Magnitude < 0.5 then
		look = position + f
	elseif math.abs(toward.Unit.Y) > 0.97 then
		look = position + unit(flat(toward), f) + Vector3.new(0, if toward.Y > 0 then 4 else -4, 0)
	end
	return CFrame.lookAt(position, look), subject, plan.fov
end

-- How many of a plan's checks fail over its whole span: the subject can see the
-- camera (and a little past it), the camera's own travel is clear, there's open water
-- under it (`floor`) and round it, it keeps off the map's edge, the school swims
-- within STEEP of level while the shot is on, no fish of it comes within `gap` of the
-- camera, and at least half of them are in the picture. With `enough`, it stops
-- counting there (a variant that can't beat the best so far)
function StartShots.check(plan: Plan, cast: Cast, enough: number?): number
	local stop = enough or math.huge
	local fails = 0
	local previous: Vector3? = nil
	local school = Schools.list[plan.school]
	local need = math.max(1, math.ceil(school.count * IN_FRAME))
	local tanUp = math.tan(math.rad(plan.fov) / 2) * FRAME_HEIGHT
	local tanAcross = tanUp * FRAME_ASPECT
	local s = 0
	while s <= plan.span + 1e-6 do
		local t = plan.t0 + s
		local frame, subject = StartShots.view(plan, t)
		local p = frame.Position
		-- The school: swimming level enough, clear of the lens, and enough of it in the
		-- picture
		local schoolFrame = Schools.schoolFrame(plan.school, t)
		if s <= plan.seconds and math.abs(schoolFrame.LookVector.Y) > STEEP_SINE then
			fails += 1
		end
		local look, up, right = frame.LookVector, frame.UpVector, frame.RightVector
		local close, shown = false, 0
		for i = school.first, school.first + school.count - 1 do
			local away = Schools.fishFrame(i, schoolFrame, t).Position - p
			if away.Magnitude < plan.gap then
				close = true
			end
			local depth = away:Dot(look)
			if
				depth > 0
				and math.abs(away:Dot(up)) <= depth * tanUp
				and math.abs(away:Dot(right)) <= depth * tanAcross
			then
				shown += 1
			end
		end
		if close then
			fails += 1
		end
		if shown < need then
			fails += 1
		end
		local toCamera = p - subject
		local length = toCamera.Magnitude
		if length > 0.5 and cast(subject, toCamera.Unit * (length + PAD)) then
			fails += 1
		end
		if previous then
			local move = p - (previous :: Vector3)
			if move.Magnitude > 0.05 and cast(previous :: Vector3, move.Unit * (move.Magnitude + PAD)) then
				fails += 1
			end
		end
		if cast(p, Vector3.new(0, -plan.floor, 0)) then
			fails += 1
		end
		local sideways = frame.RightVector
		if cast(p, sideways * SIDE_RAY) or cast(p, -sideways * SIDE_RAY) or cast(p, UP * SIDE_RAY) then
			fails += 1
		end
		if polar(p) > World.boundsRadius - EDGE_KEEP + 40 then
			fails += 1
		end
		previous = p
		if fails >= stop then
			break
		end
		s += STEP
	end
	return fails
end

-- The same path started at `t0` instead (the cut came a little later than planned):
-- the same side, height, distance and frame, its anchor where the school is then,
-- checked again over its whole span; nil if it no longer keeps to open water
function StartShots.retime(plan: Plan, t0: number, cast: Cast): Plan?
	local moved = table.clone(plan)
	moved.t0 = t0
	moved.anchor = StartShots.subject(plan.school, t0, plan.window)
	moved.fails = StartShots.check(moved, cast)
	return if moved.fails == 0 then moved else nil
end

-- A camera path for shot `shotIndex` on school `school` from shared-clock time `t0`
-- that stays in open water (or nil, with the least bad try). `side` is the side to
-- try first (+1 / -1); `landmark` overrides the shot's own (a wreck the client found).
function StartShots.plan(
	shotIndex: number,
	school: number,
	t0: number,
	cast: Cast,
	side: number?,
	landmark: Vector3?
): (Plan?, Plan?)
	local shot = Start.shots[shotIndex]
	local timing = Start.timing
	local seconds = timing.seconds
	local window = timing.window
	local width = StartShots.width(school)
	-- Far enough that the furthest fish stays `gap` clear of the lens once pushed in
	-- (`frame` × that), or `lengths` of a lone fish
	local fishLength = StartShots.fishLength(school)
	local push = shot.push or 0.1
	local gap = math.max(fishLength * GAP_LENGTHS, GAP_MIN)
	local distance = if Schools.list[school].count <= 1
		then fishLength * (shot.lengths or 6)
		else (StartShots.furthest(school) + gap) / (1 - push) * (shot.frame or 1)
	distance = math.clamp(distance, shot.near or 10, shot.far or 60)
	local mark = landmark or StartShots.landmark(shot, school)
	local anchor = StartShots.subject(school, t0, window)
	-- Travels with the school enough that it drifts at most `drift` of the distance
	-- through the frame over the shot (a fast school would swim into the lens or out
	-- of the picture)
	local travel = flat(StartShots.subject(school, t0 + seconds, window) - anchor).Magnitude
	local follow = shot.follow or 0.7
	if travel > 1 then
		follow = math.clamp(math.max(follow, 1 - (shot.drift or DRIFT) * distance / travel), 0, 1)
	end
	local forward: Vector3
	if mark and flat(mark - anchor).Magnitude > distance * 1.2 then
		forward = unit(flat(mark - anchor), Vector3.new(1, 0, 0))
	else
		mark = nil
		local heading = flat(StartShots.subject(school, t0 + seconds, window) - anchor)
		if heading.Magnitude < width * 0.3 then
			local frame = Schools.schoolFrame(school, t0 + seconds / 2)
			heading = flat(frame.LookVector)
		end
		forward = unit(heading, Vector3.new(1, 0, 0))
	end
	local right = forward:Cross(UP)
	local first = if side and side < 0 then -1 else 1
	-- Either side; then higher; then further; then closer (tight water: a canyon)
	local variants = {}
	for _, scale in { 1, 1.3, 0.8 } do
		for _, rise in { 0, 0.3 } do
			table.insert(variants, { first, rise, scale })
			table.insert(variants, { -first, rise, scale })
		end
	end
	local best: Plan? = nil
	for number, variant in variants do
		local height = (shot.height or 0.2) + variant[2]
		local plan: Plan = {
			shot = shotIndex,
			school = school,
			t0 = t0,
			seconds = seconds,
			span = seconds + timing.extend,
			style = shot.style,
			side = variant[1],
			distance = distance * variant[3],
			height = height,
			rise = (shot.rise or height) + variant[2],
			push = push,
			follow = follow,
			sweep = shot.sweep or 0.6,
			fov = shot.fov or 56,
			floor = shot.floor or 6,
			window = window,
			gap = gap,
			forward = forward,
			right = right,
			anchor = anchor,
			landmark = mark,
			variant = number,
			fails = 0,
		}
		plan.fails = StartShots.check(plan, cast, if best then (best :: Plan).fails else nil)
		if plan.fails == 0 then
			return plan, plan
		end
		if best == nil or plan.fails < (best :: Plan).fails then
			best = plan
		end
	end
	return nil, best
end

return StartShots
