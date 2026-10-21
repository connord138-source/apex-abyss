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
local windowGui: ScreenGui -- the full map, over the HUD like a menu window
local mini: MapDraw.Map
local miniHolder: Frame
local full: MapDraw.Map? = nil
local fullWindow: Ui.Window? = nil
local whereLabel: TextLabel? = nil
local placeLabel: TextLabel? = nil -- the minimap's name bar: where you are
local NAME_BAR = 22 -- pixels under the minimap's chart for the name

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
local APEX = Color3.fromRGB(255, 204, 92)
local PODMATE = Color3.fromRGB(110, 236, 220)
local PLACE = Color3.fromRGB(240, 226, 170)

-- A named place's spot (Config/Places; the builders publish them on Workspace.Places)
local function placeSpot(id: string): Vector3?
	local folder = workspace:FindFirstChild("Places")
	local spot = if folder then folder:GetAttribute(id) else nil
	return if typeof(spot) == "Vector3" then spot else nil
end

-- The named place a point is in, if any (its `radius`)
local function placeAt(position: Vector3): typeof(Config.Places.list[1])?
	for _, place in Config.Places.list do
		local spot = placeSpot(place.id)
		if spot and (spot - position).Magnitude <= place.radius then
			return place
		end
	end
	return nil
end

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
		MapDraw.mark(map, "Den", Layout.doorFrame(denIndex).Position, DEN, "◆", 13)
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
	-- The Apex shows wherever it is: its position is published (ApexService), since
	-- its fish isn't streamed in beyond the streaming radius
	local apexId = workspace:GetAttribute("ApexUserId")
	local apexAt = workspace:GetAttribute("ApexAt")
	if typeof(apexId) == "number" and apexId ~= me.UserId and typeof(apexAt) == "Vector3" then
		local apex = Players:GetPlayerByUserId(apexId)
		local character = apex and apex.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil then
			MapDraw.mark(map, "Apex", apexAt, APEX, "★", 18)
			keep.Apex = true
		end
	end
	for _, player in Players:GetPlayers() do
		if player == me then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local id = `P{player.UserId}`
			local myPod = me:GetAttribute("Pod")
			if workspace:GetAttribute("ApexUserId") == player.UserId then
				-- The Apex shows to everyone, wherever it is (Config/Pvp `apex`)
				MapDraw.mark(map, id, Layout.mapPosition(root.Position), APEX, "★", 18)
			elseif typeof(myPod) == "number" and myPod ~= 0 and player:GetAttribute("Pod") == myPod then
				MapDraw.mark(map, id, Layout.mapPosition(root.Position), PODMATE, "•", 20)
			else
				MapDraw.mark(map, id, Layout.mapPosition(root.Position), OTHER, "•", 16)
			end
			keep[id] = true
		end
	end
	-- The named places found (the LOG's Places page): a mark on both maps, its name
	-- on the full one
	local found = if s and typeof(s.places) == "table" then s.places else nil
	if found then
		for _, id in found do
			local place = Config.Places.byId[id]
			local spot = placeSpot(id)
			if place and spot then
				local key = `Place_{id}`
				local text = if map == full then `◆ {string.upper(place.name)}` else "◆"
				MapDraw.mark(map, key, spot, PLACE, text, if map == full then 11 else 10)
				keep[key] = true
			end
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
	-- (a menu that opened over it keeps the cursor free: closing the map under the
	-- INDEX locked the cursor, so its X couldn't be clicked, PC 2026-10-19)
	if not MenuController.isOpen() then
		Input.cursorWanted = false
	end
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
	local window =
		Ui.window(windowGui, "Map", "The sea, north up · you are the arrow", Vector2.new(820, 560))
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
	legendRow(side, 230, "★", APEX, "The Apex: eat it for its bounty")
	legendRow(side, 254, "•", PODMATE, "Your podmates")
	legendRow(side, 278, "•", OTHER, "Other fish in this server")
	Ui.heading(side, "SeaHeading", "The sea", 312)
	local notes = Ui.label(
		side,
		"Notes",
		"The hub is the ring in the middle: the dens and the vendors. The pale dashed ring is the shelf's drop-off, where the shallow biomes end and the deep ones begin far below. The red ring is the edge of the sea. Each biome's level range is the level it's meant for: below it, swim carefully.",
		Ui.FONT,
		13,
		Ui.color.muted,
		UDim2.new(1, 0, 0, 150),
		UDim2.fromOffset(0, 336)
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

-- Where a point is, as a name: your den, the hub, a biome or open water
-- (`long` adds the biome's levels and the depth, for the full map)
local function placeName(position: Vector3, long: boolean): string
	local biome = Biomes.at(position)
	local depth = Config.World.surfaceY - position.Y
	-- The hub first: under it is the kelp ring or no biome, so a den read OPEN WATER
	-- (playtest 2026-10-12)
	local denHere = Layout.denAt(position)
	local s = ClientState.current
	local own = if s and typeof(s.denIndex) == "number" then s.denIndex else 0
	if denHere then
		local name = if denHere == own then "YOUR DEN" else "A DEN"
		return if long then `{name} · THE HUB · safe` else name
	elseif Layout.inHub(position) then
		return if long then "THE HUB · safe" else "THE HUB"
	end
	-- A named place before its biome (owner, 2026-10-21: the landmarks' names on the
	-- map)
	local place = placeAt(position)
	if place then
		local name = string.upper(place.name)
		return if long then `{name} · {Format.distance(depth)} down` else name
	elseif biome then
		return if long
			then `{string.upper(biome.name)} · LV {biome.minLevel}–{biome.maxLevel} · {Format.distance(
				depth
			)} down`
			else string.upper(biome.name)
	end
	return if long then `OPEN WATER · {Format.distance(depth)} down` else "OPEN WATER"
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
	-- In a den (far outside the map: Layout.denOrigin) you show at its doorway
	local onMap = Layout.mapPosition(root.Position)
	MapDraw.update(mini, onMap, heading, true)
	placeMarks(mini)
	-- The place's name under the minimap (owner, 2026-10-16: "Map needs a name of
	-- the location they are at displayed")
	local nameBar = placeLabel
	if nameBar then
		local name = placeName(root.Position, false)
		if nameBar.Text ~= name then
			nameBar.Text = name
		end
	end
	local chart = full
	if chart then
		MapDraw.update(chart, onMap, heading, false)
		placeMarks(chart)
		local label = whereLabel
		if label then
			label.Text = placeName(root.Position, true)
		end
	end
end

function MapController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.screen("Map", playerGui, 6)
	-- The full map draws at the menus' level, over the HUD: on the minimap's layer the
	-- DAILY ! and SHOP buttons beside the wallet drew over its title (PC 2026-10-19)
	windowGui = Ui.screen("MapWindow", playerGui, 10)
	local touch = Input.isTouch()
	local size = if touch then MINI_SIZE_PHONE else MINI_SIZE
	miniHolder = Ui.panel(
		gui,
		"Minimap",
		UDim2.fromOffset(size + 12, size + 12 + NAME_BAR),
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
	-- The name bar under the chart: where you are, and the key that opens the map
	local name = Ui.label(
		miniHolder,
		"Place",
		"",
		Ui.FONT_HEAVY,
		if touch then 11 else 13,
		Ui.color.accent,
		UDim2.new(1, if touch then -12 else -78, 0, NAME_BAR - 4),
		UDim2.fromOffset(7, size + 9)
	)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 6
	placeLabel = name
	if not touch then
		local hint = Ui.label(
			miniHolder,
			"Hint",
			if Input.isGamepad() then "R3 · MAP" else "M · MAP",
			Ui.FONT_BOLD,
			11,
			Ui.color.muted,
			UDim2.fromOffset(64, NAME_BAR - 4),
			UDim2.new(1, -70, 0, size + 9)
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
		-- (not over Build mode's editor: the full map no longer sits on the minimap's
		-- layer, which the editor hides)
		if inputState ~= Enum.UserInputState.Begin or Input.locked or Input.editing then
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
