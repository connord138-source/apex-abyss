--!strict
-- The nominal floor height at any point (Config/World): the shelf's sand, the
-- drop-off's slope, the deep floor, the Vents' basins and the Trench's canyon. The
-- Terrain the server sculpts (Shelf.luau) follows these numbers plus relief, so
-- placement code can plan heights before anything exists and creatures can keep
-- off the bottom without raycasts. The canyon's line and widths live here too, so
-- the Terrain's cuts and the nominal floor can't disagree.
local Config = require(script.Parent.Config)

local World = Config.World

local Seafloor = {}

-- The canyon's three cuts widen toward the rim by this much beyond its floor width
local TRENCH_WIDEN = { bottom = 60, middle = 170, top = 300 }
-- Its rounded ends run this far past its radii
local TRENCH_END = 30

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

-- The canyon's line at distance `r` from the hub: its middle angle (degrees), its
-- floor width (narrower at both ends) and how far along it `r` is (0..1)
function Seafloor.trenchAxis(r: number): (number, number, number)
	local trench = World.trench
	local t = math.clamp((r - trench.radii[1]) / (trench.radii[2] - trench.radii[1]), 0, 1)
	local angle = (trench.angles[1] + trench.angles[2]) / 2 + math.sin(t * trench.bends) * trench.wobble
	local width = trench.width * (1 - math.abs(t - 0.5) * 0.5)
	return angle, width, t
end

-- Half-widths across the canyon of its three cuts (studs): at the rim, halfway down
-- and at the floor
function Seafloor.trenchHalfWidths(width: number): (number, number, number)
	return width / 2 + TRENCH_WIDEN.top, width / 2 + TRENCH_WIDEN.middle, width / 2 + TRENCH_WIDEN.bottom
end

-- How far a point is across the canyon from its line (studs; huge outside its length)
local function trenchAcross(x: number, z: number): (number, number, number)
	local r, angle = polar(x, z)
	local trench = World.trench
	if r < trench.radii[1] - TRENCH_END or r > trench.radii[2] + TRENCH_END then
		return math.huge, r, 0
	end
	local axis, width = Seafloor.trenchAxis(r)
	local off = math.abs(((angle - axis + 180) % 360) - 180)
	return math.rad(off) * r, r, width
end

-- A point on the canyon: `r` along it, `across` studs from its line (signed)
function Seafloor.trenchPoint(r: number, across: number): (number, number)
	local axis = Seafloor.trenchAxis(r)
	local angle = math.rad(axis + math.deg(across / r))
	local center = World.hub.center
	return center.X + math.cos(angle) * r, center.Z + math.sin(angle) * r
end

-- Whether a point is over the canyon (its rim width plus `margin`)
function Seafloor.inTrench(x: number, z: number, margin: number?): boolean
	local across, _, width = trenchAcross(x, z)
	if across == math.huge then
		return false
	end
	local halfTop = Seafloor.trenchHalfWidths(width)
	return across <= halfTop + (margin or 0)
end

-- Whether a point is over the Vents' sector
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

-- Where the Vents' basins are (the same on every machine): the hollows the Terrain
-- sinks below the deep floor in the Vents' sector
local basins: { { x: number, z: number, radius: number } }? = nil
function Seafloor.ventBasins(): { { x: number, z: number, radius: number } }
	if basins then
		return basins
	end
	local made = {}
	local rng = Random.new(World.seed + 11)
	local deep = World.deep
	local center = World.hub.center
	for _ = 1, 10 do
		local span = (deep.ventsAngles[2] - deep.ventsAngles[1]) % 360
		local angle = math.rad(deep.ventsAngles[1] + rng:NextNumber(8, span - 8))
		local r = rng:NextNumber(deep.ventsRadii[1] + 70, deep.ventsRadii[2] - 70)
		table.insert(made, {
			x = center.X + math.cos(angle) * r,
			z = center.Z + math.sin(angle) * r,
			radius = rng:NextNumber(70, 130),
		})
	end
	basins = made
	return made
end

-- The nominal floor height under (x, z). In the canyon it is a V inside the Terrain's
-- stepped cuts, so it is never deeper than the rock.
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
	local across, _, width = trenchAcross(x, z)
	if across ~= math.huge then
		local halfTop, _, halfBottom = Seafloor.trenchHalfWidths(width)
		if across < halfTop then
			local trench = World.trench
			local v = math.clamp((halfTop - across) / (halfTop - halfBottom), 0, 1)
			local along = math.clamp((r - trench.radii[1] + TRENCH_END) / 60, 0, 1)
				* math.clamp((trench.radii[2] + TRENCH_END - r) / 60, 0, 1)
			return deepY + (trench.floorY - deepY) * v * along
		end
	end
	-- The Vents' basins are hollows, not a whole sector; between them the floor is
	-- the deep floor (Shelf.luau carves each one where Seafloor.ventBasins says)
	for _, basin in Seafloor.ventBasins() do
		local dx, dz = x - basin.x, z - basin.z
		if dx * dx + dz * dz <= (basin.radius - 6) ^ 2 then
			return World.deep.ventsFloorY
		end
	end
	return deepY
end

return Seafloor
