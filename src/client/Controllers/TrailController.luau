--!strict
-- Boost trails (Config/Trails; owner, 2026-10-17: "boost effects, such as bubbles,
-- rainbow, glitter, fire, etc as an earnable customization"): what streams off each
-- fish's tail, from its character's `Trail` attribute. Faint while a fish swims
-- fast, full on a dash (over its top speed). Your own fish reads SwimController's
-- velocity; other fish the velocity their root replicates. Particles are left in
-- the water where they're shed, so they hang behind the fish as it swims.
--
-- Drawn about twice as present as the same presets on a skin (playtest 2026-10-17:
-- at LV 40 every trail read small and faint): particles `SIZE` times bigger, ribbons
-- `WIDE` times wider, denser on a dash. Colours that must hold their own against the
-- blue water (fire, ink, the rainbow) are drawn mostly blended rather than added: an
-- added orange or red on blue water turns grey-blue or violet, the way Fire Wake
-- went grey on a dash and the rainbow read teal to violet.
--
-- Seen from behind, your own fish's trail never reaches the camera (PC 2026-10-18:
-- Fire Wake's flames came at the camera and filled the screen): while it sheds,
-- each emitter's and ribbon's lifetime is cut to the time the camera takes to swim
-- up to where it was shed (`BEHIND` of it).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Fx = require(ReplicatedStorage.Shared.Fx)
local Size = require(ReplicatedStorage.Shared.Size)
local SwimController = require(script.Parent.SwimController)

-- A storm's lightning: points behind the tail joined by bolts
type Arc = { points: { Attachment }, beams: { Beam } }

type Entry = {
	player: Player,
	root: BasePart,
	id: string,
	length: number,
	holder: Attachment, -- at the tail
	emitters: { ParticleEmitter },
	ribbons: { Trail },
	flicker: boolean, -- a storm's ribbon crackles
	arcs: { Arc },
	nextArc: number,
	lit: boolean, -- an arc may be showing
	extras: { Instance }, -- made on the root (the arcs' points and bolts)
}

local TrailController = {}

local entries: { [Model]: Entry } = {}
local lifetimes: { [Instance]: NumberRange } = {} -- each emitter's and ribbon's own (pruned with its trail)
local FAR = 320 -- studs from the camera past which nothing is shed
local SIZE = 2 -- particles, × a skin's
local WIDE = 1.4 -- ribbons, × their old width
local BEHIND = 0.75 -- of the time the camera takes to reach a shed particle
local SHORTEST = 0.12 -- seconds a particle or ribbon lives at the least

local function lengthOf(character: Model): number
	local length = character:GetAttribute("Length")
	return if typeof(length) == "number" then length else 2
end

local function forget(character: Model)
	local entry = entries[character]
	if entry then
		entries[character] = nil
		for _, e in entry.emitters do
			lifetimes[e] = nil
		end
		for _, ribbon in entry.ribbons do
			lifetimes[ribbon] = nil
		end
		entry.holder:Destroy()
		for _, made in entry.extras do
			made:Destroy()
		end
	end
end

local function build(player: Player, character: Model)
	forget(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local id = character:GetAttribute("Trail")
	if root == nil or not root:IsA("BasePart") or typeof(id) ~= "string" then
		return
	end
	local trail = Config.Trails.byId[id]
	if trail == nil then
		return
	end
	local L = lengthOf(character)
	-- The tail: behind the root (a fish faces -Z)
	local holder = Instance.new("Attachment")
	holder.Name = "BoostTrail"
	holder.Position = Vector3.new(0, 0, L * 0.42)
	holder.Parent = root
	local c, c2 = trail.color, trail.color2
	local emitters: { ParticleEmitter } = {}
	local function emit(
		preset: Fx.Preset,
		rate: number,
		color: ColorSequence?,
		size: number?
	): ParticleEmitter
		local e = Fx.emitter(holder, preset, L, c, c2, rate, size or SIZE)
		if color then
			e.Color = color
		end
		lifetimes[e] = e.Lifetime
		e.Enabled = false
		table.insert(emitters, e)
		return e
	end
	local ribbons: { Trail } = {}
	-- A ribbon `width` lengths across, standing up (or lying flat)
	local function band(width: number, lifetime: number, color: ColorSequence, flat: boolean?): Trail
		local half = width * WIDE * L * 0.5
		local across = if flat then Vector3.new(half, 0, 0) else Vector3.new(0, half, 0)
		local a0 = Instance.new("Attachment")
		a0.Name = "BoostTrail0"
		a0.Position = across
		a0.Parent = holder
		local a1 = Instance.new("Attachment")
		a1.Name = "BoostTrail1"
		a1.Position = -across
		a1.Parent = holder
		local made = Fx.ribbon(holder, a0, a1, lifetime, color, Fx.keys({ 0, 0.15, 0.6, 0.5, 1, 1 }))
		lifetimes[made] = NumberRange.new(lifetime)
		made.Enabled = false
		table.insert(ribbons, made)
		return made
	end
	local arcs: { Arc } = {}
	local extras: { Instance } = {}
	local style = trail.style
	if style == "bubbles" then
		emit("bubbles", 3.6)
	elseif style == "glitter" then
		-- Glints flicking off, gold flakes falling and twinkles in both colours
		emit("glints", 2)
		emit("gold", 1)
		emit("stardust", 1)
	elseif style == "flame" then
		-- Orange-red to the end of its life, fading out (never a smoke stage): a
		-- yellow core only at the start (it read yellow fading to pinkish-grey, PC
		-- 2026-10-18), gone before it cools
		local hot = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 196, 80)),
			ColorSequenceKeypoint.new(0.18, c),
			ColorSequenceKeypoint.new(1, c2),
		})
		local fire = emit("flame", 1.2, hot, 1.6)
		fire.LightEmission = 0.4
		fire.Brightness = 2.4
		fire.Transparency = Fx.keys({ 0, 0.1, 0.4, 0.22, 0.75, 0.7, 1, 1 })
		local sparks = emit("embers", 1.2)
		sparks.LightEmission = 0.6
	elseif style == "rainbow" then
		-- Two ribbons crossed, so it reads from the side and from above
		for _, flat in { false, true } do
			local made = band(0.22, 0.65, Fx.rainbow(0.75), flat)
			made.LightEmission = 0.35
			made.Brightness = 2
		end
		emit("stardust", 1.6, Fx.rainbow(0.6), 2.2)
	elseif style == "storm" then
		local charged = band(0.1, 0.35, ColorSequence.new(c2, c))
		charged.Brightness = 2
		emit("sparks", 2.5, nil, 2.2)
		-- Lightning crackling off the tail (re-struck in `strike`)
		local bolt = ColorSequence.new(Color3.new(1, 1, 1), c)
		for _ = 1, 2 do
			local points: { Attachment } = {}
			local beams: { Beam } = {}
			for i = 1, 4 do
				local point = Instance.new("Attachment")
				point.Name = "BoostArc"
				point.Position = holder.Position
				point.Parent = root
				points[i] = point
				table.insert(extras, point)
			end
			-- A bright core and a wide faint glow round it on every segment (the arcs read
			-- faint at 0.035 wide, PC 2026-10-19, TR3)
			for i = 1, 3 do
				local beam = Fx.beam(root, points[i], points[i + 1], L * 0.05, L * 0.05, bolt)
				beam.Name = "BoostArc"
				beam.Brightness = 4
				beam.Enabled = false
				table.insert(beams, beam)
				table.insert(extras, beam)
				local glow = Fx.beam(root, points[i], points[i + 1], L * 0.16, L * 0.16, ColorSequence.new(c))
				glow.Name = "BoostArc"
				glow.Brightness = 2
				glow.Transparency = NumberSequence.new(0.55)
				glow.Enabled = false
				table.insert(beams, glow)
				table.insert(extras, glow)
			end
			table.insert(arcs, { points = points, beams = beams })
		end
	elseif style == "stardust" then
		emit("stardust", 2.6, nil, 2.7)
		emit("nebula", 1.5, nil, 1.5)
	elseif style == "frost" then
		local made = band(0.14, 0.5, ColorSequence.new(c, c2))
		made.LightEmission = 0.7
		made.Brightness = 1.6
		emit("frost", 1.2, nil, 1.6)
		emit("crystal", 1.2)
	elseif style == "ink" then
		-- A lit violet-indigo cloud: glowing at first, deepening as it spreads
		-- (brighter and thicker again: "visible now but still faint", PC 2026-10-18)
		-- (and again: "glows violet round the fish, but dimly", PC 2026-10-19, TR3)
		local ink = emit("ink", 2, ColorSequence.new(c2, c), 2.2)
		ink.LightEmission = 0.75
		ink.LightInfluence = 0.1
		ink.Transparency = Fx.keys({ 0, 1, 0.1, 0.05, 0.6, 0.2, 1, 1 })
	end
	entries[character] = {
		player = player,
		root = root,
		id = id,
		length = L,
		holder = holder,
		emitters = emitters,
		ribbons = ribbons,
		flicker = style == "storm",
		arcs = arcs,
		nextArc = 0,
		lit = false,
		extras = extras,
	}
end

-- A storm's arcs jump somewhere new behind the tail (every 0.06-0.12 s), each lit
-- on most strikes, more often the faster it goes; `k` 0 puts them out
local function strike(entry: Entry, k: number)
	local L = entry.length
	for _, arc in entry.arcs do
		local on = k > 0 and math.random() < 0.35 + 0.35 * k
		for _, beam in arc.beams do
			beam.Enabled = on
		end
		if on then
			local n = #arc.points
			local reach = L * (0.5 + math.random() * 0.9)
			local endX = (math.random() - 0.5) * L * 0.5
			local endY = (math.random() - 0.5) * L * 0.5
			for i, point in arc.points do
				local f = (i - 1) / (n - 1)
				local jag = if i == 1 then L * 0.06 elseif i == n then 0 else L * 0.18
				point.Position = Vector3.new(
					endX * f + (math.random() - 0.5) * jag,
					endY * f + (math.random() - 0.5) * jag,
					L * 0.42 + reach * f
				)
			end
		end
	end
end

local function watch(player: Player)
	local function track(character: Model)
		task.spawn(function()
			character:WaitForChild("HumanoidRootPart", 8)
			if character.Parent then
				build(player, character)
			end
		end)
		character:GetAttributeChangedSignal("Trail"):Connect(function()
			build(player, character)
		end)
	end
	player.CharacterAdded:Connect(track)
	player.CharacterRemoving:Connect(forget)
	if player.Character then
		track(player.Character)
	end
end

-- An emitter's or ribbon's own lifetime, at most `most` seconds
local function cut(made: Instance, most: number)
	local own: NumberRange? = lifetimes[made]
	if not own then
		return
	end
	if made:IsA("ParticleEmitter") then
		made.Lifetime = NumberRange.new(math.min(own.Min, most), math.min(own.Max, most))
	elseif made:IsA("Trail") then
		made.Lifetime = math.min(own.Max, most)
	end
end

local function step()
	local camera = Workspace.CurrentCamera
	local now = os.clock()
	for character, entry in entries do
		if entry.root.Parent == nil or character.Parent == nil then
			forget(character)
			continue
		end
		-- A fish that grew gets a trail sized to it
		local length = lengthOf(character)
		if math.abs(length - entry.length) > entry.length * 0.2 then
			build(entry.player, character)
			continue
		end
		local speed = if entry.player == Players.LocalPlayer
			then SwimController.velocity.Magnitude
			else entry.root.AssemblyLinearVelocity.Magnitude
		local relative = speed / math.max(Size.topSpeed(length), 1)
		-- Faint from 60% of top speed, full on a dash (past top speed)
		local k = math.clamp((relative - 0.6) / 0.6, 0, 1)
		local away = if camera then (camera.CFrame.Position - entry.root.Position).Magnitude else 0
		local on = k > 0.02 and away < FAR
		-- Your own trail dies before the camera, following, reaches it
		local most = if entry.player == Players.LocalPlayer and on
			then math.max(away / math.max(speed, 1) * BEHIND, SHORTEST)
			else math.huge
		for _, e in entry.emitters do
			e.Enabled = on
			if on then
				local base = e:GetAttribute("Rate")
				-- (a fifth at the first, a fifth over its own rate on a dash)
				e.Rate = (if typeof(base) == "number" then base else 6) * (0.2 + k)
				cut(e, most)
			end
		end
		for _, ribbon in entry.ribbons do
			ribbon.Enabled = on
			if on then
				cut(ribbon, most)
			end
			if on and entry.flicker then
				ribbon.Transparency = Fx.keys({ 0, if math.random() < 0.3 then 0.7 else 0.1, 1, 1 })
			end
		end
		if #entry.arcs > 0 and ((on and now >= entry.nextArc) or (not on and entry.lit)) then
			entry.nextArc = now + 0.06 + math.random() * 0.06
			entry.lit = on
			strike(entry, if on then k else 0)
		end
	end
end

function TrailController.start()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	RunService.Heartbeat:Connect(step)
end

return TrailController
