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

-- Each rig's bones' rest rotations in the fish's own axes: those of the part the bones
-- live in (a rigged model faces -Z and is never turned, so its mesh's frame is the
-- fish's: Y up, -Z ahead, X to its right). Imported bones point their own Y down the
-- spine (Blender's bone axis), so a turn about a bone's own Y rolled the body instead
-- of swinging the tail (playtest 2026-10-07: tails moved +-0.02 studs); the swing is
-- turned into each bone's axes. Taken once per rig, before any turn is applied, so no
-- pose leaks in. (Until 2026-10-19 they were taken in the Root bone's axes, which
-- share only the up axis with the fish's: from rig_fish.py's FBX the root comes in
-- facing the other way, so a yaw was the same but a turn about X, a jaw or an arch,
-- went the wrong way round.)
local restFrames: { [any]: { [string]: CFrame } } = setmetatable({}, { __mode = "k" }) :: any
-- (and where each bone sits at rest, in the same axes: a head turns about its neck)
local restPlaces: { [any]: { [string]: Vector3 } } = setmetatable({}, { __mode = "k" }) :: any

local function restOf(bones: { [string]: Bone }): { [string]: CFrame }?
	local root: Bone? = bones.Root
	if root == nil then
		return nil
	end
	local frames = restFrames[bones]
	if frames == nil then
		local made: { [string]: CFrame } = {}
		local places: { [string]: Vector3 } = {}
		local holder = root.Parent
		local rootFrame = if holder and holder:IsA("BasePart")
			then holder.CFrame
			else root.WorldCFrame * root.Transform:Inverse()
		for name, bone in bones do
			local rest = rootFrame:ToObjectSpace(bone.WorldCFrame * bone.Transform:Inverse())
			made[name] = rest.Rotation
			places[name] = rest.Position
		end
		restFrames[bones] = made
		restPlaces[bones] = places
		frames = made
	end
	return frames
end

local function turn(bone: Bone, frame: CFrame?, yaw: number, pitch: number?)
	local rotation = CFrame.Angles(pitch or 0, yaw, 0)
	bone.Transform = if frame then frame:Inverse() * rotation * frame else rotation
end

-- Drives a rigged body's bones (Head, Spine1..N, Tail) in place. `bend` curls the body
-- side to side (positive swings the tail to the fish's right, +X: the body concave to
-- its right, the shape of a right turn), `arch` (radians, optional) up or down along
-- its length (positive tips the tail down: a squid's arms curling under it). `look` (radians,
-- optional) turns the head alone about its neck, the body behind it held (a hunter
-- eyeing its fish, a head shake): the chain runs Head -> Spine1 -> ..., so a turn of
-- the Head bone on its own swings the whole body about the snout.
function SwimWave.applyBones(
	bones: { [string]: Bone },
	spine: { string },
	phase: number,
	amplitude: number,
	bend: number,
	arch: number?,
	look: number?
)
	local frames = restOf(bones)
	local places = restPlaces[bones]
	local head = bones.Head
	local headAt: Vector3? = if places then places.Head else nil
	local neckAt: Vector3? = if places and spine[1] then places[spine[1]] else nil
	local turned = look ~= nil and look ~= 0 and headAt ~= nil and neckAt ~= nil
	if head then
		if turned then
			local frame = frames and frames.Head
			local neck = (neckAt :: Vector3) - (headAt :: Vector3)
			local rotation = CFrame.Angles(0, SwimWave.headYaw(bend), 0)
				* CFrame.new(neck)
				* CFrame.Angles(0, look :: number, 0)
				* CFrame.new(-neck)
			head.Transform = if frame then frame:Inverse() * rotation * frame else rotation
		else
			turn(head, frames and frames.Head, SwimWave.headYaw(bend))
		end
	end
	local n = #spine
	for i, name in spine do
		local bone = bones[name]
		if bone then
			local pitch = if arch then arch * (0.3 + 0.7 * i / n) else nil
			local yaw = SwimWave.yaw(i, n, phase, amplitude, bend)
				- (if turned and i == 1 then look :: number else 0)
			turn(bone, frames and frames[name], yaw, pitch)
		end
	end
end

-- Turns one bone (a Jaw, a FinL or FinR, the Head) by `rotation` in the fish's own
-- axes (Y up, -Z ahead, X to its right), replacing whatever it had this frame. A jaw
-- opens with a negative turn about X (CFrame.Angles(-open, 0, 0)), as FishAnimator's;
-- a positive turn about Z tips a left fin's (FinL, at -X) tip down.
function SwimWave.setBone(bones: { [string]: Bone }, name: string, rotation: CFrame)
	local bone: Bone? = bones[name]
	if bone == nil then
		return
	end
	local frames = restOf(bones)
	local frame = frames and frames[name]
	bone.Transform = if frame then frame:Inverse() * rotation * frame else rotation
end

-- Whether a bare imported MeshPart needs turning round: the static GLB prey came in
-- facing +Z (owner, 2026-10-07: "swimming backwards"), while meshes cut from a
-- rigged FBX face -Z. The importer stamps `Facing`; without a stamp, a bare mesh is
-- taken as a static GLB.
function SwimWave.needsFlip(mesh: BasePart): boolean
	return mesh:GetAttribute("Facing") ~= "-Z"
end

return SwimWave
