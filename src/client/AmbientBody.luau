--!strict
-- A sea creature's body, built once and posed every frame (owner, 2026-10-19: the turtles,
-- mantas and stingrays were "essentially just circles put together"; crabs "need more
-- detail like the turtles"): the imported model (ReplicatedStorage.AmbientModels.<Name>,
-- rigged by tools/blender/rig_ambient.py, docs/ASSETS.md) or, until it's imported, the
-- part-built stand-in from Shared/AmbientRigs. Both are posed by the same AmbientRigs
-- functions, joint by name: a model's bones take each turn in the creature's own axes
-- (Bone.Transform = R⁻¹ · turn · R, R the bone's rest turn against its mesh, as
-- SwimWave does), a stand-in's Motor6Ds take it as it is (its joints sit square to the
-- creature). One anchored part carries the rest, so a creature moves by one CFrame
-- (BulkMoveTo). A rigged Model faces -Z and is never turned.
--
-- Used by AmbientLifeController (rays, mantas, turtles, the far whales and mantas) and
-- ForageController (the edible crabs: tinted, painted and carrying their extras).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AmbientRigs = require(ReplicatedStorage.Shared.AmbientRigs)

local AmbientBody = {}

export type Options = {
	model: string?, -- ReplicatedStorage.AmbientModels.<model>
	tint: Color3?, -- × the model's own colours (its SurfaceAppearance.Color)
	paint: Color3?, -- a solid colour instead, the model's texture held aside
	extras: string?, -- what it carries (AmbientRigs.extras)
}

export type Body = {
	model: Model,
	root: BasePart, -- the one anchored part: everything else hangs off it
	parts: { BasePart }, -- every visible part (for fading)
	rig: string,
	size: number,
	floor: number, -- studs from its middle down to what it rests on
	imported: boolean,
	bones: { [string]: Bone },
	rest: { [string]: CFrame }, -- each bone's rest turn against the mesh
	motors: { [string]: Motor6D },
	pose: AmbientRigs.Pose, -- (reused each frame)
	lift: CFrame, -- the last pose's offset of the body (studs)
	offset: CFrame, -- the root part's frame from the creature's middle (studs)
	joints: number, -- joints posed a frame (the controllers' budget)
	fade: number,
}

type Proto = {
	model: Model,
	extents: Vector3, -- at scale 1
	middle: Vector3, -- the bounding box's middle from the primary part, at scale 1
	rest: { [string]: CFrame }?,
}

local protos: { [string]: Proto } = {}
local WHITE = Color3.new(1, 1, 1)

local function quiet(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

-- The imported model, set up once: anchored, scaled to 1, its middle measured. Nothing
-- while it isn't imported (asked again next time: an import can arrive mid-session).
local function protoOf(name: string): Proto?
	local known = protos[name]
	if known then
		return known
	end
	local folder = ReplicatedStorage:FindFirstChild("AmbientModels")
	local template = folder and folder:FindFirstChild(name)
	if
		template == nil
		or not template:IsA("Model")
		or template:FindFirstChildWhichIsA("Bone", true) == nil
	then
		return nil
	end
	local clone = template:Clone()
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			quiet(descendant)
		end
	end
	local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("MeshPart", true)
	if primary == nil then
		clone:Destroy()
		return nil
	end
	clone.PrimaryPart = primary
	clone:ScaleTo(1)
	clone:PivotTo(CFrame.new())
	local box, extents = clone:GetBoundingBox()
	local made: Proto = { model = clone, extents = extents, middle = box.Position, rest = nil }
	protos[name] = made
	return made
end

-- Each bone's rest turn against the mesh (taken once, on the first body, before any
-- turn: the creature's axes are the mesh's)
local function restOf(proto: Proto, primary: BasePart, bones: { [string]: Bone }): { [string]: CFrame }
	local known = proto.rest
	if known then
		return known
	end
	local made: { [string]: CFrame } = {}
	for name, bone in bones do
		made[name] = primary.CFrame:ToObjectSpace(bone.WorldCFrame * bone.Transform:Inverse()).Rotation
	end
	proto.rest = made
	return made
end

local function newPart(shape: string, size: Vector3, frame: CFrame, color: Color3, parent: Instance): BasePart
	local made: BasePart
	if shape == "wedge" then
		made = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		if shape == "ball" then
			block.Shape = Enum.PartType.Ball
			local d = math.min(size.X, size.Y, size.Z)
			size = Vector3.new(d, d, d)
		elseif shape == "cyl" then
			block.Shape = Enum.PartType.Cylinder
		end
		made = block
	end
	made.Anchored = false
	made.Massless = true
	quiet(made)
	made.Material = Enum.Material.SmoothPlastic
	made.TopSurface = Enum.SurfaceType.Smooth
	made.BottomSurface = Enum.SurfaceType.Smooth
	made.Color = color
	made.Size = Vector3.new(math.max(size.X, 0.02), math.max(size.Y, 0.02), math.max(size.Z, 0.02))
	made.CFrame = frame
	made.Parent = parent
	return made
end

local function weld(anchor: BasePart, part: BasePart)
	local joint = Instance.new("Weld")
	joint.Part0 = anchor
	joint.Part1 = part
	joint.C0 = anchor.CFrame:Inverse() * part.CFrame
	joint.Parent = part
end

-- What a body carries (crab extras) on its anchor parts, at rest in the creature's
-- space (its middle at the origin)
local function carry(
	model: Model,
	plan: AmbientRigs.Plan,
	extras: string,
	size: number,
	look: { [string]: Color3 },
	anchorOf: (string) -> BasePart?,
	parts: { BasePart }
)
	for _, built in AmbientRigs.parts(plan, {}, size, AmbientRigs.extras(extras)) do
		local anchor = anchorOf(built.joint)
		if anchor then
			local piece = newPart(built.shape, built.size, built.cframe, look[built.role] or WHITE, model)
			weld(anchor, piece)
			table.insert(parts, piece)
		end
	end
end

-- The imported model at `size` (its measure: span or length), tinted or painted
local function fromModel(
	proto: Proto,
	rig: string,
	size: number,
	look: { [string]: Color3 },
	options: Options,
	parent: Instance
): Body
	local plan = AmbientRigs.plan(rig)
	local unit = if plan.measure == "X" then proto.extents.X else proto.extents.Z
	local scale = size / math.max(unit, 1e-3)
	local model = proto.model:Clone()
	model:ScaleTo(scale)
	-- Its middle at the origin while it's put together
	local offset = CFrame.new(-proto.middle * scale)
	model:PivotTo(offset)
	local primary = model.PrimaryPart :: BasePart
	local parts: { BasePart } = {}
	local bones: { [string]: Bone } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Bone") then
			bones[descendant.Name] = descendant
		elseif descendant:IsA("BasePart") then
			table.insert(parts, descendant)
			local appearance = descendant:FindFirstChildOfClass("SurfaceAppearance")
			if options.paint then
				-- A crab that isn't red: its texture held aside (this is its own copy)
				if appearance then
					appearance:Destroy()
				end
				if descendant:IsA("MeshPart") then
					descendant.TextureID = ""
				end
				descendant.Color = options.paint
				descendant.Material = Enum.Material.SmoothPlastic
			elseif options.tint and appearance then
				-- SurfaceAppearance.Color multiplies the colour map (a texture set by
				-- TextureID can't be tinted: organize_imports gives these models a
				-- SurfaceAppearance)
				pcall(function()
					(appearance :: any).Color = options.tint
				end)
			end
		end
	end
	if options.extras then
		carry(model, plan, options.extras, size, look, function(joint: string): BasePart?
			return if joint == "Body" then primary else nil
		end, parts)
	end
	model.Parent = parent
	local count = 0
	for _ in bones do
		count += 1
	end
	return {
		model = model,
		root = primary,
		parts = parts,
		rig = rig,
		size = size,
		floor = proto.extents.Y * 0.5 * scale,
		imported = true,
		bones = bones,
		rest = restOf(proto, primary, bones),
		motors = {},
		pose = {},
		lift = CFrame.identity,
		offset = offset,
		joints = count,
		fade = 0,
	}
end

-- The part-built stand-in at `size`: each joint's first piece is its anchor (an
-- invisible one if it has none), hung from its parent's by a Motor6D at the joint
local function standIn(
	rig: string,
	size: number,
	look: { [string]: Color3 },
	options: Options,
	parent: Instance
): Body
	local plan = AmbientRigs.plan(rig)
	local model = Instance.new("Model")
	model.Name = rig
	local anchors: { [string]: BasePart } = {}
	local parts: { BasePart } = {}
	local loose: { { part: BasePart, joint: string } } = {}
	for _, built in AmbientRigs.parts(plan, {}, size) do
		local piece = newPart(built.shape, built.size, built.cframe, look[built.role] or WHITE, model)
		table.insert(parts, piece)
		local known: BasePart? = anchors[built.joint]
		if known == nil then
			anchors[built.joint] = piece
		else
			table.insert(loose, { part = piece, joint = built.joint })
		end
	end
	for _, j in plan.joints do
		local known: BasePart? = anchors[j.name]
		if known == nil then
			local hidden = newPart("block", Vector3.one * 0.05, CFrame.new(j.at * size), WHITE, model)
			hidden.Transparency = 1
			anchors[j.name] = hidden
		end
	end
	local root = anchors[plan.joints[1].name]
	root.Anchored = true
	model.PrimaryPart = root
	local motors: { [string]: Motor6D } = {}
	for _, j in plan.joints do
		local parentName = j.parent
		if parentName then
			local at = CFrame.new(j.at * size)
			local motor = Instance.new("Motor6D")
			motor.Name = j.name
			motor.Part0 = anchors[parentName]
			motor.Part1 = anchors[j.name]
			motor.C0 = anchors[parentName].CFrame:Inverse() * at
			motor.C1 = anchors[j.name].CFrame:Inverse() * at
			motor.Parent = anchors[j.name]
			motors[j.name] = motor
		end
	end
	for _, entry in loose do
		weld(anchors[entry.joint], entry.part)
	end
	if options.extras then
		carry(model, plan, options.extras, size, look, function(joint: string): BasePart?
			return anchors[joint]
		end, parts)
	end
	model.Parent = parent
	local count = 0
	for _ in motors do
		count += 1
	end
	return {
		model = model,
		root = root,
		parts = parts,
		rig = rig,
		size = size,
		floor = plan.floor * size,
		imported = false,
		bones = {},
		rest = {},
		motors = motors,
		pose = {},
		lift = CFrame.identity,
		offset = root.CFrame,
		joints = count,
		fade = 0,
	}
end

-- A body for rig `rig` (Shared/AmbientRigs) `size` studs (its span or length, as the
-- rig measures), in `look`'s colours by role while it's part-built
function AmbientBody.new(
	rig: string,
	size: number,
	look: { [string]: Color3 },
	options: Options,
	parent: Instance
): Body
	local proto = if options.model then protoOf(options.model) else nil
	if proto then
		return fromModel(proto, rig, size, look, options, parent)
	end
	return standIn(rig, size, look, options, parent)
end

-- Whether a model is imported (so a creature built part-built can be rebuilt with it)
function AmbientBody.imported(name: string): boolean
	return protoOf(name) ~= nil
end

-- Poses the body for this moment (its joints only; AmbientBody.frame places it)
function AmbientBody.pose(body: Body, motion: AmbientRigs.Motion)
	local lift = AmbientRigs.pose(body.rig, motion, body.pose)
	if body.imported then
		local bones, rest = body.bones, body.rest
		for name, turn in body.pose do
			local bone, r = bones[name], rest[name]
			if bone and r then
				bone.Transform = r:Inverse() * turn * r
			end
		end
	else
		local motors = body.motors
		for name, turn in body.pose do
			local motor = motors[name]
			if motor then
				motor.Transform = turn
			end
		end
	end
	body.lift = CFrame.new(lift.Position * body.size) * lift.Rotation
end

-- Where the root part goes for a creature whose middle is at `frame`
function AmbientBody.frame(body: Body, frame: CFrame): CFrame
	return frame * body.lift * body.offset
end

-- Fades the whole body (LocalTransparencyModifier: 0 shown .. 1 gone)
function AmbientBody.fade(body: Body, fade: number)
	if body.fade == fade then
		return
	end
	body.fade = fade
	for _, part in body.parts do
		part.LocalTransparencyModifier = fade
	end
end

function AmbientBody.destroy(body: Body)
	body.model:Destroy()
end

return AmbientBody
