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

-- Drives a rigged body's bones (Head, Spine1..N, Tail) in place
function SwimWave.applyBones(
	bones: { [string]: Bone },
	spine: { string },
	phase: number,
	amplitude: number,
	bend: number
)
	local head = bones.Head
	if head then
		head.Transform = CFrame.Angles(0, SwimWave.headYaw(bend), 0)
	end
	local n = #spine
	for i, name in spine do
		local bone = bones[name]
		if bone then
			bone.Transform = CFrame.Angles(0, SwimWave.yaw(i, n, phase, amplitude, bend), 0)
		end
	end
end

-- Whether a bare imported MeshPart needs turning round: the static GLB prey came in
-- facing +Z (owner, 2026-10-07: "swimming backwards"), while meshes cut from a
-- rigged FBX face -Z. The importer stamps `Facing`; without a stamp, a bare mesh is
-- taken as a static GLB.
function SwimWave.needsFlip(mesh: BasePart): boolean
	return mesh:GetAttribute("Facing") ~= "-Z"
end

return SwimWave
