--!strict
-- Builds a graybox fish from a body plan (Shared/FishPlans: one per species):
-- ellipsoid parts on a chain of Motor6Ds, so clients can swim it procedurally
-- (FishAnimator: a wave down the spine, a tail beat, a jaw snap). Every part and
-- joint is laid out for a fish 1 stud long and keeps that unit layout in
-- attributes, so applyScale can resize the whole fish to any length smoothly.
-- Forward is -Z. The real creature models replace these later with the same joint
-- names.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Species = require(script.Parent.Config.Species)
local FishPlans = require(script.Parent.FishPlans)

local FishBuilder = {}

export type Look = {
	back: Color3,
	belly: Color3,
	fin: Color3,
}

export type PartSpec = FishPlans.PartSpec

local EYE = Color3.fromRGB(16, 18, 22)

local function scaled(cframe: CFrame, scale: number): CFrame
	return CFrame.new(cframe.Position * scale) * cframe.Rotation
end

-- Makes one part of a fish and its joint, at `length` studs. The unit layout is
-- kept in attributes (U, C0, C1) and again as the originals (U0, C00, C10), so
-- applyScale can resize it and Shared/Cosmetics can reshape it and put it back.
function FishBuilder.makePart(
	body: Model,
	parentPart: BasePart,
	spec: PartSpec,
	look: Look,
	length: number
): BasePart
	local part: BasePart
	if spec.shape == "Wedge" then
		part = Instance.new("WedgePart")
	elseif spec.shape == "Block" then
		part = Instance.new("Part")
	elseif spec.shape == "Ball" then
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		part = ball
	else
		part = Instance.new("Part")
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	part.Name = spec.name
	part.Material = spec.material or Enum.Material.SmoothPlastic
	part.Color = if spec.color == "eye"
		then EYE
		elseif spec.color == "fixed" then spec.fixed or Color3.new(1, 1, 1)
		else (look :: any)[spec.color]
	part.Reflectance = if spec.color == "eye" then 0.25 else 0.04
	part.Transparency = spec.transparency or 0
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = spec.color ~= "eye" and (spec.transparency or 0) < 0.3
	part:SetAttribute("Role", spec.color)
	part:SetAttribute("U", spec.size)
	part:SetAttribute("U0", spec.size)
	part:SetAttribute("T0", spec.transparency or 0)
	part.Size = spec.size * length
	part.CFrame = parentPart.CFrame
	if spec.light then
		local light = Instance.new("PointLight")
		light.Color = spec.light
		light.Range = 10
		light.Brightness = 2
		light.Parent = part
	end
	part.Parent = body

	local joint = Instance.new("Motor6D")
	joint.Name = spec.name
	joint.Part0 = parentPart
	joint.Part1 = part
	joint:SetAttribute("C0", spec.c0)
	joint:SetAttribute("C1", spec.c1)
	joint:SetAttribute("C00", spec.c0)
	joint:SetAttribute("C10", spec.c1)
	joint.C0 = scaled(spec.c0, length)
	joint.C1 = scaled(spec.c1, length)
	joint.Parent = part
	return part
end

-- Builds the fish's body under `character`, jointed to `root`, at `length` studs.
-- Returns the Body model. The base colors go on the character too (LookBack,
-- LookBelly, LookFin), so a shade can be taken off again.
function FishBuilder.build(character: Model, root: BasePart, look: Look, length: number, plan: string?): Model
	local body = Instance.new("Model")
	body.Name = "Body"
	body:SetAttribute("Plan", plan or "Nibbler")
	local mesh = FishBuilder.meshTemplate(plan)
	if mesh then
		FishBuilder.buildMesh(body, root, mesh, length)
	else
		local parts: { [string]: BasePart } = { Root = root }
		for _, spec in FishPlans.get(plan) do
			parts[spec.name] = FishBuilder.makePart(body, parts[spec.parent], spec, look, length)
		end
	end
	character:SetAttribute("LookBack", look.back)
	character:SetAttribute("LookBelly", look.belly)
	character:SetAttribute("LookFin", look.fin)
	body.Parent = character
	return body
end

-- The imported, rigged model for a species (docs/ASSETS.md):
-- ReplicatedStorage.FishModels.<name>, a Model holding one skinned MeshPart with
-- Root/Head/Spine1..N/Tail bones, facing -Z. It's named after its file: the body
-- plan (Puffer, Angler) or the species id (MorayEel, ReefShark, whose plans are Eel
-- and Shark, so they stayed graybox until both were looked up, playtest
-- 2026-10-07). Nil while it isn't imported, and the graybox part body is built.
function FishBuilder.meshTemplate(plan: string?): Model?
	local folder = ReplicatedStorage:FindFirstChild("FishModels")
	if folder == nil then
		return nil
	end
	local name = plan or "Nibbler"
	local template = folder:FindFirstChild(name)
	if template == nil then
		for _, species in Species.list do
			if species.plan == name then
				template = folder:FindFirstChild(species.id)
				break
			end
		end
	end
	if template and template:IsA("Model") and template:FindFirstChildWhichIsA("MeshPart", true) then
		return template
	end
	return nil
end

-- A mesh body: the template's parts, massless and welded to the root with a
-- Motor6D named Mesh, centered on it, scaled so the body is `length` long.
-- `UnitScale` (the model scale at 1 stud of length) and `Mesh` are stored for
-- applyScale and the animator.
function FishBuilder.buildMesh(body: Model, root: BasePart, template: Model, length: number)
	local model = template:Clone()
	model.Name = "Mesh"
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
	model:ScaleTo(1)
	local extents = model:GetExtentsSize()
	local unitScale = 1 / math.max(extents.Z, 0.01)
	model:ScaleTo(unitScale * length)
	-- Center the body on the root, nose forward (-Z)
	model:PivotTo(CFrame.new())
	local box = model:GetBoundingBox()
	model:PivotTo(CFrame.new(-box.Position))
	local primary: BasePart? = model.PrimaryPart or model:FindFirstChildWhichIsA("MeshPart", true)
	if primary == nil then
		model:Destroy()
		return
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= primary then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end
	local joint = Instance.new("Motor6D")
	joint.Name = "Mesh"
	joint.Part0 = root
	joint.Part1 = primary
	joint.C0 = CFrame.new()
	joint.C1 = primary.CFrame -- the primary part's offset from the centered model
	joint.Parent = primary
	model.Parent = body
	body:SetAttribute("Mesh", true)
	body:SetAttribute("UnitScale", unitScale)
	body:SetAttribute("Applied", length)
end

function FishBuilder.scaled(cframe: CFrame, scale: number): CFrame
	return scaled(cframe, scale)
end

-- Resizes a built body to `length` studs (every client eases this as the fish grows).
function FishBuilder.applyScale(body: Model, length: number)
	local mesh = body:FindFirstChild("Mesh")
	local unitScale = body:GetAttribute("UnitScale")
	if mesh and mesh:IsA("Model") and typeof(unitScale) == "number" then
		-- ScaleTo scales the bones with the mesh; the Motor6D's C1 follows the
		-- primary part's offset
		mesh:ScaleTo(unitScale * length)
		local primary = mesh.PrimaryPart or mesh:FindFirstChildWhichIsA("MeshPart", true)
		local joint = primary and primary:FindFirstChild("Mesh")
		if primary and joint and joint:IsA("Motor6D") then
			local applied = body:GetAttribute("Applied")
			if typeof(applied) == "number" and applied > 0 then
				local c1 = joint.C1
				joint.C1 = CFrame.new(c1.Position * (length / applied)) * c1.Rotation
			end
		end
		body:SetAttribute("Applied", length)
	end
	for _, child in body:GetChildren() do
		if child:IsA("BasePart") then
			local unit = child:GetAttribute("U")
			if typeof(unit) == "Vector3" then
				child.Size = unit * length
			end
			local joint = child:FindFirstChildOfClass("Motor6D")
			if joint then
				local c0 = joint:GetAttribute("C0")
				local c1 = joint:GetAttribute("C1")
				if typeof(c0) == "CFrame" and typeof(c1) == "CFrame" then
					joint.C0 = scaled(c0, length)
					joint.C1 = scaled(c1, length)
				end
			end
		end
	end
end

-- The base look stored on a character by build.
function FishBuilder.lookOf(character: Instance): Look?
	local back = character:GetAttribute("LookBack")
	local belly = character:GetAttribute("LookBelly")
	local fin = character:GetAttribute("LookFin")
	if typeof(back) == "Color3" and typeof(belly) == "Color3" and typeof(fin) == "Color3" then
		return { back = back, belly = belly, fin = fin }
	end
	return nil
end

-- The joints by part name, for the animator.
function FishBuilder.joints(body: Model): { [string]: Motor6D }
	local joints: { [string]: Motor6D } = {}
	for _, child in body:GetChildren() do
		local joint = child:FindFirstChildOfClass("Motor6D")
		if joint then
			joints[joint.Name] = joint
		end
	end
	return joints
end

return FishBuilder
