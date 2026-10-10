--!strict
-- The menus: each vendor's shop (opened at its stall: E, Y or a tap on the hint
-- that shows near a counter), the Wardrobe
-- (shades, body parts and variants you own, on a preview of your fish) and the
-- roll odds. One window at a time; the cursor is freed while it's open, and a
-- controller can drive it (the D-pad moves between buttons, B closes).
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Garden = require(ReplicatedStorage.Shared.Garden)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Catch = require(ReplicatedStorage.Shared.Catch)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local Tides = require(ReplicatedStorage.Shared.Tides)
local ClientState = require(script.Parent.Parent.ClientState)
local FishPreview = require(script.Parent.Parent.FishPreview)
local Input = require(script.Parent.Parent.Input)
local Sfx = require(script.Parent.Parent.Sfx)
local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Parent.Ui)

local Shop = Config.Shop
local Tiers = Config.Tiers

local MenuController = {
	-- Set while an offer card is up: the phone's stall button sat on its edge
	stallButtonHidden = false,
}

type Menu = {
	window: Ui.Window,
	anchor: Vector3?, -- a shop closes when you swim away from its stall
	render: () -> (), -- (re)builds the rows from the current state
	ticking: boolean?, -- re-render every second (countdowns)
	cleanup: (() -> ())?,
}

local gui: ScreenGui
local current: Menu? = nil
local currentShop: string? = nil
local lastTick = 0

local function state(): { [string]: any }
	return ClientState.current or {}
end

local function coral(): number
	return state().coral or 0
end

function MenuController.isOpen(): boolean
	return current ~= nil
end

function MenuController.close()
	local menu = current
	if menu == nil then
		return
	end
	current = nil
	currentShop = nil
	if menu.cleanup then
		menu.cleanup()
	end
	menu.window.frame:Destroy()
	Input.cursorWanted = false
	ContextActionService:UnbindAction("ApexCloseMenu")
	GuiService.SelectedObject = nil
end

-- A controller starts on the menu's first button of its own, not the window's X
-- (B already closes it): the X is built first, so the Daily panel opened with X
-- selected instead of CLAIM (playtest 2026-10-09). The X only if there's nothing else.
local function selectFirst(window: Ui.Window)
	if not Input.isGamepad() then
		return
	end
	for _, child in window.frame:GetDescendants() do
		if child:IsA("GuiButton") and child ~= window.close and child.Selectable and child.Visible then
			GuiService.SelectedObject = child
			return
		end
	end
	GuiService.SelectedObject = window.close
end

local function open(title: string, subtitle: string, size: Vector2, build: (Ui.Window) -> Menu)
	MenuController.close()
	local window = Ui.window(gui, title, subtitle, size)
	local menu = build(window)
	current = menu
	window.close.Activated:Connect(MenuController.close)
	Input.cursorWanted = true
	ContextActionService:BindActionAtPriority("ApexCloseMenu", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			MenuController.close()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.ButtonB)
	menu.render()
	selectFirst(window)
end

-- Rebuilds a list's rows, keeping the scroll position and the selected button.
local function rerender(list: ScrollingFrame, build: () -> ())
	local scroll = list.CanvasPosition
	local selected = GuiService.SelectedObject
	local selectedName = if selected and selected:IsDescendantOf(list) then selected:GetFullName() else nil
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	build()
	list.CanvasPosition = scroll
	if selectedName then
		for _, child in list:GetDescendants() do
			if child:IsA("GuiButton") and child:GetFullName() == selectedName then
				GuiService.SelectedObject = child
				break
			end
		end
	end
end

-- One row: a title, a line under it, an optional status on the right, and an
-- action button. Returns the row and its button.
local function row(
	list: ScrollingFrame,
	order: number,
	name: string,
	title: string,
	blurb: string,
	status: string?,
	action: string?,
	style: Ui.ButtonStyle?,
	accent: Color3?
): (Frame, TextButton?)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, -8, 0, 64)
	frame.BackgroundColor3 = Ui.color.track
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	Ui.corner(frame, UDim.new(0, 10))
	if accent then
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 4, 1, -16)
		stripe.Position = UDim2.fromOffset(8, 8)
		stripe.BackgroundColor3 = accent
		stripe.BorderSizePixel = 0
		Ui.corner(stripe, UDim.new(1, 0))
		stripe.Parent = frame
	end
	local left = if accent then 22 else 16
	Ui.label(
		frame,
		"Title",
		title,
		Ui.FONT_BOLD,
		18,
		Ui.color.text,
		UDim2.new(1, -320, 0, 22),
		UDim2.fromOffset(left, 10)
	)
	Ui.label(
		frame,
		"Blurb",
		blurb,
		Ui.FONT,
		14,
		Ui.color.muted,
		UDim2.new(1, -320, 0, 18),
		UDim2.fromOffset(left, 34)
	)
	if status then
		local label = Ui.label(
			frame,
			"Status",
			status,
			Ui.FONT_SEMI,
			14,
			Ui.color.text,
			UDim2.fromOffset(130, 20),
			UDim2.new(1, -300, 0.5, -10)
		)
		label.TextXAlignment = Enum.TextXAlignment.Right
	end
	local button: TextButton? = nil
	if action then
		button =
			Ui.button(frame, "Action", action, UDim2.fromOffset(150, 40), UDim2.new(1, -162, 0.5, -20), style)
	end
	frame.Parent = list
	return frame, button
end

local function pips(level: number, max: number): string
	return `LV {level} / {max}`
end

local function clockText(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function coralText(amount: number): string
	return `{Ui.number(amount)} CORAL`
end

local function priceStyle(price: number): Ui.ButtonStyle
	return if coral() >= price then "primary" else "disabled"
end

local function shopSubtitle(vendorId: string): string
	local vendor = Shop.vendorsById[vendorId]
	if vendorId == "Trophies" then
		local trophies = state().trophies or {}
		local held = {}
		local seen: { [string]: boolean } = {}
		for _, trophy in Shop.trophies do
			if not seen[trophy.currency] then
				seen[trophy.currency] = true
				table.insert(held, `{trophies[trophy.currency] or 0} {trophy.currencyName}`)
			end
		end
		return `{vendor.keeper} · {vendor.blurb}   ·   You have {table.concat(held, ", ")}`
	end
	return `{vendor.keeper} · {vendor.blurb}   ·   You have {Ui.number(coral())} coral`
end

-- The Trophy Hunter: boss trophies for that boss's Teeth or Beaks (BossService)
local function trophyRows(list: ScrollingFrame)
	local s = state()
	local trophies = s.trophies or {}
	local owned = s.shades or {}
	local order = 0
	for _, trophy in Shop.trophies do
		order += 1
		local held = trophies[trophy.currency] or 0
		local has = trophy.kind == "shade" and owned[trophy.shade or ""] == true
		local boss = Config.Bosses.byId[trophy.boss]
		local blurb = `{trophy.blurb} · from the {if boss then boss.name else trophy.boss}`
		local _, button = row(
			list,
			order,
			trophy.id,
			trophy.name,
			blurb,
			`Have {held} {trophy.currencyName}`,
			if has then "OWNED" else `{trophy.price} {string.upper(trophy.currencyName)}`,
			if has then "disabled" elseif held >= trophy.price then "primary" else "disabled",
			Tiers.byId.Trophy.color
		)
		if button and not has and held >= trophy.price then
			button.Activated:Connect(function()
				ClientState.request("Buy", "trophy", trophy.id)
			end)
		end
	end
end

local function upgradeRows(list: ScrollingFrame, vendorId: string)
	local upgrades = state().upgrades or {}
	local order = 0
	for _, upgrade in Shop.upgrades do
		if upgrade.vendor ~= vendorId then
			continue
		end
		order += 1
		local level = upgrades[upgrade.id] or 0
		local cost = upgrade.costs[level + 1]
		local _, button = row(
			list,
			order,
			upgrade.id,
			upgrade.name,
			upgrade.blurb,
			pips(level, #upgrade.costs),
			if cost then coralText(cost) else "MAXED",
			if cost then priceStyle(cost) else "disabled"
		)
		if button and cost then
			button.Activated:Connect(function()
				ClientState.request("Buy", "upgrade", upgrade.id)
			end)
		end
	end
end

local function charmRows(list: ScrollingFrame)
	local s = state()
	local charms = s.charms or {}
	local boosts = s.boosts or {}
	local now = workspace:GetServerTimeNow()
	local order = 0
	for _, charm in Shop.charms do
		order += 1
		local status
		if charm.seconds then
			local left = (boosts[charm.id] or 0) - now
			status = if left > 0 then `Active {clockText(left)}` else nil
		else
			local held = charms[charm.id] or 0
			-- (Robux Second Chances can take you past the trader's cap: no "2 / 1")
			status = if held > (charm.max or 1) then `Have {held}` else `Have {held} / {charm.max or 1}`
		end
		local full = charm.max ~= nil and (charms[charm.id] or 0) >= charm.max
		local _, button = row(
			list,
			order,
			charm.id,
			charm.name,
			charm.blurb,
			status,
			if full then "FULL" else coralText(charm.price),
			if full then "disabled" else priceStyle(charm.price)
		)
		if button and not full then
			button.Activated:Connect(function()
				ClientState.request("Buy", "charm", charm.id)
			end)
		end
	end
	local trade = Shop.shellTrade
	local left = s.shellTradesLeft or trade.perDay
	local _, button = row(
		list,
		order + 1,
		"ShellTrade",
		`{trade.shells} Shells`,
		"Shells for your next roll, a few times a day",
		`{left} left today`,
		if left > 0 then coralText(trade.price) else "SOLD OUT",
		if left > 0 then priceStyle(trade.price) else "disabled",
		Color3.fromRGB(242, 228, 204)
	)
	if button and left > 0 then
		button.Activated:Connect(function()
			ClientState.request("Buy", "shells", "")
		end)
	end
end

local function dyeRows(list: ScrollingFrame, preview: FishPreview.Preview)
	local s = state()
	local owned = s.shades or {}
	local wearing = if s.equipped then s.equipped.shade else ""
	local order = 0
	for _, shade in Config.Shades.list do
		-- This fish's own Commons (its line's realistic morphs)
		if shade.price == nil or shade.species ~= s.species then
			continue
		end
		order += 1
		local price = shade.price :: number
		local has = owned[shade.id] == true
		local action: string, style: Ui.ButtonStyle
		if wearing == shade.id then
			action, style = "WEARING", "disabled"
		elseif has then
			action, style = "WEAR", "secondary"
		else
			action, style = coralText(price), priceStyle(price)
		end
		local frame, button = row(
			list,
			order,
			shade.id,
			shade.name,
			if has then "This fish has it" else "A fresh tint for this fish",
			nil,
			action,
			style,
			shade.back
		)
		frame.MouseEnter:Connect(function()
			preview:show({ shade = shade.id, parts = {}, variant = nil })
		end)
		if button then
			button.SelectionGained:Connect(function()
				preview:show({ shade = shade.id, parts = {}, variant = nil })
			end)
			button.Activated:Connect(function()
				if has then
					ClientState.request("Equip", "shade", shade.id)
				elseif coral() >= price then
					ClientState.request("Buy", "dye", shade.id)
				end
			end)
		end
	end
end

-- Opens a vendor's shop (`anchor`: its stall, so swimming off closes it).
function MenuController.openShop(vendorId: string, anchor: Vector3?)
	local vendor = Shop.vendorsById[vendorId]
	if vendor == nil then
		return
	end
	local wide = vendorId == "Dyer"
	open(vendor.name, shopSubtitle(vendorId), Vector2.new(if wide then 860 else 680, 470), function(window)
		local listHolder = window.content
		local preview: FishPreview.Preview? = nil
		if wide then
			local previewFrame =
				Ui.panel(window.content, "PreviewHolder", UDim2.new(0, 230, 1, 0), UDim2.new())
			previewFrame.BackgroundTransparency = 0.6
			local made = FishPreview.new(previewFrame, UDim2.fromScale(1, 1), UDim2.new())
			local equipped = state().equipped
			made:show({
				shade = if equipped and equipped.shade ~= "" then equipped.shade else nil,
				parts = {},
				variant = nil,
			})
			preview = made
			local holder = Instance.new("Frame")
			holder.BackgroundTransparency = 1
			holder.Position = UDim2.fromOffset(244, 0)
			holder.Size = UDim2.new(1, -244, 1, 0)
			holder.Parent = window.content
			listHolder = holder
		end
		local list = Ui.list(listHolder)
		return {
			window = window,
			anchor = anchor,
			ticking = vendorId == "Charms",
			render = function()
				window.subtitle.Text = shopSubtitle(vendorId)
				rerender(list, function()
					if vendorId == "Charms" then
						charmRows(list)
					elseif vendorId == "Trophies" then
						trophyRows(list)
					elseif vendorId == "Dyer" and preview then
						dyeRows(list, preview)
					else
						upgradeRows(list, vendorId)
					end
				end)
			end,
			cleanup = function()
				if preview then
					preview:destroy()
				end
			end,
		}
	end)
	currentShop = vendorId
end

-- Your den (Config/Dens): the upgrade, the glow color, and every open slot. Picking
-- a slot lists what fits it (owned things are free to place; the rest cost coral).
local denPickSlot: string? = nil

local function denRows(list: ScrollingFrame)
	local s = state()
	local den = s.den or { level = 1, furniture = {}, owned = {}, glow = "Teal" }
	local Dens = Config.Dens
	local order = 0
	local function next(): number
		order += 1
		return order
	end
	local pickSlot = denPickSlot
	if pickSlot then
		local slot = Dens.slotsById[pickSlot]
		local current = den.furniture[pickSlot]
		local _, back = row(
			list,
			next(),
			"Back",
			`Spot {pickSlot}`,
			`{slot.kind} spot · tap an item to place it`,
			nil,
			"BACK",
			"secondary"
		)
		if back then
			back.Activated:Connect(function()
				denPickSlot = nil
				MenuController.rerenderCurrent()
			end)
		end
		if current then
			local item = Dens.itemsById[current]
			local _, clear = row(
				list,
				next(),
				"Clear",
				`Take out the {if item then item.name else current}`,
				"Leaves the spot empty",
				nil,
				"CLEAR",
				"danger"
			)
			if clear then
				clear.Activated:Connect(function()
					ClientState.request("DenPlace", pickSlot, "")
					denPickSlot = nil
				end)
			end
		end
		for _, item in Dens.items do
			if not table.find(item.kinds, slot.kind) then
				continue
			end
			local owned = den.owned[item.id] == true
			local action = if current == item.id
				then "PLACED"
				elseif owned then "PLACE"
				else coralText(item.price)
			local style: Ui.ButtonStyle = if current == item.id
				then "disabled"
				elseif owned then "primary"
				else priceStyle(item.price)
			local _, button = row(
				list,
				next(),
				item.id,
				item.name,
				item.blurb,
				if owned then "Owned" else nil,
				action,
				style,
				item.color
			)
			if button and current ~= item.id then
				button.Activated:Connect(function()
					ClientState.request("DenPlace", pickSlot, item.id)
					denPickSlot = nil
				end)
			end
		end
		return
	end
	-- The upgrade
	local level = Dens.levels[den.level] or Dens.levels[1]
	local upgrade = Dens.levels[den.level + 1]
	if upgrade then
		local _, button = row(
			list,
			next(),
			"Upgrade",
			`Upgrade to a {upgrade.name}`,
			upgrade.blurb,
			`Now: {level.name} (level {level.level})`,
			coralText(upgrade.cost),
			priceStyle(upgrade.cost),
			Ui.color.haul
		)
		if button then
			button.Activated:Connect(function()
				ClientState.request("DenUpgrade")
			end)
		end
	else
		row(list, next(), "Upgrade", `A {level.name}`, level.blurb, "Fully upgraded", nil, nil, Ui.color.haul)
	end
	-- The Coral Garden: what it grows here, and the Deep Garden pass
	local passes = s.passes or {}
	local garden = s.garden
	if typeof(garden) == "table" then
		local nextRates = if upgrade then Garden.rates(upgrade.level, passes.DeepGarden == true) else nil
		local blurb = `{Ui.number(garden.coralPerHour)} coral and {Ui.number(garden.shellsPerHour)} shells an hour, `
			.. `holds {garden.hours} h · ×{garden.rest} while you rest here`
		if nextRates and upgrade then
			blurb ..= ` · a {upgrade.name} grows {Ui.number(nextRates.coralPerHour)}/h`
		end
		local deepPass = Config.Monetization.passesByKey.DeepGarden
		local canBuy = not passes.DeepGarden and deepPass and Store.listed(deepPass.id)
		local frame, button = row(
			list,
			next(),
			"Garden",
			"Coral Garden",
			blurb,
			`{Ui.number(garden.coral)} / {Ui.number(garden.capCoral)} grown`,
			if canBuy and deepPass then `DEEP GARDEN · {Store.price(deepPass.price)}` else nil,
			"gold",
			Color3.fromRGB(255, 120, 140)
		)
		local blurbLabel = frame:FindFirstChild("Blurb") :: TextLabel?
		if blurbLabel then
			blurbLabel.TextTruncate = Enum.TextTruncate.AtEnd
		end
		if button then
			button.TextSize = 13
			button.Activated:Connect(function()
				Store.buyPass("DeepGarden")
			end)
		end
	end
	-- The glow color
	for _, glow in Dens.glows do
		local owned = glow.price == 0 or den.owned[`Glow:{glow.id}`] == true
		local worn = den.glow == glow.id
		local _, button = row(
			list,
			next(),
			`Glow{glow.id}`,
			`{glow.name} glow`,
			"Your lamps, banners and trophy trims",
			nil,
			if worn then "LIT" elseif owned then "SET" else coralText(glow.price),
			if worn then "disabled" elseif owned then "secondary" else priceStyle(glow.price),
			glow.color
		)
		if button and not worn then
			button.Activated:Connect(function()
				ClientState.request("DenColor", glow.id)
			end)
		end
	end
	-- The slots open at this level, and the ones the next level opens
	for i = 1, #Dens.levels do
		local def = Dens.levels[i]
		for _, slotId in def.slots do
			local slot = Dens.slotsById[slotId]
			local itemId = den.furniture[slotId]
			local item = if itemId then Dens.itemsById[itemId] else nil
			if i <= den.level then
				local _, button = row(
					list,
					next(),
					`Slot{slotId}`,
					`Spot {slotId} · {slot.kind}`,
					if item then item.name else "Empty",
					nil,
					"CHANGE",
					"secondary",
					if item then item.color else nil
				)
				if button then
					button.Activated:Connect(function()
						denPickSlot = slotId
						MenuController.rerenderCurrent()
					end)
				end
			elseif i == den.level + 1 then
				row(
					list,
					next(),
					`Slot{slotId}`,
					`Spot {slotId} · {slot.kind}`,
					`Opens with the {def.name}`,
					nil,
					"LOCKED",
					"disabled"
				)
			end
		end
	end
	-- The Den Expansion pass's spots (open at any level)
	local expansion = Config.Monetization.passesByKey.DenExpansion
	local hasExpansion = passes.DenExpansion == true
	if hasExpansion then
		for _, slot in Dens.slots do
			if slot.pass ~= "DenExpansion" then
				continue
			end
			local itemId = den.furniture[slot.id]
			local item = if itemId then Dens.itemsById[itemId] else nil
			local _, button = row(
				list,
				next(),
				`Slot{slot.id}`,
				`Spot {slot.id} · {slot.kind}`,
				if item then item.name else "Empty · Den Expansion",
				nil,
				"CHANGE",
				"secondary",
				if item then item.color else nil
			)
			if button then
				button.Activated:Connect(function()
					denPickSlot = slot.id
					MenuController.rerenderCurrent()
				end)
			end
		end
	elseif expansion and Store.listed(expansion.id) then
		local _, button = row(
			list,
			next(),
			"Expansion",
			"Den Expansion",
			"Four more spots (two on the floor, two on the walls), open at any level",
			nil,
			Store.price(expansion.price),
			"gold",
			Ui.color.haul
		)
		if button then
			button.Activated:Connect(function()
				Store.buyPass("DenExpansion")
			end)
		end
	end
end

local function denSubtitle(): string
	local s = state()
	local den = s.den or { level = 1 }
	local level = Config.Dens.levels[den.level] or Config.Dens.levels[1]
	return `{level.name} · level {level.level}   ·   Visitors can look, only you can change it   ·   You have {Ui.number(
		coral()
	)} coral`
end

function MenuController.openDen(anchor: Vector3?)
	denPickSlot = nil
	open("YOUR DEN", denSubtitle(), Vector2.new(700, 480), function(window)
		local list = Ui.list(window.content)
		return {
			window = window,
			anchor = anchor,
			render = function()
				window.subtitle.Text = denSubtitle()
				rerender(list, function()
					denRows(list)
				end)
			end,
		}
	end)
	currentShop = "__den"
end

-- Re-draws the open menu (a pick inside it changed)
function MenuController.rerenderCurrent()
	if current then
		current.render()
	end
end

local TABS = { "Shades", "Parts", "Variants" }

local function equippedDress(): Cosmetics.Dress
	local equipped = state().equipped or {}
	return {
		shade = if equipped.shade and equipped.shade ~= "" then equipped.shade else nil,
		parts = equipped.parts or {},
		variant = if equipped.variant and equipped.variant ~= "" then equipped.variant else nil,
	}
end

local function wardrobeRows(list: ScrollingFrame, tab: string)
	local s = state()
	local equipped = s.equipped or { shade = "", variant = "", parts = {} }
	local order = 0
	local function add(
		kind: string,
		id: string,
		name: string,
		tier: string,
		chance: number,
		has: boolean,
		worn: boolean,
		slot: string?,
		color: Color3?,
		elsewhere: boolean?,
		how: string? -- how a locked one that isn't rolled is got
	)
		order += 1
		local tierInfo = Tiers.byId[tier]
		local blurb = if has
			then `{tierInfo.name}{if slot then ` · {slot}` else ""}`
			elseif elsewhere then `{tierInfo.name} · on another of your fish · unlock it again for this one`
			elseif how then `{tierInfo.name} · {how}`
			elseif chance <= 0 then `{tierInfo.name} · beat the world boss to win it`
			else `{tierInfo.name} · roll to find · {RollOdds.oneIn(1 / chance)}`
		local action = if not has then "LOCKED" elseif worn then "TAKE OFF" else "WEAR"
		local style: Ui.ButtonStyle = if not has then "disabled" elseif worn then "secondary" else "primary"
		local _, button = row(
			list,
			order,
			id,
			if has or elsewhere then name else "???",
			blurb,
			nil,
			action,
			style,
			color or tierInfo.color
		)
		if button and has then
			button.Activated:Connect(function()
				if worn then
					ClientState.request("Equip", kind, "", slot)
				else
					ClientState.request("Equip", kind, id, slot)
				end
			end)
		end
	end
	if tab == "Shades" then
		-- This fish's own line (owner, 2026-10-10: every fish its own skins, wilder as
		-- they get rarer), then the skins every fish can earn: its catch track, boss
		-- trophies, treasure, and a week's limited skin once it has one
		local owned = s.shades or {}
		local shown: { any } = {}
		local line: { any } = Config.Shades.lines[s.species or "Nibbler"] or {}
		for _, shade in line do
			table.insert(shown, shade)
		end
		for _, shade in Config.Shades.list do
			if shade.species == nil and (shade.week == nil or owned[shade.id]) then
				table.insert(shown, shade)
			end
		end
		for _, shade in shown do
			local has = owned[shade.id] == true
			local elsewhere = not has and shade.species == nil and (s.otherShades or {})[shade.id] == true
			local rarity = if shade.catch then Config.Catch.byId[shade.catch] else nil
			local how = if rarity
				then `catch {rarity.track} {rarity.name} fish as this fish (the LOG's catch track)`
				elseif shade.treasure then "dug up from a Captain's treasure chest"
				elseif shade.week then "the Catch of the Week"
				else nil
			add(
				"shade",
				shade.id,
				shade.name,
				shade.tier,
				shade.chance,
				has,
				equipped.shade == shade.id,
				nil,
				if has or elsewhere then shade.back else nil,
				elsewhere,
				how
			)
		end
	elseif tab == "Parts" then
		for _, part in Config.Exotics.parts do
			local has = (s.parts or {})[part.id] == true
			add(
				"part",
				part.id,
				part.name,
				"Abyssal",
				part.chance,
				has,
				(equipped.parts or {})[part.slot] == part.id,
				part.slot
			)
		end
	else
		for _, variant in Config.Exotics.variants do
			local has = (s.variants or {})[variant.id] == true
			add(
				"variant",
				variant.id,
				variant.name,
				"Abyssal",
				variant.chance,
				has,
				equipped.variant == variant.id
			)
		end
	end
end

function MenuController.openWardrobe()
	open(
		"Wardrobe",
		"Shades, body parts and exotic variants you've found",
		Vector2.new(880, 500),
		function(window)
			local previewFrame =
				Ui.panel(window.content, "PreviewHolder", UDim2.new(0, 250, 1, 0), UDim2.new())
			previewFrame.BackgroundTransparency = 0.6
			local preview = FishPreview.new(previewFrame, UDim2.fromScale(1, 1), UDim2.new())
			local right = Instance.new("Frame")
			right.BackgroundTransparency = 1
			right.Position = UDim2.fromOffset(264, 0)
			right.Size = UDim2.new(1, -264, 1, 0)
			right.Parent = window.content
			local tab = "Shades"
			local tabs: { [string]: TextButton } = {}
			local listHolder = Instance.new("Frame")
			listHolder.BackgroundTransparency = 1
			listHolder.Position = UDim2.fromOffset(0, 50)
			listHolder.Size = UDim2.new(1, 0, 1, -50)
			listHolder.Parent = right
			local list = Ui.list(listHolder)
			local menu: Menu
			for i, name in TABS do
				local button = Ui.button(
					right,
					name,
					string.upper(name),
					UDim2.fromOffset(150, 38),
					UDim2.fromOffset((i - 1) * 160, 0),
					"secondary"
				)
				tabs[name] = button
				button.Activated:Connect(function()
					tab = name
					menu.render()
				end)
			end
			local lastDress = ""
			menu = {
				window = window,
				render = function()
					for name, button in tabs do
						Ui.setButtonStyle(button, if name == tab then "primary" else "secondary")
					end
					local dress = equippedDress()
					local key = `{dress.shade}|{Cosmetics.partsText(dress.parts)}|{dress.variant}`
					if key ~= lastDress then
						lastDress = key
						preview:show(dress)
					end
					rerender(list, function()
						wardrobeRows(list, tab)
					end)
				end,
				cleanup = function()
					preview:destroy()
				end,
			}
			return menu
		end
	)
end

-- A stat as a bar (1 = the Nibbler's; the bar is full at 1.6).
local function statBar(parent: Instance, y: number, label: string, value: number)
	Ui.label(
		parent,
		label,
		string.upper(label),
		Ui.FONT_BOLD,
		12,
		Ui.color.muted,
		UDim2.fromOffset(80, 16),
		UDim2.fromOffset(0, y)
	)
	local _, fill =
		Ui.bar(parent, label .. "Bar", UDim2.new(1, -90, 0, 6), UDim2.fromOffset(90, y + 5), Ui.color.accent)
	fill.Size = UDim2.fromScale(math.clamp(value / 1.6, 0.05, 1), 1)
	fill.BackgroundColor3 = if value > 1.05
		then Ui.color.safe
		elseif value < 0.95 then Ui.color.haul
		else Ui.color.accent
end

-- The species menu: every playable fish, its level, stats and abilities; switch to
-- one you own (in the safe zone) or unlock one with its biome's DNA and coral.
function MenuController.openSpecies()
	open(
		"Your Fish",
		"Every species grows on its own. Switch in the safe zone.",
		Vector2.new(920, 540),
		function(window)
			local left = Instance.new("Frame")
			left.BackgroundTransparency = 1
			left.Size = UDim2.new(0, 300, 1, 0)
			left.Parent = window.content
			local list = Ui.list(left, 6)
			local right =
				Ui.panel(window.content, "Detail", UDim2.new(1, -316, 1, 0), UDim2.fromOffset(316, 0))
			right.BackgroundTransparency = 0.55
			local preview = FishPreview.new(right, UDim2.new(0.5, 0, 0, 190), UDim2.fromOffset(0, 6))
			local info = Instance.new("Frame")
			info.BackgroundTransparency = 1
			info.Position = UDim2.new(0.5, 4, 0, 14)
			info.Size = UDim2.new(0.5, -18, 0, 180)
			info.Parent = right
			local lower = Instance.new("Frame")
			lower.BackgroundTransparency = 1
			lower.Position = UDim2.fromOffset(18, 204)
			lower.Size = UDim2.new(1, -36, 1, -214)
			lower.Parent = right
			local chosen: string = state().species or Config.Species.STARTER
			local shownPreview = ""
			local menu: Menu

			local function renderDetail()
				for _, frame in { info, lower } do
					for _, child in frame:GetChildren() do
						child:Destroy()
					end
				end
				local s = state()
				local species = Config.Species.byId[chosen]
				local owned = (s.unlocked or {})[chosen] == true
				local tutorialDone = s.tutorial ~= nil and s.tutorial.done == true
				if shownPreview ~= chosen then
					shownPreview = chosen
					preview:show({ shade = nil, parts = {}, variant = nil }, chosen)
				end
				Ui.label(
					info,
					"Name",
					string.upper(species.name),
					Ui.FONT_HEAVY,
					26,
					Ui.color.text,
					UDim2.new(1, 0, 0, 30)
				)
				Ui.label(
					info,
					"Role",
					string.upper(species.role),
					Ui.FONT_BOLD,
					14,
					Ui.color.accent,
					UDim2.new(1, 0, 0, 18),
					UDim2.fromOffset(0, 32)
				)
				local blurb = Ui.label(
					info,
					"Blurb",
					species.blurb,
					Ui.FONT,
					15,
					Ui.color.muted,
					UDim2.new(1, 0, 0, 60),
					UDim2.fromOffset(0, 54)
				)
				blurb.TextWrapped = true
				blurb.TextYAlignment = Enum.TextYAlignment.Top
				local level = (s.speciesLevels or {})[chosen]
				Ui.label(
					info,
					"Level",
					if owned then `LEVEL {level or 1}` else "NOT UNLOCKED",
					Ui.FONT_HEAVY,
					16,
					if owned then Ui.color.haul else Ui.color.muted,
					UDim2.new(1, 0, 0, 20),
					UDim2.fromOffset(0, 120)
				)

				statBar(lower, 0, "Speed", species.stats.speed)
				statBar(lower, 22, "Turning", species.stats.turn)
				statBar(lower, 44, "Health", species.stats.health)
				statBar(lower, 66, "Bite", species.stats.bite)
				local names: { string } = {}
				for _, id in species.abilities do
					table.insert(names, Config.Abilities.byId[id].name)
				end
				local abilityText = if #names == 1
					then `Ability: {names[1]} · {Config.Abilities.byId[species.abilities[1]].blurb}`
					else `Abilities (pick one in its tree): {table.concat(names, " · ")}`
				local abilities = Ui.label(
					lower,
					"Abilities",
					abilityText,
					Ui.FONT_SEMI,
					14,
					Ui.color.text,
					UDim2.new(1, 0, 0, 36),
					UDim2.fromOffset(0, 94)
				)
				abilities.TextWrapped = true
				abilities.TextYAlignment = Enum.TextYAlignment.Top

				-- What it takes, and the button
				local rule = species.unlock
				local note = ""
				local action = ""
				local style: Ui.ButtonStyle = "disabled"
				local onPress: (() -> ())? = nil
				if s.species == chosen then
					action = "SWIMMING AS THIS"
				elseif owned then
					if tutorialDone then
						action, style = `SWIM AS {string.upper(species.name)}`, "primary"
						note = "Switching respawns you in your den. Bank your Haul first."
						onPress = function()
							ClientState.request("SelectSpecies", chosen)
						end
					else
						action = "FINISH THE TUTORIAL"
					end
				elseif rule.kind == "tutorial" then
					action = "FINISH THE TUTORIAL"
					note = "Finish the tutorial and this fish is yours."
				elseif rule.kind == "dna" and rule.biome then
					local biome = Config.Biomes.byId[rule.biome]
					local have = (s.dna or {})[rule.biome] or 0
					local need = rule.dna or 0
					local price = rule.coral or 0
					note =
						`Unlock with {need} {biome.name} DNA (you have {have}) and {Ui.number(price)} coral. DNA drops from fish in the {biome.name}.`
					if have >= need and coral() >= price then
						action, style = "UNLOCK", "gold"
						onPress = function()
							ClientState.request("UnlockSpecies", chosen)
						end
					else
						action = "LOCKED"
					end
				end
				local noteLabel = Ui.label(
					lower,
					"Note",
					note,
					Ui.FONT,
					14,
					Ui.color.muted,
					UDim2.new(1, -200, 0, 40),
					UDim2.new(0, 0, 1, -44)
				)
				noteLabel.TextWrapped = true
				noteLabel.TextYAlignment = Enum.TextYAlignment.Top
				local button = Ui.button(
					lower,
					"Action",
					action,
					UDim2.fromOffset(190, 44),
					UDim2.new(1, -190, 1, -46),
					style
				)
				if onPress then
					button.Activated:Connect(onPress)
				end
			end

			menu = {
				window = window,
				render = function()
					rerender(list, function()
						local s = state()
						for i, species in Config.Species.list do
							local owned = (s.unlocked or {})[species.id] == true
							local level = (s.speciesLevels or {})[species.id]
							local status = if s.species == species.id
								then "SWIMMING"
								elseif owned then `LV {level or 1}`
								else "LOCKED"
							local selected = species.id == chosen
							-- The chip on the right is a status, not a button: the whole row
							-- selects the species (a bright LOCKED chip once read as clickable)
							local frame, chip = row(
								list,
								i,
								species.id,
								species.name,
								species.role,
								nil,
								status,
								if s.species == species.id
									then "primary"
									elseif owned then "secondary"
									else "disabled",
								species.back
							)
							frame.Size = UDim2.new(1, -8, 0, 58)
							-- A narrow column: give the names the room the wide rows give a status
							for _, name in { "Title", "Blurb" } do
								local label = frame:FindFirstChild(name) :: TextLabel?
								if label then
									label.Size = UDim2.new(1, -140, 0, label.Size.Y.Offset)
								end
							end
							if chip then
								chip.Size = UDim2.fromOffset(100, 34)
								chip.Position = UDim2.new(1, -110, 0.5, -17)
								chip.Selectable = false
								chip.Active = false
							end
							if selected then
								frame.BackgroundTransparency = 0.05
								Ui.stroke(frame, Ui.color.accent, 0.1, 2)
							end
							local hit = Instance.new("TextButton")
							hit.Name = "Select"
							hit.Text = ""
							hit.BackgroundTransparency = 1
							hit.AutoButtonColor = false
							hit.Size = UDim2.fromScale(1, 1)
							hit.ZIndex = 5
							hit.Selectable = true
							hit.Parent = frame
							hit.MouseEnter:Connect(function()
								if not selected then
									frame.BackgroundTransparency = 0.15
								end
							end)
							hit.MouseLeave:Connect(function()
								if not selected then
									frame.BackgroundTransparency = 0.35
								end
							end)
							hit.Activated:Connect(function()
								if chosen ~= species.id then
									chosen = species.id
									menu.render()
								end
							end)
						end
					end)
					renderDetail()
				end,
				cleanup = function()
					preview:destroy()
				end,
			}
			return menu
		end
	)
end

-- The satchel: the treasure maps you hold (Config/Treasure). FOLLOW one and the HUD's
-- sonar leads you to its X; only you can dig it up.
function MenuController.openSatchel()
	local Treasure = Config.Treasure
	open("Satchel", "", Vector2.new(720, 460), function(window)
		local list = Ui.list(window.content, 6)
		return {
			window = window,
			render = function()
				local s = state()
				local found = if typeof(s.treasures) == "table" then s.treasures.found or 0 else 0
				window.subtitle.Text =
					`Treasure maps drop from big fish, shells and big banks · Treasures found: {found}`
				rerender(list, function()
					local held = if typeof(s.maps) == "table" then s.maps else {}
					for i, map in held do
						local tier = Treasure.byId[map.tier]
						local following = s.activeMap == map.id
						local frame, button = row(
							list,
							i,
							map.id,
							`{if tier then tier.name else map.tier} Treasure Map`,
							map.hint,
							if following then "FOLLOWING" else "",
							if following then "STOP" else "FOLLOW",
							if following then "secondary" else "primary",
							if tier then tier.color else nil
						)
						frame.Size = UDim2.new(1, -8, 0, 64)
						if button then
							button.Activated:Connect(function()
								ClientState.request("FollowMap", if following then "" else map.id)
							end)
						end
					end
					if #held == 0 then
						local empty = Ui.label(
							list,
							"Empty",
							"No maps yet. Big fish, shells and big banks sometimes carry one.",
							Ui.FONT_SEMI,
							15,
							Ui.color.muted,
							UDim2.new(1, -8, 0, 40)
						)
						empty.TextXAlignment = Enum.TextXAlignment.Center
					end
					-- What a map can hold, per tier
					local order = #held
					for _, tier in Treasure.tiers do
						order += 1
						local total = 0
						for _, reward in tier.rewards do
							total += reward.weight
						end
						local parts: { string } = {}
						for _, reward in tier.rewards do
							table.insert(parts, `{reward.name} {RollOdds.percent(reward.weight / total)}`)
						end
						local frame = row(
							list,
							order,
							`Tier{tier.id}`,
							`{tier.name} chests hold`,
							table.concat(parts, " · "),
							nil,
							nil,
							nil,
							tier.color
						)
						frame.Size = UDim2.new(1, -8, 0, 56)
						frame.BackgroundTransparency = 0.6
						local blurb = frame:FindFirstChild("Blurb") :: TextLabel?
						if blurb then
							blurb.Size = UDim2.new(1, -40, 0, 18)
							blurb.TextTruncate = Enum.TextTruncate.AtEnd
						end
					end
				end)
			end,
		}
	end)
end

function MenuController.openOdds()
	local s = state()
	local lucky = (s.charms or {}).Lucky or 0
	local luck = if lucky > 0 then 2 else 1
	local subtitle = if luck > 1
		then "Your next roll uses a Lucky Charm: ×2 on everything but coral"
		else "Every outcome of one roll for this fish; they add up to 100%"
	open("Roll Odds", subtitle, Vector2.new(620, 520), function(window)
		local list = Ui.list(window.content, 6)
		return {
			window = window,
			render = function()
				rerender(list, function()
					-- Shades this fish already has never roll again for it
					local odds = RollOdds.table(luck, s.shades, s.species)
					table.sort(odds, function(a, b)
						return a.probability > b.probability
					end)
					for i, entry in odds do
						local outcome = entry.outcome
						local tier = Tiers.byId[outcome.tier]
						local frame = row(
							list,
							i,
							outcome.id,
							outcome.name,
							`{tier.name} · {RollOdds.oneIn(entry.probability)}`,
							RollOdds.percent(entry.probability),
							nil,
							nil,
							tier.color
						)
						frame.Size = UDim2.new(1, -8, 0, 56)
						local status = frame:FindFirstChild("Status") :: TextLabel?
						if status then
							status.Position = UDim2.new(1, -146, 0.5, -10)
							status.TextColor3 = tier.color
						end
					end
				end)
			end,
		}
	end)
end

-- A list heading (the Shop's sections)
local function heading(list: ScrollingFrame, order: number, text: string)
	local label =
		Ui.label(list, `Heading{order}`, text, Ui.FONT_HEAVY, 15, Ui.color.haul, UDim2.new(1, -8, 0, 24))
	label.LayoutOrder = order
	label.TextYAlignment = Enum.TextYAlignment.Bottom
end

-- A taller row whose blurb wraps onto two lines (the Shop's descriptions)
local function tallRow(
	list: ScrollingFrame,
	order: number,
	name: string,
	title: string,
	blurb: string,
	status: string?,
	action: string?,
	style: Ui.ButtonStyle?,
	accent: Color3?
): (Frame, TextButton?)
	local frame, button = row(list, order, name, title, blurb, status, action, style, accent)
	frame.Size = UDim2.new(1, -8, 0, 80)
	local blurbLabel = frame:FindFirstChild("Blurb") :: TextLabel?
	if blurbLabel then
		blurbLabel.Size = UDim2.new(1, -320, 0, 38)
		blurbLabel.TextWrapped = true
		blurbLabel.TextYAlignment = Enum.TextYAlignment.Top
	end
	return frame, button
end

-- The Shop (SHOP on the HUD, or the View button on a controller): Robux boosts and
-- passes, the daily reward and the free perks. Roblox's own prompts do the buying;
-- the server grants (MonetizationService). Shell packs are paid random items (they
-- buy rolls): hidden where the player's policy restricts them, with the roll odds
-- one tap away.
function MenuController.openStore()
	local Monetization = Config.Monetization
	local tune = Monetization.tuning
	open(
		"Shop",
		"Growth and safety, never bite damage · everything here can be earned in play too",
		Vector2.new(720, 540),
		function(window)
			local list = Ui.list(window.content, 6)
			return {
				window = window,
				ticking = true,
				render = function()
					local s = state()
					local passes = s.passes or {}
					local now = workspace:GetServerTimeNow()
					local order = 0
					local function next(): number
						order += 1
						return order
					end
					rerender(list, function()
						-- Daily
						local daily = s.daily
						if typeof(daily) == "table" then
							local _, button = row(
								list,
								next(),
								"Daily",
								"Daily reward",
								`Come back every day: the rewards build to Day 7 · best streak {daily.best or 0}`,
								if daily.claimable
									then `Day {daily.day} is ready!`
									else `Next in {Format.duration(
										(daily.nextAt or 0) - workspace:GetServerTimeNow()
									)}`,
								if daily.claimable then "CLAIM" else "OPEN",
								if daily.claimable then "gold" else "secondary",
								Ui.color.haul
							)
							if button then
								button.Activated:Connect(MenuController.openDaily)
							end
						end
						-- Boosts (developer products)
						heading(list, next(), "BOOSTS")
						for _, product in Monetization.products do
							if product.shop == false or not Store.listed(product.id) then
								continue
							end
							if product.paidRandom and s.paidRandomRestricted then
								continue
							end
							local status: string? = nil
							local style: Ui.ButtonStyle = if product.id == 0 then "disabled" else "gold"
							if product.key == "ServerFrenzy" then
								local left = (workspace:GetAttribute("FrenzyUntil") or 0) - now
								status = if left > 0 then `Active {clockText(left)}` else nil
							elseif product.key == "SecondChance" then
								local held = (s.charms or {}).SecondChance or 0
								status = `Have {held} / {tune.secondChance.maxCharms}`
								if held >= tune.secondChance.maxCharms then
									style = "disabled"
								end
							end
							local blurb = product.description
							if product.paidRandom then
								blurb ..= " Every roll's odds are in ODDS."
							end
							local frame, button = tallRow(
								list,
								next(),
								product.key,
								product.name,
								blurb,
								status,
								Store.price(product.price),
								style,
								if product.paidRandom then Color3.fromRGB(242, 228, 204) else Ui.color.haul
							)
							if button and style ~= "disabled" then
								button.Activated:Connect(function()
									Store.buyProduct(product.key)
								end)
							end
							-- Paid random: the odds before buying, one tap away
							if product.paidRandom then
								local odds = Ui.button(
									frame,
									"Odds",
									"ODDS",
									UDim2.fromOffset(64, 30),
									UDim2.new(1, -236, 0.5, -15),
									"secondary"
								)
								odds.TextSize = 13
								odds.Activated:Connect(MenuController.openOdds)
							end
						end
						-- Passes
						heading(list, next(), "GAME PASSES")
						for _, pass in Monetization.passes do
							if not Store.listed(pass.id) then
								continue
							end
							local has = passes[pass.key] == true
							local _, button = tallRow(
								list,
								next(),
								pass.key,
								pass.name,
								pass.description,
								if has then "Owned" else nil,
								if has then "OWNED" else Store.price(pass.price),
								if has or pass.id == 0 then "disabled" else "gold",
								Ui.color.accent
							)
							if button and not has and pass.id ~= 0 then
								button.Activated:Connect(function()
									Store.buyPass(pass.key)
								end)
							end
						end
						-- Free perks
						heading(list, next(), "FREE PERKS")
						local premium = s.premium == true
						local _, premiumButton = tallRow(
							list,
							next(),
							"Premium",
							"Roblox Premium",
							`Premium members earn +{math.floor((tune.premiumCoral - 1) * 100 + 0.5)}% coral from everything.`,
							if premium then "Active" else nil,
							if premium then "ACTIVE" else "GET PREMIUM",
							if premium then "disabled" else "secondary",
							Ui.color.safe
						)
						if premiumButton and not premium then
							premiumButton.Activated:Connect(Store.buyPremium)
						end
						if tune.group.id ~= 0 then
							local member = s.inGroup == true
							tallRow(
								list,
								next(),
								"Group",
								"Join the group",
								`Members earn +{math.floor((tune.group.coral - 1) * 100 + 0.5)}% coral, and joining gives {tune.group.shells} shells once (rejoin the game after joining).`,
								if member then "Member" else nil,
								nil,
								nil,
								Ui.color.safe
							)
						end
					end)
				end,
			}
		end
	)
end

-- The daily login streak (DAILY on the HUD; it opens by itself on joining when a
-- reward is waiting): seven days that build to a big Day 7, then loop with a bonus
-- for each finished week.
function MenuController.openDaily()
	local Daily = Config.Daily
	open("Daily Reward", "", Vector2.new(780, 400), function(window)
		local holder = Instance.new("Frame")
		holder.Name = "Days"
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.new(1, 0, 0, 200)
		holder.Parent = window.content
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = holder
		local footer = Ui.label(
			window.content,
			"Footer",
			"",
			Ui.FONT_SEMI,
			15,
			Ui.color.muted,
			UDim2.new(1, 0, 0, 20),
			UDim2.fromOffset(0, 212)
		)
		footer.TextXAlignment = Enum.TextXAlignment.Center
		local claim = Ui.button(
			window.content,
			"Claim",
			"CLAIM",
			UDim2.fromOffset(240, 48),
			UDim2.new(0.5, -120, 0, 240),
			"gold"
		)
		claim.TextSize = 20
		claim.FontFace = Ui.FONT_HEAVY
		claim.Activated:Connect(function()
			ClientState.request("ClaimDaily")
		end)
		-- What was claimed shows in the footer for a few seconds
		local claimedText, claimedUntil = "", 0
		local claimed = (ReplicatedStorage:WaitForChild("Remotes") :: Instance):WaitForChild(
				"DailyClaimed"
			) :: RemoteEvent
		local connection = claimed.OnClientEvent:Connect(function(summary: { [string]: any })
			local got = if typeof(summary.got) == "table" then table.concat(summary.got, " · ") else ""
			claimedText = `Day {summary.streak} claimed: {got}`
			claimedUntil = os.clock() + 4
			Sfx.play("Bank", { volume = 0.6 })
			MenuController.rerenderCurrent()
		end)
		local function lines(reward: typeof(Daily.days[1]), bonus: number): string
			local parts: { string } = {}
			if reward.coral then
				table.insert(parts, `{Ui.number(reward.coral * bonus)} CORAL`)
			end
			if reward.shells then
				table.insert(parts, `{Ui.number(reward.shells * bonus)} SHELLS`)
			end
			if reward.wraps then
				table.insert(parts, `{reward.wraps} KELP WRAP`)
			end
			if reward.charms then
				for id, count in reward.charms do
					local charm = Config.Shop.charmsById[id]
					table.insert(parts, `{count} {string.upper(if charm then charm.name else id)}`)
				end
			end
			if reward.map then
				local tier = Config.Treasure.byId[reward.map]
				table.insert(parts, `{string.upper(if tier then tier.name else reward.map)} MAP`)
			end
			return table.concat(parts, "\n")
		end
		return {
			window = window,
			ticking = true,
			cleanup = function()
				connection:Disconnect()
			end,
			render = function()
				local daily = state().daily
				if typeof(daily) ~= "table" then
					return
				end
				local today = daily.day or 1
				local bonus = daily.bonus or 1
				local week = math.floor(((daily.streak or 1) - 1) / #Daily.days) + 1
				window.subtitle.Text = if daily.broken
					then "You missed a day, so the streak starts again at Day 1"
					elseif (daily.best or 0) == 0 then "Claim Day 1 to start your streak"
					else `Streak: {daily.streak} day{if daily.streak == 1 then "" else "s"} · best {daily.best}`
						.. (
							if bonus > 1
								then ` · week {week} bonus +{math.floor((bonus - 1) * 100 + 0.5)}%`
								else ""
						)
				for _, child in holder:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
				for i, reward in Daily.days do
					local done = i < today or (i == today and not daily.claimable)
					local ready = i == today and daily.claimable
					local tile = Ui.panel(
						holder,
						`Day{i}`,
						UDim2.fromOffset(if reward.big then 128 else 92, 196),
						UDim2.new()
					)
					tile.LayoutOrder = i
					tile.BackgroundTransparency = if done then 0.55 else 0.15
					local stroke = tile:FindFirstChildOfClass("UIStroke")
					if stroke and (ready or reward.big) then
						stroke.Color = Ui.color.haul
						stroke.Transparency = if ready then 0 else 0.4
						stroke.Thickness = if ready then 2.5 else 1.5
					end
					local dayLabel = Ui.label(
						tile,
						"Day",
						`DAY {i}`,
						Ui.FONT_HEAVY,
						16,
						if ready then Ui.color.haul else Ui.color.text,
						UDim2.new(1, 0, 0, 22),
						UDim2.fromOffset(0, 10)
					)
					dayLabel.TextXAlignment = Enum.TextXAlignment.Center
					local body = Ui.label(
						tile,
						"Reward",
						lines(reward, bonus),
						Ui.FONT_BOLD,
						if reward.big then 15 else 14,
						if done then Ui.color.muted else Ui.color.text,
						UDim2.new(1, -10, 1, -76),
						UDim2.fromOffset(5, 40)
					)
					body.TextXAlignment = Enum.TextXAlignment.Center
					body.TextYAlignment = Enum.TextYAlignment.Center
					body.TextWrapped = true
					local foot = Ui.label(
						tile,
						"State",
						if done then "✓ CLAIMED" elseif ready then "TODAY" else "",
						Ui.FONT_HEAVY,
						13,
						if done then Ui.color.safe else Ui.color.haul,
						UDim2.new(1, 0, 0, 18),
						UDim2.new(0, 0, 1, -28)
					)
					foot.TextXAlignment = Enum.TextXAlignment.Center
				end
				claim.Visible = daily.claimable == true
				footer.TextColor3 = if os.clock() < claimedUntil then Ui.color.haul else Ui.color.muted
				footer.Text = if os.clock() < claimedUntil
					then claimedText
					elseif daily.claimable then "Claim today's reward"
					else `Come back in {Format.duration(
						(daily.nextAt or 0) - workspace:GetServerTimeNow()
					)} for Day {today % #Daily.days + 1}`
			end,
		}
	end)
end

-- The stall hint: near a counter, a chip over it says which key opens its shop
-- (E, or Y on a controller). Phones get a SHOP button above BITE instead: the
-- world chip drew behind the Haul card (playtest 2026-10-07). Our own, because a
-- ProximityPrompt never showed for the custom fish character.
local hintGui: BillboardGui
local hintKey: TextLabel
local hintText: TextLabel
local hintSpot: Attachment
local shopButton: TextButton
local nearVendor: string? = nil

local counters: { [string]: Vector3 } = {}
for _, vendor in Shop.vendors do
	counters[vendor.id] = Layout.counterPosition(vendor.angle)
end

-- The LOG (owner, 2026-10-10: "a factor that pulls people back over and over"):
-- the Catch Log and your fish's catch track, today's bounties, the Catch of the Week
-- with the weekly leaderboards, and the Tide Clock's forecast.
local LOG_TABS = { "Catch Log", "Bounties", "Weekly", "Tides" }
local logBoards: { [string]: any }? = nil -- the last GetBoards answer
local logBoardsAt = -math.huge
local logBoard = "RareCatches"
local logScope = "global"

local function rewardText(reward: { [string]: any }): string
	local parts: { string } = {}
	if reward.coral then
		table.insert(parts, `{Ui.number(reward.coral)} coral`)
	end
	if reward.shells then
		table.insert(parts, `{reward.shells} shells`)
	end
	if reward.wraps then
		table.insert(parts, `{reward.wraps} Kelp Wrap{if reward.wraps == 1 then "" else "s"}`)
	end
	if reward.charms then
		for id, count in reward.charms do
			local charm = Shop.charmsById[id]
			table.insert(parts, `{count} {if charm then charm.name else id}`)
		end
	end
	if reward.map then
		local tier = Config.Treasure.byId[reward.map]
		table.insert(parts, `a {if tier then tier.name else reward.map} map`)
	end
	return table.concat(parts, ", ")
end

local function longClock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 86400 then
		return `{seconds // 86400}d {(seconds // 3600) % 24}h`
	end
	return string.format("%d:%02d:%02d", seconds // 3600, (seconds // 60) % 60, seconds % 60)
end

local function fetchBoards(force: boolean?)
	if not force and os.clock() - logBoardsAt < 30 then
		return
	end
	logBoardsAt = os.clock()
	task.spawn(function()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local getBoards = remotes and remotes:FindFirstChild("GetBoards")
		if getBoards == nil or not getBoards:IsA("RemoteFunction") then
			return
		end
		local ok, result = pcall(function()
			return (getBoards :: RemoteFunction):InvokeServer()
		end)
		if ok and typeof(result) == "table" then
			logBoards = result
			if current then
				current.render()
			end
		end
	end)
end

-- One Catch Log line: a prey species and a cell per rarity (its count, or a dash)
local function logLine(
	list: ScrollingFrame,
	order: number,
	preyId: string,
	counts: { [string]: number },
	done: boolean
)
	local prey = Config.Prey.byId[preyId]
	local frame = Instance.new("Frame")
	frame.Name = `Log{preyId}`
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, -8, 0, 40)
	frame.BackgroundColor3 = Ui.color.track
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	Ui.corner(frame, UDim.new(0, 8))
	local title = Ui.label(
		frame,
		"Name",
		if done then `{prey.name}  ✓` else prey.name,
		Ui.FONT_BOLD,
		16,
		if done then Ui.color.haul else Ui.color.text,
		UDim2.fromOffset(150, 40),
		UDim2.fromOffset(14, 0)
	)
	title.TextYAlignment = Enum.TextYAlignment.Center
	local columns = { "Normal" }
	for _, rarity in Config.Catch.rarities do
		table.insert(columns, rarity.id)
	end
	for i, id in columns do
		local count = counts[id] or 0
		local rarity = Config.Catch.byId[id]
		local cell = Instance.new("Frame")
		cell.Name = id
		cell.Size = UDim2.fromOffset(92, 28)
		cell.Position = UDim2.fromOffset(170 + (i - 1) * 100, 6)
		cell.BackgroundColor3 = if count > 0 and rarity then rarity.color else Ui.color.panel
		cell.BackgroundTransparency = if count > 0 then 0.55 else 0.4
		cell.BorderSizePixel = 0
		Ui.corner(cell, UDim.new(0, 6))
		local label = Ui.label(
			cell,
			"Count",
			if count > 0 then `×{Ui.number(count)}` else "—",
			Ui.FONT_SEMI,
			14,
			if count > 0 then Ui.color.text else Ui.color.muted,
			UDim2.fromScale(1, 1)
		)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		cell.Parent = frame
	end
	frame.Parent = list
end

local function catchLogRows(list: ScrollingFrame)
	local s = state()
	local species = Config.Species.byId[s.species or "Nibbler"]
	local speciesName = if species then species.name else "fish"
	local tracks = (s.catchTracks or {})[s.species or ""] or {}
	local owned: { [string]: boolean } = if typeof(s.shades) == "table" then s.shades else {}
	heading(
		list,
		1,
		`YOUR {string.upper(speciesName)}'S CATCH TRACK · catch rare fish as it to unlock its skins`
	)
	for i, rarity in Config.Catch.rarities do
		local count = tracks[rarity.id] or 0
		local skin = Config.Shades.byId[rarity.skin]
		local name = `{if skin then skin.name else rarity.name} {speciesName}`
		local have = owned[rarity.skin] == true
		local blurb = `{rarity.track} {rarity.name} catches as your {speciesName} · Haul ×{rarity.haul}`
		if rarity.tide then
			blurb ..= " · only in the Prism Tide"
		end
		row(
			list,
			1 + i,
			`Track{rarity.id}`,
			name,
			blurb,
			if have then "✓ UNLOCKED" else `{math.min(count, rarity.track)} / {rarity.track}`,
			nil,
			nil,
			rarity.color
		)
	end
	local log = s.catchLog or {}
	local rows = s.logRows or {}
	local found, total = 0, 0
	for _, prey in Config.Prey.list do
		local counts = log[prey.id] or {}
		total += 1 + #Config.Catch.rarities
		if (counts.Normal or 0) > 0 then
			found += 1
		end
		for _, rarity in Config.Catch.rarities do
			if (counts[rarity.id] or 0) > 0 then
				found += 1
			end
		end
	end
	heading(list, 10, `CATCH LOG · {found} / {total} found · a first catch pays, a full row pays more`)
	local header = Instance.new("Frame")
	header.Name = "LogHeader"
	header.LayoutOrder = 11
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, -8, 0, 20)
	local columns = { "Plain" }
	for _, rarity in Config.Catch.rarities do
		table.insert(columns, rarity.name)
	end
	for i, text in columns do
		local label = Ui.label(
			header,
			text,
			string.upper(text),
			Ui.FONT_BOLD,
			12,
			if i == 1 then Ui.color.muted else Config.Catch.rarities[i - 1].color,
			UDim2.fromOffset(92, 20),
			UDim2.fromOffset(170 + (i - 1) * 100, 0)
		)
		label.TextXAlignment = Enum.TextXAlignment.Center
	end
	header.Parent = list
	for i, prey in Config.Prey.list do
		logLine(list, 11 + i, prey.id, log[prey.id] or {}, rows[prey.id] == true)
	end
	heading(list, 40, "RARE FISH · spot their sparkle; the tides change the odds")
	for i, rarity in Config.Catch.rarities do
		local odds = `about 1 in {Ui.number(math.floor(1 / rarity.chance + 0.5))} fish`
		row(
			list,
			40 + i,
			`Rarity{rarity.id}`,
			rarity.name,
			`{if rarity.tide then "Only in the Prism Tide, " else ""}{odds} · Haul ×{rarity.haul} · coral and DNA ×{rarity.dna}`,
			nil,
			nil,
			nil,
			rarity.color
		)
	end
end

local function bountyRows(list: ScrollingFrame)
	local s = state()
	local bounties = s.bounties
	if typeof(bounties) ~= "table" then
		heading(list, 1, "BOUNTIES open once the tutorial is done")
		return
	end
	local nextAt = if typeof(bounties.nextAt) == "number" then bounties.nextAt else 0
	heading(list, 1, `TODAY'S BOUNTIES · new ones in {longClock(nextAt - workspace:GetServerTimeNow())}`)
	for i, entry in bounties.list or {} do
		local bounty = Config.Bounties.byId[entry.id]
		if bounty == nil then
			continue
		end
		local text = string.gsub(bounty.text, "{n}", tostring(bounty.count))
		row(
			list,
			1 + i,
			`Bounty{i}`,
			text,
			rewardText(bounty.reward),
			if entry.done then "✓ DONE" else `{entry.progress} / {bounty.count}`,
			nil,
			nil,
			if entry.done then Ui.color.safe else Ui.color.haul
		)
	end
	row(
		list,
		10,
		"Chest",
		"BOUNTY CHEST · finish all three",
		rewardText(Config.Bounties.chest),
		if bounties.chest then "✓ OPENED" else "",
		nil,
		nil,
		Ui.color.haul
	)
	heading(list, 20, "Bounties pay the moment they're done. Three new ones every day (UTC).")
end

local function weeklyRows(list: ScrollingFrame)
	local s = state()
	local unix = workspace:GetServerTimeNow()
	local featured, _, endsAt = Catch.weekly(unix)
	if featured then
		local rarity = Config.Catch.byId[featured.rarity]
		local prey = Config.Prey.byId[featured.prey]
		local skin = Config.Shades.byId[featured.skin]
		heading(list, 1, `CATCH OF THE WEEK · ends in {longClock(endsAt - unix)}`)
		tallRow(
			list,
			2,
			"Featured",
			`{string.upper(rarity.name)} {string.upper(prey.name)}`,
			`It swims {rarity.name} ×{Config.Catch.weekly.chance} as often all week. The first one you catch pays {Ui.number(
				featured.coral
			)} coral, {featured.shells} shells and the {if skin then skin.name else featured.skin} skin for the fish you catch it with.`,
			if s.weeklyFeatured then "✓ CAUGHT" else "NOT YET",
			nil,
			nil,
			rarity.color
		)
	end
	heading(list, 10, `LEADERBOARDS · reset every Monday 00:00 UTC · the top 100 earn a title`)
	local buttons = Instance.new("Frame")
	buttons.Name = "BoardButtons"
	buttons.LayoutOrder = 11
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, -8, 0, 40)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = buttons
	for i, board in Config.Leaderboards.boards do
		local button = Ui.button(
			buttons,
			board.id,
			string.upper(board.name),
			UDim2.fromOffset(150, 36),
			UDim2.new(),
			if board.id == logBoard then "primary" else "secondary"
		)
		button.LayoutOrder = i
		button.TextSize = 13
		button.Activated:Connect(function()
			logBoard = board.id
			if current then
				current.render()
			end
		end)
	end
	local scope = Ui.button(
		buttons,
		"Scope",
		if logScope == "global" then "ALL SERVERS" else "THIS SERVER",
		UDim2.fromOffset(130, 36),
		UDim2.new(),
		"gold"
	)
	scope.LayoutOrder = 10
	scope.TextSize = 13
	scope.Activated:Connect(function()
		logScope = if logScope == "global" then "server" else "global"
		if current then
			current.render()
		end
	end)
	buttons.Parent = list
	local board = Config.Leaderboards.byId[logBoard]
	local answer = logBoards
	local data = if answer and answer.boards then answer.boards[logBoard] else nil
	if data == nil then
		heading(list, 12, "Loading the boards...")
		return
	end
	local rows = if logScope == "global" then data.global else data.server
	local mine = data.mine or 0
	heading(
		list,
		12,
		`{board.blurb} · yours this week: {Ui.number(math.floor(mine))} {board.unit}{if logScope == "global"
				and not data.live
			then " · (live boards need the published game)"
			else ""}`
	)
	local me = Players.LocalPlayer.UserId
	for i, entry in rows or {} do
		if i > Config.Leaderboards.show then
			break
		end
		local medal = if i == 1 then Ui.color.haul elseif i <= 3 then Color3.fromRGB(200, 216, 224) else nil
		local frame = row(
			list,
			12 + i,
			`Rank{i}`,
			`#{i}  {entry.name}`,
			"",
			`{Ui.number(math.floor(entry.score))} {board.unit}`,
			nil,
			nil,
			if entry.userId == me then Ui.color.safe else medal
		)
		frame.Size = UDim2.new(1, -8, 0, 40)
		local title = frame:FindFirstChild("Title") :: TextLabel?
		if title then
			title.Position = UDim2.fromOffset(22, 9)
		end
	end
	if rows == nil or #rows == 0 then
		heading(list, 13, "No scores yet this week. Be the first!")
	end
end

local function tideRows(list: ScrollingFrame)
	local unix = workspace:GetServerTimeNow()
	local tide, _, endsAt = Tides.at(unix)
	heading(list, 1, "THE TIDE NOW")
	row(
		list,
		2,
		"Now",
		string.upper(tide.name),
		tide.blurb,
		`ends in {clockText(endsAt - unix)}`,
		nil,
		nil,
		tide.color
	)
	heading(list, 3, "FORECAST · the same on every server, every 20 minutes")
	for i, slot in Tides.forecast(unix, 9) do
		local next = Config.Tides.byId[slot.tide]
		local at = os.date("%H:%M", slot.startsAt)
		row(
			list,
			3 + i,
			`Forecast{i}`,
			if next.id == "Prism" then `★ {string.upper(next.name)} ★` else next.name,
			next.blurb,
			`in {longClock(slot.startsAt - unix)} · {at}`,
			nil,
			nil,
			next.color
		)
	end
	heading(
		list,
		20,
		"The Prism Tide rises at 03:00, 09:00, 15:00 and 21:00 UTC: the only time Prism fish swim."
	)
end

function MenuController.openLog(tab: string?)
	open(
		"Log",
		"Rare catches, bounties, the weekly race and the tides",
		Vector2.new(900, 540),
		function(window)
			local shown = tab or "Catch Log"
			local tabs: { [string]: TextButton } = {}
			local listHolder = Instance.new("Frame")
			listHolder.BackgroundTransparency = 1
			listHolder.Position = UDim2.fromOffset(0, 50)
			listHolder.Size = UDim2.new(1, 0, 1, -50)
			listHolder.Parent = window.content
			local list = Ui.list(listHolder)
			local menu: Menu
			for i, name in LOG_TABS do
				local button = Ui.button(
					window.content,
					name,
					string.upper(name),
					UDim2.fromOffset(150, 38),
					UDim2.fromOffset((i - 1) * 160, 0),
					"secondary"
				)
				tabs[name] = button
				button.Activated:Connect(function()
					shown = name
					if name == "Weekly" then
						fetchBoards(true)
					end
					menu.render()
				end)
			end
			menu = {
				window = window,
				ticking = true,
				render = function()
					for name, button in tabs do
						Ui.setButtonStyle(button, if name == shown then "primary" else "secondary")
					end
					if shown == "Weekly" then
						fetchBoards()
					end
					rerender(list, function()
						if shown == "Catch Log" then
							catchLogRows(list)
						elseif shown == "Bounties" then
							bountyRows(list)
						elseif shown == "Weekly" then
							weeklyRows(list)
						else
							tideRows(list)
						end
					end)
				end,
			}
			return menu
		end
	)
end

local function openNearShop()
	local vendorId = nearVendor
	if vendorId == nil then
		return
	end
	if currentShop == vendorId then
		MenuController.close()
	elseif vendorId == "__den" then
		local denIndex = state().denIndex
		MenuController.openDen(
			if typeof(denIndex) == "number" and denIndex > 0 then Layout.poolPosition(denIndex) else nil
		)
	else
		MenuController.openShop(vendorId, counters[vendorId])
	end
end

local function buildHint(playerGui: Instance)
	hintSpot = Instance.new("Attachment")
	hintSpot.Name = "StallHint"
	hintSpot.Parent = workspace.Terrain
	hintGui = Instance.new("BillboardGui")
	hintGui.Name = "StallHint"
	hintGui.Adornee = hintSpot
	hintGui.Size = UDim2.fromOffset(250, 46)
	hintGui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	hintGui.AlwaysOnTop = true
	hintGui.LightInfluence = 0
	hintGui.Active = true
	hintGui.Enabled = false
	hintGui.ResetOnSpawn = false
	local chip = Instance.new("TextButton")
	chip.Name = "Chip"
	chip.Text = ""
	chip.AutoButtonColor = false
	chip.Selectable = false
	chip.Size = UDim2.fromScale(1, 1)
	chip.BackgroundColor3 = Ui.color.panel
	chip.BackgroundTransparency = 0.15
	Ui.corner(chip, UDim.new(1, 0))
	Ui.stroke(chip, Ui.color.accent, 0.2, 1.5)
	chip.Parent = hintGui
	local key = Instance.new("Frame")
	key.Name = "Key"
	key.AnchorPoint = Vector2.new(0, 0.5)
	key.Position = UDim2.new(0, 6, 0.5, 0)
	key.Size = UDim2.fromOffset(34, 34)
	key.BackgroundColor3 = Ui.color.accent
	Ui.corner(key, UDim.new(1, 0))
	key.Parent = chip
	hintKey = Ui.label(key, "Text", "E", Ui.FONT_HEAVY, 18, Ui.color.panel, UDim2.fromScale(1, 1))
	hintKey.TextXAlignment = Enum.TextXAlignment.Center
	hintText = Ui.label(chip, "Text", "", Ui.FONT_BOLD, 16, Ui.color.text, UDim2.new(1, -54, 1, 0))
	hintText.Position = UDim2.fromOffset(48, 0)
	chip.Activated:Connect(openNearShop)
	hintGui.Parent = playerGui

	-- Phones: above BITE and HEAL, left of the depth gauge, clear of the Haul card
	-- (at -168 its bottom edge sat on the HEAL button)
	local buttonGui = Ui.screen("StallButton", playerGui, 9)
	shopButton =
		Ui.button(buttonGui, "Shop", "", UDim2.fromOffset(230, 44), UDim2.new(1, -96, 1, -204), "primary")
	shopButton.AnchorPoint = Vector2.new(1, 1)
	shopButton.Selectable = false
	shopButton.TextScaled = true
	shopButton.TextWrapped = false -- one line; long vendor names shrink a little
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = 16
	fit.Parent = shopButton
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = shopButton
	shopButton.Visible = false
	shopButton.Activated:Connect(openNearShop)
end

local function updateHint(root: BasePart?)
	local best: string? = nil
	local bestDistance = Shop.hintReach
	if root then
		for _, vendor in Shop.vendors do
			local distance = Layout.counterDistance(vendor.angle, root.Position)
			if distance <= bestDistance then
				best, bestDistance = vendor.id, distance
			end
		end
	end
	-- Your own den's pool: the den menu
	local denIndex = state().denIndex
	local denSpot: Vector3? = nil
	if best == nil and root and typeof(denIndex) == "number" and denIndex > 0 then
		local pool = Layout.poolPosition(denIndex)
		if (root.Position - pool).Magnitude <= Config.Dens.hintReach then
			best = "__den"
			denSpot = pool
		end
	end
	nearVendor = best
	local show = best ~= nil and current == nil
	local touch = Input.isTouch()
	hintGui.Enabled = show and not touch
	shopButton.Visible = show and touch and not MenuController.stallButtonHidden
	if show and best then
		local label = if best == "__den" then "YOUR DEN" else `SHOP · {Shop.vendorsById[best].name}`
		if touch then
			shopButton.Text = label
		else
			hintSpot.WorldPosition = denSpot or counters[best]
			hintKey.Text = if Input.isGamepad() then "Y" else "E"
			hintText.Text = label
		end
	end
end

function MenuController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.screen("Menus", playerGui, 10)
	buildHint(playerGui)
	ContextActionService:BindAction("ApexShop", function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin or nearVendor == nil then
			return Enum.ContextActionResult.Pass
		end
		openNearShop()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonY)
	ClientState.changed:connect(function()
		if current then
			current.render()
		end
	end)
	RunService.Heartbeat:Connect(function()
		local character = Players.LocalPlayer.Character
		local found = character and character:FindFirstChild("HumanoidRootPart")
		local root = if found and found:IsA("BasePart") then found else nil
		updateHint(root)
		local menu = current
		if menu == nil then
			return
		end
		if menu.ticking and os.clock() - lastTick >= 1 then
			lastTick = os.clock()
			menu.render()
		end
		if menu.anchor and root and (root.Position - menu.anchor).Magnitude > Shop.reach + 8 then
			MenuController.close()
		end
	end)
end

return MenuController
