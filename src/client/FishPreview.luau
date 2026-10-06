--!strict
-- A fish turning slowly in a ViewportFrame, dressed in a shade, parts and a
-- variant: the roll reveal, the wardrobe and the Shade Dyer show cosmetics on the
-- player's own fish this way. Built with the same FishBuilder and Cosmetics as the
-- real fish, so what you see is what you get.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local FishBuilder = require(ReplicatedStorage.Shared.FishBuilder)

local LENGTH = 4

local DEFAULT_LOOK: FishBuilder.Look = {
	back = Color3.fromRGB(52, 92, 132),
	belly = Color3.fromRGB(214, 226, 234),
	fin = Color3.fromRGB(78, 132, 176),
}

export type Preview = {
	frame: ViewportFrame,
	show: (self: Preview, dress: Cosmetics.Dress) -> (),
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
	frame.Ambient = Color3.fromRGB(150, 172, 186)
	frame.LightColor = Color3.fromRGB(255, 252, 244)
	frame.LightDirection = Vector3.new(-0.5, -1, -0.6)
	local world = Instance.new("WorldModel")
	world.Parent = frame
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.2, 9.5), Vector3.new(0, 0, 0))
	camera.Parent = frame
	frame.CurrentCamera = camera
	frame.Parent = parent

	local fish: Model? = nil
	local root: Part? = nil
	local body: Model? = nil
	local shade: string? = nil
	local joints: { [string]: Motor6D } = {}
	local spin = 0
	local connection: RBXScriptConnection? = nil

	local preview = {} :: Preview
	preview.frame = frame

	function preview.show(_self: Preview, dress: Cosmetics.Dress)
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
		local look = myLook()
		local newBody = FishBuilder.build(model, newRoot, look, LENGTH)
		Cosmetics.apply(newBody, look, dress, LENGTH)
		FishBuilder.applyScale(newBody, LENGTH)
		model.Parent = world
		fish, root, body, shade = model, newRoot, newBody, dress.shade
		joints = FishBuilder.joints(newBody)
	end

	function preview.destroy(_self: Preview)
		if connection then
			connection:Disconnect()
		end
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
		currentRoot.CFrame = CFrame.Angles(0, math.rad(-70) + math.sin(spin) * 0.6, 0)
		local stalk = joints.Stalk
		if stalk then
			stalk.Transform = CFrame.Angles(0, math.sin(clock * 5) * 0.35, 0)
		end
		local mid = joints.Body3
		if mid then
			mid.Transform = CFrame.Angles(0, math.sin(clock * 5 - 0.8) * 0.18, 0)
		end
		Cosmetics.animate(currentBody, shade, clock)
	end)
	return preview
end

return FishPreview
