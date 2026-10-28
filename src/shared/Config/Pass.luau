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

-- Season 1: Riptide, 40 tiers (owner, 2026-10-17: "A few coral spots could be
-- replaced with the trails or we could extend the pass to 40-50 and add some in with
-- some other smaller items like maps and more coral"; it was 30 tiers of 2,000 XP).
-- The paid row's skins are PassRiptide (tier 1, so the Deep Pass pays at once),
-- PassUndertow (20) and PassAbyssalCurrent (40); the free row's is PassTideglass
-- (26). Boost trails (Config/Trails): free Bubbles 6, Ink 18, Glitter 32; paid Fire
-- 4, Rainbow 11, Frost 16, Storm 27, Stardust 36.
local riptide: Season = {
	name = "Riptide",
	blurb = "The first season: four skins, eight boost trails, two titles, three den pieces and a sea of coral",
	tiers = {
		tier({ coral = 100 }, { skin = "PassRiptide", coral = 300 }),
		tier({ shells = 20 }, { shells = 60 }),
		tier({ wraps = 1 }, { wraps = 2, coral = 200 }),
		tier({ coral = 150 }, { trail = "Fire" }),
		tier({ spins = 1 }, { coral = 400, spins = 1 }),
		tier({ trail = "Bubbles" }, { shells = 75 }),
		tier({ shells = 25 }, { den = "SeaGlassLantern" }),
		tier({ coral = 200 }, { coral = 500 }),
		tier({ charms = { Lucky = 1 } }, { charms = { Lucky = 2 } }),
		tier({ shells = 30 }, { shells = 90 }),
		tier({ coral = 250 }, { trail = "Rainbow" }),
		tier({ wraps = 1 }, { wraps = 2, shells = 40 }),
		tier({ title = "Tide Rider", coral = 300 }, { title = "Riptide", coral = 800, spins = 1 }),
		tier({ shells = 35 }, { shells = 100 }),
		tier({ map = "Tattered" }, { coral = 800 }),
		tier({ coral = 300 }, { trail = "Frost" }),
		tier({ spins = 1 }, { spins = 2 }),
		tier({ trail = "Ink" }, { shells = 120 }),
		tier({ shells = 40 }, { coral = 900 }),
		tier({ coral = 350 }, { skin = "PassUndertow", spins = 1 }),
		tier({ charms = { SecondChance = 1 } }, { charms = { SecondChance = 2 } }),
		tier({ shells = 45 }, { map = "Weathered" }),
		tier({ coral = 400 }, { coral = 1000 }),
		tier({ wraps = 1 }, { den = "PearlPedestal", spins = 1 }),
		tier({ spins = 1 }, { shells = 150 }),
		tier({ skin = "PassTideglass", coral = 400 }, { coral = 1100 }),
		tier({ shells = 50 }, { trail = "Storm" }),
		tier({ coral = 450 }, { coral = 1200 }),
		tier({ map = "Weathered" }, { shells = 180 }),
		tier({ charms = { Lucky = 1 } }, { charms = { Lucky = 2 }, spins = 1 }),
		tier({ shells = 55 }, { den = "CrystalShard" }),
		tier({ trail = "Glitter" }, { coral = 1300 }),
		tier({ coral = 500 }, { spins = 2 }),
		tier({ wraps = 1 }, { map = "Captain" }),
		tier({ shells = 60 }, { shells = 200 }),
		tier({ coral = 550 }, { trail = "Stardust" }),
		tier({ spins = 1 }, { coral = 1400 }),
		tier({ shells = 70 }, { shells = 220 }),
		tier({ coral = 600 }, { coral = 1500 }),
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
	xpPerTier = 1500, -- (2,000 over 30 tiers until 2026-10-17: the same 60,000 for the season)
	paidXp = 1.2, -- Deep Pass holders earn this much more XP
	overtide = { coral = 500 } :: Reward, -- every tier past the last
	-- XP for play. Banking: per kg banked, between `bankMin` and `bankMax` a bank.
	-- A player on for an hour a day (banks, bounties, gifts, the daily) makes
	-- ~2,200 a day and finishes the 40 tiers in about four weeks.
	xp = {
		bankPerKg = 2,
		bankMin = 20,
		bankMax = 300,
		-- (Silver 8 and Golden 25 until 2026-10-28, when twice as many swam: halved, so
		-- a season still takes about four weeks)
		catch = { Normal = 2, Silver = 4, Golden = 12, Glowing = 60, Crystal = 150, Prism = 300 } :: { [string]: number },
		bounty = 150,
		chest = 300,
		boss = 400,
		treasure = 100,
		daily = 200,
	},
	seasons = { riptide }, -- season n uses seasons[(n - 1) % #seasons + 1]
}
