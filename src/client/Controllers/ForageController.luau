--!strict
-- Starfish, shrimp, medkelp and crabs on this client: draws every spot (shrimp hop
-- about a little near you; starfish lie still), eats them the moment they're in reach
-- of the mouth (sucked in), and tells the server in small batches. If the server
-- doesn't confirm an eat within a moment, the food comes back.
--
-- Crabs (Config/Forage kinds with `crab`; owner, 2026-10-19: "Crabs should be edible
-- too") are built only near the camera (their kind's `range`, at most MAX_CRABS, a few
-- a frame) as AmbientBody: the imported `AmbientModels.Crab`, tinted or painted for
-- its kind and carrying its extras, or the part-built crab (Shared/AmbientRigs). Each
-- scuttles sideways about its spot on the shared clock (Shared/Crabs), legs stepping
-- and claws up as it dashes, picking at the floor between; its legs move within its
-- kind's `animate` range (every other frame to twice that) and its body everywhere it's
-- drawn. A crab the fish can't swallow isn't eaten (Size.canSwallow, as the server
-- checks), and squares up to it, claws raised and snapping, when it comes close.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AmbientRigs = require(ReplicatedStorage.Shared.AmbientRigs)
local Config = require(ReplicatedStorage.Shared.Config)
local Crabs = require(ReplicatedStorage.Shared.Crabs)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Sfx = require(script.Parent.Parent.Sfx)
local PropParts = require(ReplicatedStorage.Shared.PropParts)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local AmbientBody = require(script.Parent.Parent.AmbientBody)
local ClientState = require(script.Parent.Parent.ClientState)
local SwimController = require(script.Parent.SwimController)

local Forage = Config.Forage
type ForageDef = typeof(Forage.list[1])

local ForageController = {
	-- (mass, position) — we ate one (the HUD pops a number)
	ate = Signal.new(),
}

local HOP_DISTANCE = 140 -- shrimp further away than this hold still
local SUCK_SECONDS = 0.12
local CONFIRM_SECONDS = 1.5
local SEND_INTERVAL = 0.06
local MAX_CRABS = 40 -- crab bodies built at once (the nearest)
local CRAB_BUILDS = 2 -- crab bodies built a frame at most
local CRAB_FADE = 0.2 -- the last share of its range a crab fades over
local ALARM_NEAR = 2.2 -- × its size (plus 4 studs): a fish it can't be eaten by this close alarms it

type Crab = {
	def: ForageDef,
	up: Vector3, -- its floor's normal
	body: AmbientBody.Body?,
	motion: AmbientRigs.Motion,
	alarm: number,
	middle: Vector3, -- where it's drawn now (its middle)
	frame: CFrame,
	away: number,
}

type Food = {
	index: number,
	kind: string,
	position: Vector3,
	parts: { BasePart },
	offsets: { CFrame }, -- each part relative to the food's frame
	sizes: { Vector3 },
	yaw: number,
	hidden: boolean,
	backAt: number,
	pendingUntil: number,
	suckFrom: Vector3?,
	suckStart: number,
	pulled: boolean, -- drawn toward a mouth right now (suction)
	crab: Crab?,
}

local foods: { Food } = {}
local crabFoods: { Food } = {}
local crabFolder: Folder? = nil
local crabsBuilt = 0
local frameCount = 0
local crabTime = 0 -- seconds stepCrabs took over the last 60 frames (a readout)
local batch: { number } = {}
local lastSend = 0
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local function ellipsoid(parent: Instance, color: Color3, size: Vector3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	part.Size = size
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.Parent = parent
	return part
end

-- A starfish: the imported model, or five arms round a middle, lying flat.
local function starfish(parent: Instance, def: ForageDef, rng: Random): ({ BasePart }, { CFrame })
	local scale = rng:NextNumber(0.85, 1.25)
	local prop = PropParts.make("Starfish", Vector3.new(1.9, 0.6, 1.9) * scale, parent)
	if prop then
		return prop.parts, prop.offsets
	end
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local middle = ellipsoid(parent, def.accent, Vector3.new(0.7, 0.22, 0.7) * scale)
	table.insert(parts, middle)
	table.insert(offsets, CFrame.new())
	for arm = 0, 4 do
		local part = ellipsoid(parent, def.color, Vector3.new(0.34, 0.16, 1.1) * scale)
		table.insert(parts, part)
		table.insert(offsets, CFrame.Angles(0, arm * math.rad(72), 0) * CFrame.new(0, 0, -0.5 * scale))
	end
	return parts, offsets
end

-- Medkelp: the imported model, or three glowing fronds from a little holdfast.
local function medkelp(parent: Instance, def: ForageDef, rng: Random): ({ BasePart }, { CFrame })
	local scale = rng:NextNumber(0.9, 1.3)
	local prop = PropParts.make("Medkelp", Vector3.new(2.2, 3.2, 2.2) * scale, parent)
	if prop then
		return prop.parts, prop.offsets
	end
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local holdfast = ellipsoid(parent, Color3.fromRGB(70, 90, 70), Vector3.new(1.1, 0.4, 1.1) * scale)
	table.insert(parts, holdfast)
	table.insert(offsets, CFrame.new())
	for blade = 0, 2 do
		local frond = ellipsoid(parent, def.color, Vector3.new(0.35, 2.6, 0.9) * scale)
		frond.Material = Enum.Material.Neon
		frond.Color = def.accent
		table.insert(parts, frond)
		table.insert(
			offsets,
			CFrame.Angles(0, blade * math.rad(120), 0)
				* CFrame.new(0.3 * scale, 1.3 * scale, 0)
				* CFrame.Angles(0, 0, math.rad(-18))
		)
	end
	local glow = Instance.new("PointLight")
	glow.Color = def.accent
	glow.Range = 10
	glow.Brightness = 0.8
	glow.Parent = holdfast
	return parts, offsets
end

-- A shrimp: the imported model, or a curled body and a tail fan.
local function shrimp(parent: Instance, def: ForageDef, rng: Random): ({ BasePart }, { CFrame })
	local scale = rng:NextNumber(0.85, 1.2)
	local prop = PropParts.make("Shrimp", Vector3.new(0.9, 0.7, 1.5) * scale, parent)
	if prop then
		return prop.parts, prop.offsets
	end
	local body = ellipsoid(parent, def.color, Vector3.new(0.32, 0.36, 0.95) * scale)
	local tail = ellipsoid(parent, def.accent, Vector3.new(0.42, 0.12, 0.32) * scale)
	return { body, tail }, {
		CFrame.Angles(math.rad(-12), 0, 0),
		CFrame.new(0, 0.12 * scale, 0.5 * scale) * CFrame.Angles(math.rad(25), 0, 0),
	}
end

-- Where a shrimp hops to on its `k`th hop (each hop goes a different way).
local function hopPoint(food: Food, k: number): Vector3
	local angle = (k * 2.39996 + food.index) % (2 * math.pi)
	return food.position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * Forage.HOP * 0.55
end

local function frameOf(food: Food, now: number, near: boolean): CFrame
	if food.kind ~= "Shrimp" or not near then
		return CFrame.new(food.position) * CFrame.Angles(0, food.yaw, 0)
	end
	-- A short hop every couple of seconds, then a rest
	local cycle = 2.4 + (food.index % 5) * 0.3
	local time = now + food.index * 0.37
	local k = math.floor(time / cycle)
	local along = math.clamp((time % cycle) / 0.45, 0, 1)
	local from, to = hopPoint(food, k - 1), hopPoint(food, k)
	local at = from:Lerp(to, along) + Vector3.new(0, math.sin(along * math.pi) * 0.5, 0)
	local direction = to - from
	if direction.Magnitude < 1e-3 then
		return CFrame.new(at)
	end
	return CFrame.lookAt(at, at + direction)
end

local function place(food: Food, frame: CFrame, shrink: number)
	for i, part in food.parts do
		table.insert(moveParts, part)
		table.insert(moveFrames, frame * food.offsets[i])
		if shrink ~= 1 then
			part.Size = food.sizes[i] * shrink
		end
	end
end

local function setHidden(food: Food, hidden: boolean)
	if food.hidden == hidden then
		return
	end
	food.hidden = hidden
	local crab = food.crab
	if crab then
		-- (shown again by stepCrabs, which fades it by distance)
		local body = crab.body
		if body and hidden then
			AmbientBody.fade(body, 1)
		end
		return
	end
	-- Back on its spot (it was last drawn where a mouth sucked it in)
	local home = frameOf(food, 0, false)
	for i, part in food.parts do
		part.Transparency = if hidden then 1 else 0
		if not hidden then
			part.Size = food.sizes[i]
			part.CFrame = home * food.offsets[i]
		end
	end
end

local function build(positions: { Vector3 }, kinds: { string }, ups: { [string]: any })
	local folder = Instance.new("Folder")
	folder.Name = "Forage"
	local rng = Random.new(7)
	local crabParent = Instance.new("Folder")
	crabParent.Name = "Crabs"
	crabParent.Parent = folder
	crabFolder = crabParent
	for index, position in positions do
		local kind = kinds[index]
		local def = Forage.byId[kind]
		if def == nil then
			continue
		end
		if def.crab then
			-- A crab: its body is built only while it's near (stepCrabs)
			local up = ups[tostring(index)]
			local food: Food = {
				index = index,
				kind = kind,
				position = position,
				parts = {},
				offsets = {},
				sizes = {},
				yaw = 0,
				hidden = false,
				backAt = 0,
				pendingUntil = 0,
				suckFrom = nil,
				suckStart = 0,
				pulled = false,
				crab = {
					def = def,
					up = if typeof(up) == "Vector3" and up.Y > 0.3 then up.Unit else Vector3.yAxis,
					body = nil,
					motion = {
						t = 0,
						phase = (index * 0.618) % 1 * 2 * math.pi,
						period = 1,
						bank = 0,
						turn = 0,
						rest = 0,
						settled = -1,
						moving = false,
						alarm = 0,
					},
					alarm = 0,
					middle = position,
					frame = CFrame.new(position),
					away = math.huge,
				},
			}
			foods[index] = food
			table.insert(crabFoods, food)
			continue
		end
		local parts, offsets
		if kind == "Starfish" then
			parts, offsets = starfish(folder, def, rng)
		elseif kind == "Medkelp" then
			parts, offsets = medkelp(folder, def, rng)
		else
			parts, offsets = shrimp(folder, def, rng)
		end
		local sizes: { Vector3 } = {}
		for i, part in parts do
			sizes[i] = part.Size
		end
		local food: Food = {
			index = index,
			kind = kind,
			position = position,
			parts = parts,
			offsets = offsets,
			sizes = sizes,
			yaw = rng:NextNumber(0, 2 * math.pi),
			hidden = false,
			backAt = 0,
			pendingUntil = 0,
			suckFrom = nil,
			suckStart = 0,
			pulled = false,
		}
		foods[index] = food
		local frame = frameOf(food, 0, false)
		for i, part in parts do
			part.CFrame = frame * offsets[i]
		end
	end
	folder.Parent = workspace
end

-- A crab's feet this moment: on its floor's plane at its scuttle's offset, facing the
-- way it faces, upright along the floor; and whether it's dashing
local function crabFeet(food: Food, crab: Crab, now: number): (CFrame, boolean)
	local def = crab.def
	local dx, dz, yaw, moving = Crabs.at(food.index, def.scuttle or 2, def.speed or 2.5, now)
	local up = crab.up
	local base = food.position
	local y = base.Y - (up.X * dx + up.Z * dz) / up.Y
	local look = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	look = (look - up * look:Dot(up)).Unit
	return CFrame.fromMatrix(Vector3.new(base.X + dx, y, base.Z + dz), look:Cross(up), up), moving
end

local function dropCrab(crab: Crab)
	local body = crab.body
	if body then
		AmbientBody.destroy(body)
		crab.body = nil
		crabsBuilt -= 1
	end
end

-- The crabs near the camera: built and let go by distance, scuttling, squaring up to
-- a fish too small to eat them, sucked into a mouth that can
local function stepCrabs(
	now: number,
	camera: Vector3,
	mouth: Vector3?,
	reach: number,
	pullRange: number,
	length: number
)
	frameCount += 1
	local started = os.clock()
	local builds = 0
	for _, food in crabFoods do
		local crab = food.crab :: Crab
		local def = crab.def
		local look = def.crab
		if look == nil then
			continue
		end
		local size = def.size or 1
		local away = (food.position - camera).Magnitude
		crab.away = away
		local body = crab.body
		if body == nil then
			if away >= look.range or food.hidden or builds >= CRAB_BUILDS or crabsBuilt >= MAX_CRABS then
				continue
			end
			builds += 1
			crabsBuilt += 1
			body = AmbientBody.new("crab", size, look.look, {
				model = "Crab",
				tint = look.tint,
				paint = look.paint,
				extras = look.extras,
			}, crabFolder :: Folder)
			crab.body = body
			AmbientBody.fade(body :: AmbientBody.Body, 1)
		elseif away > look.range * 1.15 then
			dropCrab(crab)
			continue
		end
		local built = body :: AmbientBody.Body
		if food.hidden and food.suckFrom == nil then
			AmbientBody.fade(built, 1)
			continue
		end
		local feet, moving = crabFeet(food, crab, now)
		local middle = feet * CFrame.new(0, built.floor, 0)
		local fade = math.clamp((away - look.range * (1 - CRAB_FADE)) / (look.range * CRAB_FADE), 0, 1)
		fade = math.floor(fade * 10 + 0.5) / 10
		local suckFrom: Vector3? = food.suckFrom
		local sucking = typeof(suckFrom) == "Vector3"
		if suckFrom then
			-- Sucked in: drawn into the mouth as it fades
			local alpha = math.clamp((now - food.suckStart) / SUCK_SECONDS, 0, 1)
			local at = suckFrom:Lerp(mouth or suckFrom, alpha * alpha)
			middle = CFrame.new(at) * middle.Rotation
			fade = math.max(fade, alpha)
			if alpha >= 1 then
				food.suckFrom = nil
				setHidden(food, true)
			end
		elseif mouth then
			local swallows = Size.canSwallow(length * 1.03, size)
			local gap = (middle.Position - mouth).Magnitude - size * Forage.CRAB_RADIUS
			if swallows and gap < pullRange then
				-- Suction: drawn toward the mouth as it comes close
				local share = (1 - math.max(gap, 0) / pullRange) * Forage.PULL_SHARE
				middle = CFrame.new(middle.Position:Lerp(mouth, share)) * middle.Rotation
				gap = (middle.Position - mouth).Magnitude - size * Forage.CRAB_RADIUS
				if gap <= reach then
					food.suckFrom = middle.Position
					food.suckStart = now
					food.pendingUntil = now + CONFIRM_SECONDS
					food.backAt = math.huge
					table.insert(batch, food.index)
					ForageController.ate:fire(def.mass, middle.Position)
				end
			end
			-- Squaring up to a fish that can't eat it
			local target = if not swallows and gap < size * ALARM_NEAR + 4 then 1 else 0
			crab.alarm += (target - crab.alarm) * 0.08
		else
			crab.alarm *= 0.92
		end
		AmbientBody.fade(built, fade)
		if fade >= 1 then
			continue
		end
		-- Legs and claws: every frame close up, every other frame further, held beyond
		local animate = look.animate
		if away <= animate or (away <= animate * 2 and (frameCount + food.index) % 2 == 0) then
			local motion = crab.motion
			motion.t = now
			motion.moving = moving and not sucking
			motion.alarm = crab.alarm
			AmbientBody.pose(built, motion)
		end
		crab.middle = middle.Position
		table.insert(moveParts, built.root)
		table.insert(moveFrames, AmbientBody.frame(built, middle))
	end
	-- (a readout on Workspace.Forage.Crabs for play tests: bodies built, and what the
	-- crabs cost a frame, averaged over 60 frames)
	crabTime += os.clock() - started
	local readout = crabFolder
	if readout and frameCount % 60 == 0 then
		readout:SetAttribute("Built", crabsBuilt)
		readout:SetAttribute("CrabMs", math.floor(crabTime / 60 * 1e5) / 100)
		crabTime = 0
	end
end

-- Whether this fish carries all the Kelp Wraps it can: then it swims through medkelp
-- without eating it, so the fronds stay for other players (owner, 2026-10-20: "if a
-- player's kelp wrap slot is full then they should just swim through kelp wraps")
local function wrapsFull(): boolean
	local state = ClientState.current
	local charms = state and state.charms
	local held = if typeof(charms) == "table" then charms.KelpWrap else nil
	return typeof(held) == "number" and held >= Config.Tuning.heal.wrapMax
end

local function step()
	local now = Timing.clock()
	local full = wrapsFull()
	local camera = workspace.CurrentCamera.CFrame.Position
	local root = SwimController.root()
	local length = SwimController.length()
	local mouth = if root then root.CFrame:PointToWorldSpace(Size.mouthOffset(length)) else nil
	-- (× a Reef Shark's Blood Sense frenzy, Perks.sense, and an Angler Lure part,
	-- Perks.exotic: ForageService allows the same)
	local _, sense = Perks.sense(SwimController.character(), now)
	local suction = sense * Perks.exotic(SwimController.character()).reach
	local reach = (Size.reach(length) * Forage.REACH_SCALE + Forage.REACH_BONUS) * suction
	local pullRange = reach * Forage.PULL
	table.clear(moveParts)
	table.clear(moveFrames)
	for _, food in foods do
		if food.hidden and food.suckFrom == nil then
			if food.pendingUntil > 0 and now > food.pendingUntil then
				food.pendingUntil = 0
				food.backAt = 0
			end
			if food.pendingUntil == 0 and now >= food.backAt then
				setHidden(food, false)
			end
			continue
		end
		if food.hidden or food.crab then
			continue -- (crabs: stepCrabs)
		end
		if food.suckFrom then
			local alpha = math.clamp((now - food.suckStart) / SUCK_SECONDS, 0, 1)
			local at = (food.suckFrom :: Vector3):Lerp(mouth or food.position, alpha * alpha)
			place(food, CFrame.new(at) * CFrame.Angles(0, food.yaw, 0), 1 - alpha * 0.8)
			if alpha >= 1 then
				food.suckFrom = nil
				setHidden(food, true)
			end
			continue
		end
		local near = (food.position - camera).Magnitude < HOP_DISTANCE
		local frame = frameOf(food, now, near)
		local moved = near and food.kind == "Shrimp"
		local passBy = full and Forage.byId[food.kind].wrap == true
		if passBy and food.pulled then
			food.pulled, moved = false, true
		end
		if mouth and not passBy then
			local gap = (frame.Position - mouth).Magnitude
			if gap < pullRange then
				-- Suction: drawn toward the mouth as it comes close
				local share = (1 - gap / pullRange) * Forage.PULL_SHARE
				frame = CFrame.new(frame.Position:Lerp(mouth, share)) * frame.Rotation
				gap = (frame.Position - mouth).Magnitude
				food.pulled, moved = true, true
			elseif food.pulled then
				food.pulled, moved = false, true
			end
			if gap <= reach then
				food.suckFrom = frame.Position
				food.suckStart = now
				food.pendingUntil = now + CONFIRM_SECONDS
				food.backAt = math.huge
				food.pulled = false
				table.insert(batch, food.index)
				ForageController.ate:fire(Forage.byId[food.kind].mass, frame.Position)
				continue
			end
		end
		if moved then
			place(food, frame, 1)
		end
	end
	stepCrabs(now, camera, mouth, reach, pullRange, length)
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	if #batch > 0 and now - lastSend >= SEND_INTERVAL then
		lastSend = now
		ClientState.request("EatForage", batch)
		batch = {}
	end
end

local function onEaten(index: number, backAt: number, eaterUserId: number)
	local food = foods[index]
	if food == nil then
		return
	end
	food.backAt = backAt
	food.pendingUntil = 0
	if eaterUserId == Players.LocalPlayer.UserId then
		Sfx.play("Forage", { volume = 0.4, pitch = 0.9 + math.random() * 0.25 })
	end
	if eaterUserId ~= Players.LocalPlayer.UserId and food.suckFrom == nil then
		setHidden(food, true)
	end
end

-- The nearest starfish, shrimp or crab still lying there (a crab only if this fish
-- can swallow it), within `range` of `from`
function ForageController.nearest(from: Vector3, range: number): Vector3?
	local best: Vector3? = nil
	local bestDistance = range
	local length = SwimController.length()
	for _, food in foods do
		if food.hidden then
			continue
		end
		local crab = food.crab
		if crab and not Size.canSwallow(length * 1.03, crab.def.size or 1) then
			continue
		end
		local distance = (food.position - from).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			best = food.position
		end
	end
	return best
end

function ForageController.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local eaten = remotes:WaitForChild("ForageEaten") :: RemoteEvent
	eaten.OnClientEvent:Connect(onEaten)
	local getForage = remotes:WaitForChild("GetForage") :: RemoteFunction
	local ok, data = pcall(function()
		return getForage:InvokeServer()
	end)
	if not ok or typeof(data) ~= "table" then
		warn("[ForageController] couldn't load the forage spots")
		return
	end
	build(data.positions or {}, data.kinds or {}, if typeof(data.ups) == "table" then data.ups else {})
	for key, backAt in data.eaten or {} do
		local index = tonumber(key)
		if index and typeof(backAt) == "number" then
			onEaten(index, backAt, 0)
		end
	end
	RunService.RenderStepped:Connect(step)
end

return ForageController
