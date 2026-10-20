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

local function only(id: string)
	local chosen = nil
	for _, predator in PredatorService.list() do
		if predator.def.id == id and chosen == nil then
			chosen = predator
		else
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
		rounds = {},
		agains = {},
	}
	local firsts = {}
	for trial = 1, TRIALS do
		table.clear(sim.events)
		table.clear(sim.hits)
		sim.now = 1000 * trial
		sim.sees = function()
			return behaviour ~= "hide"
		end
		local predator = only(id)
		local angle = (trial - 1) / TRIALS * 2 * math.pi
		local from = spot + Vector3.new(math.cos(angle), 0, math.sin(angle)) * startGap
		predator.position = Vector3.new(from.X, spot.Y + 4, from.Z)
		predator.velocity = Vector3.zero
		predator.heading = Vector3.new(math.cos(angle + 2), 0, math.sin(angle + 2)) -- not facing it
		predator.mode = "roam"
		predator.target = nil
		predator.waypoint = predator.position
		predator.waypointUntil = 0
		predator.hitBy = {}
		predator.health = predator.maxHealth
		predator.burstUntil = 0
		predator.stunUntil = 0
		predator.fails = {}
		predator.ignore = {}
		local player = { Name = "Fish", UserId = 7, Parent = true }
		local character, root = sim.fish(fish.length, spot)
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
				alarmAt = sim.now + REACT
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
				elseif behaviour == "dash" and since >= 0 and since < swim.dashSeconds then
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
			heartbeat(DT)
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
						alarmAt = sim.now + REACT
					end
					if event.kind == "windup" and behaviour == "burrowMid" then
						character:SetAttribute("Burrowed", true)
					elseif event.kind == "windup" and behaviour == "stun" and PredatorService.stun then
						local count = PredatorService.stun(position, 30, 3)
						expect(count == 1, `stun: {count} stunned, wanted 1`)
					end
				elseif event.kind == "bite" then
					result.bites += 1
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

print(`{TRIALS} runs × {SECONDS} s each; a fish reacts {REACT} s after it sees a burst or a tell`)

-- Barracuda, the ambush sprinter, on the shelf (LV 1–40 water)
local shelf = Vector3.new(500, 0, 0)
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
-- Sits still and jukes each burst: after `giveUp` failed bursts it leaves the fish be
local dodge = case("Barracuda", n25, "water", water, "dodge", 30, "burst")
local giveUp = Config.Predators.byId.Barracuda.style.giveUp :: number
local forget = Config.Predators.byId.Barracuda.style.forget :: number
expect(
	dodge.hits == 0 and dodge.bites <= TRIALS * giveUp * math.ceil(SECONDS / (forget + 10)),
	"Barracuda: gives a fish up after a few failed bursts"
)
expect(rate(juke) <= 0.3, "Barracuda: a sideways juke beats most of its strikes")
-- Out of breath after a missed burst it still glides round to face the fish, and
-- bursts again once it has its wind
expect(
	#dodge.rounds > 0 and median(dodge.rounds) <= 3.5,
	"Barracuda: faces the fish again within a few seconds of a miss"
)
case("Barracuda", n25, "water", water, "loop", 30)
case("Barracuda", n25, "water", water, "juke", 30, "burst")
case("Barracuda", n25, "water", water, "loop", 30, "burst")
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
expect(
	math.abs(puff.fraction - Config.Predators.byId.Barracuda.biteFraction * 0.5) < 1e-6,
	"puffed: half damage"
)
-- (every bite but a killing one flinches it)
expect(puff.recoil > 0 and puff.stunned >= puff.hits - TRIALS, "puffed: recoil and a flinch on every bite")
print(
	string.format(
		"   puffed: a bite took %.0f%% (not %.0f%%), the Barracuda lost %.0f%% of its health over %d runs and flinched %d times",
		puff.fraction * 100,
		Config.Predators.byId.Barracuda.biteFraction * 100,
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
-- A missed strike: it carries through, banks round fast and runs in again from a new
-- angle (a juke then a dash away, or a loop back past it)
expect(
	#sJuke.rounds > 0 and median(sJuke.rounds) <= 3 and most(sJuke.rounds) <= 5,
	"Reef Shark: comes round within a few seconds of a miss"
)
local sHarass = case("ReefShark", n45, "water", blueWater, "harass", 50)
expect(
	sHarass.caught >= TRIALS * 0.9 and rate(sHarass) >= 0.5,
	"Reef Shark: a fish darting back and forth at it is bitten"
)
local sLoop = case("ReefShark", n45, "water", blueWater, "loop", 50)
expect(
	#sLoop.rounds > 0 and median(sLoop.rounds) <= 3 and most(sLoop.rounds) <= 5,
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
-- Smells blood: a fish 130 studs off is out of its range (80) unless it's bleeding
local sCalm = case("ReefShark", n45, "water", blueWater, "still", 130)
local sBleed = case("ReefShark", n45, "water", blueWater, "bleed", 130)
expect(sBleed.first * 3 <= sCalm.first, "Reef Shark: smells a bleeding fish from twice as far")
local _ = sJuke

if failures > 0 then
	error(`{failures} predator check(s) failed`)
end
print("predators: OK")
