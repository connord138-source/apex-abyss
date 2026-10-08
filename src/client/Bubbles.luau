--!strict
-- Bubbles: the one look for every bubble in the game (owner, 2026-10-08: "there's no
-- feeling that you're underwater. Something needs to be added"). A burst at a point
-- (bites, dashes, hurts), or a stream fixed to a fish's mouth whose rate the caller
-- drives with its speed (BubbleController).
local Bubbles = {}

local COLOR = ColorSequence.new(Color3.fromRGB(222, 250, 255))

local function style(emitter: ParticleEmitter, size: number)
	emitter.Color = COLOR
	emitter.LightEmission = 0.5
	emitter.LightInfluence = 0.7
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.7, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.35),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, size * 1.15),
	})
	emitter.Acceleration = Vector3.new(0, 4, 0)
	emitter.Drag = 2
	emitter.RotSpeed = NumberRange.new(-40, 40)
	emitter.ZOffset = 0.1
end

-- A puff of bubbles at a point; `size` is roughly the fish's length
function Bubbles.burst(position: Vector3, size: number, count: number?)
	local holder = Instance.new("Part")
	holder.Name = "BubbleBurst"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.9, 1.8)
	emitter.Speed = NumberRange.new(size * 1.2, size * 3.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	style(emitter, math.clamp(size * 0.1, 0.18, 1.2))
	emitter.Parent = holder
	holder.Parent = workspace
	emitter:Emit(count or math.clamp(math.floor(size * 5), 8, 60))
	task.delay(2.2, function()
		holder:Destroy()
	end)
end

-- A stream fixed to a fish, at `offset` from its root (the mouth); the caller sets
-- its Rate from the fish's speed. Returns the emitter.
function Bubbles.stream(root: BasePart, offset: Vector3, length: number): ParticleEmitter
	local attachment = Instance.new("Attachment")
	attachment.Name = "BubbleMouth"
	attachment.Position = offset
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "BubbleStream"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(1.4, 2.6)
	emitter.Speed = NumberRange.new(0.6, 1.8)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.LockedToPart = false
	style(emitter, math.clamp(length * 0.07, 0.14, 0.9))
	emitter.Parent = attachment
	return emitter
end

return Bubbles
