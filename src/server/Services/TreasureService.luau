--!strict
-- Treasure maps (Config/Treasure): drops from prey, shells and big banks; each map
-- points at a dig site this service picked on the seabed; the holder follows it
-- (the client does the hot/cold sonar from the site in their state) and digs with a
-- hold. The server checks the map is theirs and they're really at the X, rolls the
-- reward, grants it and sends the result for the reveal. Only the holder can dig.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Pressure = require(ReplicatedStorage.Shared.Pressure)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local HuntService = require(script.Parent.HuntService)
local StateService = require(script.Parent.StateService)

local Treasure = Config.Treasure
local Tiers = Config.Tiers
local World = Config.World

-- Config tables don't export their types; take them from the data
type MapTier = typeof(Treasure.tiers[1])
type Reward = typeof(Treasure.tiers[1].rewards[1])
type Shade = typeof(Config.Shades.list[1])

local TreasureService = {}

local rng = Random.new()
-- Each player's allowance of maps from prey (Config/Treasure `drops.preyPerHour`):
-- tokens refill over time up to `preyBurst`, and a prey map takes one
type Allowance = { tokens: number, at: number }
local preyTokens: { [Player]: Allowance } = {}
local digStarted: { [Player]: { mapId: string, at: number } } = {}

type Data = DataService.PlayerData

local function maps(data: Data): { DataService.TreasureMap }
	-- Older saves predate the satchel
	if data.maps == nil then
		data.maps = {}
		data.activeMap = ""
		data.treasures = { found = 0, byTier = {} }
	end
	return data.maps
end

local function pickWeighted<T>(items: { T }, weightOf: (T) -> number): T?
	local total = 0
	for _, item in items do
		total += weightOf(item)
	end
	if total <= 0 then
		return nil
	end
	local r = rng:NextNumber() * total
	for _, item in items do
		r -= weightOf(item)
		if r <= 0 then
			return item
		end
	end
	return items[#items]
end

local function pickTier(weights: { [string]: number }): MapTier?
	return pickWeighted(Treasure.tiers, function(tier)
		return weights[tier.id] or 0
	end)
end

-- A dig site for a tier: on the seabed, in the tier's distance band, not in the
-- trench, and above `deepest` (the holder's crush depth, Config/Pvp `pressure`: a map
-- must never send a fish where the pressure kills it). Only open floor a fish can
-- reach (Shared/Ground.open: nothing over it or round it; owner, 2026-10-17: nothing
-- "in or under items that the player cannot access"). Falls back to the sand level
-- if nothing is found.
local function pickSite(tier: MapTier, deepest: number?): Vector3
	for _ = 1, 40 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local distance = rng:NextNumber(tier.minDistance, tier.maxDistance)
		local x, z = math.cos(angle) * distance, math.sin(angle) * distance
		if Seafloor.inTrench(x, z, 16) then
			continue
		end
		local floor = Ground.open(x, z, 2.5, 0.7, 4)
		if floor and floor.Y < 40 and floor.Y > (deepest or -math.huge) + 4 then
			return floor
		end
	end
	-- No luck: a spot on the shelf's sand, inside its edge, which is above every
	-- crush depth (the old fallback ignored it and could land off the shelf, out over
	-- the deep floor; PC overnight 2026-10-14)
	local angle = rng:NextNumber(0, 2 * math.pi)
	local distance = math.min((tier.minDistance + tier.maxDistance) / 2, World.shelf.radius - 60)
	local x, z = math.cos(angle) * distance, math.sin(angle) * distance
	return Vector3.new(x, Seafloor.y(x, z), z)
end

-- A named place that may hide this tier's chest instead (Config/Places `dig`; owner,
-- 2026-10-21: the Broken Galleon's cabin is a dig site): its `<id>_Dig` spot on
-- Workspace.Places, at `digChance`, if it's above `deepest`. Returns the spot and the
-- map's hint.
local function placeSite(tier: MapTier, deepest: number?): (Vector3?, string?)
	local marks = workspace:FindFirstChild("Places")
	if marks == nil then
		return nil, nil
	end
	for _, place in Config.Places.list do
		if place.dig == nil or table.find(place.dig, tier.id) == nil then
			continue
		end
		if rng:NextNumber() >= Config.Places.digChance then
			continue
		end
		local spot = marks:GetAttribute(`{place.id}_Dig`)
		if typeof(spot) == "Vector3" and spot.Y > (deepest or -math.huge) + 4 then
			return spot, place.digHint or `At {place.name}`
		end
	end
	return nil, nil
end

local COMPASS = { "east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east" }

-- "About 320 studs north-east of the hub, among the boulders"
local function hintFor(tier: MapTier, site: Vector3): string
	local offset = site - World.hub.center
	local angle = math.atan2(offset.Z, offset.X)
	local index = (math.floor((angle + math.pi / 8) / (math.pi / 4)) % 8) + 1
	local distance = math.floor(Vector2.new(offset.X, offset.Z).Magnitude / 20 + 0.5) * 20
	local where = if tier.id == "Tattered"
		then "under the kelp"
		elseif tier.id == "Weathered" then "among the boulders"
		else "where the sand meets the open blue"
	return `About {Format.distance(distance)} {COMPASS[index]} of the hub, {where}`
end

-- Hands a player a map of `tier` (if they have room). Returns whether one was given.
function TreasureService.give(player: Player, tierId: string): boolean
	local data = DataService.get(player)
	local tier = Treasure.byId[tierId]
	if data == nil or tier == nil then
		return false
	end
	local held = maps(data)
	if #held >= Treasure.maxHeld then
		return false
	end
	local band = Pressure.limit(Size.level(Progress.mass(data)) + Perks.depth(data.upgrades))
	local deepest = if band then band.y else nil
	local placed, placeHint = placeSite(tier, deepest)
	local site = placed or pickSite(tier, deepest)
	table.insert(held, {
		id = HttpService:GenerateGUID(false),
		tier = tier.id,
		site = { x = site.X, y = site.Y, z = site.Z },
		hint = placeHint or hintFor(tier, site),
		created = Timing.now(),
	})
	-- Follow it straight away when nothing else is being followed
	if data.activeMap == "" then
		data.activeMap = held[#held].id
	end
	DataService.markDirty(player)
	Net.notify(player, `You found a {tier.name} Treasure Map! Open MAPS to see it`, "rare")
	return true
end

-- Returns whether a map dropped
local function tryDrop(player: Player, chance: number, weights: { [string]: number }): boolean
	local data = DataService.get(player)
	if data == nil or #maps(data) >= Treasure.maxHeld or rng:NextNumber() >= chance then
		return false
	end
	local tier = pickTier(weights)
	if tier then
		TreasureService.give(player, tier.id)
		return true
	end
	return false
end

local function siteOf(map: DataService.TreasureMap): Vector3
	return Vector3.new(map.site.x, map.site.y, map.site.z)
end

local function findMap(data: Data, id: string): (DataService.TreasureMap?, number)
	for index, map in maps(data) do
		if map.id == id then
			return map, index
		end
	end
	return nil, 0
end

-- Whether the player's fish is at the map's X (with slack for the server seeing
-- the fish a little in the past).
local function atSite(player: Player, map: DataService.TreasureMap): boolean
	local character, root = FishService.character(player)
	if character == nil or root == nil then
		return false
	end
	local length = character:GetAttribute("Length")
	local fishLength = if typeof(length) == "number" then length else 2
	local slack = Size.topSpeed(fishLength) * 0.35 + 4
	return (root.Position - siteOf(map)).Magnitude <= Treasure.sonar.dig + fishLength * 0.6 + slack
end

local function follow(player: Player, id: any)
	local data = DataService.get(player)
	if data == nil or typeof(id) ~= "string" then
		return
	end
	maps(data)
	if id ~= "" and findMap(data, id) == nil then
		return
	end
	data.activeMap = id
	digStarted[player] = nil
	DataService.markDirty(player)
end

local function startDig(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local map = findMap(data, data.activeMap)
	if map == nil then
		return Net.notify(player, "Follow a map first (MAPS)", "bad")
	end
	if not atSite(player, map) then
		return Net.notify(player, "Get right over the X to dig", "bad")
	end
	digStarted[player] = { mapId = map.id, at = os.clock() }
end

-- Rolls the shade for a Shade Roll reward: any of the digging fish's own line at
-- `minTier` or rarer, weighted by its roll chance (rarer ones stay rarer).
local function rollShade(minTier: string, owned: { [string]: boolean }, species: string): Shade?
	local floor = Tiers.byId[minTier]
	local pool: { Shade } = {}
	for _, shade in Config.Shades.list do
		local tier = Tiers.byId[shade.tier]
		if
			Config.Shades.rollable(shade)
			and shade.species == species
			and not owned[shade.id]
			and tier
			and floor
			and tier.order >= floor.order
		then
			table.insert(pool, shade)
		end
	end
	return pickWeighted(pool, function(shade)
		return 1 / shade.chance
	end)
end

local function grant(
	player: Player,
	data: Data,
	map: DataService.TreasureMap,
	reward: Reward
): { [string]: any }
	local result: { [string]: any } = {
		outcome = { id = reward.id, kind = reward.kind, name = reward.name, tier = reward.tier },
		pool = map.tier,
		mapTier = map.tier,
		kind = reward.kind,
		id = reward.id,
	}
	if reward.kind == "coral" then
		EconomyService.addCoral(player, reward.amount or 0)
		result.coral = reward.amount
	elseif reward.kind == "shells" then
		EconomyService.addShells(player, reward.amount or 0)
		result.shells = reward.amount
	elseif reward.kind == "haul" then
		-- Full Hauls of the digger's own, on top of what it carries (×2 Mass and
		-- Frenzy still count; Config/Treasure `hauls`)
		result.haul = HuntService.shown(player, HuntService.hauls(player, reward.hauls or 1, "sized")) -- (as food)
	elseif reward.kind == "dna" then
		HuntService.giveDna(player, siteOf(map), reward.amount or 0)
		result.dna = reward.amount
	elseif reward.kind == "wraps" then
		HuntService.giveWrap(player, reward.amount or 0)
		result.wraps = reward.amount
	elseif reward.kind == "charm" then
		local charmId = reward.charm or "Lucky"
		data.charms[charmId] = (data.charms[charmId] or 0) + 1
		result.charm = charmId
	elseif reward.kind == "shade" or reward.kind == "shaderoll" then
		local shade = if reward.kind == "shade"
			then Config.Shades.byId[reward.shade or ""]
			else rollShade(
				reward.minShadeTier or "Rare",
				Progress.shades(data),
				Progress.speciesId(data)
			)
		if shade then
			result.kind = "shade"
			result.id = shade.id
			result.outcome = { id = shade.id, kind = "shade", name = `{shade.name} Shade`, tier = shade.tier }
			if not Progress.grantShade(data, shade.id) then
				result.duplicate = true
				result.coral = shade.refund
				EconomyService.addCoral(player, shade.refund)
			end
		else
			EconomyService.addCoral(player, 300)
			result.kind = "coral"
			result.coral = 300
			result.outcome = { id = "Coral300", kind = "coral", name = "Coral Hoard", tier = "Coral" }
		end
	end
	return result
end

local function finishDig(player: Player)
	local data = DataService.get(player)
	local started = digStarted[player]
	if data == nil or started == nil then
		return
	end
	digStarted[player] = nil
	local map, index = findMap(data, started.mapId)
	if map == nil or map.id ~= data.activeMap then
		return
	end
	local tier = Treasure.byId[map.tier]
	if tier == nil then
		return
	end
	if os.clock() - started.at < tier.digSeconds - 0.5 then
		return Net.notify(player, "Keep digging...", "info")
	end
	if not atSite(player, map) then
		return Net.notify(player, "Stay on the X while you dig", "bad")
	end
	local reward = pickWeighted(tier.rewards, function(r)
		return r.weight
	end)
	if reward == nil then
		return
	end
	table.remove(maps(data), index)
	data.activeMap = ""
	data.treasures.found += 1
	data.treasures.byTier[map.tier] = (data.treasures.byTier[map.tier] or 0) + 1
	local result = grant(player, data, map, reward)
	result.found = data.treasures.found
	DataService.markDirty(player)
	Net.treasureResult(player, result)
	Events.treasure:fire(player, map.tier)
	if result.kind == "shade" and not result.duplicate then
		local shadeTier = Tiers.byId[result.outcome.tier]
		if shadeTier and shadeTier.order >= Tiers.byId[Treasure.announceFrom].order then
			task.delay(5, function()
				Net.notifyAll(
					`{player.DisplayName} dug up {string.upper(result.outcome.name)} from a {tier.name} treasure!`,
					"rare"
				)
			end)
		end
		DataService.save(player)
	end
end

function TreasureService.start()
	local drops = Treasure.drops
	Events.atePrey:connect(function(player: Player, preyId: string, _position: Vector3)
		local prey = Config.Prey.byId[preyId]
		if prey == nil then
			return
		end
		-- At most `preyPerHour` an hour (the allowance refills, up to `preyBurst`)
		local now = Timing.clock()
		local bucket: Allowance = preyTokens[player] or { tokens = drops.preyBurst, at = now }
		preyTokens[player] = bucket
		bucket.tokens =
			math.min(drops.preyBurst, bucket.tokens + (now - bucket.at) * drops.preyPerHour / 3600)
		bucket.at = now
		if bucket.tokens < 1 then
			return
		end
		local chance = math.min(prey.mass * drops.preyPerKg, drops.preyMax)
		local tiers = if prey.mass >= drops.bigPreyMass then drops.bigPreyTiers else drops.preyTiers
		if tryDrop(player, chance, tiers) then
			bucket.tokens -= 1
		end
	end)
	Events.shells:connect(function(player: Player, value: number)
		if value >= Config.Shells.goldenValue then
			tryDrop(player, drops.goldenShell, drops.goldenShellTiers)
		else
			tryDrop(player, drops.shell, drops.shellTiers)
		end
	end)
	Events.banked:connect(function(player: Player, amount: number, _level: number, worth: number?)
		-- (the Haul before the Haul rate, Config/Tuning `growth`)
		if (worth or amount) >= drops.bankMinMass then
			tryDrop(player, drops.bank, drops.bankTiers)
		end
	end)
	Net.onRequest("FollowMap", follow)
	Net.onRequest("StartDig", startDig)
	Net.onRequest("FinishDig", finishDig)
	StateService.provide(function(_player, data, state)
		state.maps = maps(data)
		state.activeMap = data.activeMap
		state.treasures = data.treasures
	end)
	DataService.releasing:connect(function(player)
		digStarted[player] = nil
		preyTokens[player] = nil
	end)
	if Timing.isStudio() then
		-- Studio testing from the Server command bar (a require there gets its own
		-- module copy, so the real service is reached through _G):
		--   _G.ApexTreasure.give(game.Players.Name, "Captain")
		(_G :: any).ApexTreasure = { give = TreasureService.give }
	end
end

return TreasureService
