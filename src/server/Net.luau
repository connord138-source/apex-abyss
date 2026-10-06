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
local banked = makeEvent("Banked") -- (summary) to the banker
local eaten = makeEvent("Eaten") -- (summary) to the fish that got eaten
local hit = makeEvent("Hit") -- (attackerUserId, victimUserId, damage) to everyone, for effects

-- Each request: its minimum seconds between calls from one player
local REQUESTS: { [string]: number } = {
	EatPrey = 0.05, -- ({ { index: number, at: number } }) batched by the client
	EatPlayer = 0.2, -- (userId)
	Bite = 0.35, -- (userId)
}
local requests: { [string]: RemoteEvent } = {}
for name in REQUESTS do
	requests[name] = makeEvent(name)
end

local getEaten = Instance.new("RemoteFunction")
getEaten.Name = "GetEaten" -- () -> { [string]: number } prey index -> back-at time
getEaten.Parent = folder

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
	local character = player.Character
	if character then
		character:PivotTo(cframe)
	end
	teleport:FireClient(player, cframe)
end

function Net.preyEaten(index: number, backAt: number, eaterUserId: number)
	preyEaten:FireAllClients(index, backAt, eaterUserId)
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

function Net.onGetEaten(handler: (Player) -> { [string]: number })
	getEaten.OnServerInvoke = handler
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
