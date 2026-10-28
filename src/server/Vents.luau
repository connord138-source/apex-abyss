--!strict
-- The Hydrothermal Vents' field, dressed (owner, 2026-10-19: "The vents part of the
-- map needs more substance too"): parts on the ground VentsPlan laid out and
-- Shelf.luau sculpted between the basins, so the whole sector reads as a working
-- hydrothermal field with places to go, not a mud plain with holes in it.
--
--   * THE FORGE: a lava lake glowing in its crater with dark crust rafting on it and
--     a soft glare hanging over it (it carries through the murk where a light can't),
--     lava running down its runnels (bright cores over deep-red rims, laid on the
--     real flank by raycast and widening as they run) to oval pools at its foot,
--     fumaroles steaming on its flanks, its shoulder cone's own lava, light and ash,
--     and a column of ash rising some 300 studs from the crater in three stretches
--     (lit orange low, murky grey high, so it carries in the deep blue over the
--     vents' murk), with embers;
--   * BLACK SMOKERS: a glowing throat on every spire (on its real top), a tall
--     billowing black plume, heat shimmer, small side throats on the flanges,
--     sulfide crust (ochre, rust, sulfur) on them, a light at each complex; and the
--     basins' older chimneys dressed to match (craggy rock flanges with a hot seam
--     under them and drips off them, staining, side throats);
--   * COLUMNAR BASALT: hex columns (three blocks turned 60°, dark basalt with
--     lighter tops) in two terraced outcrops and the causeway from the Forge's foot
--     toward the hub;
--   * MINERAL TERRACES: rimstone shelves cascading down two basin walls, each with a
--     warm glowing pool behind a scalloped rim, flowstone draped between them;
--   * THE BRINE POOL: a dark glassy lake on a basin floor with a faint teal glow
--     under it, a crust and mussel shoreline and mist rolling over it;
--   * TUBE WORMS (pale tubes with flared collars, crimson plumes fanned out like
--     feather dusters, their feet in mineral crust): three forests (round the
--     tallest smoker complex, a basin chimney and the brine pool's far shore) and
--     clumps round the smokers and chimneys, with MUSSEL and CLAM BEDS;
--   * a glow over the two biggest crust patches, and embers and mineral flecks
--     drifting over the field.
--
-- Rock (columns, terrace shelves) is solid and lives under Workspace.World.Biomes.Vents,
-- where Shared/Ground looks: predators climb over it, no shell or dig site lands in
-- it, and every top stays under VentsPlan.ceiling, so no prey school is lifted over
-- it. Decor neither collides, takes rays nor fires Touched. Everything is anchored,
-- SmoothPlastic, Neon or (the brine) Glass: never a toon-overridden material. It
-- builds 2,950–3,270 parts and 12–14 lights (PARTS_CAP stops the small life past
-- 3,300), and clears scattered boulders and plankton out of its landmarks (tidy).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local VentsPlan = require(script.Parent.VentsPlan)

local World = Config.World
local deep = World.deep

local Vents = {}

export type Ground = (x: number, z: number) -> (Vector3?, Vector3?)
export type Stats = {
	parts: number,
	solid: number,
	glow: number,
	lights: number,
	emitters: number,
	columns: number,
	chimneys: number,
	steps: number,
	worms: number,
	mussels: number,
	clumps: number,
	forests: number,
	beds: number,
	tidied: number,
}

local TAU = 2 * math.pi
local HALF = math.pi / 2
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local COLORS = {
	basalt = { Color3.fromRGB(46, 48, 56), Color3.fromRGB(54, 56, 64), Color3.fromRGB(40, 42, 50) },
	basaltTop = { Color3.fromRGB(88, 90, 98), Color3.fromRGB(100, 100, 106), Color3.fromRGB(80, 84, 94) },
	lava = Color3.fromRGB(255, 156, 56),
	lavaHot = Color3.fromRGB(255, 214, 118),
	lavaRim = Color3.fromRGB(168, 38, 14),
	raft = Color3.fromRGB(44, 34, 34),
	minerals = { Color3.fromRGB(198, 142, 54), Color3.fromRGB(150, 66, 34), Color3.fromRGB(230, 208, 72) },
	-- (the sulfide on the chimneys' flanges: the same minerals, duller, so they don't ring gold)
	crust = { Color3.fromRGB(168, 116, 56), Color3.fromRGB(128, 64, 38), Color3.fromRGB(160, 146, 70) },
	-- (the chimneys' flanges: near the columns' own basalt, so they read as growing out of it)
	flange = { Color3.fromRGB(84, 88, 98), Color3.fromRGB(94, 96, 104), Color3.fromRGB(76, 80, 90) },
	-- (the hot water trapped under a flange)
	seam = Color3.fromRGB(214, 78, 32),
	-- Rimstone: cream, ochre and rust, and the warm water standing on it
	travertine = { Color3.fromRGB(204, 182, 136), Color3.fromRGB(184, 130, 72), Color3.fromRGB(150, 86, 50) },
	terracePool = Color3.fromRGB(236, 146, 64),
	-- Giant tube worms: pale chitin tubes (stained low down on the old ones), a paler
	-- collar at the mouth, crimson plumes, and the mineral crust round their feet
	tube = { Color3.fromRGB(196, 192, 180), Color3.fromRGB(182, 180, 172), Color3.fromRGB(206, 200, 186) },
	tubeBase = { Color3.fromRGB(150, 138, 114), Color3.fromRGB(134, 126, 108), Color3.fromRGB(162, 146, 116) },
	collar = Color3.fromRGB(220, 214, 200),
	plume = { Color3.fromRGB(206, 24, 40), Color3.fromRGB(184, 16, 34), Color3.fromRGB(226, 44, 52) },
	wormCrust = { Color3.fromRGB(80, 74, 68), Color3.fromRGB(92, 84, 74), Color3.fromRGB(70, 66, 62) },
	mussel = {
		Color3.fromRGB(34, 38, 56),
		Color3.fromRGB(28, 32, 46),
		Color3.fromRGB(40, 46, 66),
		Color3.fromRGB(74, 58, 40),
	},
	clam = Color3.fromRGB(200, 194, 176),
	clamLip = Color3.fromRGB(96, 88, 80),
	brine = Color3.fromRGB(14, 22, 34),
	brineGlow = Color3.fromRGB(34, 120, 130),
	brineCrust = Color3.fromRGB(176, 176, 166),
	brineCrustDark = Color3.fromRGB(132, 130, 120),
	throat = Color3.fromRGB(255, 120, 40),
}
local LIGHT = {
	lava = Color3.fromRGB(255, 132, 60),
	smoker = Color3.fromRGB(255, 140, 64),
	terrace = Color3.fromRGB(255, 200, 104),
	brine = Color3.fromRGB(70, 200, 210),
	crust = Color3.fromRGB(255, 112, 50),
}

-- The most parts the field builds: the small life (worms, shells) is left out past it
-- (a whole field, its life included, builds 2,950–3,270 over the seeds tried)
local PARTS_CAP = 3300

local rng = Random.new(World.seed + 99)
local groundOf: Ground = function(_x: number, _z: number): (Vector3?, Vector3?)
	return nil, nil
end
local function freshStats(): Stats
	return {
		parts = 0,
		solid = 0,
		glow = 0,
		lights = 0,
		emitters = 0,
		columns = 0,
		chimneys = 0,
		steps = 0,
		worms = 0,
		mussels = 0,
		clumps = 0,
		forests = 0,
		beds = 0,
		tidied = 0,
	}
end
local stats: Stats = freshStats()

local function pick(list: { Color3 }): Color3
	return list[rng:NextInteger(1, #list)]
end

-- ---------------------------------------------------------------------------
-- Parts
-- ---------------------------------------------------------------------------

local function setup(p: BasePart, name: string, size: Vector3, cframe: CFrame, color: Color3, solid: boolean)
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = SMOOTH
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	p.CanCollide = solid
	p.CanQuery = solid
	p.CastShadow = solid
	stats.parts += 1
	if solid then
		stats.solid += 1
	end
end

local function rock(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	setup(p, name, size, cframe, color, true)
	p.Parent = parent
	return p
end

local function trim(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	setup(p, name, size, cframe, color, false)
	p.Parent = parent
	return p
end

local function glow(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	transparency: number?
): Part
	local p = trim(parent, name, size, cframe, color)
	p.Material = NEON
	p.Transparency = transparency or 0
	stats.glow += 1
	return p
end

-- No sphere-mesh lumps (owner, 2026-10-20: "I hate the spheres that are all over the
-- place that were clearly placeholders that never received a design update"): every
-- piece here is a cut, flat-faced shape in the low-poly look of the hex columns.

local function wedge(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): WedgePart
	local p = Instance.new("WedgePart")
	setup(p, name, size, cframe, color, false)
	p.Parent = parent
	return p
end

-- A faceted chip filling about `size`: two blocks an eighth of a turn apart, the
-- second a little lower and narrower, so it reads as a broken stone or a crust plate
local function chip(parent: Instance, name: string, cframe: CFrame, size: Vector3, color: Color3): Part
	local p = trim(parent, name, size * Vector3.new(0.8, 1, 0.8), cframe, color)
	trim(
		parent,
		name,
		size * Vector3.new(0.72, 0.78, 0.72),
		cframe * CFrame.new(0, -size.Y * 0.11, 0) * CFrame.Angles(0, math.pi / 4, 0),
		color
	)
	return p
end

-- A mineral streak running down a flank from `on` (its middle, on the surface; `out`
-- the surface's normal): two thin wedges back to back, wide at the top and coming to
-- a point below, like a drip of sulfur down the rock
local function streak(
	parent: Instance,
	name: string,
	on: Vector3,
	out: Vector3,
	width: number,
	length: number,
	color: Color3
)
	local base = CFrame.fromMatrix(on + out * 0.2, out, Vector3.yAxis)
	local size = Vector3.new(0.35, length, width / 2)
	wedge(parent, name, size, base * CFrame.new(0, 0, width / 4) * CFrame.Angles(math.pi, 0, 0), color)
	wedge(
		parent,
		name,
		size,
		base * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, width / 4) * CFrame.Angles(math.pi, 0, 0),
		color
	)
end

-- A flat disc lying level, its top at `top`
local function disc(
	parent: Instance,
	name: string,
	center: Vector3,
	top: number,
	radius: number,
	thickness: number,
	color: Color3,
	solid: boolean
): Part
	local p = Instance.new("Part")
	setup(
		p,
		name,
		Vector3.new(thickness, radius * 2, radius * 2),
		CFrame.new(center.X, top - thickness / 2, center.Z) * CFrame.Angles(0, 0, HALF),
		color,
		solid
	)
	p.Shape = Enum.PartType.Cylinder
	p.Parent = parent
	return p
end

-- A vent's glowing mouth on a top at `at`: a hot disc set level into the rock with a
-- dark rim round it (it was a glowing ball sat on top)
local function mouthGlow(parent: Instance, name: string, at: Vector3, radius: number)
	local hot = disc(parent, name, at, at.Y + 0.35, radius, 0.7, COLORS.throat, false)
	hot.Material = NEON
	hot.CastShadow = false
	stats.glow += 1
	disc(parent, `{name}Rim`, at, at.Y + 0.2, radius * 1.35, 0.6, COLORS.raft, false)
end

-- A cylinder from `a` to `b`
local function rod(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	radius: number,
	color: Color3
): Part
	local p = trim(
		parent,
		name,
		Vector3.new((b - a).Magnitude, radius * 2, radius * 2),
		CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, HALF, 0),
		color
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- An invisible part that holds lights and emitters (`size` is the box particles
-- leave from)
local function holder(parent: Instance, name: string, cframe: CFrame, size: Vector3): Part
	local p = trim(parent, name, size, cframe, Color3.new(1, 1, 1))
	p.Transparency = 1
	p.CastShadow = false
	return p
end

local function light(part: BasePart, color: Color3, range: number, brightness: number)
	local made = Instance.new("PointLight")
	made.Color = color
	made.Range = range
	made.Brightness = brightness
	made.Shadows = false
	made.Parent = part
	stats.lights += 1
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function groundY(x: number, z: number, fallback: number): number
	local hit = groundOf(x, z)
	return if hit then hit.Y else fallback
end

-- ---------------------------------------------------------------------------
-- Particles
-- ---------------------------------------------------------------------------

type Puff = {
	rate: number,
	life: { number },
	speed: { number },
	size: { number }, -- at birth, halfway, at the end
	fade: { number }, -- transparency at birth, at 60%
	colors: { Color3 }, -- birth to end
	rise: number?,
	drift: Vector3?,
	spread: number?,
	drag: number?,
	glow: number?, -- LightEmission
	lit: number?, -- LightInfluence
	texture: string?,
}

local function emit(part: BasePart, name: string, puff: Puff): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = puff.texture or SMOKE
	e.Rate = puff.rate
	e.Lifetime = NumberRange.new(puff.life[1], puff.life[2])
	e.Speed = NumberRange.new(puff.speed[1], puff.speed[2])
	e.EmissionDirection = Enum.NormalId.Top
	local spread = puff.spread or 12
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Acceleration = (puff.drift or Vector3.zero) + Vector3.new(0, puff.rise or 0, 0)
	e.Drag = puff.drag or 0.4
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, puff.size[1]),
		NumberSequenceKeypoint.new(0.5, puff.size[2]),
		NumberSequenceKeypoint.new(1, puff.size[3]),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, puff.fade[1]),
		NumberSequenceKeypoint.new(0.6, puff.fade[2]),
		NumberSequenceKeypoint.new(1, 1),
	})
	if #puff.colors == 1 then
		e.Color = ColorSequence.new(puff.colors[1])
	elseif #puff.colors == 2 then
		e.Color = ColorSequence.new(puff.colors[1], puff.colors[2])
	else
		e.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, puff.colors[1]),
			ColorSequenceKeypoint.new(0.4, puff.colors[2]),
			ColorSequenceKeypoint.new(1, puff.colors[3]),
		})
	end
	e.LightEmission = puff.glow or 0
	e.LightInfluence = puff.lit or 0.4
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-14, 14)
	e.Parent = part
	stats.emitters += 1
	return e
end

-- A black smoker's plume at its throat (`scale` by the spire)
local function blackSmoke(part: BasePart, scale: number)
	emit(part, "BlackSmoke", {
		rate = 6 + 8 * scale,
		life = { 6, 9 },
		speed = { 7, 11 },
		size = { 2.5 * scale + 1, 9 * scale + 2, 18 * scale + 3 },
		fade = { 0.2, 0.45 },
		colors = { Color3.fromRGB(30, 26, 30), Color3.fromRGB(18, 16, 20) },
		rise = 2,
		spread = 10,
		drag = 0.45,
		lit = 0.4,
	})
end

-- The plume carried on higher up, slower and wider, drifting
local function blackSmokeHigh(part: BasePart)
	emit(part, "BlackSmokeHigh", {
		rate = 5,
		life = { 10, 14 },
		speed = { 3, 5 },
		size = { 14, 28, 40 },
		fade = { 0.45, 0.62 },
		colors = { Color3.fromRGB(40, 34, 34), Color3.fromRGB(30, 28, 32) },
		rise = 0.8,
		drift = Vector3.new(0.5, 0, 0.3),
		spread = 16,
		drag = 0.3,
		lit = 0.5,
	})
end

local function shimmer(part: BasePart, size: number)
	emit(part, "HeatShimmer", {
		rate = 5,
		life = { 1.2, 2 },
		speed = { 2, 4 },
		size = { size * 0.4, size, size * 1.3 },
		fade = { 0.8, 0.86 },
		colors = { Color3.fromRGB(255, 150, 90), Color3.fromRGB(200, 90, 50) },
		spread = 18,
		glow = 0.5,
		lit = 0.1,
	})
end

local function embers(part: BasePart, rate: number)
	emit(part, "Embers", {
		rate = rate,
		life = { 3, 6 },
		speed = { 2, 5 },
		size = { 0.25, 0.45, 0 },
		fade = { 0.1, 0.35 },
		colors = { Color3.fromRGB(255, 196, 96), Color3.fromRGB(255, 84, 30) },
		rise = 0.8,
		spread = 30,
		glow = 1,
		lit = 0,
		texture = SPARKLE,
	})
end

-- ---------------------------------------------------------------------------
-- The Forge
-- ---------------------------------------------------------------------------

-- A glowing strip of lava from `a` to `b`, lying along the ground between them
local function lavaStrip(parent: Instance, a: Vector3, b: Vector3, width: number, rim: boolean)
	local span = b - a
	local frame = CFrame.lookAt((a + b) / 2, b)
	local lift = frame.UpVector * (if rim then 0.2 else 0.35)
	glow(
		parent,
		if rim then "LavaRim" else "Lava",
		Vector3.new(width, if rim then 0.5 else 0.6, span.Magnitude + width * 0.6),
		frame + lift,
		if rim then COLORS.lavaRim else COLORS.lava
	)
end

local function forge(parent: Instance, plan: VentsPlan.Plan)
	local f = plan.forge
	if f == nil then
		return
	end
	local m = model(parent, "Forge")
	local c = f.center
	local summit = c.Y + f.height
	-- The lava lake: the crater's floor (Shelf fills it with CrackedLava), lit up
	local lakeY = groundY(c.X, c.Z, summit - f.crater + 9)
	if lakeY > summit - 2 or lakeY < summit - f.crater - 6 then
		lakeY = summit + 9 - f.crater
	end
	local lake = disc(m, "LavaLake", c, lakeY + 0.3, f.crater * 0.6, 0.4, COLORS.lava, false)
	lake.Material = NEON
	lake.CastShadow = false
	stats.glow += 1
	local core = disc(m, "LavaLakeCore", c, lakeY + 0.4, f.crater * 0.22, 0.2, COLORS.lavaHot, false)
	core.Material = NEON
	stats.glow += 1
	for _ = 1, 5 do
		local a, d = rng:NextNumber(0, TAU), rng:NextNumber(0.25, 0.5) * f.crater
		local size = rng:NextNumber(2.5, 5)
		chip(
			m,
			"CrustRaft",
			CFrame.new(c.X + math.cos(a) * d, lakeY + 0.45, c.Z + math.sin(a) * d)
				* CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
			Vector3.new(size * 1.4, 0.6, size),
			COLORS.raft
		)
	end
	local crater =
		holder(m, "CraterGlow", CFrame.new(c.X, lakeY + 8, c.Z), Vector3.new(f.crater, 2, f.crater))
	light(crater, LIGHT.lava, 60, 3.2)
	embers(crater, 8)
	-- The glare over the lake: big soft self-lit puffs that hang there, so the
	-- crater's glow carries through the murk from far off, where a light (60 studs
	-- at most) doesn't reach
	emit(crater, "Glare", {
		rate = 1.5,
		life = { 3, 4.5 },
		speed = { 0, 0.5 },
		size = { f.crater * 1.2, f.crater * 1.8, f.crater * 2 },
		fade = { 0.8, 0.84 },
		colors = { Color3.fromRGB(255, 150, 70), Color3.fromRGB(255, 100, 40) },
		spread = 180,
		drag = 1,
		glow = 1,
		lit = 0,
	})
	-- The ash column, in three stretches up to ~300 studs over the crater
	local ash1 = holder(
		m,
		"AshColumn",
		CFrame.new(c.X, lakeY + 4, c.Z),
		Vector3.new(f.crater * 0.8, 2, f.crater * 0.8)
	)
	emit(ash1, "Ash", {
		rate = 10,
		life = { 10, 14 },
		speed = { 6, 9 },
		size = { 6, 18, 30 },
		fade = { 0.35, 0.5 },
		colors = { Color3.fromRGB(120, 64, 34), Color3.fromRGB(70, 58, 54), Color3.fromRGB(56, 52, 52) },
		rise = 1.2,
		spread = 14,
		drag = 0.25,
		glow = 0.12,
		lit = 0.5,
	})
	local ash2 = holder(m, "AshColumn", CFrame.new(c.X, summit + 80, c.Z), Vector3.new(24, 6, 24))
	emit(ash2, "Ash", {
		rate = 6,
		life = { 14, 18 },
		speed = { 4, 6 },
		size = { 20, 40, 56 },
		fade = { 0.5, 0.62 },
		colors = { Color3.fromRGB(74, 66, 62), Color3.fromRGB(78, 74, 72) },
		rise = 0.8,
		drift = Vector3.new(0.4, 0, 0.2),
		spread = 18,
		drag = 0.25,
		lit = 0.6,
	})
	local ash3 = holder(m, "AshColumn", CFrame.new(c.X + 10, summit + 160, c.Z + 5), Vector3.new(40, 8, 40))
	emit(ash3, "Ash", {
		rate = 4,
		life = { 16, 22 },
		speed = { 3, 5 },
		size = { 36, 64, 90 },
		fade = { 0.58, 0.7 },
		colors = { Color3.fromRGB(96, 92, 90), Color3.fromRGB(88, 90, 96) },
		rise = 0.5,
		drift = Vector3.new(0.6, 0, 0.3),
		spread = 22,
		drag = 0.2,
		lit = 0.7,
	})
	-- The runnels: lava laid down the real flank (by raycast down each step of the
	-- line Shelf grooved), a pool at each one's foot
	local steps = 30
	for index, heading in f.runnels do
		local top = if index == 1 then 0.97 else 0.9
		-- (a ray straight down a steep groove lands now on its floor, now on its lip:
		-- the heights are kept falling and evened out, so the lava runs in one line)
		local points: { Vector3 } = {}
		for k = 0, steps do
			local t = top * (1 - k / steps)
			local p = VentsPlan.runnelPoint(f, heading, t)
			local hit = groundOf(p.X, p.Z)
			if hit and math.abs(hit.Y - p.Y) < 8 then
				local last = points[#points]
				local y = if last then math.min(hit.Y, last.Y - 0.3) else hit.Y
				table.insert(points, Vector3.new(hit.X, y, hit.Z))
			end
		end
		for k = 2, #points - 1 do
			local a, b, d = points[k - 1], points[k], points[k + 1]
			points[k] = Vector3.new(b.X, (a.Y + b.Y * 2 + d.Y) / 4, b.Z)
		end
		for k = 1, #points - 1 do
			local along = (k - 1) / math.max(#points - 2, 1)
			-- (widening as it runs down, as a flow spreads)
			local width = 2 + 2.4 * along
			lavaStrip(m, points[k], points[k + 1], width, false)
			lavaStrip(m, points[k], points[k + 1], width * 2.1, true)
		end
		local foot = VentsPlan.runnelPoint(f, heading, 0)
		local out = Vector3.new(foot.X - c.X, 0, foot.Z - c.Z).Unit
		local pool = foot + out * 9
		local poolY = groundY(pool.X, pool.Z, c.Y)
		local radius = rng:NextNumber(5, 7)
		-- (flat and level with its crust round it: an oval sphere read as a glowing egg)
		local lavaPool = disc(m, "LavaPool", pool, poolY + 0.25, radius, 0.5, COLORS.lava, false)
		lavaPool.Material = NEON
		for k = 1, 7 do
			local a = k * TAU / 7 + rng:NextNumber(-0.2, 0.2)
			local edge =
				Vector3.new(pool.X + math.cos(a) * radius, poolY + 0.3, pool.Z + math.sin(a) * radius)
			local size = rng:NextNumber(1.8, 3)
			chip(
				m,
				"PoolCrust",
				CFrame.new(edge) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
				Vector3.new(size * 1.3, 0.8, size),
				COLORS.raft
			)
		end
		lavaPool.CastShadow = false
		stats.glow += 1
		if index == 1 then
			-- The spill: a light halfway down its runnel and one over its pool
			local mid = points[math.max(1, math.floor(#points * 0.45))]
			if mid then
				local spot =
					holder(m, "RunnelGlow", CFrame.new(mid + out * 6 + Vector3.new(0, 4, 0)), Vector3.one)
				light(spot, LIGHT.lava, 60, 2)
			end
			local poolGlow = holder(
				m,
				"PoolGlow",
				CFrame.new(pool.X, poolY + 5, pool.Z),
				Vector3.new(radius * 2, 1, radius * 2)
			)
			light(poolGlow, LIGHT.lava, 50, 2.2)
			embers(poolGlow, 3)
		else
			-- A glow halfway down the others too, so every side of the Forge shows a
			-- lit runnel
			local mid = points[math.max(1, math.floor(#points * 0.5))]
			if mid then
				local spot =
					holder(m, "RunnelGlow", CFrame.new(mid + out * 6 + Vector3.new(0, 4, 0)), Vector3.one)
				light(spot, LIGHT.lava, 50, 1.6)
			end
		end
	end
	-- Fumaroles steaming on the flanks, between the runnels
	local made = 0
	for _ = 1, 12 do
		if made >= 4 then
			break
		end
		local heading = rng:NextNumber(0, TAU)
		local clear = true
		for _, runnel in f.runnels do
			if math.abs((heading - runnel + math.pi) % TAU - math.pi) < 0.5 then
				clear = false
			end
		end
		local t = rng:NextNumber(0.25, 0.7)
		local r = VentsPlan.forgeRadius(f, t)
		local hit = groundOf(c.X + math.cos(heading) * r, c.Z + math.sin(heading) * r)
		if not clear or hit == nil or math.abs(hit.Y - (c.Y + f.height * t)) > 14 then
			continue
		end
		made += 1
		glow(
			m,
			"Fumarole",
			Vector3.new(2.2, 0.8, 2.2),
			CFrame.new(hit + Vector3.new(0, 0.2, 0)),
			COLORS.throat
		)
		local vent = holder(m, "Fumarole", CFrame.new(hit + Vector3.new(0, 1, 0)), Vector3.new(2, 1, 2))
		emit(vent, "Steam", {
			rate = 5,
			life = { 4, 6 },
			speed = { 3, 5 },
			size = { 1.5, 5, 9 },
			fade = { 0.55, 0.7 },
			colors = { Color3.fromRGB(196, 186, 172), Color3.fromRGB(150, 146, 142) },
			rise = 1.5,
			spread = 12,
			lit = 0.6,
		})
	end
	-- The shoulder cone: lava in its little crater (Shelf fills it with CrackedLava),
	-- lit, breathing ash, and a tongue of lava over its outer lip
	local shoulder = f.shoulder
	if shoulder then
		local s = shoulder.center
		local top = s.Y + shoulder.height
		local poolY = groundY(s.X, s.Z, top - shoulder.crater + 4)
		if poolY > top or poolY < top - shoulder.crater - 2 then
			poolY = top - shoulder.crater + 4
		end
		local pool = disc(m, "ShoulderLava", s, poolY + 0.3, shoulder.crater * 0.62, 0.4, COLORS.lava, false)
		pool.Material = NEON
		pool.CastShadow = false
		stats.glow += 1
		local vent = holder(m, "ShoulderGlow", CFrame.new(s.X, poolY + 6, s.Z), Vector3.new(6, 2, 6))
		light(vent, LIGHT.lava, 45, 1.8)
		embers(vent, 3)
		emit(vent, "Ash", {
			rate = 4,
			life = { 8, 12 },
			speed = { 4, 7 },
			size = { 4, 12, 20 },
			fade = { 0.4, 0.55 },
			colors = { Color3.fromRGB(110, 62, 36), Color3.fromRGB(64, 56, 54) },
			rise = 1,
			spread = 12,
			drag = 0.3,
			glow = 0.1,
			lit = 0.5,
		})
		-- (outward from the Forge, down its own flank)
		local out = Vector3.new(s.X - c.X, 0, s.Z - c.Z).Unit
		local points: { Vector3 } = {}
		for k = 0, 8 do
			local d = shoulder.crater * 0.8 + (shoulder.base - shoulder.crater) * k / 8
			local hit = groundOf(s.X + out.X * d, s.Z + out.Z * d)
			if hit then
				table.insert(points, hit)
			end
		end
		for k = 1, #points - 1 do
			local width = 1.8 + 1.6 * (k - 1) / math.max(#points - 2, 1)
			lavaStrip(m, points[k], points[k + 1], width, false)
			lavaStrip(m, points[k], points[k + 1], width * 2.1, true)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Black smokers
-- ---------------------------------------------------------------------------

local function smokers(parent: Instance, plan: VentsPlan.Plan)
	for index, smoker in plan.smokers do
		local m = model(parent, `Smokers{index}`)
		for k, spire in smoker.spires do
			local h = spire.height
			local function along(d: number): Vector3
				return spire.foot + spire.tilt * d
			end
			local function radiusAt(d: number): number
				return spire.radius * (1 - 0.5 * math.clamp(d / h, 0, 1))
			end
			-- The throat on its real top (the lip Shelf rounded off)
			local top = along(h)
			local hit = groundOf(top.X, top.Z)
			if hit == nil or math.abs(hit.Y - top.Y) > 10 then
				hit = top + Vector3.new(0, 2, 0)
			end
			assert(hit)
			local scale = math.clamp(h / 140, 0.3, 1)
			-- (a glowing mouth set into the top, not a ball sitting on it)
			mouthGlow(m, "Throat", hit, 1.3 + 1.5 * scale)
			local mouth = holder(
				m,
				"Plume",
				CFrame.new(hit + Vector3.new(0, 2.5, 0)),
				Vector3.new(2, 1, 2) * (1 + scale)
			)
			blackSmoke(mouth, scale)
			shimmer(mouth, 3 + 4 * scale)
			if k == 1 then
				light(mouth, LIGHT.smoker, 55, 2.4)
				embers(mouth, 3)
			end
			if h >= 60 then
				local high =
					holder(m, "PlumeHigh", CFrame.new(hit + Vector3.new(4, 55, 2)), Vector3.new(10, 4, 10))
				blackSmokeHigh(high)
			end
			-- Sulfide crust on its flanges, and now and then a small throat breathing
			-- out at a flange's edge
			for _, d in spire.flanges do
				local center = along(d)
				local reach = radiusAt(d) + 3.5
				for _ = 1, rng:NextInteger(3, 5) do
					local a = rng:NextNumber(0, TAU)
					local spot = center
						+ Vector3.new(math.cos(a), 0, math.sin(a)) * (reach * rng:NextNumber(0.75, 1))
					local onTop = groundOf(spot.X, spot.Z)
					if onTop and math.abs(onTop.Y - (center.Y + 2)) < 4 then
						-- (sulfide crystals: a pair of leaning prisms)
						local size = rng:NextNumber(1.6, 3.2)
						local color = pick(COLORS.minerals)
						for _ = 1, 2 do
							trim(
								m,
								"Sulfide",
								Vector3.new(size * 0.32, size * rng:NextNumber(0.7, 1.2), size * 0.32),
								CFrame.new(onTop + Vector3.new(0, size * 0.3, 0))
									* CFrame.Angles(
										rng:NextNumber(-0.5, 0.5),
										rng:NextNumber(0, TAU),
										rng:NextNumber(-0.5, 0.5)
									),
								color
							)
						end
					end
				end
				if rng:NextNumber() < 0.6 then
					local a = rng:NextNumber(0, TAU)
					local spot = center + Vector3.new(math.cos(a), 0, math.sin(a)) * (reach - 0.5)
					local onTop = groundOf(spot.X, spot.Z)
					if onTop and math.abs(onTop.Y - (center.Y + 2)) < 4 then
						mouthGlow(m, "SideThroat", onTop, 0.8)
						local side =
							holder(m, "SidePlume", CFrame.new(onTop + Vector3.new(0, 1.2, 0)), Vector3.one)
						blackSmoke(side, 0.2)
					end
				end
			end
			-- Sulfur staining down its flank
			for _ = 1, 3 do
				local d = rng:NextNumber(0.15, 0.85) * h
				local a = rng:NextNumber(0, TAU)
				local out = Vector3.new(math.cos(a), 0, math.sin(a))
				local r = radiusAt(d)
				streak(m, "Stain", along(d) + out * (r * 0.95), out, r * 0.8, r * 1.6, pick(COLORS.minerals))
			end
		end
	end
end

-- A chimney's flange (owner, 2026-10-28: the stacked many-sided plates read as flat
-- placeholder plates floating round the column, and their mineral lip as a yellow
-- star): a craggy rock ledge growing out of the column `r` round at `foot`, its top
-- at `at`, reaching up to `out` studs past it. A ring of chunky slabs, each its own
-- reach, thickness, height and slope: their inner ends buried in the column, their
-- tops sloping down and out, most tapering underneath to a thin lip (a flange grows
-- out as a shelf) and the rest blunt, so the edge is ragged. Under two of them a
-- faint hot seam where they meet the column (a real flange traps shimmering hot
-- water under it), a drip hanging off it and on some a little sulfide on top.
-- Returns a spot on its top near the edge (for a side throat).
local FLANGE =
	{ spacing = 9.5, slabs = { 5, 7 }, slope = { 0.12, 0.38 }, tapered = 0.5, seams = 2, seam = 1.4 }

local function flange(m: Instance, foot: Vector3, r: number, at: number, out: number): Vector3
	local count =
		math.clamp(math.floor(TAU * (r + out / 2) / FLANGE.spacing + 0.5), FLANGE.slabs[1], FLANGE.slabs[2])
	local turn = rng:NextNumber(0, TAU)
	local bury = math.min(r * 0.5, 3)
	local slabs: { { frame: CFrame, length: number, width: number, thick: number, tapered: boolean } } = {}
	local edge, longest = foot, -1
	for k = 0, count - 1 do
		local a = turn + (k + rng:NextNumber(-0.12, 0.12)) * TAU / count
		local radial = Vector3.new(math.cos(a), 0, math.sin(a))
		-- (a little off the radial, so the slabs' edges don't line up round it)
		local skew = a + rng:NextNumber(-0.22, 0.22)
		local heading = Vector3.new(math.cos(skew), 0, math.sin(skew))
		local reach = out * rng:NextNumber(0.55, 1.15)
		local length = reach + bury
		local tapered = rng:NextNumber() < FLANGE.tapered
		local thick = if tapered then rng:NextNumber(2, 3.2) else rng:NextNumber(1.1, 1.8)
		local width = TAU * (r + reach / 2) / count * rng:NextNumber(0.95, 1.3)
		local hinge = Vector3.new(foot.X, at + rng:NextNumber(-0.9, 0.6), foot.Z) + radial * (r - bury)
		local frame = CFrame.lookAt(hinge, hinge + heading)
			* CFrame.Angles(-rng:NextNumber(FLANGE.slope[1], FLANGE.slope[2]), 0, rng:NextNumber(-0.18, 0.18))
		local center = frame * CFrame.new(0, -thick / 2, -length / 2)
		local size = Vector3.new(width, thick, length)
		if tapered then
			-- (a wedge turned over: a flat top, the underside rising to a lip at its edge)
			wedge(m, "Flange", size, center * CFrame.Angles(0, 0, math.pi), pick(COLORS.flange))
		else
			trim(m, "Flange", size, center, pick(COLORS.flange))
		end
		table.insert(
			slabs,
			{ frame = frame, length = length, width = width, thick = thick, tapered = tapered }
		)
		if reach > longest then
			longest = reach
			edge = (frame * CFrame.new(0, 0, -(bury + reach * 0.55))).Position
		end
	end
	-- The hot seam: a thin, faint glowing slit hugging the underside of two slabs
	-- across the ring from each other, where they leave the column (a whole ring
	-- read as a neon hoop)
	for k = 1, FLANGE.seams do
		local slab = slabs[(k - 1) * math.floor(#slabs / FLANGE.seams) + 1]
		local s = bury + FLANGE.seam / 2
		-- (along the underside: a tapered slab's rises to its lip)
		local rise = if slab.tapered then math.atan(slab.thick / slab.length) else 0
		local under = if slab.tapered then -slab.thick * (1 - s / slab.length) else -slab.thick
		local hot = glow(
			m,
			"FlangeSeam",
			Vector3.new(slab.width * 0.7, 0.2, FLANGE.seam),
			slab.frame * CFrame.new(0, under - 0.1, -s) * CFrame.Angles(rise, 0, 0),
			COLORS.seam,
			0.5
		)
		hot.CastShadow = false
	end
	-- A drip hanging off the underside: a sharp tooth of rock, the lip's own colour
	do
		local slab = slabs[rng:NextInteger(1, #slabs)]
		local s = slab.length * rng:NextNumber(0.55, 0.85)
		local under = if slab.tapered then -slab.thick * (1 - s / slab.length) else -slab.thick
		local hang = (slab.frame * CFrame.new(rng:NextNumber(-0.25, 0.25) * slab.width, under, -s)).Position
		local across = slab.frame.RightVector
		local u = Vector3.new(across.X, 0, across.Z).Unit * (if rng:NextNumber() < 0.5 then 1 else -1)
		local drop = rng:NextNumber(1.2, 3)
		wedge(
			m,
			"Drip",
			Vector3.new(rng:NextNumber(0.6, 1), rng:NextNumber(0.8, 1.5), drop),
			CFrame.fromMatrix(hang + Vector3.new(0, 0.3 - drop / 2, 0), u:Cross(Vector3.yAxis), u),
			pick(COLORS.flange)
		)
	end
	-- Now and then a little sulfide where the ledge meets the column
	if rng:NextNumber() < 0.5 then
		local slab = slabs[rng:NextInteger(1, #slabs)]
		local spot = (slab.frame * CFrame.new(0, 0, -(bury + rng:NextNumber(0.4, 1.2)))).Position
		local size = rng:NextNumber(1.1, 2)
		local color = pick(COLORS.crust)
		for _ = 1, 2 do
			trim(
				m,
				"Sulfide",
				Vector3.new(size * 0.32, size * rng:NextNumber(0.7, 1.2), size * 0.32),
				CFrame.new(spot + Vector3.new(0, size * 0.25, 0))
					* CFrame.Angles(
						rng:NextNumber(-0.5, 0.5),
						rng:NextNumber(0, TAU),
						rng:NextNumber(-0.5, 0.5)
					),
				color
			)
		end
	end
	return edge
end

-- The basins' older chimneys (Shelf.luau's plain basalt columns, each with its
-- glowing throat and smoke from WorldService ventSmoke) dressed like the smokers'
-- spires: one or two craggy flanges, sulfide staining down the flank, and on some a
-- small side throat breathing out on a flange. All decor (no school or predator
-- meets more than the chimney it already climbs over).
local function chimneyDress(parent: Instance, plan: VentsPlan.Plan)
	local m = model(parent, "ChimneyCrust")
	for _, chimney in plan.chimneys do
		local foot, h, r = chimney.position, chimney.height, chimney.radius
		-- (one buried under rubble or a landmark keeps its plain look)
		local top = groundOf(foot.X, foot.Z)
		if top == nil or math.abs(top.Y - (foot.Y + h)) > 12 then
			continue
		end
		local flanges = if h < 55 then 1 else 2
		for f = 1, flanges do
			local at = foot.Y
				+ h * (if flanges == 1 then 0.55 else ({ 0.42, 0.72 })[f] + rng:NextNumber(-0.05, 0.05))
			local edge = flange(m, foot, r, at, rng:NextNumber(2.4, 4.2) + r * 0.12)
			if rng:NextNumber() < 0.35 then
				mouthGlow(m, "SideThroat", edge, 0.7)
				blackSmoke(holder(m, "SidePlume", CFrame.new(edge + Vector3.new(0, 1, 0)), Vector3.one), 0.2)
			end
		end
		for _ = 1, rng:NextInteger(2, 3) do
			local d = foot.Y + rng:NextNumber(0.12, 0.85) * h
			local a = rng:NextNumber(0, TAU)
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			local on = Vector3.new(foot.X, d, foot.Z) + out * (r * 0.97)
			streak(m, "Stain", on, out, r * 0.7, r * rng:NextNumber(1.2, 2), pick(COLORS.minerals))
		end
		stats.chimneys += 1
	end
end

-- ---------------------------------------------------------------------------
-- Columnar basalt
-- ---------------------------------------------------------------------------

local CAP = 0.9 -- the lighter top's thickness

-- A hex column: three blocks turned 60° apart make the hexagon (`size` its corner
-- radius; its flats face `yaw` and every 60° from it, so columns on VentsPlan's grid
-- meet flat to flat), the top a lighter band; it stands to the height the plan gave
-- (never higher: VentsPlan.ceiling), its foot sunk under the lowest ground beneath it
local function column(parent: Instance, c: VentsPlan.Column)
	local width = c.size * math.sqrt(3)
	local top = c.at.Y + c.height
	local low = groundY(c.at.X, c.at.Z, c.at.Y)
	for k = 0, 2 do
		local a = c.yaw + math.pi / 6 + k * TAU / 3
		low = math.min(low, groundY(c.at.X + math.cos(a) * c.size, c.at.Z + math.sin(a) * c.size, low))
	end
	if top < low + 1.5 then
		return
	end
	local bottom = low - 1.5
	local body = top - CAP - bottom
	local color, topColor = pick(COLORS.basalt), pick(COLORS.basaltTop)
	for k = 0, 2 do
		local turn = CFrame.Angles(0, -(c.yaw + math.pi / 6 + k * math.pi / 3), 0)
		rock(
			parent,
			"Basalt",
			Vector3.new(c.size, body, width),
			CFrame.new(c.at.X, bottom + body / 2, c.at.Z) * turn,
			color
		)
		rock(
			parent,
			"BasaltTop",
			Vector3.new(c.size, CAP, width),
			CFrame.new(c.at.X, top - CAP / 2, c.at.Z) * turn,
			topColor
		)
	end
	stats.columns += 1
end

local function basalt(parent: Instance, plan: VentsPlan.Plan)
	local groups: { [string]: Model } = {}
	for _, c in plan.columns do
		local existing = groups[c.group]
		local m = if existing
			then existing
			else model(parent, if c.group == "causeway" then "Causeway" else "BasaltOutcrop")
		groups[c.group] = m
		column(m, c)
	end
end

-- ---------------------------------------------------------------------------
-- Mineral terraces
-- ---------------------------------------------------------------------------

-- A cascade of rimstone shelves down a basin wall: `drop` studs a step from `first`
-- under the deep floor to `lowest` over the basin's, each `radius` (growing `grow` a
-- step), meandering up to `drift` studs a step along the wall, and now and then a
-- smaller shelf beside it half a step down (`side`)
local TERRACE = { drop = 10, first = 3, lowest = 12, radius = { 7, 10 }, grow = 0.5, drift = 6, side = 0.45 }

-- One rimstone shelf: a solid stone disc half sunk in the wall, a glowing pool on it
-- and a raised, scalloped rim round its front; returns its front edge
local function shelf(
	m: Instance,
	center: Vector3,
	y: number,
	radius: number,
	inward: Vector3,
	s: number
): Vector3
	local stone = COLORS.travertine[s % #COLORS.travertine + 1]
	local rim = COLORS.travertine[(s + 1) % #COLORS.travertine + 1]
	disc(m, "TerraceShelf", center, y, radius, 3, stone, true)
	local pool = disc(m, "TerracePool", center, y + 0.45, radius - 0.9, 0.3, COLORS.terracePool, false)
	pool.Material = NEON
	pool.Transparency = 0.4
	pool.CastShadow = false
	stats.glow += 1
	local facing = math.atan2(inward.Z, inward.X)
	local lobes = if radius > 6 then 5 else 3
	for k = 1, lobes do
		local a = facing + (k - (lobes + 1) / 2) * (2.3 / lobes) + rng:NextNumber(-0.08, 0.08)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local at = Vector3.new(center.X, y + 0.5, center.Z) + dir * (radius - 0.3)
		-- (a rimstone dam's lobe: a flat-topped, round-fronted step)
		local lobe = radius * 2.3 / lobes * 1.35
		local tall = rng:NextNumber(1.6, 2)
		local dam = trim(
			m,
			"TerraceRim",
			Vector3.new(tall, lobe * 0.8, lobe * 0.8),
			CFrame.new(at) * CFrame.Angles(0, 0, HALF),
			rim
		)
		dam.Shape = Enum.PartType.Cylinder
	end
	return Vector3.new(center.X, y, center.Z) + inward * radius
end

local function terraces(parent: Instance, plan: VentsPlan.Plan)
	local basins = Seafloor.ventBasins()
	for index, terrace in plan.terraces do
		local basin = basins[terrace.basin]
		local m = model(parent, `Terraces{index}`)
		local out = Vector3.new(math.cos(terrace.heading), 0, math.sin(terrace.heading))
		local inward = -out
		local side = Vector3.new(-out.Z, 0, out.X)
		local y = deep.floorY - TERRACE.first
		local prev: { front: Vector3, radius: number }? = nil
		local made, mid = 0, nil :: Vector3?
		local drift = 0
		-- Whether a shelf there is clear of the schools in the basin and not buried
		-- in the lip's rubble (the ground just in front stands over it)
		local function fits(center: Vector3, top: number, radius: number): (boolean, boolean)
			if top + 1.5 > VentsPlan.ceiling(center.X, center.Z, radius) then
				return false, true
			end
			local front = center + inward * (radius * 0.6)
			return groundY(front.X, front.Z, deep.ventsFloorY) <= top + 1, false
		end
		for s = 0, 11 do
			if y < deep.ventsFloorY + TERRACE.lowest then
				break
			end
			local radius = rng:NextNumber(TERRACE.radius[1], TERRACE.radius[2]) + s * TERRACE.grow
			drift = math.clamp(drift + rng:NextNumber(-1, 1) * TERRACE.drift, -14, 14)
			local wall = Vector3.new(basin.x, y, basin.z) + out * basin.radius + side * drift
			local center = wall + inward * (radius * 0.2)
			local ok, schools = fits(center, y, radius)
			-- (none goes lower once a school is in the way)
			if schools then
				break
			end
			if not ok then
				y -= TERRACE.drop
				continue
			end
			local front = shelf(m, center, y, radius, inward, s)
			-- Flowstone draped from the shelf above: a smooth tongue over its rim
			local last = prev
			if last then
				local from = last.front + Vector3.new(0, -0.6, 0)
				local to = center + inward * (radius * 0.55) + Vector3.new(0, 0.5, 0)
				local span = to - from
				-- (a sheet over the rim with ribs of drip running down it: as one
				-- stretched sphere it read as a huge pale egg)
				local width = last.radius * rng:NextNumber(0.6, 0.85)
				local tone = COLORS.travertine[(s + 2) % #COLORS.travertine + 1]
				local sheet = CFrame.lookAt((from + to) / 2, to)
				trim(m, "Flowstone", Vector3.new(width, 0.8, span.Magnitude), sheet, tone)
				for k = -1, 1 do
					trim(
						m,
						"FlowstoneRib",
						Vector3.new(width * 0.16, 0.5, span.Magnitude * rng:NextNumber(0.55, 0.95)),
						sheet * CFrame.new(k * width * 0.3, 0.5, span.Magnitude * 0.05),
						tone:Lerp(Color3.new(1, 1, 1), 0.12)
					)
				end
			end
			-- A smaller shelf beside it, half a step down
			if rng:NextNumber() < TERRACE.side then
				local small = radius * 0.6
				local sideWay = if rng:NextNumber() < 0.5 then -1 else 1
				local beside = center + side * (sideWay * (radius + small * 0.6)) + inward * (small * 0.1)
				local top = y - TERRACE.drop * 0.5
				local sideOk = fits(beside, top, small)
				if sideOk and top > deep.ventsFloorY + TERRACE.lowest then
					shelf(m, beside, top, small, inward, s + 1)
					stats.steps += 1
				end
			end
			prev = { front = front, radius = radius }
			made += 1
			stats.steps += 1
			if made == 2 then
				mid = center + inward * (radius + 6)
			end
			y -= TERRACE.drop
		end
		local glowAt = mid
		if glowAt then
			local spot = holder(m, "TerraceGlow", CFrame.new(glowAt), Vector3.new(6, 6, 6))
			light(spot, LIGHT.terrace, 40, 1.6)
			shimmer(spot, 5)
		end
	end
end

-- ---------------------------------------------------------------------------
-- The brine pool, tube worms and mussels
-- ---------------------------------------------------------------------------

local function musselBed(parent: Instance, center: Vector3, inner: number, outer: number, count: number)
	local m = model(parent, "MusselBed")
	stats.beds += 1
	for _ = 1, count do
		local a = rng:NextNumber(0, TAU)
		local d = inner + (outer - inner) * rng:NextNumber() ^ 0.7
		local x, z = center.X + math.cos(a) * d, center.Z + math.sin(a) * d
		local hit = groundOf(x, z)
		if hit == nil or math.abs(hit.Y - center.Y) > 2.5 then
			continue
		end
		if stats.parts >= PARTS_CAP then
			break
		end
		local s = rng:NextNumber(0.8, 1.3)
		local yaw = rng:NextNumber(0, TAU)
		if rng:NextNumber() < 0.2 then
			-- (two shell halves meeting in a ridge, the lip dark between them)
			local clam = CFrame.new(hit + Vector3.new(0, 0.3 * s, 0))
				* CFrame.Angles(0, yaw, rng:NextNumber(-0.2, 0.2))
			local half = Vector3.new(2 * s, 0.6 * s, 0.7 * s)
			wedge(m, "Clam", half, clam * CFrame.new(0, 0, 0.35 * s), COLORS.clam)
			wedge(
				m,
				"Clam",
				half,
				clam * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, 0.35 * s),
				COLORS.clam
			)
			trim(
				m,
				"ClamLip",
				Vector3.new(2.04 * s, 0.14, 0.12),
				clam * CFrame.new(0, 0.27 * s, 0),
				COLORS.clamLip
			)
		else
			-- (a long shell set on its edge: a lozenge, faceted along its length)
			trim(
				m,
				"Mussel",
				Vector3.new(1.7, 0.6, 0.6) * s,
				CFrame.new(hit + Vector3.new(0, 0.25 * s, 0))
					* CFrame.Angles(rng:NextNumber(-0.3, 0.3), yaw, rng:NextNumber(-0.5, 0.5))
					* CFrame.Angles(math.pi / 4, 0, 0),
				pick(COLORS.mussel)
			)
		end
		stats.mussels += 1
	end
end

-- One giant tube worm (owner, 2026-10-28: a grey rod with a red cylinder on it read
-- as a matchstick) standing out of the ground at `hit` along `dir`, `length` tall and
-- `radius` round: a pale chitin tube (on a tall one the old growth low down stouter
-- and stained, the newer bending a little off it), a flared collar at its mouth and
-- its crimson plume, `fronds` thin blades fanned out of the mouth in a cone wider than
-- the tube, like a feather duster. Now and then one has drawn its plume in. A worm
-- that would take the field past PARTS_CAP is left out whole.
local WORM = {
	buried = 0.6,
	tall = 7,
	drawnIn = 0.1,
	lean = { 0.08, 0.22 },
	plume = { 3, 3.8 },
	width = { 1.4, 1.8 },
	blade = 0.16,
}

local function worm(m: Instance, hit: Vector3, dir: Vector3, length: number, radius: number, fronds: number)
	local tall = length >= WORM.tall
	if stats.parts + 2 + fronds + (if tall then 1 else 0) > PARTS_CAP then
		return
	end
	local foot = hit - dir * WORM.buried
	local axis, mouth = dir, foot + dir * length
	if tall then
		local knee = foot + dir * (length * rng:NextNumber(0.3, 0.45))
		rod(m, "TubeBase", foot, knee + dir * 0.3, radius * 1.14, pick(COLORS.tubeBase))
		axis = (dir + Vector3.new(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.1, 0.1))).Unit
		mouth = knee + axis * (length - (knee - foot).Magnitude)
		rod(m, "Tube", knee, mouth, radius, pick(COLORS.tube))
	else
		rod(m, "Tube", foot, mouth, radius, pick(COLORS.tube))
	end
	rod(m, "Collar", mouth - axis * 0.3, mouth + axis * 0.15, radius * 1.3, COLORS.collar)
	if rng:NextNumber() >= WORM.drawnIn then
		-- (each blade's inner edge leans out of the axis and its outer edge flares
		-- further, so together they open like a feather duster)
		local side = axis:Cross(if math.abs(axis.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis).Unit
		local other = axis:Cross(side)
		local turn = rng:NextNumber(0, TAU)
		local long = radius * rng:NextNumber(WORM.plume[1], WORM.plume[2]) + 0.35
		for k = 0, fronds - 1 do
			local phi = turn + (k + rng:NextNumber(-0.15, 0.15)) * TAU / fronds
			local u = side * math.cos(phi) + other * math.sin(phi)
			local lean = rng:NextNumber(WORM.lean[1], WORM.lean[2])
			local along = axis * math.cos(lean) + u * math.sin(lean)
			local outward = u * math.cos(lean) - axis * math.sin(lean)
			local d = long * rng:NextNumber(0.85, 1.1)
			local w = radius * rng:NextNumber(WORM.width[1], WORM.width[2]) + 0.3
			-- (out of the collar's middle, so no blade's foot shows on its rim)
			local start = mouth + u * (radius * 0.1) + axis * 0.1
			wedge(
				m,
				"Plume",
				Vector3.new(WORM.blade, w, d),
				CFrame.fromMatrix(start + outward * (w / 2) + along * (d / 2), outward:Cross(along), outward),
				pick(COLORS.plume)
			)
		end
	end
	stats.worms += 1
end

-- The mineral crust a clump's feet are buried in: a low faceted mound `radius` round
-- on the ground at `at` and a broken plate at its edge
local function wormCrust(m: Instance, at: Vector3, radius: number)
	if stats.parts + 3 > PARTS_CAP then
		return
	end
	chip(
		m,
		"WormCrust",
		CFrame.new(at + Vector3.new(0, 0.1, 0))
			* CFrame.Angles(rng:NextNumber(-0.06, 0.06), rng:NextNumber(0, TAU), rng:NextNumber(-0.06, 0.06)),
		Vector3.new(radius * 2, 1.1, radius * 1.7),
		pick(COLORS.wormCrust)
	)
	local a = rng:NextNumber(0, TAU)
	local d = radius * rng:NextNumber(0.85, 1.1)
	local hit = groundOf(at.X + math.cos(a) * d, at.Z + math.sin(a) * d)
	if hit and math.abs(hit.Y - at.Y) < 2.5 then
		trim(
			m,
			"WormCrust",
			Vector3.new(rng:NextNumber(1.3, 2), rng:NextNumber(0.7, 1.1), rng:NextNumber(1.1, 1.7)),
			CFrame.new(hit + Vector3.new(0, 0.15, 0))
				* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, TAU), rng:NextNumber(-0.3, 0.3)),
			pick(COLORS.wormCrust)
		)
	end
end

-- A clump of giant tube worms on a crust mound, `spread` round: the tallest in the
-- middle with the fullest plumes, shorter ones round them leaning out
local function wormClump(parent: Instance, center: Vector3, count: number, spread: number)
	local m = model(parent, "TubeWorms")
	stats.clumps += 1
	local base = groundOf(center.X, center.Z)
	if base and math.abs(base.Y - center.Y) <= 3 then
		wormCrust(m, base, spread * 0.75)
	end
	for _ = 1, count do
		local a = rng:NextNumber(0, TAU)
		local share = math.sqrt(rng:NextNumber())
		local d = spread * share
		local hit = groundOf(center.X + math.cos(a) * d, center.Z + math.sin(a) * d)
		if hit == nil or math.abs(hit.Y - center.Y) > 3 then
			continue
		end
		local length = rng:NextNumber(3.5, 9) * (1 - 0.5 * share)
		local lean = rng:NextNumber(0.05, 0.3) * (0.4 + share)
		local dir = Vector3.new(math.cos(a) * math.sin(lean), math.cos(lean), math.sin(a) * math.sin(lean))
		worm(
			m,
			hit,
			dir,
			length,
			rng:NextNumber(0.28, 0.42) * (1 - 0.15 * share),
			if share < 0.45 then 4 else 3
		)
	end
end

-- A tube-worm forest: a band `inner`–`outer` studs round `center` (a whole ring, or
-- the arc `from`–`to` radians) of dense knots of tall worms, each on its crust mound,
-- the tallest in each knot's middle, leaning out of it; the ground under each is found
-- by raycast, and a worm whose ground isn't within `step` of the forest's is left out
-- (a rock, a spire's flank)
local FOREST = { knots = 4, tallest = 11, shortest = 3.5, step = 3.5, level = 6, radius = { 2, 3 } }
-- The forests and their worms: a belt round the tallest smoker complex, the floor
-- round a basin chimney (not in the brine pool's basin) and an arc of the brine
-- pool's shore
local FORESTS = { smoker = 34, chimney = 25, brine = 20 }

local function wormForest(
	parent: Instance,
	center: Vector3,
	inner: number,
	outer: number,
	count: number,
	from: number?,
	to: number?
): number
	local a0, a1 = from or 0, to or TAU
	-- The knots: on ground near the forest's own level (not up a mound or a spire)
	local knots: { { at: Vector3, radius: number } } = {}
	for k = 1, FOREST.knots * 2 do
		if #knots >= FOREST.knots then
			break
		end
		local a = a0 + (a1 - a0) * (k - 0.5 + rng:NextNumber(-0.3, 0.3)) / (FOREST.knots * 2)
		local d = rng:NextNumber(inner, outer)
		local hit = groundOf(center.X + math.cos(a) * d, center.Z + math.sin(a) * d)
		if hit and math.abs(hit.Y - center.Y) <= FOREST.level then
			table.insert(knots, { at = hit, radius = rng:NextNumber(FOREST.radius[1], FOREST.radius[2]) })
		end
	end
	if #knots == 0 then
		return 0
	end
	local m = model(parent, "TubeWormForest")
	stats.forests += 1
	for _, knot in knots do
		wormCrust(m, knot.at, knot.radius * 0.75)
	end
	local made = 0
	for _ = 1, count do
		local knot = knots[rng:NextInteger(1, #knots)]
		local a = rng:NextNumber(0, TAU)
		local share = math.sqrt(rng:NextNumber())
		local d = knot.radius * share
		local x, z = knot.at.X + math.cos(a) * d, knot.at.Z + math.sin(a) * d
		local hit = groundOf(x, z)
		if hit == nil or math.abs(hit.Y - knot.at.Y) > FOREST.step then
			continue
		end
		made += 1
		local length = (FOREST.shortest + (FOREST.tallest - FOREST.shortest) * (1 - share * 0.75))
			* rng:NextNumber(0.6, 1)
		local lean = rng:NextNumber(0.04, 0.28) * (0.3 + share)
		local dir = Vector3.new(math.cos(a) * math.sin(lean), math.cos(lean), math.sin(a) * math.sin(lean))
		worm(
			m,
			hit,
			dir,
			length,
			rng:NextNumber(0.3, 0.46) * (1 - 0.15 * share),
			if share < 0.45 then 4 else 3
		)
	end
	return made
end

local function brinePool(parent: Instance, plan: VentsPlan.Plan)
	local brine = plan.brine
	if brine == nil then
		return
	end
	local m = model(parent, "BrinePool")
	local c, radius = brine.center, brine.radius
	-- Level with the highest of its floor, so no edge is buried
	local y = groundY(c.X, c.Z, c.Y)
	for k = 0, 7 do
		local a = k * TAU / 8
		y = math.max(y, groundY(c.X + math.cos(a) * radius * 0.85, c.Z + math.sin(a) * radius * 0.85, y))
	end
	local surface = disc(m, "Brine", c, y + 0.35, radius, 0.6, COLORS.brine, false)
	surface.Material = Enum.Material.Glass
	surface.Transparency = 0.15
	surface.Reflectance = 0.3
	surface.CastShadow = false
	local under = disc(m, "BrineGlow", c, y + 0.05, radius - 1.5, 0.2, COLORS.brineGlow, false)
	under.Material = NEON
	under.Transparency = 0.55
	stats.glow += 1
	-- A continuous shore of mineral crust (overlapping pieces round the rim), and
	-- nodules of it scattered just past
	local pieces = math.max(20, math.floor(TAU * radius / 6))
	local spacing = TAU * radius / pieces
	for k = 1, pieces do
		local a = k * TAU / pieces + rng:NextNumber(-0.04, 0.04)
		local d = radius + rng:NextNumber(0.2, 1)
		local at = Vector3.new(c.X + math.cos(a) * d, y + 0.15, c.Z + math.sin(a) * d)
		chip(
			m,
			"BrineCrust",
			CFrame.lookAt(at, at + Vector3.new(-math.sin(a), 0, math.cos(a))),
			Vector3.new(rng:NextNumber(2, 3), rng:NextNumber(0.6, 0.9), spacing * rng:NextNumber(1.4, 1.7)),
			if k % 3 == 0 then COLORS.brineCrustDark else COLORS.brineCrust
		)
	end
	for _ = 1, math.floor(pieces / 2) do
		local a = rng:NextNumber(0, TAU)
		local d = radius + rng:NextNumber(1.5, 4.5)
		local hit = groundOf(c.X + math.cos(a) * d, c.Z + math.sin(a) * d)
		if hit and math.abs(hit.Y - y) < 2 then
			local size = rng:NextNumber(1, 2.2)
			chip(
				m,
				"BrineNodule",
				CFrame.new(hit) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
				Vector3.new(size * 1.4, size * 0.5, size),
				COLORS.brineCrust
			)
		end
	end
	musselBed(m, Vector3.new(c.X, y, c.Z), radius + 1.5, radius + 6, 44)
	local a = rng:NextNumber(0, TAU)
	wormClump(m, Vector3.new(c.X + math.cos(a) * (radius + 9), y, c.Z + math.sin(a) * (radius + 9)), 8, 3)
	-- A forest along the far shore
	wormForest(m, Vector3.new(c.X, y, c.Z), radius + 4, radius + 12, FORESTS.brine, a + 2.3, a + 4.0)
	local mist =
		holder(m, "BrineMist", CFrame.new(c.X, y + 1.2, c.Z), Vector3.new(radius * 1.6, 1, radius * 1.6))
	emit(mist, "Mist", {
		rate = 2.5,
		life = { 8, 12 },
		speed = { 0.3, 0.8 },
		size = { 6, 10, 14 },
		fade = { 0.88, 0.9 },
		colors = { Color3.fromRGB(110, 150, 156), Color3.fromRGB(80, 110, 120) },
		spread = 70,
		drag = 0.6,
		glow = 0.2,
		lit = 0.5,
	})
	local glowAt = holder(m, "BrineLight", CFrame.new(c.X, y + 5, c.Z), Vector3.one)
	light(glowAt, LIGHT.brine, 40, 0.9)
end

-- Tube worms and mussel beds round the smokers and some of the chimneys, and the
-- forests
local function life(parent: Instance, plan: VentsPlan.Plan)
	local m = model(parent, "VentLife")
	local first = plan.smokers[1]
	if first then
		local foot = Vector3.new(
			first.center.X,
			groundY(first.center.X, first.center.Z, first.center.Y),
			first.center.Z
		)
		-- (the complex stands on a mound 0.85 of its radius round: the belt is past it)
		local level = Vector3.new(foot.X, first.center.Y, foot.Z)
		wormForest(m, level, first.radius * 0.9, first.radius + 16, FORESTS.smoker)
		musselBed(m, level, first.radius + 14, first.radius + 22, 30)
	end
	local brineBasin = if plan.brine then plan.brine.basin else nil
	local basins = Seafloor.ventBasins()
	local bestChimney: VentsPlan.Chimney? = nil
	local bestRoom = -math.huge
	for _, chimney in plan.chimneys do
		local p = chimney.position
		if math.abs(p.Y - deep.ventsFloorY) > 4 then
			continue
		end
		for index, basin in basins do
			local d = math.sqrt((p.X - basin.x) ^ 2 + (p.Z - basin.z) ^ 2)
			if index ~= brineBasin and d < basin.radius - 30 and basin.radius - d > bestRoom then
				bestChimney, bestRoom = chimney, basin.radius - d
			end
		end
	end
	if bestChimney then
		local p = bestChimney.position
		wormForest(m, p, 13, 24, FORESTS.chimney)
		musselBed(m, p, 22, 30, 24)
	end
	for _, smoker in plan.smokers do
		for k = 1, math.min(2, #smoker.spires) do
			local spire = smoker.spires[if k == 1 then 1 else rng:NextInteger(2, #smoker.spires)]
			local a = rng:NextNumber(0, TAU)
			local at = spire.foot
				+ Vector3.new(math.cos(a), 0, math.sin(a)) * (spire.radius + rng:NextNumber(4, 7))
			wormClump(m, at, rng:NextInteger(8, 11), rng:NextNumber(2.6, 3.4))
			if k == 1 then
				local b = a + math.pi + rng:NextNumber(-0.6, 0.6)
				local bed = spire.foot + Vector3.new(math.cos(b), 0, math.sin(b)) * (spire.radius + 6)
				musselBed(m, bed, 0, 7, 24)
			end
		end
	end
	-- Six of the chimneys, skipping any whose foot isn't open floor: a mussel bed at
	-- each, and a clump of worms opposite it at the first four (fewer, fuller clumps)
	local order = table.clone(plan.chimneys)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local spots = 0
	for _, chimney in order do
		if spots >= 6 then
			break
		end
		local foot = chimney.position
		local a = rng:NextNumber(0, TAU)
		local at = foot + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(12, 15)
		local hit = groundOf(at.X, at.Z)
		if hit == nil or math.abs(hit.Y - foot.Y) > 3 then
			continue
		end
		if spots < 4 then
			wormClump(m, hit, rng:NextInteger(8, 10), rng:NextNumber(2.6, 3.4))
		end
		spots += 1
		local b = a + math.pi + rng:NextNumber(-0.5, 0.5)
		local bed = foot + Vector3.new(math.cos(b), 0, math.sin(b)) * 14
		musselBed(m, Vector3.new(bed.X, foot.Y, bed.Z), 0, 5, 16)
	end
end

-- ---------------------------------------------------------------------------
-- Glows and the drifting water
-- ---------------------------------------------------------------------------

local function atmosphere(parent: Instance, plan: VentsPlan.Plan)
	local m = model(parent, "VentAir")
	for _, at in plan.glows do
		local y = groundY(at.X, at.Z, at.Y)
		local spot = holder(m, "CrustGlow", CFrame.new(at.X, y + 4, at.Z), Vector3.new(16, 1, 16))
		light(spot, LIGHT.crust, 42, 1.5)
		emit(spot, "HeatHaze", {
			rate = 3,
			life = { 4, 7 },
			speed = { 0.6, 1.6 },
			size = { 9, 16, 22 },
			fade = { 0.76, 0.82 },
			colors = { Color3.fromRGB(255, 120, 60), Color3.fromRGB(160, 50, 30) },
			rise = 0.3,
			spread = 20,
			drag = 0.5,
			glow = 0.6,
			lit = 0.1,
		})
	end
	-- Embers and mineral flecks drifting over the field: round the landmarks
	local spots: { Vector3 } = {}
	for _, smoker in plan.smokers do
		table.insert(spots, smoker.center)
	end
	for _, outcrop in plan.outcrops do
		table.insert(spots, outcrop.center)
	end
	local f = plan.forge
	if f then
		table.insert(spots, f.center + Vector3.new(0, f.height * 0.4, 0))
	end
	for _, at in spots do
		local drift = holder(m, "Drift", CFrame.new(at + Vector3.new(0, 30, 0)), Vector3.new(120, 40, 120))
		emit(drift, "Flecks", {
			rate = 6,
			life = { 10, 16 },
			speed = { 0.4, 1.2 },
			size = { 0.15, 0.3, 0.1 },
			fade = { 0.3, 0.5 },
			colors = { Color3.fromRGB(232, 214, 120), Color3.fromRGB(150, 226, 196) },
			drift = Vector3.new(0.25, 0.1, -0.15),
			spread = 180,
			drag = 0.2,
			glow = 0.4,
			lit = 0.3,
			texture = SPARKLE,
		})
		embers(drift, 1.5)
	end
end

-- ---------------------------------------------------------------------------

local function flatDistance(a: Vector3, b: Vector3): number
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

-- Whether a boulder `reach` round at `p` would sit in the brine pool, on a smoker's
-- spire, in the Forge's crater or on one of its runnels or their pools
local function blockedAt(plan: VentsPlan.Plan, p: Vector3, reach: number): boolean
	local brine = plan.brine
	if
		brine
		and flatDistance(p, brine.center) < brine.radius + reach + 2
		and math.abs(p.Y - brine.center.Y) < 20
	then
		return true
	end
	for _, smoker in plan.smokers do
		for _, spire in smoker.spires do
			if flatDistance(p, spire.foot) < spire.radius + reach and p.Y > spire.foot.Y + 8 then
				return true
			end
		end
	end
	local f = plan.forge
	if f then
		if flatDistance(p, f.center) < f.rim + reach + 4 and p.Y > f.center.Y + f.height * 0.6 then
			return true
		end
		local shoulder = f.shoulder
		if
			shoulder
			and flatDistance(p, shoulder.center) < shoulder.crater + reach + 3
			and p.Y > shoulder.center.Y + shoulder.height * 0.6
		then
			return true
		end
		for _, heading in f.runnels do
			for k = 0, 20 do
				local q = VentsPlan.runnelPoint(f, heading, k / 20)
				if flatDistance(p, q) < 7 + reach and math.abs(p.Y - q.Y) < 16 then
					return true
				end
			end
			local foot = VentsPlan.runnelPoint(f, heading, 0)
			local out = Vector3.new(foot.X - f.center.X, 0, foot.Z - f.center.Z).Unit
			if flatDistance(p, foot + out * 9) < 15 + reach then
				return true
			end
		end
	end
	return false
end

-- Dressing scattered over the biome by raycast on the Terrain alone can land inside
-- a basalt column (plankton mats, boulders) or on a landmark (boulders), and the
-- brine pool covers a basin's fissures: they go
local function tidy(parent: Instance, plan: VentsPlan.Plan): number
	local removed = 0
	local BIN = 16
	local bins: { [number]: { VentsPlan.Column }? } = {}
	local function key(x: number, z: number): number
		return (math.floor(x / BIN) + 1000) * 4096 + (math.floor(z / BIN) + 1000)
	end
	for _, c in plan.columns do
		local k = key(c.at.X, c.at.Z)
		local list: { VentsPlan.Column } = bins[k] or {}
		bins[k] = list
		table.insert(list, c)
	end
	local function inColumn(p: Vector3, reach: number): boolean
		local span = math.ceil(reach / BIN) + 1
		for dx = -span, span do
			for dz = -span, span do
				local list = bins[key(p.X + dx * BIN, p.Z + dz * BIN)]
				if list == nil then
					continue
				end
				for _, c in list do
					if
						(p.X - c.at.X) ^ 2 + (p.Z - c.at.Z) ^ 2 < (c.size + 0.8 + reach) ^ 2
						and p.Y < c.at.Y + c.height + 1 + reach
					then
						return true
					end
				end
			end
		end
		return false
	end
	local biomes = parent.Parent
	local mats = if biomes then biomes:FindFirstChild("PlanktonMats") else nil
	if mats then
		for _, dot in mats:GetChildren() do
			if dot:IsA("BasePart") and inColumn(dot.Position, 0) then
				dot:Destroy()
				removed += 1
			end
		end
	end
	local brine = plan.brine
	if brine then
		for _, crack in parent:GetChildren() do
			if crack.Name ~= "Fissure" then
				continue
			end
			for _, piece in crack:GetChildren() do
				if piece:IsA("BasePart") then
					if flatDistance(piece.Position, brine.center) < brine.radius + 1.5 then
						piece:Destroy()
						removed += 1
					end
				end
			end
		end
	end
	-- Boulders the biome's scatter dropped by raycast on the Terrain alone
	-- (WorldService `rock`: a placeholder Rock part, and its BoulderRoundProp model
	-- over the same spot) that came to rest in the basalt, the brine pool, on a
	-- spire, in the crater or on a runnel: they go
	local rocks = if biomes then biomes:FindFirstChild("Rocks") else nil
	if rocks then
		local props: { Model } = {}
		for _, child in rocks:GetChildren() do
			if child:IsA("Model") and child.Name == "BoulderRoundProp" then
				table.insert(props, child)
			end
		end
		for _, child in rocks:GetChildren() do
			if not child:IsA("BasePart") or child.Name ~= "Rock" then
				continue
			end
			local p = child.Position
			local r, angle = Seafloor.polar(p.X, p.Z)
			if r < deep.ventsRadii[1] - 200 or not Seafloor.inSector(angle, 110, 240) then
				continue
			end
			local reach = math.max(child.Size.X, child.Size.Z) / 2
			if not (inColumn(p, reach) or blockedAt(plan, p, reach)) then
				continue
			end
			for index, prop in props do
				local q = prop:GetPivot().Position
				if (q.X - p.X) ^ 2 + (q.Z - p.Z) ^ 2 < 0.25 then
					prop:Destroy()
					table.remove(props, index)
					break
				end
			end
			child:Destroy()
			removed += 1
		end
	end
	return removed
end

-- Dresses the field `plan` (VentsPlan, from Shelf.ops) into `parent`
-- (Workspace.World.Biomes.Vents: where Shared/Ground looks for solid dressing) on
-- the Terrain `ground` answers for (a ray down: the top and its normal, or nil).
-- Call it after the other biomes' dressing: it clears plankton out of its columns
-- and the fissures under the brine pool.
function Vents.build(parent: Instance, plan: VentsPlan.Plan, ground: Ground): Stats
	rng = Random.new(World.seed + 99)
	groundOf = ground
	stats = freshStats()
	forge(parent, plan)
	smokers(parent, plan)
	chimneyDress(parent, plan)
	basalt(parent, plan)
	terraces(parent, plan)
	brinePool(parent, plan)
	life(parent, plan)
	atmosphere(parent, plan)
	stats.tidied = tidy(parent, plan)
	local f = plan.forge
	local where = "no Forge"
	if f then
		local r, angle = Seafloor.polar(f.center.X, f.center.Z)
		where = `the Forge {f.height} studs tall at {math.floor(r)} studs, {math.floor(angle)}°`
		local shoulder = f.shoulder
		if shoulder then
			local toward = math.atan2(-f.center.Z, -f.center.X)
			local heading = math.atan2(shoulder.center.Z - f.center.Z, shoulder.center.X - f.center.X)
			local off = math.deg(math.abs((heading - toward + math.pi) % TAU - math.pi))
			where ..= ` with a {shoulder.height}-stud shoulder cone {math.floor(off)}° off the hub's side`
		end
	end
	local spires = 0
	for _, smoker in plan.smokers do
		spires += #smoker.spires
	end
	print(
		`[Vents] {where}; {#plan.smokers} smoker complexes ({spires} spires), {stats.chimneys} chimneys dressed, {stats.columns} basalt columns, {stats.steps} terrace steps, {if plan.brine
			then "a"
			else "no"} brine pool, {stats.clumps} tube-worm clumps and {stats.forests} forests ({stats.worms} worms), {stats.beds} mussel beds ({stats.mussels} shells); {stats.parts} parts ({stats.solid} solid, {stats.glow} glowing), {stats.lights} lights, {stats.emitters} emitters; {stats.tidied} plankton, fissure pieces and boulders cleared; {plan.opsTo - plan.opsFrom + 1} Terrain ops`
	)
	for _, note in plan.notes do
		print(`[Vents] {note}`)
	end
	return stats
end

return Vents
