--!strict
-- The underwater look, graded by depth on this client: turquoise and bright in
-- the shallows, deep blue lower down, near-black in the trench, and a little
-- warmer inside the hub. Plus drifting marine snow around the camera, so the
-- water always reads as water even when nothing else is moving.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Spring = require(script.Parent.Parent.Spring)

local World = Config.World

type Grade = {
	y: number, -- camera height this look belongs to
	color: Color3, -- atmosphere
	decay: Color3,
	density: number,
	tint: Color3, -- color correction
	brightness: number,
	saturation: number,
	exposure: number,
	sight: number, -- studs of water you can see through (classic fog, for when no Atmosphere drives the look)
}

-- From the surface down; heights in between blend. The water thickens and darkens
-- with depth so no depth ever sees every other (owner, 2026-10-08: "swimming to the
-- surface allows you to see all the way down ... similar to the underwater feel of
-- Subnautica"); the deep floor is a deep blue, never black ("a large black
-- wasteland"); only the Trench goes near-black, and that is OceanController.setDark.
local GRADES: { Grade } = {
	{
		y = World.surfaceY,
		color = Color3.fromRGB(54, 146, 172),
		decay = Color3.fromRGB(18, 72, 104),
		density = 0.68,
		tint = Color3.fromRGB(196, 232, 244),
		brightness = 0.02,
		saturation = 0.06,
		exposure = 0,
		sight = 420,
	},
	{
		y = World.surfaceY * 0.55,
		color = Color3.fromRGB(40, 122, 156),
		decay = Color3.fromRGB(12, 56, 92),
		density = 0.72,
		tint = Color3.fromRGB(186, 222, 240),
		brightness = 0,
		saturation = 0.03,
		exposure = -0.1,
		sight = 360,
	},
	{
		y = World.seabedY,
		color = Color3.fromRGB(26, 96, 138),
		decay = Color3.fromRGB(8, 42, 78),
		density = 0.76,
		tint = Color3.fromRGB(200, 226, 246),
		brightness = -0.02,
		saturation = 0,
		exposure = -0.28,
		sight = 300,
	},
	{
		y = World.deep.floorY * 0.5,
		color = Color3.fromRGB(18, 76, 124),
		decay = Color3.fromRGB(6, 34, 72),
		density = 0.82,
		tint = Color3.fromRGB(184, 208, 236),
		brightness = -0.04,
		saturation = -0.04,
		exposure = -0.48,
		sight = 250,
	},
	{
		y = World.deep.floorY,
		color = Color3.fromRGB(12, 58, 108),
		decay = Color3.fromRGB(4, 28, 64),
		density = 0.88,
		tint = Color3.fromRGB(172, 198, 232),
		brightness = -0.06,
		saturation = -0.08,
		exposure = -0.62,
		sight = 210,
	},
	{
		y = World.deep.ventsFloorY,
		color = Color3.fromRGB(10, 48, 92),
		decay = Color3.fromRGB(4, 22, 52),
		density = 0.9,
		tint = Color3.fromRGB(166, 190, 226),
		brightness = -0.07,
		saturation = -0.12,
		exposure = -0.7,
		sight = 180,
	},
	{
		y = World.trench.floorY,
		-- Thick, not opaque: the Trench's black is the dark (no light), not fog, so
		-- what glows or is lit can still be seen (playtest 2026-10-08: density 1.0 and
		-- exposure -3.6 left it pure black even with a lantern)
		color = Color3.fromRGB(5, 18, 38),
		decay = Color3.fromRGB(2, 8, 20),
		density = 0.88,
		tint = Color3.fromRGB(150, 172, 214),
		brightness = -0.06,
		saturation = -0.2,
		exposure = -0.75,
		sight = 160,
	},
}

local HUB_TINT = Color3.fromRGB(246, 236, 222)
-- Dread (a world boss near): the water darkens and desaturates toward this, and
-- the contrast beats like a heart
local DREAD_TINT = Color3.fromRGB(150, 120, 130)

local OceanController = {}

local atmosphere: Atmosphere? = nil
local grade: ColorCorrectionEffect
local bloom: BloomEffect
local snowHolder: Part
local current: Grade? = nil
local hubBlend, hubVelocity = 0, 0
local dreadTarget = 0
local dread, dreadVelocity = 0, 0
local heart = 0
local blindTarget = 0
local blind, blindVelocity = 0, 0
local ink: ColorCorrectionEffect
-- Pitch dark biomes (the Trench): the light goes out, so only lamps and glowing
-- things show
local darkTarget = 0
local dark, darkVelocity = 0, 0
local lit = false
local glow = 0
local DARK_TINT = Color3.fromRGB(26, 30, 48)
-- Plankton glow in the deepest water (PlanktonController): a very faint blue-green
-- light, most noticeable in the pitch dark
local GLOW_TINT = Color3.fromRGB(70, 150, 150)
-- What's left of the light in the full dark, and the plankton's very faint share
local BLACK_AMBIENT = Color3.fromRGB(2, 3, 6)
local GLOW_AMBIENT = Color3.fromRGB(12, 30, 34)
local DARK_WATER, DARK_DECAY = Color3.fromRGB(3, 7, 14), Color3.fromRGB(1, 3, 6)

-- The light the server set (WorldService.setupLighting), read when the dark comes
-- and put back when it lifts
type Light = { brightness: number, ambient: Color3, outdoor: Color3, diffuse: number, specular: number }
local daylight: Light? = nil

local function blendGrades(a: Grade, b: Grade, t: number): Grade
	return {
		y = a.y + (b.y - a.y) * t,
		color = a.color:Lerp(b.color, t),
		decay = a.decay:Lerp(b.decay, t),
		density = a.density + (b.density - a.density) * t,
		tint = a.tint:Lerp(b.tint, t),
		brightness = a.brightness + (b.brightness - a.brightness) * t,
		saturation = a.saturation + (b.saturation - a.saturation) * t,
		exposure = a.exposure + (b.exposure - a.exposure) * t,
		sight = a.sight + (b.sight - a.sight) * t,
	}
end

local function gradeAt(y: number): Grade
	if y >= GRADES[1].y then
		return GRADES[1]
	end
	for i = 1, #GRADES - 1 do
		local upper, lower = GRADES[i], GRADES[i + 1]
		if y >= lower.y then
			return blendGrades(upper, lower, (upper.y - y) / (upper.y - lower.y))
		end
	end
	return GRADES[#GRADES]
end

local function step(dt: number)
	local position = workspace.CurrentCamera.CFrame.Position
	local target = gradeAt(position.Y)
	-- Ease toward the target look, so crossing a depth never pops
	local blended = if current then blendGrades(current, target, Spring.alpha(2.5, dt)) else target
	current = blended
	hubBlend, hubVelocity =
		Spring.number(hubBlend, hubVelocity, if Layout.inHub(position) then 1 else 0, 3, dt)

	local atmo = atmosphere
	if atmo and atmo.Parent then
		atmo.Color = blended.color
		atmo.Decay = blended.decay
		atmo.Density = blended.density * (1 - hubBlend * 0.25)
	else
		atmosphere = Lighting:FindFirstChild("OceanAtmosphere") :: Atmosphere?
	end
	-- Classic fog as well: Roblox ignores it while an Atmosphere exists, and it takes
	-- over with the same sight line if the Atmosphere ever goes
	Lighting.FogColor = blended.decay
	Lighting.FogStart = blended.sight * 0.15
	Lighting.FogEnd = blended.sight * (1 + hubBlend * 0.5)
	dread, dreadVelocity = Spring.number(dread, dreadVelocity, dreadTarget, 2.5, dt)
	heart += dt * (0.9 + dread * 0.9) * 2 * math.pi
	-- A double thump: lub-dub, then quiet
	local cycle = heart % (2 * math.pi)
	local beat = math.max(math.sin(cycle) ^ 6, math.sin(cycle - 0.9) ^ 6 * 0.6)
	grade.TintColor = blended.tint:Lerp(HUB_TINT, hubBlend * 0.6):Lerp(DREAD_TINT, dread * 0.55)
	grade.Brightness = blended.brightness - dread * 0.08
	grade.Saturation = blended.saturation - dread * 0.45
	grade.Contrast = 0.06 + dread * (0.1 + beat * 0.16)
	Lighting.ExposureCompensation = blended.exposure + hubBlend * 0.1 - dread * 0.55
	-- The dark: the light itself goes out (sun, ambient, the environment's
	-- reflections), so only what glows or is lit shows: lamps, glowing skins, the
	-- plankton, the walls' glow specks. Fog and a crushed exposure hid all of those
	-- too (playtest 2026-10-08). A lamp holder's own view is a touch less dark.
	dark, darkVelocity = Spring.number(dark, darkVelocity, darkTarget * (if lit then 0.85 else 1), 1.8, dt)
	if dark > 0.001 then
		local day: Light = daylight
			or {
				brightness = Lighting.Brightness,
				ambient = Lighting.Ambient,
				outdoor = Lighting.OutdoorAmbient,
				diffuse = Lighting.EnvironmentDiffuseScale,
				specular = Lighting.EnvironmentSpecularScale,
			}
		daylight = day
		local d = math.min(dark, 1)
		-- The plankton's very faint light is all that's left (owner: "to give very
		-- very faint light")
		local floor = BLACK_AMBIENT:Lerp(GLOW_AMBIENT, glow)
		Lighting.Brightness = day.brightness * (1 - d)
		Lighting.Ambient = day.ambient:Lerp(floor, d)
		Lighting.OutdoorAmbient = day.outdoor:Lerp(floor, d)
		Lighting.EnvironmentDiffuseScale = day.diffuse * (1 - d)
		Lighting.EnvironmentSpecularScale = day.specular * (1 - d)
		grade.TintColor = grade.TintColor:Lerp(DARK_TINT, d * 0.3)
		grade.Saturation -= d * 0.15
		Lighting.ExposureCompensation -= d * 0.3
		local atmosphereNow = atmosphere
		if atmosphereNow and atmosphereNow.Parent then
			atmosphereNow.Color = atmosphereNow.Color:Lerp(DARK_WATER, d)
			atmosphereNow.Decay = atmosphereNow.Decay:Lerp(DARK_DECAY, d)
		end
		-- Glowing things bloom a little more in the dark
		bloom.Intensity = 0.55 + d * 0.35
		bloom.Threshold = 1.35 - d * 0.25
	elseif daylight then
		local day = daylight :: Light
		Lighting.Brightness = day.brightness
		Lighting.Ambient = day.ambient
		Lighting.OutdoorAmbient = day.outdoor
		Lighting.EnvironmentDiffuseScale = day.diffuse
		Lighting.EnvironmentSpecularScale = day.specular
		bloom.Intensity = 0.55
		bloom.Threshold = 1.35
		daylight = nil
	end
	if glow > 0.001 then
		grade.TintColor = grade.TintColor:Lerp(GLOW_TINT, glow * 0.06)
	end
	-- Ink: inside a squid's cloud the water goes near-black
	blind, blindVelocity = Spring.number(blind, blindVelocity, blindTarget, 4, dt)
	ink.Enabled = blind > 0.01
	ink.Brightness = -0.92 * blind
	ink.Saturation = -0.8 * blind
	ink.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(40, 24, 50), blind)
	snowHolder.CFrame = CFrame.new(position)
end

-- Whether the camera is in a pitch-dark biome (0..1; BiomeController sets it) and
-- whether this fish carries a lamp (LampController sets it)
function OceanController.setDark(amount: number)
	darkTarget = math.clamp(amount, 0, 1)
end

function OceanController.setLit(value: boolean)
	lit = value
end

-- How dark the water round the camera is right now (0..1)
function OceanController.darkness(): number
	return math.clamp(dark, 0, 1)
end

-- How thick the glowing plankton is around the camera (0..1); PlanktonController
-- sets it
function OceanController.setGlow(amount: number)
	glow = math.clamp(amount, 0, 1)
end

-- How deep in a boss's ink cloud the camera is (0..1); PredatorController sets it.
function OceanController.setBlind(amount: number)
	blindTarget = math.clamp(amount, 0, 1)
end

-- How much a world boss's presence darkens the water (0..1); BossController sets it.
function OceanController.setDread(amount: number)
	dreadTarget = math.clamp(amount, 0, 1)
end

function OceanController.start()
	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "OceanGrade"
	grade.Contrast = 0.06
	grade.Parent = Lighting
	ink = Instance.new("ColorCorrectionEffect")
	ink.Name = "InkBlind"
	ink.Enabled = false
	ink.Parent = Lighting
	bloom = Instance.new("BloomEffect")
	bloom.Name = "OceanBloom"
	bloom.Intensity = 0.55
	bloom.Size = 28
	bloom.Threshold = 1.35
	bloom.Parent = Lighting

	-- Marine snow: specks drifting in a box that follows the camera
	snowHolder = Instance.new("Part")
	snowHolder.Name = "MarineSnow"
	snowHolder.Anchored = true
	snowHolder.CanCollide = false
	snowHolder.CanQuery = false
	snowHolder.CanTouch = false
	snowHolder.Transparency = 1
	snowHolder.Size = Vector3.new(90, 50, 90)
	snowHolder.Parent = workspace.CurrentCamera
	local snow = Instance.new("ParticleEmitter")
	snow.Shape = Enum.ParticleEmitterShape.Box
	snow.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	snow.Rate = 60
	snow.Lifetime = NumberRange.new(5, 9)
	snow.Speed = NumberRange.new(0.2, 0.8)
	snow.SpreadAngle = Vector2.new(180, 180)
	snow.Acceleration = Vector3.new(0, -0.15, 0)
	snow.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.09),
		NumberSequenceKeypoint.new(0.8, 0.07),
		NumberSequenceKeypoint.new(1, 0),
	})
	snow.Transparency = NumberSequence.new(0.35, 0.8)
	snow.LightEmission = 0.4
	snow.LightInfluence = 0.6
	snow.Color = ColorSequence.new(Color3.fromRGB(230, 245, 250))
	snow.LockedToPart = false
	snow.Parent = snowHolder

	atmosphere = Lighting:FindFirstChild("OceanAtmosphere") :: Atmosphere?
	RunService.RenderStepped:Connect(step)
end

return OceanController
