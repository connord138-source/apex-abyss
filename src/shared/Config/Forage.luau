--!strict
-- Filler food on the seabed (owner, 2026-10-06: "small filler food for low lvl xp
-- such as starfish or shrimp"): tiny, everywhere, never fights back. Spots are
-- placed at server start on whatever's under them (ForageService); the food is
-- shared, and an eaten one comes back after `respawn` seconds.
export type ForageDef = {
	id: string,
	name: string,
	mass: number, -- kg of Haul
	spots: number,
	respawn: number,
	color: Color3,
	accent: Color3,
	hops: boolean, -- shrimp hop about a little; starfish stay put
	wrap: boolean?, -- medkelp: gives a Kelp Wrap (Config/Tuning heal) instead of mass
}

local list: { ForageDef } = {
	{
		id = "Shrimp",
		name = "Shrimp",
		mass = 0.04,
		spots = 220,
		respawn = 20,
		color = Color3.fromRGB(240, 140, 96),
		accent = Color3.fromRGB(255, 196, 150),
		hops = true,
	},
	{
		id = "Starfish",
		name = "Starfish",
		mass = 0.07,
		spots = 140,
		respawn = 30,
		color = Color3.fromRGB(236, 120, 60),
		accent = Color3.fromRGB(255, 186, 110),
		hops = false,
	},
	{
		id = "Medkelp",
		name = "Medkelp",
		mass = 0,
		spots = 60,
		respawn = 120,
		color = Color3.fromRGB(96, 200, 120),
		accent = Color3.fromRGB(170, 255, 190),
		hops = false,
		wrap = true,
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
	-- Eat reach for filler food: × the fish's normal reach, plus studs. Single shrimp
	-- and starfish were too fiddly for a new fish (re-test 2026-10-06).
	REACH_SCALE = 1.6,
	REACH_BONUS = 1.2,
	-- Suction: food within PULL × that reach drifts toward the mouth, up to
	-- PULL_SHARE of the way at the lips (so it's eaten from about 1.3 × reach)
	PULL = 2.4,
	PULL_SHARE = 0.55,
}
