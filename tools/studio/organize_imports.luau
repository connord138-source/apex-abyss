-- Paste into Studio's Command Bar (View → Command Bar) after importing the 3D files
-- (File → Import 3D). It moves every imported model from the Workspace into the
-- folder the game code reads, by name:
--   species (rigged FBX: Nibbler, Cuda, Puffer, MorayEel, ReefShark, Angler) and bosses (Megalodon, GiantSquid)
--       -> ReplicatedStorage.FishModels.<SpeciesId>   (a Model holding the skinned MeshPart)
--   prey (rigged FBX: Minnow, Sardine, Wrasse, Snapper, Grouper, and the second batch
--   Garibaldi, WreckCod, Parrotfish, YellowfinTuna, MahiMahi, Lionfish, GhostShrimp,
--   Lanternfish, the third Butterflyfish, Triggerfish, Swordfish, OceanSunfish,
--   Coelacanth, VentEelpout, GulperEel, Oarfish, the fourth Opaleye, KelpBass, BlueTang,
--   Lingcod, Rattail, Viperfish, Hatchetfish, HumpheadWrasse; the Barracuda and ReefShark
--   prey are copies of the 'Cuda and Reef Shark species models)
--       -> ReplicatedStorage.PreyModels.<PreyId>      (a Model with bones; an old static MeshPart still works)
--   props, food and den furniture (GLB)
--       -> ReplicatedStorage.WorldProps.<Name>        (a Model)
--   rolled parts (GLB, parts_glb: AnglerLure, NarwhalHorn, SawSnout, SailFin, VeilTail)
--       -> ReplicatedStorage.PartModels.<PartId>       (the MeshPart, stamped Facing "+Z")
--   exotic variants (rigged FBX, variants_fbx: Puffball, Sabrecuda, Porcupine,
--   DragonMoray, Hammerhead, Deepfang)
--       -> ReplicatedStorage.VariantModels.<VariantId> (a Model holding the skinned MeshPart)
--   sea life (rigged FBX, ambient_fbx: Turtle, Manta, Stingray, Humpback, Crab)
--       -> ReplicatedStorage.AmbientModels.<Name>     (a Model with bones; each is given a
--          SurfaceAppearance from its texture, so the game can tint it: the edible crab
--          kinds are the one Crab tinted, Config/Forage)
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
local PREY = {
	Minnow = true, Sardine = true, Wrasse = true, Snapper = true, Grouper = true, Barracuda = true,
	-- The second batch (prey2_fbx, 2026-10-18)
	Garibaldi = true, WreckCod = true, Parrotfish = true, YellowfinTuna = true, MahiMahi = true,
	Lionfish = true, GhostShrimp = true, Lanternfish = true,
	-- The third batch (prey3_fbx, 2026-10-19)
	Butterflyfish = true, Triggerfish = true, Swordfish = true, OceanSunfish = true, Coelacanth = true,
	VentEelpout = true, GulperEel = true, Oarfish = true,
	-- The fourth batch (prey4_fbx, 2026-10-19)
	Opaleye = true, KelpBass = true, BlueTang = true, Lingcod = true, Rattail = true, Viperfish = true,
	Hatchetfish = true, HumpheadWrasse = true,
}
-- The rolled parts and the exotic variants (parts_glb, variants_fbx, 2026-10-21), worn
-- by Shared/Cosmetics
local PARTS = { AnglerLure = true, NarwhalHorn = true, SawSnout = true, SailFin = true, VeilTail = true }
local VARIANTS =
	{ Puffball = true, Sabrecuda = true, Porcupine = true, DragonMoray = true, Hammerhead = true, Deepfang = true }
-- The sea life (ambient_fbx, 2026-10-19), read by AmbientLifeController and the
-- edible crabs (ForageController)
local AMBIENT = { Turtle = true, Manta = true, Stingray = true, Humpback = true, Crab = true }
local PROPS = {
	GiantKelp = true, KelpClump = true, BoulderRound = true, BoulderJagged = true,
	BrainCoral = true, FanCoral = true, StaghornCoral = true, TubeSponge = true, Anemone = true,
	Shrimp = true, Starfish = true, Shell = true, Lantern = true, CrystalCluster = true, MarketStall = true,
	TreasureChest = true,
	WhaleFall = true, -- the Whale Fall's carcass (whalefall_glb), drawn by ChumController
	KeeperOutfitter = true, KeeperMason = true, KeeperCharms = true, KeeperDyer = true, KeeperTrophies = true,
	-- Den furniture, batch 1 (furniture_glb: the seven sets of Config/Dens)
	AnglerLamp = true, BarrelTable = true, BrainOttoman = true, BronzeCannon = true, BronzeTentacle = true,
	CaptainsDesk = true, CargoStack = true, ClamBed = true, ColumnPlanter = true, CoralThrone = true,
	DriftwoodShelf = true, FanCoralScreen = true, GlowCoralBed = true, GlyphTablet = true,
	GrouperStatue = true, JellyChandelier = true, KelpArmchair = true, KelpHammock = true,
	KrakenEyeLantern = true, KrakenEyePedestal = true, LavaFirePit = true, LavaLamp = true,
	MegalodonJawArch = true, ObsidianTable = true, ReefGlobe = true, RuneThrone = true,
	ScallopLamp = true, SharkToothPlaque = true, ShipAnchor = true, ShipLantern = true,
	ShipsWheel = true, StaghornChandelier = true, SulfurCrystals = true, TealBrazier = true,
	TreasurePile = true, TubeWormPlanter = true, VentCauldron = true, VoidThrone = true,
	-- The Sunken Ruins' hero props (ruins_glb; Ruins.luau fits them over their stand-ins)
	RuinHead = true, RuinHand = true, RuinGuardian = true, RuinUrn = true, RuinCapital = true, RuinStele = true,
	-- The drop-off's reef wall growth (cliff_glb; Cliff.luau fits them over their stand-ins)
	PlateCoral = true, BarrelSponge = true, SeaWhips = true, LaceFan = true,
	-- The biome landmarks (biome_*_glb; Wrecks, TrenchDress, KelpDress, ReefDress and
	-- BlueDress fit them over their stand-ins)
	GalleonBow = true, GalleonStern = true, IronSteamer = true, ToppledLighthouse = true, WreckCannon = true,
	WreckAnchor = true, WreckFigurehead = true, WreckWheelBell = true, WreckBarrels = true,
	LeviathanRibs = true, LeviathanSkull = true, TrenchCrystals = true, TrenchGlowTubes = true, GlassSponge = true,
	GlowEggs = true, BoneHeap = true,
	-- Den props, batch 2 (den_props2_glb; Config/Dens items of the same names)
	DriftwoodTable = true, KelpBed = true, PearlPedestal = true, BubbleColumn = true, SpongeSofa = true,
	ShipwreckBookshelf = true, JellyLamp = true, SeaGlassLantern = true, CoralLamp = true, Banner = true,
	ConchGramophone = true, TreasureChart = true,
}
-- Props whose colour map's alpha lets the MeshPart's own Color through (the banner's
-- cloth takes the den's glow): their SurfaceAppearance must be in Overlay mode, which
-- only a plugin or this Command Bar can set (a game script can't)
local OVERLAY = { Banner = true }

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
			-- (the 2026-10-19 rigs: a Jaw on the Megalodon, Reef Shark and 'Cuda, and
			-- FinL/FinR on the Megalodon; say which came in, so an old file shows)
			local extras = {}
			for _, bone in { "Jaw", "FinL", "FinR" } do
				if item:FindFirstChild(bone, true) then
					table.insert(extras, bone)
				end
			end
			print(`[organize_imports] {name}: rigged{if #extras > 0 then ", " .. table.concat(extras, ", ") else ""}`)
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
				primary:SetAttribute("Facing", "+Z") -- a static GLB: the code turns it round
				replaceIn(folder("PreyModels"), name, primary)
				item:Destroy()
			end
			moved += 1
		elseif VARIANTS[name] and rigged then
			print(`[organize_imports] {name}: rigged variant{if item:FindFirstChild("Jaw", true) then ", Jaw" else ""}`)
			replaceIn(folder("VariantModels"), name, item)
			moved += 1
		elseif PARTS[name] and primary then
			-- A part is one static mesh: keep the MeshPart, which faces +Z (the code turns it round)
			primary.Name = name
			primary:SetAttribute("Facing", "+Z")
			replaceIn(folder("PartModels"), name, primary)
			item:Destroy()
			print(`[organize_imports] {name}: part`)
			moved += 1
		elseif AMBIENT[name] and rigged then
			replaceIn(folder("AmbientModels"), name, item)
			print(`[organize_imports] {name}: rigged sea life`)
			moved += 1
		elseif PROPS[name] then
			replaceIn(folder("WorldProps"), name, item)
			moved += 1
		end
	elseif item:IsA("MeshPart") then
		if PARTS[name] then
			item:SetAttribute("Facing", "+Z")
			replaceIn(folder("PartModels"), name, item)
			print(`[organize_imports] {name}: part`)
			moved += 1
		elseif PREY[name] then
			item:SetAttribute("Facing", "+Z") -- a static GLB: the code turns it round
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
-- The Barracuda and Reef Shark prey (and predators) swim as copies of the 'Cuda and
-- Reef Shark species models, bones and all, even if those were imported before
local fishModels = ReplicatedStorage:FindFirstChild("FishModels")
for speciesName, preyName in { Cuda = "Barracuda", ReefShark = "ReefShark" } do
	local species = fishModels and fishModels:FindFirstChild(speciesName)
	local existing = ReplicatedStorage:FindFirstChild("PreyModels") and ReplicatedStorage.PreyModels:FindFirstChild(preyName)
	if species and species:IsA("Model") and (existing == nil or not existing:IsA("Model")) then
		replaceIn(folder("PreyModels"), preyName, species:Clone())
		moved += 1
	end
end
-- Sea life textured by a TextureID gets a SurfaceAppearance with that texture instead
-- (imported now or before): SurfaceAppearance.Color tints it in game, which a TextureID
-- can't take, and only a plugin or this Command Bar can set a ColorMap
local ambientModels = ReplicatedStorage:FindFirstChild("AmbientModels")
for name in AMBIENT do
	local model = ambientModels and ambientModels:FindFirstChild(name)
	for _, descendant in if model then model:GetDescendants() else {} do
		if descendant:IsA("MeshPart") and descendant.TextureID ~= "" and descendant:FindFirstChildOfClass("SurfaceAppearance") == nil then
			local texture = descendant.TextureID
			local appearance = Instance.new("SurfaceAppearance")
			local ok, err = pcall(function()
				(appearance :: any).ColorMap = texture
			end)
			if ok then
				appearance.Parent = descendant
				descendant.TextureID = ""
			end
			print(`[organize_imports] {name}: SurfaceAppearance from its texture {if ok then "made" else `failed ({err})`}`)
		end
	end
end
-- Overlay props (imported now or before): their texture's low alpha shows the part's Color
local worldProps = ReplicatedStorage:FindFirstChild("WorldProps")
for name in OVERLAY do
	local prop = worldProps and worldProps:FindFirstChild(name)
	for _, descendant in if prop then prop:GetDescendants() else {} do
		if descendant:IsA("SurfaceAppearance") then
			local ok, err = pcall(function()
				(descendant :: any).AlphaMode = Enum.AlphaMode.Overlay
			end)
			print(`[organize_imports] {name}: AlphaMode Overlay {if ok then "set" else `failed ({err})`}`)
		end
	end
end
print(`[organize_imports] moved {moved} model(s) into ReplicatedStorage`)
