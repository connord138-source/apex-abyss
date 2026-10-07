--!strict
-- Imported props for things the client draws itself in bulk (starfish, shrimp,
-- shells): a copy of ReplicatedStorage.WorldProps.<Name> fitted into a box, handed
-- back as loose anchored parts with their offsets from the box's center, so the
-- caller can keep moving them with BulkMoveTo the way it moves its placeholder
-- parts. Returns nil while the prop isn't imported (the placeholder is drawn).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PropParts = {}

export type Pieces = {
	parts: { BasePart },
	offsets: { CFrame }, -- each part's CFrame relative to the fitted box's center
	sizes: { Vector3 },
}

function PropParts.make(name: string, size: Vector3, parent: Instance): Pieces?
	local folder = ReplicatedStorage:FindFirstChild("WorldProps")
	local template = folder and folder:FindFirstChild(name)
	if template == nil or not template:IsA("Model") then
		return nil
	end
	local model = template:Clone()
	model:ScaleTo(1)
	local extents = model:GetExtentsSize()
	local ratio = math.min(
		size.X / math.max(extents.X, 0.01),
		size.Y / math.max(extents.Y, 0.01),
		size.Z / math.max(extents.Z, 0.01)
	)
	model:ScaleTo(ratio)
	-- Stand the box on its bottom face, centered, so the prop sits on the ground
	-- where the placeholder's center was
	model:PivotTo(CFrame.new())
	local box, boxSize = model:GetBoundingBox()
	local center = box * CFrame.new(0, 0, 0)
	local pieces: Pieces = { parts = {}, offsets = {}, sizes = {} }
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Massless = true
			for _, child in descendant:GetChildren() do
				if child:IsA("WeldConstraint") or child:IsA("Motor6D") or child:IsA("Weld") then
					child:Destroy()
				end
			end
			table.insert(pieces.parts, descendant)
			table.insert(
				pieces.offsets,
				CFrame.new(0, boxSize.Y / 2, 0) * center:ToObjectSpace(descendant.CFrame)
			)
			table.insert(pieces.sizes, descendant.Size)
			descendant.Parent = parent
		end
	end
	model:Destroy()
	if #pieces.parts == 0 then
		return nil
	end
	return pieces
end

-- Colors a prop's parts (and their textures, through SurfaceAppearance.Color, which
-- only ever darkens).
function PropParts.tint(pieces: Pieces, color: Color3)
	for _, part in pieces.parts do
		part.Color = color
		for _, child in part:GetChildren() do
			if child:IsA("SurfaceAppearance") then
				(child :: any).Color = color
			end
		end
	end
end

return PropParts
