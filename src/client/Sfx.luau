--!strict
-- Plays the game's sound pack (Config.Sounds): one uploaded audio file with every
-- sound back to back, each played from its own stretch (Sound.PlaybackRegion).
-- Until the pack's id is set, the game stays quiet apart from a few cues pinged
-- with a built-in sound, so playtests still get feedback.
--   Sfx.play("Bank")                                     -- on the player's screen
--   Sfx.play("Bite", { parent = part, volume = 0.5 })    -- 3D, from a part
--   Sfx.loop("AmbientDeep", 0.3)                         -- a bed, looping (returns the Sound)
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)

local PING = "rbxasset://sounds/electronicpingshort.wav"

-- `range`: how far a sound played from a part carries (studs, default 120)
export type Options = { volume: number?, pitch: number?, parent: Instance?, range: number? }

-- Fallback tunes: { delay, pitch, volume } notes of the ping
local FALLBACK: { [string]: { { number } } } = {
	Bank = { { 0, 1, 0.5 }, { 0.1, 1.26, 0.5 }, { 0.2, 1.5, 0.5 }, { 0.3, 2, 0.6 } },
	LevelUp = { { 0, 0.75, 0.6 }, { 0.12, 1, 0.6 }, { 0.24, 1.5, 0.7 } },
	Shell = { { 0, 2, 0.25 } },
	GoldenShell = { { 0, 2, 0.3 }, { 0.07, 2.5, 0.3 }, { 0.14, 3, 0.3 } },
	Warning = { { 0, 0.5, 0.5 }, { 0.3, 0.5, 0.5 } },
	TooBig = { { 0, 1.5, 0.3 }, { 0.11, 1.8, 0.3 }, { 0.22, 2.2, 0.3 } },
	RollRare = { { 0, 1, 0.5 }, { 0.09, 1.26, 0.5 }, { 0.18, 1.5, 0.6 } },
	RollEpic = { { 0, 1, 0.6 }, { 0.08, 1.26, 0.6 }, { 0.16, 1.5, 0.6 }, { 0.24, 2, 0.7 } },
	RollLegendary = {
		{ 0, 0.5, 0.8 },
		{ 0.12, 0.75, 0.7 },
		{ 0.24, 1, 0.7 },
		{ 0.38, 1.5, 0.8 },
		{ 0.5, 2, 0.8 },
	},
	RollMythic = {
		{ 0, 0.45, 0.9 },
		{ 0.12, 0.67, 0.8 },
		{ 0.24, 0.9, 0.8 },
		{ 0.38, 1.35, 0.8 },
		{ 0.5, 1.8, 0.9 },
	},
	RollAbyssal = {
		{ 0, 0.35, 1 },
		{ 0.3, 0.5, 0.8 },
		{ 0.45, 0.75, 0.8 },
		{ 0.6, 1, 0.8 },
		{ 0.75, 1.5, 0.9 },
	},
	RollTrophy = { { 0, 0.6, 0.7 }, { 0.15, 0.9, 0.7 }, { 0.3, 1.2, 0.8 } },
	BossWarning = { { 0, 0.25, 0.8 }, { 0.5, 0.25, 0.8 }, { 1, 0.25, 0.8 } },
	BossRise = { { 0, 0.3, 1 }, { 0.2, 0.25, 0.9 } },
	BossDefeat = { { 0, 0.5, 0.8 }, { 0.12, 0.75, 0.8 }, { 0.24, 1, 0.8 }, { 0.36, 1.5, 0.9 } },
	ChestOpen = { { 0, 1, 0.5 }, { 0.1, 1.5, 0.5 }, { 0.2, 2, 0.5 } },
}

local template: Sound? = nil
local warned = false

local Sfx = {}

local function soundId(): string?
	local id = Config.Sounds.id
	if id and id > 0 then
		return `rbxassetid://{id}`
	end
	if not warned then
		warned = true
		warn("[Sfx] Config/Sounds.luau id is 0: upload assets/audio/apex_sfx.ogg and paste its id for sound")
	end
	return nil
end

local function place(sound: Sound, parent: Instance?, range: number?)
	if parent and (parent:IsA("BasePart") or parent:IsA("Attachment")) then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 14
		sound.RollOffMaxDistance = range or 120
	end
	sound.Parent = parent or SoundService
end

-- Loads the pack in the background so the first cue isn't silent.
function Sfx.preload()
	local id = soundId()
	if id == nil or template then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "SfxPack"
	sound.SoundId = id
	sound.Parent = SoundService
	template = sound
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)
	end)
end

-- Seconds the sound lasts (at pitch 1), or 0 if it doesn't exist.
function Sfx.length(name: string): number
	local region = Config.Sounds.regions[name]
	return if region then region[2] else 0
end

function Sfx.play(name: string, options: Options?)
	local volume = if options and options.volume then options.volume else 0.8
	local pitch = if options and options.pitch then options.pitch else 1
	local parent = if options then options.parent else nil
	local range = if options then options.range else nil
	local region = Config.Sounds.regions[name]
	local id = soundId()
	if id and region then
		Sfx.preload()
		local sound = if template then template:Clone() else Instance.new("Sound")
		sound.Name = name
		sound.SoundId = id
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(region[1], region[1] + region[2])
		sound.Volume = volume
		sound.PlaybackSpeed = pitch
		place(sound, parent, range)
		sound:Play()
		task.delay(region[2] / pitch + 0.25, function()
			sound:Destroy()
		end)
		return
	end
	local tune = FALLBACK[name]
	if tune == nil then
		return
	end
	for _, note in tune do
		task.delay(note[1], function()
			if parent and parent.Parent == nil then
				return -- its part went away (streamed out)
			end
			local sound = Instance.new("Sound")
			sound.SoundId = PING
			sound.Volume = note[3] * volume
			sound.PlaybackSpeed = note[2] * pitch
			place(sound, parent, range)
			sound:Play()
			sound.Ended:Once(function()
				sound:Destroy()
			end)
		end)
	end
end

-- A bed: the named region looping for as long as the Sound lives (nil without the
-- pack). The caller owns its Volume.
function Sfx.loop(name: string, volume: number, parent: Instance?): Sound?
	local region = Config.Sounds.regions[name]
	local id = soundId()
	if id == nil or region == nil then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(region[1], region[1] + region[2])
	sound.LoopRegion = NumberRange.new(region[1], region[1] + region[2])
	sound.Looped = true
	sound.Volume = volume
	sound.Parent = parent or SoundService
	sound:Play()
	return sound
end

return Sfx
