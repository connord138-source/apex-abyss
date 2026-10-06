--!strict
-- Rolls: every 50 Shells is one roll. Most rolls pay Coral (the currency); a few
-- give a shade (Config/Shades); very rarely a body part or an exotic variant
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
	-- Outcomes at this tier or rarer are announced to the whole server
	announceFrom = "Rare",
	-- Luck multiplies every non-coral chance; it's capped so coral never drops
	-- below this share
	minCoralShare = 0.5,
}
