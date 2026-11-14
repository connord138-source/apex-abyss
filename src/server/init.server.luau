--!strict
-- Server bootstrap. Order matters: every service connects its DataService.loaded
-- handler in start(), and DataService starts last so those handlers run in this
-- order for each joining player.
-- Each start runs protected (2026-11-12): one that throws is named in the Output and
-- in Analytics (Funnel.startError) and the rest still start, where before everything
-- after it, the saves included, never did.
local BOOT = os.clock() -- before anything is required or built
local Players = game:GetService("Players")
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
local NotifyService = require(Services.NotifyService)
local ReferralService = require(Services.ReferralService)
local BadgesService = require(Services.BadgesService)
local AbilityService = require(Services.AbilityService)
local SpecialService = require(Services.SpecialService)
local StartService = require(Services.StartService)
local CompanionService = require(Services.CompanionService)
local LandmarkService = require(Services.LandmarkService)
local StateService = require(Services.StateService)
local DataService = require(Services.DataService)
local Funnel = require(script.Funnel)

-- When each player's connection was first heard. The sea is built before any save
-- loads, and a player who arrives meanwhile waits for it (Funnel.arrived logs how long).
-- The build only lets a join be heard at its few yields (in Studio the first join is
-- heard only once everything has started), and the first player's join is what
-- started this server, so the first one heard always counts from the server's own
-- start.
local heard: { [Player]: number } = {}
local anyHeard = false
Players.PlayerAdded:Connect(function(player: Player)
	heard[player] = if anyHeard then os.clock() else BOOT
	anyHeard = true
end)
Players.PlayerRemoving:Connect(function(player: Player)
	heard[player] = nil
end)

local failed: { string } = {}
local function start(name: string, service: any)
	local ok, problem = xpcall(service.start, debug.traceback)
	if not ok then
		table.insert(failed, name)
		warn(`[ApexTide] {name} failed to start: {problem}`)
	end
end

start("WorldService", WorldService) -- the graybox map and the ocean lighting
start("FishService", FishService) -- loaded: hand out a den and spawn the fish
start("MonetizationService", MonetizationService) -- passes, product receipts, Server Frenzy, rewarded ads
start("HuntService", HuntService) -- eats, bites, Haul and banking
start("EconomyService", EconomyService) -- coral and shells on the HUD
start("ShellService", ShellService) -- shell spots (after the world exists)
start("ForageService", ForageService) -- starfish and shrimp on the seabed
start("ChumService", ChumService) -- chum clouds from eaten fish, Blood Tide slicks, the Whale Fall
start("PodService", PodService) -- pods of up to 3: invites, no friendly fire, shared kills
start("ApexService", ApexService) -- the Apex bounty on the biggest fish in the server
start("PressureService", PressureService) -- depth pressure: too deep for your level hurts
start("HookService", HookService) -- fishing boats drop baited hooks; hooked fish are reeled up
start("SpeedService", SpeedService) -- lenient speed checks, logged to the Output (nothing enforced yet)
start("RollService", RollService) -- 50 shells = a roll
start("WardrobeService", WardrobeService) -- spawned: dress the fish
start("ShopService", ShopService) -- the plaza's vendors
start("ItemService", ItemService) -- the item wheel: Kelp Wraps and timed charms, used when picked
start("SpeciesService", SpeciesService) -- switching and unlocking species
start("TutorialService", TutorialService) -- loaded: skip steps already met
start("TreasureService", TreasureService) -- treasure maps: drops, following, digging
start("PredatorService", PredatorService) -- AI predators: roaming, hunting, bites, loot
start("AggroService", AggroService) -- oversized prey chase and nip the fish they outsize
start("BossService", BossService) -- world boss events: the Megalodon's phases, attacks and rewards
start("Admin", Admin) -- the owner's admin panel (checks who is asking on every call)
start("DenService", DenService) -- den bases: levels, furniture, glow, trophy wall
start("GardenService", GardenService) -- the den's Coral Garden: AFK and offline coral and shells
start("AquariumService", AquariumService) -- the den's aquarium tanks: rare catches on show, earning
start("RewardsService", RewardsService) -- the daily login streak and the group perk
start("TideService", TideService) -- the Tide Clock: the tide turning, the Prism Tide warning
start("CatchService", CatchService) -- rare catches: which fish are rare, the Catch Log, the skin goals, the Catch of the Week
start("BountyService", BountyService) -- daily bounties and the Bounty Chest
start("LeaderboardService", LeaderboardService) -- weekly leaderboards and last week's titles
start("HeartService", HeartService) -- den hearts: admire a den once a day, the Best Dens board, hearts and frames on den signs
start("WheelService", WheelService) -- the Treasure Wheel: spins, the line, prizes, free spins
start("PlaytimeService", PlaytimeService) -- playtime gifts: a ladder of gifts for minutes played today, Premium's daily spin
start("PassService", PassService) -- the Tide Pass: season XP from play, the free and Deep Pass rows
start("AchievementService", AchievementService) -- achievements: each opens a den furniture set
start("NotifyService", NotifyService) -- notifications for players away: the Coral Garden full, wheel spins back
start("ReferralService", ReferralService) -- friend invites: a welcome gift, the inviter's reward once the friend finishes the tutorial
start("BadgesService", BadgesService) -- Roblox badges, measured from the save
start("AbilityService", AbilityService) -- signature abilities the server owns: Puff Up, Burrow, Lantern Flash
start("SpecialService", SpecialService) -- every fish's special attack: the meter, and what each one does
start("StartService", StartService) -- the start screen's documentary shots: each one's water streamed in ahead
start("CompanionService", CompanionService) -- sea life that helps: a turtle at your side, a ray's shells
start("LandmarkService", LandmarkService) -- the biome landmarks: named places found, the galleon's bell, the Bay Cannon, the clams' pearls
start("StateService", StateService)

-- How long each player waited for their save: from their connection being heard (the
-- server's own start for one who was there before its scripts ran), and whether the
-- sea was still being built when they came
local built = os.clock()
local serverStart = built - BOOT
DataService.loaded:connect(function(player: Player)
	local since = heard[player] or BOOT
	Funnel.arrived(player, os.clock() - since, since < built, serverStart)
	if #failed > 0 then
		Funnel.startError(player, "server", table.concat(failed, ","))
	end
end)
start("DataService", DataService) -- last: fires loaded for players already in the server

workspace:SetAttribute("ServerStartSeconds", math.floor(serverStart * 10 + 0.5) / 10)
print(`[ApexTide] Server started in {math.floor(serverStart * 10 + 0.5) / 10} s`)
