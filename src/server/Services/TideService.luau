--!strict
-- The Tide Clock on the server (Config/Tides, Shared/Tides): tells everyone when the
-- tide turns, warns the server before a Prism Tide, and keeps the tide on Workspace
-- attributes (`Tide`, `TideEnds`) for anything that wants to read it. The tides
-- themselves are arithmetic on the clock, so every server and client agrees;
-- CatchService, HuntService and PredatorService read Shared/Tides directly.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Tides = require(ReplicatedStorage.Shared.Tides)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)

local TideConfig = Config.Tides

local TideService = {}

local current = ""
local currentEnds = 0
local warnedFor = -1 -- the Prism Tide slot already warned about

local function tick()
	local unix = Timing.unix()
	-- A forced tide (the admin panel) that has run its length goes back to the clock,
	-- so nothing still names it
	local forcedUntil = workspace:GetAttribute("TideOverrideUntil")
	if typeof(forcedUntil) == "number" and unix >= forcedUntil then
		workspace:SetAttribute("TideOverride", nil)
		workspace:SetAttribute("TideOverrideUntil", nil)
	end
	local tide, _, endsAt = Tides.at(unix)
	if tide.id ~= current or endsAt ~= currentEnds then
		current = tide.id
		currentEnds = endsAt
		workspace:SetAttribute("Tide", tide.id)
		workspace:SetAttribute("TideEnds", endsAt)
		Net.tideChanged(tide.id, endsAt)
	end
	local prismAt = Tides.nextPrism(unix)
	local slot = Tides.slotAt(prismAt)
	if prismAt > unix and prismAt - unix <= TideConfig.announceAhead and warnedFor ~= slot then
		warnedFor = slot
		Net.notifyAll("The PRISM TIDE rises in 2 minutes! Prism fish will swim.", "rare")
	end
end

function TideService.start()
	tick()
	Guard.loop("TideService.tick", 1, tick)
end

return TideService
