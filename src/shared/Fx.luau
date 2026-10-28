--!strict
-- Particle looks shared by the skin effects (Shared/SkinFx) and the boost trails
-- (TrailController). Each preset makes one ParticleEmitter sized by the fish's
-- length `L` and tinted `c` (and `c2` where it blends): mist rolling off a ghost,
-- stars drifting off a nebula, dark grit sucked into a void, foam streaking off a
-- riptide. Textures come from Config/Textures `fx*` once they're uploaded
-- (assets/textures/fx_*.png), and from Roblox's own particle images until then.
--
-- Sized to read in a still at 15-25 studs in the shallow haze (playtest 2026-10-17:
-- at LV 40 gold dust, glints, crystal flashes, embers, ink, bubbles and falling stars
-- were a few specks). The glows carry `Brightness` over 1: an emitted colour is
-- blended toward the water's haze with distance like anything else, and a brighter
-- one keeps its colour further out.
local Config = require(script.Parent.Config)

local Fx = {}

local BUILT_IN = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
}

-- An uploaded fx image (Config/Textures key), else a built-in one
local function texture(key: string, fallback: string): string
	local id = (Config.Textures :: { [string]: number })[key]
	return if typeof(id) == "number" and id ~= 0 then `rbxassetid://{id}` else fallback
end

function Fx.keys(points: { number }): NumberSequence
	local list = {}
	for i = 1, #points, 2 do
		table.insert(list, NumberSequenceKeypoint.new(points[i], points[i + 1]))
	end
	return NumberSequence.new(list)
end

local keys = Fx.keys

-- A rainbow (for Prismatic, the Rainbow trail)
function Fx.rainbow(saturation: number?): ColorSequence
	local s = saturation or 0.65
	local points = {}
	for i = 0, 6 do
		table.insert(points, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) * 0.85, s, 1)))
	end
	return ColorSequence.new(points)
end

export type Preset =
	"mist"
	| "wisps"
	| "stardust"
	| "nebula"
	| "vortex"
	| "foam"
	| "glints"
	| "crystal"
	| "gold"
	| "tropical"
	| "starfall"
	| "embers"
	| "drips"
	| "ink"
	| "motes"
	| "bubbles"
	| "frost"
	| "flame"
	| "sparks"
	| "pearls"
	| "whirls"
	| "shimmer"
	| "glitter"

-- A size sequence `k` times bigger (its envelopes too)
local function grown(sequence: NumberSequence, k: number): NumberSequence
	local list = {}
	for _, point in sequence.Keypoints do
		table.insert(list, NumberSequenceKeypoint.new(point.Time, point.Value * k, point.Envelope * k))
	end
	return NumberSequence.new(list)
end

-- One emitter of a preset, parented to `parent` (a part: it emits from the part's
-- box; an attachment: from a point). `rate` scales its usual rate and `size` its
-- particles (the boost trails draw theirs bigger than a skin's).
function Fx.emitter(
	parent: Instance,
	preset: Preset,
	L: number,
	c: Color3,
	c2: Color3?,
	rate: number?,
	size: number?
): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = `Fx{preset}`
	e.Texture = texture("fxStar", BUILT_IN.sparkle)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.SpreadAngle = Vector2.new(180, 180)
	e.Color = ColorSequence.new(c, c2 or c)
	local base = 6
	if preset == "mist" then
		-- Soft mist rolling off the body and hanging behind it
		e.Texture = texture("fxMist", BUILT_IN.smoke)
		base = 12
		e.Lifetime = NumberRange.new(1.6, 2.8)
		e.Speed = NumberRange.new(L * 0.04, L * 0.14)
		e.Acceleration = Vector3.new(0, L * 0.06, 0)
		e.Drag = 1.2
		e.RotSpeed = NumberRange.new(-25, 25)
		e.Rotation = NumberRange.new(0, 360)
		e.Size = keys({ 0, L * 0.18, 0.5, L * 0.42, 1, L * 0.6 })
		e.Transparency = keys({ 0, 1, 0.2, 0.62, 0.6, 0.75, 1, 1 })
		e.LightEmission = 0.65
	elseif preset == "wisps" then
		-- Thin spirits curling up off a haunt
		base = 8
		e.Lifetime = NumberRange.new(1.4, 2.6)
		e.Speed = NumberRange.new(L * 0.05, L * 0.2)
		e.Acceleration = Vector3.new(0, L * 0.1, 0)
		e.Drag = 1.5
		e.Size = keys({ 0, 0, 0.25, L * 0.12, 1, L * 0.04 })
		e.Transparency = keys({ 0, 1, 0.2, 0.4, 1, 1 })
	elseif preset == "stardust" then
		-- Pinpricks that twinkle twice and fade
		base = 14
		e.Brightness = 1.6
		e.Lifetime = NumberRange.new(1.4, 2.4)
		e.Speed = NumberRange.new(L * 0.02, L * 0.1)
		e.Drag = 1
		e.Rotation = NumberRange.new(0, 90)
		e.Size = keys({ 0, 0, 0.2, L * 0.085, 0.4, L * 0.025, 0.6, L * 0.085, 1, 0 })
	elseif preset == "nebula" then
		-- Coloured gas clouds drifting round the fish
		e.Texture = texture("fxMist", BUILT_IN.smoke)
		base = 5
		e.Lifetime = NumberRange.new(2.4, 3.6)
		e.Speed = NumberRange.new(L * 0.02, L * 0.08)
		e.Drag = 0.6
		e.RotSpeed = NumberRange.new(-15, 15)
		e.Rotation = NumberRange.new(0, 360)
		e.Size = keys({ 0, L * 0.3, 1, L * 0.75 })
		e.Transparency = keys({ 0, 1, 0.3, 0.72, 0.7, 0.8, 1, 1 })
		e.LightEmission = 0.85
	elseif preset == "vortex" then
		-- Grit pulled in from all round and swallowed (Void, Undertow)
		e.Texture = texture("fxSpark", BUILT_IN.sparkle)
		base = 22
		e.Shape = Enum.ParticleEmitterShape.Sphere
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		e.SpreadAngle = Vector2.new(8, 8)
		e.Lifetime = NumberRange.new(0.6, 0.9)
		e.Speed = NumberRange.new(L * 0.5, L * 0.7)
		e.Size = keys({ 0, L * 0.05, 1, 0 })
		e.Transparency = keys({ 0, 1, 0.25, 0.1, 1, 0.6 })
	elseif preset == "foam" then
		-- White water streaking off the body, left behind as it swims
		e.Texture = texture("fxSpark", BUILT_IN.sparkle)
		base = 28
		e.Lifetime = NumberRange.new(0.35, 0.7)
		e.Speed = NumberRange.new(L * 0.05, L * 0.2)
		e.Drag = 3
		e.Size = keys({ 0, L * 0.05, 1, L * 0.01 })
		e.Transparency = keys({ 0, 0.15, 1, 1 })
		e.LightEmission = 0.6
	elseif preset == "glints" then
		-- Bright points flicking off it
		base = 10
		e.Brightness = 1.8
		e.Lifetime = NumberRange.new(0.6, 1.2)
		e.Speed = NumberRange.new(L * 0.2, L * 0.6)
		e.Drag = 2
		e.Rotation = NumberRange.new(0, 90)
		e.Size = keys({ 0, 0, 0.3, L * 0.095, 1, 0 })
	elseif preset == "crystal" then
		-- Hard star flashes on the facets, gone in a blink (about seven at once)
		e.Texture = texture("fxStar", BUILT_IN.sparkle)
		base = 13
		e.Brightness = 2.2
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.Lifetime = NumberRange.new(0.35, 0.6)
		e.Speed = NumberRange.new(0, L * 0.02)
		e.Rotation = NumberRange.new(0, 90)
		e.Size = keys({ 0, 0, 0.35, L * 0.19, 1, 0 })
	elseif preset == "gold" then
		-- Gold flakes glittering down off it, turning as they fall (Roblox's own white
		-- sparkle: the fx images are drawn in a light cyan, which turned gold olive)
		e.Texture = BUILT_IN.sparkle
		base = 22
		e.Brightness = 2
		e.Lifetime = NumberRange.new(1, 1.6)
		e.Speed = NumberRange.new(L * 0.02, L * 0.06)
		e.Acceleration = Vector3.new(0, -L * 0.2, 0)
		e.Drag = 0.8
		e.Rotation = NumberRange.new(0, 90)
		e.RotSpeed = NumberRange.new(-120, 120)
		e.Size = keys({ 0, L * 0.06, 0.25, L * 0.075, 0.5, L * 0.045, 1, 0 })
		e.Transparency = keys({ 0, 0, 0.7, 0.15, 1, 1 })
	elseif preset == "tropical" then
		-- Many-coloured motes, a reef's worth
		e.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 196, 40)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(60, 230, 160)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(70, 160, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 110, 255)),
		})
		base = 14
		e.Brightness = 1.7
		e.Lifetime = NumberRange.new(1.2, 2)
		e.Speed = NumberRange.new(L * 0.04, L * 0.12)
		e.Drag = 1
		e.Rotation = NumberRange.new(0, 90)
		e.Size = keys({ 0, 0, 0.3, L * 0.09, 1, 0 })
	elseif preset == "starfall" then
		-- Stars dropping off it like a meteor shower, drawn out a little as they fall
		base = 12
		e.Brightness = 2
		e.Lifetime = NumberRange.new(0.9, 1.4)
		e.Speed = NumberRange.new(0, L * 0.05)
		e.Acceleration = Vector3.new(0, -L * 0.9, 0)
		e.Size = keys({ 0, L * 0.12, 0.6, L * 0.075, 1, 0 })
		e.Squash = keys({ 0, 0, 0.3, 0.5, 1, 0.8 })
	elseif preset == "embers" then
		-- Sparks rising off a fire, yellow cooling to red
		base = 18
		e.Brightness = 2.2
		e.Lifetime = NumberRange.new(0.8, 1.6)
		e.Speed = NumberRange.new(L * 0.05, L * 0.2)
		e.Acceleration = Vector3.new(0, L * 0.5, 0)
		e.Drag = 1
		e.Size = keys({ 0, L * 0.065, 0.6, L * 0.045, 1, 0 })
	elseif preset == "drips" then
		-- Molten drops falling off the belly
		base = 8
		e.Brightness = 1.8
		e.Lifetime = NumberRange.new(0.6, 0.9)
		e.Speed = NumberRange.new(0, L * 0.03)
		e.Acceleration = Vector3.new(0, -L * 1.4, 0)
		e.Size = keys({ 0, L * 0.065, 1, L * 0.035 })
	elseif preset == "ink" then
		-- Ink curling off and hanging in the water: thick and faintly lit in its
		-- colour, deepening toward `c2` as it spreads (unlit dark ink at 45% was lost
		-- in the blue shallows, playtest 2026-10-17)
		e.Texture = texture("fxMist", BUILT_IN.smoke)
		base = 10
		e.Color = ColorSequence.new(c, c:Lerp(c2 or c, 0.45))
		e.LightEmission = 0.25
		e.LightInfluence = 0.2
		e.Lifetime = NumberRange.new(1.8, 2.8)
		e.Speed = NumberRange.new(L * 0.03, L * 0.1)
		e.Drag = 1
		e.RotSpeed = NumberRange.new(-30, 30)
		e.Rotation = NumberRange.new(0, 360)
		e.Size = keys({ 0, L * 0.14, 1, L * 0.55 })
		e.Transparency = keys({ 0, 1, 0.12, 0.28, 0.6, 0.45, 1, 1 })
	elseif preset == "motes" then
		-- Soft lights drifting up slowly
		base = 7
		e.Lifetime = NumberRange.new(2, 3)
		e.Speed = NumberRange.new(L * 0.03, L * 0.1)
		e.Acceleration = Vector3.new(0, L * 0.05, 0)
		e.Drag = 0.5
		e.Size = keys({ 0, 0, 0.3, L * 0.045, 1, 0 })
		e.Transparency = keys({ 0, 1, 0.3, 0.15, 1, 1 })
	elseif preset == "bubbles" then
		-- Small bubbles rising
		e.Texture = texture("fxBubble", BUILT_IN.sparkle)
		base = 10
		e.LightEmission = 0.6
		e.LightInfluence = 0.6
		e.Lifetime = NumberRange.new(1.2, 2)
		e.Speed = NumberRange.new(L * 0.02, L * 0.08)
		e.Acceleration = Vector3.new(0, L * 0.45, 0)
		e.Drag = 2
		e.Size = keys({ 0, L * 0.022, 0.3, L * 0.058, 1, L * 0.065 })
		e.Transparency = keys({ 0, 0.2, 0.7, 0.35, 1, 1 })
	elseif preset == "frost" then
		-- Rime and cold haze sinking off it
		e.Texture = texture("fxMist", BUILT_IN.smoke)
		base = 7
		e.LightEmission = 0.4
		e.Lifetime = NumberRange.new(1.4, 2.2)
		e.Speed = NumberRange.new(L * 0.02, L * 0.06)
		e.Acceleration = Vector3.new(0, -L * 0.1, 0)
		e.RotSpeed = NumberRange.new(-40, 40)
		e.Size = keys({ 0, L * 0.12, 1, L * 0.35 })
		e.Transparency = keys({ 0, 1, 0.2, 0.7, 1, 1 })
	elseif preset == "flame" then
		-- Licking flames (the Fire trail)
		e.Texture = texture("fxFlame", BUILT_IN.fire)
		base = 26
		e.Lifetime = NumberRange.new(0.35, 0.6)
		e.Speed = NumberRange.new(L * 0.05, L * 0.15)
		e.Acceleration = Vector3.new(0, L * 0.6, 0)
		e.RotSpeed = NumberRange.new(-60, 60)
		e.Rotation = NumberRange.new(0, 360)
		e.Size = keys({ 0, L * 0.12, 0.4, L * 0.2, 1, 0 })
		e.Transparency = keys({ 0, 0.2, 0.6, 0.45, 1, 1 })
	elseif preset == "sparks" then
		-- Quick electric spits
		e.Texture = texture("fxSpark", BUILT_IN.sparkle)
		base = 10
		e.Lifetime = NumberRange.new(0.12, 0.3)
		e.Speed = NumberRange.new(L * 0.8, L * 1.6)
		e.Drag = 6
		e.Size = keys({ 0, L * 0.04, 1, 0 })
	elseif preset == "whirls" then
		-- Whirlpools turning on the body (Undertow): held to it, spinning
		e.Texture = texture("fxSwirl", BUILT_IN.sparkle)
		base = 3
		e.LockedToPart = true
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.Lifetime = NumberRange.new(1.6, 2.4)
		e.Speed = NumberRange.new(0, 0)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-260, -180)
		e.Size = keys({ 0, L * 0.12, 0.5, L * 0.26, 1, L * 0.3 })
		e.Transparency = keys({ 0, 1, 0.25, 0.35, 0.75, 0.45, 1, 1 })
	elseif preset == "pearls" then
		-- Round glossy pearls rising slowly
		e.Texture = texture("fxBubble", BUILT_IN.sparkle)
		base = 4
		e.LightEmission = 0.3
		e.LightInfluence = 0.6
		e.Lifetime = NumberRange.new(2, 3)
		e.Speed = NumberRange.new(L * 0.02, L * 0.05)
		e.Acceleration = Vector3.new(0, L * 0.12, 0)
		e.Size = keys({ 0, 0, 0.2, L * 0.07, 1, L * 0.06 })
		e.Transparency = keys({ 0, 1, 0.2, 0.1, 0.85, 0.2, 1, 1 })
	elseif preset == "glitter" then
		-- Fine gold glitter: quick hard twinkles where they're shed, barely moving
		-- (Golden's shine; on Roblox's own white sparkle, so the gold stays gold)
		e.Texture = BUILT_IN.sparkle
		base = 10
		e.Brightness = 2.6
		e.Lifetime = NumberRange.new(0.25, 0.5)
		e.Speed = NumberRange.new(0, L * 0.04)
		e.Drag = 4
		e.Rotation = NumberRange.new(0, 90)
		e.RotSpeed = NumberRange.new(-90, 90)
		e.Size = keys({ 0, 0, 0.35, L * 0.075, 1, 0 })
	elseif preset == "shimmer" then
		-- A shell of rainbow sparkles twinkling over the body, held to it, each one
		-- running through the hues as it lives (Prismatic: an outline alone was lost
		-- on a rainbow body, playtest 2026-10-17)
		e.Texture = texture("fxStar", BUILT_IN.sparkle)
		base = 10
		e.Brightness = 1.6
		e.LockedToPart = true
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.Color = Fx.rainbow(0.55)
		e.Lifetime = NumberRange.new(0.6, 1)
		e.Speed = NumberRange.new(0, 0)
		e.Rotation = NumberRange.new(0, 90)
		e.Size = keys({ 0, 0, 0.25, L * 0.085, 0.5, L * 0.03, 0.75, L * 0.085, 1, 0 })
	end
	if size and size ~= 1 then
		e.Size = grown(e.Size, size)
	end
	e.Rate = base * (rate or 1)
	e:SetAttribute("Rate", e.Rate)
	e:SetAttribute("ShadeEffect", true)
	e.Parent = parent
	return e
end

-- A ribbon trailing a pair of attachments (`a0` and `a1` set its width)
function Fx.ribbon(
	parent: Instance,
	a0: Attachment,
	a1: Attachment,
	lifetime: number,
	color: ColorSequence,
	fade: NumberSequence?
): Trail
	local trail = Instance.new("Trail")
	trail.Name = "FxRibbon"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = lifetime
	trail.Color = color
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = false
	trail.MinLength = 0.05
	trail.Transparency = fade or keys({ 0, 0.15, 0.6, 0.5, 1, 1 })
	trail.WidthScale = keys({ 0, 1, 1, 0.2 })
	trail:SetAttribute("ShadeEffect", true)
	trail.Parent = parent
	return trail
end

function Fx.attachment(parent: Instance, name: string): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a:SetAttribute("ShadeEffect", true)
	a.Parent = parent
	return a
end

-- A straight glowing bolt between two attachments (arcs, rays, halos)
function Fx.beam(
	parent: Instance,
	a0: Attachment,
	a1: Attachment,
	width0: number,
	width1: number,
	color: ColorSequence,
	fade: NumberSequence?
): Beam
	local beam = Instance.new("Beam")
	beam.Name = "FxBeam"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = width0
	beam.Width1 = width1
	beam.Color = color
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = 1
	beam.Transparency = fade or NumberSequence.new(0)
	beam:SetAttribute("ShadeEffect", true)
	beam.Parent = parent
	return beam
end

-- A living fire on a hearth (owner, 2026-10-28: the Teal Brazier's fire "should
-- actually flow like fire"): tall tongues rising and narrowing off a bed `width`
-- across, licks flicking off its edges and a few embers drifting up, `height` studs
-- tall, from the core colour `core` to `edge` at the tips. Emits from `parent`, a
-- flat part at the bed.
function Fx.hearth(
	parent: BasePart,
	width: number,
	height: number,
	core: Color3,
	edge: Color3
): { ParticleEmitter }
	local flames = Instance.new("ParticleEmitter")
	flames.Name = "FxHearth"
	flames.Texture = texture("fxFlame", BUILT_IN.fire)
	flames.LightEmission = 1
	flames.LightInfluence = 0
	flames.EmissionDirection = Enum.NormalId.Top
	flames.SpreadAngle = Vector2.new(8, 8)
	flames.Rate = 22
	flames.Lifetime = NumberRange.new(0.7, 1.1)
	flames.Speed = NumberRange.new(height * 0.55, height * 0.9)
	flames.Acceleration = Vector3.new(0, height * 0.6, 0)
	flames.Drag = 1.6
	flames.Rotation = NumberRange.new(-12, 12)
	flames.RotSpeed = NumberRange.new(-30, 30)
	flames.Size = keys({ 0, width * 0.42, 0.35, width * 0.36, 0.75, width * 0.18, 1, 0 })
	flames.Transparency = keys({ 0, 0.55, 0.12, 0.1, 0.6, 0.35, 1, 1 })
	flames.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, core),
		ColorSequenceKeypoint.new(0.45, core:Lerp(edge, 0.6)),
		ColorSequenceKeypoint.new(1, edge),
	})
	flames.ZOffset = 0.5
	flames.Parent = parent
	local licks = flames:Clone()
	licks.Name = "FxHearthLicks"
	licks.Rate = 16
	licks.SpreadAngle = Vector2.new(24, 24)
	licks.Lifetime = NumberRange.new(0.35, 0.6)
	licks.Speed = NumberRange.new(height * 0.8, height * 1.3)
	licks.Size = keys({ 0, width * 0.2, 0.5, width * 0.14, 1, 0 })
	licks.Transparency = keys({ 0, 0.3, 0.3, 0.25, 1, 1 })
	licks.RotSpeed = NumberRange.new(-90, 90)
	licks.ZOffset = 0.8
	licks.Parent = parent
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "FxHearthEmbers"
	embers.Texture = texture("fxStar", BUILT_IN.sparkle)
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.EmissionDirection = Enum.NormalId.Top
	embers.SpreadAngle = Vector2.new(30, 30)
	embers.Rate = 5
	embers.Lifetime = NumberRange.new(1.4, 2.4)
	embers.Speed = NumberRange.new(height * 0.3, height * 0.6)
	embers.Drag = 0.8
	embers.Size = keys({ 0, 0.22, 0.5, 0.16, 1, 0 })
	embers.Transparency = keys({ 0, 0.1, 0.8, 0.4, 1, 1 })
	embers.Color = ColorSequence.new(core)
	embers.Parent = parent
	return { flames, licks, embers }
end

return Fx
