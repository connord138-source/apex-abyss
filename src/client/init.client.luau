--!strict
-- Client bootstrap. The client draws everything and moves its own fish; the
-- server never trusts it for growth, eats or banking.
local Ads = require(script.Ads)
local ClientState = require(script.ClientState)
local Input = require(script.Input)
local Store = require(script.Store)
local BiomeController = require(script.Controllers.BiomeController)
local CameraController = require(script.Controllers.CameraController)
local FishAnimator = require(script.Controllers.FishAnimator)
local ForageController = require(script.Controllers.ForageController)
local GardenController = require(script.Controllers.GardenController)
local HealController = require(script.Controllers.HealController)
local HintController = require(script.Controllers.HintController)
local HudController = require(script.Controllers.HudController)
local HuntController = require(script.Controllers.HuntController)
local MenuController = require(script.Controllers.MenuController)
local NametagController = require(script.Controllers.NametagController)
local OfferController = require(script.Controllers.OfferController)
local OceanController = require(script.Controllers.OceanController)
local PlanktonController = require(script.Controllers.PlanktonController)
local PredatorController = require(script.Controllers.PredatorController)
local BossController = require(script.Controllers.BossController)
local LampController = require(script.Controllers.LampController)
local AdminController = require(script.Controllers.AdminController)
local AmbienceController = require(script.Controllers.AmbienceController)
local BubbleController = require(script.Controllers.BubbleController)
local KelpController = require(script.Controllers.KelpController)
local RollController = require(script.Controllers.RollController)
local SchoolController = require(script.Controllers.SchoolController)
local ShellController = require(script.Controllers.ShellController)
local StartController = require(script.Controllers.StartController)
local SwimController = require(script.Controllers.SwimController)
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
task.spawn(Ads.start) -- rewarded ads: checks whether one can be shown
BiomeController.start() -- biome names, suggested levels and under-level warnings
TutorialController.start() -- the first-session steps and markers
TreasureController.start() -- treasure maps: sonar, the X, digging
HealController.start() -- Kelp Wraps: H / LB / HEAL, the glow
HintController.start() -- EAT / BITE / DANGER / TOO BIG hints while hunting
CameraController.start()
FishAnimator.start()
PredatorController.start() -- AI predators: interpolation, tells, tags
BossController.start() -- world boss: HUD bar, dread, countdown, rewards
LampController.start() -- lamps on fish (an Anglerfish's lure, Deep Lanterns) for the dark
AdminController.start() -- the owner's admin panel (shows only for admins)
AmbienceController.start() -- the water's sound: shallow, deep and cavern beds by depth
BubbleController.start() -- bubbles off every fish's mouth as it swims
KelpController.start() -- kelp near the camera sways in the current
PlanktonController.start() -- glowing plankton in the deepest water, wakes through it
HuntController.start()
SchoolController.start()
NametagController.start()
task.spawn(ShellController.start) -- waits for the server's shell spots
task.spawn(ForageController.start) -- waits for the server's starfish and shrimp spots
SwimController.start() -- last: spawning fires the signals the others listen to

print("[ApexAbyss] Client ready")
