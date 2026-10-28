--!strict
-- Rolls: every 50 Shells is one roll. About half pay Coral (the currency), about a
-- third a small prize (`prizes`: shells, DNA, a charm, a treasure map), the rest a
-- shade (Config/Shades); very rarely a body part or an exotic variant
-- (Config/Exotics). Shared/RollOdds.luau turns these into exact odds, and the
-- server and the odds panel both use it, so they can't disagree.
return {
	shellsPerRoll = 50,
	-- Coral takes whatever chance the shades and exotics leave, split by `share`
	coral = {
		{ id = "CoralHandful", name = "Handful of Coral", amount = 25, share = 0.7 },
		{ id = "CoralPouch", name = "Coral Pouch", amount = 60, share = 0.22 },
		{ id = "CoralChest", name = "Coral Chest", amount = 150, share = 0.065 },
		{ id = "CoralJackpot", name = "Coral Jackpot", amount = 600, share = 0.015 },
	},
	-- Small prizes besides coral (owner, 2026-10-28: "need more variety in roll
	-- rewards too. a bit too much coral rolls"), each at a fixed "1 in N" taken out of
	-- coral's share (luck doesn't touch them, as it doesn't coral): shells back, DNA for
	-- the rolling fish's home biome, a charm, a treasure map. A charm you already carry
	-- the most of, or a map with the satchel full, pays `refund` coral instead. A fresh
	-- fish's roll is ~46% coral now (was ~82%).
	prizes = {
		{
			id = "ShellPurse",
			kind = "shells",
			name = "Shell Purse",
			tier = "Common",
			chance = 8,
			amount = 30,
		},
		{ id = "DnaBundle", kind = "dna", name = "DNA Bundle", tier = "Common", chance = 12, amount = 8 },
		{
			id = "LuckyCharmPrize",
			kind = "charm",
			charm = "Lucky",
			name = "Lucky Charm",
			tier = "Uncommon",
			chance = 20,
			refund = 300,
		},
		{
			id = "FeastCharmPrize",
			kind = "charm",
			charm = "Feast",
			name = "Feast Charm",
			tier = "Uncommon",
			chance = 40,
			refund = 200,
		},
		{
			id = "MagnetPrize",
			kind = "charm",
			charm = "Magnet",
			name = "Shell Magnet",
			tier = "Uncommon",
			chance = 40,
			refund = 120,
		},
		{
			id = "LanternPrize",
			kind = "charm",
			charm = "DeepLantern",
			name = "Deep Lantern",
			tier = "Uncommon",
			chance = 50,
			refund = 150,
		},
		{
			id = "TatteredMapPrize",
			kind = "map",
			map = "Tattered",
			name = "Tattered Map",
			tier = "Uncommon",
			chance = 30,
			refund = 250,
		},
		{
			id = "WeatheredMapPrize",
			kind = "map",
			map = "Weathered",
			name = "Weathered Map",
			tier = "Rare",
			chance = 120,
			refund = 600,
		},
	} :: { { [string]: any } },
	-- Outcomes at this tier or rarer are announced to the whole server (skins, parts
	-- and variants; never a prize)
	announceFrom = "Rare",
	-- Luck multiplies every skin, part and variant chance; it's capped so coral never
	-- drops below this share (0.5 until the prizes came out of it, 2026-10-28)
	minCoralShare = 0.3,
}
