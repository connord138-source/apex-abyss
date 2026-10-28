-- Checks Shared/Hearts (HeartService, HeartController): a den is admired once a UTC
-- day per visitor, a new day starts the record afresh, other dens stay open, the Best
-- Dens frame belongs to one week, the top 3 earn it, and the signs' counts.
local Hearts = require("./Hearts")

local failures = 0
local function check(ok: boolean, text: string)
	if not ok then
		failures += 1
		print("FAIL: " .. text)
	end
end

-- A fresh save (DataService's template)
local record = { day = 0, dens = {} }
local day = 20389 -- 2026-10-28
local owner, other = 1234567, 7654321

check(not Hearts.admired(nil, day, owner), "no record: not admired")
check(not Hearts.admired(record, day, owner), "fresh record: not admired")
check(Hearts.count(record, day) == 0, "fresh record: none today")

Hearts.mark(record, day, owner)
check(record.day == day, "marking sets the day")
check(Hearts.admired(record, day, owner), "admired after marking")
check(not Hearts.admired(record, day, other), "another den is still open")
check(Hearts.count(record, day) == 1, "one today")
check(record.dens[tostring(owner)] == true, "keyed by the owner's id as a string (a save's keys)")

Hearts.mark(record, day, other)
check(Hearts.admired(record, day, other), "a second den admired the same day")
check(Hearts.admired(record, day, owner), "the first stays admired")
check(Hearts.count(record, day) == 2, "two today")

-- The next UTC day: every den is open again, and marking starts afresh
check(not Hearts.admired(record, day + 1, owner), "open again the next day")
check(Hearts.count(record, day + 1) == 0, "none counted for tomorrow yet")
Hearts.mark(record, day + 1, owner)
check(record.day == day + 1, "the record moves to the new day")
check(Hearts.admired(record, day + 1, owner), "admired on the new day")
check(not Hearts.admired(record, day + 1, other), "yesterday's other den is open again")
check(Hearts.count(record, day + 1) == 1, "one on the new day (yesterday's dropped)")
check(not Hearts.admired(record, day, owner), "an old day doesn't count once the record moved on")

-- The admin's "admire again today" puts a fresh record back
record = { day = 0, dens = {} }
check(not Hearts.admired(record, day + 1, owner), "reset: open again")

-- The Best Dens frame: the week it was earned for, only
local week = 2913
check(not Hearts.framed(nil, week), "no frame record")
check(not Hearts.framed(0, week), "0 = never framed")
check(Hearts.framed(week, week), "framed in its week")
check(not Hearts.framed(week, week + 1), "gone the next week")
check(not Hearts.framed(week - 1, week), "last week's frame is gone")

-- Who earns it: the board's top N (Config/Leaderboards BestDens frame = 3)
check(Hearts.earnsFrame(1, 3), "#1 earns the frame")
check(Hearts.earnsFrame(3, 3), "#3 earns the frame")
check(not Hearts.earnsFrame(4, 3), "#4 doesn't")
check(not Hearts.earnsFrame(0, 3), "no rank 0")
check(not Hearts.earnsFrame(1, nil), "a board without a frame gives none")

-- Counts on the signs
check(Hearts.short(0) == "0", "0")
check(Hearts.short(7) == "7", "7")
check(Hearts.short(999) == "999", "999")
check(Hearts.short(1240) == "1,240", `1,240 (got {Hearts.short(1240)})`)
check(Hearts.short(9999) == "9,999", "9,999")
check(Hearts.short(12345) == "12.3k", `12.3k (got {Hearts.short(12345)})`)
check(Hearts.short(150000) == "150k", `150k (got {Hearts.short(150000)})`)
check(Hearts.short(2500000) == "2.5m", `2.5m (got {Hearts.short(2500000)})`)
check(Hearts.short(-3) == "0", "never negative")
check(Hearts.TIP == 25, "the owner's tip is 25 coral (the proposal)")

if failures == 0 then
	print("hearts_test: OK")
else
	error(`hearts_test: {failures} failures`)
end
