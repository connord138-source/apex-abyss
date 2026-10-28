--!strict
-- A still copy of a prey fish to show off (2026-10-28, the den's Trophy Gallery and
-- aquarium tanks): its imported model (ReplicatedStorage.PreyModels) scaled to a
-- length, or a part-built stand-in in its colours while it isn't imported, dressed
-- in a rare catch's look (Config/Catch rarities: the same looks the schools wear,
-- SchoolController LOOKS). Shared so the server's gallery and the client's tanks
-- draw a fish the same way.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local SwimWave = require(script.Parent.SwimWave)

local PreyDisplay = {}

export type Look = {
	material: Enum.Material,
	color: Color3,
	reflectance: number,
	transparency: number,
	light: number, -- its own light's brightness (0: none)
}

-- How each rarity looks on a fish (as SchoolController's LOOKS): its material and
-- colour (the texture held aside) and its light
PreyDisplay.LOOKS = {
	Silver = {
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(222, 232, 248),
		reflectance = 0.15,
		transparency = 0,
		light = 1.5,
	},
	Golden = {
		material = Enum.Material.Foil,
		color = Color3.fromRGB(255, 196, 64),
		reflectance = 0.1,
		transparency = 0,
		light = 1.2,
	},
	Glowing = {
		material = Enum.Material.Neon,
		color = Color3.fromRGB(20, 170, 160),
		reflectance = 0,
		transparency = 0,
		light = 2.2,
	},
	Crystal = {
		material = Enum.Material.Glass,
		color = Color3.fromRGB(150, 210, 255),
		reflectance = 0.3,
		transparency = 0.25,
		light = 1.6,
	},
	Prism = {
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(255, 120, 230),
		reflectance = 0.15,
		transparency = 0,
		light = 2.2,
	},
} :: { [string]: Look }

export type Display = {
	model: Model,
	body: BasePart, -- the part whose CFrame places the fish (its head along its look)
	turn: CFrame, -- body.CFrame = place * turn (a static mesh facing +Z is turned round)
	bones: { [string]: Bone }, -- a rigged model's, for a swim (SwimWave)
	spine: { string },
	parts: { BasePart },
	length: number,
	pieces: { [BasePart]: CFrame }?, -- a stand-in's pieces, against its body
}

local function ellipsoid(parent: Instance, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	part.Color = color
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.Parent = parent
	return part
end

-- Dresses every part of a display in a rarity's look ("Normal": as it is)
function PreyDisplay.dress(display: Display, rarity: string)
	local look = PreyDisplay.LOOKS[rarity]
	if look == nil then
		return
	end
	for _, part in display.parts do
		local skin = part:FindFirstChildWhichIsA("SurfaceAppearance")
		if skin then
			skin:Destroy()
		end
		if part:IsA("MeshPart") then
			part.TextureID = ""
		end
		part.Material = look.material
		part.Color = look.color
		part.Reflectance = look.reflectance
		part.Transparency = look.transparency
	end
	if look.light > 0 then
		local light = Instance.new("PointLight")
		light.Color = look.color
		light.Range = math.max(display.length * 1.6, 6)
		light.Brightness = look.light * 0.6
		light.Parent = display.body
	end
end

-- A still fish `length` studs long in `rarity`'s look, unparented: place it with
-- PreyDisplay.place
function PreyDisplay.build(preyId: string, rarity: string, length: number): Display
	local model = Instance.new("Model")
	model.Name = preyId
	local folder = ReplicatedStorage:FindFirstChild("PreyModels")
	local template = folder and folder:FindFirstChild(preyId)
	local display: Display
	if template and (template:IsA("Model") or template:IsA("MeshPart")) then
		local copy = template:Clone()
		local mesh: BasePart? = if copy:IsA("MeshPart")
			then copy
			else copy:FindFirstChildWhichIsA("MeshPart", true)
		if mesh then
			local parts: { BasePart } = {}
			local bones: { [string]: Bone } = {}
			for _, item in copy:GetDescendants() do
				if item:IsA("BasePart") then
					table.insert(parts, item)
				elseif item:IsA("Bone") then
					bones[item.Name] = item
				end
			end
			if copy:IsA("BasePart") then
				table.insert(parts, copy)
			end
			for _, part in parts do
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
			end
			local spine: { string } = {}
			local i = 1
			while bones[`Spine{i}`] do
				table.insert(spine, `Spine{i}`)
				i += 1
			end
			if bones.Tail then
				table.insert(spine, "Tail")
			end
			-- Its length along its own Z, then scaled to `length`
			local scale = length / math.max(mesh.Size.Z, 0.1)
			if copy:IsA("Model") then
				copy:ScaleTo(copy:GetScale() * scale)
			else
				copy.Size *= scale
			end
			copy.Parent = model
			local rigged = next(bones) ~= nil
			display = {
				model = model,
				body = mesh,
				turn = if not rigged and SwimWave.needsFlip(mesh)
					then CFrame.Angles(0, math.pi, 0)
					else CFrame.identity,
				bones = bones,
				spine = spine,
				parts = parts,
				length = length,
				pieces = nil,
			}
			PreyDisplay.dress(display, rarity)
			return display
		end
		copy:Destroy()
	end
	-- Part-built while it isn't imported: an egg-shaped body and a tail in its colours
	local prey = Config.Prey.byId[preyId]
	local back = if prey then prey.back else Color3.fromRGB(120, 140, 150)
	local belly = if prey then prey.belly else Color3.fromRGB(210, 220, 224)
	local slim = if prey then prey.slim else 0.3
	local body = ellipsoid(model, Vector3.new(length * slim * 0.45, length * slim, length * 0.8), back)
	local underside =
		ellipsoid(model, Vector3.new(length * slim * 0.4, length * slim * 0.6, length * 0.65), belly)
	local tail = ellipsoid(model, Vector3.new(length * 0.04, length * slim * 1.1, length * 0.26), back)
	model.PrimaryPart = body
	display = {
		model = model,
		body = body,
		turn = CFrame.identity,
		bones = {},
		spine = {},
		parts = { body, underside, tail },
		length = length,
		pieces = {
			[underside :: BasePart] = CFrame.new(0, -length * slim * 0.18, 0),
			[tail :: BasePart] = CFrame.new(0, 0, length * 0.46),
		} :: { [BasePart]: CFrame },
	}
	PreyDisplay.dress(display, rarity)
	return display
end

-- Puts a display's head along `frame`'s look (its middle at frame's position)
function PreyDisplay.place(display: Display, frame: CFrame)
	local pieces = display.pieces
	if pieces then
		-- the stand-in: its pieces ride with the body
		display.body.CFrame = frame
		for part, offset in pieces do
			part.CFrame = frame * offset
		end
		return
	end
	local root = display.model:FindFirstChildWhichIsA("Model") or display.model
	local target = frame * display.turn
	local pivot = root:GetPivot()
	local offset = display.body.CFrame:ToObjectSpace(pivot)
	root:PivotTo(target * offset)
end

return PreyDisplay
