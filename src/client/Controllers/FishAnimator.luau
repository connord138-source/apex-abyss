--!strict
-- Swims every player's fish on this client: a wave travels down the spine (faster
-- and wider with speed), the body bends into turns, the pectoral fins flutter,
-- the jaw snaps on bites, and growth eases instead of popping (each fish's body
-- springs toward the length the server set).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FishBuilder = require(ReplicatedStorage.Shared.FishBuilder)
local Size = require(ReplicatedStorage.Shared.Size)
local Spring = require(script.Parent.Parent.Spring)
local SwimController = require(script.Parent.SwimController)

type FishState = {
	body: Model,
	root: BasePart,
	joints: { [string]: Motor6D },
	length: number, -- the eased length the body is drawn at
	lengthVelocity: number,
	applied: number, -- the length last applied to the parts
	phase: number,
	amplitude: number,
	bend: number,
	bendVelocity: number,
	jaw: number,
	jawVelocity: number,
	snapUntil: number,
	heading: Vector3,
}

local FishAnimator = {}

local states: { [Model]: FishState } = {}
local clock = 0

local function stateOf(character: Model): FishState?
	local existing = states[character]
	if existing then
		return existing
	end
	local body = character:FindFirstChild("Body")
	local root = character:FindFirstChild("HumanoidRootPart")
	if body == nil or not body:IsA("Model") or root == nil or not root:IsA("BasePart") then
		return nil
	end
	local length = character:GetAttribute("Length")
	local start = if typeof(length) == "number" then length else 2
	local state: FishState = {
		body = body,
		root = root,
		joints = FishBuilder.joints(body),
		length = start,
		lengthVelocity = 0,
		applied = -1,
		phase = math.random() * 10,
		amplitude = 0.1,
		bend = 0,
		bendVelocity = 0,
		jaw = 0,
		jawVelocity = 0,
		snapUntil = 0,
		heading = root.CFrame.LookVector,
	}
	states[character] = state
	character.Destroying:Connect(function()
		states[character] = nil
	end)
	return state
end

-- Snaps a fish's jaw (its bite, or the server telling us someone bit).
function FishAnimator.snap(character: Model)
	local state = stateOf(character)
	if state then
		state.snapUntil = clock + 0.12
	end
end

local function setTransform(joints: { [string]: Motor6D }, name: string, cframe: CFrame)
	local joint = joints[name]
	if joint then
		joint.Transform = cframe
	end
end

local function animate(character: Model, state: FishState, dt: number, isLocal: boolean)
	-- Growth: spring toward the server's length
	local target = character:GetAttribute("Length")
	if typeof(target) == "number" then
		state.length, state.lengthVelocity = Spring.number(state.length, state.lengthVelocity, target, 7, dt)
	end
	if math.abs(state.length - state.applied) > state.length * 0.002 then
		state.applied = state.length
		FishBuilder.applyScale(state.body, state.length)
	end

	local velocity = if isLocal then SwimController.velocity else state.root.AssemblyLinearVelocity
	local speed = velocity.Magnitude
	local relative = math.clamp(speed / Size.topSpeed(state.length), 0, 2)
	local boosting = relative > 1.15
	local frequency = 0.9 + 3.6 * relative -- tail beats a second
	local wantAmplitude = 0.08 + 0.26 * math.min(relative, 1) + (if boosting then 0.1 else 0)
	state.amplitude += (wantAmplitude - state.amplitude) * Spring.alpha(4, dt)
	state.phase += 2 * math.pi * frequency * dt

	-- Turning: the body curves toward the turn
	local look = state.root.CFrame.LookVector
	local flatBefore = Vector3.new(state.heading.X, 0, state.heading.Z)
	local flatNow = Vector3.new(look.X, 0, look.Z)
	local yawRate = 0
	if flatBefore.Magnitude > 1e-3 and flatNow.Magnitude > 1e-3 and dt > 0 then
		yawRate = math.asin(math.clamp(flatBefore.Unit:Cross(flatNow.Unit).Y, -1, 1)) / dt
	end
	state.heading = look
	state.bend, state.bendVelocity =
		Spring.number(state.bend, state.bendVelocity, math.clamp(yawRate * 0.12, -0.4, 0.4), 10, dt)

	local p, a, bend = state.phase, state.amplitude, state.bend
	setTransform(state.joints, "Head", CFrame.Angles(0, math.sin(p + 0.5) * a * 0.12 + bend * 0.3, 0))
	setTransform(state.joints, "Body2", CFrame.Angles(0, math.sin(p - 0.7) * a * 0.45 + bend * 0.5, 0))
	setTransform(state.joints, "Body3", CFrame.Angles(0, math.sin(p - 1.4) * a * 0.8 + bend * 0.6, 0))
	setTransform(state.joints, "Stalk", CFrame.Angles(0, math.sin(p - 2.1) * a * 1.25 + bend * 0.5, 0))
	local flutter = math.sin(p * 0.5) * (0.15 + 0.25 * (1 - math.min(relative, 1)))
	setTransform(state.joints, "FinL", CFrame.Angles(0, 0, flutter))
	setTransform(state.joints, "FinR", CFrame.Angles(0, 0, -flutter))

	-- The jaw: open fast, then snap shut
	local wantJaw = if clock < state.snapUntil then 1 else 0
	state.jaw, state.jawVelocity = Spring.number(state.jaw, state.jawVelocity, wantJaw, 34, dt)
	setTransform(state.joints, "Jaw", CFrame.Angles(-math.max(state.jaw, 0) * 0.55, 0, 0))
end

local function step(dt: number)
	clock += dt
	local localPlayer = Players.LocalPlayer
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and character.Parent then
			local state = stateOf(character)
			if state then
				animate(character, state, dt, player == localPlayer)
			end
		end
	end
end

function FishAnimator.start()
	RunService.PreSimulation:Connect(step)
	SwimController.lunged:connect(function()
		local character = SwimController.character()
		if character then
			FishAnimator.snap(character)
		end
	end)
end

return FishAnimator
