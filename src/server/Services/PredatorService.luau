--!strict
-- AI predators (Config/Predators): simulated here ten times a second and streamed to
-- every client (positions, headings, modes), which interpolate them. Each one roams
-- its band, hunts the biggest worthwhile fish in range, shows its jaw for a moment
-- (the tell), then bites for a share of the victim's max health. Players bite back
-- (BitePredator, checked for reach and cooldown); a kill pays everyone who helped by
-- damage share. The world bosses extend this (BossService) with phases and attacks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
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

type Def = typeof(Predators.list[1])

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
	-- Set by a boss controller to override the plain behaviour
	custom: boolean?,
}

local PredatorService = {
	-- (predator, killer) — a predator died
	died = require(ReplicatedStorage.Shared.Signal).new(),
}

local predators: { Predator } = {}
local rng = Random.new(World.seed + 41)
local lastBite: { [Player]: number } = {}
local accumulator = 0

local function inTrench(x: number, z: number, margin: number): boolean
	local trench = World.trench
	return math.abs(x - trench.center.X) < trench.size.X / 2 + margin
		and math.abs(z - trench.center.Z) < trench.size.Z / 2 + margin
end

local function randomWaypoint(def: Def): Vector3
	for _ = 1, 20 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local distance = rng:NextNumber(def.band[1], def.band[2])
		local x, z = math.cos(angle) * distance, math.sin(angle) * distance
		if not inTrench(x, z, 30) then
			return Vector3.new(x, rng:NextNumber(def.depth[1], def.depth[2]), z)
		end
	end
	return Vector3.new(def.band[1], def.depth[1] + 10, 0)
end

local function spawn(predator: Predator)
	predator.position = randomWaypoint(predator.def)
	predator.velocity = Vector3.zero
	predator.heading = Vector3.new(1, 0, 0)
	predator.health = predator.maxHealth
	predator.mode = "roam"
	predator.modeUntil = 0
	predator.target = nil
	predator.waypoint = randomWaypoint(predator.def)
	predator.waypointUntil = Timing.clock() + 12
	predator.hitBy = {}
	Net.predatorEvent(
		"spawned",
		predator.index,
		{ x = predator.position.X, y = predator.position.Y, z = predator.position.Z }
	)
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
	predator.velocity = predator.velocity:Lerp(desired, 1 - math.exp(-dt * 2.2))
	if predator.velocity.Magnitude > 0.5 then
		predator.heading = rotateToward(predator.heading, predator.velocity, def.turnRate * dt)
	end
	local position = predator.position + predator.velocity * dt
	-- Stay in the water column and out of the floor
	local y = math.clamp(position.Y, math.max(def.depth[1] * 0.6, World.seabedY + 5), World.surfaceY - 12)
	predator.position = Vector3.new(position.X, y, position.Z)
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
		}
		table.insert(list, entry)
	end
	Net.predatorState({ at = now, list = list })
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
		Net.predatorEvent("died", predator.index, { by = player.UserId })
		payOut(predator, player)
		PredatorService.died:fire(predator, player)
	end
end

function PredatorService.list(): { Predator }
	return predators
end

function PredatorService.start()
	local index = 0
	for _, def in Predators.list do
		for _ = 1, def.count do
			index += 1
			local predator: Predator = {
				index = index,
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
			}
			predators[index] = predator
			spawn(predator)
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
