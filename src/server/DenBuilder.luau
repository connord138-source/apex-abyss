--!strict
-- Builds a den's base in the world (Config/Dens): carves the room further back and
-- sinks the lower chamber for its level, places the furniture in its slots, lights
-- the lamps in the den's glow color, hangs the trophy wall (the biggest catch, boss
-- teeth and beaks, the title) and tints the Haul Pool. Everything is rebuilt from
-- the saved den record, so it follows its owner from server to server; when a den
-- changes hands the rock is put back first. Props are part-built until the Tripo
-- models are imported (Props.dress).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Props = require(script.Parent.Props)

local Dens = Config.Dens
local hub = Config.World.hub

local DenBuilder = {}

export type Record = {
	level: number,
	furniture: { [string]: string },
	owned: { [string]: boolean },
	glow: string,
}

export type Trophies = {
	bestPrey: string,
	bestPreyMass: number,
	teeth: number,
	beaks: number,
	title: string,
	owner: string,
}

local ROOM_BACK = 21 -- how far behind the den's middle the carved room already ends (Cave.luau)
local STONE = Color3.fromRGB(150, 138, 118)
local WOOD = Color3.fromRGB(110, 86, 60)

local folders: { [number]: Folder } = {}
-- The garden's floor found by raycast, per den and level (DenBuilder.garden): the
-- height the bed rests at, and the floor's height in a ring round the bed's edge
type GardenFloor = { level: number, y: number, ring: { number } }
local gardenFloors: { [number]: GardenFloor } = {}
local floorUnder: (CFrame, number) -> (number?, { number }) -- (below)

local function denFolder(index: number): Folder
	local existing = folders[index]
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = `DenBase{index}`
	local world = workspace:FindFirstChild("World")
	local hubFolder = world and world:FindFirstChild("Hub")
	made.Parent = hubFolder or workspace
	folders[index] = made
	return made
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local made = Instance.new("Part")
	made.Name = name
	made.Anchored = true
	made.CanCollide = false
	made.CanQuery = false
	made.CanTouch = false
	made.CastShadow = false
	made.Size = size
	made.CFrame = cframe
	made.Color = color
	made.Material = material
	made.Parent = parent
	return made
end

-- The den's frame at floor level, facing the hub
local function floorFrame(index: number): CFrame
	local frame = Layout.denFrame(index)
	return CFrame.new(Vector3.new(frame.Position.X, hub.denFloorY, frame.Position.Z)) * frame.Rotation
end

-- A spot in the den (x right, y up from the floor, z toward the hub), facing the
-- hub. The frame looks at the hub and a CFrame's own +z points behind it, so z is
-- flipped here (playtest 2026-10-07: the trophy wall stood out in the plaza and the
-- furniture sat mirrored front to back)
local function denSpot(frame: CFrame, x: number, y: number, z: number): CFrame
	return frame * CFrame.new(x, y, -z)
end

-- Rock back, then the room carved for the level
local function carve(index: number, level: number)
	local terrain = workspace.Terrain
	local frame = floorFrame(index)
	local back = -frame.LookVector
	local middle = frame.Position
	local roomY = hub.denHeight / 2
	local def = Dens.levels[level] or Dens.levels[1]
	-- Refill the whole extension and chamber zone with stone
	local extendCenter = middle + back * (ROOM_BACK + Dens.maxExtend / 2 + 2) + Vector3.new(0, roomY, 0)
	terrain:FillBlock(
		CFrame.lookAt(extendCenter, extendCenter + back),
		Vector3.new(30, hub.denHeight + 8, Dens.maxExtend + 6),
		Enum.Material.Sandstone
	)
	terrain:FillCylinder(
		CFrame.new(middle + back * 2 + Vector3.new(0, -Dens.maxPit / 2 - 1, 0)),
		Dens.maxPit + 4,
		Dens.maxPitRadius + 3,
		Enum.Material.Rock
	)
	-- The room runs back
	if def.extend > 0 then
		local center = middle + back * (ROOM_BACK + def.extend / 2 - 1) + Vector3.new(0, roomY, 0)
		terrain:FillBlock(
			CFrame.lookAt(center, center + back),
			Vector3.new(22, hub.denHeight - 2, def.extend + 2),
			Enum.Material.Air
		)
		terrain:FillBall(
			middle + back * (ROOM_BACK + def.extend - 1) + Vector3.new(0, roomY, 0),
			10,
			Enum.Material.Air
		)
		-- A floor under it
		local floorCenter = middle + back * (ROOM_BACK + def.extend / 2) + Vector3.new(0, -1.5, 0)
		terrain:FillBlock(
			CFrame.lookAt(floorCenter, floorCenter + back),
			Vector3.new(30, 3, def.extend + 12),
			Enum.Material.Sandstone
		)
	end
	-- The lower chamber
	if def.pit > 0 then
		terrain:FillCylinder(
			CFrame.new(middle + back * 2 + Vector3.new(0, -def.pit / 2 + 0.5, 0)),
			def.pit,
			def.pitRadius,
			Enum.Material.Air
		)
		terrain:FillCylinder(
			CFrame.new(middle + back * 2 + Vector3.new(0, -def.pit - 1, 0)),
			3,
			def.pitRadius + 2,
			Enum.Material.Sandstone
		)
	end
end

local function furnish(folder: Folder, index: number, record: Record)
	local frame = floorFrame(index)
	local glow = Dens.glowsById[record.glow] or Dens.glows[1]
	for slotId, itemId in record.furniture do
		local slot = Dens.slotsById[slotId]
		local item = Dens.itemsById[itemId]
		if slot == nil or item == nil then
			continue
		end
		local at = denSpot(frame, slot.offset.X, slot.offset.Y, slot.offset.Z)
			* CFrame.Angles(0, slot.facing, 0)
		local model = Instance.new("Model")
		model.Name = item.id
		model.Parent = folder
		local color = if item.glow and item.id ~= "CoralLamp" then glow.color else item.color
		local base: Part
		if item.id == "Banner" then
			local pole = part(
				model,
				"Pole",
				Vector3.new(0.4, 0.4, 5),
				at * CFrame.new(0, item.size.Y / 2, 0),
				WOOD,
				Enum.Material.Wood
			)
			base = part(
				model,
				"Cloth",
				Vector3.new(item.size.X, item.size.Y, 0.3),
				at * CFrame.new(0, 0, 0.3),
				glow.color,
				Enum.Material.Fabric
			)
			local _ = pole
		elseif item.id == "DriftwoodTable" then
			for _, x in { -2, 2 } do
				part(
					model,
					"Stone",
					Vector3.new(1.6, 2, 1.6),
					at * CFrame.new(x, 1, 0),
					STONE,
					Enum.Material.Slate
				)
			end
			base = part(
				model,
				"Top",
				Vector3.new(item.size.X, 0.7, item.size.Z),
				at * CFrame.new(0, 2.3, 0) * CFrame.Angles(0, 0, math.rad(3)),
				WOOD,
				Enum.Material.Wood
			)
		elseif item.id == "PearlPedestal" then
			part(
				model,
				"Column",
				Vector3.new(1.6, 3.2, 1.6),
				at * CFrame.new(0, 1.6, 0),
				STONE,
				Enum.Material.Slate
			)
			base = part(
				model,
				"Pearl",
				Vector3.one * 2.2,
				at * CFrame.new(0, 4.2, 0),
				Color3.fromRGB(240, 240, 246),
				Enum.Material.SmoothPlastic
			)
			base.Shape = Enum.PartType.Ball
			base.Reflectance = 0.35
		elseif item.id == "BubbleColumn" then
			base = part(
				model,
				"Vent",
				Vector3.new(2, 0.8, 2),
				at * CFrame.new(0, 0.4, 0),
				Color3.fromRGB(70, 80, 90),
				Enum.Material.Basalt
			)
			base.Shape = Enum.PartType.Cylinder
			base.CFrame = at * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90))
			local bubbles = Instance.new("ParticleEmitter")
			bubbles.Rate = 12
			bubbles.Lifetime = NumberRange.new(2.5, 4)
			bubbles.Speed = NumberRange.new(3, 5)
			bubbles.SpreadAngle = Vector2.new(6, 6)
			bubbles.Size = NumberSequence.new(0.3, 0.7)
			bubbles.Transparency = NumberSequence.new(0.2, 0.8)
			bubbles.LightEmission = 0.4
			bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 250, 255))
			bubbles.EmissionDirection = Enum.NormalId.Right
			bubbles.Parent = base
		else
			-- A stand-in block the prop replaces
			base = part(
				model,
				"Body",
				item.size,
				at * CFrame.new(0, item.size.Y / 2, 0),
				color,
				if item.glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
			)
			if item.prop then
				local dressed = Props.dress(
					base,
					item.prop,
					{ cframe = at * CFrame.new(0, item.size.Y / 2, 0), size = item.size }
				)
				if dressed then
					base.Transparency = 1
					if item.glow then
						Props.tint(dressed, color)
					end
				end
			end
		end
		if item.glow then
			local light = Instance.new("PointLight")
			light.Color = color
			light.Brightness = 1.3
			light.Range = 18
			light.Parent = base
		end
	end
end

-- Trophies on the back wall: plaques with a label, the biggest catch's model on one
local function trophyWall(folder: Folder, index: number, record: Record, trophies: Trophies)
	local frame = floorFrame(index)
	local def = Dens.levels[record.level] or Dens.levels[1]
	local backZ = -(ROOM_BACK + def.extend) + 2.5
	local glow = Dens.glowsById[record.glow] or Dens.glows[1]
	local function plaque(x: number, title: string, line: string, accent: Color3): Part
		local at = denSpot(frame, x, 11, backZ)
		local board = part(
			folder,
			"Plaque",
			Vector3.new(6, 4.4, 0.5),
			at,
			Color3.fromRGB(60, 66, 74),
			Enum.Material.Slate
		)
		local trim = part(
			folder,
			"Trim",
			Vector3.new(6.4, 0.3, 0.6),
			at * CFrame.new(0, 2.35, 0),
			accent,
			Enum.Material.Neon
		)
		local _ = trim
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = board
		local top = Instance.new("TextLabel")
		top.BackgroundTransparency = 1
		top.Size = UDim2.new(1, 0, 0.42, 0)
		top.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
		top.TextScaled = true
		top.TextColor3 = accent
		top.Text = title
		top.Parent = gui
		local bottom = Instance.new("TextLabel")
		bottom.BackgroundTransparency = 1
		bottom.Position = UDim2.new(0, 0, 0.45, 0)
		bottom.Size = UDim2.new(1, 0, 0.5, 0)
		bottom.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
		bottom.TextScaled = true
		bottom.TextWrapped = true
		bottom.TextColor3 = Color3.fromRGB(226, 240, 246)
		bottom.Text = line
		bottom.Parent = gui
		return board
	end
	-- The biggest catch, with the prey's own model mounted above the plaque
	local prey = Config.Prey.byId[trophies.bestPrey]
	local catchLine = if prey
		then `{prey.name} · {string.format("%.1f", trophies.bestPreyMass)} kg`
		else "Nothing yet"
	plaque(-7, "BIGGEST CATCH", catchLine, glow.color)
	if prey then
		local models = ReplicatedStorage:FindFirstChild("PreyModels")
		local template = models and models:FindFirstChild(prey.id)
		local mesh = if template and template:IsA("MeshPart")
			then template
			elseif template and template:IsA("Model") then template:FindFirstChildWhichIsA(
				"MeshPart",
				true
			)
			else nil
		local at = denSpot(frame, -7, 14.6, backZ + 1.5) * CFrame.Angles(0, math.rad(90), 0)
		if mesh then
			local clone = mesh:Clone()
			for _, child in clone:GetChildren() do
				if child:IsA("Bone") then
					child:Destroy()
				end
			end
			clone.Anchored = true
			clone.CanCollide = false
			clone.CanQuery = false
			clone.Size = mesh.Size * (4.5 / math.max(mesh.Size.Z, 0.01))
			clone.CFrame = at
			clone.Parent = folder
		else
			local fish =
				part(folder, "Catch", Vector3.new(1.2, 1.6, 4.5), at, prey.back, Enum.Material.SmoothPlastic)
			local shape = Instance.new("SpecialMesh")
			shape.MeshType = Enum.MeshType.Sphere
			shape.Parent = fish
		end
	end
	-- Boss trophies
	local teethLine = if trophies.teeth > 0
		then `{trophies.teeth} {if trophies.teeth == 1 then "tooth" else "teeth"} taken`
		else "No kill yet"
	plaque(0, "MEGALODON", teethLine, Color3.fromRGB(196, 255, 170))
	if trophies.teeth > 0 then
		local tooth = part(
			folder,
			"Tooth",
			Vector3.new(1.4, 3.2, 0.8),
			denSpot(frame, 0, 14.4, backZ + 1) * CFrame.Angles(0, 0, math.rad(180)),
			Color3.fromRGB(236, 232, 220),
			Enum.Material.SmoothPlastic
		)
		local wedge = Instance.new("SpecialMesh")
		wedge.MeshType = Enum.MeshType.Wedge
		wedge.Parent = tooth
	end
	local beaksLine = if trophies.beaks > 0
		then `{trophies.beaks} beak{if trophies.beaks == 1 then "" else "s"} taken`
		else "No kill yet"
	plaque(7, "GIANT SQUID", beaksLine, Color3.fromRGB(180, 110, 255))
	if trophies.beaks > 0 then
		local beak = part(
			folder,
			"Beak",
			Vector3.new(2, 2, 2),
			denSpot(frame, 7, 14.4, backZ + 1),
			Color3.fromRGB(40, 30, 36),
			Enum.Material.SmoothPlastic
		)
		local shape = Instance.new("SpecialMesh")
		shape.MeshType = Enum.MeshType.Sphere
		shape.Parent = beak
	end
	-- The title over the door, inside
	if trophies.title ~= "" then
		local sign = part(
			folder,
			"Title",
			Vector3.new(10, 1.6, 0.4),
			denSpot(frame, 0, hub.denHeight - 3, 12),
			Color3.fromRGB(60, 66, 74),
			Enum.Material.Slate
		)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = sign
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
		label.TextScaled = true
		label.TextColor3 = glow.color
		label.Text = string.upper(trophies.title)
		label.Parent = gui
	end
end

-- The Coral Garden (Config/Dens garden): a stone basin of sand on the floor under
-- the trophy plaques, its corals growing as it fills (`fill` 0..1 by coral,
-- `shellFill` by shells), sparkling and lit in the den's glow color once full.
-- Rebuilt on its own as it grows (GardenService), so the den isn't.
local CORALS = {
	Color3.fromRGB(255, 112, 130),
	Color3.fromRGB(255, 156, 84),
	Color3.fromRGB(186, 112, 236),
	Color3.fromRGB(255, 212, 96),
	Color3.fromRGB(110, 214, 200),
}
local SPRIGS = {
	Vector2.new(0, -0.6),
	Vector2.new(-1.9, -1.2),
	Vector2.new(1.9, -1.1),
	Vector2.new(-1.1, 1.0),
	Vector2.new(1.2, 1.1),
	Vector2.new(-2.7, 0.4),
	Vector2.new(2.7, 0.5),
}

function DenBuilder.garden(index: number, record: Record, fill: number, shellFill: number)
	local folder = denFolder(index)
	local old = folder:FindFirstChild("Garden")
	if old then
		old:Destroy()
	end
	local def = Dens.levels[record.level] or Dens.levels[1]
	local glow = Dens.glowsById[record.glow] or Dens.glows[1]
	local z = -(ROOM_BACK + def.extend) + Dens.garden.fromBack
	local base = denSpot(floorFrame(index), 0, 0, z)
	-- The bed sits on the Terrain floor where it really is: the voxel floor rises
	-- above the den's nominal floor (retest 2026-10-09: the bed was 0.6 studs under
	-- it in a Nook and 1.7-4.6 under in the bigger dens, out of sight)
	local nominal = base.Position.Y
	local known = gardenFloors[index]
	if known and known.level == record.level then
		base = CFrame.new(0, known.y - nominal, 0) * base
	end
	local model = Instance.new("Model")
	model.Name = "Garden"
	local bed = part(
		model,
		"Bed",
		Vector3.new(1.3, 7.6, 7.6),
		base * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)),
		STONE,
		Enum.Material.Slate
	)
	bed.Shape = Enum.PartType.Cylinder
	-- A footing under it: the bed rests on the floor's high side, and on a sloping
	-- floor the low side showed a 2-3 stud gap (retest 2026-10-09). It goes only as
	-- deep as the floor falls away, with rubble where it falls most, so it reads as
	-- rock and not a flower pot (playtest 2026-10-09)
	local depth = 4
	local ring: { number } = if known and known.level == record.level then known.ring else {}
	if #ring > 0 then
		local low = math.huge
		for _, y in ring do
			low = math.min(low, y)
		end
		depth = math.clamp(base.Position.Y - low + 0.9, 0.8, 6)
	end
	local footing = part(
		model,
		"Footing",
		Vector3.new(depth, 7.0, 7.0),
		base * CFrame.new(0, 0.1 - depth / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		STONE:Lerp(Color3.new(0, 0, 0), 0.15),
		Enum.Material.Rock
	)
	footing.Shape = Enum.PartType.Cylinder
	for i, y in ring do
		local drop = base.Position.Y - y
		if drop > 0.35 then
			local angle = (i - 1) / #ring * 2 * math.pi
			local size =
				Vector3.new(1.5 + (i % 3) * 0.45, math.min(drop + 0.7, 4.6), 1.3 + ((i + 1) % 3) * 0.4)
			part(
				model,
				"Rubble",
				size,
				base
					* CFrame.Angles(0, angle, 0)
					* CFrame.new(0, -drop + size.Y / 2 - 0.35, -3.45)
					* CFrame.Angles(
						math.rad(9 * (i % 3 - 1)),
						math.rad(23 * i),
						math.rad(7 * ((i + 1) % 3 - 1))
					),
				STONE:Lerp(Color3.new(0, 0, 0), 0.08 + (i % 2) * 0.1),
				Enum.Material.Rock
			)
		end
	end
	local sand = part(
		model,
		"Sand",
		Vector3.new(0.3, 6.6, 6.6),
		base * CFrame.new(0, 1.15, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(226, 208, 168),
		Enum.Material.Sand
	)
	sand.Shape = Enum.PartType.Cylinder
	local rim = part(
		model,
		"Rim",
		Vector3.new(0.12, 7.75, 7.75),
		base * CFrame.new(0, 1.22, 0) * CFrame.Angles(0, 0, math.rad(90)),
		glow.color,
		Enum.Material.Neon
	)
	rim.Shape = Enum.PartType.Cylinder
	rim.Transparency = 0.55
	-- The corals fill one after another; even an empty garden shows buds
	local top = base * CFrame.new(0, 1.3, 0)
	for i, spot in SPRIGS do
		local grown = math.clamp(fill * #SPRIGS - (i - 1), 0, 1)
		local size = 0.18 + 0.82 * grown
		local color = CORALS[(i - 1) % #CORALS + 1]
		local foot = top * CFrame.new(spot.X, 0, spot.Y) * CFrame.Angles(0, i * 1.7, 0)
		local height = 0.5 + 2.6 * size
		local stalk = part(
			model,
			"Coral",
			Vector3.new(height, 0.42 * size + 0.12, 0.42 * size + 0.12),
			foot * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			color,
			Enum.Material.SmoothPlastic
		)
		stalk.Shape = Enum.PartType.Cylinder
		if grown > 0.35 then
			for side = -1, 1, 2 do
				local length = height * 0.55
				local branch = part(
					model,
					"Branch",
					Vector3.new(length, 0.3 * size + 0.08, 0.3 * size + 0.08),
					foot
						* CFrame.new(0, height * 0.45, 0)
						* CFrame.Angles(0, 0, math.rad(90 + side * 38))
						* CFrame.new(length / 2, 0, 0),
					color,
					Enum.Material.SmoothPlastic
				)
				branch.Shape = Enum.PartType.Cylinder
			end
		end
		local cap = part(
			model,
			"Polyp",
			Vector3.one * (0.3 + 0.45 * size),
			foot * CFrame.new(0, height, 0),
			color:Lerp(Color3.new(1, 1, 1), 0.25),
			if grown >= 1 then Enum.Material.Neon else Enum.Material.SmoothPlastic
		)
		cap.Shape = Enum.PartType.Ball
	end
	-- Shells washed up on the sand
	for i = 1, math.floor(shellFill * 5 + 0.001) do
		local angle = i * 2.1
		local shell = part(
			model,
			"Shell",
			Vector3.new(0.7, 0.3, 0.6),
			top * CFrame.new(math.cos(angle) * 2.6, 0.05, math.sin(angle) * 2.6) * CFrame.Angles(0, angle, 0),
			Color3.fromRGB(242, 228, 204),
			Enum.Material.SmoothPlastic
		)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = shell
	end
	-- Full: it sparkles and glows, so a glance says "collect me"
	if fill >= 0.999 then
		local light = Instance.new("PointLight")
		light.Color = glow.color
		light.Range = 14
		light.Brightness = 1.4
		light.Parent = sand
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Rate = 6
		sparkle.Lifetime = NumberRange.new(1.2, 2)
		sparkle.Speed = NumberRange.new(0.5, 1.5)
		sparkle.SpreadAngle = Vector2.new(25, 25)
		sparkle.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkle.LightEmission = 1
		sparkle.Color = ColorSequence.new(glow.color)
		sparkle.EmissionDirection = Enum.NormalId.Right -- the cylinder's axis is up
		sparkle.Parent = sand
	end
	model.Parent = folder
	if known == nil or known.level ~= record.level then
		-- Terrain carved this frame doesn't answer a raycast until a later one, so
		-- the floor is found a moment after the den is built
		task.delay(0.5, function()
			local floorY, floorRing = floorUnder(base, nominal)
			if floorY == nil or model.Parent == nil then
				return
			end
			gardenFloors[index] = { level = record.level, y = floorY, ring = floorRing }
			-- Again, on the floor now, with a footing cut to its slope
			DenBuilder.garden(index, record, fill, shellFill)
		end)
	end
end

-- The top of the Terrain floor round `at` (the highest of five rays, so nothing is
-- buried), or nil when none of them finds the floor near `nominal`; and the floor's
-- height in eight directions just outside the bed's edge (the top where a ray
-- misses), for the footing
local RING_RADIUS = 3.8
function floorUnder(spot: CFrame, nominal: number): (number?, { number })
	local at = spot.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local best: number? = nil
	for _, offset in
		{
			Vector3.zero,
			Vector3.new(2.6, 0, 0),
			Vector3.new(-2.6, 0, 0),
			Vector3.new(0, 0, 2.6),
			Vector3.new(0, 0, -2.6),
		}
	do
		local origin = Vector3.new(at.X, nominal + 12, at.Z) + offset
		local hit = workspace:Raycast(origin, Vector3.new(0, -24, 0), params)
		if hit and hit.Position.Y > nominal - 3 and hit.Position.Y < nominal + 9 then
			best = math.max(best or -math.huge, hit.Position.Y)
		end
	end
	if best == nil then
		return nil, {}
	end
	local top = best - 0.15
	local ring: { number } = {}
	for i = 1, 8 do
		local angle = (i - 1) / 8 * 2 * math.pi
		-- The same directions the footing's rubble is laid in
		local edge = (spot * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -RING_RADIUS)).Position
		local origin = Vector3.new(edge.X, nominal + 12, edge.Z)
		local hit = workspace:Raycast(origin, Vector3.new(0, -24, 0), params)
		ring[i] = if hit
				and hit.Position.Y > nominal - 8
				and hit.Position.Y < top
			then hit.Position.Y
			else top
	end
	return top, ring
end

-- Builds (or rebuilds) den `index` from its owner's record (`fill` and `shellFill`:
-- the Coral Garden's, 0..1)
function DenBuilder.build(
	index: number,
	record: Record,
	trophies: Trophies,
	fill: number?,
	shellFill: number?
)
	DenBuilder.clear(index, false)
	carve(index, record.level)
	local folder = denFolder(index)
	furnish(folder, index, record)
	trophyWall(folder, index, record, trophies)
	DenBuilder.garden(index, record, fill or 0, shellFill or 0)
end

-- Takes a den's base down; with `refill` the rock goes back to a plain Nook
function DenBuilder.clear(index: number, refill: boolean)
	local folder = folders[index]
	if folder then
		folder:Destroy()
		folders[index] = nil
	end
	gardenFloors[index] = nil
	if refill then
		carve(index, 1)
	end
end

return DenBuilder
