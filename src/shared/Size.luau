--!strict
-- Size math shared by the server (eats, banking) and clients (scaling, camera,
-- handling). Mass is in kg; length is the body length in studs.
local Config = require(script.Parent.Config)

local size = Config.Tuning.size
local swim = Config.Tuning.swim
local hunt = Config.Tuning.hunt

local MASS_CAP = size.haulLengthCap ^ 3 -- length cap → mass cap
local LOG_GROWTH = math.log(size.levelGrowth)

local Size = {}

-- A fish's drawn length: its raw length (lengthScale × mass^(1/3)) up to the knee,
-- then easing toward the cap, so a max-size fish still fits its den (Config/Tuning
-- `lengthKnee`, `lengthCap`). Smooth at the knee (slope 1 either side).
local KNEE, CAP = size.lengthKnee, size.lengthCap

function Size.length(mass: number): number
	local raw = size.lengthScale * math.max(mass, 1e-4) ^ (1 / 3)
	if raw <= KNEE then
		return raw
	end
	local span = CAP - KNEE
	return KNEE + span * (1 - math.exp(-(raw - KNEE) / span))
end

-- The raw length a drawn length stands for: what size ratios (swallowing, bites,
-- aggro, predators) and swim speed are measured in, so easing the bodies changed
-- none of the balance. Lengths at or past the cap read as a very big fish.
function Size.raw(length: number): number
	if length <= KNEE then
		return length
	end
	local span = CAP - KNEE
	local t = math.min((length - KNEE) / span, 0.999)
	return KNEE - span * math.log(1 - t)
end

-- The mass a dive actually shows: banked mass plus the Haul, up to the cap.
function Size.liveMass(banked: number, haul: number): number
	return math.min(banked + haul, banked * MASS_CAP)
end

function Size.isMaxed(banked: number, haul: number): boolean
	return banked + haul >= banked * MASS_CAP
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
