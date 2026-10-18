-- Checks Shared/Tides and Shared/Catch: the Prism Tide's schedule, no tide twice in a
-- row, every tide turns up, weeks, and the rare fish's spawn rates under each tide
-- (the goals and the old saves: catch_test.luau; how often players meet them:
-- run_catch_sim.sh).
local Tides = require("./Tides")
local Catch = require("./Catch")
local Config = require("./Config")

local failures = 0
local function check(ok: boolean, text: string)
	if not ok then
		failures += 1
		print("FAIL: " .. text)
	end
end

local slotSeconds = Config.Tides.slotSeconds
-- A week of slots from Monday 2026-10-12
local start = 1791763200
local counts: { [string]: number } = {}
local previous = ""
local prismHours: { [number]: boolean } = {}
for i = 0, 7 * 72 - 1 do
	local t = start + i * slotSeconds + 1
	local tide, startsAt, endsAt = Tides.at(t)
	counts[tide.id] = (counts[tide.id] or 0) + 1
	check(tide.id ~= previous, `slot {i}: {tide.id} twice in a row`)
	check(endsAt - startsAt == slotSeconds, "slot length")
	if tide.id == "Prism" then
		prismHours[(startsAt // 3600) % 24] = true
	end
	previous = tide.id
end
for _, tide in Config.Tides.list do
	check((counts[tide.id] or 0) > 0, `{tide.id} never comes up in a week`)
end
check(counts.Prism == 28, `Prism Tides in a week: {counts.Prism} (want 28)`)
for _, hour in { 3, 9, 15, 21 } do
	check(prismHours[hour] == true, `no Prism Tide at {hour}:00 UTC`)
end
-- The forecast agrees with Tides.at
local now = start + 5000
for _, slot in Tides.forecast(now, 6) do
	check(Tides.at(slot.startsAt + 1).id == slot.tide, "forecast disagrees")
end
check(
	Tides.nextPrism(start) == start + 3 * 3600,
	`next Prism from Monday 00:00: {Tides.nextPrism(start) - start}`
)
-- Weeks
check(Tides.weekStart(Tides.week(start)) == start, "week start")
check(Tides.week(start - 1) == Tides.week(start) - 1, "Sunday is the week before")
local first = Config.Catch.weekly.start
local featured, week = Catch.weekly(first + 100)
check(week == 1 and featured ~= nil and featured.prey == "Grouper", "week 1's Catch of the Week")
local _, before = Catch.weekly(first - 100)
check(before == 0, "no Catch of the Week before week 1")
check(Tides.weekStart(Tides.week(first)) == first, "week 1 starts on a Monday")
-- Spawn rates (Shared/Catch: a rarity's rare fish a minute round one player)
local GOLDEN = Config.Catch.byId.Golden.rate
local PRISM = Config.Catch.byId.Prism.rate
local late = Config.Catch.spawn.rush.seconds + 1
check(Catch.rate("Prism", "Calm", false, late) == 0, "Prism outside its tide")
check(math.abs(Catch.rate("Golden", "Calm", false, late) - GOLDEN) < 1e-12, "Golden at its base rate")
check(math.abs(Catch.rate("Golden", "Golden", false, late) - 5 * GOLDEN) < 1e-12, "Golden Hour ×5")
check(
	math.abs(Catch.rate("Golden", "Golden", false, 0) - 5 * Config.Catch.spawn.rush.boost * GOLDEN) < 1e-12,
	"a tide's rush early on"
)
check(
	math.abs(Catch.rate("Golden", "Calm", false, 0) - GOLDEN) < 1e-12,
	"no rush for what a tide doesn't boost"
)
check(Catch.rate("Prism", "Prism", false, late) > 0, "Prism in the Prism Tide")
check(
	math.abs(Catch.rate("Prism", "Prism", false, 0) - Config.Catch.spawn.rush.boost * PRISM) < 1e-12,
	"Prism's rush"
)
local glowing = Config.Catch.byId.Glowing.rate
check(
	math.abs(Catch.rate("Glowing", "Biolum", true, late) - 3 * Config.Tides.deepGlow * glowing) < 1e-12,
	"Glowing ×5 in the deep at night"
)
check(
	math.abs(Catch.rate("Glowing", "Biolum", false, late) - 3 * glowing) < 1e-12,
	"Glowing ×3 on the shelf at night"
)
check(
	math.abs(Catch.rate("Silver", "Golden", false, 0) - Config.Catch.byId.Silver.rate) < 1e-12,
	"Silver steady"
)
-- The Catch of the Week's own stream: its rarity, the tide's boost on it
local week1, weeklyRate = Catch.weeklyRate(first + 100, "Calm", false)
check(week1 ~= nil and math.abs(weeklyRate - Config.Catch.weekly.rate) < 1e-12, "the week's stream")
local _, blood = Catch.weeklyRate(first + 100, "Blood", false)
check(
	math.abs(
		blood - Config.Catch.weekly.rate * (Config.Tides.byId.Blood.rarity[week1 and week1.rarity or ""] or 1)
	) < 1e-12,
	"the week's stream × the tide"
)
local _, none = Catch.weeklyRate(first - 100, "Calm", false)
check(none == 0, "no week's stream before week 1")
print(
	`tides: {counts.Calm} calm, {counts.Golden} golden, {counts.Blood} blood, {counts.Sardine} sardine, {counts.Biolum} biolum, {counts.Prism} prism a week`
)
if failures == 0 then
	print("tides_test: OK")
else
	error(`tides_test: {failures} failures`)
end
