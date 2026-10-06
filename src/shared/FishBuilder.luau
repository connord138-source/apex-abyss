--!strict
-- Builds a graybox fish from a body plan (Shared/FishPlans: one per species):
-- ellipsoid parts on a chain of Motor6Ds, so clients can swim it procedurally
-- (FishAnimator: a wave down the spine, a tail beat, a jaw snap). Every part and
-- joint is laid out for a fish 1 stud long and keeps that unit layout in
-- attributes, so applyScale can resize the whole fish to any length smoothly.
-- Forward is -Z. The real creature models replace these later with the same joint
-- names.
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
	local parts: { [string]: BasePart } = { Root = root }
	for _, spec in FishPlans.get(plan) do
		parts[spec.name] = FishBuilder.makePart(body, parts[spec.parent], spec, look, length)
	end
	character:SetAttribute("LookBack", look.back)
	character:SetAttribute("LookBelly", look.belly)
	character:SetAttribute("LookFin", look.fin)
	body.Parent = character
	return body
end

function FishBuilder.scaled(cframe: CFrame, scale: number): CFrame
	return scaled(cframe, scale)
end

-- Resizes a built body to `length` studs (every client eases this as the fish grows).
function FishBuilder.applyScale(body: Model, length: number)
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
