--!strict
-- Builds a den in the world from its owner's record (Config/Dens, Shared/DenSpace):
--  * the rock (DenCarve), carved again only when the level changes;
--  * the shell: a flagstone deck on every storey in the den's floor style, stone
--    curbs round the shafts, pillars with sconces down the big rooms, and orb lamps
--    hanging from the vaults, lit in the den's glow;
--  * the things placed in Build mode, kept in step with the record by id;
--  * the trophy wall on the main room's back wall (the biggest catch, boss teeth and
--    beaks, the title over the door);
--  * the Coral Garden (a planter along the back wall, then a bed in the Hall's
--    middle), its corals growing as it fills.
-- Everything is rebuilt from the saved record, so it follows its owner from server
-- to server; when a den changes hands the rock goes back to a Nook first.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DenItems = require(ReplicatedStorage.Shared.DenItems)
local DenSpace = require(ReplicatedStorage.Shared.DenSpace)
local Props = require(ReplicatedStorage.Shared.Props)
local Cave = require(script.Parent.Cave)
local DenCarve = require(script.Parent.DenCarve)

local Dens = Config.Dens
local hub = Config.World.hub

local DenBuilder = {}

export type Placement = {
	uid: number,
	id: string,
	x: number,
	y: number,
	z: number,
	r: number, -- yaw, degrees
	s: string, -- the surface: "floor", "wall" or "ceiling"
}

export type Record = {
	level: number,
	glow: string,
	floor: string,
	placed: { Placement },
}

export type Trophies = {
	bestPrey: string,
	bestPreyMass: number,
	teeth: number,
	beaks: number,
	title: string,
	owner: string,
}

type Built = { model: Model, key: string }
type DenState = {
	folder: Folder,
	shell: Folder,
	items: Folder,
	trophies: Folder,
	carved: number?, -- the level the rock is carved for
	shellKey: string?, -- level, floor and glow the shell was built for
	placed: { [number]: Built },
	trophyKey: string?,
}

local STONE = Color3.fromRGB(176, 164, 140)
local LAMP = Color3.fromRGB(255, 222, 180)

local states: { [number]: DenState } = {}

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

local function light(on: Instance, color: Color3, range: number, brightness: number)
	local made = Instance.new("PointLight")
	made.Color = color
	made.Range = range
	made.Brightness = brightness
	made.Parent = on
end

local function glowOf(record: Record): Color3
	local glow = Dens.glowsById[record.glow] or Dens.glows[1]
	return glow.color
end

local function stateOf(index: number): DenState
	local existing = states[index]
	if existing and existing.folder.Parent then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = `DenBase{index}`
	local world = workspace:FindFirstChild("World")
	local hubFolder = world and world:FindFirstChild("Hub")
	local function sub(name: string): Folder
		local made = Instance.new("Folder")
		made.Name = name
		made.Parent = folder
		return made
	end
	local made: DenState = {
		folder = folder,
		shell = sub("Shell"),
		items = sub("Items"),
		trophies = sub("Trophies"),
		carved = if existing then existing.carved else nil,
		placed = {},
	}
	-- The camera looks past furniture (CameraController ignores this tag)
	CollectionService:AddTag(made.items, "DenItems")
	folder.Parent = hubFolder or workspace
	states[index] = made
	return made
end

-- A small, fixed scramble of a tile's corner (flagstone colors and shades)
local function hash(a: number, b: number, c: number): number
	return (math.floor(a) * 73856093 + math.floor(b) * 19349663 + c * 83492791) % 1000003
end

-- The shell: decks, shaft curbs, pillars, lamps
local function buildShell(state: DenState, index: number, record: Record)
	state.shell:ClearAllChildren()
	local frame = DenSpace.frame(index)
	local level = record.level
	local glow = glowOf(record)
	local style = Dens.floorsById[record.floor] or Dens.floors[1]
	local function spot(x: number, y: number, z: number): CFrame
		return DenSpace.spot(frame, x, y, z)
	end
	-- Decks: flagstones of mixed sizes with thin dark joints between them (the rock
	-- shows 2 studs under the gaps); the obsidian floor glows in its joints
	for storey = 1, DenSpace.storeys(level) do
		local s = DenSpace.storey(storey)
		for _, tile in DenSpace.tiles(level, storey, 10) do
			local w, d = tile.x1 - tile.x0, tile.z0 - tile.z1
			local cx, cz = (tile.x0 + tile.x1) / 2, (tile.z0 + tile.z1) / 2
			local h = hash(tile.x0, tile.z1, storey)
			local base = style.colors[h % #style.colors + 1]
			local deck = part(
				state.shell,
				"Deck",
				Vector3.new(w - 0.14, 3, d - 0.14),
				spot(cx, s.deck - 1.5, cz),
				base:Lerp(Color3.new(0, 0, 0), (h // 7 % 6) * 0.018),
				style.material
			)
			deck.CanCollide = true
			deck.CanQuery = true
			deck:SetAttribute("DenDeck", storey)
			if style.seams then
				part(
					state.shell,
					"Seam",
					Vector3.new(w, 0.2, d),
					spot(cx, s.deck - 0.4, cz),
					glow,
					Enum.Material.Neon
				)
			end
		end
	end
	-- Curbs round the shafts down, a glowing lip on their inside, and a light where
	-- each comes out of the ceiling below
	for _, shaft in DenSpace.shafts(level) do
		local deck = DenSpace.storey(shaft.from).deck
		local radius = shaft.radius + 0.7
		local count = 16
		local length = 2 * math.pi * radius / count + 0.15
		for i = 1, count do
			local around = spot(0, deck, shaft.z) * CFrame.Angles(0, (i - 0.5) / count * 2 * math.pi, 0)
			local curb = part(
				state.shell,
				"Curb",
				Vector3.new(length, 3, 1.3), -- down to the rock under the deck
				around * CFrame.new(0, -0.5, -radius),
				STONE,
				Enum.Material.Slate
			)
			curb.CanCollide = true
			part(
				state.shell,
				"Lip",
				Vector3.new(length, 0.16, 0.3),
				around * CFrame.new(0, 1.0, -radius + 0.55),
				glow,
				Enum.Material.Neon
			)
		end
		local below = part(
			state.shell,
			"ShaftLight",
			Vector3.one * 0.5,
			spot(0, DenSpace.storey(shaft.to).ceiling - 3, shaft.z),
			glow,
			Enum.Material.SmoothPlastic
		)
		below.Transparency = 1
		light(below, glow, 30, 0.9)
	end
	-- Pillars down the big rooms, up into the vault, every other one with a sconce
	for n, pillar in DenSpace.pillars(level) do
		local room = Dens.roomsById[pillar.room]
		if room == nil then
			continue
		end
		local s = DenSpace.storey(room.storey)
		local height = DenSpace.vaultAt(room, math.abs(pillar.x)) + 1.5
		local foot = spot(pillar.x, s.deck, pillar.z)
		local shaftPart = part(
			state.shell,
			"Pillar",
			Vector3.new(height, 2.6, 2.6),
			foot * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			STONE,
			Enum.Material.Slate
		)
		shaftPart.Shape = Enum.PartType.Cylinder
		shaftPart.CanCollide = true
		local plinth = part(
			state.shell,
			"Plinth",
			Vector3.new(3.8, 1.1, 3.8),
			foot * CFrame.new(0, 0.55, 0),
			STONE,
			Enum.Material.Slate
		)
		plinth.CanCollide = true
		part(
			state.shell,
			"Capital",
			Vector3.new(3.6, 0.9, 3.6),
			foot * CFrame.new(0, height - 1.2, 0),
			STONE,
			Enum.Material.Slate
		)
		-- The sconce faces the room's middle
		local inward = if pillar.x > 0 then -1 else 1
		local sconce = part(
			state.shell,
			"Sconce",
			Vector3.new(0.5, 1.2, 0.8),
			foot * CFrame.new(inward * 1.45, 7, 0),
			glow,
			Enum.Material.Neon
		)
		if n % 2 == 1 then
			light(sconce, glow, 16, 0.9)
		end
	end
	-- Orb lamps hanging down the middle of every storey below, one every 16 studs
	for storey = 2, DenSpace.storeys(level) do
		local s = DenSpace.storey(storey)
		local rooms = DenSpace.rooms(level, storey)
		local front, back = -math.huge, math.huge
		for _, room in rooms do
			front = math.max(front, room.z0)
			back = math.min(back, room.z1)
		end
		local z = front - 8
		while z > back + 4 do
			local vault = 0
			for _, room in rooms do
				if z <= room.z0 and z >= room.z1 then
					vault = math.max(vault, DenSpace.vaultAt(room, 0))
				end
			end
			if vault > 0 then
				local top = s.deck + vault
				part(
					state.shell,
					"Cord",
					Vector3.new(0.15, 4, 0.15),
					spot(0, top - 1.5, z),
					STONE,
					Enum.Material.Metal
				)
				local orb = part(
					state.shell,
					"Orb",
					Vector3.one * 1.8,
					spot(0, top - 4.2, z),
					glow:Lerp(Color3.new(1, 1, 1), 0.5),
					Enum.Material.Glass
				)
				orb.Shape = Enum.PartType.Ball
				orb.Transparency = 0.2
				local core = part(
					state.shell,
					"Core",
					Vector3.one * 0.8,
					spot(0, top - 4.2, z),
					LAMP,
					Enum.Material.Neon
				)
				core.Shape = Enum.PartType.Ball
				light(core, LAMP, 34, 0.75)
			end
			z -= 16
		end
	end
	-- Two orb lamps down the Burrow
	if level >= 2 then
		for _, z in { -22, -33 } do
			part(
				state.shell,
				"Cord",
				Vector3.new(0.15, 3, 0.15),
				spot(0, 21.5, z),
				STONE,
				Enum.Material.Metal
			)
			local core =
				part(state.shell, "Core", Vector3.one * 1.1, spot(0, 19.5, z), LAMP, Enum.Material.Neon)
			core.Shape = Enum.PartType.Ball
			light(core, LAMP, 26, 0.7)
		end
	end
end

-- The placed things, kept in step with the record by id
local function syncItems(state: DenState, index: number, record: Record)
	local frame = DenSpace.frame(index)
	local glow = glowOf(record)
	local wanted: { [number]: boolean } = {}
	for _, placement in record.placed do
		local item = Dens.itemsById[placement.id]
		if item == nil then
			continue
		end
		local key =
			`{placement.id}|{placement.x}|{placement.y}|{placement.z}|{placement.r}|{placement.s}|{record.glow}`
		wanted[placement.uid] = true
		local have = state.placed[placement.uid]
		if have and have.key == key and have.model.Parent then
			continue
		end
		if have then
			have.model:Destroy()
		end
		local model = DenItems.build(item, glow, placement.s)
		model:PivotTo(
			DenSpace.spot(frame, placement.x, placement.y, placement.z)
				* CFrame.Angles(0, math.rad(placement.r), 0)
		)
		model:SetAttribute("DenUid", placement.uid)
		-- Build mode picks things up by aiming at them
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CanQuery = true
			end
		end
		model.Parent = state.items
		state.placed[placement.uid] = { model = model, key = key }
	end
	for uid, built in state.placed do
		if not wanted[uid] then
			built.model:Destroy()
			state.placed[uid] = nil
		end
	end
end

-- The carved back wall is ragged and bulges in and out at plaque height, so each
-- column (a plaque, its trim and what's mounted over it) is set onto the rock by
-- raycast: brought forward out of a bulge, or back to a wall that's further away
-- (playtest 2026-10-10: the whole trophy wall was hidden inside the rock)
local PLAQUE_Y = 11
local WALL_REACH = 14 -- the rays start this far in front of the nominal wall
local function seatTrophies(frame: CFrame, backZ: number, columns: { [number]: { BasePart } })
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local toWall = frame:VectorToWorldSpace(Vector3.new(0, 0, WALL_REACH + 12))
	for x, items in columns do
		if items[1].Parent == nil then
			continue
		end
		local face: number? = nil -- the rock nearest the room, as a z in the den
		for _, across in { -3.3, -1.6, 0, 1.6, 3.3 } do
			for _, up in { -2.2, 0, 2.5 } do
				local origin = DenSpace.spot(frame, x + across, PLAQUE_Y + up, backZ + WALL_REACH).Position
				local hit = workspace:Raycast(origin, toWall, params)
				if hit then
					face = math.max(face or -math.huge, backZ + WALL_REACH - hit.Distance)
				end
			end
		end
		local shift = if face then math.clamp(face + 0.45 - backZ, -10, 8) else 0
		if shift ~= 0 then
			local move = frame:VectorToWorldSpace(Vector3.new(0, 0, -shift))
			for _, item in items do
				item.CFrame += move
			end
		end
	end
end

local function trophyWall(state: DenState, index: number, record: Record, trophies: Trophies)
	local folder = state.trophies
	folder:ClearAllChildren()
	local frame = DenSpace.frame(index)
	local backZ = Dens.backWall[if record.level >= 2 then 2 else 1] + 2.5
	local glow = glowOf(record)
	local columns: { [number]: { BasePart } } = {}
	local function mount(x: number, item: BasePart)
		local column = columns[x] or {}
		table.insert(column, item)
		columns[x] = column
	end
	local function plaque(x: number, title: string, line: string, accent: Color3)
		local at = DenSpace.spot(frame, x, PLAQUE_Y, backZ)
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
		mount(x, board)
		mount(x, trim)
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
	end
	-- The biggest catch, with the prey's own model mounted above the plaque
	local prey = Config.Prey.byId[trophies.bestPrey]
	local catchLine = if prey
		then `{prey.name} · {string.format("%.1f", trophies.bestPreyMass)} kg`
		else "Nothing yet"
	plaque(-7, "BIGGEST CATCH", catchLine, glow)
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
		local at = DenSpace.spot(frame, -7, 14.6, backZ + 1.5) * CFrame.Angles(0, math.rad(90), 0)
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
			mount(-7, clone)
		else
			local fish =
				part(folder, "Catch", Vector3.new(1.2, 1.6, 4.5), at, prey.back, Enum.Material.SmoothPlastic)
			local shape = Instance.new("SpecialMesh")
			shape.MeshType = Enum.MeshType.Sphere
			shape.Parent = fish
			mount(-7, fish)
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
			DenSpace.spot(frame, 0, 14.4, backZ + 1) * CFrame.Angles(0, 0, math.rad(180)),
			Color3.fromRGB(236, 232, 220),
			Enum.Material.SmoothPlastic
		)
		local wedge = Instance.new("SpecialMesh")
		wedge.MeshType = Enum.MeshType.Wedge
		wedge.Parent = tooth
		mount(0, tooth)
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
			DenSpace.spot(frame, 7, 14.4, backZ + 1),
			Color3.fromRGB(40, 30, 36),
			Enum.Material.SmoothPlastic
		)
		local shape = Instance.new("SpecialMesh")
		shape.MeshType = Enum.MeshType.Sphere
		shape.Parent = beak
		mount(7, beak)
	end
	-- Terrain carved this frame doesn't answer a raycast until a later one
	task.delay(0.5, function()
		seatTrophies(frame, backZ, columns)
	end)
	-- The title over the door, inside
	if trophies.title ~= "" then
		local sign = part(
			folder,
			"Title",
			Vector3.new(10, 1.6, 0.4),
			DenSpace.spot(frame, 0, hub.denHeight - 3, 12),
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
		label.TextColor3 = glow
		label.Text = string.upper(trophies.title)
		label.Parent = gui
	end
end

-- The Coral Garden (Config/Dens garden, DenSpace.garden): a stone planter set into
-- the deck, sand inside, and a reef of corals that grows as the garden fills
-- (`fill` 0..1 by coral, `shellFill` by shells), sparkling and lit once full. The
-- owner's word on the first one: "just sticks with spheres on the table"
-- (2026-10-13), so the corals are the imported reef props where they're in, and
-- part-built shapes of the same corals where they aren't. Rebuilt on its own as it
-- grows (GardenService), so the den isn't.
type Coral = { kind: string, x: number, z: number, size: number, color: Color3, turn: number }

local REEF = {
	Color3.fromRGB(255, 112, 130),
	Color3.fromRGB(255, 156, 84),
	Color3.fromRGB(186, 112, 236),
	Color3.fromRGB(255, 212, 96),
	Color3.fromRGB(110, 214, 200),
	Color3.fromRGB(120, 170, 255),
}

-- Where the corals stand, by shape: x across the planter, z front (+) to back (-),
-- both as fractions of its half-width and half-depth; the first ones grow first
local LAYOUTS: { [string]: { Coral } } = {
	trough = {
		{ kind = "Staghorn", x = 0, z = -0.35, size = 3.6, color = REEF[1], turn = 0.4 },
		{ kind = "Fan", x = -0.55, z = -0.55, size = 3.8, color = REEF[2], turn = 0.2 },
		{ kind = "Brain", x = 0.42, z = 0.1, size = 2.0, color = REEF[4], turn = 1.1 },
		{ kind = "Sponge", x = 0.78, z = -0.4, size = 3.0, color = REEF[3], turn = 2.0 },
		{ kind = "Anemone", x = -0.25, z = 0.3, size = 1.6, color = REEF[5], turn = 0.7 },
		{ kind = "Fan", x = 0.55, z = -0.6, size = 3.2, color = REEF[6], turn = -0.3 },
		{ kind = "Staghorn", x = -0.82, z = -0.2, size = 2.8, color = REEF[3], turn = 2.4 },
		{ kind = "Anemone", x = 0.18, z = 0.45, size = 1.3, color = REEF[1], turn = 1.9 },
		{ kind = "Brain", x = -0.6, z = 0.35, size = 1.5, color = REEF[2], turn = 0.3 },
	},
	bed = {
		{ kind = "Staghorn", x = 0, z = -0.05, size = 5.2, color = REEF[1], turn = 0.2 },
		{ kind = "Fan", x = -0.35, z = -0.45, size = 5, color = REEF[2], turn = 0.5 },
		{ kind = "Brain", x = 0.4, z = 0.2, size = 2.8, color = REEF[4], turn = 1.4 },
		{ kind = "Sponge", x = 0.5, z = -0.4, size = 4.2, color = REEF[3], turn = 2.2 },
		{ kind = "Anemone", x = -0.45, z = 0.35, size = 2.2, color = REEF[5], turn = 0.9 },
		{ kind = "Fan", x = 0.3, z = -0.65, size = 4.2, color = REEF[6], turn = -0.4 },
		{ kind = "Staghorn", x = -0.62, z = -0.05, size = 3.6, color = REEF[3], turn = 2.6 },
		{ kind = "Brain", x = -0.1, z = 0.55, size = 2.0, color = REEF[2], turn = 0.4 },
		{ kind = "Anemone", x = 0.7, z = 0.15, size = 1.8, color = REEF[1], turn = 1.7 },
		{ kind = "Sponge", x = -0.25, z = -0.7, size = 3.2, color = REEF[4], turn = 0.8 },
		{ kind = "Anemone", x = 0.15, z = 0.7, size = 1.5, color = REEF[6], turn = 2.9 },
	},
}

local PROP_OF = {
	Staghorn = "StaghornCoral",
	Fan = "FanCoral",
	Brain = "BrainCoral",
	Sponge = "TubeSponge",
	Anemone = "Anemone",
}

-- A coral of `kind`, `height` tall, standing on `foot` (part-built when the prop
-- isn't imported): branching staghorn, a fan, a round brain, a cluster of tubes, a
-- fuzzy anemone
local function coral(parent: Instance, kind: string, foot: CFrame, height: number, color: Color3)
	local box = Vector3.new(height * 0.9, height, height * 0.9)
	if kind == "Brain" then
		box = Vector3.new(height * 1.3, height, height * 1.3)
	elseif kind == "Fan" then
		box = Vector3.new(height, height, height * 0.3)
	end
	local stand =
		part(parent, "Coral", box, foot * CFrame.new(0, box.Y / 2, 0), color, Enum.Material.SmoothPlastic)
	stand.Transparency = 1
	local template = Props.template("WorldProps", PROP_OF[kind] or "")
	if template then
		local prop = Props.dress(stand, PROP_OF[kind], { cframe = stand.CFrame, size = box })
		if prop then
			Props.tint(prop, color:Lerp(Color3.new(1, 1, 1), 0.35))
			return
		end
	end
	local shade = color:Lerp(Color3.new(0, 0, 0), 0.18)
	if kind == "Staghorn" then
		-- A trunk that forks twice, every branch tapering, tips paler
		local function branch(from: CFrame, length: number, thick: number, depth: number)
			local tip = from * CFrame.new(0, length, 0)
			local limb = part(
				parent,
				"Branch",
				Vector3.new(length, thick, thick),
				from * CFrame.new(0, length / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
				if depth == 0 then color:Lerp(Color3.new(1, 1, 1), 0.25) else color,
				Enum.Material.SmoothPlastic
			)
			limb.Shape = Enum.PartType.Cylinder
			if depth > 0 then
				for i = 1, 2 do
					local spread = math.rad(28 + depth * 4) * (if i == 1 then 1 else -1)
					branch(
						tip * CFrame.Angles(0, i * 1.9 + depth, 0) * CFrame.Angles(spread, 0, 0),
						length * 0.72,
						thick * 0.72,
						depth - 1
					)
				end
			end
		end
		branch(foot, height * 0.38, height * 0.14, 2)
	elseif kind == "Fan" then
		local fan = part(
			parent,
			"Fan",
			Vector3.new(0.18, height, height),
			foot * CFrame.new(0, height * 0.45, 0) * CFrame.Angles(0, math.rad(90), 0),
			color,
			Enum.Material.Fabric
		)
		fan.Shape = Enum.PartType.Cylinder
		part(
			parent,
			"Stem",
			Vector3.new(0.35, height * 0.25, 0.35),
			foot * CFrame.new(0, height * 0.12, 0),
			shade,
			Enum.Material.SmoothPlastic
		)
	elseif kind == "Brain" then
		local brain = part(
			parent,
			"Brain",
			Vector3.new(height * 1.25, height, height * 1.25),
			foot * CFrame.new(0, height * 0.42, 0),
			color,
			Enum.Material.Pebble
		)
		brain.Shape = Enum.PartType.Ball
	elseif kind == "Sponge" then
		for i, t in { { 0, 0, 1 }, { 0.38, 0.1, 0.72 }, { -0.3, 0.32, 0.6 } } do
			local h = height * t[3]
			local tube = part(
				parent,
				"Tube",
				Vector3.new(h, height * 0.26, height * 0.26),
				foot
					* CFrame.new(t[1] * height * 0.5, h / 2, t[2] * height * 0.5)
					* CFrame.Angles(0, 0, math.rad(90)),
				if i == 1 then color else shade,
				Enum.Material.SmoothPlastic
			)
			tube.Shape = Enum.PartType.Cylinder
			local mouth = part(
				parent,
				"Mouth",
				Vector3.new(0.05, height * 0.18, height * 0.18),
				foot
					* CFrame.new(t[1] * height * 0.5, h + 0.02, t[2] * height * 0.5)
					* CFrame.Angles(0, 0, math.rad(90)),
				Color3.fromRGB(30, 18, 40),
				Enum.Material.SmoothPlastic
			)
			mouth.Shape = Enum.PartType.Cylinder
		end
	else -- Anemone
		local stalk = part(
			parent,
			"Stalk",
			Vector3.new(height * 0.45, height * 0.5, height * 0.5),
			foot * CFrame.new(0, height * 0.22, 0) * CFrame.Angles(0, 0, math.rad(90)),
			shade,
			Enum.Material.SmoothPlastic
		)
		stalk.Shape = Enum.PartType.Cylinder
		local crown = part(
			parent,
			"Crown",
			Vector3.new(height * 1.1, height * 0.6, height * 1.1),
			foot * CFrame.new(0, height * 0.55, 0),
			color,
			Enum.Material.Grass
		)
		crown.Shape = Enum.PartType.Ball
	end
end

function DenBuilder.garden(index: number, record: Record, fill: number, shellFill: number)
	local state = stateOf(index)
	local old = state.folder:FindFirstChild("Garden")
	if old then
		old:Destroy()
	end
	local spot = DenSpace.garden(record.level)
	local s = DenSpace.storey(spot.storey)
	local frame = DenSpace.frame(index)
	local glow = glowOf(record)
	local model = Instance.new("Model")
	model.Name = "Garden"
	local center = DenSpace.spot(frame, 0, s.deck, spot.z)
	local hw, hd = spot.width / 2, spot.depth / 2
	local sandTop = -0.35
	if spot.shape == "trough" then
		-- A long stone planter against the back wall: a lip at the deck's height, a
		-- glowing seam along its front, sand a little under the lip
		part(
			model,
			"Basin",
			Vector3.new(spot.width, 2.4, spot.depth),
			center * CFrame.new(0, -1.3, 0),
			STONE,
			Enum.Material.Slate
		)
		for _, side in { -1, 1 } do
			part(
				model,
				"Lip",
				Vector3.new(spot.width + 0.6, 0.7, 0.6),
				center * CFrame.new(0, 0.1, side * (hd + 0.05)),
				STONE:Lerp(Color3.new(1, 1, 1), 0.08),
				Enum.Material.Slate
			)
			local cap = part(
				model,
				"End",
				Vector3.new(0.7, spot.depth + 0.6, spot.depth + 0.6),
				center * CFrame.new(side * (hw + 0.1), 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
				STONE:Lerp(Color3.new(1, 1, 1), 0.08),
				Enum.Material.Slate
			)
			cap.Shape = Enum.PartType.Cylinder
		end
		part(
			model,
			"Seam",
			Vector3.new(spot.width, 0.14, 0.2),
			center * CFrame.new(0, 0.48, -(hd + 0.36)),
			glow,
			Enum.Material.Neon
		)
		part(
			model,
			"Sand",
			Vector3.new(spot.width - 0.4, 0.3, spot.depth - 0.4),
			center * CFrame.new(0, sandTop - 0.15, 0),
			Color3.fromRGB(226, 208, 168),
			Enum.Material.Sand
		)
	else
		-- A sunken oval bed: a ring of rounded stones, a glow under them, sand below
		-- the deck
		-- (an oval: a flattened sphere mesh, since a Cylinder part is always round)
		local function oval(
			name: string,
			thick: number,
			grow: number,
			y: number,
			color: Color3,
			material: Enum.Material
		)
			local disc = part(
				model,
				name,
				Vector3.new(spot.width + grow, thick, spot.depth + grow),
				center * CFrame.new(0, y, 0),
				color,
				material
			)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = disc
		end
		oval("Sand", 0.6, 0, sandTop - 0.3, Color3.fromRGB(226, 208, 168), Enum.Material.Sand)
		oval("Glow", 0.2, 0.8, -0.2, glow, Enum.Material.Neon)
		local stones = 22
		for i = 1, stones do
			local a = (i - 0.5) / stones * 2 * math.pi
			local x, z = math.cos(a) * (hw + 0.3), math.sin(a) * (hd + 0.3)
			local big = 1.4 + (i % 3) * 0.35
			local stone = part(
				model,
				"Stone",
				Vector3.new(big * 1.3, big * 0.8, big),
				center
					* CFrame.new(x, big * 0.18, z)
					* CFrame.Angles(0, -a + (i % 2) * 0.4, (i % 3 - 1) * 0.12),
				STONE:Lerp(Color3.new(0, 0, 0), (i % 4) * 0.05),
				Enum.Material.Slate
			)
			stone.Shape = Enum.PartType.Ball
			stone.CanCollide = true
		end
		-- A couple of boulders in the bed among the corals
		for i, at in { Vector2.new(-0.15, 0.25), Vector2.new(0.62, -0.25) } do
			local rock = part(
				model,
				"Rock",
				Vector3.new(1.8, 1.2, 1.5) * (1 + i * 0.25),
				center * CFrame.new(at.X * hw, sandTop + 0.3, at.Y * hd) * CFrame.Angles(0.2, i, 0.1),
				STONE:Lerp(Color3.new(0, 0, 0), 0.12),
				Enum.Material.Rock
			)
			rock.Shape = Enum.PartType.Ball
		end
	end
	-- The reef grows one coral after another; even an empty garden shows young ones
	local layout = LAYOUTS[spot.shape] or LAYOUTS.trough
	for i, c in layout do
		local grown = math.clamp(fill * #layout - (i - 1), 0, 1)
		local height = c.size * (0.3 + 0.7 * grown)
		-- (the center's own +z runs back into the rock, the layout's z toward the hub)
		local foot = center
			* CFrame.new(c.x * hw * 0.85, sandTop, -c.z * hd * 0.8)
			* CFrame.Angles(0, c.turn, 0)
		coral(model, c.kind, foot, height, c.color)
	end
	-- Shells washed up on the sand
	for i = 1, math.floor(shellFill * 6 + 0.001) do
		local a = i * 2.3
		local shell = part(
			model,
			"Shell",
			Vector3.new(0.8, 0.3, 0.7),
			center
				* CFrame.new(math.cos(a) * hw * 0.6, sandTop + 0.1, math.sin(a) * hd * 0.55)
				* CFrame.Angles(0, a, 0),
			Color3.fromRGB(236, 230, 214),
			Enum.Material.SmoothPlastic
		)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = shell
	end
	-- Full: it sparkles and glows, so a glance says "collect me"
	local anchor = part(
		model,
		"Anchor",
		Vector3.one * 0.5,
		center * CFrame.new(0, 2, 0),
		glow,
		Enum.Material.SmoothPlastic
	)
	anchor.Transparency = 1
	if fill >= 0.999 then
		light(anchor, glow, 18, 1.5)
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Rate = 9
		sparkle.Lifetime = NumberRange.new(1.2, 2.2)
		sparkle.Speed = NumberRange.new(0.5, 1.5)
		sparkle.SpreadAngle = Vector2.new(40, 40)
		sparkle.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.4),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkle.LightEmission = 1
		sparkle.Color = ColorSequence.new(glow)
		sparkle.Shape = Enum.ParticleEmitterShape.Box
		anchor.Size = Vector3.new(spot.width * 0.8, 1, spot.depth * 0.8)
		sparkle.Parent = anchor
	else
		light(anchor, glow, 12, 0.5 + fill * 0.6)
	end
	model.Parent = state.folder
end

-- Builds (or brings up to date) den `index` from its owner's record (`fill` and
-- `shellFill`: the Coral Garden's, 0..1)
function DenBuilder.build(
	index: number,
	record: Record,
	trophies: Trophies,
	fill: number?,
	shellFill: number?
)
	local state = stateOf(index)
	if state.carved ~= record.level then
		Cave.apply(workspace.Terrain, DenCarve.ops(index, record.level))
		state.carved = record.level
	end
	local shellKey = `{record.level}|{record.floor}|{record.glow}`
	if state.shellKey ~= shellKey then
		buildShell(state, index, record)
		state.shellKey = shellKey
	end
	syncItems(state, index, record)
	local trophyKey =
		`{record.level}|{record.glow}|{trophies.bestPrey}|{trophies.bestPreyMass}|{trophies.teeth}|{trophies.beaks}|{trophies.title}`
	if state.trophyKey ~= trophyKey then
		trophyWall(state, index, record, trophies)
		state.trophyKey = trophyKey
	end
	if fill then
		DenBuilder.garden(index, record, fill, shellFill or 0)
	end
end

-- Only the placed things (Build mode)
function DenBuilder.items(index: number, record: Record)
	syncItems(stateOf(index), index, record)
end

-- Takes a den's base down; with `refill` the rock goes back to a plain Nook
function DenBuilder.clear(index: number, refill: boolean)
	local state = states[index]
	if state then
		state.folder:Destroy()
		states[index] = nil
	end
	if refill then
		Cave.apply(workspace.Terrain, DenCarve.reset(index))
	end
end

return DenBuilder
