--!strict
-- The graybox map's layout. Shared/Layout.luau turns these into positions, and the
-- server builds the world from them (WorldService).
return {
	seed = 20261006, -- world dressing and school placement (same on every machine)
	seabedY = 0,
	surfaceY = 300, -- the ceiling; boats will sit up here
	boundsRadius = 720, -- an invisible wall rings the map here

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

	shallows = {
		inner = 150, -- the Kelp Shallows ring around the hub
		outer = 640,
	},

	trench = {
		-- A drop-off south of the hub, to feel depth before the deep biomes exist
		center = Vector3.new(0, 0, 470),
		size = Vector3.new(300, 0, 240),
		floorY = -420,
	},
}
