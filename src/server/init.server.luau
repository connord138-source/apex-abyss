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
local ChumService = require(Services.ChumService)
local PodService = require(Services.PodService)
local ApexService = require(Services.ApexService)
local PressureService = require(Services.PressureService)
local HookService = require(Services.HookService)
local SpeedService = require(Services.SpeedService)
local RollService = require(Services.RollService)
local WardrobeService = require(Services.WardrobeService)
local ShopService = require(Services.ShopService)
local ItemService = require(Services.ItemService)
local SpeciesService = require(Services.SpeciesService)
local TutorialService = require(Services.TutorialService)
local TreasureService = require(Services.TreasureService)
local PredatorService = require(Services.PredatorService)
local AggroService = require(Services.AggroService)
local BossService = require(Services.BossService)
local Admin = require(script.Admin)
local DenService = require(Services.DenService)
local GardenService = require(Services.GardenService)
local AquariumService = require(Services.AquariumService)
local RewardsService = require(Services.RewardsService)
local TideService = require(Services.TideService)
local CatchService = require(Services.CatchService)
local BountyService = require(Services.BountyService)
local LeaderboardService = require(Services.LeaderboardService)
local HeartService = require(Services.HeartService)
local WheelService = require(Services.WheelService)
local PlaytimeService = require(Services.PlaytimeService)
local PassService = require(Services.PassService)
local AchievementService = require(Services.AchievementService)
local AbilityService = require(Services.AbilityService)
local StartService = require(Services.StartService)
local CompanionService = require(Services.CompanionService)
local LandmarkService = require(Services.LandmarkService)
local StateService = require(Services.StateService)
local DataService = require(Services.DataService)

WorldService.start() -- the graybox map and the ocean lighting
FishService.start() -- loaded: hand out a den and spawn the fish
MonetizationService.start() -- passes, product receipts, Server Frenzy, rewarded ads
HuntService.start() -- eats, bites, Haul and banking
EconomyService.start() -- coral and shells on the HUD
ShellService.start() -- shell spots (after the world exists)
ForageService.start() -- starfish and shrimp on the seabed
ChumService.start() -- chum clouds from eaten fish, Blood Tide slicks, the Whale Fall
PodService.start() -- pods of up to 3: invites, no friendly fire, shared kills
ApexService.start() -- the Apex bounty on the biggest fish in the server
PressureService.start() -- depth pressure: too deep for your level hurts
HookService.start() -- fishing boats drop baited hooks; hooked fish are reeled up
SpeedService.start() -- lenient speed checks, logged to the Output (nothing enforced yet)
RollService.start() -- 50 shells = a roll
WardrobeService.start() -- spawned: dress the fish
ShopService.start() -- the plaza's vendors
ItemService.start() -- the item wheel: Kelp Wraps and timed charms, used when picked
SpeciesService.start() -- switching and unlocking species
TutorialService.start() -- loaded: skip steps already met
TreasureService.start() -- treasure maps: drops, following, digging
PredatorService.start() -- AI predators: roaming, hunting, bites, loot
AggroService.start() -- oversized prey chase and nip the fish they outsize
BossService.start() -- world boss events: the Megalodon's phases, attacks and rewards
Admin.start() -- the owner's admin panel (checks who is asking on every call)
DenService.start() -- den bases: levels, furniture, glow, trophy wall
GardenService.start() -- the den's Coral Garden: AFK and offline coral and shells
AquariumService.start() -- the den's aquarium tanks: rare catches on show, earning
RewardsService.start() -- the daily login streak and the group perk
TideService.start() -- the Tide Clock: the tide turning, the Prism Tide warning
CatchService.start() -- rare catches: which fish are rare, the Catch Log, the skin goals, the Catch of the Week
BountyService.start() -- daily bounties and the Bounty Chest
LeaderboardService.start() -- weekly leaderboards and last week's titles
HeartService.start() -- den hearts: admire a den once a day, the Best Dens board, hearts and frames on den signs
WheelService.start() -- the Treasure Wheel: spins, the line, prizes, free spins
PlaytimeService.start() -- playtime gifts: a ladder of gifts for minutes played today, Premium's daily spin
PassService.start() -- the Tide Pass: season XP from play, the free and Deep Pass rows
AchievementService.start() -- achievements: each opens a den furniture set
AbilityService.start() -- signature abilities the server owns: Puff Up, Burrow, Lantern Flash
StartService.start() -- the start screen's documentary shots: each one's water streamed in ahead
CompanionService.start() -- sea life that helps: a turtle at your side, a ray's shells
LandmarkService.start() -- the biome landmarks: named places found, the galleon's bell, the Bay Cannon, the clams' pearls
StateService.start()
DataService.start() -- last: fires loaded for players already in the server

print("[ApexTide] Server started")
