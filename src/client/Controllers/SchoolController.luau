--!strict
-- Draws the NPC prey and eats them. Every fish follows its shared path
-- (Shared/Schools.luau), so this client moves its own copies each frame with
-- BulkMoveTo and nothing is sent over the network but eats.
--
-- Eating feels instant: when a small-enough fish is in reach of our mouth it's
-- sucked in on this client straight away, and the eat goes to the server in a
-- small batch. If the server doesn't confirm it within a moment, the fish comes
-- back. Fish other players ate vanish with a puff and return when they respawn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Schools = require(ReplicatedStorage.Shared.Schools)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local ClientState = require(script.Parent.Parent.ClientState)
local SwimController = require(script.Parent.SwimController)

local SchoolController = {
	-- (preyId, mass, position) — we ate a prey fish (HUD pops a number)
	ate = Signal.new(),
}

local DRAW_DISTANCE = 520 -- schools further than this from the camera aren't moved
-- Batch 1's prey GLBs come out of Studio's importer nose on +Z, not the -Z they were
-- exported for, so the schools swam tail first (playtest 2026-10-07); a mesh is
-- turned round. Drop this if a re-exported bundle imports nose on -Z.
local MESH_TURN = CFrame.Angles(0, math.pi, 0)
local SUCK_SECONDS = 0.14
local CONFIRM_SECONDS = 1.2
local SEND_INTERVAL = 0.06

type Visual = {
	body: BasePart,
	tail: BasePart?, -- the part body's tail fin (a mesh body has none)
	bodySize: Vector3,
	tailSize: Vector3,
	hidden: boolean,
	backAt: number, -- clock when it shows again (0 = shown)
	pendingUntil: number, -- our unconfirmed eat
	suckFrom: CFrame?, -- the suction animation's start
	suckStart: number,
	fadeIn: number, -- 0..1 after respawning
}

local visuals: { Visual } = {}
local parts: { BasePart } = {}
local frames: { CFrame } = {}
local batch: { { number } } = {}
local lastSend = 0

local function makePart(parent: Instance, color: Color3, shape: "Ellipsoid" | "Fin"): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.Parent = parent
	if shape == "Fin" then
		part.Reflectance = 0.05
	end
	return part
end

-- The imported prey mesh (docs/ASSETS.md): ReplicatedStorage.PreyModels.<PreyId>,
-- a MeshPart facing -Z. Nil while it isn't imported (the ellipsoid is drawn).
local function preyTemplate(preyId: string): MeshPart?
	local folder = ReplicatedStorage:FindFirstChild("PreyModels")
	local template = folder and folder:FindFirstChild(preyId)
	if template and template:IsA("MeshPart") then
		return template
	end
	if template and template:IsA("Model") then
		local mesh = template:FindFirstChildWhichIsA("MeshPart", true)
		return mesh
	end
	return nil
end

local function build()
	local folder = Instance.new("Folder")
	folder.Name = "Prey"
	for index, fish in Schools.fish do
		local prey = Config.Prey.byId[fish.prey]
		local length = fish.length
		local bodySize = Vector3.new(length * prey.slim * 0.8, length * prey.slim, length * 0.78)
		local tailSize = Vector3.new(length * 0.03, length * prey.slim * 1.1, length * 0.26)
		local template = preyTemplate(prey.id)
		local body: BasePart
		local tail: BasePart? = nil
		if template then
			local mesh = template:Clone()
			mesh.Anchored = true
			mesh.CanCollide = false
			mesh.CanQuery = false
			mesh.CanTouch = false
			mesh.CastShadow = false
			bodySize = template.Size * (length / math.max(template.Size.Z, 0.01))
			mesh.Size = bodySize
			mesh.Parent = folder
			body = mesh
		else
			body = makePart(folder, prey.back, "Ellipsoid")
			body.Size = bodySize
			local fin = makePart(folder, prey.back:Lerp(prey.belly, 0.3), "Fin")
			fin.Name = "Tail"
			fin.Size = tailSize
			tail = fin
		end
		body.Name = prey.id
		visuals[index] = {
			body = body,
			tail = tail,
			bodySize = bodySize,
			tailSize = tailSize,
			hidden = false,
			backAt = 0,
			pendingUntil = 0,
			suckFrom = nil,
			suckStart = 0,
			fadeIn = 1,
		}
	end
	folder.Parent = workspace
end

local function setHidden(visual: Visual, hidden: boolean)
	if visual.hidden == hidden then
		return
	end
	visual.hidden = hidden
	local transparency = if hidden then 1 else 0
	visual.body.Transparency = transparency
	if visual.tail then
		visual.tail.Transparency = transparency
	end
	if not hidden then
		visual.body.Size = visual.bodySize
		if visual.tail then
			visual.tail.Size = visual.tailSize
		end
		visual.fadeIn = 0
	end
end

local function flush(now: number)
	if #batch == 0 or now - lastSend < SEND_INTERVAL then
		return
	end
	lastSend = now
	ClientState.request("EatPrey", batch)
	batch = {}
end

local function step(dt: number)
	local now = Timing.clock()
	local camera = workspace.CurrentCamera.CFrame.Position
	local root = SwimController.root()
	local length = SwimController.length()
	local mouth: Vector3? = nil
	local reach = Size.reach(length)
	local inHub = false
	if root then
		mouth = root.CFrame:PointToWorldSpace(Size.mouthOffset(length))
		local character = SwimController.character()
		inHub = character ~= nil and character:GetAttribute("InHub") == true
	end

	table.clear(parts)
	table.clear(frames)
	for schoolIndex, school in Schools.list do
		if (school.center - camera).Magnitude > DRAW_DISTANCE + school.radius then
			continue
		end
		local schoolFrame = Schools.schoolFrame(schoolIndex, now)
		for index = school.first, school.first + school.count - 1 do
			local fish = Schools.fish[index]
			local visual = visuals[index]
			-- Respawned, or our eat wasn't confirmed: show it again
			if visual.hidden and visual.suckFrom == nil then
				if visual.pendingUntil > 0 and now > visual.pendingUntil then
					visual.pendingUntil = 0
					visual.backAt = 0
				end
				if visual.pendingUntil == 0 and now >= visual.backAt then
					setHidden(visual, false)
				end
			end
			local frame = Schools.fishFrame(index, schoolFrame, now)
			if visual.suckFrom then
				-- Sucked into our mouth: slide in and shrink, then vanish
				local alpha = math.clamp((now - visual.suckStart) / SUCK_SECONDS, 0, 1)
				local target = mouth or frame.Position
				local from = visual.suckFrom :: CFrame
				frame = CFrame.new(from.Position:Lerp(target, alpha * alpha)) * from.Rotation
				local shrink = 1 - alpha * 0.85
				visual.body.Size = visual.bodySize * shrink
				if visual.tail then
					visual.tail.Size = visual.tailSize * shrink
				end
				if alpha >= 1 then
					visual.suckFrom = nil
					setHidden(visual, true)
				end
			elseif not visual.hidden then
				if visual.fadeIn < 1 then
					visual.fadeIn = math.min(1, visual.fadeIn + dt * 2.5)
					local grow = 0.3 + 0.7 * visual.fadeIn
					visual.body.Size = visual.bodySize * grow
					if visual.tail then
						visual.tail.Size = visual.tailSize * grow
					end
				end
				-- Eat it if it's in reach and small enough
				if
					mouth
					and not inHub
					and Size.canSwallow(length, fish.length)
					and (frame.Position - mouth).Magnitude <= reach + fish.radius
				then
					visual.suckFrom = frame
					visual.suckStart = now
					visual.pendingUntil = now + CONFIRM_SECONDS
					visual.backAt = math.huge
					table.insert(batch, { index, now })
					local prey = Config.Prey.byId[fish.prey]
					SchoolController.ate:fire(prey.id, prey.mass, frame.Position)
				end
			end
			if not visual.hidden then
				local beat = math.sin(now * (6 + fish.phase) + fish.phase * 4) * 0.55
				table.insert(parts, visual.body)
				local tail = visual.tail
				if tail then
					table.insert(frames, frame)
					table.insert(parts, tail)
					table.insert(
						frames,
						frame
							* CFrame.new(0, 0, visual.body.Size.Z * 0.45)
							* CFrame.Angles(0, beat, 0)
							* CFrame.new(0, 0, tail.Size.Z * 0.4)
					)
				else
					-- A one-piece mesh: a small yaw wiggle about its head reads as swimming
					table.insert(
						frames,
						frame
							* CFrame.new(0, 0, -visual.body.Size.Z * 0.3)
							* CFrame.Angles(0, beat * 0.22, 0)
							* CFrame.new(0, 0, visual.body.Size.Z * 0.3)
							* MESH_TURN
					)
				end
			end
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	flush(now)
end

-- The server says a fish was eaten (by anyone) and when it comes back.
local function onPreyEaten(index: number, backAt: number, eaterUserId: number)
	local visual = visuals[index]
	if visual == nil then
		return
	end
	visual.backAt = backAt
	visual.pendingUntil = 0
	if eaterUserId ~= Players.LocalPlayer.UserId and visual.suckFrom == nil then
		setHidden(visual, true)
	end
end

function SchoolController.start()
	build()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local preyEaten = remotes:WaitForChild("PreyEaten") :: RemoteEvent
	preyEaten.OnClientEvent:Connect(onPreyEaten)
	-- Fish already eaten when we joined
	local getEaten = remotes:WaitForChild("GetEaten") :: RemoteFunction
	task.spawn(function()
		local ok, eaten = pcall(function()
			return getEaten:InvokeServer()
		end)
		if ok and typeof(eaten) == "table" then
			for key, backAt in eaten do
				local index = tonumber(key)
				if index and typeof(backAt) == "number" then
					onPreyEaten(index, backAt, 0)
				end
			end
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return SchoolController
