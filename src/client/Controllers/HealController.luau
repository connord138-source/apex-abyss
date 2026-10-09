--!strict
-- Kelp Wraps on this client (Config/Tuning heal): H, LB on a pad or the HEAL button
-- on touch uses one; the HUD shows how many you carry and the cooldown; while a
-- wrap heals, your fish glows green (every client sees it: the Healing attribute).
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Ui = require(script.Parent.Parent.Ui)
local Sfx = require(script.Parent.Parent.Sfx)
local MenuController = require(script.Parent.MenuController)

local heal = Config.Tuning.heal

local HealController = {}

local gui: ScreenGui
local chip: Frame
local countLabel: TextLabel
local cooldownFill: Frame
local healButton: TextButton? = nil -- phones: the count and the cooldown are on it
local glows: { [Model]: Highlight } = {}

local function count(): number
	local s = ClientState.current
	local charms = if s then s.charms else nil
	return if typeof(charms) == "table" then charms.KelpWrap or 0 else 0
end

local function use()
	if MenuController.isOpen() then
		return
	end
	if count() < 1 then
		return
	end
	ClientState.request("UseWrap")
end

-- A green glow on any fish that's healing (and off again when it stops)
local function updateGlows()
	local now = Timing.clock()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character == nil then
			continue
		end
		local healing = character:GetAttribute("Healing")
		local active = typeof(healing) == "number" and healing > now
		local glow = glows[character]
		if active and not glow then
			if player == Players.LocalPlayer then
				Sfx.play("Heal", { volume = 0.6 })
			end
			local made = Instance.new("Highlight")
			made.Name = "HealGlow"
			made.FillColor = Color3.fromRGB(120, 255, 160)
			made.FillTransparency = 0.75
			made.OutlineColor = Color3.fromRGB(170, 255, 190)
			made.OutlineTransparency = 0.2
			made.DepthMode = Enum.HighlightDepthMode.Occluded
			made.Parent = character
			glows[character] = made
		elseif not active and glow then
			glow:Destroy()
			glows[character] = nil
		end
	end
	for character, glow in glows do
		if character.Parent == nil then
			glow:Destroy()
			glows[character] = nil
		end
	end
end

local function step()
	local held = count()
	-- Phones show the count and cooldown on the HEAL button itself: the chip sat on
	-- BITE (playtest 2026-10-09)
	chip.Visible = held > 0 and healButton == nil
	local keyHint = if Input.isTouch() then "" elseif Input.isGamepad() then " (LB)" else " (H)"
	countLabel.Text = `{held} KELP WRAP{if held == 1 then "" else "S"}{keyHint}`
	local character = Players.LocalPlayer.Character
	local readyAt = if character then character:GetAttribute("WrapReadyAt") else nil
	local now = Timing.clock()
	local cooling = typeof(readyAt) == "number" and readyAt > now
	if cooling then
		cooldownFill.Size = UDim2.fromScale(1 - (readyAt - now) / heal.wrapCooldown, 1)
	else
		cooldownFill.Size = UDim2.fromScale(1, 1)
	end
	local button = healButton
	if button then
		button.Text = if cooling then `HEAL\n{math.ceil(readyAt - now)}s` else `HEAL\n×{held}`
		button.BackgroundTransparency = if cooling or held == 0 then 0.55 else 0
	end
	updateGlows()
end

function HealController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.screen("Heal", playerGui, 6)
	-- A small chip left of the depth gauge: the count and the cooldown bar
	-- Under the biome chip (it covered the chip's left part at 1280×720, 2026-10-09)
	chip = Ui.panel(gui, "Wraps", UDim2.fromOffset(150, 40), UDim2.new(1, -18, 0.5, 176), Vector2.new(1, 0))
	countLabel = Ui.label(
		chip,
		"Count",
		"",
		Ui.FONT_BOLD,
		13,
		Ui.color.safe,
		UDim2.new(1, -20, 0, 18),
		UDim2.fromOffset(10, 6)
	)
	local _, fill = Ui.bar(chip, "Cooldown", UDim2.new(1, -20, 0, 5), UDim2.fromOffset(10, 28), Ui.color.safe)
	cooldownFill = fill
	chip.Visible = false
	if Input.isTouch() then
		local button = Instance.new("TextButton")
		button.Name = "Heal"
		button.Text = "HEAL"
		button.FontFace = Ui.FONT_HEAVY
		button.TextSize = 13
		button.LineHeight = 0.95
		button.TextColor3 = Ui.color.panel
		button.AutoButtonColor = false
		button.Selectable = false
		button.Size = UDim2.fromOffset(62, 62)
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.new(1, -250, 1, -150)
		button.BackgroundColor3 = Ui.color.safe
		Ui.corner(button, UDim.new(1, 0))
		Ui.stroke(button, Ui.color.stroke, 0.5, 1.5)
		button.Activated:Connect(use)
		button.Parent = gui
		healButton = button
	end
	ContextActionService:BindAction("ApexHeal", function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		use()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.H, Enum.KeyCode.ButtonL1)
	RunService.RenderStepped:Connect(step)
end

return HealController
