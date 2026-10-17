--!strict
-- Particle looks shared by the skin effects (Shared/SkinFx) and the boost trails
-- (TrailController). Each preset makes one ParticleEmitter sized by the fish's
-- length `L` and tinted `c` (and `c2` where it blends): mist rolling off a ghost,
-- stars drifting off a nebula, dark grit sucked into a void, foam streaking off a
-- riptide. Textures come from Config/Textures `fx*` once they're uploaded
-- (assets/textures/fx_*.png), and from Roblox's own particle images until then.
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

-- One emitter of a preset, parented to `parent` (a part: it emits from the part's
-- box; an attachment: from a point). `rate` scales its usual rate.
function Fx.emitter(
	parent: Instance,
	preset: Preset,
	L: number,
	c: Color3,
	c2: Color3?,
	rate: number?
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
		base = 12
		e.Lifetime = NumberRange.new(1.4, 2.4)
		e.Speed = NumberRange.new(L * 0.02, L * 0.1)
		e.Drag = 1
		e.Size = keys({ 0, 0, 0.2, L * 0.06, 0.4, L * 0.015, 0.6, L * 0.06, 1, 0 })
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
		base = 7
		e.Lifetime = NumberRange.new(0.6, 1.2)
		e.Speed = NumberRange.new(L * 0.2, L * 0.6)
		e.Drag = 2
		e.Size = keys({ 0, 0, 0.3, L * 0.06, 1, 0 })
	elseif preset == "crystal" then
		-- Hard star flashes on the facets, gone in a blink
		e.Texture = texture("fxStar", BUILT_IN.sparkle)
		base = 8
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.Lifetime = NumberRange.new(0.25, 0.45)
		e.Speed = NumberRange.new(0, L * 0.02)
		e.Rotation = NumberRange.new(0, 90)
		e.Size = keys({ 0, 0, 0.4, L * 0.14, 1, 0 })
	elseif preset == "gold" then
		-- Gold dust glittering down off it
		base = 18
		e.Lifetime = NumberRange.new(1, 1.6)
		e.Speed = NumberRange.new(L * 0.02, L * 0.06)
		e.Acceleration = Vector3.new(0, -L * 0.2, 0)
		e.Drag = 0.8
		e.Size = keys({ 0, L * 0.03, 0.5, L * 0.025, 1, 0 })
		e.Transparency = keys({ 0, 0, 0.7, 0.2, 1, 1 })
	elseif preset == "tropical" then
		-- Many-coloured motes, a reef's worth
		base = 10
		e.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 196, 40)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(60, 230, 160)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(70, 160, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 110, 255)),
		})
		e.Lifetime = NumberRange.new(1.2, 2)
		e.Speed = NumberRange.new(L * 0.04, L * 0.12)
		e.Drag = 1
		e.Size = keys({ 0, 0, 0.3, L * 0.05, 1, 0 })
	elseif preset == "starfall" then
		-- Stars dropping off it like a meteor shower
		base = 9
		e.Lifetime = NumberRange.new(0.9, 1.4)
		e.Speed = NumberRange.new(0, L * 0.05)
		e.Acceleration = Vector3.new(0, -L * 0.9, 0)
		e.Size = keys({ 0, L * 0.07, 0.6, L * 0.04, 1, 0 })
	elseif preset == "embers" then
		-- Sparks rising off a fire, yellow cooling to red
		base = 14
		e.Lifetime = NumberRange.new(0.8, 1.6)
		e.Speed = NumberRange.new(L * 0.05, L * 0.2)
		e.Acceleration = Vector3.new(0, L * 0.5, 0)
		e.Drag = 1
		e.Size = keys({ 0, L * 0.035, 1, 0 })
	elseif preset == "drips" then
		-- Molten drops falling off the belly
		base = 6
		e.Lifetime = NumberRange.new(0.6, 0.9)
		e.Speed = NumberRange.new(0, L * 0.03)
		e.Acceleration = Vector3.new(0, -L * 1.4, 0)
		e.Size = keys({ 0, L * 0.04, 1, L * 0.02 })
	elseif preset == "ink" then
		-- Dark ink curling off and hanging in the water
		e.Texture = texture("fxMist", BUILT_IN.smoke)
		base = 8
		e.LightEmission = 0
		e.LightInfluence = 0.35
		e.Lifetime = NumberRange.new(1.8, 2.8)
		e.Speed = NumberRange.new(L * 0.03, L * 0.1)
		e.Drag = 1
		e.RotSpeed = NumberRange.new(-30, 30)
		e.Rotation = NumberRange.new(0, 360)
		e.Size = keys({ 0, L * 0.1, 1, L * 0.5 })
		e.Transparency = keys({ 0, 1, 0.15, 0.45, 1, 1 })
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
		base = 8
		e.LightEmission = 0.5
		e.LightInfluence = 0.7
		e.Lifetime = NumberRange.new(1.2, 2)
		e.Speed = NumberRange.new(L * 0.02, L * 0.08)
		e.Acceleration = Vector3.new(0, L * 0.45, 0)
		e.Drag = 2
		e.Size = keys({ 0, L * 0.015, 0.3, L * 0.04, 1, L * 0.045 })
		e.Transparency = keys({ 0, 0.3, 0.7, 0.45, 1, 1 })
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

return Fx
