-- Paste into Studio's Command Bar (edit mode, with Rojo synced) after the toon images
-- are uploaded and their ids pasted into src/shared/Config/Materials.luau. Makes a
-- MaterialVariant per material under MaterialService ("Toon<Name>": the image as its
-- colour map, no normal map ever) and makes it that base material's override, so
-- Terrain and every part of that material wear it. Safe to run again (it replaces
-- them). Then File → Save (Ctrl+S); the variants live in the place file, since a game
-- script can't set a MaterialVariant's maps.
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Materials = require(ReplicatedStorage.Shared.Config.Materials)

local made, skipped = 0, 0
for key, toon in Materials.toon do
	local name = "Toon" .. key
	if toon.id == 0 then
		skipped += 1
		continue
	end
	local old = MaterialService:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local variant = Instance.new("MaterialVariant")
	variant.Name = name
	variant.BaseMaterial = toon.base
	local uri = "rbxassetid://" .. toon.id
	local ok = pcall(function()
		(variant :: any).ColorMapContent = Content.fromUri(uri)
	end)
	if not ok then
		(variant :: any).ColorMap = uri
	end
	variant.StudsPerTile = toon.studsPerTile
	variant.MaterialPattern = Enum.MaterialPattern[toon.pattern]
	variant.Parent = MaterialService
	MaterialService:SetBaseMaterialOverride(toon.base, name)
	made += 1
end
print(`[make_toon_materials] {made} toon materials on, {skipped} still stock (id 0). Now File → Save.`)
