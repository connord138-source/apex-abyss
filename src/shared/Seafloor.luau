--!strict
-- The nominal floor height at any point (Config/World): the shelf's sand, the
-- drop-off's slope, the deep floor, the Vents' basin and the Trench's canyon. The
-- Terrain the server sculpts (Shelf.luau) follows these numbers plus relief, so
-- placement code can plan heights before anything exists and creatures can keep
-- off the bottom without raycasts.
local Config = require(script.Parent.Config)

local World = Config.World

local Seafloor = {}

local function polar(x: number, z: number): (number, number)
	local center = World.hub.center
	local dx, dz = x - center.X, z - center.Z
	return math.sqrt(dx * dx + dz * dz), math.deg(math.atan2(dz, dx)) % 360
end

-- Whether `angle` (degrees, 0..360) lies in the sector from `from` clockwise to `to`
function Seafloor.inSector(angle: number, from: number, to: number): boolean
	local span = (to - from) % 360
	if span == 0 then
		return true
	end
	return (angle - from) % 360 < span
end

-- Distance (studs) and angle (degrees from +X toward +Z) of a point round the hub
function Seafloor.polar(x: number, z: number): (number, number)
	return polar(x, z)
end

-- Whether a point is over the Trench's canyon (its sector and radii)
function Seafloor.inTrench(x: number, z: number, margin: number?): boolean
	local r, angle = polar(x, z)
	local trench = World.trench
	local pad = margin or 0
	return r >= trench.radii[1] - pad
		and r <= trench.radii[2] + pad
		and Seafloor.inSector(angle, trench.angles[1] - pad * 0.1, trench.angles[2] + pad * 0.1)
end

-- Whether a point is over the Vents' basin
function Seafloor.inVents(x: number, z: number): boolean
	local r, angle = polar(x, z)
	local deep = World.deep
	return r >= deep.ventsRadii[1]
		and r <= deep.ventsRadii[2]
		and Seafloor.inSector(angle, deep.ventsAngles[1], deep.ventsAngles[2])
end

-- Whether a point is on the shelf (inside the drop-off)
function Seafloor.onShelf(x: number, z: number): boolean
	local r = polar(x, z)
	return r <= World.shelf.radius
end

-- The nominal floor height under (x, z)
function Seafloor.y(x: number, z: number): number
	local r = polar(x, z)
	local shelf = World.shelf
	if r <= shelf.radius then
		return World.seabedY
	end
	local deepY = World.deep.floorY
	if r < shelf.radius + shelf.edge then
		-- The drop-off: a steep slope the cliff roughly follows
		local t = (r - shelf.radius) / shelf.edge
		return World.seabedY + (deepY - World.seabedY) * (t * t * (3 - 2 * t))
	end
	if Seafloor.inTrench(x, z) then
		-- The canyon: deepest along its middle, shallowing toward the rims
		local _, angle = polar(x, z)
		local trench = World.trench
		local mid = (trench.angles[1] + trench.angles[2]) / 2
		local half = (trench.angles[2] - trench.angles[1]) / 2
		local across = math.abs(((angle - mid + 180) % 360) - 180) / half
		local along = math.clamp((r - trench.radii[1]) / 40, 0, 1)
			* math.clamp((trench.radii[2] - r) / 40, 0, 1)
		local depth = math.clamp(1 - across, 0, 1) ^ 0.6 * along
		return deepY + (trench.floorY - deepY) * depth
	end
	if Seafloor.inVents(x, z) then
		return World.deep.ventsFloorY
	end
	return deepY
end

return Seafloor
