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
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

type Plant = {
	base: CFrame, -- the stalk's foot, upright
	parts: { BasePart },
	offsets: { CFrame }, -- each part from the base
	phase: number,
	rate: number,
	amplitude: number,
}

local REACH = 180 -- studs from the camera a plant still sways
local RESCAN = 0.5 -- seconds between picking the plants in reach

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
	}
	for _, part in partsOf(plant) do
		table.insert(entry.parts, part)
		table.insert(entry.offsets, base:ToObjectSpace(restOf(part)))
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

local function step(dt: number)
	clock += dt
	sinceScan += dt
	if sinceScan >= RESCAN then
		sinceScan = 0
		rescan()
	end
	table.clear(parts)
	table.clear(frames)
	for _, plant in active do
		-- A slow lean that wanders round, so no two plants nod together
		local a = plant.amplitude
		local tilt = CFrame.Angles(
			a * math.sin(clock * plant.rate + plant.phase),
			0,
			a * 0.7 * math.sin(clock * plant.rate * 0.73 + plant.phase * 1.3)
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
