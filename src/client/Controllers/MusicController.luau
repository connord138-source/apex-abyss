--!strict
-- Background music (owner, 2026-10-11: "The music is horrible too ... it's just
-- random bells"; Config/Music). Plays the list for where the camera is: the hub
-- cavern, each biome, the Trench's dark, or a boss close by (BossController.setBoss),
-- shuffled, never the same track twice running. A new place has to hold for
-- `settleSeconds` before its music fades in, so a border swum along doesn't flip the
-- music back and forth; going back to a place within `resumeSeconds` carries its
-- track on where it was instead of starting it over. It ducks under the roll reveal
-- (RollController). Ported from Hatch & Snatch's MusicController. Presentation only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Biomes = require(ReplicatedStorage.Shared.Biomes)
local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local OceanController = require(script.Parent.OceanController)

local Music = Config.Music
local DUCK = 0.35 -- share of the volume left under a roll reveal
local LOAD_SECONDS = 20 -- a track that hasn't loaded by then is skipped
local CHECK_SECONDS = 0.5
local BOSS_ON = 0.35 -- how near a boss is felt before its music takes over

type Resume = { id: number, position: number, at: number }

local MusicController = {}

local group: SoundGroup? = nil
local current: Sound? = nil
local currentList: string? = nil
local currentId = 0
local lastId: { [string]: number } = {}
local resume: { [string]: Resume } = {}
local trackVolume = Music.volume -- the current track's own level
local startedAt = 0
local endedAt: number? = nil
local ducked = false
local muted = false
local warned: { [number]: boolean } = {}
local failed: { [number]: boolean } = {}
local candidate: string? = nil
local candidateSince = 0
local boss = 0
local bossId: string? = nil
local rng = Random.new()
local held: string? = nil -- a list played wherever the camera is (the start screen's)

local function level(): number
	if muted then
		return 0
	end
	return trackVolume * (if ducked then DUCK else 1)
end

local function fade(sound: Sound, volume: number, seconds: number)
	TweenService:Create(sound, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { Volume = volume }):Play()
end

-- The tracks of a list that haven't failed to load (falling back when it has none)
local function tracks(list: string): { number }
	local ids = {}
	local all: { number } = Music.lists[list] or {}
	for _, id in all do
		if not failed[id] then
			table.insert(ids, id)
		end
	end
	if #ids == 0 and list ~= Music.fallback then
		return tracks(Music.fallback)
	end
	return ids
end

-- Which list belongs where the camera is now
local function wanted(): string
	if held then
		return held
	end
	if boss >= BOSS_ON and bossId and Music.bosses[bossId] then
		return Music.bosses[bossId]
	end
	if OceanController.darkness() > 0.5 then
		return "trench"
	end
	local position = Workspace.CurrentCamera.CFrame.Position
	if Layout.inHub(position) then
		return "hub"
	end
	local biome = Biomes.at(position)
	return if biome then Music.biomes[biome.id] or Music.fallback else Music.fallback
end

local function remember()
	local sound = current
	local list = currentList
	if sound and list and sound.IsLoaded and sound.IsPlaying then
		resume[list] = { id = currentId, position = sound.TimePosition, at = os.clock() }
	end
end

local function play(list: string)
	local ids = tracks(list)
	if #ids == 0 then
		return
	end
	remember()
	local id = ids[rng:NextInteger(1, #ids)]
	local from = 0
	local back = resume[list]
	if back and os.clock() - back.at < Music.resumeSeconds and not failed[back.id] then
		id, from = back.id, back.position
	else
		for _ = 1, 8 do -- not the same track twice running (when there's a choice)
			if id ~= lastId[list] then
				break
			end
			id = ids[rng:NextInteger(1, #ids)]
		end
	end
	resume[list] = nil
	lastId[list] = id
	-- A measured track plays at its list's level; one not measured yet at the default
	local target = Music.target[list]
	local loudness = Music.loudness[id]
	trackVolume = if target
			and loudness
			and loudness > 0
		then math.clamp(target / loudness, 0.02, 0.6)
		else Music.volume
	local old = current
	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.SoundId = `rbxassetid://{id}`
	sound.Volume = 0
	sound.SoundGroup = group
	sound.Parent = group
	if from > 0 then
		local function seek()
			if sound.TimeLength > from + 5 then
				sound.TimePosition = from
			end
		end
		if sound.IsLoaded then
			seek()
		else
			sound.Loaded:Once(seek)
		end
	end
	sound:Play()
	fade(sound, level(), Music.fadeSeconds)
	current, currentList, currentId, startedAt, endedAt = sound, list, id, os.clock(), nil
	sound.Ended:Once(function()
		if current == sound then
			endedAt = os.clock()
		end
	end)
	if old then
		fade(old, 0, Music.fadeSeconds)
		task.delay(Music.fadeSeconds + 0.2, function()
			old:Destroy()
		end)
	end
end

local function step()
	local list = wanted()
	local now = os.clock()
	if list ~= candidate then
		candidate, candidateSince = list, now
	end
	-- A boss takes over at once; anywhere else has to hold a moment first
	local settled = currentList == nil
		or now - candidateSince >= (if Music.bosses[bossId or ""] == list then 1 else Music.settleSeconds)
	local sound = current
	if sound == nil or (list ~= currentList and settled) then
		play(list)
	elseif endedAt and now - endedAt >= Music.gapSeconds then
		play(currentList :: string) -- the next track
	elseif not sound.IsLoaded and now - startedAt > LOAD_SECONDS then
		failed[currentId] = true
		if not warned[currentId] then
			warned[currentId] = true
			warn(
				`[MusicController] {sound.SoundId} didn't load (not public, or not allowed here); skipping it`
			)
		end
		play(currentList :: string)
	end
end

local function apply(seconds: number)
	if current then
		fade(current, level(), seconds)
	end
end

-- Quieter while a roll reveal plays (RollController)
function MusicController.duck(on: boolean)
	if ducked ~= on then
		ducked = on
		apply(0.6)
	end
end

-- How near a world boss is (0..1) and which one (BossController, beside the dread)
function MusicController.setBoss(amount: number, id: string?)
	boss = math.clamp(amount, 0, 1)
	bossId = id
end

-- Plays `list` wherever the camera goes until it's let go (nil): the start screen's
-- shots cut round the sea every few seconds, and the music stays the hub's meanwhile
function MusicController.hold(list: string?)
	held = list
end

-- Music off or on for this session
function MusicController.setMuted(on: boolean)
	muted = on
	apply(0.5)
end

function MusicController.muted(): boolean
	return muted
end

function MusicController.start()
	local any = false
	for _, ids in Music.lists do
		if #ids > 0 then
			any = true
		end
	end
	if not any then
		return
	end
	local g = Instance.new("SoundGroup")
	g.Name = "Music"
	g.Parent = SoundService
	group = g
	task.spawn(function()
		while true do
			local ok, problem = pcall(function(): any
				step()
				return nil
			end)
			if not ok then
				warn(`[MusicController] {problem}`)
			end
			task.wait(CHECK_SECONDS)
		end
	end)
end

return MusicController
