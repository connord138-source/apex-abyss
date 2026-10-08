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
local Sfx = require(script.Parent.Parent.Sfx)
local Format = require(ReplicatedStorage.Shared.Format)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local ClientState = require(script.Parent.Parent.ClientState)
local CardPhoto = require(script.Parent.Parent.CardPhoto)
local FishPreview = require(script.Parent.Parent.FishPreview)
local Input = require(script.Parent.Parent.Input)
local Ui = require(script.Parent.Parent.Ui)
local MenuController = require(script.Parent.MenuController)

local Tiers = Config.Tiers
type Tier = typeof(Tiers.list[1])

local RollController = {}

local CARD_W, CARD_H, GAP = 168, 228, 12
local VISIBLE = 5 -- cards across the reel's window
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
local mapsButton: TextButton

local function state(): { [string]: any }
	return ClientState.current or {}
end

local function tierOf(id: string): Tier
	return Tiers.byId[id] or Tiers.byId.Common
end

-- Card art (owner, 2026-10-07: "better designs for the random rolls"): drawn with
-- frames, no image assets. A shade shows a little fish in its own colors (with its
-- glow, glints or rainbow); coral shows a branching sprig and the amount; a part
-- shows which slot it changes; a variant shows its species. Behind it all, a tier
-- gradient, a diagonal sheen and a tier badge.
local function box(
	parent: Instance,
	size: UDim2,
	position: UDim2,
	color: Color3,
	radius: UDim?,
	anchor: Vector2?
): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor or Vector2.zero
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	Ui.corner(frame, radius or UDim.new(0, 4))
	frame.Parent = parent
	return frame
end

-- A card in the reel (owner, 2026-10-08: "photos for the rolls need to be dialed way
-- up and look much more professional"): a studio shot of the outcome (CardPhoto: your
-- own fish wearing the shade, or a still life) under a spotlight on a backdrop that
-- fades into the tier's color, a floor shadow, a nameplate with the tier gem, an
-- inner hairline, a moving foil sheen from Epic up and a holographic edge from
-- Mythic up. The photo itself is attached when the card nears the window
-- (`attachPhoto`), so a reel of 46 cards builds only the shots that are seen.
local INK = Color3.fromRGB(8, 15, 25)
local KIND_LABEL: { [string]: string } = {
	shade = "SHADE",
	coral = "CORAL",
	part = "ABYSSAL PART",
	variant = "VARIANT",
	shells = "SHELLS",
	haul = "HAUL",
	dna = "DNA",
	wraps = "KELP WRAPS",
	charm = "CHARM",
}

local function card(parent: Instance, outcome: RollOdds.Outcome, x: number): Frame
	local tier = tierOf(outcome.tier)
	local frame = Instance.new("Frame")
	frame.Name = "Card"
	frame.Size = UDim2.fromOffset(CARD_W, CARD_H)
	frame.Position = UDim2.fromOffset(x, 0)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	Ui.corner(frame, UDim.new(0, 12))
	-- The backdrop: night-blue at the top into the tier's color at the floor
	local backdrop = Instance.new("UIGradient")
	backdrop.Rotation = 90
	backdrop.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, INK),
		ColorSequenceKeypoint.new(0.5, tier.color:Lerp(INK, 0.8)),
		ColorSequenceKeypoint.new(1, tier.color:Lerp(INK, 0.5)),
	})
	backdrop.Parent = frame
	-- The spotlight behind the subject: soft rings, brightest in the middle
	for i, ring in { { 170, 0.9 }, { 124, 0.86 }, { 80, 0.82 } } do
		local glow = box(
			frame,
			UDim2.fromOffset(ring[1], ring[1]),
			UDim2.fromOffset(CARD_W / 2, 84),
			tier.color:Lerp(Color3.new(1, 1, 1), 0.35 + i * 0.1),
			UDim.new(1, 0),
			Vector2.new(0.5, 0.5)
		)
		glow.BackgroundTransparency = ring[2]
		glow.ZIndex = 1
	end
	-- The floor shadow under it
	local shadow = box(
		frame,
		UDim2.fromOffset(112, 16),
		UDim2.fromOffset(CARD_W / 2, 150),
		Color3.new(0, 0, 0),
		UDim.new(1, 0),
		Vector2.new(0.5, 0.5)
	)
	shadow.BackgroundTransparency = 0.55
	shadow.ZIndex = 2
	-- Where the photo goes
	local slot = Instance.new("Frame")
	slot.Name = "Shot"
	slot.BackgroundTransparency = 1
	slot.Size = UDim2.new(1, 0, 0, 160)
	slot.Position = UDim2.fromOffset(0, 6)
	slot.ZIndex = 3
	slot.Parent = frame
	-- What it is, small, top left
	local kind = Ui.label(
		frame,
		"Kind",
		KIND_LABEL[outcome.kind] or string.upper(outcome.kind),
		Ui.FONT_HEAVY,
		10,
		Color3.new(1, 1, 1),
		UDim2.new(1, -20, 0, 14),
		UDim2.fromOffset(10, 8)
	)
	kind.TextTransparency = 0.35
	kind.ZIndex = 5
	-- The nameplate
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0, 1)
	plate.Position = UDim2.fromScale(0, 1)
	plate.Size = UDim2.new(1, 0, 0, 66)
	plate.BackgroundColor3 = Color3.fromRGB(4, 9, 16)
	plate.BorderSizePixel = 0
	plate.ZIndex = 4
	local plateFade = Instance.new("UIGradient")
	plateFade.Rotation = 90
	plateFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.35, 0.25),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	plateFade.Parent = plate
	plate.Parent = frame
	local name = Ui.label(
		plate,
		"Name",
		string.upper(outcome.name),
		Ui.FONT_HEAVY,
		14,
		Ui.color.text,
		UDim2.new(1, -14, 0, 32),
		UDim2.fromOffset(7, 12)
	)
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextYAlignment = Enum.TextYAlignment.Bottom
	name.TextWrapped = true
	name.ZIndex = 5
	local gem = box(
		plate,
		UDim2.fromOffset(8, 8),
		UDim2.new(0.5, 0, 1, -14),
		tier.color,
		UDim.new(0, 1),
		Vector2.new(0.5, 0.5)
	)
	gem.Rotation = 45
	gem.ZIndex = 5
	local tierRow = Ui.label(
		plate,
		"Tier",
		string.upper(tier.name),
		Ui.FONT_HEAVY,
		11,
		tier.color,
		UDim2.new(0.5, -12, 0, 14),
		UDim2.new(0, 0, 1, -21)
	)
	tierRow.TextXAlignment = Enum.TextXAlignment.Right
	tierRow.ZIndex = 5
	local tierRight = tierRow:Clone()
	tierRight.Text = if tier.order >= Tiers.byId.Rare.order then "RARE FIND" else "REEF STOCK"
	tierRight.Position = UDim2.new(0.5, 12, 1, -21)
	tierRight.TextXAlignment = Enum.TextXAlignment.Left
	tierRight.TextColor3 = Ui.color.muted
	tierRight.Parent = plate
	-- The frame: the tier's edge and a white hairline just inside it
	local stroke = Ui.stroke(frame, tier.color, 0.15, 2)
	stroke.Name = "Edge"
	local hairline = Instance.new("Frame")
	hairline.Name = "Hairline"
	hairline.BackgroundTransparency = 1
	hairline.Position = UDim2.fromOffset(5, 5)
	hairline.Size = UDim2.new(1, -10, 1, -10)
	hairline.ZIndex = 6
	Ui.corner(hairline, UDim.new(0, 9))
	Ui.stroke(hairline, Color3.new(1, 1, 1), 0.82, 1)
	hairline.Parent = frame
	-- Foil from Epic up: a soft band of light sweeping across now and then
	if tier.order >= Tiers.byId.Epic.order then
		local foil = Instance.new("Frame")
		foil.Name = "Foil"
		foil.BackgroundColor3 = Color3.new(1, 1, 1)
		foil.BorderSizePixel = 0
		foil.AnchorPoint = Vector2.new(0.5, 0.5)
		foil.Size = UDim2.new(0, 46, 1.8, 0)
		foil.Position = UDim2.new(0, -60, 0.5, 0)
		foil.Rotation = 18
		foil.ZIndex = 7
		local band = Instance.new("UIGradient")
		band.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.72),
			NumberSequenceKeypoint.new(1, 1),
		})
		band.Parent = foil
		foil.Parent = frame
		TweenService:Create(
			foil,
			TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 1.6),
			{ Position = UDim2.new(1, 60, 0.5, 0) }
		):Play()
	end
	-- Holo from Mythic up: the edge runs through every color
	if tier.order >= Tiers.byId.Mythic.order then
		local holo = Instance.new("UIGradient")
		holo.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 92, 146)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 214, 90)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 255, 200)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(90, 160, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 92, 146)),
		})
		holo.Parent = stroke
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = 3
		TweenService:Create(
			holo,
			TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
			{ Rotation = 360 }
		):Play()
	end
	-- Dimmed when another card wins
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 9
	dim.Parent = frame
	frame.Parent = parent
	return frame
end

-- Puts the studio shot on a card (once)
local function attachPhoto(frame: Frame, outcome: RollOdds.Outcome)
	if frame:GetAttribute("Shot") then
		return
	end
	frame:SetAttribute("Shot", true)
	local slot = frame:FindFirstChild("Shot")
	if slot and slot:IsA("GuiObject") then
		CardPhoto.new(slot, outcome :: any, tierOf(outcome.tier).color)
	end
end

-- Filler for the reel: mostly what's likely, with rare cards sprinkled in so the
-- reel teases (the odds panel shows the real chances).
local fishShades: { [string]: boolean } = {} -- the current fish's (they never roll again for it)

local function filler(rng: Random): RollOdds.Outcome
	local outcomes = RollOdds.outcomes
	if rng:NextNumber() < 0.35 then
		local rare: { RollOdds.Outcome } = {}
		for _, outcome in outcomes do
			if outcome.kind ~= "coral" and not (outcome.kind == "shade" and fishShades[outcome.id]) then
				table.insert(rare, outcome)
			end
		end
		if #rare > 0 then
			return rare[rng:NextInteger(1, #rare)]
		end
	end
	return RollOdds.pick(1, rng:NextNumber(), fishShades)
end

local function spinSeconds(tier: Tier): number
	if tier.order >= Tiers.byId.Mythic.order then
		return 6.2
	elseif tier.order >= Tiers.byId.Rare.order then
		return 4.8
	end
	return 3.4
end

-- Filler for a treasure reel: the rewards a map tier can hold (Config/Treasure).
local function treasureFiller(rng: Random, poolTier: string): RollOdds.Outcome
	local tier = Config.Treasure.byId[poolTier]
	local rewards = if tier then tier.rewards else Config.Treasure.tiers[1].rewards
	local total = 0
	for _, reward in rewards do
		total += reward.weight
	end
	local r = rng:NextNumber() * total
	local picked = rewards[#rewards]
	for _, reward in rewards do
		r -= reward.weight
		if r <= 0 then
			picked = reward
			break
		end
	end
	return { id = picked.id, kind = picked.kind :: any, name = picked.name, tier = picked.tier }
end

-- The reveal for one result from the server: a roll (its outcome is looked up in
-- the odds table) or a treasure (`result.outcome` comes along, and the reel's
-- filler is that map tier's loot).
local function reveal(result: { [string]: any })
	local outcome: RollOdds.Outcome? = if typeof(result.outcome) == "table"
		then result.outcome
		else RollOdds.get(result.kind, result.id)
	if outcome == nil then
		busy = false
		return
	end
	local treasurePool: string? = if typeof(result.pool) == "string" then result.pool else nil
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
	window.Size = UDim2.fromOffset(STEP * VISIBLE, CARD_H + 24)
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
	local outcomes: { RollOdds.Outcome } = {}
	CardPhoto.reset() -- shots of this fish, as it is now
	for i = 1, REEL_CARDS do
		local shown = if i == LAND_INDEX
			then outcome
			elseif treasurePool then treasureFiller(rng, treasurePool)
			else filler(rng)
		outcomes[i] = shown
		cards[i] = card(strip, shown, (i - 1) * STEP)
	end
	-- Shots for the cards in (or about to enter) the window, and the winner's
	local function shoot(from: number, to: number)
		for i = math.max(from, 1), math.min(to, REEL_CARDS) do
			attachPhoto(cards[i], outcomes[i])
		end
	end
	shoot(1, VISIBLE + 2)
	shoot(LAND_INDEX - 3, LAND_INDEX + 3)
	-- Land somewhere inside the winning card, not dead center every time
	local windowWidth = STEP * VISIBLE
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
			shoot(index - 3, index + 4)
			Sfx.play("Tick", { volume = 0.35, pitch = 0.95 + math.random() * 0.1 })
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
	Sfx.play("Reel", { volume = 0.5 })
	tween:Play()
	while tween.PlaybackState == Enum.PlaybackState.Playing and not skipped do
		task.wait()
	end
	Sfx.play(`Roll{tier.id}`, { volume = 0.85 })
	ticking:Disconnect()

	-- Landing
	local winner = cards[LAND_INDEX]
	for i, other in cards do
		local dim = other:FindFirstChild("Dim")
		if i ~= LAND_INDEX and dim and dim:IsA("Frame") then
			Ui.tween(dim, 0.3, { BackgroundTransparency = 0.45 })
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
	elseif result.kind == "shells" then
		detail = `+{Ui.number(result.shells or 0)} Shells`
	elseif result.kind == "haul" then
		detail = `+{Format.mass(result.haul or 0)} of Haul, straight into your dive`
	elseif result.kind == "dna" then
		detail = `+{Ui.number(result.dna or 0)} DNA`
	elseif result.kind == "wraps" then
		detail = `+{result.wraps or 0} Kelp Wraps (H heals you)`
	elseif result.kind == "charm" then
		detail = "A Lucky Charm: your next roll's rare odds ×2"
	elseif result.duplicate then
		detail = `Already yours · +{Ui.number(result.coral or 0)} Coral instead`
			.. (if treasurePool then "" else ` · {RollOdds.oneIn(probability)}`)
	else
		detail = if treasurePool
			then "NEW · dug up from treasure"
			else `NEW · {RollOdds.oneIn(probability)}`
	end
	if (result.luck or 1) > 1 then
		detail ..= "  ·  Lucky Charm ×2"
	end
	if typeof(result.found) == "number" then
		detail ..= `  ·  Treasures found: {result.found}`
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
	-- A shade's three colors, so the result reads at a glance
	if result.kind == "shade" then
		local shade = Config.Shades.byId[result.id]
		if shade then
			local swatches = Instance.new("Frame")
			swatches.BackgroundTransparency = 1
			swatches.AnchorPoint = Vector2.new(0.5, 0)
			swatches.Position = UDim2.new(0.5, 0, 0, 100)
			swatches.Size = UDim2.fromOffset(110, 20)
			swatches.Parent = panel
			local layout = Instance.new("UIListLayout")
			layout.FillDirection = Enum.FillDirection.Horizontal
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			layout.Padding = UDim.new(0, 8)
			layout.Parent = swatches
			for _, color in { shade.back, shade.belly, shade.fin } do
				local swatch = box(swatches, UDim2.fromOffset(20, 20), UDim2.new(), color, UDim.new(0, 6))
				Ui.stroke(swatch, Color3.new(1, 1, 1), 0.6, 1)
			end
		end
	end
	-- The winner bursts: tier-colored motes fly out of the card
	if big then
		for i = 1, 22 do
			local mote = box(
				overlay,
				UDim2.fromOffset(6, 6),
				UDim2.fromScale(0.5, 0.4),
				tier.color,
				UDim.new(1, 0),
				Vector2.new(0.5, 0.5)
			)
			mote.ZIndex = 4
			local angle = (i / 22) * 2 * math.pi + math.random() * 0.3
			local distance = 220 + math.random() * 160
			Ui.tween(mote, 0.9 + math.random() * 0.4, {
				Position = UDim2.new(0.5, math.cos(angle) * distance, 0.4, math.sin(angle) * distance * 0.7),
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(2, 2),
			}, Enum.EasingStyle.Quad)
			task.delay(1.4, function()
				mote:Destroy()
			end)
		end
	end

	-- Cosmetics land on your own fish
	local cosmetic = result.kind == "shade" or result.kind == "part" or result.kind == "variant"
	local preview: FishPreview.Preview? = nil
	if cosmetic then
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
	if cosmetic and not result.duplicate then
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

-- Opens a dug-up treasure (TreasureController) with the roll reveal.
function RollController.revealTreasure(result: { [string]: any })
	while busy do
		task.wait(0.1)
	end
	busy = true
	waitingSince = os.clock()
	reveal(result)
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
	row.Size = UDim2.fromOffset(540, 36)
	row.Parent = hud
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
	mapsButton = Ui.button(row, "Maps", "MAPS", UDim2.fromOffset(84, 34), UDim2.new(), "secondary")
	mapsButton.LayoutOrder = 5
	mapsButton.TextSize = 14
	mapsButton.Visible = false
	mapsButton.Activated:Connect(MenuController.openSatchel)
	-- Not selectable: a controller selection once stuck on ODDS and ate key presses
	-- (playtest 2026-10-06). The D-pad opens these instead (RollController.start).
	for _, button in { rollButton, odds, wardrobe, fish, mapsButton } do
		button.Selectable = false
	end
end

local function onState(s: { [string]: any })
	fishShades = if typeof(s.shades) == "table" then s.shades else {}
	local perRoll = s.shellsPerRoll or Config.Rolls.shellsPerRoll
	local shells = s.shells or 0
	local ready = s.rollsReady or 0
	coralText.Text = `{Ui.number(s.coral or 0)} CORAL`
	shellText.Text = `{shells % perRoll} / {perRoll} SHELLS`
	Ui.tween(shellFill, 0.4, { Size = UDim2.fromScale((shells % perRoll) / perRoll, 1) })
	rollButton.Visible = ready > 0
	local held = if typeof(s.maps) == "table" then #s.maps else 0
	mapsButton.Visible = held > 0
	mapsButton.Text = `MAPS ({held})`
	Ui.setButtonStyle(mapsButton, if s.activeMap and s.activeMap ~= "" then "primary" else "secondary")
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
