--!strict
-- Shells: the roll currency, lying around the sea. Every player has their own
-- shells (no racing other players for them); one you pick up comes back for you
-- after `respawn` seconds. Spots are placed at server start on whatever's under
-- them (seabed, rocks), and golden shells lie on the trench floor.
return {
	spots = 150, -- across the Kelp Shallows
	goldenSpots = 14, -- on the trench floor
	value = 1,
	goldenValue = 5,
	respawn = 240,
	reach = 2.5, -- studs from the mouth, plus half the fish's length
	-- Bigger prey sometimes carry shells: chance, and how many
	preyDrops = {
		Grouper = { chance = 0.25, min = 1, max = 2 },
		Barracuda = { chance = 0.35, min = 1, max = 3 },
		ReefShark = { chance = 0.5, min = 2, max = 4 },
	} :: { [string]: { chance: number, min: number, max: number } },
}
