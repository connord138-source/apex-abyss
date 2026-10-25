-- How full of fish the sea is, and what that costs a client (run_density.sh): the
-- prey schools (Shared/Schools) per biome, how often a swimming fish has prey in
-- sight, and how many prey fish a client moves, waves and keeps built at once, from
-- a grid of camera spots over every biome at two swimming heights each. Reads the
-- draw ranges Schools gives each fish (`range`, `wave`, a school's `reach`) the way
-- SchoolController uses them; an older Schools without them is measured the old
-- way (every fish of a school within 520 studs moved, waves within 160, every fish
-- built at start). Per frame (at 60 fps, full detail) it counts what
-- SchoolController does now (moves by MOVE_STEP at each fish's `pace`: the most its
-- path carries it and its ends turn, a 60th of a second at a time, over a second,
-- sway and turns included; waves by WAVE_NEAR / WAVE_HALF, a built fish out of
-- range looked at every CULL_EVERY) against the 2026-10-24 rules
-- (every drawn fish moved every frame, waves every frame within 60 and every other
-- past it, CULL_EVERY 4); keep these in step with SchoolController.
local Config = require("./Config")
local Seafloor = require("./Seafloor")
local Schools = require("./Schools")

local World = Config.World
local T = 137.25 -- any moment

-- The biome at a point (Shared/Biomes without the hub's Layout)
local function biomeAt(x: number, z: number): string
	local r, angle = Seafloor.polar(x, z)
	if r < World.hub.radius then
		return "Hub"
	end
	local fallback = "?"
	for _, biome in Config.Biomes.list do
		if r >= biome.radiusFrom and r < biome.radiusTo then
			if biome.angleFrom == 0 and biome.angleTo == 360 then
				fallback = biome.id
			elseif Seafloor.inSector(angle, biome.angleFrom, biome.angleTo) then
				return biome.id
			end
		end
	end
	return fallback
end

local ORDER = {
	"KelpShallows",
	"ShipwreckGraveyard",
	"CoralReef",
	"OpenBlue",
	"SunkenRuins",
	"HydrothermalVents",
	"AbyssalTrench",
	"TrenchCanyon",
}
-- Where a fish's camera usually is in each biome: heights over the local floor
local HEIGHTS: { [string]: { number } } = {
	KelpShallows = { 12, 45 },
	ShipwreckGraveyard = { 15, 50 },
	CoralReef = { 15, 55 },
	OpenBlue = { 120, 280 },
	SunkenRuins = { 30, 100 },
	HydrothermalVents = { 30, 100 },
	AbyssalTrench = { 40, 150 },
	TrenchCanyon = { 40, 150 },
}

local newModel = Schools.fish[1].range ~= nil
local OLD_DRAW, OLD_WAVE = 520, 160
-- SchoolController's tiers
local FPS = 60
local WAVE_DISTANCE, WAVE_NEAR, WAVE_HALF = 160, 30, 60
local MOVE_STEP, MOVE_MAX, MOVE_NEAR = 0.003, 4, 40
local CULL_EVERY, OLD_CULL_EVERY = 6, 4

-- The schools and fish per biome (a tide's schools apart)
local schoolsIn: { [string]: number } = {}
local fishIn: { [string]: number } = {}
local tideSchools, tideFish = 0, 0
local mixIn: { [string]: { [string]: number } } = {}
for _, school in Schools.list do
	if school.tide then
		tideSchools += 1
		tideFish += school.count
		continue
	end
	local biome = biomeAt(school.center.X, school.center.Z)
	schoolsIn[biome] = (schoolsIn[biome] or 0) + 1
	fishIn[biome] = (fishIn[biome] or 0) + school.count
	mixIn[biome] = mixIn[biome] or {}
	mixIn[biome][school.prey] = (mixIn[biome][school.prey] or 0) + 1
end

-- Every fish where it is at T (plain numbers, binned by 100 studs across)
local BIN = 100
local px, py, pz, pschool, ppace = {}, {}, {}, {}, {}
local bins: { [number]: { number } } = {}
local function key(bx: number, bz: number): number
	return (bx + 100) * 1000 + (bz + 100)
end
for index = 1, Schools.COUNT do
	local fish = Schools.fish[index]
	local school = Schools.list[fish.school]
	if school.tide then
		continue
	end
	local p = Schools.position(index, T)
	px[index], py[index], pz[index], pschool[index] = p.X, p.Y, p.Z, fish.school
	-- (its pace: SchoolController measures it as it's drawn)
	local pace = 0
	for k = 0, 11 do
		local t = T + k / 12
		local a = Schools.fishFrame(index, Schools.schoolFrame(fish.school, t), t)
		local b = Schools.fishFrame(index, Schools.schoolFrame(fish.school, t + 1 / 60), t + 1 / 60)
		local turned = math.acos(math.clamp(a.LookVector:Dot(b.LookVector), -1, 1))
		pace = math.max(pace, ((b.Position - a.Position).Magnitude + turned * fish.length * 0.5) * 60)
	end
	ppace[index] = pace
	local k = key(math.floor(p.X / BIN), math.floor(p.Z / BIN))
	bins[k] = bins[k] or {}
	table.insert(bins[k], index)
end

type Stat = {
	samples: number,
	drawn: number,
	drawnMax: number,
	waved: number,
	wavedMax: number,
	built: number,
	builtMax: number,
	frame: number, -- fish moved + waves set + paths looked at, a frame (now)
	frameMax: number,
	oldFrame: number, -- the same by the 2026-10-24 rules
	oldFrameMax: number,
	moves: number, -- fish moved a frame (now)
	waves: number, -- waves set a frame (now)
	oldWaves: number,
	near100: number,
	near150: number,
	busiest: string,
}
local stats: { [string]: Stat } = {}
local SPACING = 50
for gx = -1500, 1500, SPACING do
	for gz = -1500, 1500, SPACING do
		local r = math.sqrt(gx * gx + gz * gz)
		if r < 110 or r > 1480 then
			continue
		end
		local biome = biomeAt(gx, gz)
		if
			biome == "AbyssalTrench"
			and Seafloor.inTrench(gx, gz, 0)
			and Seafloor.y(gx, gz) < World.deep.floorY - 200
		then
			biome = "TrenchCanyon" -- down in the canyon, apart from its rim
		end
		local heights = HEIGHTS[biome]
		if heights == nil then
			continue
		end
		local floor = Seafloor.y(gx, gz)
		for _, h in heights do
			local cx, cy, cz = gx, floor + h, gz
			local drawn, waved, nearest = 0, 0, math.huge
			local moves, waves, oldWaves = 0, 0, 0
			local builtSchools: { [number]: boolean } = {}
			local bx, bz = math.floor(cx / BIN), math.floor(cz / BIN)
			local span = math.ceil(600 / BIN)
			for ix = bx - span, bx + span do
				for iz = bz - span, bz + span do
					local list = bins[key(ix, iz)]
					if list == nil then
						continue
					end
					for _, index in list do
						local dx, dy, dz = px[index] - cx, py[index] - cy, pz[index] - cz
						local d = math.sqrt(dx * dx + dy * dy + dz * dz)
						nearest = math.min(nearest, d)
						local fish = Schools.fish[index]
						local school = Schools.list[fish.school]
						if newModel then
							local sd = (school.center - Vector3.new(cx, cy, cz)).Magnitude
							if sd <= school.reach then
								builtSchools[fish.school] = true
							end
							if d <= fish.range then
								drawn += 1
								if d <= fish.wave then
									waved += 1
								end
								local speed = math.max(ppace[index], 1)
								local cadence = if d > MOVE_NEAR
									then math.clamp(math.floor(d * MOVE_STEP * FPS / speed), 1, MOVE_MAX)
									else 1
								moves += 1 / cadence
								if d < math.min(fish.wave, WAVE_DISTANCE) then
									local want = if d < WAVE_NEAR then 1 elseif d < WAVE_HALF then 2 else 3
									waves += 1 / (cadence * math.ceil(want / cadence))
									oldWaves += if d < WAVE_HALF then 1 else 0.5
								end
							end
						else
							local sd = (school.center - Vector3.new(cx, cy, cz)).Magnitude
							if sd <= OLD_DRAW + school.radius then
								drawn += 1
								if d < OLD_WAVE then
									waved += 1
								end
							end
						end
					end
				end
			end
			local built = 0
			if newModel then
				for schoolIndex in builtSchools do
					built += Schools.list[schoolIndex].count
				end
			else
				built = Schools.COUNT
			end
			local frame = moves + waves + math.max(built - drawn, 0) / CULL_EVERY
			local oldFrame = drawn + oldWaves + math.max(built - drawn, 0) / OLD_CULL_EVERY
			local stat = stats[biome]
			if stat == nil then
				stat = {
					samples = 0,
					drawn = 0,
					drawnMax = 0,
					waved = 0,
					wavedMax = 0,
					built = 0,
					builtMax = 0,
					frame = 0,
					frameMax = 0,
					oldFrame = 0,
					oldFrameMax = 0,
					moves = 0,
					waves = 0,
					oldWaves = 0,
					near100 = 0,
					near150 = 0,
					busiest = "",
				}
				stats[biome] = stat
			end
			stat.samples += 1
			stat.drawn += drawn
			stat.waved += waved
			stat.built += built
			if drawn > stat.drawnMax then
				stat.drawnMax = drawn
				stat.busiest = string.format("(%d, %d, %d)", cx, cy, cz)
			end
			stat.wavedMax = math.max(stat.wavedMax, waved)
			stat.builtMax = math.max(stat.builtMax, built)
			stat.frame += frame
			stat.frameMax = math.max(stat.frameMax, frame)
			stat.oldFrame += oldFrame
			stat.oldFrameMax = math.max(stat.oldFrameMax, oldFrame)
			stat.moves += moves
			stat.waves += waves
			stat.oldWaves += oldWaves
			if nearest <= 100 then
				stat.near100 += 1
			end
			if nearest <= 150 then
				stat.near150 += 1
			end
		end
	end
end

print(
	string.format(
		"%d schools, %d fish (+ %d tide schools, %d fish); draw model: %s",
		#Schools.list - tideSchools,
		Schools.COUNT - tideFish,
		tideSchools,
		tideFish,
		if newModel then "per-fish ranges" else "520 studs a school, all built"
	)
)
print(
	"biome               schools  fish | prey within 100 / 150 | moved avg/max | waved avg/max | built avg/max | busiest spot"
)
for _, biome in ORDER do
	local stat = stats[biome]
	if stat == nil then
		continue
	end
	local n = stat.samples
	print(
		string.format(
			"%-19s %7d %5d | %5.0f%% / %5.0f%%        | %5.0f / %4d   | %5.0f / %4d   | %5.0f / %4d   | %s",
			biome,
			schoolsIn[biome] or 0,
			fishIn[biome] or 0,
			100 * stat.near100 / n,
			100 * stat.near150 / n,
			stat.drawn / n,
			stat.drawnMax,
			stat.waved / n,
			stat.wavedMax,
			stat.built / n,
			stat.builtMax,
			stat.busiest
		)
	)
end
if newModel then
	print(
		"a frame (60 fps):    moves now (was) | waves now (was) | moves + waves + path looks now (was), avg / max"
	)
	for _, biome in ORDER do
		local stat = stats[biome]
		if stat == nil then
			continue
		end
		local n = stat.samples
		print(
			string.format(
				"%-19s %5.0f (%4.0f)    | %4.0f (%4.0f)     | %5.0f / %4.0f  (%5.0f / %4.0f)",
				biome,
				stat.moves / n,
				stat.drawn / n,
				stat.waves / n,
				stat.oldWaves / n,
				stat.frame / n,
				stat.frameMax,
				stat.oldFrame / n,
				stat.oldFrameMax
			)
		)
	end
end
if newModel then
	-- Each prey's pace against its configured speed (median and most over its fish)
	local paces: { [string]: { number } } = {}
	for index, pace in ppace do
		local prey = Schools.fish[index].prey
		paces[prey] = paces[prey] or {}
		table.insert(paces[prey], pace)
	end
	local names = {}
	for prey in paces do
		table.insert(names, prey)
	end
	table.sort(names)
	local parts = {}
	for _, prey in names do
		local list = paces[prey]
		table.sort(list)
		table.insert(
			parts,
			string.format(
				"%s %.0f (speed %g, most %.0f)",
				prey,
				list[math.ceil(#list / 2)],
				Config.Prey.byId[prey].speed,
				list[#list]
			)
		)
	end
	print("pace, studs/s on screen: " .. table.concat(parts, ", "))
end
for _, biome in ORDER do
	local mix = mixIn[biome]
	if mix then
		local parts = {}
		for prey, count in mix do
			table.insert(parts, `{prey} {count}`)
		end
		table.sort(parts)
		print(`  {biome}: {table.concat(parts, ", ")}`)
	end
end
