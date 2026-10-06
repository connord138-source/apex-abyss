--!strict
-- Player save data via ProfileStore (session-locked, auto-saving). In an
-- unpublished Studio place ProfileStore falls back to a mock store by itself.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileStore = require(script.Parent.Parent.Packages.ProfileStore)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Timing = require(ReplicatedStorage.Shared.Timing)

-- One species' own progress (owner: every species levels up separately)
export type SpeciesRecord = {
	mass: number, -- banked mass: the size every dive as this species starts at
	bestMass: number,
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
	tutorial: { step: number, progress: number, done: boolean },
	-- The last haul banked, so a Double Haul receipt that lands late (or after a
	-- rejoin) still doubles exactly that amount, once
	lastHaul: { id: number, amount: number, doubled: boolean },
	nextHaulId: number,
	stats: {
		preyEaten: number,
		playersEaten: number,
		timesEaten: number,
		banks: number,
		banked: number, -- total mass ever banked
		shells: number, -- shells ever collected
		rolls: number,
		coralEarned: number,
	},
	coral: number, -- the currency (vendors)
	shells: number, -- every Config.Rolls.shellsPerRoll is one roll
	shades: { [string]: boolean }, -- owned (Config/Shades)
	parts: { [string]: boolean }, -- owned body parts (Config/Exotics)
	variants: { [string]: boolean }, -- owned exotic variants
	-- What's worn ("" = nothing); parts by slot
	equipped: { shade: string, variant: string, parts: { [string]: string } },
	upgrades: { [string]: number }, -- level per upgrade (Config/Shop)
	charms: { [string]: number }, -- stocked charms held (Lucky, SecondChance)
	boosts: { [string]: number }, -- timed charms: Unix time each runs out
	shellTrades: { day: number, count: number }, -- the Tidecharm Trader's daily shell sales
	-- Monetization
	passes: { [string]: boolean },
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
	stats = {
		preyEaten = 0,
		playersEaten = 0,
		timesEaten = 0,
		banks = 0,
		banked = 0,
		shells = 0,
		rolls = 0,
		coralEarned = 0,
	},
	coral = 0,
	shells = 0,
	shades = {},
	parts = {},
	variants = {},
	equipped = { shade = "", variant = "", parts = {} },
	upgrades = {},
	charms = {},
	boosts = {},
	shellTrades = { day = 0, count = 0 },
	passes = {},
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
