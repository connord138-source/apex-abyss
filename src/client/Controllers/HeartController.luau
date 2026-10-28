--!strict
-- Den hearts on the visitor's side (HeartService; owner, 2026-10-28, the den
-- proposal's "Den visits that count"). Inside someone else's den a chip in the HUD's
-- hint place (where the Treasure Wheel's sits, above the health bar) reads
-- E · ADMIRE THIS DEN (Y on a pad; on phones an ADMIRE button where the stall button
-- goes) with whose den it is and its hearts; once you have, ADMIRED TODAY, and a
-- few hearts float up. The heart is drawn from frames (Ui.heart), never an emoji.
--
-- E / Y is only taken in a den that isn't yours: in your own den it opens the den
-- menu (MenuController). Who lives where comes from the owners' player attributes
-- (`DenIndex`, `DenHearts`, `DenFramed`, set by HeartService), what you admired today
-- from your state (`admired`, Shared/Hearts).
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HeartGlyph = require(ReplicatedStorage.Shared.HeartGlyph)
local Hearts = require(ReplicatedStorage.Shared.Hearts)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Tides = require(ReplicatedStorage.Shared.Tides)
local Timing = require(ReplicatedStorage.Shared.Timing)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local MenuController = require(script.Parent.MenuController)
local StartController = require(script.Parent.StartController)
local SwimController = require(script.Parent.SwimController)

local HeartController = {}

local player = Players.LocalPlayer

-- The heart before you've admired (a paler rose) and after
local HEART_DIM = Color3.fromRGB(176, 118, 134)

local hintGui: ScreenGui
local keyCap: Frame
local keyText: TextLabel
local chipHeart: Frame
local chipScale: UIScale
local words: TextLabel
local about: TextLabel
local phoneGui: ScreenGui
local phone: TextButton
local phoneHeart: Frame
local phoneStyle = ""

-- The den we're in, when it's someone else's, and its owner
local visiting: number? = nil
local owner: Player? = nil
local admiredNow = false
-- The last request: no second one for a moment, and the hearts float up when the
-- server's answer (our state's `admired`) comes back
local sent: { userId: number, at: number }? = nil

local function ownerOf(index: number): Player?
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("DenIndex") == index then
			return other
		end
	end
	return nil
end

local function admiredToday(ownerPlayer: Player): boolean
	local current = ClientState.current
	local record = if current and typeof(current.admired) == "table" then current.admired else nil
	return Hearts.admired(record, Tides.day(Timing.unix()), ownerPlayer.UserId)
end

local function admire()
	local index, found = visiting, owner
	if index == nil or found == nil or admiredNow then
		return
	end
	local last = sent
	if last and os.clock() - last.at < 1.5 then
		return
	end
	sent = { userId = found.UserId, at = os.clock() }
	ClientState.request("AdmireDen", index)
end

-- A few hearts float up from `from` (a GuiObject on screen) and fade
local function burst(gui: ScreenGui, from: GuiObject)
	local scale = Ui.scaleOf(gui)
	local centre = (from.AbsolutePosition + from.AbsoluteSize / 2) / scale
	for i = 1, 5 do
		local group = Instance.new("CanvasGroup")
		group.Name = "FloatingHeart"
		group.BackgroundTransparency = 1
		group.AnchorPoint = Vector2.new(0.5, 0.5)
		local size = math.random(16, 26)
		group.Size = UDim2.fromOffset(size + 4, size + 4)
		group.Position = UDim2.fromOffset(centre.X + math.random(-30, 30), centre.Y)
		group.Parent = gui
		local heart = Ui.heart(group, size)
		heart.AnchorPoint = Vector2.new(0.5, 0.5)
		heart.Position = UDim2.fromScale(0.5, 0.5)
		task.delay((i - 1) * 0.07, function()
			local rise = math.random(70, 120)
			Ui.tween(group, 1.1, {
				Position = UDim2.fromOffset(centre.X + math.random(-50, 50), centre.Y - rise),
				GroupTransparency = 1,
			}, Enum.EasingStyle.Sine)
			task.delay(1.2, function()
				group:Destroy()
			end)
		end)
	end
end

local function build(playerGui: Instance)
	hintGui = Ui.screen("AdmireHint", playerGui, 9)
	hintGui.Enabled = false
	local chip =
		Ui.panel(hintGui, "Chip", UDim2.fromOffset(0, 44), UDim2.new(0.5, 0, 1, -146), Vector2.new(0.5, 1))
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.BackgroundTransparency = 0.12
	local edge = chip:FindFirstChildOfClass("UIStroke")
	if edge then
		edge.Color = Ui.HEART
		edge.Transparency = 0.3
	end
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = chip
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = chip
	-- A rose key cap with its key on it (the Treasure Wheel's is gold)
	keyCap = Instance.new("Frame")
	keyCap.Name = "Key"
	keyCap.Size = UDim2.fromOffset(32, 32)
	keyCap.BackgroundColor3 = Ui.HEART
	keyCap.LayoutOrder = 1
	Ui.corner(keyCap, UDim.new(0, 8))
	keyCap.Parent = chip
	keyText = Ui.label(keyCap, "Text", "E", Ui.FONT_HEAVY, 17, Ui.color.panel, UDim2.fromScale(1, 1))
	keyText.TextXAlignment = Enum.TextXAlignment.Center
	chipHeart = Ui.heart(chip, 24, HEART_DIM)
	chipHeart.LayoutOrder = 2
	chipScale = Instance.new("UIScale")
	chipScale.Parent = chipHeart
	words = Ui.label(chip, "Text", "", Ui.FONT_HEAVY, 17, Ui.color.text, UDim2.fromOffset(0, 32))
	words.AutomaticSize = Enum.AutomaticSize.X
	words.LayoutOrder = 3
	about = Ui.label(chip, "About", "", Ui.FONT_SEMI, 14, Ui.color.muted, UDim2.fromOffset(0, 32))
	about.AutomaticSize = Enum.AutomaticSize.X
	about.LayoutOrder = 4
	-- Phones: one button where the stall button goes (no den shop in someone else's den)
	phoneGui = Ui.screen("AdmireButton", playerGui, 9)
	phone = Ui.button(
		phoneGui,
		"Admire",
		"ADMIRE",
		UDim2.fromOffset(230, 44),
		UDim2.new(1, -96, 1, -204),
		"primary"
	)
	phone.AnchorPoint = Vector2.new(1, 1)
	phone.Selectable = false
	phone.Visible = false
	-- (the heart at the left end; the words, centred, clear it)
	phoneHeart = Ui.heart(phone, 22)
	phoneHeart.AnchorPoint = Vector2.new(0, 0.5)
	phoneHeart.Position = UDim2.new(0, 12, 0.5, 0)
	phone.Activated:Connect(admire)
end

local function setPhoneStyle(style: Ui.ButtonStyle)
	if phoneStyle ~= style then
		phoneStyle = style
		Ui.setButtonStyle(phone, style)
		phone.Selectable = false
	end
end

local function update()
	local root = SwimController.root()
	local current = ClientState.current
	local own = if current and typeof(current.denIndex) == "number" then current.denIndex else 0
	local index = if root then Layout.denAt(root.Position) else nil
	local found = if index and index ~= own then ownerOf(index) else nil
	visiting = if found then index else nil
	owner = found
	local show = found ~= nil and not MenuController.isOpen() and not StartController.isUp()
	local touch = Input.isTouch()
	hintGui.Enabled = show and not touch
	phone.Visible = show and touch
	if found == nil then
		admiredNow = false
		return
	end
	local done = admiredToday(found)
	-- Just admired: the heart fills, pulses, and a few float up
	local last = sent
	if done and not admiredNow and last and last.userId == found.UserId and os.clock() - last.at < 6 then
		sent = nil
		Sfx.play("GoldenShell", { volume = 0.6 })
		chipScale.Scale = 1.6
		Ui.tween(chipScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		if show then
			burst(if touch then phoneGui else hintGui, if touch then phoneHeart else chipHeart)
		end
	end
	admiredNow = done
	local hearts = found:GetAttribute("DenHearts")
	local count = if typeof(hearts) == "number" then hearts else 0
	local framed = found:GetAttribute("DenFramed") == true
	keyCap.Visible = not done
	keyText.Text = if Input.isGamepad() then "Y" else "E"
	words.Text = if done then "ADMIRED TODAY" else "ADMIRE THIS DEN"
	local hearts = `{Hearts.short(count)} {if count == 1 then "heart" else "hearts"}`
	local top = if framed then " · a Best Dens top 3" else ""
	about.Text = `{found.DisplayName}'s den · {hearts}{top}`
	HeartGlyph.paint(chipHeart, if done then Ui.HEART else HEART_DIM)
	phone.Text = if done then "ADMIRED TODAY" else "ADMIRE THIS DEN"
	HeartGlyph.paint(phoneHeart, if done then Ui.HEART else Color3.fromRGB(255, 236, 240))
	setPhoneStyle(if done then "secondary" else "primary")
end

function HeartController.start()
	build(player:WaitForChild("PlayerGui"))
	-- E / Y admires in someone else's den (bound after the stall hint's binding, so
	-- this one is asked first and passes everywhere else, your own den included)
	ContextActionService:BindAction("ApexAdmire", function(_, inputState)
		if
			inputState ~= Enum.UserInputState.Begin
			or visiting == nil
			or admiredNow
			or MenuController.isOpen()
			or StartController.isUp()
		then
			return Enum.ContextActionResult.Pass
		end
		admire()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonY)
	task.spawn(function()
		while true do
			update()
			task.wait(0.2)
		end
	end)
end

return HeartController
