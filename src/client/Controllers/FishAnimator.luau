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
local Timing = require(ReplicatedStorage.Shared.Timing)
local FishBuilder = require(ReplicatedStorage.Shared.FishBuilder)
local FishPlans = require(ReplicatedStorage.Shared.FishPlans)
local Size = require(ReplicatedStorage.Shared.Size)
local SwimWave = require(ReplicatedStorage.Shared.SwimWave)
local SkinLoader = require(script.Parent.Parent.SkinLoader)
local Spring = require(script.Parent.Parent.Spring)
local SwimController = require(script.Parent.SwimController)

type FishState = {
	body: Model,
	root: BasePart,
	joints: { [string]: Motor6D },
	bones: { [string]: Bone }, -- a rigged mesh body's bones (Head, Spine1.., Tail)
	boneFrames: { [string]: CFrame }, -- each bone's rest rotation in the fish's own axes
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
	puff: number, -- a Pufferfish's Puff Up: the body drawn this much bigger, eased
	puffVelocity: number,
}

local FishAnimator = {}

local states: { [Model]: FishState } = {}
local clock = 0

-- The bank's growth sequence (BankController): your own fish drawn back at the size
-- it started the dive at, then growing to its new banked size with a pop, instead of
-- the spring toward the server's length (owner, 2026-10-18: "needs to be animation
-- when they drop the haul off showing the fish getting bigger too")
type GrowthShow = {
	character: Model,
	from: number, -- the length before the bank
	to: number, -- the length after it
	pop: number, -- how far past `to` the pop overshoots
	start: number, -- `clock` when it began
	duration: number,
	startLength: number?, -- the length drawn when it began (taken on the first frame)
}
local growth: GrowthShow? = nil
local SHRINK = 0.15 -- share of the show easing back to the old size
local HOLD = 0.3 -- ...and holding it, before the growth
local OVERSHOOT_AT = 0.45 -- share of the growth spent rising past the new size

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

-- A body's bones, each one's rest rotation in the fish's own axes, and its spine.
-- Imported bones point their own Y down the spine (Blender's bone axis), so a turn
-- about a bone's Y rolled the body instead of swinging the tail (playtest
-- 2026-10-07). Keep each bone's rest rotation in the fish's axes to turn the
-- animation's fish-axis rotations into the bone's own.
local function rigOf(body: Model, root: BasePart): ({ [string]: Bone }, { [string]: CFrame }, { string })
	local bones, boneSpine = bonesOf(body)
	local boneFrames: { [string]: CFrame } = {}
	for name, bone in bones do
		local rest = root.CFrame:ToObjectSpace(bone.WorldCFrame * bone.Transform:Inverse())
		boneFrames[name] = rest.Rotation
	end
	local spine = if #boneSpine > 0 then boneSpine else FishPlans.spine(body:GetAttribute("Plan") :: string?)
	return bones, boneFrames, spine
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
	local bones, boneFrames, spine = rigOf(body, root)
	local state: FishState = {
		body = body,
		root = root,
		joints = FishBuilder.joints(body),
		bones = bones,
		boneFrames = boneFrames,
		spine = spine,
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
		puff = 1,
		puffVelocity = 0,
	}
	states[character] = state
	character.Destroying:Connect(function()
		states[character] = nil
	end)
	return state
end

-- The bank's growth sequence on your own fish: from its drawn size back to `from`,
-- a beat, then up to `to` with a pop, over `seconds` (BankController). Returns the
-- moment (seconds from now) the growth itself starts, for the sparkles and sound.
function FishAnimator.showGrowth(from: number, to: number, seconds: number): number
	local character = Players.LocalPlayer.Character
	if character == nil then
		return 0
	end
	growth = {
		character = character,
		from = from,
		to = to,
		pop = math.max(to * 0.1, (to - from) * 0.3),
		start = clock,
		duration = seconds,
		startLength = nil,
	}
	return seconds * (SHRINK + HOLD)
end

-- Ends the growth sequence now (skipped): the fish springs on to its real size
function FishAnimator.endGrowth()
	growth = nil
end

-- The length your own fish is drawn at right now (the growth card counts with it)
function FishAnimator.drawnLength(): number?
	local character = Players.LocalPlayer.Character
	local state = if character then states[character] else nil
	return if state then state.length else nil
end

-- Snaps a fish's jaw (its bite, or the server telling us someone bit).
function FishAnimator.snap(character: Model)
	local state = stateOf(character)
	if state then
		state.snapUntil = clock + 0.12
	end
end

-- Drives a part body's Motor6D or a mesh body's Bone of that name (both take an
-- animated offset in Transform). `cframe` is a rotation in the fish's own axes (Y
-- up, -Z ahead), which a bone gets in its own axes.
local function setTransform(state: FishState, name: string, cframe: CFrame)
	local joint = state.joints[name]
	if joint then
		joint.Transform = cframe
		return
	end
	local bone = state.bones[name]
	if bone then
		local frame = state.boneFrames[name]
		bone.Transform = if frame then frame:Inverse() * cframe * frame else cframe
	end
end

local skinTestSeen: any = nil -- the SkinFailTest stamp last acted on

-- Puts on the fish's shade, parts and variant when they change (Shared/Cosmetics),
-- and re-sizes the shade's glow and glints when the fish has grown a lot.
local function dress(character: Model, state: FishState)
	local shade = character:GetAttribute("Shade")
	-- A skin still downloading is put on once it has arrived (SkinLoader)
	local skin = if state.body:GetAttribute("Mesh")
		then Cosmetics.skinOf(state.body, if typeof(shade) == "string" and shade ~= "" then shade else nil)
		else nil
	-- The admin's skin-loading test, on your own fish
	if skin and character == Players.LocalPlayer.Character then
		local test = Players.LocalPlayer:GetAttribute("SkinFailTest")
		if test ~= nil and test ~= skinTestSeen then
			skinTestSeen = test
			SkinLoader.claimTest(skin)
		end
	end
	-- A variant with its own model waits for that model's textures the same way
	-- (SkinLoader draws it hidden so they download): until they've arrived, at most
	-- 30 s, the fish keeps its own body (PC 2026-10-22: a shade on a fresh variant
	-- drew it a flat silhouette for 6-14 s)
	local variant = character:GetAttribute("Variant")
	local variantModel = if typeof(variant) == "string" and variant ~= ""
		then FishBuilder.variantTemplate(variant)
		else nil
	local variantState = if variantModel then SkinLoader.state(variantModel) else ""
	-- Its state is in the key, so it's put on when it stops waiting and put on
	-- afresh when a skin worn anyway has all its textures at last
	local key = `{shade}|{character:GetAttribute("Parts")}|{variant}|{variantState}|{if skin
		then SkinLoader.state(skin)
		else ""}`
	-- (not mid growth sequence: it dips and pops, and would re-dress twice)
	local grown = math.abs(state.length - state.dressLength) > state.dressLength * 0.25
		and not (growth and growth.character == character)
	if key == state.dressKey and not grown then
		return
	end
	local look = FishBuilder.lookOf(character)
	if look == nil then
		return
	end
	state.dressKey = key
	state.dressLength = state.length
	local wear = Cosmetics.dressOf(character)
	if variantState == "waiting" then
		wear.variant = nil
	end
	if Cosmetics.apply(state.body, look, wear, state.length, SkinLoader.ready) then
		-- A variant's own model went on (or came off): its bones are new
		state.bones, state.boneFrames, state.spine = rigOf(state.body, state.root)
		state.joints = FishBuilder.joints(state.body)
	end
	state.applied = -1 -- re-scale everything, new parts included
end

local function animate(character: Model, state: FishState, dt: number, isLocal: boolean)
	dress(character, state)
	local shade = character:GetAttribute("Shade")
	Cosmetics.animate(state.body, if typeof(shade) == "string" and shade ~= "" then shade else nil, clock)
	-- Growth: spring toward the server's length (or the bank's growth sequence)
	local show = growth
	if show and show.character == character then
		local startLength = show.startLength or state.length
		show.startLength = startLength
		local t = (clock - show.start) / show.duration
		if t >= 1 then
			growth = nil
			state.length, state.lengthVelocity = show.to, 0
		elseif t < SHRINK then
			local u = t / SHRINK
			state.length = startLength + (show.from - startLength) * (1 - (1 - u) ^ 2)
		elseif t < SHRINK + HOLD then
			state.length = show.from
		else
			-- Up past the new size, then a damped wobble settling on it
			local u = (t - SHRINK - HOLD) / (1 - SHRINK - HOLD)
			if u < OVERSHOOT_AT then
				local v = u / OVERSHOOT_AT
				state.length = show.from + (show.to + show.pop - show.from) * (1 - (1 - v) ^ 2)
			else
				local v = (u - OVERSHOOT_AT) / (1 - OVERSHOOT_AT)
				state.length = show.to + show.pop * math.exp(-4 * v) * math.cos(3 * math.pi * v)
			end
		end
		state.lengthVelocity = 0
	else
		local target = character:GetAttribute("Length")
		if typeof(target) == "number" then
			state.length, state.lengthVelocity =
				Spring.number(state.length, state.lengthVelocity, target, 7, dt)
		end
	end
	-- Puffed up (Config/Abilities PuffUp): swells with a bounce, shrinks when it ends
	local puffed = character:GetAttribute("Puffed")
	local wantPuff = if typeof(puffed) == "number" and puffed > Timing.clock()
		then Config.Abilities.byId.PuffUp.scale or 1.45
		else 1
	state.puff, state.puffVelocity = Spring.number(state.puff, state.puffVelocity, wantPuff, 14, dt)
	local drawn = state.length * state.puff
	if math.abs(drawn - state.applied) > drawn * 0.002 then
		state.applied = drawn
		FishBuilder.applyScale(state.body, drawn)
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
	-- (yawRate is + turning left and SwimWave's + bend swings the tail right, so the
	-- bend is the yaw rate's opposite: it had flung the tail out of the turn, as the
	-- predators did until 2026-10-19)
	state.bend, state.bendVelocity =
		Spring.number(state.bend, state.bendVelocity, math.clamp(-yawRate * 0.12, -0.4, 0.4), 10, dt)

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

	-- The jaw: open fast, then snap shut (a mesh body's Jaw bone, rig_fish.py --jaw on
	-- the 'Cuda and Reef Shark, a little less: past ~25° the 'Cuda's front teeth
	-- stretch)
	local wantJaw = if clock < state.snapUntil then 1 else 0
	state.jaw, state.jawVelocity = Spring.number(state.jaw, state.jawVelocity, wantJaw, 34, dt)
	local jawOpen = if state.joints.Jaw then 0.55 else 0.42
	setTransform(state, "Jaw", CFrame.Angles(-math.max(state.jaw, 0) * jawOpen, 0, 0))
	-- A mesh body's rolled parts ride its bones (a veil tail swings with the tail)
	Cosmetics.follow(state.body)
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
	-- Window skins move once the camera has (Cosmetics.windows)
	RunService:BindToRenderStep("ShadeWindows", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
		Cosmetics.windows(clock, dt)
	end)
	SwimController.lunged:connect(function()
		local character = SwimController.character()
		if character then
			FishAnimator.snap(character)
		end
	end)
end

return FishAnimator
