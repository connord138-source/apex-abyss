--!strict
-- AI predators (Config/Predators): simulated here ten times a second and streamed to
-- every client (positions, headings, modes), which interpolate them. Each one roams
-- its band, hunts the biggest worthwhile fish in range, shows its jaw for a moment
-- (the tell), then bites for a share of the victim's max health. Players bite back
-- (BitePredator, checked for reach and cooldown); a kill pays everyone who helped by
-- damage share. The world bosses (BossService) are `custom` predators: they ride the
-- same stream and bite checks, but BossService moves them (steer), scales their
-- damage (onHit) and pays their rewards.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PredatorsConfig = require(ReplicatedStorage.Shared.Config.Predators)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local HuntService = require(script.Parent.HuntService)

local Predators = Config.Predators
local World = Config.World
local hunt = Config.Tuning.hunt
local swim = Config.Tuning.swim

export type Def = PredatorsConfig.PredatorDef

export type Mode = "roam" | "hunt" | "windup" | "recover" | "dead"

export type Predator = {
	index: number,
	def: Def,
	position: Vector3,
	velocity: Vector3,
	heading: Vector3,
	health: number,
	maxHealth: number,
	mode: Mode,
	modeUntil: number,
	target: Player?,
	waypoint: Vector3,
	waypointUntil: number,
	respawnAt: number,
	-- Damage dealt by each player this life, and when they last bit (the school bonus)
	hitBy: { [Player]: { damage: number, at: number } },
	-- Set by a boss controller: skips the plain behaviour and the plain loot
	custom: boolean?,
	-- A boss's hook on every player bite: (predator, player, damage, point) → damage
	onHit: ((Predator, Player, number, Vector3) -> number)?,
	-- A boss's stagger meter (0..1), streamed to clients
	meter: number,
}

local PredatorService = {
	-- (predator, killer?) — a predator died (killer nil when it was removed)
	died = require(ReplicatedStorage.Shared.Signal).new(),
}

local predators: { [number]: Predator } = {}
local nextIndex = 1
local rng = Random.new(World.seed + 41)
local lastBite: { [Player]: number } = {}
local accumulator = 0
local STREAM_BATCH = 4 -- creatures per position packet (an entry is ~130 bytes)

local function randomWaypoint(def: Def): Vector3
	for _ = 1, 20 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local sector = def.angles
		if sector then
			local span = (sector[2] - sector[1]) % 360
			angle = math.rad(sector[1] + rng:NextNumber(0, if span == 0 then 360 else span))
		end
		local distance = rng:NextNumber(def.band[1], def.band[2])
		local x, z = math.cos(angle) * distance, math.sin(angle) * distance
		if not Seafloor.inTrench(x, z, 30) then
			return Vector3.new(x, Seafloor.y(x, z) + rng:NextNumber(def.depth[1], def.depth[2]), z)
		end
	end
	local fallback = math.rad(if def.angles then (def.angles[1] + def.angles[2]) / 2 else 0)
	local x, z = math.cos(fallback) * def.band[1], math.sin(fallback) * def.band[1]
	return Vector3.new(x, Seafloor.y(x, z) + def.depth[1] + 10, z)
end

local function spawn(predator: Predator, at: Vector3?)
	predator.position = at or randomWaypoint(predator.def)
	predator.velocity = Vector3.zero
	predator.heading = Vector3.new(1, 0, 0)
	predator.health = predator.maxHealth
	predator.mode = "roam"
	predator.modeUntil = 0
	predator.target = nil
	predator.waypoint = randomWaypoint(predator.def)
	predator.waypointUntil = Timing.clock() + 12
	predator.hitBy = {}
	predator.meter = 0
	Net.predatorEvent("spawned", predator.index, {
		id = predator.def.id,
		x = predator.position.X,
		y = predator.position.Y,
		z = predator.position.Z,
	})
end

local function mouthOf(predator: Predator): Vector3
	return predator.position + predator.heading * predator.def.length * 0.45
end

local function rotateToward(from: Vector3, to: Vector3, maxAngle: number): Vector3
	if to.Magnitude < 1e-4 then
		return from
	end
	to = to.Unit
	local dot = math.clamp(from:Dot(to), -1, 1)
	local angle = math.acos(dot)
	if angle <= maxAngle or angle < 1e-4 then
		return to
	end
	local axis = from:Cross(to)
	if axis.Magnitude < 1e-5 then
		axis = Vector3.yAxis
	end
	return CFrame.fromAxisAngle(axis.Unit, maxAngle):VectorToWorldSpace(from)
end

-- The fish worth hunting: alive, not safe, in range, big enough (or it bit us).
local function pickTarget(predator: Predator, now: number): Player?
	local def = predator.def
	local best: Player? = nil
	local bestScore = -math.huge
	for player, record in HuntService.sessions() do
		local character, root = FishService.character(player)
		if character == nil or root == nil or not record.alive or record.inHub then
			continue
		end
		if record.safeUntil > now then
			continue
		end
		local distance = (root.Position - predator.position).Magnitude
		local hit = predator.hitBy[player]
		local provoked = hit ~= nil and now - hit.at < 8
		if distance > (if provoked then def.aggroRange * Predators.loseRange else def.aggroRange) then
			continue
		end
		local length = character:GetAttribute("Length")
		local fishLength = if typeof(length) == "number" then length else 2
		if fishLength < def.length * def.ignoreBelow and not provoked then
			continue
		end
		local score = fishLength + (if provoked then 50 else 0) - distance * 0.05
		if score > bestScore then
			best, bestScore = player, score
		end
	end
	return best
end

local function targetRoot(predator: Predator): (BasePart?, number)
	local target = predator.target
	if target == nil then
		return nil, 0
	end
	local character, root = FishService.character(target)
	if character == nil or root == nil then
		return nil, 0
	end
	local length = character:GetAttribute("Length")
	return root, if typeof(length) == "number" then length else 2
end

-- Moves a predator toward a desired velocity: it accelerates, turns no faster than
-- `turnRate` (its own by default), and stays in the water column.
local function steer(predator: Predator, desired: Vector3, dt: number, turnRate: number?)
	local def = predator.def
	predator.velocity = predator.velocity:Lerp(desired, 1 - math.exp(-dt * 2.2))
	if predator.velocity.Magnitude > 0.5 then
		predator.heading = rotateToward(predator.heading, predator.velocity, (turnRate or def.turnRate) * dt)
	end
	local position = predator.position + predator.velocity * dt
	local floor = Seafloor.y(position.X, position.Z)
	local y = math.clamp(position.Y, floor + math.max(def.depth[1] * 0.6, 5), World.surfaceY - 12)
	predator.position = Vector3.new(position.X, y, position.Z)
end

local function simulate(predator: Predator, dt: number, now: number)
	local def = predator.def
	if predator.mode == "dead" then
		if now >= predator.respawnAt then
			spawn(predator)
		end
		return
	end
	-- Pick or drop a target
	if predator.mode ~= "windup" and predator.mode ~= "recover" then
		local target = predator.target
		local root, _ = targetRoot(predator)
		local session = if target then HuntService.sessions()[target] else nil
		if
			root == nil
			or session == nil
			or not session.alive
			or session.inHub
			or (root.Position - predator.position).Magnitude > def.aggroRange * Predators.loseRange
		then
			predator.target = pickTarget(predator, now)
		end
		predator.mode = if predator.target then "hunt" else "roam"
	end

	local desired: Vector3
	if predator.mode == "roam" then
		if (predator.waypoint - predator.position).Magnitude < 8 or now > predator.waypointUntil then
			predator.waypoint = randomWaypoint(def)
			predator.waypointUntil = now + 12
		end
		desired = (predator.waypoint - predator.position).Unit * def.speed * Predators.roamSpeed
	else
		local root, fishLength = targetRoot(predator)
		if root == nil then
			predator.mode = "roam"
			desired = predator.velocity
		else
			-- Lead the target a little
			local aim = root.Position + root.AssemblyLinearVelocity * 0.3
			local toTarget = aim - mouthOf(predator)
			if predator.mode == "hunt" then
				desired = (if toTarget.Magnitude > 1e-3 then toTarget.Unit else predator.heading) * def.speed
				if (root.Position - mouthOf(predator)).Magnitude <= def.biteReach + fishLength * 0.5 then
					predator.mode = "windup"
					predator.modeUntil = now + def.telegraph
					Net.predatorEvent("windup", predator.index, {
						target = (predator.target :: Player).UserId,
						seconds = def.telegraph,
					})
				end
			elseif predator.mode == "windup" then
				-- Jaw open: slow, still turning toward the fish
				desired = (if toTarget.Magnitude > 1e-3 then toTarget.Unit else predator.heading)
					* def.speed
					* 0.35
				if now >= predator.modeUntil then
					local reach = def.biteReach * 1.6 + fishLength * 0.5 + Size.topSpeed(fishLength) * 0.15
					local hit = (root.Position - mouthOf(predator)).Magnitude <= reach
					if hit then
						HuntService.damage(predator.target :: Player, def.biteFraction, def.name)
					end
					local mouth = mouthOf(predator)
					Net.predatorEvent(
						"bite",
						predator.index,
						{ hit = hit, x = mouth.X, y = mouth.Y, z = mouth.Z }
					)
					predator.mode = "recover"
					predator.modeUntil = now + (if hit then def.biteCooldown else def.biteCooldown * 0.6)
				end
			else -- recover: coast past, then come round
				desired = predator.heading * def.speed * 0.5
				if now >= predator.modeUntil then
					predator.mode = "hunt"
				end
			end
		end
	end
	steer(predator, desired, dt)
end

local function stream(now: number)
	local list: { { any } } = {}
	for _, predator in predators do
		local entry: { any } = {
			predator.index,
			math.floor(predator.position.X * 10) / 10,
			math.floor(predator.position.Y * 10) / 10,
			math.floor(predator.position.Z * 10) / 10,
			math.floor(predator.heading.X * 100) / 100,
			math.floor(predator.heading.Y * 100) / 100,
			math.floor(predator.heading.Z * 100) / 100,
			predator.mode,
			math.floor(predator.health / predator.maxHealth * 100) / 100,
			if predator.target then (predator.target :: Player).UserId else 0,
			predator.def.id,
			math.floor(predator.meter * 100) / 100,
		}
		table.insert(list, entry)
	end
	-- An unreliable packet over its size limit is dropped whole (playtest 2026-10-08:
	-- with the bigger map's predators and a boss up, every update was dropped), so the
	-- list goes out a few creatures at a time; the client takes each entry on its own
	for first = 1, #list, STREAM_BATCH do
		local last = math.min(first + STREAM_BATCH - 1, #list)
		Net.predatorState({ at = now, list = table.move(list, first, last, 1, {}) })
	end
end

local function payOut(predator: Predator, killer: Player?)
	local def = predator.def
	local total = 0
	for _, record in predator.hitBy do
		total += record.damage
	end
	if total <= 0 then
		return
	end
	for player, record in predator.hitBy do
		if player.Parent == nil then
			continue
		end
		local share = math.max(record.damage / total, 0.1)
		if player == killer then
			share += 0.1
		end
		local data = DataService.get(player)
		if data == nil then
			continue
		end
		HuntService.feed(player, def.loot.haulKg * share)
		HuntService.giveDna(player, predator.position, math.max(1, math.floor(def.loot.dna * share + 0.5)))
		EconomyService.addCoral(player, math.floor(def.loot.coral * share + 0.5))
		Events.ate:fire(player, 1)
		Net.notify(
			player,
			if player == killer
				then `You killed the {def.name}! +{string.format("%.1f", def.loot.haulKg * share)} kg Haul`
				else `The {def.name} is dead · your share: +{string.format(
					"%.1f",
					def.loot.haulKg * share
				)} kg Haul`,
			"good"
		)
	end
end

local function onBite(player: Player, index: any)
	if typeof(index) ~= "number" or index % 1 ~= 0 then
		return
	end
	local predator = predators[index]
	if predator == nil or predator.mode == "dead" then
		return
	end
	local now = Timing.clock()
	if now - (lastBite[player] or 0) < swim.biteCooldown * 0.8 then
		return
	end
	local mouth, length, slack = HuntService.mouth(player)
	local data = DataService.get(player)
	if mouth == nil or data == nil then
		return
	end
	-- Distance to the body, a segment from tail to nose
	local def = predator.def
	local half = predator.heading * def.length * 0.5
	local a, b = predator.position - half, predator.position + half
	local ab = b - a
	local t = math.clamp((mouth - a):Dot(ab) / math.max(ab:Dot(ab), 1e-4), 0, 1)
	local nearest = a + ab * t
	if (nearest - mouth).Magnitude > Size.reach(length) + def.length * 0.18 + slack then
		return
	end
	lastBite[player] = now
	local school = 0
	for other, record in predator.hitBy do
		if other ~= player and now - record.at < Predators.schoolWindow then
			school += 1
		end
	end
	local ratio = math.clamp(
		(length / def.length) ^ Predators.biteRatioPower,
		Predators.biteRatioMin,
		Predators.biteRatioMax
	)
	local jaw = Perks.bite(data.upgrades)
	local species = Progress.species(data).stats.bite
	local damage = hunt.biteDamage * ratio * (1 + Predators.schoolBonus * school) * jaw * species
	local hook = predator.onHit
	if hook then
		damage = hook(predator, player, damage, nearest)
	end
	predator.health -= damage
	local record: { damage: number, at: number } = predator.hitBy[player] or { damage = 0, at = now }
	record.damage += damage
	record.at = now
	predator.hitBy[player] = record
	Net.predatorEvent("hurt", predator.index, {
		by = player.UserId,
		damage = damage,
		health = math.max(predator.health / predator.maxHealth, 0),
		x = nearest.X,
		y = nearest.Y,
		z = nearest.Z,
	})
	if predator.health <= 0 then
		predator.mode = "dead"
		predator.respawnAt = now + def.respawn
		predator.target = nil
		Net.predatorEvent("died", predator.index, { by = player.UserId, gone = predator.custom == true })
		if not predator.custom then
			payOut(predator, player)
		end
		PredatorService.died:fire(predator, player)
		if predator.custom then
			predators[predator.index] = nil
		end
	end
end

local function make(def: Def, custom: boolean?): Predator
	local predator: Predator = {
		index = nextIndex,
		def = def,
		position = Vector3.zero,
		velocity = Vector3.zero,
		heading = Vector3.new(1, 0, 0),
		health = def.health,
		maxHealth = def.health,
		mode = "roam",
		modeUntil = 0,
		target = nil,
		waypoint = Vector3.zero,
		waypointUntil = 0,
		respawnAt = 0,
		hitBy = {},
		custom = custom,
		onHit = nil,
		meter = 0,
	}
	nextIndex += 1
	predators[predator.index] = predator
	return predator
end

function PredatorService.list(): { [number]: Predator }
	return predators
end

function PredatorService.get(index: number): Predator?
	return predators[index]
end

-- Adds a creature the caller drives (a boss): it's streamed and bitable, but not
-- simulated here. `at` is where it appears.
function PredatorService.add(def: Def, at: Vector3?): Predator
	local predator = make(def, true)
	spawn(predator, at)
	return predator
end

-- Takes a custom creature out of the world (a boss escaping): clients fade it.
function PredatorService.remove(predator: Predator, reason: string)
	if predators[predator.index] ~= predator then
		return
	end
	predator.mode = "dead"
	predator.target = nil
	Net.predatorEvent("died", predator.index, { by = 0, gone = true, reason = reason })
	PredatorService.died:fire(predator, nil)
	predators[predator.index] = nil
end

-- Helpers for a boss controller
PredatorService.pickTarget = pickTarget
PredatorService.targetRoot = targetRoot
PredatorService.steer = steer
PredatorService.mouthOf = mouthOf
PredatorService.rotateToward = rotateToward

function PredatorService.start()
	for _, def in Predators.list do
		for _ = 1, def.count do
			spawn(make(def, false))
		end
	end
	Net.onRequest("BitePredator", onBite)
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Predators.tickSeconds then
			return
		end
		local step = accumulator
		accumulator = 0
		local now = Timing.clock()
		for _, predator in predators do
			if not predator.custom then
				Guard.run("PredatorService.simulate", function()
					simulate(predator, step, now)
				end)
			end
		end
		stream(now)
	end)
	DataService.releasing:connect(function(player)
		lastBite[player] = nil
		for _, predator in predators do
			predator.hitBy[player] = nil
			if predator.target == player then
				predator.target = nil
			end
		end
	end)
end

return PredatorService
