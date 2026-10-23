-- The AI predators' hunting styles (run_predators.sh). Each case puts one predator
-- near one player fish and runs the real PredatorService for a minute, many times
-- from different directions. The fish sits still, cruises slowly, flees in a straight
-- line, jukes sideways or loops back when it sees the attack coming, Dashes during
-- the tell, hides behind rock, burrows, puffs up, or gets the predator stunned.
-- After every miss it also times the come-round (owner, 2026-10-19: "If he misses the
-- player he just slowly turns around and goes at them again"): after a miss it swam on
-- past (facing away), how long until the predator points back at the fish (`round`),
-- and after any miss, until its next attack (`again`).
local rbx = require("./sim_rbx")
local Vector3 = rbx.Vector3
local sim = require("./sim_services")
local Config = require("./Config")
local Seafloor = require("./Seafloor")
local Size = require("./Size")
local PredatorService = require("./PredatorService")
-- An older service (BEFORE=1): print the table, check nothing
local before = require("./sim_mode").before

local swim = Config.Tuning.swim
local sizeTuning = Config.Tuning.size
local DT = 0.1
local LAG = 0.1 -- the server sees a fish this far in the past
local REACT = 0.3 -- a person's reaction to a warning
-- (a case can react sooner or later: `reactNext` for the next case only)
local reactNext: number? = nil
local TRIALS = 12
local SECONDS = 60

sim.groundY = function(x: number, z: number): number
	return Seafloor.y(x, z)
end
PredatorService.start()
local heartbeat = rbx.heartbeat :: (number) -> ()

-- Playable species: their speed and turn multipliers (Config/Species)
local SPECIES = {
	Nibbler = { speed = 1, turn = 1 },
	Cuda = { speed = 1.25, turn = 1 },
	Puffer = { speed = 0.8, turn = 1 },
	Moray = { speed = 1.1, turn = 1.25 },
}

type Fish = { species: string, level: number, length: number, top: number, turn: number }
local function fishAt(species: string, level: number): Fish
	local mass = sizeTuning.levelGrowth ^ (level - 1)
	local length = Size.length(mass) -- (Size reads speeds and turns off the drawn length)
	local kind = SPECIES[species]
	return {
		species = species,
		level = level,
		length = length,
		top = Size.topSpeed(length) * kind.speed,
		turn = Size.turnRate(length) * swim.cruiseTurn * kind.turn,
	}
end

-- The first creature of a kind (and its pack, if it hunts in one); every other one
-- is put out of the way
local function only(id: string)
	local chosen = nil
	for _, predator in PredatorService.list() do
		if predator.def.id == id and chosen == nil then
			chosen = predator
		end
	end
	local crew = {}
	for _, member in (chosen and chosen.pack) or { chosen } do
		crew[member] = true
	end
	for _, predator in PredatorService.list() do
		if not crew[predator] then
			predator.mode = "dead"
			predator.respawnAt = math.huge
			predator.target = nil
		end
	end
	return chosen
end

local failures = 0
local function expect(ok: boolean, what: string)
	if not ok and not before then
		failures += 1
		print("FAIL: " .. what)
	end
end

type Behaviour =
	"dodge"
	| "still"
	| "cruise"
	| "flee"
	| "juke"
	| "loop"
	| "dash"
	| "hide"
	| "burrow"
	| "burrowMid"
	| "stun"
	| "puff"
	| "bleed"
	| "harass"
	| "stillDash"
type Result = {
	bites: number,
	hits: number,
	tells: number,
	caught: number, -- runs with at least one hit
	first: number, -- median seconds to the first hit
	lost: number,
	stunned: number,
	fraction: number, -- the share of max health the last hit took
	recoil: number, -- the predator's health lost to recoil (share of its max)
	biters: number, -- how many of its pack bit (or snapped at) the fish
	pulled: number, -- shoves toward it (a gulp or a lure)
	lured: number, -- "luring" warnings
	stray: number, -- the furthest it got from its hole (a tethered hunter)
	rounds: { number }, -- seconds from each miss it swam past until it faces the fish again (within ~37°)
	agains: { number }, -- seconds from each miss until its next tell or burst at the fish
}

local function run(
	id: string,
	fish: Fish,
	spot: Vector3,
	behaviour: Behaviour,
	startGap: number,
	early: string?
): Result
	local result: Result = {
		bites = 0,
		hits = 0,
		tells = 0,
		caught = 0,
		first = 0,
		lost = 0,
		stunned = 0,
		fraction = 0,
		recoil = 0,
		biters = 0,
		pulled = 0,
		lured = 0,
		stray = 0,
		rounds = {},
		agains = {},
	}
	local firsts = {}
	local whoBit = {}
	local react = reactNext or REACT
	reactNext = nil
	for trial = 1, TRIALS do
		table.clear(sim.events)
		table.clear(sim.hits)
		table.clear(sim.shoves)
		sim.now = 1000 * trial
		sim.sees = function()
			return behaviour ~= "hide"
		end
		local predator = only(id)
		local angle = (trial - 1) / TRIALS * 2 * math.pi
		local from = spot + Vector3.new(math.cos(angle), 0, math.sin(angle)) * startGap
		-- (a pack starts together: the rest at their stations beside the leader)
		for i, member in predator.pack or { predator } do
			local side = Vector3.new(-math.sin(angle), 0, math.cos(angle)) * ((i - 1) * 6 - 6)
			member.position = Vector3.new(from.X, spot.Y + 4, from.Z)
				+ (if predator.pack then side else Vector3.zero)
			member.velocity = Vector3.zero
			member.heading = Vector3.new(math.cos(angle + 2), 0, math.sin(angle + 2)) -- not facing it
			member.mode = "roam"
			member.target = nil
			member.waypoint = member.position
			member.waypointUntil = 0
			member.hitBy = {}
			member.health = member.maxHealth
			member.burstUntil = 0
			member.stunUntil = 0
			member.fails = {}
			member.ignore = {}
			member.nipped = {}
			member.strayed = math.huge
			-- (a tethered hunter's hole is where it starts)
			if member.home then
				member.home = member.position
			end
		end
		local player = { Name = "Fish", UserId = 7, Parent = true }
		local character, root = sim.fish(fish.length, spot)
		character:SetAttribute("FishLevel", fish.level)
		character:SetAttribute("MaxHealth", 100)
		character:SetAttribute("Health", if behaviour == "bleed" then 40 else 100)
		character:SetAttribute("Burrowed", behaviour == "burrow")
		-- (AbilityService puts the clock it deflates at)
		character:SetAttribute("Puffed", if behaviour == "puff" then math.huge else nil)
		sim.sessions = { [player] = { alive = true, inHub = false, safeUntil = 0 } }
		sim.characters = { [player] = { character = character, root = root } }
		local position, velocity = spot, Vector3.zero
		local history = {}
		local alarmAt = math.huge -- when it reacts to a burst or a tell
		local alarmAway: Vector3? = nil -- which way was away from it then
		local fleeing = false
		local seen = 0
		local first = nil
		local healthBefore = predator.health
		local missAt: number? = nil -- the last miss, until it has come round
		local passed = false -- (it swam on past the fish after that miss)
		local againFrom: number? = nil -- the last miss, until its next attack
		local backOffUntil = 0 -- (harass: swimming off after a pass at it)
		for _ = 1, math.floor(SECONDS / DT) do
			sim.now += DT
			local t = sim.now - 1000 * trial
			-- The fish sees it coming: a hunting predator within 60 studs sets a fleeing
			-- fish off (after its reaction)
			local hunted = predator.target == player
			local gapNow = (predator.position - position).Magnitude
			local fleeKinds = behaviour == "flee"
				or behaviour == "juke"
				or behaviour == "loop"
				or behaviour == "dash"
			if fleeKinds and hunted and gapNow < 60 and not fleeing then
				fleeing = true
			end
			-- Turning early: as it closes to within 25 studs, before any tell
			if early == "close" and fleeing and gapNow < 25 and alarmAt == math.huge then
				alarmAt = sim.now + react
			end
			if fleeing and (gapNow > 150 or not hunted) and alarmAt == math.huge then
				fleeing = false
			end
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
				if behaviour == "harass" then
					-- The owner's back and forth (2026-10-20): straight at it to bite,
					-- off for a second, and back at it again
					local toIt = predator.position - position
					local unit = if toIt.Magnitude > 1e-3 then toIt.Unit else Vector3.xAxis
					if sim.now < backOffUntil then
						want = -unit * fish.top
					elseif toIt.Magnitude < predator.def.length * 0.5 + 3 then
						backOffUntil = sim.now + 1
						want = -unit * fish.top
					else
						want = unit * fish.top
					end
				elseif behaviour == "cruise" then
					local a = sim.now * 5 / 12
					want = Vector3.new(-math.sin(a), 0, math.cos(a)) * 5
				elseif
					(behaviour == "dash" or behaviour == "stillDash")
					and since >= 0
					and since < swim.dashSeconds
				then
					want = away * fish.top * swim.boostMultiplier
					velocity = want -- a dash is a burst
				elseif (behaviour == "juke" or behaviour == "dodge") and since >= 0 and since < 0.7 then
					-- Hard sideways
					want = side * fish.top
				elseif behaviour == "loop" and since >= 0 and since < math.pi / fish.turn + 1 then
					-- Doubling back: round at its own turn rate, then on back past it
					local turned = math.min(since * fish.turn, math.pi)
					want = (frame * math.cos(turned) + side * math.sin(turned)).Unit * fish.top
				elseif fleeing then
					want = away * fish.top
				end
				local rate = if want.Magnitude > 0 then swim.accel else swim.drag
				velocity += (want - velocity) * (1 - math.exp(-rate * sub))
				position += velocity * sub
				-- The map's wall holds the fish in too
				local out = Vector3.new(position.X, 0, position.Z)
				local limit = Config.World.boundsRadius - 4
				if out.Magnitude > limit then
					position = Vector3.new(out.Unit.X * limit, position.Y, out.Unit.Z * limit)
					velocity -= out.Unit * math.max(velocity:Dot(out.Unit), 0)
				end
			end
			table.insert(history, { at = sim.now, position = position, velocity = velocity })
			while #history > 1 and history[2].at <= sim.now - LAG do
				table.remove(history, 1)
			end
			root.Position = history[1].position
			root.AssemblyLinearVelocity = history[1].velocity
			local pushedBefore = #sim.shoves
			heartbeat(DT)
			-- A gulp or a lure pulls the fish (the server shoves it; its client adds it)
			for i = pushedBefore + 1, #sim.shoves do
				local shove = sim.shoves[i]
				if shove.player == player then
					velocity += shove.push
					result.pulled += 1
				end
			end
			if predator.home then
				result.stray = math.max(result.stray, (predator.position - predator.home).Magnitude)
			end
			-- Round again after a miss: pointed back at the fish
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
			local last = #sim.events
			for i = seen + 1, last do
				local event = sim.events[i]
				local mine = event.payload.target == player.UserId
				if againFrom and mine and (event.kind == "windup" or event.kind == "burst") then
					table.insert(result.agains, sim.now - againFrom)
					againFrom = nil
				end
				if (event.kind == "windup" or (early == "burst" and event.kind == "burst")) and mine then
					if event.kind == "windup" then
						result.tells += 1
					end
					if alarmAt == math.huge or sim.now - alarmAt > 2.5 then
						alarmAt = sim.now + react
					end
					if event.kind == "windup" and behaviour == "burrowMid" then
						character:SetAttribute("Burrowed", true)
					elseif event.kind == "windup" and behaviour == "stun" and PredatorService.stun then
						local count = PredatorService.stun(position, 30, 3)
						expect(count == 1, `stun: {count} stunned, wanted 1`)
					end
				elseif event.kind == "luring" and mine then
					result.lured += 1
				elseif event.kind == "bite" then
					result.bites += 1
					whoBit[event.index] = true
					if event.payload.hit then
						result.hits += 1
						first = first or t
					else
						missAt, againFrom, passed = sim.now, sim.now, false
					end
				elseif event.kind == "lost" then
					result.lost += 1
				elseif event.kind == "stunned" then
					result.stunned += 1
				end
			end
			seen = last
			if alarmAt ~= math.huge and sim.now - alarmAt > 3 then
				alarmAt = math.huge
				alarmAway = nil
			end
		end
		for _, hit in sim.hits do
			result.fraction = hit.fraction
		end
		result.recoil += (healthBefore - math.max(predator.health, 0)) / predator.maxHealth
		if first then
			result.caught += 1
		end
		table.insert(firsts, first or SECONDS)
	end
	table.sort(firsts)
	result.first = firsts[math.ceil(#firsts / 2)]
	for _ in whoBit do
		result.biters += 1
	end
	return result
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

local function show(id: string, fish: Fish, where: string, behaviour: string, r: Result, early: string?)
	print(
		string.format(
			"%-9s %-7s LV%-3d %4.1f/s %-6s %-11s caught %2d/%d  bites %3d hits %3d (%3.0f%% of tells)  %4.1f hits/min  first %4.1f s%s",
			id,
			fish.species,
			fish.level,
			fish.top,
			where,
			behaviour .. (if early then "@" .. early else ""),
			r.caught,
			TRIALS,
			r.bites,
			r.hits,
			if r.tells > 0 then r.hits / r.tells * 100 else 0,
			r.hits / TRIALS / (SECONDS / 60),
			r.first,
			if #r.rounds > 0
				then string.format(
					"  · after a miss: round %.1f s (most %.1f), again %.1f s (most %.1f)",
					median(r.rounds),
					most(r.rounds),
					median(r.agains),
					most(r.agains)
				)
				else ""
		)
	)
end

local function case(
	id: string,
	fish: Fish,
	where: string,
	spot: Vector3,
	behaviour: Behaviour,
	startGap: number,
	early: string?
): Result
	local r = run(id, fish, spot, behaviour, startGap, early)
	show(id, fish, where, behaviour, r, early)
	return r
end

local function rate(r: Result): number
	return if r.tells > 0 then r.hits / r.tells else 0
end

-- Spread (owner, 2026-10-22: "Predators should be more spread out"): every plain
-- creature roams its water for 3 minutes with no fish about; past the first 30 s,
-- every 5 s, how far each is from the nearest other (its packmates aside)
print("-- Spread: every creature roaming, no fish about")
do
	local nearest: { number } = {}
	local close = 0
	for step = 1, 1800 do
		sim.now += DT
		heartbeat(DT)
		if step > 300 and step % 50 == 0 then
			for _, a in PredatorService.list() do
				if a.mode == "dead" then
					continue
				end
				local best = math.huge
				for _, b in PredatorService.list() do
					if b ~= a and b.mode ~= "dead" and not (a.pack and b.pack == a.pack) then
						local flat = Vector3.new(a.position.X - b.position.X, 0, a.position.Z - b.position.Z)
						best = math.min(best, flat.Magnitude)
					end
				end
				table.insert(nearest, best)
				if best < 40 then
					close += 1
				end
			end
		end
	end
	table.sort(nearest)
	local share = close / #nearest
	print(
		string.format(
			"   nearest other: median %.0f studs, lowest tenth %.0f; within 40 studs %.1f%% of the time",
			nearest[math.ceil(#nearest / 2)],
			nearest[math.ceil(#nearest / 10)],
			share * 100
		)
	)
	expect(share <= 0.05, "spread: creatures are rarely within 40 studs of each other")
end

-- No mobbing (owner, 2026-10-22: "they shouldn't mob a player either"): every
-- Barracuda and Goliath Grouper in the wreck bay starts 40 studs round one still
-- LV 18 fish; at most Config/Predators `mob.hunters` may hunt it at once
print("-- Mob: the bay's hunters round one still fish")
do
	local cap = (Config.Predators :: any).mob and (Config.Predators :: any).mob.hunters or 2
	local bx, bz = -650, 0
	local spot = Vector3.new(bx, Seafloor.y(bx, bz) + 20, bz)
	local fish = fishAt("Nibbler", 18)
	local player = { Name = "Mobbed", UserId = 9, Parent = true }
	local character, root = sim.fish(fish.length, spot)
	character:SetAttribute("FishLevel", 18)
	character:SetAttribute("MaxHealth", 100)
	character:SetAttribute("Health", 100)
	sim.sessions = { [player] = { alive = true, inHub = false, safeUntil = 0 } }
	sim.characters = { [player] = { character = character, root = root } }
	local crowd = 0
	for _, predator in PredatorService.list() do
		if predator.def.id == "Barracuda" or predator.def.id == "GoliathGrouper" then
			crowd += 1
			local angle = crowd * 0.7
			predator.position = spot + Vector3.new(math.cos(angle), 0.05, math.sin(angle)) * 40
			predator.velocity = Vector3.zero
			predator.mode = "roam"
			predator.target = nil
			predator.waypoint = spot
			predator.waypointUntil = sim.now + 30
		end
	end
	local most, hunted = 0, 0
	for _ = 1, 400 do
		sim.now += DT
		heartbeat(DT)
		local units: { [any]: boolean } = {}
		local count = 0
		for _, predator in PredatorService.list() do
			if predator.target == player and predator.mode ~= "dead" then
				local unit: any = predator.pack or predator
				if not units[unit] then
					units[unit] = true
					count += 1
				end
			end
		end
		most = math.max(most, count)
		if count > 0 then
			hunted += 1
		end
	end
	print(`   {crowd} round it: at most {most} hunting it at once, hunted {hunted * DT} s of 40`)
	expect(most <= cap, `mob: at most {cap} hunt one fish at once (saw {most})`)
	expect(hunted * DT >= 20, "mob: the fish is still hunted")
	sim.sessions = {}
	sim.characters = {}
end

print(`{TRIALS} runs × {SECONDS} s each; a fish reacts {REACT} s after it sees a burst or a tell`)

-- Barracuda, the ambush sprinter, on the shelf (LV 1–40 water)
local shelf = Vector3.new(-650, 0, 0) -- (the wreck bay: it hunts only in and near its own water)
local function sand(fish: Fish): Vector3
	return Vector3.new(shelf.X, Seafloor.y(shelf.X, shelf.Z) + 0.2 * fish.length, shelf.Z)
end
local water = Vector3.new(shelf.X, 30, shelf.Z)
local n10, n25, n40 = fishAt("Nibbler", 10), fishAt("Nibbler", 25), fishAt("Nibbler", 40)
local c25, c40 = fishAt("Cuda", 25), fishAt("Cuda", 40)
local p25 = fishAt("Puffer", 25)
print("-- Barracuda: ambush sprinter")
local still = case("Barracuda", n25, "sand", sand(n25), "still", 40)
expect(still.hits > 0 and still.hits >= still.bites * 0.85, "Barracuda: a still fish is bitten")
local cruise = case("Barracuda", n25, "water", water, "cruise", 40)
expect(cruise.hits > 0 and cruise.hits >= cruise.bites * 0.85, "Barracuda: a slow fish is bitten")
local flee10 = case("Barracuda", n10, "water", water, "flee", 30)
expect(flee10.caught >= TRIALS * 0.75, "Barracuda: a LV 10 Nibbler can't outrun its burst from close")
case("Barracuda", n25, "water", water, "flee", 30)
local n30, n35 = fishAt("Nibbler", 30), fishAt("Nibbler", 35)
case("Barracuda", n30, "water", water, "flee", 30)
case("Barracuda", n35, "water", water, "flee", 30)
case("Barracuda", n40, "water", water, "flee", 30)
case("Barracuda", c25, "water", water, "flee", 30)
local cudaFlee = case("Barracuda", c40, "water", water, "flee", 30)
expect(cudaFlee.caught <= TRIALS * 0.25, "Barracuda: a LV 40 'Cuda outlasts its burst")
local juke = case("Barracuda", n25, "water", water, "juke", 30)
-- The owner's LV 16 fish darting in and out at it (2026-10-20)
local n16 = fishAt("Nibbler", 16)
local harass = case("Barracuda", n16, "water", water, "harass", 30)
expect(
	harass.caught >= TRIALS * 0.9 and rate(harass) >= 0.6,
	"Barracuda: a fish darting back and forth at it is bitten"
)
-- Sits still and jukes each burst or tell (owner, 2026-10-20: "a lot more aggressive
-- and more accurate"): past `commit` of its tell it lunges on its line, so a juke
-- escapes it only some of the time
local dodge = case("Barracuda", n25, "water", water, "dodge", 30, "burst")
expect(rate(dodge) >= 0.3 and rate(dodge) <= 0.9, "Barracuda: a juke at every strike only sometimes works")
expect(rate(juke) >= 0.3 and rate(juke) <= 0.75, "Barracuda: a sideways juke escapes about half its strikes")
-- Out of breath after a missed burst it still glides round to face the fish, and
-- bursts again once it has its wind
expect(
	#dodge.rounds > 0 and median(dodge.rounds) <= 3.5,
	"Barracuda: faces the fish again within a few seconds of a miss"
)
case("Barracuda", n25, "water", water, "loop", 30)
case("Barracuda", n25, "water", water, "juke", 30, "burst")
local loopBurst = case("Barracuda", n25, "water", water, "loop", 30, "burst")
expect(rate(loopBurst) <= 0.3, "Barracuda: doubling back as it bursts makes it overshoot")
local dash = case("Barracuda", n25, "water", water, "dash", 30)
expect(rate(dash) <= 0.3, "Barracuda: a Dash at the burst escapes most strikes")
local hide = case("Barracuda", n25, "sand", sand(n25), "hide", 40)
expect(hide.bites == 0, "Barracuda: no bite through rock")
local burrow = case("Barracuda", n25, "sand", sand(n25), "burrow", 40)
expect(burrow.tells == 0 and burrow.bites == 0, "Barracuda: a burrowed fish isn't prey")
local burrowMid = case("Barracuda", n25, "sand", sand(n25), "burrowMid", 40)
expect(burrowMid.lost > 0 and burrowMid.hits == 0, "Barracuda: burrowing mid-tell calls the bite off")
local stun = case("Barracuda", n25, "sand", sand(n25), "stun", 40)
expect(stun.stunned > 0 and stun.hits == 0 and stun.bites == 0, "Barracuda: a stun calls its tell off")
local puff = case("Barracuda", p25, "sand", sand(p25), "puff", 40)
expect(puff.hits > 0, "Barracuda: bites a puffed fish")
local barracudaLevel = PredatorService.theirBite(Config.Predators.byId.Barracuda, 25)
expect(
	math.abs(puff.fraction - Config.Predators.byId.Barracuda.biteFraction * barracudaLevel * 0.5) < 1e-6,
	"puffed: half damage"
)
-- (every bite but a killing one flinches it)
expect(puff.recoil > 0 and puff.stunned >= puff.hits - TRIALS, "puffed: recoil and a flinch on every bite")
print(
	string.format(
		"   puffed: a bite took %.0f%% (not %.0f%%), the Barracuda lost %.0f%% of its health over %d runs and flinched %d times",
		puff.fraction * 100,
		Config.Predators.byId.Barracuda.biteFraction * barracudaLevel * 100,
		puff.recoil / TRIALS * 100,
		TRIALS,
		puff.stunned
	)
)

-- Reef Shark, the relentless tracker, in the Open Blue (LV 35–55 water)
print("-- Reef Shark: relentless tracker")
local blue = Vector3.new(0, 0, -1200)
local deep = Seafloor.y(blue.X, blue.Z)
local blueWater = Vector3.new(blue.X, deep + 250, blue.Z)
local n45, n55 = fishAt("Nibbler", 45), fishAt("Nibbler", 55)
local c35, c45 = fishAt("Cuda", 35), fishAt("Cuda", 45)
local m45, p45 = fishAt("Moray", 45), fishAt("Puffer", 45)
local sStill = case("ReefShark", n45, "water", blueWater, "still", 60)
expect(sStill.hits > 0 and sStill.hits >= sStill.bites * 0.85, "Reef Shark: a still fish is bitten")
local sCruise = case("ReefShark", n45, "water", blueWater, "cruise", 60)
expect(sCruise.hits > 0 and sCruise.hits >= sCruise.bites * 0.85, "Reef Shark: a slow fish is bitten")
case("ReefShark", n40, "water", blueWater, "flee", 50)
local sFlee55 = case("ReefShark", n55, "water", blueWater, "flee", 50)
expect(sFlee55.caught >= TRIALS * 0.75, "Reef Shark: runs a LV 55 Nibbler down in a straight line")
case("ReefShark", c35, "water", blueWater, "flee", 50)
case("ReefShark", c40, "water", blueWater, "flee", 50)
local sCuda = case("ReefShark", c45, "water", blueWater, "flee", 50)
expect(sCuda.caught <= TRIALS * 0.25, "Reef Shark: a LV 45 'Cuda outruns it")
case("ReefShark", m45, "water", blueWater, "flee", 50)
case("ReefShark", p45, "water", blueWater, "flee", 50)
local sJuke = case("ReefShark", n45, "water", blueWater, "juke", 50)
expect(
	rate(sJuke) >= 0.25 and rate(sJuke) <= 0.75,
	"Reef Shark: a sideways juke escapes about half its strikes"
)
-- A missed strike: it carries through, banks round fast and runs in again from a new
-- angle (a juke then a dash away, or a loop back past it)
expect(
	#sJuke.rounds > 0 and median(sJuke.rounds) <= 3 and most(sJuke.rounds) <= 5,
	"Reef Shark: comes round within a few seconds of a miss"
)
local sHarass = case("ReefShark", n45, "water", blueWater, "harass", 50)
expect(
	sHarass.caught >= TRIALS * 0.75 and rate(sHarass) >= 0.35,
	"Reef Shark: a fish darting back and forth at it is bitten"
)
local sLoop = case("ReefShark", n45, "water", blueWater, "loop", 50)
-- (a loop it bites through has no miss to come round from: count its passes with the
-- harasser's)
local passes = table.move(sHarass.rounds, 1, #sHarass.rounds, 1, table.clone(sLoop.rounds))
expect(
	#passes > 0 and median(passes) <= 3 and most(passes) <= 6.5,
	"Reef Shark: comes round within a few seconds of a missed pass"
)
case("ReefShark", m45, "water", blueWater, "loop", 50)
local sLoopEarly = case("ReefShark", n45, "water", blueWater, "loop", 50, "close")
expect(rate(sLoopEarly) <= 0.5, "Reef Shark: a tight turn as it closes makes it overshoot")
case("ReefShark", m45, "water", blueWater, "loop", 50, "close")
local sDash = case("ReefShark", n45, "water", blueWater, "dash", 50)
expect(rate(sDash) <= 0.2, "Reef Shark: a Dash during its tell escapes")
local sHide = case("ReefShark", n45, "water", blueWater, "hide", 60)
expect(sHide.bites == 0, "Reef Shark: no bite through rock")
-- Smells blood: a fish 180 studs off is out of its range (110) unless it's bleeding
local sCalm = case("ReefShark", n45, "water", blueWater, "still", 180)
local sBleed = case("ReefShark", n45, "water", blueWater, "bleed", 180)
expect(sBleed.first * 3 <= sCalm.first, "Reef Shark: smells a bleeding fish from twice as far")
local _ = sJuke

-- A spot at `degrees` round the hub, `r` out, `up` studs over the floor
local function at(degrees: number, r: number, up: number): Vector3
	local a = math.rad(degrees)
	local x, z = math.cos(a) * r, math.sin(a) * r
	return Vector3.new(x, Seafloor.y(x, z) + up, z)
end
-- Down in the Trench's canyon, over its floor
local trenchR = 1200
local tx, tz = Seafloor.trenchPoint(trenchR, 0)
local function trenchAt(up: number): Vector3
	return Vector3.new(tx, Seafloor.y(tx, tz) + up, tz)
end

-- The levels (owner, 2026-10-21: "Ensure ease of eating them scales with levels as
-- well"): a Barracuda (LV 18) bites a LV 10 fish harder, shies off a LV 35 one
print("-- Levels")
local n35shy = case("Barracuda", n35, "water", water, "still", 30)
expect(n35shy.tells == 0 and n35shy.bites == 0, "levels: a Barracuda won't hunt a fish 17 levels above it")
local f10 = PredatorService.theirBite(Config.Predators.byId.Barracuda, 10)
local f18 = PredatorService.theirBite(Config.Predators.byId.Barracuda, 18)
local f28 = PredatorService.theirBite(Config.Predators.byId.Barracuda, 28)
expect(math.abs(f18 - 1) < 1e-6, "levels: its bite at its own level is as tuned")
expect(f10 > 1.2 and f10 <= 1.5, "levels: a fish 8 under it takes more (to 1.5×)")
expect(f28 < 0.6, "levels: a fish 10 over it takes about half")
print(
	string.format(
		"   Barracuda's bite × %.2f on a LV 10, × %.2f on a LV 18, × %.2f on a LV 28",
		f10,
		f18,
		f28
	)
)

-- A player's bites to kill one, by the biter's level against its own
local function bitesToKill(id: string, level: number): (number, boolean, number)
	local predator = only(id)
	predator.mode = "roam"
	predator.health = predator.maxHealth
	predator.hitBy = {}
	predator.target = nil
	local player = { Name = "Biter", UserId = 9, Parent = true }
	local character, root = sim.fish(4, predator.position)
	character:SetAttribute("FishLevel", level)
	sim.sessions = { [player] = { alive = true, inHub = false, safeUntil = 0 } }
	sim.characters = { [player] = { character = character, root = root } }
	sim.mouth = function()
		return predator.position, 4, 0
	end
	table.clear(sim.events)
	table.clear(sim.coral)
	local bites, swallowed = 0, false
	while predator.mode ~= "dead" and bites < 400 do
		sim.now += 1
		sim.requests.BitePredator(player, predator.index)
		bites += 1
	end
	for _, event in sim.events do
		if event.kind == "died" and event.payload.swallowed then
			swallowed = true
		end
	end
	local coral = 0
	for _, amount in sim.coral do
		coral += amount
	end
	sim.mouth = nil
	predator.mode = "dead"
	predator.respawnAt = math.huge
	return bites, swallowed, coral
end
local even, _, evenCoral = bitesToKill("Barracuda", 18)
local up10 = bitesToKill("Barracuda", 28)
local up20, swallowed20, upCoral = bitesToKill("Barracuda", 38)
local down10 = bitesToKill("Barracuda", 8)
print(
	string.format(
		"   bites to kill a Barracuda (LV 18): LV 8 %d, LV 18 %d, LV 28 %d, LV 38 %d%s · coral LV 18 %.0f, LV 38 %.0f",
		down10,
		even,
		up10,
		up20,
		if swallowed20 then " (swallowed whole)" else "",
		evenCoral,
		upCoral
	)
)
expect(even >= 6 and even <= 10, "levels: a fish of its level kills it in about 8 bites")
expect(up10 <= even * 0.65, "levels: 10 levels up chunks it in a few bites")
expect(up20 == 1 and swallowed20, "levels: 20 levels up swallows it whole in one bite")
expect(down10 >= even * 1.6, "levels: 10 levels under barely scratches it")
expect(upCoral <= evenCoral * 0.2, "levels: a kill pays a fish far above it little")

-- Sea Lion, the kelp's harrier (LV 6)
print("-- Sea Lion: harrier")
local kelp = at(30, 380, 12)
local n6 = fishAt("Nibbler", 6)
local lStill = case("SeaLion", n6, "water", kelp, "still", 40)
expect(lStill.caught >= TRIALS * 0.9, "Sea Lion: a still fish is nipped")
-- (it lets a fish go after its `nips` and leaves it `forget` s: a 60 s trial sees two
-- rounds of nips at most)
local lionStyle = Config.Predators.byId.SeaLion.style :: any
expect(
	lStill.hits <= TRIALS * lionStyle.nips * math.ceil(SECONDS / lionStyle.forget),
	`Sea Lion: lets a fish go after {lionStyle.nips} nips ({lStill.hits} in {TRIALS} trials)`
)
expect(
	math.abs(lStill.fraction - Config.Predators.byId.SeaLion.biteFraction) < 1e-6,
	"Sea Lion: a light nip at its level"
)
local lFlee = case("SeaLion", n6, "water", kelp, "flee", 40)
expect(lFlee.caught >= TRIALS * 0.6, "Sea Lion: runs a fleeing LV 6 fish down")
-- It's where a new fish learns to juke: one in time beats its nip, one late doesn't
local lJuke = case("SeaLion", n6, "water", kelp, "juke", 40)
expect(rate(lJuke) <= 0.35, "Sea Lion: a juke in time beats its nip")
reactNext = 0.6
local lLate = case("SeaLion", n6, "water", kelp, "juke", 40)
print("   (that last juke came 0.6 s after its tell began)")
expect(rate(lLate) >= 0.5, "Sea Lion: a juke too late is nipped")
local lDash = case("SeaLion", n6, "water", kelp, "stillDash", 40)
-- (a Dash beats the nip it's used on; a harrier comes round again before the fish's
-- Dash would have recharged, and the sim's fish only dashes once every 2.5 s)
expect(rate(lDash) <= 0.55, "Sea Lion: a Dash beats the nip it's used on")
sim.data = { tutorial = { done = false } }
local lLearner = case("SeaLion", n6, "water", kelp, "still", 40)
sim.data = {}
expect(lLearner.tells == 0, "Sea Lion: leaves a fish in the tutorial alone")

-- Goliath Grouper, the wreck bay's gulper (LV 18)
print("-- Goliath Grouper: lurker, gulps")
local bay = at(180, 650, 6)
local n18 = fishAt("Nibbler", 18)
local gStill = case("GoliathGrouper", n18, "water", bay, "still", 22)
expect(
	gStill.caught >= TRIALS * 0.75 and gStill.pulled > 0,
	"Grouper: its gulp pulls a still fish in and bites it"
)
local gDash = case("GoliathGrouper", n18, "water", bay, "stillDash", 22)
expect(rate(gDash) <= 0.35, "Grouper: a Dash breaks the gulp")
case("GoliathGrouper", n18, "water", bay, "flee", 22)
case("GoliathGrouper", n18, "water", bay, "juke", 22)

-- Giant Trevally, the reef's packs (LV 32)
print("-- Giant Trevally: pack of three")
local reef = at(300, 690, 30)
local n32, c32 = fishAt("Nibbler", 32), fishAt("Cuda", 32)
local tStill = case("GiantTrevally", n32, "water", reef, "still", 50)
expect(tStill.caught >= TRIALS * 0.9 and tStill.biters >= 2, "Trevally: the pack bites, more than one of it")
local tFlee = case("GiantTrevally", n32, "water", reef, "flee", 50)
-- (a fish that flees out of the reef is let go: PC 2026-10-22, the packs had chased
-- LV 1-8 fish into the Kelp Shallows)
expect(
	tFlee.caught >= TRIALS * 0.3 and tFlee.biters >= 2,
	"Trevally: the pack runs a LV 32 Nibbler down in the reef"
)
case("GiantTrevally", c32, "water", reef, "flee", 50)
-- Its own water (PC 2026-10-22: the LV 32 packs followed LV 1-8 fish 300 studs into
-- the Kelp Shallows, to r 213): a pack at the reef's inner edge on a LV 8 fish that
-- swims straight for the hub never follows it far into the kelp, nor bites it there
do
	local pack = only("GiantTrevally")
	local a = math.rad(300)
	local inward = -Vector3.new(math.cos(a), 0, math.sin(a))
	local start = Vector3.new(math.cos(a) * 560, 0, math.sin(a) * 560)
	local fish = fishAt("Nibbler", 8)
	local player = { Name = "Small", UserId = 11, Parent = true }
	local character, root =
		sim.fish(fish.length, start + Vector3.new(0, Seafloor.y(start.X, start.Z) + 25, 0))
	character:SetAttribute("FishLevel", 8)
	character:SetAttribute("MaxHealth", 100)
	character:SetAttribute("Health", 100)
	sim.sessions = { [player] = { alive = true, inHub = false, safeUntil = 0 } }
	sim.characters = { [player] = { character = character, root = root } }
	for i, member in pack.pack or { pack } do
		member.position = root.Position - inward * 40 + Vector3.new(i * 6, 0, 0)
		member.velocity = Vector3.zero
		member.mode = "roam"
		member.target = nil
		member.hitBy = {}
		member.health = member.maxHealth
	end
	table.clear(sim.events)
	local deepest = math.huge
	for _ = 1, 300 do
		sim.now += DT
		local p = root.Position + inward * fish.top * DT
		local r = Vector3.new(p.X, 0, p.Z).Magnitude
		if r > 260 then
			root.Position = Vector3.new(p.X, Seafloor.y(p.X, p.Z) + 25, p.Z)
		end
		root.AssemblyLinearVelocity = inward * fish.top
		heartbeat(DT)
		for _, member in pack.pack or { pack } do
			deepest = math.min(deepest, Vector3.new(member.position.X, 0, member.position.Z).Magnitude)
		end
	end
	print(string.format("   pack after a LV 8 fish swimming for the hub: deepest r %.0f", deepest))
	expect(
		deepest >= 400,
		`Trevally: the pack stays out of the Kelp Shallows (came to r {math.floor(deepest)})`
	)
	sim.sessions = {}
	sim.characters = {}
end
local tDash = case("GiantTrevally", n32, "water", reef, "dash", 50)
expect(rate(tDash) <= 0.45, "Trevally: a Dash beats most strikes")
local tHide = case("GiantTrevally", n32, "water", reef, "hide", 50)
expect(tHide.bites == 0, "Trevally: no bite through rock (the arches hide you)")

-- Mako, the Open Blue's missile (LV 45)
print("-- Mako: missile from below")
local mStill = case("MakoShark", n45, "water", blueWater, "still", 70)
expect(mStill.caught >= TRIALS * 0.9, "Mako: a still fish is bitten")
local mFlee = case("MakoShark", c45, "water", blueWater, "flee", 60)
expect(mFlee.caught >= TRIALS * 0.6, "Mako: runs even a LV 45 'Cuda down")
-- It turns wide: a juke the moment its jaw flashes beats it, a late one doesn't
local mJuke = case("MakoShark", n45, "water", blueWater, "juke", 60)
expect(rate(mJuke) <= 0.35, "Mako: a juke in time beats it")
reactNext = 0.5
local mLate = case("MakoShark", n45, "water", blueWater, "juke", 60)
print("   (that last juke came 0.5 s into its 0.8 s tell)")
expect(rate(mLate) >= 0.4, "Mako: a late juke is caught")
local mDash = case("MakoShark", n45, "water", blueWater, "stillDash", 60)
expect(rate(mDash) <= 0.35, "Mako: a Dash beats it")

-- Sixgill, the Ruins' patroller (LV 60)
print("-- Sixgill: slow patroller, heavy bite")
local ruins = at(8, 1180, 20)
local n60 = fishAt("Nibbler", 60)
local xStill = case("SixgillShark", n60, "water", ruins, "still", 60)
expect(xStill.caught >= TRIALS * 0.9, "Sixgill: a still fish is bitten")
expect(
	math.abs(xStill.fraction - Config.Predators.byId.SixgillShark.biteFraction) < 1e-6,
	"Sixgill: its heavy bite"
)
local xFlee = case("SixgillShark", n60, "water", ruins, "flee", 60)
expect(xFlee.caught <= TRIALS * 0.3, "Sixgill: a fish of its level outswims it")

-- Wolf Eel, the Vents' crevice striker (LV 75)
print("-- Wolf Eel: lunges from its hole")
local vents = at(175, 1150, 4)
local n75 = fishAt("Nibbler", 75)
local wStill = case("WolfEel", n75, "water", vents, "still", 22)
expect(wStill.caught >= TRIALS * 0.9, "Wolf Eel: a fish by its hole is bitten")
local wFar = case("WolfEel", n75, "water", vents, "still", 80)
expect(wFar.bites == 0, "Wolf Eel: a fish well clear of its hole is left alone")
local wFlee = case("WolfEel", n75, "water", vents, "flee", 22)
local tether = (Config.Predators.byId.WolfEel.style :: any).tether
expect(
	wFlee.stray <= tether + 30,
	`Wolf Eel: never strays far from its hole ({math.floor(wFlee.stray)} studs)`
)
local wDash = case("WolfEel", n75, "water", vents, "stillDash", 22)
expect(rate(wDash) <= 0.35, "Wolf Eel: a Dash beats its lunge")
-- By a rock (PC 2026-10-22: three of four sat nose-down at their holes and never
-- hunted): its hole at the foot of a 24-stud rock its body reaches over; roaming 20 s
-- it never points more than MAX_PITCH (0.8) down, and a still fish 18 studs out from
-- the hole, away from the rock, is bitten
do
	local eel = only("WolfEel")
	local hole = Vector3.new(vents.X, Seafloor.y(vents.X, vents.Z) + 4, vents.Z)
	local flatGround = sim.groundY
	sim.groundY = function(x: number, z: number): number
		local base = Seafloor.y(x, z)
		if math.abs(x - (hole.X + 14)) < 6 and math.abs(z - hole.Z) < 6 then
			return base + 24
		end
		return base
	end
	eel.position, eel.home = hole, hole
	eel.velocity = Vector3.zero
	eel.heading = Vector3.new(1, 0, 0)
	eel.mode, eel.target = "roam", nil
	eel.waypoint, eel.waypointUntil = hole, 0
	sim.sessions, sim.characters = {}, {}
	local lowest = 1
	for _ = 1, 200 do
		sim.now += DT
		heartbeat(DT)
		lowest = math.min(lowest, eel.heading.Y)
	end
	local fish = fishAt("Nibbler", 75)
	local player = { Name = "Beside", UserId = 12, Parent = true }
	local spot = hole + Vector3.new(-18, 0, 0)
	local character, root = sim.fish(fish.length, spot)
	character:SetAttribute("FishLevel", 75)
	character:SetAttribute("MaxHealth", 100)
	character:SetAttribute("Health", 100)
	sim.sessions = { [player] = { alive = true, inHub = false, safeUntil = 0 } }
	sim.characters = { [player] = { character = character, root = root } }
	table.clear(sim.events)
	local hits = 0
	for _ = 1, 200 do
		sim.now += DT
		heartbeat(DT)
	end
	for _, event in sim.events do
		if event.kind == "bite" and event.payload.hit then
			hits += 1
		end
	end
	print(
		string.format(
			"   by a rock: steepest nose-down %.2f, then %d bites on a still fish by its hole in 20 s",
			-lowest,
			hits
		)
	)
	expect(lowest >= -0.81, `Wolf Eel: never stands on its nose by a rock ({string.format("%.2f", lowest)})`)
	expect(hits > 0, "Wolf Eel: hunts a fish by its hole when a rock stands beside it")
	sim.groundY = flatGround
	sim.sessions, sim.characters = {}, {}
end
-- By a tall column (PC 2026-10-22 round 2: two eels sat ~110 studs over the floor at
-- the pitch cap, their holes at the column's foot, and never hunted a fish 13–16
-- studs off them): roaming 40 s from its hole it stays near the floor; one found up
-- on the column takes it as its hole and hunts a still fish 15 studs off it
do
	local eel = only("WolfEel")
	local hole = Vector3.new(vents.X, Seafloor.y(vents.X, vents.Z) + 4, vents.Z)
	local flatGround = sim.groundY
	local function column(x: number, z: number): boolean
		return math.abs(x - (hole.X + 22)) < 10 and math.abs(z - hole.Z) < 10
	end
	sim.groundY = function(x: number, z: number): number
		local base = Seafloor.y(x, z)
		return if column(x, z) then base + 110 else base
	end
	local function reset(at: Vector3)
		eel.position, eel.home = at, hole
		eel.velocity = Vector3.zero
		eel.heading = Vector3.new(1, 0, 0)
		eel.mode, eel.target = "roam", nil
		eel.waypoint, eel.waypointUntil = at, 0
		eel.strayed = math.huge
	end
	reset(hole)
	sim.sessions, sim.characters = {}, {}
	local highest = 0
	for _ = 1, 400 do
		sim.now += DT
		heartbeat(DT)
		highest = math.max(highest, eel.position.Y - hole.Y)
	end
	-- (found up on the column, its hole at the foot: it takes the nearest spot by the
	-- floor as its hole and goes down to it, then hunts a fish by that hole)
	local top = Vector3.new(hole.X + 22, Seafloor.y(hole.X, hole.Z) + 110 + 22 * 0.12 + 2, hole.Z)
	reset(top)
	local down: number? = nil
	for step = 1, 200 do
		sim.now += DT
		heartbeat(DT)
		local home = eel.home :: Vector3
		if
			down == nil
			and home.Y - Seafloor.y(home.X, home.Z) < 20
			and eel.position.Y - Seafloor.y(eel.position.X, eel.position.Z) < 20
		then
			down = step * DT
		end
	end
	local home = eel.home :: Vector3
	local fish = fishAt("Nibbler", 75)
	local player = { Name = "Beside", UserId = 13, Parent = true }
	local away = Vector3.new(home.X - (hole.X + 22), 0, home.Z - hole.Z)
	away = if away.Magnitude > 1e-3 then away.Unit else Vector3.new(-1, 0, 0)
	local spot = home + away * 15
	local character, root = sim.fish(fish.length, spot)
	character:SetAttribute("FishLevel", 75)
	character:SetAttribute("MaxHealth", 100)
	character:SetAttribute("Health", 100)
	sim.sessions = { [player] = { alive = true, inHub = false, safeUntil = 0 } }
	sim.characters = { [player] = { character = character, root = root } }
	table.clear(sim.events)
	local hunted: number? = nil
	for step = 1, 200 do
		sim.now += DT
		heartbeat(DT)
		if hunted == nil and eel.target == player then
			hunted = step * DT
		end
	end
	local hits = 0
	for _, event in sim.events do
		if event.kind == "bite" and event.payload.hit then
			hits += 1
		end
	end
	print(
		string.format(
			"   by a 110-stud column: rose at most %.0f studs off its hole in 40 s; found on top, back by the floor after %s s, then hunted after %s s, %d bites in 20 s",
			highest,
			if down then string.format("%.1f", down) else "never",
			if hunted then string.format("%.1f", hunted) else "never",
			hits
		)
	)
	expect(highest < 40, `Wolf Eel: doesn't climb the column beside its hole ({math.floor(highest)} studs)`)
	expect(down ~= nil and down < 12, "Wolf Eel: one stranded on a column goes back down by the floor")
	expect(hunted ~= nil and hunted < 8, "Wolf Eel: then hunts a fish by its new hole")
	expect(hits > 0, "Wolf Eel: then bites a fish by its new hole")
	sim.groundY = flatGround
	sim.sessions, sim.characters = {}, {}
end
-- Its holes are by the floor (PC 2026-10-23: four held holes 69-121 studs up beside
-- basalt columns, one sat on the drop-off's crest at shelf height): in a field of
-- 100-stud columns every 40 studs, and with the real drop-off's lip standing at
-- shelf height out to r 940, every eel's new hole stands within LURK_RISE (14) plus
-- its lurk height of the nominal floor
do
	local flatGround = sim.groundY
	sim.groundY = function(x: number, z: number): number
		local base = Seafloor.y(x, z)
		local r = math.sqrt(x * x + z * z)
		if r < 940 then
			return math.max(base, Config.World.seabedY)
		end
		local cx, cz = (x % 40) - 20, (z % 40) - 20
		return if math.abs(cx) < 7 and math.abs(cz) < 7 then base + 100 else base
	end
	local worst = 0
	local count = 0
	for _, predator in PredatorService.list() do
		if predator.def.id == "WolfEel" then
			for _ = 1, 8 do
				predator.mode = "dead"
				predator.respawnAt = sim.now
				heartbeat(DT)
				local home = predator.home :: Vector3
				worst = math.max(worst, home.Y - Seafloor.y(home.X, home.Z))
				count += 1
			end
		end
	end
	print(
		string.format(
			"   holes: %d picked among columns and the drop-off's lip, highest %.1f studs over the floor",
			count,
			worst
		)
	)
	local lurk = (Config.Predators.byId.WolfEel.style :: any).lurk
	expect(
		count > 0 and worst <= 14 + lurk[2] + 0.5,
		`Wolf Eel: every hole is by the floor ({string.format("%.1f", worst)} studs up)`
	)
	sim.groundY = flatGround
end

-- Goblin Shark, the Trench's jaw launcher (LV 90)
print("-- Goblin Shark: jaw throw")
local n90 = fishAt("Nibbler", 90)
local canyon = trenchAt(40)
local oStill = case("GoblinShark", n90, "water", canyon, "still", 60)
expect(oStill.caught >= TRIALS * 0.9, "Goblin: a still fish is bitten from far off")
local oDodge = case("GoblinShark", n90, "water", canyon, "dodge", 60, "burst")
expect(rate(oDodge) <= 0.35, "Goblin: dodging sideways in time beats its jaw throw")
reactNext = 0.9
local oLate = case("GoblinShark", n90, "water", canyon, "dodge", 60, "burst")
print("   (that last dodge came 0.9 s into its 1.1 s tell)")
expect(rate(oLate) >= 0.5, "Goblin: a dodge too late is caught")
local oFlee = case("GoblinShark", n90, "water", canyon, "flee", 60)
expect(oFlee.caught <= TRIALS * 0.5, "Goblin: too slow to run a fleeing fish down")

-- Black Dragonfish, the Trench's lure (LV 88)
print("-- Black Dragonfish: lure")
local n88 = fishAt("Nibbler", 88)
local deepWater = trenchAt(90)
local dStill = case("BlackDragonfish", n88, "water", deepWater, "still", 40)
expect(dStill.caught >= TRIALS * 0.9, "Dragonfish: a still fish is bitten")
expect(dStill.pulled > 0 and dStill.lured > 0, "Dragonfish: its lure draws the fish in, with a warning")
local dDash = case("BlackDragonfish", n88, "water", deepWater, "stillDash", 40)
expect(rate(dDash) <= 0.55, "Dragonfish: a Dash beats the lunge it's used on")

if failures > 0 then
	error(`{failures} predator check(s) failed`)
end
print("predators: OK")
