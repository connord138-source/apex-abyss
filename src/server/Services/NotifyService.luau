--!strict
-- Notifications to players who aren't playing (Config/Social notify; owner,
-- 2026-11-03): Roblox experience notifications, sent through Open Cloud with the
-- experience's API key Secret. Two kinds:
--
--  * One waiting for each player who leaves: their Coral Garden full, or failing
--    that their free wheel spins back, whichever comes first (`soonest` to `latest`
--    after leaving). It waits in a memory store sorted by when it's due, so any
--    server can send it; coming back cancels it.
--  * Now: a friend they invited finished the tutorial (ReferralService).
--
-- Roblox sends at most one a day per experience, only to players 13+ who allowed
-- them (the client asks: MenuController.openNotify), and only once the game has 100
-- visits. A message whose id is "" isn't sent; in Studio nothing is sent unless an
-- admin test asks (it prints what would go instead).
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local GardenService = require(script.Parent.GardenService)
local StateService = require(script.Parent.StateService)

type PlayerData = DataService.PlayerData

local tune = Config.Social.notify
local Wheel = Config.Wheel

local URL = "https://apis.roblox.com/cloud/v2/users/%d/notifications"
local DUE_EVERY = 60 -- seconds between looks for notifications that are due
local BATCH = 20

-- The sorted map of notifications waiting, opened on first use: opening it throws in
-- an unpublished place, and at require time that stopped every service after this one
-- (PC 2026-11-03)
local waitingMap: MemoryStoreSortedMap? = nil
local function waiting(): MemoryStoreSortedMap?
	if waitingMap == nil then
		local ok, map = pcall(
			MemoryStoreService.GetSortedMap,
			MemoryStoreService,
			if Timing.isStudio() then "Notify_Studio_v1" else "Notify_v1"
		)
		waitingMap = if ok then map else nil
	end
	return waitingMap
end

local NotifyService = {}

local lastWarned: { [string]: number } = {}
local function warnOnce(key: string, text: string)
	local now = os.clock()
	if now - (lastWarned[key] or -math.huge) >= 300 then
		lastWarned[key] = now
		warn(text)
	end
end

-- Sends one notification now; true if Roblox took it (not that it was delivered).
-- `force`: send from Studio too (the admin test).
function NotifyService.send(
	userId: number,
	kind: string,
	params: { [string]: string }?,
	force: boolean?
): boolean
	local message = (tune.messages :: any)[kind]
	if message == nil or message.id == "" then
		return false
	end
	if Timing.isStudio() and not force then
		print(`[Notify] would send {kind} to {userId}: {message.text}`)
		return true
	end
	local found, secret = pcall(HttpService.GetSecret, HttpService, tune.secret)
	if not found then
		warnOnce(
			"secret",
			`[Notify] no Secret named "{tune.secret}" (Creator Hub → the experience → Secrets)`
		)
		return false
	end
	local parameters: { [string]: any } = {}
	for name, value in params or {} do
		parameters[name] = { stringValue = value }
	end
	local universe = if game.GameId ~= 0 then game.GameId else tune.universe
	local body = HttpService:JSONEncode({
		source = { universe = `universes/{universe}` },
		payload = {
			type = "MOMENT",
			messageId = message.id,
			parameters = parameters,
			joinExperience = { launchData = `notify:{kind}` },
			analyticsData = { category = message.category },
		},
	})
	local ok, response = pcall(HttpService.RequestAsync, HttpService, {
		Url = string.format(URL, userId),
		Method = "POST",
		Headers = { ["content-type"] = "application/json", ["x-api-key"] = secret },
		Body = body,
	})
	if not ok then
		warnOnce("request", `[Notify] {response} (Game Settings → Security → Allow HTTP Requests?)`)
		return false
	end
	if not response.Success then
		warnOnce(`status{response.StatusCode}`, `[Notify] {response.StatusCode}: {response.Body}`)
		return false
	end
	if Timing.isStudio() then
		print(`[Notify] sent {kind} to {userId}`)
	end
	return true
end

-- What to send a player who's leaving now, and when (nil: nothing)
function NotifyService.plan(
	player: Player,
	data: PlayerData,
	now: number
): (string?, number, { [string]: string })
	local best: string? = nil
	local due = math.huge
	local params: { [string]: string } = {}
	-- The Coral Garden, full: from what's in it at the garden's away rate
	local rates = GardenService.rates(player, data)
	if tune.messages.garden.id ~= "" and rates.capCoral > 0 and rates.coralPerHour > 0 then
		local left = math.max(0, rates.capCoral - data.garden.coral)
		best = "garden"
		due = now + math.max(tune.soonest, left / rates.coralPerHour * 3600)
		params = { coral = Format.number(math.floor(rates.capCoral)) }
	end
	-- The free wheel spins, all back (only if they've used some)
	if tune.messages.spins.id ~= "" and data.wheel.spins < Wheel.maxFree and data.wheel.lastFree > 0 then
		local back = data.wheel.lastFree + (Wheel.maxFree - data.wheel.spins) * Wheel.freeEvery
		local at = math.max(now + tune.soonest, back)
		if at < due then
			best = "spins"
			due = at
			params = {}
		end
	end
	if best == nil or due > now + tune.latest then
		return nil, 0, {}
	end
	return best, due, params
end

local function schedule(player: Player, data: PlayerData)
	local now = Timing.now()
	local kind, due, params = NotifyService.plan(player, data, now)
	if kind == nil then
		return
	end
	local map = waiting()
	if map == nil then
		return
	end
	local key = tostring(player.UserId)
	local ok, problem =
		pcall(map.SetAsync, map, key, { kind = kind, params = params }, math.floor(due - now) + 86400, due)
	if not ok then
		warnOnce("schedule", `[Notify] couldn't keep one for later: {problem}`)
	elseif Timing.isStudio() then
		print(`[Notify] {player.Name}: {kind} in {math.floor((due - now) / 60)} min`)
	end
end

local function cancel(userId: number)
	local map = waiting()
	if map then
		pcall(map.RemoveAsync, map, tostring(userId))
	end
end

-- Sends what's due. Each one is claimed first, so two servers don't both send it.
local function sendDue()
	local map = waiting()
	if map == nil then
		return
	end
	local now = Timing.now()
	local ok, items = pcall(map.GetRangeAsync, map, Enum.SortDirection.Ascending, BATCH, nil, {
		sortKey = now,
	})
	if not ok or typeof(items) ~= "table" then
		return
	end
	for _, item in items do
		local key = item.key
		local userId = tonumber(key)
		if userId == nil or Players:GetPlayerByUserId(userId) then
			cancel(userId or 0)
			continue
		end
		local claimed, entry = pcall(map.UpdateAsync, map, key, function(old: any, sortKey: any)
			if typeof(old) ~= "table" or old.claimed then
				return nil
			end
			old.claimed = game.JobId
			return old, sortKey
		end, 300)
		if claimed and typeof(entry) == "table" and entry.claimed == game.JobId then
			NotifyService.send(userId, entry.kind, entry.params)
			cancel(userId)
		end
	end
end

function NotifyService.start()
	-- Back in the game: nothing to tell them
	DataService.loaded:connect(function(player: Player)
		task.spawn(cancel, player.UserId)
	end)
	-- (after GardenService's releasing handler, which grows the garden to now)
	DataService.releasing:connect(function(player: Player, data: PlayerData)
		task.spawn(Guard.run, "NotifyService.schedule", schedule, player, data)
	end)
	Guard.loop("NotifyService.due", DUE_EVERY + math.random() * 10, sendDue)
	-- Our card asking whether they'd like notifications (once a month at most)
	Net.onRequest("NotifyAsked", function(player: Player)
		local data = DataService.get(player)
		if data then
			data.notify.asked = Timing.now()
			DataService.markDirty(player)
		end
	end)
	StateService.provide(function(_player, data, state)
		state.notifyAsk = data.tutorial.done
			and data.stats.banks >= tune.askAfterBanks
			and Timing.now() - data.notify.asked >= tune.askAgain
	end)
end

-- Admin testing: what would be sent if this player left now, sent at once
function NotifyService.test(player: Player): string
	local data = DataService.get(player)
	if data == nil then
		return "No data"
	end
	local kind, due, params = NotifyService.plan(player, data, Timing.now())
	if kind == nil then
		return "Nothing to send (no message ids in Config/Social, or nothing waiting)"
	end
	local sent = NotifyService.send(player.UserId, kind, params, true)
	return `{kind} (due in {math.floor((due - Timing.now()) / 60)} min): {if sent
		then "sent"
		else "not sent, see the Output"}`
end

return NotifyService
