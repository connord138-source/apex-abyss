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
}

local byId: { [string]: ForageDef } = {}
for _, def in list do
	byId[def.id] = def
end

return {
	list = list,
	byId = byId,
	HOP = 1.6, -- studs a shrimp can be from its spot (the server allows for it)
}
