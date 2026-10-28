--!strict
-- Build mode (owner, 2026-10-13: "The dens need to be larger and have much more
-- depth so players can build in them and show them off. It's meant to be like the
-- players house/base. We will have furniture, rugs, lamps, and tons of items").
-- In your own den, B (or BUILD in the den menu) turns it on: you keep swimming and
-- aim with the camera, a ghost of the thing picked in the tray shows where it would
-- go (green, or red with the reason), and it goes onto a deck, a wall or a ceiling,
-- whichever it's made for, or onto something already there. Aim at a placed thing to
-- pick it up and move it, or put it back in the tray. The server checks every
-- request against the den's space again (DenService, Shared/DenSpace).
--
--   PC          aim: the camera · LEFT CLICK place / pick up · RIGHT CLICK drop it
--               R / F turn · Q / E pick a thing · X put away · G snap on/off
--               L lay out the picked thing's set · B done
--   Controller  RT place / pick up · LT drop it · LB / RB turn · D-pad left/right
--               pick · D-pad up snap · D-pad down lay out · X put away · B done
--   Phone       aim: drag · PLACE, TURN, SNAP, LAY OUT, PUT AWAY, DROP, DONE and
--               the tray's tiles
--
-- The editor view (owner, 2026-10-16: "when a player goes to build in their den it
-- should set them in a locked screen where they can edit the den and drag parts
-- there. Its too difficult to do as a fish"): Build mode takes the screen. The
-- fish holds still (`Input.editing`), the camera leaves it and looks down on the
-- den's floor from a three-quarter view (CameraController.override), and the
-- cursor is free: point at the floor and click, or press on a placed thing and
-- drag it where it should go and let go (a quick click picks it up instead, and
-- the next click puts it down), or drag a thing straight out of the tray. The view:
--
--   PC          WASD / arrows pan · RIGHT-DRAG orbit · wheel zoom · SPACE / C the
--               floor above / below
--   Controller  left stick pans · right stick orbits · A the next floor
--   Phone       drag orbits · pinch zooms · tap places or picks up · FLOOR
--
-- The view keeps to the floor of the storey it's on (the den's rooms there) and
-- out of the rock (a ray from the floor to the camera).
--
-- Snapping (owner, 2026-10-14; on by default, G turns it off): turns go in 45°
-- steps (15° off); a floor thing lines up with a neighbour's x or z when within
-- 0.8 studs, and with rock close behind it, it backs onto the wall facing out; a
-- wall thing lines up with a neighbour's height. Starter layouts: with a set's piece
-- picked (or aimed at), L lays out every piece of that set in your tray round the
-- spot you aim at, facing you (Config/Dens `layouts`, DenService `DenLayout`).
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local DenItems = require(ReplicatedStorage.Shared.DenItems)
local DenSpace = require(ReplicatedStorage.Shared.DenSpace)
local Layout = require(ReplicatedStorage.Shared.Layout)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local ItemPhoto = require(script.Parent.Parent.ItemPhoto)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local CameraController = require(script.Parent.CameraController)
local HudController = require(script.Parent.HudController)
local MapController = require(script.Parent.MapController)
local MenuController = require(script.Parent.MenuController)
local SwimController = require(script.Parent.SwimController)

local Dens = Config.Dens

local BuildController = {}

local REACH = 320 -- how far the aim reaches (the editor's camera sits back over a big den)
local TURN = 15 -- degrees a tap of turn (snapping off)
local SNAP_TURN = 45 -- with snapping on
local ALIGN = 0.8 -- a floor thing lines up with a neighbour this close
local ALIGN_WALL = 1.2 -- a wall thing with a neighbour's height this close
local WALL_GAP = 2.5 -- a floor thing backs onto rock this close behind it
local TURN_REPEAT = 0.1 -- a held turn repeats this often
local GOOD = Color3.fromRGB(112, 236, 164)
local BAD = Color3.fromRGB(255, 96, 96)
local PICK = Color3.fromRGB(255, 220, 120)
local PRIORITY = 3500

type Selection = { id: string, uid: number? } -- uid: moving a placed thing
type Spot = { ok: boolean, surface: string, at: Vector3, turn: number, why: string?, snapped: boolean? }

local active = false
local selection: Selection? = nil
local yaw = 0
local spot: Spot? = nil
local aimedUid: number? = nil
local turning = 0 -- -1, 0, 1 while a turn is held
-- Turned by hand (R / F, LB / RB, TURN) since it was picked: snapping still backs it
-- onto a wall but keeps that turn (PC 2026-10-16: next to a wall, snapping overrode
-- R / F)
local handTurned = false
local underUid: number? = nil -- the placed thing under the aim (through a picked one)
local pickedAt = 0 -- when a placed thing was last picked up
local STEP_DOWN = 0.6 -- seconds: a second click this soon on a stack steps down
local nextTurn = 0
local hiddenUid: number? = nil
local snapOn = true
local lastFloor: Vector3? = nil -- the last floor spot aimed at (den frame)
local aimedSet: string? = nil -- the set of the placed thing aimed at

-- The editor view: a focus on the den's floor (den frame) the camera orbits
type View = { x: number, y: number, z: number, yaw: number, pitch: number, distance: number, storey: number }
local view: View = { x = 0, y = 1, z = 0, yaw = 0, pitch = math.rad(52), distance = 45, storey = 1 }
local VIEW_PITCH = { math.rad(18), math.rad(84) }
local VIEW_ZOOM = { 10, 120 }
-- Zoomed out, the view climbs toward the vault and looks down: the lowest pitch
-- rises to VIEW_TOPDOWN by full zoom, and once the camera is up against the vault
-- the rest of the zoom widens the lens, up to VIEW_FOV_MAX (PC 2026-10-16 round 2,
-- D6: zooming out sank the camera toward the floor and never showed a whole room)
local VIEW_TOPDOWN = math.rad(58)
local VIEW_FOV_MAX = 96
local VIEW_START = 60 -- the starting zoom
local VIEW_PAN = 26 -- studs a second at the starting zoom
local VIEW_FOCUS_UP = 2 -- the camera looks this far over the deck
local orbiting = false -- the right mouse button held: dragging turns the view
local orbitMoved = 0 -- pixels the mouse moved while orbiting (a click drops instead)
local dragging = false -- a placed thing picked up with the left button held
local trayDrag = false -- a thing pressed in the tray, to be let go on the floor
local pressAt = Vector2.zero
local pressClock = 0
local tapAt: Vector2? = nil -- a phone's last tap: where it aims
local buttonClock = 0 -- when a Build button or tray tile was last pressed
local pinchFrom: number? = nil
local viewParams = RaycastParams.new()
viewParams.FilterType = Enum.RaycastFilterType.Include

local gui: ScreenGui
local panel: Frame
local header: TextLabel
local statusLabel: TextLabel
local controlsLabel: TextLabel
local trayFrame: ScrollingFrame
local touchRow: Frame
local snapButton: TextButton? = nil
local trayButton: TextButton? = nil
local shopButton: TextButton? = nil
-- The den shop is open over Build mode (owner, 2026-10-17: "I don't see a shop at all
-- where you buy den items"): the bar steps aside and the view holds still until it closes
local shopping = false
local bind: () -> ()
local unbind: () -> ()
local hintChip: TextLabel
local touchHint: TextLabel
-- A phone's editor (PC 2026-10-16: the panel sat in the middle third of the screen,
-- the swim stick and BITE / DASH / ITEMS / HEAL stayed up, little floor was left to
-- tap): a slim bar along the bottom whose tray folds away (it folds by itself once
-- a thing is picked), the help line at the top, and the swimming HUD hidden.
local trayFolded = false
-- Hidden while editing on every device (PC 2026-10-16 round 2: on PC the HUD's top
-- chips covered the view, and a click under a chip or the minimap was swallowed and
-- placed nothing)
local HIDE_WHILE_BUILDING = {
	"Hud",
	"SwimStickRing",
	"Heal",
	"ItemWheel",
	"Wallet",
	"Offers",
	"Map",
	"Hints",
	"Tides",
	"Pvp",
	"Biome",
	"Catches",
	"StallButton",
	"WheelButtons",
	"Tutorial",
	"Admin",
}
local hiddenGuis: { ScreenGui } = {}
local relayout: () -> () = function() end -- layoutTray, once it's defined

local ghost: Model? = nil
local ghostKey = ""
local ghostLight: Highlight
local aimLight: Highlight
local ghostFolder: Folder

local function state(): { [string]: any }
	return ClientState.current or {}
end

local function denRecord(): any
	local s = state()
	return s.den or { level = 1, glow = "Teal", items = {}, placed = {} }
end

-- The den's shape (Shared/DenSpace): its level, wings and Open Plan
local function denShape(): DenSpace.Shape
	local record = denRecord()
	return {
		level = record.level or 1,
		wings = if typeof(record.wings) == "table" then record.wings else nil,
		open = record.open == true,
	}
end

local function ownIndex(): number
	local index = state().denIndex
	return if typeof(index) == "number" then index else 0
end

local function glowColor(): Color3
	local glow = Dens.glowsById[denRecord().glow] or Dens.glows[1]
	return glow.color
end

local function denFolder(): Instance?
	local world = workspace:FindFirstChild("World")
	local hub = world and world:FindFirstChild("Hub")
	return hub and hub:FindFirstChild(`DenBase{ownIndex()}`)
end

local function placedCount(id: string): number
	local count = 0
	for _, placement in denRecord().placed or {} do
		if placement.id == id then
			count += 1
		end
	end
	return count
end

local function inTray(id: string): number
	local items = denRecord().items or {}
	return (items[id] or 0) - placedCount(id)
end

-- The things in the tray, in the catalog's order
-- A tile stays where it is for the rest of the Build session once shown, greyed at
-- ×0, so the tiles after it don't shift (PC 2026-10-16 round 2, B4: a remembered
-- tile position picked the wrong thing once one ran out)
local shownThisSession: { [string]: boolean } = {}

local function trayIds(): { string }
	local list: { string } = {}
	for _, item in Dens.items do
		if inTray(item.id) > 0 or shownThisSession[item.id] then
			shownThisSession[item.id] = true
			table.insert(list, item.id)
		end
	end
	return list
end

-- The tray's things that are left to place
local function pickableIds(): { string }
	local list: { string } = {}
	for _, id in trayIds() do
		if inTray(id) > 0 then
			table.insert(list, id)
		end
	end
	return list
end

local function capacity(): number
	local c = state().denCapacity
	return if typeof(c) == "number" then c else 15
end

local function insideOwnDen(): boolean
	local root = SwimController.root()
	return root ~= nil and ownIndex() > 0 and Layout.denAt(root.Position) == ownIndex()
end

-- The placed model with a uid
local function modelOf(uid: number): Model?
	local folder = denFolder()
	local items = folder and folder:FindFirstChild("Items")
	if items == nil then
		return nil
	end
	for _, model in items:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("DenUid") == uid then
			return model
		end
	end
	return nil
end

-- Hides (locally) the thing being moved, or shows it again
local function hide(uid: number?)
	if hiddenUid == uid then
		return
	end
	local old = if hiddenUid then modelOf(hiddenUid) else nil
	if old then
		for _, descendant in old:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.LocalTransparencyModifier = 0
			end
		end
	end
	hiddenUid = uid
	local model = if uid then modelOf(uid) else nil
	if model then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.LocalTransparencyModifier = 1
			end
		end
	end
end

local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	ghostKey = ""
	ghostLight.Adornee = nil
end

local function select(new: Selection?)
	selection = new
	handTurned = false
	if new and new.uid == nil and active and Input.isTouch() and not trayFolded then
		trayFolded = true
		task.defer(relayout)
	end
	if new == nil then
		hide(nil)
		clearGhost()
	elseif new.uid then
		hide(new.uid)
	else
		hide(nil)
	end
	BuildController.refresh()
end

-- The aim ray: from the screen's middle (the mouse is locked to it), or from a
-- freed mouse pointer
local function aimRay(): Ray
	local camera = workspace.CurrentCamera
	local point = camera.ViewportSize / 2
	local tap = tapAt
	if active and Input.isTouch() and tap then
		-- A phone in the editor aims where it last tapped (inset like the mouse)
		point = tap + GuiService:GetGuiInset()
	elseif
		UserInputService.MouseEnabled
		and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter
		and not Input.isTouch()
		and not (active and Input.isGamepad())
	then
		point = UserInputService:GetMouseLocation()
	end
	return camera:ViewportPointToRay(point.X, point.Y)
end

local function rayParams(): RaycastParams
	local include: { Instance } = { workspace.Terrain }
	local folder = denFolder()
	if folder then
		local shell = folder:FindFirstChild("Shell")
		if shell then
			table.insert(include, shell)
		end
		local garden = folder:FindFirstChild("Garden")
		if garden then
			table.insert(include, garden)
		end
		local items = folder:FindFirstChild("Items")
		if items then
			for _, model in items:GetChildren() do
				if model:GetAttribute("DenUid") ~= hiddenUid then
					table.insert(include, model)
				end
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	return params
end

-- The view's focus stays over a storey's floor: the nearest spot inside one of its
-- rooms, VIEW_INSET from the walls. (Clamped to the box round all the rooms, its
-- corners lay in the rock, where the camera's ray out of the rock started inside it,
-- so panning took the view through the walls into the hub and the open sea: PC
-- 2026-10-16 BD2.)
local VIEW_INSET = 3

-- Whether another of the storey's rooms carries on past `z` (where two rooms meet,
-- the line between them is open floor, not a wall)
local function carriesOn(rooms: { any }, room: any, z: number): boolean
	for _, other in rooms do
		if other ~= room then
			local near, far = math.min(other.z0, other.z1), math.max(other.z0, other.z1)
			if z >= near - 0.5 and z <= far + 0.5 then
				return true
			end
		end
	end
	return false
end

local function clampView()
	local rooms = DenSpace.rooms(denShape(), view.storey)
	local house = {}
	for _, room in rooms do
		if room.wing == nil then
			table.insert(house, room)
		end
	end
	local bestX, bestZ, bestGap = view.x, view.z, math.huge
	for _, room in rooms do
		local cx = room.cx or 0
		local x0, x1 = cx - math.max(room.x - VIEW_INSET, 0), cx + math.max(room.x - VIEW_INSET, 0)
		local near, far = math.min(room.z0, room.z1), math.max(room.z0, room.z1)
		-- Inset from the end walls only: insetting both ends of every room left a
		-- gap where two rooms meet that panning never crossed, so the view stopped
		-- at the first room's end (PC 2026-10-16 round 2, D6)
		local z0 = if room.wing == nil and carriesOn(house, room, near) then near else near + VIEW_INSET
		local z1 = if room.wing == nil and carriesOn(house, room, far) then far else far - VIEW_INSET
		if room.wing then
			-- A wing runs out sideways: its passage reaches back into the house and
			-- on into the wing, and the wing is inset only at its far end
			local outward = if cx > 0 then 1 else -1
			local inner, outer = cx - outward * room.x, cx + outward * room.x
			if room.passage then
				inner -= outward * (VIEW_INSET + 2)
			else
				outer -= outward * VIEW_INSET
			end
			x0, x1 = math.min(inner, outer), math.max(inner, outer)
		end
		if z0 > z1 then
			z0, z1 = (near + far) / 2, (near + far) / 2
		end
		local x = math.clamp(view.x, x0, x1)
		local z = math.clamp(view.z, z0, z1)
		local gap = (x - view.x) ^ 2 + (z - view.z) ^ 2
		if gap < bestGap then
			bestX, bestZ, bestGap = x, z, gap
		end
	end
	if bestGap == math.huge then
		bestX, bestZ = math.clamp(view.x, -10, 10), math.clamp(view.z, -10, 10)
	end
	view.x, view.z = bestX, bestZ
end

-- Up or down a storey (-1 up, +1 down), keeping the view's spot as near as it can
local function changeFloor(by: number)
	local deepest = DenSpace.storeys(denShape())
	local nextStorey = math.clamp(view.storey + by, 1, deepest)
	if nextStorey == view.storey then
		Sfx.play("TooBig", { volume = 0.25 })
		return
	end
	view.storey = nextStorey
	view.y = DenSpace.storey(nextStorey).deck
	clampView()
	Sfx.play("UiOpen", { volume = 0.35, pitch = if by < 0 then 1.15 else 0.9 })
end

-- The view starts over the floor the fish is on, looking the way the camera did
local function startView()
	local index = ownIndex()
	local root = SwimController.root()
	local frame = DenSpace.frame(index)
	local here = if root then DenSpace.toLocal(frame, root.Position) else Vector3.zero
	local best, bestGap = 1, math.huge
	for n = 1, DenSpace.storeys(denShape()) do
		local gap = math.abs(here.Y - DenSpace.storey(n).deck)
		if gap < bestGap then
			best, bestGap = n, gap
		end
	end
	view.storey = best
	view.x, view.z = here.X, here.Z
	view.y = DenSpace.storey(best).deck
	-- The middle of the room the fish is in, not over the pool where it waits (PC
	-- 2026-10-16 round 2, D6: a LV 100 fish filled the view)
	for _, room in DenSpace.rooms(denShape(), best) do
		local near, far = math.min(room.z0, room.z1), math.max(room.z0, room.z1)
		if DenSpace.inRoom(room, here.X, here.Z, 2) then
			view.x, view.z = room.cx or 0, (near + far) / 2
			break
		end
	end
	clampView()
	local look = workspace.CurrentCamera.CFrame.LookVector
	view.yaw = math.atan2(-look.X, -look.Z)
	view.pitch = math.rad(55)
	view.distance = VIEW_START
	viewParams.FilterDescendantsInstances = { workspace.Terrain }
end

-- The editor's camera, every frame (CameraController.override)
local function viewCFrame(dt: number): CFrame?
	local index = ownIndex()
	if not active or index == 0 then
		return nil
	end
	-- The cursor is free; held in place while the right button orbits
	local behavior = if orbiting then Enum.MouseBehavior.LockCurrentPosition else Enum.MouseBehavior.Default
	if UserInputService.MouseBehavior ~= behavior then
		UserInputService.MouseBehavior = behavior
	end
	if not UserInputService.MouseIconEnabled then
		UserInputService.MouseIconEnabled = true
	end
	-- Orbit: the right mouse button held, a phone's drag or the right stick
	local look = Input.consumeLook(dt)
	if shopping then
		look = Vector2.zero
	end
	if orbiting and not shopping then
		local delta = UserInputService:GetMouseDelta()
		orbitMoved += delta.Magnitude
		look += delta * Config.Tuning.camera.mouseSensitivity
	end
	view.yaw -= look.X
	-- Zoom: the wheel, or a phone's pinch (set in the pinch handler)
	local notches = Input.consumeZoom()
	if notches ~= 0 and not shopping then
		view.distance = math.clamp(view.distance * (1 - 0.12 * notches), VIEW_ZOOM[1], VIEW_ZOOM[2])
	end
	-- Zoomed out it climbs and looks down: the lowest pitch rises with the zoom
	local zoomed = math.clamp((view.distance - VIEW_START) / (VIEW_ZOOM[2] - VIEW_START), 0, 1)
	local lowest = VIEW_PITCH[1] + (VIEW_TOPDOWN - VIEW_PITCH[1]) * zoomed
	view.pitch = math.clamp(view.pitch + look.Y, lowest, VIEW_PITCH[2])
	-- Under the vault: the camera stops just under it along its own line of sight,
	-- and the zoom left over widens the lens instead
	local headroom = math.max(DenSpace.storey(view.storey).ceiling - view.y - VIEW_FOCUS_UP - 3, 4)
	local reach = math.min(view.distance, headroom / math.max(math.sin(view.pitch), 0.05))
	local base = Config.Tuning.camera.fov
	CameraController.overrideFov = math.clamp(base + (view.distance / reach - 1) * 22, base, VIEW_FOV_MAX)
	-- Pan: WASD or the arrows, or the left stick, across the floor
	local pan = Vector2.zero
	if UserInputService:GetFocusedTextBox() == nil and not shopping then
		local function key(a: Enum.KeyCode, b: Enum.KeyCode): number
			return if UserInputService:IsKeyDown(a) or UserInputService:IsKeyDown(b) then 1 else 0
		end
		pan += Vector2.new(
			key(Enum.KeyCode.D, Enum.KeyCode.Right) - key(Enum.KeyCode.A, Enum.KeyCode.Left),
			key(Enum.KeyCode.W, Enum.KeyCode.Up) - key(Enum.KeyCode.S, Enum.KeyCode.Down)
		)
	end
	for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if input.KeyCode == Enum.KeyCode.Thumbstick1 and not shopping then
			local stick = Vector2.new(input.Position.X, input.Position.Y)
			if stick.Magnitude > 0.15 then
				pan += stick
			end
		end
	end
	if pan.Magnitude > 1 then
		pan = pan.Unit
	end
	local frame = DenSpace.frame(index)
	if pan.Magnitude > 0 then
		local forward = Vector3.new(-math.sin(view.yaw), 0, -math.cos(view.yaw))
		local right = Vector3.new(math.cos(view.yaw), 0, -math.sin(view.yaw))
		local delta = (forward * pan.Y + right * pan.X) * VIEW_PAN * (view.distance / 30) * dt
		local here = DenSpace.spot(frame, view.x, view.y, view.z).Position
		local moved = DenSpace.toLocal(frame, here + delta)
		view.x, view.z = moved.X, moved.Z
		clampView()
	end
	local focus = DenSpace.spot(frame, view.x, view.y + VIEW_FOCUS_UP, view.z).Position
	local orient = CFrame.Angles(0, view.yaw, 0) * CFrame.Angles(-view.pitch, 0, 0)
	local want = focus - orient.LookVector * reach
	-- Out of the rock: the camera stops short of the den's ceiling and walls
	local offset = want - focus
	local hit = workspace:Raycast(focus, offset, viewParams)
	local at = if hit then focus + offset.Unit * math.max(1.5, hit.Distance - 1.2) else want
	return CFrame.lookAt(at, focus)
end

-- Whether a point is over the tray (its clicks are the tray's). `position` counts
-- from below the top bar, as GetGuiObjectsAtPosition does (an input's Position, a
-- tap, the mouse less the inset). It also tried the point the inset lower, which
-- made a strip as tall as the top bar above the tray swallow clicks: a green ghost
-- there placed nothing and said nothing (PC 2026-10-17, BC2).
local function overPanel(position: Vector3 | Vector2): boolean
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return false
	end
	for _, object in playerGui:GetGuiObjectsAtPosition(position.X, position.Y) do
		if object:IsDescendantOf(panel) then
			return true
		end
	end
	return false
end

-- The placed thing a part belongs to (its uid)
local function uidOf(instance: Instance?): (number?, Model?)
	local at = instance
	while at and at ~= workspace do
		if at:IsA("Model") then
			local uid = at:GetAttribute("DenUid")
			if typeof(uid) == "number" then
				return uid, at
			end
		end
		at = at.Parent
	end
	return nil, nil
end

local function snapHalf(n: number): number
	return math.floor(n * 2 + 0.5) / 2
end

local function turnStep(): number
	return if snapOn then SNAP_TURN else TURN
end

-- Snapping a floor thing: x and z line up with the nearest neighbour's within
-- ALIGN, then, with rock (or a pillar) within WALL_GAP of where its back would be,
-- it backs onto that wall facing out (or, turned by hand, keeping its turn).
-- Returns the new spot and turn, and whether anything snapped.
local function snapFloor(item: any, at: Vector3, turn: number): (Vector3, number, boolean, Vector3?)
	local x, z, r = at.X, at.Z, turn
	local snapped = false
	local s = selection
	local bestX, bestZ = ALIGN, ALIGN
	for _, other in denRecord().placed or {} do
		if (s and other.uid == s.uid) or other.s ~= "floor" or math.abs((other.y or 0) - at.Y) > 0.5 then
			continue
		end
		local dx, dz = math.abs(other.x - at.X), math.abs(other.z - at.Z)
		if dx < bestX then
			bestX, x, snapped = dx, other.x, true
		end
		if dz < bestZ then
			bestZ, z, snapped = dz, other.z, true
		end
	end
	if item.flat then
		return Vector3.new(x, at.Y, z), r, snapped, nil
	end
	local frame = DenSpace.frame(ownIndex())
	local folder = denFolder()
	local include: { Instance } = { workspace.Terrain }
	local shell = folder and folder:FindFirstChild("Shell")
	if shell then
		table.insert(include, shell)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	local origin = DenSpace.spot(frame, x, at.Y + math.min(1.5, item.size.Y / 2), z).Position
	local depth = item.size.Z
	-- Kept at its own turn, its reach toward a wall is its turned footprint's
	local c, sn = math.abs(math.cos(math.rad(turn))), math.abs(math.sin(math.rad(turn)))
	local halfX = (c * item.size.X + sn * item.size.Z) / 2
	local halfZ = (sn * item.size.X + c * item.size.Z) / 2
	local reach = WALL_GAP + math.max(item.size.X, item.size.Z) / 2 + 1
	local bestGap, bestMove: Vector3?, bestTurn = WALL_GAP, nil, r
	local away: Vector3? = nil
	-- Each way in the den's frame (dx, dz) and the turn that faces away from it
	for _, way in { { 0, 1, 180 }, { 0, -1, 0 }, { 1, 0, 90 }, { -1, 0, 270 } } do
		local direction = frame:VectorToWorldSpace(Vector3.new(way[1], 0, -way[2]))
		local hit = workspace:Raycast(origin, direction * reach, params)
		if hit then
			local distance = (hit.Position - origin).Magnitude
			local half = if not handTurned then depth / 2 elseif way[1] ~= 0 then halfX else halfZ
			local gap = distance - half
			if gap < bestGap and gap > -half then
				bestGap = gap
				bestMove = Vector3.new(way[1], 0, way[2]) * (distance - half - 0.15)
				bestTurn = if handTurned then r else way[3]
				away = Vector3.new(-way[1], 0, -way[2])
			end
		end
	end
	if bestMove then
		x += bestMove.X
		z += bestMove.Z
		r = bestTurn
		snapped = true
	end
	return Vector3.new(x, at.Y, z), r, snapped, if bestMove then away else nil
end

-- A wall thing's height lines up with the nearest neighbour wall thing's, else
-- whole studs
local function snapWall(at: Vector3): Vector3
	local s = selection
	local best, y = ALIGN_WALL, math.floor(at.Y + 0.5)
	for _, other in denRecord().placed or {} do
		if (s and other.uid == s.uid) or other.s ~= "wall" then
			continue
		end
		local d = math.abs((other.y or 0) - at.Y)
		local near = math.abs(other.x - at.X) + math.abs(other.z - at.Z) < 30
		if near and d < best then
			best, y = d, other.y
		end
	end
	return Vector3.new(at.X, y, at.Z)
end

-- Where the selected thing would go, from what the aim hits
local function findSpot(item: any, hit: RaycastResult, params: RaycastParams): Spot?
	local frame = DenSpace.frame(ownIndex())
	local level = denShape()
	local normal = hit.Normal
	local surface = if normal.Y > 0.6 then "floor" elseif normal.Y < -0.6 then "ceiling" else "wall"
	local position = hit.Position
	if not table.find(item.kinds, surface) then
		if table.find(item.kinds, "floor") then
			-- A floor thing aimed at a wall or a ceiling drops to the floor below
			local down = workspace:Raycast(position + normal * 1.5, Vector3.new(0, -60, 0), params)
			-- Aimed at the side of a placed thing by the pool or the garden, the drop in
			-- front of it falls into the hole: then it goes on that thing's top
			-- (playtest 2026-10-13)
			local dropped = down
			local onIt = uidOf(hit.Instance) ~= nil
			if
				onIt
				and (
					dropped == nil
					or dropped.Normal.Y <= 0.6
					or not DenSpace.check(level, item, "floor", DenSpace.toLocal(frame, dropped.Position)).ok
				)
			then
				local top = workspace:Raycast(
					position - normal * 0.6 + Vector3.new(0, 8, 0),
					Vector3.new(0, -12, 0),
					params
				)
				if top and top.Normal.Y > 0.6 and uidOf(top.Instance) ~= nil then
					down = top
				end
			end
			if down == nil or down.Normal.Y <= 0.6 then
				return nil
			end
			surface, position, normal = "floor", down.Position, down.Normal
		elseif table.find(item.kinds, "ceiling") then
			-- A ceiling thing aimed at the floor or a wall rises to the vault above: the
			-- editor view always looks down (VIEW_PITCH), so the ceiling itself is never
			-- under the aim (PC 2026-10-19 round 2, DP3: the Jellyfish Lamp couldn't be
			-- placed at all)
			local up = workspace:Raycast(position + normal * 1.5, Vector3.new(0, 80, 0), params)
			if up == nil or up.Normal.Y >= -0.6 then
				return {
					ok = false,
					surface = "ceiling",
					at = DenSpace.toLocal(frame, position),
					turn = yaw,
					why = "Aim at the ceiling",
				}
			end
			surface, position, normal = "ceiling", up.Position, up.Normal
		else
			local local0 = DenSpace.toLocal(frame, position)
			return {
				ok = false,
				surface = surface,
				at = local0,
				turn = yaw,
				why = if table.find(item.kinds, "wall") then "Aim at a wall" else "Aim at the ceiling",
			}
		end
	end
	local at = DenSpace.toLocal(frame, position)
	local turn = yaw
	if surface == "floor" then
		-- Through a joint between flagstones the ray reaches the rock under the
		-- deck: lift it onto the deck (playtest 2026-10-13)
		local storey = DenSpace.storeyAt(at.Y)
		if storey then
			local deck = DenSpace.storey(storey).deck
			if at.Y < deck - 0.1 and DenSpace.nearDeck(level, storey, at.X, at.Z) then
				at = Vector3.new(at.X, deck, at.Z)
			end
		end
		at = Vector3.new(snapHalf(at.X), math.floor(at.Y * 100 + 0.5) / 100, snapHalf(at.Z))
	elseif surface == "wall" then
		-- Faces out of the rock: its look is the wall's normal, flattened
		local flat = Vector3.new(normal.X, 0, normal.Z)
		if flat.Magnitude < 1e-3 then
			return nil
		end
		local look = frame:VectorToObjectSpace(flat.Unit)
		turn = math.deg(math.atan2(-look.X, -look.Z))
		at = Vector3.new(at.X, snapHalf(at.Y), at.Z)
	end
	local s = selection
	local function valid(where: Vector3): DenSpace.Check
		local check = DenSpace.check(level, item, surface, where)
		if check.ok and surface == "floor" then
			check = DenSpace.resting(level, denRecord().placed or {}, where, if s then s.uid else nil)
		end
		return check
	end
	-- Snapping: the snapped spot when it's allowed, else the free one
	local snapped = false
	if
		snapOn
		and surface == "floor"
		and at.Y < (DenSpace.storey(DenSpace.storeyAt(at.Y) or 1).deck + 0.3)
	then
		local snapAt, snapTurn, did, away = snapFloor(item, at, turn)
		-- Backed onto a pillar, the piece sat in the pillar's deck hole and was
		-- refused (PC overnight 2026-10-14): nudge it straight out until it fits
		if did and away and not valid(snapAt).ok then
			for step = 1, 8 do
				local nudged = snapAt + away * (0.5 * step)
				if valid(nudged).ok then
					snapAt = nudged
					break
				end
			end
		end
		if did and valid(snapAt).ok then
			at, turn, snapped = snapAt, snapTurn, true
		end
	elseif snapOn and surface == "wall" then
		local snapAt = snapWall(at)
		if snapAt ~= at and valid(snapAt).ok then
			at, snapped = snapAt, true
		end
	end
	local check = valid(at)
	local ok, why = check.ok, check.why
	if ok and s and s.uid == nil then
		if inTray(item.id) <= 0 then
			ok, why = false, `No {item.name} left`
		elseif #(denRecord().placed or {}) >= capacity() then
			ok, why = false, `Your den holds {capacity()} things · upgrade it for more`
		end
	end
	return { ok = ok, surface = surface, at = at, turn = turn % 360, why = why, snapped = snapped }
end

local function showGhost(item: any, at: Spot)
	local key = `{item.id}|{at.surface}|{denRecord().glow}`
	if key ~= ghostKey then
		clearGhost()
		local model = DenItems.build(item, glowColor(), at.surface)
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CanQuery = false
				descendant.Transparency = math.max(descendant.Transparency, 0.4)
				if descendant.Name == "Root" then
					descendant.Transparency = 1
				end
			elseif descendant:IsA("Light") then
				descendant.Enabled = false
			end
		end
		model.Parent = ghostFolder
		ghost = model
		ghostKey = key
	end
	local model = ghost
	if model then
		local frame = DenSpace.frame(ownIndex())
		model:PivotTo(
			DenSpace.spot(frame, at.at.X, at.at.Y, at.at.Z) * CFrame.Angles(0, math.rad(at.turn), 0)
		)
		ghostLight.Adornee = model
		ghostLight.OutlineColor = if at.ok then GOOD else BAD
		ghostLight.FillColor = if at.ok then GOOD else BAD
	end
end

-- A message from a key press (L with nothing to lay out) is held a moment; the
-- aim's own line is written every frame and wiped it at once, so L seemed to do
-- nothing (PC playtest 2026-10-14, B2)
local statusHeldUntil = 0

local function setStatus(text: string, color: Color3?, hold: number?)
	if hold then
		statusHeldUntil = os.clock() + hold
	elseif os.clock() < statusHeldUntil then
		return
	end
	statusLabel.Text = text
	statusLabel.TextColor3 = color or Ui.color.muted
end

local function step()
	if not active then
		return
	end
	if not insideOwnDen() then
		BuildController.stop()
		return
	end
	-- The den shop open over Build mode: nothing is aimed until it closes
	if shopping then
		if MenuController.isOpen() then
			return
		end
		shopping = false
		panel.Visible = true
		bind()
		BuildController.refresh()
	end
	-- A held turn
	if turning ~= 0 and os.clock() >= nextTurn then
		yaw = (yaw + turning * turnStep()) % 360
		handTurned = true
		nextTurn = os.clock() + TURN_REPEAT
	end
	local params = rayParams()
	local ray = aimRay()
	local hit = workspace:Raycast(ray.Origin, ray.Direction * REACH, params)
	-- Only the storey being viewed: through a shaft's mouth the aim reached the deck
	-- below and placed there (PC 2026-10-16, phone)
	if
		hit
		and DenSpace.storeyAt(DenSpace.toLocal(DenSpace.frame(ownIndex()), hit.Position).Y) ~= view.storey
	then
		hit = nil
	end
	lastFloor = if hit and hit.Normal.Y > 0.6
		then DenSpace.toLocal(DenSpace.frame(ownIndex()), hit.Position)
		else nil
	local s = selection
	if s ~= nil then
		-- What the aim rests on under the picked thing (hidden from the ray)
		underUid = uidOf(if hit then hit.Instance else nil)
	end
	if s == nil then
		-- Nothing picked: aim at a placed thing to pick it up
		spot = nil
		local uid, model = uidOf(if hit then hit.Instance else nil)
		aimedUid = uid
		underUid = uid
		aimLight.Adornee = model
		local aimedItem = if model then Dens.itemsById[model.Name] else nil
		aimedSet = if aimedItem and aimedItem.set and Dens.layouts[aimedItem.set] then aimedItem.set else nil
		if model then
			local item = aimedItem
			setStatus(
				`{if item then item.name else "A thing"} · {if Input.isTouch()
					then "PICK UP to move it"
					elseif Input.isGamepad() then "RT to move it · X to put it away"
					else "LEFT CLICK to move it · X to put it away"}`,
				PICK
			)
		else
			setStatus(
				if #trayIds() > 0
					then "Pick a thing from the tray, or aim at one you've placed"
					else `Your tray is empty · {if Input.isGamepad() then "Y · SHOP" else "SHOP"} buys things for it`
			)
		end
		return
	end
	aimLight.Adornee = nil
	aimedUid = nil
	aimedSet = nil
	local item = Dens.itemsById[s.id]
	if item == nil then
		select(nil)
		return
	end
	local found = if hit then findSpot(item, hit, params) else nil
	spot = found
	if found == nil then
		clearGhost()
		setStatus(`{item.name} · aim inside your den`)
		return
	end
	showGhost(item, found)
	if found.ok then
		setStatus(
			`{item.name} · {found.surface} · {math.floor(found.turn + 0.5)}°{if found.snapped
				then " · snapped"
				else ""}`,
			GOOD
		)
	else
		setStatus(`{item.name} · {found.why or "can't go there"}`, BAD)
	end
end

-- Every placement gets an answer: the server either changes the den or says why
-- not, and if neither has happened a second later the bar says so (PC 2026-10-16
-- round 2, D6: two clicks with a green ghost placed nothing and said nothing)
local function placedSignature(): string
	local parts = {}
	for _, p in denRecord().placed or {} do
		table.insert(parts, `{p.uid}:{p.x}:{p.y}:{p.z}:{p.r}`)
	end
	return table.concat(parts, ",")
end

local function expectAnswer(what: string)
	local before = placedSignature()
	task.delay(1.2, function()
		if active and placedSignature() == before then
			setStatus(`{what} didn't go down · try again`, BAD, 2.5)
		end
	end)
end

local function pickUp(uid: number): boolean
	for _, placement in denRecord().placed or {} do
		if placement.uid == uid then
			yaw = placement.r or 0
			select({ id = placement.id, uid = uid })
			pickedAt = os.clock()
			Sfx.play("UiOpen", { volume = 0.4, pitch = 1.2 })
			return true
		end
	end
	return false
end

local function place()
	local s = selection
	if s == nil then
		-- Pick up what's aimed at
		local uid = aimedUid
		if uid then
			pickUp(uid)
		end
		return
	end
	-- A second click (tap, RT) straight after picking up a stacked thing steps down
	-- to the thing it stands on: the aim passes through the picked one to it (PC
	-- 2026-10-16 round 2, B4: a piece with something on it couldn't be aimed at)
	local under = underUid
	if s.uid and under and under ~= s.uid and os.clock() - pickedAt < STEP_DOWN then
		for _, p in DenSpace.stackOn(denRecord().placed or {}, under) do
			if p.uid == s.uid then
				select(nil)
				pickUp(under)
				setStatus("Picked the one underneath · its stack comes with it", PICK, 2)
				return
			end
		end
	end
	local at = spot
	if at == nil or not at.ok then
		Sfx.play("TooBig", { volume = 0.35 })
		return
	end
	local item = Dens.itemsById[s.id]
	expectAnswer(if item then item.name else "It")
	if s.uid then
		ClientState.request("DenMove", s.uid, at.surface, at.at.X, at.at.Y, at.at.Z, at.turn)
		select(nil)
	else
		ClientState.request("DenPlace", s.id, at.surface, at.at.X, at.at.Y, at.at.Z, at.turn)
		-- Keep the same thing picked while there's more in the tray (the server's
		-- answer arrives in the state; the count is checked again as you aim)
		if inTray(s.id) <= 1 then
			select(nil)
		end
	end
	Sfx.play("Shell", { volume = 0.45, pitch = 0.8 })
end

local function putAway()
	local s = selection
	local uid = if s and s.uid then s.uid else aimedUid
	if uid then
		ClientState.request("DenStore", uid)
		select(nil)
		Sfx.play("UiOpen", { volume = 0.35, pitch = 0.8 })
	end
end

-- The set whose starter layout L would lay out: the picked thing's, or the aimed one's
local function layoutSet(): string?
	local s = selection
	local item = if s then Dens.itemsById[s.id] else nil
	if item and item.set and Dens.layouts[item.set] then
		return item.set
	end
	return aimedSet
end

-- Lays out a set round the floor spot aimed at, its front toward the camera
local function layOut()
	local setId = layoutSet()
	local anchor = lastFloor
	if anchor == nil and selection == nil and aimedUid then
		-- Aimed at a placed piece (L lays out its set): the aim hits the piece, not
		-- the floor, so lay it out round where that piece stands (PC playtest
		-- 2026-10-14, B2: L on an aimed piece did nothing)
		for _, placement in denRecord().placed or {} do
			if placement.uid == aimedUid then
				anchor = Vector3.new(placement.x, placement.y, placement.z)
				break
			end
		end
	end
	if setId == nil then
		Sfx.play("TooBig", { volume = 0.35 })
		setStatus("Pick a piece of a furniture set first", BAD, 2.5)
		return
	end
	if anchor == nil then
		Sfx.play("TooBig", { volume = 0.35 })
		setStatus("Aim at your floor to lay the set out there", BAD, 2.5)
		return
	end
	local frame = DenSpace.frame(ownIndex())
	local camera = DenSpace.toLocal(frame, workspace.CurrentCamera.CFrame.Position)
	local facing = math.deg(math.atan2(-(camera.X - anchor.X), camera.Z - anchor.Z)) % 360
	ClientState.request("DenLayout", setId, anchor.X, anchor.Y, anchor.Z, facing)
	select(nil)
	Sfx.play("Shell", { volume = 0.5, pitch = 0.7 })
end

local function toggleSnap()
	snapOn = not snapOn
	if snapOn then
		yaw = math.floor(yaw / SNAP_TURN + 0.5) * SNAP_TURN % 360
	end
	Sfx.play("UiOpen", { volume = 0.3, pitch = if snapOn then 1.2 else 0.9 })
	BuildController.refresh()
end

local function cycle(by: number)
	local ids = pickableIds()
	if #ids == 0 then
		return
	end
	local s = selection
	local at = if s and s.uid == nil then table.find(ids, s.id) else nil
	local nextIndex = if at then (at - 1 + by) % #ids + 1 elseif by > 0 then 1 else #ids
	select({ id = ids[nextIndex] })
end

local function tile(parent: Instance, id: string, order: number)
	local item = Dens.itemsById[id]
	local picked = selection ~= nil
		and (selection :: Selection).id == id
		and (selection :: Selection).uid == nil
	local empty = inTray(id) <= 0
	local button = Instance.new("TextButton")
	button.Name = id
	button.LayoutOrder = order
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(156, 64)
	button.BackgroundColor3 = if picked then Color3.fromRGB(30, 70, 90) else Ui.color.track
	button.BackgroundTransparency = if picked then 0.05 elseif empty then 0.7 else 0.3
	button.BorderSizePixel = 0
	Ui.corner(button, UDim.new(0, 10))
	Ui.stroke(
		button,
		if picked then Ui.color.haul else item.color,
		if picked then 0 else 0.55,
		if picked then 2 else 1
	)
	-- Its picture (owner, 2026-10-18: the shop "needs pics of the items"), made as
	-- the tile scrolls into view (ItemPhoto)
	local picture = Instance.new("Frame")
	picture.Name = "Picture"
	picture.Size = UDim2.fromOffset(52, 52)
	picture.Position = UDim2.fromOffset(6, 6)
	picture.BackgroundColor3 = Color3.fromRGB(14, 30, 44)
	picture.BackgroundTransparency = if empty then 0.6 else 0.2
	picture.BorderSizePixel = 0
	Ui.corner(picture, UDim.new(0, 8))
	picture.Parent = button
	ItemPhoto.attach(picture, item, glowColor(), trayFrame)
	local name = Ui.label(
		button,
		"Name",
		item.name,
		Ui.FONT_BOLD,
		13,
		if empty then Ui.color.muted else Ui.color.text,
		UDim2.new(1, -70, 0, 30),
		UDim2.fromOffset(64, 4)
	)
	name.TextWrapped = true
	name.TextYAlignment = Enum.TextYAlignment.Top
	local count = Ui.label(
		button,
		"Count",
		`×{inTray(id)}  ·  {table.concat(item.kinds, "/")}`,
		Ui.FONT_SEMI,
		11,
		Ui.color.muted,
		UDim2.new(1, -70, 0, 14),
		UDim2.new(0, 64, 1, -19)
	)
	count.TextXAlignment = Enum.TextXAlignment.Left
	button.Activated:Connect(function()
		buttonClock = os.clock()
		if not trayDrag and not empty then
			select({ id = id })
		end
	end)
	-- Pressed with the mouse, it can be dragged straight onto the floor
	button.MouseButton1Down:Connect(function()
		if not Input.isTouch() and not empty then
			select({ id = id })
			trayDrag = true
		end
	end)
	button.Parent = parent
end

-- Redraws the tray and the header
function BuildController.refresh()
	if not active then
		return
	end
	local placed = #(denRecord().placed or {})
	header.Text = `BUILD MODE  ·  {placed} / {capacity()} placed  ·  SNAP {if snapOn then "ON" else "OFF"}`
	if snapButton then
		snapButton.Text = if snapOn then "SNAP ON" else "SNAP OFF"
	end
	for _, child in trayFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local ids = trayIds()
	for i, id in ids do
		tile(trayFrame, id, i)
	end
	local s = selection
	if s and s.uid == nil and inTray(s.id) <= 0 then
		select(nil)
	end
end

local function controlsText(): string
	if Input.isTouch() then
		return "Tap the floor to place, a thing to pick it up · drag to turn the view, pinch to zoom · FLOOR changes storey"
	elseif Input.isGamepad() then
		return "Left stick pan · right stick turn view · RT place / pick up · LT drop · LB RB turn · D-pad: pick, snap, lay out · A floor · X put away · Y shop · B done"
	end
	return "Click to place · drag things (from the tray too) · RIGHT-DRAG turn view · WASD pan · wheel zoom · SPACE / C floor · R F turn · G snap · L lay out · X put away · B done"
end

-- The skin effects round your own fish (Shared/SkinFx: mist, rings, halos) stop
-- while it's hidden for editing, and start again after
local stilled: { Instance } = {}
local function stillEffects(still: boolean)
	if not still then
		for _, effect in stilled do
			if effect.Parent then
				(effect :: any).Enabled = true
			end
		end
		table.clear(stilled)
		return
	end
	local character = Players.LocalPlayer.Character
	if character == nil then
		return
	end
	for _, effect in character:GetDescendants() do
		if
			(effect:IsA("ParticleEmitter") or effect:IsA("Trail") or effect:IsA("Beam"))
			and effect:GetAttribute("ShadeEffect")
			and (effect :: any).Enabled
		then
			(effect :: any).Enabled = false
			table.insert(stilled, effect)
		end
	end
end

-- Opens the den shop over Build mode (bought things land in the tray)
local function openShop()
	if not active or shopping then
		return
	end
	select(nil)
	unbind()
	shopping = true
	orbiting, dragging, trayDrag = false, false, false
	aimLight.Adornee = nil
	aimedUid = nil
	panel.Visible = false
	MenuController.openDenShop()
end

function bind()
	ContextActionService:BindActionAtPriority("ApexBuildPlace", function(_, inputState, input: InputObject)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		-- A click on the tray is the tray's
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if overPanel(input.Position) then
				return Enum.ContextActionResult.Pass
			end
			-- Pressed on a placed thing: it comes up with the pointer, and goes down
			-- where the button is let go (a quick click leaves it picked up)
			if selection == nil and aimedUid then
				place()
				dragging = selection ~= nil
				pressAt = UserInputService:GetMouseLocation()
				pressClock = os.clock()
				return Enum.ContextActionResult.Sink
			end
		end
		place()
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	-- The right button: held and dragged, it turns the view; a click drops the
	-- thing picked (let go in the InputEnded handler)
	ContextActionService:BindActionAtPriority("ApexBuildDrop", function(_, inputState, input)
		if inputState == Enum.UserInputState.Begin then
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				orbiting = true
				orbitMoved = 0
			else
				select(nil)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)
	ContextActionService:BindActionAtPriority(
		"ApexBuildFloor",
		function(_, inputState, input)
			if inputState == Enum.UserInputState.Begin then
				local key = input.KeyCode
				if key == Enum.KeyCode.ButtonA then
					-- One button: down a storey, and back to the top from the deepest
					local deepest = DenSpace.storeys(denShape())
					changeFloor(if view.storey >= deepest then 1 - view.storey else 1)
				else
					changeFloor(if key == Enum.KeyCode.Space or key == Enum.KeyCode.PageUp then -1 else 1)
				end
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		PRIORITY,
		Enum.KeyCode.Space,
		Enum.KeyCode.C,
		Enum.KeyCode.PageUp,
		Enum.KeyCode.PageDown,
		Enum.KeyCode.ButtonA
	)
	ContextActionService:BindActionAtPriority("ApexBuildTurn", function(_, inputState, input)
		local by = if input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1
		if inputState == Enum.UserInputState.Begin then
			yaw = (yaw + by * turnStep()) % 360
			handTurned = true
			turning = by
			nextTurn = os.clock() + 0.35
		elseif inputState == Enum.UserInputState.End and turning == by then
			turning = 0
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.KeyCode.R, Enum.KeyCode.F, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
	ContextActionService:BindActionAtPriority("ApexBuildPick", function(_, inputState, input)
		if inputState == Enum.UserInputState.Begin then
			local back = input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.DPadLeft
			cycle(if back then -1 else 1)
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight)
	ContextActionService:BindActionAtPriority("ApexBuildAway", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			putAway()
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.KeyCode.X, Enum.KeyCode.Delete, Enum.KeyCode.ButtonX)
	ContextActionService:BindActionAtPriority("ApexBuildDone", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			BuildController.stop()
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.KeyCode.B, Enum.KeyCode.ButtonB)
	ContextActionService:BindActionAtPriority("ApexBuildSnap", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggleSnap()
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.KeyCode.G, Enum.KeyCode.DPadUp)
	ContextActionService:BindActionAtPriority("ApexBuildLayout", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			layOut()
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.KeyCode.L, Enum.KeyCode.DPadDown)
	-- Y opens the den shop (and, sunk, the stall menu and the HUD's D-pad menus wait
	-- till you're done). A second sink on Y bound after it took Y first and the shop
	-- never opened (PC 2026-10-17, DS1)
	ContextActionService:BindActionAtPriority("ApexBuildShop", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			openShop()
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.KeyCode.ButtonY)
end

function unbind()
	for _, name in
		{
			"ApexBuildPlace",
			"ApexBuildDrop",
			"ApexBuildFloor",
			"ApexBuildTurn",
			"ApexBuildPick",
			"ApexBuildAway",
			"ApexBuildDone",
			"ApexBuildSnap",
			"ApexBuildLayout",
			"ApexBuildShop",
		}
	do
		ContextActionService:UnbindAction(name)
	end
end

function BuildController.isActive(): boolean
	return active
end

-- The tray's size and place for the device in use now (a phone's is taller, for
-- its row of buttons, and sits higher; playtest 2026-10-13: laid out for a mouse
-- and then shown with the phone's row, the row hung over the HAUL card)
local function layoutTray()
	local touch = Input.isTouch()
	touchRow.Visible = touch
	controlsLabel.Visible = not touch
	touchHint.Visible = touch and active
	local tray = trayButton
	if tray then
		tray.Text = if trayFolded then "TRAY ▲" else "TRAY ▼"
	end
	local shop = shopButton
	if shop then
		shop.Visible = not touch
		shop.Text = if Input.isGamepad() then "Y · SHOP" else "SHOP"
	end
	statusLabel.Size = if touch then UDim2.new(0.62, -14, 0, 18) else UDim2.new(0.62, -122, 0, 18)
	if not touch then
		panel.Size = UDim2.fromOffset(860, 146)
		panel.Position = UDim2.new(0.5, 0, 1, -120)
		trayFrame.Visible = true
		return
	end
	-- Full width (in the gui's scaled pixels), along the bottom edge
	local scale = Ui.scaleOf(gui)
	local camera = workspace.CurrentCamera
	local width = math.min(camera.ViewportSize.X / scale - 24, 980)
	trayFrame.Visible = not trayFolded
	panel.Size = UDim2.fromOffset(width, if trayFolded then 82 else 160)
	panel.Position = UDim2.new(0.5, 0, 1, -6)
	touchRow.Position = UDim2.new(0, 10, 0, if trayFolded then 34 else 112)
	touchHint.Position = UDim2.new(0.5, 0, 0, math.ceil((Ui.topInset() + 8) / scale))
end

relayout = layoutTray

-- Folds or opens a phone's tray
local function foldTray(folded: boolean)
	if trayFolded == folded then
		return
	end
	trayFolded = folded
	layoutTray()
end

-- Hides (or brings back) the swimming HUD while editing
local function hideSwimHud(hidden: boolean)
	if not hidden then
		for _, screen in hiddenGuis do
			screen.Enabled = true
		end
		table.clear(hiddenGuis)
		return
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	for _, name in HIDE_WHILE_BUILDING do
		local screen = playerGui:FindFirstChild(name)
		if screen and screen:IsA("ScreenGui") and screen.Enabled then
			screen.Enabled = false
			table.insert(hiddenGuis, screen)
		end
	end
end

function BuildController.start()
	if active then
		return
	end
	if ownIndex() == 0 or not insideOwnDen() then
		Sfx.play("TooBig", { volume = 0.3 })
		return
	end
	MenuController.close()
	active = true
	Input.building = true
	Input.editing = true
	MenuController.building = true
	turning = 0
	startView()
	CameraController.override = viewCFrame
	CameraController.hideFish = true
	stillEffects(true)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	controlsLabel.Text = controlsText()
	touchHint.Text = controlsText()
	trayFolded = false
	table.clear(shownThisSession)
	layoutTray()
	hideSwimHud(true)
	panel.Visible = true
	bind()
	select(nil)
	BuildController.refresh()
	Sfx.play("UiOpen", { volume = 0.5 })
end

function BuildController.stop()
	if not active then
		return
	end
	active = false
	Input.building = false
	Input.editing = false
	CameraController.override = nil
	CameraController.overrideFov = nil
	CameraController.hideFish = false
	stillEffects(false)
	orbiting, dragging, trayDrag = false, false, false
	tapAt, pinchFrom = nil, nil
	MenuController.building = false
	if shopping then
		shopping = false
		MenuController.close()
	end
	select(nil)
	aimLight.Adornee = nil
	aimedUid = nil
	panel.Visible = false
	touchHint.Visible = false
	hideSwimHud(false)
	unbind()
end

function BuildController.toggle()
	if active then
		BuildController.stop()
	else
		BuildController.start()
	end
end

local function buildGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.screen("Build", playerGui, 8)
	local touch = Input.isTouch()
	panel = Ui.panel(
		gui,
		"Tray",
		UDim2.fromOffset(if touch then 680 else 860, if touch then 172 else 146),
		UDim2.new(0.5, 0, 1, if touch then -150 else -120),
		Vector2.new(0.5, 1)
	)
	panel.Visible = false
	header = Ui.label(
		panel,
		"Header",
		"BUILD MODE",
		Ui.FONT_HEAVY,
		15,
		Ui.color.haul,
		UDim2.new(0.5, 0, 0, 18),
		UDim2.fromOffset(14, 8)
	)
	header.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel = Ui.label(
		panel,
		"Status",
		"",
		Ui.FONT_SEMI,
		13,
		Ui.color.muted,
		UDim2.new(0.62, -14, 0, 18),
		UDim2.new(0.38, 0, 0, 8)
	)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Right
	statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	-- The den shop, at the bar's top-right corner (a phone has it in its row)
	local shop = Ui.button(panel, "Shop", "SHOP", UDim2.fromOffset(96, 24), UDim2.new(1, -106, 0, 6), "gold")
	shop.TextSize = 13
	shop.Selectable = false
	shop.Activated:Connect(function()
		buttonClock = os.clock()
		openShop()
	end)
	shopButton = shop
	trayFrame = Instance.new("ScrollingFrame")
	trayFrame.Name = "Things"
	trayFrame.BackgroundTransparency = 1
	trayFrame.BorderSizePixel = 0
	trayFrame.Position = UDim2.fromOffset(10, 32)
	trayFrame.Size = UDim2.new(1, -20, 0, 76)
	trayFrame.ScrollingDirection = Enum.ScrollingDirection.X
	trayFrame.AutomaticCanvasSize = Enum.AutomaticSize.X
	trayFrame.CanvasSize = UDim2.new()
	trayFrame.ScrollBarThickness = 4
	trayFrame.Selectable = false
	trayFrame.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = trayFrame
	controlsLabel = Ui.label(
		panel,
		"Controls",
		"",
		Ui.FONT_SEMI,
		12,
		Ui.color.muted,
		UDim2.new(1, -28, 0, 16),
		UDim2.new(0, 14, 0, 112)
	)
	controlsLabel.TextXAlignment = Enum.TextXAlignment.Left
	controlsLabel.TextTruncate = Enum.TextTruncate.AtEnd
	-- The phone's buttons
	touchRow = Instance.new("Frame")
	touchRow.Name = "TouchButtons"
	touchRow.BackgroundTransparency = 1
	touchRow.Size = UDim2.new(1, -20, 0, 40)
	touchRow.Position = UDim2.new(0, 10, 0, 126)
	touchRow.Visible = false
	touchRow.Parent = panel
	type TouchButton = { text: string, style: Ui.ButtonStyle, run: () -> () }
	local buttons: { TouchButton } = {
		{ text = "PLACE", style = "primary", run = place },
		{
			text = "TURN",
			style = "secondary",
			run = function()
				yaw = (yaw + 45) % 360
				handTurned = true
			end,
		},
		{ text = "SNAP ON", style = "secondary", run = toggleSnap },
		{
			text = "FLOOR",
			style = "secondary",
			run = function()
				local deepest = DenSpace.storeys(denShape())
				changeFloor(if view.storey >= deepest then 1 - view.storey else 1)
			end,
		},
		{ text = "LAY OUT", style = "secondary", run = layOut },
		{ text = "PUT AWAY", style = "secondary", run = putAway },
		{ text = "SHOP", style = "gold", run = openShop },
		{
			text = "DROP",
			style = "secondary",
			run = function()
				select(nil)
			end,
		},
		{
			text = "TRAY ▼",
			style = "secondary",
			run = function()
				foldTray(not trayFolded)
			end,
		},
		{ text = "DONE", style = "gold", run = BuildController.stop },
	}
	local share = 1 / #buttons
	for i, spec in buttons do
		local button = Ui.button(
			touchRow,
			spec.text,
			spec.text,
			UDim2.new(share, -6, 1, 0),
			UDim2.new((i - 1) * share, 0, 0, 0),
			spec.style
		)
		button.TextSize = 13
		button.Activated:Connect(function()
			buttonClock = os.clock()
			spec.run()
		end)
		if spec.text == "SNAP ON" then
			snapButton = button
		elseif spec.text == "TRAY ▼" then
			trayButton = button
		end
	end
	-- The chip that says B builds, while you're in your own den
	hintChip = Ui.label(
		gui,
		"BuildHint",
		"B · BUILD MODE",
		Ui.FONT_BOLD,
		13,
		Ui.color.haul,
		UDim2.fromOffset(170, 24),
		UDim2.new(0.5, 0, 1, -262)
	)
	hintChip.AnchorPoint = Vector2.new(0.5, 0)
	hintChip.TextStrokeTransparency = 0.5
	hintChip.Visible = false
	-- A phone's help line, at the top while editing
	touchHint = Ui.label(
		gui,
		"TouchHint",
		"",
		Ui.FONT_SEMI,
		13,
		Ui.color.text,
		UDim2.fromOffset(720, 20),
		UDim2.new(0.5, 0, 0, 44)
	)
	touchHint.AnchorPoint = Vector2.new(0.5, 0)
	touchHint.TextXAlignment = Enum.TextXAlignment.Center
	touchHint.TextStrokeTransparency = 0.45
	touchHint.TextWrapped = true
	touchHint.Visible = false
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if active then
			layoutTray()
		end
	end)
end

function BuildController.init()
	buildGui()
	ghostFolder = Instance.new("Folder")
	ghostFolder.Name = "BuildGhost"
	ghostFolder.Parent = workspace
	ghostLight = Instance.new("Highlight")
	ghostLight.Name = "BuildGhost"
	ghostLight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	ghostLight.FillTransparency = 0.78
	ghostLight.OutlineTransparency = 0
	ghostLight.Parent = ghostFolder
	aimLight = Instance.new("Highlight")
	aimLight.Name = "BuildAim"
	aimLight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	aimLight.FillColor = PICK
	aimLight.FillTransparency = 0.8
	aimLight.OutlineColor = PICK
	aimLight.Parent = ghostFolder
end

function BuildController.startController()
	BuildController.init()
	-- Messages while building show on the bar's status line for a few seconds
	HudController.buildNote = function(text: string, color: Color3): boolean
		if not active then
			return false
		end
		setStatus(text, color, 3.5)
		return true
	end
	MenuController.startBuild = BuildController.start
	ContextActionService:BindAction("ApexBuild", function(_, inputState)
		-- (nor under the full map: B in the den started Build mode beneath it, PC
		-- 2026-10-19 round 2, UI3)
		if
			inputState ~= Enum.UserInputState.Begin
			or Input.locked
			or MenuController.isOpen()
			or MapController.isOpen()
		then
			return Enum.ContextActionResult.Pass
		end
		if not active and not insideOwnDen() then
			return Enum.ContextActionResult.Pass
		end
		BuildController.toggle()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.B)
	ClientState.changed:connect(function()
		if active then
			BuildController.refresh()
		end
		-- A moved thing comes back where the server put it
		if hiddenUid and (selection == nil or (selection :: Selection).uid ~= hiddenUid) then
			hide(nil)
		end
	end)
	RunService.RenderStepped:Connect(step)
	-- Letting go of the mouse: a dragged thing goes down (or back), a right click
	-- that didn't turn the view drops what's picked
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if not active then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 and orbiting then
			orbiting = false
			if orbitMoved < 6 then
				select(nil)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			local mouse = UserInputService:GetMouseLocation()
			if trayDrag then
				trayDrag = false
				local s = selection
				local at = spot
				if s and s.uid == nil and at and not overPanel(mouse - GuiService:GetGuiInset()) then
					if at.ok then
						place()
						select(nil)
					else
						Sfx.play("TooBig", { volume = 0.35 })
					end
				end
			elseif dragging then
				dragging = false
				local moved = (mouse - pressAt).Magnitude > 6 or os.clock() - pressClock > 0.35
				if moved then
					local at = spot
					if at and at.ok then
						place()
					else
						-- Can't go there: it goes back where it was
						select(nil)
						Sfx.play("TooBig", { volume = 0.35 })
						setStatus("It can't go there · put back", BAD, 2)
					end
				end
			end
		end
	end)
	-- A phone taps the floor to place, or a placed thing to pick it up, and pinches
	-- to zoom. A tap on the bar or a tray tile comes here too, unprocessed (PC
	-- 2026-10-16 round 2, B1: picking a tile, TRAY and TURN each placed the thing
	-- picked as well), so a tap over the bar, or one that pressed a Build button
	-- (either way round), is the button's alone
	UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processed: boolean)
		if not active or processed or overPanel(position) then
			return
		end
		local at = os.clock()
		task.delay(0.05, function()
			if not active or math.abs(buttonClock - at) < 0.3 then
				return
			end
			tapAt = position
			step()
			place()
		end)
	end)
	UserInputService.TouchPinch:Connect(
		function(_, scale: number, _, pinchState: Enum.UserInputState, processed)
			if not active or processed then
				return
			end
			if pinchState == Enum.UserInputState.Begin then
				pinchFrom = view.distance
			elseif pinchState == Enum.UserInputState.Change and pinchFrom and scale > 0 then
				view.distance = math.clamp((pinchFrom :: number) / scale, VIEW_ZOOM[1], VIEW_ZOOM[2])
			else
				pinchFrom = nil
			end
		end
	)
	RunService.Heartbeat:Connect(function()
		local show = not active
			and not Input.locked
			and not Input.isTouch()
			and not Input.isGamepad()
			and not MenuController.isOpen()
			and not MapController.isOpen()
			and not MenuController.denHintShown()
			and insideOwnDen()
		if hintChip.Visible ~= show then
			hintChip.Visible = show
		end
	end)
end

return BuildController
