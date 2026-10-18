--!strict
-- The Sunken Ruins' city (owner, 2026-10-18: "Sunken ruins need an extreme update
-- with the structures and detail. Very crude down there"; the look target is
-- assets/concepts/BiomeSunkenRuins.jpg). Shelf.luau lays its ground (a pale sand
-- plain, drifts against the stones, the sunken courtyard's pit) and
-- src/server/Ruins.luau builds the city from parts, plus smaller ruins spread over
-- the rest of the biome.
--
-- The city's frame: its middle (the great temple) stands `radius` studs out from
-- the hub at `angle` degrees (from +X toward +Z), on the deep floor. In that frame
-- x runs outward along the processional avenue (the gateway near the drop-off's
-- foot at about -245, the temple at 0, the back quarter past it), z across (toward
-- larger angles) and y up; studs. The sand chutes down the drop-off at 340 and 20
-- degrees keep their mounds clear of the theatre and the courtyard here.
return {
	angle = 2,
	radius = 1230,
	-- The city's box (its frame): no Terrain mounds under it, no outlying ruin or
	-- boulder inside it
	keepOut = { x = { -285, 235 }, z = { -205, 245 } },
	-- The sunken courtyard: its open middle (x along the city's x, z across), its
	-- floor `depth` under the deep floor, lined with walls `wall` thick; stairs
	-- `stair` wide come down from the avenue's side
	court = { x = -118, z = -146, inner = { 78, 68 }, depth = 18, wall = 5, stair = 22 },
	theatre = { x = -140, z = 152 },
	-- The pale sand plain the city stands on (Terrain discs, x, z, radius) and the
	-- drifts heaped against its stones (sand balls: x, z, radius; they rise about a
	-- fifth of their radius)
	sand = {
		{ -40, 10, 205 },
		{ -175, 120, 120 },
		{ -150, -95, 120 },
		{ 120, -40, 130 },
		{ 95, 120, 110 },
		{ -250, -20, 70 },
	},
	sandHeight = 3,
	drifts = {
		{ -40, -66, 24 },
		{ 10, -60, 20 },
		{ 52, 30, 26 },
		{ 60, -30, 18 },
		{ -60, 58, 22 },
		{ -200, -44, 16 },
		{ -170, 40, 18 },
		{ -262, 34, 20 },
		{ -262, -40, 18 },
		{ -190, 196, 26 },
		{ -60, 200, 22 },
		{ -66, -120, 20 },
		{ -178, -100, 18 },
		{ 140, 96, 22 },
		{ 196, -20, 26 },
		{ 110, -112, 20 },
	},
	-- Smaller ruins over the rest of the biome (gateways, colonnades, houses,
	-- obelisks, round shrines, a colossus's feet, glyph steles), each `apart` from
	-- the others and clear of the city
	outlying = { count = 15, angles = { 322, 62 }, radii = { 1010, 1440 }, apart = 170, margin = 60 },
	boulders = 34,
	-- How much of the stones grows coral, sponges, anemones, moss and sea grass
	growth = { top = 0.45, foot = 0.7 },

	colors = {
		marble = Color3.fromRGB(196, 212, 206), -- seafoam-white marble: columns, arches, statues
		shade = Color3.fromRGB(150, 172, 172), -- the platforms and walls
		weathered = Color3.fromRGB(122, 148, 150),
		teal = Color3.fromRGB(64, 140, 140), -- bands, lips, lintels
		dark = Color3.fromRGB(34, 56, 66), -- recesses, glyph panels, cracks
		paving = Color3.fromRGB(116, 136, 144),
		bronze = Color3.fromRGB(60, 98, 92), -- verdigris: braziers, basins
		moss = { Color3.fromRGB(70, 140, 104), Color3.fromRGB(98, 160, 92), Color3.fromRGB(56, 118, 112) },
		urn = { Color3.fromRGB(40, 130, 150), Color3.fromRGB(32, 72, 120), Color3.fromRGB(62, 150, 136) },
		mosaic = {
			Color3.fromRGB(46, 150, 156),
			Color3.fromRGB(30, 60, 112),
			Color3.fromRGB(214, 176, 74),
			Color3.fromRGB(200, 222, 220),
		},
	},
	-- The glyphs carved in the stones glow faintly (Neon), and a few lights read
	-- through the deep haze: few and big
	glyph = { color = Color3.fromRGB(84, 226, 222), transparency = 0.3, size = 2.2, stroke = 0.42 },
	light = { color = Color3.fromRGB(110, 232, 226), range = 56, brightness = 1.25 },
	-- Faint shafts of light from the surface onto the great temple
	shafts = { count = 2, strength = 0.1 },
}
