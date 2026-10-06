--!strict
-- One place for every device's controls, so the swim, camera and HUD code never
-- cares what the player is holding.
--
--   PC:       mouse looks (cursor locked; hold Alt to free it), WASD swims toward
--             the camera, Space / Ctrl up and down, Shift or Q uses the ability (the
--             Nibbler's Dash), click or F bites
--   Gamepad:  left stick swims, right stick looks, RT ability, RB or X bites,
--             A / B up and down
--   Touch:    Roblox's thumbstick swims, drag anywhere else to look, the HUD's
--             Dash and Bite buttons
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)

local cameraTuning = Config.Tuning.camera

local Input = {
	-- () — the bite button was pressed
	bite = Signal.new(),
	-- () — the ability button was pressed (the Nibbler's Dash)
	ability = Signal.new(),
	-- Set by menus (none yet) to free the mouse
	cursorWanted = false,
}

local controls: any = nil
local touchLook = Vector2.zero
local lookTouches: { [InputObject]: boolean } = {}
local stick2 = Vector2.zero
local held: { [string]: boolean } = {}

local function setHeld(key: Enum.KeyCode | Enum.UserInputType, down: boolean)
	held[key.Name] = down
end

function Input.start()
	local player = Players.LocalPlayer
	task.spawn(function()
		local module =
			require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
		controls = module:GetControls()
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.Touch then
			if not processed then
				lookTouches[input] = true
			end
			return
		end
		if processed then
			return
		end
		setHeld(input.KeyCode, true)
		setHeld(input.UserInputType, true)
		local key = input.KeyCode
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or key == Enum.KeyCode.F
			or key == Enum.KeyCode.ButtonR1
			or key == Enum.KeyCode.ButtonX
		then
			Input.bite:fire()
		elseif key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.Q or key == Enum.KeyCode.ButtonR2 then
			Input.ability:fire()
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			lookTouches[input] = nil
			return
		end
		setHeld(input.KeyCode, false)
		setHeld(input.UserInputType, false)
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch and lookTouches[input] then
			touchLook += Vector2.new(input.Delta.X, input.Delta.Y)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local position = Vector2.new(input.Position.X, -input.Position.Y)
			stick2 = if position.Magnitude < 0.15 then Vector2.zero else position
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		table.clear(held)
		table.clear(lookTouches)
	end)
end

local function down(name: string): boolean
	return held[name] == true
end

-- The swim stick: x = right, z = forward (negative), from WASD, the left stick or
-- the touch thumbstick.
function Input.moveVector(): Vector3
	if controls then
		local ok, vector = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(vector) == "Vector3" then
			return vector
		end
	end
	return Vector3.zero
end

-- Up/down: +1, 0 or -1.
function Input.vertical(): number
	local up = down("Space") or down("ButtonA") or held.TouchUp == true
	local dive = down("LeftControl") or down("C") or down("ButtonB") or held.TouchDown == true
	return (if up then 1 else 0) - (if dive then 1 else 0)
end

-- The HUD's held touch buttons ("Up", "Down").
function Input.setTouchButton(name: string, isDown: boolean)
	held["Touch" .. name] = isDown
end

-- Whether the mouse should be locked for looking right now.
function Input.wantsMouseLock(): boolean
	return UserInputService.MouseEnabled
		and not UserInputService.TouchEnabled
		and not Input.cursorWanted
		and not down("LeftAlt")
		and not down("RightAlt")
end

-- Look input since the last call, as (yaw, pitch) radians. Call once per frame.
function Input.consumeLook(dt: number): Vector2
	local look = Vector2.zero
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		look += UserInputService:GetMouseDelta() * cameraTuning.mouseSensitivity
	end
	look += touchLook * cameraTuning.touchSensitivity
	touchLook = Vector2.zero
	look += stick2 * cameraTuning.gamepadSpeed * dt
	return look
end

function Input.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Input.isGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

return Input
