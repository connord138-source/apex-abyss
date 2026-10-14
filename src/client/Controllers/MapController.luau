--!strict
-- The minimap and the full map (owner, 2026-10-12: "also need a map/mini map to
-- show people where they are"). The minimap is a small sonar chart in the HUD's
-- corner that slides under the fish (north up, the fish's arrow in the middle); a
-- click or tap on it, M on a keyboard or R3 on a controller opens the full map: the
-- whole sea with every biome named and levelled, and a legend. Both carry the same
-- markers: your den, the treasure X you're following, the boss while one is up,
-- and the other fish in the server. Shared/MapDraw draws the chart.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Biomes = require(ReplicatedStorage.Shared.Biomes)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Layout = require(ReplicatedStorage.Shared.Layout)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local MapDraw = require(script.Parent.Parent.MapDraw)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local BossController = require(script.Parent.BossController)
local ChumController = require(script.Parent.ChumController)
local MenuController = require(script.Parent.MenuController)
local StartController = require(script.Parent.StartController)
local SwimController = require(script.Parent.SwimController)

local MapController = {}

local gui: ScreenGui
local mini: MapDraw.Map
local miniHolder: Frame
local full: MapDraw.Map? = nil
local fullWindow: Ui.Window? = nil
local whereLabel: TextLabel? = nil

local MINI_SIZE = 190 -- pixels, PC and console
local MINI_SIZE_PHONE = 112
local MINI_SPAN = 520 -- studs from the fish to the minimap's edge
local FULL_SIZE = 460 -- the chart's side in the full map
local FULL_SPAN = Config.World.boundsRadius + 70

local DEN = Color3.fromRGB(255, 204, 92)
local TREASURE = Color3.fromRGB(255, 120, 90)
local BOSS = Color3.fromRGB(255, 70, 70)
local OTHER = Color3.fromRGB(226, 240, 248)
local WHALE = Color3.fromRGB(150, 214, 230)

-- The treasure site being followed, if any (the Satchel's FOLLOW)
local function treasureSite(): Vector3?
	local s = ClientState.current
	if s == nil or typeof(s.maps) ~= "table" or typeof(s.activeMap) ~= "string" or s.activeMap == "" then
		return nil
	end
	for _, map in s.maps do
		if typeof(map) == "table" and map.id == s.activeMap and typeof(map.site) == "table" then
			return Vector3.new(map.site.x, map.site.y, map.site.z)
		end
	end
	return nil
end

-- Every marker, on one chart
local function placeMarks(map: MapDraw.Map)
	local keep: { [string]: boolean } = {}
	local s = ClientState.current
	local denIndex = if s then s.denIndex else nil
	if typeof(denIndex) == "number" and denIndex > 0 then
		MapDraw.mark(map, "Den", Layout.poolPosition(denIndex), DEN, "◆", 13)
		keep.Den = true
	end
	local site = treasureSite()
	if site then
		MapDraw.mark(map, "Treasure", site, TREASURE, "X", 15)
		keep.Treasure = true
	end
	local bossAt = BossController.position()
	if bossAt then
		MapDraw.mark(map, "Boss", bossAt, BOSS, "●", 18)
		keep.Boss = true
		local mark = map.marks.Boss
		if mark and mark:IsA("TextLabel") then
			mark.TextTransparency = 0.25 + 0.25 * math.sin(os.clock() * 5)
		end
	end
	local whaleAt = ChumController.whale()
	if whaleAt then
		MapDraw.mark(map, "Whale", whaleAt, WHALE, "W", 16)
		keep.Whale = true
		local mark = map.marks.Whale
		if mark and mark:IsA("TextLabel") then
			mark.TextTransparency = 0.2 + 0.2 * math.sin(os.clock() * 3)
		end
	end
	local me = Players.LocalPlayer
	for _, player in Players:GetPlayers() do
		if player == me then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local id = `P{player.UserId}`
			MapDraw.mark(map, id, root.Position, OTHER, "•", 16)
			keep[id] = true
		end
	end
	MapDraw.prune(map, keep)
end

local function closeFull()
	local window = fullWindow
	if window == nil then
		return
	end
	fullWindow = nil
	full = nil
	whereLabel = nil
	window.frame:Destroy()
	Input.cursorWanted = false
	ContextActionService:UnbindAction("ApexCloseMap")
end

local function legendRow(parent: Instance, y: number, glyph: string, color: Color3, text: string)
	local mark = Ui.label(
		parent,
		"Mark",
		glyph,
		Ui.FONT_HEAVY,
		15,
		color,
		UDim2.fromOffset(22, 20),
		UDim2.fromOffset(0, y)
	)
	mark.TextXAlignment = Enum.TextXAlignment.Center
	mark.TextStrokeTransparency = 0.5
	Ui.label(
		parent,
		"Text",
		text,
		Ui.FONT_SEMI,
		13,
		Ui.color.text,
		UDim2.new(1, -28, 0, 20),
		UDim2.fromOffset(28, y)
	)
end

local function openFull()
	if fullWindow then
		closeFull()
		return
	end
	MenuController.close()
	local window = Ui.window(gui, "Map", "The sea, north up · you are the arrow", Vector2.new(820, 560))
	fullWindow = window
	window.close.Activated:Connect(closeFull)
	Input.cursorWanted = true
	local chart = MapDraw.new(window.content, FULL_SIZE, FULL_SIZE / (2 * FULL_SPAN), true)
	chart.frame.Position = UDim2.fromOffset(0, 0)
	full = chart
	-- The side: where you are, then a legend
	local side = Instance.new("Frame")
	side.Name = "Side"
	side.BackgroundTransparency = 1
	side.Position = UDim2.fromOffset(FULL_SIZE + 22, 0)
	side.Size = UDim2.new(1, -(FULL_SIZE + 22), 1, 0)
	side.Parent = window.content
	Ui.heading(side, "WhereHeading", "You are in", 0)
	local where = Ui.label(
		side,
		"Where",
		"",
		Ui.FONT_HEAVY,
		18,
		Ui.color.accent,
		UDim2.new(1, 0, 0, 24),
		UDim2.fromOffset(0, 24)
	)
	whereLabel = where
	Ui.heading(side, "LegendHeading", "Legend", 86)
	legendRow(side, 110, "▲", Ui.color.accent, "You, pointing where you swim")
	legendRow(side, 134, "◆", DEN, "Your den: bank your Haul there")
	legendRow(side, 158, "X", TREASURE, "The treasure map you're following")
	legendRow(side, 182, "●", BOSS, "A world boss, while one is up")
	legendRow(side, 206, "W", WHALE, "A Whale Fall: food for everyone")
	legendRow(side, 230, "•", OTHER, "Other fish in this server")
	Ui.heading(side, "SeaHeading", "The sea", 266)
	local notes = Ui.label(
		side,
		"Notes",
		"The hub is the ring in the middle: the dens and the vendors. The pale dashed ring is the shelf's drop-off, where the shallow biomes end and the deep ones begin far below. The red ring is the edge of the sea. Each biome's level range is the level it's meant for: below it, swim carefully.",
		Ui.FONT,
		13,
		Ui.color.muted,
		UDim2.new(1, 0, 0, 150),
		UDim2.fromOffset(0, 290)
	)
	notes.TextWrapped = true
	notes.TextYAlignment = Enum.TextYAlignment.Top
	local hint = Ui.label(
		side,
		"Hint",
		if Input.isTouch()
			then "Tap X to close"
			elseif Input.isGamepad() then "B or R3 closes"
			else "M or X closes",
		Ui.FONT_BOLD,
		12,
		Ui.color.muted,
		UDim2.new(1, 0, 0, 16),
		UDim2.new(0, 0, 1, -18)
	)
	hint.TextXAlignment = Enum.TextXAlignment.Right
	ContextActionService:BindActionAtPriority("ApexCloseMap", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			closeFull()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.ButtonB)
	Sfx.play("UiOpen", { volume = 0.5 })
end

function MapController.isOpen(): boolean
	return fullWindow ~= nil
end

local function step()
	if Input.locked then
		return
	end
	if fullWindow and MenuController.isOpen() then
		closeFull() -- a menu opened over it
	end
	local root = SwimController.root()
	if root == nil then
		return
	end
	local heading = root.CFrame.LookVector
	MapDraw.update(mini, root.Position, heading, true)
	placeMarks(mini)
	local chart = full
	if chart then
		MapDraw.update(chart, root.Position, heading, false)
		placeMarks(chart)
		local label = whereLabel
		if label then
			local biome = Biomes.at(root.Position)
			local depth = Config.World.surfaceY - root.Position.Y
			-- The hub first: under it is the kelp ring or no biome, so a den read
			-- OPEN WATER (playtest 2026-10-12)
			local denHere = Layout.denAt(root.Position)
			local s = ClientState.current
			local own = if s and typeof(s.denIndex) == "number" then s.denIndex else 0
			label.Text = if denHere
				then `{if denHere == own then "YOUR DEN" else "A DEN"} · THE HUB · safe`
				elseif Layout.inHub(root.Position) then "THE HUB · safe"
				elseif
					biome
				then `{string.upper(biome.name)} · LV {biome.minLevel}–{biome.maxLevel} · {Format.distance(
					depth
				)} down`
				else `OPEN WATER · {Format.distance(depth)} down`
		end
	end
end

function MapController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.screen("Map", playerGui, 6)
	local touch = Input.isTouch()
	local size = if touch then MINI_SIZE_PHONE else MINI_SIZE
	miniHolder = Ui.panel(
		gui,
		"Minimap",
		UDim2.fromOffset(size + 12, size + 12),
		UDim2.new(1, -18, 1, -18),
		Vector2.new(1, 1)
	)
	if touch then
		-- Phones: the top-right corner, under the growth chip (the bottom-right
		-- holds BITE and DASH)
		miniHolder.Position = UDim2.new(1, -12, 0, 34)
		miniHolder.AnchorPoint = Vector2.new(1, 0)
	end
	mini = MapDraw.new(miniHolder, size, size / (2 * MINI_SPAN), false)
	mini.frame.Position = UDim2.fromOffset(6, 6)
	local north = Ui.label(
		miniHolder,
		"North",
		"N",
		Ui.FONT_HEAVY,
		11,
		Ui.color.muted,
		UDim2.fromOffset(16, 14),
		UDim2.new(0.5, -8, 0, 7)
	)
	north.TextXAlignment = Enum.TextXAlignment.Center
	north.ZIndex = 6
	if not touch then
		local hint = Ui.label(
			miniHolder,
			"Hint",
			if Input.isGamepad() then "R3 · MAP" else "M · MAP",
			Ui.FONT_BOLD,
			11,
			Ui.color.muted,
			UDim2.new(1, -12, 0, 14),
			UDim2.new(0, 0, 1, -19)
		)
		hint.TextXAlignment = Enum.TextXAlignment.Right
		hint.ZIndex = 6
	end
	-- A click or tap on the minimap opens the full map
	local button = Instance.new("TextButton")
	button.Name = "Open"
	button.Text = ""
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 7
	button.Selectable = false
	button.Parent = miniHolder
	button.Activated:Connect(openFull)
	ContextActionService:BindAction("ApexMap", function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin or Input.locked then
			return Enum.ContextActionResult.Pass
		end
		openFull()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.M, Enum.KeyCode.ButtonR3)
	miniHolder.Visible = false
	StartController.afterStart(function()
		miniHolder.Visible = true
	end)
	RunService.RenderStepped:Connect(step)
end

return MapController
