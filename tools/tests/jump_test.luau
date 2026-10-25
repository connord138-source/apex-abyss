-- How far a held prey fish jumps on screen when it's moved again (TEST=jump_test
-- run_density.sh): SchoolController moves a far fish every few frames (MOVE_STEP at
-- its measured `pace`), and the PC measures the step as 1080p pixels (PJ checks: each
-- drawn fish 60-200 studs from the camera, still and swimming at 20 studs/s; the jump
-- after one or more held frames). This plays SchoolController's rules frame by frame
-- at 60 fps from busy camera spots in each biome and prints the median, 95th
-- percentile and share over 4 px of those jumps, and the moves a frame, for the
-- current rule and the variants in VARIANTS (keep `current` in step with
-- SchoolController).
local Config = require("./Config")
local Seafloor = require("./Seafloor")
local Schools = require("./Schools")

local World = Config.World
local FPS = 60
local DT = 1 / FPS
local T0 = 137.25
local PX_PER_RAD = 540 / math.tan(math.rad(35)) -- 1080p at the camera's 70° field of view
local MOVE_MAX, MOVE_NEAR, PACE_GAP = 4, 40, 0.25
local BAND_NEAR, BAND_FAR = 60, 200
local SECONDS = 2 -- still, then swimming as long

type Variant = { name: string, turn: number, settle: number, step: number }
local VARIANTS: { Variant } = {
	{ name = "2026-10-26 rule (turn 0.5, settle 2, step 0.003)", turn = 0.5, settle = 2, step = 0.003 },
	{ name = "current (turn 0.25, settle 4, step 0.0042)", turn = 0.25, settle = 4, step = 0.0042 },
	{ name = "turn 0.25, settle 4, step 0.0045", turn = 0.25, settle = 4, step = 0.0045 },
}

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
}
local HEIGHT: { [string]: number } = {
	KelpShallows = 15,
	ShipwreckGraveyard = 18,
	CoralReef = 18,
	OpenBlue = 150,
	SunkenRuins = 35,
	HydrothermalVents = 35,
	AbyssalTrench = 60,
}
local SPOTS = 3 -- the busiest camera spots of each biome

-- Every fish's position at T0, to find busy spots
local BIN = 100
local bins: { [number]: { number } } = {}
local function key(bx: number, bz: number): number
	return (bx + 100) * 1000 + (bz + 100)
end
local p0: { [number]: Vector3 } = {}
for index = 1, Schools.COUNT do
	local fish = Schools.fish[index]
	if Schools.list[fish.school].tide then
		continue
	end
	local p = Schools.position(index, T0)
	p0[index] = p
	local k = key(math.floor(p.X / BIN), math.floor(p.Z / BIN))
	bins[k] = bins[k] or {}
	table.insert(bins[k], index)
end
local function near(at: Vector3, radius: number): { number }
	local out = {}
	local span = math.ceil(radius / BIN)
	local bx, bz = math.floor(at.X / BIN), math.floor(at.Z / BIN)
	for ix = bx - span, bx + span do
		for iz = bz - span, bz + span do
			for _, index in bins[key(ix, iz)] or {} do
				if (p0[index] - at).Magnitude <= radius then
					table.insert(out, index)
				end
			end
		end
	end
	return out
end

-- Camera spots: per biome, the SPOTS with the most fish 60-200 studs off (a 100-stud grid)
type Spot = { biome: string, at: Vector3, fish: { number } }
local spots: { Spot } = {}
for _, biome in ORDER do
	local found: { { at: Vector3, fish: { number }, count: number } } = {}
	for gx = -1500, 1500, 100 do
		for gz = -1500, 1500, 100 do
			local r = math.sqrt(gx * gx + gz * gz)
			if r < 150 or r > 1480 or biomeAt(gx, gz) ~= biome then
				continue
			end
			local at = Vector3.new(gx, Seafloor.y(gx, gz) + HEIGHT[biome], gz)
			local list = near(at, BAND_FAR + 40)
			local count = 0
			for _, index in list do
				local d = (p0[index] - at).Magnitude
				if d >= BAND_NEAR and d <= BAND_FAR and d <= Schools.fish[index].range then
					count += 1
				end
			end
			table.insert(found, { at = at, fish = list, count = count })
		end
	end
	table.sort(found, function(a, b)
		return a.count > b.count
	end)
	for i = 1, math.min(SPOTS, #found) do
		table.insert(spots, { biome = biome, at = found[i].at, fish = found[i].fish })
	end
end

local function percentile(list: { number }, p: number): number
	if #list == 0 then
		return 0
	end
	return list[math.clamp(math.ceil(#list * p), 1, #list)]
end

type Result = { jumps: { number }, moves: number, frames: number, slow: { [string]: { number } } }

-- Plays one spot under a variant: still for SECONDS, then swimming at 20 studs/s
local function play(spot: Spot, variant: Variant, result: Result)
	local swimDir = Vector3.new(1, 0, 0.3).Unit
	type State = {
		pace: number,
		at: Vector3?,
		facing: Vector3?,
		stepAt: number,
		holdUntil: number,
		shown: Vector3?,
	}
	local states: { [number]: State } = {}
	for _, index in spot.fish do
		local fish = Schools.fish[index]
		states[index] = {
			pace = Config.Prey.byId[fish.prey].speed,
			at = nil,
			facing = nil,
			stepAt = -1,
			holdUntil = 0,
			shown = nil,
		}
	end
	local frames = SECONDS * 2 * FPS
	for frame = 1, frames do
		local t = T0 + frame * DT
		local swimming = frame > SECONDS * FPS
		local camera = spot.at
			+ (if swimming then swimDir * 20 * (frame - SECONDS * FPS) * DT else Vector3.zero)
		local moves = 0
		for _, index in spot.fish do
			local state = states[index]
			if state.holdUntil > frame then
				continue
			end
			local fish = Schools.fish[index]
			local cf = Schools.fishFrame(index, Schools.schoolFrame(fish.school, t), t)
			local far = (cf.Position - camera).Magnitude
			if far > fish.range then
				state.at = nil -- (out of range: not drawn, its pace isn't measured across the gap)
				state.shown = nil
				continue
			end
			moves += 1
			local since = t - state.stepAt
			local last, facing = state.at, state.facing
			if last and facing and since > 0 and since < PACE_GAP then
				local turned = math.acos(math.clamp(facing:Dot(cf.LookVector), -1, 1))
				local rate = ((cf.Position - last).Magnitude + turned * fish.length * variant.turn) / since
				state.pace = if rate > state.pace
					then rate
					else state.pace + (rate - state.pace) * math.min(1, since * variant.settle)
			end
			-- The jump seen from the camera, if it was held one or more frames
			local shown = state.shown
			if shown and since > DT * 1.5 and far >= BAND_NEAR and far <= BAND_FAR then
				local a, b = (shown - camera).Unit, (cf.Position - camera).Unit
				table.insert(result.jumps, math.acos(math.clamp(a:Dot(b), -1, 1)) * PX_PER_RAD)
			end
			state.at, state.facing, state.stepAt, state.shown = cf.Position, cf.LookVector, t, cf.Position
			local hold = 1
			if far > MOVE_NEAR then
				hold =
					math.clamp(math.floor(far * variant.step / (math.max(state.pace, 1) * DT)), 1, MOVE_MAX)
			end
			state.holdUntil = frame + hold
			if far >= 100 and far <= 150 then
				local list = result.slow[fish.prey]
				if list == nil then
					list = {}
					result.slow[fish.prey] = list
				end
				table.insert(list, hold)
			end
		end
		result.moves += moves
		result.frames += 1
	end
end

print(
	string.format(
		"%d camera spots (%d a biome), %d s still + %d s swimming at 20 studs/s, 60 fps",
		#spots,
		SPOTS,
		SECONDS,
		SECONDS
	)
)
for _, variant in VARIANTS do
	print(`\n{variant.name}`)
	print("biome               jumps 60-200 studs: median  95th   over 4 px  over 3 px | moves a frame")
	for _, biome in ORDER do
		local result: Result = { jumps = {}, moves = 0, frames = 0, slow = {} }
		for _, spot in spots do
			if spot.biome == biome then
				play(spot, variant, result)
			end
		end
		table.sort(result.jumps)
		local over4, over3 = 0, 0
		for _, jump in result.jumps do
			if jump > 4 then
				over4 += 1
			end
			if jump > 3 then
				over3 += 1
			end
		end
		local n = math.max(#result.jumps, 1)
		print(
			string.format(
				"%-19s %6d jumps:           %4.2f px  %4.2f   %5.1f%%     %5.1f%%   | %5.0f",
				biome,
				#result.jumps,
				percentile(result.jumps, 0.5),
				percentile(result.jumps, 0.95),
				100 * over4 / n,
				100 * over3 / n,
				result.moves / math.max(result.frames, 1) * #spots / (SPOTS * #ORDER)
			)
		)
		if biome == "CoralReef" or biome == "SunkenRuins" then
			local parts = {}
			for _, prey in { "Butterflyfish", "BlueTang", "Opaleye", "Lionfish", "Parrotfish", "Wrasse" } do
				local list = result.slow[prey]
				if list then
					local sum = 0
					for _, hold in list do
						sum += hold
					end
					table.insert(parts, string.format("%s %.1f", prey, sum / #list))
				end
			end
			if #parts > 0 then
				print("    frames a move at 100-150 studs: " .. table.concat(parts, ", "))
			end
		end
	end
end
