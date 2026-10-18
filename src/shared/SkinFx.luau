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
--   rainbow   a rainbow ribbon off the tail (Prismatic)
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
-- None of this draws in a ViewportFrame (Roblox draws no particles, trails or beams
-- there), so the menus' fish show only the skin.
local Workspace = game:GetService("Workspace")

local Fx = require(script.Parent.Fx)
local ShadesConfig = require(script.Parent.Config.Shades)
local Size = require(script.Parent.Size)

local SkinFx = {}

type Ribbon = {
	a0: Attachment,
	a1: Attachment,
	trail: Trail,
	at: number, -- how far along the body (0 head, 1 tail)
	side: number, -- angle round the body (0 the back, π/2 the right flank)
	out: number, -- how far out from the body's surface, in lengths
	width: number, -- in lengths
	radial: boolean, -- the ribbon's width points out from the body (else up)
	phase: number,
	sway: number,
	lifetime: number, -- its trail's at a cruise
	keep: number, -- the least share of that kept on a dash
	scale: number, -- the share it has now
}

type Orbiter = {
	a0: Attachment,
	a1: Attachment,
	trail: Trail,
	phase: number,
	last: number,
	lifetime: number,
	scale: number,
	fade: number, -- how far it's faded out, past top speed
}

type Arc = { points: { Attachment }, beams: { Beam } }

-- A curtain of light standing over the back (Aurora)
type Curtain = { a0: Attachment, a1: Attachment, beam: Beam, at: number, phase: number }

-- Where a crown sits on a fish's head, in its unit box (nose at z -0.5, the box's
-- middle at 0, as Cosmetics' ANCHORS): `z` along the body, `y` the head's top there,
-- `radius` and `tilt` (radians, its top leaning back)
type Seat = { z: number, y: number, radius: number, tilt: number }

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
		seat: Seat?,
	}?,
	rays: { points: { Attachment }, tips: { Attachment } }?,
	sunburst: { center: Attachment, tips: { Attachment } }?,
	arcs: { Arc },
	nextArc: number,
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
local SEATS: { [string]: Seat } = {
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

local function ribbon(
	live: Live,
	at: number,
	side: number,
	out: number,
	width: number,
	lifetime: number,
	color: ColorSequence,
	fade: NumberSequence?,
	radial: boolean?
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
		radial = radial == true,
		phase = math.random() * 10,
		sway = 0.06,
		lifetime = lifetime,
		keep = 0.5,
		scale = 1,
	}
	table.insert(live.ribbons, made)
	return made
end

local function orbiter(live: Live, list: { Orbiter }, color: ColorSequence, lifetime: number, phase: number)
	local a0 = Fx.attachment(live.core, "FxOrbit0")
	local a1 = Fx.attachment(live.core, "FxOrbit1")
	local trail = Fx.ribbon(live.core, a0, a1, lifetime, color, orbitFade(0))
	table.insert(
		list,
		{ a0 = a0, a1 = a1, trail = trail, phase = phase, last = 0, lifetime = lifetime, scale = 1, fade = 0 }
	)
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
			-- ribbons alone were thin streaks (playtest 2026-10-17)
			for i, at in { 0.3, 0.5, 0.7 } do
				local a0 = Fx.attachment(core, "FxCurtain0")
				local a1 = Fx.attachment(core, "FxCurtain1")
				local beam = Fx.beam(
					core,
					a0,
					a1,
					L * 0.26,
					L * 0.38,
					curtain,
					Fx.keys({ 0, 0.4, 0.2, 0.28, 0.65, 0.5, 1, 1 })
				)
				beam.Segments = 12
				beam.Brightness = 1.6
				table.insert(live.curtains, { a0 = a0, a1 = a1, beam = beam, at = at, phase = i * 1.9 })
			end
			-- and ribbons streaming off them as it swims
			for i, at in { 0.28, 0.5, 0.72 } do
				local made = ribbon(
					live,
					at,
					(i - 2) * 0.35,
					0.02,
					0.3,
					1.3,
					curtain,
					Fx.keys({ 0, 0.3, 0.5, 0.5, 1, 1 })
				)
				made.trail.Brightness = 1.4
			end
		elseif kind == "currents" then
			for _, side in { math.pi * 0.5, -math.pi * 0.5 } do
				ribbon(live, 0.22, side, 0.04, 0.09, 0.9, pair, nil, true)
				ribbon(live, 0.5, side * 0.8, 0.05, 0.07, 0.8, pair, nil, true)
			end
		elseif kind == "foam" then
			local white = ColorSequence.new(Color3.fromRGB(235, 252, 255), c)
			for _, side in { math.pi * 0.55, -math.pi * 0.55 } do
				ribbon(live, 0.3, side, 0.03, 0.05, 0.5, white, nil, true)
			end
			ribbon(live, 0.98, 0, 0.01, 0.12, 0.45, white)
		elseif kind == "comet" then
			-- (its tail is the point: it keeps more of it on a dash)
			local tail = ribbon(
				live,
				1.0,
				0,
				0,
				0.34,
				1.1,
				ColorSequence.new(Color3.new(1, 1, 1), c),
				Fx.keys({ 0, 0.05, 0.4, 0.4, 1, 1 })
			)
			tail.keep = 0.7
		elseif kind == "rainbow" then
			ribbon(live, 1.0, 0, 0, 0.26, 0.9, Fx.rainbow(0.6), Fx.keys({ 0, 0.15, 0.6, 0.45, 1, 1 }))
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
		else
			Fx.emitter(core, kind :: Fx.Preset, L, c, c2)
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
	local function orbit(o: Orbiter)
		if math.abs(o.scale - orbitScale) > 0.02 then
			o.scale = orbitScale
			o.trail.Lifetime = o.lifetime * orbitScale
		end
		if o.fade ~= fade then
			o.fade = fade
			o.trail.Transparency = orbitFade(fade)
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
		local scale = math.clamp(over * 1.25, r.keep, 1)
		if math.abs(r.scale - scale) > 0.02 then
			r.scale = scale
			r.trail.Lifetime = r.lifetime * scale
		end
		local swing = math.sin(t * 2.2 + r.phase) * r.sway * L
		local p, dir = surface(live, body, frame, r.at, r.side, r.out, L)
		local across = if r.radial then dir else up
		local sideways = frame.RightVector * swing + up * math.cos(t * 1.7 + r.phase) * r.sway * 0.6 * L
		r.a0.WorldPosition = p + sideways
		r.a1.WorldPosition = p + sideways + across * r.width * L
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
