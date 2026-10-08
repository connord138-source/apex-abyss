--!strict
-- Bubbles from every fish's mouth as it swims (owner, 2026-10-08: the water needed
-- something moving in it): a stream whose rate follows the fish's speed, fixed to
-- its mouth. Your own fish uses SwimController's velocity; other fish use the
-- velocity their root replicates. Bursts (bites, dashes) are Bubbles.burst.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Size = require(ReplicatedStorage.Shared.Size)
local Bubbles = require(script.Parent.Parent.Bubbles)
local SwimController = require(script.Parent.SwimController)

type Entry = { player: Player, root: BasePart, emitter: ParticleEmitter, length: number }

local BubbleController = {}

local entries: { [Model]: Entry } = {}

local function lengthOf(character: Model): number
	local length = character:GetAttribute("Length")
	return if typeof(length) == "number" then length else 2
end

local function attach(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 8)
	if root == nil or not root:IsA("BasePart") or character.Parent == nil then
		return
	end
	local length = lengthOf(character)
	local emitter = Bubbles.stream(root, Size.mouthOffset(length) + Vector3.new(0, length * 0.06, 0), length)
	entries[character] = { player = player, root = root, emitter = emitter, length = length }
end

local function forget(character: Model)
	local entry = entries[character]
	if entry then
		entries[character] = nil
		local attachment = entry.emitter.Parent
		if attachment then
			attachment:Destroy()
		end
	end
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(attach, player, character)
	end)
	player.CharacterRemoving:Connect(forget)
	if player.Character then
		task.spawn(attach, player, player.Character)
	end
end

local function step()
	for character, entry in entries do
		if entry.root.Parent == nil or character.Parent == nil then
			forget(character)
			continue
		end
		-- A fish that grew gets a new stream sized to it
		local length = lengthOf(character)
		if math.abs(length - entry.length) > entry.length * 0.2 then
			forget(character)
			task.spawn(attach, entry.player, character)
			continue
		end
		local speed = if entry.player == Players.LocalPlayer
			then SwimController.velocity.Magnitude
			else entry.root.AssemblyLinearVelocity.Magnitude
		local relative = math.clamp(speed / math.max(Size.topSpeed(length), 1), 0, 1.6)
		entry.emitter.Rate = 0.6 + relative * relative * 7
	end
end

function BubbleController.start()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	RunService.Heartbeat:Connect(step)
end

return BubbleController
