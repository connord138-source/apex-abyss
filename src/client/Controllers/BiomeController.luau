--!strict
-- Where you are: a banner with the biome's name and suggested levels when you swim
-- into it, and a chip under the depth gauge while you're there. A biome above your
-- fish's level gets a red warning instead (owner: low-level players must be told
-- they're under-developed for an area and should come back later).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Biomes = require(ReplicatedStorage.Shared.Biomes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local Sfx = require(script.Parent.Parent.Sfx)
local OceanController = require(script.Parent.OceanController)
local Config = require(ReplicatedStorage.Shared.Config)
local SwimController = require(script.Parent.SwimController)

local BiomeController = {}

local SETTLE = 0.6 -- seconds in a new biome before it's announced (no flicker on edges)
local AFTER_HUB = 3.2 -- leaving the hub shows the safe-zone banner first

local gui: ScreenGui
local chip: Frame
local chipName: TextLabel
local chipLevels: TextLabel
local current: Biomes.Biome? = nil
local candidate: Biomes.Biome? = nil
local candidateSince = 0
local leftHubAt = -math.huge
local wasInHub = true

local function level(): number
	local state = ClientState.current
	return if state and typeof(state.level) == "number" then state.level else 1
end

local function speciesName(): string
	local state = ClientState.current
	return if state and typeof(state.speciesName) == "string" then state.speciesName else "fish"
end

local function banner(biome: Biomes.Biome)
	Sfx.play("Banner", { volume = 0.45 })
	local old = gui:FindFirstChild("BiomeBanner")
	if old then
		old:Destroy()
	end
	local danger = Biomes.tooLow(biome, level())
	local holder = Instance.new("Frame")
	holder.Name = "BiomeBanner"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0.18, 0)
	holder.Size = UDim2.fromOffset(640, 96)
	local bossBottom = Ui.bossBottom()
	if bossBottom > 0 then
		-- Below the boss bar (on a phone 18% down is inside it)
		local height = gui.AbsoluteSize.Y / Ui.scaleOf(gui)
		holder.Position = UDim2.new(0.5, 0, 0, math.max(height * 0.18, bossBottom + 10))
	end
	holder.BackgroundTransparency = 1
	local title = Ui.label(
		holder,
		"Title",
		string.upper(biome.name),
		Ui.FONT_HEAVY,
		40,
		if danger then Ui.color.danger else Ui.color.text,
		UDim2.new(1, 0, 0, 44)
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextStrokeTransparency = 0.5
	local text = if danger
		then `TOO DANGEROUS FOR NOW · suggested level {biome.minLevel}–{biome.maxLevel}`
		else `Suggested level {biome.minLevel}–{biome.maxLevel}`
	if biome.dark then
		text ..= "  ·  PITCH DARK · bring a light: a Deep Lantern, an Anglerfish's lure or a glowing shade"
	end
	local sub = Ui.label(
		holder,
		"Sub",
		text,
		Ui.FONT_BOLD,
		18,
		if danger then Ui.color.danger else biome.color,
		UDim2.new(1, 0, 0, 22),
		UDim2.fromOffset(0, 46)
	)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.TextStrokeTransparency = 0.6
	if danger then
		local advice = Ui.label(
			holder,
			"Advice",
			`Your {speciesName()} is level {level()}. Fish here will hunt you; come back stronger.`,
			Ui.FONT_SEMI,
			16,
			Ui.color.text,
			UDim2.new(1, 0, 0, 20),
			UDim2.fromOffset(0, 70)
		)
		advice.TextXAlignment = Enum.TextXAlignment.Center
		advice.TextStrokeTransparency = 0.6
	end
	local labels: { TextLabel } = {}
	for _, child in holder:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
			child.TextTransparency = 1
			child.TextStrokeTransparency = 1
		end
	end
	holder.Parent = gui
	for _, label in labels do
		Ui.tween(label, 0.4, { TextTransparency = 0, TextStrokeTransparency = 0.55 })
	end
	task.delay(if danger then 5 else 3, function()
		if holder.Parent == nil then
			return
		end
		for _, label in labels do
			Ui.tween(label, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
		task.wait(0.65)
		holder:Destroy()
	end)
end

local function updateChip()
	local biome = current
	chip.Visible = biome ~= nil
	if biome == nil then
		return
	end
	local danger = Biomes.tooLow(biome, level())
	chipName.Text = string.upper(biome.name)
	chipLevels.Text = `LV {biome.minLevel}–{biome.maxLevel}{if biome.dark then " · DARK" else ""}`
	chipLevels.TextColor3 = if danger then Ui.color.danger else biome.color
	local stroke = chip:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if danger then Ui.color.danger else Ui.color.stroke
		stroke.Transparency = if danger then 0.2 else 0.72
	end
end

local function step()
	local root = SwimController.root()
	if root == nil then
		return
	end
	local biome = Biomes.at(root.Position)
	local inHub = biome == nil
	-- The pitch dark of a dark biome, once you're down in it
	OceanController.setDark(
		if biome and biome.dark and root.Position.Y < Config.World.deep.floorY + 40 then 1 else 0
	)
	if wasInHub and not inHub then
		leftHubAt = os.clock()
	end
	wasInHub = inHub
	if biome ~= candidate then
		candidate = biome
		candidateSince = os.clock()
	end
	local wait = if os.clock() - leftHubAt < AFTER_HUB then AFTER_HUB else SETTLE
	if candidate ~= current and os.clock() - candidateSince >= wait then
		current = candidate
		if current then
			banner(current)
		end
		updateChip()
	end
end

function BiomeController.start()
	gui = Ui.screen("Biome", Players.LocalPlayer:WaitForChild("PlayerGui"), 6)
	chip =
		Ui.panel(gui, "BiomeChip", UDim2.fromOffset(200, 50), UDim2.new(1, -18, 0.5, 118), Vector2.new(1, 0))
	if Ui.isTouch() then
		-- Phones: above the depth gauge instead, clear of the BITE button it sat on
		-- (playtest 2026-10-07)
		chip.AnchorPoint = Vector2.new(1, 1)
		chip.Position = UDim2.new(1, -18, 0.5, -113)
	end
	chipName = Ui.label(
		chip,
		"Name",
		"",
		Ui.FONT_BOLD,
		14,
		Ui.color.text,
		UDim2.new(1, -20, 0, 18),
		UDim2.fromOffset(10, 6)
	)
	chipName.TextXAlignment = Enum.TextXAlignment.Right
	chipLevels = Ui.label(
		chip,
		"Levels",
		"",
		Ui.FONT_HEAVY,
		15,
		Ui.color.muted,
		UDim2.new(1, -20, 0, 18),
		UDim2.fromOffset(10, 26)
	)
	chipLevels.TextXAlignment = Enum.TextXAlignment.Right
	chip.Visible = false
	ClientState.changed:connect(updateChip)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.2 then
			accumulator = 0
			step()
		end
	end)
	-- A new fish starts in its den (in the hub): nothing to announce yet
	SwimController.spawned:connect(function()
		current, candidate, wasInHub = nil, nil, true
		updateChip()
	end)
end

return BiomeController
