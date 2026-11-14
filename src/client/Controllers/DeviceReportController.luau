--!strict
-- How the game runs on each kind of device (owner, 2026-11-08: phones and tablets
-- lost far more new players than computers, and Analytics' Performance page stays
-- empty until the game is bigger). Three reports a session go to the server, which
-- logs them to Analytics as custom events (Server/Funnel `load`, `device`):
--   the load time: seconds from the client's scripts starting (init.client stamps
--     `ClientBoot` on the player) to TAP TO START showing;
--   the frame rate, the memory in use and the kind of device after `EARLY_SECONDS` of
--     play past the start screen (2026-11-12: half of new players leave within three
--     minutes, so the minute's report never heard from the ones who left first);
--   and the same after `PLAY_SECONDS`.
-- Frames while the fish is held still don't count: loading washes, the bank's growth
-- moment.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local StartController = require(script.Parent.StartController)

local EARLY_SECONDS = 10
local PLAY_SECONDS = 60
local LONGEST_FRAME = 2 -- seconds: a frame longer than this was the app in the background
local PHONE_HEIGHT = 600 -- a touch screen shorter than this (its short side, in points) is a phone

local DeviceReportController = {}

-- "phone", "tablet", "gamepad" or "computer"
local function kind(): string
	if Input.usingTouch() then
		local size = workspace.CurrentCamera.ViewportSize
		return if math.min(size.X, size.Y) < PHONE_HEIGHT then "phone" else "tablet"
	elseif Input.isGamepad() then
		return "gamepad"
	end
	return "computer"
end

function DeviceReportController.start()
	StartController.afterPrompt(function(sinceOpened: number, at: number)
		local boot = Players.LocalPlayer:GetAttribute("ClientBoot")
		local seconds = if typeof(boot) == "number" then at - boot else sinceOpened
		ClientState.request("LoadReport", seconds, kind())
	end)
	StartController.afterStart(function()
		local frames, seconds = 0, 0
		local early = false
		local connection: RBXScriptConnection? = nil
		connection = RunService.RenderStepped:Connect(function(dt: number)
			if Input.locked or dt > LONGEST_FRAME then
				return
			end
			frames += 1
			seconds += dt
			if not early and seconds >= EARLY_SECONDS then
				early = true
				ClientState.request(
					"DeviceReport",
					frames / seconds,
					Stats:GetTotalMemoryUsageMb(),
					kind(),
					"early"
				)
			end
			if seconds < PLAY_SECONDS then
				return
			end
			if connection then
				connection:Disconnect()
			end
			ClientState.request(
				"DeviceReport",
				frames / seconds,
				Stats:GetTotalMemoryUsageMb(),
				kind(),
				"minute"
			)
		end)
	end)
end

return DeviceReportController
