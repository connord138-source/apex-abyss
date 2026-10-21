--!strict
-- Where each named place (Config/Places) ended up: the builders that raise them
-- (Wrecks, TrenchDress, KelpDress, ReefDress, BlueDress, and WorldService for the
-- Ruins' and the Vents' own) publish a Vector3 attribute named by the place's id on
-- Workspace.Places, which every client sees (the map's names, the minimap's name bar)
-- and PlacesService checks visits against.
local PlaceMarks = {}

local function holder(): Instance?
	if typeof(workspace) ~= "Instance" then
		return nil -- (the cloud previews build without a Workspace)
	end
	local found = workspace:FindFirstChild("Places")
	if found then
		return found
	end
	local folder = Instance.new("Folder")
	folder.Name = "Places"
	folder.Parent = workspace
	return folder
end

function PlaceMarks.set(id: string, position: Vector3)
	local folder = holder()
	if folder then
		folder:SetAttribute(id, position)
	end
end

return PlaceMarks
