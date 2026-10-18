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
-- The fish swims by the player's aim (SwimController `aim`, set here), never by the
-- view rock has bent or a shake has turned.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Size = require(ReplicatedStorage.Shared.Size)
local Input = require(script.Parent.Parent.Input)
local Spring = require(script.Parent.Parent.Spring)
local SwimController = require(script.Parent.SwimController)
local ClientState = require(script.Parent.Parent.ClientState)

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

-- How big the camera frames your fish (owner, 2026-10-11: "ensure that player fish
-- are actually getting bigger as they grow"): the distance followed the length one
-- for one, so a fish grown 36% longer looked 8% bigger on screen. Now it follows the
-- banked length to the power `growFraming` and only `growHaul` of a dive's growth
-- (since 2026-10-18 `growFraming` 1.0 and a lens widening with size, `growFov`: a
-- grown fish no longer fills more of the screen; the bank shows the growth).
local function framedLength(live: number): number
	local s = ClientState.current
	local mass = if s and typeof(s.mass) == "number" then s.mass else nil
	local banked = if mass then math.min(Size.length(mass), live) else live
	local start = Size.length(Config.Tuning.size.startMass)
	return start * (banked / start) ^ tuning.growFraming + (live - banked) * tuning.growHaul
end

-- Your own fish's parts, faded when the camera is right on top of it.
local fadeCharacter: Model? = nil
local fadeParts: { BasePart } = {}
local fadeAdded: RBXScriptConnection? = nil
local fadeShown = 0
local fadeHid: { [BasePart]: boolean? } = {} -- parts this fade hid all the way (Build mode)

local function fadeFish(character: Model?, amount: number)
	if character ~= fadeCharacter then
		if fadeAdded then
			fadeAdded:Disconnect()
			fadeAdded = nil
		end
		fadeCharacter = character
		table.clear(fadeParts)
		table.clear(fadeHid)
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
	-- Small changes are skipped, but always land exactly on solid again
	if math.abs(amount - fadeShown) < 0.02 and not (amount == 0 and fadeShown ~= 0) then
		return
	end
	fadeShown = amount
	for _, part in fadeParts do
		-- 1 means Cosmetics hid it (a variant replaced it); leave those alone, but not
		-- the ones this fade hid itself (Build mode hides your fish at 1, and after
		-- DONE it stayed invisible: PC 2026-10-17, BC1)
		if part.LocalTransparencyModifier < 0.999 or fadeHid[part] then
			part.LocalTransparencyModifier = amount
			fadeHid[part] = if amount >= 0.999 then true else nil
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

-- Set by a view that takes the screen over (Build mode's editor): called every
-- frame with dt, it returns the camera's CFrame, or nil to give the fish camera back
CameraController.override = nil :: ((number) -> CFrame?)?
-- While an override has the screen: its lens, and whether your own fish is hidden
-- (Build mode: a LV 100 fish filled the editor's view, PC 2026-10-16 round 2)
CameraController.overrideFov = nil :: number?
CameraController.hideFish = false

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
	-- Another view has the screen (Build mode's editor): it places the camera and
	-- minds the cursor itself
	local override = CameraController.override
	if override then
		local cframe = override(dt)
		if cframe then
			camera.CFrame = cframe
			camera.FieldOfView = CameraController.overrideFov or tuning.fov
			fadeFish(SwimController.character(), if CameraController.hideFish then 1 else 0)
			hasFocus = false
			return
		end
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
	-- A stick's sideways push (controller, phone) turns the aim, at the fish's own
	-- turn rate so the camera and the fish swing round together
	local _, steer = Input.drive()
	if steer ~= 0 then
		local turn = SwimController.turnRate()
		yaw -= steer * math.clamp(turn * tuning.steerScale, tuning.steerMin, tuning.steerMax) * dt
	end
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
	local wantDistance = (tuning.baseDistance + tuning.perLength * framedLength(length)) * zoom * speciesScale
	if not hasFocus then
		focus, focusVelocity = target, Vector3.zero
		distance = wantDistance
		reach = wantDistance
		hasFocus = true
	end
	focus, focusVelocity = Spring.vector(focus, focusVelocity, target, tuning.focusSpring, dt)
	local lag = focus - target
	local limit = length * tuning.maxLag
	local knee = limit * tuning.lagKnee
	if lag.Magnitude > length * 6 + 30 then
		-- A respawn or a teleport: cut straight there, behind the fish and as far back
		-- as the rock allows (the sweep below still limits it). Leaving a den the camera
		-- kept the den's heading, ~110° off the fish, and eased out from ~3 studs, so the
		-- first second on the plaza looked through the doorway (PC 2026-10-18, LD2)
		focus, focusVelocity = target, Vector3.zero
		alignBehind(SwimController.heading())
		reach = wantDistance
	elseif lag.Magnitude > knee then
		-- At full speed the spring trailed far enough to shrink the fish to a dot
		-- (playtest re-test, 2026-10-06); a little trail still reads as motion. Past
		-- the knee the trail eases toward the limit instead of hitting it, so a Dash
		-- or a stop doesn't jolt the fish across the screen
		local over = lag.Magnitude - knee
		local span = limit - knee
		focus = target + lag.Unit * (knee + span * (1 - math.exp(-over / span)))
	end
	distance, distanceVelocity =
		Spring.number(distance, distanceVelocity, wantDistance, tuning.distanceSpring, dt)
	local start = Size.length(Config.Tuning.size.startMass)
	local grown = math.clamp((length - start) / math.max(Config.Tuning.size.lengthCap - start, 1), 0, 1)
	local wantFov = (if SwimController.boosting then tuning.boostFov else tuning.fov) + tuning.growFov * grown
	fov, fovVelocity = Spring.number(fov, fovVelocity, wantFov, 6, dt)

	local rotation = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	SwimController.aim = rotation
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
	-- and the things in the dens (the camera looks past a lamp, not into it)
	for _, folder in CollectionService:GetTagged("DenItems") do
		table.insert(ignore, folder)
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
	-- A Space tap can poke the fish into a ceiling for a moment, and a ray that
	-- starts inside rock doesn't see it: the camera went through a den roof for a few
	-- frames (playtest 2026-10-07). Last frame's camera spot was out of rock, so if
	-- the look-at point is hidden from it inside rock (a ray back out sees nothing,
	-- unlike a corner in the way), push the point straight out of the rock's face.
	local previous = camera.CFrame.Position
	local fromCamera = eye - previous
	if fromCamera.Magnitude > 1e-3 and fromCamera.Magnitude < wantDistance * 3 then
		local hit = workspace:Raycast(previous, fromCamera, rayParams)
		if hit and workspace:Raycast(eye, -fromCamera, rayParams) == nil then
			local depth = (eye - hit.Position):Dot(hit.Normal)
			eye -= hit.Normal * (depth - clearance)
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
	-- rest of the way along the rock and look back at the fish from there. How far
	-- it slides fades in with how flat the rock is (`slideFrom` → `slideFull` of the
	-- normal's height): a den's arched vault turns from roof to wall, and an on/off
	-- slide there threw the camera in and out as the fish moved under it
	local bend = eye + back * first
	local slide: Vector3? = nil
	local second = 0
	local flatness = if normal
		then math.clamp((math.abs(normal.Y) - tuning.slideFrom) / (tuning.slideFull - tuning.slideFrom), 0, 1)
		else 0
	if normal and flatness > 0 and first < distance - 0.05 then
		local along = back - normal * back:Dot(normal)
		if along.Magnitude > 0.05 then
			slide = along.Unit
			bend += normal * 0.05
			local free = sweep(bend, along.Unit, distance - first, nearBox, near)
			second = free * flatness * flatness * (3 - 2 * flatness)
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
