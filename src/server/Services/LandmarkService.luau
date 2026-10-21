--!strict
-- The biome landmarks' play (owner, 2026-10-21: the biome detail boards), checked on
-- the server where it pays or moves a fish:
--
--   * Named places (Config/Places): every `checkSeconds` each live fish out of the
--     hub and the dens is checked against the places it hasn't found (their spots are
--     Vector3 attributes on Workspace.Places, set by the builders); the first visit
--     marks `data.places[id]`, pays the place's reward (RewardsService.grant) and
--     toasts it, and the last one found pays `allFound` on top. State `places` lists
--     what's found (the LOG's Places page, the map's names).
--   * The Broken Galleon's bell (`Landmark` "bell"): a bite within reach rings it for
--     everyone near (`Net.landmark`), once a `cooldown` a fish.
--   * The Bay Cannon ("cannon"): a fish at its muzzle is fired along its aim; the
--     client drives the thrust (LandmarkController), and `MovedAt` is stamped through
--     the flight so SpeedService takes it as a push, not a cheat.
--   * The Clam Garden's pearls ("pearl"): a bite within reach of a pearl pays
--     `pearl.reward`; it's gone for that fish until `data.pearls[index]` (Unix time),
--     kept in the save so leaving doesn't grow it back. State `pearls` carries those
--     times so the client hides what's taken.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local FishService = require(script.Parent.FishService)
local HuntService = require(script.Parent.HuntService)
local RewardsService = require(script.Parent.RewardsService)
local StateService = require(script.Parent.StateService)

local Places = Config.Places
type Place = typeof(Places.list[1])

local LandmarkService = {}

local MOUTH_SLACK = 4 -- studs: the client's reach and its view's lag

local function marks(): Instance?
	return workspace:FindFirstChild("Places")
end

local function markAt(name: string): Vector3?
	local folder = marks()
	local value = if folder then folder:GetAttribute(name) else nil
	return if typeof(value) == "Vector3" then value else nil
end

-- A live fish out of the hub and the dens: its middle, or nil
local function outside(player: Player): Vector3?
	local _, root = FishService.character(player)
	if root == nil then
		return nil
	end
	local at = root.Position
	if Layout.inHub(at) or Layout.denAt(at) then
		return nil
	end
	return at
end

-- ---------------------------------------------------------------------------
-- Named places
-- ---------------------------------------------------------------------------

local function found(player: Player, data: DataService.PlayerData, place: Place)
	data.places[place.id] = true
	local got = RewardsService.grant(player, data, place.reward)
	local count = 0
	for _, entry in Places.list do
		if data.places[entry.id] then
			count += 1
		end
	end
	Net.notify(
		player,
		`Discovered {place.name} ({count}/{#Places.list}) · {table.concat(got, ", ")}`,
		"rare"
	)
	if count == #Places.list then
		local bonus = RewardsService.grant(player, data, Places.allFound)
		Net.notify(player, `Every place found! {table.concat(bonus, ", ")}`, "rare")
	end
	DataService.markDirty(player)
end

local function checkPlaces()
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		local at = if data then outside(player) else nil
		if data == nil or at == nil then
			continue
		end
		for _, place in Places.list do
			if data.places[place.id] then
				continue
			end
			local spot = markAt(place.id)
			if spot and (spot - at).Magnitude <= place.radius then
				found(player, data, place)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- The bell, the cannon and the pearls
-- ---------------------------------------------------------------------------

local lastBell: { [Player]: number } = {}
local lastCannon: { [Player]: number } = {}

-- The mouth is within `reach` (plus the fish's own reach) of `spot`
local function bites(player: Player, spot: Vector3, reach: number): boolean
	local mouth, length, slack = HuntService.mouth(player)
	if mouth == nil or Layout.inHub(mouth) or Layout.denAt(mouth) then
		return false
	end
	return (mouth - spot).Magnitude <= reach + Size.reach(length) + slack + MOUTH_SLACK
end

local function ringBell(player: Player, index: number)
	local spot = markAt(`Bell{index}`)
	local now = Timing.clock()
	if spot == nil or now - (lastBell[player] or 0) < Places.bell.cooldown then
		return
	end
	if not bites(player, spot, Places.bell.reach) then
		return
	end
	lastBell[player] = now
	Net.landmark("bell", index, { by = player.UserId })
end

local function fireCannon(player: Player, index: number)
	local muzzle, aim = markAt(`Cannon{index}`), markAt(`Cannon{index}Aim`)
	local tune = Places.cannon
	local now = Timing.clock()
	local at = outside(player)
	if muzzle == nil or aim == nil or at == nil or now - (lastCannon[player] or 0) < tune.cooldown then
		return
	end
	if HuntService.mouth(player) == nil then
		return
	end
	if (at - muzzle).Magnitude > tune.reach + MOUTH_SLACK then
		return
	end
	lastCannon[player] = now
	-- The flight is a push the client drives: stamp MovedAt through it (Net.shove's
	-- stamp), so the speed check takes the cannon's speed as a push
	for k = 0, math.ceil(tune.seconds) do
		task.delay(k, function()
			if player.Parent then
				player:SetAttribute("MovedAt", os.clock())
			end
		end)
	end
	Net.landmarkTo(player, "cannon", index, { aim = aim.Unit, speed = tune.speed, seconds = tune.seconds })
	Net.landmark("boom", index, { by = player.UserId })
end

local function takePearl(player: Player, index: number)
	local data = DataService.get(player)
	local spot = markAt(`Pearl{index}`)
	if data == nil or spot == nil then
		return
	end
	local key = tostring(index)
	local now = Timing.unix()
	if now < (data.pearls[key] or 0) then
		return
	end
	if not bites(player, spot, Places.pearl.reach) then
		return
	end
	data.pearls[key] = now + Places.pearl.regrow
	local got = RewardsService.grant(player, data, Places.pearl.reward)
	Net.notify(player, `A pearl! {table.concat(got, ", ")} · it grows back`, "good")
	DataService.markDirty(player)
end

local function onRequest(player: Player, kind: any, index: any)
	if typeof(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > 64 then
		return
	end
	if kind == "bell" then
		ringBell(player, index)
	elseif kind == "cannon" then
		fireCannon(player, index)
	elseif kind == "pearl" then
		takePearl(player, index)
	end
end

function LandmarkService.start()
	Net.onRequest("Landmark", onRequest)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastBell[player] = nil
		lastCannon[player] = nil
	end)
	Guard.loop("LandmarkService.places", Places.checkSeconds, checkPlaces)
	StateService.provide(function(_player, data, state)
		local list: { string } = {}
		for _, place in Places.list do
			if data.places[place.id] then
				table.insert(list, place.id)
			end
		end
		state.places = list
		-- (only pearls still growing back)
		local now = Timing.unix()
		local pearls: { [string]: number } = {}
		for key, at in data.pearls do
			if at > now then
				pearls[key] = at
			end
		end
		state.pearls = pearls
	end)
end

return LandmarkService
