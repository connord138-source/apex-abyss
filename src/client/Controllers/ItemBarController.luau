--!strict
-- The item bar (owner, 2026-10-18: "I dont see how a player is supposed to use a
-- kelp wrap either i dont see an inventory bar or anything"): the consumables you
-- carry (Config/Shop `items`: Kelp Wraps, Feast Charm, Shell Magnet, Deep Lantern)
-- as slots beside the Haul card, each with its photo (CardPhoto), how many you have,
-- its key, whether it's ready and a cooldown sweep. Only what you carry (or a charm
-- still running) shows; with nothing, a faint ITEMS note marks the place.
--   Keyboard: 1-4 use the slot with that number (H still uses a Kelp Wrap), or click
--             one with a free cursor (Alt).
--   Pad:      LB as before (a tap uses a wrap, a hold opens the item wheel).
--   Touch:    tap a slot.
-- The item wheel (ItemWheelController) still works; both send UseItem (ItemService).
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Timing = require(ReplicatedStorage.Shared.Timing)
local CardPhoto = require(script.Parent.Parent.CardPhoto)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local MenuController = require(script.Parent.MenuController)
local StartController = require(script.Parent.StartController)

local Shop = Config.Shop
local heal = Config.Tuning.heal

local ItemBarController = {}

local SLOT_W, SLOT_H = 66, 92 -- as tall as the Haul card it sits beside
local GAP = 8
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }
local KEY_NAMES = { "1", "2", "3", "4" }

local COLORS: { [string]: Color3 } = {
	KelpWrap = Ui.color.safe,
	Feast = Ui.color.haul,
	Magnet = Ui.color.accent,
	DeepLantern = Color3.fromRGB(255, 214, 150),
}
local SHORT: { [string]: string } = {
	KelpWrap = "KELP WRAP",
	Feast = "FEAST",
	Magnet = "MAGNET",
	DeepLantern = "LANTERN",
}
-- Its photo: the roll cards' rolled Kelp Wraps, or the charm
local PHOTOS: { [string]: CardPhoto.Outcome } = {
	KelpWrap = { kind = "wraps", id = "wraps", name = "", tier = "Uncommon" },
	Feast = { kind = "charm", id = "charm", name = "", tier = "Rare" },
	Magnet = { kind = "charm", id = "charm", name = "", tier = "Rare" },
	DeepLantern = { kind = "charm", id = "charm", name = "", tier = "Rare" },
}

type Slot = {
	id: string,
	index: number,
	frame: Frame,
	scale: UIScale,
	stroke: UIStroke?,
	visual: Frame,
	photo: ViewportFrame?,
	count: TextLabel,
	status: TextLabel,
	key: Frame,
	keyText: TextLabel,
	sweep: Frame,
	timer: Frame,
	timerFill: Frame,
	shown: number, -- the count last drawn (a pop when it goes up)
}

local gui: ScreenGui
local bar: Frame
local empty: TextLabel
local slots: { Slot } = {}

local function state(): { [string]: any }
	return ClientState.current or {}
end

local function held(id: string): number
	local charms = state().charms
	return if typeof(charms) == "table" then charms[id] or 0 else 0
end

-- Seconds a timed charm has left running (0 when it isn't on)
local function running(id: string): number
	local boosts = state().boosts
	local ends = if typeof(boosts) == "table" then boosts[id] or 0 else 0
	return math.max(0, ends - workspace:GetServerTimeNow())
end

-- Whether items can be used right now (not under a menu, the start screen or Build)
local function usable(): boolean
	return not (MenuController.isOpen() or Input.locked or Input.building or Input.editing)
end

-- Uses one of an item (the server checks everything: none left, cooling down, full
-- health)
local function use(id: string)
	if not usable() then
		return
	end
	ClientState.request("UseItem", id)
	for _, slot in slots do
		if slot.id == id then
			slot.scale.Scale = 0.86
			Ui.tween(slot.scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	Sfx.play("UiClick", { volume = 0.4 })
end

-- The key a slot shows for this device (nil: none, tap or click it)
local function keyText(slot: Slot): string?
	if Input.isTouch() then
		return nil
	elseif Input.isGamepad() then
		return if slot.id == "KelpWrap" then "LB" else nil
	end
	return KEY_NAMES[slot.index]
end

local function makeSlot(index: number, id: string): Slot
	local color = COLORS[id] or Ui.color.accent
	local frame = Ui.panel(bar, id, UDim2.fromOffset(SLOT_W, SLOT_H), UDim2.new())
	frame.LayoutOrder = index
	frame.Visible = false
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Transparency = 0.45
		stroke.Thickness = 1.5
	end
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.BorderSizePixel = 0
	band.BackgroundColor3 = color
	band.AnchorPoint = Vector2.new(0.5, 0)
	band.Position = UDim2.new(0.5, 0, 0, 4)
	band.Size = UDim2.new(1, -24, 0, 3)
	Ui.corner(band, UDim.new(1, 0))
	band.Parent = frame
	local visual = Instance.new("Frame")
	visual.Name = "Visual"
	visual.BackgroundColor3 = Ui.color.panelFoot
	visual.BackgroundTransparency = 0.4
	visual.BorderSizePixel = 0
	visual.ClipsDescendants = true
	visual.Position = UDim2.fromOffset(5, 10)
	visual.Size = UDim2.new(1, -10, 0, 44)
	Ui.corner(visual, UDim.new(0, 8))
	visual.Parent = frame
	local count = Ui.label(
		frame,
		"Count",
		"×0",
		Ui.FONT_HEAVY,
		15,
		color,
		UDim2.fromOffset(40, 18),
		UDim2.new(1, -46, 0, 38)
	)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextStrokeTransparency = 0.35
	count.TextStrokeColor3 = Ui.color.panelFoot
	count.ZIndex = 4
	local name = Ui.label(
		frame,
		"Name",
		SHORT[id] or id,
		Ui.FONT_HEAVY,
		10,
		Ui.color.text,
		UDim2.new(1, -4, 0, 14),
		UDim2.fromOffset(2, 57)
	)
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = 10
	fit.Parent = name
	local status = Ui.label(
		frame,
		"Status",
		"",
		Ui.FONT_BOLD,
		10,
		Ui.color.safe,
		UDim2.new(1, 0, 0, 14),
		UDim2.fromOffset(0, 72)
	)
	status.TextXAlignment = Enum.TextXAlignment.Center
	-- The cooldown sweep: a shade over the slot that drains downward as it recharges
	local sweep = Instance.new("Frame")
	sweep.Name = "Sweep"
	sweep.BackgroundColor3 = Color3.new(0, 0, 0)
	sweep.BackgroundTransparency = 0.45
	sweep.BorderSizePixel = 0
	sweep.AnchorPoint = Vector2.new(0, 1)
	sweep.Position = UDim2.fromScale(0, 1)
	sweep.Size = UDim2.fromScale(1, 0)
	sweep.ZIndex = 5
	Ui.corner(sweep)
	sweep.Parent = frame
	-- A running charm's time left, along the foot
	local timer, timerFill = Ui.bar(frame, "Timer", UDim2.new(1, -14, 0, 3), UDim2.new(0, 7, 1, -5), color)
	timer.Visible = false
	-- Its key, a small cap over the top-left corner
	local key = Ui.keycap(frame, "Key", "1", 20)
	key.Position = UDim2.fromOffset(-6, -6)
	key.ZIndex = 6
	for _, d in key:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 7
		end
	end
	local padding = key:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingLeft = UDim.new(0, 5)
		padding.PaddingRight = UDim.new(0, 5)
	end
	local keyLabel = key:FindFirstChild("Text") :: TextLabel
	-- The whole slot is one button (a tap on a phone, a click with a free cursor)
	local hit = Instance.new("TextButton")
	hit.Name = "Use"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Selectable = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 8
	hit.Parent = frame
	hit.Activated:Connect(function()
		use(id)
	end)
	hit.MouseEnter:Connect(function()
		Ui.tween(scale, 0.15, { Scale = 1.05 })
		if stroke then
			stroke.Transparency = 0.1
		end
	end)
	hit.MouseLeave:Connect(function()
		Ui.tween(scale, 0.15, { Scale = 1 })
		if stroke then
			stroke.Transparency = 0.45
		end
	end)
	return {
		id = id,
		index = index,
		frame = frame,
		scale = scale,
		stroke = stroke,
		visual = visual,
		photo = nil,
		count = count,
		status = status,
		key = key,
		keyText = keyLabel,
		sweep = sweep,
		timer = timer,
		timerFill = timerFill,
		shown = 0,
	}
end

-- What a slot says under its name, whether it's ready, and how much of a cooldown
-- is left (0..1)
local function statusOf(slot: Slot, count: number): (string, Color3, number)
	if slot.id == "KelpWrap" then
		local character = Players.LocalPlayer.Character
		local readyAt = if character then character:GetAttribute("WrapReadyAt") else nil
		local now = Timing.clock()
		if typeof(readyAt) == "number" and readyAt > now then
			return `{math.ceil(readyAt - now)}s`,
				Ui.color.muted,
				math.clamp((readyAt - now) / heal.wrapCooldown, 0, 1)
		end
		local health = if character then character:GetAttribute("Health") else nil
		local most = if character then character:GetAttribute("MaxHealth") else nil
		if typeof(health) == "number" and typeof(most) == "number" and health >= most then
			return "FULL HP", Ui.color.muted, 0
		end
		return if count > 0 then "HEAL" else "NONE", if count > 0 then Ui.color.safe else Ui.color.muted, 0
	end
	local left = running(slot.id)
	if left > 0 then
		return `ON {Format.clock(left)}`, Ui.color.haul, 0
	end
	return if count > 0 then "READY" else "NONE", if count > 0 then Ui.color.safe else Ui.color.muted, 0
end

local function step()
	local hidden = StartController.isUp() or Input.editing or Input.building
	gui.Enabled = not hidden
	if hidden then
		return
	end
	local any = false
	for _, slot in slots do
		local count = held(slot.id)
		local charm = Shop.charmsById[slot.id]
		local left = running(slot.id)
		local show = count > 0 or left > 0
		slot.frame.Visible = show
		if not show then
			slot.shown = count
			continue
		end
		any = true
		-- The photo is made the first time the slot shows (its size is known then)
		if slot.photo == nil then
			local outcome = PHOTOS[slot.id]
			if outcome then
				slot.photo = CardPhoto.new(slot.visual, outcome, COLORS[slot.id] or Ui.color.accent)
			end
		end
		slot.count.Text = `×{count}`
		if count > slot.shown then
			slot.scale.Scale = 1.15
			Ui.tween(slot.scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		slot.shown = count
		local text, color, cooling = statusOf(slot, count)
		slot.status.Text = text
		slot.status.TextColor3 = color
		slot.sweep.Size = UDim2.fromScale(1, cooling)
		slot.frame.BackgroundTransparency = if count > 0 then Ui.PANEL_TRANSPARENCY else 0.5
		local duration = if charm and charm.seconds then charm.seconds else 0
		slot.timer.Visible = left > 0 and duration > 0
		if slot.timer.Visible then
			slot.timerFill.Size = UDim2.fromScale(math.clamp(left / duration, 0, 1), 1)
		end
		local key = keyText(slot)
		slot.key.Visible = key ~= nil
		if key then
			slot.keyText.Text = key
		end
	end
	empty.Visible = not any
	empty.Text = if Input.isTouch()
		then "ITEMS"
		elseif Input.isGamepad() then "ITEMS · HOLD LB"
		else "ITEMS · 1-4 · G"
end

function ItemBarController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.screen("ItemBar", playerGui, 6)
	-- Left of the Haul card (its left edge is 160 left of the middle), on its foot
	bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundTransparency = 1
	bar.AnchorPoint = Vector2.new(1, 1)
	bar.Position = UDim2.new(0.5, -170, 1, -22)
	bar.Size = UDim2.fromOffset(#Shop.items * (SLOT_W + GAP), SLOT_H)
	bar.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar
	-- Phones: a little smaller (the swim stick's resting ring is further left)
	if Input.isTouch() then
		local scale = Instance.new("UIScale")
		scale.Scale = 0.8
		scale.Parent = bar
	end
	empty = Ui.label(bar, "Empty", "ITEMS", Ui.FONT_BOLD, 11, Ui.color.muted, UDim2.fromOffset(0, 20))
	empty.AutomaticSize = Enum.AutomaticSize.X
	empty.LayoutOrder = 100
	empty.TextTransparency = 0.45
	for index, id in Shop.items do
		table.insert(slots, makeSlot(index, id))
	end
	ContextActionService:BindAction("ApexItemBar", function(_, inputState, input)
		if inputState ~= Enum.UserInputState.Begin or not usable() then
			return Enum.ContextActionResult.Pass
		end
		for index, key in KEYS do
			if input.KeyCode == key then
				local id = Shop.items[index]
				if id then
					use(id)
				end
				return Enum.ContextActionResult.Sink
			end
		end
		return Enum.ContextActionResult.Pass
	end, false, table.unpack(KEYS))
	RunService.RenderStepped:Connect(step)
end

return ItemBarController
