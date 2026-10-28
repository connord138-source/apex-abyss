--!strict
-- Builds a den in the world from its owner's record (Config/Dens, Shared/DenSpace):
--  * the rock (DenCarve), carved again only when the level changes;
--  * the shell: a flagstone deck on every storey in the den's floor style, stone
--    curbs round the shafts, pillars with sconces down the big rooms, and orb lamps
--    hanging from the vaults, lit in the den's glow;
--  * the things placed in Build mode, kept in step with the record by id;
--  * the trophy wall on the main room's back wall (the biggest catch, boss teeth and
--    beaks), under the den's title board (NAME'S SANCTUM, the title worn, the den's
--    hearts and, for last week's top 3 Best Dens, a gold frame: HeartService);
--  * the Coral Garden (a planter along the back wall, then a bed in the Hall's
--    middle), its corals growing as it fills.
-- Everything is rebuilt from the saved record, so it follows its owner from server
-- to server; when a den changes hands the rock goes back to a Nook first.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DensConfig = require(ReplicatedStorage.Shared.Config.Dens)
local DenItems = require(ReplicatedStorage.Shared.DenItems)
local DenSpace = require(ReplicatedStorage.Shared.DenSpace)
local HeartGlyph = require(ReplicatedStorage.Shared.HeartGlyph)
local Hearts = require(ReplicatedStorage.Shared.Hearts)
local Cave = require(script.Parent.Cave)
local DenCarve = require(script.Parent.DenCarve)
local DenWings = require(script.Parent.DenWings)

local Dens = Config.Dens

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
	wings: { [string]: string }?, -- wing slot id → wing id (Config/Dens wings)
	open: boolean?, -- Open Plan
	tanks: DenWings.Stock?, -- the aquarium's fish, by tank id
}

export type Trophies = {
	bestPrey: string,
	bestPreyMass: number,
	teeth: number,
	beaks: number,
	title: string,
	owner: string,
	gallery: DenWings.Gallery?, -- the Trophy Gallery's records
}

-- The record's shape (Shared/DenSpace): its level, wings and Open Plan
local function shapeOf(record: Record): DenSpace.Shape
	return { level = record.level, wings = record.wings, open = record.open }
end
DenBuilder.shapeOf = shapeOf

type Built = { model: Model, key: string }
-- The title board's parts that change with den hearts (paintSign)
type Sign = { name: TextLabel, title: TextLabel?, badge: Frame, count: TextLabel, gold: { BasePart } }
type DenState = {
	folder: Folder,
	shell: Folder,
	items: Folder,
	trophies: Folder,
	wings: Folder,
	tanks: Folder,
	carved: string?, -- the shape the rock is carved for (DenSpace.key)
	shellKey: string?, -- shape, floor and glow the shell was built for
	placed: { [number]: Built },
	trophyKey: string?,
	wingKey: string?,
	tankKey: string?,
	hearts: number, -- den hearts (HeartService, DenBuilder.setHearts)
	framed: boolean, -- the Best Dens frame this week
	sign: Sign?,
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
		wings = sub("Wings"),
		tanks = sub("Tanks"),
		carved = if existing then existing.carved else nil,
		placed = {},
		hearts = if existing then existing.hearts else 0,
		framed = if existing then existing.framed else false,
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
	local level = shapeOf(record)
	local glow = glowOf(record)
	local style = Dens.floorsById[record.floor] or Dens.floors[1]
	local function spot(x: number, y: number, z: number): CFrame
		return DenSpace.spot(frame, x, y, z)
	end
	-- Decks: flagstones of mixed sizes with thin dark joints between them, each a
	-- slab down to the rock floor under it (Config/Dens storeys); the obsidian floor
	-- glows in its joints
	for storey = 1, DenSpace.storeys(level) do
		local s = DenSpace.storey(storey)
		local thick = s.deck - s.floor + 0.5
		for _, tile in DenSpace.tiles(level, storey, 10) do
			local w, d = tile.x1 - tile.x0, tile.z0 - tile.z1
			local cx, cz = (tile.x0 + tile.x1) / 2, (tile.z0 + tile.z1) / 2
			local h = hash(tile.x0, tile.z1, storey)
			local base = style.colors[h % #style.colors + 1]
			local deck = part(
				state.shell,
				"Deck",
				Vector3.new(w - 0.14, thick, d - 0.14),
				spot(cx, s.deck - thick / 2, cz),
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
	-- Curbs round the shafts down, lining the mouth to below the rock floor, a
	-- glowing lip on their inside, and a light where each comes out of the ceiling
	-- below
	for _, shaft in DenSpace.shafts(level) do
		local from = DenSpace.storey(shaft.from)
		local deck = from.deck
		local radius = shaft.radius + 0.7
		local count = 20
		local length = 2 * math.pi * radius / count + 0.15
		local depth = deck + 1 - (from.floor - 1)
		for i = 1, count do
			local around = spot(0, deck, shaft.z) * CFrame.Angles(0, (i - 0.5) / count * 2 * math.pi, 0)
			local curb = part(
				state.shell,
				"Curb",
				Vector3.new(length, depth, 1.3),
				around * CFrame.new(0, 1 - depth / 2, -radius),
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
	-- The Haul Pool sits in a stone basin with a rim (the pool itself is a glowing
	-- disc a stud thick: WorldService)
	do
		local s = DenSpace.storey(1)
		local r = DenSpace.POOL_RADIUS
		local fill = 0.45 - (s.floor - 0.5)
		local basin = part(
			state.shell,
			"PoolBasin",
			Vector3.new(fill, (r + 0.85) * 2, (r + 0.85) * 2),
			spot(0, 0.45 - fill / 2, DenSpace.POOL_Z) * CFrame.Angles(0, 0, math.rad(90)),
			STONE:Lerp(Color3.new(0, 0, 0), 0.25),
			Enum.Material.Slate
		)
		basin.Shape = Enum.PartType.Cylinder
		local count = 18
		local radius = r + 0.45
		local length = 2 * math.pi * radius / count + 0.12
		for i = 1, count do
			local around = spot(0, s.deck, DenSpace.POOL_Z)
				* CFrame.Angles(0, (i - 0.5) / count * 2 * math.pi, 0)
			part(
				state.shell,
				"PoolRim",
				Vector3.new(length, 1.1, 0.9),
				around * CFrame.new(0, -0.15, -radius),
				STONE:Lerp(Color3.new(1, 1, 1), 0.06),
				Enum.Material.Slate
			)
		end
	end
	-- Pillars down the big rooms, up into the vault, every other one with a sconce
	local roomsById: { [string]: DensConfig.Room } = {}
	for _, room in DenSpace.rooms(level) do
		roomsById[room.id] = room
	end
	for n, pillar in DenSpace.pillars(level) do
		local room = roomsById[pillar.room]
		if room == nil then
			continue
		end
		local s = DenSpace.storey(room.storey)
		local height = DenSpace.vaultAt(room, math.abs(pillar.x), pillar.z) + 1.5
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
		local inward = if pillar.x > (room.cx or 0) then -1 else 1
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
	-- Orb lamps hanging from the arch down every storey, one every 20 studs down the
	-- middle, and in rooms wider than 70 (the v4 Nook on) a row down each side as
	-- well. Each cord stops short of the arch, then reaches up to the real rock by a
	-- ray once the Terrain answers (it poked out through the den's roof: PC
	-- 2026-10-16 round 2)
	local cords: { Part } = {}
	for storey = 1, DenSpace.storeys(level) do
		local s = DenSpace.storey(storey)
		-- (the house's own rooms: the wings hang their own lamps, DenWings)
		local rooms: { DensConfig.Room } = {}
		for _, room in DenSpace.rooms(level, storey) do
			if room.wing == nil then
				table.insert(rooms, room)
			end
		end
		local front, back = -math.huge, math.huge
		for _, room in rooms do
			front = math.max(front, room.z0)
			back = math.min(back, room.z1)
		end
		local z = front - 10
		while z > back + 4 do
			local widest: DensConfig.Room? = nil
			for _, room in rooms do
				if z <= room.z0 and z >= room.z1 and (widest == nil or room.x > widest.x) then
					widest = room
				end
			end
			if widest then
				local across = { 0 }
				if widest.x > 35 then
					across = { -widest.x * 0.5, 0, widest.x * 0.5 }
				end
				for _, x in across do
					-- None in a shaft's mouth: there's no rock above it to hang from
					-- (PC 2026-10-17, D3b: the Hall's middle lamp hung in the shaft)
					local inMouth = false
					for _, shaft in DenSpace.shafts(level) do
						if shaft.to == storey and (x * x + (z - shaft.z) ^ 2) < (shaft.radius + 4) ^ 2 then
							inMouth = true
						end
					end
					if inMouth then
						continue
					end
					local top = s.deck + DenSpace.vaultAt(widest, math.abs(x))
					table.insert(
						cords,
						part(
							state.shell,
							"Cord",
							Vector3.new(0.15, 2.3, 0.15),
							spot(x, top - 2.15, z),
							STONE,
							Enum.Material.Metal
						)
					)
					local orb = part(
						state.shell,
						"Orb",
						Vector3.one * 2.2,
						spot(x, top - 4.4, z),
						glow:Lerp(Color3.new(1, 1, 1), 0.5),
						Enum.Material.Glass
					)
					orb.Shape = Enum.PartType.Ball
					orb.Transparency = 0.2
					local core = part(
						state.shell,
						"Core",
						Vector3.one,
						spot(x, top - 4.4, z),
						LAMP,
						Enum.Material.Neon
					)
					core.Shape = Enum.PartType.Ball
					light(core, LAMP, 40, if x == 0 then 0.8 else 0.6)
				end
			end
			z -= 20
		end
	end
	task.delay(0.5, function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		for _, cord in cords do
			if cord.Parent == nil then
				continue
			end
			local low = cord.Position - Vector3.new(0, cord.Size.Y / 2, 0)
			local hit = workspace:Raycast(low, Vector3.new(0, 12, 0), params)
			if hit then
				local length = math.max(hit.Position.Y + 0.3 - low.Y, 0.5)
				cord.Size = Vector3.new(0.15, length, 0.15)
				cord.CFrame = CFrame.new(low + Vector3.new(0, length / 2, 0))
			end
		end
	end)
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
local TITLE_Y = 20.5 -- the den's title board, over the trophies
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

-- Den hearts on the title board: the heart and count at its right end once the den
-- has a heart (the lines give it room), and the gold frame while it's worn
local SIGN_HEART = Color3.fromRGB(255, 96, 122)
local SIGN_GOLD = Color3.fromRGB(236, 172, 44)
local SIGN_GEM = Color3.fromRGB(255, 232, 150)
local function paintSign(state: DenState)
	local sign = state.sign
	if sign == nil or sign.badge.Parent == nil then
		return
	end
	local shown = state.hearts > 0
	sign.badge.Visible = shown
	sign.count.Text = Hearts.short(state.hearts)
	local width = if shown then 0.72 else 0.92
	sign.name.Size = UDim2.fromScale(width, sign.name.Size.Y.Scale)
	local title = sign.title
	if title then
		title.Size = UDim2.fromScale(width, title.Size.Y.Scale)
	end
	for _, piece in sign.gold do
		piece.Transparency = if state.framed then 0 else 1
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
			Enum.Material.SmoothPlastic
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
	-- The den's title board over the trophies: a lacquered board in a brass frame, in
	-- the same style as the doorways' nameplates (SmoothPlastic: a toon material's
	-- tile blurred a small sign). It hung over the way out until 2026-10-20, when the
	-- way out took the den's doorway style (DenDoor.exit), whose nameplate reaches
	-- near the vault. It reads the owner's name and the den's level (CONNOR'S
	-- SANCTUM), the title they wear under it, and since den hearts (2026-10-28) the
	-- den's hearts at its right end and, for last week's top 3 Best Dens, a bright
	-- gold frame outside the brass (paintSign shows them; DenBuilder.setHearts).
	local worn = trophies.title ~= ""
	local at = DenSpace.spot(frame, 0, TITLE_Y, backZ)
	local width, height = 16, if worn then 3.6 else 2.8
	local sign = part(
		folder,
		"Title",
		Vector3.new(width, height, 0.5),
		at,
		Color3.fromRGB(20, 88, 102),
		Enum.Material.SmoothPlastic
	)
	mount(0, sign)
	local brass = Color3.fromRGB(214, 160, 70)
	for _, y in { -1, 1 } do
		mount(
			0,
			part(
				folder,
				"TitleTrim",
				Vector3.new(width + 0.4, 0.4, 0.35),
				at * CFrame.new(0, y * height / 2, -0.2),
				brass,
				Enum.Material.SmoothPlastic
			)
		)
	end
	for _, x in { -1, 1 } do
		mount(
			0,
			part(
				folder,
				"TitleTrim",
				Vector3.new(0.4, height + 0.4, 0.35),
				at * CFrame.new(x * width / 2, 0, -0.2),
				brass,
				Enum.Material.SmoothPlastic
			)
		)
	end
	-- The Best Dens frame: built with the board, shown only while it's worn
	local gold: { BasePart } = {}
	local gx, gy = width / 2 + 0.55, height / 2 + 0.55
	local function goldPiece(name: string, size: Vector3, cframe: CFrame, color: Color3, ball: boolean?)
		local piece = part(folder, name, size, cframe, color, Enum.Material.Neon)
		if ball then
			piece.Shape = Enum.PartType.Ball
		end
		piece.Transparency = 1
		mount(0, piece)
		table.insert(gold, piece)
	end
	for _, y in { -1, 1 } do
		goldPiece(
			"TitleFrame",
			Vector3.new(gx * 2 + 0.4, 0.4, 0.45),
			at * CFrame.new(0, y * gy, -0.25),
			SIGN_GOLD
		)
	end
	for _, x in { -1, 1 } do
		goldPiece(
			"TitleFrame",
			Vector3.new(0.4, gy * 2 + 0.4, 0.45),
			at * CFrame.new(x * gx, 0, -0.25),
			SIGN_GOLD
		)
		for _, y in { -1, 1 } do
			goldPiece("TitleGem", Vector3.one * 1, at * CFrame.new(x * gx, y * gy, -0.4), SIGN_GEM, true)
		end
	end
	goldPiece(
		"TitleGem",
		Vector3.new(1.1, 1.1, 0.45),
		at * CFrame.new(0, gy + 0.4, -0.4) * CFrame.Angles(0, 0, math.rad(45)),
		SIGN_GEM
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Parent = sign
	local stroke = Color3.fromRGB(8, 34, 42)
	local function line(name: string, text: string, y: number, h: number, color: Color3): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.04, y)
		label.Size = UDim2.fromScale(0.92, h)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		-- (one line: spaces made non-breaking, so a long name shrinks, never wraps)
		label.Text = (string.gsub(string.upper(text), " ", "\u{00A0}"))
		label.Parent = gui
		local edge = Instance.new("UIStroke")
		edge.Color = stroke
		edge.Thickness = 3
		edge.Parent = label
		return label
	end
	local levelName = (Dens.levels[record.level] or Dens.levels[1]).name
	local name = line(
		"Name",
		`{trophies.owner}'S {levelName}`,
		if worn then 0.07 else 0.1,
		if worn then 0.5 else 0.8,
		if worn then Color3.fromRGB(255, 244, 222) else glow
	)
	local titleLabel = if worn then line("Worn", trophies.title, 0.58, 0.36, glow) else nil
	-- The hearts: a drawn heart (Shared/HeartGlyph) and the count, at the right end
	local badge = Instance.new("Frame")
	badge.Name = "Hearts"
	badge.BackgroundTransparency = 1
	badge.AnchorPoint = Vector2.new(1, 0.5)
	badge.Position = UDim2.fromScale(0.97, 0.5)
	badge.Size = UDim2.fromScale(0.2, if worn then 0.5 else 0.7)
	badge.Visible = false
	badge.Parent = gui
	local heart = HeartGlyph.draw(badge, UDim2.fromScale(0.4, 0.96), SIGN_HEART, stroke)
	heart.AnchorPoint = Vector2.new(0, 0.5)
	heart.Position = UDim2.fromScale(0, 0.5)
	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.BackgroundTransparency = 1
	count.AnchorPoint = Vector2.new(0, 0.5)
	count.Position = UDim2.fromScale(0.42, 0.5)
	count.Size = UDim2.fromScale(0.58, 0.96)
	count.Font = Enum.Font.GothamBlack
	count.TextScaled = true
	count.TextXAlignment = Enum.TextXAlignment.Left
	count.TextColor3 = Color3.fromRGB(255, 208, 104)
	count.Parent = badge
	local countEdge = Instance.new("UIStroke")
	countEdge.Color = stroke
	countEdge.Thickness = 2.5
	countEdge.Parent = count
	state.sign = { name = name, title = titleLabel, badge = badge, count = count, gold = gold }
	paintSign(state)
	-- Terrain carved this frame doesn't answer a raycast until a later one
	task.delay(0.5, function()
		seatTrophies(frame, backZ, columns)
	end)
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

-- A coral of `kind`, `height` tall, standing on `foot`: the den things' reef pieces
-- (Shared/DenItems: the imported reef props where they're in, else part-built
-- staghorn, fans, brains, tube sponges and anemones). The garden's sponges are a
-- clump of three tubes.
local function coral(parent: Instance, kind: string, foot: CFrame, height: number, color: Color3, rng: Random)
	DenItems.piece(parent, if kind == "Sponge" then "Sponges" else kind, foot, height, color, rng)
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
		-- (down to the rock floor under the deck)
		local depth = s.deck - 0.1 - s.floor
		part(
			model,
			"Basin",
			Vector3.new(spot.width, depth, spot.depth),
			center * CFrame.new(0, -0.1 - depth / 2, 0),
			STONE,
			Enum.Material.SmoothPlastic
		)
		for _, side in { -1, 1 } do
			part(
				model,
				"Lip",
				Vector3.new(spot.width + 0.6, 0.7, 0.6),
				center * CFrame.new(0, 0.1, side * (hd + 0.05)),
				STONE:Lerp(Color3.new(1, 1, 1), 0.08),
				Enum.Material.SmoothPlastic
			)
			local cap = part(
				model,
				"End",
				Vector3.new(0.7, spot.depth + 0.6, spot.depth + 0.6),
				center * CFrame.new(side * (hw + 0.1), 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
				STONE:Lerp(Color3.new(1, 1, 1), 0.08),
				Enum.Material.SmoothPlastic
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
			Enum.Material.SmoothPlastic
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
		-- Stone under the bed, down to the rock floor
		local depth = s.deck - 0.9 - s.floor
		part(
			model,
			"Footing",
			Vector3.new(spot.width + 1.4, depth, spot.depth + 1.4),
			center * CFrame.new(0, -0.9 - depth / 2, 0),
			STONE:Lerp(Color3.new(0, 0, 0), 0.2),
			Enum.Material.SmoothPlastic
		)
		oval("Sand", 0.6, 0, sandTop - 0.3, Color3.fromRGB(226, 208, 168), Enum.Material.SmoothPlastic)
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
				Enum.Material.SmoothPlastic
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
				Enum.Material.SmoothPlastic
			)
			rock.Shape = Enum.PartType.Ball
		end
	end
	-- The reef grows one coral after another; even an empty garden shows young ones
	local layout = LAYOUTS[spot.shape] or LAYOUTS.trough
	local rng = Random.new(index * 977 + record.level)
	for i, c in layout do
		local grown = math.clamp(fill * #layout - (i - 1), 0, 1)
		-- (1.3 times the v3 corals: the planters grew with the rooms, 2026-10-18)
		local height = c.size * 1.3 * (0.3 + 0.7 * grown)
		-- (the center's own +z runs back into the rock, the layout's z toward the hub)
		local foot = center
			* CFrame.new(c.x * hw * 0.85, sandTop, -c.z * hd * 0.8)
			* CFrame.Angles(0, c.turn, 0)
		coral(model, c.kind, foot, height, c.color, rng)
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
	local shape = shapeOf(record)
	local shapeKey = DenSpace.key(shape)
	if state.carved ~= shapeKey then
		Cave.apply(workspace.Terrain, DenCarve.ops(index, shape))
		state.carved = shapeKey
	end
	-- Clients read which shafts this den has (SwimController's shaft lift)
	state.folder:SetAttribute("Level", record.level)
	state.folder:SetAttribute("Shape", shapeKey)
	local shellKey = `{shapeKey}|{record.floor}|{record.glow}`
	if state.shellKey ~= shellKey then
		buildShell(state, index, record)
		state.shellKey = shellKey
	end
	syncItems(state, index, record)
	-- The wings' dressing, and the aquarium's tanks
	local gallery: DenWings.Gallery = trophies.gallery
		or {
			biggest = nil,
			byRarity = {},
			teeth = trophies.teeth,
			beaks = trophies.beaks,
			title = trophies.title,
		}
	local galleryKey = ""
	if gallery.biggest then
		galleryKey ..= `{gallery.biggest.prey}{gallery.biggest.rarity}{gallery.biggest.kg}`
	end
	for rarity, catch in gallery.byRarity do
		galleryKey ..= `|{rarity}{catch.prey}{catch.kg}`
	end
	local wingKey = `{shellKey}|{gallery.teeth}|{gallery.beaks}|{galleryKey}`
	if state.wingKey ~= wingKey then
		state.wings:ClearAllChildren()
		DenWings.build(state.wings, index, DenSpace.frame(index), shape, glowOf(record), gallery)
		state.wingKey = wingKey
	end
	local stock = record.tanks or {}
	local tankKey = shellKey
	for _, tank in DenSpace.tanks(shape) do
		local fish = stock[tank.id]
		tankKey ..= `|{tank.id}={if fish then fish.prey .. fish.rarity else ""}`
	end
	if state.tankKey ~= tankKey then
		state.tanks:ClearAllChildren()
		DenWings.tanks(state.tanks, DenSpace.frame(index), shape, glowOf(record), stock)
		state.tankKey = tankKey
	end
	local trophyKey =
		`{record.level}|{record.glow}|{trophies.bestPrey}|{trophies.bestPreyMass}|{trophies.teeth}|{trophies.beaks}|{trophies.title}|{trophies.owner}`
	if state.trophyKey ~= trophyKey then
		trophyWall(state, index, record, trophies)
		state.trophyKey = trophyKey
	end
	if fill then
		DenBuilder.garden(index, record, fill, shellFill or 0)
	end
end

-- Den `index`'s hearts and whether its title board wears the Best Dens frame this
-- week (HeartService); kept for the board when it's built again
function DenBuilder.setHearts(index: number, hearts: number, framed: boolean)
	local state = stateOf(index)
	state.hearts = hearts
	state.framed = framed
	paintSign(state)
end

-- Only the placed things (Build mode)
function DenBuilder.items(index: number, record: Record)
	syncItems(stateOf(index), index, record)
end

-- Takes a den's base down; with `refill` its block of rock goes too (it's carved
-- again for the den's next owner)
function DenBuilder.clear(index: number, refill: boolean)
	local state = states[index]
	if state then
		state.folder:Destroy()
		states[index] = nil
	end
	if refill then
		Cave.apply(workspace.Terrain, DenCarve.clear(index))
	end
end

return DenBuilder
