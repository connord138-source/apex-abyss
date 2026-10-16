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
		Rock = { base = Enum.Material.Rock, id = 0, studsPerTile = 14, pattern = "Organic" },
		Slate = { base = Enum.Material.Slate, id = 0, studsPerTile = 14, pattern = "Organic" },
		Basalt = { base = Enum.Material.Basalt, id = 0, studsPerTile = 12, pattern = "Organic" },
		Sandstone = { base = Enum.Material.Sandstone, id = 0, studsPerTile = 14, pattern = "Organic" },
		Sand = { base = Enum.Material.Sand, id = 0, studsPerTile = 16, pattern = "Organic" },
		Mud = { base = Enum.Material.Mud, id = 0, studsPerTile = 16, pattern = "Organic" },
		CrackedLava = { base = Enum.Material.CrackedLava, id = 0, studsPerTile = 12, pattern = "Organic" },
		Pebble = { base = Enum.Material.Pebble, id = 0, studsPerTile = 8, pattern = "Regular" },
		Marble = { base = Enum.Material.Marble, id = 0, studsPerTile = 14, pattern = "Organic" },
		WoodPlanks = { base = Enum.Material.WoodPlanks, id = 0, studsPerTile = 8, pattern = "Regular" },
		Wood = { base = Enum.Material.Wood, id = 0, studsPerTile = 8, pattern = "Regular" },
	} :: { [string]: Toon },
}
