--!strict
-- Shells lying around the sea. The spots are placed once at server start (a ray
-- down from above finds the seabed or rock under each one), and every player has
-- their own copy of each: a shell you pick up comes back for you after a while,
-- whatever anyone else does. Clients draw them and pick them up instantly
-- (ShellController); the server checks the fish is really there.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
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

local function placeSpots()
	local rng = Random.new(World.seed + 10)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace:WaitForChild("World"), workspace.Terrain }
	local trench = World.trench
	local function inTrench(x: number, z: number): boolean
		return math.abs(x - trench.center.X) < trench.size.X / 2 + 12
			and math.abs(z - trench.center.Z) < trench.size.Z / 2 + 12
	end
	local function drop(x: number, z: number, golden: boolean): boolean
		local from = Vector3.new(x, World.surfaceY - 10, z)
		local hit = workspace:Raycast(from, Vector3.new(0, -(World.surfaceY - trench.floorY + 20), 0), params)
		if hit == nil or hit.Instance.Name == "Surface" then
			return false
		end
		table.insert(spots, { position = hit.Position + hit.Normal * 0.7, golden = golden })
		return true
	end
	local placed, tries = 0, 0
	while placed < Shells.spots and tries < Shells.spots * 6 do
		tries += 1
		local angle = rng:NextNumber(0, 2 * math.pi)
		local distance = rng:NextNumber(World.shallows.inner, World.shallows.outer)
		local x, z = math.cos(angle) * distance, math.sin(angle) * distance
		if not inTrench(x, z) and drop(x, z, false) then
			placed += 1
		end
	end
	for _ = 1, Shells.goldenSpots do
		local x = trench.center.X + rng:NextNumber(-0.4, 0.4) * trench.size.X
		local z = trench.center.Z + rng:NextNumber(-0.4, 0.4) * trench.size.Z
		drop(x, z, true)
	end
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
	local reach = Perks.shellReach(fishLength, data.upgrades, data.boosts, Timing.now())
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
