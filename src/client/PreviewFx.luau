--!strict
-- A skin in a ViewportFrame looking the way it does in the water (owner, 2026-10-18:
-- "skins should also exactly match in the example screen. You can see how much better
-- this skin actually looks in game than in the preview"). A viewport draws no lights,
-- no bloom, no particles, trails or beams, so the Wardrobe, the Shade Dyer, the roll
-- reveal and the cards showed a skin flat and dark: no glow round its lines, none of
-- the coloured light it casts, none of its effects. Here they're stood in for:
--
--   * the glow map burns brighter (EmissiveStrength x `GLOW_BOOST`, the game's bloom
--     standing behind it) and pulses as Cosmetics pulses it in the water
--   * the light the skin casts (Config/Shades `glow`, `light`, else its effect
--     colour) tints the viewport's ambient light, and shows as a soft glow behind the
--     fish (a few stacked ellipses: no image needed) breathing with the pulse
--   * the skin's effects (Config/Shades `fx`, else its `aura` or `sparkle`) as 2D
--     sparkles over the fish in the effect colours: twinkling stars for glints,
--     crystal, gold, stardust and the like, soft motes drifting up (embers fall
--     upward, drips down), bubbles as rings, mist and ink as faint puffs; rainbow
--     colours for the rainbow effects (as Hatch & Snatch's viewports got matching 2D
--     glints)
--   * the shine (`sheen`: Golden, Silver): the viewport's light sweeps over the fish
--     head to tail every 2.5 s, as the game's runs down it, with stars in the skin's
--     effect colours following
--
-- A live preview (FishPreview, one at a time) is stepped every frame by its owner; a
-- card (CardPhoto, many) is set up once and its sparkles are tweens, so a grid of
-- cards costs no script time per frame.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local ShadesConfig = require(ReplicatedStorage.Shared.Config.Shades)

type Shade = ShadesConfig.Shade

local PreviewFx = {}

-- The glow map, brighter than in the water by this (no bloom in a viewport)
local GLOW_BOOST = 1.6
-- The back glow's ellipses (outermost first) and how much each adds at full strength
local RINGS = 7
local RING_ALPHA = 0.1
-- The shine (`sheen`: Golden, Silver): one sweep every PERIOD, taking SWEEP (SkinFx's
-- numbers), the light flaring toward the skin's `fxLight`, else Golden's warm white
local SHEEN_PERIOD = 2.5
local SHEEN_SWEEP = 0.95
local SHEEN_LIGHT = Color3.fromRGB(255, 236, 190)

type Shape = "star" | "dot" | "ring" | "puff"

-- How each effect (Config/Shades `fx`, Shared/SkinFx and Shared/Fx kinds) and aura is
-- drawn in 2D: its shape, its size (a share of the frame's height), how it drifts
-- (shares of the height a second, up positive), and which colour (1 the effect
-- colour, 2 the second)
type Look = { shape: Shape, size: number, drift: number, color: number, rainbow: boolean? }
local LOOKS: { [string]: Look } = {
	stardust = { shape = "star", size = 0.06, drift = 0.02, color = 1 },
	glints = { shape = "star", size = 0.07, drift = 0, color = 1 },
	crystal = { shape = "star", size = 0.09, drift = 0, color = 1 },
	gold = { shape = "star", size = 0.06, drift = -0.04, color = 1 },
	glitter = { shape = "star", size = 0.05, drift = 0, color = 1 },
	sheen = { shape = "star", size = 0.06, drift = 0, color = 2 },
	shimmer = { shape = "star", size = 0.06, drift = 0, color = 1, rainbow = true },
	rainbow = { shape = "star", size = 0.06, drift = 0.01, color = 1, rainbow = true },
	rainbowRim = { shape = "star", size = 0.05, drift = 0, color = 1, rainbow = true },
	tropical = { shape = "dot", size = 0.035, drift = 0.03, color = 1, rainbow = true },
	sparks = { shape = "star", size = 0.05, drift = 0, color = 2 },
	arcs = { shape = "star", size = 0.07, drift = 0, color = 2 },
	starfall = { shape = "star", size = 0.07, drift = -0.08, color = 1 },
	comet = { shape = "star", size = 0.06, drift = 0, color = 2 },
	halo = { shape = "star", size = 0.06, drift = 0.02, color = 1 },
	rays = { shape = "star", size = 0.06, drift = 0.03, color = 2 },
	sunburst = { shape = "star", size = 0.07, drift = 0, color = 2 },
	crown = { shape = "star", size = 0.06, drift = 0, color = 1 },
	stars = { shape = "star", size = 0.06, drift = 0.02, color = 1 },
	embers = { shape = "dot", size = 0.03, drift = 0.1, color = 1 },
	motes = { shape = "dot", size = 0.035, drift = 0.04, color = 1 },
	wisps = { shape = "dot", size = 0.03, drift = 0.06, color = 2 },
	drips = { shape = "dot", size = 0.03, drift = -0.12, color = 2 },
	aurora = { shape = "dot", size = 0.04, drift = 0.04, color = 2 },
	bubbles = { shape = "ring", size = 0.04, drift = 0.08, color = 2 },
	pearls = { shape = "ring", size = 0.05, drift = 0.03, color = 1 },
	foam = { shape = "ring", size = 0.03, drift = 0.03, color = 2 },
	mist = { shape = "puff", size = 0.3, drift = 0.02, color = 1 },
	ink = { shape = "puff", size = 0.28, drift = 0.01, color = 1 },
	nebula = { shape = "puff", size = 0.34, drift = 0, color = 1 },
	frost = { shape = "puff", size = 0.24, drift = -0.02, color = 2 },
	vortex = { shape = "puff", size = 0.22, drift = 0, color = 1 },
	swirls = { shape = "puff", size = 0.22, drift = 0, color = 1 },
	whirls = { shape = "puff", size = 0.2, drift = 0, color = 1 },
	currents = { shape = "puff", size = 0.24, drift = 0, color = 1 },
	ring = { shape = "puff", size = 0.26, drift = 0, color = 1 },
}

type Sprite = {
	holder: Frame,
	look: Look,
	color: Color3,
	x: number,
	y: number,
	period: number,
	phase: number,
	cycle: number,
	follow: boolean, -- rides the shine's sweep (Golden, Silver)
}

export type Handle = {
	-- Puts a skin on (nil: none) for the model in the viewport (its ShadeSkins get
	-- their glow boosted)
	setShade: (self: Handle, shadeId: string?, model: Instance?) -> (),
	-- One frame of a live preview (any clock)
	step: (self: Handle, t: number) -> (),
	destroy: (self: Handle) -> (),
}

type Options = { live: boolean, count: number? }

local function luminance(c: Color3): number
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

-- The skin's effect colours (SkinFx's): its effect colour, else its glow, sparkle or
-- fin colour; and the second, else its belly
local function colorsOf(shade: Shade): (Color3, Color3)
	return shade.fxColor or shade.glow or shade.sparkle or shade.fin, shade.fxColor2 or shade.belly
end

-- The light a skin casts (nil: none) and how strongly it shows behind the fish
local function lightOf(shade: Shade): (Color3?, number)
	if shade.glow then
		return shade.glow, 0.85
	elseif shade.light then
		return shade.light, 0.75
	elseif shade.fx and shade.fxColor then
		return shade.fxColor, 0.6
	elseif shade.emissive then
		return shade.fin, 0.5
	elseif shade.sparkle then
		return shade.sparkle, 0.3
	end
	return nil, 0
end

-- The 2D looks a skin's effects get, in order, at most three
local function looksOf(shade: Shade): { { look: Look, color: Color3 } }
	local c, c2 = colorsOf(shade)
	local kinds: { string } = {}
	if shade.fx then
		for _, kind in shade.fx do
			table.insert(kinds, kind)
		end
	elseif shade.aura then
		table.insert(kinds, shade.aura)
	elseif shade.sparkle then
		table.insert(kinds, "glints")
	end
	local out: { { look: Look, color: Color3 } } = {}
	for _, kind in kinds do
		local look = LOOKS[kind]
		if look and #out < 3 then
			table.insert(out, { look = look, color = if look.color == 2 then c2 else c })
		end
	end
	return out
end

local function corner(parent: Instance, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = parent
end

-- A bar fading out to both ends
local function bar(parent: Instance, size: UDim2, rotation: number, color: Color3)
	local b = Instance.new("Frame")
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromScale(0.5, 0.5)
	b.Size = size
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	local fade = Instance.new("UIGradient")
	fade.Rotation = rotation
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = b
	b.Parent = parent
end

-- One sprite's shape in a square holder (sized by its holder)
local function shapeIn(holder: Frame, shape: Shape, color: Color3)
	if shape == "star" then
		-- A four-point star: two crossing bars fading to their tips, a soft core
		bar(holder, UDim2.fromScale(1, 0.14), 0, color)
		bar(holder, UDim2.fromScale(0.14, 1), 90, color)
		local core = Instance.new("Frame")
		core.AnchorPoint = Vector2.new(0.5, 0.5)
		core.Position = UDim2.fromScale(0.5, 0.5)
		core.Size = UDim2.fromScale(0.3, 0.3)
		core.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
		core.BackgroundTransparency = 0.15
		core.BorderSizePixel = 0
		corner(core, 0.5)
		core.Parent = holder
		local halo = core:Clone()
		halo.Size = UDim2.fromScale(0.62, 0.62)
		halo.BackgroundColor3 = color
		halo.BackgroundTransparency = 0.7
		halo.Parent = holder
	elseif shape == "dot" then
		holder.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.25)
		holder.BackgroundTransparency = 0.1
		corner(holder, 0.5)
		local halo = Instance.new("Frame")
		halo.AnchorPoint = Vector2.new(0.5, 0.5)
		halo.Position = UDim2.fromScale(0.5, 0.5)
		halo.Size = UDim2.fromScale(2.4, 2.4)
		halo.BackgroundColor3 = color
		halo.BackgroundTransparency = 0.78
		halo.BorderSizePixel = 0
		corner(halo, 0.5)
		halo.Parent = holder
	elseif shape == "ring" then
		corner(holder, 0.5)
		local stroke = Instance.new("UIStroke")
		stroke.Color = color:Lerp(Color3.new(1, 1, 1), 0.4)
		stroke.Thickness = 1.5
		stroke.Transparency = 0.2
		stroke.Parent = holder
		holder.BackgroundColor3 = color
		holder.BackgroundTransparency = 0.82
	else
		-- A faint puff: three soft stacked circles (faint enough not to veil the fish)
		for i = 1, 3 do
			local ring = Instance.new("Frame")
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = UDim2.fromScale(0.5, 0.5)
			ring.Size = UDim2.fromScale(1 - (i - 1) * 0.28, 1 - (i - 1) * 0.28)
			ring.BackgroundColor3 = color
			ring.BackgroundTransparency = 0.94
			ring.BorderSizePixel = 0
			corner(ring, 0.5)
			ring.Parent = holder
		end
	end
end

-- A place over the fish: an ellipse round the frame's middle, where the fish is
local function spot(rng: Random): (number, number)
	local a = rng:NextNumber(0, 2 * math.pi)
	local r = math.sqrt(rng:NextNumber())
	return 0.5 + math.cos(a) * r * 0.34, 0.52 + math.sin(a) * r * 0.2
end

function PreviewFx.new(frame: ViewportFrame, options: Options): Handle
	local live = options.live
	local rng = Random.new()
	local baseAmbient = frame.Ambient
	local baseLight = frame.LightColor
	local baseDirection = frame.LightDirection
	local connections: { RBXScriptConnection } = {}

	-- The back glow, behind the viewport among its siblings (skipped where the parent
	-- lays its children out: it would take a slot)
	local parent = frame.Parent
	local glow: Frame? = nil
	local rings: { Frame } = {}
	if parent and not parent:FindFirstChildWhichIsA("UIGridStyleLayout") then
		local made = Instance.new("Frame")
		made.Name = "SkinGlow"
		made.BackgroundTransparency = 1
		made.Visible = false
		for i = 1, RINGS do
			local k = (i - 1) / (RINGS - 1) -- 0 outermost .. 1 innermost
			local ring = Instance.new("Frame")
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = UDim2.fromScale(0.5, 0.53)
			ring.Size = UDim2.fromScale(0.92 - 0.6 * k, 0.6 - 0.36 * k)
			ring.BackgroundTransparency = 1
			ring.BorderSizePixel = 0
			corner(ring, 0.5)
			ring.Parent = made
			table.insert(rings, ring)
		end
		local function mirror()
			made.AnchorPoint = frame.AnchorPoint
			made.Position = frame.Position
			made.Size = frame.Size
			made.ZIndex = math.max(frame.ZIndex - 1, 0)
		end
		mirror()
		for _, property in { "AnchorPoint", "Position", "Size", "ZIndex" } do
			table.insert(connections, frame:GetPropertyChangedSignal(property):Connect(mirror))
		end
		made.Parent = parent
		glow = made
	end

	-- The sparkles, over the fish (a viewport's children draw on top of it)
	local layer = Instance.new("Frame")
	layer.Name = "SkinSparkles"
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.ClipsDescendants = true
	layer.ZIndex = frame.ZIndex
	layer.Parent = frame

	local handle = {} :: Handle
	local shade: Shade? = nil
	local skins: { SurfaceAppearance } = {}
	local sprites: { Sprite } = {}
	local tweens: { Tween } = {}
	local glowAlpha = 0
	local sheen = false
	local dim = 1 -- a card shown locked (its ImageColor3 darkened) shows none of this

	local function setRings(k: number)
		if glow == nil then
			return
		end
		local a = RING_ALPHA * glowAlpha * k * dim
		for _, ring in rings do
			ring.BackgroundTransparency = 1 - math.clamp(a, 0, 1)
		end
	end

	local function clear()
		for _, tween in tweens do
			tween:Cancel()
		end
		table.clear(tweens)
		for _, sprite in sprites do
			sprite.holder:Destroy()
		end
		table.clear(sprites)
	end

	local function readDim()
		local l = luminance(frame.ImageColor3)
		dim = math.clamp((l - 0.6) / 0.35, 0, 1)
		layer.Visible = dim > 0.5
		setRings(1)
	end
	table.insert(connections, frame:GetPropertyChangedSignal("ImageColor3"):Connect(readDim))

	-- The frame's height in pixels (just parented, a frame may not be laid out yet:
	-- its parent's, then a card's)
	local function heightOf(): number
		local height = frame.AbsoluteSize.Y
		local holder = frame.Parent
		if height < 10 and holder and holder:IsA("GuiObject") then
			height = holder.AbsoluteSize.Y
		end
		return if height < 10 then 160 else height
	end

	local function sizeOf(look: Look): number
		return math.max(look.size * heightOf(), 5)
	end

	local function addSprite(look: Look, color: Color3, follow: boolean)
		local holder = Instance.new("Frame")
		holder.Name = "Sparkle"
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.ZIndex = layer.ZIndex
		local tint = if look.rainbow then Color3.fromHSV(rng:NextNumber(), 0.55, 1) else color
		shapeIn(holder, look.shape, tint)
		for _, d in holder:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = layer.ZIndex
			end
		end
		local x, y = spot(rng)
		local quick = look.shape == "star"
		local sprite: Sprite = {
			holder = holder,
			look = look,
			color = tint,
			x = x,
			y = y,
			period = if quick then rng:NextNumber(0.7, 1.4) else rng:NextNumber(1.6, 2.8),
			phase = rng:NextNumber(0, 3),
			cycle = -1,
			follow = follow,
		}
		holder.Position = UDim2.fromScale(x, y)
		holder.Size = UDim2.fromOffset(0, 0)
		holder.Parent = layer
		table.insert(sprites, sprite)
		if not live then
			-- A card: each sparkle swells and fades back where it is, forever
			local px = sizeOf(look) * rng:NextNumber(0.75, 1.2)
			local tween = TweenService:Create(
				holder,
				TweenInfo.new(
					sprite.period / 2,
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut,
					-1,
					true,
					sprite.phase
				),
				{ Size = UDim2.fromOffset(px, px) }
			)
			tween:Play()
			table.insert(tweens, tween)
		end
	end

	function handle.setShade(_self: Handle, shadeId: string?, model: Instance?)
		clear()
		table.clear(skins)
		shade = if shadeId then Config.Shades.byId[shadeId] else nil
		sheen = false
		frame.LightDirection = baseDirection
		frame.LightColor = baseLight
		local current = shade
		if current == nil then
			frame.Ambient = baseAmbient
			glowAlpha = 0
			if glow then
				glow.Visible = false
			end
			return
		end
		if model then
			for _, d in model:GetDescendants() do
				if d:IsA("SurfaceAppearance") and d.Name == "ShadeSkin" then
					table.insert(skins, d)
					d.EmissiveStrength = (current.emissive or 1) * GLOW_BOOST
				end
			end
		end
		local light, strength = lightOf(current)
		if light then
			glowAlpha = strength
			frame.Ambient = baseAmbient:Lerp(light, 0.22 * strength)
			if glow then
				for _, ring in rings do
					ring.BackgroundColor3 = light
				end
				glow.Visible = true
			end
		else
			frame.Ambient = baseAmbient
			glowAlpha = 0
			if glow then
				glow.Visible = false
			end
		end
		setRings(1)
		local count = options.count or (if live then 16 else 6)
		local looks = looksOf(current)
		if current.fx then
			sheen = table.find(current.fx, "sheen") ~= nil
		end
		if #looks > 0 then
			for i = 1, count do
				local pick = looks[(i - 1) % #looks + 1]
				-- (puffs are big: fewer of them)
				if pick.look.shape ~= "puff" or i <= #looks * 2 then
					addSprite(pick.look, pick.color, false)
				end
			end
		end
		if sheen and live then
			-- Stars riding the sweep
			local c, c2 = colorsOf(current)
			for i = 1, 5 do
				addSprite(LOOKS.sheen, if i % 2 == 0 then c else c2, true)
			end
		end
		readDim()
	end

	function handle.step(_self: Handle, t: number)
		local current = shade
		if current == nil then
			return
		end
		local pulse = math.clamp(Cosmetics.pulse(current.pulse, t), 0.45, 1.8)
		-- The glow map, brighter than in the water, pulsing as there
		local strength = (current.emissive or 1) * pulse * GLOW_BOOST
		for _, skin in skins do
			skin.EmissiveStrength = strength
		end
		setRings(0.75 + 0.35 * (pulse - 0.45) / 1.35)
		if current.cycle and glow then
			local hue = Color3.fromHSV((t * 0.12) % 1, 0.55, 1)
			for _, ring in rings do
				ring.BackgroundColor3 = hue
			end
		end
		-- The shine (Golden's, Silver's): the light swings over the fish head (left) to
		-- tail, flaring in the skin's shine colour
		local sweepAt: number? = nil
		if sheen then
			local k = (t % SHEEN_PERIOD) / SHEEN_SWEEP
			if k < 1 then
				sweepAt = k
				local a = math.pi * (0.1 + 0.8 * k)
				frame.LightDirection = Vector3.new(math.cos(a), -0.7, -0.55)
				local flare = math.sin(math.pi * k)
				frame.LightColor = baseLight:Lerp(current.fxLight or SHEEN_LIGHT, 0.6 * flare)
			else
				frame.LightDirection = baseDirection
				frame.LightColor = baseLight
			end
		end
		local height = heightOf()
		for _, sprite in sprites do
			local look = sprite.look
			if sprite.follow then
				local at = sweepAt
				if at == nil then
					sprite.holder.Size = UDim2.fromOffset(0, 0)
					continue
				end
				-- Along the fish with the band, twinkling fast
				local twinkle = math.abs(math.sin((t + sprite.phase) * 9))
				local px = look.size * height * twinkle * math.sin(math.pi * at)
				sprite.holder.Position = UDim2.fromScale(0.2 + 0.6 * at, sprite.y)
				sprite.holder.Size = UDim2.fromOffset(px, px)
				continue
			end
			local u = (t + sprite.phase) / sprite.period
			local cycle = math.floor(u)
			local k = u - cycle
			if cycle ~= sprite.cycle then
				sprite.cycle = cycle
				sprite.x, sprite.y = spot(rng)
			end
			local swell = math.sin(math.pi * k)
			if look.shape == "star" then
				swell = swell ^ 3
			end
			local px = look.size * height * swell
			sprite.holder.Size = UDim2.fromOffset(px, px)
			sprite.holder.Position =
				UDim2.fromScale(sprite.x, sprite.y - look.drift * k * sprite.period * 0.5)
			sprite.holder.Rotation = if look.shape == "star" then 20 * k else 0
		end
	end

	function handle.destroy(_self: Handle)
		clear()
		for _, connection in connections do
			connection:Disconnect()
		end
		if glow then
			glow:Destroy()
		end
		layer:Destroy()
	end

	-- Gone with its viewport
	table.insert(
		connections,
		frame.Destroying:Connect(function()
			handle:destroy()
		end)
	)
	return handle
end

return PreviewFx
