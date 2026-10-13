--!strict
-- The real ground under a point: the top of the Terrain and of the world's solid
-- dressing (rocks, coral, wrecks, ruins, vent chimneys) in that column, found by a
-- ray cast down from the surface. Shared/Seafloor gives the nominal floor (the sand
-- and the canyon, smooth), which reef heads, ridges, arches, wrecks and chimneys rise
-- far above: AI predators kept to the nominal floor swam through them (owner,
-- 2026-10-13: "the predator fish will phase through the sand in the ground"). Taking
-- the column's top also keeps big creatures out from under arches and out of tunnels,
-- which is where small fish hide.
--
-- Answers are cached per 4-stud cell (the Terrain's voxel size), so asking about the
-- same water every tick costs nothing. A column with nothing to hit (the Terrain not
-- built yet, or not streamed in on a client) answers the nominal floor and isn't
-- cached, so it's asked again later.
local Config = require(script.Parent.Config)
local Seafloor = require(script.Parent.Seafloor)

local World = Config.World

local Ground = {}

local CELL = 4
local SOLID = { "Rocks", "Coral", "Wrecks", "Ruins", "Vents" } -- under Workspace.World.Biomes
local PARAMS_AGE = 5 -- seconds before the ray filter is rebuilt (dressing streams in)

local cache: { [number]: number } = {}
local params: RaycastParams? = nil
local paramsAt = -math.huge

local function rayParams(): RaycastParams
	local now = os.clock()
	local made = params
	if made and now - paramsAt < PARAMS_AGE then
		return made
	end
	local include: { Instance } = { workspace.Terrain }
	local world = workspace:FindFirstChild("World")
	local biomes = if world then world:FindFirstChild("Biomes") else nil
	if biomes then
		for _, name in SOLID do
			local folder = biomes:FindFirstChild(name)
			if folder then
				table.insert(include, folder)
			end
		end
	end
	local fresh = RaycastParams.new()
	fresh.FilterType = Enum.RaycastFilterType.Include
	fresh.FilterDescendantsInstances = include
	fresh.RespectCanCollide = true -- soft dressing (kelp, anemones) doesn't count
	params = fresh
	paramsAt = now
	return fresh
end

-- The height of the ground's top at (x, z)
function Ground.y(x: number, z: number): number
	local cx, cz = math.floor(x / CELL), math.floor(z / CELL)
	local key = (cx + 2000) * 4096 + (cz + 2000)
	local cached = cache[key]
	if cached then
		return cached
	end
	local centerX, centerZ = (cx + 0.5) * CELL, (cz + 0.5) * CELL
	local nominal = Seafloor.y(centerX, centerZ)
	local from = Vector3.new(centerX, World.surfaceY - 1, centerZ)
	local hit = workspace:Raycast(from, Vector3.new(0, nominal - World.surfaceY - 80, 0), rayParams())
	if hit == nil then
		return nominal
	end
	local top = math.max(hit.Position.Y, nominal - 40)
	cache[key] = top
	return top
end

-- Forgets every answer (the world was rebuilt)
function Ground.clear()
	table.clear(cache)
	params = nil
end

return Ground
