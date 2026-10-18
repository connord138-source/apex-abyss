-- How full of fish the sea is, and what that costs a client (run_density.sh): the
-- prey schools (Shared/Schools) per biome, how often a swimming fish has prey in
-- sight, and how many prey fish a client moves, waves and keeps built at once, from
-- a grid of camera spots over every biome at two swimming heights each. Reads the
-- draw ranges Schools gives each fish (`range`, `wave`, a school's `reach`) the way
-- SchoolController uses them; an older Schools without them is measured the old
-- way (every fish of a school within 520 studs moved, waves within 160, every fish
-- built at start).
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
local px, py, pz, pschool = {}, {}, {}, {}
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
		if biome == "AbyssalTrench" and Seafloor.inTrench(gx, gz, 0) and Seafloor.y(gx, gz) < World.deep.floorY - 200 then
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
