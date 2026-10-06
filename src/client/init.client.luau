--!strict
-- Client bootstrap. The client draws everything and moves its own fish; the
-- server never trusts it for growth, eats or banking.
local ClientState = require(script.ClientState)
local Input = require(script.Input)
local CameraController = require(script.Controllers.CameraController)
local FishAnimator = require(script.Controllers.FishAnimator)
local HudController = require(script.Controllers.HudController)
local HuntController = require(script.Controllers.HuntController)
local NametagController = require(script.Controllers.NametagController)
local OceanController = require(script.Controllers.OceanController)
local SchoolController = require(script.Controllers.SchoolController)
local SwimController = require(script.Controllers.SwimController)

ClientState.start()
Input.start()
OceanController.start()
HudController.start() -- before the swim controller, so it hears the first spawn
CameraController.start()
FishAnimator.start()
HuntController.start()
SchoolController.start()
NametagController.start()
SwimController.start() -- last: spawning fires the signals the others listen to

print("[ApexAbyss] Client ready")
