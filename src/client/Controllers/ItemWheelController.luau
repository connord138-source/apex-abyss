--!strict
-- The item wheel (owner, 2026-10-11: "kelp wraps also need to be put in user inventory
-- wheel to be used when needed and not immediately, same for kelp wraps won from the
-- spin wheel"): the consumables you carry (Config/Shop `items`: Kelp Wrap, Feast
-- Charm, Shell Magnet, Deep Lantern), four slots round a centre that names the one
-- you point at. Nothing starts until it's picked here (ItemService on the server).
--   Keyboard: hold G, point at a slot with the mouse, let go to use it; a quick tap
--             of G leaves the wheel open to click a slot (G again closes it).
--   Pad:      hold LB, point with either stick, let go to use it; a quick tap of LB
--             still uses a Kelp Wrap at once (HealController).
--   Touch:    the ITEMS button opens it; tap a slot.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Timing = require(ReplicatedStorage.Shared.Timing)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Ui = require(script.Parent.Parent.Ui)
local HealController = require(script.Parent.HealController)
local MenuController = require(script.Parent.MenuController)

local Shop = Config.Shop

local ItemWheelController = {}

local HOLD = 0.28 -- seconds: a key held longer than this is a hold, not a tap
local RING = 132 -- pixels from the centre to a slot's middle
local SLOT = 112
local DEAD = 46 -- pixels (or a stick under 0.5) that point at nothing

local COLORS: { [string]: Color3 } = {
	KelpWrap = Ui.color.safe,
	Feast = Ui.color.haul,
	Magnet = Ui.color.accent,
	DeepLantern = Color3.fromRGB(255, 214, 150),
}
local SHORT: { [string]: string } = {
	KelpWrap = "KELP WRAP",
	Feast = "FEAST",
	Magnet = "SHELL MAGNET",
	DeepLantern = "DEEP LANTERN",
}

type Slot = {
	id: string,
	button: TextButton,
	scale: UIScale,
	stroke: UIStroke,
	count: TextLabel,
	status: TextLabel,
}

local gui: ScreenGui
local root: CanvasGroup
local rootScale: UIScale
local title: TextLabel
local blurb: TextLabel
local slots: { Slot } = {}
local openMode: "mouse" | "pad" | "touch" | nil = nil
local hovered: number? = nil
local keyDownAt: number? = nil -- G
local padDownAt: number? = nil -- LB, until it turns into a hold
local lockedBefore = false

local function state(): any
	return ClientState.current or {}
end

local function held(id: string): number
	local charms = state().charms
	return if typeof(charms) == "table" then charms[id] or 0 else 0
end

-- What a slot says under its count: ready, cooling down, running, or none left.
local function statusOf(id: string): (string, boolean)
	local count = held(id)
	if id == "KelpWrap" then
		local character = Players.LocalPlayer.Character
		local readyAt = if character then character:GetAttribute("WrapReadyAt") else nil
		local now = Timing.clock()
		if typeof(readyAt) == "number" and readyAt > now then
			return `READY IN {math.ceil(readyAt - now)}s`, false
		end
		return if count > 0 then "READY" else "NONE LEFT", count > 0
	end
	local boosts = state().boosts
	local ends = if typeof(boosts) == "table" then boosts[id] or 0 else 0
	local left = ends - workspace:GetServerTimeNow()
	if left > 0 then
		return `ON · {Format.clock(left)}`, count > 0
	end
	return if count > 0 then "READY" else "NONE LEFT", count > 0
end

local function setHovered(index: number?)
	if hovered == index then
		return
	end
	hovered = index
	for i, slot in slots do
		local on = i == index
		Ui.tween(slot.scale, 0.12, { Scale = if on then 1.08 else 1 })
		slot.stroke.Thickness = if on then 3 else 1.5
		slot.stroke.Transparency = if on then 0 else 0.5
	end
	local id = if index then Shop.items[index] else nil
	local charm = if id then Shop.charmsById[id] else nil
	title.Text = if charm then string.upper(charm.name) else "ITEMS"
	blurb.Text = if charm
		then charm.blurb
		elseif openMode == "pad" then "Point with a stick, let go of LB to use"
		elseif openMode == "touch" then "Tap one to use it"
		else "Point at one and let go of G, or click it"
end

local function close()
	if openMode == nil then
		return
	end
	if openMode == "mouse" and not MenuController.isOpen() then
		Input.cursorWanted = false -- (a menu that just opened keeps it free)
	elseif openMode == "pad" then
		Input.locked = lockedBefore
	end
	openMode = nil
	keyDownAt = nil
	Ui.tween(rootScale, 0.12, { Scale = 0.9 })
	Ui.tween(root, 0.12, { GroupTransparency = 1 })
	task.delay(0.13, function()
		if openMode == nil then
			root.Visible = false
		end
	end)
end

local function use(index: number)
	local id = Shop.items[index]
	if id then
		ClientState.request("UseItem", id)
	end
	close()
end

local function open(mode: "mouse" | "pad" | "touch")
	if openMode ~= nil or MenuController.isOpen() or Input.locked then
		return
	end
	openMode = mode
	if mode == "mouse" then
		Input.cursorWanted = true -- free the cursor to point and click
	elseif mode == "pad" then
		lockedBefore = Input.locked
		Input.locked = true -- the sticks point at slots, not swim
	end
	hovered = -1 -- (so the centre's text is set afresh)
	setHovered(nil)
	root.Visible = true
	root.GroupTransparency = 1
	rootScale.Scale = 0.9
	Ui.tween(rootScale, 0.16, { Scale = 1 })
	Ui.tween(root, 0.16, { GroupTransparency = 0 })
end

-- The slot a direction points at (x right, y down; slots go clockwise from the top).
local function slotAt(direction: Vector2): number?
	if direction.Magnitude < 1e-3 then
		return nil
	end
	local angle = math.atan2(direction.X, -direction.Y) % (2 * math.pi)
	local count = #Shop.items
	return math.floor((angle + math.pi / count) / (2 * math.pi / count)) % count + 1
end

local function step()
	for _, slot in slots do
		local count = held(slot.id)
		slot.count.Text = `×{count}`
		local text, ready = statusOf(slot.id)
		slot.status.Text = text
		slot.button.BackgroundTransparency = if ready then 0.18 else 0.45
	end
	-- A tap of LB that turns into a hold opens the wheel
	if padDownAt and Timing.clock() - padDownAt >= HOLD then
		padDownAt = nil
		open("pad")
	end
	if openMode == nil then
		return
	end
	if MenuController.isOpen() then
		close()
		return
	end
	if openMode == "mouse" then
		local center = root.AbsolutePosition + root.AbsoluteSize / 2
		local offset = UserInputService:GetMouseLocation() - center
		setHovered(if offset.Magnitude > DEAD * Ui.scaleOf(gui) then slotAt(offset) else nil)
	elseif openMode == "pad" then
		local best = Vector2.zero
		for _, pad in UserInputService:GetConnectedGamepads() do
			for _, input in UserInputService:GetGamepadState(pad) do
				if input.KeyCode == Enum.KeyCode.Thumbstick1 or input.KeyCode == Enum.KeyCode.Thumbstick2 then
					local v = Vector2.new(input.Position.X, -input.Position.Y)
					if v.Magnitude > best.Magnitude then
						best = v
					end
				end
			end
		end
		if best.Magnitude > 0.5 then
			setHovered(slotAt(best))
		end
	end
end

local function makeSlot(index: number, id: string): Slot
	local count = #Shop.items
	local angle = (index - 1) / count * 2 * math.pi
	local button = Instance.new("TextButton")
	button.Name = id
	button.Text = ""
	button.AutoButtonColor = false
	button.Selectable = false
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = UDim2.fromOffset(SLOT, SLOT)
	button.Position = UDim2.new(0.5, math.sin(angle) * RING, 0.5, -math.cos(angle) * RING)
	button.BackgroundColor3 = Ui.color.panel
	Ui.corner(button, UDim.new(0, 18))
	local stroke = Ui.stroke(button, COLORS[id] or Ui.color.stroke, 0.5, 1.5)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.BorderSizePixel = 0
	band.Size = UDim2.new(1, -24, 0, 4)
	band.Position = UDim2.fromOffset(12, 12)
	band.BackgroundColor3 = COLORS[id] or Ui.color.accent
	Ui.corner(band, UDim.new(1, 0))
	band.Parent = button
	local name = Ui.label(
		button,
		"Name",
		SHORT[id] or id,
		Ui.FONT_HEAVY,
		12,
		Ui.color.text,
		UDim2.new(1, -12, 0, 16),
		UDim2.fromOffset(6, 22)
	)
	name.TextXAlignment = Enum.TextXAlignment.Center
	local countLabel = Ui.label(
		button,
		"Count",
		"×0",
		Ui.FONT_HEAVY,
		28,
		COLORS[id] or Ui.color.text,
		UDim2.new(1, -12, 0, 34),
		UDim2.fromOffset(6, 40)
	)
	countLabel.TextXAlignment = Enum.TextXAlignment.Center
	local status = Ui.label(
		button,
		"Status",
		"",
		Ui.FONT_BOLD,
		11,
		Ui.color.muted,
		UDim2.new(1, -12, 0, 16),
		UDim2.fromOffset(6, 82)
	)
	status.TextXAlignment = Enum.TextXAlignment.Center
	button.Activated:Connect(function()
		if openMode then
			use(index)
		end
	end)
	button.MouseEnter:Connect(function()
		if openMode == "mouse" or openMode == "touch" then
			setHovered(index)
		end
	end)
	button.Parent = root
	return { id = id, button = button, scale = scale, stroke = stroke, count = countLabel, status = status }
end

function ItemWheelController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.screen("ItemWheel", playerGui, 8)
	root = Instance.new("CanvasGroup")
	root.Name = "Wheel"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(RING * 2 + SLOT + 20, RING * 2 + SLOT + 20)
	root.BackgroundTransparency = 1
	root.Visible = false
	rootScale = Instance.new("UIScale")
	rootScale.Parent = root
	root.Parent = gui
	-- The centre: a disc that names the slot you point at
	local hub = Instance.new("TextButton")
	hub.Name = "Centre"
	hub.Text = ""
	hub.AutoButtonColor = false
	hub.Selectable = false
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(150, 150)
	hub.BackgroundColor3 = Ui.color.panel
	hub.BackgroundTransparency = 0.12
	Ui.corner(hub, UDim.new(1, 0))
	Ui.stroke(hub, Ui.color.stroke, 0.45, 1.5)
	hub.Parent = root
	hub.Activated:Connect(close) -- the middle (nothing picked) closes it
	title = Ui.label(
		hub,
		"Title",
		"ITEMS",
		Ui.FONT_HEAVY,
		15,
		Ui.color.text,
		UDim2.new(1, -24, 0, 20),
		UDim2.fromOffset(12, 30)
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	blurb = Ui.label(
		hub,
		"Blurb",
		"",
		Ui.FONT,
		11,
		Ui.color.muted,
		UDim2.new(1, -28, 0, 70),
		UDim2.fromOffset(14, 54)
	)
	blurb.TextXAlignment = Enum.TextXAlignment.Center
	blurb.TextYAlignment = Enum.TextYAlignment.Top
	blurb.TextWrapped = true
	for index, id in Shop.items do
		table.insert(slots, makeSlot(index, id))
	end
	-- Phones: an ITEMS button left of HEAL and DASH (clear of BITE and the stall button)
	if Input.isTouch() then
		local button = Instance.new("TextButton")
		button.Name = "Items"
		button.Text = "ITEMS"
		button.FontFace = Ui.FONT_HEAVY
		button.TextSize = 12
		button.TextColor3 = Ui.color.text
		button.AutoButtonColor = false
		button.Selectable = false
		button.Size = UDim2.fromOffset(54, 54)
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.new(1, -312, 1, -96)
		button.BackgroundColor3 = Ui.color.panel
		button.BackgroundTransparency = 0.2
		Ui.corner(button, UDim.new(1, 0))
		Ui.stroke(button, Ui.color.stroke, 0.4, 1.5)
		button.Activated:Connect(function()
			if openMode then
				close()
			else
				open("touch")
			end
		end)
		button.Parent = gui
	end
	ContextActionService:BindAction("ApexItems", function(_, inputState, input)
		local now = Timing.clock()
		if input.KeyCode == Enum.KeyCode.ButtonL1 then
			if inputState == Enum.UserInputState.Begin then
				padDownAt = now
			elseif inputState == Enum.UserInputState.End then
				if padDownAt then
					-- A tap: the quick Kelp Wrap
					padDownAt = nil
					HealController.use()
				elseif openMode == "pad" then
					local pick = hovered
					if pick then
						use(pick)
					else
						close()
					end
				end
			end
			return Enum.ContextActionResult.Sink
		end
		-- G
		if inputState == Enum.UserInputState.Begin then
			if openMode then
				close()
			else
				open("mouse")
				keyDownAt = now
			end
		elseif inputState == Enum.UserInputState.End and openMode == "mouse" and keyDownAt then
			local heldFor = now - keyDownAt
			keyDownAt = nil
			if heldFor >= HOLD then
				-- Held: let go on a slot to use it, off the slots to put it away
				local pick = hovered
				if pick then
					use(pick)
				else
					close()
				end
			end
			-- (a tap leaves it open to click)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.G, Enum.KeyCode.ButtonL1)
	RunService.RenderStepped:Connect(step)
end

return ItemWheelController
