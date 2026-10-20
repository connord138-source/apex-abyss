--!strict
-- Size math shared by the server (eats, banking) and clients (scaling, camera,
-- handling). Mass is in kg; length is the body length in studs.
local Config = require(script.Parent.Config)

local size = Config.Tuning.size
local swim = Config.Tuning.swim
local hunt = Config.Tuning.hunt
local growth = Config.Tuning.growth

local LOG_GROWTH = math.log(size.levelGrowth)

local Size = {}

-- A fish's drawn length, linear in level (owner, 2026-10-20: "the first jump is a
-- foot in length second and third jumps were 0.1 foot in increase. That needs to be
-- adjusted so that the growth is linear"): every level adds the same STEP studs, from
-- 2 at the start mass to `lengthTop` at the last level, then a soft cap at
-- `lengthCap` (a full Haul at LV 100 stays under it, and a max-size fish still fits
-- its den). Below the start mass (the small prey) it's the raw curve, which meets the
-- line at 2 studs. Size ratios and swim speed use the raw length (Size.raw).
local START_LENGTH = size.lengthScale * size.startMass ^ (1 / 3)
local STEP = (size.lengthTop - START_LENGTH) / (size.maxLevel - 1)
local CAP = size.lengthCap
local SOFT = CAP - 0.4 -- where the soft cap starts
local SPAN = CAP - SOFT

function Size.length(mass: number): number
	if mass <= size.startMass then
		return size.lengthScale * math.max(mass, 1e-4) ^ (1 / 3)
	end
	local line = START_LENGTH + STEP * math.log(mass / size.startMass) / LOG_GROWTH
	if line <= SOFT then
		return line
	end
	return SOFT + SPAN * (1 - math.exp(-(line - SOFT) / SPAN))
end

-- The raw length (lengthScale × mass^⅓) a drawn length stands for: what size ratios
-- (swallowing, bites, aggro, predators) and swim speed are measured in, so the drawn
-- curve changes none of the balance. Lengths at or past the cap read as a very big
-- fish.
function Size.raw(length: number): number
	if length <= START_LENGTH then
		return length
	end
	local line = length
	if length > SOFT then
		local t = math.min((length - SOFT) / SPAN, 0.999)
		line = SOFT - SPAN * math.log(1 - t)
	end
	local mass = size.startMass * math.exp((line - START_LENGTH) / STEP * LOG_GROWTH)
	return size.lengthScale * mass ^ (1 / 3)
end

-- The mass a dive shows: banked mass plus the Haul. Food stops going on at the Haul's
-- cap (Size.haulCap, HuntService `addHaul`), so this is at most a full Haul past the
-- banked mass, plus any reward carried on top (a boss's Haul, a treasure's).
function Size.liveMass(banked: number, haul: number): number
	return banked + math.max(haul, 0)
end

-- A smooth level: exactly `level` at the mass where that level starts, `level` + 0.5
-- halfway (by the log of the mass) to the next (for the Haul's curves; Size.level is
-- the whole level shown)
function Size.levelAt(mass: number): number
	return math.clamp(math.log(math.max(mass, size.startMass)) / LOG_GROWTH + 1, 1, size.maxLevel)
end

-- A curve of { level, value } points (Config/Tuning `growth`) read at `level`: a
-- straight line between points (in log space when `log`, for values that span
-- decades), the end values past either end
local function curve(points: { { number } }, level: number, log: boolean): number
	local first, last = points[1], points[#points]
	if level <= first[1] then
		return first[2]
	elseif level >= last[1] then
		return last[2]
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if level <= b[1] then
			local t = (level - a[1]) / math.max(b[1] - a[1], 1e-9)
			if log then
				return math.exp(math.log(a[2]) + (math.log(b[2]) - math.log(a[2])) * t)
			end
			return a[2] + (b[2] - a[2]) * t
		end
	end
	return last[2]
end

-- The Haul (Config/Tuning `growth`), all by the fish's banked mass: how many levels a
-- full one banks...
function Size.haulLevels(banked: number): number
	return curve(growth.cap, Size.levelAt(banked), false)
end

-- ...that in kg of growth: everyday food stops going on here (MAX SIZE)...
function Size.haulCap(banked: number): number
	return math.max(banked, size.startMass) * (size.levelGrowth ^ Size.haulLevels(banked) - 1)
end

-- ...the kg of food a full one holds (what the Haul card shows)...
function Size.haulFood(banked: number): number
	return curve(growth.food, Size.levelAt(banked), true)
end

-- ...so the growth each kg of food gives (the Haul holds growth: Size.liveMass)...
function Size.haulRate(banked: number): number
	return Size.haulCap(banked) / math.max(Size.haulFood(banked), 1e-6)
end

-- ...and a Haul's growth shown as food (kg): the Haul card, pops and toasts
function Size.haulShown(banked: number, haul: number): number
	return haul / math.max(Size.haulRate(banked), 1e-9)
end

-- Food in a biome whose top level (Config/Biomes `maxLevel`) the fish's `level` is
-- past counts for less (Config/Tuning `growth` `overLevel`)
function Size.overLevel(level: number, maxLevel: number): number
	local over = growth.overLevel
	return math.clamp(1 - over.slope * (level - maxLevel), over.floor, 1)
end

-- Whether the Haul is full (MAX SIZE: swim home and bank it)
function Size.isMaxed(banked: number, haul: number): boolean
	return haul >= Size.haulCap(banked) * 0.9995
end

function Size.level(mass: number): number
	local level = math.floor(math.log(math.max(mass, size.startMass)) / LOG_GROWTH) + 1
	return math.clamp(level, 1, size.maxLevel)
end

-- Banked mass at which `level` starts.
function Size.massForLevel(level: number): number
	return size.levelGrowth ^ (level - 1)
end

function Size.stage(level: number): string
	local name = size.stages[1].name
	for _, stage in size.stages do
		if level >= stage.level then
			name = stage.name
		end
	end
	return name
end

-- Whether a fish of length `eater` can swallow one of length `prey` whole.
function Size.canSwallow(eater: number, prey: number): boolean
	return Size.raw(prey) < Size.raw(eater) * hunt.swallowRatio
end

-- How many times bigger `a` is than `b`, in raw lengths
function Size.ratio(a: number, b: number): number
	return Size.raw(a) / math.max(Size.raw(b), 1e-4)
end

-- Swimming, scaled by length: bigger fish are faster in studs but slower to turn.
-- Speed grows as raw length ^ `speedExponent` up to `speedKnee`, then eases toward
-- `speedCap` along a power curve that meets it with the same value and slope, so
-- every size is still faster than any smaller one but a LV 100 fish is no longer
-- four times a new one (owner, 2026-10-18: a LV 100 'Cuda crossed the map in seconds).
local SPEED_KNEE = swim.speedKnee
local SPEED_AT_KNEE = swim.baseSpeed * SPEED_KNEE ^ swim.speedExponent
local SPEED_SPAN = swim.speedCap - SPEED_AT_KNEE
local SPEED_EASE = swim.speedExponent * SPEED_AT_KNEE / SPEED_SPAN

function Size.topSpeed(length: number): number
	local raw = Size.raw(length)
	if raw <= SPEED_KNEE then
		return swim.baseSpeed * raw ^ swim.speedExponent
	end
	return swim.speedCap - SPEED_SPAN * (raw / SPEED_KNEE) ^ -SPEED_EASE
end

function Size.turnRate(length: number): number
	return swim.turnRate * Size.raw(length) ^ swim.turnExponent
end

-- The physics collider: a ball about as thick as the body.
function Size.colliderDiameter(length: number): number
	return length * 0.4
end

-- The mouth, relative to the fish's center (forward is -Z).
function Size.mouthOffset(length: number): Vector3
	return Vector3.new(0, 0, -length * hunt.mouthOffset)
end

function Size.reach(length: number): number
	return length * hunt.reach
end

return Size
