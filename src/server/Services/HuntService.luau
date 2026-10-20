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
local Format = require(ReplicatedStorage.Shared.Format)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Schools = require(ReplicatedStorage.Shared.Schools)
local Size = require(ReplicatedStorage.Shared.Size)
local Tides = require(ReplicatedStorage.Shared.Tides)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
local CatchService = require(script.Parent.CatchService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local MonetizationService = require(script.Parent.MonetizationService)
local ShellService = require(script.Parent.ShellService)
local StateService = require(script.Parent.StateService)

local hunt = Config.Tuning.hunt
local swim = Config.Tuning.swim
local economy = Config.Tuning.economy
local hub = Config.World.hub
local money = Config.Monetization.tuning

export type Session = {
	haul: number,
	-- The Haul before the Haul rate (Config/Tuning `growth`): what a bank pays from
	-- (coral, Tide Pass XP, the map chance), so slower growth didn't cut a dive's pay
	worth: number,
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
		worth = 0,
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

-- The fish's live length (banked mass plus Haul).
local function liveLength(player: Player): number?
	local data = DataService.get(player)
	local session = sessions[player]
	if data == nil or session == nil then
		return nil
	end
	return Size.length(Size.liveMass(Progress.mass(data), session.haul))
end

-- The species' max health in bite fights.
-- How much a bite hurts a fish with a sea turtle at its side (Config/Companions:
-- CompanionService sets the character's `Escort`, the clock it leaves at)
local PRESSURE = "the crushing deep" -- (PressureService's source: no turtle helps there)
local function escortScale(character: Model): number
	local escort = character:GetAttribute("Escort")
	if typeof(escort) == "number" and escort > Timing.clock() then
		return Config.Companions.turtle.bite
	end
	return 1
end

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
	-- (its banked level: what a fight goes by, Config/Pvp `fight`; nametags show it)
	local data = DataService.get(player)
	if character and data then
		character:SetAttribute("FishLevel", Size.level(Progress.mass(data)))
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

-- A fish's Haul rate (Config/Tuning `growth`, Shared/Size): the share of each kg
-- eaten that goes on its Haul, by its banked level
local function haulRate(player: Player): number
	local data = DataService.get(player)
	return if data then Size.haulRate(Progress.mass(data)) else 1
end

-- Food in a biome below the fish counts for less (Config/Tuning `growth`
-- `overLevel`): × this, by the biome the fish is in now (none in the hub)
local function overLevel(player: Player, banked: number): number
	local _, root = FishService.character(player)
	local biome = if root then Biomes.at(root.Position) else nil
	return if biome then Size.overLevel(Size.level(banked), biome.maxLevel) else 1
end

-- How much a fish's full Haul holds (kg; Config/Tuning `growth` `cap`)
local function fullHaul(player: Player): number
	local data = DataService.get(player)
	return if data then Size.haulCap(Progress.mass(data)) else 0
end

-- How a gain counts (addHaul). Everyday food stops at the full Haul (MAX SIZE);
-- rewards and a Haul given back go on top:
--   "food"    eaten food in kg: × the fish's Haul rate (less in a biome below it:
--             `overLevel`), then ×2 Mass and Server Frenzy (prey, filler food)
--   "rated"   already in Haul (a share of a full Haul: bait, whale and slick chunks,
--             predator loot; a share of a kill): ×2 Mass and Server Frenzy only
--   "raw"     goes on as it is (chum from a dead fish's Haul, grown already)
--   "sized"   a reward in Haul, past the full Haul (a boss's, a treasure's, the
--             admin's kg): ×2 Mass and Server Frenzy, and worth what it is
--   "restore" a Haul given back (a Second Chance): as it is, past the full Haul
export type Gain = "food" | "rated" | "raw" | "sized" | "restore"

-- Adds to a fish's Haul (see Gain; "food" when `how` is nil), and to its `worth` (the
-- kg eaten it stands for, before the rate: what a bank pays from). Returns what was
-- added (nothing once everyday food meets a full Haul).
local function addHaul(player: Player, amount: number, how: Gain?): number
	local session = sessions[player]
	local data = DataService.get(player)
	if session == nil or data == nil or amount <= 0 then
		return 0
	end
	local banked = Progress.mass(data)
	local rate = Size.haulRate(banked)
	local added = amount
	if how ~= "raw" and how ~= "restore" then
		added *= MonetizationService.growth(player)
	end
	if how == nil or how == "food" then
		-- (worth stays the kg eaten: what a bank pays isn't cut, only the growth)
		rate *= overLevel(player, banked)
		added *= rate
	end
	if how ~= "sized" and how ~= "restore" then
		added = math.min(added, math.max(Size.haulCap(banked) - session.haul, 0))
	end
	if added <= 0 then
		return 0
	end
	session.worth += if how == "sized" then added else added / rate
	session.haul += added
	refreshSize(player)
	return added
end

-- The Reef Shark's Blood Sense draws prey in from further (Perks.sense); the server
-- keeps it on half a second longer, since it sees the fish a little in the past
local function suctionOf(player: Player): number
	local character = FishService.character(player)
	local _, suction = Perks.sense(character, Timing.clock(), 0.5)
	return suction
end

-- A Haul lost to being eaten, for a Second Chance bought on the eaten screen.
-- Offered only for a Haul worth having (`minShare` of a full Haul), after the
-- tutorial; only an offered Haul is remembered, so a Second Chance bought from the
-- Shop otherwise is a charm. Returns the kg to offer, or nil.
local function rememberLost(data: DataService.PlayerData, lost: number): number?
	local worth = lost > 0 and lost >= Size.haulCap(Progress.mass(data)) * money.secondChance.minShare
	if not worth or not data.tutorial.done then
		data.lostHaul = { amount = 0, at = 0 }
		return nil
	end
	data.lostHaul = { amount = lost, at = Timing.now() }
	return lost
end

-- A fish is eaten: its Haul is lost (part of it goes to the eater) and it
-- respawns in its den.
local function eatPlayer(victim: Player, eater: Player)
	local victimSession = sessions[victim]
	local eaterSession = sessions[eater]
	local victimData = DataService.get(victim)
	local eaterData = DataService.get(eater)
	local victimLength = liveLength(victim)
	if
		victimSession == nil
		or eaterSession == nil
		or victimData == nil
		or eaterData == nil
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
	-- (by level: their banked sizes)
	local ratio = math.clamp(
		Size.ratio(Size.length(Progress.mass(victimData)), Size.length(Progress.mass(eaterData)))
			/ hunt.swallowRatio,
		0,
		1
	)
	local farm = math.max(ratio * ratio, 0.02)
	-- Half its Haul, and a share of what a full Haul is for it (Config/Tuning `hunt`):
	-- already in Haul, so no Haul rate; it stops at the eater's full Haul
	local gain = (
		lost * hunt.playerHaulShare + Size.haulCap(Progress.mass(victimData)) * hunt.playerBaseHauls
	) * farm
	EconomyService.earnCoral(eater, economy.eatPlayerCoral * farm)
	local offer = if saved then nil else rememberLost(victimData, lost)
	local _, victimRoot = FishService.character(victim)
	if victimRoot and lost > 0 then
		Events.burst:fire(victim, victimRoot.Position, lost * Config.Chum.share, victimLength)
	end
	victimSession.haul = 0
	victimSession.worth = 0
	victimSession.alive = false
	victimData.stats.timesEaten += 1
	eaterData.stats.playersEaten += 1
	Net.hit(eater, victim, -1)
	Net.eaten(victim, {
		by = eater.DisplayName,
		lost = lost,
		saved = if saved then keptHaul[victim] else nil,
		respawn = hunt.respawnSeconds,
		offer = offer,
	})
	Net.notify(eater, `You ate {victim.DisplayName}!`, "good")
	FishService.respawnIn(victim, hunt.respawnSeconds)
	DataService.markDirty(victim)
	addHaul(eater, gain, "rated")
	Events.ate:fire(eater, 1)
	-- (the gain before ×2 Mass and Frenzy, after the Haul rate: a podmate's share
	-- gets its own ×2 Mass and Frenzy, "rated")
	Events.atePlayer:fire(eater, victim, gain)
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
	local allowance = slack(length)
	local suction = suctionOf(player)
	local tide = Tides.at(Timing.unix())
	local gained = 0
	local count = 0
	local stung, stingFloor = 0, 0 -- venomous prey swallowed: share of max health, and the floor
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
		-- A tide's school (the Sardine Run's bait balls) only while its tide is up
		if not Schools.out(index, tide.id) then
			continue
		end
		local fish = Schools.fish[index]
		if not Size.canSwallow(length * 1.03, fish.length) then
			continue
		end
		-- The client's swallow reach and its suction pull (Schools.eatReach, EAT_PULLED),
		-- wider while a Reef Shark's Blood Sense runs
		local reach = Schools.eatReach(length, fish.radius) * Schools.EAT_PULLED * suction
		if (Schools.position(index, at) - mouth).Magnitude > reach + allowance then
			continue
		end
		local prey = Config.Prey.byId[fish.prey]
		local backAt = now + prey.respawn
		eatenUntil[index] = backAt
		Net.preyEaten(index, backAt, player.UserId)
		-- A rare fish (Config/Catch) is worth more, and so is a tide's catch
		local rarityId = CatchService.take(index, backAt)
		local rare = if rarityId then Config.Catch.byId[rarityId] else nil
		local worth = (if rare then rare.haul else 1)
			* (tide.haul or 1)
			* (if fish.mass < Config.Tides.smallMass then tide.smallHaul or 1 else 1)
		-- Each fish its own size (Schools `mass`): a big one is worth more
		gained += fish.mass * hunt.preyGain * Perks.feast(data.boosts, Timing.now()) * worth
		data.stats.preyEaten += 1
		count += 1
		if fish.mass > data.stats.bestPreyMass then
			data.stats.bestPrey = prey.id
			data.stats.bestPreyMass = fish.mass
			Events.trophies:fire(player)
		end
		-- Eating heals a little, so snacking matters in a long fight; a venomous fish
		-- (Config/Prey `venom`: the Lionfish) heals nothing and stings instead
		local most = maxHealth(player)
		local venom = Config.Prey.venom[prey.id]
		if venom then
			local ratio = Size.ratio(length, fish.length)
			stung += math.max(venom.least, venom.share * math.min(1, venom.fullRatio / ratio))
			stingFloor = math.max(stingFloor, venom.floor)
		elseif session.health < most then
			session.health =
				math.min(most, session.health + most * (heal.eatBase + heal.eatPerKg * fish.mass))
			character:SetAttribute("Health", session.health)
		end
		-- A wrap tucked in the fish, sometimes
		if math.random() < heal.preyDropChance and HuntService.giveWrap(player, 1) then
			Net.notify(player, `The {prey.name} had a Kelp Wrap in it!`, "good")
		end
		-- DNA: big prey always carry some, small ones sometimes, rare ones more
		local position = Schools.position(index, at)
		local dna = if rare then rare.dna else 1
		if fish.mass >= economy.dnaBigMass then
			giveDna(player, position, math.max(1, math.floor(fish.mass / economy.dnaBigMass)) * dna)
		elseif rare then
			giveDna(player, position, dna)
		elseif math.random() < economy.dnaChance then
			giveDna(player, position, 1)
		end
		local shells = ShellService.preyDrop(player, prey.id)
		if shells > 0 then
			Net.notify(player, `The {prey.name} had {shells} shell{if shells == 1 then "" else "s"}!`, "good")
		end
		Events.atePrey:fire(player, prey.id, position)
		Events.caught:fire(player, prey.id, rarityId or "Normal", position, fish.mass)
	end
	if gained > 0 then
		addHaul(player, gained)
		Events.ate:fire(player, count)
	end
	-- The sting: never in the hub or under spawn protection, and never fatal (it stops
	-- at the venom's floor of max health)
	if stung > 0 and not isSafe(session, now) then
		local most = maxHealth(player)
		local amount = math.min(most * stung, math.max(session.health - most * stingFloor, 0))
		if amount > 0 then
			session.health -= amount
			session.lastHitAt = now
			character:SetAttribute("Health", session.health)
			Net.hitBy(player, -1, amount)
		end
		Net.notify(player, "STUNG · venomous spines", "bad")
	end
end

-- Whether two players share a pod (PodService sets the `Pod` attribute; read here
-- so this service needn't require that one)
local function podmates(a: Player, b: Player): boolean
	local pod = a:GetAttribute("Pod")
	return typeof(pod) == "number" and pod ~= 0 and pod == b:GetAttribute("Pod")
end

-- A fish's live mass (banked plus Haul), for schooling
-- A fish's banked mass (its level, without the Haul aboard): what a fight goes by
local function bankedMassOf(player: Player): number
	local data = DataService.get(player)
	if data == nil or sessions[player] == nil then
		return 0
	end
	return Progress.mass(data)
end

local function targetOf(player: Player, userId: any): (Player?, Session?, BasePart?)
	if not finite(userId) then
		return nil, nil, nil
	end
	local target = Players:GetPlayerByUserId(userId)
	if target == nil or target == player or podmates(player, target) then
		return nil, nil, nil
	end
	local session = sessions[target]
	local _, root = FishService.character(target)
	if session == nil or root == nil or not session.alive then
		return nil, nil, nil
	end
	return target, session, root
end

-- A bite on another player: every player fight is bitten out, however big the
-- biter (Config/Pvp `fight`: by level, never swallowed whole). Small fish do little
-- alone, but a school bites together (Config/Pvp `school`): everyone who bit the
-- same target in the last few seconds, close to the biter, bites with their combined
-- banked mass, so a school of small fish can bring down one far bigger than any of
-- them.
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
	local schooling = Config.Pvp.school
	local school = 0
	local mass = bankedMassOf(player)
	for otherId, at in targetSession.bitBy do
		if otherId == player.UserId or now - at >= schooling.window then
			continue
		end
		local other = Players:GetPlayerByUserId(otherId)
		local otherRoot: BasePart? = nil
		if other then
			_, otherRoot = FishService.character(other)
		end
		if other and otherRoot and (otherRoot.Position - root.Position).Magnitude <= schooling.range then
			school += 1
			mass += bankedMassOf(other)
		end
	end
	targetSession.bitBy[player.UserId] = now
	-- The school's combined banked mass against the target's: their levels, not the
	-- Haul aboard (Config/Pvp `fight`)
	local fight = Config.Pvp.fight
	local targetMass = math.max(bankedMassOf(target), 1e-3)
	local ratio = math.clamp((mass / targetMass) ^ fight.power, fight.min, fight.max)
	local attackerData = DataService.get(player)
	local jaw = Perks.bite(if attackerData then attackerData.upgrades else nil)
	local species = if attackerData then Progress.species(attackerData).stats.bite else 1
	local damage = hunt.biteDamage * ratio * (1 + schooling.bonus * school) * jaw * species
	-- Signature abilities (Config/Abilities): a Moray's bite out of a burrow is an
	-- ambush, and a puffed-up Pufferfish takes less and spikes the biter
	local abilities = Config.Abilities.byId
	local attacker = FishService.character(player)
	local strike = if attacker then attacker:GetAttribute("BurrowStrike") else nil
	if
		attacker
		and (attacker:GetAttribute("Burrowed") == true or (typeof(strike) == "number" and strike > now))
	then
		damage *= abilities.Burrow.strikeBonus or 1.6
		attacker:SetAttribute("BurrowStrike", nil)
		Net.notify(player, "AMBUSH!", "good")
	end
	local victim = FishService.character(target)
	local puffed = if victim then victim:GetAttribute("Puffed") else nil
	if typeof(puffed) == "number" and puffed > now then
		damage *= abilities.PuffUp.damageTaken or 0.5
		HuntService.damage(player, abilities.PuffUp.recoil or 0.1, "spines")
	end
	if victim then
		damage *= escortScale(victim)
	end
	targetSession.health -= damage
	targetSession.lastHitAt = now
	Net.hit(player, target, damage)
	if school > 0 then
		Net.notify(player, `SCHOOL BITE ×{school + 1}`, "good")
	end
	local character = FishService.character(target)
	if character then
		character:SetAttribute("Health", math.max(targetSession.health, 0))
	end
	if targetSession.health <= 0 then
		eatPlayer(target, player)
	end
end

local function bank(player: Player, session: Session, data: DataService.PlayerData)
	local bonus = hunt.bankMultiplier * Perks.bank(data.upgrades)
	local amount = session.haul * bonus
	-- What the Haul was worth before the Haul rate (Config/Tuning `growth`, Session
	-- `worth`): coral, Tide Pass XP and the map chance are reckoned from it, so slowing
	-- the growth didn't cut what a dive pays
	local worth = math.max(session.worth, session.haul) * bonus
	local record = Progress.record(data)
	local levelBefore = Size.level(record.mass)
	record.mass += amount
	record.bestMass = math.max(record.bestMass, record.mass)
	data.lastHaul = { id = data.nextHaulId, amount = amount, doubled = false, species = data.current }
	data.nextHaulId += 1
	data.stats.banks += 1
	data.stats.banked += amount
	session.haul = 0
	session.worth = 0
	local levelAfter = Size.level(record.mass)
	local coral = EconomyService.earnCoral(player, economy.bankCoral * math.sqrt(worth))
	-- Double Haul on the bank screen, for a full or nearly full Haul (`minFull` of what
	-- a full Haul held before this bank)
	local offer = nil
	if amount >= Size.haulCap(record.mass - amount) * money.doubleHaul.minFull and data.tutorial.done then
		local tier = money.doubleHaul.tiers[#money.doubleHaul.tiers]
		for _, candidate in money.doubleHaul.tiers do
			if amount <= candidate.maxKg then
				tier = candidate
				break
			end
		end
		offer = {
			id = data.lastHaul.id,
			product = tier.key,
			levels = Size.level(record.mass + amount) - levelAfter,
			ad = amount <= money.doubleHaul.adMaxKg,
		}
	end
	Net.banked(player, {
		amount = amount,
		food = Size.haulShown(record.mass - amount, amount), -- (the Haul as the card showed it)
		coral = coral,
		mass = record.mass,
		levelBefore = levelBefore,
		level = levelAfter,
		stage = Size.stage(levelAfter),
		offer = offer,
	})
	refreshSize(player)
	Events.banked:fire(player, amount, levelAfter, worth)
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
			-- No regeneration (Config/Tuning hunt.health): a Kelp Wrap heals, through
			-- hits too (that's what it's for)
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
				if
					flat < Config.Dens.pool.radius + length * 0.5 + 1
					and math.abs(offset.Y) < hub.denHeight
				then
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

-- Adds food to a player's Haul (with the Feast Charm), as eating prey does: × the
-- Haul rate unless `how` says otherwise (Gain; "sized" for a reward in kg of Haul).
-- Returns the kg added (after the rate, ×2 Mass and Server Frenzy and the full Haul).
function HuntService.feed(player: Player, mass: number, how: Gain?): number
	local data = DataService.get(player)
	if data == nil then
		return 0
	end
	return addHaul(player, mass * hunt.preyGain * Perks.feast(data.boosts, Timing.now()), how)
end

-- The share of a kg eaten that goes on this player's Haul now (Config/Tuning
-- `growth`)
function HuntService.haulRate(player: Player): number
	return haulRate(player)
end

-- What a full Haul holds for this player's fish now (kg)
function HuntService.fullHaul(player: Player): number
	return fullHaul(player)
end

-- A Haul amount (kg of growth) as the player sees it: food, kg of fish eaten
-- (Size.haulShown), for toasts and reward cards
function HuntService.shown(player: Player, kg: number): number
	local data = DataService.get(player)
	return if data then Size.haulShown(Progress.mass(data), kg) else kg
end

-- Adds `hauls` of this fish's full Haul (bait, whale chunks, slick chunks, predator
-- loot: "rated", stopping at a full Haul; a boss's or a treasure's Haul: "sized", on
-- top), so a bonus meal is worth the same share of a dive at every level. Returns
-- the kg added.
function HuntService.hauls(player: Player, hauls: number, how: Gain?): number
	return addHaul(player, fullHaul(player) * hauls, how or "rated")
end

-- × a fish's prey reach (Blood Sense draws prey in from further), for ForageService
function HuntService.suction(player: Player): number
	return suctionOf(player)
end

-- Takes a share of a fish's Haul away (a fisherman landing it). Returns the kg taken.
function HuntService.takeHaul(player: Player, share: number): number
	local session = sessions[player]
	if session == nil or session.haul <= 0 then
		return 0
	end
	local taken = session.haul * math.clamp(share, 0, 1)
	session.haul -= taken
	session.worth *= 1 - math.clamp(share, 0, 1)
	refreshSize(player)
	return taken
end

-- Adds food, counted as `how` says (Gain: "food" by default, kg eaten: the Haul rate
-- then ×2 Mass and Server Frenzy; "rated" or "sized" already in Haul; "raw" as it
-- is, for chum: a lost Haul that was grown already). Returns the kg added.
function HuntService.gain(player: Player, amount: number, how: Gain?): number
	return addHaul(player, amount, how)
end

-- Every fish's session (alive, inHub, safeUntil, ...), for creatures choosing a
-- target (PredatorService). Read only.
function HuntService.sessions(): { [Player]: Session }
	return sessions
end

-- Whether prey fish `index` is eaten (and waiting to respawn) at `now`.
function HuntService.preyEaten(index: number, now: number): boolean
	return (eatenUntil[index] or 0) > now
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
	local offer = if saved then nil else rememberLost(data, lost)
	local _, root = FishService.character(player)
	if root and lost > 0 then
		Events.burst:fire(player, root.Position, lost * Config.Chum.share, liveLength(player) or 2)
	end
	session.haul = 0
	session.worth = 0
	session.alive = false
	data.stats.timesEaten += 1
	Net.hitBy(player, -1, -1)
	Net.eaten(player, {
		by = source,
		lost = lost,
		saved = if saved then keptHaul[player] else nil,
		respawn = hunt.respawnSeconds,
		offer = offer,
	})
	FishService.respawnIn(player, hunt.respawnSeconds)
	DataService.markDirty(player)
end

-- Hurts a fish by a share of its max health (predators and bosses; nothing
-- one-shots, owner 2026-10-07). `source` names the attacker for the death screen.
function HuntService.damage(player: Player, fraction: number, source: string, quiet: boolean?)
	local session = sessions[player]
	local character = FishService.character(player)
	if session == nil or character == nil or not session.alive or isSafe(session, Timing.clock()) then
		return
	end
	-- (a turtle at its side takes the edge off a bite, never off the crushing deep)
	local scale = if source == PRESSURE then 1 else escortScale(character)
	local amount = maxHealth(player) * fraction * scale
	session.health -= amount
	session.lastHitAt = Timing.clock()
	character:SetAttribute("Health", math.max(session.health, 0))
	if not quiet then
		Net.hitBy(player, -1, amount)
	end
	if session.health <= 0 then
		HuntService.kill(player, source)
	end
end

-- Heals a fish fully (the admin panel).
function HuntService.healFull(player: Player)
	local session = sessions[player]
	local character = FishService.character(player)
	if session and character and session.alive then
		session.health = maxHealth(player)
		character:SetAttribute("Health", session.health)
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

HuntService.useWrap = useWrap

function HuntService.giveDna(player: Player, position: Vector3, amount: number)
	giveDna(player, position, amount)
end

-- Double Haul (a product receipt or a watched ad): the last banked Haul again, up to
-- `cap` kg (a bigger haul banked before the receipt landed is doubled up to the
-- size that was paid for). Each haul doubles once; a second receipt for the same
-- one is never lost, it becomes a Second Chance charm.
local function doubleHaul(player: Player, data: DataService.PlayerData, cap: number)
	local last = data.lastHaul
	if last.amount <= 0 or last.doubled then
		data.charms.SecondChance = (data.charms.SecondChance or 0) + 1
		Net.notify(player, "That Haul was already doubled, so here's a Second Chance charm instead.", "info")
		return
	end
	local amount = math.min(last.amount, cap)
	local speciesId = last.species or data.current
	local record = data.species[speciesId] or Progress.record(data)
	local levelBefore = Size.level(record.mass)
	record.mass += amount
	record.bestMass = math.max(record.bestMass, record.mass)
	last.doubled = true
	data.stats.banked += amount
	local levelAfter = Size.level(record.mass)
	Net.banked(player, {
		amount = amount,
		food = Size.haulShown(record.mass - amount, amount), -- (as food, like the bank card)
		doubled = true,
		mass = record.mass,
		levelBefore = levelBefore,
		level = levelAfter,
		stage = Size.stage(levelAfter),
	})
	if speciesId == data.current then
		refreshSize(player)
	end
end

-- Second Chance bought on the eaten screen gives back the Haul just lost (once);
-- bought any other time, it's a charm for the next time something eats you.
local function secondChance(player: Player, data: DataService.PlayerData)
	local lost = data.lostHaul
	if lost.amount > 0 and Timing.now() - lost.at <= money.secondChance.window then
		local amount = lost.amount
		data.lostHaul = { amount = 0, at = 0 }
		local session = sessions[player]
		if session and session.alive then
			addHaul(player, amount, "restore")
		else
			keptHaul[player] = (keptHaul[player] or 0) + amount -- back on the next spawn
		end
		Net.notify(
			player,
			`Second Chance: your {Format.mass(HuntService.shown(player, amount))} Haul is back! Swim home to bank it.`,
			"rare"
		)
		return
	end
	data.charms.SecondChance = (data.charms.SecondChance or 0) + 1
	Net.notify(player, "Second Chance ready: the next time you're eaten, you keep your Haul.", "rare")
end

function HuntService.start()
	for _, tier in money.doubleHaul.tiers do
		MonetizationService.onProduct(tier.key, function(player, data)
			doubleHaul(player, data, tier.maxKg)
		end)
	end
	MonetizationService.onProduct("AdDoubleHaul", function(player, data)
		doubleHaul(player, data, money.doubleHaul.adMaxKg)
	end)
	MonetizationService.onProduct("SecondChance", secondChance)
	FishService.spawned:connect(function(player: Player, character: Model)
		local session = newSession()
		session.health = maxHealth(player)
		session.haul = keptHaul[player] or 0
		keptHaul[player] = nil
		sessions[player] = session
		-- (a kept Haul took the rate as it was eaten)
		session.worth = session.haul / haulRate(player)
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
