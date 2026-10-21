-- Roblox shims for running server logic in the plain luau CLI (run_predators.sh,
-- run_schools.sh): Vector3, CFrame, Random, Color3, Enum and a `game` whose
-- RunService.Heartbeat hands its callback to the test. One module, so every file
-- shares the same metatables (luau sandboxes each module's globals).
local rbx = {}

local V = {}
local function vec(x: number?, y: number?, z: number?)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V)
end
V.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m < 1e-12 then
			return vec(0, 0, 0)
		end
		return vec(v.X / m, v.Y / m, v.Z / m)
	elseif k == "Cross" then
		return function(a, b)
			return vec(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
		end
	elseif k == "Dot" then
		return function(a, b)
			return a.X * b.X + a.Y * b.Y + a.Z * b.Z
		end
	elseif k == "Lerp" then
		return function(a, b, t)
			return vec(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
		end
	end
	return nil
end
V.__add = function(a, b)
	return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V.__sub = function(a, b)
	return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V.__unm = function(a)
	return vec(-a.X, -a.Y, -a.Z)
end
V.__mul = function(a, b)
	if type(a) == "number" then
		return vec(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return vec(a.X * b, a.Y * b, a.Z * b)
	end
	return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a, b)
	return vec(a.X / b, a.Y / b, a.Z / b)
end
V.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V.__type = "Vector3"
V.__tostring = function(v)
	return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
end
local Vector3 = {
	new = vec,
	zero = vec(0, 0, 0),
	one = vec(1, 1, 1),
	xAxis = vec(1, 0, 0),
	yAxis = vec(0, 1, 0),
	zAxis = vec(0, 0, 1),
}
rbx.Vector3 = Vector3

-- CFrame: rotation columns (right, up, back) and a position
local C = {}
local function cf(p, r)
	return setmetatable({ p = p, r = r }, C)
end
local function rotv(r, v)
	return r.x * v.X + r.y * v.Y + r.z * v.Z
end
local function inverse(self)
	local r = self.r
	local rt = {
		x = vec(r.x.X, r.y.X, r.z.X),
		y = vec(r.x.Y, r.y.Y, r.z.Y),
		z = vec(r.x.Z, r.y.Z, r.z.Z),
	}
	return cf(-rotv(rt, self.p), rt)
end
C.__index = function(c, k)
	if k == "Position" then
		return c.p
	elseif k == "X" then
		return c.p.X
	elseif k == "Y" then
		return c.p.Y
	elseif k == "Z" then
		return c.p.Z
	elseif k == "RightVector" then
		return c.r.x
	elseif k == "UpVector" then
		return c.r.y
	elseif k == "LookVector" then
		return -c.r.z
	elseif k == "Rotation" then
		return cf(vec(0, 0, 0), c.r)
	elseif k == "Inverse" then
		return inverse
	elseif k == "VectorToWorldSpace" then
		return function(self, v)
			return rotv(self.r, v)
		end
	elseif k == "VectorToObjectSpace" then
		return function(self, v)
			return rotv(inverse(self).r, v)
		end
	elseif k == "PointToWorldSpace" then
		return function(self, v)
			return self.p + rotv(self.r, v)
		end
	elseif k == "PointToObjectSpace" then
		return function(self, v)
			local inv = inverse(self)
			return inv.p + rotv(inv.r, v)
		end
	elseif k == "ToObjectSpace" then
		return function(self, o)
			return inverse(self) * o
		end
	end
	return nil
end
C.__mul = function(a, b)
	if getmetatable(b) == V then
		return a.p + rotv(a.r, b)
	end
	return cf(a.p + rotv(a.r, b.p), { x = rotv(a.r, b.r.x), y = rotv(a.r, b.r.y), z = rotv(a.r, b.r.z) })
end
C.__add = function(a, v)
	return cf(a.p + v, a.r)
end
C.__type = "CFrame"
local I = { x = vec(1, 0, 0), y = vec(0, 1, 0), z = vec(0, 0, 1) }
local CFrame = {}
CFrame.identity = cf(vec(0, 0, 0), I)
CFrame.new = function(a, b, c)
	if a == nil then
		return CFrame.identity
	elseif type(a) == "number" then
		return cf(vec(a, b, c), I)
	end
	return cf(a, I)
end
local function rx(t)
	local c, s = math.cos(t), math.sin(t)
	return cf(vec(0, 0, 0), { x = vec(1, 0, 0), y = vec(0, c, s), z = vec(0, -s, c) })
end
local function ry(t)
	local c, s = math.cos(t), math.sin(t)
	return cf(vec(0, 0, 0), { x = vec(c, 0, -s), y = vec(0, 1, 0), z = vec(s, 0, c) })
end
local function rz(t)
	local c, s = math.cos(t), math.sin(t)
	return cf(vec(0, 0, 0), { x = vec(c, s, 0), y = vec(-s, c, 0), z = vec(0, 0, 1) })
end
CFrame.Angles = function(x, y, z)
	return rx(x) * ry(y) * rz(z)
end
CFrame.fromMatrix = function(p, right, up, back)
	return cf(p, { x = right, y = up, z = back or right:Cross(up) })
end
CFrame.lookAt = function(pos, target, up)
	up = up or vec(0, 1, 0)
	local back = (pos - target).Unit
	local right = up:Cross(back)
	if right.Magnitude < 1e-6 then
		right = vec(1, 0, 0)
	end
	right = right.Unit
	return CFrame.fromMatrix(pos, right, back:Cross(right), back)
end
CFrame.fromAxisAngle = function(axis, angle)
	local k = axis.Unit
	local c, s = math.cos(angle), math.sin(angle)
	local function rot(v)
		return v * c + k:Cross(v) * s + k * (k:Dot(v) * (1 - c))
	end
	return cf(vec(0, 0, 0), { x = rot(vec(1, 0, 0)), y = rot(vec(0, 1, 0)), z = rot(vec(0, 0, 1)) })
end
rbx.CFrame = CFrame

-- Random: a Park-Miller LCG (not Roblox's sequence: layouts differ from the game's,
-- the logic doesn't)
rbx.Random = {
	new = function(seed: number?)
		local state = math.floor(seed or 1) % 2147483647
		if state <= 0 then
			state += 2147483646
		end
		local function step()
			state = (state * 48271) % 2147483647
			return state / 2147483647
		end
		return {
			NextNumber = function(_, a, b)
				a = a or 0
				b = b or 1
				return a + (b - a) * step()
			end,
			NextInteger = function(_, a, b)
				return a + math.floor(step() * (b - a + 1))
			end,
			NextUnitVector = function(_)
				local z = step() * 2 - 1
				local t = step() * 2 * math.pi
				local r = math.sqrt(1 - z * z)
				return vec(r * math.cos(t), r * math.sin(t), z)
			end,
		}
	end,
}

local stub = setmetatable({}, {
	__index = function()
		return 0
	end,
})
rbx.Color3 = {
	new = function()
		return stub
	end,
	fromRGB = function()
		return stub
	end,
	fromHSV = function()
		return stub
	end,
}
rbx.Enum = setmetatable({}, {
	__index = function()
		return stub
	end,
})

-- An empty Workspace: no World folder (no kelp, no dressing)
rbx.workspace = {
	FindFirstChild = function()
		return nil
	end,
}

-- Every Heartbeat callback a service connected, run in order by `rbx.heartbeat`
rbx.heartbeats = {} :: { (number) -> () }
rbx.heartbeat = nil :: ((number) -> ())?
rbx.game = {
	GetService = function(_, name: string)
		if name == "RunService" then
			return {
				Heartbeat = {
					Connect = function(_, f)
						table.insert(rbx.heartbeats, f)
						rbx.heartbeat = function(dt: number)
							for _, callback in rbx.heartbeats do
								callback(dt)
							end
						end
						return {}
					end,
				},
				IsServer = function()
					return true
				end,
				IsClient = function()
					return false
				end,
			}
		end
		if name == "Players" then
			-- (the sim streams to no one: PredatorService only sends each player what's near)
			return {
				GetPlayers = function()
					return {}
				end,
			}
		end
		return {}
	end,
}

return rbx
