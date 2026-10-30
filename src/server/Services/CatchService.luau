--!strict
-- Rare catches (Config/Catch; owner, 2026-10-10: "random rarities of fish that can be
-- eaten for more towards the haul or like 10 total unlocks a skin"; 2026-10-18: "They
-- will need atleast 10 gold of 5 different species to unlock the skin. Once the skin
-- is unlocked, it is unlocked for all of their fish").
--
-- Which prey fish swim rare. Every player out in the biomes brings their own stream
-- of rare fish, set swimming out of everyone's sight and fading when they've had
-- their time (Shared/RareSpawn, run here every `spawn.tick` s). Every client is told
-- which fish are rare (`PreyRarity`) and draws them so (SchoolController);
-- HuntService takes a fish's rarity when it's eaten and pays its Haul, then this pays
-- the rest: coral, the Catch Log, the skin goals (Shared/Catch `goal`: a skin for
-- every fish), the Catch of the Week, and the server announcements.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Biomes = require(ReplicatedStorage.Shared.Biomes)
local Catch = require(ReplicatedStorage.Shared.Catch)
local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local RareSpawn = require(ReplicatedStorage.Shared.RareSpawn)
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

local spawner = RareSpawn.new(math.floor(os.clock() * 1000) % 1000003 + 1)
local respawning: { [number]: number } = {} -- prey index → clock when it's back
local sendIndices: { number } = {}
local sendCodes: { number } = {}
local NEWS_GAP = 45 -- seconds between "a Prism fish shimmers" announcements
local lastNews = -math.huge

local function send(index: number, id: string?)
	table.insert(sendIndices, index)
	table.insert(sendCodes, if id then CatchConfig.codes[id] else 0)
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

-- A Prism fish is news (one a while: with a full server there's one a minute)
local function spawned(index: number, id: string)
	local def = CatchConfig.byId[id]
	local now = Timing.clock()
	if def and def.announce.spawn and now - lastNews >= NEWS_GAP then
		lastNews = now
		local prey = Config.Prey.byId[Schools.fish[index].prey]
		Net.notifyAll(
			`A {string.upper(def.name)} {string.upper(if prey then prey.name else "fish")} shimmers in {where(
				index
			)}!`,
			"rare"
		)
	end
end

local function eatenUntil(index: number): number?
	return respawning[index]
end

local function tick()
	local now = Timing.clock()
	local unix = Timing.unix()
	local tide, startedAt = Tides.at(unix)
	-- Eaten fish that are back (one picked while it was eaten comes back rare)
	for index, backAt in respawning do
		if backAt <= now then
			respawning[index] = nil
			local id = RareSpawn.respawned(spawner, index, now)
			if id and Schools.out(index, tide.id) then
				send(index, id)
				spawned(index, id)
			elseif id then
				RareSpawn.set(spawner, index, nil, now)
			end
		end
	end
	-- Who's out hunting (not in the hub or a den), and where everyone is
	local hunters: { RareSpawn.Hunter } = {}
	local everyone: { Vector3 } = {}
	for _, player in Players:GetPlayers() do
		local character, root = FishService.character(player)
		if character == nil or root == nil then
			continue
		end
		local position = root.Position
		table.insert(everyone, position)
		if Layout.inHub(position) then
			continue
		end
		local length = character:GetAttribute("Length")
		local biome = Biomes.at(position)
		table.insert(hunters, {
			id = player.UserId,
			position = position,
			length = if typeof(length) == "number" then length else 2,
			deep = biome ~= nil and biome.deep == true,
		})
	end
	local changes = RareSpawn.step(
		spawner,
		CatchConfig.spawn.tick,
		now,
		unix,
		tide.id,
		unix - startedAt,
		hunters,
		everyone,
		eatenUntil
	)
	for _, change in changes do
		send(change.index, change.rarity)
		if change.rarity then
			spawned(change.index, change.rarity)
		end
	end
	flush()
	-- The stream's counts so far, for playtests (Workspace.RareSpawn: Placed_<rarity>,
	-- Failed_<rarity>, Capped_<rarity> and Swimming_<rarity>)
	local board = workspace:FindFirstChild("RareSpawn")
	if board == nil then
		board = Instance.new("Folder")
		board.Name = "RareSpawn"
		board.Parent = workspace
	end
	for _, rarity in CatchConfig.rarities do
		local id = rarity.id
		local stats = spawner.stats
		for key, count in
			{
				Placed = stats.placed[id] or 0,
				Failed = stats.failed[id] or 0,
				Capped = stats.capped[id] or 0,
				Swimming = spawner.count[id] or 0,
			}
		do
			local name = `{key}_{id}`
			if (board :: Instance):GetAttribute(name) ~= count then
				(board :: Instance):SetAttribute(name, count)
			end
		end
	end
end

-- The rarity of fish `index` as it's eaten (nil = plain): taken off it; it comes
-- back at `backAt` (HuntService), plain unless it's picked meanwhile.
function CatchService.take(index: number, backAt: number): string?
	local id = RareSpawn.take(spawner, index)
	if id then
		send(index, nil)
	end
	respawning[index] = backAt
	flush()
	return id
end

function CatchService.rarityOf(index: number): string?
	return RareSpawn.rarityOf(spawner, index)
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
		RareSpawn.set(spawner, nearest[i].index, rarityId, now)
		send(nearest[i].index, rarityId)
		made += 1
	end
	flush()
	return made
end

-- Unlocks a catch skin for every fish the player has or will have (the playable
-- species all get it now, the way a Tide Pass skin does); false if they all had it
-- or the skin isn't in Config/Shades yet
function CatchService.grantEveryFish(data: PlayerData, skin: string): boolean
	if Config.Shades.byId[skin] == nil then
		return false
	end
	local new = false
	for _, species in Config.Species.list do
		new = Progress.grantShade(data, skin, species.id) or new
	end
	return new
end

-- Every catch skin whose goal the player's Catch Log has met, on every fish (and any
-- catch skin one fish earned on the old per-fish tracks: DataService does that on
-- load). The skins that were new.
local function checkGoals(data: PlayerData): { string }
	local got: { string } = {}
	for _, rarityId in Catch.met(data.catchLog) do
		local skin = CatchConfig.byId[rarityId].skin
		if CatchService.grantEveryFish(data, skin) then
			table.insert(got, skin)
		end
	end
	return got
end

-- Testing (the admin panel): `count` catches of `rarityId` on prey `preyId`'s Catch
-- Log row, or on each of the first `spread` prey species; unlocks the skin when its
-- goal is met. What it did, in words.
function CatchService.addCatches(
	player: Player,
	rarityId: string,
	preyId: string?,
	spread: number,
	count: number
): string
	local data = DataService.get(player)
	local def = CatchConfig.byId[rarityId]
	if data == nil or def == nil then
		return "no data"
	end
	local targets: { string } = {}
	if preyId and Config.Prey.byId[preyId] then
		table.insert(targets, preyId)
	else
		for i, prey in Config.Prey.list do
			if i > spread then
				break
			end
			table.insert(targets, prey.id)
		end
	end
	for _, id in targets do
		local row: { [string]: number } = data.catchLog[id] or {}
		data.catchLog[id] = row
		row[rarityId] = (row[rarityId] or 0) + count
		if (row.Normal or 0) == 0 then
			row.Normal = 1
		end
		-- A biggest catch where there's none yet, at the fish's usual mass, so the den's
		-- Trophy Gallery has something to show in a test
		local best: { [string]: number } = data.catchBest[id] or {}
		data.catchBest[id] = best
		local prey = Config.Prey.byId[id]
		best[rarityId] = best[rarityId] or (if prey then prey.mass else 1)
	end
	Events.trophies:fire(player) -- (the den's Trophy Gallery)
	local got = checkGoals(data)
	DataService.markDirty(player)
	-- The goal-met banner, as a real catch shows it (PC 2026-10-19, UN1: the admin add
	-- unlocked the skin with no banner); no catch toast with it
	if table.find(got, def.skin) then
		Net.caught(
			player,
			{ prey = targets[#targets], rarity = rarityId, skin = def.skin, unlockOnly = true }
		)
	end
	local done, _, met = Catch.goal(data.catchLog, rarityId)
	return `{player.DisplayName}: +{count} {rarityId} on {#targets} species · {done}/{def.unlock.species} species at {def.unlock.each}{if met
		then " · goal met"
		else ""}{if #got > 0 then ` · unlocked {table.concat(got, ", ")}` else ""}`
end

local function grantTitle(data: PlayerData, title: string): boolean
	if data.titles[title] then
		return false
	end
	data.titles[title] = true
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
		-- A rare record goes up in the den's Trophy Gallery (PC 2026-11-02, DE5: it
		-- waited for a full den rebuild)
		if rarityId ~= "Normal" then
			Events.trophies:fire(player)
		end
	end
	if first then
		local coral = CatchConfig.firstCatch[rarityId] or 0
		EconomyService.addCoral(player, coral)
		summary.first = coral
		if not data.logRows[preyId] and Catch.rowDone(row) then
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
		-- The skin goal: `each` of this rarity from each of `species` prey species
		local done, _, met = Catch.goal(data.catchLog, rarityId)
		summary.count = row[rarityId]
		summary.each = def.unlock.each
		summary.done = done
		summary.need = def.unlock.species
		if met and CatchService.grantEveryFish(data, def.skin) then
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
			summary.species = species
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
	Net.onGetRarities(function(): { [string]: number }
		local result: { [string]: number } = {}
		for index, rare in spawner.rare do
			result[tostring(index)] = CatchConfig.codes[rare.rarity]
		end
		return result
	end)
	Events.caught:connect(onCaught)
	-- (every goal is checked again on each join: DataService)
	Guard.loop("CatchService.tick", CatchConfig.spawn.tick, tick)
	StateService.provide(function(_player, data, state)
		state.catchLog = data.catchLog
		state.catchBest = data.catchBest
		state.logRows = data.logRows
		state.weeklyFeatured = Weekly.record(data).featured
	end)
end

return CatchService
