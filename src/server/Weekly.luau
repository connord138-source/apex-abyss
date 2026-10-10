--!strict
-- A player's record for this week (leaderboard scores, the Catch of the Week), reset
-- when a new week starts (Shared/Tides.week: Monday 00:00 UTC).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tides = require(ReplicatedStorage.Shared.Tides)
local Timing = require(ReplicatedStorage.Shared.Timing)
local DataService = require(script.Parent.Services.DataService)

local Weekly = {}

function Weekly.record(
	data: DataService.PlayerData
): { week: number, scores: { [string]: number }, featured: boolean }
	local week = Tides.week(Timing.unix())
	if data.weekly.week ~= week then
		data.weekly = { week = week, scores = {}, featured = false }
	end
	return data.weekly
end

return Weekly
