--!strict
-- Effects on the top skins (owner, 2026-10-17: "When I say the skin needs movement or
-- glow I mean the skin needs EFFECTS. not just a ripple effect running over the
-- design ... Undertow should have the swirls moving"): the Tide Pass skins, the
-- Legendary and Mythic skins, the boss trophies and the treasure skins each wear a
-- set from Config/Shades `fx` (with `fxColor` / `fxColor2`). Built by Cosmetics when a
-- body dresses, driven every frame by Cosmetics.animate:
--
--   swirls    ribbons spiralling round the body from head to tail (Undertow, Jade)
--   ring      an accretion ring circling the body's middle (Void)
--   aurora    curtains of light waving over the back, streaming off it (Aurora)
--   currents  dark current ribbons along both flanks (Abyssal Current)
--   foam      white water ribbons off the pectorals (Riptide)
--   comet     a wide glowing tail (Comet)
--   rainbow   a rainbow ribbon off the tail (Prismatic, Prism)
--   sheen     a polished shine: a band of light running head to tail every 2.5 s,
--             a light riding it so the skin's own gloss catches it, sparks
--             following it and fine glitter on the body, all in the skin's effect
--             colours (Golden's warm gold, Silver's cool silver-white)
--   halo      a ring of light over the head, turning (Divine)
--   crown     a spiked gold band seated on the head (Lantern King)
--   rays      soft light rays fanning up over the head (Divine)
--   sunburst  rays turning round the body (Sunburst)
--   arcs      lightning crawling over the body in bursts (Thunder)
--   rim       an outline in the effect colour; rainbowRim cycles through the hues
--             over a faint holographic fill
--   anything else is a Shared/Fx particle preset emitted from the body (mist,
--   stardust, nebula, vortex, gold, embers, drips, crystal, shimmer, ...)
--
-- Ribbons sway a little on their own, so they draw even while the fish holds still.
-- Past top speed their trails shorten, so a dash draws about the streak a cruise
-- does (playtest 2026-10-17: Undertow's swirls stretched into long zig-zags that
-- read like lightning on a dash).
--
-- Every ribbon starts on the body (owner, 2026-10-18: Prism's rainbow "follows above
-- the fish, you can see where the line starts", and a Comet's tail stood "right in
-- your face"): a tail ribbon is centred on the tail fin's middle line and no taller
-- than the fin, a flank ribbon starts at the skin. Your own fish's ribbons and
-- particles never reach your camera: like the boost trails (TrailController), each
-- one's lifetime is cut to `BEHIND` of the time the following camera takes to reach
-- where it was shed, and a ribbon fades back while the camera looks along it from
-- behind. Other players' fish keep theirs whole.
-- None of this draws in a ViewportFrame (Roblox draws no particles, trails, beams or
-- lights there): the menus' fish and the cards get 2D stand-ins instead
-- (src/client/PreviewFx: sparkles in the effect colours, the skin's light behind the
-- fish, the shine as the viewport's light sweeping over it).
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Fx = require(script.Parent.Fx)
local ShadesConfig = require(script.Parent.Config.Shades)
local Size = require(script.Parent.Size)

local SkinFx = {}

-- Your own fish's effects die before the camera, following, reaches where they were
-- shed (TrailController's numbers)
local BEHIND = 0.75 -- of the time the camera takes to reach it
local SHORTEST = 0.12 -- seconds a ribbon or particle lives at the least
-- Looking along your own fish's ribbons from behind fades them back, to this much at
-- most (a hint of the tail stays)
local VIEW_FADE = 0.8

-- The shine (Golden, Silver): one sweep head to tail every PERIOD seconds, taking SWEEP
local SHEEN_PERIOD = 2.5
local SHEEN_SWEEP = 0.95

-- Where a tail ribbon starts: on the tail fin, a little in from its trailing edge,
-- so the ribbon's first edge is in the fin
local TAIL = 0.96

-- How a ribbon is seated: "surface" stands up off the skin at its angle round the
-- body (aurora's streamers off the curtains), "radial" points out from the skin
-- (currents, foam off the pectorals), "centered" straddles the body's middle line
-- (a tail ribbon: it trails from the tail fin itself)
type Seat = "surface" | "radial" | "centered"

type Ribbon = {
	a0: Attachment,
	a1: Attachment,
	trail: Trail,
	at: number, -- how far along the body (0 head, 1 tail)
	side: number, -- angle round the body (0 the back, π/2 the right flank)
	out: number, -- how far out from the body's surface, in lengths
	width: number, -- in lengths
	seat: Seat,
	phase: number,
	sway: number,
	lifetime: number, -- its trail's at a cruise
	keep: number, -- the least share of that kept on a dash
	life: number, -- the lifetime it has now
	fade: NumberSequence, -- its own transparency
	faded: { [number]: NumberSequence }, -- that, faded back by tenths (the view fade)
	shown: number, -- the tenth it shows now
}

type Orbiter = {
	a0: Attachment,
	a1: Attachment,
	trail: Trail,
	phase: number,
	last: number,
	lifetime: number,
	life: number, -- the lifetime it has now
	fade: number, -- how far it's faded out, past top speed or seen from behind
}

-- A particle emitter that sheds into the water (cut for your own fish), with its own
-- lifetime
type Shed = { emitter: ParticleEmitter, life: NumberRange, cap: number }

-- The shine (`sheen`; Golden, Silver): the band across the flank (three points, upper flank to
-- lower), the light riding just off it, the sparks it sheds, and the glitter's seat,
-- which hops over the body
type Sweep = {
	points: { Attachment },
	beams: { Beam },
	lamp: Attachment,
	light: PointLight,
	sparks: ParticleEmitter,
	dust: Attachment,
	on: boolean,
}

type Arc = { points: { Attachment }, beams: { Beam } }

-- A curtain of light standing over the back (Aurora)
type Curtain = { a0: Attachment, a1: Attachment, beam: Beam, at: number, phase: number }

-- Where a crown sits on a fish's head, in its unit box (nose at z -0.5, the box's
-- middle at 0, as Shared/PartFit's anchors): `z` along the body, `y` the head's top there,
-- `radius` and `tilt` (radians, its top leaning back)
type CrownSeat = { z: number, y: number, radius: number, tilt: number }

export type Live = {
	core: BasePart,
	length: number,
	bones: { Bone }, -- head to tail
	swirls: { Orbiter },
	ring: { Orbiter },
	ribbons: { Ribbon },
	curtains: { Curtain },
	halo: {
		points: { Attachment },
		tips: { { tip: Attachment, base: number } },
		radius: number,
		lift: number,
		crown: boolean,
		seat: CrownSeat?,
	}?,
	rays: { points: { Attachment }, tips: { Attachment } }?,
	sunburst: { center: Attachment, tips: { Attachment } }?,
	arcs: { Arc },
	nextArc: number,
	sheds: { Shed },
	sweep: Sweep?,
	rim: Highlight?,
	rainbowRim: boolean,
	color: Color3,
	color2: Color3,
	speed: number, -- studs a second, eased
	lastPos: Vector3?,
	lastT: number,
}

-- Seats measured from the rigged FBX (assets/fbx/species). The Angler's box top
-- (0.37 over the middle) is its lure stalk's arch, so a crown set on the box's height
-- floated over the lure (playtest 2026-10-17: 3.8 studs over the root of a 7.5-stud
-- fish); the head's own top is 0.19-0.22 between the stalk's foot (z -0.2 to -0.16)
-- and the dorsal fin (from z -0.04), its flat crest about 0.08 to each side. The
-- crown hugs the back of the stalk's foot, its band just clear of the crest at the
-- sides and front, its back dipping into the head as it leans back (about 5°).
local SEATS: { [string]: CrownSeat } = {
	Angler = { z = -0.105, y = 0.206, radius = 0.075, tilt = 0.08 },
}

local function colorsOf(shade: ShadesConfig.Shade): (Color3, Color3)
	local c = shade.fxColor or shade.glow or shade.sparkle or shade.fin
	return c, shade.fxColor2 or shade.belly
end

-- The body's bones from head to tail (Head, Spine1..n, Tail), when it has them
local function spineOf(holder: Instance): { Bone }
	local found: { [string]: Bone } = {}
	for _, descendant in holder:GetDescendants() do
		if descendant:IsA("Bone") then
			found[descendant.Name] = descendant
		end
	end
	local list: { Bone } = {}
	if found.Head then
		table.insert(list, found.Head)
	end
	local i = 1
	while found[`Spine{i}`] do
		table.insert(list, found[`Spine{i}`])
		i += 1
	end
	if found.Tail then
		table.insert(list, found.Tail)
	end
	return list
end

-- The fish's own frame: its root (the box's middle), facing its heading and banked
-- with it (the body Model has no PrimaryPart, so its own pivot doesn't turn with
-- the fish)
local function frameOf(body: Model): CFrame
	local holder = body.Parent
	if holder and holder:IsA("Model") then
		local root: Instance? = holder.PrimaryPart
			or holder:FindFirstChild("HumanoidRootPart")
			or holder:FindFirstChild("Root")
		if root and root:IsA("BasePart") then
			return root.CFrame
		end
	end
	return body:GetPivot()
end

-- A point on the body's middle line `f` of the way from head to tail, and the way
-- forward there
local function spineAt(live: Live, frame: CFrame, f: number, L: number): (Vector3, Vector3)
	local bones = live.bones
	if #bones < 2 then
		return frame.Position + frame.LookVector * (0.5 - f) * L, frame.LookVector
	end
	-- The bones run over the middle of the body: stretch them to the ends
	local span = (#bones - 1) * math.clamp((f - 0.08) / 0.84, 0, 1)
	local i = math.clamp(math.floor(span) + 1, 1, #bones - 1)
	local a = bones[i].TransformedWorldCFrame.Position
	local b = bones[i + 1].TransformedWorldCFrame.Position
	local forward = a - b
	forward = if forward.Magnitude > 1e-4 then forward.Unit else frame.LookVector
	local base = a:Lerp(b, span - (i - 1))
	-- Past the end bones, along the line they make
	if f < 0.08 then
		base += forward * (0.08 - f) * L
	elseif f > 0.92 then
		base -= forward * (f - 0.92) * L
	end
	return base, forward
end

-- The point on the bone line at `z` along the unit box (nose -0.5, tail +0.5) as the
-- bones lie now, and the way forward there; the box's middle line without bones
local function boneAt(live: Live, frame: CFrame, z: number, L: number): (Vector3, Vector3)
	local target = z * L
	local previous: Vector3? = nil
	local previousZ = 0
	for _, bone in live.bones do
		local p = bone.TransformedWorldCFrame.Position
		local along = frame:PointToObjectSpace(p).Z
		if previous and along > previousZ and along >= target and previousZ <= target then
			local forward = previous - p
			return previous:Lerp(p, (target - previousZ) / (along - previousZ)),
				if forward.Magnitude > 1e-4 then forward.Unit else frame.LookVector
		end
		previous, previousZ = p, along
	end
	return frame * Vector3.new(0, 0, target), frame.LookVector
end

-- `forward` made square to `up` (with a fallback), and the right hand there
local function square(forward: Vector3, up: Vector3, frame: CFrame): (Vector3, Vector3)
	local flat = forward - up * forward:Dot(up)
	flat = if flat.Magnitude > 1e-4 then flat.Unit else frame.LookVector
	local right = flat:Cross(up)
	return flat, if right.Magnitude > 1e-4 then right.Unit else frame.RightVector
end

-- The body's half width and half height at `f` (thinner toward the tail)
local function radiiAt(body: Model, f: number, L: number): (number, number)
	local w = body:GetAttribute("UnitW")
	local h = body:GetAttribute("UnitH")
	local taper = 1 - 0.55 * math.clamp((f - 0.35) / 0.65, 0, 1)
	return L * (if typeof(w) == "number" then w else 0.35) * 0.5 * taper,
		L * (if typeof(h) == "number" then h else 0.4) * 0.5 * taper
end

-- A point `out` lengths off the body's surface at `f` and angle `angle` round it
-- (0 = straight up off the back), and the way out from the body there
local function surface(
	live: Live,
	body: Model,
	frame: CFrame,
	f: number,
	angle: number,
	out: number,
	L: number
): (Vector3, Vector3)
	local center, forward = spineAt(live, frame, f, L)
	local right = forward:Cross(frame.UpVector)
	right = if right.Magnitude > 1e-4 then right.Unit else frame.RightVector
	local up = right:Cross(forward).Unit
	local rw, rh = radiiAt(body, f, L)
	local dir = up * math.cos(angle) + right * math.sin(angle)
	local reach = up * math.cos(angle) * rh + right * math.sin(angle) * rw
	return center + reach + dir * out * L, dir
end

-- An orbiter's trail, faded out `fade` of the way (0 as Fx.ribbon draws it)
local function orbitFade(fade: number): NumberSequence
	return Fx.keys({ 0, 0.15 + 0.7 * fade, 0.6, 0.5 + 0.4 * fade, 1, 1 })
end

-- `sequence` faded back by `k` (0 as it is, 1 gone)
local function fadedBy(sequence: NumberSequence, k: number): NumberSequence
	local list = {}
	for _, point in sequence.Keypoints do
		table.insert(list, NumberSequenceKeypoint.new(point.Time, 1 - (1 - point.Value) * (1 - k)))
	end
	return NumberSequence.new(list)
end

local function ribbon(
	live: Live,
	at: number,
	side: number,
	out: number,
	width: number,
	lifetime: number,
	color: ColorSequence,
	fade: NumberSequence?,
	seat: Seat?
): Ribbon
	local a0 = Fx.attachment(live.core, "FxRibbon0")
	local a1 = Fx.attachment(live.core, "FxRibbon1")
	local trail = Fx.ribbon(live.core, a0, a1, lifetime, color, fade)
	local made: Ribbon = {
		a0 = a0,
		a1 = a1,
		trail = trail,
		at = at,
		side = side,
		out = out,
		width = width,
		seat = seat or "surface",
		phase = math.random() * 10,
		sway = 0.06,
		lifetime = lifetime,
		keep = 0.5,
		life = lifetime,
		fade = trail.Transparency,
		faded = {},
		shown = 0,
	}
	table.insert(live.ribbons, made)
	return made
end

local function orbiter(live: Live, list: { Orbiter }, color: ColorSequence, lifetime: number, phase: number)
	local a0 = Fx.attachment(live.core, "FxOrbit0")
	local a1 = Fx.attachment(live.core, "FxOrbit1")
	local trail = Fx.ribbon(live.core, a0, a1, lifetime, color, orbitFade(0))
	table.insert(list, {
		a0 = a0,
		a1 = a1,
		trail = trail,
		phase = phase,
		last = 0,
		lifetime = lifetime,
		life = lifetime,
		fade = 0,
	})
end

-- Builds a shade's effects on a dressed body (`holder` is the mesh model, or the
-- body for a part-built fish; `core` its main part). Nil when the shade has none.
function SkinFx.build(
	body: Model,
	holder: Instance,
	core: BasePart,
	shade: ShadesConfig.Shade,
	length: number
): Live?
	local list = shade.fx
	if list == nil or #list == 0 then
		return nil
	end
	local c, c2 = colorsOf(shade)
	local live: Live = {
		core = core,
		length = length,
		bones = spineOf(holder),
		swirls = {},
		ring = {},
		ribbons = {},
		curtains = {},
		halo = nil,
		rays = nil,
		sunburst = nil,
		arcs = {},
		nextArc = 0,
		sheds = {},
		sweep = nil,
		rim = nil,
		rainbowRim = false,
		color = c,
		color2 = c2,
		speed = 0,
		lastPos = nil,
		lastT = 0,
	}
	local L = length
	local pair = ColorSequence.new(c, c2)
	for _, kind in list do
		if kind == "swirls" then
			for i = 1, 3 do
				orbiter(live, live.swirls, pair, 0.55, (i - 1) / 3)
			end
		elseif kind == "ring" then
			for i = 1, 2 do
				orbiter(live, live.ring, pair, 0.7, (i - 1) / 2)
			end
		elseif kind == "aurora" then
			local curtain = ColorSequence.new({
				ColorSequenceKeypoint.new(0, c),
				ColorSequenceKeypoint.new(0.5, c2),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 90, 255)),
			})
			-- Curtains standing over the back, waving: on a still fish the trailing
			-- ribbons alone were thin streaks (playtest 2026-10-17); two, softer, since
			-- three at brightness 1.6 read "bold, verging on loud" (PC 2026-10-18)
			for i, at in { 0.36, 0.62 } do
				local a0 = Fx.attachment(core, "FxCurtain0")
				local a1 = Fx.attachment(core, "FxCurtain1")
				local beam = Fx.beam(
					core,
					a0,
					a1,
					L * 0.22,
					L * 0.32,
					curtain,
					Fx.keys({ 0, 0.55, 0.2, 0.42, 0.65, 0.62, 1, 1 })
				)
				beam.Segments = 12
				beam.Brightness = 1.15
				table.insert(live.curtains, { a0 = a0, a1 = a1, beam = beam, at = at, phase = i * 1.9 })
			end
			-- and ribbons streaming off them as it swims (from the skin, shorter than
			-- the curtains, so their edge never shows over them)
			for i, at in { 0.28, 0.5, 0.72 } do
				local made = ribbon(
					live,
					at,
					(i - 2) * 0.35,
					0,
					0.18,
					1.3,
					curtain,
					Fx.keys({ 0, 0.42, 0.5, 0.6, 1, 1 })
				)
				made.trail.Brightness = 1.1
			end
		elseif kind == "currents" then
			-- (from the skin out: they began a little off it, a seam you could see)
			for _, side in { math.pi * 0.5, -math.pi * 0.5 } do
				ribbon(live, 0.22, side, 0, 0.09, 0.9, pair, nil, "radial")
				ribbon(live, 0.5, side * 0.8, 0, 0.07, 0.8, pair, nil, "radial")
			end
		elseif kind == "foam" then
			local white = ColorSequence.new(Color3.fromRGB(235, 252, 255), c)
			for _, side in { math.pi * 0.55, -math.pi * 0.55 } do
				ribbon(live, 0.3, side, 0, 0.05, 0.5, white, nil, "radial")
			end
			ribbon(live, TAIL, 0, 0, 0.12, 0.45, white, nil, "centered")
		elseif kind == "comet" then
			-- (its tail is the point: it keeps more of it on a dash; centred on the tail
			-- fin and about its height: from the back's top up 0.34 of a length it stood
			-- over the fish "right in your face", 2026-10-18)
			local tail = ribbon(
				live,
				TAIL,
				0,
				0,
				0.22,
				1.1,
				ColorSequence.new(Color3.new(1, 1, 1), c),
				Fx.keys({ 0, 0.05, 0.4, 0.4, 1, 1 }),
				"centered"
			)
			tail.keep = 0.7
		elseif kind == "rainbow" then
			-- (from the tail fin's middle: from the back's top it rode over the fish
			-- and its first edge showed in the water, Prism 2026-10-18)
			ribbon(
				live,
				TAIL,
				0,
				0,
				0.18,
				0.9,
				Fx.rainbow(0.6),
				Fx.keys({ 0, 0.15, 0.6, 0.45, 1, 1 }),
				"centered"
			)
		elseif kind == "halo" or kind == "crown" then
			local crown = kind == "crown"
			local points: { Attachment } = {}
			local count = if crown then 10 else 14
			for i = 1, count do
				points[i] = Fx.attachment(core, "FxHalo")
			end
			local gold = ColorSequence.new(c)
			local band = if crown then L * 0.03 else L * 0.028
			for i = 1, count do
				Fx.beam(core, points[i], points[i % count + 1], band, band, gold)
			end
			local tips: { { tip: Attachment, base: number } } = {}
			if crown then
				-- Points on every other link
				for i = 1, count, 2 do
					local tip = Fx.attachment(core, "FxCrownTip")
					Fx.beam(core, points[i], tip, L * 0.032, L * 0.004, gold)
					table.insert(tips, { tip = tip, base = i })
				end
			end
			-- A crown sits on the head where its fish has a seat measured
			local plan = body:GetAttribute("MeshPlan")
			live.halo = {
				points = points,
				tips = tips,
				radius = if crown then 0.11 else 0.16,
				lift = if crown then 0.1 else 0.2,
				crown = crown,
				seat = if crown and typeof(plan) == "string" then SEATS[plan] else nil,
			}
		elseif kind == "rays" then
			local points: { Attachment } = {}
			local tips: { Attachment } = {}
			for i = 1, 6 do
				points[i] = Fx.attachment(core, "FxRay")
				tips[i] = Fx.attachment(core, "FxRayTip")
				Fx.beam(
					core,
					points[i],
					tips[i],
					L * 0.02,
					L * 0.16,
					ColorSequence.new(c),
					Fx.keys({ 0, 0.45, 1, 1 })
				)
			end
			live.rays = { points = points, tips = tips }
		elseif kind == "sunburst" then
			local center = Fx.attachment(core, "FxSun")
			local tips: { Attachment } = {}
			for i = 1, 10 do
				tips[i] = Fx.attachment(core, "FxSunTip")
				Fx.beam(
					core,
					center,
					tips[i],
					L * 0.03,
					L * 0.2,
					ColorSequence.new(c, c2),
					Fx.keys({ 0, 0.55, 1, 1 })
				)
			end
			live.sunburst = { center = center, tips = tips }
		elseif kind == "arcs" then
			local bolt = ColorSequence.new(Color3.new(1, 1, 1), c)
			for _ = 1, 3 do
				local points: { Attachment } = {}
				local beams: { Beam } = {}
				for i = 1, 5 do
					points[i] = Fx.attachment(core, "FxArc")
				end
				for i = 1, 4 do
					beams[i] = Fx.beam(core, points[i], points[i + 1], L * 0.022, L * 0.022, bolt)
				end
				table.insert(live.arcs, { points = points, beams = beams })
			end
		elseif kind == "rim" or kind == "rainbowRim" then
			-- A rainbow outline alone was lost on Prismatic's rainbow body (playtest
			-- 2026-10-17): it draws solid over a faint fill of the opposite hue, a
			-- holographic wash that drifts round the wheel (with Fx "shimmer")
			local rainbow = kind == "rainbowRim"
			local rim = Instance.new("Highlight")
			rim.Name = "FxRim"
			rim.Adornee = holder
			rim.FillTransparency = if rainbow then 0.84 else 1
			rim.FillColor = c
			rim.OutlineColor = c
			rim.OutlineTransparency = if rainbow then 0 else 0.25
			rim.DepthMode = Enum.HighlightDepthMode.Occluded
			rim:SetAttribute("ShadeEffect", true)
			rim.Parent = core
			live.rim = rim
			live.rainbowRim = rainbow
		elseif kind == "sheen" then
			-- A band of light across the flank facing the camera, upper flank to
			-- lower (three points, two beams, brightest in the middle), switched on
			-- only while it sweeps
			local points: { Attachment } = {}
			for i = 1, 3 do
				points[i] = Fx.attachment(core, "FxSheen")
			end
			local band = ColorSequence.new(c2)
			local beams = {
				Fx.beam(
					core,
					points[1],
					points[2],
					L * 0.03,
					L * 0.08,
					band,
					Fx.keys({ 0, 1, 0.5, 0.35, 1, 0.15 })
				),
				Fx.beam(
					core,
					points[2],
					points[3],
					L * 0.08,
					L * 0.03,
					band,
					Fx.keys({ 0, 0.15, 0.5, 0.35, 1, 1 })
				),
			}
			for _, beam in beams do
				beam.Segments = 4
				beam.Enabled = false
			end
			-- The light riding it, close over the upper flank: on a polished skin
			-- (Golden's is gloss) it lays a real highlight that runs along the body
			local lamp = Fx.attachment(core, "FxSheenLight")
			local light = Instance.new("PointLight")
			light.Name = "FxSheenLight"
			light.Color = c2
			light.Brightness = 0
			light.Enabled = false
			light.Range = math.clamp(L * 0.9, 2, 30)
			light.Shadows = false
			light:SetAttribute("ShadeEffect", true)
			light.Parent = lamp
			-- Sparks thrown off the band as it passes (its rate rides the sweep), and
			-- fine glitter twinkling all over the body from a seat that hops about
			local sparks = Fx.emitter(points[2], "glitter", L, c2, c, 0)
			local dust = Fx.attachment(core, "FxGlitter")
			table.insert(live.sheds, { emitter = sparks, life = sparks.Lifetime, cap = math.huge })
			local glitter = Fx.emitter(dust, "glitter", L, c, c2, 1.4)
			table.insert(live.sheds, { emitter = glitter, life = glitter.Lifetime, cap = math.huge })
			live.sweep = {
				points = points,
				beams = beams,
				lamp = lamp,
				light = light,
				sparks = sparks,
				dust = dust,
				on = false,
			}
		else
			local e = Fx.emitter(core, kind :: Fx.Preset, L, c, c2)
			-- (held to the body, it never trails toward the camera)
			if not e.LockedToPart then
				table.insert(live.sheds, { emitter = e, life = e.Lifetime, cap = math.huge })
			end
		end
	end
	return live
end

-- Moves the effects with the body (`t` any clock). Far from the camera only the
-- particles run.
function SkinFx.step(live: Live, body: Model, t: number)
	local drawn = body:GetAttribute("Applied")
	local L = if typeof(drawn) == "number" then drawn else live.length
	local camera = Workspace.CurrentCamera
	local frame = frameOf(body)
	if camera and (camera.CFrame.Position - frame.Position).Magnitude > 260 then
		live.lastPos = nil
		return
	end
	-- Its speed, from its moves between steps (eased): past top speed the trails
	-- shorten so a dash draws about the streak a cruise does, and the swirls fade
	-- a little
	local top = math.max(Size.topSpeed(live.length), 1)
	local last = live.lastPos
	local dt = t - live.lastT
	if last and dt > 1e-3 and dt < 0.5 then
		local speed = math.min((frame.Position - last).Magnitude / dt, top * 4)
		live.speed += (speed - live.speed) * math.min(dt * 8, 1)
	end
	live.lastPos = frame.Position
	live.lastT = t
	local over = top / math.max(live.speed, 1e-3)
	local orbitScale = math.clamp(over, 0.15, 1)
	local fade = math.floor(math.clamp((live.speed / top - 1.1) / 0.6, 0, 1) * 6 + 0.5) / 10
	-- Your own fish: nothing it sheds lives past `BEHIND` of the time the following
	-- camera takes to reach it, and its ribbons fade back while the camera looks
	-- along them from behind (in tenths, so the sequences are made once)
	local me = Players.LocalPlayer
	local mine = camera ~= nil and me ~= nil and me.Character ~= nil and body.Parent == me.Character
	local most = math.huge
	local view = 0
	if mine and camera then
		local away = (camera.CFrame.Position - frame.Position).Magnitude
		most = math.max(away / math.max(live.speed, 1) * BEHIND, SHORTEST)
		local along = camera.CFrame.LookVector:Dot(frame.LookVector)
		view = math.floor(math.clamp((along - 0.55) / 0.37, 0, 1) * VIEW_FADE * 10 + 0.5)
	end
	local orbitFadeNow = math.max(fade, view / 10)
	local function orbit(o: Orbiter)
		local life = math.min(o.lifetime * orbitScale, most)
		if math.abs(o.life - life) > 0.01 then
			o.life = life
			o.trail.Lifetime = life
		end
		if o.fade ~= orbitFadeNow then
			o.fade = orbitFadeNow
			o.trail.Transparency = orbitFade(orbitFadeNow)
		end
	end
	for _, shed in live.sheds do
		-- (in steps of a tenth of a second, so it isn't set every frame)
		local cap = if most < 10 then math.ceil(most * 10) / 10 else math.huge
		if cap ~= shed.cap then
			shed.cap = cap
			shed.emitter.Lifetime =
				NumberRange.new(math.min(shed.life.Min, cap), math.min(shed.life.Max, cap))
		end
	end
	-- Swirls: head to tail in 2.4 s, once round every 1.1 s
	for _, o in live.swirls do
		orbit(o)
		local f = (t / 2.4 + o.phase) % 1
		if f < o.last then
			o.trail:Clear()
		end
		o.last = f
		local at = 0.06 + f * 0.86
		local angle = t * (2 * math.pi / 1.1) + o.phase * 2 * math.pi
		local p, dir = surface(live, body, frame, at, angle, 0.06, L)
		o.a0.WorldPosition = p
		o.a1.WorldPosition = p + dir * L * 0.06
	end
	-- The ring: twice round the middle a second, tilted a little
	for _, o in live.ring do
		orbit(o)
		local angle = t * 2 * math.pi * 0.9 + o.phase * 2 * math.pi
		local p, dir = surface(live, body, frame, 0.45 + 0.05 * math.sin(angle), angle, 0.22, L)
		o.a0.WorldPosition = p
		o.a1.WorldPosition = p + dir * L * 0.08
	end
	local up = frame.UpVector
	for _, r in live.ribbons do
		local life = math.min(r.lifetime * math.clamp(over * 1.25, r.keep, 1), most)
		if math.abs(r.life - life) > 0.01 then
			r.life = life
			r.trail.Lifetime = life
		end
		if r.shown ~= view then
			r.shown = view
			local faded: NumberSequence? = r.faded[view]
			if not faded then
				local made = if view == 0 then r.fade else fadedBy(r.fade, view / 10)
				r.faded[view] = made
				faded = made
			end
			r.trail.Transparency = faded :: NumberSequence
		end
		local swing = math.sin(t * 2.2 + r.phase) * r.sway * L
		local sideways = frame.RightVector * swing + up * math.cos(t * 1.7 + r.phase) * r.sway * 0.6 * L
		if r.seat == "centered" then
			-- Across the body's middle line (the tail fin's), half each side
			local p = spineAt(live, frame, r.at, L)
			local half = up * r.width * L * 0.5
			r.a0.WorldPosition = p - half + sideways * 0.5
			r.a1.WorldPosition = p + half + sideways * 0.5
		else
			local p, dir = surface(live, body, frame, r.at, r.side, r.out, L)
			local across = if r.seat == "radial" then dir else up
			r.a0.WorldPosition = p + sideways
			r.a1.WorldPosition = p + sideways + across * r.width * L
		end
	end
	-- The shine (Golden, Silver): a band of light runs head to tail on the flank facing the
	-- camera, a light riding just off the upper flank (the gloss catches it), sparks
	-- thrown off it; then a rest. The glitter's seat hops about the body every step.
	local sweep = live.sweep
	if sweep then
		sweep.dust.WorldPosition =
			surface(live, body, frame, 0.08 + math.random() * 0.82, math.random() * 2 * math.pi, 0.006, L)
		local k = (t % SHEEN_PERIOD) / SHEEN_SWEEP
		if k < 1 then
			local f = 0.05 + k * 0.9
			local glow = math.sin(math.pi * k) ^ 0.6
			local center, forward = spineAt(live, frame, f, L)
			local right = forward:Cross(up)
			right = if right.Magnitude > 1e-4 then right.Unit else frame.RightVector
			local s = if camera and (camera.CFrame.Position - center):Dot(right) < 0 then -1 else 1
			sweep.points[1].WorldPosition = surface(live, body, frame, f, s * math.pi * 0.18, 0.012, L)
			sweep.points[2].WorldPosition = surface(live, body, frame, f, s * math.pi * 0.5, 0.02, L)
			sweep.points[3].WorldPosition = surface(live, body, frame, f, s * math.pi * 0.82, 0.012, L)
			sweep.lamp.WorldPosition = surface(live, body, frame, f, s * math.pi * 0.3, 0.35, L)
			sweep.light.Enabled = true
			sweep.light.Brightness = 7 * glow
			for _, beam in sweep.beams do
				beam.Enabled = true
				beam.Brightness = 3.2 * glow
			end
			sweep.sparks.Rate = 26 * glow
			sweep.on = true
		elseif sweep.on then
			sweep.on = false
			sweep.light.Enabled = false
			sweep.light.Brightness = 0
			for _, beam in sweep.beams do
				beam.Enabled = false
			end
			sweep.sparks.Rate = 0
		end
	end
	-- Curtains: from the back up and a little back, waving (each end's curve runs
	-- along the body, so the sheet bends like cloth)
	for _, curtain in live.curtains do
		local foot = surface(live, body, frame, curtain.at, 0, 0, L)
		local _, forward = spineAt(live, frame, curtain.at, L)
		local ahead = square(forward, up, frame)
		local rise = L * (0.48 + 0.07 * math.sin(t * 0.7 + curtain.phase))
		local crest = foot + up * rise - ahead * L * 0.1
		curtain.a0.WorldCFrame = CFrame.fromMatrix(foot, ahead, up)
		curtain.a1.WorldCFrame = CFrame.fromMatrix(crest, ahead, up)
		curtain.beam.CurveSize0 = math.sin(t * 1.1 + curtain.phase) * L * 0.16
		curtain.beam.CurveSize1 = math.sin(t * 1.1 + curtain.phase + 1.5) * L * 0.16
	end
	local halo = live.halo
	if halo then
		local seat = halo.seat
		local middle: Vector3
		local forward: Vector3
		if seat then
			-- Seated on the head's top, riding the bones (it turns with the head)
			local p, along = boneAt(live, frame, seat.z, L)
			middle = p + up * (seat.y * L - frame:PointToObjectSpace(p).Y)
			forward = along
		else
			local center, along = spineAt(live, frame, 0.18, L)
			local _, rh = radiiAt(body, 0.18, L)
			middle = center + up * (rh + halo.lift * L)
			forward = along
		end
		local ahead, right = square(forward, up, frame)
		-- A seat tips the ring back by its tilt: the front rises, the top leans back
		local tilt = if seat then seat.tilt else 0
		local axis = up * math.cos(tilt) - ahead * math.sin(tilt)
		ahead = ahead * math.cos(tilt) + up * math.sin(tilt)
		local radius = (if seat then seat.radius else halo.radius) * L
		local count = #halo.points
		-- A halo turns; a seated crown holds still with a point at the back, none
		-- at the front (where the Angler's lure stalk rises)
		local spin = if seat then 1.5 * math.pi else t * 0.6
		for i, a in halo.points do
			local angle = spin + (i - 1) / count * 2 * math.pi
			a.WorldPosition = middle + (right * math.cos(angle) + ahead * math.sin(angle)) * radius
		end
		local height = if seat then L * 0.065 else L * 0.07
		for _, entry in halo.tips do
			entry.tip.WorldPosition = halo.points[entry.base].WorldPosition + axis * height
		end
	end
	local rays = live.rays
	if rays then
		local center = spineAt(live, frame, 0.2, L)
		local _, rh = radiiAt(body, 0.2, L)
		local base = center + up * rh * 0.9
		for i, a in rays.points do
			local angle = t * 0.25 + (i - 1) / #rays.points * 2 * math.pi
			local lean = (frame.RightVector * math.cos(angle) + frame.LookVector * math.sin(angle)) * 0.45
			a.WorldPosition = base
			rays.tips[i].WorldPosition = base + (up + lean).Unit * L * (0.55 + 0.1 * math.sin(t * 1.3 + i))
		end
	end
	local sun = live.sunburst
	if sun then
		local center, forward = spineAt(live, frame, 0.45, L)
		local _, right = square(forward, up, frame)
		sun.center.WorldPosition = center
		for i, tip in sun.tips do
			local angle = t * 0.35 + (i - 1) / #sun.tips * 2 * math.pi
			tip.WorldPosition = center
				+ (up * math.cos(angle) + right * math.sin(angle))
					* L
					* (0.62 + 0.08 * math.sin(t * 2 + i))
		end
	end
	if #live.arcs > 0 and t >= live.nextArc then
		-- Lightning: each arc jumps somewhere new every ~0.09 s, and shows in bursts
		live.nextArc = t + 0.06 + math.random() * 0.06
		for _, arc in live.arcs do
			local on = math.random() < 0.6
			for _, beam in arc.beams do
				beam.Enabled = on
			end
			if on then
				local f1 = 0.1 + math.random() * 0.8
				local f2 = math.clamp(f1 + (math.random() - 0.5) * 0.5, 0.05, 0.95)
				local s1 = math.random() * 2 * math.pi
				local s2 = s1 + (math.random() - 0.5) * 2.2
				local n = #arc.points
				for i, a in arc.points do
					local k = (i - 1) / (n - 1)
					local jitter = if i == 1 or i == n then 0.01 else 0.04 + math.random() * 0.1
					local p = surface(live, body, frame, f1 + (f2 - f1) * k, s1 + (s2 - s1) * k, jitter, L)
					a.WorldPosition = p
				end
			end
		end
	end
	local rim = live.rim
	if rim and live.rainbowRim then
		local hue = (t * 0.15) % 1
		rim.OutlineColor = Color3.fromHSV(hue, 0.85, 1)
		rim.FillColor = Color3.fromHSV((hue + 0.5) % 1, 0.45, 1)
	end
end

return SkinFx
