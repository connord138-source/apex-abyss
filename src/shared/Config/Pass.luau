--!strict
-- The Tide Pass (PassService; owner, 2026-10-12: a monetizable asset that pays on
-- playtime): a season pass of `weeks` weeks on the Tide Clock's week numbers
-- (Shared/Tides.week), `tiers` tiers of `xpPerTier` XP each. Playing earns the XP
-- (`xp`: banking, catches, bounties, bosses, treasure, the daily streak and the
-- playtime gifts), and every tier has a free reward; the Deep Pass (a developer
-- product, Config/Monetization `DeepPass`, bought for the season) opens the paid
-- row too and earns XP ×`paidXp`. Rewards are cosmetics up to Epic (the owner's rule:
-- Legendary and Mythic skins only roll), titles, den pieces, coral, shells, spins and
-- maps. Past the last tier every `xpPerTier` more pays `overtide`. A new season
-- claims whatever was unlocked and starts the record again; the Deep Pass is per
-- season.
local Rewards = require(script.Parent.Rewards)

export type Reward = Rewards.Reward
export type Tier = { free: Reward?, paid: Reward? }
export type Season = { name: string, blurb: string, tiers: { Tier } }

local function tier(free: Reward?, paid: Reward?): Tier
	return { free = free, paid = paid }
end

-- Season 1: Riptide. The paid row's skins are PassRiptide (tier 1, so the Deep Pass
-- pays at once), PassUndertow (15) and PassAbyssalCurrent (30); the free row's is
-- PassTideglass (20).
local riptide: Season = {
	name = "Riptide",
	blurb = "The first season: four skins, two titles, three den pieces and a sea of coral",
	tiers = {
		tier({ coral = 100 }, { skin = "PassRiptide", coral = 300 }),
		tier({ shells = 20 }, { shells = 60 }),
		tier({ wraps = 1 }, { wraps = 2, coral = 200 }),
		tier({ coral = 150 }, { coral = 400 }),
		tier({ spins = 1 }, { den = "SeaGlassLantern", spins = 1 }),
		tier({ shells = 25 }, { shells = 75 }),
		tier({ coral = 200 }, { coral = 500 }),
		tier({ charms = { Lucky = 1 } }, { charms = { Lucky = 2 } }),
		tier({ shells = 30 }, { shells = 90 }),
		tier({ title = "Tide Rider", coral = 300 }, { title = "Riptide", coral = 800, spins = 1 }),
		tier({ coral = 250 }, { coral = 600 }),
		tier({ wraps = 1 }, { wraps = 2, shells = 40 }),
		tier({ shells = 35 }, { shells = 100 }),
		tier({ coral = 300 }, { coral = 800 }),
		tier({ spins = 1 }, { skin = "PassUndertow", spins = 2 }),
		tier({ shells = 40 }, { shells = 120 }),
		tier({ coral = 350 }, { coral = 900 }),
		tier({ charms = { SecondChance = 1 } }, { charms = { SecondChance = 2 } }),
		tier({ shells = 45 }, { shells = 130 }),
		tier({ skin = "PassTideglass", coral = 400 }, { den = "PearlPedestal", coral = 1000, spins = 1 }),
		tier({ coral = 450 }, { coral = 1100 }),
		tier({ wraps = 1 }, { map = "Weathered" }),
		tier({ shells = 50 }, { shells = 150 }),
		tier({ coral = 500 }, { coral = 1200 }),
		tier({ spins = 1 }, { den = "CrystalShard", spins = 2 }),
		tier({ shells = 60 }, { shells = 180 }),
		tier({ coral = 600 }, { coral = 1500 }),
		tier({ charms = { Lucky = 1 } }, { map = "Captain" }),
		tier({ shells = 70 }, { shells = 200 }),
		tier(
			{ title = "Riptide Veteran", coral = 1000, spins = 1 },
			{ skin = "PassAbyssalCurrent", title = "Abyss Walker", coral = 2500, spins = 3 }
		),
	},
}

return {
	name = "Tide Pass",
	product = "DeepPass", -- Config/Monetization product key
	start = 1791763200, -- Monday 2026-10-12 00:00 UTC: season 1's first week
	weeks = 4,
	xpPerTier = 2000,
	paidXp = 1.2, -- Deep Pass holders earn this much more XP
	overtide = { coral = 500 } :: Reward, -- every tier past the last
	-- XP for play. Banking: per kg banked, between `bankMin` and `bankMax` a bank.
	-- A player on for an hour a day (banks, bounties, gifts, the daily) makes
	-- ~2,200 a day and finishes the 30 tiers in about four weeks.
	xp = {
		bankPerKg = 2,
		bankMin = 20,
		bankMax = 300,
		catch = { Normal = 2, Golden = 25, Glowing = 60, Crystal = 150, Prism = 300 } :: { [string]: number },
		bounty = 150,
		chest = 300,
		boss = 400,
		treasure = 100,
		daily = 200,
	},
	seasons = { riptide }, -- season n uses seasons[(n - 1) % #seasons + 1]
}
