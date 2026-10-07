--!strict
-- Server bootstrap. Order matters: every service connects its DataService.loaded
-- handler in start(), and DataService starts last so those handlers run in this
-- order for each joining player.
local Services = script.Services
local WorldService = require(Services.WorldService)
local FishService = require(Services.FishService)
local HuntService = require(Services.HuntService)
local EconomyService = require(Services.EconomyService)
local ShellService = require(Services.ShellService)
local ForageService = require(Services.ForageService)
local RollService = require(Services.RollService)
local WardrobeService = require(Services.WardrobeService)
local ShopService = require(Services.ShopService)
local SpeciesService = require(Services.SpeciesService)
local TutorialService = require(Services.TutorialService)
local TreasureService = require(Services.TreasureService)
local PredatorService = require(Services.PredatorService)
local BossService = require(Services.BossService)
local StateService = require(Services.StateService)
local DataService = require(Services.DataService)

WorldService.start() -- the graybox map and the ocean lighting
FishService.start() -- loaded: hand out a den and spawn the fish
HuntService.start() -- eats, bites, Haul and banking
EconomyService.start() -- coral and shells on the HUD
ShellService.start() -- shell spots (after the world exists)
ForageService.start() -- starfish and shrimp on the seabed
RollService.start() -- 50 shells = a roll
WardrobeService.start() -- spawned: dress the fish
ShopService.start() -- the plaza's vendors
SpeciesService.start() -- switching and unlocking species
TutorialService.start() -- loaded: skip steps already met
TreasureService.start() -- treasure maps: drops, following, digging
PredatorService.start() -- AI predators: roaming, hunting, bites, loot
BossService.start() -- world boss events: the Megalodon's phases, attacks and rewards
StateService.start()
DataService.start() -- last: fires loaded for players already in the server

print("[ApexAbyss] Server started")
