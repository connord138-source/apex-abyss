--!strict
-- The PvP twists on this client (Config/Pvp): the POD button on the HUD (lit while
-- an invite waits), the Apex crown (a gold outline on the Apex for everyone near,
-- and a chip for the Apex itself with its bounty), and depth pressure (a creaking
-- squeeze at the screen's edges and a meter while you're too deep for your level).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local MenuController = require(script.Parent.MenuController)
local SwimController = require(script.Parent.SwimController)

local PvpController = {}

local APEX = Color3.fromRGB(255, 204, 92)
local CRUSH = Color3.fromRGB(80, 120, 255)

local gui: ScreenGui
local podButton: TextButton? = nil
local apexChip: TextLabel
local pressureFrame: Frame
local pressureFill: Frame
local pressureText: TextLabel
local squeeze: Frame
local apexLight: Highlight
local lastCreak = 0

-- The POD button joins the HUD's button row (ROLL, ODDS, WARDROBE, FISH, MAPS)
local function buildPodButton()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("Wallet", 10)
	local row = hud and hud:WaitForChild("Buttons", 10)
	if row == nil or not row:IsA("Frame") then
		return
	end
	row.Size = row.Size + UDim2.fromOffset(78, 0)
	local button = Ui.button(row, "Pod", "POD", UDim2.fromOffset(70, 34), UDim2.new(), "secondary")
	button.LayoutOrder = 6
	button.TextSize = 14
	button.Selectable = false
	button.Activated:Connect(MenuController.openPod)
	podButton = button
end

local function onState(s: { [string]: any })
	local button = podButton
	if button == nil then
		return
	end
	local pod = s.pod
	local invite = typeof(pod) == "table" and pod.invite ~= nil
	local count = if typeof(pod) == "table" and typeof(pod.members) == "table" then #pod.members else 0
	button.Text = if invite then "POD !" elseif count > 0 then `POD {count}` else "POD"
	Ui.setButtonStyle(button, if invite then "gold" elseif count > 0 then "primary" else "secondary")
	button.Selectable = false
end

local function buildGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.screen("Pvp", playerGui, 6)
	-- The Apex's own chip, top centre under the tide chip
	apexChip = Ui.label(
		gui,
		"Apex",
		"",
		Ui.FONT_HEAVY,
		15,
		APEX,
		UDim2.fromOffset(460, 22),
		UDim2.new(0.5, 0, 0, 96)
	)
	apexChip.AnchorPoint = Vector2.new(0.5, 0)
	apexChip.TextXAlignment = Enum.TextXAlignment.Center
	apexChip.TextStrokeTransparency = 0.4
	apexChip.Visible = false
	-- The pressure squeeze: dark blue edges closing in
	squeeze = Instance.new("Frame")
	squeeze.Name = "Squeeze"
	squeeze.Size = UDim2.fromScale(1, 1)
	squeeze.BackgroundColor3 = Color3.fromRGB(4, 10, 40)
	squeeze.BackgroundTransparency = 1
	squeeze.BorderSizePixel = 0
	squeeze.ZIndex = 0
	local edges = Instance.new("UIGradient")
	edges.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 1),
		NumberSequenceKeypoint.new(0.7, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	edges.Parent = squeeze
	squeeze.Parent = gui
	-- The meter, under the centre of the screen
	pressureFrame =
		Ui.panel(gui, "Pressure", UDim2.fromOffset(420, 58), UDim2.new(0.5, 0, 0.62, 0), Vector2.new(0.5, 0))
	pressureFrame.Visible = false
	pressureText = Ui.label(
		pressureFrame,
		"Text",
		"",
		Ui.FONT_BOLD,
		14,
		Ui.color.text,
		UDim2.new(1, -20, 0, 20),
		UDim2.fromOffset(10, 6)
	)
	pressureText.TextXAlignment = Enum.TextXAlignment.Center
	local _, fill = Ui.bar(pressureFrame, "Meter", UDim2.new(1, -20, 0, 10), UDim2.fromOffset(10, 36), CRUSH)
	pressureFill = fill
	apexLight = Instance.new("Highlight")
	apexLight.Name = "ApexCrown"
	apexLight.FillTransparency = 1
	apexLight.OutlineColor = APEX
	apexLight.OutlineTransparency = 0.15
	apexLight.DepthMode = Enum.HighlightDepthMode.Occluded
	apexLight.Parent = gui
end

local function step()
	local now = os.clock()
	-- The Apex: a gold outline on its fish for everyone else, a chip for itself
	local apexId = workspace:GetAttribute("ApexUserId")
	local bounty = workspace:GetAttribute("ApexBounty")
	local apex = if typeof(apexId) == "number" and apexId ~= 0 then Players:GetPlayerByUserId(apexId) else nil
	local me = Players.LocalPlayer
	if apex == me then
		apexChip.Visible = true
		apexChip.Text = `★ YOU ARE THE APEX · bounty {Format.number(
			if typeof(bounty) == "number" then bounty else 0
		)} coral · everyone can see you`
		apexLight.Adornee = nil
	else
		apexChip.Visible = false
		local character = if apex then apex.Character else nil
		apexLight.Adornee = character
		apexLight.OutlineTransparency = 0.15 + 0.25 * math.sin(now * 3) ^ 2
	end
	-- Depth pressure
	local character = SwimController.character()
	local pressure = if character then character:GetAttribute("Pressure") else nil
	local level = if typeof(pressure) == "number" then pressure else 0
	if level > 0 then
		pressureFrame.Visible = true
		local crushY = if character then character:GetAttribute("CrushY") else nil
		local depth = if typeof(crushY) == "number"
			then Format.depth(Config.World.surfaceY - crushY)
			else "here"
		pressureText.Text = if level >= 1
			then `CRUSHING · too deep for your level · rise above {depth}`
			else `PRESSURE BUILDING · rise above {depth}`
		pressureText.TextColor3 = if level >= 1 then Ui.color.danger else Ui.color.text
		pressureFill.Size = UDim2.fromScale(level, 1)
		squeeze.BackgroundTransparency = 1 - 0.55 * level
		if now - lastCreak > (if level >= 1 then 1.6 else 3) then
			lastCreak = now
			Sfx.play("Warning", { volume = 0.25 + 0.25 * level, pitch = 0.55 })
		end
	elseif pressureFrame.Visible then
		pressureFrame.Visible = false
		squeeze.BackgroundTransparency = 1
	end
end

function PvpController.start()
	buildGui()
	task.spawn(buildPodButton)
	ClientState.changed:connect(onState)
	if ClientState.current then
		onState(ClientState.current)
	end
	RunService.RenderStepped:Connect(step)
	-- A new invite: a sound with the toast
	local hadInvite = false
	ClientState.changed:connect(function(s: { [string]: any })
		local invite = typeof(s.pod) == "table" and s.pod.invite ~= nil
		if invite and not hadInvite then
			Sfx.play("Banner", { volume = 0.4 })
		end
		hadInvite = invite
	end)
end

return PvpController
