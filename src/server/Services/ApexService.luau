--!strict
-- The Apex bounty (Config/Pvp `apex`, GDD §5): the biggest fish in the server wears
-- a crown that everyone sees on their map and over its name, and a bounty of coral
-- grows on it while it swims out of the hub. Whoever eats it takes the bounty (and,
-- the first time, the Apex Hunter title); a creature that kills it, or the Apex
-- leaving, just ends the reign. The crown moves only to a fish clearly bigger
-- (`takeOver`), so it doesn't flicker between two of a size.
--
-- Workspace attributes for every client: ApexUserId (0 = none), ApexBounty.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local HuntService = require(script.Parent.HuntService)

local tune = Config.Pvp.apex

local ApexService = {}

local apex: Player? = nil
local bounty = 0
local forced = false -- crowned from the admin panel: kept even alone in the server
local lastTick = 0

local function publish()
	workspace:SetAttribute("ApexUserId", if apex then apex.UserId else 0)
	workspace:SetAttribute("ApexBounty", math.floor(bounty))
end

local function liveMass(player: Player): number?
	local data = DataService.get(player)
	local session = HuntService.sessions()[player]
	if data == nil or session == nil or not session.alive then
		return nil
	end
	local banked = Progress.mass(data)
	if Size.level(banked) < tune.minLevel then
		return nil
	end
	return Size.liveMass(banked, session.haul)
end

local function crown(player: Player?)
	if player == apex then
		return
	end
	forced = false
	apex = player
	bounty = tune.base
	publish()
	if player then
		Net.notifyAll(
			`{player.DisplayName} is the APEX · bounty {Format.number(bounty)} coral · eat them to claim it`,
			"rare"
		)
		Net.notify(player, "You're the APEX: everyone can see you on the map. Stay alive!", "rare")
	end
end

-- Admin: crown a player now (nil: nobody)
function ApexService.crown(player: Player?)
	crown(player)
	forced = player ~= nil
end

-- Admin: add to the bounty
function ApexService.addBounty(amount: number)
	bounty = math.clamp(bounty + amount, 0, tune.cap)
	publish()
end

function ApexService.current(): (Player?, number)
	return apex, bounty
end

-- The Apex was eaten by a player: the eater takes the bounty
local function onAtePlayer(eater: Player, victim: Player, _gain: number)
	if victim ~= apex then
		return
	end
	local paid = math.floor(bounty)
	EconomyService.addCoral(eater, paid)
	local data = DataService.get(eater)
	if data then
		data.stats.apexKills = (data.stats.apexKills or 0) + 1
		if not data.titles[tune.title] then
			data.titles[tune.title] = true
			Net.notify(eater, `New title: {tune.title}`, "rare")
		end
		DataService.markDirty(eater)
	end
	Net.notifyAll(
		`{eater.DisplayName} took down the APEX {victim.DisplayName} and claimed {Format.number(paid)} coral!`,
		"rare"
	)
	apex = nil
	bounty = 0
	publish()
end

function ApexService.start()
	publish()
	Events.atePlayer:connect(onAtePlayer)
	Players.PlayerRemoving:Connect(function(player)
		if player == apex then
			apex = nil
			bounty = 0
			publish()
		end
	end)
	Guard.loop("ApexService", 2, function()
		local now = Timing.clock()
		local dt = if lastTick > 0 then now - lastTick else 0
		lastTick = now
		local current = apex
		-- The reign ends when its fish dies (to a creature: no bounty paid)
		if current then
			local session = HuntService.sessions()[current]
			if session == nil or not session.alive then
				apex = nil
				bounty = 0
				publish()
				current = nil
			elseif not session.inHub then
				bounty = math.min(tune.cap, bounty + tune.perMinute * dt / 60)
				publish()
			end
		end
		if #Players:GetPlayers() < tune.minPlayers then
			if current and not forced then
				crown(nil)
			end
			return
		end
		local best: Player? = nil
		local bestMass = 0
		for _, player in Players:GetPlayers() do
			local mass = liveMass(player)
			if mass and mass > bestMass then
				best, bestMass = player, mass
			end
		end
		if best == nil or best == current then
			return
		end
		local held = if current then liveMass(current) else nil
		if held == nil or bestMass >= held * tune.takeOver then
			crown(best)
		end
	end)
end

return ApexService
