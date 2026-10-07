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

local Biomes = require(ReplicatedStorage.Shared.Biomes)
local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Schools = require(ReplicatedStorage.Shared.Schools)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local ShellService = require(script.Parent.ShellService)
local StateService = require(script.Parent.StateService)

local hunt = Config.Tuning.hunt
local swim = Config.Tuning.swim
local economy = Config.Tuning.economy
local hub = Config.World.hub

export type Session = {
	haul: number,
	health: number,
	lastHitAt: number,
	lastBiteAt: number,
	safeUntil: number,
	inHub: boolean,
	alive: boolean,
	-- Who bit this fish recently (userId → clock), for the school bonus
	bitBy: { [number]: number },
	-- A Kelp Wrap healing: health a second until `healUntil`; the next wrap allowed
	healRate: number,
	healUntil: number,
	wrapReadyAt: number,
}

local HuntService = {}

local sessions: { [Player]: Session } = {}
local keptHaul: { [Player]: number } = {} -- a Second Chance's Haul, for the next spawn
local eatenUntil: { [number]: number } = {} -- prey index → clock when it's back

local function newSession(): Session
	return {
		haul = 0,
		health = hunt.health, -- set to the species' max health on spawn
		lastHitAt = 0,
		lastBiteAt = 0,
		safeUntil = Timing.clock() + hunt.spawnProtection,
		inHub = true,
		alive = true,
		bitBy = {},
		healRate = 0,
		healUntil = 0,
		wrapReadyAt = 0,
	}
end

local heal = Config.Tuning.heal

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
	return Size.length(Size.liveMass(Progress.mass(data), session.haul))
end

-- The species' max health in bite fights.
local function maxHealth(player: Player): number
	local data = DataService.get(player)
	return hunt.health * (if data then Progress.species(data).stats.health else 1)
end

-- DNA of the biome a fish was eaten in (it unlocks that biome's species).
local function giveDna(player: Player, position: Vector3, amount: number)
	local data = DataService.get(player)
	local biome = Biomes.at(position)
	if data == nil or biome == nil or amount <= 0 then
		return
	end
	data.dna[biome.id] = (data.dna[biome.id] or 0) + amount
	DataService.markDirty(player)
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
	-- 1.6: room for Strong Fins and the fastest species
	return Size.topSpeed(length) * 1.6 * swim.boostMultiplier * swim.lungeSpeed * hunt.latencySeconds
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
	local gain = (lost * hunt.playerHaulShare + Progress.mass(victimData) * hunt.playerBaseShare) * farm
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
	Events.ate:fire(eater, 1)
end

local function onEatPrey(player: Player, batch: any)
	if typeof(batch) ~= "table" or #batch > 12 then
		return
	end
	local session = sessions[player]
	local data = DataService.get(player)
	local character, root = FishService.character(player)
	local length = liveLength(player)
	if
		session == nil
		or data == nil
		or character == nil
		or root == nil
		or length == nil
		or not session.alive
	then
		return
	end
	local now = Timing.clock()
	local mouth = mouthOf(root, length)
	local allowance = Size.reach(length) + slack(length)
	local gained = 0
	local count = 0
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
		count += 1
		-- Eating heals a little, so snacking matters in a long fight
		local most = maxHealth(player)
		if session.health < most then
			session.health =
				math.min(most, session.health + most * (heal.eatBase + heal.eatPerKg * prey.mass))
			character:SetAttribute("Health", session.health)
		end
		-- A wrap tucked in the fish, sometimes
		if math.random() < heal.preyDropChance and HuntService.giveWrap(player, 1) then
			Net.notify(player, `The {prey.name} had a Kelp Wrap in it!`, "good")
		end
		-- DNA: big prey always carry some, small ones sometimes
		local position = Schools.position(index, at)
		if prey.mass >= economy.dnaBigMass then
			giveDna(player, position, math.max(1, math.floor(prey.mass / economy.dnaBigMass)))
		elseif math.random() < economy.dnaChance then
			giveDna(player, position, 1)
		end
		local shells = ShellService.preyDrop(player, prey.id)
		if shells > 0 then
			Net.notify(player, `The {prey.name} had {shells} shell{if shells == 1 then "" else "s"}!`, "good")
		end
		Events.atePrey:fire(player, prey.id, position)
	end
	if gained > 0 then
		addHaul(player, gained)
		Events.ate:fire(player, count)
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
	local species = if attackerData then Progress.species(attackerData).stats.bite else 1
	local damage = hunt.biteDamage * ratio * (1 + 0.35 * school) * jaw * species
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
	local record = Progress.record(data)
	local levelBefore = Size.level(record.mass)
	record.mass += amount
	record.bestMass = math.max(record.bestMass, record.mass)
	data.lastHaul = { id = data.nextHaulId, amount = amount, doubled = false }
	data.nextHaulId += 1
	data.stats.banks += 1
	data.stats.banked += amount
	session.haul = 0
	local levelAfter = Size.level(record.mass)
	EconomyService.addCoral(player, coral)
	Net.banked(player, {
		amount = amount,
		coral = coral,
		mass = record.mass,
		levelBefore = levelBefore,
		level = levelAfter,
		stage = Size.stage(levelAfter),
	})
	refreshSize(player)
	Events.banked:fire(player, amount, levelAfter)
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
				Events.leftHub:fire(player)
			end
			if inHub ~= session.inHub then
				session.inHub = inHub
				character:SetAttribute("InHub", inHub)
				DataService.markDirty(player)
			end
			local most = maxHealth(player)
			if session.health < most and now - session.lastHitAt > hunt.regenDelay then
				session.health = math.min(most, session.health + hunt.regenPerSecond * 0.2)
				character:SetAttribute("Health", session.health)
			end
			-- A Kelp Wrap heals through hits (that's what it's for)
			if now < session.healUntil and session.health < most then
				session.health = math.min(most, session.health + session.healRate * 0.2)
				character:SetAttribute("Health", session.health)
			elseif session.healUntil > 0 and now >= session.healUntil then
				session.healUntil = 0
				character:SetAttribute("Healing", 0)
			end
			local den = FishService.denOf(player)
			if den and session.haul > 0 then
				local length = liveLength(player) or 1
				local offset = root.Position - Layout.poolPosition(den)
				local flat = Vector2.new(offset.X, offset.Z).Magnitude
				-- Any part of the fish over the glow banks (8.7 studs out, on the glow's
				-- edge, once didn't: re-test 2026-10-06)
				if flat < hub.poolRadius + length * 0.5 + 1 and math.abs(offset.Y) < hub.denHeight then
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

-- Every fish's session (alive, inHub, safeUntil, ...), for creatures choosing a
-- target (PredatorService). Read only.
function HuntService.sessions(): { [Player]: Session }
	return sessions
end

-- The Haul a player is carrying (0 if not swimming).
function HuntService.haul(player: Player): number
	local session = sessions[player]
	return if session then session.haul else 0
end

-- Gives DNA of the biome at `position` (forage and other food sources).
-- A creature (predator, boss) kills a fish: the Haul is lost like any death (a
-- Second Chance keeps it), the fish respawns in its den.
function HuntService.kill(player: Player, source: string)
	local session = sessions[player]
	local data = DataService.get(player)
	if session == nil or data == nil or not session.alive then
		return
	end
	local lost = session.haul
	local saved = lost > 0 and (data.charms.SecondChance or 0) > 0
	if saved then
		data.charms.SecondChance -= 1
		keptHaul[player] = lost
		lost = 0
	end
	session.haul = 0
	session.alive = false
	data.stats.timesEaten += 1
	Net.hitBy(player, -1, -1)
	Net.eaten(player, {
		by = source,
		lost = lost,
		saved = if saved then keptHaul[player] else nil,
		respawn = hunt.respawnSeconds,
	})
	FishService.respawnIn(player, hunt.respawnSeconds)
	DataService.markDirty(player)
end

-- Hurts a fish by a share of its max health (predators and bosses; nothing
-- one-shots, owner 2026-10-07). `source` names the attacker for the death screen.
function HuntService.damage(player: Player, fraction: number, source: string)
	local session = sessions[player]
	local character = FishService.character(player)
	if session == nil or character == nil or not session.alive or isSafe(session, Timing.clock()) then
		return
	end
	local amount = maxHealth(player) * fraction
	session.health -= amount
	session.lastHitAt = Timing.clock()
	character:SetAttribute("Health", math.max(session.health, 0))
	Net.hitBy(player, -1, amount)
	if session.health <= 0 then
		HuntService.kill(player, source)
	end
end

-- Hands a player Kelp Wraps (up to the carry cap). Returns whether any were added.
function HuntService.giveWrap(player: Player, count: number): boolean
	local data = DataService.get(player)
	if data == nil then
		return false
	end
	local held = data.charms.KelpWrap or 0
	if held >= heal.wrapMax then
		return false
	end
	data.charms.KelpWrap = math.min(heal.wrapMax, held + count)
	DataService.markDirty(player)
	return true
end

-- Uses a Kelp Wrap: heals wrapFraction of max health over wrapSeconds, with the
-- Healing attribute set until it ends (the client slows and glows).
local function useWrap(player: Player)
	local session = sessions[player]
	local data = DataService.get(player)
	local character = FishService.character(player)
	if session == nil or data == nil or character == nil or not session.alive then
		return
	end
	local now = Timing.clock()
	if (data.charms.KelpWrap or 0) < 1 then
		return Net.notify(
			player,
			"No Kelp Wraps. The Tidecharm Trader sells them, and medkelp grows in the shallows",
			"bad"
		)
	end
	if now < session.wrapReadyAt then
		return Net.notify(player, `Kelp Wrap ready in {math.ceil(session.wrapReadyAt - now)}s`, "info")
	end
	if session.health >= maxHealth(player) then
		return Net.notify(player, "You're at full health", "info")
	end
	data.charms.KelpWrap -= 1
	session.healRate = maxHealth(player) * heal.wrapFraction / heal.wrapSeconds
	session.healUntil = now + heal.wrapSeconds
	session.wrapReadyAt = now + heal.wrapCooldown
	character:SetAttribute("Healing", session.healUntil)
	character:SetAttribute("WrapReadyAt", session.wrapReadyAt)
	DataService.markDirty(player)
end

function HuntService.giveDna(player: Player, position: Vector3, amount: number)
	giveDna(player, position, amount)
end

function HuntService.start()
	FishService.spawned:connect(function(player: Player, character: Model)
		local session = newSession()
		session.health = maxHealth(player)
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
	Net.onRequest("UseWrap", useWrap)
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
		local mass = Progress.mass(data)
		local level = Size.level(mass)
		local species = Progress.species(data)
		state.mass = mass
		state.haul = haul
		state.level = level
		state.stage = Size.stage(level)
		state.species = species.id
		state.speciesName = species.name
		state.levelMass = Size.massForLevel(level)
		state.nextLevelMass = Size.massForLevel(level + 1)
		state.maxed = Size.isMaxed(mass, haul)
		-- Every species' level, for the species menu
		local levels: { [string]: number } = {}
		for id, record in data.species do
			levels[id] = Size.level(record.mass)
		end
		state.speciesLevels = levels
		state.unlocked = data.unlocked
		state.dna = data.dna
		state.inHub = if session then session.inHub else true
		state.den = FishService.denOf(player)
		state.stats = data.stats
	end)
end

return HuntService
