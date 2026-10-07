--!strict
-- World bosses (Config/Bosses, GDD §8). A boss is a `custom` predator: PredatorService
-- streams it and checks the players' bites, and this service does the rest. The
-- event clock raises one about every half hour (two minutes' warning). The boss
-- hunts the biggest fish around, telegraphs every attack, and moves through three
-- phases as its health falls: Hunting (charge, bite), Frenzy (faster, tail sweep,
-- blood cloud, Marked for death) and Last stand (it makes for the Trench on a
-- clock, breaching on the way; catch it or it escapes). Its health scales with the
-- number of attackers; its soft spots take double damage and fill a stagger meter
-- that stuns it. Everyone who dealt a share of the damage is paid: Teeth for the
-- Trophy Hunter, a huge Haul, coral, a shade roll, a title, and a chance at the
-- trophy shade straight from the kill. Nothing it does one-shots (owner).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BossesConfig = require(ReplicatedStorage.Shared.Config.Bosses)
local Config = require(ReplicatedStorage.Shared.Config)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local HuntService = require(script.Parent.HuntService)
local PredatorService = require(script.Parent.PredatorService)

local Bosses = Config.Bosses
local Tiers = Config.Tiers
local World = Config.World

type BossDef = BossesConfig.BossDef
type Predator = PredatorService.Predator

type Attack = {
	kind: string, -- bite, charge, lunge, sweep, breach
	stage: string, -- tell, go, recover, rocket, crash
	endsAt: number,
	target: Player?,
	aim: Vector3, -- a locked direction (charges)
	hit: { [Player]: boolean }, -- fish already hurt by this attack
}

type Boss = {
	def: BossDef,
	predator: Predator,
	phase: number,
	attack: Attack?,
	cooldowns: { [string]: number }, -- attack kind → ready at
	nextAttackAt: number,
	nextTargetAt: number,
	mark: { target: Player, endsAt: number, nextLungeAt: number }?,
	stagger: number, -- damage on soft spots toward a stagger
	staggeredUntil: number,
	staggerReadyAt: number,
	exhaustedUntil: number,
	lastStandUntil: number,
	nextBreachAt: number,
	bloodUntil: number,
	waypoint: Vector3,
	waypointUntil: number,
	spawnedAt: number,
}

type Fish = { player: Player, root: BasePart, length: number }

local BossService = {}

local active: Boss? = nil
local rng = Random.new()
local rotationIndex = 0
local nextEventAt = 0
local warned = false
local accumulator = 0

local function nextDef(): BossDef
	local id = Bosses.rotation[(rotationIndex % #Bosses.rotation) + 1]
	return Bosses.byId[id]
end

local function schedule(now: number, delay: number)
	nextEventAt = now + delay
	warned = false
end

local function interval(def: BossDef): number
	return if Timing.isStudio() then def.event.studioInterval else def.event.interval
end

local function patrolPoint(def: BossDef): Vector3
	local patrol = def.patrol
	local base = math.atan2(patrol.direction.Z, patrol.direction.X)
	local angle = base + rng:NextNumber(-patrol.spread, patrol.spread)
	local distance = rng:NextNumber(patrol.band[1], patrol.band[2])
	return Vector3.new(
		math.cos(angle) * distance,
		rng:NextNumber(patrol.depth[1], patrol.depth[2]),
		math.sin(angle) * distance
	)
end

-- What the clients need to know about the event right now
local function stateOf(): { [string]: any }
	local boss = active
	if boss then
		return {
			state = "active",
			id = boss.def.id,
			name = boss.def.name,
			title = boss.def.title,
			index = boss.predator.index,
			phase = boss.phase,
			lastStandUntil = boss.lastStandUntil,
			mark = if boss.mark then boss.mark.target.UserId else 0,
			staggeredUntil = boss.staggeredUntil,
			exhaustedUntil = boss.exhaustedUntil,
			bloodUntil = boss.bloodUntil,
			spawnedAt = boss.spawnedAt,
		}
	end
	local def = nextDef()
	return {
		state = if warned then "warning" else "gone",
		id = def.id,
		name = def.name,
		title = def.title,
		at = nextEventAt,
	}
end

local function broadcast()
	Net.bossState(stateOf())
end

-- The fish a boss can hurt right now: alive, out of the hub, not protected.
local function fishAround(now: number): { Fish }
	local list: { Fish } = {}
	for player, session in HuntService.sessions() do
		if not session.alive or session.inHub or session.safeUntil > now then
			continue
		end
		local character, root = FishService.character(player)
		if character == nil or root == nil then
			continue
		end
		local length = character:GetAttribute("Length")
		table.insert(
			list,
			{ player = player, root = root, length = if typeof(length) == "number" then length else 2 }
		)
	end
	return list
end

-- Distance from a point to the boss's body (tail tip to nose), and where along it
local function alongBody(predator: Predator, point: Vector3): (number, number)
	local half = predator.heading * predator.def.length * 0.5
	local a = predator.position - half
	local ab = half * 2
	local t = math.clamp((point - a):Dot(ab) / math.max(ab:Dot(ab), 1e-4), 0, 1)
	return (a + ab * t - point).Magnitude, t
end

local function speedOf(boss: Boss): number
	local speed = boss.def.predator.speed
	if boss.phase >= 2 then
		speed *= boss.def.frenzySpeed
	end
	return speed
end

local function endMark(boss: Boss, now: number)
	if boss.mark == nil then
		return
	end
	boss.mark = nil
	boss.cooldowns.mark = now + boss.def.mark.cooldown
	Net.predatorEvent("unmarked", boss.predator.index, {})
	broadcast()
end

local function startAttack(
	boss: Boss,
	kind: string,
	stage: string,
	seconds: number,
	target: Player?,
	now: number
)
	boss.attack = {
		kind = kind,
		stage = stage,
		endsAt = now + seconds,
		target = target,
		aim = boss.predator.heading,
		hit = {},
	}
end

local function targetOf(boss: Boss): (BasePart?, number)
	local attack = boss.attack
	local predator = boss.predator
	local target = if attack then attack.target else predator.target
	if target == nil then
		return nil, 0
	end
	local session = HuntService.sessions()[target]
	if session == nil or not session.alive or session.inHub then
		return nil, 0
	end
	local character, root = FishService.character(target)
	if character == nil or root == nil then
		return nil, 0
	end
	local length = character:GetAttribute("Length")
	return root, if typeof(length) == "number" then length else 2
end

-- Hurts every fish the attack reaches (once per attack), with a push.
local function strike(
	boss: Boss,
	attack: Attack,
	fraction: number,
	now: number,
	reaches: (Fish) -> boolean,
	push: (Fish) -> Vector3?
)
	for _, fish in fishAround(now) do
		if attack.hit[fish.player] or not reaches(fish) then
			continue
		end
		attack.hit[fish.player] = true
		HuntService.damage(fish.player, fraction, boss.def.name)
		local shove = push(fish)
		if shove then
			Net.shove(fish.player, shove)
		end
	end
end

local function runAttack(boss: Boss, attack: Attack, dt: number, now: number): Vector3
	local predator = boss.predator
	local def = boss.def
	local speed = speedOf(boss)
	local index = predator.index
	local root, fishLength = targetOf(boss)
	local mouth = PredatorService.mouthOf(predator)
	local toward = if root
		then (root.Position + root.AssemblyLinearVelocity * 0.3 - mouth)
		else predator.heading
	local direction = if toward.Magnitude > 1e-3 then toward.Unit else predator.heading
	local desired = predator.heading * speed * 0.3

	if attack.kind == "bite" then
		if attack.stage == "tell" then
			predator.mode = "windup"
			desired = direction * speed * 0.35
			if now >= attack.endsAt then
				local hit = false
				if root then
					local reach = def.bite.reach * 1.6 + fishLength * 0.5 + Size.topSpeed(fishLength) * 0.15
					hit = (root.Position - mouth).Magnitude <= reach
					if hit then
						HuntService.damage(attack.target :: Player, def.bite.fraction, def.name)
					end
				end
				Net.predatorEvent("bite", index, { hit = hit, x = mouth.X, y = mouth.Y, z = mouth.Z })
				attack.stage = "recover"
				attack.endsAt = now + 1.2
				boss.cooldowns.bite = now + def.bite.cooldown
			end
		else
			predator.mode = "recover"
			desired = predator.heading * speed * 0.5
			if now >= attack.endsAt then
				boss.attack = nil
			end
		end
	elseif attack.kind == "charge" or attack.kind == "lunge" then
		local lunge = attack.kind == "lunge"
		local fraction = if lunge then def.mark.lungeFraction else def.charge.fraction
		local radius = if lunge then def.charge.radius * 0.8 else def.charge.radius
		if attack.stage == "tell" then
			predator.mode = "windup"
			-- Eyes flash: it slows and lines up on the fish
			desired = direction * speed * 0.15
			if now >= attack.endsAt then
				attack.aim = if root
					then ((root.Position + root.AssemblyLinearVelocity * 0.4) - predator.position).Unit
					else predator.heading
				attack.stage = "go"
				attack.endsAt = now + (if lunge then def.mark.lungeSeconds else def.charge.seconds)
				Net.predatorEvent("rush", index, { seconds = attack.endsAt - now })
			end
		elseif attack.stage == "go" then
			predator.mode = "hunt"
			desired = attack.aim * speed * (if lunge then 2 else def.charge.speedMul)
			strike(boss, attack, fraction, now, function(fish)
				local distance = alongBody(predator, fish.root.Position)
				return distance <= radius + fish.length * 0.4
			end, function(_)
				return attack.aim * 30
			end)
			if now >= attack.endsAt then
				attack.stage = "recover"
				attack.endsAt = now + (if lunge then 0.5 else 1.5)
				if not lunge then
					boss.cooldowns.charge = now + def.charge.cooldown
				end
				Net.predatorEvent(
					"charged",
					index,
					{ x = predator.position.X, y = predator.position.Y, z = predator.position.Z }
				)
			end
		else
			predator.mode = "recover"
			desired = predator.heading * speed * 0.4
			if now >= attack.endsAt then
				boss.attack = nil
			end
		end
	elseif attack.kind == "sweep" then
		if attack.stage == "tell" then
			predator.mode = "windup"
			desired = predator.velocity * 0.2
			if now >= attack.endsAt then
				local center = predator.position
				strike(boss, attack, def.sweep.fraction, now, function(fish)
					local offset = fish.root.Position - center
					return offset.Magnitude <= def.sweep.radius + fish.length * 0.4
						and predator.heading:Dot(offset.Unit) < 0.25
				end, function(fish)
					local offset = fish.root.Position - center
					local flat = Vector3.new(offset.X, 0, offset.Z)
					local out = if flat.Magnitude > 1e-3 then flat.Unit else -predator.heading
					return out * def.sweep.push + Vector3.new(0, 12, 0)
				end)
				Net.predatorEvent(
					"swept",
					index,
					{ x = center.X, y = center.Y, z = center.Z, radius = def.sweep.radius }
				)
				attack.stage = "recover"
				attack.endsAt = now + 0.8
				boss.cooldowns.sweep = now + def.sweep.cooldown
			end
		else
			predator.mode = "recover"
			desired = predator.heading * speed * 0.4
			if now >= attack.endsAt then
				boss.attack = nil
			end
		end
	elseif attack.kind == "breach" then
		local breach = def.lastStand.breach
		if attack.stage == "tell" then
			predator.mode = "windup"
			-- It sinks, gathering itself
			local flat = Vector3.new(predator.heading.X, 0, predator.heading.Z)
			desired = Vector3.new(0, -speed * 0.5, 0)
				+ (if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis) * speed * 0.2
			if now >= attack.endsAt then
				attack.stage = "rocket"
				attack.endsAt = now + breach.rocket
				Net.predatorEvent("breach", index, { stage = "rocket", seconds = breach.rocket })
			end
		elseif attack.stage == "rocket" then
			predator.mode = "hunt"
			desired = Vector3.new(0, speed * 2.6, 0)
			if now >= attack.endsAt then
				attack.stage = "crash"
				attack.endsAt = now + breach.crash
				Net.predatorEvent("breach", index, { stage = "crash", seconds = breach.crash })
			end
		elseif attack.stage == "crash" then
			predator.mode = "hunt"
			desired = Vector3.new(0, -speed * 3.2, 0)
			if now >= attack.endsAt then
				local center = predator.position
				strike(boss, attack, breach.fraction, now, function(fish)
					local offset = fish.root.Position - center
					local flat = Vector3.new(offset.X, 0, offset.Z)
					return flat.Magnitude <= breach.radius + fish.length * 0.4
						and math.abs(offset.Y) <= breach.band
				end, function(fish)
					local offset = fish.root.Position - center
					local flat = Vector3.new(offset.X, 0, offset.Z)
					local out = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
					return out * breach.push + Vector3.new(0, 15, 0)
				end)
				Net.predatorEvent(
					"shock",
					index,
					{ x = center.X, y = center.Y, z = center.Z, radius = breach.radius }
				)
				boss.exhaustedUntil = now + def.lastStand.exhausted
				boss.nextBreachAt = now + def.lastStand.breachEvery + def.lastStand.exhausted
				Net.predatorEvent("exhausted", index, { seconds = def.lastStand.exhausted })
				boss.attack = nil
				broadcast()
			end
		end
	end
	return desired
end

local function enterPhase(boss: Boss, phase: number, now: number)
	boss.phase = phase
	local def = boss.def
	local index = boss.predator.index
	if phase == 2 then
		boss.bloodUntil = now + 10
		Net.predatorEvent("blood", index, { seconds = 10 })
		Net.notifyAll(`The {string.upper(def.name)} is in a FRENZY!`, "bad")
	elseif phase == 3 then
		boss.lastStandUntil = now + def.lastStand.clock
		boss.nextBreachAt = now + 4
		endMark(boss, now)
		boss.attack = nil
		Net.predatorEvent("laststand", index, { seconds = def.lastStand.clock })
		Net.notifyAll(
			`LAST STAND · the {string.upper(def.name)} makes for the Trench · {def.lastStand.clock} s`,
			"bad"
		)
	end
	broadcast()
end

local function escape(boss: Boss, now: number)
	active = nil
	PredatorService.remove(boss.predator, "escaped")
	Net.notifyAll(`The {string.upper(boss.def.name)} slipped away into the Trench. It will be back.`, "info")
	schedule(now, boss.def.event.escapeDelay)
	broadcast()
end

local function pickWeighted<T>(list: { T }, weight: (T) -> number): T?
	local total = 0
	for _, item in list do
		total += weight(item)
	end
	if total <= 0 then
		return nil
	end
	local pick = rng:NextNumber() * total
	for _, item in list do
		pick -= weight(item)
		if pick <= 0 then
			return item
		end
	end
	return list[#list]
end

local function rollShade(minTier: string)
	local floor = Tiers.byId[minTier]
	local pool = {}
	for _, shade in Config.Shades.list do
		local tier = Tiers.byId[shade.tier]
		if
			shade.chance > 0
			and not shade.boss
			and not shade.treasure
			and tier
			and floor
			and tier.order >= floor.order
		then
			table.insert(pool, shade)
		end
	end
	return pickWeighted(pool, function(shade)
		return 1 / shade.chance
	end)
end

local function rewards(boss: Boss, killer: Player?)
	local def = boss.def
	local reward = def.rewards
	local predator = boss.predator
	local total = 0
	local ranked: { { player: Player, damage: number } } = {}
	for player, record in predator.hitBy do
		total += record.damage
		table.insert(ranked, { player = player, damage = record.damage })
	end
	if total <= 0 then
		return
	end
	table.sort(ranked, function(a, b)
		return a.damage > b.damage
	end)
	for rank, entry in ranked do
		local player = entry.player
		local share = entry.damage / total
		if player.Parent == nil or share < reward.minShare then
			continue
		end
		local data = DataService.get(player)
		if data == nil then
			continue
		end
		local teeth = reward.each
			+ (if rank <= 3 then reward.topThree else 0)
			+ (if player == killer then reward.killer else 0)
		local summary: { [string]: any } = {
			boss = def.id,
			name = def.name,
			currencyName = reward.currencyName,
			rank = rank,
			share = share,
		}
		-- The Haul (carry it home), the coral jackpot
		local haul = reward.haulKg * math.max(share, reward.minHaulShare)
		HuntService.feed(player, haul)
		summary.haul = haul
		local coral = math.floor(math.max(reward.coral * share, reward.coralMin) + 0.5)
		EconomyService.addCoral(player, coral)
		summary.coral = coral
		-- A shade roll, Rare or better
		local shade = rollShade(reward.shadeRollMin)
		if shade then
			local duplicate = data.shades[shade.id] == true
			if duplicate then
				EconomyService.addCoral(player, shade.refund)
			else
				data.shades[shade.id] = true
			end
			summary.shade = {
				id = shade.id,
				name = shade.name,
				tier = shade.tier,
				duplicate = duplicate,
				coral = shade.refund,
			}
		end
		-- The trophy straight from the kill, sometimes (twice as often for the top dealer)
		local chance = reward.dropChance * (if rank == 1 then 2 else 1)
		if rng:NextNumber() < chance then
			if data.shades[reward.dropShade] then
				teeth += 3
				summary.extraTeeth = 3
			else
				data.shades[reward.dropShade] = true
				summary.trophy = reward.dropShade
			end
		end
		data.trophies[reward.trophyCurrency] = (data.trophies[reward.trophyCurrency] or 0) + teeth
		summary.teeth = teeth
		-- The title (worn at once if none is)
		if not data.titles[reward.title] then
			data.titles[reward.title] = true
			summary.title = reward.title
		end
		if data.title == "" then
			data.title = reward.title
			local character = FishService.character(player)
			if character then
				character:SetAttribute("Title", reward.title)
			end
		end
		data.stats.bossKills += 1
		Events.ate:fire(player, 1)
		DataService.markDirty(player)
		Net.bossReward(player, summary)
		if summary.trophy then
			task.delay(6, function()
				Net.notifyAll(
					`{player.DisplayName} won the {string.upper(reward.dropShade)} shade from the {string.upper(
						def.name
					)}!`,
					"rare"
				)
			end)
			DataService.save(player)
		end
	end
end

local function onDied(predator: Predator, killer: Player?)
	local boss = active
	if boss == nil or boss.predator ~= predator then
		return
	end
	if killer == nil then
		return -- removed (an escape): nothing to pay
	end
	active = nil
	Net.notifyAll(
		`{killer.DisplayName} landed the killing bite on the {string.upper(boss.def.name)}!`,
		"rare"
	)
	rewards(boss, killer)
	schedule(Timing.clock(), interval(boss.def))
	rotationIndex += 1
	broadcast()
end

-- Every player bite on the boss: soft spots double it, a stagger or exhaustion
-- triples it, and soft-spot damage fills the stagger meter.
local function onHit(predator: Predator, _player: Player, damage: number, point: Vector3): number
	local boss = active
	if boss == nil or boss.predator ~= predator then
		return damage
	end
	local def = boss.def
	local now = Timing.clock()
	local _, t = alongBody(predator, point)
	local soft = false
	for _, spot in def.softSpots do
		if t >= spot.from and t <= spot.to then
			soft = true
		end
	end
	local multiplier = 1
	if soft then
		multiplier *= def.stagger.softMultiplier
	end
	local stunned = boss.staggeredUntil > now or boss.exhaustedUntil > now
	if stunned then
		multiplier *= def.stagger.staggerMultiplier
	end
	local final = damage * multiplier
	if soft and not stunned then
		boss.stagger += final
		predator.meter = math.clamp(boss.stagger / def.stagger.need, 0, 1)
		if boss.stagger >= def.stagger.need and now >= boss.staggerReadyAt then
			boss.stagger = 0
			predator.meter = 0
			boss.staggeredUntil = now + def.stagger.seconds
			boss.staggerReadyAt = now + def.stagger.seconds + def.stagger.cooldown
			boss.attack = nil
			endMark(boss, now)
			Net.predatorEvent("stagger", predator.index, { seconds = def.stagger.seconds })
			Net.notifyAll(`The {string.upper(def.name)} is STAGGERED · bite it!`, "good")
			broadcast()
		end
	end
	return final
end

local function summon(def: BossDef, now: number)
	local predator = PredatorService.add(def.predator, patrolPoint(def))
	predator.onHit = onHit
	predator.maxHealth = def.baseHealth
	predator.health = def.baseHealth
	active = {
		def = def,
		predator = predator,
		phase = 1,
		attack = nil,
		cooldowns = {},
		nextAttackAt = now + 3,
		nextTargetAt = 0,
		mark = nil,
		stagger = 0,
		staggeredUntil = 0,
		staggerReadyAt = now + 15,
		exhaustedUntil = 0,
		lastStandUntil = 0,
		nextBreachAt = 0,
		bloodUntil = 0,
		waypoint = patrolPoint(def),
		waypointUntil = now + 15,
		spawnedAt = now,
	}
	warned = false
	Net.notifyAll(`THE {string.upper(def.name)} RISES`, "bad")
	broadcast()
end

local function countBehind(boss: Boss, now: number): number
	local predator = boss.predator
	local count = 0
	for _, fish in fishAround(now) do
		local offset = fish.root.Position - predator.position
		if offset.Magnitude <= boss.def.sweep.radius and predator.heading:Dot(offset.Unit) < -0.1 then
			count += 1
		end
	end
	return count
end

local function chooseAttack(boss: Boss, now: number)
	local def = boss.def
	local predator = boss.predator
	local cooldowns = boss.cooldowns
	boss.nextAttackAt = now + 0.3
	if boss.phase == 3 and now >= boss.nextBreachAt then
		startAttack(boss, "breach", "tell", def.lastStand.breach.telegraph, nil, now)
		Net.predatorEvent("breach", predator.index, {
			stage = "tell",
			seconds = def.lastStand.breach.telegraph,
			x = predator.position.X,
			z = predator.position.Z,
		})
		return
	end
	local mark = boss.mark
	if mark and now >= mark.nextLungeAt then
		mark.nextLungeAt = now + def.mark.lungeEvery
		startAttack(boss, "lunge", "tell", def.mark.lungeTell, mark.target, now)
		Net.predatorEvent(
			"windup",
			predator.index,
			{ target = mark.target.UserId, seconds = def.mark.lungeTell }
		)
		return
	end
	local root, fishLength = PredatorService.targetRoot(predator)
	local target = predator.target
	if root == nil or target == nil then
		return
	end
	if
		boss.phase >= 2
		and (cooldowns.sweep or 0) <= now
		and countBehind(boss, now) >= def.sweep.behindMin
	then
		startAttack(boss, "sweep", "tell", def.sweep.telegraph, nil, now)
		Net.predatorEvent("sweep", predator.index, {
			seconds = def.sweep.telegraph,
			x = predator.position.X,
			y = predator.position.Y,
			z = predator.position.Z,
			radius = def.sweep.radius,
		})
		return
	end
	if boss.phase >= 2 and mark == nil and (cooldowns.mark or 0) <= now and now - boss.spawnedAt > 10 then
		boss.mark = { target = target, endsAt = now + def.mark.seconds, nextLungeAt = now + 1 }
		Net.predatorEvent("marked", predator.index, { target = target.UserId, seconds = def.mark.seconds })
		Net.notify(target, "MARKED FOR DEATH · the Megalodon has your scent", "bad")
		broadcast()
		return
	end
	local distance = (root.Position - PredatorService.mouthOf(predator)).Magnitude
	if (cooldowns.bite or 0) <= now and distance <= def.bite.trigger + fishLength * 0.5 then
		startAttack(boss, "bite", "tell", def.bite.telegraph, target, now)
		Net.predatorEvent("windup", predator.index, { target = target.UserId, seconds = def.bite.telegraph })
		return
	end
	if
		(cooldowns.charge or 0) <= now
		and distance >= def.charge.minRange
		and distance <= def.charge.maxRange
	then
		startAttack(boss, "charge", "tell", def.charge.telegraph, target, now)
		Net.predatorEvent(
			"charge",
			predator.index,
			{ target = target.UserId, seconds = def.charge.telegraph }
		)
		return
	end
end

local function tick(boss: Boss, dt: number, now: number)
	local def = boss.def
	local predator = boss.predator
	if predator.mode == "dead" then
		return
	end
	-- Health scales with how many are attacking
	local attackers = 0
	for _, record in predator.hitBy do
		if now - record.at < def.attackerWindow then
			attackers += 1
		end
	end
	local wantMax = def.baseHealth * (1 + def.healthPerAttacker * math.max(attackers - 1, 0))
	if math.abs(wantMax - predator.maxHealth) > 1 then
		predator.health = predator.health * wantMax / predator.maxHealth
		predator.maxHealth = wantMax
	end
	-- Phases
	local fraction = predator.health / predator.maxHealth
	local phase = if fraction > def.phases[1] then 1 elseif fraction > def.phases[2] then 2 else 3
	if phase > boss.phase then
		enterPhase(boss, phase, now)
	end
	if boss.phase == 3 and now >= boss.lastStandUntil then
		escape(boss, now)
		return
	end
	-- The mark runs out, or its fish is gone
	local mark = boss.mark
	if mark then
		local session = HuntService.sessions()[mark.target]
		if now >= mark.endsAt or session == nil or not session.alive or session.inHub then
			endMark(boss, now)
			mark = nil
		end
	end
	-- Pick a target now and then (the marked fish while a mark holds)
	if mark then
		predator.target = mark.target
	elseif now >= boss.nextTargetAt then
		boss.nextTargetAt = now + 0.5
		local root = PredatorService.targetRoot(predator)
		local session = if predator.target then HuntService.sessions()[predator.target :: Player] else nil
		if root == nil or session == nil or not session.alive or session.inHub then
			predator.target = PredatorService.pickTarget(predator, now)
		end
	end

	local stunned = boss.staggeredUntil > now or boss.exhaustedUntil > now
	local speed = speedOf(boss)
	local desired: Vector3
	local turnRate: number? = nil
	local attack = boss.attack
	if stunned then
		predator.mode = "recover"
		desired = predator.velocity * 0.05
		boss.attack = nil
	elseif attack then
		desired = runAttack(boss, attack, dt, now)
		if attack.stage == "go" then
			turnRate = 6 -- locked on
		end
	else
		if now >= boss.nextAttackAt then
			chooseAttack(boss, now)
		end
		local root = PredatorService.targetRoot(predator)
		if boss.attack then
			desired = predator.velocity
		elseif boss.phase == 3 then
			-- Making for the Trench, slowly, until the clock runs out
			local trench = World.trench.center
			local goal = Vector3.new(trench.X, 30, trench.Z)
			local offset = goal - predator.position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if flat.Magnitude < 90 then
				local tangent = Vector3.new(-flat.Z, 0, flat.X).Unit
				desired = tangent * speed * 0.45
			else
				desired = offset.Unit * speed * 0.4
			end
			predator.mode = "hunt"
		elseif root then
			local lead = root.Position + root.AssemblyLinearVelocity * 0.3
			local toward = lead - PredatorService.mouthOf(predator)
			desired = (if toward.Magnitude > 1e-3 then toward.Unit else predator.heading)
				* speed
				* (if mark then def.mark.speedMul else 1)
			predator.mode = "hunt"
		else
			if (boss.waypoint - predator.position).Magnitude < 15 or now > boss.waypointUntil then
				boss.waypoint = patrolPoint(def)
				boss.waypointUntil = now + 15
			end
			desired = (boss.waypoint - predator.position).Unit * speed * 0.55
			predator.mode = "roam"
		end
	end
	PredatorService.steer(predator, desired, dt, turnRate)
end

-- Summons a boss now (Studio testing, and the event clock).
function BossService.summon(id: string?)
	if active then
		return
	end
	local def = if id then Bosses.byId[id] else nextDef()
	if def then
		summon(def, Timing.clock())
	end
end

function BossService.active(): Boss?
	return active
end

function BossService.start()
	local now = Timing.clock()
	schedule(now, interval(nextDef()))
	PredatorService.died:connect(onDied)
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Config.Predators.tickSeconds then
			return
		end
		local step = accumulator
		accumulator = 0
		local clock = Timing.clock()
		local boss = active
		if boss then
			Guard.run("BossService.tick", function()
				tick(boss, step, clock)
			end)
			return
		end
		local def = nextDef()
		if not warned and clock >= nextEventAt - def.event.warning then
			warned = true
			Net.notifyAll(
				`THE {string.upper(def.name)} RISES IN {math.floor(def.event.warning / 60)} MINUTES · gather in the Open Blue`,
				"bad"
			)
			broadcast()
		elseif clock >= nextEventAt then
			summon(def, clock)
		end
	end)
	DataService.loaded:connect(function(player: Player)
		Net.bossStateTo(player, stateOf())
	end)
	DataService.releasing:connect(function(player: Player)
		local boss = active
		if boss and boss.mark and boss.mark.target == player then
			endMark(boss, Timing.clock())
		end
	end)
	if Timing.isStudio() then
		-- Studio testing from the Server command bar (a require there gets its own
		-- module copy, so the real service is reached through _G):
		--   _G.ApexBoss.summon()            -- raise the next boss now
		--   _G.ApexBoss.hurt(0.5)           -- take half its health off
		(_G :: any).ApexBoss = {
			summon = BossService.summon,
			hurt = function(fraction: number)
				local boss = active
				if boss then
					boss.predator.health =
						math.max(boss.predator.health - boss.predator.maxHealth * fraction, 1)
				end
			end,
		}
	end
end

return BossService
