--!strict
-- The first-session tutorial (Config/Tutorial): one step at a time, each counting
-- one kind of event. Finishing it unlocks the 'Cuda and species select, and pays
-- enough shells for a first roll. The client shows the current step and points the
-- way (TutorialController).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Size = require(ReplicatedStorage.Shared.Size)
local Events = require(script.Parent.Parent.Events)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StateService = require(script.Parent.StateService)

local Tutorial = Config.Tutorial

local TutorialService = {}

local function finish(player: Player, data: DataService.PlayerData)
	local tutorial = data.tutorial
	tutorial.done = true
	local reward = Tutorial.reward
	data.unlocked[reward.unlock] = true
	EconomyService.addShells(player, reward.shells)
	EconomyService.addCoral(player, reward.coral)
	DataService.markDirty(player)
	DataService.save(player)
	local species = Config.Species.byId[reward.unlock]
	Net.notify(player, `Tutorial complete! The {species.name} is yours, and so is your first roll`, "rare")
end

-- The Nibbler's level, for the level step.
local function nibblerLevel(data: DataService.PlayerData): number
	return Size.level(Progress.mass(data, Config.Species.STARTER))
end

-- Moves past any steps that are already met (a level step after a big bank).
local function settle(player: Player, data: DataService.PlayerData)
	local tutorial = data.tutorial
	while not tutorial.done do
		local step = Tutorial.steps[tutorial.step]
		if step == nil then
			finish(player, data)
			return
		end
		if step.event == "level" then
			tutorial.progress = math.min(nibblerLevel(data), step.goal)
		end
		if tutorial.progress < step.goal then
			return
		end
		tutorial.step += 1
		tutorial.progress = 0
		if Tutorial.steps[tutorial.step] then
			Net.notify(player, "Tutorial step complete!", "good")
		end
	end
end

local function count(player: Player, event: string, amount: number)
	local data = DataService.get(player)
	if data == nil or data.tutorial.done then
		return
	end
	local step = Tutorial.steps[data.tutorial.step]
	if step and step.event == event then
		data.tutorial.progress += amount
	end
	settle(player, data)
	DataService.markDirty(player)
end

function TutorialService.start()
	Events.leftHub:connect(function(player: Player)
		count(player, "leftHub", 1)
	end)
	Events.ate:connect(function(player: Player, amount: number)
		count(player, "ate", amount)
	end)
	Events.banked:connect(function(player: Player)
		count(player, "banked", 1)
		count(player, "level", 0)
	end)
	Events.shells:connect(function(player: Player, amount: number)
		count(player, "shells", amount)
	end)
	DataService.loaded:connect(function(player: Player, data: DataService.PlayerData)
		if not data.tutorial.done then
			settle(player, data)
		end
	end)
	StateService.provide(function(_player, data, state)
		state.tutorial = data.tutorial
	end)
end

return TutorialService
