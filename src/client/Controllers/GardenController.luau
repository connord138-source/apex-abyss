--!strict
-- Your den's Coral Garden on screen (GardenService): a sign over the garden saying
-- what's grown and how fast, coral and shell pops when it pays out, and a welcome
-- back banner when it grew while you were away.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Format = require(ReplicatedStorage.Shared.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)

local GardenController = {}

local board: BillboardGui
local title: TextLabel
local line: TextLabel
local note: TextLabel
local banners: ScreenGui
local sinceFind = 1
local gardenPart: BasePart? = nil -- the sign's adornee (Adornee is typed non-nil)

local function state(): { [string]: any }
	return ClientState.current or {}
end

-- Your own den's garden (rebuilt as it grows, so it's looked up again)
local function findGarden(): BasePart?
	local index = state().denIndex
	if typeof(index) ~= "number" or index <= 0 then
		return nil
	end
	local world = workspace:FindFirstChild("World")
	local hub = world and world:FindFirstChild("Hub")
	local den = hub and hub:FindFirstChild(`DenBase{index}`)
	local garden = den and den:FindFirstChild("Garden")
	local sand = garden and garden:FindFirstChild("Sand")
	return if sand and sand:IsA("BasePart") then sand else nil
end

local function buildBoard(playerGui: Instance)
	board = Instance.new("BillboardGui")
	board.Name = "CoralGarden"
	board.Size = UDim2.fromOffset(230, 70)
	board.StudsOffsetWorldSpace = Vector3.new(0, 6.5, 0)
	board.MaxDistance = 70
	board.LightInfluence = 0
	board.AlwaysOnTop = false
	board.ResetOnSpawn = false
	title = Ui.label(
		board,
		"Title",
		"CORAL GARDEN",
		Ui.FONT_HEAVY,
		17,
		Color3.fromRGB(255, 150, 160),
		UDim2.new(1, 0, 0, 22)
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextStrokeTransparency = 0.5
	line = Ui.label(
		board,
		"Line",
		"",
		Ui.FONT_BOLD,
		15,
		Ui.color.text,
		UDim2.new(1, 0, 0, 20),
		UDim2.fromOffset(0, 22)
	)
	line.TextXAlignment = Enum.TextXAlignment.Center
	line.TextStrokeTransparency = 0.55
	note = Ui.label(
		board,
		"Note",
		"",
		Ui.FONT_SEMI,
		13,
		Ui.color.muted,
		UDim2.new(1, 0, 0, 18),
		UDim2.fromOffset(0, 44)
	)
	note.TextXAlignment = Enum.TextXAlignment.Center
	note.TextStrokeTransparency = 0.6
	board.Parent = playerGui
end

local function refresh()
	local garden = state().garden
	if typeof(garden) ~= "table" then
		return
	end
	line.Text = `{Ui.number(garden.coral)} coral · {Ui.number(garden.shells)} shells`
	if garden.resting then
		note.Text = `Resting here: ×{garden.rest} growth, collected every minute`
	elseif garden.coral >= garden.capCoral then
		note.Text = "Full · swim in to collect"
	else
		local perHour = math.max(garden.coralPerHour, 1)
		local hours = (garden.capCoral - garden.coral) / perHour
		note.Text = `+{Ui.number(perHour)}/h · full in {Format.duration(hours * 3600)}`
	end
end

-- A rising "+48 CORAL" over the garden
local function pop(text: string, color: Color3, delay: number)
	local at = gardenPart
	if at == nil then
		return
	end
	task.delay(delay, function()
		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(200, 30)
		tag.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		tag.LightInfluence = 0
		tag.MaxDistance = 80
		tag.Adornee = at
		local label = Ui.label(tag, "Text", text, Ui.FONT_HEAVY, 20, color, UDim2.fromScale(1, 1))
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextStrokeTransparency = 0.5
		tag.Parent = board.Parent
		Ui.tween(tag, 1.6, { StudsOffsetWorldSpace = Vector3.new(0, 8, 0) })
		Ui.tween(label, 1.6, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.delay(1.7, function()
			tag:Destroy()
		end)
	end)
end

-- "WELCOME BACK": what grew while you were away
local function welcome(summary: { [string]: any })
	local holder = Instance.new("Frame")
	holder.Name = "Welcome"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.3)
	holder.Size = UDim2.fromOffset(640, 100)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.7
	scale.Parent = holder
	local heading =
		Ui.label(holder, "Title", "WELCOME BACK", Ui.FONT_HEAVY, 40, Ui.color.haul, UDim2.new(1, 0, 0, 46))
	heading.TextXAlignment = Enum.TextXAlignment.Center
	heading.TextStrokeTransparency = 0.55
	local parts: { string } = {}
	if (summary.coral or 0) > 0 then
		table.insert(parts, `+{Ui.number(summary.coral)} coral`)
	end
	if (summary.shells or 0) > 0 then
		table.insert(parts, `+{Ui.number(summary.shells)} shells`)
	end
	local sub = Ui.label(
		holder,
		"Sub",
		`Your Coral Garden grew while you were away ({Format.duration(summary.away)}): {table.concat(
			parts,
			" · "
		)}`,
		Ui.FONT_BOLD,
		19,
		Ui.color.text,
		UDim2.new(1, 0, 0, 26),
		UDim2.fromOffset(0, 50)
	)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.TextStrokeTransparency = 0.6
	holder.Parent = banners
	Ui.tween(scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(4.5, function()
		Ui.tween(heading, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
		Ui.tween(sub, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.wait(0.55)
		holder:Destroy()
	end)
end

local function onCollected(summary: { [string]: any })
	local coral = typeof(summary.coral) == "number" and summary.coral or 0
	local shells = typeof(summary.shells) == "number" and summary.shells or 0
	if coral > 0 then
		pop(`+{Ui.number(coral)} CORAL`, Color3.fromRGB(255, 150, 160), 0)
	end
	if shells > 0 then
		pop(`+{shells} SHELL{if shells == 1 then "" else "S"}`, Color3.fromRGB(242, 228, 204), 0.35)
	end
	if typeof(summary.away) == "number" then
		Sfx.play("Bank", { volume = 0.6 })
		welcome(summary)
	else
		Sfx.play("Shell", { volume = 0.45 })
	end
end

function GardenController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	buildBoard(playerGui)
	banners = Ui.screen("GardenBanner", playerGui, 9)
	ClientState.changed:connect(refresh)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local collected = remotes:WaitForChild("GardenCollected") :: RemoteEvent
	collected.OnClientEvent:Connect(onCollected)
	RunService.Heartbeat:Connect(function(dt)
		sinceFind += dt
		local lost = gardenPart ~= nil and (gardenPart :: BasePart).Parent == nil
		if sinceFind >= 1 or lost then
			sinceFind = 0
			gardenPart = findGarden()
			board.Adornee = gardenPart :: any
			board.Enabled = gardenPart ~= nil
		end
	end)
end

return GardenController
