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
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local CameraController = require(script.Parent.CameraController)
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
local VIEW_PAN = 26 -- studs a second at the starting zoom
local VIEW_FOCUS_UP = 2 -- the camera looks this far over the deck
local orbiting = false -- the right mouse button held: dragging turns the view
local orbitMoved = 0 -- pixels the mouse moved while orbiting (a click drops instead)
local dragging = false -- a placed thing picked up with the left button held
local trayDrag = false -- a thing pressed in the tray, to be let go on the floor
local pressAt = Vector2.zero
local pressClock = 0
local tapAt: Vector2? = nil -- a phone's last tap: where it aims
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
local hintChip: TextLabel
local touchHint: TextLabel
-- A phone's editor (PC 2026-10-16: the panel sat in the middle third of the screen,
-- the swim stick and BITE / DASH / ITEMS / HEAL stayed up, little floor was left to
-- tap): a slim bar along the bottom whose tray folds away (it folds by itself once
-- a thing is picked), the help line at the top, and the swimming HUD hidden.
local trayFolded = false
local HIDE_ON_TOUCH = {
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
local function trayIds(): { string }
	local list: { string } = {}
	for _, item in Dens.items do
		if inTray(item.id) > 0 then
			table.insert(list, item.id)
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
	local level = denRecord().level or 1
	local rooms = DenSpace.rooms(level, view.storey)
	local bestX, bestZ, bestGap = view.x, view.z, math.huge
	for _, room in rooms do
		local half = math.max(room.x - VIEW_INSET, 0)
		local near, far = math.min(room.z0, room.z1), math.max(room.z0, room.z1)
		-- Inset from the end walls only: insetting both ends of every room left a
		-- gap where two rooms meet that panning never crossed, so the view stopped
		-- at the first room's end (PC 2026-10-16 round 2, D6)
		local z0 = if carriesOn(rooms, room, near) then near else near + VIEW_INSET
		local z1 = if carriesOn(rooms, room, far) then far else far - VIEW_INSET
		if z0 > z1 then
			z0, z1 = (near + far) / 2, (near + far) / 2
		end
		local x = math.clamp(view.x, -half, half)
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
	local deepest = DenSpace.storeys(denRecord().level or 1)
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
	for n = 1, DenSpace.storeys(denRecord().level or 1) do
		local gap = math.abs(here.Y - DenSpace.storey(n).deck)
		if gap < bestGap then
			best, bestGap = n, gap
		end
	end
	view.storey = best
	view.x, view.z = here.X, here.Z
	view.y = DenSpace.storey(best).deck
	clampView()
	local look = workspace.CurrentCamera.CFrame.LookVector
	view.yaw = math.atan2(-look.X, -look.Z)
	view.pitch = math.rad(52)
	view.distance = 45
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
	if orbiting then
		local delta = UserInputService:GetMouseDelta()
		orbitMoved += delta.Magnitude
		look += delta * Config.Tuning.camera.mouseSensitivity
	end
	view.yaw -= look.X
	-- Zoom: the wheel, or a phone's pinch (set in the pinch handler)
	local notches = Input.consumeZoom()
	if notches ~= 0 then
		view.distance = math.clamp(view.distance * (1 - 0.12 * notches), VIEW_ZOOM[1], VIEW_ZOOM[2])
	end
	-- Under the storey's ceiling: zoomed out, the view lowers toward the floor's
	-- far side instead of pressing up into the rock
	local headroom = DenSpace.storey(view.storey).ceiling - view.y - VIEW_FOCUS_UP - 2
	local steepest = VIEW_PITCH[2]
	if view.distance * math.sin(steepest) > headroom then
		steepest = math.max(VIEW_PITCH[1], math.asin(math.clamp(headroom / view.distance, 0, 1)))
	end
	view.pitch = math.clamp(view.pitch + look.Y, VIEW_PITCH[1], steepest)
	-- Pan: WASD or the arrows, or the left stick, across the floor
	local pan = Vector2.zero
	if UserInputService:GetFocusedTextBox() == nil then
		local function key(a: Enum.KeyCode, b: Enum.KeyCode): number
			return if UserInputService:IsKeyDown(a) or UserInputService:IsKeyDown(b) then 1 else 0
		end
		pan += Vector2.new(
			key(Enum.KeyCode.D, Enum.KeyCode.Right) - key(Enum.KeyCode.A, Enum.KeyCode.Left),
			key(Enum.KeyCode.W, Enum.KeyCode.Up) - key(Enum.KeyCode.S, Enum.KeyCode.Down)
		)
	end
	for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
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
	local want = focus - orient.LookVector * view.distance
	-- Out of the rock: the camera stops short of the den's ceiling and walls
	local offset = want - focus
	local hit = workspace:Raycast(focus, offset, viewParams)
	local at = if hit then focus + offset.Unit * math.max(1.5, hit.Distance - 1.2) else want
	return CFrame.lookAt(at, focus)
end

-- Whether a screen point is over the tray (its clicks are the tray's)
local function overPanel(position: Vector3 | Vector2): boolean
	local inset = GuiService:GetGuiInset()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return false
	end
	for _, y in { position.Y, position.Y + inset.Y } do
		for _, object in playerGui:GetGuiObjectsAtPosition(position.X, y) do
			if object:IsDescendantOf(panel) then
				return true
			end
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
	local level = denRecord().level or 1
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
	if s == nil then
		-- Nothing picked: aim at a placed thing to pick it up
		spot = nil
		local uid, model = uidOf(if hit then hit.Instance else nil)
		aimedUid = uid
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
					else "Your tray is empty · buy things in the den menu (E at your pool)"
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

local function place()
	local s = selection
	if s == nil then
		-- Pick up what's aimed at
		local uid = aimedUid
		if uid then
			for _, placement in denRecord().placed or {} do
				if placement.uid == uid then
					yaw = placement.r or 0
					select({ id = placement.id, uid = uid })
					Sfx.play("UiOpen", { volume = 0.4, pitch = 1.2 })
					return
				end
			end
		end
		return
	end
	local at = spot
	if at == nil or not at.ok then
		Sfx.play("TooBig", { volume = 0.35 })
		return
	end
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
	local ids = trayIds()
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
	local button = Instance.new("TextButton")
	button.Name = id
	button.LayoutOrder = order
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(112, 64)
	button.BackgroundColor3 = if picked then Color3.fromRGB(30, 70, 90) else Ui.color.track
	button.BackgroundTransparency = if picked then 0.05 else 0.3
	button.BorderSizePixel = 0
	Ui.corner(button, UDim.new(0, 10))
	Ui.stroke(
		button,
		if picked then Ui.color.haul else item.color,
		if picked then 0 else 0.55,
		if picked then 2 else 1
	)
	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.fromOffset(10, 10)
	swatch.Position = UDim2.fromOffset(8, 9)
	swatch.BackgroundColor3 = item.color
	swatch.BorderSizePixel = 0
	Ui.corner(swatch, UDim.new(1, 0))
	swatch.Parent = button
	local name = Ui.label(
		button,
		"Name",
		item.name,
		Ui.FONT_BOLD,
		13,
		Ui.color.text,
		UDim2.new(1, -26, 0, 30),
		UDim2.fromOffset(22, 3)
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
		UDim2.new(1, -16, 0, 14),
		UDim2.new(0, 8, 1, -19)
	)
	count.TextXAlignment = Enum.TextXAlignment.Left
	button.Activated:Connect(function()
		if not trayDrag then
			select({ id = id })
		end
	end)
	-- Pressed with the mouse, it can be dragged straight onto the floor
	button.MouseButton1Down:Connect(function()
		if not Input.isTouch() then
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
		return "Left stick pan · right stick turn view · RT place / pick up · LT drop · LB RB turn · D-pad: pick, snap, lay out · A floor · X put away · B done"
	end
	return "Click to place · drag things (from the tray too) · RIGHT-DRAG turn view · WASD pan · wheel zoom · SPACE / C floor · R F turn · G snap · L lay out · X put away · B done"
end

local function bind()
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
					local deepest = DenSpace.storeys(denRecord().level or 1)
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
	-- The stall menu and the HUD's D-pad menus wait till you're done
	ContextActionService:BindActionAtPriority("ApexBuildQuiet", function()
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.KeyCode.ButtonY)
end

local function unbind()
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
			"ApexBuildQuiet",
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

-- Hides (or brings back) the swimming HUD while a phone edits
local function hideSwimHud(hidden: boolean)
	if not hidden then
		for _, screen in hiddenGuis do
			screen.Enabled = true
		end
		table.clear(hiddenGuis)
		return
	end
	if not Input.isTouch() then
		return
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	for _, name in HIDE_ON_TOUCH do
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
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	controlsLabel.Text = controlsText()
	touchHint.Text = controlsText()
	trayFolded = false
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
	orbiting, dragging, trayDrag = false, false, false
	tapAt, pinchFrom = nil, nil
	MenuController.building = false
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
				local deepest = DenSpace.storeys(denRecord().level or 1)
				changeFloor(if view.storey >= deepest then 1 - view.storey else 1)
			end,
		},
		{ text = "LAY OUT", style = "secondary", run = layOut },
		{ text = "PUT AWAY", style = "secondary", run = putAway },
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
		button.Activated:Connect(spec.run)
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
	MenuController.startBuild = BuildController.start
	ContextActionService:BindAction("ApexBuild", function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin or Input.locked or MenuController.isOpen() then
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
	-- to zoom
	UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processed: boolean)
		if not active or processed then
			return
		end
		tapAt = position
		step()
		place()
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
