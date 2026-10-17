--!strict
-- Boost trails (Config/Trails; owner, 2026-10-17: "boost effects, such as bubbles,
-- rainbow, glitter, fire, etc as an earnable customization"): what streams off each
-- fish's tail, from its character's `Trail` attribute. Faint while a fish swims
-- fast, full on a dash (over its top speed). Your own fish reads SwimController's
-- velocity; other fish the velocity their root replicates. Particles are left in
-- the water where they're shed, so they hang behind the fish as it swims.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Fx = require(ReplicatedStorage.Shared.Fx)
local Size = require(ReplicatedStorage.Shared.Size)
local SwimController = require(script.Parent.SwimController)

type Entry = {
	player: Player,
	root: BasePart,
	id: string,
	length: number,
	holder: Attachment, -- at the tail
	emitters: { ParticleEmitter },
	ribbon: Trail?,
	flicker: boolean, -- a storm's ribbon crackles
}

local TrailController = {}

local entries: { [Model]: Entry } = {}
local FAR = 320 -- studs from the camera past which nothing is shed

local function lengthOf(character: Model): number
	local length = character:GetAttribute("Length")
	return if typeof(length) == "number" then length else 2
end

local function forget(character: Model)
	local entry = entries[character]
	if entry then
		entries[character] = nil
		entry.holder:Destroy()
	end
end

local function build(player: Player, character: Model)
	forget(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local id = character:GetAttribute("Trail")
	if root == nil or not root:IsA("BasePart") or typeof(id) ~= "string" then
		return
	end
	local trail = Config.Trails.byId[id]
	if trail == nil then
		return
	end
	local L = lengthOf(character)
	-- The tail: behind the root (a fish faces -Z)
	local holder = Instance.new("Attachment")
	holder.Name = "BoostTrail"
	holder.Position = Vector3.new(0, 0, L * 0.42)
	holder.Parent = root
	local c, c2 = trail.color, trail.color2
	local emitters: { ParticleEmitter } = {}
	local function emit(preset: Fx.Preset, rate: number, color: ColorSequence?)
		local e = Fx.emitter(holder, preset, L, c, c2, rate)
		if color then
			e.Color = color
		end
		e.Enabled = false
		table.insert(emitters, e)
	end
	local ribbon: Trail? = nil
	local function band(width: number, lifetime: number, color: ColorSequence)
		local a0 = Instance.new("Attachment")
		a0.Name = "BoostTrail0"
		a0.Position = Vector3.new(0, width * L * 0.5, 0)
		a0.Parent = holder
		local a1 = Instance.new("Attachment")
		a1.Name = "BoostTrail1"
		a1.Position = Vector3.new(0, -width * L * 0.5, 0)
		a1.Parent = holder
		local made = Fx.ribbon(holder, a0, a1, lifetime, color, Fx.keys({ 0, 0.2, 0.6, 0.55, 1, 1 }))
		made.Enabled = false
		ribbon = made
	end
	local style = trail.style
	if style == "bubbles" then
		emit("bubbles", 4)
	elseif style == "glitter" then
		emit("glints", 3)
		emit("gold", 1.2)
	elseif style == "flame" then
		emit("flame", 1)
		emit("embers", 1)
	elseif style == "rainbow" then
		band(0.22, 0.65, Fx.rainbow(0.7))
		emit("stardust", 1.5, Fx.rainbow(0.6))
	elseif style == "storm" then
		band(0.1, 0.35, ColorSequence.new(c2, c))
		emit("sparks", 2.5)
	elseif style == "stardust" then
		emit("stardust", 2)
		emit("nebula", 1.2)
	elseif style == "frost" then
		band(0.14, 0.5, ColorSequence.new(c, c2))
		emit("frost", 1.2)
		emit("crystal", 1)
	elseif style == "ink" then
		emit("ink", 1.6)
	end
	entries[character] = {
		player = player,
		root = root,
		id = id,
		length = L,
		holder = holder,
		emitters = emitters,
		ribbon = ribbon,
		flicker = style == "storm",
	}
end

local function watch(player: Player)
	local function track(character: Model)
		task.spawn(function()
			character:WaitForChild("HumanoidRootPart", 8)
			if character.Parent then
				build(player, character)
			end
		end)
		character:GetAttributeChangedSignal("Trail"):Connect(function()
			build(player, character)
		end)
	end
	player.CharacterAdded:Connect(track)
	player.CharacterRemoving:Connect(forget)
	if player.Character then
		track(player.Character)
	end
end

local function step()
	local camera = Workspace.CurrentCamera
	for character, entry in entries do
		if entry.root.Parent == nil or character.Parent == nil then
			forget(character)
			continue
		end
		-- A fish that grew gets a trail sized to it
		local length = lengthOf(character)
		if math.abs(length - entry.length) > entry.length * 0.2 then
			build(entry.player, character)
			continue
		end
		local speed = if entry.player == Players.LocalPlayer
			then SwimController.velocity.Magnitude
			else entry.root.AssemblyLinearVelocity.Magnitude
		local relative = speed / math.max(Size.topSpeed(length), 1)
		-- Faint from 60% of top speed, full on a dash (past top speed)
		local k = math.clamp((relative - 0.6) / 0.6, 0, 1)
		local near = camera == nil or (camera.CFrame.Position - entry.root.Position).Magnitude < FAR
		local on = k > 0.02 and near
		for _, e in entry.emitters do
			e.Enabled = on
			if on then
				local base = e:GetAttribute("Rate")
				e.Rate = (if typeof(base) == "number" then base else 6) * (0.25 + 0.75 * k)
			end
		end
		local ribbon = entry.ribbon
		if ribbon then
			ribbon.Enabled = on
			if on and entry.flicker then
				ribbon.Transparency = Fx.keys({ 0, if math.random() < 0.3 then 0.7 else 0.1, 1, 1 })
			end
		end
	end
end

function TrailController.start()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	RunService.Heartbeat:Connect(step)
end

return TrailController
