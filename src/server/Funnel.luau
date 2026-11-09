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

-- A save logged under an older tutorial list (TutorialService `migrate`; v2 had
-- `oldCount` steps, LeaveHub first and the Treasure Wheel sixth, before 2026-11-08):
-- its furthest step is moved to what it has done in this list, so the steps still
-- ahead of it log. Past the tutorial it keeps its place counted from the end.
function Funnel.reordered(data: Data, oldCount: number)
	local furthest = data.onboarding
	if furthest < TUTORIAL_FIRST then
		return -- (never logged, or not past diving in)
	end
	local count = #Config.Tutorial.steps
	if furthest >= TUTORIAL_FIRST + oldCount - 1 then
		data.onboarding = furthest + count - oldCount
		return
	end
	local done = if data.tutorial.done then count else data.tutorial.step - 1
	data.onboarding = math.max(TUTORIAL_FIRST - 1, TUTORIAL_FIRST + done - 1)
end

-- How the game runs on each kind of device (DeviceReportController, once a session
-- after a minute's play; owner, 2026-11-08: phones and tablets lost far more new
-- players than computers, and the Performance page stays empty until the game is
-- bigger). Analytics → Custom events → "FrameRate": its value is the average frames a
-- second, and its three fields are the frame rate's band, the kind of device and the
-- memory's band, so a breakdown shows how many phones ran under 20. Once per player
-- per server; whatever the client sends is checked first.
local KINDS = { phone = true, tablet = true, gamepad = true, computer = true }
type Band = { below: number, name: string }
local FPS_BANDS: { Band } = {
	{ below = 20, name = "under 20" },
	{ below = 30, name = "20-29" },
	{ below = 45, name = "30-44" },
	{ below = 55, name = "45-54" },
}
local MEMORY_BANDS: { Band } = {
	{ below = 1000, name = "under 1 GB" },
	{ below = 1500, name = "1-1.5 GB" },
	{ below = 2000, name = "1.5-2 GB" },
	{ below = 3000, name = "2-3 GB" },
}
local reported: { [number]: boolean } = {}

local function band(value: number, bands: { Band }, top: string): string
	for _, entry in bands do
		if value < entry.below then
			return entry.name
		end
	end
	return top
end

local function finite(value: any, low: number, high: number): boolean
	return typeof(value) == "number" and value == value and value >= low and value <= high
end

function Funnel.device(player: Player, fps: any, memory: any, kind: any)
	if reported[player.UserId] or not finite(fps, 1, 1000) or not finite(memory, 0, 100000) then
		return
	end
	if typeof(kind) ~= "string" or not KINDS[kind] then
		return
	end
	reported[player.UserId] = true
	local fpsBand = band(fps, FPS_BANDS, "55+")
	local memoryBand = band(memory, MEMORY_BANDS, "3 GB+")
	if Timing.isStudio() then
		print(
			`[Funnel] {player.Name}: {math.floor(fps + 0.5)} FPS ({fpsBand}), {kind}, {math.floor(memory)} MB`
		)
		return
	end
	Guard.run("Funnel.device", function()
		AnalyticsService:LogCustomEvent(player, "FrameRate", math.floor(fps + 0.5), {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = fpsBand,
			[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = kind,
			[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = memoryBand,
		})
	end)
end

return Funnel
