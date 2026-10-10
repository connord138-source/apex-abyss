--!strict
-- Server bootstrap. Order matters: every service connects its DataService.loaded
-- handler in start(), and DataService starts last so those handlers run in this
-- order for each joining player.
local Services = script.Services
local WorldService = require(Services.WorldService)
local FishService = require(Services.FishService)
local MonetizationService = require(Services.MonetizationService)
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
local AggroService = require(Services.AggroService)
local BossService = require(Services.BossService)
local Admin = require(script.Admin)
local DenService = require(Services.DenService)
local GardenService = require(Services.GardenService)
local RewardsService = require(Services.RewardsService)
local TideService = require(Services.TideService)
local CatchService = require(Services.CatchService)
local BountyService = require(Services.BountyService)
local LeaderboardService = require(Services.LeaderboardService)
local StateService = require(Services.StateService)
local DataService = require(Services.DataService)

WorldService.start() -- the graybox map and the ocean lighting
FishService.start() -- loaded: hand out a den and spawn the fish
MonetizationService.start() -- passes, product receipts, Server Frenzy, rewarded ads
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
AggroService.start() -- oversized prey chase and nip the fish they outsize
BossService.start() -- world boss events: the Megalodon's phases, attacks and rewards
Admin.start() -- the owner's admin panel (checks who is asking on every call)
DenService.start() -- den bases: levels, furniture, glow, trophy wall
GardenService.start() -- the den's Coral Garden: AFK and offline coral and shells
RewardsService.start() -- the daily login streak and the group perk
TideService.start() -- the Tide Clock: the tide turning, the Prism Tide warning
CatchService.start() -- rare catches: which fish are rare, the Catch Log, catch tracks, the Catch of the Week
BountyService.start() -- daily bounties and the Bounty Chest
LeaderboardService.start() -- weekly leaderboards and last week's titles
StateService.start()
DataService.start() -- last: fires loaded for players already in the server

print("[ApexAbyss] Server started")
