--!strict
-- Starfish and shrimp: tiny filler food on the seabed. Spots are placed once at
-- server start (a ray down finds the sand or rock under each), the food is shared
-- by everyone, and an eaten one comes back after its respawn time. Clients draw it
-- and eat it instantly (ForageController); the server checks each eat.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local HuntService = require(script.Parent.HuntService)

local Forage = Config.Forage
local World = Config.World

local ForageService = {}

type Spot = { position: Vector3, kind: string }

local spots: { Spot } = {}
local eatenUntil: { [number]: number } = {}

local function placeSpots()
	local rng = Random.new(World.seed + 20)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace:WaitForChild("World"), workspace.Terrain }
	local trench = World.trench
	for _, def in Forage.list do
		local placed, tries = 0, 0
		while placed < def.spots and tries < def.spots * 6 do
			tries += 1
			local angle = rng:NextNumber(0, 2 * math.pi)
			local distance = rng:NextNumber(World.shallows.inner - 20, World.shallows.outer)
			local x, z = math.cos(angle) * distance, math.sin(angle) * distance
			local inTrench = math.abs(x - trench.center.X) < trench.size.X / 2 + 10
				and math.abs(z - trench.center.Z) < trench.size.Z / 2 + 10
			if not inTrench then
				local from = Vector3.new(x, World.surfaceY - 10, z)
				local hit = workspace:Raycast(from, Vector3.new(0, -(World.surfaceY + 40), 0), params)
				-- Only on the floor or gentle tops, not up the side of a rock
				if hit and hit.Normal.Y > 0.6 and hit.Instance.Name ~= "Surface" then
					table.insert(spots, { position = hit.Position + hit.Normal * 0.35, kind = def.id })
					placed += 1
				end
			end
		end
	end
end

local function onEat(player: Player, batch: any)
	if typeof(batch) ~= "table" or #batch > 12 then
		return
	end
	local mouth, length, slack = HuntService.mouth(player)
	if mouth == nil or DataService.get(player) == nil then
		return
	end
	local now = Timing.clock()
	local fed = 0
	local count = 0
	for _, index in batch do
		if typeof(index) ~= "number" or index % 1 ~= 0 or spots[index] == nil then
			continue
		end
		if (eatenUntil[index] or 0) > now then
			continue
		end
		local spot = spots[index]
		-- The client's reach, its suction pull (eats from up to ~1.3 × reach) and a hop
		local reach = (Size.reach(length) * Forage.REACH_SCALE + Forage.REACH_BONUS) * 1.35 + Forage.HOP
		if (spot.position - mouth).Magnitude > reach + slack then
			continue
		end
		local def = Forage.byId[spot.kind]
		if def.wrap then
			-- Medkelp: a Kelp Wrap, if there's room to carry it (else it stays put)
			if not HuntService.giveWrap(player, 1) then
				Net.notify(player, "You can't carry more Kelp Wraps", "info")
				continue
			end
			Net.notify(player, "Medkelp: +1 Kelp Wrap", "good")
		end
		local backAt = now + def.respawn
		eatenUntil[index] = backAt
		Net.forageEaten(index, backAt, player.UserId)
		fed += def.mass
		count += 1
		if math.random() < Config.Tuning.economy.forageDnaChance then
			HuntService.giveDna(player, spot.position, 1)
		end
	end
	if fed > 0 then
		HuntService.feed(player, fed)
		Events.ate:fire(player, count)
	end
end

function ForageService.start()
	placeSpots()
	Net.onRequest("EatForage", onEat)
	Net.onGetForage(function(): { [string]: any }
		local positions: { Vector3 } = {}
		local kinds: { string } = {}
		for _, spot in spots do
			table.insert(positions, spot.position)
			table.insert(kinds, spot.kind)
		end
		local eaten: { [string]: number } = {}
		local now = Timing.clock()
		for index, backAt in eatenUntil do
			if backAt > now then
				eaten[tostring(index)] = backAt
			end
		end
		return { positions = positions, kinds = kinds, eaten = eaten }
	end)
	Guard.loop("ForageService.prune", 15, function()
		local now = Timing.clock()
		for index, backAt in eatenUntil do
			if backAt <= now then
				eatenUntil[index] = nil
			end
		end
	end)
end

return ForageService
