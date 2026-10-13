--!strict
-- Den bases (Config/Dens, GDD §6): each player's den record (level, glow, floor, the
-- things they own and where they've placed them) lives in their save and is built
-- into whichever den they hold this server (DenBuilder). Upgrades, things, glows and
-- floors cost coral; only the den's owner can change it (visitors can swim in and
-- look). Things are placed freely in Build mode (BuildController): the client aims
-- and asks, and this checks every request against the den's space (DenSpace) before
-- it's saved. The trophy wall fills itself from the player's stats and trophies.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DenSpace = require(ReplicatedStorage.Shared.DenSpace)
local Garden = require(ReplicatedStorage.Shared.Garden)
local DenBuilder = require(script.Parent.Parent.DenBuilder)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local MonetizationService = require(script.Parent.MonetizationService)
local StateService = require(script.Parent.StateService)
local WorldService = require(script.Parent.WorldService)

local Dens = Config.Dens

local DenService = {}

type DenRecord = typeof(({} :: DataService.PlayerData).den)
type Placement = DenBuilder.Placement

local function fail(player: Player, text: string)
	Net.notify(player, text, "bad")
end

local function trophiesOf(player: Player, data: DataService.PlayerData): DenBuilder.Trophies
	return {
		bestPrey = data.stats.bestPrey,
		bestPreyMass = data.stats.bestPreyMass,
		teeth = data.trophies.MegalodonTeeth or 0,
		beaks = data.trophies.KrakenBeaks or 0,
		title = data.title,
		owner = player.DisplayName,
	}
end

local function capacityOf(player: Player, den: DenRecord): number
	return DenSpace.capacity(den.level, MonetizationService.hasPass(player, "DenExpansion"))
end

local function placedOf(den: DenRecord, itemId: string): number
	local count = 0
	for _, placement in den.placed do
		if placement.id == itemId then
			count += 1
		end
	end
	return count
end

-- Copies of a thing in the tray (owned, not placed)
local function inTray(den: DenRecord, itemId: string): number
	return (den.items[itemId] or 0) - placedOf(den, itemId)
end

-- The first placement of a thing that may stand at (x, y, z), or nil
local function snap(n: number): number
	return math.floor(n * 100 + 0.5) / 100
end

-- Saves from before Build mode (2026-10-13): things bought then (kept in `owned`)
-- become one copy each in the tray, and things in the old slots are placed where
-- those slots were, or on the nearest free spot of the same floor, or left in the
-- tray. Runs once: it empties what it moves.
local OLD_SLOTS: { [string]: { surface: string, at: Vector3 } } = {
	A1 = { surface = "floor", at = Vector3.new(-7, 0, -4) },
	A2 = { surface = "floor", at = Vector3.new(7, 0, -4) },
	A3 = { surface = "floor", at = Vector3.new(-7, 0, 6) },
	A4 = { surface = "floor", at = Vector3.new(7, 0, 6) },
	W1 = { surface = "wall", at = Vector3.new(-11.5, 9, 0) },
	W2 = { surface = "wall", at = Vector3.new(11.5, 9, 0) },
	W3 = { surface = "wall", at = Vector3.new(-10.5, 9, -24) },
	W4 = { surface = "wall", at = Vector3.new(10.5, 9, -24) },
	P1 = { surface = "floor", at = Vector3.new(-5, -34, 2) },
	P2 = { surface = "floor", at = Vector3.new(5, -34, 2) },
	P3 = { surface = "floor", at = Vector3.new(0, -34, -5) },
	P4 = { surface = "floor", at = Vector3.new(0, -34, 6) },
	X1 = { surface = "floor", at = Vector3.new(-8, 0, -12) },
	X2 = { surface = "floor", at = Vector3.new(8, 0, -12) },
	X3 = { surface = "wall", at = Vector3.new(-11.5, 8, 6) },
	X4 = { surface = "wall", at = Vector3.new(11.5, 8, 6) },
}

local function migrate(den: DenRecord)
	for id, has in den.owned do
		if Dens.itemsById[id] and has == true then
			den.items[id] = math.max(den.items[id] or 0, 1)
			den.owned[id] = nil
		end
	end
	if next(den.furniture) == nil then
		return
	end
	for slotId, itemId in den.furniture do
		local slot = OLD_SLOTS[slotId]
		local item = Dens.itemsById[itemId]
		if slot == nil or item == nil then
			continue
		end
		-- The old system let one bought thing stand in several slots: keep them all
		den.items[itemId] = math.max(den.items[itemId] or 0, placedOf(den, itemId) + 1)
		local surface = if table.find(item.kinds, slot.surface) then slot.surface else item.kinds[1]
		local at = slot.at
		if surface == "floor" then
			local storey = DenSpace.storeyAt(at.Y) or 1
			at = Vector3.new(at.X, DenSpace.storey(storey).deck, at.Z)
			if not DenSpace.check(den.level, item, "floor", at).ok then
				-- The nearest free spot of that floor, in rings out from the old one
				local found: Vector3? = nil
				for ring = 1, 12 do
					for i = 0, ring * 8 - 1 do
						local a = i / (ring * 8) * 2 * math.pi
						local try = at + Vector3.new(math.cos(a), 0, math.sin(a)) * ring * 1.5
						if DenSpace.check(den.level, item, "floor", try).ok then
							found = try
							break
						end
					end
					if found then
						break
					end
				end
				if found == nil then
					continue
				end
				at = found
			end
		elseif not DenSpace.check(den.level, item, surface, at).ok then
			continue
		end
		-- A wall thing looks into the room, away from its side of the room
		local yaw = if surface == "wall" then (if at.X < 0 then -90 else 90) else 0
		table.insert(den.placed, {
			uid = den.nextUid,
			id = itemId,
			x = snap(at.X),
			y = snap(at.Y),
			z = snap(at.Z),
			r = yaw,
			s = surface,
		})
		den.nextUid += 1
	end
	table.clear(den.furniture)
end

local function recordOf(den: DenRecord): DenBuilder.Record
	return { level = den.level, glow = den.glow, floor = den.floor, placed = den.placed }
end

-- Builds the player's den as their record says
function DenService.refresh(player: Player)
	local data = DataService.get(player)
	local den = FishService.denOf(player)
	if data == nil or den == nil then
		return
	end
	migrate(data.den)
	Guard.run("DenService.build", function()
		local rates = Garden.rates(
			data.den.level,
			MonetizationService.hasPass(player, "DeepGarden"),
			if MonetizationService.isPremium(player)
				then Config.Monetization.tuning.premium.gardenHours
				else 0
		)
		local shellFill = if rates.capShells > 0 then data.garden.shells / rates.capShells else 0
		DenBuilder.build(
			den,
			recordOf(data.den),
			trophiesOf(player, data),
			Garden.fill(data.garden, rates),
			shellFill
		)
		local level = Dens.levels[data.den.level] or Dens.levels[1]
		WorldService.setDenLevel(den, level.name)
	end)
end

-- The player's record and the den they hold, when they can change it
local function mine(player: Player): (DataService.PlayerData?, number?)
	local data = DataService.get(player)
	local den = FishService.denOf(player)
	if data == nil or den == nil then
		return nil, nil
	end
	return data, den
end

-- Things changed: rebuild just them, save, and tell the client
local function placedChanged(player: Player, data: DataService.PlayerData, den: number)
	Guard.run("DenService.items", function()
		DenBuilder.items(den, recordOf(data.den))
	end)
	DataService.markDirty(player)
	Events.denChanged:fire(player, "place")
end

local function upgrade(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local next = Dens.levels[data.den.level + 1]
	if next == nil then
		local top = Dens.levels[#Dens.levels]
		return fail(player, `Your den is already a {top.name}`)
	end
	if not EconomyService.spendCoral(player, next.cost) then
		return fail(player, `Not enough coral ({next.cost} needed)`)
	end
	data.den.level = next.level
	DataService.markDirty(player)
	Net.notify(player, `Your den is a {next.name} now`, "good")
	DenService.refresh(player)
	Events.denChanged:fire(player, "upgrade")
end

local function buy(player: Player, itemId: any)
	local data = DataService.get(player)
	local item = if typeof(itemId) == "string" then Dens.itemsById[itemId] else nil
	if data == nil or item == nil then
		return
	end
	if not EconomyService.spendCoral(player, item.price) then
		return fail(player, `Not enough coral ({item.price} needed)`)
	end
	data.den.items[item.id] = (data.den.items[item.id] or 0) + 1
	DataService.markDirty(player)
	Net.notify(player, `Bought a {item.name} · it's in your Build tray`, "good")
end

-- A place a thing is asked to go: every number finite and in range
local function readSpot(surface: any, x: any, y: any, z: any, yaw: any): (string?, Vector3?, number?)
	if
		typeof(surface) ~= "string" or not (surface == "floor" or surface == "wall" or surface == "ceiling")
	then
		return nil, nil, nil
	end
	for _, n in { x, y, z, yaw } do
		if typeof(n) ~= "number" or n ~= n or math.abs(n) > 400 then
			return nil, nil, nil
		end
	end
	return surface, Vector3.new(snap(x), snap(y), snap(z)), snap(yaw % 360)
end

local function place(player: Player, itemId: any, surface: any, x: any, y: any, z: any, yaw: any)
	local data, den = mine(player)
	local item = if typeof(itemId) == "string" then Dens.itemsById[itemId] else nil
	local face, at, turn = readSpot(surface, x, y, z, yaw)
	if data == nil or den == nil or item == nil or face == nil or at == nil or turn == nil then
		return
	end
	local record = data.den
	if inTray(record, item.id) <= 0 then
		return fail(player, `No {item.name} left in your tray`)
	end
	if #record.placed >= capacityOf(player, record) then
		return fail(player, `Your den holds {capacityOf(player, record)} things · upgrade it for more`)
	end
	local check = DenSpace.check(record.level, item, face, at)
	if not check.ok then
		return fail(player, check.why or "That doesn't go there")
	end
	table.insert(
		record.placed,
		{ uid = record.nextUid, id = item.id, x = at.X, y = at.Y, z = at.Z, r = turn, s = face }
	)
	record.nextUid += 1
	placedChanged(player, data, den)
end

local function find(record: DenRecord, uid: any): (number?, Placement?)
	if typeof(uid) ~= "number" then
		return nil, nil
	end
	for i, placement in record.placed do
		if placement.uid == uid then
			return i, placement
		end
	end
	return nil, nil
end

local function move(player: Player, uid: any, surface: any, x: any, y: any, z: any, yaw: any)
	local data, den = mine(player)
	local face, at, turn = readSpot(surface, x, y, z, yaw)
	if data == nil or den == nil or face == nil or at == nil or turn == nil then
		return
	end
	local _, placement = find(data.den, uid)
	local item = if placement then Dens.itemsById[placement.id] else nil
	if placement == nil or item == nil then
		return
	end
	local check = DenSpace.check(data.den.level, item, face, at)
	if not check.ok then
		return fail(player, check.why or "That doesn't go there")
	end
	placement.x, placement.y, placement.z, placement.r, placement.s = at.X, at.Y, at.Z, turn, face
	placedChanged(player, data, den)
end

local function store(player: Player, uid: any)
	local data, den = mine(player)
	if data == nil or den == nil then
		return
	end
	if uid == 0 then
		table.clear(data.den.placed)
		Net.notify(player, "Everything's back in your tray", "good")
	else
		local i = find(data.den, uid)
		if i == nil then
			return
		end
		table.remove(data.den.placed, i)
	end
	placedChanged(player, data, den)
end

local function color(player: Player, glowId: any)
	local data = DataService.get(player)
	if data == nil or typeof(glowId) ~= "string" then
		return
	end
	local glow = Dens.glowsById[glowId]
	if glow == nil then
		return
	end
	if glow.price > 0 and not data.den.owned[`Glow:{glow.id}`] then
		if not EconomyService.spendCoral(player, glow.price) then
			return fail(player, `Not enough coral ({glow.price} needed)`)
		end
		data.den.owned[`Glow:{glow.id}`] = true
	end
	data.den.glow = glow.id
	DataService.markDirty(player)
	DenService.refresh(player)
end

local function floor(player: Player, floorId: any)
	local data = DataService.get(player)
	local style = if typeof(floorId) == "string" then Dens.floorsById[floorId] else nil
	if data == nil or style == nil then
		return
	end
	if style.price > 0 and not data.den.owned[`Floor:{style.id}`] then
		if not EconomyService.spendCoral(player, style.price) then
			return fail(player, `Not enough coral ({style.price} needed)`)
		end
		data.den.owned[`Floor:{style.id}`] = true
		Net.notify(player, `{style.name} laid in your den`, "good")
	end
	data.den.floor = style.id
	DataService.markDirty(player)
	DenService.refresh(player)
end

-- Admin testing: the den at a level, and some of every thing in the tray
function DenService.setLevel(player: Player, level: number)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	data.den.level = math.clamp(math.floor(level), 1, #Dens.levels)
	-- Things that no longer fit a smaller den go back to the tray
	for i = #data.den.placed, 1, -1 do
		local placement = data.den.placed[i]
		local item = Dens.itemsById[placement.id]
		local at = Vector3.new(placement.x, placement.y, placement.z)
		if item == nil or not DenSpace.check(data.den.level, item, placement.s, at).ok then
			table.remove(data.den.placed, i)
		end
	end
	DataService.markDirty(player)
	DenService.refresh(player)
end

function DenService.giveItems(player: Player, count: number)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	for _, item in Dens.items do
		data.den.items[item.id] = (data.den.items[item.id] or 0) + count
	end
	DataService.markDirty(player)
end

function DenService.start()
	DataService.loaded:connect(function(_player: Player, data: DataService.PlayerData)
		migrate(data.den)
	end)
	FishService.denAssigned:connect(function(player: Player, _index: number)
		DenService.refresh(player)
	end)
	FishService.denFreed:connect(function(index: number)
		Guard.run("DenService.clear", function()
			DenBuilder.clear(index, true)
			WorldService.setDenLevel(index, nil)
		end)
	end)
	Events.trophies:connect(function(player: Player)
		DenService.refresh(player)
	end)
	-- A pass's room (Den Expansion) and garden (Deep Garden) show at once
	MonetizationService.passAdded:connect(function(player: Player, key: string)
		if key == "DenExpansion" or key == "DeepGarden" then
			DenService.refresh(player)
			DataService.markDirty(player)
		end
	end)
	Net.onRequest("DenUpgrade", upgrade)
	Net.onRequest("DenBuy", buy)
	Net.onRequest("DenPlace", place)
	Net.onRequest("DenMove", move)
	Net.onRequest("DenStore", store)
	Net.onRequest("DenColor", color)
	Net.onRequest("DenFloor", floor)
	StateService.provide(function(player, data, state)
		state.den = data.den
		state.denIndex = FishService.denOf(player) or 0
		state.denCapacity = capacityOf(player, data.den)
	end)
end

return DenService
