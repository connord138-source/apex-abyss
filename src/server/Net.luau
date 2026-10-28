--!strict
-- Remotes. Server -> client: state snapshots, toasts, world events (prey eaten,
-- banking, being eaten). Client -> server: requests (eats, bites). Every request
-- argument is untrusted, so each handler validates it, and requests are rate
-- limited per player and kind.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local function makeEvent(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local stateUpdate = makeEvent("StateUpdate")
local notify = makeEvent("Notify")
local teleport = makeEvent("Teleport") -- (cframe) move your own fish there
local preyEaten = makeEvent("PreyEaten") -- (index, backAt, eaterUserId) to everyone
local preyChase = makeEvent("PreyChase") -- (index, targetUserId, startAt, seconds, hit) to everyone: a prey fish turns on a player
local banked = makeEvent("Banked") -- (summary) to the banker
local eaten = makeEvent("Eaten") -- (summary) to the fish that got eaten
local hit = makeEvent("Hit") -- (attackerUserId, victimUserId, damage) to everyone, for effects
local shellResult = makeEvent("ShellResult") -- (index, backAt) 0 = not allowed, show it again
local rollResult = makeEvent("RollResult") -- (result) to the roller
local forageEaten = makeEvent("ForageEaten") -- (index, backAt, eaterUserId) to everyone
local treasureResult = makeEvent("TreasureResult") -- (result) to the digger
local predatorEvent = makeEvent("PredatorEvent") -- (kind, index, payload) to everyone: windup, bite, hurt, died, spawned
local bossState = makeEvent("BossState") -- (state) to everyone: the world boss event (warning, active, gone)
local bossReward = makeEvent("BossReward") -- (summary) to a player who helped kill a boss
local shove = makeEvent("Shove") -- (velocity) to a player: a push from a creature (its client adds it)
local gardenCollected = makeEvent("GardenCollected") -- (summary) to the den's owner: the Coral Garden paid out
local dailyClaimed = makeEvent("DailyClaimed") -- (summary) to the claimer: a daily streak reward
local preyRarity = makeEvent("PreyRarity") -- ({ index }, { code }) to everyone: prey fish turned rare (code 0 = plain again)
local caught = makeEvent("Caught") -- (summary) to the catcher: a rare catch, a first in the Catch Log, track progress, a skin unlocked
local tideChanged = makeEvent("TideChanged") -- (tideId, endsAt) to everyone: the tide turned
local passClaimed = makeEvent("PassClaimed") -- (summary) to the claimer: Tide Pass rewards claimed
local achievement = makeEvent("Achievement") -- (summary) to the player: an achievement done and the den set it opened
local chum = makeEvent("Chum") -- (kind, payload) to everyone: chum clouds and the Whale Fall (add, eat, remove, warn)
local hooks = makeEvent("Hooks") -- ({ boats }) to everyone: the fishing boats and their lines, about once a second
-- (kind, index, payload) the biome landmarks: a bell rang, a cannon fired (LandmarkService).
-- Not "Landmark": that's the request's name, and two remotes of one name let a client's
-- WaitForChild find either (PC 2026-10-22: bites on the bell and swims into the cannon
-- went to this event, which no server code hears)
local landmark = makeEvent("LandmarkEvent")
-- Predator positions stream ~10 times a second; a dropped packet doesn't matter
local predatorState = Instance.new("UnreliableRemoteEvent")
predatorState.Name = "PredatorState"
predatorState.Parent = folder

-- Each request: its minimum seconds between calls from one player
local REQUESTS: { [string]: number } = {
	EatPrey = 0.05, -- ({ { index: number, at: number } }) batched by the client
	Bite = 0.35, -- (userId)
	BiteWhale = 0.3, -- (lane) a mouthful off a passing humpback (CompanionService)
	Collect = 0.03, -- (shell spot index)
	EatForage = 0.05, -- ({ number }) forage spot indexes, batched by the client
	EatChum = 0.05, -- ({ { cloudId, chunkIndex } }) chum chunks, batched by the client
	PodInvite = 1, -- (userId) ask another player into your pod
	PodAccept = 0.5, -- () join the pod you were invited to
	PodDecline = 0.5, -- () turn the invite down
	PodLeave = 0.5, -- () leave your pod
	TakeBait = 0.3, -- (hookId) swallow a hook's bait (and get hooked)
	StruggleHook = 0.05, -- () mash to break free of a hook
	BiteLine = 0.3, -- (userId) bite a hooked podmate's line
	Roll = 0.4, -- ()
	Buy = 0.2, -- (kind: "upgrade" | "charm" | "dye" | "shells", id: string)
	Equip = 0.15, -- (kind: "shade" | "part" | "variant", id: string ("" = take off), slot: string?)
	SelectSpecies = 0.5, -- (speciesId) swim as another unlocked species (in the safe zone)
	UnlockSpecies = 0.5, -- (speciesId) unlock with its biome's DNA and coral
	FollowMap = 0.3, -- (mapId or "") follow a treasure map, or stop
	StartDig = 0.4, -- () begin digging at the followed map's X
	FinishDig = 0.4, -- () the dig hold completed
	UseWrap = 0.3, -- () use a Kelp Wrap (heal)
	UseItem = 0.3, -- (id) use an item from the item wheel (Config/Shop items)
	BitePredator = 0.35, -- (predator index) bite an AI predator or boss
	Struggle = 0.05, -- () mash to break a boss's grab (0.12 dropped fast mashing, playtest 2026-10-08)
	DenUpgrade = 0.5, -- () the den's next level
	DenBuy = 0.2, -- (itemId) one more of a den thing, into the Build tray
	DenPlace = 0.12, -- (itemId, surface, x, y, z, yaw) a thing from the tray into the den
	DenMove = 0.12, -- (uid, surface, x, y, z, yaw) a placed thing somewhere else
	DenLayout = 0.5, -- (setId, x, y, z, facing) a set's starter layout from the tray
	DenStore = 0.12, -- (uid) a placed thing back into the tray (0: everything)
	DenColor = 0.25, -- (glowId) the den's glow color
	DenFloor = 0.25, -- (floorId) the decks' stone
	DenDoor = 0.25, -- (doorId) the doorway style on the plaza (bought once, then worn)
	EnterDen = 0.5, -- (index) swam into that den's doorway portal on the plaza
	LeaveDen = 0.5, -- () swam into the way out on your den's front wall
	Prestream = 4, -- () near a portal: stream the far side in ahead of the swim through
	UseAbility = 0.3, -- (abilityId) the fish's signature ability (Config/Abilities)
	EndAbility = 0.3, -- () come out of a Burrow
	ClaimDaily = 1, -- () today's daily streak reward
	ClaimGift = 0.5, -- () the next playtime gift that's ready (Config/Playtime)
	ClaimPass = 0.5, -- () every Tide Pass reward unlocked and not yet claimed (Config/Pass)
	WatchAd = 3, -- () a rewarded video ad (its reward: Double Haul on a small Haul)
	SpinWheel = 0.3, -- (all: boolean) spend a Treasure Wheel spin at its button (or join the line; all = Spin all)
	TutorialSaw = 1, -- ("Index") the tutorial's last step: the INDEX was opened
	AdmireDen = 1, -- (index) admire the den you're visiting: a heart for its owner, once a day (HeartService)
	Companion = 1, -- ("turtle" | "ray") a sea turtle joined us, or we flushed a resting ray (Config/Companions)
	Landmark = 0.25, -- ("bell" | "cannon" | "pearl", index) bit the galleon's bell or a clam's pearl, swam into the Bay Cannon (LandmarkService)
	StartShot = 1.5, -- (shotIndex, schoolIndex, showingShot, showingSchool) the start screen's next shot: stream its water in (StartService)
	StartDone = 1, -- () dived in from the start screen
}
local requests: { [string]: RemoteEvent } = {}
for name in REQUESTS do
	requests[name] = makeEvent(name)
end

local getEaten = Instance.new("RemoteFunction")
getEaten.Name = "GetEaten" -- () -> { [string]: number } prey index -> back-at time
getEaten.Parent = folder

local getForage = Instance.new("RemoteFunction")
getForage.Name = "GetForage" -- () -> { positions, kinds, eaten }
getForage.Parent = folder

local getRarities = Instance.new("RemoteFunction")
getRarities.Name = "GetRarities" -- () -> { [string]: number } prey index -> rarity code
getRarities.Parent = folder

local getBoards = Instance.new("RemoteFunction")
getBoards.Name = "GetBoards" -- () -> the weekly leaderboards (LeaderboardService)
getBoards.Parent = folder

local getChum = Instance.new("RemoteFunction")
getChum.Name = "GetChum" -- () -> { clouds, warn } the chum clouds and any Whale Fall coming
getChum.Parent = folder

local redeem = Instance.new("RemoteFunction")
redeem.Name = "RedeemCode" -- (text) -> (ok, message): a redeem code (Config/Codes)
redeem.Parent = folder

local getShells = Instance.new("RemoteFunction")
getShells.Name = "GetShells" -- () -> { positions, golden, hidden }
getShells.Parent = folder

folder.Parent = ReplicatedStorage

local NOTIFY_REPEAT = 1 -- the same toast goes to a player at most this often
local lastRequest: { [Player]: { [string]: number } } = {}
local lastNotify: { [Player]: { text: string, at: number } } = {}
Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
	lastNotify[player] = nil
end)

export type NotifyKind = "info" | "good" | "bad" | "rare"

local Net = {}

-- Sends the fields of a player's state that changed (StateService); `cleared`
-- lists fields that are now nil, and `full` says to start from an empty state.
function Net.sendState(player: Player, changes: { [string]: any }, cleared: { string }, full: boolean)
	stateUpdate:FireClient(player, changes, cleared, full)
end

function Net.notify(player: Player, text: string, kind: NotifyKind?)
	local now = os.clock()
	local last = lastNotify[player]
	if last and last.text == text and now - last.at < NOTIFY_REPEAT then
		return
	end
	lastNotify[player] = { text = text, at = now }
	notify:FireClient(player, text, kind or "info")
end

-- Moves a player's fish on the server and on their own client. The client owns
-- its fish's physics, so a server-only move can be undone by its next frame.
function Net.teleport(player: Player, cframe: CFrame)
	player:SetAttribute("MovedAt", os.clock()) -- (SpeedService: not the player's own swimming)
	local character = player.Character
	if character then
		character:PivotTo(cframe)
	end
	teleport:FireClient(player, cframe)
end

function Net.preyEaten(index: number, backAt: number, eaterUserId: number)
	preyEaten:FireAllClients(index, backAt, eaterUserId)
end

-- A prey fish chases a player (AggroService): clients draw the dart.
function Net.preyChase(index: number, targetUserId: number, startAt: number, seconds: number)
	preyChase:FireAllClients(index, targetUserId, startAt, seconds)
end

function Net.banked(player: Player, summary: { [string]: any })
	banked:FireClient(player, summary)
end

function Net.eaten(player: Player, summary: { [string]: any })
	eaten:FireClient(player, summary)
end

function Net.hit(attacker: Player, victim: Player, damage: number)
	hit:FireAllClients(attacker.UserId, victim.UserId, damage)
end

-- A hit from something that isn't a player (a creature): `sourceId` is negative.
function Net.hitBy(victim: Player, sourceId: number, damage: number)
	hit:FireAllClients(sourceId, victim.UserId, damage)
end

function Net.onGetEaten(handler: (Player) -> { [string]: number })
	getEaten.OnServerInvoke = handler
end

-- The admin panel (Admin.luau): (action, target, ...) → a line of text
local adminRemote = Instance.new("RemoteFunction")
adminRemote.Name = "Admin"
adminRemote.Parent = folder

function Net.onAdmin(handler: (Player, any, any, ...any) -> string)
	adminRemote.OnServerInvoke = handler
end

function Net.onGetForage(handler: (Player) -> { [string]: any })
	getForage.OnServerInvoke = handler
end

function Net.forageEaten(index: number, backAt: number, eaterUserId: number)
	forageEaten:FireAllClients(index, backAt, eaterUserId)
end

function Net.onGetShells(handler: (Player) -> { [string]: any })
	getShells.OnServerInvoke = handler
end

function Net.shellResult(player: Player, index: number, backAt: number)
	shellResult:FireClient(player, index, backAt)
end

function Net.rollResult(player: Player, result: { [string]: any })
	rollResult:FireClient(player, result)
end

function Net.treasureResult(player: Player, result: { [string]: any })
	treasureResult:FireClient(player, result)
end

function Net.predatorStateTo(player: Player, packet: { [string]: any })
	predatorState:FireClient(player, packet)
end

function Net.predatorEvent(kind: string, index: number, payload: { [string]: any })
	predatorEvent:FireAllClients(kind, index, payload)
end

function Net.bossState(state: { [string]: any })
	bossState:FireAllClients(state)
end

function Net.bossStateTo(player: Player, state: { [string]: any })
	bossState:FireClient(player, state)
end

function Net.bossReward(player: Player, summary: { [string]: any })
	bossReward:FireClient(player, summary)
end

-- Pushes a player's fish (a tail sweep, a shockwave): the client owns its physics,
-- so it adds the velocity itself.
function Net.shove(player: Player, velocity: Vector3)
	player:SetAttribute("MovedAt", os.clock())
	shove:FireClient(player, velocity)
end

function Net.gardenCollected(player: Player, summary: { [string]: any })
	gardenCollected:FireClient(player, summary)
end

function Net.passClaimed(player: Player, summary: { [string]: any })
	passClaimed:FireClient(player, summary)
end

function Net.achievement(player: Player, summary: { [string]: any })
	achievement:FireClient(player, summary)
end

function Net.dailyClaimed(player: Player, summary: { [string]: any })
	dailyClaimed:FireClient(player, summary)
end

-- Prey fish whose rarity changed (Config/Catch codes; 0 = plain again), to everyone.
function Net.preyRarity(indices: { number }, codes: { number })
	preyRarity:FireAllClients(indices, codes)
end

function Net.onGetRarities(handler: (Player) -> { [string]: number })
	getRarities.OnServerInvoke = handler
end

function Net.chum(kind: string, payload: { [string]: any })
	chum:FireAllClients(kind, payload)
end

function Net.hooks(payload: { [string]: any })
	hooks:FireAllClients(payload)
end

-- A landmark event for everyone (a bell rang, a cannon boomed) or one player (their
-- cannon shot: the aim and speed their client drives)
function Net.landmark(kind: string, index: number, payload: { [string]: any })
	landmark:FireAllClients(kind, index, payload)
end

function Net.landmarkTo(player: Player, kind: string, index: number, payload: { [string]: any })
	landmark:FireClient(player, kind, index, payload)
end

function Net.onGetChum(handler: (Player) -> { [string]: any })
	getChum.OnServerInvoke = handler
end

function Net.onRedeem(handler: (Player, any) -> (boolean, string))
	redeem.OnServerInvoke = handler
end

function Net.onGetBoards(handler: (Player) -> { [string]: any })
	getBoards.OnServerInvoke = handler
end

function Net.caught(player: Player, summary: { [string]: any })
	caught:FireClient(player, summary)
end

function Net.tideChanged(tideId: string, endsAt: number)
	tideChanged:FireAllClients(tideId, endsAt)
end

-- A toast for everyone (rare rolls).
function Net.notifyAll(text: string, kind: NotifyKind?)
	notify:FireAllClients(text, kind or "info")
end

-- Handles one kind of client request. The handler gets the raw, untrusted arguments.
function Net.onRequest(name: string, handler: (Player, ...any) -> ())
	local interval = REQUESTS[name]
	assert(interval, `unknown request {name}`)
	requests[name].OnServerEvent:Connect(function(player: Player, ...: any)
		local now = os.clock()
		local last = lastRequest[player] or {}
		lastRequest[player] = last
		if now - (last[name] or 0) < interval then
			return
		end
		last[name] = now
		handler(player, ...)
	end)
end

return Net
