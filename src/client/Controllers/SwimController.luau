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
local DenSpace = require(ReplicatedStorage.Shared.DenSpace)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Spring = require(script.Parent.Parent.Spring)
local Bubbles = require(script.Parent.Parent.Bubbles)
local Sfx = require(script.Parent.Parent.Sfx)

local swim = Config.Tuning.swim
local World = Config.World

local SwimController = {
	velocity = Vector3.zero,
	boosting = false, -- mid-Dash
	slipstream = false, -- in a podmate's slipstream (faster)
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
-- What's holding the fish and where it drags it: "creature" (a boss's grab) or
-- "hook" (a fisherman's line, HookController)
local holds: { [string]: Vector3? } = {}

local function heldAt(): Vector3?
	for _, point in holds do
		return point
	end
	return nil
end

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

-- A den shaft the fish is under or in, as the point on its axis level with the
-- fish (nil when there's none). The den's level comes from its DenBase folder
-- (DenBuilder), so a shaft only counts once it's carved.
local function shaftAxis(position: Vector3): Vector3?
	local index = Layout.denAt(position)
	if index == nil then
		return nil
	end
	local world = workspace:FindFirstChild("World")
	local hub = world and world:FindFirstChild("Hub")
	local base = hub and hub:FindFirstChild(`DenBase{index}`)
	local level = if base then base:GetAttribute("Level") else nil
	if typeof(level) ~= "number" then
		return nil
	end
	local frame = DenSpace.frame(index)
	local here = DenSpace.toLocal(frame, position)
	for _, shaft in DenSpace.shafts(level) do
		local top = DenSpace.storey(shaft.from).deck + 6
		local bottom = DenSpace.storey(shaft.to).ceiling - 14
		local off = Vector2.new(here.X, here.Z - shaft.z).Magnitude
		if here.Y < top and here.Y > bottom and off < shaft.radius + 6 then
			return DenSpace.spot(frame, 0, here.Y, shaft.z).Position
		end
	end
	return nil
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

-- The species' handling multipliers (Config/Species), from the fish's attribute.
function SwimController.stats(): { speed: number, turn: number }
	local id = if character then character:GetAttribute("Species") else nil
	local species = if typeof(id) == "string" then Config.Species.byId[id] else nil
	return if species then species.stats else { speed = 1, turn = 1 }
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
	if next(holds) ~= nil then
		SwimController.struggle()
		return false
	end
	if root == nil or SwimController.dashCharge < 1 then
		return false
	end
	SwimController.dashCharge = 0
	dashUntil = clock + swim.dashSeconds
	dashStarted = true
	local length = SwimController.length()
	Sfx.play("Dash", { volume = 0.55, pitch = math.clamp(1.25 - length * 0.02, 0.7, 1.2) })
	Bubbles.burst(root.CFrame:PointToWorldSpace(Vector3.new(0, 0, length * 0.4)), length, 14)
	return true
end

-- A push from a creature (a tail sweep, a breach's shockwave): the server tells us
-- and we add it, since this client owns the fish's physics.
function SwimController.shove(velocity: Vector3)
	if root == nil then
		return
	end
	SwimController.velocity += velocity
	lungeUntil = 0
end

-- A grab: while `point` is set the fish is dragged toward it and can't swim (it
-- can only struggle). Nil lets go. PredatorController sets it from the HeldBy
-- attribute the server puts on the character.
function SwimController.hold(point: Vector3?)
	holds.creature = point
end

-- The same for another holder (`source`: "hook")
function SwimController.holdBy(source: string, point: Vector3?)
	holds[source] = point
end

function SwimController.isHeld(): boolean
	return next(holds) ~= nil
end

-- A mash (BITE or DASH while held): tells whatever holds the fish
function SwimController.struggle()
	if holds.hook then
		ClientState.request("StruggleHook")
	end
	if holds.creature then
		ClientState.request("Struggle")
	end
end

-- A bite if the cooldown allows (the jaw snaps); returns whether it did. It darts
-- forward only with something to bite in reach (`dart`): a bite into open water is
-- just the snap (owner, 2026-10-16: "right click is just a weaker dash").
function SwimController.lunge(dart: boolean?): boolean
	if root == nil or clock - lastBiteAt < swim.biteCooldown then
		return false
	end
	lastBiteAt = clock
	lungeUntil = if dart then clock + swim.lungeSeconds else 0
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

-- Whether we're in a podmate's slipstream: one ahead of us within range, inside the
-- cone of our heading, and swimming our way
local function slipstreamOf(me: BasePart): boolean
	local pod = Players.LocalPlayer:GetAttribute("Pod")
	if typeof(pod) ~= "number" or pod == 0 then
		return false
	end
	local tune = Config.Pvp.pods.slipstream
	local velocity = me.AssemblyLinearVelocity
	if velocity.Magnitude < 2 then
		return false
	end
	local heading = velocity.Unit
	for _, player in Players:GetPlayers() do
		if player == Players.LocalPlayer or player:GetAttribute("Pod") ~= pod then
			continue
		end
		local other = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if other and other:IsA("BasePart") then
			local offset = other.Position - me.Position
			local distance = offset.Magnitude
			if
				distance > 0.5
				and distance <= tune.range
				and offset.Unit:Dot(heading) >= tune.cone
				and other.AssemblyLinearVelocity:Dot(heading) > 0
			then
				return true
			end
		end
	end
	return false
end

local function step(dt: number)
	clock += dt
	local currentRoot = root
	if currentRoot == nil or currentRoot.Parent == nil or linear == nil or align == nil then
		return
	end
	local length = SwimController.length()
	local upgrades = if ClientState.current then ClientState.current.upgrades else nil
	local stats = SwimController.stats()
	local top = Size.topSpeed(length) * Perks.speed(upgrades) * stats.speed
	-- A Kelp Wrap slows you while it heals (the PvP counterplay)
	local healing = if character then character:GetAttribute("Healing") else nil
	if typeof(healing) == "number" and healing > Timing.clock() then
		top *= Config.Tuning.heal.wrapSlow
	end
	-- A podmate's slipstream: close behind one swimming the same way is faster
	-- (Config/Pvp `pods.slipstream`)
	SwimController.slipstream = slipstreamOf(currentRoot)
	if SwimController.slipstream then
		top *= Config.Pvp.pods.slipstream.speed
	end
	local camera = workspace.CurrentCamera.CFrame

	-- Where the player wants to go, relative to the camera: the keys as on PC, plus
	-- a stick's throttle straight along the aim (its steering turns the camera). A
	-- stick pushed sideways (and not pulled back) also cruises gently along the aim,
	-- so the fish carves round with the camera; with no cruise the camera orbited a
	-- fish coasting to a stop (playtest 2026-10-07, owner: cruise into the turn)
	local move = Input.moveVector()
	local throttle, steer = Input.drive()
	local ahead = math.max(throttle, 0)
	if throttle > -0.05 then
		ahead = math.max(ahead, math.abs(steer) * swim.turnCruise)
	end
	-- Level swimming: a camera tipped within `levelZone` of level swims level, and
	-- past it the climb or dive eases in, so straight up is still straight up
	local look = camera.LookVector
	local aimPitch = math.asin(math.clamp(look.Y, -1, 1))
	local over = math.max(0, math.abs(aimPitch) - swim.levelZone)
	local eased = math.sign(aimPitch) * over * (math.pi / 2) / (math.pi / 2 - swim.levelZone)
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local forward = if flatLook.Magnitude > 1e-3
		then flatLook.Unit * math.cos(eased) + Vector3.yAxis * math.sin(eased)
		else look
	local wish = forward * -move.Z
		+ camera.RightVector * move.X
		+ Vector3.yAxis * Input.vertical() * swim.verticalShare
		+ forward * ahead
	local intent = math.min(wish.Magnitude, 1)

	-- The Dash: a burst that recharges (Deep Gills makes it recharge faster)
	local boosting = clock < dashUntil
	if not boosting then
		SwimController.dashCharge =
			math.min(1, SwimController.dashCharge + dt * Perks.boost(upgrades) / swim.dashRecharge)
	end
	SwimController.boosting = boosting
	-- A stick pulled back with nothing else held: brake, then back up, still facing
	-- the way it was (a fish that spun round to face the camera looked wrong)
	local reversing = throttle < -0.05 and intent <= 0.05 and not boosting

	local velocity = SwimController.velocity
	local held = heldAt()
	if held then
		-- Dragged toward the beak: no swimming, just the pull
		local pull = held - currentRoot.Position
		velocity = if pull.Magnitude > 2 then pull.Unit * Config.Bosses.grabPull else Vector3.zero
		dashStarted = false
		lungeUntil = 0
	elseif dashStarted then
		-- The tail flick: jump straight to Dash speed, the way the player is steering
		dashStarted = false
		local direction = if intent > 0.05 then limitPitch(wish.Unit) else heading
		velocity = direction * top * swim.boostMultiplier
	end
	local speed = velocity.Magnitude
	local lunging = clock < lungeUntil
	if held then
		-- (the pull above stands)
	elseif lunging then
		-- A bite lunge: a straight dart along the heading
		velocity = heading * math.max(speed, top * swim.lungeSpeed)
	elseif reversing then
		local back = -heading * top * swim.reverseShare * -throttle
		velocity = velocity:Lerp(back, Spring.alpha(swim.brake, dt))
	elseif intent > 0.05 then
		local want = limitPitch(wish.Unit)
		local current = if speed > top * 0.12 then velocity.Unit else heading
		-- From (nearly) still, a fish can pivot quickly; at speed it carves
		local turnScale = if speed < top * 0.25 then 2.6 else (if boosting then 0.75 else swim.cruiseTurn)
		local direction = rotateToward(current, want, Size.turnRate(length) * stats.turn * turnScale * dt)
		local targetSpeed = top * intent * (if boosting then swim.boostMultiplier else 1)
		local newSpeed = speed + (targetSpeed - speed) * Spring.alpha(swim.accel, dt)
		velocity = direction * newSpeed
	elseif boosting then
		velocity = heading * math.max(speed, top * swim.boostMultiplier * 0.8)
	else
		velocity *= math.exp(-swim.drag * dt)
	end

	-- Den shafts lift: under or in a shaft and swimming mostly up or down, the fish
	-- goes straight and eases onto the shaft's axis. The pitch limit turns straight
	-- up into 80° along the heading, so a big fish under the Sanctum's mouth slid
	-- along the vault instead of rising into it (PC overnight 2026-10-14)
	if not held and not lunging and not reversing and intent > 0.05 and math.abs(wish.Unit.Y) > 0.55 then
		local axis = shaftAxis(currentRoot.Position)
		if axis then
			local toAxis = Vector3.new(axis.X - currentRoot.Position.X, 0, axis.Z - currentRoot.Position.Z)
			local pull = if toAxis.Magnitude > 0.3
				then toAxis.Unit * math.min(toAxis.Magnitude * 2.5, top * 0.6)
				else Vector3.zero
			velocity = Vector3.new(0, math.sign(wish.Y) * velocity.Magnitude, 0) + pull
		end
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
		-- And off the heading: from nearly still the fish turns from its heading, so
		-- one left pointing out of the map turned a little, was clamped back to a
		-- crawl and never came round (playtest 2026-10-07: stuck at the edge, every
		-- key dead)
		local facing = heading:Dot(out)
		if facing > 0 then
			local along = heading - out * facing
			heading = if along.Magnitude > 1e-3 then along.Unit else out:Cross(Vector3.yAxis)
		end
	end
	SwimController.velocity = velocity

	-- Hover with a gentle bob when idle
	local applied = velocity
	if velocity.Magnitude < 1 then
		applied += Vector3.new(0, math.sin(clock * 1.7) * swim.idleBob, 0)
	end
	linear.VectorVelocity = applied

	-- Facing: along the velocity when moving ahead; while backing up (or coasting
	-- backwards after it), keep facing forward and follow the aim's turn; level out
	-- slowly when idle
	local previous = heading
	if reversing then
		local aim = Vector3.new(camera.LookVector.X, heading.Y, camera.LookVector.Z)
		if aim.Magnitude > 1e-3 then
			heading = rotateToward(heading, limitPitch(aim.Unit), Size.turnRate(length) * stats.turn * dt)
		end
	elseif
		velocity.Magnitude > top * 0.08
		and (intent > 0.05 or boosting or lunging or velocity:Dot(heading) > 0)
	then
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
	-- (the ability button is routed by AbilityController: Dash, or the fish's own)

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
	local shove = remotes:WaitForChild("Shove") :: RemoteEvent
	shove.OnClientEvent:Connect(function(velocity: Vector3)
		if typeof(velocity) == "Vector3" then
			SwimController.shove(velocity)
		end
	end)
end

return SwimController
