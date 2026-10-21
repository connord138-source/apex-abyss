--!strict
-- Server speed checks, lenient and log-only for now (CLAUDE.md "Not built yet:
-- server-side speed checks"). Each fish runs on its owner's client, so an exploiter
-- could move theirs faster than any fish can swim. Every second this compares how
-- far each fish moved with the most it could (its top speed with Strong Fins, its
-- species, a Dash the whole time and a podmate's slipstream or a manta's draft, plus
-- generous slack);
-- three strikes in 30 s writes a warning to the Output with the numbers, so false
-- positives can be found in testing before anything is enforced. Moves the server
-- made (a teleport, a respawn, a creature's shove) reset the baseline.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Guard = require(script.Parent.Parent.Guard)
local Progress = require(script.Parent.Parent.Progress)
local DataService = require(script.Parent.DataService)
local FishService = require(script.Parent.FishService)
local HuntService = require(script.Parent.HuntService)

local swim = Config.Tuning.swim

local SpeedService = {}

local SLACK = 1.5 -- × the fastest a fish can go
local EXTRA = 25 -- studs of latency and physics slack
local STRIKES = 3
local WINDOW = 30
local LOG_EVERY = 30

type Track = { position: Vector3, at: number, strikes: { number }, loggedAt: number }

local tracks: { [Player]: Track } = {}

-- The fastest a fish can be going (studs a second)
local function fastest(player: Player, length: number): number
	local data = DataService.get(player)
	local species = if data then Progress.species(data).stats.speed else 1.3
	local fins = Perks.speed(if data then data.upgrades else nil)
	-- A Reef Shark's Blood Sense frenzy (kept on 1.5 s past its end: the check spans
	-- the last second)
	local character = FishService.character(player)
	local sense = Perks.sense(character, Timing.clock(), 1.5)
	-- A Sail Fin's top speed (Perks.exotic)
	local exotic = Perks.exotic(character).speed
	-- The faster of a podmate's slipstream and a manta's draft (Config/Companions)
	local draft = math.max(Config.Pvp.pods.slipstream.speed, Config.Companions.manta.speed)
	return Size.topSpeed(length) * fins * species * sense * exotic * swim.boostMultiplier * draft
end

function SpeedService.start()
	FishService.spawned:connect(function(player: Player)
		tracks[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
	end)
	Guard.loop("SpeedService", 1, function()
		local now = os.clock()
		for player, session in HuntService.sessions() do
			local _, root = FishService.character(player)
			local _, length = HuntService.mouth(player)
			if root == nil or not session.alive or length <= 0 then
				tracks[player] = nil
				continue
			end
			-- A grab or a hook drags the fish (not its own swimming): start again after
			local character = FishService.character(player)
			if
				character
				and (character:GetAttribute("HeldBy") ~= nil or character:GetAttribute("HookedBy") ~= nil)
			then
				tracks[player] = nil
				continue
			end
			local track = tracks[player]
			local movedAt = player:GetAttribute("MovedAt")
			if track == nil or (typeof(movedAt) == "number" and movedAt >= track.at - 0.5) then
				tracks[player] = { position = root.Position, at = now, strikes = {}, loggedAt = 0 }
				continue
			end
			local dt = now - track.at
			local moved = (root.Position - track.position).Magnitude
			local allowed = fastest(player, length) * SLACK * dt + EXTRA
			track.position, track.at = root.Position, now
			if moved <= allowed then
				continue
			end
			table.insert(track.strikes, now)
			while #track.strikes > 0 and now - track.strikes[1] > WINDOW do
				table.remove(track.strikes, 1)
			end
			if #track.strikes >= STRIKES and now - track.loggedAt > LOG_EVERY then
				track.loggedAt = now
				warn(
					string.format(
						"[SpeedCheck] %s (%d) moved %.0f studs in %.1f s (allowed %.0f) · %d strikes in %d s · length %.1f",
						player.Name,
						player.UserId,
						moved,
						dt,
						allowed,
						#track.strikes,
						WINDOW,
						length
					)
				)
			end
		end
	end)
end

return SpeedService
