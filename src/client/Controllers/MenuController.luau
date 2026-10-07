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
local Layout = require(ReplicatedStorage.Shared.Layout)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local ClientState = require(script.Parent.Parent.ClientState)
local FishPreview = require(script.Parent.Parent.FishPreview)
local Input = require(script.Parent.Parent.Input)
local Ui = require(script.Parent.Parent.Ui)

local Shop = Config.Shop
local Tiers = Config.Tiers

local MenuController = {}

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

local function selectFirst(container: Instance)
	if not Input.isGamepad() then
		return
	end
	for _, child in container:GetDescendants() do
		if child:IsA("GuiButton") and child.Selectable and child.Visible then
			GuiService.SelectedObject = child
			return
		end
	end
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
	selectFirst(window.frame)
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
			status = `Have {charms[charm.id] or 0} / {charm.max or 1}`
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
		if shade.price == nil then
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
			if has then "Yours" else "A fresh tint",
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
		color: Color3?
	)
		order += 1
		local tierInfo = Tiers.byId[tier]
		local blurb = if has
			then `{tierInfo.name}{if slot then ` · {slot}` else ""}`
			elseif chance <= 0 then `{tierInfo.name} · beat the world boss to win it`
			else `{tierInfo.name} · roll to find · {RollOdds.oneIn(1 / chance)}`
		local action = if not has then "LOCKED" elseif worn then "TAKE OFF" else "WEAR"
		local style: Ui.ButtonStyle = if not has then "disabled" elseif worn then "secondary" else "primary"
		local _, button = row(
			list,
			order,
			id,
			if has then name else "???",
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
		for _, shade in Config.Shades.list do
			local has = (s.shades or {})[shade.id] == true
			add(
				"shade",
				shade.id,
				shade.name,
				shade.tier,
				shade.chance,
				has,
				equipped.shade == shade.id,
				nil,
				if has then shade.back else nil
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
		else "Every outcome of one roll; they add up to 100%"
	open("Roll Odds", subtitle, Vector2.new(620, 520), function(window)
		local list = Ui.list(window.content, 6)
		return {
			window = window,
			render = function()
				rerender(list, function()
					local odds = RollOdds.table(luck)
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

-- The stall hint: near a counter, a chip over it says which key opens its shop
-- (E, Y on a controller, or tap the chip). Our own, because a ProximityPrompt never
-- showed for the custom fish character.
local hintGui: BillboardGui
local hintKeyFrame: Frame
local hintKey: TextLabel
local hintText: TextLabel
local hintSpot: Attachment
local nearVendor: string? = nil

local counters: { [string]: Vector3 } = {}
for _, vendor in Shop.vendors do
	counters[vendor.id] = Layout.counterPosition(vendor.angle)
end

local function openNearShop()
	local vendorId = nearVendor
	if vendorId == nil then
		return
	end
	if currentShop == vendorId then
		MenuController.close()
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
	hintKeyFrame = key
	hintKey = Ui.label(key, "Text", "E", Ui.FONT_HEAVY, 18, Ui.color.panel, UDim2.fromScale(1, 1))
	hintKey.TextXAlignment = Enum.TextXAlignment.Center
	hintText = Ui.label(chip, "Text", "", Ui.FONT_BOLD, 16, Ui.color.text, UDim2.new(1, -54, 1, 0))
	hintText.Position = UDim2.fromOffset(48, 0)
	chip.Activated:Connect(openNearShop)
	hintGui.Parent = playerGui
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
	nearVendor = best
	local show = best ~= nil and current == nil
	hintGui.Enabled = show
	if show and best then
		hintSpot.WorldPosition = counters[best]
		local touch = Input.isTouch()
		hintKeyFrame.Visible = not touch
		hintKey.Text = if Input.isGamepad() then "Y" else "E"
		hintText.Position = UDim2.fromOffset(if touch then 18 else 48, 0)
		hintText.Text = `{if touch then "TAP TO SHOP" else "SHOP"} · {Shop.vendorsById[best].name}`
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
