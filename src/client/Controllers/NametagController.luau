--!strict
-- Names over other players' fish, colored by threat at a glance: red if they can
-- swallow you, green if you can swallow them, white for an even fight, and blue
-- while they're safe (in the hub or freshly spawned).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Size = require(ReplicatedStorage.Shared.Size)
local Ui = require(script.Parent.Parent.Ui)
local HuntController = require(script.Parent.HuntController)
local SwimController = require(script.Parent.SwimController)

local NametagController = {}

type Tag = {
	gui: BillboardGui,
	name: TextLabel,
	status: TextLabel,
}

local tags: { [Model]: Tag } = {}

local function make(player: Player, character: Model, root: BasePart): Tag
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nametag"
	gui.Size = UDim2.fromOffset(200, 44)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	gui.Adornee = root
	local name =
		Ui.label(gui, "Name", player.DisplayName, Ui.FONT_BOLD, 18, Ui.color.text, UDim2.new(1, 0, 0, 22))
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextStrokeTransparency = 0.6
	name.RichText = true -- the gold VIP tag
	local status = Ui.label(
		gui,
		"Status",
		"",
		Ui.FONT_SEMI,
		13,
		Ui.color.muted,
		UDim2.new(1, 0, 0, 16),
		UDim2.fromOffset(0, 22)
	)
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.TextStrokeTransparency = 0.7
	gui.Parent = character
	local tag = { gui = gui, name = name, status = status }
	tags[character] = tag
	character.Destroying:Connect(function()
		tags[character] = nil
	end)
	return tag
end

local function step()
	local myLength = SwimController.length()
	for _, player in Players:GetPlayers() do
		if player == Players.LocalPlayer then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character == nil or root == nil or not root:IsA("BasePart") then
			continue
		end
		local tag = tags[character] or make(player, character, root)
		local length = character:GetAttribute("Length")
		local theirs = if typeof(length) == "number" then length else 2
		tag.gui.StudsOffsetWorldSpace = Vector3.new(0, theirs * 0.45 + 1.5, 0)
		local color, status
		if HuntController.isSafe(character) then
			color, status = Ui.color.accent, "SAFE"
		elseif Size.canSwallow(theirs, myLength) then
			color, status = Ui.color.danger, "DANGER"
		elseif Size.canSwallow(myLength, theirs) then
			color, status = Ui.color.safe, "PREY"
		else
			color, status = Ui.color.text, "EVEN FIGHT"
		end
		tag.name.TextColor3 = color
		local display =
			string.gsub(string.gsub(string.gsub(player.DisplayName, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
		tag.name.Text = if character:GetAttribute("VIP") == true
			then `<font color="#FFCC5C">VIP</font> {display}`
			else display
		local title = character:GetAttribute("Title")
		tag.status.Text = if typeof(title) == "string" and title ~= ""
			then `{status} · {string.upper(title)}`
			else status
		tag.status.TextColor3 = color
	end
end

function NametagController.start()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.1 then
			accumulator = 0
			step()
		end
	end)
end

return NametagController
