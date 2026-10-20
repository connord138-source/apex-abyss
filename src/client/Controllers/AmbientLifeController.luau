--!strict
-- Sea life that isn't food (owner, 2026-10-18: "We still need so much more fish too. I
-- feel like the ocean has a pretty empty feeling"; "Think Subnautica"): jellyfish
-- drifting in the deep water, stingrays gliding over the sand and settling into it,
-- mantas flying slow loops over the reef and the wrecks, turtles rowing over the shelf,
-- clouds of tiny reef fish over the coral heads, and whales and mantas passing far off
-- through the Open Blue's haze (Config/Ambient). Client-only: nothing replicates,
-- nothing is eaten (the crabs are food now: Config/Forage, ForageController).
--
-- The rays, mantas, turtles and giants are their imported models
-- (ReplicatedStorage.AmbientModels) or, until those are in, faceted part-built stand-ins
-- (owner, 2026-10-19: "the sea turtles and manta rays/stingrays need to be dialed up
-- they're essentially just circles put together"); both are AmbientBody, posed by
-- Shared/AmbientRigs: the manta's slow, powerful flap with its wingtips lagging, the
-- stingray's ripple along its disc edge, the turtle's sweeping front-flipper strokes and
-- glide with its hind flippers as rudders and its head bobbing, the humpback's
-- pectorals and fluke stroke; all bank into their turns. Joints move every frame within
-- a kind's `animate` range, every other frame out to twice that, and hold their pose
-- beyond; at most Config/Ambient `jointBudget` joint turns a frame, nearest first.
--
-- The sea is cut into squares (Config/Ambient `CELL`); a square's creatures come from a
-- seed of its position and move on the shared clock, so a place always holds the same
-- life doing the same thing. Only squares near the camera are built (nearest first,
-- a few a refresh), and each creature fades in and out at the edge of its range
-- (LocalTransparencyModifier), so nothing pops. Its ranges shrink with the prey
-- schools' on a slow device (SchoolController.detail). Near a world boss everything
-- fades away, and the giants hide while one is up. The folder `Workspace.AmbientLife`
-- carries a readout for play tests: how many of each are built, and `PoseMs` / `Joints`
-- (the posing's cost a frame, averaged over a second).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AmbientRigs = require(ReplicatedStorage.Shared.AmbientRigs)
local Biomes = require(ReplicatedStorage.Shared.Biomes)
local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Giants = require(ReplicatedStorage.Shared.Giants)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Timing = require(ReplicatedStorage.Shared.Timing)
local AmbientBody = require(script.Parent.Parent.AmbientBody)
local BossController = require(script.Parent.BossController)
local SchoolController = require(script.Parent.SchoolController)
local SwimController = require(script.Parent.SwimController)
local ClientState = require(script.Parent.Parent.ClientState)
local HudController = require(script.Parent.HudController)
local HuntController = require(script.Parent.HuntController)

local Ambient = Config.Ambient
local World = Config.World
local KINDS = Ambient.kinds
type Kind = typeof(KINDS.ray)
local CELL = Ambient.CELL
-- The kinds laid out by square, and a salt each for their seeds (the crab's 3 stays
-- retired, so the others' squares hold what they did)
local SQUARE_KINDS = { "jelly", "ray", "manta", "turtle" }
local SALT: { [string]: number } = { jelly = 1, ray = 2, turtle = 4, cloud = 5, giant = 6, manta = 7 }
local HUB_CLEAR = 210 -- studs from the hub's middle: its seamount, no life laid out
-- Sea life that helps (Config/Companions; CompanionService checks and pays, and
-- CompanionController draws a turtle at an escorted fish's side): a turtle we've swum
-- beside since `turtleSince` (its key `turtleKey`), the one swimming with us now (its
-- loop's copy hidden meanwhile), when another may join or a ray be flushed, and each
-- flushed ray (key → when: it bursts off the sand and is gone from our view a while)
local Companions = Config.Companions
local INTERACT = 140 -- studs from the camera within which they notice our fish
local RAY_BURST = 1.2 -- seconds a flushed ray takes to burst away and fade
local turtleKey: number? = nil
local turtleSince = 0
local escortKey: number? = nil
local turtleAgain = 0
local rayAgain = 0
local flushed: { [number]: number } = {}
local FADE_SHARE = 0.2 -- the last share of a range a creature fades over
local REFRESH = 0.4 -- seconds between looks at which squares should be built
local SPAWN_BUDGET = 0.002 -- seconds a refresh may spend building squares
local NEAR_DETAIL = 90 -- studs: closer than this, jellies pulse and trail their tentacles
local WHITE = Color3.new(1, 1, 1)
local SAND = Color3.fromRGB(176, 170, 152)
local TAU = 2 * math.pi

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
	lifts: { number }?, -- heights round its loop it swims at (rays, mantas, turtles)
	ground: { number }?, -- the ground's heights round its loop (rays settle onto it)
	pulse: number, -- a jelly's beats a second
	bellMesh: SpecialMesh?,
	rimMesh: SpecialMesh?,
	tips: { Attachment }?,
	tipRest: { Vector3 }?,
	beams: { Beam }?,
	-- a reef cloud's fish: where each circles, and its parts with their offsets from
	-- the fish's own frame (a model's mesh, or a part-built body, tail and fin)
	fish: { CloudFish }?,
	startle: number, -- a reef cloud scattering from a fish swimming into it, 0–1
	from: Vector3?, -- a giant's line
	to: Vector3?,
	giant: string?, -- "whale" | "manta"
	body: AmbientBody.Body?, -- a ray's, manta's, turtle's or giant's
	beat: number, -- seconds a flap, stroke or ripple
	cycle: number, -- a stingray's day (Config/Ambient `settle`)
	restFor: number,
	settled: number, -- how settled it was last frame (0 .. 1)
	puff: ParticleEmitter?,
	posedAt: number, -- when its joints last moved
	motion: AmbientRigs.Motion,
}

type CloudFish = { a: number, w: number, r: number, h: number, parts: { BasePart }, offsets: { CFrame } }

local AmbientLifeController = {}

local folder: Folder
local creatures: { [Creature]: boolean } = {}
local squares: { [number]: { Creature } } = {} -- square key → its creatures (maybe none)
local squareAt: { [number]: Vector2 } = {} -- square key → its middle
local counts: { [string]: number } = {}
local clouds: { [number]: Creature } = {} -- coral square key → its cloud
local giants: { [number]: Creature } = {} -- lane → its giant this pass
local giantSlot: { [number]: number } = {}
local nextRefresh = 0
local nextScan = 0
local bossFade = 0
local frameCount = 0
local poseTime, poseFrames, jointsPosed = 0, 0, 0
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
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
		ground = nil,
		pulse = 1,
		bellMesh = nil,
		rimMesh = nil,
		tips = nil,
		tipRest = nil,
		beams = nil,
		fish = nil,
		startle = 0,
		from = nil,
		to = nil,
		giant = nil,
		body = nil,
		beat = 1,
		cycle = 1,
		restFor = 0,
		settled = 0,
		puff = nil,
		posedAt = -math.huge,
		motion = {
			t = 0,
			phase = phase,
			period = 1,
			bank = 0,
			turn = 0,
			rest = 0,
			settled = -1,
			moving = true,
		},
	}
end

-- Out of sight to start with: it fades in as it comes into range
local function setFade(creature: Creature, fade: number)
	creature.fade = fade
	local body = creature.body
	if body then
		AmbientBody.fade(body, fade)
	end
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

-- Heights round a loop (for things that glide or cruise over it): `count` samples of
-- the real ground plus `clear`, eased so a rise is a ramp, never a step; and the raw
-- ground under each
local function loopLifts(
	creature: Creature,
	count: number,
	clear: number,
	slope: number
): ({ number }, { number })
	local lifts = table.create(count, 0)
	local ground = table.create(count, 0)
	local home = creature.home
	for k = 1, count do
		local a = (k - 1) / count * TAU
		local x = home.X + math.cos(a) * creature.radius
		local z = home.Z + math.sin(a) * creature.radius * creature.ellipse
		ground[k] = Ground.y(x, z)
		lifts[k] = ground[k] + clear
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
	return lifts, ground
end

local function liftAt(lifts: { number }, a: number): number
	local count = #lifts
	local u = ((a / TAU) % 1) * count
	local i = math.floor(u)
	local low = lifts[i % count + 1]
	local high = lifts[(i + 1) % count + 1]
	return low + (high - low) * (u - i)
end

-- Where a creature is at angle `a` round its loop (at its swimming height)
local function loopAt(creature: Creature, a: number): Vector3
	local r = creature.radius
	local home = creature.home
	local y = if creature.lifts then liftAt(creature.lifts, a) else home.Y
	return Vector3.new(home.X + math.cos(a) * r, y, home.Z + math.sin(a) * r * creature.ellipse)
end

-- Its frame at angle `a` (looking along its path, up and down with it) and how hard
-- it's turning: + right, radians a second
local function loopFrame(creature: Creature, a: number, yOffset: number): (CFrame, number)
	local step = 0.04 * math.sign(creature.angular)
	local here = loopAt(creature, a)
	local ahead = loopAt(creature, a + step)
	local after = loopAt(creature, a + 2 * step)
	local d1, d2 = ahead - here, after - ahead
	local yaw1 = math.atan2(-d1.X, -d1.Z)
	local yaw2 = math.atan2(-d2.X, -d2.Z)
	local dyaw = (yaw2 - yaw1 + math.pi) % TAU - math.pi
	-- (yaw grows turning left; the loop's angle runs at `angular` radians a second)
	local rate = -dyaw / math.abs(step) * math.abs(creature.angular)
	local at = here + Vector3.new(0, yOffset, 0)
	local flat = Vector3.new(d1.X, 0, d1.Z).Magnitude
	local climb = math.clamp(d1.Y / math.max(flat, 1e-3), -0.35, 0.35)
	local look = Vector3.new(d1.X, climb * flat, d1.Z)
	return CFrame.lookAt(at, at + look), rate
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
-- Rays, mantas and turtles: their bodies (Shared/AmbientRigs), each on a loop of its own

local function bodyOf(creature: Creature, kind: Kind, rig: string)
	local look = kind.look or {}
	if kind.tint and kind.look then
		-- (a stand-in's main colour is this creature's pick of `colors`)
		local picked = table.clone(kind.look)
		picked[kind.tint] = kind.colors[(creature.key + math.floor(creature.phase * 7)) % #kind.colors + 1]
		look = picked
	end
	creature.body = AmbientBody.new(rig, creature.size, look, { model = kind.model }, creature.model)
end

local function beatOf(rng: Random, kind: Kind): number
	local beat = kind.beat or { 2, 3 }
	return rng:NextNumber(beat[1], beat[2])
end

local function onLoopSetup(creature: Creature, rng: Random, kind: Kind, radius: { number })
	creature.radius = rng:NextNumber(radius[1], radius[2])
	creature.ellipse = rng:NextNumber(0.55, 1)
	local speed = kind.speed or { 4, 4 }
	creature.angular = rng:NextNumber(speed[1], speed[2])
		/ creature.radius
		* (if rng:NextNumber() < 0.5 then -1 else 1)
end

-- A stingray gliding low over the sand on a lazy loop, now and then easing down into
-- it in a puff of sand and lying there a while
local function makeRay(rng: Random, key: number, x: number, z: number, _floor: number): Creature?
	local kind = KINDS.ray
	local span = rng:NextNumber(kind.size[1], kind.size[2])
	local creature = newCreature("ray", key, Vector3.new(x, 0, z), span, rng:NextNumber(0, TAU))
	onLoopSetup(creature, rng, kind, { 16, 38 })
	local depth = kind.depth or { 2, 3 }
	local clear = rng:NextNumber(depth[1], depth[2])
	creature.beat = beatOf(rng, kind)
	local settle = Ambient.settle
	creature.cycle = rng:NextNumber(settle.cycle[1], settle.cycle[2])
	creature.restFor = rng:NextNumber(settle.rest[1], settle.rest[2])
	creature.lifts, creature.ground = loopLifts(creature, 18, clear + span * 0.05, 0.35)
	bodyOf(creature, kind, "stingray")
	local body = creature.body :: AmbientBody.Body
	-- A puff of sand as it lands and lifts off
	local attachment = Instance.new("Attachment")
	attachment.Parent = body.root
	local puff = Instance.new("ParticleEmitter")
	puff.Rate = 0
	puff.Color = ColorSequence.new(SAND)
	puff.LightInfluence = 1
	puff.Lifetime = NumberRange.new(1.4, 2.4)
	puff.Speed = NumberRange.new(span * 0.25, span * 0.55)
	puff.SpreadAngle = Vector2.new(80, 80)
	puff.EmissionDirection = Enum.NormalId.Top
	puff.Drag = 3
	puff.Acceleration = Vector3.new(0, -0.4, 0)
	puff.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, span * 0.12),
		NumberSequenceKeypoint.new(1, span * 0.4),
	})
	puff.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	puff.Parent = attachment
	creature.puff = puff
	add(creature, {})
	return creature
end

-- Where a ray is now, its frame, and how settled it is (it banks into its loop's turns
-- while gliding; settled it lies flat on the ground)
local function rayFrame(creature: Creature, t: number): (CFrame, number, number, number)
	local settle = Ambient.settle
	local covered, settled, since =
		AmbientRigs.rayTravel(t, creature.cycle, creature.restFor, settle.ease, creature.phase)
	local a = creature.phase + creature.angular * covered
	local frame, rate = loopFrame(creature, a, math.sin(t * 0.8 + creature.phase) * 0.3 * (1 - settled))
	if settled > 0 and creature.ground then
		local body = creature.body
		local rest = liftAt(creature.ground :: { number }, a) + (if body then body.floor else 0)
		local y = frame.Position.Y + (rest - frame.Position.Y) * settled
		frame = CFrame.new(frame.Position.X, y, frame.Position.Z) * frame.Rotation
		frame = frame:Lerp(
			CFrame.new(frame.Position) * CFrame.Angles(0, select(2, frame:ToOrientation()), 0),
			settled
		)
	end
	return frame, rate * (1 - settled), settled, since
end

-- A manta flying slow loops well over the reef and the wrecks
local function makeManta(rng: Random, key: number, x: number, z: number, _floor: number): Creature?
	local kind = KINDS.manta
	local span = rng:NextNumber(kind.size[1], kind.size[2])
	local creature = newCreature("manta", key, Vector3.new(x, 0, z), span, rng:NextNumber(0, TAU))
	onLoopSetup(creature, rng, kind, { 45, 90 })
	local depth = kind.depth or { 25, 60 }
	creature.beat = beatOf(rng, kind)
	creature.lifts = (loopLifts(creature, 24, rng:NextNumber(depth[1], depth[2]), 0.3))
	bodyOf(creature, kind, "manta")
	add(creature, {})
	return creature
end

-- A turtle rowing big slow loops over the shelf: each stroke surges it on, then it glides
local function makeTurtle(rng: Random, key: number, x: number, z: number, _floor: number): Creature?
	local kind = KINDS.turtle
	local size = rng:NextNumber(kind.size[1], kind.size[2])
	local creature = newCreature("turtle", key, Vector3.new(x, 0, z), size, rng:NextNumber(0, TAU))
	onLoopSetup(creature, rng, kind, { 40, 80 })
	local depth = kind.depth or { 20, 40 }
	creature.beat = beatOf(rng, kind)
	creature.lifts = (loopLifts(creature, 24, rng:NextNumber(depth[1], depth[2]), 0.3))
	bodyOf(creature, kind, "turtle")
	add(creature, {})
	return creature
end

-- Where a loop creature is now: its frame and turn rate
local function cruiseFrame(creature: Creature, t: number): (CFrame, number)
	local covered = if creature.kind == "turtle"
		then AmbientRigs.turtleTravel(t, creature.beat, creature.phase)
		else t
	local a = creature.phase + creature.angular * covered
	local bob = if creature.kind == "manta" then 0 else math.sin(t * 0.5 + creature.phase) * 0.6
	return loopFrame(creature, a, bob)
end

----------------------------------------------------------------------------------
-- Giants: a humpback or a manta crossing the Open Blue on a long line, seen far off
-- through the haze

local function giantLine(lane: number, slot: number): (string, Vector3, Vector3, number)
	return Giants.line(lane, slot)
end

local function makeGiant(lane: number, slot: number): Creature
	local which, from, to, size = giantLine(lane, slot)
	local creature = newCreature("giant", lane, from, size, (lane * 1.7) % TAU)
	creature.giant = which
	creature.from = from
	creature.to = to
	local settings = if which == "whale" then Ambient.giants.whale else Ambient.giants.manta
	local rng = Random.new(seedOf(lane, slot, SALT.giant + 1))
	creature.beat = rng:NextNumber(settings.beat[1], settings.beat[2])
	creature.body =
		AmbientBody.new(settings.rig, size, settings.look, { model = settings.model }, creature.model)
	add(creature, {})
	return creature
end

local function giantAt(creature: Creature, t: number): (Vector3, number)
	return Giants.at(creature.key, creature.from :: Vector3, creature.to :: Vector3, t)
end

----------------------------------------------------------------------------------
-- Reef-fish clouds: a handful of tiny bright fish circling and darting over a coral
-- head (the corals near the camera, looked for every so often).

-- The little fish a cloud is made of (owner, 2026-10-20: "little groups of fish or
-- something that are just spheres"): a small reef species' own model shrunk to fry
-- size (Config/Ambient `cloudPrey`, by biome; the rigged model faces -Z, its mesh
-- moved with its bones), else a part-built one (body, tail and dorsal fin)
type CloudProto = { model: Model, length: number }
local cloudProtos: { [string]: CloudProto | false } = {}

local function cloudProto(preyId: string): CloudProto?
	local known = cloudProtos[preyId]
	if known == false then
		return nil
	elseif known then
		return known :: CloudProto
	end
	local models = ReplicatedStorage:FindFirstChild("PreyModels")
	local template = models and models:FindFirstChild(preyId)
	if
		template == nil
		or not template:IsA("Model")
		or template:FindFirstChildWhichIsA("MeshPart", true) == nil
	then
		cloudProtos[preyId] = false
		return nil
	end
	local clone = template:Clone()
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		end
	end
	clone:ScaleTo(1)
	local proto = { model = clone, length = math.max(clone:GetExtentsSize().Z, 0.01) }
	cloudProtos[preyId] = proto
	return proto
end

local function cloudFish(
	parent: Instance,
	proto: CloudProto?,
	size: number,
	color: Color3
): ({ BasePart }, { CFrame })
	if proto then
		local clone = proto.model:Clone()
		clone:ScaleTo(size / proto.length)
		local mesh = clone:FindFirstChildWhichIsA("MeshPart", true) :: MeshPart
		local box = clone:GetBoundingBox()
		local base = CFrame.new(box.Position) * clone:GetPivot().Rotation
		local offset = base:ToObjectSpace(mesh.CFrame)
		mesh.Parent = parent
		clone:Destroy()
		return { mesh }, { offset }
	end
	local body =
		part(parent, Vector3.new(size * 0.32, size * 0.5, size * 0.8), color, Enum.Material.SmoothPlastic, 0)
	local tail = Instance.new("WedgePart")
	tail.Anchored = true
	tail.CanCollide = false
	tail.CanQuery = false
	tail.CanTouch = false
	tail.CastShadow = false
	tail.Material = Enum.Material.SmoothPlastic
	tail.Color = color:Lerp(Color3.new(0, 0, 0), 0.15)
	tail.Size = Vector3.new(size * 0.04, size * 0.42, size * 0.3)
	tail.Parent = parent
	local fin = tail:Clone()
	fin.Size = Vector3.new(size * 0.03, size * 0.18, size * 0.32)
	fin.Parent = parent
	-- (-Z is ahead: the tail behind the body, its wedge's slope facing back; the fin on top)
	return { body, tail, fin }, {
		CFrame.identity,
		CFrame.new(0, 0, size * 0.52) * CFrame.Angles(0, math.pi, 0),
		CFrame.new(0, size * 0.27, size * 0.05),
	}
end

local function makeCloud(key: number, top: Vector3): Creature
	local kind = KINDS.cloud
	local rng = Random.new(key)
	local center = top + Vector3.new(0, rng:NextNumber(1.5, 4), 0)
	local creature = newCreature("cloud", key, center, rng:NextNumber(2, 4.5), rng:NextNumber(0, 2 * math.pi))
	local main = kind.colors[rng:NextInteger(1, #kind.colors)]
	local fishSize = rng:NextNumber(kind.size[1], kind.size[2])
	local count = rng:NextInteger(Ambient.cloudFish[1], Ambient.cloudFish[2])
	-- One species a cloud, from the biome it's in
	local biome = Biomes.at(center)
	local species = Ambient.cloudPrey[if biome then biome.id else ""] or Ambient.cloudPrey.default
	local proto = cloudProto(species[rng:NextInteger(1, #species)])
	local fish: { CloudFish } = {}
	local pieces: { BasePart } = {}
	for _ = 1, count do
		local color = if rng:NextNumber() < 0.75 then main else kind.colors[rng:NextInteger(1, #kind.colors)]
		local parts, offsets = cloudFish(creature.model, proto, fishSize * rng:NextNumber(0.8, 1.2), color)
		for _, piece in parts do
			table.insert(pieces, piece)
		end
		table.insert(fish, {
			a = rng:NextNumber(0, 2 * math.pi),
			w = rng:NextNumber(0.6, 1.3) * (if rng:NextNumber() < 0.5 then -1 else 1),
			r = rng:NextNumber(0.35, 1),
			h = rng:NextNumber(-0.5, 0.5),
			parts = parts,
			offsets = offsets,
		})
	end
	creature.fish = fish
	add(creature, pieces)
	return creature
end

-- A cloud scatters when a fish swims into it: wider and quicker for a few seconds
local STARTLE_REACH = 7 -- studs past the cloud's own size
local lastCloudAt = 0

local function poseCloud(creature: Creature, t: number, fishAt: Vector3?)
	local fish = creature.fish
	if fish == nil then
		return
	end
	local center = creature.home
	local dt = math.clamp(t - lastCloudAt, 0, 0.1)
	local near = fishAt ~= nil and (fishAt - center).Magnitude < creature.size + STARTLE_REACH
	creature.startle = math.clamp(creature.startle + (if near then dt * 4 else -dt * 0.6), 0, 1)
	local spread = 1 + 1.4 * creature.startle
	local radius = creature.size * spread
	for _, f in fish do
		local a = f.a + f.w * (t + creature.startle * 1.5)
		local r = radius * f.r * (1 + 0.25 * math.sin(t * 0.7 + f.a * 3))
		local at = center
			+ Vector3.new(math.cos(a) * r, (f.h + math.sin(t * 1.3 + f.a) * 0.25) * radius, math.sin(a) * r)
		local heading = Vector3.new(-math.sin(a), 0, math.cos(a)) * math.sign(f.w)
		local frame = CFrame.lookAt(at, at + heading)
		for i, piece in f.parts do
			table.insert(moveParts, piece)
			table.insert(moveFrames, frame * f.offsets[i])
		end
	end
end

----------------------------------------------------------------------------------
-- Building and letting go

type Maker = (Random, number, number, number, number) -> Creature?

local makers: { [string]: Maker } = {
	jelly = makeJelly,
	ray = makeRay,
	manta = makeManta,
	turtle = makeTurtle,
}

-- One square's creatures of one kind (from its seed)
local function buildSquare(id: string, key: number, cx: number, cz: number): { Creature }
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
		local creature = makers[id](own, key, x, z, floor)
		if creature then
			table.insert(made, creature)
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
local function refreshSquares(camera: Vector3, scale: number)
	local wanted: { { key: number, id: string, cx: number, cz: number, away: number } } = {}
	for index, id in SQUARE_KINDS do
		local kind = KINDS[id]
		local reach = kind.range * scale + CELL * 0.75
		for cx = math.floor((camera.X - reach) / CELL), math.floor((camera.X + reach) / CELL) do
			for cz = math.floor((camera.Z - reach) / CELL), math.floor((camera.Z + reach) / CELL) do
				local middle = Vector2.new((cx + 0.5) * CELL, (cz + 0.5) * CELL)
				local away = (middle - Vector2.new(camera.X, camera.Z)).Magnitude
				local key = index * 100_000_000 + (cx + 5000) * 10_000 + (cz + 5000)
				if away <= reach and squares[key] == nil then
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
		squares[entry.key] = buildSquare(entry.id, entry.key, entry.cx, entry.cz)
		squareAt[entry.key] = Vector2.new((entry.cx + 0.5) * CELL, (entry.cz + 0.5) * CELL)
	end
end

-- The coral heads near the camera, a reef-fish cloud over each of the nearest
local function refreshClouds(camera: Vector3, scale: number)
	local kind = KINDS.cloud
	if kind.max <= 0 then
		return -- (the clouds are real prey now: Config/Prey `laterZones`)
	end
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

-- A creature's frame this moment (rays, mantas, turtles, giants), how hard it's
-- turning, and for a ray how settled it is and how long it has lain there
local function frameOf(creature: Creature, t: number): (CFrame, number, number, number)
	local kind = creature.kind
	if kind == "ray" then
		return rayFrame(creature, t)
	elseif kind == "giant" then
		local at = giantAt(creature, t)
		local from, to = creature.from :: Vector3, creature.to :: Vector3
		return CFrame.lookAt(at, at + (to - from)), 0, 0, -1
	end
	local frame, rate = cruiseFrame(creature, t)
	return frame, rate, 0, -1
end

----------------------------------------------------------------------------------
-- The humpbacks are edible (Config/Ambient `whale.feed`): our fish can't swim through
-- one, and BITE finds one at our mouth (HuntController.findWhale; CompanionService
-- checks the bite)

-- Sets our own fish back onto a whale's skin, keeping only its speed along it
local function solidWhale(creature: Creature, frame: CFrame)
	local mine = SwimController.root()
	if mine == nil or SwimController.isHeld() then
		return
	end
	local gap, out = Giants.gap(frame.Position, frame.LookVector, creature.size, mine.Position)
	local inside = mine.Size.X * 0.4 - gap
	if inside <= 0 then
		return
	end
	local velocity = SwimController.velocity
	local into = velocity:Dot(out)
	if into < 0 then
		SwimController.velocity = velocity - out * into
	end
	mine.CFrame += out * inside
end

-- The lane of a whale in view whose skin is within `reach` of `mouth`, if any
local function whaleAt(mouth: Vector3, reach: number): number?
	local now = Timing.clock()
	for lane, creature in giants do
		if creature.giant == "whale" and creature.fade < 0.5 then
			local at = giantAt(creature, now)
			local heading = ((creature.to :: Vector3) - (creature.from :: Vector3)).Unit
			if (Giants.gap(at, heading, creature.size, mouth)) <= reach then
				return lane
			end
		end
	end
	return nil
end

local function centerOf(creature: Creature, t: number): Vector3
	local kind = creature.kind
	if kind == "jelly" then
		return jellyAt(creature, t)
	elseif kind == "cloud" then
		return creature.home
	elseif kind == "giant" then
		return (giantAt(creature, t))
	end
	return (frameOf(creature, t)).Position
end

-- What a turtle, manta or ray near the camera does with our fish this frame (Config/
-- Companions): a turtle we've stayed beside long enough joins us, a manta's wake
-- carries us, and a ray resting on the sand bursts away from a fish skimming over it
local fishVelocity = Vector3.zero
local inWake = false -- in a manta's wake this frame
local wakeSince: number? = nil -- since when, unbroken
local draftUntil = 0 -- its current carries us until then (the clock)
local sawTurtle = false
local function interact(creature: Creature, frame: CFrame, settled: number, fishAt: Vector3, now: number)
	local kind = creature.kind
	local offset = fishAt - frame.Position
	if kind == "turtle" then
		local tune = Companions.turtle
		if escortKey or offset.Magnitude > creature.size * tune.reach then
			return
		end
		sawTurtle = true
		if turtleKey ~= creature.key then
			turtleKey, turtleSince = creature.key, now
		elseif now - turtleSince >= tune.join and now >= turtleAgain then
			turtleAgain = now + tune.lasts + tune.cooldown
			escortKey = creature.key
			ClientState.request("Companion", "turtle")
		end
	elseif kind == "manta" then
		local tune = Companions.manta
		local look = frame.LookVector
		local along = offset:Dot(look)
		local span = creature.size
		if
			along < 0
			and -along < span * tune.behind
			and (offset - look * along).Magnitude < span * tune.width
			and fishVelocity.Magnitude > 2
			and fishVelocity.Unit:Dot(look) > tune.align
		then
			inWake = true
		end
	elseif kind == "ray" then
		local tune = Companions.ray
		if settled < 0.85 or now < rayAgain or flushed[creature.key] then
			return
		end
		local flat = Vector2.new(offset.X, offset.Z).Magnitude
		if flat <= creature.size * tune.reach and offset.Y > -2 and offset.Y <= tune.over then
			rayAgain = now + tune.cooldown
			flushed[creature.key] = now
			local puff = creature.puff
			if puff then
				puff:Emit(40)
			end
			ClientState.request("Companion", "ray")
		end
	end
end

type Posing = { creature: Creature, away: number, frame: CFrame, rate: number, settled: number, since: number }
local posing: { Posing } = {}

local function step(dt: number)
	local now = Timing.clock()
	frameCount += 1
	local camera = workspace.CurrentCamera.CFrame.Position
	local scale = SchoolController.detail()
	-- Near a world boss everything fades away (and the giants hide while one is up)
	local boss = BossController.position()
	local bossUp = boss ~= nil
	local nearBoss = boss ~= nil and (boss - camera).Magnitude < Ambient.bossClear
	bossFade = math.clamp(bossFade + (if nearBoss then dt else -dt) / 1.5, 0, 1)
	if now >= nextRefresh then
		nextRefresh = now + REFRESH
		refreshSquares(camera, scale)
		refreshGiants(camera, now, bossUp)
	end
	if now >= nextScan then
		nextScan = now + Ambient.cloudScan
		refreshClouds(camera, scale)
		-- (a readout on the folder for play tests: how many of each are built, and what
		-- posing them cost a frame over the last second)
		for id in KINDS do
			folder:SetAttribute(id, counts[id] or 0)
		end
		if poseFrames > 0 then
			folder:SetAttribute("PoseMs", math.floor(poseTime / poseFrames * 1e5) / 100)
			folder:SetAttribute("Joints", math.floor(jointsPosed / poseFrames + 0.5))
		end
		poseTime, poseFrames, jointsPosed = 0, 0, 0
	end
	local started = os.clock()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local fishAt = if root and root:IsA("BasePart") then root.Position else nil
	fishVelocity = if root and root:IsA("BasePart") then root.AssemblyLinearVelocity else Vector3.zero
	inWake = false
	sawTurtle = false
	-- The turtle swimming with us: until the server's `Escort` runs out
	local escort = if character then character:GetAttribute("Escort") else nil
	if escortKey and not (typeof(escort) == "number" and escort > now) then
		escortKey = nil
	end
	table.clear(moveParts)
	table.clear(moveFrames)
	table.clear(posing)
	for creature in creatures do
		local kind = KINDS[creature.kind]
		local isGiant = creature.kind == "giant"
		local range = if isGiant then kind.range else kind.range * scale
		local frame, rate, settled, since = CFrame.identity, 0, 0, -1
		local at: Vector3
		if creature.body then
			frame, rate, settled, since = frameOf(creature, now)
			at = frame.Position
		else
			at = centerOf(creature, now)
		end
		local away = (at - camera).Magnitude
		local fade = 0
		-- A flushed ray bursts up off the sand and away, then stays gone a while
		local flushedAt = if creature.kind == "ray" then flushed[creature.key] else nil
		if flushedAt then
			local elapsed = now - flushedAt
			if elapsed >= Companions.ray.hidden + RAY_BURST then
				flushed[creature.key] = nil
			elseif elapsed >= Companions.ray.hidden then
				fade = 1 - (elapsed - Companions.ray.hidden) / RAY_BURST -- (back, fading in)
			elseif elapsed < RAY_BURST then
				local u = elapsed / RAY_BURST
				frame = (frame + frame.LookVector * (u * u * 22) + Vector3.new(0, u * 5, 0))
					* CFrame.Angles(-u * 0.5, 0, 0)
				at = frame.Position
				settled, since = 0, -1
				fade = u
			else
				fade = 1
			end
		end
		-- The turtle swimming with us is drawn at our side (CompanionController), not here
		if creature.kind == "turtle" and creature.key == escortKey then
			fade = 1
		end
		if fishAt and creature.body and away < INTERACT and fade < 1 then
			interact(creature, frame, settled, fishAt, now)
		end
		if away > range * (1 - FADE_SHARE) then
			fade = (away - range * (1 - FADE_SHARE)) / (range * FADE_SHARE)
		end
		if isGiant then
			-- in and out at the ends of its line; a manta never close (a humpback stays
			-- in view up close: it's edible, Config/Ambient `whale.feed`)
			if creature.giant ~= "whale" then
				local near = Ambient.giants.near
				fade = math.max(fade, 1 - (away - near) / 50)
			end
			local _, u = giantAt(creature, now)
			fade = math.max(fade, 1 - math.min(u, 1 - u) / 0.08)
		end
		if creature.giant == "whale" and fade < 0.5 then
			solidWhale(creature, frame)
		end
		fade = math.max(fade, bossFade)
		fade = math.clamp(math.floor(fade * 10 + 0.5) / 10, 0, 1)
		if fade ~= creature.fade then
			setFade(creature, fade)
		end
		if fade >= 1 then
			continue
		end
		local id = creature.kind
		if id == "jelly" then
			poseJelly(creature, now, at, away)
		elseif id == "cloud" then
			poseCloud(creature, now, fishAt)
		elseif creature.body then
			table.insert(posing, {
				creature = creature,
				away = away,
				frame = frame,
				rate = rate,
				settled = settled,
				since = since,
			})
		end
	end
	lastCloudAt = now
	if not sawTurtle then
		turtleKey = nil
	end
	-- A manta's draft (SwimController takes it like a podmate's slipstream): ridden
	-- `ride` s, its current carries us `carry` s more, renewed while we stay in it.
	-- `Draft` on our own character (this client's copy only) is for play tests.
	local manta = Companions.manta
	if inWake then
		wakeSince = wakeSince or now
		if now - (wakeSince :: number) >= manta.ride then
			if now >= draftUntil then
				HudController.toast("A manta's current carries you · faster", "good")
			end
			draftUntil = now + manta.carry
		end
	else
		wakeSince = nil
	end
	local draft = now < draftUntil and fishAt ~= nil
	if SwimController.draft ~= draft then
		SwimController.draft = draft
		if character then
			character:SetAttribute("Draft", if draft then true else nil)
		end
	end
	-- The bodies: joints nearest first within the budget, every one moved
	table.sort(posing, function(a, b)
		return a.away < b.away
	end)
	local budget = Ambient.jointBudget
	for _, entry in posing do
		local creature = entry.creature
		local body = creature.body :: AmbientBody.Body
		local kind = KINDS[creature.kind]
		local animate = (kind.animate or 120) * scale
		local due = entry.away <= animate
			or (entry.away <= animate * 2 and (frameCount + creature.key) % 2 == 0)
		if due and budget >= body.joints then
			budget -= body.joints
			local motion = creature.motion
			motion.t = now
			motion.period = creature.beat
			-- Banking into its turn (a turn rate of ~0.5 rad/s is a hard one)
			motion.turn = math.clamp(entry.rate / 0.5, -1, 1)
			motion.bank = math.clamp(entry.rate * 0.7, -0.45, 0.45)
			motion.rest = entry.settled
			motion.settled = entry.since
			AmbientBody.pose(body, motion)
			creature.posedAt = now
		end
		-- A puff of sand as a ray beds down or lifts off (near the camera)
		local puff = creature.puff
		if puff then
			local was = creature.settled
			if
				entry.away < Ambient.settle.puffRange
				and (
					(was < 0.85 and entry.settled >= 0.85)
					or (was > 0.15 and entry.settled <= 0.15 and was > entry.settled)
				)
			then
				puff:Emit(14)
			end
			creature.settled = entry.settled
		end
		table.insert(moveParts, body.root)
		table.insert(moveFrames, AmbientBody.frame(body, entry.frame))
	end
	jointsPosed += Ambient.jointBudget - budget
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	poseTime += os.clock() - started
	poseFrames += 1
end

function AmbientLifeController.start()
	folder = Instance.new("Folder")
	folder.Name = "AmbientLife"
	folder.Parent = workspace
	HuntController.findWhale = whaleAt
	RunService.RenderStepped:Connect(step)
end

-- How many ambient creatures are built now, by kind (the admin panel's readout, tests)
function AmbientLifeController.counts(): { [string]: number }
	return table.clone(counts)
end

return AmbientLifeController
