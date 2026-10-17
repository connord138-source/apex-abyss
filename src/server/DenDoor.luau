--!strict
-- A den's front door on the plaza, and its way out inside the den (owner,
-- 2026-10-17: "The names of the dens look rough", "Needs to be more of an entrance
-- to their den not just a hole with light coming out of it"). Each doorway in the
-- cavern wall (Cave.denDoor: a round alcove with a flat sill) gets:
--   - a chunky arch of rounded stones (the rounded-rock rule, in parts so it stays
--     crisp) on stacked jamb stones, all outside the opening;
--   - a nameplate on the arch's crown (Decor.plaque): the owner's name on one line
--     and the den's level (NOOK ... SANCTUM) under it, each line scaled to fit, so
--     a 20-character name is never cut off;
--   - a lantern on each jamb, a stone threshold with two steps down to the paving,
--     and coral, sponges and kelp at the jambs' feet (not on a tunnel's side);
--   - the portal at the alcove's back as a bubble curtain: a dark pane in a
--     stepped brass collar, a faint ForceField shimmer over it and bubbles rising
--     across it, where it was a glowing disc.
-- An empty den reads shut: a slate plaque saying EMPTY DEN, unlit lanterns and a
-- dim, still curtain (its portal lets no one in: DenDoorController).
--
-- Nothing reaches inside the alcove's radius (10.5) or the sill's width, so a LV 100
-- fish (collider ~6.8) swims in as before, and the portal's trigger (Layout.doorAt)
-- is unchanged. tools/preview/run_hub.sh renders it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Decor = require(script.Parent.Decor)

local World = Config.World
local hub = World.hub
local part = Decor.part

local DenDoor = {}

-- Warm sea-sandstone stones (the doorways' rock is Sandstone, Cave.luau)
local STONES = {
	Color3.fromRGB(214, 186, 140),
	Color3.fromRGB(196, 166, 122),
	Color3.fromRGB(226, 200, 156),
	Color3.fromRGB(184, 154, 112),
}
local JAMB_STONES = {
	Color3.fromRGB(176, 148, 108),
	Color3.fromRGB(194, 164, 120),
	Color3.fromRGB(206, 178, 134),
}
local MORTAR = Color3.fromRGB(128, 104, 76)
local STEP = Color3.fromRGB(168, 150, 120)
local STEP_EDGE = Color3.fromRGB(196, 178, 146)
local LACQUER_EMPTY = Color3.fromRGB(52, 62, 70)
local TRIM_EMPTY = Color3.fromRGB(112, 120, 126)
local TEXT_EMPTY = Color3.fromRGB(150, 168, 176)
local CURTAIN = Color3.fromRGB(110, 206, 224)
local CURTAIN_SHUT = Color3.fromRGB(70, 104, 114)
local PANE = Color3.fromRGB(10, 38, 52)
local PANE_SHUT = Color3.fromRGB(20, 30, 36)
local GLOW = Color3.fromRGB(130, 222, 232)

-- The doorway's shape (Cave.denDoor), in the door's frame (Layout.doorFrame: the
-- portal's middle, -Z toward the hub)
local WALL_Z = -9 -- the cavern wall's face (hub.radius)
local ARCH_IN = 11 -- the arch stones' inner edge (the alcove's radius is 10.5)
local ARCH_OUT = 15
local DEPTH = 3.0 -- how far the stones stand out from the wall
local PLAQUE = Vector2.new(18.6, 6.0)

type Door = {
	plaque: Decor.Plaque,
	lanterns: { Decor.Lantern },
	curtain: BasePart,
	pane: BasePart,
	bubbles: ParticleEmitter,
	shimmer: ParticleEmitter,
	glow: PointLight,
}

local doors: { [number]: Door } = {}

-- The arch over an opening of radius `inner` (its middle at `frame`, the wall at
-- local z `wall`, the stones standing out toward -Z, springing at y 0) and its
-- jambs down to `floor`: eleven rounded stones over the top and four a side,
-- overlapping, on a darker band of mortar so no rock shows between them. Returns
-- the jambs' middle (x) and the stones' middle (z).
local function arch(
	parent: Instance,
	frame: CFrame,
	inner: number,
	outer: number,
	wall: number,
	floor: number,
	seed: number
): (number, number)
	local rng = Random.new(seed)
	local thick = outer - inner
	local z = wall - DEPTH / 2 + 0.3 -- sunk a little into the rock
	local mid = (inner + outer) / 2
	local count = 11
	local step = math.pi / (count - 1)
	-- The mortar band: flat blocks against the wall behind the stones
	local bands = 6
	for i = 0, bands - 1 do
		local theta = (i + 0.5) * math.pi / bands
		local chord = 2 * mid * math.sin(math.pi / bands / 2) + 0.6
		part(parent, {
			Name = "ArchMortar",
			Size = Vector3.new(chord, thick + 0.5, 1.2),
			CFrame = frame
				* CFrame.new(math.cos(theta) * mid, math.sin(theta) * mid, wall - 0.4)
				* CFrame.Angles(0, 0, theta - math.pi / 2),
			Color = MORTAR,
			CanCollide = false,
		})
	end
	for i = 0, count - 1 do
		-- 0 = the right springing (local +X), up over the top to the left
		local theta = i * step
		local length = mid * step * 1.42
		local stone = Decor.pebble(
			parent,
			"ArchStone",
			frame
				* CFrame.new(math.cos(theta) * mid, math.sin(theta) * mid, z)
				* CFrame.Angles(0, 0, theta - math.pi / 2),
			Vector3.new(length * rng:NextNumber(0.95, 1.06), thick * rng:NextNumber(0.98, 1.08), DEPTH),
			STONES[(i % #STONES) + 1]
		)
		stone.CanCollide = true
	end
	-- The jambs: four stones a side from the floor up to the springing, the bottom
	-- one bigger, on their own mortar
	local jambX = inner + thick / 2 - 1.0 -- hugging the sill's straight sides (it's 18 wide)
	local heights = { 4.2, 3.6, 3.4, 3.2 }
	local total = 0
	for _, h in heights do
		total += h
	end
	local scale = (0.6 - floor) / total
	for side = -1, 1, 2 do
		part(parent, {
			Name = "ArchMortar",
			Size = Vector3.new(thick + 0.5, -floor + 0.4, 1.2),
			CFrame = frame * CFrame.new(side * jambX, floor / 2 + 0.2, wall - 0.4),
			Color = MORTAR,
			CanCollide = false,
		})
		local y = floor
		for k, h in heights do
			local height = h * scale
			local width = thick * (if k == 1 then 1.16 else 1.04) * rng:NextNumber(0.97, 1.05)
			local stone = Decor.pebble(
				parent,
				"JambStone",
				frame * CFrame.new(side * (jambX + (if k == 1 then 0.2 else 0)), y + height / 2, z),
				Vector3.new(width, height * 1.18, DEPTH * (if k == 1 then 1.08 else 1)),
				JAMB_STONES[((k + (if side > 0 then 0 else 1)) % #JAMB_STONES) + 1]
			)
			stone.CanCollide = true
			y += height
		end
	end
	return jambX, z
end

-- Coral, sponges and kelp at a jamb's foot (`side` is the local X sign, `x` the
-- jamb's outer edge, `z` the stones' middle)
local function growth(
	parent: Instance,
	frame: CFrame,
	side: number,
	x: number,
	floor: number,
	z: number,
	rng: Random
)
	Decor.pebble(
		parent,
		"BrainCoral",
		frame * CFrame.new(side * (x + 0.6), floor + 1.0, z - 0.8) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
		Vector3.new(2.6, 2.0, 2.4),
		Decor.CORALS[rng:NextInteger(1, #Decor.CORALS)]
	).CanCollide =
		true
	Decor.sponges(parent, frame * CFrame.new(side * (x + 2.6), floor, z - 1.2), 2, rng)
	-- Kelp climbing the wall beside the arch
	Decor.kelp(parent, frame * CFrame.new(side * (x + 3.4), floor, z + 0.6), 3, 3.8, rng)
end

-- The portal: a dark pane in a stepped brass collar, a faint
-- ForceField shimmer over it, bubbles rising across it and a soft light in front
local function pane(
	parent: Instance,
	frame: CFrame,
	radius: number
): (BasePart, BasePart, ParticleEmitter, ParticleEmitter, PointLight)
	Decor.disc(parent, "PortalCollar", frame * CFrame.new(0, 0, 0.35), radius + 1.35, 0.4).Color =
		Decor.BRASS_DARK
	Decor.disc(parent, "PortalRing", frame * CFrame.new(0, 0, 0.25), radius + 0.75, 0.4).Color = Decor.BRASS
	local backing = Decor.disc(parent, "PortalPane", frame * CFrame.new(0, 0, 0.1), radius, 0.6)
	backing.Color = PANE
	local curtain = Decor.disc(parent, "Portal", frame * CFrame.new(0, 0, -0.35), radius, 0.2)
	curtain.Color = CURTAIN
	curtain.Material = Enum.Material.ForceField
	curtain.Transparency = 0.55
	-- Bubbles rise across the whole opening (any that start outside the circle are
	-- in the rock behind it)
	local sheet = part(parent, {
		Name = "PortalBubbles",
		Size = Vector3.new(radius * 2, radius * 2, 0.4),
		CFrame = frame * CFrame.new(0, 0, -0.75),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "Bubbles"
	bubbles.Rate = 26
	bubbles.Lifetime = NumberRange.new(2.2, 3.4)
	bubbles.Speed = NumberRange.new(1.5, 3)
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.SpreadAngle = Vector2.new(8, 8)
	bubbles.Acceleration = Vector3.new(0, 1.5, 0)
	bubbles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.3, 0.42),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	bubbles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.12, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	bubbles.LightEmission = 0.45
	bubbles.Color = ColorSequence.new(Color3.fromRGB(214, 250, 255))
	bubbles.Parent = sheet
	local shimmer = Instance.new("ParticleEmitter")
	shimmer.Name = "Shimmer"
	shimmer.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	shimmer.Rate = 5
	shimmer.Lifetime = NumberRange.new(1, 1.6)
	shimmer.Speed = NumberRange.new(0.2, 0.6)
	shimmer.SpreadAngle = Vector2.new(180, 180)
	shimmer.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	shimmer.Transparency = NumberSequence.new(0.35, 1)
	shimmer.LightEmission = 1
	shimmer.Color = ColorSequence.new(Color3.fromRGB(196, 250, 255))
	shimmer.Parent = sheet
	local lamp = part(parent, {
		Name = "PortalGlow",
		Size = Vector3.one,
		CFrame = frame * CFrame.new(0, 0, -4),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	local glow = Instance.new("PointLight")
	glow.Color = GLOW
	glow.Range = 16
	glow.Brightness = 0.5
	glow.Parent = lamp
	return curtain, backing, bubbles, shimmer, glow
end

-- Which local X side of den `index`'s doorway opens onto a tunnel's mouth (the
-- doors either side of a tunnel nearly touch it), or 0
local function tunnelSide(index: number): number
	local frame = Layout.doorFrame(index)
	local here = math.atan2(frame.Position.Z - hub.center.Z, frame.Position.X - hub.center.X)
	for _, delta in { -1, 1 } do
		local angle = here + delta * 2 * math.pi / hub.segments
		local segment = math.floor(((angle % (2 * math.pi)) / (2 * math.pi)) * hub.segments + 0.5)
				% hub.segments
			+ 1
		if Layout.segmentKind(segment) == "tunnel" then
			local probe = hub.center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * hub.radius
			local x = frame:PointToObjectSpace(Vector3.new(probe.X, frame.Position.Y, probe.Z)).X
			return if x > 0 then 1 else -1
		end
	end
	return 0
end

-- Den `index`'s front door on the plaza, into `parent` (its Den<i> model)
function DenDoor.front(parent: Instance, index: number)
	local frame = Layout.doorFrame(index)
	local folder = Instance.new("Model")
	folder.Name = "Doorway"
	local rng = Random.new(World.seed + index * 31)
	local floor = hub.denFloorY - frame.Position.Y -- the doorway's floor (the den floor's height)
	local jambX, stoneZ = arch(folder, frame, ARCH_IN, ARCH_OUT, WALL_Z, floor, World.seed + index)
	local outerX = jambX + (ARCH_OUT - ARCH_IN) / 2
	local plaque = Decor.plaque(
		folder,
		frame * CFrame.new(0, ARCH_IN + PLAQUE.Y / 2 - 0.4, WALL_Z - DEPTH - 0.1),
		PLAQUE,
		Decor.LACQUER,
		true
	)

	-- A lantern on each jamb's outer face
	local lanterns: { Decor.Lantern } = {}
	for side = -1, 1, 2 do
		table.insert(
			lanterns,
			Decor.lantern(
				folder,
				frame * CFrame.new(side * (outerX + 1.2), -2.2, stoneZ - 0.4),
				-side,
				false,
				14
			)
		)
	end

	-- The threshold: a slab over the sill's ledge (Cave.denFloor: it reaches 7 in
	-- front of the wall), a rounded nose, two steps down to the paving
	local ledge = WALL_Z - 7.4
	part(folder, {
		Name = "Threshold",
		Size = Vector3.new(19.6, 1.2, WALL_Z + 0.4 - ledge),
		CFrame = frame * CFrame.new(0, floor - 0.2, (WALL_Z + 0.4 + ledge) / 2),
		Color = STEP,
		CanCollide = true,
	})
	part(folder, {
		Name = "ThresholdNose",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(19.6, 1.2, 1.2),
		CFrame = frame * CFrame.new(0, floor - 0.2, ledge),
		Color = STEP_EDGE,
		CanCollide = false,
	})
	local paving = hub.paving - frame.Position.Y
	local rise = (floor + 0.4 - paving) / 3
	for k = 1, 2 do
		local top = floor + 0.4 - rise * k
		local bottom = paving - 0.6
		local depth = if k == 1 then 2.4 else 1.8
		local front = ledge - 0.6 - (k - 1) * 1.8
		part(folder, {
			Name = "Step",
			Size = Vector3.new(20.4 + k * 1.2, top - bottom, depth),
			CFrame = frame
				* CFrame.new(0, (top + bottom) / 2, front - depth / 2 + (if k == 1 then 0.6 else 0)),
			Color = if k == 1 then STEP_EDGE else STEP,
			CanCollide = true,
		})
	end

	-- Coral and kelp at the jambs' feet, on the side(s) away from a tunnel's mouth
	local open = tunnelSide(index)
	for side = -1, 1, 2 do
		if side ~= open then
			growth(folder, frame, side, outerX, floor, stoneZ, rng)
		end
	end

	local curtain, backing, bubbles, shimmer, glow = pane(folder, frame, Layout.DOOR_RADIUS)
	folder.Parent = parent
	doors[index] = {
		plaque = plaque,
		lanterns = lanterns,
		curtain = curtain,
		pane = backing,
		bubbles = bubbles,
		shimmer = shimmer,
		glow = glow,
	}
	DenDoor.setSign(index, nil, nil)
end

-- The way out inside den `index` (on its front wall, Layout.exitFrame): the same
-- arch, curtain and lanterns as the front door under a TO THE HUB plaque
function DenDoor.exit(parent: Instance, index: number)
	local frame = Layout.exitFrame(index)
	local radius = Config.Dens.exit.radius
	local folder = Instance.new("Model")
	folder.Name = "Exit"
	local floor = -Config.Dens.exit.y -- the deck, in the portal's frame
	-- The front wall is 0.6 behind the portal (its frame looks into the den)
	local inner = radius + 0.4
	local outer = radius + 3.6
	local wall = 0.6
	local jambX, stoneZ = arch(folder, frame, inner, outer, wall, floor, World.seed + 700 + index)
	local outerX = jambX + (outer - inner) / 2
	local plaque = Decor.plaque(
		folder,
		frame * CFrame.new(0, inner + 2.3, wall - DEPTH),
		Vector2.new(14, 4.6),
		Decor.LACQUER,
		true
	)
	plaque.title.Text = "TO THE HUB"
	if plaque.sub then
		plaque.sub.Text = "THE PLAZA"
	end
	for side = -1, 1, 2 do
		Decor.lantern(folder, frame * CFrame.new(side * (outerX + 1.2), -2.2, stoneZ - 0.4), -side, true, 14)
	end
	local rng = Random.new(World.seed + 900 + index)
	for side = -1, 1, 2 do
		growth(folder, frame, side, outerX, floor, stoneZ, rng)
	end
	pane(folder, frame * CFrame.new(0, 0, 0.3), radius)
	folder.Parent = parent
end

-- Who lives in den `index` (nil: nobody) and its level's name (Config/Dens
-- levels), on its nameplate; an empty den's door reads shut
function DenDoor.setSign(index: number, owner: string?, levelName: string?)
	local door = doors[index]
	if door == nil then
		return
	end
	local lived = owner ~= nil
	local plaque = door.plaque
	if owner then
		plaque.title.Text = `{Decor.oneLine(owner)}'S`
	else
		plaque.title.Text = "EMPTY DEN"
	end
	plaque.title.TextColor3 = if lived then Decor.TEXT else TEXT_EMPTY
	local sub = plaque.sub
	if sub then
		sub.Text = if lived then Decor.oneLine(levelName or "Den") else "VACANT"
		sub.TextColor3 = if lived then Decor.TEXT_GOLD else TEXT_EMPTY
	end
	plaque.board.Color = if lived then Decor.LACQUER else LACQUER_EMPTY
	for _, trim in plaque.trims do
		trim.Color = if lived
			then (if trim.Name == "PlaqueBoss" then Decor.BRASS_LIGHT else Decor.BRASS)
			else TRIM_EMPTY
	end
	for _, lantern in door.lanterns do
		Decor.light(lantern, lived)
	end
	door.curtain.Color = if lived then CURTAIN else CURTAIN_SHUT
	door.curtain.Transparency = if lived then 0.55 else 0.75
	door.pane.Color = if lived then PANE else PANE_SHUT
	door.bubbles.Rate = if lived then 26 else 4
	door.shimmer.Enabled = lived
	door.glow.Enabled = lived
end

return DenDoor
