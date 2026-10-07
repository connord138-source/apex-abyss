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
local Config = require(script.Parent.Config)
local FishBuilder = require(script.Parent.FishBuilder)

type PartSpec = FishBuilder.PartSpec

type Cosmetic = {
	parts: { PartSpec },
	hides: { string }?, -- base parts it replaces
}

type VariantShape = {
	scale: { [string]: Vector3 }, -- per base part: size multiplier
	joints: { [string]: CFrame }?, -- per base part: a new joint position (unit)
	extra: { PartSpec },
	hides: { string }?,
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

local function spikes(): { PartSpec }
	local list: { PartSpec } = {}
	local count = 12
	for i = 1, count do
		local angle = (i / count) * 2 * math.pi
		local z = if i % 2 == 0 then -0.06 else 0.06
		local outward = Vector3.new(math.cos(angle), math.sin(angle), 0)
		local at = Vector3.new(outward.X * 0.15, outward.Y * 0.16, z)
		table.insert(list, {
			name = `Spike{i}`,
			parent = "Body1",
			size = Vector3.new(0.012, 0.012, 0.07),
			-- Point the spike's length outward from the body
			c0 = CFrame.lookAt(at, at + outward, Vector3.zAxis) * CFrame.new(0, 0, -0.025),
			c1 = CFrame.new(),
			shape = "Ellipsoid",
			color = "fin",
		})
	end
	return list
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
		extra = spikes(),
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
		extra = {
			{
				name = "Hammer",
				parent = "Head",
				size = Vector3.new(0.64, 0.06, 0.13),
				c0 = CFrame.new(0, 0.02, -0.1),
				c1 = CFrame.new(),
				shape = "Ellipsoid",
				color = "back",
			},
		},
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

-- Paints the body in a shade (or its base look when `shadeId` is nil), and adds
-- the shade's glow and glints. `length` sizes the effects.
local function paint(body: Model, look: FishBuilder.Look, shadeId: string?, length: number)
	local shade = if shadeId then Config.Shades.byId[shadeId] else nil
	for _, child in body:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end
		local role = child:GetAttribute("Role")
		if role == "eye" or role == "fixed" then
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
	local core = body:FindFirstChild("Body1")
	if shade == nil or core == nil or not core:IsA("BasePart") then
		return
	end
	if shade.glow then
		local light = Instance.new("PointLight")
		light.Name = "ShadeGlow"
		light.Color = shade.glow
		light.Range = math.clamp(length * 4, 8, 60)
		light.Brightness = 1.2
		light:SetAttribute("ShadeEffect", true)
		light.Parent = core
	end
	if shade.sparkle then
		local glints = Instance.new("ParticleEmitter")
		glints.Name = "ShadeSparkle"
		glints.Rate = 7
		glints.Lifetime = NumberRange.new(0.6, 1.2)
		glints.Speed = NumberRange.new(length * 0.2, length * 0.6)
		glints.SpreadAngle = Vector2.new(180, 180)
		glints.Drag = 2
		glints.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, length * 0.06),
			NumberSequenceKeypoint.new(1, 0),
		})
		glints.LightEmission = 1
		glints.Color = ColorSequence.new(shade.sparkle)
		glints:SetAttribute("ShadeEffect", true)
		glints.Parent = core
	end
end

-- Dresses a body. Call FishBuilder.applyScale(body, length) afterwards.
-- A rigged mesh body (FishBuilder.buildMesh) keeps its texture: a shade tints it
-- (SurfaceAppearance.Color and the part color multiply, so this only ever darkens
-- or colors; whitening looks need their own textures later) and gets the shade's
-- glow and glints. Rolled parts and variants don't fit a mesh yet.
local function paintMesh(body: Model, shadeId: string?, length: number)
	local mesh = body:FindFirstChild("Mesh")
	if mesh == nil then
		return
	end
	local shade = if shadeId then Config.Shades.byId[shadeId] else nil
	local tint = if shade then shade.back:Lerp(Color3.new(1, 1, 1), 0.35) else Color3.new(1, 1, 1)
	local core: BasePart? = nil
	for _, descendant in mesh:GetDescendants() do
		if descendant:IsA("SurfaceAppearance") then
			(descendant :: any).Color = tint
		elseif descendant:IsA("BasePart") then
			descendant.Color = tint
			descendant.Transparency = if shade then shade.transparency or 0 else 0
			core = core or descendant
		elseif descendant:GetAttribute("ShadeEffect") then
			descendant:Destroy()
		end
	end
	if shade == nil or core == nil then
		return
	end
	if shade.glow then
		local light = Instance.new("PointLight")
		light.Name = "ShadeGlow"
		light.Color = shade.glow
		light.Range = math.clamp(length * 4, 8, 60)
		light.Brightness = 1.2
		light:SetAttribute("ShadeEffect", true)
		light.Parent = core
	end
	if shade.sparkle then
		local glints = Instance.new("ParticleEmitter")
		glints.Name = "ShadeSparkle"
		glints.Rate = 7
		glints.Lifetime = NumberRange.new(0.6, 1.2)
		glints.Speed = NumberRange.new(length * 0.2, length * 0.6)
		glints.SpreadAngle = Vector2.new(180, 180)
		glints.Drag = 2
		glints.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, length * 0.06),
			NumberSequenceKeypoint.new(1, 0),
		})
		glints.LightEmission = 1
		glints.Color = ColorSequence.new(shade.sparkle)
		glints:SetAttribute("ShadeEffect", true)
		glints.Parent = core
	end
end

function Cosmetics.apply(body: Model, look: FishBuilder.Look, dress: Dress, length: number)
	if body:GetAttribute("Mesh") then
		paintMesh(body, dress.shade, length)
		return
	end
	strip(body)
	local variant = if dress.variant then VARIANTS[dress.variant] else nil
	if variant then
		addParts(body, variant.extra, look)
		hide(body, variant.hides)
	end
	for _, slot in Config.Exotics.SLOTS do
		local id = dress.parts[slot]
		local cosmetic = if id then PARTS[id] else nil
		if cosmetic then
			addParts(body, cosmetic.parts, look)
			hide(body, cosmetic.hides)
		end
	end
	-- Reshape last, so added parts move out with the bigger body they sit on
	if variant then
		reshape(body, variant)
	end
	paint(body, look, dress.shade, length)
end

-- Per-frame shade animation (Prismatic's rolling colors). `t` is any clock.
function Cosmetics.animate(body: Model, shadeId: string?, t: number)
	local shade = if shadeId then Config.Shades.byId[shadeId] else nil
	if shade == nil or not shade.cycle then
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
