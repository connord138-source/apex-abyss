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
-- Until the first shot is in (and whenever none is) a plain water backdrop shows
-- under the title (the old ViewportFrame scene is gone, owner 2026-10-20). Every cut
-- is held under the murk until the new spot has loaded round the camera: its parts
-- in (StartShots.partsNear against the server's count), the downloads queue nearly
-- empty, and `mesh` seconds for the Terrain to mesh, which Roblox does only round the
-- camera and can't report (cut straight in, the floor and kelp showed through for a
-- few seconds, owner 2026-10-20).
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
-- The camera's distance keeps the school's furthest fish 2.5 of its lengths (5 studs
-- at least) clear of the lens once it has pushed in, × `frame` (a lone fish: `lengths`
-- of it, 6 unless set), kept between `near` and `far`; `height` is the camera over the
-- school, a share of that distance (negative: below it, looking up); `push` the share
-- pushed in over the shot; `follow` how much the camera travels with the school (0: it
-- only pans, 1: it moves with it), raised so the school drifts no more than `drift`
-- (0.3 unless set) of the distance through the picture; `floor` the studs it keeps
-- over the ground. Shared/StartShots checks every moment of a shot: open water round
-- the camera, no fish of the school within that gap of the lens, and at least half of
-- the school in the picture between the letterbox bars.
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
	drift: number?,
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
		frame = 1.05,
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
		frame = 1.0,
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
		-- Triggerfish passing a wreck: the camera behind them, the hull beyond (beside
		-- them, keeping pace, when no wreck is near)
		id = "wreck",
		biome = "ShipwreckGraveyard",
		prey = { "Triggerfish", "WreckCod", "Lingcod" },
		radii = { 520, 800 },
		style = "track",
		frame = 1.1,
		near = 10,
		far = 40,
		height = 0.18,
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
		frame = 0.9,
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
		frame = 1.15,
		near = 14,
		far = 46,
		height = 0.12,
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
		frame = 1.1,
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
		frame = 1.0,
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
		dipHold = 0.18, -- the cut back onto the backdrop, in the murk
		mesh = 2.6, -- the least a cut is held, the camera at the new spot (Terrain meshes round it)
		holdMax = 6, -- the most: it clears then whatever is still loading
		parts = 0.9, -- share of the server's parts round the school that must be in
		queue = 10, -- downloads still waiting (ContentProvider.RequestQueueSize) at most
		dipIn = 0.6, -- out of it into the new shot
		reveal = 1.2, -- the backdrop clearing onto the first shot
		diveIn = 0.45, -- the dive: the wash closing over the shot
		diveHold = 0.9, -- held over the den while its Terrain meshes in round the camera
		diveOut = 0.7,
		letterbox = 0.085, -- the bars' height, a share of the screen's
	},
}
