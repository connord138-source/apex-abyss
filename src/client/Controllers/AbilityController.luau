--!strict
-- The ability button (left click, RT, the phone's ability button) fires the fish's
-- signature ability (Config/Species `signature`, Config/Abilities; owner,
-- 2026-10-17: "each different fish should have their own limitations/advantages"):
--   Dash (Nibbler) and Torpedo ('Cuda): SwimController's burst, the Torpedo longer
--     and barely turning
--   Puff Up (Pufferfish), Burrow (Moray Eel), Lantern Flash (Anglerfish): asked of the
--     server (AbilityService), which sets Puffed, Burrowed and FlashAt on the
--     character; here we draw them (the flash's light and dazzle, a burrowed fish
--     faded, the Moray held still until it moves) and keep the button's cooldown
--   Blood Sense (Reef Shark), below
-- The Reef Shark has **Blood Sense** (owner, 2026-10-13:
-- "it should highlight players through surfaces as a flashing red thermal to show
-- where the other players and predators are"): for a few seconds every other fish
-- and every predator in the sea shows through rock and murk as a flashing red
-- heat signature, with a red cast over the water. Since 2026-10-18 it's a feeding
-- frenzy too (owner: "move a bit faster ... a bit of a magnet towards prey fish
-- and pull them in from a wider distance ... highlight both prey and predator
-- fish"): it's asked of the server (AbilityService sets `Sensing`), which the swim,
-- the prey and forage eats and the server's checks read (Perks.sense), and the
-- prey the shark could swallow within `range` glow a softer amber after the
-- players and predators, inside Roblox's Highlight cap. The reveal is drawn here.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Bubbles = require(script.Parent.Parent.Bubbles)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local Input = require(script.Parent.Parent.Input)
local Sfx = require(script.Parent.Parent.Sfx)
local PredatorController = require(script.Parent.PredatorController)
local SchoolController = require(script.Parent.SchoolController)
local SwimController = require(script.Parent.SwimController)

local AbilityController = {}

-- Blood Sense (Config/Abilities BloodSense)
local SENSE = Config.Abilities.byId.BloodSense
local SENSE_SECONDS = SENSE.seconds or 7
local SENSE_COOLDOWN = SENSE.cooldown or 24
local PREY_RANGE = SENSE.range or 120 -- studs round the shark its prey are marked within
local SENSE_REFRESH = 0.25 -- seconds between looks for new fish to mark (prey dart about)
-- Roblox draws at most 31 Highlights at once: a few are left for the game's own (a
-- whale's rim, the Apex's outline, a chasing fish's glow)
local HIGHLIGHT_CAP = 28
local HOT = Color3.fromRGB(255, 36, 36) -- the signature's cool end
local HOTTER = Color3.fromRGB(255, 176, 64) -- its hot end (a thermal's yellow core)
local RIM = Color3.fromRGB(255, 120, 120)
-- Prey glow softer, amber to a warm red, so the threats still stand out
local PREY_HOT = Color3.fromRGB(255, 132, 48)
local PREY_HOTTER = Color3.fromRGB(255, 196, 96)
local PREY_RIM = Color3.fromRGB(255, 186, 120)

local senseUntil = 0 -- when the reveal ends
local senseReadyAt = 0 -- when it can go again
local nextRefresh = 0
local marks: { [Instance]: Highlight } = {}
local preyMarks: { [Instance]: boolean } = {} -- the marks on prey (drawn softer)
local cast: ColorCorrectionEffect? = nil
local castAlpha = 0

-- Which species the player is swimming as, by the state
local function species(): string
	local s = ClientState.current
	local id = if s then s.species else nil
	return if typeof(id) == "string" then id else "Nibbler"
end

local Abilities = Config.Abilities.byId

-- This fish's part and variant bonuses (Perks.exotic: a Dragon Moray's quicker Burrow,
-- a Sabrecuda's longer Torpedo, a Hammerhead's wider Blood Sense, ...)
local function exotic(): Perks.Exotic
	return Perks.exotic(Players.LocalPlayer.Character)
end

-- An ability's cooldown for this player: the Outfitter's Quick Recovery shortens every
-- fish's own (Perks.boost), and a variant may shorten its own (`id`; AbilityService
-- does the same)
local function recharge(seconds: number, id: string?): number
	local s = ClientState.current
	local variant = if id then Perks.of(exotic().recharge, id) else 1
	return seconds / (Perks.boost(if s then s.upgrades else nil) * variant)
end

-- The other signature abilities' cooldowns and runs (os.clock)
local readyAt: { [string]: number } = {}
local runUntil: { [string]: number } = {}
local runFor: { [string]: number } = {}
local endAskedAt = 0
local wasBurrowed = false
local dazzle: Frame? = nil
local faded: { [Model]: boolean? } = {}

local function myCharacter(): Model?
	return Players.LocalPlayer.Character
end

local function burrowed(): boolean
	local character = myCharacter()
	return character ~= nil and character:GetAttribute("Burrowed") == true
end

-- The ability the button fires for this fish
function AbilityController.name(): string
	local def = Config.Species.byId[species()]
	return if def then def.signature else "Dash"
end

-- The button's word (DASH, TORPEDO, PUFF, BURROW, SENSE, FLASH; OUT while burrowed)
function AbilityController.label(): string
	local id = AbilityController.name()
	if id == "Burrow" and burrowed() then
		return "OUT"
	end
	local ability = Abilities[id]
	return if ability then ability.label or string.upper(ability.name) else "DASH"
end

-- The ability's charge, 0..1 (1 = ready), for the HUD's bar
function AbilityController.charge(): number
	local id = AbilityController.name()
	local now = os.clock()
	if id == "BloodSense" then
		if now >= senseReadyAt then
			return 1
		end
		return math.clamp(1 - (senseReadyAt - now) / recharge(SENSE_COOLDOWN, id), 0, 0.999)
	elseif id == "Dash" then
		return SwimController.dashCharge
	elseif id == "Burrow" and burrowed() then
		return 1
	end
	local ready = readyAt[id] or 0
	if now >= ready then
		return 1
	end
	local cooldown = recharge((Abilities[id] and Abilities[id].cooldown) or 1, id)
	return math.clamp(1 - (ready - now) / cooldown, 0, 0.999)
end

-- How much of a running ability is left, 0..1 (nil when none runs): Blood Sense,
-- the Torpedo, Puff Up
function AbilityController.running(): number?
	local now = os.clock()
	if now < senseUntil then
		return (senseUntil - now) / SENSE_SECONDS
	end
	for id, untilAt in runUntil do
		if now < untilAt then
			return (untilAt - now) / (runFor[id] or 1)
		end
	end
	return nil
end

-- Seconds of a running reveal left (0 when none), for a chip
function AbilityController.senseLeft(): number
	return math.max(0, senseUntil - os.clock())
end

-- Everything Blood Sense marks: the other players' fish and every drawn predator,
-- nearest first, then the prey within PREY_RANGE the shark could swallow, nearest
-- first, all within the Highlight cap. Returns the list and which of it is prey.
local function targets(): ({ Instance }, { [Instance]: boolean })
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
	local prey: { [Instance]: boolean } = {}
	for _, entry in
		SchoolController.edibleNear(
			from,
			SwimController.length(),
			PREY_RANGE * Perks.of(exotic().range, "BloodSense"), -- (a Hammerhead's reaches further)
			HIGHLIGHT_CAP - #list
		)
	do
		table.insert(list, entry.instance)
		prey[entry.instance] = true
	end
	return list, prey
end

local function mark(instance: Instance, prey: boolean)
	if marks[instance] then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "BloodSense"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = if prey then PREY_HOT else HOT
	highlight.FillTransparency = if prey then 0.7 else 0.3
	highlight.OutlineColor = if prey then PREY_RIM else RIM
	highlight.OutlineTransparency = if prey then 0.3 else 0
	highlight.Adornee = instance
	highlight.Parent = instance
	marks[instance] = highlight
	if prey then
		preyMarks[instance] = true
	else
		preyMarks[instance] = nil
	end
end

local function clearMarks()
	for _, highlight in marks do
		highlight:Destroy()
	end
	table.clear(marks)
	table.clear(preyMarks)
end

local function refreshMarks()
	local wanted: { [Instance]: boolean } = {}
	local list, prey = targets()
	for _, instance in list do
		wanted[instance] = true
		-- (a fish that was prey and is now a threat, or back, is marked afresh)
		if marks[instance] and (preyMarks[instance] == true) ~= (prey[instance] == true) then
			marks[instance]:Destroy()
			marks[instance] = nil
		end
		if instance.Parent ~= nil then
			mark(instance, prey[instance] == true)
		end
	end
	for instance, highlight in marks do
		if not wanted[instance] or instance.Parent == nil then
			highlight:Destroy()
			marks[instance] = nil
			preyMarks[instance] = nil
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
	senseReadyAt = now + recharge(SENSE_COOLDOWN, "BloodSense")
	nextRefresh = 0
	Sfx.play("Warning", { volume = 0.45, pitch = 0.8 })
	return true
end

-- A cooldown ability that's ready: starts its clock and says so
local function take(id: string): boolean
	local now = os.clock()
	if now < (readyAt[id] or 0) or SwimController.root() == nil then
		Sfx.play("TooBig", { volume = 0.25 })
		return false
	end
	local ability = Abilities[id]
	readyAt[id] = now + recharge(ability.cooldown or 1, id)
	if ability.seconds then
		-- (a variant may make it last longer, and a Narwhal Horn carries a Torpedo further)
		local seconds = ability.seconds
			* Perks.of(exotic().duration, id)
			* (if id == "Torpedo" then exotic().dash else 1)
		runUntil[id] = now + seconds
		runFor[id] = seconds
	end
	return true
end

local function fire()
	local id = AbilityController.name()
	if id == "BloodSense" then
		if bloodSense() then
			-- The frenzy's speed and pull come once the server says so (`Sensing`)
			ClientState.request("UseAbility", "BloodSense")
		else
			Sfx.play("TooBig", { volume = 0.25 })
		end
	elseif id == "Torpedo" then
		local ability = Abilities.Torpedo
		if take("Torpedo") then
			-- (a Sabrecuda's runs longer; SwimController adds a Narwhal Horn's)
			SwimController.dash(
				(ability.seconds or 1.4) * Perks.of(exotic().duration, "Torpedo"),
				ability.turn,
				true
			)
		end
	elseif id == "PuffUp" then
		if take("PuffUp") then
			ClientState.request("UseAbility", "PuffUp")
			Sfx.play("Bubbles", { volume = 0.55, pitch = 0.7 })
		end
	elseif id == "Burrow" then
		if burrowed() then
			ClientState.request("EndAbility")
		elseif os.clock() >= (readyAt.Burrow or 0) then
			-- (its cooldown starts when it ends, below)
			ClientState.request("UseAbility", "Burrow")
		else
			Sfx.play("TooBig", { volume = 0.25 })
		end
	elseif id == "LanternFlash" then
		if take("LanternFlash") then
			ClientState.request("UseAbility", "LanternFlash")
		end
	else
		SwimController.dash()
	end
end

-- An Anglerfish's Lantern Flash: a burst of light at it for everyone, and a white-out
-- for players near it (less when it's behind them); the flasher sees only the light
local function flash(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local ability = Abilities.LanternFlash
	local light = Instance.new("PointLight")
	light.Name = "LanternFlash"
	light.Color = Color3.fromRGB(255, 244, 200)
	light.Range = 60
	light.Brightness = 12
	light.Shadows = false
	light.Parent = root
	Ui.tween(light, 0.7, { Brightness = 0 })
	task.delay(0.75, function()
		light:Destroy()
	end)
	Bubbles.burst(root.Position, 4, 18)
	Sfx.play("Banner", { volume = 0.5, pitch = 1.4 })
	if character == myCharacter() or dazzle == nil then
		return
	end
	local mine = SwimController.root()
	if mine == nil then
		return
	end
	local offset = root.Position - workspace.CurrentCamera.CFrame.Position
	-- (a Deepfang Angler's flash reaches further, Perks.exotic: AbilityService stuns as far)
	local reach = (ability.reach or 48) * Perks.of(Perks.exotic(character).range, "LanternFlash")
	if (root.Position - mine.Position).Magnitude > reach then
		return
	end
	local facing = if offset.Magnitude > 1e-3
		then math.clamp(workspace.CurrentCamera.CFrame.LookVector:Dot(offset.Unit), 0, 1)
		else 1
	local strength = 0.45 + 0.55 * facing
	local frame = dazzle :: Frame
	frame.BackgroundTransparency = 1 - strength
	frame.Visible = true
	Ui.tween(frame, ability.blind or 1.4, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
end

-- Every fish: a burrowed fish (not your own) fades and its name tag goes
-- (NametagController); your own is held still while burrowed and comes out when
-- you try to swim
local function abilityStep()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character == nil or player == Players.LocalPlayer then
			continue
		end
		local hidden = character:GetAttribute("Burrowed") == true
		if hidden ~= (faded[character] == true) then
			faded[character] = if hidden then true else nil
			local body = character:FindFirstChild("Body")
			if body then
				for _, part in body:GetDescendants() do
					if part:IsA("BasePart") then
						part.LocalTransparencyModifier = if hidden then 0.8 else 0
					end
				end
			end
		end
	end
	for character in faded do
		if character.Parent == nil then
			faded[character] = nil
		end
	end
	local hiding = burrowed()
	SwimController.pinned = hiding
	if hiding and not wasBurrowed then
		local root = SwimController.root()
		if root then
			Bubbles.burst(root.Position, SwimController.length(), 16)
		end
		Sfx.play("Forage", { volume = 0.5, pitch = 0.6 })
	elseif wasBurrowed and not hiding then
		readyAt.Burrow = os.clock() + recharge(Abilities.Burrow.cooldown or 8, "Burrow")
	end
	wasBurrowed = hiding
	if hiding and os.clock() - endAskedAt > 0.3 then
		local throttle = Input.drive()
		if Input.moveVector().Magnitude > 0.1 or throttle > 0.2 or math.abs(Input.vertical()) > 0.1 then
			endAskedAt = os.clock()
			ClientState.request("EndAbility")
		end
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
		-- Prey breathe softer, a little out of step
		local preyThrob = 0.5 + 0.5 * math.sin(now * 2 * math.pi * 1.6 + 1)
		local preyColor = PREY_HOT:Lerp(PREY_HOTTER, preyThrob)
		local preyFill = 0.78 - 0.18 * preyThrob
		for instance, highlight in marks do
			if preyMarks[instance] then
				highlight.FillColor = preyColor
				highlight.FillTransparency = preyFill
				highlight.OutlineTransparency = 0.25 + 0.3 * (1 - preyThrob)
			else
				highlight.FillColor = color
				highlight.FillTransparency = fill
				highlight.OutlineTransparency = 0.2 * (1 - throb)
			end
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
	RunService.Heartbeat:Connect(abilityStep)
	-- The Lantern Flash's dazzle, over everything
	local gui = Ui.screen("Dazzle", Players.LocalPlayer:WaitForChild("PlayerGui"), 45)
	local frame = Instance.new("Frame")
	frame.Name = "Dazzle"
	frame.BackgroundColor3 = Color3.fromRGB(255, 252, 236)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Visible = false
	frame.Parent = gui
	dazzle = frame
	-- Every fish's flashes (a character's FlashAt changes when its Angler flashes)
	local function watch(player: Player)
		local function track(character: Model)
			character:GetAttributeChangedSignal("FlashAt"):Connect(function()
				local at = character:GetAttribute("FlashAt")
				if typeof(at) == "number" and Timing.clock() - at < 1 then
					flash(character)
				end
			end)
		end
		player.CharacterAdded:Connect(track)
		if player.Character then
			track(player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	-- A species switch (or a respawn) ends a running reveal
	Players.LocalPlayer.CharacterAdded:Connect(function()
		senseUntil = 0
	end)
end

return AbilityController
