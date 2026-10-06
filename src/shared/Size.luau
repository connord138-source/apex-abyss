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

function Size.length(mass: number): number
	return size.lengthScale * math.max(mass, 1e-4) ^ (1 / 3)
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
	return prey < eater * hunt.swallowRatio
end

-- Swimming, scaled by length: bigger fish are faster in studs but slower to turn.
function Size.topSpeed(length: number): number
	return swim.baseSpeed * length ^ swim.speedExponent
end

function Size.turnRate(length: number): number
	return swim.turnRate * length ^ swim.turnExponent
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
