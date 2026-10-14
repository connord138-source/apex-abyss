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
	-- The bait's kg: this × the banked mass at the middle of the biome's level range
	bait = 0.4,
	minBait = 0.4,
	reel = 7, -- studs a second the line pulls a hooked fish up
	hold = 9, -- seconds before a hooked fish is landed
	struggleNeed = 10, -- mashes to break free
	struggleGap = 0.15, -- seconds between mashes that count
	minHooked = 3, -- seconds on the line before a fish can break free
	landedShare = 0.3, -- of the Haul the fisherman keeps when it lands you
	biteRange = 26, -- a podmate biting within this many studs of a hooked fish cuts the line
}
