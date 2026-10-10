--!strict
-- Kelp sways (owner, 2026-10-08: nothing in the water moved but the fish). Every
-- kelp plant the server built (workspace.World.Biomes.Kelp, "Kelp" models) bends
-- gently about its base in a slow current. Only the plants within reach of the
-- camera move, in one BulkMoveTo a frame, so a thousand plants cost nothing.
--
-- Plants are collected as they come into reach, not once at the start: with
-- streaming, a plant's Model arrives before its parts, so a plant collected at the
-- start had no stalk and never moved (retest 2026-10-08: the first start swayed
-- nothing, a later one swayed everything). A plant whose parts streamed in or out
-- is collected again; each part's rest pose is kept (the `KelpRest` attribute), so
-- collecting a plant mid-sway never makes it drift.
--
-- Kelp is soft, so fish swim through it, but it gives way (owner, 2026-10-10: "the
-- kelp and a lot of other items are phasing and glitching"): a plant leans away
-- from any fish passing through it, far enough to clear the fish at its height, and
-- springs back after; a plant the camera is inside fades out instead of flickering
-- across the lens.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

type Plant = {
	base: CFrame, -- the stalk's foot, upright
	parts: { BasePart },
	offsets: { CFrame }, -- each part from the base
	phase: number,
	rate: number,
	amplitude: number,
	height: number, -- how tall it stands
	pushX: number, -- the lean away from fish, radians about the base's X and Z
	pushZ: number,
	faded: boolean, -- the camera is inside it
}

local REACH = 180 -- studs from the camera a plant still sways
local RESCAN = 0.5 -- seconds between picking the plants in reach
local GIVE = 3.5 -- studs round the stalk a fish pushes it (plus the fish's own radius)
local MAX_LEAN = 0.55 -- radians a plant leans away at most
local LEAN_IN = 7 -- how fast it gives way (per second) ...
local LEAN_OUT = 1.8 -- ... and springs back
local FADE_RADIUS = 4 -- studs round the stalk the camera makes it fade
local FADED = 0.75 -- its LocalTransparencyModifier then

local KelpController = {}

local folder: Instance? = nil
local known: { [Model]: Plant } = setmetatable({}, { __mode = "k" }) :: any
local active: { Plant } = {}
local parts: { BasePart } = {}
local frames: { CFrame } = {}
local clock = 0
local sinceScan = RESCAN

local rng = Random.new(7)

-- A part's pose as the server built it (taken the first time this client sees it)
local function restOf(part: BasePart): CFrame
	local rest = part:GetAttribute("KelpRest")
	if typeof(rest) == "CFrame" then
		return rest
	end
	part:SetAttribute("KelpRest", part.CFrame)
	return part.CFrame
end

local function partsOf(plant: Model): { BasePart }
	local list = {}
	for _, descendant in plant:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

-- The plant's sway record from the parts it has now, or nil while its stalk hasn't
-- streamed in
local function collect(plant: Model, old: Plant?): Plant?
	local stalk = plant:FindFirstChild("Stalk")
	if stalk == nil or not stalk:IsA("BasePart") then
		return nil
	end
	local base = restOf(stalk) * CFrame.new(0, -stalk.Size.Y / 2, 0)
	local entry: Plant = {
		base = base,
		parts = {},
		offsets = {},
		phase = if old then old.phase else rng:NextNumber(0, 6.28),
		rate = if old then old.rate else rng:NextNumber(0.3, 0.55),
		amplitude = if old then old.amplitude else rng:NextNumber(0.035, 0.07),
		height = stalk.Size.Y,
		pushX = if old then old.pushX else 0,
		pushZ = if old then old.pushZ else 0,
		faded = false,
	}
	for _, part in partsOf(plant) do
		table.insert(entry.parts, part)
		local offset = base:ToObjectSpace(restOf(part))
		table.insert(entry.offsets, offset)
		entry.height = math.max(entry.height, offset.Y + part.Size.Y / 2)
	end
	return entry
end

local function rescan()
	table.clear(active)
	local holder = folder
	if holder == nil then
		return
	end
	local camera = Workspace.CurrentCamera.CFrame.Position
	for _, child in holder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		local plant = child :: Model
		-- (a Model's pivot is known even before its parts stream in)
		if (plant:GetPivot().Position - camera).Magnitude > REACH then
			continue
		end
		local entry: Plant? = known[plant]
		local first: BasePart? = if entry then entry.parts[1] else nil
		local stale = entry == nil
			or first == nil
			or first.Parent == nil
			or #(entry :: Plant).parts ~= #partsOf(plant)
		if stale then
			entry = collect(plant, entry)
			if entry then
				known[plant] = entry
			else
				known[plant] = nil
			end
		end
		if entry and #entry.parts > 0 then
			table.insert(active, entry)
		end
	end
end

-- Every player's fish near the camera: where it is and how wide (prey are small
-- and swim round the kelp)
local swimmers: { { position: Vector3, radius: number } } = {}
local function gatherSwimmers(camera: Vector3)
	table.clear(swimmers)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - camera).Magnitude < REACH + 20 then
			local length = (character :: Model):GetAttribute("Length")
			table.insert(swimmers, {
				position = root.Position,
				radius = if typeof(length) == "number" then length * 0.3 else 1,
			})
		end
	end
end

-- The lean (about the base's X and Z) that clears every fish in the plant, or 0, 0
local function leanFor(plant: Plant): (number, number)
	local bestX, bestZ, best = 0, 0, 0
	for _, swimmer in swimmers do
		local q = plant.base:PointToObjectSpace(swimmer.position)
		if q.Y < -swimmer.radius or q.Y > plant.height + swimmer.radius then
			continue
		end
		local d = math.sqrt(q.X * q.X + q.Z * q.Z)
		local reach = GIVE + swimmer.radius
		if d >= reach then
			continue
		end
		-- Far enough over to clear the fish at its height, away from it
		local angle = math.min(MAX_LEAN, (reach - d) / math.max(q.Y, 4))
		if angle > best then
			local awayX, awayZ = 1, 0
			if d > 1e-3 then
				awayX, awayZ = -q.X / d, -q.Z / d
			end
			-- About X tips the top toward +Z; about Z by a negative angle, toward +X
			best, bestX, bestZ = angle, awayZ * angle, -awayX * angle
		end
	end
	return bestX, bestZ
end

local function setFaded(plant: Plant, faded: boolean)
	if plant.faded == faded then
		return
	end
	plant.faded = faded
	for _, part in plant.parts do
		if part.Parent ~= nil and part.Transparency < 1 then
			part.LocalTransparencyModifier = if faded then FADED else 0
		end
	end
end

local function step(dt: number)
	clock += dt
	sinceScan += dt
	if sinceScan >= RESCAN then
		sinceScan = 0
		rescan()
	end
	local camera = Workspace.CurrentCamera.CFrame.Position
	gatherSwimmers(camera)
	table.clear(parts)
	table.clear(frames)
	for _, plant in active do
		-- Give way to fish, quickly, and spring back slowly
		local wantX, wantZ = leanFor(plant)
		local pushing = wantX ~= 0 or wantZ ~= 0
		local ease = math.min(1, dt * (if pushing then LEAN_IN else LEAN_OUT))
		plant.pushX += (wantX - plant.pushX) * ease
		plant.pushZ += (wantZ - plant.pushZ) * ease
		local eye = plant.base:PointToObjectSpace(camera)
		setFaded(
			plant,
			eye.Y > -1 and eye.Y < plant.height + 1 and math.sqrt(eye.X * eye.X + eye.Z * eye.Z) < FADE_RADIUS
		)
		-- A slow lean that wanders round, so no two plants nod together
		local a = plant.amplitude
		local tilt = CFrame.Angles(
			a * math.sin(clock * plant.rate + plant.phase) + plant.pushX,
			0,
			a * 0.7 * math.sin(clock * plant.rate * 0.73 + plant.phase * 1.3) + plant.pushZ
		)
		local frame = plant.base * tilt
		for i, part in plant.parts do
			if part.Parent ~= nil then
				table.insert(parts, part)
				table.insert(frames, frame * plant.offsets[i])
			end
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function KelpController.start()
	task.spawn(function()
		-- The kelp lives in World.Biomes.Kelp, built once the Terrain answers raycasts
		local world = Workspace:WaitForChild("World", 60)
		local biomes = if world then world:WaitForChild("Biomes", 120) else nil
		folder = if biomes then biomes:WaitForChild("Kelp", 120) else nil
		if folder == nil then
			return
		end
		RunService.RenderStepped:Connect(step)
	end)
end

return KelpController
