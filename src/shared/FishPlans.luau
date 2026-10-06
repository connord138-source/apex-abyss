--!strict
-- Graybox body plans for the six playable species (until their Tripo models
-- arrive). Each plan is laid out in absolute positions, then normalized to a fish
-- one stud long and turned into FishBuilder part specs, with joints at the right
-- pivots: spine segments bend where they meet, fins and lobes swing from their
-- base. Every plan has the same core names (Body1, Head, Jaw, Belly, Stalk,
-- TailUp, TailDown, Dorsal, FinL, FinR, EyeL, EyeR) so the animator, cosmetics
-- and variants work on all of them. Forward is -Z.
export type PartSpec = {
	name: string,
	parent: string, -- part it hangs from ("Root" = the HumanoidRootPart)
	size: Vector3, -- unit size
	c0: CFrame, -- the joint in the parent's frame (unit)
	c1: CFrame, -- the joint in this part's frame (unit)
	shape: "Ellipsoid" | "Wedge" | "Block" | "Ball",
	color: "back" | "belly" | "fin" | "eye" | "fixed",
	fixed: Color3?, -- the color when `color` is "fixed"
	material: Enum.Material?,
	transparency: number?,
	light: Color3?, -- a small light in the part (an angler's lure)
}

type Piece = {
	name: string,
	parent: string,
	size: Vector3,
	at: CFrame, -- the part's frame
	pivot: CFrame, -- where it bends from
	shape: "Ellipsoid" | "Wedge" | "Block" | "Ball",
	color: "back" | "belly" | "fin" | "eye" | "fixed",
	fixed: Color3?,
	material: Enum.Material?,
	light: Color3?,
}

type Dims = { w: number, h: number, l: number }

type Options = {
	head: Dims,
	jaw: Dims,
	body: Dims,
	segs: { Dims }, -- behind Body1: Body2, Body3, ...
	stalk: Dims,
	tail: { h: number, l: number, angle: number, down: number },
	dorsal: { h: number, l: number, at: number, shape: "Ellipsoid" | "Wedge" },
	fins: { l: number, w: number, droop: number },
	eyes: { size: number, googly: boolean },
}

-- Where a standard fish's pieces landed (for a plan's extras).
type Layout = {
	body1Front: number,
	body1Center: number,
	headCenter: number,
	stalkBack: number,
	segCenters: { number },
}

local WHITE = Color3.fromRGB(250, 250, 248)
local IVORY = Color3.fromRGB(240, 232, 210)
local LURE = Color3.fromRGB(255, 236, 140)
local OVERLAP = 0.22

local function piece(
	name: string,
	parent: string,
	size: Vector3,
	at: CFrame,
	pivot: CFrame,
	shape: "Ellipsoid" | "Wedge" | "Block" | "Ball",
	color: "back" | "belly" | "fin" | "eye" | "fixed"
): Piece
	return {
		name = name,
		parent = parent,
		size = size,
		at = at,
		pivot = pivot,
		shape = shape,
		color = color,
	}
end

-- A fish laid out front (z = 0) to back, before normalizing.
local function standard(o: Options): ({ Piece }, Layout)
	local pieces: { Piece } = {}
	local headFront = 0
	local body1Front = o.head.l * (1 - OVERLAP)
	local body1Center = body1Front + o.body.l / 2
	-- Body1 hangs from the root; everything else hangs from it
	table.insert(
		pieces,
		piece(
			"Body1",
			"Root",
			Vector3.new(o.body.w, o.body.h, o.body.l),
			CFrame.new(0, 0, body1Center),
			CFrame.new(0, 0, body1Center),
			"Ellipsoid",
			"back"
		)
	)
	local headCenter = headFront + o.head.l / 2
	table.insert(
		pieces,
		piece(
			"Head",
			"Body1",
			Vector3.new(o.head.w, o.head.h, o.head.l),
			CFrame.new(0, o.body.h * 0.03, headCenter),
			CFrame.new(0, 0, body1Front),
			"Ellipsoid",
			"back"
		)
	)
	-- The jaw hinges at its back end, under the head
	local jawCenter = headCenter + o.head.l * 0.08
	table.insert(
		pieces,
		piece(
			"Jaw",
			"Head",
			Vector3.new(o.jaw.w, o.jaw.h, o.jaw.l),
			CFrame.new(0, -o.head.h * 0.3, jawCenter),
			CFrame.new(0, -o.head.h * 0.3, jawCenter + o.jaw.l / 2),
			"Ellipsoid",
			"belly"
		)
	)
	table.insert(
		pieces,
		piece(
			"Belly",
			"Body1",
			Vector3.new(o.body.w * 0.86, o.body.h * 0.62, o.body.l * 1.15),
			CFrame.new(0, -o.body.h * 0.22, body1Center + o.body.l * 0.05),
			CFrame.new(0, 0, body1Center),
			"Ellipsoid",
			"belly"
		)
	)
	-- The spine behind Body1, each segment bending at its front
	local parent = "Body1"
	local back = body1Front + o.body.l
	local segCenters: { number } = {}
	for i, seg in o.segs do
		local front = back - (if i == 1 then o.body.l else o.segs[i - 1].l) * OVERLAP
		local center = front + seg.l / 2
		local name = `Body{i + 1}`
		table.insert(
			pieces,
			piece(
				name,
				parent,
				Vector3.new(seg.w, seg.h, seg.l),
				CFrame.new(0, 0, center),
				CFrame.new(0, 0, front),
				"Ellipsoid",
				"back"
			)
		)
		table.insert(segCenters, center)
		parent = name
		back = front + seg.l
	end
	local lastL = if #o.segs > 0 then o.segs[#o.segs].l else o.body.l
	local stalkFront = back - lastL * OVERLAP
	local stalkCenter = stalkFront + o.stalk.l / 2
	table.insert(
		pieces,
		piece(
			"Stalk",
			parent,
			Vector3.new(o.stalk.w, o.stalk.h, o.stalk.l),
			CFrame.new(0, 0, stalkCenter),
			CFrame.new(0, 0, stalkFront),
			"Ellipsoid",
			"back"
		)
	)
	local stalkBack = stalkFront + o.stalk.l
	-- Tail lobes swing from the end of the stalk
	local base = CFrame.new(0, 0, stalkBack - o.stalk.l * 0.15)
	local angle = math.rad(o.tail.angle)
	table.insert(
		pieces,
		piece(
			"TailUp",
			"Stalk",
			Vector3.new(0.025, o.tail.h, o.tail.l),
			base * CFrame.Angles(angle, 0, 0) * CFrame.new(0, o.tail.h / 2, 0),
			base,
			"Ellipsoid",
			"fin"
		)
	)
	local downH = o.tail.h * o.tail.down
	table.insert(
		pieces,
		piece(
			"TailDown",
			"Stalk",
			Vector3.new(0.025, downH, o.tail.l * 0.92),
			base * CFrame.Angles(-angle, 0, 0) * CFrame.new(0, -downH / 2, 0),
			base,
			"Ellipsoid",
			"fin"
		)
	)
	local dorsalZ = body1Front + o.body.l * o.dorsal.at
	local dorsalBase = CFrame.new(0, o.body.h * 0.42, dorsalZ)
	table.insert(
		pieces,
		piece(
			"Dorsal",
			"Body1",
			Vector3.new(0.022, o.dorsal.h, o.dorsal.l),
			dorsalBase * CFrame.new(0, o.dorsal.h / 2, 0),
			dorsalBase,
			o.dorsal.shape,
			"fin"
		)
	)
	-- Pectoral fins, swept back and drooping
	for side = -1, 1, 2 do
		local root = CFrame.new(side * o.body.w * 0.42, -o.body.h * 0.18, body1Front + o.body.l * 0.25)
		local fin = root
			* CFrame.Angles(0, side * math.rad(-28), side * math.rad(-o.fins.droop))
			* CFrame.new(side * o.fins.l / 2, 0, 0)
		table.insert(
			pieces,
			piece(
				if side < 0 then "FinL" else "FinR",
				"Body1",
				Vector3.new(o.fins.l, 0.016, o.fins.w),
				fin,
				root,
				"Ellipsoid",
				"fin"
			)
		)
	end
	-- Eyes (googly ones get a white ball with a pupil)
	for side = -1, 1, 2 do
		local name = if side < 0 then "EyeL" else "EyeR"
		local size = o.eyes.size
		local eyeAt = CFrame.new(side * o.head.w * 0.36, o.head.h * 0.17, headCenter - o.head.l * 0.12)
		if o.eyes.googly then
			local white = piece(name, "Head", Vector3.one * size, eyeAt, eyeAt, "Ball", "fixed")
			white.fixed = WHITE
			table.insert(pieces, white)
			local pupilAt = eyeAt * CFrame.new(side * size * 0.28, 0, -size * 0.22)
			table.insert(
				pieces,
				piece(
					if side < 0 then "PupilL" else "PupilR",
					name,
					Vector3.one * size * 0.5,
					pupilAt,
					pupilAt,
					"Ball",
					"eye"
				)
			)
		else
			table.insert(pieces, piece(name, "Head", Vector3.one * size, eyeAt, eyeAt, "Ball", "eye"))
		end
	end
	return pieces,
		{
			body1Front = body1Front,
			body1Center = body1Center,
			headCenter = headCenter,
			stalkBack = stalkBack,
			segCenters = segCenters,
		}
end

-- Normalizes a layout to one stud long, centered on the root, and makes the
-- joints: C0 is the pivot in the parent's frame, C1 the pivot in the part's.
local function finalize(pieces: { Piece }): { PartSpec }
	local minZ, maxZ = math.huge, -math.huge
	for _, p in pieces do
		local half = p.size / 2
		for _, corner in
			{
				Vector3.new(half.X, half.Y, half.Z),
				Vector3.new(-half.X, half.Y, half.Z),
				Vector3.new(half.X, -half.Y, half.Z),
				Vector3.new(half.X, half.Y, -half.Z),
				Vector3.new(-half.X, -half.Y, half.Z),
				Vector3.new(-half.X, half.Y, -half.Z),
				Vector3.new(half.X, -half.Y, -half.Z),
				Vector3.new(-half.X, -half.Y, -half.Z),
			}
		do
			local z = p.at:PointToWorldSpace(corner).Z
			minZ = math.min(minZ, z)
			maxZ = math.max(maxZ, z)
		end
	end
	local k = 1 / (maxZ - minZ)
	local shift = Vector3.new(0, 0, -(minZ + maxZ) / 2)
	local function norm(cframe: CFrame): CFrame
		return CFrame.new((cframe.Position + shift) * k) * cframe.Rotation
	end
	local absolute: { [string]: CFrame } = { Root = CFrame.identity }
	for _, p in pieces do
		absolute[p.name] = norm(p.at)
	end
	local specs: { PartSpec } = {}
	for _, p in pieces do
		local pivot = norm(p.pivot)
		table.insert(specs, {
			name = p.name,
			parent = p.parent,
			size = p.size * k,
			c0 = absolute[p.parent]:Inverse() * pivot,
			c1 = absolute[p.name]:Inverse() * pivot,
			shape = p.shape,
			color = p.color,
			fixed = p.fixed,
			material = p.material,
			light = p.light,
		})
	end
	return specs
end

local function dims(w: number, h: number, l: number): Dims
	return { w = w, h = h, l = l }
end

local PLANS: { [string]: { PartSpec } } = {}
local SPINES: { [string]: { string } } = {}

local function register(id: string, pieces: { Piece }, segCount: number)
	PLANS[id] = finalize(pieces)
	local spine: { string } = {}
	for i = 1, segCount do
		table.insert(spine, `Body{i + 1}`)
	end
	table.insert(spine, "Stalk")
	SPINES[id] = spine
end

-- The starter: round, friendly, big googly eyes.
do
	local options: Options = {
		head = dims(0.3, 0.3, 0.3),
		jaw = dims(0.18, 0.06, 0.16),
		body = dims(0.37, 0.39, 0.34),
		segs = { dims(0.28, 0.3, 0.22) },
		stalk = dims(0.1, 0.14, 0.14),
		tail = { h = 0.25, l = 0.13, angle = 40, down = 0.9 },
		dorsal = { h = 0.14, l = 0.2, at = 0.3, shape = "Ellipsoid" },
		fins = { l = 0.15, w = 0.09, droop = 18 },
		eyes = { size = 0.14, googly = true },
	}
	local pieces = standard(options)
	register("Nibbler", pieces, #options.segs)
end

-- 'Cuda: long and slim with a pointed underbite and a second dorsal near the tail.
do
	local options: Options = {
		head = dims(0.14, 0.15, 0.32),
		jaw = dims(0.1, 0.05, 0.28),
		body = dims(0.18, 0.2, 0.32),
		segs = { dims(0.16, 0.18, 0.3), dims(0.13, 0.15, 0.28), dims(0.1, 0.12, 0.22) },
		stalk = dims(0.06, 0.08, 0.12),
		tail = { h = 0.24, l = 0.1, angle = 46, down = 1 },
		dorsal = { h = 0.09, l = 0.12, at = 0.45, shape = "Wedge" },
		fins = { l = 0.1, w = 0.06, droop = 15 },
		eyes = { size = 0.05, googly = false },
	}
	local pieces, layout = standard(options)
	local second = CFrame.new(0, 0.07, layout.segCenters[3])
	local fin = piece(
		"Dorsal2",
		"Body4",
		Vector3.new(0.02, 0.07, 0.1),
		second * CFrame.new(0, 0.035, 0),
		second,
		"Wedge",
		"fin"
	)
	table.insert(pieces, fin)
	register("Cuda", pieces, #options.segs)
end

-- Pufferfish: a round body covered in spines.
do
	local options: Options = {
		head = dims(0.36, 0.36, 0.26),
		jaw = dims(0.14, 0.05, 0.1),
		body = dims(0.52, 0.52, 0.44),
		segs = { dims(0.3, 0.32, 0.18) },
		stalk = dims(0.1, 0.12, 0.1),
		tail = { h = 0.2, l = 0.12, angle = 35, down = 0.9 },
		dorsal = { h = 0.08, l = 0.1, at = 0.7, shape = "Ellipsoid" },
		fins = { l = 0.12, w = 0.1, droop = 10 },
		eyes = { size = 0.1, googly = false },
	}
	local pieces, layout = standard(options)
	local count = 18
	for i = 1, count do
		local ring = (i % 3) - 1 -- three rings: front, middle, back
		local angle = (i / count) * 2 * math.pi * 3
		local out = Vector3.new(math.cos(angle), math.sin(angle), 0)
		local at = Vector3.new(
			out.X * options.body.w * 0.48,
			out.Y * options.body.h * 0.48,
			layout.body1Center + ring * options.body.l * 0.28
		)
		local frame = CFrame.lookAt(at, at + out, Vector3.zAxis) * CFrame.new(0, 0, -0.03)
		table.insert(
			pieces,
			piece(`Spine{i}`, "Body1", Vector3.new(0.018, 0.018, 0.09), frame, frame, "Ellipsoid", "fin")
		)
	end
	register("Puffer", pieces, #options.segs)
end

-- Moray Eel: a long tapering ribbon with a fin ridge down its back.
do
	local segs = {}
	for i = 1, 5 do
		local taper = 1 - (i - 1) * 0.14
		table.insert(segs, dims(0.14 * taper, 0.17 * taper, 0.22))
	end
	local options: Options = {
		head = dims(0.14, 0.16, 0.22),
		jaw = dims(0.1, 0.05, 0.17),
		body = dims(0.15, 0.17, 0.24),
		segs = segs,
		stalk = dims(0.05, 0.08, 0.14),
		tail = { h = 0.1, l = 0.12, angle = 30, down = 0.9 },
		dorsal = { h = 0.06, l = 0.24, at = 0.5, shape = "Ellipsoid" },
		fins = { l = 0.06, w = 0.04, droop = 10 },
		eyes = { size = 0.045, googly = false },
	}
	local pieces, layout = standard(options)
	for i, center in layout.segCenters do
		local base = CFrame.new(0, segs[i].h * 0.45, center)
		table.insert(
			pieces,
			piece(
				`Ridge{i}`,
				`Body{i + 1}`,
				Vector3.new(0.016, 0.06, 0.24),
				base * CFrame.new(0, 0.02, 0),
				base,
				"Ellipsoid",
				"fin"
			)
		)
	end
	register("Eel", pieces, #segs)
end

-- Reef Shark: pointed snout, tall dorsal, big pectorals, a lopsided tail.
do
	local options: Options = {
		head = dims(0.22, 0.2, 0.3),
		jaw = dims(0.16, 0.06, 0.18),
		body = dims(0.3, 0.3, 0.36),
		segs = { dims(0.24, 0.25, 0.28), dims(0.16, 0.18, 0.24) },
		stalk = dims(0.07, 0.09, 0.14),
		tail = { h = 0.38, l = 0.14, angle = 40, down = 0.55 },
		dorsal = { h = 0.25, l = 0.22, at = 0.28, shape = "Wedge" },
		fins = { l = 0.27, w = 0.12, droop = 24 },
		eyes = { size = 0.045, googly = false },
	}
	local pieces = standard(options)
	register("Shark", pieces, #options.segs)
end

-- Anglerfish: a huge head, an underbite full of teeth, and a glowing lure.
do
	local options: Options = {
		head = dims(0.42, 0.38, 0.34),
		jaw = dims(0.4, 0.12, 0.32),
		body = dims(0.34, 0.32, 0.3),
		segs = { dims(0.22, 0.24, 0.2) },
		stalk = dims(0.08, 0.1, 0.1),
		tail = { h = 0.22, l = 0.1, angle = 30, down = 0.9 },
		dorsal = { h = 0.07, l = 0.1, at = 0.7, shape = "Ellipsoid" },
		fins = { l = 0.1, w = 0.07, droop = 12 },
		eyes = { size = 0.06, googly = false },
	}
	local pieces, layout = standard(options)
	local stalkBase = CFrame.new(0, options.head.h * 0.45, layout.headCenter + 0.02)
	local stalkAt = stalkBase * CFrame.Angles(math.rad(50), 0, 0) * CFrame.new(0, 0, -0.17)
	table.insert(
		pieces,
		piece("LureStalk", "Head", Vector3.new(0.02, 0.02, 0.34), stalkAt, stalkBase, "Ellipsoid", "fin")
	)
	local bulbAt = stalkAt * CFrame.new(0, 0, -0.18)
	local bulb = piece("LureBulb", "LureStalk", Vector3.one * 0.08, bulbAt, bulbAt, "Ball", "fixed")
	bulb.fixed = LURE
	bulb.material = Enum.Material.Neon
	bulb.light = LURE
	table.insert(pieces, bulb)
	for i = 1, 6 do
		local x = (i - 3.5) * options.jaw.w * 0.15
		local tooth = CFrame.new(x, -options.head.h * 0.3 + options.jaw.h * 0.5, layout.headCenter - 0.06)
		local t = piece(`Tooth{i}`, "Jaw", Vector3.new(0.02, 0.06, 0.02), tooth, tooth, "Wedge", "fixed")
		t.fixed = IVORY
		table.insert(pieces, t)
	end
	register("Angler", pieces, #options.segs)
end

local FishPlans = {}

-- The part specs for a body plan (the Nibbler's if `id` is unknown).
function FishPlans.get(id: string?): { PartSpec }
	return PLANS[id or "Nibbler"] or PLANS.Nibbler
end

-- The segments behind Body1, front to back, for the swim wave.
function FishPlans.spine(id: string?): { string }
	return SPINES[id or "Nibbler"] or SPINES.Nibbler
end

return FishPlans
