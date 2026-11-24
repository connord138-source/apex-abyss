--!strict
-- The tutorial on this client, directed (owner, 2026-10-12: "Controls need to be
-- more obvious during the tutorial and tutorial needs to be more directed instead
-- of just a floating Ui. Alt key is used to pull up the mouse to click the ui
-- screens and that needs to be told so people arent guessing"):
--   * a card under the wallet with the current step, its progress, and the keys
--     the step needs drawn as key caps for this device (Config/Tutorial `controls`)
--   * a trail of lights from the fish to the step's target (the nearest exit, the
--     nearest food, your den's pool, the nearest shell; `guide`), with the distance
--     and an arrow on the card, so there's always somewhere to swim
--   * markers that point the way (the hub's exits breathe, BANK HERE at the pool)
--   * a cursor tip: how to free the mouse for buttons and menus
--   * a celebration when it's done
-- Since 2026-10-18 it walks a whole first loop (owner: "show them how to complete a
-- full cycle of hunting, storing, spinning, etc."): the trail also leads to the
-- Treasure Wheel's red button, the Haul step counts the Haul against its target in
-- kg, and the steps done at the HUD (ROLL, the item bar's Kelp Wrap, INDEX) get a
-- ring breathing round that button instead of a trail (`point`).
-- Since 2026-11-20 (docs/GAMEPLAN.md round 1 items 7 to 9): a ring marks the very
-- fish, shrimp or shell the trail leads to; from the hub or a den the trail to food
-- or shells goes by the way out and a tunnel, never into the rock; and a phone shows
-- the step as a strip at the top of the screen instead of the card (which lay under
-- the steering thumb), with the HUD's button row put away until the INDEX is met.
-- The server counts the steps (TutorialService).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.Tutorial)
local Format = require(ReplicatedStorage.Shared.Format)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Size = require(ReplicatedStorage.Shared.Size)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local ForageController = require(script.Parent.ForageController)
local MenuController = require(script.Parent.MenuController)
local SchoolController = require(script.Parent.SchoolController)
local ShellController = require(script.Parent.ShellController)
local StartController = require(script.Parent.StartController)
local SwimController = require(script.Parent.SwimController)

local Tutorial = Config.Tutorial
local hub = Config.World.hub

local TutorialController = {}

local gui: ScreenGui
local panel: Frame
local header: TextLabel
local titleText: TextLabel
local stepText: TextLabel
local countText: TextLabel
local fill: Frame
local capsRow: Frame
local guideLine: TextLabel
local guideArrow: TextLabel
local tipLine: TextLabel
-- A phone's step: a strip at the top of the screen (buildStrip)
local strip: Frame
local stripStep: TextLabel
local stripTitle: TextLabel
local stripCount: TextLabel
local stripLine: TextLabel
local stripGuide: TextLabel
local stripArrow: TextLabel
local stripFill: Frame
local showing = false -- the tutorial is up: its card, or the strip on a phone
local markers: Folder
local trail: Folder
local shownStep = 0
local shownDevice = "" -- the device its key caps were drawn for
local shownMarker: string? = nil
local wasDone: boolean? = nil
local target: Vector3? = nil
local targetFish: number? = nil -- the prey fish the trail leads to (its index), if it is one
local guideKind: string? = nil
local nextSearch = 0
local nextTidy = 0 -- when the phone's strip and button row are next looked at

local pointRing: Frame? = nil -- the ring round the HUD button a step needs
local pointKind: string? = nil
local pointedAt: GuiObject? = nil

local TRAIL_DOTS = 9 -- lights between the fish and the target
local TRAIL_NEAR = 14 -- studs: the trail goes out this close to the target
local TRAIL_SPAN = 90 -- studs: the trail reaches this far ahead at most
-- A bead this close to the camera fades out. The trail to a way out behind you runs back
-- along the camera's line, and a fish from about LV 5 sits further from the camera than
-- the trail's start, so a bead went right past the lens and filled the screen with a huge
-- cyan blob (PC 2026-11-05)
local BEAD_GONE_WITHIN = 3 -- studs from the camera: not drawn
local BEAD_FULL_PAST = 8 -- studs from the camera: drawn in full
local SEARCH_RANGE = 420 -- studs: how far the guide looks for food or a shell
-- The ring on the trail's target: its width is `RING_STUDS` of the world at the
-- target's distance, within these shares of the screen's height, and none past
-- `RING_REACH` studs from the camera
local RING_STUDS = 3.2
local RING_SMALLEST = 0.055
local RING_BIGGEST = 0.16
local RING_REACH = 220
-- Bigger and bolder (owner, 2026-10-20: "tutorial needs to be more prominent its a
-- bit small"): a headline with the goal, larger text, and the card drawn at
-- CARD_SCALE (a little less on a phone's smaller screen); each step also opens with
-- a banner in the middle of the screen (stepBanner)
local PANEL_HEIGHT = 214
local PANEL_HEIGHT_TOUCH = 196 -- no cursor tip on a phone
local CARD_SCALE = 1.2
local CARD_SCALE_TOUCH = 1.05

-- A step done the moment it began (the Haul already full from the steps before:
-- PC 2026-10-19, TU1) would flash past unseen, so the card still shows it, done,
-- with a line saying what happened, before the next one
local INSTANT = 1 -- seconds: a step done this soon after its card showed
local RECAP_SECONDS = 2.5
local liveStep = 0 -- the server's step, as last seen
local liveShownAt: number? = nil -- when the card began showing it (nil: not yet)
local recaps: { number } = {} -- steps waiting to be shown done
local recapStep: number? = nil -- the step the card shows done right now
local recapUntil = 0
local shownRecap = false -- the card shows `shownStep` done

-- A floating label in the world, visible through walls: thin text and a short
-- line, breathing slowly (owner, 2026-10-08: the old chips were "a flashing blue
-- box ... in black"; markers must be subtle)
local function marker(position: Vector3, text: string)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = markers
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(160, 30)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 240
	billboard.Adornee = anchor
	billboard.Parent = anchor
	local label = Ui.label(billboard, "Text", text, Ui.FONT_BOLD, 15, Ui.color.accent, UDim2.new(1, 0, 0, 22))
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTransparency = 0.1
	local line = Instance.new("Frame")
	line.Name = "Line"
	line.BackgroundColor3 = Ui.color.accent
	line.BorderSizePixel = 0
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.new(0.5, 0, 0, 24)
	line.Size = UDim2.fromOffset(36, 2)
	line.Parent = billboard
	local info = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(label, info, { TextTransparency = 0.5 }):Play()
	TweenService:Create(line, info, { BackgroundTransparency = 0.5 }):Play()
end

-- The exits are built into the rock (lintels and lanterns, WorldService). When the
-- tutorial asks for the way out, the lanterns breathe brighter instead of a chip.
type Pulsed = { light: PointLight, brightness: number, range: number, part: BasePart, transparency: number }
local pulses: { Tween } = {}
local pulsed: { Pulsed } = {}

local function stopPulses()
	for _, tween in pulses do
		tween:Cancel()
	end
	for _, entry in pulsed do
		entry.light.Brightness = entry.brightness
		entry.light.Range = entry.range
		entry.part.Transparency = entry.transparency
	end
	table.clear(pulses)
	table.clear(pulsed)
end

local function pulseExits()
	local info = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	for _, part in CollectionService:GetTagged("ExitLight") do
		local light = if part:IsA("BasePart") then part:FindFirstChildOfClass("PointLight") else nil
		if part:IsA("BasePart") and light then
			table.insert(pulsed, {
				light = light,
				brightness = light.Brightness,
				range = light.Range,
				part = part,
				transparency = part.Transparency,
			})
			local brighter = TweenService:Create(
				light,
				info,
				{ Brightness = light.Brightness * 3.2, Range = light.Range * 1.5 }
			)
			local solid = TweenService:Create(part, info, { Transparency = 0 })
			brighter:Play()
			solid:Play()
			table.insert(pulses, brighter)
			table.insert(pulses, solid)
		end
	end
end

local function showMarkers(kind: string?, s: { [string]: any })
	if kind == shownMarker then
		return
	end
	shownMarker = kind
	markers:ClearAllChildren()
	stopPulses()
	if kind == "exits" then
		pulseExits()
	elseif kind == "den" and typeof(s.denIndex) == "number" and s.denIndex > 0 then
		-- (state.denIndex: `den` is the den's record since the den bases landed, so
		-- the BANK HERE marker had stopped showing)
		marker(Layout.poolPosition(s.denIndex) + Vector3.new(0, 4, 0), "BANK HERE")
		-- (the den is through its doorway on the plaza: Layout.doorFrame)
		marker(Layout.doorFrame(s.denIndex).Position + Vector3.new(0, 12, 0), "YOUR DEN")
	end
end

-- The hub's exits: the four tunnel mouths (just inside the wall, at swimming
-- height) and the hole in the roof
local exits: { Vector3 } = {}
for segment = 1, hub.segments do
	if Layout.segmentKind(segment) == "tunnel" then
		local angle = Layout.segmentAngle(segment)
		table.insert(
			exits,
			hub.center
				+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * (hub.radius + hub.wallThickness + 6)
				+ Vector3.new(0, hub.denFloorY + hub.tunnelHeight * 0.4, 0)
		)
	end
end
table.insert(exits, hub.center + Vector3.new(0, hub.height + 6, 0))

local function nearestExit(from: Vector3): Vector3?
	-- In a den, the way out is its portal on the front wall
	local den = Layout.denAt(from)
	if den then
		return Layout.exitFrame(den).Position
	end
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, exit in exits do
		local distance = (exit - from).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			best = exit
		end
	end
	return best
end

-- From out in the sea, the way into the hub toward `goal`: out on the sand, the
-- outer end of the tunnel that makes the shortest trip; inside a tunnel, its inner
-- end; so the trail home never runs into the seamount's rock (a new fish's first
-- dive starts out there, FishService). Nil once in the cavern or a den.
local TUNNEL_CONE = 0.2 -- radians either side of a tunnel's line that count as in it
local TUNNEL_TOP = hub.denFloorY + hub.tunnelHeight + hub.tunnelArch + 8
local function intoHub(from: Vector3, goal: Vector3): Vector3?
	if Layout.denAt(from) then
		return nil
	end
	local offset = from - hub.center
	local flat = Vector2.new(offset.X, offset.Z).Magnitude
	if flat < hub.radius - 2 and offset.Y < hub.height then
		return nil
	end
	local heading = math.atan2(offset.Z, offset.X)
	local best: Vector3? = nil
	local bestCost = math.huge
	for _, angle in Layout.tunnelAngles do
		local inner, outer = Layout.tunnelEnds(angle)
		local gap = math.abs((heading - angle + math.pi) % (2 * math.pi) - math.pi)
		if flat < Layout.MOUTH + 14 and gap < TUNNEL_CONE and offset.Y < TUNNEL_TOP then
			return inner
		end
		local cost = (outer - from).Magnitude + (inner - outer).Magnitude + (goal - inner).Magnitude
		if cost < bestCost then
			best, bestCost = outer, cost
		end
	end
	return best
end

-- The other way: from the hub, the way out to sea toward `goal` (nil: the nearest
-- way out). In the cavern, the inner end of the tunnel that makes the shortest trip;
-- at that end or inside a tunnel, its outer end on the sand; so a trail to food or a
-- shell never runs into the cavern's wall (the Haul step after a trip home, the Shells
-- step from the plaza). Nil out in the sea. A den's way out is the caller's.
local INNER_NEAR = 24 -- studs from a tunnel's inner end: on to its outer end
local function outOfHub(from: Vector3, goal: Vector3?): Vector3?
	local offset = from - hub.center
	local flat = Vector2.new(offset.X, offset.Z).Magnitude
	-- (the tubes end 10 short of MOUTH: past that a fish is out on the sand)
	if offset.Y >= hub.height or flat >= Layout.MOUTH - 10 then
		return nil
	end
	local heading = math.atan2(offset.Z, offset.X)
	local best: Vector3? = nil
	local bestCost = math.huge
	for _, angle in Layout.tunnelAngles do
		local inner, outer = Layout.tunnelEnds(angle)
		local gap = math.abs((heading - angle + math.pi) % (2 * math.pi) - math.pi)
		local toInner = (inner - from).Magnitude
		if
			toInner < INNER_NEAR
			or (flat >= hub.radius - 2 and gap < TUNNEL_CONE and offset.Y < TUNNEL_TOP)
		then
			return outer
		end
		local cost = toInner + (outer - inner).Magnitude + (if goal then (goal - outer).Magnitude else 0)
		if cost < bestCost then
			best, bestCost = inner, cost
		end
	end
	-- (past the cavern's wall and in no tunnel: out on the seamount's flank)
	if flat >= hub.radius + hub.wallThickness then
		return nil
	end
	return best
end

-- Where the step's trail leads right now. `viaWhat` names a place on the way there (a
-- tunnel, a den's way out) while the trail leads to that first; `targetFish` is the
-- prey fish it leads to, when it is one.
local viaWhat: string? = nil
local function findTarget(kind: string?, from: Vector3, s: { [string]: any }): Vector3?
	viaWhat = nil
	targetFish = nil
	if kind == "exits" then
		return nearestExit(from)
	elseif kind == "den" then
		if typeof(s.denIndex) ~= "number" or s.denIndex <= 0 then
			return nil
		end
		-- Into the hub, through the doorway, then to the pool inside
		if Layout.denAt(from) == s.denIndex then
			return Layout.poolPosition(s.denIndex) + Vector3.new(0, 2, 0)
		end
		local door = Layout.doorFrame(s.denIndex).Position
		local way = intoHub(from, door)
		if way then
			viaWhat = "the tunnel into the hub"
		end
		return way or door
	elseif kind == "food" or kind == "shells" then
		-- From a den the sea is a doorway and a tunnel away: its way out first
		local den = Layout.denAt(from)
		if den then
			viaWhat = "your den's way out"
			return Layout.exitFrame(den).Position
		end
		local goal: Vector3? = nil
		local fishIndex: number? = nil
		if kind == "food" then
			-- (never Medkelp: it feeds nothing and counts for nothing, ForageController)
			local fish, index =
				SchoolController.nearestEdibleFish(from, SwimController.length(), SEARCH_RANGE)
			local food = ForageController.nearest(from, SEARCH_RANGE, nil, true)
			if fish and (food == nil or (fish - from).Magnitude <= (food - from).Magnitude + 20) then
				goal, fishIndex = fish, index
			else
				goal = food
			end
		else
			goal = ShellController.nearest(from, SEARCH_RANGE)
		end
		-- From the hub, by a tunnel
		local way = outOfHub(from, goal)
		if way then
			viaWhat = "the tunnel out to sea"
			return way
		end
		targetFish = fishIndex
		return goal
	elseif kind == "wheel" then
		-- The Treasure Wheel's red button (WheelService publishes where it is); from a
		-- den, through its way out first
		local den = Layout.denAt(from)
		if den then
			viaWhat = "your den's way out"
			return Layout.exitFrame(den).Position
		end
		local wheelState = ReplicatedStorage:FindFirstChild("WheelState")
		local at = if wheelState then wheelState:GetAttribute("ButtonPosition") else nil
		if typeof(at) ~= "Vector3" then
			return nil
		end
		local way = intoHub(from, at)
		if way then
			viaWhat = "the tunnel into the hub"
		end
		return way or at
	end
	return nil
end

-- The HUD button a `point` step needs (ROLL and INDEX on the wallet's row, the item
-- bar's Kelp Wrap), while it's on screen
local function pointTarget(kind: string): GuiObject?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end
	local found: Instance? = nil
	if kind == "Roll" or kind == "Index" then
		local wallet = playerGui:FindFirstChild("Wallet")
		local buttons = wallet and wallet:FindFirstChild("Buttons", true)
		found = buttons and buttons:FindFirstChild(kind)
	elseif kind == "Wrap" then
		local bar = playerGui:FindFirstChild("ItemBar")
		found = bar and bar:FindFirstChild("KelpWrap", true)
	end
	if found and found:IsA("GuiObject") and found.Visible then
		return found
	end
	return nil
end

-- A ring of light breathing round a HUD button, with a small arrow over it
local function ringRound(target: GuiObject)
	if pointRing then
		pointRing:Destroy()
	end
	local ring = Instance.new("Frame")
	ring.Name = "TutorialRing"
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.new(1, 14, 1, 14)
	ring.ZIndex = 20
	Ui.corner(ring, UDim.new(0, 14))
	local stroke = Ui.stroke(ring, Ui.color.haul, 0, 3)
	local arrow = Ui.label(
		ring,
		"Arrow",
		"▼",
		Ui.FONT_HEAVY,
		18,
		Ui.color.haul,
		UDim2.fromOffset(24, 20),
		UDim2.new(0.5, -12, 0, -24)
	)
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	arrow.TextStrokeTransparency = 0.4
	arrow.ZIndex = 20
	local info = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(stroke, info, { Transparency = 0.6 }):Play()
	TweenService:Create(arrow, info, { Position = UDim2.new(0.5, -12, 0, -32) }):Play()
	ring.Parent = target
	pointRing = ring
	pointedAt = target
end

local function clearPoint()
	if pointRing then
		pointRing:Destroy()
	end
	pointRing = nil
	pointedAt = nil
end

-- The trail of lights: small glowing beads on a straight line from the fish to the
-- target, flowing toward it; they ride along as the fish swims
local beads: { BasePart } = {}
local beadFrames: { CFrame } = {}

local function buildTrail()
	for i = 1, TRAIL_DOTS do
		local bead = Instance.new("Part")
		bead.Name = `Bead{i}`
		bead.Shape = Enum.PartType.Ball
		bead.Size = Vector3.new(1.1, 1.1, 1.1)
		bead.Material = Enum.Material.Neon
		bead.Color = Ui.color.accent
		bead.Anchored = true
		bead.CanCollide = false
		bead.CanQuery = false
		bead.CanTouch = false
		bead.CastShadow = false
		bead.Transparency = 1
		bead.Parent = trail
		beads[i] = bead
		beadFrames[i] = CFrame.new()
	end
end

local function hideTrail()
	for _, bead in beads do
		if bead.Transparency < 1 then
			bead.Transparency = 1
		end
	end
end

local function drawTrail(from: Vector3, to: Vector3, t: number)
	local offset = to - from
	local distance = offset.Magnitude
	if distance <= TRAIL_NEAR + 4 then
		hideTrail()
		return
	end
	local direction = offset.Unit
	local span = math.min(distance - TRAIL_NEAR, TRAIL_SPAN)
	local start = from + direction * 6
	local flow = (t * 0.9) % 1 -- the beads slide toward the target
	local lens = workspace.CurrentCamera.CFrame.Position
	for i, bead in beads do
		local k = ((i - 1) + flow) / TRAIL_DOTS
		local position = start + direction * (span * k)
		local fade = math.sin(k * math.pi) -- bright in the middle, fading at both ends
		local clear = math.clamp(
			((position - lens).Magnitude - BEAD_GONE_WITHIN) / (BEAD_FULL_PAST - BEAD_GONE_WITHIN),
			0,
			1
		)
		bead.Transparency = 1 - (0.85 - 0.6 * (1 - fade)) * clear
		local size = 0.8 + 0.5 * fade
		bead.Size = Vector3.new(size, size, size)
		beadFrames[i] = CFrame.new(position)
	end
	workspace:BulkMoveTo(beads, beadFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- A ring on the very thing the trail leads to (docs/GAMEPLAN.md round 1 item 7). The
-- trail goes out within TRAIL_NEAR of its target, which in the shallows is nearly
-- always (food is everywhere at spawn), and nothing said which of the fish in view was
-- the one small enough to swallow. A thin ring in the trail's colour sits on the fish,
-- shrimp, starfish or shell itself, drawn over the water's haze; a fish is followed as
-- it swims (SchoolController.fishPosition).
local ringPart: Part
local ringGui: BillboardGui
local ringStroke: UIStroke

local function buildRing()
	ringPart = Instance.new("Part")
	ringPart.Name = "Target"
	ringPart.Anchored = true
	ringPart.CanCollide = false
	ringPart.CanQuery = false
	ringPart.CanTouch = false
	ringPart.CastShadow = false
	ringPart.Transparency = 1
	ringPart.Size = Vector3.one
	ringPart.Parent = trail
	ringGui = Instance.new("BillboardGui")
	ringGui.Name = "Ring"
	ringGui.AlwaysOnTop = true
	ringGui.LightInfluence = 0
	ringGui.Size = UDim2.fromOffset(60, 60)
	ringGui.Adornee = ringPart
	ringGui.Enabled = false
	ringGui.Parent = ringPart
	local circle = Instance.new("Frame")
	circle.Name = "Circle"
	circle.BackgroundTransparency = 1
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.5)
	circle.Size = UDim2.new(1, -8, 1, -8)
	Ui.corner(circle, UDim.new(1, 0))
	ringStroke = Ui.stroke(circle, Ui.color.accent, 0.2, 2.5)
	circle.Parent = ringGui
end

local function hideRing()
	if ringGui.Enabled then
		ringGui.Enabled = false
	end
end

local function drawRing(at: Vector3, t: number)
	local camera = workspace.CurrentCamera
	local away = (at - camera.CFrame.Position).Magnitude
	if away > RING_REACH then
		hideRing()
		return
	end
	ringPart.CFrame = CFrame.new(at)
	-- (a stud at `away` is this many pixels tall: the lens's half height over its tangent)
	local height = camera.ViewportSize.Y
	local perStud = height / (2 * math.tan(math.rad(camera.FieldOfView) / 2) * math.max(away, 1))
	local pixels = math.clamp(RING_STUDS * perStud, RING_SMALLEST * height, RING_BIGGEST * height)
	ringGui.Size = UDim2.fromOffset(pixels, pixels)
	ringStroke.Transparency = 0.2 + 0.3 * (0.5 + 0.5 * math.sin(t * 4))
	if not ringGui.Enabled then
		ringGui.Enabled = true
	end
end

-- The trail and the ring, both away
local function hideGuide()
	hideTrail()
	hideRing()
end

local function celebrate()
	-- A menu may be open (the INDEX was the last step until 2026-11-20): the banner
	-- waits until it's read and closed
	local waited = task.wait(0.3)
	while MenuController.isOpen() and waited < 90 do
		waited += task.wait(0.2)
	end
	-- Then it takes its turn on the middle of the screen: after the bank's growth
	-- sequence or a skin unlock already up, and one that comes in meanwhile waits for
	-- it (they drew on top of each other, PC 2026-10-19, UN1)
	Ui.stageBanner("tutorial", 5, 0.65, function()
		Ui.clearTideBanner()
		local holder = Instance.new("Frame")
		holder.Name = "TutorialBanner"
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.32)
		holder.Size = UDim2.fromOffset(700, 110)
		holder.BackgroundTransparency = 1
		local scale = Instance.new("UIScale")
		scale.Scale = 0.6
		scale.Parent = holder
		local title = Ui.label(
			holder,
			"Title",
			"TUTORIAL COMPLETE",
			Ui.FONT_HEAVY,
			46,
			Ui.color.haul,
			UDim2.new(1, 0, 0, 52)
		)
		title.TextXAlignment = Enum.TextXAlignment.Center
		title.TextStrokeTransparency = 0.5
		local cuda = Config.Species.byId.Cuda
		local sub = Ui.label(
			holder,
			"Sub",
			`INDEX shows what's next · Nibbler LV {cuda.unlock.level or 15} unlocks the {cuda.name}`,
			Ui.FONT_BOLD,
			20,
			Ui.color.text,
			UDim2.new(1, 0, 0, 26),
			UDim2.fromOffset(0, 58)
		)
		sub.TextXAlignment = Enum.TextXAlignment.Center
		sub.TextStrokeTransparency = 0.6
		holder.Parent = gui
		Ui.tween(scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		return function(quick: boolean)
			local seconds = if quick then 0.2 else 0.6
			Ui.tween(title, seconds, { TextTransparency = 1, TextStrokeTransparency = 1 })
			Ui.tween(sub, seconds, { TextTransparency = 1, TextStrokeTransparency = 1 })
			task.delay(seconds + 0.05, function()
				holder:Destroy()
			end)
		end
	end)
end

-- Which kind of controls this device shows
local function device(): string
	return if Input.usingTouch() then "touch" elseif Input.isGamepad() then "pad" else "keys"
end

-- The key for a control on this device, or nil when it has none
local function keyFor(control: TutorialConfig.Control): string?
	if Input.usingTouch() then
		return control.touch
	elseif Input.isGamepad() then
		return control.pad
	end
	return control.keys
end

-- A phone's step (docs/GAMEPLAN.md round 1 item 9). The card sat in the lower left,
-- under the thumb that steers, its text about 10 px tall on an iPhone. On a phone the
-- step is a strip at the top of the screen instead, in the tide chip's place
-- (TideController hides its chip meanwhile, and the SAFE ZONE chip moves under the
-- strip: Ui.stripBottom, Ui.topBottom): the goal big, one short line (Config/Tutorial
-- `phone`), the count and the way.
local STRIP_SIZE = Vector2.new(460, 90)
local STRIP_TOP = 8

local function buildStrip()
	strip = Ui.panel(
		gui,
		"Strip",
		UDim2.fromOffset(STRIP_SIZE.X, STRIP_SIZE.Y),
		UDim2.new(0.5, 0, 0, STRIP_TOP),
		Vector2.new(0.5, 0)
	)
	local stroke = strip:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Ui.color.accent
		stroke.Transparency = 0.5
	end
	stripTitle = Ui.label(
		strip,
		"Title",
		"",
		Ui.FONT_HEAVY,
		26,
		Ui.color.text,
		UDim2.new(1, -28, 0, 30),
		UDim2.fromOffset(14, 6)
	)
	stripTitle.TextXAlignment = Enum.TextXAlignment.Center
	stripTitle.TextScaled = true
	local titleSize = Instance.new("UITextSizeConstraint")
	titleSize.MaxTextSize = 26
	titleSize.Parent = stripTitle
	stripStep = Ui.label(
		strip,
		"Step",
		"",
		Ui.FONT_BOLD,
		11,
		Ui.color.muted,
		UDim2.fromOffset(40, 12),
		UDim2.new(1, -50, 0, 6)
	)
	stripStep.TextXAlignment = Enum.TextXAlignment.Right
	stripLine = Ui.label(
		strip,
		"Line",
		"",
		Ui.FONT_SEMI,
		15,
		Ui.color.text,
		UDim2.new(1, -28, 0, 18),
		UDim2.fromOffset(14, 38)
	)
	stripLine.TextXAlignment = Enum.TextXAlignment.Center
	stripLine.TextScaled = true
	local lineSize = Instance.new("UITextSizeConstraint")
	lineSize.MaxTextSize = 15
	lineSize.Parent = stripLine
	-- The count, then an arrow and the distance to the step's target, in one centred row
	local way = Instance.new("Frame")
	way.Name = "Way"
	way.BackgroundTransparency = 1
	way.Position = UDim2.fromOffset(0, 58)
	way.Size = UDim2.new(1, 0, 0, 18)
	way.Parent = strip
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = way
	stripCount = Ui.label(way, "Count", "", Ui.FONT_HEAVY, 15, Ui.color.accent, UDim2.fromOffset(0, 18))
	stripCount.AutomaticSize = Enum.AutomaticSize.X
	stripCount.LayoutOrder = 1
	stripCount.Visible = false
	stripArrow = Ui.label(way, "Arrow", "▲", Ui.FONT_HEAVY, 14, Ui.color.accent, UDim2.fromOffset(16, 18))
	stripArrow.TextXAlignment = Enum.TextXAlignment.Center
	stripArrow.LayoutOrder = 2
	stripArrow.Visible = false
	stripGuide = Ui.label(way, "Guide", "", Ui.FONT_BOLD, 14, Ui.color.accent, UDim2.fromOffset(0, 18))
	stripGuide.AutomaticSize = Enum.AutomaticSize.X
	stripGuide.LayoutOrder = 3
	stripGuide.Visible = false
	local _, bar =
		Ui.bar(strip, "Progress", UDim2.new(1, -28, 0, 5), UDim2.new(0, 14, 1, -11), Ui.color.accent)
	stripFill = bar
	strip.Visible = false
end

-- The strip's count ("2 / 5", "DONE ✓"; hidden when there's nothing to count)
local function stripCounts(text: string, color: Color3)
	stripCount.Text = text
	stripCount.TextColor3 = color
	stripCount.Visible = text ~= ""
end

-- The card for a mouse or a pad, the strip for a phone, or neither
local function present()
	local touch = shownDevice == "touch"
	panel.Visible = showing and not touch
	strip.Visible = showing and touch
end

-- A little bounce so a new step is noticed (the card, or the strip, whose edge
-- flashes too: a phone gets no banner in the middle of the screen, the strip is it)
local function bounce(by: number, seconds: number)
	local touch = device() == "touch"
	local piece = if touch then strip else panel
	local rest = if touch then 1 else CARD_SCALE
	local scaler = piece:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scaler.Parent = piece
	scaler.Scale = rest * by
	Ui.tween(scaler, seconds, { Scale = rest }, Enum.EasingStyle.Back)
	local stroke = piece:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
		Ui.tween(stroke, 1.6, { Transparency = 0.5 })
	end
end

-- The guide: the distance to the step's target and an arrow turned toward it (nil:
-- none), on the card and on the strip
local function showGuide(text: string?, turn: number?)
	guideLine.Visible = text ~= nil
	stripGuide.Visible = text ~= nil
	if text then
		guideLine.Text = text
		stripGuide.Text = text
	end
	guideArrow.Visible = turn ~= nil
	stripArrow.Visible = turn ~= nil
	if turn then
		guideArrow.Rotation = turn
		stripArrow.Rotation = turn
	end
end

-- Phones: the HUD's button row runs across the middle of the screen, nine buttons
-- just over the fish (the 2026-11-08 phone screenshot), and until a new player has
-- met the INDEX there is nothing in it for them. So on a phone it's put away for the
-- tutorial's first steps: only ROLL shows on the Roll step and INDEX on the Index
-- step (the ring finds them), and from the step after the INDEX on, and ever after,
-- the whole row is back. The buttons are moved to a hidden frame beside the row, not
-- hidden one by one: their own controllers set Visible (ROLL only with a roll ready,
-- MAPS with a map held), and more join the row late (PASS, LOG, DAILY, SHOP, POD).
local EVERY = "*"
local rowAllowed: string? = EVERY -- every button, the one named, or none (nil)
local heldRow: Frame? = nil
local lastPoint = 0 -- the last step done at a HUD button
for index, each in Tutorial.steps do
	if each.point ~= nil then
		lastPoint = index
	end
end

local function rowWanted(s: { [string]: any }): string?
	local tutorial = s.tutorial
	if not Ui.isTouch() or typeof(tutorial) ~= "table" or tutorial.done then
		return EVERY
	end
	local index = tutorial.step
	if typeof(index) ~= "number" or index > lastPoint then
		return EVERY
	end
	local step = Tutorial.steps[index]
	local point = if step then step.point else nil
	return if point == "Roll" or point == "Index" then point else nil
end

local function sortRow()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local wallet = playerGui and playerGui:FindFirstChild("Wallet")
	local row = wallet and wallet:FindFirstChild("Buttons")
	if wallet == nil or row == nil then
		return
	end
	local held = heldRow
	if held == nil or held.Parent ~= wallet then
		if rowAllowed == EVERY then
			return -- (nothing was ever put away)
		end
		held = Instance.new("Frame")
		held.Name = "ButtonsHeld"
		held.BackgroundTransparency = 1
		held.Visible = false
		held.Parent = wallet
		heldRow = held
	end
	local allowed = rowAllowed
	for _, child in held:GetChildren() do
		if child:IsA("GuiButton") and (allowed == EVERY or child.Name == allowed) then
			child.Parent = row
		end
	end
	if allowed ~= EVERY then
		for _, child in row:GetChildren() do
			if child:IsA("GuiButton") and child.Name ~= allowed then
				child.Parent = held
			end
		end
	end
end

-- The card's rows for this device. On a phone the guide line (the distance to the
-- step's target) sits right under the header, clear of the swim stick's resting
-- ring at the screen's lower left, which lay over it (PC 2026-10-19: "21 ft to the
-- nearest exit"); the cursor tip is for a mouse, so a phone's card is shorter.
local function cardScale(): number
	return if shownDevice == "touch" then CARD_SCALE_TOUCH else CARD_SCALE
end

local function layoutCard()
	local touch = shownDevice == "touch"
	local guideY = if touch then 30 else 160
	panel.Size = UDim2.fromOffset(300, if touch then PANEL_HEIGHT_TOUCH else PANEL_HEIGHT)
	titleText.Position = UDim2.fromOffset(14, if touch then 48 else 28)
	stepText.Position = UDim2.fromOffset(14, if touch then 74 else 54)
	capsRow.Position = UDim2.fromOffset(14, if touch then 128 else 106)
	tipLine.Position = UDim2.fromOffset(14, guideY + 19)
	local scaler = panel:FindFirstChildOfClass("UIScale")
	if scaler then
		scaler.Scale = cardScale()
	end
	guideArrow.Position = UDim2.fromOffset(23, guideY + 8)
	guideLine.Position = UDim2.fromOffset(36, guideY)
	tipLine.Visible = not touch
end

-- Rebuilds the row of key caps for a step (and the card's rows for the device)
local function showControls(step: TutorialConfig.Step)
	shownDevice = device()
	layoutCard()
	present()
	capsRow:ClearAllChildren()
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	-- On a phone the caps line up from the card's right: its lower-left corner is
	-- where the swim stick's ring rests (HudController), and it lay over STICK / DRAG
	-- (PC 2026-10-20, TU3)
	layout.HorizontalAlignment = if shownDevice == "touch"
		then Enum.HorizontalAlignment.Right
		else Enum.HorizontalAlignment.Left
	layout.Parent = capsRow
	local shown = 0
	for i, control in step.controls do
		local key = keyFor(control)
		if key == nil then
			continue
		end
		shown += 1
		local holder = Instance.new("Frame")
		holder.Name = `Control{i}`
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromOffset(0, 50)
		holder.AutomaticSize = Enum.AutomaticSize.X
		holder.LayoutOrder = i
		holder.Parent = capsRow
		-- The cap over its caption, centred: the holder is as wide as the wider of
		-- the two (a long caption under a short cap, "free the cursor for buttons"
		-- under ALT, ran into the next one: PC playtest 2026-10-14, R1)
		local stack = Instance.new("UIListLayout")
		stack.FillDirection = Enum.FillDirection.Vertical
		stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
		stack.Padding = UDim.new(0, 4)
		stack.SortOrder = Enum.SortOrder.LayoutOrder
		stack.Parent = holder
		local cap = Ui.keycap(holder, "Cap", key, 30)
		cap.LayoutOrder = 1
		local caption =
			Ui.label(holder, "Does", control.does, Ui.FONT_SEMI, 11, Ui.color.muted, UDim2.fromOffset(0, 14))
		caption.AutomaticSize = Enum.AutomaticSize.X
		caption.LayoutOrder = 2
		caption.TextXAlignment = Enum.TextXAlignment.Center
		caption.TextWrapped = false
	end
	capsRow.Visible = shown > 0
end

-- The cursor tip under the card, for players with a mouse
local function cursorTip(): string
	if Input.usingTouch() or Input.isGamepad() then
		return ""
	end
	return "Tap ALT to free the cursor for buttons and menus · ALT again to swim"
end

-- Each new step opens with its goal in the middle of the screen for a few seconds
-- (waiting its turn behind the bank's growth sequence or another banner)
local bannerStep = 0 -- the step whose banner was asked for last
local function stepBanner(index: number, step: TutorialConfig.Step)
	bannerStep = index
	Ui.stageBanner("tutorialStep", 3.2, 0.5, function()
		local holder = Instance.new("Frame")
		holder.Name = "TutorialStepBanner"
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.3)
		holder.Size = UDim2.fromOffset(760, 96)
		holder.BackgroundTransparency = 1
		local scale = Instance.new("UIScale")
		scale.Scale = 0.7
		scale.Parent = holder
		local over = Ui.label(
			holder,
			"Over",
			`TUTORIAL · STEP {index} OF {#Tutorial.steps}`,
			Ui.FONT_BOLD,
			20,
			Ui.color.accent,
			UDim2.new(1, 0, 0, 24)
		)
		over.TextXAlignment = Enum.TextXAlignment.Center
		over.TextStrokeTransparency = 0.6
		local title = Ui.label(
			holder,
			"Title",
			step.title,
			Ui.FONT_HEAVY,
			44,
			Ui.color.text,
			UDim2.new(1, 0, 0, 52),
			UDim2.fromOffset(0, 28)
		)
		title.TextXAlignment = Enum.TextXAlignment.Center
		title.TextStrokeTransparency = 0.45
		holder.Parent = gui
		Ui.tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		return function(quick: boolean)
			local seconds = if quick then 0.2 else 0.5
			Ui.tween(over, seconds, { TextTransparency = 1, TextStrokeTransparency = 1 })
			Ui.tween(title, seconds, { TextTransparency = 1, TextStrokeTransparency = 1 })
			task.delay(seconds + 0.05, function()
				holder:Destroy()
			end)
		end
	end, function()
		-- (only while no later step's banner has been asked for: the bank step's banner
		-- stepped aside for the bank's growth and came back over the next step's card)
		return bannerStep == index
	end)
end

-- The card turns to another step (or to a step shown done): a little bounce so it's
-- noticed, and its keys; the trail or ring only for the step being played
local function newCard(index: number, step: TutorialConfig.Step, done: boolean)
	local first = shownStep == 0
	-- (a phone's strip sits where the banner would open: the strip itself is the banner)
	if not done and shownStep ~= index and device() ~= "touch" then
		stepBanner(index, step)
	end
	shownStep = index
	shownRecap = done
	showControls(step)
	if not first then
		bounce(1.08, 0.4)
		Sfx.play("Banner", { volume = 0.3 })
	end
	tipLine.Text = cursorTip()
	guideKind = if done then nil else step.guide
	pointKind = if done then nil else step.point
	clearPoint()
	target = nil
	nextSearch = 0
end

-- What a step done the moment it began says on the card
local function recapNote(step: TutorialConfig.Step, s: { [string]: any }): string
	if step.event == "haul" then
		if s.maxed then
			return "Your Haul is full: that's all you can carry. Swim home to bank it!"
		elseif (s.haul or 0) > 0 then
			return "Your Haul is big enough already. Swim home to bank it!"
		end
	elseif step.event == "banked" then
		return "Banked! That Haul is yours for good now"
	end
	return "Done already! On to the next step"
end

-- The card for a step done the moment it began: its number, DONE, a full bar and
-- what happened
local function drawRecap(index: number, s: { [string]: any })
	local step = Tutorial.steps[index]
	if step == nil then
		return
	end
	if shownStep ~= index or not shownRecap then
		newCard(index, step, true)
	end
	header.Text = `TUTORIAL · STEP {index} OF {#Tutorial.steps}`
	titleText.Text = step.title
	stepText.Text = recapNote(step, s)
	stepText.TextColor3 = Ui.color.haul
	countText.Text = "DONE ✓"
	countText.TextColor3 = Ui.color.safe
	Ui.tween(fill, 0.35, { Size = UDim2.fromScale(1, 1) })
	stripStep.Text = `{index} / {#Tutorial.steps}`
	stripTitle.Text = step.title
	stripLine.Text = stepText.Text
	stripLine.TextColor3 = Ui.color.haul
	stripCounts("DONE ✓", Ui.color.safe)
	Ui.tween(stripFill, 0.35, { Size = UDim2.fromScale(1, 1) })
end

-- The card for the step being played
local function drawLive(s: { [string]: any })
	local tutorial = s.tutorial
	local index = if typeof(tutorial) == "table" then tutorial.step else nil
	local step = if typeof(index) == "number" then Tutorial.steps[index] else nil
	if step == nil or typeof(tutorial) ~= "table" then
		return
	end
	if shownStep ~= index or shownRecap then
		newCard(index, step, false)
		liveShownAt = os.clock()
	end
	header.Text = `TUTORIAL · STEP {index} OF {#Tutorial.steps}`
	titleText.Text = step.title
	stepText.Text = step.text
	stepText.TextColor3 = Ui.color.text
	countText.TextColor3 = Ui.color.accent
	local progress = math.min(tutorial.progress or 0, step.goal)
	if step.event == "haul" then
		-- The Haul against its target, as food like the Haul card (Size.haulShown; the
		-- server counts it in percent)
		local banked = s.mass or 1
		local haulTarget = TutorialConfig.haulTarget(banked)
		local shown = Size.haulShown(banked, math.min(s.haul or 0, haulTarget))
		countText.Text = `{Format.mass(shown)} / {Format.mass(Size.haulShown(banked, haulTarget))}`
	else
		countText.Text = if step.goal > 1 then `{progress} / {step.goal}` else ""
	end
	Ui.tween(fill, 0.35, { Size = UDim2.fromScale(progress / step.goal, 1) })
	stripStep.Text = `{index} / {#Tutorial.steps}`
	stripTitle.Text = step.title
	stripLine.Text = step.phone
	stripLine.TextColor3 = Ui.color.text
	stripCounts(countText.Text, Ui.color.accent)
	Ui.tween(stripFill, 0.35, { Size = UDim2.fromScale(progress / step.goal, 1) })
end

-- The card: a step shown done while any wait their turn, else the live step
local function render(s: { [string]: any })
	if recapStep == nil and #recaps > 0 then
		recapStep = table.remove(recaps, 1)
		recapUntil = os.clock() + RECAP_SECONDS
	end
	local done = recapStep
	if done then
		drawRecap(done, s)
	else
		drawLive(s)
	end
	local live = Tutorial.steps[liveStep]
	showMarkers(if live then live.marker else nil, s)
end

local function onState(s: { [string]: any })
	local tutorial = s.tutorial
	if typeof(tutorial) ~= "table" then
		return
	end
	rowAllowed = rowWanted(s)
	sortRow()
	if tutorial.done then
		showing = false
		present()
		table.clear(recaps)
		recapStep = nil
		showMarkers(nil, s)
		guideKind = nil
		pointKind = nil
		clearPoint()
		target = nil
		targetFish = nil
		hideGuide()
		-- A restart draws its first card afresh (its trail, banner and keys): the card
		-- that was up when it finished may be the same step (PC 2026-10-20, DX: finished
		-- at step 1, restarted, no trail)
		shownStep = 0
		liveStep = 0
		liveShownAt = nil
		if wasDone == false then
			task.spawn(celebrate)
		end
		wasDone = true
		return
	end
	wasDone = false
	local index = tutorial.step
	if typeof(index) ~= "number" or Tutorial.steps[index] == nil then
		return
	end
	if liveStep ~= 0 and index > liveStep then
		-- Moved on: the step on the card if it was up under a second (or never got
		-- its turn), and any step never shown, are shown done first
		local shownAt = liveShownAt
		if shownAt == nil or os.clock() - shownAt < INSTANT then
			table.insert(recaps, liveStep)
		end
		for skipped = liveStep + 1, index - 1 do
			table.insert(recaps, skipped)
		end
		liveShownAt = nil
	elseif index < liveStep then
		-- Sent back (the Haul lost on the way home): straight there
		table.clear(recaps)
		recapStep = nil
		liveShownAt = nil
	end
	liveStep = index
	showing = true
	render(s)
	present()
end

-- What the guide line says on a `point` step
local POINT_LINES: { [string]: string } = {
	Roll = "The gold ROLL button, under your wallet",
	Wrap = "Your item bar, left of the Haul card",
	Index = "The INDEX button, under your wallet",
}

-- A `point` step: keep a ring on its HUD button (it can appear late, after the
-- server's grant arrives, and be rebuilt)
local function stepPoint()
	local kind = pointKind
	if kind == nil or not showing then
		clearPoint()
		return
	end
	if
		pointedAt == nil
		or pointedAt.Parent == nil
		or not pointedAt.Visible
		or pointRing == nil
		or pointRing.Parent == nil
	then
		clearPoint()
		local found = pointTarget(kind)
		if found then
			ringRound(found)
		end
	end
	showGuide(POINT_LINES[kind] or "", nil)
end

-- Every frame: find or refresh the target, draw the trail, write the distance (or
-- ring the HUD button a `point` step needs)
local function step(_dt: number)
	-- Twice a second: the phone's button row (buttons join it late), and the strip
	-- under the boss bar while one is up
	local now = os.clock()
	if now >= nextTidy then
		nextTidy = now + 0.5
		sortRow()
		if strip.Visible then
			local boss = Ui.bossBottom()
			strip.Position = UDim2.new(0.5, 0, 0, if boss > 0 then boss + 6 else STRIP_TOP)
		end
	end
	-- A step shown done has had its moment: the next one done, or the live step
	if recapStep ~= nil and now >= recapUntil then
		recapStep = nil
		local s = ClientState.current
		if s and showing then
			render(s)
		end
	end
	-- The device changed under a step: draw its keys again (PC 2026-10-19, TU1: on a
	-- phone the card kept W A S D, MOUSE and the ALT tip, drawn while the simulator
	-- still read as a keyboard; a pad picked up mid-step kept the keyboard's too)
	local shown = Tutorial.steps[shownStep]
	if shown and showing and device() ~= shownDevice then
		showControls(shown)
		tipLine.Text = cursorTip()
	end
	if pointKind ~= nil and showing then
		hideGuide()
		stepPoint()
		return
	end
	clearPoint()
	if not showing or guideKind == nil then
		hideGuide()
		showGuide(nil, nil)
		return
	end
	local root = SwimController.root()
	if root == nil then
		hideGuide()
		return
	end
	if now >= nextSearch then
		nextSearch = now + 0.5
		target = findTarget(guideKind, root.Position, ClientState.current or {})
	end
	local to = target
	if to == nil then
		hideGuide()
		showGuide(nil, nil)
		return
	end
	-- A fish swims on between looks: the trail and the ring stay on it (eaten, by us or
	-- anyone: look again now)
	local fish = targetFish
	if fish then
		local live = SchoolController.fishPosition(fish)
		if live then
			to = live
		else
			nextSearch = 0
		end
	end
	drawTrail(root.Position, to, now)
	if viaWhat == nil and (guideKind == "food" or guideKind == "shells") then
		drawRing(to, now)
	else
		hideRing()
	end
	local offset = to - root.Position
	local distance = offset.Magnitude
	-- The arrow turns relative to where the camera looks
	local look = workspace.CurrentCamera.CFrame.LookVector
	local cameraYaw = math.atan2(-look.X, -look.Z)
	local targetYaw = math.atan2(-offset.X, -offset.Z)
	local what = viaWhat
		or (
			if guideKind == "exits"
				then "the nearest exit"
				elseif guideKind == "den" then "your den's pool"
				elseif guideKind == "shells" then "the nearest shell"
				elseif guideKind == "wheel" then "the Treasure Wheel"
				else "the nearest food"
		)
	local vertical = if offset.Y > 8 then " · above you" elseif offset.Y < -8 then " · below you" else ""
	showGuide(`{Format.distance(distance)} to {what}{vertical}`, math.deg(targetYaw - cameraYaw))
end

function TutorialController.start()
	gui = Ui.screen("Tutorial", Players.LocalPlayer:WaitForChild("PlayerGui"), 7)
	panel = Ui.panel(gui, "Tutorial", UDim2.fromOffset(300, PANEL_HEIGHT), UDim2.fromOffset(18, 262))
	Ui.belowTopBar(gui, panel, 262)
	local scaler = Instance.new("UIScale")
	scaler.Scale = CARD_SCALE
	scaler.Parent = panel
	local stroke = panel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Ui.color.accent
		stroke.Transparency = 0.5
	end
	header = Ui.label(
		panel,
		"Header",
		"",
		Ui.FONT_BOLD,
		12,
		Ui.color.accent,
		UDim2.new(1, -28, 0, 16),
		UDim2.fromOffset(14, 10)
	)
	titleText = Ui.label(
		panel,
		"Title",
		"",
		Ui.FONT_HEAVY,
		21,
		Ui.color.text,
		UDim2.new(1, -28, 0, 24),
		UDim2.fromOffset(14, 28)
	)
	titleText.TextScaled = true
	local titleSize = Instance.new("UITextSizeConstraint")
	titleSize.MaxTextSize = 21
	titleSize.Parent = titleText
	stepText = Ui.label(
		panel,
		"Step",
		"",
		Ui.FONT_SEMI,
		14,
		Ui.color.text,
		UDim2.new(1, -28, 0, 48),
		UDim2.fromOffset(14, 54)
	)
	stepText.TextWrapped = true
	stepText.TextYAlignment = Enum.TextYAlignment.Top
	countText = Ui.label(
		panel,
		"Count",
		"",
		Ui.FONT_HEAVY,
		16,
		Ui.color.accent,
		UDim2.fromOffset(130, 18),
		UDim2.new(1, -144, 0, 8)
	)
	countText.TextXAlignment = Enum.TextXAlignment.Right
	capsRow = Instance.new("Frame")
	capsRow.Name = "Controls"
	capsRow.BackgroundTransparency = 1
	capsRow.Position = UDim2.fromOffset(14, 88)
	capsRow.Size = UDim2.new(1, -28, 0, 50)
	capsRow.Parent = panel
	-- The guide: an arrow and the distance to the step's target
	guideArrow = Ui.label(
		panel,
		"Arrow",
		"▲",
		Ui.FONT_HEAVY,
		16,
		Ui.color.accent,
		UDim2.fromOffset(18, 18),
		UDim2.fromOffset(14, 142)
	)
	guideArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	guideArrow.Position = UDim2.fromOffset(23, 151)
	guideArrow.TextXAlignment = Enum.TextXAlignment.Center
	guideArrow.Visible = false
	guideLine = Ui.label(
		panel,
		"Guide",
		"",
		Ui.FONT_BOLD,
		12,
		Ui.color.accent,
		UDim2.new(1, -50, 0, 16),
		UDim2.fromOffset(36, 143)
	)
	guideLine.Visible = false
	tipLine = Ui.label(
		panel,
		"Tip",
		"",
		Ui.FONT,
		11,
		Ui.color.muted,
		UDim2.new(1, -28, 0, 14),
		UDim2.fromOffset(14, 160)
	)
	tipLine.TextWrapped = true
	local _, bar =
		Ui.bar(panel, "Progress", UDim2.new(1, -28, 0, 5), UDim2.new(0, 14, 1, -13), Ui.color.accent)
	fill = bar
	panel.Visible = false
	buildStrip()
	markers = Instance.new("Folder")
	markers.Name = "TutorialMarkers"
	markers.Parent = workspace
	trail = Instance.new("Folder")
	trail.Name = "TutorialTrail"
	trail.Parent = workspace
	buildTrail()
	buildRing()
	ClientState.changed:connect(onState)
	if ClientState.current then
		onState(ClientState.current)
	end
	RunService.RenderStepped:Connect(step)
	-- After the start screen the step pops, so a new player sees where to begin
	StartController.afterStart(function()
		task.wait(0.6)
		if not showing then
			return
		end
		Sfx.play("Banner", { volume = 0.4 })
		bounce(1.14, 0.5)
	end)
end

return TutorialController
