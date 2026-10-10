-- Checks Shared/Tides and Shared/Catch: the Prism Tide's schedule, no tide twice in a
-- row, every tide turns up, weeks, and the rare-catch odds.
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
check(Tides.nextPrism(start) == start + 3 * 3600, `next Prism from Monday 00:00: {Tides.nextPrism(start) - start}`)
-- Weeks
check(Tides.weekStart(Tides.week(start)) == start, "week start")
check(Tides.week(start - 1) == Tides.week(start) - 1, "Sunday is the week before")
local first = Config.Catch.weekly.start
local featured, week = Catch.weekly(first + 100)
check(week == 1 and featured ~= nil and featured.prey == "Grouper", "week 1's Catch of the Week")
local _, before = Catch.weekly(first - 100)
check(before == 0, "no Catch of the Week before week 1")
check(Tides.weekStart(Tides.week(first)) == first, "week 1 starts on a Monday")
-- Odds
local calm = Catch.chances("Minnow", "Calm", false, start + 100)
check(calm.Prism == 0, "Prism outside its tide")
check(math.abs(calm.Golden - 1 / 35) < 1e-12, "Golden at its base odds")
local golden = Catch.chances("Minnow", "Golden", false, start + 100)
check(math.abs(golden.Golden - 5 / 35) < 1e-12, "Golden Hour ×5")
local prism = Catch.chances("Minnow", "Prism", false, start + 100)
check(prism.Prism > 0, "Prism in the Prism Tide")
local biolumDeep = Catch.chances("Sardine", "Biolum", true, start + 100)
check(math.abs(biolumDeep.Glowing - 5 / 180) < 1e-12, "Glowing ×5 in the deep at night")
local weeklyFish = Catch.chances("Grouper", "Calm", false, first + 100)
check(math.abs(weeklyFish.Crystal - 3 / 900) < 1e-12, "the featured fish ×3")
-- Rolling: the rarest first, and plain past the sum
check(Catch.roll(0, golden) == "Crystal", "roll 0 is the rarest available")
check(Catch.roll(0.99, golden) == nil, "a high roll is plain")
-- Simulated spawn rates under Calm
math.randomseed(1)
local tally: { [string]: number } = {}
local n = 2000000
for _ = 1, n do
	local id = Catch.roll(math.random(), calm)
	if id then
		tally[id] = (tally[id] or 0) + 1
	end
end
for _, rarity in Config.Catch.rarities do
	local want = calm[rarity.id]
	local got = (tally[rarity.id] or 0) / n
	check(want == 0 and got == 0 or math.abs(got - want) / want < 0.05, `{rarity.id}: {got} vs {want}`)
end
print(`tides: {counts.Calm} calm, {counts.Golden} golden, {counts.Blood} blood, {counts.Sardine} sardine, {counts.Biolum} biolum, {counts.Prism} prism a week`)
if failures == 0 then
	print("tides_test: OK")
else
	error(`tides_test: {failures} failures`)
end
