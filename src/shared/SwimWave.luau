--!strict
-- The shape of a fish's swim, shared by every animator (players' fish, prey, the
-- predators and bosses), so they all move the same way (owner, 2026-10-07: "more
-- fluid and natural like a fish, not the entire body swaying back and forth"). A
-- real fish holds its head and shoulders nearly still and whips the back half: the
-- wave's amplitude is tiny at the front and grows steeply toward the tail fin, and
-- it travels backward down the body so the tail lags the hips.
local SwimWave = {}

-- How much of the wave a segment carries, by its place along the spine (0 = just
-- behind the head, 1 = the tail fin)
function SwimWave.envelope(t: number): number
	return 0.06 + 0.94 * t ^ 1.9
end

-- The phase lag from head to tail, in radians, for a spine of `segments` joints:
-- about two thirds of a wavelength along the body, a little more on long bodies
function SwimWave.spread(segments: number): number
	return 2.0 + 0.3 * math.max(segments - 3, 0)
end

-- The yaw of spine joint `i` of `n` at wave phase `phase` (radians) with the given
-- amplitude (radians at the tail) and turning bend (radians, shared down the body)
function SwimWave.yaw(i: number, n: number, phase: number, amplitude: number, bend: number): number
	local t = i / n
	local swing = math.sin(phase - SwimWave.spread(n) * t) * amplitude * SwimWave.envelope(t)
	return swing + bend * (0.3 + 0.7 * t)
end

-- The head: no sway, only the bend into a turn
function SwimWave.headYaw(bend: number): number
	return bend * 0.25
end

-- Each rig's bones' rest rotations in the fish's own axes (its Root bone's: Y up, -Z
-- ahead). Imported bones point their own Y down the spine (Blender's bone axis), so
-- a turn about a bone's own Y rolled the body instead of swinging the tail (playtest
-- 2026-10-07: tails moved +-0.02 studs); the swing is turned into each bone's axes.
-- Taken once per rig, before any turn is applied, so no pose leaks in.
local restFrames: { [any]: { [string]: CFrame } } = setmetatable({}, { __mode = "k" }) :: any

local function restOf(bones: { [string]: Bone }): { [string]: CFrame }?
	local root = bones.Root
	if root == nil then
		return nil
	end
	local frames = restFrames[bones]
	if frames == nil then
		local made: { [string]: CFrame } = {}
		local rootFrame = root.WorldCFrame * root.Transform:Inverse()
		for name, bone in bones do
			made[name] = rootFrame:ToObjectSpace(bone.WorldCFrame * bone.Transform:Inverse()).Rotation
		end
		restFrames[bones] = made
		frames = made
	end
	return frames
end

local function turn(bone: Bone, frame: CFrame?, yaw: number)
	local rotation = CFrame.Angles(0, yaw, 0)
	bone.Transform = if frame then frame:Inverse() * rotation * frame else rotation
end

-- Drives a rigged body's bones (Head, Spine1..N, Tail) in place
function SwimWave.applyBones(
	bones: { [string]: Bone },
	spine: { string },
	phase: number,
	amplitude: number,
	bend: number
)
	local frames = restOf(bones)
	local head = bones.Head
	if head then
		turn(head, frames and frames.Head, SwimWave.headYaw(bend))
	end
	local n = #spine
	for i, name in spine do
		local bone = bones[name]
		if bone then
			turn(bone, frames and frames[name], SwimWave.yaw(i, n, phase, amplitude, bend))
		end
	end
end

return SwimWave
