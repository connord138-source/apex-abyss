--!strict
-- Time helpers shared by server and client.
local RunService = game:GetService("RunService")

local isStudio = RunService:IsStudio()

-- Subtracted from the server clock before it goes into trig paths (Schools), so
-- the numbers stay small and smooth.
local EPOCH = 1_790_000_000

local Timing = {}

function Timing.isStudio(): boolean
	return isStudio
end

-- Unix time, for saves.
function Timing.now(): number
	return os.time()
end

-- The shared clock: the same value on the server and every client, to the
-- millisecond, so anything computed from it (school paths) agrees everywhere.
function Timing.clock(): number
	return workspace:GetServerTimeNow() - EPOCH
end

return Timing
