--!strict
-- The menus: each vendor's shop (opened at its stall's prompt), the Wardrobe
-- (shades, body parts and variants you own, on a preview of your fish) and the
-- roll odds. One window at a time; the cursor is freed while it's open, and a
-- controller can drive it (the D-pad moves between buttons, B closes).
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
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
	return `{vendor.keeper} · {vendor.blurb}   ·   You have {Ui.number(coral())} coral`
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

function MenuController.start()
	gui = Ui.screen("Menus", Players.LocalPlayer:WaitForChild("PlayerGui"), 10)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local vendor = prompt:GetAttribute("Vendor")
		local stall = prompt.Parent
		if typeof(vendor) == "string" then
			MenuController.openShop(vendor, if stall and stall:IsA("BasePart") then stall.Position else nil)
		end
	end)
	ClientState.changed:connect(function()
		if current then
			current.render()
		end
	end)
	RunService.Heartbeat:Connect(function()
		local menu = current
		if menu == nil then
			return
		end
		if menu.ticking and os.clock() - lastTick >= 1 then
			lastTick = os.clock()
			menu.render()
		end
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if
			menu.anchor
			and root
			and root:IsA("BasePart")
			and (root.Position - menu.anchor).Magnitude > Shop.reach + 8
		then
			MenuController.close()
		end
	end)
end

return MenuController
