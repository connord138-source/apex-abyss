--!strict
-- Chum and the Whale Fall (GDD §5 "Chum", §8 "Tide events"; built 2026-10-14).
--
-- Chum: a fish that gets eaten (by a player or a creature) bursts part of its lost
-- Haul into a cloud of chunks that sink slowly where it died; any fish swallows a
-- chunk by swimming into it (no button, like shrimp), and AI predators nearby come
-- for the cloud. During a Blood Tide the water is full of it: slicks of chum appear
-- round players out in the biomes.
--
-- The Whale Fall: a dead whale sinks into a random biome about every 26 minutes
-- (between the world bosses), announced a minute ahead with a marker on the map; it
-- settles on the floor and feeds the whole server for five minutes, its chunks
-- growing back as they're eaten. Chunk sizes follow the biome's level, so a whale in
-- the Trench is worth far more than one in the kelp.
return {
	share = 0.4, -- of a lost Haul bursts into chum (the eater's own share comes on top)
	minHaul = 0.5, -- a lost Haul under this (kg) bursts nothing
	chunks = { min = 4, max = 14 },
	chunkKg = 0.6, -- a cloud has about one chunk per this many kg (between min and max)
	lifetime = 45, -- seconds a cloud stays
	sink = 1.4, -- studs a second a cloud sinks
	sinkMax = 28, -- how far it sinks at most (and never below the floor)
	spread = { base = 3, perLength = 0.5 }, -- studs round the death spot, + per stud of the fish
	lure = 320, -- AI predators within this many studs swim to a cloud
	-- A chunk's kg in a biome: this × the banked mass at the middle of the biome's
	-- level range (Kelp ~0.15, Reef ~1.3, Open Blue ~4.5, Trench ~460)
	biomeChunk = 0.05,
	minChunk = 0.15,
	-- Blood Tide slicks: every `every` seconds, one appears `ring` studs from a random
	-- player out in a biome, `chunks` chunks of the biome's size
	slick = { every = 20, chunks = 7, lifetime = 40, ring = { 50, 140 } },
	whale = {
		every = 26 * 60, -- seconds between whale falls
		first = 13 * 60, -- the first, after the server starts
		studioEvery = 6 * 60,
		studioFirst = 90,
		-- Quiet water after a whale before the next is announced (PC overnight
		-- 2026-10-14: in Studio the next was announced a second after one ended,
		-- so one was always coming or under way)
		rest = 120,
		warn = 60, -- announced this long before it starts to sink
		height = 150, -- starts this far above the floor
		sinkSeconds = 30,
		feed = 300, -- seconds it lasts once it starts sinking
		chunks = 18,
		respawn = 14, -- a chunk grows back this long after it's eaten
		chunkScale = 3, -- × the biome's chunk
		length = 60, -- the carcass, studs
		-- The marker over a settled whale, through the haze (ChumController): studs
		-- from the camera, none inside `hide`, full from `full`, fading out from
		-- `fade`, gone past `range` (PC 2026-10-17 round 2, W1c: from 120 studs up the
		-- plume was lost in the haze)
		marker = { hide = 70, full = 90, fade = 620, range = 700 },
	},
}
