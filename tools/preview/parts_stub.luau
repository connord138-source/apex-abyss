-- Roblox instance shims on top of roblox_stub.luau and cave_stub.luau, enough to
-- run the hub's part builders (DenDoor.luau, Plaza.luau, TreasureWheel.luau) in
-- the luau CLI and dump every part, light, particle emitter and SurfaceGui they
-- make. tools/preview/render_hub.py draws the dump over the voxelized cavern.
-- (Ported from Hatch & Snatch's tools/preview/world_stub.luau.)
local Col = {}
Col.__index = function(c, k)
	if k == "Lerp" then
		return function(a, b, t)
			return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
		end
	end
	if k == "ToHSV" then
		return function(me)
			local r, g, b = me.R, me.G, me.B
			local max, min = math.max(r, g, b), math.min(r, g, b)
			local h, s, v = 0, 0, max
			local d = max - min
			if max > 0 then
				s = d / max
			end
			if d > 0 then
				if max == r then
					h = ((g - b) / d) % 6
				elseif max == g then
					h = (b - r) / d + 2
				else
					h = (r - g) / d + 4
				end
				h = h / 6
			end
			return h, s, v
		end
	end
	return nil
end
Color3 = {
	new = function(r, g, b)
		return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Col)
	end,
	fromRGB = function(r, g, b)
		return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, Col)
	end,
	fromHSV = function(h, s, v)
		local i = math.floor(h * 6)
		local f = h * 6 - i
		local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
		local r, g, b
		i = i % 6
		if i == 0 then
			r, g, b = v, t, p
		elseif i == 1 then
			r, g, b = q, v, p
		elseif i == 2 then
			r, g, b = p, v, t
		elseif i == 3 then
			r, g, b = p, q, v
		elseif i == 4 then
			r, g, b = t, p, v
		else
			r, g, b = v, p, q
		end
		return setmetatable({ R = r, G = g, B = b }, Col)
	end,
}
Vector3.one = Vector3.new(1, 1, 1)
local VMeta = getmetatable(Vector3.new(0, 0, 0))
local oldIndex = VMeta.__index
VMeta.__index = function(v, k)
	if k == "Abs" then
		return function(me)
			return Vector3.new(math.abs(me.X), math.abs(me.Y), math.abs(me.Z))
		end
	end
	if k == "Max" then
		return function(a, b)
			return Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
		end
	end
	if k == "Min" then
		return function(a, b)
			return Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
		end
	end
	return oldIndex(v, k)
end
local CMeta = getmetatable(CFrame.identity)
local oldCIndex = CMeta.__index
CMeta.__index = function(c, k)
	if k == "Lerp" then
		return function(a, b, t)
			-- position only (enough for the previews)
			return CFrame.new(a.p:Lerp(b.p, t)) * a.Rotation
		end
	end
	if k == "ToWorldSpace" then
		return function(self, o)
			return self * o
		end
	end
	if k == "VectorToObjectSpace" then
		return function(self, v)
			return self.Rotation:Inverse() * v
		end
	end
	if k == "XVector" then
		return c.r.x
	end
	if k == "YVector" then
		return c.r.y
	end
	if k == "ZVector" then
		return c.r.z
	end
	return oldCIndex(c, k)
end
CMeta.__add = function(a, v)
	return CFrame.new(a.p + v) * a.Rotation
end
CMeta.__sub = function(a, v)
	return CFrame.new(a.p - v) * a.Rotation
end
CFrame.fromAxisAngle = function(axis, angle)
	local u = axis.Unit
	local c, s = math.cos(angle), math.sin(angle)
	local t = 1 - c
	local x, y, z = u.X, u.Y, u.Z
	return CFrame.fromMatrix(
		Vector3.new(0, 0, 0),
		Vector3.new(t * x * x + c, t * x * y + s * z, t * x * z - s * y),
		Vector3.new(t * x * y - s * z, t * y * y + c, t * y * z + s * x),
		Vector3.new(t * x * z + s * y, t * y * z - s * x, t * z * z + c)
	)
end

ColorSequenceKeypoint = {
	new = function(t, c)
		return { Time = t, Value = c }
	end,
}
NumberRange = {
	new = function(a, b)
		return { Min = a, Max = b or a }
	end,
}
NumberSequenceKeypoint = {
	new = function(t, v)
		return { Time = t, Value = v }
	end,
}
NumberSequence = {
	new = function(a, b)
		if type(a) == "number" then
			return { Keypoints = { { Time = 0, Value = a }, { Time = 1, Value = b or a } } }
		end
		return { Keypoints = a }
	end,
}
ColorSequence = {
	new = function(a, b)
		if type(a) == "table" and a.R ~= nil then
			return { Keypoints = { { Time = 0, Value = a }, { Time = 1, Value = b or a } } }
		end
		return { Keypoints = a }
	end,
}
Vector2 = {
	new = function(x, y)
		return { X = x or 0, Y = y or 0 }
	end,
}
UDim = {
	new = function(s, o)
		return { Scale = s or 0, Offset = o or 0 }
	end,
}
UDim2 = {
	new = function(xs, xo, ys, yo)
		return { XS = xs or 0, XO = xo or 0, YS = ys or 0, YO = yo or 0 }
	end,
	fromScale = function(xs, ys)
		return { XS = xs or 0, XO = 0, YS = ys or 0, YO = 0 }
	end,
	fromOffset = function(xo, yo)
		return { XS = 0, XO = xo or 0, YS = 0, YO = yo or 0 }
	end,
}
Font = {
	new = function(family, weight, style)
		return { Family = family, Weight = weight, Style = style }
	end,
}

local DEFAULTS = {
	Part = {
		Shape = Enum.PartType.Block,
		Size = Vector3.new(4, 1, 2),
		Color = Color3.fromRGB(163, 162, 165),
		Material = Enum.Material.Plastic,
		Transparency = 0,
		Reflectance = 0,
		CanCollide = true,
		CanQuery = true,
		CastShadow = true,
	},
	WedgePart = {
		Size = Vector3.new(4, 1, 2),
		Color = Color3.fromRGB(163, 162, 165),
		Material = Enum.Material.Plastic,
		Transparency = 0,
		Reflectance = 0,
		CanCollide = true,
		CanQuery = true,
		CastShadow = true,
	},
	CornerWedgePart = {
		Size = Vector3.new(4, 1, 2),
		Color = Color3.fromRGB(163, 162, 165),
		Material = Enum.Material.Plastic,
		Transparency = 0,
		Reflectance = 0,
		CanCollide = true,
		CanQuery = true,
		CastShadow = true,
	},
	TextLabel = {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		TextColor3 = Color3.new(0, 0, 0),
		TextTransparency = 0,
		TextSize = 14,
		Size = UDim2.new(0, 100, 0, 50),
		Position = UDim2.new(0, 0, 0, 0),
		AnchorPoint = Vector2.new(0, 0),
		Visible = true,
	},
	Frame = {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(0, 100, 0, 100),
		Position = UDim2.new(0, 0, 0, 0),
		AnchorPoint = Vector2.new(0, 0),
		Visible = true,
	},
	SurfaceGui = { Face = Enum.NormalId.Front, PixelsPerStud = 50, LightInfluence = 1, Brightness = 1 },
	UIStroke = { Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 0 },
}

local Inst = {}
local PARTS = { Part = true, WedgePart = true, CornerWedgePart = true, MeshPart = true }
local function new(class)
	local props = {}
	for k, v in DEFAULTS[class] or {} do
		props[k] = v
	end
	local self = setmetatable(
		{ ClassName = class, IsPart = PARTS[class] or false, _props = props, _children = {}, _attrs = {} },
		Inst
	)
	if self.IsPart and props.CFrame == nil then
		props.CFrame = CFrame.identity
	end
	return self
end
local function clone(me)
	local copy = new(rawget(me, "ClassName"))
	for k, v in rawget(me, "_props") do
		rawget(copy, "_props")[k] = v
	end
	for k, v in rawget(me, "_attrs") do
		rawget(copy, "_attrs")[k] = v
	end
	for _, c in rawget(me, "_children") do
		local cc = clone(c)
		cc.Parent = copy
	end
	return copy
end
Inst.__index = function(self, k)
	local raw = rawget(self, "_props")[k]
	if raw ~= nil then
		return raw
	end
	if k == "Parent" then
		return rawget(self, "_parent")
	end
	if k == "Position" then
		local cf = rawget(self, "_props").CFrame
		return cf and cf.p
	end
	if k == "Name" then
		return rawget(self, "ClassName")
	end
	if k == "FindFirstChild" then
		return function(me, name)
			for _, c in rawget(me, "_children") do
				if c.Name == name then
					return c
				end
			end
			return nil
		end
	end
	if k == "WaitForChild" then
		return function(me, name)
			for _, c in rawget(me, "_children") do
				if c.Name == name then
					return c
				end
			end
			return nil
		end
	end
	if k == "FindFirstChildWhichIsA" or k == "FindFirstChildOfClass" then
		return function(me, class)
			for _, c in rawget(me, "_children") do
				if c.ClassName == class or (class == "BasePart" and c.IsPart) then
					return c
				end
			end
			return nil
		end
	end
	if k == "GetChildren" then
		return function(me)
			return table.clone(rawget(me, "_children"))
		end
	end
	if k == "IsA" then
		return function(me, class)
			return me.ClassName == class
				or (class == "BasePart" and me.IsPart == true)
				or (class == "GuiObject" and (me.ClassName == "TextLabel" or me.ClassName == "Frame"))
				or (class == "Light" and (me.ClassName == "PointLight" or me.ClassName == "SpotLight"))
		end
	end
	if k == "Destroy" then
		return function(me)
			me.Parent = nil
		end
	end
	if k == "ClearAllChildren" then
		return function(me)
			for _, c in table.clone(rawget(me, "_children")) do
				c.Parent = nil
			end
		end
	end
	if k == "Clone" then
		return clone
	end
	if k == "SetAttribute" then
		return function(me, a, v)
			rawget(me, "_attrs")[a] = v
		end
	end
	if k == "GetAttribute" then
		return function(me, a)
			return rawget(me, "_attrs")[a]
		end
	end
	if k == "GetDescendants" then
		return function(me)
			local out = {}
			local function walk(n)
				for _, c in rawget(n, "_children") do
					table.insert(out, c)
					walk(c)
				end
			end
			walk(me)
			return out
		end
	end
	if k == "GetPivot" then
		return function(me)
			return rawget(me, "_props").CFrame or CFrame.identity
		end
	end
	return nil
end
Inst.__newindex = function(self, k, v)
	if k == "Parent" then
		local old = rawget(self, "_parent")
		if old then
			local kids = rawget(old, "_children")
			for i, c in kids do
				if c == self then
					table.remove(kids, i)
					break
				end
			end
		end
		rawset(self, "_parent", v)
		if v then
			table.insert(rawget(v, "_children"), self)
		end
		return
	end
	if k == "Position" and rawget(self, "IsPart") then
		local cf = rawget(self, "_props").CFrame or CFrame.identity
		rawget(self, "_props").CFrame = CFrame.new(v) * cf.Rotation
		return
	end
	rawget(self, "_props")[k] = v
end
Instance = { new = new }

local tags = {}
local collection = {
	AddTag = function(_, inst, tag)
		tags[inst] = tags[inst] or {}
		tags[inst][tag] = true
	end,
	RemoveTag = function() end,
	HasTag = function(_, inst, tag)
		return tags[inst] ~= nil and tags[inst][tag] == true
	end,
}
game = {
	GetService = function(_, name)
		if name == "CollectionService" then
			return collection
		end
		return SERVICES[name] or new(name)
	end,
}
workspace = new("Workspace")
-- Terrain: a repaint (Terrain:ReplaceMaterial, BlueDress's pale sand) prints a T line,
-- T|replace|min|max|from|to, which render_hub.py applies to the voxels before meshing
do
	local terrain = new("Terrain")
	terrain.Name = "Terrain"
	terrain.ReplaceMaterial = function(_, region, _resolution, from, to)
		local a, b = region.Min, region.Max
		print(
			string.format("T|replace|%.1f,%.1f,%.1f|%.1f,%.1f,%.1f|%s|%s", a.X, a.Y, a.Z, b.X, b.Y, b.Z, from.Name, to.Name)
		)
	end
	terrain.Parent = workspace
end
Region3 = {
	new = function(low, high)
		local region = { Min = low, Max = high }
		region.ExpandToGrid = function(me, grid)
			local function snap(v, f)
				return Vector3.new(f(v.X / grid) * grid, f(v.Y / grid) * grid, f(v.Z / grid) * grid)
			end
			return Region3.new(snap(me.Min, math.floor), snap(me.Max, math.ceil))
		end
		return region
	end,
}
-- (no scheduler: what a builder defers, like DenDoor seating a nameplate on the rock
-- by raycast, is skipped here)
task = {
	spawn = function() end,
	delay = function() end,
	wait = function()
		return 0
	end,
}

-- Props stub: records what would be dressed with an imported model (render_hub.py
-- draws the GLB when it's in assets/tripo/, else the placeholder part stays)
PROP_PLACEMENTS = {}
PropsStub = {
	dress = function(part, name, options)
		local opts = options or {}
		local record = {
			name = name,
			cframe = opts.cframe or part.CFrame,
			size = opts.size or part.Size,
			tint = opts.tint,
		}
		table.insert(PROP_PLACEMENTS, record)
		if USE_PROPS then
			if not opts.keepVisible then
				part.Transparency = 1
			end
			-- (the model the builder gets back: its Glow / GlowTint attributes, which
			-- the builders set as they set the real model's EmissiveStrength and
			-- EmissiveTint, ride the R line so the preview glows as the game does)
			local model = new("Model")
			record.model = model
			return model
		end
		return nil
	end,
	spawn = function(name, cframe, height)
		table.insert(PROP_PLACEMENTS, {
			name = name,
			cframe = cframe * CFrame.new(0, height / 2, 0),
			size = Vector3.new(height, height, height),
			height = true,
		})
		return if USE_PROPS then new("Model") else nil
	end,
	template = function()
		return nil
	end,
	tint = function() end,
}

local function v3(v)
	return string.format("%.3f,%.3f,%.3f", v.X, v.Y, v.Z)
end
local function frame(cf)
	return string.format("%s|%s|%s|%s", v3(cf.p), v3(cf.r.x), v3(cf.r.y), v3(cf.r.z))
end
local function col(c)
	return string.format("%.3f,%.3f,%.3f", c.R, c.G, c.B)
end
local function udim2(u)
	return string.format("%.4f,%.2f,%.4f,%.2f", u.XS, u.XO, u.YS, u.YO)
end
local function esc(s)
	return (string.gsub(tostring(s), "[|\n]", " "))
end

-- A SurfaceGui's labels and frames, in tree order: U|depth|kind|...
local function dumpGui(gui, part)
	local canvasW, canvasH
	local face = gui.Face and gui.Face.Name or "Front"
	local s = part.Size
	local fw, fh
	if face == "Front" or face == "Back" then
		fw, fh = s.X, s.Y
	elseif face == "Left" or face == "Right" then
		fw, fh = s.Z, s.Y
	else
		fw, fh = s.X, s.Z
	end
	if gui.SizingMode and gui.SizingMode.Name == "PixelsPerStud" then
		local pps = gui.PixelsPerStud or 50
		canvasW, canvasH = fw * pps, fh * pps
	elseif gui.CanvasSize then
		canvasW, canvasH = gui.CanvasSize.X, gui.CanvasSize.Y
	else
		canvasW, canvasH = 800, 600
	end
	print(
		string.format(
			"G|%s|%s|%s|%.1f,%.1f|%.2f|%s",
			esc(part.Name),
			frame(part.CFrame),
			v3(part.Size),
			canvasW,
			canvasH,
			gui.LightInfluence or 1,
			face
		)
	)
	local function walk(node, depth)
		for _, c in rawget(node, "_children") do
			if c.ClassName == "TextLabel" or c.ClassName == "Frame" or c.ClassName == "TextButton" then
				local stroke, limit, corner = nil, nil, nil
				for _, g in rawget(c, "_children") do
					if g.ClassName == "UIStroke" then
						stroke = g
					elseif g.ClassName == "UITextSizeConstraint" then
						limit = g
					elseif g.ClassName == "UICorner" then
						corner = g
					end
				end
				local weight = "Bold"
				if c.FontFace and c.FontFace.Weight then
					weight = c.FontFace.Weight.Name
				elseif c.Font then
					weight = c.Font.Name
				end
				print(
					string.format(
						"U|%d|%s|%s|%s|%s|%s|%.3f|%s|%.3f|%s|%s|%s|%.1f|%s|%.1f|%.3f|%s|%s|%s|%s",
						depth,
						c.ClassName,
						udim2(c.Position),
						udim2(c.Size),
						string.format("%.2f,%.2f", c.AnchorPoint.X, c.AnchorPoint.Y),
						col(c.BackgroundColor3),
						c.BackgroundTransparency,
						col(c.TextColor3 or Color3.new(0, 0, 0)),
						c.TextTransparency or 0,
						esc(c.Text or ""),
						if c.TextScaled then "1" else "0",
						weight,
						c.TextSize or 14,
						if stroke then col(stroke.Color) else "",
						if stroke then stroke.Thickness else 0,
						if stroke then stroke.Transparency or 0 else 0,
						if limit then tostring(limit.MaxTextSize) else "",
						if corner and corner.CornerRadius then string.format(
							"%.3f,%.1f",
							corner.CornerRadius.Scale,
							corner.CornerRadius.Offset
						) else "",
						c.TextXAlignment and c.TextXAlignment.Name or "Center",
						c.Visible == false and "0" or "1"
					)
				)
				walk(c, depth + 1)
			end
		end
	end
	walk(gui, 0)
end

-- One line per part: P|name|shape|size|frame|color|material|transparency|light
function dumpParts(root)
	for _, d in root:GetDescendants() do
		if d.IsPart then
			local shape = if d.ClassName == "WedgePart"
				then "Wedge"
				elseif d.ClassName == "CornerWedgePart" then "CornerWedge"
				else (d.Shape and d.Shape.Name or "Block")
			local s = d.Size
			for _, child in rawget(d, "_children") do
				if child.ClassName == "SpecialMesh" and child.MeshType then
					local mt = child.MeshType.Name
					if mt == "Sphere" then
						shape = "Ellipsoid" -- a sphere mesh fills the part's box
					elseif mt == "Cylinder" then
						shape = "Cylinder"
					elseif mt == "Wedge" then
						shape = "Wedge"
					end
					s = s * (child.Scale or Vector3.new(1, 1, 1))
				end
			end
			if (d.Transparency or 0) < 1 then
				print(
					string.format(
						"P|%s|%s|%s|%s|%s|%s|%.2f|%.2f",
						esc(d.Name),
						shape,
						v3(s),
						frame(d.CFrame),
						col(d.Color),
						d.Material and d.Material.Name or "Plastic",
						d.Transparency or 0,
						d.Reflectance or 0
					)
				)
			end
			for _, child in rawget(d, "_children") do
				if child.ClassName == "PointLight" or child.ClassName == "SpotLight" then
					local c = child.Color or Color3.new(1, 1, 1)
					print(
						string.format(
							"L|%s|%s|%.2f|%.2f",
							v3(d.CFrame.p),
							col(c),
							child.Range or 12,
							child.Brightness or 1
						)
					)
				elseif child.ClassName == "ParticleEmitter" then
					local keys = child.Color and child.Color.Keypoints
					local c = (keys and keys[1] and keys[1].Value) or Color3.new(1, 1, 1)
					local size = 0.4
					local sk = child.Size and child.Size.Keypoints
					if type(sk) == "table" then
						for _, k in sk do
							if type(k) == "table" and k.Value then
								size = math.max(size, k.Value)
							end
						end
					end
					local acc = child.Acceleration or Vector3.new(0, 0, 0)
					-- (its transparency at birth: render_hub.py draws see-through
					-- emitters fainter)
					local fade = 0.35
					local tk = child.Transparency and child.Transparency.Keypoints
					if type(tk) == "table" and type(tk[1]) == "table" and tk[1].Value then
						fade = tk[1].Value
					end
					print(
						string.format(
							"E|%s|%s|%s|%s|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f",
							esc(child.Name),
							frame(d.CFrame),
							v3(d.Size),
							col(c),
							child.Rate or 5,
							child.Lifetime and child.Lifetime.Max or 2,
							child.Speed and child.Speed.Max or 1,
							acc.Y,
							size,
							fade
						)
					)
				elseif child.ClassName == "SurfaceGui" then
					dumpGui(child, d)
				elseif child.ClassName == "Beam" then
					-- B|from|to|width0|width1|color|transparency at 0, 0.6 and 1 (a light
					-- shaft: LightEmission 1, so it adds)
					local a0, a1 = child.Attachment0, child.Attachment1
					local keys = child.Transparency and child.Transparency.Keypoints
					local function at(t)
						if type(keys) ~= "table" then
							return 0
						end
						local before, after = keys[1], keys[#keys]
						for _, k in keys do
							if k.Time <= t then
								before = k
							end
							if k.Time >= t and after.Time > k.Time then
								after = k
							end
						end
						if after.Time <= before.Time then
							return before.Value
						end
						local u = (t - before.Time) / (after.Time - before.Time)
						return before.Value + (after.Value - before.Value) * u
					end
					local ck = child.Color and child.Color.Keypoints
					local c = (ck and ck[1] and ck[1].Value) or Color3.new(1, 1, 1)
					if a0 and a1 and a0.WorldPosition and a1.WorldPosition then
						print(
							string.format(
								"B|%s|%s|%.2f|%.2f|%s|%.3f|%.3f|%.3f",
								v3(a0.WorldPosition),
								v3(a1.WorldPosition),
								child.Width0 or 1,
								child.Width1 or 1,
								col(c),
								at(0),
								at(0.6),
								at(1)
							)
						)
					end
				end
			end
		end
	end
	for _, r in PROP_PLACEMENTS do
		local cf = r.cframe
		local tint = r.tint
		local glow = r.model and r.model:GetAttribute("Glow")
		local glowTint = r.model and r.model:GetAttribute("GlowTint")
		print(
			string.format(
				"R|%s|%s|%s|%s|%s|%s|%s",
				r.name,
				if r.height then "height" else "box",
				frame(cf),
				v3(r.size),
				if tint then col(tint) else "",
				if type(glow) == "number" then string.format("%.2f", glow) else "",
				if glowTint then col(glowTint) else ""
			)
		)
	end
end

-- Counts of what the builders made (for the report): C|total|collide|query|shadow
function countParts(root)
	local total, collide, query, shadow = 0, 0, 0, 0
	for _, d in root:GetDescendants() do
		if d.IsPart then
			total += 1
			if d.CanCollide ~= false then
				collide += 1
			end
			if d.CanQuery ~= false then
				query += 1
			end
			if d.CastShadow ~= false then
				shadow += 1
			end
		end
	end
	return total, collide, query, shadow
end
return true
