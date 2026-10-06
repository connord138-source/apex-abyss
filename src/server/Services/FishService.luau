--!strict
-- Each player's fish: a custom character (a ball collider as the
-- HumanoidRootPart, a Humanoid so the touch controls and camera plumbing work,
-- and the graybox body from FishBuilder). The player's own client moves it
-- (SwimController, with network ownership); the server sizes it, spawns it in its
-- den and respawns it after it's eaten. Dens are handed out here too.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FishBuilder = require(ReplicatedStorage.Shared.FishBuilder)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)

local hunt = Config.Tuning.hunt

local FishService = {
	-- (player, character) after a fish is spawned
	spawned = Signal.new(),
}

local denOwners: { [number]: Player } = {}
local dens: { [Player]: number } = {}
local respawnToken: { [Player]: number } = {}

-- Graybox looks, handed out by UserId so a player keeps theirs
local LOOKS: { FishBuilder.Look } = {
	{
		back = Color3.fromRGB(52, 92, 132),
		belly = Color3.fromRGB(214, 226, 234),
		fin = Color3.fromRGB(78, 132, 176),
	},
	{
		back = Color3.fromRGB(214, 98, 52),
		belly = Color3.fromRGB(246, 214, 182),
		fin = Color3.fromRGB(236, 140, 80),
	},
	{
		back = Color3.fromRGB(58, 122, 96),
		belly = Color3.fromRGB(206, 228, 200),
		fin = Color3.fromRGB(90, 160, 120),
	},
	{
		back = Color3.fromRGB(110, 76, 160),
		belly = Color3.fromRGB(222, 210, 240),
		fin = Color3.fromRGB(150, 110, 200),
	},
	{
		back = Color3.fromRGB(60, 140, 150),
		belly = Color3.fromRGB(210, 236, 236),
		fin = Color3.fromRGB(90, 186, 196),
	},
	{
		back = Color3.fromRGB(176, 140, 50),
		belly = Color3.fromRGB(244, 230, 184),
		fin = Color3.fromRGB(214, 176, 80),
	},
	{
		back = Color3.fromRGB(94, 104, 114),
		belly = Color3.fromRGB(226, 228, 230),
		fin = Color3.fromRGB(124, 136, 146),
	},
	{
		back = Color3.fromRGB(168, 46, 60),
		belly = Color3.fromRGB(240, 200, 200),
		fin = Color3.fromRGB(206, 80, 92),
	},
}

function FishService.denOf(player: Player): number?
	return dens[player]
end

function FishService.character(player: Player): (Model?, BasePart?)
	local character = player.Character
	if character == nil or character.Parent == nil then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	return character, root
end

-- Resizes the fish's collider and tells every client the new length (they ease the
-- body to it). `length` is in studs.
function FishService.setLength(player: Player, length: number)
	local character, root = FishService.character(player)
	if character == nil or root == nil then
		return
	end
	character:SetAttribute("Length", length)
	root.Size = Vector3.one * Size.colliderDiameter(length)
end

local function makeCharacter(player: Player, length: number, at: CFrame): Model
	local character = Instance.new("Model")
	character.Name = player.Name

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.one * Size.colliderDiameter(length)
	root.Transparency = 1
	root.CanCollide = true
	root.CanTouch = true
	-- Frictionless and springless: a fish slides along walls instead of sticking
	root.CustomPhysicalProperties = PhysicalProperties.new(1, 0, 0, 100, 100)
	root.CFrame = at
	root.Parent = character
	local attachment = Instance.new("Attachment")
	attachment.Name = "RootAttachment"
	attachment.Parent = root

	local humanoid = Instance.new("Humanoid")
	-- The Humanoid only keeps Roblox's touch controls and camera plumbing happy;
	-- it never moves the fish
	humanoid.EvaluateStateMachine = false
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.AutoRotate = false
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = character

	local look = LOOKS[(player.UserId % #LOOKS) + 1]
	FishBuilder.build(character, root, look, length)
	character.PrimaryPart = root
	character:SetAttribute("Length", length)
	character:SetAttribute("Health", hunt.health)
	character:SetAttribute("SafeUntil", Timing.clock() + hunt.spawnProtection)
	character:SetAttribute("UserId", player.UserId)
	return character
end

function FishService.spawn(player: Player)
	local data = DataService.get(player)
	local den = dens[player]
	if data == nil or den == nil or player.Parent ~= Players then
		return
	end
	FishService.despawn(player)
	local length = Size.length(data.mass)
	local character = makeCharacter(player, length, Layout.spawnFrame(den))
	player.Character = character
	character.Parent = workspace
	local root = character.PrimaryPart
	if root then
		root:SetNetworkOwner(player)
	end
	FishService.spawned:fire(player, character)
end

function FishService.despawn(player: Player)
	respawnToken[player] = (respawnToken[player] or 0) + 1
	local character = player.Character
	if character then
		player.Character = nil
		character:Destroy()
	end
end

-- Removes the fish now and brings it back in its den after `seconds`.
function FishService.respawnIn(player: Player, seconds: number)
	FishService.despawn(player)
	local token = respawnToken[player]
	task.delay(seconds, function()
		if respawnToken[player] == token and player.Parent == Players then
			FishService.spawn(player)
		end
	end)
end

local function assignDen(player: Player): number?
	for index = 1, Layout.DEN_COUNT do
		local owner: Player? = denOwners[index]
		if owner == nil then
			denOwners[index] = player
			dens[player] = index
			WorldService.setDenOwner(index, player.DisplayName)
			return index
		end
	end
	return nil
end

function FishService.start()
	Players.CharacterAutoLoads = false -- fish are spawned here, never as avatars
	DataService.loaded:connect(function(player: Player)
		if assignDen(player) == nil then
			player:Kick("This server is full — please join another.")
			return
		end
		FishService.spawn(player)
	end)
	DataService.releasing:connect(function(player: Player)
		FishService.despawn(player)
		respawnToken[player] = nil
		local den = dens[player]
		if den then
			dens[player] = nil
			denOwners[den] = nil
			WorldService.setDenOwner(den, nil)
		end
	end)
end

return FishService
