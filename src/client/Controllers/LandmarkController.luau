--!strict
-- The biome landmarks on this client (owner, 2026-10-21: the biome detail boards;
-- the server builds them, LandmarkService checks what pays or moves a fish):
--
--   * what floats bobs (tag `Bobbing`: the otters, the buoy, the sargassum rafts) and
--     the jelly chains drift (`Drifting`), near the camera only;
--   * garden eels duck into the sand as a fish swims over them (`GardenEels`);
--   * little fish shelter under each sargassum raft (`Sargassum`), built near it;
--   * hammerheads circle Hammerhead Pinnacle (the PlaceMarks HammerheadPinnacle and
--     HammerheadPinnacle_Base): VariantModels.Hammerhead, or a part-built shark;
--   * BITE the Broken Galleon's bell or a clam's pearl (`HuntController.findLandmark`;
--     the bell rings for everyone near, a pearl taken stays hidden for us until it
--     grows back: state `pearls`);
--   * swim into the Bay Cannon's muzzle and it fires you over the bay: the server's
--     answer starts the flight and we drive it (it stamps MovedAt meanwhile).
--
-- Spots come from Workspace.Places (its attributes replicate whatever streams), the
-- moving pieces from their tags as they stream in.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Bubbles = require(script.Parent.Parent.Bubbles)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.Sfx)
local HuntController = require(script.Parent.HuntController)
local SwimController = require(script.Parent.SwimController)

local Places = Config.Places

local LandmarkController = {}

local NEAR = 500 -- studs from the camera that floating things move
local EEL_NEAR = 26 -- studs across a fish makes a garden eel patch duck
local EEL_DOWN = 3.2 -- studs it sinks
local SHELTER_NEAR = 320 -- studs from the camera a raft's fish are built
local SHELTER_FISH = 8
local SHARKS = 4
local SHARK_NEAR = 900
local SHARK_LENGTH = 16

type Floater = { model: Model, base: CFrame, phase: number }
local floaters: { [Model]: Floater } = {}
local drifters: { [Model]: Floater } = {}
type Eels = { model: Model, base: CFrame, down: number }
local eels: { [Model]: Eels } = {}
type Shelter = { model: Model, base: CFrame, fish: { BasePart }, phase: number }
local shelters: { [Model]: Shelter } = {}

local folder: Folder

local function marks(): Instance?
	return Workspace:FindFirstChild("Places")
end

local function mark(name: string): Vector3?
	local places = marks()
	local value = if places then places:GetAttribute(name) else nil
	return if typeof(value) == "Vector3" then value else nil
end

local function seedOf(at: Vector3): number
	return (math.abs(at.X * 0.37 + at.Z * 0.71) % 6.283)
end

local function track(tag: string, into: { [Model]: any }, make: (Model) -> any)
	local function add(instance: Instance)
		if instance:IsA("Model") and into[instance] == nil then
			into[instance] = make(instance)
		end
	end
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		local entry = into[instance :: Model]
		if entry and entry.fish then
			for _, part in entry.fish do
				part:Destroy()
			end
		end
		into[instance :: Model] = nil
	end)
end

local function floater(model: Model): Floater
	local base = model:GetPivot()
	return { model = model, base = base, phase = seedOf(base.Position) }
end

-- ---------------------------------------------------------------------------
-- Little fish under the rafts
-- ---------------------------------------------------------------------------

local SHELTER_COLORS =
	{ Color3.fromRGB(230, 200, 70), Color3.fromRGB(150, 180, 200), Color3.fromRGB(240, 150, 60) }

local function buildShelter(entry: Shelter)
	for k = 1, SHELTER_FISH do
		local fish = Instance.new("Part")
		fish.Name = "ShelterFish"
		fish.Anchored = true
		fish.CanCollide = false
		fish.CanQuery = false
		fish.CanTouch = false
		fish.CastShadow = false
		fish.Material = Enum.Material.SmoothPlastic
		fish.Color = SHELTER_COLORS[(k % #SHELTER_COLORS) + 1]
		fish.Size = Vector3.new(0.45, 0.8, 1.6)
		fish.Parent = folder
		table.insert(entry.fish, fish)
	end
end

local function clearShelter(entry: Shelter)
	for _, part in entry.fish do
		part:Destroy()
	end
	table.clear(entry.fish)
end

-- ---------------------------------------------------------------------------
-- Hammerheads round the pinnacle
-- ---------------------------------------------------------------------------

local sharks: { Model } = {}

local function partShark(): Model
	local model = Instance.new("Model")
	model.Name = "Hammerhead"
	local grey = Color3.fromRGB(104, 116, 128)
	local function piece(name: string, size: Vector3, at: CFrame, shape: string?)
		local p: BasePart = if shape == "wedge" then Instance.new("WedgePart") else Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = grey
		p.Size = size
		p.CFrame = at
		p.Parent = model
		return p
	end
	-- (along -Z, the way a rigged model faces)
	local body = piece("Body", Vector3.new(2.2, 2.4, 12), CFrame.new())
	model.PrimaryPart = body
	piece("Head", Vector3.new(7.5, 0.7, 1.8), CFrame.new(0, 0.2, -6.4))
	piece("Dorsal", Vector3.new(0.4, 3.2, 2.6), CFrame.new(0, 2.6, -0.5), "wedge")
	piece("Tail", Vector3.new(0.4, 4.2, 2.4), CFrame.new(0, 0.8, 7) * CFrame.Angles(0, math.pi, 0), "wedge")
	return model
end

local function sharkModel(): Model
	local variants = ReplicatedStorage:FindFirstChild("VariantModels")
	local template = if variants then variants:FindFirstChild("Hammerhead") else nil
	if template and template:IsA("Model") then
		local model = template:Clone()
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
		end
		local extent = model:GetExtentsSize()
		local long = math.max(extent.X, extent.Y, extent.Z)
		if long > 0 then
			model:ScaleTo(SHARK_LENGTH / long)
		end
		return model
	end
	return partShark()
end

local function stepSharks(now: number, camera: Vector3)
	local center, base = mark("HammerheadPinnacle"), mark("HammerheadPinnacle_Base")
	if center == nil or base == nil or (camera - center).Magnitude > SHARK_NEAR then
		for _, shark in sharks do
			shark:Destroy()
		end
		table.clear(sharks)
		return
	end
	if #sharks == 0 then
		for _ = 1, SHARKS do
			local shark = sharkModel()
			shark.Parent = folder
			table.insert(sharks, shark)
		end
	end
	for k, shark in sharks do
		local radius = 70 + k * 14
		local speed = 9 + k
		local way = if k % 2 == 0 then 1 else -1
		local angle = way * now * speed / radius + k * 1.7
		local height = base.Y + 50 + k * 34 + math.sin(now * 0.3 + k) * 8
		local at = Vector3.new(base.X + math.cos(angle) * radius, height, base.Z + math.sin(angle) * radius)
		local ahead = Vector3.new(-math.sin(angle) * way, 0, math.cos(angle) * way)
		shark:PivotTo(CFrame.lookAt(at, at + ahead) * CFrame.Angles(0, 0, way * 0.18))
	end
end

-- ---------------------------------------------------------------------------
-- The bell, the pearls and the cannon
-- ---------------------------------------------------------------------------

local function pearlHidden(index: number): boolean
	local s = ClientState.current
	local pearls = if s and typeof(s.pearls) == "table" then s.pearls else nil
	local at = if pearls then pearls[tostring(index)] else nil
	return typeof(at) == "number" and at > Workspace:GetServerTimeNow()
end

-- What a bite at `mouth` (reaching `reach`) would take: the bell or a pearl
local function findLandmark(mouth: Vector3, reach: number): (string?, number?)
	for index = 1, 8 do
		local bell = mark(`Bell{index}`)
		if bell == nil then
			break
		end
		if (bell - mouth).Magnitude <= reach + Places.bell.reach then
			return "bell", index
		end
	end
	for index = 1, 32 do
		local pearl = mark(`Pearl{index}`)
		if pearl == nil then
			break
		end
		if not pearlHidden(index) and (pearl - mouth).Magnitude <= reach + Places.pearl.reach then
			return "pearl", index
		end
	end
	return nil, nil
end

local function showPearls()
	for _, bead in CollectionService:GetTagged("ClamPearl") do
		local index = bead:GetAttribute("Pearl")
		if bead:IsA("BasePart") and typeof(index) == "number" then
			bead.LocalTransparencyModifier = if pearlHidden(index) then 1 else 0
		end
	end
end

-- A sound out in the water at `at`, heard to `range`
local emitters: { [string]: Attachment } = {}
local function soundAt(key: string, at: Vector3, name: string, volume: number, pitch: number, range: number)
	local emitter: Attachment? = emitters[key]
	if emitter == nil then
		local made = Instance.new("Attachment")
		made.Name = `Landmark_{key}`
		made.Parent = Workspace.Terrain
		made.WorldPosition = at
		emitters[key] = made
		emitter = made
	end
	assert(emitter)
	Sfx.play(name, { volume = volume, pitch = pitch, parent = emitter :: Instance, range = range })
end

local flight: { aim: Vector3, speed: number, untilAt: number }? = nil
local cannonAsked = 0

local function checkCannon(now: number)
	local root = SwimController.root()
	if root == nil or flight ~= nil or now - cannonAsked < 1.5 then
		return
	end
	for index = 1, 4 do
		local muzzle = mark(`Cannon{index}`)
		if muzzle == nil then
			break
		end
		if (root.Position - muzzle).Magnitude <= Places.cannon.reach then
			cannonAsked = now
			ClientState.request("Landmark", "cannon", index)
			return
		end
	end
end

local function onLandmark(kind: string, index: number, payload: { [string]: any })
	if kind == "bell" then
		local bell = mark(`Bell{index}`)
		if bell then
			soundAt(`Bell{index}`, bell, "GoldenShell", 1, 0.5, Places.bell.heard)
			Bubbles.burst(bell, 3, 10)
		end
	elseif kind == "boom" then
		local muzzle = mark(`Cannon{index}`)
		if muzzle then
			soundAt(`Cannon{index}`, muzzle, "Breach", 1, 1.25, 400)
			Bubbles.burst(muzzle, 8, 26)
		end
	elseif kind == "cannon" then
		local aim, speed, seconds = payload.aim, payload.speed, payload.seconds
		if typeof(aim) == "Vector3" and typeof(speed) == "number" and typeof(seconds) == "number" then
			flight = { aim = aim.Unit, speed = speed, untilAt = os.clock() + seconds }
		end
	end
end

-- ---------------------------------------------------------------------------

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local eye = camera.CFrame.Position
	local now = Workspace:GetServerTimeNow()
	for model, entry in floaters do
		if model.Parent and (entry.base.Position - eye).Magnitude < NEAR then
			local t = now * 0.8 + entry.phase
			model:PivotTo(
				entry.base
					* CFrame.new(0, math.sin(t) * 1.2, 0)
					* CFrame.Angles(math.sin(t * 0.7) * 0.05, 0, math.cos(t * 0.6) * 0.05)
			)
		end
	end
	for model, entry in drifters do
		if model.Parent and (entry.base.Position - eye).Magnitude < NEAR then
			local t = now * 0.25 + entry.phase
			model:PivotTo(
				entry.base
					* CFrame.new(math.sin(t) * 4, math.sin(t * 1.3) * 3, math.cos(t * 0.8) * 4)
					* CFrame.Angles(0, math.sin(t * 0.5) * 0.3, math.sin(t) * 0.08)
			)
		end
	end
	local root = SwimController.root()
	local fishAt = if root then root.Position else nil
	for model, entry in eels do
		if model.Parent == nil then
			continue
		end
		local want = 0
		if fishAt then
			local flat = (fishAt - entry.base.Position) * Vector3.new(1, 0, 1)
			if flat.Magnitude < EEL_NEAR and fishAt.Y - entry.base.Position.Y < 34 then
				want = EEL_DOWN
			end
		end
		-- (quick down, slow back up)
		local rate = if want > entry.down then 10 else 0.8
		local down = entry.down + (want - entry.down) * math.min(1, dt * rate)
		if math.abs(down - entry.down) > 0.01 then
			entry.down = down
			model:PivotTo(entry.base * CFrame.new(0, -down, 0))
		end
	end
	for model, entry in shelters do
		local raft = entry.base.Position
		if model.Parent == nil or (raft - eye).Magnitude > SHELTER_NEAR then
			if #entry.fish > 0 then
				clearShelter(entry)
			end
			continue
		end
		if #entry.fish == 0 then
			buildShelter(entry)
		end
		local parts: { BasePart } = {}
		local frames: { CFrame } = {}
		for k, fish in entry.fish do
			local radius = 5 + (k % 4) * 2.5
			local way = if k % 2 == 0 then 1 else -1
			local angle = way * now * (0.7 + k * 0.05) + k * 0.8 + entry.phase
			local at = raft
				+ Vector3.new(math.cos(angle) * radius, -9 - (k % 3) * 2.5, math.sin(angle) * radius)
			local ahead = Vector3.new(-math.sin(angle) * way, 0, math.cos(angle) * way)
			table.insert(parts, fish)
			table.insert(frames, CFrame.lookAt(at, at + ahead))
		end
		Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	stepSharks(now, eye)
	local live = flight
	if live then
		if os.clock() > live.untilAt or SwimController.root() == nil then
			flight = nil
		else
			local want = live.aim * live.speed
			SwimController.shove((want - SwimController.velocity) * math.min(1, dt * 8))
		end
	end
	checkCannon(os.clock())
end

function LandmarkController.start()
	folder = Instance.new("Folder")
	folder.Name = "Landmarks"
	folder.Parent = Workspace
	track("Bobbing", floaters, floater)
	track("Drifting", drifters, floater)
	track("GardenEels", eels, function(model: Model)
		return { model = model, base = model:GetPivot(), down = 0 }
	end)
	track("Sargassum", shelters, function(model: Model)
		local base = model:GetPivot()
		return { model = model, base = base, fish = {}, phase = seedOf(base.Position) }
	end)
	HuntController.findLandmark = function(mouth: Vector3, reach: number): (string?, number?)
		return findLandmark(mouth, reach)
	end
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LandmarkEvent") :: RemoteEvent
	remote.OnClientEvent:Connect(onLandmark)
	ClientState.changed:connect(showPearls)
	CollectionService:GetInstanceAddedSignal("ClamPearl"):Connect(showPearls)
	task.spawn(function()
		while true do
			task.wait(1)
			showPearls()
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return LandmarkController
