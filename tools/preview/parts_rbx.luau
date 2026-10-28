-- Roblox shims for running Shared/PartFit in the plain luau CLI (run_parts.sh):
-- tools/tests/sim_rbx.luau's Vector3 and CFrame, and a real Color3 (fromRGB,
-- fromHSV, Lerp, ToHSV), since the parts' tints are worked out from colours.
local rbx = require("./sim_rbx")

local Col = {}
local function rgb(r: number, g: number, b: number)
	return setmetatable({ R = r, G = g, B = b }, Col)
end
Col.__index = function(_, k)
	if k == "Lerp" then
		return function(a, b, t)
			return rgb(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
		end
	elseif k == "ToHSV" then
		return function(c)
			local r, g, b = c.R, c.G, c.B
			local max, min = math.max(r, g, b), math.min(r, g, b)
			local h, s = 0, 0
			local d = max - min
			if max > 0 then
				s = d / max
			end
			if d > 0 then
				if max == r then
					h = ((g - b) / d) % 6
				elseif max == g then
					h = (b - r) / d + 2
				else
					h = (r - g) / d + 4
				end
				h /= 6
			end
			return h, s, max
		end
	end
	return nil
end
Col.__type = "Color3"

local Color3 = {
	new = function(r: number?, g: number?, b: number?)
		return rgb(r or 0, g or 0, b or 0)
	end,
	fromRGB = function(r: number, g: number, b: number)
		return rgb(r / 255, g / 255, b / 255)
	end,
	fromHSV = function(h: number, s: number, v: number)
		local i = math.floor(h * 6) % 6
		local f = h * 6 - math.floor(h * 6)
		local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
		local rs = { { v, t, p }, { q, v, p }, { p, v, t }, { p, q, v }, { t, p, v }, { v, p, q } }
		local c = rs[i + 1]
		return rgb(c[1], c[2], c[3])
	end,
}

return { Vector3 = rbx.Vector3, CFrame = rbx.CFrame, Color3 = Color3, Enum = rbx.Enum }
