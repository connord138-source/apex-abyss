--!strict
-- The world boss on this client (Config/Bosses, BossService): the event countdown
-- when one is about to rise, the boss bar (name, phase, health, stagger meter, the
-- Last stand clock) while it's near, the dread as it closes in (the water darkens
-- and beats like a heart, a NEARBY warning points at it, the camera shakes as it
-- passes) and the reward card when it dies. PredatorController draws the body.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local AmbienceController = require(script.Parent.AmbienceController)
local Sfx = require(script.Parent.Parent.Sfx)
local Format = require(ReplicatedStorage.Shared.Format)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Ui = require(script.Parent.Parent.Ui)
local CameraController = require(script.Parent.CameraController)
local OceanController = require(script.Parent.OceanController)
local PredatorController = require(script.Parent.PredatorController)
local RollController = require(script.Parent.RollController)
local SwimController = require(script.Parent.SwimController)

local Bosses = Config.Bosses

local BossController = {}

local gui: ScreenGui
local bar: Frame
local nameLabel: TextLabel
local phaseLabel: TextLabel
local healthFill: Frame
local meterFill: Frame
local countdown: Frame
local countdownLabel: TextLabel
local nearby: Frame
local nearbyLabel: TextLabel
local nearbyArrow: TextLabel

local state: { [string]: any } = { state = "gone" }
local lastShake = 0
local barAlpha = 0

local PHASES = { "HUNTING", "FRENZY", "LAST STAND" }

local function clockText(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function buildBar()
	bar = Ui.panel(gui, "Boss", UDim2.fromOffset(460, 62), UDim2.new(0.5, 0, 0, 52), Vector2.new(0.5, 0))
	local stroke = bar:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Ui.color.danger
		stroke.Transparency = 0.4
	end
	nameLabel = Ui.label(
		bar,
		"Name",
		"",
		Ui.FONT_HEAVY,
		17,
		Ui.color.danger,
		UDim2.new(1, -24, 0, 22),
		UDim2.fromOffset(12, 6)
	)
	phaseLabel = Ui.label(
		bar,
		"Phase",
		"",
		Ui.FONT_BOLD,
		13,
		Ui.color.text,
		UDim2.new(1, -24, 0, 18),
		UDim2.fromOffset(12, 6)
	)
	phaseLabel.TextXAlignment = Enum.TextXAlignment.Right
	local _, health =
		Ui.bar(bar, "Health", UDim2.new(1, -24, 0, 8), UDim2.fromOffset(12, 34), Ui.color.danger)
	healthFill = health
	local _, meter = Ui.bar(bar, "Stagger", UDim2.new(1, -24, 0, 4), UDim2.fromOffset(12, 48), Ui.color.haul)
	meterFill = meter
	meterFill.Size = UDim2.fromScale(0, 1)
	bar.Visible = false

	countdown =
		Ui.panel(gui, "Countdown", UDim2.fromOffset(360, 34), UDim2.new(0.5, 0, 0, 52), Vector2.new(0.5, 0))
	countdownLabel = Ui.label(
		countdown,
		"Text",
		"",
		Ui.FONT_BOLD,
		14,
		Ui.color.danger,
		UDim2.new(1, -20, 1, 0),
		UDim2.fromOffset(10, 0)
	)
	countdownLabel.TextXAlignment = Enum.TextXAlignment.Center
	countdownLabel.TextYAlignment = Enum.TextYAlignment.Center
	countdown.Visible = false

	nearby =
		Ui.panel(gui, "Nearby", UDim2.fromOffset(250, 40), UDim2.new(0.5, 0, 0.5, -170), Vector2.new(0.5, 0))
	nearby.BackgroundTransparency = 0.5
	nearbyArrow = Ui.label(
		nearby,
		"Arrow",
		"▲",
		Ui.FONT_HEAVY,
		22,
		Ui.color.danger,
		UDim2.fromOffset(30, 40),
		UDim2.fromOffset(8, 0)
	)
	nearbyArrow.TextXAlignment = Enum.TextXAlignment.Center
	nearbyArrow.TextYAlignment = Enum.TextYAlignment.Center
	nearbyLabel = Ui.label(
		nearby,
		"Text",
		"",
		Ui.FONT_BOLD,
		14,
		Ui.color.danger,
		UDim2.new(1, -50, 1, 0),
		UDim2.fromOffset(44, 0)
	)
	nearbyLabel.TextYAlignment = Enum.TextYAlignment.Center
	nearby.Visible = false
end

-- The reward card: what the kill paid, then the shade reveal if there was one
local function rewardCard(summary: { [string]: any })
	local holder = Instance.new("Frame")
	holder.Name = "BossReward"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.36)
	holder.Size = UDim2.fromOffset(700, 180)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = holder
	local name = if typeof(summary.name) == "string" then summary.name else "BOSS"
	local title = Ui.label(
		holder,
		"Title",
		`{string.upper(name)} SLAIN`,
		Ui.FONT_HEAVY,
		48,
		Ui.color.danger,
		UDim2.new(1, 0, 0, 54)
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextStrokeTransparency = 0.5
	local lines = {}
	if typeof(summary.teeth) == "number" then
		local currency = if typeof(summary.currencyName) == "string" then summary.currencyName else "Teeth"
		table.insert(lines, `+{summary.teeth} {string.upper(currency)}`)
	end
	if typeof(summary.haul) == "number" then
		table.insert(lines, `+{string.format("%.1f", summary.haul)} kg HAUL · carry it home`)
	end
	if typeof(summary.coral) == "number" then
		table.insert(lines, `+{Ui.number(summary.coral)} CORAL`)
	end
	local sub = Ui.label(
		holder,
		"Sub",
		table.concat(lines, "   ·   "),
		Ui.FONT_BOLD,
		20,
		Ui.color.haul,
		UDim2.new(1, 0, 0, 26),
		UDim2.fromOffset(0, 58)
	)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.TextStrokeTransparency = 0.6
	local extra = {}
	if typeof(summary.trophy) == "string" then
		local shade = Config.Shades.byId[summary.trophy]
		table.insert(
			extra,
			`TROPHY WON · {string.upper(if shade then shade.name else summary.trophy)} SHADE`
		)
	end
	if typeof(summary.title) == "string" then
		table.insert(extra, `TITLE · {string.upper(summary.title)}`)
	end
	if typeof(summary.rank) == "number" then
		table.insert(extra, `#{summary.rank} damage · {math.floor((summary.share or 0) * 100 + 0.5)}%`)
	end
	local third = Ui.label(
		holder,
		"Extra",
		table.concat(extra, "   ·   "),
		Ui.FONT_BOLD,
		17,
		Ui.color.text,
		UDim2.new(1, 0, 0, 22),
		UDim2.fromOffset(0, 88)
	)
	third.TextXAlignment = Enum.TextXAlignment.Center
	third.TextStrokeTransparency = 0.6
	holder.Parent = gui
	Ui.tween(scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(4.5, function()
		for _, label in { title, sub, third } do
			Ui.tween(label, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
		Ui.tween(scale, 0.5, { Scale = 1.08 })
		task.wait(0.55)
		holder:Destroy()
		-- Then the shade: the trophy if it dropped, else the Rare-or-better roll
		local shade = if typeof(summary.trophy) == "string" then Config.Shades.byId[summary.trophy] else nil
		if shade then
			RollController.revealTreasure({
				kind = "shade",
				id = shade.id,
				outcome = { id = shade.id, kind = "shade", name = `{shade.name} Shade`, tier = shade.tier },
				pool = `{name} trophy`,
			})
		end
		local rolled = summary.shade
		if typeof(rolled) == "table" and typeof(rolled.id) == "string" then
			local def = Config.Shades.byId[rolled.id]
			if def then
				RollController.revealTreasure({
					kind = "shade",
					id = def.id,
					outcome = { id = def.id, kind = "shade", name = `{def.name} Shade`, tier = def.tier },
					duplicate = rolled.duplicate == true,
					coral = if rolled.duplicate == true then rolled.coral else nil,
					pool = `{name} kill`,
				})
			end
		end
	end)
end

local function step(dt: number)
	local now = Timing.clock()
	local me = Players.LocalPlayer.UserId
	if state.state == "warning" and typeof(state.at) == "number" then
		local left = state.at - now
		countdown.Visible = left > -1
		local name = if typeof(state.name) == "string" then string.upper(state.name) else "THE BOSS"
		countdownLabel.Text = if left > 0
			then `THE {name} RISES IN {clockText(left)} · OPEN BLUE`
			else `THE {name} IS RISING`
	else
		countdown.Visible = false
	end
	if state.state ~= "active" or typeof(state.index) ~= "number" then
		bar.Visible = false
		nearby.Visible = false
		OceanController.setDread(0)
		AmbienceController.setDread(0)
		return
	end
	local def = Bosses.byId[state.id]
	local position, mode, health, meter = PredatorController.get(state.index)
	local root = SwimController.root()
	local camera = workspace.CurrentCamera
	if def == nil or position == nil then
		bar.Visible = false
		nearby.Visible = false
		OceanController.setDread(0)
		AmbienceController.setDread(0)
		return
	end
	local from = if root then root.Position else camera.CFrame.Position
	local distance = (position - from).Magnitude
	-- The bar, while it's within range
	local show = distance <= Bosses.hudRange and mode ~= "dead"
	barAlpha = math.clamp(barAlpha + (if show then dt else -dt) * 4, 0, 1)
	bar.Visible = barAlpha > 0
	bar.BackgroundTransparency = 1 - (1 - Ui.PANEL_TRANSPARENCY) * barAlpha
	nameLabel.Text = `{string.upper(def.name)} · {def.title}`
	local phase = if typeof(state.phase) == "number" then state.phase else 1
	local phaseText = def.phaseNames[phase] or PHASES[phase] or "HUNTING"
	if phase == 3 and typeof(state.lastStandUntil) == "number" then
		phaseText = `{phaseText} · ESCAPES IN {clockText(state.lastStandUntil - now)}`
	end
	if typeof(state.staggeredUntil) == "number" and state.staggeredUntil > now then
		phaseText = `STAGGERED · {string.format("%.1f", state.staggeredUntil - now)} s`
	elseif typeof(state.exhaustedUntil) == "number" and state.exhaustedUntil > now then
		phaseText = `EXHAUSTED · {string.format("%.1f", state.exhaustedUntil - now)} s · TRIPLE DAMAGE`
	elseif state.mark == me then
		phaseText = "MARKED YOU FOR DEATH"
	end
	phaseLabel.Text = phaseText
	phaseLabel.TextColor3 = if phase == 3 or state.mark == me then Ui.color.danger else Ui.color.text
	healthFill.Size = UDim2.fromScale(health, 1)
	meterFill.Size = UDim2.fromScale(meter, 1)
	-- Dread: the water darkens as it closes in, the camera shakes as it passes
	local range = def.dread.range
	local dread = math.clamp(1 - (distance - 40) / math.max(range - 40, 1), 0, 1)
	OceanController.setDread(dread)
	AmbienceController.setDread(dread)
	if distance < def.dread.shakeRange and now - lastShake > 0.35 then
		lastShake = now
		CameraController.kick(0.12 + 0.3 * (1 - distance / def.dread.shakeRange))
	end
	-- The NEARBY warning points at it
	if dread > 0 and distance > 60 then
		nearby.Visible = true
		nearby.BackgroundTransparency = 0.5 + 0.5 * (1 - dread)
		nearbyLabel.Text = `{def.dread.warning} · {Format.distance(distance)}`
		nearbyLabel.TextTransparency = 1 - dread
		local look = camera.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		local toward = position - from
		local flat = Vector3.new(toward.X, 0, toward.Z)
		if flatLook.Magnitude > 1e-3 and flat.Magnitude > 1e-3 then
			local angle = math.atan2(flatLook.Unit:Cross(flat.Unit).Y, flatLook.Unit:Dot(flat.Unit))
			nearbyArrow.Rotation = -math.deg(angle)
		end
		nearbyArrow.TextTransparency = 1 - dread
	else
		nearby.Visible = false
	end
end

function BossController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.screen("BossHud", playerGui, 5)
	buildBar()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local bossState = remotes:WaitForChild("BossState") :: RemoteEvent
	bossState.OnClientEvent:Connect(function(incoming: any)
		if typeof(incoming) == "table" then
			local before = state.state
			state = incoming
			if state.state ~= before then
				if state.state == "warning" then
					Sfx.play("BossWarning", { volume = 0.8 })
				elseif state.state == "active" then
					Sfx.play("BossRise", { volume = 0.9 })
				end
			end
		end
	end)
	local bossReward = remotes:WaitForChild("BossReward") :: RemoteEvent
	bossReward.OnClientEvent:Connect(function(summary: any)
		if typeof(summary) == "table" then
			Sfx.play("BossDefeat", { volume = 0.9 })
			rewardCard(summary)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return BossController
