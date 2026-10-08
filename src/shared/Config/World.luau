--!strict
-- The map's layout (owner, 2026-10-07: "biomes need to be spread out and clearly
-- different biomes with some dependent on depth off of a ocean shelf that would be
-- at the end of the lower level zones and begin the higher level zones. coral zone
-- being the last of the shallower zones"; 2026-10-08: "the entirety of the map is
-- still too small ... each biome made larger ... needs MUCH MUCH more depth too. Far
-- too shallow of a map"). The hub seamount stands in the middle of a wide, shallow
-- SHELF; the low-level biomes sit on it (Kelp Shallows round the hub, the Shipwreck
-- Graveyard to the west, the Coral Reef as the shelf's outer band). The shelf ends
-- in a cliff, the DROP-OFF, and the high-level biomes lie on the deep floor far
-- below it: the Open Blue to the north, the Sunken Ruins to the east, the
-- Hydrothermal Vents to the south-west and the Abyssal Trench, a canyon cut into
-- the deep floor to the south. Shared/Seafloor.luau turns these numbers into a floor
-- height for any point; Shared/Layout.luau handles the hub; the server sculpts the
-- Terrain from them (Shelf.luau, Cave.luau).
return {
	seed = 20261006, -- world dressing and school placement (same on every machine)
	seabedY = 0, -- the shelf's sand level
	surfaceY = 440, -- the ceiling; boats will sit up here
	boundsRadius = 1500, -- an invisible wall rings the map here

	hub = {
		center = Vector3.new(0, 0, 0),
		radius = 95, -- inner face of the cavern wall
		height = 110, -- cavern ceiling
		wallThickness = 14,
		segments = 24, -- wall pieces round the ring: dens, tunnels and plain wall
		denDepth = 34, -- how far a den runs back into the wall
		denHeight = 26,
		denFloorY = 4,
		tunnelHeight = 36,
		tunnelLength = 44,
		oculusRadius = 28, -- the hole in the cavern roof (light comes down through it)
		poolRadius = 7, -- each den's Haul Pool: swim into it to bank
	},

	-- The shelf: shallow sand from the hub out to `radius`, then the drop-off, a
	-- cliff `edge` wide down to the deep floor
	shelf = {
		radius = 850,
		edge = 90,
	},
	deep = {
		floorY = -430, -- the deep floor beyond the drop-off
		ventsFloorY = -540, -- the Hydrothermal Vents' basins
		ventsAngles = { 125, 215 }, -- the basins' sector (degrees from +X toward +Z)
		ventsRadii = { 1000, 1440 },
	},

	-- The shallow dressing and placements (kelp, shells, forage, small schools) live
	-- in this ring on the shelf
	shallows = {
		inner = 150,
		outer = 830,
	},

	trench = {
		-- The Abyssal Trench: a canyon cut into the deep floor to the south. The
		-- center and size are its bounding box; the canyon itself winds
		-- (Seafloor.trenchAxis, Shelf.luau).
		center = Vector3.new(0, 0, 1210),
		size = Vector3.new(700, 0, 560),
		floorY = -920,
		angles = { 68, 112 }, -- the biome's sector (the canyon is narrower)
		radii = { 990, 1430 },
		width = 210, -- across, at the floor
		wobble = 3.5, -- degrees the canyon's line winds either side of its middle
		bends = 5.5, -- how many times it winds along its length
	},
}
