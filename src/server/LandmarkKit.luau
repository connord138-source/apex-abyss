--!strict
-- Part helpers the biome landmark builders share (Wrecks, TrenchDress, KelpDress,
-- ReefDress, BlueDress; owner, 2026-10-21: the biome detail boards in
-- assets/concepts/biome_detail/). Every imported model has a part-built stand-in
-- that works with nothing imported; Props.dress fits the model over it.
--
-- The rules the world builders keep: small built pieces are SmoothPlastic (and Neon
-- where something glows), never a material the toon variants override; no
-- sphere-mesh lumps; nothing fires Touched; decor takes no camera rays; solid pieces
-- (what fish bump into) also take rays, so Shared/Ground and the camera see them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Props = require(ReplicatedStorage.Shared.Props)

local LandmarkKit = {}

export type Stats = {
	parts: number,
	solid: number,
	glow: number,
	lights: number,
	emitters: number,
	models: number, -- imported models placed
	standins: number, -- stand-ins left (their model isn't imported)
	heroes: { [string]: number }, -- placements by model name
	-- Ground a landmark stands on, kept clear of the biome's other scatter
	-- (LandmarkKit.clearAround, called by WorldService after the scatter)
	clearings: { { center: Vector3, radius: number } },
}

export type Ground = (x: number, z: number) -> (Vector3?, Vector3?)

local SMOOTH = Enum.Material.SmoothPlastic
local HALF = math.pi / 2
-- Tripo props face +X in the GLB and Studio turns a GLB half round: a quarter turn
-- puts a model's front on its frame's look (as Ruins.luau and Plaza.luau)
LandmarkKit.GLB_FRONT = CFrame.Angles(0, -HALF, 0)

function LandmarkKit.stats(): Stats
	return {
		parts = 0,
		solid = 0,
		glow = 0,
		lights = 0,
		emitters = 0,
		models = 0,
		standins = 0,
		heroes = {},
		clearings = {},
	}
end

-- An anchored part; `solid` pieces collide and take rays, the rest are decor
function LandmarkKit.part(
	stats: Stats,
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	solid: boolean,
	shape: Enum.PartType?,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or SMOOTH
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	p.CanCollide = solid
	p.CanQuery = solid
	p.CastShadow = solid and math.max(size.X, size.Y, size.Z) >= 6
	p.Parent = parent
	stats.parts += 1
	if solid then
		stats.solid += 1
	end
	if material == Enum.Material.Neon then
		stats.glow += 1
		p.CastShadow = false
	end
	return p
end

-- A cylinder from `a` to `b` (its axis is a part's X)
function LandmarkKit.rod(
	stats: Stats,
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	radius: number,
	color: Color3,
	solid: boolean,
	material: Enum.Material?
): Part
	local span = b - a
	local frame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, HALF, 0)
	return LandmarkKit.part(
		stats,
		parent,
		name,
		Vector3.new(span.Magnitude, radius * 2, radius * 2),
		frame,
		color,
		solid,
		Enum.PartType.Cylinder,
		material
	)
end

-- A glowing piece (Neon, no collision)
function LandmarkKit.glow(
	stats: Stats,
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	shape: Enum.PartType?
): Part
	return LandmarkKit.part(stats, parent, name, size, cframe, color, false, shape, Enum.Material.Neon)
end

function LandmarkKit.light(
	stats: Stats,
	holder: Instance,
	color: Color3,
	range: number,
	brightness: number
): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = holder
	stats.lights += 1
	return light
end

-- Welds everything in a holder the client moves (LandmarkController's bobbing and
-- drifting things) to one anchored part, `root` or its first, so it moves as one
-- assembly and the client's batch moves that root alone (PC 2026-10-25: a
-- part-built jellyfish was 15 anchored parts, ~40 moved a frame at the pinnacle)
function LandmarkKit.oneBody(holder: Instance, root: BasePart?)
	local base = root
	local parts = {}
	for _, d in holder:GetDescendants() do
		if d:IsA("BasePart") then
			base = base or d
			table.insert(parts, d)
		end
	end
	if base == nil then
		return
	end
	base.Anchored = true
	for _, part in parts do
		if part ~= base then
			part.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = base
			weld.Part1 = part
			weld.Parent = part
		end
	end
end

-- An invisible holder for a light (or a sound, an emitter) at a point
function LandmarkKit.anchor(parent: Instance, name: string, at: CFrame, size: Vector3?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size or Vector3.one
	p.CFrame = at
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = parent
	return p
end

export type HeroOptions = {
	solid: boolean?, -- the model is what fish bump into (its stand-in goes)
	blocksCamera: boolean?, -- with `solid`: the camera stays out of it too
	-- The stand-in's solid parts stay as invisible colliders under a non-colliding
	-- model (arches and hulls a fish swims through: a mesh's own collision hull can
	-- fill an arch's opening)
	keepColliders: boolean?,
	tint: Color3?,
}

-- A model over its part-built stand-in: the stand-in is built first (in a Standin
-- model); once WorldProps.<name> is imported, Props.dress fits it into the box (`box`
-- its middle, `size` in the model's own axes) and the stand-in goes (or turns into
-- invisible colliders, `keepColliders`)
function LandmarkKit.hero(
	stats: Stats,
	parent: Instance,
	name: string,
	box: CFrame,
	size: Vector3,
	build: (Model) -> (),
	options: HeroOptions?
): (Model, Model?)
	local opts: HeroOptions = options or {}
	local holder = Instance.new("Model")
	holder.Name = name
	-- (its pivot is its box, so a client moving it (LandmarkController: bobbing,
	-- drifting, ducking) moves it about its own middle)
	holder.WorldPivot = box
	holder.Parent = parent
	local standin = Instance.new("Model")
	standin.Name = "Standin"
	standin.Parent = holder
	local before = { stats.parts, stats.solid, stats.glow }
	build(standin)
	local anchor = LandmarkKit.anchor(holder, name .. "Box", box, size)
	local dressed = Props.dress(anchor, name, {
		cframe = box,
		size = size,
		solid = opts.solid == true and not opts.keepColliders,
		blocksCamera = opts.blocksCamera,
		tint = opts.tint,
	})
	stats.heroes[name] = (stats.heroes[name] or 0) + 1
	if dressed then
		stats.models += 1
		if opts.keepColliders then
			-- The stand-in's solid parts stay, unseen; its decor goes
			for _, piece in standin:GetDescendants() do
				if piece:IsA("BasePart") then
					if piece.CanCollide then
						piece.Transparency = 1
						piece.CastShadow = false
					else
						piece:Destroy()
					end
				elseif piece:IsA("Light") or piece:IsA("ParticleEmitter") then
					piece:Destroy()
				end
			end
		else
			standin:Destroy()
			stats.parts, stats.solid, stats.glow = before[1], before[2], before[3]
		end
	else
		stats.standins += 1
	end
	return holder, dressed
end

-- The box of a model standing on `ground` (its foot `sink` of its height into the
-- sand), turned `yaw` with its front on the frame's look, `size` (length along the
-- front, height, width) in studs
function LandmarkKit.standing(
	ground: Vector3,
	yaw: number,
	size: Vector3,
	sink: number?,
	tilt: CFrame?
): CFrame
	local frame = CFrame.new(ground) * CFrame.Angles(0, yaw, 0) * (tilt or CFrame.identity)
	return frame * CFrame.new(0, size.Y * (0.5 - (sink or 0)), 0) * LandmarkKit.GLB_FRONT
end

-- A chain of iron links from `a` to `b` sagging `sag` studs in the middle (links
-- `link` long, alternate ones turned a quarter: a real chain reads at a distance)
function LandmarkKit.chain(
	stats: Stats,
	parent: Instance,
	a: Vector3,
	b: Vector3,
	sag: number,
	link: number,
	color: Color3,
	ground: Ground?
)
	local count = math.max(2, math.floor((b - a).Magnitude / (link * 0.8)))
	local previous = a
	for i = 1, count do
		local t = i / count
		local point = a:Lerp(b, t) - Vector3.new(0, sag * 4 * t * (1 - t), 0)
		if ground then
			local hit = ground(point.X, point.Z)
			if hit and point.Y < hit.Y + link * 0.25 then
				point = Vector3.new(point.X, hit.Y + link * 0.25, point.Z)
			end
		end
		local mid = (previous + point) / 2
		local along = point - previous
		if along.Magnitude > 0.05 then
			local frame = CFrame.lookAt(mid, point) * CFrame.Angles(0, 0, if i % 2 == 0 then HALF else 0)
			LandmarkKit.part(
				stats,
				parent,
				"ChainLink",
				Vector3.new(link * 0.22, link * 0.5, along.Magnitude + link * 0.15),
				frame,
				color,
				false
			)
		end
		previous = point
	end
end

-- A small ship's lantern (no sphere roof): brass cap and foot round amber Neon glass
function LandmarkKit.lantern(stats: Stats, parent: Instance, at: CFrame, size: number, lit: boolean): Part
	local brass = Color3.fromRGB(150, 118, 60)
	LandmarkKit.part(
		stats,
		parent,
		"LanternCap",
		Vector3.new(1.3, 0.4, 1.3) * size,
		at * CFrame.new(0, 0.95 * size, 0),
		brass,
		false
	)
	LandmarkKit.part(
		stats,
		parent,
		"LanternRoof",
		Vector3.new(0.7, 0.5, 0.7) * size,
		at * CFrame.new(0, 1.35 * size, 0) * CFrame.Angles(0, math.pi / 4, 0),
		brass,
		false
	)
	local glass = LandmarkKit.part(
		stats,
		parent,
		"LanternGlass",
		Vector3.new(0.95, 1.5, 0.95) * size,
		at,
		if lit then Color3.fromRGB(242, 162, 72) else Color3.fromRGB(78, 74, 66),
		false,
		nil,
		if lit then Enum.Material.Neon else nil
	)
	LandmarkKit.part(
		stats,
		parent,
		"LanternFoot",
		Vector3.new(1.2, 0.35, 1.2) * size,
		at * CFrame.new(0, -0.92 * size, 0),
		brass,
		false
	)
	return glass
end

-- A beam of light down from the surface (as WorldService's shafts): `strength` 0..1;
-- `foot` the share of it still showing at the bottom (0 by default: it fades out)
function LandmarkKit.shaft(
	parent: Instance,
	top: Vector3,
	bottom: Vector3,
	width: number,
	strength: number,
	foot: number?
)
	local kept = foot or 0
	local holder = LandmarkKit.anchor(parent, "LightShaft", CFrame.new(top))
	local a0 = Instance.new("Attachment")
	a0.Parent = holder
	a0.WorldPosition = top
	local a1 = Instance.new("Attachment")
	a1.Parent = holder
	a1.WorldPosition = bottom
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = width
	beam.Width1 = width * 1.7
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(Color3.fromRGB(200, 244, 255))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 - strength),
		NumberSequenceKeypoint.new(0.6, 1 - strength * math.max(0.5, kept)),
		NumberSequenceKeypoint.new(1, 1 - strength * kept),
	})
	beam.Parent = holder
end

-- A sun shaft that reads soft-edged, as the scenes paint them: a Beam is a hard-edged
-- ribbon, so a wide faint one round a narrow brighter core along the same line
function LandmarkKit.softShaft(
	parent: Instance,
	top: Vector3,
	bottom: Vector3,
	width: number,
	strength: number,
	foot: number?
)
	LandmarkKit.shaft(parent, top, bottom, width, strength * 0.5, foot)
	LandmarkKit.shaft(parent, top, bottom, width * 0.42, strength * 0.7, foot)
end

-- Marks ground a landmark stands on (`radius` across from `center`)
function LandmarkKit.clearing(stats: Stats, center: Vector3, radius: number)
	table.insert(stats.clearings, { center = center, radius = radius })
end

-- Takes the scatter other loops dropped out of a landmark's clearings: every part
-- or model directly in `folders` whose middle lies in one (folders inside them, the
-- landmarks' own, are left alone). Returns how many went.
function LandmarkKit.clearAround(
	folders: { Instance },
	clearings: { { center: Vector3, radius: number } }
): number
	local removed = 0
	if #clearings == 0 then
		return 0
	end
	for _, holder in folders do
		for _, child in holder:GetChildren() do
			local at: Vector3? = nil
			if child:IsA("BasePart") then
				at = child.Position
			elseif child:IsA("Model") then
				local part = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart", true)
				at = if part then part.Position else nil
			end
			if at == nil then
				continue
			end
			for _, c in clearings do
				local dx, dz = at.X - c.center.X, at.Z - c.center.Z
				if dx * dx + dz * dz <= c.radius * c.radius then
					child:Destroy()
					removed += 1
					break
				end
			end
		end
	end
	return removed
end

return LandmarkKit
