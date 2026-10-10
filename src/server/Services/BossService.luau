--!strict
-- World bosses (Config/Bosses, GDD §8). A boss is a `custom` predator: PredatorService
-- streams it and checks the players' bites, and this service does the rest. The
-- event clock raises one about every half hour (two minutes' warning), the bosses
-- taking turns. Each hunts the biggest fish around, telegraphs every attack, and
-- moves through three phases as its health falls. Two kits:
--   shark (Megalodon): Hunting (charge, bite), Frenzy (faster, blood cloud, tail
--     sweep, Marked for death), Last stand (makes for the open ocean on a clock,
--     breaching on the way; catch it or it escapes).
--   squid (Giant Squid, keeps to the Trench): Lurker (tentacle grabs, ink then a jet away), Enraged (two
--     grabs, whirlpool), Mantle (up into open water: beak slam, siphon blast; sinks
--     away after its clock).
-- Health scales with the number of attackers; soft spots take double damage and
-- fill a stagger meter that stuns it. Everyone who dealt a share of the damage is
-- paid: Teeth or Beaks for the Trophy Hunter, a huge Haul, coral, a shade roll, a
-- title, and a chance at the trophy shade straight from the kill. Nothing one-shots.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BossesConfig = require(ReplicatedStorage.Shared.Config.Bosses)
local Config = require(ReplicatedStorage.Shared.Config)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local Progress = require(script.Parent.Parent.Progress)
local FishService = require(script.Parent.FishService)
local HuntService = require(script.Parent.HuntService)
local PredatorService = require(script.Parent.PredatorService)

local Bosses = Config.Bosses
local Tiers = Config.Tiers
local World = Config.World

type BossDef = BossesConfig.BossDef
type SharkKit = BossesConfig.SharkKit
type SquidKit = BossesConfig.SquidKit
type Predator = PredatorService.Predator

type Attack = {
	kind: string, -- shark: bite, charge, lunge, sweep, breach · squid: grab, ink, jet, whirlpool, slam, siphon
	stage: string, -- tell, go, recover, rocket, crash
	endsAt: number,
	target: Player?,
	aim: Vector3, -- a locked direction (charges)
	hit: { [Player]: boolean }, -- fish already hurt by this attack
}

type Grab = {
	endsAt: number,
	dealt: number, -- share of the fish's health taken so far (stops at grab.maxShare)
	struggles: number,
	bites: number,
	biters: { [Player]: boolean },
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
	grabs: { [Player]: Grab },
	grabFree: { [Player]: number }, -- when a fish let go can be grabbed again
	whirl: { endsAt: number, center: Vector3 }?,
	inkUntil: number,
	stagger: number, -- damage on soft spots toward a stagger
	staggeredUntil: number,
	staggerReadyAt: number,
	exhaustedUntil: number,
	lastStandUntil: number, -- the third phase's escape clock
	escapeGoal: Vector3, -- where the last stand makes for
	nextBreachAt: number,
	bloodUntil: number,
	waypoint: Vector3,
	waypointUntil: number,
	homeUntil: number, -- heading back home after a chase led it out
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

local function depthBand(boss: Boss): { number }
	local squid = boss.def.squid
	if squid then
		return if boss.phase >= 3 then squid.mantleDepth else squid.lurkDepth
	end
	return boss.def.patrol.depth
end

local function patrolPoint(def: BossDef, depth: { number }?): Vector3
	local patrol = def.patrol
	local band = depth or patrol.depth
	if patrol.trench then
		-- Somewhere along the canyon, away from its ends and walls
		local trench = World.trench
		local r = rng:NextNumber(trench.radii[1] + 50, trench.radii[2] - 50)
		local _, width = Seafloor.trenchAxis(r)
		local x, z = Seafloor.trenchPoint(r, rng:NextNumber(-0.3, 0.3) * width)
		return Vector3.new(x, Seafloor.y(x, z) + rng:NextNumber(band[1], band[2]), z)
	end
	local base = math.atan2(patrol.direction.Z, patrol.direction.X)
	local angle = base + rng:NextNumber(-patrol.spread, patrol.spread)
	local distance = rng:NextNumber(patrol.band[1], patrol.band[2])
	local x, z = math.cos(angle) * distance, math.sin(angle) * distance
	return Vector3.new(x, Seafloor.y(x, z) + rng:NextNumber(band[1], band[2]), z)
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

-- The squid's beak sits where the arms meet, a little behind its center
local function beakOf(predator: Predator): Vector3
	return predator.position + predator.heading * predator.def.length * 0.1
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
	local shark = boss.def.shark
	boss.cooldowns.mark = now + (if shark then shark.mark.cooldown else 20)
	Net.predatorEvent("unmarked", boss.predator.index, {})
	broadcast()
end

-- A grab lets go: the fish swims again, pushed off the beak
local function release(boss: Boss, player: Player, how: string, now: number)
	local grab = boss.grabs[player]
	if grab == nil then
		return
	end
	boss.grabs[player] = nil
	local squidKit = boss.def.squid
	if squidKit then
		boss.grabFree[player] = now + squidKit.grab.recover
	end
	local character, root = FishService.character(player)
	if character then
		character:SetAttribute("HeldBy", nil)
		character:SetAttribute("HeldUntil", nil)
	end
	if root and how ~= "eaten" then
		local away = root.Position - beakOf(boss.predator)
		local flat = Vector3.new(away.X, 0, away.Z)
		local out = if flat.Magnitude > 1e-3 then flat.Unit else -boss.predator.heading
		Net.shove(player, out * 40 + Vector3.new(0, 10, 0))
	end
	Net.predatorEvent("released", boss.predator.index, { target = player.UserId, how = how })
	if how == "bitten" then
		local squid = boss.def.squid
		local beaks = if squid then squid.grab.freeBeaks else 0
		if beaks > 0 then
			for biter in grab.biters do
				local data = DataService.get(biter)
				if data and biter ~= player then
					local currency = boss.def.rewards.trophyCurrency
					data.trophies[currency] = (data.trophies[currency] or 0) + beaks
					DataService.markDirty(biter)
					Net.notify(
						biter,
						`You bit {player.DisplayName} free · +{beaks} {boss.def.rewards.currencyName}`,
						"good"
					)
				end
			end
		end
		Net.notify(player, "Your team bit you free!", "good")
	elseif how == "struggled" then
		Net.notify(player, "You broke free!", "good")
	end
	local _ = now
end

local function releaseAll(boss: Boss, how: string, now: number)
	for player in boss.grabs do
		release(boss, player, how, now)
	end
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

local function runShark(boss: Boss, attack: Attack, now: number, root: BasePart?, fishLength: number): Vector3
	local predator = boss.predator
	local def = boss.def
	local shark = def.shark :: SharkKit
	local speed = speedOf(boss)
	local index = predator.index
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
					local reach = shark.bite.reach * 1.6 + fishLength * 0.5 + Size.topSpeed(fishLength) * 0.15
					hit = (root.Position - mouth).Magnitude <= reach
					if hit then
						HuntService.damage(attack.target :: Player, shark.bite.fraction, def.name)
					end
				end
				Net.predatorEvent("bite", index, { hit = hit, x = mouth.X, y = mouth.Y, z = mouth.Z })
				attack.stage = "recover"
				attack.endsAt = now + 1.2
				boss.cooldowns.bite = now + shark.bite.cooldown
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
		local fraction = if lunge then shark.mark.lungeFraction else shark.charge.fraction
		local radius = if lunge then shark.charge.radius * 0.8 else shark.charge.radius
		if attack.stage == "tell" then
			predator.mode = "windup"
			-- Eyes flash: it slows and lines up on the fish
			desired = direction * speed * 0.15
			if now >= attack.endsAt then
				attack.aim = if root
					then ((root.Position + root.AssemblyLinearVelocity * 0.4) - predator.position).Unit
					else predator.heading
				attack.stage = "go"
				attack.endsAt = now + (if lunge then shark.mark.lungeSeconds else shark.charge.seconds)
				Net.predatorEvent("rush", index, { seconds = attack.endsAt - now })
			end
		elseif attack.stage == "go" then
			predator.mode = "hunt"
			desired = attack.aim * speed * (if lunge then 2 else shark.charge.speedMul)
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
					boss.cooldowns.charge = now + shark.charge.cooldown
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
				strike(boss, attack, shark.sweep.fraction, now, function(fish)
					local offset = fish.root.Position - center
					return offset.Magnitude <= shark.sweep.radius + fish.length * 0.4
						and predator.heading:Dot(offset.Unit) < 0.25
				end, function(fish)
					local offset = fish.root.Position - center
					local flat = Vector3.new(offset.X, 0, offset.Z)
					local out = if flat.Magnitude > 1e-3 then flat.Unit else -predator.heading
					return out * shark.sweep.push + Vector3.new(0, 12, 0)
				end)
				Net.predatorEvent(
					"swept",
					index,
					{ x = center.X, y = center.Y, z = center.Z, radius = shark.sweep.radius }
				)
				attack.stage = "recover"
				attack.endsAt = now + 0.8
				boss.cooldowns.sweep = now + shark.sweep.cooldown
			end
		else
			predator.mode = "recover"
			desired = predator.heading * speed * 0.4
			if now >= attack.endsAt then
				boss.attack = nil
			end
		end
	elseif attack.kind == "breach" then
		local breach = shark.breach
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
				boss.exhaustedUntil = now + shark.exhausted
				boss.nextBreachAt = now + shark.breachEvery + shark.exhausted
				Net.predatorEvent("exhausted", index, { seconds = shark.exhausted })
				boss.attack = nil
				broadcast()
			end
		end
	end
	return desired
end

local function jetTo(boss: Boss, now: number)
	local predator = boss.predator
	local def = boss.def
	local squid = def.squid :: SquidKit
	local from = predator.position
	-- Somewhere `distance` away, still inside the patrol band
	local destination = from
	for _ = 1, 12 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local candidate = from + Vector3.new(math.cos(angle), 0, math.sin(angle)) * squid.jet.distance
		local flat = Vector3.new(candidate.X, 0, candidate.Z).Magnitude
		local inside = if def.patrol.trench
			then Seafloor.inTrench(candidate.X, candidate.Z, -20)
			else flat >= def.patrol.band[1] and flat <= def.patrol.band[2]
		if inside then
			destination = candidate
			break
		end
	end
	local band = depthBand(boss)
	destination = Vector3.new(
		destination.X,
		Seafloor.y(destination.X, destination.Z) + rng:NextNumber(band[1], band[2]),
		destination.Z
	)
	Net.predatorEvent("jetted", predator.index, {
		fromX = from.X,
		fromY = from.Y,
		fromZ = from.Z,
		x = destination.X,
		y = destination.Y,
		z = destination.Z,
	})
	predator.position = destination
	predator.velocity = Vector3.zero
	boss.cooldowns.jet = now + squid.jet.cooldown
end

local function runSquid(boss: Boss, attack: Attack, now: number, root: BasePart?, fishLength: number): Vector3
	local predator = boss.predator
	local def = boss.def
	local squid = def.squid :: SquidKit
	local speed = speedOf(boss)
	local index = predator.index
	local beak = beakOf(predator)
	local toward = if root
		then (root.Position + root.AssemblyLinearVelocity * 0.3 - beak)
		else predator.heading
	local direction = if toward.Magnitude > 1e-3 then toward.Unit else predator.heading
	local desired = predator.heading * speed * 0.3

	if attack.kind == "grab" then
		if attack.stage == "tell" then
			predator.mode = "windup"
			desired = direction * speed * 0.3
			if now >= attack.endsAt then
				local target = attack.target :: Player
				local session = HuntService.sessions()[target]
				local caught = root ~= nil
					and session ~= nil
					and session.alive
					and not session.inHub
					and session.safeUntil <= now
					and (boss.grabFree[target] or 0) <= now
					and (root.Position - beak).Magnitude <= squid.grab.range + fishLength * 0.5
				if caught then
					boss.grabs[target] = {
						endsAt = now + squid.grab.seconds,
						dealt = 0,
						struggles = 0,
						bites = 0,
						biters = {},
					}
					local character = FishService.character(target)
					if character then
						character:SetAttribute("HeldBy", index)
						character:SetAttribute("HeldUntil", now + squid.grab.seconds)
					end
					Net.predatorEvent(
						"grabbed",
						index,
						{ target = target.UserId, seconds = squid.grab.seconds }
					)
					Net.notify(target, "GRABBED · mash BITE to break free", "bad")
				else
					Net.predatorEvent(
						"grab",
						index,
						{ target = 0, seconds = 0, missed = true, x = beak.X, y = beak.Y, z = beak.Z }
					)
				end
				boss.cooldowns.grab = now + squid.grab.cooldown * (if boss.phase >= 2 then 0.5 else 1)
				attack.stage = "recover"
				attack.endsAt = now + 0.6
			end
		else
			predator.mode = "hunt"
			desired = predator.velocity * 0.5
			if now >= attack.endsAt then
				boss.attack = nil
			end
		end
	elseif attack.kind == "ink" then
		-- The cloud bursts at once; the attack is the moment it holds still in it
		predator.mode = "recover"
		desired = predator.velocity * 0.3
		if now >= attack.endsAt then
			boss.attack = nil
			-- Then it's gone: the jet follows straight away
			boss.cooldowns.jet = 0
			boss.nextAttackAt = now
		end
	elseif attack.kind == "jet" then
		if attack.stage == "tell" then
			predator.mode = "windup"
			desired = -predator.heading * speed * 0.3
			if now >= attack.endsAt then
				jetTo(boss, now)
				boss.attack = nil
			end
		end
	elseif attack.kind == "whirlpool" then
		if attack.stage == "tell" then
			predator.mode = "windup"
			desired = predator.velocity * 0.1
			if now >= attack.endsAt then
				boss.whirl = { endsAt = now + squid.whirlpool.seconds, center = predator.position }
				Net.predatorEvent("whirling", index, {
					seconds = squid.whirlpool.seconds,
					radius = squid.whirlpool.radius,
					x = predator.position.X,
					y = predator.position.Y,
					z = predator.position.Z,
				})
				attack.stage = "go"
				attack.endsAt = now + squid.whirlpool.seconds
			end
		elseif attack.stage == "go" then
			predator.mode = "hunt"
			desired = Vector3.zero
			if now >= attack.endsAt then
				boss.whirl = nil
				boss.cooldowns.whirlpool = now + squid.whirlpool.cooldown
				Net.predatorEvent("whirled", index, {})
				boss.attack = nil
			end
		end
	elseif attack.kind == "slam" then
		if attack.stage == "tell" then
			predator.mode = "windup"
			desired = direction * speed * 0.4
			if now >= attack.endsAt then
				local hit = false
				if root then
					local reach = squid.slam.reach * 1.5 + fishLength * 0.5 + Size.topSpeed(fishLength) * 0.15
					hit = (root.Position - beak).Magnitude <= reach
					if hit then
						HuntService.damage(attack.target :: Player, squid.slam.fraction, def.name)
					end
				end
				Net.predatorEvent("bite", index, { hit = hit, x = beak.X, y = beak.Y, z = beak.Z })
				boss.cooldowns.slam = now + squid.slam.cooldown
				attack.stage = "recover"
				attack.endsAt = now + 1
			end
		else
			predator.mode = "recover"
			desired = predator.heading * speed * 0.3
			if now >= attack.endsAt then
				boss.attack = nil
			end
		end
	elseif attack.kind == "siphon" then
		if attack.stage == "tell" then
			predator.mode = "windup"
			desired = direction * speed * 0.2
			if now >= attack.endsAt then
				local origin = beak
				local heading = predator.heading
				strike(boss, attack, squid.siphon.fraction, now, function(fish)
					local offset = fish.root.Position - origin
					return offset.Magnitude <= squid.siphon.range + fish.length * 0.4
						and offset.Magnitude > 1e-3
						and heading:Dot(offset.Unit) >= squid.siphon.cosine
				end, function(fish)
					local offset = fish.root.Position - origin
					local out = if offset.Magnitude > 1e-3 then offset.Unit else heading
					return (heading * 0.7 + out * 0.3).Unit * squid.siphon.push
				end)
				Net.predatorEvent("siphoned", index, {
					x = origin.X,
					y = origin.Y,
					z = origin.Z,
					hx = heading.X,
					hy = heading.Y,
					hz = heading.Z,
					range = squid.siphon.range,
				})
				boss.cooldowns.siphon = now + squid.siphon.cooldown
				attack.stage = "recover"
				attack.endsAt = now + 1
			end
		else
			predator.mode = "recover"
			desired = predator.heading * speed * 0.3
			if now >= attack.endsAt then
				boss.attack = nil
			end
		end
	end
	return desired
end

local function runAttack(boss: Boss, attack: Attack, now: number): Vector3
	local root, fishLength = targetOf(boss)
	if boss.def.kit == "squid" then
		return runSquid(boss, attack, now, root, fishLength)
	end
	return runShark(boss, attack, now, root, fishLength)
end

local function enterPhase(boss: Boss, phase: number, now: number)
	boss.phase = phase
	local def = boss.def
	local index = boss.predator.index
	local name = string.upper(def.name)
	if def.kit == "shark" then
		local shark = def.shark :: SharkKit
		if phase == 2 then
			boss.bloodUntil = now + 10
			Net.predatorEvent("blood", index, { seconds = 10 })
			Net.notifyAll(`The {name} is in a FRENZY!`, "bad")
		elseif phase == 3 then
			boss.lastStandUntil = now + def.escapeClock
			boss.nextBreachAt = now + 4
			-- Out to the far edge of its own open water, the way it's facing (the
			-- Trench was 2,000 studs off and the deepest dark is the squid's; owner,
			-- 2026-10-09: the Megalodon is "not for deepest darkest ocean just deep blue")
			local patrol = def.patrol
			local base = math.atan2(patrol.direction.Z, patrol.direction.X)
			local at = boss.predator.position
			local off = math.atan2(at.Z, at.X) - base
			off = math.clamp((off + math.pi) % (2 * math.pi) - math.pi, -patrol.spread, patrol.spread)
			local out = patrol.band[2] - 40
			local x, z = math.cos(base + off) * out, math.sin(base + off) * out
			boss.escapeGoal = Vector3.new(x, Seafloor.y(x, z) + (patrol.depth[1] + patrol.depth[2]) / 2, z)
			endMark(boss, now)
			boss.attack = nil
			Net.predatorEvent("laststand", index, { seconds = def.escapeClock })
			Net.notifyAll(`LAST STAND · the {name} makes for the open ocean · {def.escapeClock} s`, "bad")
			local _ = shark
		end
	else
		if phase == 2 then
			Net.predatorEvent("enraged", index, {})
			Net.notifyAll(`The {name} is ENRAGED · two tentacles at once`, "bad")
		elseif phase == 3 then
			boss.lastStandUntil = now + def.escapeClock
			releaseAll(boss, "dropped", now)
			boss.attack = nil
			boss.whirl = nil
			Net.predatorEvent("mantle", index, { seconds = def.escapeClock })
			Net.notifyAll(`The {name} RISES into open water · it sinks away in {def.escapeClock} s`, "bad")
		end
	end
	broadcast()
end

local function escape(boss: Boss, now: number)
	active = nil
	releaseAll(boss, "dropped", now)
	local reason = if boss.def.kit == "squid" then "sunk" else "escaped"
	PredatorService.remove(boss.predator, reason)
	Net.notifyAll(
		if boss.def.kit == "squid"
			then `The {string.upper(boss.def.name)} sank back into the Trench. It will be back.`
			else `The {string.upper(boss.def.name)} slipped away into the deep blue. It will be back.`,
		"info"
	)
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

local function rollShade(minTier: string, owned: { [string]: boolean }, species: string)
	local floor = Tiers.byId[minTier]
	local pool = {}
	for _, shade in Config.Shades.list do
		local tier = Tiers.byId[shade.tier]
		if
			Config.Shades.rollable(shade)
			and shade.species == species
			and not owned[shade.id]
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
		summary.haul = HuntService.feed(player, haul) -- (×2 Mass and Server Frenzy count)
		local coral = math.floor(math.max(reward.coral * share, reward.coralMin) + 0.5)
		summary.coral = EconomyService.earnCoral(player, coral)
		-- A shade roll, Rare or better (a fish that has them all gets coral instead:
		-- it got nothing at all, playtest 2026-10-08)
		local shade = rollShade(reward.shadeRollMin, Progress.shades(data), Progress.speciesId(data))
		if shade == nil then
			local instead = math.floor(reward.coral * 0.5)
			EconomyService.addCoral(player, instead)
			summary.shadeCoral = instead
		end
		if shade then
			local duplicate = not Progress.grantShade(data, shade.id)
			if duplicate then
				EconomyService.addCoral(player, shade.refund)
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
			if Progress.grantShade(data, reward.dropShade) then
				summary.trophy = reward.dropShade
			else
				teeth += 3
				summary.extraTeeth = 3
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
		Events.trophies:fire(player)
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
	releaseAll(boss, "dropped", Timing.clock())
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
-- triples it, soft-spot damage fills the stagger meter, and bites help a grabbed
-- teammate break free.
local function onHit(predator: Predator, player: Player, damage: number, point: Vector3): number
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
			boss.whirl = nil
			endMark(boss, now)
			releaseAll(boss, "dropped", now)
			Net.predatorEvent("stagger", predator.index, { seconds = def.stagger.seconds })
			Net.notifyAll(`The {string.upper(def.name)} is STAGGERED · bite it!`, "good")
			broadcast()
		end
	end
	-- Biting the squid while it holds someone loosens the grab
	local squid = def.squid
	if squid then
		for victim, grab in boss.grabs do
			if victim ~= player then
				grab.bites += 1
				grab.biters[player] = true
				if grab.bites >= squid.grab.biteFree then
					release(boss, victim, "bitten", now)
				end
			end
		end
	end
	return final
end

local function onStruggle(player: Player)
	local boss = active
	if boss == nil then
		return
	end
	local grab = boss.grabs[player]
	local squid = boss.def.squid
	if grab == nil or squid == nil then
		return
	end
	grab.struggles += 1
	Net.predatorEvent("struggle", boss.predator.index, {
		target = player.UserId,
		progress = math.clamp(grab.struggles / squid.grab.struggleNeed, 0, 1),
	})
	if grab.struggles >= squid.grab.struggleNeed then
		release(boss, player, "struggled", Timing.clock())
	end
end

local function summon(def: BossDef, now: number)
	local depth = if def.squid then def.squid.lurkDepth else def.patrol.depth
	local predator = PredatorService.add(def.predator, patrolPoint(def, depth))
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
		grabs = {},
		grabFree = {},
		whirl = nil,
		inkUntil = 0,
		stagger = 0,
		staggeredUntil = 0,
		staggerReadyAt = now + 15,
		exhaustedUntil = 0,
		lastStandUntil = 0,
		escapeGoal = Vector3.zero,
		nextBreachAt = 0,
		bloodUntil = 0,
		waypoint = patrolPoint(def, depth),
		waypointUntil = now + 15,
		homeUntil = 0,
		spawnedAt = now,
	}
	warned = false
	Net.notifyAll(`THE {string.upper(def.name)} RISES`, "bad")
	broadcast()
end

local function countNear(boss: Boss, now: number, radius: number, behind: boolean): number
	local predator = boss.predator
	local count = 0
	for _, fish in fishAround(now) do
		local offset = fish.root.Position - predator.position
		if offset.Magnitude <= radius and (not behind or predator.heading:Dot(offset.Unit) < -0.1) then
			count += 1
		end
	end
	return count
end

local function grabCount(boss: Boss): number
	local count = 0
	for _ in boss.grabs do
		count += 1
	end
	return count
end

local function chooseShark(boss: Boss, now: number)
	local def = boss.def
	local shark = def.shark :: SharkKit
	local predator = boss.predator
	local cooldowns = boss.cooldowns
	if boss.phase == 3 and now >= boss.nextBreachAt then
		startAttack(boss, "breach", "tell", shark.breach.telegraph, nil, now)
		Net.predatorEvent("breach", predator.index, {
			stage = "tell",
			seconds = shark.breach.telegraph,
			x = predator.position.X,
			z = predator.position.Z,
		})
		return
	end
	local mark = boss.mark
	if mark and now >= mark.nextLungeAt then
		mark.nextLungeAt = now + shark.mark.lungeEvery
		startAttack(boss, "lunge", "tell", shark.mark.lungeTell, mark.target, now)
		Net.predatorEvent(
			"windup",
			predator.index,
			{ target = mark.target.UserId, seconds = shark.mark.lungeTell }
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
		and countNear(boss, now, shark.sweep.radius, true) >= shark.sweep.behindMin
	then
		startAttack(boss, "sweep", "tell", shark.sweep.telegraph, nil, now)
		Net.predatorEvent("sweep", predator.index, {
			seconds = shark.sweep.telegraph,
			x = predator.position.X,
			y = predator.position.Y,
			z = predator.position.Z,
			radius = shark.sweep.radius,
		})
		return
	end
	if boss.phase >= 2 and mark == nil and (cooldowns.mark or 0) <= now and now - boss.spawnedAt > 10 then
		boss.mark = { target = target, endsAt = now + shark.mark.seconds, nextLungeAt = now + 1 }
		Net.predatorEvent("marked", predator.index, { target = target.UserId, seconds = shark.mark.seconds })
		Net.notify(target, `MARKED FOR DEATH · the {def.name} has your scent`, "bad")
		broadcast()
		return
	end
	local distance = (root.Position - PredatorService.mouthOf(predator)).Magnitude
	if (cooldowns.bite or 0) <= now and distance <= shark.bite.trigger + fishLength * 0.5 then
		startAttack(boss, "bite", "tell", shark.bite.telegraph, target, now)
		Net.predatorEvent(
			"windup",
			predator.index,
			{ target = target.UserId, seconds = shark.bite.telegraph }
		)
		return
	end
	if
		(cooldowns.charge or 0) <= now
		and distance >= shark.charge.minRange
		and distance <= shark.charge.maxRange
	then
		startAttack(boss, "charge", "tell", shark.charge.telegraph, target, now)
		Net.predatorEvent(
			"charge",
			predator.index,
			{ target = target.UserId, seconds = shark.charge.telegraph }
		)
		return
	end
end

local function chooseSquid(boss: Boss, now: number)
	local def = boss.def
	local squid = def.squid :: SquidKit
	local predator = boss.predator
	local cooldowns = boss.cooldowns
	local index = predator.index
	-- Pending jet after an ink
	if boss.inkUntil > now and (cooldowns.jet or 0) <= now then
		startAttack(boss, "jet", "tell", squid.jet.telegraph, nil, now)
		Net.predatorEvent("jet", index, { seconds = squid.jet.telegraph })
		return
	end
	local root, fishLength = PredatorService.targetRoot(predator)
	local target = predator.target
	local attackers = 0
	for _, record in predator.hitBy do
		if now - record.at < 6 then
			attackers += 1
		end
	end
	if boss.phase >= 3 then
		if root and target then
			local distance = (root.Position - beakOf(predator)).Magnitude
			if (cooldowns.slam or 0) <= now and distance <= squid.slam.reach * 1.8 + fishLength * 0.5 then
				startAttack(boss, "slam", "tell", squid.slam.telegraph, target, now)
				Net.predatorEvent("windup", index, { target = target.UserId, seconds = squid.slam.telegraph })
				return
			end
		end
		if (cooldowns.siphon or 0) <= now then
			local inFront = 0
			for _, fish in fishAround(now) do
				local offset = fish.root.Position - beakOf(predator)
				if
					offset.Magnitude <= squid.siphon.range
					and offset.Magnitude > 1e-3
					and predator.heading:Dot(offset.Unit) >= squid.siphon.cosine
				then
					inFront += 1
				end
			end
			if inFront >= 1 then
				startAttack(boss, "siphon", "tell", squid.siphon.telegraph, nil, now)
				Net.predatorEvent("siphon", index, {
					seconds = squid.siphon.telegraph,
					range = squid.siphon.range,
					x = predator.position.X,
					y = predator.position.Y,
					z = predator.position.Z,
				})
				return
			end
		end
		return
	end
	-- Lurker and Enraged
	if
		boss.phase >= 2
		and (cooldowns.whirlpool or 0) <= now
		and countNear(boss, now, squid.whirlpool.radius, false) >= 2
	then
		startAttack(boss, "whirlpool", "tell", squid.whirlpool.telegraph, nil, now)
		Net.predatorEvent("whirl", index, {
			seconds = squid.whirlpool.telegraph,
			radius = squid.whirlpool.radius,
			x = predator.position.X,
			y = predator.position.Y,
			z = predator.position.Z,
		})
		return
	end
	if attackers >= 1 and (cooldowns.ink or 0) <= now and now - boss.spawnedAt > 8 then
		startAttack(boss, "ink", "go", 0.8, nil, now)
		boss.inkUntil = now + squid.ink.seconds
		boss.cooldowns.ink = now + squid.ink.cooldown
		Net.predatorEvent("ink", index, {
			seconds = squid.ink.seconds,
			radius = squid.ink.radius,
			x = predator.position.X,
			y = predator.position.Y,
			z = predator.position.Z,
		})
		return
	end
	if root and target and boss.grabs[target] == nil then
		local maxGrabs = if boss.phase >= 2 then 2 else 1
		local distance = (root.Position - beakOf(predator)).Magnitude
		if
			(cooldowns.grab or 0) <= now
			and (boss.grabFree[target] or 0) <= now
			and grabCount(boss) < maxGrabs
			and distance <= squid.grab.range * 1.2 + fishLength * 0.5
		then
			startAttack(boss, "grab", "tell", squid.grab.telegraph, target, now)
			Net.predatorEvent("grab", index, { target = target.UserId, seconds = squid.grab.telegraph })
			return
		end
	end
	if attackers >= 2 and (cooldowns.jet or 0) <= now and predator.health < predator.maxHealth * 0.9 then
		startAttack(boss, "jet", "tell", squid.jet.telegraph, nil, now)
		Net.predatorEvent("jet", index, { seconds = squid.jet.telegraph })
		return
	end
end

local function chooseAttack(boss: Boss, now: number)
	boss.nextAttackAt = now + 0.3
	if boss.def.kit == "squid" then
		chooseSquid(boss, now)
	else
		chooseShark(boss, now)
	end
end

-- Grabs hurt their fish every tick and let go when time runs out
local function tickGrabs(boss: Boss, dt: number, now: number)
	local squid = boss.def.squid
	if squid == nil then
		return
	end
	for player, grab in boss.grabs do
		local session = HuntService.sessions()[player]
		if session == nil or not session.alive or session.inHub or player.Parent == nil then
			release(boss, player, "eaten", now)
			continue
		end
		if now >= grab.endsAt then
			release(boss, player, "dropped", now)
			continue
		end
		local take = math.min(squid.grab.fraction * dt, squid.grab.maxShare - grab.dealt)
		grab.dealt += take
		HuntService.damage(player, take, boss.def.name, true)
		if grab.dealt >= squid.grab.maxShare - 1e-6 then
			release(boss, player, "dropped", now)
		end
	end
	local whirl = boss.whirl
	if whirl then
		for _, fish in fishAround(now) do
			local offset = whirl.center - fish.root.Position
			if offset.Magnitude <= squid.whirlpool.radius and offset.Magnitude > 4 then
				Net.shove(fish.player, offset.Unit * squid.whirlpool.pull * dt)
			end
		end
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
	tickGrabs(boss, dt, now)
	-- The mark runs out, or its fish is gone
	local mark = boss.mark
	if mark then
		local session = HuntService.sessions()[mark.target]
		if now >= mark.endsAt or session == nil or not session.alive or session.inHub then
			endMark(boss, now)
			mark = nil
		end
	end
	-- Pick a target now and then (the marked fish while a mark holds; never a fish
	-- it already holds)
	if mark then
		predator.target = mark.target
	elseif now >= boss.nextTargetAt then
		boss.nextTargetAt = now + 0.5
		local root = PredatorService.targetRoot(predator)
		local current = predator.target
		local session = if current then HuntService.sessions()[current :: Player] else nil
		if
			root == nil
			or session == nil
			or not session.alive
			or session.inHub
			or (current ~= nil and boss.grabs[current :: Player] ~= nil)
		then
			predator.target = PredatorService.pickTarget(predator, now)
			if predator.target and boss.grabs[predator.target :: Player] then
				predator.target = nil
			end
		end
	end
	-- A boss with a home (the squid's Trench) gives up a chase that leads it out and
	-- swims back in for a while before it hunts again
	local leash = def.patrol.leash
	if leash and def.patrol.trench then
		local at = predator.position
		if boss.homeUntil <= now and not Seafloor.inTrench(at.X, at.Z, leash) then
			boss.homeUntil = now + 8
			boss.waypoint = patrolPoint(def, depthBand(boss))
			boss.waypointUntil = now + 8
		end
		local target = predator.target
		if boss.homeUntil > now and target and boss.grabs[target :: Player] == nil then
			predator.target = nil
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
		desired = runAttack(boss, attack, now)
		if attack.stage == "go" and (attack.kind == "charge" or attack.kind == "lunge") then
			turnRate = 6 -- locked on
		end
	else
		if now >= boss.nextAttackAt then
			chooseAttack(boss, now)
		end
		local root = PredatorService.targetRoot(predator)
		if boss.attack then
			desired = predator.velocity
		elseif def.kit == "shark" and boss.phase == 3 then
			-- Making for the open ocean, slowly, until the clock runs out
			local offset = boss.escapeGoal - predator.position
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
			local anchor = if def.kit == "squid" then beakOf(predator) else PredatorService.mouthOf(predator)
			local toward = lead - anchor
			-- A squid holding fish hovers near them instead of ramming
			local holding = def.kit == "squid" and grabCount(boss) > 0
			local shark = def.shark
			local chase = if mark and shark then shark.mark.speedMul elseif holding then 0.25 else 1
			desired = (if toward.Magnitude > 1e-3 then toward.Unit else predator.heading) * speed * chase
			predator.mode = "hunt"
		else
			if (boss.waypoint - predator.position).Magnitude < 15 or now > boss.waypointUntil then
				boss.waypoint = patrolPoint(def, depthBand(boss))
				boss.waypointUntil = now + 15
			end
			desired = (boss.waypoint - predator.position).Unit * speed * 0.55
			predator.mode = "roam"
		end
		-- The squid keeps to its depth band: deep while it lurks, high in its mantle
		-- phase. Hunting, it rises to meet its prey (up to its predator depth limit):
		-- clamped to the band, it sank away from every fish above the Trench floor and
		-- never grabbed (playtest 2026-10-08).
		if def.kit == "squid" then
			local band = depthBand(boss)
			local floor = Seafloor.y(predator.position.X, predator.position.Z)
			local y = predator.position.Y - floor
			local top = band[2]
			if root then
				top = math.clamp(root.Position.Y - floor + 20, band[2], def.predator.depth[2])
			end
			if y < band[1] then
				desired = Vector3.new(desired.X, math.max(desired.Y, speed * 0.5), desired.Z)
			elseif y > top then
				desired = Vector3.new(desired.X, math.min(desired.Y, -speed * 0.5), desired.Z)
			end
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

-- Sends the boss away at once (the admin panel): like an escape, but the next event
-- keeps its normal timing
function BossService.dismiss()
	local boss = active
	if boss == nil then
		return
	end
	local now = Timing.clock()
	active = nil
	releaseAll(boss, "dropped", now)
	PredatorService.remove(boss.predator, if boss.def.kit == "squid" then "sunk" else "escaped")
	Net.notifyAll(`The {string.upper(boss.def.name)} was sent away.`, "info")
	schedule(now, interval(boss.def))
	rotationIndex += 1 -- the other boss is next, as after a kill
	broadcast()
end

function BossService.start()
	local now = Timing.clock()
	schedule(now, interval(nextDef()))
	PredatorService.died:connect(onDied)
	Net.onRequest("Struggle", onStruggle)
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
				`THE {string.upper(def.name)} RISES IN {math.floor(def.event.warning / 60)} MINUTES · {if def.kit
						== "squid"
					then "watch the deep edges"
					else "gather in the Open Blue"}`,
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
		if boss then
			local clock = Timing.clock()
			if boss.mark and boss.mark.target == player then
				endMark(boss, clock)
			end
			if boss.grabs[player] then
				boss.grabs[player] = nil
			end
		end
	end)
	if Timing.isStudio() then
		-- Studio testing from the Server command bar (a require there gets its own
		-- module copy, so the real service is reached through _G):
		--   _G.ApexBoss.summon()                -- raise the next boss now
		--   _G.ApexBoss.summon("GiantSquid")    -- a particular one
		--   _G.ApexBoss.hurt(0.5)               -- take half its health off
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
