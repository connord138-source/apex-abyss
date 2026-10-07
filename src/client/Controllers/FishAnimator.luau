--!strict
-- Swims every player's fish on this client: a wave travels down the spine (faster
-- and wider with speed), the body bends into turns, the pectoral fins flutter,
-- the jaw snaps on bites, and growth eases instead of popping (each fish's body
-- springs toward the length the server set).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Config = require(ReplicatedStorage.Shared.Config)
local FishBuilder = require(ReplicatedStorage.Shared.FishBuilder)
local FishPlans = require(ReplicatedStorage.Shared.FishPlans)
local Size = require(ReplicatedStorage.Shared.Size)
local SwimWave = require(ReplicatedStorage.Shared.SwimWave)
local Spring = require(script.Parent.Parent.Spring)
local SwimController = require(script.Parent.SwimController)

type FishState = {
	body: Model,
	root: BasePart,
	joints: { [string]: Motor6D },
	bones: { [string]: Bone }, -- a rigged mesh body's bones (Head, Spine1.., Tail)
	spine: { string }, -- segments behind Body1, front to back (the body plan's)
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
	dressKey: string, -- the Shade/Parts/Variant attributes last dressed from
	dressLength: number, -- the length the shade's effects were sized for
}

local FishAnimator = {}

local states: { [Model]: FishState } = {}
local clock = 0

-- The bones of an imported mesh body, by name, and its spine order (Spine1..N then
-- Tail), or nothing for a part body.
local function bonesOf(body: Model): ({ [string]: Bone }, { string })
	local bones: { [string]: Bone } = {}
	local spine: { string } = {}
	if body:GetAttribute("Mesh") then
		for _, descendant in body:GetDescendants() do
			if descendant:IsA("Bone") then
				bones[descendant.Name] = descendant
			end
		end
		local i = 1
		while bones[`Spine{i}`] do
			table.insert(spine, `Spine{i}`)
			i += 1
		end
		if bones.Tail then
			table.insert(spine, "Tail")
		end
	end
	return bones, spine
end

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
	local bones, boneSpine = bonesOf(body)
	local state: FishState = {
		body = body,
		root = root,
		joints = FishBuilder.joints(body),
		bones = bones,
		spine = if #boneSpine > 0 then boneSpine else FishPlans.spine(body:GetAttribute("Plan") :: string?),
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
		dressKey = "",
		dressLength = start,
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

-- Drives a part body's Motor6D or a mesh body's Bone of that name (both take an
-- animated offset in Transform).
local function setTransform(state: FishState, name: string, cframe: CFrame)
	local joint = state.joints[name]
	if joint then
		joint.Transform = cframe
		return
	end
	local bone = state.bones[name]
	if bone then
		bone.Transform = cframe
	end
end

-- Puts on the fish's shade, parts and variant when they change (Shared/Cosmetics),
-- and re-sizes the shade's glow and glints when the fish has grown a lot.
local function dress(character: Model, state: FishState)
	local shade = character:GetAttribute("Shade")
	local key = `{shade}|{character:GetAttribute("Parts")}|{character:GetAttribute("Variant")}`
	local grown = math.abs(state.length - state.dressLength) > state.dressLength * 0.25
	if key == state.dressKey and not grown then
		return
	end
	local look = FishBuilder.lookOf(character)
	if look == nil then
		return
	end
	state.dressKey = key
	state.dressLength = state.length
	Cosmetics.apply(state.body, look, Cosmetics.dressOf(character), state.length)
	state.applied = -1 -- re-scale everything, new parts included
end

local function animate(character: Model, state: FishState, dt: number, isLocal: boolean)
	dress(character, state)
	local shade = character:GetAttribute("Shade")
	Cosmetics.animate(state.body, if typeof(shade) == "string" and shade ~= "" then shade else nil, clock)
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
	local species = Config.Species.byId[character:GetAttribute("Species") :: any]
	local top = Size.topSpeed(state.length) * (if species then species.stats.speed else 1)
	local relative = math.clamp(speed / top, 0, 2)
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
	-- The head holds still; only a turn bends it (Shared/SwimWave: a real fish whips
	-- its back half and keeps its shoulders steady). Long bodies (the eel) carry the
	-- wave with a gentler bend at each joint.
	setTransform(state, "Head", CFrame.Angles(0, SwimWave.headYaw(bend), 0))
	local n = #state.spine
	local soften = (3 / n) ^ 0.6
	for i, name in state.spine do
		setTransform(
			state,
			name,
			CFrame.Angles(0, SwimWave.yaw(i, n, p, a * 1.6 * soften, bend * 0.55 * soften), 0)
		)
	end
	local flutter = math.sin(p * 0.5) * (0.15 + 0.25 * (1 - math.min(relative, 1)))
	setTransform(state, "FinL", CFrame.Angles(0, 0, flutter))
	setTransform(state, "FinR", CFrame.Angles(0, 0, -flutter))

	-- The jaw: open fast, then snap shut
	local wantJaw = if clock < state.snapUntil then 1 else 0
	state.jaw, state.jawVelocity = Spring.number(state.jaw, state.jawVelocity, wantJaw, 34, dt)
	setTransform(state, "Jaw", CFrame.Angles(-math.max(state.jaw, 0) * 0.55, 0, 0))
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
