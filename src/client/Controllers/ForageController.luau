--!strict
-- Starfish and shrimp on this client: draws every spot (shrimp hop about a
-- little near you; starfish lie still), eats them the moment they're in reach of
-- the mouth (sucked in), and tells the server in small batches. If the server
-- doesn't confirm an eat within a moment, the food comes back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PropParts = require(ReplicatedStorage.Shared.PropParts)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local ClientState = require(script.Parent.Parent.ClientState)
local SwimController = require(script.Parent.SwimController)

local Forage = Config.Forage
type ForageDef = typeof(Forage.list[1])

local ForageController = {
	-- (mass, position) — we ate one (the HUD pops a number)
	ate = Signal.new(),
}

local HOP_DISTANCE = 140 -- shrimp further away than this hold still
local SUCK_SECONDS = 0.12
local CONFIRM_SECONDS = 1.5
local SEND_INTERVAL = 0.06

type Food = {
	index: number,
	kind: string,
	position: Vector3,
	parts: { BasePart },
	offsets: { CFrame }, -- each part relative to the food's frame
	sizes: { Vector3 },
	yaw: number,
	hidden: boolean,
	backAt: number,
	pendingUntil: number,
	suckFrom: Vector3?,
	suckStart: number,
	pulled: boolean, -- drawn toward a mouth right now (suction)
}

local foods: { Food } = {}
local batch: { number } = {}
local lastSend = 0
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local function ellipsoid(parent: Instance, color: Color3, size: Vector3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	part.Size = size
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.Parent = parent
	return part
end

-- A starfish: the imported model, or five arms round a middle, lying flat.
local function starfish(parent: Instance, def: ForageDef, rng: Random): ({ BasePart }, { CFrame })
	local scale = rng:NextNumber(0.85, 1.25)
	local prop = PropParts.make("Starfish", Vector3.new(1.9, 0.6, 1.9) * scale, parent)
	if prop then
		return prop.parts, prop.offsets
	end
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local middle = ellipsoid(parent, def.accent, Vector3.new(0.7, 0.22, 0.7) * scale)
	table.insert(parts, middle)
	table.insert(offsets, CFrame.new())
	for arm = 0, 4 do
		local part = ellipsoid(parent, def.color, Vector3.new(0.34, 0.16, 1.1) * scale)
		table.insert(parts, part)
		table.insert(offsets, CFrame.Angles(0, arm * math.rad(72), 0) * CFrame.new(0, 0, -0.5 * scale))
	end
	return parts, offsets
end

-- A shrimp: the imported model, or a curled body and a tail fan.
local function shrimp(parent: Instance, def: ForageDef, rng: Random): ({ BasePart }, { CFrame })
	local scale = rng:NextNumber(0.85, 1.2)
	local prop = PropParts.make("Shrimp", Vector3.new(0.9, 0.7, 1.5) * scale, parent)
	if prop then
		return prop.parts, prop.offsets
	end
	local body = ellipsoid(parent, def.color, Vector3.new(0.32, 0.36, 0.95) * scale)
	local tail = ellipsoid(parent, def.accent, Vector3.new(0.42, 0.12, 0.32) * scale)
	return { body, tail }, {
		CFrame.Angles(math.rad(-12), 0, 0),
		CFrame.new(0, 0.12 * scale, 0.5 * scale) * CFrame.Angles(math.rad(25), 0, 0),
	}
end

-- Where a shrimp hops to on its `k`th hop (each hop goes a different way).
local function hopPoint(food: Food, k: number): Vector3
	local angle = (k * 2.39996 + food.index) % (2 * math.pi)
	return food.position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * Forage.HOP * 0.55
end

local function frameOf(food: Food, now: number, near: boolean): CFrame
	if food.kind ~= "Shrimp" or not near then
		return CFrame.new(food.position) * CFrame.Angles(0, food.yaw, 0)
	end
	-- A short hop every couple of seconds, then a rest
	local cycle = 2.4 + (food.index % 5) * 0.3
	local time = now + food.index * 0.37
	local k = math.floor(time / cycle)
	local along = math.clamp((time % cycle) / 0.45, 0, 1)
	local from, to = hopPoint(food, k - 1), hopPoint(food, k)
	local at = from:Lerp(to, along) + Vector3.new(0, math.sin(along * math.pi) * 0.5, 0)
	local direction = to - from
	if direction.Magnitude < 1e-3 then
		return CFrame.new(at)
	end
	return CFrame.lookAt(at, at + direction)
end

local function place(food: Food, frame: CFrame, shrink: number)
	for i, part in food.parts do
		table.insert(moveParts, part)
		table.insert(moveFrames, frame * food.offsets[i])
		if shrink ~= 1 then
			part.Size = food.sizes[i] * shrink
		end
	end
end

local function setHidden(food: Food, hidden: boolean)
	if food.hidden == hidden then
		return
	end
	food.hidden = hidden
	-- Back on its spot (it was last drawn where a mouth sucked it in)
	local home = frameOf(food, 0, false)
	for i, part in food.parts do
		part.Transparency = if hidden then 1 else 0
		if not hidden then
			part.Size = food.sizes[i]
			part.CFrame = home * food.offsets[i]
		end
	end
end

local function build(positions: { Vector3 }, kinds: { string })
	local folder = Instance.new("Folder")
	folder.Name = "Forage"
	local rng = Random.new(7)
	for index, position in positions do
		local kind = kinds[index]
		local def = Forage.byId[kind]
		if def == nil then
			continue
		end
		local parts, offsets
		if kind == "Starfish" then
			parts, offsets = starfish(folder, def, rng)
		else
			parts, offsets = shrimp(folder, def, rng)
		end
		local sizes: { Vector3 } = {}
		for i, part in parts do
			sizes[i] = part.Size
		end
		local food: Food = {
			index = index,
			kind = kind,
			position = position,
			parts = parts,
			offsets = offsets,
			sizes = sizes,
			yaw = rng:NextNumber(0, 2 * math.pi),
			hidden = false,
			backAt = 0,
			pendingUntil = 0,
			suckFrom = nil,
			suckStart = 0,
			pulled = false,
		}
		foods[index] = food
		local frame = frameOf(food, 0, false)
		for i, part in parts do
			part.CFrame = frame * offsets[i]
		end
	end
	folder.Parent = workspace
end

local function step()
	local now = Timing.clock()
	local camera = workspace.CurrentCamera.CFrame.Position
	local root = SwimController.root()
	local length = SwimController.length()
	local mouth = if root then root.CFrame:PointToWorldSpace(Size.mouthOffset(length)) else nil
	local reach = Size.reach(length) * Forage.REACH_SCALE + Forage.REACH_BONUS
	local pullRange = reach * Forage.PULL
	table.clear(moveParts)
	table.clear(moveFrames)
	for _, food in foods do
		if food.hidden and food.suckFrom == nil then
			if food.pendingUntil > 0 and now > food.pendingUntil then
				food.pendingUntil = 0
				food.backAt = 0
			end
			if food.pendingUntil == 0 and now >= food.backAt then
				setHidden(food, false)
			end
			continue
		end
		if food.hidden then
			continue
		end
		if food.suckFrom then
			local alpha = math.clamp((now - food.suckStart) / SUCK_SECONDS, 0, 1)
			local at = (food.suckFrom :: Vector3):Lerp(mouth or food.position, alpha * alpha)
			place(food, CFrame.new(at) * CFrame.Angles(0, food.yaw, 0), 1 - alpha * 0.8)
			if alpha >= 1 then
				food.suckFrom = nil
				setHidden(food, true)
			end
			continue
		end
		local near = (food.position - camera).Magnitude < HOP_DISTANCE
		local frame = frameOf(food, now, near)
		local moved = near and food.kind == "Shrimp"
		if mouth then
			local gap = (frame.Position - mouth).Magnitude
			if gap < pullRange then
				-- Suction: drawn toward the mouth as it comes close
				local share = (1 - gap / pullRange) * Forage.PULL_SHARE
				frame = CFrame.new(frame.Position:Lerp(mouth, share)) * frame.Rotation
				gap = (frame.Position - mouth).Magnitude
				food.pulled, moved = true, true
			elseif food.pulled then
				food.pulled, moved = false, true
			end
			if gap <= reach then
				food.suckFrom = frame.Position
				food.suckStart = now
				food.pendingUntil = now + CONFIRM_SECONDS
				food.backAt = math.huge
				food.pulled = false
				table.insert(batch, food.index)
				ForageController.ate:fire(Forage.byId[food.kind].mass, frame.Position)
				continue
			end
		end
		if moved then
			place(food, frame, 1)
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	if #batch > 0 and now - lastSend >= SEND_INTERVAL then
		lastSend = now
		ClientState.request("EatForage", batch)
		batch = {}
	end
end

local function onEaten(index: number, backAt: number, eaterUserId: number)
	local food = foods[index]
	if food == nil then
		return
	end
	food.backAt = backAt
	food.pendingUntil = 0
	if eaterUserId ~= Players.LocalPlayer.UserId and food.suckFrom == nil then
		setHidden(food, true)
	end
end

function ForageController.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local eaten = remotes:WaitForChild("ForageEaten") :: RemoteEvent
	eaten.OnClientEvent:Connect(onEaten)
	local getForage = remotes:WaitForChild("GetForage") :: RemoteFunction
	local ok, data = pcall(function()
		return getForage:InvokeServer()
	end)
	if not ok or typeof(data) ~= "table" then
		warn("[ForageController] couldn't load the forage spots")
		return
	end
	build(data.positions or {}, data.kinds or {})
	for key, backAt in data.eaten or {} do
		local index = tonumber(key)
		if index and typeof(backAt) == "number" then
			onEaten(index, backAt, 0)
		end
	end
	RunService.RenderStepped:Connect(step)
end

return ForageController
