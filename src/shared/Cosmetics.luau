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

-- The spectral treatment (the Ghost shade; owner, 2026-10-08: "the whole fish needs
-- a similar to ghost from sea of thieves glow"): the body goes see-through and
-- shimmering, a Highlight fills it with pale light and rims it, wisps drift off it,
-- and Cosmetics.animate breathes it. `holder` is where the Highlight lives (the body,
-- or a mesh body's Mesh model so the mesh cleanup finds it).
local function haunt(holder: Instance, core: BasePart, shade: ShadesConfig.Shade, length: number)
	local old = holder:FindFirstChild("ShadeHaunt")
	if old then
		old:Destroy()
	end
	local halo = Instance.new("Highlight")
	halo.Name = "ShadeHaunt"
	halo.FillColor = shade.glow or shade.back
	halo.FillTransparency = 0.55
	halo.OutlineColor = shade.belly
	halo.OutlineTransparency = 0.15
	halo.DepthMode = Enum.HighlightDepthMode.Occluded
	halo:SetAttribute("ShadeEffect", true)
	halo.Parent = holder
	local wisps = Instance.new("ParticleEmitter")
	wisps.Name = "ShadeWisps"
	wisps.Rate = 9
	wisps.Lifetime = NumberRange.new(1.4, 2.6)
	wisps.Speed = NumberRange.new(length * 0.05, length * 0.2)
	wisps.SpreadAngle = Vector2.new(180, 180)
	wisps.Acceleration = Vector3.new(0, length * 0.08, 0)
	wisps.Drag = 1.5
	wisps.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.25, length * 0.16),
		NumberSequenceKeypoint.new(1, length * 0.05),
	})
	wisps.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	wisps.LightEmission = 1
	wisps.Color = ColorSequence.new(shade.belly, shade.glow or shade.back)
	wisps:SetAttribute("ShadeEffect", true)
	wisps.Parent = core
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
	local core = body:FindFirstChild("Body1")
	if shade == nil or core == nil or not core:IsA("BasePart") then
		return
	end
	if shade.spectral then
		haunt(body, core, shade, length)
	end
	if shade.glow then
		local light = Instance.new("PointLight")
		light.Name = "ShadeGlow"
		light.Color = shade.glow
		light.Range = math.clamp(length * 4, 8, 60)
		light.Brightness = if shade.spectral then 2.2 else 1.2
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
-- A fish's skin for a shade: ReplicatedStorage.ShadeSkins.<Fish>.<Shade>, a
-- SurfaceAppearance (or a StringValue holding a texture id), made by tools/shades and
-- filed by tools/studio/organize_shades.luau. Nil until it's imported.
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

local function paintMesh(body: Model, shadeId: string?, length: number)
	local mesh = body:FindFirstChild("Mesh")
	if mesh == nil then
		return
	end
	local shade = if shadeId then Config.Shades.byId[shadeId] else nil
	local spectral = shade ~= nil and shade.spectral == true
	local plan = body:GetAttribute("MeshPlan")
	local skin = if shade and not spectral
		then skinFor(if typeof(plan) == "string" then plan else nil, shade.id)
		else nil
	-- Without its skin imported yet, a shade tints the texture (multiplies, so it can
	-- only darken; the skin is the real look)
	local tint = if shade and skin == nil
		then shade.back:Lerp(Color3.new(1, 1, 1), 0.35)
		else Color3.new(1, 1, 1)
	local core: BasePart? = nil
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
		if spectral then
			holdOwn(part, true)
			part.Color = (shade :: ShadesConfig.Shade).back
			part.Material = Enum.Material.ForceField
			part.Transparency = (shade :: ShadesConfig.Shade).transparency or 0.3
		elseif skin then
			holdOwn(part, true)
			if skin:IsA("SurfaceAppearance") then
				local worn = skin:Clone()
				worn.Name = "ShadeSkin"
				worn.Parent = part
			elseif skin:IsA("StringValue") then
				if ownTexture == nil then
					part:SetAttribute("OwnTexture", part.TextureID)
				end
				part.TextureID = skin.Value
			end
			part.Color = Color3.new(1, 1, 1)
			part.Material = Enum.Material.Plastic
			part.Transparency = (shade :: ShadesConfig.Shade).transparency or 0
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
		haunt(mesh, core, shade, length)
	end
	if shade.glow then
		local light = Instance.new("PointLight")
		light.Name = "ShadeGlow"
		light.Color = shade.glow
		light.Range = math.clamp(length * 4, 8, 60)
		light.Brightness = if spectral then 2.2 else 1.2
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
	if shade == nil then
		return
	end
	if shade.spectral then
		-- The haunt breathes: the fill and the body's veil swell and fade slowly
		local pulse = 0.5 + 0.5 * math.sin(t * 1.7)
		local halo = body:FindFirstChild("ShadeHaunt", true)
		if halo and halo:IsA("Highlight") then
			halo.FillTransparency = 0.45 + 0.2 * pulse
			halo.OutlineTransparency = 0.05 + 0.25 * pulse
		end
		local veil = (shade.transparency or 0.3) + 0.12 * pulse
		for _, descendant in body:GetDescendants() do
			if descendant:IsA("BasePart") and descendant.Material == Enum.Material.ForceField then
				local base = descendant:GetAttribute("T0")
				descendant.Transparency = math.max(if typeof(base) == "number" then base else 0, veil)
			end
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
