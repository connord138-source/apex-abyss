--!strict
-- Den doorways (owner, 2026-10-16: "Dens also still need to be substantially
-- bigger"; every den is now a private interior far outside the play area,
-- Layout.denOrigin). Swimming into a den's bubble portal on the plaza, or into the
-- way out on a den's front wall, washes the screen over with water and bubbles and
-- asks the server to move the fish (DenService checks it's really at the portal,
-- streams the place in round it and moves it); the wash clears once it's there. A
-- den nobody lives in keeps its portal shut.
--
-- Loading (owner, 2026-10-17: leaving a den, "it takes about 20 seconds for the safe
-- zone to load and you see everything else and through the floor in the meantime. If
-- we need to add a loading screen that is fine"): near a portal the far side is
-- streamed in ahead (`Prestream`), and after the move the wash stays up, as a
-- loading screen with a tip, holding the fish still, until the place round the fish
-- has really arrived (rock under it and round it, the doorway's model) or LOAD_MOST.
--
-- Your own doorway (owner, 2026-10-18: "once all the dens are used up too it would
-- be hard to see ours without having to go through each name until we see ours"):
-- only on your screen, a soft gold column of light rises from a glowing ring on the
-- paving in front of it, and YOUR DEN floats over its nameplate (boxless, like the
-- tutorial's markers), seen across the plaza. The doorway's style (Config/Dens
-- `doors`, bought in the den menu) makes it stand out to everyone too.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local HudController = require(script.Parent.HudController)
local SwimController = require(script.Parent.SwimController)

local DenDoorController = {}

local WASH = Color3.fromRGB(8, 44, 64)
local FADE_IN = 0.22
local FADE_OUT = 0.45
local WAIT_MOST = 2.5 -- seconds to wait for the move before clearing anyway
local LOAD_MOST = 25 -- seconds to wait for the place to stream in before clearing anyway
local SETTLE = 0.6 -- the place must be there this long (Terrain meshes after it arrives)
-- Coming out on the plaza, longer: Roblox first draws the newly arrived hub Terrain
-- coarse, which closes the doorway's arch over (a dark blue rock face, though rays
-- already pass), and meshes it finely only 1.5–3.6 s after arriving (PC 2026-10-18,
-- LD2); 5 s since the owner's "needs to wait a touch longer for the map to fully
-- develop" (2026-10-18), the words and a tip showing all the while
local SETTLE_HUB = 3.5
-- ...and only once nearly every part of the hub has streamed in (World.Hub
-- `PlazaParts`, Layout.hubParts) and the meshes and textures they asked for have
-- loaded (ContentProvider's queue nearly empty): the owner's "the loading screen back
-- to the hub from the den ends before the hub finishes loading" (2026-10-20), after
-- the rock-and-doorway check alone let the plaza's stalls, lamps and dressing pop in
local HUB_SHARE = 0.96
local QUEUE_LEFT = 4
local PRESTREAM_REACH = 36 -- studs from a portal at which the far side is asked for
local COOLDOWN = 1.2 -- after a move, before another portal takes the fish

local busy = false
local coolUntil = 0
local arrived = false
local shutNoteAt = 0
local prestreamAt = 0
local wash: Frame
local loading: TextLabel
local tipLabel: TextLabel

-- Whether the hub has arrived on this client: its parts (counted at most every
-- 0.3 s) and the assets they load
local countedAt, counted = 0, 0
local function hubLoaded(hub: Instance): boolean
	local want = hub:GetAttribute("PlazaParts")
	if typeof(want) ~= "number" or want <= 0 then
		return true
	end
	if os.clock() - countedAt > 0.3 then
		countedAt = os.clock()
		counted = Layout.hubParts(hub)
	end
	return counted >= want * HUB_SHARE and ContentProvider.RequestQueueSize <= QUEUE_LEFT
end

-- Whether the cavern's own rock round the plaza has finished arriving: rays from the
-- plaza's middle out to its walls at two heights and up into its vault, against the
-- Terrain only, counted every CAVERN_EVERY seconds; settled once at least
-- CAVERN_LEAST of them hit and the count hasn't changed for CAVERN_STILL seconds (the
-- tunnels and the oculus let a few through, so it waits for the count to stop rising
-- rather than for a number). The parts count and the doorway's rock didn't cover it:
-- the far walls and the vault were still streaming in when the wash cleared, and
-- filled in only as the fish swam off (owner, 2026-10-20: "the fish still has to
-- start moving once leaving the den for the hub to load")
local CAVERN_EVERY = 0.25
local CAVERN_STILL = 1.5
local CAVERN_LEAST = 0.6
local CAVERN_AROUND = 24 -- rays round each ring
local CAVERN_UP = 12 -- rays up into the vault
local cavernParams = RaycastParams.new()
cavernParams.FilterType = Enum.RaycastFilterType.Include
cavernParams.FilterDescendantsInstances = { workspace.Terrain }
cavernParams.IgnoreWater = true
local cavernAt, cavernHits, cavernSince = 0, -1, 0

local function cavernRays(): number
	local hub = Config.World.hub
	local reach = hub.radius + 60
	local hits = 0
	for _, height in { hub.paving + 18, hub.paving + 70 } do
		local origin = hub.center + Vector3.new(0, height, 0)
		for i = 0, CAVERN_AROUND - 1 do
			local a = (i + 0.5) / CAVERN_AROUND * 2 * math.pi
			if workspace:Raycast(origin, Vector3.new(math.cos(a), 0, math.sin(a)) * reach, cavernParams) then
				hits += 1
			end
		end
	end
	local origin = hub.center + Vector3.new(0, hub.paving + 30, 0)
	for i = 0, CAVERN_UP - 1 do
		local a = i / CAVERN_UP * 2 * math.pi
		local direction = Vector3.new(math.cos(a) * 0.6, 0.8, math.sin(a) * 0.6)
		if workspace:Raycast(origin, direction * (hub.height + 60), cavernParams) then
			hits += 1
		end
	end
	return hits
end

local function cavernSettled(): boolean
	local now = os.clock()
	if now - cavernAt >= CAVERN_EVERY then
		cavernAt = now
		local hits = cavernRays()
		if hits ~= cavernHits then
			cavernHits, cavernSince = hits, now
		end
	end
	return cavernHits >= (2 * CAVERN_AROUND + CAVERN_UP) * CAVERN_LEAST and now - cavernSince >= CAVERN_STILL
end

-- How much of the hub is here, 0–1, for the loading words
local function hubShare(): number
	local world = workspace:FindFirstChild("World")
	local hub = world and world:FindFirstChild("Hub")
	local want = hub and hub:GetAttribute("PlazaParts")
	if typeof(want) ~= "number" or want <= 0 then
		return 1
	end
	return math.clamp(counted / (want * HUB_SHARE), 0, 1)
end

-- Whether the place round the fish has streamed in: rock under it and round it,
-- and (for the plaza) the doorway it came out of
local function arrivedAt(door: number?): boolean
	local character = Players.LocalPlayer.Character
	local root = SwimController.root()
	if character == nil or root == nil then
		return false
	end
	if door then
		local world = workspace:FindFirstChild("World")
		local hub = world and world:FindFirstChild("Hub")
		local doorway = hub and hub:FindFirstChild(`Den{door}`)
		if doorway == nil then
			return false
		end
		-- and its lanterns' lights: the doorway and the rock round it showed dim blue
		-- for ~0.5–1 s after the wash cleared while they streamed in (PC 2026-10-17, LD1)
		if doorway:GetAttribute("Owner") ~= nil and doorway:FindFirstChildWhichIsA("Light", true) == nil then
			return false
		end
		if not hubLoaded(hub :: Instance) or not cavernSettled() then
			return false
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local origin = root.Position
	if workspace:Raycast(origin, Vector3.new(0, -90, 0), params) == nil then
		return false
	end
	local walls = 0
	for i = 0, 7 do
		local angle = i / 8 * 2 * math.pi
		if workspace:Raycast(origin, Vector3.new(math.cos(angle), 0, math.sin(angle)) * 170, params) then
			walls += 1
		end
	end
	return walls >= 2
end

-- Whether someone lives in den `index` (the doorway's model carries its owner's
-- name; if it hasn't streamed in, let the server decide)
local function lived(index: number): boolean
	local world = workspace:FindFirstChild("World")
	local hub = world and world:FindFirstChild("Hub")
	local model = hub and hub:FindFirstChild(`Den{index}`)
	if model == nil then
		return true
	end
	return model:GetAttribute("Owner") ~= nil
end

-- A few bubbles rising across the wash
local function bubbles()
	for _ = 1, 16 do
		local size = math.random(8, 22)
		local bubble = Instance.new("Frame")
		bubble.BackgroundColor3 = Color3.fromRGB(190, 240, 255)
		bubble.BackgroundTransparency = 0.55
		bubble.BorderSizePixel = 0
		bubble.AnchorPoint = Vector2.new(0.5, 0.5)
		bubble.Size = UDim2.fromOffset(size, size)
		bubble.Position = UDim2.new(math.random(), 0, 1.05, 0)
		Ui.corner(bubble, UDim.new(1, 0))
		bubble.Parent = wash
		local rise = 0.5 + math.random() * 0.5
		Ui.tween(bubble, rise, {
			Position = UDim2.new(bubble.Position.X.Scale + (math.random() - 0.5) * 0.08, 0, -0.1, 0),
			BackgroundTransparency = 0.9,
		})
		task.delay(rise + 0.05, function()
			bubble:Destroy()
		end)
	end
end

local function go(request: string, index: number?)
	busy = true
	arrived = false
	cavernAt, cavernHits, cavernSince = 0, -1, 0
	-- Leaving: the doorway on the plaza we'll come out at
	local root = SwimController.root()
	local door = if request == "LeaveDen" and root then Layout.denAt(root.Position) else nil
	Sfx.play("Bubbles", { volume = 0.6, pitch = 1.1 })
	wash.Visible = true
	loading.Text = if request == "LeaveDen" then "SWIMMING OUT TO THE HUB" else "SWIMMING INTO THE DEN"
	local tips = Config.Tutorial.tips
	tipLabel.Text = tips[math.random(1, #tips)]
	loading.TextTransparency = 1
	tipLabel.TextTransparency = 1
	bubbles()
	Ui.tween(wash, FADE_IN, { BackgroundTransparency = 0 })
	task.delay(FADE_IN, function()
		ClientState.request(request, index)
		local started = os.clock()
		while not arrived and os.clock() - started < WAIT_MOST do
			task.wait()
		end
		-- The place must be there (held still meanwhile); the words show if it takes a while
		Input.hold("den", true)
		local since: number? = nil
		local shown = false
		local settle = if door then SETTLE_HUB else SETTLE
		-- Leaving takes a while: the words and the tip are up from the start
		if door then
			shown = true
			Ui.tween(loading, 0.3, { TextTransparency = 0 })
			Ui.tween(tipLabel, 0.3, { TextTransparency = 0.15 })
		end
		started = os.clock()
		while os.clock() - started < LOAD_MOST do
			if arrivedAt(door) then
				since = since or os.clock()
				if os.clock() - (since :: number) >= settle then
					break
				end
			else
				since = nil
			end
			if not shown and os.clock() - started > 0.6 then
				shown = true
				Ui.tween(loading, 0.3, { TextTransparency = 0 })
				Ui.tween(tipLabel, 0.3, { TextTransparency = 0.15 })
			end
			if shown and math.random() < 0.02 then
				bubbles()
			end
			if door then
				loading.Text = `SWIMMING OUT TO THE HUB · {math.floor(hubShare() * 100)}%`
			end
			task.wait(0.05)
		end
		Input.hold("den", false)
		Ui.tween(loading, 0.2, { TextTransparency = 1 })
		Ui.tween(tipLabel, 0.2, { TextTransparency = 1 })
		-- A frame for the camera to cut to the new place under the wash
		task.wait(0.1)
		Sfx.play("Bubble", { volume = 0.5, pitch = 0.8 })
		bubbles()
		Ui.tween(wash, FADE_OUT, { BackgroundTransparency = 1 })
		task.delay(FADE_OUT, function()
			if not busy then
				wash.Visible = false
			end
		end)
		coolUntil = os.clock() + COOLDOWN
		busy = false
	end)
end

-- Your doorway's marker (built on this client only, in front of den `index`'s door)
local MARK = Color3.fromRGB(255, 204, 92)
local MARK_RING = 7 -- the ring on the paving: its radius
local MARK_OUT = 28 -- how far in front of the portal it lies (past the steps)
-- YOUR DEN stands on a point just over the nameplate's top (the den's `PlaqueTop`,
-- local to the door's frame; the Stone Arch's until it streams in), its arrow down
-- onto it: centred on a fixed height, the tag sat across the name on the taller
-- styles and, at its fixed pixel size, on every style from across the plaza (PC
-- 2026-10-19, DN1)
local MARK_TAG_TOP = 16.6
local MARK_TAG_OVER = 1
local markerFolder: Folder? = nil
local markerIndex = 0
local markerRing: { BasePart } = {}
local markerBeam: Beam? = nil
local markerTag: BillboardGui? = nil
local markerAnchor: BasePart? = nil

local function clearMarker()
	if markerFolder then
		markerFolder:Destroy()
	end
	markerFolder, markerBeam, markerTag, markerAnchor = nil, nil, nil, nil
	table.clear(markerRing)
	markerIndex = 0
end

local function buildMarker(index: number)
	clearMarker()
	markerIndex = index
	local frame = Layout.doorFrame(index)
	local hub = Config.World.hub
	local folder = Instance.new("Folder")
	folder.Name = "YourDenMarker"
	local function piece(name: string, size: Vector3, cframe: CFrame): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.CFrame = cframe
		p.Color = MARK
		p.Material = Enum.Material.Neon
		p.Parent = folder
		return p
	end
	-- A ring of light on the paving in front of the steps
	local ground = frame * CFrame.new(0, hub.paving - frame.Position.Y + 0.12, -MARK_OUT)
	local level = CFrame.new(ground.Position) * (frame - frame.Position)
	local count = 24
	for k = 1, count do
		local a = k / count * 2 * math.pi
		local segment = piece(
			"Ring",
			Vector3.new(2 * MARK_RING * math.sin(math.pi / count) + 0.1, 0.12, 0.5),
			level * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -MARK_RING)
		)
		segment.Transparency = 0.3
		table.insert(markerRing, segment)
	end
	-- A soft column of light rising from it
	local base = piece("Base", Vector3.one * 0.4, level)
	base.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = MARK
	light.Range = 22
	light.Brightness = 1.2
	light.Parent = base
	local foot = Instance.new("Attachment")
	foot.Parent = base
	local top = Instance.new("Attachment")
	top.Parent = base
	top.Position = Vector3.new(0, 42, 0)
	local beam = Instance.new("Beam")
	beam.Attachment0 = foot
	beam.Attachment1 = top
	beam.FaceCamera = true
	beam.Width0 = MARK_RING * 1.5
	beam.Width1 = 3
	beam.Color = ColorSequence.new(MARK)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.5, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Segments = 1
	beam.Parent = base
	markerBeam = beam
	-- YOUR DEN over the nameplate: thin text and a short line, breathing slowly
	local anchor = piece("Tag", Vector3.one, frame * CFrame.new(0, MARK_TAG_TOP + MARK_TAG_OVER, -12))
	anchor.Transparency = 1
	markerAnchor = anchor
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(180, 46)
	tag.SizeOffset = Vector2.new(0, 0.5)
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.MaxDistance = 420
	tag.Adornee = anchor
	tag.Parent = anchor
	local label = Ui.label(tag, "Text", "YOUR DEN", Ui.FONT_HEAVY, 18, MARK, UDim2.new(1, 0, 0, 24))
	label.TextXAlignment = Enum.TextXAlignment.Center
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(40, 26, 6)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = label
	local line = Instance.new("Frame")
	line.Name = "Line"
	line.BackgroundColor3 = MARK
	line.BorderSizePixel = 0
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.new(0.5, 0, 0, 27)
	line.Size = UDim2.fromOffset(40, 2)
	line.Parent = tag
	local arrow = Ui.label(
		tag,
		"Arrow",
		"▼",
		Ui.FONT_HEAVY,
		11,
		MARK,
		UDim2.new(1, 0, 0, 14),
		UDim2.fromOffset(0, 31)
	)
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	markerTag = tag
	folder.Parent = workspace
	markerFolder = folder
end

-- Shows your doorway's marker while your fish is out of its den (and not in Build
-- mode); YOUR DEN steps aside while the tutorial shows its own
local function updateMarker()
	local s = ClientState.current
	local index = if s and typeof(s.denIndex) == "number" then s.denIndex else 0
	local root = SwimController.root()
	local out = root ~= nil and Layout.denAt(root.Position) == nil
	if index <= 0 or not out then
		if markerFolder then
			clearMarker()
		end
		return
	end
	if markerIndex ~= index or markerFolder == nil or markerFolder.Parent == nil then
		buildMarker(index)
	end
	-- breathing
	local wave = 0.5 + 0.5 * math.sin(os.clock() * 2.2)
	for _, segment in markerRing do
		segment.Transparency = 0.15 + 0.4 * wave
	end
	local beam = markerBeam
	if beam then
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45 + 0.2 * wave),
			NumberSequenceKeypoint.new(0.5, 0.78 + 0.1 * wave),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
	local anchor = markerAnchor
	if anchor then
		-- over this door's nameplate, whichever style built it
		local world = workspace:FindFirstChild("World")
		local hub = world and world:FindFirstChild("Hub")
		local den = hub and hub:FindFirstChild(`Den{index}`)
		local top = den and den:GetAttribute("PlaqueTop")
		local y = (if typeof(top) == "number" then top else MARK_TAG_TOP) + MARK_TAG_OVER
		local at = Layout.doorFrame(index) * CFrame.new(0, y, -12)
		if (anchor.Position - at.Position).Magnitude > 0.05 then
			anchor.CFrame = at
		end
	end
	local tag = markerTag
	if tag then
		-- (through the rock only from inside the hub: from the shallows it pointed
		-- into the seamount)
		local tutorial = workspace:FindFirstChild("TutorialMarkers")
		tag.Enabled = root ~= nil
			and Layout.inHub(root.Position)
			and not (tutorial and #tutorial:GetChildren() > 0)
		local label = tag:FindFirstChild("Text") :: TextLabel?
		if label then
			label.TextTransparency = 0.05 + 0.3 * wave
		end
	end
end

local markerClock = 0

local function step()
	if os.clock() - markerClock > 0.05 then
		markerClock = os.clock()
		updateMarker()
	end
	if busy or Input.locked or os.clock() < coolUntil then
		return
	end
	local root = SwimController.root()
	if root == nil then
		return
	end
	local position = root.Position
	-- Near a portal: have the far side streamed in before we swim through
	if os.clock() > prestreamAt then
		local den = Layout.denAt(position)
		local near = if den
			then (position - Layout.exitFrame(den).Position).Magnitude <= PRESTREAM_REACH
			else false
		if not near and den == nil then
			for i = 1, Layout.DEN_COUNT do
				if (position - Layout.doorFrame(i).Position).Magnitude <= PRESTREAM_REACH and lived(i) then
					near = true
					break
				end
			end
		end
		if near then
			prestreamAt = os.clock() + 8
			ClientState.request("Prestream")
		end
	end
	local door = Layout.doorAt(position)
	if door then
		if lived(door) then
			go("EnterDen", door)
		elseif os.clock() > shutNoteAt then
			shutNoteAt = os.clock() + 4
			HudController.toast("No one lives in this den yet", "info")
		end
		return
	end
	if Layout.exitAt(position) then
		go("LeaveDen", nil)
	end
end

function DenDoorController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Ui.screen("DenDoor", playerGui, 40)
	wash = Instance.new("Frame")
	wash.Name = "Wash"
	wash.BackgroundColor3 = WASH
	wash.BackgroundTransparency = 1
	wash.BorderSizePixel = 0
	wash.Size = UDim2.fromScale(1, 1)
	wash.Visible = false
	wash.Parent = gui
	loading = Ui.label(
		wash,
		"Loading",
		"",
		Ui.FONT_HEAVY,
		26,
		Ui.color.text,
		UDim2.new(1, -40, 0, 34),
		UDim2.new(0.5, 0, 0.5, -30)
	)
	loading.AnchorPoint = Vector2.new(0.5, 0.5)
	loading.TextXAlignment = Enum.TextXAlignment.Center
	loading.TextTransparency = 1
	tipLabel = Ui.label(
		wash,
		"Tip",
		"",
		Ui.FONT_SEMI,
		17,
		Ui.color.muted,
		UDim2.new(0.8, 0, 0, 48),
		UDim2.new(0.5, 0, 0.5, 16)
	)
	tipLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	tipLabel.TextXAlignment = Enum.TextXAlignment.Center
	tipLabel.TextWrapped = true
	tipLabel.TextTransparency = 1
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local teleport = remotes:WaitForChild("Teleport") :: RemoteEvent
	teleport.OnClientEvent:Connect(function()
		arrived = true
	end)
	RunService.Heartbeat:Connect(step)
end

return DenDoorController
