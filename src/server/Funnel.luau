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
-- `oldCount` steps, LeaveHub first and the Treasure Wheel sixth, before 2026-11-08; v3
-- had Shells second, before 2026-11-20): its furthest step is moved to what it has done
-- in this list, so the steps still ahead of it log. Past the tutorial it keeps its
-- place counted from the end.
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

-- How the game runs on each kind of device (DeviceReportController; owner, 2026-11-08:
-- phones and tablets lost far more new players than computers, and the Performance
-- page stays empty until the game is bigger). Analytics → Custom events: the value is
-- the average frames a second, and the three fields are the frame rate's band, the
-- kind of device and the memory's band, so a breakdown shows how many phones ran
-- under 20. Two samples a session, each once per player per server: "FrameRateEarly"
-- over the first 10 seconds of play (2026-11-12: half of new players leave within three
-- minutes, and the minute's sample never heard from the ones who left first) and
-- "FrameRate" over the first minute. Whatever the client sends is checked first.
local KINDS = { phone = true, tablet = true, gamepad = true, computer = true }
local STAGES: { [string]: string } = { early = "FrameRateEarly", minute = "FrameRate" }
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
local WAIT_BANDS: { Band } = {
	{ below = 5, name = "under 5 s" },
	{ below = 10, name = "5-9 s" },
	{ below = 20, name = "10-19 s" },
	{ below = 40, name = "20-39 s" },
	{ below = 60, name = "40-59 s" },
	{ below = 90, name = "60-89 s" },
}
local reported: { [string]: boolean } = {}

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

-- True the first time `what` is asked for this player in this server
local function once(player: Player, what: string): boolean
	local key = `{player.UserId}:{what}`
	if reported[key] then
		return false
	end
	reported[key] = true
	return true
end

function Funnel.device(player: Player, fps: any, memory: any, kind: any, stage: any)
	local event = STAGES[if typeof(stage) == "string" then stage else "minute"]
	if event == nil or not finite(fps, 1, 1000) or not finite(memory, 0, 100000) then
		return
	end
	if typeof(kind) ~= "string" or not KINDS[kind] or not once(player, event) then
		return
	end
	local fpsBand = band(fps, FPS_BANDS, "55+")
	local memoryBand = band(memory, MEMORY_BANDS, "3 GB+")
	if Timing.isStudio() then
		print(
			`[Funnel] {player.Name}: {event} {math.floor(fps + 0.5)} FPS ({fpsBand}), {kind}, {math.floor(
				memory
			)} MB`
		)
		return
	end
	Guard.run("Funnel.device", function()
		AnalyticsService:LogCustomEvent(player, event, math.floor(fps + 0.5), {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = fpsBand,
			[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = kind,
			[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = memoryBand,
		})
	end)
end

-- How long players wait before they can play (2026-11-12: every server start builds
-- the whole sea before any save loads, most joins start a server, and a player who
-- gives up on the loading screen never reaches "Joined", so nothing showed the wait).
-- Two custom events, each once per player per server:
--   "JoinWait": seconds from the player's connection being heard (the server's own
--     start for one who was there before its scripts ran) to their save being loaded;
--     fields: the wait's band, "cold" (they came while the sea was being built) or
--     "warm", and the band of this server's whole start.
--   "LoadTime": seconds from the client's scripts starting to TAP TO START showing
--     (StartController `prompted`); fields: its band, the kind of device, cold or warm.
local arrivals: { [number]: string } = {}

function Funnel.arrived(player: Player, waited: number, cold: boolean, serverStart: number)
	local how = if cold then "cold" else "warm"
	arrivals[player.UserId] = how
	if not once(player, "JoinWait") then
		return
	end
	local seconds = math.floor(math.clamp(waited, 0, 3600) + 0.5)
	local waitBand = band(seconds, WAIT_BANDS, "90 s+")
	local startBand = band(serverStart, WAIT_BANDS, "90 s+")
	if Timing.isStudio() then
		print(`[Funnel] {player.Name}: JoinWait {seconds} s ({waitBand}), {how}, server start {startBand}`)
		return
	end
	Guard.run("Funnel.arrived", function()
		AnalyticsService:LogCustomEvent(player, "JoinWait", seconds, {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = waitBand,
			[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = how,
			[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = startBand,
		})
	end)
end

function Funnel.load(player: Player, seconds: any, kind: any)
	if not finite(seconds, 0, 3600) or typeof(kind) ~= "string" or not KINDS[kind] then
		return
	end
	if not once(player, "LoadTime") then
		return
	end
	local whole = math.floor(seconds + 0.5)
	local waitBand = band(whole, WAIT_BANDS, "90 s+")
	local how = arrivals[player.UserId] or "unknown"
	if Timing.isStudio() then
		print(`[Funnel] {player.Name}: LoadTime {whole} s ({waitBand}), {kind}, {how}`)
		return
	end
	Guard.run("Funnel.load", function()
		AnalyticsService:LogCustomEvent(player, "LoadTime", whole, {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = waitBand,
			[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = kind,
			[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = how,
		})
	end)
end

-- A controller (client) or service (server) whose start threw (init.client and
-- init.server start each one protected, so the rest still start). Custom event
-- "StartError": fields "client" or "server", and the first that failed. Once per
-- player per server and side; a client's names are checked before they're logged.
function Funnel.startError(player: Player, side: string, names: any)
	if typeof(names) ~= "string" or #names == 0 or #names > 200 or names:find("[^%w,_]") then
		return
	end
	if (side ~= "client" and side ~= "server") or not once(player, `StartError:{side}`) then
		return
	end
	local first = names:match("^[^,]+") or names
	warn(`[Funnel] {player.Name}: {side} start failed: {names}`)
	if Timing.isStudio() then
		return
	end
	Guard.run("Funnel.startError", function()
		AnalyticsService:LogCustomEvent(player, "StartError", 1, {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = side,
			[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = first,
		})
	end)
end

return Funnel
