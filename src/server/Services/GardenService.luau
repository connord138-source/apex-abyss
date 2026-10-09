--!strict
-- The den's Coral Garden, the game's AFK income (owner, 2026-10-09: "an afk aspect
-- of the game to earn something to keep players coming back"; GDD §10's den farm).
-- Every den grows coral and a few shells over real time (Config/Dens garden, the
-- shared Garden helper):
--
--  * Away from the game it keeps growing, up to 8 hours' worth (16 with the Deep
--    Garden pass), so there's always something waiting when you come back.
--  * Online it grows at the same rate, and twice as fast while you rest in your own
--    den, where it's collected every minute: AFK in your den is a steady income.
--  * Swimming into your den collects it (you spawn there, so a returning player
--    collects at once and is told what grew while they were away).
--  * A bigger den grows more; VIP, Premium and the group perk add their coral share.
--
-- The garden's corals grow visibly as it fills and sparkle once full (DenBuilder).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Garden = require(ReplicatedStorage.Shared.Garden)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Timing = require(ReplicatedStorage.Shared.Timing)
local DenBuilder = require(script.Parent.Parent.DenBuilder)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local MonetizationService = require(script.Parent.MonetizationService)
local StateService = require(script.Parent.StateService)

type PlayerData = DataService.PlayerData

local tune = Config.Dens.garden
local TICK = 5
local AWAY_NOTICE = 10 * 60 -- away at least this long: the first collection says so

type Watch = {
	inDen: boolean,
	lastCollect: number,
	away: number?, -- seconds away before this session (until the first collection)
	shown: number, -- the fill step the garden was last drawn at
}

local GardenService = {}

local watches: { [Player]: Watch } = {}

local function ratesOf(player: Player, data: PlayerData): Garden.Rates
	return Garden.rates(data.den.level, MonetizationService.hasPass(player, "DeepGarden"))
end

-- Whether the player's fish is inside their own den right now
local function inOwnDen(player: Player): boolean
	local _, root = FishService.character(player)
	local den = FishService.denOf(player)
	return root ~= nil and den ~= nil and Layout.denAt(root.Position) == den
end

-- Redraws the garden when it has grown (or been emptied) a step
local function redraw(player: Player, data: PlayerData, force: boolean?)
	local watch = watches[player]
	local den = FishService.denOf(player)
	if watch == nil or den == nil then
		return
	end
	local rates = ratesOf(player, data)
	local fill = Garden.fill(data.garden, rates)
	local shellFill = if rates.capShells > 0 then data.garden.shells / rates.capShells else 0
	-- 7 corals fill one after another; 28 steps keeps each one's growth smooth
	local step = math.floor(fill * 28) + math.floor(shellFill * 5) * 100
	if step == watch.shown and not force then
		return
	end
	watch.shown = step
	Guard.run("GardenService.draw", function()
		DenBuilder.garden(den, data.den, fill, shellFill)
	end)
end

-- Moves what's grown (whole coral and shells) into the wallet
local function collect(player: Player, data: PlayerData)
	local watch = watches[player]
	local coral = math.floor(data.garden.coral)
	local shells = math.floor(data.garden.shells)
	if coral < 1 and shells < 1 then
		return
	end
	data.garden.coral -= coral
	data.garden.shells -= shells
	local earned = EconomyService.earnCoral(player, coral)
	EconomyService.addShells(player, shells)
	local away = if watch then watch.away else nil
	if watch then
		watch.away = nil
		watch.lastCollect = Timing.now()
	end
	Net.gardenCollected(player, {
		coral = earned,
		shells = shells,
		away = if away and away >= AWAY_NOTICE then away else nil,
	})
	DataService.markDirty(player)
	redraw(player, data)
end

local function tick()
	local now = Timing.now()
	for player, watch in watches do
		Guard.run("GardenService.tick", function()
			local data = DataService.get(player)
			if data == nil then
				return
			end
			local inDen = inOwnDen(player)
			Garden.grow(data.garden, ratesOf(player, data), now, if inDen then tune.rest else 1)
			if inDen and (not watch.inDen or now - watch.lastCollect >= tune.collectEvery) then
				collect(player, data)
			end
			watch.inDen = inDen
			redraw(player, data)
			DataService.markDirty(player)
		end)
	end
end

-- Admin testing: grows the garden as if the player had been away `hours`.
function GardenService.fastForward(player: Player, hours: number)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local rates = ratesOf(player, data)
	data.garden.at = Timing.now() - hours * 3600
	local seconds = Garden.grow(data.garden, rates, Timing.now(), 1)
	local watch = watches[player]
	if watch then
		watch.away = seconds
		watch.inDen = false -- so the next tick in the den collects with the notice
	end
	DataService.markDirty(player)
	redraw(player, data, true)
end

function GardenService.start()
	DataService.loaded:connect(function(player: Player, data: PlayerData)
		-- What grew while they were away (capped at what the garden holds)
		local away = Garden.grow(data.garden, ratesOf(player, data), Timing.now(), 1)
		watches[player] = { inDen = false, lastCollect = 0, away = away, shown = -1 }
	end)
	DataService.releasing:connect(function(player: Player, data: PlayerData)
		Garden.grow(
			data.garden,
			ratesOf(player, data),
			Timing.now(),
			if inOwnDen(player) then tune.rest else 1
		)
		watches[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		watches[player] = nil
	end)
	-- The garden is drawn with the den (a new den, an upgrade); a Deep Garden pass
	-- changes what it holds
	FishService.denAssigned:connect(function(player: Player)
		local watch = watches[player]
		if watch then
			watch.shown = -1
		end
	end)
	MonetizationService.passAdded:connect(function(player: Player, key: string)
		local watch = watches[player]
		if key == "DeepGarden" and watch then
			watch.shown = -1
		end
	end)
	Guard.loop("GardenService.tick", TICK, tick)
	StateService.provide(function(player, data, state)
		local rates = ratesOf(player, data)
		state.garden = {
			coral = math.floor(data.garden.coral),
			shells = math.floor(data.garden.shells),
			capCoral = math.floor(rates.capCoral),
			capShells = math.floor(rates.capShells),
			coralPerHour = rates.coralPerHour,
			shellsPerHour = rates.shellsPerHour,
			hours = rates.hours,
			rest = tune.rest,
			resting = watches[player] ~= nil and watches[player].inDen,
		}
	end)
end

return GardenService
