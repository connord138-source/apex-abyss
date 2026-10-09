--!strict
-- The Shop's faces on the HUD and the moments it's offered (GDD §9):
--
--  * DAILY and SHOP buttons beside the wallet (the View button opens the Shop on a
--    controller). DAILY glows while today's reward waits, and the Daily panel opens
--    by itself once per session when one does (after the tutorial).
--  * A note in the Haul card's corner while growth is boosted: ×2 Mass, a Server
--    Frenzy (with its clock), or both.
--  * Double Haul on the bank screen: one tap to double the Haul just banked (the
--    price by its size), WATCH AD for a small one, and SKIP. No countdown (owner).
--  * Second Chance after being eaten with a Haul worth having: one tap to get it
--    back, or SKIP.
--
-- Both cards free the cursor while they're up and go away when you swim out of the
-- hub. The server decides when an offer is made (HuntService) and grants every
-- purchase (MonetizationService).
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Ads = require(script.Parent.Parent.Ads)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Parent.Ui)
local HudController = require(script.Parent.HudController)
local MenuController = require(script.Parent.MenuController)
local StartController = require(script.Parent.StartController)
local SwimController = require(script.Parent.SwimController)

local Monetization = Config.Monetization

local OfferController = {}

local gui: ScreenGui
local dailyButton: TextButton
local dailyScale: UIScale
local chip: Frame
local chipText: TextLabel
local card: Frame? = nil
local cardKind: string? = nil
local dailyShown = false

local function state(): { [string]: any }
	return ClientState.current or {}
end

-- Takes the open card down (and gives the mouse back to looking)
local function closeCard()
	local old = card
	if old == nil then
		return
	end
	card = nil
	cardKind = nil
	MenuController.stallButtonHidden = false
	ContextActionService:UnbindAction("ApexOfferSkip")
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(old) then
		GuiService.SelectedObject = nil
	end
	if not MenuController.isOpen() then
		Input.cursorWanted = false
	end
	local scale = old:FindFirstChildOfClass("UIScale")
	if scale then
		Ui.tween(scale, 0.18, { Scale = 0.9 })
	end
	Ui.tween(old, 0.18, { BackgroundTransparency = 1 })
	task.delay(0.2, function()
		old:Destroy()
	end)
end

-- A card under the screen's middle: a title, a line, and up to three buttons
type Choice = { text: string, style: Ui.ButtonStyle, width: number, pressed: () -> () }

-- Phones: the card sits in the gap between the HUD button row and the health bar,
-- measured on screen (a fixed spot overlapped the row by 2-4 px on an iPhone 14,
-- playtests 2026-10-09). Returns the card's height and the centre's shift in design
-- units, or nil when either piece isn't there.
local CARD_MARGIN = 6
local function phoneGap(frame: Frame): (number?, number?)
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local wallet = playerGui and playerGui:FindFirstChild("Wallet")
	local row = wallet and wallet:FindFirstChild("Buttons")
	local hud = playerGui and playerGui:FindFirstChild("Hud")
	local health = hud and hud:FindFirstChild("Health")
	if row == nil or health == nil or not health:IsA("GuiObject") then
		return nil, nil
	end
	local top = -math.huge
	for _, button in row:GetChildren() do
		if button:IsA("GuiObject") and button.Visible then
			top = math.max(top, button.AbsolutePosition.Y + button.AbsoluteSize.Y)
		end
	end
	if top == -math.huge then
		return nil, nil
	end
	local bottom = health.AbsolutePosition.Y
	local scale = Ui.scaleOf(gui)
	local height = math.clamp((bottom - top) / scale - CARD_MARGIN * 2, 100, 124)
	-- Both are measured on screen like the card itself, so only the difference counts
	local centre = frame.AbsolutePosition.Y + frame.AbsoluteSize.Y / 2
	return height, ((top + bottom) / 2 - centre) / scale
end

local function openCard(kind: string, title: string, line: string, accent: Color3, choices: { Choice })
	closeCard()
	local frame =
		Ui.panel(gui, "Offer", UDim2.fromOffset(460, 132), UDim2.fromScale(0.5, 0.62), Vector2.new(0.5, 0.5))
	local touch = Ui.isTouch()
	if touch then
		frame.Size = UDim2.fromOffset(460, 108)
		frame.Position = UDim2.fromScale(0.5, 0.64)
	end
	frame.BackgroundTransparency = 0.12
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = accent
		stroke.Transparency = 0.25
		stroke.Thickness = 1.5
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = frame
	local heading = Ui.label(
		frame,
		"Title",
		title,
		Ui.FONT_HEAVY,
		22,
		accent,
		UDim2.new(1, -24, 0, 28),
		UDim2.fromOffset(12, if touch then 4 else 10)
	)
	heading.TextXAlignment = Enum.TextXAlignment.Center
	local sub = Ui.label(
		frame,
		"Line",
		line,
		Ui.FONT_SEMI,
		15,
		Ui.color.text,
		UDim2.new(1, -24, 0, 20),
		UDim2.fromOffset(12, if touch then 31 else 40)
	)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	local row = Instance.new("Frame")
	row.Name = "Choices"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -24, 0, 44)
	row.Position = if touch then UDim2.new(0, 12, 1, -50) else UDim2.fromOffset(12, 74)
	row.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local first: TextButton? = nil
	for i, choice in choices do
		local button = Ui.button(
			row,
			`Choice{i}`,
			choice.text,
			UDim2.fromOffset(choice.width, 42),
			UDim2.new(),
			choice.style
		)
		button.LayoutOrder = i
		button.TextSize = 15
		button.Activated:Connect(choice.pressed)
		first = first or button
	end
	if touch then
		-- Again a frame later, once the new card has been laid out on screen
		local function fit()
			local height, shift = phoneGap(frame)
			if height and shift and card == frame then
				frame.Size = UDim2.fromOffset(460, height)
				frame.Position += UDim2.fromOffset(0, shift)
			end
		end
		task.defer(function()
			fit()
			RunService.RenderStepped:Wait()
			fit()
		end)
	end
	card = frame
	cardKind = kind
	MenuController.stallButtonHidden = true -- it sat on the card's edge on phones
	Ui.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	Input.cursorWanted = true
	if Input.isGamepad() and first then
		GuiService.SelectedObject = first
	end
	-- B skips on a controller
	ContextActionService:BindActionAtPriority("ApexOfferSkip", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and not MenuController.isOpen() then
			closeCard()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, 2900, Enum.KeyCode.ButtonB)
end

-- Double Haul, after banking (the server sends `offer` with the summary)
local function onBanked(summary: { [string]: any })
	if summary.doubled then
		if cardKind == "double" then
			closeCard()
		end
		return
	end
	local offer = summary.offer
	if typeof(offer) ~= "table" then
		return
	end
	local product = Monetization.productsByKey[offer.product]
	if product == nil or not Store.listed(product.id) then
		return
	end
	local amount = typeof(summary.amount) == "number" and summary.amount or 0
	local levels = typeof(offer.levels) == "number" and offer.levels or 0
	local choices: { Choice } = {
		{
			text = `DOUBLE IT · {Store.price(product.price)}`,
			style = "gold",
			width = 190,
			pressed = function()
				Store.buyProduct(product.key)
			end,
		},
	}
	if offer.ad and Ads.available then
		table.insert(choices, {
			text = "WATCH AD",
			style = "primary",
			width = 120,
			pressed = function()
				Ads.watch()
				closeCard()
			end,
		})
	end
	table.insert(choices, { text = "SKIP", style = "secondary", width = 90, pressed = closeCard })
	-- Shown once the banked banner has had its moment
	task.delay(1.1, function()
		openCard(
			"double",
			"DOUBLE THIS HAUL?",
			if levels > 0
				then `+{Format.mass(amount)} more · {levels} more level{if levels == 1 then "" else "s"}`
				else `+{Format.mass(amount)} more`,
			Ui.color.haul,
			choices
		)
	end)
end

-- Second Chance, after being eaten with a Haul worth having
local function onEaten(summary: { [string]: any })
	local lost = summary.offer
	local product = Monetization.productsByKey.SecondChance
	if typeof(lost) ~= "number" or product == nil or not Store.listed(product.id) then
		return
	end
	local respawn = typeof(summary.respawn) == "number" and summary.respawn or 3
	task.delay(respawn + 0.4, function()
		openCard(
			"second",
			"GET YOUR HAUL BACK?",
			`You lost {Format.mass(lost)} · Second Chance returns all of it`,
			Ui.color.accent,
			{
				{
					text = `GET IT BACK · {Store.price(product.price)}`,
					style = "gold",
					width = 220,
					pressed = function()
						Store.buyProduct("SecondChance")
					end,
				},
				{ text = "SKIP", style = "secondary", width = 90, pressed = closeCard },
			}
		)
	end)
end

local function buildButtons()
	local holder: Frame
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local wallet = playerGui:FindFirstChild("Wallet")
	local row = wallet and wallet:FindFirstChild("Buttons")
	if Ui.isTouch() and row and row:IsA("Frame") then
		-- Phones: at the end of the HUD button row. Beside the wallet, the centre
		-- banners' second lines ran across them (playtest 2026-10-09)
		holder = row
	else
		-- Beside the wallet card, clear of the boss bar, the treasure sonar and the
		-- depth gauge
		holder = Instance.new("Frame")
		holder.Name = "StoreButtons"
		holder.BackgroundTransparency = 1
		holder.Position = UDim2.fromOffset(258, 144)
		holder.Size = UDim2.fromOffset(196, 34)
		holder.Parent = gui
		Ui.belowTopBar(gui, holder, 144)
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = holder
	end
	dailyButton = Ui.button(holder, "Daily", "DAILY", UDim2.fromOffset(90, 34), UDim2.new(), "secondary")
	dailyButton.LayoutOrder = 11
	dailyButton.TextSize = 14
	dailyButton.Activated:Connect(MenuController.openDaily)
	dailyScale = dailyButton:FindFirstChildOfClass("UIScale") :: UIScale
	local shop = Ui.button(holder, "Shop", "SHOP", UDim2.fromOffset(90, 34), UDim2.new(), "gold")
	shop.LayoutOrder = 12
	shop.TextSize = 14
	shop.Activated:Connect(MenuController.openStore)
	-- Not selectable, like the other HUD buttons (the View button opens the Shop)
	dailyButton.Selectable = false
	shop.Selectable = false

	-- The growth chip lives in the Haul card's top-right corner, on every screen:
	-- growth is about the Haul, and nothing else draws there
	local hud = playerGui:WaitForChild("Hud", 10)
	local haul = hud and hud:WaitForChild("Haul", 10)
	chip = Instance.new("Frame")
	chip.Name = "Growth"
	chip.BackgroundTransparency = 1
	chip.Size = UDim2.fromOffset(200, 16)
	chip.AnchorPoint = Vector2.new(1, 0)
	chip.Position = UDim2.new(1, -16, 0, 10)
	chip.Visible = false
	chip.Parent = haul or gui
	chipText = Ui.label(chip, "Text", "", Ui.FONT_HEAVY, 13, Ui.color.haul, UDim2.fromScale(1, 1))
	chipText.TextXAlignment = Enum.TextXAlignment.Right
	chipText.TextYAlignment = Enum.TextYAlignment.Center
end

local function onState(s: { [string]: any })
	local daily = s.daily
	local ready = typeof(daily) == "table" and daily.claimable == true
	Ui.setButtonStyle(dailyButton, if ready then "gold" else "secondary")
	dailyButton.Selectable = false
	dailyButton.Text = if ready then "DAILY !" else "DAILY"
	-- Swimming out of the hub takes an open offer down
	if card and s.inHub == false then
		closeCard()
	end
end

-- The Daily panel opens by itself once a session, when a reward waits
local waitingForStart = false
local function maybeShowDaily()
	if dailyShown then
		return
	end
	-- Not under the start screen: a moment after the player dives in
	if StartController.isUp() then
		if not waitingForStart then
			waitingForStart = true
			StartController.afterStart(function()
				task.delay(1.5, maybeShowDaily)
			end)
		end
		return
	end
	local s = state()
	local daily = s.daily
	local tutorial = s.tutorial
	if typeof(daily) ~= "table" or not daily.claimable then
		return
	end
	if typeof(tutorial) == "table" and not tutorial.done then
		return
	end
	if MenuController.isOpen() then
		return
	end
	-- Never over an offer card: on respawn it covered the eaten screen's Second
	-- Chance offer (playtest 2026-10-09, phone). Try again once the card is gone.
	if card then
		task.delay(2, maybeShowDaily)
		return
	end
	dailyShown = true
	MenuController.openDaily()
end

local function step()
	local s = state()
	-- An open card keeps the cursor free: closing a menu over it locked the mouse
	-- again, so GET IT BACK couldn't be clicked (playtest 2026-10-09)
	if card then
		Input.cursorWanted = true
	end
	-- The growth chip
	local mass = s.massMultiplier or 1
	local frenzyLeft = (workspace:GetAttribute("FrenzyUntil") or 0) - workspace:GetServerTimeNow()
	local frenzy = if frenzyLeft > 0 then (workspace:GetAttribute("Frenzy") or 2) else 1
	if mass > 1 or frenzy > 1 then
		chip.Visible = true
		if frenzy > 1 and mass > 1 then
			chipText.Text = `×{mass * frenzy} GROWTH · {Format.clock(frenzyLeft)}`
		elseif frenzy > 1 then
			chipText.Text = `FRENZY ×{frenzy} · {Format.clock(frenzyLeft)}`
		else
			chipText.Text = `×{mass} MASS`
		end
	else
		chip.Visible = false
	end
	-- DAILY breathes while a reward waits
	if dailyButton.Text ~= "DAILY" then
		dailyScale.Scale = 1 + math.sin(os.clock() * 4) * 0.05
	else
		dailyScale.Scale = 1
	end
end

function OfferController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.screen("Offers", playerGui, 7)
	buildButtons()
	Store.said:connect(function(text: string)
		HudController.toast(text, "info")
	end)
	Store.productClosed:connect(function(key: string, _bought: boolean)
		if
			(cardKind == "double" and string.find(key, "DoubleHaul") ~= nil)
			or (cardKind == "second" and key == "SecondChance")
		then
			closeCard()
		end
	end)
	ClientState.changed:connect(onState)
	if ClientState.current then
		onState(ClientState.current)
	end
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local banked = remotes:WaitForChild("Banked") :: RemoteEvent
	banked.OnClientEvent:Connect(onBanked)
	local eaten = remotes:WaitForChild("Eaten") :: RemoteEvent
	eaten.OnClientEvent:Connect(onEaten)
	SwimController.spawned:connect(function()
		task.delay(3, maybeShowDaily)
	end)
	-- Controllers: the View button opens the Shop
	ContextActionService:BindAction("ApexShopButton", function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin or MenuController.isOpen() then
			return Enum.ContextActionResult.Pass
		end
		MenuController.openStore()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonSelect)
	RunService.Heartbeat:Connect(step)
end

return OfferController
