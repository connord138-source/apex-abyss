--!strict
-- The roll reel's card photos (owner, 2026-10-08: "photos for the rolls need to be
-- dialed way up and look much more professional"): every card is a lit 3D shot. A
-- shade is your own fish wearing it (the real skin, the same FishBuilder and
-- Cosmetics as the fish you swim), a part or variant is a fish wearing that, and the
-- rest are small still lifes in the game's chunky low-poly style: coral sprigs (a
-- chest of them for the big amounts), shells, a bundle of prey for a Haul, a DNA
-- helix, rolled Kelp Wraps, a Lucky Charm. Imported props are used where they exist
-- (WorldProps, PreyModels). Each subject is built once per reel and cloned into the
-- cards that show it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local FishBuilder = require(ReplicatedStorage.Shared.FishBuilder)

local CardPhoto = {}

local LENGTH = 4 -- the subjects are about this many studs across
local FOV = 24 -- a long lens: flatter, like a product shot
local DEFAULT_LOOK: FishBuilder.Look = {
	back = Color3.fromRGB(52, 92, 132),
	belly = Color3.fromRGB(214, 226, 234),
	fin = Color3.fromRGB(78, 132, 176),
}

export type Outcome = { id: string, kind: string, name: string, tier: string, amount: number? }

local masters: { [string]: Model } = {}

local function part(
	parent: Instance,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- An ellipsoid: a block with a sphere mesh stretched to its size
local function blob(
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = part(parent, Enum.PartType.Block, size, cframe, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- An imported prop fitted to `height`, standing at `cframe`; nil when it isn't imported
local function prop(
	folderName: string,
	name: string,
	height: number,
	cframe: CFrame,
	parent: Instance
): Model?
	local folder = ReplicatedStorage:FindFirstChild(folderName)
	local template = folder and folder:FindFirstChild(name)
	if template == nil or not template:IsA("Model") then
		return nil
	end
	local model = template:Clone()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		elseif d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
	local extents = model:GetExtentsSize()
	model:ScaleTo(model:GetScale() * height / math.max(extents.Y, extents.X, extents.Z, 0.01))
	-- Stand it on `cframe`: its bounding box's bottom there, centered
	local box, size = model:GetBoundingBox()
	local pivotFromBox = box:ToObjectSpace(model:GetPivot())
	model:PivotTo(cframe * CFrame.new(0, size.Y / 2, 0) * pivotFromBox)
	model.Parent = parent
	return model
end

local function newSubject(): (Model, Part)
	local model = Instance.new("Model")
	model.Name = "Subject"
	local root = part(model, Enum.PartType.Block, Vector3.one, CFrame.new(), Color3.new(), nil)
	root.Name = "Root"
	root.Transparency = 1
	model.PrimaryPart = root
	return model, root
end

-- The player's current fish (or `speciesId`) and its base colors
local function myFish(speciesId: string?): (string, FishBuilder.Look)
	local character = Players.LocalPlayer.Character
	local id = speciesId
		or (if character then character:GetAttribute("Species") :: string? else nil)
		or Config.Species.STARTER
	local species = Config.Species.byId[id] or Config.Species.byId[Config.Species.STARTER]
	local look = if speciesId
		then { back = species.back, belly = species.belly, fin = species.fin }
		else (if character then FishBuilder.lookOf(character) else nil) or DEFAULT_LOOK
	return species.id, look
end

local function fish(dress: Cosmetics.Dress, speciesId: string?, partBody: boolean): Model
	local model, root = newSubject()
	local id, look = myFish(speciesId)
	local species = Config.Species.byId[id]
	local body = FishBuilder.build(model, root, look, LENGTH, species.plan, partBody)
	Cosmetics.apply(body, look, dress, LENGTH)
	FishBuilder.applyScale(body, LENGTH)
	model:SetAttribute("Pose", "fish")
	return model
end

local CORALS = {
	Color3.fromRGB(255, 104, 96),
	Color3.fromRGB(255, 156, 60),
	Color3.fromRGB(186, 98, 236),
	Color3.fromRGB(255, 92, 150),
}

local function sprig(parent: Instance, base: CFrame, height: number, color: Color3, rng: Random)
	local trunk = base * CFrame.Angles(rng:NextNumber(-0.25, 0.25), 0, rng:NextNumber(-0.25, 0.25))
	part(
		parent,
		Enum.PartType.Cylinder,
		Vector3.new(height, 0.22, 0.22),
		trunk * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color
	)
	part(
		parent,
		Enum.PartType.Ball,
		Vector3.one * 0.32,
		trunk * CFrame.new(0, height, 0),
		color:Lerp(Color3.new(1, 1, 1), 0.25)
	)
	for b = 1, 2 do
		local at = trunk
			* CFrame.new(0, height * (0.35 + b * 0.18), 0)
			* CFrame.Angles(0, b * 2.4, math.rad(rng:NextNumber(35, 55)))
		local len = height * rng:NextNumber(0.35, 0.5)
		part(
			parent,
			Enum.PartType.Cylinder,
			Vector3.new(len, 0.16, 0.16),
			at * CFrame.new(0, len / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			color
		)
		part(
			parent,
			Enum.PartType.Ball,
			Vector3.one * 0.24,
			at * CFrame.new(0, len, 0),
			color:Lerp(Color3.new(1, 1, 1), 0.25)
		)
	end
end

local function chest(parent: Instance, cframe: CFrame)
	if prop("WorldProps", "TreasureChest", 2.4, cframe, parent) then
		return
	end
	local wood, brass = Color3.fromRGB(96, 62, 38), Color3.fromRGB(232, 182, 64)
	part(
		parent,
		Enum.PartType.Block,
		Vector3.new(2.6, 1.4, 1.6),
		cframe * CFrame.new(0, 0.7, 0),
		wood,
		Enum.Material.Wood
	)
	part(
		parent,
		Enum.PartType.Cylinder,
		Vector3.new(2.6, 1.6, 1.6),
		cframe * CFrame.new(0, 1.4, 0) * CFrame.Angles(0, 0, 0),
		wood,
		Enum.Material.Wood
	)
	for _, x in { -0.9, 0.9 } do
		part(
			parent,
			Enum.PartType.Block,
			Vector3.new(0.18, 1.45, 1.65),
			cframe * CFrame.new(x, 0.72, 0),
			brass,
			Enum.Material.Metal
		)
	end
	part(
		parent,
		Enum.PartType.Block,
		Vector3.new(0.4, 0.5, 0.12),
		cframe * CFrame.new(0, 1.1, -0.82),
		brass,
		Enum.Material.Metal
	)
end

local function coin(parent: Instance, cframe: CFrame)
	part(
		parent,
		Enum.PartType.Cylinder,
		Vector3.new(0.1, 0.5, 0.5),
		cframe,
		Color3.fromRGB(255, 200, 60),
		Enum.Material.Metal
	)
end

local function coral(amount: number): Model
	local model = newSubject()
	local rng = Random.new(amount)
	part(
		model,
		Enum.PartType.Cylinder,
		Vector3.new(0.5, 3.4, 3.4),
		CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(196, 176, 132),
		Enum.Material.Sand
	)
	local big = amount >= 150
	if big then
		chest(model, CFrame.new(0.3, 0.3, 0.6) * CFrame.Angles(0, math.rad(-25), 0))
	end
	local count = if amount <= 25 then 3 elseif amount <= 60 then 5 elseif amount <= 150 then 5 else 8
	for i = 1, count do
		local angle = i / count * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local r = if big then rng:NextNumber(1.0, 1.5) else rng:NextNumber(0.2, 1.1)
		local base = CFrame.new(math.cos(angle) * r, 0.3, math.sin(angle) * r - (if big then 0.4 else 0))
		local color = CORALS[(i - 1) % #CORALS + 1]
		if
			not prop(
				"WorldProps",
				if i % 2 == 0 then "BrainCoral" else "StaghornCoral",
				rng:NextNumber(1.0, 1.6),
				base,
				model
			)
		then
			sprig(model, base, rng:NextNumber(1.1, 1.8), color, rng)
		end
	end
	if amount >= 600 then
		for _ = 1, 9 do
			local a = rng:NextNumber(0, math.pi * 2)
			coin(
				model,
				CFrame.new(
					math.cos(a) * rng:NextNumber(0.6, 1.5),
					0.42,
					math.sin(a) * rng:NextNumber(0.6, 1.5) - 0.6
				) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), math.rad(90))
			)
		end
	end
	model:SetAttribute("Pose", "still")
	return model
end

local function shells(): Model
	local model = newSubject()
	local rng = Random.new(5)
	for i = 1, 4 do
		local at = CFrame.new((i - 2.5) * 0.8, 0.35, rng:NextNumber(-0.4, 0.4))
			* CFrame.Angles(0, rng:NextNumber(0, 6), 0)
		if not prop("WorldProps", "Shell", 1.0, at, model) then
			local color = Color3.fromRGB(242, 214, 170)
				:Lerp(Color3.fromRGB(255, 160, 110), rng:NextNumber(0, 0.6))
			for k = 0, 3 do
				blob(
					model,
					Vector3.new(0.9 - k * 0.18, 0.5 - k * 0.08, 0.9 - k * 0.18),
					at * CFrame.new(k * 0.08, k * 0.22, 0),
					color:Lerp(Color3.fromRGB(150, 96, 70), k * 0.12)
				)
			end
		end
	end
	model:SetAttribute("Pose", "still")
	return model
end

local function haul(): Model
	local model = newSubject()
	local names = { "Snapper", "Grouper", "Wrasse" }
	for i, name in names do
		local at = CFrame.new(0, 0.6 + (i - 2) * 0.55, (i - 2) * 0.2)
			* CFrame.Angles(0, math.rad(90 + (i - 2) * 8), math.rad((i - 2) * 6))
		local placed = prop("PreyModels", name, 3.2, at, model)
		if not placed then
			local prey = Config.Prey.byId[name]
			local back = if prey then prey.back else Color3.fromRGB(200, 90, 70)
			local belly = if prey then prey.belly else Color3.fromRGB(240, 220, 200)
			blob(model, Vector3.new(0.9, 0.9, 3.0), at, back)
			blob(model, Vector3.new(0.7, 0.5, 2.6), at * CFrame.new(0, -0.18, 0), belly)
			part(model, Enum.PartType.Wedge, Vector3.new(0.1, 0.9, 0.8), at * CFrame.new(0, 0, 1.7), back)
		end
	end
	-- Tied with a kelp band
	part(
		model,
		Enum.PartType.Cylinder,
		Vector3.new(0.35, 1.9, 1.9),
		CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(70, 128, 52),
		Enum.Material.Grass
	)
	model:SetAttribute("Pose", "still")
	return model
end

local function dna(): Model
	local model = newSubject()
	local a, b = Color3.fromRGB(86, 222, 255), Color3.fromRGB(190, 110, 255)
	for i = 0, 11 do
		local y = i * 0.32
		local angle = i * 0.62
		local p1 = Vector3.new(math.cos(angle) * 0.8, y, math.sin(angle) * 0.8)
		local p2 = -Vector3.new(p1.X, 0, p1.Z) + Vector3.new(0, y, 0)
		part(model, Enum.PartType.Ball, Vector3.one * 0.38, CFrame.new(p1), a, Enum.Material.Neon)
		part(model, Enum.PartType.Ball, Vector3.one * 0.38, CFrame.new(p2), b, Enum.Material.Neon)
		local mid = (p1 + p2) / 2
		part(
			model,
			Enum.PartType.Cylinder,
			Vector3.new((p1 - p2).Magnitude, 0.1, 0.1),
			CFrame.lookAt(mid, p1) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(230, 240, 250)
		)
	end
	model:SetAttribute("Pose", "still")
	return model
end

local function wraps(): Model
	local model = newSubject()
	for i = 1, 3 do
		local at = CFrame.new((i - 2) * 0.9, 0.5 + (if i == 2 then 0.55 else 0), 0)
			* CFrame.Angles(0, math.rad((i - 2) * 18), math.rad(90))
		part(
			model,
			Enum.PartType.Cylinder,
			Vector3.new(2.6, 0.8, 0.8),
			at,
			Color3.fromRGB(64, 150, 70),
			Enum.Material.Grass
		)
		for _, x in { -1.15, 1.15 } do
			part(
				model,
				Enum.PartType.Cylinder,
				Vector3.new(0.12, 0.82, 0.82),
				at * CFrame.new(x, 0, 0),
				Color3.fromRGB(150, 220, 120),
				Enum.Material.Grass
			)
		end
		part(
			model,
			Enum.PartType.Cylinder,
			Vector3.new(0.25, 0.86, 0.86),
			at,
			Color3.fromRGB(196, 160, 96),
			Enum.Material.Fabric
		)
	end
	model:SetAttribute("Pose", "still")
	return model
end

local function charm(): Model
	local model = newSubject()
	local gold = Color3.fromRGB(255, 204, 70)
	local at = CFrame.new(0, 1.4, 0) * CFrame.Angles(0, math.rad(20), math.rad(90))
	part(model, Enum.PartType.Cylinder, Vector3.new(0.3, 2.4, 2.4), at, gold, Enum.Material.Metal)
	part(
		model,
		Enum.PartType.Cylinder,
		Vector3.new(0.34, 1.7, 1.7),
		at,
		gold:Lerp(Color3.fromRGB(140, 90, 20), 0.35),
		Enum.Material.Metal
	)
	part(
		model,
		Enum.PartType.Ball,
		Vector3.one * 0.9,
		CFrame.new(0, 1.4, 0) * CFrame.Angles(0, math.rad(20), 0) * CFrame.new(0, 0, -0.18),
		Color3.fromRGB(70, 255, 200),
		Enum.Material.Neon
	)
	part(
		model,
		Enum.PartType.Cylinder,
		Vector3.new(0.12, 0.6, 0.6),
		CFrame.new(0, 2.75, 0) * CFrame.Angles(0, math.rad(20), 0),
		gold,
		Enum.Material.Metal
	)
	model:SetAttribute("Pose", "still")
	return model
end

-- The subject for an outcome, built once and kept as the master copy
local function master(outcome: Outcome): Model?
	local character = Players.LocalPlayer.Character
	local species = if character then character:GetAttribute("Species") else nil
	local key = `{outcome.kind}:{outcome.id}:{tostring(species)}`
	local made = masters[key]
	if made then
		return made
	end
	local model: Model? = nil
	local kind = outcome.kind
	if kind == "shade" then
		model = fish({ shade = outcome.id, parts = {}, variant = nil }, nil, false)
	elseif kind == "part" then
		local cosmetic = Config.Exotics.partsById[outcome.id]
		if cosmetic then
			model = fish({ shade = nil, parts = { [cosmetic.slot] = cosmetic.id }, variant = nil }, nil, true)
		end
	elseif kind == "variant" then
		local variant = Config.Exotics.variantsById[outcome.id]
		if variant then
			model = fish({ shade = nil, parts = {}, variant = variant.id }, variant.species, true)
		end
	elseif kind == "coral" then
		model = coral(outcome.amount or 25)
	elseif kind == "shells" then
		model = shells()
	elseif kind == "haul" then
		model = haul()
	elseif kind == "dna" then
		model = dna()
	elseif kind == "wraps" then
		model = wraps()
	elseif kind == "charm" then
		model = charm()
	end
	if model then
		for _, d in model:GetDescendants() do
			if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Highlight") then
				d:Destroy()
			end
		end
		masters[key] = model
	end
	return model
end

-- Forget the built subjects (the player's fish or look changed)
function CardPhoto.reset()
	for _, model in masters do
		model:Destroy()
	end
	table.clear(masters)
end

-- A lit 3D shot of `outcome` in a ViewportFrame filling `parent`, tinted toward
-- `tint` (the tier's color). Nil if there's nothing to show.
function CardPhoto.new(parent: GuiObject, outcome: Outcome, tint: Color3): ViewportFrame?
	local source = master(outcome)
	if source == nil then
		return nil
	end
	local frame = Instance.new("ViewportFrame")
	frame.Name = "Photo"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Ambient = Color3.fromRGB(118, 132, 150):Lerp(tint, 0.18)
	frame.LightColor = Color3.fromRGB(255, 250, 240)
	frame.LightDirection = Vector3.new(-0.45, -1, -0.55)
	frame.ZIndex = parent.ZIndex
	local world = Instance.new("WorldModel")
	world.Parent = frame
	local model = source:Clone()
	model.Parent = world
	local root = model.PrimaryPart
	if root and model:GetAttribute("Pose") == "fish" then
		-- Three-quarter, head to the left and toward us, nose lifted: a hero pose
		root.CFrame = CFrame.Angles(0, math.rad(118), 0) * CFrame.Angles(math.rad(8), 0, math.rad(-5))
	elseif root then
		model:PivotTo(CFrame.Angles(0, math.rad(-18), 0) * model:GetPivot())
	end
	local box, extents = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	camera.Parent = frame
	frame.CurrentCamera = camera
	local size = parent.AbsoluteSize
	local aspect = if size.Y > 1 then size.X / size.Y else 1
	local tanV = math.tan(math.rad(FOV / 2))
	local reach = math.max(extents.X, extents.Z) / 2
	local half = extents.Y / 2
	local distance = math.max(reach / (tanV * aspect), half / tanV) * 1.25
		+ math.max(extents.X, extents.Z) / 2
	local look = (Vector3.new(0, 0.22, 1)).Unit
	camera.CFrame = CFrame.lookAt(box.Position + look * distance, box.Position)
	frame.Parent = parent
	return frame
end

return CardPhoto
