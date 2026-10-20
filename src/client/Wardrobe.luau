--!strict
-- The Wardrobe (owner, 2026-10-18: "Wardrobe ui needs to be stepped up entirely",
-- and "if a skin comes with a trail it needs to say that in the description"): a
-- locker. On the left your fish turns on a lit stage that glows in the rarity of
-- whatever it's trying on, and under it that thing's name, tier, how it's got and
-- what it has (its effects in words, the trail it comes with, its light in the
-- dark), with WEAR / WORN / LOCKED. On the right every skin, part, variant and
-- boost trail is a card: a lit photo (CardPhoto, made only once a card scrolls into
-- view, then kept), its name and tier, the worn one marked, a locked one dimmed and
-- padlocked with how to get it.
--
--   Mouse: hover a card to try it on, click to pick it, click it again or WEAR.
--   Pad:   the D-pad walks the cards (each one tried on), A wears, LB / RB change
--          tabs, B closes (MenuController).
--   Phone: tap a card to try it on, tap it again or WEAR.
--
-- MenuController.openWardrobe opens it in a menu window and passes the Index's text
-- helpers in (`Deps`); the server's Equip request (WardrobeService) does the wearing.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Catch = require(ReplicatedStorage.Shared.Catch)
local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Format = require(ReplicatedStorage.Shared.Format)
local Fx = require(ReplicatedStorage.Shared.Fx)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local CardPhoto = require(script.Parent.CardPhoto)
local ClientState = require(script.Parent.ClientState)
local FishPreview = require(script.Parent.FishPreview)
local Input = require(script.Parent.Input)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local Tiers = Config.Tiers

local Wardrobe = {}

-- What MenuController hands in: the Index's text helpers and the menus a locked
-- thing's link opens
export type Deps = {
	shadeHow: (shade: any, s: any) -> string,
	passSource: (field: string, id: string) -> string?,
	openPass: () -> (),
	openLog: () -> (),
	openOdds: () -> (),
	openIndex: (tab: string?) -> (),
}

export type Built = { render: () -> (), cleanup: () -> () }

type Item = {
	key: string, -- kind:id
	kind: string, -- the Equip kind: "shade", "part", "variant" or "trail"
	id: string,
	name: string,
	tier: string, -- Config/Tiers
	has: boolean,
	elsewhere: boolean, -- a skin every fish can have, unlocked on another of your fish
	slot: string?, -- a part's slot
	species: string?, -- the fish a line skin or a variant is for
	universal: boolean, -- a skin every fish can have
	trailFx: boolean, -- a skin whose effects stream a trail
	fx: boolean, -- a skin with effects
	order: number, -- its place in the config list
	record: any, -- its Config entry
}

type Card = {
	item: Item,
	frame: Frame,
	button: TextButton,
	visual: Frame,
	stroke: UIStroke?,
	worn: TextLabel,
	status: TextLabel,
	attached: boolean,
}

type View = {
	scroll: ScrollingFrame,
	cards: { Card },
	byKey: { [string]: Card },
	signature: string,
	items: { Item },
}

type Wake = { frame: Frame, ribbons: { Frame }, dots: { Frame }, style: string }

local TABS = { "Skins", "Parts", "Variants", "Trails" }
local FILTERS = {
	{ id = "all", name = "ALL" },
	{ id = "line", name = "THIS FISH" },
	{ id = "every", name = "EVERY FISH" },
}

-- The skin effects (Config/Shades `fx`, Shared/SkinFx and Shared/Fx) in words. The
-- ones that stream a trail behind the fish are listed apart: a skin with one says so
-- (owner, 2026-10-18).
local TRAIL_WORDS: { [string]: string } = {
	swirls = "swirl ribbons spiralling head to tail",
	ring = "an accretion ring that leaves a spiral of light",
	aurora = "aurora ribbons off its back",
	currents = "current ribbons along both flanks",
	foam = "white-water streaks off its fins and tail",
	comet = "a long glowing comet tail",
	rainbow = "a rainbow ribbon off its tail",
}
local EFFECT_WORDS: { [string]: string } = {
	rim = "a glowing outline",
	rainbowRim = "a rainbow outline",
	halo = "a turning halo",
	crown = "a gold crown",
	rays = "light rays over its head",
	sunburst = "turning sun rays",
	arcs = "crawling lightning",
	mist = "spectral mist",
	wisps = "rising spirits",
	stardust = "twinkling stardust",
	nebula = "nebula clouds",
	vortex = "a swallowing vortex",
	glints = "bright glints",
	crystal = "crystal flashes",
	gold = "falling gold flakes",
	tropical = "reef-coloured motes",
	starfall = "falling stars",
	embers = "rising embers",
	drips = "molten drips",
	ink = "glowing ink",
	motes = "drifting lights",
	bubbles = "rising bubbles",
	frost = "sinking frost",
	flame = "flames",
	sparks = "electric sparks",
	whirls = "turning whirlpools",
	pearls = "rising pearls",
	shimmer = "holographic sparkles",
	sheen = "a polished gold shine running head to tail",
}
-- A skin whose effect reads otherwise (the same `sheen` in silver)
local SKIN_EFFECT_WORDS: { [string]: { [string]: string } } = {
	CatchSilver = { sheen = "a polished silver shine running head to tail" },
}
local AURA_WORDS: { [string]: string } = {
	glints = "drifting glints",
	embers = "drifting embers",
	frost = "drifting frost",
	sparks = "crackling sparks",
	stars = "drifting stars",
	motes = "drifting motes of light",
	bubbles = "drifting bubbles",
	ink = "curling ink",
}
local PULSE_WORDS: { [string]: string } = {
	breathe = "breathes",
	heartbeat = "thumps like a heartbeat",
	flicker = "flickers",
	wave = "rolls in waves",
	twinkle = "twinkles",
	strobe = "flashes",
	scan = "sweeps",
}

local MUTED = Ui.color.muted
local FX_COLOR = Color3.fromRGB(206, 170, 255)

type Layout = {
	window: Vector2,
	hero: number, -- the stage column's width
	stage: number, -- the stage's height
	columns: number,
	cardH: number,
	nameSize: number,
	textSize: number,
}

-- Phones get the touch design (960 × 540, Ui.screen): a smaller window, a three-wide
-- grid and bigger tap targets; PCs and consoles four cards across
local function layout(): Layout
	if Ui.isTouch() then
		return {
			window = Vector2.new(920, 520),
			hero = 320,
			stage = 146,
			columns = 3,
			cardH = 168,
			nameSize = 19,
			textSize = 12,
		}
	end
	return {
		window = Vector2.new(1080, 640),
		hero = 390,
		stage = 236,
		columns = 4,
		cardH = 186,
		nameSize = 22,
		textSize = 13,
	}
end

function Wardrobe.size(): Vector2
	return layout().window
end

function Wardrobe.subtitle(): string
	if Ui.isTouch() then
		return "Tap anything to try it on your fish · tap again or WEAR to put it on"
	elseif Input.isGamepad() then
		return "Move to try things on · A wears · LB / RB change tabs · B closes"
	end
	return "Hover anything to try it on your fish · click to pick it · click again or WEAR to put it on"
end

local function state(): { [string]: any }
	return ClientState.current or {}
end

type TierInfo = { id: string, name: string, color: Color3, order: number }

-- A locked thing's look, hidden (cards and the stage)
local SILHOUETTE = Color3.fromRGB(10, 20, 30)

-- A boost trail's wake drawn as a dark, hidden shape
local function hideWake(frame: Instance)
	for _, d in frame:GetDescendants() do
		if d:IsA("Frame") then
			d.BackgroundColor3 = Color3.fromRGB(34, 46, 58)
		elseif d:IsA("UIGradient") then
			d.Color = ColorSequence.new(Color3.fromRGB(34, 46, 58))
		end
	end
end

local function tierOf(id: string): TierInfo
	return Tiers.byId[id] or Tiers.byId.Common
end

local function fishName(id: string?): string
	local species = Config.Species.byId[id or ""]
	return if species then species.name else "fish"
end

-- Config text into RichText
local function esc(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function capital(text: string): string
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

local function nonEmpty(value: any): string?
	return if typeof(value) == "string" and value ~= "" then value else nil
end

-- Whether `item` is what this fish wears now
local function isWorn(item: Item, s: { [string]: any }): boolean
	local equipped = s.equipped or {}
	if item.kind == "shade" then
		return equipped.shade == item.id
	elseif item.kind == "part" then
		return (equipped.parts or {})[item.slot or ""] == item.id
	elseif item.kind == "variant" then
		return equipped.variant == item.id
	end
	return s.trail == item.id
end

-- A skin's effects split into the trails it streams and everything else, in words
local function effectsOf(shade: any): ({ string }, { string })
	local trails: { string } = {}
	local others: { string } = {}
	for _, kind in shade.fx or {} do
		if TRAIL_WORDS[kind] then
			table.insert(trails, TRAIL_WORDS[kind])
		else
			local own = SKIN_EFFECT_WORDS[shade.id]
			table.insert(
				others,
				(own and own[kind])
					or EFFECT_WORDS[kind]
					or string.lower((string.gsub(kind, "(%l)(%u)", "%1 %2")))
			)
		end
	end
	if shade.fx == nil then
		if shade.aura and AURA_WORDS[shade.aura] then
			table.insert(others, AURA_WORDS[shade.aura])
		elseif shade.sparkle then
			table.insert(others, AURA_WORDS.glints)
		end
	end
	if shade.cycle then
		table.insert(others, "colours cycling the rainbow")
	end
	if shade.spectral then
		table.insert(others, "a breathing ghostly glow")
	end
	if shade.glow and not shade.emissive and not shade.spectral then
		table.insert(others, "a soft glow")
	end
	return trails, others
end

local function hasTrail(shade: any): boolean
	for _, kind in shade.fx or {} do
		if TRAIL_WORDS[kind] then
			return true
		end
	end
	return false
end

-- Every item of a tab, in the order it's shown: by tier, Common first, owned first
-- within a tier. Skins are this fish's own line and the ones every fish can have.
local function itemsFor(tab: string, s: { [string]: any }, filter: string): ({ Item }, number, number)
	local items: { Item } = {}
	local current = s.species or Config.Species.STARTER
	local function push(item: Item)
		table.insert(items, item)
	end
	if tab == "Skins" then
		local owned = s.shades or {}
		local other = s.otherShades or {}
		local index = 0
		local function add(shade: any, universal: boolean)
			index += 1
			local has = owned[shade.id] == true
			push({
				key = `shade:{shade.id}`,
				kind = "shade",
				id = shade.id,
				name = shade.name,
				tier = shade.tier,
				has = has,
				elsewhere = not has and universal and other[shade.id] == true,
				slot = nil,
				species = shade.species,
				universal = universal,
				trailFx = hasTrail(shade),
				fx = shade.fx ~= nil or shade.aura ~= nil or shade.sparkle ~= nil,
				order = index,
				record = shade,
			})
		end
		local line: { any } = Config.Shades.lines[current] or {}
		for _, shade in line do
			add(shade, false)
		end
		for _, shade in Config.Shades.list do
			-- (a week's limited skin shows once it's yours)
			if shade.species == nil and (shade.week == nil or owned[shade.id]) then
				add(shade, true)
			end
		end
	elseif tab == "Parts" then
		for i, part in Config.Exotics.parts do
			push({
				key = `part:{part.id}`,
				kind = "part",
				id = part.id,
				name = part.name,
				tier = "Abyssal",
				has = (s.parts or {})[part.id] == true,
				elsewhere = false,
				slot = part.slot,
				species = nil,
				universal = true,
				trailFx = false,
				fx = false,
				order = i,
				record = part,
			})
		end
	elseif tab == "Variants" then
		for i, variant in Config.Exotics.variants do
			push({
				key = `variant:{variant.id}`,
				kind = "variant",
				id = variant.id,
				name = variant.name,
				tier = "Abyssal",
				has = (s.variants or {})[variant.id] == true,
				elsewhere = false,
				slot = nil,
				species = variant.species,
				universal = false,
				trailFx = false,
				fx = false,
				-- this fish's own variant first
				order = if variant.species == current then 0 else i,
				record = variant,
			})
		end
	else
		for i, trail in Config.Trails.list do
			push({
				key = `trail:{trail.id}`,
				kind = "trail",
				id = trail.id,
				name = trail.name,
				tier = trail.tier,
				has = (s.trails or {})[trail.id] == true,
				elsewhere = false,
				slot = nil,
				species = nil,
				universal = true,
				trailFx = false,
				fx = false,
				order = i,
				record = trail,
			})
		end
	end
	local owned = 0
	for _, item in items do
		owned += if item.has then 1 else 0
	end
	local total = #items
	if tab == "Skins" and filter ~= "all" then
		local kept: { Item } = {}
		for _, item in items do
			if item.universal == (filter == "every") then
				table.insert(kept, item)
			end
		end
		items = kept
	end
	-- Common first, down to Mythic (owner, 2026-10-20: "skins should be listed from
	-- common ascending down to mythic"); owned first within a tier
	table.sort(items, function(a, b)
		if a.kind == "variant" and (a.order == 0) ~= (b.order == 0) then
			return a.order == 0
		end
		local ta, tb = tierOf(a.tier).order, tierOf(b.tier).order
		if ta ~= tb then
			return ta < tb
		end
		if a.has ~= b.has then
			return a.has
		end
		if a.universal ~= b.universal then
			return not a.universal
		end
		return a.order < b.order
	end)
	return items, owned, total
end

-- A gem: a small square turned 45° in a tier's colour
local function gem(parent: Instance, size: number, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Gem"
	frame.Size = UDim2.fromOffset(size, size)
	frame.Rotation = 45
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	Ui.corner(frame, UDim.new(0, 2))
	Ui.stroke(frame, Color3.new(1, 1, 1), 0.45, 1)
	frame.Parent = parent
	return frame
end

-- A padlock drawn from frames (no emoji icons): a ring for the shackle, a body over
-- its lower half, a keyhole
local function padlock(parent: Instance, size: number, color: Color3, z: number): Frame
	local lock = Instance.new("Frame")
	lock.Name = "Lock"
	lock.BackgroundTransparency = 1
	lock.Size = UDim2.fromOffset(size, size)
	lock.ZIndex = z
	local shackle = Instance.new("Frame")
	shackle.Name = "Shackle"
	shackle.BackgroundTransparency = 1
	shackle.AnchorPoint = Vector2.new(0.5, 0)
	shackle.Position = UDim2.fromScale(0.5, 0)
	shackle.Size = UDim2.fromScale(0.56, 0.66)
	shackle.ZIndex = z
	Ui.corner(shackle, UDim.new(0.5, 0))
	Ui.stroke(shackle, color, 0, math.max(2, math.floor(size / 8)))
	shackle.Parent = lock
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundColor3 = color
	body.BorderSizePixel = 0
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.fromScale(0.5, 1)
	body.Size = UDim2.fromScale(0.84, 0.58)
	body.ZIndex = z
	Ui.corner(body, UDim.new(0, math.max(2, math.floor(size / 7))))
	body.Parent = lock
	local hole = Instance.new("Frame")
	hole.Name = "Keyhole"
	hole.BackgroundColor3 = Ui.color.panelFoot
	hole.BorderSizePixel = 0
	hole.AnchorPoint = Vector2.new(0.5, 0.5)
	hole.Position = UDim2.fromScale(0.5, 0.5)
	hole.Size = UDim2.fromScale(0.18, 0.4)
	hole.ZIndex = z
	Ui.corner(hole, UDim.new(0.5, 0))
	hole.Parent = body
	lock.Parent = parent
	return lock
end

local function chipColor(chip: TextLabel, text: string, color: Color3)
	chip.Text = text
	chip.TextColor3 = color
	chip.BackgroundColor3 = color
	local stroke = chip:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end
end

-- A boost trail's wake: ribbons in its colours streaming right (off the tail of a
-- fish facing left) and bits of what it's made of (bubbles, glitter, flame, ...)
local function wake(parent: Instance, trail: any, z: number, dotCount: number): Wake
	local frame = Instance.new("Frame")
	frame.Name = "Wake"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = z
	frame.Parent = parent
	local rainbow = trail.style == "rainbow"
	local colors = if rainbow then Fx.rainbow(0.7) else ColorSequence.new(trail.color2, trail.color)
	local ribbons: { Frame } = {}
	for i, spec in { { 0.5, 0.16, 0.12 }, { 0.42, 0.07, 0.35 }, { 0.6, 0.06, 0.45 } } do
		local ribbon = Instance.new("Frame")
		ribbon.Name = `Ribbon{i}`
		ribbon.AnchorPoint = Vector2.new(0, 0.5)
		ribbon.Position = UDim2.fromScale(0.36, spec[1])
		ribbon.Size = UDim2.fromScale(0.66, spec[2])
		ribbon.BackgroundColor3 = Color3.new(1, 1, 1)
		ribbon.BorderSizePixel = 0
		ribbon.ZIndex = z
		Ui.corner(ribbon, UDim.new(1, 0))
		local gradient = Instance.new("UIGradient")
		gradient.Color = colors
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, spec[3]),
			NumberSequenceKeypoint.new(0.55, math.min(1, spec[3] + 0.35)),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = ribbon
		ribbon.Parent = frame
		ribbons[i] = ribbon
	end
	local dots: { Frame } = {}
	local style = trail.style
	for i = 1, dotCount do
		local dot = Instance.new("Frame")
		dot.Name = "Bit"
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.BorderSizePixel = 0
		dot.ZIndex = z
		local t = (i - 1) / math.max(dotCount - 1, 1)
		dot.BackgroundColor3 = if rainbow
			then Color3.fromHSV(t * 0.85, 0.6, 1)
			else trail.color2:Lerp(trail.color, t)
		local size = if style == "ink" then 0.12 elseif style == "bubbles" then 0.07 else 0.045
		dot.Size = UDim2.fromScale(size, size)
		dot.SizeConstraint = Enum.SizeConstraint.RelativeYY
		if style == "glitter" or style == "stardust" or style == "frost" then
			dot.Rotation = 45
			Ui.corner(dot, UDim.new(0, 1))
		else
			Ui.corner(dot, UDim.new(1, 0))
		end
		if style == "bubbles" then
			dot.BackgroundTransparency = 0.85
			Ui.stroke(dot, trail.color, 0.15, 1.5)
		else
			dot.BackgroundTransparency = if style == "ink" then 0.55 else 0.1
		end
		-- spread along the wake for a still (animate moves them)
		dot.Position = UDim2.fromScale(0.42 + t * 0.55, 0.5 + math.sin(i * 2.3) * 0.14)
		dot.Parent = frame
		dots[i] = dot
	end
	return { frame = frame, ribbons = ribbons, dots = dots, style = style }
end

-- Moves a wake's bits along it and ripples its ribbons
local function animateWake(made: Wake, clock: number)
	for i, ribbon in made.ribbons do
		local base = ({ 0.5, 0.42, 0.6 })[i]
		ribbon.Position = UDim2.fromScale(0.36, base + math.sin(clock * 2.2 + i * 1.7) * 0.02)
	end
	local count = #made.dots
	local fall = if made.style == "frost" or made.style == "glitter" then 0.12 else -0.08
	for i, dot in made.dots do
		local t = (clock * 0.32 + i / count) % 1
		dot.Position = UDim2.fromScale(0.42 + t * 0.6, 0.5 + math.sin(i * 2.3) * 0.12 + t * fall)
		local fade = math.clamp(t * 1.2, 0, 1)
		if made.style ~= "bubbles" then
			dot.BackgroundTransparency = (if made.style == "ink" then 0.55 else 0.1) + fade * 0.85
		end
	end
end

function Wardrobe.build(window: Ui.Window, deps: Deps): Built
	local L = layout()
	local content = window.content
	local W = L.window.X - 36
	local H = L.window.Y - 96
	local GAP = 14
	local gridX = L.hero + GAP
	local gridW = W - gridX
	local GRID_TOP = 82
	local CELL_GAP = 10
	local cellW = math.floor((gridW - 16 - (L.columns - 1) * CELL_GAP) / L.columns)
	local visualH = L.cardH - 72
	local pad = Input.isGamepad()

	local connections: { RBXScriptConnection } = {}
	local tab = "Skins"
	local filter = "all"
	local views: { [string]: View } = {}
	local selectedKey: { [string]: string } = {}
	local hoverKey: string? = nil
	local hoverEndAt: number? = nil
	local shownKey = ""
	local pendingShow: { dress: Cosmetics.Dress, species: string?, fish: string, at: number }? = nil
	local shownFish: string? = nil -- the fish on the stage, re-dressed in place
	local firstShow = true
	local detailKey = ""
	local glowColor = Ui.color.accent
	local stageCycle = false
	local stageWake: Wake? = nil
	local stageWakeId = ""

	---------------------------------------------------------------- the stage
	local hero = Instance.new("Frame")
	hero.Name = "Hero"
	hero.BackgroundTransparency = 1
	hero.Size = UDim2.fromOffset(L.hero, H)
	hero.Parent = content

	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.Size = UDim2.fromOffset(L.hero, L.stage)
	stage.BackgroundColor3 = Color3.fromRGB(3, 10, 18)
	stage.BackgroundTransparency = 0.05
	stage.BorderSizePixel = 0
	stage.ClipsDescendants = true
	Ui.corner(stage)
	local stageStroke = Ui.stroke(stage, Ui.color.accent, 0.55, 1.5)
	stage.Parent = hero
	-- A wash of the tier's colour rising from the floor
	local wash = Instance.new("Frame")
	wash.Name = "Wash"
	wash.Size = UDim2.fromScale(1, 1)
	wash.BackgroundColor3 = glowColor
	wash.BorderSizePixel = 0
	Ui.corner(wash)
	local washGradient = Instance.new("UIGradient")
	washGradient.Rotation = 90
	washGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.6, 0.9),
		NumberSequenceKeypoint.new(1, 0.62),
	})
	washGradient.Parent = wash
	wash.Parent = stage
	-- A soft oval glow behind the fish: rings of faint colour stacked into a falloff
	local rings: { Frame } = {}
	for i = 1, 10 do
		local ring = Instance.new("Frame")
		ring.Name = "Glow"
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		local d = 0.2 + (i - 1) * 0.11
		ring.SizeConstraint = Enum.SizeConstraint.RelativeXX
		ring.Size = UDim2.fromScale(d, d * 0.6)
		ring.BackgroundColor3 = glowColor
		ring.BackgroundTransparency = 0.94
		ring.BorderSizePixel = 0
		Ui.corner(ring, UDim.new(0.5, 0))
		ring.Parent = stage
		rings[i] = ring
	end
	-- Two spotlights from above
	local beams: { UIGradient } = {}
	for i, x in { 0.3, 0.7 } do
		local beam = Instance.new("Frame")
		beam.Name = "Beam"
		beam.AnchorPoint = Vector2.new(0.5, 0.5)
		beam.Position = UDim2.fromScale(x, 0.32)
		beam.Size = UDim2.fromScale(0.16, 1.1)
		beam.Rotation = if i == 1 then -20 else 20
		beam.BackgroundColor3 = Color3.new(1, 1, 1)
		beam.BorderSizePixel = 0
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(glowColor:Lerp(Color3.new(1, 1, 1), 0.55))
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.78),
			NumberSequenceKeypoint.new(0.6, 0.95),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = beam
		beam.Parent = stage
		beams[i] = gradient
	end
	-- A lit disc of floor under the fish
	local floor = Instance.new("Frame")
	floor.Name = "Floor"
	floor.AnchorPoint = Vector2.new(0.5, 0.5)
	floor.Position = UDim2.fromScale(0.5, 0.86)
	floor.Size = UDim2.fromScale(0.66, 0.11)
	floor.BackgroundColor3 = glowColor
	floor.BackgroundTransparency = 0.8
	floor.BorderSizePixel = 0
	Ui.corner(floor, UDim.new(0.5, 0))
	local floorRim = Ui.stroke(floor, glowColor, 0.35, 1.5)
	floor.Parent = stage
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.fromScale(0.5, 0.5)
	shadow.Size = UDim2.fromScale(0.6, 0.45)
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.55
	shadow.BorderSizePixel = 0
	Ui.corner(shadow, UDim.new(0.5, 0))
	shadow.Parent = floor

	local preview = FishPreview.new(stage, UDim2.fromScale(1, 1), UDim2.new())
	preview.frame.ZIndex = 3

	local stateChip = Ui.chip(stage, "State", "", Ui.color.accent, 22)
	stateChip.Position = UDim2.fromOffset(10, 10)
	stateChip.ZIndex = 5
	local fishLabel = Ui.label(
		stage,
		"Fish",
		"",
		Ui.FONT_BOLD,
		11,
		MUTED,
		UDim2.new(1, -20, 0, 14),
		UDim2.new(0, 12, 1, -22)
	)
	fishLabel.ZIndex = 5
	-- Effects and trails don't draw in a ViewportFrame: the stage says where they show
	local seaNote = Ui.label(
		stage,
		"SeaNote",
		"EFFECTS SHOW IN THE SEA",
		Ui.FONT_BOLD,
		10,
		MUTED,
		UDim2.new(0.6, 0, 0, 14),
		UDim2.new(0.4, -12, 1, -22)
	)
	seaNote.TextXAlignment = Enum.TextXAlignment.Right
	seaNote.ZIndex = 5
	seaNote.Visible = false

	---------------------------------------------------------------- the details
	local infoTop = L.stage + 10
	local buttonH = if Ui.isTouch() then 44 else 42
	local info = Instance.new("ScrollingFrame")
	info.Name = "Details"
	info.BackgroundTransparency = 1
	info.BorderSizePixel = 0
	info.Position = UDim2.fromOffset(0, infoTop)
	info.Size = UDim2.fromOffset(L.hero, H - infoTop - buttonH - 10)
	info.ScrollBarThickness = 3
	info.ScrollBarImageColor3 = Ui.color.stroke
	info.AutomaticCanvasSize = Enum.AutomaticSize.Y
	info.CanvasSize = UDim2.new()
	info.Selectable = false
	info.ScrollingDirection = Enum.ScrollingDirection.Y
	info.Parent = hero
	local infoList = Instance.new("UIListLayout")
	infoList.Padding = UDim.new(0, 5)
	infoList.SortOrder = Enum.SortOrder.LayoutOrder
	infoList.Parent = info
	-- A fade and an arrow at the foot while there's more to read below
	local more = Instance.new("Frame")
	more.Name = "More"
	more.BackgroundColor3 = Ui.color.panelFoot
	more.BorderSizePixel = 0
	more.AnchorPoint = Vector2.new(0, 1)
	more.Position = UDim2.fromOffset(0, infoTop + info.Size.Y.Offset)
	more.Size = UDim2.fromOffset(L.hero, 22)
	more.ZIndex = 4
	more.Visible = false
	local moreFade = Instance.new("UIGradient")
	moreFade.Rotation = 90
	moreFade.Transparency = NumberSequence.new(1, 0.15)
	moreFade.Parent = more
	more.Parent = hero
	local moreArrow =
		Ui.label(more, "Arrow", "▼", Ui.FONT_BOLD, 11, Ui.color.accent, UDim2.new(1, -4, 1, 0))
	moreArrow.TextXAlignment = Enum.TextXAlignment.Right
	moreArrow.ZIndex = 5

	local nameLabel = Ui.label(
		info,
		"Name",
		"",
		Ui.FONT_HEAVY,
		L.nameSize,
		Ui.color.text,
		UDim2.new(1, -8, 0, L.nameSize + 4)
	)
	nameLabel.LayoutOrder = 1
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	local markHolder = Instance.new("Frame")
	markHolder.Name = "Mark"
	markHolder.BackgroundTransparency = 1
	markHolder.Size = UDim2.new(1, 0, 0, 3)
	markHolder.LayoutOrder = 2
	markHolder.Parent = info
	local mark = Instance.new("Frame")
	mark.Name = "AccentMark"
	mark.BorderSizePixel = 0
	mark.Size = UDim2.fromOffset(48, 3)
	mark.BackgroundColor3 = glowColor
	Ui.corner(mark, UDim.new(1, 0))
	mark.Parent = markHolder

	local tierRow = Instance.new("Frame")
	tierRow.Name = "TierRow"
	tierRow.BackgroundTransparency = 1
	tierRow.Size = UDim2.new(1, -8, 0, 20)
	tierRow.LayoutOrder = 3
	tierRow.Parent = info
	local tierLayout = Instance.new("UIListLayout")
	tierLayout.FillDirection = Enum.FillDirection.Horizontal
	tierLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tierLayout.Padding = UDim.new(0, 8)
	tierLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tierLayout.Parent = tierRow
	local gemHolder = Instance.new("Frame")
	gemHolder.BackgroundTransparency = 1
	gemHolder.Size = UDim2.fromOffset(14, 14)
	gemHolder.LayoutOrder = 1
	gemHolder.Parent = tierRow
	local tierGem = gem(gemHolder, 9, glowColor)
	tierGem.AnchorPoint = Vector2.new(0.5, 0.5)
	tierGem.Position = UDim2.fromScale(0.5, 0.5)
	local tierLabel = Ui.label(tierRow, "Tier", "", Ui.FONT_HEAVY, 14, glowColor, UDim2.fromOffset(0, 18))
	tierLabel.AutomaticSize = Enum.AutomaticSize.X
	tierLabel.LayoutOrder = 2
	local oddsLabel = Ui.label(tierRow, "Odds", "", Ui.FONT_SEMI, 13, MUTED, UDim2.fromOffset(0, 18))
	oddsLabel.AutomaticSize = Enum.AutomaticSize.X
	oddsLabel.LayoutOrder = 3

	local chipRow = Instance.new("Frame")
	chipRow.Name = "Chips"
	chipRow.BackgroundTransparency = 1
	chipRow.Size = UDim2.new(1, -8, 0, 0)
	chipRow.AutomaticSize = Enum.AutomaticSize.Y
	chipRow.LayoutOrder = 4
	chipRow.Parent = info
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Wraps = true
	chipLayout.Padding = UDim.new(0, 6)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chipRow

	-- The wear buttons along the column's foot
	local primary = Ui.button(
		hero,
		"Wear",
		"WEAR",
		UDim2.fromOffset(L.hero, buttonH),
		UDim2.fromOffset(0, H - buttonH),
		"primary"
	)
	primary.TextSize = 17
	local primaryLock = padlock(primary, 16, Color3.fromRGB(110, 136, 148), 3)
	primaryLock.AnchorPoint = Vector2.new(0, 0.5)
	primaryLock.Position = UDim2.new(0, 14, 0.5, 0)
	local secondary = Ui.button(
		hero,
		"Second",
		"TAKE OFF",
		UDim2.fromOffset(L.hero / 2 - 4, buttonH),
		UDim2.fromOffset(L.hero / 2 + 4, H - buttonH),
		"secondary"
	)
	secondary.TextSize = 15

	---------------------------------------------------------------- tabs
	local tabButtons: { [string]: TextButton } = {}
	local capW = if pad then 44 else 0
	local tabsW = gridW - capW * 2
	local tabW = (tabsW - 3 * 8) / 4
	for i, name in TABS do
		local button = Ui.button(
			content,
			name,
			string.upper(name),
			UDim2.fromOffset(tabW, 40),
			UDim2.fromOffset(gridX + capW + (i - 1) * (tabW + 8), 0),
			"secondary"
		)
		button.RichText = true
		button.TextSize = 15
		tabButtons[name] = button
	end
	if pad then
		local left = Ui.keycap(content, "TabLeft", "LB", 26)
		left.Position = UDim2.fromOffset(gridX + 2, 7)
		local right = Ui.keycap(content, "TabRight", "RB", 26)
		right.AnchorPoint = Vector2.new(1, 0)
		right.Position = UDim2.fromOffset(W - 2, 7)
	end

	-- The line under the tabs: what the tab holds, and on SKINS the filter
	local note = Ui.label(
		content,
		"Note",
		"",
		Ui.FONT_BOLD,
		12,
		MUTED,
		UDim2.fromOffset(gridW, 26),
		UDim2.fromOffset(gridX + 2, 48)
	)
	note.TextTruncate = Enum.TextTruncate.AtEnd
	if Ui.isTouch() then
		note.TextSize = 11
	end
	local filterButtons: { [string]: TextButton } = {}
	local filterX = W
	for i = #FILTERS, 1, -1 do
		local entry = FILTERS[i]
		local width = 26 + #entry.name * 7
		filterX -= width
		local button = Ui.button(
			content,
			`Filter{entry.id}`,
			entry.name,
			UDim2.fromOffset(width, 26),
			UDim2.fromOffset(filterX, 48),
			"secondary"
		)
		button.TextSize = 12
		filterButtons[entry.id] = button
		filterX -= 6
	end
	local filterLeft = filterX

	---------------------------------------------------------------- helpers
	-- (set below: `render` redraws everything from the state, `refreshFocus` only
	-- the stage and the details, for a hover or a pick)
	local render: () -> () = function() end
	local refreshFocus: () -> () = function() end

	local function currentView(): View?
		return views[tab]
	end

	local function itemByKey(key: string?): Item?
		local view = currentView()
		if key == nil or view == nil then
			return nil
		end
		local card = view.byKey[key]
		return if card then card.item else nil
	end

	-- What the stage and details show: the card under the mouse, else the picked one
	local function focusItem(): Item?
		return itemByKey(hoverKey) or itemByKey(selectedKey[tab])
	end

	local function equip(item: Item)
		if not item.has then
			return
		end
		ClientState.request("Equip", item.kind, item.id, item.slot)
		Sfx.play("Bubble", { volume = 0.5, pitch = 1.15 })
	end

	local function takeOff(item: Item)
		ClientState.request("Equip", item.kind, "", item.slot)
		Sfx.play("UiOpen", { volume = 0.35, pitch = 0.85 })
	end

	-- Where a locked thing is got, as a menu to open
	local function linkFor(item: Item): (string?, (() -> ())?)
		local r = item.record
		if item.kind == "trail" or (item.kind == "shade" and r.pass) then
			return "TIDE PASS", deps.openPass
		elseif item.kind == "shade" and (r.catch or r.week) then
			return "OPEN LOG", deps.openLog
		elseif item.kind == "shade" and (r.boss or r.treasure) then
			return "INDEX", function()
				deps.openIndex("Skins")
			end
		end
		return "ROLL ODDS", deps.openOdds
	end

	-- A locked card's short "how" (the details say it in full)
	local function shortHow(item: Item, s: { [string]: any }): string
		local r = item.record
		local function pass(field: string): string
			local where = deps.passSource(field, item.id)
			if where == nil then
				return "A LATER SEASON"
			end
			local number = string.match(where, "tier (%d+)") or "?"
			return `{if string.find(where, "Deep") then "DEEP PASS" else "TIDE PASS"} · TIER {number}`
		end
		if item.elsewhere then
			return "ON ANOTHER FISH"
		elseif item.kind == "trail" then
			return pass("trail")
		elseif item.kind == "shade" then
			if r.pass then
				return pass("skin")
			elseif r.catch then
				local rarity = Config.Catch.byId[r.catch]
				local done = Catch.goal(s.catchLog, rarity.id)
				return `CATCH GOAL {math.min(done, rarity.unlock.species)}/{rarity.unlock.species} SPECIES`
			elseif r.week then
				return "CATCH OF THE WEEK"
			elseif r.boss then
				return `{if r.boss == "GiantSquid" then "GIANT SQUID" else string.upper(r.boss)} DROP`
			elseif r.treasure then
				return `TREASURE · ROLL {RollOdds.oneIn(1 / r.chance)}`
			elseif r.price then
				return `SHADE DYER · {Ui.number(r.price)}`
			end
		end
		local chance = r.chance or 0
		return if chance > 0 then `ROLL · {RollOdds.oneIn(1 / chance)}` else "SEE THE INDEX"
	end

	-- The details' lines for an item, as RichText
	local function detailLines(
		item: Item,
		s: { [string]: any }
	): { { text: string, color: Color3?, small: boolean? } }
		local lines: { { text: string, color: Color3?, small: boolean? } } = {}
		local function add(text: string, color: Color3?, small: boolean?)
			table.insert(lines, { text = text, color = color, small = small })
		end
		local r = item.record
		local current = s.species or Config.Species.STARTER
		add(esc(r.blurb or ""), MUTED)
		if item.kind == "shade" then
			-- (an owned one says so on the stage and its button)
			if not item.has then
				local how = esc(deps.shadeHow(r, s))
				add(
					if item.elsewhere
						then `<b>On another of your fish:</b> unlock it again for this one. {how}`
						else `<b>How to get:</b> {how}`
				)
			end
			local trails, others = effectsOf(r)
			if #others > 0 then
				add(`<b>Effects:</b> {esc(capital(table.concat(others, ", ")))}.`, FX_COLOR)
			end
			if #trails > 0 then
				add(
					`<b>Comes with a trail:</b> {esc(capital(table.concat(trails, " and ")))}, streaming behind you as you swim, on top of any boost trail.`,
					Ui.color.haul
				)
			end
			if r.emissive or r.spectral then
				local source = Config.Tuning.light.sources[r.tier]
				if source then
					local pulse = if r.pulse then PULSE_WORDS[r.pulse] else nil
					add(
						`<b>Lights the dark:</b> about {Format.distance(source.range)} round you in the deep{if pulse
							then `, and its glow {pulse}`
							else ""}.`,
						Color3.fromRGB(150, 236, 255)
					)
				end
			end
		elseif item.kind == "part" then
			if r.id == "AnglerLure" then
				add("Lights up dark water like an Anglerfish's lure.", Color3.fromRGB(150, 236, 255))
			end
			add(`Worn in the <b>{esc(r.slot)}</b> slot, one part a slot, on any fish. Looks only: no stats.`)
			if not item.has then
				add(
					`<b>How to get:</b> roll it as any fish · about {RollOdds.oneIn(1 / r.chance)}. A duplicate turns into {Ui.number(
						r.refund
					)} coral.`
				)
			end
		elseif item.kind == "variant" then
			local fish = esc(fishName(r.species))
			add(
				if r.species == current
					then `Reshapes your {fish}. One variant is worn at a time.`
					else `<b>{fish} only:</b> it shows when you swim as the {fish}. One variant is worn at a time.`
			)
			if not item.has then
				add(
					`<b>How to get:</b> roll it as the {fish} · about {RollOdds.oneIn(1 / r.chance)}. A duplicate turns into {Ui.number(
						r.refund
					)} coral.`
				)
			end
		else
			add("Streams off your tail when you swim fast, and full on a dash. One at a time, on every fish.")
			if not item.has then
				add(
					`<b>How to get:</b> {esc(deps.passSource("trail", item.id) or "A later Tide Pass season")}. Boost trails are earned, never sold.`
				)
			end
		end
		return lines
	end

	---------------------------------------------------------------- the stage's look
	local function setGlow(color: Color3, cycle: boolean)
		local was = stageCycle
		stageCycle = cycle
		if color == glowColor and not was then
			return
		end
		glowColor = color
		Ui.tween(wash, 0.35, { BackgroundColor3 = color })
		for _, ring in rings do
			Ui.tween(ring, 0.35, { BackgroundColor3 = color })
		end
		Ui.tween(floor, 0.35, { BackgroundColor3 = color })
		Ui.tween(floorRim, 0.35, { Color = color })
		Ui.tween(stageStroke, 0.35, { Color = color })
		Ui.tween(mark, 0.35, { BackgroundColor3 = color })
		for _, gradient in beams do
			gradient.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.55))
		end
	end

	-- Puts the fish on the stage in what it wears, trying on `item`
	local function showPreview(item: Item?, s: { [string]: any })
		local equipped = s.equipped or {}
		local current = s.species or Config.Species.STARTER
		local dress: Cosmetics.Dress = {
			shade = nonEmpty(equipped.shade),
			parts = table.clone(equipped.parts or {}),
			variant = nonEmpty(equipped.variant),
		}
		local species: string? = nil
		-- A locked thing isn't put on: the fish stands as a silhouette instead
		local hidden = item ~= nil and not item.has and not item.elsewhere
		preview.frame.ImageColor3 = if hidden then SILHOUETTE else Color3.new(1, 1, 1)
		if item and not hidden then
			if item.kind == "shade" then
				dress.shade = item.id
			elseif item.kind == "part" and item.slot then
				dress.parts[item.slot] = item.id
			elseif item.kind == "variant" then
				dress.variant = item.id
				if item.species ~= current then
					-- Another fish's variant: shown on that fish
					species = item.species
				end
			end
		end
		local body = species or current
		if dress.shade and not Config.Shades.fits(dress.shade, body) then
			dress.shade = nil
		end
		-- A variant shows only on its own fish
		local variant = if dress.variant then Config.Exotics.variantsById[dress.variant] else nil
		if variant == nil or variant.species ~= body then
			dress.variant = nil
		end
		local key =
			`{current}|{species or ""}|{dress.shade or ""}|{Cosmetics.partsText(dress.parts)}|{dress.variant or ""}`
		if key ~= shownKey then
			shownKey = key
			-- (a new fish waits a moment, so sweeping the mouse or the D-pad over the
			-- grid doesn't build one for every card it crosses)
			pendingShow = {
				dress = dress,
				species = species,
				fish = species or current,
				at = os.clock() + (if firstShow then 0 else 0.07),
			}
			firstShow = false
		end
		fishLabel.Text =
			string.upper(if species then `{fishName(species)} · another of your fish` else fishName(current))
		-- A boost trail streams behind the fish
		local trailId = if item and item.kind == "trail" then item.id else ""
		if trailId ~= stageWakeId then
			stageWakeId = trailId
			if stageWake then
				stageWake.frame:Destroy()
				stageWake = nil
			end
			if item and item.kind == "trail" then
				stageWake = wake(stage, item.record, 2, 14)
				if hidden and stageWake then
					hideWake(stageWake.frame)
				end
			end
		end
	end

	-- Fills the stage and the details for the focused item
	local function showDetails(s: { [string]: any })
		local item = focusItem()
		showPreview(item, s)
		if item == nil then
			detailKey = ""
			nameLabel.Text = "Nothing here yet"
			tierLabel.Text = ""
			oddsLabel.Text = ""
			for _, child in chipRow:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			for _, child in info:GetChildren() do
				if child:IsA("TextLabel") and child.Name == "Line" then
					child:Destroy()
				end
			end
			stateChip.Visible = false
			seaNote.Visible = false
			primary.Visible = false
			secondary.Visible = false
			setGlow(Ui.color.accent, false)
			return
		end
		local worn = isWorn(item, s)
		local tier = tierOf(item.tier)
		local r = item.record
		setGlow(
			tier.color,
			item.kind == "shade" and r.cycle == true or item.kind == "trail" and r.style == "rainbow"
		)
		seaNote.Visible = item.fx or item.kind == "trail"
		seaNote.Text = if item.kind == "trail"
			then "STREAMS OFF YOU IN THE SEA"
			else "EFFECTS SHOW IN THE SEA"
		stateChip.Visible = true
		if worn then
			chipColor(stateChip, "✓ WORN", Ui.color.safe)
		elseif not item.has then
			chipColor(
				stateChip,
				if item.elsewhere then "ON ANOTHER FISH" else "LOCKED · UNLOCK TO SEE IT",
				MUTED
			)
		elseif item.kind == "trail" then
			chipColor(stateChip, "BOOST TRAIL", Ui.color.accent)
		else
			chipColor(stateChip, "TRYING ON", Ui.color.accent)
		end
		-- (everything below is rebuilt only when the item or its state changes)
		local key = `{item.key}|{item.has}|{item.elsewhere}|{worn}|{s.species}`
		if key ~= detailKey then
			detailKey = key
			info.CanvasPosition = Vector2.zero
			nameLabel.Text = item.name
			tierLabel.Text = string.upper(tier.name)
			tierLabel.TextColor3 = tier.color
			tierGem.BackgroundColor3 = tier.color
			local rolled = if item.kind == "shade"
				then Config.Shades.rollable(r)
				else item.kind == "part" or item.kind == "variant"
			oddsLabel.Text = if rolled and (r.chance or 0) > 0
				then `· {RollOdds.oneIn(1 / r.chance)} a roll`
				else ""
			for _, child in chipRow:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			local chips: { { text: string, color: Color3 } } = {}
			if item.kind == "shade" then
				table.insert(
					chips,
					if item.universal
						then { text = "EVERY FISH", color = Ui.color.accent }
						else {
							text = `{string.upper(fishName(item.species))} ONLY`,
							color = Ui.color.accent,
						}
				)
				if item.trailFx then
					table.insert(chips, { text = "+ TRAIL", color = Ui.color.haul })
				end
				if item.fx and not item.trailFx then
					table.insert(chips, { text = "EFFECTS", color = FX_COLOR })
				end
				if r.emissive or r.spectral then
					table.insert(chips, { text = "GLOWS", color = Color3.fromRGB(150, 236, 255) })
				end
			elseif item.kind == "part" then
				table.insert(
					chips,
					{ text = `{string.upper(item.slot or "")} SLOT`, color = Ui.color.accent }
				)
				table.insert(chips, { text = "EVERY FISH", color = Ui.color.accent })
			elseif item.kind == "variant" then
				table.insert(
					chips,
					{ text = `{string.upper(fishName(item.species))} ONLY`, color = Ui.color.accent }
				)
			else
				table.insert(chips, { text = "EVERY FISH", color = Ui.color.accent })
			end
			for i, chip in chips do
				local made = Ui.chip(chipRow, `Chip{i}`, chip.text, chip.color, 20)
				made.LayoutOrder = i
			end
			for _, child in info:GetChildren() do
				if child:IsA("TextLabel") and child.Name == "Line" then
					child:Destroy()
				end
			end
			for i, line in detailLines(item, s) do
				if line.text == "" then
					continue
				end
				local label = Ui.label(
					info,
					"Line",
					line.text,
					Ui.FONT,
					if line.small then L.textSize - 1 else L.textSize,
					line.color or Ui.color.text,
					UDim2.new(1, -10, 0, 0)
				)
				label.RichText = true
				label.TextWrapped = true
				label.AutomaticSize = Enum.AutomaticSize.Y
				label.TextYAlignment = Enum.TextYAlignment.Top
				label.LayoutOrder = 10 + i
			end
		end
		-- The buttons
		primary.Visible = true
		primaryLock.Visible = false
		local link, _ = linkFor(item)
		if worn then
			primary.Text = "✓ WORN"
			Ui.setButtonStyle(primary, "disabled")
			primary.TextColor3 = Ui.color.safe
			secondary.Text = "TAKE OFF"
			Ui.setButtonStyle(secondary, "secondary")
		elseif item.has then
			primary.Text = "WEAR"
			Ui.setButtonStyle(primary, "primary")
		else
			primary.Text = "LOCKED"
			Ui.setButtonStyle(primary, "disabled")
			primaryLock.Visible = true
			secondary.Text = link or "INDEX"
			Ui.setButtonStyle(secondary, "secondary")
		end
		local split = worn or not item.has
		secondary.Visible = split
		primary.Size = UDim2.fromOffset(if split then L.hero / 2 - 4 else L.hero, buttonH)
	end

	---------------------------------------------------------------- cards
	local function newView(): View
		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "Grid"
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.Position = UDim2.fromOffset(gridX, GRID_TOP)
		scroll.Size = UDim2.fromOffset(gridW, H - GRID_TOP)
		scroll.ScrollBarThickness = 4
		scroll.ScrollBarImageColor3 = Ui.color.stroke
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new()
		scroll.ScrollingDirection = Enum.ScrollingDirection.Y
		scroll.Selectable = false
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromOffset(cellW, L.cardH)
		grid.CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = scroll
		local padding = Instance.new("UIPadding")
		-- (room for a lifted card's edge)
		padding.PaddingTop = UDim.new(0, 6)
		padding.PaddingLeft = UDim.new(0, 5)
		padding.PaddingBottom = UDim.new(0, 10)
		padding.Parent = scroll
		scroll.Parent = content
		return { scroll = scroll, cards = {}, byKey = {}, signature = "", items = {} }
	end

	local function pick(item: Item)
		if selectedKey[tab] ~= item.key then
			selectedKey[tab] = item.key
			Sfx.play("Tick", { volume = 0.25, pitch = 1.1 })
		end
		hoverKey = nil
		hoverEndAt = nil
		refreshFocus()
	end

	local function buildCard(view: View, item: Item, order: number, s: { [string]: any }): Card
		local tier = tierOf(item.tier)
		local frame = Ui.panel(view.scroll, item.key, UDim2.fromOffset(cellW, L.cardH), UDim2.new())
		frame.LayoutOrder = order
		local stroke = frame:FindFirstChildOfClass("UIStroke")
		local visual = Instance.new("Frame")
		visual.Name = "Visual"
		visual.BackgroundColor3 = Ui.color.panelFoot
		visual.BackgroundTransparency = 0.2
		visual.BorderSizePixel = 0
		visual.ClipsDescendants = true
		visual.Position = UDim2.fromOffset(5, 5)
		visual.Size = UDim2.new(1, -10, 0, visualH)
		Ui.corner(visual, UDim.new(0, 8))
		visual.Parent = frame
		-- The tier's colour glowing up from the bottom of the photo
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.Size = UDim2.fromScale(1, 1)
		glow.BackgroundColor3 = tier.color
		glow.BorderSizePixel = 0
		Ui.corner(glow, UDim.new(0, 8))
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.9),
			NumberSequenceKeypoint.new(1, if item.has then 0.5 else 0.75),
		})
		gradient.Parent = glow
		glow.Parent = visual
		local spot = Instance.new("Frame")
		spot.Name = "Spot"
		spot.AnchorPoint = Vector2.new(0.5, 0.5)
		spot.Position = UDim2.fromScale(0.5, 0.55)
		spot.SizeConstraint = Enum.SizeConstraint.RelativeXX
		spot.Size = UDim2.fromScale(0.85, 0.5)
		spot.BackgroundColor3 = tier.color
		spot.BackgroundTransparency = if item.has then 0.86 else 0.93
		spot.BorderSizePixel = 0
		Ui.corner(spot, UDim.new(0.5, 0))
		spot.Parent = visual
		-- The rarity strip under the photo
		local strip = Instance.new("Frame")
		strip.Name = "Strip"
		strip.AnchorPoint = Vector2.new(0, 1)
		strip.Position = UDim2.fromScale(0, 1)
		strip.Size = UDim2.new(1, 0, 0, 3)
		strip.BackgroundColor3 = tier.color
		strip.BackgroundTransparency = if item.has then 0 else 0.4
		strip.BorderSizePixel = 0
		strip.ZIndex = 4
		strip.Parent = visual
		if item.kind == "trail" then
			local made = wake(visual, item.record, 2, 8)
			made.frame.Position = UDim2.fromScale(-0.3, 0)
			made.frame.Size = UDim2.fromScale(1.25, 1)
			if not item.has then
				hideWake(made.frame)
			end
		end
		if not item.has then
			local dim = Instance.new("Frame")
			dim.Name = "Dim"
			dim.Size = UDim2.fromScale(1, 1)
			dim.BackgroundColor3 = Ui.color.panelFoot
			dim.BackgroundTransparency = if item.elsewhere then 0.6 else 0.45
			dim.BorderSizePixel = 0
			dim.ZIndex = 3
			dim.Parent = visual
			local lock = padlock(visual, 18, if item.elsewhere then Ui.color.haul else MUTED, 5)
			lock.AnchorPoint = Vector2.new(1, 0)
			lock.Position = UDim2.new(1, -7, 0, 7)
		end
		-- Tags along the photo's foot: a skin for every fish, one with a trail or effects
		local tags = Instance.new("Frame")
		tags.Name = "Tags"
		tags.BackgroundTransparency = 1
		tags.Position = UDim2.new(0, 6, 1, -22)
		tags.Size = UDim2.new(1, -12, 0, 16)
		tags.ZIndex = 5
		tags.Parent = visual
		local tagLayout = Instance.new("UIListLayout")
		tagLayout.FillDirection = Enum.FillDirection.Horizontal
		tagLayout.Padding = UDim.new(0, 4)
		tagLayout.SortOrder = Enum.SortOrder.LayoutOrder
		tagLayout.Parent = tags
		local function tag(text: string, color: Color3, at: number)
			local chip = Ui.chip(tags, text, text, color, 16)
			chip.LayoutOrder = at
			chip.ZIndex = 5
			chip.BackgroundTransparency = 0.45
			chip.BackgroundColor3 = Ui.color.panelFoot
		end
		if item.kind == "shade" then
			if item.trailFx then
				tag("TRAIL", Ui.color.haul, 1)
			elseif item.fx then
				tag("FX", FX_COLOR, 1)
			end
			if item.universal and tab == "Skins" and filter == "all" then
				tag("ALL FISH", Ui.color.accent, 2)
			end
		elseif item.kind == "variant" and item.species ~= (s.species or Config.Species.STARTER) then
			tag(string.upper(fishName(item.species)), Ui.color.accent, 1)
		elseif item.kind == "part" then
			tag(string.upper(item.slot or ""), Ui.color.accent, 1)
		end
		local worn = Ui.chip(visual, "Worn", "✓ WORN", Ui.color.safe, 18)
		worn.Position = UDim2.fromOffset(6, 6)
		worn.ZIndex = 6
		worn.BackgroundTransparency = 0.25
		worn.BackgroundColor3 = Color3.fromRGB(8, 40, 28)
		worn.Visible = false
		-- The words
		local name = Ui.label(
			frame,
			"Name",
			item.name,
			Ui.FONT_BOLD,
			14,
			if item.has then Ui.color.text else MUTED,
			UDim2.new(1, -16, 0, 18),
			UDim2.fromOffset(9, visualH + 11)
		)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local tierGemCard = gem(frame, 7, tier.color)
		tierGemCard.Position = UDim2.fromOffset(11, visualH + 36)
		local tierText = Ui.label(
			frame,
			"Tier",
			string.upper(tier.name),
			Ui.FONT_HEAVY,
			11,
			tier.color,
			UDim2.new(1, -30, 0, 14),
			UDim2.fromOffset(24, visualH + 32)
		)
		tierText.TextTruncate = Enum.TextTruncate.AtEnd
		local status = Ui.label(
			frame,
			"Status",
			"",
			Ui.FONT_BOLD,
			11,
			MUTED,
			UDim2.new(1, -16, 0, 13),
			UDim2.fromOffset(9, visualH + 49)
		)
		status.TextTruncate = Enum.TextTruncate.AtEnd
		-- One button over the card: hover tries it on, a click (tap) picks it, a
		-- second click (tap) or A wears it
		local button = Instance.new("TextButton")
		button.Name = "Select"
		button.Text = ""
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		button.Size = UDim2.fromScale(1, 1)
		button.ZIndex = 8
		button.Selectable = true
		button.Parent = frame
		-- A lift under the mouse or the D-pad
		local lift = Instance.new("UIScale")
		lift.Parent = frame
		local function raise(up: boolean)
			frame.ZIndex = if up then 2 else 1
			Ui.tween(lift, 0.2, { Scale = if up then 1.04 else 1 }, Enum.EasingStyle.Back)
		end
		local card: Card = {
			item = item,
			frame = frame,
			button = button,
			visual = visual,
			stroke = stroke,
			worn = worn,
			status = status,
			attached = false,
		}
		button.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				hoverEndAt = nil
				raise(true)
				if hoverKey ~= card.item.key then
					hoverKey = card.item.key
					refreshFocus()
				end
			end
		end)
		button.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end
			raise(false)
			if hoverKey == card.item.key then
				-- back to the picked one a moment later, unless another card is hovered
				hoverEndAt = os.clock() + 0.15
			end
		end)
		button.SelectionGained:Connect(function()
			raise(true)
			pick(card.item)
		end)
		button.SelectionLost:Connect(function()
			raise(false)
		end)
		button.Activated:Connect(function(input: InputObject?)
			local now = state()
			local it = card.item
			local fromPad = (input ~= nil and string.sub(input.UserInputType.Name, 1, 7) == "Gamepad")
				or Input.isGamepad()
			if fromPad or selectedKey[tab] == it.key then
				pick(it)
				if it.has and not isWorn(it, now) then
					equip(it)
				end
			else
				pick(it)
			end
		end)
		return card
	end

	-- Puts the photo on a card once it's in view (built once, kept)
	local function attach(card: Card)
		card.attached = true
		local item = card.item
		if item.kind == "trail" then
			return
		end
		local tier = tierOf(item.tier)
		local photo = CardPhoto.new(
			card.visual,
			{ id = item.id, kind = item.kind, name = item.name, tier = item.tier },
			tier.color
		)
		if photo then
			photo.ZIndex = 2
			-- A locked one is a dark silhouette until it's unlocked (owner, 2026-10-20:
			-- "the skin should be hidden until unlocked and not shown until then, but
			-- they should still be able to see the name and description"); one this
			-- player has on another fish is only dimmed
			if not item.has then
				photo.ImageColor3 = if item.elsewhere then Color3.fromRGB(190, 196, 206) else SILHOUETTE
			end
		end
	end

	local function attachVisible()
		local view = currentView()
		if view == nil then
			return
		end
		local scroll = view.scroll
		local top = scroll.AbsolutePosition.Y - 40
		local bottom = scroll.AbsolutePosition.Y + scroll.AbsoluteSize.Y + 40
		local budget = 3
		for _, card in view.cards do
			if card.attached then
				continue
			end
			local frame = card.frame
			if frame.AbsoluteSize.X > 1 and frame.AbsolutePosition.Y + frame.AbsoluteSize.Y >= top then
				if frame.AbsolutePosition.Y <= bottom then
					attach(card)
					budget -= 1
					if budget <= 0 then
						return
					end
				end
			end
		end
	end

	-- Each card's marks: worn, picked, its status line
	local function markCards(view: View, s: { [string]: any })
		local picked = selectedKey[tab]
		for _, card in view.cards do
			local item = card.item
			local worn = isWorn(item, s)
			card.worn.Visible = worn
			local tier = tierOf(item.tier)
			local stroke = card.stroke
			if stroke then
				if worn then
					stroke.Color = Ui.color.safe
					stroke.Transparency = 0
					stroke.Thickness = 2
				elseif item.key == picked then
					stroke.Color = Ui.color.accent
					stroke.Transparency = 0
					stroke.Thickness = 2
				elseif item.key == hoverKey then
					stroke.Color = tier.color
					stroke.Transparency = 0.05
					stroke.Thickness = 1.5
				else
					stroke.Color = tier.color
					stroke.Transparency = if item.has then 0.45 else 0.75
					stroke.Thickness = 1
				end
			end
			card.frame.BackgroundTransparency = if item.key == picked
				then 0.02
				elseif item.has then 0.12
				else 0.3
			if worn then
				card.status.Text = "WEARING"
				card.status.TextColor3 = Ui.color.safe
			elseif item.has then
				card.status.Text = if item.kind == "variant"
						and item.species ~= (s.species or Config.Species.STARTER)
					then `OWNED · {string.upper(fishName(item.species))}`
					else "OWNED"
				card.status.TextColor3 = Ui.color.text
			else
				card.status.Text = shortHow(item, s)
				card.status.TextColor3 = if item.elsewhere then Ui.color.haul else MUTED
			end
		end
	end

	-- Keeps the card a controller picked in view
	local function follow()
		local selected = GuiService.SelectedObject
		local view = currentView()
		if selected == nil or view == nil or not selected:IsDescendantOf(view.scroll) then
			return
		end
		local frame = selected.Parent
		if frame == nil or not frame:IsA("GuiObject") then
			return
		end
		local scroll = view.scroll
		local above = frame.AbsolutePosition.Y - scroll.AbsolutePosition.Y
		local below = above + frame.AbsoluteSize.Y - scroll.AbsoluteSize.Y
		if above < 0 then
			scroll.CanvasPosition = Vector2.new(0, math.max(0, scroll.CanvasPosition.Y + above - 6))
		elseif below > 0 then
			scroll.CanvasPosition = Vector2.new(0, scroll.CanvasPosition.Y + below + 6)
		end
	end
	table.insert(connections, GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(follow))

	-- Selects the picked card for a controller
	local function selectPicked()
		if not Input.isGamepad() or window.frame.Parent == nil then
			return
		end
		local view = currentView()
		local key = selectedKey[tab]
		local card = if view and key then view.byKey[key] else nil
		if card then
			GuiService.SelectedObject = card.button
		elseif view and view.cards[1] then
			GuiService.SelectedObject = view.cards[1].button
		end
	end

	---------------------------------------------------------------- render
	render = function()
		local s = state()
		-- Tabs and their counts
		for _, name in TABS do
			local _, owned, total = itemsFor(name, s, "all")
			local button = tabButtons[name]
			Ui.setButtonStyle(button, if name == tab then "primary" else "secondary")
			button.Text = `{string.upper(name)}  <font size="12" transparency="0.25">{owned}/{total}</font>`
		end
		-- The note and the filter
		local skins = tab == "Skins"
		for id, button in filterButtons do
			button.Visible = skins
			Ui.setButtonStyle(button, if id == filter then "primary" else "secondary")
		end
		local current = s.species or Config.Species.STARTER
		if skins then
			local line, lineOwned, everyOwned, every = 0, 0, 0, 0
			local items = itemsFor("Skins", s, "all")
			for _, item in items do
				if item.universal then
					every += 1
					everyOwned += if item.has then 1 else 0
				else
					line += 1
					lineOwned += if item.has then 1 else 0
				end
			end
			note.Text =
				`{string.upper(fishName(current))}'S LINE {lineOwned}/{line}  ·  EVERY FISH {everyOwned}/{every}`
			note.Size = UDim2.fromOffset(filterLeft - gridX - 8, 26)
		else
			note.Text = if tab == "Parts"
				then "LOOKS ONLY  ·  ONE A SLOT  ·  FROM ROLLS AS ANY FISH"
				elseif tab == "Variants" then "EACH RESHAPES ONE FISH  ·  FROM ROLLS AS THAT FISH"
				else "EVERY FISH'S  ·  ONE AT A TIME  ·  EARNED ON THE TIDE PASS"
			note.Size = UDim2.fromOffset(gridW, 26)
		end
		-- The grid: rebuilt only when what it holds changes, else just re-marked
		for name, view in views do
			view.scroll.Visible = name == tab
		end
		local view = views[tab]
		if view == nil then
			view = newView()
			views[tab] = view
		end
		local items = itemsFor(tab, s, filter)
		local parts: { string } = { current, filter }
		for _, item in items do
			table.insert(parts, `{item.key}={item.has}/{item.elsewhere}`)
		end
		local signature = table.concat(parts, ",")
		if signature ~= view.signature then
			local selected = GuiService.SelectedObject
			local reselect = selected ~= nil and selected:IsDescendantOf(view.scroll)
			for _, card in view.cards do
				card.frame:Destroy()
			end
			view.cards = {}
			view.byKey = {}
			view.items = items
			view.signature = signature
			for i, item in items do
				local card = buildCard(view, item, i, s)
				table.insert(view.cards, card)
				view.byKey[item.key] = card
			end
			if reselect then
				task.defer(selectPicked)
			end
		end
		-- The picked card: kept, else the one worn, else the first
		local picked = selectedKey[tab]
		if picked == nil or view.byKey[picked] == nil then
			local chosen: string? = nil
			for _, item in items do
				if isWorn(item, s) then
					chosen = item.key
					break
				end
			end
			if chosen == nil and items[1] then
				chosen = items[1].key
			end
			if chosen then
				selectedKey[tab] = chosen
			end
		end
		markCards(view, s)
		showDetails(s)
	end
	refreshFocus = function()
		local s = state()
		local view = currentView()
		if view then
			markCards(view, s)
		end
		showDetails(s)
	end

	---------------------------------------------------------------- input
	local function setTab(name: string)
		if name == tab then
			return
		end
		tab = name
		hoverKey = nil
		Sfx.play("UiOpen", { volume = 0.35, pitch = 1.05 })
		render()
		task.defer(selectPicked)
	end
	for name, button in tabButtons do
		button.Activated:Connect(function()
			setTab(name)
		end)
	end
	for id, button in filterButtons do
		button.Activated:Connect(function()
			if filter ~= id then
				filter = id
				local view = views.Skins
				if view then
					view.scroll.CanvasPosition = Vector2.zero
				end
				render()
			end
		end)
	end
	-- The mouse reaching the buttons ends any hover at once, so they act on the
	-- picked card and say what they'll do to it
	for _, button in { primary, secondary } do
		button.MouseEnter:Connect(function()
			if hoverKey then
				hoverKey = nil
				hoverEndAt = nil
				refreshFocus()
			end
		end)
	end
	primary.Activated:Connect(function()
		local item = focusItem()
		if item and item.has and not isWorn(item, state()) then
			equip(item)
		end
	end)
	secondary.Activated:Connect(function()
		local item = focusItem()
		if item == nil then
			return
		end
		if item.has and isWorn(item, state()) then
			takeOff(item)
		elseif not item.has then
			local _, open = linkFor(item)
			if open then
				open()
			end
		end
	end)
	ContextActionService:BindActionAtPriority("ApexWardrobeTabs", function(_, inputState, input)
		if inputState == Enum.UserInputState.Begin then
			local at = table.find(TABS, tab) or 1
			local step = if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1
			setTab(TABS[(at - 1 + step) % #TABS + 1])
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)

	-- The stage's motion, the hover's end and the photos coming in
	local clock = 0
	local nextAttach = 0
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt)
			clock += dt
			if hoverEndAt and os.clock() >= hoverEndAt then
				hoverEndAt = nil
				hoverKey = nil
				refreshFocus()
			end
			local waiting = pendingShow
			if waiting and os.clock() >= waiting.at then
				pendingShow = nil
				-- The same fish is re-dressed in place (no rebuild); another is built
				if waiting.fish == shownFish then
					preview:dress(waiting.dress)
				else
					shownFish = waiting.fish
					preview:show(waiting.dress, waiting.species)
				end
			end
			if stageCycle then
				local color = Color3.fromHSV((clock * 0.12) % 1, 0.55, 1)
				for _, ring in rings do
					ring.BackgroundColor3 = color
				end
				wash.BackgroundColor3 = color
				floor.BackgroundColor3 = color
				floorRim.Color = color
				stageStroke.Color = color
			end
			local made = stageWake
			if made then
				animateWake(made, clock)
			end
			if clock >= nextAttach then
				nextAttach = clock + 0.1
				attachVisible()
				local canvas = info.AbsoluteCanvasSize.Y
				local shown = info.AbsoluteWindowSize.Y
				more.Visible = canvas > shown + 4 and info.CanvasPosition.Y < canvas - shown - 4
			end
		end)
	)

	-- Start on the card worn (or the first) with a controller
	task.defer(selectPicked)

	return {
		render = function()
			render()
		end,
		cleanup = function()
			ContextActionService:UnbindAction("ApexWardrobeTabs")
			for _, connection in connections do
				connection:Disconnect()
			end
			preview:destroy()
		end,
	}
end

return Wardrobe
