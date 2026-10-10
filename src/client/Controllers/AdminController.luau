--!strict
-- The owner's admin panel: an ADMIN button in the bottom-left corner, only for
-- players the server marked as admins (Admin.luau). Every button asks the server,
-- which checks again who is asking, runs it (AdminActions) and answers with a line
-- of text shown at the bottom of the panel. Pick who it applies to at the top: you,
-- everyone, or one player in the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent.Parent.Ui)

local AdminController = {}

local ROW = 44
local SUFFIXES: { [string]: number } = { k = 1e3, m = 1e6, b = 1e9 }

local gui: ScreenGui
local window: Frame
local list: ScrollingFrame
local resultLabel: TextLabel
local targetLabel: TextLabel
local target: any = "me"
local remote: RemoteFunction

-- "1.5k", "250m" or "1000" → a number (nil if it isn't one)
local function parseAmount(text: string): number?
	local cleaned = text:gsub("[%s,]", ""):lower()
	local number, suffix = cleaned:match("^([%d%.e%+%-]+)(%a*)$")
	local value = if number then tonumber(number) else nil
	if value == nil then
		return nil
	end
	if suffix ~= "" then
		local multiplier = SUFFIXES[suffix :: string]
		if multiplier == nil then
			return nil
		end
		value *= multiplier
	end
	return value
end

local function ask(action: string, ...: any)
	local args = table.pack(...)
	task.spawn(function()
		local ok, result = pcall(function()
			return remote:InvokeServer(action, target, table.unpack(args, 1, args.n))
		end)
		resultLabel.Text = if ok then tostring(result) else `Failed: {tostring(result)}`
	end)
end

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function header(text: string)
	local label = Ui.label(list, "Header", text, Ui.FONT_HEAVY, 14, Ui.color.haul, UDim2.new(1, -12, 0, 26))
	label.LayoutOrder = nextOrder()
end

local function row(title: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = title
	frame.BackgroundColor3 = Ui.color.track
	frame.BackgroundTransparency = 0.5
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, -12, 0, ROW)
	frame.LayoutOrder = nextOrder()
	Ui.corner(frame, UDim.new(0, 8))
	local label = Ui.label(
		frame,
		"Title",
		title,
		Ui.FONT_BOLD,
		14,
		Ui.color.text,
		UDim2.fromOffset(190, ROW),
		UDim2.fromOffset(12, 0)
	)
	label.TextYAlignment = Enum.TextYAlignment.Center
	frame.Parent = list
	return frame
end

local function textBox(parent: Frame, placeholder: string, x: number, width: number): TextBox
	local box = Instance.new("TextBox")
	box.Name = "Input"
	box.PlaceholderText = placeholder
	box.Text = ""
	box.ClearTextOnFocus = false
	box.FontFace = Ui.FONT
	box.TextSize = 14
	box.TextColor3 = Ui.color.text
	box.PlaceholderColor3 = Ui.color.muted
	box.BackgroundColor3 = Ui.color.panel
	box.BorderSizePixel = 0
	box.Size = UDim2.fromOffset(width, 30)
	box.Position = UDim2.new(0, x, 0.5, -15)
	Ui.corner(box, UDim.new(0, 6))
	Ui.stroke(box)
	box.Parent = parent
	return box
end

local function button(
	parent: Frame,
	text: string,
	x: number,
	width: number,
	style: Ui.ButtonStyle?
): TextButton
	return Ui.button(
		parent,
		text,
		text,
		UDim2.fromOffset(width, 32),
		UDim2.new(0, x, 0.5, -16),
		style or "primary"
	)
end

-- A row with one amount box and a button
local function amountRow(title: string, placeholder: string, action: string, min: number, buttonText: string?)
	local frame = row(title)
	local box = textBox(frame, placeholder, 210, 150)
	local go = button(frame, buttonText or "GO", 370, 90)
	go.Activated:Connect(function()
		local amount = parseAmount(box.Text)
		if amount == nil or amount < min then
			resultLabel.Text = `Type a number (at least {min})`
			return
		end
		ask(action, amount)
	end)
end

-- A row with a cycling pick (tap to step through options) and a button
local function pickRow(
	title: string,
	options: { { label: string, value: any } },
	action: string,
	buttonText: string?,
	extraBox: string?
)
	local frame = row(title)
	local index = 1
	local pick = button(frame, options[1].label, 210, 190, "secondary")
	pick.Activated:Connect(function()
		index = index % #options + 1
		pick.Text = options[index].label
	end)
	local box: TextBox? = nil
	local goX = 410
	if extraBox then
		box = textBox(frame, extraBox, 410, 90)
		goX = 510
	end
	local go = button(frame, buttonText or "GO", goX, 90)
	go.Activated:Connect(function()
		if box then
			local amount = parseAmount(box.Text)
			ask(action, options[index].value, amount or 1)
		else
			ask(action, options[index].value)
		end
	end)
end

local function actionRow(title: string, action: string, buttonText: string, style: Ui.ButtonStyle?)
	local frame = row(title)
	local go = button(frame, buttonText, 210, 150, style)
	go.Activated:Connect(function()
		ask(action)
	end)
end

local function textRow(title: string, placeholder: string, action: string)
	local frame = row(title)
	local box = textBox(frame, placeholder, 210, 190)
	local go = button(frame, "SET", 410, 90)
	go.Activated:Connect(function()
		ask(action, box.Text)
	end)
end

local function build()
	window =
		Ui.panel(gui, "Admin", UDim2.fromOffset(640, 560), UDim2.new(0.5, 0, 0.5, 0), Vector2.new(0.5, 0.5))
	window.BackgroundTransparency = 0.05
	window.Visible = false
	local title = Ui.label(
		window,
		"Title",
		"ADMIN",
		Ui.FONT_HEAVY,
		22,
		Ui.color.text,
		UDim2.fromOffset(200, 30),
		UDim2.fromOffset(16, 10)
	)
	title.TextYAlignment = Enum.TextYAlignment.Center
	local close =
		Ui.button(window, "Close", "X", UDim2.fromOffset(36, 32), UDim2.new(1, -46, 0, 10), "danger")
	close.Activated:Connect(function()
		window.Visible = false
	end)
	-- Who it applies to
	targetLabel = Ui.label(
		window,
		"Target",
		"Applies to: ME",
		Ui.FONT_BOLD,
		14,
		Ui.color.accent,
		UDim2.fromOffset(300, 30),
		UDim2.fromOffset(220, 10)
	)
	targetLabel.TextYAlignment = Enum.TextYAlignment.Center
	local function setTarget(value: any, text: string)
		target = value
		targetLabel.Text = `Applies to: {text}`
	end
	local me = Ui.button(window, "Me", "ME", UDim2.fromOffset(60, 28), UDim2.fromOffset(16, 48), "secondary")
	me.Activated:Connect(function()
		setTarget("me", "ME")
	end)
	local all =
		Ui.button(window, "All", "ALL", UDim2.fromOffset(60, 28), UDim2.fromOffset(84, 48), "secondary")
	all.Activated:Connect(function()
		setTarget("all", "EVERYONE")
	end)
	local other = Ui.button(
		window,
		"Next",
		"NEXT PLAYER",
		UDim2.fromOffset(140, 28),
		UDim2.fromOffset(152, 48),
		"secondary"
	)
	local otherIndex = 0
	other.Activated:Connect(function()
		local players = Players:GetPlayers()
		otherIndex = otherIndex % #players + 1
		local picked = players[otherIndex]
		setTarget(picked.UserId, picked.DisplayName)
	end)

	list = Ui.list(window)
	list.Position = UDim2.fromOffset(12, 84)
	list.Size = UDim2.new(1, -24, 1, -130)
	resultLabel = Ui.label(
		window,
		"Result",
		"",
		Ui.FONT_SEMI,
		14,
		Ui.color.haul,
		UDim2.new(1, -32, 0, 36),
		UDim2.new(0, 16, 1, -42)
	)
	resultLabel.TextWrapped = true

	header("CORAL · SHELLS · LEVEL")
	amountRow("Add coral (negative takes)", "e.g. 5000 or 2k", "addCoral", -1e12, "ADD")
	amountRow("Set coral", "amount", "setCoral", 0, "SET")
	amountRow("Add shells", "amount", "addShells", 1, "ADD")
	amountRow("Set level (respawns)", "1–100", "setLevel", 1, "SET")
	amountRow("Add Haul (kg)", "kg", "feed", 1, "FEED")

	header("UNLOCKS · ITEMS")
	local biomes: { { label: string, value: any } } = {}
	for _, biome in Config.Biomes.list do
		table.insert(biomes, { label = biome.name, value = biome.id })
	end
	pickRow("DNA", biomes, "dna", "GIVE", "amount")
	local species: { { label: string, value: any } } = { { label = "All species", value = "all" } }
	for _, def in Config.Species.list do
		table.insert(species, { label = def.name, value = def.id })
	end
	pickRow("Unlock species", species, "unlockSpecies", "UNLOCK")
	actionRow("Every shade, part and variant", "allShades", "GIVE ALL")
	local charms: { { label: string, value: any } } = {}
	for _, def in Config.Shop.charms do
		table.insert(charms, { label = def.name, value = def.id })
	end
	pickRow("Charm", charms, "charm", "GIVE", "×")
	amountRow("Kelp Wraps", "amount", "wraps", 1, "GIVE")
	local trophies: { { label: string, value: any } } = {}
	for _, def in Config.Bosses.list do
		table.insert(trophies, { label = def.rewards.currencyName, value = def.rewards.trophyCurrency })
	end
	pickRow("Boss trophies", trophies, "trophies", "GIVE", "amount")
	local maps: { { label: string, value: any } } = {}
	for _, tier in Config.Treasure.tiers do
		table.insert(maps, { label = `{tier.name} map`, value = tier.id })
	end
	pickRow("Treasure map", maps, "giveMap", "GIVE")
	textRow("Title (blank takes it off)", "e.g. Megalodon Slayer", "title")

	header("FISH")
	actionRow("Heal fully", "heal", "HEAL", "secondary")
	actionRow("Get eaten (lose the Haul)", "kill", "EAT", "danger")
	actionRow("Restart the tutorial", "resetTutorial", "RESTART", "secondary")
	actionRow("Finish the tutorial (species select)", "finishTutorial", "FINISH", "secondary")
	pickRow("Teleport to", biomes, "goTo", "GO")

	header("WORLD BOSSES")
	local bosses: { { label: string, value: any } } = { { label = "Next in rotation", value = "" } }
	for _, def in Config.Bosses.list do
		table.insert(bosses, { label = def.name, value = def.id })
	end
	pickRow("Summon now", bosses, "summonBoss", "SUMMON")
	local fractions: { { label: string, value: any } } = {
		{ label = "Take 25% off", value = 0.25 },
		{ label = "Take 50% off", value = 0.5 },
		{ label = "Leave it at 1 hp", value = 1 },
	}
	pickRow("Hurt the boss", fractions, "hurtBoss", "HURT")
	actionRow("Send the boss away", "endBoss", "DISMISS", "danger")

	header("MONETIZATION (NO ROBUX)")
	local passes: { { label: string, value: any } } = {}
	for _, pass in Config.Monetization.passes do
		table.insert(passes, { label = pass.name, value = pass.key })
	end
	pickRow("Grant a pass", passes, "grantPass", "GRANT")
	pickRow("Take a pass away", passes, "revokePass", "TAKE")
	local products: { { label: string, value: any } } = {}
	for _, product in Config.Monetization.products do
		table.insert(products, { label = product.name, value = product.key })
	end
	pickRow("Run a product's effect", products, "runProduct", "RUN")
	local perks: { { label: string, value: any } } = {
		{ label = "Premium ON", value = "premium:on" },
		{ label = "Premium OFF", value = "premium:off" },
		{ label = "Restricted ON", value = "restricted:on" },
		{ label = "Restricted OFF", value = "restricted:off" },
		{ label = "Group ON", value = "group:on" },
		{ label = "Group OFF", value = "group:off" },
	}
	pickRow("Test as (perks, policy)", perks, "perk", "SET")

	header("DAILY STREAK · CORAL GARDEN")
	actionRow("Daily: claim again today", "dailyReset", "RESET", "secondary")
	amountRow("Daily: set the streak", "days", "dailyStreak", 0, "SET")
	actionRow("Daily: miss a day (streak resets)", "dailyBreak", "BREAK", "danger")
	amountRow("Coral Garden: grow hours", "hours (max 48)", "gardenHours", 0, "GROW")

	header("TIDES · RARE CATCHES · BOUNTIES · WEEKLY")
	local tides: { { label: string, value: any } } = { { label = "Back to the clock", value = "" } }
	for _, tide in Config.Tides.list do
		table.insert(tides, { label = tide.name, value = tide.id })
	end
	pickRow("Force a tide (10 min, this server)", tides, "forceTide", "SET")
	local rarities: { { label: string, value: any } } = {}
	for _, rarity in Config.Catch.rarities do
		table.insert(rarities, { label = rarity.name, value = rarity.id })
	end
	pickRow("Turn the 10 nearest fish", rarities, "rareNear", "TURN")
	pickRow("Catch track: add catches (current fish)", rarities, "trackAdd", "ADD", "×")
	actionRow("Catch of the Week: catch it", "weeklyCatch", "CATCH", "secondary")
	pickRow("Bounties", {
		{ label = "Finish all three", value = "finish" },
		{ label = "Draw new ones", value = "redraw" },
	}, "bounties", "GO")
	local boards: { { label: string, value: any } } = {}
	for _, board in Config.Leaderboards.boards do
		table.insert(boards, { label = board.name, value = board.id })
	end
	pickRow("Leaderboard: add to my score", boards, "boardPoints", "ADD", "amount")

	header("TREASURE WHEEL")
	amountRow("Wheel: give spins", "spins", "wheelSpins", 1, "GIVE")
	local slices: { { label: string, value: any } } = {}
	for index, segment in Config.Wheel.segments do
		table.insert(slices, { label = segment.label, value = index })
	end
	pickRow("Wheel: the next spin lands on", slices, "wheelLand", "RIG")
end

function AdminController.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	gui = Ui.screen("Admin", playerGui, 20)
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin") :: RemoteFunction
	local open =
		Ui.button(gui, "Open", "ADMIN", UDim2.fromOffset(84, 30), UDim2.new(0, 16, 1, -46), "secondary")
	open.Visible = false
	local function refresh()
		open.Visible = player:GetAttribute("Admin") == true
	end
	player:GetAttributeChangedSignal("Admin"):Connect(refresh)
	refresh()
	local built = false
	open.Activated:Connect(function()
		if not built then
			built = true
			build()
		end
		window.Visible = not window.Visible
	end)
end

return AdminController
