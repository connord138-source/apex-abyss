--!strict
-- Where rare fish swim (Config/Catch `spawn`; owner, 2026-10-18: "I caught three
-- crystal fish in about 5 minutes ... rerun the spawn rates to fit what you think is
-- best that players dont get annoyed with the grind but they are also not done super
-- quick").
--
-- Every player out in the biomes has their own stream of rare fish: each rarity at
-- its rate a minute (Shared/Catch `rate`: the tide's boost, a rush early in a tide),
-- each one set swimming on a fish `near`–`far` studs from them, one they can swallow,
-- with nobody within `clearance` of it, so nothing turns rare in sight. It lands in
-- the biome the player is in (the one they're searching) when it can. The species is
-- picked first, evenly among the ones there they could eat, then a school of it, then
-- a fish in it, so every species gets its share of rare fish (the skin goals want
-- five). The Catch of the Week has a stream of its own (`weekly.rate`), only on its
-- species, only where it swims near the player. A rare fish swims about its
-- rarity's `life`, then quietly turns plain once no one's within `clearance`; a tide's
-- own rarity fades the same way when its tide ends. How often a player meets one
-- depends on neither how many fish swim nor how many players there are, and twelve
-- players hunting don't starve each other: each brings their own.
--
-- With no such fish (a full server crowding one biome), an eaten fish there that's
-- about to come back is picked instead: it comes back rare, fading in as it would.
--
-- Pure (Schools, Size, Seafloor; no services): CatchService runs it on the server and
-- tools/tests/catch_sim.luau runs the same code to measure the rates.
local Catch = require(script.Parent.Catch)
local Config = require(script.Parent.Config)
local Schools = require(script.Parent.Schools)
local Seafloor = require(script.Parent.Seafloor)
local Size = require(script.Parent.Size)

local CatchConfig = Config.Catch
local SPAWN = CatchConfig.spawn
local TRIES = 8 -- school picks before falling back to an eaten fish
local COMING_BACK = 45 -- seconds: an eaten fish back within this may be picked
local RETRY = 5 -- seconds before trying again when there was nowhere to put one

export type Hunter = {
	id: number, -- the player's UserId (its own spawn clock)
	position: Vector3,
	length: number, -- its rare fish are ones it can swallow
	deep: boolean, -- in a deep biome (a Bioluminescent Night's Glowing ×5 there)
}

export type Rare = { rarity: string, fadeAt: number }

export type Change = { index: number, rarity: string? }

export type Spawner = {
	rare: { [number]: Rare }, -- fish index → its rarity while it swims rare
	queued: { [number]: string }, -- eaten fish that come back rare
	count: { [string]: number }, -- rare fish of each rarity swimming (queued too)
	owed: { [number]: { [string]: number } }, -- hunter id → rarity → spawn clock
	due: { [number]: { [string]: number? } }, -- hunter id → rarity → when the next one comes
	-- How each rarity's spawns went: set swimming, nowhere to put one (tried again in
	-- RETRY seconds), or held back by the cap (PC 2026-11-02: the server set only ~1.1
	-- Silver a minute swimming round one hunter against the sim's 2.5)
	stats: { placed: { [string]: number }, failed: { [string]: number }, capped: { [string]: number } },
	rng: Random,
}

type SchoolInfo = {
	x: number,
	y: number,
	z: number,
	loop: number, -- how far its fish stray from its center (loop, school, rise and fall)
	prey: string,
	smallest: number, -- its smallest fish's length
	tide: string?,
	biome: string, -- the biome its middle is in
}

local RareSpawn = {}

-- The biome at (x, z) (Shared/Biomes without the hub's Layout): a sector that names
-- this spot, else the ring all round (the Kelp Shallows)
local function biomeOf(x: number, z: number): string
	local r, angle = Seafloor.polar(x, z)
	local fallback = ""
	for _, biome in Config.Biomes.list do
		if r >= biome.radiusFrom and r < biome.radiusTo then
			if (biome.angleTo - biome.angleFrom) % 360 == 0 then
				fallback = biome.id
			elseif Seafloor.inSector(angle, biome.angleFrom, biome.angleTo) then
				return biome.id
			end
		end
	end
	return fallback
end

local infos: { SchoolInfo }? = nil
local function schoolInfos(): { SchoolInfo }
	local known = infos
	if known then
		return known
	end
	local made: { SchoolInfo } = {}
	for _, school in Schools.list do
		local smallest = math.huge
		for i = school.first, school.first + school.count - 1 do
			smallest = math.min(smallest, Schools.fish[i].length)
		end
		table.insert(made, {
			x = school.center.X,
			y = school.center.Y,
			z = school.center.Z,
			loop = school.radius + school.spread + school.height,
			prey = school.prey,
			smallest = smallest,
			tide = school.tide,
			biome = biomeOf(school.center.X, school.center.Z),
		})
	end
	infos = made
	return made
end

local function apart(position: Vector3, x: number, y: number, z: number): number
	local dx, dy, dz = position.X - x, position.Y - y, position.Z - z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Whether anyone in `everyone` is within `range` of a point
local function nearAnyone(everyone: { Vector3 }, x: number, y: number, z: number, range: number): boolean
	for _, position in everyone do
		if apart(position, x, y, z) < range then
			return true
		end
	end
	return false
end

function RareSpawn.new(seed: number?): Spawner
	local count: { [string]: number } = {}
	for _, rarity in CatchConfig.rarities do
		count[rarity.id] = 0
	end
	return {
		rare = {},
		queued = {},
		count = count,
		owed = {},
		due = {},
		stats = { placed = {}, failed = {}, capped = {} },
		rng = Random.new(seed or 1),
	}
end

local function lifeOf(spawner: Spawner, rarityId: string): number
	local rarity = CatchConfig.byId[rarityId]
	return rarity.life * (0.75 + 0.5 * spawner.rng:NextNumber())
end

-- Sets fish `index` rare (or plain), noting the change
local function set(spawner: Spawner, index: number, rarityId: string?, now: number, changes: { Change }?)
	local old = spawner.rare[index]
	if old then
		spawner.count[old.rarity] -= 1
		spawner.rare[index] = nil
	end
	if rarityId then
		spawner.rare[index] = { rarity = rarityId, fadeAt = now + lifeOf(spawner, rarityId) }
		spawner.count[rarityId] += 1
	end
	if changes and (old ~= nil or rarityId ~= nil) then
		table.insert(changes, { index = index, rarity = rarityId })
	end
end

-- One rare fish of `rarityId` for `hunter`; false if there was nowhere to put it
local function place(
	spawner: Spawner,
	hunter: Hunter,
	rarityId: string,
	now: number,
	tideId: string,
	everyone: { Vector3 },
	eatenUntil: (number) -> number?,
	changes: { Change },
	only: string? -- this prey species only (the Catch of the Week)
): boolean
	local rng = spawner.rng
	local near, far, clearance = SPAWN.near, SPAWN.far, SPAWN.clearance
	local at = hunter.position
	-- The schools in reach with a fish the hunter can swallow, by species: in the
	-- biome the hunter is in if it has any, else anywhere in reach
	local bySpecies: { [string]: { number } } = {}
	local species: { string } = {}
	local open: { [number]: boolean } = {} -- clear of everyone at its center
	local home = biomeOf(at.X, at.Z)
	local elsewhere: { [string]: { number } } = {}
	local elsewhereSpecies: { string } = {}
	for index, info in schoolInfos() do
		if info.tide and info.tide ~= tideId then
			continue
		end
		if not Size.canSwallow(hunter.length, info.smallest) then
			continue
		end
		local distance = apart(at, info.x, info.y, info.z)
		if distance < near - info.loop or distance > far + info.loop then
			continue
		end
		local inHome = info.biome == home
		local group = if inHome then bySpecies else elsewhere
		local list = group[info.prey]
		if list == nil then
			list = {}
			group[info.prey] = list
			table.insert(if inHome then species else elsewhereSpecies, info.prey)
		end
		table.insert(list, index)
		open[index] = not nearAnyone(everyone, info.x, info.y, info.z, clearance)
	end
	if #species == 0 then
		bySpecies, species = elsewhere, elsewhereSpecies
	end
	if #species == 0 then
		return false
	end
	if only then
		-- (the Catch of the Week's own stream: its species or nothing)
		if bySpecies[only] == nil then
			return false
		end
		species = { only }
	end
	table.sort(species) -- (the same order every run, for the sim)
	for _ = 1, TRIES do
		local list = bySpecies[species[rng:NextInteger(1, #species)]]
		local schoolIndex = list[rng:NextInteger(1, #list)]
		if not open[schoolIndex] then
			continue
		end
		local school = Schools.list[schoolIndex]
		local start = rng:NextInteger(0, school.count - 1)
		for k = 0, school.count - 1 do
			local index = school.first + (start + k) % school.count
			local fish = Schools.fish[index]
			if spawner.rare[index] or spawner.queued[index] then
				continue
			end
			local back = eatenUntil(index)
			if (back and back > now) or not Size.canSwallow(hunter.length, fish.length) then
				continue
			end
			local position = Schools.position(index, now)
			local distance = (position - at).Magnitude
			if distance < near or distance > far then
				continue
			end
			if nearAnyone(everyone, position.X, position.Y, position.Z, clearance) then
				continue
			end
			set(spawner, index, rarityId, now, changes)
			return true
		end
	end
	-- Nowhere out of sight: an eaten fish in reach comes back rare
	local order = table.clone(species)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	for _, preyId in order do
		for _, schoolIndex in bySpecies[preyId] do
			local school = Schools.list[schoolIndex]
			for index = school.first, school.first + school.count - 1 do
				local back = eatenUntil(index)
				if
					back
					and back > now
					and back < now + COMING_BACK
					and not spawner.queued[index]
					and Size.canSwallow(hunter.length, Schools.fish[index].length)
				then
					spawner.queued[index] = rarityId
					spawner.count[rarityId] += 1
					return true
				end
			end
		end
	end
	return false
end

-- One step of `dt` seconds (`now` on the shared clock, `unix` for the Catch of the
-- Week, tide `tideId` up for `sinceTide` seconds: Shared/Tides.at): rare fish past
-- their life (or their tide) that no one is near turn plain, and each hunter's
-- rarities come due and are placed. `hunters` are the players out in the biomes;
-- `everyone` is where every player is (the hub too); `eatenUntil(index)` is when an
-- eaten fish is back (nil if it isn't eaten). Returns what changed, for the clients.
function RareSpawn.step(
	spawner: Spawner,
	dt: number,
	now: number,
	unix: number,
	tideId: string,
	sinceTide: number, -- seconds since the tide turned
	hunters: { Hunter },
	everyone: { Vector3 },
	eatenUntil: (number) -> number?
): { Change }
	local changes: { Change } = {}
	local clearance = SPAWN.clearance
	for index, rare in spawner.rare do
		local rarity = CatchConfig.byId[rare.rarity]
		if not Schools.out(index, tideId) then
			set(spawner, index, nil, now, changes)
		elseif now >= rare.fadeAt or (rarity.tide and rarity.tide ~= tideId) then
			local position = Schools.position(index, now)
			if not nearAnyone(everyone, position.X, position.Y, position.Z, clearance) then
				set(spawner, index, nil, now, changes)
			end
		end
	end
	-- Each rarity's spawns a second, summed over the hunters (the cap)
	local since = sinceTide
	local rates: { [string]: number } = {}
	for _, hunter in hunters do
		for _, rarity in CatchConfig.rarities do
			rates[rarity.id] = (rates[rarity.id] or 0)
				+ Catch.rate(rarity.id, tideId, hunter.deep, since) / 60
		end
	end
	local seen: { [number]: boolean } = {}
	for _, hunter in hunters do
		seen[hunter.id] = true
		local owed = spawner.owed[hunter.id]
		local due = spawner.due[hunter.id]
		if owed == nil or due == nil then
			owed, due = {}, {}
			spawner.owed[hunter.id] = owed
			spawner.due[hunter.id] = due
		end
		for _, rarity in CatchConfig.rarities do
			local id = rarity.id
			local rate = Catch.rate(id, tideId, hunter.deep, since) / 60
			if rate <= 0 then
				continue
			end
			-- A Poisson clock: the next one comes after an exponential wait
			owed[id] = (owed[id] or 0) + rate * dt
			local wait: number = due[id] or -math.log(1 - spawner.rng:NextNumber())
			due[id] = wait
			if owed[id] < wait then
				continue
			end
			local cap = SPAWN.cap * (rates[id] or 0) * rarity.life + 1
			local stats = spawner.stats
			if spawner.count[id] >= cap then
				owed[id] = 0
				due[id] = nil
				stats.capped[id] = (stats.capped[id] or 0) + 1
			elseif place(spawner, hunter, id, now, tideId, everyone, eatenUntil, changes) then
				owed[id] -= wait
				due[id] = nil
				stats.placed[id] = (stats.placed[id] or 0) + 1
			else
				stats.failed[id] = (stats.failed[id] or 0) + 1
				-- (nowhere this time: it comes when there's room, tried again in a
				-- few seconds, never more than the one)
				owed[id] = wait - rate * RETRY
			end
		end
		-- The Catch of the Week's own stream: its rarity on its species, only while
		-- the player is near where that species swims (nothing owed elsewhere)
		local featured, weekly = Catch.weeklyRate(unix, tideId, hunter.deep)
		if featured and weekly > 0 then
			owed.Weekly = (owed.Weekly or 0) + weekly / 60 * dt
			local wait: number = due.Weekly or -math.log(1 - spawner.rng:NextNumber())
			due.Weekly = wait
			if owed.Weekly >= wait then
				owed.Weekly -= wait
				due.Weekly = nil
				place(
					spawner,
					hunter,
					featured.rarity,
					now,
					tideId,
					everyone,
					eatenUntil,
					changes,
					featured.prey
				)
			end
		end
	end
	for id in spawner.owed do
		if not seen[id] then
			spawner.owed[id] = nil
			spawner.due[id] = nil
		end
	end
	return changes
end

-- An eaten fish is back: rare if it was picked while eaten (its rarity, else nil)
function RareSpawn.respawned(spawner: Spawner, index: number, now: number): string?
	local rarityId = spawner.queued[index]
	if rarityId == nil then
		return nil
	end
	spawner.queued[index] = nil
	spawner.count[rarityId] -= 1
	set(spawner, index, rarityId, now, nil)
	return rarityId
end

-- A fish eaten: its rarity (nil = plain), taken off it
function RareSpawn.take(spawner: Spawner, index: number): string?
	local rare = spawner.rare[index]
	if rare == nil then
		return nil
	end
	set(spawner, index, nil, 0, nil)
	return rare.rarity
end

-- Sets a fish's rarity by hand (the admin panel), nil = plain
function RareSpawn.set(spawner: Spawner, index: number, rarityId: string?, now: number)
	set(spawner, index, rarityId, now, nil)
end

function RareSpawn.rarityOf(spawner: Spawner, index: number): string?
	local rare = spawner.rare[index]
	return if rare then rare.rarity else nil
end

return RareSpawn
