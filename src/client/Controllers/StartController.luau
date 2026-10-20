--!strict
-- The start screen (owner, 2026-10-09: "a start screen when players load into the
-- server. Just hit any button to start and then it pushes them straight to the den
-- and tutorial. Starter screen should have motion and some fish swimming by with
-- maybe some kelp"; 2026-10-19: "The start screen could be dialed up as well. It
-- could be rolling shots of different fish around the different biomes or just have
-- the actual visual quality turned up").
--
-- It covers the game from the first frame. While the game loads, a plain water
-- backdrop (light shafts, marine snow, rising bubbles) shows under the title; the old
-- ViewportFrame scene of swimming fish and kelp is gone now the real sea plays
-- (owner, 2026-10-20). As soon as the first shot's water is in, it clears onto an
-- attract mode of documentary shots (Config/Start, Shared/StartShots), one per biome,
-- each following a real prey school on the shared clock with the camera easing
-- alongside, ahead of or round it, letterboxed, a lower third naming the fish and its
-- biome, cut through a dip into murk or a bubble wash.
-- Each next shot's water is streamed in by the server while the current one plays
-- (the StartShot request; StartService puts a replication focus there and answers
-- with the `StartStreamed` attribute: how many of the world's parts stand round the
-- school, and where); a shot is cut to only once those parts have reached this
-- client, its Terrain answers a ray there and its camera's path has been checked
-- clear of rock, and the cut is then held under the murk with the camera already at
-- the new spot until it has loaded round it (Config/Start `mesh`, `parts`, `queue`,
-- `holdMax`): Roblox meshes Terrain only round the camera and can't say when it's
-- done, and a cut straight in showed the floor and the kelp missing for a few
-- seconds (owner, 2026-10-20). One that doesn't arrive is skipped, and with none
-- ready the backdrop comes back. The camera is taken through
-- CameraController.override; every other GUI is hidden meanwhile, the music keeps
-- the hub's list and BiomeController reads the dark where the shot is (`viewpoint`).
--
-- The title, the three how-to cards and the prompt stay over all of it. Once the fish
-- has spawned in its den the prompt shows, and any key, click, tap or controller
-- button dives in: the shot pushes on into a bubble wash, the camera goes back to
-- the fish in its den behind it, and the wash clears there, where the tutorial (or
-- the Daily panel, or WELCOME BACK) picks up.
--
-- Other controllers hold their join-time UI until then with `afterStart`.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Biomes = require(ReplicatedStorage.Shared.Biomes)
local Config = require(ReplicatedStorage.Shared.Config)
local Schools = require(ReplicatedStorage.Shared.Schools)
local Signal = require(ReplicatedStorage.Shared.Signal)
local StartShots = require(ReplicatedStorage.Shared.StartShots)
local Timing = require(ReplicatedStorage.Shared.Timing)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local CameraController = require(script.Parent.CameraController)
local MusicController = require(script.Parent.MusicController)
local OceanController = require(script.Parent.OceanController)

local StartController = {
	-- () — the player pressed start and the game is in front of them
	started = Signal.new(),
}

local MIN_SHOW = 2.4 -- seconds on screen before the prompt, so it never just flashes
local MAX_WAIT = 25 -- the prompt shows by then even if the fish hasn't spawned yet
local GRACE = 0.45 -- input is ignored this long after the prompt appears
local LOGO_HEIGHT = 200 -- the title logo's height on the 1280x720 design layer
local LOGO_HEIGHT_TOUCH = 160 -- and on the phones' 960x540 one
local LOGO_ASPECT = 838 / 708 -- marketing/logo.png's width over its height

local Start = Config.Start
local timing = Start.timing
local MURK = Color3.fromRGB(6, 30, 42) -- a dip between shots
local WASH = Color3.fromRGB(22, 84, 106) -- a bubble wash, and the dive
local ASK_GAP = 1.6 -- seconds between shot requests (Net allows one every 1.5)
local GUARD_EASE = 3 -- how fast the camera eases back out once rock no longer pulls it in
local CURSOR_IDLE = 2 -- seconds the mouse must rest before the cursor hides over a shot

local up = false
local done = false
local waiting: { () -> () } = {}
local viewing: Vector3? = nil -- the shot's camera, while one is on screen

-- Whether the start screen is covering the game
function StartController.isUp(): boolean
	return up
end

-- Runs `fn` once the player has started (straight away if they already have)
function StartController.afterStart(fn: () -> ())
	if done then
		task.spawn(fn)
	else
		table.insert(waiting, fn)
	end
end

-- Where the start screen's shot is filming from, while one is on screen (the fish
-- waits in its den meanwhile): BiomeController reads the dark there
function StartController.viewpoint(): Vector3?
	return if up then viewing else nil
end

-- Screen ---------------------------------------------------------------------------

-- The device, read when the screen opens and changed only by real input of another
-- kind: the Device Simulator turns its keyboard flag on ~2 s in, which flipped a
-- phone's prompt to PRESS ANY KEY (playtest 2026-10-09)
type Device = "touch" | "gamepad" | "keys"
local device: Device = "keys"

local function deviceFromInput(kind: Enum.UserInputType): Device?
	if kind == Enum.UserInputType.Touch then
		return "touch"
	elseif kind.Name:sub(1, 7) == "Gamepad" then
		return "gamepad"
	elseif
		kind == Enum.UserInputType.Keyboard
		or kind == Enum.UserInputType.MouseButton1
		or kind == Enum.UserInputType.MouseButton2
	then
		return "keys"
	end
	return nil
end

local function promptText(): string
	if device == "touch" then
		return "TAP TO START"
	elseif device == "gamepad" then
		return "PRESS ANY BUTTON"
	end
	return "PRESS ANY KEY"
end

local function biteKey(): string
	if device == "touch" then
		return "The BITE button"
	elseif device == "gamepad" then
		return "RB or X"
	end
	return "Right click"
end

local function dashKey(): string
	if device == "touch" then
		return "DASH"
	elseif device == "gamepad" then
		return "RT"
	end
	return "Left click"
end

local function ready(): boolean
	local character = Players.LocalPlayer.Character
	return character ~= nil
		and character:FindFirstChild("HumanoidRootPart") ~= nil
		and ClientState.current ~= nil
end

local function gradient(
	parent: Instance,
	rotation: number,
	transparency: NumberSequence,
	color: ColorSequence?
)
	local made = Instance.new("UIGradient")
	made.Rotation = rotation
	made.Transparency = transparency
	if color then
		made.Color = color
	end
	made.Parent = parent
	return made
end

-- Shots ------------------------------------------------------------------------------

-- A shot on screen
type Show = {
	plan: StartShots.Plan,
	name: string, -- the lower third: the fish
	place: string, -- and its biome and levels
	color: Color3, -- the biome's accent
	guard: number, -- how far the camera may stand from its subject (rock pulls it in)
	captioned: boolean,
	token: string, -- the shot it was asked for as ("<shot>:<school>"): its focus stays while it plays
}

-- A shot's area as the server streamed it: how many of the world's parts stand round
-- its school, and where (StartShots.partsNear)
type Area = {
	parts: number,
	at: Vector3,
	checkedAt: number,
	ok: boolean,
}

-- The next shot: asked for, then its water in, then its path checked
type Pending = {
	shot: number,
	school: number,
	token: string, -- what StartService's `StartStreamed` starts with once its water is in
	askedAt: number,
	area: Area?, -- read from that answer
	arrivedAt: number?,
	planning: boolean?, -- its path is being checked (a few frames: planFor)
	plan: StartShots.Plan?,
}

local show: Show? = nil
local pending: Pending? = nil
local queue: { number } = {}
local lastBiome: string? = nil
local lastAsk = -math.huge
local everShown = false
local resting: { [number]: number } = {} -- shots skipped until then (os.clock): no water, no clear path
-- Schools no clear path was found for, skipped until then (os.clock): most failures
-- pass (a steep stretch of its loop, rock along this part of its path)
local bad: { [number]: number } = {}
local BAD_FOR = 120
local candidateLists: { [number]: { number } } = {}
local rng = Random.new()

local worldParams: RaycastParams? = nil
local worldFolder: Instance? = nil
-- Rays see the Terrain and the built world (wrecks, the ruins' stones, boulders);
-- kelp and coral are see-through to them, which the shots' `floor` allows for
local function castParams(): RaycastParams
	local world = workspace:FindFirstChild("World")
	local params = worldParams
	if params == nil or world ~= worldFolder then
		local made = RaycastParams.new()
		made.FilterType = Enum.RaycastFilterType.Include
		made.FilterDescendantsInstances = if world
			then { workspace.Terrain, world }
			else { workspace.Terrain }
		made.IgnoreWater = true
		worldParams, worldFolder = made, world
		return made
	end
	return params
end

local function castWorld(origin: Vector3, direction: Vector3): number?
	local hit = workspace:Raycast(origin, direction, castParams())
	return if hit then hit.Distance else nil
end

-- The same, for checking the next shot's path while one plays: a few hundred rays a
-- frame, then it waits for the next (a whole check is up to ~1,500 rays a school,
-- which would hitch the shot on screen)
local CASTS_PER_FRAME = 160
local castsThisFrame = 0
local function castSpread(origin: Vector3, direction: Vector3): number?
	castsThisFrame += 1
	if castsThisFrame >= CASTS_PER_FRAME then
		castsThisFrame = 0
		RunService.Heartbeat:Wait()
	end
	return castWorld(origin, direction)
end

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true

local function candidatesOf(index: number): { number }
	local list = candidateLists[index]
	if list == nil then
		list = StartShots.candidates(Start.shots[index])
		candidateLists[index] = list
	end
	return list
end

-- One of the shot's best schools, at random so each visit differs: one of the three
-- gentlest swimmers (StartShots.candidates' order) of its first prey that has any
-- left, or for the temple shot of those near its temple
local function pickSchool(index: number): number?
	local best: { number } = {}
	local first: string? = nil
	local shot = Start.shots[index]
	for _, school in candidatesOf(index) do
		if (bad[school] or 0) > os.clock() then
			continue
		end
		local group = if shot.landmark == "temple" then "temple" else Schools.list[school].prey
		first = first or group
		if group == first and #best < 3 then
			table.insert(best, school)
		end
	end
	if #best == 0 then
		return nil
	end
	return best[rng:NextInteger(1, #best)]
end

-- The next shot to ask for: one of Config/Start `first` to open, then every shot in a
-- shuffled round, never the same biome twice running, none that's resting
local function nextShot(): number?
	local now = os.clock()
	local function free(index: number): boolean
		return (resting[index] or 0) <= now and Start.shots[index].biome ~= lastBiome
	end
	if not everShown then
		local opening: { number } = {}
		for _, id in Start.first do
			local index = Start.byId[id]
			if index and free(index) then
				table.insert(opening, index)
			end
		end
		if #opening > 0 then
			return opening[rng:NextInteger(1, #opening)]
		end
	end
	for _ = 1, 2 do
		for i, index in queue do
			if free(index) then
				table.remove(queue, i)
				return index
			end
		end
		table.clear(queue)
		for index in Start.shots do
			table.insert(queue, index)
		end
		for i = #queue, 2, -1 do
			local j = rng:NextInteger(1, i)
			queue[i], queue[j] = queue[j], queue[i]
		end
	end
	return nil
end

local function ask()
	if os.clock() - lastAsk < ASK_GAP then
		return
	end
	local index = nextShot()
	if index == nil then
		return
	end
	local school = pickSchool(index)
	if school == nil then
		resting[index] = os.clock() + 600
		return
	end
	lastAsk = os.clock()
	pending = {
		shot = index,
		school = school,
		token = `{index}:{school}`,
		askedAt = os.clock(),
	}
	-- (and the shot on screen, whose focus the server keeps)
	local showing = show
	local keepShot, keepSchool = 0, 0
	if showing then
		local a, b = string.match(showing.token, "^(%d+):(%d+)$")
		keepShot, keepSchool = tonumber(a) or 0, tonumber(b) or 0
	end
	ClientState.request("StartShot", index, school, keepShot, keepSchool)
end

-- Whether nearly all of an area's parts have reached this client (checked at most
-- every AREA_EVERY seconds: a spatial query over ~110 studs)
local AREA_EVERY = 0.3
local function areaIn(area: Area): boolean
	local now = os.clock()
	if now - area.checkedAt >= AREA_EVERY then
		area.checkedAt = now
		area.ok = area.parts <= 0 or StartShots.partsNear(area.at) >= area.parts * timing.parts
	end
	return area.ok
end

-- The server's answer for a shot: "<shot>:<school>|<parts>|<x>,<y>,<z>"
local function areaOf(answer: string): Area?
	local parts, x, y, z = string.match(answer, "|(%d+)|([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)$")
	local n, px, py, pz = tonumber(parts), tonumber(x), tonumber(y), tonumber(z)
	if n == nil or px == nil or py == nil or pz == nil then
		return nil
	end
	return { parts = n, at = Vector3.new(px, py, pz), checkedAt = -math.huge, ok = false }
end

-- Whether a pending shot's water is in: the server has streamed it, nearly all of
-- the world's parts round its school are here, and (unless its school swims in open
-- water far over the floor) the Terrain under it answers a ray
local function arrived(p: Pending): boolean
	local answer = Players.LocalPlayer:GetAttribute("StartStreamed")
	if typeof(answer) ~= "string" or string.sub(answer, 1, #p.token + 1) ~= p.token .. "|" then
		return false
	end
	if p.area == nil then
		p.area = areaOf(answer)
	end
	local area = p.area
	if area and not areaIn(area) then
		return false
	end
	local near, over = StartShots.groundNear(p.school)
	if not near then
		return true
	end
	local at = Schools.schoolFrame(p.school, Timing.clock()).Position
	return workspace:Raycast(at + Vector3.new(0, 4, 0), Vector3.new(0, -(over + 120), 0), terrainOnly) ~= nil
end

-- The nearest wreck's hull to a school, once its area is in (the wreck shot's landmark)
local function wreckNear(school: number): Vector3?
	local world = workspace:FindFirstChild("World")
	local biomes = world and world:FindFirstChild("Biomes")
	local wrecks = biomes and biomes:FindFirstChild("Wrecks")
	if wrecks == nil then
		return nil
	end
	local center = Schools.list[school].center
	local best: Vector3? = nil
	local bestDistance = 170
	for _, wreck in wrecks:GetChildren() do
		local keel = wreck:FindFirstChild("Keel")
		if keel and keel:IsA("BasePart") then
			local distance = (keel.Position - center).Magnitude
			if distance < bestDistance then
				best, bestDistance = keel.Position + Vector3.new(0, 8, 0), distance
			end
		end
	end
	return best
end

-- A clear camera path for a pending shot from `t0`: its own school, else up to three
-- of the shot's others in the same water. It yields (its rays are spread over a few
-- frames), so it runs in its own thread
local function planFor(p: Pending, t0: number): StartShots.Plan?
	local shot = Start.shots[p.shot]
	local side = if rng:NextNumber() < 0.5 then 1 else -1
	local function try(school: number): StartShots.Plan?
		local landmark = if shot.landmark == "wreck" then wreckNear(school) else nil
		local plan = StartShots.plan(p.shot, school, t0, castSpread, side, landmark)
		if plan == nil then
			bad[school] = os.clock() + BAD_FOR
		end
		return plan
	end
	local plan = try(p.school)
	if plan then
		return plan
	end
	local center = Schools.list[p.school].center
	local tried = 0
	for _, school in candidatesOf(p.shot) do
		if
			school ~= p.school
			and (bad[school] or 0) <= os.clock()
			and (Schools.list[school].center - center).Magnitude < 140
		then
			tried += 1
			plan = try(school)
			if plan or tried >= 3 then
				break
			end
		end
	end
	return plan
end

-- Puts a planned shot's camera in place now, under the murk, its path starting once
-- the hold is over (`mesh` from now): moved to start then and checked again (one
-- variant's rays), else planned afresh from then, else as planned (its first check
-- covered running late by `extend`). False if it can't go.
local function begin(p: Pending): boolean
	pending = nil
	local planned = p.plan :: StartShots.Plan
	local now = Timing.clock()
	local startAt = now + timing.mesh
	local plan = StartShots.retime(planned, startAt, castWorld)
		or StartShots.plan(planned.shot, planned.school, startAt, castWorld, planned.side, planned.landmark)
	if plan == nil and startAt - planned.t0 <= timing.extend then
		plan = planned
	end
	if plan == nil then
		resting[p.shot] = os.clock() + 45
		return false
	end
	local shot = Start.shots[plan.shot]
	local name, place = StartShots.caption(shot, plan.school)
	local biome = Config.Biomes.byId[shot.biome]
	show = {
		plan = plan,
		name = name,
		place = place,
		color = if biome then biome.color else Ui.color.accent,
		guard = math.huge,
		captioned = false,
		token = p.token,
	}
	lastBiome = shot.biome
	everShown = true
	-- The dark where the shot is, straight away (BiomeController follows `viewpoint`)
	local frame = StartShots.view(plan, now)
	viewing = frame.Position
	OceanController.setDark(Biomes.darkAt(frame.Position))
	return true
end

-- The camera while a shot is on screen (CameraController.override); nil hands it back
local diveFrom: number? = nil
local function cinematic(dt: number): CFrame?
	local current = show
	if current == nil then
		viewing = nil
		return nil
	end
	local frame, subject, fov = StartShots.view(current.plan, Timing.clock())
	local position = frame.Position
	-- Never into rock: a ray from the subject to the camera pulls it in (snapping in,
	-- easing back out) for anything the plan's check couldn't see
	local away = position - subject
	local length = away.Magnitude
	if length > 0.5 then
		local want = length
		local hit = workspace:Raycast(subject, away.Unit * (length + 1.5), castParams())
		if hit then
			want = math.max(hit.Distance - 1.5, 1)
		end
		if want < current.guard then
			current.guard = want
		else
			current.guard += (want - current.guard) * (1 - math.exp(-dt * GUARD_EASE))
		end
		if current.guard < length then
			position = subject + away.Unit * current.guard
		end
	end
	local cframe = CFrame.new(position) * frame.Rotation
	-- The dive: the shot pushes on into the wash
	local push = 0
	if diveFrom then
		local t = math.clamp((os.clock() - (diveFrom :: number)) / timing.diveIn, 0, 1)
		push = t * t
		cframe *= CFrame.new(0, 0, -push * math.min(length * 0.6, 14))
	end
	CameraController.overrideFov = fov + push * 14
	workspace.CurrentCamera.Focus = CFrame.new(subject)
	viewing = cframe.Position
	return cframe
end

-- Every other GUI stays hidden under the start screen (the world shows through it
-- now): each one found enabled is switched off and switched back on at the dive
local hiddenGuis: { [LayerCollector]: boolean } = {}
local function hideOthers(playerGui: Instance, own: Instance)
	for _, child in playerGui:GetChildren() do
		if child ~= own and child:IsA("LayerCollector") and child.Enabled then
			child.Enabled = false
			hiddenGuis[child] = true
		end
	end
end

local function restoreOthers()
	for collector in hiddenGuis do
		if collector.Parent then
			collector.Enabled = true
		end
	end
	table.clear(hiddenGuis)
end

function StartController.start()
	device = (if Input.isTouch() then "touch" elseif Input.isGamepad() then "gamepad" else "keys") :: Device
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	up = true
	Input.hold("start", true)
	Input.cursorWanted = true
	MusicController.hold("hub")
	CameraController.override = cinematic
	-- Chat and the player list stay out of the way until the dive
	local hiddenCore: { Enum.CoreGuiType } = {}
	for _, coreGui in { Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList } do
		local ok, enabled = pcall(function()
			return StarterGui:GetCoreGuiEnabled(coreGui)
		end)
		if ok and enabled then
			pcall(function()
				StarterGui:SetCoreGuiEnabled(coreGui, false)
			end)
			table.insert(hiddenCore, coreGui)
		end
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "StartScreen"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Edge to edge: inside the safe area, a phone's notch strips showed the game
	-- world, cutting the scene's fish off at the seam (playtest 2026-10-09)
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 100
	gui.Parent = playerGui

	-- The backdrop -------------------------------------------------------------------

	-- The water: lighter toward the surface (and a button for taps)
	local cover = Instance.new("TextButton")
	cover.Name = "Cover"
	cover.Text = ""
	cover.AutoButtonColor = false
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = Color3.new(1, 1, 1)
	cover.BorderSizePixel = 0
	cover.Selectable = false
	cover.ZIndex = 0
	cover.Parent = gui
	gradient(
		cover,
		90,
		NumberSequence.new(0),
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(52, 140, 172)),
			ColorSequenceKeypoint.new(0.42, Color3.fromRGB(16, 68, 104)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 16, 32)),
		})
	)

	-- Light shafts from the surface
	local shafts: { { frame: Frame, base: number, phase: number } } = {}
	for i = 1, 6 do
		local shaft = Instance.new("Frame")
		shaft.Name = "Shaft"
		shaft.AnchorPoint = Vector2.new(0.5, 0)
		shaft.Position = UDim2.new(0.08 + (i - 1) * 0.17, 0, -0.1, 0)
		shaft.Size = UDim2.new(0.05 + (i % 3) * 0.025, 0, 1.15, 0)
		shaft.BackgroundColor3 = Color3.fromRGB(190, 240, 255)
		shaft.BorderSizePixel = 0
		shaft.Rotation = -14 + (i % 2) * 6
		shaft.ZIndex = 1
		gradient(
			shaft,
			90,
			NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.55),
				NumberSequenceKeypoint.new(0.55, 0.88),
				NumberSequenceKeypoint.new(1, 1),
			})
		)
		shaft.Parent = gui
		table.insert(shafts, { frame = shaft, base = shaft.Rotation, phase = i * 1.3 })
	end

	-- Marine snow and rising bubbles (the bubbles also wash over cuts and the dive)
	local specks: { { frame: Frame, x: number, y: number, speed: number, drift: number, base: number } } = {}
	for _ = 1, 46 do
		local speck = Instance.new("Frame")
		local size = math.random(2, 4)
		speck.Size = UDim2.fromOffset(size, size)
		speck.BackgroundColor3 = Color3.fromRGB(225, 245, 255)
		local base = 0.45 + math.random() * 0.4
		speck.BackgroundTransparency = base
		speck.BorderSizePixel = 0
		speck.ZIndex = 5
		Ui.corner(speck, UDim.new(1, 0))
		speck.Parent = gui
		table.insert(specks, {
			frame = speck,
			x = math.random(),
			y = math.random(),
			speed = 0.006 + math.random() * 0.014,
			drift = math.random() * 6,
			base = base,
		})
	end
	type Bubble = {
		frame: Frame,
		stroke: UIStroke,
		x: number,
		y: number,
		speed: number,
		wobble: number,
		passing: boolean, -- a wash's or the dive's: it rises away instead of coming round again
	}
	local bubbles: { Bubble } = {}
	local function bubble(x: number, y: number, speed: number, size: number, passing: boolean)
		local ring = Instance.new("Frame")
		ring.Size = UDim2.fromOffset(size, size)
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.BackgroundColor3 = Color3.fromRGB(200, 240, 255)
		ring.BackgroundTransparency = 0.85
		ring.BorderSizePixel = 0
		ring.ZIndex = if passing then 9 else 6
		Ui.corner(ring, UDim.new(1, 0))
		local stroke = Ui.stroke(ring, Color3.fromRGB(220, 250, 255), 0.35, 1.2)
		ring.Parent = gui
		table.insert(bubbles, {
			frame = ring,
			stroke = stroke,
			x = x,
			y = y,
			speed = speed,
			wobble = math.random() * 6,
			passing = passing,
		})
	end
	for _ = 1, 12 do
		bubble(
			if math.random() < 0.5 then 0.06 + math.random() * 0.2 else 0.74 + math.random() * 0.2,
			math.random(),
			0.04 + math.random() * 0.05,
			math.random(5, 12),
			false
		)
	end
	local function burst(count: number, from: number, to: number)
		for _ = 1, count do
			bubble(
				from + math.random() * (to - from),
				0.95 + math.random() * 0.25,
				0.35 + math.random() * 0.4,
				math.random(8, 22),
				true
			)
		end
	end

	-- The top and bottom edges darken, so the middle reads and the words stay clear
	local edges: { Frame } = {}
	local function edge(rotation: number, height: number, y: number)
		local shade = Instance.new("Frame")
		shade.Name = "Edge"
		shade.BackgroundColor3 = Color3.fromRGB(2, 8, 18)
		shade.BorderSizePixel = 0
		shade.Size = UDim2.fromScale(1, height)
		shade.Position = UDim2.fromScale(0, y)
		shade.ZIndex = 7
		gradient(shade, rotation, NumberSequence.new(1, 0.3))
		shade.Parent = gui
		table.insert(edges, shade)
	end
	edge(90, 0.34, 0.66)
	edge(270, 0.2, 0)

	-- The murk a cut dips through (and the dive's wash), and the letterbox bars
	local murk = Instance.new("Frame")
	murk.Name = "Murk"
	murk.Size = UDim2.fromScale(1, 1)
	murk.BackgroundColor3 = MURK
	murk.BackgroundTransparency = 1
	murk.BorderSizePixel = 0
	murk.ZIndex = 8
	murk.Parent = gui
	local bars: { Frame } = {}
	for _, top in { true, false } do
		local bar = Instance.new("Frame")
		bar.Name = if top then "BarTop" else "BarBottom"
		bar.AnchorPoint = Vector2.new(0, if top then 0 else 1)
		bar.Position = UDim2.fromScale(0, if top then 0 else 1)
		bar.Size = UDim2.fromScale(1, 0)
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BackgroundTransparency = 0.04
		bar.BorderSizePixel = 0
		bar.ZIndex = 10
		bar.Parent = gui
		table.insert(bars, bar)
		Ui.tween(bar, 1.1, { Size = UDim2.fromScale(1, timing.letterbox) }, Enum.EasingStyle.Sine)
	end

	-- The words ------------------------------------------------------------------------

	-- The title, how to play, the lower third and the prompt, on a scaled layer
	local layer = Instance.new("Frame")
	layer.Name = "Layer"
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 11
	layer.Parent = gui
	local layerScale = Instance.new("UIScale")
	layerScale.Parent = layer
	local function rescale()
		local size = workspace.CurrentCamera.ViewportSize
		local design = if Ui.isTouch() then Vector2.new(960, 540) else Vector2.new(1280, 720)
		local scale = math.clamp(math.min(size.X / design.X, size.Y / design.Y), 0.55, 1.4)
		layerScale.Scale = scale
		-- The layer is scaled about its corner, so size it to fill the screen
		layer.Size = UDim2.fromScale(1 / scale, 1 / scale)
	end
	rescale()
	local viewportChanged = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	local titleGroup = Instance.new("Frame")
	titleGroup.Name = "Title"
	titleGroup.BackgroundTransparency = 1
	titleGroup.AnchorPoint = Vector2.new(0.5, 0.5)
	titleGroup.Position = UDim2.fromScale(0.5, 0.23)
	titleGroup.Size = UDim2.fromOffset(820, 170)
	titleGroup.ZIndex = 8
	titleGroup.Parent = layer
	local titlePop = Instance.new("UIScale")
	titlePop.Scale = 0.72
	titlePop.Parent = titleGroup
	local title = Ui.label(
		titleGroup,
		"Name",
		"APEX TIDE",
		Ui.FONT_HEAVY,
		100,
		Color3.new(1, 1, 1),
		UDim2.new(1, 0, 0, 112)
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.ZIndex = 9
	title.TextTransparency = 1
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(4, 26, 44)
	titleStroke.Thickness = 4
	titleStroke.Transparency = 1
	titleStroke.Parent = title
	local shine = gradient(
		title,
		100,
		NumberSequence.new(0),
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 236, 255)),
			ColorSequenceKeypoint.new(0.42, Color3.fromRGB(226, 250, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.58, Color3.fromRGB(226, 250, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(96, 200, 236)),
		})
	)
	-- The store logo in place of the lettering once it's uploaded (Config/Textures
	-- `logo`, marketing/logo.png): the group moves down so the stacked logo clears the
	-- letterbox, and its bottom sits on the rule
	local logoId = (Config.Textures :: any).logo
	local logo: ImageLabel? = nil
	if typeof(logoId) == "number" and logoId > 0 then
		-- (phones lay out on a 960x540 design, so the logo is smaller there and sits
		-- a little lower to clear the bar)
		local touch = Ui.isTouch()
		local height = if touch then LOGO_HEIGHT_TOUCH else LOGO_HEIGHT
		titleGroup.Position = UDim2.fromScale(0.5, if touch then 0.34 else 0.32)
		local image = Instance.new("ImageLabel")
		image.Name = "Logo"
		image.BackgroundTransparency = 1
		image.Image = `rbxassetid://{logoId}`
		image.ScaleType = Enum.ScaleType.Fit
		image.AnchorPoint = Vector2.new(0.5, 1)
		image.Position = UDim2.new(0.5, 0, 0, 110)
		image.Size = UDim2.fromOffset(math.round(height * LOGO_ASPECT), height)
		image.ImageTransparency = 1
		image.ZIndex = 9
		image.Parent = titleGroup
		logo = image
	end
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.new(0.5, 0, 0, 116)
	rule.Size = UDim2.fromOffset(0, 2)
	rule.BackgroundColor3 = Ui.color.accent
	rule.BorderSizePixel = 0
	rule.ZIndex = 9
	gradient(
		rule,
		0,
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
	)
	rule.Parent = titleGroup
	local subtitle = Ui.label(
		titleGroup,
		"Subtitle",
		"EAT   ·   GROW   ·   BECOME THE APEX",
		Ui.FONT_BOLD,
		22,
		Ui.color.accent,
		UDim2.new(1, 0, 0, 28),
		UDim2.fromOffset(0, 128)
	)
	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	subtitle.ZIndex = 9
	subtitle.TextTransparency = 1
	subtitle.TextStrokeTransparency = 1

	-- How to play, in three cards over the bottom bar (owner: "needs to be clear
	-- mechanics on how to actually bite fish")
	local guide = Instance.new("Frame")
	guide.Name = "HowToPlay"
	guide.BackgroundTransparency = 1
	guide.AnchorPoint = Vector2.new(0.5, 1)
	guide.Position = UDim2.new(0.5, 0, 1 - timing.letterbox, -14)
	guide.Size = UDim2.fromOffset(780, 76)
	guide.ZIndex = 8
	guide.Parent = layer
	local guideLayout = Instance.new("UIListLayout")
	guideLayout.FillDirection = Enum.FillDirection.Horizontal
	guideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	guideLayout.Padding = UDim.new(0, 12)
	guideLayout.SortOrder = Enum.SortOrder.LayoutOrder
	guideLayout.Parent = guide
	local guideCards: { Frame } = {}
	local guideLines: { TextLabel } = {}
	local function guideCard(order: number, heading: string, line: string, color: Color3)
		local card = Ui.panel(guide, `Step{order}`, UDim2.fromOffset(250, 74), UDim2.new())
		card.LayoutOrder = order
		card.ZIndex = 8
		card.BackgroundTransparency = 1
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
			stroke.Transparency = 1
		end
		local head = Ui.label(
			card,
			"Heading",
			heading,
			Ui.FONT_HEAVY,
			16,
			color,
			UDim2.new(1, -24, 0, 20),
			UDim2.fromOffset(12, 9)
		)
		head.ZIndex = 9
		head.TextTransparency = 1
		local body = Ui.label(
			card,
			"Line",
			line,
			Ui.FONT_SEMI,
			14,
			Ui.color.text,
			UDim2.new(1, -24, 0, 36),
			UDim2.fromOffset(12, 30)
		)
		body.TextWrapped = true
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.ZIndex = 9
		body.TextTransparency = 1
		table.insert(guideCards, card)
		table.insert(guideLines, head)
		table.insert(guideLines, body)
		return body
	end
	guideCard(1, "EAT", "Swim into smaller fish to swallow them. Too big? They chase you.", Ui.color.safe)
	local biteLine = guideCard(2, "BITE", "", Ui.color.danger)
	guideCard(3, "BANK", "Swim home to your den's pool to keep what you ate.", Ui.color.haul)
	local function refreshBite()
		biteLine.Text = `{biteKey()} bites fish your size, predators and bosses. {dashKey()} dashes.`
	end
	refreshBite()

	-- The lower third: the shot's fish, and its biome and levels, over the cards' left
	local caption = Instance.new("Frame")
	caption.Name = "LowerThird"
	caption.BackgroundTransparency = 1
	caption.AnchorPoint = Vector2.new(0, 1)
	local captionAt = UDim2.new(0, 56, 1 - timing.letterbox, -(14 + 76 + 20))
	caption.Position = captionAt
	caption.Size = UDim2.fromOffset(560, 60)
	caption.ZIndex = 8
	caption.Parent = layer
	local captionBar = Instance.new("Frame")
	captionBar.Name = "Accent"
	captionBar.AnchorPoint = Vector2.new(0, 1)
	captionBar.Position = UDim2.new(0, 0, 1, -2)
	captionBar.Size = UDim2.fromOffset(4, 0)
	captionBar.BorderSizePixel = 0
	captionBar.BackgroundColor3 = Ui.color.accent
	captionBar.ZIndex = 9
	Ui.corner(captionBar, UDim.new(1, 0))
	captionBar.Parent = caption
	local captionName = Ui.label(
		caption,
		"Fish",
		"",
		Ui.FONT_HEAVY,
		32,
		Ui.color.text,
		UDim2.new(1, -18, 0, 36),
		UDim2.fromOffset(18, 0)
	)
	captionName.ZIndex = 9
	captionName.TextTransparency = 1
	captionName.TextStrokeColor3 = Color3.fromRGB(2, 12, 22)
	captionName.TextStrokeTransparency = 1
	local captionPlace = Ui.label(
		caption,
		"Place",
		"",
		Ui.FONT_BOLD,
		15,
		Ui.color.accent,
		UDim2.new(1, -18, 0, 20),
		UDim2.fromOffset(18, 38)
	)
	captionPlace.ZIndex = 9
	captionPlace.TextTransparency = 1
	captionPlace.TextStrokeColor3 = Color3.fromRGB(2, 12, 22)
	captionPlace.TextStrokeTransparency = 1
	local function showCaption(current: Show)
		captionName.Text = current.name
		captionPlace.Text = string.upper(current.place)
		captionPlace.TextColor3 = current.color:Lerp(Color3.new(1, 1, 1), 0.25)
		captionBar.BackgroundColor3 = current.color
		caption.Position = captionAt - UDim2.fromOffset(18, 0)
		Ui.tween(caption, 0.7, { Position = captionAt })
		Ui.tween(captionBar, 0.5, { Size = UDim2.fromOffset(4, 54) })
		Ui.tween(captionName, 0.6, { TextTransparency = 0, TextStrokeTransparency = 0.7 })
		task.delay(0.15, function()
			if show == current then
				Ui.tween(captionPlace, 0.6, { TextTransparency = 0, TextStrokeTransparency = 0.75 })
			end
		end)
	end
	local function hideCaption(seconds: number)
		Ui.tween(captionBar, seconds, { Size = UDim2.fromOffset(4, 0) })
		for _, label in { captionName, captionPlace } do
			Ui.tween(label, seconds, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
	end

	-- The prompt, in the bottom bar
	local prompt = Ui.label(
		layer,
		"Prompt",
		"LOADING THE REEF",
		Ui.FONT_HEAVY,
		22,
		Ui.color.muted,
		UDim2.fromOffset(600, 30)
	)
	prompt.AnchorPoint = Vector2.new(0.5, 0.5)
	prompt.Position = UDim2.fromScale(0.5, 1 - timing.letterbox / 2)
	prompt.TextXAlignment = Enum.TextXAlignment.Center
	prompt.TextStrokeTransparency = 0.6
	prompt.ZIndex = 9

	-- Entrance
	if logo then
		Ui.tween(logo, 0.9, { ImageTransparency = 0 })
	else
		Ui.tween(title, 0.9, { TextTransparency = 0 })
		Ui.tween(titleStroke, 0.9, { Transparency = 0.25 })
	end
	Ui.tween(titlePop, 1.1, { Scale = 0.86 }, Enum.EasingStyle.Back)
	task.delay(0.45, function()
		Ui.tween(rule, 0.8, { Size = UDim2.fromOffset(480, 2) })
		Ui.tween(subtitle, 0.7, { TextTransparency = 0, TextStrokeTransparency = 0.7 })
	end)
	task.delay(0.9, function()
		for i, card in guideCards do
			task.delay((i - 1) * 0.12, function()
				Ui.tween(card, 0.5, { BackgroundTransparency = 0.35 })
				local stroke = card:FindFirstChildOfClass("UIStroke")
				if stroke then
					Ui.tween(stroke, 0.5, { Transparency = 0.45 })
				end
			end)
		end
		for _, line in guideLines do
			Ui.tween(line, 0.6, { TextTransparency = 0 })
		end
	end)

	-- The backdrop's presence (0 gone, 1 there), eased: it clears onto the first shot,
	-- and comes back whenever no shot is ready
	local loading, loadingFrom, loadingTo, loadingSince, loadingSeconds = 1, 1, 1, 0, 0
	local function setLoading(on: boolean, seconds: number)
		loadingFrom, loadingTo, loadingSince, loadingSeconds =
			loading, if on then 1 else 0, os.clock(), seconds
		if seconds <= 0 then
			loading = loadingTo
		end
	end

	-- Cuts: dip out into the murk (or a bubble wash), cut while it's thickest, hold
	-- there with the camera at the new spot until it has loaded round it, then clear
	-- onto the next shot (or back onto the backdrop). The first shot is held the same
	-- way under the backdrop, then the backdrop clears.
	local cutPhase: "none" | "out" | "hold" | "in" = "none"
	local cutAt = 0
	local cutTo: Pending? = nil
	local holdArea: Area? = nil -- the new spot's parts, waited for in the hold
	local fromBackdrop = false -- the hold is under the backdrop (the first shot), not the murk
	local clearSeconds = 0 -- how long the clearing takes
	local snapIn = 0 -- frames until the water's look snaps to the new place
	local function startCut(to: Pending?)
		local shot = if to then Start.shots[to.shot] else nil
		local style = if shot then shot.cut or "murk" else "murk"
		cutPhase, cutAt, cutTo = "out", os.clock(), to
		fromBackdrop = false
		hideCaption(0.3)
		murk.BackgroundColor3 = if style == "bubbles" then WASH else MURK
		-- (fully opaque either way: the hold must hide the spot loading)
		Ui.tween(murk, timing.dipOut, { BackgroundTransparency = 0 }, Enum.EasingStyle.Sine)
		if style == "bubbles" then
			Sfx.play("Bubble", { volume = 0.22, pitch = 0.9 })
			burst(30, 0.05, 0.95)
		end
	end

	-- Whether a held cut may clear: at least `mesh` seconds with the camera at the new
	-- spot (the Terrain meshes round it), nearly all its parts in and the downloads
	-- queue nearly empty; or `holdMax` whatever is left. Back onto the backdrop there's
	-- nothing to wait for.
	local function spotReady(held: number, area: Area?, showing: boolean): boolean
		if not showing then
			return held >= timing.dipHold
		end
		if held >= timing.holdMax then
			local current = show
			warn(
				string.format(
					"[StartShots] %s cleared after %.1f s still loading (parts %s, queue %d)",
					if current then Start.shots[current.plan.shot].id else "?",
					held,
					if area then tostring(areaIn(area)) else "n/a",
					ContentProvider.RequestQueueSize
				)
			)
			return true
		end
		return held >= timing.mesh
			and (area == nil or areaIn(area))
			and ContentProvider.RequestQueueSize <= timing.queue
	end

	-- The schedule, each frame until the dive: the next shot asked for, its water
	-- waited for and its path checked, then cut to when the one on screen is done
	local function tick()
		local now = os.clock()
		if pending == nil and cutPhase ~= "out" then
			ask()
		end
		local p = pending
		if p and p.plan == nil then
			if p.arrivedAt == nil then
				if arrived(p) then
					p.arrivedAt = now
				elseif now - p.askedAt > timing.arrive then
					resting[p.shot] = now + 60
					pending = nil
				end
			elseif
				not p.planning
				and now - (p.arrivedAt :: number)
					>= (if everShown then timing.settle else timing.firstSettle)
			then
				-- Its path, checked over the next few frames for when it would show: once
				-- the one on screen ends, the dip and the hold
				local current = show
				local t0 = (
					if current
						then math.max(Timing.clock(), current.plan.t0 + current.plan.seconds) + timing.dipOut
						else Timing.clock()
				) + timing.mesh
				p.planning = true
				task.spawn(function()
					local plan = planFor(p, t0)
					if pending ~= p then
						return -- (dived in, or given up on meanwhile)
					end
					p.planning = false
					if plan then
						p.plan = plan
					else
						resting[p.shot] = os.clock() + 45
						pending = nil
					end
				end)
			end
		end
		if cutPhase == "out" then
			if now - cutAt >= timing.dipOut then
				local to = cutTo
				if to and begin(to) then
					setLoading(false, 0)
					holdArea = to.area
				else
					show = nil
					viewing = nil
					setLoading(true, 0)
					holdArea = nil
				end
				snapIn = 2
				cutPhase, cutAt, cutTo = "hold", now, nil
			end
			return
		elseif cutPhase == "hold" then
			if spotReady(now - cutAt, holdArea, show ~= nil) then
				if fromBackdrop then
					setLoading(false, timing.reveal)
					clearSeconds = timing.reveal
				else
					Ui.tween(murk, timing.dipIn, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
					clearSeconds = timing.dipIn
				end
				cutPhase, cutAt = "in", now
			end
			return
		elseif cutPhase == "in" then
			if now - cutAt >= clearSeconds then
				cutPhase = "none"
			end
			return
		end
		local current = show
		local nextUp = pending
		if current == nil then
			-- The first shot (or the next after the backdrop came back): held under the
			-- backdrop until its spot has loaded, then the backdrop clears onto it
			if nextUp and nextUp.plan then
				local area = nextUp.area
				if begin(nextUp) then
					holdArea = area
					fromBackdrop = true
					snapIn = 2
					cutPhase, cutAt = "hold", now
				end
			end
			return
		end
		local elapsed = Timing.clock() - current.plan.t0
		if not current.captioned and elapsed >= 0.5 then
			current.captioned = true
			showCaption(current)
		end
		if elapsed >= current.plan.seconds and nextUp and nextUp.plan then
			startCut(nextUp)
		elseif elapsed >= current.plan.seconds + timing.extend then
			startCut(nil)
		end
	end

	-- Motion
	local opened = os.clock()
	local promptAt: number? = nil
	local dive = 0 -- 0..1 once started: the bubbles rush up
	local leaving = false
	local lastMouseMove = os.clock()
	local mouseConnection = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			lastMouseMove = os.clock()
		end
	end)
	local renderConnection = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - opened
		if up then
			hideOthers(playerGui, gui)
		end
		if not leaving then
			tick()
		end
		if snapIn > 0 then
			snapIn -= 1
			if snapIn == 0 then
				OceanController.snap()
			end
		end
		-- The backdrop: eased in or out, and moving only while it shows
		if loadingSeconds > 0 then
			local u = math.clamp((os.clock() - loadingSince) / loadingSeconds, 0, 1)
			loading = loadingFrom + (loadingTo - loadingFrom) * u * u * (3 - 2 * u)
		end
		local shown = loading > 0.001
		cover.BackgroundTransparency = 1 - loading
		if shown then
			for _, speck in specks do
				speck.y += speck.speed * dt
				if speck.y > 1.02 then
					speck.y = -0.02
					speck.x = math.random()
				end
				speck.frame.Position =
					UDim2.fromScale(speck.x + math.sin(t * 0.3 + speck.drift) * 0.01, speck.y)
			end
		end
		for _, shaft in shafts do
			shaft.frame.Visible = shown
			shaft.frame.Rotation = shaft.base + math.sin(t * 0.25 + shaft.phase) * 3
			shaft.frame.BackgroundTransparency = 1 - (0.75 - 0.2 * math.sin(t * 0.4 + shaft.phase)) * loading
		end
		for _, speck in specks do
			speck.frame.BackgroundTransparency = 1 - (1 - speck.base) * loading
		end
		for i = #bubbles, 1, -1 do
			local b = bubbles[i]
			b.y -= b.speed * dt * (1 + dive * 6)
			if b.y < -0.05 then
				if b.passing then
					b.frame:Destroy()
					table.remove(bubbles, i)
					continue
				end
				b.y = 1.05
			end
			b.frame.Position = UDim2.fromScale(b.x + math.sin(t * 2 + b.wobble) * 0.006, b.y)
			if not b.passing then
				-- (the backdrop's own bubbles go with it)
				b.frame.BackgroundTransparency = 1 - 0.15 * loading
				b.stroke.Transparency = 1 - 0.65 * loading
			end
		end
		-- Over a shot the cursor hides once the mouse rests (the fish camera minds it
		-- otherwise)
		if show and not leaving then
			UserInputService.MouseIconEnabled = os.clock() - lastMouseMove < CURSOR_IDLE
		end
		shine.Offset = Vector2.new(((t * 0.22) % 1.6) - 0.8, 0)
		if promptAt and not leaving then
			prompt.TextTransparency = 0.15 + 0.45 * (0.5 + 0.5 * math.cos((os.clock() - promptAt) * 3.2))
		elseif not leaving then
			local dots = math.floor(t * 2.5) % 4
			prompt.Text = "LOADING THE REEF" .. string.rep(".", dots)
		end
	end)

	-- Dive in
	local inputConnection: RBXScriptConnection? = nil
	local tapConnection: RBXScriptConnection? = nil
	local inputTypeConnection: RBXScriptConnection? = nil
	local function go()
		if leaving or promptAt == nil or os.clock() - (promptAt :: number) < GRACE then
			return
		end
		leaving = true
		if inputConnection then
			inputConnection:Disconnect()
		end
		if tapConnection then
			tapConnection:Disconnect()
		end
		if inputTypeConnection then
			inputTypeConnection:Disconnect()
		end
		Sfx.play("Dash", { volume = 0.7 })
		Sfx.play("Bubbles", { volume = 0.6 })
		burst(26, 0.3, 0.7)
		Ui.tween(titlePop, 0.7, { Scale = 1.15 }, Enum.EasingStyle.Quad)
		for _, label in { title, subtitle, prompt } do
			Ui.tween(label, 0.45, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
		Ui.tween(titleStroke, 0.45, { Transparency = 1 })
		if logo then
			Ui.tween(logo, 0.45, { ImageTransparency = 1 })
		end
		Ui.tween(rule, 0.45, { BackgroundTransparency = 1 })
		hideCaption(0.35)
		for _, card in guideCards do
			Ui.tween(card, 0.35, { BackgroundTransparency = 1 })
			local stroke = card:FindFirstChildOfClass("UIStroke")
			if stroke then
				Ui.tween(stroke, 0.35, { Transparency = 1 })
			end
		end
		for _, line in guideLines do
			Ui.tween(line, 0.35, { TextTransparency = 1 })
		end
		-- The shot (if one is on) pushes on into a bubble wash...
		diveFrom = os.clock()
		task.spawn(function()
			local from = os.clock()
			while dive < 1 do
				dive = math.min(1, (os.clock() - from) / 0.9)
				RunService.RenderStepped:Wait()
			end
		end)
		cutPhase = "none"
		murk.BackgroundColor3 = WASH
		Ui.tween(murk, timing.diveIn, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad)
		task.delay(timing.diveIn, function()
			-- ...the camera goes back to the fish in its den behind it...
			show = nil
			pending = nil
			viewing = nil
			if CameraController.override == cinematic then
				CameraController.override = nil
				CameraController.overrideFov = nil
			end
			Input.consumeZoom() -- (a wheel turned on the start screen)
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				workspace.CurrentCamera.Focus = root.CFrame
			end
			MusicController.hold(nil)
			OceanController.setDark(0)
			snapIn = 2
			setLoading(false, 0)
			ClientState.request("StartDone")
			-- ...held while the den's Terrain meshes in round the camera, then clears
			task.wait(timing.diveHold)
			up = false
			Input.hold("start", false)
			Input.cursorWanted = false
			for _, coreGui in hiddenCore do
				pcall(function()
					StarterGui:SetCoreGuiEnabled(coreGui, true)
				end)
			end
			restoreOthers()
			for _, bar in bars do
				Ui.tween(bar, timing.diveOut, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Sine)
			end
			for _, shade in edges do
				Ui.tween(shade, timing.diveOut, { BackgroundTransparency = 1 })
			end
			for _, b in bubbles do
				Ui.tween(b.frame, timing.diveOut, { BackgroundTransparency = 1 })
				Ui.tween(b.stroke, timing.diveOut, { Transparency = 1 })
			end
			Ui.tween(murk, timing.diveOut, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
			done = true
			StartController.started:fire()
			local queued = waiting
			waiting = {}
			for _, fn in queued do
				task.spawn(fn)
			end
			task.delay(timing.diveOut + 0.3, function()
				renderConnection:Disconnect()
				mouseConnection:Disconnect()
				viewportChanged:Disconnect()
				gui:Destroy()
			end)
		end)
	end

	-- Any key, click, tap or controller button (not a stick nudging, nor Escape,
	-- which opens Roblox's menu)
	local function isStart(input: InputObject): boolean
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Keyboard then
			return input.KeyCode ~= Enum.KeyCode.Escape
		elseif kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 then
			return true
		elseif kind == Enum.UserInputType.Touch then
			return true
		elseif kind.Name:sub(1, 7) == "Gamepad" then
			local name = input.KeyCode.Name
			return name:sub(1, 6) == "Button" or name:sub(1, 4) == "DPad"
		end
		return false
	end
	inputConnection = UserInputService.InputBegan:Connect(function(input)
		if isStart(input) then
			go()
		end
	end)
	tapConnection = cover.Activated:Connect(go)
	inputTypeConnection = UserInputService.LastInputTypeChanged:Connect(function(kind)
		local now = deviceFromInput(kind)
		if now == nil or now == device then
			return
		end
		device = now :: Device
		refreshBite()
		if promptAt then
			prompt.Text = promptText()
		end
	end)

	-- The prompt shows once the fish is in its den (and the screen has had a moment)
	task.spawn(function()
		while not ready() and os.clock() - opened < MAX_WAIT do
			task.wait(0.2)
		end
		local left = MIN_SHOW - (os.clock() - opened)
		if left > 0 then
			task.wait(left)
		end
		prompt.Text = promptText()
		prompt.TextColor3 = Color3.new(1, 1, 1)
		promptAt = os.clock()
	end)
end

return StartController
