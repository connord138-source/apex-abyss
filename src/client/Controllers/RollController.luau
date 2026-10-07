--!strict
-- The wallet (Coral and Shells, top left), the Roll / Odds / Wardrobe buttons,
-- and the roll reveal: a case-opening reel that slows onto what the server
-- rolled. The rarer the result, the longer the reel creeps and the bigger the
-- landing (a flash and light rays in the tier's color from Rare up). Cosmetics land
-- on a preview of your own fish, with a button to wear them straight away.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local ClientState = require(script.Parent.Parent.ClientState)
local FishPreview = require(script.Parent.Parent.FishPreview)
local Input = require(script.Parent.Parent.Input)
local Ui = require(script.Parent.Parent.Ui)
local MenuController = require(script.Parent.MenuController)

local Tiers = Config.Tiers
type Tier = typeof(Tiers.list[1])

local RollController = {}

local CARD_W, CARD_H, GAP = 128, 150, 10
local STEP = CARD_W + GAP
local REEL_CARDS = 46
local LAND_INDEX = 40

local hud: ScreenGui
local revealGui: ScreenGui
local coralText: TextLabel
local shellText: TextLabel
local shellFill: Frame
local rollButton: TextButton
local rollScale: UIScale
local busy = false
local waitingSince = 0

local function state(): { [string]: any }
	return ClientState.current or {}
end

local function tierOf(id: string): Tier
	return Tiers.byId[id] or Tiers.byId.Common
end

-- Small icon text for a card (no image assets yet).
local function glyph(outcome: RollOdds.Outcome): string
	if outcome.kind == "coral" then
		return "C"
	elseif outcome.kind == "shade" then
		return "◆"
	end
	return "★"
end

local function card(parent: Instance, outcome: RollOdds.Outcome, x: number): Frame
	local tier = tierOf(outcome.tier)
	local frame = Instance.new("Frame")
	frame.Name = "Card"
	frame.Size = UDim2.fromOffset(CARD_W, CARD_H)
	frame.Position = UDim2.fromOffset(x, 0)
	frame.BackgroundColor3 = Color3.fromRGB(12, 28, 42)
	frame.BorderSizePixel = 0
	Ui.corner(frame, UDim.new(0, 12))
	local stroke = Ui.stroke(frame, tier.color, 0.35, 2)
	stroke.Name = "Edge"
	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0, 6)
	band.BackgroundColor3 = tier.color
	band.BorderSizePixel = 0
	Ui.corner(band, UDim.new(0, 12))
	band.Parent = frame
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150))
	gradient.Parent = frame
	local icon = Ui.label(
		frame,
		"Icon",
		glyph(outcome),
		Ui.FONT_HEAVY,
		44,
		tier.color,
		UDim2.new(1, 0, 0, 60),
		UDim2.fromOffset(0, 22)
	)
	icon.TextXAlignment = Enum.TextXAlignment.Center
	if outcome.kind == "shade" then
		local shade = Config.Shades.byId[outcome.id]
		if shade then
			icon.TextColor3 = shade.back
			icon.TextStrokeColor3 = shade.fin
			icon.TextStrokeTransparency = 0.2
		end
	end
	local name = Ui.label(
		frame,
		"Name",
		outcome.name,
		Ui.FONT_BOLD,
		15,
		Ui.color.text,
		UDim2.new(1, -12, 0, 36),
		UDim2.fromOffset(6, 86)
	)
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextWrapped = true
	local tierLabel = Ui.label(
		frame,
		"Tier",
		string.upper(tier.name),
		Ui.FONT_SEMI,
		12,
		tier.color,
		UDim2.new(1, 0, 0, 14),
		UDim2.fromOffset(0, 126)
	)
	tierLabel.TextXAlignment = Enum.TextXAlignment.Center
	frame.Parent = parent
	return frame
end

-- Filler for the reel: mostly what's likely, with rare cards sprinkled in so the
-- reel teases (the odds panel shows the real chances).
local function filler(rng: Random): RollOdds.Outcome
	local outcomes = RollOdds.outcomes
	if rng:NextNumber() < 0.35 then
		local rare: { RollOdds.Outcome } = {}
		for _, outcome in outcomes do
			if outcome.kind ~= "coral" then
				table.insert(rare, outcome)
			end
		end
		return rare[rng:NextInteger(1, #rare)]
	end
	return RollOdds.pick(1, rng:NextNumber())
end

local function spinSeconds(tier: Tier): number
	if tier.order >= Tiers.byId.Mythic.order then
		return 6.2
	elseif tier.order >= Tiers.byId.Rare.order then
		return 4.8
	end
	return 3.4
end

-- The reveal for one roll result from the server.
local function reveal(result: { [string]: any })
	local outcome = RollOdds.get(result.kind, result.id)
	if outcome == nil then
		busy = false
		return
	end
	local tier = tierOf(outcome.tier)
	local big = tier.order >= Tiers.byId.Rare.order
	Input.cursorWanted = true

	local overlay = Instance.new("TextButton") -- a button, so a tap can skip
	overlay.Name = "Reveal"
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(2, 8, 16)
	overlay.BackgroundTransparency = 1
	overlay.Selectable = false
	overlay.Parent = revealGui
	Ui.tween(overlay, 0.3, { BackgroundTransparency = 0.3 })

	local window = Instance.new("Frame")
	window.Name = "Reel"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.4)
	window.Size = UDim2.fromOffset(STEP * 6, CARD_H + 20)
	window.BackgroundTransparency = 1
	window.ClipsDescendants = true
	window.Parent = overlay
	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.fromOffset(STEP * REEL_CARDS, CARD_H)
	strip.Position = UDim2.fromOffset(0, 10)
	strip.Parent = window
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, 0),
		NumberSequenceKeypoint.new(0.82, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = strip
	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0)
	marker.Position = UDim2.new(0.5, 0, 0, 0)
	marker.Size = UDim2.new(0, 3, 1, 0)
	marker.BackgroundColor3 = Ui.color.haul
	marker.BorderSizePixel = 0
	marker.ZIndex = 5
	marker.Parent = window

	local rng = Random.new()
	local cards: { Frame } = {}
	for i = 1, REEL_CARDS do
		local shown = if i == LAND_INDEX then outcome else filler(rng)
		cards[i] = card(strip, shown, (i - 1) * STEP)
	end
	-- Land somewhere inside the winning card, not dead center every time
	local windowWidth = STEP * 6
	local landX = -((LAND_INDEX - 1) * STEP + CARD_W / 2 - windowWidth / 2)
		+ rng:NextNumber(-CARD_W * 0.35, CARD_W * 0.35)
	local seconds = spinSeconds(tier)
	local tween = TweenService:Create(
		strip,
		TweenInfo.new(
			seconds,
			if big then Enum.EasingStyle.Exponential else Enum.EasingStyle.Quint,
			Enum.EasingDirection.Out
		),
		{ Position = UDim2.fromOffset(landX, 10) }
	)
	-- The card under the marker bumps as it passes
	local lastIndex = 0
	local ticking = RunService.RenderStepped:Connect(function()
		local offset = -strip.Position.X.Offset + windowWidth / 2
		local index = math.clamp(math.floor(offset / STEP) + 1, 1, REEL_CARDS)
		if index ~= lastIndex then
			lastIndex = index
			local scale = cards[index]:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			scale.Parent = cards[index]
			scale.Scale = 1.06
			Ui.tween(scale, 0.18, { Scale = 1 })
		end
	end)
	local skipped = false
	overlay.Activated:Connect(function()
		if tween.PlaybackState == Enum.PlaybackState.Playing then
			skipped = true
			tween:Cancel()
			strip.Position = UDim2.fromOffset(landX, 10)
		end
	end)
	tween:Play()
	while tween.PlaybackState == Enum.PlaybackState.Playing and not skipped do
		task.wait()
	end
	ticking:Disconnect()

	-- Landing
	local winner = cards[LAND_INDEX]
	for i, other in cards do
		if i ~= LAND_INDEX then
			Ui.tween(other, 0.3, { BackgroundTransparency = 0.6 })
		end
	end
	local winScale = winner:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	winScale.Parent = winner
	Ui.tween(winScale, 0.45, { Scale = 1.12 }, Enum.EasingStyle.Back)
	local edge = winner:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Transparency = 0
		edge.Thickness = 3
	end
	if big then
		local flash = Instance.new("Frame")
		flash.Size = UDim2.fromScale(1, 1)
		flash.BackgroundColor3 = tier.color
		flash.BackgroundTransparency = 0.25
		flash.BorderSizePixel = 0
		flash.Parent = overlay
		Ui.tween(flash, 0.9, { BackgroundTransparency = 1 })
		-- Light rays: a wide, soft sweep turning behind the result
		local rays = Instance.new("Frame")
		rays.Name = "Rays"
		rays.AnchorPoint = Vector2.new(0.5, 0.5)
		rays.Position = UDim2.fromScale(0.5, 0.4)
		rays.Size = UDim2.fromOffset(900, 900)
		rays.BackgroundColor3 = tier.color
		rays.BackgroundTransparency = 0.55
		rays.BorderSizePixel = 0
		rays.ZIndex = 0
		Ui.corner(rays, UDim.new(1, 0))
		local sweep = Instance.new("UIGradient")
		sweep.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 0.55),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(0.55, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		sweep.Parent = rays
		rays.Parent = overlay
		window.ZIndex = 2
		TweenService:Create(
			rays,
			TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
			{ Rotation = 360 }
		):Play()
	end

	-- The result panel
	local panel = Instance.new("Frame")
	panel.Name = "Result"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0.4, CARD_H / 2 + 30)
	panel.Size = UDim2.fromOffset(640, 230)
	panel.BackgroundTransparency = 1
	panel.Parent = overlay
	local tierLabel = Ui.label(
		panel,
		"Tier",
		string.upper(tier.name),
		Ui.FONT_HEAVY,
		18,
		tier.color,
		UDim2.new(1, 0, 0, 22)
	)
	tierLabel.TextXAlignment = Enum.TextXAlignment.Center
	local title = Ui.label(
		panel,
		"Title",
		string.upper(outcome.name),
		Ui.FONT_HEAVY,
		if big then 44 else 36,
		Ui.color.text,
		UDim2.new(1, 0, 0, 50),
		UDim2.fromOffset(0, 22)
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextStrokeTransparency = 0.55
	local probability = if typeof(result.probability) == "number" then result.probability else 0
	local detail
	if result.kind == "coral" then
		detail = `+{Ui.number(result.coral or 0)} Coral`
	elseif result.duplicate then
		detail =
			`Already yours · +{Ui.number(result.coral or 0)} Coral instead · {RollOdds.oneIn(probability)}`
	else
		detail = `NEW · {RollOdds.oneIn(probability)}`
	end
	if (result.luck or 1) > 1 then
		detail ..= "  ·  Lucky Charm ×2"
	end
	local detailLabel = Ui.label(
		panel,
		"Detail",
		detail,
		Ui.FONT_BOLD,
		18,
		if result.duplicate then Ui.color.muted else Ui.color.haul,
		UDim2.new(1, 0, 0, 22),
		UDim2.fromOffset(0, 76)
	)
	detailLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- Cosmetics land on your own fish
	local preview: FishPreview.Preview? = nil
	if result.kind ~= "coral" then
		local made = FishPreview.new(
			overlay,
			UDim2.fromOffset(300, 200),
			UDim2.new(0.5, 0, 0.4, 0),
			Vector2.new(0.5, 0.5)
		)
		made.frame.ZIndex = 3
		local dress = { shade = nil :: string?, parts = {} :: { [string]: string }, variant = nil :: string? }
		if result.kind == "shade" then
			dress.shade = result.id
		elseif result.kind == "variant" then
			dress.variant = result.id
		elseif result.kind == "part" then
			local part = Config.Exotics.partsById[result.id]
			if part then
				dress.parts[part.slot] = part.id
			end
		end
		made:show(dress)
		preview = made
		-- The reel steps aside for the fish
		Ui.tween(window, 0.4, { Position = UDim2.fromScale(0.5, 0.16) })
		Ui.tween(winScale, 0.4, { Scale = 0.9 })
	end

	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 46)
	buttons.Position = UDim2.fromOffset(0, 118)
	buttons.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = buttons

	local closed = false
	local function finish()
		if closed then
			return
		end
		closed = true
		if preview then
			preview:destroy()
		end
		overlay.Visible = false
		task.delay(0.1, function()
			overlay:Destroy()
		end)
		Input.cursorWanted = MenuController.isOpen()
		busy = false
	end
	if result.kind ~= "coral" and not result.duplicate then
		local wear = Ui.button(buttons, "Wear", "WEAR IT", UDim2.fromOffset(150, 44), UDim2.new(), "gold")
		wear.Activated:Connect(function()
			ClientState.request("Equip", result.kind, result.id)
			finish()
		end)
	end
	local left = if typeof(result.rollsLeft) == "number" then result.rollsLeft else 0
	if left > 0 then
		local again = Ui.button(
			buttons,
			"Again",
			`ROLL AGAIN ({left})`,
			UDim2.fromOffset(190, 44),
			UDim2.new(),
			"primary"
		)
		again.Activated:Connect(function()
			finish()
			RollController.roll()
		end)
	end
	local done = Ui.button(buttons, "Done", "DONE", UDim2.fromOffset(120, 44), UDim2.new(), "secondary")
	done.Activated:Connect(finish)
	if Input.isGamepad() then
		game:GetService("GuiService").SelectedObject = buttons:FindFirstChildWhichIsA("TextButton")
	end
end

-- Asks the server for a roll (the reveal plays when the result arrives).
function RollController.roll()
	if busy or (state().rollsReady or 0) < 1 then
		return
	end
	busy = true
	waitingSince = os.clock()
	ClientState.request("Roll")
end

local function buildWallet()
	local card = Ui.panel(hud, "Wallet", UDim2.fromOffset(232, 66), UDim2.fromOffset(18, 144))
	Ui.belowTopBar(hud, card, 144)
	local coralDot = Instance.new("Frame")
	coralDot.Size = UDim2.fromOffset(10, 10)
	coralDot.Position = UDim2.fromOffset(14, 14)
	coralDot.BackgroundColor3 = Tiers.byId.Coral.color
	coralDot.BorderSizePixel = 0
	Ui.corner(coralDot, UDim.new(1, 0))
	coralDot.Parent = card
	coralText = Ui.label(
		card,
		"Coral",
		"0 CORAL",
		Ui.FONT_HEAVY,
		17,
		Ui.color.text,
		UDim2.fromOffset(190, 20),
		UDim2.fromOffset(30, 8)
	)
	local shellDot = coralDot:Clone()
	shellDot.Position = UDim2.fromOffset(14, 38)
	shellDot.BackgroundColor3 = Color3.fromRGB(242, 228, 204)
	shellDot.Parent = card
	shellText = Ui.label(
		card,
		"Shells",
		"0 / 50 SHELLS",
		Ui.FONT_BOLD,
		14,
		Ui.color.muted,
		UDim2.fromOffset(120, 18),
		UDim2.fromOffset(30, 32)
	)
	local _, fill = Ui.bar(
		card,
		"ShellProgress",
		UDim2.fromOffset(84, 5),
		UDim2.fromOffset(134, 39),
		Color3.fromRGB(242, 228, 204)
	)
	shellFill = fill

	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(18, 218)
	row.Size = UDim2.fromOffset(420, 36)
	row.Parent = hud
	Ui.belowTopBar(hud, row, 218)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	rollButton = Ui.button(row, "Roll", "ROLL", UDim2.fromOffset(120, 34), UDim2.new(), "gold")
	rollButton.LayoutOrder = 1
	rollButton.TextSize = 15
	rollScale = rollButton:FindFirstChildOfClass("UIScale") :: UIScale
	rollButton.Activated:Connect(RollController.roll)
	local odds = Ui.button(row, "Odds", "ODDS", UDim2.fromOffset(70, 34), UDim2.new(), "secondary")
	odds.LayoutOrder = 2
	odds.TextSize = 14
	odds.Activated:Connect(MenuController.openOdds)
	local wardrobe =
		Ui.button(row, "Wardrobe", "WARDROBE", UDim2.fromOffset(110, 34), UDim2.new(), "secondary")
	wardrobe.LayoutOrder = 3
	wardrobe.TextSize = 14
	wardrobe.Activated:Connect(MenuController.openWardrobe)
	local fish = Ui.button(row, "Fish", "FISH", UDim2.fromOffset(70, 34), UDim2.new(), "secondary")
	fish.LayoutOrder = 4
	fish.TextSize = 14
	fish.Activated:Connect(MenuController.openSpecies)
	-- Not selectable: a controller selection once stuck on ODDS and ate key presses
	-- (playtest 2026-10-06). The D-pad opens these instead (RollController.start).
	for _, button in { rollButton, odds, wardrobe, fish } do
		button.Selectable = false
	end
end

local function onState(s: { [string]: any })
	local perRoll = s.shellsPerRoll or Config.Rolls.shellsPerRoll
	local shells = s.shells or 0
	local ready = s.rollsReady or 0
	coralText.Text = `{Ui.number(s.coral or 0)} CORAL`
	shellText.Text = `{shells % perRoll} / {perRoll} SHELLS`
	Ui.tween(shellFill, 0.4, { Size = UDim2.fromScale((shells % perRoll) / perRoll, 1) })
	rollButton.Visible = ready > 0
	local key = if UserInputService.KeyboardEnabled then " (R)" else ""
	rollButton.Text = if ready > 1 then `ROLL ×{ready}{key}` else `ROLL{key}`
end

function RollController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	hud = Ui.screen("Wallet", playerGui, 6)
	revealGui = Ui.screen("RollReveal", playerGui, 20)
	buildWallet()
	ClientState.changed:connect(onState)
	if ClientState.current then
		onState(ClientState.current)
	end
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local rollResult = remotes:WaitForChild("RollResult") :: RemoteEvent
	rollResult.OnClientEvent:Connect(function(result: { [string]: any })
		task.spawn(reveal, result)
	end)
	-- Controllers: the D-pad opens the HUD's menus (up Fish, left Wardrobe, right
	-- Odds, down Roll) while no menu has the selection
	GuiService.AutoSelectGuiEnabled = false
	ContextActionService:BindAction("ApexHudPad", function(_, inputState, input)
		if
			inputState ~= Enum.UserInputState.Begin
			or MenuController.isOpen()
			or GuiService.SelectedObject ~= nil
		then
			return Enum.ContextActionResult.Pass
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.DPadUp then
			MenuController.openSpecies()
		elseif key == Enum.KeyCode.DPadLeft then
			MenuController.openWardrobe()
		elseif key == Enum.KeyCode.DPadRight then
			MenuController.openOdds()
		elseif key == Enum.KeyCode.DPadDown and rollButton.Visible then
			RollController.roll()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight)
	-- Keyboards: R rolls, without freeing the cursor (Alt+click on ROLL once missed)
	ContextActionService:BindAction("ApexRollKey", function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin or not rollButton.Visible or MenuController.isOpen() then
			return Enum.ContextActionResult.Pass
		end
		RollController.roll()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.R)
	-- The roll button breathes while a roll is ready; a lost request frees it again
	RunService.Heartbeat:Connect(function()
		if rollButton.Visible and not busy then
			rollScale.Scale = 1 + math.sin(os.clock() * 4) * 0.04
		end
		if busy and revealGui:FindFirstChild("Reveal") == nil and os.clock() - waitingSince > 4 then
			busy = false
		end
	end)
end

return RollController
