--!strict
-- Client bootstrap. The client draws everything and moves its own fish; the
-- server never trusts it for growth, eats or banking.
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
local BossController = require(script.Controllers.BossController)
local MapController = require(script.Controllers.MapController)
local LampController = require(script.Controllers.LampController)
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
local TreasureController = require(script.Controllers.TreasureController)
local TutorialController = require(script.Controllers.TutorialController)

ClientState.start()
Input.start()
StartController.start() -- the start screen covers the game until the player dives in
OceanController.start()
HudController.start() -- before the swim controller, so it hears the first spawn
MenuController.start() -- shops (at the stalls), wardrobe, odds
RollController.start() -- wallet, Roll button and the reveal
Store.start() -- Robux prompts (passes, products)
OfferController.start() -- DAILY and SHOP, the growth chip, Double Haul and Second Chance cards
GardenController.start() -- the den's Coral Garden sign, payouts and welcome back
AquariumController.start() -- the den's tank fish and the Observatory's view
BuildController.startController() -- Build mode in your own den: B / BUILD, the tray, the ghost
DenDoorController.start() -- den doorways: the bubble portals into the private dens and back out
task.spawn(Ads.start) -- rewarded ads: checks whether one can be shown
BiomeController.start() -- biome names, suggested levels and under-level warnings
TideController.start() -- the Tide Clock: the chip, the banner when it turns, the water's tint
CatchController.start() -- rare catches: toasts, skin unlocks, the Catch of the Week
task.spawn(TreasureWheelController.start) -- the Treasure Wheel: its spin, bulbs, result, the hint at its button
TutorialController.start() -- the first-session steps and markers
TreasureController.start() -- treasure maps: sonar, the X, digging
HealController.start() -- Kelp Wraps: H / LB / HEAL, the glow
ItemWheelController.start() -- the item wheel: G / hold LB / ITEMS, wraps and timed charms used when picked
ItemBarController.start() -- the item bar beside the Haul card: 1-4 / H / LB / tap, with counts and cooldowns
BankController.start() -- the bank's growth sequence: side-on camera, the fish growing, before → after
HintController.start() -- EAT / BITE / DANGER / TOO BIG hints while hunting
CameraController.start()
FishAnimator.start()
PredatorController.start() -- AI predators: interpolation, tells, tags
AbilityController.start() -- the ability button: Dash, or the Reef Shark's Blood Sense
BossController.start() -- world boss: HUD bar, dread, countdown, rewards
MapController.start() -- the minimap and the full map (M / R3 / tap it)
LampController.start() -- lamps on fish (an Anglerfish's lure, Deep Lanterns) for the dark
AdminController.start() -- the owner's admin panel (shows only for admins)
AmbienceController.start() -- the water's sound: shallow, deep and cavern beds by depth
MusicController.start() -- the music for where you are (Config/Music)
BubbleController.start() -- bubbles off every fish's mouth as it swims
TrailController.start() -- boost trails off every fish's tail (Config/Trails)
KelpController.start() -- kelp near the camera sways in the current
PlanktonController.start() -- glowing plankton in the deepest water, wakes through it
AmbientLifeController.start() -- jellies, rays, mantas, turtles, reef-fish clouds and far-off giants
CompanionController.start() -- a sea turtle at the side of every fish it has joined (Config/Companions)
LandmarkController.start() -- the biome landmarks: bobbing and drifting things, ducking eels, the bell, the pearls, the Bay Cannon, the pinnacle's hammerheads
HuntController.start()
SchoolController.start()
ChumController.start() -- chum clouds, Blood Tide slicks and the Whale Fall: drawn and eaten here
PvpController.start() -- the POD button, the Apex crown and bounty, depth pressure
HookController.start() -- fishing boats, their lines and bait; hooked fish reeled up
NametagController.start()
task.spawn(ShellController.start) -- waits for the server's shell spots
task.spawn(ForageController.start) -- waits for the server's starfish and shrimp spots
SwimController.start() -- last: spawning fires the signals the others listen to

print("[ApexTide] Client ready")
