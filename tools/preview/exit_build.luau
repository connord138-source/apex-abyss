-- run_hub.sh builder for the way out inside a den (DenDoor.exit), on a stand-in
-- front wall and deck (the real ones are DenCarve's Terrain), with the den's title
-- board over it as DenBuilder makes it. NO_TERRAIN=1 (the den is far from the hub).
local Dens = Config.Dens
local root = Instance.new("Folder")
local den = Instance.new("Model")
den.Parent = root
DenDoor.exit(den, 1)
local frame = Layout.exitFrame(1)
local wall = Instance.new("Part")
wall.Name = "Wall"
wall.Size = Vector3.new(70, 44, 2)
wall.CFrame = frame * CFrame.new(0, 8, 1.6)
wall.Color = Color3.fromRGB(150, 138, 118)
wall.Material = Enum.Material.Limestone
wall.Parent = root
local deck = Instance.new("Part")
deck.Name = "Deck"
deck.Size = Vector3.new(70, 1, 40)
deck.CFrame = frame * CFrame.new(0, -Dens.exit.y - 0.5, -19)
deck.Color = Color3.fromRGB(150, 140, 120)
deck.Material = Enum.Material.Slate
deck.Parent = root
-- DenBuilder's title board (trophies.title), as built there
local at = frame * CFrame.new(0, Dens.exit.radius + 8, 0.1) * CFrame.Angles(0, math.pi, 0)
local sign = Decor.part(root, { Name = "Title", Size = Vector3.new(12, 2.4, 0.5), CFrame = at, Color = Color3.fromRGB(20, 88, 102) })
for _, y in { -1, 1 } do
	Decor.part(root, { Name = "TitleTrim", Size = Vector3.new(12.4, 0.4, 0.35), CFrame = at * CFrame.new(0, y * 1.2, 0.2), Color = Decor.BRASS })
end
for _, x in { -1, 1 } do
	Decor.part(root, { Name = "TitleTrim", Size = Vector3.new(0.4, 2.8, 0.35), CFrame = at * CFrame.new(x * 6, 0, 0.2), Color = Decor.BRASS })
end
local gui = Instance.new("SurfaceGui")
gui.Face = Enum.NormalId.Back
gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
gui.PixelsPerStud = 60
gui.LightInfluence = 0
gui.Parent = sign
local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Position = UDim2.fromScale(0.04, 0.1)
label.Size = UDim2.fromScale(0.92, 0.8)
label.TextScaled = true
label.TextColor3 = Color3.fromRGB(120, 230, 255)
label.Text = "MEGALODON SLAYER"
label.Parent = gui
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(8, 34, 42)
stroke.Thickness = 3
stroke.Parent = label
-- a lamp in the room, as the den's orb lamps light it
local lamp = Decor.part(root, { Name = "Lamp", Size = Vector3.one, CFrame = frame * CFrame.new(0, 8, -20), Transparency = 1 })
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
print(string.format("V|exit|%s|%s|70", v3((frame * CFrame.new(-6, 1, -30)).Position), v3((frame * CFrame.new(0, 3, 0)).Position)))
print(string.format("V|exit34|%s|%s|70", v3((frame * CFrame.new(14, -4, -14)).Position), v3((frame * CFrame.new(0, 2, 0)).Position)))
