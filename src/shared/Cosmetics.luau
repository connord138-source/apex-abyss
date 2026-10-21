--!strict
-- What shades, body parts and exotic variants look like on a fish, applied on
-- each client (the server only sets the character's Shade, Parts and Variant
-- attributes). The same code dresses the real fish and the preview fish in the
-- roll reveal and the menus.
--
-- `apply` rebuilds a body's cosmetics from scratch every time something changes:
-- it takes off the old ones (cosmetic parts, reshaping, hidden parts), then puts
-- on the variant, the parts and the shade, in that order. Afterwards the body
-- needs FishBuilder.applyScale at its current length.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local ShadesConfig = require(script.Parent.Config.Shades)
local FishBuilder = require(script.Parent.FishBuilder)
local SkinFx = require(script.Parent.SkinFx)

type PartSpec = FishBuilder.PartSpec

type Cosmetic = {
	parts: { PartSpec },
	hides: { string }?, -- base parts it replaces
}

-- The body's width and height as fractions of its length (a mesh body's box, or
-- the graybox plan's Body1), so pieces that ring the body fit every fish
type Dims = { w: number, h: number }

type VariantShape = {
	scale: { [string]: Vector3 }, -- per base part: size multiplier (graybox bodies)
	joints: { [string]: CFrame }?, -- per base part: a new joint position (unit)
	extra: { PartSpec } | (Dims) -> { PartSpec },
	hides: { string }?,
	meshScale: number?, -- a mesh body is drawn this much bigger (an inflated variant)
}

export type Dress = {
	shade: string?,
	parts: { [string]: string }, -- slot → part id
	variant: string?,
}

local IVORY = Color3.fromRGB(238, 230, 208)
local BONE = Color3.fromRGB(196, 186, 162)
local LURE = Color3.fromRGB(255, 236, 140)

local function teeth(): { PartSpec }
	local list: { PartSpec } = {}
	for i, z in { -0.15, -0.08, -0.01, 0.06 } do
		for side = -1, 1, 2 do
			table.insert(list, {
				name = `Tooth{i}{if side < 0 then "L" else "R"}`,
				parent = "SawBlade",
				size = Vector3.new(0.035, 0.012, 0.02),
				c0 = CFrame.new(side * 0.06, 0, z),
				c1 = CFrame.new(),
				shape = "Block",
				color = "fixed",
				fixed = IVORY,
			})
		end
	end
	return list
end

-- A spike pointing out of the body from `at` along `outward` (unit)
local function spike(
	name: string,
	parent: string,
	at: Vector3,
	outward: Vector3,
	length: number,
	thick: number,
	color: "fin" | "fixed",
	fixed: Color3?
): PartSpec
	return {
		name = name,
		parent = parent,
		size = Vector3.new(thick, thick, length),
		-- Point the spike's length outward from the body
		c0 = CFrame.lookAt(at, at + outward, Vector3.zAxis) * CFrame.new(0, 0, -length * 0.36),
		c1 = CFrame.new(),
		shape = "Ellipsoid",
		color = color,
		fixed = fixed,
	}
end

-- A ring of spikes round the body (the Puffball); the ring fits the body's box
local function spikes(dims: Dims): { PartSpec }
	local list: { PartSpec } = {}
	local count = 12
	for i = 1, count do
		local angle = (i / count) * 2 * math.pi
		local z = if i % 2 == 0 then -0.06 else 0.06
		local outward = Vector3.new(math.cos(angle), math.sin(angle), 0)
		local at = Vector3.new(outward.X * dims.w * 0.41, outward.Y * dims.h * 0.41, z)
		table.insert(list, spike(`Spike{i}`, "Body1", at, outward, 0.07, 0.012, "fin"))
	end
	return list
end

-- Long bone quills all over (the Porcupine Puffer): three rings and a crown
local function quills(dims: Dims): { PartSpec }
	local list: { PartSpec } = {}
	local n = 0
	for ring, z in { -0.1, 0.02, 0.14 } do
		local count = if ring == 2 then 12 else 10
		for i = 1, count do
			local angle = ((i + ring * 0.5) / count) * 2 * math.pi
			local outward = Vector3.new(math.cos(angle), math.sin(angle), (z + 0.02) * 1.2).Unit
			local at = Vector3.new(math.cos(angle) * dims.w * 0.42, math.sin(angle) * dims.h * 0.42, z)
			n += 1
			table.insert(list, spike(`Quill{n}`, "Body1", at, outward, 0.15, 0.014, "fixed", BONE))
		end
	end
	return list
end

-- Thin fin frills in a row along the back (a crest or a ridge)
local function crest(
	prefix: string,
	dims: Dims,
	count: number,
	zFrom: number,
	zTo: number,
	height: number,
	color: "fin" | "fixed",
	fixed: Color3?
): { PartSpec }
	local list: { PartSpec } = {}
	for i = 1, count do
		local k = (i - 0.5) / count
		local z = zFrom + (zTo - zFrom) * k
		local h = height * (0.7 + 0.3 * math.sin(k * math.pi))
		table.insert(list, {
			name = `{prefix}{i}`,
			parent = "Body1",
			size = Vector3.new(0.012, h, (zTo - zFrom) / count * 0.7),
			c0 = CFrame.new(0, dims.h * 0.46 + h * 0.4, z) * CFrame.Angles(math.rad(-18), 0, 0),
			c1 = CFrame.new(),
			shape = "Wedge",
			color = color,
			fixed = fixed,
			transparency = if color == "fin" then 0.15 else nil,
		})
	end
	return list
end

-- Fangs from the front of the jaw, angled down and forward
local function fangs(count: number, length: number, spread: number, y: number): { PartSpec }
	local list: { PartSpec } = {}
	for i = 1, count do
		local x = (i - (count + 1) / 2) * spread
		local at = Vector3.new(x, y, -0.13)
		local outward = Vector3.new(x * 0.4, -0.75, -0.5).Unit
		table.insert(list, spike(`Fang{i}`, "Head", at, outward, length, 0.016, "fixed", IVORY))
	end
	return list
end

-- A lure on a stalk from the head, tilted to `yaw` degrees sideways
local function lure(name: string, yaw: number, length: number, bulb: number): { PartSpec }
	return {
		{
			name = `{name}Stalk`,
			parent = "Head",
			size = Vector3.new(0.02, 0.02, length),
			c0 = CFrame.new(0, 0.12, -0.02)
				* CFrame.Angles(0, math.rad(yaw), 0)
				* CFrame.Angles(math.rad(55), 0, 0),
			c1 = CFrame.new(0, 0, length / 2),
			shape = "Ellipsoid",
			color = "fin",
		},
		{
			name = `{name}Bulb`,
			parent = `{name}Stalk`,
			size = Vector3.new(bulb, bulb, bulb),
			c0 = CFrame.new(0, 0, -length / 2),
			c1 = CFrame.new(),
			shape = "Ball",
			color = "fixed",
			fixed = LURE,
			material = Enum.Material.Neon,
			light = LURE,
		},
	}
end

local function joinSpecs(...: { PartSpec }): { PartSpec }
	local out: { PartSpec } = {}
	for _, list in { ... } do
		for _, spec in list do
			table.insert(out, spec)
		end
	end
	return out
end

local PARTS: { [string]: Cosmetic } = {
	AnglerLure = {
		parts = {
			{
				name = "LureStalk",
				parent = "Head",
				size = Vector3.new(0.02, 0.02, 0.34),
				c0 = CFrame.new(0, 0.12, -0.02) * CFrame.Angles(math.rad(55), 0, 0),
				c1 = CFrame.new(0, 0, 0.17),
				shape = "Ellipsoid",
				color = "fin",
			},
			{
				name = "LureBulb",
				parent = "LureStalk",
				size = Vector3.new(0.075, 0.075, 0.075),
				c0 = CFrame.new(0, 0, -0.17),
				c1 = CFrame.new(),
				shape = "Ball",
				color = "fixed",
				fixed = LURE,
				material = Enum.Material.Neon,
				light = LURE,
			},
		},
	},
	NarwhalHorn = {
		parts = {
			{
				name = "Horn",
				parent = "Head",
				size = Vector3.new(0.035, 0.035, 0.56),
				c0 = CFrame.new(0, 0.03, -0.13) * CFrame.Angles(math.rad(8), 0, 0),
				c1 = CFrame.new(0, 0, 0.28),
				shape = "Ellipsoid",
				color = "fixed",
				fixed = IVORY,
			},
		},
	},
	SawSnout = {
		parts = {
			{
				name = "SawBlade",
				parent = "Head",
				size = Vector3.new(0.1, 0.016, 0.38),
				c0 = CFrame.new(0, -0.02, -0.12),
				c1 = CFrame.new(0, 0, 0.19),
				shape = "Block",
				color = "fixed",
				fixed = BONE,
			},
			table.unpack(teeth()),
		},
	},
	SailFin = {
		parts = {
			{
				name = "Sail",
				parent = "Body1",
				size = Vector3.new(0.015, 0.36, 0.52),
				c0 = CFrame.new(0, 0.16, 0.08),
				c1 = CFrame.new(0, -0.16, 0),
				shape = "Ellipsoid",
				color = "fin",
				transparency = 0.12,
			},
		},
		hides = { "Dorsal" },
	},
	VeilTail = {
		parts = {
			{
				name = "VeilUp",
				parent = "Stalk",
				size = Vector3.new(0.012, 0.44, 0.26),
				c0 = CFrame.new(0, 0, 0.06) * CFrame.Angles(math.rad(50), 0, 0),
				c1 = CFrame.new(0, -0.2, 0),
				shape = "Ellipsoid",
				color = "fin",
				transparency = 0.35,
			},
			{
				name = "VeilDown",
				parent = "Stalk",
				size = Vector3.new(0.012, 0.4, 0.24),
				c0 = CFrame.new(0, 0, 0.06) * CFrame.Angles(math.rad(-50), 0, 0),
				c1 = CFrame.new(0, 0.18, 0),
				shape = "Ellipsoid",
				color = "fin",
				transparency = 0.35,
			},
		},
		hides = { "TailUp", "TailDown" },
	},
}

-- The rolled parts' Tripo models (owner, 2026-10-21: the approved PartsBoard's
-- legendary sheet; parts_glb, ReplicatedStorage.PartModels.<PartId>). Each hangs on
-- `parent` like the part-built pieces above, its longest side `length` of the fish's
-- length, its attach point (where it meets the fish) at `c0` there. `box` and
-- `attach` are the model's own proportions and that point, in units of its longest
-- side (tools/props/parts_prep.py's parts.json). Until it's imported the part-built
-- piece is drawn.
type PartFit = {
	parent: string,
	length: number,
	c0: CFrame,
	box: Vector3,
	attach: Vector3,
	light: Color3?,
}
local PART_MODELS: { [string]: PartFit } = {
	-- A segmented stalk from the top of the head to a crystal bulb dangling ahead of
	-- the mouth
	AnglerLure = {
		parent = "Head",
		length = 0.42,
		c0 = CFrame.new(0, 0.13, 0.02),
		box = Vector3.new(0.3424, 0.9738, 1),
		attach = Vector3.new(-0.0457, -0.0229, 0.5),
		light = Color3.fromRGB(120, 235, 255),
	},
	NarwhalHorn = {
		parent = "Head",
		length = 0.56,
		c0 = CFrame.new(0, 0.03, -0.13) * CFrame.Angles(math.rad(8), 0, 0),
		box = Vector3.new(0.3269, 0.3213, 1),
		attach = Vector3.new(0.0037, -0.0046, 0.5),
	},
	SawSnout = {
		parent = "Head",
		length = 0.42,
		c0 = CFrame.new(0, -0.02, -0.12),
		box = Vector3.new(0.358, 0.1295, 1),
		attach = Vector3.new(0.0045, -0.0005, 0.5),
	},
	-- Its foot a little into the back, the tall end forward
	SailFin = {
		parent = "Body1",
		length = 0.52,
		c0 = CFrame.new(0, 0.13, 0.08),
		box = Vector3.new(0.1204, 0.4918, 1),
		attach = Vector3.new(0, -0.2459, 0.0002),
	},
	-- Its stem round the tail stalk, the veil flowing out behind the fish's own tail
	VeilTail = {
		parent = "Stalk",
		length = 0.48,
		c0 = CFrame.new(0, 0, -0.02),
		box = Vector3.new(0.3083, 0.8497, 1),
		attach = Vector3.new(0.07, 0.0079, -0.5),
	},
}
-- (a static GLB faces +Z, the fish -Z: turned round about its own middle)
local MODEL_TURN = CFrame.Angles(0, math.pi, 0)

-- A rolled part's model as one piece to hang (nil until it's imported)
local function modelSpecs(id: string): { PartSpec }?
	local fit = PART_MODELS[id]
	local template = if fit then FishBuilder.partModel(id) else nil
	if fit == nil or template == nil then
		return nil
	end
	local turn = if template:GetAttribute("Facing") == "-Z" then CFrame.new() else MODEL_TURN
	local spec: PartSpec = {
		name = id,
		parent = fit.parent,
		size = fit.box * fit.length,
		c0 = fit.c0,
		c1 = turn * CFrame.new(fit.attach * fit.length),
		shape = "Block",
		color = "fixed",
		mesh = id,
		light = fit.light,
	}
	return { spec }
end

local VARIANTS: { [string]: VariantShape } = {
	Puffball = {
		scale = {
			Body1 = Vector3.new(1.7, 1.7, 1.3),
			Belly = Vector3.new(1.7, 1.6, 1.25),
			Head = Vector3.new(1.25, 1.25, 1.1),
			Body2 = Vector3.new(1.1, 1.15, 0.85),
			Body3 = Vector3.new(0.85, 0.9, 0.8),
			Dorsal = Vector3.new(1, 0.8, 1),
		},
		extra = function(dims: Dims)
			return spikes(if dims.w > 0.45 then dims else { w = dims.w * 1.7, h = dims.h * 1.7 })
		end,
		meshScale = 1.22,
	},
	-- One for every fish (owner, 2026-10-12): real pieces on the body, and on a mesh
	-- body a bigger draw where the fish is "puffed up"
	Sabrecuda = {
		scale = { Head = Vector3.new(1, 1, 1.12), Dorsal = Vector3.new(1, 1.4, 1.1) },
		extra = function(dims: Dims)
			return joinSpecs(fangs(2, 0.11, 0.05, -0.03), crest("Ridge", dims, 7, -0.12, 0.3, 0.07, "fin"))
		end,
		meshScale = 1.08,
	},
	Porcupine = {
		scale = { Body1 = Vector3.new(1.25, 1.25, 1.1), Belly = Vector3.new(1.25, 1.2, 1.1) },
		extra = function(dims: Dims)
			return quills(if dims.w > 0.45 then dims else { w = dims.w * 1.25, h = dims.h * 1.25 })
		end,
		meshScale = 1.2,
	},
	DragonMoray = {
		scale = { Head = Vector3.new(1.1, 1.1, 1) },
		extra = function(dims: Dims)
			local horns: { PartSpec } = {
				spike(
					"HornL",
					"Head",
					Vector3.new(-0.04, 0.06, -0.06),
					Vector3.new(-0.35, 0.8, -0.45).Unit,
					0.08,
					0.018,
					"fixed",
					IVORY
				),
				spike(
					"HornR",
					"Head",
					Vector3.new(0.04, 0.06, -0.06),
					Vector3.new(0.35, 0.8, -0.45).Unit,
					0.08,
					0.018,
					"fixed",
					IVORY
				),
			}
			return joinSpecs(horns, crest("Frill", dims, 11, -0.25, 0.42, 0.08, "fin"))
		end,
	},
	Deepfang = {
		scale = { Head = Vector3.new(1.08, 1.08, 1.08) },
		extra = function(_dims: Dims)
			return joinSpecs(
				lure("CrownL", -28, 0.3, 0.06),
				lure("CrownR", 28, 0.3, 0.06),
				lure("CrownTop", 0, 0.4, 0.085),
				fangs(4, 0.1, 0.05, -0.06)
			)
		end,
	},
	Hammerhead = {
		scale = {
			Head = Vector3.new(1, 0.85, 1),
			Dorsal = Vector3.new(1, 1.7, 1.15),
			TailUp = Vector3.new(1, 1.3, 1),
		},
		joints = {
			EyeL = CFrame.new(-0.3, 0.03, -0.1),
			EyeR = CFrame.new(0.3, 0.03, -0.1),
		},
		-- A widened head, not a plate on it (playtest 2026-10-12: "a flat paddle laid
		-- on the snout"): a bridge round the snout's middle and two thick lobes swept
		-- back to the eyes at their tips
		extra = {
			{
				name = "Hammer",
				parent = "Head",
				size = Vector3.new(0.2, 0.075, 0.13),
				c0 = CFrame.new(0, 0, -0.1),
				c1 = CFrame.new(),
				shape = "Ellipsoid",
				color = "back",
			} :: PartSpec,
			{
				name = "HammerL",
				parent = "Head",
				size = Vector3.new(0.34, 0.065, 0.1),
				c0 = CFrame.new(-0.15, 0, -0.088) * CFrame.Angles(0, math.rad(10), 0),
				c1 = CFrame.new(),
				shape = "Ellipsoid",
				color = "back",
			} :: PartSpec,
			{
				name = "HammerR",
				parent = "Head",
				size = Vector3.new(0.34, 0.065, 0.1),
				c0 = CFrame.new(0.15, 0, -0.088) * CFrame.Angles(0, math.rad(-10), 0),
				c1 = CFrame.new(),
				shape = "Ellipsoid",
				color = "back",
			} :: PartSpec,
			{
				name = "HammerEyeL",
				parent = "Head",
				size = Vector3.one * 0.04,
				c0 = CFrame.new(-0.305, 0.006, -0.062),
				c1 = CFrame.new(),
				shape = "Ball",
				color = "fixed",
				fixed = Color3.fromRGB(18, 20, 24),
			} :: PartSpec,
			{
				name = "HammerEyeR",
				parent = "Head",
				size = Vector3.one * 0.04,
				c0 = CFrame.new(0.305, 0.006, -0.062),
				c1 = CFrame.new(),
				shape = "Ball",
				color = "fixed",
				fixed = Color3.fromRGB(18, 20, 24),
			} :: PartSpec,
		} :: { PartSpec },
	},
}

local Cosmetics = {}

local function scaleOf(variant: VariantShape?, name: string): Vector3
	return if variant and variant.scale[name] then variant.scale[name] else Vector3.one
end

local function mulPosition(cframe: CFrame, by: Vector3): CFrame
	return CFrame.new(cframe.Position * by) * cframe.Rotation
end

-- Takes every cosmetic off: removes added parts, restores shapes and visibility.
local function strip(body: Model)
	for _, child in body:GetChildren() do
		if child:GetAttribute("Cosmetic") then
			child:Destroy()
		end
	end
	for _, child in body:GetChildren() do
		if child:IsA("BasePart") then
			child.LocalTransparencyModifier = 0
			local u0 = child:GetAttribute("U0")
			if typeof(u0) == "Vector3" then
				child:SetAttribute("U", u0)
			end
			local joint = child:FindFirstChildOfClass("Motor6D")
			if joint then
				joint:SetAttribute("C0", joint:GetAttribute("C00"))
				joint:SetAttribute("C1", joint:GetAttribute("C10"))
			end
			for _, effect in child:GetChildren() do
				if effect:GetAttribute("ShadeEffect") then
					effect:Destroy()
				end
			end
		end
	end
end

local function hide(body: Model, names: { string }?)
	if names == nil then
		return
	end
	for _, name in names do
		local part = body:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.LocalTransparencyModifier = 1
		end
	end
end

local function addParts(body: Model, specs: { PartSpec }, look: FishBuilder.Look)
	for _, spec in specs do
		local parent = body:FindFirstChild(spec.parent)
		if parent and parent:IsA("BasePart") then
			local part = FishBuilder.makePart(body, parent, spec, look, 1)
			part:SetAttribute("Cosmetic", true)
		end
	end
end

-- A variant's extra pieces, fitted to a body's width and height
local function extrasOf(variant: VariantShape, dims: Dims): { PartSpec }
	local extra = variant.extra
	if typeof(extra) == "function" then
		return extra(dims)
	end
	return extra :: { PartSpec }
end

-- A graybox body's dims: its Body1's unit size
local function grayboxDims(body: Model): Dims
	local body1 = body:FindFirstChild("Body1")
	local unit = if body1 then body1:GetAttribute("U0") else nil
	if typeof(unit) == "Vector3" then
		return { w = unit.X, h = unit.Y }
	end
	return { w = 0.37, h = 0.39 }
end

local function reshape(body: Model, variant: VariantShape)
	for _, child in body:GetChildren() do
		if child:IsA("BasePart") then
			local u0 = child:GetAttribute("U0")
			if typeof(u0) == "Vector3" then
				child:SetAttribute("U", u0 * scaleOf(variant, child.Name))
			end
			local joint = child:FindFirstChildOfClass("Motor6D")
			local c0 = joint and joint:GetAttribute("C00")
			local c1 = joint and joint:GetAttribute("C10")
			if joint and typeof(c0) == "CFrame" and typeof(c1) == "CFrame" then
				local override = variant.joints and variant.joints[child.Name]
				local parentName = if joint.Part0 then joint.Part0.Name else ""
				-- A bigger parent pushes its children's joints out with it
				joint:SetAttribute("C0", override or mulPosition(c0, scaleOf(variant, parentName)))
				joint:SetAttribute("C1", mulPosition(c1, scaleOf(variant, child.Name)))
			end
		end
	end
end

-- Rolled parts and exotic variants on a mesh body (owner, 2026-10-12: "parts need
-- to be actual physical parts that change the appearance of the fish as well.
-- Right now they do nothing. Variants should also be different/upgrades from the
-- original base fish as well. For all playable models"). A mesh body has no
-- Head/Body1/Stalk parts to hang pieces from, so those names are anchors: frames in
-- the fish's own unit box (nose at z -0.5, tail at +0.5), tuned per body plan
-- (ANCHORS), each tied to a bone (Head, Spine1, Tail). A piece is a part jointed
-- to the mesh's primary part by a Motor6D whose C0 is rewritten every frame from
-- its bone's animated pose (Cosmetics.follow, from FishAnimator), so a veil tail
-- swings with the tail and a horn turns with the head. Pieces live under the Mesh
-- model, so ScaleTo grows them with the fish; a variant's `meshScale` draws the
-- whole fish bigger (FishBuilder.applyScale).
type Rigged = {
	part: BasePart,
	joint: Motor6D,
	bone: Bone?,
	offset: CFrame, -- the part from its bone's rest frame (or the primary), at unit length
}
local meshRigs: { [Model]: { Rigged } } = {}

-- Per body plan: where the head sits (its length as a fraction of the body's,
-- from the nose), its height, the back's height over the middle, the tail stalk,
-- and `partScale`: rolled parts are made for the round graybox body (Body1 0.39 of
-- the length tall), so on a slender fish they're drawn smaller, as much as its
-- body is thinner. The heights were measured from the rigged FBX (the body's top
-- at Body1, the snout's middle) and set so a sail stands a third deep in the back:
-- on the Moray Eel a graybox-sized sail touched the back only at its lowest point
-- and read as floating a body height above it (playtest 2026-10-12), and the
-- Hammerhead's paddle lay on top of the snout (the head anchor sat 0.07 of the
-- length over the shark's snout)
type AnchorTune = {
	head: number?,
	headY: number?,
	bodyY: number?,
	stalkZ: number?,
	partScale: number?,
}
local ANCHORS: { [string]: AnchorTune } = {
	Nibbler = {},
	Cuda = { head = 0.3, headY = -0.039, bodyY = -0.023, partScale = 0.65 },
	Puffer = { head = 0.38 },
	Eel = { head = 0.16, headY = -0.037, bodyY = -0.043, stalkZ = 0.42, partScale = 0.55 },
	Shark = { head = 0.3, headY = -0.05, bodyY = -0.032, partScale = 0.8 },
	Angler = { head = 0.46, headY = 0.03, bodyY = -0.026 },
}

-- The anchors of a mesh body, in its unit box, the box's dims and the plan's part
-- scale
local function meshAnchors(body: Model): ({ [string]: CFrame }, Dims, number)
	local plan = body:GetAttribute("Plan")
	local tune: AnchorTune = ANCHORS[if typeof(plan) == "string" then plan else ""] or ({} :: AnchorTune)
	local w = body:GetAttribute("UnitW")
	local h = body:GetAttribute("UnitH")
	local dims: Dims = {
		w = if typeof(w) == "number" then w else 0.4,
		h = if typeof(h) == "number" then h else 0.45,
	}
	local head = tune.head or 0.3
	local headY = tune.headY or math.clamp((dims.h * 0.4 - 0.15) * 0.5, -0.08, 0.08)
	local bodyY = tune.bodyY or math.clamp(dims.h / 2 - 0.195, -0.1, 0.12)
	return {
		Head = CFrame.new(0, headY, -0.5 + head * 0.5),
		Body1 = CFrame.new(0, bodyY, -0.05),
		Body2 = CFrame.new(0, bodyY * 0.8, 0.15),
		Body3 = CFrame.new(0, bodyY * 0.6, 0.28),
		Stalk = CFrame.new(0, 0, tune.stalkZ or 0.38),
	},
		dims,
		tune.partScale or 1
end

-- A rolled part's pieces drawn `k` times their size (sizes and the offsets inside
-- the part; where it hangs on the body stays)
local function scaledSpecs(specs: { PartSpec }, k: number): { PartSpec }
	if k == 1 then
		return specs
	end
	local out: { PartSpec } = {}
	for _, spec in specs do
		local copy = table.clone(spec)
		copy.size = spec.size * k
		copy.c0 = CFrame.new(spec.c0.Position * k) * spec.c0.Rotation
		copy.c1 = CFrame.new(spec.c1.Position * k) * spec.c1.Rotation
		table.insert(out, copy)
	end
	return out
end

local function meshBones(mesh: Model): { [string]: Bone }
	local bones: { [string]: Bone } = {}
	for _, descendant in mesh:GetDescendants() do
		if descendant:IsA("Bone") then
			bones[descendant.Name] = descendant
		end
	end
	return bones
end

local function lastSpine(bones: { [string]: Bone }): Bone?
	local last: Bone? = nil
	local i = 1
	while bones[`Spine{i}`] do
		last = bones[`Spine{i}`]
		i += 1
	end
	return last
end

-- The bone an anchor rides
local function boneFor(bones: { [string]: Bone }, anchor: string): Bone?
	if anchor == "Head" then
		return bones.Head or bones.Root
	elseif anchor == "Stalk" then
		return bones.Tail or lastSpine(bones) or bones.Root
	elseif anchor == "Body2" then
		return bones.Spine2 or bones.Spine1 or bones.Root
	elseif anchor == "Body3" then
		return bones.Spine3 or lastSpine(bones) or bones.Root
	end
	return bones.Spine1 or bones.Root
end

-- A bone's frame in its part's space: at rest, or as animated right now
local function boneLocal(bone: Bone, animated: boolean): CFrame
	local chain = if animated then bone.TransformedCFrame else bone.CFrame
	local parent = bone.Parent
	while parent and parent:IsA("Bone") do
		chain = (if animated then parent.TransformedCFrame else parent.CFrame) * chain
		parent = parent.Parent
	end
	return chain
end

local function primaryOf(mesh: Model): (BasePart?, Motor6D?)
	local primary = mesh.PrimaryPart or mesh:FindFirstChildWhichIsA("MeshPart", true)
	local joint = if primary then primary:FindFirstChild("Mesh") else nil
	return primary, if joint and joint:IsA("Motor6D") then joint else nil
end

local function stripMesh(body: Model, mesh: Model)
	for _, child in mesh:GetChildren() do
		if child:GetAttribute("Cosmetic") then
			child:Destroy()
		end
	end
	meshRigs[body] = nil
	body:SetAttribute("MeshScale", 1)
end

-- Hangs pieces on a mesh body (see above). `drawn` is the length the mesh is at.
local function addMeshParts(
	body: Model,
	mesh: Model,
	specs: { PartSpec },
	look: FishBuilder.Look,
	anchors: { [string]: CFrame },
	bones: { [string]: Bone }
)
	local primary, meshJoint = primaryOf(mesh)
	local drawn = body:GetAttribute("Applied")
	if primary == nil or meshJoint == nil or typeof(drawn) ~= "number" or drawn <= 0 then
		return
	end
	local rig = meshRigs[body] or {}
	meshRigs[body] = rig
	-- Root space → primary space at unit length (the Mesh joint: primary = root * C1⁻¹)
	local c1 = meshJoint.C1
	local toPrimary = CFrame.new(c1.Position / drawn) * c1.Rotation
	local built: { [string]: { frame: CFrame, bone: Bone? } } = {}
	for _, spec in specs do
		local parentFrame: CFrame? = nil
		local bone: Bone? = nil
		local made = built[spec.parent]
		if made then
			parentFrame, bone = made.frame, made.bone
		elseif anchors[spec.parent] then
			parentFrame = anchors[spec.parent]
			bone = boneFor(bones, spec.parent)
			if string.sub(spec.parent, 1, 4) == "Body" and parentFrame then
				-- A piece on the back rides the spine bone under it, so it sways with
				-- that stretch of the body (Spine1 sits near the head on a long fish)
				local at = (toPrimary * parentFrame).Position
				local best = math.huge
				for _, candidate in bones do
					local rest = boneLocal(candidate, false).Position / drawn
					local distance = (rest - at).Magnitude
					if distance < best then
						best = distance
						bone = candidate
					end
				end
			end
		end
		if parentFrame == nil then
			continue
		end
		local restRoot = parentFrame * spec.c0 * spec.c1:Inverse() -- unit, root space
		built[spec.name] = { frame = restRoot, bone = bone }
		local restPrimary = toPrimary * restRoot
		local offset = restPrimary
		if bone then
			local boneRest = boneLocal(bone, false)
			local boneUnit = CFrame.new(boneRest.Position / drawn) * boneRest.Rotation
			offset = boneUnit:ToObjectSpace(restPrimary)
		end
		local part = FishBuilder.makePart(mesh, primary, spec, look, drawn)
		part:SetAttribute("Cosmetic", true)
		local joint = part:FindFirstChildOfClass("Motor6D")
		if joint == nil then
			continue
		end
		joint.C1 = CFrame.new()
		local entry: Rigged = { part = part, joint = joint, bone = bone, offset = offset }
		table.insert(rig, entry)
		-- At rest now, so a preview (no animator) shows it in place
		local base = if bone then boneLocal(bone, false) else CFrame.new()
		joint.C0 = base * CFrame.new(offset.Position * drawn) * offset.Rotation
	end
end

-- Every frame, after the animator has posed the bones: the pieces ride them
function Cosmetics.follow(body: Model)
	local rig = meshRigs[body]
	if rig == nil then
		return
	end
	local drawn = body:GetAttribute("Applied")
	if typeof(drawn) ~= "number" then
		return
	end
	for _, entry in rig do
		local base = if entry.bone then boneLocal(entry.bone, true) else CFrame.new()
		entry.joint.C0 = base * CFrame.new(entry.offset.Position * drawn) * entry.offset.Rotation
	end
end

-- The spectral treatment (the Ghost shade; owner, 2026-10-08: "the whole fish needs
-- a similar to ghost from sea of thieves glow"): the body goes see-through and
-- shimmering, a Highlight fills it with pale light and rims it, wisps drift off it,
-- and Cosmetics.animate breathes it. `holder` is where the Highlight lives (the body,
-- or a mesh body's Mesh model so the mesh cleanup finds it).
local function haunt(holder: Instance, shade: ShadesConfig.Shade)
	local old = holder:FindFirstChild("ShadeHaunt")
	if old then
		old:Destroy()
	end
	-- Spectral green, never see-through (owner, 2026-10-17: "The ghost skin doesnt need
	-- to literally be invisible, it should be spectral green with some mist coming off
	-- of it"): a green fill over the fish's own look, a bright rim, and the mist and
	-- wisps of its `fx`
	local halo = Instance.new("Highlight")
	halo.Name = "ShadeHaunt"
	halo.FillColor = shade.glow or shade.back
	halo.FillTransparency = 0.5
	halo.OutlineColor = shade.belly
	halo.OutlineTransparency = 0.1
	halo.DepthMode = Enum.HighlightDepthMode.Occluded
	halo:SetAttribute("ShadeEffect", true)
	halo.Parent = holder
end

-- Living shades: each dressed body's worn skins and glow light, so animate drives
-- the glow without searching the body every frame
type Live = {
	skins: { SurfaceAppearance },
	light: PointLight?,
	phase: number,
	sheens: { Texture }, -- the moving layer's six faces per part (Config/Shades `sheen`)
	fx: SkinFx.Live?, -- the skin's effects (Config/Shades `fx`)
	-- A window skin's layer (Cosmetics.windows): its sheen, the core part's frame last
	-- frame, how fast the fish is turning (smoothed), and each layer's smoothed offset
	window: ShadesConfig.Sheen?,
	core: BasePart?,
	lastFrame: CFrame?,
	turn: number,
	offsets: { [Texture]: Vector2 },
}

-- The faces a moving layer is projected from (a MeshPart takes a Texture as a
-- projection from each face, as Hatch & Snatch's galaxy finish found)
local SHEEN_FACES = {
	Enum.NormalId.Left,
	Enum.NormalId.Right,
	Enum.NormalId.Top,
	Enum.NormalId.Bottom,
	Enum.NormalId.Front,
	Enum.NormalId.Back,
}

-- A window's pattern holds still on screen (Config/Shades `window`): each face's
-- texture slides against the part's movement relative to the camera. The texture's
-- right and down on each face in the part's own axes, as Hatch & Snatch measured them
-- for its Galaxy finish (CreatureAnimator SKY_AXES; the top face's entry negated
-- there to match); the bottom mirrors the top.
local WINDOW_AXES: { [Enum.NormalId]: { Vector3 } } = {
	[Enum.NormalId.Front] = { Vector3.new(-1, 0, 0), Vector3.new(0, -1, 0) },
	[Enum.NormalId.Back] = { Vector3.new(1, 0, 0), Vector3.new(0, -1, 0) },
	[Enum.NormalId.Right] = { Vector3.new(0, 0, -1), Vector3.new(0, -1, 0) },
	[Enum.NormalId.Left] = { Vector3.new(0, 0, 1), Vector3.new(0, -1, 0) },
	[Enum.NormalId.Top] = { Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1) },
	[Enum.NormalId.Bottom] = { Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1) },
}

-- The two faces of `part` its flanks look out of (`right` the fish's right): a window
-- skin is laid only on those (PC 2026-10-20: "a bit glitchy once moving": where the
-- six projections met, along the back, belly, head and tail, the seams slid against
-- each other as the fish turned and banked)
local function sideFaces(part: BasePart, right: Vector3): { Enum.NormalId }
	local own = part.CFrame:VectorToObjectSpace(right)
	local best, worst = Enum.NormalId.Right, Enum.NormalId.Left
	local most, least = -math.huge, math.huge
	for _, face in SHEEN_FACES do
		local dot = Vector3.FromNormalId(face):Dot(own)
		if dot > most then
			best, most = face, dot
		end
		if dot < least then
			worst, least = face, dot
		end
	end
	return { best, worst }
end

-- The face of `part` the fish's head points out of (`forward` in the part's own frame)
local function headFace(part: BasePart, forward: Vector3): Enum.NormalId
	local own = part.CFrame:VectorToObjectSpace(forward)
	local best, bestDot = Enum.NormalId.Front, -math.huge
	for _, face in SHEEN_FACES do
		local dot = Vector3.FromNormalId(face):Dot(own)
		if dot > bestDot then
			best, bestDot = face, dot
		end
	end
	return best
end

-- The layer that moves across a shade's skin: six Textures per part, slid every
-- frame by Cosmetics.animate. Nothing while its image isn't uploaded (id 0). A
-- Texture can't be masked, so a toothed fish leaves out the face its head points
-- out of (`skip`): seen from the front, Nebula turned the Reef Shark's small teeth
-- violet (PC follow-up 2026-10-14), and teeth are always bone white.
local function sheenLayers(
	part: BasePart,
	shade: ShadesConfig.Shade,
	length: number,
	skip: Enum.NormalId?,
	only: { Enum.NormalId }?
): { Texture }
	local sheen = shade.sheen
	local id = if sheen then (Config.Textures :: { [string]: number })[sheen.texture] else nil
	if sheen == nil or typeof(id) ~= "number" or id == 0 then
		return {}
	end
	local layers: { Texture } = {}
	local faces: { Enum.NormalId } = if only then only else SHEEN_FACES :: any
	for _, face in faces do
		if face == skip then
			continue
		end
		local texture = Instance.new("Texture")
		texture.Name = "Sheen"
		texture.Face = face
		texture.Texture = `rbxassetid://{id}`
		texture.Transparency = sheen.transparency
		texture.Color3 = sheen.color or Color3.new(1, 1, 1)
		texture.StudsPerTileU = sheen.tile * length
		texture.StudsPerTileV = sheen.tile * length
		texture:SetAttribute("ShadeEffect", true)
		texture.Parent = part
		table.insert(layers, texture)
	end
	return layers
end
local live: { [Model]: Live } = setmetatable({}, { __mode = "k" }) :: any

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function keys(points: { number }): NumberSequence
	local list = {}
	for i = 1, #points, 2 do
		table.insert(list, NumberSequenceKeypoint.new(points[i], points[i + 1]))
	end
	return NumberSequence.new(list)
end

-- The shade's light on the fish (its base brightness is kept for the pulse)
local function glowLight(core: BasePart, shade: ShadesConfig.Shade, length: number): PointLight?
	if not shade.glow then
		return nil
	end
	local light = Instance.new("PointLight")
	light.Name = "ShadeGlow"
	light.Color = shade.glow
	light.Range = math.clamp(length * 4, 8, 60)
	light.Brightness = if shade.spectral
		then 2.2
		elseif shade.emissive then 1.2 + shade.emissive * 0.3
		else 1.2
	light:SetAttribute("Base", light.Brightness)
	light:SetAttribute("ShadeEffect", true)
	light.Parent = core
	return light
end

-- What drifts off a fish in the shade, scaled by its length (Config/Shades `aura`;
-- glints by default when the shade has a sparkle color)
local function aura(core: BasePart, shade: ShadesConfig.Shade, length: number)
	-- (a skin with an effect set sheds only its effects: SkinFx; PC 2026-10-18 found
	-- 13 of them shedding these glints on top)
	if shade.fx then
		return
	end
	local kind = shade.aura or (if shade.sparkle then "glints" else nil)
	if kind == nil then
		return
	end
	local color = shade.sparkle or shade.glow or shade.fin
	local e = Instance.new("ParticleEmitter")
	e.Name = "ShadeAura"
	e.Texture = SPARKLE
	e.LightEmission = 1
	e.SpreadAngle = Vector2.new(180, 180)
	e.Color = ColorSequence.new(color)
	if kind == "embers" then
		-- Sparks rising off a fire, yellow cooling to red
		e.Rate = 10
		e.Lifetime = NumberRange.new(0.8, 1.6)
		e.Speed = NumberRange.new(length * 0.05, length * 0.2)
		e.Acceleration = Vector3.new(0, length * 0.5, 0)
		e.Drag = 1
		e.Size = keys({ 0, length * 0.035, 1, 0 })
		e.Color = ColorSequence.new(Color3.fromRGB(255, 226, 120), Color3.fromRGB(255, 70, 20))
	elseif kind == "frost" then
		-- Rime flakes shed and sinking, turning as they go
		e.Rate = 6
		e.Lifetime = NumberRange.new(1.2, 2.2)
		e.Speed = NumberRange.new(length * 0.02, length * 0.08)
		e.Acceleration = Vector3.new(0, -length * 0.12, 0)
		e.RotSpeed = NumberRange.new(-90, 90)
		e.LightEmission = 0.4
		e.Size = keys({ 0, length * 0.035, 0.8, length * 0.03, 1, 0 })
	elseif kind == "sparks" then
		-- Quick electric spits
		e.Rate = 5
		e.Lifetime = NumberRange.new(0.15, 0.35)
		e.Speed = NumberRange.new(length * 0.8, length * 1.6)
		e.Drag = 6
		e.Size = keys({ 0, length * 0.03, 1, 0 })
		e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	elseif kind == "stars" then
		-- Pinpricks that twinkle twice and fade (rainbow for a cycling shade)
		e.Rate = 5
		e.Lifetime = NumberRange.new(1.5, 2.5)
		e.Speed = NumberRange.new(length * 0.02, length * 0.08)
		e.Drag = 1
		e.Size = keys({ 0, 0, 0.2, length * 0.05, 0.4, length * 0.015, 0.6, length * 0.05, 1, 0 })
		if shade.cycle then
			e.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 0.6, 1)),
				ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33, 0.6, 1)),
				ColorSequenceKeypoint.new(0.66, Color3.fromHSV(0.66, 0.6, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromHSV(0.9, 0.6, 1)),
			})
		end
	elseif kind == "motes" then
		-- Soft lights drifting up slowly
		e.Rate = 6
		e.Lifetime = NumberRange.new(2, 3)
		e.Speed = NumberRange.new(length * 0.03, length * 0.1)
		e.Acceleration = Vector3.new(0, length * 0.05, 0)
		e.Drag = 0.5
		e.Size = keys({ 0, 0, 0.3, length * 0.04, 1, 0 })
		e.Transparency = keys({ 0, 1, 0.3, 0.2, 1, 1 })
	elseif kind == "bubbles" then
		-- A trail of small bubbles rising
		e.Rate = 3
		e.Lifetime = NumberRange.new(1.5, 2.5)
		e.Speed = NumberRange.new(length * 0.02, length * 0.08)
		e.Acceleration = Vector3.new(0, length * 0.4, 0)
		e.Drag = 2
		e.LightEmission = 0.5
		e.LightInfluence = 0.7
		e.Size = keys({ 0, length * 0.015, 0.3, length * 0.035, 1, length * 0.04 })
		e.Transparency = keys({ 0, 0.35, 0.7, 0.5, 1, 1 })
	elseif kind == "ink" then
		-- Dark ink curling off the body, tinged with the shade's glow
		e.Texture = SMOKE
		e.LightEmission = 0
		e.LightInfluence = 0.3
		e.Rate = 4
		e.Lifetime = NumberRange.new(1.6, 2.6)
		e.Speed = NumberRange.new(length * 0.03, length * 0.1)
		e.Drag = 1
		e.RotSpeed = NumberRange.new(-30, 30)
		e.Size = keys({ 0, length * 0.06, 1, length * 0.22 })
		e.Transparency = keys({ 0, 1, 0.15, 0.55, 1, 1 })
		e.Color = ColorSequence.new(shade.back:Lerp(shade.glow or shade.fin, 0.3))
	else
		-- Glints: bright points flicking off it
		e.Rate = 7
		e.Lifetime = NumberRange.new(0.6, 1.2)
		e.Speed = NumberRange.new(length * 0.2, length * 0.6)
		e.Drag = 2
		e.Size = keys({ 0, 0, 0.3, length * 0.06, 1, 0 })
	end
	e:SetAttribute("ShadeEffect", true)
	e.Parent = core
end

-- How bright a shade's glow is at time `t`, 1 being its set level (Config/Shades
-- `pulse`)
function Cosmetics.pulse(kind: ShadesConfig.Pulse?, t: number): number
	if kind == "breathe" then
		return 0.7 + 0.3 * math.sin(t * 1.6)
	elseif kind == "heartbeat" then
		local p = t % 1.3
		return 0.55 + 0.75 * math.exp(-((p - 0.1) / 0.07) ^ 2) + 0.45 * math.exp(-((p - 0.34) / 0.08) ^ 2)
	elseif kind == "flicker" then
		return 0.85 + 0.5 * math.noise(t * 7, 0.5)
	elseif kind == "wave" then
		return 0.7 + 0.3 * math.sin(t * 2.6)
	elseif kind == "twinkle" then
		return 0.55 + 0.45 * (0.5 + 0.5 * math.sin(t * 5.3)) * (0.5 + 0.5 * math.sin(t * 1.9 + 1))
	elseif kind == "strobe" then
		-- A low glow, with lightning flashes now and then
		return if math.noise(t * 1.8, 3.1) > 0.3 then 2.2 else 0.5
	elseif kind == "scan" then
		return 0.55 + 1.1 * math.max(0, math.sin(t * 1.8)) ^ 10
	end
	return 1
end

-- Paints the body in a shade (or its base look when `shadeId` is nil), and adds
-- the shade's glow and glints. `length` sizes the effects.
local function paint(body: Model, look: FishBuilder.Look, shadeId: string?, length: number)
	local shade = if shadeId then Config.Shades.byId[shadeId] else nil
	for _, child in body:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end
		local role = child:GetAttribute("Role")
		local isEye = role == "eye"
		if isEye or role == "fixed" then
			if shade and shade.spectral and isEye then
				child.Color = shade.belly
				child.Material = Enum.Material.Neon
			elseif isEye and child.Material == Enum.Material.Neon then
				child.Material = Enum.Material.SmoothPlastic
			end
			continue
		end
		if shade then
			local color = if role == "belly"
				then shade.belly
				elseif role == "fin" then shade.fin
				else shade.back
			if shade.accent and (child.Name == "Body2" or child.Name == "Stalk") then
				color = shade.accent
			end
			child.Color = color
			child.Material = shade.material or Enum.Material.SmoothPlastic
			child.Reflectance = shade.reflectance or 0.04
		else
			child.Color = if role == "belly" then look.belly elseif role == "fin" then look.fin else look.back
			child.Material = Enum.Material.SmoothPlastic
			child.Reflectance = 0.04
		end
		-- See-through parts (a veil tail) stay at least as clear as they were made
		local base = child:GetAttribute("T0")
		child.Transparency = math.max(
			if typeof(base) == "number" then base else 0,
			if shade then shade.transparency or 0 else 0
		)
	end
	local oldHaunt = body:FindFirstChild("ShadeHaunt")
	if oldHaunt then
		oldHaunt:Destroy()
	end
	live[body] = nil
	local core = body:FindFirstChild("Body1")
	if shade == nil or core == nil or not core:IsA("BasePart") then
		return
	end
	if shade.spectral then
		haunt(body, shade)
	end
	live[body] = {
		skins = {},
		light = glowLight(core, shade, length),
		phase = math.random() * 20,
		sheens = {},
		fx = SkinFx.build(body, body, core, shade, length),
		turn = 0,
		offsets = {},
	}
	aura(core, shade, length)
end

-- Dresses a body. Call FishBuilder.applyScale(body, length) afterwards.
-- A rigged mesh body (FishBuilder.buildMesh) wears its shade's skin (below), or
-- without one a tint (SurfaceAppearance.Color and the part color multiply, so a
-- tint only ever darkens), and gets the shade's glow and glints. Rolled parts and
-- variants hang off its bones (addMeshParts).
-- A fish's skin for a shade: ReplicatedStorage.ShadeSkins.<Fish>.<Shade>, a
-- SurfaceAppearance (or a StringValue holding a texture id), made by tools/shades and
-- filed by tools/studio/organize_shades.luau. Nil until it's imported. A toothed fish
-- (tools/shades/teeth.json) also has a "Natural" skin: its own texture with bone-white
-- teeth (owner, 2026-10-14: "All fish should always have bone white teeth"), worn when
-- it has no shade.
local function skinFor(plan: string?, shadeId: string): Instance?
	local root = ReplicatedStorage:FindFirstChild("ShadeSkins")
	local folder = if root and plan then root:FindFirstChild(plan) else nil
	local skin = if folder then folder:FindFirstChild(shadeId) else nil
	if skin and (skin:IsA("SurfaceAppearance") or skin:IsA("StringValue")) then
		return skin
	end
	return nil
end

-- Puts the part's own texture aside (a SurfaceAppearance only works parented
-- straight to its part), or back
local function holdOwn(part: BasePart, hold: boolean)
	local held = part:FindFirstChild("HeldAppearance")
	if hold then
		local own: Instance? = nil
		for _, child in part:GetChildren() do
			if child:IsA("SurfaceAppearance") and child.Name ~= "ShadeSkin" then
				own = child
			end
		end
		if own then
			if held == nil then
				local made = Instance.new("Folder")
				made.Name = "HeldAppearance"
				made.Parent = part
				held = made
			end
			own.Parent = held
		end
	elseif held then
		local own = held:FindFirstChildOfClass("SurfaceAppearance")
		if own then
			own.Parent = part
		end
	end
end

-- The skin a mesh body wears for a shade (its Natural skin with none), or nil
function Cosmetics.skinOf(body: Model, shadeId: string?): Instance?
	local shade = if shadeId then Config.Shades.byId[shadeId] else nil
	if shade and shade.spectral == true then
		return nil
	end
	local plan = body:GetAttribute("MeshPlan")
	local planName = if typeof(plan) == "string" then plan else nil
	return (if shade then skinFor(planName, shade.id) else nil) or skinFor(planName, "Natural")
end

-- `skinReady` (the client's SkinLoader): a skin whose textures haven't all arrived
-- isn't worn yet, so the fish shows the stand-in, never untextured white
local function paintMesh(body: Model, shadeId: string?, length: number, skinReady: ((Instance) -> boolean)?)
	local mesh = body:FindFirstChild("Mesh")
	if mesh == nil then
		return
	end
	local shade = if shadeId then Config.Shades.byId[shadeId] else nil
	local spectral = shade ~= nil and shade.spectral == true
	local plan = body:GetAttribute("MeshPlan")
	local planName = if typeof(plan) == "string" then plan else nil
	local skin = if shade and not spectral then skinFor(planName, shade.id) else nil
	-- A skin still loading: for those few seconds the fish is the shade's own colour,
	-- flat (PC 2026-10-19, SK4b: the tinted texture can only darken, so an orange
	-- Nibbler under Lilac read maroon)
	local waiting = false
	if skin and skinReady and not skinReady(skin) then
		skin = nil
		waiting = true
	end
	-- No shade (or a shade not imported yet): the fish's own look, white teeth and all
	local natural = if skin == nil and not waiting then skinFor(planName, "Natural") else nil
	if natural and skinReady and not skinReady(natural) then
		natural = nil
	end
	-- A fish with teeth (it has a Natural skin) keeps the moving sheen off its mouth
	local toothed = skinFor(planName, "Natural") ~= nil
	local forward = body:GetPivot().LookVector
	-- Without its skin imported yet, a shade tints the texture (multiplies, so it can
	-- only darken; the skin is the real look)
	-- (closer to the shade's own colour: at 0.35 toward white the stand-in looked like
	-- the plain fish, PC 2026-10-18)
	local tint = if shade and skin == nil
		then shade.back:Lerp(Color3.new(1, 1, 1), 0.12)
		else Color3.new(1, 1, 1)
	local core: BasePart? = nil
	local worn: { SurfaceAppearance } = {}
	local sheens: { Texture } = {}
	live[body] = nil
	for _, descendant in mesh:GetDescendants() do
		if descendant:GetAttribute("ShadeEffect") or descendant.Name == "ShadeSkin" then
			descendant:Destroy()
		end
	end
	for _, descendant in mesh:GetDescendants() do
		if not descendant:IsA("MeshPart") then
			continue
		end
		local part = descendant :: MeshPart
		core = core or part
		local ownTexture = part:GetAttribute("OwnTexture")
		if shade then
			local sides = if shade.sheen and shade.sheen.window
				then sideFaces(part, body:GetPivot().RightVector)
				else nil
			for _, layer in
				sheenLayers(part, shade, length, if toothed then headFace(part, forward) else nil, sides)
			do
				table.insert(sheens, layer)
			end
		end
		if spectral then
			-- The fish's own look under the haunt's green (its Natural skin when it has one)
			local own = natural
			if own and own:IsA("SurfaceAppearance") then
				holdOwn(part, true)
				local clone = own:Clone()
				clone.Name = "ShadeSkin"
				clone.Color = (shade :: ShadesConfig.Shade).back
				clone.Parent = part
			else
				holdOwn(part, false)
				if typeof(ownTexture) == "string" then
					part.TextureID = ownTexture
				end
				local appearance = part:FindFirstChildOfClass("SurfaceAppearance")
				if appearance then
					(appearance :: any).Color = (shade :: ShadesConfig.Shade).back
				end
			end
			part.Color = (shade :: ShadesConfig.Shade).back
			part.Material = Enum.Material.Plastic
			part.Transparency = 0
		elseif skin then
			holdOwn(part, true)
			if skin:IsA("SurfaceAppearance") then
				local clone = skin:Clone()
				clone.Name = "ShadeSkin"
				-- The glow map's strength (the Angler's lure glows in every skin)
				clone.EmissiveStrength = (shade :: ShadesConfig.Shade).emissive or 1
				clone.Parent = part
				table.insert(worn, clone)
			elseif skin:IsA("StringValue") then
				if ownTexture == nil then
					part:SetAttribute("OwnTexture", part.TextureID)
				end
				part.TextureID = skin.Value
			end
			part.Color = Color3.new(1, 1, 1)
			part.Material = Enum.Material.Plastic
			part.Transparency = (shade :: ShadesConfig.Shade).transparency or 0
		elseif waiting then
			holdOwn(part, true)
			if part.TextureID ~= "" then
				if ownTexture == nil then
					part:SetAttribute("OwnTexture", part.TextureID)
				end
				part.TextureID = ""
			end
			part.Color = (shade :: ShadesConfig.Shade).back
			part.Material = Enum.Material.Plastic
			part.Transparency = (shade :: ShadesConfig.Shade).transparency or 0
		elseif natural and natural:IsA("SurfaceAppearance") then
			holdOwn(part, true)
			local clone = natural:Clone()
			clone.Name = "ShadeSkin"
			clone.Color = tint
			clone.EmissiveStrength = 1
			clone.Parent = part
			part.Color = Color3.new(1, 1, 1)
			part.Material = Enum.Material.Plastic
			part.Transparency = if shade then shade.transparency or 0 else 0
		else
			holdOwn(part, false)
			if typeof(ownTexture) == "string" then
				part.TextureID = ownTexture
			end
			part.Material = Enum.Material.Plastic
			part.Color = tint
			part.Transparency = if shade then shade.transparency or 0 else 0
			local own = part:FindFirstChildOfClass("SurfaceAppearance")
			if own then
				(own :: any).Color = tint
			end
		end
	end
	if shade == nil or core == nil then
		return
	end
	if spectral then
		haunt(mesh, shade)
	end
	live[body] = {
		skins = worn,
		light = glowLight(core, shade, length),
		phase = math.random() * 20,
		sheens = sheens,
		fx = SkinFx.build(body, mesh, core, shade, length),
		window = if shade.sheen and shade.sheen.window and #sheens > 0 then shade.sheen else nil,
		core = core,
		turn = 0,
		offsets = {},
	}
	aura(core, shade, length)
end

-- An exotic variant with its own model (variants_fbx, VariantModels.<VariantId>) is
-- drawn as that mesh instead of its species' (owner, 2026-10-21: "a whole new model,
-- not pieces stuck on"), and the species' comes back when it's taken off. The new
-- mesh is built like any (FishBuilder.buildMesh, its MeshPlan the variant's id, so
-- the species' skins don't go on it: a shade tints its own texture). Returns the mesh
-- now on the body.
local function swapMesh(body: Model, mesh: Model, variant: string?, length: number): Model
	local want = if variant then FishBuilder.variantTemplate(variant) else nil
	if want == nil then
		local current = body:GetAttribute("MeshPlan")
		if typeof(current) ~= "string" or Config.Exotics.variantsById[current] == nil then
			return mesh
		end
		local plan = body:GetAttribute("Plan")
		want = FishBuilder.meshTemplate(if typeof(plan) == "string" then plan else nil)
	end
	if want == nil or body:GetAttribute("MeshPlan") == want.Name then
		return mesh
	end
	local _, joint = primaryOf(mesh)
	local root = if joint then joint.Part0 else nil
	if root == nil then
		return mesh
	end
	stripMesh(body, mesh)
	mesh:Destroy()
	FishBuilder.buildMesh(body, root, want, length)
	local built = body:FindFirstChild("Mesh")
	return if built and built:IsA("Model") then built else mesh
end

-- Dresses a body (see above). Returns true when a variant's own model replaced the
-- mesh (or the species' came back), so an animator must find the bones again.
function Cosmetics.apply(
	body: Model,
	look: FishBuilder.Look,
	dress: Dress,
	length: number,
	skinReady: ((Instance) -> boolean)?
): boolean
	local found = body:FindFirstChild("Mesh")
	if body:GetAttribute("Mesh") and found and found:IsA("Model") then
		local mesh = swapMesh(body, found, dress.variant, length)
		local rebuilt = mesh ~= found
		stripMesh(body, mesh)
		paintMesh(body, dress.shade, length, skinReady)
		local anchors, dims, partScale = meshAnchors(body)
		local bones = meshBones(mesh)
		local variant = if dress.variant then VARIANTS[dress.variant] else nil
		if variant then
			-- (a variant drawn as its own model has its horns and fangs already)
			if body:GetAttribute("MeshPlan") ~= dress.variant then
				addMeshParts(body, mesh, extrasOf(variant, dims), look, anchors, bones)
			end
			body:SetAttribute("MeshScale", variant.meshScale or 1)
		end
		for _, slot in Config.Exotics.SLOTS do
			local id = dress.parts[slot]
			local cosmetic = if id then PARTS[id] else nil
			if cosmetic and id then
				local specs = modelSpecs(id) or cosmetic.parts
				addMeshParts(body, mesh, scaledSpecs(specs, partScale), look, anchors, bones)
			end
		end
		return rebuilt
	end
	strip(body)
	local variant = if dress.variant then VARIANTS[dress.variant] else nil
	if variant then
		addParts(body, extrasOf(variant, grayboxDims(body)), look)
		hide(body, variant.hides)
	end
	for _, slot in Config.Exotics.SLOTS do
		local id = dress.parts[slot]
		local cosmetic = if id then PARTS[id] else nil
		if cosmetic and id then
			addParts(body, modelSpecs(id) or cosmetic.parts, look)
			hide(body, cosmetic.hides)
		end
	end
	-- Reshape last, so added parts move out with the bigger body they sit on
	if variant then
		reshape(body, variant)
	end
	paint(body, look, dress.shade, length)
	return false
end

-- Window skins in the world, every frame once the camera has moved (FishAnimator binds
-- this after the camera's render step; run with the fish's animation, before the
-- camera, the pattern was a frame behind and shimmered as the fish swam, PC
-- 2026-10-20: "a bit glitchy once moving"). Each flank's pattern holds still on
-- screen, its offset eased over a few hundredths of a second so the camera's spring
-- doesn't jitter it, and drifts slowly; it fades while the fish turns or banks hard
-- (the flank swings faster than a still pattern can follow) and comes back as it
-- straightens out.
local WINDOW_EASE = 0.05 -- seconds: the offsets' smoothing
local TURN_SMOOTH = 0.12 -- seconds: the turn rate's smoothing
local TURN_FROM, TURN_FULL = 0.9, 2.6 -- rad/s: the layer starts to fade, and is faded most
local TURN_FADE = 0.85 -- the most it fades

function Cosmetics.windows(t: number, dt: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local eye = camera.CFrame.Position
	local ease = 1 - math.exp(-dt / WINDOW_EASE)
	for body, state in live do
		local sheen, core = state.window, state.core
		-- (a preview's fish is animated by Cosmetics.animate, against its own view)
		if sheen == nil or core == nil or #state.sheens == 0 or not body:IsDescendantOf(workspace) then
			continue
		end
		-- How fast it's turning: its core part's look and up, frame to frame
		local frame = core.CFrame
		local last = state.lastFrame
		state.lastFrame = frame
		if last and dt > 0 then
			local swing = math.acos(math.clamp(last.LookVector:Dot(frame.LookVector), -1, 1))
			local roll = math.acos(math.clamp(last.UpVector:Dot(frame.UpVector), -1, 1))
			state.turn += (math.max(swing, roll) / dt - state.turn) * (1 - math.exp(-dt / TURN_SMOOTH))
		end
		local fade = math.clamp((state.turn - TURN_FROM) / (TURN_FULL - TURN_FROM), 0, 1) * TURN_FADE
		fade = math.floor(fade * 50 + 0.5) / 50
		local transparency = sheen.transparency + (1 - sheen.transparency) * fade
		local drawn = body:GetAttribute("Applied")
		local studs = sheen.tile * (if typeof(drawn) == "number" then drawn else 2)
		local drift = (t + state.phase) * (sheen.drift or 0) * studs
		for _, layer in state.sheens do
			if layer.StudsPerTileU ~= studs then
				layer.StudsPerTileU = studs
				layer.StudsPerTileV = studs
			end
			if layer.Transparency ~= transparency then
				layer.Transparency = transparency
			end
			local part = layer.Parent
			local axes = WINDOW_AXES[layer.Face]
			if part and part:IsA("BasePart") and axes then
				local relative = part.CFrame:VectorToObjectSpace(part.Position - eye)
				local goal = Vector2.new(relative:Dot(axes[1]) + drift, relative:Dot(axes[2]) + drift * 0.6)
				local was = state.offsets[layer]
				-- (a jump, from a teleport or a new tile size, isn't eased)
				local now = if was and (goal - was).Magnitude < studs then was:Lerp(goal, ease) else goal
				state.offsets[layer] = now
				layer.OffsetStudsU = now.X
				layer.OffsetStudsV = now.Y
			end
		end
	end
end

-- Per-frame shade animation: the glow's pulse, Prismatic's rolling colors, the
-- Ghost's breathing haunt. `t` is any clock.
function Cosmetics.animate(body: Model, shadeId: string?, t: number)
	local shade = if shadeId then Config.Shades.byId[shadeId] else nil
	if shade == nil then
		return
	end
	local state = live[body]
	if state and state.fx then
		SkinFx.step(state.fx, body, t + state.phase)
	end
	local sheen = shade.sheen
	if state and sheen and sheen.window and body:IsDescendantOf(workspace) then
		-- (a fish in the world: Cosmetics.windows, after the camera has moved)
		state.window = if #state.sheens > 0 then sheen else nil
	elseif state and sheen and sheen.window and #state.sheens > 0 then
		-- A window in a preview: the pattern holds still against the world's camera
		-- while the fish turns, and drifts slowly so it moves on a still fish too
		local drawn = body:GetAttribute("Applied")
		local studs = sheen.tile * (if typeof(drawn) == "number" then drawn else 2)
		local camera = workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		local drift = (t + state.phase) * (sheen.drift or 0) * studs
		for _, layer in state.sheens do
			if layer.StudsPerTileU ~= studs then
				layer.StudsPerTileU = studs
				layer.StudsPerTileV = studs
			end
			local part = layer.Parent
			local axes = WINDOW_AXES[layer.Face]
			if part and part:IsA("BasePart") and axes then
				local relative = part.CFrame:VectorToObjectSpace(part.Position - eye)
				layer.OffsetStudsU = relative:Dot(axes[1]) + drift
				layer.OffsetStudsV = relative:Dot(axes[2]) + drift * 0.6
			end
		end
	elseif state and sheen and #state.sheens > 0 then
		-- The moving layer: slides along the body (U on the side faces) and drifts
		-- across it, one tile every 1/speed seconds, sized to the fish as it grows
		local drawn = body:GetAttribute("Applied")
		local studs = sheen.tile * (if typeof(drawn) == "number" then drawn else 2)
		local along = ((t + state.phase) * sheen.speed % 1) * studs
		local across = ((t + state.phase) * (sheen.drift or 0) % 1) * studs
		for _, layer in state.sheens do
			if layer.StudsPerTileU ~= studs then
				layer.StudsPerTileU = studs
				layer.StudsPerTileV = studs
			end
			local face = layer.Face
			if face == Enum.NormalId.Front or face == Enum.NormalId.Back then
				layer.OffsetStudsU = across
				layer.OffsetStudsV = along
			elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
				layer.OffsetStudsU = along
				layer.OffsetStudsV = across
			else
				layer.OffsetStudsU = across
				layer.OffsetStudsV = along
			end
		end
	end
	if state and (shade.pulse or shade.cycle) then
		-- The glow map and the light move together; a cycling shade's glow rolls
		-- through the rainbow too
		local k = Cosmetics.pulse(shade.pulse, t + state.phase)
		local strength = (shade.emissive or 1) * k
		local tint = if shade.cycle then Color3.fromHSV((t * 0.12) % 1, 0.55, 1) else nil
		for _, skin in state.skins do
			skin.EmissiveStrength = strength
			if tint then
				skin.EmissiveTint = tint
			end
		end
		local light = state.light
		if light then
			local base = light:GetAttribute("Base")
			light.Brightness = (if typeof(base) == "number" then base else 1.2) * k
			if tint then
				light.Color = tint
			end
		end
	end
	if shade.spectral then
		-- The haunt breathes: its green swells and fades slowly
		local pulse = 0.5 + 0.5 * math.sin(t * 1.7)
		local halo = body:FindFirstChild("ShadeHaunt", true)
		if halo and halo:IsA("Highlight") then
			halo.FillTransparency = 0.36 + 0.22 * pulse
			halo.OutlineTransparency = 0.02 + 0.2 * pulse
		end
		return
	end
	if not shade.cycle then
		return
	end
	-- Glossy plastic at 0.65 saturation: Neon melts a fish into a blob (a lesson
	-- from Hatch & Snatch)
	local hue = (t * 0.12) % 1
	for _, child in body:GetChildren() do
		if child:IsA("BasePart") then
			local role = child:GetAttribute("Role")
			if role == "back" then
				child.Color = Color3.fromHSV(hue, 0.65, 1)
			elseif role == "belly" then
				child.Color = Color3.fromHSV(hue, 0.22, 1)
			elseif role == "fin" then
				child.Color = Color3.fromHSV((hue + 0.33) % 1, 0.65, 1)
			end
		end
	end
end

-- A character's dress, from the attributes the server sets.
function Cosmetics.dressOf(character: Instance): Dress
	local shade = character:GetAttribute("Shade")
	local variant = character:GetAttribute("Variant")
	local parts: { [string]: string } = {}
	local list = character:GetAttribute("Parts")
	if typeof(list) == "string" then
		for slot, id in list:gmatch("(%w+)=(%w+)") do
			if slot and id then
				parts[slot] = id
			end
		end
	end
	return {
		shade = if typeof(shade) == "string" and shade ~= "" then shade else nil,
		parts = parts,
		variant = if typeof(variant) == "string" and variant ~= "" then variant else nil,
	}
end

-- The attribute text for equipped parts ("Head=AnglerLure,Back=SailFin").
function Cosmetics.partsText(parts: { [string]: string }): string
	local entries: { string } = {}
	for _, slot in Config.Exotics.SLOTS do
		if parts[slot] then
			table.insert(entries, `{slot}={parts[slot]}`)
		end
	end
	return table.concat(entries, ",")
end

return Cosmetics
