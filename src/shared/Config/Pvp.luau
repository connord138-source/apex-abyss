--!strict
-- PvP twists and teams (GDD §5, §6; built 2026-10-14): pods, schooling, the Apex
-- bounty and depth pressure.
return {
	-- Pods of up to 3 (POD on the HUD, or the Shop on a controller): podmates can't
	-- eat or bite each other, swimming in a podmate's slipstream (close behind it)
	-- is faster, and when one eats a player the others nearby get a share of the Haul
	pods = {
		size = 3,
		inviteSeconds = 30,
		shareRange = 220, -- studs: podmates this close to a kill get its share
		killShare = 0.5, -- of the eater's gain, to each podmate in range (on top)
		slipstream = { range = 18, cone = 0.7, speed = 1.15 },
	},
	-- Schooling: everyone who bit the same fish in the last `window` seconds (within
	-- `range` studs of each other) bites with their combined mass, so a school of
	-- small fish can take down one far bigger than any of them
	school = { range = 40, window = 2.5, bonus = 0.15 },
	-- The Apex bounty: the biggest fish in the server (live mass, at least `minLevel`,
	-- with at least `minPlayers` in the server) wears a crown everyone sees on the map;
	-- the bounty grows while it's out of the hub, and whoever eats it takes it
	apex = {
		minPlayers = 2,
		minLevel = 10,
		takeOver = 1.1, -- a rival must be this much heavier to take the crown
		base = 500, -- coral
		perMinute = 150, -- while the Apex swims out of the hub
		cap = 6000,
		-- Paid only once the Apex has swum `minReign` seconds out of the hub, and never
		-- twice between the same two players within `pairCooldown` (no trading the crown)
		minReign = 120,
		pairCooldown = 20 * 60,
		title = "Apex Hunter", -- for the first bounty claimed
	},
	-- Depth pressure gates the deep biomes (owner's design: "depth pressure gates
	-- biomes, not walls"): below a band's depth a fish under its level feels the
	-- pressure build for `grace` seconds, then loses `damage` of its max health a
	-- second until it rises. Each level of the Outfitter's Pressure Hide counts as
	-- `Perks.depth` extra levels. Bands sit 10 levels under the biomes they guard.
	pressure = {
		bands = {
			{ y = -60, level = 25, name = "the drop-off" }, -- off the shelf (Open Blue LV 35)
			{ y = -330, level = 40, name = "the deep floor" }, -- the Ruins (LV 50)
			{ y = -480, level = 55, name = "the vent basins" }, -- the Vents (LV 65)
			{ y = -640, level = 70, name = "the Trench's depths" }, -- the Trench (LV 80)
		},
		grace = 6,
		damage = 0.03,
		-- A world boss fight is for the whole server: no pressure within this many
		-- studs of a boss that's up (the Giant Squid lurks below the deepest band)
		bossRange = 500,
	},
}
