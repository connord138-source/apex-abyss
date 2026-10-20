--!strict
-- A sea turtle swimming at the side of every fish it has joined (Config/Companions;
-- owner, 2026-10-20: "a buff where they swim with you and provide a bonus"): the
-- server sets the character's `Escort` attribute (the clock it leaves at;
-- CompanionService), and every client draws the turtle there, so everyone sees who has
-- one. It's the ambient turtle's body (AmbientBody, the imported model or its
-- part-built stand-in), posed by Shared/AmbientRigs: it rows to keep up, banks into
-- turns, glides when the fish is still, and fades in as it joins and out as it leaves.
-- The ambient copy it came from is hidden meanwhile (AmbientLifeController).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AmbientRigs = require(ReplicatedStorage.Shared.AmbientRigs)
local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local AmbientBody = require(script.Parent.Parent.AmbientBody)

local CompanionController = {}

local tune = Config.Companions.turtle
local kind = Config.Ambient.kinds.turtle
local SIZE = (kind.size[1] + kind.size[2]) / 2
local FADE = 0.8 -- seconds it takes to join or leave
local BEAT_SWIM = 2.6 -- seconds a stroke while keeping up (it glides at its kind's own)

type Escort = {
	body: AmbientBody.Body,
	holder: Model,
	frame: CFrame,
	shown: number, -- 0 .. 1
	yaw: number,
	motion: AmbientRigs.Motion,
	side: number,
}

local escorts: { [Player]: Escort } = {}
local folder: Folder

local function build(player: Player, at: CFrame): Escort
	local holder = Instance.new("Model")
	holder.Name = `Turtle_{player.UserId}`
	holder.Parent = folder
	local body = AmbientBody.new("turtle", SIZE, kind.look or {}, { model = kind.model }, holder)
	AmbientBody.fade(body, 1)
	return {
		body = body,
		holder = holder,
		frame = at,
		shown = 0,
		yaw = 0,
		side = if player.UserId % 2 == 0 then 1 else -1,
		motion = {
			t = 0,
			phase = (player.UserId % 97) / 97 * 2 * math.pi,
			period = BEAT_SWIM,
			bank = 0,
			turn = 0,
			rest = 0,
			settled = -1,
			moving = true,
		},
	}
end

local function drop(player: Player)
	local escort = escorts[player]
	if escort then
		escort.holder:Destroy()
		escorts[player] = nil
	end
end

local function step(dt: number)
	local now = Timing.clock()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local untilAt = character and character:GetAttribute("Escort")
		local active = typeof(untilAt) == "number" and untilAt > now
		local escort = escorts[player]
		if root == nil or not root:IsA("BasePart") or (not active and escort == nil) then
			if escort and (root == nil or not root:IsA("BasePart")) then
				drop(player)
			end
			continue
		end
		local length = character and character:GetAttribute("Length")
		local fishLength = if typeof(length) == "number" then length else 2
		-- Where it swims: beside the fish and a little back, level with it
		local side = if escort then escort.side elseif player.UserId % 2 == 0 then 1 else -1
		local place = root.CFrame
			* CFrame.new(side * (fishLength * tune.side + SIZE * 0.6), 0, fishLength * tune.back + SIZE * 0.2)
		if escort == nil then
			escort = build(player, CFrame.new(place.Position + root.CFrame.LookVector * -SIZE * 2))
			escorts[player] = escort
		end
		local e = escort :: Escort
		-- Catch up on a spring; face the way it's going (or the fish's way when still)
		local from = e.frame.Position
		local to = from:Lerp(place.Position, math.min(1, dt * tune.follow))
		local moved = to - from
		local speed = moved.Magnitude / math.max(dt, 1e-3)
		local heading = if speed > 1.5 then moved.Unit else root.CFrame.LookVector
		local flat = Vector3.new(heading.X, 0, heading.Z)
		local yaw = if flat.Magnitude > 1e-3 then math.atan2(-flat.X, -flat.Z) else e.yaw
		local turn = (yaw - e.yaw + math.pi) % (2 * math.pi) - math.pi
		local rate = turn / math.max(dt, 1e-3)
		e.yaw += turn * math.min(1, dt * 4)
		local pitch = math.clamp(math.asin(math.clamp(heading.Y, -1, 1)), -0.6, 0.6)
		e.frame = CFrame.new(to) * CFrame.Angles(0, e.yaw, 0) * CFrame.Angles(pitch, 0, 0)
		-- Join and leave as a fade
		e.shown = math.clamp(e.shown + (if active then dt else -dt) / FADE, 0, 1)
		if e.shown <= 0 and not active then
			drop(player)
			continue
		end
		AmbientBody.fade(e.body, math.floor((1 - e.shown) * 10 + 0.5) / 10)
		local motion = e.motion
		motion.t = now
		motion.period = if speed > 4 then BEAT_SWIM else (kind.beat or { 4 })[1]
		motion.turn = math.clamp(rate / 0.5, -1, 1)
		motion.bank = math.clamp(rate * 0.7, -0.45, 0.45)
		AmbientBody.pose(e.body, motion)
		e.body.root.CFrame = AmbientBody.frame(e.body, e.frame)
	end
	for player in escorts do
		if player.Parent == nil then
			drop(player)
		end
	end
end

function CompanionController.start()
	folder = Instance.new("Folder")
	folder.Name = "Companions"
	folder.Parent = workspace
	RunService.RenderStepped:Connect(step)
end

return CompanionController
