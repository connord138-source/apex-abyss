--!strict
-- Server bootstrap. Order matters: every service connects its DataService.loaded
-- handler in start(), and DataService starts last so those handlers run in this
-- order for each joining player.
local Services = script.Services
local StateService = require(Services.StateService)
local DataService = require(Services.DataService)

StateService.start()
DataService.start() -- last: fires loaded for players already in the server

print("[ApexAbyss] Server started")
