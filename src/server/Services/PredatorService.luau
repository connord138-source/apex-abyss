--!strict
-- AI predators (Config/Predators): simulated here ten times a second and streamed to
-- every client (positions, headings, modes), which interpolate them. Each one roams
-- its band, hunts the biggest worthwhile fish in range, shows its jaw for a moment
-- (the tell), then bites for a share of the victim's max health. Players bite back
-- (BitePredator, checked for reach and cooldown); a kill pays everyone who helped by
-- damage share. The world bosses (BossService) are `custom` predators: they ride the
-- same stream and bite checks, but BossService moves them (steer), scales their
-- damage (onHit) and pays their rewards.
--
-- Each plain predator hunts in its own style (Config/Predators `style`): the
-- Barracuda is an ambush sprinter (lurks by cover, bursts from mid range leading its
-- fish, snaps at once from close and whips round on a fish beside it; outlasting the
-- burst or a Dash beats it, a juke late in its tell about half the time), the Reef
-- Shark a relentless tracker (runs most fish in its water down, smells blood, but
-- turns wide and is too big for kelp). Owner, 2026-10-20: "a lot more aggressive and
-- more accurate ... Easily killed a barracuda at lvl 16 by just going back and forth
-- at it": both now bite a fish darting in and out at them. A burrowed fish (character attribute `Burrowed`) is never prey, a
-- puffed one (`Puffed`) takes half a bite and spines the biter, and the Anglerfish's
-- Lantern Flash stuns them (`PredatorService.stun`).
--
-- Every biome has its own since 2026-10-21 (Config/Predators), each in its own way:
-- the Sea Lion harries, the Goliath Grouper's tell sucks a fish in (`gulp`), Giant
-- Trevally hunt in packs (one drives, two flank), the Mako comes up from below, the
-- Sixgill patrols, the Wolf Eel lunges from its hole and never strays far
-- (`tether`), the Goblin Shark throws its jaws, and the Black Dragonfish draws its fish
-- in with a lure (`lure`). A fight goes by level like a fight between players
-- (Config/Predators `fight`): bites both ways scale with the gap, a fish `swallow`
-- levels up swallows it whole, it shies off a fish `shy` levels up, and a kill pays a
-- fish well above it little.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PredatorsConfig = require(ReplicatedStorage.Shared.Config.Predators)
local Format = require(ReplicatedStorage.Shared.Format)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Size = require(ReplicatedStorage.Shared.Size)
local Tides = require(ReplicatedStorage.Shared.Tides)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
local ChumService = require(script.Parent.ChumService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local HuntService = require(script.Parent.HuntService)

local Predators = Config.Predators
local World = Config.World
local hunt = Config.Tuning.hunt
local swim = Config.Tuning.swim

export type Def = PredatorsConfig.PredatorDef

export type Mode = "roam" | "hunt" | "windup" | "recover" | "stunned" | "dead"

export type Predator = {
	index: number,
	def: Def,
	position: Vector3,
	velocity: Vector3,
	heading: Vector3,
	health: number,
	maxHealth: number,
	mode: Mode,
	modeUntil: number,
	target: Player?,
	waypoint: Vector3,
	waypointUntil: number,
	lureAt: number, -- when it next looks for chum while roaming
	respawnAt: number,
	-- Damage dealt by each player this life, and when they last bit (the school bonus)
	hitBy: { [Player]: { damage: number, at: number } },
	-- Set by a boss controller: skips the plain behaviour and the plain loot
	custom: boolean?,
	-- A boss's hook on every player bite: (predator, player, damage, point) → damage
	onHit: ((Predator, Player, number, Vector3) -> number)?,
	-- A boss's stagger meter (0..1), streamed to clients
	meter: number,
	-- Which way it peels off after a strike (+1 right, -1 left), for a looping pass
	peel: number,
	-- An ambusher's burst runs until this clock (0 = none); stunned until this clock
	burstUntil: number,
	stunUntil: number,
	-- An ambusher's failed bursts on each fish, and the fish it has given up on (until)
	fails: { [Player]: number },
	ignore: { [Player]: number },
	-- A harrier's landed nips on each fish (how many, the last one's clock), until it
	-- lets that fish go (`nips`)
	nipped: { [Player]: { count: number, at: number } },
	-- Its last strike (or feint) and how far it swerves off as it carries through: it
	-- comes round once `carry` has passed
	strikeAt: number,
	veer: number,
	-- How it opens a hunt on the fish it has (`approachFor`): "circle" (until
	-- `approachUntil`, round `orbit` ±1), "under" or "direct"; and a feint left to use
	approach: string,
	approachFor: Player?,
	approachUntil: number,
	orbit: number,
	feintLeft: boolean,
	-- Its pack (Config/Predators `pack`): every member, and its place in it (1 leads)
	pack: { Predator }?,
	role: number,
	-- A tethered hunter's hole (`tether`): where it spawned, or where it was last
	-- stranded (`strayed`: when it went past its tether while roaming, math.huge
	-- while it's in)
	home: Vector3?,
	strayed: number,
	-- Its patch of its group's water (Config/Predators `spread`): number `slot`
	-- (from 0) of `slots`; nil for a boss or one added on its own (the whole water)
	slot: number?,
	slots: number?,
	-- A gulper's pull is broken for this tell (the fish swam off too fast)
	gulpFree: boolean,
	-- When a lure last told its fish it's being drawn in
	luredAt: number,
}

local PredatorService = {
	-- (predator, killer?) — a predator died (killer nil when it was removed)
	died = require(ReplicatedStorage.Shared.Signal).new(),
}

local predators: { [number]: Predator } = {}
local nextIndex = 1
local rng = Random.new(World.seed + 41)
local lastBite: { [Player]: number } = {}
local accumulator = 0
local STREAM_BATCH = 4 -- creatures per position packet (an entry is ~130 bytes)
-- A body's half-height as a share of its length (its belly under its middle)
local BODY_HALF = 0.12
-- Water kept between the belly and the ground, at the least (studs)
local BELLY_GAP = 1.5
-- How steeply a plain predator may point up or down (sine of the pitch): a fish
-- doesn't stand on its nose (PC 2026-10-22: three of four Wolf Eels sat nose-down by
-- a rock, heading (0, -1, 0))
local MAX_PITCH = 0.8
-- Seconds a tethered hunter may roam past its tether before that spot becomes its
-- hole (PC 2026-10-22: two Wolf Eels climbed a basalt column ~110 studs over their
-- holes; measured from the hole, every fish beside them was out of reach)
local REHOME_AFTER = 4
-- Studs a lurker's spot may stand over the nominal floor (Seafloor): higher is a
-- rock's top or the drop-off's lip, not a hole by the floor
local LURK_RISE = 14
-- How much faster a tethered hunter turns round on a fish beside or behind it (its
-- `whip`, unless its style sets one)
local TETHER_WHIP = 2.5
local TETHER_PIVOT = 0.08 -- (the share of its speed it keeps meanwhile)

-- A Blood Tide's hunters: faster and keener (Config/Tides `hunters`; never bosses)
local function hunters(predator: Predator): (number, number)
	if predator.custom then
		return 1, 1
	end
	local tide = Tides.at(Timing.unix())
	local boost = tide.hunters
	return if boost then boost.speed else 1, if boost then boost.aggro else 1
end

-- Its mode as it stands now (read afresh after a call that may have changed it)
local function modeOf(predator: Predator): Mode
	return predator.mode
end

-- How it hunts (Config/Predators `style`; a predator with none is the plain hunter)
local PLAIN: PredatorsConfig.Style = {
	kind = "plain",
	chase = 1,
	turnAtSpeed = 0.8,
	tellFollow = 0.55,
	slowsToTurn = 0.35,
}
local function styleOf(def: Def): PredatorsConfig.Style
	return def.style or PLAIN
end

local fight = Predators.fight
local growth = Config.Tuning.size.levelGrowth

-- A fish's level, the one fights go by (HuntService's `FishLevel`: banked, so the
-- Haul aboard doesn't count)
local function levelOf(character: Model?): number
	local level = if character then character:GetAttribute("FishLevel") else nil
	return if typeof(level) == "number" then level else 1
end

-- How much stronger level `a` is than level `b` in a fight: (the mass at `a` ÷ the
-- mass at `b`) ^ power, about ×1.07 a level (Config/Pvp `fight`)
local function strength(a: number, b: number): number
	return growth ^ ((a - b) * fight.power)
end

-- Its bite on a fish, × its biteFraction: harder on a fish under its level, a nip on
-- one well above it (1 for a creature with no level: a boss)
local function theirBite(def: Def, character: Model?): number
	local level = def.level
	if level == nil then
		return 1
	end
	return math.clamp(strength(level, levelOf(character)), fight.theirs.min, fight.theirs.max)
end

-- Whether a fish is too far above a plain predator's level for it to take on
local function outclassed(def: Def, character: Model): boolean
	local level = def.level
	return level ~= nil and levelOf(character) > level + fight.shy
end

-- Whether a fish is still in the tutorial (a `spareLearners` hunter leaves it alone)
local function learning(player: Player): boolean
	local data = DataService.get(player)
	local tutorial = if data then (data :: any).tutorial else nil
	return typeof(tutorial) == "table" and tutorial.done == false
end

-- Kelp forests (World.Biomes.Kelp): where each stalk stands, by cell, for a hunter
-- too big to follow a fish into one (`kelpShy`). Read once the kelp is built.
type KelpStalk = { x: number, z: number, bottom: number, top: number }
local KELP_CELL = 16
local KELP_NEAR = 12 -- studs: two stalks this close round a fish and it's in the forest
local kelpCells: { [number]: { KelpStalk } }? = nil
local kelpTriedAt = -math.huge
local function kelpKey(cx: number, cz: number): number
	return (cx + 1000) * 4096 + (cz + 1000)
end
local function kelpIndex(): { [number]: { KelpStalk } }?
	local known = kelpCells
	if known then
		return known
	end
	if os.clock() - kelpTriedAt < 10 then
		return nil
	end
	kelpTriedAt = os.clock()
	local world = workspace:FindFirstChild("World")
	local biomes = if world then world:FindFirstChild("Biomes") else nil
	local kelp = if biomes then biomes:FindFirstChild("Kelp") else nil
	if kelp == nil then
		return nil
	end
	local cells: { [number]: { KelpStalk } } = {}
	for _, plant in kelp:GetChildren() do
		local stalk = plant:FindFirstChild("Stalk")
		if stalk and stalk:IsA("BasePart") then
			local at, height = stalk.Position, stalk.Size.Y
			local key = kelpKey(math.floor(at.X / KELP_CELL), math.floor(at.Z / KELP_CELL))
			local list = cells[key] or {}
			cells[key] = list
			table.insert(list, { x = at.X, z = at.Z, bottom = at.Y - height / 2, top = at.Y + height / 2 })
		end
	end
	kelpCells = cells
	return cells
end
local function inKelp(position: Vector3): boolean
	local cells = kelpIndex()
	if cells == nil then
		return false
	end
	local cx, cz = math.floor(position.X / KELP_CELL), math.floor(position.Z / KELP_CELL)
	local near = 0
	for dx = -1, 1 do
		for dz = -1, 1 do
			local list: { KelpStalk } = cells[kelpKey(cx + dx, cz + dz)] or {}
			for _, stalk in list do
				local ex, ez = stalk.x - position.X, stalk.z - position.Z
				if
					ex * ex + ez * ez <= KELP_NEAR * KELP_NEAR
					and position.Y >= stalk.bottom - 2
					and position.Y <= stalk.top
				then
					near += 1
					if near >= 2 then
						return true
					end
				end
			end
		end
	end
	return false
end

-- How far rock or kelp stands round a spot (an ambusher lurks by it)
local function coverAt(x: number, z: number, away: number?): number
	local floor = Seafloor.y(x, z)
	local raised = 0
	local d = away or 10
	for _, offset in
		{ Vector3.new(d, 0, 0), Vector3.new(-d, 0, 0), Vector3.new(0, 0, d), Vector3.new(0, 0, -d) }
	do
		raised = math.max(raised, Ground.y(x + offset.X, z + offset.Z) - floor)
	end
	if inKelp(Vector3.new(x, floor + 4, z)) then
		raised += 10
	end
	return raised
end

-- Its own patch of its group's water (Config/Predators `spread`): the sector (or
-- the whole ring) cut into `slots` arcs, `overlap` of an arc either side. Its first
-- angle and its span, in degrees.
local function patchOf(predator: Predator): (number, number)
	local def = predator.def
	local from = if def.angles then def.angles[1] else 0
	local span = if def.angles then (def.angles[2] - def.angles[1]) % 360 else 360
	span = if span == 0 then 360 else span
	local slot, slots = predator.slot, predator.slots
	if slot == nil or slots == nil or slots <= 1 then
		return from, span
	end
	local arc = span / slots
	local overlap = arc * Predators.spread.overlap
	return from + arc * slot - overlap, arc + overlap * 2
end

-- A spot down in the Trench's canyon (a `trench` hunter): along its winding line,
-- across its floor, at the hunter's depth over the real ground
local function trenchWaypoint(predator: Predator): Vector3
	local def = predator.def
	local trench = World.trench
	local lo = math.max(def.band[1], trench.radii[1] + 15)
	local hi = math.max(math.min(def.band[2], trench.radii[2] - 15), trench.radii[1] + 16)
	-- (its patch is a stretch of the canyon)
	local slot, slots = predator.slot, predator.slots
	if slot and slots and slots > 1 then
		local step = (hi - lo) / slots
		local overlap = step * Predators.spread.overlap
		lo, hi = math.max(lo, lo + step * slot - overlap), math.min(hi, lo + step * (slot + 1) + overlap)
	end
	local r = rng:NextNumber(lo, hi)
	local _, width = Seafloor.trenchAxis(r)
	local _, _, halfBottom = Seafloor.trenchHalfWidths(width)
	local x, z = Seafloor.trenchPoint(r, rng:NextNumber(-1, 1) * math.max(halfBottom - 12, 4))
	local ground = math.max(Seafloor.y(x, z), Ground.y(x, z))
	return Vector3.new(x, ground + rng:NextNumber(def.depth[1], def.depth[2]), z)
end

-- How far round the ring the next roaming spot may lie from where it is (PC
-- 2026-10-22: a spot anywhere in a wide sector had the Reef's trevally packs swim
-- straight chords across the Kelp Shallows, down to the hub's keep-out at r 213)
local ROAM_ARC = math.rad(50)

-- An angle round the hub in its patch: anywhere in it, or within ROAM_ARC of `near`
-- and in the patch (from outside it, the patch's nearer end; never piled on an edge)
local function pickAngle(predator: Predator, near: number?): number
	local from, span = patchOf(predator)
	if near == nil then
		return math.rad(from + rng:NextNumber(0, span))
	end
	if span >= 360 then
		return near + rng:NextNumber(-ROAM_ARC, ROAM_ARC)
	end
	local arc = math.deg(ROAM_ARC)
	local into = (math.deg(near) - from) % 360
	if into > span then
		-- (outside the patch: back in from its nearer end)
		into = if into - span < 360 - into then span else 0
	end
	return math.rad(from + rng:NextNumber(math.max(into - arc, 0), math.min(into + arc, span)))
end

local function randomWaypoint(predator: Predator, near: number?): Vector3
	local def = predator.def
	local style = styleOf(def)
	if style.trench then
		return trenchWaypoint(predator)
	end
	local lurk = style.lurk
	if lurk then
		-- An ambusher lurks low by a rock, a coral head or the kelp: the best cover of a
		-- few spots in its patch, the rock just past its body's reach, and at a height
		-- its body can rest at over the ground under it (a Wolf Eel's hole had been at
		-- the foot of a rock its body overlapped: held up over the rock's top, it
		-- pointed itself down at the hole; PC 2026-10-22)
		-- Only by the floor itself: a spot whose ground stands more than LURK_RISE over
		-- the nominal floor is a rock top or the drop-off's lip (PC 2026-10-23: four
		-- Wolf Eels held holes 69-121 studs up beside basalt columns, taking the
		-- column's top for their ground, and one sat on the shelf's crest at r 920, by
		-- the Wreck bay's LV 10-25 water); the lowest one found if none is
		local best: Vector3? = nil
		local bestCover = -1
		local lowest: Vector3? = nil
		local lowestRise = math.huge
		local half = def.length * 0.5
		local clear = def.length * BODY_HALF + BELLY_GAP
		for _ = 1, 12 do
			local angle = pickAngle(predator, near)
			local distance = rng:NextNumber(def.band[1], def.band[2])
			local x, z = math.cos(angle) * distance, math.sin(angle) * distance
			if not Seafloor.inTrench(x, z, 30) then
				local cover = coverAt(x, z, half + 4)
				local floor = Seafloor.y(x, z)
				local ground = math.max(floor, Ground.y(x, z))
				for _, offset in
					{
						Vector3.new(half, 0, 0),
						Vector3.new(-half, 0, 0),
						Vector3.new(0, 0, half),
						Vector3.new(0, 0, -half),
					}
				do
					ground = math.max(ground, Ground.y(x + offset.X, z + offset.Z))
				end
				local up = math.max(rng:NextNumber(lurk[1], lurk[2]), clear + 0.5)
				local spot = Vector3.new(x, ground + up, z)
				local rise = ground - floor
				if rise <= LURK_RISE and cover > bestCover then
					best, bestCover = spot, cover
				elseif rise < lowestRise then
					lowest, lowestRise = spot, rise
				end
			end
		end
		if best or lowest then
			return (best or lowest) :: Vector3
		end
	end
	for _ = 1, 20 do
		local angle = pickAngle(predator, near)
		local distance = rng:NextNumber(def.band[1], def.band[2])
		local x, z = math.cos(angle) * distance, math.sin(angle) * distance
		if not Seafloor.inTrench(x, z, 30) then
			-- Over the real ground: a waypoint inside a reef head was swum straight into
			local ground = math.max(Seafloor.y(x, z), Ground.y(x, z))
			return Vector3.new(x, ground + rng:NextNumber(def.depth[1], def.depth[2]), z)
		end
	end
	local from, span = patchOf(predator)
	local fallback = math.rad(from + span / 2)
	local x, z = math.cos(fallback) * def.band[1], math.sin(fallback) * def.band[1]
	return Vector3.new(x, Seafloor.y(x, z) + def.depth[1] + 10, z)
end

-- A hole by the floor near `at` for a tethered hunter that was stranded there: the
-- nearest spot (itself, then rings 12 studs apart out to 48) whose ground under its
-- body stands no more than LURK_RISE over the nominal floor, or `at` if none is
local function holeNear(predator: Predator, at: Vector3): Vector3
	local def = predator.def
	local half = def.length * 0.5
	local clear = def.length * BODY_HALF + BELLY_GAP
	local lurk = styleOf(def).lurk
	local up = math.max(if lurk then lurk[1] else 2, clear + 0.5)
	for ring = 0, 4 do
		local count = if ring == 0 then 1 else 8
		for k = 1, count do
			local a = k / count * 2 * math.pi
			local x, z = at.X + math.cos(a) * ring * 12, at.Z + math.sin(a) * ring * 12
			local floor = Seafloor.y(x, z)
			local ground = math.max(floor, Ground.y(x, z))
			for _, offset in { { half, 0 }, { -half, 0 }, { 0, half }, { 0, -half } } do
				ground = math.max(ground, Ground.y(x + offset[1], z + offset[2]))
			end
			if ground - floor <= LURK_RISE and not Seafloor.inTrench(x, z, 30) then
				return Vector3.new(x, ground + up, z)
			end
		end
	end
	return at
end

-- Where it roams to next: a tethered hunter circles its hole, level with it, over
-- ground no higher than the hole's (never onto the rock beside it: a spot inside the
-- rock had it climb the rock's face to its top), the rest roam on round their patch
-- from where they are
local function waypointFor(predator: Predator): Vector3
	local home = predator.home
	if home then
		local def = predator.def
		local tether = styleOf(def).tether or 16
		local clear = def.length * BODY_HALF + BELLY_GAP
		local below = home.Y - clear
		local room = def.length * 0.3
		for _ = 1, 8 do
			local angle = rng:NextNumber(0, 2 * math.pi)
			local out = rng:NextNumber(10, math.max(tether * 0.5, 12))
			local x, z = home.X + math.cos(angle) * out, home.Z + math.sin(angle) * out
			-- (the rock round the spot, with room for its body, and halfway back)
			local ground = math.max(
				Ground.y(x, z),
				Ground.y(x + room, z),
				Ground.y(x - room, z),
				Ground.y(x, z + room),
				Ground.y(x, z - room),
				Ground.y((x + home.X) * 0.5, (z + home.Z) * 0.5),
				Seafloor.y(x, z)
			)
			if ground <= below + 3 then
				return Vector3.new(x, math.max(home.Y, ground + clear) + rng:NextNumber(0, 2), z)
			end
		end
		return home
	end
	local at = predator.position
	return randomWaypoint(predator, math.atan2(at.Z, at.X))
end

-- A pack's leader: its first member that's alive (nil for a lone hunter)
local function leaderOf(predator: Predator): Predator?
	local pack = predator.pack
	if pack == nil then
		return nil
	end
	for _, member in pack do
		if member.mode ~= "dead" then
			return member
		end
	end
	return nil
end

-- Where a pack member keeps station round its leader: out to one side and a little
-- behind (its `role` picks the side)
local function stationOf(predator: Predator, leader: Predator): Vector3
	local spread = (styleOf(predator.def).pack :: { size: number, spread: number }).spread
	local heading = Vector3.new(leader.heading.X, 0, leader.heading.Z)
	heading = if heading.Magnitude > 1e-3 then heading.Unit else Vector3.xAxis
	local right = Vector3.new(-heading.Z, 0, heading.X)
	local side = if predator.role % 2 == 0 then 1 else -1
	local rank = math.ceil((predator.role - 1) / 2)
	return leader.position + right * side * spread * rank - heading * spread * 0.6 * rank
end

local function spawn(predator: Predator, at: Vector3?)
	-- (a pack member comes back beside its leader)
	local leader = leaderOf(predator)
	if at == nil and leader and leader ~= predator then
		at = stationOf(predator, leader)
	end
	predator.position = at or randomWaypoint(predator)
	predator.home = if styleOf(predator.def).tether then predator.position else nil
	predator.strayed = math.huge
	predator.velocity = Vector3.zero
	predator.heading = Vector3.new(1, 0, 0)
	predator.health = predator.maxHealth
	predator.mode = "roam"
	predator.modeUntil = 0
	predator.target = nil
	predator.waypoint = waypointFor(predator)
	predator.waypointUntil = Timing.clock() + 12
	predator.hitBy = {}
	predator.meter = 0
	predator.peel = if rng:NextNumber() < 0.5 then -1 else 1
	predator.burstUntil = 0
	predator.stunUntil = 0
	predator.fails = {}
	predator.ignore = {}
	predator.nipped = {}
	predator.strikeAt = -math.huge
	predator.veer = 0
	predator.approach = "direct"
	predator.approachFor = nil
	predator.approachUntil = 0
	predator.feintLeft = false
	predator.gulpFree = false
	Net.predatorEvent("spawned", predator.index, {
		id = predator.def.id,
		x = predator.position.X,
		y = predator.position.Y,
		z = predator.position.Z,
	})
end

local function mouthOf(predator: Predator): Vector3
	return predator.position + predator.heading * predator.def.length * (predator.def.mouth or 0.45)
end

local function rotateToward(from: Vector3, to: Vector3, maxAngle: number): Vector3
	if to.Magnitude < 1e-4 then
		return from
	end
	to = to.Unit
	local dot = math.clamp(from:Dot(to), -1, 1)
	local angle = math.acos(dot)
	if angle <= maxAngle or angle < 1e-4 then
		return to
	end
	local axis = from:Cross(to)
	if axis.Magnitude < 1e-5 then
		axis = Vector3.yAxis
	end
	return CFrame.fromAxisAngle(axis.Unit, maxAngle):VectorToWorldSpace(from)
end

-- Whether a point is inside the hub's keep-out (Predators.hubKeepOut).
local function nearHub(position: Vector3, margin: number): boolean
	local hub = World.hub.center
	return Vector3.new(position.X - hub.X, 0, position.Z - hub.Z).Magnitude < Predators.hubKeepOut + margin
end

-- A plain hunter takes and keeps only fish this close to its own water (studs of
-- band past its edges; PC 2026-10-22: the Reef's LV 32 trevally packs followed LV 1-8
-- fish 300 studs into the Kelp Shallows, to r 213, and ate them at the Kelp Cathedral)
local CHASE_SLACK = 60

-- Whether a point is in a creature's own water: its band round the hub and its
-- sector, give or take `slack` studs of band (chum doesn't draw a reef shark into
-- the kelp)
local function inRange(def: Def, position: Vector3, slack: number?): boolean
	local hub = World.hub.center
	local offset = Vector3.new(position.X - hub.X, 0, position.Z - hub.Z)
	local r = offset.Magnitude
	local give = slack or 40
	if r < def.band[1] - give or r > def.band[2] + give then
		return false
	end
	local sector = def.angles
	if sector == nil then
		return true
	end
	local angle = math.deg(math.atan2(offset.Z, offset.X)) % 360
	local span = (sector[2] - sector[1]) % 360
	return span == 0 or (angle - sector[1]) % 360 <= span
end

-- Whether a fish is puffed up (the Pufferfish's Puff Up: character attribute
-- `Puffed`, the server clock it deflates at, set by AbilityService; `true` also counts)
local function isPuffed(character: Model, now: number): boolean
	local value = character:GetAttribute("Puffed")
	return value == true or (typeof(value) == "number" and value > now)
end

-- Whether a fish's health is under `below` of its max (a tracker smells blood)
local function bleeding(character: Model, below: number): boolean
	local health, most = character:GetAttribute("Health"), character:GetAttribute("MaxHealth")
	return typeof(health) == "number" and typeof(most) == "number" and most > 0 and health < most * below
end

-- How far it notices a fish: its aggro range, keener on a Blood Tide, further on a
-- bleeding fish for a tracker
local function senseRange(predator: Predator, character: Model): number
	local def = predator.def
	local style = styleOf(def)
	local _, keen = hunters(predator)
	local range = def.aggroRange * keen
	local blood = style.blood
	if blood and bleeding(character, style.bloodBelow or 0.5) then
		range *= blood
	end
	return range
end

-- Whether a plain predator may go after this fish at all: not one burrowed in the
-- sand (character attribute `Burrowed`), not one it gave up on, and not one in a kelp
-- forest it's too big for (bosses skip these)
local function inReach(
	predator: Predator,
	player: Player,
	character: Model,
	root: BasePart,
	now: number
): boolean
	if predator.custom then
		return true
	end
	if character:GetAttribute("Burrowed") == true or (predator.ignore[player] or 0) > now then
		return false
	end
	return not (styleOf(predator.def).kelpShy and inKelp(root.Position))
end

-- Whether it keeps chasing the fish it has: alive, out of the hub, in reach and
-- within its leash
local function keepsHunting(predator: Predator, player: Player, now: number): boolean
	local session = HuntService.sessions()[player]
	local character, root = FishService.character(player)
	if session == nil or character == nil or root == nil or not session.alive or session.inHub then
		return false
	end
	if nearHub(root.Position, 0) or not inReach(predator, player, character, root, now) then
		return false
	end
	-- (a fish far above its level only while it's being bitten by it)
	local hit = predator.hitBy[player]
	if outclassed(predator.def, character) and not (hit and now - hit.at < 8) then
		return false
	end
	-- (a tethered hunter lets a fish go once it's out of reach of its hole)
	local style = styleOf(predator.def)
	local home = predator.home
	if home and (root.Position - home).Magnitude > (style.tether or 0) + predator.def.aggroRange * 0.6 then
		return false
	end
	-- (and every plain hunter lets a fish go once it's swum out of its water)
	if not predator.custom and not inRange(predator.def, root.Position, CHASE_SLACK) then
		return false
	end
	local leash = style.leash or Predators.loseRange
	return (root.Position - predator.position).Magnitude <= senseRange(predator, character) * leash
end

-- A fish its packmates are already on (it joins in)
local function packTarget(predator: Predator, now: number): Player?
	local pack = predator.pack
	if pack == nil then
		return nil
	end
	for _, mate in pack do
		local target = mate.target
		if mate ~= predator and mate.mode ~= "dead" and target and keepsHunting(predator, target, now) then
			return target
		end
	end
	return nil
end

-- How many hunt this fish now, leaving out `self` and its pack: a pack counts once,
-- and so does a boss (Config/Predators `mob`)
local function huntersOn(player: Player, self: Predator): number
	local seen: { [any]: boolean } = {}
	local count = 0
	for _, other in predators do
		if other.target ~= player or other == self or other.mode == "dead" then
			continue
		end
		if self.pack and other.pack == self.pack then
			continue
		end
		local unit: any = other.pack or other
		if not seen[unit] then
			seen[unit] = true
			count += 1
		end
	end
	return count
end

-- The fish worth hunting: alive, not safe, in range, big enough (or it bit us).
local function pickTarget(predator: Predator, now: number): Player?
	local def = predator.def
	local best: Player? = nil
	local bestScore = -math.huge
	for player, record in HuntService.sessions() do
		local character, root = FishService.character(player)
		if character == nil or root == nil or not record.alive or record.inHub then
			continue
		end
		if record.safeUntil > now or nearHub(root.Position, 0) then
			continue
		end
		if not inReach(predator, player, character, root, now) then
			continue
		end
		if not predator.custom and not inRange(def, root.Position, CHASE_SLACK) then
			continue
		end
		local distance = (root.Position - predator.position).Magnitude
		local hit = predator.hitBy[player]
		local provoked = hit ~= nil and now - hit.at < 8
		local range = senseRange(predator, character)
		if distance > (if provoked then range * Predators.loseRange else range) then
			continue
		end
		local length = character:GetAttribute("Length")
		local fishLength = if typeof(length) == "number" then length else 2
		if Size.raw(fishLength) < def.length * def.ignoreBelow and not provoked then
			continue
		end
		-- (it shies off a fish far above its level, leaves one still in the tutorial
		-- alone if it's a `spareLearners` hunter, and a tethered one only takes fish
		-- near its hole)
		if not provoked and outclassed(def, character) then
			continue
		end
		local style = styleOf(def)
		if style.spareLearners and learning(player) then
			continue
		end
		local home = predator.home
		if home and (root.Position - home).Magnitude > (style.tether or 0) + def.aggroRange * 0.5 then
			continue
		end
		-- (a fish that already has its share of hunters is left to them, unless it
		-- bit this one: no mobbing)
		if not provoked and huntersOn(player, predator) >= Predators.mob.hunters then
			continue
		end
		local score = fishLength + (if provoked then 50 else 0) - distance * 0.05
		if score > bestScore then
			best, bestScore = player, score
		end
	end
	return best
end

-- The nearest fish far above its level that's close (it shies off), or nil
local function shyFrom(predator: Predator): Vector3?
	local def = predator.def
	if def.level == nil or predator.custom then
		return nil
	end
	local best: Vector3? = nil
	local bestGap = def.aggroRange * 0.5
	for player, record in HuntService.sessions() do
		local character, root = FishService.character(player)
		if character == nil or root == nil or not record.alive or record.inHub then
			continue
		end
		local gap = (root.Position - predator.position).Magnitude
		if gap < bestGap and outclassed(def, character) then
			best, bestGap = root.Position, gap
		end
	end
	return best
end

-- The nearest fish within `mob.gap` that already has its share of hunters, or nil:
-- a roamer gives that hunt room
local function crowdFrom(predator: Predator): Vector3?
	local mob = Predators.mob
	local best: Vector3? = nil
	local bestGap = mob.gap
	for player, record in HuntService.sessions() do
		local _, root = FishService.character(player)
		if root == nil or not record.alive or record.inHub then
			continue
		end
		local gap = (root.Position - predator.position).Magnitude
		if gap < bestGap and huntersOn(player, predator) >= mob.hunters then
			best, bestGap = root.Position, gap
		end
	end
	return best
end

-- Room to itself (Config/Predators `spread.spacing`): which way a roamer eases off
-- the creatures too close to it (its packmates aside), stronger the closer they are
local function crowding(predator: Predator): Vector3
	local spacing = Predators.spread.spacing
	local push = Vector3.zero
	for _, other in predators do
		if other == predator or other.mode == "dead" or (predator.pack and other.pack == predator.pack) then
			continue
		end
		local away = predator.position - other.position
		local flat = Vector3.new(away.X, 0, away.Z)
		local gap = flat.Magnitude
		if gap < spacing and gap > 1e-3 then
			push += flat.Unit * (1 - gap / spacing)
		end
	end
	return push
end

-- How many others are making for this chum cloud (a pack counts once)
local function atChum(predator: Predator, chum: Vector3): number
	local seen: { [any]: boolean } = {}
	local count = 0
	for _, other in predators do
		if other == predator or other.mode ~= "roam" or (predator.pack and other.pack == predator.pack) then
			continue
		end
		if (other.waypoint - chum).Magnitude < 12 + other.def.length then
			local unit: any = other.pack or other
			if not seen[unit] then
				seen[unit] = true
				count += 1
			end
		end
	end
	return count
end

local function targetRoot(predator: Predator): (BasePart?, number)
	local target = predator.target
	if target == nil then
		return nil, 0
	end
	local character, root = FishService.character(target)
	if character == nil or root == nil then
		return nil, 0
	end
	local length = character:GetAttribute("Length")
	return root, if typeof(length) == "number" then length else 2
end

-- How far below the surface a creature's middle must stay, as a share of its length
-- (its back plus a dorsal fin)
local CEILING_SHARE = 0.3
-- How far ahead (seconds of travel) the ground is read, so a creature climbs over a
-- reef head before it reaches it instead of popping up on top of it
local LOOK_AHEAD = 1.4
-- Ground rising more than this ahead of a tethered hunter roaming by its hole is a
-- wall it turns along, not a rock it climbs (studs, or half its length if more)
local WALL_CLIMB = 12

-- The highest ground under a creature's body (tail to nose) and along the stretch
-- of water it's about to cross: the real ground (Shared/Ground: the Terrain and the
-- solid dressing), not the nominal floor, which reef heads, ridges, wrecks and
-- chimneys rise far above (owner, 2026-10-13: "the predator fish will phase through
-- the sand in the ground")
local function groundAround(
	predator: Predator,
	position: Vector3,
	velocity: Vector3
): (number, number, Vector3)
	local def = predator.def
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local facing = Vector3.new(predator.heading.X, 0, predator.heading.Z)
	local direction = if flat.Magnitude > 1
		then flat.Unit
		elseif facing.Magnitude > 1e-3 then facing.Unit
		else Vector3.xAxis
	local half = def.length * 0.5
	local under = -math.huge
	for _, along in { -half, 0, half } do
		local at = position + direction * along
		under = math.max(under, Ground.y(at.X, at.Z))
	end
	local reach = half + flat.Magnitude * LOOK_AHEAD
	local ahead = under
	for _, share in { 0.5, 1 } do
		local at = position + direction * (half + (reach - half) * share)
		ahead = math.max(ahead, Ground.y(at.X, at.Z))
	end
	return under, ahead, direction
end

-- The height above the ground a creature likes to keep: its roaming band's floor
-- while it roams, right down on it while it hunts (prey sits on the sand: held 2
-- studs higher, a Barracuda's mouth stayed ~4 studs over a fish resting on the
-- floor, out of its strike range, and it circled overhead; owner, 2026-10-17)
local function preferredGap(predator: Predator): number
	local def = predator.def
	local hard = def.length * BODY_HALF + BELLY_GAP
	if
		not predator.custom
		and (predator.mode == "hunt" or predator.mode == "windup" or predator.mode == "recover")
	then
		return hard
	end
	local lurk = styleOf(def).lurk
	if lurk and not predator.custom then
		return math.max(lurk[1], hard)
	end
	return math.max(def.depth[1] * 0.6, 5) + def.length * BODY_HALF
end

-- A boss's body when its def has none (Config/Predators `Swim`)
local BOSS_SWIM: PredatorsConfig.Swim = {
	turnAtSpeed = 0.7,
	comeTurn = 2.2,
	accel = 1.3,
	brake = 1,
	carry = 0.5,
	glide = 0.15,
	beat = 3,
}

-- Moves a predator toward a desired velocity and keeps it in the water column.
-- A plain predator swims like a fish (owner, 2026-10-13: "Their tracking should also
-- be more fluid and realistic"): it turns its body toward where it wants to go,
-- easing into the turn and turning slower at speed, and swims along its heading,
-- speeding up briskly and slowing gently, so it sweeps round in arcs instead of
-- sliding sideways at a target. A boss (`custom`) swims the same way with its own
-- heavier body (Config/Bosses `swim`; it slid sideways on a direct velocity model
-- until 2026-10-19, owner: "his actual movements are very stiff"): momentum, a
-- turning circle that widens with speed, a surge when a move asks for one. `direct`
-- is for the moves that throw the whole body (a breach's crash, a squid drawing back
-- to jet): the velocity goes where the move says and the body follows as it can.
-- Both read the real ground ahead and climb over it, and never sink into it.
local function steer(predator: Predator, desired: Vector3, dt: number, turnRate: number?, direct: boolean?)
	local def = predator.def
	-- Climb over the ground ahead before reaching it...
	local under, ahead, direction = groundAround(predator, predator.position, predator.velocity)
	local want = ahead + preferredGap(predator)
	-- ...unless it's a tethered hunter by its hole and the ground ahead is a wall (more
	-- than WALL_CLIMB over the ground at its middle): it slides along it instead and
	-- keeps to the ground it can rest on, hunting or not (PC 2026-10-22: Wolf Eels
	-- turning by their holes climbed a basalt column ~110 studs and stayed up there;
	-- 2026-10-23: facing its rock as it came round, one rose onto the rock's top,
	-- couldn't point down at a fish beside it and went hunt, recover, hunt without
	-- ever closing in)
	if predator.home then
		local middle = Ground.y(predator.position.X, predator.position.Z)
		local wall = middle + math.max(WALL_CLIMB, def.length * 0.5)
		if ahead > wall then
			local into = desired:Dot(direction)
			if into > 0 then
				desired -= direction * into
			end
			want = (if under <= wall then under else middle) + preferredGap(predator)
		end
	end
	if predator.position.Y < want then
		local climb = math.min((want - predator.position.Y) * 1.6, def.speed * 0.9)
		desired = Vector3.new(desired.X, math.max(desired.Y, climb), desired.Z)
	end
	if predator.custom and direct then
		predator.velocity = predator.velocity:Lerp(desired, 1 - math.exp(-dt * 5))
		if predator.velocity.Magnitude > 0.5 then
			predator.heading =
				rotateToward(predator.heading, predator.velocity, (turnRate or def.turnRate) * dt)
		end
	elseif predator.custom then
		local body = def.swim or BOSS_SWIM
		local wantSpeed = desired.Magnitude
		local wantDirection = if wantSpeed > 1e-3 then desired / wantSpeed else predator.heading
		local speedNow = math.max(predator.velocity:Dot(predator.heading), 0)
		-- Turns hardest nearly still (a pivot), widest flat out
		local fullSpeed = math.clamp(speedNow / math.max(def.speed, 1), 0, 1)
		local keep = 1.4 + (body.turnAtSpeed - 1.4) * fullSpeed
		local rate = (turnRate or def.turnRate) * keep
		local angle = math.acos(math.clamp(predator.heading:Dot(wantDirection), -1, 1))
		local turn = math.min(rate * dt, angle * (1 - math.exp(-dt * 6)))
		predator.heading = rotateToward(predator.heading, wantDirection, turn)
		-- Speeds up on its strokes (a surge when a move asks for far more), coasts down,
		-- and slows through a hard turn
		-- (in a tell it flares its fins and holds off, so the warning is a fair one: it
		-- had coasted half-way to the fish while its eyes flashed)
		local goal = wantSpeed * (1 - 0.3 * math.clamp(angle / math.pi, 0, 1))
		local change = if goal > speedNow
			then def.speed * body.accel * (if goal > def.speed * 1.4 then 2.5 else 1)
			else def.speed * body.brake * (if predator.mode == "windup" then 4 else 1)
		local speed = speedNow + math.clamp(goal - speedNow, -change * dt, change * dt)
		-- (its bulk carries a little way on through a turn: no slide, no snap)
		predator.velocity = predator.velocity:Lerp(predator.heading * speed, 1 - math.exp(-dt * 4))
	else
		local wantSpeed = desired.Magnitude
		local wantDirection = if wantSpeed > 1e-3 then desired / wantSpeed else predator.heading
		local speedNow = predator.velocity.Magnitude
		-- Turns slower the faster it goes (each style keeps its own share at full
		-- speed: a tracker turns wide, an ambusher wider still in a burst), and eases in
		-- as it lines up (no snap)
		local style = styleOf(def)
		local bursting = predator.burstUntil > Timing.clock()
		local fullSpeed = math.clamp(speedNow / math.max(def.speed, 1), 0, 1)
		local keep = if bursting then style.burstTurn or 1 else 1.25 + (style.turnAtSpeed - 1.25) * fullSpeed
		local rate = (turnRate or def.turnRate) * keep
		local angle = math.acos(math.clamp(predator.heading:Dot(wantDirection), -1, 1))
		local turn = math.min(rate * dt, angle * (1 - math.exp(-dt * 5)))
		predator.heading = rotateToward(predator.heading, wantDirection, turn)
		-- Swims along its heading: slows in a hard turn, speeds up briskly, eases off.
		-- With its jaw open for a strike it flares its fins and pulls up short instead
		-- (it had slid ~15 studs past a fish that sat still and missed it)
		local goal = wantSpeed * (1 - 0.35 * math.clamp(angle / math.pi, 0, 1))
		local striking = predator.mode == "windup"
		local change = if goal > speedNow
			then def.speed * (if bursting then 6 else 1.6)
			else def.speed * (if striking then style.tellBrake or Predators.strike.brake else 0.9)
		local speed = speedNow + math.clamp(goal - speedNow, -change * dt, change * dt)
		-- (striking, it swims exactly as braked, so where its tell begins holds true)
		predator.velocity = if striking
			then predator.heading * speed
			else predator.velocity:Lerp(predator.heading * speed, 1 - math.exp(-dt * 6))
	end
	local position = predator.position + predator.velocity * dt
	-- Never out past the map's wall (the squid chased a fish 4,700 studs out,
	-- playtest 2026-10-10)
	local hub = World.hub.center
	local out = Vector3.new(position.X - hub.X, 0, position.Z - hub.Z)
	local limit = World.boundsRadius - def.length * 0.5
	if out.Magnitude > limit then
		local outward = out.Unit
		position = Vector3.new(hub.X + outward.X * limit, position.Y, hub.Z + outward.Z * limit)
		local along = predator.velocity:Dot(outward)
		if along > 0 then
			predator.velocity -= outward * along
		end
	end
	-- ...and never into the hub's keep-out: the cave, its tunnels and the sand round
	-- them (Predators.hubKeepOut)
	local away = Vector3.new(position.X - hub.X, 0, position.Z - hub.Z)
	local keep = Predators.hubKeepOut + def.length * 0.5
	if away.Magnitude < keep then
		local outward = if away.Magnitude > 1e-3 then away.Unit else Vector3.xAxis
		position = Vector3.new(hub.X + outward.X * keep, position.Y, hub.Z + outward.Z * keep)
		local into = predator.velocity:Dot(outward)
		if into < 0 then
			predator.velocity -= outward * into
		end
	end
	-- Never into the ground: the belly stays over the highest ground under the body.
	-- A boss also keeps its old height off the nominal floor, which its fight was
	-- tuned on (the Megalodon stays up in the blue; a fish on the sand is out of reach)
	local under, _, direction = groundAround(predator, position, predator.velocity)
	-- A tethered hunter by its hole meets a tall rock as a wall: its nose (or tail)
	-- stops against it instead of the whole body being lifted onto its top (PC
	-- 2026-10-22: a Wolf Eel turning by its hole was set on a basalt column ~110
	-- studs up in one step)
	if predator.home and not predator.custom then
		local middle = Ground.y(position.X, position.Z)
		local wall = middle + math.max(WALL_CLIMB, def.length * 0.5)
		if under > wall then
			local half = def.length * 0.5
			local step = position - predator.position
			under = middle
			for _, side in { 1, -1 } do
				local at = position + direction * half * side
				local ground = Ground.y(at.X, at.Z)
				if ground <= wall then
					under = math.max(under, ground)
				else
					-- (no further that way)
					local into = Vector3.new(step.X, 0, step.Z):Dot(direction * side)
					if into > 0 then
						position -= direction * side * into
					end
					local push = predator.velocity:Dot(direction * side)
					if push > 0 then
						predator.velocity -= direction * side * push
					end
				end
			end
		end
	end
	local floor = under + def.length * BODY_HALF + BELLY_GAP
	if predator.custom then
		floor = math.max(floor, Seafloor.y(position.X, position.Z) + math.max(def.depth[1] * 0.6, 5))
	end
	-- The surface is a ceiling for the whole body, not just its middle: a big
	-- creature's back and fin sit well above its axis (playtest 2026-10-10: the
	-- Megalodon chased a fish at the surface, its middle stopped 12 studs under, and
	-- its back and fin broke through the surface sheet)
	local ceiling = World.surfaceY - math.max(12, def.length * CEILING_SHARE)
	local y = math.clamp(position.Y, math.min(floor, ceiling), ceiling)
	if y >= ceiling and predator.velocity.Y > 0 then
		predator.velocity = Vector3.new(predator.velocity.X, 0, predator.velocity.Z)
	end
	if y <= floor + 0.05 and predator.velocity.Y < 0 then
		predator.velocity = Vector3.new(predator.velocity.X, 0, predator.velocity.Z)
	end
	-- ...and its nose doesn't dig in: near the ground it can only point down so far
	local reachDown = def.length * 0.45
	local noseAt = position + predator.heading * reachDown
	local noseGround = Ground.y(noseAt.X, noseAt.Z)
	local roomDown = (y - noseGround - def.length * BODY_HALF * 0.5 - BELLY_GAP) / math.max(reachDown, 1)
	if predator.heading.Y < 0 and roomDown < 1 and -predator.heading.Y > math.max(roomDown, 0) then
		local flat = Vector3.new(predator.heading.X, 0, predator.heading.Z)
		local tilt = -math.max(roomDown, 0)
		local level = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
		predator.heading = (level * math.sqrt(math.max(1 - tilt * tilt, 0)) + Vector3.yAxis * tilt).Unit
	end
	-- ...and a plain predator never stands on its nose or tail (MAX_PITCH)
	if not predator.custom and math.abs(predator.heading.Y) > MAX_PITCH then
		local flat = Vector3.new(predator.heading.X, 0, predator.heading.Z)
		local moving = Vector3.new(predator.velocity.X, 0, predator.velocity.Z)
		local level = if flat.Magnitude > 1e-3
			then flat.Unit
			elseif moving.Magnitude > 1e-3 then moving.Unit
			else Vector3.xAxis
		local tilt = math.clamp(predator.heading.Y, -MAX_PITCH, MAX_PITCH)
		predator.heading = (level * math.sqrt(1 - tilt * tilt) + Vector3.yAxis * tilt).Unit
	end
	-- ...and its nose and tail stay under too: near the surface it can only tilt so far
	local reach = def.length * 0.45
	local room = (World.surfaceY - 4 - def.length * 0.09 - y) / math.max(reach, 1)
	if room < 1 and math.abs(predator.heading.Y) > room then
		local flat = Vector3.new(predator.heading.X, 0, predator.heading.Z)
		local tilt = math.clamp(predator.heading.Y, -math.max(room, 0), math.max(room, 0))
		local level = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
		predator.heading = (level * math.sqrt(math.max(1 - tilt * tilt, 0)) + Vector3.yAxis * tilt).Unit
	end
	predator.position = Vector3.new(position.X, y, position.Z)
end

-- How close (studs from its mouth to the fish's middle) a predator holds its open
-- jaw while it telegraphs a bite
-- An ambusher lines up on its fish this well (cosine of the angle) before it bursts
-- (a style's `burstFacing`)
local BURST_FACING = 0.92

local function holdGap(def: Def, fishLength: number): number
	return def.biteReach * Predators.strike.hold + fishLength * 0.5
end

-- How far its snap reaches when the tell ends: its bite reach (× the style's `snap`),
-- the fish's half-length and the room the server's view of a moving fish needs (it
-- trails its owner's)
local function strikeReach(def: Def, fishLength: number): number
	return def.biteReach * (styleOf(def).snap or 1.6) + fishLength * 0.5 + Size.topSpeed(fishLength) * 0.1
end

local function payOut(predator: Predator, killer: Player?, swallowed: boolean?)
	local def = predator.def
	local total = 0
	for _, record in predator.hitBy do
		total += record.damage
	end
	if total <= 0 then
		return
	end
	for player, record in predator.hitBy do
		if player.Parent == nil then
			continue
		end
		local share = math.max(record.damage / total, 0.1)
		if player == killer then
			share += 0.1
		end
		local data = DataService.get(player)
		if data == nil then
			continue
		end
		-- A fish well above its level gets little for it (Config/Predators `fight`
		-- `pay`), so farming low predators doesn't pay
		local pay = 1
		local level = def.level
		if level then
			local over = strength(level, levelOf((FishService.character(player))))
			pay = if over < 1 then math.max(over ^ fight.pay, fight.payMin) else 1
		end
		-- (a share of the fish's own full Haul: Config/Predators `loot`)
		local gained = HuntService.shown(player, HuntService.hauls(player, def.loot.hauls * share * pay)) -- (as food)
		local dna = math.floor(def.loot.dna * share * pay + 0.5)
		if dna > 0 then
			HuntService.giveDna(player, predator.position, dna)
		end
		EconomyService.earnCoral(player, def.loot.coral * share * pay)
		Events.ate:fire(player, 1)
		Net.notify(
			player,
			if player == killer and swallowed
				then `You swallowed the {def.name} whole! +{Format.haul(gained)} Haul`
				elseif player == killer then `You killed the {def.name}! +{Format.haul(gained)} Haul`
				else `The {def.name} is dead · your share: +{Format.haul(gained)} Haul`,
			"good"
		)
	end
end

-- Damage to a creature from a player (a bite, or a puffed fish's spines), counted
-- toward that player's share of the kill
local function hurt(
	predator: Predator,
	player: Player,
	damage: number,
	at: Vector3,
	now: number,
	swallowed: boolean?
)
	local def = predator.def
	predator.health -= damage
	local record: { damage: number, at: number } = predator.hitBy[player] or { damage = 0, at = now }
	record.damage += damage
	record.at = now
	predator.hitBy[player] = record
	Net.predatorEvent("hurt", predator.index, {
		by = player.UserId,
		damage = damage,
		health = math.max(predator.health / predator.maxHealth, 0),
		x = at.X,
		y = at.Y,
		z = at.Z,
	})
	if predator.health <= 0 then
		predator.mode = "dead"
		predator.respawnAt = now + def.respawn
		predator.target = nil
		predator.burstUntil = 0
		Net.predatorEvent(
			"died",
			predator.index,
			{ by = player.UserId, gone = predator.custom == true, swallowed = swallowed == true }
		)
		if not predator.custom then
			payOut(predator, player, swallowed)
		end
		PredatorService.died:fire(predator, player)
		if predator.custom then
			predators[predator.index] = nil
		end
	end
end

-- Stuns a plain predator: it drops its fish and any tell (no bite), drifts to a stop,
-- can't start a tell, then roams again
local function stunOne(predator: Predator, seconds: number, now: number)
	predator.mode = "stunned"
	predator.stunUntil = math.max(predator.stunUntil, now + seconds)
	predator.target = nil
	predator.burstUntil = 0
	Net.predatorEvent("stunned", predator.index, { seconds = seconds })
end

-- An ambusher's burst is over: it's out of breath (no tell, no bite) for a while. A
-- burst that missed counts against that fish; after a few it gives the fish up.
local function winded(predator: Predator, failed: boolean, now: number)
	local style = styleOf(predator.def)
	predator.burstUntil = 0
	predator.mode = "recover"
	predator.modeUntil = now + (style.winded or 3)
	predator.strikeAt = now
	predator.veer = 0
	local victim = predator.target
	if victim == nil then
		return
	end
	if not failed then
		predator.fails[victim] = nil
		-- (a bite that landed sates it a little longer: `sated`)
		predator.modeUntil += style.sated or 0
		return
	end
	local fails = (predator.fails[victim] or 0) + 1
	predator.fails[victim] = fails
	if fails >= (style.giveUp or math.huge) then
		predator.fails[victim] = nil
		predator.ignore[victim] = now + (style.forget or 20)
		predator.target = nil
	end
end

-- A harrier's nip landed: after `nips` of them (each within `forget` s of the last)
-- it lets the fish go for `forget` s and says so
local function nipped(predator: Predator, victim: Player, now: number)
	local style = styleOf(predator.def)
	local limit = style.nips
	if limit == nil then
		return
	end
	local forget = style.forget or 20
	local last = predator.nipped[victim]
	local count = if last and now - last.at <= forget then last.count + 1 else 1
	if count < limit then
		predator.nipped[victim] = { count = count, at = now }
		return
	end
	predator.nipped[victim] = nil
	predator.ignore[victim] = now + forget
	predator.target = nil
	Net.notify(victim, `The {predator.def.name} has had its fun and leaves you be`, "info")
end

-- How far out it likes to start a run at a fish: room to reach speed and open its jaw
local function runInOf(def: Def): number
	return def.length * 1.5 + def.speed * def.telegraph * 0.8
end

-- A way to swim that takes it round `center` at `radius` (out when it's inside, in
-- when it's outside, toward the centre's depth), circling `spin` (+1 / -1; nil: the
-- way it's already going, its peel side to break a tie)
local function orbitWay(predator: Predator, center: Vector3, radius: number, spin: number?): Vector3
	local away = predator.position - center
	local flat = Vector3.new(away.X, 0, away.Z)
	local r = flat.Magnitude
	local radial = if r > 1e-3 then flat / r else Vector3.new(predator.heading.X, 0, predator.heading.Z).Unit
	local tangent = Vector3.new(-radial.Z, 0, radial.X)
	local turn = spin or (if predator.heading:Dot(tangent) + 0.3 * predator.peel >= 0 then 1 else -1)
	local pull = math.clamp((radius - r) / math.max(radius, 1), -1, 1) * 1.6
	local rise = math.clamp((center.Y - predator.position.Y) / math.max(radius, 1), -0.6, 0.6)
	local way = tangent * turn + radial * pull + Vector3.yAxis * rise
	return if way.Magnitude > 1e-3 then way.Unit else predator.heading
end

-- Burst and glide (owner, 2026-10-19: "his actual movements are very stiff"): × its
-- pace at `now`, a few strong strokes then a coast, over a `beat`-second cycle of its
-- own phase. Averages 1 (the strokes' 45% of the cycle carry the coast).
local function rhythm(predator: Predator, now: number, glide: number, beat: number): number
	local t = (now / math.max(beat, 0.5) + predator.index * 0.37) % 1
	local stroke = if t < 0.45 then math.sin(t / 0.45 * math.pi) else 0
	return math.clamp(1 + glide * (stroke * 3.5 - 1), 1 - glide, 1 + 1.6 * glide)
end

-- How it opens a hunt on a fish it has just taken (Config/Predators `circle`, `under`,
-- `feint`): circling in, up from below, or straight in
local function chooseApproach(predator: Predator, now: number)
	local style = styleOf(predator.def)
	local roll = rng:NextNumber()
	local circle, under = style.circle or 0, style.under or 0
	if roll < circle then
		predator.approach = "circle"
		predator.approachUntil = now + (style.circleSeconds or 2.5)
		predator.orbit = if rng:NextNumber() < 0.5 then -1 else 1
	elseif roll < circle + under then
		predator.approach = "under"
	else
		predator.approach = "direct"
	end
	predator.feintLeft = rng:NextNumber() < (style.feint or 0)
end

-- Off it goes after a strike, a feint or a fish inside its turning circle: it carries
-- through `carry` s (swerving `veer` radians to its `peel` side), then comes round
local function startRecover(predator: Predator, now: number, seconds: number, carried: boolean, veer: number?)
	predator.mode = "recover"
	predator.modeUntil = now + seconds
	predator.strikeAt = if carried then now else now - (styleOf(predator.def).carry or 0.4)
	predator.veer = veer or 0
	predator.peel = if rng:NextNumber() < 0.5 then -1 else 1
end

local function simulate(predator: Predator, dt: number, now: number)
	local def = predator.def
	local style = styleOf(def)
	local turnRate: number? = nil
	if predator.mode == "dead" then
		if now >= predator.respawnAt then
			spawn(predator)
		end
		return
	end
	-- Stunned (a Lantern Flash, a puffed fish's spines): it drifts to a stop, then roams
	if predator.mode == "stunned" then
		if now < predator.stunUntil then
			steer(predator, Vector3.zero, dt)
			return
		end
		predator.mode = "roam"
		predator.waypoint = waypointFor(predator)
		predator.waypointUntil = now + 12
	end
	-- Keep or drop its fish. One that burrows, slips into kelp it's too big for, gets
	-- out of reach or dies is lost, and a tell on it is called off (no bite).
	if predator.mode ~= "recover" then
		local target = predator.target
		if target and not keepsHunting(predator, target, now) then
			if predator.mode == "windup" then
				Net.predatorEvent("lost", predator.index, {})
			end
			if style.kind == "ambush" and predator.burstUntil > 0 then
				winded(predator, true, now)
			elseif predator.mode == "windup" then
				startRecover(predator, now, 1, true)
			end
			predator.target = nil
		end
		local mode = modeOf(predator)
		if mode ~= "windup" and mode ~= "recover" then
			if predator.target == nil then
				predator.target = packTarget(predator, now) or pickTarget(predator, now)
			end
			predator.mode = if predator.target then "hunt" else "roam"
		end
		-- A fish it has just taken: how it'll come in
		if predator.target and predator.target ~= predator.approachFor then
			predator.approachFor = predator.target
			chooseApproach(predator, now)
		end
	end

	local desired: Vector3
	local fast = hunters(predator)
	local speed = def.speed * fast
	if predator.mode == "roam" then
		predator.burstUntil = 0
		local reached = (predator.waypoint - predator.position).Magnitude < 8 or now > predator.waypointUntil
		-- Chum in the water draws it in (Config/Chum `lure`), looked for every second so
		-- a fresh cloud turns it at once (PC overnight 2026-10-14: checked only at each
		-- new waypoint, every 6–12 s, a Barracuda took ~15 s to arrive); else a new
		-- spot to roam
		if reached or now >= predator.lureAt then
			predator.lureAt = now + 1
			local chum = ChumService.nearest(predator.position, Config.Chum.lure)
			-- (no more than `mob.chum` to one cloud)
			if
				chum
				and not nearHub(chum, def.length)
				and inRange(def, chum)
				and atChum(predator, chum) < Predators.mob.chum
			then
				if reached or (predator.waypoint - chum).Magnitude > def.length * 1.5 then
					local around = rng:NextUnitVector() * def.length * 0.6
					predator.waypoint = chum + Vector3.new(around.X, math.abs(around.Y) + 3, around.Z)
					predator.waypointUntil = now + 6
				end
			elseif reached then
				predator.waypoint = waypointFor(predator)
				predator.waypointUntil = now + 12
			end
		end
		-- A lazy weave and a slow swell in pace, so a cruising fish doesn't fly a ruler
		local phase = now * 0.35 + predator.index * 1.7
		local toWaypoint = (predator.waypoint - predator.position).Unit
		local weave = CFrame.fromAxisAngle(Vector3.yAxis, math.sin(phase) * 0.3)
		desired = (weave:VectorToWorldSpace(toWaypoint) + Vector3.yAxis * math.sin(phase * 0.6) * 0.08).Unit
			* speed
			* (style.roam or Predators.roamSpeed)
			* rhythm(predator, now, math.max(style.glide or 0.2, 0.2), style.beat or 2.6)
		-- It keeps its distance from the others (not a tethered one: its hole holds it)
		if predator.home == nil then
			local push = crowding(predator)
			if push.Magnitude > 1e-3 then
				desired = (desired.Unit + push * 1.5).Unit * desired.Magnitude
			end
		end
		-- A pack member keeps station by its leader (it catches up when behind)
		local leader = leaderOf(predator)
		if leader and leader ~= predator then
			local toStation = stationOf(predator, leader) - predator.position
			local far = toStation.Magnitude
			if far > 3 then
				local pace = speed * (style.roam or Predators.roamSpeed) * math.clamp(far / 20, 0.6, 1.6)
				desired = toStation.Unit * pace
			end
		end
		-- ...and it shies off a fish far above its level (Config/Predators `fight`) and
		-- gives room to a fish that's already being hunted (`mob`)
		local bully = shyFrom(predator) or crowdFrom(predator)
		if bully then
			local away = predator.position - bully
			away = Vector3.new(away.X, math.max(away.Y, 0) * 0.3, away.Z)
			if away.Magnitude > 1e-3 then
				desired = away.Unit * speed * 0.7
			end
		end
	elseif predator.mode == "recover" then
		-- After a strike it carries on through, then comes round hard (owner,
		-- 2026-10-19: "If he misses the player he just slowly turns around and goes at
		-- them again. It needs to feel like a real predator"): a fast banked turn onto
		-- a loop round the fish, a run-in's length out on the side it peeled to, until
		-- its bite is ready, then it turns in for a fresh pass from a new angle. (Aimed
		-- straight back it arrived before its bite was ready, or too fast to pull up,
		-- and circled the fish inside its own turning circle.) An ambusher out of breath
		-- glides round its loop slowly, facing in. With no fish it peels off and loops
		-- away.
		local root = targetRoot(predator)
		local since = now - predator.strikeAt
		local ready = now >= predator.modeUntil
		local winded = style.kind == "ambush" and not ready
		local facingFish, flatGap = 1, math.huge
		local runIn = runInOf(def)
		if root == nil or predator.target == nil then
			local away = CFrame.fromAxisAngle(Vector3.yAxis, -predator.peel * 0.7)
			desired = (away:VectorToWorldSpace(predator.heading) + Vector3.yAxis * 0.15).Unit
				* def.speed
				* (style.recover or 0.8)
		elseif since < (style.carry or 0.4) then
			local off = CFrame.fromAxisAngle(Vector3.yAxis, -predator.peel * predator.veer)
			desired = off:VectorToWorldSpace(predator.heading)
				* def.speed
				* (if winded then style.recover or 0.8 else 1)
		else
			local toFish = root.Position - predator.position
			flatGap = Vector3.new(toFish.X, 0, toFish.Z).Magnitude
			facingFish = if toFish.Magnitude > 1e-3 then predator.heading:Dot(toFish.Unit) else 1
			-- (it turns in inside the loop, so it's lined up before it runs in)
			local way = if ready and flatGap >= runIn * 0.6
				then toFish.Unit
				else orbitWay(predator, root.Position, runIn, nil)
			desired = way * def.speed * (style.comePace or 0.8)
			turnRate = def.turnRate * (style.comeTurn or 2)
		end
		-- Hunts again once its bite is ready and it's round with room to run in (or
		-- it has had long enough)
		if
			ready and (root == nil or (flatGap >= runIn * 0.5 and facingFish >= 0.85))
			or now >= predator.modeUntil + 3
		then
			predator.mode = if predator.target then "hunt" else "roam"
		end
	else
		local root, fishLength = targetRoot(predator)
		if root == nil then
			predator.mode = "roam"
			desired = predator.velocity
		else
			-- The strike (owner, 2026-10-17: "Predator fish have horrible aim and are
			-- barely a threat; even sitting still they can't hit me"): it closes in,
			-- opens its jaw (the tell) and glides in to hold it just off the fish, timed
			-- to arrive as the tell ends, then snaps. A fish that stays put or dawdles
			-- is bitten; one that dashes off during the tell outruns the glide (`follow`)
			-- and the snap's reach. Each style closes in its own way (Config/Predators
			-- `style`).
			local strike = Predators.strike
			local mouth = mouthOf(predator)
			local toFish = root.Position - mouth
			local gap = toFish.Magnitude
			local hold = holdGap(def, fishLength)
			local fishVelocity = root.AssemblyLinearVelocity
			-- How fast the fish is getting away from its jaw
			local fleeing = if gap > 1e-3 then math.max(fishVelocity:Dot(toFish / gap), 0) else 0
			-- Lead the fish by the time it takes to close the gap, and keep the aim off
			-- the ground (a fish on the sand is struck from just above it)
			-- (in a burst it leads the fish by `burstLead` of the time to close: a sprinter
			-- reads a fish's swim, so a juke has to be a real one)
			local lead = if predator.burstUntil > now
				then math.clamp(gap / math.max(speed * (style.burst or 1), 1), 0, 0.6) * (style.burstLead or 0)
				elseif predator.mode == "windup" then math.clamp(predator.modeUntil - now, 0, 0.5)
				else math.clamp(gap / math.max(speed, 1), 0, 1.2)
			local aim = root.Position + fishVelocity * lead
			-- A pack's flankers swing out wide to either side of the fish and come in
			-- from there, while the leader drives straight at it
			local leader = leaderOf(predator)
			local pack = style.pack
			if pack and leader and leader ~= predator and gap > pack.spread * 2.2 then
				local across = Vector3.new(-toFish.Z, 0, toFish.X)
				local side = if predator.role % 2 == 0 then 1 else -1
				if across.Magnitude > 1e-3 then
					aim += across.Unit * side * pack.spread * math.clamp(gap / (pack.spread * 4), 0.5, 1.5)
				end
			end
			local aimFloor = Ground.y(aim.X, aim.Z) + def.length * BODY_HALF + BELLY_GAP
			aim = Vector3.new(aim.X, math.max(aim.Y, aimFloor), aim.Z)
			local toTarget = aim - mouth
			local direction = if toTarget.Magnitude > 1e-3 then toTarget.Unit else predator.heading
			local facing = predator.heading:Dot(direction)
			local ambush = style.kind == "ambush"
			-- An ambusher's burst ran out without a tell: out of breath
			if
				ambush
				and predator.mode == "hunt"
				and predator.burstUntil > 0
				and now >= predator.burstUntil
			then
				winded(predator, true, now)
				desired = predator.heading * def.speed * (style.recover or 0.8)
			else
				local bursting = predator.burstUntil > now
				-- The fastest it keeps up during a tell: a burst's pace, else `tellFollow`
				local cap = def.speed * (if bursting then style.burst or 1 else style.tellFollow)
				if predator.mode == "hunt" then
					-- A lure draws in the fish it stalks (Config/Predators `lure`): a gentle
					-- pull toward its glowing bulb, and a word to the fish the first time
					local lure = style.lure
					if lure and gap <= lure.radius and gap > hold then
						local victim = predator.target :: Player
						Net.shove(victim, -toFish / math.max(gap, 1e-3) * lure.pull * dt)
						if now - predator.luredAt > 5 then
							predator.luredAt = now
							Net.predatorEvent("luring", predator.index, { target = victim.UserId })
						end
					end
					-- Where the tell starts: it glides in from there to arrive as it ends,
					-- allowing for a fish getting away, and never closer than it can pull up
					-- in (a heavy tracker opens its jaw further out)
					local tell = def.telegraph
					local decel = def.speed * (style.tellBrake or strike.brake)
					local moving = predator.velocity.Magnitude
					local pullsUp = if moving <= decel * tell
						then moving * moving / (2 * decel)
						else moving * tell - decel * tell * tell / 2
					-- (plus a tick's travel: it's only checked ten times a second)
					local glide = math.max(cap - fleeing, 0) * tell * strike.closing
					local engage = hold + math.max(glide, pullsUp - fleeing * tell) + moving * dt
					local pace: number
					if bursting then
						pace = speed * (style.burst or 1)
					elseif style.kind == "plain" then
						-- Stalks in at a cruise, then sprints the last stretch
						pace = speed * (0.75 + 0.45 * (1 - math.clamp((gap - 10) / 35, 0, 1)))
					else
						pace = speed * style.chase
					end
					-- Close in with the fish off to one side, it slows to turn (at full
					-- speed it circled it); a tracker hardly does (it turns wide)
					if not bursting and gap < engage * 2.5 then
						local floor = style.slowsToTurn or 0.35
						pace *= floor + (1 - floor) * math.clamp((facing - 0.2) / 0.7, 0, 1)
					end
					-- How it comes in on a fish that isn't running (chosen as it took the
					-- fish, Config/Predators `circle`, `under`): circling round it and
					-- tightening, or stalking up from below it for a lunge; never into a tell
					-- while it's circling (its jaws aren't on the fish)
					local way = direction
					local circling = false
					local calm = not bursting and fleeing < speed * 0.3
					if calm and predator.approach == "circle" and now < predator.approachUntil then
						local runIn = runInOf(def)
						local out = Vector3.new(predator.position.X - aim.X, 0, predator.position.Z - aim.Z)
						if out.Magnitude > runIn * 0.9 then
							-- (round it, the loop tightening to a run-in's length as time runs out)
							circling = true
							local left = (predator.approachUntil - now) / (style.circleSeconds or 2.5)
							local radius = math.max(runIn, out.Magnitude * (0.8 + 0.15 * left))
							way = orbitWay(predator, aim, radius, predator.orbit)
						end
					elseif calm and predator.approach == "under" and gap > engage * 1.3 then
						local depth = math.min(style.underDepth or 20, (gap - engage * 1.3) * 0.5)
						local below = aim - Vector3.yAxis * depth
						below = Vector3.new(below.X, math.max(below.Y, aimFloor), below.Z)
						local toBelow = below - mouth
						way = if toBelow.Magnitude > 1e-3 then toBelow.Unit else direction
					end
					-- Burst and glide while it cruises in (a straight chase is flat out)
					if calm and gap > engage * 2.5 then
						pace *= rhythm(predator, now, style.glide or 0, style.beat or 2.5)
					end
					desired = way * pace
					-- A fish close beside or behind it is inside its turning circle (it only
					-- circles it): it swims on out and comes round hard for another pass. A
					-- `whip` hunter (the Barracuda) snaps its body round on the spot instead,
					-- nearly stopping, and faces the fish in a fraction of a second (owner,
					-- 2026-10-20: "Easily killed a barracuda at lvl 16 by just going back and
					-- forth at it")
					-- (a tethered hunter has no room to swim out from its hole: it snaps round
					-- in it, PC 2026-10-23)
					local whip = style.whip or (if predator.home then TETHER_WHIP else nil)
					local whipping = whip ~= nil and not bursting and gap < def.length * 2.5 and facing < 0.7
					if whipping then
						-- (a long tethered body pivots nearly on the spot: swimming at the
						-- fish carried its middle onto it and the jaws past it)
						local pace = if style.whip then style.slowsToTurn or 0.35 else TETHER_PIVOT
						desired = direction * speed * pace
						turnRate = def.turnRate * (whip :: number)
					elseif not bursting and gap < def.length * 2 and facing < 0.2 then
						startRecover(predator, now, 1, false)
					elseif
						-- A feint (once a hunt, `feint`): it swerves off a run at a fish that
						-- isn't running, no tell, and comes round again
						calm
						and predator.feintLeft
						and predator.mode == "hunt"
						and gap < engage * 2.2
						and gap > engage * 1.3
						and facing > 0.85
					then
						predator.feintLeft = false
						startRecover(predator, now, 1.4, true, 0.9)
					end
					local sees = false
					-- (a gulper opens its mouth from further out: its tell sucks the fish in)
					local gulp = style.gulp
					local tellAt = if gulp then math.max(engage, gulp.reach * 0.65) else engage
					-- (an ambusher already this close snaps at once, no burst needed)
					local snapsNow = ambush and gap <= tellAt
					if ambush and not bursting and not snapsNow then
						-- An ambusher stalks in low and slow, then bursts from close
						if
							gap <= (style.trigger or 0)
							and facing >= (style.burstFacing or BURST_FACING)
							and Ground.sees(mouth, root.Position, fishLength * 0.3)
						then
							predator.burstUntil = now + (style.burstSeconds or 1.5)
							Net.predatorEvent("burst", predator.index, {
								target = (predator.target :: Player).UserId,
								seconds = style.burstSeconds,
							})
						end
					elseif
						predator.mode == "hunt"
						and not circling
						and gap <= tellAt
						and facing >= (style.tellFacing or strike.facing)
					then
						if not bursting and not ambush and gap < engage * 0.7 and fleeing < speed * 0.3 then
							-- Lined up only once it's far too close and fast to pull up: it
							-- swims on past and comes round for a proper run (a tell from
							-- here only overshot the fish; an ambusher stalks in slow enough
							-- to pull up and snaps)
							startRecover(predator, now, 0.5, false)
						else
							sees = Ground.sees(mouth, root.Position, fishLength * 0.3)
						end
					end
					if sees then
						predator.mode = "windup"
						predator.modeUntil = now + def.telegraph
						predator.gulpFree = false
						-- (and it stops speeding up as it opens its jaw)
						desired = direction * math.min(desired.Magnitude, moving)
						-- (a burst carries it through a tell begun in it)
						if bursting then
							predator.burstUntil = math.max(predator.burstUntil, predator.modeUntil + dt)
						end
						Net.predatorEvent("windup", predator.index, {
							target = (predator.target :: Player).UserId,
							seconds = def.telegraph,
						})
					end
				else -- windup
					-- Jaw open: glides in to hold its mouth just off the fish as the tell
					-- ends, keeping up with a fish getting away up to `cap`, still turning
					local left = math.max(predator.modeUntil - now, dt)
					local pace = math.clamp((gap - hold) / left + fleeing, 1, math.max(cap, 1))
					-- Past `commit` of its tell it has committed to its line and only
					-- lunges along it, so a juke timed well escapes (Config/Predators)
					local committed = style.commit ~= nil
						and def.telegraph - (predator.modeUntil - now)
							>= def.telegraph * (style.commit :: number)
					desired = (if committed then predator.heading else direction) * pace
					-- A gulper's open mouth sucks the fish in (Config/Predators `gulp`) until
					-- it swims off faster than it can pull (a Dash breaks it)
					local gulp = style.gulp
					if gulp and not predator.gulpFree and gap <= gulp.reach then
						if fleeing > Size.topSpeed(fishLength) * gulp.breakAt then
							predator.gulpFree = true
						else
							Net.shove(
								predator.target :: Player,
								-toFish / math.max(gap, 1e-3) * gulp.pull * dt
							)
						end
					end
					if now >= predator.modeUntil then
						local victim = predator.target :: Player
						-- In front of its jaws (a fish that turned off to the side of its head as
						-- it came on is missed: it overshoots), and not through rock (a fish
						-- under an arch or in a reef's tunnel is safe)
						local ahead = gap <= 1
							or predator.heading:Dot(toFish / math.max(gap, 1e-3))
								>= (style.cone or strike.cone)
						local hit = gap <= strikeReach(def, fishLength)
							and ahead
							and Ground.sees(mouth, root.Position, fishLength * 0.3)
						local puffed = false
						if hit then
							local character = FishService.character(victim)
							puffed = character ~= nil and isPuffed(character, now)
							-- (by level: harder on a fish under its level, a nip on one above)
							local fraction = def.biteFraction
								* theirBite(def, character)
								* (if puffed then Predators.puffDamage else 1)
							HuntService.damage(victim, fraction, def.name)
						end
						Net.predatorEvent(
							"bite",
							predator.index,
							{ hit = hit, x = mouth.X, y = mouth.Y, z = mouth.Z }
						)
						-- The strike carries it on through, and it peels off to one side and
						-- comes round
						predator.velocity += predator.heading * def.speed * 0.5
						if ambush then
							predator.peel = if rng:NextNumber() < 0.5 then -1 else 1
							winded(predator, not hit, now)
						else
							-- (a miss comes round as soon as its bite is ready; a bite that
							-- landed sates it a little, `sated`)
							startRecover(
								predator,
								now,
								if hit then def.biteCooldown + (style.sated or 0) else def.biteCooldown * 0.6,
								true
							)
							if hit then
								nipped(predator, victim, now)
							end
						end
						-- A puffed fish's spines: the biter takes recoil and flinches
						if puffed then
							hurt(predator, victim, predator.maxHealth * Predators.puffRecoil, mouth, now)
							if modeOf(predator) ~= "dead" then
								stunOne(predator, Predators.puffFlinch, now)
							end
						end
					end
				end
			end
		end
	end
	if modeOf(predator) == "dead" then
		return
	end
	-- A tethered hunter never strays far from its hole: past its tether it swims back
	-- (a lunge or a tell may carry it out a little). One held out past it while
	-- roaming (rock between, a ledge it was lifted onto) takes the nearest spot by the
	-- floor as its hole after REHOME_AFTER (`holeNear`), and swims down to it
	local home = predator.home
	if home and predator.mode ~= "windup" and predator.burstUntil <= now then
		local back = home - predator.position
		if back.Magnitude <= (style.tether or 0) or predator.mode ~= "roam" then
			predator.strayed = math.huge
		elseif predator.strayed == math.huge then
			predator.strayed = now
		end
		if now - predator.strayed > REHOME_AFTER then
			predator.home = holeNear(predator, predator.position)
			predator.strayed = math.huge
			predator.waypoint = waypointFor(predator)
			predator.waypointUntil = now + 12
		elseif back.Magnitude > (style.tether or 0) then
			desired = back.Unit * def.speed * 0.8
		end
	end
	steer(predator, desired, dt, turnRate)
end

local function stream(now: number)
	local list: { { any } } = {}
	local where: { Predator } = {}
	for _, predator in predators do
		local entry: { any } = {
			predator.index,
			math.floor(predator.position.X * 10) / 10,
			math.floor(predator.position.Y * 10) / 10,
			math.floor(predator.position.Z * 10) / 10,
			math.floor(predator.heading.X * 100) / 100,
			math.floor(predator.heading.Y * 100) / 100,
			math.floor(predator.heading.Z * 100) / 100,
			predator.mode,
			math.floor(predator.health / predator.maxHealth * 100) / 100,
			if predator.target then (predator.target :: Player).UserId else 0,
			predator.def.id,
			math.floor(predator.meter * 100) / 100,
			predator.def.level or 0, -- (its level, for the tag's LV n · STRONGER / WEAKER)
		}
		table.insert(list, entry)
		table.insert(where, predator)
	end
	-- Each player gets the creatures near their fish, any hunting them and every boss
	-- (owner, 2026-10-21: more predators; all ~26 to everyone would be ~35 KB/s each).
	-- An unreliable packet over its size limit is dropped whole (playtest 2026-10-08:
	-- with the bigger map's predators and a boss up, every update was dropped), so the
	-- list goes out a few creatures at a time; the client takes each entry on its own
	-- and hides a creature it stops hearing about (PredatorController `STALE`)
	local range = Predators.streamRange
	for _, player in Players:GetPlayers() do
		local _, root = FishService.character(player)
		local near: { { any } } = {}
		for i, predator in where do
			if
				predator.custom
				or predator.target == player
				or (root and (predator.position - root.Position).Magnitude <= range)
			then
				table.insert(near, list[i])
			end
		end
		for first = 1, #near, STREAM_BATCH do
			local last = math.min(first + STREAM_BATCH - 1, #near)
			Net.predatorStateTo(player, { at = now, list = table.move(near, first, last, 1, {}) })
		end
	end
end

local function onBite(player: Player, index: any)
	if typeof(index) ~= "number" or index % 1 ~= 0 then
		return
	end
	local predator = predators[index]
	if predator == nil or predator.mode == "dead" then
		return
	end
	local now = Timing.clock()
	if now - (lastBite[player] or 0) < swim.biteCooldown * 0.8 then
		return
	end
	local mouth, length, slack = HuntService.mouth(player)
	local data = DataService.get(player)
	if mouth == nil or data == nil then
		return
	end
	-- Distance to the body, a segment from tail to nose
	local def = predator.def
	local half = predator.heading * def.length * 0.5
	local a, b = predator.position - half, predator.position + half
	local ab = b - a
	local t = math.clamp((mouth - a):Dot(ab) / math.max(ab:Dot(ab), 1e-4), 0, 1)
	local nearest = a + ab * t
	-- The biter's client draws the creature where it was a moment ago (the stream's
	-- interpolation delay plus latency), so a fast boss gets that much room too
	-- (retest 2026-10-09: bites on a swimming Megalodon's flank missed)
	local drift = predator.velocity.Magnitude * (Predators.interpolationDelay + hunt.latencySeconds)
	if
		(nearest - mouth).Magnitude
		> Size.reach(length) + def.length * (def.girth or 0.18) + slack + drift
	then
		return
	end
	lastBite[player] = now
	local school = 0
	for other, record in predator.hitBy do
		if other ~= player and now - record.at < Predators.schoolWindow then
			school += 1
		end
	end
	-- A plain predator: by level, like a fight between players (Config/Predators
	-- `fight`); `swallow` levels up, one bite swallows it whole. A boss: `bitten`.
	local bitten = def.bitten
	local level = def.level
	local swallowed = false
	local ratio: number
	if bitten then
		ratio = math.clamp(
			bitten.scale * (Size.raw(length) / def.length) ^ bitten.power,
			Predators.biteRatioMin,
			Predators.biteRatioMax
		)
	elseif level then
		local mine = levelOf((FishService.character(player)))
		swallowed = not predator.custom and mine >= level + fight.swallow
		ratio = math.clamp(strength(mine, level), fight.yours.min, fight.yours.max)
	else
		ratio = math.clamp(
			(Size.raw(length) / def.length) ^ Predators.biteRatioPower,
			Predators.biteRatioMin,
			Predators.biteRatioMax
		)
	end
	local jaw = Perks.bite(data.upgrades)
	local species = Progress.species(data).stats.bite
	local damage = hunt.biteDamage * ratio * (1 + Predators.schoolBonus * school) * jaw * species
	if swallowed then
		damage = math.max(damage, predator.health)
	end
	local hook = predator.onHit
	if hook then
		damage = hook(predator, player, damage, nearest)
	end
	Events.bitPredator:fire(player, def.id, predator.custom == true)
	if predator.custom then
		Events.bossDamage:fire(player, damage)
	end
	hurt(predator, player, damage, nearest, now, swallowed)
end

local function make(def: Def, custom: boolean?): Predator
	local predator: Predator = {
		index = nextIndex,
		def = def,
		position = Vector3.zero,
		velocity = Vector3.zero,
		heading = Vector3.new(1, 0, 0),
		health = def.health,
		maxHealth = def.health,
		mode = "roam",
		modeUntil = 0,
		target = nil,
		waypoint = Vector3.zero,
		waypointUntil = 0,
		lureAt = 0,
		respawnAt = 0,
		hitBy = {},
		custom = custom,
		onHit = nil,
		meter = 0,
		peel = 1,
		burstUntil = 0,
		stunUntil = 0,
		fails = {},
		ignore = {},
		nipped = {},
		strikeAt = -math.huge,
		veer = 0,
		approach = "direct",
		approachFor = nil,
		approachUntil = 0,
		orbit = 1,
		feintLeft = false,
		pack = nil,
		role = 1,
		home = nil,
		strayed = math.huge,
		slot = nil,
		slots = nil,
		gulpFree = false,
		luredAt = -math.huge,
	}
	nextIndex += 1
	predators[predator.index] = predator
	return predator
end

function PredatorService.list(): { [number]: Predator }
	return predators
end

function PredatorService.get(index: number): Predator?
	return predators[index]
end

-- Adds a creature the caller drives (a boss): it's streamed and bitable, but not
-- simulated here. `at` is where it appears.
function PredatorService.add(def: Def, at: Vector3?): Predator
	local predator = make(def, true)
	spawn(predator, at)
	return predator
end

-- Takes a custom creature out of the world (a boss escaping): clients fade it.
function PredatorService.remove(predator: Predator, reason: string)
	if predators[predator.index] ~= predator then
		return
	end
	predator.mode = "dead"
	predator.target = nil
	Net.predatorEvent("died", predator.index, { by = 0, gone = true, reason = reason })
	PredatorService.died:fire(predator, nil)
	predators[predator.index] = nil
end

-- Stuns every plain predator (never a boss) within `radius` of `position` for
-- `seconds` (the Anglerfish's Lantern Flash): each drops its fish and any tell (no
-- bite), drifts to a stop, can't start a tell, then roams again. Returns how many.
function PredatorService.stun(position: Vector3, radius: number, seconds: number): number
	local now = Timing.clock()
	local count = 0
	for _, predator in predators do
		if predator.custom or predator.mode == "dead" then
			continue
		end
		-- (to its body, a segment from tail to nose)
		local half = predator.heading * predator.def.length * 0.5
		local a, b = predator.position - half, predator.position + half
		local ab = b - a
		local t = math.clamp((position - a):Dot(ab) / math.max(ab:Dot(ab), 1e-4), 0, 1)
		if (a + ab * t - position).Magnitude <= radius then
			stunOne(predator, seconds, now)
			count += 1
		end
	end
	return count
end

-- The share of a bite a fish takes: a puffed fish (character attribute `Puffed`, the
-- Pufferfish's Puff Up) takes `Predators.puffDamage`. Plain predators apply it
-- themselves; a boss's bites (BossService) should multiply by it too.
function PredatorService.biteScale(player: Player): number
	local character = FishService.character(player)
	if character ~= nil and isPuffed(character, Timing.clock()) then
		return Predators.puffDamage
	end
	return 1
end

-- A fight by level (Config/Predators `fight`), for the sims: how much stronger level
-- `a` is than `b`, and a creature's bite on a fish of `level`, × its biteFraction
PredatorService.strength = strength
function PredatorService.theirBite(def: Def, level: number): number
	local stand = {
		GetAttribute = function(_: any, name: string): any
			return if name == "FishLevel" then level else nil
		end,
	}
	return theirBite(def, stand :: any)
end

-- Helpers for a boss controller
PredatorService.pickTarget = pickTarget
PredatorService.targetRoot = targetRoot
PredatorService.steer = steer
PredatorService.mouthOf = mouthOf
PredatorService.rhythm = rhythm
PredatorService.CEILING_SHARE = CEILING_SHARE
PredatorService.orbitWay = orbitWay
PredatorService.rotateToward = rotateToward

function PredatorService.start()
	for _, def in Predators.groups do
		local pack = styleOf(def).pack
		-- (each of the group's `count` takes its own patch of the water, a pack as one)
		for slot = 0, def.count - 1 do
			if pack then
				-- (`count` packs, each `size` together: the leader first, the rest at
				-- their stations beside it)
				local members: { Predator } = {}
				for role = 1, pack.size do
					local member = make(def, false)
					member.pack = members
					member.role = role
					member.slot, member.slots = slot, def.count
					table.insert(members, member)
					spawn(member)
				end
			else
				local predator = make(def, false)
				predator.slot, predator.slots = slot, def.count
				spawn(predator)
			end
		end
	end
	Net.onRequest("BitePredator", onBite)
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Predators.tickSeconds then
			return
		end
		local step = accumulator
		accumulator = 0
		local now = Timing.clock()
		for _, predator in predators do
			if not predator.custom then
				Guard.run("PredatorService.simulate", function()
					simulate(predator, step, now)
				end)
			end
		end
		stream(now)
	end)
	DataService.releasing:connect(function(player)
		lastBite[player] = nil
		for _, predator in predators do
			predator.hitBy[player] = nil
			predator.fails[player] = nil
			predator.ignore[player] = nil
			predator.nipped[player] = nil
			if predator.target == player then
				predator.target = nil
			end
		end
	end)
end

return PredatorService
