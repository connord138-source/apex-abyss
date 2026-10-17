-- Hit rates of the AI predators' telegraphed bites (run_predators.sh). Each
-- scenario puts one predator near one fish and runs the real PredatorService for a
-- minute, many times from different directions; the fish sits still, cruises
-- slowly, or reacts to the tell by swimming or dashing away.
local rbx = require("./sim_rbx")
local Vector3 = rbx.Vector3
local sim = require("./sim_services")
local Config = require("./Config")
local Seafloor = require("./Seafloor")
local Size = require("./Size")
local PredatorService = require("./PredatorService")

local swim = Config.Tuning.swim
local DT = 0.1
local LAG = 0.1 -- the server sees a fish this far in the past
local TRIALS = 16
local SECONDS = 60

sim.groundY = function(x: number, z: number): number
	return Seafloor.y(x, z)
end
PredatorService.start()
local heartbeat = rbx.heartbeat :: (number) -> ()

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

-- A fish that stays put or dawdles is nearly always bitten; one that dashes off
-- within about half a second of the tell gets away
local failures = 0
local function check(where: string, id: string, behaviour: string, hits: number, bites: number, react: number)
	local rate = if bites > 0 then hits / bites else 0
	if (behaviour == "still" or behaviour == "cruise") and (bites == 0 or rate < 0.9) then
		failures += 1
		print(`FAIL: {where} {id} {behaviour}: only {math.floor(rate * 100)}% of its bites landed`)
	elseif behaviour == "dash" and react <= 0.55 and rate > 0.1 then
		failures += 1
		print(`FAIL: {where} {id} dash at {react} s: {math.floor(rate * 100)}% of its bites landed`)
	end

	type Behaviour = "still" | "cruise" | "swim" | "dash"

	local function run(
		where: string,
		id: string,
		length: number,
		spot: Vector3,
		behaviour: Behaviour,
		startGap: number,
		react: number?
	)
		local bites, hits, tells, tellHits, firsts = 0, 0, 0, 0, {}
		local gapSum, closest = 0, math.huge
		local top = Size.topSpeed(length)
		for trial = 1, TRIALS do
			table.clear(sim.events)
			table.clear(sim.hits)
			sim.now = 1000 * trial
			local predator = only(id)
			local angle = (trial - 1) / TRIALS * 2 * math.pi
			local from = spot + Vector3.new(math.cos(angle), 0, math.sin(angle)) * startGap
			predator.position = Vector3.new(from.X, spot.Y + 6, from.Z)
			predator.velocity = Vector3.zero
			predator.heading = Vector3.new(math.cos(angle + 2), 0, math.sin(angle + 2)) -- not facing it
			predator.mode = "roam"
			predator.target = nil
			predator.waypoint = predator.position
			predator.waypointUntil = 0
			predator.hitBy = {}
			predator.health = predator.maxHealth
			local player = { Name = "Fish", UserId = 7 }
			local character, root = sim.fish(length, spot)
			sim.sessions = { [player] = { alive = true, inHub = false, safeUntil = 0 } }
			sim.characters = { [player] = { character = character, root = root } }
			local position, velocity = spot, Vector3.zero
			local history = {}
			local reactAt, fleeFrom: Vector3? = math.huge, nil
			local seen = 0
			local first = nil
			for step = 1, math.floor(SECONDS / DT) do
				sim.now += DT
				-- The fish
				local sub = DT / 4
				for _ = 1, 4 do
					local want = Vector3.zero
					if behaviour == "cruise" then
						local t = sim.now * 5 / 12
						want = Vector3.new(-math.sin(t), 0, math.cos(t)) * 5
					elseif (behaviour == "swim" or behaviour == "dash") and sim.now >= reactAt then
						local away = Vector3.new(
							position.X - (fleeFrom :: Vector3).X,
							0,
							position.Z - (fleeFrom :: Vector3).Z
						).Unit
						local into = sim.now - reactAt
						if behaviour == "dash" and into < swim.dashSeconds then
							want = away * top * swim.boostMultiplier
							velocity = want -- a dash is a burst
						elseif into < 1.6 then
							want = away * top
						end
					end
					velocity += (want - velocity) * (1 - math.exp(
						-(if want.Magnitude > 0 then swim.accel else swim.drag) * sub
					))
					position += velocity * sub
				end
				table.insert(history, { at = sim.now, position = position, velocity = velocity })
				while #history > 1 and history[2].at <= sim.now - LAG do
					table.remove(history, 1)
				end
				root.Position = history[1].position
				root.AssemblyLinearVelocity = history[1].velocity
				heartbeat(DT)
				for i = seen + 1, #sim.events do
					local event = sim.events[i]
					if event.kind == "windup" and event.payload.target == player.UserId then
						tells += 1
						reactAt = sim.now + (react or 0.3) -- a person's reaction to INCOMING
						fleeFrom = predator.position
					elseif event.kind == "bite" then
						bites += 1
						gapSum += (Vector3.new(event.payload.x, event.payload.y, event.payload.z) - position).Magnitude
						if event.payload.hit then
							hits += 1
							tellHits += 1
							first = first or (sim.now - 1000 * trial)
						end
					end
				end
				seen = #sim.events
				closest = math.min(closest, (predator.position - position).Magnitude)
				if behaviour ~= "cruise" and sim.now > reactAt + 3 then
					reactAt = math.huge -- it settles again (still)
				end
				local _ = step
			end
			table.insert(firsts, first or SECONDS)
		end
		table.sort(firsts)
		print(
			string.format(
				"%-10s L%-2d %-9s %-6s %4.2fs  bites %3d  hits %3d  (%3.0f%% of bites, %3.0f%% of tells)  %4.1f hits/min  first %4.1f s  mouth-fish at snap %4.1f  closest body %4.1f",
				id,
				length,
				where,
				behaviour,
				react or 0.3,
				bites,
				hits,
				if bites > 0 then hits / bites * 100 else 0,
				if tells > 0 then tellHits / tells * 100 else 0,
				hits / TRIALS / (SECONDS / 60),
				firsts[math.ceil(#firsts / 2)],
				if bites > 0 then gapSum / bites else 0,
				closest
			)
		)
		if where ~= "hidden" then
			check(where, id, behaviour, hits, bites, react or 0.3)
		end
		return hits, bites
	end

	print(`{TRIALS} trials × {SECONDS} s each; the fish reacts 0.3 s after a tell`)
end
local shelf = Vector3.new(500, 0, 0)
local sand = Vector3.new(shelf.X, Seafloor.y(shelf.X, shelf.Z) + 0.2 * 3, shelf.Z)
local water = Vector3.new(shelf.X, 30, shelf.Z)
run("sand", "Barracuda", 3, sand, "still", 40)
run("water", "Barracuda", 3, water, "still", 40)
run("near sand", "Barracuda", 3, sand + Vector3.new(0, 2, 0), "cruise", 40)
run("water", "Barracuda", 3, water, "cruise", 40)
run("sand", "Barracuda", 3, sand, "swim", 40)
run("sand", "Barracuda", 3, sand, "dash", 40)
run("water", "Barracuda", 3, water, "dash", 40)
run("sand", "Barracuda", 3, sand, "dash", 40, 0.55)
run("sand", "Barracuda", 3, sand, "dash", 40, 0.75)
-- Hidden: rock between the jaw and the fish (under an arch, in a reef's tunnel)
sim.sees = function()
	return false
end
local hiddenHits, hiddenBites = run("hidden", "Barracuda", 3, sand, "still", 40)
sim.sees = function()
	return true
end
if hiddenHits > 0 or hiddenBites > 0 then
	error("a predator bit a fish through rock")
end
local blue = Vector3.new(0, 0, -1200)
local deep = Seafloor.y(blue.X, blue.Z)
local blueWater = Vector3.new(blue.X, deep + 250, blue.Z)
local blueSand = Vector3.new(blue.X, deep + 0.2 * 5, blue.Z)
run("water", "ReefShark", 5, blueWater, "still", 60)
run("sand", "ReefShark", 5, blueSand, "still", 60)
run("water", "ReefShark", 5, blueWater, "cruise", 60)
run("water", "ReefShark", 5, blueWater, "swim", 60)
run("water", "ReefShark", 5, blueWater, "dash", 60)
run("water", "ReefShark", 5, blueWater, "dash", 60, 0.7)
run("water", "ReefShark", 5, blueWater, "dash", 60, 0.9)
if failures > 0 then
	error(`{failures} predator check(s) failed`)
end
print("predators: OK")
