--!strict
-- Names over other players' fish with their level, colored by threat at a glance:
-- red if they're well above your level (STRONGER: their bites hit much harder), green
-- if well below (WEAKER), white for an even fight (Config/Pvp `fight` `edge`), and
-- blue while they're safe (in the hub or freshly spawned). No player is swallowed
-- whole: every fight is bitten out, by level.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Format = require(ReplicatedStorage.Shared.Format)
local Ui = require(script.Parent.Parent.Ui)
local HuntController = require(script.Parent.HuntController)
local StartController = require(script.Parent.StartController)

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
		local apexId = workspace:GetAttribute("ApexUserId")
		local apex = apexId == player.UserId
		if HuntController.podmate(player) then
			color, status = Color3.fromRGB(110, 236, 220), "PODMATE"
		elseif HuntController.isSafe(character) then
			color, status = Ui.color.accent, "SAFE"
		else
			local standing = HuntController.standing(character)
			if standing == "stronger" then
				color, status = Ui.color.danger, "STRONGER"
			elseif standing == "weaker" then
				color, status = Ui.color.safe, "WEAKER"
			else
				color, status = Ui.color.text, "EVEN FIGHT"
			end
		end
		status = `LV {HuntController.levelOf(character)} · {status}`
		tag.name.TextColor3 = color
		local display =
			string.gsub(string.gsub(string.gsub(player.DisplayName, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
		-- A gold VIP tag and a pale blue diamond for Roblox Premium (◆ renders in
		-- Roblox fonts; ✦ doesn't)
		local premium = if character:GetAttribute("Premium") == true
			then `<font color="#9BE2FF">◆</font> `
			else ""
		tag.name.Text = if character:GetAttribute("VIP") == true
			then `{premium}<font color="#FFCC5C">VIP</font> {display}`
			else display
		local title = character:GetAttribute("Title")
		tag.status.Text = if typeof(title) == "string" and title ~= ""
			then `{status} · {string.upper(title)}`
			else status
		tag.status.TextColor3 = color
		-- The Apex: a crown line everyone can read from far off (Config/Pvp `apex`):
		-- heavier, bigger and darker-edged (PC overnight 2026-10-14: small and dim at
		-- 70 studs, readable only from 30)
		if apex then
			local bounty = workspace:GetAttribute("ApexBounty")
			tag.status.Text =
				`★ APEX · {Format.number(if typeof(bounty) == "number" then bounty else 0)} BOUNTY · {status}`
			tag.status.TextColor3 = Color3.fromRGB(255, 214, 110)
		end
		tag.status.FontFace = if apex then Ui.FONT_HEAVY else Ui.FONT_SEMI
		tag.status.TextSize = if apex then 18 else 13
		tag.status.Size = UDim2.new(1, 0, 0, if apex then 22 else 16)
		tag.status.TextStrokeTransparency = if apex then 0.15 else 0.7
		tag.gui.Size = UDim2.fromOffset(if apex then 300 else 200, if apex then 50 else 44)
		tag.gui.MaxDistance = if apex then 900 else 220
		-- A Moray hiding in a burrow shows no name (Config/Abilities Burrow), and none
		-- shows over the start screen's shots
		tag.gui.Enabled = character:GetAttribute("Burrowed") ~= true and not StartController.isUp()
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
