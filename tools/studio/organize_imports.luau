-- Paste into Studio's Command Bar (View → Command Bar) after importing the 3D files
-- (File → Import 3D). It moves every imported model from the Workspace into the
-- folder the game code reads, by name:
--   species (rigged FBX: Nibbler, Cuda, Puffer, MorayEel, ReefShark, Angler) and bosses (Megalodon, GiantSquid)
--       -> ReplicatedStorage.FishModels.<SpeciesId>   (a Model holding the skinned MeshPart)
--   prey (rigged FBX: Minnow, Sardine, Wrasse, Snapper, Grouper; the Barracuda and
--   ReefShark prey are copies of the 'Cuda and Reef Shark species models)
--       -> ReplicatedStorage.PreyModels.<PreyId>      (a Model with bones; an old static MeshPart still works)
--   props and food (GLB)
--       -> ReplicatedStorage.WorldProps.<Name>        (a Model)
-- Studio names a GLB import "Scene" when its root node is unnamed: set its Name to
-- its file name in the Import Preview before importing. A species import must be
-- rigged (have Bones), so a stray static copy of the same name isn't filed as one.
-- Safe to run again: a re-import replaces the old copy. Then File → Save (Ctrl+S):
-- these folders live in the place file, not in Rojo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SPECIES = {
	Nibbler = true, Cuda = true, Puffer = true, MorayEel = true, ReefShark = true, Angler = true,
	Megalodon = true, -- the world bosses: rigged like a species, read by PredatorController
	GiantSquid = true,
}
local PREY = { Minnow = true, Sardine = true, Wrasse = true, Snapper = true, Grouper = true, Barracuda = true }
local PROPS = {
	GiantKelp = true, KelpClump = true, BoulderRound = true, BoulderJagged = true,
	BrainCoral = true, FanCoral = true, StaghornCoral = true, TubeSponge = true, Anemone = true,
	Shrimp = true, Starfish = true, Shell = true, Lantern = true, CrystalCluster = true, MarketStall = true,
	TreasureChest = true,
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
		local rigged = item:FindFirstChildWhichIsA("Bone", true) ~= nil
		if SPECIES[name] and rigged then
			replaceIn(folder("FishModels"), name, item)
			-- The same model also feeds the prey school of that species (the 'Cuda is the
			-- Barracuda prey, the shark is the ReefShark prey) until its own prey GLB is in
			local preyName = if name == "Cuda" then "Barracuda" elseif name == "ReefShark" then "ReefShark" else nil
			if preyName then
				-- The same rigged model swims as that prey (bones and all)
				replaceIn(folder("PreyModels"), preyName, item:Clone())
			end
			moved += 1
		elseif PREY[name] then
			-- Rigged prey keep their Model and bones; an old static import is just the MeshPart
			if item:FindFirstChildWhichIsA("Bone", true) then
				replaceIn(folder("PreyModels"), name, item)
			elseif primary then
				replaceIn(folder("PreyModels"), name, primary)
				item:Destroy()
			end
			moved += 1
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
