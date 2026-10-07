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
}

-- From the surface down; heights in between blend
local GRADES: { Grade } = {
	{
		y = World.surfaceY,
		color = Color3.fromRGB(70, 168, 190),
		decay = Color3.fromRGB(30, 92, 120),
		density = 0.36,
		tint = Color3.fromRGB(236, 252, 255),
		brightness = 0.04,
		saturation = 0.08,
		exposure = 0.15,
	},
	{
		y = 120,
		color = Color3.fromRGB(46, 128, 162),
		decay = Color3.fromRGB(16, 62, 96),
		density = 0.42,
		tint = Color3.fromRGB(222, 242, 252),
		brightness = 0.01,
		saturation = 0.04,
		exposure = 0,
	},
	{
		y = World.seabedY,
		color = Color3.fromRGB(28, 92, 132),
		decay = Color3.fromRGB(10, 40, 72),
		density = 0.5,
		tint = Color3.fromRGB(204, 228, 246),
		brightness = -0.02,
		saturation = 0,
		exposure = -0.25,
	},
	{
		y = World.deep.floorY,
		color = Color3.fromRGB(14, 52, 88),
		decay = Color3.fromRGB(6, 24, 46),
		density = 0.58,
		tint = Color3.fromRGB(176, 200, 230),
		brightness = -0.06,
		saturation = -0.1,
		exposure = -0.8,
	},
	{
		y = World.trench.floorY,
		color = Color3.fromRGB(6, 20, 40),
		decay = Color3.fromRGB(2, 8, 20),
		density = 0.64,
		tint = Color3.fromRGB(150, 172, 214),
		brightness = -0.12,
		saturation = -0.2,
		exposure = -1.4,
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
-- Pitch dark biomes (the Trench): near-black unless this fish carries a lamp
local darkTarget = 0
local dark, darkVelocity = 0, 0
local lit = false
local DARK_TINT = Color3.fromRGB(26, 30, 48)

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
	-- The dark: a lamp holds a little of the light; everyone else sees only the glow specks
	dark, darkVelocity = Spring.number(dark, darkVelocity, darkTarget * (if lit then 0.45 else 1), 1.8, dt)
	if dark > 0.001 then
		grade.TintColor = grade.TintColor:Lerp(DARK_TINT, dark * 0.8)
		grade.Brightness -= dark * 0.5
		grade.Saturation -= dark * 0.5
		Lighting.ExposureCompensation -= dark * 2.6
		local atmosphereNow = atmosphere
		if atmosphereNow and atmosphereNow.Parent then
			atmosphereNow.Density = math.min(atmosphereNow.Density + dark * 0.25, 1)
		end
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
