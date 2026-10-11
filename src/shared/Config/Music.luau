--!strict
-- Background music (owner, 2026-10-11: "The music is horrible too that needs to be
-- changed it's just random bells it sounds like"). There was no music before: what
-- played was the sound pack's ambience beds, and the hub's bed pinged a glockenspiel
-- at random pitches every second or two. MusicController plays these lists by where
-- the camera is (the hub, each biome, the Trench's dark, a boss close by), shuffled,
-- crossfading when the place changes and picking a track up where it left off when
-- you swim back within two minutes. It ducks under the roll reveal.
--
-- Every id is Roblox's licensed APM library (Creator Store → Audio → Music, uploader
-- @APMOfficial; public, free in any experience). Most come from one album, David
-- Lindsay's "Underwater Kingdom", so the whole sea sounds of a piece: Kelp Forest for
-- the Kelp Shallows, Great Barrier Reef for the reef, Infinite Expanse and Endless
-- Sonar for the Open Blue, Mariana Trench for the Trench. "Underscore" cuts drop
-- the lead melody (quieter under play), "Full instrumental" keeps it.
--
-- Subtle, never loud (the Hatch & Snatch rule): licensed tracks are mastered very
-- differently, so each track's own loudness is measured in Studio (PlaybackLoudness
-- averaged over the track; it ignores Volume) and kept in `loudness`; it then plays
-- at Volume = its list's `target` ÷ that, so every track sits at the same level. A
-- track not measured yet plays at `volume`. An empty list falls back to `fallback`.
export type Music = {
	volume: number,
	loudness: { [number]: number },
	target: { [string]: number },
	fadeSeconds: number,
	gapSeconds: number,
	settleSeconds: number,
	resumeSeconds: number,
	lists: { [string]: { number } },
	biomes: { [string]: string },
	bosses: { [string]: string },
	fallback: string,
}

local Music: Music = {
	volume = 0.14,
	loudness = { -- by id: its average PlaybackLoudness (the PC session measures these)
	},
	-- loudness × Volume per list: calm under play, the boss a little forward
	target = {
		hub = 13,
		shallows = 14,
		reef = 14,
		wreck = 13,
		openBlue = 13,
		ruins = 13,
		vents = 13,
		trench = 12,
		megalodon = 17,
		squid = 17,
	},
	fadeSeconds = 3, -- the crossfade between tracks and lists
	gapSeconds = 5, -- quiet between two tracks
	settleSeconds = 4, -- a new place must hold this long before its music starts (no flip-flop at a border)
	resumeSeconds = 120, -- back in a place within this, its track carries on where it was
	lists = {
		-- The cavern and the dens (and the start screen): calm, home
		hub = {
			87173382902467, -- Aquatic Atmosphere - Underscore (David Lindsay, Underwater Kingdom)
			80280537117632, -- Beneath The Waves - Underscore (Underwater Kingdom)
		},
		-- The Kelp Shallows: light through the kelp, wonder
		shallows = {
			97633872384292, -- Kelp Forest - Full instrumental (Underwater Kingdom)
			137371958480889, -- Beneath The Waves - Full instrumental (Underwater Kingdom)
			126273536255517, -- Aquatic Atmosphere - Full instrumental (Underwater Kingdom)
		},
		-- The Coral Reef: colour and life
		reef = {
			83836973342490, -- Great Barrier Reef - Full instrumental (Underwater Kingdom)
			73300187566988, -- Ethereal Expedition - Full instrumental (Underwater Kingdom)
		},
		-- The Shipwreck Graveyard: lonely, a little uneasy
		wreck = {
			135491429739395, -- Desolate Ocean - Full instrumental (Underwater Kingdom)
			88282617098851, -- Underwater Kingdom - Underscore (Underwater Kingdom)
		},
		-- The Open Blue: vast open water, something out there
		openBlue = {
			93304688532873, -- Infinite Expanse - Full instrumental (Underwater Kingdom)
			81352888696689, -- Endless Sonar - Full instrumental (Underwater Kingdom)
		},
		-- The Sunken Ruins: ancient, mysterious
		ruins = {
			101185329860830, -- Ethereal Expedition - Underscore (Underwater Kingdom)
			88282617098851, -- Underwater Kingdom - Underscore (Underwater Kingdom)
		},
		-- The Hydrothermal Vents: deep, heavy
		vents = {
			126481946316902, -- Deep Sea Descent - Full instrumental (Underwater Kingdom)
			74998943024781, -- Abyssal Plain - Full instrumental (Underwater Kingdom)
		},
		-- The Trench in its dark: creepy (owner, 2026-10-11: "a creepy vibe for the trench")
		trench = {
			134719419887499, -- Mariana Trench - Underscore (Underwater Kingdom)
			9040019476, -- The Deep Sea Dwellers (Cezame, Underwater Exploration: "abyssal, unlinear & mysterious")
			102811657791599, -- Nightmare of the Abyss (Denis Jean Levaillant, Scary Drones & Textures)
		},
		-- A boss close by
		megalodon = {
			9040160517, -- Dangerous Predator (Kosinus Trailers: ominous drone into dark hybrid orchestra)
			9043603934, -- Predator (a) (KPM, Dark Nature: "stealthy, dark, prowling hybrid orchestral")
		},
		squid = {
			1837224922, -- The Kraken Lurks 2 (Thierry Caroubi, Cinematic Odyssey)
			9043603934, -- Predator (a) (KPM, Dark Nature)
		},
	},
	-- Config/Biomes id → list
	biomes = {
		KelpShallows = "shallows",
		CoralReef = "reef",
		ShipwreckGraveyard = "wreck",
		OpenBlue = "openBlue",
		SunkenRuins = "ruins",
		HydrothermalVents = "vents",
		AbyssalTrench = "trench",
	},
	-- Config/Bosses id → list
	bosses = { Megalodon = "megalodon", GiantSquid = "squid" },
	fallback = "shallows",
}

return Music
