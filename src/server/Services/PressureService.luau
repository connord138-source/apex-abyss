--!strict
-- Depth pressure (Config/Pvp `pressure`, Shared/Pressure): a fish below the crush
-- depth for its level (plus its Pressure Hide) feels the pressure build for a few
-- seconds, then loses a share of its health every second until it rises. Never in
-- the hub or the dens (they're dug below the shelf). The character's `Pressure`
-- attribute (0 = fine, up to 1 = crushing) and `CrushY` drive the HUD's warning.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Pressure = require(ReplicatedStorage.Shared.Pressure)
local Size = require(ReplicatedStorage.Shared.Size)
local Guard = require(script.Parent.Parent.Guard)
local Progress = require(script.Parent.Parent.Progress)
local DataService = require(script.Parent.DataService)
local FishService = require(script.Parent.FishService)
local HuntService = require(script.Parent.HuntService)

local tune = Config.Pvp.pressure
local TICK = 0.5

local PressureService = {}

local built: { [Player]: number } = {} -- seconds under the crush depth

-- The level a fish counts as against the pressure (its banked level and its hide)
function PressureService.level(data: DataService.PlayerData): number
	return Size.level(Progress.mass(data)) + Perks.depth(data.upgrades)
end

function PressureService.start()
	Guard.loop("PressureService", TICK, function()
		for player, session in HuntService.sessions() do
			local character, root = FishService.character(player)
			local data = DataService.get(player)
			if character == nil or root == nil or data == nil then
				built[player] = nil
				continue
			end
			local band = Pressure.limit(PressureService.level(data))
			local deep = session.alive and not session.inHub and band ~= nil and root.Position.Y < band.y
			if not deep then
				if built[player] then
					built[player] = nil
					character:SetAttribute("Pressure", 0)
				end
				continue
			end
			local seconds = (built[player] or 0) + TICK
			built[player] = seconds
			character:SetAttribute("Pressure", math.min(seconds / tune.grace, 1))
			character:SetAttribute("CrushY", if band then band.y else 0)
			if seconds > tune.grace then
				HuntService.damage(player, tune.damage * TICK, "the crushing deep", true)
			end
		end
		for player in built do
			if HuntService.sessions()[player] == nil then
				built[player] = nil
			end
		end
	end)
end

return PressureService
