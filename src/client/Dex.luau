--!strict
-- The INDEX's collection tabs, as a Pokédex (owner, 2026-11-03: "Index needs to be
-- dialed up way more. Think pokedex from pokemon. We want to have a visual of each skin
-- in here and if they are locked then just a teaser of the locked skin"): numbered cards
-- with a real photo of each skin, part, variant and fish, how much of the collection is
-- yours, and an entry beside the grid with a big photo and how to get it. A locked one
-- is a dark silhouette in a glow of its rarity, its name and how to get it still shown.
-- MenuController.openIndex hosts it; the GUIDE tab stays a list there. Photos go on as
-- cards come into view, a couple a frame (CardPhoto: each is a little 3D scene).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local CardPhoto = require(script.Parent.CardPhoto)
local Input = require(script.Parent.Input)
local Ui = require(script.Parent.Ui)

local Tiers = Config.Tiers

local SILHOUETTE = Color3.fromRGB(10, 20, 30)
local EVERY_FISH = "__every"
local PHOTOS_A_FRAME = 2

-- What the Index passes in: its words for how things are got
export type Deps = {
	shadeHow: (shade: any, s: any) -> string,
	fxWords: (fx: any) -> string,
	passSource: (kind: string, id: string) -> string?,
	unlockHow: (species: any) -> string,
}

type Entry = {
	key: string,
	number: number,
	name: string,
	tier: any,
	kind: string,
	id: string,
	species: string?, -- the fish it's shown on (nil: the one you're swimming as)
	record: any,
}

type Card = {
	entry: Entry,
	frame: TextButton,
	visual: Frame,
	status: TextLabel,
	glow: Frame,
	attached: boolean,
	photo: ViewportFrame?,
}

export type Dex = {
	show: (tab: string, s: { [string]: any }) -> (),
	update: (s: { [string]: any }) -> (),
	hide: () -> (),
	destroy: () -> (),
}

local function tierOf(id: string): any
	return Tiers.byId[id] or Tiers.byId.Common
end

-- Every entry of a tab, numbered the same for everyone
local function entriesOf(tab: string, s: { [string]: any }): { Entry }
	local out: { Entry } = {}
	local function add(kind: string, record: any, species: string?, tier: any)
		table.insert(out, {
			key = `{kind}:{record.id}:{species or ""}`,
			number = #out + 1,
			name = record.name,
			tier = tier,
			kind = kind,
			id = record.id,
			species = species,
			record = record,
		})
	end
	if tab == "Skins" then
		for _, species in Config.Species.list do
			local line: { any } = Config.Shades.lines[species.id] or {}
			for _, shade in line do
				add("shade", shade, species.id, tierOf(shade.tier))
			end
		end
		local owned = s.shades or {}
		local other = s.otherShades or {}
		for _, shade in Config.Shades.list do
			-- (a week's limited skin shows once it's yours)
			if shade.species == nil and (shade.week == nil or owned[shade.id] or other[shade.id]) then
				add("shade", shade, nil, tierOf(shade.tier))
			end
		end
	elseif tab == "Parts" then
		for _, part in Config.Exotics.parts do
			add("part", part, nil, Tiers.byId.Abyssal)
		end
	elseif tab == "Variants" then
		for _, variant in Config.Exotics.variants do
			add("variant", variant, variant.species, Tiers.byId.Abyssal)
		end
	elseif tab == "Fish" then
		for _, species in Config.Species.list do
			add("fish", species, species.id, { name = species.role, color = species.fin, order = 0 })
		end
	else
		for _, trail in Config.Trails.list do
			add("trail", trail, nil, tierOf(trail.tier))
		end
	end
	return out
end

-- Whether this player has it; a universal skin on another fish counts, shown dimmed
local function hasEntry(entry: Entry, s: { [string]: any }): (boolean, boolean)
	if entry.kind == "shade" then
		if entry.species then
			local byFish = (s.allShades or {})[entry.species]
			return typeof(byFish) == "table" and byFish[entry.id] == true, false
		end
		local here = (s.shades or {})[entry.id] == true
		return here or (s.otherShades or {})[entry.id] == true, not here
	elseif entry.kind == "part" then
		return (s.parts or {})[entry.id] == true, false
	elseif entry.kind == "variant" then
		return (s.variants or {})[entry.id] == true, false
	elseif entry.kind == "fish" then
		return (s.unlocked or {})[entry.id] == true, false
	end
	return (s.trails or {})[entry.id] == true, false
end

-- The entry's words, a paragraph a line
local function linesOf(entry: Entry, s: { [string]: any }, deps: Deps): { string }
	local record = entry.record
	if entry.kind == "shade" then
		local lines = { deps.shadeHow(record, s) }
		if record.fx then
			table.insert(lines, `Effects: {deps.fxWords(record.fx)}.`)
		end
		return lines
	elseif entry.kind == "part" then
		return {
			record.blurb,
			`Bonus: {record.bonus.text}.`,
			`Roll it as any fish: about {RollOdds.oneIn(1 / record.chance)}. One to a slot ({record.slot}).`,
		}
	elseif entry.kind == "variant" then
		local fish = Config.Species.byId[record.species]
		local name = if fish then fish.name else "that fish"
		return {
			record.blurb,
			`Bonus: {record.bonus.text}.`,
			`Roll it as {name}: about {RollOdds.oneIn(1 / record.chance)}.`,
		}
	elseif entry.kind == "fish" then
		return {
			`Good at: {table.concat(record.perks, ", ")}.`,
			`Watch out: {table.concat(record.drawbacks, ", ")}.`,
			`Special: {Config.Specials.bySpecies[record.id].name}. {Config.Specials.bySpecies[record.id].blurb}`,
			deps.unlockHow(record),
		}
	end
	return { record.blurb, `{deps.passSource("trail", record.id) or "A later Tide Pass season"}.` }
end

-- What the entry is, under its name
local function subtitleOf(entry: Entry): string
	if entry.kind == "shade" then
		local fish = if entry.species then Config.Species.byId[entry.species] else nil
		return `{entry.tier.name} skin · {if fish then fish.name else "every fish"}`
	elseif entry.kind == "part" then
		return `Abyssal part · {entry.record.slot} slot · any fish`
	elseif entry.kind == "variant" then
		local fish = Config.Species.byId[entry.record.species]
		return `Abyssal variant · {if fish then fish.name else ""}`
	elseif entry.kind == "fish" then
		return entry.record.role
	end
	return `{entry.tier.name} boost trail · every fish`
end

-- A trail has no model: three streaks of its colour, fading behind
local function trailSwatch(parent: GuiObject, color: Color3, z: number)
	for i = 1, 3 do
		local streak = Instance.new("Frame")
		streak.Name = "Streak"
		streak.AnchorPoint = Vector2.new(0.5, 0.5)
		streak.Position = UDim2.fromScale(0.5, 0.26 + (i - 1) * 0.24)
		streak.Size = UDim2.new(0.74 - math.abs(i - 2) * 0.14, 0, 0, 7)
		streak.BackgroundColor3 = color
		streak.BorderSizePixel = 0
		streak.ZIndex = z
		Ui.corner(streak, UDim.new(1, 0))
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.6, 0.25),
			NumberSequenceKeypoint.new(1, 0),
		})
		fade.Parent = streak
		streak.Parent = parent
	end
end

-- A soft glow of the rarity behind a photo
local function glowOf(parent: GuiObject, color: Color3, z: number): Frame
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.BackgroundColor3 = color
	glow.BorderSizePixel = 0
	glow.Size = UDim2.fromScale(1, 1)
	glow.ZIndex = z
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.92),
		NumberSequenceKeypoint.new(1, 0.55),
	})
	fade.Parent = glow
	glow.Parent = parent
	return glow
end

local Dex = {}

function Dex.new(parent: Frame, deps: Deps): Dex
	local touch = Input.isTouch()
	local ENTRY_W = if touch then 250 else 290
	local CARD = if touch then Vector2.new(112, 112) else Vector2.new(124, 128)

	local holder = Instance.new("Frame")
	holder.Name = "Dex"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = parent

	-- The progress line over the grid
	local counted = Ui.label(
		holder,
		"Counted",
		"",
		Ui.FONT_HEAVY,
		14,
		Ui.color.text,
		UDim2.fromOffset(240, 18),
		UDim2.fromOffset(0, 0)
	)
	local bar, barFill = Ui.bar(
		holder,
		"Progress",
		UDim2.new(1, -(ENTRY_W + 262), 0, 8),
		UDim2.fromOffset(246, 5),
		Ui.color.accent
	)
	bar.ZIndex = 2

	-- The fish filter, skins only
	local chips = Instance.new("Frame")
	chips.Name = "Chips"
	chips.BackgroundTransparency = 1
	chips.Position = UDim2.fromOffset(0, 22)
	chips.Size = UDim2.new(1, -(ENTRY_W + 12), 0, 26)
	chips.Parent = holder
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Padding = UDim.new(0, 4)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chips

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 5
	grid.ScrollBarImageColor3 = Ui.color.stroke
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.Parent = holder
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(CARD.X, CARD.Y)
	gridLayout.CellPadding = UDim2.fromOffset(6, 6)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	-- The entry: a big photo, its number and name, how to get it
	local panel = Instance.new("Frame")
	panel.Name = "Entry"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.fromScale(1, 0)
	panel.Size = UDim2.new(0, ENTRY_W, 1, -2)
	panel.BackgroundColor3 = Ui.color.track
	panel.BackgroundTransparency = 0.35
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	Ui.corner(panel, UDim.new(0, 12))
	local panelStroke = Ui.stroke(panel, Ui.color.stroke, 0.3, 1.5)
	panel.Parent = holder
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.BackgroundTransparency = 1
	stage.ClipsDescendants = true
	stage.Size = UDim2.new(1, 0, 0, if touch then 130 else 176)
	stage.Parent = panel
	local stageGlow = glowOf(stage, Ui.color.accent, 1)
	local numberLabel = Ui.label(
		panel,
		"Number",
		"",
		Ui.FONT_HEAVY,
		13,
		Ui.color.muted,
		UDim2.fromOffset(70, 18),
		UDim2.fromOffset(10, 8)
	)
	numberLabel.ZIndex = 4
	local ownedLabel = Ui.label(
		panel,
		"Owned",
		"",
		Ui.FONT_HEAVY,
		13,
		Ui.color.safe,
		UDim2.new(1, -90, 0, 18),
		UDim2.fromOffset(80, 8)
	)
	ownedLabel.TextXAlignment = Enum.TextXAlignment.Right
	ownedLabel.ZIndex = 4
	local textTop = stage.Size.Y.Offset + 6
	local nameLabel = Ui.label(
		panel,
		"Name",
		"",
		Ui.FONT_HEAVY,
		if touch then 18 else 21,
		Ui.color.text,
		UDim2.new(1, -20, 0, 26),
		UDim2.fromOffset(10, textTop)
	)
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	local subLabel = Ui.label(
		panel,
		"Sub",
		"",
		Ui.FONT_BOLD,
		13,
		Ui.color.accent,
		UDim2.new(1, -20, 0, 18),
		UDim2.fromOffset(10, textTop + 26)
	)
	subLabel.TextTruncate = Enum.TextTruncate.AtEnd
	local words = Instance.new("ScrollingFrame")
	words.Name = "Words"
	words.BackgroundTransparency = 1
	words.BorderSizePixel = 0
	words.Position = UDim2.fromOffset(10, textTop + 48)
	words.Size = UDim2.new(1, -16, 1, -(textTop + 54))
	words.ScrollBarThickness = 4
	words.ScrollBarImageColor3 = Ui.color.stroke
	words.CanvasSize = UDim2.new()
	words.AutomaticCanvasSize = Enum.AutomaticSize.Y
	words.Parent = panel
	local wordsText = Ui.label(
		words,
		"Text",
		"",
		Ui.FONT,
		if touch then 14 else 15,
		Ui.color.text,
		UDim2.new(1, -8, 0, 0),
		UDim2.new()
	)
	wordsText.TextWrapped = true
	wordsText.TextYAlignment = Enum.TextYAlignment.Top
	wordsText.AutomaticSize = Enum.AutomaticSize.Y

	local tab = ""
	local filter: string? = nil
	local cards: { Card } = {}
	local entries: { Entry } = {}
	local chosen: Entry? = nil
	local stagePhoto: Instance? = nil
	local latest: { [string]: any } = {}

	-- Puts a photo of the entry in `into`; locked, it's a dark silhouette
	local function photoOf(
		entry: Entry,
		into: GuiObject,
		has: boolean,
		dimmed: boolean,
		z: number
	): ViewportFrame?
		if entry.kind == "trail" then
			return nil
		end
		local photo = CardPhoto.new(
			into,
			{
				id = entry.id,
				kind = entry.kind,
				name = entry.name,
				tier = entry.tier.id or "Common",
				species = entry.species,
			} :: any,
			entry.tier.color
		)
		if photo then
			photo.ZIndex = z
			photo.ImageColor3 = if not has
				then SILHOUETTE
				elseif dimmed then Color3.fromRGB(190, 196, 206)
				else Color3.new(1, 1, 1)
		end
		return photo
	end

	local function showEntry(entry: Entry)
		chosen = entry
		local has, dimmed = hasEntry(entry, latest)
		if stagePhoto then
			(stagePhoto :: Instance):Destroy()
			stagePhoto = nil
		end
		stageGlow.BackgroundColor3 = entry.tier.color
		panelStroke.Color = entry.tier.color
		if entry.kind == "trail" then
			local swatch = Instance.new("Frame")
			swatch.BackgroundTransparency = 1
			swatch.Size = UDim2.fromScale(1, 1)
			swatch.ZIndex = 2
			swatch.Parent = stage
			trailSwatch(swatch, if has then entry.record.color else SILHOUETTE, 2)
			stagePhoto = swatch
		else
			stagePhoto = photoOf(entry, stage, has, dimmed, 2)
		end
		numberLabel.Text = string.format("No. %03d", entry.number)
		ownedLabel.Text = if has then (if entry.kind == "fish" then "UNLOCKED" else "COLLECTED") else "LOCKED"
		ownedLabel.TextColor3 = if has then Ui.color.safe else Ui.color.muted
		nameLabel.Text = entry.name
		subLabel.Text = subtitleOf(entry)
		subLabel.TextColor3 = entry.tier.color
		wordsText.Text = table.concat(linesOf(entry, latest, deps), "\n\n")
		for _, card in cards do
			card.frame.BackgroundTransparency = if card.entry == entry then 0.05 else 0.35
		end
	end

	-- The status mark on each card, and the count, from the latest state
	local function markCards()
		local got = 0
		for _, entry in entries do
			if hasEntry(entry, latest) then
				got += 1
			end
		end
		counted.Text = `COLLECTED {got} / {#entries}`
		barFill.Size = UDim2.fromScale(if #entries > 0 then got / #entries else 0, 1)
		for _, card in cards do
			local has = hasEntry(card.entry, latest)
			card.status.Text = if has then string.format("%03d", card.entry.number) else "???"
			card.status.TextColor3 = if has then card.entry.tier.color else Ui.color.muted
			if card.photo then
				local _, dimmed = hasEntry(card.entry, latest)
				card.photo.ImageColor3 = if not has
					then SILHOUETTE
					elseif dimmed then Color3.fromRGB(190, 196, 206)
					else Color3.new(1, 1, 1)
			end
		end
	end

	local function cardFor(entry: Entry): Card
		local frame = Instance.new("TextButton")
		frame.Name = entry.key
		frame.Text = ""
		frame.AutoButtonColor = false
		frame.LayoutOrder = entry.number
		frame.BackgroundColor3 = Ui.color.track
		frame.BackgroundTransparency = 0.35
		frame.BorderSizePixel = 0
		frame.ClipsDescendants = true
		Ui.corner(frame, UDim.new(0, 10))
		Ui.stroke(frame, entry.tier.color, 0.45, 1.5)
		local visual = Instance.new("Frame")
		visual.Name = "Visual"
		visual.BackgroundTransparency = 1
		visual.Size = UDim2.new(1, 0, 1, -34)
		visual.ClipsDescendants = true
		visual.Parent = frame
		local glow = glowOf(visual, entry.tier.color, 1)
		if entry.kind == "trail" then
			local has = hasEntry(entry, latest)
			trailSwatch(visual, if has then entry.record.color else SILHOUETTE, 2)
		end
		local status = Ui.label(
			frame,
			"Status",
			"",
			Ui.FONT_HEAVY,
			11,
			Ui.color.muted,
			UDim2.fromOffset(40, 14),
			UDim2.fromOffset(7, 4)
		)
		status.ZIndex = 3
		local name = Ui.label(
			frame,
			"Name",
			entry.name,
			Ui.FONT_BOLD,
			13,
			Ui.color.text,
			UDim2.new(1, -10, 0, 16),
			UDim2.new(0, 5, 1, -33)
		)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local tier = Ui.label(
			frame,
			"Tier",
			entry.tier.name,
			Ui.FONT_SEMI,
			11,
			entry.tier.color,
			UDim2.new(1, -10, 0, 14),
			UDim2.new(0, 5, 1, -17)
		)
		tier.TextTruncate = Enum.TextTruncate.AtEnd
		frame.Parent = grid
		frame.Activated:Connect(function()
			showEntry(entry)
		end)
		return {
			entry = entry,
			frame = frame,
			visual = visual,
			status = status,
			glow = glow,
			attached = entry.kind == "trail",
			photo = nil,
		}
	end

	-- A photo for each card in view, a couple a frame, so the window opens at once
	local function attachVisible()
		if not holder.Visible then
			return
		end
		local top = grid.AbsolutePosition.Y - 30
		local bottom = grid.AbsolutePosition.Y + grid.AbsoluteSize.Y + 30
		local budget = PHOTOS_A_FRAME
		for _, card in cards do
			if card.attached then
				continue
			end
			local frame = card.frame
			if
				frame.AbsoluteSize.X > 1
				and frame.AbsolutePosition.Y + frame.AbsoluteSize.Y >= top
				and frame.AbsolutePosition.Y <= bottom
			then
				card.attached = true
				local has, dimmed = hasEntry(card.entry, latest)
				card.photo = photoOf(card.entry, card.visual, has, dimmed, 2)
				budget -= 1
				if budget <= 0 then
					return
				end
			end
		end
	end
	local stepping = RunService.RenderStepped:Connect(attachVisible)

	-- The grid for the tab and filter
	local function fill()
		for _, card in cards do
			card.frame:Destroy()
		end
		table.clear(cards)
		grid.CanvasPosition = Vector2.zero
		local first: Entry? = nil
		for _, entry in entries do
			local shown = true
			if tab == "Skins" then
				shown = if filter == EVERY_FISH then entry.species == nil else entry.species == filter
			end
			if shown then
				first = first or entry
				table.insert(cards, cardFor(entry))
			end
		end
		markCards()
		if first then
			showEntry(first)
		end
	end

	local function buildChips()
		for _, child in chips:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		local show = tab == "Skins"
		chips.Visible = show
		local gridTop = if show then 52 else 24
		grid.Position = UDim2.fromOffset(0, gridTop)
		grid.Size = UDim2.new(1, -(ENTRY_W + 8), 1, -gridTop)
		if not show then
			return
		end
		local list = Config.Species.list
		local function chip(order: number, id: string, text: string)
			local button = Ui.button(
				chips,
				id,
				text,
				UDim2.new(1 / (#list + 1), -4, 1, 0),
				UDim2.new(),
				if filter == id then "primary" else "secondary"
			)
			button.LayoutOrder = order
			button.TextSize = 11
			button.Activated:Connect(function()
				filter = id
				buildChips()
				fill()
			end)
		end
		for i, species in list do
			chip(i, species.id, string.upper(species.name))
		end
		chip(#list + 1, EVERY_FISH, "ALL FISH")
	end

	local dex = {} :: Dex

	function dex.show(name: string, s: { [string]: any })
		latest = s
		holder.Visible = true
		if name == tab then
			dex.update(s)
			return
		end
		tab = name
		entries = entriesOf(name, s)
		if filter == nil then
			filter = s.species or Config.Species.STARTER
		end
		buildChips()
		fill()
	end

	function dex.update(s: { [string]: any })
		latest = s
		markCards()
		local current = chosen
		if current then
			local has = hasEntry(current, s)
			ownedLabel.Text = if has
				then (if current.kind == "fish" then "UNLOCKED" else "COLLECTED")
				else "LOCKED"
			ownedLabel.TextColor3 = if has then Ui.color.safe else Ui.color.muted
		end
	end

	function dex.hide()
		holder.Visible = false
	end

	function dex.destroy()
		stepping:Disconnect()
		holder:Destroy()
	end

	return dex
end

return Dex
