--!strict
-- The NPC prey. They are never Instances on the server: every fish follows a
-- path computed from the shared clock (Timing.clock), so the server and every
-- client agree where each one is without sending positions. Clients draw them
-- (SchoolController); the server only checks eats against the path and keeps
-- which fish are eaten until they respawn (HuntService).
--
-- Each school loops round its own center on a tilted figure-eight, and each fish
-- keeps an offset inside the school with a little wobble, so they read as a school.
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
	phase: number,
	spread: number, -- studs: how far fish sit from the school's middle
	first: number, -- its fish are Schools.fish[first .. first + count - 1]
	count: number,
	tide: string?, -- only out while this tide is up (Config/Tides)
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
}

-- Where some of a prey's schools go (Config/Prey `zones`, `tideZones`)
type Zone = {
	band: { number },
	angles: { number }?,
	schools: number,
	depth: { number }?,
	tide: string?,
	perSchool: number?,
}

local list: { School } = {}
local fish: { Fish } = {}

-- Every fish its own size (owner, 2026-10-10: the Catch Log tracks "their biggest
-- eat of each species"): most within ±18% of the species, 1 in 25 a trophy up to
-- half again as long. From its own seed, so no school moves.
local sizeRng = Random.new(World.seed + 2)
local TROPHY_CHANCE = 0.04
local function sizeOf(): number
	if sizeRng:NextNumber() < TROPHY_CHANCE then
		return 1.25 + sizeRng:NextNumber() * 0.25
	end
	return 0.82 + sizeRng:NextNumber() * 0.36
end

-- Lays out one zone's schools of a prey (rng shared, so the layout is the same
-- everywhere)
local function build(rng: Random, prey: any, zone: Zone, tide: string?)
	local length = Size.length(prey.mass)
	local perSchool = zone.perSchool or prey.perSchool
	for _ = 1, zone.schools do
		local radius = rng:NextNumber(prey.pathRadius[1], prey.pathRadius[2])
		local spread = prey.spread * length * math.sqrt(perSchool)
		local margin = radius + spread + 10
		local band = zone.band
		local angle, distance = 0, 0
		for _ = 1, 12 do
			if zone.angles then
				local span = (zone.angles[2] - zone.angles[1]) % 360
				angle = math.rad(zone.angles[1] + rng:NextNumber(0, if span == 0 then 360 else span))
			else
				angle = rng:NextNumber(0, 2 * math.pi)
			end
			distance = rng:NextNumber(band[1] + margin, band[2] - margin)
			if not Seafloor.inTrench(math.cos(angle) * distance, math.sin(angle) * distance, margin) then
				break
			end
		end
		local height = rng:NextNumber(4, 14)
		local floor = Seafloor.y(math.cos(angle) * distance, math.sin(angle) * distance)
		local depth = zone.depth or prey.depth
		local y = floor + rng:NextNumber(depth[1] + height, depth[2] - height)
		local direction = if rng:NextInteger(0, 1) == 0 then -1 else 1
		local school: School = {
			prey = prey.id,
			center = World.hub.center
				+ Vector3.new(math.cos(angle) * distance, y, math.sin(angle) * distance),
			radius = radius,
			ellipse = rng:NextNumber(0.55, 1),
			height = height,
			angularSpeed = direction * prey.speed / radius,
			phase = rng:NextNumber(0, 2 * math.pi),
			spread = spread,
			first = #fish + 1,
			count = perSchool,
			tide = tide,
		}
		table.insert(list, school)
		for _ = 1, perSchool do
			local offset = if perSchool == 1
				then Vector3.zero
				else Vector3.new(
					rng:NextNumber(-1, 1),
					rng:NextNumber(-0.45, 0.45),
					rng:NextNumber(-1, 1)
				) * spread
			local size = sizeOf()
			table.insert(fish, {
				school = #list,
				prey = prey.id,
				offset = offset,
				phase = rng:NextNumber(0, 2 * math.pi),
				length = length * size,
				radius = length * size * 0.3,
				size = size,
				mass = prey.mass * size ^ 3,
			})
		end
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
end

local Schools = {
	list = list,
	fish = fish,
	COUNT = #fish,
}

-- Whether fish `index` is out: a tide school only while its tide is up
function Schools.out(index: number, tideId: string): boolean
	local tide = list[fish[index].school].tide
	return tide == nil or tide == tideId
end

-- The school's frame at time t: its position on the loop, facing along it.
function Schools.schoolFrame(index: number, t: number): CFrame
	local school = list[index]
	local a = school.phase + school.angularSpeed * t
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
	return CFrame.lookAt(position, position + velocity)
end

-- One fish's frame, given its school's frame at the same t.
function Schools.fishFrame(index: number, schoolFrame: CFrame, t: number): CFrame
	local f = fish[index]
	local p = f.phase
	local wobble = Vector3.new(
		math.sin(t * 1.3 + p) * 0.5,
		math.sin(t * 1.9 + p * 2) * 0.35,
		math.sin(t * 0.9 + p) * 0.6
	)
	local position = schoolFrame:PointToWorldSpace(f.offset + wobble * f.length)
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
