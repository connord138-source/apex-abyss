--!strict
-- The biome landmarks on this client (owner, 2026-10-21: the biome detail boards;
-- the server builds them, LandmarkService checks what pays or moves a fish):
--
--   * what floats bobs (tag `Bobbing`: the otters, the buoy, the sargassum rafts) and
--     the jelly chains drift (`Drifting`), near the camera only;
--   * garden eels duck into the sand as a fish swims over them (`GardenEels`);
--   * little fish shelter under each sargassum raft (`Sargassum`), built near it;
--   * (the hammerheads round Hammerhead Pinnacle are real predators since 2026-10-28,
--     Config/Predators `Hammerhead`, drawn by PredatorController);
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
local SwimWave = require(ReplicatedStorage.Shared.SwimWave)
local Bubbles = require(script.Parent.Parent.Bubbles)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.Sfx)
local HuntController = require(script.Parent.HuntController)
local SwimController = require(script.Parent.SwimController)

local Places = Config.Places

local LandmarkController = {}

-- Floating things bob and drift about a stud a second, so they're posed every other
-- frame within NEAR_EVERY, every fifth within NEAR_HALF and every eighth past it,
-- all in one BulkMoveTo with the raft fish. Their motion eases
-- out with distance and they hold still past it: a jelly past DRIFT_STILL, a raft,
-- buoy or otter past BOB_STILL. Each is welded into one assembly on the server
-- (LandmarkKit.oneBody), so only its anchored root is moved (PC 2026-10-22, 66.7
-- ms/s at Hammerhead Pinnacle, 40 of it a PivotTo on each part-built jelly every
-- frame; 2026-10-23, 52.7 with them batched, 39.6 of it the move: ~150 jelly parts
-- a frame, most of them 200-500 out; 2026-10-24, 19.5 with the far ones still;
-- 2026-10-25, 17.6 with 4 raft fish: ~40 jelly parts and ~12 raft fish a frame;
-- 2026-10-27, 16.6 with the raft fish as prey models, BulkMoveTo 11.5)
local NEAR_EVERY = 60
local NEAR_HALF = 120
local DRIFT_FADE = 150
local DRIFT_STILL = 220
local BOB_FADE = 260
local BOB_STILL = 360
local EEL_LOOK = 140 -- studs from the camera a garden eel patch is checked
local EEL_NEAR = 26 -- studs across a fish makes a garden eel patch duck
local EEL_DOWN = 3.2 -- studs it sinks
local SHELTER_NEAR = 180 -- studs from the camera a raft's fish are built (cleared
-- SHELTER_KEEP further out, so they don't flicker on the edge). Each is moved as
-- often as its own speed needs (SchoolController's rule): a step never turns more
-- than SHELTER_STEP radians seen from the camera, at most every SHELTER_MAX frames
-- (PC 2026-10-27: every frame within 70 studs and every other to 120 whatever its
-- speed, and the slowest circle at under half the fastest's)
local SHELTER_KEEP = 30
local SHELTER_STEP = 0.0042
local SHELTER_MAX = 6
local SHELTER_FISH = 4

-- A floating thing: its rest pivot (the server's), and each of its parts placed
-- against it (an assembly's root only: welded parts follow it), kept up to date as
-- parts stream in and out
type Floater = {
	model: Model,
	base: CFrame,
	phase: number,
	salt: number, -- (which frames it moves on)
	bob: number, -- its bob's share (the `Bob` attribute: a buoy on a chain bobs less)
	moved: boolean, -- off its rest pose
	offsets: { [BasePart]: CFrame },
	connections: { RBXScriptConnection },
}
local floaters: { [Model]: Floater } = {}
local drifters: { [Model]: Floater } = {}
type Eels = { model: Model, base: CFrame, down: number }
local eels: { [Model]: Eels } = {}
type Shelter = {
	model: Model,
	base: CFrame,
	fish: { BasePart }, -- what moves (a model's body)
	made: { Instance }, -- what goes when they're cleared
	turn: { CFrame }, -- each one's own turn (a static mesh that came in facing +Z)
	next: { number }, -- the frame each is next moved on (SHELTER_STEP)
	phase: number,
}
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
		if entry and entry.made then
			for _, made in entry.made do
				made:Destroy()
			end
		end
		if entry and entry.connections then
			for _, connection in entry.connections do
				connection:Disconnect()
			end
		end
		into[instance :: Model] = nil
	end)
end

-- A part that arrives is where the server put it (nothing bobs there), so its place
-- against the rest pivot is read straight off it. Only anchored roots are kept: the
-- parts welded to one ride with it (one that arrives before its weld would read as
-- its own root)
local function place(entry: Floater, part: Instance)
	if part:IsA("BasePart") and part.Anchored then
		local root: BasePart? = part.AssemblyRootPart
		if root == nil or root == part then
			entry.offsets[part] = entry.base:ToObjectSpace(part.CFrame)
		end
	end
end

local function floater(model: Model): Floater
	local base = model:GetPivot()
	local bob = model:GetAttribute("Bob")
	local phase = seedOf(base.Position)
	local entry: Floater = {
		model = model,
		base = base,
		phase = phase,
		salt = math.floor(phase * 10),
		bob = if typeof(bob) == "number" then bob else 1,
		moved = false,
		offsets = {},
		connections = {},
	}
	for _, part in model:GetDescendants() do
		place(entry, part)
	end
	table.insert(
		entry.connections,
		model.DescendantAdded:Connect(function(part)
			place(entry, part)
		end)
	)
	table.insert(
		entry.connections,
		model.DescendantRemoving:Connect(function(part)
			if part:IsA("BasePart") then
				entry.offsets[part] = nil
			end
		end)
	)
	return entry
end

-- ---------------------------------------------------------------------------
-- Little fish under the rafts
-- ---------------------------------------------------------------------------

local SHELTER_COLORS =
	{ Color3.fromRGB(230, 200, 70), Color3.fromRGB(150, 180, 200), Color3.fromRGB(240, 150, 60) }

-- Raft fish are little copies of the prey models (SHELTER_PREY, about SHELTER_LENGTH
-- long; PC 2026-10-26: coloured boxes read as chips floating under a raft), a box
-- until PreyModels are in
local SHELTER_PREY = { "Sardine", "Minnow" }
local SHELTER_LENGTH = 1.8
local MESH_FLIP = CFrame.Angles(0, math.pi, 0)
local shelterTemplates: { [string]: Instance } = {}

-- A prey model, anchored and scaled to a raft fish, to clone (nil until imported)
local function shelterTemplate(id: string): Instance?
	local made = shelterTemplates[id]
	if made then
		return made
	end
	local models = ReplicatedStorage:FindFirstChild("PreyModels")
	local template = if models then models:FindFirstChild(id) else nil
	if template == nil or not (template:IsA("Model") or template:IsA("MeshPart")) then
		return nil
	end
	local copy = template:Clone()
	local parts: { Instance } = if copy:IsA("BasePart") then { copy } else copy:GetDescendants()
	for _, part in parts do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
	end
	if copy:IsA("Model") then
		local extent = copy:GetExtentsSize()
		local long = math.max(extent.X, extent.Y, extent.Z)
		if long > 0 then
			copy:ScaleTo(copy:GetScale() * SHELTER_LENGTH / long)
		end
	elseif copy:IsA("BasePart") then
		local long = math.max(copy.Size.X, copy.Size.Y, copy.Size.Z)
		if long > 0 then
			copy.Size *= SHELTER_LENGTH / long
		end
	end
	shelterTemplates[id] = copy
	return copy
end

local function buildShelter(entry: Shelter)
	for k = 1, SHELTER_FISH do
		local template = shelterTemplate(SHELTER_PREY[(k % #SHELTER_PREY) + 1])
		local body: BasePart? = nil
		local turn = CFrame.identity
		if template then
			local copy = template:Clone()
			if copy:IsA("Model") then
				-- (a rigged body faces -Z already: its mesh is what moves, as SchoolController's)
				local mesh = copy.PrimaryPart or copy:FindFirstChildWhichIsA("MeshPart", true)
				if mesh then
					body = mesh :: BasePart
				end
			elseif copy:IsA("BasePart") then
				body = copy
				turn = if SwimWave.needsFlip(copy) then MESH_FLIP else CFrame.identity
			end
			if body then
				copy.Parent = folder
				table.insert(entry.made, copy)
			else
				copy:Destroy()
			end
		end
		if body == nil then
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
			table.insert(entry.made, fish)
			body = fish
		end
		table.insert(entry.fish, body :: BasePart)
		table.insert(entry.turn, turn)
		table.insert(entry.next, 0)
	end
end

local function clearShelter(entry: Shelter)
	for _, made in entry.made do
		made:Destroy()
	end
	table.clear(entry.fish)
	table.clear(entry.made)
	table.clear(entry.turn)
	table.clear(entry.next)
end

-- ---------------------------------------------------------------------------
-- What moves this frame
-- ---------------------------------------------------------------------------

-- What moves this frame, in one BulkMoveTo
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
local frameCount = 0
local smoothDt = 1 / 60 -- the frame time, eased (the raft fish's SHELTER_STEP)

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

local cannonCheck = 0

-- Whether a floater this far off moves this frame
local function due(gap: number, salt: number): boolean
	local every = if gap < NEAR_EVERY then 2 elseif gap < NEAR_HALF then 5 else 8
	return (frameCount + salt) % every == 0
end

-- How much of its motion a floater keeps this far off: all of it to `fade`, none
-- past `still`
local function reach(gap: number, fade: number, still: number): number
	local x = math.clamp((still - gap) / (still - fade), 0, 1)
	return x * x * (3 - 2 * x)
end

-- Every floater due this frame, posed by `pose`, in the batch
local function queue(entry: Floater, pose: CFrame)
	for part, offset in entry.offsets do
		table.insert(moveParts, part)
		table.insert(moveFrames, pose * offset)
	end
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	frameCount += 1
	smoothDt += (math.min(dt, 0.1) - smoothDt) * math.min(1, dt * 0.6)
	local eye = camera.CFrame.Position
	local now = Workspace:GetServerTimeNow()
	-- (a floater streamed out is dropped by its tag; its parts by DescendantRemoving)
	for _, entry in floaters do
		local gap = (entry.base.Position - eye).Magnitude
		local k = reach(gap, BOB_FADE, BOB_STILL) * entry.bob
		if k <= 0 then
			if entry.moved then
				entry.moved = false
				queue(entry, entry.base)
			end
		elseif due(gap, entry.salt) then
			entry.moved = true
			local t = now * 0.8 + entry.phase
			queue(
				entry,
				entry.base
					* CFrame.new(0, math.sin(t) * 1.2 * k, 0)
					* CFrame.Angles(math.sin(t * 0.7) * 0.05 * k, 0, math.cos(t * 0.6) * 0.05 * k)
			)
		end
	end
	for _, entry in drifters do
		local gap = (entry.base.Position - eye).Magnitude
		local k = reach(gap, DRIFT_FADE, DRIFT_STILL)
		if k <= 0 then
			if entry.moved then
				entry.moved = false
				queue(entry, entry.base)
			end
		elseif due(gap, entry.salt) then
			entry.moved = true
			local t = now * 0.25 + entry.phase
			queue(
				entry,
				entry.base
					* CFrame.new(math.sin(t) * 4 * k, math.sin(t * 1.3) * 3 * k, math.cos(t * 0.8) * 4 * k)
					* CFrame.Angles(0, math.sin(t * 0.5) * 0.3 * k, math.sin(t) * 0.08 * k)
			)
		end
	end
	local root = SwimController.root()
	local fishAt = if root then root.Position else nil
	for model, entry in eels do
		if entry.down == 0 and (entry.base.Position - eye).Magnitude > EEL_LOOK then
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
	-- (a model that leaves is dropped by `track`, so no Parent reads here)
	for _, entry in shelters do
		local raft = entry.base.Position
		local gap = (raft - eye).Magnitude
		if gap > SHELTER_NEAR + (if #entry.fish > 0 then SHELTER_KEEP else 0) then
			if #entry.fish > 0 then
				clearShelter(entry)
			end
			continue
		end
		if #entry.fish == 0 then
			buildShelter(entry)
		end
		for k, fish in entry.fish do
			if entry.next[k] > frameCount then
				continue
			end
			local radius = 5 + (k % 4) * 2.5
			local rate = 0.7 + k * 0.05
			local way = if k % 2 == 0 then 1 else -1
			local angle = way * now * rate + k * 0.8 + entry.phase
			local at = raft
				+ Vector3.new(math.cos(angle) * radius, -9 - (k % 3) * 2.5, math.sin(angle) * radius)
			-- (by its own distance: PC 2026-10-28, from the raft's, 1.5% of the steps within
			-- 70 studs went over 4 px)
			local hold = math.floor((at - eye).Magnitude * SHELTER_STEP / (rate * radius * smoothDt))
			entry.next[k] = frameCount + math.clamp(hold, 1, SHELTER_MAX)
			local ahead = Vector3.new(-math.sin(angle) * way, 0, math.cos(angle) * way)
			table.insert(moveParts, fish)
			table.insert(moveFrames, CFrame.lookAt(at, at + ahead) * entry.turn[k])
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
		table.clear(moveParts)
		table.clear(moveFrames)
	end
	local live = flight
	if live then
		if os.clock() > live.untilAt or SwimController.root() == nil then
			flight = nil
		else
			local want = live.aim * live.speed
			SwimController.shove((want - SwimController.velocity) * math.min(1, dt * 8))
		end
	end
	cannonCheck += dt
	if cannonCheck >= 0.1 then
		cannonCheck = 0
		checkCannon(os.clock())
	end
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
		return {
			model = model,
			base = base,
			fish = {},
			made = {},
			turn = {},
			next = {},
			phase = seedOf(base.Position),
		}
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
