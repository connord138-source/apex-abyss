--!strict
-- The plaza's shopkeepers come alive on each client (owner, 2026-11-03: "The vendors are
-- also static, they need movement"). A keeper is one solid mesh with no bones
-- (WorldProps.Keeper<VendorId>, Plaza.keeper tags it `Keeper`), so the whole of it moves:
-- it bobs and sways as it treads water, turns to look at the nearest fish, and every so
-- often gives a little excited hop. Only near the camera, and never far from its spot,
-- so the counters and the server's copy stay put.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local REACH = 220 -- studs from the camera: past this they rest
local LOOK_REACH = 46 -- studs: a fish this close gets looked at
local LOOK_MOST = math.rad(50) -- as far as a keeper turns from its spot
local TURN_RATE = 3 -- how quickly it comes round
local BOB = 0.45 -- studs up and down
local SWAY = math.rad(5) -- rocks this far
local IDLE_YAW = math.rad(14) -- looks about this far when nobody's near
local HOP_EVERY = { 7, 15 } -- seconds between hops
local HOP_SECONDS = 0.7
local HOP_HEIGHT = 1.5

type Keeper = {
	model: Model,
	base: CFrame,
	phase: number,
	yaw: number,
	hopAt: number,
	hopStarted: number,
	random: Random,
}

local VendorController = {}

local keepers: { [Instance]: Keeper } = {}

local function add(instance: Instance)
	if not instance:IsA("Model") or keepers[instance] then
		return
	end
	local random = Random.new()
	keepers[instance] = {
		model = instance,
		base = instance:GetPivot(),
		phase = random:NextNumber() * 20,
		yaw = 0,
		hopAt = os.clock() + random:NextNumber(HOP_EVERY[1], HOP_EVERY[2]),
		hopStarted = -math.huge,
		random = random,
	}
end

local function remove(instance: Instance)
	keepers[instance] = nil
end

-- The nearest fish's place, if one's near enough to look at
local function nearestFish(at: Vector3): Vector3?
	local best: Vector3? = nil
	local bestDistance = LOOK_REACH
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local distance = (root.Position - at).Magnitude
			if distance < bestDistance then
				best, bestDistance = root.Position, distance
			end
		end
	end
	return best
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local now = os.clock()
	for _, keeper in keepers do
		local base = keeper.base
		if (base.Position - camera.CFrame.Position).Magnitude > REACH then
			continue
		end
		local t = now + keeper.phase
		-- Where it wants to look: at the nearest fish, or idly about
		local wanted = math.sin(t * 0.35) * IDLE_YAW
		local fish = nearestFish(base.Position)
		if fish then
			local local_ = base:PointToObjectSpace(fish)
			-- (the keeper's model faces its own -X once turned by GLB_FRONT: Plaza.keeper)
			wanted = math.clamp(math.atan2(local_.Z, -local_.X), -LOOK_MOST, LOOK_MOST)
		end
		keeper.yaw += (wanted - keeper.yaw) * (1 - math.exp(-dt * TURN_RATE))
		-- A hop now and then
		if now >= keeper.hopAt then
			keeper.hopStarted = now
			keeper.hopAt = now + keeper.random:NextNumber(HOP_EVERY[1], HOP_EVERY[2])
		end
		local hopped = (now - keeper.hopStarted) / HOP_SECONDS
		local hop = if hopped < 1 then math.sin(hopped * math.pi) * HOP_HEIGHT else 0
		keeper.model:PivotTo(
			base
				* CFrame.new(0, math.sin(t * 1.3) * BOB + hop, 0)
				* CFrame.Angles(0, keeper.yaw, 0)
				* CFrame.Angles(math.sin(t * 0.9) * SWAY, 0, math.cos(t * 0.7) * SWAY)
		)
	end
end

function VendorController.start()
	CollectionService:GetInstanceAddedSignal("Keeper"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("Keeper"):Connect(remove)
	for _, instance in CollectionService:GetTagged("Keeper") do
		add(instance)
	end
	RunService.RenderStepped:Connect(step)
end

return VendorController
