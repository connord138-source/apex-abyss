--!strict
-- Everything Coral buys, by vendor. The vendors' stalls stand round the hub plaza
-- (WorldService builds them at `angle` degrees round the beacon).
export type Vendor = {
	id: string,
	name: string,
	keeper: string,
	blurb: string,
	angle: number,
	color: Color3, -- the stall's awning
}

export type Upgrade = {
	id: string,
	vendor: string,
	name: string,
	blurb: string,
	per: number, -- effect per level (meaning depends on the upgrade)
	costs: { number }, -- coral for each level, in order
}

-- A world boss trophy (GDD §8): bought with that boss's Teeth or Beaks (data.trophies)
export type Trophy = {
	id: string,
	vendor: string,
	name: string,
	blurb: string,
	kind: "shade", -- more kinds (den pieces, body parts) when their systems exist
	shade: string?, -- Config/Shades id
	currency: string, -- data.trophies key
	currencyName: string,
	price: number,
	boss: string, -- Config/Bosses id, for the row's color
}

export type Charm = {
	id: string,
	vendor: string,
	name: string,
	blurb: string,
	price: number,
	max: number?, -- most you can hold
	seconds: number?, -- timed charms: how long it lasts once used from the item wheel
}

local vendors: { Vendor } = {
	{
		id = "Outfitter",
		name = "Fin & Gill Outfitter",
		keeper = "Old Hermit",
		blurb = "Permanent upgrades for every dive.",
		angle = 45,
		color = Color3.fromRGB(80, 170, 220),
	},
	{
		id = "Mason",
		name = "Den Mason",
		keeper = "Octavio",
		blurb = "Make your den bank more from every Haul.",
		angle = 135,
		color = Color3.fromRGB(230, 130, 70),
	},
	{
		id = "Charms",
		name = "Tidecharm Trader",
		keeper = "Old Tortuga",
		blurb = "Charms, and shells for coral.",
		angle = 225,
		color = Color3.fromRGB(110, 200, 140),
	},
	{
		id = "Dyer",
		name = "Shade Dyer",
		keeper = "Puff",
		blurb = "Fresh colors for your fish.",
		angle = 315,
		color = Color3.fromRGB(200, 120, 220),
	},
	{
		id = "Trophies",
		name = "Trophy Hunter",
		keeper = "Scar",
		blurb = "Boss trophies, for Teeth and Beaks.",
		angle = 90,
		color = Color3.fromRGB(196, 255, 170),
	},
}

local trophies: { Trophy } = {
	{
		id = "GhostShade",
		vendor = "Trophies",
		name = "Ghost Shade",
		blurb = "Spectral green with mist rolling off it, like the drowned",
		kind = "shade",
		shade = "Ghost",
		currency = "MegalodonTeeth",
		currencyName = "Megalodon Teeth",
		price = 12,
		boss = "Megalodon",
	},
	{
		id = "AbyssInkShade",
		vendor = "Trophies",
		name = "Abyss Ink Shade",
		blurb = "Ink-black with glowing spots",
		kind = "shade",
		shade = "AbyssInk",
		currency = "KrakenBeaks",
		currencyName = "Kraken Beaks",
		price = 12,
		boss = "GiantSquid",
	},
}

local upgrades: { Upgrade } = {
	{
		id = "Fins",
		vendor = "Outfitter",
		name = "Strong Fins",
		blurb = "+3% top speed per level",
		per = 0.03, -- (was 0.04: a maxed LV 100 'Cuda chaining Torpedo crossed the map in 31 s; 33 s now)
		costs = { 200, 600, 1500, 3500, 8000 },
	},
	{
		-- Every fish's own ability (owner, 2026-10-21: "sells dash for all of them when
		-- not all fish can dash. That vendor needs to be relative to all fish"): the
		-- Nibbler's Dash, the 'Cuda's Torpedo, the Puffer's Puff Up, the Moray's Burrow,
		-- the Reef Shark's Blood Sense and the Angler's Lantern Flash all recharge
		-- faster (Perks.boost). `{ability}` in the blurb is the current fish's
		-- (MenuController). The id is the one saves hold: it sold "Deep Gills", a
		-- faster Dash only, until then.
		id = "Gills",
		vendor = "Outfitter",
		name = "Quick Recovery",
		blurb = "{ability} recharges 12% faster per level",
		per = 0.12,
		costs = { 250, 700, 1800, 4000, 9000 },
	},
	{
		id = "Senses",
		vendor = "Outfitter",
		name = "Shell Sense",
		blurb = "+20% shell pickup reach per level",
		per = 0.2,
		costs = { 150, 450, 1200, 3000, 7000 },
	},
	{
		id = "Jaw",
		vendor = "Outfitter",
		name = "Iron Jaw",
		blurb = "+6% bite damage per level",
		per = 0.06,
		costs = { 300, 900, 2200, 5000, 11000 },
	},
	{
		id = "Hide",
		vendor = "Outfitter",
		name = "Pressure Hide",
		blurb = "Dive as if 4 levels higher per level (depth pressure)",
		per = 4,
		costs = { 400, 1200, 3000, 7000, 15000 },
	},
	{
		id = "Chamber",
		vendor = "Mason",
		name = "Haul Chamber",
		blurb = "+6% to every Haul you bank, per level",
		per = 0.06,
		costs = { 300, 900, 2500, 6000, 15000 },
	},
}

local charms: { Charm } = {
	{
		id = "Lucky",
		vendor = "Charms",
		name = "Lucky Charm",
		blurb = "Your next roll has ×2 luck on everything but coral",
		price = 800,
		max = 3,
	},
	{
		id = "SecondChance",
		vendor = "Charms",
		name = "Second Chance",
		blurb = "Keep your Haul the next time you're eaten",
		price = 1200,
		max = 1,
	},
	{
		id = "KelpWrap",
		vendor = "Charms",
		name = "Kelp Wrap",
		blurb = "Heals 40% over 4 s. Use it from your item wheel (G) or H. You swim slower while it works",
		price = 120,
		max = 5,
	},
	{
		id = "DeepLantern",
		vendor = "Charms",
		name = "Deep Lantern",
		blurb = "A small light for the dark Trench, 10 minutes from when you use it (item wheel, G)",
		price = 350,
		max = 3,
		seconds = 600,
	},
	{
		id = "Magnet",
		vendor = "Charms",
		name = "Shell Magnet",
		blurb = "×2 shell pickup reach for 10 minutes from when you use it (item wheel, G)",
		price = 250,
		max = 3,
		seconds = 600,
	},
	{
		id = "Feast",
		vendor = "Charms",
		name = "Feast Charm",
		blurb = "+25% Haul from everything you eat for 10 minutes from when you use it (item wheel, G)",
		price = 400,
		max = 3,
		seconds = 600,
	},
}

local function index<T>(list: { T }): { [string]: T }
	local byId: { [string]: T } = {}
	for _, item in list do
		byId[(item :: any).id] = item
	end
	return byId
end

return {
	vendors = vendors,
	vendorsById = index(vendors),
	upgrades = upgrades,
	upgradesById = index(upgrades),
	charms = charms,
	charmsById = index(charms),
	-- The item wheel's slots, clockwise from the top (owner, 2026-10-11: consumables
	-- are carried and used when wanted, "not immediately"): a Kelp Wrap heals, the
	-- others start their timer when used
	items = { "KelpWrap", "Feast", "Magnet", "DeepLantern" },
	trophies = trophies,
	trophiesById = index(trophies),
	-- The Tidecharm Trader also sells shells, a few times a day
	shellTrade = { vendor = "Charms", shells = 10, price = 400, perDay = 5 },
	-- How close you must be to a stall to buy from it (studs)
	reach = 30,
	-- How close the "E · Shop" hint shows (studs from the counter's box, so it works
	-- from the ends and the back too)
	hintReach = 15,
}
