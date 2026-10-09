--!strict
-- The AI predators and world bosses on this client (Config/Predators, Config/Bosses,
-- PredatorService). The server streams their positions ten times a second over an
-- unreliable remote; this controller keeps a short history per creature and draws
-- each one a little behind the stream, so they glide instead of stepping. Events
-- (PredatorEvent) carry the moments: a windup (the jaw flashes, and a warning if
-- it's coming for us), a bite (bubbles), a hurt (a flash, a damage pop for our own
-- bites), a death (a fade), and the bosses' tells: a charge, a tail sweep, a mark,
-- a stagger, a blood cloud, a breach and its shockwave.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PredatorsConfig = require(ReplicatedStorage.Shared.Config.Predators)
local Signal = require(ReplicatedStorage.Shared.Signal)
local SwimWave = require(ReplicatedStorage.Shared.SwimWave)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Ui = require(script.Parent.Parent.Ui)
local Sfx = require(script.Parent.Parent.Sfx)
local CameraController = require(script.Parent.CameraController)
local OceanController = require(script.Parent.OceanController)
local SwimController = require(script.Parent.SwimController)

-- A creature's body radius as a share of its length, for biting it and for bumping
-- into a boss
local BODY_RADIUS = 0.18

-- A boss's own light in the pitch dark (OceanController.darkness): bioluminescent
-- violet for the squid, a cold blue otherwise
local DARK_GLOW: { [string]: Color3 } = {
	GiantSquid = Color3.fromRGB(130, 90, 255),
	default = Color3.fromRGB(90, 160, 255),
}

local Predators = Config.Predators
local Bosses = Config.Bosses

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
local TAG_DISTANCE = 240

type Sample = {
	at: number,
	position: Vector3,
	heading: Vector3,
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
	jaw: Highlight,
	glow: PointLight,
	blood: ParticleEmitter?,
	tag: BillboardGui,
	healthFill: Frame,
	status: TextLabel,
}

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
	gui.Size = if visual.boss then UDim2.fromOffset(320, 56) else UDim2.fromOffset(220, 46)
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
		UDim2.fromOffset(0, if visual.boss then 26 else 20)
	)
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.TextStrokeTransparency = 0.6
	local _, fill = Ui.bar(
		gui,
		"Health",
		UDim2.new(0.6, 0, 0, 5),
		UDim2.new(0.2, 0, 0, if visual.boss then 46 else 38),
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
			local made = makePart(folder, def.back)
			made.Size = bodySize
			local fin = makePart(folder, def.back:Lerp(def.belly, 0.3))
			fin.Name = "Tail"
			fin.Size = tailSize
			tail = fin
			body = made
		end
	end
	local part = body :: BasePart
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
		jaw = jaw,
		glow = glow,
		blood = nil,
		tag = nil :: any,
		healthFill = nil :: any,
		status = nil :: any,
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
			return a.position:Lerp(b.position, alpha),
				if heading.Magnitude > 1e-3 then heading.Unit else b.heading
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

-- A rigged body swims: a wave runs down the spine, wider and faster with speed
local function swimBones(visual: Visual, dt: number, relative: number)
	local frequency = 0.5 + 1.4 * math.min(relative, 1.5)
	visual.phase += 2 * math.pi * frequency * dt
	local amplitude = 0.06 + 0.16 * math.min(relative, 1)
	local p = visual.phase
	local n = #visual.spine
	if n == 0 then
		return
	end
	local soften = (3 / n) ^ 0.6
	SwimWave.applyBones(visual.bones, visual.spine, p, amplitude * 1.6 * soften, 0)
end

-- Bosses are solid: your own fish is kept out of the body (a capsule from tail to
-- nose, thickest mid-body) instead of swimming through it (playtest 2026-10-08: the
-- Megalodon and fish phased through each other). The fish is set back onto the
-- body's surface and only its speed into the body is taken away: no push is added,
-- so it rests against the flank, in bite reach (retest 2026-10-09: a push added to
-- the velocity carried on after the fish was out and threw it 37-42 studs off the
-- axis, past the bite reach).
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
	local girth = visual.def.length * BODY_RADIUS
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
	for _, visual in visuals do
		-- Fade in and out
		local goal = if visual.hidden then 0 else 1
		if visual.fade ~= goal then
			visual.fade =
				math.clamp(visual.fade + (if goal > visual.fade then dt else -dt) / FADE_SECONDS, 0, 1)
			setTransparency(visual, 1 - visual.fade)
		end
		if visual.fade <= 0 then
			if visual.gone then
				destroy(visual)
			end
			continue
		end
		local position, heading = sampleAt(visual, renderAt)
		visual.position = position
		-- Turn smoothly toward the streamed heading
		local blended = visual.heading:Lerp(heading, 1 - math.exp(-dt * 8))
		visual.heading = if blended.Magnitude > 1e-3 then blended.Unit else heading
		if visual.boss and not visual.hidden then
			solid(visual)
		end
		local frame = frameOf(position, visual.heading)
		local relative = speedOf(visual) / math.max(visual.def.speed, 1)
		if visual.model then
			swimBones(visual, dt, relative)
			table.insert(parts, visual.body)
			table.insert(frames, frame)
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
			local dark = if visual.boss then OceanController.darkness() else 0
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
			else
				jaw.OutlineTransparency = 1
				glow.Brightness = 0
			end
		end
		-- The tag: hidden inside a blood cloud (sonar only), else the status line
		visual.tag.Enabled = not visual.hidden and visual.bloodUntil <= now
		if visual.staggerUntil > now then
			visual.status.Text = "STAGGERED · BITE IT"
			visual.status.TextColor3 = Ui.color.haul
		elseif visual.target == me then
			visual.status.Text = if visual.markedUntil > now then "MARKED YOU FOR DEATH" else "HUNTING YOU"
			visual.status.TextColor3 = Ui.color.danger
		elseif visual.mode == "hunt" or visual.mode == "windup" or visual.mode == "recover" then
			visual.status.Text = "HUNTING"
			visual.status.TextColor3 = Ui.color.haul
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
	local cameraAt = workspace.CurrentCamera.CFrame.Position
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

-- A stream packet: { at, list = { {index, x, y, z, hx, hy, hz, mode, hp01, targetUserId, defId, meter}, ... } }
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
		if payload.target == me then
			warn(`{string.upper(def.name)} · INCOMING`, seconds + 0.3)
			Sfx.play("Warning", { volume = 0.6 })
		end
	elseif kind == "bite" then
		visual.windupUntil = 0
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
		if myDistance < def.length * 3 then
			CameraController.kick(0.35)
		end
	elseif kind == "charged" then
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
			if myDistance < 160 then
				CameraController.kick(0.4)
			end
		end
	elseif kind == "shock" then
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
			bubbles(visual.position, def.length * (if visual.boss then 0.5 else 0.9))
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
		local gap = (a + ab * t - mouth).Magnitude - visual.def.length * BODY_RADIUS
		if gap <= reach and gap < bestGap then
			best, bestGap = index, gap
		end
	end
	return best
end

-- The creature drawn at `index`: its position, mode, health (0..1) and stagger
-- meter (0..1), for the boss HUD. Nil when it isn't known here.
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
