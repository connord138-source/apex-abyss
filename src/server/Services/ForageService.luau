--!strict
-- Starfish and shrimp: tiny filler food on the seabed. Spots are placed once at
-- server start (a ray down finds the sand or rock under each), the food is shared
-- by everyone, and an eaten one comes back after its respawn time. Clients draw it
-- and eat it instantly (ForageController); the server checks each eat.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
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

-- Whether a fish can get to food at `position`: nothing solid round it (a rock or
-- coral it would sit inside or under; playtest 2026-10-10: a shrimp at a boulder's
-- foot was behind an invisible wall). The world is built before this runs.
local blockers = OverlapParams.new()
blockers.FilterType = Enum.RaycastFilterType.Exclude
blockers.FilterDescendantsInstances = { workspace.Terrain }
blockers.RespectCanCollide = true
local function reachable(position: Vector3): boolean
	return #workspace:GetPartBoundsInRadius(position + Vector3.new(0, 1.5, 0), 2.5, blockers) == 0
end

local function placeSpots()
	local rng = Random.new(World.seed + 20)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain } -- the floor itself, never a kelp blade
	for _, def in Forage.list do
		for _, band in def.bands do
			local placed, tries = 0, 0
			while placed < band.count and tries < band.count * 6 do
				tries += 1
				local angle = rng:NextNumber(0, 2 * math.pi)
				-- Even over the band's area, not bunched at its inner edge
				local distance = math.sqrt(rng:NextNumber(band.from ^ 2, band.to ^ 2))
				local x, z = math.cos(angle) * distance, math.sin(angle) * distance
				if not Seafloor.inTrench(x, z, 10) then
					local from = Vector3.new(x, World.surfaceY - 10, z)
					local hit = workspace:Raycast(from, Vector3.new(0, -(World.surfaceY + 40), 0), params)
					-- Only on the floor or gentle tops, not up the side of a rock
					if hit and hit.Normal.Y > 0.6 then
						local position = hit.Position + hit.Normal * 0.35
						if reachable(position) then
							table.insert(spots, { position = position, kind = def.id })
							placed += 1
						end
					end
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
