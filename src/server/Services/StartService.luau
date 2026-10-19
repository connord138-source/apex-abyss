--!strict
-- The start screen's documentary shots (StartController, Config/Start): while a player
-- is still on the start screen their fish waits in its den, far from every biome, so
-- the water each shot films hasn't streamed in. Before each cut the client asks for
-- its next shot (its index in Config/Start and the school it follows); this checks
-- the school belongs to that shot (Shared/StartShots.fits) and that the player hasn't
-- dived in yet (the `StartScreen` attribute, set on joining and cleared by
-- `StartDone`), streams the area round the school (and the landmark behind it) in
-- with RequestStreamAroundAsync (along the school's loop for as long as the shot
-- could run, StartShots.streamPoints), then says so: the `StartStreamed` attribute
-- becomes "<shot>:<school>". The client still checks the Terrain is really there
-- before it cuts, and skips a shot that doesn't arrive. Requests are rate-limited by
-- Net (one every 1.5 s) and capped per player (MOST).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local StartShots = require(ReplicatedStorage.Shared.StartShots)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Net = require(script.Parent.Parent.Net)

local StartService = {}

local ON_SCREEN = "StartScreen"
local STREAMED = "StartStreamed"
local TIMEOUT = 10 -- seconds a stream may take
-- Shot requests one player gets in a session: an attract mode left running for an
-- hour asks for ~550 (one every 6.5 s); past this it stays on what it has
local MOST = 700

local served: { [Player]: number } = {}

local function whole(value: any, low: number, high: number): number?
	if typeof(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < low or value > high then
		return nil
	end
	return value
end

local function shot(player: Player, rawShot: any, rawSchool: any)
	if player:GetAttribute(ON_SCREEN) ~= true then
		return
	end
	local index = whole(rawShot, 1, #Config.Start.shots)
	local school = whole(rawSchool, 1, 100000)
	if index == nil or school == nil then
		return
	end
	local def = Config.Start.shots[index]
	if not StartShots.fits(def, school) then
		return
	end
	local count = (served[player] or 0) + 1
	if count > MOST then
		return
	end
	served[player] = count
	local token = `{index}:{school}`
	-- Every point at once (each waits up to TIMEOUT), then say so
	local points = StartShots.streamPoints(def, school, Timing.clock())
	local left = #points
	for _, at in points do
		task.spawn(function()
			pcall(function()
				player:RequestStreamAroundAsync(at, TIMEOUT)
			end)
			left -= 1
			if left == 0 and player.Parent and player:GetAttribute(ON_SCREEN) == true then
				player:SetAttribute(STREAMED, token)
			end
		end)
	end
end

local function done(player: Player)
	player:SetAttribute(ON_SCREEN, nil)
	player:SetAttribute(STREAMED, nil)
end

function StartService.start()
	local function joined(player: Player)
		player:SetAttribute(ON_SCREEN, true)
	end
	Players.PlayerAdded:Connect(joined)
	for _, player in Players:GetPlayers() do
		joined(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		served[player] = nil
	end)
	Net.onRequest("StartShot", shot)
	Net.onRequest("StartDone", done)
end

return StartService
