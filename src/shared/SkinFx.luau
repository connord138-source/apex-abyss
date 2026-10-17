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
--   aurora    long curtains streaming off the back (Aurora)
--   currents  dark current ribbons along both flanks (Abyssal Current)
--   foam      white water ribbons off the pectorals (Riptide)
--   comet     a wide glowing tail (Comet)
--   rainbow   a rainbow ribbon off the tail (Prismatic)
--   halo      a ring of light over the head, turning (Divine, Lantern King's crown)
--   rays      soft light rays fanning up over the head (Divine)
--   sunburst  rays turning round the body (Sunburst)
--   arcs      lightning crawling over the body in bursts (Thunder)
--   rim       an outline in the effect colour; rainbowRim cycles through the hues
--   anything else is a Shared/Fx particle preset emitted from the body (mist,
--   stardust, nebula, vortex, gold, embers, drips, crystal, ...)
--
-- Ribbons sway a little on their own, so they draw even while the fish holds still.
-- None of this draws in a ViewportFrame (Roblox draws no particles, trails or beams
-- there), so the menus' fish show only the skin.
local Workspace = game:GetService("Workspace")

local Fx = require(script.Parent.Fx)
local ShadesConfig = require(script.Parent.Config.Shades)

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
}

type Orbiter = {
	a0: Attachment,
	a1: Attachment,
	trail: Trail,
	phase: number,
	last: number,
}

type Arc = { points: { Attachment }, beams: { Beam } }

export type Live = {
	core: BasePart,
	length: number,
	bones: { Bone }, -- head to tail
	swirls: { Orbiter },
	ring: { Orbiter },
	ribbons: { Ribbon },
	halo: { points: { Attachment }, radius: number, lift: number, crown: boolean }?,
	rays: { points: { Attachment }, tips: { Attachment } }?,
	sunburst: { center: Attachment, tips: { Attachment } }?,
	arcs: { Arc },
	nextArc: number,
	rim: Highlight?,
	rainbowRim: boolean,
	color: Color3,
	color2: Color3,
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

-- A point on the body's middle line `f` of the way from head to tail, and the way
-- forward there
local function spineAt(live: Live, body: Model, f: number, L: number): (Vector3, Vector3)
	local bones = live.bones
	local pivot = body:GetPivot()
	if #bones < 2 then
		return pivot.Position + pivot.LookVector * (0.5 - f) * L, pivot.LookVector
	end
	-- The bones run over the middle of the body: stretch them to the ends
	local span = (#bones - 1) * math.clamp((f - 0.08) / 0.84, 0, 1)
	local i = math.clamp(math.floor(span) + 1, 1, #bones - 1)
	local a = bones[i].TransformedWorldCFrame.Position
	local b = bones[i + 1].TransformedWorldCFrame.Position
	local forward = a - b
	forward = if forward.Magnitude > 1e-4 then forward.Unit else pivot.LookVector
	local base = a:Lerp(b, span - (i - 1))
	-- Past the end bones, along the line they make
	if f < 0.08 then
		base += forward * (0.08 - f) * L
	elseif f > 0.92 then
		base -= forward * (f - 0.92) * L
	end
	return base, forward
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
	f: number,
	angle: number,
	out: number,
	L: number
): (Vector3, Vector3)
	local center, forward = spineAt(live, body, f, L)
	local up0 = body:GetPivot().UpVector
	local right = forward:Cross(up0)
	right = if right.Magnitude > 1e-4 then right.Unit else body:GetPivot().RightVector
	local up = right:Cross(forward).Unit
	local rw, rh = radiiAt(body, f, L)
	local dir = up * math.cos(angle) + right * math.sin(angle)
	local reach = up * math.cos(angle) * rh + right * math.sin(angle) * rw
	return center + reach + dir * out * L, dir
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
)
	local a0 = Fx.attachment(live.core, "FxRibbon0")
	local a1 = Fx.attachment(live.core, "FxRibbon1")
	local trail = Fx.ribbon(live.core, a0, a1, lifetime, color, fade)
	table.insert(live.ribbons, {
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
	})
end

local function orbiter(live: Live, list: { Orbiter }, color: ColorSequence, lifetime: number, phase: number)
	local a0 = Fx.attachment(live.core, "FxOrbit0")
	local a1 = Fx.attachment(live.core, "FxOrbit1")
	local trail = Fx.ribbon(live.core, a0, a1, lifetime, color)
	table.insert(list, { a0 = a0, a1 = a1, trail = trail, phase = phase, last = 0 })
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
		halo = nil,
		rays = nil,
		sunburst = nil,
		arcs = {},
		nextArc = 0,
		rim = nil,
		rainbowRim = false,
		color = c,
		color2 = c2,
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
			for i, at in { 0.28, 0.5, 0.72 } do
				ribbon(
					live,
					at,
					(i - 2) * 0.35,
					0.02,
					0.24,
					1.3,
					curtain,
					Fx.keys({ 0, 0.35, 0.5, 0.55, 1, 1 })
				)
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
			ribbon(
				live,
				1.0,
				0,
				0,
				0.34,
				1.1,
				ColorSequence.new(Color3.new(1, 1, 1), c),
				Fx.keys({ 0, 0.05, 0.4, 0.4, 1, 1 })
			)
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
			for i = 1, count do
				Fx.beam(core, points[i], points[i % count + 1], L * 0.028, L * 0.028, gold)
			end
			if crown then
				-- Points on every other link
				for i = 1, count, 2 do
					local tip = Fx.attachment(core, "FxCrownTip")
					tip:SetAttribute("Base", i)
					Fx.beam(core, points[i], tip, L * 0.03, L * 0.004, gold)
				end
			end
			live.halo = {
				points = points,
				radius = if crown then 0.11 else 0.16,
				lift = if crown then 0.1 else 0.2,
				crown = crown,
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
			local rim = Instance.new("Highlight")
			rim.Name = "FxRim"
			rim.Adornee = holder
			rim.FillTransparency = 1
			rim.OutlineColor = c
			rim.OutlineTransparency = 0.25
			rim.DepthMode = Enum.HighlightDepthMode.Occluded
			rim:SetAttribute("ShadeEffect", true)
			rim.Parent = core
			live.rim = rim
			live.rainbowRim = kind == "rainbowRim"
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
	local pivot = body:GetPivot()
	if camera and (camera.CFrame.Position - pivot.Position).Magnitude > 260 then
		return
	end
	-- Swirls: head to tail in 2.4 s, once round every 1.1 s
	for _, o in live.swirls do
		local f = (t / 2.4 + o.phase) % 1
		if f < o.last then
			o.trail:Clear()
		end
		o.last = f
		local at = 0.06 + f * 0.86
		local angle = t * (2 * math.pi / 1.1) + o.phase * 2 * math.pi
		local p, dir = surface(live, body, at, angle, 0.06, L)
		o.a0.WorldPosition = p
		o.a1.WorldPosition = p + dir * L * 0.06
	end
	-- The ring: twice round the middle a second, tilted a little
	for _, o in live.ring do
		local angle = t * 2 * math.pi * 0.9 + o.phase * 2 * math.pi
		local p, dir = surface(live, body, 0.45 + 0.05 * math.sin(angle), angle, 0.22, L)
		o.a0.WorldPosition = p
		o.a1.WorldPosition = p + dir * L * 0.08
	end
	for _, r in live.ribbons do
		local swing = math.sin(t * 2.2 + r.phase) * r.sway * L
		local p, dir = surface(live, body, r.at, r.side, r.out, L)
		local up = pivot.UpVector
		local across = if r.radial then dir else up
		local sideways = pivot.RightVector * swing + up * math.cos(t * 1.7 + r.phase) * r.sway * 0.6 * L
		r.a0.WorldPosition = p + sideways
		r.a1.WorldPosition = p + sideways + across * r.width * L
	end
	local halo = live.halo
	if halo then
		local center, forward = spineAt(live, body, 0.18, L)
		local _, rh = radiiAt(body, 0.18, L)
		local up = pivot.UpVector
		local right = forward:Cross(up)
		right = if right.Magnitude > 1e-4 then right.Unit else pivot.RightVector
		local middle = center + up * (rh + halo.lift * L)
		local count = #halo.points
		local spin = t * 0.6
		for i, a in halo.points do
			local angle = spin + (i - 1) / count * 2 * math.pi
			a.WorldPosition = middle + (right * math.cos(angle) + forward * math.sin(angle)) * halo.radius * L
		end
		if halo.crown then
			for _, tip in live.core:GetChildren() do
				if tip.Name == "FxCrownTip" and tip:IsA("Attachment") then
					local base = tip:GetAttribute("Base")
					local from = halo.points[if typeof(base) == "number" then base else 1]
					tip.WorldPosition = from.WorldPosition + up * L * 0.07
				end
			end
		end
	end
	local rays = live.rays
	if rays then
		local center = spineAt(live, body, 0.2, L)
		local _, rh = radiiAt(body, 0.2, L)
		local up = pivot.UpVector
		local base = center + up * rh * 0.9
		for i, a in rays.points do
			local angle = t * 0.25 + (i - 1) / #rays.points * 2 * math.pi
			local lean = (pivot.RightVector * math.cos(angle) + pivot.LookVector * math.sin(angle)) * 0.45
			a.WorldPosition = base
			rays.tips[i].WorldPosition = base + (up + lean).Unit * L * (0.55 + 0.1 * math.sin(t * 1.3 + i))
		end
	end
	local sun = live.sunburst
	if sun then
		local center, forward = spineAt(live, body, 0.45, L)
		local up = pivot.UpVector
		local right = forward:Cross(up)
		right = if right.Magnitude > 1e-4 then right.Unit else pivot.RightVector
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
					local p = surface(live, body, f1 + (f2 - f1) * k, s1 + (s2 - s1) * k, jitter, L)
					a.WorldPosition = p
				end
			end
		end
	end
	local rim = live.rim
	if rim and live.rainbowRim then
		rim.OutlineColor = Color3.fromHSV((t * 0.15) % 1, 0.55, 1)
	end
end

return SkinFx
