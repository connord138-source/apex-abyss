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
		-- The shelf's tints keep more red than they did (×0.77 turned gold skins lime,
		-- playtest 2026-10-10); deeper down the water goes bluer, as it should
		tint = Color3.fromRGB(222, 238, 246),
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
		tint = Color3.fromRGB(214, 232, 244),
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
		tint = Color3.fromRGB(216, 232, 246),
		brightness = -0.02,
		saturation = 0,
		exposure = -0.28,
		sight = 300,
	},
	{
		y = World.deep.floorY * 0.5,
		-- Open water (the Open Blue's middle depths, where the Megalodon roams): a
		-- rich deep blue that swallows things a few hundred studs off, never black
		-- (owner, 2026-10-09)
		color = Color3.fromRGB(20, 84, 138),
		decay = Color3.fromRGB(8, 40, 86),
		density = 0.8,
		tint = Color3.fromRGB(186, 212, 240),
		brightness = -0.03,
		saturation = -0.02,
		exposure = -0.4,
		sight = 260,
	},
	{
		y = World.deep.floorY,
		color = Color3.fromRGB(14, 64, 118),
		decay = Color3.fromRGB(5, 30, 70),
		density = 0.86,
		tint = Color3.fromRGB(176, 202, 236),
		brightness = -0.05,
		saturation = -0.06,
		exposure = -0.52,
		sight = 220,
	},
	{
		y = World.deep.ventsFloorY,
		-- Thinner than the floor above it, so the chimneys' glow reads across a basin
		-- (playtest 2026-10-08: a chimney 45 studs off was only a silhouette)
		color = Color3.fromRGB(10, 48, 92),
		decay = Color3.fromRGB(4, 22, 52),
		density = 0.84,
		tint = Color3.fromRGB(176, 196, 228),
		brightness = -0.04,
		saturation = -0.08,
		exposure = -0.5,
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
-- Dread (a world boss near): the water turns colder and greyer toward this and the
-- contrast beats like a heart. It never darkens the picture: near a boss the fight
-- has to be seen (owner, 2026-10-09: "how the hell will anyone fight anything in
-- pitch black or low visibility let alone a boss"); the edges darken instead
-- (BossController's vignette)
local DREAD_TINT = Color3.fromRGB(170, 192, 218)

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
local beatNow = 0
-- A world boss's fight light (BossController): near one the water clears and the
-- dark lifts, so the fight reads
local bossLightTarget = 0
local bossLight, bossLightVelocity = 0, 0
-- The tide's faint colour in the water (Config/Tides `tint`; TideController), and a
-- Bioluminescent Night's dimmer sea
local tideColor = Color3.new(1, 1, 1)
local tideTarget, tideDimTarget = 0, 0
local tide, tideVelocity = 0, 0
local tideDim, tideDimVelocity = 0, 0
local blindTarget = 0
local blind, blindVelocity = 0, 0
local ink: ColorCorrectionEffect
-- Pitch dark biomes (the Trench): the light goes out, so only lamps and glowing
-- things show
local darkTarget = 0
local dark, darkVelocity = 0, 0 -- the dark this player sees (less where their own light lifts it)
local water, waterVelocity = 0, 0 -- the water's own dark, before anyone's light
local reveal = 0 -- how much of the dark this fish's own light lifts (LampController)
local glow = 0
-- Plankton glow in the deepest water (PlanktonController): a very faint blue-green
-- light, most noticeable in the pitch dark
local GLOW_TINT = Color3.fromRGB(70, 150, 150)
-- What's left of the light in the full dark (owner, 2026-10-09: "about 5-10%
-- visibility with no light"), and with the plankton's glow at its thickest; the haze
-- is a very deep blue, so rock and fish read as dim shapes against it
local lightTuning = Config.Tuning.light
local BLACK_AMBIENT = lightTuning.ambient
local GLOW_AMBIENT = lightTuning.plankton
local DARK_WATER, DARK_DECAY = lightTuning.water, lightTuning.decay
local DARK_DENSITY = 0.6

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
		atmo.Density = blended.density * (1 - hubBlend * 0.25) * (1 - bossLight * 0.22)
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
	beatNow = beat * dread
	bossLight, bossLightVelocity = Spring.number(bossLight, bossLightVelocity, bossLightTarget, 2, dt)
	tide, tideVelocity = Spring.number(tide, tideVelocity, tideTarget * (1 - hubBlend), 0.6, dt)
	tideDim, tideDimVelocity =
		Spring.number(tideDim, tideDimVelocity, tideDimTarget * (1 - hubBlend), 0.6, dt)
	grade.TintColor =
		blended.tint:Lerp(HUB_TINT, hubBlend * 0.6):Lerp(tideColor, tide):Lerp(DREAD_TINT, dread * 0.4)
	grade.Brightness = blended.brightness + bossLight * 0.03
	grade.Saturation = blended.saturation - dread * 0.3 + bossLight * 0.12
	grade.Contrast = 0.06 + dread * (0.06 + beat * 0.12)
	Lighting.ExposureCompensation = blended.exposure + hubBlend * 0.1 + bossLight * 0.35 - tideDim * 0.25
	-- The dark: the light itself goes out (sun, ambient, the environment's
	-- reflections), so only what glows or is lit shows: lamps, glowing skins, the
	-- plankton, the walls' glow specks. Fog and a crushed exposure hid all of those
	-- too (playtest 2026-10-08). A fish's own light lifts its view of the dark by
	-- how rare the light is (Config/Tuning light.sources `reveal`).
	-- Near a boss the dark lifts by more than half, whatever light you carry
	dark, darkVelocity =
		Spring.number(dark, darkVelocity, darkTarget * (1 - reveal) * (1 - bossLight * 0.6), 1.8, dt)
	water, waterVelocity = Spring.number(water, waterVelocity, darkTarget, 1.8, dt)
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
		-- With the light gone, no colour grade or exposure cut on top: they only
		-- crushed what glows (retest 2026-10-08: tint x0.5 and exposure -1 left the
		-- lantern's pool, glowing skins and plankton barely visible). The water thins
		-- too, so a lamp's pool and the glow round you read; the black haze still
		-- swallows anything unlit.
		grade.TintColor = grade.TintColor:Lerp(Color3.new(1, 1, 1), d * 0.9)
		grade.Brightness *= 1 - d
		grade.Saturation *= 1 - d * 0.7
		Lighting.ExposureCompensation = Lighting.ExposureCompensation * (1 - d) + d * 0.25
		local atmosphereNow = atmosphere
		if atmosphereNow and atmosphereNow.Parent then
			atmosphereNow.Color = atmosphereNow.Color:Lerp(DARK_WATER, d)
			atmosphereNow.Decay = atmosphereNow.Decay:Lerp(DARK_DECAY, d)
			atmosphereNow.Density = atmosphereNow.Density + (DARK_DENSITY - atmosphereNow.Density) * d
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
-- how much of the dark this fish's light lifts (0..1; LampController sets it)
function OceanController.setDark(amount: number)
	darkTarget = math.clamp(amount, 0, 1)
end

function OceanController.setReveal(amount: number)
	reveal = math.clamp(amount, 0, 0.9)
end

-- How dark the water round the camera is right now (0..1), before this fish's own
-- light lifts it: glowing skins and bosses scale by it, so a rare light never dims
-- itself on its holder's screen (playtest 2026-10-09: Legendary, Mythic and Trophy
-- shades came out 2.07 / 2.34 / 2.37 instead of 2.6 / 3.2 / 3.4)
function OceanController.darkness(): number
	return math.clamp(water, 0, 1)
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

-- How strongly a world boss is felt (0..1; BossController sets it): colder,
-- greyer water and a heartbeat in the contrast, never a darker picture
function OceanController.setDread(amount: number)
	dreadTarget = math.clamp(amount, 0, 1)
end

-- The tide's colour in the water (`amount` 0..1 of it) and how much a dark tide dims
-- the sea (0..1); eased over a few seconds, and never inside the hub
function OceanController.setTide(color: Color3, amount: number, dim: number)
	tideColor = color
	tideTarget = math.clamp(amount, 0, 1)
	tideDimTarget = math.clamp(dim, 0, 1)
end

-- The heartbeat's pulse right now, scaled by the dread (0..1), for the vignette
function OceanController.heartbeat(): number
	return beatNow
end

-- How close the camera is to a boss fight (0..1; BossController sets it): the water
-- round it clears and the dark lifts so the boss can be seen and fought
function OceanController.setBossLight(amount: number)
	bossLightTarget = math.clamp(amount, 0, 1)
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
