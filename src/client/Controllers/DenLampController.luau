--!strict
-- Den lamps light the storey you're looking at (owner, 2026-11-04: the fish's white
-- glow). A PointLight passes through rock, so the Hall's lamps, 26 studs under the
-- Nook's floor, lit a fish from below on top of the Nook's own: over a pool at
-- 20 lamps, its colour clipped and pale skins read plain white. DenBuilder tags each
-- lamp's light (`DenLamp`) and gives it `Storeys`, a mask of the storeys it shows
-- from: its own, plus the next one by a shaft, so a look down a shaft still finds a
-- lit room. This follows the camera, since Build mode's view changes storey with the
-- fish left behind. It also spares a big den about half its lights.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DenSpace = require(ReplicatedStorage.Shared.DenSpace)
local Layout = require(ReplicatedStorage.Shared.Layout)

local TAG = "DenLamp"
local CHECK_EVERY = 0.2
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local DenLampController = {}

-- The fades running, each cleared as it ends
local tweens: { [PointLight]: Tween } = {}
-- The bit of the storey being looked at; nil outside a den, where every lamp's on
local current: number? = nil

local function shows(light: PointLight): boolean
	local mask = light:GetAttribute("Storeys")
	return current == nil or typeof(mask) ~= "number" or bit32.btest(mask, current)
end

local function apply(light: PointLight, fade: boolean)
	-- (from the server's attribute: a fade changes the live value, and a weak table
	-- loses an Instance key while the lamp's still there, leaving lamps stuck at 0)
	local bright = light:GetAttribute("Full")
	local brightness = if typeof(bright) == "number" then bright else light.Brightness
	local playing = tweens[light]
	if playing then
		playing:Cancel()
		tweens[light] = nil
	end
	local on = shows(light)
	if not fade then
		light.Enabled = on
		light.Brightness = brightness
		return
	end
	light.Enabled = true
	local tween = TweenService:Create(light, FADE, { Brightness = if on then brightness else 0 })
	tweens[light] = tween
	tween.Completed:Once(function(state)
		if tweens[light] == tween then
			tweens[light] = nil
		end
		if state == Enum.PlaybackState.Completed then
			light.Enabled = on
		end
	end)
	tween:Play()
end

-- The storey under the camera, as a bit of the mask
local function storeyBit(): number?
	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local at = camera.CFrame.Position
	local den = Layout.denAt(at)
	if den == nil then
		return nil
	end
	local storey = DenSpace.storeyAt(DenSpace.toLocal(DenSpace.frame(den), at).Y)
	return if storey then bit32.lshift(1, storey - 1) else nil
end

function DenLampController.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance)
		if instance:IsA("PointLight") then
			apply(instance, false)
		end
	end)
	for _, instance in CollectionService:GetTagged(TAG) do
		if instance:IsA("PointLight") then
			apply(instance, false)
		end
	end
	local waited = 0
	RunService.Heartbeat:Connect(function(dt)
		waited += dt
		if waited < CHECK_EVERY then
			return
		end
		waited = 0
		local now = storeyBit()
		if now == current then
			return
		end
		current = now
		for _, instance in CollectionService:GetTagged(TAG) do
			if instance:IsA("PointLight") then
				apply(instance, true)
			end
		end
	end)
end

return DenLampController
