--!strict
-- The third-person camera. The player aims it (mouse, right stick or a touch
-- drag) and the fish swims where it points. The look-at point trails the fish on
-- a spring, so motion reads as fluid rather than glued on; the camera pulls back
-- smoothly as the fish grows, widens a little while boosting, and never clips into
-- rock: the look-at point is kept out of rock first (it once sat inside a den's
-- ceiling, so the ray started past it), then a sphere swept back from it pulls the
-- camera in, snapping in and easing back out.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Input = require(script.Parent.Parent.Input)
local Spring = require(script.Parent.Parent.Spring)
local SwimController = require(script.Parent.SwimController)

local tuning = Config.Tuning.camera

local CameraController = {}

local yaw, pitch = 0, -0.15
local focus, focusVelocity = Vector3.zero, Vector3.zero
local distance, distanceVelocity = 12, 0
local zoom = 1
local reach = 12
local fov, fovVelocity = tuning.fov, 0
local shake = 0
local hasFocus = false
-- Until the fish spawns, look over the hub from above its roof
local lastPosition: Vector3? = Config.World.hub.center + Vector3.new(0, Config.World.hub.height + 40, 0)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- A short jolt (a bite landing, being bitten).
function CameraController.kick(strength: number)
	shake = math.max(shake, strength)
end

-- Faces the camera along a fish's heading (on spawn).
local function alignBehind(heading: Vector3)
	local flat = Vector3.new(heading.X, 0, heading.Z)
	if flat.Magnitude > 1e-3 then
		yaw = math.atan2(-flat.X, -flat.Z)
	end
	pitch = -0.12
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	-- Mouse look: lock the cursor unless the player wants it (Alt, or a menu)
	if Input.wantsMouseLock() then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end

	local look = Input.consumeLook(dt)
	yaw -= look.X
	pitch = math.clamp(pitch - look.Y, tuning.minPitch, tuning.maxPitch)

	local notches = Input.consumeZoom()
	if notches ~= 0 then
		zoom = math.clamp(zoom - notches * tuning.zoomStep, tuning.zoomMin, tuning.zoomMax)
	end

	local root = SwimController.root()
	local length = SwimController.length()
	local target = if root then root.Position + Vector3.new(0, length * tuning.height, 0) else lastPosition
	if target == nil then
		return
	end
	lastPosition = target
	local wantDistance = (tuning.baseDistance + tuning.perLength * length) * zoom
	if not hasFocus then
		focus, focusVelocity = target, Vector3.zero
		distance = wantDistance
		reach = wantDistance
		hasFocus = true
	end
	focus, focusVelocity = Spring.vector(focus, focusVelocity, target, tuning.focusSpring, dt)
	-- Never let the focus fall too far behind (a respawn, a teleport)
	if (focus - target).Magnitude > length * 6 + 30 then
		focus, focusVelocity = target, Vector3.zero
	end
	distance, distanceVelocity =
		Spring.number(distance, distanceVelocity, wantDistance, tuning.distanceSpring, dt)
	local wantFov = if SwimController.boosting then tuning.boostFov else tuning.fov
	fov, fovVelocity = Spring.number(fov, fovVelocity, wantFov, 6, dt)

	local rotation = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local back = -rotation.LookVector
	-- Keep out of rock. Everything that moves is ignored: fish, prey and pickups.
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	for _, name in { "Prey", "Forage", "Shells" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
	local clearance = math.clamp(length * tuning.clearance, tuning.clearanceMin, tuning.clearanceMax)
	-- 1. The look-at point sits above the fish and trails it, so against a ceiling
	-- or a wall it can end up inside the rock; pull it back toward the fish
	local eye = focus
	local anchor = if root then root.Position else focus
	local toEye = eye - anchor
	if toEye.Magnitude > 1e-3 then
		local blocked = workspace:Raycast(anchor, toEye, rayParams)
		if blocked then
			eye = anchor + toEye.Unit * math.max(blocked.Distance - clearance, 0)
		end
	end
	-- 2. Sweep a sphere back from there; snap in when blocked, ease back out
	local want = distance
	local hit = workspace:Spherecast(eye, clearance, back * distance, rayParams)
	if hit then
		want = math.max(hit.Distance, 0.3)
	end
	if want < reach then
		reach = want
	else
		reach += (want - reach) * (1 - math.exp(-dt * 5))
	end
	local position = eye + back * reach
	if shake > 0.001 then
		local t = os.clock() * 40
		position += Vector3.new(math.noise(t, 0, 0), math.noise(0, t, 0), math.noise(0, 0, t)) * shake * length * 0.5
		shake *= math.exp(-dt * 9)
	end
	camera.CFrame = CFrame.new(position) * rotation
	camera.FieldOfView = fov
end

function CameraController.start()
	SwimController.spawned:connect(function()
		alignBehind(SwimController.heading())
		hasFocus = false
	end)
	RunService:BindToRenderStep("ApexCamera", Enum.RenderPriority.Camera.Value + 1, update)
	-- The default camera keeps resetting this on spawn; ours wins every frame anyway
	Players.LocalPlayer.CharacterAdded:Connect(function()
		workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
	end)
end

return CameraController
