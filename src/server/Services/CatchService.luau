--!strict
-- Rare catches (Config/Catch; owner, 2026-10-10: "random rarities of fish that can be
-- eaten for more towards the haul or like 10 total unlocks a skin").
--
-- Which prey fish swim rare. A fish's rarity is rolled when it respawns, and fish no
-- one is near are re-rolled now and then, so the sea keeps changing and the tide's
-- odds reach every school (Shared/Catch, Config/Tides). Every client is told which
-- fish are rare (`PreyRarity`) and draws them so (SchoolController); HuntService
-- takes a fish's rarity when it's eaten and pays its Haul, then this pays the rest:
-- coral, the Catch Log, the fish's catch track (its skin at `track` catches), the
-- Catch of the Week, and the server announcements.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Biomes = require(ReplicatedStorage.Shared.Biomes)
local Catch = require(ReplicatedStorage.Shared.Catch)
local Config = require(ReplicatedStorage.Shared.Config)
local Schools = require(ReplicatedStorage.Shared.Schools)
local Tides = require(ReplicatedStorage.Shared.Tides)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
local Weekly = require(script.Parent.Parent.Weekly)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local StateService = require(script.Parent.StateService)

type PlayerData = DataService.PlayerData

local CatchConfig = Config.Catch

local CatchService = {}

local rarity: { [number]: string } = {} -- prey index → rarity id (rare fish only)
local respawning: { [number]: number } = {} -- prey index → clock when it's back (rolled then)
local deep: { [number]: boolean } = {} -- school index → swims in a deep biome
local sendIndices: { number } = {}
local sendCodes: { number } = {}
local rng = Random.new()
local cursor = 0 -- the rotation's place in the fish list

local function setRarity(index: number, id: string?)
	if rarity[index] == id then
		return
	end
	local code = 0
	if id then
		rarity[index] = id
		code = CatchConfig.codes[id]
	else
		rarity[index] = nil
	end
	table.insert(sendIndices, index)
	table.insert(sendCodes, code)
end

local function flush()
	if #sendIndices > 0 then
		Net.preyRarity(sendIndices, sendCodes)
		sendIndices, sendCodes = {}, {}
	end
end

local function where(index: number): string
	local school = Schools.list[Schools.fish[index].school]
	local biome = Biomes.at(school.center)
	return if biome then `the {biome.name}` else "the sea"
end

local function roll(index: number, tideId: string, unix: number): string?
	local fish = Schools.fish[index]
	local chances = Catch.chances(fish.prey, tideId, deep[fish.school] == true, unix)
	return Catch.roll(rng:NextNumber(), chances)
end

-- A fish (re)spawning with a new roll; a Prism fish is news
local function spawned(index: number, tideId: string, unix: number)
	local id = roll(index, tideId, unix)
	setRarity(index, id)
	local def = if id then CatchConfig.byId[id] else nil
	if def and def.announce.spawn then
		local prey = Config.Prey.byId[Schools.fish[index].prey]
		Net.notifyAll(
			`A {string.upper(def.name)} {string.upper(prey.name)} shimmers in {where(index)}!`,
			"rare"
		)
	end
end

local function nearAnyone(position: Vector3, clearance: number): boolean
	for _, player in Players:GetPlayers() do
		local _, root = FishService.character(player)
		if root and (root.Position - position).Magnitude < clearance then
			return true
		end
	end
	return false
end

local function tick()
	local now = Timing.clock()
	local unix = Timing.unix()
	local tide, startedAt = Tides.at(unix)
	-- Eaten fish that are back
	for index, backAt in respawning do
		if backAt <= now then
			respawning[index] = nil
			if Schools.out(index, tide.id) then
				spawned(index, tide.id, unix)
			end
		end
	end
	-- Re-roll a few fish nobody's near (three times as many just after the tide
	-- turns, so its fish show up early in its 20 minutes)
	local rotate = CatchConfig.rotate
	local quota = rotate.perTick * (if unix - startedAt < 120 then 3 else 1)
	local done = 0
	for _ = 1, Schools.COUNT do
		if done >= quota then
			break
		end
		cursor = cursor % Schools.COUNT + 1
		local index = cursor
		if respawning[index] then
			continue
		end
		if not Schools.out(index, tide.id) then
			setRarity(index, nil)
			continue
		end
		if nearAnyone(Schools.position(index, now), rotate.clearance) then
			continue
		end
		done += 1
		spawned(index, tide.id, unix)
	end
	flush()
end

-- The rarity of fish `index` as it's eaten (nil = plain): taken off it, and a new
-- one is rolled when it respawns at `backAt` (HuntService).
function CatchService.take(index: number, backAt: number): string?
	local id = rarity[index]
	setRarity(index, nil)
	respawning[index] = backAt
	flush()
	return id
end

function CatchService.rarityOf(index: number): string?
	return rarity[index]
end

-- Testing (the admin panel): the `count` prey fish nearest `position` turn `rarityId`
function CatchService.forceNear(position: Vector3, rarityId: string, count: number): number
	if CatchConfig.byId[rarityId] == nil then
		return 0
	end
	local now = Timing.clock()
	local tide = Tides.at(Timing.unix())
	local nearest: { { index: number, distance: number } } = {}
	for index = 1, Schools.COUNT do
		if not respawning[index] and Schools.out(index, tide.id) then
			table.insert(
				nearest,
				{ index = index, distance = (Schools.position(index, now) - position).Magnitude }
			)
		end
	end
	table.sort(nearest, function(a, b)
		return a.distance < b.distance
	end)
	local made = 0
	for i = 1, math.min(count, #nearest) do
		setRarity(nearest[i].index, rarityId)
		made += 1
	end
	flush()
	return made
end

-- Testing (the admin panel): `count` catches of `rarityId` on the catch track of the
-- fish a player swims as, unlocking its skin at the track's count
function CatchService.addTrack(player: Player, rarityId: string, count: number): string?
	local data = DataService.get(player)
	local def = CatchConfig.byId[rarityId]
	if data == nil or def == nil then
		return nil
	end
	local species = Progress.speciesId(data)
	local track = data.catchTracks[species] or {}
	data.catchTracks[species] = track
	track[rarityId] = (track[rarityId] or 0) + count
	local unlocked = track[rarityId] >= def.track and Progress.grantShade(data, def.skin, species)
	DataService.markDirty(player)
	return if unlocked then def.skin else ""
end

local function grantTitle(data: PlayerData, title: string): boolean
	if data.titles[title] then
		return false
	end
	data.titles[title] = true
	return true
end

-- A finished Catch Log row: every rarity of one prey species caught at least once
local function rowDone(row: { [string]: number }): boolean
	if (row.Normal or 0) == 0 then
		return false
	end
	for _, def in CatchConfig.rarities do
		if (row[def.id] or 0) == 0 then
			return false
		end
	end
	return true
end

local function onCaught(player: Player, preyId: string, rarityId: string, _position: Vector3, mass: number)
	local data = DataService.get(player)
	local prey = Config.Prey.byId[preyId]
	if data == nil or prey == nil then
		return
	end
	local unix = Timing.unix()
	local species = Progress.speciesId(data)
	local summary: { [string]: any } = { prey = preyId, rarity = rarityId }
	-- The Catch Log: a first catch pays, and so does a finished row
	local row = data.catchLog[preyId] or {}
	data.catchLog[preyId] = row
	local first = (row[rarityId] or 0) == 0
	row[rarityId] = (row[rarityId] or 0) + 1
	-- The biggest of each species at each rarity (owner, 2026-10-10: "track their
	-- biggest eat of each species and rarity of species too")
	local best = data.catchBest[preyId] or {}
	data.catchBest[preyId] = best
	local before = best[rarityId] or 0
	summary.mass = mass
	if mass > before then
		best[rarityId] = mass
		if before > 0 then
			summary.record = before
		end
	end
	if first then
		local coral = CatchConfig.firstCatch[rarityId] or 0
		EconomyService.addCoral(player, coral)
		summary.first = coral
		if not data.logRows[preyId] and rowDone(row) then
			data.logRows[preyId] = true
			EconomyService.addCoral(player, CatchConfig.rowComplete.coral)
			EconomyService.addShells(player, CatchConfig.rowComplete.shells)
			summary.row = true
			local all = true
			for _, def in Config.Prey.list do
				if not data.logRows[def.id] then
					all = false
					break
				end
			end
			if all and grantTitle(data, CatchConfig.logTitle) then
				summary.title = CatchConfig.logTitle
				Net.notifyAll(`{player.DisplayName} finished the Catch Log: {CatchConfig.logTitle}!`, "rare")
			end
		end
	end
	local def = CatchConfig.byId[rarityId]
	if def then
		-- Coral, the tide's bonus on top
		local tide = Tides.at(unix)
		summary.coral = EconomyService.earnCoral(player, Catch.coral(rarityId, mass) * (tide.coral or 1))
		-- The catch track of the fish we're swimming as
		local track = data.catchTracks[species] or {}
		data.catchTracks[species] = track
		track[rarityId] = (track[rarityId] or 0) + 1
		summary.track = track[rarityId]
		summary.need = def.track
		summary.species = species
		if track[rarityId] >= def.track and Progress.grantShade(data, def.skin, species) then
			summary.skin = def.skin
		end
		if def.announce.catch then
			Net.notifyAll(
				`{player.DisplayName} caught a {string.upper(def.name)} {string.upper(prey.name)}!`,
				"rare"
			)
		end
	end
	-- The Catch of the Week: the first one this week pays big and unlocks its skin
	local featured = Catch.weekly(unix)
	if featured and featured.prey == preyId and featured.rarity == rarityId then
		summary.weekly = true
		local record = Weekly.record(data)
		if not record.featured then
			record.featured = true
			EconomyService.addCoral(player, featured.coral)
			EconomyService.addShells(player, featured.shells)
			data.wheel.spins += Config.Wheel.weekly
			summary.weeklySpins = Config.Wheel.weekly
			summary.weeklyCoral = featured.coral
			summary.weeklyShells = featured.shells
			if Progress.grantShade(data, featured.skin, species) then
				summary.weeklySkin = featured.skin
			end
			Net.notifyAll(
				`{player.DisplayName} caught this week's {string.upper(rarityId)} {string.upper(prey.name)}!`,
				"rare"
			)
		end
	end
	DataService.markDirty(player)
	-- Only what's news goes to the client (a plain minnow eaten isn't)
	if summary.first or def or summary.record or summary.weekly or summary.row then
		Net.caught(player, summary)
	end
end

function CatchService.start()
	-- Which schools swim in the deep (a Bioluminescent Night glows brighter there)
	for index, school in Schools.list do
		local biome = Biomes.at(school.center)
		deep[index] = biome ~= nil and biome.deep
	end
	-- Every fish starts with a roll
	local unix = Timing.unix()
	local tide = Tides.at(unix)
	for index = 1, Schools.COUNT do
		local id = if Schools.out(index, tide.id) then roll(index, tide.id, unix) else nil
		if id then
			rarity[index] = id
		end
	end
	Net.onGetRarities(function(): { [string]: number }
		local result: { [string]: number } = {}
		for index, id in rarity do
			result[tostring(index)] = CatchConfig.codes[id]
		end
		return result
	end)
	Events.caught:connect(onCaught)
	Guard.loop("CatchService.tick", CatchConfig.rotate.seconds, tick)
	StateService.provide(function(_player, data, state)
		state.catchLog = data.catchLog
		state.catchBest = data.catchBest
		state.logRows = data.logRows
		state.catchTracks = data.catchTracks
		state.weeklyFeatured = Weekly.record(data).featured
	end)
end

return CatchService
