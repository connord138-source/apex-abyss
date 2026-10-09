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

-- Thousands separators: "2,500"
function Format.number(value: number): string
	local text = tostring(math.floor(value + 0.5))
	local sign = ""
	if string.sub(text, 1, 1) == "-" then
		sign, text = "-", string.sub(text, 2)
	end
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	if string.sub(formatted, 1, 1) == "," then
		formatted = string.sub(formatted, 2)
	end
	return sign .. formatted
end

-- A span of time: "45s", "12m", "3h 20m", "2d 5h"
function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return `{seconds}s`
	elseif seconds < 3600 then
		return `{seconds // 60}m`
	elseif seconds < 86400 then
		local minutes = (seconds % 3600) // 60
		return if minutes > 0 then `{seconds // 3600}h {minutes}m` else `{seconds // 3600}h`
	end
	local hours = (seconds % 86400) // 3600
	return if hours > 0 then `{seconds // 86400}d {hours}h` else `{seconds // 86400}d`
end

-- A countdown clock: "4:05", "1:02:09"
function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return Format
