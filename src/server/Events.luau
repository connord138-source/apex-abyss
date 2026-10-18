--!strict
-- Game events services announce and others listen to (the tutorial, later quests
-- and achievements), so the services that do things don't need to know who cares.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

return {
	ate = Signal.new(), -- (player, count) prey, forage or players eaten
	atePrey = Signal.new(), -- (player, preyId, position) one prey fish eaten (treasure drops)
	-- (player, amount, level, worth) a Haul banked: `amount` kg went on, `worth` is that
	-- Haul before the Haul rate (Config/Tuning `growth`), for what a bank pays
	banked = Signal.new(),
	leftHub = Signal.new(), -- (player) swam out of the safe zone
	shells = Signal.new(), -- (player, count) shells picked up
	unlocked = Signal.new(), -- (player, speciesId) a species unlocked
	trophies = Signal.new(), -- (player) something on the den's trophy wall changed
	denChanged = Signal.new(), -- (player, what) the den was upgraded or redecorated
	-- (player, preyId, rarity ("Normal" or a Config/Catch id), position, mass) a prey
	-- fish eaten (the Catch Log, skin goals, bounties, leaderboards)
	caught = Signal.new(),
	bitPredator = Signal.new(), -- (player, predatorId, boss) a bite on an AI hunter or a world boss landed
	bossDamage = Signal.new(), -- (player, amount) damage dealt to a world boss
	treasure = Signal.new(), -- (player, tierId) a treasure chest dug up
	bounty = Signal.new(), -- (player, "done" | "chest") a daily bounty finished, or the chest paid
	bossKill = Signal.new(), -- (player) a world boss kill the player helped with
	passXp = Signal.new(), -- (player, amount, reason) Tide Pass XP from a claim (the daily streak, a playtime gift)
	-- (victim, position, haul, length) a fish was eaten: `haul` of its lost Haul bursts
	-- into chum (ChumService)
	burst = Signal.new(),
	-- (eater, victim, gain) a player ate another player (pods share it, the Apex bounty pays)
	atePlayer = Signal.new(),
	spun = Signal.new(), -- (player) a Treasure Wheel spin paid out (the tutorial)
	rolled = Signal.new(), -- (player) a roll spent 50 shells (the tutorial)
	-- (player, itemId, used) an item from the item bar or wheel: used, or tried with
	-- one in hand at full health (a Kelp Wrap is kept then; the tutorial counts both)
	usedItem = Signal.new(),
}
