--!strict
-- A lit photo of a prey species in a ViewportFrame, for the Catch Logbook (owner,
-- 2026-10-18: "We want a catch logbook that shows the largest they have caught").
-- Its import (ReplicatedStorage.PreyModels.<PreyId>: a rigged Model facing -Z, or a
-- static MeshPart, turned round unless stamped `Facing = "-Z"`, as SchoolController
-- draws them), or a part-built stand-in in its colours until it's imported. Each
-- species is built once and cloned into a photo only when its row comes into view, a
-- few a frame, so the long list stays light. Side-on, head to the left, a little from
-- above. A species never caught is a dark silhouette.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local SwimWave = require(ReplicatedStorage.Shared.SwimWave)

local PreyPhoto = {}

local FOV = 24
local PER_FRAME = 2 -- photos made a frame at most
local MARGIN = 80 -- pixels outside the list's window a row may be and still get one
local LENGTH = 4 -- studs: every subject is scaled to this long

type Pending = { holder: GuiObject, preyId: string, dark: boolean, clip: GuiObject? }

local masters: { [string]: Model } = {}
local pending: { Pending } = {}

local function blob(parent: Instance, size: Vector3, cframe: CFrame, color: Color3)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.Parent = parent
end

-- The species facing -Z, LENGTH long, its middle at the origin
local function master(preyId: string): Model
	local cached = masters[preyId]
	if cached then
		return cached
	end
	local model = Instance.new("Model")
	model.Name = preyId
	local folder = ReplicatedStorage:FindFirstChild("PreyModels")
	local template = folder and folder:FindFirstChild(preyId)
	local placed = false
	if template and template:IsA("Model") then
		local clone = template:Clone()
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			elseif d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			end
		end
		local extents = clone:GetExtentsSize()
		clone:ScaleTo(clone:GetScale() * LENGTH / math.max(extents.Z, 0.01))
		local box = clone:GetBoundingBox()
		clone:PivotTo(clone:GetPivot() - box.Position)
		clone.Parent = model
		placed = true
	elseif template and template:IsA("MeshPart") then
		local mesh = template:Clone()
		mesh.Anchored = true
		mesh.Size = template.Size * (LENGTH / math.max(template.Size.Z, 0.01))
		mesh.CFrame = if SwimWave.needsFlip(template) then CFrame.Angles(0, math.pi, 0) else CFrame.identity
		mesh.Parent = model
		placed = true
	end
	if not placed then
		-- The stand-in: a body, a paler belly and a tail fin, head at -Z
		local prey = Config.Prey.byId[preyId]
		local back = if prey then prey.back else Color3.fromRGB(120, 150, 160)
		local belly = if prey then prey.belly else Color3.fromRGB(210, 220, 225)
		local slim = if prey then prey.slim else 0.3
		blob(
			model,
			Vector3.new(LENGTH * slim * 0.8, LENGTH * slim, LENGTH * 0.78),
			CFrame.new(0, 0, -0.1),
			back
		)
		blob(
			model,
			Vector3.new(LENGTH * slim * 0.6, LENGTH * slim * 0.55, LENGTH * 0.66),
			CFrame.new(0, -LENGTH * slim * 0.2, -0.15),
			belly
		)
		blob(
			model,
			Vector3.new(LENGTH * 0.04, LENGTH * slim * 1.1, LENGTH * 0.26),
			CFrame.new(0, 0, LENGTH * 0.4),
			back:Lerp(belly, 0.3)
		)
	end
	masters[preyId] = model
	return model
end

local function photo(entry: Pending): boolean
	local holder = entry.holder
	local frame = Instance.new("ViewportFrame")
	frame.Name = "Photo"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = holder.ZIndex
	if entry.dark then
		-- Never caught: a dark shape against the backdrop
		frame.Ambient = Color3.new(0, 0, 0)
		frame.LightColor = Color3.new(0, 0, 0)
		frame.ImageColor3 = Color3.fromRGB(6, 14, 22)
		frame.ImageTransparency = 0.05
	else
		frame.Ambient = Color3.fromRGB(150, 166, 178)
		frame.LightColor = Color3.fromRGB(255, 250, 240)
		frame.LightDirection = Vector3.new(0.4, -1, -0.5)
	end
	local model = master(entry.preyId):Clone()
	-- A touch of three-quarter: the head turned a little toward us, nose up
	model:PivotTo(CFrame.Angles(0, math.rad(-16), 0) * CFrame.Angles(math.rad(4), 0, 0) * model:GetPivot())
	model.Parent = frame
	local box, extents = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	camera.Parent = frame
	frame.CurrentCamera = camera
	local size = holder.AbsoluteSize
	local aspect = if size.Y > 1 then size.X / size.Y else 1.4
	local tanV = math.tan(math.rad(FOV / 2))
	-- Side-on from -X (the head, at -Z, on the left), a little from above
	local distance = math.max(extents.Z / 2 / (tanV * aspect), extents.Y / 2 / tanV) * 1.18 + extents.X / 2
	local look = Vector3.new(-1, 0.18, 0).Unit
	camera.CFrame = CFrame.lookAt(box.Position + look * distance, box.Position)
	frame.Parent = holder
	return true
end

local function inView(entry: Pending): boolean
	local holder = entry.holder
	if not holder.Visible then
		return false
	end
	local clip = entry.clip
	if clip == nil then
		return true
	end
	local at, size = holder.AbsolutePosition, holder.AbsoluteSize
	local top, window = clip.AbsolutePosition, clip.AbsoluteSize
	return at.X + size.X >= top.X - MARGIN
		and at.X <= top.X + window.X + MARGIN
		and at.Y + size.Y >= top.Y - MARGIN
		and at.Y <= top.Y + window.Y + MARGIN
end

local function step()
	local made = 0
	for i = #pending, 1, -1 do
		local entry = pending[i]
		if entry.holder.Parent == nil or not entry.holder:IsDescendantOf(game) then
			table.remove(pending, i)
		elseif made < PER_FRAME and inView(entry) then
			table.remove(pending, i)
			made += 1
			local ok, err = pcall(photo, entry)
			if not ok then
				warn("[PreyPhoto]", entry.preyId, err)
			end
		end
	end
end

local connection: RBXScriptConnection? = nil

-- A photo of prey `preyId` filling `holder` (a dark silhouette when `dark`), made once
-- the holder is within `clip`'s window (the list it scrolls in; nil: at once)
function PreyPhoto.attach(holder: GuiObject, preyId: string, dark: boolean, clip: GuiObject?)
	table.insert(pending, { holder = holder, preyId = preyId, dark = dark, clip = clip })
	if connection == nil then
		connection = RunService.Heartbeat:Connect(step)
	end
end

return PreyPhoto
