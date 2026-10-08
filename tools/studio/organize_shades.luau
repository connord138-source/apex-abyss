-- Paste into Studio's Command Bar (View → Command Bar) after importing the shade
-- skins (File → Import 3D, the assets/shades/glb/<Fish>_Shades.glb files from the
-- `shade_skins` bundle). Each imported <Fish>_Shades holds one quad per shade; this
-- files each quad's SurfaceAppearance (or its texture id, when the importer made a
-- plain textured MeshPart) under
--   ReplicatedStorage.ShadeSkins.<Fish>.<Shade>
-- where Cosmetics wears it on that fish, and removes the imported model. Safe to run
-- again: a re-import replaces that fish's skins. Then File → Save (Ctrl+S).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:FindFirstChild("ShadeSkins")
if root == nil then
	root = Instance.new("Folder")
	root.Name = "ShadeSkins"
	root.Parent = ReplicatedStorage
end

local models, skins = 0, 0
for _, model in workspace:GetChildren() do
	local fishName = model:IsA("Model") and string.match(model.Name, "^(.+)_Shades$")
	if not fishName then
		continue
	end
	local folder = root:FindFirstChild(fishName)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = fishName
		folder.Parent = root
	end
	for _, part in model:GetDescendants() do
		if not part:IsA("MeshPart") then
			continue
		end
		local shade = part.Name
		local old = folder:FindFirstChild(shade)
		if old then
			old:Destroy()
		end
		local appearance = part:FindFirstChildWhichIsA("SurfaceAppearance")
		if appearance then
			appearance.Name = shade
			appearance.MetalnessMap = "" -- skins are non-metallic
			appearance.Parent = folder
			skins += 1
		elseif part.TextureID ~= "" then
			local value = Instance.new("StringValue")
			value.Name = shade
			value.Value = part.TextureID
			value.Parent = folder
			skins += 1
		end
	end
	model:Destroy()
	models += 1
end
print(`[organize_shades] filed {skins} skin(s) for {models} fish under ReplicatedStorage.ShadeSkins`)
