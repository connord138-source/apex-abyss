--!strict
-- Baited hooks from boats (GDD §5 "Hooks from above"; built 2026-10-14): fishing
-- boats drift over the sea, their dark hulls seen from below against the surface,
-- and now and then drop a line with a fish on the hook. The bait is a big meal (it
-- goes on your Haul when you swallow it), but you're hooked: the line reels you up
-- toward the boat. Mash BITE or DASH to break free, or have a podmate bite the line;
-- if it lands you, the fisherman keeps a share of your Haul.
return {
	boats = 5,
	band = { 280, 1300 }, -- studs from the middle the boats drift in (clear of the hub)
	drift = 6, -- studs a second while not fishing
	between = { 20, 45 }, -- seconds drifting between lines
	line = 70, -- seconds a line stays down untouched
	depth = { 60, 300 }, -- the bait this far under the surface (and 20+ over the floor)
	-- What the bait puts on the Haul: this share of the taker's own full Haul
	-- (Shared/Size haulCap), so it's the same big meal at every level (a minute or two
	-- of hunting) and stops at a full Haul. It was kg by the biome under the boat ×
	-- the Haul rate, capped at 3 levels' worth, until the 2026-10-19 pace: a LV 21
	-- fish took a 4.6 t Trench bait (PC follow-up 2026-10-14), and in kg × a rate that
	-- climbs with level it would barely move a LV 10 Haul and fill a LV 90 one.
	baitHaul = 0.5,
	reel = 7, -- studs a second the line pulls a hooked fish up
	hold = 9, -- seconds before a hooked fish is landed
	struggleNeed = 10, -- mashes to break free
	struggleGap = 0.15, -- seconds between mashes that count
	minHooked = 3, -- seconds on the line before a fish can break free
	landedShare = 0.3, -- of the Haul the fisherman keeps when it lands you
	biteRange = 26, -- a podmate biting within this many studs of a hooked fish cuts the line
}
