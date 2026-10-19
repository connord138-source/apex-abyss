--!strict
-- Filler food on the seabed (owner, 2026-10-06: "small filler food for low lvl xp
-- such as starfish or shrimp"): tiny, everywhere, never fights back. Spots are
-- placed at server start on whatever's under them (ForageService); the food is
-- shared, and an eaten one comes back after `respawn` seconds.
--
-- Thickest near the hub, where new fish start (owner, 2026-10-10: "needs a lot more
-- smaller fish and starter food laying around. far too scarce": 360 spots spread
-- over the whole shelf were one every ~75 studs; now about one every 20 near the hub).
--
-- Crabs (owner, 2026-10-19: "Crabs were another animal that needs more detail like the
-- turtles. Crabs should be edible too"): a kind of crab per floor, each in its own
-- biome, mostly beside the rocks, coral, wrecks, ruins and chimneys there (ForageService)
-- and always on open floor. Each scuttles sideways about its spot on the shared clock
-- (Shared/Crabs), so the server checks an eat against its spot plus `scuttle`. Unlike
-- the shrimp and starfish a crab has a size: only a fish that can swallow something
-- `size` studs long eats it (Size.canSwallow, like prey). Drawn from the imported
-- `AmbientModels.Crab` (tinted or painted per kind) or a part-built crab
-- (Shared/AmbientRigs), near the camera only (ForageController).
-- A band is a ring of studs from the hub (`from`, `to`), or a biome's own sector
-- (`biome`, Config/Biomes; `from`/`to` then narrow its rings)
export type Band = { from: number?, to: number?, count: number, biome: string? }
export type CrabLook = {
	tint: Color3?, -- × the imported crab's own scarlet (SurfaceAppearance.Color); nil: as it is
	paint: Color3?, -- a solid colour instead, its texture held aside (a crab that isn't red)
	look: { [string]: Color3 }, -- the part-built crab's colours by role (Shared/AmbientRigs)
	extras: string?, -- what it carries (AmbientRigs.extras): "sponge", "barnacles", "fuzz", "spikes"
	range: number, -- studs from the camera it's drawn within
	animate: number, -- its legs move within this (its body still scuttles past it)
	near: number, -- the share of its spots beside rock (the rest out on the open floor)
}
export type ForageDef = {
	id: string,
	name: string,
	mass: number, -- kg of Haul
	bands: { Band },
	respawn: number,
	color: Color3,
	accent: Color3,
	hops: boolean, -- shrimp hop about a little; starfish stay put
	wrap: boolean?, -- medkelp: gives a Kelp Wrap (Config/Tuning heal) instead of mass
	crab: CrabLook?, -- a crab (below)
	size: number?, -- a crab's width across its legs, studs: what's measured to swallow it
	scuttle: number?, -- studs a crab wanders from its spot
	speed: number?, -- a crab's dash, studs/s
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- A blend of two colours (plain arithmetic, so the luau CLI's shims can load this file)
local function mix(a: Color3, b: Color3, k: number): Color3
	return Color3.new(a.R + (b.R - a.R) * k, a.G + (b.G - a.G) * k, a.B + (b.B - a.B) * k)
end

-- A part-built crab's colours: shell, its facets, claws, underside (Shared/AmbientRigs roles)
local function shell(top: Color3, claw: Color3?, belly: Color3?): { [string]: Color3 }
	local black, white = Color3.new(0, 0, 0), Color3.new(1, 1, 1)
	return {
		top = top,
		top2 = mix(top, black, 0.18),
		claw = claw or mix(top, white, 0.06),
		belly = belly or rgb(150, 156, 166),
		dark = rgb(34, 34, 40),
		eye = rgb(12, 12, 14),
		extra = rgb(232, 196, 40),
		extra2 = rgb(126, 74, 184),
		extra3 = rgb(64, 150, 92),
		barnacle = rgb(134, 140, 146),
		bristle = rgb(110, 176, 168),
		spike = mix(top, black, 0.4),
	}
end

local list: { ForageDef } = {
	{
		id = "Shrimp",
		name = "Shrimp",
		mass = 0.04,
		bands = {
			{ from = 140, to = 330, count = 440 },
			{ from = 330, to = 520, count = 320 },
			{ from = 520, to = 830, count = 260 },
		},
		respawn = 20,
		color = Color3.fromRGB(240, 140, 96),
		accent = Color3.fromRGB(255, 196, 150),
		hops = true,
	},
	{
		id = "Starfish",
		name = "Starfish",
		mass = 0.07,
		bands = {
			{ from = 140, to = 330, count = 240 },
			{ from = 330, to = 520, count = 180 },
			{ from = 520, to = 830, count = 160 },
		},
		respawn = 30,
		color = Color3.fromRGB(236, 120, 60),
		accent = Color3.fromRGB(255, 186, 110),
		hops = false,
	},
	{
		id = "Medkelp",
		name = "Medkelp",
		mass = 0,
		bands = { { from = 140, to = 830, count = 80 } },
		respawn = 120,
		color = Color3.fromRGB(96, 200, 120),
		accent = Color3.fromRGB(170, 255, 190),
		hops = false,
		wrap = true,
	},
	-- The crabs, a kind a floor (after the others: their placement draws on the same
	-- random sequence, so the shrimp, starfish and medkelp keep their spots)
	{
		id = "ShoreCrab",
		name = "Shore Crab",
		mass = 0.1,
		bands = { { biome = "KelpShallows", from = 215, to = 480, count = 130 } },
		respawn = 30,
		color = rgb(200, 48, 44),
		accent = rgb(230, 90, 60),
		hops = false,
		size = 1, -- (a brand-new fish swallows it)
		scuttle = 3,
		speed = 3.2,
		crab = { look = shell(rgb(200, 48, 44)), range = 90, animate = 36, near = 0.6 },
	},
	{
		id = "RockCrab",
		name = "Rock Crab",
		mass = 0.7,
		bands = { { biome = "ShipwreckGraveyard", count = 110 } },
		respawn = 40,
		color = rgb(150, 40, 32),
		accent = rgb(190, 70, 50),
		hops = false,
		size = 1.8, -- (swallowed from LV 8)
		scuttle = 4,
		speed = 3,
		crab = {
			tint = rgb(190, 150, 135),
			look = shell(rgb(150, 40, 32)),
			range = 120,
			animate = 44,
			near = 0.8,
		},
	},
	{
		id = "DecoratorCrab",
		name = "Decorator Crab",
		mass = 1.5,
		bands = { { biome = "CoralReef", count = 170 } },
		respawn = 40,
		color = rgb(204, 60, 44),
		accent = rgb(232, 196, 40),
		hops = false,
		size = 2.4, -- (swallowed from LV 16; a sponge garden on its back)
		scuttle = 4,
		speed = 2.6,
		crab = { extras = "sponge", look = shell(rgb(204, 60, 44)), range = 130, animate = 48, near = 0.8 },
	},
	{
		id = "StoneCrab",
		name = "Stone Crab",
		mass = 8,
		bands = { { biome = "SunkenRuins", count = 110 } },
		respawn = 50,
		color = rgb(118, 30, 28),
		accent = rgb(60, 60, 66),
		hops = false,
		size = 4.4, -- (swallowed from LV 34; barnacles on its shell)
		scuttle = 5,
		speed = 2.6,
		crab = {
			tint = rgb(150, 120, 120),
			extras = "barnacles",
			look = shell(rgb(118, 30, 28), rgb(110, 34, 30)),
			range = 170,
			animate = 60,
			near = 0.85,
		},
	},
	{
		id = "YetiCrab",
		name = "Yeti Crab",
		mass = 5,
		bands = { { biome = "HydrothermalVents", count = 110 } },
		respawn = 50,
		color = rgb(122, 136, 146),
		accent = rgb(110, 176, 168),
		hops = false,
		size = 3.4, -- (swallowed from LV 27; mid grey with teal bristles, never white)
		scuttle = 5,
		speed = 2.4,
		crab = {
			paint = rgb(122, 136, 146),
			extras = "fuzz",
			look = shell(rgb(122, 136, 146), rgb(132, 146, 154), rgb(104, 114, 124)),
			range = 160,
			animate = 60,
			near = 0.9,
		},
	},
	{
		id = "KingCrab",
		name = "King Crab",
		mass = 12,
		bands = { { biome = "AbyssalTrench", count = 30 } },
		respawn = 120,
		color = rgb(184, 40, 34),
		accent = rgb(120, 24, 22),
		hops = false,
		size = 9, -- (a big one: swallowed from LV 57, so only by the bigger fish)
		scuttle = 8,
		speed = 2.2,
		crab = {
			tint = rgb(220, 160, 150),
			extras = "spikes",
			look = shell(rgb(184, 40, 34)),
			range = 260,
			animate = 100,
			near = 0.7,
		},
	},
}

local byId: { [string]: ForageDef } = {}
for _, def in list do
	byId[def.id] = def
end

return {
	list = list,
	byId = byId,
	HOP = 1.6, -- studs a shrimp can be from its spot (the server allows for it)
	-- A crab is in reach of a mouth this share of its size out from its middle (its
	-- legs; ForageController and ForageService allow the same)
	CRAB_RADIUS = 0.35,
	-- ...and its middle stands this share of its size over the floor (the model's and
	-- the part-built crab's feet are 0.27 of their width under their middles)
	CRAB_HEIGHT = 0.27,
	-- Eat reach for filler food: × the fish's normal reach, plus studs. Single shrimp
	-- and starfish were too fiddly for a new fish (re-test 2026-10-06).
	REACH_SCALE = 1.6,
	REACH_BONUS = 1.2,
	-- Suction: food within PULL × that reach drifts toward the mouth, up to
	-- PULL_SHARE of the way at the lips (so it's eaten from about 1.3 × reach)
	PULL = 2.4,
	PULL_SHARE = 0.55,
}
