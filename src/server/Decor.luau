--!strict
-- Part-built dressing shared by the hub's builders (DenDoor.luau, Plaza.luau): plain
-- anchored parts in materials the toon overrides leave alone (owner, 2026-10-17:
-- the wheel and the stalls looked "fuzzy, cheap" once Config/Materials re-skinned
-- Wood, Slate, Marble, ... game-wide: a toon map tiles every 8 to 16 studs, so on a
-- small part it's one big blurry patch). SmoothPlastic with bold colour blocking,
-- brass trims and Neon only where something glows; nothing takes camera rays
-- unless asked (CanQuery false) and nothing fires Touched.
local Decor = {}

-- The palette the hub's builders share (the Treasure Wheel's lacquer and brass)
Decor.BRASS = Color3.fromRGB(214, 160, 70)
Decor.BRASS_LIGHT = Color3.fromRGB(246, 204, 118)
Decor.BRASS_DARK = Color3.fromRGB(150, 104, 44)
Decor.IRON = Color3.fromRGB(46, 52, 60)
Decor.LACQUER = Color3.fromRGB(20, 88, 102)
Decor.TEXT = Color3.fromRGB(255, 244, 222)
Decor.TEXT_GOLD = Color3.fromRGB(255, 208, 104)
Decor.TEXT_STROKE = Color3.fromRGB(8, 34, 42)
Decor.GLASS_LIT = Color3.fromRGB(242, 162, 72) -- Neon: a deeper amber reads as glowing glass, not white
Decor.GLASS_DARK = Color3.fromRGB(78, 74, 66)
Decor.LAMP_LIGHT = Color3.fromRGB(255, 186, 112)
Decor.KELP = { Color3.fromRGB(64, 150, 74), Color3.fromRGB(96, 178, 70), Color3.fromRGB(46, 128, 84) }
Decor.CORALS = {
	Color3.fromRGB(255, 118, 132),
	Color3.fromRGB(255, 160, 80),
	Color3.fromRGB(176, 110, 236),
	Color3.fromRGB(255, 214, 92),
	Color3.fromRGB(96, 214, 196),
}

-- An anchored SmoothPlastic part with `props` set on it
function Decor.part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CanTouch = false
	p.CanQuery = false
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end
local part = Decor.part

-- A rounded stone or blob: an ellipsoid filling `size` (a sphere mesh on a block)
function Decor.pebble(parent: Instance, name: string, cframe: CFrame, size: Vector3, color: Color3): Part
	local p = part(parent, {
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = color,
		CanCollide = false,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- A disc facing along `cframe`'s look (a cylinder's axis is its X)
function Decor.disc(parent: Instance, name: string, cframe: CFrame, radius: number, thickness: number): Part
	return part(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, radius * 2, radius * 2),
		CFrame = cframe * CFrame.Angles(0, math.rad(90), 0),
		CanCollide = false,
		CastShadow = false,
	})
end

-- An upright cylinder standing on `base` (`base`'s up is its axis)
function Decor.upright(parent: Instance, name: string, base: CFrame, height: number, radius: number): Part
	return part(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		CanCollide = false,
	})
end

-- A flat triangle a-b-c, `thickness` thick, as two right-angled wedges that meet on
-- the altitude from its longest edge (as TreasureWheel's slices)
function Decor.triangle(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	thickness: number,
	props: { [string]: any }
): { WedgePart }
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local made = {}
	for k = 1, 2 do
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.TopSurface = Enum.SurfaceType.Smooth
		w.BottomSurface = Enum.SurfaceType.Smooth
		w.Material = Enum.Material.SmoothPlastic
		w.CanTouch = false
		w.CanQuery = false
		w.CanCollide = false
		w.CastShadow = false
		for key, value in props do
			(w :: any)[key] = value
		end
		if k == 1 then
			w.Size = Vector3.new(thickness, height, math.abs(ab:Dot(back)))
			w.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
		else
			w.Size = Vector3.new(thickness, height, math.abs(ac:Dot(back)))
			w.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
		end
		w.Parent = parent
		table.insert(made, w)
	end
	return made
end

export type Lantern = { glass: BasePart, light: PointLight }

-- A brass lantern on an iron arm; `at` is the glass's middle, the arm runs 2 studs
-- from over it toward `armToward` (a local X sign: the wall or the post it hangs
-- from; 0 for none). `glow` colours its glass and light (default warm).
function Decor.lantern(
	parent: Instance,
	at: CFrame,
	armToward: number,
	lit: boolean,
	range: number?,
	glow: Color3?
): Lantern
	if armToward ~= 0 then
		part(parent, {
			Name = "LanternArm",
			Size = Vector3.new(2.1, 0.32, 0.32),
			CFrame = at * CFrame.new(armToward * 1.05, 1.75, 0),
			Color = Decor.IRON,
			CanCollide = false,
			CastShadow = false,
		})
	end
	part(parent, {
		Name = "LanternCap",
		Size = Vector3.new(1.75, 0.45, 1.75),
		CFrame = at * CFrame.new(0, 1.05, 0),
		Color = Decor.BRASS,
		CanCollide = false,
	})
	Decor.pebble(
		parent,
		"LanternRoof",
		at * CFrame.new(0, 1.45, 0),
		Vector3.new(1.35, 0.8, 1.35),
		Decor.BRASS_DARK
	)
	local glass = part(parent, {
		Name = "LanternGlass",
		Size = Vector3.new(1.2, 1.6, 1.2),
		CFrame = at,
		Color = if lit then (glow or Decor.GLASS_LIT) else Decor.GLASS_DARK,
		Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		Transparency = if lit then 0.08 else 0,
		CanCollide = false,
		CastShadow = false,
	})
	part(parent, {
		Name = "LanternBase",
		Size = Vector3.new(1.55, 0.4, 1.55),
		CFrame = at * CFrame.new(0, -0.98, 0),
		Color = Decor.BRASS,
		CanCollide = false,
	})
	local light = Instance.new("PointLight")
	light.Color = glow or Decor.LAMP_LIGHT
	light.Range = range or 16
	light.Brightness = 0.85
	light.Enabled = lit
	light.Parent = glass
	return { glass = glass, light = light }
end

-- Lights a lantern, or puts it out
function Decor.light(lantern: Lantern, lit: boolean)
	lantern.glass.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
	lantern.glass.Color = if lit then Decor.GLASS_LIT else Decor.GLASS_DARK
	lantern.glass.Transparency = if lit then 0.08 else 0
	lantern.light.Enabled = lit
end

export type Plaque = {
	board: BasePart,
	trims: { BasePart },
	title: TextLabel,
	sub: TextLabel?,
	gui: SurfaceGui,
}

-- A nameplate: a lacquered board in a brass frame with corner bosses, facing along
-- `at`'s look, and its lettering on a SurfaceGui (unlit, so it reads across the
-- plaza). `sub` adds a second, smaller line between two short brass rules. Each line
-- is scaled to fit its box on one line: a 20-character name shrinks, never cut off.
function Decor.plaque(parent: Instance, at: CFrame, size: Vector2, color: Color3, sub: boolean): Plaque
	local board = part(parent, {
		Name = "Plaque",
		Size = Vector3.new(size.X, size.Y, 0.8),
		CFrame = at,
		Color = color,
		CanCollide = false,
	})
	local trims: { BasePart } = {}
	local bar = 0.55
	for _, y in { -1, 1 } do
		table.insert(
			trims,
			part(parent, {
				Name = "PlaqueTrim",
				Size = Vector3.new(size.X + bar, bar, 0.5),
				CFrame = at * CFrame.new(0, y * (size.Y / 2), -0.3),
				Color = Decor.BRASS,
				CanCollide = false,
			})
		)
	end
	for _, x in { -1, 1 } do
		table.insert(
			trims,
			part(parent, {
				Name = "PlaqueTrim",
				Size = Vector3.new(bar, size.Y + bar, 0.5),
				CFrame = at * CFrame.new(x * (size.X / 2), 0, -0.3),
				Color = Decor.BRASS,
				CanCollide = false,
			})
		)
	end
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			table.insert(
				trims,
				part(parent, {
					Name = "PlaqueBoss",
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * 0.95,
					CFrame = at * CFrame.new(x * (size.X / 2), y * (size.Y / 2), -0.45),
					Color = Decor.BRASS_LIGHT,
					CanCollide = false,
					CastShadow = false,
				})
			)
		end
	end
	-- The lettering sits on a thin face just in front of the board, inside the frame
	local face = part(parent, {
		Name = "PlaqueFace",
		Size = Vector3.new(size.X - 0.9, size.Y - 0.9, 0.05),
		CFrame = at * CFrame.new(0, 0, -0.45),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Brightness = 1.15
	gui.Parent = face
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = if sub then UDim2.fromScale(0.035, 0.05) else UDim2.fromScale(0.04, 0.12)
	title.Size = if sub then UDim2.fromScale(0.93, 0.56) else UDim2.fromScale(0.92, 0.76)
	title.Font = Enum.Font.FredokaOne
	-- (TextWrapped stays on: turning it off after TextScaled turns TextScaled off, which
	-- drew every name 8 px high, PC 2026-10-17 HB1; Decor.oneLine keeps a line whole)
	title.TextScaled = true
	title.TextColor3 = Decor.TEXT
	title.Text = ""
	title.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Decor.TEXT_STROKE
	stroke.Thickness = 4
	stroke.Parent = title
	local subLabel: TextLabel? = nil
	if sub then
		for _, x in { 0.07, 0.71 } do
			local rule = Instance.new("Frame")
			rule.Name = "Rule"
			rule.BorderSizePixel = 0
			rule.BackgroundColor3 = Decor.BRASS_LIGHT
			rule.AnchorPoint = Vector2.new(0, 0.5)
			rule.Position = UDim2.fromScale(x, 0.8)
			rule.Size = UDim2.new(0.22, 0, 0, 5)
			rule.Parent = gui
		end
		local line = Instance.new("TextLabel")
		line.Name = "Sub"
		line.BackgroundTransparency = 1
		line.Position = UDim2.fromScale(0.3, 0.65)
		line.Size = UDim2.fromScale(0.4, 0.3)
		line.Font = Enum.Font.GothamBlack
		line.TextScaled = true
		line.TextColor3 = Decor.TEXT_GOLD
		line.Text = ""
		line.Parent = gui
		local lineStroke = Instance.new("UIStroke")
		lineStroke.Color = Decor.TEXT_STROKE
		lineStroke.Thickness = 2.5
		lineStroke.Parent = line
		subLabel = line
	end
	return { board = board, trims = trims, title = title, sub = subLabel, gui = gui }
end

-- Text for one line of a plaque: upper case, and spaces made non-breaking so a
-- scaled label shrinks the line instead of wrapping it
function Decor.oneLine(text: string): string
	return (string.gsub(string.upper(text), " ", "\u{00A0}"))
end

-- Kelp: `count` leaf-shaped blades zigzagging up from `base` (its up), each
-- `length` long, the top one paler
function Decor.kelp(parent: Instance, base: CFrame, count: number, length: number, rng: Random)
	local color = Decor.KELP[rng:NextInteger(1, #Decor.KELP)]
	local y = 0
	for k = 1, count do
		local l = length * rng:NextNumber(0.85, 1.15)
		local lean = rng:NextNumber(0.12, 0.26) * (if k % 2 == 0 then -1 else 1)
		Decor.pebble(
			parent,
			"KelpBlade",
			base * CFrame.new(0, y + l / 2, 0) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), lean),
			Vector3.new(1.9, l * 1.08, 0.3),
			if k == count then color:Lerp(Color3.fromRGB(200, 230, 90), 0.45) else color
		).CastShadow =
			false
		y += l * 0.82
	end
	-- the stalk the blades grow from
	local stalk = Decor.upright(parent, "KelpStalk", base, y, 0.16)
	stalk.Color = color:Lerp(Color3.new(0, 0, 0), 0.25)
	stalk.CastShadow = false
end

-- A clump of tube sponges standing on `base`
function Decor.sponges(parent: Instance, base: CFrame, count: number, rng: Random)
	local color = Decor.CORALS[rng:NextInteger(1, #Decor.CORALS)]
	for k = 1, count do
		local h = rng:NextNumber(1.8, 3.4)
		local r = rng:NextNumber(0.38, 0.55)
		local at = base
			* CFrame.new((k - (count + 1) / 2) * 1.05, 0, rng:NextNumber(-0.5, 0.5))
			* CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.2, 0.2))
		local tube = Decor.upright(parent, "TubeSponge", at, h, r)
		tube.Color = color
		tube.CanCollide = true -- hard corals and sponges are solid (playtest 2026-10-10)
	end
end

-- A starfish stuck flat on a surface: five arms round `at` (facing along its look)
function Decor.starfish(parent: Instance, at: CFrame, size: number, color: Color3)
	for k = 0, 4 do
		part(parent, {
			Name = "Starfish",
			Size = Vector3.new(size * 0.32, size * 0.55, 0.16),
			CFrame = at * CFrame.Angles(0, 0, k * 2 * math.pi / 5) * CFrame.new(0, size * 0.27, 0),
			Color = color,
			CanCollide = false,
			CastShadow = false,
		})
	end
	Decor.pebble(
		parent,
		"Starfish",
		at,
		Vector3.new(size * 0.36, size * 0.36, 0.22),
		color:Lerp(Color3.new(1, 1, 1), 0.2)
	)
end

return Decor
