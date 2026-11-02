-- Paste into Studio's Command Bar (View → Command Bar) in the place file, not in Play,
-- then File → Save to File. It takes the NormalMap off every SurfaceAppearance in the
-- place (the 1,804 left on Tripo props imported before the 2026-10-13 rule: garden
-- corals, shells, …; PC report 2026-10-20-pc-3). The account was terminated once over
-- a normal map, so none should be served from the game at all; the colour, roughness
-- and metal maps stay, so the props keep their look apart from the fine relief.
-- Nothing is uploaded or deleted: the old images stay on the account until they're
-- archived in Creator Hub (Connor). Run it again after importing anything old.
-- Prints how many it cleared, and where, by top-level folder.
local cleared, byRoot = 0, {}
for _, service in { workspace, game:GetService("ReplicatedStorage"), game:GetService("ServerStorage") } do
	for _, item in service:GetDescendants() do
		if item:IsA("SurfaceAppearance") and item.NormalMap ~= "" then
			item.NormalMap = ""
			cleared += 1
			local root = item
			while root.Parent and root.Parent ~= service do
				root = root.Parent
			end
			local key = `{service.Name}.{root.Name}`
			byRoot[key] = (byRoot[key] or 0) + 1
		end
	end
end
local lines = {}
for key, count in byRoot do
	table.insert(lines, `{key} {count}`)
end
table.sort(lines)
print(`[clear_normal_maps] cleared {cleared}: {table.concat(lines, ", ")}`)
