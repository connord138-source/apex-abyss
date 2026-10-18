--!strict
-- A fish turning slowly in a ViewportFrame, dressed in a shade, parts and a
-- variant: the roll reveal, the wardrobe and the Shade Dyer show cosmetics on the
-- player's own fish this way. Built with the same FishBuilder and Cosmetics as the
-- real fish, so what you see is what you get, and lit like the shallows with the
-- skin's glow, light and effects stood in for (PreviewFx: a viewport draws no
-- lights, bloom or particles; owner, 2026-10-18: "skins should also exactly match in
-- the example screen").
--
--   preview:show(dress, species?)  builds the fish (species: the player's own fish
--                                  by default)
--   preview:dress(dress)           puts a new dress on the fish already shown, in
--                                  place (no rebuild), as the game re-dresses a fish;
--                                  builds it if there's none yet
--   preview:setTurn(mode)          "sway" (default: the roll cards' hero pose, head to
--                                  the left, swaying), "spin" (a slow full turn) or
--                                  "still" (the hero pose, held)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local FishBuilder = require(ReplicatedStorage.Shared.FishBuilder)
local PreviewFx = require(script.Parent.PreviewFx)

local LENGTH = 4
local FOV = 30
local ELEVATION = math.rad(8) -- the camera looks down on the fish a little
local HERO = math.rad(118) -- head to the left and toward us
local SPIN_RATE = 0.45 -- radians a second, the slow full turn

local DEFAULT_LOOK: FishBuilder.Look = {
	back = Color3.fromRGB(52, 92, 132),
	belly = Color3.fromRGB(214, 226, 234),
	fin = Color3.fromRGB(78, 132, 176),
}

export type Turn = "sway" | "spin" | "still"

export type Preview = {
	frame: ViewportFrame,
	-- Shows a fish in a dress; `species` picks the body and colors (the player's
	-- current fish by default)
	show: (self: Preview, dress: Cosmetics.Dress, species: string?) -> (),
	-- A new dress on the fish shown, in place (the same species; builds one if none)
	dress: (self: Preview, dress: Cosmetics.Dress) -> (),
	-- How it turns: "sway" (default), "spin" (a slow full turn) or "still"
	setTurn: (self: Preview, mode: Turn) -> (),
	destroy: (self: Preview) -> (),
}

local FishPreview = {}

-- The player's own base colors (from their fish), or the default blue.
local function myLook(): FishBuilder.Look
	local character = Players.LocalPlayer.Character
	return (if character then FishBuilder.lookOf(character) else nil) or DEFAULT_LOOK
end

function FishPreview.new(parent: Instance, size: UDim2, position: UDim2, anchor: Vector2?): Preview
	local frame = Instance.new("ViewportFrame")
	frame.Name = "FishPreview"
	frame.BackgroundTransparency = 1
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor or Vector2.zero
	-- The shallows: a cool, slightly teal fill and sunlight from above and in front
	-- (PreviewFx tints the fill toward the light the skin casts)
	frame.Ambient = Color3.fromRGB(150, 176, 190)
	frame.LightColor = Color3.fromRGB(255, 250, 238)
	frame.LightDirection = Vector3.new(-0.45, -1, -0.6)
	local world = Instance.new("WorldModel")
	world.Parent = frame
	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.2, 9.5), Vector3.new(0, 0, 0))
	camera.Parent = frame
	frame.CurrentCamera = camera
	frame.Parent = parent
	local fx = PreviewFx.new(frame, { live = true })

	local fish: Model? = nil
	local root: Part? = nil
	local body: Model? = nil
	local shade: string? = nil
	local joints: { [string]: Motor6D } = {}
	local look: FishBuilder.Look? = nil
	local shownSpecies: string? = nil
	local spin = 0
	local turn: Turn = "sway"
	local yaw = HERO
	local connection: RBXScriptConnection? = nil
	-- The fish spins about its own middle, not its root
	local pivot = CFrame.identity
	-- Its size: horizontal reach while turning (the diagonal of its footprint) and height
	local reach, height = LENGTH / 2, LENGTH / 4

	-- Back the camera off until the turning fish fits the frame, whatever its shape
	-- (long fish were cropped side-on in a narrow frame, playtest 2026-10-06).
	local function frameCamera()
		local size = frame.AbsoluteSize
		local aspect = if size.Y > 1 then size.X / size.Y else 1
		local tanV = math.tan(math.rad(FOV / 2))
		local sinV = math.sin(math.atan(tanV))
		local sinH = math.sin(math.atan(tanV * aspect))
		local distance = math.max(reach / sinH, height / sinV) * 1.1
		camera.CFrame =
			CFrame.lookAt(Vector3.new(0, math.sin(ELEVATION), math.cos(ELEVATION)) * distance, Vector3.zero)
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(frameCamera)

	local preview = {} :: Preview
	preview.frame = frame

	-- Where the fish's middle is (it spins about that, not its root) and how big it
	-- is, measured square to the camera
	local function measure(model: Model, newRoot: Part)
		local held = newRoot.CFrame
		newRoot.CFrame = CFrame.new()
		local box, extents = model:GetBoundingBox()
		pivot = CFrame.new(-box.Position)
		reach = Vector2.new(extents.X, extents.Z).Magnitude / 2
		height = extents.Y / 2
		newRoot.CFrame = held
		frameCamera()
	end

	function preview.show(_self: Preview, dress: Cosmetics.Dress, speciesId: string?)
		if fish then
			fish:Destroy()
		end
		local model = Instance.new("Model")
		model.Name = "Fish"
		local newRoot = Instance.new("Part")
		newRoot.Name = "Root"
		newRoot.Anchored = true
		newRoot.Transparency = 1
		newRoot.Size = Vector3.one
		newRoot.CFrame = CFrame.new()
		newRoot.Parent = model
		local character = Players.LocalPlayer.Character
		local id = speciesId
			or (if character then character:GetAttribute("Species") :: string? else nil)
			or Config.Species.STARTER
		local species = Config.Species.byId[id] or Config.Species.byId[Config.Species.STARTER]
		local newLook = if speciesId
			then { back = species.back, belly = species.belly, fin = species.fin }
			else myLook()
		local newBody = FishBuilder.build(model, newRoot, newLook, LENGTH, species.plan)
		Cosmetics.apply(newBody, newLook, dress, LENGTH)
		FishBuilder.applyScale(newBody, LENGTH)
		model.Parent = world
		fish, root, body, shade = model, newRoot, newBody, dress.shade
		look, shownSpecies = newLook, speciesId
		joints = FishBuilder.joints(newBody)
		measure(model, newRoot)
		fx:setShade(dress.shade, model)
	end

	function preview.dress(self: Preview, dress: Cosmetics.Dress)
		local currentFish, currentRoot, currentBody, currentLook = fish, root, body, look
		if currentFish == nil or currentRoot == nil or currentBody == nil or currentLook == nil then
			self:show(dress, shownSpecies)
			return
		end
		Cosmetics.apply(currentBody, currentLook, dress, LENGTH)
		FishBuilder.applyScale(currentBody, LENGTH)
		shade = dress.shade
		joints = FishBuilder.joints(currentBody)
		measure(currentFish, currentRoot)
		fx:setShade(dress.shade, currentFish)
	end

	function preview.setTurn(_self: Preview, mode: Turn)
		turn = mode
	end

	function preview.destroy(_self: Preview)
		if connection then
			connection:Disconnect()
		end
		fx:destroy()
		frame:Destroy()
	end

	local clock = 0
	connection = RunService.RenderStepped:Connect(function(dt)
		clock += dt
		spin += dt * 0.6
		local currentRoot = root
		local currentBody = body
		if currentRoot == nil or currentBody == nil then
			return
		end
		-- The roll cards' hero pose: head to the left and toward us, swaying a little
		-- (owner, 2026-10-16: at -70° the fish faced right and away, "facing the wrong
		-- direction in the skin selector"); or a slow full turn, or held
		if turn == "spin" then
			yaw += dt * SPIN_RATE
		else
			-- (back to the pose by the short way round, eased, after a spin)
			local want = HERO + (if turn == "sway" then math.sin(spin) * 0.35 else 0)
			local gap = (want - yaw + math.pi) % (2 * math.pi) - math.pi
			yaw += gap * math.min(dt * 4, 1)
		end
		currentRoot.CFrame = CFrame.Angles(0, yaw, 0) * pivot
		local stalk = joints.Stalk
		if stalk then
			stalk.Transform = CFrame.Angles(0, math.sin(clock * 5) * 0.35, 0)
		end
		local mid = joints.Body3
		if mid then
			mid.Transform = CFrame.Angles(0, math.sin(clock * 5 - 0.8) * 0.18, 0)
		end
		Cosmetics.animate(currentBody, shade, clock)
		fx:step(clock)
	end)
	return preview
end

return FishPreview
