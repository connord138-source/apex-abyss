--!strict
-- The game's sound pack. Every sound lives back to back in ONE audio file,
-- assets/audio/apex_sfx.ogg, synthesized by tools/audio/make_sfx.py, so the pack is
-- a single upload; src/client/Sfx.luau plays each sound's own stretch of it
-- (Sound.PlaybackRegion), and AmbienceController loops the three beds. Until `id`
-- is set the game is silent apart from a few pinged cues (Sfx's fallbacks).
--
-- Beds: AmbientShallow, AmbientDeep, AmbientHub (loops, crossfaded by depth).
-- One-shots: Bubble(s), Dash, Snap (a bite that misses), Bite, Chomp (an eat),
-- Hurt, Eaten, Heal, Bank, LevelUp, Shell, GoldenShell, Forage, Dig, ChestOpen,
-- Reel and Tick (the roll reel), Roll<Tier> stingers, Warning (a predator's tell),
-- TooBig, Banner (a biome), Boss* (warning, rise, phase, defeat), Breach, Grab,
-- Ink, UiOpen, UiClick.
--
-- v2 (owner, 2026-10-11: "The music is horrible too ... it's just random bells"):
-- no bells in the beds or everyday cues (tools/audio/make_sfx.py); real music is
-- Config/Music. v3 (owner, 2026-10-20: the bite "sounds like a coconut falling"):
-- Snap and Bite are teeth clacking shut and a wet crunch, nothing else changed. Until
-- v3's id is pasted into `id`, the v2 pack (`legacy`) keeps playing.
export type Region = { number } -- { start, length } in seconds
export type Pack = { id: number, regions: { [string]: Region }, skip: { [string]: boolean }? }

local Sounds: {
	id: number,
	regions: { [string]: Region },
	loops: { [string]: boolean },
	legacy: Pack,
} =
	{
		id = 0, -- the uploaded v3 apex_sfx.ogg (Creator Hub → Development Items → Audio); 0 plays `legacy`
		regions = {
			-- BEGIN REGIONS (written by tools/audio/make_sfx.py; { start, length } in seconds)
			AmbientShallow = { 0.100, 14.500 },
			AmbientDeep = { 14.650, 16.500 },
			AmbientHub = { 31.200, 14.500 },
			Bubble = { 45.750, 0.300 },
			Bubbles = { 46.400, 0.900 },
			Dash = { 47.650, 0.900 },
			Snap = { 48.900, 0.350 },
			Bite = { 49.600, 0.600 },
			Chomp = { 50.550, 0.800 },
			Hurt = { 51.700, 0.800 },
			Eaten = { 52.850, 1.600 },
			Heal = { 54.800, 1.200 },
			Bank = { 56.350, 2.000 },
			LevelUp = { 58.700, 2.200 },
			Shell = { 61.250, 0.500 },
			GoldenShell = { 62.100, 0.900 },
			Forage = { 63.350, 0.300 },
			Dig = { 64.000, 0.900 },
			ChestOpen = { 65.250, 1.800 },
			Reel = { 67.400, 0.700 },
			Tick = { 68.450, 0.080 },
			RollCoral = { 68.880, 0.800 },
			RollCommon = { 70.030, 1.000 },
			RollRare = { 71.380, 1.600 },
			RollEpic = { 73.330, 2.200 },
			RollLegendary = { 75.880, 2.900 },
			RollMythic = { 79.130, 3.400 },
			RollAbyssal = { 82.880, 3.600 },
			RollTrophy = { 86.830, 2.800 },
			Warning = { 89.980, 0.800 },
			TooBig = { 91.130, 0.600 },
			Banner = { 92.080, 0.800 },
			BossWarning = { 93.230, 3.400 },
			BossRise = { 96.980, 2.600 },
			BossPhase = { 99.930, 1.500 },
			BossDefeat = { 101.780, 3.600 },
			Breach = { 105.730, 1.800 },
			Grab = { 107.880, 0.900 },
			Ink = { 109.130, 1.000 },
			UiOpen = { 110.480, 0.350 },
			UiClick = { 111.180, 0.080 },
			-- END REGIONS
		},
		loops = { AmbientShallow = true, AmbientDeep = true, AmbientHub = true },
		-- The v2 pack (uploaded 2026-10-11), played while `id` is 0: everything but
		-- the v3 bite sounds is the same
		legacy = {
			id = 126295816698039,
			regions = {
				AmbientShallow = { 0.100, 14.500 },
				AmbientDeep = { 14.650, 16.500 },
				AmbientHub = { 31.200, 14.500 },
				Bubble = { 45.750, 0.300 },
				Bubbles = { 46.400, 0.900 },
				Dash = { 47.650, 0.900 },
				Snap = { 48.900, 0.350 },
				Bite = { 49.600, 0.700 },
				Chomp = { 50.650, 0.800 },
				Hurt = { 51.800, 0.800 },
				Eaten = { 52.950, 1.600 },
				Heal = { 54.900, 1.200 },
				Bank = { 56.450, 2.000 },
				LevelUp = { 58.800, 2.200 },
				Shell = { 61.350, 0.500 },
				GoldenShell = { 62.200, 0.900 },
				Forage = { 63.450, 0.300 },
				Dig = { 64.100, 0.900 },
				ChestOpen = { 65.350, 1.800 },
				Reel = { 67.500, 0.700 },
				Tick = { 68.550, 0.080 },
				RollCoral = { 68.980, 0.800 },
				RollCommon = { 70.130, 1.000 },
				RollRare = { 71.480, 1.600 },
				RollEpic = { 73.430, 2.200 },
				RollLegendary = { 75.980, 2.900 },
				RollMythic = { 79.230, 3.400 },
				RollAbyssal = { 82.980, 3.600 },
				RollTrophy = { 86.930, 2.800 },
				Warning = { 90.080, 0.800 },
				TooBig = { 91.230, 0.600 },
				Banner = { 92.180, 0.800 },
				BossWarning = { 93.330, 3.400 },
				BossRise = { 97.080, 2.600 },
				BossPhase = { 100.030, 1.500 },
				BossDefeat = { 101.880, 3.600 },
				Breach = { 105.830, 1.800 },
				Grab = { 107.980, 0.900 },
				Ink = { 109.230, 1.000 },
				UiOpen = { 110.580, 0.350 },
				UiClick = { 111.280, 0.080 },
			},
		},
	}

return Sounds
