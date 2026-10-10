--!strict
-- Which tide is up when (Config/Tides). Pure arithmetic on Unix time, so every
-- server and client agrees without sending anything: a slot's tide comes from a hash
-- of its number, never the same twice in a row, with the Prism Tide on its schedule.
-- Also the UTC day and the Monday-based week, for bounties and the Catch of the Week.
local TideConfig = require(script.Parent.Config.Tides)

local Tides = {}

export type Slot = { tide: string, startsAt: number, endsAt: number }

-- A number in [0, 1) from an integer, the same everywhere
local function hash(n: number): number
	-- (every product stays under 2^53, so doubles do it exactly)
	local h = (n * 2654435761 + TideConfig.seed * 40503) % 4294967296
	h = (h * 69069 + 1) % 4294967296
	h = (h * 69069 + 1) % 4294967296
	return h / 4294967296
end

local weighted: { { id: string, weight: number } } = {}
local total = 0
for _, tide in TideConfig.list do
	if tide.weight > 0 then
		table.insert(weighted, { id = tide.id, weight = tide.weight })
		total += tide.weight
	end
end

-- The tide a slot would get from its hash alone
local function drawn(slot: number): string
	local pick = hash(slot) * total
	for _, entry in weighted do
		pick -= entry.weight
		if pick < 0 then
			return entry.id
		end
	end
	return weighted[#weighted].id
end

local function isPrism(slot: number): boolean
	return slot % TideConfig.prism.every == TideConfig.prism.at
end

-- A second draw for a slot that would repeat the tide before: among the others, by
-- their weights, so a repeat doesn't favour any one tide
local function redrawn(slot: number, exclude: string): string
	local pool = 0
	for _, entry in weighted do
		if entry.id ~= exclude then
			pool += entry.weight
		end
	end
	local pick = hash(slot + 7_777_777) * pool
	for _, entry in weighted do
		if entry.id ~= exclude then
			pick -= entry.weight
			if pick < 0 then
				return entry.id
			end
		end
	end
	return exclude
end

-- A slot's tide: the Prism Tide on its schedule, otherwise the hash, moved on to the
-- second draw among the others when it would repeat the tide before. Worked forward from the
-- last Prism Tide (at most `every` - 1 slots), so it's exact and quick.
function Tides.tideOf(slot: number): string
	if isPrism(slot) then
		return TideConfig.prism.id
	end
	local every, at = TideConfig.prism.every, TideConfig.prism.at
	local from = slot - ((slot - at) % every)
	local before = TideConfig.prism.id
	local id = before
	for s = from + 1, slot do
		id = drawn(s)
		if id == before then
			id = redrawn(s, id)
		end
		before = id
	end
	return id
end

function Tides.slotAt(unix: number): number
	return math.floor(unix / TideConfig.slotSeconds)
end

-- Testing (the admin panel): a tide forced on every client and the server for a
-- while, through Workspace attributes (`TideOverride` id, `TideOverrideUntil` Unix)
local function forced(unix: number): (string?, number)
	local world = (workspace :: any) :: Workspace?
	if world == nil then
		return nil, 0
	end
	local id = world:GetAttribute("TideOverride")
	local untilAt = world:GetAttribute("TideOverrideUntil")
	if typeof(id) == "string" and typeof(untilAt) == "number" and unix < untilAt and TideConfig.byId[id] then
		return id, untilAt
	end
	return nil, 0
end

-- The tide up at Unix time `unix`, and when it started and ends
function Tides.at(unix: number): (TideConfig.Tide, number, number)
	local override, untilAt = forced(unix)
	if override then
		return TideConfig.byId[override], untilAt - TideConfig.slotSeconds, untilAt
	end
	local slot = Tides.slotAt(unix)
	local tide = TideConfig.byId[Tides.tideOf(slot)]
	return tide, slot * TideConfig.slotSeconds, (slot + 1) * TideConfig.slotSeconds
end

-- The next `count` tides after the current one
function Tides.forecast(unix: number, count: number): { Slot }
	local slot = Tides.slotAt(unix)
	local result: { Slot } = {}
	for i = 1, count do
		local s = slot + i
		table.insert(result, {
			tide = Tides.tideOf(s),
			startsAt = s * TideConfig.slotSeconds,
			endsAt = (s + 1) * TideConfig.slotSeconds,
		})
	end
	return result
end

-- When the next Prism Tide starts (now, if one is up)
function Tides.nextPrism(unix: number): number
	local slot = Tides.slotAt(unix)
	local every, at = TideConfig.prism.every, TideConfig.prism.at
	local offset = (at - slot) % every
	return (slot + offset) * TideConfig.slotSeconds
end

-- The UTC day number (the daily streak and bounties use the same)
function Tides.day(unix: number): number
	return math.floor(unix / 86400)
end

-- The week number, weeks starting Monday 00:00 UTC (1970-01-01 was a Thursday)
function Tides.week(unix: number): number
	return (math.floor(unix / 86400) + 3) // 7
end

-- When week `week` starts
function Tides.weekStart(week: number): number
	return (week * 7 - 3) * 86400
end

return Tides
