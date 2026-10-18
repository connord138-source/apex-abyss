--!strict
-- Den doorways (owner, 2026-10-16: "Dens also still need to be substantially
-- bigger"; every den is now a private interior far outside the play area,
-- Layout.denOrigin). Swimming into a den's bubble portal on the plaza, or into the
-- way out on a den's front wall, washes the screen over with water and bubbles and
-- asks the server to move the fish (DenService checks it's really at the portal,
-- streams the place in round it and moves it); the wash clears once it's there. A
-- den nobody lives in keeps its portal shut.
--
-- Loading (owner, 2026-10-17: leaving a den, "it takes about 20 seconds for the safe
-- zone to load and you see everything else and through the floor in the meantime. If
-- we need to add a loading screen that is fine"): near a portal the far side is
-- streamed in ahead (`Prestream`), and after the move the wash stays up, as a
-- loading screen with a tip, holding the fish still, until the place round the fish
-- has really arrived (rock under it and round it, the doorway's model) or LOAD_MOST.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local HudController = require(script.Parent.HudController)
local SwimController = require(script.Parent.SwimController)

local DenDoorController = {}

local WASH = Color3.fromRGB(8, 44, 64)
local FADE_IN = 0.22
local FADE_OUT = 0.45
local WAIT_MOST = 2.5 -- seconds to wait for the move before clearing anyway
local LOAD_MOST = 25 -- seconds to wait for the place to stream in before clearing anyway
local SETTLE = 0.6 -- the place must be there this long (Terrain meshes after it arrives)
-- Coming out on the plaza, longer: Roblox first draws the newly arrived hub Terrain
-- coarse, which closes the doorway's arch over (a dark blue rock face, though rays
-- already pass), and meshes it finely only 1.5–3.6 s after arriving (PC 2026-10-18, LD2)
local SETTLE_HUB = 3.4
local PRESTREAM_REACH = 36 -- studs from a portal at which the far side is asked for
local COOLDOWN = 1.2 -- after a move, before another portal takes the fish

local busy = false
local coolUntil = 0
local arrived = false
local shutNoteAt = 0
local prestreamAt = 0
local wash: Frame
local loading: TextLabel
local tipLabel: TextLabel

-- Whether the place round the fish has streamed in: rock under it and round it,
-- and (for the plaza) the doorway it came out of
local function arrivedAt(door: number?): boolean
	local character = Players.LocalPlayer.Character
	local root = SwimController.root()
	if character == nil or root == nil then
		return false
	end
	if door then
		local world = workspace:FindFirstChild("World")
		local hub = world and world:FindFirstChild("Hub")
		local doorway = hub and hub:FindFirstChild(`Den{door}`)
		if doorway == nil then
			return false
		end
		-- and its lanterns' lights: the doorway and the rock round it showed dim blue
		-- for ~0.5–1 s after the wash cleared while they streamed in (PC 2026-10-17, LD1)
		if doorway:GetAttribute("Owner") ~= nil and doorway:FindFirstChildWhichIsA("Light", true) == nil then
			return false
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local origin = root.Position
	if workspace:Raycast(origin, Vector3.new(0, -90, 0), params) == nil then
		return false
	end
	local walls = 0
	for i = 0, 7 do
		local angle = i / 8 * 2 * math.pi
		if workspace:Raycast(origin, Vector3.new(math.cos(angle), 0, math.sin(angle)) * 170, params) then
			walls += 1
		end
	end
	return walls >= 2
end

-- Whether someone lives in den `index` (the doorway's model carries its owner's
-- name; if it hasn't streamed in, let the server decide)
local function lived(index: number): boolean
	local world = workspace:FindFirstChild("World")
	local hub = world and world:FindFirstChild("Hub")
	local model = hub and hub:FindFirstChild(`Den{index}`)
	if model == nil then
		return true
	end
	return model:GetAttribute("Owner") ~= nil
end

-- A few bubbles rising across the wash
local function bubbles()
	for _ = 1, 16 do
		local size = math.random(8, 22)
		local bubble = Instance.new("Frame")
		bubble.BackgroundColor3 = Color3.fromRGB(190, 240, 255)
		bubble.BackgroundTransparency = 0.55
		bubble.BorderSizePixel = 0
		bubble.AnchorPoint = Vector2.new(0.5, 0.5)
		bubble.Size = UDim2.fromOffset(size, size)
		bubble.Position = UDim2.new(math.random(), 0, 1.05, 0)
		Ui.corner(bubble, UDim.new(1, 0))
		bubble.Parent = wash
		local rise = 0.5 + math.random() * 0.5
		Ui.tween(bubble, rise, {
			Position = UDim2.new(bubble.Position.X.Scale + (math.random() - 0.5) * 0.08, 0, -0.1, 0),
			BackgroundTransparency = 0.9,
		})
		task.delay(rise + 0.05, function()
			bubble:Destroy()
		end)
	end
end

local function go(request: string, index: number?)
	busy = true
	arrived = false
	-- Leaving: the doorway on the plaza we'll come out at
	local root = SwimController.root()
	local door = if request == "LeaveDen" and root then Layout.denAt(root.Position) else nil
	Sfx.play("Bubbles", { volume = 0.6, pitch = 1.1 })
	wash.Visible = true
	loading.Text = if request == "LeaveDen" then "SWIMMING OUT TO THE HUB" else "SWIMMING INTO THE DEN"
	local tips = Config.Tutorial.tips
	tipLabel.Text = tips[math.random(1, #tips)]
	loading.TextTransparency = 1
	tipLabel.TextTransparency = 1
	bubbles()
	Ui.tween(wash, FADE_IN, { BackgroundTransparency = 0 })
	task.delay(FADE_IN, function()
		ClientState.request(request, index)
		local started = os.clock()
		while not arrived and os.clock() - started < WAIT_MOST do
			task.wait()
		end
		-- The place must be there (held still meanwhile); the words show if it takes a while
		local wasLocked = Input.locked
		Input.locked = true
		local since: number? = nil
		local shown = false
		local settle = if door then SETTLE_HUB else SETTLE
		started = os.clock()
		while os.clock() - started < LOAD_MOST do
			if arrivedAt(door) then
				since = since or os.clock()
				if os.clock() - (since :: number) >= settle then
					break
				end
			else
				since = nil
			end
			if not shown and os.clock() - started > 0.6 then
				shown = true
				Ui.tween(loading, 0.3, { TextTransparency = 0 })
				Ui.tween(tipLabel, 0.3, { TextTransparency = 0.15 })
			end
			if shown and math.random() < 0.02 then
				bubbles()
			end
			task.wait(0.05)
		end
		Input.locked = wasLocked
		Ui.tween(loading, 0.2, { TextTransparency = 1 })
		Ui.tween(tipLabel, 0.2, { TextTransparency = 1 })
		-- A frame for the camera to cut to the new place under the wash
		task.wait(0.1)
		Sfx.play("Bubble", { volume = 0.5, pitch = 0.8 })
		bubbles()
		Ui.tween(wash, FADE_OUT, { BackgroundTransparency = 1 })
		task.delay(FADE_OUT, function()
			if not busy then
				wash.Visible = false
			end
		end)
		coolUntil = os.clock() + COOLDOWN
		busy = false
	end)
end

local function step()
	if busy or Input.locked or os.clock() < coolUntil then
		return
	end
	local root = SwimController.root()
	if root == nil then
		return
	end
	local position = root.Position
	-- Near a portal: have the far side streamed in before we swim through
	if os.clock() > prestreamAt then
		local den = Layout.denAt(position)
		local near = if den
			then (position - Layout.exitFrame(den).Position).Magnitude <= PRESTREAM_REACH
			else false
		if not near and den == nil then
			for i = 1, Layout.DEN_COUNT do
				if (position - Layout.doorFrame(i).Position).Magnitude <= PRESTREAM_REACH and lived(i) then
					near = true
					break
				end
			end
		end
		if near then
			prestreamAt = os.clock() + 8
			ClientState.request("Prestream")
		end
	end
	local door = Layout.doorAt(position)
	if door then
		if lived(door) then
			go("EnterDen", door)
		elseif os.clock() > shutNoteAt then
			shutNoteAt = os.clock() + 4
			HudController.toast("No one lives in this den yet", "info")
		end
		return
	end
	if Layout.exitAt(position) then
		go("LeaveDen", nil)
	end
end

function DenDoorController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Ui.screen("DenDoor", playerGui, 40)
	wash = Instance.new("Frame")
	wash.Name = "Wash"
	wash.BackgroundColor3 = WASH
	wash.BackgroundTransparency = 1
	wash.BorderSizePixel = 0
	wash.Size = UDim2.fromScale(1, 1)
	wash.Visible = false
	wash.Parent = gui
	loading = Ui.label(
		wash,
		"Loading",
		"",
		Ui.FONT_HEAVY,
		26,
		Ui.color.text,
		UDim2.new(1, -40, 0, 34),
		UDim2.new(0.5, 0, 0.5, -30)
	)
	loading.AnchorPoint = Vector2.new(0.5, 0.5)
	loading.TextXAlignment = Enum.TextXAlignment.Center
	loading.TextTransparency = 1
	tipLabel = Ui.label(
		wash,
		"Tip",
		"",
		Ui.FONT_SEMI,
		17,
		Ui.color.muted,
		UDim2.new(0.8, 0, 0, 48),
		UDim2.new(0.5, 0, 0.5, 16)
	)
	tipLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	tipLabel.TextXAlignment = Enum.TextXAlignment.Center
	tipLabel.TextWrapped = true
	tipLabel.TextTransparency = 1
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local teleport = remotes:WaitForChild("Teleport") :: RemoteEvent
	teleport.OnClientEvent:Connect(function()
		arrived = true
	end)
	RunService.Heartbeat:Connect(step)
end

return DenDoorController
