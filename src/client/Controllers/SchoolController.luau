--!strict
-- Draws the NPC prey and eats them. Every fish follows its shared path
-- (Shared/Schools.luau), so this client moves its own copies each frame with
-- BulkMoveTo and nothing is sent over the network but eats.
--
-- Eating feels instant: when a small-enough fish is in reach of our mouth it's
-- sucked in on this client straight away, and the eat goes to the server in a
-- small batch. If the server doesn't confirm it within a moment, the fish comes
-- back. Fish other players ate vanish with a puff and return when they respawn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Schools = require(ReplicatedStorage.Shared.Schools)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Size = require(ReplicatedStorage.Shared.Size)
local SwimWave = require(ReplicatedStorage.Shared.SwimWave)
local Timing = require(ReplicatedStorage.Shared.Timing)
local ClientState = require(script.Parent.Parent.ClientState)
local SwimController = require(script.Parent.SwimController)

local SchoolController = {
	-- (preyId, mass, position) — we ate a prey fish (HUD pops a number)
	ate = Signal.new(),
	-- (preyId) — a prey fish too big to swallow is at our mouth (at most once a second)
	tooBig = Signal.new(),
}

local lastTooBig = 0

local DRAW_DISTANCE = 520 -- schools further than this from the camera aren't moved
-- Static GLB prey meshes came in facing +Z (owner, 2026-10-07: "swimming backwards");
-- they're turned round when drawn. Rigged FBX bodies face -Z already.
local MESH_FLIP = CFrame.Angles(0, math.pi, 0)
local SUCK_SECONDS = 0.14
local CONFIRM_SECONDS = 1.2
local SEND_INTERVAL = 0.06

type Visual = {
	body: BasePart,
	tail: BasePart?, -- the part body's tail fin (a mesh body has none)
	model: Model?, -- a rigged body (its primary MeshPart is `body`); its bones swim
	bones: { [string]: Bone },
	spine: { string },
	unitScale: number, -- the rigged model's scale at full size
	phase: number, -- the swim wave
	flip: boolean, -- a static mesh that came in facing +Z
	bodySize: Vector3,
	tailSize: Vector3,
	hidden: boolean,
	backAt: number, -- clock when it shows again (0 = shown)
	pendingUntil: number, -- our unconfirmed eat
	suckFrom: CFrame?, -- the suction animation's start
	suckStart: number,
	fadeIn: number, -- 0..1 after respawning
	-- A chase (AggroService): this fish darts at a player and back
	chase: { target: Player, startAt: number, endsAt: number, glow: Highlight }?,
}

local visuals: { Visual } = {}
local parts: { BasePart } = {}
local frames: { CFrame } = {}
local batch: { { number } } = {}
local lastSend = 0
local aggro = Config.Tuning.aggro
local chaseWarning: TextLabel? = nil
local chaseWarningUntil = 0

local function makePart(parent: Instance, color: Color3, shape: "Ellipsoid" | "Fin"): Part
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
	if shape == "Fin" then
		part.Reflectance = 0.05
	end
	return part
end

-- The imported prey (docs/ASSETS.md): ReplicatedStorage.PreyModels.<PreyId>, a rigged
-- Model (bones swim it) or an older static MeshPart. Nothing while it isn't
-- imported (the ellipsoid is drawn).
local function preyTemplate(preyId: string): (MeshPart?, Model?)
	local folder = ReplicatedStorage:FindFirstChild("PreyModels")
	local template = folder and folder:FindFirstChild(preyId)
	if template and template:IsA("MeshPart") then
		return template, nil
	end
	if template and template:IsA("Model") then
		local mesh = template:FindFirstChildWhichIsA("MeshPart", true)
		if mesh and template:FindFirstChildWhichIsA("Bone", true) then
			return mesh, template
		end
		return mesh, nil
	end
	return nil, nil
end

local function bonesOf(model: Model): ({ [string]: Bone }, { string })
	local bones: { [string]: Bone } = {}
	local spine: { string } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Bone") then
			bones[descendant.Name] = descendant
		end
	end
	local i = 1
	while bones[`Spine{i}`] do
		table.insert(spine, `Spine{i}`)
		i += 1
	end
	if bones.Tail then
		table.insert(spine, "Tail")
	end
	return bones, spine
end

local function build()
	local folder = Instance.new("Folder")
	folder.Name = "Prey"
	for index, fish in Schools.fish do
		local prey = Config.Prey.byId[fish.prey]
		local length = fish.length
		local bodySize = Vector3.new(length * prey.slim * 0.8, length * prey.slim, length * 0.78)
		local tailSize = Vector3.new(length * 0.03, length * prey.slim * 1.1, length * 0.26)
		local template, rigged = preyTemplate(prey.id)
		local body: BasePart
		local tail: BasePart? = nil
		local model: Model? = nil
		local bones: { [string]: Bone } = {}
		local spine: { string } = {}
		local unitScale = 1
		local flip = false
		if rigged then
			-- A rigged body: anchored, scaled to the fish's length, its bones swim
			local clone = rigged:Clone()
			for _, descendant in clone:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
					descendant.CanCollide = false
					descendant.CanQuery = false
					descendant.CanTouch = false
					descendant.CastShadow = false
				end
			end
			clone:ScaleTo(1)
			unitScale = length / math.max(clone:GetExtentsSize().Z, 0.01)
			clone:ScaleTo(unitScale)
			clone:PivotTo(CFrame.new())
			clone:PivotTo(CFrame.new(-clone:GetBoundingBox().Position))
			local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("MeshPart", true)
			clone.PrimaryPart = primary
			bodySize = clone:GetExtentsSize()
			bones, spine = bonesOf(clone)
			clone.Parent = folder
			model = clone
			body = primary :: BasePart
		elseif template then
			local mesh = template:Clone()
			mesh.Anchored = true
			mesh.CanCollide = false
			mesh.CanQuery = false
			mesh.CanTouch = false
			mesh.CastShadow = false
			bodySize = template.Size * (length / math.max(template.Size.Z, 0.01))
			mesh.Size = bodySize
			mesh.Parent = folder
			body = mesh
			flip = SwimWave.needsFlip(template)
		else
			body = makePart(folder, prey.back, "Ellipsoid")
			body.Size = bodySize
			local fin = makePart(folder, prey.back:Lerp(prey.belly, 0.3), "Fin")
			fin.Name = "Tail"
			fin.Size = tailSize
			tail = fin
		end
		body.Name = prey.id
		visuals[index] = {
			body = body,
			tail = tail,
			bodySize = bodySize,
			tailSize = tailSize,
			hidden = false,
			backAt = 0,
			pendingUntil = 0,
			suckFrom = nil,
			suckStart = 0,
			fadeIn = 1,
			model = model,
			bones = bones,
			spine = spine,
			unitScale = unitScale,
			phase = fish.phase * 3,
			flip = flip,
			chase = nil,
		}
	end
	folder.Parent = workspace
end

local function setHidden(visual: Visual, hidden: boolean)
	if visual.hidden == hidden then
		return
	end
	visual.hidden = hidden
	local transparency = if hidden then 1 else 0
	if visual.model then
		for _, descendant in (visual.model :: Model):GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Transparency = transparency
			end
		end
	else
		visual.body.Transparency = transparency
	end
	if visual.tail then
		visual.tail.Transparency = transparency
	end
	if not hidden then
		if visual.model then
			(visual.model :: Model):ScaleTo(visual.unitScale)
		else
			visual.body.Size = visual.bodySize
		end
		if visual.tail then
			visual.tail.Size = visual.tailSize
		end
		visual.fadeIn = 0
	end
end

local function flush(now: number)
	if #batch == 0 or now - lastSend < SEND_INTERVAL then
		return
	end
	lastSend = now
	ClientState.request("EatPrey", batch)
	batch = {}
end

local function step(dt: number)
	local now = Timing.clock()
	local camera = workspace.CurrentCamera.CFrame.Position
	local root = SwimController.root()
	local length = SwimController.length()
	local mouth: Vector3? = nil
	local reach = Size.reach(length)
	local inHub = false
	if root then
		mouth = root.CFrame:PointToWorldSpace(Size.mouthOffset(length))
		local character = SwimController.character()
		inHub = character ~= nil and character:GetAttribute("InHub") == true
	end

	table.clear(parts)
	table.clear(frames)
	for schoolIndex, school in Schools.list do
		if (school.center - camera).Magnitude > DRAW_DISTANCE + school.radius then
			continue
		end
		local schoolFrame = Schools.schoolFrame(schoolIndex, now)
		for index = school.first, school.first + school.count - 1 do
			local fish = Schools.fish[index]
			local visual = visuals[index]
			-- Respawned, or our eat wasn't confirmed: show it again
			if visual.hidden and visual.suckFrom == nil then
				if visual.pendingUntil > 0 and now > visual.pendingUntil then
					visual.pendingUntil = 0
					visual.backAt = 0
				end
				if visual.pendingUntil == 0 and now >= visual.backAt then
					setHidden(visual, false)
				end
			end
			local frame = Schools.fishFrame(index, schoolFrame, now)
			-- Chasing: it darts off its path at the player and comes back
			local chase = visual.chase
			if chase then
				local character = chase.target.Character
				local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
				if now >= chase.endsAt or targetRoot == nil or not targetRoot:IsA("BasePart") then
					chase.glow:Destroy()
					visual.chase = nil
				else
					local targetLength = character and character:GetAttribute("Length")
					local blend = Schools.chaseBlend(now - chase.startAt, aggro.seconds, aggro.lungeAt)
					local at = Schools.chasePosition(
						index,
						frame.Position,
						targetRoot.Position,
						if typeof(targetLength) == "number" then targetLength else 2,
						blend
					)
					local toward = targetRoot.Position - at
					if toward.Magnitude > 1e-3 and blend > 0.02 then
						local face = CFrame.lookAt(at, at + toward)
						frame = frame.Rotation:Lerp(face.Rotation, math.min(blend * 1.5, 1)) + at
					else
						frame = frame.Rotation + at
					end
					chase.glow.FillTransparency = 0.6 + 0.3 * (1 - blend)
				end
			end
			if visual.suckFrom then
				-- Sucked into our mouth: slide in and shrink, then vanish
				local alpha = math.clamp((now - visual.suckStart) / SUCK_SECONDS, 0, 1)
				local target = mouth or frame.Position
				local from = visual.suckFrom :: CFrame
				frame = CFrame.new(from.Position:Lerp(target, alpha * alpha)) * from.Rotation
				local shrink = 1 - alpha * 0.85
				if visual.model then
					(visual.model :: Model):ScaleTo(visual.unitScale * shrink)
				else
					visual.body.Size = visual.bodySize * shrink
				end
				if visual.tail then
					visual.tail.Size = visual.tailSize * shrink
				end
				if alpha >= 1 then
					visual.suckFrom = nil
					setHidden(visual, true)
				end
			elseif not visual.hidden then
				if visual.fadeIn < 1 then
					visual.fadeIn = math.min(1, visual.fadeIn + dt * 2.5)
					local grow = 0.3 + 0.7 * visual.fadeIn
					if visual.model then
						(visual.model :: Model):ScaleTo(visual.unitScale * grow)
					else
						visual.body.Size = visual.bodySize * grow
					end
					if visual.tail then
						visual.tail.Size = visual.tailSize * grow
					end
				end
				-- Eat it if it's in reach and small enough
				local inReach = mouth ~= nil
					and not inHub
					and (frame.Position - (mouth :: Vector3)).Magnitude <= reach + fish.radius
				if inReach and not Size.canSwallow(length, fish.length) then
					if now - lastTooBig > 1 then
						lastTooBig = now
						SchoolController.tooBig:fire(fish.prey)
					end
				elseif inReach then
					visual.suckFrom = frame
					visual.suckStart = now
					visual.pendingUntil = now + CONFIRM_SECONDS
					visual.backAt = math.huge
					table.insert(batch, { index, now })
					local prey = Config.Prey.byId[fish.prey]
					SchoolController.ate:fire(prey.id, prey.mass, frame.Position)
				end
			end
			if not visual.hidden then
				local beat = math.sin(now * (6 + fish.phase) + fish.phase * 4) * 0.55
				table.insert(parts, visual.body)
				local tail = visual.tail
				if visual.model then
					-- A rigged body: the head holds still and the wave runs down the spine
					-- (Shared/SwimWave), faster for the quick little ones
					local prey = Config.Prey.byId[fish.prey]
					visual.phase += dt * 2 * math.pi * (0.9 + prey.speed * 0.22)
					SwimWave.applyBones(visual.bones, visual.spine, visual.phase, 0.34, 0)
					table.insert(frames, frame)
				elseif tail then
					table.insert(frames, frame)
					table.insert(parts, tail)
					table.insert(
						frames,
						frame
							* CFrame.new(0, 0, visual.body.Size.Z * 0.45)
							* CFrame.Angles(0, beat, 0)
							* CFrame.new(0, 0, tail.Size.Z * 0.4)
					)
				else
					-- A one-piece static mesh: a small yaw wiggle about its head, turned round
					table.insert(
						frames,
						frame
							* CFrame.new(0, 0, -visual.body.Size.Z * 0.3)
							* CFrame.Angles(0, beat * 0.22, 0)
							* CFrame.new(0, 0, visual.body.Size.Z * 0.3)
							* (if visual.flip then MESH_FLIP else CFrame.identity)
					)
				end
			end
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	flush(now)
end

-- The server says a fish turned on a player (AggroService): it darts at them.
local function onPreyChase(index: number, targetUserId: number, startAt: number, seconds: number)
	local visual = visuals[index]
	local target = Players:GetPlayerByUserId(targetUserId)
	if visual == nil or target == nil or visual.hidden then
		return
	end
	if visual.chase then
		visual.chase.glow:Destroy()
	end
	local glow = Instance.new("Highlight")
	glow.Name = "ChaseGlow"
	glow.FillColor = Ui.color.danger
	glow.FillTransparency = 0.9
	glow.OutlineColor = Ui.color.danger
	glow.OutlineTransparency = 0.2
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Adornee = visual.body
	glow.Parent = visual.body
	visual.chase = { target = target, startAt = startAt, endsAt = startAt + seconds, glow = glow }
	if target == Players.LocalPlayer and chaseWarning then
		local prey = Config.Prey.byId[Schools.fish[index].prey]
		chaseWarning.Text = `{string.upper(prey.name)} · TOO BIG TO EAT · SWIM!`
		Sfx.play("TooBig", { volume = 0.5 })
		chaseWarningUntil = Timing.clock() + aggro.lungeAt + 0.4
	end
end

-- The server says a fish was eaten (by anyone) and when it comes back.
local function onPreyEaten(index: number, backAt: number, eaterUserId: number)
	local visual = visuals[index]
	if visual == nil then
		return
	end
	visual.backAt = backAt
	visual.pendingUntil = 0
	if eaterUserId == Players.LocalPlayer.UserId then
		local length = Schools.fish[index].length
		Sfx.play("Chomp", {
			volume = math.clamp(0.25 + length * 0.04, 0.25, 0.7),
			pitch = math.clamp(1.5 - length * 0.08, 0.7, 1.5),
		})
	end
	if eaterUserId ~= Players.LocalPlayer.UserId and visual.suckFrom == nil then
		setHidden(visual, true)
	end
end

function SchoolController.start()
	build()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local preyEaten = remotes:WaitForChild("PreyEaten") :: RemoteEvent
	preyEaten.OnClientEvent:Connect(onPreyEaten)
	local preyChase = remotes:WaitForChild("PreyChase") :: RemoteEvent
	preyChase.OnClientEvent:Connect(onPreyChase)
	-- The warning when one turns on us
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Ui.screen("Chase", playerGui, 6)
	local label = Ui.label(
		gui,
		"Warning",
		"",
		Ui.FONT_HEAVY,
		18,
		Ui.color.danger,
		UDim2.new(1, 0, 0, 26),
		UDim2.new(0, 0, 0.5, -90)
	)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextStrokeTransparency = 0.4
	label.Visible = false
	chaseWarning = label
	RunService.RenderStepped:Connect(function()
		label.Visible = chaseWarningUntil > Timing.clock()
	end)
	-- Fish already eaten when we joined
	local getEaten = remotes:WaitForChild("GetEaten") :: RemoteFunction
	task.spawn(function()
		local ok, eaten = pcall(function()
			return getEaten:InvokeServer()
		end)
		if ok and typeof(eaten) == "table" then
			for key, backAt in eaten do
				local index = tonumber(key)
				if index and typeof(backAt) == "number" then
					onPreyEaten(index, backAt, 0)
				end
			end
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return SchoolController
