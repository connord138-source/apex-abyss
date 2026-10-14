--!strict
-- Depth pressure (Config/Pvp `pressure`): how deep a fish of a level can swim before
-- the pressure starts to hurt it. The server applies it (PressureService); the
-- client shows it (HudController).
local Config = require(script.Parent.Config)

local Pressure = {}

export type Band = { y: number, level: number, name: string }

-- The band a fish of `level` can't go below (its y is the crush depth), or nil
-- when it can go anywhere
function Pressure.limit(level: number): Band?
	for _, band in Config.Pvp.pressure.bands do
		if level < band.level then
			return band
		end
	end
	return nil
end

-- Whether a fish of `level` at height `y` is too deep
function Pressure.tooDeep(level: number, y: number): boolean
	local band = Pressure.limit(level)
	return band ~= nil and y < band.y
end

return Pressure
