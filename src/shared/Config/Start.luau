--!strict
-- The start screen's attract mode (owner, 2026-10-19: "The start screen could be dialed
-- up as well. It could be rolling shots of different fish around the different biomes
-- or just have the actual visual quality turned up"): while the game loads and waits
-- for a key, the real sea plays like a nature documentary. Each shot follows a real
-- prey school (Shared/Schools: the same fish a player would meet there, on the shared
-- clock) in its biome, a lower third names the fish and the place, and the shots cut
-- through a dip into murk or a quick bubble wash. StartController plays them;
-- Shared/StartShots works out each camera from the school's own path and the world's
-- config; the server streams each shot's water in ahead of its cut (StartService).
-- The old ViewportFrame scene is the loading layer: it shows until the first shot is
-- in, and again whenever none is.
--
-- A shot frames one school of its `prey` (the first in the list with a school in the
-- shot's place: its biome's sector and radii, narrowed by `radii` and `angles`).
-- Its camera, in `style`:
--   track  keeps pace beside the school (with a landmark: behind the school, the
--          landmark beyond it)
--   lead   hangs ahead and to one side; the school swims at it
--   glide  slides past the school from behind, overtaking it
--   orbit  a slow arc round the school (`sweep` radians)
--   rise   from beside and below, rising toward the light (`height` to `rise`)
-- `frame` × the school's width (its spread both ways plus a fish), or `lengths` of its
-- fish if that's nearer (7 unless set), is the camera's distance, kept between `near`
-- and `far` and never inside the school's spread; `height` is the camera over the school, a
-- share of that distance (negative: below it, looking up); `push` the share pushed in
-- over the shot; `follow` how much the camera travels with the school (0: it only
-- pans, 1: it moves with it); `floor` the studs it keeps over the ground.
-- `landmark` turns the shot so something stands behind the school:
--   temple  the Sunken Ruins' great temple (Config/Ruins), schools within `within`
--   basin   the middle of the Vents' basin the school swims in (its chimneys)
--   canyon  the Trench's canyon further along its line (its walls either side)
--   wreck   the nearest wreck's hull (found once the area is in, so the client only)
export type Style = "track" | "lead" | "glide" | "orbit" | "rise"
export type Landmark = "temple" | "basin" | "canyon" | "wreck"

export type Shot = {
	id: string,
	biome: string, -- Config/Biomes id: where its school swims, and the lower third's place
	prey: { string }, -- the featured fish, most wanted first (Config/Prey ids)
	radii: { number }?, -- studs from the hub, inside the biome's own
	angles: { number }?, -- degrees round the hub (from +X toward +Z), inside the biome's own
	style: Style,
	frame: number?,
	lengths: number?,
	near: number?,
	far: number?,
	height: number?,
	rise: number?,
	push: number?,
	follow: number?,
	sweep: number?,
	fov: number?,
	floor: number?,
	landmark: Landmark?,
	within: number?, -- (temple) studs from the landmark its school must be
	cut: ("murk" | "bubbles")?, -- how the cut into this shot looks
}

local shots: { Shot } = {
	{
		-- A low dolly through the kelp stalks, a Garibaldi school passing in the light
		id = "kelp",
		biome = "KelpShallows",
		prey = { "Garibaldi", "Opaleye", "KelpBass" },
		radii = { 230, 450 },
		style = "glide",
		frame = 1.25,
		near = 8,
		far = 30,
		height = -0.12,
		push = 0.1,
		follow = 0.55,
		fov = 58,
		floor = 4,
		cut = "bubbles",
	},
	{
		-- A slow track low over the coral beside a Parrotfish school
		id = "reef",
		biome = "CoralReef",
		prey = { "Parrotfish", "BlueTang", "Butterflyfish" },
		radii = { 530, 790 },
		style = "track",
		frame = 1.15,
		near = 10,
		far = 40,
		height = 0.3,
		push = 0.12,
		follow = 0.7,
		fov = 55,
		floor = 12, -- (the corals are parts the rays can't see, up to ~12 studs tall)
		cut = "murk",
	},
	{
		-- Triggerfish swimming at the camera, a wreck's hull behind them
		id = "wreck",
		biome = "ShipwreckGraveyard",
		prey = { "Triggerfish", "WreckCod", "Lingcod" },
		radii = { 520, 800 },
		style = "lead",
		frame = 1.2,
		near = 10,
		far = 40,
		height = 0.28,
		push = 0.15,
		follow = 0.75,
		fov = 55,
		floor = 7,
		landmark = "wreck",
		cut = "murk",
	},
	{
		-- A Yellowfin Tuna school coming at the camera out of the clear deep blue, seen
		-- from a little below against the light
		id = "openblue",
		biome = "OpenBlue",
		prey = { "YellowfinTuna", "MahiMahi", "Swordfish" },
		radii = { 990, 1280 },
		style = "lead",
		frame = 0.85,
		lengths = 5.5,
		near = 26,
		far = 70,
		height = -0.22,
		push = 0.14,
		follow = 0.85,
		fov = 60,
		floor = 20,
		cut = "bubbles",
	},
	{
		-- Past a Humphead Wrasse or Lionfish toward the great temple
		id = "ruins",
		biome = "SunkenRuins",
		prey = { "HumpheadWrasse", "Lionfish", "Coelacanth" },
		style = "track",
		frame = 1.4,
		near = 14,
		far = 46,
		height = 0.32,
		push = 0.12,
		follow = 0.7,
		fov = 58,
		floor = 8,
		landmark = "temple",
		within = 330,
		cut = "murk",
	},
	{
		-- A slow arc round Vent Eelpouts nosing over a basin, the chimneys glowing beyond
		id = "vents",
		biome = "HydrothermalVents",
		prey = { "VentEelpout", "Rattail", "GhostShrimp" },
		style = "orbit",
		frame = 1.3,
		near = 10,
		far = 40,
		height = 0.3,
		push = 0.08,
		follow = 0.8,
		sweep = 0.7,
		fov = 56,
		floor = 7,
		landmark = "basin",
		cut = "murk",
	},
	{
		-- Lanternfish glowing in the Trench's creepy teal, the canyon running on beyond
		id = "trench",
		biome = "AbyssalTrench",
		prey = { "Lanternfish", "Viperfish", "Hatchetfish", "Oarfish" },
		style = "orbit",
		frame = 1.1,
		near = 10,
		far = 44,
		height = 0.12,
		push = 0.1,
		follow = 0.8,
		sweep = 0.6,
		fov = 58,
		floor = 10,
		landmark = "canyon",
		cut = "murk",
	},
	{
		-- A huge Ocean Sunfish drifting high in the Open Blue, the camera rising to it
		id = "sunfish",
		biome = "OpenBlue",
		prey = { "OceanSunfish", "Swordfish", "MahiMahi" },
		radii = { 990, 1280 },
		style = "rise",
		frame = 1,
		lengths = 5,
		near = 20,
		far = 50,
		height = -0.55,
		rise = -0.12,
		push = 0.1,
		follow = 0.9,
		fov = 56,
		floor = 20,
		cut = "bubbles",
	},
}

local byId: { [string]: number } = {}
for index, shot in shots do
	byId[shot.id] = index
end

return {
	shots = shots,
	byId = byId,
	-- The first shot is one of these (bright, quick to stream in), then the rest in a
	-- shuffled order, never the same biome twice running
	first = { "kelp", "reef", "openblue" },
	timing = {
		seconds = 6.5, -- a shot's length
		extend = 4, -- how much longer a shot may run while the next one streams in
		settle = 1.6, -- an area must be in this long before it's cut to (Terrain meshes after it arrives)
		firstSettle = 2.2,
		arrive = 12, -- seconds to wait for an area to stream in before trying another shot
		window = 1.2, -- seconds either side the school's path is averaged over (a calm subject)
		dipOut = 0.35, -- into the murk
		dipHold = 0.18, -- the cut, in the murk
		dipIn = 0.6, -- out of it into the new shot
		reveal = 1.2, -- the loading scene clearing onto the first shot
		diveIn = 0.45, -- the dive: the wash closing over the shot
		diveHold = 0.9, -- held over the den while its Terrain meshes in round the camera
		diveOut = 0.7,
		letterbox = 0.085, -- the bars' height, a share of the screen's
	},
}
