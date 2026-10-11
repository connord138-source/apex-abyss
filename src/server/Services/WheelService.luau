--!strict
-- The Treasure Wheel (Config/Wheel; owner, 2026-10-10: "do want a spin wheel
-- again"), ported from Hatch & Snatch's Luck Wheel. A game-show wheel on the hub
-- plaza (TreasureWheel.luau builds it; WorldService stands it on the cave floor). A
-- player at its big red button spends a spin; the server picks the prize and
-- publishes the spin as attributes on ReplicatedStorage.WheelState, and every client
-- animates the same spin from them (TreasureWheelController).
--
-- From Hatch & Snatch's rebuild (its owner: "VERY crude and glitchy" before): a
-- second spinner joins a line (one place per player) instead of being turned away,
-- and Spin all keeps a player in the line until their spins run out (it pauses on
-- the jackpot). Each result stays up a moment before the next spin. Spins come back
-- on their own every few hours (online or off, up to a cap), so it's a reason to come
-- back; never sold.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Timing = require(ReplicatedStorage.Shared.Timing)
local TreasureWheel = require(script.Parent.Parent.TreasureWheel)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local HuntService = require(script.Parent.HuntService)
local StateService = require(script.Parent.StateService)
local TreasureService = require(script.Parent.TreasureService)
local WardrobeService = require(script.Parent.WardrobeService)
local WorldService = require(script.Parent.WorldService)

type PlayerData = DataService.PlayerData

local Wheel = Config.Wheel
local Tiers = Config.Tiers

local SPIN_SECONDS = 5.5
local SETTLE_SECONDS = 0.25 -- after the clients' spin ends, the server pays out
local RESULT_SECONDS = 1.8 -- the result shows this long before the next spin in line
local IDLE_SECONDS = 8 -- then the sign goes back to inviting a spin
local IDLE_TEXT = "Swim up to the big red button to spin!"
local rng = Random.new()

type Prize = { index: number, amount: number, detail: string, skin: string? }
type Entry = { player: Player, auto: boolean, prize: Prize?, paid: boolean? }

local queue: { Entry } = {}
local current: Entry? = nil
local resting = false -- a result is showing; the next spin waits for it
local spinCount = 0
local state: Folder
local rigged: { [Player]: number } = {} -- the admin's "land on": the next spin's slice

local WheelService = {}

-- Free spins: one every `freeEvery`, online or off, while fewer than `maxFree` wait
-- (and a new player's first). Returns whether a spin came.
local function accrue(data: PlayerData, now: number): boolean
	local wheel = data.wheel
	if wheel.lastFree == 0 then
		wheel.lastFree = now
		wheel.spins += Wheel.startSpins
		return Wheel.startSpins > 0
	end
	if wheel.spins >= Wheel.maxFree then
		wheel.lastFree = now -- full: the clock starts again once one is used
		return false
	end
	local earned = math.floor((now - wheel.lastFree) / Wheel.freeEvery)
	if earned <= 0 then
		return false
	end
	local add = math.min(earned, Wheel.maxFree - wheel.spins)
	wheel.spins += add
	wheel.lastFree += earned * Wheel.freeEvery
	return add > 0
end

-- Adds spins (the Bounty Chest, the Catch of the Week, the daily streak, the admin)
function WheelService.give(player: Player, count: number)
	local data = DataService.get(player)
	if data == nil or count <= 0 then
		return
	end
	accrue(data, Timing.now())
	data.wheel.spins += count
	DataService.markDirty(player)
end

-- The admin's "land on": the next spin of `player` stops on slice `index`
function WheelService.rig(player: Player, index: number)
	rigged[player] = index
end

local function pickSegment(): number
	local total = 0
	for _, segment in Wheel.segments do
		total += segment.weight
	end
	local roll = rng:NextNumber() * total
	for index, segment in Wheel.segments do
		roll -= segment.weight
		if roll <= 0 then
			return index
		end
	end
	return 1
end

-- Where the wheel stops for slice `index`, in degrees: slice i sits (i - 1) × slice
-- round from the top, so turning by that angle brings it under the flapper. It stops
-- in a gap between two pegs, where the flapper hangs straight (Hatch & Snatch
-- playtest 2026-10-04: stopped against a peg it rested tilted ~30°).
local function landingAngle(index: number): number
	local slice = 360 / #Wheel.segments
	local spacing = 360 / TreasureWheel.PEGS
	local offsets: { number } = {}
	for k = -TreasureWheel.PEGS, TreasureWheel.PEGS do
		local offset = (k + rng:NextNumber(0.7, 0.85)) * spacing
		if math.abs(offset) <= slice * 0.35 then
			table.insert(offsets, offset)
		end
	end
	local offset = if #offsets > 0 then offsets[rng:NextInteger(1, #offsets)] else 0
	return (index - 1) * slice + offset
end

local function setStatus(text: string)
	local wheel = WorldService.wheel
	if wheel then
		wheel.status.Text = text
	end
	state:SetAttribute("Queue", #queue)
end

local function spinningText(): string
	local name = if current then current.player.DisplayName else "Someone"
	local line = if #queue > 0 then `  ·  {#queue} in line` else ""
	return `<b>{name}</b> is spinning…{line}`
end

local function entryOf(player: Player): (Entry?, number?)
	if current and current.player == player then
		return current, 0
	end
	for place, entry in queue do
		if entry.player == player then
			return entry, place
		end
	end
	return nil, nil
end

-- A Rare-or-better skin from the line of the fish the player swims as (the jackpot)
local function rollSkin(data: PlayerData, minTier: string): string?
	local floor = Tiers.byId[minTier]
	local species = Progress.speciesId(data)
	local owned = Progress.shades(data)
	local pool = {}
	local total = 0
	for _, shade in Config.Shades.list do
		local tier = Tiers.byId[shade.tier]
		if
			Config.Shades.rollable(shade)
			and shade.species == species
			and not owned[shade.id]
			and tier
			and floor
			and tier.order >= floor.order
		then
			table.insert(pool, shade)
			total += 1 / shade.chance
		end
	end
	local pick = rng:NextNumber() * total
	for _, shade in pool do
		pick -= 1 / shade.chance
		if pick <= 0 then
			return shade.id
		end
	end
	return if #pool > 0 then pool[#pool].id else nil
end

-- What the spin pays, worked out when it starts so the clients can show it as the
-- wheel stops
local function prepare(data: PlayerData, index: number): Prize
	local segment = Wheel.segments[index]
	if segment.kind == "coral" then
		return { index = index, amount = segment.value, detail = `+{Format.number(segment.value)} coral` }
	elseif segment.kind == "shells" then
		return { index = index, amount = segment.value, detail = `+{segment.value} shells` }
	elseif segment.kind == "wraps" then
		return { index = index, amount = segment.value, detail = `+{segment.value} Kelp Wraps` }
	elseif segment.kind == "charm" then
		local charm = Config.Shop.charmsById[segment.charm or ""]
		local name = if charm then charm.name else "a charm"
		return {
			index = index,
			amount = 1,
			detail = `{name}{if charm and charm.seconds then ": on now" else ""}`,
		}
	elseif segment.kind == "map" then
		local tier = Config.Treasure.byId[segment.map or ""]
		return { index = index, amount = 1, detail = `A {if tier then tier.name else ""} treasure map` }
	elseif segment.kind == "skin" then
		local skin = rollSkin(data, segment.minTier or "Rare")
		if skin == nil then
			return {
				index = index,
				amount = Wheel.jackpotCoral,
				detail = `Your fish has every rare skin: +{Format.number(Wheel.jackpotCoral)} coral`,
			}
		end
		local shade = Config.Shades.byId[skin]
		return {
			index = index,
			amount = 1,
			detail = `The {shade.name} skin ({shade.tier}) for your {Progress.species(data).name}!`,
			skin = skin,
		}
	end
	return { index = index, amount = segment.value, detail = `+{segment.value} spins` }
end

local function award(player: Player, prize: Prize)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local segment = Wheel.segments[prize.index]
	if segment.kind == "coral" then
		EconomyService.addCoral(player, prize.amount)
	elseif segment.kind == "shells" then
		EconomyService.addShells(player, prize.amount)
	elseif segment.kind == "wraps" then
		HuntService.giveWrap(player, prize.amount)
	elseif segment.kind == "charm" then
		local charm = Config.Shop.charmsById[segment.charm or ""]
		if charm and charm.seconds then
			local now = Timing.now()
			data.boosts[charm.id] = math.max(data.boosts[charm.id] or 0, now) + charm.seconds
			WardrobeService.refresh(player)
		elseif charm then
			data.charms[charm.id] = (data.charms[charm.id] or 0) + 1
		end
	elseif segment.kind == "map" then
		if not TreasureService.give(player, segment.map or "Weathered") then
			EconomyService.addCoral(player, 500)
			Net.notify(player, "Your satchel was full: 500 coral instead", "info")
		end
	elseif segment.kind == "skin" then
		if prize.skin then
			Progress.grantShade(data, prize.skin)
			local shade = Config.Shades.byId[prize.skin]
			Net.notifyAll(
				`{player.DisplayName} hit the JACKPOT on the Treasure Wheel: the {shade.name} skin!`,
				"rare"
			)
		else
			EconomyService.addCoral(player, prize.amount)
		end
	elseif segment.kind == "spins" then
		data.wheel.spins += prize.amount
	end
	DataService.markDirty(player)
end

local startNext: () -> ()

-- Pays the entry's prize once (at the end of its spin, or as its player leaves).
local function payOut(entry: Entry)
	local prize = entry.prize
	if prize and not entry.paid then
		entry.paid = true
		award(entry.player, prize)
	end
end

local function settle(entry: Entry, prize: Prize, to: number)
	local wheel = WorldService.wheel
	local player = entry.player
	state:SetAttribute("Angle", to % 360)
	if wheel then
		wheel.disc:PivotTo(wheel.base * CFrame.Angles(0, 0, math.rad(to)))
	end
	local data = DataService.get(player)
	if player.Parent and data then
		payOut(entry)
	end
	local segment = Wheel.segments[prize.index]
	-- Spin all: back of the line while spins last, unless it just won the jackpot
	if entry.auto and player.Parent and data then
		if segment.kind == "skin" then
			entry.auto = false
			Net.notify(
				player,
				if data.wheel.spins > 0
					then "Spin all paused: you hit the jackpot!"
					else "Spin all done, on the jackpot!",
				"rare"
			)
		elseif data.wheel.spins > 0 then
			table.insert(queue, entry)
		else
			Net.notify(player, "Spin all done: you're out of spins.", "info")
		end
	end
	setStatus(
		`<font color="#{segment.color:ToHex()}"><b>{player.DisplayName}</b> won {segment.label}!</font>`
	)
end

local function finish(entry: Entry, prize: Prize, to: number, id: number)
	-- Whatever goes wrong paying out, the wheel must free up for the next in line
	Guard.run("WheelService.finish", settle, entry, prize, to)
	current = nil
	resting = true
	task.delay(RESULT_SECONDS, function()
		resting = false
		startNext()
	end)
	task.delay(IDLE_SECONDS, function()
		if current == nil and #queue == 0 and spinCount == id then
			setStatus(IDLE_TEXT)
		end
	end)
end

-- Starts this entry's spin; false if it can't (left, or out of spins).
local function begin(entry: Entry): boolean
	local wheel = WorldService.wheel
	local player = entry.player
	local data = DataService.get(player)
	if wheel == nil or data == nil or player.Parent == nil or data.wheel.spins <= 0 then
		return false
	end
	data.wheel.spins -= 1
	DataService.markDirty(player)
	current = entry

	local index = rigged[player] or pickSegment()
	rigged[player] = nil
	local prize = prepare(data, index)
	entry.prize = prize
	entry.paid = false
	local from = (state:GetAttribute("Angle") :: number) % 360
	-- Five to six full turns, ending on the prize
	local to = 6 * 360 + landingAngle(index)
	spinCount += 1
	local id = spinCount
	state:SetAttribute("SpinFrom", from)
	state:SetAttribute("SpinTo", to)
	state:SetAttribute("SpinDuration", SPIN_SECONDS)
	state:SetAttribute("SpinStart", Workspace:GetServerTimeNow())
	state:SetAttribute("SpinIndex", index)
	state:SetAttribute("SpinnerUserId", player.UserId)
	state:SetAttribute("SpinnerName", player.DisplayName)
	state:SetAttribute("SpinDetail", prize.detail)
	state:SetAttribute("SpinId", id) -- last: clients read the whole spin when this changes
	setStatus(spinningText())

	task.delay(SPIN_SECONDS + SETTLE_SECONDS, finish, entry, prize, to, id)
	return true
end

startNext = function()
	if current or resting then
		return
	end
	while #queue > 0 do
		local entry = table.remove(queue, 1) :: Entry
		local started = false
		Guard.run("WheelService.begin", function()
			started = begin(entry)
		end)
		if started then
			return
		end
		current = nil -- it failed part-way: don't leave the wheel held
	end
	state:SetAttribute("Queue", 0)
end

local function nextFreeText(data: PlayerData): string
	local seconds = math.max(0, math.ceil(data.wheel.lastFree + Wheel.freeEvery - Timing.now()))
	return Format.duration(seconds)
end

-- Whether the player is at the big red button (the hint shows there)
local function atButton(player: Player): boolean
	local wheel = WorldService.wheel
	local _, root = FishService.character(player)
	return wheel ~= nil
		and root ~= nil
		and (root.Position - wheel.button.Position).Magnitude <= Wheel.reach + 6
end

local function request(player: Player, auto: any)
	local data = DataService.get(player)
	if data == nil or not atButton(player) then
		return
	end
	auto = auto == true
	accrue(data, Timing.now())
	local entry, place = entryOf(player)
	if entry then
		if auto then
			entry.auto = not entry.auto
			Net.notify(
				player,
				if entry.auto
					then "Spin all on: you'll keep spinning until your spins run out."
					else "Spin all off.",
				"info"
			)
		elseif place == 0 then
			Net.notify(player, "Your spin is turning!", "info")
		else
			Net.notify(player, `You're #{place} in line for the wheel.`, "info")
		end
		return
	end
	if data.wheel.spins <= 0 then
		Net.notify(
			player,
			`No spins left. The next free one comes in {nextFreeText(data)} (the Bounty Chest and the Catch of the Week give more).`,
			"bad"
		)
		return
	end
	table.insert(queue, { player = player, auto = auto })
	if current then
		Net.notify(player, `You're #{#queue} in line: the wheel is turning.`, "info")
		setStatus(spinningText())
	else
		startNext()
	end
end

function WheelService.start()
	state = Instance.new("Folder")
	state.Name = "WheelState"
	state:SetAttribute("Angle", 0)
	state:SetAttribute("SpinId", 0)
	state:SetAttribute("Queue", 0)
	local wheel = WorldService.wheel
	if wheel then
		state:SetAttribute("ButtonPosition", wheel.button.Position)
		wheel.status.Text = IDLE_TEXT
	end
	state.Parent = ReplicatedStorage

	-- Leaving mid-spin still pays (the spin was already spent)
	DataService.releasing:connect(function(player: Player)
		local spinning = current
		if spinning and spinning.player == player then
			Guard.run("WheelService.leave", payOut, spinning)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		rigged[player] = nil
		for i = #queue, 1, -1 do
			if queue[i].player == player then
				table.remove(queue, i)
			end
		end
		state:SetAttribute("Queue", #queue)
	end)
	DataService.loaded:connect(function(player: Player, data: PlayerData)
		if accrue(data, Timing.now()) then
			DataService.markDirty(player)
		end
	end)
	-- Free spins come in while someone's online too
	Guard.loop("WheelService.free", 30, function()
		local now = Timing.now()
		for player, data in DataService.loadedPlayers() do
			local before = data.wheel.spins
			if accrue(data, now) then
				DataService.markDirty(player)
				if before == 0 then
					Net.notify(player, "A free spin is ready at the Treasure Wheel!", "good")
				end
			end
		end
	end)
	Net.onRequest("SpinWheel", request)
	StateService.provide(function(_player, data, state_)
		local full = data.wheel.spins >= Wheel.maxFree
		state_.wheel = {
			spins = data.wheel.spins,
			-- When the next free spin comes (0 while the free ones are full)
			nextFreeAt = if full then 0 else data.wheel.lastFree + Wheel.freeEvery,
		}
	end)
end

return WheelService
