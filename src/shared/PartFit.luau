--!strict
-- Where the rolled parts hang on each fish, and how each part's model is fitted to
-- it (Shared/Cosmetics hangs them). Plain data and arithmetic, so the cloud preview
-- (tools/preview/run_parts.sh) draws exactly what the game does.
--
-- Fitted to the fish, not stuck on (owner, 2026-10-28: "veil tail doesnt make sense
-- on the shark with that look. It just looks slapped on. The parts need to shape to
-- the fish and change their appearance to fit. Not just mesh slap a part on"): each
-- model has a place, a size and a stretch of its own on every body plan, measured on
-- that fish's model (a horn grows from the snout's tip on a shark and from the
-- forehead on the round fish, a sail's foot sinks into the back, a veil trails off a
-- forked tail as a long narrow streamer and off an eel's tail as a ribbon), and it
-- takes the fish's colours (`tint`, below).
local PartFit = {}

export type Look = { back: Color3, belly: Color3, fin: Color3 }

-- Per body plan: where the head sits (its length as a fraction of the body's, from
-- the nose), its height, the back's height over the middle, the tail stalk, and
-- `partScale`: the part-built pieces (Cosmetics, drawn while a part's model isn't
-- imported) are made for the round graybox body (Body1 0.39 of the length tall), so
-- on a slender fish they're drawn smaller, as much as its body is thinner. The
-- heights were measured from the rigged FBX (the body's top at Body1, the snout's
-- middle) and set so a sail stands a third deep in the back: on the Moray Eel a
-- graybox-sized sail touched the back only at its lowest point and read as floating
-- a body height above it (playtest 2026-10-12), and the Hammerhead's paddle lay on
-- top of the snout (the head anchor sat 0.07 of the length over the shark's snout)
export type AnchorTune = {
	head: number?,
	headY: number?,
	bodyY: number?,
	stalkZ: number?,
	partScale: number?,
}
PartFit.ANCHORS = {
	Nibbler = {},
	Cuda = { head = 0.3, headY = -0.039, bodyY = -0.023, partScale = 0.65 },
	Puffer = { head = 0.38 },
	Eel = { head = 0.16, headY = -0.037, bodyY = -0.043, stalkZ = 0.42, partScale = 0.55 },
	Shark = { head = 0.3, headY = -0.05, bodyY = -0.032, partScale = 0.8 },
	Angler = { head = 0.46, headY = 0.03, bodyY = -0.026 },
} :: { [string]: AnchorTune }

-- The anchors of a mesh body in its unit box (nose at z -0.5, tail at +0.5), from its
-- plan and its width and height over its length, and the plan's part scale
function PartFit.anchors(plan: string?, w: number, h: number): ({ [string]: CFrame }, number)
	local tune: AnchorTune = PartFit.ANCHORS[plan or ""] or ({} :: AnchorTune)
	local head = tune.head or 0.3
	local headY = tune.headY or math.clamp((h * 0.4 - 0.15) * 0.5, -0.08, 0.08)
	local bodyY = tune.bodyY or math.clamp(h / 2 - 0.195, -0.1, 0.12)
	return {
		Head = CFrame.new(0, headY, -0.5 + head * 0.5),
		Body1 = CFrame.new(0, bodyY, -0.05),
		Body2 = CFrame.new(0, bodyY * 0.8, 0.15),
		Body3 = CFrame.new(0, bodyY * 0.6, 0.28),
		Stalk = CFrame.new(0, 0, tune.stalkZ or 0.38),
	},
		tune.partScale or 1
end

-- Each fish model's own colours, read off its colour map (`parts_preview.py --
-- colours`: the body's upward and downward faces, and the tail fin), for the parts
-- of a mesh fish wearing no shade. The species' `back`/`belly`/`fin` were picked for
-- the graybox bodies and drift from the textures: the Reef Shark's fin colour is a
-- blue-grey (84, 96, 110), its model's tail a neutral charcoal, and a veil tinted
-- toward the blue stayed blue on it
PartFit.LOOKS = {
	Nibbler = {
		back = Color3.fromRGB(209, 131, 77),
		belly = Color3.fromRGB(204, 160, 89),
		fin = Color3.fromRGB(214, 123, 46),
	},
	Cuda = {
		back = Color3.fromRGB(99, 120, 131),
		belly = Color3.fromRGB(190, 196, 201),
		fin = Color3.fromRGB(181, 166, 105),
	},
	Puffer = {
		back = Color3.fromRGB(134, 97, 72),
		belly = Color3.fromRGB(195, 181, 162),
		fin = Color3.fromRGB(172, 133, 103),
	},
	Eel = {
		back = Color3.fromRGB(78, 86, 10),
		belly = Color3.fromRGB(120, 122, 97),
		fin = Color3.fromRGB(80, 91, 16),
	},
	Shark = {
		back = Color3.fromRGB(104, 111, 117),
		belly = Color3.fromRGB(173, 180, 188),
		fin = Color3.fromRGB(61, 64, 65),
	},
	Angler = {
		back = Color3.fromRGB(51, 65, 99),
		belly = Color3.fromRGB(35, 36, 68),
		fin = Color3.fromRGB(63, 85, 119),
	},
} :: { [string]: Look }

-- How a part's model sits on one body plan's mesh: `at` is where its attach point
-- goes in the fish's unit box and how it's turned (the model's front, toward the
-- fish's nose, is -Z), `length` its longest side as a share of the fish's length and
-- `stretch` its own box scaled per axis (x across, y up, z along: a slimmer, lower or
-- longer cut on this fish). `parent` is the anchor whose bone it rides (Head, Body1,
-- Stalk: Cosmetics), so a veil swings with the tail and a horn turns with the head.
export type Shape = {
	parent: string,
	at: CFrame,
	length: number,
	stretch: Vector3?,
}

-- One part's model (parts_glb, ReplicatedStorage.PartModels.<PartId>). `box` and
-- `attach` are the model's own proportions and the point where it meets the fish, in
-- units of its longest side (tools/props/parts_prep.py's parts.json). `reversed`: the
-- model hangs turned half round from how parts_prep squared it up, and `attach` is
-- the point at its other end, turned with it (the saw: parts_prep read its sheet
-- with the tip on the left, so the bevelled root with the glowing line pointed away
-- from the fish and the square tip sat in its face; the approved board has it the
-- other way). On a graybox body it hangs on `parent` at `c0`, `length` long (the part
-- body's own parts, before any mesh). `tint` is the fish colour it takes and
-- `strength` how far (below).
export type Model = {
	box: Vector3,
	attach: Vector3,
	reversed: boolean?,
	parent: string,
	length: number,
	c0: CFrame,
	own: Color3,
	tint: "back" | "belly" | "fin",
	strength: number,
	transparency: number?,
	light: Color3?,
	plans: { [string]: Shape },
}

-- A Shape on one line: the anchor it rides, where its attach point goes (x, y, z in
-- the unit box), its pitch in degrees (+ tips its front up), its length, and its
-- stretch across, up and along (1 when left out)
local function on(
	parent: string,
	x: number,
	y: number,
	z: number,
	pitch: number,
	length: number,
	across: number?,
	up: number?,
	along: number?
): Shape
	return {
		parent = parent,
		at = CFrame.new(x, y, z) * CFrame.Angles(math.rad(pitch), 0, 0),
		length = length,
		stretch = Vector3.new(across or 1, up or 1, along or 1),
	}
end

-- Every number below was set by eye on tools/preview/run_parts.sh's contact sheet (the
-- six fish's FBX with the parts' GLBs, hung by this table): rerun it after changing one
PartFit.MODELS = {
	-- A segmented stalk from the top of the head arching forward to a crystal bulb
	-- dangling ahead of the mouth. Its foot sits on the head behind the eyes, its bulb
	-- just ahead of the mouth, sized to each head (the Nibbler's size swamped the Moray's
	-- head). On the Anglerfish it lies over the fish's own lure, from the same foot,
	-- the crystal round the yellow bulb: that lure grown into a crystal, not a second
	-- one. Its stalk takes the fish's back colour; the crystal keeps its glow
	AnglerLure = {
		box = Vector3.new(0.3424, 0.9738, 1),
		attach = Vector3.new(-0.0457, -0.0229, 0.5),
		parent = "Head",
		length = 0.42,
		c0 = CFrame.new(0, 0.13, 0.02),
		own = Color3.fromRGB(95, 121, 127),
		tint = "back",
		strength = 0.7,
		light = Color3.fromRGB(120, 235, 255),
		plans = {
			Nibbler = on("Head", 0, 0.21, -0.3, 0, 0.42),
			Cuda = on("Head", 0, 0.03, -0.3, 0, 0.27),
			Puffer = on("Head", 0, 0.255, -0.32, 0, 0.38),
			Eel = on("Head", 0, 0.045, -0.37, 0, 0.22),
			Shark = on("Head", 0, 0.035, -0.31, 0, 0.27),
			Angler = on("Head", 0, 0.2, -0.165, 0, 0.35),
		},
	},
	-- A spiral horn with a gold collar. On the round fish it grows from the forehead
	-- between the eyes, tipped up like a unicorn's; on the Cuda, Moray and Reef Shark
	-- from the snout's tip along the jaw's line, slimmer, a swordfish's bill; on the
	-- Anglerfish from the face under its lure's bulb. Its flared base is sunk into the
	-- head so only the gold collar meets the skin (it stood off the face like a plate)
	NarwhalHorn = {
		box = Vector3.new(0.3269, 0.3213, 1),
		attach = Vector3.new(0.0037, -0.0046, 0.5),
		parent = "Head",
		length = 0.56,
		c0 = CFrame.new(0, 0.03, -0.13) * CFrame.Angles(math.rad(8), 0, 0),
		own = Color3.fromRGB(177, 178, 178),
		tint = "belly",
		strength = 0.25,
		plans = {
			Nibbler = on("Head", 0, 0.1, -0.415, 10, 0.5),
			Cuda = on("Head", 0, -0.035, -0.42, 2, 0.42, 0.7, 0.7),
			Puffer = on("Head", 0, 0.06, -0.44, 8, 0.48),
			Eel = on("Head", 0, -0.025, -0.44, 4, 0.32, 0.65, 0.65),
			Shark = on("Head", 0, -0.045, -0.41, 2, 0.42, 0.75, 0.75),
			Angler = on("Head", 0, 0.115, -0.26, -8, 0.42, 0.8, 0.8),
		},
	},
	-- A toothed blade lying flat out of the mouth, its glowing line running from the
	-- bevelled root at the face to the square tip: slimmer on the slender fish (a
	-- sawshark's on the Reef Shark), dipping away under the Anglerfish's bulb. Only a
	-- little tinted, so its teeth stay bone white
	SawSnout = {
		box = Vector3.new(0.358, 0.1295, 1),
		attach = Vector3.new(-0.0073, -0.0013, 0.5),
		reversed = true,
		parent = "Head",
		length = 0.42,
		c0 = CFrame.new(0, -0.02, -0.12),
		own = Color3.fromRGB(105, 113, 125),
		tint = "back",
		strength = 0.3,
		plans = {
			Nibbler = on("Head", 0, -0.045, -0.44, 0, 0.5),
			Cuda = on("Head", 0, -0.045, -0.44, 0, 0.45, 0.7, 0.8),
			Puffer = on("Head", 0, -0.01, -0.44, 0, 0.45),
			Eel = on("Head", 0, -0.035, -0.45, 0, 0.36, 0.75, 0.75),
			Shark = on("Head", 0, -0.05, -0.44, -2, 0.42, 0.8, 0.8),
			Angler = on("Head", 0, 0.1, -0.27, -4, 0.42),
		},
	},
	-- A spined sail along the back: a long tapered foot, the spines leaning back, the
	-- front one steep and the tallest over its middle. Its foot is sunk into the back
	-- to the membrane and cut shorter (`along`) on the curved backs, so the bare foot
	-- never floats over the head or the tail stalk. It grows out of the fish's own
	-- dorsal fin and stands over it (taller on the Nibbler, whose dorsal is tall and
	-- thick), is wider on the Reef Shark and Cuda so their dorsal sits inside it, rises
	-- from the Moray's dorsal ridge, and is short on the Puffer's round back
	SailFin = {
		box = Vector3.new(0.1204, 0.4918, 1),
		attach = Vector3.new(0, -0.2459, 0.0002),
		parent = "Body1",
		length = 0.52,
		c0 = CFrame.new(0, 0.13, 0.08),
		own = Color3.fromRGB(47, 58, 78),
		tint = "fin",
		strength = 1,
		plans = {
			Nibbler = on("Body1", 0, 0.18, -0.13, 0, 0.55, 1, 1.3, 0.65),
			Cuda = on("Body1", 0, 0.035, -0.06, 0, 0.5, 1.3, 1.05, 0.75),
			Puffer = on("Body1", 0, 0.29, -0.12, 0, 0.46, 1, 1, 0.55),
			Eel = on("Body1", 0, 0.02, -0.12, 0, 0.45, 0.7, 0.85, 0.75),
			Shark = on("Body1", 0, -0.01, -0.12, 2, 0.55, 1.4, 1.15, 0.8),
			Angler = on("Body1", 0, 0.15, -0.02, 4, 0.42, 1, 1.1, 0.7),
		},
	},
	-- A flowing veil off the tail. Its stem is a hollow sleeve, which stood round the
	-- tail stalk with its opening showing; now it's sunk in the stalk, slim enough to
	-- stay inside. On the Reef Shark and Cuda (forked tails: the betta fan on the shark
	-- "just looks slapped on", owner 2026-10-28) it's a long narrow streamer rooted in
	-- the fork and sweeping up and back like the upper lobe; on the Moray a ribbon off
	-- the tail's tip; on the round fish a betta's fan as on the approved board, its
	-- flaps round the fish's own tail fin. A little see-through, like fin membrane
	VeilTail = {
		box = Vector3.new(0.3083, 0.8497, 1),
		attach = Vector3.new(0.07, 0.0079, -0.5),
		parent = "Stalk",
		length = 0.48,
		c0 = CFrame.new(0, 0, -0.02),
		own = Color3.fromRGB(52, 59, 128),
		tint = "fin",
		strength = 1,
		transparency = 0.2,
		plans = {
			Nibbler = on("Stalk", 0, -0.02, 0.25, 0, 0.6, 0.7, 1, 1),
			Cuda = on("Stalk", 0, 0.005, 0.24, -6, 0.45, 0.3, 0.4, 1.6),
			Puffer = on("Stalk", 0, 0.015, 0.31, 0, 0.5, 0.7, 0.95, 1),
			Eel = on("Stalk", 0, -0.004, 0.36, 0, 0.36, 0.35, 0.4, 1.6),
			Shark = on("Stalk", 0, 0, 0.27, -8, 0.5, 0.3, 0.38, 1.7),
			Angler = on("Stalk", 0, 0, 0.29, 0, 0.5, 0.7, 0.95, 1),
		},
	},
} :: { [string]: Model }

local function luminance(r: number, g: number, b: number): number
	return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

-- The colour a part's SurfaceAppearance is multiplied by on a fish of this look (its
-- own colours, or its shade's). A multiply can only darken, so the part is moved
-- toward the fish's colour at its own brightness (`own` is its colour map's average),
-- `strength` of the way, and only as far as a multiply can take it there: a blue veil
-- turns slate on a grey shark, olive on a green eel and navy on an angler, but can't
-- turn orange, so on the Nibbler it stays nearly the approved board's blue-violet
-- instead of going a muddy brown
function PartFit.tint(model: Model, look: Look): Color3
	local own, colour = model.own, look[model.tint]
	local k = luminance(own.R, own.G, own.B) / math.max(luminance(colour.R, colour.G, colour.B), 0.02)
	local want = { colour.R * k, colour.G * k, colour.B * k }
	local base = { own.R, own.G, own.B }
	local ratio, miss, away = {}, 0, 0
	for i = 1, 3 do
		ratio[i] = math.clamp(want[i] / math.max(base[i], 0.02), 0, 1)
		miss += (base[i] * ratio[i] - want[i]) ^ 2
		away += (base[i] - want[i]) ^ 2
	end
	-- How much of the way there the multiply gets (1: all of it)
	local reach = if away < 0.04 ^ 2 then 1 else 1 - math.sqrt(miss) / math.sqrt(away)
	local t = math.clamp((reach - 0.3) / 0.6, 0, 1)
	local share = model.strength * t * t * (3 - 2 * t)
	return Color3.new(1, 1, 1):Lerp(Color3.new(ratio[1], ratio[2], ratio[3]), share)
end

return PartFit
