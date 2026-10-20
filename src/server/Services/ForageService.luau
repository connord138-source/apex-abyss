--!strict
-- Starfish, shrimp, medkelp and crabs: filler food on the seabed. Spots are placed once
-- at server start on open floor (Shared/Ground `open`: never in or under a rock, coral,
-- wreck, ruin or overhang a fish can't get to), the food is shared by everyone, and
-- an eaten one comes back after its respawn time. Clients draw it and eat it
-- instantly (ForageController); the server checks each eat.
--
-- Crabs (Config/Forage kinds with `crab`) are laid out in their own biome, mostly
-- beside the rock, coral, wrecks, ruins and chimneys there, on floor open for their
-- whole scuttle; an eat allows for that scuttle (Shared/Crabs) and the crab's size, and
-- only a fish that can swallow something its size eats one (Size.canSwallow).
--
-- Once the world is built this also lifts the prey schools over the real ground
-- (Shared/Schools `settle`) and publishes the lifts for clients (`SchoolLifts`).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Biomes = require(ReplicatedStorage.Shared.Biomes)
local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Schools = require(ReplicatedStorage.Shared.Schools)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local HuntService = require(script.Parent.HuntService)

local Forage = Config.Forage
type Band = typeof(Forage.list[1].bands[1])
local World = Config.World

local ForageService = {}

type Spot = { position: Vector3, kind: string, up: Vector3? }

local spots: { Spot } = {}
local eatenUntil: { [number]: number } = {}

-- Open floor a small fish can get to (Shared/Ground `open`): a ball of OPEN_RADIUS
-- comes down onto it from above, no part's box comes within OPEN_ROOM of the water over
-- it (playtest 2026-10-10: a shrimp at a boulder's foot was behind an invisible
-- wall), and the floor is gentle (OPEN_UP, not up the side of a rock). The world is
-- built before this runs.
local OPEN_RADIUS = 1.25
local OPEN_ROOM = 2.5
local OPEN_UP = 0.6

-- Crabs keep `HUB_CLEAR` studs from the hub (its seamount), and one beside rock has
-- solid dressing within `BESIDE` studs of the edge of its open floor
local HUB_CLEAR = 215
local BESIDE = 9

-- Solid dressing round a spot (rock, coral, wrecks, ruins, chimneys: anything a fish
-- bumps into but the Terrain)
local besideParams: OverlapParams? = nil
local function besideRock(at: Vector3, radius: number): boolean
	local params = besideParams
	if params == nil then
		local made = OverlapParams.new()
		made.FilterType = Enum.RaycastFilterType.Exclude
		made.FilterDescendantsInstances = { workspace.Terrain }
		made.RespectCanCollide = true
		made.MaxParts = 1
		besideParams = made
		params = made
	end
	return #workspace:GetPartBoundsInRadius(at, radius, params :: OverlapParams) > 0
end

-- A point in a band: a ring round the hub, or a biome's own sector (narrowed to the
-- band's rings), even over its area
local function sample(rng: Random, band: Band): (number, number)
	local center = World.hub.center
	local from, to, angleFrom, span = band.from or 140, band.to or 830, 0, 360
	local biomeId = band.biome
	local biome = if biomeId then Config.Biomes.byId[biomeId] else nil
	if biome then
		from = math.max(biome.radiusFrom, band.from or 0, HUB_CLEAR)
		to = math.min(biome.radiusTo, band.to or math.huge)
		angleFrom = biome.angleFrom
		span = (biome.angleTo - biome.angleFrom) % 360
		if span == 0 then
			span = 360
		end
	end
	local angle = math.rad(angleFrom + rng:NextNumber(0, span))
	local distance = math.sqrt(rng:NextNumber(from ^ 2, to ^ 2))
	return center.X + math.cos(angle) * distance, center.Z + math.sin(angle) * distance
end

local function placeSpots()
	local rng = Random.new(World.seed + 20)
	local closed, short = 0, 0
	local crabs = 0
	for _, def in Forage.list do
		local crab = def.crab
		-- A crab needs open floor for its whole scuttle and room for its size
		local radius = if crab then math.max(OPEN_RADIUS, (def.size or 1) * 0.4) else OPEN_RADIUS
		local room = if crab then OPEN_ROOM + (def.scuttle or 0) else OPEN_ROOM
		for _, band in def.bands do
			local placed, tries = 0, 0
			local most = band.count * (if crab then 14 else 8)
			while placed < band.count and tries < most do
				tries += 1
				local x, z = sample(rng, band)
				local biomeId = band.biome
				-- (a crab may live in the Trench's canyon; nothing else is put down there)
				if biomeId ~= "AbyssalTrench" and Seafloor.inTrench(x, z, 10) then
					continue
				end
				local floor, normal = Ground.open(x, z, radius, OPEN_UP, room)
				if floor == nil or normal == nil then
					closed += 1
					continue
				end
				if biomeId then
					local biome = Biomes.at(floor + Vector3.new(0, 2, 0))
					if biome == nil or biome.id ~= biomeId then
						continue
					end
				end
				-- Mostly beside rock: a spot out on the open floor is kept only some of the time
				if
					crab
					and rng:NextNumber() < crab.near
					and not besideRock(floor + Vector3.new(0, 2, 0), room + BESIDE)
				then
					continue
				end
				if crab then
					table.insert(spots, { position = floor, kind = def.id, up = normal })
					crabs += 1
				else
					table.insert(spots, { position = floor + normal * 0.35, kind = def.id })
				end
				placed += 1
			end
			short += band.count - placed
		end
	end
	print(
		`[ForageService] {#spots} food spots on open floor, {crabs} of them crabs ({closed} tries refused as closed in, {short} short)`
	)
end

-- Lifts the prey schools over the rocks, reefs and wrecks along their loops (the
-- dressing is built by now) and tells clients
local function settleSchools()
	local started = os.clock()
	local lifts = Schools.settle(Ground.y, function()
		task.wait()
	end)
	workspace:SetAttribute("SchoolLifts", lifts)
	local lifted = if lifts == "" then 0 else #string.split(lifts, ";")
	local ms = math.floor((os.clock() - started) * 1000)
	print(
		`[ForageService] {lifted} of {#Schools.list} prey schools lifted over the ground ({ms} ms, yielding)`
	)
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
	local suction = HuntService.suction(player) -- (a Reef Shark's Blood Sense frenzy)
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
		local def = Forage.byId[spot.kind]
		-- The client's reach, its suction pull (eats from up to ~1.3 × reach) and a hop;
		-- a crab's scuttle and its legs' reach instead of the hop, and only one the
		-- fish can swallow
		local reach = (Size.reach(length) * Forage.REACH_SCALE + Forage.REACH_BONUS) * 1.35 * suction
		local crabSize = def.size
		local at = spot.position
		if crabSize then
			if not Size.canSwallow(length * 1.03, crabSize) then
				continue
			end
			-- (measured to its middle, a little over the floor it walks on)
			at += (spot.up or Vector3.yAxis) * crabSize * Forage.CRAB_HEIGHT
			reach += (def.scuttle or 0) + crabSize * Forage.CRAB_RADIUS + 1
		else
			reach += Forage.HOP
		end
		if (at - mouth).Magnitude > reach + slack then
			continue
		end
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
	-- (in its own thread: it yields between schools, and the start order goes on; the
	-- server and every client draw the schools unlifted until it's published)
	task.spawn(settleSchools)
	placeSpots()
	Net.onRequest("EatForage", onEat)
	Net.onGetForage(function(): { [string]: any }
		local positions: { Vector3 } = {}
		local kinds: { string } = {}
		local ups: { [string]: Vector3 } = {} -- a crab's floor's normal, by spot
		for index, spot in spots do
			table.insert(positions, spot.position)
			table.insert(kinds, spot.kind)
			if spot.up then
				ups[tostring(index)] = spot.up
			end
		end
		local eaten: { [string]: number } = {}
		local now = Timing.clock()
		for index, backAt in eatenUntil do
			if backAt > now then
				eaten[tostring(index)] = backAt
			end
		end
		return { positions = positions, kinds = kinds, eaten = eaten, ups = ups }
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
