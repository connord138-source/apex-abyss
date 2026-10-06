--!strict
-- Server bootstrap. Order matters: every service connects its DataService.loaded
-- handler in start(), and DataService starts last so those handlers run in this
-- order for each joining player.
local Services = script.Services
local WorldService = require(Services.WorldService)
local FishService = require(Services.FishService)
local HuntService = require(Services.HuntService)
local StateService = require(Services.StateService)
local DataService = require(Services.DataService)

WorldService.start() -- the graybox map and the ocean lighting
FishService.start() -- loaded: hand out a den and spawn the fish
HuntService.start() -- eats, bites, Haul and banking
StateService.start()
DataService.start() -- last: fires loaded for players already in the server

print("[ApexAbyss] Server started")
