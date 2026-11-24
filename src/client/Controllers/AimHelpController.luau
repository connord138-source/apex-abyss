--!strict
-- Aim help on touch screens (owner, 2026-11-08: phones and tablets were 61% of new
-- players and lost 3-5x more of them than computers at every step that meant swimming
-- somewhere; a phone changes depth only by dragging the view or with UP / DOWN). A
-- few times a second it looks ahead of a fish played by touch for something to swim
-- into: the nearest fish it can swallow, filler food (shrimp, starfish, crabs) or a
-- shell, within `range` and `cone` of the way it's heading and no steeper above or
-- below than `steepest` (Config/Tuning `swim.touchHelp`). SwimController tilts the
-- swim toward it (`helpPoint`) while the stick is pushed. Not in the hub or a den,
-- where the tunnels and shafts are the player's to steer. Tests read the point off the
-- fish's client-side `AimHelp` attribute.
-- Gamepads too since 2026-11-20 (docs/GAMEPLAN.md round 1 item 14): a pad's left stick
-- steers the same way and its right stick aims the tilt, which a new player on a
-- console leaves alone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Input = require(script.Parent.Parent.Input)
local ForageController = require(script.Parent.ForageController)
local SchoolController = require(script.Parent.SchoolController)
local ShellController = require(script.Parent.ShellController)
local SwimController = require(script.Parent.SwimController)

local help = Config.Tuning.swim.touchHelp

local AimHelpController = {}

-- Where the swim should lean toward now, or nil
local function find(): Vector3?
	local root = SwimController.root()
	if root == nil or Input.locked or not (Input.usingTouch() or Input.isGamepad()) then
		return nil
	end
	local from = root.Position
	if Layout.inHub(from) or Layout.denAt(from) ~= nil then
		return nil
	end
	local aim = SwimController.aim or workspace.CurrentCamera.CFrame.Rotation
	local flat = Vector3.new(aim.LookVector.X, 0, aim.LookVector.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	flat = flat.Unit
	local cosCone = math.cos(help.cone)
	local tanSteepest = math.tan(help.steepest)
	-- Ahead within the cone, and not too steep (nor right under or over the fish)
	local function ahead(point: Vector3): boolean
		local to = point - from
		local flatTo = Vector3.new(to.X, 0, to.Z)
		local across = flatTo.Magnitude
		return across > 0.5
			and flatTo:Dot(flat) >= across * cosCone
			and math.abs(to.Y) <= across * tanSteepest
	end
	local length = SwimController.length()
	local range = help.range + help.perLength * length
	local best: Vector3? = nil
	local bestDistance = math.huge
	local function consider(point: Vector3?)
		if point and (point - from).Magnitude < bestDistance then
			best = point
			bestDistance = (point - from).Magnitude
		end
	end
	consider(SchoolController.nearestEdible(from, length, range, ahead))
	consider(ForageController.nearest(from, range, ahead))
	consider(ShellController.nearest(from, range, ahead))
	return best
end

function AimHelpController.start()
	task.spawn(function()
		while true do
			local ok, point = pcall(find)
			local found = if ok then point else nil
			SwimController.helpPoint = found
			-- (for tests: the fish's client-side `AimHelp` attribute is the point, or nil)
			local character = SwimController.character()
			if character and character:GetAttribute("AimHelp") ~= found then
				character:SetAttribute("AimHelp", found)
			end
			task.wait(help.every)
		end
	end)
end

return AimHelpController
