--!strict
-- Kelp sways (owner, 2026-10-08: nothing in the water moved but the fish). Every
-- kelp plant the server built (workspace.World.Kelp, "Kelp" models) bends gently
-- about its base in a slow current. Only the plants within reach of the camera
-- move, in one BulkMoveTo a frame, so a thousand plants cost nothing.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

type Plant = {
	base: CFrame, -- the stalk's foot, upright
	parts: { BasePart },
	offsets: { CFrame }, -- each part from the base
	phase: number,
	rate: number,
	amplitude: number,
	position: Vector3,
}

local REACH = 180 -- studs from the camera a plant still sways
local RESCAN = 0.5 -- seconds between picking the plants in reach

local KelpController = {}

local plants: { Plant } = {}
local active: { Plant } = {}
local parts: { BasePart } = {}
local frames: { CFrame } = {}
local clock = 0
local sinceScan = RESCAN

local rng = Random.new(7)

local function collectOne(plant: Instance)
	local stalk = plant:FindFirstChild("Stalk")
	if not plant:IsA("Model") or stalk == nil or not stalk:IsA("BasePart") then
		return
	end
	local base = stalk.CFrame * CFrame.new(0, -stalk.Size.Y / 2, 0)
	local entry: Plant = {
		base = base,
		parts = {},
		offsets = {},
		phase = rng:NextNumber(0, 6.28),
		rate = rng:NextNumber(0.3, 0.55),
		amplitude = rng:NextNumber(0.035, 0.07),
		position = base.Position,
	}
	for _, descendant in plant:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(entry.parts, descendant)
			table.insert(entry.offsets, base:ToObjectSpace(descendant.CFrame))
		end
	end
	if #entry.parts > 0 then
		table.insert(plants, entry)
	end
end

local function rescan()
	table.clear(active)
	local camera = Workspace.CurrentCamera.CFrame.Position
	for _, plant in plants do
		-- (a plant whose parts streamed out or were rebuilt is skipped)
		if (plant.position - camera).Magnitude < REACH and plant.parts[1].Parent ~= nil then
			table.insert(active, plant)
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
			table.insert(parts, part)
			table.insert(frames, frame * plant.offsets[i])
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function KelpController.start()
	task.spawn(function()
		local world = Workspace:WaitForChild("World", 30)
		local folder = if world then world:WaitForChild("Kelp", 30) else nil
		if folder == nil then
			return
		end
		for _, plant in folder:GetChildren() do
			collectOne(plant)
		end
		-- Plants that arrive later (Studio can be quicker than the server's build)
		folder.ChildAdded:Connect(function(child)
			task.delay(1, collectOne, child) -- once its parts and prop are in
		end)
		RunService.RenderStepped:Connect(step)
	end)
end

return KelpController
