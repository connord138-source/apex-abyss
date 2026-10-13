--!strict
-- Achievements (owner, 2026-10-13: "players will need to complete achievements to
-- unlock the ability to purchase each set with coral. Once a set is unlocked,
-- pieces are individually bought, not the entire set. This makes them
-- interchangeable if wanted"). Each one opens a den furniture set (Config/Dens
-- `sets`) in the den menu; the pieces are then bought one at a time with coral.
-- AchievementService measures them from the save (lifetime tallies, so what a
-- player did before this shipped counts) and marks each done once, for good.
export type Measure =
	"banks" -- hauls banked
	| "catches" -- rare catches of `rarity` (Config/Catch), any prey
	| "treasures" -- treasure chests dug up
	| "level" -- the best level of any fish
	| "bossKills" -- world boss fights won (≥1% of the damage)

export type Achievement = {
	id: string,
	name: string,
	blurb: string, -- what to do, as a goal ("Bank 25 hauls")
	measure: Measure,
	rarity: string?, -- for "catches"
	goal: number,
	set: string, -- the furniture set it opens (Config/Dens sets)
}

local list: { Achievement } = {
	{
		id = "SettlingIn",
		name = "Settling In",
		blurb = "Bank 25 hauls at your den",
		measure = "banks",
		goal = 25,
		set = "KelpCottage",
	},
	{
		id = "GoldenTouch",
		name = "Golden Touch",
		blurb = "Catch 25 Golden fish",
		measure = "catches",
		rarity = "Golden",
		goal = 25,
		set = "ReefPalace",
	},
	{
		id = "TreasureHunter",
		name = "Treasure Hunter",
		blurb = "Dig up 10 treasure chests",
		measure = "treasures",
		goal = 10,
		set = "Shipwreck",
	},
	{
		id = "DeepDiver",
		name = "Deep Diver",
		blurb = "Reach level 50 with any fish",
		measure = "level",
		goal = 50,
		set = "SunkenTemple",
	},
	{
		id = "GlowGetter",
		name = "Glow Getter",
		blurb = "Catch 15 Glowing fish",
		measure = "catches",
		rarity = "Glowing",
		goal = 15,
		set = "VentForge",
	},
	{
		id = "ApexOfTheAbyss",
		name = "Apex of the Abyss",
		blurb = "Reach level 80 with any fish",
		measure = "level",
		goal = 80,
		set = "AbyssGlow",
	},
	{
		id = "MonsterHunter",
		name = "Monster Hunter",
		blurb = "Help bring down 3 world bosses",
		measure = "bossKills",
		goal = 3,
		set = "Trophies",
	},
}

local byId: { [string]: Achievement } = {}
local bySet: { [string]: Achievement } = {}
for _, achievement in list do
	byId[achievement.id] = achievement
	bySet[achievement.set] = achievement
end

return {
	list = list,
	byId = byId,
	bySet = bySet,
}
