--!strict
-- The onboarding funnel (Creator Hub → the experience → Analytics → Funnels): where
-- new players stop in their first session, logged with AnalyticsService (owner,
-- 2026-11-03). Steps go in order and each is logged once (`data.onboarding` holds
-- the furthest); Roblox counts a skipped step as done. Roblox takes these only from
-- a published game's server, so in Studio each step is printed instead.
local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Guard = require(script.Parent.Guard)
local DataService = require(script.Parent.Services.DataService)

type Data = DataService.PlayerData

-- The steps by name. The tutorial's come from Config/Tutorial, so a step added there
-- lands here too (Roblox shows a warning on dates that span a renamed step).
local STEPS: { string } = { "Joined", "Dived in" }
local TUTORIAL_FIRST = #STEPS + 1
for _, step in Config.Tutorial.steps do
	table.insert(STEPS, `Tutorial: {step.id}`)
end
table.insert(STEPS, "Banked on their own")
table.insert(STEPS, "Reached LV 15")

local index: { [string]: number } = {}
for i, name in STEPS do
	index[name] = i
end

local Funnel = {
	STEPS = STEPS,
}

local function log(player: Player, step: number)
	local name = STEPS[step]
	if Timing.isStudio() then
		print(`[Funnel] {player.Name}: step {step} {name}`)
		return
	end
	Guard.run("Funnel.log", function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

-- Logs `name` if it's further than this player has come; true if it was logged
function Funnel.reach(player: Player, data: Data, name: string): boolean
	local step = index[name]
	if step == nil or data.onboarding < 0 or step <= data.onboarding then
		return false
	end
	data.onboarding = step
	log(player, step)
	return true
end

-- On join: a player who finished the tutorial before the funnel shipped is never
-- logged (they'd show as quitting after "Joined"); everyone else starts it
function Funnel.joined(player: Player, data: Data)
	if data.onboarding == 0 and data.tutorial.done then
		data.onboarding = -1
		return
	end
	Funnel.reach(player, data, "Joined")
end

-- The tutorial's steps done so far, from the save (the last one is the tutorial
-- finished)
function Funnel.tutorial(player: Player, data: Data)
	if data.onboarding < 0 then
		return
	end
	local done = if data.tutorial.done then #Config.Tutorial.steps else data.tutorial.step - 1
	if done < 1 then
		return
	end
	local step = TUTORIAL_FIRST + done - 1
	if step > data.onboarding then
		-- (Funnel.reach by name, so skipped steps stay Roblox's to fill in)
		Funnel.reach(player, data, STEPS[step])
	end
end

return Funnel
