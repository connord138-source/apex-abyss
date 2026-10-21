--!strict
-- The AI predators and world bosses on this client (Config/Predators, Config/Bosses,
-- PredatorService). The server streams their positions ten times a second over an
-- unreliable remote; this controller keeps a short history per creature and draws
-- each one a little behind the stream, so they glide instead of stepping. Events
-- (PredatorEvent) carry the moments: a windup (the jaw flashes, and a warning if
-- it's coming for us), a bite (bubbles), a hurt (a flash, a damage pop for our own
-- bites), a death (a fade), and the bosses' tells: a charge, a tail sweep, a mark,
-- a stagger, a blood cloud, a breach and its shockwave.
--
-- A rigged body is animated from how it moves and the tells it shows (owner,
-- 2026-10-19: "His mouth doesn't move and his actual movements are very stiff ...
-- Needs to be fun to fight them not robotic"), with nothing more on the stream: tail
-- beats that follow its speed and thrust (strong strokes, a trailing glide), a C-bend
-- into turns and an arch through climbs, a bank (a boss rolls its belly out on a hard
-- one), a hunter's head eyeing its fish, pectoral fins (FinL/FinR) that flare in a
-- tell and tuck in a charge, and the jaw (rig_fish.py --jaw): a little open as it
-- cruises (sharks breathe that way), a gape that builds through a bite's tell, a snap
-- shut on the bite with a head shake when it lands, a wide mouth through a charge or
-- breach, chomps in the Megalodon's frenzy. The Giant Squid's arms writhe, curl up to
-- reach in a grab's tell and stream straight behind a jet.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Spring = require(script.Parent.Parent.Spring)
local PredatorsConfig = require(ReplicatedStorage.Shared.Config.Predators)
local Signal = require(ReplicatedStorage.Shared.Signal)
local SwimWave = require(ReplicatedStorage.Shared.SwimWave)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Ui = require(script.Parent.Parent.Ui)
local Sfx = require(script.Parent.Parent.Sfx)
local CameraController = require(script.Parent.CameraController)
local OceanController = require(script.Parent.OceanController)
local StartController = require(script.Parent.StartController)
local SwimController = require(script.Parent.SwimController)

-- A creature's body radius as a share of its length, for biting it and for bumping
-- into a boss
local BODY_RADIUS = 0.18

-- Each rig's jaw, radians past the model's own pose (+ opens; Tripo models a mouth a
-- little open): as it cruises, the full gape of a tell, and snapped shut
-- `throw` (× its length): how far its jaws shoot forward at the end of a tell
type JawRange = { cruise: number, wide: number, shut: number, throw: number? }
local JAW: { [string]: JawRange } = {
	Megalodon = { cruise = -0.05, wide = 0.5, shut = -0.2 },
	ReefShark = { cruise = 0.07, wide = 0.36, shut = -0.08 },
	Barracuda = { cruise = 0.03, wide = 0.42, shut = -0.12 },
	SeaLion = { cruise = 0.04, wide = 0.35, shut = -0.08 },
	GoliathGrouper = { cruise = 0.1, wide = 0.55, shut = -0.05 }, -- (a gulp: the widest mouth)
	GiantTrevally = { cruise = 0.05, wide = 0.38, shut = -0.08 },
	MakoShark = { cruise = 0.08, wide = 0.42, shut = -0.1 },
	SixgillShark = { cruise = 0.06, wide = 0.45, shut = -0.1 },
	WolfEel = { cruise = 0.05, wide = 0.5, shut = -0.1 },
	GoblinShark = { cruise = 0.05, wide = 0.7, shut = -0.1, throw = 0.1 }, -- (the jaw throw)
	BlackDragonfish = { cruise = 0.1, wide = 0.65, shut = -0.05 },
	default = { cruise = 0.05, wide = 0.4, shut = -0.1 },
}

-- A rigged model is drawn centred on its box; where its box isn't centred on its
-- body this moves it back (× its length: the Black Dragonfish's chin barbel hangs
-- far under it, so its box sits ~0.21 of its length under its body)
local DRAW_SHIFT: { [string]: number } = {
	BlackDragonfish = -0.21,
}

-- The part-built body until a predator's model is imported (Config/Predators
-- `model`), from each model's own proportions: its body (`w`, `h` × its length),
-- tail (× its length) and tail colour, and the pieces that make it read (head, jaw,
-- fins, snout, eyes, a lure), each sized and placed × its length (forward is -Z),
-- turned `rot` degrees. `rig` pieces go on the imported model too (a lure's glow, a
-- Sixgill's eye glow).
type Piece = {
	shape: string, -- "ball" | "block" | "wedge"
	size: Vector3,
	at: Vector3,
	rot: Vector3?,
	color: string?, -- "back" | "belly" | "dark" | "eye" | "white" | "glow" (default back)
	glow: Color3?, -- a Neon piece in this colour (and `light` gives it a PointLight)
	light: number?, -- the light's range × its length
	rig: boolean?,
	jaw: boolean?, -- a jaw that's thrown forward with the Goblin Shark's (JawRange `throw`)
}
type StandIn = { w: number, h: number, tail: Vector3, tailColor: Color3?, pieces: { Piece } }
local CYAN = Color3.fromRGB(90, 230, 255)
local STAND_INS: { [string]: StandIn } = {
	SeaLion = {
		w = 0.25,
		h = 0.26,
		tail = Vector3.new(0.26, 0.025, 0.14), -- (its hind flippers, flat)
		pieces = {
			{ shape = "ball", size = Vector3.new(0.2, 0.2, 0.24), at = Vector3.new(0, 0.04, -0.42) },
			{
				shape = "ball",
				size = Vector3.new(0.1, 0.08, 0.1),
				at = Vector3.new(0, 0, -0.54),
				color = "belly",
			},
			{ shape = "ball", size = Vector3.one * 0.04, at = Vector3.new(0.08, 0.08, -0.47), color = "eye" },
			{
				shape = "ball",
				size = Vector3.one * 0.04,
				at = Vector3.new(-0.08, 0.08, -0.47),
				color = "eye",
			},
			{
				shape = "block",
				size = Vector3.new(0.34, 0.025, 0.12),
				at = Vector3.new(0.2, -0.07, -0.16),
				rot = Vector3.new(0, -15, -25),
			},
			{
				shape = "block",
				size = Vector3.new(0.34, 0.025, 0.12),
				at = Vector3.new(-0.2, -0.07, -0.16),
				rot = Vector3.new(0, 15, 25),
			},
		},
	},
	GoliathGrouper = {
		w = 0.42,
		h = 0.5,
		tail = Vector3.new(0.04, 0.34, 0.16),
		pieces = {
			{
				shape = "ball",
				size = Vector3.new(0.28, 0.22, 0.08),
				at = Vector3.new(0, -0.03, -0.42),
				color = "dark",
			},
			{ shape = "wedge", size = Vector3.new(0.03, 0.14, 0.42), at = Vector3.new(0, 0.28, 0.05) },
			{
				shape = "block",
				size = Vector3.new(0.16, 0.02, 0.1),
				at = Vector3.new(0.21, -0.06, -0.14),
				rot = Vector3.new(0, 0, -20),
			},
			{
				shape = "block",
				size = Vector3.new(0.16, 0.02, 0.1),
				at = Vector3.new(-0.21, -0.06, -0.14),
				rot = Vector3.new(0, 0, 20),
			},
			{ shape = "ball", size = Vector3.one * 0.045, at = Vector3.new(0.15, 0.1, -0.33), color = "eye" },
			{
				shape = "ball",
				size = Vector3.one * 0.045,
				at = Vector3.new(-0.15, 0.1, -0.33),
				color = "eye",
			},
		},
	},
	GiantTrevally = {
		w = 0.2,
		h = 0.52,
		tail = Vector3.new(0.03, 0.44, 0.18),
		tailColor = Color3.fromRGB(206, 186, 92),
		pieces = {
			{ shape = "ball", size = Vector3.new(0.17, 0.44, 0.22), at = Vector3.new(0, 0.02, -0.32) },
			{ shape = "wedge", size = Vector3.new(0.02, 0.15, 0.3), at = Vector3.new(0, 0.28, 0.06) },
			{ shape = "ball", size = Vector3.one * 0.05, at = Vector3.new(0.07, 0.07, -0.38), color = "eye" },
			{
				shape = "ball",
				size = Vector3.one * 0.05,
				at = Vector3.new(-0.07, 0.07, -0.38),
				color = "eye",
			},
		},
	},
	MakoShark = {
		w = 0.2,
		h = 0.22,
		tail = Vector3.new(0.03, 0.44, 0.14),
		pieces = {
			{ shape = "ball", size = Vector3.new(0.12, 0.1, 0.24), at = Vector3.new(0, 0, -0.46) },
			{ shape = "wedge", size = Vector3.new(0.03, 0.22, 0.16), at = Vector3.new(0, 0.19, -0.02) },
			{
				shape = "block",
				size = Vector3.new(0.32, 0.02, 0.12),
				at = Vector3.new(0.17, -0.07, -0.12),
				rot = Vector3.new(0, -20, -15),
			},
			{
				shape = "block",
				size = Vector3.new(0.32, 0.02, 0.12),
				at = Vector3.new(-0.17, -0.07, -0.12),
				rot = Vector3.new(0, 20, 15),
			},
			{
				shape = "ball",
				size = Vector3.one * 0.035,
				at = Vector3.new(0.07, 0.04, -0.38),
				color = "eye",
			},
			{
				shape = "ball",
				size = Vector3.one * 0.035,
				at = Vector3.new(-0.07, 0.04, -0.38),
				color = "eye",
			},
		},
	},
	SixgillShark = {
		w = 0.26,
		h = 0.24,
		tail = Vector3.new(0.03, 0.28, 0.2),
		pieces = {
			{ shape = "ball", size = Vector3.new(0.24, 0.18, 0.26), at = Vector3.new(0, 0, -0.36) },
			{ shape = "wedge", size = Vector3.new(0.03, 0.12, 0.14), at = Vector3.new(0, 0.15, 0.22) },
			{
				shape = "block",
				size = Vector3.new(0.3, 0.02, 0.12),
				at = Vector3.new(0.16, -0.08, -0.14),
				rot = Vector3.new(0, -15, -15),
			},
			{
				shape = "block",
				size = Vector3.new(0.3, 0.02, 0.12),
				at = Vector3.new(-0.16, -0.08, -0.14),
				rot = Vector3.new(0, 15, 15),
			},
			{
				shape = "ball",
				size = Vector3.one * 0.045,
				at = Vector3.new(0.11, 0.05, -0.43),
				glow = Color3.fromRGB(110, 255, 140),
			},
			{
				shape = "ball",
				size = Vector3.one * 0.045,
				at = Vector3.new(-0.11, 0.05, -0.43),
				glow = Color3.fromRGB(110, 255, 140),
				light = 0.5,
			},
		},
	},
	WolfEel = {
		w = 0.15,
		h = 0.17,
		tail = Vector3.new(0.02, 0.13, 0.16),
		pieces = {
			{ shape = "ball", size = Vector3.new(0.18, 0.18, 0.2), at = Vector3.new(0, 0.01, -0.4) },
			{
				shape = "ball",
				size = Vector3.new(0.15, 0.06, 0.12),
				at = Vector3.new(0, -0.07, -0.46),
				color = "dark",
			},
			{ shape = "block", size = Vector3.new(0.02, 0.05, 0.7), at = Vector3.new(0, 0.09, 0.05) },
			{
				shape = "ball",
				size = Vector3.one * 0.032,
				at = Vector3.new(0.075, 0.07, -0.44),
				color = "eye",
			},
			{
				shape = "ball",
				size = Vector3.one * 0.032,
				at = Vector3.new(-0.075, 0.07, -0.44),
				color = "eye",
			},
			{
				shape = "ball",
				size = Vector3.one * 0.045,
				at = Vector3.new(0.07, 0.02, -0.18),
				color = "dark",
			},
			{
				shape = "ball",
				size = Vector3.one * 0.045,
				at = Vector3.new(-0.07, 0.03, 0.02),
				color = "dark",
			},
			{
				shape = "ball",
				size = Vector3.one * 0.045,
				at = Vector3.new(0.065, -0.01, 0.2),
				color = "dark",
			},
		},
	},
	GoblinShark = {
		w = 0.17,
		h = 0.19,
		tail = Vector3.new(0.03, 0.3, 0.2),
		pieces = {
			{
				shape = "block",
				size = Vector3.new(0.07, 0.02, 0.34),
				at = Vector3.new(0, 0.04, -0.6),
				color = "belly",
			},
			{
				shape = "wedge",
				size = Vector3.new(0.12, 0.06, 0.13),
				at = Vector3.new(0, -0.08, -0.36),
				rot = Vector3.new(180, 0, 0),
				color = "dark",
				jaw = true,
			},
			{ shape = "wedge", size = Vector3.new(0.025, 0.12, 0.14), at = Vector3.new(0, 0.15, 0.05) },
			{
				shape = "block",
				size = Vector3.new(0.26, 0.02, 0.1),
				at = Vector3.new(0.13, -0.07, -0.1),
				rot = Vector3.new(0, -15, -15),
			},
			{
				shape = "block",
				size = Vector3.new(0.26, 0.02, 0.1),
				at = Vector3.new(-0.13, -0.07, -0.1),
				rot = Vector3.new(0, 15, 15),
			},
			{ shape = "ball", size = Vector3.one * 0.03, at = Vector3.new(0.06, 0.05, -0.38), color = "eye" },
			{
				shape = "ball",
				size = Vector3.one * 0.03,
				at = Vector3.new(-0.06, 0.05, -0.38),
				color = "eye",
			},
		},
	},
	BlackDragonfish = {
		w = 0.1,
		h = 0.15,
		tail = Vector3.new(0.02, 0.17, 0.14),
		pieces = {
			{ shape = "ball", size = Vector3.new(0.11, 0.15, 0.16), at = Vector3.new(0, 0.01, -0.38) },
			{
				shape = "wedge",
				size = Vector3.new(0.012, 0.05, 0.02),
				at = Vector3.new(0.03, -0.05, -0.45),
				color = "white",
			},
			{
				shape = "wedge",
				size = Vector3.new(0.012, 0.05, 0.02),
				at = Vector3.new(-0.03, -0.05, -0.45),
				color = "white",
			},
			{
				shape = "block",
				size = Vector3.new(0.012, 0.42, 0.012),
				at = Vector3.new(0, -0.27, -0.38),
				color = "dark",
			},
			{ shape = "ball", size = Vector3.one * 0.03, at = Vector3.new(0.05, 0.04, -0.42), glow = CYAN },
			{ shape = "ball", size = Vector3.one * 0.03, at = Vector3.new(-0.05, 0.04, -0.42), glow = CYAN },
			{ shape = "ball", size = Vector3.one * 0.02, at = Vector3.new(0.052, -0.03, -0.2), glow = CYAN },
			{ shape = "ball", size = Vector3.one * 0.02, at = Vector3.new(0.052, -0.03, -0.05), glow = CYAN },
			{ shape = "ball", size = Vector3.one * 0.02, at = Vector3.new(0.052, -0.03, 0.1), glow = CYAN },
			{ shape = "ball", size = Vector3.one * 0.02, at = Vector3.new(-0.052, -0.03, -0.2), glow = CYAN },
			{
				shape = "ball",
				size = Vector3.one * 0.02,
				at = Vector3.new(-0.052, -0.03, -0.05),
				glow = CYAN,
			},
			{ shape = "ball", size = Vector3.one * 0.02, at = Vector3.new(-0.052, -0.03, 0.1), glow = CYAN },
			-- The lure, the barbel's glowing tip (on the imported model too)
			{
				shape = "ball",
				size = Vector3.one * 0.06,
				at = Vector3.new(0, -0.5, -0.38),
				glow = CYAN,
				light = 1.4,
				rig = true,
			},
		},
	},
}
local TAU = 2 * math.pi

-- A boss's own light in the pitch dark (OceanController.darkness): bioluminescent
-- violet for the squid, a cold blue otherwise
local DARK_GLOW: { [string]: Color3 } = {
	GiantSquid = Color3.fromRGB(130, 90, 255),
	default = Color3.fromRGB(90, 160, 255),
}

local Predators = Config.Predators
local Bosses = Config.Bosses

-- How each boss shows itself (Config/Bosses `sight`), by its creature's id
local SIGHT: { [string]: { far: number?, near: number?, light: number } } = {}
for _, boss in Bosses.list do
	SIGHT[boss.predator.id] = boss.sight
end
-- The rim that keeps a boss readable in a fight (owner, 2026-10-09: "once he is upon
-- them he needs to be seeable to be fightable")
local FIGHT_RIM = Color3.fromRGB(190, 225, 255)

type Def = PredatorsConfig.PredatorDef

local PredatorController = {
	-- (damage, position) — our bite landed on a predator (HUD pops the number)
	hit = Signal.new(),
	-- (kind, index, payload) — every predator event, for the boss HUD
	event = Signal.new(),
}

local HISTORY = 8 -- stream samples kept per creature
-- Static prey meshes (PreyModels) came in facing +Z (owner, 2026-10-07: "swimming
-- backwards"); they're turned round when drawn. Rigged FBX bodies face -Z already.
local MESH_FLIP = CFrame.Angles(0, math.pi, 0)
local EXTRAPOLATE = 0.25 -- seconds we keep moving past the last sample
local FADE_SECONDS = 0.7
-- A creature the stream stops sending (it swam out of range, or we did: the server
-- sends each player only the creatures near their fish) fades out after this long
local STALE = 1.5
local TAG_DISTANCE = 240

type Sample = {
	at: number,
	position: Vector3,
	heading: Vector3,
}

type Motion = {
	last: Vector3, -- where it was drawn last frame
	velocity: Vector3, -- smoothed from the drawn motion
	speed: number,
	thrust: number, -- smoothed change of speed ÷ its top speed a second (+ strokes, - glide)
	amplitude: number,
	bend: number,
	bendVelocity: number,
	arch: number,
	archVelocity: number,
	look: number, -- the head's turn toward its fish
	gape: number, -- the jaw, radians past the model's pose
	gapeVelocity: number,
	fins: number, -- the pectorals' droop (radians, tips down)
	finsVelocity: number,
	windupFrom: number, -- when the current bite tell began
	snapUntil: number, -- jaw shut (a bite, a charge's end, a breach's crash)
	shakeUntil: number, -- a head shake: the bite landed
	rushUntil: number, -- a charge, lunge or burst under way (mouth wide, fins tucked)
	rocketUntil: number, -- a breach's rocket (mouth wide, hard strokes)
	crashUntil: number, -- a breach's crash (rolls onto its side)
	jetUntil: number, -- a squid's jet (arms streaming straight)
	reachUntil: number, -- a squid's grab tell (arms curling up to reach)
	nextChomp: number, -- the Megalodon's frenzy chomps
	jawRange: JawRange,
	throw: number, -- the jaws shot forward (studs)
	throwVelocity: number,
}

type Visual = {
	index: number,
	def: Def,
	boss: boolean,
	model: Model?, -- a rigged boss body (its MeshPart is `body`)
	bones: { [string]: Bone },
	spine: { string },
	body: BasePart,
	tail: BasePart?,
	flip: boolean, -- a static mesh that came in facing +Z
	bodySize: Vector3,
	tailSize: Vector3,
	samples: { Sample },
	heardAt: number, -- the server clock of the last stream entry or spawn heard for it
	position: Vector3, -- where it's drawn this frame
	heading: Vector3,
	mode: string,
	health: number, -- 0..1
	meter: number, -- a boss's stagger meter, 0..1
	target: number, -- userId it's hunting (0 = none)
	hidden: boolean,
	gone: boolean, -- destroyed once it has faded
	fade: number, -- 0 hidden .. 1 shown, eased
	phase: number, -- the swim wave
	windupUntil: number,
	tellUntil: number, -- a charge or sweep tell (eyes flash, yellow)
	flashUntil: number,
	markedUntil: number,
	staggerUntil: number,
	bloodUntil: number,
	grabs: { [number]: number }, -- a squid's held fish: userId → when the grab times out
	presence: number, -- 0..1: how far a boss has faded in out of the water (Config/Bosses `sight`)
	shown: number, -- the opacity last applied to the body
	roll: number, -- banked into its turn (radians; right side down is negative)
	rollVelocity: number,
	motion: Motion, -- a rigged body's animation (read off its motion and tells)
	jaw: Highlight,
	glow: PointLight,
	blood: ParticleEmitter?,
	tag: BillboardGui,
	healthFill: Frame,
	status: TextLabel,
	levelLine: TextLabel?, -- LV n · STRONGER / WEAKER / EVEN FIGHT (not on a boss)
	level: number, -- its group's level (streamed; 0 = none)
	extras: { Extra }, -- a stand-in's pieces, a model's `rig` pieces, a gulper's suction
	lights: { { light: PointLight, brightness: number } }, -- the pieces' own lights
	lure: PointLight?, -- a dragonfish's lure
	suction: ParticleEmitter?, -- a gulper's pull, streaming into its mouth through a tell
	drawShift: number, -- studs a rigged body's mesh is moved up or down (DRAW_SHIFT)
}

-- A piece drawn with the body: at the body's frame × `offset`; a `jaw` piece is
-- thrown forward with the jaws, a `hidden` one (an emitter's holder) never shows
type Extra = { part: BasePart, offset: CFrame, jaw: boolean, hidden: boolean }

local visuals: { [number]: Visual } = {}
local parts: { BasePart } = {}
local frames: { CFrame } = {}
local folder: Folder
local warning: TextLabel
local warningUntil = 0
-- A squid's tentacle beams (userId → the part) and its ink clouds
local beams: { [number]: Part } = {}
local inks: { { center: Vector3, radius: number, endsAt: number } } = {}

local function dropBeam(userId: number)
	local beam = beams[userId]
	if beam then
		beam:Destroy()
		beams[userId] = nil
	end
end

-- A tentacle from the beak to a held fish, redrawn every frame while the grab holds
local function drawBeam(userId: number, from: Vector3, to: Vector3)
	local beam = beams[userId]
	if not beam then
		local made = Instance.new("Part")
		made.Name = "Tentacle"
		made.Anchored = true
		made.CanCollide = false
		made.CanQuery = false
		made.CanTouch = false
		made.CastShadow = false
		made.Shape = Enum.PartType.Cylinder
		made.Material = Enum.Material.SmoothPlastic
		made.Color = Color3.fromRGB(120, 40, 80)
		made.Parent = folder
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 170, 80)
		light.Brightness = 1.2
		light.Range = 14
		light.Parent = made
		beams[userId] = made
		beam = made
	end
	local part = beam :: Part
	local span = to - from
	local length = math.max(span.Magnitude, 1)
	local mid = (from + to) / 2
	part.Size = Vector3.new(length, 1.6, 1.6)
	part.CFrame = CFrame.lookAt(mid, to) * CFrame.Angles(0, math.rad(90), 0)
end

-- A burst of dark ink that hangs in the water, and lingers in the blind list
local function inkCloud(center: Vector3, radius: number, seconds: number)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(center)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(seconds * 0.8, seconds * 1.1)
	emitter.Speed = NumberRange.new(radius * 0.08, radius * 0.25)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 1.5
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, radius * 0.25),
		NumberSequenceKeypoint.new(0.3, radius * 0.7),
		NumberSequenceKeypoint.new(1, radius * 0.9),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.7, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(Color3.fromRGB(18, 10, 24), Color3.fromRGB(30, 16, 40))
	emitter.LightInfluence = 0
	emitter.Parent = holder
	holder.Parent = workspace
	emitter:Emit(90)
	table.insert(inks, { center = center, radius = radius, endsAt = Timing.clock() + seconds })
	task.delay(seconds * 1.2, function()
		holder:Destroy()
	end)
end

-- A whirlpool: bubbles racing round the center for its duration
local function whirlCloud(center: Vector3, radius: number, seconds: number)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(radius * 1.6, radius * 0.6, radius * 1.6)
	holder.CFrame = CFrame.new(center)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Shape = Enum.ParticleEmitterShape.Cylinder
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.Rate = 160
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(radius * 0.5, radius * 0.9)
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	emitter.Drag = 0.5
	emitter.Size = NumberSequence.new(1.2, 0.3)
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.LightEmission = 0.4
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 240, 255))
	emitter.Parent = holder
	holder.Parent = workspace
	task.delay(seconds, function()
		emitter.Enabled = false
		task.wait(1.5)
		holder:Destroy()
	end)
end

local function makePart(parent: Instance, color: Color3): Part
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
	return part
end

-- The imported prey mesh (docs/ASSETS.md): ReplicatedStorage.PreyModels.<model>, a
-- MeshPart facing -Z. Nil while it isn't imported (parts are drawn instead).
local function preyTemplate(name: string): MeshPart?
	local models = ReplicatedStorage:FindFirstChild("PreyModels")
	local found = models and models:FindFirstChild(name)
	if found and found:IsA("MeshPart") then
		return found
	end
	if found and found:IsA("Model") then
		return found:FindFirstChildWhichIsA("MeshPart", true)
	end
	return nil
end

-- A rigged body (a Model holding a skinned MeshPart with bones): FishModels.<model>
-- for the bosses, PreyModels.<model> for a predator whose prey model is rigged
local function riggedTemplate(name: string, folderName: string): Model?
	local models = ReplicatedStorage:FindFirstChild(folderName)
	local found = models and models:FindFirstChild(name)
	if
		found
		and found:IsA("Model")
		and found:FindFirstChildWhichIsA("MeshPart", true)
		and found:FindFirstChildWhichIsA("Bone", true)
	then
		return found
	end
	return nil
end

local function defOf(id: string): (Def?, boolean)
	local boss = Bosses.byId[id]
	if boss then
		return boss.predator, true
	end
	return Predators.byId[id], false
end

local function makeTag(visual: Visual)
	local def = visual.def
	local gui = Instance.new("BillboardGui")
	gui.Name = "PredatorTag"
	-- (a plain predator's tag has its level line under its name, like a player's)
	local levelled = not visual.boss
	local below = if levelled then 16 else 0
	gui.Size = if visual.boss then UDim2.fromOffset(320, 56) else UDim2.fromOffset(220, 46 + below)
	gui.StudsOffsetWorldSpace = Vector3.new(0, def.length * (if visual.boss then 0.3 else 0.45) + 2, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = if visual.boss then 700 else TAG_DISTANCE
	gui.Adornee = visual.body
	local name = Ui.label(
		gui,
		"Name",
		`{def.tag or "PREDATOR"} · {string.upper(def.name)}`,
		Ui.FONT_HEAVY,
		if visual.boss then 20 else 15,
		Ui.color.danger
	)
	name.Size = UDim2.new(1, 0, 0, if visual.boss then 26 else 20)
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextStrokeTransparency = 0.5
	local status = Ui.label(
		gui,
		"Status",
		"",
		Ui.FONT_SEMI,
		if visual.boss then 14 else 12,
		Ui.color.text,
		UDim2.new(1, 0, 0, 16),
		UDim2.fromOffset(0, if visual.boss then 26 else 20 + below)
	)
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.TextStrokeTransparency = 0.6
	if levelled then
		local line = Ui.label(
			gui,
			"Level",
			"",
			Ui.FONT_HEAVY,
			13,
			Ui.color.text,
			UDim2.new(1, 0, 0, 16),
			UDim2.fromOffset(0, 20)
		)
		line.TextXAlignment = Enum.TextXAlignment.Center
		line.TextStrokeTransparency = 0.5
		visual.levelLine = line
	end
	local _, fill = Ui.bar(
		gui,
		"Health",
		UDim2.new(0.6, 0, 0, 5),
		UDim2.new(0.2, 0, 0, if visual.boss then 46 else 38 + below),
		Ui.color.danger
	)
	fill.Size = UDim2.fromScale(1, 1)
	gui.Parent = visual.body
	visual.tag = gui
	visual.healthFill = fill
	visual.status = status
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

local function newMotion(def: Def): Motion
	local range = JAW[def.model] or JAW.default
	return {
		last = Vector3.new(0, -500, 0),
		velocity = Vector3.zero,
		speed = 0,
		thrust = 0,
		amplitude = 0.08,
		bend = 0,
		bendVelocity = 0,
		arch = 0,
		archVelocity = 0,
		look = 0,
		gape = range.cruise,
		gapeVelocity = 0,
		fins = 0,
		finsVelocity = 0,
		windupFrom = 0,
		snapUntil = 0,
		shakeUntil = 0,
		rushUntil = 0,
		rocketUntil = 0,
		crashUntil = 0,
		jetUntil = 0,
		reachUntil = 0,
		nextChomp = 0,
		jawRange = range,
		throw = 0,
		throwVelocity = 0,
	}
end

local function pieceColor(def: Def, name: string?): Color3
	if name == "belly" then
		return def.belly
	elseif name == "dark" then
		return def.back:Lerp(Color3.fromRGB(26, 22, 22), 0.6)
	elseif name == "eye" then
		return Color3.fromRGB(16, 16, 20)
	elseif name == "white" then
		return Color3.fromRGB(235, 235, 230)
	end
	return def.back
end

-- One piece of a stand-in (STAND_INS), sized to the creature: SmoothPlastic, or Neon
-- with a light for a glowing one
local function makePiece(parent: Instance, def: Def, piece: Piece): (BasePart, PointLight?)
	local length = def.length
	local part: BasePart
	if piece.shape == "ball" then
		part = makePart(parent, pieceColor(def, piece.color))
	else
		part = if piece.shape == "wedge" then Instance.new("WedgePart") else Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = pieceColor(def, piece.color)
		part.Parent = parent
	end
	part.Name = "Piece"
	part.Size = piece.size * length
	local light: PointLight? = nil
	if piece.glow then
		part.Material = Enum.Material.Neon
		part.Color = piece.glow
		if piece.light then
			local made = Instance.new("PointLight")
			made.Color = piece.glow
			made.Range = math.min(piece.light * length, 60)
			made.Brightness = 0
			made.Shadows = false
			made.Parent = part
			light = made
		end
	end
	return part, light
end

local function build(index: number, def: Def, boss: boolean): Visual
	local length = def.length
	local bodySize = Vector3.new(length * 0.2, length * 0.24, length * 0.8)
	local tailSize = Vector3.new(length * 0.03, length * 0.3, length * 0.26)
	local body: BasePart? = nil
	local tail: BasePart? = nil
	local model: Model? = nil
	local bones: { [string]: Bone } = {}
	local spine: { string } = {}
	local flip = false
	local rigged = riggedTemplate(def.model, if boss then "FishModels" else "PreyModels")
	do
		if rigged then
			local clone = rigged:Clone()
			clone.Name = def.id
			for _, descendant in clone:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
					descendant.CanCollide = false
					descendant.CanQuery = false
					descendant.CanTouch = false
				end
			end
			clone:ScaleTo(1)
			local extents = clone:GetExtentsSize()
			clone:ScaleTo(length / math.max(extents.Z, 0.01))
			clone:PivotTo(CFrame.new())
			local box = clone:GetBoundingBox()
			clone:PivotTo(CFrame.new(-box.Position))
			local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("MeshPart", true)
			if primary then
				clone.PrimaryPart = primary
				bodySize = clone:GetExtentsSize()
				bones, spine = bonesOf(clone)
				clone.Parent = folder
				model = clone
				body = primary
			else
				clone:Destroy()
			end
		end
	end
	if body == nil then
		local mesh = preyTemplate(def.model)
		if mesh then
			local clone = mesh:Clone()
			clone.Anchored = true
			clone.CanCollide = false
			clone.CanQuery = false
			clone.CanTouch = false
			clone.CastShadow = false
			bodySize = mesh.Size * (length / math.max(mesh.Size.Z, 0.01))
			clone.Size = bodySize
			clone.Parent = folder
			body = clone
			flip = SwimWave.needsFlip(mesh)
		else
			-- (a predator's own shape until its model is in: STAND_INS)
			local shape = if boss then nil else STAND_INS[def.model]
			if shape then
				bodySize = Vector3.new(length * shape.w, length * shape.h, length * 0.8)
				tailSize = shape.tail * length
			end
			local made = makePart(folder, def.back)
			made.Size = bodySize
			local fin = makePart(
				folder,
				if shape and shape.tailColor then shape.tailColor else def.back:Lerp(def.belly, 0.3)
			)
			fin.Name = "Tail"
			fin.Size = tailSize
			tail = fin
			body = made
		end
	end
	local part = body :: BasePart
	-- Its pieces: every one on a stand-in, the `rig` ones (a lure) on a model; a
	-- gulper's suction stream ahead of its mouth
	local extras: { Extra } = {}
	local lights: { { light: PointLight, brightness: number } } = {}
	local lure: PointLight? = nil
	local shape = if boss then nil else STAND_INS[def.model]
	local standing = tail ~= nil
	if shape then
		for _, piece in shape.pieces do
			if not standing and not piece.rig then
				continue
			end
			local made, light = makePiece(model or part, def, piece)
			local turn = piece.rot or Vector3.zero
			table.insert(extras, {
				part = made,
				offset = CFrame.new(piece.at * length)
					* CFrame.Angles(math.rad(turn.X), math.rad(turn.Y), math.rad(turn.Z)),
				jaw = piece.jaw == true,
				hidden = false,
			})
			if light then
				local brightness = if piece.rig then 1.6 else 0.9
				table.insert(lights, { light = light, brightness = brightness })
				if piece.rig then
					lure = light
				end
			end
		end
	end
	local suction: ParticleEmitter? = nil
	local gulp = def.style and def.style.gulp
	if gulp then
		-- (water drawn in from up to its reach ahead, faster near the mouth)
		local holder = Instance.new("Part")
		holder.Name = "Suction"
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.CastShadow = false
		holder.Transparency = 1
		local reach = gulp.reach * 0.8
		holder.Size = Vector3.new(length * 0.35, length * 0.35, reach)
		holder.Parent = model or part
		local emitter = Instance.new("ParticleEmitter")
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter.EmissionDirection = Enum.NormalId.Back -- (toward the mouth)
		emitter.Rate = 70
		emitter.Speed = NumberRange.new(reach * 1.4, reach * 2)
		emitter.Lifetime = NumberRange.new(0.25, 0.55)
		emitter.Acceleration = Vector3.zero
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.3, 0.45),
			NumberSequenceKeypoint.new(1, 0.1),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.35),
			NumberSequenceKeypoint.new(1, 0.9),
		})
		emitter.LightEmission = 0.35
		emitter.Color = ColorSequence.new(Color3.fromRGB(215, 245, 255))
		emitter.Enabled = false
		emitter.Parent = holder
		suction = emitter
		table.insert(extras, {
			part = holder :: BasePart,
			offset = CFrame.new(0, 0, -(length * (def.mouth or 0.45) + reach * 0.5)),
			jaw = false,
			hidden = true,
		})
	end
	part.Name = def.id
	-- The jaw tell and hurt flash: a highlight that's off until needed
	local jaw = Instance.new("Highlight")
	jaw.Name = "Jaw"
	jaw.FillColor = Ui.color.danger
	jaw.FillTransparency = 1
	jaw.OutlineColor = Ui.color.danger
	jaw.OutlineTransparency = 1
	jaw.DepthMode = Enum.HighlightDepthMode.Occluded
	jaw.Adornee = model or part
	jaw.Parent = part
	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = Ui.color.danger
	glow.Brightness = 0
	glow.Range = length * 1.6
	glow.Shadows = false
	glow.Parent = part
	local visual: Visual = {
		index = index,
		def = def,
		boss = boss,
		model = model,
		bones = bones,
		spine = spine,
		body = part,
		tail = tail,
		flip = flip,
		bodySize = bodySize,
		tailSize = tailSize,
		samples = {},
		heardAt = 0,
		position = Vector3.new(0, -500, 0),
		heading = Vector3.new(1, 0, 0),
		mode = "dead",
		health = 1,
		meter = 0,
		target = 0,
		hidden = true,
		gone = false,
		fade = 0,
		phase = index * 1.7,
		windupUntil = 0,
		tellUntil = 0,
		flashUntil = 0,
		markedUntil = 0,
		staggerUntil = 0,
		bloodUntil = 0,
		grabs = {},
		-- A boss that fades in starts unseen, wherever it rises
		presence = if SIGHT[def.id] and SIGHT[def.id].far then 0 else 1,
		shown = 0,
		roll = 0,
		rollVelocity = 0,
		motion = newMotion(def),
		jaw = jaw,
		glow = glow,
		blood = nil,
		tag = nil :: any,
		healthFill = nil :: any,
		status = nil :: any,
		levelLine = nil,
		level = def.level or 0,
		extras = extras,
		lights = lights,
		lure = lure,
		suction = suction,
		drawShift = if model then (DRAW_SHIFT[def.model] or 0) * length else 0,
	}
	makeTag(visual)
	visual.tag.Enabled = false
	return visual
end

local function setTransparency(visual: Visual, transparency: number)
	if visual.model then
		for _, descendant in (visual.model :: Model):GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Transparency = transparency
			end
		end
	else
		visual.body.Transparency = transparency
	end
	if visual.tail then
		visual.tail.Transparency = transparency
	end
	for _, extra in visual.extras do
		extra.part.Transparency = if extra.hidden then 1 else transparency
	end
end

local function visualFor(index: number, id: string?): Visual?
	local existing = visuals[index]
	if existing then
		return existing
	end
	if id == nil then
		return nil
	end
	local def, boss = defOf(id)
	if def == nil then
		return nil
	end
	local made = build(index, def, boss)
	setTransparency(made, 1)
	visuals[index] = made
	return made
end

local function destroy(visual: Visual)
	visuals[visual.index] = nil
	for userId in visual.grabs do
		dropBeam(userId)
	end
	if visual.model then
		(visual.model :: Model):Destroy()
	else
		visual.body:Destroy()
	end
	if visual.tail then
		(visual.tail :: BasePart):Destroy()
	end
end

local function setHidden(visual: Visual, hidden: boolean)
	if visual.hidden == hidden then
		return
	end
	visual.hidden = hidden
	visual.tag.Enabled = not hidden
	if hidden then
		visual.windupUntil = 0
		visual.tellUntil = 0
		visual.markedUntil = 0
		visual.staggerUntil = 0
		visual.jaw.FillTransparency = 1
		visual.jaw.OutlineTransparency = 1
		visual.glow.Brightness = 0
		if visual.blood then
			(visual.blood :: ParticleEmitter).Enabled = false
		end
	end
end

local function bubbles(position: Vector3, size: number, color: Color3?)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Speed = NumberRange.new(size * 1.5, size * 4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, size * 2, 0)
	emitter.Drag = 3
	emitter.Size = NumberSequence.new(size * 0.12, size * 0.04)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.LightEmission = 0.5
	emitter.Color = ColorSequence.new(color or Color3.fromRGB(220, 250, 255))
	emitter.Parent = holder
	holder.Parent = workspace
	emitter:Emit(math.clamp(math.floor(size * 6), 8, 80))
	task.delay(2, function()
		holder:Destroy()
	end)
end

-- A breach's shockwave: a ring that races outward along the water and fades
local function shockwave(position: Vector3, radius: number)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(230, 250, 255)
	ring.Transparency = 0.2
	ring.Size = Vector3.new(4, 1, 4)
	ring.CFrame = CFrame.new(position)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Parent = ring
	-- A cylinder mesh lies along X; stand it up
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	Ui.tween(
		ring,
		0.9,
		{ Size = Vector3.new(2, radius * 2, radius * 2), Transparency = 1 },
		Enum.EasingStyle.Quad
	)
	bubbles(position, radius * 0.5)
	task.delay(1, function()
		ring:Destroy()
	end)
end

local function bloodCloud(visual: Visual, seconds: number)
	local length = visual.def.length
	local emitter = visual.blood
	if emitter == nil then
		local made = Instance.new("ParticleEmitter")
		made.Name = "Blood"
		made.Shape = Enum.ParticleEmitterShape.Sphere
		made.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		made.Rate = 40
		made.Lifetime = NumberRange.new(3, 5)
		made.Speed = NumberRange.new(1, 4)
		made.SpreadAngle = Vector2.new(180, 180)
		made.Drag = 1
		made.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, length * 0.15),
			NumberSequenceKeypoint.new(0.4, length * 0.5),
			NumberSequenceKeypoint.new(1, length * 0.7),
		})
		made.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.6, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		})
		made.Color = ColorSequence.new(Color3.fromRGB(96, 10, 18), Color3.fromRGB(40, 6, 12))
		made.LightInfluence = 0.2
		made.Parent = visual.body
		visual.blood = made
		emitter = made
	end
	local cloud = emitter :: ParticleEmitter
	cloud.Enabled = true
	visual.bloodUntil = Timing.clock() + seconds
	task.delay(seconds, function()
		if visual.bloodUntil <= Timing.clock() then
			cloud.Enabled = false
		end
	end)
end

-- Where the creature is at `t`, from its stream samples: between the two that
-- bracket it, or a little past the last one.
local function sampleAt(visual: Visual, t: number): (Vector3, Vector3)
	local samples = visual.samples
	local count = #samples
	if count == 0 then
		return visual.position, visual.heading
	end
	local last = samples[count]
	if count == 1 or t >= last.at then
		if count >= 2 and t > last.at then
			local previous = samples[count - 1]
			local span = last.at - previous.at
			if span > 1e-3 then
				local velocity = (last.position - previous.position) / span
				local ahead = math.min(t - last.at, EXTRAPOLATE)
				return last.position + velocity * ahead, last.heading
			end
		end
		return last.position, last.heading
	end
	for i = count - 1, 1, -1 do
		local a = samples[i]
		if t >= a.at then
			local b = samples[i + 1]
			local alpha = math.clamp((t - a.at) / math.max(b.at - a.at, 1e-3), 0, 1)
			local heading = a.heading:Lerp(b.heading, alpha)
			-- A curve through the samples (Catmull-Rom), not straight lines between
			-- them: a turning fish drew a polygon of 0.1 s chords (owner, 2026-10-13:
			-- "Their tracking should also be more fluid")
			local p1, p2 = a.position, b.position
			local p0 = if i > 1 then samples[i - 1].position else p1 * 2 - p2
			local p3 = if i + 2 <= count then samples[i + 2].position else p2 * 2 - p1
			local t2, t3 = alpha * alpha, alpha * alpha * alpha
			local position = (
				p1 * 2
				+ (p2 - p0) * alpha
				+ (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
				+ (p1 * 3 - p0 - p2 * 3 + p3) * t3
			) * 0.5
			return position, if heading.Magnitude > 1e-3 then heading.Unit else b.heading
		end
	end
	local first = samples[1]
	return first.position, first.heading
end

local function frameOf(position: Vector3, heading: Vector3): CFrame
	local up = if math.abs(heading.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt(position, position + heading, up)
end

local function speedOf(visual: Visual): number
	local samples = visual.samples
	local count = #samples
	if count < 2 then
		return 0
	end
	local a, b = samples[count - 1], samples[count]
	return (b.position - a.position).Magnitude / math.max(b.at - a.at, 1e-3)
end

-- Where its fish is, for a hunter's eye (nil when it has none, or isn't drawn here)
local function targetPosition(visual: Visual): Vector3?
	if visual.target == 0 then
		return nil
	end
	local player = Players:GetPlayerByUserId(visual.target)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- A rigged body comes alive, all of it read off how it moves and the tells it shows
-- (see the top): its tail beats, C-bend, arch, head, jaw and pectoral fins
local function animateRig(visual: Visual, dt: number, now: number, yawRate: number, pitchRate: number)
	local def = visual.def
	local motion = visual.motion
	local bones = visual.bones
	local bossDef = Bosses.byId[def.id]
	local squid = bossDef ~= nil and bossDef.kit == "squid"
	-- How it's moving: its speed, and its thrust (speeding up is a stroke, slowing a
	-- glide), smoothed off where it's drawn
	local step = math.max(dt, 1e-3)
	local moved = (visual.position - motion.last) / step
	motion.last = visual.position
	if moved.Magnitude > def.speed * 5 then
		moved = motion.velocity -- (a jet or a fresh life jumps it)
	end
	motion.velocity = motion.velocity:Lerp(moved, 1 - math.exp(-dt * 5))
	local speed = motion.velocity.Magnitude
	local change = (speed - motion.speed) / step
	motion.speed = speed
	motion.thrust += (math.clamp(change / math.max(def.speed, 1), -2, 3) - motion.thrust) * (1 - math.exp(
		-dt * 3
	))
	local relative = speed / math.max(def.speed, 1)
	local thrust = motion.thrust
	local rushing = motion.rushUntil > now or motion.rocketUntil > now
	local slack = visual.mode == "stunned" or visual.staggerUntil > now
	-- Tail beats: quicker and wider with speed, hardest as it drives on, the tail
	-- trailing through a glide; a big body beats slow and heavy (the Megalodon's
	-- strokes come about once a second as it cruises)
	local size = math.clamp((20 / def.length) ^ 0.35, 0.45, 1.3)
	local stroking = if rushing then 1 else math.clamp(0.4 + thrust * 1.6, 0, 1)
	local frequency = (
		0.45
		+ 1.1 * math.min(relative, 1.6)
		+ 0.8 * math.clamp(thrust, 0, 1.5)
		+ (if rushing then 0.5 else 0)
	) * size
	local amplitude = (0.05 + 0.13 * math.min(relative, 1.2) + 0.1 * math.clamp(thrust, 0, 1.5))
		* (0.4 + 0.6 * stroking)
	if slack then
		amplitude *= 0.4
		frequency *= 0.5
	end
	-- (a squid's mantle pulse, read off its thrust: the arms close and trail straight
	-- as it jets, then spread and drift on the glide)
	local pulse = if squid then math.clamp(thrust * 1.5, 0, 1) else 0
	local drift = if squid then math.clamp(-thrust * 2, 0, 1) else 0
	if squid then
		-- Its arms never quite still; streamed straight behind a jet
		amplitude = if motion.jetUntil > now then 0.02 else math.max(amplitude, 0.1) * (1 - 0.55 * pulse)
	end
	motion.amplitude += (amplitude - motion.amplitude) * (1 - math.exp(-dt * 3))
	visual.phase += TAU * frequency * dt
	-- A C-bend into a turn (deep in a burst-turn) and an arch through a climb or dive:
	-- the body follows its own path, concave toward the turn, the tail swinging in
	-- behind (yawRate is + turning left, and SwimWave's + bend swings the tail right,
	-- so it's negated; the same for the arch). Bend is per joint and the joints add
	-- up: 0.2 curls a Megalodon ~1 radian nose to tail.
	motion.bend, motion.bendVelocity =
		Spring.number(motion.bend, motion.bendVelocity, math.clamp(-yawRate * 0.1, -0.2, 0.2), 7, dt)
	local arch = math.clamp(-pitchRate * 0.08, -0.08, 0.08)
	if squid then
		-- The arms writhe, gather toward their fish in a grab's tell (up for a fish above
		-- it, under the mantle for one below), and stream in a jet
		arch += (0.1 * math.sin(now * 0.9 + visual.index) + 0.05 * math.sin(now * 2.3)) * (1 - 0.7 * pulse + 0.6 * drift)
		if motion.reachUntil > now then
			local at = targetPosition(visual)
			local above = at ~= nil and at.Y > visual.position.Y
			arch += if above then -0.3 else 0.3
		end
		if motion.jetUntil > now then
			arch = 0
		end
	end
	motion.arch, motion.archVelocity = Spring.number(motion.arch, motion.archVelocity, arch, 5, dt)
	-- Its head: eyes on its fish while it hunts (a slow searching sweep at a cruise),
	-- and a shake when a bite lands
	local look = 0
	if not squid and (visual.mode == "hunt" or visual.mode == "windup") then
		local at = targetPosition(visual)
		if at then
			local toward = frameOf(visual.position, visual.heading):VectorToObjectSpace(at - visual.position)
			look = math.clamp(math.atan2(-toward.X, -toward.Z) * 0.4, -0.22, 0.22)
		end
		look += math.sin(now * 1.7 + visual.index) * 0.04 * (1 - math.min(relative, 1))
	end
	motion.look += (look - motion.look) * (1 - math.exp(-dt * 4))
	look = motion.look
	if motion.shakeUntil > now then
		local left = motion.shakeUntil - now
		look += math.sin(left * 34) * 0.24 * (left / 0.6)
	end
	local n = #visual.spine
	if n > 0 then
		local soften = (3 / n) ^ 0.6
		SwimWave.applyBones(
			bones,
			visual.spine,
			visual.phase,
			motion.amplitude * 1.6 * soften,
			motion.bend * soften,
			motion.arch * soften,
			look
		)
	end
	-- The jaw (rig_fish.py --jaw)
	if bones.Jaw then
		local range = motion.jawRange
		local want = range.cruise + math.sin(now * 1.3 + visual.index) * 0.03 * range.wide
		local stiffness = 9
		if motion.snapUntil > now then
			want, stiffness = range.shut, 40
		elseif visual.windupUntil > now then
			-- The gape builds through the tell, trembling as it comes
			local span = math.max(visual.windupUntil - motion.windupFrom, 0.2)
			local progress = math.clamp((now - motion.windupFrom) / span, 0, 1)
			want = range.cruise
				+ (range.wide - range.cruise) * (1 - (1 - progress) ^ 3)
				+ math.sin(now * 38) * 0.015
			stiffness = 12
		elseif rushing then
			want, stiffness = range.wide * 0.9, 14
		elseif visual.tellUntil > now then
			want = range.cruise + (range.wide - range.cruise) * 0.45
		elseif slack then
			want, stiffness = range.wide * 0.45 + math.sin(now * 2.2) * 0.05, 4
		elseif
			bossDef
			and bossDef.kit == "shark"
			and visual.mode == "hunt"
			and visual.health <= bossDef.phases[1]
		then
			-- The Megalodon's frenzy: its jaws working as it hunts
			if now >= motion.nextChomp then
				motion.nextChomp = now + 1.1 + math.random() * 0.8
			end
			local into = motion.nextChomp - now
			if into < 0.32 then
				want = if into > 0.16 then range.wide * 0.75 else range.shut
				stiffness = 30
			end
		end
		motion.gape, motion.gapeVelocity =
			Spring.number(motion.gape, motion.gapeVelocity, want, stiffness, dt)
		SwimWave.setBone(bones, "Jaw", CFrame.new(0, 0, -motion.throw) * CFrame.Angles(-motion.gape, 0, 0))
	end
	-- Pectoral fins (rig_fish.py --fins): flared down in a tell (a shark's threat
	-- hunch), tucked back in a charge, angled into a dive or climb, the inside one
	-- lower in a bank, sculling slowly otherwise
	if bones.FinL or bones.FinR then
		local droop = if visual.windupUntil > now or visual.tellUntil > now
			then 0.32
			elseif rushing then -0.12
			else 0.04 * math.sin(visual.phase * 0.5)
		motion.fins, motion.finsVelocity = Spring.number(motion.fins, motion.finsVelocity, droop, 6, dt)
		local tilt = math.clamp(visual.heading.Y * 0.7 + pitchRate * 0.15, -0.35, 0.35)
		local bank = math.clamp(visual.roll * 0.35, -0.25, 0.25)
		local sweep = if rushing then 0.35 else 0.05
		SwimWave.setBone(bones, "FinL", CFrame.Angles(tilt, sweep, motion.fins + bank))
		SwimWave.setBone(bones, "FinR", CFrame.Angles(tilt, -sweep, -(motion.fins - bank)))
	end
end

-- Bosses are solid: your own fish is kept out of the body (a capsule from tail to
-- nose, thickest mid-body) instead of swimming through it (playtest 2026-10-08: the
-- Megalodon and fish phased through each other). The fish is set back onto the
-- body's surface and only its speed into the body is taken away: no push is added,
-- so it rests against the flank, in bite reach (retest 2026-10-09: a push added to
-- the velocity carried on after the fish was out and threw it 37-42 studs off the
-- axis, past the bite reach).
-- How far `point` is from a creature's body: its axis, less the body radius
local function bodyGap(visual: Visual, point: Vector3): number
	local half = visual.heading * visual.def.length * 0.42
	local tail, span = visual.position - half, half * 2
	local t = math.clamp((point - tail):Dot(span) / math.max(span:Dot(span), 1e-4), 0, 1)
	return math.max(
		(point - (tail + span * t)).Magnitude - visual.def.length * (visual.def.girth or BODY_RADIUS),
		0
	)
end

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function solid(visual: Visual)
	local mine = SwimController.root()
	if mine == nil or SwimController.isHeld() then
		return
	end
	local half = visual.heading * visual.def.length * 0.42
	local tail, span = visual.position - half, half * 2
	local point = mine.Position
	local t = math.clamp((point - tail):Dot(span) / math.max(span:Dot(span), 1e-4), 0, 1)
	-- The same body radius biting measures to (PredatorController.nearest), so a
	-- fish held against the flank is always in bite range (the model's full width,
	-- fins and all, held fish ~40 studs off a Megalodon's axis, out of reach of a
	-- bite, playtest 2026-10-08)
	local girth = visual.def.length * (visual.def.girth or BODY_RADIUS)
	local radius = girth * (0.45 + 0.55 * math.sin(math.pi * t)) + mine.Size.X * 0.4
	local offset = point - (tail + span * t)
	local distance = offset.Magnitude
	if distance >= radius then
		return
	end
	local out = if distance > 1e-3 then offset / distance else Vector3.yAxis
	local velocity = SwimController.velocity
	local into = velocity:Dot(out)
	if into < 0 then
		SwimController.velocity = velocity - out * into
	end
	mine.CFrame += out * (radius - distance)
end

local function step(dt: number)
	local now = Timing.clock()
	local renderAt = now - Predators.interpolationDelay
	local me = Players.LocalPlayer.UserId
	table.clear(parts)
	table.clear(frames)
	local cameraAt = workspace.CurrentCamera.CFrame.Position
	-- (our fish's level, for each predator's LV line: fights go by level)
	local myFish = SwimController.character()
	local mine = if myFish then myFish:GetAttribute("FishLevel") else nil
	local myLevel = if typeof(mine) == "number" then mine else 1
	local edge = Config.Pvp.fight.edge
	for _, visual in visuals do
		if not visual.hidden and now - visual.heardAt > STALE then
			setHidden(visual, true)
		end
		-- Fade in and out
		local goal = if visual.hidden then 0 else 1
		if visual.fade ~= goal then
			visual.fade =
				math.clamp(visual.fade + (if goal > visual.fade then dt else -dt) / FADE_SECONDS, 0, 1)
		end
		-- A boss that hunts out of the blue fades into view as it closes in and fades
		-- back out as it leaves (owner, 2026-10-09: "unseen until he slowly fades into
		-- view of players"); its tells and fight rim follow
		local sight = SIGHT[visual.def.id]
		local far, near = if sight then sight.far else nil, if sight then sight.near else nil
		if far and near then
			-- (left as it was while it leaves, so a boss that was out of sight never
			-- flashes into view as it goes)
			if not visual.hidden then
				local gap = bodyGap(visual, cameraAt)
				local target = smoothstep((far - gap) / math.max(far - near, 1))
				-- (the last step lands on the target: easing alone never quite reaches it)
				visual.presence = if math.abs(target - visual.presence) < 0.01
					then target
					else visual.presence + (target - visual.presence) * math.min(1, dt * 2.5)
			end
		else
			visual.presence = 1
		end
		-- Fully opaque or plainly fading, never a hair see-through: any Transparency
		-- above 0 draws a mesh in Roblox's transparent pass, which doesn't sort its own
		-- faces, so fins, the tail and the inside of the jaw showed through the body
		-- for the whole fight while the fade sat at 0.995 (owner, playtest 2026-10-10:
		-- "boss has holes and see through glitches")
		local opacity = visual.fade * visual.presence
		if opacity >= 0.97 then
			opacity = 1
		elseif opacity <= 0.02 then
			opacity = 0
		end
		if
			opacity ~= visual.shown
			and (math.abs(opacity - visual.shown) > 0.006 or opacity == 0 or opacity == 1)
		then
			visual.shown = opacity
			setTransparency(visual, 1 - opacity)
		end
		if visual.fade <= 0 then
			if visual.gone then
				destroy(visual)
			end
			continue
		end
		local position, heading = sampleAt(visual, renderAt)
		-- Never drawn into the ground: the curve and the extrapolation past the last
		-- sample can dip a hair below where the server keeps it
		local belly = Ground.y(position.X, position.Z) + visual.def.length * 0.12 + 1
		if position.Y < belly then
			position = Vector3.new(position.X, belly, position.Z)
		end
		visual.position = position
		-- Turn smoothly toward the streamed heading
		local before = visual.heading
		local blended = visual.heading:Lerp(heading, 1 - math.exp(-dt * 8))
		visual.heading = if blended.Magnitude > 1e-3 then blended.Unit else heading
		-- Bank into the turn, like the player's own fish (right side down turning right);
		-- the Megalodon rolls its pale belly out on a hard one, falls onto its side in a
		-- breach's crash, and twists with a bite's head shake
		local flatBefore = Vector3.new(before.X, 0, before.Z)
		local flatNow = Vector3.new(visual.heading.X, 0, visual.heading.Z)
		local yawRate, pitchRate = 0, 0
		if dt > 0 and flatBefore.Magnitude > 1e-3 and flatNow.Magnitude > 1e-3 then
			yawRate = math.asin(math.clamp(flatBefore.Unit:Cross(flatNow.Unit).Y, -1, 1)) / dt
		end
		if dt > 0 then
			pitchRate = (
				math.asin(math.clamp(visual.heading.Y, -1, 1)) - math.asin(math.clamp(before.Y, -1, 1))
			) / dt
		end
		local bossDef = Bosses.byId[visual.def.id]
		local bankScale, bankMost = 0.35, 0.5
		if bossDef then
			bankScale, bankMost =
				if bossDef.kit == "shark" then 0.55 else 0.2, if bossDef.kit == "shark" then 0.95 else 0.3
		end
		local wantRoll = math.clamp(yawRate * bankScale, -bankMost, bankMost)
		local motion = visual.motion
		if motion.crashUntil > now then
			wantRoll += 1.1
		end
		if motion.shakeUntil > now then
			wantRoll += math.sin((motion.shakeUntil - now) * 30) * 0.12
		end
		visual.roll, visual.rollVelocity = Spring.number(visual.roll, visual.rollVelocity, wantRoll, 6, dt)
		-- The Goblin Shark's jaws shoot forward late in its tell and out to their full
		-- reach on the bite, then fold back (JawRange `throw`)
		local throwShare = motion.jawRange.throw
		if throwShare then
			local wantThrow = 0
			if motion.snapUntil > now then
				wantThrow = throwShare * visual.def.length
			elseif visual.windupUntil > now then
				local span = math.max(visual.windupUntil - motion.windupFrom, 0.2)
				if (now - motion.windupFrom) / span > 0.7 then
					wantThrow = throwShare * visual.def.length * 0.4
				end
			end
			motion.throw, motion.throwVelocity =
				Spring.number(motion.throw, motion.throwVelocity, wantThrow, 34, dt)
		end
		if visual.boss and not visual.hidden then
			solid(visual)
		end
		local frame = frameOf(position, visual.heading) * CFrame.Angles(0, 0, visual.roll)
		local relative = speedOf(visual) / math.max(visual.def.speed, 1)
		if visual.model then
			animateRig(visual, dt, now, yawRate, pitchRate)
			table.insert(parts, visual.body)
			table.insert(
				frames,
				if visual.drawShift ~= 0 then frame * CFrame.new(0, visual.drawShift, 0) else frame
			)
		else
			local rate = 3 + math.min(relative, 1.5) * 5
			visual.phase += dt * rate
			local beat = math.sin(visual.phase) * 0.4
			table.insert(parts, visual.body)
			local tail = visual.tail
			if tail then
				table.insert(frames, frame)
				table.insert(parts, tail)
				table.insert(
					frames,
					frame
						* CFrame.new(0, 0, visual.bodySize.Z * 0.45)
						* CFrame.Angles(0, beat, 0)
						* CFrame.new(0, 0, tail.Size.Z * 0.4)
				)
			else
				table.insert(
					frames,
					frame
						* CFrame.new(0, 0, -visual.bodySize.Z * 0.3)
						* CFrame.Angles(0, beat * 0.18, 0)
						* CFrame.new(0, 0, visual.bodySize.Z * 0.3)
						* (if visual.flip then MESH_FLIP else CFrame.identity)
				)
			end
		end
		-- Its pieces (STAND_INS; a lure on its model) ride the body's frame
		local thrown = CFrame.new(0, 0, -motion.throw)
		for _, extra in visual.extras do
			table.insert(parts, extra.part)
			table.insert(frames, frame * (if extra.jaw then thrown * extra.offset else extra.offset))
		end
		-- Their own lights fade with the body; a dragonfish's lure breathes, and
		-- brightens as it hunts
		for _, own in visual.lights do
			local pulse = if own.light == visual.lure
				then (0.75 + 0.25 * math.sin(now * 1.8 + visual.index)) * (if visual.mode == "hunt"
						or visual.mode == "windup"
					then 1.6
					else 1)
				else 1
			own.light.Brightness = own.brightness * pulse * visual.shown
		end
		-- A gulper's tell: water streams into its open mouth
		local suction = visual.suction
		if suction then
			local pulling = visual.windupUntil > now and visual.shown > 0.5
			if suction.Enabled ~= pulling then
				suction.Enabled = pulling
			end
		end
		-- The tells: a bite's jaw flashes red faster as it comes; a charge or sweep
		-- tell flashes the eyes amber; a stagger glows gold; a hurt flash is white
		local jaw, glow = visual.jaw, visual.glow
		if visual.flashUntil > now then
			jaw.FillColor = Color3.new(1, 1, 1)
			jaw.FillTransparency = 0.35
			jaw.OutlineTransparency = 0.2
			glow.Brightness = 0
		elseif visual.staggerUntil > now then
			local pulse = 0.5 + 0.5 * math.sin(now * 6)
			jaw.FillColor = Ui.color.haul
			jaw.FillTransparency = 0.6 + 0.3 * pulse
			jaw.OutlineColor = Ui.color.haul
			jaw.OutlineTransparency = 0.1
			glow.Color = Ui.color.haul
			glow.Brightness = 2 + pulse
		elseif visual.windupUntil > now then
			local left = visual.windupUntil - now
			local pulse = 0.5
				+ 0.5 * math.sin(now * (14 + (1 - math.clamp(left / visual.def.telegraph, 0, 1)) * 20))
			jaw.FillColor = Ui.color.danger
			jaw.OutlineColor = Ui.color.danger
			jaw.FillTransparency = 0.45 + 0.4 * pulse
			jaw.OutlineTransparency = 0.1
			glow.Color = Ui.color.danger
			glow.Brightness = 1.5 + 2 * pulse
		elseif visual.tellUntil > now then
			local pulse = 0.5 + 0.5 * math.sin(now * 22)
			jaw.FillColor = Color3.fromRGB(255, 170, 60)
			jaw.OutlineColor = Color3.fromRGB(255, 170, 60)
			jaw.FillTransparency = 0.7 + 0.25 * pulse
			jaw.OutlineTransparency = 0.05
			glow.Color = Color3.fromRGB(255, 120, 40)
			glow.Brightness = 2 + 3 * pulse
		elseif visual.markedUntil > now then
			jaw.FillColor = Ui.color.danger
			jaw.OutlineColor = Ui.color.danger
			jaw.FillTransparency = 1
			jaw.OutlineTransparency = 0.3
			glow.Color = Ui.color.danger
			glow.Brightness = 0.8
		else
			-- In the dark a boss shows by its own eerie light, a faint pulsing glow and
			-- rim, so it reads as a silhouette instead of vanishing (playtest
			-- 2026-10-08: the Giant Squid couldn't be seen without a lamp)
			-- Every hunter shows faintly in the dark, a boss most (owner, 2026-10-09: "how
			-- the hell will anyone fight anything in pitch black"), as far as it has
			-- faded in
			local dark = OceanController.darkness() * (if visual.boss then 1 else 0.6) * visual.presence
			jaw.FillTransparency = 1
			if dark > 0.05 then
				-- A tinted fill and a bright rim, so the whole body reads as a glowing
				-- silhouette (a faint rim alone was a grey blob, playtest 2026-10-08)
				local pulse = 0.5 + 0.5 * math.sin(now * 1.3)
				local eerie = DARK_GLOW[visual.def.id] or DARK_GLOW.default
				jaw.FillColor = eerie
				jaw.FillTransparency = 1 - dark * (0.22 + 0.1 * pulse)
				jaw.OutlineColor = eerie
				jaw.OutlineTransparency = 1 - dark * (0.75 + 0.2 * pulse)
				glow.Color = eerie
				glow.Brightness = dark * (1.6 + 1.2 * pulse)
			elseif visual.boss and sight then
				-- In open water a faint cool rim keeps its outline readable up close
				local close = 1
					- smoothstep((bodyGap(visual, cameraAt) - sight.light * 0.4) / (sight.light * 0.6))
				jaw.OutlineColor = FIGHT_RIM
				jaw.OutlineTransparency = 1 - 0.4 * close * visual.presence
				glow.Brightness = 0
			else
				jaw.OutlineTransparency = 1
				glow.Brightness = 0
			end
		end
		-- The tag: hidden inside a blood cloud (sonar only), and until a boss has faded
		-- most of the way in; else the status line
		visual.tag.Enabled = not visual.hidden
			and visual.bloodUntil <= now
			and visual.presence > 0.5
			and not StartController.isUp() -- (the start screen's shots: no tags over them)
		-- Fights go by level, as between players (Config/Predators `fight`): its level
		-- against ours
		local line = visual.levelLine
		if line then
			if visual.level > 0 then
				local gap = visual.level - myLevel
				if gap >= edge then
					line.Text, line.TextColor3 = `LV {visual.level} · STRONGER`, Ui.color.danger
				elseif gap <= -edge then
					line.Text, line.TextColor3 = `LV {visual.level} · WEAKER`, Ui.color.safe
				else
					line.Text, line.TextColor3 = `LV {visual.level} · EVEN FIGHT`, Ui.color.text
				end
			else
				line.Text = ""
			end
		end
		local style = visual.def.style
		if visual.staggerUntil > now then
			visual.status.Text = "STAGGERED · BITE IT"
			visual.status.TextColor3 = Ui.color.haul
		elseif visual.mode == "stunned" then
			-- (a Lantern Flash or a puffed fish's spines: it drifts, harmless for now)
			visual.status.Text = "STUNNED"
			visual.status.TextColor3 = Ui.color.haul
		elseif visual.target == me then
			visual.status.Text = if visual.markedUntil > now
				then "MARKED YOU FOR DEATH"
				elseif style and style.pack then "PACK HUNTING YOU"
				else "HUNTING YOU"
			visual.status.TextColor3 = Ui.color.danger
		elseif visual.mode == "hunt" or visual.mode == "windup" or visual.mode == "recover" then
			visual.status.Text = "HUNTING"
			visual.status.TextColor3 = Ui.color.haul
		elseif visual.level > 0 and myLevel > visual.level + Predators.fight.shy then
			-- (it won't hunt a fish this far above it: it shies off)
			visual.status.Text = "WARY OF YOU"
			visual.status.TextColor3 = Ui.color.safe
		else
			visual.status.Text = "ROAMING"
			visual.status.TextColor3 = Ui.color.muted
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- Tentacle grabs: a beam to each held fish; our own fish is dragged to the beak
	local myCharacter = Players.LocalPlayer.Character
	local heldBy = if myCharacter then myCharacter:GetAttribute("HeldBy") else nil
	local heldUntil = if myCharacter then myCharacter:GetAttribute("HeldUntil") else nil
	local holder = if typeof(heldBy) == "number"
			and typeof(heldUntil) == "number"
			and heldUntil > now
		then visuals[heldBy]
		else nil
	if holder and not holder.hidden then
		SwimController.hold(holder.position + holder.heading * holder.def.length * 0.1)
	else
		SwimController.hold(nil)
	end
	for _, visual in visuals do
		for userId, endsAt in visual.grabs do
			local player = Players:GetPlayerByUserId(userId)
			local character = player and player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if endsAt <= now or visual.hidden or root == nil or not root:IsA("BasePart") then
				visual.grabs[userId] = nil
				dropBeam(userId)
				continue
			end
			drawBeam(userId, visual.position + visual.heading * visual.def.length * 0.1, root.Position)
		end
	end
	-- Ink: the camera inside a cloud goes blind
	local blind = 0
	for i = #inks, 1, -1 do
		local cloud = inks[i]
		if cloud.endsAt <= now then
			table.remove(inks, i)
			continue
		end
		local distance = (cloud.center - cameraAt).Magnitude
		local inside = math.clamp(1 - (distance - cloud.radius * 0.55) / (cloud.radius * 0.45), 0, 1)
		local fading = math.clamp((cloud.endsAt - now) / 1.5, 0, 1)
		blind = math.max(blind, inside * fading)
	end
	OceanController.setBlind(blind)
	-- The incoming warning
	if warningUntil > now then
		local left = warningUntil - now
		warning.Visible = true
		warning.TextTransparency = if left < 0.3 then 1 - left / 0.3 else 0.5 + 0.5 * math.sin(now * 18) * 0.4
	else
		warning.Visible = false
	end
end

-- A stream packet: { at, list = { {index, x, y, z, hx, hy, hz, mode, hp01, targetUserId, defId, meter, level}, ... } }
local function onState(packet: any)
	if typeof(packet) ~= "table" or typeof(packet.at) ~= "number" or typeof(packet.list) ~= "table" then
		return
	end
	local at = packet.at
	for _, entry in packet.list do
		if typeof(entry) ~= "table" or typeof(entry[1]) ~= "number" then
			continue
		end
		local visual = visualFor(entry[1], if typeof(entry[11]) == "string" then entry[11] else nil)
		if visual == nil or visual.gone then
			continue
		end
		local x, y, z = entry[2], entry[3], entry[4]
		local hx, hy, hz = entry[5], entry[6], entry[7]
		if typeof(x) ~= "number" or typeof(y) ~= "number" or typeof(z) ~= "number" then
			continue
		end
		local heading = Vector3.new(
			if typeof(hx) == "number" then hx else 1,
			if typeof(hy) == "number" then hy else 0,
			if typeof(hz) == "number" then hz else 0
		)
		if heading.Magnitude < 1e-3 then
			heading = Vector3.xAxis
		end
		local samples = visual.samples
		-- Back in range after a gap: start its path afresh (no slide from where it was)
		if at - visual.heardAt > STALE then
			table.clear(samples)
		end
		visual.heardAt = math.max(visual.heardAt, at)
		local last = samples[#samples]
		if last == nil or at > last.at then
			table.insert(samples, { at = at, position = Vector3.new(x, y, z), heading = heading.Unit })
			if #samples > HISTORY then
				table.remove(samples, 1)
			end
		end
		local mode = entry[8]
		visual.mode = if typeof(mode) == "string" then mode else visual.mode
		local hp = entry[9]
		if typeof(hp) == "number" then
			visual.health = math.clamp(hp, 0, 1)
			visual.healthFill.Size = UDim2.fromScale(visual.health, 1)
		end
		local target = entry[10]
		visual.target = if typeof(target) == "number" then target else 0
		local meter = entry[12]
		visual.meter = if typeof(meter) == "number" then math.clamp(meter, 0, 1) else 0
		-- (its group's level: a fish of one kind can be a different level in other waters)
		local level = entry[13]
		if typeof(level) == "number" and level > 0 then
			visual.level = level
		end
		-- Joined mid-life, or missed an event: the mode says whether it's there
		if visual.mode == "dead" then
			setHidden(visual, true)
		elseif visual.hidden then
			-- A fresh life starts where the stream says, not where the last one ended
			visual.position = Vector3.new(x, y, z)
			visual.heading = heading.Unit
			setHidden(visual, false)
		end
	end
end

local function warn(text: string, seconds: number)
	warning.Text = text
	warningUntil = Timing.clock() + seconds
end

local function onEvent(kind: any, index: any, payload: any)
	if typeof(kind) ~= "string" or typeof(index) ~= "number" or typeof(payload) ~= "table" then
		return
	end
	local visual = visualFor(index, if typeof(payload.id) == "string" then payload.id else nil)
	if visual == nil then
		return
	end
	local now = Timing.clock()
	local me = Players.LocalPlayer.UserId
	local def = visual.def
	local at: Vector3? = if typeof(payload.x) == "number"
			and typeof(payload.y) == "number"
			and typeof(payload.z) == "number"
		then Vector3.new(payload.x, payload.y, payload.z)
		else nil
	local myRoot = Players.LocalPlayer.Character
		and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local myDistance = if myRoot and myRoot:IsA("BasePart")
		then (myRoot.Position - visual.position).Magnitude
		else math.huge
	if kind == "spawned" then
		visual.heardAt = now
		if at then
			table.clear(visual.samples)
			visual.position = at
			visual.mode = "roam"
			visual.health = 1
			visual.healthFill.Size = UDim2.fromScale(1, 1)
		end
		visual.gone = false
		setHidden(visual, false)
	elseif kind == "windup" then
		local seconds = if typeof(payload.seconds) == "number" then payload.seconds else def.telegraph
		visual.windupUntil = now + seconds
		visual.motion.windupFrom = now
		if payload.target == me then
			-- (a boss's bite: its head sets late in the tell, so swimming off its jaws
			-- or slipping aside gets clear; BossService BITE_COMMIT)
			local bossDef = Bosses.byId[def.id]
			local jaws = bossDef ~= nil and bossDef.kit == "shark" and seconds >= 0.8
			-- (each predator's own words: GULP · DASH OUT, JAW THROW · DODGE SIDEWAYS, ...)
			local words = def.style and def.style.warn
			warn(
				if jaws
					then `{string.upper(def.name)} · JAWS OPEN · SWIM CLEAR`
					else `{string.upper(def.name)} · {words or "INCOMING"}`,
				seconds + 0.3
			)
			Sfx.play("Warning", { volume = 0.6 })
		end
	elseif kind == "lost" or kind == "stunned" then
		-- Its tell is called off (the fish burrowed or slipped away; a flash or spines
		-- stunned it): no bite comes
		visual.windupUntil = 0
		if kind == "stunned" then
			bubbles(visual.position, def.length * 0.3)
			if visual.target == me then
				warn(`{string.upper(def.name)} · STUNNED`, 1.5)
			end
		end
	elseif kind == "burst" then
		-- An ambusher bursts from cover: a swirl of bubbles off its tail, mouth open
		bubbles(visual.position - visual.heading * def.length * 0.4, def.length * 0.35)
		visual.motion.rushUntil = now + (if typeof(payload.seconds) == "number" then payload.seconds else 1.5)
		if payload.target == me then
			local words = def.style and def.style.warn
			warn(`{string.upper(def.name)} · {words or "BURSTING AT YOU · JUKE SIDEWAYS"}`, 1.6)
		end
	elseif kind == "luring" then
		-- A dragonfish's lure draws the fish it stalks in (Config/Predators `lure`)
		if payload.target == me then
			warn(`{string.upper(def.name)} · ITS LURE IS PULLING YOU IN · SWIM OFF`, 2)
		end
	elseif kind == "bite" then
		visual.windupUntil = 0
		-- The jaws snap shut; a bite that lands gets a head shake
		visual.motion.snapUntil = now + 0.22
		visual.motion.rushUntil = 0
		if payload.hit == true then
			visual.motion.shakeUntil = now + 0.6
		end
		if myDistance < def.length * 4 + 80 then
			Sfx.play("Bite", {
				volume = 0.7,
				pitch = math.clamp(1.1 - def.length * 0.004, 0.55, 1),
				parent = visual.body :: Instance,
				range = 260,
			})
		end
		if at then
			bubbles(at, if payload.hit == true then def.length * 0.5 else def.length * 0.25)
		end
	elseif kind == "charge" then
		local seconds = if typeof(payload.seconds) == "number" then payload.seconds else 1.2
		visual.tellUntil = now + seconds
		if payload.target == me then
			warn(`{string.upper(def.name)} · CHARGING · DODGE SIDEWAYS`, seconds + 0.6)
		end
	elseif kind == "rush" then
		visual.tellUntil = 0
		-- The surge: mouth wide, fins tucked, a burst of water off its tail
		visual.motion.rushUntil = now + (if typeof(payload.seconds) == "number" then payload.seconds else 1)
		bubbles(visual.position - visual.heading * def.length * 0.45, def.length * 0.25)
		if myDistance < def.length * 3 then
			CameraController.kick(0.35)
		end
	elseif kind == "charged" then
		visual.motion.rushUntil = 0
		visual.motion.snapUntil = now + 0.25
		if at then
			bubbles(at, def.length * 0.3)
		end
	elseif kind == "sweep" then
		local seconds = if typeof(payload.seconds) == "number" then payload.seconds else 1
		visual.tellUntil = now + seconds
		local radius = if typeof(payload.radius) == "number" then payload.radius else 40
		if myDistance <= radius + 8 then
			warn("TAIL SWEEP · GET CLEAR", seconds + 0.4)
		end
	elseif kind == "swept" then
		visual.tellUntil = 0
		if at then
			bubbles(at, def.length * 0.6)
		end
		local radius = if typeof(payload.radius) == "number" then payload.radius else 40
		if myDistance <= radius * 1.6 then
			CameraController.kick(0.6)
		end
	elseif kind == "marked" then
		local seconds = if typeof(payload.seconds) == "number" then payload.seconds else 8
		visual.markedUntil = now + seconds
		if payload.target == me then
			warn(`MARKED FOR DEATH · {math.floor(seconds)} s · FILL ITS STAGGER METER`, 3)
		end
	elseif kind == "unmarked" then
		visual.markedUntil = 0
	elseif kind == "stagger" then
		local seconds = if typeof(payload.seconds) == "number" then payload.seconds else 4
		visual.staggerUntil = now + seconds
		visual.markedUntil = 0
		visual.tellUntil = 0
		visual.windupUntil = 0
		bubbles(visual.position, def.length * 0.4, Ui.color.haul)
	elseif kind == "blood" then
		bloodCloud(visual, if typeof(payload.seconds) == "number" then payload.seconds else 10)
	elseif kind == "breach" then
		local seconds = if typeof(payload.seconds) == "number" then payload.seconds else 2
		if payload.stage == "tell" then
			visual.tellUntil = now + seconds
			if myDistance < 160 then
				warn("IT'S GOING TO BREACH · GO UP OR DOWN", seconds + 0.5)
			end
		elseif payload.stage == "rocket" then
			visual.tellUntil = 0
			visual.motion.rocketUntil = now + seconds
			bubbles(visual.position - visual.heading * def.length * 0.45, def.length * 0.3)
			if myDistance < 160 then
				CameraController.kick(0.4)
			end
		elseif payload.stage == "crash" then
			visual.motion.rocketUntil = 0
			visual.motion.crashUntil = now + seconds + 0.6
		end
	elseif kind == "shock" then
		visual.motion.snapUntil = now + 0.3
		Sfx.play("Breach", { volume = 0.95, parent = visual.body :: Instance, range = 500 })
		local radius = if typeof(payload.radius) == "number" then payload.radius else 45
		if at then
			shockwave(at, radius)
		end
		if myDistance <= radius * 2.5 then
			CameraController.kick(math.clamp(1 - myDistance / (radius * 2.5), 0.3, 1))
		end
	elseif kind == "exhausted" then
		local seconds = if typeof(payload.seconds) == "number" then payload.seconds else 5
		visual.staggerUntil = now + seconds
	elseif kind == "laststand" then
		Sfx.play("BossPhase", { volume = 0.85 })
		visual.markedUntil = 0
	elseif kind == "grab" then
		local seconds = if typeof(payload.seconds) == "number" then payload.seconds else 1
		if payload.missed == true then
			if at then
				bubbles(at, def.length * 0.2)
			end
		else
			visual.tellUntil = now + seconds
			-- (its arms curl up and reach)
			visual.motion.reachUntil = now + seconds + 0.3
			if payload.target == me then
				warn("TENTACLE · GET CLEAR", seconds + 0.3)
			end
		end
	elseif kind == "grabbed" then
		if payload.target == me then
			Sfx.play("Grab", { volume = 0.9 })
		end
		local seconds = if typeof(payload.seconds) == "number" then payload.seconds else 4
		if typeof(payload.target) == "number" then
			visual.grabs[payload.target] = now + seconds
		end
		visual.tellUntil = 0
		if payload.target == me then
			warn("GRABBED · MASH BITE TO BREAK FREE", seconds)
			CameraController.kick(0.5)
		end
	elseif kind == "struggle" then
		if payload.target == me and typeof(payload.progress) == "number" then
			warn(`BREAKING FREE · {math.floor(payload.progress * 100 + 0.5)}%`, 1.2)
		end
	elseif kind == "released" then
		if typeof(payload.target) == "number" then
			visual.grabs[payload.target] = nil
			dropBeam(payload.target)
		end
		if payload.target == me then
			warn(if payload.how == "eaten" then "" else "FREE", 0.8)
		end
	elseif kind == "ink" then
		Sfx.play("Ink", { volume = 0.8, parent = visual.body :: Instance, range = 300 })
		local seconds = if typeof(payload.seconds) == "number" then payload.seconds else 6
		local radius = if typeof(payload.radius) == "number" then payload.radius else 50
		inkCloud(at or visual.position, radius, seconds)
		visual.bloodUntil = now + seconds -- its tag hides in the cloud
	elseif kind == "jet" then
		visual.tellUntil = now + (if typeof(payload.seconds) == "number" then payload.seconds else 0.6)
	elseif kind == "jetted" then
		visual.tellUntil = 0
		-- (arms streamed straight behind it as it shoots off)
		visual.motion.jetUntil = now + 0.9
		if
			typeof(payload.fromX) == "number"
			and typeof(payload.fromY) == "number"
			and typeof(payload.fromZ) == "number"
		then
			bubbles(Vector3.new(payload.fromX, payload.fromY, payload.fromZ), def.length * 0.6)
		end
		if at then
			table.clear(visual.samples)
			visual.position = at
			bubbles(at, def.length * 0.4)
		end
	elseif kind == "whirl" then
		local seconds = if typeof(payload.seconds) == "number" then payload.seconds else 1.2
		local radius = if typeof(payload.radius) == "number" then payload.radius else 70
		visual.tellUntil = now + seconds
		if myDistance <= radius + 10 then
			warn("WHIRLPOOL · SWIM AWAY FROM IT", seconds + 3)
		end
	elseif kind == "whirling" then
		local seconds = if typeof(payload.seconds) == "number" then payload.seconds else 3
		local radius = if typeof(payload.radius) == "number" then payload.radius else 70
		visual.tellUntil = 0
		whirlCloud(at or visual.position, radius, seconds)
	elseif kind == "siphon" then
		local seconds = if typeof(payload.seconds) == "number" then payload.seconds else 1
		local range = if typeof(payload.range) == "number" then payload.range else 48
		visual.tellUntil = now + seconds
		if myRoot and myRoot:IsA("BasePart") then
			local offset = myRoot.Position - visual.position
			if offset.Magnitude <= range + 10 and visual.heading:Dot(offset.Unit) > 0.4 then
				warn("SIPHON BLAST · GET OUT OF ITS FACE", seconds + 0.3)
			end
		end
	elseif kind == "siphoned" then
		visual.tellUntil = 0
		local range = if typeof(payload.range) == "number" then payload.range else 48
		local heading = if typeof(payload.hx) == "number"
				and typeof(payload.hy) == "number"
				and typeof(payload.hz) == "number"
			then Vector3.new(payload.hx, payload.hy, payload.hz)
			else visual.heading
		local origin = at or visual.position
		bubbles(origin + heading * range * 0.3, def.length * 0.5)
		bubbles(origin + heading * range * 0.7, def.length * 0.5)
	elseif kind == "enraged" or kind == "mantle" then
		Sfx.play("BossPhase", { volume = 0.85 })
		visual.flashUntil = now + 0.3
	elseif kind == "hurt" then
		visual.flashUntil = now + 0.12
		if typeof(payload.health) == "number" then
			visual.health = math.clamp(payload.health, 0, 1)
			visual.healthFill.Size = UDim2.fromScale(visual.health, 1)
		end
		local position = at or visual.position
		bubbles(position, def.length * (if visual.boss then 0.08 else 0.2))
		if payload.by == me and typeof(payload.damage) == "number" then
			PredatorController.hit:fire(payload.damage, position)
		end
	elseif kind == "died" then
		visual.mode = "dead"
		-- A boss's last warning goes with it (a "GOING TO BREACH" line stayed up
		-- behind the slain card, retest 2026-10-08)
		if visual.boss then
			warningUntil = 0
		end
		if payload.reason ~= "escaped" and payload.reason ~= "sunk" then
			-- (swallowed whole by a fish 20 levels up: a gulp, not a kill)
			bubbles(
				visual.position,
				def.length * (if visual.boss then 0.5 elseif payload.swallowed == true then 1.4 else 0.9)
			)
		end
		if payload.swallowed == true and payload.by == me then
			Sfx.play("Chomp", { volume = 0.9 })
			CameraController.kick(0.3)
		end
		setHidden(visual, true)
		if payload.gone == true then
			visual.gone = true
		end
	end
	PredatorController.event:fire(kind, index, payload)
end

-- The index of the live creature whose body is within `reach` of `mouth` (nearest
-- first), or nil. Distance is to the body's tail-to-nose line, like the server's.
function PredatorController.nearest(mouth: Vector3, reach: number): number?
	local best: number? = nil
	local bestGap = math.huge
	for index, visual in visuals do
		if visual.hidden or visual.mode == "dead" then
			continue
		end
		local half = visual.heading * visual.def.length * 0.5
		local a, b = visual.position - half, visual.position + half
		local ab = b - a
		local t = math.clamp((mouth - a):Dot(ab) / math.max(ab:Dot(ab), 1e-4), 0, 1)
		local gap = (a + ab * t - mouth).Magnitude - visual.def.length * (visual.def.girth or BODY_RADIUS)
		if gap <= reach and gap < bestGap then
			best, bestGap = index, gap
		end
	end
	return best
end

-- The creature drawn at `index`: its position, mode, health (0..1) and stagger
-- meter (0..1), for the boss HUD. Nil when it isn't known here.
-- How far `point` is from a creature's body (nil while it isn't drawn), and how
-- opaque it's drawn right now (0..1: its fade into view)
function PredatorController.gap(index: number, point: Vector3): (number?, number)
	local visual = visuals[index]
	if visual == nil or visual.hidden then
		return nil, 0
	end
	return bodyGap(visual, point), visual.shown
end

-- Every creature drawn right now (not hidden, not dead): what to adorn (its rigged
-- model, or its body part) and where it is. Blood Sense marks them.
function PredatorController.drawn(): { { instance: Instance, position: Vector3 } }
	local list: { { instance: Instance, position: Vector3 } } = {}
	for _, visual in visuals do
		if visual.hidden or visual.gone or visual.mode == "dead" then
			continue
		end
		local instance: Instance = if visual.model then visual.model :: Model else visual.body
		table.insert(list, { instance = instance, position = visual.position })
	end
	return list
end

function PredatorController.get(index: number): (Vector3?, string?, number, number)
	local visual = visuals[index]
	if visual == nil or visual.hidden then
		return nil, nil, 0, 0
	end
	return visual.position, visual.mode, visual.health, visual.meter
end

function PredatorController.start()
	folder = Instance.new("Folder")
	folder.Name = "Predators"
	folder.Parent = workspace
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Ui.screen("Predators", playerGui, 6)
	warning = Ui.label(
		gui,
		"Warning",
		"",
		Ui.FONT_HEAVY,
		22,
		Ui.color.danger,
		UDim2.new(1, 0, 0, 30),
		UDim2.new(0, 0, 0.5, -120)
	)
	warning.TextXAlignment = Enum.TextXAlignment.Center
	warning.TextStrokeTransparency = 0.4
	warning.Visible = false
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local state = remotes:WaitForChild("PredatorState") :: UnreliableRemoteEvent
	state.OnClientEvent:Connect(onState)
	local event = remotes:WaitForChild("PredatorEvent") :: RemoteEvent
	event.OnClientEvent:Connect(onEvent)
	RunService.RenderStepped:Connect(step)
end

return PredatorController
