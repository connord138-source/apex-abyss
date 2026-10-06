--!strict
-- Moves the player's own fish. It runs on this client every frame (the client
-- owns its fish's physics), so there's never any input lag; the server only
-- checks what it does.
--
-- Feel: the fish has momentum (it accelerates and coasts), its heading can only
-- swing so fast (big fish turn slower), it banks into turns, and a boost starts
-- with a tail flick. Velocity drives a LinearVelocity and the heading an
-- AlignOrientation, so walls and rocks still collide naturally.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Size = require(ReplicatedStorage.Shared.Size)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Spring = require(script.Parent.Parent.Spring)

local swim = Config.Tuning.swim
local World = Config.World

local SwimController = {
	velocity = Vector3.zero,
	boosting = false, -- mid-Dash
	dashCharge = 1, -- 0..1; the Dash is ready at 1
	-- () — a bite lunge started (the animator snaps the jaw)
	lunged = Signal.new(),
	-- (character) — our fish spawned
	spawned = Signal.new(),
}

local character: Model? = nil
local root: BasePart? = nil
local linear: LinearVelocity? = nil
local align: AlignOrientation? = nil
local heading = Vector3.new(0, 0, -1) -- unit, the way the fish faces
local roll, rollVelocity = 0, 0
local lungeUntil = 0
local lastBiteAt = -math.huge
local dashUntil = 0
local dashStarted = false
local clock = 0

local function rotateToward(from: Vector3, to: Vector3, maxAngle: number): Vector3
	local dot = math.clamp(from:Dot(to), -1, 1)
	local angle = math.acos(dot)
	if angle <= maxAngle or angle < 1e-4 then
		return to
	end
	local axis = from:Cross(to)
	if axis.Magnitude < 1e-5 then
		-- Exactly opposite: turn about the up axis (or any axis when vertical)
		axis = if math.abs(from.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
	end
	return CFrame.fromAxisAngle(axis.Unit, maxAngle):VectorToWorldSpace(from)
end

-- Keeps a heading within the pitch limit, so the fish never flips over the top.
local function limitPitch(direction: Vector3): Vector3
	local maxY = math.sin(swim.maxPitch)
	if math.abs(direction.Y) <= maxY then
		return direction
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-4 then
		flat = Vector3.new(heading.X, 0, heading.Z)
		if flat.Magnitude < 1e-4 then
			flat = Vector3.new(0, 0, -1)
		end
	end
	local y = math.sign(direction.Y) * maxY
	return (flat.Unit * math.sqrt(1 - y * y) + Vector3.new(0, y, 0)).Unit
end

function SwimController.length(): number
	if character then
		local length = character:GetAttribute("Length")
		if typeof(length) == "number" then
			return length
		end
	end
	return Size.length(Config.Tuning.size.startMass)
end

function SwimController.root(): BasePart?
	return root
end

function SwimController.character(): Model?
	return character
end

function SwimController.heading(): Vector3
	return heading
end

-- Starts a Dash if it has recharged; returns whether it did.
function SwimController.dash(): boolean
	if root == nil or SwimController.dashCharge < 1 then
		return false
	end
	SwimController.dashCharge = 0
	dashUntil = clock + swim.dashSeconds
	dashStarted = true
	return true
end

-- Starts a bite lunge if the cooldown allows; returns whether it did.
function SwimController.lunge(): boolean
	if root == nil or clock - lastBiteAt < swim.biteCooldown then
		return false
	end
	lastBiteAt = clock
	lungeUntil = clock + swim.lungeSeconds
	SwimController.lunged:fire()
	return true
end

local function onCharacter(newCharacter: Model)
	character = newCharacter
	local newRoot = newCharacter:WaitForChild("HumanoidRootPart", 10)
	if newRoot == nil or not newRoot:IsA("BasePart") or character ~= newCharacter then
		return
	end
	root = newRoot
	local attachment = newRoot:WaitForChild("RootAttachment", 10)
	if attachment == nil or not attachment:IsA("Attachment") then
		return
	end
	-- Our own constraints, made on this client: the owner simulates the fish
	local newLinear = Instance.new("LinearVelocity")
	newLinear.Attachment0 = attachment
	newLinear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	newLinear.RelativeTo = Enum.ActuatorRelativeTo.World
	newLinear.MaxForce = math.huge
	newLinear.VectorVelocity = Vector3.zero
	newLinear.Parent = newRoot
	local newAlign = Instance.new("AlignOrientation")
	newAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment
	newAlign.Attachment0 = attachment
	newAlign.RigidityEnabled = false
	newAlign.Responsiveness = 45
	newAlign.MaxTorque = math.huge
	newAlign.MaxAngularVelocity = math.huge
	newAlign.CFrame = newRoot.CFrame.Rotation
	newAlign.Parent = newRoot
	linear = newLinear
	align = newAlign
	heading = newRoot.CFrame.LookVector
	SwimController.velocity = Vector3.zero
	SwimController.dashCharge = 1
	dashUntil = 0
	roll, rollVelocity = 0, 0
	SwimController.spawned:fire(newCharacter)
end

local function step(dt: number)
	clock += dt
	local currentRoot = root
	if currentRoot == nil or currentRoot.Parent == nil or linear == nil or align == nil then
		return
	end
	local length = SwimController.length()
	local upgrades = if ClientState.current then ClientState.current.upgrades else nil
	local top = Size.topSpeed(length) * Perks.speed(upgrades)
	local camera = workspace.CurrentCamera.CFrame

	-- Where the player wants to go, relative to the camera
	local move = Input.moveVector()
	local wish = camera.LookVector * -move.Z
		+ camera.RightVector * move.X
		+ Vector3.yAxis * Input.vertical() * swim.verticalShare
	local intent = math.min(wish.Magnitude, 1)

	-- The Dash: a burst that recharges (Deep Gills makes it recharge faster)
	local boosting = clock < dashUntil
	if not boosting then
		SwimController.dashCharge =
			math.min(1, SwimController.dashCharge + dt * Perks.boost(upgrades) / swim.dashRecharge)
	end
	SwimController.boosting = boosting

	local velocity = SwimController.velocity
	if dashStarted then
		-- The tail flick: jump straight to Dash speed, the way the player is steering
		dashStarted = false
		local direction = if intent > 0.05 then limitPitch(wish.Unit) else heading
		velocity = direction * top * swim.boostMultiplier
	end
	local speed = velocity.Magnitude
	local lunging = clock < lungeUntil
	if lunging then
		-- A bite lunge: a straight dart along the heading
		velocity = heading * math.max(speed, top * swim.lungeSpeed)
	elseif intent > 0.05 then
		local want = limitPitch(wish.Unit)
		local current = if speed > top * 0.12 then velocity.Unit else heading
		-- From (nearly) still, a fish can pivot quickly; at speed it carves
		local turnScale = if speed < top * 0.25 then 2.6 else (if boosting then 0.75 else 1)
		local direction = rotateToward(current, want, Size.turnRate(length) * turnScale * dt)
		local targetSpeed = top * intent * (if boosting then swim.boostMultiplier else 1)
		local newSpeed = speed + (targetSpeed - speed) * Spring.alpha(swim.accel, dt)
		velocity = direction * newSpeed
	elseif boosting then
		velocity = heading * math.max(speed, top * swim.boostMultiplier * 0.8)
	else
		velocity *= math.exp(-swim.drag * dt)
	end

	-- The surface is the ceiling, and the map has edges
	local position = currentRoot.Position
	local ceiling = World.surfaceY - length * 0.3 - 1
	if position.Y > ceiling and velocity.Y > 0 then
		velocity = Vector3.new(velocity.X, 0, velocity.Z)
	end
	local flat = Vector3.new(position.X, 0, position.Z)
	local edge = World.boundsRadius - length - 4
	if flat.Magnitude > edge then
		local out = flat.Unit
		local outward = velocity:Dot(out)
		if outward > 0 then
			velocity -= out * outward
		end
	end
	SwimController.velocity = velocity

	-- Hover with a gentle bob when idle
	local applied = velocity
	if velocity.Magnitude < 1 then
		applied += Vector3.new(0, math.sin(clock * 1.7) * swim.idleBob, 0)
	end
	linear.VectorVelocity = applied

	-- Facing: along the velocity when moving; level out slowly when idle
	local previous = heading
	if velocity.Magnitude > top * 0.08 then
		heading = limitPitch(velocity.Unit)
	else
		local level = Vector3.new(heading.X, heading.Y * (1 - Spring.alpha(1.5, dt)), heading.Z)
		if level.Magnitude > 1e-3 then
			heading = level.Unit
		end
	end
	-- Bank into turns, from how fast the heading swings left or right
	local flatBefore = Vector3.new(previous.X, 0, previous.Z)
	local flatAfter = Vector3.new(heading.X, 0, heading.Z)
	local yawRate = 0
	if flatBefore.Magnitude > 1e-3 and flatAfter.Magnitude > 1e-3 and dt > 0 then
		local cross = flatBefore.Unit:Cross(flatAfter.Unit).Y
		yawRate = math.asin(math.clamp(cross, -1, 1)) / dt
	end
	local targetRoll = math.clamp(yawRate * swim.rollFromTurn, -swim.maxRoll, swim.maxRoll)
	roll, rollVelocity = Spring.number(roll, rollVelocity, targetRoll, 7, dt)
	align.CFrame = CFrame.lookAt(Vector3.zero, heading) * CFrame.Angles(0, 0, roll)
end

function SwimController.start()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterRemoving:Connect(function(old)
		if old == character then
			character = nil
			root = nil
			linear = nil
			align = nil
		end
	end)
	RunService.PreSimulation:Connect(step)
	Input.ability:connect(SwimController.dash)

	-- Server moves (none in the prototype yet, but the remote exists)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local teleport = remotes:WaitForChild("Teleport") :: RemoteEvent
	teleport.OnClientEvent:Connect(function(cframe: CFrame)
		local currentRoot = root
		if currentRoot then
			currentRoot.CFrame = cframe
			currentRoot.AssemblyLinearVelocity = Vector3.zero
			SwimController.velocity = Vector3.zero
			heading = cframe.LookVector
		end
	end)
end

return SwimController
