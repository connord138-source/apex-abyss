--!strict
-- The edible crabs' scuttle (Config/Forage kinds with `crab`; owner, 2026-10-19:
-- "Crabs should be edible too"), the same on the server and on every client, like the
-- shrimp's hop: each crab keeps to a disc of `scuttle` studs round its spot, dashing
-- sideways from one point of the disc to the next, then pausing a few seconds, on the
-- shared clock. It faces the middle of its disc (so it reads as scuttling about its
-- home), turning to face its next dash in the last half second of a pause. The server
-- only needs to know a crab is within `scuttle` of its spot (ForageService); clients
-- draw the dash (ForageController). Pure math, no Instances.
local Crabs = {}

local TAU = 2 * math.pi
local TURN = 0.5 -- seconds a crab takes to turn before a dash

-- 0 .. 1 from two numbers (a crab's spot and a dash)
local function hash(a: number, b: number): number
	local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return x - math.floor(x)
end

local function ease(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- The point of its disc crab `index` dashes to on its `k`th dash
local function waypoint(index: number, k: number, radius: number): (number, number)
	local r = radius * math.sqrt(hash(index, k * 2 + 0.25))
	local a = TAU * hash(index + 0.5, k * 2 + 1.25)
	return math.cos(a) * r, math.sin(a) * r
end

-- The way it faces for a dash from (ax, az) to (bx, bz): its side along the dash, its
-- front toward the middle of its disc (CFrame.Angles(0, yaw, 0))
local function facing(index: number, k: number, ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	if dx * dx + dz * dz < 1e-4 then
		return TAU * hash(index + 0.75, k)
	end
	local yaw = math.atan2(-dz, dx)
	-- Its front, (-sin yaw, -cos yaw), toward the middle (-(a + b) / 2)
	local mx, mz = (ax + bx) / 2, (az + bz) / 2
	if (-math.sin(yaw)) * -mx + (-math.cos(yaw)) * -mz < 0 then
		yaw += math.pi
	end
	return yaw
end

local function wrap(a: number): number
	return (a + math.pi) % TAU - math.pi
end

-- Seconds between one dash and the next for crab `index`
function Crabs.period(index: number): number
	return 3.5 + 3.5 * hash(index, 0.5)
end

-- Where crab `index` (its spot's number) is at time `t` (Timing.clock): its offset from
-- its spot (studs, x and z), the way it faces (yaw, radians), and whether it's dashing
function Crabs.at(index: number, scuttle: number, speed: number, t: number): (number, number, number, boolean)
	local period = Crabs.period(index)
	local x = t + period * hash(index, 1.5)
	local k = math.floor(x / period)
	local u = x - k * period
	local ax, az = waypoint(index, k - 1, scuttle)
	local bx, bz = waypoint(index, k, scuttle)
	local dx, dz = bx - ax, bz - az
	local distance = math.sqrt(dx * dx + dz * dz)
	local dash = math.clamp(distance / math.max(speed, 0.1), 0.35, period * 0.5)
	local s = if u < dash then ease(u / dash) else 1
	local yaw = facing(index, k, ax, az, bx, bz)
	if u > period - TURN then
		local cx, cz = waypoint(index, k + 1, scuttle)
		local after = facing(index, k + 1, bx, bz, cx, cz)
		yaw += wrap(after - yaw) * ease((u - (period - TURN)) / TURN)
	end
	return ax + dx * s, az + dz * s, yaw, u < dash and distance > 0.05
end

return Crabs
