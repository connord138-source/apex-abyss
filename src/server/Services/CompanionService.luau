--!strict
-- Sea life that helps (Config/Companions; owner, 2026-10-20: "fish that are not edible
-- such as turtles and stingrays manta rays need to have some kind of function whether
-- it is a buff where they swim with you and provide a bonus or something similar").
-- The turtles, rays and mantas live only on each client (AmbientLifeController), so a
-- client tells us when a turtle joined it or it flushed a ray (`Companion`), and we
-- check what we can: a live fish out of the hub and the dens, in a biome that kind
-- lives in, near the floor for a ray, and the cooldowns. A turtle sets the character's
-- `Escort` attribute (the clock it leaves at): every client draws it at that fish's
-- side (CompanionController) and HuntService scales what bites do by `bite`. A ray
-- pays a few shells. The manta's draft is a speed the client takes for itself, which
-- SpeedService allows.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Biomes = require(ReplicatedStorage.Shared.Biomes)
local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Net = require(script.Parent.Parent.Net)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)

local Companions = Config.Companions
local Kinds = Config.Ambient.kinds

local CompanionService = {}

-- When each player may have a turtle join, or flush a ray, again (the clock)
local turtleAgain: { [Player]: number } = {}
local rayAgain: { [Player]: number } = {}

local function livesHere(kind: string, position: Vector3): boolean
	local biome = Biomes.at(position)
	if biome == nil then
		return false
	end
	for _, id in Kinds[kind].biomes do
		if id == biome.id then
			return true
		end
	end
	return false
end

local function onRequest(player: Player, kind: any)
	if kind ~= "turtle" and kind ~= "ray" then
		return
	end
	local character, root = FishService.character(player)
	if character == nil or root == nil then
		return
	end
	local at = root.Position
	if Layout.inHub(at) or Layout.denAt(at) or not livesHere(kind, at) then
		return
	end
	local now = Timing.clock()
	if kind == "turtle" then
		local tune = Companions.turtle
		if now < (turtleAgain[player] or 0) then
			return
		end
		-- (a little short of the client's own timer: latency)
		turtleAgain[player] = now + tune.lasts + tune.cooldown * 0.9
		character:SetAttribute("Escort", now + tune.lasts)
		Net.notify(player, "A sea turtle swims with you · bites hurt less", "good")
	else
		local tune = Companions.ray
		if now < (rayAgain[player] or 0) then
			return
		end
		-- low over the sand (a little slack over the client's check)
		if at.Y - Ground.y(at.X, at.Z) > tune.over + 6 then
			return
		end
		rayAgain[player] = now + tune.cooldown * 0.9
		EconomyService.addShells(player, tune.shells)
		Net.notify(player, `+{tune.shells} shells · the ray stirred them up`, "good")
	end
end

function CompanionService.start()
	Net.onRequest("Companion", onRequest)
	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		turtleAgain[player] = nil
		rayAgain[player] = nil
	end)
end

return CompanionService
