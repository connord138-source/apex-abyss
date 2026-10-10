--!strict
-- Brings the Treasure Wheel (src/server/TreasureWheel.luau; Config/Wheel) to life on
-- every client. Ported from Hatch & Snatch's Luck Wheel controller. WheelService
-- publishes each spin on ReplicatedStorage.WheelState (SpinId last) and every client
-- turns the disc through the same eased spin, so everyone nearby watches the same
-- thing:
--   * the wheel is found by its tag and bound again whenever it streams back in;
--   * the disc moves with one BulkMoveTo from offsets taken off its hub;
--   * a flapper swings off each peg as it passes and ticks, heard near the wheel only;
--   * marquee bulbs chase, faster while it spins; at the end the winning slice and
--     the bulbs flash, confetti pops, and the spinner gets a result banner (even with
--     the wheel streamed out: the spin lives in ReplicatedStorage).
-- And, since ProximityPrompts never worked for the fish characters, its own hint at
-- the big red button: E · SPIN (Y on a controller) and T · SPIN ALL, a SPIN button on
-- phones, or when the next free spin comes. Presentation only; the server decides.
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local MenuController = require(script.Parent.MenuController)
local StartController = require(script.Parent.StartController)
local SwimController = require(script.Parent.SwimController)

local TAG = "TreasureWheel"
local CONFETTI_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local FLAPPER_MAX = 38 -- degrees the flapper swings before a peg slips past it
local SPRING = 900 -- the flapper's spring back (per degree, per second squared)
local DAMPING = 16
local FAST_PEGS = 12 -- pegs a second above which the flapper just rattles
local TICK_GAP = 0.045 -- at most ~22 ticks a second
local FLASH_SECONDS = 3.2
local BANNER_SECONDS = 3.6
local BULB_ON = Color3.fromRGB(255, 240, 200)
local BULB_DIM = Color3.fromRGB(120, 60, 28)
local CONFETTI = {
	Color3.fromRGB(255, 214, 70),
	Color3.fromRGB(255, 90, 150),
	Color3.fromRGB(80, 200, 255),
	Color3.fromRGB(140, 255, 120),
}

local Wheel = Config.Wheel
local segments = Wheel.segments
local player = Players.LocalPlayer
local rng = Random.new()

type Rig = { parts: { BasePart }, offsets: { CFrame } }
type Bulb = { part: BasePart, group: string, index: number }
type Wheel = {
	model: Model,
	base: CFrame,
	spacing: number, -- degrees between pegs
	disc: Rig,
	flapper: Rig,
	pivot: CFrame,
	flap: number, -- the flapper's swing, degrees (+ = pushed the way the wheel turns)
	flapVelocity: number,
	shownFlap: number,
	posedRest: boolean,
	bulbs: { Bulb },
	bulbKey: number,
	slices: { [number]: { BasePart } },
	materials: { [BasePart]: Enum.Material },
	flashIndex: number?,
	flashUntil: number,
	emitters: { ParticleEmitter },
	lastPeg: number, -- pegs passed, for the ticks
	mount: BasePart?,
	button: BasePart?,
	buttonRest: CFrame?,
}
type Spin = {
	id: number,
	from: number,
	to: number,
	start: number,
	duration: number,
	index: number,
	spinnerId: number,
	detail: string,
}

local wheels: { [Model]: Wheel } = {}
local state: Instance
local spin: Spin? = nil
local celebrated = 0 -- the last spin id celebrated
local lastTickAt = 0
local lastAngle: number? = nil
local bannerGui: ScreenGui? = nil
local bannerCard: Instance? = nil

local TreasureWheelController = {}

-- The hint at the button (built in start)
local hintSpot: Attachment
local hintGui: BillboardGui
local hintKey: TextLabel
local hintText: TextLabel
local hintSub: TextLabel
local phoneSpin: TextButton
local phoneAll: TextButton
local nearButton = false

local function rig(container: Instance, reference: CFrame): Rig
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
			table.insert(offsets, reference:ToObjectSpace(descendant.CFrame))
		end
	end
	return { parts = parts, offsets = offsets }
end

local function pose(target: Rig, frame: CFrame)
	local cframes = table.create(#target.parts) :: { CFrame }
	for i, offset in target.offsets do
		cframes[i] = frame * offset
	end
	Workspace:BulkMoveTo(target.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

local function countParts(container: Instance): number
	local count = 0
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

-- The win sound from the sound pack (Config/Sounds): the Legendary stinger for the
-- jackpot, the Rare one otherwise; at the wheel, or on the spinner's screen (nil).
local function jingle(parent: Instance?, jackpot: boolean)
	Sfx.play(if jackpot then "RollLegendary" else "RollRare", { parent = parent, volume = 0.9 })
end

local function readSpin(): Spin?
	local id = state:GetAttribute("SpinId")
	local from = state:GetAttribute("SpinFrom")
	local to = state:GetAttribute("SpinTo")
	local start = state:GetAttribute("SpinStart")
	local duration = state:GetAttribute("SpinDuration")
	if
		typeof(id) ~= "number"
		or id <= 0
		or typeof(from) ~= "number"
		or typeof(to) ~= "number"
		or typeof(start) ~= "number"
		or typeof(duration) ~= "number"
	then
		return nil
	end
	local index = state:GetAttribute("SpinIndex")
	local spinnerId = state:GetAttribute("SpinnerUserId")
	local detail = state:GetAttribute("SpinDetail")
	return {
		id = id,
		from = from,
		to = to,
		start = start,
		duration = duration,
		index = if typeof(index) == "number" then index else 1,
		spinnerId = if typeof(spinnerId) == "number" then spinnerId else 0,
		detail = if typeof(detail) == "string" then detail else "",
	}
end

-- The disc's angle now, and how far through the spin (nil when it's at rest).
local function discAngle(now: number): (number, number?)
	local current = spin
	if current then
		local elapsed = now - current.start
		if elapsed < current.duration then
			local t = math.clamp(elapsed / current.duration, 0, 1)
			return current.from + (current.to - current.from) * (1 - (1 - t) ^ 4), t
		end
		return current.to, nil
	end
	local angle = state:GetAttribute("Angle")
	return if typeof(angle) == "number" then angle else 0, nil
end

-- How far the peg nearest the flapper pushes it, from `u`, the degrees the disc
-- has turned past the last peg: a peg touches it a little before the top, drags
-- it to FLAPPER_MAX two-thirds of the way to the next peg, then slips past.
-- WheelService stops the wheel in the free stretch between (landingAngle).
local function pushed(u: number, spacing: number): number
	local release = spacing * 0.667
	local contact = spacing * 0.88
	local span = spacing * 0.787
	if u <= release then
		return FLAPPER_MAX * (u + spacing * 0.12) / span
	elseif u >= contact then
		return FLAPPER_MAX * (u - contact) / span
	end
	return 0
end

local function stepFlapper(wheel: Wheel, angle: number, dt: number, fast: boolean)
	if fast then
		wheel.flap = FLAPPER_MAX * (0.72 + math.noise(os.clock() * 25, 0.5) * 0.25)
		wheel.flapVelocity = 0
	else
		local target = pushed(angle % wheel.spacing, wheel.spacing)
		local steps = 4
		local h = math.min(dt, 1 / 20) / steps
		for _ = 1, steps do
			wheel.flapVelocity += (-SPRING * wheel.flap - DAMPING * wheel.flapVelocity) * h
			wheel.flap += wheel.flapVelocity * h
			if wheel.flap < target then
				wheel.flap = target
				wheel.flapVelocity = math.max(wheel.flapVelocity, 0)
			end
		end
	end
	if math.abs(wheel.flap - wheel.shownFlap) > 0.05 then
		wheel.shownFlap = wheel.flap
		-- The wheel turns clockwise (seen from the front), carrying the tip to the viewer's right
		pose(wheel.flapper, wheel.pivot * CFrame.Angles(0, 0, -math.rad(wheel.flap)))
	end
end

local function tick(wheel: Wheel)
	local now = os.clock()
	if now - lastTickAt < TICK_GAP or wheel.mount == nil then
		return
	end
	lastTickAt = now
	Sfx.play(
		"Tick",
		{ parent = wheel.mount :: Instance?, volume = 0.55, pitch = 1 + rng:NextNumber() * 0.15 }
	)
end

local function setBulbs(wheel: Wheel, colorOf: (Bulb) -> Color3)
	for _, b in wheel.bulbs do
		b.part.Color = colorOf(b)
	end
end

local function updateBulbs(wheel: Wheel, spinning: boolean)
	local now = os.clock()
	local flashIndex = wheel.flashIndex
	if flashIndex and now < wheel.flashUntil then
		local segment = segments[flashIndex]
		if segment.kind == "skin" then
			-- Jackpot: a rainbow running round every string of bulbs
			setBulbs(wheel, function(b)
				return Color3.fromHSV((now * 0.9 + b.index * 0.045) % 1, 0.65, 1)
			end)
			wheel.bulbKey = -1
			return
		end
		local on = math.floor(now * 6) % 2 == 0
		local key = if on then -2 else -3
		if key ~= wheel.bulbKey then
			wheel.bulbKey = key
			setBulbs(wheel, function()
				return if on then segment.color else BULB_DIM
			end)
		end
		return
	end
	-- A marquee chase, with the wheel's turn; three times as fast while it spins
	local step = math.floor(now * (if spinning then 16 else 5))
	if step == wheel.bulbKey then
		return
	end
	wheel.bulbKey = step
	setBulbs(wheel, function(b)
		if b.group == "Finial" then
			return if step % 2 == 0 then BULB_ON else BULB_DIM
		end
		return if (b.index - step) % 3 == 0 then BULB_ON else BULB_DIM
	end)
end

local function stopFlash(wheel: Wheel)
	if wheel.flashIndex then
		for part, material in wheel.materials do
			part.Material = material
		end
	end
	wheel.flashIndex = nil
	wheel.bulbKey = -4
end

local function updateFlash(wheel: Wheel)
	local index = wheel.flashIndex
	if index == nil then
		return
	end
	local now = os.clock()
	if now >= wheel.flashUntil then
		stopFlash(wheel)
		return
	end
	local lit = math.floor(now * 5) % 2 == 0
	local pieces: { BasePart } = wheel.slices[index] or {}
	for _, piece in pieces do
		piece.Material = if lit then Enum.Material.Neon else wheel.materials[piece]
	end
end

local function showBanner(current: Spin)
	local segment = segments[current.index]
	if segment == nil then
		return
	end
	if bannerGui == nil then
		bannerGui = Ui.screen("WheelResult", player:WaitForChild("PlayerGui"), 15)
	end
	if bannerCard then
		bannerCard:Destroy()
	end
	local jackpot = segment.kind == "skin"
	local group = Instance.new("CanvasGroup")
	group.AnchorPoint = Vector2.new(0.5, 0)
	group.Position = UDim2.new(0.5, 0, 0, math.max(84, Ui.bossBottom() + 60))
	group.Size = UDim2.fromOffset(540, 150)
	group.BackgroundTransparency = 1
	local pop = Instance.new("UIScale")
	pop.Scale = 0.35
	pop.Parent = group
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(510, 128)
	card.BackgroundColor3 = segment.color:Lerp(Color3.new(0, 0, 0), if jackpot then 0.35 else 0.6)
	card.Parent = group
	Ui.corner(card, UDim.new(0, 18))
	Ui.stroke(card, Color3.fromRGB(255, 214, 90), 0, 3)
	local kicker = Ui.label(
		card,
		"Kicker",
		if jackpot then "TREASURE WHEEL · JACKPOT!" else "TREASURE WHEEL",
		Ui.FONT_HEAVY,
		16,
		Color3.fromRGB(255, 214, 90),
		UDim2.new(1, -40, 0, 22),
		UDim2.fromOffset(20, 12)
	)
	kicker.TextXAlignment = Enum.TextXAlignment.Left
	local title = Ui.label(
		card,
		"Title",
		`YOU WON {segment.label}!`,
		Ui.FONT_HEAVY,
		30,
		Ui.color.text,
		UDim2.new(1, -40, 0, 40),
		UDim2.fromOffset(20, 36)
	)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local detail = Ui.label(
		card,
		"Detail",
		current.detail,
		Ui.FONT_BOLD,
		17,
		Color3.fromRGB(255, 236, 190),
		UDim2.new(1, -40, 0, 26),
		UDim2.fromOffset(20, 84)
	)
	detail.TextXAlignment = Enum.TextXAlignment.Left
	group.Parent = bannerGui
	bannerCard = group
	TweenService
		:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	task.delay(BANNER_SECONDS, function()
		if bannerCard ~= group then
			return
		end
		local fade = TweenService:Create(group, TweenInfo.new(0.4), {
			GroupTransparency = 1,
			Position = group.Position - UDim2.fromOffset(0, 24),
		})
		fade:Play()
		fade.Completed:Once(function()
			group:Destroy()
		end)
	end)
end

local function celebrate(current: Spin)
	local segment = segments[current.index]
	if segment == nil then
		return
	end
	local jackpot = segment.kind == "skin"
	local heard = false
	for _, wheel in wheels do
		stopFlash(wheel)
		wheel.flashIndex = current.index
		wheel.flashUntil = os.clock() + (if jackpot then FLASH_SECONDS * 1.6 else FLASH_SECONDS)
		for _, emitter in wheel.emitters do
			emitter:Emit(if jackpot then 45 else 16)
		end
		if wheel.mount then
			jingle(wheel.mount, jackpot)
			heard = true
		end
	end
	if current.spinnerId == player.UserId then
		showBanner(current)
		if not heard then
			jingle(nil, jackpot)
		end
	end
end

local function pressButton(wheel: Wheel)
	local button, rest = wheel.button, wheel.buttonRest
	if button == nil or rest == nil then
		return
	end
	local down = TweenService:Create(button, TweenInfo.new(0.08), { CFrame = rest * CFrame.new(-0.2, 0, 0) })
	down:Play()
	down.Completed:Once(function()
		TweenService:Create(button, TweenInfo.new(0.18), { CFrame = rest }):Play()
	end)
end

local function onSpin()
	spin = readSpin()
	local current = spin
	if current == nil then
		return
	end
	for _, wheel in wheels do
		stopFlash(wheel)
		wheel.posedRest = false
		wheel.lastPeg = math.floor(current.from / wheel.spacing)
		pressButton(wheel)
	end
	lastAngle = nil
end

local function bind(instance: Instance)
	if not instance:IsA("Model") or wheels[instance] then
		return
	end
	local model = instance :: Model
	-- The model streams in whole (Atomic), but wait until every piece is here anyway
	local disc: Instance?, flapper: Instance?
	local deadline = os.clock() + 15
	while model.Parent and os.clock() < deadline do
		disc = model:FindFirstChild("WheelDisc")
		flapper = model:FindFirstChild("Flapper")
		if
			disc
			and flapper
			and countParts(disc) >= (disc:GetAttribute("Parts") or 1) :: number
			and countParts(flapper) >= (flapper:GetAttribute("Parts") or 1) :: number
		then
			break
		end
		disc = nil
		task.wait(0.2)
	end
	local base = model:GetAttribute("BaseCFrame")
	local pivot = if flapper then flapper:GetAttribute("PivotCFrame") else nil
	local hub = if disc then disc:FindFirstChild("Hub") else nil
	if
		disc == nil
		or flapper == nil
		or model.Parent == nil
		or typeof(base) ~= "CFrame"
		or typeof(pivot) ~= "CFrame"
		or hub == nil
		or not hub:IsA("BasePart")
	then
		return
	end
	local pegs = model:GetAttribute("Pegs")
	local spacing = 360 / (if typeof(pegs) == "number" and pegs > 0 then pegs else 24)

	local wheel: Wheel = {
		model = model,
		base = base,
		spacing = spacing,
		-- Offsets from the wheel's center as the server left it (the hub's pivot)
		disc = rig(disc, hub.CFrame * hub.PivotOffset),
		flapper = rig(flapper, pivot),
		pivot = pivot,
		flap = 0,
		flapVelocity = 0,
		shownFlap = 0,
		posedRest = false,
		bulbs = {},
		bulbKey = -4,
		slices = {},
		materials = {},
		flashIndex = nil,
		flashUntil = 0,
		emitters = {},
		lastPeg = math.floor(discAngle(Workspace:GetServerTimeNow()) / spacing),
		mount = nil,
		button = nil,
		buttonRest = nil,
	}
	for _, piece in disc:GetDescendants() do
		local index = piece:GetAttribute("Slice")
		if piece:IsA("BasePart") and typeof(index) == "number" then
			wheel.slices[index] = wheel.slices[index] or {}
			table.insert(wheel.slices[index], piece)
			wheel.materials[piece] = piece.Material
		end
	end
	local bulbs = model:FindFirstChild("Bulbs")
	if bulbs then
		for _, b in bulbs:GetChildren() do
			local group, index = b:GetAttribute("Group"), b:GetAttribute("Index")
			if b:IsA("BasePart") and typeof(group) == "string" and typeof(index) == "number" then
				table.insert(wheel.bulbs, { part = b, group = group, index = index })
			end
		end
	end
	local mount = model:FindFirstChild("FlapperMount")
	if mount and mount:IsA("BasePart") then
		wheel.mount = mount
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.new(0, 0, -0.8)
		attachment.Parent = mount
		for _, color in CONFETTI do
			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = CONFETTI_TEXTURE
			emitter.Color = ColorSequence.new(color)
			emitter.LightEmission = 0.4
			emitter.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(1, 0.25),
			})
			emitter.Lifetime = NumberRange.new(2.2, 3.2)
			emitter.Speed = NumberRange.new(16, 28)
			emitter.SpreadAngle = Vector2.new(65, 40)
			emitter.Acceleration = Vector3.new(0, -24, 0)
			emitter.Drag = 1.2
			emitter.Rotation = NumberRange.new(0, 360)
			emitter.RotSpeed = NumberRange.new(-240, 240)
			emitter.EmissionDirection = Enum.NormalId.Front
			emitter.Rate = 0
			emitter.Parent = attachment
			table.insert(wheel.emitters, emitter)
		end
	end
	local button = model:FindFirstChild("SpinButton")
	if button and button:IsA("BasePart") then
		wheel.button = button
		wheel.buttonRest = button.CFrame
	end
	wheels[model] = wheel
end

-- The hint at the big red button (no ProximityPrompts: they never worked for the
-- fish characters). The button's place comes from WheelState, so it shows even
-- before the wheel has streamed in.
local function buildHint(playerGui: Instance)
	hintSpot = Instance.new("Attachment")
	hintSpot.Name = "WheelHint"
	hintSpot.Parent = workspace.Terrain
	hintGui = Instance.new("BillboardGui")
	hintGui.Name = "WheelHint"
	hintGui.Adornee = hintSpot
	hintGui.Size = UDim2.fromOffset(280, 64)
	hintGui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	hintGui.AlwaysOnTop = true
	hintGui.LightInfluence = 0
	hintGui.Enabled = false
	hintGui.ResetOnSpawn = false
	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.Size = UDim2.new(1, 0, 0, 44)
	chip.BackgroundColor3 = Ui.color.panel
	chip.BackgroundTransparency = 0.15
	Ui.corner(chip, UDim.new(1, 0))
	Ui.stroke(chip, Color3.fromRGB(255, 214, 90), 0.2, 1.5)
	chip.Parent = hintGui
	local key = Instance.new("Frame")
	key.Name = "Key"
	key.AnchorPoint = Vector2.new(0, 0.5)
	key.Position = UDim2.new(0, 6, 0.5, 0)
	key.Size = UDim2.fromOffset(34, 34)
	key.BackgroundColor3 = Color3.fromRGB(255, 214, 90)
	Ui.corner(key, UDim.new(1, 0))
	key.Parent = chip
	hintKey = Ui.label(key, "Text", "E", Ui.FONT_HEAVY, 18, Ui.color.panel, UDim2.fromScale(1, 1))
	hintKey.TextXAlignment = Enum.TextXAlignment.Center
	hintText = Ui.label(chip, "Text", "", Ui.FONT_BOLD, 16, Ui.color.text, UDim2.new(1, -54, 1, 0))
	hintText.Position = UDim2.fromOffset(48, 0)
	hintSub = Ui.label(hintGui, "Sub", "", Ui.FONT_SEMI, 13, Ui.color.text, UDim2.new(1, 0, 0, 18))
	hintSub.Position = UDim2.fromOffset(0, 46)
	hintSub.TextXAlignment = Enum.TextXAlignment.Center
	hintSub.TextStrokeTransparency = 0.4
	hintGui.Parent = playerGui
	-- Phones: SPIN and ALL where the stall button goes
	local buttons = Ui.screen("WheelButtons", playerGui, 9)
	phoneSpin =
		Ui.button(buttons, "Spin", "SPIN", UDim2.fromOffset(160, 44), UDim2.new(1, -96, 1, -204), "gold")
	phoneSpin.AnchorPoint = Vector2.new(1, 1)
	phoneSpin.Selectable = false
	phoneSpin.Visible = false
	phoneSpin.Activated:Connect(function()
		ClientState.request("SpinWheel", false)
	end)
	phoneAll =
		Ui.button(buttons, "All", "ALL", UDim2.fromOffset(64, 44), UDim2.new(1, -264, 1, -204), "secondary")
	phoneAll.AnchorPoint = Vector2.new(1, 1)
	phoneAll.Selectable = false
	phoneAll.Visible = false
	phoneAll.Activated:Connect(function()
		ClientState.request("SpinWheel", true)
	end)
end

local function updateHint()
	local at = state:GetAttribute("ButtonPosition")
	local root = SwimController.root()
	local near = typeof(at) == "Vector3"
		and root ~= nil
		and (root.Position - at).Magnitude <= Wheel.reach
		and not MenuController.isOpen()
		and not StartController.isUp()
	nearButton = near == true
	local touch = Input.isTouch()
	hintGui.Enabled = nearButton and not touch
	local current = ClientState.current
	local wheelState = if current and typeof(current.wheel) == "table" then current.wheel else {}
	local spins: number = if typeof(wheelState.spins) == "number" then wheelState.spins else 0
	local nextFreeAt: number = if typeof(wheelState.nextFreeAt) == "number" then wheelState.nextFreeAt else 0
	phoneSpin.Visible = nearButton and touch
	phoneAll.Visible = nearButton and touch and spins >= 2
	if not nearButton then
		return
	end
	local queued = state:GetAttribute("Queue")
	local active = spin
	local busy = (typeof(queued) == "number" and queued > 0)
		or (active ~= nil and Workspace:GetServerTimeNow() < active.start + active.duration + 2)
	local text: string
	if spins <= 0 then
		text = "NO SPINS LEFT"
	else
		text = if busy then `JOIN THE LINE ({spins})` else `SPIN ({spins})`
	end
	local free = if nextFreeAt > 0
		then `next free spin in {Format.duration(math.max(0, nextFreeAt - Workspace:GetServerTimeNow()))}`
		else "free spins are full: spin one!"
	if typeof(at) == "Vector3" then
		hintSpot.WorldPosition = at
	end
	hintKey.Text = if Input.isGamepad() then "Y" else "E"
	hintText.Text = text
	hintSub.Text = if spins >= 2 and not Input.isGamepad() then `T · SPIN ALL   ·   {free}` else free
	phoneSpin.Text = if spins <= 0 then "NO SPINS" else `SPIN ({spins})`
end

function TreasureWheelController.start()
	state = ReplicatedStorage:WaitForChild("WheelState")
	buildHint(player:WaitForChild("PlayerGui"))
	-- E / Y spins, T spins all, at the button only (after the stall hint's binding, so
	-- this one is asked first and passes when it's not ours)
	ContextActionService:BindAction("ApexWheel", function(_, inputState, input)
		if inputState ~= Enum.UserInputState.Begin or not nearButton then
			return Enum.ContextActionResult.Pass
		end
		ClientState.request("SpinWheel", input.KeyCode == Enum.KeyCode.T)
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonY, Enum.KeyCode.T)
	spin = readSpin()
	local current = spin
	if current and Workspace:GetServerTimeNow() >= current.start + current.duration then
		celebrated = current.id -- over before we joined
	end
	state:GetAttributeChangedSignal("SpinId"):Connect(onSpin)

	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance)
		task.spawn(bind, instance)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance)
		if instance:IsA("Model") then
			wheels[instance] = nil
		end
	end)
	for _, instance in CollectionService:GetTagged(TAG) do
		task.spawn(bind, instance)
	end

	RunService.RenderStepped:Connect(function(dt)
		local now = Workspace:GetServerTimeNow()
		local angle, t = discAngle(now)
		local spinning = t ~= nil
		local speed = if lastAngle then math.abs(angle - lastAngle) / math.max(dt, 1 / 240) else 0
		lastAngle = angle
		for model, wheel in wheels do
			if model.Parent == nil then
				wheels[model] = nil
				continue
			end
			if spinning or not wheel.posedRest then
				pose(wheel.disc, wheel.base * CFrame.Angles(0, 0, math.rad(angle)))
				wheel.posedRest = not spinning
			end
			stepFlapper(wheel, angle, dt, speed / wheel.spacing > FAST_PEGS)
			local peg = math.floor(angle / wheel.spacing)
			if peg ~= wheel.lastPeg then
				wheel.lastPeg = peg
				if spinning then
					tick(wheel)
				end
			end
			updateFlash(wheel)
			updateBulbs(wheel, spinning)
		end
		local active = spin
		if active and celebrated < active.id and now >= active.start + active.duration then
			celebrated = active.id
			celebrate(active)
		end
	end)

	task.spawn(function()
		while true do
			updateHint()
			task.wait(0.2)
		end
	end)
end

return TreasureWheelController
