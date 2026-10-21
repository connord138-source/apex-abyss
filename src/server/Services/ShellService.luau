--!strict
-- Shells lying around the sea. The spots are placed once at server start on open
-- floor (Shared/Ground `open`: the seabed itself, never in or under a rock, coral,
-- wreck, ruin or overhang a fish can't get to), and every player has their own copy
-- of each: a shell you pick up comes back for you after a while, whatever anyone
-- else does. Clients draw them and pick them up instantly (ShellController); the
-- server checks the fish is really there.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)

local Shells = Config.Shells
local World = Config.World

local ShellService = {}

type Spot = { position: Vector3, golden: boolean }

local spots: { Spot } = {}
local collected: { [Player]: { [number]: number } } = {} -- spot → clock it's back

-- Open floor a small fish can get to (Shared/Ground `open`): the Terrain itself (a
-- shell on a kelp blade or a rock's placeholder part floated above the floor, owner
-- 2026-10-08), a ball of OPEN_RADIUS comes down onto it from above, no part's box
-- comes within OPEN_ROOM of the water over it, and it's no steeper than OPEN_UP
local OPEN_RADIUS = 1.25
local OPEN_ROOM = 2.5
local OPEN_UP = 0.5

local function placeSpots()
	local rng = Random.new(World.seed + 10)
	local trench = World.trench
	local closed = 0
	local function drop(x: number, z: number, golden: boolean): boolean
		local floor, normal = Ground.open(x, z, OPEN_RADIUS, OPEN_UP, OPEN_ROOM)
		if floor == nil or normal == nil then
			closed += 1
			return false
		end
		table.insert(spots, { position = floor + normal * 0.7, golden = golden })
		return true
	end
	local placed, tries = 0, 0
	while placed < Shells.spots and tries < Shells.spots * 8 do
		tries += 1
		local angle = rng:NextNumber(0, 2 * math.pi)
		local distance = rng:NextNumber(World.shallows.inner, World.shallows.outer)
		local x, z = math.cos(angle) * distance, math.sin(angle) * distance
		if not Seafloor.inTrench(x, z, 12) and drop(x, z, false) then
			placed += 1
		end
	end
	local golden = 0
	for _ = 1, Shells.goldenSpots do
		-- Down in the canyon, near its floor line (a few tries: a ledge or a pillar
		-- can stand over a spot)
		for _ = 1, 8 do
			local r = rng:NextNumber(trench.radii[1] + 40, trench.radii[2] - 40)
			local _, width = Seafloor.trenchAxis(r)
			local _, _, halfBottom = Seafloor.trenchHalfWidths(width)
			local x, z = Seafloor.trenchPoint(r, rng:NextNumber(-halfBottom * 0.7, halfBottom * 0.7))
			if drop(x, z, true) then
				golden += 1
				break
			end
		end
	end
	print(
		`[ShellService] {placed} of {Shells.spots} shells and {golden} of {Shells.goldenSpots} golden on open floor ({closed} tries refused as closed in)`
	)
end

local function collect(player: Player, index: any)
	if typeof(index) ~= "number" or index % 1 ~= 0 or spots[index] == nil then
		return
	end
	local data = DataService.get(player)
	local character, root = FishService.character(player)
	local mine = collected[player]
	if data == nil or character == nil or root == nil or mine == nil then
		return
	end
	local now = Timing.clock()
	local spot = spots[index]
	if (mine[index] or 0) > now then
		Net.shellResult(player, index, mine[index])
		return
	end
	local length = character:GetAttribute("Length")
	local fishLength = if typeof(length) == "number" then length else 2
	local reach =
		Perks.shellReach(fishLength, data.upgrades, data.boosts, Timing.now(), Perks.exotic(character).find)
	-- Slack for the server seeing the fish a little in the past
	local slack = Size.topSpeed(fishLength) * Perks.speed(data.upgrades) * 2 * 0.35 + 4
	if (root.Position - spot.position).Magnitude > reach + fishLength * 0.5 + slack then
		Net.shellResult(player, index, 0)
		return
	end
	local backAt = now + Shells.respawn
	mine[index] = backAt
	local value = if spot.golden then Shells.goldenValue else Shells.value
	EconomyService.addShells(player, value)
	Events.shells:fire(player, value)
	Net.shellResult(player, index, backAt)
end

-- Shells carried by a big prey fish, sometimes. Returns how many were found.
function ShellService.preyDrop(player: Player, preyId: string): number
	local drop = Shells.preyDrops[preyId]
	if drop == nil or math.random() > drop.chance then
		return 0
	end
	local count = math.random(drop.min, drop.max)
	EconomyService.addShells(player, count)
	return count
end

function ShellService.start()
	placeSpots()
	Players.PlayerAdded:Connect(function(player)
		collected[player] = {}
	end)
	for _, player in Players:GetPlayers() do
		collected[player] = collected[player] or {}
	end
	Players.PlayerRemoving:Connect(function(player)
		collected[player] = nil
	end)
	Net.onRequest("Collect", collect)
	Net.onGetShells(function(player: Player): { [string]: any }
		local positions: { Vector3 } = {}
		local golden: { boolean } = {}
		for _, spot in spots do
			table.insert(positions, spot.position)
			table.insert(golden, spot.golden)
		end
		local hidden: { [string]: number } = {}
		local now = Timing.clock()
		local mine: { [number]: number } = collected[player] or {}
		for index, backAt in mine do
			if backAt > now then
				hidden[tostring(index)] = backAt
			end
		end
		return { positions = positions, golden = golden, hidden = hidden }
	end)
end

return ShellService
