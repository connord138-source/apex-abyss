--!strict
-- Number formatting for the HUD.
local Format = {}

-- Mass: "0.35 kg", "1.2 kg", "340 kg", "1.2 t", "48 t".
function Format.mass(kg: number): string
	-- (two places under a kilo: since the 2026-10-19 pace a full Haul is 0.16 kg at
	-- LV 8 and 0.67 kg at LV 25, so a bank or a lost Haul reads "0.23 kg", not "0.2")
	if kg < 1 then
		return string.format("%.2f kg", kg)
	elseif kg < 10 then
		return string.format("%.1f kg", kg)
	elseif kg < 1000 then
		return string.format("%d kg", math.floor(kg + 0.5))
	elseif kg < 10000 then
		return string.format("%.1f t", kg / 1000)
	end
	return string.format("%d t", math.floor(kg / 1000 + 0.5))
end

-- A Haul amount gained (pops, reward toasts), as food (Size.haulShown): grams under a
-- kilo (a starfish is 40 g): "1.3 g", "56 g",
-- "2.4 kg", "340 kg"
function Format.haul(kg: number): string
	if kg < 0.01 then
		return string.format("%.1f g", kg * 1000)
	elseif kg < 1 then
		return string.format("%d g", math.floor(kg * 1000 + 0.5))
	end
	return Format.mass(kg)
end

-- A catch's weight with enough digits for the small fish (the Catch Log's biggest:
-- a minnow weighs 0.06–0.3 kg)
function Format.catchMass(kg: number): string
	if kg < 1 then
		return string.format("%.2f kg", kg)
	end
	return Format.mass(kg)
end

-- Distances read in feet (owner, 2026-10-08: "instead of studs it should say ft");
-- a stud is 0.28 m, about 0.92 ft
local FEET_PER_STUD = 0.92

function Format.distance(studs: number): string
	return string.format("%d ft", math.max(0, math.floor(studs * FEET_PER_STUD + 0.5)))
end

-- A fish's length in feet, always with a decimal ("2.1 ft", "14.9 ft"), so a bank's
-- growth shows at every size (the bank's growth card). Growth is linear since
-- 2026-10-20, ~0.7 ft a load, so whole feet past 10 read "15 ft → 15 ft" at LV 95 → 100
-- (PC 2026-10-20, GR)
function Format.length(studs: number): string
	return string.format("%.1f ft", math.max(0, studs * FEET_PER_STUD))
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
