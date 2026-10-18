--!strict
-- Sea life that isn't food (owner, 2026-10-18: "We still need so much more fish too. I
-- feel like the ocean has a pretty empty feeling"; "Think Subnautica"): jellyfish
-- drifting in the deep water, rays gliding over the sand, crabs scuttling round rocks
-- and wrecks, turtles cruising the shelf, clouds of tiny reef fish over the coral
-- heads, and whales and mantas passing far off through the Open Blue's haze
-- (Config/Ambient). Client-only and part-built: nothing replicates, nothing is eaten.
--
-- The sea is cut into squares (Config/Ambient `CELL`); a square's creatures come from a
-- seed of its position and move on the shared clock, so a place always holds the same
-- life doing the same thing. Only squares near the camera are built (nearest first,
-- a few a refresh), and each creature fades in and out at the edge of its range
-- (LocalTransparencyModifier), so nothing pops. Its ranges shrink with the prey
-- schools' on a slow device (SchoolController.detail). Near a world boss everything
-- fades away, and the giants hide while one is up.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Biomes = require(ReplicatedStorage.Shared.Biomes)
local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Timing = require(ReplicatedStorage.Shared.Timing)
local BossController = require(script.Parent.BossController)
local SchoolController = require(script.Parent.SchoolController)

local Ambient = Config.Ambient
local World = Config.World
local KINDS = Ambient.kinds
local CELL = Ambient.CELL
-- The kinds laid out by square, and a salt each for their seeds
local SQUARE_KINDS = { "jelly", "ray", "crab", "turtle" }
local SALT: { [string]: number } = { jelly = 1, ray = 2, crab = 3, turtle = 4, cloud = 5, giant = 6 }
local HUB_CLEAR = 210 -- studs from the hub's middle: its seamount, no life laid out
local FADE_SHARE = 0.2 -- the last share of a range a creature fades over
local REFRESH = 0.4 -- seconds between looks at which squares should be built
local SPAWN_BUDGET = 0.002 -- seconds a refresh may spend building squares
local NEAR_DETAIL = 90 -- studs: closer than this, jellies pulse and trail their tentacles
local WHITE = Color3.new(1, 1, 1)

type Creature = {
	kind: string,
	key: number,
	model: Model,
	parts: { BasePart },
	fade: number, -- the LocalTransparencyModifier on its parts (0 shown .. 1 gone)
	home: Vector3,
	size: number,
	radius: number,
	ellipse: number,
	angular: number, -- radians/s round its loop (sign = direction)
	phase: number,
	lifts: { number }?, -- ground heights round its loop (rays, turtles) or along its walk (crabs)
	yaw: number,
	walk: number, -- a crab's walk, studs
	cycle: number, -- a crab's walk cycle, seconds
	pulse: number, -- a jelly's beats a second
	bellMesh: SpecialMesh?,
	rimMesh: SpecialMesh?,
	tips: { Attachment }?,
	tipRest: { Vector3 }?,
	beams: { Beam }?,
	fish: { { a: number, w: number, r: number, h: number } }?, -- a reef cloud's fish
	from: Vector3?, -- a giant's line
	to: Vector3?,
	giant: string?, -- "whale" | "manta"
	still: boolean, -- a crab at rest, already posed there (left alone until it moves)
}

local AmbientLifeController = {}

local folder: Folder
local creatures: { [Creature]: boolean } = {}
local squares: { [number]: { Creature } } = {} -- square key → its creatures (maybe none)
local squareAt: { [number]: Vector2 } = {} -- square key → its middle
local retryAt: { [number]: number } = {} -- square key → when to try a square whose ground wasn't in
local counts: { [string]: number } = {}
local clouds: { [number]: Creature } = {} -- coral square key → its cloud
local giants: { [number]: Creature } = {} -- lane → its giant this pass
local giantSlot: { [number]: number } = {}
local nextRefresh = 0
local nextScan = 0
local bossFade = 0
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
local rayParams: RaycastParams? = nil
local rayParamsAt = -math.huge
local coralParams: OverlapParams? = nil

local function inList(list: { string }, id: string): boolean
	return table.find(list, id) ~= nil
end

local function seedOf(a: number, b: number, salt: number): number
	return ((a + 5000) * 100003 + (b + 5000)) * 17 + salt * 7919 + World.seed
end

local function part(
	parent: Instance,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	transparency: number
): Part
	local made = Instance.new("Part")
	made.Anchored = true
	made.CanCollide = false
	made.CanQuery = false
	made.CanTouch = false
	made.CastShadow = false
	made.Material = material
	made.Color = color
	made.Transparency = transparency
	made.Size = size
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = made
	made.Parent = parent
	return made
end

local function newCreature(kind: string, key: number, home: Vector3, size: number, phase: number): Creature
	local model = Instance.new("Model")
	model.Name = kind
	return {
		kind = kind,
		key = key,
		model = model,
		parts = {},
		fade = 0,
		home = home,
		size = size,
		radius = 0,
		ellipse = 1,
		angular = 0,
		phase = phase,
		lifts = nil,
		yaw = 0,
		walk = 0,
		cycle = 1,
		pulse = 1,
		bellMesh = nil,
		rimMesh = nil,
		tips = nil,
		tipRest = nil,
		beams = nil,
		fish = nil,
		from = nil,
		to = nil,
		giant = nil,
		still = false,
	}
end

-- Out of sight to start with: it fades in as it comes into range
local function setFade(creature: Creature, fade: number)
	creature.fade = fade
	for _, piece in creature.parts do
		piece.LocalTransparencyModifier = fade
	end
	local beams = creature.beams
	if beams then
		for _, beam in beams do
			beam.Enabled = fade < 1
			beam.Transparency = NumberSequence.new(0.25 + 0.75 * fade, 1)
		end
	end
end

local function add(creature: Creature, parts: { BasePart })
	creature.parts = parts
	setFade(creature, 1)
	creature.model.Parent = folder
	creatures[creature] = true
	counts[creature.kind] = (counts[creature.kind] or 0) + 1
end

local function remove(creature: Creature)
	if creatures[creature] then
		creatures[creature] = nil
		counts[creature.kind] = (counts[creature.kind] or 1) - 1
	end
	creature.model:Destroy()
end

-- The solid world under a point (the Terrain and the biomes' rock, coral, wrecks,
-- ruins and vents), rebuilt now and then as the world streams in
local function groundRay(): RaycastParams
	local now = os.clock()
	local made = rayParams
	if made and now - rayParamsAt < 5 then
		return made
	end
	local include: { Instance } = { workspace.Terrain }
	local world = workspace:FindFirstChild("World")
	local biomes = world and world:FindFirstChild("Biomes")
	if biomes then
		for _, name in { "Rocks", "Coral", "Wrecks", "Ruins", "Vents" } do
			local found = biomes:FindFirstChild(name)
			if found then
				table.insert(include, found)
			end
		end
	end
	local fresh = RaycastParams.new()
	fresh.FilterType = Enum.RaycastFilterType.Include
	fresh.FilterDescendantsInstances = include
	fresh.RespectCanCollide = true
	rayParams = fresh
	rayParamsAt = now
	return fresh
end

local function castDown(x: number, z: number): RaycastResult?
	local floor = Seafloor.y(x, z)
	local from = Vector3.new(x, World.surfaceY - 2, z)
	return workspace:Raycast(from, Vector3.new(0, floor - World.surfaceY - 60, 0), groundRay())
end

-- Ground heights round a loop (for things that glide or cruise over it): `count`
-- samples of the real ground plus `clear`, eased so a rise is a ramp, never a step
local function loopLifts(creature: Creature, count: number, clear: number, slope: number): { number }
	local lifts = table.create(count, 0)
	local home = creature.home
	for k = 1, count do
		local a = (k - 1) / count * 2 * math.pi
		local x = home.X + math.cos(a) * creature.radius
		local z = home.Z + math.sin(a) * creature.radius * creature.ellipse
		lifts[k] = Ground.y(x, z) + clear
	end
	local spacing = math.pi * creature.radius * (1 + creature.ellipse) / count
	for _ = 1, 2 do
		for k = 0, 2 * count - 1 do
			local here, before = k % count + 1, (k - 1) % count + 1
			lifts[here] = math.max(lifts[here], lifts[before] - slope * spacing)
		end
		for k = 2 * count - 1, 0, -1 do
			local here, after = k % count + 1, (k + 1) % count + 1
			lifts[here] = math.max(lifts[here], lifts[after] - slope * spacing)
		end
	end
	return lifts
end

local function liftAt(lifts: { number }, a: number): number
	local count = #lifts
	local u = ((a / (2 * math.pi)) % 1) * count
	local i = math.floor(u)
	local low = lifts[i % count + 1]
	local high = lifts[(i + 1) % count + 1]
	return low + (high - low) * (u - i)
end

-- Where a creature on a loop is at time t, and which way it's going
local function onLoop(creature: Creature, t: number): (Vector3, Vector3, number)
	local a = creature.phase + creature.angular * t
	local r = creature.radius
	local home = creature.home
	local x = home.X + math.cos(a) * r
	local z = home.Z + math.sin(a) * r * creature.ellipse
	local y = if creature.lifts then liftAt(creature.lifts, a) else home.Y
	local heading = Vector3.new(-math.sin(a) * r, 0, math.cos(a) * r * creature.ellipse)
		* math.sign(creature.angular)
	return Vector3.new(x, y, z), heading, a
end

----------------------------------------------------------------------------------
-- Jellyfish: a pale see-through bell, a Neon rim and four glowing tentacles that
-- trail and sway; it beats, drifts on a slow loop and bobs.

local function makeJelly(rng: Random, key: number, x: number, z: number, floor: number): Creature?
	local kind = KINDS.jelly
	local depth = kind.depth or { 30, 300 }
	local y = floor + rng:NextNumber(depth[1], depth[2])
	local size = rng:NextNumber(kind.size[1], kind.size[2])
	local color = kind.colors[rng:NextInteger(1, #kind.colors)]
	local radius = rng:NextNumber(4, 16)
	local speed = kind.speed or { 1, 1 }
	local creature = newCreature("jelly", key, Vector3.zero, size, rng:NextNumber(0, 2 * math.pi))
	creature.radius = radius
	creature.ellipse = rng:NextNumber(0.6, 1)
	creature.angular = rng:NextNumber(speed[1], speed[2])
		/ radius
		* (if rng:NextNumber() < 0.5 then -1 else 1)
	creature.pulse = rng:NextNumber(0.45, 0.85)
	local tentacle = rng:NextNumber(1.4, 2.6)
	-- (over whatever stands there, and under the surface)
	y = math.min(math.max(y, Ground.y(x, z) + 12 + size), World.surfaceY - 20)
	creature.home = Vector3.new(x, y, z)
	local bell = part(
		creature.model,
		Vector3.new(size, size * 0.62, size),
		color:Lerp(WHITE, 0.55),
		Enum.Material.SmoothPlastic,
		0.45
	)
	local rim = part(
		creature.model,
		Vector3.new(size * 1.04, size * 0.14, size * 1.04),
		color,
		Enum.Material.Neon,
		0.2
	)
	creature.bellMesh = bell:FindFirstChildOfClass("SpecialMesh")
	creature.rimMesh = rim:FindFirstChildOfClass("SpecialMesh")
	local tips: { Attachment } = {}
	local rest: { Vector3 } = {}
	local beams: { Beam } = {}
	for i = 1, 4 do
		local a = (i - 0.5) / 4 * 2 * math.pi
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(math.cos(a) * size * 0.28, -size * 0.12, math.sin(a) * size * 0.28)
		top.Parent = bell
		local tip = Instance.new("Attachment")
		local at = Vector3.new(
			math.cos(a) * size * 0.2,
			-size * tentacle * (0.8 + 0.1 * i),
			math.sin(a) * size * 0.2
		)
		tip.Position = at
		tip.Parent = bell
		local beam = Instance.new("Beam")
		beam.Attachment0 = top
		beam.Attachment1 = tip
		beam.Width0 = size * 0.1
		beam.Width1 = size * 0.02
		beam.FaceCamera = true
		beam.Segments = 8
		beam.CurveSize0 = size * 0.5 * (if i % 2 == 0 then 1 else -1)
		beam.CurveSize1 = -size * 0.4 * (if i % 2 == 0 then 1 else -1)
		beam.Color = ColorSequence.new(color)
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Parent = bell
		table.insert(tips, tip)
		table.insert(rest, at)
		table.insert(beams, beam)
	end
	creature.tips = tips
	creature.tipRest = rest
	creature.beams = beams
	add(creature, { bell, rim })
	return creature
end

local function jellyAt(creature: Creature, t: number): Vector3
	local a = creature.phase + creature.angular * t
	local r = creature.radius
	return creature.home
		+ Vector3.new(
			math.cos(a) * r,
			math.sin(t * 0.21 + creature.phase) * 3,
			math.sin(a) * r * creature.ellipse
		)
end

local function poseJelly(creature: Creature, t: number, at: Vector3, away: number)
	local size = creature.size
	local p = creature.phase
	-- A beat: the bell squeezes and lifts, then relaxes
	local u = (t * creature.pulse + p) % 1
	local squeeze = if u < 0.3 then math.sin(u / 0.3 * math.pi) else 0
	local lift = squeeze * size * 0.12
	local frame = CFrame.new(at + Vector3.new(0, lift, 0))
		* CFrame.Angles(math.sin(t * 0.37 + p) * 0.18, p, math.cos(t * 0.29 + p) * 0.18)
	table.insert(moveParts, creature.parts[1])
	table.insert(moveFrames, frame)
	table.insert(moveParts, creature.parts[2])
	table.insert(moveFrames, frame * CFrame.new(0, -size * 0.2, 0))
	if away < NEAR_DETAIL then
		local bellMesh, rimMesh = creature.bellMesh, creature.rimMesh
		if bellMesh and rimMesh then
			local scale = Vector3.new(1 - 0.16 * squeeze, 1 + 0.1 * squeeze, 1 - 0.16 * squeeze)
			bellMesh.Scale = scale
			rimMesh.Scale = Vector3.new(scale.X, 1, scale.Z)
		end
		local tips, rest = creature.tips, creature.tipRest
		if tips and rest then
			for i, tip in tips do
				tip.Position = rest[i]
					+ Vector3.new(
						math.sin(t * 1.1 + i * 1.3 + p) * size * 0.3,
						squeeze * size * 0.15,
						math.cos(t * 0.9 + i * 1.7 + p) * size * 0.3
					)
			end
		end
	end
end

----------------------------------------------------------------------------------
-- Rays: a flat body and two wings that flap slowly, a whip of a tail; they glide a
-- couple of studs over the ground on a lazy loop.

local function makeRay(rng: Random, key: number, x: number, z: number, _floor: number): Creature?
	local kind = KINDS.ray
	local span = rng:NextNumber(kind.size[1], kind.size[2])
	local creature = newCreature("ray", key, Vector3.new(x, 0, z), span, rng:NextNumber(0, 2 * math.pi))
	creature.radius = rng:NextNumber(16, 38)
	creature.ellipse = rng:NextNumber(0.5, 1)
	local speed = kind.speed or { 4, 4 }
	creature.angular = rng:NextNumber(speed[1], speed[2])
		/ creature.radius
		* (if rng:NextNumber() < 0.5 then -1 else 1)
	local depth = kind.depth or { 2, 3 }
	local clear = rng:NextNumber(depth[1], depth[2])
	local color = kind.colors[rng:NextInteger(1, #kind.colors)]
	creature.lifts = loopLifts(creature, 18, clear + span * 0.05, 0.35)
	local model = creature.model
	local belly = color:Lerp(WHITE, 0.25)
	local body =
		part(model, Vector3.new(span * 0.36, span * 0.1, span * 0.5), color, Enum.Material.SmoothPlastic, 0)
	local left =
		part(model, Vector3.new(span * 0.5, span * 0.06, span * 0.36), color, Enum.Material.SmoothPlastic, 0)
	local right =
		part(model, Vector3.new(span * 0.5, span * 0.06, span * 0.36), color, Enum.Material.SmoothPlastic, 0)
	local tail = part(
		model,
		Vector3.new(span * 0.035, span * 0.035, span * 0.65),
		belly,
		Enum.Material.SmoothPlastic,
		0
	)
	add(creature, { body, left, right, tail })
	return creature
end

local function poseRay(creature: Creature, t: number)
	local span = creature.size
	local p = creature.phase
	local at, heading = onLoop(creature, t)
	at += Vector3.new(0, math.sin(t * 0.8 + p) * 0.3, 0)
	local frame = CFrame.lookAt(at, at + heading) * CFrame.Angles(0, 0, -math.sign(creature.angular) * 0.12)
	local flap = math.sin(t * 1.4 + p) * 0.3
	table.insert(moveParts, creature.parts[1])
	table.insert(moveFrames, frame)
	table.insert(moveParts, creature.parts[2])
	table.insert(
		moveFrames,
		frame * CFrame.new(-span * 0.1, 0, 0) * CFrame.Angles(0, -0.3, flap) * CFrame.new(-span * 0.24, 0, 0)
	)
	table.insert(moveParts, creature.parts[3])
	table.insert(
		moveFrames,
		frame * CFrame.new(span * 0.1, 0, 0) * CFrame.Angles(0, 0.3, -flap) * CFrame.new(span * 0.24, 0, 0)
	)
	table.insert(moveParts, creature.parts[4])
	table.insert(
		moveFrames,
		frame
			* CFrame.new(0, 0, span * 0.22)
			* CFrame.Angles(0, math.sin(t * 1.2 + p) * 0.25, 0)
			* CFrame.new(0, 0, span * 0.32)
	)
end

----------------------------------------------------------------------------------
-- Crabs: a shell, a dark fringe of legs and two claws; they scuttle sideways a few
-- studs, wait, and scuttle back, mostly on and beside rocks, coral and wrecks.

-- "retry": the ground there hasn't streamed in yet
local function makeCrab(rng: Random, key: number, x: number, z: number, _floor: number): (Creature?, boolean)
	local kind = KINDS.crab
	-- Every draw first, so the square comes out the same whatever the rays find
	local spots: { Vector2 } = {}
	for _ = 1, 4 do
		table.insert(spots, Vector2.new(x + rng:NextNumber(-14, 14), z + rng:NextNumber(-14, 14)))
	end
	local onSand = rng:NextNumber() < 0.35
	local size = rng:NextNumber(kind.size[1], kind.size[2])
	local yaw = rng:NextNumber(0, 2 * math.pi)
	local walk = rng:NextNumber(2, 6)
	local cycle = rng:NextNumber(5, 11)
	local phase = rng:NextNumber(0, 20)
	local color = kind.colors[rng:NextInteger(1, #kind.colors)]
	local chosen: RaycastResult? = nil
	local sand: RaycastResult? = nil
	local missed = 0
	for _, spot in spots do
		local hit = castDown(spot.X, spot.Y)
		if hit == nil then
			missed += 1
			continue
		end
		local rocky = hit.Instance ~= workspace.Terrain
			or hit.Material == Enum.Material.Rock
			or hit.Material == Enum.Material.Basalt
			or hit.Material == Enum.Material.Slate
			or hit.Material == Enum.Material.Limestone
		if rocky and hit.Normal.Y > 0.55 then
			chosen = hit
			break
		elseif hit.Normal.Y > 0.7 then
			sand = sand or hit
		end
	end
	if chosen == nil and missed == #spots then
		return nil, true
	end
	if chosen == nil and onSand then
		chosen = sand
	end
	if chosen == nil then
		return nil, false
	end
	local hit = chosen :: RaycastResult
	local creature = newCreature("crab", key, hit.Position, size, phase)
	creature.yaw = yaw
	creature.walk = walk
	creature.cycle = cycle
	-- The ground along its walk (it keeps to the spot's height where a ray misses)
	local side = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
	local lifts: { number } = {}
	for k = 0, 4 do
		local along = hit.Position + side * (k / 4 - 0.5) * walk
		local under = castDown(along.X, along.Z)
		local y = if under and math.abs(under.Position.Y - hit.Position.Y) < walk
			then under.Position.Y
			else hit.Position.Y
		table.insert(lifts, y)
	end
	creature.lifts = lifts
	local model = creature.model
	local shell =
		part(model, Vector3.new(size, size * 0.42, size * 0.75), color, Enum.Material.SmoothPlastic, 0)
	local legs = part(
		model,
		Vector3.new(size * 1.6, size * 0.12, size * 0.9),
		color:Lerp(Color3.new(0, 0, 0), 0.45),
		Enum.Material.SmoothPlastic,
		0
	)
	local claw = color:Lerp(Color3.new(0, 0, 0), 0.15)
	local left =
		part(model, Vector3.new(size * 0.32, size * 0.22, size * 0.34), claw, Enum.Material.SmoothPlastic, 0)
	local right =
		part(model, Vector3.new(size * 0.32, size * 0.22, size * 0.34), claw, Enum.Material.SmoothPlastic, 0)
	add(creature, { shell, legs, left, right })
	return creature, false
end

-- How far along its walk a crab is (0..1) and whether it's moving
local function crabStep(creature: Creature, t: number): (number, boolean)
	local u = ((t + creature.phase) % creature.cycle) / creature.cycle
	local function ease(x: number): number
		return x * x * (3 - 2 * x)
	end
	if u < 0.15 then
		return ease(u / 0.15), true
	elseif u < 0.5 then
		return 1, false
	elseif u < 0.65 then
		return 1 - ease((u - 0.5) / 0.15), true
	end
	return 0, false
end

local function crabAt(creature: Creature, t: number): Vector3
	local s = crabStep(creature, t)
	local side = Vector3.new(math.cos(creature.yaw), 0, -math.sin(creature.yaw))
	local at = creature.home + side * (s - 0.5) * creature.walk
	local lifts = creature.lifts
	if lifts then
		local u = s * (#lifts - 1)
		local i = math.clamp(math.floor(u), 0, #lifts - 2)
		local y = lifts[i + 1] + (lifts[i + 2] - lifts[i + 1]) * (u - i)
		at = Vector3.new(at.X, y, at.Z)
	end
	return at
end

local function poseCrab(creature: Creature, t: number, at: Vector3)
	local size = creature.size
	local p = creature.phase
	local _, moving = crabStep(creature, t)
	-- (resting, it stays put: nothing to move until it scuttles again)
	if not moving and creature.still then
		return
	end
	creature.still = not moving
	local bob = if moving then math.abs(math.sin(t * 22 + p)) * size * 0.06 else 0
	local frame = CFrame.new(at + Vector3.new(0, size * 0.3 + bob, 0)) * CFrame.Angles(0, creature.yaw, 0)
	local jitter = if moving then math.sin(t * 30 + p) * 0.12 else 0
	table.insert(moveParts, creature.parts[1])
	table.insert(moveFrames, frame)
	table.insert(moveParts, creature.parts[2])
	table.insert(moveFrames, frame * CFrame.new(0, -size * 0.14, 0) * CFrame.Angles(0, jitter, 0))
	for k, sign in { -1, 1 } do
		local raise = if moving then math.sin(t * 9 + p + sign) * size * 0.06 else 0
		table.insert(moveParts, creature.parts[2 + k])
		table.insert(
			moveFrames,
			frame
				* CFrame.new(sign * size * 0.42, size * 0.04 + raise, -size * 0.48)
				* CFrame.Angles(0, sign * 0.4, 0)
		)
	end
end

----------------------------------------------------------------------------------
-- Turtles: a domed shell, a head and four flippers, the front pair rowing; they
-- cruise big slow loops well over the shelf.

local function makeTurtle(rng: Random, key: number, x: number, z: number, _floor: number): Creature?
	local kind = KINDS.turtle
	local size = rng:NextNumber(kind.size[1], kind.size[2])
	local creature = newCreature("turtle", key, Vector3.new(x, 0, z), size, rng:NextNumber(0, 2 * math.pi))
	creature.radius = rng:NextNumber(40, 80)
	creature.ellipse = rng:NextNumber(0.55, 1)
	local speed = kind.speed or { 4, 4 }
	creature.angular = rng:NextNumber(speed[1], speed[2])
		/ creature.radius
		* (if rng:NextNumber() < 0.5 then -1 else 1)
	local depth = kind.depth or { 20, 40 }
	local clear = rng:NextNumber(depth[1], depth[2])
	local color = kind.colors[rng:NextInteger(1, #kind.colors)]
	creature.lifts = loopLifts(creature, 24, clear, 0.3)
	local model = creature.model
	local skin = color:Lerp(Color3.fromRGB(120, 140, 100), 0.6)
	local shell =
		part(model, Vector3.new(size * 0.8, size * 0.3, size), color, Enum.Material.SmoothPlastic, 0)
	local dome = part(
		model,
		Vector3.new(size * 0.62, size * 0.3, size * 0.78),
		color:Lerp(Color3.new(0, 0, 0), 0.25),
		Enum.Material.SmoothPlastic,
		0
	)
	local head =
		part(model, Vector3.new(size * 0.24, size * 0.2, size * 0.3), skin, Enum.Material.SmoothPlastic, 0)
	local pieces: { BasePart } = { shell, dome, head }
	for _ = 1, 2 do
		table.insert(
			pieces,
			part(
				model,
				Vector3.new(size * 0.75, size * 0.06, size * 0.26),
				skin,
				Enum.Material.SmoothPlastic,
				0
			)
		)
	end
	for _ = 1, 2 do
		table.insert(
			pieces,
			part(
				model,
				Vector3.new(size * 0.3, size * 0.05, size * 0.2),
				skin,
				Enum.Material.SmoothPlastic,
				0
			)
		)
	end
	add(creature, pieces)
	return creature
end

local function poseTurtle(creature: Creature, t: number)
	local size = creature.size
	local p = creature.phase
	local at, heading = onLoop(creature, t)
	local stroke = math.sin(t * 1.3 + p)
	at += Vector3.new(0, stroke * size * 0.08, 0)
	local frame = CFrame.lookAt(at, at + heading)
		* CFrame.Angles(stroke * 0.05, 0, -math.sign(creature.angular) * 0.1)
	local parts = creature.parts
	table.insert(moveParts, parts[1])
	table.insert(moveFrames, frame)
	table.insert(moveParts, parts[2])
	table.insert(moveFrames, frame * CFrame.new(0, size * 0.1, 0))
	table.insert(moveParts, parts[3])
	table.insert(moveFrames, frame * CFrame.new(0, size * 0.02, -size * 0.6))
	for k, sign in { -1, 1 } do
		table.insert(moveParts, parts[3 + k])
		table.insert(
			moveFrames,
			frame
				* CFrame.new(sign * size * 0.3, -size * 0.02, -size * 0.22)
				* CFrame.Angles(0, sign * 0.5, sign * stroke * 0.5)
				* CFrame.new(sign * size * 0.3, 0, 0)
		)
		table.insert(moveParts, parts[5 + k])
		table.insert(
			moveFrames,
			frame
				* CFrame.new(sign * size * 0.25, -size * 0.04, size * 0.42)
				* CFrame.Angles(0, -sign * 0.6, -sign * stroke * 0.2)
				* CFrame.new(sign * size * 0.1, 0, 0)
		)
	end
end

----------------------------------------------------------------------------------
-- Reef-fish clouds: a handful of tiny bright fish circling and darting over a coral
-- head (the corals near the camera, looked for every so often).

local function makeCloud(key: number, top: Vector3): Creature
	local kind = KINDS.cloud
	local rng = Random.new(key)
	local center = top + Vector3.new(0, rng:NextNumber(1.5, 4), 0)
	local creature = newCreature("cloud", key, center, rng:NextNumber(2, 4.5), rng:NextNumber(0, 2 * math.pi))
	local main = kind.colors[rng:NextInteger(1, #kind.colors)]
	local fishSize = rng:NextNumber(kind.size[1], kind.size[2])
	local count = rng:NextInteger(Ambient.cloudFish[1], Ambient.cloudFish[2])
	local fish = {}
	local pieces: { BasePart } = {}
	for _ = 1, count do
		local color = if rng:NextNumber() < 0.75 then main else kind.colors[rng:NextInteger(1, #kind.colors)]
		local size = fishSize * rng:NextNumber(0.8, 1.2)
		table.insert(
			pieces,
			part(
				creature.model,
				Vector3.new(size * 0.35, size * 0.55, size),
				color,
				Enum.Material.SmoothPlastic,
				0
			)
		)
		table.insert(fish, {
			a = rng:NextNumber(0, 2 * math.pi),
			w = rng:NextNumber(0.6, 1.3) * (if rng:NextNumber() < 0.5 then -1 else 1),
			r = rng:NextNumber(0.35, 1),
			h = rng:NextNumber(-0.5, 0.5),
		})
	end
	creature.fish = fish
	add(creature, pieces)
	return creature
end

local function poseCloud(creature: Creature, t: number)
	local fish = creature.fish
	if fish == nil then
		return
	end
	local center = creature.home
	local radius = creature.size
	for i, f in fish do
		local a = f.a + f.w * t
		local r = radius * f.r * (1 + 0.25 * math.sin(t * 0.7 + f.a * 3))
		local at = center
			+ Vector3.new(math.cos(a) * r, (f.h + math.sin(t * 1.3 + f.a) * 0.25) * radius, math.sin(a) * r)
		local heading = Vector3.new(-math.sin(a), 0, math.cos(a)) * math.sign(f.w)
		table.insert(moveParts, creature.parts[i])
		table.insert(moveFrames, CFrame.lookAt(at, at + heading))
	end
end

----------------------------------------------------------------------------------
-- Giants: a whale or a manta crossing the Open Blue on a long line, seen far off
-- through the haze (part-built: never close enough to look at).

local function giantLine(lane: number, slot: number): (string, Vector3, Vector3, number)
	local rng = Random.new(seedOf(lane, slot, SALT.giant))
	local kind = KINDS.giant
	local which = if rng:NextNumber() < 0.55 then "whale" else "manta"
	local length = rng:NextNumber(kind.size[1], kind.size[2])
	local r = rng:NextNumber(1050, 1350)
	local angle = math.rad(rng:NextNumber(234, 306))
	local x, z = math.cos(angle) * r, math.sin(angle) * r
	-- Roughly across the sector (along the circle), so it stays in the Open Blue
	local heading = angle + math.pi / 2 + rng:NextNumber(-0.5, 0.5)
	local floor = Seafloor.y(x, z)
	local y = math.min(floor + rng:NextNumber(150, 360), World.surfaceY - 60)
	local half = Ambient.giants.lane / 2
	local direction = Vector3.new(math.cos(heading), 0, math.sin(heading))
	local middle = Vector3.new(x, y, z)
	local function inside(point: Vector3): Vector3
		local flat = Vector2.new(point.X, point.Z)
		if flat.Magnitude > 1460 then
			flat = flat.Unit * 1460
		end
		return Vector3.new(flat.X, point.Y, flat.Y)
	end
	local from = inside(middle - direction * half)
	local to = inside(middle + direction * half + Vector3.new(0, rng:NextNumber(-40, 40), 0))
	if rng:NextNumber() < 0.5 then
		from, to = to, from
	end
	return which, from, to, if which == "whale" then length else length * 0.42
end

local function makeGiant(lane: number, slot: number): Creature
	local which, from, to, size = giantLine(lane, slot)
	local kind = KINDS.giant
	local creature = newCreature("giant", lane, from, size, (lane * 1.7) % (2 * math.pi))
	creature.giant = which
	creature.from = from
	creature.to = to
	local model = creature.model
	local pieces: { BasePart } = {}
	if which == "whale" then
		local color = kind.colors[1]
		local L = size
		for _, shape in
			{
				Vector3.new(L * 0.2, L * 0.2, L * 0.62), -- body
				Vector3.new(L * 0.17, L * 0.15, L * 0.3), -- head
				Vector3.new(L * 0.11, L * 0.1, L * 0.4), -- tail stock
				Vector3.new(L * 0.3, L * 0.025, L * 0.08), -- flippers
				Vector3.new(L * 0.3, L * 0.025, L * 0.08),
				Vector3.new(L * 0.17, L * 0.02, L * 0.09), -- flukes
				Vector3.new(L * 0.17, L * 0.02, L * 0.09),
			}
		do
			table.insert(pieces, part(model, shape, color, Enum.Material.SmoothPlastic, 0))
		end
	else
		local color = kind.colors[2]
		local W = size
		for _, shape in
			{
				Vector3.new(W * 0.3, W * 0.07, W * 0.38), -- body
				Vector3.new(W * 0.45, W * 0.04, W * 0.3), -- wings
				Vector3.new(W * 0.45, W * 0.04, W * 0.3),
				Vector3.new(W * 0.05, W * 0.03, W * 0.12), -- horns
				Vector3.new(W * 0.05, W * 0.03, W * 0.12),
				Vector3.new(W * 0.02, W * 0.02, W * 0.5), -- tail
			}
		do
			table.insert(pieces, part(model, shape, color, Enum.Material.SmoothPlastic, 0))
		end
	end
	add(creature, pieces)
	return creature
end

local function giantAt(creature: Creature, t: number): (Vector3, number)
	local period = Ambient.giants.period
	local lane = creature.key
	local u = ((t + lane * period / Ambient.giants.lanes) % period) / period
	local from, to = creature.from :: Vector3, creature.to :: Vector3
	return from:Lerp(to, u) + Vector3.new(0, math.sin(u * math.pi * 2) * 12, 0), u
end

local function poseGiant(creature: Creature, t: number, at: Vector3)
	local from, to = creature.from :: Vector3, creature.to :: Vector3
	local frame = CFrame.lookAt(at, at + (to - from))
	local parts = creature.parts
	local p = creature.phase
	if creature.giant == "whale" then
		local L = creature.size
		local beat = math.sin(t * 0.55 + p)
		local frames = {
			frame * CFrame.Angles(beat * 0.02, 0, 0),
			frame * CFrame.new(0, -L * 0.01, -L * 0.38),
			frame
				* CFrame.new(0, 0, L * 0.36)
				* CFrame.Angles(beat * 0.08, 0, 0)
				* CFrame.new(0, 0, L * 0.08),
			frame
				* CFrame.new(-L * 0.1, -L * 0.07, -L * 0.14)
				* CFrame.Angles(0, 0.5, -0.3 + beat * 0.08)
				* CFrame.new(-L * 0.14, 0, 0),
			frame
				* CFrame.new(L * 0.1, -L * 0.07, -L * 0.14)
				* CFrame.Angles(0, -0.5, 0.3 - beat * 0.08)
				* CFrame.new(L * 0.14, 0, 0),
		}
		local tail = frame * CFrame.new(0, 0, L * 0.5) * CFrame.Angles(beat * 0.3, 0, 0)
		table.insert(frames, tail * CFrame.Angles(0, -0.45, 0) * CFrame.new(-L * 0.07, 0, L * 0.03))
		table.insert(frames, tail * CFrame.Angles(0, 0.45, 0) * CFrame.new(L * 0.07, 0, L * 0.03))
		for i, piece in parts do
			table.insert(moveParts, piece)
			table.insert(moveFrames, frames[i])
		end
	else
		local W = creature.size
		local flap = math.sin(t * 0.6 + p) * 0.45
		local frames = {
			frame,
			frame * CFrame.new(-W * 0.12, 0, 0) * CFrame.Angles(0, -0.25, flap) * CFrame.new(-W * 0.2, 0, 0),
			frame * CFrame.new(W * 0.12, 0, 0) * CFrame.Angles(0, 0.25, -flap) * CFrame.new(W * 0.2, 0, 0),
			frame * CFrame.new(-W * 0.08, 0, -W * 0.22),
			frame * CFrame.new(W * 0.08, 0, -W * 0.22),
			frame * CFrame.new(0, 0, W * 0.4),
		}
		for i, piece in parts do
			table.insert(moveParts, piece)
			table.insert(moveFrames, frames[i])
		end
	end
end

----------------------------------------------------------------------------------
-- Building and letting go

type Maker = (Random, number, number, number, number) -> Creature?

local makers: { [string]: Maker } = {
	jelly = makeJelly,
	ray = makeRay,
	turtle = makeTurtle,
}

-- One square's creatures of one kind (from its seed), or nil to try it again later
local function buildSquare(id: string, key: number, cx: number, cz: number): { Creature }?
	local kind = KINDS[id]
	local rng = Random.new(seedOf(cx, cz, SALT[id]))
	local whole = math.floor(kind.perCell)
	local count = whole + (if rng:NextNumber() < kind.perCell - whole then 1 else 0)
	local made: { Creature } = {}
	for _ = 1, count do
		local x = (cx + rng:NextNumber()) * CELL
		local z = (cz + rng:NextNumber()) * CELL
		-- (a seed of its own, so a creature skipped here doesn't change the next)
		local own = Random.new(rng:NextInteger(1, 2 ^ 30))
		local floor = Seafloor.y(x, z)
		local r = Seafloor.polar(x, z)
		local biome = if r > HUB_CLEAR then Biomes.at(Vector3.new(x, floor + 6, z)) else nil
		if biome == nil or not inList(kind.biomes, biome.id) then
			continue
		end
		if id == "crab" then
			local crab, retry = makeCrab(own, key, x, z, floor)
			if retry then
				for _, creature in made do
					remove(creature)
				end
				return nil
			end
			if crab then
				table.insert(made, crab)
			end
		else
			local creature = makers[id](own, key, x, z, floor)
			if creature then
				table.insert(made, creature)
			end
		end
	end
	return made
end

local function dropSquare(key: number)
	local list = squares[key]
	if list then
		for _, creature in list do
			remove(creature)
		end
	end
	squares[key] = nil
	squareAt[key] = nil
end

-- Which squares should be built for the camera now: new ones built nearest first
-- (within a budget), far ones let go
local function refreshSquares(camera: Vector3, scale: number, now: number)
	local wanted: { { key: number, id: string, cx: number, cz: number, away: number } } = {}
	for index, id in SQUARE_KINDS do
		local kind = KINDS[id]
		local reach = kind.range * scale + CELL * 0.75
		for cx = math.floor((camera.X - reach) / CELL), math.floor((camera.X + reach) / CELL) do
			for cz = math.floor((camera.Z - reach) / CELL), math.floor((camera.Z + reach) / CELL) do
				local middle = Vector2.new((cx + 0.5) * CELL, (cz + 0.5) * CELL)
				local away = (middle - Vector2.new(camera.X, camera.Z)).Magnitude
				local key = index * 100_000_000 + (cx + 5000) * 10_000 + (cz + 5000)
				if away <= reach and squares[key] == nil and (retryAt[key] or 0) <= now then
					table.insert(wanted, { key = key, id = id, cx = cx, cz = cz, away = away })
				end
			end
		end
	end
	-- Let go of squares well out of reach
	for key, middle in squareAt do
		local index = math.floor(key / 100_000_000)
		local id = SQUARE_KINDS[index]
		local reach = KINDS[id].range * scale + CELL * 1.5
		if (middle - Vector2.new(camera.X, camera.Z)).Magnitude > reach then
			dropSquare(key)
		end
	end
	if #wanted == 0 then
		return
	end
	table.sort(wanted, function(a, b)
		return a.away < b.away
	end)
	local started = os.clock()
	for _, entry in wanted do
		if os.clock() - started > SPAWN_BUDGET then
			break
		end
		if (counts[entry.id] or 0) >= KINDS[entry.id].max then
			continue
		end
		local made = buildSquare(entry.id, entry.key, entry.cx, entry.cz)
		if made == nil then
			retryAt[entry.key] = now + 2 -- (its ground isn't in yet)
		else
			retryAt[entry.key] = nil
			squares[entry.key] = made
			squareAt[entry.key] = Vector2.new((entry.cx + 0.5) * CELL, (entry.cz + 0.5) * CELL)
		end
	end
end

-- The coral heads near the camera, a reef-fish cloud over each of the nearest
local function refreshClouds(camera: Vector3, scale: number)
	local kind = KINDS.cloud
	local range = kind.range * scale
	local world = workspace:FindFirstChild("World")
	local biomes = world and world:FindFirstChild("Biomes")
	local coral = biomes and biomes:FindFirstChild("Coral")
	local keep: { [number]: Vector3 } = {}
	if coral then
		local params = coralParams or OverlapParams.new()
		coralParams = params
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { coral }
		params.RespectCanCollide = false
		local tops: { [number]: Vector3 } = {}
		for _, piece in workspace:GetPartBoundsInRadius(camera, range, params) do
			local position = piece.Position
			local cx = math.floor(position.X / Ambient.cloudCell)
			local cz = math.floor(position.Z / Ambient.cloudCell)
			local key = seedOf(cx, cz, SALT.cloud)
			local top = position + Vector3.new(0, piece.Size.Y * 0.5, 0)
			local known: Vector3? = tops[key]
			if known == nil or top.Y > known.Y then
				tops[key] = top
			end
		end
		local found: { { key: number, top: Vector3, away: number } } = {}
		for key, top in tops do
			local biome = Biomes.at(top)
			if biome and inList(kind.biomes, biome.id) then
				table.insert(found, { key = key, top = top, away = (top - camera).Magnitude })
			end
		end
		table.sort(found, function(a, b)
			return a.away < b.away
		end)
		for i = 1, math.min(kind.max, #found) do
			keep[found[i].key] = found[i].top
		end
	end
	for key, cloud in clouds do
		local kept: Vector3? = keep[key]
		if kept == nil and (cloud.home - camera).Magnitude > range * 0.9 then
			remove(cloud)
			clouds[key] = nil
		end
	end
	for key, top in keep do
		if clouds[key] == nil and (counts.cloud or 0) < kind.max + 2 then
			clouds[key] = makeCloud(key, top)
		end
	end
end

-- The giants' lanes: each its creature for this pass, built only while it's near
local function refreshGiants(camera: Vector3, now: number, bossUp: boolean)
	local settings = Ambient.giants
	local range = KINDS.giant.range
	for lane = 1, settings.lanes do
		local slot = math.floor((now + lane * settings.period / settings.lanes) / settings.period)
		local current: Creature? = giants[lane]
		if current and (giantSlot[lane] ~= slot or bossUp) then
			remove(current)
			giants[lane] = nil
			current = nil
		end
		if current == nil and not bossUp then
			local _, from, to = giantLine(lane, slot)
			-- (the nearest the line comes to the camera)
			local line = to - from
			local u = math.clamp((camera - from):Dot(line) / math.max(line:Dot(line), 1), 0, 1)
			if (from + line * u - camera).Magnitude < range + 120 then
				giants[lane] = makeGiant(lane, slot)
				giantSlot[lane] = slot
			end
		end
	end
end

----------------------------------------------------------------------------------

local function centerOf(creature: Creature, t: number): Vector3
	local kind = creature.kind
	if kind == "jelly" then
		return jellyAt(creature, t)
	elseif kind == "crab" then
		return crabAt(creature, t)
	elseif kind == "cloud" then
		return creature.home
	elseif kind == "giant" then
		return (giantAt(creature, t))
	end
	return (onLoop(creature, t))
end

local function step(dt: number)
	local now = Timing.clock()
	local camera = workspace.CurrentCamera.CFrame.Position
	local scale = SchoolController.detail()
	-- Near a world boss everything fades away (and the giants hide while one is up)
	local boss = BossController.position()
	local bossUp = boss ~= nil
	local nearBoss = boss ~= nil and (boss - camera).Magnitude < Ambient.bossClear
	bossFade = math.clamp(bossFade + (if nearBoss then dt else -dt) / 1.5, 0, 1)
	if now >= nextRefresh then
		nextRefresh = now + REFRESH
		refreshSquares(camera, scale, now)
		refreshGiants(camera, now, bossUp)
	end
	if now >= nextScan then
		nextScan = now + Ambient.cloudScan
		refreshClouds(camera, scale)
		-- (a readout on the folder for play tests: how many of each are built)
		for id in KINDS do
			folder:SetAttribute(id, counts[id] or 0)
		end
	end
	table.clear(moveParts)
	table.clear(moveFrames)
	for creature in creatures do
		local kind = KINDS[creature.kind]
		local at = centerOf(creature, now)
		local away = (at - camera).Magnitude
		local range = if creature.kind == "giant" then kind.range else kind.range * scale
		local fade = 0
		if away > range * (1 - FADE_SHARE) then
			fade = (away - range * (1 - FADE_SHARE)) / (range * FADE_SHARE)
		end
		if creature.kind == "giant" then
			-- never close, and in and out at the ends of its line
			local near = Ambient.giants.near
			fade = math.max(fade, 1 - (away - near) / 50)
			local _, u = giantAt(creature, now)
			fade = math.max(fade, 1 - math.min(u, 1 - u) / 0.08)
		end
		fade = math.max(fade, bossFade)
		fade = math.clamp(math.floor(fade * 10 + 0.5) / 10, 0, 1)
		if fade ~= creature.fade then
			setFade(creature, fade)
		end
		if fade >= 1 then
			creature.still = false -- (posed afresh when it's back in range)
			continue
		end
		local id = creature.kind
		if id == "jelly" then
			poseJelly(creature, now, at, away)
		elseif id == "ray" then
			poseRay(creature, now)
		elseif id == "crab" then
			poseCrab(creature, now, at)
		elseif id == "turtle" then
			poseTurtle(creature, now)
		elseif id == "cloud" then
			poseCloud(creature, now)
		elseif id == "giant" then
			poseGiant(creature, now, at)
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function AmbientLifeController.start()
	folder = Instance.new("Folder")
	folder.Name = "AmbientLife"
	folder.Parent = workspace
	RunService.RenderStepped:Connect(step)
end

-- How many ambient creatures are built now, by kind (the admin panel's readout, tests)
function AmbientLifeController.counts(): { [string]: number }
	return table.clone(counts)
end

return AmbientLifeController
