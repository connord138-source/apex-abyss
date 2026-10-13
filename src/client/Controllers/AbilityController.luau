--!strict
-- The ability button (left click, RT, the DASH button) does what the fish you're
-- swimming as does: the Nibbler and every fish without its own ability yet Dash
-- (SwimController), and the Reef Shark has **Blood Sense** (owner, 2026-10-13:
-- "it should highlight players through surfaces as a flashing red thermal to show
-- where the other players and predators are"): for a few seconds every other fish
-- and every predator in the sea shows through rock and murk as a flashing red
-- heat signature, with a red cast over the water. It's a reveal on this client
-- only (characters and predator positions already replicate), on a cooldown.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Sfx = require(script.Parent.Parent.Sfx)
local PredatorController = require(script.Parent.PredatorController)
local SwimController = require(script.Parent.SwimController)

local AbilityController = {}

-- Blood Sense
local SENSE_SECONDS = 7
local SENSE_COOLDOWN = 24
local SENSE_REFRESH = 0.5 -- seconds between looks for new fish to mark
local HIGHLIGHT_CAP = 31 -- Roblox draws at most 31 Highlights at once
local HOT = Color3.fromRGB(255, 36, 36) -- the signature's cool end
local HOTTER = Color3.fromRGB(255, 176, 64) -- its hot end (a thermal's yellow core)
local RIM = Color3.fromRGB(255, 120, 120)

local senseUntil = 0 -- when the reveal ends
local senseReadyAt = 0 -- when it can go again
local nextRefresh = 0
local marks: { [Instance]: Highlight } = {}
local cast: ColorCorrectionEffect? = nil
local castAlpha = 0

-- Which species the player is swimming as, by the state
local function species(): string
	local s = ClientState.current
	local id = if s then s.species else nil
	return if typeof(id) == "string" then id else "Nibbler"
end

-- The ability the button fires for this fish
function AbilityController.name(): string
	return if species() == "ReefShark" then "BloodSense" else "Dash"
end

-- The ability's charge, 0..1 (1 = ready), for the HUD's bar
function AbilityController.charge(): number
	if AbilityController.name() == "BloodSense" then
		local now = os.clock()
		if now >= senseReadyAt then
			return 1
		end
		return math.clamp(1 - (senseReadyAt - now) / SENSE_COOLDOWN, 0, 0.999)
	end
	return SwimController.dashCharge
end

-- Seconds of a running reveal left (0 when none), for a chip
function AbilityController.senseLeft(): number
	return math.max(0, senseUntil - os.clock())
end

-- Everything Blood Sense marks: the other players' fish and every drawn predator,
-- nearest first, within the Highlight cap
local function targets(): { Instance }
	local root = SwimController.root()
	local from = if root then root.Position else workspace.CurrentCamera.CFrame.Position
	local found: { { instance: Instance, distance: number } } = {}
	for _, player in Players:GetPlayers() do
		if player == Players.LocalPlayer then
			continue
		end
		local character = player.Character
		local body = character and character:FindFirstChild("Body")
		local at = character and character:FindFirstChild("HumanoidRootPart")
		if character and body and at and at:IsA("BasePart") then
			table.insert(found, { instance = body, distance = (at.Position - from).Magnitude })
		end
	end
	for _, entry in PredatorController.drawn() do
		table.insert(found, { instance = entry.instance, distance = (entry.position - from).Magnitude })
	end
	table.sort(found, function(a, b)
		return a.distance < b.distance
	end)
	local list: { Instance } = {}
	for i = 1, math.min(#found, HIGHLIGHT_CAP) do
		table.insert(list, found[i].instance)
	end
	return list
end

local function mark(instance: Instance)
	if marks[instance] then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "BloodSense"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = HOT
	highlight.FillTransparency = 0.3
	highlight.OutlineColor = RIM
	highlight.OutlineTransparency = 0
	highlight.Adornee = instance
	highlight.Parent = instance
	marks[instance] = highlight
end

local function clearMarks()
	for _, highlight in marks do
		highlight:Destroy()
	end
	table.clear(marks)
end

local function refreshMarks()
	local wanted: { [Instance]: boolean } = {}
	for _, instance in targets() do
		wanted[instance] = true
		if instance.Parent ~= nil then
			mark(instance)
		end
	end
	for instance, highlight in marks do
		if not wanted[instance] or instance.Parent == nil then
			highlight:Destroy()
			marks[instance] = nil
		end
	end
end

local function senseCast(): ColorCorrectionEffect
	local existing = cast
	if existing then
		return existing
	end
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "BloodSenseCast"
	effect.TintColor = Color3.new(1, 1, 1)
	effect.Saturation = 0
	effect.Contrast = 0
	effect.Parent = Lighting
	cast = effect
	return effect
end

-- Starts Blood Sense if it has recharged; returns whether it did
local function bloodSense(): boolean
	local now = os.clock()
	if now < senseReadyAt or SwimController.root() == nil then
		return false
	end
	senseUntil = now + SENSE_SECONDS
	senseReadyAt = now + SENSE_COOLDOWN
	nextRefresh = 0
	Sfx.play("Warning", { volume = 0.45, pitch = 0.8 })
	return true
end

local function fire()
	if AbilityController.name() == "BloodSense" then
		bloodSense()
	else
		SwimController.dash()
	end
end

local function step(dt: number)
	local now = os.clock()
	local active = now < senseUntil
	if active then
		if now >= nextRefresh then
			nextRefresh = now + SENSE_REFRESH
			refreshMarks()
		end
		-- The flash: a quick thermal throb, hot core to red and back, 2.5 times a second
		local throb = 0.5 + 0.5 * math.sin(now * 2 * math.pi * 2.5)
		local color = HOT:Lerp(HOTTER, throb)
		local fill = 0.5 - 0.35 * throb
		for _, highlight in marks do
			highlight.FillColor = color
			highlight.FillTransparency = fill
			highlight.OutlineTransparency = 0.2 * (1 - throb)
		end
	elseif next(marks) then
		clearMarks()
	end
	-- The red cast over the water eases in and out with the reveal
	local wantCast = if active then 1 else 0
	castAlpha += (wantCast - castAlpha) * math.min(1, dt * (if active then 6 else 3))
	if castAlpha > 0.005 then
		local effect = senseCast()
		effect.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 196, 196), castAlpha)
		effect.Saturation = -0.35 * castAlpha
		effect.Contrast = 0.12 * castAlpha
	elseif cast then
		(cast :: ColorCorrectionEffect):Destroy()
		cast = nil
		castAlpha = 0
	end
end

function AbilityController.start()
	Input.ability:connect(fire)
	RunService.RenderStepped:Connect(step)
	-- A species switch (or a respawn) ends a running reveal
	Players.LocalPlayer.CharacterAdded:Connect(function()
		senseUntil = 0
	end)
end

return AbilityController
