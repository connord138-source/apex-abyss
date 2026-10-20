--!strict
-- Hunting other players on this client: the bite button (a lunge that bites
-- whatever is in front of the mouth) and the feedback for hits (jaw snaps, a camera
-- jolt, bubbles). No player is ever swallowed whole, however small (owner,
-- 2026-10-20: "bigger fish should never auto eat another player it needs to be a
-- fight"); a bigger fish only bites harder (Config/Pvp `fight`, by level). The
-- server checks every bite (HuntService).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Size = require(ReplicatedStorage.Shared.Size)
local Sfx = require(script.Parent.Parent.Sfx)
local Bubbles = require(script.Parent.Parent.Bubbles)
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
	-- (landed) — our own bite: false as the jaws snap, true when one lands on a fish
	-- or a creature (owner, 2026-10-20: "biting also needs a sound queue or something
	-- to let the player know they are biting"; HudController draws the jaws)
	snapped = Signal.new(),
}

local function lengthOf(character: Model): number
	local length = character:GetAttribute("Length")
	return if typeof(length) == "number" then length else 2
end

-- A fish's level, the one fights go by (HuntService's `FishLevel`: banked, so the
-- Haul aboard doesn't count; Config/Pvp `fight`)
function HuntController.levelOf(character: Model?): number
	local level = if character then character:GetAttribute("FishLevel") else nil
	return if typeof(level) == "number" then level else 1
end

-- How another fish stands against ours in a fight: "stronger", "weaker" or "even"
-- (Config/Pvp `fight` `edge` levels apart)
function HuntController.standing(character: Model): string
	local gap = HuntController.levelOf(character) - HuntController.levelOf(SwimController.character())
	local edge = Config.Pvp.fight.edge
	return if gap >= edge then "stronger" elseif gap <= -edge then "weaker" else "even"
end

-- Whether another player is in our pod (PodService's `Pod` attribute): podmates
-- can't eat or bite each other
function HuntController.podmate(player: Player): boolean
	local mine = Players.LocalPlayer:GetAttribute("Pod")
	return typeof(mine) == "number" and mine ~= 0 and player:GetAttribute("Pod") == mine
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
		if character and otherRoot and otherRoot:IsA("BasePart") and not HuntController.podmate(player) then
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

local function onBite()
	if SwimController.isHeld() then
		SwimController.struggle()
		return
	end
	-- What's in reach decides whether the bite darts at it: a lunge carries us
	-- forward, so look a little ahead of the mouth. With nothing there it's only the
	-- snap of the jaw, never a second, weaker dash (owner, 2026-10-16).
	local length = SwimController.length()
	local target: (() -> ())? = nil
	if not selfSafe() then
		for _, entry in nearby(length * 0.6 + 2) do
			if not HuntController.isSafe(entry.character) then
				local userId = entry.player.UserId
				target = function()
					ClientState.request("Bite", userId)
				end
				break
			end
		end
		-- No fish in reach: a predator or boss, maybe
		local root = SwimController.root()
		if target == nil and root then
			local mouth = root.CFrame:PointToWorldSpace(Size.mouthOffset(length))
			local index = PredatorController.nearest(mouth, Size.reach(length) + length * 0.6 + 2)
			if index then
				target = function()
					ClientState.request("BitePredator", index)
				end
			end
		end
	end
	if not SwimController.lunge(target ~= nil) then
		return
	end
	-- Heard and seen every time: a sharp snap (it was 0.35, lost under the music), a
	-- puff of bubbles at the mouth, a nudge of the camera and the jaws at the screen's
	-- middle; a bite that lands adds the crunch (onHit, onPredatorHit)
	Sfx.play(
		"Snap",
		{ volume = 0.9, pitch = math.clamp(1.3 - length * 0.03, 0.6, 1.3) * (0.94 + math.random() * 0.12) }
	)
	local root = SwimController.root()
	if root then
		Bubbles.burst(root.CFrame:PointToWorldSpace(Size.mouthOffset(length)), length * 0.35, 6)
	end
	CameraController.kick(0.1)
	HuntController.snapped:fire(false)
	if target then
		target()
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
		if victim ~= Players.LocalPlayer and attacker ~= Players.LocalPlayer then
			-- Someone else's fight, heard from where it happens
			Sfx.play(
				if damage < 0 then "Chomp" else "Bite",
				{ volume = 0.5, parent = victimRoot :: Instance, range = 160 }
			)
		end
	end
	if victim == Players.LocalPlayer and damage > 0 then
		Sfx.play("Hurt", { volume = 0.8 })
	elseif attacker == Players.LocalPlayer then
		Sfx.play(if damage < 0 then "Chomp" else "Bite", { volume = 0.85 })
		HuntController.snapped:fire(true)
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
	-- Our bite landing on a predator or a boss: the crunch and the jaws, as on a fish
	PredatorController.hit:connect(function()
		Sfx.play("Bite", { volume = 0.85, pitch = 0.95 + math.random() * 0.1 })
		HuntController.snapped:fire(true)
	end)
end

return HuntController
