--!strict
-- Baited hooks from boats (Config/Hooks, GDD §5). Fishing boats drift over the sea
-- and now and then drop a line with bait on it. Swallowing the bait puts it on your
-- Haul and hooks you: the line reels you up toward the boat (the client drags its
-- own fish, HookController). Mashing BITE or DASH breaks free; a podmate biting near
-- you cuts the line; if it lands you, the fisherman keeps a share of your Haul. The
-- boats and lines go to every client about once a second.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Biomes = require(ReplicatedStorage.Shared.Biomes)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local FishService = require(script.Parent.FishService)
local HuntService = require(script.Parent.HuntService)
local PodService = require(script.Parent.PodService)

local tune = Config.Hooks
local World = Config.World
local TICK = 0.25

local HookService = {}

type Hook = {
	id: number,
	position: Vector3, -- where the bait hangs
	mass: number,
	taken: Player?,
	hookedAt: number,
	struggles: number,
	lastStruggle: number,
}

type Boat = {
	index: number,
	angle: number,
	radius: number,
	turn: number, -- +1 or -1: which way round it drifts
	position: Vector3,
	yaw: number,
	nextAt: number, -- when it drops its next line
	liftAt: number, -- when an untouched line comes up
	hook: Hook?,
}

local rng = Random.new()
local boats: { Boat } = {}
local hookedBy: { [Player]: Hook } = {}
local nextHookId = 1

local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include
floorParams.FilterDescendantsInstances = { workspace.Terrain }

local function floorUnder(x: number, z: number): number
	local hit =
		workspace:Raycast(Vector3.new(x, World.surfaceY - 2, z), Vector3.new(0, -1400, 0), floorParams)
	return if hit then hit.Position.Y else Seafloor.y(x, z)
end

-- Where a hooked fish is being reeled to now
local function reelPoint(hook: Hook, now: number): Vector3
	local up = math.max(0, now - hook.hookedAt) * tune.reel
	local y = math.min(hook.position.Y + up, World.surfaceY - 8)
	return Vector3.new(hook.position.X, y, hook.position.Z)
end

local function payload(now: number): { [string]: any }
	local list = {}
	for _, boat in boats do
		local hook = boat.hook
		table.insert(list, {
			i = boat.index,
			x = boat.position.X,
			z = boat.position.Z,
			yaw = boat.yaw,
			hook = if hook
				then {
					id = hook.id,
					x = hook.position.X,
					y = hook.position.Y,
					z = hook.position.Z,
					taken = if hook.taken then hook.taken.UserId else 0,
					hookedAt = hook.hookedAt,
				}
				else nil,
		})
	end
	return { boats = list, now = now }
end

local function clearAttributes(player: Player)
	local character = FishService.character(player)
	if character then
		character:SetAttribute("HookedBy", nil)
		character:SetAttribute("HookStruggle", nil)
	end
end

-- The line comes up: the hooked fish (if any) is let go
local function raise(boat: Boat, now: number)
	local hook = boat.hook
	if hook and hook.taken then
		hookedBy[hook.taken] = nil
		clearAttributes(hook.taken)
	end
	boat.hook = nil
	boat.nextAt = now + rng:NextNumber(tune.between[1], tune.between[2])
	Net.hooks(payload(now))
end

local function boatOf(hook: Hook): Boat?
	for _, boat in boats do
		if boat.hook == hook then
			return boat
		end
	end
	return nil
end

local function release(player: Player, how: string)
	local hook = hookedBy[player]
	if hook == nil then
		return
	end
	local boat = boatOf(hook)
	if boat then
		raise(boat, Timing.clock())
	else
		hookedBy[player] = nil
		clearAttributes(player)
	end
	if how == "free" then
		Net.notify(player, "You broke free, and kept the bait!", "good")
	elseif how == "cut" then
		Net.notify(player, "Your podmate bit the line. You're free!", "good")
	end
end

-- Drops a line where the boat is, if there's water enough under it
local function drop(boat: Boat, now: number)
	local x, z = boat.position.X, boat.position.Z
	local floor = floorUnder(x, z)
	local y = World.surfaceY - rng:NextNumber(tune.depth[1], tune.depth[2])
	y = math.max(y, floor + 20)
	local at = Vector3.new(x, y, z)
	local biome = Biomes.at(at)
	if y > World.surfaceY - 40 or biome == nil then
		boat.nextAt = now + 8
		return
	end
	local mid = (biome.minLevel + biome.maxLevel) / 2
	boat.hook = {
		id = nextHookId,
		position = at,
		mass = math.max(tune.minBait, tune.bait * Size.massForLevel(mid)),
		taken = nil,
		hookedAt = 0,
		struggles = 0,
		lastStruggle = 0,
	}
	nextHookId += 1
	boat.liftAt = now + tune.line
	Net.hooks(payload(now))
end

local function hookById(id: any): (Boat?, Hook?)
	if typeof(id) ~= "number" then
		return nil, nil
	end
	for _, boat in boats do
		local hook = boat.hook
		if hook and hook.id == id then
			return boat, hook
		end
	end
	return nil, nil
end

local function takeBait(player: Player, id: any)
	local _, hook = hookById(id)
	local session = HuntService.sessions()[player]
	if hook == nil or hook.taken or hookedBy[player] or session == nil or session.inHub then
		return
	end
	local mouth, length, slack = HuntService.mouth(player)
	if mouth == nil then
		return
	end
	if (hook.position - mouth).Magnitude > Size.reach(length) * 1.35 + 3 + slack then
		return
	end
	local now = Timing.clock()
	local added = HuntService.gain(player, hook.mass)
	hook.taken = player
	hook.hookedAt = now
	hookedBy[player] = hook
	local character = FishService.character(player)
	if character then
		character:SetAttribute("HookedBy", hook.id)
		character:SetAttribute("HookStruggle", 0)
	end
	Net.notify(player, `+{Format.mass(added)} bait · HOOKED! Mash BITE or DASH to break free`, "bad")
	Net.hooks(payload(now))
end

local function struggle(player: Player)
	local hook = hookedBy[player]
	local now = Timing.clock()
	if hook == nil or now - hook.lastStruggle < tune.struggleGap then
		return
	end
	hook.lastStruggle = now
	hook.struggles += 1
	local character = FishService.character(player)
	if character then
		character:SetAttribute("HookStruggle", math.clamp(hook.struggles / tune.struggleNeed, 0, 1))
	end
	if hook.struggles >= tune.struggleNeed and now - hook.hookedAt >= tune.minHooked then
		release(player, "free")
	end
end

-- A podmate bites the line near a hooked fish
local function biteLine(player: Player, userId: any)
	if typeof(userId) ~= "number" then
		return
	end
	local target = Players:GetPlayerByUserId(userId)
	if target == nil or hookedBy[target] == nil or not PodService.together(player, target) then
		return
	end
	local _, mine = FishService.character(player)
	local _, theirs = FishService.character(target)
	if mine == nil or theirs == nil or (mine.Position - theirs.Position).Magnitude > tune.biteRange then
		return
	end
	release(target, "cut")
	Net.notify(player, `You bit {target.DisplayName}'s line!`, "good")
end

local function step()
	local now = Timing.clock()
	for _, boat in boats do
		local hook = boat.hook
		if hook == nil then
			-- Drifting round the sea
			boat.angle += boat.turn * tune.drift * TICK / boat.radius
			local x, z = math.cos(boat.angle) * boat.radius, math.sin(boat.angle) * boat.radius
			-- (the hull's length runs along its X: CFrame.Angles(0, yaw, 0) points X at
			-- (cos yaw, 0, -sin yaw), which must be the drift (-sin a, 0, cos a) × turn)
			boat.yaw = math.atan2(-math.cos(boat.angle) * boat.turn, -math.sin(boat.angle) * boat.turn)
			boat.position = Vector3.new(x, World.surfaceY, z)
			if now >= boat.nextAt then
				drop(boat, now)
			end
		elseif hook.taken then
			local player = hook.taken :: Player
			local session = HuntService.sessions()[player]
			if player.Parent ~= Players or session == nil or not session.alive then
				hookedBy[player] = nil
				raise(boat, now)
			elseif reelPoint(hook, now).Y >= World.surfaceY - 9 or now - hook.hookedAt >= tune.hold then
				-- Landed: the fisherman keeps a share of the Haul
				local taken = HuntService.takeHaul(player, tune.landedShare)
				raise(boat, now)
				Net.notify(
					player,
					if taken > 0
						then `Landed! The fisherman kept {Format.mass(taken)} of your Haul`
						else "Landed! Lucky you had no Haul",
					"bad"
				)
			end
		elseif now >= boat.liftAt then
			raise(boat, now)
		end
	end
end

function HookService.start()
	for i = 1, tune.boats do
		local radius = rng:NextNumber(tune.band[1], tune.band[2])
		local angle = rng:NextNumber(0, 2 * math.pi)
		table.insert(boats, {
			index = i,
			angle = angle,
			radius = radius,
			turn = if rng:NextNumber() < 0.5 then -1 else 1,
			position = Vector3.new(math.cos(angle) * radius, World.surfaceY, math.sin(angle) * radius),
			yaw = 0,
			nextAt = Timing.clock() + rng:NextNumber(5, tune.between[2]),
			liftAt = 0,
			hook = nil,
		})
	end
	Net.onRequest("TakeBait", takeBait)
	Net.onRequest("StruggleHook", struggle)
	Net.onRequest("BiteLine", biteLine)
	Players.PlayerRemoving:Connect(function(player)
		hookedBy[player] = nil
	end)
	Guard.loop("HookService", TICK, step)
	Guard.loop("HookService.stream", 1, function()
		Net.hooks(payload(Timing.clock()))
	end)
end

return HookService
