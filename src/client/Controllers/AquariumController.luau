--!strict
-- The den's living displays (2026-10-28; the den expansion the owner approved):
--  * each aquarium tank's fish (DenWings.tanks tags its Water part `AquariumTank`
--    with the fish's Prey and Rarity) swims slowly back and forth inside it, turning
--    toward the glass at each end, its tail waving, while the camera is near;
--  * past the Observatory's window (`ObservatoryWindow`, with the way out `Out`) a
--    deep-sea diorama drifts by: a humpback and two mantas crossing the view, jellies
--    rising and sinking, and a school of little fish wheeling through, built only
--    while the camera is near the window.
--
-- Cost (PC 2026-11-02, DE14: 43-45 ms/s in a full den, a PivotTo and a CFrame write a
-- fish every frame): everything moves in one BulkMoveTo a frame; a tank's fish only
-- while its tank is on screen, the nearer the more often, its tail only near; the
-- Observatory's view only while its window is on screen from inside the room; the
-- tagged lists are kept by signals, not GetTagged.
-- PC 2026-11-03 (6.9 / 23.5 / 12.1 ms/s in the Nook, at the window, in the Aquarium
-- Hall; moving parts is most of it): a tank off screen costs a distance and
-- a dot, a built tank's stock is read every STOCK_EVERY seconds, a fish is placed in
-- its tank the frame it's built (one built off screen sat under the hub), and the
-- tank fish (~1-2 studs/s) move every frame only within TANK_CLOSE, every other to
-- TANK_NEAR, every fourth to TANK_FAR and every eighth past it; past the window only
-- what the line of sight through the glass reaches moves, staggered: the school every
-- other frame, the mantas every third, the far humpback and the jellies (each one
-- moved part, the rest welded on) every fourth.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AmbientBody = require(script.Parent.Parent.AmbientBody)
local AmbientRigs = require(ReplicatedStorage.Shared.AmbientRigs)
local Config = require(ReplicatedStorage.Shared.Config)
local PreyDisplay = require(ReplicatedStorage.Shared.PreyDisplay)
local SwimWave = require(ReplicatedStorage.Shared.SwimWave)

local AquariumController = {}

local TANK_RANGE = 140 -- studs from the camera a tank's fish is built
local TANK_CLOSE = 15 -- a tank's fish moves every frame within this
local TANK_NEAR = 35 -- every other frame within this (its tail waves within it)
local TANK_FAR = 80 -- every fourth frame within this, every eighth past it
local STOCK_EVERY = 0.5 -- seconds between reads of a built tank's stock
local VIEW_RANGE = 220 -- studs from the camera the window's diorama is built
-- On screen: within this of the camera's look (cos of ~66°: the screen's half width
-- at 16:9 and a little more, so nothing is caught still at the edge)
local ON_SCREEN = 0.4
local TAU = 2 * math.pi

local frameCount = 0
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

-- The tagged parts, kept as they come and go
local function tracked(tag: string): { [BasePart]: boolean }
	local set: { [BasePart]: boolean } = {}
	local function add(item: Instance)
		if item:IsA("BasePart") then
			set[item] = true
		end
	end
	for _, item in CollectionService:GetTagged(tag) do
		add(item)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(item: Instance)
		if item:IsA("BasePart") then
			set[item] = nil
		end
	end)
	return set
end

local tankParts: { [BasePart]: boolean } = {}
local windowParts: { [BasePart]: boolean } = {}

type TankFish = {
	water: BasePart,
	display: PreyDisplay.Display,
	prey: string,
	rarity: string,
	phase: number,
	speed: number,
	slot: number, -- which frame of 2, 4 or 8 it moves on
	posed: boolean, -- placed in its tank yet
	checked: number, -- when its tank's stock was last read
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

local function onScreen(
	look: Vector3,
	camera: Vector3,
	at: Vector3,
	distance: number,
	radius: number
): boolean
	if distance < radius then
		return true
	end
	return look:Dot((at - camera) / distance) > ON_SCREEN - radius / distance
end

-- A tank's fish, built once its tank is near and kept in step with what's in it
local function tankFish(water: BasePart, near: boolean, now: number): TankFish?
	local have = tanks[water]
	if near and have and now - have.checked < STOCK_EVERY then
		return have
	end
	local prey = water:GetAttribute("Prey")
	local rarity = water:GetAttribute("Rarity")
	if not near or typeof(prey) ~= "string" or typeof(rarity) ~= "string" then
		if have then
			have.display.model:Destroy()
			tanks[water] = nil
		end
		return nil
	end
	if have and have.prey == prey and have.rarity == rarity then
		have.checked = now
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
		prey = prey,
		rarity = rarity,
		phase = (seed % 1000) / 1000 * TAU,
		speed = 0.32 + (seed % 7) * 0.025,
		slot = seed % 8,
		posed = false,
		checked = now,
	}
	tanks[water] = made
	return made
end

local function swimTanks(now: number, camera: Vector3, look: Vector3)
	-- (a tank leaving the place drops out of tankParts by its tag's signal)
	for water in tankParts do
		local middle = water.Position
		local distance = (middle - camera).Magnitude
		if distance >= TANK_RANGE then
			if tanks[water] then
				tankFish(water, false, now)
			end
			continue
		end
		local size = water.Size
		if not onScreen(look, camera, middle, distance, size.X) then
			continue
		end
		local every = if distance < TANK_CLOSE
			then 1
			elseif distance < TANK_NEAR then 2
			elseif distance < TANK_FAR then 4
			else 8
		local have = tanks[water]
		if have and have.posed and every > 1 and (frameCount + have.slot) % every ~= 0 then
			continue
		end
		-- (built, or rebuilt for a new stock, only on screen, and placed at once)
		local fish = tankFish(water, true, now)
		if fish == nil then
			continue
		end
		fish.posed = true
		local display = fish.display
		local reach = math.max(size.X / 2 - display.length * 0.55 - 0.4, 0.2)
		local t = now * fish.speed + fish.phase
		local along = math.sin(t)
		local heading = math.cos(t) -- +: swimming toward +X
		-- At each end it turns through facing the glass (the tank's -Z)
		local turn = (1 - math.clamp((heading + 0.3) / 0.6, 0, 1)) * math.pi
		local swimLook = Vector3.new(math.cos(turn), 0, -math.sin(turn))
		local bob = math.sin(t * 2.3 + fish.phase) * size.Y * 0.08
		local depth = -size.Z * 0.12 + math.sin(t * 0.7) * size.Z * 0.08
		local at = Vector3.new(along * reach, bob, depth)
		PreyDisplay.pose(display, water.CFrame * CFrame.lookAt(at, at + swimLook), moveParts, moveFrames)
		if distance < TANK_NEAR and #display.spine > 0 then
			SwimWave.applyBones(display.bones, display.spine, now * 6 + fish.phase, 0.22, 0)
		end
	end
	for water, fish in tanks do
		if tankParts[water] == nil then
			fish.display.model:Destroy()
			tanks[water] = nil
		end
	end
end

-- The Observatory's view: one per window near the camera
type Drifter = {
	body: AmbientBody.Body?,
	display: PreyDisplay.Display?,
	motion: AmbientRigs.Motion?,
	path: (t: number) -> CFrame,
	parts: { BasePart },
	jelly: boolean,
	phase: number, -- (a jelly's sway)
	reach: number, -- studs it reaches round its middle (seen through the glass)
	every: number, -- moved every this many frames
	slot: number, -- which of them
	placed: Vector3?, -- where it was last moved to (nil: not yet)
}
type View = { window: BasePart, model: Model, drifters: { Drifter } }
local views: { [BasePart]: View } = {}

local JELLY = {
	Color3.fromRGB(150, 120, 255),
	Color3.fromRGB(110, 170, 255),
	Color3.fromRGB(90, 220, 255),
}
local JELLY_TRAIL = 2.6 -- a tentacle's longest, in bell widths
-- The sand outside lies this far under the window's middle (DenCarve WINDOW_Y +
-- SEA_FLOOR): a jelly's tentacles stay over it
local SEA_DOWN = 35

-- A jelly in the Open Blue's look (BlueDress `jellyfish`): a stepped bell glowing
-- through, a bright rim, long tentacles and oral arms, all welded to an invisible core,
-- so it moves as one part (PC 2026-11-03: six parts a jelly were most of what moved
-- past the window). Big and nearly solid (owner, 2026-11-02: at 1.6-3.4 studs and half
-- see-through they were lost in the haze).
local function jelly(parent: Instance, size: number, color: Color3, rng: Random): { BasePart }
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.Transparency = 1
	core.Size = Vector3.one * 0.2
	core.CFrame = CFrame.identity
	core.Parent = parent
	local function piece(
		name: string,
		shape: Enum.PartType,
		box: Vector3,
		at: CFrame,
		tint: Color3,
		clear: number
	)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Anchored = false
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = tint
		p.Transparency = clear
		p.Size = box
		p.CFrame = at
		p.Parent = parent
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = core
		weld.Part1 = p
		weld.Parent = p
	end
	local upright = CFrame.Angles(0, 0, math.pi / 2) -- (a cylinder's axis is its X)
	local function disc(name: string, diameter: number, thick: number, y: number, tint: Color3, clear: number)
		piece(
			name,
			Enum.PartType.Cylinder,
			Vector3.new(thick, diameter, diameter),
			CFrame.new(0, y, 0) * upright,
			tint,
			clear
		)
	end
	local glow = color:Lerp(Color3.new(0.8, 0.9, 1), 0.25)
	disc("Bell", size, size * 0.22, 0, color, 0.3)
	disc("BellTop", size * 0.72, size * 0.2, size * 0.2, color, 0.25)
	disc("BellCap", size * 0.4, size * 0.14, size * 0.36, color, 0.18)
	disc("Rim", size * 1.04, size * 0.07, -size * 0.1, glow, 0.05)
	local thick = math.max(0.25, size * 0.04)
	for k = 1, 8 do
		local a = k / 8 * TAU
		local long = size * rng:NextNumber(1.8, JELLY_TRAIL)
		piece(
			"Tentacle",
			Enum.PartType.Block,
			Vector3.new(thick, long, thick),
			CFrame.new(math.cos(a) * size * 0.42, -size * 0.12 - long / 2, math.sin(a) * size * 0.42)
				* CFrame.Angles(rng:NextNumber(-0.12, 0.12), 0, rng:NextNumber(-0.12, 0.12)),
			glow,
			0.15
		)
	end
	for k = 1, 3 do
		local a = k / 3 * TAU + 0.5
		local long = size * rng:NextNumber(1.1, 1.7)
		piece(
			"OralArm",
			Enum.PartType.Block,
			Vector3.new(size * 0.14, long, size * 0.08),
			CFrame.new(math.cos(a) * size * 0.1, -size * 0.12 - long / 2, math.sin(a) * size * 0.1)
				* CFrame.Angles(0, a, 0.15),
			color,
			0.25
		)
	end
	return { core }
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
		jelly = false,
		phase = 0,
		reach = 36,
		every = 4,
		slot = 2,
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
			jelly = false,
			phase = 0,
			reach = 10,
			every = 3,
			slot = k,
		})
	end
	-- Jellies rising and sinking at every depth
	for i = 1, 9 do
		local holder = Instance.new("Model")
		holder.Name = "Jelly"
		holder.Parent = model
		local size = rng:NextNumber(4.5, 8.5)
		local parts = jelly(holder, size, JELLY[(i % #JELLY) + 1], rng)
		local ahead = rng:NextNumber(28, 110)
		local side = rng:NextNumber(-60, 60)
		-- (its bob is 7 studs, its tentacles up to JELLY_TRAIL bells under it)
		local rise = rng:NextNumber(-SEA_DOWN + 8 + size * (JELLY_TRAIL + 0.15), 34)
		local phase = rng:NextNumber(0, TAU)
		table.insert(drifters, {
			parts = parts,
			jelly = true,
			phase = phase,
			reach = size * (JELLY_TRAIL + 0.2),
			every = 4,
			slot = i % 4,
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
			jelly = false,
			phase = 0,
			reach = 1.5,
			every = 2,
			slot = i % 2,
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

local function driftViews(now: number, camera: Vector3, look: Vector3)
	for window in windowParts do
		local distance = (window.Position - camera).Magnitude
		local near = distance < VIEW_RANGE
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
		-- Only from inside the room (the sea is behind the window's glass) with the
		-- window on screen
		local out = window:GetAttribute("Out")
		if typeof(out) == "Vector3" and (camera - window.Position):Dot(out) > 0 then
			continue
		end
		local radius = window:GetAttribute("Radius")
		if
			not onScreen(
				look,
				camera,
				window.Position,
				distance,
				if typeof(radius) == "number" then radius else 14
			)
		then
			continue
		end
		local opening = (if typeof(radius) == "number" then radius else 14) + 1
		local glass = window.Position
		local outward = if typeof(out) == "Vector3" then out.Unit else window.CFrame.LookVector
		local toGlass = (glass - camera):Dot(outward)
		-- Whether the line of sight to `at` passes through the round opening, with room
		-- for what reaches `reach` round it (the rest of the view is behind rock)
		local function seen(at: Vector3, reach: number): boolean
			local toward = at - camera
			local along = toward:Dot(outward)
			if along <= toGlass then
				return false
			end
			local scale = toGlass / along
			return (camera + toward * scale - glass).Magnitude < opening + reach * scale
		end
		for _, drifter in view.drifters do
			local placed = drifter.placed
			if placed and drifter.every > 1 and (frameCount + drifter.slot) % drifter.every ~= 0 then
				continue
			end
			local frame = drifter.path(now)
			-- Moved while it's seen, and once more when it goes out of sight (so it's
			-- never left still at the edge of the view); all placed the first frame
			-- the window is in view
			if placed and not seen(frame.Position, drifter.reach) and not seen(placed, drifter.reach) then
				continue
			end
			drifter.placed = frame.Position
			local body = drifter.body
			if body and drifter.motion then
				drifter.motion.t = now
				AmbientBody.pose(body, drifter.motion)
				table.insert(moveParts, body.root)
				table.insert(moveFrames, AmbientBody.frame(body, frame))
			elseif drifter.display then
				PreyDisplay.pose(drifter.display, frame, moveParts, moveFrames)
			elseif drifter.jelly then
				-- (its bell, the strands welded under it, rocking gently)
				local sway = math.sin(now * 0.9 + drifter.phase) * 0.12
				table.insert(moveParts, drifter.parts[1])
				table.insert(moveFrames, frame * CFrame.Angles(sway, 0, sway * 0.6))
			end
		end
	end
	for window, view in views do
		if windowParts[window] == nil then
			view.model:Destroy()
			views[window] = nil
		end
	end
end

function AquariumController.start()
	tankParts = tracked("AquariumTank")
	windowParts = tracked("ObservatoryWindow")
	RunService.Heartbeat:Connect(function()
		local camera = workspace.CurrentCamera
		if camera == nil then
			return
		end
		if
			next(tankParts) == nil
			and next(windowParts) == nil
			and next(tanks) == nil
			and next(views) == nil
		then
			return
		end
		frameCount += 1
		local now = workspace:GetServerTimeNow()
		local cframe = camera.CFrame
		local at, look = cframe.Position, cframe.LookVector
		table.clear(moveParts)
		table.clear(moveFrames)
		swimTanks(now, at, look)
		driftViews(now, at, look)
		if #moveParts > 0 then
			workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return AquariumController
