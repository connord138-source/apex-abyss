--!strict
-- The water's sound (owner, 2026-10-08: "there's no feeling that you're
-- underwater. Something needs to be added"): three beds from the sound pack
-- (Config/Sounds, Sfx.loop) crossfaded by where the camera is: the bright shallows
-- over the shelf, the deep drone below the drop-off, and the cavern's hush in the
-- hub. Everything else in the game is one-shots; this is what makes it feel like
-- being underwater when nothing is happening.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Sfx = require(script.Parent.Parent.Sfx)
local Spring = require(script.Parent.Parent.Spring)

local World = Config.World

-- Each bed's full volume (the pack is mastered quiet; these stay under the cues)
local BASE: { [string]: number } = { AmbientShallow = 0.5, AmbientDeep = 0.55, AmbientHub = 0.45 }

local AmbienceController = {}

local beds: { [string]: Sound } = {}
local levels: { [string]: number } = { AmbientShallow = 0, AmbientDeep = 0, AmbientHub = 0 }
local dread = 0

-- How much of each bed belongs at the camera's position (0..1 each)
local function targets(position: Vector3): { [string]: number }
	local deepT =
		math.clamp((World.seabedY - 40 - position.Y) / (World.seabedY - 40 - World.deep.floorY), 0, 1)
	local hubT = if Layout.inHub(position) then 1 else 0
	local outside = 1 - hubT * 0.75
	return {
		AmbientShallow = (1 - deepT) * outside,
		AmbientDeep = math.max(deepT * outside, dread * 0.6), -- a boss near brings the drone up
		AmbientHub = hubT,
	}
end

local function step(dt: number)
	local position = workspace.CurrentCamera.CFrame.Position
	local wanted = targets(position)
	local alpha = Spring.alpha(1.4, dt)
	for name, sound in beds do
		local level = levels[name] + (wanted[name] - levels[name]) * alpha
		levels[name] = level
		sound.Volume = BASE[name] * level
	end
end

-- How close a world boss is (0..1); BossController sets it alongside the dread look
function AmbienceController.setDread(amount: number)
	dread = math.clamp(amount, 0, 1)
end

function AmbienceController.start()
	for name in BASE do
		local sound = Sfx.loop(name, 0)
		if sound then
			beds[name] = sound
		end
	end
	if next(beds) == nil then
		return -- no pack yet (Config/Sounds id is 0)
	end
	RunService.RenderStepped:Connect(step)
end

return AmbienceController
