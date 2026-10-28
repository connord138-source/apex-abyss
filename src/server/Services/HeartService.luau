--!strict
-- Den hearts (owner, 2026-10-28: "i like the den changes lets do that and try it
-- out", the den proposal's §3 "Den visits that count",
-- docs/proposals/2026-10-28-den-expansion.md). A visitor in someone else's den can
-- admire it once a UTC day (E / Y / ADMIRE, HeartController; `AdmireDen`): the owner
-- gets a heart (`data.den.hearts`, for good), a 25 coral tip (Shared/Hearts.TIP,
-- fixed: addCoral), a toast and a point on this week's Best Dens board
-- (Config/Leaderboards). Last week's top 3 on that board wear a gold frame on their
-- den's signs this week (`data.den.frame` = the week; LeaderboardService.ranked).
--
-- The signs: the doorway's nameplate on the plaza (DenDoor.setHearts) and the title
-- board inside (DenBuilder.setHearts) show the heart count and the frame. Clients
-- read who lives where and how loved it is from player attributes on each den's
-- owner: `DenIndex`, `DenHearts`, `DenFramed` (a visitor's client can't see the
-- owner's state), and their own `admired` record from their state.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Hearts = require(ReplicatedStorage.Shared.Hearts)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Tides = require(ReplicatedStorage.Shared.Tides)
local Timing = require(ReplicatedStorage.Shared.Timing)
local DenBuilder = require(script.Parent.Parent.DenBuilder)
local DenDoor = require(script.Parent.Parent.DenDoor)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local StateService = require(script.Parent.StateService)

local BOARD = "BestDens" -- Config/Leaderboards

local HeartService = {}

-- Whether a den record wears the Best Dens frame this week
local function framedNow(data: DataService.PlayerData): boolean
	return Hearts.framed(data.den.frame, Tides.week(Timing.unix()))
end

-- What each den owner's signs show now (so the weekly check only redraws a change)
local shown: { [Player]: boolean } = {}

-- Puts a den owner's hearts and frame on their den's signs, and on their player for
-- clients (the visitor's chip reads them)
local function show(player: Player)
	local data = DataService.get(player)
	local index = FishService.denOf(player)
	if data == nil or index == nil then
		return
	end
	local hearts = data.den.hearts or 0
	local framed = framedNow(data)
	shown[player] = framed
	player:SetAttribute("DenIndex", index)
	player:SetAttribute("DenHearts", hearts)
	player:SetAttribute("DenFramed", framed)
	Guard.run("HeartService.signs", function()
		DenDoor.setHearts(index, hearts, framed)
		DenBuilder.setHearts(index, hearts, framed)
	end)
end

-- `count` hearts for a den owner (a visitor's, or the admin's): saved, on the board,
-- on the signs
local function give(owner: Player, data: DataService.PlayerData, count: number)
	data.den.hearts = (data.den.hearts or 0) + count
	LeaderboardService.add(owner, BOARD, count)
	DataService.markDirty(owner)
	show(owner)
end

-- A visitor admires den `index` (untrusted: checked here)
local function admire(player: Player, index: any)
	if typeof(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > Layout.DEN_COUNT then
		return
	end
	local data = DataService.get(player)
	local owner = FishService.ownerOf(index)
	local ownerData = if owner then DataService.get(owner) else nil
	if data == nil or owner == nil or ownerData == nil then
		return
	end
	if owner == player then
		return -- (your own den: E opens the den menu there)
	end
	-- Really inside that den now
	local _, root = FishService.character(player)
	if root == nil or Layout.denAt(root.Position) ~= index then
		return
	end
	local day = Tides.day(Timing.unix())
	if Hearts.admired(data.admired, day, owner.UserId) then
		Net.notify(player, `You already admired {owner.DisplayName}'s den today. Come back tomorrow!`, "info")
		return
	end
	Hearts.mark(data.admired, day, owner.UserId)
	DataService.markDirty(player)
	give(owner, ownerData, 1)
	EconomyService.addCoral(owner, Hearts.TIP)
	local total = ownerData.den.hearts
	local hearts = `{Hearts.short(total)} {if total == 1 then "heart" else "hearts"}`
	Net.notify(
		owner,
		`{player.DisplayName} admired your den! +{Hearts.TIP} coral tip · {hearts} in all`,
		"good"
	)
	Net.notify(player, `You admired {owner.DisplayName}'s den. You can admire it again tomorrow.`, "good")
end

-- Testing (the admin panel): `count` hearts for each target's den (and their Best
-- Dens score this week)
function HeartService.addHearts(player: Player, count: number)
	local data = DataService.get(player)
	if data then
		give(player, data, count)
	end
end

-- Testing: the target can admire every den again today
function HeartService.admireAgain(player: Player)
	local data = DataService.get(player)
	if data then
		data.admired = { day = 0, dens = {} }
		DataService.markDirty(player)
	end
end

-- Testing: the Best Dens frame on (this week) or off; returns whether it's on now
function HeartService.toggleFrame(player: Player): boolean
	local data = DataService.get(player)
	if data == nil then
		return false
	end
	data.den.frame = if framedNow(data) then 0 else Tides.week(Timing.unix())
	DataService.markDirty(player)
	show(player)
	return framedNow(data)
end

function HeartService.start()
	Net.onRequest("AdmireDen", admire)
	-- A den handed out: its hearts and frame go up on its signs
	FishService.denAssigned:connect(function(player: Player, _index: number)
		show(player)
	end)
	DataService.releasing:connect(function(player: Player)
		shown[player] = nil
	end)
	-- Last week's top 3 Best Dens: a gold frame on their signs this week
	LeaderboardService.ranked:connect(function(player: Player, boardId: string, rank: number, week: number)
		local board = Config.Leaderboards.byId[boardId]
		local data = DataService.get(player)
		if board == nil or boardId ~= BOARD or data == nil or not Hearts.earnsFrame(rank, board.frame) then
			return
		end
		if data.den.frame ~= week then
			data.den.frame = week
			DataService.markDirty(player)
			Net.notify(
				player,
				`Your den was #{rank} in last week's Best Dens: its signs wear a gold frame this week!`,
				"rare"
			)
		end
		show(player)
	end)
	-- A frame ends with its week (and starts with one, for a player who was here)
	Guard.loop("HeartService.frames", 60, function()
		for player, data in DataService.loadedPlayers() do
			if FishService.denOf(player) and shown[player] ~= framedNow(data) then
				show(player)
				DataService.markDirty(player) -- (state.denFramed)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		shown[player] = nil
	end)
	-- The visitor's own record (which dens they admired today), and the den's frame
	-- for its owner's menu (their hearts are `den.hearts` in state.den)
	StateService.provide(function(_player, data, state)
		state.admired = data.admired
		state.denFramed = framedNow(data)
	end)
end

return HeartService
