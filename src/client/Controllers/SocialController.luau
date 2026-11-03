--!strict
-- The notifications card (MenuController.openNotify) when the server says it's time
-- (NotifyService `notifyAsk`: the tutorial done, a few banks, not asked this month),
-- in a quiet moment: off the start screen, no menu or centre banner up, not
-- building, and in the hub or a den.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Layout)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Ui = require(script.Parent.Parent.Ui)
local MenuController = require(script.Parent.MenuController)
local StartController = require(script.Parent.StartController)

local LOOK_EVERY = 3

local SocialController = {}

local function quiet(): boolean
	if StartController.isUp() or MenuController.isOpen() or Ui.centreBannerUp() or Input.editing then
		return false
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return false
	end
	return Layout.inHub(root.Position) or Layout.denAt(root.Position) ~= nil
end

function SocialController.start()
	task.spawn(function()
		while true do
			task.wait(LOOK_EVERY)
			local s = ClientState.current
			if s and s.notifyAsk == true and quiet() then
				ClientState.request("NotifyAsked")
				MenuController.openNotify()
				return -- (once a session; the server says when again)
			end
		end
	end)
end

return SocialController
