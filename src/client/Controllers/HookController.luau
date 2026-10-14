--!strict
-- Baited hooks on this client (Config/Hooks, HookService): the fishing boats' dark
-- hulls against the surface, their lines and the bait on each hook. Swimming into
-- the bait swallows it (no button, like any small fish) and hooks you: the line
-- reels your fish up toward the boat while a panel says to mash BITE or DASH. A
-- podmate's BITE close to you cuts the line.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local HuntController = require(script.Parent.HuntController)
local SwimController = require(script.Parent.SwimController)

local tune = Config.Hooks
local World = Config.World

local HookController = {}

local HULL = Color3.fromRGB(26, 32, 40)
local LINE = Color3.fromRGB(214, 226, 232)
local BAIT = Color3.fromRGB(180, 196, 206)

type HookState = { id: number, position: Vector3, taken: number, hookedAt: number }
type Drawn = {
	model: Model,
	hull: BasePart,
	pieces: { { part: BasePart, offset: CFrame } }, -- the hull's pieces, in the hull's frame
	from: Vector3,
	to: Vector3,
	yaw: number,
	movedAt: number,
	hook: HookState?,
	hookPart: BasePart,
	bait: BasePart,
	beam: Beam,
	top: Attachment,
	bottom: Attachment,
	tag: BillboardGui,
}

local drawn: { [number]: Drawn } = {}
local folder: Folder
local panel: Frame
local panelText: TextLabel
local panelFill: Frame
local lastTry = 0

local function part(parent: Instance, name: string, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.Color = color
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- A boat seen from below: a dark hull, a keel and a little cabin, its line, the
-- hook and a silver bait fish
local function build(index: number): Drawn
	local model = Instance.new("Model")
	model.Name = `Boat{index}`
	local hull = part(model, "Hull", Vector3.new(26, 4, 9), HULL)
	model.PrimaryPart = hull
	local pieces: { { part: BasePart, offset: CFrame } } = {
		{ part = part(model, "Keel", Vector3.new(22, 2.4, 3), HULL), offset = CFrame.new(0, -2.6, 0) },
		{
			part = part(model, "Bow", Vector3.new(7, 4, 6.4), HULL),
			offset = CFrame.new(14.5, 0, 0) * CFrame.Angles(0, math.rad(45), 0),
		},
		{
			part = part(model, "Cabin", Vector3.new(8, 5, 6), Color3.fromRGB(40, 46, 56)),
			offset = CFrame.new(-3, 4, 0),
		},
	}
	local top = Instance.new("Attachment")
	top.Name = "LineTop"
	top.Parent = hull
	top.Position = Vector3.new(-11, -1.5, 0)
	local hookPart = part(model, "Hook", Vector3.new(0.25, 1.6, 0.25), Color3.fromRGB(160, 170, 180))
	hookPart.Material = Enum.Material.Metal
	local bait = part(model, "Bait", Vector3.new(1.6, 0.55, 0.4), BAIT)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = bait
	local bottom = Instance.new("Attachment")
	bottom.Name = "LineBottom"
	bottom.Parent = hookPart
	bottom.Position = Vector3.new(0, 0.8, 0)
	local beam = Instance.new("Beam")
	beam.Attachment0 = top
	beam.Attachment1 = bottom
	beam.Width0 = 0.12
	beam.Width1 = 0.12
	beam.Color = ColorSequence.new(LINE)
	beam.Transparency = NumberSequence.new(0.2)
	beam.LightEmission = 0.3
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Parent = hull
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Size = UDim2.fromOffset(150, 22)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	tag.MaxDistance = 70
	tag.LightInfluence = 0
	tag.Adornee = bait
	local text = Ui.label(
		tag,
		"Text",
		"BAIT · it's on a hook",
		Ui.FONT_BOLD,
		14,
		Ui.color.haul,
		UDim2.fromScale(1, 1)
	)
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.TextStrokeTransparency = 0.5
	tag.Parent = bait
	model.Parent = folder
	return {
		model = model,
		hull = hull,
		pieces = pieces,
		from = Vector3.zero,
		to = Vector3.zero,
		yaw = 0,
		movedAt = 0,
		hook = nil,
		hookPart = hookPart,
		bait = bait,
		beam = beam,
		top = top,
		bottom = bottom,
		tag = tag,
	}
end

local function onHooks(data: { [string]: any })
	if typeof(data) ~= "table" or typeof(data.boats) ~= "table" then
		return
	end
	local now = os.clock()
	for _, entry in data.boats do
		local d = drawn[entry.i]
		local at = Vector3.new(entry.x, World.surfaceY - 2, entry.z)
		if d == nil then
			d = build(entry.i)
			drawn[entry.i] = d
			d.from = at
		else
			d.from = d.hull.Position
		end
		d.to = at
		d.yaw = entry.yaw
		d.movedAt = now
		local hook = entry.hook
		d.hook = if typeof(hook) == "table"
			then {
				id = hook.id,
				position = Vector3.new(hook.x, hook.y, hook.z),
				taken = hook.taken,
				hookedAt = hook.hookedAt,
			}
			else nil
	end
end

-- Where a hook is now: hanging still, or reeling its fish up
local function hookPoint(hook: HookState, now: number): Vector3
	if hook.taken == 0 then
		return hook.position + Vector3.new(0, math.sin(now * 1.3 + hook.id) * 0.4, 0)
	end
	local up = math.max(0, now - hook.hookedAt) * tune.reel
	return Vector3.new(hook.position.X, math.min(hook.position.Y + up, World.surfaceY - 8), hook.position.Z)
end

local function step()
	local now = Timing.clock()
	local clock = os.clock()
	local me = Players.LocalPlayer
	local character = SwimController.character()
	local root = SwimController.root()
	local length = SwimController.length()
	local mouth = if root then root.CFrame:PointToWorldSpace(Size.mouthOffset(length)) else nil
	local hookedId = if character then character:GetAttribute("HookedBy") else nil
	local inHub = character ~= nil and character:GetAttribute("InHub") == true
	local holding: Vector3? = nil
	for _, d in drawn do
		local alpha = math.clamp((clock - d.movedAt) / 1, 0, 1)
		local at = d.from:Lerp(d.to, alpha)
		d.hull.CFrame = CFrame.new(at)
			* CFrame.Angles(0, d.yaw, 0)
			* CFrame.Angles(math.sin(clock * 0.8 + d.yaw) * 0.03, 0, 0)
		for _, piece in d.pieces do
			piece.part.CFrame = d.hull.CFrame * piece.offset
		end
		local hook = d.hook
		local show = hook ~= nil
		d.beam.Enabled = show
		d.hookPart.Transparency = if show then 0 else 1
		d.bait.Transparency = if show and hook and hook.taken == 0 then 0 else 1
		d.tag.Enabled = show and hook ~= nil and hook.taken == 0
		if hook then
			local point = hookPoint(hook, now)
			d.hookPart.CFrame = CFrame.new(point)
			d.bait.CFrame = CFrame.new(point - Vector3.new(0, 0.9, 0))
				* CFrame.Angles(0, now * 0.6 + hook.id, 0)
			if hook.taken == me.UserId or hook.id == hookedId then
				holding = point
			end
			-- Swallowing the bait (and getting hooked)
			if
				hook.taken == 0
				and mouth
				and not inHub
				and hookedId == nil
				and os.clock() - lastTry > 0.5
				and (d.bait.Position - mouth).Magnitude <= Size.reach(length) + 1.5
			then
				lastTry = os.clock()
				ClientState.request("TakeBait", hook.id)
			end
		end
	end
	-- Hooked: dragged up the line, mashing to get free
	if typeof(hookedId) == "number" and holding then
		SwimController.holdBy("hook", holding)
		panel.Visible = true
		local progress = if character then character:GetAttribute("HookStruggle") else 0
		panelFill.Size = UDim2.fromScale(if typeof(progress) == "number" then progress else 0, 1)
		panelText.Text = `HOOKED! Mash {Input.biteKey()} or {Input.dashKey()} to break free`
	else
		SwimController.holdBy("hook", nil)
		panel.Visible = false
	end
end

-- A podmate hooked close by: our BITE cuts their line
local function onBite()
	local root = SwimController.root()
	if root == nil then
		return
	end
	for _, player in Players:GetPlayers() do
		if player == Players.LocalPlayer or not HuntController.podmate(player) then
			continue
		end
		local character = player.Character
		local other = character and character:FindFirstChild("HumanoidRootPart")
		if
			character
			and other
			and other:IsA("BasePart")
			and typeof(character:GetAttribute("HookedBy")) == "number"
			and (other.Position - root.Position).Magnitude <= tune.biteRange
		then
			ClientState.request("BiteLine", player.UserId)
			Sfx.play("Snap", { volume = 0.5 })
			return
		end
	end
end

function HookController.start()
	folder = Instance.new("Folder")
	folder.Name = "Boats"
	folder.Parent = workspace
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Ui.screen("Hooks", playerGui, 7)
	panel = Ui.panel(gui, "Hooked", UDim2.fromOffset(440, 58), UDim2.new(0.5, 0, 0.7, 0), Vector2.new(0.5, 0))
	if Input.isTouch() then
		-- Phones: up where the pressure meter sits; at 0.7 it covered the top of
		-- the HAUL card and the ITEMS button (PC playtest 2026-10-14, X2)
		panel.Position = UDim2.new(0.5, 0, 0.62, 0)
	end
	panel.Visible = false
	panelText = Ui.label(
		panel,
		"Text",
		"",
		Ui.FONT_HEAVY,
		15,
		Ui.color.danger,
		UDim2.new(1, -20, 0, 20),
		UDim2.fromOffset(10, 6)
	)
	panelText.TextXAlignment = Enum.TextXAlignment.Center
	local _, fill =
		Ui.bar(panel, "Struggle", UDim2.new(1, -20, 0, 10), UDim2.fromOffset(10, 36), Ui.color.safe)
	panelFill = fill
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local event = remotes:WaitForChild("Hooks") :: RemoteEvent
	event.OnClientEvent:Connect(onHooks)
	Input.bite:connect(onBite)
	RunService.RenderStepped:Connect(step)
end

return HookController
