--!strict
-- Critically damped springs (implicit Euler, stable at any frame rate). Everything
-- that moves in the camera and HUD goes through these, so nothing snaps.
local Spring = {}

-- Steps a number spring toward `target`; `omega` is its stiffness in radians/s
-- (higher = tighter). Returns the new position and velocity.
function Spring.number(x: number, v: number, target: number, omega: number, dt: number): (number, number)
	local f = 1 + 2 * dt * omega
	local oo = omega * omega
	local hoo = dt * oo
	local hhoo = dt * hoo
	local detInv = 1 / (f + hhoo)
	return (f * x + dt * v + hhoo * target) * detInv, (v + hoo * (target - x)) * detInv
end

function Spring.vector(x: Vector3, v: Vector3, target: Vector3, omega: number, dt: number): (Vector3, Vector3)
	local f = 1 + 2 * dt * omega
	local oo = omega * omega
	local hoo = dt * oo
	local hhoo = dt * hoo
	local detInv = 1 / (f + hhoo)
	return (x * f + v * dt + target * hhoo) * detInv, (v + (target - x) * hoo) * detInv
end

-- Frame-rate independent exponential approach: the share of the gap to close this
-- frame at `rate` per second.
function Spring.alpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

return Spring
