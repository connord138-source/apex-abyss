--!strict
-- Shells: the roll currency, lying around the sea. Every player has their own
-- shells (no racing other players for them); one you pick up comes back for you
-- after `respawn` seconds. Spots are placed at server start on whatever's under
-- them (seabed, rocks), and golden shells lie on the trench floor.
return {
	spots = 300, -- across the shelf (owner, 2026-10-20: "need more shell spawns too. Atleast double"; was 150)
	goldenSpots = 28, -- on the trench floor (was 14)
	value = 1,
	goldenValue = 5,
	respawn = 240,
	reach = 2.5, -- studs from the mouth, plus half the fish's length
	-- Bigger prey sometimes carry shells: chance, and how many
	preyDrops = {
		Grouper = { chance = 0.25, min = 1, max = 2 },
		MahiMahi = { chance = 0.25, min = 1, max = 2 },
		YellowfinTuna = { chance = 0.3, min = 1, max = 3 },
		Barracuda = { chance = 0.35, min = 1, max = 3 },
		ReefShark = { chance = 0.5, min = 2, max = 4 },
		-- (the third prey batch's big fish, 2026-10-19)
		Coelacanth = { chance = 0.25, min = 1, max = 2 },
		Swordfish = { chance = 0.35, min = 1, max = 3 },
		OceanSunfish = { chance = 0.5, min = 2, max = 4 },
		Oarfish = { chance = 0.5, min = 2, max = 4 },
		-- (the fourth batch's big one, 2026-10-19)
		HumpheadWrasse = { chance = 0.3, min = 1, max = 3 },
	} :: { [string]: { chance: number, min: number, max: number } },
}
