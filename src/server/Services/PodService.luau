--!strict
-- Pods (Config/Pvp `pods`, GDD §6): teams of up to 3 made in the POD menu. A player
-- invites another, who accepts or declines within half a minute; leaving (or
-- leaving the server) takes you out, and a pod of one is gone. Podmates can't eat or
-- bite each other (HuntService reads the `Pod` player attribute, so it needn't know
-- this service), a podmate's slipstream is faster (the client), and when one eats a
-- player, the others nearby get a share of the Haul.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local FishService = require(script.Parent.FishService)
local HuntService = require(script.Parent.HuntService)
local StateService = require(script.Parent.StateService)

local tune = Config.Pvp.pods

local PodService = {}

type Pod = { id: number, members: { Player } }
type Invite = { from: Player, pod: number, expires: number }

local pods: { [number]: Pod } = {}
local podOf: { [Player]: Pod } = {}
local invites: { [Player]: Invite } = {} -- the latest invite each player has waiting
local nextId = 1

local function touch(player: Player)
	DataService.markDirty(player)
end

local function setAttribute(player: Player, pod: Pod?)
	player:SetAttribute("Pod", if pod then pod.id else 0)
end

local function leave(player: Player, quiet: boolean?)
	local pod = podOf[player]
	if pod == nil then
		return
	end
	podOf[player] = nil
	local index = table.find(pod.members, player)
	if index then
		table.remove(pod.members, index)
	end
	setAttribute(player, nil)
	touch(player)
	for _, member in pod.members do
		if not quiet then
			Net.notify(member, `{player.DisplayName} left your pod`, "info")
		end
		touch(member)
	end
	if #pod.members <= 1 then
		for _, member in pod.members do
			podOf[member] = nil
			setAttribute(member, nil)
			touch(member)
		end
		pods[pod.id] = nil
	end
end

-- Whether two players are in the same pod
function PodService.together(a: Player, b: Player): boolean
	local pod = podOf[a]
	return pod ~= nil and pod == podOf[b]
end

-- A player's podmates (not themselves)
function PodService.mates(player: Player): { Player }
	local pod = podOf[player]
	local list: { Player } = {}
	if pod then
		for _, member in pod.members do
			if member ~= player then
				table.insert(list, member)
			end
		end
	end
	return list
end

local function invite(player: Player, userId: any)
	if typeof(userId) ~= "number" then
		return
	end
	local target = Players:GetPlayerByUserId(userId)
	if target == nil or target == player or DataService.get(target) == nil then
		return
	end
	local pod = podOf[player]
	if pod and #pod.members >= tune.size then
		return Net.notify(player, `Your pod is full ({tune.size} fish)`, "bad")
	end
	if PodService.together(player, target) then
		return Net.notify(player, `{target.DisplayName} is already in your pod`, "info")
	end
	if podOf[target] then
		return Net.notify(player, `{target.DisplayName} is in another pod`, "bad")
	end
	invites[target] =
		{ from = player, pod = if pod then pod.id else 0, expires = Timing.clock() + tune.inviteSeconds }
	Net.notify(target, `{player.DisplayName} invited you to their pod · open POD to accept`, "good")
	Net.notify(player, `Invited {target.DisplayName} to your pod`, "info")
	touch(target)
end

local function accept(player: Player)
	local offer = invites[player]
	invites[player] = nil
	touch(player)
	if offer == nil or Timing.clock() > offer.expires or offer.from.Parent ~= Players then
		return Net.notify(player, "That invite ran out", "info")
	end
	local from = offer.from
	local pod = podOf[from]
	if pod == nil then
		pod = { id = nextId, members = { from } }
		nextId += 1
		pods[pod.id] = pod
		podOf[from] = pod
		setAttribute(from, pod)
	end
	if #pod.members >= tune.size then
		return Net.notify(player, `{from.DisplayName}'s pod is full`, "bad")
	end
	leave(player, true)
	table.insert(pod.members, player)
	podOf[player] = pod
	setAttribute(player, pod)
	for _, member in pod.members do
		Net.notify(
			member,
			if member == player
				then `You joined {from.DisplayName}'s pod`
				else `{player.DisplayName} joined your pod`,
			"good"
		)
		touch(member)
	end
end

local function decline(player: Player)
	local offer = invites[player]
	invites[player] = nil
	touch(player)
	if offer and offer.from.Parent == Players then
		Net.notify(offer.from, `{player.DisplayName} said no to your pod`, "info")
	end
end

-- A podmate's kill: a share of the eater's gain to each podmate close by
local function shareKill(eater: Player, _victim: Player, gain: number)
	local _, eaterRoot = FishService.character(eater)
	if eaterRoot == nil or gain <= 0 then
		return
	end
	for _, mate in PodService.mates(eater) do
		local _, root = FishService.character(mate)
		if root and (root.Position - eaterRoot.Position).Magnitude <= tune.shareRange then
			local added = HuntService.gain(mate, gain * tune.killShare)
			if added > 0 then
				Net.notify(
					mate,
					`Pod kill by {eater.DisplayName} · +{math.floor(added * 10 + 0.5) / 10} kg Haul`,
					"good"
				)
			end
		end
	end
end

function PodService.start()
	Net.onRequest("PodInvite", invite)
	Net.onRequest("PodAccept", accept)
	Net.onRequest("PodDecline", decline)
	Net.onRequest("PodLeave", function(player: Player)
		if podOf[player] then
			leave(player)
			Net.notify(player, "You left the pod", "info")
		end
	end)
	Events.atePlayer:connect(shareKill)
	Players.PlayerAdded:Connect(function(player)
		setAttribute(player, nil)
	end)
	for _, player in Players:GetPlayers() do
		setAttribute(player, nil)
	end
	Players.PlayerRemoving:Connect(function(player)
		leave(player)
		invites[player] = nil
		for target, offer in invites do
			if offer.from == player then
				invites[target] = nil
				touch(target)
			end
		end
	end)
	-- Invites run out
	Guard.loop("PodService.invites", 2, function()
		local now = Timing.clock()
		for target, offer in invites do
			if now > offer.expires then
				invites[target] = nil
				touch(target)
			end
		end
	end)
	StateService.provide(function(player, _data, state)
		local pod = podOf[player]
		local members: { { id: number, name: string } } = {}
		if pod then
			for _, member in pod.members do
				table.insert(members, { id = member.UserId, name = member.DisplayName })
			end
		end
		local offer = invites[player]
		state.pod = {
			id = if pod then pod.id else 0,
			members = members,
			size = tune.size,
			invite = if offer and offer.from.Parent == Players
				then { from = offer.from.DisplayName, fromId = offer.from.UserId, expires = offer.expires }
				else nil,
		}
	end)
end

return PodService
