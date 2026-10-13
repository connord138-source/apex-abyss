--!strict
-- Builds one den thing (Config/Dens items) as a Model whose pivot is where it's
-- attached: a floor thing's pivot is under its middle and it stands up from there; a
-- wall thing's pivot is on the rock and it stands out along the pivot's look; a
-- ceiling thing's pivot is on the rock above and it hangs down. The server places
-- them (DenBuilder) and Build mode's ghost is the same model (BuildController), so
-- what you aim is what you get. Imported Tripo props (Props.dress) replace the
-- part-built stand-ins where they exist.
local Config = require(script.Parent.Config)
local DensConfig = require(script.Parent.Config.Dens)
local Props = require(script.Parent.Props)

local DenItems = {}

local STONE = Color3.fromRGB(150, 138, 118)
local WOOD = Color3.fromRGB(110, 86, 60)
local IRON = Color3.fromRGB(52, 58, 64)

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

local function shaped(p: Part, shape: Enum.PartType): Part
	p.Shape = shape
	return p
end

local function light(on: BasePart, color: Color3, range: number, brightness: number)
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = range
	glow.Brightness = brightness
	glow.Parent = on
end

-- A box the imported prop is fitted into, or the stand-in that shows without it. A
-- Tripo prop faces +X in its GLB (Roblox's import turns it to -X), so `front` turns
-- it to face the box's look, and the box is fitted turned with it.
local function dressed(model: Model, item: DensConfig.Item, box: CFrame, color: Color3): Part
	local stand = part(
		model,
		"Body",
		item.size,
		box,
		color,
		if item.glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	)
	if item.prop then
		local fit, size = box, item.size
		if item.front then
			fit = box * CFrame.Angles(0, -math.rad(item.front), 0)
			size = Vector3.new(size.Z, size.Y, size.X)
		end
		local prop = Props.dress(stand, item.prop, { cframe = fit, size = size })
		if prop and item.glow then
			Props.tint(prop, color)
		end
	end
	return stand
end

-- A rug: a flat body in its own color, and its top-down art (Config/Textures
-- `rug<id>`, tools/props/rug_textures.py) as a Decal on an invisible sheet just
-- over it. Without the art, rings of its color stand in.
local function rug(model: Model, item: DensConfig.Item): Part
	local size = item.size
	local round = item.rug ~= "square"
	local function sheet(name: string, inset: number, y: number, color: Color3): Part
		local made = part(
			model,
			name,
			Vector3.new(size.X - inset, 0.1, size.Z - inset),
			CFrame.new(0, y, 0),
			color,
			Enum.Material.Fabric
		)
		if round then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = made
		end
		return made
	end
	local body = sheet("Rug", 0, 0.05, item.color)
	local art = (Config.Textures :: any)[`rug{item.id}`]
	if typeof(art) == "number" and art > 0 then
		local face = part(
			model,
			"Art",
			Vector3.new(size.X, 0.05, size.Z),
			CFrame.new(0, 0.13, 0),
			item.color,
			Enum.Material.SmoothPlastic
		)
		face.Transparency = 1
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Top
		decal.Texture = `rbxassetid://{art}`
		decal.Parent = face
	else
		sheet("Border", 0.8, 0.07, item.color:Lerp(Color3.new(0, 0, 0), 0.3))
		sheet("Field", 1.8, 0.09, item.color:Lerp(Color3.new(1, 1, 1), 0.18))
		sheet("Heart", size.X * 0.6, 0.11, item.color:Lerp(Color3.new(0, 0, 0), 0.2))
	end
	return body
end

-- The thing `item` in the den's glow color, at the identity frame (move it with
-- PivotTo). `surface` picks how a thing that goes in more than one place is
-- mounted (the Crystal Shard juts out of a wall).
function DenItems.build(item: DensConfig.Item, glow: Color3, surface: string): Model
	local model = Instance.new("Model")
	model.Name = item.id
	local color = if item.glow and item.id ~= "CoralLamp" then glow else item.color
	local size = item.size
	local main: BasePart
	if item.id == "Banner" then
		part(
			model,
			"Pole",
			Vector3.new(size.X + 0.8, 0.35, 0.35),
			CFrame.new(0, size.Y / 2, -0.35),
			WOOD,
			Enum.Material.Wood
		)
		main = part(
			model,
			"Cloth",
			Vector3.new(size.X, size.Y, 0.2),
			CFrame.new(0, 0, -0.4),
			glow,
			Enum.Material.Fabric
		)
		part(
			model,
			"Hem",
			Vector3.new(size.X, 0.3, 0.26),
			CFrame.new(0, -size.Y / 2, -0.4),
			glow:Lerp(Color3.new(1, 1, 1), 0.3),
			Enum.Material.Neon
		)
		-- A crest stitched on: a ring and a fin
		local crest = part(
			model,
			"Crest",
			Vector3.new(0.08, 2.2, 2.2),
			CFrame.new(0, 0.6, -0.53) * CFrame.Angles(0, math.rad(90), 0),
			glow:Lerp(Color3.new(1, 1, 1), 0.55),
			Enum.Material.SmoothPlastic
		)
		shaped(crest, Enum.PartType.Cylinder)
	elseif item.id == "SeaGlassLantern" then
		part(
			model,
			"Bracket",
			Vector3.new(0.35, 0.35, 1.6),
			CFrame.new(0, 1.3, -0.8),
			IRON,
			Enum.Material.Metal
		)
		part(model, "Hook", Vector3.new(0.2, 0.7, 0.2), CFrame.new(0, 1.0, -1.5), IRON, Enum.Material.Metal)
		main = part(
			model,
			"Glass",
			Vector3.new(1.3, 1.8, 1.3),
			CFrame.new(0, -0.1, -1.5),
			color,
			Enum.Material.Glass
		)
		main.Transparency = 0.25
		part(model, "Cap", Vector3.new(1.6, 0.3, 1.6), CFrame.new(0, 0.85, -1.5), IRON, Enum.Material.Metal)
		part(model, "Foot", Vector3.new(1.5, 0.25, 1.5), CFrame.new(0, -1.1, -1.5), IRON, Enum.Material.Metal)
		local flame = shaped(
			part(model, "Flame", Vector3.one * 0.7, CFrame.new(0, -0.1, -1.5), color, Enum.Material.Neon),
			Enum.PartType.Ball
		)
		main = flame
	elseif item.id == "JellyLamp" then
		part(model, "Cord", Vector3.new(0.12, 1.4, 0.12), CFrame.new(0, -0.7, 0), IRON, Enum.Material.Metal)
		local bell = shaped(
			part(model, "Bell", Vector3.new(3, 2, 3), CFrame.new(0, -2.2, 0), color, Enum.Material.Glass),
			Enum.PartType.Ball
		)
		bell.Transparency = 0.3
		local core = shaped(
			part(model, "Core", Vector3.new(1.4, 0.9, 1.4), CFrame.new(0, -2.3, 0), color, Enum.Material.Neon),
			Enum.PartType.Ball
		)
		for i = 1, 6 do
			local angle = i / 6 * 2 * math.pi
			local length = 1.6 + (i % 3) * 0.5
			local tentacle = part(
				model,
				"Tentacle",
				Vector3.new(0.14, length, 0.14),
				CFrame.new(math.cos(angle) * 0.9, -3.1 - length / 2, math.sin(angle) * 0.9)
					* CFrame.Angles(math.sin(angle) * 0.15, 0, math.cos(angle) * 0.15),
				color:Lerp(Color3.new(1, 1, 1), 0.35),
				Enum.Material.Neon
			)
			tentacle.Transparency = 0.35
		end
		main = core
	elseif item.id == "KelpRug" then
		main = part(
			model,
			"Rug",
			Vector3.new(size.X, 0.14, size.Z),
			CFrame.new(0, 0.07, 0),
			item.color,
			Enum.Material.Fabric
		)
		part(
			model,
			"Border",
			Vector3.new(size.X - 0.7, 0.15, size.Z - 0.7),
			CFrame.new(0, 0.08, 0),
			item.color:Lerp(Color3.new(0, 0, 0), 0.3),
			Enum.Material.Fabric
		)
		part(
			model,
			"Field",
			Vector3.new(size.X - 1.4, 0.16, size.Z - 1.4),
			CFrame.new(0, 0.09, 0),
			item.color:Lerp(Color3.fromRGB(196, 220, 170), 0.25),
			Enum.Material.Fabric
		)
		-- A woven diamond in the middle in the den's glow
		part(
			model,
			"Motif",
			Vector3.new(1.8, 0.17, 1.8),
			CFrame.new(0, 0.1, 0) * CFrame.Angles(0, math.rad(45), 0),
			glow:Lerp(item.color, 0.35),
			Enum.Material.Fabric
		)
	elseif item.id == "DriftwoodTable" then
		for _, x in { -2, 2 } do
			part(model, "Stone", Vector3.new(1.6, 2, 1.6), CFrame.new(x, 1, 0), STONE, Enum.Material.Slate)
		end
		main = part(
			model,
			"Top",
			Vector3.new(size.X, 0.7, size.Z),
			CFrame.new(0, 2.3, 0) * CFrame.Angles(0, 0, math.rad(2)),
			WOOD,
			Enum.Material.Wood
		)
	elseif item.id == "PearlPedestal" then
		part(model, "Plinth", Vector3.new(2.4, 0.5, 2.4), CFrame.new(0, 0.25, 0), STONE, Enum.Material.Slate)
		part(model, "Column", Vector3.new(1.6, 3, 1.6), CFrame.new(0, 2, 0), STONE, Enum.Material.Slate)
		part(model, "Dish", Vector3.new(2.2, 0.4, 2.2), CFrame.new(0, 3.6, 0), STONE, Enum.Material.Slate)
		main = shaped(
			part(
				model,
				"Pearl",
				Vector3.one * 2.2,
				CFrame.new(0, 4.6, 0),
				Color3.fromRGB(240, 240, 246),
				Enum.Material.SmoothPlastic
			),
			Enum.PartType.Ball
		)
		main.Reflectance = 0.35
	elseif item.id == "BubbleColumn" then
		main = shaped(
			part(
				model,
				"Vent",
				Vector3.new(0.8, 2, 2),
				CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Color3.fromRGB(70, 80, 90),
				Enum.Material.Basalt
			),
			Enum.PartType.Cylinder
		)
		local bubbles = Instance.new("ParticleEmitter")
		bubbles.Rate = 12
		bubbles.Lifetime = NumberRange.new(2.5, 4)
		bubbles.Speed = NumberRange.new(3, 5)
		bubbles.SpreadAngle = Vector2.new(6, 6)
		bubbles.Size = NumberSequence.new(0.3, 0.7)
		bubbles.Transparency = NumberSequence.new(0.2, 0.8)
		bubbles.LightEmission = 0.4
		bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 250, 255))
		bubbles.EmissionDirection = Enum.NormalId.Right -- the cylinder's axis is up
		bubbles.Parent = main
	elseif item.rug then
		main = rug(model, item)
	elseif surface == "wall" and table.find(item.kinds, "floor") then
		-- A floor thing on a wall juts out of the rock: its up turned to point out
		main = dressed(model, item, CFrame.new(0, 0, -size.Y / 2) * CFrame.Angles(math.rad(-90), 0, 0), color)
	elseif surface == "wall" then
		-- A wall thing hangs flat on the rock, standing out by its depth
		main = dressed(model, item, CFrame.new(0, 0, -size.Z / 2), color)
	elseif surface == "ceiling" then
		main = dressed(model, item, CFrame.new(0, -size.Y / 2, 0), color)
	else
		main = dressed(model, item, CFrame.new(0, size.Y / 2, 0), color)
	end
	if item.glow then
		light(main, color, 18, 1.3)
	elseif item.lamp then
		light(main, item.lamp, 18, 1.2)
	end
	-- A few bubbles off the top of a thing that steams (the Vent Cauldron)
	if item.bubbles and item.id ~= "BubbleColumn" then
		local vent = part(
			model,
			"Steam",
			Vector3.new(size.X * 0.5, 0.2, size.Z * 0.5),
			main.CFrame * CFrame.new(0, size.Y * 0.3, 0),
			item.color,
			Enum.Material.SmoothPlastic
		)
		vent.Transparency = 1
		local bubbles = Instance.new("ParticleEmitter")
		bubbles.Rate = 5
		bubbles.Lifetime = NumberRange.new(1.5, 2.5)
		bubbles.Speed = NumberRange.new(2, 3.5)
		bubbles.SpreadAngle = Vector2.new(10, 10)
		bubbles.Size = NumberSequence.new(0.25, 0.5)
		bubbles.Transparency = NumberSequence.new(0.3, 0.9)
		bubbles.LightEmission = 0.3
		bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 250, 255))
		bubbles.EmissionDirection = Enum.NormalId.Top
		bubbles.Shape = Enum.ParticleEmitterShape.Box
		bubbles.Parent = vent
	end
	-- An invisible root at the pivot (what Build mode hits to pick a thing up)
	local root = part(model, "Root", Vector3.one * 0.2, CFrame.new(), color, Enum.Material.SmoothPlastic)
	root.Transparency = 1
	model.PrimaryPart = root
	return model
end

-- The thing's box at the identity frame (Build mode's clearance and pick-up box)
function DenItems.box(item: DensConfig.Item, surface: string): (CFrame, Vector3)
	local size = item.size
	if surface == "wall" and table.find(item.kinds, "floor") then
		return CFrame.new(0, 0, -size.Y / 2) * CFrame.Angles(math.rad(-90), 0, 0), size
	elseif surface == "wall" then
		return CFrame.new(0, 0, -size.Z / 2), size
	elseif surface == "ceiling" then
		return CFrame.new(0, -size.Y / 2, 0), size
	end
	return CFrame.new(0, size.Y / 2, 0), size
end

-- Every surface a thing goes on, in the order Build mode tries them
function DenItems.surfaces(item: DensConfig.Item): { string }
	return item.kinds
end

return DenItems
