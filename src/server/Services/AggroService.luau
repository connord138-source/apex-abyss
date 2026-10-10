--!strict
-- Prey that outsize a player turn on them (owner, 2026-10-07: "the fish that the
-- player cannot eat yet because they are too small need to briefly chase the player
-- at a slow speed and hurt them if they get too close"). Prey fish follow shared
-- paths (Shared/Schools), so a chase is a short, shared detour: the server picks a
-- fish near a player that it outsizes, tells every client when the chase starts,
-- and at the lunge moment checks (on the same curve the clients draw) whether the
-- fish reached the player; if so it nips them for a share of max health.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Schools = require(ReplicatedStorage.Shared.Schools)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local FishService = require(script.Parent.FishService)
local HuntService = require(script.Parent.HuntService)

local aggro = Config.Tuning.aggro
local hunt = Config.Tuning.hunt

type Chase = {
	index: number,
	target: Player,
	startAt: number,
	lunged: boolean,
}

local AggroService = {}

local chases: { Chase } = {}
local fishReadyAt: { [number]: number } = {} -- fish index → clock it may chase again
local playerReadyAt: { [Player]: number } = {}
local accumulator = 0

local function lengthOf(character: Model): number
	local length = character:GetAttribute("Length")
	return if typeof(length) == "number" then length else 2
end

-- The nearest prey fish within range that outsizes this player
local function pickFish(root: BasePart, length: number, now: number): number?
	local best: number? = nil
	local bestDistance = aggro.range
	for schoolIndex, school in Schools.list do
		if (school.center - root.Position).Magnitude > school.radius + school.spread + aggro.range + 20 then
			continue
		end
		local schoolFrame = Schools.schoolFrame(schoolIndex, now)
		for index = school.first, school.first + school.count - 1 do
			local fish = Schools.fish[index]
			if fish.length < length * aggro.ratio or (fishReadyAt[index] or 0) > now then
				continue
			end
			if HuntService.preyEaten(index, now) then
				continue
			end
			local distance = (Schools.fishFrame(index, schoolFrame, now).Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = index, distance
			end
		end
	end
	return best
end

local function startChases(now: number)
	for player, session in HuntService.sessions() do
		if
			not session.alive
			or session.inHub
			or session.safeUntil > now
			or (playerReadyAt[player] or 0) > now
		then
			continue
		end
		local character, root = FishService.character(player)
		if character == nil or root == nil then
			continue
		end
		local index = pickFish(root, lengthOf(character), now)
		if index == nil then
			continue
		end
		fishReadyAt[index] = now + aggro.cooldown
		playerReadyAt[player] = now + aggro.seconds + aggro.playerCooldown
		table.insert(chases, { index = index, target = player, startAt = now, lunged = false })
		Net.preyChase(index, player.UserId, now, aggro.seconds)
	end
end

local function lunge(chase: Chase, now: number)
	local player = chase.target
	local session = HuntService.sessions()[player]
	local character, root = FishService.character(player)
	if session == nil or character == nil or root == nil or not session.alive or session.inHub then
		return
	end
	if HuntService.preyEaten(chase.index, now) then
		return
	end
	local fish = Schools.fish[chase.index]
	local length = lengthOf(character)
	local blend = Schools.chaseBlend(now - chase.startAt, aggro.seconds, aggro.lungeAt)
	local at =
		Schools.chasePosition(chase.index, Schools.position(chase.index, now), root.Position, length, blend)
	-- Latency slack: the player sees themselves a little ahead of where we do
	local slack = Size.topSpeed(length) * hunt.latencySeconds
	if (at - root.Position).Magnitude <= fish.length * 0.5 + length * 0.35 + aggro.reach + slack then
		local prey = Config.Prey.byId[fish.prey]
		local fraction = math.min(aggro.fraction + aggro.perKg * fish.mass, aggro.maxFraction)
		HuntService.damage(player, fraction, `a {prey.name}`)
	end
end

local function step(now: number)
	for i = #chases, 1, -1 do
		local chase = chases[i]
		if not chase.lunged and now >= chase.startAt + aggro.lungeAt then
			chase.lunged = true
			Guard.run("AggroService.lunge", lunge, chase, now)
		end
		if now >= chase.startAt + aggro.seconds then
			table.remove(chases, i)
		end
	end
	startChases(now)
end

function AggroService.start()
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.2 then
			return
		end
		accumulator = 0
		Guard.run("AggroService.step", step, Timing.clock())
	end)
	DataService.releasing:connect(function(player)
		playerReadyAt[player] = nil
		for i = #chases, 1, -1 do
			if chases[i].target == player then
				table.remove(chases, i)
			end
		end
	end)
end

return AggroService
