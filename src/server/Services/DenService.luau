--!strict
-- Den bases (Config/Dens, GDD §6): each player's den record (level, glow, floor, the
-- things they own and where they've placed them) lives in their save and is built
-- into whichever den they hold this server (DenBuilder). Upgrades, things, glows and
-- floors cost coral; only the den's owner can change it (visitors can swim in and
-- look). Things are placed freely in Build mode (BuildController): the client aims
-- and asks, and this checks every request against the den's space (DenSpace) before
-- it's saved. The trophy wall fills itself from the player's stats and trophies.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DensConfig = require(ReplicatedStorage.Shared.Config.Dens)
local DenSpace = require(ReplicatedStorage.Shared.DenSpace)
local Garden = require(ReplicatedStorage.Shared.Garden)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Size = require(ReplicatedStorage.Shared.Size)
local DenBuilder = require(script.Parent.Parent.DenBuilder)
local DenWings = require(script.Parent.Parent.DenWings)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local AchievementService = require(script.Parent.AchievementService)
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

-- A den record's shape (Shared/DenSpace): its level, wings and Open Plan
local function shapeOf(den: DenRecord): DenSpace.Shape
	return {
		level = den.level,
		wings = if typeof(den.wings) == "table" then den.wings else nil,
		open = den.open == true,
	}
end

local function fail(player: Player, text: string)
	Net.notify(player, text, "bad")
end

local function trophiesOf(player: Player, data: DataService.PlayerData): DenBuilder.Trophies
	-- The Trophy Gallery's records: the heaviest catch overall and at each rarity
	-- (the Catch Log's biggest, CatchService)
	local biggest: DenWings.Catch? = nil
	local byRarity: { [string]: DenWings.Catch } = {}
	for prey, best in data.catchBest do
		if Config.Prey.byId[prey] == nil or typeof(best) ~= "table" then
			continue
		end
		for rarity, kg in best do
			if typeof(kg) ~= "number" then
				continue
			end
			local have = byRarity[rarity]
			if have == nil or kg > have.kg then
				byRarity[rarity] = { prey = prey, rarity = rarity, kg = kg }
			end
			if biggest == nil or kg > biggest.kg then
				biggest = { prey = prey, rarity = rarity, kg = kg }
			end
		end
	end
	local teeth = data.trophies.MegalodonTeeth or 0
	local beaks = data.trophies.KrakenBeaks or 0
	return {
		bestPrey = data.stats.bestPrey,
		bestPreyMass = data.stats.bestPreyMass,
		teeth = teeth,
		beaks = beaks,
		title = data.title,
		owner = player.DisplayName,
		gallery = { biggest = biggest, byRarity = byRarity, teeth = teeth, beaks = beaks, title = data.title },
	}
end

local function capacityOf(player: Player, den: DenRecord): number
	return DenSpace.capacity(shapeOf(den), MonetizationService.hasPass(player, "DenExpansion"))
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

-- Placements made before the private interiors (owner, 2026-10-16): the main
-- storey kept its height, but the lower storeys' decks went down from -34 and -70
-- to -54 and -114. Each thing moves with its storey.
local OLD_DECKS = { 1, -34, -70 }

local function relayout(den: DenRecord)
	local mark = den.layout or 2
	if mark >= Dens.layout.current then
		return
	end
	den.layout = Dens.layout.current
	if mark < 3 then
		for _, placement in den.placed do
			local old = if placement.y >= -8 then 1 elseif placement.y >= -52 then 2 else 3
			placement.y += DenSpace.storey(old).deck - OLD_DECKS[old]
		end
	end
	if mark < 4 then
		-- the bigger rooms and things of 2026-10-18 (DenSpace.grow)
		DenSpace.grow(shapeOf(den), den.placed, Dens.layout.growth)
	end
	-- Anything that no longer fits goes back to the tray
	for _ = 1, 3 do
		local kept = {}
		for _, placement in den.placed do
			local item = Dens.itemsById[placement.id]
			local at = Vector3.new(placement.x, placement.y, placement.z)
			local fits = item ~= nil and DenSpace.check(shapeOf(den), item, placement.s, at).ok
			if fits and placement.s == "floor" then
				fits = DenSpace.resting(shapeOf(den), den.placed, at, placement.uid).ok
			end
			if fits then
				table.insert(kept, placement)
			end
		end
		if #kept == #den.placed then
			break
		end
		den.placed = kept
	end
end

local function migrate(den: DenRecord)
	-- (a save from before the doorway styles)
	if typeof(den.door) ~= "string" or Dens.doorsById[den.door] == nil then
		den.door = "Stone"
	end
	if typeof(den.doors) ~= "table" then
		den.doors = {}
	end
	relayout(den)
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
			if not DenSpace.check(shapeOf(den), item, "floor", at).ok then
				-- The nearest free spot of that floor, in rings out from the old one
				local found: Vector3? = nil
				for ring = 1, 12 do
					for i = 0, ring * 8 - 1 do
						local a = i / (ring * 8) * 2 * math.pi
						local try = at + Vector3.new(math.cos(a), 0, math.sin(a)) * ring * 1.5
						if DenSpace.check(shapeOf(den), item, "floor", try).ok then
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
		elseif not DenSpace.check(shapeOf(den), item, surface, at).ok then
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
	local shape = shapeOf(den)
	return {
		level = den.level,
		glow = den.glow,
		floor = den.floor,
		placed = den.placed,
		wings = shape.wings,
		open = shape.open,
		tanks = if typeof(den.tanks) == "table" then den.tanks else nil,
	}
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
		WorldService.setDenDoor(den, data.den.door)
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
	-- Whatever was stacked on a thing that moved or went away comes down with it
	-- (or back to the tray)
	local fell = DenSpace.settle(shapeOf(data.den), data.den.placed)
	if #fell > 0 then
		for i = #data.den.placed, 1, -1 do
			if table.find(fell, data.den.placed[i].uid) then
				table.remove(data.den.placed, i)
			end
		end
		Net.notify(
			player,
			`{#fell} thing{if #fell == 1 then "" else "s"} that stood on it went back to your tray`,
			"info"
		)
	end
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
	-- A set's pieces sell once its achievement is done (Config/Achievements)
	if item.set and not AchievementService.setOpen(data, item.set) then
		local achievement = Config.Achievements.bySet[item.set]
		local set = Dens.setsById[item.set]
		return fail(
			player,
			`The {if set then set.name else "set"} set opens with {if achievement
				then `{achievement.name}: {achievement.blurb}`
				else "an achievement"}`
		)
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
	local check = DenSpace.check(shapeOf(record), item, face, at)
	if check.ok and face == "floor" then
		check = DenSpace.resting(shapeOf(record), record.placed, at)
	end
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

-- A set's starter layout (Config/Dens `layouts`) laid out round a spot: every piece
-- of it you have in the tray (up to the den's room for things), fitted on the floor
-- by DenSpace.fitLayout. `facing` turns its front toward the camera.
local function layout(player: Player, setId: any, x: any, y: any, z: any, facing: any)
	local data, den = mine(player)
	local pieces = if typeof(setId) == "string" then Dens.layouts[setId] else nil
	local _, at, turn = readSpot("floor", x, y, z, facing)
	if data == nil or den == nil or pieces == nil or at == nil or turn == nil then
		return
	end
	local record = data.den
	local room = capacityOf(player, record) - #record.placed
	local have: { [string]: number } = {}
	local chosen: { DensConfig.LayoutPiece } = {}
	for _, piece in pieces do
		have[piece.id] = have[piece.id] or inTray(record, piece.id)
		if have[piece.id] > 0 and #chosen < room then
			have[piece.id] -= 1
			table.insert(chosen, piece)
		end
	end
	local set = Dens.setsById[setId]
	local name = if set then set.name else "set"
	if #chosen == 0 then
		if room <= 0 then
			return fail(player, `Your den holds {capacityOf(player, record)} things · upgrade it for more`)
		end
		return fail(player, `No {name} floor pieces in your tray`)
	end
	local fit, why = DenSpace.fitLayout(shapeOf(record), record.placed, chosen, at, turn)
	if fit == nil then
		return fail(player, why or "Not enough open floor here")
	end
	for _, spot in fit do
		table.insert(record.placed, {
			uid = record.nextUid,
			id = spot.id,
			x = snap(spot.x),
			y = snap(spot.y),
			z = snap(spot.z),
			r = snap(spot.r % 360),
			s = "floor",
		})
		record.nextUid += 1
	end
	placedChanged(player, data, den)
	Net.notify(
		player,
		`Laid out {#fit} {name} piece{if #fit == 1 then "" else "s"} · move any of them as you like`,
		"good"
	)
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
	local check = DenSpace.check(shapeOf(data.den), item, face, at)
	if check.ok and face == "floor" then
		check = DenSpace.resting(shapeOf(data.den), data.den.placed, at, placement.uid)
	end
	if not check.ok then
		return fail(player, check.why or "That doesn't go there")
	end
	-- What's stacked on it comes along, turned with it (PC 2026-10-16 round 2, B4);
	-- a carried thing that can't stand at its new spot goes back to the tray
	local from = { x = placement.x, y = placement.y, z = placement.z, r = placement.r }
	local to = { x = at.X, y = at.Y, z = at.Z, r = turn }
	local stack: { DenSpace.Placed } = {}
	if face == "floor" and placement.s == "floor" then
		stack = DenSpace.stackOn(data.den.placed, placement.uid)
	end
	placement.x, placement.y, placement.z, placement.r, placement.s = at.X, at.Y, at.Z, turn, face
	local dropped = 0
	for _, carried in stack do
		carried.x, carried.y, carried.z, carried.r = DenSpace.carry(carried, from, to)
		local carriedItem = Dens.itemsById[carried.id]
		local fits = carriedItem ~= nil
			and DenSpace.check(
				shapeOf(data.den),
				carriedItem,
				"floor",
				Vector3.new(carried.x, carried.y, carried.z)
			).ok
		if not fits then
			local i = find(data.den, carried.uid)
			if i then
				table.remove(data.den.placed, i)
				dropped += 1
			end
		end
	end
	if dropped > 0 then
		Net.notify(
			player,
			`{dropped} thing{if dropped == 1 then "" else "s"} stacked on it didn't fit there · back in your tray`,
			"info"
		)
	end
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

-- Why a doorway style can't be bought yet (nil: it can)
function DenService.doorLocked(data: DataService.PlayerData, style: DensConfig.Door): string?
	if style.level and data.den.level < style.level then
		local level = Dens.levels[style.level]
		return `The {style.name} needs a {if level then level.name else "bigger"} den`
	end
	if style.achievement and data.achievements[style.achievement] ~= true then
		local achievement = Config.Achievements.byId[style.achievement]
		return `The {style.name} opens with {if achievement
			then `{achievement.name}: {achievement.blurb}`
			else "an achievement"}`
	end
	return nil
end

-- A doorway style for the den's front door on the plaza (owner, 2026-10-18): bought
-- once with coral (at its den level, after its achievement), then worn or swapped
local function door(player: Player, doorId: any)
	local data = DataService.get(player)
	local style = if typeof(doorId) == "string" then Dens.doorsById[doorId] else nil
	if data == nil or style == nil then
		return
	end
	local den = data.den
	if typeof(den.doors) ~= "table" then
		den.doors = {}
	end
	if style.price > 0 and den.doors[style.id] ~= true then
		local locked = DenService.doorLocked(data, style)
		if locked then
			return fail(player, locked)
		end
		if not EconomyService.spendCoral(player, style.price) then
			return fail(player, `Not enough coral ({style.price} needed)`)
		end
		den.doors[style.id] = true
		Net.notify(player, `The {style.name} is on your den's doorway`, "good")
	end
	den.door = style.id
	DataService.markDirty(player)
	DenService.refresh(player)
end

-- After the den's shape changes (a wing built or taken down, Open Plan switched),
-- what's placed is brought along: things in a wing move with it when Open Plan moves
-- the side walls it opens from, the house's wall and ceiling things go back to the
-- tray when its walls moved, and anything else that no longer fits does too (a wing
-- taken down, a wall thing where a passage was cut). Fish in the den are moved over
-- the pool, out of the rock being carved. Returns how many went to the tray.
local function reshape(player: Player, data: DataService.PlayerData, before: DenSpace.Shape): number
	local den = data.den
	local after = shapeOf(den)
	local wallsMoved = (before.open == true) ~= (after.open == true)
	local oldPlans: { [string]: DenSpace.WingPlan } = {}
	for _, plan in DenSpace.wingPlans(before) do
		oldPlans[plan.slot.id] = plan
	end
	local newPlans: { [string]: DenSpace.WingPlan } = {}
	for _, plan in DenSpace.wingPlans(after) do
		newPlans[plan.slot.id] = plan
	end
	local kept = {}
	for _, placement in den.placed do
		local item = Dens.itemsById[placement.id]
		if item == nil then
			continue
		end
		-- Which wing it stood in (passage or room), if any
		local inWing: string? = nil
		for slotId, plan in oldPlans do
			if
				DenSpace.inRoom(plan.room, placement.x, placement.z, 1)
				or DenSpace.inRoom(plan.passage, placement.x, placement.z, 1)
			then
				inWing = slotId
			end
		end
		if inWing then
			local was, now = oldPlans[inWing], newPlans[inWing]
			if now and was.def.id == now.def.id then
				placement.x = snap(placement.x + now.side * (now.x1 - was.x1))
			end
		elseif wallsMoved and placement.s ~= "floor" then
			continue
		end
		local at = Vector3.new(placement.x, placement.y, placement.z)
		if DenSpace.check(after, item, placement.s, at).ok then
			table.insert(kept, placement)
		end
	end
	local dropped = #den.placed - #kept
	den.placed = kept
	local fell = DenSpace.settle(after, den.placed)
	if #fell > 0 then
		for i = #den.placed, 1, -1 do
			if table.find(fell, den.placed[i].uid) then
				table.remove(den.placed, i)
			end
		end
		dropped += #fell
	end
	-- Tanks a wing took with it give their fish back
	if typeof(den.tanks) == "table" then
		local open: { [string]: boolean } = {}
		for _, tank in DenSpace.tanks(after) do
			open[tank.id] = true
		end
		for id in den.tanks do
			if not open[id] then
				den.tanks[id] = nil
			end
		end
	end
	local index = FishService.denOf(player)
	if index then
		for _, other in Players:GetPlayers() do
			local _, root = FishService.character(other)
			if root and Layout.denAt(root.Position) == index then
				Net.teleport(other, Layout.spawnFrame(index))
			end
		end
	end
	return dropped
end

local function trayNote(player: Player, dropped: number)
	if dropped > 0 then
		Net.notify(
			player,
			`{dropped} thing{if dropped == 1 then "" else "s"} went back to your Build tray`,
			"info"
		)
	end
end

-- A wing built onto a slot (Config/Dens wings), swapped for another (the old one
-- gives back `wing.refund` of its price) or taken down (`wingId` "")
local function wing(player: Player, slotId: any, wingId: any)
	local data = DataService.get(player)
	local slot = if typeof(slotId) == "string" then Dens.wingSlotsById[slotId] else nil
	if data == nil or slot == nil or typeof(wingId) ~= "string" then
		return
	end
	local den = data.den
	if den.level < Dens.wing.level then
		local level = Dens.levels[Dens.wing.level]
		return fail(player, `Wings open once your den is a {if level then level.name else "Sanctum"}`)
	end
	if typeof(den.wings) ~= "table" then
		den.wings = {}
	end
	local current = Dens.wingsById[den.wings[slot.id] or ""]
	local def = if wingId == "" then nil else Dens.wingsById[wingId]
	if wingId ~= "" and def == nil then
		return
	end
	if current and def and current.id == def.id then
		return
	end
	if def and not EconomyService.spendCoral(player, def.price) then
		return fail(player, `Not enough coral ({def.price} needed)`)
	end
	local before = shapeOf(den)
	local refund = if current then math.floor(current.price * Dens.wing.refund) else 0
	if refund > 0 then
		EconomyService.addCoral(player, refund)
	end
	if def then
		den.wings[slot.id] = def.id
	else
		den.wings[slot.id] = nil
	end
	local dropped = reshape(player, data, before)
	DataService.markDirty(player)
	if def then
		Net.notify(
			player,
			`The masons built your {def.name}{if refund > 0
				then ` · +{refund} coral back for the {(current :: DensConfig.Wing).name}`
				else ""}`,
			"good"
		)
	else
		Net.notify(
			player,
			`Your {(current :: DensConfig.Wing).name} came down · +{refund} coral back`,
			"info"
		)
	end
	trayNote(player, dropped)
	DenService.refresh(player)
	Events.denChanged:fire(player, "wing")
end

-- Open Plan (Config/Dens openPlan): bought once, then switched on or off
local function openPlan(player: Player, on: any)
	local data = DataService.get(player)
	if data == nil or typeof(on) ~= "boolean" then
		return
	end
	local den = data.den
	local tune = Dens.openPlan
	if on and den.openOwned ~= true then
		if den.level < tune.level then
			local level = Dens.levels[tune.level]
			return fail(player, `Open Plan needs a {if level then level.name else "bigger"} den`)
		end
		if not EconomyService.spendCoral(player, tune.price) then
			return fail(player, `Not enough coral ({tune.price} needed)`)
		end
		den.openOwned = true
	end
	if (den.open == true) == on then
		return
	end
	local before = shapeOf(den)
	den.open = on
	local dropped = reshape(player, data, before)
	DataService.markDirty(player)
	Net.notify(
		player,
		if on then "Open Plan: the masons knocked your walls through" else "Your den's walls are back",
		"good"
	)
	trayNote(player, dropped)
	DenService.refresh(player)
	Events.denChanged:fire(player, "open")
end

-- Admin: every wing slot filled (in Config order) or emptied, and Open Plan on or off
function DenService.adminWings(player: Player, fill: boolean): string
	local data = DataService.get(player)
	if data == nil then
		return "No data"
	end
	local den = data.den
	local before = shapeOf(den)
	den.level = math.max(den.level, Dens.wing.level)
	den.wings = {}
	if fill then
		for i, slot in Dens.wingSlots do
			local def = Dens.wings[((i - 1) % #Dens.wings) + 1]
			den.wings[slot.id] = def.id
		end
	end
	local dropped = reshape(player, data, before)
	DataService.markDirty(player)
	DenService.refresh(player)
	return if fill
		then `Wings built in all {#Dens.wingSlots} slots · {dropped} back to the tray`
		else `Wings taken down · {dropped} back to the tray`
end

-- Admin: a wing slot set to one kind (no coral)
function DenService.adminWing(player: Player, slotId: string, wingId: string): string
	local data = DataService.get(player)
	if data == nil then
		return "No data"
	end
	local den = data.den
	local before = shapeOf(den)
	den.level = math.max(den.level, Dens.wing.level)
	if typeof(den.wings) ~= "table" then
		den.wings = {}
	end
	if Dens.wingsById[wingId] then
		den.wings[slotId] = wingId
	else
		den.wings[slotId] = nil
	end
	local dropped = reshape(player, data, before)
	DataService.markDirty(player)
	DenService.refresh(player)
	return `{slotId}: {if Dens.wingsById[wingId] then wingId else "empty"} · {dropped} back to the tray`
end

function DenService.adminOpen(player: Player, on: boolean): string
	local data = DataService.get(player)
	if data == nil then
		return "No data"
	end
	local den = data.den
	local before = shapeOf(den)
	den.openOwned = true
	den.open = on
	local dropped = reshape(player, data, before)
	DataService.markDirty(player)
	DenService.refresh(player)
	return `Open Plan {if on then "on" else "off"} · {dropped} back to the tray`
end

-- The den's shape for a player (other services: the aquarium's tanks)
function DenService.shape(player: Player): DenSpace.Shape?
	local data = DataService.get(player)
	return if data then shapeOf(data.den) else nil
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
		if item == nil or not DenSpace.check(shapeOf(data.den), item, placement.s, at).ok then
			table.remove(data.den.placed, i)
		end
	end
	DataService.markDirty(player)
	DenService.refresh(player)
end

-- Admin (PC 2026-10-16 round 2, D7: Studio had no old saves to load): turns this
-- den's record back into one saved before the private interiors (every placed thing
-- at its storey's old height, pulled in to the old rooms' size, no layout mark),
-- then loads it the way an old save loads (relayout). Returns a line for the admin
-- panel.
function DenService.simulateOldSave(player: Player): string
	local data = DataService.get(player)
	if data == nil then
		return "No data"
	end
	local den = data.den
	local before = #den.placed
	local lower = 0
	local growth = Dens.layout.growth
	for _, placement in den.placed do
		local storey = DenSpace.storeyAt(placement.y) or 1
		if storey > 1 then
			lower += 1
		end
		placement.y += OLD_DECKS[storey] - DenSpace.storey(storey).deck
		placement.x = snap(placement.x / growth)
		placement.z = snap(placement.z / growth)
	end
	den.layout = nil
	relayout(den)
	DataService.markDirty(player)
	DenService.refresh(player)
	return `Old save loaded: {before} placed ({lower} on the lower storeys) → {#den.placed} on their decks, {before - #den.placed} back to the tray`
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

-- The doorway portals (owner, 2026-10-16: every den is a private interior far
-- outside the play area). A fish swimming into a den's portal on the plaza goes into
-- that den (anyone may visit a den someone lives in, to look); one swimming into a
-- den's way out comes back out in front of its doorway. The client asks as its fish
-- swims in; the server checks it's really there, has the place stream in round the
-- fish, then moves it.
local travelling: { [Player]: boolean } = {}
local function travel(player: Player, target: CFrame)
	if travelling[player] then
		return
	end
	travelling[player] = true
	task.spawn(function()
		-- (3 s wasn't enough: leaving a den, the hub took ~20 s to arrive, owner
		-- 2026-10-17; the client keeps its loading wash up until the place is there)
		pcall(function()
			player:RequestStreamAroundAsync(target.Position, 10)
		end)
		local _, root = FishService.character(player)
		if root and player.Parent then
			Net.teleport(player, target)
		end
		travelling[player] = nil
	end)
end

-- Where a fish leaving den `index` comes out on the plaza: as far out as its camera
-- needs (Layout.exitOut), stepped back toward the doorway while its body would
-- overlap anything solid there (a stall's counter and posts, the Treasure Wheel)
local exitParams = OverlapParams.new()
exitParams.FilterType = Enum.RaycastFilterType.Exclude
exitParams.RespectCanCollide = true
local function exitFor(player: Player, index: number): CFrame
	local character = FishService.character(player)
	local length = if character then character:GetAttribute("Length") else nil
	if character == nil or typeof(length) ~= "number" then
		return Layout.hubExitFrame(index)
	end
	local speciesId = character:GetAttribute("Species")
	local species = if typeof(speciesId) == "string" then Config.Species.byId[speciesId] else nil
	local scale = if species and species.camera then species.camera else 1
	local filter: { Instance } = { workspace.Terrain }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(filter, other.Character)
		end
	end
	exitParams.FilterDescendantsInstances = filter
	local thick = Size.colliderDiameter(length) + 2
	local body = Vector3.new(thick, thick, length + 4)
	local out = Layout.exitOut(length, scale)
	while out > Layout.EXIT_OUT do
		local frame = Layout.hubExitFrame(index, out)
		if #workspace:GetPartBoundsInBox(frame, body, exitParams) == 0 then
			return frame
		end
		out -= 2
	end
	return Layout.hubExitFrame(index)
end

local function enterDen(player: Player, index: any)
	if typeof(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > Layout.DEN_COUNT then
		return
	end
	local _, root = FishService.character(player)
	if root == nil then
		return
	end
	if (root.Position - Layout.doorFrame(index).Position).Magnitude > Layout.DOOR_RADIUS + 16 then
		return
	end
	if FishService.ownerOf(index) == nil then
		Net.notify(player, "No one lives in this den yet", "info")
		return
	end
	travel(player, Layout.spawnFrame(index))
end

local function leaveDen(player: Player)
	local _, root = FishService.character(player)
	if root == nil then
		return
	end
	local index = Layout.denAt(root.Position)
	if index == nil then
		return
	end
	if (root.Position - Layout.exitFrame(index).Position).Magnitude > Config.Dens.exit.radius + 16 then
		return
	end
	travel(player, exitFor(player, index))
end

-- A fish near a portal (within 40 studs) has the far side streamed in ahead of it,
-- so swimming through finds it there: the hub from a den's way out, a lived-in den
-- from its doorway on the plaza
local prestreamed: { [Player]: number } = {}
local function prestream(player: Player)
	local _, root = FishService.character(player)
	if root == nil then
		return
	end
	local position = root.Position
	local target: CFrame? = nil
	local index = Layout.denAt(position)
	if index then
		if (position - Layout.exitFrame(index).Position).Magnitude <= 40 then
			target = exitFor(player, index)
		end
	else
		for door = 1, Layout.DEN_COUNT do
			if
				FishService.ownerOf(door) ~= nil
				and (position - Layout.doorFrame(door).Position).Magnitude <= 40
			then
				target = Layout.spawnFrame(door)
				break
			end
		end
	end
	if target == nil or os.clock() - (prestreamed[player] or 0) < 8 then
		return
	end
	prestreamed[player] = os.clock()
	local at = (target :: CFrame).Position
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(at, 10)
		end)
	end)
end

-- Every fish inside den `index` goes back out to the plaza (its owner left)
local function evict(index: number)
	for _, player in Players:GetPlayers() do
		local _, root = FishService.character(player)
		if root and Layout.denAt(root.Position) == index then
			travel(player, exitFor(player, index))
		end
	end
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
			evict(index)
			DenBuilder.clear(index, true)
			WorldService.setDenLevel(index, nil)
			WorldService.setDenDoor(index, nil)
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
	Net.onRequest("DenLayout", layout)
	Net.onRequest("DenStore", store)
	Net.onRequest("DenColor", color)
	Net.onRequest("DenFloor", floor)
	Net.onRequest("DenDoor", door)
	Net.onRequest("DenWing", wing)
	Net.onRequest("DenOpenPlan", openPlan)
	Net.onRequest("EnterDen", enterDen)
	Net.onRequest("LeaveDen", leaveDen)
	Net.onRequest("Prestream", prestream)
	Players.PlayerRemoving:Connect(function(player)
		prestreamed[player] = nil
	end)
	StateService.provide(function(player, data, state)
		state.den = data.den
		state.denIndex = FishService.denOf(player) or 0
		state.denCapacity = capacityOf(player, data.den)
	end)
end

return DenService
