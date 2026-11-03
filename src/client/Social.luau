--!strict
-- Roblox's own prompts for getting the game around (Config/Social): the friend
-- invite (its referral banner, set in Creator Hub, shows on top of it) and allowing
-- notifications. Used by the Shop, the Pod window and the notifications card.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Config = require(ReplicatedStorage.Shared.Config)

local notifications = game:GetService("ExperienceNotificationService") :: any

local Social = {}

-- Opens the invite prompt; false and why when it can't (an account that can't send
-- invites, or Studio)
function Social.invite(): (boolean, string?)
	local player = Players.LocalPlayer
	local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	if not ok or can ~= true then
		return false, "Not on this account"
	end
	local options = Instance.new("ExperienceInviteOptions")
	options.PromptMessage = Config.Social.referral.message
	local shown = pcall(SocialService.PromptGameInvite, SocialService, player, options)
	if not shown then
		return false, "Didn't open, try again"
	end
	return true, nil
end

-- Opens Roblox's notifications prompt; false when Roblox won't show it (already on,
-- under 13, or shown in the last 30 days)
function Social.allowNotifications(): boolean
	local ok, can = pcall(notifications.CanPromptOptInAsync, notifications)
	if not ok or can ~= true then
		return false
	end
	return (pcall(notifications.PromptOptIn, notifications))
end

return Social
