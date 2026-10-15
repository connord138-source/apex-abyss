--!strict
-- Chum and the Whale Fall on this client (Config/Chum, ChumService): draws each
-- cloud's chunks on their shared paths (Shared/Chum) with a murky red haze, the
-- Whale Fall's carcass sinking to the floor, and eats chunks the moment they're in
-- reach of the mouth (sucked in like shrimp, no button), telling the server in small
-- batches. A chunk the server doesn't confirm comes back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Chum = require(ReplicatedStorage.Shared.Chum)
local Config = require(ReplicatedStorage.Shared.Config)
local PropParts = require(ReplicatedStorage.Shared.PropParts)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.Sfx)
local SwimController = require(script.Parent.SwimController)

local Forage = Config.Forage
local tune = Config.Chum

local ChumController = {
	-- (kg, position) we ate a chunk (the HUD pops a number)
	ate = Signal.new(),
}

local DRAW_RANGE = 520 -- clouds further from the camera hold still
local SUCK_SECONDS = 0.12
local CONFIRM_SECONDS = 1.5
local SEND_INTERVAL = 0.06
local MEAT = Color3.fromRGB(138, 34, 40)
local FAT = Color3.fromRGB(190, 112, 104)
local MURK = Color3.fromRGB(110, 26, 30)
local CARCASS = Color3.fromRGB(86, 96, 108)
local BELLY = Color3.fromRGB(148, 156, 162)
local BONE = Color3.fromRGB(226, 220, 204)

type Piece = {
	parts: { BasePart },
	offsets: { CFrame },
	sizes: { Vector3 },
	hidden: boolean,
	backAt: number, -- shared clock it's back (math.huge: gone)
	pendingUntil: number,
	suckFrom: Vector3?,
	suckStart: number,
}

type Drawn = {
	cloud: Chum.Cloud,
	folder: Folder,
	pieces: { Piece },
	murk: Part,
	emitter: ParticleEmitter,
	carcass: Model?,
	yaw: number,
	crushed: { [BasePart]: number }, -- dressing hidden under a settled carcass (its old modifier)
	crushAt: number,
	rim: Highlight?, -- a deep floor's carcass: a faint outline through the haze
}

local drawn: { [number]: Drawn } = {}
local batch: { { number } } = {}
local lastSend = 0
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
local warn: { at: Vector3, startsAt: number, biome: string }? = nil
local root: Folder

local function ellipsoid(parent: Instance, color: Color3, size: Vector3, name: string?): Part
	local part = Instance.new("Part")
	part.Name = name or "Piece"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	part.Size = size
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.Parent = parent
	return part
end

-- A chunk: a lump of meat with a pale fatty side
local function chunkPieces(parent: Instance, m: number, seed: number): Piece
	local s = Chum.size(m)
	local rng = Random.new(seed)
	local meat = ellipsoid(parent, MEAT, Vector3.new(s, s * 0.7, s * 0.85))
	local fat = ellipsoid(parent, FAT, Vector3.new(s * 0.55, s * 0.4, s * 0.5))
	local turn = CFrame.Angles(rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3), 0)
	return {
		parts = { meat, fat },
		offsets = { turn, turn * CFrame.new(s * 0.28, s * 0.12, 0) },
		sizes = { meat.Size, fat.Size },
		hidden = false,
		backAt = 0,
		pendingUntil = 0,
		suckFrom = nil,
		suckStart = 0,
	}
end

-- The whale: the imported prop, or a part-built carcass with a bitten flank and
-- bare ribs (lengthwise along X, head at +X)
local function carcass(parent: Instance, deep: boolean): Model
	local model = Instance.new("Model")
	model.Name = "WhaleFall"
	local L = tune.whale.length
	-- The imported whale (whalefall_glb) lies lengthwise along its own Z, head at
	-- -Z, flippers spread about 0.7 of its length: fitted by its length, then
	-- turned a quarter round onto X
	local props = ReplicatedStorage:FindFirstChild("WorldProps")
	local template = props and props:FindFirstChild("WhaleFall")
	local extents = if template and template:IsA("Model") then template:GetExtentsSize() else Vector3.zero
	local alongZ = extents.Z > extents.X
	local box = if alongZ then Vector3.new(L * 0.8, L * 0.3, L) else Vector3.new(L, L * 0.3, L * 0.8)
	local prop = PropParts.make("WhaleFall", box, model)
	if prop then
		local turn = if alongZ then CFrame.Angles(0, -math.pi / 2, 0) else CFrame.identity
		for i, part in prop.parts do
			part.CFrame = turn * prop.offsets[i]
		end
		-- Its middle on the cloud's center (6 studs over the floor), so the belly
		-- rests a little into the sand
		local _, size = model:GetBoundingBox()
		local drop = CFrame.new(0, -size.Y * 0.5, 0)
		for _, part in prop.parts do
			part.CFrame = drop * part.CFrame
		end
		local anchor = Instance.new("Part")
		anchor.Name = "Root"
		anchor.Anchored = true
		anchor.Transparency = 1
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.Size = Vector3.one
		anchor.CFrame = CFrame.identity
		anchor.Parent = model
		model.PrimaryPart = anchor
	else
		local body = ellipsoid(model, CARCASS, Vector3.new(L * 0.62, L * 0.2, L * 0.22), "Root")
		model.PrimaryPart = body
		local function at(part: Part, cframe: CFrame)
			part.CFrame = cframe
		end
		at(ellipsoid(model, BELLY, Vector3.new(L * 0.5, L * 0.12, L * 0.2)), CFrame.new(0, -L * 0.06, 0))
		at(
			ellipsoid(model, CARCASS, Vector3.new(L * 0.28, L * 0.17, L * 0.19)),
			CFrame.new(L * 0.36, L * 0.01, 0)
		)
		at(
			ellipsoid(model, BELLY, Vector3.new(L * 0.26, L * 0.05, L * 0.16)),
			CFrame.new(L * 0.37, -L * 0.085, 0) * CFrame.Angles(0, 0, math.rad(-8))
		)
		at(
			ellipsoid(model, CARCASS, Vector3.new(L * 0.32, L * 0.1, L * 0.1)),
			CFrame.new(-L * 0.38, L * 0.02, 0)
		)
		for side = -1, 1, 2 do
			at(
				ellipsoid(model, CARCASS, Vector3.new(L * 0.1, L * 0.018, L * 0.17)),
				CFrame.new(-L * 0.54, L * 0.03, side * L * 0.075) * CFrame.Angles(0, math.rad(side * 25), 0)
			)
			at(
				ellipsoid(model, CARCASS, Vector3.new(L * 0.13, L * 0.02, L * 0.06)),
				CFrame.new(L * 0.16, -L * 0.07, side * L * 0.12)
					* CFrame.Angles(math.rad(side * 30), math.rad(side * 30), 0)
			)
		end
		-- The bitten flank: torn meat, and ribs standing out of it
		at(
			ellipsoid(model, MEAT, Vector3.new(L * 0.24, L * 0.1, L * 0.08)),
			CFrame.new(-L * 0.02, L * 0.035, L * 0.085)
		)
		for i = 0, 5 do
			local rib = Instance.new("Part")
			rib.Name = "Rib"
			rib.Anchored = true
			rib.CanCollide = false
			rib.CanQuery = false
			rib.CanTouch = false
			rib.CastShadow = false
			rib.Material = Enum.Material.SmoothPlastic
			rib.Color = BONE
			rib.Size = Vector3.new(0.9, L * 0.13, 0.9)
			rib.CFrame = CFrame.new(-L * 0.1 + i * L * 0.035, L * 0.07, L * 0.09)
				* CFrame.Angles(math.rad(-38), 0, 0)
			rib.Parent = model
		end
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(160, 214, 224)
	-- Brighter on the deep floors, where the carcass was a dark shape past ~70 studs
	-- (PC 2026-10-15, the Open Blue)
	light.Range = if deep then 60 else 45
	light.Brightness = if deep then 1 else 0.6
	light.Parent = model.PrimaryPart
	model.Parent = parent
	return model
end

-- On the deep floors a light can't reach through the haze, and a carcass was only a
-- faint shape past ~50 studs (PC 2026-10-15 round 2): a faint cool outline, like the
-- eerie rim predators wear in the dark, hidden by rock in front of it
local RIM = Color3.fromRGB(150, 205, 230)
local RIM_RANGE = { 40, 200 } -- studs from the camera: none closer (it reads by its light), gone past
local function rim(model: Model): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "WhaleRim"
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = RIM
	highlight.OutlineColor = RIM
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Adornee = model
	highlight.Parent = model
	return highlight
end

-- Small corals and boulders poking up through a settled carcass are hidden on this
-- client while it lies there, as if crushed under it (PC 2026-10-15: sponges and
-- staghorns through a Coral Reef whale's flukes). Only pieces whose middle is under
-- the body; big rock, wrecks and ruins are kept out from under it by the server.
local CRUSH_FOLDERS = { "Coral", "Rocks" }
local DEEP_FLOOR = -150 -- below this a whale lies on a deep floor (the shelf's sand is near 0)
local CRUSH_MAX = 26 -- studs: anything bigger stays

local function crush(d: Drawn, at: CFrame)
	local world = workspace:FindFirstChild("World")
	local biomes = if world then world:FindFirstChild("Biomes") else nil
	if biomes == nil then
		return
	end
	local include: { Instance } = {}
	for _, name in CRUSH_FOLDERS do
		local folder = biomes:FindFirstChild(name)
		if folder then
			table.insert(include, folder)
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	params.RespectCanCollide = false
	local L = tune.whale.length
	for _, part in workspace:GetPartBoundsInBox(at, Vector3.new(L, 18, L * 0.55), params) do
		if d.crushed[part] or math.max(part.Size.X, part.Size.Y, part.Size.Z) > CRUSH_MAX then
			continue
		end
		local p = at:PointToObjectSpace(part.Position)
		if (p.X / (L * 0.5)) ^ 2 + (p.Z / (L * 0.27)) ^ 2 <= 1.1 then
			d.crushed[part] = part.LocalTransparencyModifier
			part.LocalTransparencyModifier = 1
		end
	end
end

local function remove(id: number)
	local d = drawn[id]
	if d then
		drawn[id] = nil
		for part, before in d.crushed do
			part.LocalTransparencyModifier = before
		end
		d.folder:Destroy()
	end
end

local function add(payload: { [string]: any })
	if typeof(payload) ~= "table" or typeof(payload.id) ~= "number" or typeof(payload.chunks) ~= "table" then
		return
	end
	remove(payload.id)
	local cloud: Chum.Cloud = {
		id = payload.id,
		kind = payload.kind,
		x = payload.x,
		y = payload.y,
		z = payload.z,
		floor = payload.floor,
		born = payload.born,
		ends = payload.ends,
		chunks = payload.chunks,
		biome = payload.biome,
		yaw = if typeof(payload.yaw) == "number" then payload.yaw else nil,
	}
	local folder = Instance.new("Folder")
	folder.Name = `Chum{cloud.id}`
	local pieces: { Piece } = {}
	for i, chunk in cloud.chunks do
		pieces[i] = chunkPieces(folder, chunk.m, cloud.id * 31 + i)
	end
	local murk = Instance.new("Part")
	murk.Name = "Murk"
	murk.Anchored = true
	murk.CanCollide = false
	murk.CanQuery = false
	murk.CanTouch = false
	murk.Transparency = 1
	murk.Size = Vector3.one
	murk.Parent = folder
	local spread = if cloud.kind == "whale" then tune.whale.length * 0.4 else 5
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(MURK, Color3.fromRGB(70, 22, 26))
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.72),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new(spread * 0.5, spread * 1.3)
	emitter.Lifetime = NumberRange.new(3, 5)
	emitter.Rate = if cloud.kind == "whale" then 10 else 6
	emitter.Speed = NumberRange.new(0.3, 1.2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-10, 10)
	emitter.Drag = 1
	emitter.LightInfluence = 1
	emitter.Parent = murk
	local d: Drawn = {
		cloud = cloud,
		folder = folder,
		pieces = pieces,
		murk = murk,
		emitter = emitter,
		carcass = if cloud.kind == "whale" then carcass(folder, cloud.floor < DEEP_FLOOR) else nil,
		yaw = Chum.yaw(cloud),
		crushed = {},
		crushAt = 0,
		rim = nil,
	}
	local body = d.carcass
	if body and cloud.floor < DEEP_FLOOR then
		d.rim = rim(body)
	end
	drawn[cloud.id] = d
	for key, backAt in payload.eaten or {} do
		local i = tonumber(key)
		local piece = if i then pieces[i] else nil
		if piece and typeof(backAt) == "number" then
			piece.backAt = if backAt < 0 then math.huge else backAt
			piece.hidden = true
			for _, part in piece.parts do
				part.Transparency = 1
			end
		end
	end
	folder.Parent = root
end

local function setHidden(piece: Piece, hidden: boolean)
	if piece.hidden == hidden then
		return
	end
	piece.hidden = hidden
	for i, part in piece.parts do
		part.Transparency = if hidden then 1 else 0
		part.Size = piece.sizes[i]
	end
end

local function place(piece: Piece, frame: CFrame, shrink: number)
	for i, part in piece.parts do
		table.insert(moveParts, part)
		table.insert(moveFrames, frame * piece.offsets[i])
		local size = piece.sizes[i] * shrink
		if part.Size ~= size then
			part.Size = size
		end
	end
end

local function step()
	local now = Timing.clock()
	local camera = workspace.CurrentCamera.CFrame.Position
	local fishRoot = SwimController.root()
	local length = SwimController.length()
	local mouth = if fishRoot then fishRoot.CFrame:PointToWorldSpace(Size.mouthOffset(length)) else nil
	local reach = Size.reach(length) * Forage.REACH_SCALE + Forage.REACH_BONUS
	table.clear(moveParts)
	table.clear(moveFrames)
	for _, d in drawn do
		local cloud = d.cloud
		local center = Chum.center(cloud, now)
		local near = (center - camera).Magnitude < DRAW_RANGE
		d.emitter.Enabled = near and now < cloud.ends - 2
		if not near then
			continue
		end
		d.murk.CFrame = CFrame.new(center)
		local model = d.carcass
		if model then
			-- Nose a little down while it sinks, level once it's down
			local sinking = math.clamp(1 - (now - cloud.born) / tune.whale.sinkSeconds, 0, 1)
			model:PivotTo(
				CFrame.new(center)
					* CFrame.Angles(0, d.yaw, 0)
					* CFrame.Angles(math.rad(14), 0, math.rad(-12 * sinking - 6))
			)
			local outline = d.rim
			if outline then
				-- Fades in past RIM_RANGE[1] and out toward RIM_RANGE[2], and with the
				-- carcass's own fade at the end
				local away = (center - camera).Magnitude
				local inner = math.clamp((away - RIM_RANGE[1]) / 30, 0, 1)
				local outer = math.clamp((RIM_RANGE[2] - away) / 40, 0, 1)
				local strength = inner * outer * math.clamp((cloud.ends - now) / 3, 0, 1)
				outline.OutlineTransparency = 1 - 0.6 * strength
				outline.FillTransparency = 1 - 0.14 * strength
				outline.Enabled = strength > 0.01
			end
			-- Once it's nearly down, and again now and then as dressing streams in
			if sinking < 0.15 and now >= d.crushAt then
				d.crushAt = now + 2
				crush(d, CFrame.new(cloud.x, cloud.floor + 6, cloud.z) * CFrame.Angles(0, d.yaw, 0))
			end
		end
		-- Fades out over its last seconds
		local fade = math.clamp((cloud.ends - now) / 3, 0, 1)
		for i, piece in d.pieces do
			if piece.hidden and piece.suckFrom == nil then
				if piece.pendingUntil > 0 and now > piece.pendingUntil then
					piece.pendingUntil = 0
					piece.backAt = 0
				end
				if piece.pendingUntil == 0 and now >= piece.backAt then
					setHidden(piece, false)
				end
				continue
			end
			if piece.hidden then
				continue
			end
			local at = Chum.chunk(cloud, i, now)
			if piece.suckFrom then
				local alpha = math.clamp((now - piece.suckStart) / SUCK_SECONDS, 0, 1)
				local from = piece.suckFrom :: Vector3
				place(piece, CFrame.new(from:Lerp(mouth or from, alpha * alpha)), 1 - alpha * 0.8)
				if alpha >= 1 then
					piece.suckFrom = nil
					setHidden(piece, true)
				end
				continue
			end
			if mouth and now < cloud.ends then
				local size = piece.sizes[1].X
				local gap = (at - mouth).Magnitude - size * 0.5
				local pullRange = reach * Forage.PULL
				if gap < pullRange then
					at = at:Lerp(mouth, (1 - math.max(gap, 0) / pullRange) * Forage.PULL_SHARE)
					gap = (at - mouth).Magnitude - size * 0.5
				end
				if gap <= reach then
					piece.suckFrom = at
					piece.suckStart = now
					piece.pendingUntil = now + CONFIRM_SECONDS
					piece.backAt = math.huge
					table.insert(batch, { cloud.id, i })
					ChumController.ate:fire(cloud.chunks[i].m, at)
					continue
				end
			end
			place(piece, CFrame.new(at), fade)
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- At most 12 a send (the server drops a bigger batch): the rest go next time
	if #batch > 0 and now - lastSend >= SEND_INTERVAL then
		lastSend = now
		local send = {}
		for i = 1, math.min(#batch, 12) do
			table.insert(send, table.remove(batch, 1))
		end
		ClientState.request("EatChum", send)
	end
end

local function onEaten(payload: { [string]: any })
	local d = drawn[payload.id]
	local piece = if d then d.pieces[payload.index] else nil
	if piece == nil then
		return
	end
	piece.backAt = if payload.backAt < 0 then math.huge else payload.backAt
	piece.pendingUntil = 0
	if payload.by == Players.LocalPlayer.UserId then
		Sfx.play("Chomp", { volume = 0.3, pitch = 1.1 + math.random() * 0.2 })
	elseif piece.suckFrom == nil then
		setHidden(piece, true)
	end
end

local function onEvent(kind: string, payload: { [string]: any })
	if typeof(payload) ~= "table" then
		return
	end
	if kind == "add" then
		add(payload)
		if payload.kind == "whale" then
			warn = nil
		end
	elseif kind == "eat" then
		onEaten(payload)
	elseif kind == "remove" then
		remove(payload.id)
	elseif kind == "warn" then
		if payload.done then
			warn = nil
		elseif typeof(payload.x) == "number" then
			warn = {
				at = Vector3.new(payload.x, payload.y, payload.z),
				startsAt = payload.startsAt,
				biome = payload.biome,
			}
			Sfx.play("BossWarning", { volume = 0.35, pitch = 0.7 })
		end
	end
end

-- Where the Whale Fall is (coming, sinking or feeding), for the map
function ChumController.whale(): Vector3?
	for _, d in drawn do
		if d.cloud.kind == "whale" then
			return Chum.center(d.cloud, Timing.clock())
		end
	end
	return if warn then warn.at else nil
end

function ChumController.start()
	root = Instance.new("Folder")
	root.Name = "Chum"
	root.Parent = workspace
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local event = remotes:WaitForChild("Chum") :: RemoteEvent
	event.OnClientEvent:Connect(onEvent)
	task.spawn(function()
		local getChum = remotes:WaitForChild("GetChum") :: RemoteFunction
		local ok, data = pcall(function()
			return getChum:InvokeServer()
		end)
		if ok and typeof(data) == "table" then
			for _, payload in data.clouds or {} do
				add(payload)
			end
			if typeof(data.warn) == "table" then
				onEvent("warn", data.warn)
			end
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return ChumController
