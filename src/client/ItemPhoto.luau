--!strict
-- A lit photo of a den thing (Config/Dens items) in a ViewportFrame, for the den
-- shop's rows and Build mode's tray tiles (owner, 2026-10-18: "Den shop needs pics
-- of the items they are buying as well"). Each thing is built once per glow color
-- (Shared/DenItems, the same model as the placed thing and Build mode's ghost:
-- imported props where they're in, the part-built pieces where they aren't) and
-- cloned into a photo only when its row or tile comes into view, a few a frame, so
-- a long shop list stays light. Framed by the thing's own box, three-quarter from
-- the front and above (a rug from higher, a wall thing nearly face on).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DensConfig = require(ReplicatedStorage.Shared.Config.Dens)
local DenItems = require(ReplicatedStorage.Shared.DenItems)

local ItemPhoto = {}

local FOV = 30
local PER_FRAME = 3 -- photos made a frame at most
local MARGIN = 80 -- pixels outside the list's window a row may be and still get one

type Pending = { holder: GuiObject, item: DensConfig.Item, glow: Color3, clip: GuiObject? }

local masters: { [string]: Model } = {}
local pending: { Pending } = {}

-- The thing as it's built in a den, without its lights and particles (a viewport
-- draws neither)
local function master(item: DensConfig.Item, glow: Color3): Model
	local key = `{item.id}|{glow:ToHex()}`
	local cached = masters[key]
	if cached then
		return cached
	end
	local model = DenItems.build(item, glow, item.kinds[1])
	for _, d in model:GetDescendants() do
		if d:IsA("Light") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	masters[key] = model
	return model
end

-- The box round a model's visible parts
local function bounds(model: Model): (Vector3, Vector3)
	local low = Vector3.one * math.huge
	local high = -Vector3.one * math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local half = d.Size / 2
			for _, corner in
				{
					Vector3.new(1, 1, 1),
					Vector3.new(1, 1, -1),
					Vector3.new(1, -1, 1),
					Vector3.new(1, -1, -1),
					Vector3.new(-1, 1, 1),
					Vector3.new(-1, 1, -1),
					Vector3.new(-1, -1, 1),
					Vector3.new(-1, -1, -1),
				}
			do
				local point = d.CFrame:PointToWorldSpace(half * corner)
				low = low:Min(point)
				high = high:Max(point)
			end
		end
	end
	if low.X > high.X then
		local box, size = model:GetBoundingBox()
		return box.Position, size
	end
	return (low + high) / 2, high - low
end

local function photo(entry: Pending)
	local holder = entry.holder
	local item = entry.item
	local frame = Instance.new("ViewportFrame")
	frame.Name = "Photo"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Ambient = Color3.fromRGB(140, 152, 164)
	frame.LightColor = Color3.fromRGB(255, 248, 236)
	frame.LightDirection = Vector3.new(0.35, -1, 0.55)
	frame.ZIndex = holder.ZIndex
	local model = master(item, entry.glow):Clone()
	model.Parent = frame
	local center, extents = bounds(model)
	-- Which way the camera looks from: the thing's front is -Z
	local from = Vector3.new(-0.6, 0.5, -1)
	if item.flat then
		from = Vector3.new(-0.3, 1.4, -0.8)
	elseif item.kinds[1] == "wall" then
		from = Vector3.new(-0.35, 0.2, -1)
	elseif item.kinds[1] == "ceiling" then
		from = Vector3.new(-0.5, 0.05, -1)
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	camera.Parent = frame
	frame.CurrentCamera = camera
	local radius = math.max((extents / 2).Magnitude, 0.5)
	local distance = radius / math.sin(math.rad(FOV / 2)) * 0.92
	camera.CFrame = CFrame.lookAt(center + from.Unit * distance, center)
	frame.Parent = holder
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
				warn("[ItemPhoto]", entry.item.id, err)
			end
		end
	end
end

local connection: RBXScriptConnection? = nil

-- A photo of `item` (in the den's `glow` color) filling `holder`, made once the
-- holder is within `clip`'s window (the list it scrolls in; nil: at once)
function ItemPhoto.attach(holder: GuiObject, item: DensConfig.Item, glow: Color3, clip: GuiObject?)
	table.insert(pending, { holder = holder, item = item, glow = glow, clip = clip })
	if connection == nil then
		connection = RunService.Heartbeat:Connect(step)
	end
end

return ItemPhoto
