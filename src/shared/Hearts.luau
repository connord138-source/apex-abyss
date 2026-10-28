--!strict
-- Den hearts (owner, 2026-10-28, the den proposal's "Den visits that count",
-- docs/proposals/2026-10-28-den-expansion.md §3): a visitor admires another
-- player's den once a UTC day; the owner gets a heart, a coral tip and a point on
-- the weekly Best Dens board (Config/Leaderboards), whose top 3 wear a gold frame on
-- their den's signs the next week. The rules both sides read (HeartService,
-- HeartController). Pure: no Roblox globals, so tools/tests/run_hearts.sh runs it in
-- the luau CLI.
local Hearts = {}

Hearts.TIP = 25 -- coral to the den's owner for each heart (a fixed tip: addCoral)

-- What a visitor admired: the UTC day (Shared/Tides.day) and the owners' user ids
-- (as strings: a save's keys) admired that day
export type Admired = { day: number, dens: { [string]: boolean } }

-- Whether the visitor already admired `ownerId`'s den on `day` (a record from an
-- earlier day counts for nothing)
function Hearts.admired(record: Admired?, day: number, ownerId: number): boolean
	return record ~= nil and record.day == day and record.dens[tostring(ownerId)] == true
end

-- Marks `ownerId`'s den admired on `day`; a record from an earlier day starts afresh
function Hearts.mark(record: Admired, day: number, ownerId: number)
	if record.day ~= day then
		record.day = day
		record.dens = {}
	end
	record.dens[tostring(ownerId)] = true
end

-- How many dens the visitor admired on `day`
function Hearts.count(record: Admired?, day: number): number
	if record == nil or record.day ~= day then
		return 0
	end
	local n = 0
	for _ in record.dens do
		n += 1
	end
	return n
end

-- Whether a den's signs wear the Best Dens frame in `week` (Shared/Tides.week): the
-- den record's `frame` is the week it was earned for (the week after the one ranked)
function Hearts.framed(frameWeek: number?, week: number): boolean
	return frameWeek ~= nil and frameWeek > 0 and frameWeek == week
end

-- Whether last week's rank on a board earns the frame (`frame`: the board's top N)
function Hearts.earnsFrame(rank: number, frame: number?): boolean
	return frame ~= nil and rank >= 1 and rank <= frame
end

-- A heart count for a sign: "7", "1,240", then "12.4k" (signs have room for ~5)
function Hearts.short(hearts: number): string
	local n = math.max(0, math.floor(hearts))
	if n < 10000 then
		local text = tostring(n)
		if n >= 1000 then
			text = `{string.sub(text, 1, #text - 3)},{string.sub(text, -3)}`
		end
		return text
	elseif n < 1000000 then
		local k = math.floor(n / 100) / 10
		return if k >= 100 then `{math.floor(k)}k` else `{k}k`
	end
	return `{math.floor(n / 100000) / 10}m`
end

return Hearts
