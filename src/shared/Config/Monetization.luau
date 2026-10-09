--!strict
-- Game passes and developer products (MonetizationService, GDD §9). The rule:
-- **sell growth and safety, never bite damage**, so PvP stays fair. Kelp Wraps are
-- never sold for Robux, and nothing here touches bite damage.
--
-- `id` is the asset id from Creator Hub (the experience → Monetization → Passes /
-- Developer Products). Anything with id 0 hasn't been created yet: a live game hides
-- it, Studio shows it greyed out so the layout can be checked. Prices are what to
-- set in Creator Hub (Robux); the Shop shows them.
export type Pass = {
	key: string,
	id: number,
	name: string,
	price: number,
	description: string,
}
export type Product = {
	key: string,
	id: number,
	name: string,
	price: number,
	description: string,
	shop: boolean?, -- false = not listed in the Shop (offered elsewhere, or an ad's reward)
	-- A paid random item under Roblox's rules: Robux for shells, which buy random
	-- rolls. Hidden from players whose policy restricts paid random items
	-- (PolicyService), and the roll odds are shown before buying.
	paidRandom: boolean?,
}

local passes: { Pass } = {
	{
		key = "DoubleMass",
		id = 2023286343,
		name = "×2 Mass",
		price = 399,
		description = "Everything you eat counts double toward your Haul. Grow twice as fast, forever.",
	},
	{
		key = "VIP",
		id = 2021282363,
		name = "VIP",
		price = 299,
		description = "A gold VIP tag over your fish and +10% coral from everything you earn.",
	},
	{
		key = "DenExpansion",
		id = 2022452343,
		name = "Den Expansion",
		price = 149,
		description = "Four more furniture spots in your den (two on the floor, two on the walls), at any den level.",
	},
	{
		key = "DeepGarden",
		id = 2022290332,
		name = "Deep Garden",
		price = 129,
		description = "Your den's Coral Garden grows 50% faster and holds 16 hours instead of 8.",
	},
}

local products: { Product } = {
	{
		key = "SecondChance",
		id = 3717380340,
		name = "Second Chance",
		price = 39,
		description = "Just eaten? Get back the Haul you lost. Otherwise it's a Second Chance "
			.. "charm that keeps your Haul the next time something eats you.",
	},
	{
		key = "ServerFrenzy",
		id = 3717380401,
		name = "Server Frenzy",
		price = 99,
		description = "×2 growth for everyone in the server for 15 minutes, and your name is announced. "
			.. "Buying again adds 15 minutes.",
	},
	-- Double Haul: offered on the bank screen, one per haul size (Roblox products have
	-- fixed prices). Not listed in the Shop.
	{
		key = "DoubleHaulSmall",
		id = 3717380436,
		name = "Double Haul",
		price = 19,
		description = "Doubles the Haul you just banked.",
		shop = false,
	},
	{
		key = "DoubleHaulBig",
		id = 3717380455,
		name = "Double Haul (Big)",
		price = 49,
		description = "Doubles the big Haul you just banked.",
		shop = false,
	},
	{
		key = "DoubleHaulHuge",
		id = 3717380479,
		name = "Double Haul (Huge)",
		price = 99,
		description = "Doubles the huge Haul you just banked.",
		shop = false,
	},
	{
		key = "ShellPouch",
		id = 3717380495,
		name = "Shell Pouch",
		price = 49,
		description = "100 Shells: two rolls for shades, parts and variants.",
		paidRandom = true,
	},
	{
		key = "ShellChest",
		id = 3717380526,
		name = "Shell Chest",
		price = 199,
		description = "600 Shells: twelve rolls, two of them free.",
		paidRandom = true,
	},
	{
		-- The rewarded video ad's reward (Roblox grants ad rewards as a developer
		-- product, and they can't be random): doubles a small Haul. Not in the Shop.
		key = "AdDoubleHaul",
		id = 3717380541,
		name = "Double Haul (ad)",
		price = 5,
		description = "Doubles the small Haul you just banked.",
		shop = false,
	},
}

local Monetization = {
	passes = passes,
	products = products,
	passesByKey = {} :: { [string]: Pass },
	productsByKey = {} :: { [string]: Product },

	tuning = {
		doubleMass = 2,
		vipCoral = 1.1,
		denExpansionSlots = { "X1", "X2", "X3", "X4" }, -- Config/Dens slots the pass opens
		deepGarden = { rate = 1.5, hours = 16 },
		-- Second Chance bought within this long of being eaten gives that Haul back
		-- (a receipt can land late); otherwise it's a charm. After the tutorial, the
		-- eaten screen offers it for a lost Haul of at least `minShare` of your banked
		-- mass, and the Shop sells it while you hold fewer than `maxCharms`.
		secondChance = { window = 180, minShare = 0.25, maxCharms = 5 },
		-- Server Frenzy: each purchase adds `minutes` of ×`multiplier` growth for the
		-- whole server, up to `maxMinutes` ahead.
		serverFrenzy = { minutes = 15, maxMinutes = 120, multiplier = 2 },
		shellPouch = 100,
		shellChest = 600,
		-- Double Haul on the bank screen (after the tutorial): offered when doubling
		-- would add at least `minLevels` (2 ≈ a Haul of 30% of your mass), priced
		-- by the Haul's size: up to `maxKg` per tier, the last tier takes the rest. A
		-- haul banked again before the receipt lands is doubled up to its tier's cap.
		-- The rewarded ad doubles Hauls up to `adMaxKg`.
		doubleHaul = {
			minLevels = 2,
			tiers = {
				{ key = "DoubleHaulSmall", maxKg = 60 },
				{ key = "DoubleHaulBig", maxKg = 2500 },
				{ key = "DoubleHaulHuge", maxKg = math.huge },
			},
			adMaxKg = 60,
		},
		-- Free perks
		premiumCoral = 1.1, -- Roblox Premium members (more Premium playtime → Premium Payouts)
		-- The Roblox group: `id` 0 until the group exists. Members earn `coral` more;
		-- joining pays `shells` once.
		group = { id = 0, coral = 1.05, shells = 100 },
	},
}

for _, pass in passes do
	Monetization.passesByKey[pass.key] = pass
end
for _, product in products do
	Monetization.productsByKey[product.key] = product
end

return Monetization
