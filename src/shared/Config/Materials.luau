--!strict
-- Toon materials (owner, 2026-10-16: "Walls need to look more like schedule 1 or how
-- to fish graphics. Looks too much like garrymod textures or semi realistic for our
-- purposes"): every stock material the world is built from is swapped, game-wide,
-- for a flat cel-shaded tile (tools/textures/make_toon_materials.py →
-- assets/textures/toon_<Name>.png): big flat plates, bands and planks with bold seams
-- and a lit edge, in grey so the world's own colours still tint them (CrackedLava
-- carries its own glowing cracks). MaterialService base-material overrides put them
-- on Terrain and parts alike.
--
-- The variants live in the place file (a game script can't set a MaterialVariant's
-- maps, "lacking capability Plugin"): upload the PNGs as Images, paste each id here,
-- then run tools/studio/make_toon_materials.luau in Studio's Command Bar (edit mode)
-- and save the place. WorldService warns at start about one with an id but no
-- variant. An id of 0 leaves that material stock.
export type Toon = {
	base: Enum.Material,
	id: number, -- the uploaded image (0 = not yet)
	studsPerTile: number,
	pattern: "Organic" | "Regular", -- Organic breaks up the tiling on big surfaces
}

return {
	-- The maps average about 0.8, and Roblox multiplies them by the colour; while a
	-- material's toon variant is on, the Terrain's colour for it is lifted this much
	-- (Cave.apply) so the world keeps its brightness
	terrainLift = 1.22,
	toon = {
		Rock = { base = Enum.Material.Rock, id = 89603876982877, studsPerTile = 14, pattern = "Organic" },
		Slate = { base = Enum.Material.Slate, id = 119359993464917, studsPerTile = 14, pattern = "Organic" },
		Basalt = { base = Enum.Material.Basalt, id = 111910319680317, studsPerTile = 12, pattern = "Organic" },
		Sandstone = {
			base = Enum.Material.Sandstone,
			id = 131675162443724,
			studsPerTile = 14,
			pattern = "Organic",
		},
		Sand = { base = Enum.Material.Sand, id = 106165081904025, studsPerTile = 16, pattern = "Organic" },
		Mud = { base = Enum.Material.Mud, id = 95002228991579, studsPerTile = 16, pattern = "Organic" },
		CrackedLava = {
			base = Enum.Material.CrackedLava,
			id = 82259631041878,
			studsPerTile = 12,
			pattern = "Organic",
		},
		Pebble = { base = Enum.Material.Pebble, id = 128471083984632, studsPerTile = 8, pattern = "Regular" },
		Marble = { base = Enum.Material.Marble, id = 135582267178085, studsPerTile = 14, pattern = "Organic" },
		WoodPlanks = {
			base = Enum.Material.WoodPlanks,
			id = 140248237259309,
			studsPerTile = 8,
			pattern = "Regular",
		},
		Wood = { base = Enum.Material.Wood, id = 117559280684803, studsPerTile = 8, pattern = "Regular" },
		-- The dens' rock: Rock's plates (the same image) in the dens' own tan.
		-- Sandstone's long bands read as wood grain on a den's walls (PC 2026-10-16
		-- round 2, T1), and a Terrain colour is per material, so the dens take a
		-- material nothing else in the world uses
		Limestone = {
			base = Enum.Material.Limestone,
			id = 89603876982877,
			studsPerTile = 12,
			pattern = "Organic",
		},
		-- The Blue Hole's walls (owner, 2026-10-21: "look how much different your hole
		-- looks from the mockup"): Rock's plates (the same image) in the hole's deep
		-- blue, on a material nothing else uses (a Terrain colour is per material)
		Glacier = {
			base = Enum.Material.Glacier,
			id = 89603876982877,
			studsPerTile = 14,
			pattern = "Organic",
		},
	} :: { [string]: Toon },
}
