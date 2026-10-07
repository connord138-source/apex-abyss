--!strict
-- The AI predators on this client (Config/Predators, PredatorService). The server
-- streams their positions ten times a second over an unreliable remote; this
-- controller keeps a short history per predator and draws each one a little behind
-- the stream, so they glide instead of stepping. Events (PredatorEvent) carry the
-- moments: a windup (the jaw flashes, and a warning if it's coming for us), a bite
-- (bubbles), a hurt (a flash, a damage pop for our own bites) and a death (a fade).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Ui = require(script.Parent.Parent.Ui)

local Predators = Config.Predators

type Def = typeof(Predators.list[1])

local PredatorController = {
	-- (damage, position) — our bite landed on a predator (HUD pops the number)
	hit = Signal.new(),
}

local HISTORY = 8 -- stream samples kept per predator
local EXTRAPOLATE = 0.25 -- seconds we keep moving past the last sample
local FADE_SECONDS = 0.7
local TAG_DISTANCE = 240

type Sample = {
	at: number,
	position: Vector3,
	heading: Vector3,
}

type Visual = {
	index: number,
	def: Def,
	body: BasePart,
	tail: BasePart?,
	bodySize: Vector3,
	tailSize: Vector3,
	samples: { Sample },
	position: Vector3, -- where it's drawn this frame
	heading: Vector3,
	mode: string,
	health: number, -- 0..1
	target: number, -- userId it's hunting (0 = none)
	hidden: boolean,
	fade: number, -- 0 hidden .. 1 shown, eased
	windupUntil: number,
	flashUntil: number,
	jaw: Highlight,
	glow: PointLight,
	tag: BillboardGui,
	healthFill: Frame,
	status: TextLabel,
}

local visuals: { [number]: Visual } = {}
local parts: { BasePart } = {}
local frames: { CFrame } = {}
local folder: Folder
local warning: TextLabel
local warningUntil = 0

local function makePart(parent: Instance, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.Parent = parent
	return part
end

-- The imported mesh (docs/ASSETS.md): ReplicatedStorage.PreyModels.<model>, a
-- MeshPart facing -Z. Nil while it isn't imported (parts are drawn instead).
local function template(name: string): MeshPart?
	local models = ReplicatedStorage:FindFirstChild("PreyModels")
	local found = models and models:FindFirstChild(name)
	if found and found:IsA("MeshPart") then
		return found
	end
	if found and found:IsA("Model") then
		return found:FindFirstChildWhichIsA("MeshPart", true)
	end
	return nil
end

local function makeTag(visual: Visual)
	local def = visual.def
	local gui = Instance.new("BillboardGui")
	gui.Name = "PredatorTag"
	gui.Size = UDim2.fromOffset(220, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, def.length * 0.45 + 2, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = TAG_DISTANCE
	gui.Adornee = visual.body
	local name =
		Ui.label(gui, "Name", `PREDATOR · {string.upper(def.name)}`, Ui.FONT_HEAVY, 15, Ui.color.danger)
	name.Size = UDim2.new(1, 0, 0, 20)
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextStrokeTransparency = 0.5
	local status = Ui.label(
		gui,
		"Status",
		"",
		Ui.FONT_SEMI,
		12,
		Ui.color.text,
		UDim2.new(1, 0, 0, 14),
		UDim2.fromOffset(0, 20)
	)
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.TextStrokeTransparency = 0.6
	local _, fill = Ui.bar(gui, "Health", UDim2.new(0.6, 0, 0, 5), UDim2.new(0.2, 0, 0, 38), Ui.color.danger)
	fill.Size = UDim2.fromScale(1, 1)
	gui.Parent = visual.body
	visual.tag = gui
	visual.healthFill = fill
	visual.status = status
end

local function build(index: number, def: Def): Visual
	local length = def.length
	local bodySize = Vector3.new(length * 0.2, length * 0.24, length * 0.8)
	local tailSize = Vector3.new(length * 0.03, length * 0.3, length * 0.26)
	local mesh = template(def.model)
	local body: BasePart
	local tail: BasePart? = nil
	if mesh then
		local clone = mesh:Clone()
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanQuery = false
		clone.CanTouch = false
		clone.CastShadow = false
		bodySize = mesh.Size * (length / math.max(mesh.Size.Z, 0.01))
		clone.Size = bodySize
		clone.Parent = folder
		body = clone
	else
		body = makePart(folder, def.back)
		body.Size = bodySize
		local fin = makePart(folder, def.back:Lerp(def.belly, 0.3))
		fin.Name = "Tail"
		fin.Size = tailSize
		tail = fin
	end
	body.Name = def.id
	-- The jaw tell and hurt flash: a highlight that's off until needed
	local jaw = Instance.new("Highlight")
	jaw.Name = "Jaw"
	jaw.FillColor = Ui.color.danger
	jaw.FillTransparency = 1
	jaw.OutlineColor = Ui.color.danger
	jaw.OutlineTransparency = 1
	jaw.DepthMode = Enum.HighlightDepthMode.Occluded
	jaw.Adornee = body
	jaw.Parent = body
	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = Ui.color.danger
	glow.Brightness = 0
	glow.Range = length * 1.6
	glow.Shadows = false
	glow.Parent = body
	local visual: Visual = {
		index = index,
		def = def,
		body = body,
		tail = tail,
		bodySize = bodySize,
		tailSize = tailSize,
		samples = {},
		position = Vector3.new(0, -500, 0),
		heading = Vector3.new(1, 0, 0),
		mode = "dead",
		health = 1,
		target = 0,
		hidden = true,
		fade = 0,
		windupUntil = 0,
		flashUntil = 0,
		jaw = jaw,
		glow = glow,
		tag = nil :: any,
		healthFill = nil :: any,
		status = nil :: any,
	}
	makeTag(visual)
	visual.tag.Enabled = false
	body.Transparency = 1
	if tail then
		tail.Transparency = 1
	end
	return visual
end

local function setHidden(visual: Visual, hidden: boolean)
	if visual.hidden == hidden then
		return
	end
	visual.hidden = hidden
	visual.tag.Enabled = not hidden
	if hidden then
		visual.windupUntil = 0
		visual.jaw.FillTransparency = 1
		visual.jaw.OutlineTransparency = 1
		visual.glow.Brightness = 0
	end
end

local function bubbles(position: Vector3, size: number)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Speed = NumberRange.new(size * 1.5, size * 4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, size * 2, 0)
	emitter.Drag = 3
	emitter.Size = NumberSequence.new(size * 0.12, size * 0.04)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.LightEmission = 0.5
	emitter.Color = ColorSequence.new(Color3.fromRGB(220, 250, 255))
	emitter.Parent = holder
	holder.Parent = workspace
	emitter:Emit(math.clamp(math.floor(size * 6), 8, 60))
	task.delay(2, function()
		holder:Destroy()
	end)
end

-- Where the predator is at `t`, from its stream samples: between the two that
-- bracket it, or a little past the last one.
local function sampleAt(visual: Visual, t: number): (Vector3, Vector3)
	local samples = visual.samples
	local count = #samples
	if count == 0 then
		return visual.position, visual.heading
	end
	local last = samples[count]
	if count == 1 or t >= last.at then
		if count >= 2 and t > last.at then
			local previous = samples[count - 1]
			local span = last.at - previous.at
			if span > 1e-3 then
				local velocity = (last.position - previous.position) / span
				local ahead = math.min(t - last.at, EXTRAPOLATE)
				return last.position + velocity * ahead, last.heading
			end
		end
		return last.position, last.heading
	end
	for i = count - 1, 1, -1 do
		local a = samples[i]
		if t >= a.at then
			local b = samples[i + 1]
			local alpha = math.clamp((t - a.at) / math.max(b.at - a.at, 1e-3), 0, 1)
			local heading = a.heading:Lerp(b.heading, alpha)
			return a.position:Lerp(b.position, alpha),
				if heading.Magnitude > 1e-3 then heading.Unit else b.heading
		end
	end
	local first = samples[1]
	return first.position, first.heading
end

local function frameOf(position: Vector3, heading: Vector3): CFrame
	local up = if math.abs(heading.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt(position, position + heading, up)
end

local function step(dt: number)
	local now = Timing.clock()
	local renderAt = now - Predators.interpolationDelay
	local me = Players.LocalPlayer.UserId
	table.clear(parts)
	table.clear(frames)
	for _, visual in visuals do
		-- Fade in and out
		local goal = if visual.hidden then 0 else 1
		if visual.fade ~= goal then
			visual.fade =
				math.clamp(visual.fade + (if goal > visual.fade then dt else -dt) / FADE_SECONDS, 0, 1)
			local transparency = 1 - visual.fade
			visual.body.Transparency = transparency
			if visual.tail then
				visual.tail.Transparency = transparency
			end
		end
		if visual.fade <= 0 then
			continue
		end
		local position, heading = sampleAt(visual, renderAt)
		visual.position = position
		-- Turn smoothly toward the streamed heading
		local blended = visual.heading:Lerp(heading, 1 - math.exp(-dt * 8))
		visual.heading = if blended.Magnitude > 1e-3 then blended.Unit else heading
		local frame = frameOf(position, visual.heading)
		local speed = if #visual.samples >= 2
			then (visual.samples[#visual.samples].position - visual.samples[#visual.samples - 1].position).Magnitude
				/ math.max(visual.samples[#visual.samples].at - visual.samples[#visual.samples - 1].at, 1e-3)
			else 0
		local rate = 3 + math.min(speed / math.max(visual.def.speed, 1), 1.5) * 5
		local beat = math.sin(now * rate + visual.index * 1.7) * 0.4
		table.insert(parts, visual.body)
		local tail = visual.tail
		if tail then
			table.insert(frames, frame)
			table.insert(parts, tail)
			table.insert(
				frames,
				frame
					* CFrame.new(0, 0, visual.bodySize.Z * 0.45)
					* CFrame.Angles(0, beat, 0)
					* CFrame.new(0, 0, tail.Size.Z * 0.4)
			)
		else
			table.insert(
				frames,
				frame
					* CFrame.new(0, 0, -visual.bodySize.Z * 0.3)
					* CFrame.Angles(0, beat * 0.18, 0)
					* CFrame.new(0, 0, visual.bodySize.Z * 0.3)
			)
		end
		-- The tell: the jaw flashes faster as the bite comes; a hurt flash is white
		if visual.flashUntil > now then
			visual.jaw.FillColor = Color3.new(1, 1, 1)
			visual.jaw.FillTransparency = 0.35
			visual.jaw.OutlineTransparency = 0.2
			visual.glow.Brightness = 0
		elseif visual.windupUntil > now then
			local left = visual.windupUntil - now
			local pulse = 0.5
				+ 0.5 * math.sin(now * (14 + (1 - math.clamp(left / visual.def.telegraph, 0, 1)) * 20))
			visual.jaw.FillColor = Ui.color.danger
			visual.jaw.FillTransparency = 0.45 + 0.4 * pulse
			visual.jaw.OutlineTransparency = 0.1
			visual.glow.Brightness = 1.5 + 2 * pulse
		else
			visual.jaw.FillTransparency = 1
			visual.jaw.OutlineTransparency = 1
			visual.glow.Brightness = 0
		end
		-- The tag's status line
		if visual.target == me then
			visual.status.Text = "HUNTING YOU"
			visual.status.TextColor3 = Ui.color.danger
		elseif visual.mode == "hunt" or visual.mode == "windup" or visual.mode == "recover" then
			visual.status.Text = "HUNTING"
			visual.status.TextColor3 = Ui.color.haul
		else
			visual.status.Text = "ROAMING"
			visual.status.TextColor3 = Ui.color.muted
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- The incoming warning
	if warningUntil > now then
		local left = warningUntil - now
		warning.Visible = true
		warning.TextTransparency = if left < 0.3 then 1 - left / 0.3 else 0.5 + 0.5 * math.sin(now * 18) * 0.4
	else
		warning.Visible = false
	end
end

-- A stream packet: { at, list = { {index, x, y, z, hx, hy, hz, mode, hp01, targetUserId}, ... } }
local function onState(packet: any)
	if typeof(packet) ~= "table" or typeof(packet.at) ~= "number" or typeof(packet.list) ~= "table" then
		return
	end
	local at = packet.at
	for _, entry in packet.list do
		if typeof(entry) ~= "table" or typeof(entry[1]) ~= "number" then
			continue
		end
		local visual = visuals[entry[1]]
		if visual == nil then
			continue
		end
		local x, y, z = entry[2], entry[3], entry[4]
		local hx, hy, hz = entry[5], entry[6], entry[7]
		if typeof(x) ~= "number" or typeof(y) ~= "number" or typeof(z) ~= "number" then
			continue
		end
		local heading = Vector3.new(
			if typeof(hx) == "number" then hx else 1,
			if typeof(hy) == "number" then hy else 0,
			if typeof(hz) == "number" then hz else 0
		)
		if heading.Magnitude < 1e-3 then
			heading = Vector3.xAxis
		end
		local samples = visual.samples
		local last = samples[#samples]
		if last == nil or at > last.at then
			table.insert(samples, { at = at, position = Vector3.new(x, y, z), heading = heading.Unit })
			if #samples > HISTORY then
				table.remove(samples, 1)
			end
		end
		local mode = entry[8]
		visual.mode = if typeof(mode) == "string" then mode else visual.mode
		local hp = entry[9]
		if typeof(hp) == "number" then
			visual.health = math.clamp(hp, 0, 1)
			visual.healthFill.Size = UDim2.fromScale(visual.health, 1)
		end
		local target = entry[10]
		visual.target = if typeof(target) == "number" then target else 0
		-- Joined mid-life, or missed an event: the mode says whether it's there
		if visual.mode == "dead" then
			setHidden(visual, true)
		elseif visual.hidden then
			-- A fresh life starts where the stream says, not where the last one ended
			visual.position = Vector3.new(x, y, z)
			visual.heading = heading.Unit
			setHidden(visual, false)
		end
	end
end

local function onEvent(kind: any, index: any, payload: any)
	if typeof(kind) ~= "string" or typeof(index) ~= "number" or typeof(payload) ~= "table" then
		return
	end
	local visual = visuals[index]
	if visual == nil then
		return
	end
	local now = Timing.clock()
	local me = Players.LocalPlayer.UserId
	if kind == "spawned" then
		if
			typeof(payload.x) == "number"
			and typeof(payload.y) == "number"
			and typeof(payload.z) == "number"
		then
			local position = Vector3.new(payload.x, payload.y, payload.z)
			table.clear(visual.samples)
			visual.position = position
			visual.mode = "roam"
			visual.health = 1
			visual.healthFill.Size = UDim2.fromScale(1, 1)
		end
		setHidden(visual, false)
	elseif kind == "windup" then
		local seconds = if typeof(payload.seconds) == "number" then payload.seconds else visual.def.telegraph
		visual.windupUntil = now + seconds
		if payload.target == me then
			warning.Text = `{string.upper(visual.def.name)} · INCOMING`
			warningUntil = now + seconds + 0.3
		end
	elseif kind == "bite" then
		visual.windupUntil = 0
		if
			typeof(payload.x) == "number"
			and typeof(payload.y) == "number"
			and typeof(payload.z) == "number"
		then
			bubbles(
				Vector3.new(payload.x, payload.y, payload.z),
				if payload.hit == true then visual.def.length * 0.5 else visual.def.length * 0.25
			)
		end
	elseif kind == "hurt" then
		visual.flashUntil = now + 0.12
		if typeof(payload.health) == "number" then
			visual.health = math.clamp(payload.health, 0, 1)
			visual.healthFill.Size = UDim2.fromScale(visual.health, 1)
		end
		local position = if typeof(payload.x) == "number"
				and typeof(payload.y) == "number"
				and typeof(payload.z) == "number"
			then Vector3.new(payload.x, payload.y, payload.z)
			else visual.position
		bubbles(position, visual.def.length * 0.2)
		if payload.by == me and typeof(payload.damage) == "number" then
			PredatorController.hit:fire(payload.damage, position)
		end
	elseif kind == "died" then
		visual.mode = "dead"
		bubbles(visual.position, visual.def.length * 0.9)
		setHidden(visual, true)
		if payload.by == me then
			TweenService:Create(visual.jaw, TweenInfo.new(0.1), { FillTransparency = 1 }):Play()
		end
	end
end

-- The index of the live predator whose body is within `reach` of `mouth` (nearest
-- first), or nil. Distance is to the body's tail-to-nose line, like the server's.
function PredatorController.nearest(mouth: Vector3, reach: number): number?
	local best: number? = nil
	local bestGap = math.huge
	for index, visual in visuals do
		if visual.hidden or visual.mode == "dead" then
			continue
		end
		local half = visual.heading * visual.def.length * 0.5
		local a, b = visual.position - half, visual.position + half
		local ab = b - a
		local t = math.clamp((mouth - a):Dot(ab) / math.max(ab:Dot(ab), 1e-4), 0, 1)
		local gap = (a + ab * t - mouth).Magnitude - visual.def.length * 0.18
		if gap <= reach and gap < bestGap then
			best, bestGap = index, gap
		end
	end
	return best
end

-- The predator drawn at `index` (its position and whether it's alive), for other
-- controllers' effects.
function PredatorController.get(index: number): (Vector3?, string?)
	local visual = visuals[index]
	if visual == nil then
		return nil, nil
	end
	return visual.position, visual.mode
end

function PredatorController.start()
	folder = Instance.new("Folder")
	folder.Name = "Predators"
	folder.Parent = workspace
	-- The same indices the server hands out: in list order, `count` each
	local index = 0
	for _, def in Predators.list do
		for _ = 1, def.count do
			index += 1
			visuals[index] = build(index, def)
		end
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Ui.screen("Predators", playerGui, 6)
	warning = Ui.label(
		gui,
		"Warning",
		"",
		Ui.FONT_HEAVY,
		22,
		Ui.color.danger,
		UDim2.new(1, 0, 0, 30),
		UDim2.new(0, 0, 0.5, -120)
	)
	warning.TextXAlignment = Enum.TextXAlignment.Center
	warning.TextStrokeTransparency = 0.4
	warning.Visible = false
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local state = remotes:WaitForChild("PredatorState") :: UnreliableRemoteEvent
	state.OnClientEvent:Connect(onState)
	local event = remotes:WaitForChild("PredatorEvent") :: RemoteEvent
	event.OnClientEvent:Connect(onEvent)
	RunService.RenderStepped:Connect(step)
end

return PredatorController
