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
local Reward = require(ReplicatedStorage.Shared.Reward)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local Tides = require(ReplicatedStorage.Shared.Tides)
local Timing = require(ReplicatedStorage.Shared.Timing)
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
	-- Set by BuildController: the den menu's BUILD button calls it
	startBuild = nil :: (() -> ())?,
	-- Set while Build mode is on: no stall hints
	building = false,
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
		local held = charms[charm.id] or 0
		-- (Robux Second Chances can take you past the trader's cap: no "2 / 1")
		local status = if held > (charm.max or 1) then `Have {held}` else `Have {held} / {charm.max or 1}`
		if charm.seconds then
			-- A timed charm waits in the item wheel (G) until it's used
			local left = (boosts[charm.id] or 0) - now
			if left > 0 then
				status ..= ` · on {clockText(left)}`
			end
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

-- Your den (Config/Dens): Build mode, the upgrade, the Coral Garden, the things to
-- buy (into the Build tray), the floor's stone and the glow color.
local function denSection(list: ScrollingFrame, order: number, text: string)
	local frame = Instance.new("Frame")
	frame.Name = `Section{order}`
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, -8, 0, 30)
	frame.BackgroundTransparency = 1
	local label = Ui.label(
		frame,
		"Text",
		string.upper(text),
		Ui.FONT_HEAVY,
		13,
		Ui.color.accent,
		UDim2.new(1, -16, 0, 18),
		UDim2.fromOffset(8, 10)
	)
	label.TextXAlignment = Enum.TextXAlignment.Left
	frame.Parent = list
end

local function denRecord(): any
	local s = state()
	return s.den or { level = 1, glow = "Teal", floor = "Flagstone", owned = {}, items = {}, placed = {} }
end

local function denRows(list: ScrollingFrame)
	local s = state()
	local den = denRecord()
	local Dens = Config.Dens
	local order = 0
	local function next(): number
		order += 1
		return order
	end
	local placed = if typeof(den.placed) == "table" then #den.placed else 0
	local capacity = if typeof(s.denCapacity) == "number" then s.denCapacity else 15
	-- Build mode
	local _, build = row(
		list,
		next(),
		"Build",
		"Build your den",
		"Place, move and turn your things on any floor, wall or ceiling",
		`{placed} / {capacity} placed`,
		"BUILD",
		"gold",
		Ui.color.haul
	)
	if build then
		build.Activated:Connect(function()
			local start = MenuController.startBuild
			MenuController.close()
			if start then
				start()
			end
		end)
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
			`holds {upgrade.capacity}`,
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
		row(list, next(), "Upgrade", `A {level.name}`, level.blurb, "Fully dug", nil, nil, Ui.color.haul)
	end
	-- The Coral Garden: what it grows here, and the Deep Garden pass
	local passes = s.passes or {}
	local garden = s.garden
	if typeof(garden) == "table" then
		local nextRates = if upgrade
			then Garden.rates(
				upgrade.level,
				passes.DeepGarden == true,
				if state().premium == true then Config.Monetization.tuning.premium.gardenHours else 0
			)
			else nil
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
	-- The Den Expansion pass: more things at any level
	local expansion = Config.Monetization.passesByKey.DenExpansion
	if not passes.DenExpansion and expansion and Store.listed(expansion.id) then
		local _, button = row(
			list,
			next(),
			"Expansion",
			"Den Expansion",
			`Place {Dens.expansionCapacity} more things in your den, at any level`,
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
	-- Things: bought into the Build tray (the furniture sets come after)
	denSection(list, next(), "Things · they go into your Build tray")
	local items = if typeof(den.items) == "table" then den.items else {}
	local function itemRow(item: typeof(Dens.items[1]))
		local owned = items[item.id] or 0
		local where = table.concat(item.kinds, " / ")
		local _, button = row(
			list,
			next(),
			`Item{item.id}`,
			item.name,
			`{item.blurb} · {where}`,
			if owned > 0 then `{owned} owned` else nil,
			coralText(item.price),
			priceStyle(item.price),
			item.color
		)
		if button then
			button.Activated:Connect(function()
				ClientState.request("DenBuy", item.id)
			end)
		end
	end
	for _, item in Dens.items do
		if item.set == nil then
			itemRow(item)
		end
	end
	-- Furniture sets (owner, 2026-10-13): an achievement opens each, then its pieces
	-- are bought one at a time, to mix with any other set's
	local progress = if typeof(s.achievements) == "table" then s.achievements else {}
	for _, set in Dens.sets do
		local achievement = Config.Achievements.bySet[set.id]
		local tier = Config.Tiers.byId[set.tier]
		local accent = if tier then tier.color else Ui.color.haul
		local pieces: { typeof(Dens.items[1]) } = {}
		for _, item in Dens.items do
			if item.set == set.id then
				table.insert(pieces, item)
			end
		end
		local done = achievement == nil or (progress[achievement.id] or 0) >= achievement.goal
		denSection(
			list,
			next(),
			if done and Dens.layouts[set.id]
				then `{set.name} set · {set.biome} · L in Build mode lays out the pieces you have`
				else `{set.name} set · {set.biome}`
		)
		if done then
			for _, item in pieces do
				itemRow(item)
			end
		elseif achievement then
			local names = {}
			for _, item in pieces do
				table.insert(names, item.name)
			end
			local frame = row(
				list,
				next(),
				`Set{set.id}`,
				`Locked · {achievement.name}`,
				`{achievement.blurb} to open it. {#pieces} pieces, each bought on its own: {table.concat(
					names,
					", "
				)}`,
				`{Ui.number(progress[achievement.id] or 0)} / {Ui.number(achievement.goal)}`,
				nil,
				nil,
				accent
			)
			-- (the piece list runs to two lines: playtest 2026-10-13, it ran off the edge;
			-- two lines still cut six pieces at the fourth, PC playtest 2026-10-14 N1, so a
			-- locked row, which has no button, gives the list the button's width and a
			-- third line, with the progress at the right edge)
			frame.Size = UDim2.new(1, -8, 0, 98)
			local blurb = frame:FindFirstChild("Blurb") :: TextLabel?
			if blurb then
				blurb.TextWrapped = true
				blurb.TextYAlignment = Enum.TextYAlignment.Top
				blurb.Size = UDim2.new(1, -190, 0, 58)
			end
			local status = frame:FindFirstChild("Status") :: TextLabel?
			if status then
				status.Position = UDim2.new(1, -150, 0.5, -10)
			end
		end
	end
	-- The floor's stone
	denSection(list, next(), "Floors · the stone of every deck")
	local owned = if typeof(den.owned) == "table" then den.owned else {}
	for _, style in Dens.floors do
		local has = style.price == 0 or owned[`Floor:{style.id}`] == true
		local laid = den.floor == style.id
		local _, button = row(
			list,
			next(),
			`Floor{style.id}`,
			style.name,
			style.blurb,
			nil,
			if laid then "LAID" elseif has then "LAY" else coralText(style.price),
			if laid then "disabled" elseif has then "secondary" else priceStyle(style.price),
			style.colors[1]
		)
		if button and not laid then
			button.Activated:Connect(function()
				ClientState.request("DenFloor", style.id)
			end)
		end
	end
	-- The glow color
	denSection(list, next(), "Glow · lamps, banners, trims and seams")
	for _, glow in Dens.glows do
		local has = glow.price == 0 or owned[`Glow:{glow.id}`] == true
		local worn = den.glow == glow.id
		local _, button = row(
			list,
			next(),
			`Glow{glow.id}`,
			`{glow.name} glow`,
			"Your lamps, banners and trophy trims",
			nil,
			if worn then "LIT" elseif has then "SET" else coralText(glow.price),
			if worn then "disabled" elseif has then "secondary" else priceStyle(glow.price),
			glow.color
		)
		if button and not worn then
			button.Activated:Connect(function()
				ClientState.request("DenColor", glow.id)
			end)
		end
	end
end

local function denSubtitle(): string
	local s = state()
	local den = denRecord()
	local level = Config.Dens.levels[den.level] or Config.Dens.levels[1]
	local placed = if typeof(den.placed) == "table" then #den.placed else 0
	local capacity = if typeof(s.denCapacity) == "number" then s.denCapacity else level.capacity
	return `{level.name} · level {level.level} · {placed}/{capacity} things   ·   Visitors look, only you change it   ·   {Ui.number(
		coral()
	)} coral`
end

function MenuController.openDen(anchor: Vector3?)
	open("YOUR DEN", denSubtitle(), Vector2.new(720, 520), function(window)
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
		-- (catch-track skins first, then the weeks', then trophies and treasure)
		for pass = 1, 3 do
			for _, shade in Config.Shades.list do
				local group = if shade.catch then 1 elseif shade.week then 2 else 3
				if shade.species == nil and group == pass and (shade.week == nil or owned[shade.id]) then
					table.insert(shown, shade)
				end
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
		-- Every fish has its own variant (Config/Exotics): this fish's first, then
		-- the others', each named for the fish it reshapes
		local current = s.species
		local ordered = table.clone(Config.Exotics.variants)
		table.sort(ordered, function(a, b)
			local aMine, bMine = a.species == current, b.species == current
			if aMine ~= bMine then
				return aMine
			end
			return a.chance < b.chance
		end)
		for _, variant in ordered do
			local has = (s.variants or {})[variant.id] == true
			local species = Config.Species.byId[variant.species]
			add(
				"variant",
				variant.id,
				variant.name,
				"Abyssal",
				variant.chance,
				has,
				equipped.variant == variant.id,
				if species then `{species.name} only` else nil
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
						-- Two lines: the Weathered and Captain's odds ran past one and were
						-- cut at "..." (PC playtest 2026-10-14, D3b)
						frame.Size = UDim2.new(1, -8, 0, 74)
						frame.BackgroundTransparency = 0.6
						local blurb = frame:FindFirstChild("Blurb") :: TextLabel?
						if blurb then
							blurb.Size = UDim2.new(1, -40, 0, 36)
							blurb.TextWrapped = true
							blurb.TextYAlignment = Enum.TextYAlignment.Top
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
						-- Pods: here too, so a controller can reach them (POD is a HUD button)
						local pod = if typeof(s.pod) == "table" then s.pod else nil
						local podCount = if pod and typeof(pod.members) == "table" then #pod.members else 0
						local _, podButton = row(
							list,
							next(),
							"Pod",
							"Pod",
							"Team up with up to 2 friends: no eating each other, slipstream, shared kills",
							if pod and pod.invite
								then "Invite waiting!"
								elseif podCount > 0 then `{podCount} in your pod`
								else nil,
							"OPEN",
							if pod and pod.invite then "gold" else "secondary",
							Ui.color.safe
						)
						if podButton then
							podButton.Activated:Connect(MenuController.openPod)
						end
						-- Free perks
						heading(list, next(), "FREE PERKS")
						local premium = s.premium == true
						local premiumRow, premiumButton = tallRow(
							list,
							next(),
							"Premium",
							"Roblox Premium",
							`Premium members earn +{math.floor((tune.premiumCoral - 1) * 100 + 0.5)}% coral from everything, ×{tune.premium.gifts} playtime gifts, {tune.premium.spins} free wheel spin a day, +{tune.premium.gardenHours} h of Coral Garden and a ◆ by their name.`,
							if premium then "Active" else nil,
							if premium then "ACTIVE" else "GET PREMIUM",
							if premium then "disabled" else "secondary",
							Ui.color.safe
						)
						-- Its blurb runs to three lines: the tall row's two cut it off at
						-- "Coral Garden and a" (PC playtest 2026-10-14, C1)
						premiumRow.Size = UDim2.new(1, -8, 0, 96)
						local premiumBlurb = premiumRow:FindFirstChild("Blurb") :: TextLabel?
						if premiumBlurb then
							premiumBlurb.Size = UDim2.new(1, -320, 0, 56)
						end
						if premiumButton and not premium then
							premiumButton.Activated:Connect(Store.buyPremium)
						end
						local _, codesButton = row(
							list,
							next(),
							"Codes",
							"Codes",
							"Got a code from the group or the game page? Redeem it here.",
							nil,
							"REDEEM",
							"secondary",
							Ui.color.haul
						)
						if codesButton then
							codesButton.Activated:Connect(MenuController.openCodes)
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

-- Pods (Config/Pvp `pods`, PodService): who's in yours, an invite waiting, and
-- everyone else in the server to invite. Podmates can't eat each other, swim faster
-- in each other's slipstream and share the Haul from player kills.
function MenuController.openPod()
	local tune = Config.Pvp.pods
	open(
		"Pod",
		`Swim with up to {tune.size - 1} friends · no eating each other · slipstream · shared kills`,
		Vector2.new(640, 500),
		function(window)
			local list = Ui.list(window.content, 6)
			return {
				window = window,
				ticking = true,
				render = function()
					local s = state()
					local pod = if typeof(s.pod) == "table" then s.pod else { id = 0, members = {} }
					local members = if typeof(pod.members) == "table" then pod.members else {}
					local inPod: { [number]: boolean } = {}
					for _, member in members do
						inPod[member.id] = true
					end
					local order = 0
					local function next(): number
						order += 1
						return order
					end
					rerender(list, function()
						local offer = pod.invite
						if typeof(offer) == "table" then
							local left = math.max(0, math.floor((offer.expires or 0) - Timing.clock()))
							heading(list, next(), "INVITE")
							local _, yes = row(
								list,
								next(),
								"Accept",
								`{offer.from} wants you in their pod`,
								`Runs out in {left} s`,
								nil,
								"JOIN",
								"gold",
								Ui.color.safe
							)
							if yes then
								yes.Activated:Connect(function()
									ClientState.request("PodAccept")
								end)
							end
							local _, no =
								row(list, next(), "Decline", "Not now", "", nil, "DECLINE", "secondary")
							if no then
								no.Activated:Connect(function()
									ClientState.request("PodDecline")
								end)
							end
						end
						heading(
							list,
							next(),
							if #members > 0 then `YOUR POD ({#members}/{tune.size})` else "YOUR POD"
						)
						if #members == 0 then
							row(
								list,
								next(),
								"Alone",
								"You're swimming alone",
								"Invite someone below",
								nil,
								nil,
								nil
							)
						end
						for _, member in members do
							local me = member.id == Players.LocalPlayer.UserId
							row(
								list,
								next(),
								`Member{member.id}`,
								if me then `{member.name} (you)` else member.name,
								if me then "" else "Podmate: no eating each other",
								nil,
								nil,
								nil,
								Ui.color.safe
							)
						end
						if #members > 0 then
							local _, leave =
								row(list, next(), "Leave", "Leave the pod", "", nil, "LEAVE", "danger")
							if leave then
								leave.Activated:Connect(function()
									ClientState.request("PodLeave")
								end)
							end
						end
						heading(list, next(), "IN THIS SERVER")
						local full = #members >= tune.size
						local any = false
						for _, player in Players:GetPlayers() do
							if player == Players.LocalPlayer or inPod[player.UserId] then
								continue
							end
							any = true
							local theirs = player:GetAttribute("Pod")
							local busy = typeof(theirs) == "number" and theirs ~= 0
							local _, ask = row(
								list,
								next(),
								`Player{player.UserId}`,
								player.DisplayName,
								if busy then "In another pod" else "",
								nil,
								if busy or full then "—" else "INVITE",
								if busy or full then "disabled" else "primary"
							)
							if ask and not busy and not full then
								ask.Activated:Connect(function()
									ClientState.request("PodInvite", player.UserId)
								end)
							end
						end
						if not any then
							row(list, next(), "Nobody", "Nobody else is here yet", "", nil, nil, nil)
						end
					end)
				end,
			}
		end
	)
end

-- Redeem codes (Config/Codes): a box, REDEEM and the server's answer. Its own
-- window, so the box keeps its text (the Shop redraws every second).
function MenuController.openCodes()
	open("Codes", "Each code works once", Vector2.new(460, 230), function(window)
		local box = Instance.new("TextBox")
		box.Name = "Code"
		box.PlaceholderText = "Type a code"
		box.Text = ""
		box.ClearTextOnFocus = false
		box.FontFace = Ui.FONT_BOLD
		box.TextSize = 20
		box.TextColor3 = Ui.color.text
		box.PlaceholderColor3 = Ui.color.muted
		box.BackgroundColor3 = Ui.color.track
		box.BackgroundTransparency = 0.2
		box.BorderSizePixel = 0
		box.Size = UDim2.new(1, -150, 0, 46)
		box.Position = UDim2.fromOffset(0, 10)
		Ui.corner(box, UDim.new(0, 10))
		Ui.stroke(box, Ui.color.haul, 0.5, 1)
		box.Parent = window.content
		local answer = Ui.label(
			window.content,
			"Answer",
			"",
			Ui.FONT_SEMI,
			15,
			Ui.color.muted,
			UDim2.new(1, 0, 0, 44),
			UDim2.fromOffset(0, 66)
		)
		answer.TextWrapped = true
		answer.TextXAlignment = Enum.TextXAlignment.Left
		answer.TextYAlignment = Enum.TextYAlignment.Top
		local redeem = Ui.button(
			window.content,
			"Redeem",
			"REDEEM",
			UDim2.fromOffset(136, 46),
			UDim2.new(1, -136, 0, 10),
			"gold"
		)
		local busy = false
		local function send()
			if busy or box.Text == "" then
				return
			end
			busy = true
			answer.Text = "Checking…"
			answer.TextColor3 = Ui.color.muted
			local remotes = ReplicatedStorage:WaitForChild("Remotes")
			local remote = remotes:WaitForChild("RedeemCode") :: RemoteFunction
			local ok, paid, line = pcall(function()
				return remote:InvokeServer(box.Text)
			end)
			busy = false
			if not answer.Parent then
				return
			end
			if ok and typeof(line) == "string" then
				answer.Text = line
				answer.TextColor3 = if paid then Ui.color.safe else Ui.color.danger
				Sfx.play(if paid then "Bank" else "TooBig", { volume = 0.5 })
			else
				answer.Text = "Couldn't reach the server · try again"
				answer.TextColor3 = Ui.color.danger
			end
		end
		redeem.Activated:Connect(send)
		box.FocusLost:Connect(function(enter)
			if enter then
				send()
			end
		end)
		if Input.isTouch() then
			-- Phones: at the top, so the box stays above the on-screen keyboard (in
			-- the middle the keyboard hid it: PC playtest 2026-10-14, X2)
			window.frame.AnchorPoint = Vector2.new(0.5, 0)
			window.frame.Position = UDim2.new(0.5, 0, 0, 6)
		end
		return { window = window, render = function() end }
	end)
end

-- The daily login streak (DAILY on the HUD; it opens by itself on joining when a
-- reward is waiting): seven days that build to a big Day 7, then loop with a bonus
-- for each finished week.
function MenuController.openDaily()
	local Daily = Config.Daily
	local Playtime = Config.Playtime
	local premiumTune = Config.Monetization.tuning.premium
	open("Daily Reward", "", Vector2.new(780, 540), function(window)
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
		-- Playtime gifts (owner, 2026-10-12): a ladder for minutes played today, under
		-- the streak. The DAILY button counts down to the next one.
		local giftHeader = Ui.label(
			window.content,
			"GiftHeader",
			"PLAYTIME GIFTS",
			Ui.FONT_HEAVY,
			15,
			Ui.color.haul,
			UDim2.new(1, 0, 0, 18),
			UDim2.fromOffset(0, 284)
		)
		giftHeader.TextXAlignment = Enum.TextXAlignment.Center
		local gifts = Instance.new("Frame")
		gifts.Name = "Gifts"
		gifts.BackgroundTransparency = 1
		gifts.Position = UDim2.fromOffset(0, 306)
		gifts.Size = UDim2.new(1, 0, 0, 92)
		gifts.Parent = window.content
		local giftLayout = Instance.new("UIListLayout")
		giftLayout.FillDirection = Enum.FillDirection.Horizontal
		giftLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		giftLayout.Padding = UDim.new(0, 6)
		giftLayout.SortOrder = Enum.SortOrder.LayoutOrder
		giftLayout.Parent = gifts
		local claimGift = Ui.button(
			window.content,
			"ClaimGift",
			"CLAIM GIFT",
			UDim2.fromOffset(220, 38),
			UDim2.new(0.5, -110, 0, 402),
			"gold"
		)
		claimGift.FontFace = Ui.FONT_HEAVY
		claimGift.Activated:Connect(function()
			ClientState.request("ClaimGift")
		end)
		-- Premium's perks, for those without it (never a wall: the gifts come anyway)
		local premiumButton = Ui.button(
			window.content,
			"Premium",
			"GET PREMIUM",
			UDim2.fromOffset(150, 38),
			UDim2.new(0.5, 130, 0, 402),
			"secondary"
		)
		premiumButton.TextSize = 13
		premiumButton.Activated:Connect(Store.buyPremium)
		local premiumNote = Ui.label(
			window.content,
			"PremiumNote",
			`Premium: ×{premiumTune.gifts} gifts · {premiumTune.spins} free spin a day · +{premiumTune.gardenHours} h garden`,
			Ui.FONT_SEMI,
			12,
			Ui.color.muted,
			UDim2.fromOffset(250, 38),
			UDim2.new(0.5, -380, 0, 402)
		)
		premiumNote.TextXAlignment = Enum.TextXAlignment.Right
		premiumNote.TextWrapped = true
		-- What was claimed shows in the footer for a few seconds
		local claimedText, claimedUntil = "", 0
		local claimed = (ReplicatedStorage:WaitForChild("Remotes") :: Instance):WaitForChild(
				"DailyClaimed"
			) :: RemoteEvent
		local connection = claimed.OnClientEvent:Connect(function(summary: { [string]: any })
			local got = if typeof(summary.got) == "table" then table.concat(summary.got, " · ") else ""
			claimedText = if summary.kind == "gift"
				then `{summary.minutes}-minute gift claimed: {got}`
				else `Day {summary.streak} claimed: {got}`
			claimedUntil = os.clock() + 4
			Sfx.play("Bank", { volume = 0.6 })
			MenuController.rerenderCurrent()
		end)
		local function renderGifts()
			local pt = state().playtime
			for _, child in gifts:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			if typeof(pt) ~= "table" then
				claimGift.Visible = false
				premiumButton.Visible = false
				premiumNote.Visible = false
				return
			end
			local now = workspace:GetServerTimeNow()
			local claimedCount = pt.claimed or 0
			local unlockedCount = pt.unlocked or 0
			local bonus = pt.bonus or 1
			local premium = state().premium == true
			giftHeader.Text = if pt.claimable
				then "PLAYTIME GIFTS · A GIFT IS READY"
				elseif typeof(pt.nextAt) == "number" then `PLAYTIME GIFTS · NEXT IN {clockText(
					pt.nextAt - now
				)}`
				else "PLAYTIME GIFTS · ALL CLAIMED TODAY"
			for i, gift in Playtime.gifts do
				local done = i <= claimedCount
				local ready = not done and i <= unlockedCount
				local nextOne = not done and not ready and i == unlockedCount + 1
				local tile = Ui.panel(
					gifts,
					`Gift{i}`,
					UDim2.fromOffset(if gift.big then 108 else 92, 92),
					UDim2.new()
				)
				tile.LayoutOrder = i
				tile.BackgroundTransparency = if done then 0.55 else 0.15
				local stroke = tile:FindFirstChildOfClass("UIStroke")
				if stroke and (ready or gift.big) then
					stroke.Color = Ui.color.haul
					stroke.Transparency = if ready then 0 else 0.4
					stroke.Thickness = if ready then 2.5 else 1.5
				end
				local when = Ui.label(
					tile,
					"When",
					`{gift.minutes} MIN`,
					Ui.FONT_HEAVY,
					13,
					if ready then Ui.color.haul else Ui.color.text,
					UDim2.new(1, 0, 0, 16),
					UDim2.fromOffset(0, 6)
				)
				when.TextXAlignment = Enum.TextXAlignment.Center
				local body = Ui.label(
					tile,
					"Reward",
					table.concat(Reward.lines(gift, bonus), "\n"),
					Ui.FONT_BOLD,
					11,
					if done then Ui.color.muted else Ui.color.text,
					UDim2.new(1, -6, 0, 40),
					UDim2.fromOffset(3, 24)
				)
				body.TextXAlignment = Enum.TextXAlignment.Center
				body.TextYAlignment = Enum.TextYAlignment.Center
				body.TextWrapped = true
				local foot = Ui.label(
					tile,
					"State",
					if done
						then "✓"
						elseif ready then "READY"
						elseif nextOne and typeof(pt.nextAt) == "number" then clockText(pt.nextAt - now)
						else "",
					Ui.FONT_HEAVY,
					12,
					if done then Ui.color.safe else Ui.color.haul,
					UDim2.new(1, 0, 0, 16),
					UDim2.new(0, 0, 1, -20)
				)
				foot.TextXAlignment = Enum.TextXAlignment.Center
			end
			claimGift.Visible = pt.claimable == true
			premiumButton.Visible = not premium
			premiumNote.Visible = not premium
			premiumNote.Text = if premium
				then ""
				else `Premium: ×{premiumTune.gifts} gifts · {premiumTune.spins} free spin a day · +{premiumTune.gardenHours} h garden`
		end
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
			if reward.spins then
				table.insert(parts, `{reward.spins} WHEEL SPIN{if reward.spins == 1 then "" else "S"}`)
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
				renderGifts()
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

-- The Tide Pass (owner, 2026-10-12; Config/Pass): the season's XP bar, then every
-- tier as a column with its free reward over its Deep Pass reward, scrolled
-- sideways; CLAIM ALL takes every unlocked reward, DEEP PASS buys this season's paid
-- row (a developer product).
local passScrolled = false
function MenuController.openPass()
	local Pass = Config.Pass
	local product = Config.Monetization.productsByKey[Pass.product]
	open("Tide Pass", "", Vector2.new(920, 540), function(window)
		local content = window.content
		local seasonLabel = Ui.label(
			content,
			"Season",
			"",
			Ui.FONT_HEAVY,
			18,
			Ui.color.text,
			UDim2.new(1, -310, 0, 24),
			UDim2.fromOffset(0, 0)
		)
		local _, fill =
			Ui.bar(content, "Xp", UDim2.new(1, -310, 0, 10), UDim2.fromOffset(0, 30), Ui.color.haul)
		local xpLabel = Ui.label(
			content,
			"XpText",
			"",
			Ui.FONT_SEMI,
			13,
			Ui.color.muted,
			UDim2.new(1, -310, 0, 16),
			UDim2.fromOffset(0, 44)
		)
		local claimAll = Ui.button(
			content,
			"ClaimAll",
			"CLAIM ALL",
			UDim2.fromOffset(150, 40),
			UDim2.new(1, -300, 0, 2),
			"gold"
		)
		claimAll.FontFace = Ui.FONT_HEAVY
		claimAll.Activated:Connect(function()
			ClientState.request("ClaimPass")
		end)
		local deep = Ui.button(
			content,
			"Deep",
			if product then `DEEP PASS · {Store.price(product.price)}` else "DEEP PASS",
			UDim2.fromOffset(140, 40),
			UDim2.new(1, -140, 0, 2),
			if product and product.id ~= 0 then "gold" else "disabled"
		)
		deep.TextSize = 13
		deep.Activated:Connect(function()
			Store.buyProduct(Pass.product)
		end)
		local rowFree = Ui.label(
			content,
			"RowFree",
			"FREE",
			Ui.FONT_HEAVY,
			11,
			Ui.color.muted,
			UDim2.fromOffset(36, 16),
			UDim2.fromOffset(0, 102)
		)
		rowFree.Rotation = -90
		local rowDeep = Ui.label(
			content,
			"RowDeep",
			"DEEP",
			Ui.FONT_HEAVY,
			11,
			Ui.color.haul,
			UDim2.fromOffset(36, 16),
			UDim2.fromOffset(0, 290)
		)
		rowDeep.Rotation = -90
		local strip = Instance.new("ScrollingFrame")
		strip.Name = "Tiers"
		strip.BackgroundTransparency = 1
		strip.BorderSizePixel = 0
		strip.Position = UDim2.fromOffset(28, 70)
		strip.Size = UDim2.new(1, -28, 1, -70)
		strip.ScrollingDirection = Enum.ScrollingDirection.X
		strip.ScrollBarThickness = 6
		strip.ScrollBarImageColor3 = Ui.color.stroke
		strip.ElasticBehavior = Enum.ElasticBehavior.Never
		strip.Selectable = false
		strip.Parent = content
		local COLUMN, GAP = 96, 8
		-- What was claimed shows in the subtitle for a few seconds
		local claimedText, claimedUntil = "", 0
		local claimedRemote = (ReplicatedStorage:WaitForChild("Remotes") :: Instance):WaitForChild(
			"PassClaimed"
		) :: RemoteEvent
		local connection = claimedRemote.OnClientEvent:Connect(function(summary: { [string]: any })
			local got = if typeof(summary.got) == "table" then table.concat(summary.got, " · ") else ""
			claimedText = `Claimed: {got}`
			claimedUntil = os.clock() + 5
			Sfx.play("Bank", { volume = 0.6 })
			MenuController.rerenderCurrent()
		end)
		local function tile(
			parent: Instance,
			name: string,
			y: number,
			reward: Reward.Reward?,
			claimed: boolean,
			unlocked: boolean,
			locked: boolean,
			paidRow: boolean
		)
			local frame = Ui.panel(parent, name, UDim2.fromOffset(COLUMN, 165), UDim2.fromOffset(0, y))
			frame.BackgroundTransparency = if claimed then 0.6 elseif locked then 0.35 else 0.12
			local stroke = frame:FindFirstChildOfClass("UIStroke")
			if stroke then
				if unlocked and not claimed and not locked then
					stroke.Color = Ui.color.haul
					stroke.Transparency = 0
					stroke.Thickness = 2.5
				elseif paidRow then
					stroke.Color = Ui.color.haul
					stroke.Transparency = 0.6
				end
			end
			local body = Ui.label(
				frame,
				"Reward",
				if reward then table.concat(Reward.lines(reward), "\n") else "—",
				Ui.FONT_BOLD,
				12,
				if claimed or locked then Ui.color.muted else Ui.color.text,
				UDim2.new(1, -8, 1, -40),
				UDim2.fromOffset(4, 10)
			)
			body.TextXAlignment = Enum.TextXAlignment.Center
			body.TextYAlignment = Enum.TextYAlignment.Center
			body.TextWrapped = true
			local foot = Ui.label(
				frame,
				"State",
				if claimed
					then "✓ CLAIMED"
					elseif locked then "DEEP PASS"
					elseif unlocked then "READY"
					else "",
				Ui.FONT_HEAVY,
				11,
				if claimed then Ui.color.safe elseif locked then Ui.color.muted else Ui.color.haul,
				UDim2.new(1, 0, 0, 16),
				UDim2.new(0, 0, 1, -22)
			)
			foot.TextXAlignment = Enum.TextXAlignment.Center
			return frame
		end
		return {
			window = window,
			ticking = true,
			cleanup = function()
				connection:Disconnect()
			end,
			render = function()
				local pass = state().pass
				if typeof(pass) ~= "table" then
					return
				end
				local def = Pass.seasons[((pass.season or 1) - 1) % #Pass.seasons + 1]
				local tier = pass.tier or 0
				local tiers = pass.tiers or #def.tiers
				local per = pass.per or Pass.xpPerTier
				local xp = pass.xp or 0
				local into = xp - tier * per
				local waiting = pass.waiting or 0
				local left = (pass.endsAt or 0) - workspace:GetServerTimeNow()
				seasonLabel.Text = `SEASON {pass.season or 1} · {string.upper(def.name)}`
				window.subtitle.Text = if os.clock() < claimedUntil
					then claimedText
					else `{def.blurb} · ends in {Format.duration(left)}`
				window.subtitle.TextColor3 = if os.clock() < claimedUntil
					then Ui.color.haul
					else Ui.color.muted
				fill.Size = UDim2.fromScale(math.clamp(into / per, 0, 1), 1)
				xpLabel.Text = if tier < tiers
					then `TIER {tier} of {tiers} · {Ui.number(into)} / {Ui.number(per)} XP to the next`
					else `EVERY TIER DONE · OVERTIDE: {Ui.number(into)} / {Ui.number(per)} XP to {Ui.number(
						Pass.overtide.coral or 0
					)} coral`
				claimAll.Text = if waiting > 0 then `CLAIM ALL ({waiting})` else "CLAIM ALL"
				Ui.setButtonStyle(claimAll, if waiting > 0 then "gold" else "disabled")
				deep.Visible = pass.paid ~= true and product ~= nil and Store.listed(product.id)
				rowDeep.Text = if pass.paid then "DEEP ✓" else "DEEP"
				for _, child in strip:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
				strip.CanvasSize = UDim2.fromOffset(tiers * (COLUMN + GAP), 0)
				for i = 1, tiers do
					local entry = def.tiers[i]
					local column = Instance.new("Frame")
					column.Name = `Tier{i}`
					column.BackgroundTransparency = 1
					column.Position = UDim2.fromOffset((i - 1) * (COLUMN + GAP), 0)
					column.Size = UDim2.fromOffset(COLUMN, 358)
					column.Parent = strip
					local number = Ui.label(
						column,
						"Number",
						`TIER {i}`,
						Ui.FONT_HEAVY,
						13,
						if i == tier + 1
							then Ui.color.haul
							elseif i <= tier then Ui.color.text
							else Ui.color.muted,
						UDim2.new(1, 0, 0, 18),
						UDim2.fromOffset(0, 0)
					)
					number.TextXAlignment = Enum.TextXAlignment.Center
					local unlocked = i <= tier
					tile(column, "Free", 22, entry.free, i <= (pass.claimedFree or 0), unlocked, false, false)
					tile(
						column,
						"Paid",
						195,
						entry.paid,
						pass.paid == true and i <= (pass.claimedPaid or 0),
						unlocked and pass.paid == true,
						pass.paid ~= true,
						true
					)
				end
				-- Open on the tier being worked toward
				if not passScrolled then
					passScrolled = true
					strip.CanvasPosition = Vector2.new(math.max(0, (tier - 1) * (COLUMN + GAP)), 0)
				end
			end,
		}
	end)
	passScrolled = false
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
	if reward.spins then
		table.insert(parts, `{reward.spins} wheel spin{if reward.spins == 1 then "" else "s"}`)
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

-- One Catch Log line: a prey species, its biggest ever, and a cell per rarity (how
-- many, and the biggest of that rarity; a dash until caught)
local function logLine(
	list: ScrollingFrame,
	order: number,
	preyId: string,
	counts: { [string]: number },
	best: { [string]: number },
	done: boolean
)
	local prey = Config.Prey.byId[preyId]
	local frame = Instance.new("Frame")
	frame.Name = `Log{preyId}`
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, -8, 0, 48)
	frame.BackgroundColor3 = Ui.color.track
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	Ui.corner(frame, UDim.new(0, 8))
	local biggest = 0
	for _, kg in best do
		biggest = math.max(biggest, kg)
	end
	Ui.label(
		frame,
		"Name",
		if done then `{prey.name}  ✓` else prey.name,
		Ui.FONT_BOLD,
		16,
		if done then Ui.color.haul else Ui.color.text,
		UDim2.fromOffset(150, 20),
		UDim2.fromOffset(14, 5)
	)
	Ui.label(
		frame,
		"Biggest",
		if biggest > 0 then `biggest {Format.catchMass(biggest)}` else "not caught yet",
		Ui.FONT_SEMI,
		12,
		Ui.color.muted,
		UDim2.fromOffset(150, 16),
		UDim2.fromOffset(14, 26)
	)
	local columns = { "Normal" }
	for _, rarity in Config.Catch.rarities do
		table.insert(columns, rarity.id)
	end
	for i, id in columns do
		local count = counts[id] or 0
		local rarity = Config.Catch.byId[id]
		local cell = Instance.new("Frame")
		cell.Name = id
		cell.Size = UDim2.fromOffset(92, 38)
		cell.Position = UDim2.fromOffset(170 + (i - 1) * 100, 5)
		cell.BackgroundColor3 = if count > 0 and rarity then rarity.color else Ui.color.panel
		cell.BackgroundTransparency = if count > 0 then 0.55 else 0.4
		cell.BorderSizePixel = 0
		Ui.corner(cell, UDim.new(0, 6))
		local top = Ui.label(
			cell,
			"Count",
			if count > 0 then `×{Ui.number(count)}` else "—",
			Ui.FONT_SEMI,
			14,
			if count > 0 then Ui.color.text else Ui.color.muted,
			UDim2.new(1, 0, 0, 20),
			UDim2.fromOffset(0, 2)
		)
		top.TextXAlignment = Enum.TextXAlignment.Center
		if count > 0 and best[id] then
			local sub = Ui.label(
				cell,
				"Best",
				Format.catchMass(best[id]),
				Ui.FONT_SEMI,
				11,
				Ui.color.text,
				UDim2.new(1, 0, 0, 14),
				UDim2.fromOffset(0, 21)
			)
			sub.TextXAlignment = Enum.TextXAlignment.Center
			sub.TextTransparency = 0.25
		end
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
	heading(
		list,
		10,
		`CATCH LOG · {found} / {total} found · each cell: how many, and your biggest · a first catch pays, a full row more`
	)
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
	local best = s.catchBest or {}
	for i, prey in Config.Prey.list do
		logLine(list, 11 + i, prey.id, log[prey.id] or {}, best[prey.id] or {}, rows[prey.id] == true)
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
			)} coral, {featured.shells} shells, {Config.Wheel.weekly} wheel spins and the {if skin
				then skin.name
				else featured.skin} skin for the fish you catch it with.`,
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
	-- The Treasure Wheel's button nearer than the counter: E is the wheel's
	-- (TreasureWheelController shows its hint by the same rule)
	local wheelState = ReplicatedStorage:FindFirstChild("WheelState")
	local button = if wheelState then wheelState:GetAttribute("ButtonPosition") else nil
	if best and root and typeof(button) == "Vector3" then
		local distance = (root.Position - button).Magnitude
		if distance <= Config.Wheel.reach and distance < bestDistance then
			best = nil
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
	if MenuController.building then
		best = nil
	end
	nearVendor = best
	local show = best ~= nil and current == nil
	local touch = Input.isTouch()
	hintGui.Enabled = show and not touch
	shopButton.Visible = show and touch and not MenuController.stallButtonHidden
	if show and best then
		local label = if best == "__den"
			then (if touch or Input.isGamepad() then "YOUR DEN" else "YOUR DEN   ·   B  BUILD")
			else `SHOP · {Shop.vendorsById[best].name}`
		if touch then
			shopButton.Text = label
		else
			hintSpot.WorldPosition = denSpot or counters[best]
			hintKey.Text = if Input.isGamepad() then "Y" else "E"
			hintText.Text = label
		end
	end
end

-- Whether the hint at your den's pool is up (it already says B · BUILD, so Build
-- mode's own hint stands aside: a screenshot of 2026-10-14 showed both)
function MenuController.denHintShown(): boolean
	return nearVendor == "__den" and current == nil
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
