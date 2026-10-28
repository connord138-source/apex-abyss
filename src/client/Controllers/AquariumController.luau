--!strict
-- The den's living displays (2026-10-28; the den expansion the owner approved):
--  * each aquarium tank's fish (DenWings.tanks tags its Water part `AquariumTank`
--    with the fish's Prey and Rarity) swims slowly back and forth inside it, turning
--    toward the glass at each end, its tail waving, while the camera is near;
--  * past the Observatory's window (`ObservatoryWindow`, with the way out `Out`) a
--    deep-sea diorama drifts by: a humpback and two mantas crossing the view, jellies
--    rising and sinking, and a school of little fish wheeling through, built only
--    while the camera is near the window.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AmbientBody = require(script.Parent.Parent.AmbientBody)
local AmbientRigs = require(ReplicatedStorage.Shared.AmbientRigs)
local Config = require(ReplicatedStorage.Shared.Config)
local PreyDisplay = require(ReplicatedStorage.Shared.PreyDisplay)
local SwimWave = require(ReplicatedStorage.Shared.SwimWave)

local AquariumController = {}

local TANK_RANGE = 140 -- studs from the camera a tank's fish swims
local VIEW_RANGE = 220 -- studs from the camera the window's diorama is built
local TAU = 2 * math.pi

type TankFish = {
	water: BasePart,
	display: PreyDisplay.Display,
	key: string,
	phase: number,
	speed: number,
}

local tanks: { [BasePart]: TankFish } = {}
local folder: Folder? = nil

local function home(): Folder
	if folder and folder.Parent then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = "DenLife"
	made.Parent = workspace
	folder = made
	return made
end

local function seedOf(text: string): number
	local n = 0
	for i = 1, #text do
		n = (n * 31 + string.byte(text, i)) % 1000003
	end
	return n
end

-- A tank's fish, built once its tank is near and kept in step with what's in it
local function tankFish(water: BasePart, near: boolean): TankFish?
	local prey = water:GetAttribute("Prey")
	local rarity = water:GetAttribute("Rarity")
	local have = tanks[water]
	if not near or typeof(prey) ~= "string" or typeof(rarity) ~= "string" then
		if have then
			have.display.model:Destroy()
			tanks[water] = nil
		end
		return nil
	end
	local key = `{prey}|{rarity}`
	if have and have.key == key then
		return have
	end
	if have then
		have.display.model:Destroy()
	end
	local def = Config.Prey.byId[prey]
	local slim = if def then def.slim else 0.3
	-- As long as fits the tank's width and height comfortably
	local length = math.min(water.Size.X * 0.36, water.Size.Y * 0.7 / math.max(slim, 0.2), 4.5)
	local display = PreyDisplay.build(prey, rarity, length)
	display.model.Parent = home()
	local seed = seedOf(water:GetFullName())
	local made: TankFish = {
		water = water,
		display = display,
		key = key,
		phase = (seed % 1000) / 1000 * TAU,
		speed = 0.32 + (seed % 7) * 0.025,
	}
	tanks[water] = made
	return made
end

local function swimTanks(now: number, camera: Vector3)
	for _, water in CollectionService:GetTagged("AquariumTank") do
		if not water:IsA("BasePart") or not water:IsDescendantOf(workspace) then
			continue
		end
		local near = (water.Position - camera).Magnitude < TANK_RANGE
		local fish = tankFish(water, near)
		if fish == nil then
			continue
		end
		local display = fish.display
		local size = water.Size
		local reach = math.max(size.X / 2 - display.length * 0.55 - 0.4, 0.2)
		local t = now * fish.speed + fish.phase
		local along = math.sin(t)
		local heading = math.cos(t) -- +: swimming toward +X
		-- At each end it turns through facing the glass (the tank's -Z)
		local turn = (1 - math.clamp((heading + 0.3) / 0.6, 0, 1)) * math.pi
		local look = Vector3.new(math.cos(turn), 0, -math.sin(turn))
		local bob = math.sin(t * 2.3 + fish.phase) * size.Y * 0.08
		local depth = -size.Z * 0.12 + math.sin(t * 0.7) * size.Z * 0.08
		local at = Vector3.new(along * reach, bob, depth)
		local frame = water.CFrame * CFrame.lookAt(at, at + look)
		PreyDisplay.place(display, frame)
		if #display.spine > 0 then
			SwimWave.applyBones(display.bones, display.spine, now * 6 + fish.phase, 0.22, 0)
		end
	end
	for water, fish in tanks do
		if not water:IsDescendantOf(workspace) then
			fish.display.model:Destroy()
			tanks[water] = nil
		end
	end
end

-- The Observatory's view: one per window near the camera
type Drifter = {
	part: BasePart?,
	body: AmbientBody.Body?,
	display: PreyDisplay.Display?,
	motion: AmbientRigs.Motion?,
	path: (t: number) -> CFrame,
	parts: { BasePart },
}
type View = { window: BasePart, model: Model, drifters: { Drifter } }
local views: { [BasePart]: View } = {}

local JELLY = {
	Color3.fromRGB(150, 120, 255),
	Color3.fromRGB(110, 170, 255),
	Color3.fromRGB(90, 220, 255),
}

local function jelly(parent: Instance, size: number, color: Color3): { BasePart }
	local parts: { BasePart } = {}
	local bell = Instance.new("Part")
	bell.Name = "Bell"
	bell.Anchored = true
	bell.CanCollide = false
	bell.CanQuery = false
	bell.CanTouch = false
	bell.CastShadow = false
	bell.Shape = Enum.PartType.Ball
	bell.Size = Vector3.new(size, size * 0.7, size)
	bell.Color = color
	bell.Material = Enum.Material.Neon
	bell.Transparency = 0.45
	bell.Parent = parent
	table.insert(parts, bell)
	for i = 1, 5 do
		local a = i / 5 * TAU
		local strand = Instance.new("Part")
		strand.Name = "Tentacle"
		strand.Anchored = true
		strand.CanCollide = false
		strand.CanQuery = false
		strand.CanTouch = false
		strand.CastShadow = false
		strand.Size = Vector3.new(0.12, size * 1.6, 0.12)
		strand.Color = color
		strand.Material = Enum.Material.Neon
		strand.Transparency = 0.35
		strand:SetAttribute(
			"Offset",
			Vector3.new(math.cos(a) * size * 0.3, -size * 0.9, math.sin(a) * size * 0.3)
		)
		strand.Parent = parent
		table.insert(parts, strand)
	end
	return parts
end

local function buildView(window: BasePart): View?
	local out = window:GetAttribute("Out")
	if typeof(out) ~= "Vector3" then
		return nil
	end
	local outward = out.Unit
	local up = Vector3.yAxis
	local across = outward:Cross(up).Unit
	local middle = window.Position
	local model = Instance.new("Model")
	model.Name = "ObservatoryView"
	model.Parent = home()
	local drifters: { Drifter } = {}
	local rng = Random.new(seedOf(window:GetFullName()))
	-- A frame `ahead` studs out, `side` across and `rise` up, heading `dir`
	local function spot(ahead: number, side: number, rise: number, dir: Vector3): CFrame
		local at = middle + outward * ahead + across * side + up * rise
		return CFrame.lookAt(at, at + dir)
	end
	-- The humpback crossing slowly far out, and two mantas nearer, the other way
	local giants = Config.Ambient.giants
	local whale =
		AmbientBody.new(giants.whale.rig, 62, giants.whale.look, { model = giants.whale.model }, model)
	table.insert(drifters, {
		body = whale,
		motion = { t = 0, phase = 0, period = 7.5, bank = 0, turn = 0, rest = 0, settled = -1, moving = true },
		path = function(t: number): CFrame
			local u = (t / 70) % 1
			return spot(130, (u - 0.5) * 420, -6 + math.sin(t * 0.2) * 5, across)
		end,
		parts = whale.parts,
	})
	for k = 1, 2 do
		local manta =
			AmbientBody.new(giants.manta.rig, 16, giants.manta.look, { model = giants.manta.model }, model)
		local offset = k * 0.47
		table.insert(drifters, {
			body = manta,
			motion = {
				t = 0,
				phase = k,
				period = 5.2,
				bank = 0,
				turn = 0,
				rest = 0,
				settled = -1,
				moving = true,
			},
			path = function(t: number): CFrame
				local u = (t / 34 + offset) % 1
				return spot(55 + k * 18, (0.5 - u) * 260, 14 - k * 16 + math.sin(t * 0.4 + k) * 4, -across)
			end,
			parts = manta.parts,
		})
	end
	-- Jellies rising and sinking at every depth
	for i = 1, 9 do
		local holder = Instance.new("Model")
		holder.Name = "Jelly"
		holder.Parent = model
		local size = rng:NextNumber(1.6, 3.4)
		local parts = jelly(holder, size, JELLY[(i % #JELLY) + 1])
		local ahead = rng:NextNumber(22, 110)
		local side = rng:NextNumber(-60, 60)
		local rise = rng:NextNumber(-30, 34)
		local phase = rng:NextNumber(0, TAU)
		table.insert(drifters, {
			parts = parts,
			path = function(t: number): CFrame
				return spot(
					ahead,
					side + math.sin(t * 0.13 + phase) * 6,
					rise + math.sin(t * 0.35 + phase) * 7,
					outward
				)
			end,
		})
	end
	-- A school of little fish wheeling past
	local preyId = if rng:NextNumber() < 0.5 then "Sardine" else "Lanternfish"
	for i = 1, 14 do
		local display = PreyDisplay.build(preyId, "Normal", 1.6)
		display.model.Parent = model
		local lane = rng:NextNumber(-8, 8)
		local lift = rng:NextNumber(-6, 6)
		local lag = i * 0.022
		table.insert(drifters, {
			display = display,
			parts = display.parts,
			path = function(t: number): CFrame
				local a = (t / 26 - lag) * TAU
				local at = middle
					+ outward * (45 + math.cos(a) * 18 + lane)
					+ across * (math.sin(a) * 70)
					+ up * (8 + lift + math.sin(a * 2) * 6)
				local dir = outward * -math.sin(a) * 18 + across * math.cos(a) * 70
				return CFrame.lookAt(at, at + dir)
			end,
		})
	end
	return { window = window, model = model, drifters = drifters }
end

local function driftViews(now: number, camera: Vector3)
	for _, window in CollectionService:GetTagged("ObservatoryWindow") do
		if not window:IsA("BasePart") or not window:IsDescendantOf(workspace) then
			continue
		end
		local near = (window.Position - camera).Magnitude < VIEW_RANGE
		local have: View? = views[window]
		if near and have == nil then
			have = buildView(window)
			if have then
				views[window] = have
			end
		elseif not near and have then
			have.model:Destroy()
			views[window] = nil
			have = nil
		end
		local view = have
		if view == nil then
			continue
		end
		for _, drifter in view.drifters do
			local frame = drifter.path(now)
			local body = drifter.body
			if body and drifter.motion then
				drifter.motion.t = now
				AmbientBody.pose(body, drifter.motion)
				body.root.CFrame = AmbientBody.frame(body, frame)
			elseif drifter.display then
				PreyDisplay.place(drifter.display, frame)
			else
				local bell = drifter.parts[1]
				bell.CFrame = frame
				for i = 2, #drifter.parts do
					local strand = drifter.parts[i]
					local offset = strand:GetAttribute("Offset")
					if typeof(offset) == "Vector3" then
						local sway = math.sin(now * 1.7 + i) * 0.3
						strand.CFrame = CFrame.new(frame.Position + offset)
							* CFrame.Angles(sway, 0, sway * 0.6)
					end
				end
			end
		end
	end
	for window, view in views do
		if not window:IsDescendantOf(workspace) then
			view.model:Destroy()
			views[window] = nil
		end
	end
end

function AquariumController.start()
	RunService.Heartbeat:Connect(function()
		local camera = workspace.CurrentCamera
		if camera == nil then
			return
		end
		local now = workspace:GetServerTimeNow()
		local at = camera.CFrame.Position
		swimTanks(now, at)
		driftViews(now, at)
	end)
end

return AquariumController
