--!strict
-- The underwater look, graded by depth on this client: clear and bright in the
-- shallows, deep blue lower down, a creepy dim teal in the trench, and a little
-- warmer inside the hub; each biome's own water colour over that (Config/Biomes
-- `water`), and the haze thickening toward the map's edge so it never shows. Plus
-- drifting marine snow around the camera, so the water always reads as water even
-- when nothing else is moving.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Biomes = require(ReplicatedStorage.Shared.Biomes)
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
-- wasteland"); only the Trench goes darker still, and that is OceanController.setDark
-- (murky and dim, not black).
-- Clearer and brighter, Subnautica-style (owner, 2026-10-18: "Visibility needs to be
-- turned up too ... went a bit too blue and its hard to see anywhere other than the
-- kelp area. Think Subnautica"): every grade is thinner (shelf 0.68 → 0.53, the deep
-- floor 0.86 → 0.62), lighter (the deep floor's exposure −0.52 → −0.24) and its haze
-- less saturated, and the deep grades' tints keep more red. These are the depth's
-- light; each biome's own water colour (Config/Biomes `water`) is blended over them
-- by `biomeWater`. The shelf's tints stay as they were (×0.84–0.87 red: gold skins
-- read gold, lilac lilac; playtest 2026-10-10 and owner 2026-10-11).
local GRADES: { Grade } = {
	{
		y = World.surfaceY,
		color = Color3.fromRGB(76, 150, 172),
		decay = Color3.fromRGB(30, 88, 110),
		density = 0.5,
		tint = Color3.fromRGB(224, 238, 246),
		brightness = 0.03,
		saturation = 0.06,
		exposure = 0.05,
		sight = 900,
	},
	{
		y = World.surfaceY * 0.55,
		color = Color3.fromRGB(62, 132, 160),
		decay = Color3.fromRGB(22, 74, 98),
		density = 0.51,
		tint = Color3.fromRGB(216, 232, 244),
		brightness = 0.01,
		saturation = 0.04,
		exposure = -0.02,
		sight = 800,
	},
	{
		-- The shelf floor: a biome's `haze` and `decay` are its colours in this light
		y = World.seabedY,
		color = Color3.fromRGB(48, 114, 146),
		decay = Color3.fromRGB(16, 60, 86),
		density = 0.53,
		tint = Color3.fromRGB(216, 232, 246),
		brightness = 0,
		saturation = 0.02,
		exposure = -0.1,
		sight = 650,
	},
	{
		y = World.deep.floorY * 0.5,
		-- Open water (the Open Blue's middle depths, where the Megalodon roams): a
		-- clear deep blue it can be seen coming through, never black (owner,
		-- 2026-10-09 and 2026-10-18)
		color = Color3.fromRGB(34, 92, 132),
		decay = Color3.fromRGB(10, 48, 82),
		density = 0.58,
		tint = Color3.fromRGB(204, 220, 240),
		brightness = -0.01,
		saturation = 0,
		exposure = -0.16,
		sight = 560,
	},
	{
		y = World.deep.floorY,
		color = Color3.fromRGB(26, 74, 112),
		decay = Color3.fromRGB(8, 38, 70),
		density = 0.62,
		tint = Color3.fromRGB(198, 214, 236),
		brightness = -0.02,
		saturation = -0.03,
		exposure = -0.24,
		sight = 440,
	},
	{
		y = World.deep.ventsFloorY,
		-- At this depth it is the Trench's upper canyon only: the Vents themselves
		-- blend toward VENTS_GRADE (below) by their sector
		color = Color3.fromRGB(20, 58, 96),
		decay = Color3.fromRGB(6, 28, 58),
		density = 0.64,
		tint = Color3.fromRGB(198, 206, 228),
		brightness = -0.01,
		saturation = -0.05,
		exposure = -0.26,
		sight = 380,
	},
	{
		y = World.trench.floorY,
		-- Thick, not opaque: the Trench's black is the dark (no light), not fog, so
		-- what glows or is lit can still be seen (playtest 2026-10-08: density 1.0 and
		-- exposure -3.6 left it pure black even with a lantern)
		color = Color3.fromRGB(8, 26, 48),
		decay = Color3.fromRGB(3, 10, 24),
		density = 0.68,
		tint = Color3.fromRGB(176, 192, 222),
		brightness = -0.04,
		saturation = -0.14,
		exposure = -0.45,
		sight = 300,
	},
}

-- The Hydrothermal Vents' own water (PC 2026-10-17 round 2, V1: the basins' floor
-- was near black from 100 studs and almost black wide): in the Vents' sector, from
-- a little over the deep floor down, the grade blends toward this, thinner and
-- warmer, lit by the lava, so distance fades into a dark red-brown murk rather than
-- black, and lighter (exposure −0.15, was −0.32). By sector, not depth, so the
-- Trench's canyon at the same depth keeps its own look (it's dark).
local VENTS_ID = "HydrothermalVents"
local VENTS_GRADE: Grade = {
	y = World.deep.ventsFloorY,
	-- (PC 2026-10-18: the far floor still dark at 100 studs, Lilac magenta-pink: a
	-- thinner, lighter warm murk the floor's silhouette reads against, and a near
	-- neutral tint, so the warm light alone carries the colour; thinner again with
	-- the rest of the sea, 0.68 → 0.6, owner 2026-10-18)
	color = Color3.fromRGB(112, 62, 44),
	decay = Color3.fromRGB(64, 32, 24),
	density = 0.6,
	tint = Color3.fromRGB(230, 222, 218),
	brightness = 0.02,
	saturation = -0.02,
	exposure = -0.1,
	sight = 460,
}
-- Studs over the deep floor: none of it from VENTS_FADE up, all of it from VENTS_FULL
-- down (a fish looking down into a basin from over its lip already sees it)
local VENTS_FADE, VENTS_FULL = 140, 40

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function luminance(color: Color3): number
	return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
end

-- Biome water (Config/Biomes `water`): how much of the camera's water is each
-- biome's. 1 well inside it, easing across `BIOME_FEATHER` studs centred on each
-- border (along the radius and round the sector alike), so crossing one blends the
-- water over ~90 studs instead of switching it; the shares are normalised to 1.
local BIOME_FEATHER = 90
local MAP_EDGE = World.boundsRadius
local CENTER = World.hub.center
local REFERENCE = GRADES[3] -- the shelf floor's light, the one a biome's colours are given in
local REFERENCE_HAZE, REFERENCE_DECAY = luminance(REFERENCE.color), luminance(REFERENCE.decay)
local shares: { [string]: number } = {}

local function membership(biome: Biomes.Biome, radius: number, angle: number): number
	local inner = if biome.radiusFrom <= 0
		then 1
		else smoothstep((radius - biome.radiusFrom) / BIOME_FEATHER + 0.5)
	local outer = if biome.radiusTo >= MAP_EDGE
		then 1
		else 1 - smoothstep((radius - biome.radiusTo) / BIOME_FEATHER + 0.5)
	local share = inner * outer
	local span = (biome.angleTo - biome.angleFrom) % 360
	if share <= 0 or span == 0 then
		return share -- (a whole ring: the Kelp Shallows)
	end
	-- Degrees inside the sector from its nearer edge (negative outside), in studs
	local along = (angle - biome.angleFrom) % 360
	local degrees = if along < span
		then math.min(along, span - along)
		else -math.min(along - span, 360 - along)
	return share * smoothstep(math.rad(degrees) * math.max(radius, 1) / BIOME_FEATHER + 0.5)
end

local function shareBiomes(position: Vector3)
	local offset = position - CENTER
	local radius = Vector2.new(offset.X, offset.Z).Magnitude
	local angle = math.deg(math.atan2(offset.Z, offset.X)) % 360
	local total = 0
	for _, biome in Config.Biomes.list do
		local share = if biome.live then membership(biome, radius, angle) else 0
		shares[biome.id] = share
		total += share
	end
	if total > 1e-6 then
		for id, share in shares do
			shares[id] = share / total
		end
	end
end

-- The depth's grade with the biomes' water blended over it (`count`: how much the
-- biomes count here, less in the hub). Their colours keep the depth's light (scaled
-- by its luminance against the shelf floor's), their tints multiply its tint.
local function biomeWater(base: Grade, count: number): Grade
	local hazeLight = luminance(base.color) / REFERENCE_HAZE
	local decayLight = luminance(base.decay) / REFERENCE_DECAY
	local total = 0
	local hazeR, hazeG, hazeB, decayR, decayG, decayB = 0, 0, 0, 0, 0, 0
	local tintR, tintG, tintB = 0, 0, 0
	local density, exposure, saturation = 0, 0, 0
	for _, biome in Config.Biomes.list do
		local water = biome.water
		local share = (shares[biome.id] or 0) * count
		if water == nil or share <= 0 then
			continue
		end
		total += share
		hazeR += water.haze.R * share
		hazeG += water.haze.G * share
		hazeB += water.haze.B * share
		decayR += water.decay.R * share
		decayG += water.decay.G * share
		decayB += water.decay.B * share
		tintR += water.tint.R * share
		tintG += water.tint.G * share
		tintB += water.tint.B * share
		density += water.density * share
		exposure += water.exposure * share
		saturation += water.saturation * share
	end
	if total <= 1e-4 then
		return base
	end
	local keep = 1 - total
	local function mix(own: Color3, r: number, g: number, b: number, light: number): Color3
		return Color3.new(
			math.min(own.R * keep + r * light, 1),
			math.min(own.G * keep + g * light, 1),
			math.min(own.B * keep + b * light, 1)
		)
	end
	return {
		y = base.y,
		color = mix(base.color, hazeR, hazeG, hazeB, hazeLight),
		decay = mix(base.decay, decayR, decayG, decayB, decayLight),
		density = base.density + density,
		tint = Color3.new(
			base.tint.R * (keep + tintR),
			base.tint.G * (keep + tintG),
			base.tint.B * (keep + tintB)
		),
		brightness = base.brightness,
		saturation = base.saturation + saturation,
		exposure = base.exposure + exposure,
		-- (the classic fog's sight line, only used without an Atmosphere: ~6% less a
		-- 0.01 of density)
		sight = base.sight * math.exp(-6 * density),
	}
end

-- How far into the Vents' warm murk the camera is: its share of the Vents (eased at
-- the sector's borders like every biome's water) by how far down a basin it is
local function ventsAt(position: Vector3, count: number): number
	local depth = math.clamp((World.deep.floorY + VENTS_FADE - position.Y) / (VENTS_FADE - VENTS_FULL), 0, 1)
	return depth * (shares[VENTS_ID] or 0) * count
end

-- The map's edge must never show (owner, 2026-10-18: "we dont want to see the map
-- barrier either"): past the barrier (World.boundsRadius) the Terrain runs on another
-- ~700 studs and the Horizon walls stand 1,400 out, so with the clearer water the
-- haze thickens toward EDGE_DENSITY over the last EDGE_RAMP studs inside the barrier,
-- and from the barrier itself nothing past it reads. The Horizon walls take the
-- water's own colour (`tintHorizon`), so where anything of them is left it is water.
-- (240, was 380: the Megalodon roams 1,000–1,440 out, and its fights sat in the
-- edge's haze; PC 2026-10-19, MG1)
local EDGE_RAMP, EDGE_DENSITY = 240, 0.72

local function edgeAt(position: Vector3): number
	local offset = position - CENTER
	local radius = Vector2.new(offset.X, offset.Z).Magnitude
	return smoothstep((radius - (MAP_EDGE - EDGE_RAMP)) / EDGE_RAMP)
end

local horizonWalls: { BasePart } = {}
local horizonLooked = -math.huge
local horizonColor: Color3? = nil

local function tintHorizon(color: Color3, now: number)
	-- (they stream in like everything else: look again every few seconds)
	if now - horizonLooked > 3 then
		horizonLooked = now
		table.clear(horizonWalls)
		local world = workspace:FindFirstChild("World")
		local bounds = world and world:FindFirstChild("Bounds")
		if bounds then
			for _, child in bounds:GetChildren() do
				if child.Name == "Horizon" and child:IsA("BasePart") then
					table.insert(horizonWalls, child)
				end
			end
		end
		horizonColor = nil
	end
	local last = horizonColor
	if
		last
		and math.abs(last.R - color.R) + math.abs(last.G - color.G) + math.abs(last.B - color.B) < 0.004
	then
		return
	end
	horizonColor = color
	for _, wall in horizonWalls do
		wall.Color = color
	end
end

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
-- Dark biomes (the Trench): most of the light goes, the water turns murky, and
-- lamps and glowing things carry the rest
local darkTarget = 0
local dark, darkVelocity = 0, 0 -- the dark this player sees (less where their own light lifts it)
local water, waterVelocity = 0, 0 -- the water's own dark, before anyone's light
local reveal = 0 -- how much of the dark this fish's own light lifts (LampController)
-- No shadow pass in the dark: the Trench spent 484 of its 1,014 draw calls on
-- shadows under a sun faded to 14% (PC 2026-10-20 round 2). Off once the water is
-- SHADOWS_OFF dark, back on under SHADOWS_ON (so a fish on the edge can't flip it),
-- to whatever the server had set.
local SHADOWS_OFF, SHADOWS_ON = 0.6, 0.35
local shadowsHeld: boolean? = nil -- the server's GlobalShadows while ours are off
local glow = 0
-- Plankton glow in the deepest water (PlanktonController): a very faint blue-green
-- light, most noticeable in the pitch dark
local GLOW_TINT = Color3.fromRGB(70, 150, 150)
-- What's left of the light in the dark, and with the plankton's glow at its
-- thickest: dim and cold, never black (owner, 2026-10-11: "a creepy vibe for the
-- trench ... darker but not pitch black"); the haze is a murky green-teal, so rock,
-- fish and the boss loom out of it as shapes (Config/Tuning `light`)
local lightTuning = Config.Tuning.light
local DARK_AMBIENT = lightTuning.ambient
local GLOW_AMBIENT = lightTuning.plankton
local DARK_WATER, DARK_DECAY = lightTuning.water, lightTuning.decay
local DARK_DENSITY = lightTuning.density
local DARK_GRADE = lightTuning.grade

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

-- Set by `snap`: the next frame takes the look where the camera is at once
local snapping = false

local function step(dt: number)
	local position = workspace.CurrentCamera.CFrame.Position
	if snapping then
		-- A cut (the start screen's shots, its dive into the den): no easing across it
		snapping = false
		current = nil
		hubBlend, hubVelocity = if Layout.inHub(position) then 1 else 0, 0
		dark, darkVelocity = darkTarget * (1 - reveal), 0
		water, waterVelocity = darkTarget, 0
		tide, tideVelocity = tideTarget * (1 - hubBlend), 0
		tideDim, tideDimVelocity = tideDimTarget * (1 - hubBlend), 0
	end
	-- A den is graded like the hub whatever storey you're on (its interior sits
	-- at the hub's height, far outside the map: Layout.denOrigin), with no biome's
	-- water and no edge
	local inDen = Layout.denAt(position) ~= nil
	local target = gradeAt(if inDen then Config.World.hub.denFloorY else position.Y)
	local edge = 0
	if not inDen then
		-- Each biome's own water, less of it inside the hub's cavern
		shareBiomes(position)
		local count = 1 - hubBlend
		target = biomeWater(target, count)
		local vents = ventsAt(position, count)
		if vents > 0 then
			target = blendGrades(target, VENTS_GRADE, vents)
		end
		-- Thicker toward the map's edge (applied last, over the boss's clearing and
		-- the dark too), so nothing past it shows
		edge = edgeAt(position)
		if edge > 0 and target.density < EDGE_DENSITY then
			-- (a copy: gradeAt can hand back one of GRADES itself)
			target = table.clone(target)
			target.sight *= math.exp(-6 * (EDGE_DENSITY - target.density) * edge)
		end
	end
	-- Ease toward the target look, so crossing a depth never pops
	local blended = if current then blendGrades(current, target, Spring.alpha(2.5, dt)) else target
	current = blended
	hubBlend, hubVelocity =
		Spring.number(hubBlend, hubVelocity, if Layout.inHub(position) then 1 else 0, 3, dt)

	local atmo = atmosphere
	if atmo and atmo.Parent then
		atmo.Color = blended.color
		atmo.Decay = blended.decay
		-- (a boss's fight light clears it by 20%: the Megalodon at ~200 studs read as an
		-- outline over haze, PC 2026-10-19; the map's edge is thickened after this)
		atmo.Density = blended.density * (1 - hubBlend * 0.25) * (1 - bossLight * 0.2)
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
	if shadowsHeld == nil and water > SHADOWS_OFF then
		shadowsHeld = Lighting.GlobalShadows
		Lighting.GlobalShadows = false
	elseif shadowsHeld ~= nil and water < SHADOWS_ON then
		Lighting.GlobalShadows = shadowsHeld :: boolean
		shadowsHeld = nil
	end
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
		-- A dim, cold light is left, a little more where the plankton is thick, and a
		-- sliver of the light from far above
		local floor = DARK_AMBIENT:Lerp(GLOW_AMBIENT, glow)
		Lighting.Brightness = day.brightness * (1 - d * (1 - lightTuning.sun))
		Lighting.Ambient = day.ambient:Lerp(floor, d)
		Lighting.OutdoorAmbient = day.outdoor:Lerp(floor, d)
		Lighting.EnvironmentDiffuseScale = day.diffuse * (1 - d * (1 - lightTuning.environment))
		Lighting.EnvironmentSpecularScale = day.specular * (1 - d * (1 - lightTuning.environment))
		-- The creepy grade: cold, drained, a touch more contrast. Never a strong tint
		-- or an exposure cut on top: those crushed what glows (retest 2026-10-08: tint
		-- x0.5 and exposure -1 left the lantern's pool, glowing skins and plankton
		-- barely visible).
		grade.TintColor = grade.TintColor:Lerp(DARK_GRADE.tint, d * 0.9)
		grade.Brightness *= 1 - d
		grade.Saturation = grade.Saturation * (1 - d) + DARK_GRADE.saturation * d
		grade.Contrast += DARK_GRADE.contrast * d
		Lighting.ExposureCompensation = Lighting.ExposureCompensation * (1 - d) + d * lightTuning.exposure
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
	local haze = atmosphere
	if haze and haze.Parent then
		-- The map's edge: thicker toward it whatever else cleared the water
		if edge > 0 and haze.Density < EDGE_DENSITY then
			haze.Density += (EDGE_DENSITY - haze.Density) * edge
		end
		-- The Horizon walls in the water's colour as the camera sees it (its haze
		-- toward its shade), the dark's included
		tintHorizon(haze.Decay:Lerp(haze.Color, 0.4), os.clock())
	end
end

-- The camera has cut somewhere else (the start screen's shots): the next frame
-- takes that place's water, light and dark at once instead of easing into them
function OceanController.snap()
	snapping = true
end

-- Whether the camera is in a dark biome (0..1; BiomeController sets it) and
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

-- The sky as water (Config/Textures `skyUp`/`skySide`/`skyDown`; owner, 2026-10-28:
-- "way to get rid of the skybox?"): wherever the sky peeks past the haze it reads as
-- more water, lit from above and darkening down. Only on this client, and only once
-- all three images are uploaded (until then Roblox's default sky stays).
local function waterSky()
	local textures = Config.Textures :: { [string]: number }
	local up, side, down = textures.skyUp or 0, textures.skySide or 0, textures.skyDown or 0
	if up == 0 or side == 0 or down == 0 then
		return
	end
	task.spawn(function()
		local sky = Lighting:WaitForChild("OceanSky", 30)
		if sky == nil or not sky:IsA("Sky") then
			return
		end
		sky.SkyboxUp = `rbxassetid://{up}`
		sky.SkyboxDn = `rbxassetid://{down}`
		for _, face in { "SkyboxBk", "SkyboxFt", "SkyboxLf", "SkyboxRt" } do
			(sky :: any)[face] = `rbxassetid://{side}`
		end
	end)
end

function OceanController.start()
	waterSky()
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
