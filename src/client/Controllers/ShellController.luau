--!strict
-- Shells on this client: draws every spot (gently bobbing and turning, with a
-- glint so they catch the eye), picks them up the moment they're in reach (they
-- zip into the mouth), and tells the server. Each player has their own shells; a
-- picked one comes back for you when the server says.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local ClientState = require(script.Parent.Parent.ClientState)
local SwimController = require(script.Parent.SwimController)

local Shells = Config.Shells

local ShellController = {
	-- (value, position) — we picked one up (the HUD pops a number)
	collected = Signal.new(),
}

local DRAW_DISTANCE = 160 -- shells further away hold still
local GLINT_DISTANCE = 140
local SUCK_SECONDS = 0.16
local CONFIRM_SECONDS = 2

type Shell = {
	index: number,
	position: Vector3,
	golden: boolean,
	body: Part,
	tip: Part,
	glint: ParticleEmitter,
	bodySize: Vector3,
	tipSize: Vector3,
	hidden: boolean,
	backAt: number,
	pendingUntil: number,
	suckFrom: Vector3?,
	suckStart: number,
	phase: number,
}

local shells: { Shell } = {}
local queue: { number } = {}
local lastSend = 0
local parts: { BasePart } = {}
local frames: { CFrame } = {}

local CREAM = Color3.fromRGB(242, 228, 204)
local CREAM_DARK = Color3.fromRGB(214, 184, 150)
local GOLD = Color3.fromRGB(255, 204, 84)
local GOLD_DARK = Color3.fromRGB(230, 164, 50)

local function shellPart(parent: Instance, name: string, color: Color3, golden: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Reflectance = if golden then 0.35 else 0.08
	part.Color = color
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.Parent = parent
	return part
end

local function build(positions: { Vector3 }, golden: { boolean })
	local folder = Instance.new("Folder")
	folder.Name = "Shells"
	for index, position in positions do
		local isGolden = golden[index] == true
		local scale = if isGolden then 1.35 else 1
		local body = shellPart(folder, "Shell", if isGolden then GOLD else CREAM, isGolden)
		local bodySize = Vector3.new(1.2, 0.8, 1.4) * scale
		body.Size = bodySize
		local tip = shellPart(folder, "Tip", if isGolden then GOLD_DARK else CREAM_DARK, isGolden)
		local tipSize = Vector3.new(0.55, 0.6, 0.7) * scale
		tip.Size = tipSize
		local glint = Instance.new("ParticleEmitter")
		glint.Rate = if isGolden then 4 else 1.5
		glint.Lifetime = NumberRange.new(0.5, 0.9)
		glint.Speed = NumberRange.new(0.3, 1)
		glint.SpreadAngle = Vector2.new(180, 180)
		glint.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.4, if isGolden then 0.5 else 0.32),
			NumberSequenceKeypoint.new(1, 0),
		})
		glint.LightEmission = 1
		glint.Color =
			ColorSequence.new(if isGolden then Color3.fromRGB(255, 230, 150) else Color3.new(1, 1, 1))
		glint.Enabled = false
		glint.Parent = body
		table.insert(shells, {
			index = index,
			position = position,
			golden = isGolden,
			body = body,
			tip = tip,
			glint = glint,
			bodySize = bodySize,
			tipSize = tipSize,
			hidden = false,
			backAt = 0,
			pendingUntil = 0,
			suckFrom = nil,
			suckStart = 0,
			phase = (index * 1.7) % (2 * math.pi),
		})
		body.CFrame = CFrame.new(position)
		tip.CFrame = CFrame.new(position)
	end
	folder.Parent = workspace
end

local function setHidden(shell: Shell, hidden: boolean)
	if shell.hidden == hidden then
		return
	end
	shell.hidden = hidden
	shell.body.Transparency = if hidden then 1 else 0
	shell.tip.Transparency = if hidden then 1 else 0
	if hidden then
		shell.glint.Enabled = false
	else
		shell.body.Size = shell.bodySize
		shell.tip.Size = shell.tipSize
	end
end

local function step(dt: number)
	local now = Timing.clock()
	local camera = workspace.CurrentCamera.CFrame.Position
	local root = SwimController.root()
	local length = SwimController.length()
	local state = ClientState.current
	local reach = Perks.shellReach(
		length,
		if state then state.upgrades else nil,
		if state then state.boosts else nil,
		workspace:GetServerTimeNow()
	)
	local mouth = if root then root.CFrame:PointToWorldSpace(Size.mouthOffset(length)) else nil
	table.clear(parts)
	table.clear(frames)
	for _, shell in shells do
		if shell.hidden and shell.suckFrom == nil then
			if shell.pendingUntil > 0 and now > shell.pendingUntil then
				shell.pendingUntil = 0
				shell.backAt = 0
			end
			if shell.pendingUntil == 0 and now >= shell.backAt then
				setHidden(shell, false)
			end
		end
		if shell.hidden then
			continue
		end
		local distance = (shell.position - camera).Magnitude
		if shell.suckFrom then
			local alpha = math.clamp((now - shell.suckStart) / SUCK_SECONDS, 0, 1)
			local target = mouth or shell.position
			local at = (shell.suckFrom :: Vector3):Lerp(target, alpha * alpha)
			shell.body.Size = shell.bodySize * (1 - alpha * 0.8)
			shell.tip.Size = shell.tipSize * (1 - alpha * 0.8)
			table.insert(parts, shell.body)
			table.insert(frames, CFrame.new(at))
			table.insert(parts, shell.tip)
			table.insert(frames, CFrame.new(at))
			if alpha >= 1 then
				shell.suckFrom = nil
				setHidden(shell, true)
			end
			continue
		end
		if mouth and (shell.position - mouth).Magnitude <= reach then
			shell.suckFrom = shell.position
			shell.suckStart = now
			shell.pendingUntil = now + CONFIRM_SECONDS
			shell.backAt = math.huge
			table.insert(queue, shell.index)
			ShellController.collected:fire(
				if shell.golden then Shells.goldenValue else Shells.value,
				shell.position
			)
			continue
		end
		shell.glint.Enabled = distance < GLINT_DISTANCE
		if distance < DRAW_DISTANCE then
			local t = now + shell.phase
			local frame = CFrame.new(shell.position + Vector3.new(0, math.sin(t * 1.8) * 0.25, 0))
				* CFrame.Angles(0.35, t * 0.6, 0.15)
			table.insert(parts, shell.body)
			table.insert(frames, frame)
			table.insert(parts, shell.tip)
			table.insert(frames, frame * CFrame.new(0, 0.25, 0.45) * CFrame.Angles(-0.4, 0, 0))
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- One pickup per request (the server rate-limits them)
	if #queue > 0 and now - lastSend >= 0.06 then
		lastSend = now
		ClientState.request("Collect", table.remove(queue, 1))
	end
end

local function onResult(index: number, backAt: number)
	local shell = shells[index]
	if shell == nil then
		return
	end
	shell.pendingUntil = 0
	shell.backAt = backAt
	if backAt == 0 and shell.suckFrom == nil then
		setHidden(shell, false)
	end
end

function ShellController.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local result = remotes:WaitForChild("ShellResult") :: RemoteEvent
	result.OnClientEvent:Connect(onResult)
	local getShells = remotes:WaitForChild("GetShells") :: RemoteFunction
	local ok, data = pcall(function()
		return getShells:InvokeServer()
	end)
	if not ok or typeof(data) ~= "table" then
		warn("[ShellController] couldn't load the shells")
		return
	end
	build(data.positions or {}, data.golden or {})
	for key, backAt in data.hidden or {} do
		local shell = shells[tonumber(key) or 0]
		if shell and typeof(backAt) == "number" then
			shell.backAt = backAt
			setHidden(shell, true)
		end
	end
	RunService.RenderStepped:Connect(step)
end

return ShellController
