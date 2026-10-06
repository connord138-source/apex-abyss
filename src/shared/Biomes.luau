--!strict
-- Which biome a position is in (Config/Biomes): the hub first, then the outer
-- sectors, then the Kelp Shallows ring round the hub.
local Config = require(script.Parent.Config)
local Layout = require(script.Parent.Layout)

export type Biome = typeof(Config.Biomes.list[1])

local Biomes = {}

local center = Config.World.hub.center

local function inSector(angle: number, from: number, to: number): boolean
	-- Normalize both ends to start at `from`, so sectors can cross 0°
	local span = (to - from) % 360
	if span == 0 then
		return true
	end
	return (angle - from) % 360 < span
end

-- The biome at `position`, or nil inside the hub (the safe zone has no biome).
function Biomes.at(position: Vector3): Biome?
	if Layout.inHub(position) then
		return nil
	end
	local offset = position - center
	local radius = Vector2.new(offset.X, offset.Z).Magnitude
	local angle = math.deg(math.atan2(offset.Z, offset.X)) % 360
	local fallback: Biome? = nil
	for _, biome in Config.Biomes.list do
		if biome.live and radius >= biome.radiusFrom and radius < biome.radiusTo then
			if biome.angleFrom == 0 and biome.angleTo == 360 then
				fallback = fallback or biome
			elseif inSector(angle, biome.angleFrom, biome.angleTo) then
				return biome
			end
		end
	end
	return fallback
end

-- Whether a fish of `level` is under-levelled for `biome`.
function Biomes.tooLow(biome: Biome, level: number): boolean
	return level + Config.Biomes.warnSlack < biome.minLevel
end

return Biomes
