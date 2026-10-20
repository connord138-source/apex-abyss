-- run_hub.sh builder for the way out inside a den (DenDoor.exit), at the back of
-- its alcove in a stand-in front wall over a stand-in deck (the real ones are
-- DenCarve's Terrain). The doorway style is EXIT_STYLE if a wrapper sets it (the
-- Stone Arch otherwise). NO_TERRAIN=1 (the den is far from the hub).
local Dens = Config.Dens
local root = Instance.new("Folder")
local den = Instance.new("Model")
den.Parent = root
DenDoor.exit(den, 1)
if EXIT_STYLE then
	DenDoor.restyle(1, EXIT_STYLE)
end
local frame = Layout.exitFrame(1)
local exit = Dens.exit
local wallZ = -exit.back -- the front wall's face, in the portal's frame
local floor = -exit.y
local function slab(name, size, at, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = frame * at
	p.Color = color or Color3.fromRGB(150, 138, 118)
	p.Material = Enum.Material.Limestone
	p.Parent = root
	return p
end
-- The front wall round the alcove's mouth (a square hole as wide as the alcove)
local hole = exit.alcove
local top = 32
slab("Wall", Vector3.new(70 / 2 - hole, top - floor, 2), CFrame.new(-(hole + 70 / 2) / 2, (top + floor) / 2, wallZ + 1))
slab("Wall", Vector3.new(70 / 2 - hole, top - floor, 2), CFrame.new((hole + 70 / 2) / 2, (top + floor) / 2, wallZ + 1))
slab("Wall", Vector3.new(hole * 2, top - hole, 2), CFrame.new(0, (top + hole) / 2, wallZ + 1))
-- The alcove: its sides, roof and the rock behind the portal
local shade = Color3.fromRGB(120, 110, 94)
slab("Alcove", Vector3.new(1, hole - floor, -wallZ + 1), CFrame.new(-hole - 0.5, (hole + floor) / 2, wallZ / 2 + 0.5), shade)
slab("Alcove", Vector3.new(1, hole - floor, -wallZ + 1), CFrame.new(hole + 0.5, (hole + floor) / 2, wallZ / 2 + 0.5), shade)
slab("Alcove", Vector3.new(hole * 2 + 2, 1, -wallZ + 1), CFrame.new(0, hole + 0.5, wallZ / 2 + 0.5), shade)
slab("Alcove", Vector3.new(hole * 2 + 2, hole - floor, 1), CFrame.new(0, (hole + floor) / 2, 1.5), shade)
local deck = slab("Deck", Vector3.new(70, 1, 40), CFrame.new(0, floor - 0.5, wallZ - 20), Color3.fromRGB(150, 140, 120))
deck.Material = Enum.Material.Slate
-- a lamp in the room, as the den's orb lamps light it
local lamp = Decor.part(root, { Name = "Lamp", Size = Vector3.one, CFrame = frame * CFrame.new(0, 8, wallZ - 22), Transparency = 1 })
local light = Instance.new("PointLight")
light.Range = 40
light.Brightness = 1
light.Color = Color3.fromRGB(255, 220, 180)
light.Parent = lamp
local t, c, q, s = countParts(den)
print(string.format("C|%d|%d|%d|%d", t, c, q, s))
dumpParts(root)
local function v3(v)
	return string.format("%.3f,%.3f,%.3f", v.X, v.Y, v.Z)
end
print(string.format("V|exit|%s|%s|70", v3((frame * CFrame.new(-6, 2, wallZ - 34)).Position), v3((frame * CFrame.new(0, 4, wallZ)).Position)))
print(string.format("V|exit34|%s|%s|70", v3((frame * CFrame.new(18, -2, wallZ - 22)).Position), v3((frame * CFrame.new(0, 3, wallZ)).Position)))
