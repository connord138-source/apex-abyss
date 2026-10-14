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
local Ground = require(ReplicatedStorage.Shared.Ground)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Size = require(ReplicatedStorage.Shared.Size)
local Tides = require(ReplicatedStorage.Shared.Tides)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
local ChumService = require(script.Parent.ChumService)
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
	-- Which way it peels off after a strike (+1 right, -1 left), for a looping pass
	peel: number,
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

-- A Blood Tide's hunters: faster and keener (Config/Tides `hunters`; never bosses)
local function hunters(predator: Predator): (number, number)
	if predator.custom then
		return 1, 1
	end
	local tide = Tides.at(Timing.unix())
	local boost = tide.hunters
	return if boost then boost.speed else 1, if boost then boost.aggro else 1
end

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
			-- Over the real ground: a waypoint inside a reef head was swum straight into
			local ground = math.max(Seafloor.y(x, z), Ground.y(x, z))
			return Vector3.new(x, ground + rng:NextNumber(def.depth[1], def.depth[2]), z)
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
	predator.peel = if rng:NextNumber() < 0.5 then -1 else 1
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

-- Whether a point is inside the hub's keep-out (Predators.hubKeepOut).
local function nearHub(position: Vector3, margin: number): boolean
	local hub = World.hub.center
	return Vector3.new(position.X - hub.X, 0, position.Z - hub.Z).Magnitude < Predators.hubKeepOut + margin
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
		if record.safeUntil > now or nearHub(root.Position, 0) then
			continue
		end
		local distance = (root.Position - predator.position).Magnitude
		local hit = predator.hitBy[player]
		local provoked = hit ~= nil and now - hit.at < 8
		local _, keen = hunters(predator)
		local range = def.aggroRange * keen
		if distance > (if provoked then range * Predators.loseRange else range) then
			continue
		end
		local length = character:GetAttribute("Length")
		local fishLength = if typeof(length) == "number" then length else 2
		if Size.raw(fishLength) < def.length * def.ignoreBelow and not provoked then
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

-- How far below the surface a creature's middle must stay, as a share of its length
-- (its back plus a dorsal fin)
local CEILING_SHARE = 0.3
-- A body's half-height as a share of its length (its belly under its middle)
local BODY_HALF = 0.12
-- Water kept between the belly and the ground, at the least (studs)
local BELLY_GAP = 1.5
-- How far ahead (seconds of travel) the ground is read, so a creature climbs over a
-- reef head before it reaches it instead of popping up on top of it
local LOOK_AHEAD = 1.4

-- The highest ground under a creature's body (tail to nose) and along the stretch
-- of water it's about to cross: the real ground (Shared/Ground: the Terrain and the
-- solid dressing), not the nominal floor, which reef heads, ridges, wrecks and
-- chimneys rise far above (owner, 2026-10-13: "the predator fish will phase through
-- the sand in the ground")
local function groundAround(predator: Predator, position: Vector3, velocity: Vector3): (number, number)
	local def = predator.def
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local facing = Vector3.new(predator.heading.X, 0, predator.heading.Z)
	local direction = if flat.Magnitude > 1
		then flat.Unit
		elseif facing.Magnitude > 1e-3 then facing.Unit
		else Vector3.xAxis
	local half = def.length * 0.5
	local under = -math.huge
	for _, along in { -half, 0, half } do
		local at = position + direction * along
		under = math.max(under, Ground.y(at.X, at.Z))
	end
	local reach = half + flat.Magnitude * LOOK_AHEAD
	local ahead = under
	for _, share in { 0.5, 1 } do
		local at = position + direction * (half + (reach - half) * share)
		ahead = math.max(ahead, Ground.y(at.X, at.Z))
	end
	return under, ahead
end

-- The height above the ground a creature likes to keep: its roaming band's floor
-- while it roams, closer down while it hunts (prey sits on the sand)
local function preferredGap(predator: Predator): number
	local def = predator.def
	local hard = def.length * BODY_HALF + BELLY_GAP
	if
		not predator.custom
		and (predator.mode == "hunt" or predator.mode == "windup" or predator.mode == "recover")
	then
		return hard + 2
	end
	return math.max(def.depth[1] * 0.6, 5) + def.length * BODY_HALF
end

-- Moves a predator toward a desired velocity and keeps it in the water column.
-- A plain predator swims like a fish (owner, 2026-10-13: "Their tracking should also
-- be more fluid and realistic"): it turns its body toward where it wants to go,
-- easing into the turn and turning slower at speed, and swims along its heading,
-- speeding up briskly and slowing gently, so it sweeps round in arcs instead of
-- sliding sideways at a target. A boss (`custom`) keeps the direct velocity model its
-- charges, jets and breaches were tuned on. Both read the real ground ahead and
-- climb over it, and never sink into it.
local function steer(predator: Predator, desired: Vector3, dt: number, turnRate: number?)
	local def = predator.def
	-- Climb over the ground ahead before reaching it
	local _, ahead = groundAround(predator, predator.position, predator.velocity)
	local want = ahead + preferredGap(predator)
	if predator.position.Y < want then
		local climb = math.min((want - predator.position.Y) * 1.6, def.speed * 0.9)
		desired = Vector3.new(desired.X, math.max(desired.Y, climb), desired.Z)
	end
	if predator.custom then
		predator.velocity = predator.velocity:Lerp(desired, 1 - math.exp(-dt * 2.2))
		if predator.velocity.Magnitude > 0.5 then
			predator.heading =
				rotateToward(predator.heading, predator.velocity, (turnRate or def.turnRate) * dt)
		end
	else
		local wantSpeed = desired.Magnitude
		local wantDirection = if wantSpeed > 1e-3 then desired / wantSpeed else predator.heading
		local speedNow = predator.velocity.Magnitude
		-- Turns slower the faster it goes, and eases in as it lines up (no snap)
		local rate = (turnRate or def.turnRate)
			* (1.25 - 0.45 * math.clamp(speedNow / math.max(def.speed, 1), 0, 1))
		local angle = math.acos(math.clamp(predator.heading:Dot(wantDirection), -1, 1))
		local turn = math.min(rate * dt, angle * (1 - math.exp(-dt * 5)))
		predator.heading = rotateToward(predator.heading, wantDirection, turn)
		-- Swims along its heading: slows in a hard turn, speeds up briskly, eases off
		local goal = wantSpeed * (1 - 0.35 * math.clamp(angle / math.pi, 0, 1))
		local change = if goal > speedNow then def.speed * 1.6 else def.speed * 0.9
		local speed = speedNow + math.clamp(goal - speedNow, -change * dt, change * dt)
		predator.velocity = predator.velocity:Lerp(predator.heading * speed, 1 - math.exp(-dt * 6))
	end
	local position = predator.position + predator.velocity * dt
	-- Never out past the map's wall (the squid chased a fish 4,700 studs out,
	-- playtest 2026-10-10)
	local hub = World.hub.center
	local out = Vector3.new(position.X - hub.X, 0, position.Z - hub.Z)
	local limit = World.boundsRadius - def.length * 0.5
	if out.Magnitude > limit then
		local outward = out.Unit
		position = Vector3.new(hub.X + outward.X * limit, position.Y, hub.Z + outward.Z * limit)
		local along = predator.velocity:Dot(outward)
		if along > 0 then
			predator.velocity -= outward * along
		end
	end
	-- ...and never into the hub's keep-out: the cave, its tunnels and the sand round
	-- them (Predators.hubKeepOut)
	local away = Vector3.new(position.X - hub.X, 0, position.Z - hub.Z)
	local keep = Predators.hubKeepOut + def.length * 0.5
	if away.Magnitude < keep then
		local outward = if away.Magnitude > 1e-3 then away.Unit else Vector3.xAxis
		position = Vector3.new(hub.X + outward.X * keep, position.Y, hub.Z + outward.Z * keep)
		local into = predator.velocity:Dot(outward)
		if into < 0 then
			predator.velocity -= outward * into
		end
	end
	-- Never into the ground: the belly stays over the highest ground under the body.
	-- A boss also keeps its old height off the nominal floor, which its fight was
	-- tuned on (the Megalodon stays up in the blue; a fish on the sand is out of reach)
	local under = groundAround(predator, position, predator.velocity)
	local floor = under + def.length * BODY_HALF + BELLY_GAP
	if predator.custom then
		floor = math.max(floor, Seafloor.y(position.X, position.Z) + math.max(def.depth[1] * 0.6, 5))
	end
	-- The surface is a ceiling for the whole body, not just its middle: a big
	-- creature's back and fin sit well above its axis (playtest 2026-10-10: the
	-- Megalodon chased a fish at the surface, its middle stopped 12 studs under, and
	-- its back and fin broke through the surface sheet)
	local ceiling = World.surfaceY - math.max(12, def.length * CEILING_SHARE)
	local y = math.clamp(position.Y, math.min(floor, ceiling), ceiling)
	if y >= ceiling and predator.velocity.Y > 0 then
		predator.velocity = Vector3.new(predator.velocity.X, 0, predator.velocity.Z)
	end
	if y <= floor + 0.05 and predator.velocity.Y < 0 then
		predator.velocity = Vector3.new(predator.velocity.X, 0, predator.velocity.Z)
	end
	-- ...and its nose doesn't dig in: near the ground it can only point down so far
	local reachDown = def.length * 0.45
	local noseAt = position + predator.heading * reachDown
	local noseGround = Ground.y(noseAt.X, noseAt.Z)
	local roomDown = (y - noseGround - def.length * BODY_HALF * 0.5 - BELLY_GAP) / math.max(reachDown, 1)
	if predator.heading.Y < 0 and roomDown < 1 and -predator.heading.Y > math.max(roomDown, 0) then
		local flat = Vector3.new(predator.heading.X, 0, predator.heading.Z)
		local tilt = -math.max(roomDown, 0)
		local level = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
		predator.heading = (level * math.sqrt(math.max(1 - tilt * tilt, 0)) + Vector3.yAxis * tilt).Unit
	end
	-- ...and its nose and tail stay under too: near the surface it can only tilt so far
	local reach = def.length * 0.45
	local room = (World.surfaceY - 4 - def.length * 0.09 - y) / math.max(reach, 1)
	if room < 1 and math.abs(predator.heading.Y) > room then
		local flat = Vector3.new(predator.heading.X, 0, predator.heading.Z)
		local tilt = math.clamp(predator.heading.Y, -math.max(room, 0), math.max(room, 0))
		local level = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
		predator.heading = (level * math.sqrt(math.max(1 - tilt * tilt, 0)) + Vector3.yAxis * tilt).Unit
	end
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
			or nearHub(root.Position, 0)
			or (root.Position - predator.position).Magnitude > def.aggroRange * Predators.loseRange
		then
			predator.target = pickTarget(predator, now)
		end
		predator.mode = if predator.target then "hunt" else "roam"
	end

	local desired: Vector3
	local fast = hunters(predator)
	local speed = def.speed * fast
	if predator.mode == "roam" then
		if (predator.waypoint - predator.position).Magnitude < 8 or now > predator.waypointUntil then
			-- Chum in the water draws it in (Config/Chum `lure`); else a new spot to roam
			local chum = ChumService.nearest(predator.position, Config.Chum.lure)
			if chum and not nearHub(chum, def.length) then
				local around = rng:NextUnitVector() * def.length * 0.6
				predator.waypoint = chum + Vector3.new(around.X, math.abs(around.Y) + 3, around.Z)
				predator.waypointUntil = now + 6
			else
				predator.waypoint = randomWaypoint(def)
				predator.waypointUntil = now + 12
			end
		end
		-- A lazy weave and a slow swell in pace, so a cruising fish doesn't fly a ruler
		local phase = now * 0.35 + predator.index * 1.7
		local toWaypoint = (predator.waypoint - predator.position).Unit
		local weave = CFrame.fromAxisAngle(Vector3.yAxis, math.sin(phase) * 0.3)
		desired = (weave:VectorToWorldSpace(toWaypoint) + Vector3.yAxis * math.sin(phase * 0.6) * 0.08).Unit
			* speed
			* Predators.roamSpeed
			* (0.85 + 0.15 * math.sin(phase * 0.5))
	else
		local root, fishLength = targetRoot(predator)
		if root == nil then
			predator.mode = "roam"
			desired = predator.velocity
		else
			-- Lead the target by the time it takes to close the gap, and keep the aim off
			-- the ground (a fish on the sand is struck from just above it)
			local gap = (root.Position - mouthOf(predator)).Magnitude
			local lead = math.clamp(gap / math.max(speed, 1), 0, 1.2)
			local aim = root.Position + root.AssemblyLinearVelocity * lead
			local aimFloor = Ground.y(aim.X, aim.Z) + def.length * BODY_HALF + BELLY_GAP
			aim = Vector3.new(aim.X, math.max(aim.Y, aimFloor), aim.Z)
			local toTarget = aim - mouthOf(predator)
			if predator.mode == "hunt" then
				-- Stalks in at a cruise, then sprints the last stretch
				local burst = 0.75 + 0.45 * (1 - math.clamp((gap - 10) / 35, 0, 1))
				desired = (if toTarget.Magnitude > 1e-3 then toTarget.Unit else predator.heading)
					* speed
					* burst
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
					-- The strike carries it on through, and it peels off to one side
					predator.velocity += predator.heading * def.speed * 0.5
					predator.peel = if rng:NextNumber() < 0.5 then -1 else 1
				end
			else -- recover: peel off to one side and loop round for another pass
				local away = CFrame.fromAxisAngle(Vector3.yAxis, -predator.peel * 0.7)
				desired = (away:VectorToWorldSpace(predator.heading) + Vector3.yAxis * 0.15).Unit
					* def.speed
					* 0.8
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
		local gained = HuntService.feed(player, def.loot.haulKg * share)
		HuntService.giveDna(player, predator.position, math.max(1, math.floor(def.loot.dna * share + 0.5)))
		EconomyService.earnCoral(player, def.loot.coral * share)
		Events.ate:fire(player, 1)
		Net.notify(
			player,
			if player == killer
				then `You killed the {def.name}! +{string.format("%.1f", gained)} kg Haul`
				else `The {def.name} is dead · your share: +{string.format("%.1f", gained)} kg Haul`,
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
	-- The biter's client draws the creature where it was a moment ago (the stream's
	-- interpolation delay plus latency), so a fast boss gets that much room too
	-- (retest 2026-10-09: bites on a swimming Megalodon's flank missed)
	local drift = predator.velocity.Magnitude * (Predators.interpolationDelay + hunt.latencySeconds)
	if (nearest - mouth).Magnitude > Size.reach(length) + def.length * 0.18 + slack + drift then
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
		(Size.raw(length) / def.length) ^ Predators.biteRatioPower,
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
	Events.bitPredator:fire(player, def.id, predator.custom == true)
	if predator.custom then
		Events.bossDamage:fire(player, damage)
	end
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
		peel = 1,
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
