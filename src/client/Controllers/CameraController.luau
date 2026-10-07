--!strict
-- The third-person camera. The player aims it (mouse, right stick or a touch
-- drag) and the fish swims where it points. The look-at point trails the fish on
-- a spring, so motion reads as fluid rather than glued on; the camera pulls back
-- smoothly as the fish grows, widens a little while boosting, and never clips into
-- rock: the look-at point is kept out of rock first (it once sat inside a den's
-- ceiling, so the ray started past it), then a ray and a near-plane-sized box swept
-- back from it pull the camera in, snapping in and easing back out. Under a ceiling
-- (or on the seabed) it slides along the rock instead of collapsing into the fish,
-- and when it does end up close, your own fish fades so it doesn't fill the view.
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

-- Your own fish's parts, faded when the camera is right on top of it.
local fadeCharacter: Model? = nil
local fadeParts: { BasePart } = {}
local fadeAdded: RBXScriptConnection? = nil
local fadeShown = 0

local function fadeFish(character: Model?, amount: number)
	if character ~= fadeCharacter then
		if fadeAdded then
			fadeAdded:Disconnect()
			fadeAdded = nil
		end
		fadeCharacter = character
		table.clear(fadeParts)
		fadeShown = -1
		if character then
			for _, item in character:GetDescendants() do
				if item:IsA("BasePart") then
					table.insert(fadeParts, item)
				end
			end
			fadeAdded = character.DescendantAdded:Connect(function(item)
				if item:IsA("BasePart") then
					table.insert(fadeParts, item)
					fadeShown = -1
				end
			end)
		end
	end
	if math.abs(amount - fadeShown) < 0.02 then
		return
	end
	fadeShown = amount
	for _, part in fadeParts do
		-- 1 means Cosmetics hid it (a variant replaced it); leave those alone
		if part.LocalTransparencyModifier < 0.999 then
			part.LocalTransparencyModifier = amount
		end
	end
end

-- How far a near-plane-sized box can travel from `origin` along `direction` (a unit
-- vector) before it touches rock, with a ray down the middle as well: a sweep
-- ignores whatever it starts touching (a sphere that grazed a den roof once let the
-- camera through it). Returns the free distance and the normal of what stopped it.
local function sweep(
	origin: Vector3,
	direction: Vector3,
	length: number,
	box: Vector3,
	near: number
): (number, Vector3?)
	local free, normal: Vector3? = length, nil
	local ray = workspace:Raycast(origin, direction * length, rayParams)
	if ray then
		free, normal = math.max(ray.Distance - near - 0.1, 0), ray.Normal
	end
	local frame = CFrame.lookAt(origin, origin - direction)
	local swept = workspace:Blockcast(frame, box, direction * length, rayParams)
	if swept and swept.Distance < free then
		free, normal = swept.Distance, swept.Normal
	end
	return free, normal
end

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
	local character = SwimController.character()
	-- Thin fish sit a little closer (Config/Species `camera`)
	local speciesId = if character then character:GetAttribute("Species") else nil
	local species = if typeof(speciesId) == "string" then Config.Species.byId[speciesId] else nil
	local speciesScale = if species and species.camera then species.camera else 1
	local target = if root then root.Position + Vector3.new(0, length * tuning.height, 0) else lastPosition
	if target == nil then
		return
	end
	lastPosition = target
	local wantDistance = (tuning.baseDistance + tuning.perLength * length) * zoom * speciesScale
	if not hasFocus then
		focus, focusVelocity = target, Vector3.zero
		distance = wantDistance
		reach = wantDistance
		hasFocus = true
	end
	focus, focusVelocity = Spring.vector(focus, focusVelocity, target, tuning.focusSpring, dt)
	local lag = focus - target
	if lag.Magnitude > length * 6 + 30 then
		-- A respawn or a teleport: cut straight there
		focus, focusVelocity = target, Vector3.zero
	elseif lag.Magnitude > length * tuning.maxLag then
		-- At full speed the spring trailed far enough to shrink the fish to a dot
		-- (playtest re-test, 2026-10-06); a little trail still reads as motion
		focus = target + lag.Unit * length * tuning.maxLag
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
	-- 2. How far back the camera can go, the size of its near plane kept clear so
	-- the view's edges stay out of rock at grazing angles
	local near = math.abs(camera.NearPlaneZ)
	local halfHeight = near * math.tan(math.rad(fov / 2)) * 1.6
	local viewport = camera.ViewportSize
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	local nearBox = Vector3.new(halfHeight * aspect * 2, halfHeight * 2, near * 2)
	local first, normal = sweep(eye, back, distance, nearBox, near)
	-- 3. Stopped by a ceiling (looking down) or the seabed (looking up): rather than
	-- collapse into the fish (it sat 0.7 studs off, re-test 2026-10-07), slide the
	-- rest of the way along the rock and look back at the fish from there
	local bend = eye + back * first
	local slide: Vector3? = nil
	local second = 0
	if normal and math.abs(normal.Y) > 0.6 and first < distance - 0.05 then
		local along = back - normal * back:Dot(normal)
		if along.Magnitude > 0.05 then
			slide = along.Unit
			bend += normal * 0.05
			second = sweep(bend, along.Unit, distance - first, nearBox, near)
		end
	end
	-- Snap in when blocked, ease back out (measured along the path, bend included)
	local want = first + second
	if want < reach then
		reach = want
	else
		reach += (want - reach) * (1 - math.exp(-dt * 5))
	end
	local position = eye + back * math.min(reach, first)
	local view = rotation
	if slide and reach > first then
		position = bend + slide * (reach - first)
		view = CFrame.lookAt(position, eye).Rotation
	end
	-- Shake turns the camera rather than moving it, so it can't knock it into rock
	local jolt = CFrame.identity
	if shake > 0.001 then
		local t = os.clock() * 40
		jolt = CFrame.Angles(math.noise(t, 0, 0) * shake * 0.06, math.noise(0, t, 0) * shake * 0.06, 0)
		shake *= math.exp(-dt * 9)
	end
	camera.CFrame = CFrame.new(position) * view * jolt
	-- Right on top of your own fish (its back to a wall), fade it out of the way
	local fade = 0
	if root then
		local gap = (position - root.Position).Magnitude
		fade = math.clamp((length * 1.3 - gap) / (length * 0.8), 0, 0.8)
	end
	fadeFish(character, fade)
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
