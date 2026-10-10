--!strict
-- The Treasure Wheel (owner, 2026-10-10: "do want a spin wheel again"; ported from
-- Hatch & Snatch's Luck Wheel: WheelService, TreasureWheel.luau,
-- TreasureWheelController). A game-show wheel on the hub plaza: swim up to its big
-- red button and spend a spin. Everyone in the hub sees it turn; a second spinner
-- joins the line, and Spin all keeps you in it until your spins run out.
--
-- Spins come back on their own (one every `freeEvery`, online or off, up to
-- `maxFree` waiting: a reason to come back), and from the Bounty Chest, the Catch of
-- the Week and daily streak days 3 and 6. They're never sold. The jackpot rolls a
-- Rare-or-better skin from the line of the fish you swim as (the elite skins stay
-- RNG, owner).
export type Segment = {
	label: string, -- the odds board and the result banner
	kind: string, -- coral · shells · wraps · charm · spins · map · skin
	value: number, -- coral, shells, wraps or spins
	weight: number, -- its share of the wheel's odds (they add up to 100)
	color: Color3,
	big: string, -- on the slice, near the rim (5 letters at most reads best)
	sub: string, -- on the slice, under it (8 at most: the slice narrows inward)
	charm: string?, -- kind "charm": the Config/Shop charm
	map: string?, -- kind "map": the Config/Treasure tier
	minTier: string?, -- kind "skin": the rarest-or-better tier rolled
}

-- Round the wheel clockwise from the top; alternating light and dark so the slices
-- read apart
local segments: { Segment } = {
	{
		label = "300 CORAL",
		kind = "coral",
		value = 300,
		weight = 24,
		color = Color3.fromRGB(255, 132, 96),
		big = "300",
		sub = "CORAL",
	},
	{
		label = "TREASURE MAP",
		kind = "map",
		value = 1,
		weight = 10,
		color = Color3.fromRGB(40, 110, 200),
		big = "MAP",
		sub = "TREASURE",
		map = "Weathered",
	},
	{
		label = "40 SHELLS",
		kind = "shells",
		value = 40,
		weight = 18,
		color = Color3.fromRGB(230, 200, 120),
		big = "40",
		sub = "SHELLS",
	},
	{
		label = "FEAST CHARM",
		kind = "charm",
		value = 1,
		weight = 12,
		color = Color3.fromRGB(214, 90, 40),
		big = "FEAST",
		sub = "CHARM",
		charm = "Feast",
	},
	{
		label = "+2 SPINS",
		kind = "spins",
		value = 2,
		weight = 10,
		color = Color3.fromRGB(150, 100, 240),
		big = "+2",
		sub = "SPINS",
	},
	{
		label = "2 KELP WRAPS",
		kind = "wraps",
		value = 2,
		weight = 12,
		color = Color3.fromRGB(60, 190, 110),
		big = "KELP",
		sub = "2 WRAPS",
	},
	{
		label = "LUCKY CHARM",
		kind = "charm",
		value = 1,
		weight = 10,
		color = Color3.fromRGB(20, 140, 130),
		big = "LUCKY",
		sub = "CHARM",
		charm = "Lucky",
	},
	{
		label = "JACKPOT · SKIN",
		kind = "skin",
		value = 1,
		weight = 4,
		color = Color3.fromRGB(255, 210, 60),
		big = "SKIN",
		sub = "JACKPOT",
		minTier = "Rare",
	},
}

return {
	segments = segments,
	freeEvery = 4 * 3600, -- seconds: a free spin, online or off
	maxFree = 3, -- free spins stop coming once this many wait
	startSpins = 1, -- a new player's first spin
	reach = 16, -- studs from the big red button to spin
	jackpotCoral = 2500, -- the jackpot when the fish has every Rare+ skin already
	bountyChest = 1, -- spins in the Bounty Chest
	weekly = 2, -- spins for the Catch of the Week
	angle = 240, -- where it stands on the plaza (degrees from +X toward +Z) ...
	radius = 62, -- ... and how far out from the beacon, facing it
}
