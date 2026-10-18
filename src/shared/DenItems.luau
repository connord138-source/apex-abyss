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
local Props = require(script.Parent.Props)

local DenItems = {}

local SMOOTH = Enum.Material.SmoothPlastic
local STONE = Color3.fromRGB(150, 138, 118)
local STONE_LIGHT = Color3.fromRGB(176, 164, 140)
local WOOD = Color3.fromRGB(122, 96, 68)
local WOOD_DARK = Color3.fromRGB(82, 62, 44)
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
	branch(foot, height * 0.38, height * 0.14, 2)
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
			Vector3.new(height * 1.05, height * 0.08, height * 0.12),
			foot
				* CFrame.new(0, height * 0.9 + k * 0.01, (k - 2) * height * 0.22)
				* CFrame.Angles(0, (k - 2) * 0.35, 0),
			darker(color, 0.3)
		)
	end
end

local function sponge(parent: Instance, foot: CFrame, height: number, color: Color3)
	local radius = height * 0.14
	upright(parent, "Tube", foot, height, radius, color)
	-- a flared lip and the dark mouth
	upright(
		parent,
		"Lip",
		foot * CFrame.new(0, height - 0.05, 0),
		height * 0.06,
		radius * 1.18,
		paler(color, 0.15)
	)
	upright(
		parent,
		"Mouth",
		foot * CFrame.new(0, height + 0.01, 0),
		0.05,
		radius * 0.72,
		Color3.fromRGB(30, 18, 40)
	)
end

local function fan(parent: Instance, foot: CFrame, height: number, color: Color3)
	-- The fan faces along the foot's look; ribs fan out from the stem
	upright(parent, "Stem", foot, height * 0.22, height * 0.04, darker(color, 0.25))
	local disc = part(
		parent,
		"Fan",
		Vector3.new(0.16, height, height),
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
			Vector3.new(height * 0.24, l * 1.1, height * 0.05),
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
		local f = math.clamp((0.62 + 0.38 * rng:NextNumber()) * (1 - 0.3 * r) * (0.85 + 0.15 * back), 0.45, 1)
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
-- it to face the box's look, and the box is fitted turned with it.
local function dressed(model: Model, item: DensConfig.Item, box: CFrame, color: Color3): Part
	local stand = part(model, "Body", item.size, box, color, if item.glow then Enum.Material.Neon else SMOOTH)
	if item.prop then
		local fit, size = box, item.size
		if item.front then
			fit = box * CFrame.Angles(0, -math.rad(item.front), 0)
			size = Vector3.new(size.Z, size.Y, size.X)
		end
		local prop = Props.dress(stand, item.prop, { cframe = fit, size = size })
		if prop and item.glow then
			Props.tint(prop, color)
		end
	end
	return stand
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

-- The thing `item` in the den's glow color, at the identity frame (move it with
-- PivotTo). `surface` picks how a thing that goes in more than one place is
-- mounted (the Crystal Cluster juts out of a wall).
function DenItems.build(item: DensConfig.Item, glow: Color3, surface: string): Model
	local model = Instance.new("Model")
	model.Name = item.id
	local color = if item.glow and item.id ~= "CoralLamp" then glow else item.color
	local size = item.size
	local main: BasePart
	if item.id == "Banner" then
		local k = size.X / 4
		part(
			model,
			"Pole",
			Vector3.new(size.X + 0.8 * k, 0.35 * k, 0.35 * k),
			CFrame.new(0, size.Y / 2, -0.35 * k),
			WOOD
		)
		for side = -1, 1, 2 do
			shaped(
				part(
					model,
					"PoleEnd",
					Vector3.one * 0.6 * k,
					CFrame.new(side * (size.X / 2 + 0.4 * k), size.Y / 2, -0.35 * k),
					Color3.fromRGB(214, 160, 70)
				),
				Enum.PartType.Ball
			)
		end
		main = part(
			model,
			"Cloth",
			Vector3.new(size.X, size.Y, 0.2),
			CFrame.new(0, 0, -0.4 * k),
			glow,
			Enum.Material.Fabric
		)
		-- A swallowtail foot: two wedges cut up into the hem
		part(
			model,
			"Hem",
			Vector3.new(size.X, 0.3 * k, 0.26),
			CFrame.new(0, -size.Y / 2, -0.4 * k),
			paler(glow, 0.3),
			Enum.Material.Neon
		)
		for side = -1, 1, 2 do
			part(
				model,
				"Stripe",
				Vector3.new(0.3 * k, size.Y * 0.92, 0.24),
				CFrame.new(side * (size.X / 2 - 0.5 * k), 0, -0.42 * k),
				paler(glow, 0.45)
			)
		end
		-- A crest stitched on: a ring and a fish's tail fin
		shaped(
			part(
				model,
				"Crest",
				Vector3.new(0.08, 2.2 * k, 2.2 * k),
				CFrame.new(0, size.Y * 0.12, -0.4 * k - 0.13) * CFrame.Angles(0, math.rad(90), 0),
				paler(glow, 0.55)
			),
			Enum.PartType.Cylinder
		)
		blob(
			model,
			"CrestFish",
			Vector3.new(1.5 * k, 0.7 * k, 0.1),
			CFrame.new(0, size.Y * 0.12, -0.4 * k - 0.2),
			darker(glow, 0.35)
		)
	elseif item.id == "SeaGlassLantern" then
		local k = size.Y / 3
		part(
			model,
			"Plate",
			Vector3.new(1.0 * k, 1.3 * k, 0.2),
			CFrame.new(0, 1.3 * k, -0.1),
			IRON,
			Enum.Material.Metal
		)
		part(
			model,
			"Bracket",
			Vector3.new(0.3 * k, 0.3 * k, 1.6 * k),
			CFrame.new(0, 1.3 * k, -0.8 * k),
			IRON,
			Enum.Material.Metal
		)
		part(
			model,
			"Hook",
			Vector3.new(0.2 * k, 0.7 * k, 0.2 * k),
			CFrame.new(0, 1.0 * k, -1.5 * k),
			IRON,
			Enum.Material.Metal
		)
		local glass = part(
			model,
			"Glass",
			Vector3.new(1.3 * k, 1.8 * k, 1.3 * k),
			CFrame.new(0, -0.1 * k, -1.5 * k),
			color,
			Enum.Material.Glass
		)
		glass.Transparency = 0.25
		part(
			model,
			"Cap",
			Vector3.new(1.6 * k, 0.3 * k, 1.6 * k),
			CFrame.new(0, 0.85 * k, -1.5 * k),
			IRON,
			Enum.Material.Metal
		)
		part(
			model,
			"Foot",
			Vector3.new(1.5 * k, 0.25 * k, 1.5 * k),
			CFrame.new(0, -1.1 * k, -1.5 * k),
			IRON,
			Enum.Material.Metal
		)
		main = shaped(
			part(
				model,
				"Flame",
				Vector3.one * 0.7 * k,
				CFrame.new(0, -0.1 * k, -1.5 * k),
				color,
				Enum.Material.Neon
			),
			Enum.PartType.Ball
		)
	elseif item.id == "JellyLamp" then
		local k = size.Y / 5
		part(
			model,
			"Cord",
			Vector3.new(0.12, 1.4 * k, 0.12),
			CFrame.new(0, -0.7 * k, 0),
			IRON,
			Enum.Material.Metal
		)
		local bell = blob(model, "Bell", Vector3.new(3 * k, 2 * k, 3 * k), CFrame.new(0, -2.2 * k, 0), color)
		bell.Material = Enum.Material.Glass
		bell.Transparency = 0.3
		blob(
			model,
			"Rim",
			Vector3.new(3.1 * k, 0.4 * k, 3.1 * k),
			CFrame.new(0, -2.9 * k, 0),
			paler(color, 0.3)
		).Material =
			Enum.Material.Neon
		main = shaped(
			part(
				model,
				"Core",
				Vector3.new(1.4, 0.9, 1.4) * k,
				CFrame.new(0, -2.3 * k, 0),
				color,
				Enum.Material.Neon
			),
			Enum.PartType.Ball
		)
		for i = 1, 10 do
			local angle = i / 10 * 2 * math.pi
			local length = (1.6 + (i % 3) * 0.6) * k
			local tentacle = part(
				model,
				"Tentacle",
				Vector3.new(0.12 * k, length, 0.12 * k),
				CFrame.new(math.cos(angle) * 1.1 * k, -3.1 * k - length / 2, math.sin(angle) * 1.1 * k)
					* CFrame.Angles(math.sin(angle) * 0.15, 0, math.cos(angle) * 0.15),
				paler(color, 0.35),
				Enum.Material.Neon
			)
			tentacle.Transparency = 0.35
		end
		-- four frilled oral arms down the middle
		for i = 1, 4 do
			local angle = i / 4 * 2 * math.pi + 0.4
			blob(
				model,
				"Arm",
				Vector3.new(0.5 * k, 1.8 * k, 0.16 * k),
				CFrame.new(math.cos(angle) * 0.35 * k, -3.6 * k, math.sin(angle) * 0.35 * k)
					* CFrame.Angles(0, -angle, 0),
				paler(color, 0.15)
			).Transparency =
				0.2
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
	elseif item.id == "DriftwoodTable" then
		-- Two stacked rounded stones under a long weathered slab, grain along its top
		for _, x in { -1, 1 } do
			local at = x * size.X * 0.3
			blob(model, "Stone", Vector3.new(3.4, 3.0, 3.2), CFrame.new(at, 1.4, 0), STONE)
			blob(model, "Stone", Vector3.new(2.6, 2.4, 2.4), CFrame.new(at, 3.9, 0.1), STONE_LIGHT)
		end
		local top = size.Y - 0.6
		main = part(
			model,
			"Top",
			Vector3.new(size.X, 1.1, size.Z * 0.82),
			CFrame.new(0, top, 0) * CFrame.Angles(0, 0, math.rad(1.5)),
			WOOD
		)
		blob(model, "End", Vector3.new(2.2, 1.1, size.Z * 0.82), CFrame.new(-size.X / 2, top, 0), WOOD)
		blob(model, "End", Vector3.new(2.2, 1.1, size.Z * 0.82), CFrame.new(size.X / 2, top, 0), WOOD)
		part(
			model,
			"Bark",
			Vector3.new(size.X * 0.96, 0.5, size.Z * 0.86),
			CFrame.new(0, top - 0.55, 0),
			WOOD_DARK
		)
		for k = -1, 1 do
			part(
				model,
				"Grain",
				Vector3.new(size.X * (0.7 + 0.1 * (k % 2)), 0.08, 0.16),
				CFrame.new(k * 0.6, top + 0.56, k * size.Z * 0.22),
				WOOD_DARK
			)
		end
		-- a shell and a starfish left on it
		local rng = Random.new(seedOf(item.id))
		DenItems.piece(
			model,
			"Shell",
			CFrame.new(size.X * 0.28, top + 0.5, 1.2),
			1.4,
			Color3.fromRGB(236, 196, 160),
			rng
		)
		DenItems.piece(
			model,
			"Star",
			CFrame.new(-size.X * 0.22, top + 0.52, -1),
			1.8,
			Color3.fromRGB(255, 140, 90),
			rng
		)
	elseif item.id == "PearlPedestal" then
		local k = size.Y / 10
		part(
			model,
			"Plinth",
			Vector3.new(4.8, 0.8, 4.8) * Vector3.new(k, k, k),
			CFrame.new(0, 0.4 * k, 0),
			STONE
		)
		part(model, "Step", Vector3.new(3.8, 0.6, 3.8) * k, CFrame.new(0, 1.1 * k, 0), STONE_LIGHT)
		upright(model, "Column", CFrame.new(0, 1.4 * k, 0), 5 * k, 1.1 * k, STONE_LIGHT)
		for i = 1, 8 do
			local a = i / 8 * 2 * math.pi
			upright(
				model,
				"Flute",
				CFrame.new(math.cos(a) * 1.1 * k, 1.4 * k, math.sin(a) * 1.1 * k),
				5 * k,
				0.16 * k,
				STONE
			)
		end
		part(model, "Capital", Vector3.new(3.4, 0.6, 3.4) * k, CFrame.new(0, 6.7 * k, 0), STONE)
		-- An open clam holding the pearl
		local clam = Color3.fromRGB(196, 186, 220)
		blob(model, "Clam", Vector3.new(4.4, 1.2, 3.6) * k, CFrame.new(0, 7.3 * k, 0), clam)
		blob(
			model,
			"Lid",
			Vector3.new(4.4, 0.9, 3.6) * k,
			CFrame.new(0, 8.4 * k, 1.5 * k) * CFrame.Angles(math.rad(62), 0, 0),
			paler(clam, 0.12)
		)
		main = shaped(
			part(model, "Pearl", Vector3.one * 2.3 * k, CFrame.new(0, 8.3 * k, -0.1 * k), PEARL),
			Enum.PartType.Ball
		)
		main.Reflectance = 0.35
		shaped(
			part(
				model,
				"Shine",
				Vector3.one * 1.2 * k,
				CFrame.new(0, 8.3 * k, -0.1 * k),
				paler(glow, 0.5),
				Enum.Material.Neon
			),
			Enum.PartType.Ball
		).Transparency =
			0.55
	elseif item.id == "BubbleColumn" then
		-- A vent cone in a ring of stones; bubbles rise all the way up
		local around = 8
		for i = 1, around do
			local a = i / around * 2 * math.pi
			blob(
				model,
				"Stone",
				Vector3.new(1.6, 1.1, 1.3),
				CFrame.new(math.cos(a) * size.X * 0.38, 0.4, math.sin(a) * size.Z * 0.38)
					* CFrame.Angles(0, -a, 0),
				STONE:Lerp(STONE_LIGHT, (i % 3) / 3)
			)
		end
		local vent = Color3.fromRGB(70, 80, 90)
		upright(model, "Cone", CFrame.new(), 0.8, 1.3, darker(vent, 0.1))
		upright(model, "Cone", CFrame.new(0, 0.8, 0), 0.7, 0.9, vent)
		main = upright(
			model,
			"Vent",
			CFrame.new(0, 1.5, 0),
			0.3,
			0.5,
			Color3.fromRGB(150, 230, 255),
			Enum.Material.Neon
		)
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
		bubbles.EmissionDirection = Enum.NormalId.Right -- the cylinder's axis is up
		bubbles.Parent = main
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
	elseif surface == "wall" and table.find(item.kinds, "floor") then
		-- A floor thing on a wall juts out of the rock: its up turned to point out
		main = dressed(model, item, CFrame.new(0, 0, -size.Y / 2) * CFrame.Angles(math.rad(-90), 0, 0), color)
	elseif surface == "wall" then
		-- A wall thing hangs flat on the rock, standing out by its depth
		main = dressed(model, item, CFrame.new(0, 0, -size.Z / 2), color)
	elseif surface == "ceiling" then
		main = dressed(model, item, CFrame.new(0, -size.Y / 2, 0), color)
	else
		main = dressed(model, item, CFrame.new(0, size.Y / 2, 0), color)
	end
	-- Bigger things light more of the room
	local reach = math.clamp(14 + math.max(size.X, size.Y, size.Z), 18, 34)
	if item.glow then
		light(main, if item.id == "CoralLamp" then glow else color, reach, 1.3)
	elseif item.lamp then
		light(main, item.lamp, reach, 1.2)
	end
	-- A few bubbles off the top of a thing that steams (the Vent Cauldron)
	if item.bubbles and item.id ~= "BubbleColumn" then
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
