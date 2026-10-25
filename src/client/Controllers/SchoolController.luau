--!strict
-- Draws the NPC prey and eats them. Every fish follows its shared path
-- (Shared/Schools.luau), so this client moves its own copies each frame with
-- BulkMoveTo and nothing is sent over the network but eats.
--
-- Eating feels instant: when a small-enough fish is in reach of our mouth it's
-- sucked in on this client straight away, and the eat goes to the server in a
-- small batch. If the server doesn't confirm it within a moment, the fish comes
-- back. Fish other players ate vanish with a puff and return when they respawn.
--
-- Rare fish (Config/Catch; the server says which, `PreyRarity`) wear their rarity:
-- bright silver flashing like a mirror, gold foil, a teal glow, clear crystal or a
-- shifting rainbow, with sparkles and a small light so they can be spotted from a
-- distance. A tide's own schools (the Sardine Run's bait balls) are only drawn while
-- it's up.
--
-- Only the schools near the camera are built (owner, 2026-10-18: "We still need so
-- much more fish too", which took the sea from ~1,300 fish to ~4,100): a school is
-- built when it comes within its reach (Schools `reach`), nearest first within a
-- small time budget a frame, and let go well past it; until then only what the
-- server said about its fish is kept (eaten until, rarity). Each fish is drawn
-- within its own range (Schools `range`: bigger fish further, the back of a big
-- school thinning first) and fades out over the last FADE_SHARE of it
-- (LocalTransparencyModifier). A client whose frames run slow draws everything a
-- little nearer (`detail`, eased; SchoolController.detail for the ambient life).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Schools = require(ReplicatedStorage.Shared.Schools)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Size = require(ReplicatedStorage.Shared.Size)
local SwimWave = require(ReplicatedStorage.Shared.SwimWave)
local Tides = require(ReplicatedStorage.Shared.Tides)
local Timing = require(ReplicatedStorage.Shared.Timing)
local ClientState = require(script.Parent.Parent.ClientState)
local SwimController = require(script.Parent.SwimController)

local SchoolController = {
	-- (preyId, mass, position, rarity?) — we ate a prey fish (HUD pops a number)
	ate = Signal.new(),
	-- (preyId) — a prey fish too big to swallow is at our mouth (at most once a second)
	tooBig = Signal.new(),
}

local lastTooBig = 0

-- Bodies further than this hold their spine still (they still swim their paths): the
-- wave can't be seen that far off, and there are many more small fish near the hub
-- now (owner, 2026-10-10: "far too scarce"). Small fish stop sooner (Schools `wave`).
local WAVE_DISTANCE = 160
-- Within WAVE_NEAR a spine's wave is set every frame, to WAVE_HALF every other and
-- past it every third (the bones hold their pose in between; the wave runs on the
-- clock), so the fuller sea (Config/Prey `fill`, 2026-10-20: ~8,500 fish, up to ~300
-- waving at once in a swarm) costs a fraction (PC 2026-10-25: SwimWave.applyBones
-- 38.6 ms/s in the Kelp Cathedral's nave at every other frame past 60)
local WAVE_NEAR = 30
local WAVE_HALF = 60
-- A drawn fish is moved every few frames when it's far enough off for how fast it
-- moves: its step between moves never turns more than MOVE_STEP radians as seen
-- from the camera (~3.2 px on a 1080p screen; whole frames round it down, so most
-- steps are ~2 px), never past every MOVE_MAX frames,
-- and every frame within MOVE_NEAR of the camera or our mouth, while it's rare,
-- chased, sucked in, growing back or shrinking away (PC 2026-10-25: 155 ms/s in the
-- nave, BulkMoveTo 55.7 of it, every drawn fish moved every frame; most are small
-- slow fish 60-220 studs off). How fast is its `pace`, measured as it's drawn: how
-- far it went and a quarter of its length times the turn of its heading since it was
-- last moved, a peak that settles over 1 / PACE_SETTLE s (PC 2026-10-26: by its
-- `speed` a Butterflyfish was held 3 frames, but its sway and turns carry it ~19
-- studs/s at `speed` 5, so it stepped 4-5 px in the Reef); a gap longer than PACE_GAP
-- (it was out of range or hidden) isn't measured. Tuned with `TEST=jump_test
-- run_density.sh` (PC 2026-10-27: at 0.003, half the turn's arc and a 0.5 s settle,
-- held fish jumped ~1 px and moved nearly every frame, SchoolController +19-33%)
local MOVE_STEP = 0.0042
local MOVE_MAX = 4
local MOVE_NEAR = 40
local PACE_SETTLE = 4
local PACE_TURN = 0.25
local PACE_GAP = 0.25
-- A fish that respawns swims back in from behind its school as it grows, over
-- RETURN_SECONDS from RETURN_LENGTHS of its own body lengths back (owner,
-- 2026-10-20: respawns are ~⅓ as long now, so they're seen much more)
local RETURN_SECONDS = 1.1
local RETURN_LENGTHS = 6
local RETURN_EDIBLE = 0.8
-- A fish fades out over the last share of its draw range (Schools `range`)
local FADE_SHARE = 0.2
-- A built fish past its draw range is looked at again only every CULL_EVERY frames
-- (most built fish are: Kelp 472 built, 119 drawn, PC 2026-10-20; their path maths
-- was spent every frame for nothing; 587 built, ~280 drawn in the nave, 2026-10-25)
local CULL_EVERY = 6
-- A school is let go this far past its reach (so one on the edge isn't rebuilt
-- every few frames)
local RELEASE_SLACK = 90
local BUILD_BUDGET = 0.003 -- seconds a frame spent building newly near schools
-- How far the client draws (×): eased toward DETAIL_MIN while frames take longer
-- than SLOW_FRAME, back to 1 under FAST_FRAME
local DETAIL_MIN = 0.6 -- (0.7 until 2026-10-20: the fuller sea held Kelp, Reef and Trench at it)
local SLOW_FRAME = 1 / 38
local FAST_FRAME = 1 / 52
-- Static GLB prey meshes came in facing +Z (owner, 2026-10-07: "swimming backwards");
-- they're turned round when drawn. Rigged FBX bodies face -Z already.
local MESH_FLIP = CFrame.Angles(0, math.pi, 0)
local SUCK_SECONDS = 0.14
local CONFIRM_SECONDS = 1.2
local SEND_INTERVAL = 0.06

type Visual = {
	body: BasePart,
	tail: BasePart?, -- the part body's tail fin (a mesh body has none)
	model: Model?, -- a rigged body (its primary MeshPart is `body`); its bones swim
	bones: { [string]: Bone },
	spine: { string },
	unitScale: number, -- the rigged model's scale at full size
	phase: number, -- the swim wave
	flip: boolean, -- a static mesh that came in facing +Z
	bodySize: Vector3,
	tailSize: Vector3,
	hidden: boolean,
	backAt: number, -- clock when it shows again (0 = shown)
	pendingUntil: number, -- our unconfirmed eat
	suckFrom: CFrame?, -- the suction animation's start
	suckStart: number,
	fadeIn: number, -- 0..1 after respawning
	-- A chase (AggroService): this fish darts at a player and back
	chase: { target: Player, startAt: number, endsAt: number, glow: Highlight }?,
	-- Its rarity's look while it swims rare (Config/Catch): what was changed, to put
	-- back, and what was added
	look: Look?,
	parts: { BasePart }, -- every part of its body (fades and hiding)
	cull: number, -- its LocalTransparencyModifier: 0 drawn .. 1 out of range
	-- Part-built extras riding on it (SHAPES on a part body, GLOWS on any: makeExtras)
	extras: { Extra }?,
	at: Vector3?, -- where it was last drawn
	facing: Vector3?, -- and which way it faced
	stepAt: number, -- clock when it was last moved (its wave runs on the clock)
	pace: number, -- studs a second it moves on screen (MOVE_STEP), its `speed` at first
	swimRate: number, -- radians a second its spine wave runs
	holdUntil: number, -- frameCount until which it's held where it is
	far: number, -- how far off it was last drawn
	lit: Color3?, -- its glow light's colour while it has one shown (GLOW_LIGHTS)
	waveFrame: number, -- frameCount its wave was last set
}

-- (its part is made the first time it shows: a Lanternfish far off never builds spots)
type Extra = {
	part: BasePart?,
	color: Color3,
	size: Vector3,
	offset: CFrame,
	neon: boolean,
	near: number,
	light: boolean,
	shown: boolean,
}

type Look = {
	rarity: string,
	held: { [BasePart]: SurfaceAppearance },
	saved: {
		[BasePart]: {
			color: Color3,
			material: Enum.Material,
			reflectance: number,
			transparency: number,
			texture: string?,
		},
	},
	extras: { Instance },
	light: PointLight?,
	sparkle: ParticleEmitter?,
	glint: BillboardGui?, -- a star that stays a few pixels wide however far off
	glintScale: UIScale?,
}

-- Each prey's body set up once from its import, cloned for each of its fish
type Proto = { model: Model?, mesh: MeshPart?, unitLength: number, extents: Vector3, flip: boolean }

local visuals: { [number]: Visual } = {} -- prey index → its body, while its school is built
local built: { [number]: boolean } = {} -- school index → its fish are built (or being built)
local nextFish: { [number]: number } = {} -- school index → its next fish to build, while part built
local backAts: { [number]: number } = {} -- prey index → clock it's back after being eaten
local protos: { [string]: Proto } = {}
local folder: Folder? = nil
local detail = 1 -- how far this client draws (×), from its frame time
local smoothDt = 1 / 60
local frameCount = 0
local wanted: { { index: number, away: number } } = {}
local drawList: { number } = {}
-- (a readout on the Prey folder for play tests: Detail, Built, Drawn, once a second)
local builtCount = 0
local drawnCount = 0
local biggestRadius = 0 -- the biggest prey's radius (`eatLook`)
local readoutAt = 0
local parts: { BasePart } = {}
local frames: { CFrame } = {}
local batch: { { number } } = {}
local lastSend = 0
local aggro = Config.Tuning.aggro
local chaseWarning: TextLabel? = nil
local chaseWarningUntil = 0
local CatchConfig = Config.Catch
local rarities: { [number]: string } = {} -- prey index → rarity id (rare fish only)
local prisms: { [number]: Visual } = {} -- fish wearing the Prism look (their colour cycles)
-- Fish wearing the Silver look, which must read apart from the plain silvery minnows
-- and sardines by its body, not only its sparkles (owner, 2026-10-18; PC 2026-10-19,
-- SV1: on Foil, a metal that shows the dark water, its body read like a plain
-- sardine's). A whiter cool polished silver (SmoothPlastic, lit, with a little sheen
-- of the water), lit over its back by a small cool light of its own: a light inside
-- the body lights none of its skin, and a wide one lit the plain fish round it too.
-- Then a mirror flash: every 1.2-2 s, staggered fish by fish, its flank catches the
-- light in a quick bright pulse, like a real silver fish turning in the sun. The
-- pulse is Neon white at its peak beyond SILVER_NEAR; nearer the camera it is colour
-- and light only. Its glint swells with it.
local silvers: { [number]: Visual } = {}
local silverPulse: { [number]: number } = {} -- its flash as last drawn (0 at rest)
local SILVER_BASE = Color3.fromRGB(222, 232, 248)
local SILVER_FLASH = Color3.fromRGB(242, 249, 255)
local SILVER_LIGHT = Color3.fromRGB(214, 232, 255)
local SILVER_SHEEN = 0.15 -- its reflectance at rest
local SILVER_GLOW = 1.5 -- its own light's brightness at rest
local SILVER_GLOW_FLASH = 6 -- and at a flash's peak
local SILVER_PERIOD = 1.2 -- seconds between flashes: SILVER_PERIOD + up to SILVER_SPREAD
local SILVER_SPREAD = 0.8
local SILVER_WIDTH = 0.11 -- the flash's half-width, a share of its period
local SILVER_NEON = 0.55 -- the body is Neon above this (the peak, about 0.15 s)
local SILVER_NEAR = 24 -- studs from the camera: nearer, no Neon
-- A tide school near the camera when its tide ends shrinks away over TIDE_FADE
-- seconds instead of popping out in front of you (playtest 2026-10-10); far off,
-- out in the haze, it just goes
local tideFade: { [number]: number } = {} -- school index → clock its fade began
local TIDE_FADE = 1.5
local TIDE_FADE_RANGE = 160
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
-- A rare fish's glint (playtest 2026-10-10: a Golden Minnow was a 2-3 pixel speck at
-- 60 studs and gone by 100): a small four-point star drawn at a fixed pixel size, so
-- it reads out to GLINT_RANGE; it fades in past GLINT_NEAR, where the fish itself reads
local GLINT_RANGE = 240
local GLINT_NEAR = 18
local GLINT_FADE = 30
local GLINT_PIXELS: { [string]: number } =
	{ Silver = 13, Golden = 15, Glowing = 17, Crystal = 19, Prism = 21 }
local RARE_RANGE = GLINT_RANGE + 15 -- a rare fish is drawn at least this far, for its glint
-- Its light reaches further for the rarer ones (×length, plus studs)
local LIGHT_BONUS: { [string]: number } = { Silver = 1, Golden = 2, Glowing = 5, Crystal = 7, Prism = 9 }
local glints: { [number]: Look } = {} -- fish index → its look, while it has a glint
local glintShown: { [number]: boolean } = {}
local glintSeen: { [number]: boolean } = {}
-- The star is drawn on top of the water's haze (playtest 2026-10-11: depth-tested in
-- the world, the haze fogged it out past ~100 studs, though it was still on), so rock
-- has to hide it another way: a ray from the camera to the fish, a few a frame, shared
-- round the stars in reach. It eases out behind rock and back in, never pops.
local GLINT_CHECKS = 6
local glintAt: { [number]: Vector3 } = {} -- stars in reach this frame → where their fish is
local glintBlocked: { [number]: boolean } = {}
local glintVis: { [number]: number } = {}
local glintQueue: { number } = {}
local glintCursor = 0
local rockParams = RaycastParams.new()
rockParams.FilterType = Enum.RaycastFilterType.Include
rockParams.RespectCanCollide = true -- the solid world: Terrain, rock, wrecks, hard coral
rockParams.IgnoreWater = true
local rockWorld: Instance? = nil

-- How each rarity looks on a fish: its material and colour (the texture is held
-- aside), its sparkle and its light
local LOOKS: {
	[string]: {
		material: Enum.Material,
		color: Color3,
		reflectance: number,
		transparency: number,
		light: number,
	},
} =
	{
		Silver = {
			material = Enum.Material.SmoothPlastic,
			color = SILVER_BASE,
			reflectance = SILVER_SHEEN,
			transparency = 0,
			light = SILVER_GLOW,
		},
		Golden = {
			material = Enum.Material.Foil,
			color = Color3.fromRGB(255, 196, 64),
			reflectance = 0.1,
			transparency = 0,
			light = 1.2,
		},
		Glowing = {
			material = Enum.Material.Neon,
			color = Color3.fromRGB(20, 170, 160),
			reflectance = 0,
			transparency = 0,
			light = 2.2,
		},
		Crystal = {
			material = Enum.Material.Glass,
			color = Color3.fromRGB(150, 210, 255),
			reflectance = 0.3,
			transparency = 0.25,
			light = 1.6,
		},
		Prism = {
			material = Enum.Material.SmoothPlastic,
			color = Color3.fromRGB(255, 120, 230),
			reflectance = 0.15,
			transparency = 0,
			light = 2.2,
		},
	}

local function makePart(parent: Instance, color: Color3, shape: "Ellipsoid" | "Fin"): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.Parent = parent
	if shape == "Fin" then
		part.Reflectance = 0.05
	end
	return part
end

-- Part-built extras on some prey, each an ellipsoid riding on the fish (moved with its
-- body). SHAPES give the second to fourth prey batches (Config/Prey, 2026-10-18/19) a
-- look of their own while their models aren't imported: a belly, bands, fins on the
-- part body. GLOWS are
-- the glowing bits every body wears, imported or not: the Lanternfish's light spots and
-- the Ghost Shrimp's teal tips (Neon parts; never a see-through body, which sorts
-- badly). `at` is a place on the body in its half-extents (x across, y up, z along:
-- -1 the snout, 1 the tail), and `hug` pulls it in to the body's egg-shaped outline
-- toward the ends (a spot on the flank); `size` is × the body's extents, or `ball` ×
-- its length. A glow shows only within its `near` studs of the camera (past that it's
-- a speck), and the GLOW_LIGHTS nearest glowing fish with `light` carry a faint light.
type ExtraSpec = { at: Vector3, size: Vector3?, ball: number?, color: Color3, hug: boolean? }
type Glow = { near: number, color: Color3, light: boolean, spots: { ExtraSpec } }

local LANTERN = Color3.fromRGB(90, 236, 255)
local SHRIMP_TIP = Color3.fromRGB(60, 240, 214)
local CHARCOAL = Color3.fromRGB(52, 44, 44)
local DARK_BAND = Color3.fromRGB(36, 34, 48) -- the Butterflyfish's eye band and eyespot
local BLOTCH = Color3.fromRGB(214, 226, 234) -- the Coelacanth's pale blotches
local EMBER = Color3.fromRGB(250, 120, 40) -- the Vent Eelpout's specks
local OAR_RED = Color3.fromRGB(200, 32, 38) -- the Oarfish's fins (a true red, as its model)
local VIPER_GLOW = Color3.fromRGB(96, 232, 244) -- the Viperfish's light spots
local HATCHET_GLOW = Color3.fromRGB(84, 242, 232) -- the Hatchetfish's keel dots
local SPOT_WHITE = Color3.fromRGB(226, 236, 232) -- the Opaleye's two back spots
local TANG_YELLOW = Color3.fromRGB(250, 212, 28)
local EMBER_EDGE = Color3.fromRGB(232, 110, 36) -- the Rattail's fin edges (orange, never pink)
local GLOW_LIGHTS = 3
-- A light stays on its fish while that fish is still among the nearest, and another
-- takes it only when GLOW_KEEP studs nearer (PC 2026-10-27: following a Lanternfish
-- school the three lights moved to another fish 12-37 times in 7.2 s as the nearest
-- swapped places, and a held fish offered its distance from its last move)
local GLOW_KEEP = 8
local GLOW_LIGHT_RANGE = 7
local GLOW_LIGHT_BRIGHTNESS = 0.7

local lanternSpots: { ExtraSpec } = {}
-- (along the mid-flank row painted on the imported model, measured on a render)
for _, z in { -0.34, -0.04, 0.26, 0.52 } do
	for _, side in { -1, 1 } do
		table.insert(
			lanternSpots,
			{ at = Vector3.new(side * 0.85, 0.02, z), ball = 0.05, color = LANTERN, hug = true }
		)
	end
end

-- The fourth batch's glowing rows, measured on the imported models (the cyan dots of
-- their colour maps, found on the mesh through its UVs, and checked on a render with
-- these balls on): the Viperfish's two rows along its lower flank, the front two
-- thirds of them (behind that the spine wave swings the body off the spots), and the
-- Hatchetfish's row along its keel's edge, chin to the keel's point. Both sides each.
-- On the part-built stand-in they sit inside the body (its SHAPES paint the rows).
local viperSpots: { ExtraSpec } = {}
for _, spot in
	{
		{ 0.45, -0.6, -0.42 },
		{ 0.44, -0.565, -0.25 },
		{ 0.4, -0.55, -0.09 },
		{ 0.36, -0.52, 0.07 },
		{ 0.29, -0.495, 0.21 }, -- the belly row
		{ 0.59, -0.374, -0.43 },
		{ 0.59, -0.355, -0.26 },
		{ 0.537, -0.364, -0.105 },
		{ 0.49, -0.36, 0.05 },
		{ 0.43, -0.34, 0.19 }, -- the flank row
	}
do
	for _, side in { -1, 1 } do
		table.insert(
			viperSpots,
			{ at = Vector3.new(side * spot[1], spot[2], spot[3]), ball = 0.03, color = VIPER_GLOW }
		)
	end
end
local hatchetSpots: { ExtraSpec } = {}
for _, spot in
	{
		{ 0.176, -0.297, -0.54 },
		{ 0.174, -0.479, -0.38 },
		{ 0.14, -0.633, -0.22 },
		{ 0.143, -0.751, -0.06 },
		{ 0.127, -0.878, 0.09 },
	}
do
	for _, side in { -1, 1 } do
		table.insert(
			hatchetSpots,
			{ at = Vector3.new(side * spot[1], spot[2], spot[3]), ball = 0.04, color = HATCHET_GLOW }
		)
	end
end

local GLOWS: { [string]: Glow } = {
	Lanternfish = { near = 60, color = LANTERN, light = true, spots = lanternSpots },
	Viperfish = { near = 60, color = VIPER_GLOW, light = true, spots = viperSpots },
	Hatchetfish = { near = 45, color = HATCHET_GLOW, light = false, spots = hatchetSpots },
	GhostShrimp = {
		near = 45,
		color = SHRIMP_TIP,
		light = false,
		spots = {
			-- (where the imported model's tips are, measured on a render: its tail fan
			-- curls down, its antennae arch up over its back)
			{ at = Vector3.new(0, -0.78, 0.86), ball = 0.08, color = SHRIMP_TIP }, -- the tail fan
			{ at = Vector3.new(0.9, 0.93, -0.09), ball = 0.05, color = SHRIMP_TIP }, -- the antennae
			{ at = Vector3.new(-0.9, 0.93, -0.09), ball = 0.05, color = SHRIMP_TIP },
			{ at = Vector3.new(0.25, -0.88, -0.38), ball = 0.045, color = SHRIMP_TIP }, -- leg tips
			{ at = Vector3.new(-0.25, -0.88, -0.16), ball = 0.045, color = SHRIMP_TIP },
			{ at = Vector3.new(0.25, -0.88, 0.06), ball = 0.045, color = SHRIMP_TIP },
		},
	},
}

local SHAPES: { [string]: { ExtraSpec } } = {
	Garibaldi = {
		{
			at = Vector3.new(0, 0.85, 0.1),
			size = Vector3.new(0.12, 0.5, 0.6),
			color = Color3.fromRGB(214, 76, 10),
		},
	},
	WreckCod = {
		{
			at = Vector3.new(0, -0.35, 0),
			size = Vector3.new(0.85, 0.6, 0.85),
			color = Color3.fromRGB(172, 178, 176),
		},
		{
			at = Vector3.new(0, 0.85, 0.15),
			size = Vector3.new(0.12, 0.4, 0.7),
			color = Color3.fromRGB(84, 78, 44),
		},
	},
	Parrotfish = {
		{
			at = Vector3.new(0, -0.35, 0),
			size = Vector3.new(0.85, 0.6, 0.85),
			color = Color3.fromRGB(96, 196, 176),
		},
		{
			at = Vector3.new(0, -0.1, -0.95),
			size = Vector3.new(0.45, 0.35, 0.18),
			color = Color3.fromRGB(200, 226, 240),
		},
	},
	YellowfinTuna = {
		{
			at = Vector3.new(0, -0.3, 0),
			size = Vector3.new(0.9, 0.65, 0.9),
			color = Color3.fromRGB(196, 206, 220),
		},
		{
			at = Vector3.new(0, 1, 0.1),
			size = Vector3.new(0.1, 0.7, 0.25),
			color = Color3.fromRGB(250, 204, 40),
		},
		{
			at = Vector3.new(0, -1, 0.15),
			size = Vector3.new(0.1, 0.7, 0.25),
			color = Color3.fromRGB(250, 204, 40),
		},
	},
	MahiMahi = {
		{
			at = Vector3.new(0, -0.3, 0),
			size = Vector3.new(0.85, 0.65, 0.9),
			color = Color3.fromRGB(222, 196, 52),
		},
		{
			at = Vector3.new(0, 0.8, 0.05),
			size = Vector3.new(0.1, 0.55, 0.95),
			color = Color3.fromRGB(30, 90, 120),
		},
	},
	Lionfish = {
		{ at = Vector3.new(0, 0, -0.25), size = Vector3.new(1.04, 1.04, 0.12), color = CHARCOAL, hug = true },
		{ at = Vector3.new(0, 0, 0.25), size = Vector3.new(1.04, 1.04, 0.12), color = CHARCOAL, hug = true },
		{
			at = Vector3.new(0, 1.2, -0.05),
			size = Vector3.new(0.08, 0.9, 0.6),
			color = Color3.fromRGB(150, 60, 30),
		},
		{
			at = Vector3.new(0.75, -0.1, 0.05),
			size = Vector3.new(0.5, 0.9, 0.5),
			color = Color3.fromRGB(120, 56, 34),
		},
		{
			at = Vector3.new(-0.75, -0.1, 0.05),
			size = Vector3.new(0.5, 0.9, 0.5),
			color = Color3.fromRGB(120, 56, 34),
		},
	},
	GhostShrimp = {
		{
			at = Vector3.new(0, 0.35, -1.25),
			size = Vector3.new(0.08, 0.3, 0.8),
			color = Color3.fromRGB(170, 196, 214),
		},
	},
	Lanternfish = {
		{
			at = Vector3.new(0, -0.35, 0),
			size = Vector3.new(0.85, 0.6, 0.85),
			color = Color3.fromRGB(58, 80, 122),
		},
	},
	-- The third batch (Config/Prey, 2026-10-19)
	Butterflyfish = {
		-- the dark band through the eye, the eyespot near the tail, the pointed snout
		{
			at = Vector3.new(0, 0.05, -0.5),
			size = Vector3.new(1.04, 1.04, 0.14),
			color = DARK_BAND,
			hug = true,
		},
		{ at = Vector3.new(0.8, 0.45, 0.45), ball = 0.07, color = DARK_BAND, hug = true },
		{ at = Vector3.new(-0.8, 0.45, 0.45), ball = 0.07, color = DARK_BAND, hug = true },
		{
			at = Vector3.new(0, -0.1, -1),
			size = Vector3.new(0.18, 0.16, 0.25),
			color = Color3.fromRGB(240, 196, 30),
		},
		{
			at = Vector3.new(0, 0.85, 0.2),
			size = Vector3.new(0.1, 0.45, 0.7),
			color = Color3.fromRGB(226, 172, 20),
		},
	},
	Triggerfish = {
		-- the white-spotted belly, the yellow net on the back, the orange beak
		{
			at = Vector3.new(0, -0.4, 0.05),
			size = Vector3.new(0.85, 0.5, 0.8),
			color = Color3.fromRGB(226, 230, 236),
		},
		{
			at = Vector3.new(0, 0.5, 0.05),
			size = Vector3.new(0.75, 0.35, 0.5),
			color = Color3.fromRGB(214, 186, 40),
		},
		{
			at = Vector3.new(0, -0.05, -0.98),
			size = Vector3.new(0.3, 0.25, 0.14),
			color = Color3.fromRGB(244, 120, 24),
		},
		{
			at = Vector3.new(0, 1, -0.15),
			size = Vector3.new(0.08, 0.35, 0.2),
			color = Color3.fromRGB(28, 36, 72),
		},
	},
	Swordfish = {
		-- the silver belly, the sword and the tall dorsal fin
		{
			at = Vector3.new(0, -0.35, 0),
			size = Vector3.new(0.85, 0.6, 0.9),
			color = Color3.fromRGB(200, 210, 222),
		},
		{
			at = Vector3.new(0, 0, -1.45),
			size = Vector3.new(0.12, 0.12, 0.5),
			color = Color3.fromRGB(96, 88, 150),
		},
		{
			at = Vector3.new(0, 1.5, -0.3),
			size = Vector3.new(0.08, 1.3, 0.25),
			color = Color3.fromRGB(58, 50, 128),
		},
	},
	OceanSunfish = {
		-- the paler belly, one tall fin up and one down, the scalloped back edge
		{
			at = Vector3.new(0, -0.3, 0),
			size = Vector3.new(0.85, 0.6, 0.85),
			color = Color3.fromRGB(176, 188, 196),
		},
		{
			at = Vector3.new(0, 1.35, 0.5),
			size = Vector3.new(0.1, 0.9, 0.25),
			color = Color3.fromRGB(112, 124, 136),
		},
		{
			at = Vector3.new(0, -1.35, 0.5),
			size = Vector3.new(0.1, 0.9, 0.25),
			color = Color3.fromRGB(112, 124, 136),
		},
		{
			at = Vector3.new(0, 0, 0.95),
			size = Vector3.new(0.3, 0.85, 0.12),
			color = Color3.fromRGB(150, 162, 172),
		},
	},
	Coelacanth = {
		-- white blotches, fleshy lobed fins, the second dorsal on its stalk
		{ at = Vector3.new(0.85, 0.25, -0.15), ball = 0.06, color = BLOTCH, hug = true },
		{ at = Vector3.new(-0.85, 0.25, -0.15), ball = 0.06, color = BLOTCH, hug = true },
		{ at = Vector3.new(0.85, -0.1, 0.3), ball = 0.07, color = BLOTCH, hug = true },
		{ at = Vector3.new(-0.85, -0.1, 0.3), ball = 0.07, color = BLOTCH, hug = true },
		{
			at = Vector3.new(0.75, -0.55, -0.3),
			size = Vector3.new(0.3, 0.3, 0.3),
			color = Color3.fromRGB(44, 72, 98),
		},
		{
			at = Vector3.new(-0.75, -0.55, -0.3),
			size = Vector3.new(0.3, 0.3, 0.3),
			color = Color3.fromRGB(44, 72, 98),
		},
		{
			at = Vector3.new(0, 0.95, 0.4),
			size = Vector3.new(0.1, 0.5, 0.3),
			color = Color3.fromRGB(44, 72, 98),
		},
	},
	VentEelpout = {
		-- the big blunt head, the long soft back fin, a few ember-orange specks
		{
			at = Vector3.new(0, 0.05, -0.6),
			size = Vector3.new(1.1, 1.1, 0.5),
			color = Color3.fromRGB(64, 60, 64),
		},
		{
			at = Vector3.new(0, 0.85, 0.3),
			size = Vector3.new(0.08, 0.3, 0.9),
			color = Color3.fromRGB(74, 70, 74),
		},
		{ at = Vector3.new(0.85, 0.2, -0.1), ball = 0.04, color = EMBER, hug = true },
		{ at = Vector3.new(-0.85, 0.2, -0.1), ball = 0.04, color = EMBER, hug = true },
		{ at = Vector3.new(0.85, -0.1, 0.35), ball = 0.04, color = EMBER, hug = true },
		{ at = Vector3.new(-0.85, -0.1, 0.35), ball = 0.04, color = EMBER, hug = true },
	},
	GulperEel = {
		-- the huge pouch mouth, its dark inside, the whip tail
		{
			at = Vector3.new(0, -0.1, -0.7),
			size = Vector3.new(1.4, 1.6, 0.55),
			color = Color3.fromRGB(26, 24, 30),
		},
		{
			at = Vector3.new(0, -0.25, -1),
			size = Vector3.new(0.9, 0.9, 0.1),
			color = Color3.fromRGB(54, 30, 44),
		},
		{
			at = Vector3.new(0, 0, 1.4),
			size = Vector3.new(0.12, 0.15, 0.8),
			color = Color3.fromRGB(22, 22, 28),
		},
	},
	Oarfish = {
		-- the red fin along the whole back, the crest of rays, the streamers below
		{
			at = Vector3.new(0, 1.1, 0.05),
			size = Vector3.new(0.08, 0.5, 0.95),
			color = OAR_RED,
		},
		{
			at = Vector3.new(0, 2, -0.85),
			size = Vector3.new(0.06, 1.8, 0.12),
			color = OAR_RED,
		},
		{
			at = Vector3.new(0, -1.6, -0.55),
			size = Vector3.new(0.05, 0.35, 0.5),
			color = OAR_RED,
		},
	},
	-- The fourth batch (Config/Prey, 2026-10-19)
	Opaleye = {
		-- its two white spots high on the back, the rounded soft dorsal fin
		{ at = Vector3.new(0.55, 0.72, -0.2), ball = 0.045, color = SPOT_WHITE, hug = true },
		{ at = Vector3.new(-0.55, 0.72, -0.2), ball = 0.045, color = SPOT_WHITE, hug = true },
		{ at = Vector3.new(0.55, 0.72, 0.05), ball = 0.045, color = SPOT_WHITE, hug = true },
		{ at = Vector3.new(-0.55, 0.72, 0.05), ball = 0.045, color = SPOT_WHITE, hug = true },
		{
			at = Vector3.new(0, 0.9, 0.15),
			size = Vector3.new(0.1, 0.45, 0.75),
			color = Color3.fromRGB(96, 104, 42),
		},
	},
	KelpBass = {
		-- the paler belly, pale olive blotches, the spiny first dorsal, the big jaw
		{
			at = Vector3.new(0, -0.35, 0),
			size = Vector3.new(0.85, 0.6, 0.85),
			color = Color3.fromRGB(160, 168, 116),
		},
		{ at = Vector3.new(0.85, 0.2, -0.1), ball = 0.09, color = Color3.fromRGB(150, 160, 98), hug = true },
		{ at = Vector3.new(-0.85, 0.2, -0.1), ball = 0.09, color = Color3.fromRGB(150, 160, 98), hug = true },
		{ at = Vector3.new(0.85, 0.15, 0.3), ball = 0.08, color = Color3.fromRGB(150, 160, 98), hug = true },
		{ at = Vector3.new(-0.85, 0.15, 0.3), ball = 0.08, color = Color3.fromRGB(150, 160, 98), hug = true },
		{
			at = Vector3.new(0, 1, -0.15),
			size = Vector3.new(0.08, 0.5, 0.45),
			color = Color3.fromRGB(84, 80, 44),
		},
		{
			at = Vector3.new(0, -0.15, -0.95),
			size = Vector3.new(0.5, 0.3, 0.14),
			color = Color3.fromRGB(44, 48, 60),
		},
	},
	BlueTang = {
		-- the black palette marking, the yellow tail and pectoral fins
		{
			at = Vector3.new(0, 0.3, 0.05),
			size = Vector3.new(1.04, 0.32, 0.75),
			color = Color3.fromRGB(18, 24, 52),
			hug = true,
		},
		{
			at = Vector3.new(0, 0, 1.05),
			size = Vector3.new(0.08, 0.55, 0.22),
			color = TANG_YELLOW,
		},
		{ at = Vector3.new(0.85, -0.15, -0.2), ball = 0.07, color = TANG_YELLOW, hug = true },
		{ at = Vector3.new(-0.85, -0.15, -0.2), ball = 0.07, color = TANG_YELLOW, hug = true },
	},
	Lingcod = {
		-- the pale belly, dark blotches, the long spiny back fin, the huge jaw
		{
			at = Vector3.new(0, -0.35, 0),
			size = Vector3.new(0.85, 0.6, 0.85),
			color = Color3.fromRGB(170, 182, 164),
		},
		{ at = Vector3.new(0.85, 0.3, -0.2), ball = 0.06, color = Color3.fromRGB(70, 76, 56), hug = true },
		{ at = Vector3.new(-0.85, 0.3, -0.2), ball = 0.06, color = Color3.fromRGB(70, 76, 56), hug = true },
		{ at = Vector3.new(0.85, 0.2, 0.25), ball = 0.06, color = Color3.fromRGB(70, 76, 56), hug = true },
		{ at = Vector3.new(-0.85, 0.2, 0.25), ball = 0.06, color = Color3.fromRGB(70, 76, 56), hug = true },
		{
			at = Vector3.new(0, 0.95, 0.1),
			size = Vector3.new(0.08, 0.35, 0.85),
			color = Color3.fromRGB(84, 94, 74),
		},
		{
			at = Vector3.new(0, -0.1, -0.85),
			size = Vector3.new(0.75, 0.55, 0.35),
			color = Color3.fromRGB(110, 122, 102),
		},
	},
	Rattail = {
		-- the big blunt head, the long thin rat tail, ember-orange fin edges
		{
			at = Vector3.new(0, 0.05, -0.6),
			size = Vector3.new(1.15, 1.15, 0.5),
			color = Color3.fromRGB(92, 104, 124),
		},
		{
			at = Vector3.new(0, 0, 1.35),
			size = Vector3.new(0.12, 0.14, 0.9),
			color = Color3.fromRGB(86, 98, 118),
		},
		{
			at = Vector3.new(0, 1.1, -0.3),
			size = Vector3.new(0.08, 0.6, 0.22),
			color = Color3.fromRGB(80, 90, 108),
		},
		{
			at = Vector3.new(0, 0.95, 0.45),
			size = Vector3.new(0.06, 0.12, 0.8),
			color = EMBER_EDGE,
		},
		{
			at = Vector3.new(0, -0.95, 0.45),
			size = Vector3.new(0.06, 0.12, 0.8),
			color = EMBER_EDGE,
		},
	},
	Viperfish = {
		-- the glassy fangs, its rows of cyan spots (the GLOWS sit inside a part body)
		{
			at = Vector3.new(0, -0.2, -1),
			size = Vector3.new(0.35, 0.5, 0.08),
			color = Color3.fromRGB(214, 228, 236),
		},
		{
			at = Vector3.new(0, 0.95, 0.1),
			size = Vector3.new(0.08, 0.45, 0.25),
			color = Color3.fromRGB(56, 84, 110),
		},
		{ at = Vector3.new(0.85, -0.45, -0.3), ball = 0.025, color = VIPER_GLOW, hug = true },
		{ at = Vector3.new(-0.85, -0.45, -0.3), ball = 0.025, color = VIPER_GLOW, hug = true },
		{ at = Vector3.new(0.85, -0.45, 0), ball = 0.025, color = VIPER_GLOW, hug = true },
		{ at = Vector3.new(-0.85, -0.45, 0), ball = 0.025, color = VIPER_GLOW, hug = true },
		{ at = Vector3.new(0.85, -0.45, 0.3), ball = 0.025, color = VIPER_GLOW, hug = true },
		{ at = Vector3.new(-0.85, -0.45, 0.3), ball = 0.025, color = VIPER_GLOW, hug = true },
	},
	Hatchetfish = {
		-- the silver belly under the navy back, the keel's row of cyan dots, the tail stalk
		{
			at = Vector3.new(0, -0.3, 0),
			size = Vector3.new(0.9, 0.65, 0.85),
			color = Color3.fromRGB(168, 188, 212),
		},
		{
			at = Vector3.new(0, 0, 1.1),
			size = Vector3.new(0.12, 0.22, 0.3),
			color = Color3.fromRGB(150, 170, 196),
		},
		{ at = Vector3.new(0.6, -0.72, -0.3), ball = 0.04, color = HATCHET_GLOW, hug = true },
		{ at = Vector3.new(-0.6, -0.72, -0.3), ball = 0.04, color = HATCHET_GLOW, hug = true },
		{ at = Vector3.new(0.6, -0.78, 0), ball = 0.04, color = HATCHET_GLOW, hug = true },
		{ at = Vector3.new(-0.6, -0.78, 0), ball = 0.04, color = HATCHET_GLOW, hug = true },
		{ at = Vector3.new(0.6, -0.72, 0.3), ball = 0.04, color = HATCHET_GLOW, hug = true },
		{ at = Vector3.new(-0.6, -0.72, 0.3), ball = 0.04, color = HATCHET_GLOW, hug = true },
	},
	HumpheadWrasse = {
		-- the tall forehead hump, the thick lips, the paler belly
		{
			at = Vector3.new(0, -0.3, 0),
			size = Vector3.new(0.85, 0.6, 0.85),
			color = Color3.fromRGB(84, 182, 182),
		},
		{
			at = Vector3.new(0, 0.7, -0.62),
			size = Vector3.new(0.75, 0.55, 0.4),
			color = Color3.fromRGB(44, 140, 174),
		},
		{
			at = Vector3.new(0, -0.2, -1),
			size = Vector3.new(0.42, 0.32, 0.14),
			color = Color3.fromRGB(60, 170, 182),
		},
	},
}

type LightPick = { distance: number, at: Vector3, color: Color3, index: number, used: boolean }
-- (`index`: the fish it's on, 0 = none)
local glowLights: { { part: BasePart, light: PointLight, index: number } } = {} -- made in start
local lightPicks: { LightPick } = {} -- this frame's nearest
local glowHeld: { [number]: boolean } = {} -- the fish holding a light last frame

-- A fish's extras (nil = none): its SHAPES on a part body, its GLOWS on any body
local function makeExtras(preyId: string, length: number, bodySize: Vector3, partBody: boolean): { Extra }?
	local list: { Extra } = {}
	local half = bodySize / 2
	local function add(spec: ExtraSpec, near: number, neon: boolean, light: boolean)
		local at = spec.at
		local taper = if spec.hug then math.sqrt(math.max(1 - at.Z * at.Z, 0.05)) else 1
		local ball = spec.ball
		table.insert(list, {
			part = nil,
			color = spec.color,
			size = if ball
				then Vector3.one * (ball * length)
				else bodySize * (spec.size or Vector3.one) * taper,
			offset = CFrame.new(at.X * half.X * taper, at.Y * half.Y * taper, at.Z * half.Z),
			neon = neon,
			near = near,
			light = light,
			shown = false,
		})
	end
	local shapes = SHAPES[preyId]
	if partBody and shapes then
		for _, spec in shapes do
			add(spec, math.huge, false, false)
		end
	end
	local glow = GLOWS[preyId]
	if glow then
		for i, spec in glow.spots do
			add(spec, glow.near, true, glow.light and i == 1)
		end
	end
	return if #list > 0 then list else nil
end

local function showExtra(extra: Extra, shown: boolean)
	if extra.shown == shown then
		return
	end
	extra.shown = shown
	local part = extra.part
	if part == nil and shown and folder then
		local made = makePart(folder :: Folder, extra.color, "Ellipsoid")
		made.Name = "Extra"
		made.Size = extra.size
		if extra.neon then
			made.Material = Enum.Material.Neon
		end
		extra.part = made
	elseif part then
		part.Transparency = if shown then 0 else 1
	end
end

-- Keeps the GLOW_LIGHTS nearest glowing fish this frame (sorted, nearest first; a fish
-- holding a light counts GLOW_KEEP nearer)
local function pickLight(distance: number, at: Vector3, color: Color3, index: number)
	if glowHeld[index] then
		distance -= GLOW_KEEP
	end
	local count = #lightPicks
	if count >= GLOW_LIGHTS and distance >= lightPicks[count].distance then
		return
	end
	local i = count
	while i >= 1 and lightPicks[i].distance > distance do
		i -= 1
	end
	table.insert(
		lightPicks,
		i + 1,
		{ distance = distance, at = at, color = color, index = index, used = false }
	)
	if #lightPicks > GLOW_LIGHTS then
		table.remove(lightPicks)
	end
end

-- The imported prey (docs/ASSETS.md): ReplicatedStorage.PreyModels.<PreyId>, a rigged
-- Model (bones swim it) or an older static MeshPart. Nothing while it isn't
-- imported (the ellipsoid is drawn).
local function preyTemplate(preyId: string): (MeshPart?, Model?)
	local folder = ReplicatedStorage:FindFirstChild("PreyModels")
	local template = folder and folder:FindFirstChild(preyId)
	if template and template:IsA("MeshPart") then
		return template, nil
	end
	if template and template:IsA("Model") then
		local mesh = template:FindFirstChildWhichIsA("MeshPart", true)
		if mesh and template:FindFirstChildWhichIsA("Bone", true) then
			return mesh, template
		end
		return mesh, nil
	end
	return nil, nil
end

local function bonesOf(model: Model): ({ [string]: Bone }, { string })
	local bones: { [string]: Bone } = {}
	local spine: { string } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Bone") then
			bones[descendant.Name] = descendant
		end
	end
	local i = 1
	while bones[`Spine{i}`] do
		table.insert(spine, `Spine{i}`)
		i += 1
	end
	if bones.Tail then
		table.insert(spine, "Tail")
	end
	return bones, spine
end

-- A prey's body from its import, set up once (anchored, scaled to 1, its size
-- measured) and cloned for each of its fish as their schools are built
local function protoOf(prey: any): Proto
	local known = protos[prey.id]
	if known then
		return known
	end
	local template, rigged = preyTemplate(prey.id)
	local proto: Proto = { model = nil, mesh = nil, unitLength = 1, extents = Vector3.one, flip = false }
	if rigged then
		local clone = rigged:Clone()
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
		proto.extents = clone:GetExtentsSize()
		proto.unitLength = math.max(proto.extents.Z, 0.01)
		clone:PivotTo(CFrame.new())
		clone:PivotTo(CFrame.new(-clone:GetBoundingBox().Position))
		clone.PrimaryPart = clone.PrimaryPart or clone:FindFirstChildWhichIsA("MeshPart", true)
		proto.model = clone
	elseif template then
		local mesh = template:Clone()
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.CastShadow = false
		proto.mesh = mesh
		proto.extents = template.Size
		proto.unitLength = math.max(template.Size.Z, 0.01)
		proto.flip = SwimWave.needsFlip(template)
	end
	protos[prey.id] = proto
	return proto
end

local function partsOf(visual: Visual): { BasePart }
	local list: { BasePart } = {}
	if visual.model then
		for _, descendant in (visual.model :: Model):GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(list, descendant)
			end
		end
	else
		table.insert(list, visual.body)
	end
	if visual.tail then
		table.insert(list, visual.tail :: BasePart)
	end
	return list
end

-- How far out of its range a fish is drawn (LocalTransparencyModifier: 0 shown .. 1
-- gone); a rare fish's look sheds nothing while it's out of range
local function setCull(visual: Visual, cull: number)
	local was = visual.cull
	visual.cull = cull
	for _, part in visual.parts do
		part.LocalTransparencyModifier = cull
	end
	local extras = visual.extras
	if extras then
		for _, extra in extras do
			if extra.part then
				(extra.part :: BasePart).LocalTransparencyModifier = cull
			end
			if cull >= 1 then
				showExtra(extra, false) -- (not moved while it's out of range)
			end
		end
	end
	local look = visual.look
	if look and (was >= 1) ~= (cull >= 1) then
		if look.sparkle then
			look.sparkle.Enabled = cull < 1
		end
		if look.light then
			look.light.Enabled = cull < 1
		end
	end
end

-- One fish's body, out of sight until it's drawn in range
local function makeVisual(index: number): Visual
	local fish = Schools.fish[index]
	local prey = Config.Prey.byId[fish.prey]
	local length = fish.length
	local bodySize = Vector3.new(length * prey.slim * 0.8, length * prey.slim, length * 0.78)
	local tailSize = Vector3.new(length * 0.03, length * prey.slim * 1.1, length * 0.26)
	local proto = protoOf(prey)
	local parent = folder :: Folder
	local body: BasePart
	local tail: BasePart? = nil
	local model: Model? = nil
	local bones: { [string]: Bone } = {}
	local spine: { string } = {}
	local unitScale = 1
	local flip = false
	if proto.model then
		-- A rigged body: anchored, scaled to the fish's length, its bones swim
		local clone = (proto.model :: Model):Clone()
		unitScale = length / proto.unitLength
		clone:ScaleTo(unitScale)
		bodySize = proto.extents * unitScale
		bones, spine = bonesOf(clone)
		clone.Parent = parent
		model = clone
		body = (clone.PrimaryPart or clone:FindFirstChildWhichIsA("MeshPart", true)) :: BasePart
	elseif proto.mesh then
		local mesh = (proto.mesh :: MeshPart):Clone()
		bodySize = proto.extents * (length / proto.unitLength)
		mesh.Size = bodySize
		mesh.Parent = parent
		body = mesh
		flip = proto.flip
	else
		body = makePart(parent, prey.back, "Ellipsoid")
		body.Size = bodySize
		local fin = makePart(parent, prey.back:Lerp(prey.belly, 0.3), "Fin")
		fin.Name = "Tail"
		fin.Size = tailSize
		tail = fin
	end
	body.Name = prey.id
	local visual: Visual = {
		body = body,
		tail = tail,
		bodySize = bodySize,
		tailSize = tailSize,
		hidden = false,
		backAt = 0,
		pendingUntil = 0,
		suckFrom = nil,
		suckStart = 0,
		fadeIn = 1,
		model = model,
		bones = bones,
		spine = spine,
		unitScale = unitScale,
		phase = fish.phase * 3,
		stepAt = 0,
		pace = prey.speed,
		swimRate = 2 * math.pi * (0.9 + prey.speed * 0.22),
		holdUntil = 0,
		far = 0,
		lit = nil,
		waveFrame = 0,
		flip = flip,
		chase = nil,
		parts = {},
		cull = 0,
	}
	visual.parts = partsOf(visual)
	visual.extras = makeExtras(prey.id, length, bodySize, model == nil and not proto.mesh)
	setCull(visual, 1)
	return visual
end

local function setHidden(visual: Visual, hidden: boolean)
	if visual.hidden == hidden then
		return
	end
	visual.hidden = hidden
	visual.holdUntil = 0
	local transparency = if hidden then 1 else 0
	for _, part in visual.parts do
		part.Transparency = transparency
	end
	if hidden and visual.extras then
		for _, extra in visual.extras do
			showExtra(extra, false) -- (shown again as it's drawn: step)
		end
	end
	if not hidden then
		if visual.model then
			(visual.model :: Model):ScaleTo(visual.unitScale)
		else
			visual.body.Size = visual.bodySize
		end
		if visual.tail then
			visual.tail.Size = visual.tailSize
		end
		visual.fadeIn = 0
	end
end

-- A Silver fish's mirror flash at `now`: 0 at rest, 1 at its peak. Each fish has its
-- own period (SILVER_PERIOD + up to SILVER_SPREAD) and phase from its index, so the
-- silver fish in a school never flash together
local function silverFlash(index: number, now: number): number
	local h = math.sin(index * 12.9898) * 43758.5453
	h -= math.floor(h)
	local period = SILVER_PERIOD + SILVER_SPREAD * h
	local at = ((now + h * 7.3) / period) % 1
	local d = math.abs(at - 0.5) / SILVER_WIDTH
	if d >= 1 then
		return 0
	end
	local bump = 1 - d * d
	return bump * bump
end

-- Takes a rarity's look off a fish, putting its own texture and colours back
local function clearLook(index: number, visual: Visual)
	local look = visual.look
	if look == nil then
		return
	end
	visual.look = nil
	prisms[index] = nil
	silvers[index] = nil
	silverPulse[index] = nil
	glints[index] = nil
	glintShown[index] = nil
	glintBlocked[index] = nil
	glintVis[index] = nil
	for part, saved in look.saved do
		part.Color = saved.color
		part.Material = saved.material
		part.Reflectance = saved.reflectance
		if not visual.hidden then
			part.Transparency = saved.transparency
		end
		if saved.texture then
			(part :: MeshPart).TextureID = saved.texture
		end
	end
	for part, appearance in look.held do
		appearance.Parent = part
	end
	for _, extra in look.extras do
		extra:Destroy()
	end
end

-- Puts a rarity's look on a fish (nil = plain)
local function setLook(index: number, rarityId: string?)
	local visual = visuals[index]
	if visual == nil or (visual.look and visual.look.rarity == rarityId) then
		return
	end
	clearLook(index, visual)
	visual.holdUntil = 0 -- (a rare fish is moved every frame)
	local style = if rarityId then LOOKS[rarityId] else nil
	local def = if rarityId then CatchConfig.byId[rarityId] else nil
	if rarityId == nil or style == nil or def == nil then
		return
	end
	local look: Look = { rarity = rarityId, held = {}, saved = {}, extras = {}, light = nil }
	for _, part in partsOf(visual) do
		if part.Transparency >= 1 and not visual.hidden then
			continue -- a part the model keeps hidden
		end
		-- Prey batch 2 is textured by its TextureID, not a SurfaceAppearance: held aside
		-- too (PC 2026-10-19 round 2, SV3: a Silver Tuna or Mahi-mahi kept its whole
		-- texture under the silver and barely read as rare)
		local texture = if part:IsA("MeshPart") and part.TextureID ~= "" then part.TextureID else nil
		look.saved[part] = {
			color = part.Color,
			material = part.Material,
			reflectance = part.Reflectance,
			transparency = if visual.hidden then 0 else part.Transparency,
			texture = texture,
		}
		local appearance = part:FindFirstChildOfClass("SurfaceAppearance")
		if appearance then
			look.held[part] = appearance
			appearance.Parent = nil
		end
		if texture then
			(part :: MeshPart).TextureID = ""
		end
		part.Color = style.color
		part.Material = style.material
		part.Reflectance = style.reflectance
		if not visual.hidden then
			part.Transparency = style.transparency
		end
	end
	local length = Schools.fish[index].length
	local attachment = Instance.new("Attachment")
	attachment.Name = "RareLook"
	attachment.Parent = visual.body
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = SPARKLE
	sparkle.Color = if rarityId == "Silver"
		then ColorSequence.new(Color3.new(1, 1, 1), def.color)
		else ColorSequence.new(def.color)
	sparkle.LightEmission = 1
	sparkle.Rate = (if rarityId == "Silver" then 8 else 5) + math.min(length, 6)
	sparkle.Lifetime = NumberRange.new(0.6, 1.2)
	sparkle.Speed = NumberRange.new(0.2, 0.8)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, math.clamp(length * 0.18, 0.15, 1.2)),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkle.Transparency = NumberSequence.new(0.2, 1)
	sparkle.Parent = attachment
	local light = Instance.new("PointLight")
	light.Color = def.color
	light.Brightness = style.light
	light.Range = math.clamp(6 + length * 2 + (LIGHT_BONUS[rarityId] or 0), 8, 22)
	light.Shadows = false
	light.Parent = attachment
	if rarityId == "Silver" then
		-- Its own small light just over its back, lighting its back and flanks and
		-- barely reaching the plain fish round it
		local over = Instance.new("Attachment")
		over.Name = "SilverLight"
		over.Parent = visual.body
		over.Position = Vector3.new(0, visual.bodySize.Y * 0.5 + length * 0.3, 0)
		light.Color = SILVER_LIGHT
		light.Range = math.clamp(length * 1.8, 3, 12)
		light.Parent = over
		table.insert(look.extras, over)
	end
	-- The glint: two thin bars crossed (a four-point star) and a bright core
	local glint = Instance.new("BillboardGui")
	glint.Name = "Glint"
	local pixels = GLINT_PIXELS[rarityId] or 15
	glint.Size = UDim2.fromOffset(pixels, pixels)
	glint.LightInfluence = 0
	glint.AlwaysOnTop = true -- through the haze; rock hides it by ray (glintBlocked)
	glint.MaxDistance = GLINT_RANGE
	glint.Enabled = false
	local scale = Instance.new("UIScale")
	scale.Parent = glint
	for _, bar in { Vector2.new(1, 0.16), Vector2.new(0.16, 1) } do
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.fromScale(bar.X, bar.Y)
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = def.color:Lerp(Color3.new(1, 1, 1), 0.35)
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Rotation = if bar.X > bar.Y then 0 else 90
		fade.Parent = frame
		frame.Parent = glint
	end
	local core = Instance.new("Frame")
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromScale(0.34, 0.34)
	core.BorderSizePixel = 0
	core.BackgroundColor3 = def.color:Lerp(Color3.new(1, 1, 1), 0.6)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = core
	core.Parent = glint
	glint.Parent = attachment
	look.glint = glint
	look.glintScale = scale
	glints[index] = look
	table.insert(look.extras, attachment)
	look.light = light
	look.sparkle = sparkle
	if visual.cull >= 1 then
		-- (out of range: nothing shows until it's drawn)
		sparkle.Enabled = false
		light.Enabled = false
	end
	visual.look = look
	if rarityId == "Prism" then
		prisms[index] = visual
	elseif rarityId == "Silver" then
		silvers[index] = visual
	end
end

-- The rarity of fish `index` (nil = plain), as the server last said
function SchoolController.rarityOf(index: number): string?
	return rarities[index]
end

-- Whether a school is out now: a tide's own schools only while it's up
local function schoolOut(school: Schools.School): boolean
	return school.tide == nil or school.tide == Tides.at(Timing.unix()).id
end

-- The nearest prey fish a fish `length` long could swallow, within `range` studs of
-- `from` (the tutorial's guide points at it). Positions come off the shared paths,
-- so it costs nothing to ask for one that isn't drawn.
function SchoolController.nearestEdible(from: Vector3, length: number, range: number): Vector3?
	local now = Timing.clock()
	local best: Vector3? = nil
	local bestDistance = range
	for schoolIndex, school in Schools.list do
		if (school.center - from).Magnitude > range + school.radius or not schoolOut(school) then
			continue
		end
		local schoolFrame = Schools.schoolFrame(schoolIndex, now)
		for index = school.first, school.first + school.count - 1 do
			local fish = Schools.fish[index]
			local visual = visuals[index]
			if not Size.canSwallow(length, fish.length) then
				continue
			end
			-- (a school not built here yet: what the server said about its fish)
			if if visual then visual.hidden else (backAts[index] or 0) > now then
				continue
			end
			local position = Schools.fishFrame(index, schoolFrame, now).Position
			local distance = (position - from).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				best = position
			end
		end
	end
	return best
end

-- The prey fish a fish `length` long could swallow within `range` studs of `from`,
-- drawn and showing, nearest first, at most `count` (Blood Sense marks them,
-- AbilityController): each one's drawn body (its rigged Model, or its part) and how
-- far off it is
function SchoolController.edibleNear(
	from: Vector3,
	length: number,
	range: number,
	count: number
): { { instance: Instance, distance: number } }
	local now = Timing.clock()
	local found: { { instance: Instance, distance: number } } = {}
	if count <= 0 then
		return found
	end
	for schoolIndex, school in Schools.list do
		if (school.center - from).Magnitude > range + school.radius or not schoolOut(school) then
			continue
		end
		local schoolFrame = Schools.schoolFrame(schoolIndex, now)
		for index = school.first, school.first + school.count - 1 do
			local fish = Schools.fish[index]
			local visual = visuals[index]
			if
				visual == nil
				or visual.hidden
				or visual.cull >= 1 -- (out of its draw range: not where it swims)
				or visual.suckFrom ~= nil
				or not Size.canSwallow(length, fish.length)
			then
				continue
			end
			local distance = (Schools.fishFrame(index, schoolFrame, now).Position - from).Magnitude
			if distance <= range then
				local body: Instance = visual.model or visual.body
				table.insert(found, { instance = body, distance = distance })
			end
		end
	end
	table.sort(found, function(a, b)
		return a.distance < b.distance
	end)
	while #found > count do
		table.remove(found)
	end
	return found
end

local function onRarity(indices: { number }, codes: { number })
	for i, index in indices do
		local code = codes[i]
		local def = if typeof(code) == "number" and code > 0 then CatchConfig.rarities[code] else nil
		if typeof(index) ~= "number" or Schools.fish[index] == nil then
			continue
		end
		if def then
			rarities[index] = def.id
		else
			rarities[index] = nil
		end
		-- (a fish whose school isn't built here wears it when it is)
		if visuals[index] then
			setLook(index, if def then def.id else nil)
		end
	end
end

local function flush(now: number)
	if #batch == 0 or now - lastSend < SEND_INTERVAL then
		return
	end
	lastSend = now
	ClientState.request("EatPrey", batch)
	batch = {}
end

-- A school comes into reach: its fish get bodies, wearing what the server said
-- about them (eaten until, rarity), as many as fit in this frame's budget (at least
-- one); the rest next frame
local function buildSchool(schoolIndex: number, now: number, started: number)
	local school = Schools.list[schoolIndex]
	local from = nextFish[schoolIndex] or school.first
	built[schoolIndex] = true
	nextFish[schoolIndex] = nil
	for index = from, school.first + school.count - 1 do
		if index > from and os.clock() - started > BUILD_BUDGET then
			nextFish[schoolIndex] = index
			return
		end
		local visual = makeVisual(index)
		visuals[index] = visual
		builtCount += 1
		local back = backAts[index]
		if back and back > now then
			visual.backAt = back
			setHidden(visual, true)
		end
		local rarity = rarities[index]
		if rarity then
			setLook(index, rarity)
		end
	end
end

-- A school far out of reach (or its tide over): its fish's bodies go
local function releaseSchool(schoolIndex: number)
	local school = Schools.list[schoolIndex]
	built[schoolIndex] = nil
	nextFish[schoolIndex] = nil
	tideFade[schoolIndex] = nil
	for index = school.first, school.first + school.count - 1 do
		local visual = visuals[index]
		if visual == nil then
			continue
		end
		visuals[index] = nil
		builtCount -= 1
		clearLook(index, visual)
		if visual.chase then
			visual.chase.glow:Destroy()
		end
		if visual.model then
			(visual.model :: Model):Destroy()
		else
			visual.body:Destroy()
		end
		if visual.tail then
			(visual.tail :: BasePart):Destroy()
		end
		if visual.extras then
			for _, extra in visual.extras do
				if extra.part then
					(extra.part :: BasePart):Destroy()
				end
			end
		end
	end
end

local function step(dt: number)
	local now = Timing.clock()
	local camera = workspace.CurrentCamera.CFrame.Position
	local root = SwimController.root()
	local length = SwimController.length()
	local mouth: Vector3? = nil
	local reach = Size.reach(length)
	local inHub = false
	-- A Reef Shark's Blood Sense frenzy draws prey in from further (Perks.sense), and
	-- so does an Angler Lure part (Perks.exotic; the server allows the same)
	local suction = 1
	if root then
		mouth = root.CFrame:PointToWorldSpace(Size.mouthOffset(length))
		local character = SwimController.character()
		inHub = character ~= nil and character:GetAttribute("InHub") == true
		local _, pull = Perks.sense(character, now)
		suction = pull * Perks.exotic(character).reach
	end
	-- No fish further than this from our mouth can be pulled in or reached (the
	-- biggest prey's reach and pull), so nearer ones alone are checked for an eat
	local eat = Config.Prey.eat
	local eatLook = (reach * math.max(eat.scale, 1) + math.max(eat.bonus, 0) + biggestRadius)
			* math.max(eat.pull, 1)
			* suction
		+ 1

	table.clear(parts)
	table.clear(frames)
	local tideId = Tides.at(Timing.unix()).id
	-- Prism fish shimmer through the rainbow
	if next(prisms) then
		local hue = (now * 0.25) % 1
		for index, visual in prisms do
			local look = visual.look
			if look then
				local color = Color3.fromHSV((hue + index * 0.07) % 1, 0.65, 1)
				for part in look.saved do
					part.Color = color
				end
				if look.light then
					look.light.Color = color
				end
			end
		end
	end
	-- Silver fish: the mirror flash, redrawn only while one runs (or to put a fish
	-- back at rest after one)
	for index, visual in silvers do
		local look = visual.look
		if look and visual.cull < 1 then
			local pulse = silverFlash(index, now)
			if pulse > 0 or (silverPulse[index] or 0) > 0 then
				silverPulse[index] = pulse
				local neon = pulse > SILVER_NEON and (visual.body.Position - camera).Magnitude > SILVER_NEAR
				local material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
				local color = SILVER_BASE:Lerp(SILVER_FLASH, pulse)
				for part in look.saved do
					part.Color = color
					part.Reflectance = SILVER_SHEEN * (1 - pulse)
					if part.Material ~= material then
						part.Material = material
					end
				end
				if look.light then
					look.light.Brightness = SILVER_GLOW + (SILVER_GLOW_FLASH - SILVER_GLOW) * pulse
				end
			end
		end
	end
	table.clear(glintSeen)
	table.clear(glintAt)
	-- How far this client can afford to draw: its frame time, smoothed over a couple
	-- of seconds, eases the ranges in on a slow device and back out
	smoothDt += (math.min(dt, 0.1) - smoothDt) * math.min(1, dt * 0.6)
	frameCount += 1
	local wantDetail = if smoothDt > SLOW_FRAME then DETAIL_MIN elseif smoothDt < FAST_FRAME then 1 else detail
	detail += (wantDetail - detail) * math.min(1, dt * 0.3)
	-- Schools near enough are built (nearest first, a few milliseconds a frame), far
	-- ones let go; only built ones are drawn
	table.clear(wanted)
	table.clear(drawList)
	for schoolIndex, school in Schools.list do
		local away = (school.center - camera).Magnitude
		local reachHere = school.reach * detail
		if built[schoolIndex] then
			if away > reachHere + RELEASE_SLACK then
				releaseSchool(schoolIndex)
			else
				table.insert(drawList, schoolIndex)
				if nextFish[schoolIndex] then
					table.insert(wanted, { index = schoolIndex, away = away }) -- (the rest of it)
				end
			end
		elseif away <= reachHere and (school.tide == nil or school.tide == tideId) then
			table.insert(wanted, { index = schoolIndex, away = away })
		end
	end
	if #wanted > 0 then
		table.sort(wanted, function(a, b)
			return a.away < b.away
		end)
		local started = os.clock()
		for _, entry in wanted do
			if os.clock() - started > BUILD_BUDGET then
				break
			end
			local fresh = not built[entry.index]
			buildSchool(entry.index, now, started)
			if fresh then
				table.insert(drawList, entry.index)
			end
		end
	end
	for _, schoolIndex in drawList do
		local school = Schools.list[schoolIndex]
		-- A tide's school (the Sardine Run's bait balls) only while its tide is up: near
		-- the camera when it ends it shrinks away, then it's let go
		local fadeOut: number? = nil
		if school.tide and school.tide ~= tideId then
			local fading = tideFade[schoolIndex]
			if fading == nil and (school.center - camera).Magnitude < TIDE_FADE_RANGE + school.radius then
				fading = now
				tideFade[schoolIndex] = now
			end
			if fading == nil or now - fading >= TIDE_FADE then
				releaseSchool(schoolIndex)
				continue
			end
			fadeOut = (now - fading) / TIDE_FADE
		elseif tideFade[schoolIndex] then
			tideFade[schoolIndex] = nil
			for index = school.first, school.first + school.count - 1 do
				local visual = visuals[index]
				if visual then
					visual.fadeIn = 0 -- one caught mid-fade grows back
				end
			end
		end
		local schoolFrame = Schools.schoolFrame(schoolIndex, now)
		for index = school.first, school.first + school.count - 1 do
			local fish = Schools.fish[index]
			local visual = visuals[index]
			if visual == nil then
				continue -- (still being built)
			end
			if
				visual.cull >= 1
				and visual.chase == nil
				and visual.suckFrom == nil
				and (index + frameCount) % CULL_EVERY ~= 0
			then
				continue
			end
			-- Held between moves (`holdUntil`, set as it's drawn below: MOVE_STEP), it stays
			-- where it was, its glow light still picked (by where the camera is now)
			if visual.holdUntil > frameCount then
				drawnCount += 1
				local lit, at = visual.lit, visual.at
				if lit and at then
					pickLight((at - camera).Magnitude, at, lit, index)
				end
				continue
			end
			-- Respawned, or our eat wasn't confirmed: show it again
			if visual.hidden and visual.suckFrom == nil then
				if visual.pendingUntil > 0 and now > visual.pendingUntil then
					visual.pendingUntil = 0
					visual.backAt = 0
				end
				if visual.pendingUntil == 0 and now >= visual.backAt then
					setHidden(visual, false)
				end
			end
			local frame = Schools.fishFrame(index, schoolFrame, now)
			-- Chasing: it darts off its path at the player and comes back
			local chase = visual.chase
			if chase then
				local character = chase.target.Character
				local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
				if now >= chase.endsAt or targetRoot == nil or not targetRoot:IsA("BasePart") then
					chase.glow:Destroy()
					visual.chase = nil
				else
					local targetLength = character and character:GetAttribute("Length")
					local blend = Schools.chaseBlend(now - chase.startAt, aggro.seconds, aggro.lungeAt)
					local at = Schools.chasePosition(
						index,
						frame.Position,
						targetRoot.Position,
						if typeof(targetLength) == "number" then targetLength else 2,
						blend
					)
					local toward = targetRoot.Position - at
					if toward.Magnitude > 1e-3 and blend > 0.02 then
						local face = CFrame.lookAt(at, at + toward)
						frame = frame.Rotation:Lerp(face.Rotation, math.min(blend * 1.5, 1)) + at
					else
						frame = frame.Rotation + at
					end
					chase.glow.FillTransparency = 0.6 + 0.3 * (1 - blend)
				end
			end
			-- Out of its draw range it isn't drawn (or eaten); over the last of it, it fades
			local far = (frame.Position - camera).Magnitude
			local mouthGap = if mouth then (frame.Position - mouth).Magnitude else math.huge
			local range = (if rarities[index] then math.max(fish.range, RARE_RANGE) else fish.range) * detail
			local cull = 0
			if visual.suckFrom == nil and visual.chase == nil and far > range * (1 - FADE_SHARE) then
				cull = math.min(
					math.floor((far - range * (1 - FADE_SHARE)) / (range * FADE_SHARE) * 10 + 0.5) / 10,
					1
				)
			end
			if cull ~= visual.cull then
				setCull(visual, cull)
			end
			if cull >= 1 then
				continue
			end
			if visual.suckFrom then
				-- Sucked into our mouth: slide in and shrink, then vanish
				local alpha = math.clamp((now - visual.suckStart) / SUCK_SECONDS, 0, 1)
				local target = mouth or frame.Position
				local from = visual.suckFrom :: CFrame
				frame = CFrame.new(from.Position:Lerp(target, alpha * alpha)) * from.Rotation
				local shrink = 1 - alpha * 0.85
				if visual.model then
					(visual.model :: Model):ScaleTo(visual.unitScale * shrink)
				else
					visual.body.Size = visual.bodySize * shrink
				end
				if visual.tail then
					visual.tail.Size = visual.tailSize * shrink
				end
				if alpha >= 1 then
					visual.suckFrom = nil
					setHidden(visual, true)
				end
			elseif not visual.hidden then
				if fadeOut then
					-- Its tide is over: it shrinks away (and can't be eaten any more)
					local shrink = 1 - 0.8 * fadeOut
					if visual.model then
						(visual.model :: Model):ScaleTo(visual.unitScale * shrink)
					else
						visual.body.Size = visual.bodySize * shrink
					end
					if visual.tail then
						visual.tail.Size = visual.tailSize * shrink
					end
				elseif visual.fadeIn < 1 then
					-- Back from being eaten: it swims in from behind the school as it grows
					visual.fadeIn = math.min(1, visual.fadeIn + dt / RETURN_SECONDS)
					local behind = (1 - visual.fadeIn) ^ 2 * RETURN_LENGTHS * fish.length
					frame *= CFrame.new(0, 0, behind)
					local grow = 0.3 + 0.7 * visual.fadeIn
					if visual.model then
						(visual.model :: Model):ScaleTo(visual.unitScale * grow)
					else
						visual.body.Size = visual.bodySize * grow
					end
					if visual.tail then
						visual.tail.Size = visual.tailSize * grow
					end
				end
				-- Eat it if it's in reach and small enough: a fish we can swallow is drawn
				-- toward the mouth as we pass close (suction), and goes in a little way out
				-- (owner, 2026-10-17: "I've swam inches from one and if you don't directly
				-- hit the fish it doesn't eat it")
				-- (a fish still swimming back in is drawn off its path, where the server
				-- wouldn't find it: it's edible once nearly back, RETURN_EDIBLE)
				-- (only near our mouth: `eatLook`)
				local open = fadeOut == nil and mouth ~= nil and not inHub and visual.fadeIn >= RETURN_EDIBLE
				if open and mouthGap <= eatLook then
					local gap = mouthGap
					local swallow = Size.canSwallow(length, fish.length)
					local inReach = false
					if swallow then
						local eatReach, pullRange = Schools.eatReach(length, fish.radius)
						eatReach *= suction
						pullRange *= suction
						if gap < pullRange then
							local share = (1 - gap / pullRange) * eat.pullShare
							frame = CFrame.new(frame.Position:Lerp(mouth :: Vector3, share)) * frame.Rotation
							gap = (frame.Position - (mouth :: Vector3)).Magnitude
						end
						inReach = gap <= eatReach
					else
						inReach = gap <= reach + fish.radius
					end
					if inReach and not swallow then
						if now - lastTooBig > 1 then
							lastTooBig = now
							SchoolController.tooBig:fire(fish.prey)
						end
					elseif inReach then
						visual.suckFrom = frame
						visual.suckStart = now
						visual.pendingUntil = now + CONFIRM_SECONDS
						visual.backAt = math.huge
						table.insert(batch, { index, now })
						SchoolController.ate:fire(fish.prey, fish.mass, frame.Position, rarities[index])
					end
				end
			end
			local glintLook = glints[index]
			if glintLook and not visual.hidden then
				-- Twinkles, and fades in past GLINT_NEAR (up close the fish itself reads)
				local away = (frame.Position - camera).Magnitude
				local scaleBy = math.clamp((away - GLINT_NEAR) / GLINT_FADE, 0, 1)
				if scaleBy > 0 and away < GLINT_RANGE then
					glintAt[index] = frame.Position
					local vis = glintVis[index] or 0
					vis += ((if glintBlocked[index] then 0 else 1) - vis) * math.min(1, dt * 8)
					glintVis[index] = vis
					if vis > 0.02 then
						glintSeen[index] = true
						local glintScale = glintLook.glintScale
						if glintScale then
							-- (a Silver fish's star swells with its mirror flash)
							glintScale.Scale = scaleBy
								* vis
								* (0.75 + 0.25 * math.sin(now * 5 + index * 1.7))
								* (1 + 0.7 * (silverPulse[index] or 0))
						end
					end
				else
					glintVis[index] = 0
				end
			end
			if not visual.hidden then
				drawnCount += 1
				-- How fast it really moves on screen since it was last moved (`pace`)
				local since = now - visual.stepAt
				local last, facing = visual.at, visual.facing
				if last and facing and since > 0 and since < PACE_GAP then
					local turned = math.acos(math.clamp(facing:Dot(frame.LookVector), -1, 1))
					local rate = ((frame.Position - last).Magnitude + turned * fish.length * PACE_TURN)
						/ since
					visual.pace = if rate > visual.pace
						then rate
						else visual.pace + (rate - visual.pace) * math.min(1, since * PACE_SETTLE)
				end
				visual.at = frame.Position
				visual.facing = frame.LookVector
				visual.stepAt = now
				visual.far = far
				-- Held a few frames when it's far enough off for that pace (MOVE_STEP)
				local hold = 1
				if
					far > MOVE_NEAR
					and mouthGap > MOVE_NEAR
					and visual.suckFrom == nil
					and visual.chase == nil
					and visual.fadeIn >= 1
					and fadeOut == nil
					and rarities[index] == nil
				then
					hold = math.clamp(
						math.floor(far * MOVE_STEP / (math.max(visual.pace, 1) * smoothDt)),
						1,
						MOVE_MAX
					)
				end
				visual.holdUntil = frameCount + hold - 1
				local elapsed = math.min(since, 0.5)
				table.insert(parts, visual.body)
				local tail = visual.tail
				if visual.model then
					-- A rigged body: the head holds still and the wave runs down the spine
					-- (Shared/SwimWave), faster for the quick little ones
					-- (on the clock: a fish moved every few frames keeps its pace; its wave is
					-- set on frames it's moved, at most every WAVE_NEAR / WAVE_HALF tier's frames)
					visual.phase += elapsed * visual.swimRate
					local want = if far < WAVE_NEAR then 1 elseif far < WAVE_HALF then 2 else 3
					if
						far < math.min(fish.wave, WAVE_DISTANCE) * detail
						and frameCount - visual.waveFrame >= want
					then
						visual.waveFrame = frameCount
						SwimWave.applyBones(visual.bones, visual.spine, visual.phase, 0.34, 0)
					end
					table.insert(frames, frame)
				elseif tail then
					local beat = math.sin(now * (6 + fish.phase) + fish.phase * 4) * 0.55
					table.insert(frames, frame)
					table.insert(parts, tail)
					table.insert(
						frames,
						frame
							* CFrame.new(0, 0, visual.body.Size.Z * 0.45)
							* CFrame.Angles(0, beat, 0)
							* CFrame.new(0, 0, tail.Size.Z * 0.4)
					)
				else
					-- A one-piece static mesh: a small yaw wiggle about its head, turned round
					local beat = math.sin(now * (6 + fish.phase) + fish.phase * 4) * 0.55
					table.insert(
						frames,
						frame
							* CFrame.new(0, 0, -visual.body.Size.Z * 0.3)
							* CFrame.Angles(0, beat * 0.22, 0)
							* CFrame.new(0, 0, visual.body.Size.Z * 0.3)
							* (if visual.flip then MESH_FLIP else CFrame.identity)
					)
				end
				-- Its extras ride on it (not while it's sucked in, growing back or shrinking
				-- away: they don't scale); a glow only near the camera
				local extras = visual.extras
				visual.lit = nil
				if extras then
					local whole = visual.suckFrom == nil and fadeOut == nil and visual.fadeIn >= 1
					for _, extra in extras do
						local shown = whole and far < extra.near * detail
						showExtra(extra, shown)
						if shown and extra.part then
							table.insert(parts, extra.part :: BasePart)
							table.insert(frames, frame * extra.offset)
							if extra.light then
								local color = GLOWS[fish.prey].color
								visual.lit = color
								pickLight(far, frame.Position, color, index)
							end
						end
					end
				end
			end
		end
	end
	-- The faint lights go to the nearest glowing fish (GLOW_LIGHTS): first each light
	-- whose fish is still among them, then the free ones to the rest
	table.clear(glowHeld)
	for _, slot in glowLights do
		local kept = 0
		for _, pick in lightPicks do
			if pick.index == slot.index and not pick.used then
				pick.used = true
				kept = slot.index
				break
			end
		end
		slot.index = kept
	end
	for _, slot in glowLights do
		local pick: LightPick? = nil
		for _, candidate in lightPicks do
			if candidate.index == slot.index and slot.index ~= 0 then
				pick = candidate
				break
			end
		end
		if pick == nil then
			for _, candidate in lightPicks do
				if not candidate.used then
					candidate.used = true
					slot.index = candidate.index
					pick = candidate
					break
				end
			end
		end
		if pick then
			glowHeld[pick.index] = true
			table.insert(parts, slot.part)
			table.insert(frames, CFrame.new(pick.at))
			if slot.light.Color ~= pick.color then
				slot.light.Color = pick.color
			end
		else
			slot.index = 0
		end
		if slot.light.Enabled ~= (pick ~= nil) then
			slot.light.Enabled = pick ~= nil
		end
	end
	table.clear(lightPicks)
	-- Rock checks for the stars in reach, a few a frame, round robin
	table.clear(glintQueue)
	for index in glintAt do
		table.insert(glintQueue, index)
	end
	if #glintQueue > 0 then
		if rockWorld == nil or rockWorld.Parent == nil then
			rockWorld = workspace:FindFirstChild("World")
			rockParams.FilterDescendantsInstances = if rockWorld
				then { workspace.Terrain, rockWorld }
				else { workspace.Terrain }
		end
		table.sort(glintQueue)
		for _ = 1, math.min(GLINT_CHECKS, #glintQueue) do
			glintCursor = glintCursor % #glintQueue + 1
			local index = glintQueue[glintCursor]
			local toFish = glintAt[index] - camera
			-- Stop a little short, so the fish's own seabed doesn't count
			local hit =
				workspace:Raycast(camera, toFish * (1 - 1.5 / math.max(toFish.Magnitude, 1.5)), rockParams)
			glintBlocked[index] = hit ~= nil
		end
	end
	-- A glint shows only on a rare fish drawn this frame (a school out of reach sits at
	-- its built spot, and an eaten fish is hidden)
	for index, glintLook in glints do
		local shown = glintSeen[index] == true
		if glintShown[index] ~= shown then
			glintShown[index] = shown
			local glint = glintLook.glint
			if glint then
				glint.Enabled = shown
			end
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	flush(now)
	if now >= readoutAt and folder then
		readoutAt = now + 1
		folder:SetAttribute("Detail", math.floor(detail * 100 + 0.5) / 100)
		folder:SetAttribute("Built", builtCount)
		folder:SetAttribute("Drawn", drawnCount)
	end
	drawnCount = 0
end

-- The server says a fish turned on a player (AggroService): it darts at them.
local function onPreyChase(index: number, targetUserId: number, startAt: number, seconds: number)
	local visual = visuals[index]
	local target = Players:GetPlayerByUserId(targetUserId)
	if visual == nil or target == nil or visual.hidden then
		return
	end
	if visual.chase then
		visual.chase.glow:Destroy()
	end
	local glow = Instance.new("Highlight")
	glow.Name = "ChaseGlow"
	glow.FillColor = Ui.color.danger
	glow.FillTransparency = 0.9
	glow.OutlineColor = Ui.color.danger
	glow.OutlineTransparency = 0.2
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Adornee = visual.body
	glow.Parent = visual.body
	visual.chase = { target = target, startAt = startAt, endsAt = startAt + seconds, glow = glow }
	visual.holdUntil = 0
	if target == Players.LocalPlayer and chaseWarning then
		local prey = Config.Prey.byId[Schools.fish[index].prey]
		chaseWarning.Text = `{string.upper(prey.name)} · TOO BIG TO EAT · SWIM!`
		Sfx.play("TooBig", { volume = 0.5 })
		chaseWarningUntil = Timing.clock() + aggro.lungeAt + 0.4
	end
end

-- The server says a fish was eaten (by anyone) and when it comes back.
local function onPreyEaten(index: number, backAt: number, eaterUserId: number)
	if typeof(index) ~= "number" or Schools.fish[index] == nil or typeof(backAt) ~= "number" then
		return
	end
	backAts[index] = backAt -- (kept for a school built later)
	local visual = visuals[index]
	if visual == nil then
		return
	end
	visual.backAt = backAt
	visual.pendingUntil = 0
	if eaterUserId == Players.LocalPlayer.UserId then
		local length = Schools.fish[index].length
		Sfx.play("Chomp", {
			volume = math.clamp(0.25 + length * 0.04, 0.25, 0.7),
			pitch = math.clamp(1.5 - length * 0.08, 0.7, 1.5),
		})
	end
	if eaterUserId ~= Players.LocalPlayer.UserId and visual.suckFrom == nil then
		setHidden(visual, true)
	end
end

-- How far this client draws (×, DETAIL_MIN..1): eased in while its frames run slow
function SchoolController.detail(): number
	return detail
end

function SchoolController.start()
	local made = Instance.new("Folder")
	made.Name = "Prey"
	made.Parent = workspace
	folder = made -- (each school's fish are built as it comes near: step)
	for _, fish in Schools.fish do
		biggestRadius = math.max(biggestRadius, fish.radius)
	end
	-- The few faint lights the nearest glowing fish carry (GLOWS `light`)
	for _ = 1, GLOW_LIGHTS do
		local anchor = Instance.new("Part")
		anchor.Name = "GlowLight"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CastShadow = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.2
		local light = Instance.new("PointLight")
		light.Range = GLOW_LIGHT_RANGE
		light.Brightness = GLOW_LIGHT_BRIGHTNESS
		light.Shadows = false
		light.Enabled = false
		light.Parent = anchor
		anchor.Parent = made
		table.insert(glowLights, { part = anchor :: BasePart, light = light, index = 0 })
	end
	-- The schools' lifts over the rocks and reefs, as the server worked them out
	-- (Schools.settle), so we draw every fish where the server checks it
	local function loadLifts()
		local lifts = workspace:GetAttribute("SchoolLifts")
		Schools.load(if typeof(lifts) == "string" then lifts else nil)
	end
	loadLifts()
	workspace:GetAttributeChangedSignal("SchoolLifts"):Connect(loadLifts)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local preyEaten = remotes:WaitForChild("PreyEaten") :: RemoteEvent
	preyEaten.OnClientEvent:Connect(onPreyEaten)
	local preyChase = remotes:WaitForChild("PreyChase") :: RemoteEvent
	preyChase.OnClientEvent:Connect(onPreyChase)
	local preyRarity = remotes:WaitForChild("PreyRarity") :: RemoteEvent
	preyRarity.OnClientEvent:Connect(onRarity)
	-- The fish that were already rare when we joined
	local getRarities = remotes:WaitForChild("GetRarities") :: RemoteFunction
	task.spawn(function()
		local ok, known = pcall(function()
			return getRarities:InvokeServer()
		end)
		if ok and typeof(known) == "table" then
			local indices, codes = {}, {}
			for key, code in known do
				local index = tonumber(key)
				if index and typeof(code) == "number" then
					table.insert(indices, index)
					table.insert(codes, code)
				end
			end
			onRarity(indices, codes)
		end
	end)
	-- The warning when one turns on us
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Ui.screen("Chase", playerGui, 6)
	local label = Ui.label(
		gui,
		"Warning",
		"",
		Ui.FONT_HEAVY,
		18,
		Ui.color.danger,
		UDim2.new(1, 0, 0, 26),
		UDim2.new(0, 0, 0.5, -90)
	)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextStrokeTransparency = 0.4
	label.Visible = false
	chaseWarning = label
	RunService.RenderStepped:Connect(function()
		label.Visible = chaseWarningUntil > Timing.clock()
	end)
	-- Fish already eaten when we joined
	local getEaten = remotes:WaitForChild("GetEaten") :: RemoteFunction
	task.spawn(function()
		local ok, eaten = pcall(function()
			return getEaten:InvokeServer()
		end)
		if ok and typeof(eaten) == "table" then
			for key, backAt in eaten do
				local index = tonumber(key)
				if index and typeof(backAt) == "number" then
					onPreyEaten(index, backAt, 0)
				end
			end
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return SchoolController
