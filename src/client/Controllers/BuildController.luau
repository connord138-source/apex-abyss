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
--               R / F turn · Q / E pick a thing · X put away · B done
--   Controller  RT place / pick up · LT drop it · LB / RB turn · D-pad pick · X put
--               away · B done
--   Phone       aim: drag · PLACE, TURN, PUT AWAY, DONE and the tray's tiles
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
local MapController = require(script.Parent.MapController)
local MenuController = require(script.Parent.MenuController)
local SwimController = require(script.Parent.SwimController)

local Dens = Config.Dens

local BuildController = {}

local REACH = 70 -- how far the aim reaches
local TURN = 15 -- degrees a tap of turn
local TURN_REPEAT = 0.1 -- a held turn repeats this often
local GOOD = Color3.fromRGB(112, 236, 164)
local BAD = Color3.fromRGB(255, 96, 96)
local PICK = Color3.fromRGB(255, 220, 120)
local PRIORITY = 3500

type Selection = { id: string, uid: number? } -- uid: moving a placed thing
type Spot = { ok: boolean, surface: string, at: Vector3, turn: number, why: string? }

local active = false
local selection: Selection? = nil
local yaw = 0
local spot: Spot? = nil
local aimedUid: number? = nil
local turning = 0 -- -1, 0, 1 while a turn is held
local nextTurn = 0
local hiddenUid: number? = nil

local gui: ScreenGui
local panel: Frame
local header: TextLabel
local statusLabel: TextLabel
local controlsLabel: TextLabel
local trayFrame: ScrollingFrame
local touchRow: Frame
local hintChip: TextLabel

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
	if
		UserInputService.MouseEnabled
		and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter
		and not Input.isTouch()
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
	local check = DenSpace.check(level, item, surface, at)
	local ok, why = check.ok, check.why
	local s = selection
	if ok and s and s.uid == nil then
		if inTray(item.id) <= 0 then
			ok, why = false, `No {item.name} left`
		elseif #(denRecord().placed or {}) >= capacity() then
			ok, why = false, `Your den holds {capacity()} things · upgrade it for more`
		end
	end
	return { ok = ok, surface = surface, at = at, turn = turn % 360, why = why }
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

local function setStatus(text: string, color: Color3?)
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
		yaw = (yaw + turning * TURN) % 360
		nextTurn = os.clock() + TURN_REPEAT
	end
	local params = rayParams()
	local ray = aimRay()
	local hit = workspace:Raycast(ray.Origin, ray.Direction * REACH, params)
	local s = selection
	if s == nil then
		-- Nothing picked: aim at a placed thing to pick it up
		spot = nil
		local uid, model = uidOf(if hit then hit.Instance else nil)
		aimedUid = uid
		aimLight.Adornee = model
		if model then
			local item = Dens.itemsById[model.Name]
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
		setStatus(`{item.name} · {found.surface} · {math.floor(found.turn + 0.5)}°`, GOOD)
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
		select({ id = id })
	end)
	button.Parent = parent
end

-- Redraws the tray and the header
function BuildController.refresh()
	if not active then
		return
	end
	local placed = #(denRecord().placed or {})
	header.Text = `BUILD MODE  ·  {placed} / {capacity()} placed`
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
		return "Drag to aim · tap a thing in the tray, then PLACE"
	elseif Input.isGamepad() then
		return "RT place / pick up · LT drop · LB RB turn · D-pad pick · X put away · B done"
	end
	return "LEFT CLICK place / pick up · RIGHT CLICK drop · R F turn · Q E pick · X put away · B done · Alt frees the cursor"
end

local function bind()
	ContextActionService:BindActionAtPriority("ApexBuildPlace", function(_, inputState, input: InputObject)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		-- A click on the tray (cursor freed with Alt) is the tray's
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local inset = GuiService:GetGuiInset()
			local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
			for _, y in { input.Position.Y, input.Position.Y + inset.Y } do
				for _, object in
					if playerGui then playerGui:GetGuiObjectsAtPosition(input.Position.X, y) else {}
				do
					if object:IsDescendantOf(panel) then
						return Enum.ContextActionResult.Pass
					end
				end
			end
		end
		place()
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindActionAtPriority("ApexBuildDrop", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			select(nil)
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)
	ContextActionService:BindActionAtPriority("ApexBuildTurn", function(_, inputState, input)
		local by = if input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1
		if inputState == Enum.UserInputState.Begin then
			yaw = (yaw + by * TURN) % 360
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
	-- The stall menu, the HUD's D-pad menus and the item wheel wait till you're done
	ContextActionService:BindActionAtPriority("ApexBuildQuiet", function()
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.KeyCode.ButtonY, Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown, Enum.KeyCode.G)
end

local function unbind()
	for _, name in
		{
			"ApexBuildPlace",
			"ApexBuildDrop",
			"ApexBuildTurn",
			"ApexBuildPick",
			"ApexBuildAway",
			"ApexBuildDone",
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
	panel.Size = UDim2.fromOffset(if touch then 600 else 760, if touch then 172 else 146)
	panel.Position = UDim2.new(0.5, 0, 1, if touch then -150 else -120)
	touchRow.Visible = touch
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
	MenuController.building = true
	turning = 0
	controlsLabel.Text = controlsText()
	layoutTray()
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
	MenuController.building = false
	select(nil)
	aimLight.Adornee = nil
	aimedUid = nil
	panel.Visible = false
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
		UDim2.fromOffset(if touch then 600 else 760, if touch then 172 else 146),
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
			end,
		},
		{ text = "PUT AWAY", style = "secondary", run = putAway },
		{
			text = "DROP",
			style = "secondary",
			run = function()
				select(nil)
			end,
		},
		{ text = "DONE", style = "gold", run = BuildController.stop },
	}
	for i, spec in buttons do
		local button = Ui.button(
			touchRow,
			spec.text,
			spec.text,
			UDim2.new(0.2, -6, 1, 0),
			UDim2.new((i - 1) * 0.2, 0, 0, 0),
			spec.style
		)
		button.TextSize = 14
		button.Activated:Connect(spec.run)
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
	RunService.Heartbeat:Connect(function()
		local show = not active
			and not Input.locked
			and not Input.isTouch()
			and not Input.isGamepad()
			and not MenuController.isOpen()
			and not MapController.isOpen()
			and insideOwnDen()
		if hintChip.Visible ~= show then
			hintChip.Visible = show
		end
	end)
end

return BuildController
