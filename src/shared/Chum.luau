--!strict
-- Where chum is (Config/Chum): a cloud's chunks drift and sink on a path worked out
-- from the shared clock, so the server (checking eats) and every client (drawing
-- them) agree without streaming positions. A Whale Fall's carcass sinks from its
-- start height to the floor and its chunks hang round it.
local Config = require(script.Parent.Config)

local Chum = {}

export type Chunk = { m: number, ox: number, oy: number, oz: number }
export type Cloud = {
	id: number,
	kind: string, -- "chum", "slick" or "whale"
	x: number,
	y: number, -- where it started (a whale: its start height)
	z: number,
	floor: number, -- the ground under it
	born: number, -- Timing.clock when it appeared (a whale: when it starts to sink)
	ends: number,
	chunks: { Chunk },
	biome: string?,
}

local tune = Config.Chum

-- The middle of a cloud (a whale: the carcass) at shared time `t`
function Chum.center(cloud: Cloud, t: number): Vector3
	local age = math.max(0, t - cloud.born)
	if cloud.kind == "whale" then
		local a = math.clamp(age / tune.whale.sinkSeconds, 0, 1)
		local eased = 1 - (1 - a) * (1 - a)
		local rest = cloud.floor + 6
		return Vector3.new(cloud.x, cloud.y + (rest - cloud.y) * eased, cloud.z)
	end
	local y = math.max(cloud.y - math.min(age * tune.sink, tune.sinkMax), cloud.floor + 1.5)
	return Vector3.new(cloud.x, y, cloud.z)
end

-- Chunk `i` of a cloud at shared time `t`: its spot round the middle, turning slowly
-- and bobbing, never under the floor
function Chum.chunk(cloud: Cloud, i: number, t: number): Vector3
	local chunk = cloud.chunks[i]
	local center = Chum.center(cloud, t)
	local age = math.max(0, t - cloud.born)
	local swirl = age * 0.35 + i * 1.7
	local x = center.X + chunk.ox + math.sin(swirl) * 0.9
	local z = center.Z + chunk.oz + math.cos(swirl) * 0.9
	local y = center.Y + chunk.oy + math.sin(swirl * 1.3) * 0.5
	return Vector3.new(x, math.max(y, cloud.floor + 0.6), z)
end

-- A chunk's drawn size (studs across) from its kg
function Chum.size(m: number): number
	return math.clamp(0.55 + m ^ (1 / 3) * 0.4, 0.6, 3.2)
end

-- Chunk offsets round a middle (deterministic from `seed`): a loose ball for chum,
-- a ring round the carcass for a whale
function Chum.offsets(kind: string, count: number, spread: number, seed: number): { { number } }
	local rng = Random.new(seed)
	local list: { { number } } = {}
	for i = 1, count do
		if kind == "whale" then
			local angle = (i / count) * 2 * math.pi + rng:NextNumber(-0.2, 0.2)
			local r = rng:NextNumber(spread * 0.45, spread)
			table.insert(list, { math.cos(angle) * r, rng:NextNumber(-2, 9), math.sin(angle) * r })
		else
			local angle = rng:NextNumber(0, 2 * math.pi)
			local r = spread * math.sqrt(rng:NextNumber())
			table.insert(
				list,
				{ math.cos(angle) * r, rng:NextNumber(-spread * 0.4, spread * 0.4), math.sin(angle) * r }
			)
		end
	end
	return list
end

return Chum
