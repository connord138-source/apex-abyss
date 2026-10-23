--!strict
-- Kelp sways (owner, 2026-10-08: nothing in the water moved but the fish). Every
-- kelp plant the server built (workspace.World.Biomes.Kelp, "Kelp" models) bends
-- gently about its base in a slow current. Only the plants within reach of the
-- camera move, in one BulkMoveTo a frame, so a thousand plants cost nothing.
--
-- Plants are collected as they come into reach, not once at the start: with
-- streaming, a plant's Model arrives before its parts, so a plant collected at the
-- start had no stalk and never moved (retest 2026-10-08: the first start swayed
-- nothing, a later one swayed everything). A plant whose parts streamed in or out
-- is collected again; each part's rest pose is kept (the `KelpRest` attribute), so
-- collecting a plant mid-sway never makes it drift.
--
-- Nothing about a plant's sway is random per collect (owner, 2026-10-11: "the kelp
-- ... still glitch while they move"): the records were kept in a weak table keyed
-- by the plant's Model, and Luau collects an Instance key whenever no script holds
-- that Model, though the plant is still there; every garbage collection re-rolled
-- each plant's phase and dropped its lean, so the whole forest snapped to new poses
-- (the 2026-10-10 spring-back readings jumped 5° → 1° → 4° within 0.15 s). The
-- records are held strongly now (pruned when a plant goes), and a plant's phase,
-- rate and reach come from where it stands, so a plant streamed out and back sways
-- on exactly as before.
--
-- Kelp is soft, so fish swim through it, but it gives way (owner, 2026-10-10: "the
-- kelp and a lot of other items are phasing and glitching"): a fish brushing a
-- plant nudges it aside and drags it a little along its swim, through a damped
-- spring, so it eases over and wobbles back (it used to swing up to 30° at once
-- and flip across the stalk as a fish passed its middle). A plant the camera is
-- inside fades out, eased, instead of flickering across the lens. Sway dies away
-- over the last stretch of reach, so a plant never stops mid-lean or pops back in.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

type Plant = {
	model: Model,
	base: CFrame, -- the stalk's foot, upright
	at: Vector3, -- (its position)
	salt: number, -- which frames it's posed on when it isn't posed every frame
	parts: { BasePart },
	offsets: { CFrame }, -- each part from the base
	phase: number,
	rate: number,
	amplitude: number,
	height: number, -- how tall it stands
	spread: number, -- how far its fronds reach round the stalk
	leanX: number, -- where fish have pushed its top (radians toward +X and +Z) ...
	leanZ: number,
	spinX: number, -- ... and how fast that lean is moving
	spinZ: number,
	fade: number, -- its LocalTransparencyModifier now
	shownFade: number, -- the one last written to its parts
	posed: boolean, -- moved off its rest pose
	seen: number, -- the rescan that last found it in reach
	recheckUntil: number, -- while its parts may still be streaming in, its part count is checked
}

local REACH = 120 -- studs from the camera a plant still sways ...
local BLEND = 40 -- ... easing to stillness over the last this many
-- (180 and 50 until 2026-10-20: the sway moved as many parts as all the prey, and
-- moving parts is what the renderer's prepare step pays for, PC 2026-10-20 round 2)
-- Past HALF_RATE studs a plant no fish is pushing is posed every other frame, past
-- THIRD_RATE every third (PC 2026-10-22: the Kelp Cathedral's tall rings put ~665
-- pieces in reach of its nave, 37.8 ms/s; then 42.5: a plant skipped this frame had
-- still worked out its push, spring and fade first, so now a resting plant with no
-- fish by it does nothing on the frames it isn't posed)
local HALF_RATE = 50
local THIRD_RATE = 85
-- Plants are kept in a grid of CELL-stud cells by where they stand, so a rescan
-- looks only at the cells round the camera (it had walked every plant in the
-- Shallows twice a second); a plant's part count is re-checked only for RECHECK s
-- after it's collected (its parts stream in after its Model)
local CELL = 64
local RECHECK = 10
local SCAN_REACH = REACH + 80 -- plants a rescan keeps (the camera moves between scans)
local RESCAN = 0.5 -- seconds between picking the plants in reach
local GIVE = 2.5 -- studs round the stalk's fronds a fish touches it (plus its radius)
local CORE = 0.35 -- share of the fronds' reach that's thick enough to push
local MAX_LEAN = 0.22 -- radians a short plant leans away at most ...
local MAX_TOP = 24 -- ... and studs a tall one's top moves
local DRAG = 0.8 -- how much of the lean follows the fish's swim (the rest is away from it)
local PUSH = 1.6 -- how hard a fish pushes (a full push leans it the most)
local STIFF = 16 -- the lean's spring (1/s²) ...
local DAMP = 5.2 -- ... and damping (1/s): a little under critical, so it wobbles once
local FADE_RADIUS = 3.5 -- studs round the stalk (plus a share of the fronds) the camera fades it
local FADE_OUT = 2 -- extra studs before it comes back (no flicker on the edge)
local FADED = 0.75 -- its LocalTransparencyModifier then
local FADE_RATE = 7 -- how fast it fades (per second)

local KelpController = {}

local folder: Instance? = nil
local grid: { [number]: { Model } } = {}
local indexed: { [Model]: boolean } = {}
local known: { [Model]: Plant } = {}
local active: { Plant } = {}
local settle: { Plant } = {} -- left reach while posed: put back at rest
local parts: { BasePart } = {}
local frames: { CFrame } = {}
local clock = 0
local sinceScan = RESCAN
local scan = 0

-- A part's pose as the server built it (taken the first time this client sees it)
local function restOf(part: BasePart): CFrame
	local rest = part:GetAttribute("KelpRest")
	if typeof(rest) == "CFrame" then
		return rest
	end
	part:SetAttribute("KelpRest", part.CFrame)
	return part.CFrame
end

local function partsOf(plant: Model): { BasePart }
	local list = {}
	for _, descendant in plant:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

-- 0..1 from where a plant stands, the same on every collect and every client
local function hash(at: Vector3, salt: number): number
	local n = math.sin(at.X * 12.9898 + at.Z * 78.233 + at.Y * 3.7719 + salt * 41.414) * 43758.5453
	return n - math.floor(n)
end

-- The plant's sway record from the parts it has now, or nil while its stalk hasn't
-- streamed in
local function collect(plant: Model, old: Plant?): Plant?
	local stalk = plant:FindFirstChild("Stalk")
	if stalk == nil or not stalk:IsA("BasePart") then
		return nil
	end
	local base = restOf(stalk) * CFrame.new(0, -stalk.Size.Y / 2, 0)
	local at = base.Position
	local entry: Plant = {
		model = plant,
		base = base,
		at = at,
		salt = math.floor(hash(at, 4) * 12),
		parts = {},
		offsets = {},
		phase = hash(at, 1) * 2 * math.pi,
		rate = 0.3 + 0.25 * hash(at, 2),
		amplitude = 0.035 + 0.035 * hash(at, 3),
		height = stalk.Size.Y,
		spread = 0,
		leanX = if old then old.leanX else 0,
		leanZ = if old then old.leanZ else 0,
		spinX = if old then old.spinX else 0,
		spinZ = if old then old.spinZ else 0,
		fade = if old then old.fade else 0,
		shownFade = -1, -- parts that just streamed in need it written
		posed = true, -- write its pose at once
		seen = scan,
		recheckUntil = clock + RECHECK,
	}
	for _, part in partsOf(plant) do
		table.insert(entry.parts, part)
		local offset = base:ToObjectSpace(restOf(part))
		table.insert(entry.offsets, offset)
		entry.height = math.max(entry.height, offset.Y + part.Size.Y / 2)
		if part.Transparency < 1 then
			local across = math.sqrt(offset.X * offset.X + offset.Z * offset.Z)
			entry.spread = math.max(entry.spread, across + math.max(part.Size.X, part.Size.Z) / 2)
		end
	end
	return entry
end

local function cellKey(cx: number, cz: number): number
	return (cx + 32768) * 65536 + (cz + 32768)
end

-- Files a plant in the grid by its pivot (known even before its parts stream in)
local function filePlant(child: Instance)
	if not child:IsA("Model") or indexed[child :: Model] then
		return
	end
	local plant = child :: Model
	indexed[plant] = true
	local at = plant:GetPivot().Position
	local key = cellKey(math.floor(at.X / CELL), math.floor(at.Z / CELL))
	local list = grid[key]
	if list == nil then
		list = {}
		grid[key] = list
	end
	table.insert(list, plant)
end

local function rescan()
	scan += 1
	local holder = folder
	if holder == nil then
		return
	end
	local camera = Workspace.CurrentCamera.CFrame.Position
	local previous = table.clone(active)
	table.clear(active)
	local x0, x1 = math.floor((camera.X - SCAN_REACH) / CELL), math.floor((camera.X + SCAN_REACH) / CELL)
	local z0, z1 = math.floor((camera.Z - SCAN_REACH) / CELL), math.floor((camera.Z + SCAN_REACH) / CELL)
	for cx = x0, x1 do
		for cz = z0, z1 do
			local list = grid[cellKey(cx, cz)]
			if list == nil then
				continue
			end
			for i = #list, 1, -1 do
				local plant = list[i]
				-- (a plant streamed out is dropped from its cell; it's filed again if it
				-- comes back)
				if plant.Parent ~= holder then
					indexed[plant] = nil
					list[i] = list[#list]
					list[#list] = nil
					continue
				end
				if (plant:GetPivot().Position - camera).Magnitude > SCAN_REACH then
					continue
				end
				local entry: Plant? = known[plant]
				local first: BasePart? = if entry then entry.parts[1] else nil
				local stale = entry == nil
					or first == nil
					or first.Parent == nil
					or (clock < (entry :: Plant).recheckUntil and #(entry :: Plant).parts ~= #partsOf(plant))
				if stale then
					entry = collect(plant, entry)
					known[plant] = entry :: any
				end
				if entry and #entry.parts > 0 then
					entry.seen = scan
					table.insert(active, entry)
				end
			end
		end
	end
	-- Plants that left reach still leaning go back to rest; gone plants are dropped
	for _, entry in previous do
		if entry.seen ~= scan and entry.posed then
			table.insert(settle, entry)
		end
	end
	for plant in known do
		if plant.Parent == nil then
			known[plant] = nil
		end
	end
end

-- Every player's fish near the camera: where it is, how it's moving and how wide
-- (prey are small and swim round the kelp)
type Swimmer = { position: Vector3, velocity: Vector3, radius: number }
local swimmers: { Swimmer } = {}
local function gatherSwimmers(camera: Vector3)
	table.clear(swimmers)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - camera).Magnitude < SCAN_REACH then
			local length = (character :: Model):GetAttribute("Length")
			table.insert(swimmers, {
				position = root.Position,
				velocity = root.AssemblyLinearVelocity,
				radius = if typeof(length) == "number" then length * 0.3 else 1,
			})
		end
	end
end

-- Whether any fish is near enough round a plant's stalk to push it (a quick look
-- before the plant's own axes are worked out)
local function touched(plant: Plant): boolean
	local at = plant.at
	for _, swimmer in swimmers do
		local reach = plant.spread * CORE + GIVE + swimmer.radius + 2
		local p = swimmer.position
		local dx, dz = p.X - at.X, p.Z - at.Z
		if dx * dx + dz * dz < reach * reach and p.Y > at.Y - reach and p.Y < at.Y + plant.height + reach then
			return true
		end
	end
	return false
end

-- Where the fish in a plant push its top (radians toward +X and +Z in its own
-- axes): out of the way near the stalk's edge, along the swim through its middle.
-- Smooth everywhere, so a fish crossing the stalk never flips it.
local function pushFor(plant: Plant): (number, number)
	local px, pz = 0, 0
	for _, swimmer in swimmers do
		local q = plant.base:PointToObjectSpace(swimmer.position)
		if q.Y < -swimmer.radius or q.Y > plant.height + swimmer.radius then
			continue
		end
		local reach = plant.spread * CORE + GIVE + swimmer.radius
		local d = math.sqrt(q.X * q.X + q.Z * q.Z)
		if d >= reach then
			continue
		end
		local s = d / reach
		local inside = (1 - s) * (1 - s) -- 1 at the stalk, 0 at the edge
		-- Away from the fish: zero at the stalk and at the edge, so it never jumps
		local away = 4 * (1 - s) / reach
		local ax, az = -q.X * away, -q.Z * away
		-- Along its swim, the more the deeper in
		local v = plant.base:VectorToObjectSpace(swimmer.velocity)
		local speed = math.sqrt(v.X * v.X + v.Z * v.Z)
		local dx, dz = 0, 0
		if speed > 0.5 then
			local k = inside * math.min(speed / 12, 1) / speed
			dx, dz = v.X * k, v.Z * k
		end
		-- A big fish pushes harder, and a fish high up has the leverage
		local heft = math.clamp(0.6 + swimmer.radius * 0.3, 0.6, 1)
		local lever = 0.4 + 0.6 * math.clamp(q.Y / plant.height, 0, 1)
		local k = heft * lever * PUSH
		px += (ax * (1 - DRAG) * 2 + dx * DRAG) * k
		pz += (az * (1 - DRAG) * 2 + dz * DRAG) * k
	end
	local size = math.sqrt(px * px + pz * pz)
	if size > 1 then
		px, pz = px / size, pz / size
	end
	local most = math.min(MAX_LEAN, MAX_TOP / math.max(plant.height, 1))
	return px * most, pz * most
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function setFade(plant: Plant, dt: number, inside: boolean)
	local want = if inside then FADED else 0
	plant.fade += (want - plant.fade) * math.min(1, dt * FADE_RATE)
	if math.abs(plant.fade - want) < 0.01 then
		plant.fade = want
	end
	if plant.fade == plant.shownFade then
		return
	end
	plant.shownFade = plant.fade
	for _, part in plant.parts do
		if part.Parent ~= nil and part.Transparency < 1 then
			part.LocalTransparencyModifier = plant.fade
		end
	end
end

local frameCount = 0

local function pose(plant: Plant, frame: CFrame)
	for i, part in plant.parts do
		if part.Parent ~= nil then
			table.insert(parts, part)
			table.insert(frames, frame * plant.offsets[i])
		end
	end
end

local function step(dt: number)
	dt = math.min(dt, 0.1)
	clock += dt
	sinceScan += dt
	if sinceScan >= RESCAN then
		sinceScan = 0
		rescan()
	end
	local camera = Workspace.CurrentCamera.CFrame.Position
	gatherSwimmers(camera)
	table.clear(parts)
	table.clear(frames)
	for _, plant in settle do
		if plant.seen ~= scan and plant.posed then
			plant.posed = false
			plant.leanX, plant.leanZ, plant.spinX, plant.spinZ = 0, 0, 0, 0
			pose(plant, plant.base)
		end
	end
	table.clear(settle)
	-- The spring's steps stay short however long the frame
	local steps = math.max(1, math.ceil(dt * 60))
	local h = dt / steps
	frameCount += 1
	for _, plant in active do
		-- (how far the camera is from its stalk, in the world's axes: a plant stands
		-- within a few degrees of upright)
		local at = plant.at
		local dx, dz = camera.X - at.X, camera.Z - at.Z
		local across = math.sqrt(dx * dx + dz * dz)
		local up = camera.Y - at.Y
		local over = up - math.clamp(up, 0, plant.height)
		local distance = math.sqrt(across * across + over * over)
		local weight = smooth((REACH - distance) / BLEND)
		local radius = FADE_RADIUS + plant.spread * 0.25 + (if plant.fade > 0 then FADE_OUT else 0)
		local resting = math.abs(plant.leanX) + math.abs(plant.leanZ) < 1e-3
			and math.abs(plant.spinX) + math.abs(plant.spinZ) < 1e-3
		local pushed = weight > 0 and touched(plant)
		local every = if distance <= HALF_RATE then 1 elseif distance <= THIRD_RATE then 2 else 3
		-- A resting plant no fish is near, with the camera nowhere inside it, does
		-- nothing on the frames it isn't posed
		if
			every > 1
			and resting
			and not pushed
			and plant.fade == 0
			and across > radius + 4
			and (plant.salt + frameCount) % every ~= 0
		then
			continue
		end
		-- Give way to fish through a damped spring
		local wantX, wantZ = 0, 0
		if pushed then
			wantX, wantZ = pushFor(plant)
		end
		if not (resting and wantX == 0 and wantZ == 0) then
			for _ = 1, steps do
				plant.spinX += ((wantX - plant.leanX) * STIFF - plant.spinX * DAMP) * h
				plant.spinZ += ((wantZ - plant.leanZ) * STIFF - plant.spinZ * DAMP) * h
				plant.leanX += plant.spinX * h
				plant.leanZ += plant.spinZ * h
			end
		end
		local still = weight <= 0
			and math.abs(plant.leanX) + math.abs(plant.leanZ) < 1e-3
			and math.abs(plant.spinX) + math.abs(plant.spinZ) < 1e-3
		-- The camera inside it fades it (a little further out before it comes back)
		if across < radius + 4 or plant.fade > 0 then
			local eye = plant.base:PointToObjectSpace(camera)
			setFade(
				plant,
				dt,
				eye.Y > -1 and eye.Y < plant.height + 1 and math.sqrt(eye.X * eye.X + eye.Z * eye.Z) < radius
			)
		end
		if still then
			if plant.posed then
				plant.posed = false
				plant.leanX, plant.leanZ, plant.spinX, plant.spinZ = 0, 0, 0, 0
				pose(plant, plant.base)
			end
			continue
		end
		plant.posed = true
		if
			every > 1
			and math.abs(plant.leanX) + math.abs(plant.leanZ) < 0.01
			and (plant.salt + frameCount) % every ~= 0
		then
			continue
		end
		-- A slow lean that wanders round, so no two plants nod together. About X
		-- tips the top toward +Z; about Z by a negative angle, toward +X.
		local a = plant.amplitude * weight
		local tilt = CFrame.Angles(
			a * math.sin(clock * plant.rate + plant.phase) + plant.leanZ,
			0,
			a * 0.7 * math.sin(clock * plant.rate * 0.73 + plant.phase * 1.3) - plant.leanX
		)
		pose(plant, plant.base * tilt)
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function KelpController.start()
	task.spawn(function()
		-- The kelp lives in World.Biomes.Kelp, built once the Terrain answers raycasts
		local world = Workspace:WaitForChild("World", 60)
		local biomes = if world then world:WaitForChild("Biomes", 120) else nil
		folder = if biomes then biomes:WaitForChild("Kelp", 120) else nil
		if folder == nil then
			return
		end
		local holder = folder :: Instance
		for _, child in holder:GetChildren() do
			filePlant(child)
		end
		holder.ChildAdded:Connect(filePlant)
		RunService.RenderStepped:Connect(step)
	end)
end

return KelpController
