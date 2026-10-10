--!strict
-- Game events services announce and others listen to (the tutorial, later quests
-- and achievements), so the services that do things don't need to know who cares.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

return {
	ate = Signal.new(), -- (player, count) prey, forage or players eaten
	atePrey = Signal.new(), -- (player, preyId, position) one prey fish eaten (treasure drops)
	banked = Signal.new(), -- (player, amount, level) a Haul banked
	leftHub = Signal.new(), -- (player) swam out of the safe zone
	shells = Signal.new(), -- (player, count) shells picked up
	unlocked = Signal.new(), -- (player, speciesId) a species unlocked
	trophies = Signal.new(), -- (player) something on the den's trophy wall changed
	denChanged = Signal.new(), -- (player, what) the den was upgraded or redecorated
	-- (player, preyId, rarity ("Normal" or a Config/Catch id), position, mass) a prey
	-- fish eaten (the Catch Log, catch tracks, bounties, leaderboards)
	caught = Signal.new(),
	bitPredator = Signal.new(), -- (player, predatorId, boss) a bite on an AI hunter or a world boss landed
	bossDamage = Signal.new(), -- (player, amount) damage dealt to a world boss
	treasure = Signal.new(), -- (player, tierId) a treasure chest dug up
}
