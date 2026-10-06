--!strict
-- The graybox player fish: ellipsoid segments on a chain of Motor6Ds, so clients
-- can swim it procedurally (FishAnimator: a wave down the spine, a tail beat, a
-- jaw snap). Every part and joint is laid out for a fish 1 stud long and keeps
-- that unit layout in attributes, so applyScale can resize the whole fish to any
-- length smoothly. Forward is -Z. The real creature models replace this later
-- with the same joint names.
local FishBuilder = {}

export type Look = {
	back: Color3,
	belly: Color3,
	fin: Color3,
}

type PartSpec = {
	name: string,
	parent: string, -- part it hangs from ("Root" = the HumanoidRootPart)
	size: Vector3, -- unit size
	c0: CFrame, -- the joint in the parent's frame (unit)
	c1: CFrame, -- the joint in this part's frame (unit)
	shape: "Ellipsoid" | "Wedge",
	color: "back" | "belly" | "fin" | "eye",
}

-- The spine, front to back, then the fins. Joints sit where segments meet, so a
-- Transform rotation bends the body there.
local PARTS: { PartSpec } = {
	{
		name = "Body1",
		parent = "Root",
		size = Vector3.new(0.3, 0.32, 0.36),
		c0 = CFrame.new(0, 0, -0.02),
		c1 = CFrame.new(),
		shape = "Ellipsoid",
		color = "back",
	},
	{
		name = "Head",
		parent = "Body1",
		size = Vector3.new(0.25, 0.26, 0.3),
		c0 = CFrame.new(0, 0.01, -0.15),
		c1 = CFrame.new(0, 0, 0.12),
		shape = "Ellipsoid",
		color = "back",
	},
	{
		name = "Jaw",
		parent = "Head",
		size = Vector3.new(0.17, 0.07, 0.2),
		c0 = CFrame.new(0, -0.075, 0.05),
		c1 = CFrame.new(0, 0, 0.1),
		shape = "Ellipsoid",
		color = "belly",
	},
	{
		name = "Belly",
		parent = "Body1",
		size = Vector3.new(0.26, 0.2, 0.42),
		c0 = CFrame.new(0, -0.07, 0.03),
		c1 = CFrame.new(),
		shape = "Ellipsoid",
		color = "belly",
	},
	{
		name = "Body2",
		parent = "Body1",
		size = Vector3.new(0.23, 0.26, 0.27),
		c0 = CFrame.new(0, 0, 0.15),
		c1 = CFrame.new(0, 0, -0.12),
		shape = "Ellipsoid",
		color = "back",
	},
	{
		name = "Body3",
		parent = "Body2",
		size = Vector3.new(0.15, 0.18, 0.22),
		c0 = CFrame.new(0, 0, 0.12),
		c1 = CFrame.new(0, 0, -0.09),
		shape = "Ellipsoid",
		color = "back",
	},
	{
		name = "Stalk",
		parent = "Body3",
		size = Vector3.new(0.07, 0.1, 0.16),
		c0 = CFrame.new(0, 0, 0.09),
		c1 = CFrame.new(0, 0, -0.06),
		shape = "Ellipsoid",
		color = "back",
	},
	{
		name = "TailUp",
		parent = "Stalk",
		size = Vector3.new(0.025, 0.24, 0.11),
		c0 = CFrame.new(0, 0, 0.06) * CFrame.Angles(math.rad(38), 0, 0),
		c1 = CFrame.new(0, -0.1, 0),
		shape = "Ellipsoid",
		color = "fin",
	},
	{
		name = "TailDown",
		parent = "Stalk",
		size = Vector3.new(0.025, 0.22, 0.1),
		c0 = CFrame.new(0, 0, 0.06) * CFrame.Angles(math.rad(-38), 0, 0),
		c1 = CFrame.new(0, 0.09, 0),
		shape = "Ellipsoid",
		color = "fin",
	},
	{
		name = "Dorsal",
		parent = "Body1",
		size = Vector3.new(0.02, 0.15, 0.2),
		c0 = CFrame.new(0, 0.2, 0.04),
		c1 = CFrame.new(),
		shape = "Wedge",
		color = "fin",
	},
	{
		name = "FinL",
		parent = "Body1",
		size = Vector3.new(0.14, 0.015, 0.08),
		c0 = CFrame.new(-0.13, -0.07, -0.08) * CFrame.Angles(0, math.rad(-25), math.rad(-20)),
		c1 = CFrame.new(0.06, 0, 0),
		shape = "Ellipsoid",
		color = "fin",
	},
	{
		name = "FinR",
		parent = "Body1",
		size = Vector3.new(0.14, 0.015, 0.08),
		c0 = CFrame.new(0.13, -0.07, -0.08) * CFrame.Angles(0, math.rad(25), math.rad(20)),
		c1 = CFrame.new(-0.06, 0, 0),
		shape = "Ellipsoid",
		color = "fin",
	},
	{
		name = "EyeL",
		parent = "Head",
		size = Vector3.new(0.05, 0.05, 0.05),
		c0 = CFrame.new(-0.1, 0.045, -0.05),
		c1 = CFrame.new(),
		shape = "Ellipsoid",
		color = "eye",
	},
	{
		name = "EyeR",
		parent = "Head",
		size = Vector3.new(0.05, 0.05, 0.05),
		c0 = CFrame.new(0.1, 0.045, -0.05),
		c1 = CFrame.new(),
		shape = "Ellipsoid",
		color = "eye",
	},
}

local EYE = Color3.fromRGB(16, 18, 22)

local function scaled(cframe: CFrame, scale: number): CFrame
	return CFrame.new(cframe.Position * scale) * cframe.Rotation
end

-- Builds the fish's body under `character`, jointed to `root`, at `length` studs.
-- Returns the Body model.
function FishBuilder.build(character: Model, root: BasePart, look: Look, length: number): Model
	local body = Instance.new("Model")
	body.Name = "Body"
	local parts: { [string]: BasePart } = { Root = root }
	for _, spec in PARTS do
		local part: BasePart
		if spec.shape == "Wedge" then
			part = Instance.new("WedgePart")
		else
			part = Instance.new("Part")
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		end
		part.Name = spec.name
		part.Material = Enum.Material.SmoothPlastic
		part.Color = if spec.color == "eye" then EYE else (look :: any)[spec.color]
		part.Reflectance = if spec.color == "eye" then 0.25 else 0.04
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = spec.color ~= "eye"
		part:SetAttribute("U", spec.size)
		part.Size = spec.size * length
		part.CFrame = root.CFrame
		part.Parent = body
		parts[spec.name] = part

		local joint = Instance.new("Motor6D")
		joint.Name = spec.name
		joint.Part0 = parts[spec.parent]
		joint.Part1 = part
		joint:SetAttribute("C0", spec.c0)
		joint:SetAttribute("C1", spec.c1)
		joint.C0 = scaled(spec.c0, length)
		joint.C1 = scaled(spec.c1, length)
		joint.Parent = part
	end
	body.Parent = character
	return body
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
