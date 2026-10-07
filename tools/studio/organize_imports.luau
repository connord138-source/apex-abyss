-- Paste into Studio's Command Bar (View → Command Bar) after importing the 3D files
-- (File → Import 3D). It moves every imported model from the Workspace into the
-- folder the game code reads, by name:
--   species (rigged FBX: Nibbler, Cuda, Puffer, MorayEel, ReefShark, Angler)
--       -> ReplicatedStorage.FishModels.<SpeciesId>   (a Model holding the skinned MeshPart)
--   prey (static GLB: Minnow, Sardine, Wrasse, Snapper, Grouper, Barracuda, ReefShark)
--       -> ReplicatedStorage.PreyModels.<PreyId>      (the MeshPart itself)
--   props and food (GLB)
--       -> ReplicatedStorage.WorldProps.<Name>        (a Model)
-- Safe to run again: a re-import replaces the old copy. Then File → Save (Ctrl+S):
-- these folders live in the place file, not in Rojo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SPECIES = { Nibbler = true, Cuda = true, Puffer = true, MorayEel = true, ReefShark = true, Angler = true }
local PREY = { Minnow = true, Sardine = true, Wrasse = true, Snapper = true, Grouper = true, Barracuda = true }
local PROPS = {
	GiantKelp = true, KelpClump = true, BoulderRound = true, BoulderJagged = true,
	BrainCoral = true, FanCoral = true, StaghornCoral = true, TubeSponge = true, Anemone = true,
	Shrimp = true, Starfish = true, Shell = true, Lantern = true, CrystalCluster = true, MarketStall = true,
}

local function folder(name: string): Folder
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = name
	made.Parent = ReplicatedStorage
	return made
end

local function replaceIn(target: Folder, name: string, item: Instance)
	local old = target:FindFirstChild(name)
	if old and old ~= item then
		old:Destroy()
	end
	item.Name = name
	item.Parent = target
end

local function largestPart(model: Model): BasePart?
	local best: BasePart? = nil
	local bestVolume = -1
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local size = descendant.Size
			local volume = size.X * size.Y * size.Z
			if volume > bestVolume then
				best, bestVolume = descendant, volume
			end
		end
	end
	return best
end

local moved = 0
for _, item in workspace:GetChildren() do
	local name = item.Name
	-- Studio names an import after its file; a rigged FBX comes in as a Model with
	-- the MeshPart (and its bones) inside
	if item:IsA("Model") then
		local primary = largestPart(item)
		if primary then
			item.PrimaryPart = primary
		end
		if SPECIES[name] then
			replaceIn(folder("FishModels"), name, item)
			-- The same model also feeds the prey school of that species (the 'Cuda is the
			-- Barracuda prey, the shark is the ReefShark prey)
			local preyName = if name == "Cuda" then "Barracuda" elseif name == "ReefShark" then "ReefShark" else nil
			if preyName and primary and not ReplicatedStorage:FindFirstChild("PreyModels") or (preyName and primary and ReplicatedStorage.PreyModels:FindFirstChild(preyName) == nil) then
				local copy = primary:Clone()
				for _, child in copy:GetChildren() do
					if child:IsA("Bone") then
						child:Destroy()
					end
				end
				replaceIn(folder("PreyModels"), preyName, copy)
			end
			moved += 1
		elseif PREY[name] then
			-- Prey are one MeshPart each; unwrap the Model
			if primary then
				replaceIn(folder("PreyModels"), name, primary)
				item:Destroy()
				moved += 1
			end
		elseif PROPS[name] then
			replaceIn(folder("WorldProps"), name, item)
			moved += 1
		end
	elseif item:IsA("MeshPart") then
		if PREY[name] then
			replaceIn(folder("PreyModels"), name, item)
			moved += 1
		elseif PROPS[name] then
			local model = Instance.new("Model")
			model.PrimaryPart = item
			item.Parent = model
			replaceIn(folder("WorldProps"), name, model)
			moved += 1
		end
	end
end
print(`[organize_imports] moved {moved} model(s) into ReplicatedStorage`)
