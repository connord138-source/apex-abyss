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

export type Charm = {
	id: string,
	vendor: string,
	name: string,
	blurb: string,
	price: number,
	max: number?, -- most you can hold (stocked charms)
	seconds: number?, -- timed charms: how long it lasts
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
}

local upgrades: { Upgrade } = {
	{
		id = "Fins",
		vendor = "Outfitter",
		name = "Strong Fins",
		blurb = "+4% top speed per level",
		per = 0.04,
		costs = { 200, 600, 1500, 3500, 8000 },
	},
	{
		id = "Gills",
		vendor = "Outfitter",
		name = "Deep Gills",
		blurb = "Dash recharges 12% faster per level",
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
		id = "Magnet",
		vendor = "Charms",
		name = "Shell Magnet",
		blurb = "×2 shell pickup reach for 10 minutes",
		price = 250,
		seconds = 600,
	},
	{
		id = "Feast",
		vendor = "Charms",
		name = "Feast Charm",
		blurb = "+25% Haul from everything you eat for 10 minutes",
		price = 400,
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
	-- The Tidecharm Trader also sells shells, a few times a day
	shellTrade = { vendor = "Charms", shells = 10, price = 400, perDay = 5 },
	-- How close you must be to a stall to buy from it (studs)
	reach = 30,
	-- How close the "E · Shop" hint shows (studs from the counter's box, so it works
	-- from the ends and the back too)
	hintReach = 15,
}
