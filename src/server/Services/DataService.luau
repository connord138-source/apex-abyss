--!strict
-- Player save data via ProfileStore (session-locked, auto-saving). In an
-- unpublished Studio place ProfileStore falls back to a mock store by itself.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileStore = require(script.Parent.Parent.Packages.ProfileStore)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Catch = require(ReplicatedStorage.Shared.Catch)
local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)

-- One species' own progress (owner: every species levels up separately)
export type SpeciesRecord = {
	mass: number, -- banked mass: the size every dive as this species starts at
	bestMass: number,
	-- Shades are unlocked per fish (owner, 2026-10-08: "the shades will also apply to
	-- all fish interchangeably. They will just need to be unlocked again for that
	-- fish"), and each fish remembers the one it wears (Server/Progress)
	shades: { [string]: boolean }?,
	shade: string?,
}

export type TreasureMap = {
	id: string,
	tier: string, -- Config/Treasure tier id
	site: { x: number, y: number, z: number }, -- the dig spot on the seabed
	hint: string,
	created: number,
}

export type PlayerData = {
	version: number,
	createdAt: number, -- first join
	lastSeen: number,
	mass: number, -- retired: the Nibbler's mass before per-species progress (migrated)
	bestMass: number, -- retired
	species: { [string]: SpeciesRecord }, -- per species (Server/Progress)
	current: string, -- the species the player swims as
	unlocked: { [string]: boolean },
	dna: { [string]: number }, -- per biome, for unlocking species
	tutorial: { step: number, progress: number, done: boolean, v: number? }, -- v: the step list's version (TutorialService; kept out of the template)
	-- The last haul banked, so a Double Haul receipt that lands late (or after a
	-- rejoin) still doubles exactly that amount, once
	lastHaul: { id: number, amount: number, doubled: boolean, species: string? },
	nextHaulId: number,
	-- The Haul lost when last eaten (no Second Chance charm), so a Second Chance
	-- bought on the eaten screen gives exactly that back, once (amount 0 = none)
	lostHaul: { amount: number, at: number },
	stats: {
		preyEaten: number,
		playersEaten: number,
		timesEaten: number,
		banks: number,
		banked: number, -- total mass ever banked
		shells: number, -- shells ever collected
		rolls: number,
		coralEarned: number,
		bossKills: number, -- world boss kills helped with
		bestLevel: number?, -- the best level any fish has reached (achievements)
		apexKills: number?, -- Apex bounties claimed (ApexService)
		bestPrey: string, -- the biggest fish ever eaten (Config/Prey id) and its mass
		bestPreyMass: number,
	},
	-- The den base (Config/Dens): its level, glow and floor, the things placed in it
	-- (Build mode) and how many of each thing are owned, the glows and floors bought
	den: {
		level: number,
		glow: string,
		floor: string,
		owned: { [string]: boolean }, -- "Glow:<id>", "Floor:<id>"
		items: { [string]: number }, -- copies of each thing (placed or in the tray)
		placed: { { uid: number, id: string, x: number, y: number, z: number, r: number, s: string } },
		nextUid: number,
		-- retired: things by slot, before Build mode (DenService moves them into
		-- `placed`, and things bought then, kept in `owned`, into `items`)
		furniture: { [string]: string },
		-- the den's shape the placements were made in (3: the private interiors of
		-- 2026-10-16, 4: the bigger rooms of 2026-10-18; older ones are moved over
		-- once by DenService)
		layout: number?,
		door: string, -- the doorway style on the plaza (Config/Dens doors)
		doors: { [string]: boolean }, -- doorway styles bought
		wings: { [string]: string }, -- wing slot id → wing id (Config/Dens wings)
		openOwned: boolean, -- Open Plan bought
		open: boolean, -- Open Plan on
		tanks: { [string]: { prey: string, rarity: string } }, -- the aquarium's fish by tank id
	},
	coral: number, -- the currency (vendors)
	trophies: { [string]: number }, -- boss currencies (MegalodonTeeth, KrakenBeaks)
	titles: { [string]: boolean }, -- earned titles
	title: string, -- the worn title ("" = none)
	shells: number, -- every Config.Rolls.shellsPerRoll is one roll
	shades: { [string]: boolean }, -- retired: shades before they were per fish (migrated into each record)
	parts: { [string]: boolean }, -- owned body parts (Config/Exotics)
	variants: { [string]: boolean }, -- owned exotic variants
	-- What's worn ("" = nothing); parts by slot
	equipped: { shade: string, variant: string, parts: { [string]: string } },
	trails: { [string]: boolean }, -- boost trails owned (Config/Trails; every fish's)
	trail: string, -- the boost trail worn ("" = none)
	upgrades: { [string]: number }, -- level per upgrade (Config/Shop)
	charms: { [string]: number }, -- stocked charms held (Lucky, SecondChance)
	boosts: { [string]: number }, -- timed charms: Unix time each runs out
	shellTrades: { day: number, count: number }, -- the Tidecharm Trader's daily shell sales
	-- Treasure maps held (Config/Treasure), the one being followed, and the tally
	maps: { TreasureMap },
	activeMap: string,
	treasures: { found: number, byTier: { [string]: number } },
	-- The daily login streak (Config/Daily): the UTC day last claimed, the streak
	-- then, and the longest ever
	daily: { day: number, streak: number, best: number },
	-- The den's Coral Garden (Config/Dens garden): what's grown and not yet
	-- collected, and the Unix time it was last grown to
	garden: { coral: number, shells: number, at: number },
	aquarium: { coral: number, shells: number, at: number, fed: number }, -- (Shared/Aquarium)
	-- Rare catches (Config/Catch): the Catch Log (prey id → rarity id, "Normal" too →
	-- lifetime catches; the skin goals count it, Shared/Catch `goal`) and its finished
	-- rows. `catchTracks` is retired (each fish's own catch track until 2026-10-18,
	-- species id → rarity id → catches as that fish): kept in the save, unused.
	catchLog: { [string]: { [string]: number } },
	catchBest: { [string]: { [string]: number } }, -- prey id → rarity id → the biggest eaten (kg)
	logRows: { [string]: boolean },
	catchTracks: { [string]: { [string]: number } },
	-- Today's bounties (Config/Bounties): the UTC day they're for, each one's id,
	-- goal progress and whether it paid, and whether the chest paid
	bounties: { day: number, list: { { id: string, progress: number, done: boolean } }, chest: boolean },
	-- This week (Shared/Tides.week): leaderboard scores (Config/Leaderboards id →
	-- score), whether the Catch of the Week was caught, and the last week whose
	-- leaderboard titles were checked
	weekly: { week: number, scores: { [string]: number }, featured: boolean },
	lbChecked: number,
	-- The Treasure Wheel (Config/Wheel): spins waiting, and when the free-spin clock
	-- last paid (Unix; 0 = never: a new player's first spin)
	wheel: { spins: number, lastFree: number },
	-- Playtime gifts (Config/Playtime): the UTC day, seconds played that day, how many
	-- gifts on the ladder were claimed, and the last day Premium's free spin came
	playtime: { day: number, seconds: number, claimed: number, premiumDay: number },
	-- The Tide Pass (Config/Pass): the season the record is for, its XP, how many
	-- tiers were claimed on each row, and whether this season's Deep Pass is bought
	pass: { season: number, xp: number, claimedFree: number, claimedPaid: number, paid: boolean },
	-- Achievements done (Config/Achievements id → true), each opening a den
	-- furniture set; marked once, for good (AchievementService)
	achievements: { [string]: boolean },
	-- Named places found (Config/Places id → true; PlacesService), and when each of the
	-- Clam Garden's pearls grows back for this player (its index → Unix time;
	-- LandmarkService)
	places: { [string]: boolean },
	pearls: { [string]: number },
	codes: { [string]: boolean }, -- redeem codes used (Config/Codes)
	-- Monetization
	passes: { [string]: boolean },
	groupRewarded: boolean, -- got the one-time Roblox group reward
	purchaseIds: { string }, -- developer-product receipts already granted (newest last)
	onboarding: number,
}

local TEMPLATE: PlayerData = {
	version = 1,
	createdAt = 0,
	lastSeen = 0,
	mass = 1,
	bestMass = 1,
	species = {},
	current = "Nibbler",
	unlocked = { Nibbler = true },
	dna = {},
	tutorial = { step = 1, progress = 0, done = false },
	lastHaul = { id = 0, amount = 0, doubled = false },
	nextHaulId = 1,
	lostHaul = { amount = 0, at = 0 },
	stats = {
		preyEaten = 0,
		playersEaten = 0,
		timesEaten = 0,
		banks = 0,
		banked = 0,
		shells = 0,
		rolls = 0,
		coralEarned = 0,
		bossKills = 0,
		bestLevel = 1,
		bestPrey = "",
		bestPreyMass = 0,
	},
	den = {
		level = 1,
		glow = "Teal",
		floor = "Flagstone",
		owned = {},
		items = {},
		placed = {},
		nextUid = 1,
		furniture = {},
		-- (no `layout`: Reconcile would hand an old save the new one before
		-- DenService moved its placements over; DenService sets it)
		door = "Stone",
		doors = {},
		-- (2026-10-28: the den expansion) wing slot id → wing id, Open Plan bought and
		-- on, and the aquarium's fish by tank id
		wings = {},
		openOwned = false,
		open = false,
		tanks = {},
	},
	-- The aquarium's earnings waiting (Shared/Aquarium): coral, shells, when it last
	-- grew (Unix) and the UTC day it was last fed
	aquarium = { coral = 0, shells = 0, at = 0, fed = 0 },
	coral = 0,
	trophies = {},
	titles = {},
	title = "",
	shells = 0,
	shades = {},
	parts = {},
	variants = {},
	equipped = { shade = "", variant = "", parts = {} },
	trails = {},
	trail = "",
	upgrades = {},
	charms = {},
	boosts = {},
	shellTrades = { day = 0, count = 0 },
	maps = {},
	activeMap = "",
	treasures = { found = 0, byTier = {} },
	daily = { day = 0, streak = 0, best = 0 },
	garden = { coral = 0, shells = 0, at = 0 },
	catchLog = {},
	catchBest = {},
	logRows = {},
	catchTracks = {},
	bounties = { day = 0, list = {}, chest = false },
	weekly = { week = 0, scores = {}, featured = false },
	lbChecked = 0,
	wheel = { spins = 0, lastFree = 0 },
	playtime = { day = 0, seconds = 0, claimed = 0, premiumDay = 0 },
	pass = { season = 0, xp = 0, claimedFree = 0, claimedPaid = 0, paid = false },
	achievements = {},
	places = {},
	pearls = {},
	codes = {},
	passes = {},
	groupRewarded = false,
	purchaseIds = {},
	onboarding = 0,
}

-- Studio reads and writes the live game's DataStores, so Studio sessions use their
-- own store and never touch real saves.
local STORE_NAME = if Timing.isStudio() then "PlayerData_Studio_v1" else "PlayerData_v1"
local store = ProfileStore.New(STORE_NAME, TEMPLATE :: any)
local profiles: { [Player]: any } = {}
local dirty: { [Player]: boolean } = {}

local DataService = {
	-- (player, data) — fired after a profile loads; listeners run in connect order
	loaded = Signal.new(),
	-- (player, data) — fired right before the session ends so services can clean up
	releasing = Signal.new(),
}

function DataService.get(player: Player): PlayerData?
	local profile = profiles[player]
	return if profile then profile.Data :: PlayerData else nil
end

function DataService.loadedPlayers(): { [Player]: PlayerData }
	local result: { [Player]: PlayerData } = {}
	for player, profile in profiles do
		result[player] = profile.Data :: PlayerData
	end
	return result
end

-- Flags the player's state for replication on the next StateService flush.
function DataService.markDirty(player: Player)
	dirty[player] = true
end

function DataService.takeDirty(): { Player }
	local list: { Player } = {}
	for player in dirty do
		table.insert(list, player)
	end
	table.clear(dirty)
	return list
end

local PURCHASE_ID_CACHE = 100

-- Grants a developer product exactly once, the way ProfileStore recommends: the
-- receipt's PurchaseId is recorded in the save alongside the grant, and Roblox is
-- only told "granted" once a save containing it has gone through. If the server
-- dies first, Roblox retries the receipt later and the recorded id stops a double
-- grant. `grant` changes the player's data; it runs at most once per PurchaseId.
function DataService.processPurchase(
	player: Player,
	purchaseId: string,
	grant: (PlayerData) -> ()
): Enum.ProductPurchaseDecision
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = profile.Data :: PlayerData
	if table.find(data.purchaseIds, purchaseId) == nil then
		local ok, problem = pcall(function(): any
			grant(data)
			return nil
		end)
		if not ok then
			warn(`[DataService] purchase {purchaseId} failed to grant: {problem}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		while #data.purchaseIds >= PURCHASE_ID_CACHE do
			table.remove(data.purchaseIds, 1)
		end
		table.insert(data.purchaseIds, purchaseId)
		dirty[player] = true
	end
	-- Wait for a save that includes it
	local decision: Enum.ProductPurchaseDecision? = nil
	local function check()
		local saved = profile.LastSavedData
		if saved and saved.purchaseIds and table.find(saved.purchaseIds, purchaseId) then
			decision = Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	check()
	if decision then
		return decision
	end
	local connection = profile.OnAfterSave:Connect(check)
	profile:Save()
	local deadline = os.clock() + 30
	local nextSave = os.clock() + 10
	while decision == nil and profile:IsActive() and os.clock() < deadline do
		task.wait()
		if os.clock() >= nextSave then
			nextSave = os.clock() + 10
			profile:Save() -- the first save may have been throttled
		end
	end
	connection:Disconnect()
	return decision or Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Saves a player's data now (after something that must not be lost in a crash).
function DataService.save(player: Player)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		profile:Save()
	end
end

local function onPlayerAdded(player: Player)
	-- Give up after a minute (ProfileStore's own timeout is off when Cancel is set)
	local started = os.clock()
	local profile = store:StartSessionAsync(
		`Player_{player.UserId}`,
		{
			Cancel = function()
				return player.Parent ~= Players or os.clock() - started > 60
			end,
		} :: any
	)
	if profile == nil then
		player:Kick("Could not load your data — please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		-- The session ended under us (loaded on another server, or the lock was
		-- lost): let services clean up as if the player left
		if profiles[player] == profile then
			DataService.releasing:fire(player, profile.Data)
			profiles[player] = nil
			dirty[player] = nil
		end
		if player.Parent == Players and not ProfileStore.IsClosing then
			player:Kick("Your data was loaded on another server — please rejoin.")
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	local data = profile.Data :: PlayerData
	if data.createdAt == 0 then
		data.createdAt = Timing.now()
	end
	-- Saves from before per-species progress: their size becomes the Nibbler's
	if data.species.Nibbler == nil then
		data.species.Nibbler = { mass = math.max(data.mass, 1), bestMass = math.max(data.bestMass, 1) }
	end
	data.unlocked.Nibbler = true
	-- Saves from before shades were per fish: every fish the player has gets the
	-- shades they owned, and the current one keeps wearing its shade
	if next(data.shades) ~= nil then
		for id in data.unlocked do
			local record = data.species[id]
			if record == nil then
				local start = Config.Tuning.size.startMass
				record = { mass = start, bestMass = start }
				data.species[id] = record
			end
			local owned = record.shades or {}
			for shadeId in data.shades do
				owned[shadeId] = true
			end
			record.shades = owned
		end
		local worn = data.equipped.shade
		local current = data.species[data.current]
		if current and worn ~= "" then
			current.shade = worn
		end
		table.clear(data.shades)
	end
	-- Skin lines per fish (owner, 2026-10-10): a fish keeps its own line's skins and
	-- the ones every fish can have; any other skin it held turns into its coral
	for id, record in data.species do
		local owned = record.shades
		if owned then
			for shadeId in owned do
				if not Config.Shades.fits(shadeId, id) then
					owned[shadeId] = nil
					local shade = Config.Shades.byId[shadeId]
					data.coral += if shade then shade.refund else 0
					if record.shade == shadeId then
						record.shade = ""
					end
				end
			end
		end
	end
	if not Config.Shades.fits(data.equipped.shade, data.current) then
		data.equipped.shade = ""
	end
	-- Catch skins are every fish's (owner, 2026-10-18: "Once the skin is unlocked, it
	-- is unlocked for all of their fish"): each goal the Catch Log meets (checked again
	-- on every join, so a changed rule or a skin added later lands), and any catch skin
	-- one fish earned on the old per-fish catch tracks, go on every playable fish,
	-- the ones not unlocked yet too. Nothing is taken away.
	local owned: { [string]: { [string]: boolean }? } = {}
	for id, record in data.species do
		owned[id] = record.shades
	end
	for _, skin in Catch.accountSkins(data.catchLog, owned) do
		if Config.Shades.byId[skin] == nil then
			continue
		end
		for _, species in Config.Species.list do
			local record = data.species[species.id]
			if record == nil then
				local start = Config.Tuning.size.startMass
				record = { mass = start, bestMass = start }
				data.species[species.id] = record
			end
			local shades = record.shades or {}
			shades[skin] = true
			record.shades = shades
		end
	end

	profiles[player] = profile
	DataService.loaded:fire(player, data)
	dirty[player] = true
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end
	local data = profile.Data :: PlayerData
	data.lastSeen = Timing.now()
	DataService.releasing:fire(player, data)
	profiles[player] = nil
	dirty[player] = nil
	profile:EndSession()
end

function DataService.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return DataService
