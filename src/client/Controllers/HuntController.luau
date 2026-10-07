--!strict
-- Hunting other players on this client: swallowing a small-enough fish the
-- moment it's in reach, the bite button (a lunge that bites whatever is in front
-- of the mouth), and the feedback for hits (jaw snaps, a camera jolt, bubbles).
-- The server checks every eat and bite (HuntService).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local CameraController = require(script.Parent.CameraController)
local PredatorController = require(script.Parent.PredatorController)
local FishAnimator = require(script.Parent.FishAnimator)
local SwimController = require(script.Parent.SwimController)

local hunt = Config.Tuning.hunt

local HuntController = {
	-- (damage) — we were bitten
	bitten = Signal.new(),
}

local lastEatTry: { [number]: number } = {}

local function lengthOf(character: Model): number
	local length = character:GetAttribute("Length")
	return if typeof(length) == "number" then length else 2
end

-- Whether a fish can't be eaten or bitten right now (in the hub or protected).
function HuntController.isSafe(character: Model): boolean
	if character:GetAttribute("InHub") == true then
		return true
	end
	local safeUntil = character:GetAttribute("SafeUntil")
	return typeof(safeUntil) == "number" and Timing.clock() < safeUntil
end

-- Other players' fish near our mouth: (player, character, root, gap) where gap is
-- how far their body is from our reach (<= 0 means in reach).
local function nearby(range: number): { { player: Player, character: Model, root: BasePart, gap: number } }
	local results = {}
	local root = SwimController.root()
	if root == nil then
		return results
	end
	local length = SwimController.length()
	local mouth = root.CFrame:PointToWorldSpace(Size.mouthOffset(length))
	for _, player in Players:GetPlayers() do
		if player == Players.LocalPlayer then
			continue
		end
		local character = player.Character
		local otherRoot = character and character:FindFirstChild("HumanoidRootPart")
		if character and otherRoot and otherRoot:IsA("BasePart") then
			local gap = (otherRoot.Position - mouth).Magnitude
				- Size.reach(length)
				- lengthOf(character) * 0.4
			if gap <= range then
				table.insert(results, { player = player, character = character, root = otherRoot, gap = gap })
			end
		end
	end
	table.sort(results, function(a, b)
		return a.gap < b.gap
	end)
	return results
end

local function selfSafe(): boolean
	local character = SwimController.character()
	return character == nil or HuntController.isSafe(character)
end

-- Swallow any small-enough fish that's in reach.
local function autoEat()
	if selfSafe() then
		return
	end
	local length = SwimController.length()
	local now = os.clock()
	for _, entry in nearby(0) do
		local userId = entry.player.UserId
		if
			Size.canSwallow(length, lengthOf(entry.character))
			and not HuntController.isSafe(entry.character)
			and now - (lastEatTry[userId] or 0) > 0.25
		then
			lastEatTry[userId] = now
			local character = SwimController.character()
			if character then
				FishAnimator.snap(character)
			end
			ClientState.request("EatPlayer", userId)
		end
	end
end

local function onBite()
	if not SwimController.lunge() then
		return
	end
	if selfSafe() then
		return
	end
	local length = SwimController.length()
	-- The lunge carries us forward, so look a little ahead of the mouth
	for _, entry in nearby(length * 0.6 + 2) do
		if not HuntController.isSafe(entry.character) then
			if Size.canSwallow(length, lengthOf(entry.character)) then
				ClientState.request("EatPlayer", entry.player.UserId)
			else
				ClientState.request("Bite", entry.player.UserId)
			end
			return
		end
	end
	-- No fish in reach: a predator or boss, maybe
	local root = SwimController.root()
	if root then
		local mouth = root.CFrame:PointToWorldSpace(Size.mouthOffset(length))
		local index = PredatorController.nearest(mouth, Size.reach(length) + length * 0.6 + 2)
		if index then
			ClientState.request("BitePredator", index)
		end
	end
end

local function bubbleBurst(position: Vector3, size: number)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Speed = NumberRange.new(size * 1.5, size * 4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, size * 2, 0)
	emitter.Drag = 3
	emitter.Size = NumberSequence.new(size * 0.12, size * 0.04)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.LightEmission = 0.5
	emitter.Color = ColorSequence.new(Color3.fromRGB(220, 250, 255))
	emitter.Parent = holder
	holder.Parent = workspace
	emitter:Emit(math.clamp(math.floor(size * 6), 8, 60))
	task.delay(2, function()
		holder:Destroy()
	end)
end

-- Every bite and swallow in the server, for effects.
local function onHit(attackerId: number, victimId: number, damage: number)
	local attacker = Players:GetPlayerByUserId(attackerId)
	local victim = Players:GetPlayerByUserId(victimId)
	local attackerCharacter = attacker and attacker.Character
	local victimCharacter = victim and victim.Character
	if attackerCharacter and attacker ~= Players.LocalPlayer then
		FishAnimator.snap(attackerCharacter)
	end
	local victimRoot = victimCharacter and victimCharacter:FindFirstChild("HumanoidRootPart")
	if victimCharacter and victimRoot and victimRoot:IsA("BasePart") then
		local size = lengthOf(victimCharacter)
		bubbleBurst(victimRoot.Position, if damage < 0 then size * 1.6 else size * 0.6)
	end
	if victim == Players.LocalPlayer then
		CameraController.kick(if damage < 0 then 1 else math.clamp(damage / hunt.biteDamage, 0.2, 0.8))
		if damage > 0 then
			HuntController.bitten:fire(damage)
		end
	elseif attacker == Players.LocalPlayer then
		CameraController.kick(0.25)
	end
end

function HuntController.start()
	Input.bite:connect(onBite)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local hit = remotes:WaitForChild("Hit") :: RemoteEvent
	hit.OnClientEvent:Connect(onHit)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.05 then
			accumulator = 0
			autoEat()
		end
	end)
end

return HuntController
