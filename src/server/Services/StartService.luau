--!strict
-- The start screen's documentary shots (StartController, Config/Start): while a player
-- is still on the start screen their fish waits in its den, far from every biome, so
-- the water each shot films hasn't streamed in. Before each cut the client asks for
-- its next shot (its index in Config/Start and the school it follows, plus the shot it
-- has on screen); this checks the school belongs to that shot (Shared/StartShots.fits)
-- and that the player hasn't dived in yet (the `StartScreen` attribute, set on joining
-- and cleared by `StartDone`), then streams the shot's area in two ways:
--   * a replication focus there (Player:AddReplicationFocus on an invisible anchored
--     part in Workspace.StartFoci), so the whole area round it streams in like the
--     water round a fish and stays while it's filmed; a player keeps at most two, the
--     shot on screen and the next one, and loses them on diving in (the den streams
--     round the fish throughout: an added focus never replaces the character's);
--   * RequestStreamAroundAsync along the school's loop for as long as the shot could
--     run (StartShots.streamPoints), which sends each spot's near water first.
-- Then it says so: the `StartStreamed` attribute becomes
-- "<shot>:<school>|<parts>|<x>,<y>,<z>", the world's parts within
-- StartShots.AREA_RADIUS of the school when asked, and where that was, so the client
-- can tell when those have reached it too (StartShots.partsNear on both sides) before
-- it cuts and while it holds the cut under the murk. Requests are rate-limited by Net
-- (one every 1.5 s) and capped per player (MOST).
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
-- Each player's replication foci, by the shot they film ("<shot>:<school>")
local foci: { [Player]: { [string]: BasePart } } = {}
local fociFolder: Folder? = nil

local function whole(value: any, low: number, high: number): number?
	if typeof(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < low or value > high then
		return nil
	end
	return value
end

local function folder(): Folder
	local existing = fociFolder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "StartFoci"
	made.Parent = workspace
	fociFolder = made
	return made
end

local function drop(player: Player, part: BasePart)
	pcall(function()
		(player :: any):RemoveReplicationFocus(part)
	end)
	part:Destroy()
end

local function release(player: Player)
	local mine = foci[player]
	foci[player] = nil
	if mine then
		for _, part in mine do
			drop(player, part)
		end
	end
end

-- Puts a focus at `at` for the shot `token`, keeping the one for `keep` (the shot on
-- screen); any other is moved there (or dropped, past one spare)
local function focusOn(player: Player, token: string, at: Vector3, keep: string?)
	local mine = foci[player]
	if mine == nil then
		mine = {}
		foci[player] = mine
	end
	local spare: BasePart? = nil
	for key, part in mine do
		if key ~= token and key ~= keep then
			mine[key] = nil
			if spare == nil then
				spare = part
			else
				drop(player, part)
			end
		end
	end
	local part = mine[token] or spare
	if part == nil then
		local made = Instance.new("Part")
		made.Name = `Focus{player.UserId}`
		made.Anchored = true
		made.CanCollide = false
		made.CanQuery = false
		made.CanTouch = false
		made.CastShadow = false
		made.Transparency = 1
		made.Size = Vector3.new(1, 1, 1)
		made.CFrame = CFrame.new(at)
		made.Parent = folder()
		local ok = pcall(function()
			(player :: any):AddReplicationFocus(made)
		end)
		if not ok then
			made:Destroy()
			return
		end
		part = made
	end
	local focus = part :: BasePart
	focus.CFrame = CFrame.new(at)
	mine[token] = focus
end

local function shot(player: Player, rawShot: any, rawSchool: any, rawShowShot: any, rawShowSchool: any)
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
	local showShot = whole(rawShowShot, 1, #Config.Start.shots)
	local showSchool = whole(rawShowSchool, 1, 100000)
	local keep = if showShot and showSchool then `{showShot}:{showSchool}` else nil
	local points = StartShots.streamPoints(def, school, Timing.clock())
	local at = points[1]
	focusOn(player, token, at, keep)
	-- Every point at once (each waits up to TIMEOUT), then say so
	local left = #points
	for _, point in points do
		task.spawn(function()
			pcall(function()
				player:RequestStreamAroundAsync(point, TIMEOUT)
			end)
			left -= 1
			if left == 0 and player.Parent and player:GetAttribute(ON_SCREEN) == true then
				local parts = StartShots.partsNear(at)
				player:SetAttribute(
					STREAMED,
					string.format("%s|%d|%.2f,%.2f,%.2f", token, parts, at.X, at.Y, at.Z)
				)
			end
		end)
	end
end

local function done(player: Player)
	player:SetAttribute(ON_SCREEN, nil)
	player:SetAttribute(STREAMED, nil)
	release(player)
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
		release(player)
	end)
	Net.onRequest("StartShot", shot)
	Net.onRequest("StartDone", done)
end

return StartService
