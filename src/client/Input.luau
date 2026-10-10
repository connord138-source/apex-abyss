--!strict
-- One place for every device's controls, so the swim, camera and HUD code never
-- cares what the player is holding.
--
--   PC:       mouse looks (cursor locked; tap Alt or M to free it for the HUD and
--             menus, tap again or click the game to lock it; hold Alt for a
--             moment's cursor), the wheel zooms,
--             WASD or the arrows swim toward the camera, Space / Ctrl up and
--             down, Shift or Q uses the ability (the Nibbler's Dash), click or F
--             bites, E shops at a stall
--   Gamepad:  left stick up swims ahead (further = faster), sideways turns, down
--             backs up; right stick aims (up and down too); RT ability, RB or X
--             bites, A / B up and down, Y shops at a stall
--   Touch:    the same stick under the left thumb (bottom left), drag anywhere
--             else to aim, the HUD's Dash and Bite buttons
--
-- The move vector is built here from the keys and sticks, not from Roblox's
-- PlayerModule: that module isn't inserted for this game's custom fish character
-- (playtest 2026-10-06: WASD did nothing while the client waited on it forever).
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)

local cameraTuning = Config.Tuning.camera

local Input = {
	-- () — the bite button was pressed
	bite = Signal.new(),
	-- () — the ability button was pressed (the Nibbler's Dash)
	ability = Signal.new(),
	-- Set by menus to free the mouse
	cursorWanted = false,
	-- Alt or M tapped: the cursor stays free for the HUD buttons and panels until
	-- Alt or M again, or a click on the game (owner, 2026-10-10: "since the cursor is
	-- tied to swimming there is no way to click on ui panels"). Studio's own window
	-- can take an Alt tap, so M does the same.
	cursorToggled = false,
	-- (free: boolean) — the player freed or locked the cursor (the HUD's chip)
	cursorChanged = Signal.new(),
	-- Set while the start screen is up: the fish doesn't swim, look, bite or dash
	locked = false,
}

local ALT_TAP = 0.35 -- seconds: an Alt let go sooner than this toggles the cursor
local altDownAt: number? = nil

local touchLook = Vector2.zero
local lookTouches: { [InputObject]: boolean } = {}
local stick1 = Vector2.zero
local stick2 = Vector2.zero
local stickPad: Enum.UserInputType? = nil -- the gamepad that last moved a stick
local touchMove = Vector2.zero
local wheel = 0
local held: { [string]: boolean } = {}

local function setHeld(key: Enum.KeyCode | Enum.UserInputType, down: boolean)
	held[key.Name] = down
end

-- A stick past its dead zone, rescaled so it still reaches 1 at full tilt.
local function deadZone(position: Vector2): Vector2
	local magnitude = position.Magnitude
	if magnitude < 0.15 then
		return Vector2.zero
	end
	return position.Unit * math.min((magnitude - 0.15) / 0.85, 1)
end

-- The sticks, read from the pad's own state every frame as well as from events: a
-- release that sends no near-zero InputChanged (Studio's Controller Emulator sends
-- InputChanged (0, 1), then InputEnded) left the fish swimming and the camera
-- spinning on their own (playtest 2026-10-07), so a missed event can never stick.
local function pollSticks()
	local pad = stickPad
	if pad == nil then
		return
	end
	if not UserInputService:GetGamepadConnected(pad) then
		stickPad, stick1, stick2 = nil, Vector2.zero, Vector2.zero
		return
	end
	for _, state in UserInputService:GetGamepadState(pad) do
		if state.KeyCode == Enum.KeyCode.Thumbstick1 then
			stick1 = deadZone(Vector2.new(state.Position.X, -state.Position.Y))
		elseif state.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick2 = deadZone(Vector2.new(state.Position.X, -state.Position.Y))
		end
	end
end

-- Frees or locks the cursor for the player (the Alt / M toggle)
local function setCursor(free: boolean)
	-- (not under the start screen: any key there just dives in)
	if Input.cursorToggled == free or (free and Input.locked) then
		return
	end
	Input.cursorToggled = free
	if free then
		-- Free it now, not on the camera's next frame, so a click straight after lands
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	Input.cursorChanged:fire(free)
end

function Input.start()
	-- The HUD's own stick and buttons replace Roblox's touch controls (its dynamic
	-- thumbstick drew a second ring beside ours, playtest 2026-10-07)
	GuiService.TouchControlsEnabled = false
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
		if key == Enum.KeyCode.LeftAlt or key == Enum.KeyCode.RightAlt then
			-- Free the cursor now, not on the camera's next frame, so a click that
			-- follows straight after lands where it's aimed (a tap toggles it on release)
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
			altDownAt = os.clock()
		elseif key == Enum.KeyCode.M then
			setCursor(not Input.cursorToggled)
		end
		-- With the cursor freed, a click on the game (not on a button) takes the mouse
		-- back for swimming; it doesn't bite
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			and Input.cursorToggled
			and not Input.cursorWanted
		then
			setCursor(false)
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or key == Enum.KeyCode.F
			or key == Enum.KeyCode.ButtonR1
			or key == Enum.KeyCode.ButtonX
		then
			if not Input.locked then
				Input.bite:fire()
			end
		elseif key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.Q or key == Enum.KeyCode.ButtonR2 then
			if not Input.locked then
				Input.ability:fire()
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			lookTouches[input] = nil
			return
		end
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			stick1 = Vector2.zero
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick2 = Vector2.zero
		end
		setHeld(input.KeyCode, false)
		setHeld(input.UserInputType, false)
		if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
			local downAt = altDownAt
			altDownAt = nil
			if downAt and os.clock() - downAt <= ALT_TAP then
				setCursor(not Input.cursorToggled)
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.Touch and lookTouches[input] then
			touchLook += Vector2.new(input.Delta.X, input.Delta.Y)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			if not processed then
				wheel += input.Position.Z
			end
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
			stickPad = input.UserInputType
			stick1 = deadZone(Vector2.new(input.Position.X, -input.Position.Y))
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stickPad = input.UserInputType
			stick2 = deadZone(Vector2.new(input.Position.X, -input.Position.Y))
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		table.clear(held)
		table.clear(lookTouches)
		stick1, stick2, touchMove = Vector2.zero, Vector2.zero, Vector2.zero
	end)
	-- Before the camera and the swim read them this frame
	RunService:BindToRenderStep("ApexSticks", Enum.RenderPriority.Input.Value, pollSticks)
end

local function down(name: string): boolean
	return held[name] == true
end

local function axis(positive: boolean, negative: boolean): number
	return (if positive then 1 else 0) - (if negative then 1 else 0)
end

-- Keyboard swimming: x = right, z = forward (negative), relative to the camera, from
-- WASD or the arrow keys. Length at most 1. (The owner likes PC as it is: A/D slide
-- the fish sideways while the mouse aims.)
function Input.moveVector(): Vector3
	if Input.locked then
		return Vector3.zero
	end
	local keys = Vector2.new(
		axis(down("D") or down("Right"), down("A") or down("Left")),
		axis(down("S") or down("Down"), down("W") or down("Up"))
	)
	if keys.Magnitude > 1 then
		keys = keys.Unit
	end
	return Vector3.new(keys.X, 0, keys.Y)
end

-- Stick swimming (owner, 2026-10-07: controller and phone): the left stick or the
-- touch stick is a throttle and a rudder. Returns throttle (+1 full ahead, -1 back
-- up) and steer (+1 turn right); the right stick or a screen drag aims up and down.
function Input.drive(): (number, number)
	if Input.locked then
		return 0, 0
	end
	-- The left stick moves the selection while a menu button is selected
	-- (stick1 is stored with y flipped, so pushing up is negative)
	local stick = if GuiService.SelectedObject then Vector2.zero else stick1
	local drive = stick + touchMove
	return math.clamp(-drive.Y, -1, 1), math.clamp(drive.X, -1, 1)
end

-- The HUD's touch thumbstick: x = right, y = back (screen down), length at most 1.
function Input.setTouchMove(vector: Vector2)
	touchMove = vector
end

-- Up/down: +1, 0 or -1.
function Input.vertical(): number
	if Input.locked then
		return 0
	end
	local up = down("Space") or down("ButtonA")
	local dive = down("LeftControl") or down("C") or down("ButtonB")
	return (if up then 1 else 0) - (if dive then 1 else 0)
end

-- Whether the mouse should be locked for looking right now.
function Input.wantsMouseLock(): boolean
	return UserInputService.MouseEnabled
		and not UserInputService.TouchEnabled
		and not Input.cursorWanted
		and not Input.cursorToggled
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
	return if Input.locked then Vector2.zero else look
end

-- Mouse wheel notches since the last call (up is positive, meaning zoom in).
function Input.consumeZoom(): number
	local notches = wheel
	wheel = 0
	return notches
end

function Input.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Input.isGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

return Input
