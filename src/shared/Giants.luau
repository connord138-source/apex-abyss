--!strict
-- The giants crossing the Open Blue (Config/Ambient `giants`): on each of `lanes`
-- long lines a humpback or a giant manta passes every `period` seconds, the same on
-- every client and on the server (each pass is seeded by its lane and its slot of
-- the shared clock). AmbientLifeController draws them; the humpbacks are edible
-- (owner, 2026-10-20: "whales should be edible too"), so CompanionService checks a
-- bite on one against where this says it is.
local Config = require(script.Parent.Config)
local Seafloor = require(script.Parent.Seafloor)

local Ambient = Config.Ambient
local World = Config.World

local Giants = {}

local SALT = 6 -- (AmbientLifeController's salt for the giants)
local TAU = 2 * math.pi

export type Pass = { lane: number, slot: number, kind: string, from: Vector3, to: Vector3, size: number }

-- The seed of one thing in the sea's layout (the same as AmbientLifeController's)
function Giants.seedOf(a: number, b: number, salt: number): number
	return ((a + 5000) * 100003 + (b + 5000)) * 17 + salt * 7919 + World.seed
end

-- The pass a lane is on at `t`
function Giants.slot(lane: number, t: number): number
	local settings = Ambient.giants
	return math.floor((t + lane * settings.period / settings.lanes) / settings.period)
end

-- A pass: "whale" or "manta", the line it crosses on and its length (a manta's span)
function Giants.line(lane: number, slot: number): (string, Vector3, Vector3, number)
	local rng = Random.new(Giants.seedOf(lane, slot, SALT))
	local kind = Ambient.kinds.giant
	local which = if rng:NextNumber() < 0.55 then "whale" else "manta"
	local length = rng:NextNumber(kind.size[1], kind.size[2])
	local r = rng:NextNumber(1050, 1350)
	local angle = math.rad(rng:NextNumber(234, 306))
	local x, z = math.cos(angle) * r, math.sin(angle) * r
	-- Roughly across the sector (along the circle), so it stays in the Open Blue
	local heading = angle + math.pi / 2 + rng:NextNumber(-0.5, 0.5)
	local floor = Seafloor.y(x, z)
	local y = math.min(floor + rng:NextNumber(150, 360), World.surfaceY - 60)
	local half = Ambient.giants.lane / 2
	local direction = Vector3.new(math.cos(heading), 0, math.sin(heading))
	local middle = Vector3.new(x, y, z)
	local function inside(point: Vector3): Vector3
		local flat = Vector2.new(point.X, point.Z)
		if flat.Magnitude > 1460 then
			flat = flat.Unit * 1460
		end
		return Vector3.new(flat.X, point.Y, flat.Y)
	end
	local from = inside(middle - direction * half)
	local to = inside(middle + direction * half + Vector3.new(0, rng:NextNumber(-40, 40), 0))
	if rng:NextNumber() < 0.5 then
		from, to = to, from
	end
	return which, from, to, if which == "whale" then length else length * 0.42
end

-- Where a lane's giant is at `t` on its line, and how far along it (0..1)
function Giants.at(lane: number, from: Vector3, to: Vector3, t: number): (Vector3, number)
	local period = Ambient.giants.period
	local u = ((t + lane * period / Ambient.giants.lanes) % period) / period
	return from:Lerp(to, u) + Vector3.new(0, math.sin(u * TAU) * 12, 0), u
end

-- A lane's pass at `t`
function Giants.pass(lane: number, t: number): Pass
	local slot = Giants.slot(lane, t)
	local kind, from, to, size = Giants.line(lane, slot)
	return { lane = lane, slot = slot, kind = kind, from = from, to = to, size = size }
end

-- How far `point` is from a whale's body (a capsule along its line, `girth` of its
-- length thick in the middle, thinner at the head and flukes): studs past its skin
-- (below 0 inside), and the way out through the skin there
function Giants.gap(at: Vector3, heading: Vector3, size: number, point: Vector3): (number, Vector3)
	local half = heading * size * 0.42
	local tail, span = at - half, half * 2
	local t = math.clamp((point - tail):Dot(span) / math.max(span:Dot(span), 1e-4), 0, 1)
	local radius = size * Ambient.giants.whale.girth * (0.45 + 0.55 * math.sin(math.pi * t))
	local offset = point - (tail + span * t)
	local distance = offset.Magnitude
	return distance - radius, if distance > 1e-3 then offset / distance else Vector3.yAxis
end

return Giants
