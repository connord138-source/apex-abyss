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
export type Region = { number } -- { start, length } in seconds

local Sounds: { id: number, regions: { [string]: Region }, loops: { [string]: boolean } } = {
	id = 0, -- the uploaded apex_sfx.ogg (Creator Hub → Development Items → Audio)
	regions = {
		-- BEGIN REGIONS (written by tools/audio/make_sfx.py; { start, length } in seconds)
		AmbientShallow = { 0.100, 14.500 },
		AmbientDeep = { 14.650, 16.500 },
		AmbientHub = { 31.200, 12.500 },
		Bubble = { 43.750, 0.300 },
		Bubbles = { 44.400, 0.900 },
		Dash = { 45.650, 0.900 },
		Snap = { 46.900, 0.350 },
		Bite = { 47.600, 0.700 },
		Chomp = { 48.650, 0.800 },
		Hurt = { 49.800, 0.800 },
		Eaten = { 50.950, 1.600 },
		Heal = { 52.900, 1.200 },
		Bank = { 54.450, 2.000 },
		LevelUp = { 56.800, 2.200 },
		Shell = { 59.350, 0.500 },
		GoldenShell = { 60.200, 0.900 },
		Forage = { 61.450, 0.300 },
		Dig = { 62.100, 0.900 },
		ChestOpen = { 63.350, 1.800 },
		Reel = { 65.500, 0.700 },
		Tick = { 66.550, 0.080 },
		RollCoral = { 66.980, 0.800 },
		RollCommon = { 68.130, 1.000 },
		RollRare = { 69.480, 1.600 },
		RollEpic = { 71.430, 2.200 },
		RollLegendary = { 73.980, 2.900 },
		RollMythic = { 77.230, 3.400 },
		RollAbyssal = { 80.980, 3.600 },
		RollTrophy = { 84.930, 2.800 },
		Warning = { 88.080, 0.800 },
		TooBig = { 89.230, 0.600 },
		Banner = { 90.180, 0.800 },
		BossWarning = { 91.330, 3.400 },
		BossRise = { 95.080, 2.600 },
		BossPhase = { 98.030, 1.500 },
		BossDefeat = { 99.880, 3.600 },
		Breach = { 103.830, 1.800 },
		Grab = { 105.980, 0.900 },
		Ink = { 107.230, 1.000 },
		UiOpen = { 108.580, 0.350 },
		UiClick = { 109.280, 0.080 },
		-- END REGIONS
	},
	loops = { AmbientShallow = true, AmbientDeep = true, AmbientHub = true },
}

return Sounds
