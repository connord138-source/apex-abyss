--!strict
-- Hunt & Haul on the server: checks every eat and bite, keeps each player's
-- Haul for the dive, grows them live, banks the Haul at their own den, and
-- handles a fish being eaten (it loses its Haul and respawns in its den).
--
-- Clients detect eats themselves (it must feel instant) and the server checks
-- each one: the prey is where the shared path says at that moment, near enough to
-- the eater's mouth (with slack for latency), small enough to swallow, and not
-- already eaten.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Schools = require(ReplicatedStorage.Shared.Schools)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local ShellService = require(script.Parent.ShellService)
local StateService = require(script.Parent.StateService)

local hunt = Config.Tuning.hunt
local swim = Config.Tuning.swim
local economy = Config.Tuning.economy
local hub = Config.World.hub

type Session = {
	haul: number,
	health: number,
	lastHitAt: number,
	lastBiteAt: number,
	safeUntil: number,
	inHub: boolean,
	alive: boolean,
	-- Who bit this fish recently (userId → clock), for the school bonus
	bitBy: { [number]: number },
}

local HuntService = {}

local sessions: { [Player]: Session } = {}
local keptHaul: { [Player]: number } = {} -- a Second Chance's Haul, for the next spawn
local eatenUntil: { [number]: number } = {} -- prey index → clock when it's back

local function newSession(): Session
	return {
		haul = 0,
		health = hunt.health,
		lastHitAt = 0,
		lastBiteAt = 0,
		safeUntil = Timing.clock() + hunt.spawnProtection,
		inHub = true,
		alive = true,
		bitBy = {},
	}
end

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

-- The fish's live length (banked mass plus Haul, capped).
local function liveLength(player: Player): number?
	local data = DataService.get(player)
	local session = sessions[player]
	if data == nil or session == nil then
		return nil
	end
	return Size.length(Size.liveMass(data.mass, session.haul))
end

local function refreshSize(player: Player)
	local length = liveLength(player)
	if length then
		FishService.setLength(player, length)
	end
	local character = FishService.character(player)
	local session = sessions[player]
	if character and session then
		character:SetAttribute("Haul", session.haul)
	end
	DataService.markDirty(player)
end

local function isSafe(session: Session, now: number): boolean
	return session.inHub or now < session.safeUntil
end

-- How far the server's view of a fish may trail where its owner really has it.
local function slack(length: number): number
	-- 1.25: room for Strong Fins
	return Size.topSpeed(length) * 1.25 * swim.boostMultiplier * swim.lungeSpeed * hunt.latencySeconds
		+ hunt.reachSlack
end

local function mouthOf(root: BasePart, length: number): Vector3
	return root.CFrame:PointToWorldSpace(Size.mouthOffset(length))
end

local function addHaul(player: Player, amount: number)
	local session = sessions[player]
	if session then
		session.haul += amount
		refreshSize(player)
	end
end

-- A fish is eaten: its Haul is lost (part of it goes to the eater) and it
-- respawns in its den.
local function eatPlayer(victim: Player, eater: Player)
	local victimSession = sessions[victim]
	local eaterSession = sessions[eater]
	local victimData = DataService.get(victim)
	local eaterLength = liveLength(eater)
	local victimLength = liveLength(victim)
	if
		victimSession == nil
		or eaterSession == nil
		or victimData == nil
		or eaterLength == nil
		or victimLength == nil
	then
		return
	end
	local lost = victimSession.haul
	-- A Second Chance charm keeps the Haul (the eater only gets the base share)
	local saved = lost > 0 and (victimData.charms.SecondChance or 0) > 0
	if saved then
		victimData.charms.SecondChance -= 1
		keptHaul[victim] = lost
		lost = 0
	end
	-- Eating much smaller players pays almost nothing, so farming new fish is pointless
	local ratio = math.clamp(victimLength / eaterLength / hunt.swallowRatio, 0, 1)
	local farm = math.max(ratio * ratio, 0.02)
	local gain = (lost * hunt.playerHaulShare + victimData.mass * hunt.playerBaseShare) * farm
	EconomyService.addCoral(eater, economy.eatPlayerCoral * farm)
	victimSession.haul = 0
	victimSession.alive = false
	victimData.stats.timesEaten += 1
	local eaterData = DataService.get(eater)
	if eaterData then
		eaterData.stats.playersEaten += 1
	end
	Net.hit(eater, victim, -1)
	Net.eaten(victim, {
		by = eater.DisplayName,
		lost = lost,
		saved = if saved then keptHaul[victim] else nil,
		respawn = hunt.respawnSeconds,
	})
	Net.notify(eater, `You ate {victim.DisplayName}!`, "good")
	FishService.respawnIn(victim, hunt.respawnSeconds)
	DataService.markDirty(victim)
	addHaul(eater, gain)
end

local function onEatPrey(player: Player, batch: any)
	if typeof(batch) ~= "table" or #batch > 12 then
		return
	end
	local session = sessions[player]
	local data = DataService.get(player)
	local _, root = FishService.character(player)
	local length = liveLength(player)
	if session == nil or data == nil or root == nil or length == nil or not session.alive then
		return
	end
	local now = Timing.clock()
	local mouth = mouthOf(root, length)
	local allowance = Size.reach(length) + slack(length)
	local gained = 0
	for _, entry in batch do
		if typeof(entry) ~= "table" then
			continue
		end
		local index, at = entry[1], entry[2]
		if not finite(index) or not finite(at) or index % 1 ~= 0 or index < 1 or index > Schools.COUNT then
			continue
		end
		if at < now - 1 or at > now + 0.25 or (eatenUntil[index] or 0) > now then
			continue
		end
		local fish = Schools.fish[index]
		if not Size.canSwallow(length * 1.03, fish.length) then
			continue
		end
		if (Schools.position(index, at) - mouth).Magnitude > allowance + fish.radius then
			continue
		end
		local prey = Config.Prey.byId[fish.prey]
		local backAt = now + prey.respawn
		eatenUntil[index] = backAt
		Net.preyEaten(index, backAt, player.UserId)
		gained += prey.mass * hunt.preyGain * Perks.feast(data.boosts, Timing.now())
		data.stats.preyEaten += 1
		local shells = ShellService.preyDrop(player, prey.id)
		if shells > 0 then
			Net.notify(player, `The {prey.name} had {shells} shell{if shells == 1 then "" else "s"}!`, "good")
		end
	end
	if gained > 0 then
		addHaul(player, gained)
	end
end

local function targetOf(player: Player, userId: any): (Player?, Session?, BasePart?)
	if not finite(userId) then
		return nil, nil, nil
	end
	local target = Players:GetPlayerByUserId(userId)
	if target == nil or target == player then
		return nil, nil, nil
	end
	local session = sessions[target]
	local _, root = FishService.character(target)
	if session == nil or root == nil or not session.alive then
		return nil, nil, nil
	end
	return target, session, root
end

-- Swallowing a smaller player whole.
local function onEatPlayer(player: Player, userId: any)
	local session = sessions[player]
	local _, root = FishService.character(player)
	local length = liveLength(player)
	local target, targetSession, targetRoot = targetOf(player, userId)
	if
		session == nil
		or root == nil
		or length == nil
		or target == nil
		or targetSession == nil
		or targetRoot == nil
	then
		return
	end
	local now = Timing.clock()
	if not session.alive or isSafe(session, now) or isSafe(targetSession, now) then
		return
	end
	local targetLength = liveLength(target)
	if targetLength == nil or not Size.canSwallow(length * 1.03, targetLength) then
		return
	end
	local distance = (targetRoot.Position - mouthOf(root, length)).Magnitude
	if distance > Size.reach(length) + targetLength * 0.4 + slack(length) + slack(targetLength) then
		return
	end
	eatPlayer(target, player)
end

-- A bite on a fish too big to swallow. Small fish do little alone, but every
-- other fish that bit the same target in the last few seconds adds to the damage
-- (schooling).
local function onBite(player: Player, userId: any)
	local session = sessions[player]
	local _, root = FishService.character(player)
	local length = liveLength(player)
	local target, targetSession, targetRoot = targetOf(player, userId)
	if
		session == nil
		or root == nil
		or length == nil
		or target == nil
		or targetSession == nil
		or targetRoot == nil
	then
		return
	end
	local now = Timing.clock()
	if not session.alive or now - session.lastBiteAt < swim.biteCooldown * 0.8 then
		return
	end
	if isSafe(session, now) or isSafe(targetSession, now) then
		return
	end
	local targetLength = liveLength(target)
	if targetLength == nil then
		return
	end
	local distance = (targetRoot.Position - mouthOf(root, length)).Magnitude
	if distance > Size.reach(length) + targetLength * 0.45 + slack(length) + slack(targetLength) then
		return
	end
	session.lastBiteAt = now
	local school = 0
	for otherId, at in targetSession.bitBy do
		if otherId ~= player.UserId and now - at < 2.5 then
			school += 1
		end
	end
	targetSession.bitBy[player.UserId] = now
	local ratio = math.clamp((length / targetLength) ^ 2, 0.04, 1.5)
	local attackerData = DataService.get(player)
	local jaw = Perks.bite(if attackerData then attackerData.upgrades else nil)
	local damage = hunt.biteDamage * ratio * (1 + 0.35 * school) * jaw
	targetSession.health -= damage
	targetSession.lastHitAt = now
	Net.hit(player, target, damage)
	local character = FishService.character(target)
	if character then
		character:SetAttribute("Health", math.max(targetSession.health, 0))
	end
	if targetSession.health <= 0 then
		eatPlayer(target, player)
	end
end

local function bank(player: Player, session: Session, data: DataService.PlayerData)
	local amount = session.haul * hunt.bankMultiplier * Perks.bank(data.upgrades)
	local coral = math.floor(economy.bankCoral * math.sqrt(amount))
	local levelBefore = Size.level(data.mass)
	data.mass += amount
	data.bestMass = math.max(data.bestMass, data.mass)
	data.lastHaul = { id = data.nextHaulId, amount = amount, doubled = false }
	data.nextHaulId += 1
	data.stats.banks += 1
	data.stats.banked += amount
	session.haul = 0
	local levelAfter = Size.level(data.mass)
	EconomyService.addCoral(player, coral)
	Net.banked(player, {
		amount = amount,
		coral = coral,
		mass = data.mass,
		levelBefore = levelBefore,
		level = levelAfter,
		stage = Size.stage(levelAfter),
	})
	refreshSize(player)
end

-- Banking, the hub's safe zone and healing, a few times a second.
local function tick()
	local now = Timing.clock()
	for player, session in sessions do
		Guard.run("HuntService.tick", function()
			local character, root = FishService.character(player)
			local data = DataService.get(player)
			if character == nil or root == nil or data == nil or not session.alive then
				return
			end
			local inHub = Layout.inHub(root.Position)
			if session.inHub and not inHub then
				session.safeUntil = math.max(session.safeUntil, now + hunt.leaveHubProtection)
				character:SetAttribute("SafeUntil", session.safeUntil)
			end
			if inHub ~= session.inHub then
				session.inHub = inHub
				character:SetAttribute("InHub", inHub)
				DataService.markDirty(player)
			end
			if session.health < hunt.health and now - session.lastHitAt > hunt.regenDelay then
				session.health = math.min(hunt.health, session.health + hunt.regenPerSecond * 0.2)
				character:SetAttribute("Health", session.health)
			end
			local den = FishService.denOf(player)
			if den and session.haul > 0 then
				local length = liveLength(player) or 1
				local offset = root.Position - Layout.poolPosition(den)
				local flat = Vector2.new(offset.X, offset.Z).Magnitude
				if flat < hub.poolRadius + length * 0.4 and math.abs(offset.Y) < hub.denHeight then
					bank(player, session, data)
				end
			end
		end)
	end
end

-- Where a player's mouth is, how long their fish is and how far the server's view
-- of it may trail (for food checks elsewhere: ForageService). Nil when the fish
-- can't eat right now (dead, respawning).
function HuntService.mouth(player: Player): (Vector3?, number, number)
	local session = sessions[player]
	local _, root = FishService.character(player)
	local length = liveLength(player)
	if session == nil or root == nil or length == nil or not session.alive then
		return nil, 0, 0
	end
	return mouthOf(root, length), length, slack(length)
end

-- Adds food to a player's Haul (with the Feast Charm), as eating prey does.
function HuntService.feed(player: Player, mass: number)
	local data = DataService.get(player)
	if data then
		addHaul(player, mass * hunt.preyGain * Perks.feast(data.boosts, Timing.now()))
	end
end

function HuntService.start()
	FishService.spawned:connect(function(player: Player, character: Model)
		local session = newSession()
		session.haul = keptHaul[player] or 0
		keptHaul[player] = nil
		sessions[player] = session
		character:SetAttribute("InHub", true)
		character:SetAttribute("Haul", 0)
		refreshSize(player)
	end)
	DataService.releasing:connect(function(player: Player)
		sessions[player] = nil
		keptHaul[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)

	Net.onRequest("EatPrey", onEatPrey)
	Net.onRequest("EatPlayer", onEatPlayer)
	Net.onRequest("Bite", onBite)
	Net.onGetEaten(function(): { [string]: number }
		local now = Timing.clock()
		local result: { [string]: number } = {}
		for index, backAt in eatenUntil do
			if backAt > now then
				result[tostring(index)] = backAt
			end
		end
		return result
	end)
	Guard.loop("HuntService.tick", 0.2, tick)
	-- Forget prey that are back, so the table stays small
	Guard.loop("HuntService.prune", 10, function()
		local now = Timing.clock()
		for index, backAt in eatenUntil do
			if backAt <= now then
				eatenUntil[index] = nil
			end
		end
	end)

	StateService.provide(function(player, data, state)
		local session = sessions[player]
		local haul = if session then session.haul else 0
		local level = Size.level(data.mass)
		state.mass = data.mass
		state.haul = haul
		state.level = level
		state.stage = Size.stage(level)
		state.levelMass = Size.massForLevel(level)
		state.nextLevelMass = Size.massForLevel(level + 1)
		state.maxed = Size.isMaxed(data.mass, haul)
		state.inHub = if session then session.inHub else true
		state.den = FishService.denOf(player)
		state.stats = data.stats
	end)
end

return HuntService
