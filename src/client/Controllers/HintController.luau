--!strict
-- Short hints on how hunting works, at the moment they matter (owner, 2026-10-09:
-- "needs to be clear mechanics on how to actually bite fish ... are the other fish
-- the same way or do they need to be eaten by hitting a bite key?").
--
-- The rule: anything under ~70% of your length (prey fish, shrimp, starfish, small
-- players) is swallowed just by swimming into it, like shells; a fish about your
-- size, an AI predator or a boss takes bites with the BITE button; a fish ~1.4x your
-- length can swallow you. A chip above the health bar says which, a few times a
-- session:
--
--   EAT       out of the hub, until you've swallowed a few things
--   BITE      a fish your size, a predator or a boss is at your mouth
--   DANGER    a fish big enough to swallow you is close
--   TOO BIG   a prey fish too big to swallow is at your mouth
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Size = require(ReplicatedStorage.Shared.Size)
local Input = require(script.Parent.Parent.Input)
local Ui = require(script.Parent.Parent.Ui)
local ForageController = require(script.Parent.ForageController)
local HuntController = require(script.Parent.HuntController)
local MenuController = require(script.Parent.MenuController)
local PredatorController = require(script.Parent.PredatorController)
local SchoolController = require(script.Parent.SchoolController)
local StartController = require(script.Parent.StartController)
local SwimController = require(script.Parent.SwimController)

local HintController = {}

type Kind = "eat" | "bite" | "danger" | "tooBig"
type Rule = { tag: string, color: Color3, cooldown: number, cap: number }

local RULES: { [Kind]: Rule } = {
	eat = { tag = "EAT", color = Ui.color.safe, cooldown = 45, cap = 3 },
	bite = { tag = "BITE", color = Ui.color.danger, cooldown = 30, cap = 5 },
	danger = { tag = "DANGER", color = Ui.color.danger, cooldown = 35, cap = 3 },
	tooBig = { tag = "TOO BIG", color = Ui.color.haul, cooldown = 30, cap = 3 },
}
local HOLD = 4.5 -- seconds a hint stays up

local swallowRatio = Config.Tuning.hunt.swallowRatio

local gui: ScreenGui
local chip: Frame? = nil
local chipKind: Kind? = nil
local shownAt: { [string]: number } = {}
local shownCount: { [string]: number } = {}
local swallowed = 0 -- prey and forage eaten this session
local leftHubAt: number? = nil

local function biteKey(): string
	if Input.isTouch() then
		return "BITE"
	elseif Input.isGamepad() then
		return "RB"
	end
	return "F / CLICK"
end

local function textFor(kind: Kind): string
	if kind == "eat" then
		return "Swim into smaller fish, shrimp and starfish to swallow them. No button needed."
	elseif kind == "bite" then
		return `Press {biteKey()} to bite fish your size, predators and bosses. Bites wear them down.`
	elseif kind == "danger" then
		return "That fish is big enough to swallow you. Dash away or hide!"
	end
	return "Too big to swallow yet. Eat smaller fish and grow first."
end

-- Phones: the hint line's width, wrapped to fit the room between the tutorial card
-- (its right edge 318 from the left) and the HEAL button (281 from the right), less
-- the tag and the padding
local function touchLineWidth(): number
	local width = gui.AbsoluteSize.X / Ui.scaleOf(gui)
	local half = math.min(width / 2 - 318, width / 2 - 281) - 8
	return math.clamp(half * 2 - 120, 200, 320)
end

local function hide()
	local old = chip
	if old == nil then
		return
	end
	chip = nil
	chipKind = nil
	for _, descendant in old:GetDescendants() do
		if descendant:IsA("TextLabel") then
			Ui.tween(descendant, 0.3, { TextTransparency = 1 })
		elseif descendant:IsA("Frame") then
			Ui.tween(descendant, 0.3, { BackgroundTransparency = 1 })
		elseif descendant:IsA("UIStroke") then
			Ui.tween(descendant, 0.3, { Transparency = 1 })
		end
	end
	Ui.tween(old, 0.3, { BackgroundTransparency = 1 })
	task.delay(0.35, function()
		old:Destroy()
	end)
end

local function show(kind: Kind)
	local rule = RULES[kind]
	local now = os.clock()
	if (shownCount[kind] or 0) >= rule.cap or now - (shownAt[kind] or -math.huge) < rule.cooldown then
		return
	end
	if StartController.isUp() or MenuController.isOpen() or chip then
		return
	end
	shownAt[kind] = now
	shownCount[kind] = (shownCount[kind] or 0) + 1
	local frame =
		Ui.panel(gui, "Hint", UDim2.fromOffset(0, 40), UDim2.new(0.5, 0, 1, -146), Vector2.new(0.5, 1))
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.BackgroundTransparency = 0.18
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rule.color
		stroke.Transparency = 0.35
	end
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	local tag = Instance.new("Frame")
	tag.Name = "Tag"
	tag.BackgroundColor3 = rule.color
	tag.BorderSizePixel = 0
	tag.Size = UDim2.fromOffset(0, 28)
	tag.AutomaticSize = Enum.AutomaticSize.X
	tag.LayoutOrder = 1
	Ui.corner(tag, UDim.new(0, 8))
	local tagPadding = Instance.new("UIPadding")
	tagPadding.PaddingLeft = UDim.new(0, 10)
	tagPadding.PaddingRight = UDim.new(0, 10)
	tagPadding.Parent = tag
	local tagText =
		Ui.label(tag, "Text", rule.tag, Ui.FONT_HEAVY, 15, Ui.color.panel, UDim2.fromOffset(0, 28))
	tagText.AutomaticSize = Enum.AutomaticSize.X
	tagText.TextXAlignment = Enum.TextXAlignment.Center
	tag.Parent = frame
	local line =
		Ui.label(frame, "Line", textFor(kind), Ui.FONT_SEMI, 16, Ui.color.text, UDim2.fromOffset(0, 28))
	line.AutomaticSize = Enum.AutomaticSize.X
	line.LayoutOrder = 2
	if Input.isTouch() then
		-- Phones: wrapped between the tutorial card and the HEAL button (on one line
		-- it ran over both, playtest 2026-10-09)
		frame.AutomaticSize = Enum.AutomaticSize.XY
		padding.PaddingTop = UDim.new(0, 6)
		padding.PaddingBottom = UDim.new(0, 6)
		line.AutomaticSize = Enum.AutomaticSize.Y
		line.Size = UDim2.fromOffset(touchLineWidth(), 0)
		line.TextWrapped = true
	end
	local pop = Instance.new("UIScale")
	pop.Scale = 0.8
	pop.Parent = frame
	Ui.tween(pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	chip = frame
	chipKind = kind
	task.delay(HOLD, function()
		if chip == frame then
			hide()
		end
	end)
end

local function lengthOf(character: Model): number
	local length = character:GetAttribute("Length")
	return if typeof(length) == "number" then length else 2
end

-- Every quarter second: is something worth a hint at our mouth?
local function check()
	local character = SwimController.character()
	local root = SwimController.root()
	if character == nil or root == nil or StartController.isUp() then
		return
	end
	if character:GetAttribute("InHub") == true then
		leftHubAt = nil
		return
	end
	local now = os.clock()
	leftHubAt = leftHubAt or now
	local length = SwimController.length()
	local mouth = root.CFrame:PointToWorldSpace(Size.mouthOffset(length))
	local reach = Size.reach(length)
	-- Other players: one your size is a bite, a much bigger one is a danger
	for _, player in Players:GetPlayers() do
		local other = player.Character
		local otherRoot = other and other:FindFirstChild("HumanoidRootPart")
		if player ~= Players.LocalPlayer and other and otherRoot and otherRoot:IsA("BasePart") then
			local otherLength = lengthOf(other)
			local gap = (otherRoot.Position - mouth).Magnitude - reach - otherLength * 0.4
			if not HuntController.isSafe(other) then
				if otherLength * swallowRatio > length and gap < length * 3 then
					show("danger")
					return
				elseif not Size.canSwallow(length, otherLength) and gap < length * 1.2 then
					show("bite")
					return
				end
			end
		end
	end
	-- AI predators and bosses are always bitten
	if PredatorController.nearest(mouth, reach + length * 1.2 + 2) then
		show("bite")
		return
	end
	-- Out hunting and nothing swallowed yet: say how eating works
	if swallowed < 3 and now - (leftHubAt :: number) > 4 then
		show("eat")
	end
end

function HintController.start()
	gui = Ui.screen("Hints", Players.LocalPlayer:WaitForChild("PlayerGui"), 6)
	local function ate()
		swallowed += 1
		-- Only the EAT hint has done its job; a shrimp swallowed under a DANGER chip
		-- took the warning down with it (playtest 2026-10-09)
		if chip and chipKind == "eat" and swallowed >= 3 then
			hide()
		end
	end
	SchoolController.ate:connect(ate)
	ForageController.ate:connect(ate)
	SchoolController.tooBig:connect(function()
		show("tooBig")
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.25 then
			accumulator = 0
			check()
		end
	end)
end

return HintController
