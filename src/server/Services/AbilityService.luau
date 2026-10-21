--!strict
-- The signature abilities the server must know about (Config/Abilities; owner,
-- 2026-10-17: "each different fish should have their own limitations/advantages").
-- The client asks (`UseAbility`), and the server checks the fish is that species,
-- the ability has recharged and (for Burrow) there's rock or wreckage to hide
-- against, then puts it on the character as attributes every client and service
-- reads:
--   Puffed      server clock (Timing.clock) it deflates at: the Pufferfish can't be
--               swallowed, bites on it do less and hurt the biter (HuntService,
--               PredatorService), and it swims slowly and is drawn bigger (clients)
--   Burrowed    true while a Moray hides: predators ignore it, other players see it
--               faded with no name tag. It comes out when it moves off the spot, asks
--               (`EndAbility`) or after `seconds`; then BurrowStrike (server clock) is
--               when its ambush bite runs out (HuntService)
--   FlashAt     server clock of an Anglerfish's Lantern Flash: predators round it are
--               stunned (PredatorService.stun) and clients dazzle the players near it
--   Sensing     server clock a Reef Shark's Blood Sense ends at (a feeding frenzy,
--               owner 2026-10-18): it swims faster and draws prey in from further
--               (Perks.sense: SwimController, SchoolController, ForageController, and
--               HuntService and SpeedService allow for it); its owner's client draws
--               the reveal
-- The Dash and the 'Cuda's Torpedo are the client's alone (movement).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
local DataService = require(script.Parent.DataService)
local FishService = require(script.Parent.FishService)
local PredatorService = require(script.Parent.PredatorService)

local Abilities = Config.Abilities.byId

local AbilityService = {}

local SLACK = 0.85 -- the server's cooldowns run this much shorter (latency)

type Burrow = { spot: Vector3, since: number }

local readyAt: { [Player]: { [string]: number } } = {}
local burrows: { [Player]: Burrow } = {}

-- An ability's cooldown for this player (the Outfitter's Quick Recovery shortens every
-- fish's own: Perks.boost), a little short of the client's for latency
local function cooldownOf(player: Player, seconds: number): number
	local data = DataService.get(player)
	return seconds * SLACK / Perks.boost(if data then data.upgrades else nil)
end

-- The signature ability of the fish a player swims as
local function signatureOf(player: Player): string?
	local data = DataService.get(player)
	return if data then Progress.species(data).signature else nil
end

local function lengthOf(character: Model): number
	local length = character:GetAttribute("Length")
	return if typeof(length) == "number" then length else 2
end

-- Whether rock, wreckage or the seabed is within reach of the fish (six rays)
local function againstCover(character: Model, root: BasePart, reach: number): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local characters: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	params.FilterDescendantsInstances = characters
	params.RespectCanCollide = true
	for _, direction in
		{ Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis, -Vector3.yAxis, Vector3.yAxis }
	do
		if workspace:Raycast(root.Position, direction * reach, params) then
			return true
		end
	end
	return false
end

local function endBurrow(player: Player)
	local burrow = burrows[player]
	if burrow == nil then
		return
	end
	burrows[player] = nil
	local now = Timing.clock()
	local mine: { [string]: number } = readyAt[player] or {}
	readyAt[player] = mine
	mine.Burrow = now + cooldownOf(player, Abilities.Burrow.cooldown or 8)
	local character = FishService.character(player)
	if character then
		character:SetAttribute("Burrowed", nil)
		character:SetAttribute("BurrowStrike", now + (Abilities.Burrow.strike or 1.5))
	end
end

local function use(player: Player, id: any)
	if typeof(id) ~= "string" or signatureOf(player) ~= id then
		return
	end
	local ability = Abilities[id]
	local character, root = FishService.character(player)
	if ability == nil or character == nil or root == nil then
		return
	end
	-- Pressed again while burrowed: come out
	if id == "Burrow" and burrows[player] then
		endBurrow(player)
		return
	end
	local now = Timing.clock()
	local mine: { [string]: number } = readyAt[player] or {}
	readyAt[player] = mine
	if now < (mine[id] or 0) then
		return
	end
	if id == "PuffUp" then
		character:SetAttribute("Puffed", now + (ability.seconds or 4))
	elseif id == "Burrow" then
		local length = lengthOf(character)
		if not againstCover(character, root, length * (ability.reach or 0.9) + length * 0.3) then
			Net.notify(player, "Burrow against rock, wreckage or the seabed", "info")
			return
		end
		burrows[player] = { spot = root.Position, since = now }
		character:SetAttribute("Burrowed", true)
		return -- (its cooldown starts when it ends)
	elseif id == "BloodSense" then
		character:SetAttribute("Sensing", now + (ability.seconds or 7))
	elseif id == "LanternFlash" then
		character:SetAttribute("FlashAt", now)
		local stun = (PredatorService :: any).stun
		if typeof(stun) == "function" then
			stun(root.Position, ability.reach or 48, ability.stun or 2.5)
		end
	else
		return
	end
	mine[id] = now + cooldownOf(player, ability.cooldown or 0)
end

function AbilityService.start()
	Net.onRequest("UseAbility", use)
	Net.onRequest("EndAbility", function(player: Player)
		endBurrow(player)
	end)
	-- Burrowed fish come out when they move off the spot, or after `seconds`
	Guard.loop("AbilityService.burrows", 0.2, function()
		local now = Timing.clock()
		local ability = Abilities.Burrow
		for player, burrow in burrows do
			local _, root = FishService.character(player)
			if
				root == nil
				or (root.Position - burrow.spot).Magnitude > (ability.stray or 4)
				or now - burrow.since > (ability.seconds or 30)
			then
				endBurrow(player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		readyAt[player] = nil
		burrows[player] = nil
	end)
	-- A new fish (a respawn, a species switch) starts clean
	FishService.spawned:connect(function(player: Player)
		burrows[player] = nil
	end)
end

return AbilityService
