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
		then `{trophies.teeth} tooth{if trophies.teeth == 1 then "" else "s"} taken`
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

-- Builds (or rebuilds) den `index` from its owner's record
function DenBuilder.build(index: number, record: Record, trophies: Trophies)
	DenBuilder.clear(index, false)
	carve(index, record.level)
	local folder = denFolder(index)
	furnish(folder, index, record)
	trophyWall(folder, index, record, trophies)
end

-- Takes a den's base down; with `refill` the rock goes back to a plain Nook
function DenBuilder.clear(index: number, refill: boolean)
	local folder = folders[index]
	if folder then
		folder:Destroy()
		folders[index] = nil
	end
	if refill then
		carve(index, 1)
	end
end

return DenBuilder
