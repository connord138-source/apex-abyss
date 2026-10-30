--!strict
-- Builds one den thing (Config/Dens items) as a Model whose pivot is where it's
-- attached: a floor thing's pivot is under its middle and it stands up from there; a
-- wall thing's pivot is on the rock and it stands out along the pivot's look; a
-- ceiling thing's pivot is on the rock above and it hangs down. The server places
-- them (DenBuilder), Build mode's ghost is the same model (BuildController) and so
-- is the den shop's photo (ItemPhoto), so what you aim is what you get. Imported
-- Tripo props (Props.dress) replace the part-built stand-ins where they exist.
--
-- Gardens, piles and clusters (owner, 2026-10-18: "An anemone garden is literally
-- just one anemone lmao. everything is just a single item") are built of many
-- pieces (Config/Dens `cluster`): a bed, then reef pieces scattered over the
-- footprint at varied sizes and turns, seeded by the thing's id so every copy is
-- alike. The pieces (`DenItems.piece`) are the imported reef props where they're in
-- and part-built shapes of the same things where they aren't; the Coral Garden
-- grows from the same pieces (DenBuilder).
--
-- Part-built pieces are SmoothPlastic (and Neon or Glass where they glow): the toon
-- materials (Config/Materials) re-skin Slate, Wood, Basalt, Sand, Pebble, ...
-- game-wide with tiles 8 to 16 studs across, a blur on anything small (owner,
-- 2026-10-17: "fuzzy, cheap").
local Config = require(script.Parent.Config)
local DensConfig = require(script.Parent.Config.Dens)
local Fx = require(script.Parent.Fx)
local Props = require(script.Parent.Props)

local DenItems = {}

local SMOOTH = Enum.Material.SmoothPlastic
local STONE = Color3.fromRGB(150, 138, 118)
local STONE_LIGHT = Color3.fromRGB(176, 164, 140)
local WOOD = Color3.fromRGB(122, 96, 68)
local IRON = Color3.fromRGB(52, 58, 64)
local SAND = Color3.fromRGB(226, 208, 168)
local PEARL = Color3.fromRGB(240, 240, 246)

-- The reef's colors (a cluster with none of its own)
DenItems.REEF = {
	Color3.fromRGB(255, 112, 130),
	Color3.fromRGB(255, 156, 84),
	Color3.fromRGB(186, 112, 236),
	Color3.fromRGB(255, 212, 96),
	Color3.fromRGB(110, 214, 200),
	Color3.fromRGB(120, 170, 255),
}

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local made = Instance.new("Part")
	made.Name = name
	made.Anchored = true
	made.CanCollide = false
	made.CanQuery = false
	made.CanTouch = false
	made.CastShadow = false
	made.TopSurface = Enum.SurfaceType.Smooth
	made.BottomSurface = Enum.SurfaceType.Smooth
	made.Size = size
	made.CFrame = cframe
	made.Color = color
	made.Material = material or SMOOTH
	made.Parent = parent
	return made
end

local function shaped(p: Part, shape: Enum.PartType): Part
	p.Shape = shape
	return p
end

-- An ellipsoid filling `size` (a sphere mesh on a block: a Ball part is always round)
local function blob(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = part(parent, name, size, cframe, color)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- An upright cylinder standing on `base` (its up is the axis), `length` tall
local function upright(
	parent: Instance,
	name: string,
	base: CFrame,
	length: number,
	radius: number,
	color: Color3,
	material: Enum.Material?
): Part
	return shaped(
		part(
			parent,
			name,
			Vector3.new(length, radius * 2, radius * 2),
			base * CFrame.new(0, length / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			color,
			material
		),
		Enum.PartType.Cylinder
	)
end

local function light(on: BasePart, color: Color3, range: number, brightness: number)
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = range
	glow.Brightness = brightness
	glow.Parent = on
end

local function paler(color: Color3, by: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), by)
end

local function darker(color: Color3, by: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), by)
end

-- A banner's cloth in the den's glow: deeper and richer than the glow itself, so the
-- gold emblem and trim stand out on every glow (PC 2026-10-19 round 2: on Gold they
-- vanished into the cloth, and Violet read lilac)
local function clothOf(glow: Color3): Color3
	local h, sat, v = glow:ToHSV()
	return Color3.fromHSV(h, math.min(1, sat * 1.15 + 0.1), v * 0.62)
end

-- A fixed number from a string (a thing's id seeds its pieces)
local function seedOf(text: string): number
	local h = 5381
	for i = 1, #text do
		h = (h * 33 + string.byte(text, i)) % 2147483647
	end
	return h
end

-- An imported reef prop fitted into a box standing on `foot`, tinted (it can only
-- darken a texture); nil when it isn't imported
local function propPiece(parent: Instance, name: string, foot: CFrame, box: Vector3, tint: Color3?): Model?
	if Props.template("WorldProps", name) == nil then
		return nil
	end
	local stand = part(parent, "Piece", box, foot * CFrame.new(0, box.Y / 2, 0), Color3.new(1, 1, 1))
	stand.Transparency = 1
	local prop = Props.dress(stand, name, { cframe = stand.CFrame, size = box })
	if prop and tint then
		Props.tint(prop, tint)
	end
	stand:Destroy()
	return prop
end

-- The reef pieces, each standing on `foot` (its up is theirs), about `height` tall.
-- Shared with the Coral Garden (DenBuilder). `rng` varies the small details.
local PROP_OF: { [string]: string } = {
	Staghorn = "StaghornCoral",
	Fan = "FanCoral",
	Brain = "BrainCoral",
	Anemone = "Anemone",
	Shell = "Shell",
	Kelp = "KelpClump",
	Crystal = "CrystalCluster",
}

local function staghorn(parent: Instance, foot: CFrame, height: number, color: Color3, tips: { CFrame }?)
	-- A trunk that forks twice, every branch tapering, the tips paler
	local function branch(from: CFrame, length: number, thick: number, depth: number)
		local tip = from * CFrame.new(0, length, 0)
		upright(parent, "Branch", from, length, thick / 2, if depth == 0 then paler(color, 0.25) else color)
		if depth > 0 then
			for i = 1, 2 do
				local spread = math.rad(28 + depth * 4) * (if i == 1 then 1 else -1)
				branch(
					tip * CFrame.Angles(0, i * 1.9 + depth, 0) * CFrame.Angles(spread, 0, 0),
					length * 0.72,
					thick * 0.72,
					depth - 1
				)
			end
		elseif tips then
			table.insert(tips, tip)
		end
	end
	branch(foot, height * 0.4, height * 0.11, 2)
end

local function anemone(parent: Instance, foot: CFrame, height: number, color: Color3, rng: Random)
	local stalk = darker(color, 0.22)
	upright(parent, "Stalk", foot, height * 0.5, height * 0.2, stalk)
	blob(
		parent,
		"Disc",
		Vector3.new(height * 0.72, height * 0.2, height * 0.72),
		foot * CFrame.new(0, height * 0.5, 0),
		color
	)
	blob(
		parent,
		"Mouth",
		Vector3.new(height * 0.2, height * 0.08, height * 0.2),
		foot * CFrame.new(0, height * 0.6, 0),
		darker(color, 0.45)
	)
	-- A crown of tentacles leaning out, paler toward the tips
	local count = 9
	local turn = rng:NextNumber(0, 1)
	for k = 1, count do
		local a = (k + turn) / count * 2 * math.pi
		local lean = math.rad(rng:NextNumber(28, 46))
		local base = foot
			* CFrame.new(math.cos(a) * height * 0.24, height * 0.55, math.sin(a) * height * 0.24)
			* CFrame.Angles(0, -a, 0)
			* CFrame.Angles(0, 0, -lean)
		upright(
			parent,
			"Tentacle",
			base,
			height * rng:NextNumber(0.36, 0.5),
			height * 0.045,
			paler(color, 0.3)
		)
	end
end

local function brain(parent: Instance, foot: CFrame, height: number, color: Color3, rng: Random)
	blob(
		parent,
		"Brain",
		Vector3.new(height * 1.3, height, height * 1.2),
		foot * CFrame.new(0, height * 0.45, 0),
		color
	)
	-- Lumps and grooves, so it reads as a brain coral, not a ball
	for k = 1, 3 do
		local a = k * 2.1 + rng:NextNumber(0, 0.5)
		blob(
			parent,
			"Lump",
			Vector3.new(height * 0.62, height * 0.5, height * 0.55),
			foot * CFrame.new(math.cos(a) * height * 0.32, height * 0.62, math.sin(a) * height * 0.3),
			paler(color, 0.08 * k)
		)
	end
	for k = 1, 3 do
		blob(
			parent,
			"Groove",
			Vector3.new(height * 0.7, height * 0.08, height * 0.12),
			foot
				* CFrame.new(0, height * (0.84 - math.abs(k - 2) * 0.03), (k - 2) * height * 0.2)
				* CFrame.Angles(0, (k - 2) * 0.35, 0),
			darker(color, 0.3)
		)
	end
end

local function sponge(parent: Instance, foot: CFrame, height: number, color: Color3)
	local radius = height * 0.14
	upright(parent, "Tube", foot, height, radius, color)
	-- a flared lip and the dark mouth
	local lip = height * 0.06
	upright(
		parent,
		"Lip",
		foot * CFrame.new(0, height - lip, 0),
		lip + 0.02,
		radius * 1.18,
		paler(color, 0.15)
	)
	upright(
		parent,
		"Mouth",
		foot * CFrame.new(0, height + 0.02, 0),
		0.06,
		radius * 0.78,
		Color3.fromRGB(30, 18, 40)
	)
end

local function fan(parent: Instance, foot: CFrame, height: number, color: Color3)
	-- The fan faces along the foot's look; ribs fan out from the stem
	upright(parent, "Stem", foot, height * 0.22, height * 0.04, darker(color, 0.25))
	local disc = part(
		parent,
		"Fan",
		Vector3.new(0.3, height, height),
		foot * CFrame.new(0, height * 0.55, 0) * CFrame.Angles(0, math.rad(90), 0),
		color
	)
	disc.Shape = Enum.PartType.Cylinder
	for k = -2, 2 do
		local a = math.rad(k * 24)
		part(
			parent,
			"Rib",
			Vector3.new(height * 0.05, height * 0.48, 0.22),
			foot
				* CFrame.new(0, height * 0.2, -0.14)
				* CFrame.Angles(0, 0, a)
				* CFrame.new(0, height * 0.24, 0),
			darker(color, 0.22)
		)
	end
end

local function shell(parent: Instance, foot: CFrame, span: number, color: Color3, rng: Random)
	if rng:NextNumber() < 0.6 then
		-- A scallop: a shallow dome with ribs over it
		blob(
			parent,
			"Scallop",
			Vector3.new(span, span * 0.32, span * 0.9),
			foot * CFrame.new(0, span * 0.1, 0),
			color
		)
		for k = -2, 2 do
			part(
				parent,
				"ShellRib",
				Vector3.new(span * 0.07, span * 0.05, span * 0.46),
				foot
					* CFrame.new(0, span * 0.2, span * 0.12)
					* CFrame.Angles(0, math.rad(k * 22), 0)
					* CFrame.new(0, 0, -span * 0.2),
				darker(color, 0.12)
			)
		end
		blob(
			parent,
			"Hinge",
			Vector3.new(span * 0.32, span * 0.16, span * 0.2),
			foot * CFrame.new(0, span * 0.06, span * 0.42),
			darker(color, 0.08)
		)
	else
		-- A conch: tapering whorls along a tilted axis, a pale lip
		local axis = foot * CFrame.Angles(0, 0, math.rad(80))
		for k = 0, 2 do
			local r = span * (0.42 - k * 0.12)
			blob(
				parent,
				"Whorl",
				Vector3.new(r * 2, r * 2.2, r * 2),
				axis * CFrame.new(0, k * span * 0.28, 0),
				if k == 0 then color else darker(color, 0.08 * k)
			)
		end
		blob(
			parent,
			"Lip",
			Vector3.new(span * 0.5, span * 0.6, span * 0.18),
			axis * CFrame.new(span * 0.18, -span * 0.05, 0),
			paler(color, 0.35)
		)
	end
end

local function kelp(parent: Instance, foot: CFrame, height: number, color: Color3, rng: Random)
	local y = 0
	local count = 4
	for k = 1, count do
		local l = height / count * rng:NextNumber(1.0, 1.3)
		local lean = rng:NextNumber(0.15, 0.3) * (if k % 2 == 0 then -1 else 1)
		blob(
			parent,
			"KelpBlade",
			Vector3.new(height * 0.36, l * 1.15, height * 0.06),
			foot * CFrame.new(0, y + l / 2, 0) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), lean),
			if k == count then paler(color, 0.35) else color
		)
		y += l * 0.8
	end
	upright(parent, "KelpStalk", foot, y, height * 0.025, darker(color, 0.3))
end

local function blade(parent: Instance, foot: CFrame, length: number, color: Color3, rng: Random)
	-- A kelp leaf lying down, a little curled, with a darker midrib
	local leaf = foot * CFrame.Angles(rng:NextNumber(-0.12, 0.12), 0, rng:NextNumber(-0.18, 0.18))
	blob(
		parent,
		"Leaf",
		Vector3.new(length * 0.3, length * 0.06, length),
		leaf * CFrame.new(0, length * 0.03, 0),
		color
	)
	part(
		parent,
		"Midrib",
		Vector3.new(length * 0.03, length * 0.03, length * 0.8),
		leaf * CFrame.new(0, length * 0.055, 0),
		darker(color, 0.3)
	)
end

local function crystal(parent: Instance, foot: CFrame, height: number, color: Color3)
	-- A long prism shard, a lit core and a pointed tip
	local w = height * 0.24
	local body = height * 0.8
	local glass = part(
		parent,
		"Shard",
		Vector3.new(w, body, w),
		foot * CFrame.new(0, body / 2, 0),
		color,
		Enum.Material.Glass
	)
	glass.Transparency = 0.25
	part(
		parent,
		"Core",
		Vector3.new(w * 0.45, body * 0.86, w * 0.45),
		foot * CFrame.new(0, body / 2, 0),
		color,
		Enum.Material.Neon
	)
	local tip = height - body
	for k = 0, 1 do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Tip"
		wedge.Anchored = true
		wedge.CanCollide = false
		wedge.CanQuery = false
		wedge.CanTouch = false
		wedge.CastShadow = false
		wedge.Material = Enum.Material.Glass
		wedge.Transparency = 0.2
		wedge.Color = paler(color, 0.25)
		wedge.Size = Vector3.new(w, tip, w / 2)
		wedge.CFrame = foot
			* CFrame.new(0, body + tip / 2, 0)
			* CFrame.Angles(0, k * math.pi, 0)
			* CFrame.new(0, 0, -w / 4)
		wedge.Parent = parent
	end
end

local function rock(parent: Instance, foot: CFrame, height: number, color: Color3, rng: Random)
	local tone = color:Lerp(STONE, 0.6)
	blob(
		parent,
		"Rock",
		Vector3.new(height * rng:NextNumber(1.3, 1.7), height, height * rng:NextNumber(1.1, 1.4)),
		foot
			* CFrame.new(0, height * 0.4, 0)
			* CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2)),
		tone
	)
	blob(
		parent,
		"Rock",
		Vector3.new(height * 0.8, height * 0.6, height * 0.7),
		foot * CFrame.new(height * 0.6, height * 0.2, height * 0.3),
		darker(tone, 0.12)
	)
end

local function star(parent: Instance, foot: CFrame, span: number, color: Color3)
	for k = 0, 4 do
		local a = k * 2 * math.pi / 5
		blob(
			parent,
			"Arm",
			Vector3.new(span * 0.2, span * 0.1, span * 0.52),
			foot * CFrame.Angles(0, a, 0) * CFrame.new(0, span * 0.04, -span * 0.24),
			color
		)
	end
	blob(
		parent,
		"Middle",
		Vector3.new(span * 0.3, span * 0.14, span * 0.3),
		foot * CFrame.new(0, span * 0.06, 0),
		paler(color, 0.2)
	)
end

-- One piece of `kind` standing on `foot`, about `height` tall (for a Shell or a Star,
-- across; for a Blade, long). `tips`, when given, collects the staghorn's branch tips
-- (a lamp's glowing bulbs). Uses the imported prop where there is one (never for a
-- Sponge: the imported TubeSponge reads as two flat boxes up close, playtest
-- 2026-10-13).
function DenItems.piece(
	parent: Instance,
	kind: string,
	foot: CFrame,
	height: number,
	color: Color3,
	rng: Random,
	tips: { CFrame }?
)
	local propName = PROP_OF[kind]
	if propName and tips == nil then
		local box = Vector3.new(height * 0.9, height, height * 0.9)
		if kind == "Brain" then
			box = Vector3.new(height * 1.3, height, height * 1.3)
		elseif kind == "Fan" then
			box = Vector3.new(height, height, height * 0.3)
		elseif kind == "Shell" then
			box = Vector3.new(height, height * 0.5, height)
		elseif kind == "Crystal" then
			box = Vector3.new(height * 0.6, height, height * 0.6)
		end
		-- (a texture can only be darkened: tint toward white, so the color shows)
		if propPiece(parent, propName, foot, box, paler(color, 0.35)) then
			return
		end
	end
	if kind == "Staghorn" then
		staghorn(parent, foot, height, color, tips)
	elseif kind == "Anemone" then
		anemone(parent, foot, height, color, rng)
	elseif kind == "Brain" then
		brain(parent, foot, height, color, rng)
	elseif kind == "Sponge" then
		sponge(parent, foot, height, color)
	elseif kind == "Sponges" then
		-- three tubes of a clump (the Coral Garden's)
		for i, t in { { 0, 0, 1 }, { 0.38, 0.1, 0.72 }, { -0.3, 0.32, 0.6 } } do
			sponge(
				parent,
				foot * CFrame.new(t[1] * height * 0.5, 0, t[2] * height * 0.5),
				height * t[3],
				if i == 1 then color else darker(color, 0.18)
			)
		end
	elseif kind == "Fan" then
		fan(parent, foot, height, color)
	elseif kind == "Shell" then
		shell(parent, foot, height, color, rng)
	elseif kind == "Kelp" then
		kelp(parent, foot, height, color, rng)
	elseif kind == "Blade" then
		blade(parent, foot, height, color, rng)
	elseif kind == "Crystal" then
		crystal(parent, foot, height, color)
	elseif kind == "Rock" then
		rock(parent, foot, height, color, rng)
	elseif kind == "Star" then
		star(parent, foot, height, color)
	end
end

-- How tall a piece of `kind` stands in a cluster whose pieces reach `tall`, at
-- `f` (0.5..1) of its biggest: rocks and stars sit low, shells are small
local function pieceSize(kind: string, tall: number, f: number, halfX: number, halfZ: number): number
	if kind == "Rock" then
		return math.max(0.8, tall * 0.28 * f)
	elseif kind == "Star" then
		return math.max(1.2, tall * 0.34 * f)
	elseif kind == "Shell" then
		return math.clamp(0.9 + 1.4 * f, 0.8, math.max(1, tall * 0.7))
	elseif kind == "Blade" then
		return math.max(halfX, halfZ) * (0.35 + 0.3 * f)
	end
	return tall * f
end

-- A cluster (Config/Dens `cluster`) standing on `base` (its up is the cluster's): the
-- bed, then the pieces over it. Returns the part a light hangs on.
local function cluster(model: Model, item: DensConfig.Item, base: CFrame, glow: Color3): BasePart
	local spec = item.cluster :: DensConfig.Cluster
	local size = item.size
	local hx, hz = size.X / 2, size.Z / 2
	local rng = Random.new(seedOf(item.id))
	local colors = spec.colors or (if item.glow then { glow } else DenItems.REEF)
	-- The bed: an ellipsoid whose top is `bedTop` at its middle (pieces stand on its
	-- surface, so a heap's pieces rise toward the middle)
	local bedTop = 0
	local bedX, bedZ = hx * 0.98, hz * 0.98
	if spec.bed == "sand" then
		bedTop = math.min(0.5, size.Y * 0.1)
		blob(model, "Sand", Vector3.new(bedX * 2, bedTop * 2, bedZ * 2), base, SAND)
		-- a ring of rounded stones round its rim
		local around = math.floor(2 * math.pi * math.sqrt((hx * hx + hz * hz) / 2) / 1.6)
		for k = 1, around do
			local a = (k - 0.5) / around * 2 * math.pi
			local big = rng:NextNumber(0.9, 1.4)
			blob(
				model,
				"RimStone",
				Vector3.new(big * 1.3, big * 0.7, big),
				base
					* CFrame.new(math.cos(a) * hx * 0.97, big * 0.15, math.sin(a) * hz * 0.97)
					* CFrame.Angles(0, -a, 0),
				STONE:Lerp(STONE_LIGHT, rng:NextNumber())
			)
		end
	elseif spec.bed == "rock" then
		bedTop = math.clamp(size.Y * 0.12, 0.6, 1.4)
		bedX, bedZ = hx * 0.85, hz * 0.85
		blob(model, "Base", Vector3.new(bedX * 2, bedTop * 2, bedZ * 2), base, darker(STONE, 0.1))
		for k = 1, 3 do
			local a = k * 2.2
			blob(
				model,
				"BaseRock",
				Vector3.new(hx * 0.9, bedTop * 1.6, hz * 0.8),
				base
					* CFrame.new(math.cos(a) * hx * 0.35, 0, math.sin(a) * hz * 0.35)
					* CFrame.Angles(0, a, 0),
				STONE:Lerp(STONE_LIGHT, k / 4)
			)
		end
	elseif spec.bed == "kelp" then
		bedTop = size.Y * 0.4
		blob(model, "Mound", Vector3.new(bedX * 2, bedTop * 2, bedZ * 2), base, Color3.fromRGB(56, 92, 46))
	elseif spec.bed == "heap" then
		-- a low heap of sand under a pile, its pieces lying over it
		bedTop = size.Y * 0.5
		bedX, bedZ = hx * 0.8, hz * 0.8
		blob(model, "Heap", Vector3.new(bedX * 2, bedTop * 2, bedZ * 2), base, darker(SAND, 0.08))
	end
	local function surface(x: number, z: number): number
		if bedTop <= 0 then
			return 0
		end
		local d = 1 - (x / bedX) ^ 2 - (z / bedZ) ^ 2
		return bedTop * math.sqrt(math.max(d, 0))
	end
	local tall = size.Y - bedTop
	local spread = spec.spread or 0.78
	local tips: { CFrame }? = if spec.glow then {} else nil
	local turn = rng:NextNumber(0, 2 * math.pi)
	for i = 1, spec.count do
		local kind = spec.kinds[(i - 1) % #spec.kinds + 1]
		local color = colors[(i - 1) % #colors + 1]
		-- A sunflower spiral: even cover, the first pieces in the middle
		local r = if spec.count == 1 then 0 else math.sqrt((i - 0.5) / spec.count) * spread
		local a = turn + i * 2.39996 + rng:NextNumber(-0.25, 0.25)
		local x, z = math.cos(a) * r * hx, math.sin(a) * r * hz
		-- Bigger in the middle and toward the back (+z), smaller toward the front
		local back = (z / math.max(hz, 0.01) + 1) / 2
		local f = math.clamp((0.5 + 0.5 * rng:NextNumber()) * (1 - 0.3 * r) * (0.85 + 0.15 * back), 0.45, 1)
		local h = pieceSize(kind, tall, f, hx, hz)
		local sink = if kind == "Blade" or kind == "Star" or kind == "Shell" then 0.05 else 0.15
		local foot = base
			* CFrame.new(x, math.max(surface(x, z) - sink, 0), z)
			* CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0)
		if kind == "Crystal" or kind == "Shell" then
			-- shards lean out from the middle; shells lie every which way
			local out = math.atan2(z, x)
			local lean = if kind == "Crystal" then math.rad(8 + 26 * r) else rng:NextNumber(-0.35, 0.35)
			foot = base
				* CFrame.new(x, math.max(surface(x, z) - sink, 0), z)
				* CFrame.Angles(0, -out, 0)
				* CFrame.Angles(0, 0, -lean)
				* CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0)
		end
		DenItems.piece(model, kind, foot, h, color, rng, if kind == "Staghorn" then tips else nil)
	end
	-- A lamp: bulbs glowing at the branch tips
	if tips then
		for k, tip in tips do
			shaped(
				part(
					model,
					"Bulb",
					Vector3.one * (if k % 3 == 0 then 1.1 else 0.8),
					tip,
					glow,
					Enum.Material.Neon
				),
				Enum.PartType.Ball
			)
		end
	end
	local anchor = part(model, "Body", Vector3.one * 0.2, base * CFrame.new(0, size.Y * 0.6, 0), item.color)
	anchor.Transparency = 1
	return anchor
end

-- A box the imported prop is fitted into, or the stand-in that shows without it. A
-- Tripo prop faces +X in its GLB (Roblox's import turns it to -X), so `front` turns
-- it to face the box's look, and the box is fitted turned with it (a quarter turn
-- swaps its width and depth; a half turn doesn't). A glowing thing's prop is tinted
-- in the den's glow, except an `overlay` one: its texture lets the glow through where
-- its alpha is low (the banner's cloth), so only its MeshParts take the color.
local function dressed(model: Model, item: DensConfig.Item, box: CFrame, color: Color3): Part
	local stand = part(model, "Body", item.size, box, color, if item.glow then Enum.Material.Neon else SMOOTH)
	if item.prop then
		local fit, size = box, item.size
		if item.front then
			fit = box * CFrame.Angles(0, -math.rad(item.front), 0)
			if math.abs(math.sin(math.rad(item.front))) > 0.5 then
				size = Vector3.new(size.Z, size.Y, size.X)
			end
		end
		local prop = Props.dress(stand, item.prop, { cframe = fit, size = size })
		if prop and item.overlay then
			local cloth = clothOf(color)
			for _, descendant in prop:GetDescendants() do
				if descendant:IsA("MeshPart") then
					descendant.Color = cloth
				end
			end
		elseif prop and item.glow then
			Props.tint(prop, color)
		end
	end
	return stand
end

-- The generic mount for `surface`: a prop in its box (or the box itself as the stand-in)
local function mounted(model: Model, item: DensConfig.Item, surface: string, color: Color3): BasePart
	local size = item.size
	if surface == "wall" and table.find(item.kinds, "floor") then
		-- A floor thing on a wall juts out of the rock: its up turned to point out
		return dressed(model, item, CFrame.new(0, 0, -size.Y / 2) * CFrame.Angles(math.rad(-90), 0, 0), color)
	elseif surface == "wall" then
		-- A wall thing hangs flat on the rock, standing out by its depth
		return dressed(model, item, CFrame.new(0, 0, -size.Z / 2), color)
	elseif surface == "ceiling" then
		return dressed(model, item, CFrame.new(0, -size.Y / 2, 0), color)
	end
	return dressed(model, item, CFrame.new(0, size.Y / 2, 0), color)
end

-- A rug: a flat body in its own color, and its top-down art (Config/Textures
-- `rug<id>`, tools/props/rug_textures.py) as a Decal on an invisible sheet just
-- over it. Without the art, rings of its color stand in.
local function rug(model: Model, item: DensConfig.Item): Part
	local size = item.size
	local round = item.rug ~= "square"
	local function sheet(name: string, inset: number, y: number, color: Color3): Part
		local made = part(
			model,
			name,
			Vector3.new(size.X - inset, 0.1, size.Z - inset),
			CFrame.new(0, y, 0),
			color,
			Enum.Material.Fabric
		)
		if round then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = made
		end
		return made
	end
	local body = sheet("Rug", 0, 0.05, item.color)
	local art = (Config.Textures :: any)[`rug{item.id}`]
	if typeof(art) == "number" and art > 0 then
		local face = part(model, "Art", Vector3.new(size.X, 0.05, size.Z), CFrame.new(0, 0.13, 0), item.color)
		face.Transparency = 1
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Top
		decal.Texture = `rbxassetid://{art}`
		decal.Parent = face
	else
		local edge = math.max(1.2, size.X * 0.06)
		sheet("Border", edge, 0.07, darker(item.color, 0.3))
		sheet("Field", edge * 2.2, 0.09, paler(item.color, 0.18))
		sheet("Heart", math.min(size.X, size.Z) * 0.6, 0.11, darker(item.color, 0.2))
	end
	return body
end

-- The den props of batch 2 (owner, 2026-10-19: the buyable props "MUCH much better";
-- boards assets/concepts/DenPropsA.jpg and DenPropsB.jpg): Tripo models
-- (`den_props2_glb`), and these part-built stand-ins of the same designs until
-- they're imported. Each builds in its box (floor: standing up from y 0; wall: out
-- from the rock at z 0 along -z, centered on y 0; ceiling: hanging down from y 0),
-- its front toward -z, and returns the part its light hangs on.
local DRIFT = Color3.fromRGB(134, 128, 116)
local DRIFT_DARK = Color3.fromRGB(98, 92, 84)
local BRASS = Color3.fromRGB(196, 150, 64)
local GOLD = Color3.fromRGB(226, 178, 62)
local HULL = Color3.fromRGB(72, 58, 48)
local OLIVE = Color3.fromRGB(128, 122, 62)
local MOSS = Color3.fromRGB(98, 142, 62)
local TEAL = Color3.fromRGB(56, 160, 166)
local ORANGE = Color3.fromRGB(240, 112, 40)

-- A cylinder whose axis runs along `axis` ("X", "Y" or "Z") at `cframe`
local function rod(
	parent: Instance,
	name: string,
	cframe: CFrame,
	length: number,
	radius: number,
	color: Color3,
	axis: string,
	material: Enum.Material?
): Part
	local turn = if axis == "Y"
		then CFrame.Angles(0, 0, math.rad(90))
		elseif axis == "Z" then CFrame.Angles(0, math.rad(90), 0)
		else CFrame.new()
	return shaped(
		part(parent, name, Vector3.new(length, radius * 2, radius * 2), cframe * turn, color, material),
		Enum.PartType.Cylinder
	)
end

-- A beam from `a` to `b` (square, `thick` across)
local function beam(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	thick: number,
	color: Color3
): Part
	return part(
		parent,
		name,
		Vector3.new(thick, thick, (b - a).Magnitude),
		CFrame.lookAt((a + b) / 2, b),
		color
	)
end

-- A right-angled triangle of cloth in the x-y plane at depth `z`: its right angle at
-- `corner`, one leg `across` studs along x (signed), the other `down` studs down
local function pennant(
	parent: Instance,
	corner: Vector3,
	across: number,
	down: number,
	color: Color3,
	thick: number
): WedgePart
	local made = Instance.new("WedgePart")
	made.Name = "Tail"
	made.Anchored = true
	made.CanCollide = false
	made.CanQuery = false
	made.CanTouch = false
	made.CastShadow = false
	made.Material = Enum.Material.Fabric
	made.Color = color
	made.Size = Vector3.new(thick, down, math.abs(across))
	-- The wedge's full faces are its bottom and back: its up runs down the cloth, its
	-- back toward `corner`'s side, so its right angle sits on the corner
	local side = if across >= 0 then 1 else -1
	local center = corner + Vector3.new(-across / 2, -down / 2, 0)
	made.CFrame =
		CFrame.fromMatrix(center, Vector3.new(0, 0, side), Vector3.new(0, -1, 0), Vector3.new(side, 0, 0))
	made.Parent = parent
	return made
end

local STAND_INS: { [string]: (Model, DensConfig.Item, Color3, Color3) -> BasePart } = {}

-- Planks on two crossed trestles, a mussel-shell bowl of pearls and a jar candle
STAND_INS.DriftwoodTable = function(model, item)
	local size = item.size
	local top = size.Y * 0.76
	for k = -1, 1 do
		part(
			model,
			"Plank",
			Vector3.new(size.X, 0.7, size.Z * 0.31),
			CFrame.new(0, top - 0.35, k * size.Z * 0.33) * CFrame.Angles(0, 0, math.rad(k * 0.8)),
			if k == 0 then DRIFT else DRIFT:Lerp(DRIFT_DARK, 0.3)
		)
	end
	local legs = top - 0.7
	local tilt = math.atan2(size.Z * 0.36, legs)
	for _, side in { -1, 1 } do
		local x = side * size.X * 0.36
		for _, sign in { -1, 1 } do
			part(
				model,
				"Trestle",
				Vector3.new(0.7, legs / math.cos(tilt), 0.7),
				CFrame.new(x, legs / 2, 0) * CFrame.Angles(sign * tilt, 0, 0),
				DRIFT_DARK
			)
		end
	end
	part(model, "Stretcher", Vector3.new(size.X * 0.72, 0.5, 0.5), CFrame.new(0, legs * 0.5, 0), DRIFT_DARK)
	-- the bowl and its pearls
	local bowl = CFrame.new(-size.X * 0.16, top + 0.35, size.Z * 0.08)
	blob(model, "Bowl", Vector3.new(2.4, 0.8, 1.9), bowl, Color3.fromRGB(64, 92, 176))
	for i = 1, 5 do
		local a = i / 5 * 2 * math.pi
		shaped(
			part(
				model,
				"Pearl",
				Vector3.one * 0.42,
				bowl * CFrame.new(math.cos(a) * 0.45, 0.35, math.sin(a) * 0.3),
				PEARL
			),
			Enum.PartType.Ball
		)
	end
	local jar = CFrame.new(size.X * 0.2, top, -size.Z * 0.12)
	local glass = upright(model, "Jar", jar, 1.5, 0.6, Color3.fromRGB(120, 210, 196), Enum.Material.Glass)
	glass.Transparency = 0.35
	shaped(
		part(
			model,
			"Candle",
			Vector3.one * 0.45,
			jar * CFrame.new(0, 0.6, 0),
			Color3.fromRGB(150, 255, 230),
			Enum.Material.Neon
		),
		Enum.PartType.Ball
	)
	local body =
		part(model, "Body", Vector3.new(size.X, 0.2, size.Z * 0.9), CFrame.new(0, top - 0.35, 0), DRIFT_DARK)
	body.Transparency = 1
	return body
end

-- A low oval frame of olive kelp rope, a moss mattress, teal pillows against a
-- latticed headboard at the back (+z), a blanket folded back at the foot
STAND_INS.KelpBed = function(model, item)
	local size = item.size
	local frame = blob(
		model,
		"Frame",
		Vector3.new(size.X, size.Y * 0.42, size.Z * 0.94),
		CFrame.new(0, size.Y * 0.3, 0),
		OLIVE
	)
	blob(
		model,
		"Rope",
		Vector3.new(size.X * 1.0, size.Y * 0.14, size.Z * 0.96),
		CFrame.new(0, size.Y * 0.48, 0),
		darker(OLIVE, 0.18)
	)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			upright(
				model,
				"Post",
				CFrame.new(x * size.X * 0.4, 0, z * size.Z * 0.38),
				size.Y * 0.62,
				0.45,
				darker(OLIVE, 0.3)
			)
		end
	end
	blob(
		model,
		"Mattress",
		Vector3.new(size.X * 0.86, size.Y * 0.3, size.Z * 0.84),
		CFrame.new(0, size.Y * 0.56, -size.Z * 0.02),
		MOSS
	)
	-- the headboard: a tall oval of rope, crossed by a lattice
	local head = CFrame.new(0, size.Y * 0.62, size.Z * 0.45)
	blob(model, "Headboard", Vector3.new(size.X * 0.92, size.Y * 0.8, 0.5), head, OLIVE)
	for _, sign in { -1, 1 } do
		part(
			model,
			"Lattice",
			Vector3.new(size.X * 0.7, 0.25, 0.3),
			head * CFrame.new(0, 0, -0.3) * CFrame.Angles(0, 0, math.rad(sign * 28)),
			darker(OLIVE, 0.25)
		)
	end
	for _, x in { -1, 1 } do
		blob(
			model,
			"Pillow",
			Vector3.new(size.X * 0.36, size.Y * 0.2, size.Z * 0.16),
			CFrame.new(x * size.X * 0.2, size.Y * 0.74, size.Z * 0.3) * CFrame.Angles(math.rad(-14), 0, 0),
			TEAL
		)
	end
	-- the blanket folded back over the foot of the mattress
	part(
		model,
		"Blanket",
		Vector3.new(size.X * 0.8, 0.5, size.Z * 0.26),
		CFrame.new(0, size.Y * 0.7, -size.Z * 0.2),
		darker(MOSS, 0.22),
		Enum.Material.Fabric
	)
	return frame
end

-- A fluted column on a stepped plinth, an open blue-violet clam holding the pearl
STAND_INS.PearlPedestal = function(model, item, color)
	local size = item.size
	local w, h = size.X / 5, size.Y / 10 -- the v3 pedestal was 5 x 10 x 5
	part(model, "Plinth", Vector3.new(4.8 * w, 0.8 * h, 4.8 * w), CFrame.new(0, 0.4 * h, 0), STONE)
	part(model, "Step", Vector3.new(3.8 * w, 0.6 * h, 3.8 * w), CFrame.new(0, 1.1 * h, 0), STONE_LIGHT)
	upright(model, "Column", CFrame.new(0, 1.4 * h, 0), 5 * h, 1.1 * w, STONE_LIGHT)
	for i = 1, 8 do
		local a = i / 8 * 2 * math.pi
		upright(
			model,
			"Flute",
			CFrame.new(math.cos(a) * 1.1 * w, 1.4 * h, math.sin(a) * 1.1 * w),
			5 * h,
			0.16 * w,
			STONE
		)
	end
	part(model, "Capital", Vector3.new(3.4 * w, 0.6 * h, 3.4 * w), CFrame.new(0, 6.7 * h, 0), STONE)
	for _, x in { -1, 1 } do
		rod(model, "Scroll", CFrame.new(x * 1.5 * w, 6.55 * h, 0), 3.2 * w, 0.32 * w, STONE_LIGHT, "Z")
	end
	local clam = Color3.fromRGB(104, 96, 200)
	blob(model, "Clam", Vector3.new(4.4 * w, 1.2 * h, 3.6 * w), CFrame.new(0, 7.3 * h, 0), clam)
	blob(
		model,
		"Lid",
		Vector3.new(4.4 * w, 0.9 * h, 3.6 * w),
		CFrame.new(0, 8.4 * h, 1.5 * w) * CFrame.Angles(math.rad(62), 0, 0),
		paler(clam, 0.12)
	)
	local pearl = shaped(
		part(model, "Pearl", Vector3.one * 2.3 * math.min(w, h), CFrame.new(0, 8.3 * h, -0.1 * w), PEARL),
		Enum.PartType.Ball
	)
	pearl.Reflectance = 0.35
	shaped(
		part(
			model,
			"Shine",
			Vector3.one * 1.2 * math.min(w, h),
			CFrame.new(0, 8.3 * h, -0.1 * w),
			paler(color, 0.5),
			Enum.Material.Neon
		),
		Enum.PartType.Ball
	).Transparency =
		0.55
	return pearl
end

-- Two rings of mossy stones round a bronze vent grate (the bubbles: `column` below)
STAND_INS.BubbleColumn = function(model, item)
	local size = item.size
	for row = 0, 1 do
		local around = 9
		for i = 1, around do
			local a = (i + row * 0.5) / around * 2 * math.pi
			local radius = 0.38 - row * 0.03
			local stone = blob(
				model,
				"Stone",
				Vector3.new(size.X * 0.24, size.Y * 0.46, size.Z * 0.2),
				CFrame.new(
					math.cos(a) * size.X * radius,
					size.Y * (0.24 + row * 0.42),
					math.sin(a) * size.Z * radius
				) * CFrame.Angles(0, -a, 0),
				STONE:Lerp(STONE_LIGHT, (i % 3) / 3)
			)
			if (i + row) % 2 == 0 then
				blob(
					model,
					"Moss",
					Vector3.new(size.X * 0.13, size.Y * 0.12, size.Z * 0.11),
					stone.CFrame * CFrame.new(0, size.Y * 0.2, 0),
					MOSS
				)
			end
		end
	end
	local grate = upright(model, "Grate", CFrame.new(0, size.Y * 0.18, 0), size.Y * 0.2, size.X * 0.22, BRASS)
	for k = -2, 2 do
		part(
			model,
			"Slat",
			Vector3.new(size.X * 0.34, size.Y * 0.08, size.X * 0.04),
			CFrame.new(0, size.Y * 0.4, k * size.X * 0.075),
			darker(BRASS, 0.45)
		)
	end
	return grate
end

-- Three seats of teal kelp cloth in a driftwood frame, orange sponge bolsters
-- against the arms, scallop shells on the back's corners
STAND_INS.SpongeSofa = function(model, item)
	local size = item.size
	local base = part(
		model,
		"Base",
		Vector3.new(size.X * 0.9, size.Y * 0.16, size.Z * 0.8),
		CFrame.new(0, size.Y * 0.24, 0),
		DRIFT
	)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			part(
				model,
				"Leg",
				Vector3.new(0.7, size.Y * 0.18, 0.7),
				CFrame.new(x * size.X * 0.43, size.Y * 0.09, z * size.Z * 0.36),
				DRIFT_DARK
			)
		end
		-- the arm: a rail on slats
		part(
			model,
			"Arm",
			Vector3.new(size.X * 0.06, size.Y * 0.06, size.Z * 0.88),
			CFrame.new(x * size.X * 0.46, size.Y * 0.6, 0),
			DRIFT
		)
		for k = -1, 1 do
			part(
				model,
				"Slat",
				Vector3.new(size.X * 0.03, size.Y * 0.28, 0.45),
				CFrame.new(x * size.X * 0.46, size.Y * 0.44, k * size.Z * 0.28),
				DRIFT_DARK
			)
		end
		-- a sponge bolster lying along the arm, a scallop on the back's corner
		rod(
			model,
			"Bolster",
			CFrame.new(x * size.X * 0.37, size.Y * 0.5, -size.Z * 0.04),
			size.Z * 0.55,
			size.Y * 0.1,
			ORANGE,
			"Z"
		)
		blob(
			model,
			"Scallop",
			Vector3.new(size.X * 0.08, size.Y * 0.13, size.Z * 0.06),
			CFrame.new(x * size.X * 0.45, size.Y * 0.9, size.Z * 0.4),
			ORANGE
		)
	end
	part(
		model,
		"Back",
		Vector3.new(size.X * 0.88, size.Y * 0.44, size.Z * 0.08),
		CFrame.new(0, size.Y * 0.58, size.Z * 0.4),
		DRIFT_DARK
	)
	part(
		model,
		"Rail",
		Vector3.new(size.X * 0.96, size.Y * 0.06, size.Z * 0.12),
		CFrame.new(0, size.Y * 0.82, size.Z * 0.4),
		DRIFT
	)
	for k = -1, 1 do
		blob(
			model,
			"Seat",
			Vector3.new(size.X * 0.27, size.Y * 0.16, size.Z * 0.64),
			CFrame.new(k * size.X * 0.28, size.Y * 0.38, -size.Z * 0.06),
			TEAL
		)
		blob(
			model,
			"Cushion",
			Vector3.new(size.X * 0.27, size.Y * 0.32, size.Z * 0.16),
			CFrame.new(k * size.X * 0.28, size.Y * 0.6, size.Z * 0.27) * CFrame.Angles(math.rad(-10), 0, 0),
			darker(TEAL, 0.08)
		)
	end
	return base
end

-- Bowed hull planks round four shelves of books and bottles, a brass porthole in
-- its side; its back (+z) stands against a wall
STAND_INS.ShipwreckBookshelf = function(model, item)
	local size = item.size
	for _, x in { -1, 1 } do
		-- each side two planks meeting at a slight bow
		for _, half in { -1, 1 } do
			part(
				model,
				"Side",
				Vector3.new(size.X * 0.09, size.Y * 0.52, size.Z * 0.86),
				CFrame.new(x * size.X * 0.45, size.Y * (0.5 + half * 0.245), 0)
					* CFrame.Angles(0, 0, math.rad(x * half * 3)),
				HULL
			)
		end
	end
	part(
		model,
		"Back",
		Vector3.new(size.X * 0.84, size.Y, size.Z * 0.08),
		CFrame.new(0, size.Y * 0.5, size.Z * 0.42),
		darker(HULL, 0.2)
	)
	local shelves = { 0.03, 0.26, 0.48, 0.7, 0.93 }
	local rng = Random.new(seedOf(item.id))
	local spines = {
		Color3.fromRGB(150, 44, 40),
		Color3.fromRGB(40, 56, 110),
		Color3.fromRGB(46, 104, 66),
		Color3.fromRGB(110, 70, 44),
		Color3.fromRGB(32, 108, 112),
	}
	for i, y in shelves do
		part(
			model,
			"Shelf",
			Vector3.new(size.X * 0.82, size.Y * 0.035, size.Z * 0.8),
			CFrame.new(0, size.Y * y, 0),
			Color3.fromRGB(96, 76, 58)
		)
		local above = shelves[i + 1]
		if above == nil then
			continue
		end
		local room = size.Y * (above - y) - size.Y * 0.035
		local x = -size.X * 0.38
		while x < size.X * 0.36 do
			local width = size.X * rng:NextNumber(0.035, 0.065)
			local tall = room * rng:NextNumber(0.62, 0.86)
			local roll = rng:NextNumber()
			if roll < 0.1 then
				local bottle = upright(
					model,
					"Bottle",
					CFrame.new(x + width, size.Y * y + size.Y * 0.018, -size.Z * 0.05),
					tall * 0.6,
					width * 0.8,
					Color3.fromRGB(110, 190, 170),
					Enum.Material.Glass
				)
				bottle.Transparency = 0.3
				x += width * 2.2
			elseif roll < 0.15 then
				DenItems.piece(
					model,
					"Staghorn",
					CFrame.new(x + width, size.Y * y + size.Y * 0.018, -size.Z * 0.05),
					tall * 0.8,
					Color3.fromRGB(220, 60, 60),
					rng
				)
				x += width * 3
			else
				part(
					model,
					"Book",
					Vector3.new(width, tall, size.Z * 0.5),
					CFrame.new(x + width / 2, size.Y * y + size.Y * 0.018 + tall / 2, -size.Z * 0.04)
						* CFrame.Angles(0, 0, math.rad(if roll > 0.92 then 9 else 0)),
					spines[rng:NextInteger(1, #spines)]
				)
				x += width + 0.05
			end
		end
	end
	-- the porthole, in its right-hand side (seen from the front)
	local hole = CFrame.new(-size.X * 0.5 - 0.1, size.Y * 0.62, 0)
	rod(model, "Porthole", hole, 0.35, size.Z * 0.24, BRASS, "X")
	rod(
		model,
		"PortGlass",
		hole * CFrame.new(-0.05, 0, 0),
		0.4,
		size.Z * 0.16,
		Color3.fromRGB(110, 190, 220),
		"X",
		Enum.Material.Glass
	)
	local body = part(
		model,
		"Body",
		Vector3.new(size.X * 0.8, 0.2, size.Z * 0.6),
		CFrame.new(0, size.Y * 0.5, 0),
		HULL
	)
	body.Transparency = 1
	return body
end

-- Three glowing amber jellyfish on brass chains of different lengths from a plate
STAND_INS.JellyLamp = function(model, item, color)
	local size = item.size
	local across = math.min(size.X, size.Z)
	local k = across / 4
	rod(model, "Plate", CFrame.new(0, -0.18, 0), 0.35, across * 0.48, BRASS, "Y")
	local main: BasePart? = nil
	for i, drop in { 0.12, 0.48, 0.3 } do
		local a = i / 3 * 2 * math.pi
		local x, z = math.cos(a) * across * 0.27, math.sin(a) * across * 0.27
		local chain = size.Y * drop
		part(
			model,
			"Chain",
			Vector3.new(0.12, chain, 0.12),
			CFrame.new(x, -0.35 - chain / 2, z),
			BRASS,
			Enum.Material.Metal
		)
		local top = -0.35 - chain
		local bell =
			blob(model, "Bell", Vector3.new(1.5, 1.0, 1.5) * k, CFrame.new(x, top - 0.5 * k, z), color)
		bell.Material = Enum.Material.Glass
		bell.Transparency = 0.25
		local core = shaped(
			part(
				model,
				"Core",
				Vector3.new(0.8, 0.55, 0.8) * k,
				CFrame.new(x, top - 0.55 * k, z),
				color,
				Enum.Material.Neon
			),
			Enum.PartType.Ball
		)
		if i == 2 then
			main = core
		end
		for t = 1, 6 do
			local b = t / 6 * 2 * math.pi
			local length = (1.0 + (t % 2) * 0.4) * k
			part(
				model,
				"Arm",
				Vector3.new(0.14 * k, length, 0.22 * k),
				CFrame.new(x + math.cos(b) * 0.4 * k, top - 0.95 * k - length / 2, z + math.sin(b) * 0.4 * k)
					* CFrame.Angles(math.sin(b) * 0.12, 0, math.cos(b) * 0.12),
				paler(color, 0.15)
			)
		end
	end
	return main :: BasePart
end

-- A small iron lantern of sea glass hung from a scrolled bracket on a wooden plate
STAND_INS.SeaGlassLantern = function(model, item, color)
	local size = item.size
	local k = size.Y / 5
	part(
		model,
		"Plate",
		Vector3.new(1.1 * k, 2.2 * k, 0.3 * k),
		CFrame.new(0, 1.3 * k, -0.15 * k),
		darker(WOOD, 0.2)
	)
	part(
		model,
		"Bracket",
		Vector3.new(0.2 * k, 0.2 * k, 2.6 * k),
		CFrame.new(0, 1.8 * k, -1.6 * k),
		IRON,
		Enum.Material.Metal
	)
	beam(model, "Brace", Vector3.new(0, 0.9, -0.3) * k, Vector3.new(0, 1.8, -1.5) * k, 0.18 * k, IRON)
	shaped(
		part(
			model,
			"Curl",
			Vector3.one * 0.5 * k,
			CFrame.new(0, 1.45 * k, -0.95 * k),
			IRON,
			Enum.Material.Metal
		),
		Enum.PartType.Ball
	)
	local at = -2.4 * k
	part(
		model,
		"Hanger",
		Vector3.new(0.12, 1.3 * k, 0.12) * Vector3.new(k, 1, k),
		CFrame.new(0, 1.05 * k, at),
		IRON,
		Enum.Material.Metal
	)
	local glass = part(
		model,
		"Glass",
		Vector3.new(1.1 * k, 1.6 * k, 1.1 * k),
		CFrame.new(0, -0.85 * k, at),
		color,
		Enum.Material.Glass
	)
	glass.Transparency = 0.25
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			part(
				model,
				"Post",
				Vector3.new(0.14, 1.7, 0.14) * k,
				CFrame.new(x * 0.56 * k, -0.85 * k, at + z * 0.56 * k),
				IRON,
				Enum.Material.Metal
			)
		end
	end
	part(model, "Cap", Vector3.new(1.4, 0.3, 1.4) * k, CFrame.new(0, 0.05 * k, at), IRON, Enum.Material.Metal)
	part(
		model,
		"Peak",
		Vector3.new(0.8, 0.3, 0.8) * k,
		CFrame.new(0, 0.33 * k, at),
		IRON,
		Enum.Material.Metal
	)
	part(
		model,
		"Foot",
		Vector3.new(1.3, 0.2, 1.3) * k,
		CFrame.new(0, -1.75 * k, at),
		IRON,
		Enum.Material.Metal
	)
	return shaped(
		part(model, "Flame", Vector3.one * 0.55 * k, CFrame.new(0, -0.85 * k, at), color, Enum.Material.Neon),
		Enum.PartType.Ball
	)
end

-- A branching orange coral trunk on a rock under a glowing fan-coral shade
STAND_INS.CoralLamp = function(model, item, color)
	local size = item.size
	blob(
		model,
		"Rock",
		Vector3.new(size.X * 0.7, size.Y * 0.1, size.Z * 0.7),
		CFrame.new(0, size.Y * 0.04, 0),
		STONE
	)
	upright(model, "Trunk", CFrame.new(0, size.Y * 0.06, 0), size.Y * 0.66, size.X * 0.06, ORANGE)
	for _, side in { -1, 1 } do
		upright(
			model,
			"Branch",
			CFrame.new(0, size.Y * (0.3 + side * 0.06), 0) * CFrame.Angles(0, 0, math.rad(side * 38)),
			size.Y * 0.2,
			size.X * 0.04,
			ORANGE
		)
	end
	upright(model, "Collar", CFrame.new(0, size.Y * 0.71, 0), size.Y * 0.03, size.X * 0.13, STONE_LIGHT)
	for i = 1, 3 do
		local a = i / 3 * 2 * math.pi
		blob(
			model,
			"Fan",
			Vector3.new(size.X * 0.62, size.Y * 0.22, size.Z * 0.07),
			CFrame.new(0, size.Y * 0.8, 0)
				* CFrame.Angles(0, a, 0)
				* CFrame.new(0, 0, -size.Z * 0.2)
				* CFrame.Angles(math.rad(-52), 0, 0),
			darker(ORANGE, 0.05)
		)
	end
	return shaped(
		part(
			model,
			"Glow",
			Vector3.one * size.X * 0.24,
			CFrame.new(0, size.Y * 0.78, 0),
			color,
			Enum.Material.Neon
		),
		Enum.PartType.Ball
	)
end

-- A swallowtail banner in the den's glow on a driftwood pole: gold trim and a gold
-- fish leaping a wave
STAND_INS.Banner = function(model, item, glow)
	local color = clothOf(glow)
	local size = item.size
	local depth = -size.Z * 0.55
	rod(model, "Pole", CFrame.new(0, size.Y * 0.42, depth), size.X, 0.28, DRIFT, "X")
	for _, side in { -1, 1 } do
		beam(
			model,
			"Rope",
			Vector3.new(side * size.X * 0.4, size.Y * 0.42, depth),
			Vector3.new(0, size.Y * 0.5, -0.1),
			0.12,
			darker(WOOD, 0.35)
		)
	end
	local width = size.X * 0.8
	local top, foot = size.Y * 0.4, -size.Y * 0.28
	local cloth = part(
		model,
		"Cloth",
		Vector3.new(width, top - foot, 0.14),
		CFrame.new(0, (top + foot) / 2, depth - 0.2),
		color,
		Enum.Material.Fabric
	)
	-- the swallowtail: two triangles down from the cloth's foot, notched in the middle
	for _, side in { -1, 1 } do
		pennant(
			model,
			Vector3.new(side * width / 2, foot, depth - 0.2),
			side * width / 2,
			size.Y * 0.22,
			color,
			0.14
		)
	end
	for _, side in { -1, 1 } do
		part(
			model,
			"Trim",
			Vector3.new(0.22, top - foot + size.Y * 0.2, 0.16),
			CFrame.new(side * (width / 2 - 0.25), (top + foot - size.Y * 0.2) / 2, depth - 0.24),
			GOLD
		)
	end
	part(model, "TrimTop", Vector3.new(width, 0.22, 0.16), CFrame.new(0, top - 0.3, depth - 0.24), GOLD)
	blob(
		model,
		"Fish",
		Vector3.new(width * 0.42, size.Y * 0.1, 0.12),
		CFrame.new(0, size.Y * 0.1, depth - 0.3) * CFrame.Angles(0, 0, math.rad(20)),
		GOLD
	)
	for k = -1, 1 do
		blob(
			model,
			"Wave",
			Vector3.new(width * 0.2, size.Y * 0.04, 0.12),
			CFrame.new(k * width * 0.18, -size.Y * 0.04 + math.abs(k) * 0.3, depth - 0.3),
			GOLD
		)
	end
	return cloth
end

-- A dark wood cabinet with brass corners and a record on the turntable, its horn a
-- great spiral conch: cool white with rust bands, deep orange in the bell
STAND_INS.ConchGramophone = function(model, item)
	local size = item.size
	local wood = Color3.fromRGB(86, 60, 42)
	local h, w, d = size.Y * 0.36, size.X * 0.86, size.Z * 0.6
	local cabinet = part(model, "Cabinet", Vector3.new(w, h, d), CFrame.new(0, h / 2, size.Z * 0.12), wood)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			for _, y in { 0.06, 0.94 } do
				part(
					model,
					"Corner",
					Vector3.one * size.X * 0.11,
					CFrame.new(x * w / 2, h * y, size.Z * 0.12 + z * d / 2),
					BRASS
				)
			end
		end
	end
	rod(
		model,
		"Crank",
		CFrame.new(w / 2 + 0.3, h * 0.5, size.Z * 0.12),
		0.6,
		0.12,
		IRON,
		"X",
		Enum.Material.Metal
	)
	local deck = CFrame.new(-size.X * 0.06, h, size.Z * 0.08)
	rod(model, "Record", deck * CFrame.new(0, 0.06, 0), 0.12, size.X * 0.3, Color3.fromRGB(26, 26, 30), "Y")
	rod(model, "Label", deck * CFrame.new(0, 0.1, 0), 0.06, size.X * 0.08, Color3.fromRGB(196, 56, 44), "Y")
	beam(
		model,
		"Arm",
		Vector3.new(size.X * 0.3, h + 0.5, size.Z * 0.3),
		Vector3.new(size.X * 0.05, h + 0.25, size.Z * 0.12),
		0.18,
		BRASS
	)
	-- the horn: a conch's whorls rising from the back and swelling toward the bell
	local white = Color3.fromRGB(226, 230, 236)
	local rust = Color3.fromRGB(150, 70, 36)
	local whorls = {
		{ y = 0.45, z = 0.36, s = 0.16 },
		{ y = 0.55, z = 0.3, s = 0.22 },
		{ y = 0.64, z = 0.18, s = 0.28 },
		{ y = 0.72, z = 0.02, s = 0.36 },
	}
	for i, whorl in whorls do
		blob(
			model,
			"Whorl",
			Vector3.new(size.X * whorl.s, size.X * whorl.s * 0.9, size.Z * whorl.s * 0.9),
			CFrame.new(size.X * 0.08, size.Y * whorl.y, size.Z * whorl.z),
			if i % 2 == 0 then rust else white
		)
	end
	local bell = CFrame.new(size.X * 0.04, size.Y * 0.78, -size.Z * 0.2)
	rod(model, "Bell", bell, size.Z * 0.12, size.X * 0.36, white, "Z")
	rod(model, "Throat", bell * CFrame.new(0, 0, -0.08), size.Z * 0.12, size.X * 0.29, ORANGE, "Z")
	return cabinet
end

-- A sea chart in a thick driftwood frame bound with rope at the corners: islands, a
-- dotted path to a red X and a compass star
STAND_INS.TreasureChart = function(model, item)
	local size = item.size
	local depth = -size.Z * 0.5
	local bar = size.Y * 0.11
	for _, y in { -1, 1 } do
		part(
			model,
			"Frame",
			Vector3.new(size.X, bar, size.Z * 0.9),
			CFrame.new(0, y * (size.Y / 2 - bar / 2), depth),
			DRIFT
		)
	end
	for _, x in { -1, 1 } do
		part(
			model,
			"Frame",
			Vector3.new(bar, size.Y, size.Z * 0.9),
			CFrame.new(x * (size.X / 2 - bar / 2), 0, depth),
			DRIFT_DARK
		)
		for _, y in { -1, 1 } do
			blob(
				model,
				"Rope",
				Vector3.new(bar * 1.5, bar * 1.5, size.Z * 1.0),
				CFrame.new(x * (size.X / 2 - bar / 2), y * (size.Y / 2 - bar / 2), depth)
					* CFrame.Angles(0, 0, math.rad(45)),
				darker(WOOD, 0.4)
			)
		end
	end
	local face = -size.Z * 0.7
	local chart = part(
		model,
		"Chart",
		Vector3.new(size.X - bar * 2, size.Y - bar * 2, 0.12),
		CFrame.new(0, 0, face),
		Color3.fromRGB(124, 170, 172)
	)
	local land = Color3.fromRGB(110, 150, 70)
	for _, island in
		{ { -0.26, 0.18, 0.2 }, { 0.22, 0.24, 0.16 }, { -0.14, -0.2, 0.12 }, { 0.05, 0.02, 0.06 } }
	do
		blob(
			model,
			"Island",
			Vector3.new(size.X * island[3], size.Y * island[3] * 0.9, 0.08),
			CFrame.new(size.X * island[1], size.Y * island[2], face - 0.08),
			land
		)
	end
	for i = 0, 7 do
		local t = i / 7
		part(
			model,
			"Path",
			Vector3.new(0.18, 0.18, 0.06),
			CFrame.new(size.X * (-0.2 + t * 0.4), size.Y * (0.08 - math.sin(t * math.pi) * 0.18), face - 0.08),
			Color3.fromRGB(60, 50, 44)
		)
	end
	for _, sign in { -1, 1 } do
		part(
			model,
			"X",
			Vector3.new(size.X * 0.07, 0.16, 0.06),
			CFrame.new(size.X * 0.22, -size.Y * 0.08, face - 0.1) * CFrame.Angles(0, 0, math.rad(sign * 45)),
			Color3.fromRGB(200, 40, 36)
		)
	end
	for _, turn in { 0, 45, 90, 135 } do
		part(
			model,
			"Compass",
			Vector3.new(size.X * (if turn % 90 == 0 then 0.1 else 0.06), 0.1, 0.06),
			CFrame.new(size.X * 0.32, -size.Y * 0.24, face - 0.1) * CFrame.Angles(0, 0, math.rad(turn)),
			Color3.fromRGB(70, 62, 56)
		)
	end
	return chart
end

-- A column of bubbles from the Bubble Column's grate, rising to the ceiling
local function column(model: Model, item: DensConfig.Item)
	local vent = part(model, "Vent", Vector3.new(1, 0.2, 1), CFrame.new(0, item.size.Y * 0.45, 0), item.color)
	vent.Transparency = 1
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Rate = 16
	bubbles.Lifetime = NumberRange.new(4, 6)
	bubbles.Speed = NumberRange.new(5, 8)
	bubbles.SpreadAngle = Vector2.new(6, 6)
	bubbles.Acceleration = Vector3.new(0, 1, 0)
	bubbles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(1, 0.8),
	})
	bubbles.Transparency = NumberSequence.new(0.2, 0.85)
	bubbles.LightEmission = 0.4
	bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 250, 255))
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.Parent = vent
end

-- The thing `item` in the den's glow color, at the identity frame (move it with
-- PivotTo). `surface` picks how a thing that goes in more than one place is
-- mounted (the Crystal Cluster juts out of a wall).
function DenItems.build(item: DensConfig.Item, glow: Color3, surface: string): Model
	local model = Instance.new("Model")
	model.Name = item.id
	-- A glowing thing is in the den's glow; a lamp in its own light's color
	local color = if item.glow then glow else item.color
	local size = item.size
	local main: BasePart
	local standIn = STAND_INS[item.id]
	if standIn then
		-- Its model where it's imported, else the part-built stand-in
		if item.prop and Props.template("WorldProps", item.prop) then
			main = mounted(model, item, surface, color)
		else
			main = standIn(model, item, if item.lamp then item.lamp else color, glow)
		end
	elseif item.id == "KelpRug" then
		main = part(
			model,
			"Rug",
			Vector3.new(size.X, 0.14, size.Z),
			CFrame.new(0, 0.07, 0),
			item.color,
			Enum.Material.Fabric
		)
		local edge = math.max(0.7, size.X * 0.05)
		part(
			model,
			"Border",
			Vector3.new(size.X - edge, 0.15, size.Z - edge),
			CFrame.new(0, 0.08, 0),
			darker(item.color, 0.3),
			Enum.Material.Fabric
		)
		part(
			model,
			"Field",
			Vector3.new(size.X - edge * 2, 0.16, size.Z - edge * 2),
			CFrame.new(0, 0.09, 0),
			item.color:Lerp(Color3.fromRGB(196, 220, 170), 0.25),
			Enum.Material.Fabric
		)
		-- Woven bands across it, and a diamond in the middle in the den's glow
		for k = -2, 2 do
			part(
				model,
				"Weave",
				Vector3.new(size.X - edge * 3, 0.165, 0.5),
				CFrame.new(0, 0.095, k * size.Z * 0.16),
				darker(item.color, 0.12),
				Enum.Material.Fabric
			)
		end
		local motif = size.Z * 0.3
		part(
			model,
			"Motif",
			Vector3.new(motif, 0.17, motif),
			CFrame.new(0, 0.1, 0) * CFrame.Angles(0, math.rad(45), 0),
			glow:Lerp(item.color, 0.35),
			Enum.Material.Fabric
		)
	elseif item.id == "SeaFan" then
		-- Three fans of different sizes spreading out over the rock from one root
		local rng = Random.new(seedOf(item.id))
		local fans = {
			{ x = -size.X * 0.24, h = size.Y * 0.72, tilt = 18, color = item.color },
			{ x = 0, h = size.Y, tilt = -2, color = Color3.fromRGB(255, 120, 130) },
			{ x = size.X * 0.26, h = size.Y * 0.8, tilt = -20, color = Color3.fromRGB(196, 120, 236) },
		}
		for i, f in fans do
			local foot = CFrame.new(f.x * 0.3, -size.Y / 2, -size.Z * 0.5 + i * 0.12)
				* CFrame.Angles(0, 0, math.rad(f.tilt))
			DenItems.piece(model, "Fan", foot, f.h, f.color, rng)
		end
		blob(
			model,
			"Holdfast",
			Vector3.new(2.2, 1.2, 1.2),
			CFrame.new(0, -size.Y / 2 + 0.3, -size.Z * 0.4),
			darker(item.color, 0.35)
		)
		main =
			part(model, "Body", Vector3.new(size.X, size.Y, 0.2), CFrame.new(0, 0, -size.Z / 2), item.color)
		main.Transparency = 1
	elseif item.rug then
		main = rug(model, item)
	elseif item.cluster then
		local base = CFrame.new()
		if surface == "wall" then
			-- out of the rock: its up points out of the wall
			base = CFrame.new(0, 0, -size.Y / 2)
				* CFrame.Angles(math.rad(-90), 0, 0)
				* CFrame.new(0, -size.Y / 2, 0)
		end
		main = cluster(model, item, base, glow)
	else
		main = mounted(model, item, surface, color)
	end
	-- Bigger things light more of the room
	local reach = math.clamp(14 + math.max(size.X, size.Y, size.Z), 18, 34)
	if item.glow then
		light(main, color, reach, 1.3)
	elseif item.lamp then
		light(main, item.lamp, reach, 1.2)
	end
	local flame = item.flame
	if flame and item.lamp then
		local bed = part(
			model,
			"Hearth",
			Vector3.new(size.X * flame.width * 0.7, 0.2, size.Z * flame.width * 0.7),
			CFrame.new(0, size.Y * flame.at, 0),
			item.lamp
		)
		bed.Transparency = 1
		-- A pale core in the lamp's own colour (a near-white core read yellow-white over
		-- the bowl, PC 2026-11-02 BF1)
		Fx.hearth(
			bed,
			size.X * flame.width,
			size.Y * flame.height,
			item.lamp:Lerp(Color3.new(1, 1, 1), 0.3),
			item.lamp:Lerp(Color3.new(0, 0.3, 0.32), 0.35)
		)
	end
	if item.id == "BubbleColumn" then
		column(model, item)
	elseif item.bubbles then
		-- A few bubbles off the top of a thing that steams (the Vent Cauldron)
		local vent = part(
			model,
			"Steam",
			Vector3.new(size.X * 0.5, 0.2, size.Z * 0.5),
			main.CFrame * CFrame.new(0, size.Y * 0.3, 0),
			item.color
		)
		vent.Transparency = 1
		local bubbles = Instance.new("ParticleEmitter")
		bubbles.Rate = 6
		bubbles.Lifetime = NumberRange.new(1.5, 2.5)
		bubbles.Speed = NumberRange.new(2, 3.5)
		bubbles.SpreadAngle = Vector2.new(10, 10)
		bubbles.Size = NumberSequence.new(0.3, 0.6)
		bubbles.Transparency = NumberSequence.new(0.3, 0.9)
		bubbles.LightEmission = 0.3
		bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 250, 255))
		bubbles.EmissionDirection = Enum.NormalId.Top
		bubbles.Shape = Enum.ParticleEmitterShape.Box
		bubbles.Parent = vent
	end
	-- An invisible root at the pivot (what Build mode hits to pick a thing up)
	local root = part(model, "Root", Vector3.one * 0.2, CFrame.new(), color)
	root.Transparency = 1
	model.PrimaryPart = root
	return model
end

-- The thing's box at the identity frame (Build mode's clearance and pick-up box)
function DenItems.box(item: DensConfig.Item, surface: string): (CFrame, Vector3)
	local size = item.size
	if surface == "wall" and table.find(item.kinds, "floor") then
		return CFrame.new(0, 0, -size.Y / 2) * CFrame.Angles(math.rad(-90), 0, 0), size
	elseif surface == "wall" then
		return CFrame.new(0, 0, -size.Z / 2), size
	elseif surface == "ceiling" then
		return CFrame.new(0, -size.Y / 2, 0), size
	end
	return CFrame.new(0, size.Y / 2, 0), size
end

-- Every surface a thing goes on, in the order Build mode tries them
function DenItems.surfaces(item: DensConfig.Item): { string }
	return item.kinds
end

return DenItems
