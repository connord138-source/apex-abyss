--!strict
-- Client bootstrap. The client draws everything and moves its own fish; the
-- server never trusts it for growth, eats or banking.
local ClientState = require(script.ClientState)
local Input = require(script.Input)
local BiomeController = require(script.Controllers.BiomeController)
local CameraController = require(script.Controllers.CameraController)
local FishAnimator = require(script.Controllers.FishAnimator)
local ForageController = require(script.Controllers.ForageController)
local HealController = require(script.Controllers.HealController)
local HudController = require(script.Controllers.HudController)
local HuntController = require(script.Controllers.HuntController)
local MenuController = require(script.Controllers.MenuController)
local NametagController = require(script.Controllers.NametagController)
local OceanController = require(script.Controllers.OceanController)
local PredatorController = require(script.Controllers.PredatorController)
local BossController = require(script.Controllers.BossController)
local RollController = require(script.Controllers.RollController)
local SchoolController = require(script.Controllers.SchoolController)
local ShellController = require(script.Controllers.ShellController)
local SwimController = require(script.Controllers.SwimController)
local TreasureController = require(script.Controllers.TreasureController)
local TutorialController = require(script.Controllers.TutorialController)

ClientState.start()
Input.start()
OceanController.start()
HudController.start() -- before the swim controller, so it hears the first spawn
MenuController.start() -- shops (at the stalls), wardrobe, odds
RollController.start() -- wallet, Roll button and the reveal
BiomeController.start() -- biome names, suggested levels and under-level warnings
TutorialController.start() -- the first-session steps and markers
TreasureController.start() -- treasure maps: sonar, the X, digging
HealController.start() -- Kelp Wraps: H / LB / HEAL, the glow
CameraController.start()
FishAnimator.start()
PredatorController.start() -- AI predators: interpolation, tells, tags
BossController.start() -- world boss: HUD bar, dread, countdown, rewards
HuntController.start()
SchoolController.start()
NametagController.start()
task.spawn(ShellController.start) -- waits for the server's shell spots
task.spawn(ForageController.start) -- waits for the server's starfish and shrimp spots
SwimController.start() -- last: spawning fires the signals the others listen to

print("[ApexAbyss] Client ready")
