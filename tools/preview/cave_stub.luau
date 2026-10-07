-- Roblox shims on top of roblox_stub.luau (Vector3, CFrame), enough to run
-- src/server/Cave.luau in the luau CLI and dump its fill ops as JSON lines.
local function enumGroup(name)
	return setmetatable({}, {
		__index = function(t, k)
			local item = { Name = k, EnumType = name }
			rawset(t, k, item)
			return item
		end,
	})
end
Enum = setmetatable({}, {
	__index = function(t, k)
		local group = enumGroup(k)
		rawset(t, k, group)
		return group
	end,
})
Vector3.xAxis = Vector3.new(1, 0, 0)
Vector3.yAxis = Vector3.new(0, 1, 0)
Vector3.zAxis = Vector3.new(0, 0, 1)
CFrame.lookAt = function(pos, target, up)
	up = up or Vector3.new(0, 1, 0)
	local back = (pos - target).Unit
	local right = up:Cross(back).Unit
	local realUp = back:Cross(right)
	return CFrame.fromMatrix(pos, right, realUp, back)
end
Color3 = {
	new = function(r, g, b)
		return { R = r, G = g, B = b }
	end,
	fromRGB = function(r, g, b)
		return { R = r / 255, G = g / 255, B = b / 255 }
	end,
}
-- Random: the same LCG as Hatch & Snatch's previews (layout jitter only)
Random = {
	new = function(seed)
		local state = math.floor(seed or 1) % 2147483647
		if state <= 0 then
			state = state + 2147483646
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
		}
	end,
}
-- `game:GetService("ReplicatedStorage").Shared.X` resolves to the module loaded by run_cave.sh
game = {
	GetService = function(_, name)
		return SERVICES[name]
	end,
}

function dumpOps(ops)
	local function v(x)
		return string.format("[%.3f,%.3f,%.3f]", x.X, x.Y, x.Z)
	end
	for _, op in ops do
		local cf = op.cframe
		local axes = if cf
			then string.format(
				"%s,%s,%s",
				v(cf.RightVector),
				v(cf.UpVector),
				v(cf.LookVector)
			)
			else "null,null,null"
		print(
			string.format(
				'{"kind":"%s","material":"%s","center":%s,"radius":%s,"height":%s,"size":%s,"axes":[%s]}',
				op.kind,
				op.material.Name,
				v(op.center),
				tostring(op.radius or "null"),
				tostring(op.height or "null"),
				if op.size then v(op.size) else "null",
				axes
			)
		)
	end
end
-- The parts that stay parts, for the renderer's stand-ins: cave_layout.json
function dumpLayout(Layout, hub)
	local function v(x)
		return string.format("[%.2f,%.2f,%.2f]", x.X, x.Y, x.Z)
	end
	local dens = {}
	for den = 1, Layout.DEN_COUNT do
		local frame = Layout.denFrame(den)
		local lamp = frame.Position + Vector3.new(0, hub.denHeight / 2 - 3, 0)
		table.insert(dens, string.format('{"pool":%s,"lamp":%s}', v(Layout.poolPosition(den)), v(lamp)))
	end
	local sconces = {}
	for segment = 1, hub.segments do
		if Layout.segmentKind(segment) == "wall" then
			local angle = Layout.segmentAngle(segment)
			table.insert(sconces, v(hub.center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (hub.radius - 1) + Vector3.new(0, 18, 0)))
		end
	end
	print(string.format('{"dens":[%s],"sconces":[%s]}', table.concat(dens, ","), table.concat(sconces, ",")))
end
return true
