--!strict
-- Client bootstrap. The client draws everything and moves its own fish; the
-- server never trusts it for growth, eats or banking.
-- Each start runs protected (2026-11-12): a controller that throws is named in the
-- Output and reported to Analytics (the StartError request), and the rest still start,
-- where before nothing after it did, swimming included.
local BOOT = os.clock() -- before anything is required (the load time counts from here)
game:GetService("Players").LocalPlayer:SetAttribute("ClientBoot", BOOT)
local Ads = require(script.Ads)
local ClientState = require(script.ClientState)
local Input = require(script.Input)
local Store = require(script.Store)
local BankController = require(script.Controllers.BankController)
local BiomeController = require(script.Controllers.BiomeController)
local BuildController = require(script.Controllers.BuildController)
local DenDoorController = require(script.Controllers.DenDoorController)
local CatchController = require(script.Controllers.CatchController)
local CameraController = require(script.Controllers.CameraController)
local FishAnimator = require(script.Controllers.FishAnimator)
local ForageController = require(script.Controllers.ForageController)
local ChumController = require(script.Controllers.ChumController)
local PvpController = require(script.Controllers.PvpController)
local SocialController = require(script.Controllers.SocialController)
local VendorController = require(script.Controllers.VendorController)
local HookController = require(script.Controllers.HookController)
local GardenController = require(script.Controllers.GardenController)
local AquariumController = require(script.Controllers.AquariumController)
local HealController = require(script.Controllers.HealController)
local ItemBarController = require(script.Controllers.ItemBarController)
local ItemWheelController = require(script.Controllers.ItemWheelController)
local HintController = require(script.Controllers.HintController)
local HudController = require(script.Controllers.HudController)
local HuntController = require(script.Controllers.HuntController)
local MenuController = require(script.Controllers.MenuController)
local NametagController = require(script.Controllers.NametagController)
local OfferController = require(script.Controllers.OfferController)
local OceanController = require(script.Controllers.OceanController)
local PlanktonController = require(script.Controllers.PlanktonController)
local AmbientLifeController = require(script.Controllers.AmbientLifeController)
local CompanionController = require(script.Controllers.CompanionController)
local LandmarkController = require(script.Controllers.LandmarkController)
local PredatorController = require(script.Controllers.PredatorController)
local AbilityController = require(script.Controllers.AbilityController)
local AimHelpController = require(script.Controllers.AimHelpController)
local DeviceReportController = require(script.Controllers.DeviceReportController)
local SpecialController = require(script.Controllers.SpecialController)
local BossController = require(script.Controllers.BossController)
local MapController = require(script.Controllers.MapController)
local LampController = require(script.Controllers.LampController)
local DenLampController = require(script.Controllers.DenLampController)
local AdminController = require(script.Controllers.AdminController)
local AmbienceController = require(script.Controllers.AmbienceController)
local MusicController = require(script.Controllers.MusicController)
local BubbleController = require(script.Controllers.BubbleController)
local TrailController = require(script.Controllers.TrailController)
local KelpController = require(script.Controllers.KelpController)
local RollController = require(script.Controllers.RollController)
local SchoolController = require(script.Controllers.SchoolController)
local ShellController = require(script.Controllers.ShellController)
local StartController = require(script.Controllers.StartController)
local SwimController = require(script.Controllers.SwimController)
local TideController = require(script.Controllers.TideController)
local TreasureWheelController = require(script.Controllers.TreasureWheelController)
local HeartController = require(script.Controllers.HeartController)
local TreasureController = require(script.Controllers.TreasureController)
local TutorialController = require(script.Controllers.TutorialController)

local failed: { string } = {}
local function start(name: string, fn: () -> ())
	local ok, problem = xpcall(fn, debug.traceback)
	if not ok then
		table.insert(failed, name)
		warn(`[ApexTide] {name} failed to start: {problem}`)
	end
end

start("ClientState", ClientState.start)
start("Input", Input.start)
start("StartController", StartController.start) -- the start screen covers the game until the player dives in
start("OceanController", OceanController.start)
start("HudController", HudController.start) -- before the swim controller, so it hears the first spawn
start("MenuController", MenuController.start) -- shops (at the stalls), wardrobe, odds
start("RollController", RollController.start) -- wallet, Roll button and the reveal
start("Store", Store.start) -- Robux prompts (passes, products)
start("OfferController", OfferController.start) -- DAILY and SHOP, the growth chip, Double Haul and Second Chance cards
start("GardenController", GardenController.start) -- the den's Coral Garden sign, payouts and welcome back
start("AquariumController", AquariumController.start) -- the den's tank fish and the Observatory's view
start("BuildController", BuildController.startController) -- Build mode in your own den: B / BUILD, the tray, the ghost
start("DenDoorController", DenDoorController.start) -- den doorways: the bubble portals into the private dens and back out
task.spawn(Ads.start) -- rewarded ads: checks whether one can be shown
start("BiomeController", BiomeController.start) -- biome names, suggested levels and under-level warnings
start("TideController", TideController.start) -- the Tide Clock: the chip, the banner when it turns, the water's tint
start("CatchController", CatchController.start) -- rare catches: toasts, skin unlocks, the Catch of the Week
task.spawn(TreasureWheelController.start) -- the Treasure Wheel: its spin, bulbs, result, the hint at its button
start("HeartController", HeartController.start) -- den hearts: E / Y / ADMIRE in someone else's den, once a day
start("TutorialController", TutorialController.start) -- the first-session steps and markers
start("TreasureController", TreasureController.start) -- treasure maps: sonar, the X, digging
start("HealController", HealController.start) -- Kelp Wraps: H / LB / HEAL, the glow
start("ItemWheelController", ItemWheelController.start) -- the item wheel: G / hold LB / ITEMS, wraps and timed charms used when picked
start("ItemBarController", ItemBarController.start) -- the item bar beside the Haul card: 1-4 / H / LB / tap, with counts and cooldowns
start("BankController", BankController.start) -- the bank's growth sequence: side-on camera, the fish growing, before → after
start("HintController", HintController.start) -- EAT / BITE / DANGER / TOO BIG hints while hunting
start("CameraController", CameraController.start)
start("FishAnimator", FishAnimator.start)
start("PredatorController", PredatorController.start) -- AI predators: interpolation, tells, tags
start("AbilityController", AbilityController.start) -- the ability button: Dash, or the Reef Shark's Blood Sense
start("SpecialController", SpecialController.start) -- every fish's special attack: the meter, the key and how they look
start("BossController", BossController.start) -- world boss: HUD bar, dread, countdown, rewards
start("MapController", MapController.start) -- the minimap and the full map (M / R3 / tap it)
start("LampController", LampController.start) -- lamps on fish (an Anglerfish's lure, Deep Lanterns) for the dark
start("DenLampController", DenLampController.start) -- den lamps light the storey you're looking at
start("AdminController", AdminController.start) -- the owner's admin panel (shows only for admins)
start("AmbienceController", AmbienceController.start) -- the water's sound: shallow, deep and cavern beds by depth
start("MusicController", MusicController.start) -- the music for where you are (Config/Music)
start("BubbleController", BubbleController.start) -- bubbles off every fish's mouth as it swims
start("TrailController", TrailController.start) -- boost trails off every fish's tail (Config/Trails)
start("KelpController", KelpController.start) -- kelp near the camera sways in the current
start("PlanktonController", PlanktonController.start) -- glowing plankton in the deepest water, wakes through it
start("AmbientLifeController", AmbientLifeController.start) -- jellies, rays, mantas, turtles, reef-fish clouds and far-off giants
start("CompanionController", CompanionController.start) -- a sea turtle at the side of every fish it has joined (Config/Companions)
start("LandmarkController", LandmarkController.start) -- the biome landmarks: bobbing and drifting things, ducking eels, the bell, the pearls, the Bay Cannon, the pinnacle's hammerheads
start("HuntController", HuntController.start)
start("SchoolController", SchoolController.start)
start("ChumController", ChumController.start) -- chum clouds, Blood Tide slicks and the Whale Fall: drawn and eaten here
start("PvpController", PvpController.start) -- the POD button, the Apex crown and bounty, depth pressure
start("SocialController", SocialController.start) -- the notifications card, now and then in a quiet moment
start("VendorController", VendorController.start) -- the plaza's shopkeepers bob, sway and turn to look at you
start("HookController", HookController.start) -- fishing boats, their lines and bait; hooked fish reeled up
start("NametagController", NametagController.start)
task.spawn(ShellController.start) -- waits for the server's shell spots
task.spawn(ForageController.start) -- waits for the server's starfish and shrimp spots
start("AimHelpController", AimHelpController.start) -- touch screens: the swim leans toward food a little above or below
start("DeviceReportController", DeviceReportController.start) -- the load time, then the frame rate and memory after 10 s and a minute, to Analytics
start("SwimController", SwimController.start) -- last: spawning fires the signals the others listen to

if #failed > 0 then
	task.spawn(ClientState.request, "StartError", table.concat(failed, ","))
end

print("[ApexTide] Client ready")
