--!strict
-- The menus: each vendor's shop (opened at its stall: E, Y or a tap on the hint
-- that shows near a counter), the Wardrobe
-- (skins, body parts, variants and boost trails tried on your fish: Wardrobe.luau)
-- and the roll odds. One window at a time; the cursor is freed while it's open, and a
-- controller can drive it (the D-pad moves between buttons, B closes).
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Biomes = require(ReplicatedStorage.Shared.Biomes)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Garden = require(ReplicatedStorage.Shared.Garden)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Catch = require(ReplicatedStorage.Shared.Catch)
local Fx = require(ReplicatedStorage.Shared.Fx)
local Reward = require(ReplicatedStorage.Shared.Reward)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local Schools = require(ReplicatedStorage.Shared.Schools)
local Tides = require(ReplicatedStorage.Shared.Tides)
local Timing = require(ReplicatedStorage.Shared.Timing)
local ClientState = require(script.Parent.Parent.ClientState)
local CardPhoto = require(script.Parent.Parent.CardPhoto)
local FishPreview = require(script.Parent.Parent.FishPreview)
local Input = require(script.Parent.Parent.Input)
local ItemPhoto = require(script.Parent.Parent.ItemPhoto)
local PreyPhoto = require(script.Parent.Parent.PreyPhoto)
local Sfx = require(script.Parent.Parent.Sfx)
local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Parent.Ui)
local Wardrobe = require(script.Parent.Parent.Wardrobe)
local StartController = require(script.Parent.StartController)

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

-- Whether a press is under way (a pad's A or the mouse's left button held down):
-- rebuilding the rows then swaps the button out from under it, and the press is lost
-- (PC 2026-10-16 round 2, P2: the first A on the Shop's Log row did nothing; the
-- Shop redraws every second)
local function pressing(): boolean
	return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
		or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
end

local deferred: { [ScrollingFrame]: boolean } = {}

-- Rebuilds a list's rows, keeping the scroll position and the selected button. Held
-- off while a press is under way, then done once it's let go.
local function rerender(list: ScrollingFrame, build: () -> ())
	if pressing() then
		if not deferred[list] then
			deferred[list] = true
			task.spawn(function()
				while pressing() and list.Parent do
					task.wait(0.05)
				end
				task.wait(0.05)
				deferred[list] = nil
				if list.Parent then
					rerender(list, build)
				end
			end)
		end
		return
	end
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

-- An upgrade's blurb for the fish being swum: `{ability}` is its own ability's name
-- (Quick Recovery speeds up the Dash, the Torpedo, Puff Up, ...)
local function upgradeBlurb(blurb: string): string
	local species = Config.Species.byId[state().species or Config.Species.STARTER]
	local ability = if species then Config.Abilities.byId[species.signature] else nil
	return (string.gsub(blurb, "{ability}", if ability then ability.name else "Your ability"))
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
			upgradeBlurb(upgrade.blurb),
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

-- A den row with a picture at its left (owner, 2026-10-18: "Den shop needs pics of
-- the items they are buying"): the row grows taller, its words move over and get
-- two lines, and the picture's frame is returned to fill
local function pictureRow(frame: Frame): Frame
	frame.Size = UDim2.new(1, -8, 0, 84)
	local holder = Instance.new("Frame")
	holder.Name = "Picture"
	holder.Size = UDim2.fromOffset(72, 72)
	holder.Position = UDim2.fromOffset(18, 6)
	holder.BackgroundColor3 = Color3.new(1, 1, 1)
	holder.BackgroundTransparency = 0.1
	holder.BorderSizePixel = 0
	Ui.corner(holder, UDim.new(0, 8))
	local floor = Instance.new("UIGradient")
	floor.Rotation = 90
	floor.Color = ColorSequence.new(Color3.fromRGB(58, 92, 112), Color3.fromRGB(14, 30, 44))
	floor.Parent = holder
	holder.Parent = frame
	local title = frame:FindFirstChild("Title") :: TextLabel?
	if title then
		title.Position = UDim2.fromOffset(100, 12)
		title.Size = UDim2.new(1, -398, 0, 22)
	end
	local blurb = frame:FindFirstChild("Blurb") :: TextLabel?
	if blurb then
		blurb.Position = UDim2.fromOffset(100, 36)
		blurb.Size = UDim2.new(1, -398, 0, 38)
		blurb.TextWrapped = true
		blurb.TextYAlignment = Enum.TextYAlignment.Top
	end
	return holder
end

-- The doorway styles' rows (Config/Dens `doors`; owner, 2026-10-18: "change the
-- actual entrance to our den to unlockable versions to make it easier to spot"):
-- each with a swatch of its stone, trim and glow; bought once, then worn or swapped
local function denDoorRows(list: ScrollingFrame, next: () -> number, s: any, den: any)
	local Dens = Config.Dens
	local progress = if typeof(s.achievements) == "table" then s.achievements else {}
	local owned = if typeof(den.doors) == "table" then den.doors else {}
	local wearing = if typeof(den.door) == "string" then den.door else "Stone"
	denSection(list, next(), "Doorway · your den's front door on the plaza, easy to spot")
	for _, style in Dens.doors do
		local has = style.price == 0 or owned[style.id] == true
		local worn = wearing == style.id
		local locked: string? = nil
		local count: string? = nil
		if not has then
			if style.level and (den.level or 1) < style.level then
				local level = Dens.levels[style.level]
				locked = `needs a {if level then level.name else "bigger"} den`
			elseif style.achievement then
				local achievement = Config.Achievements.byId[style.achievement]
				if achievement and (progress[achievement.id] or 0) < achievement.goal then
					locked = `opens with {achievement.name}: {achievement.blurb}`
					count = `{Ui.number(progress[achievement.id] or 0)} / {Ui.number(achievement.goal)}`
				end
			end
		end
		local frame, button = row(
			list,
			next(),
			`Door{style.id}`,
			style.name,
			if locked then `{style.blurb} · {locked}` else style.blurb,
			if count then count elseif has and not worn then "Owned" else nil,
			if worn then "IN USE" elseif has then "USE" elseif locked then "LOCKED" else coralText(style.price),
			if worn
				then "disabled"
				elseif has then "secondary"
				elseif locked then "disabled"
				else priceStyle(style.price),
			style.colors[3]
		)
		-- The swatch: its stone round its trim round its glow, like a little doorway
		local swatch = pictureRow(frame)
		swatch.BackgroundColor3 = style.colors[1]
		local shade = swatch:FindFirstChildOfClass("UIGradient")
		if shade then
			shade:Destroy()
		end
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.56)
		ring.Size = UDim2.fromOffset(48, 48)
		ring.BackgroundColor3 = style.colors[2]
		ring.BorderSizePixel = 0
		Ui.corner(ring, UDim.new(1, 0))
		ring.Parent = swatch
		local glow = Instance.new("Frame")
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, 0.5)
		glow.Size = UDim2.fromOffset(32, 32)
		glow.BackgroundColor3 = style.colors[3]
		glow.BorderSizePixel = 0
		Ui.corner(glow, UDim.new(1, 0))
		glow.Parent = ring
		if button and not worn and locked == nil then
			button.Activated:Connect(function()
				ClientState.request("DenDoor", style.id)
			end)
		end
	end
end

-- The den shop's rows: things (into the Build tray), the furniture sets, floors and
-- glows. Part of the den menu, and on its own as Build mode's SHOP
local function denShopRows(list: ScrollingFrame, next: () -> number, s: any, den: any)
	local Dens = Config.Dens
	-- Things: bought into the Build tray (the furniture sets come after)
	denSection(list, next(), "Things · they go into your Build tray")
	local items = if typeof(den.items) == "table" then den.items else {}
	local glowColor = (Dens.glowsById[den.glow] or Dens.glows[1]).color
	local function itemRow(item: typeof(Dens.items[1]))
		local owned = items[item.id] or 0
		local where = table.concat(item.kinds, " / ")
		local frame, button = row(
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
		-- Its picture, made as it scrolls into view (ItemPhoto)
		ItemPhoto.attach(pictureRow(frame), item, glowColor, list)
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

-- `shopOnly`: the den shop opened from Build mode (things, sets, floors and glows)
local function denRows(list: ScrollingFrame, shopOnly: boolean?)
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
	local level = Dens.levels[den.level] or Dens.levels[1]
	local upgrade = Dens.levels[den.level + 1]
	local passes = s.passes or {}
	if shopOnly then
		denShopRows(list, next, s, den)
		return
	end
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
	local garden = s.garden
	if typeof(garden) == "table" then
		local nextRates = if upgrade
			then Garden.rates(
				upgrade.level,
				passes.DeepGarden == true,
				if state().premium == true then Config.Monetization.tuning.premium.gardenHours else 0
			)
			else nil
		-- (shorter on a phone, where the long line was cut off at the right)
		local touch = Input.isTouch()
		local blurb = if touch
			then `{Ui.number(garden.coralPerHour)} coral, {Ui.number(garden.shellsPerHour)} shells /h · {garden.hours} h · ×{garden.rest} resting here`
			else `{Ui.number(garden.coralPerHour)} coral and {Ui.number(garden.shellsPerHour)} shells an hour, `
				.. `holds {garden.hours} h · ×{garden.rest} while you rest here`
		if nextRates and upgrade and not touch then
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
	denDoorRows(list, next, s, den)
	denShopRows(list, next, s, den)
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
	open("YOUR DEN · BUILD AND SHOP", denSubtitle(), Vector2.new(720, 520), function(window)
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

-- The den shop on its own (Build mode's SHOP, owner 2026-10-17): what you buy goes
-- into the Build tray
function MenuController.openDenShop()
	local function subtitle(): string
		return `Bought things go into your Build tray   ·   {Ui.number(coral())} coral`
	end
	open("DEN SHOP", subtitle(), Vector2.new(720, 520), function(window)
		local list = Ui.list(window.content)
		return {
			window = window,
			render = function()
				window.subtitle.Text = subtitle()
				rerender(list, function()
					denRows(list, true)
				end)
			end,
		}
	end)
	currentShop = "__denshop"
end

-- Re-draws the open menu (a pick inside it changed)
function MenuController.rerenderCurrent()
	if current then
		current.render()
	end
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
-- A DNA unlock's three conditions, each marked ✓ once met (PC 2026-10-18: at LV 40
-- it still said "Grow your Nibbler to LV 15 (it's LV 40)"), and whether all are
local function unlockNote(rule: any, s: any): (string, boolean)
	local biome = Config.Biomes.byId[rule.biome]
	local biomeName = if biome then biome.name else "its home biome"
	local have = (s.dna or {})[rule.biome] or 0
	local need = rule.dna or 0
	local price = rule.coral or 0
	local starter = (s.speciesLevels or {})[Config.Species.STARTER] or 1
	local parts: { string } = {}
	local ready = true
	if rule.level then
		if starter >= rule.level then
			table.insert(parts, `✓ Nibbler LV {rule.level}`)
		else
			ready = false
			table.insert(parts, `grow your Nibbler to LV {rule.level} (LV {starter} now)`)
		end
	end
	if have >= need then
		table.insert(parts, `✓ {need} {biomeName} DNA`)
	else
		ready = false
		table.insert(parts, `{need} {biomeName} DNA ({have} so far; it drops from fish there)`)
	end
	if coral() >= price then
		table.insert(parts, `✓ {Ui.number(price)} coral`)
	else
		ready = false
		table.insert(parts, `{Ui.number(price)} coral (you have {Ui.number(coral())})`)
	end
	local list = table.concat(parts, " · ")
	return if ready then `Ready: {list}.` else `To unlock: {list}.`, ready
end

-- A fish's good points and its drawbacks (Config/Species `perks`, `drawbacks`) as
-- rows with a green tick or a red minus badge (owner, 2026-10-18: "The perks for
-- each fish and their drawbacks need to be listed on the ui where the player
-- selects their fish"). Returns the height used.
local function fishTraits(parent: Instance, species: any): number
	local y = 0
	local function badge(row: Frame, good: boolean)
		local dot = Instance.new("Frame")
		dot.Name = "Badge"
		dot.BackgroundColor3 = if good then Ui.color.safe else Ui.color.danger
		dot.BorderSizePixel = 0
		dot.Size = UDim2.fromOffset(15, 15)
		dot.Position = UDim2.fromOffset(0, 1)
		Ui.corner(dot, UDim.new(1, 0))
		dot.Parent = row
		if good then
			local tick =
				Ui.label(dot, "Tick", "✓", Ui.FONT_HEAVY, 12, Ui.color.panelFoot, UDim2.fromScale(1, 1))
			tick.TextXAlignment = Enum.TextXAlignment.Center
		else
			-- A minus drawn as a bar (no glyph to go missing)
			local bar = Instance.new("Frame")
			bar.Name = "Minus"
			bar.BackgroundColor3 = Color3.fromRGB(255, 240, 240)
			bar.BorderSizePixel = 0
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromScale(0.5, 0.5)
			bar.Size = UDim2.fromOffset(8, 2)
			bar.Parent = dot
		end
	end
	local function section(title: string, color: Color3, lines: { string }, good: boolean)
		local heading = Ui.label(
			parent,
			title,
			title,
			Ui.FONT_HEAVY,
			12,
			color,
			UDim2.new(1, 0, 0, 16),
			UDim2.fromOffset(0, y)
		)
		heading.Name = if good then "GoodAt" else "WatchOut"
		y += 18
		for i, text in lines do
			local row = Instance.new("Frame")
			row.Name = `{if good then "Perk" else "Drawback"}{i}`
			row.BackgroundTransparency = 1
			row.Position = UDim2.fromOffset(0, y)
			row.Size = UDim2.new(1, 0, 0, 17)
			row.Parent = parent
			badge(row, good)
			local label = Ui.label(
				row,
				"Text",
				text,
				Ui.FONT_SEMI,
				13,
				Ui.color.text,
				UDim2.new(1, -22, 1, 0),
				UDim2.fromOffset(22, 0)
			)
			label.TextScaled = true
			local fit = Instance.new("UITextSizeConstraint")
			fit.MaxTextSize = 13
			fit.MinTextSize = 9
			fit.Parent = label
			y += 18
		end
	end
	section("GOOD AT", Ui.color.safe, species.perks or {}, true)
	y += 6
	section("WATCH OUT", Ui.color.danger, species.drawbacks or {}, false)
	return y
end

-- A fish's signature ability: the key that uses it on this device as a key cap, its
-- name, and what it does
local function fishAbility(parent: Instance, species: any, y: number)
	local ability = Config.Abilities.byId[species.signature]
	if ability == nil then
		return
	end
	local key = if Input.isTouch()
		then ability.label or string.upper(ability.name)
		elseif Input.isGamepad() then "RT"
		else "LEFT CLICK"
	local row = Instance.new("Frame")
	row.Name = "Ability"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(0, y)
	row.Size = UDim2.new(1, 0, 0, 24)
	row.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local cap = Ui.keycap(row, "Key", key, 24)
	cap.LayoutOrder = 1
	local name = Ui.label(
		row,
		"Name",
		string.upper(ability.name),
		Ui.FONT_HEAVY,
		15,
		Ui.color.haul,
		UDim2.fromOffset(0, 24)
	)
	name.AutomaticSize = Enum.AutomaticSize.X
	name.LayoutOrder = 2
	local blurb = Ui.label(
		parent,
		"AbilityBlurb",
		ability.blurb,
		Ui.FONT,
		13,
		Ui.color.muted,
		UDim2.new(1, 0, 0, 72),
		UDim2.fromOffset(0, y + 30)
	)
	blurb.TextWrapped = true
	blurb.TextYAlignment = Enum.TextYAlignment.Top
end

function MenuController.openSpecies()
	open(
		"Your Fish",
		"Each fish levels up on its own, and fights go by its level. Switch in the safe zone.",
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
				local level = (s.speciesLevels or {})[chosen]
				Ui.label(
					info,
					"Level",
					if owned then `LEVEL {level or 1}` else "NOT UNLOCKED",
					Ui.FONT_HEAVY,
					15,
					if owned then Ui.color.haul else Ui.color.muted,
					UDim2.new(1, 0, 0, 18),
					UDim2.fromOffset(0, 52)
				)
				-- Its ability, with the button that uses it on this device
				fishAbility(info, species, 78)

				-- Stats and the blurb on the left, good at / watch out on the right
				local stats = Instance.new("Frame")
				stats.Name = "Stats"
				stats.BackgroundTransparency = 1
				stats.Size = UDim2.new(0.42, -8, 0, 170)
				stats.Parent = lower
				statBar(stats, 0, "Speed", species.stats.speed)
				statBar(stats, 22, "Turning", species.stats.turn)
				statBar(stats, 44, "Health", species.stats.health)
				statBar(stats, 66, "Bite", species.stats.bite)
				local blurb = Ui.label(
					stats,
					"Blurb",
					species.blurb,
					Ui.FONT,
					13,
					Ui.color.muted,
					UDim2.new(1, 0, 0, 60),
					UDim2.fromOffset(0, 92)
				)
				blurb.TextWrapped = true
				blurb.TextYAlignment = Enum.TextYAlignment.Top
				local traits = Instance.new("Frame")
				traits.Name = "Traits"
				traits.BackgroundTransparency = 1
				traits.Position = UDim2.new(0.42, 8, 0, 0)
				traits.Size = UDim2.new(0.58, -8, 0, 170)
				traits.Parent = lower
				fishTraits(traits, species)

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
					local ready
					note, ready = unlockNote(rule, s)
					if ready then
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
					UDim2.new(1, -200, 0, 58),
					UDim2.new(0, 0, 1, -60)
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

-- The Index (owner, 2026-10-17: "Need more info for players such as an index or
-- something to show them how they are to get all of the harder skins, parts, what
-- the parts do, etc. Needs more direction for players starting out"): a GUIDE of
-- what to do next and how the game works, then every skin of this fish and every
-- skin any fish can have, the parts, the variants, the fish and the boost trails,
-- each with how it's got and whether it's yours. ROLL ODDS opens the odds panel.
local INDEX_TABS = { "Guide", "Skins", "Parts", "Variants", "Fish", "Trails" }

-- A skin's effect ids as words ("rainbowRim" reads "rainbow rim")
local function fxWords(ids: { string }): string
	local words: { string } = {}
	for _, id in ids do
		table.insert(words, string.lower((string.gsub(id, "(%l)(%u)", "%1 %2"))))
	end
	return table.concat(words, ", ")
end

-- A row whose text runs to more lines (the Index): the title, then `text` wrapped
local function infoRow(
	list: ScrollingFrame,
	order: number,
	title: string,
	text: string,
	accent: Color3?,
	status: string?,
	statusColor: Color3?
)
	local frame = row(list, order, `Info{order}`, title, text, status, nil, nil, accent)
	local lines = math.clamp(math.ceil(#text / 92), 1, 3)
	frame.Size = UDim2.new(1, -8, 0, 44 + lines * 17)
	local blurb = frame:FindFirstChild("Blurb") :: TextLabel?
	if blurb then
		blurb.TextWrapped = true
		blurb.TextYAlignment = Enum.TextYAlignment.Top
		blurb.Size = UDim2.new(1, -200, 0, lines * 17 + 2)
	end
	local label = frame:FindFirstChild("Status") :: TextLabel?
	if label then
		label.Position = UDim2.new(1, -150, 0, 12)
		if statusColor then
			label.TextColor3 = statusColor
		end
	end
end

-- Where a reward (a skin or a boost trail) sits on this season's Tide Pass
local function passSource(field: string, id: string): string?
	local pass = state().pass
	local season = if typeof(pass) == "table" and typeof(pass.season) == "number" then pass.season else 1
	local def = Config.Pass.seasons[(season - 1) % #Config.Pass.seasons + 1]
	for i, entry in def.tiers do
		if entry.free and (entry.free :: any)[field] == id then
			return `Tide Pass free row, tier {i}`
		elseif entry.paid and (entry.paid :: any)[field] == id then
			return `Deep Pass row, tier {i}`
		end
	end
	return nil
end

-- How a skin is got, for the fish you swim as
local function shadeHow(shade: any, s: any): string
	if shade.pass then
		return `{passSource("skin", shade.id) or "A Tide Pass season"} · works on every fish`
	elseif shade.catch then
		local rarity = Config.Catch.byId[shade.catch]
		local done = Catch.goal(s.catchLog, rarity.id)
		return `Catch {rarity.unlock.each} {rarity.name} fish of each of {rarity.unlock.species} species, as any fish ({math.min(
			done,
			rarity.unlock.species
		)} / {rarity.unlock.species} species so far) · then it's every fish's · the LOG's logbook`
	elseif shade.week then
		return "The Catch of the Week's skin: catch that week's fish (the LOG) while it runs"
	elseif shade.boss then
		local boss = if shade.boss == "GiantSquid" then "Giant Squid" else shade.boss
		local price = ""
		for _, item in Config.Shop.trophies do
			if item.shade == shade.id then
				price = ` or {item.price} {item.currencyName} at the Trophy Hunter`
			end
		end
		return `Beat the {boss} world boss: a 1 in 15 drop{price}`
	elseif shade.treasure then
		return `Dug up from a Captain's treasure chest, or roll it on any fish · about {RollOdds.oneIn(
			1 / shade.chance
		)}`
	elseif shade.price then
		return `The Shade Dyer sells it for {Ui.number(shade.price)} coral, or roll it · {RollOdds.oneIn(
			1 / shade.chance
		)}`
	end
	return `Roll it (50 shells a roll) · about {RollOdds.oneIn(1 / shade.chance)}`
end

-- The Wardrobe (src/client/Wardrobe.luau): your fish on a lit stage trying things
-- on, and every skin, part, variant and boost trail as a card. It reads the Index's
-- text helpers above, and a locked thing's link opens the menu it's got from.
function MenuController.openWardrobe()
	open("Wardrobe", Wardrobe.subtitle(), Wardrobe.size(), function(window)
		local built = Wardrobe.build(window, {
			shadeHow = shadeHow,
			passSource = passSource,
			openPass = function()
				MenuController.openPass()
			end,
			openLog = function()
				MenuController.openLog()
			end,
			openOdds = function()
				MenuController.openOdds()
			end,
			openIndex = function(tab: string?)
				MenuController.openIndex(tab)
			end,
		})
		return { window = window, render = built.render, cleanup = built.cleanup }
	end)
end

-- What to do next, from where you are (the Guide's first rows)
-- A key name for this device: keyboard, pad or touch
local function byDevice(keyboard: string, pad: string, touch: string): string
	return if Input.isTouch() then touch elseif Input.isGamepad() then pad else keyboard
end

local function nextGoals(s: any): { { title: string, text: string } }
	local goals: { { title: string, text: string } } = {}
	local tutorial = s.tutorial
	-- (opening this finishes the tutorial's last step, so that step doesn't show)
	local tutorialStep = if typeof(tutorial) == "table"
		then Config.Tutorial.steps[tutorial.step or 1]
		else nil
	if
		typeof(tutorial) == "table"
		and not tutorial.done
		and (tutorialStep == nil or tutorialStep.event ~= "index")
	then
		table.insert(goals, {
			title = "Finish the tutorial",
			text = `Step {tutorial.step or 1} of {#Config.Tutorial.steps}: follow the card at the top left and the trail of lights.`,
		})
	end
	local levels = s.speciesLevels or {}
	local nibbler = levels[Config.Species.STARTER] or 1
	local unlocked = s.unlocked or {}
	local cuda = Config.Species.byId.Cuda
	if not unlocked.Cuda and cuda.unlock.biome then
		local note, ready = unlockNote(cuda.unlock, s)
		table.insert(goals, {
			title = `Unlock the {cuda.name}`,
			text = if ready then `{note} Unlock it in FISH.` else note,
		})
	end
	local level = s.level or nibbler
	for _, biome in Config.Biomes.list do
		if biome.live and biome.minLevel > level then
			table.insert(goals, {
				title = `Next biome: {biome.name}`,
				text = `Suggested from LV {biome.minLevel} (you're LV {level}). Eat, bank, repeat: bigger fish give more.`,
			})
			break
		end
	end
	local ready = s.rollsReady or 0
	if ready > 0 then
		table.insert(goals, {
			title = `{ready} roll{if ready == 1 then "" else "s"} ready`,
			text = `Press {byDevice("ROLL (R)", "ROLL (D-pad down)", "ROLL")} for a new skin, part or variant for the fish you swim as.`,
		})
	end
	local den = s.den
	local denLevel = if typeof(den) == "table" and typeof(den.level) == "number" then den.level else 1
	local nextDen = Config.Dens.levels[denLevel + 1]
	if nextDen then
		table.insert(goals, {
			title = `Dig your den into a {nextDen.name}`,
			text = `{Ui.number(nextDen.cost)} coral in the den menu ({byDevice("E", "Y", "DEN & SHOP")} in your den). It holds {nextDen.capacity} things.`,
		})
	end
	return goals
end

-- How it works, in this device's own buttons
local function guide(): { { title: string, text: string } }
	return {
		{
			title = "Eat and grow",
			text = `Swim into anything under about two thirds your size to swallow it. {byDevice(
				"BITE (right click)",
				"BITE (RB)",
				"Tap BITE on"
			)} other players, predators and bosses: players are never swallowed whole, and a higher level bites harder. A fish that's too big to eat will chase you: swim away.`,
		},
		{
			title = "Predators",
			text = "Every predator shows its level on its tag. Ten levels above it you bite it apart in a few bites, twenty above you swallow it whole, and once you're twelve above it, it won't hunt you. Below its level its bites hurt more and yours barely scratch. Each hunts its own way, so read the warning: dash out of a grouper's gulp, dodge a goblin shark's jaws sideways.",
		},
		{
			title = "Bank your Haul",
			text = "Everything you eat on a dive is your Haul, and it grows you live. Swim home into your den's pool to bank it as growth for good. Get eaten first and it bursts into chum.",
		},
		{
			title = "Biomes and depth",
			text = "Kelp Shallows LV 1+, Shipwreck Graveyard 10+, Coral Reef 25+, Open Blue 35+, Sunken Ruins 50+, Hydrothermal Vents 65+, Abyssal Trench 80+. Too deep too soon and the pressure crushes you.",
		},
		{
			title = "Shells and rolls",
			text = "Every 50 shells is a roll: a skin, a body part or a variant for the fish you swim as. Skins you have never roll again for that fish. ROLL ODDS shows every chance.",
		},
		{
			title = "Fish",
			text = "Each fish levels up on its own. Unlock new fish in FISH with their home biome's DNA (it drops from fish there) and coral.",
		},
		{
			title = "Your den",
			text = `Your den is your house. {byDevice(
				"Press E in it for the den menu and shop, B to build.",
				"Press Y in it for the den menu and shop; BUILD is in the menu.",
				"Tap DEN & SHOP in it for the den menu and shop; BUILD is in the menu."
			)} Its Coral Garden grows coral and shells while you're away.`,
		},
		{
			title = "Healing",
			text = `Health never comes back on its own. Kelp Wraps ({byDevice("H", "LB", "HEAL")}) heal 40%, and eating prey heals a little.`,
		},
		{
			title = "Rare catches and tides",
			text = "Silver, Golden, Glowing, Crystal and Prism fish sparkle and pay big. Catch them from five species for skins every fish wears (the LOG's logbook). The Tide Clock changes the sea every 20 minutes.",
		},
		{
			title = "Whale hunts",
			text = "Humpbacks cross the Open Blue. Only hunters (the 'Cuda, Moray Eel, Reef Shark and Anglerfish) from LV 60 can hurt one: bring it down together and everyone who bit it is paid, and it sinks as a Whale Fall that feeds the whole server.",
		},
		{
			title = "World bosses",
			text = "The Megalodon and the Giant Squid rise about every 30 minutes. Fight together for trophies, exclusive skins and a huge Haul.",
		},
		{
			title = "Treasure maps",
			text = "Maps drop from prey, shells and big banks. Follow one (MAPS) and dig at the X: coral, shells and sometimes a rare skin.",
		},
		{
			title = "The Tide Pass",
			text = "Playing earns pass tiers: skins that work on every fish, boost trails, coral and more. The Deep Pass opens a second row.",
		},
	}
end

function MenuController.openIndex(startTab: string?)
	-- The tutorial's last step is opening this (TutorialService)
	local tutorial = state().tutorial
	if typeof(tutorial) == "table" and not tutorial.done then
		ClientState.request("TutorialSaw", "Index")
	end
	open("Index", "How to get everything, and what to do next", Vector2.new(920, 560), function(window)
		local tab = startTab or "Guide"
		local tabs: { [string]: TextButton } = {}
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Position = UDim2.fromOffset(0, 50)
		holder.Size = UDim2.new(1, 0, 1, -50)
		holder.Parent = window.content
		local list = Ui.list(holder, 6)
		local menu: Menu
		for i, name in INDEX_TABS do
			local button = Ui.button(
				window.content,
				name,
				string.upper(name),
				UDim2.fromOffset(110, 38),
				UDim2.fromOffset((i - 1) * 116, 0),
				"secondary"
			)
			tabs[name] = button
			button.Activated:Connect(function()
				tab = name
				list.CanvasPosition = Vector2.zero
				menu.render()
			end)
		end
		local odds = Ui.button(
			window.content,
			"Odds",
			"ROLL ODDS",
			UDim2.fromOffset(130, 38),
			UDim2.new(1, -130, 0, 0),
			"gold"
		)
		odds.Activated:Connect(MenuController.openOdds)
		local function owned(has: boolean): (string, Color3)
			return if has then "YOURS" else "NOT YET", if has then Ui.color.safe else Ui.color.muted
		end
		menu = {
			window = window,
			render = function()
				for name, button in tabs do
					Ui.setButtonStyle(button, if name == tab then "primary" else "secondary")
				end
				rerender(list, function()
					local s = state()
					local order = 0
					local function next(): number
						order += 1
						return order
					end
					if tab == "Guide" then
						denSection(list, next(), "Next for you")
						for _, goal in nextGoals(s) do
							infoRow(list, next(), goal.title, goal.text, Ui.color.haul)
						end
						denSection(list, next(), "How it works")
						for _, entry in guide() do
							infoRow(list, next(), entry.title, entry.text, Ui.color.accent)
						end
					elseif tab == "Skins" then
						local species = Config.Species.byId[s.species or ""] or Config.Species.byId.Nibbler
						local shades = s.shades or {}
						denSection(list, next(), `{species.name} skins · this fish's own line`)
						local line: { any } = Config.Shades.lines[species.id] or {}
						for _, shade in line do
							local tier = Tiers.byId[shade.tier]
							local status, color = owned(shades[shade.id] == true)
							local fx = if shade.fx then ` · effects: {fxWords(shade.fx)}` else ""
							infoRow(
								list,
								next(),
								`{shade.name} · {tier.name}`,
								shadeHow(shade, s) .. fx,
								tier.color,
								status,
								color
							)
						end
						denSection(
							list,
							next(),
							"Skins every fish can have · unlocked per fish (Tide Pass skins for all at once)"
						)
						for _, shade in Config.Shades.list do
							if shade.species == nil and (shade.week == nil or shades[shade.id]) then
								local tier = Tiers.byId[shade.tier]
								local status, color = owned(shades[shade.id] == true)
								local fx = if shade.fx then ` · effects: {fxWords(shade.fx)}` else ""
								infoRow(
									list,
									next(),
									`{shade.name} · {tier.name}`,
									shadeHow(shade, s) .. fx,
									tier.color,
									status,
									color
								)
							end
						end
					elseif tab == "Parts" then
						denSection(
							list,
							next(),
							"Body parts · one per slot, from rolls, on any fish · each with a small bonus, never bite damage"
						)
						for _, part in Config.Exotics.parts do
							local status, color = owned((s.parts or {})[part.id] == true)
							infoRow(
								list,
								next(),
								`{part.name} · {part.slot}`,
								`{part.blurb} Bonus: {part.bonus.text}. Roll it · about {RollOdds.oneIn(
									1 / part.chance
								)}. Duplicates turn into {Ui.number(part.refund)} coral.`,
								Tiers.byId.Abyssal.color,
								status,
								color
							)
						end
					elseif tab == "Variants" then
						denSection(
							list,
							next(),
							"Exotic variants · each a rare form of one fish, from rolls as that fish, with a small bonus to its ability"
						)
						for _, variant in Config.Exotics.variants do
							local fish = Config.Species.byId[variant.species]
							local status, color = owned((s.variants or {})[variant.id] == true)
							infoRow(
								list,
								next(),
								`{variant.name} · {if fish then fish.name else variant.species} only`,
								`{variant.blurb} Bonus: {variant.bonus.text}. Roll it as {if fish
									then fish.name
									else "that fish"} · about {RollOdds.oneIn(1 / variant.chance)}.`,
								Tiers.byId.Abyssal.color,
								status,
								color
							)
						end
					elseif tab == "Fish" then
						denSection(list, next(), "The fish · each levels up on its own")
						for _, species in Config.Species.list do
							local rule = species.unlock
							local how = if rule.kind == "start"
								then "Everyone starts as one."
								elseif rule.kind == "tutorial" then "Finish the tutorial."
								else `{if rule.level then `Nibbler LV {rule.level}, then ` else ""}{rule.dna or 0} {(
									Config.Biomes.byId[rule.biome or ""] or { name = "?" }
								).name} DNA and {Ui.number(rule.coral or 0)} coral (FISH menu).`
							local status, color = owned((s.unlocked or {})[species.id] == true)
							-- Its good points and drawbacks, as in FISH (Config/Species)
							infoRow(
								list,
								next(),
								`{species.name} · {species.role}`,
								`Good at: {table.concat(species.perks, ", ")}. Watch out: {table.concat(
									species.drawbacks,
									", "
								)}. {how}`,
								species.fin,
								status,
								color
							)
						end
					else
						denSection(
							list,
							next(),
							"Boost trails · every fish's, worn in the Wardrobe's TRAILS · they stream off you when you dash"
						)
						for _, trail in Config.Trails.list do
							local tier = Tiers.byId[trail.tier]
							local status, color = owned((s.trails or {})[trail.id] == true)
							infoRow(
								list,
								next(),
								`{trail.name} · {tier.name}`,
								`{trail.blurb} {passSource("trail", trail.id) or "A later Tide Pass season"}.`,
								trail.color,
								status,
								color
							)
						end
					end
				end)
			end,
		}
		return menu
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
						-- The Tide Pass: here too, so a controller can reach it (PASS is a HUD
						-- button; PC 2026-10-16, PS1)
						local pass = if typeof(s.pass) == "table" then s.pass else nil
						local waiting = if pass and typeof(pass.waiting) == "number" then pass.waiting else 0
						local _, passButton = row(
							list,
							next(),
							"TidePass",
							"Tide Pass",
							"This season's free row and the Deep Pass: every reward and what's unlocked",
							if waiting > 0 then `{waiting} to claim` else nil,
							"OPEN",
							if waiting > 0 then "gold" else "secondary",
							Ui.color.accent
						)
						if passButton then
							passButton.Activated:Connect(MenuController.openPass)
						end
						-- The LOG: here too, for the same reason (PC 2026-10-16: a controller
						-- couldn't reach the Catch Log, bounties, the weekly race or the tides)
						local _, logButton = row(
							list,
							next(),
							"Log",
							"Log",
							"The Catch Log, today's bounties, the weekly race and the tide forecast",
							nil,
							"OPEN",
							"secondary",
							Ui.color.accent
						)
						if logButton then
							logButton.Activated:Connect(function()
								MenuController.openLog()
							end)
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

-- The daily panel's pictures: a reward's headline as a lit 3D photo (the roll cards'
-- subjects: a charm, Kelp Wraps, shells, coral; a chest of coral for big amounts),
-- and a chip in the corner for what has no photo (a wheel spin, a treasure map)
local function dailyVisual(reward: Reward.Reward): (CardPhoto.Outcome?, string?)
	local extra: { string } = {}
	if reward.map then
		table.insert(extra, "+MAP")
	end
	if reward.spins then
		table.insert(extra, "+SPIN")
	end
	local chip = if #extra > 0 then table.concat(extra, " ") else nil
	if reward.charms then
		local id = if reward.charms.SecondChance then "secondChance" else "charm"
		return { kind = "charm", id = id, name = "", tier = "Rare" }, chip
	elseif reward.wraps then
		return { kind = "wraps", id = "wraps", name = "", tier = "Uncommon" }, chip
	elseif reward.shells and not reward.coral then
		return { kind = "shells", id = "shells", name = "", tier = "Common" }, chip
	elseif reward.coral then
		return { kind = "coral", id = "coral", name = "", tier = "Coral", amount = reward.coral }, chip
	elseif reward.shells then
		return { kind = "shells", id = "shells", name = "", tier = "Common" }, chip
	end
	return nil, chip
end

-- A flame drawn from frames (no emoji icons): a round base under a turned square,
-- with a lighter core
local function flame(parent: Instance, size: number): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Flame"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	holder.Parent = parent
	local function drop(scale: number, color: Color3, z: number)
		local s = size * scale
		local base = Instance.new("Frame")
		base.Name = "Base"
		base.BackgroundColor3 = color
		base.BorderSizePixel = 0
		base.AnchorPoint = Vector2.new(0.5, 1)
		base.Position = UDim2.new(0.5, 0, 1, -size * (1 - scale) * 0.1)
		base.Size = UDim2.fromOffset(s * 0.72, s * 0.72)
		base.ZIndex = z
		Ui.corner(base, UDim.new(1, 0))
		base.Parent = holder
		local tip = Instance.new("Frame")
		tip.Name = "Tip"
		tip.BackgroundColor3 = color
		tip.BorderSizePixel = 0
		tip.AnchorPoint = Vector2.new(0.5, 0.5)
		tip.Position = UDim2.new(0.5, 0, 1, -size * (1 - scale) * 0.1 - s * 0.5)
		tip.Size = UDim2.fromOffset(s * 0.5, s * 0.5)
		tip.Rotation = 45
		tip.ZIndex = z
		Ui.corner(tip, UDim.new(0, math.max(2, math.floor(s * 0.08))))
		tip.Parent = holder
	end
	drop(1, Color3.fromRGB(255, 120, 40), 2)
	drop(0.6, Color3.fromRGB(255, 214, 90), 3)
	return holder
end

-- One tile of the daily panel or the gift strip: a heading, the reward's photo, its
-- lines, and a foot that holds a CLAIM button, a check or a countdown
type DailyTile = {
	frame: Frame,
	scale: UIScale,
	stroke: UIStroke?,
	head: TextLabel,
	visual: Frame,
	body: TextLabel,
	foot: TextLabel,
	check: Frame,
	claim: TextButton,
	chip: TextLabel?,
}

local function dailyTile(
	parent: Instance,
	name: string,
	order: number,
	size: Vector2,
	reward: Reward.Reward,
	visualHeight: number,
	bodyHeight: number,
	onClaim: () -> ()
): DailyTile
	local frame = Ui.panel(parent, name, UDim2.fromOffset(size.X, size.Y), UDim2.new())
	frame.LayoutOrder = order
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local head = Ui.label(
		frame,
		"Head",
		"",
		Ui.FONT_HEAVY,
		13,
		Ui.color.text,
		UDim2.new(1, 0, 0, 16),
		UDim2.fromOffset(0, 6)
	)
	head.TextXAlignment = Enum.TextXAlignment.Center
	local visual = Instance.new("Frame")
	visual.Name = "Visual"
	visual.BackgroundColor3 = Ui.color.panelFoot
	visual.BackgroundTransparency = 0.35
	visual.BorderSizePixel = 0
	visual.ClipsDescendants = true
	visual.Position = UDim2.fromOffset(6, 23)
	visual.Size = UDim2.new(1, -12, 0, visualHeight)
	Ui.corner(visual, UDim.new(0, 8))
	visual.Parent = frame
	local outcome, chipText = dailyVisual(reward)
	if outcome then
		CardPhoto.new(visual, outcome, Ui.color.haul)
	end
	local chip: TextLabel? = nil
	if chipText then
		local made = Ui.chip(visual, "Extra", chipText, Ui.color.haul, 16)
		made.AnchorPoint = Vector2.new(1, 1)
		made.Position = UDim2.new(1, -3, 1, -3)
		made.ZIndex = visual.ZIndex + 3
		chip = made
	end
	local body = Ui.label(
		frame,
		"Reward",
		"",
		Ui.FONT_BOLD,
		11,
		Ui.color.text,
		UDim2.new(1, -8, 0, bodyHeight),
		UDim2.fromOffset(4, 25 + visualHeight)
	)
	body.TextXAlignment = Enum.TextXAlignment.Center
	body.TextYAlignment = Enum.TextYAlignment.Center
	body.TextWrapped = true
	-- (a long line, "1 SECOND CHANCE", shrinks to fit instead of running off)
	body.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint")
	fit.Name = "Fit"
	fit.MaxTextSize = 11
	fit.MinTextSize = 7
	fit.Parent = body
	local foot = Ui.label(
		frame,
		"State",
		"",
		Ui.FONT_HEAVY,
		12,
		Ui.color.muted,
		UDim2.new(1, 0, 0, 16),
		UDim2.new(0, 0, 1, -22)
	)
	foot.TextXAlignment = Enum.TextXAlignment.Center
	-- Claimed: a green check badge in the top-right corner
	local check = Instance.new("Frame")
	check.Name = "Check"
	check.BackgroundColor3 = Ui.color.safe
	check.BorderSizePixel = 0
	check.AnchorPoint = Vector2.new(1, 0)
	check.Position = UDim2.new(1, 4, 0, -4)
	check.Size = UDim2.fromOffset(22, 22)
	check.ZIndex = 6
	Ui.corner(check, UDim.new(1, 0))
	Ui.stroke(check, Ui.color.panelFoot, 0.2, 2)
	local tick = Ui.label(check, "Tick", "✓", Ui.FONT_HEAVY, 15, Ui.color.panelFoot, UDim2.fromScale(1, 1))
	tick.TextXAlignment = Enum.TextXAlignment.Center
	tick.ZIndex = 7
	check.Visible = false
	check.Parent = frame
	local claim =
		Ui.button(frame, "Claim", "CLAIM", UDim2.new(1, -12, 0, 28), UDim2.new(0, 6, 1, -34), "gold")
	claim.FontFace = Ui.FONT_HEAVY
	claim.TextSize = 14
	claim.ZIndex = 6
	claim.Visible = false
	claim.Activated:Connect(onClaim)
	return {
		frame = frame,
		scale = scale,
		stroke = frame:FindFirstChildOfClass("UIStroke"),
		head = head,
		visual = visual,
		body = body,
		foot = foot,
		check = check,
		claim = claim,
		chip = chip,
	}
end

-- A tile's look for its state: claimed (dim, a check), ready (gold edge, bigger, the
-- CLAIM button), next (accent edge), later (dimmed); `big` keeps a gold edge
local function styleTile(tile: DailyTile, kind: "done" | "ready" | "next" | "later", big: boolean?)
	local done, ready = kind == "done", kind == "ready"
	tile.frame.BackgroundTransparency = if done then 0.5 elseif kind == "later" then 0.35 else 0.1
	tile.check.Visible = done
	tile.claim.Visible = ready
	tile.foot.Visible = not ready
	local stroke = tile.stroke
	if stroke then
		stroke.Color = if ready or big
			then Ui.color.haul
			elseif kind == "next" then Ui.color.accent
			else Ui.color.stroke
		stroke.Thickness = if ready then 2.5 elseif big or kind == "next" then 1.5 else 1
		stroke.Transparency = if ready then 0 elseif big or kind == "next" then 0.35 else 0.62
	end
	local muted = done or kind == "later"
	tile.head.TextColor3 = if ready
		then Ui.color.haul
		elseif big and not done then Ui.color.haul
		else Ui.color.text
	tile.head.TextTransparency = if muted then 0.35 else 0
	tile.body.TextColor3 = if muted then Ui.color.muted else Ui.color.text
	tile.visual.BackgroundTransparency = if muted then 0.6 else 0.35
	local photo = tile.visual:FindFirstChildOfClass("ViewportFrame")
	if photo then
		photo.ImageTransparency = if kind == "later" then 0.45 elseif done then 0.3 else 0
	end
	local want = if ready then 1.06 else 1
	if math.abs(tile.scale.Scale - want) > 0.001 then
		Ui.tween(tile.scale, 0.3, { Scale = want }, Enum.EasingStyle.Back)
	end
end

-- The daily login streak (DAILY on the HUD; it opens by itself on joining when a
-- reward is waiting): seven days that build to a big Day 7, then loop with a bonus
-- for each finished week. Spruced up (owner, 2026-10-18: "Daily reward screen could
-- be spruced up a bit"): a streak strip with a flame, the count and the week bonus;
-- every day a tile with its rewards as photos, today's raised with its own CLAIM,
-- claimed days checked, later ones dimmed, Day 7 bigger and gold; the playtime gifts
-- in the same tiles with a bar filling toward the next one. Tiles are built once and
-- restyled every second (photos aren't rebuilt), and a pad lands on CLAIM.
function MenuController.openDaily()
	local Daily = Config.Daily
	local Playtime = Config.Playtime
	local premiumTune = Config.Monetization.tuning.premium
	open("Daily Reward", "", Vector2.new(780, 520), function(window)
		local content = window.content
		-- The streak strip: flame, count, best, the week's bonus
		local strip = Instance.new("Frame")
		strip.Name = "Streak"
		strip.BackgroundTransparency = 1
		strip.Size = UDim2.new(1, 0, 0, 32)
		strip.Parent = content
		local stripLayout = Instance.new("UIListLayout")
		stripLayout.FillDirection = Enum.FillDirection.Horizontal
		stripLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		stripLayout.Padding = UDim.new(0, 10)
		stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
		stripLayout.Parent = strip
		local fire = flame(strip, 28)
		fire.LayoutOrder = 1
		local streakText =
			Ui.label(strip, "Count", "", Ui.FONT_HEAVY, 22, Ui.color.text, UDim2.fromOffset(0, 30))
		streakText.AutomaticSize = Enum.AutomaticSize.X
		streakText.LayoutOrder = 2
		local bestText =
			Ui.label(strip, "Best", "", Ui.FONT_SEMI, 14, Ui.color.muted, UDim2.fromOffset(0, 30))
		bestText.AutomaticSize = Enum.AutomaticSize.X
		bestText.LayoutOrder = 3
		local weekChip = Ui.chip(strip, "Week", "", Ui.color.haul, 26)
		weekChip.LayoutOrder = 4
		-- The days
		local days = Instance.new("Frame")
		days.Name = "Days"
		days.BackgroundTransparency = 1
		days.Position = UDim2.fromOffset(0, 38)
		days.Size = UDim2.new(1, 0, 0, 172)
		days.Parent = content
		local dayLayout = Instance.new("UIListLayout")
		dayLayout.FillDirection = Enum.FillDirection.Horizontal
		dayLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		dayLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		dayLayout.Padding = UDim.new(0, 8)
		dayLayout.SortOrder = Enum.SortOrder.LayoutOrder
		dayLayout.Parent = days
		local dayTiles: { DailyTile } = {}
		for i, reward in Daily.days do
			local big = reward.big == true
			local tile = dailyTile(
				days,
				`Day{i}`,
				i,
				Vector2.new(if big then 128 else 92, if big then 172 else 160),
				reward,
				if big then 66 else 56,
				40,
				function()
					ClientState.request("ClaimDaily")
				end
			)
			if big then
				-- The day the week builds to: washed in gold, under everything on it
				local band = Instance.new("Frame")
				band.Name = "Band"
				band.BackgroundColor3 = Ui.color.haul
				band.BackgroundTransparency = 0.84
				band.BorderSizePixel = 0
				band.Size = UDim2.fromScale(1, 1)
				band.ZIndex = 0
				Ui.corner(band)
				band.Parent = tile.frame
			end
			dayTiles[i] = tile
		end
		local footer = Ui.label(
			content,
			"Footer",
			"",
			Ui.FONT_SEMI,
			14,
			Ui.color.muted,
			UDim2.new(1, 0, 0, 16),
			UDim2.fromOffset(0, 212)
		)
		footer.TextXAlignment = Enum.TextXAlignment.Center
		-- Playtime gifts (owner, 2026-10-12): a ladder for minutes played today. Each
		-- tile lists its rewards one to a line (PC 2026-10-19: on a phone "2,000 CORAL ·
		-- WEATHERED MAP ·" was cut off at the smallest size), so the strip sits a
		-- little higher and its tiles are taller, with a slimmer CLAIM.
		local giftHeader = Ui.heading(content, "GiftHeader", "Playtime gifts", 232)
		giftHeader.TextColor3 = Ui.color.haul
		local giftState = Ui.label(
			content,
			"GiftState",
			"",
			Ui.FONT_BOLD,
			12,
			Ui.color.text,
			UDim2.fromOffset(300, 16),
			UDim2.new(1, -300, 0, 232)
		)
		giftState.TextXAlignment = Enum.TextXAlignment.Right
		local _, giftFill =
			Ui.bar(content, "GiftProgress", UDim2.new(1, 0, 0, 5), UDim2.fromOffset(0, 254), Ui.color.haul)
		local gifts = Instance.new("Frame")
		gifts.Name = "Gifts"
		gifts.BackgroundTransparency = 1
		gifts.Position = UDim2.fromOffset(0, 262)
		gifts.Size = UDim2.new(1, 0, 0, 124)
		gifts.Parent = content
		local giftLayout = Instance.new("UIListLayout")
		giftLayout.FillDirection = Enum.FillDirection.Horizontal
		giftLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		giftLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		giftLayout.Padding = UDim.new(0, 8)
		giftLayout.SortOrder = Enum.SortOrder.LayoutOrder
		giftLayout.Parent = gifts
		local giftTiles: { DailyTile } = {}
		for i, gift in Playtime.gifts do
			local tile = dailyTile(
				gifts,
				`Gift{i}`,
				i,
				Vector2.new(if gift.big then 108 else 92, 124),
				gift,
				28,
				-- (four lines at 8 take ~44.4: at 44 the hour's 250 PASS XP was cut,
				-- PC 2026-10-19 round 2, UI2)
				46,
				function()
					ClientState.request("ClaimGift")
				end
			)
			-- Up to four lines (the hour's gift), shrinking no smaller than 8
			local fit = tile.body:FindFirstChild("Fit")
			if fit and fit:IsA("UITextSizeConstraint") then
				fit.MaxTextSize = 10
				fit.MinTextSize = 8
			end
			tile.claim.Size = UDim2.new(1, -12, 0, 22)
			tile.claim.Position = UDim2.new(0, 6, 1, -24)
			tile.claim.TextSize = 13
			giftTiles[i] = tile
		end
		-- Premium's perks, for those without it (never a wall: the gifts come anyway)
		local premiumButton = Ui.button(
			content,
			"Premium",
			"GET PREMIUM",
			UDim2.fromOffset(150, 32),
			UDim2.new(1, -150, 0, 390),
			"secondary"
		)
		premiumButton.TextSize = 13
		premiumButton.Activated:Connect(Store.buyPremium)
		local premiumNote = Ui.label(
			content,
			"PremiumNote",
			`Premium: ×{premiumTune.gifts} gifts · {premiumTune.spins} free spin a day · +{premiumTune.gardenHours} h garden`,
			Ui.FONT_SEMI,
			12,
			Ui.color.muted,
			UDim2.new(1, -166, 0, 32),
			UDim2.fromOffset(0, 390)
		)
		premiumNote.TextXAlignment = Enum.TextXAlignment.Right
		premiumNote.TextWrapped = true
		-- What was claimed shows in the footer for a few seconds
		local claimedText, claimedUntil = "", 0
		local claimed = (ReplicatedStorage:WaitForChild("Remotes") :: Instance):WaitForChild(
				"DailyClaimed"
			) :: RemoteEvent
		local function reselect()
			-- A pad's selection was on a CLAIM that just went away: the next one, or GET
			-- PREMIUM, or the close button
			local selected = GuiService.SelectedObject
			if
				not Input.isGamepad()
				or (selected and selected.Visible and selected:IsDescendantOf(window.frame))
			then
				return
			end
			for _, tiles in { dayTiles, giftTiles } do
				for _, tile in tiles do
					if tile.claim.Visible then
						GuiService.SelectedObject = tile.claim
						return
					end
				end
			end
			GuiService.SelectedObject = if premiumButton.Visible then premiumButton else window.close
		end
		local connection = claimed.OnClientEvent:Connect(function(summary: { [string]: any })
			local got = if typeof(summary.got) == "table" then table.concat(summary.got, " · ") else ""
			claimedText = if summary.kind == "gift"
				then `{summary.minutes}-minute gift claimed: {got}`
				else `Day {summary.streak} claimed: {got}`
			claimedUntil = os.clock() + 4
			Sfx.play("Bank", { volume = 0.6 })
			MenuController.rerenderCurrent()
			task.defer(reselect)
		end)
		local function renderGifts()
			local pt = state().playtime
			if typeof(pt) ~= "table" then
				gifts.Visible = false
				premiumButton.Visible = false
				premiumNote.Visible = false
				giftState.Text = ""
				return
			end
			gifts.Visible = true
			local now = workspace:GetServerTimeNow()
			local claimedCount = pt.claimed or 0
			local unlockedCount = pt.unlocked or 0
			local bonus = pt.bonus or 1
			local premium = state().premium == true
			local nextGift = Playtime.gifts[unlockedCount + 1]
			local prevMinutes = if unlockedCount > 0 then Playtime.gifts[unlockedCount].minutes else 0
			giftState.Text = if pt.claimable
				then "A GIFT IS READY · CLAIM IT"
				elseif nextGift and typeof(pt.nextAt) == "number" then `NEXT GIFT IN {clockText(
					pt.nextAt - now
				)}`
				else "ALL CLAIMED TODAY"
			giftState.TextColor3 = if pt.claimable then Ui.color.haul else Ui.color.text
			-- The bar fills from the last gift's minute to the next one's
			local fraction = 1
			if nextGift and typeof(pt.nextAt) == "number" then
				local span = math.max((nextGift.minutes - prevMinutes) * 60, 1)
				fraction = 1 - math.clamp((pt.nextAt - now) / span, 0, 1)
			end
			giftFill.Size = UDim2.fromScale(fraction, 1)
			for i, gift in Playtime.gifts do
				local tile = giftTiles[i]
				local done = i <= claimedCount
				local ready = not done and i <= unlockedCount
				local nextOne = not done and not ready and i == unlockedCount + 1
				tile.head.Text = `{gift.minutes} MIN`
				tile.body.Text = table.concat(Reward.lines(gift, bonus), "\n")
				tile.foot.Text = if done
					then "CLAIMED"
					elseif nextOne and typeof(pt.nextAt) == "number" then clockText(pt.nextAt - now)
					else ""
				tile.foot.TextColor3 = if done then Ui.color.safe else Ui.color.accent
				styleTile(
					tile,
					if done then "done" elseif ready then "ready" elseif nextOne then "next" else "later",
					gift.big
				)
			end
			premiumButton.Visible = not premium
			premiumNote.Visible = not premium
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
				local streak = daily.streak or 0
				local week = math.floor((math.max(streak, 1) - 1) / #Daily.days) + 1
				window.subtitle.Text = if daily.broken
					then "You missed a day, so the streak starts again at Day 1"
					elseif (daily.best or 0) == 0 then "Claim Day 1 to start your streak"
					else "Come back every day: the rewards build to Day 7"
				streakText.Text = if (daily.best or 0) == 0 then "NO STREAK YET" else `{streak} DAY STREAK`
				bestText.Text = if (daily.best or 0) > 0 then `best {daily.best}` else ""
				weekChip.Text = if bonus > 1
					then `WEEK {week} · +{math.floor((bonus - 1) * 100 + 0.5)}% CORAL & SHELLS`
					else "EACH FULL WEEK: +25% MORE"
				for i, reward in Daily.days do
					local tile = dayTiles[i]
					local done = i < today or (i == today and not daily.claimable)
					local ready = i == today and daily.claimable
					tile.head.Text = if ready then "TODAY" else `DAY {i}`
					tile.body.Text = table.concat(Reward.lines(reward, bonus), "\n")
					tile.foot.Text = if done
						then (if i == today then "✓ TODAY" else "CLAIMED")
						elseif i == today % #Daily.days + 1 then "TOMORROW"
						else ""
					tile.foot.TextColor3 = if done then Ui.color.safe else Ui.color.muted
					styleTile(tile, if done then "done" elseif ready then "ready" else "later", reward.big)
				end
				renderGifts()
				footer.TextColor3 = if os.clock() < claimedUntil then Ui.color.haul else Ui.color.muted
				footer.Text = if os.clock() < claimedUntil
					then claimedText
					elseif daily.claimable then "Today's reward is waiting: CLAIM it on its tile"
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
-- row (a developer product). Laid out as a track you can read at a glance (owner,
-- 2026-10-16: "a free version ... that everyone gets, and a visual showing the
-- unlock tree/pass so players can see what they get with the paid version, its just
-- locked"): a FREE PASS row everyone has and a DEEP PASS row under it, each named by
-- a card at its left; a progress line with a node per tier; every reward shown as a
-- lit 3D photo (a skin on your own fish, coral, shells, wraps, a charm: the roll
-- cards' subjects) or a badge (den piece, title, map, spin); the Deep row padlocked
-- until it's bought, its rewards still in plain view.
local passScrolled = false

-- A padlock drawn from frames (no emoji icons): a ring for the shackle, a body over
-- its lower half, a keyhole
local function padlock(parent: Instance, size: number, color: Color3): Frame
	local lock = Instance.new("Frame")
	lock.Name = "Lock"
	lock.BackgroundTransparency = 1
	lock.Size = UDim2.fromOffset(size, size)
	lock.Parent = parent
	local shackle = Instance.new("Frame")
	shackle.Name = "Shackle"
	shackle.BackgroundTransparency = 1
	shackle.AnchorPoint = Vector2.new(0.5, 0)
	shackle.Position = UDim2.fromScale(0.5, 0)
	shackle.Size = UDim2.fromScale(0.56, 0.66)
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
	Ui.corner(body, UDim.new(0, math.max(2, math.floor(size / 7))))
	body.Parent = lock
	local hole = Instance.new("Frame")
	hole.Name = "Keyhole"
	hole.BackgroundColor3 = Ui.color.panelFoot
	hole.BorderSizePixel = 0
	hole.AnchorPoint = Vector2.new(0.5, 0.5)
	hole.Position = UDim2.fromScale(0.5, 0.5)
	hole.Size = UDim2.fromScale(0.18, 0.4)
	Ui.corner(hole, UDim.new(0.5, 0))
	hole.Parent = body
	return lock
end

local function tierColor(id: string): Color3
	local tier = Config.Tiers.byId[id]
	return if tier then tier.color else Ui.color.accent
end

-- What a pass reward shows above its words: the roll cards' photo of its headline
-- (a skin on your fish, a charm, Kelp Wraps, shells, coral), or a badge word for
-- the things with no photo; and the colour it's framed in
local function passVisual(reward: Reward.Reward): (CardPhoto.Outcome?, string?, Color3, string?)
	if reward.skin then
		local shade = Config.Shades.byId[reward.skin]
		local tier = if shade then shade.tier else "Rare"
		return { kind = "shade", id = reward.skin, name = "", tier = tier }, nil, tierColor(tier), "SKIN"
	elseif reward.trail then
		local trail = Config.Trails.byId[reward.trail]
		return nil, "TRAIL", if trail then trail.color else Ui.color.accent, "TRAIL"
	elseif reward.den then
		return nil, "DEN", Ui.color.haul, "DEN"
	elseif reward.title then
		return nil, "TITLE", Ui.color.accent, "TITLE"
	elseif reward.map then
		return nil, "MAP", Color3.fromRGB(255, 170, 110), nil
	elseif reward.spins then
		return nil, "SPIN", Ui.color.haul, nil
	elseif reward.charms then
		local id = if reward.charms.SecondChance then "secondChance" else "charm"
		return { kind = "charm", id = id, name = "", tier = "Rare" }, nil, Ui.color.stroke, nil
	elseif reward.wraps then
		return { kind = "wraps", id = "wraps", name = "", tier = "Uncommon" }, nil, Ui.color.stroke, nil
	elseif reward.shells then
		return { kind = "shells", id = "shells", name = "", tier = "Common" }, nil, Ui.color.stroke, nil
	end
	return { kind = "coral", id = "coral", name = "", tier = "Coral", amount = reward.coral or 25 },
		nil,
		Ui.color.stroke,
		nil
end

-- "3 skins · 1 title · 3 den pieces" for a row of a season
local function passHighlights(
	season: { tiers: { { free: Reward.Reward?, paid: Reward.Reward? } } },
	row: string
): string
	local skins, titles, dens, trails = 0, 0, 0, 0
	for _, entry in season.tiers do
		local reward = (entry :: any)[row] :: Reward.Reward?
		if reward then
			skins += if reward.skin then 1 else 0
			titles += if reward.title then 1 else 0
			dens += if reward.den then 1 else 0
			trails += if reward.trail then 1 else 0
		end
	end
	local parts: { string } = {}
	if skins > 0 then
		table.insert(parts, `{skins} skin{if skins == 1 then "" else "s"} for every fish`)
	end
	if trails > 0 then
		table.insert(parts, `{trails} boost trail{if trails == 1 then "" else "s"}`)
	end
	if titles > 0 then
		table.insert(parts, `{titles} title{if titles == 1 then "" else "s"}`)
	end
	if dens > 0 then
		table.insert(parts, `{dens} den piece{if dens == 1 then "" else "s"}`)
	end
	return table.concat(parts, " · ")
end

type PassCell = {
	frame: Frame,
	stroke: UIStroke?,
	frameColor: Color3,
	visual: Frame,
	photo: ViewportFrame?,
	outcome: CardPhoto.Outcome?,
	body: TextLabel,
	foot: TextLabel,
	lock: Frame?,
	ready: boolean,
	locked: boolean,
}
type PassColumn = {
	number: TextLabel,
	fill: Frame,
	node: Frame,
	free: PassCell?,
	paid: PassCell?,
	attached: boolean,
}

function MenuController.openPass()
	local Pass = Config.Pass
	local product = Config.Monetization.productsByKey[Pass.product]
	local priceText = if product then Store.price(product.price) else ""
	open("Tide Pass", "", Vector2.new(940, 560), function(window)
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
			if product then `DEEP PASS · {priceText}` else "DEEP PASS",
			UDim2.fromOffset(140, 40),
			UDim2.new(1, -140, 0, 2),
			if product and product.id ~= 0 then "gold" else "disabled"
		)
		deep.TextSize = 13
		deep.Activated:Connect(function()
			Store.buyProduct(Pass.product)
		end)

		local COLUMN, GAP, TILE = 104, 8, 158
		local HEADER = 124 -- the row cards' width at the left
		local TOP = 70 -- the strip's top in the window
		local FREE_Y, PAID_Y = 26, 26 + TILE + 8

		-- The row cards: what each row is, fixed at the left while the tiers scroll
		local freeCard = Ui.panel(
			content,
			"FreeCard",
			UDim2.fromOffset(HEADER - 8, TILE),
			UDim2.fromOffset(0, TOP + FREE_Y)
		)
		local freeTitle = Ui.label(
			freeCard,
			"Title",
			"FREE PASS",
			Ui.FONT_HEAVY,
			16,
			Ui.color.safe,
			UDim2.new(1, -12, 0, 20),
			UDim2.fromOffset(8, 10)
		)
		freeTitle.TextXAlignment = Enum.TextXAlignment.Left
		local freeWho = Ui.label(
			freeCard,
			"Who",
			"Everyone gets it, every season",
			Ui.FONT_SEMI,
			11,
			Ui.color.text,
			UDim2.new(1, -14, 0, 30),
			UDim2.fromOffset(8, 32)
		)
		freeWho.TextWrapped = true
		freeWho.TextXAlignment = Enum.TextXAlignment.Left
		freeWho.TextYAlignment = Enum.TextYAlignment.Top
		local freeHigh = Ui.label(
			freeCard,
			"Highlights",
			"",
			Ui.FONT_BOLD,
			11,
			Ui.color.muted,
			UDim2.new(1, -14, 0, 44),
			UDim2.fromOffset(8, 70)
		)
		freeHigh.TextWrapped = true
		freeHigh.TextXAlignment = Enum.TextXAlignment.Left
		freeHigh.TextYAlignment = Enum.TextYAlignment.Top
		local freeChip = Ui.chip(freeCard, "Open", "OPEN", Ui.color.safe, 20)
		freeChip.Position = UDim2.new(0, 8, 1, -28)

		local deepCard = Ui.panel(
			content,
			"DeepCard",
			UDim2.fromOffset(HEADER - 8, TILE),
			UDim2.fromOffset(0, TOP + PAID_Y)
		)
		local deepStroke = deepCard:FindFirstChildOfClass("UIStroke")
		if deepStroke then
			deepStroke.Color = Ui.color.haul
			deepStroke.Transparency = 0.25
			deepStroke.Thickness = 2
		end
		local deepTitle = Ui.label(
			deepCard,
			"Title",
			"DEEP PASS",
			Ui.FONT_HEAVY,
			16,
			Ui.color.haul,
			UDim2.new(1, -12, 0, 20),
			UDim2.fromOffset(8, 10)
		)
		deepTitle.TextXAlignment = Enum.TextXAlignment.Left
		local deepLock = padlock(deepCard, 26, Ui.color.haul)
		deepLock.AnchorPoint = Vector2.new(1, 0)
		deepLock.Position = UDim2.new(1, -8, 0, 8)
		local deepWho = Ui.label(
			deepCard,
			"Who",
			"",
			Ui.FONT_SEMI,
			11,
			Ui.color.text,
			UDim2.new(1, -14, 0, 30),
			UDim2.fromOffset(8, 36)
		)
		deepWho.TextWrapped = true
		deepWho.TextXAlignment = Enum.TextXAlignment.Left
		deepWho.TextYAlignment = Enum.TextYAlignment.Top
		local deepHigh = Ui.label(
			deepCard,
			"Highlights",
			"",
			Ui.FONT_BOLD,
			11,
			Ui.color.muted,
			UDim2.new(1, -14, 0, 44),
			UDim2.fromOffset(8, 70)
		)
		deepHigh.TextWrapped = true
		deepHigh.TextXAlignment = Enum.TextXAlignment.Left
		deepHigh.TextYAlignment = Enum.TextYAlignment.Top
		local deepChip = Ui.chip(deepCard, "State", "LOCKED", Ui.color.haul, 20)
		deepChip.Position = UDim2.new(0, 8, 1, -28)
		-- The whole card buys it while it's locked
		local deepBuy = Instance.new("TextButton")
		deepBuy.Name = "Buy"
		deepBuy.Text = ""
		deepBuy.BackgroundTransparency = 1
		deepBuy.Size = UDim2.fromScale(1, 1)
		deepBuy.ZIndex = deepCard.ZIndex + 5
		deepBuy.Selectable = false
		deepBuy.Parent = deepCard
		deepBuy.Activated:Connect(function()
			local pass = state().pass
			if typeof(pass) == "table" and pass.paid ~= true and product and product.id ~= 0 then
				Store.buyProduct(Pass.product)
			end
		end)

		local strip = Instance.new("ScrollingFrame")
		strip.Name = "Tiers"
		strip.BackgroundTransparency = 1
		strip.BorderSizePixel = 0
		strip.Position = UDim2.fromOffset(HEADER, TOP)
		strip.Size = UDim2.new(1, -HEADER, 1, -TOP)
		strip.ScrollingDirection = Enum.ScrollingDirection.X
		strip.ScrollBarThickness = 6
		strip.ScrollBarImageColor3 = Ui.color.stroke
		strip.ElasticBehavior = Enum.ElasticBehavior.Never
		strip.Selectable = false
		strip.Parent = content

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

		-- One reward tile: a photo or badge, its words, its state at the foot, and
		-- on the Deep row a padlock until the pass is bought
		local function cell(
			parent: Instance,
			name: string,
			y: number,
			reward: Reward.Reward?,
			paidRow: boolean
		): PassCell
			local frame = Ui.panel(parent, name, UDim2.fromOffset(COLUMN, TILE), UDim2.fromOffset(0, y))
			local stroke = frame:FindFirstChildOfClass("UIStroke")
			local visual = Instance.new("Frame")
			visual.Name = "Visual"
			visual.BackgroundColor3 = Ui.color.panelFoot
			visual.BackgroundTransparency = 0.35
			visual.BorderSizePixel = 0
			visual.ClipsDescendants = true
			visual.Position = UDim2.fromOffset(5, 5)
			visual.Size = UDim2.new(1, -10, 0, 74)
			Ui.corner(visual, UDim.new(0, 8))
			visual.Parent = frame
			local outcome: CardPhoto.Outcome? = nil
			local frameColor = Ui.color.stroke
			if reward then
				local badge: string?, tag: string?
				outcome, badge, frameColor, tag = passVisual(reward)
				if reward.trail then
					-- A streak in the trail's colours behind the word
					local trail = Config.Trails.byId[reward.trail]
					local streak = Instance.new("Frame")
					streak.Name = "Streak"
					streak.AnchorPoint = Vector2.new(0.5, 0.5)
					streak.Position = UDim2.fromScale(0.5, 0.5)
					streak.Size = UDim2.new(1, -16, 0, 22)
					streak.BackgroundColor3 = Color3.new(1, 1, 1)
					streak.BorderSizePixel = 0
					Ui.corner(streak, UDim.new(1, 0))
					local gradient = Instance.new("UIGradient")
					gradient.Color = if trail and trail.style == "rainbow"
						then Fx.rainbow(0.7)
						else ColorSequence.new(
							if trail then trail.color2 else Ui.color.accent,
							if trail then trail.color else Ui.color.accent
						)
					gradient.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(0.6, 0.35),
						NumberSequenceKeypoint.new(1, 0.1),
					})
					gradient.Parent = streak
					streak.Parent = visual
				end
				if badge then
					local word = Ui.label(
						visual,
						"Badge",
						badge,
						Ui.FONT_HEAVY,
						22,
						frameColor,
						UDim2.fromScale(1, 1),
						UDim2.fromOffset(0, 0)
					)
					word.TextXAlignment = Enum.TextXAlignment.Center
					word.TextStrokeTransparency = 0.6
				end
				if tag then
					local chip = Ui.chip(visual, "Tag", tag, frameColor, 16)
					chip.Position = UDim2.fromOffset(4, 4)
					chip.ZIndex = visual.ZIndex + 3
				end
			end
			local body = Ui.label(
				frame,
				"Reward",
				if reward then table.concat(Reward.lines(reward), "\n") else "—",
				Ui.FONT_BOLD,
				11,
				Ui.color.text,
				UDim2.new(1, -8, 0, 52),
				UDim2.fromOffset(4, 82)
			)
			body.TextXAlignment = Enum.TextXAlignment.Center
			body.TextYAlignment = Enum.TextYAlignment.Center
			body.TextWrapped = true
			local foot = Ui.label(
				frame,
				"State",
				"",
				Ui.FONT_HEAVY,
				11,
				Ui.color.muted,
				UDim2.new(1, 0, 0, 16),
				UDim2.new(0, 0, 1, -20)
			)
			foot.TextXAlignment = Enum.TextXAlignment.Center
			local lock: Frame? = nil
			if paidRow then
				local made = padlock(frame, 18, Ui.color.haul)
				made.AnchorPoint = Vector2.new(1, 0)
				made.Position = UDim2.new(1, -8, 0, 8)
				made.ZIndex = visual.ZIndex + 4
				for _, d in made:GetDescendants() do
					if d:IsA("GuiObject") then
						d.ZIndex = visual.ZIndex + 4
					end
				end
				lock = made
			end
			local made: PassCell = {
				frame = frame,
				stroke = stroke,
				frameColor = frameColor,
				visual = visual,
				photo = nil,
				outcome = outcome,
				body = body,
				foot = foot,
				lock = lock,
				ready = false,
				locked = false,
			}
			-- A tap (or A on a pad) claims a READY tile (with everything unlocked
			-- before it: tiers are claimed in order), and on the locked Deep row buys
			-- the pass. Tiles are selectable so a controller can walk the track
			-- (PC 2026-10-16: a pad saw tiers 1-7 only).
			local hit = Instance.new("TextButton")
			hit.Name = "Select"
			hit.Text = ""
			hit.BackgroundTransparency = 1
			hit.AutoButtonColor = false
			hit.Size = UDim2.fromScale(1, 1)
			hit.ZIndex = visual.ZIndex + 6
			hit.Selectable = true
			hit.Parent = frame
			hit.Activated:Connect(function()
				if made.ready then
					ClientState.request("ClaimPass")
				elseif made.locked and product and product.id ~= 0 then
					Store.buyProduct(Pass.product)
				end
			end)
			return made
		end

		-- A tile's look for its state
		local function paint(c: PassCell?, claimed: boolean, ready: boolean, locked: boolean)
			if c == nil then
				return
			end
			c.frame.BackgroundTransparency = if claimed then 0.55 elseif locked then 0.3 else 0.1
			local stroke = c.stroke
			if stroke then
				if ready then
					stroke.Color = Ui.color.haul
					stroke.Transparency = 0
					stroke.Thickness = 2.5
				else
					stroke.Color = c.frameColor
					stroke.Transparency = if claimed then 0.75 elseif locked then 0.5 else 0.2
					stroke.Thickness = if c.frameColor ~= Ui.color.stroke then 2 else 1
				end
			end
			c.body.TextColor3 = if claimed or locked then Ui.color.muted else Ui.color.text
			c.foot.Text = if claimed
				then "✓ CLAIMED"
				elseif locked then "DEEP PASS"
				elseif ready then "READY"
				else ""
			c.foot.TextColor3 = if claimed
				then Ui.color.safe
				elseif locked then Ui.color.haul
				else Ui.color.haul
			local photo = c.photo
			if photo then
				photo.ImageColor3 = if claimed or locked
					then Color3.fromRGB(150, 160, 175)
					else Color3.new(1, 1, 1)
			end
			local lock = c.lock
			if lock then
				lock.Visible = locked
			end
			c.ready = ready
			c.locked = locked
		end

		local columns: { PassColumn } = {}
		local builtFor = ""

		-- Screen pixels per canvas offset: CanvasPosition and AbsoluteSize count screen
		-- pixels, so where the window is scaled down (phones) they're smaller than the
		-- column offsets they're measured against (PC 2026-10-16, PS1: the right-hand
		-- columns never got their photos on the phone)
		local function canvasScale(): number
			local offset = strip.CanvasSize.X.Offset
			if offset <= 0 or strip.AbsoluteCanvasSize.X <= 0 then
				return 1
			end
			return strip.AbsoluteCanvasSize.X / offset
		end

		-- Photos are made only for the columns in (or next to) view, as they scroll in
		local function attachVisible()
			local scale = canvasScale()
			local left = strip.CanvasPosition.X / scale - (COLUMN + GAP)
			local right = (strip.CanvasPosition.X + strip.AbsoluteSize.X) / scale + (COLUMN + GAP)
			for i, column in columns do
				local x = (i - 1) * (COLUMN + GAP)
				if column.attached or x + COLUMN < left or x > right then
					continue
				end
				column.attached = true
				for _, c in { column.free, column.paid } do
					local outcome = c and c.outcome
					if c and outcome then
						c.photo = CardPhoto.new(c.visual, outcome, tierColor(outcome.tier))
					end
				end
			end
		end
		local scrolled = strip:GetPropertyChangedSignal("CanvasPosition"):Connect(attachVisible)
		-- The canvas's screen size settles a frame after it's set
		local resized = strip:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(attachVisible)
		-- A controller walking the tiles: keep the selected tier in view
		local followed = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
			local selected = GuiService.SelectedObject
			if selected == nil or not selected:IsDescendantOf(strip) then
				return
			end
			local tierFrame: Instance? = selected
			while tierFrame and tierFrame.Parent ~= strip do
				tierFrame = tierFrame.Parent
			end
			if tierFrame == nil or not tierFrame:IsA("GuiObject") then
				return
			end
			local scale = canvasScale()
			local x = tierFrame.Position.X.Offset * scale
			local width = (COLUMN + GAP) * scale
			local view = strip.AbsoluteSize.X
			local at = strip.CanvasPosition.X
			if x < at + width * 0.5 then
				strip.CanvasPosition = Vector2.new(math.max(0, x - width), 0)
			elseif x + width > at + view - width * 0.5 then
				strip.CanvasPosition = Vector2.new(math.max(0, x + 2 * width - view), 0)
			end
		end)

		local function build(
			def: { tiers: { { free: Reward.Reward?, paid: Reward.Reward? } } },
			tiers: number
		)
			for _, child in strip:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			table.clear(columns)
			strip.CanvasSize = UDim2.fromOffset(tiers * (COLUMN + GAP), 0)
			for i = 1, tiers do
				local entry = def.tiers[i]
				local column = Instance.new("Frame")
				column.Name = `Tier{i}`
				column.BackgroundTransparency = 1
				column.Position = UDim2.fromOffset((i - 1) * (COLUMN + GAP), 0)
				column.Size = UDim2.fromOffset(COLUMN, PAID_Y + TILE)
				column.Parent = strip
				local number = Ui.label(
					column,
					"Number",
					`TIER {i}`,
					Ui.FONT_HEAVY,
					12,
					Ui.color.muted,
					UDim2.new(1, 0, 0, 14),
					UDim2.fromOffset(0, 0)
				)
				number.TextXAlignment = Enum.TextXAlignment.Center
				-- The track: a line through every tier, filled up to where you are,
				-- with a node at each tier
				local track = Instance.new("Frame")
				track.Name = "Track"
				track.BackgroundColor3 = Ui.color.track
				track.BorderSizePixel = 0
				track.Position = UDim2.fromOffset(0, 17)
				track.Size = UDim2.fromOffset(COLUMN + GAP, 4)
				track.Parent = column
				local trackFill = Instance.new("Frame")
				trackFill.Name = "Fill"
				trackFill.BackgroundColor3 = Ui.color.haul
				trackFill.BorderSizePixel = 0
				trackFill.Size = UDim2.fromScale(0, 1)
				trackFill.Parent = track
				local node = Instance.new("Frame")
				node.Name = "Node"
				node.AnchorPoint = Vector2.new(0.5, 0.5)
				node.Position = UDim2.fromOffset(COLUMN / 2, 19)
				node.Size = UDim2.fromOffset(10, 10)
				node.BackgroundColor3 = Ui.color.track
				node.BorderSizePixel = 0
				Ui.corner(node, UDim.new(0.5, 0))
				Ui.stroke(node, Ui.color.haul, 0.3, 1.5)
				node.Parent = column
				columns[i] = {
					number = number,
					fill = trackFill,
					node = node,
					free = cell(column, "Free", FREE_Y, entry and entry.free, false),
					paid = cell(column, "Paid", PAID_Y, entry and entry.paid, true),
					attached = false,
				}
			end
		end

		return {
			window = window,
			ticking = true,
			cleanup = function()
				connection:Disconnect()
				scrolled:Disconnect()
				resized:Disconnect()
				followed:Disconnect()
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
				local paid = pass.paid == true
				local left = (pass.endsAt or 0) - workspace:GetServerTimeNow()
				seasonLabel.Text = `SEASON {pass.season or 1} · {string.upper(def.name)}`
				window.subtitle.Text = if os.clock() < claimedUntil
					then claimedText
					elseif Input.isTouch() then `Skins work on every fish · ends in {Format.duration(
						left
					)}`
					else `{def.blurb} · pass skins work on every fish · ends in {Format.duration(left)}`
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
				deep.Visible = not paid and product ~= nil and Store.listed(product.id)
				-- The row cards
				freeHigh.Text = `{tiers} tiers · {passHighlights(def, "free")}`
				deepHigh.Text = `Everything free, plus {passHighlights(def, "paid")} · ×{Pass.paidXp} XP`
				deepLock.Visible = not paid
				deepWho.Text = if paid
					then "Yours this season: every skin works on all your fish"
					else `Unlock for {if priceText ~= "" then priceText else "Robux"} · skins work on all your fish`
				deepChip.Text = if paid then "UNLOCKED" else "LOCKED"
				deepChip.TextColor3 = if paid then Ui.color.safe else Ui.color.haul
				-- The tiers: built once a season, repainted every tick
				local key = `{pass.season or 1}:{tiers}`
				if builtFor ~= key then
					builtFor = key
					build(def, tiers)
				end
				for i, column in columns do
					local unlocked = i <= tier
					local current = i == tier + 1
					column.number.TextColor3 = if current
						then Ui.color.haul
						elseif unlocked then Ui.color.text
						else Ui.color.muted
					column.fill.Size = UDim2.fromScale(
						if unlocked then 1 elseif current then math.clamp(into / per, 0, 1) * 0.5 else 0,
						1
					)
					column.node.BackgroundColor3 = if unlocked then Ui.color.haul else Ui.color.track
					local freeClaimed = i <= (pass.claimedFree or 0)
					paint(column.free, freeClaimed, unlocked and not freeClaimed, false)
					local paidClaimed = paid and i <= (pass.claimedPaid or 0)
					paint(column.paid, paidClaimed, paid and unlocked and not paidClaimed, not paid)
				end
				-- Open on the tier being worked toward
				if not passScrolled then
					passScrolled = true
					strip.CanvasPosition =
						Vector2.new(math.max(0, (tier - 1) * (COLUMN + GAP) * canvasScale()), 0)
				end
				attachVisible()
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
-- the Catch Logbook and its skin goals, today's bounties, the Catch of the Week
-- with the weekly leaderboards, and the Tide Clock's forecast.
local LOG_TABS = { "Catch Log", "Bounties", "Weekly", "Tides", "Places" }
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

-- The Catch Logbook (owner, 2026-10-18: "We want a catch logbook that shows the
-- largest they have caught and they can track total gold/crystal/silver etc that they
-- have for each fish. They will need atleast 10 gold of 5 different species to unlock
-- the skin. Once the skin is unlocked, it is unlocked for all of their fish"): the
-- skin goals across the top (your fish in each skin, how far along it is, which
-- species count), then an entry per prey species, straight from Config/Prey so a new
-- species turns up by itself (a photo, a dark ??? until it's caught; where it swims;
-- its biggest; a cell per rarity with how many, the biggest of that rarity and how it
-- stands toward that skin), then how often each rarity swims.
type CatchRarity = typeof(Config.Catch.rarities[1])

local LOG_COLUMNS: { string } = { "Normal" }
for _, rarity in Config.Catch.rarities do
	table.insert(LOG_COLUMNS, rarity.id)
end
local LOG_ENTRY = 96 -- an entry's height
local LOG_CELL = 96 -- a rarity cell's width
local LOG_GAP = 6
local LOG_CELLS_X = 250 -- where the cells start (856 - 6 × 102 + 6)
local GOAL_W, GOAL_H, GOAL_GAP = 164, 220, 9

-- Where each prey species swims: its schools' biomes, most schools first (once)
local preyWhere: { [string]: string }? = nil
local function whereSwims(preyId: string): string
	local known = preyWhere
	if known == nil then
		local counts: { [string]: { [string]: number } } = {}
		for _, school in Schools.list do
			local biome = Biomes.at(school.center)
			if biome then
				local byBiome = counts[school.prey] or {}
				counts[school.prey] = byBiome
				byBiome[biome.name] = (byBiome[biome.name] or 0) + 1
			end
		end
		local made: { [string]: string } = {}
		for id, byBiome in counts do
			local names: { string } = {}
			for name in byBiome do
				table.insert(names, name)
			end
			table.sort(names, function(a, b)
				if byBiome[a] ~= byBiome[b] then
					return byBiome[a] > byBiome[b]
				end
				return a < b
			end)
			made[id] = table.concat(names, " · ")
		end
		preyWhere = made
		known = made
	end
	return (known :: { [string]: string })[preyId] or "the open sea"
end

local function preyName(preyId: string): string
	local prey = Config.Prey.byId[preyId]
	return if prey then prey.name else preyId
end

-- A see-through button over a whole card or entry, so a controller can walk them
-- (the list itself isn't selectable)
local function selectOver(frame: GuiObject, onPick: (() -> ())?)
	local hit = Instance.new("TextButton")
	hit.Name = "Select"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = frame.ZIndex + 6
	hit.Selectable = true
	hit.Parent = frame
	if onPick then
		hit.Activated:Connect(onPick)
	end
end

-- A skin goal's card: a photo of your fish in the skin, the rule, how many species
-- are done, which ones count and the nearest to counting
local function goalCard(parent: Frame, index: number, rarity: CatchRarity, s: any)
	local skin = Config.Shades.byId[rarity.skin]
	local owned = typeof(s.shades) == "table" and s.shades[rarity.skin] == true
	local rule = rarity.unlock
	local done, counted, _, counts = Catch.goal(s.catchLog, rarity.id)
	local card = Instance.new("Frame")
	card.Name = `Goal{rarity.id}`
	card.Size = UDim2.fromOffset(GOAL_W, GOAL_H)
	card.Position = UDim2.fromOffset((index - 1) * (GOAL_W + GOAL_GAP), 0)
	card.BackgroundColor3 = Ui.color.track
	card.BackgroundTransparency = 0.3
	card.BorderSizePixel = 0
	Ui.corner(card, UDim.new(0, 10))
	Ui.stroke(card, rarity.color, if owned then 0.15 else 0.6, if owned then 2 else 1)
	local visual = Instance.new("Frame")
	visual.Name = "Visual"
	visual.BackgroundColor3 = Color3.new(1, 1, 1)
	visual.BackgroundTransparency = 0.1
	visual.BorderSizePixel = 0
	visual.ClipsDescendants = true
	visual.Position = UDim2.fromOffset(6, 6)
	visual.Size = UDim2.new(1, -12, 0, 104)
	Ui.corner(visual, UDim.new(0, 8))
	local backdrop = Instance.new("UIGradient")
	backdrop.Rotation = 90
	backdrop.Color = ColorSequence.new(rarity.color:Lerp(Ui.color.panel, 0.6), Ui.color.panelFoot)
	backdrop.Parent = visual
	visual.Parent = card
	if skin then
		CardPhoto.new(
			visual,
			{ id = skin.id, kind = "shade", name = skin.name, tier = skin.tier },
			rarity.color
		)
	end
	-- (once won it's every fish's, the ones to come too: said on every card)
	local chip = Ui.chip(
		visual,
		"EveryFish",
		if owned then "✓ EVERY FISH" else "FOR EVERY FISH",
		if owned then Ui.color.safe else rarity.color,
		18
	)
	chip.Position = UDim2.fromOffset(6, 6)
	chip.ZIndex = visual.ZIndex + 4
	Ui.label(
		card,
		"Title",
		`{string.upper(if skin then skin.name else rarity.name)} SKIN`,
		Ui.FONT_HEAVY,
		15,
		rarity.color,
		UDim2.new(1, -16, 0, 18),
		UDim2.fromOffset(10, 114)
	)
	Ui.label(
		card,
		"Rule",
		`{rule.each} {rarity.name} × {rule.species} species`,
		Ui.FONT_SEMI,
		12,
		Ui.color.muted,
		UDim2.new(1, -16, 0, 16),
		UDim2.fromOffset(10, 133)
	)
	local _, fill = Ui.bar(card, "Progress", UDim2.new(1, -20, 0, 6), UDim2.fromOffset(10, 154), rarity.color)
	fill.Size = UDim2.fromScale(if owned then 1 else math.clamp(done / rule.species, 0, 1), 1)
	Ui.label(
		card,
		"Count",
		if owned then "✓ every fish has it" else `{math.min(done, rule.species)} / {rule.species} species`,
		Ui.FONT_BOLD,
		13,
		if owned then Ui.color.safe else Ui.color.text,
		UDim2.new(1, -16, 0, 16),
		UDim2.fromOffset(10, 164)
	)
	-- Which species count, then the nearest one that doesn't yet
	local names: { string } = {}
	for i, preyId in counted do
		if i > 3 then
			table.insert(names, `+{#counted - 3}`)
			break
		end
		table.insert(names, preyName(preyId))
	end
	local nextId, nextCount = nil :: string?, 0
	for preyId, n in counts do
		if n < rule.each and (n > nextCount or (n == nextCount and nextId and preyId < nextId)) then
			nextId, nextCount = preyId, n
		end
	end
	local lines: { string } = {}
	if #names > 0 then
		table.insert(lines, `✓ {table.concat(names, ", ")}`)
	end
	if nextId and not owned then
		table.insert(lines, `next: {preyName(nextId)} {nextCount}/{rule.each}`)
	end
	if #lines == 0 then
		table.insert(
			lines,
			if rarity.tide
				then "Prism Tides only: 03, 09, 15, 21 UTC"
				else `Catch {rarity.name} fish of any kind`
		)
	end
	local detail = Ui.label(
		card,
		"Species",
		table.concat(lines, "\n"),
		Ui.FONT,
		11,
		Ui.color.muted,
		UDim2.new(1, -16, 0, 32),
		UDim2.fromOffset(10, 183)
	)
	detail.TextWrapped = true
	detail.TextYAlignment = Enum.TextYAlignment.Top
	card.Parent = parent
	selectOver(card, if owned then MenuController.openWardrobe else nil)
end

-- One prey species' entry: its photo, name, where it swims, its biggest, and a cell
-- per rarity
local function logEntry(
	list: ScrollingFrame,
	order: number,
	prey: typeof(Config.Prey.list[1]),
	counts: { [string]: number },
	best: { [string]: number },
	rowDone: boolean
)
	local caught = false
	local biggest = 0
	for _, n in counts do
		if n > 0 then
			caught = true
		end
	end
	for _, kg in best do
		biggest = math.max(biggest, kg)
	end
	local frame = Instance.new("Frame")
	frame.Name = `Log{prey.id}`
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, -8, 0, LOG_ENTRY)
	frame.BackgroundColor3 = Ui.color.track
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	Ui.corner(frame, UDim.new(0, 10))
	local holder = Instance.new("Frame")
	holder.Name = "Picture"
	holder.Size = UDim2.fromOffset(112, 80)
	holder.Position = UDim2.fromOffset(8, 8)
	holder.BackgroundColor3 = Color3.new(1, 1, 1)
	holder.BackgroundTransparency = 0.1
	holder.BorderSizePixel = 0
	holder.ClipsDescendants = true
	Ui.corner(holder, UDim.new(0, 8))
	local backdrop = Instance.new("UIGradient")
	backdrop.Rotation = 90
	backdrop.Color = if caught
		then ColorSequence.new(Color3.fromRGB(70, 118, 140), Color3.fromRGB(14, 34, 50))
		else ColorSequence.new(Color3.fromRGB(44, 70, 86), Color3.fromRGB(12, 24, 34))
	backdrop.Parent = holder
	holder.Parent = frame
	PreyPhoto.attach(holder, prey.id, not caught, list)
	Ui.label(
		frame,
		"Name",
		if not caught then "???" elseif rowDone then `{prey.name}  ✓` else prey.name,
		Ui.FONT_HEAVY,
		16,
		if not caught then Ui.color.muted elseif rowDone then Ui.color.haul else Ui.color.text,
		UDim2.fromOffset(116, 20),
		UDim2.fromOffset(128, 8)
	)
	local where = Ui.label(
		frame,
		"Where",
		whereSwims(prey.id),
		Ui.FONT,
		11,
		Ui.color.muted,
		UDim2.fromOffset(116, 30),
		UDim2.fromOffset(128, 30)
	)
	where.TextWrapped = true
	where.TextYAlignment = Enum.TextYAlignment.Top
	Ui.label(
		frame,
		"Biggest",
		if biggest > 0 then `BIGGEST {Format.catchMass(biggest)}` else "not caught yet",
		Ui.FONT_BOLD,
		12,
		if biggest > 0 then Ui.color.haul else Ui.color.muted,
		UDim2.fromOffset(116, 16),
		UDim2.fromOffset(128, 70)
	)
	for i, id in LOG_COLUMNS do
		local rarity = Config.Catch.byId[id]
		local count = counts[id] or 0
		local color = if rarity then rarity.color else Ui.color.muted
		local cell = Instance.new("Frame")
		cell.Name = id
		cell.Size = UDim2.fromOffset(LOG_CELL, 80)
		cell.Position = UDim2.fromOffset(LOG_CELLS_X + (i - 1) * (LOG_CELL + LOG_GAP), 8)
		cell.BackgroundColor3 = if count > 0 then color else Ui.color.panel
		cell.BackgroundTransparency = if count > 0 then 0.76 else 0.5
		cell.BorderSizePixel = 0
		Ui.corner(cell, UDim.new(0, 8))
		local qualifies = rarity ~= nil and count >= rarity.unlock.each
		if qualifies then
			Ui.stroke(cell, color, 0.1, 1.5)
		end
		local function centred(name: string, text: string, font: Font, size: number, tint: Color3, y: number)
			local label = Ui.label(
				cell,
				name,
				text,
				font,
				size,
				tint,
				UDim2.new(1, 0, 0, size + 4),
				UDim2.fromOffset(0, y)
			)
			label.TextXAlignment = Enum.TextXAlignment.Center
		end
		centred("Rarity", if rarity then string.upper(rarity.name) else "PLAIN", Ui.FONT_BOLD, 11, color, 4)
		centred(
			"Count",
			if count > 0 then `×{Ui.number(count)}` else "—",
			Ui.FONT_HEAVY,
			20,
			if count > 0 then Ui.color.text else Ui.color.muted,
			19
		)
		local bestText = if count > 0 and best[id]
			then Format.catchMass(best[id])
			elseif rarity and rarity.tide and count == 0 then "Prism Tide"
			else ""
		centred("Best", bestText, Ui.FONT_SEMI, 11, Ui.color.muted, 44)
		if rarity and count > 0 then
			centred(
				"Goal",
				if qualifies then "✓ counts" else `{count}/{rarity.unlock.each} for skin`,
				Ui.FONT_SEMI,
				10,
				if qualifies then Ui.color.safe else Ui.color.muted,
				60
			)
		end
		cell.Parent = frame
	end
	frame.Parent = list
	selectOver(frame)
end

-- How often each rarity swims, and which tides bring more
local function rarityRows(list: ScrollingFrame, order: number)
	heading(list, order, "RARE FISH · spot the sparkle and the glint; the tides change how often they swim")
	for i, rarity in Config.Catch.rarities do
		local boosts: { string } = {}
		for _, tide in Config.Tides.list do
			local boost = tide.rarity[rarity.id]
			if boost and boost > 1 and tide.id ~= rarity.tide then
				local deep = if tide.id == "Biolum" and rarity.id == "Glowing"
					then ` (×{Format.number(boost * Config.Tides.deepGlow)} in the deep)`
					else ""
				table.insert(boosts, `{tide.name} ×{boost}{deep}`)
			end
		end
		local often = if rarity.tide
			then `Only in the Prism Tide: about {math.floor(20 / rarity.every + 0.5)} a tide when you hunt`
			else `About one every {rarity.every} min when you hunt`
		local more = if #boosts > 0 then ` · more in {table.concat(boosts, ", ")}` else ""
		tallRow(
			list,
			order + i,
			`Rarity{rarity.id}`,
			rarity.name,
			`{often}{more} · Haul ×{rarity.haul}`,
			nil,
			nil,
			nil,
			rarity.color
		)
	end
end

local function catchLogRows(list: ScrollingFrame)
	local s = state()
	heading(
		list,
		1,
		"SKIN GOALS · each one, once won, is every fish's: the ones you have and the ones to come"
	)
	local goals = Instance.new("Frame")
	goals.Name = "Goals"
	goals.LayoutOrder = 2
	goals.BackgroundTransparency = 1
	goals.Size = UDim2.new(1, -8, 0, GOAL_H)
	goals.Parent = list
	for i, rarity in Config.Catch.rarities do
		goalCard(goals, i, rarity, s)
	end
	local log = s.catchLog or {}
	local rows = s.logRows or {}
	local best = s.catchBest or {}
	local found = 0
	for _, prey in Config.Prey.list do
		for _, n in log[prey.id] or {} do
			if n > 0 then
				found += 1
				break
			end
		end
	end
	heading(
		list,
		10,
		`LOGBOOK · {found} / {#Config.Prey.list} species caught · a first catch pays, a full row more`
	)
	local header = Instance.new("Frame")
	header.Name = "LogHeader"
	header.LayoutOrder = 11
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, -8, 0, 18)
	for i, id in LOG_COLUMNS do
		local rarity = Config.Catch.byId[id]
		local label = Ui.label(
			header,
			id,
			if rarity then string.upper(rarity.name) else "PLAIN",
			Ui.FONT_BOLD,
			12,
			if rarity then rarity.color else Ui.color.muted,
			UDim2.fromOffset(LOG_CELL, 18),
			UDim2.fromOffset(LOG_CELLS_X + (i - 1) * (LOG_CELL + LOG_GAP), 0)
		)
		label.TextXAlignment = Enum.TextXAlignment.Center
	end
	header.Parent = list
	for i, prey in Config.Prey.list do
		logEntry(list, 100 + i, prey, log[prey.id] or {}, best[prey.id] or {}, rows[prey.id] == true)
	end
	rarityRows(list, 1000)
end

-- What the logbook shows, as one string: it's rebuilt only when this changes (the LOG
-- redraws every second for its countdowns, and the photos would start over each time)
local function logKey(): string
	local s = state()
	local parts: { string } = { tostring(s.species) }
	local log = s.catchLog or {}
	local best = s.catchBest or {}
	local rows = s.logRows or {}
	for _, prey in Config.Prey.list do
		local row = log[prey.id] or {}
		local top = best[prey.id] or {}
		for _, id in LOG_COLUMNS do
			table.insert(parts, `{row[id] or 0}:{top[id] or 0}`)
		end
		table.insert(parts, if rows[prey.id] then "1" else "0")
	end
	local shades = if typeof(s.shades) == "table" then s.shades else {}
	for _, rarity in Config.Catch.rarities do
		table.insert(parts, if shades[rarity.skin] then "1" else "0")
	end
	return table.concat(parts, ",")
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
			`It swims {rarity.name} far more often all week: hunting where {prey.name}s swim, about one every {Config.Catch.weekly.every} min. The first one you catch pays {Ui.number(
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

-- The LOG's Places page (Config/Places; owner, 2026-10-21: every landmark a named
-- place with a first-visit reward): the ones found with their story, the rest as ???
-- with their biome and what finding them pays, so there's something to go and look for
local function placeRows(list: ScrollingFrame)
	local s = state()
	local found: { [string]: boolean } = {}
	local count = 0
	if typeof(s.places) == "table" then
		for _, id in s.places do
			found[id] = true
			count += 1
		end
	end
	local places = Config.Places.list
	heading(list, 1, `PLACES {count}/{#places} · swim to one to find it; each pays once`)
	for i, place in places do
		local biome = Config.Biomes.byId[place.biome]
		local biomeName = if biome then biome.name else place.biome
		local got = found[place.id] == true
		row(
			list,
			1 + i,
			`Place{i}`,
			if got then place.name else `??? · {biomeName}`,
			if got then place.blurb else `Somewhere in the {biomeName}`,
			if got then "FOUND ✓" else rewardText(place.reward :: any),
			nil,
			nil,
			if biome then biome.color else nil
		)
	end
	heading(list, 2 + #places, `Find all {#places}: {rewardText(Config.Places.allFound :: any)} more`)
end

function MenuController.openLog(tab: string?)
	open(
		"Log",
		"Your Catch Logbook and its skin goals, bounties, the weekly race, the tides and the places you've found",
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
			local builtKey: string? = nil
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
					-- (the logbook only when what it shows changed: its photos)
					local key = if shown == "Catch Log" then logKey() else nil
					if key and key == builtKey then
						return
					end
					builtKey = key
					rerender(list, function()
						if shown == "Catch Log" then
							catchLogRows(list)
						elseif shown == "Bounties" then
							bountyRows(list)
						elseif shown == "Weekly" then
							weeklyRows(list)
						elseif shown == "Places" then
							placeRows(list)
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
	-- One line, long vendor names shrink a little: the label's spaces are
	-- non-breaking, since turning TextWrapped off would turn TextScaled off too (HB1)
	shopButton.TextScaled = true
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
	-- Within the Treasure Wheel's reach, E is the wheel's unless you're right at a
	-- counter (Config/Wheel `stallClose`; TreasureWheelController uses the same rule)
	local wheelState = ReplicatedStorage:FindFirstChild("WheelState")
	local button = if wheelState then wheelState:GetAttribute("ButtonPosition") else nil
	if best and root and typeof(button) == "Vector3" then
		local distance = (root.Position - button).Magnitude
		local atCounter = bestDistance <= Config.Wheel.stallClose and bestDistance < distance
		if distance <= Config.Wheel.reach and not atCounter then
			best = nil
		end
	end
	-- Your own den: E (Y, the phone's button) opens the den menu anywhere inside it
	-- (owner, 2026-10-17: "E does nothing in my den"); the chip shows at the pool
	local denIndex = state().denIndex
	local denSpot: Vector3? = nil
	if best == nil and root and typeof(denIndex) == "number" and denIndex > 0 then
		local pool = Layout.poolPosition(denIndex)
		if (root.Position - pool).Magnitude <= Config.Dens.hintReach then
			best = "__den"
			denSpot = pool
		elseif Layout.denAt(root.Position) == denIndex then
			best = "__den"
		end
	end
	if MenuController.building then
		best = nil
	end
	nearVendor = best
	local show = best ~= nil and current == nil
	local touch = Input.isTouch()
	-- (away from the pool the den's E works without a chip; and none over the start
	-- screen's shots: the fish waits at its pool, and the chip is always on top)
	hintGui.Enabled = show
		and not touch
		and (best ~= "__den" or denSpot ~= nil)
		and not StartController.isUp()
	shopButton.Visible = show and touch and not MenuController.stallButtonHidden
	if show and best then
		local label = if best == "__den"
			then (if touch or Input.isGamepad() then "DEN & SHOP" else "DEN & SHOP  ·  B  BUILD")
			else `SHOP · {Shop.vendorsById[best].name}`
		if touch then
			shopButton.Text = (string.gsub(label, " ", "\u{00A0}"))
		else
			local at = denSpot or counters[best]
			if at then
				hintSpot.WorldPosition = at
			end
			hintKey.Text = if Input.isGamepad() then "Y" else "E"
			hintText.Text = label
		end
	end
end

-- Whether the hint at your den's pool is up (it already says B · BUILD, so Build
-- mode's own hint stands aside: a screenshot of 2026-10-14 showed both)
function MenuController.denHintShown(): boolean
	return nearVendor == "__den" and current == nil and hintGui.Enabled
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
