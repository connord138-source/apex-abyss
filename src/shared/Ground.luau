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

-- Whether nothing solid (the Terrain or the solid dressing) lies between two
-- points: a predator's snap doesn't reach a fish through a reef head or an arch.
-- The ray stops `short` studs before `to` (default 0.5), so the sand a fish rests on
-- doesn't count.
function Ground.sees(from: Vector3, to: Vector3, short: number?): boolean
	local span = to - from
	local length = span.Magnitude - (short or 0.5)
	if length <= 0.05 then
		return true
	end
	return workspace:Raycast(from, span.Unit * length, rayParams()) == nil
end

-- Open floor (server, once the world is built): a spot for something a small fish
-- picks up off the bottom (a shell, a shrimp, a starfish, medkelp), never in or under
-- anything it can't get to (owner, 2026-10-17: "Ensure that no shells or shrimp or
-- fish spawn in or under items that the player cannot access"). At (x, z):
--   * the first solid thing a ray down from the surface meets is the Terrain itself
--     (not a rock, a coral head, a wreck, a ruin, an arch or a lantern: everything
--     that collides counts, not just the biomes' dressing), and it's no steeper than
--     `minUp` (the normal's height);
--   * a ball `radius` studs across comes straight down onto it (nothing overhangs
--     it and it isn't at the bottom of a crack too narrow for a fish);
--   * no solid part's box comes within `room` studs of the water just over it.
-- Returns the floor point and its normal, or nil.
local openRay: RaycastParams? = nil
local openOverlap: OverlapParams? = nil
local function openParams(): (RaycastParams, OverlapParams)
	local rays, overlap = openRay, openOverlap
	if rays and overlap then
		return rays, overlap
	end
	local freshRays = RaycastParams.new()
	freshRays.FilterType = Enum.RaycastFilterType.Exclude
	freshRays.FilterDescendantsInstances = {}
	freshRays.RespectCanCollide = true -- kelp and anemones are soft
	local freshOverlap = OverlapParams.new()
	freshOverlap.FilterType = Enum.RaycastFilterType.Exclude
	freshOverlap.FilterDescendantsInstances = { workspace.Terrain }
	freshOverlap.RespectCanCollide = true
	openRay, openOverlap = freshRays, freshOverlap
	return freshRays, freshOverlap
end

function Ground.open(x: number, z: number, radius: number, minUp: number, room: number): (Vector3?, Vector3?)
	local rays, overlap = openParams()
	local top = World.surfaceY - 2
	local bottom = World.trench.floorY - 60
	local hit = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, bottom - top, 0), rays)
	if hit == nil or hit.Instance ~= workspace.Terrain or hit.Normal.Y < minUp then
		return nil, nil
	end
	local floor = hit.Position
	-- (a shape cast reaches 1,024 studs at most: from 300 over the spot, along water the
	-- ray just came down)
	local from = math.min(top, floor.Y + 300)
	local ball = workspace:Spherecast(
		Vector3.new(x, from, z),
		radius,
		Vector3.new(0, floor.Y - from - radius - 2, 0),
		rays
	)
	if ball == nil then
		return nil, nil
	end
	local stopped = from - ball.Distance
	if stopped - floor.Y > radius / math.max(hit.Normal.Y, 0.5) + 0.75 then
		return nil, nil
	end
	local over = floor + Vector3.new(0, room * 0.6, 0)
	if #workspace:GetPartBoundsInRadius(over, room, overlap) > 0 then
		return nil, nil
	end
	return floor, hit.Normal
end

-- Forgets every answer (the world was rebuilt)
function Ground.clear()
	table.clear(cache)
	params = nil
end

return Ground
