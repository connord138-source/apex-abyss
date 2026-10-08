--!strict
-- Number formatting for the HUD.
local Format = {}

-- Mass: "0.3 kg", "12.4 kg", "340 kg", "1.2 t", "48 t".
function Format.mass(kg: number): string
	if kg < 10 then
		return string.format("%.1f kg", kg)
	elseif kg < 1000 then
		return string.format("%d kg", math.floor(kg + 0.5))
	elseif kg < 10000 then
		return string.format("%.1f t", kg / 1000)
	end
	return string.format("%d t", math.floor(kg / 1000 + 0.5))
end

-- Distances read in feet (owner, 2026-10-08: "instead of studs it should say ft");
-- a stud is 0.28 m, about 0.92 ft
local FEET_PER_STUD = 0.92

function Format.distance(studs: number): string
	return string.format("%d ft", math.max(0, math.floor(studs * FEET_PER_STUD + 0.5)))
end

-- Depth below the surface, in feet
function Format.depth(studs: number): string
	return Format.distance(studs)
end

return Format
