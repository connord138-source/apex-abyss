--!strict
-- Rewarded video ads (ported from Hatch & Snatch): whether Roblox can show this
-- player one right now. Checked every minute once the AdDoubleHaul product has a
-- Creator Hub id; the Double Haul card shows its WATCH AD button only while
-- `Ads.available` is true. Roblox only serves ads to eligible players in eligible
-- experiences, so until then it stays false and the button never shows.
local AdService = game:GetService("AdService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local ClientState = require(script.Parent.ClientState)

local CHECK_SECONDS = 60

local Ads = {
	available = false,
}

local function check()
	local ok, result = pcall(function()
		return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
	end)
	Ads.available = ok and result.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
end

-- Asks the server to show an ad; the reward arrives as a receipt once it's watched.
function Ads.watch()
	if not Ads.available then
		return
	end
	Ads.available = false
	ClientState.request("WatchAd")
	task.delay(5, check)
end

function Ads.start()
	local product = Config.Monetization.productsByKey.AdDoubleHaul
	-- Studio never serves ads, and each check there logged "ad system not
	-- initialized yet" (playtest 2026-10-09)
	if product == nil or product.id == 0 or RunService:IsStudio() then
		return
	end
	while true do
		check()
		task.wait(CHECK_SECONDS)
	end
end

return Ads
