--!strict
-- Bioluminescent plankton in the deepest water (owner, 2026-10-08: "deepest depths
-- should have light luminescense such as photoplankton etc to give very very faint
-- light"). Below the shelf the water fills with faint blue-green specks that
-- twinkle around the camera, thickest in the Trench; any fish swimming through
-- them leaves a brief sparkling wake, the way real plankton flashes when it's
-- disturbed; and the pitch dark gets a very faint teal lift
-- (OceanController.setGlow). The deep floor's glowing mats are WorldService's.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Size = require(ReplicatedStorage.Shared.Size)
local OceanController = require(script.Parent.OceanController)
local SwimController = require(script.Parent.SwimController)

local World = Config.World

-- How much glow at a height: none on the shelf, a hint at the drop-off's foot,
-- most of it on the deep floor, all of it at the bottom of the Trench
local START_Y = World.deep.floorY + 110
local FLOOR_SHARE = 0.55
local CLOUD_RATE = 70 -- specks a second around the camera at full glow
local WAKE_RANGE = 260 -- fish further from the camera than this leave no wake
local TEAL = Color3.fromRGB(90, 255, 214)
local BLUE = Color3.fromRGB(86, 168, 255)

type Wake = { player: Player, root: BasePart, emitter: ParticleEmitter, length: number }

local PlanktonController = {}

local cloud: Part
local specks: { ParticleEmitter } = {}
local wakes: { [Model]: Wake } = {}
local glow = 0

-- 0 above the drop-off's foot .. 1 at the bottom of the Trench
function PlanktonController.glowAt(y: number): number
	if y >= START_Y then
		return 0
	end
	local floor = World.deep.floorY
	if y >= floor then
		return FLOOR_SHARE * (START_Y - y) / (START_Y - floor)
	end
	local t = math.clamp((floor - y) / (floor - World.trench.floorY), 0, 1)
	return FLOOR_SHARE + (1 - FLOOR_SHARE) * t
end

local function speckEmitter(color: Color3, size: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Rate = 0
	e.Lifetime = NumberRange.new(4, 8)
	e.Speed = NumberRange.new(0.05, 0.35)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 0.5
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.15, size),
		NumberSequenceKeypoint.new(0.85, size * 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	-- A slow twinkle: each speck brightens and dims twice in its life
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.25),
		NumberSequenceKeypoint.new(0.4, 0.75),
		NumberSequenceKeypoint.new(0.6, 0.3),
		NumberSequenceKeypoint.new(0.8, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.LightEmission = 1
	e.LightInfluence = 0 -- it makes its own light
	e.Color = ColorSequence.new(color)
	e.LockedToPart = false
	e.Parent = cloud
	return e
end

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
	local attachment = Instance.new("Attachment")
	attachment.Name = "PlanktonWake"
	attachment.Parent = root
	local e = Instance.new("ParticleEmitter")
	e.Name = "Wake"
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.7, 1.6)
	e.Speed = NumberRange.new(length * 0.05, length * 0.4) -- spread over the body
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3
	local size = math.clamp(length * 0.025, 0.06, 0.5)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 1.4),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Color = ColorSequence.new(Color3.fromRGB(170, 255, 240), TEAL)
	e.LockedToPart = false -- the sparks stay in the water behind the fish
	e.Parent = attachment
	wakes[character] = { player = player, root = root, emitter = e, length = length }
end

local function forget(character: Model)
	local wake = wakes[character]
	if wake then
		wakes[character] = nil
		local attachment = wake.emitter.Parent
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

local function step(dt: number)
	local camera = workspace.CurrentCamera
	local position = camera.CFrame.Position
	-- Ease in and out, so the glow never pops on crossing a depth
	local target = PlanktonController.glowAt(position.Y)
	glow += (target - glow) * math.min(dt * 1.5, 1)
	cloud.CFrame = CFrame.new(position)
	specks[1].Rate = CLOUD_RATE * 0.65 * glow
	specks[2].Rate = CLOUD_RATE * 0.35 * glow
	OceanController.setGlow(glow)

	for character, wake in wakes do
		if wake.root.Parent == nil or character.Parent == nil then
			forget(character)
			continue
		end
		local length = lengthOf(character)
		if math.abs(length - wake.length) > wake.length * 0.2 then
			forget(character)
			task.spawn(attach, wake.player, character)
			continue
		end
		local at = wake.root.Position
		local here = PlanktonController.glowAt(at.Y)
		if here <= 0.01 or (at - position).Magnitude > WAKE_RANGE then
			wake.emitter.Rate = 0
			continue
		end
		local speed = if wake.player == Players.LocalPlayer
			then SwimController.velocity.Magnitude
			else wake.root.AssemblyLinearVelocity.Magnitude
		local relative = math.clamp(speed / math.max(Size.topSpeed(length), 1), 0, 1.6)
		wake.emitter.Rate = here * relative * relative * (12 + length * 3)
	end
end

function PlanktonController.start()
	cloud = Instance.new("Part")
	cloud.Name = "Plankton"
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CanQuery = false
	cloud.CanTouch = false
	cloud.Transparency = 1
	-- Close round the camera: the thick deep water hides anything further off
	cloud.Size = Vector3.new(70, 40, 70)
	cloud.Parent = workspace.CurrentCamera
	specks = { speckEmitter(TEAL, 0.09), speckEmitter(BLUE, 0.13) }
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	RunService.RenderStepped:Connect(step)
end

return PlanktonController
