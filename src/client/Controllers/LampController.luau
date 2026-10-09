--!strict
-- Lights the fish that carry a light into the dark (owner, 2026-10-07: the Abyssal
-- Trench needs a light source, "that could be the perk of the angler fish";
-- 2026-10-09: "visibility with a light source scales with how rare the light source
-- is"). A fish's light is the best of:
--
--  * its `Lamp` attribute (the server's WardrobeService): "lantern" while a Deep
--    Lantern charm runs (350 coral, the weakest), "lure" for an Anglerfish;
--  * its shade, if the shade glows (Config/Shades `emissive`, or the spectral
--    Ghost): Common (Ember, Ink, Neon Tetra), Rare, Epic, Legendary, Mythic and boss
--    shades light further each tier.
--
-- Each source's range, brightness, beam and how much of the dark it lifts from the
-- holder's own view are in Config/Tuning `light.sources`. Every client hangs the
-- light on every lit fish, so a lit fish lights the dark for everyone round it. A
-- glowing shade's light only comes up as the water darkens (it's a skin, not a lamp,
-- so it doesn't flood the shallows). A deep-coloured light (violet) is brightened a
-- little to light as much as a pale one of its tier (playtest 2026-10-09: Abyss Ink
-- read weaker than Nebula; at x1.6 the purples outshone everything, retest
-- 2026-10-09, so x1.2 at most), and a shade can carry its own `lampBoost`.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local OceanController = require(script.Parent.OceanController)

local LampController = {}

type Source = { range: number, brightness: number, beam: number, reveal: number }
type Lamp = {
	key: string, -- which source (and colour) it was made for
	light: PointLight,
	beam: SpotLight?,
	bulb: Part?,
	source: Source,
	fromShade: boolean,
	boost: number, -- makes up for a deep colour lighting less
}

local SOURCES = Config.Tuning.light.sources
local LAMP_COLORS: { [string]: Color3 } = {
	lure = Color3.fromRGB(150, 240, 255),
	lantern = Color3.fromRGB(255, 214, 150),
}

local lamps: { [Model]: Lamp } = {}

-- How much light a colour carries (linear luminance), and the brightness boost that
-- makes a deep colour light as much as a warm orange one does (Magma's ~0.33)
local REFERENCE_LUMINANCE = 0.32
local MAX_BOOST = 1.2
local function linear(c: number): number
	return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
end
local function boostFor(color: Color3): number
	local luminance = 0.2126 * linear(color.R) + 0.7152 * linear(color.G) + 0.0722 * linear(color.B)
	return math.clamp(REFERENCE_LUMINANCE / math.max(luminance, 0.01), 1, MAX_BOOST)
end

-- The fish's best light: its key (for rebuilding when it changes), the source, its
-- colour, whether it comes from the shade, and the shade's own lamp boost
local function bestLight(character: Model): (string?, Source?, Color3?, boolean, number)
	local bestKey: string? = nil
	local best: Source? = nil
	local color: Color3? = nil
	local fromShade = false
	local extra = 1
	local kind = character:GetAttribute("Lamp")
	if typeof(kind) == "string" and SOURCES[kind] then
		bestKey, best, color = kind, SOURCES[kind], LAMP_COLORS[kind]
	end
	local shadeId = character:GetAttribute("Shade")
	local shade = if typeof(shadeId) == "string" then Config.Shades.byId[shadeId] else nil
	if shade and (shade.emissive or shade.spectral) then
		local source = SOURCES[shade.tier]
		if source and (best == nil or source.reveal > (best :: Source).reveal) then
			local tier = Config.Tiers.byId[shade.tier]
			bestKey = `shade:{shade.id}`
			best = source
			color = shade.glow or shade.light or (if tier then tier.color else Color3.new(1, 1, 1))
			fromShade = true
			extra = shade.lampBoost or 1
		end
	end
	return bestKey, best, color, fromShade, extra
end

local function attach(
	character: Model,
	root: BasePart,
	key: string,
	source: Source,
	color: Color3,
	fromShade: boolean,
	extra: number
): Lamp
	local light = Instance.new("PointLight")
	light.Name = "Lamp"
	light.Color = color
	light.Range = source.range
	light.Brightness = source.brightness
	light.Shadows = false
	light.Parent = root
	local beam: SpotLight? = nil
	if source.beam > 0 then
		local made = Instance.new("SpotLight")
		made.Name = "LampBeam"
		made.Color = color
		made.Range = math.min(source.range + 12, 60)
		made.Brightness = source.beam
		made.Angle = 80
		made.Face = Enum.NormalId.Front -- the root faces the fish's heading
		made.Shadows = false
		made.Parent = root
		beam = made
	end
	local bulb: Part? = nil
	if key == "lantern" then
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
		made.Color = color
		made.Size = Vector3.one * 0.5
		made.CFrame = root.CFrame * CFrame.new(0, -root.Size.Y * 0.5, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = made
		weld.Parent = made
		made.Parent = character
		bulb = made
	end
	return {
		key = key,
		light = light,
		beam = beam,
		bulb = bulb,
		source = source,
		fromShade = fromShade,
		boost = boostFor(color) * extra,
	}
end

local function detach(character: Model)
	local lamp = lamps[character]
	if lamp then
		lamp.light:Destroy()
		if lamp.beam then
			(lamp.beam :: SpotLight):Destroy()
		end
		if lamp.bulb then
			(lamp.bulb :: Part):Destroy()
		end
		lamps[character] = nil
	end
end

local function step()
	local me = Players.LocalPlayer
	local myReveal = 0
	-- A glowing skin's light comes up with the dark round the camera: the water's
	-- own dark, never lessened by this fish's light (that dimmed a rare shade on its
	-- holder's screen, playtest 2026-10-09)
	local darkness = OceanController.darkness()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character == nil or root == nil or not root:IsA("BasePart") then
			continue
		end
		local key, source, color, fromShade, extra = bestLight(character)
		local current: Lamp? = lamps[character]
		if current and current.key ~= key then
			detach(character)
			current = nil
		end
		if key and source and color and current == nil then
			local made = attach(character, root, key, source, color, fromShade, extra)
			lamps[character] = made
			current = made
		end
		local lamp = current
		if lamp then
			local scale = if lamp.fromShade then 0.2 + 0.8 * darkness else 1
			lamp.light.Brightness = lamp.source.brightness * lamp.boost * scale
			if player == me then
				myReveal = lamp.source.reveal
			end
		end
	end
	for character in lamps do
		if character.Parent == nil then
			detach(character)
		end
	end
	OceanController.setReveal(myReveal)
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
