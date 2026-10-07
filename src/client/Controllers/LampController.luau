--!strict
-- Lights the fish that carry a lamp (owner, 2026-10-07: the Abyssal Trench needs a
-- light source, "that could be the perk of the angler fish"). The server puts a
-- `Lamp` attribute on a character: "lure" for an Anglerfish, "lantern" while a Deep
-- Lantern charm runs. Every client hangs a PointLight on those fish, so a lit fish
-- lights the dark for everyone round it; OceanController eases the pitch dark for
-- the local fish while it's lit.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local OceanController = require(script.Parent.OceanController)

local LampController = {}

type Lamp = { light: PointLight, kind: string, bulb: Part? }

local lamps: { [Model]: Lamp } = {}

local LOOKS = {
	lure = { color = Color3.fromRGB(150, 240, 255), range = 80, brightness = 2.6 },
	lantern = { color = Color3.fromRGB(255, 214, 150), range = 90, brightness = 2.2 },
}

local function attach(character: Model, root: BasePart, kind: string): Lamp?
	local look = LOOKS[kind]
	if look == nil then
		return nil
	end
	local light = Instance.new("PointLight")
	light.Name = "Lamp"
	light.Color = look.color
	light.Range = look.range
	light.Brightness = look.brightness
	light.Shadows = false
	light.Parent = root
	local bulb: Part? = nil
	if kind == "lantern" then
		-- A small glowing lantern slung under the fish
		local made = Instance.new("Part")
		made.Name = "LanternBulb"
		made.Anchored = false
		made.CanCollide = false
		made.CanQuery = false
		made.CanTouch = false
		made.Massless = true
		made.Shape = Enum.PartType.Ball
		made.Material = Enum.Material.Neon
		made.Color = look.color
		made.Size = Vector3.one * 0.5
		made.CFrame = root.CFrame * CFrame.new(0, -root.Size.Y * 0.5, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = made
		weld.Parent = made
		made.Parent = character
		bulb = made
	end
	return { light = light, kind = kind, bulb = bulb }
end

local function detach(character: Model)
	local lamp = lamps[character]
	if lamp then
		lamp.light:Destroy()
		if lamp.bulb then
			(lamp.bulb :: Part):Destroy()
		end
		lamps[character] = nil
	end
end

local function step()
	local me = Players.LocalPlayer
	local litMine = false
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character == nil or root == nil or not root:IsA("BasePart") then
			continue
		end
		local kind = character:GetAttribute("Lamp")
		local wanted = if typeof(kind) == "string" and kind ~= "" then kind else nil
		local current: Lamp? = lamps[character]
		if current and (wanted == nil or current.kind ~= wanted) then
			detach(character)
			current = nil
		end
		if wanted and current == nil then
			local made = attach(character, root, wanted)
			if made then
				lamps[character] = made
			end
		end
		if player == me and wanted then
			litMine = true
		end
	end
	for character in lamps do
		if character.Parent == nil then
			detach(character)
		end
	end
	OceanController.setLit(litMine)
end

function LampController.start()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.25 then
			accumulator = 0
			step()
		end
	end)
end

return LampController
