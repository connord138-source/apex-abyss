--!strict
-- Den doorways (owner, 2026-10-16: "Dens also still need to be substantially
-- bigger"; every den is now a private interior far outside the play area,
-- Layout.denOrigin). Swimming into a den's bubble portal on the plaza, or into the
-- way out on a den's front wall, washes the screen over with water and bubbles and
-- asks the server to move the fish (DenService checks it's really at the portal,
-- streams the place in round it and moves it); the wash clears once it's there. A
-- den nobody lives in keeps its portal shut.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
local COOLDOWN = 1.2 -- after a move, before another portal takes the fish

local busy = false
local coolUntil = 0
local arrived = false
local shutNoteAt = 0
local wash: Frame

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
	Sfx.play("Bubbles", { volume = 0.6, pitch = 1.1 })
	wash.Visible = true
	bubbles()
	Ui.tween(wash, FADE_IN, { BackgroundTransparency = 0 })
	task.delay(FADE_IN, function()
		ClientState.request(request, index)
		local started = os.clock()
		while not arrived and os.clock() - started < WAIT_MOST do
			task.wait()
		end
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
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local teleport = remotes:WaitForChild("Teleport") :: RemoteEvent
	teleport.OnClientEvent:Connect(function()
		arrived = true
	end)
	RunService.Heartbeat:Connect(step)
end

return DenDoorController
