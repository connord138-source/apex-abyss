-- The world bosses' fights (run_predators.sh, after predator_sim.luau): the real
-- BossService on the real PredatorService against fake services. Each case raises a
-- boss beside one player fish in its own water and runs the fight, many times from
-- different directions. The fish sits still, dodges sideways at every warning, backs
-- straight off at every warning (`retreat`), flees flat out, or hugs the surface.
-- Besides the bites and hits it times how long the boss takes to come round after a
-- miss (owner, 2026-10-19: "If he misses the player he just slowly turns around and
-- goes at them again"): after a miss it swam on past, until it points back at the
-- fish (`round`), and after any miss, until its next attack on it (`again`).
local rbx = require("./sim_rbx")
local Vector3 = rbx.Vector3
local sim = require("./sim_services")
local Config = require("./Config")
local Seafloor = require("./Seafloor")
local Size = require("./Size")
local PredatorService = require("./PredatorService")
local BossService = require("./BossService")
local before = require("./sim_mode").before

local swim = Config.Tuning.swim
local sizeTuning = Config.Tuning.size
local World = Config.World
local DT = 0.1
local LAG = 0.1
local REACT = 0.3
local DODGE = 1.4 -- seconds a dodging fish swims flat out sideways (a held input)
local TRIALS = 8
local SECONDS = 90

sim.groundY = function(x: number, z: number): number
	return Seafloor.y(x, z)
end
PredatorService.start()
BossService.start()
local heartbeat = rbx.heartbeat :: (number) -> ()
-- No plain predators in a boss fight
for _, predator in PredatorService.list() do
	predator.mode = "dead"
	predator.respawnAt = math.huge
end

local failures = 0
local function expect(ok: boolean, what: string)
	if not ok and not before then
		failures += 1
		print("FAIL: " .. what)
	end
end

local function median(list: { number }): number
	if #list == 0 then
		return 0
	end
	local sorted = table.clone(list)
	table.sort(sorted)
	return sorted[math.ceil(#sorted / 2)]
end

local function most(list: { number }): number
	local top = 0
	for _, value in list do
		top = math.max(top, value)
	end
	return top
end

type Fish = { level: number, length: number, top: number }
local function fishAt(level: number, speedMul: number?): Fish
	local length = Size.length(sizeTuning.levelGrowth ^ (level - 1))
	return { level = level, length = length, top = Size.topSpeed(length) * (speedMul or 1) }
end

type Behaviour = "still" | "dodge" | "retreat" | "flee" | "surface"
type Result = {
	attacks: number, -- tells aimed at the fish (bites, charges, lunges, grabs)
	bites: number,
	hits: number, -- hits of any attack on the fish (a grab's hold counts once)
	worst: number, -- the most one hit took (share of max health)
	damage: number, -- share of max health taken, all told
	byKind: { [string]: { tells: number, hits: number } }, -- bite, charge, lunge, grab, other
	rounds: { number },
	agains: { number },
	turns: { number }, -- radians/s of its body's fastest turns
	-- seconds from each time it swam on past the fish (from facing it to facing away)
	-- until it faced the fish again, hit or miss: how fast it comes round
	passes: { number },
	speeds: { number }, -- its speed every tick (studs/s)
}

local function run(id: string, fish: Fish, spot: Vector3, behaviour: Behaviour, startGap: number): Result
	local result: Result = {
		attacks = 0,
		bites = 0,
		hits = 0,
		worst = 0,
		damage = 0,
		byKind = {},
		rounds = {},
		agains = {},
		turns = {},
		speeds = {},
		passes = {},
	}
	for trial = 1, TRIALS do
		table.clear(sim.events)
		table.clear(sim.hits)
		table.clear(sim.shoves)
		sim.now = 5000 * trial
		local player = { Name = "Fish", UserId = 7, Parent = true, DisplayName = "Fish" }
		local character, root = sim.fish(fish.length, spot)
		character:SetAttribute("MaxHealth", 100)
		character:SetAttribute("Health", 100)
		sim.sessions = { [player] = { alive = true, inHub = false, safeUntil = 0 } }
		sim.characters = { [player] = { character = character, root = root } }
		local boss = BossService.active()
		if boss then
			-- (sent away between runs)
			BossService.dismiss()
		end
		BossService.summon(id)
		boss = BossService.active() :: any
		local predator = boss.predator
		local angle = (trial - 1) / TRIALS * 2 * math.pi
		local from = spot + Vector3.new(math.cos(angle), 0, math.sin(angle)) * startGap
		predator.position = Vector3.new(from.X, spot.Y + 10, from.Z)
		predator.velocity = Vector3.zero
		predator.heading = Vector3.new(math.cos(angle + 2), 0, math.sin(angle + 2))
		local position, velocity = spot, Vector3.zero
		local history = {}
		local alarmAt = math.huge
		local alarmAway: Vector3? = nil
		local seen = 0
		local missAt: number? = nil
		local passed = false -- (it swam on past the fish after that miss)
		local facedAt: number? = nil -- last faced the fish
		local awayAt: number? = nil -- swam on past it (faced away) since
		local againFrom: number? = nil
		local chargeAt: number? = nil -- a charge or lunge under way at this fish
		local hitsBefore = 0
		local lastHeading = predator.heading
		for _ = 1, math.floor(SECONDS / DT) do
			sim.now += DT
			local away = Vector3.new(position.X - predator.position.X, 0, position.Z - predator.position.Z)
			away = if away.Magnitude > 1e-3 then away.Unit else Vector3.xAxis
			local since = sim.now - alarmAt
			if since >= 0 and alarmAway == nil then
				alarmAway = away
			end
			local frame = alarmAway or away
			local side = Vector3.new(-frame.Z, 0, frame.X)
			for _ = 1, 4 do
				local sub = DT / 4
				local want = Vector3.zero
				if behaviour == "dodge" and since >= 0 and since < DODGE then
					want = side * fish.top
				elseif behaviour == "retreat" and since >= 0 and since < DODGE then
					want = frame * fish.top
				elseif behaviour == "flee" then
					want = away * fish.top
				elseif alarmAt == math.huge and chargeAt == nil and (position - spot).Magnitude > 40 then
					-- (pushed or dodged off its spot, it swims back to keep fighting there)
					want = (spot - position).Unit * fish.top * 0.5
				end
				local rate = if want.Magnitude > 0 then swim.accel else swim.drag
				velocity += (want - velocity) * (1 - math.exp(-rate * sub))
				position += velocity * sub
				if behaviour == "surface" then
					position = Vector3.new(position.X, World.surfaceY - 3, position.Z)
				end
				-- The map's wall holds the fish in too
				local out = Vector3.new(position.X, 0, position.Z)
				local limit = World.boundsRadius - 4
				if out.Magnitude > limit then
					position = Vector3.new(out.Unit.X * limit, position.Y, out.Unit.Z * limit)
					velocity -= out.Unit * math.max(velocity:Dot(out.Unit), 0)
				end
			end
			-- Shoves from the boss's sweeps and blasts move the fish too
			for _, shove in sim.shoves do
				velocity += shove.push
			end
			table.clear(sim.shoves)
			table.insert(history, { at = sim.now, position = position, velocity = velocity })
			while #history > 1 and history[2].at <= sim.now - LAG do
				table.remove(history, 1)
			end
			root.Position = history[1].position
			root.AssemblyLinearVelocity = history[1].velocity
			character:SetAttribute("Health", 100)
			heartbeat(DT)
			-- How it moves: its speed and how fast its body swings round
			table.insert(result.speeds, predator.velocity.Magnitude)
			local turned = math.acos(math.clamp(lastHeading:Dot(predator.heading), -1, 1)) / DT
			table.insert(result.turns, turned)
			lastHeading = predator.heading
			-- Every pass: from facing the fish to facing away, until it faces it again
			do
				local toFish = position - predator.position
				local facing = if toFish.Magnitude > 1e-3 then predator.heading:Dot(toFish.Unit) else 1
				if facing >= 0.8 then
					if awayAt then
						table.insert(result.passes, sim.now - awayAt)
						awayAt = nil
					end
					facedAt = sim.now
				elseif facing < 0.3 and facedAt and awayAt == nil and sim.now - facedAt < 3 then
					awayAt = sim.now
				end
			end
			-- Round again after a miss
			if missAt then
				local toFish = position - predator.position
				-- (only a miss it swam on past counts: one still facing the fish
				-- has nothing to come round from)
				local facing = if toFish.Magnitude > 1e-3 then predator.heading:Dot(toFish.Unit) else 1
				if not passed and facing < 0.3 then
					passed = true
				elseif not passed and sim.now - missAt > 1.5 then
					missAt = nil
				elseif passed and facing >= 0.8 then
					table.insert(result.rounds, sim.now - (missAt :: number))
					missAt = nil
				end
			end
			for i = seen + 1, #sim.events do
				local event = sim.events[i]
				local mine = event.payload.target == player.UserId
				local tell = (event.kind == "windup" or event.kind == "charge" or event.kind == "grab")
					and mine
				if tell then
					result.attacks += 1
					local kind = if event.kind == "windup"
						then (if (event.payload.seconds or 1) < 0.8 then "lunge" else "bite")
						else event.kind
					local entry = result.byKind[kind] or { tells = 0, hits = 0 }
					entry.tells += 1
					result.byKind[kind] = entry
					if againFrom then
						table.insert(result.agains, sim.now - againFrom)
						againFrom = nil
					end
					-- (a charge is dodged once it comes: CHARGING · DODGE SIDEWAYS)
					if event.kind ~= "charge" and (alarmAt == math.huge or sim.now - alarmAt > 2.5) then
						alarmAt, alarmAway = sim.now + REACT, nil
					end
					if
						event.kind == "charge"
						or (event.kind == "windup" and (event.payload.seconds or 1) < 0.8)
					then
						chargeAt = sim.now
						hitsBefore = #sim.hits
					end
				elseif event.kind == "rush" and chargeAt then
					alarmAt, alarmAway = sim.now + REACT, nil
				elseif event.kind == "grabbed" and mine then
					-- (a grab that caught the fish: its hold ticks small below)
					result.hits += 1
					local entry = result.byKind.grab or { tells = 0, hits = 0 }
					entry.hits += 1
					result.byKind.grab = entry
				elseif event.kind == "bite" then
					result.bites += 1
					if not event.payload.hit then
						missAt, againFrom, passed = sim.now, sim.now, false
					end
				elseif event.kind == "charged" and chargeAt then
					if #sim.hits == hitsBefore then
						missAt, againFrom, passed = sim.now, sim.now, false
					end
					chargeAt = nil
				end
			end
			seen = #sim.events
			if alarmAt ~= math.huge and sim.now - alarmAt > DODGE + 1.5 then
				alarmAt = math.huge
				alarmAway = nil
			end
		end
		-- Each hit by the attack its share says it was (a grab's hold ticks small, and
		-- each grab is counted once, by its "grabbed" event above)
		local shark = Config.Bosses.byId[id].shark
		for _, hit in sim.hits do
			if hit.player == player then
				result.damage += hit.fraction
				result.worst = math.max(result.worst, hit.fraction)
				if hit.fraction < 0.05 then
					continue
				end
				result.hits += 1
				local kind = "other"
				if shark then
					if math.abs(hit.fraction - shark.bite.fraction) < 1e-3 then
						kind = "bite"
					elseif math.abs(hit.fraction - shark.charge.fraction) < 1e-3 then
						kind = "charge"
					elseif math.abs(hit.fraction - shark.mark.lungeFraction) < 1e-3 then
						kind = "lunge"
					end
				end
				local entry = result.byKind[kind] or { tells = 0, hits = 0 }
				entry.hits += 1
				result.byKind[kind] = entry
			end
		end
	end
	return result
end

local function show(id: string, fish: Fish, behaviour: string, r: Result)
	local fast = 0
	for _, turn in r.turns do
		fast = math.max(fast, turn)
	end
	local slow, quick = math.huge, 0
	for _, speed in r.speeds do
		slow = math.min(slow, speed)
		quick = math.max(quick, speed)
	end
	local parts = {}
	for _, kind in { "bite", "charge", "lunge", "grab", "other" } do
		local entry = r.byKind[kind]
		if entry then
			table.insert(parts, `{kind} {entry.hits}/{entry.tells}`)
		end
	end
	print(
		string.format(
			"%-10s LV%-3d %4.1f/s %-8s hits/tells: %-40s %4.1f hits/min, %3.0f%% health/min (worst hit %2.0f%%)%s  · speed %.0f–%.0f, turns to %.1f rad/s",
			id,
			fish.level,
			fish.top,
			behaviour,
			table.concat(parts, ", "),
			r.hits / TRIALS / (SECONDS / 60),
			r.damage / TRIALS / (SECONDS / 60) * 100,
			r.worst * 100,
			if #r.rounds > 0
				then string.format(
					"  · after a miss: round %.1f s (most %.1f), again %.1f s (most %.1f)",
					median(r.rounds),
					most(r.rounds),
					median(r.agains),
					most(r.agains)
				)
				else "",
			slow,
			quick,
			fast
		)
			.. (
				if #r.passes > 0
					then string.format(
						"  · after a pass: round %.1f s (most %.1f, %d passes)",
						median(r.passes),
						most(r.passes),
						#r.passes
					)
					else ""
			)
	)
end

local function case(id: string, fish: Fish, spot: Vector3, behaviour: Behaviour, startGap: number): Result
	local r = run(id, fish, spot, behaviour, startGap)
	show(id, fish, behaviour, r)
	return r
end

print(`{TRIALS} runs × {SECONDS} s each per boss case; a fish reacts {REACT} s after a warning`)
local megalodon = Config.Bosses.byId.Megalodon
-- Its water: the Open Blue, north, between its patrol band's depths
local blue = Vector3.new(0, 0, -1200)
local floor = Seafloor.y(blue.X, blue.Z)
local depth = megalodon.patrol.depth
local ceiling = World.surfaceY - math.max(12, megalodon.predator.length * 0.3)
print(
	string.format(
		"-- Megalodon (%d studs): patrol band %.0f to %.0f, ceiling for its middle %.0f, surface %.0f",
		megalodon.predator.length,
		floor + depth[1],
		floor + depth[2],
		ceiling,
		World.surfaceY
	)
)
expect(floor + depth[2] <= ceiling, "Megalodon: its patrol band fits under the surface")
local water = Vector3.new(blue.X, floor + (depth[1] + depth[2]) / 2, blue.Z)
local n45 = fishAt(45)
local mStill = case("Megalodon", n45, water, "still", 220)
expect(mStill.hits > 0, "Megalodon: a still fish is hit")
expect(mStill.worst < 1, "Megalodon: nothing one-shots")
local mDodge = case("Megalodon", n45, water, "dodge", 220)
expect(
	#mDodge.rounds > 0 and median(mDodge.rounds) <= 4,
	"Megalodon: comes round within a few seconds of a miss"
)
-- (a charge carries it well past a fish that dodged, so the next attack takes longer)
expect(#mDodge.agains > 0 and median(mDodge.agains) <= 8, "Megalodon: attacks again soon after a miss")
expect(mDodge.hits < mStill.hits, "Megalodon: dodging its tells beats some of its attacks")
-- A bite is dodged by backing straight off its jaws at the warning (its head swings
-- after a fish that slips sideways), a charge by slipping sideways
local mRetreat = case("Megalodon", n45, water, "retreat", 220)
local function biteRate(r: Result): number
	local entry = r.byKind.bite
	return if entry and entry.tells > 0 then entry.hits / entry.tells else 0
end
expect(biteRate(mRetreat) <= 0.4, "Megalodon: backing off its jaws at the warning escapes most bites")
expect(biteRate(mDodge) <= 0.4, "Megalodon: slipping aside at the warning escapes most bites")
expect(biteRate(mStill) >= 0.9, "Megalodon: a fish that sits in front of its jaws is bitten")
expect(mStill.worst < 1 and mRetreat.hits < mStill.hits, "Megalodon: dodging beats its attacks")
local mFlee = case("Megalodon", fishAt(55, 1.25), water, "flee", 220)
expect(mFlee.attacks > 0, "Megalodon: goes after a fish that runs")
local surface = Vector3.new(blue.X, World.surfaceY - 3, blue.Z)
local mSurface = case("Megalodon", n45, surface, "surface", 220)
expect(mSurface.hits > 0, "Megalodon: reaches a fish hugging the surface")

-- Its leash (PC 2026-10-25: a Megalodon hunting a fish followed it to the Kelp
-- Shallows and circled at the hub's keep-out for 5 minutes): once it's hunting a
-- fish in the Open Blue, the fish swims flat out for the hub or is put down in the
-- shallows (an admin goTo). It gives up at the drop-off, never comes over the shelf,
-- and isn't hunting that fish at the end.
local function leash(how: "swim" | "teleport"): (number, number, boolean)
	local fish = fishAt(55, 1.25)
	local nearest, giveUp, hunting = math.huge, math.huge, false
	for trial = 1, TRIALS do
		sim.now = 900000 + 5000 * trial
		local player = { Name = "Fish", UserId = 7, Parent = true, DisplayName = "Fish" }
		local character, root = sim.fish(fish.length, water)
		character:SetAttribute("MaxHealth", 100)
		character:SetAttribute("Health", 100)
		sim.sessions = { [player] = { alive = true, inHub = false, safeUntil = 0 } }
		sim.characters = { [player] = { character = character, root = root } }
		if BossService.active() then
			BossService.dismiss()
		end
		BossService.summon("Megalodon")
		local predator = (BossService.active() :: any).predator
		local angle = (trial - 1) / TRIALS * 2 * math.pi
		predator.position = water + Vector3.new(math.cos(angle) * 150, 10, math.sin(angle) * 150)
		predator.velocity = Vector3.zero
		local position = water
		local hunted = false
		local leftAt: number? = nil
		for step = 1, math.floor(150 / DT) do
			sim.now += DT
			if step * DT > 15 and hunted then
				if how == "teleport" and leftAt == nil then
					-- The Otter Meadow, where the PC's fish was
					local a = math.rad(291)
					local x, z = math.cos(a) * 328, math.sin(a) * 328
					position = Vector3.new(x, Seafloor.y(x, z) + 30, z)
					leftAt = sim.now
				elseif how == "swim" then
					leftAt = leftAt or sim.now
					local flat = Vector3.new(position.X, 0, position.Z)
					if flat.Magnitude > 330 then
						position -= flat.Unit * fish.top * DT
						position = Vector3.new(
							position.X,
							math.max(position.Y, Seafloor.y(position.X, position.Z) + 30),
							position.Z
						)
					end
				end
			end
			root.Position = position
			root.AssemblyLinearVelocity = Vector3.zero
			character:SetAttribute("Health", 100)
			heartbeat(DT)
			hunted = hunted or predator.target == player
			local at = predator.position
			nearest = math.min(nearest, math.sqrt(at.X * at.X + at.Z * at.Z))
			if leftAt and predator.target ~= player and giveUp == math.huge then
				giveUp = sim.now - leftAt
			end
		end
		expect(hunted, `Megalodon: hunts the fish before it leaves ({how}, run {trial})`)
		hunting = hunting or predator.target == player
	end
	BossService.dismiss()
	return nearest, giveUp, hunting
end
for _, how in { "swim", "teleport" } :: { "swim" | "teleport" } do
	local nearest, giveUp, hunting = leash(how)
	print(
		string.format(
			"Megalodon leash (%s for the hub): nearest it came to the hub r %.0f (the shelf's edge is %d), gave up the fish within %.1f s",
			how,
			nearest,
			World.shelf.radius,
			giveUp
		)
	)
	expect(
		nearest > World.shelf.radius - 40,
		`Megalodon: never over the shelf when a fish leads it home ({how})`
	)
	expect(not hunting, `Megalodon: not still hunting a fish that left its water ({how})`)
end

local squid = Config.Bosses.byId.GiantSquid
local trench = Config.World.trench
local r = (trench.radii[1] + trench.radii[2]) / 2
local tx, tz = Seafloor.trenchPoint(r, 0)
local deep = Vector3.new(tx, Seafloor.y(tx, tz) + 40, tz)
print(string.format("-- Giant Squid (%d studs) in the Trench", squid.predator.length))
local sStill = case("GiantSquid", fishAt(85), deep, "still", 120)
expect(sStill.attacks > 0, "Giant Squid: attacks a still fish")
expect(sStill.worst < 1, "Giant Squid: nothing one-shots")

if failures > 0 then
	error(`{failures} boss check(s) failed`)
end
print("bosses: OK")
