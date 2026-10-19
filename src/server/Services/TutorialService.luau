--!strict
-- The first-session tutorial (Config/Tutorial): one step at a time, each counting
-- one kind of event, checked here on the server. Since 2026-10-18 it walks a whole
-- first loop (owner: "show them how to complete a full cycle of hunting, storing,
-- spinning, etc."): leave the hub, eat, shells, fill the Haul (its size read here),
-- bank it, spin the Treasure Wheel, roll, use a Kelp Wrap, open the INDEX. Steps
-- that need something hand it over as they start (a wheel spin, shells for a roll, a
-- Kelp Wrap) if the player has none. Finishing opens species select and pays a
-- little coral and shells (the 'Cuda is earned after, Config/Species). The client
-- shows the current step and points the way (TutorialController).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.Tutorial)
local Size = require(ReplicatedStorage.Shared.Size)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local HuntService = require(script.Parent.HuntService)
local ItemService = require(script.Parent.ItemService)
local StateService = require(script.Parent.StateService)
local WheelService = require(script.Parent.WheelService)

local Tutorial = Config.Tutorial

local TutorialService = {}

-- Saves from before the 2026-10-18 list (v nil: LeaveHub, Eat, Bank, Shells, Level)
-- move onto the new one: the same step where it still exists, else the next new
-- thing to learn. A Bank step goes back to filling the Haul (a rejoin starts with an
-- empty one), the old Shells and Level steps on to the Treasure Wheel. A brand-new
-- save (step 1, v nil too) stays on step 1.
local OLD_STEPS: { [number]: string } = {
	[1] = "LeaveHub",
	[2] = "Eat",
	[3] = "Haul",
	[4] = "Wheel",
	[5] = "Wheel",
}

local stepIndex: { [string]: number } = {}
for i, step in Tutorial.steps do
	stepIndex[step.id] = i
end

local function migrate(data: DataService.PlayerData)
	local tutorial = data.tutorial
	if tutorial.v == Tutorial.version then
		return
	end
	if not tutorial.done then
		local id = OLD_STEPS[tutorial.step] or "Wheel"
		local index = stepIndex[id] or 1
		-- Progress carries over only where the step is the same one
		if index ~= tutorial.step or (id ~= "LeaveHub" and id ~= "Eat") then
			tutorial.progress = 0
		end
		tutorial.step = index
	end
	tutorial.v = Tutorial.version
end

local function finish(player: Player, data: DataService.PlayerData)
	local tutorial = data.tutorial
	tutorial.done = true
	local reward = Tutorial.reward
	EconomyService.addShells(player, reward.shells)
	EconomyService.addCoral(player, reward.coral)
	DataService.markDirty(player)
	DataService.save(player)
	local cuda = Config.Species.byId.Cuda.unlock
	Net.notify(
		player,
		`Tutorial complete! +{reward.coral} coral and +{reward.shells} shells. INDEX shows what's next; Nibbler LV {cuda.level} unlocks the 'Cuda`,
		"rare"
	)
end

-- Finishes the tutorial now, with its reward (Admin: testers skip straight to
-- species select). False if it was already done.
function TutorialService.complete(player: Player): boolean
	local data = DataService.get(player)
	if data == nil or data.tutorial.done then
		return false
	end
	finish(player, data)
	return true
end

-- The Haul step's target in kg, from the Nibbler's banked mass: HAUL_LEVELS' worth,
-- a full Haul for a new fish (Config/Tuning `growth` `cap`), or a full Haul if it's
-- less (a fish that banked part of its first dive past LV 3), so the step can end
local function haulTarget(data: DataService.PlayerData): number
	local banked = Progress.mass(data, Config.Species.STARTER)
	return math.min(Tutorial.haulTarget(banked), Size.haulCap(banked) * 0.999)
end

-- A step starting: hand over what it needs if the player has none (each only while
-- its step is up, and using it ends the step, so it can't be farmed)
local function enter(player: Player, data: DataService.PlayerData, step: TutorialConfig.Step)
	if step.grant == "spin" and data.wheel.spins < 1 then
		WheelService.give(player, 1)
		Net.notify(player, "A free Treasure Wheel spin for you! The wheel is on the plaza", "good")
	elseif step.grant == "roll" then
		local need = Config.Rolls.shellsPerRoll - data.shells
		if need > 0 then
			EconomyService.addShells(player, need)
			Net.notify(player, `+{need} shells: enough for your first roll!`, "good")
		end
	elseif step.grant == "wrap" and (data.charms.KelpWrap or 0) < 1 then
		if ItemService.give(player, "KelpWrap", 1) > 0 then
			Net.notify(player, "A Kelp Wrap for you! It's in your item bar", "good")
		end
	end
end

-- What a step's progress is right now, for the steps measured rather than counted
local function measure(player: Player, data: DataService.PlayerData, step: TutorialConfig.Step): number?
	if step.event == "haul" then
		local share = HuntService.haul(player) / math.max(haulTarget(data), 1e-6)
		return math.clamp(math.floor(share * 100), 0, step.goal)
	end
	return nil
end

-- Moves past any steps that are already met (a Haul already big enough), handing
-- each new step what it needs.
local function settle(player: Player, data: DataService.PlayerData)
	local tutorial = data.tutorial
	tutorial.v = Tutorial.version
	while not tutorial.done do
		local step = Tutorial.steps[tutorial.step]
		if step == nil then
			finish(player, data)
			return
		end
		local measured = measure(player, data, step)
		if measured then
			tutorial.progress = measured
		end
		if tutorial.progress < step.goal then
			return
		end
		tutorial.step += 1
		tutorial.progress = 0
		local nextStep = Tutorial.steps[tutorial.step]
		if nextStep then
			Net.notify(player, "Tutorial step complete!", "good")
			enter(player, data, nextStep)
		end
	end
end

local function current(player: Player): (DataService.PlayerData?, TutorialConfig.Step?)
	local data = DataService.get(player)
	if data == nil or data.tutorial.done then
		return nil, nil
	end
	return data, Tutorial.steps[data.tutorial.step]
end

local function count(player: Player, event: string, amount: number)
	local data, step = current(player)
	if data == nil then
		return
	end
	if step and step.event == event then
		data.tutorial.progress += amount
	end
	settle(player, data)
	DataService.markDirty(player)
end

-- Back to a step (the Haul was lost on the way home)
local function back(player: Player, data: DataService.PlayerData, id: string, text: string)
	local index = stepIndex[id]
	if index == nil or data.tutorial.step <= index then
		return
	end
	data.tutorial.step = index
	data.tutorial.progress = 0
	DataService.markDirty(player)
	Net.notify(player, text, "info")
end

function TutorialService.start()
	Events.leftHub:connect(function(player: Player)
		count(player, "leftHub", 1)
	end)
	Events.ate:connect(function(player: Player, amount: number)
		count(player, "ate", amount)
		count(player, "haul", 0)
	end)
	Events.banked:connect(function(player: Player)
		-- Banked before the Haul was full: that's the lesson anyway, so the Haul step
		-- and the Bank step both count
		local data, step = current(player)
		if data and step and step.event == "haul" then
			data.tutorial.progress = step.goal
			data.tutorial.step += 1
			data.tutorial.progress = 0
		end
		count(player, "banked", 1)
	end)
	Events.shells:connect(function(player: Player, amount: number)
		count(player, "shells", amount)
	end)
	Events.spun:connect(function(player: Player)
		count(player, "spun", 1)
	end)
	Events.rolled:connect(function(player: Player)
		count(player, "rolled", 1)
	end)
	Events.usedItem:connect(function(player: Player)
		count(player, "item", 1)
	end)
	-- Eaten on the way home: the Haul is gone, so it's back to filling it
	Events.burst:connect(function(player: Player)
		local data, step = current(player)
		if data and step and step.event == "banked" then
			back(player, data, "Haul", "You lost your Haul! Fill it again, then bank it at home")
		end
	end)
	-- The INDEX opened (only the client can see that; nothing is paid for it alone)
	Net.onRequest("TutorialSaw", function(player: Player, what: any)
		if what == "Index" then
			count(player, "index", 1)
		end
	end)
	-- The Haul step reads the Haul itself (chum, bites and kills grow it too), and a
	-- fish on the Bank step with nothing left to bank (eaten on the way, or back after
	-- a rejoin) goes back to filling it
	Guard.loop("TutorialService.haul", 0.5, function()
		for _, player in Players:GetPlayers() do
			local data, step = current(player)
			if data == nil or step == nil then
				continue
			end
			if step.event == "haul" then
				local before, beforeStep = data.tutorial.progress, data.tutorial.step
				settle(player, data)
				if data.tutorial.progress ~= before or data.tutorial.step ~= beforeStep then
					DataService.markDirty(player)
				end
			elseif step.event == "banked" and HuntService.haul(player) <= 0 then
				back(player, data, "Haul", "Your Haul is empty! Fill it again, then bank it at home")
			end
		end
	end)
	DataService.loaded:connect(function(player: Player, data: DataService.PlayerData)
		migrate(data)
		if not data.tutorial.done then
			local step = Tutorial.steps[data.tutorial.step]
			if step then
				enter(player, data, step)
			end
			settle(player, data)
		end
	end)
	StateService.provide(function(_player, data, state)
		state.tutorial = data.tutorial
	end)
end

-- Starts the tutorial again from step 1 (the admin panel)
function TutorialService.restart(player: Player, data: DataService.PlayerData)
	data.tutorial = { step = 1, progress = 0, done = false, v = Tutorial.version }
	DataService.markDirty(player)
end

return TutorialService
