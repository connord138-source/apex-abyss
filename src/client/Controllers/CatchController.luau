--!strict
-- Rare catches on this client (Config/Catch; CatchService sends a summary of every
-- catch that's news, `Caught`): a toast for each rare catch with its coral and the
-- fish's catch-track count, a NEW IN THE CATCH LOG note for a first, and a banner
-- when a catch unlocks a skin or lands the Catch of the Week.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local HudController = require(script.Parent.HudController)

local CatchConfig = Config.Catch

local CatchController = {}

local gui: ScreenGui

local function preyName(id: string): string
	local prey = Config.Prey.byId[id]
	return if prey then prey.name else id
end

local function shadeName(id: string): string
	local shade = Config.Shades.byId[id]
	return if shade then shade.name else id
end

local function speciesName(id: string?): string
	local species = if id then Config.Species.byId[id] else nil
	return if species then species.name else "fish"
end

-- A big centred line or two for a skin unlock or the Catch of the Week
local function banner(kicker: string, title: string, sub: string, color: Color3)
	local old = gui:FindFirstChild("CatchBanner")
	if old then
		old:Destroy()
	end
	local holder = Instance.new("Frame")
	holder.Name = "CatchBanner"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	local height = gui.AbsoluteSize.Y / Ui.scaleOf(gui)
	holder.Position = UDim2.new(0.5, 0, 0, math.max(height * 0.24, Ui.bossBottom() + 70))
	holder.Size = UDim2.fromOffset(680, 84)
	holder.BackgroundTransparency = 1
	local labels = {
		Ui.label(holder, "Kicker", kicker, Ui.FONT_BOLD, 16, color, UDim2.new(1, 0, 0, 20)),
		Ui.label(
			holder,
			"Title",
			title,
			Ui.FONT_HEAVY,
			38,
			Ui.color.text,
			UDim2.new(1, 0, 0, 42),
			UDim2.fromOffset(0, 20)
		),
		Ui.label(
			holder,
			"Sub",
			sub,
			Ui.FONT_BOLD,
			17,
			Ui.color.muted,
			UDim2.new(1, 0, 0, 22),
			UDim2.fromOffset(0, 64)
		),
	}
	for _, label in labels do
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextTransparency = 1
		label.TextStrokeTransparency = 1
	end
	holder.Parent = gui
	for _, label in labels do
		Ui.tween(label, 0.45, { TextTransparency = 0, TextStrokeTransparency = 0.5 })
	end
	task.delay(4.5, function()
		if holder.Parent == nil then
			return
		end
		for _, label in labels do
			Ui.tween(label, 0.7, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
		task.wait(0.75)
		holder:Destroy()
	end)
end

local function onCaught(summary: { [string]: any })
	if typeof(summary) ~= "table" or typeof(summary.prey) ~= "string" then
		return
	end
	local prey = preyName(summary.prey)
	local rare = if typeof(summary.rarity) == "string" then CatchConfig.byId[summary.rarity] else nil
	if rare then
		local tier = Config.Tiers.byId[rare.tier]
		Sfx.play(`Roll{rare.tier}`, { volume = 0.45 })
		local text = `{string.upper(rare.name)} {string.upper(prey)}`
		if typeof(summary.coral) == "number" and summary.coral > 0 then
			text ..= ` · +{Format.number(summary.coral)} coral`
		end
		if typeof(summary.track) == "number" and typeof(summary.need) == "number" and summary.skin == nil then
			if summary.track < summary.need then
				text ..= ` · {rare.name} skin {summary.track}/{summary.need}`
			end
		end
		HudController.toast(text, if tier and tier.order >= 4 then "rare" else "good")
	end
	if typeof(summary.first) == "number" then
		local label = if rare then `{rare.name} {prey}` else prey
		HudController.toast(
			`NEW IN THE CATCH LOG · {label} · +{Format.number(summary.first)} coral`,
			"good"
		)
	end
	-- A new biggest of this species at this rarity: said for rare ones and trophy-size
	-- plain ones (a slightly bigger minnow every few bites would be noise)
	local preyDef = Config.Prey.byId[summary.prey]
	local trophy = preyDef ~= nil and typeof(summary.mass) == "number" and summary.mass >= preyDef.mass * 1.9
	if typeof(summary.record) == "number" and typeof(summary.mass) == "number" and (rare or trophy) then
		local label = if rare then `{rare.name} {prey}` else prey
		HudController.toast(
			`NEW BIGGEST · {Format.catchMass(summary.mass)} {label} (was {Format.catchMass(summary.record)})`,
			"good"
		)
	end
	if summary.row then
		HudController.toast(
			`CATCH LOG ROW DONE · every {prey} · +{Format.number(CatchConfig.rowComplete.coral)} coral, {CatchConfig.rowComplete.shells} shells`,
			"rare"
		)
	end
	if typeof(summary.title) == "string" then
		HudController.toast(`TITLE EARNED · {summary.title}`, "rare")
	end
	if typeof(summary.skin) == "string" and rare then
		Sfx.play("LevelUp", { volume = 0.7 })
		banner(
			"SKIN UNLOCKED",
			`{string.upper(shadeName(summary.skin))} {string.upper(speciesName(summary.species))}`,
			`{summary.need} {rare.name} catches as your {speciesName(summary.species)} · wear it in the WARDROBE`,
			rare.color
		)
	end
	if typeof(summary.weeklyCoral) == "number" then
		Sfx.play("RollLegendary", { volume = 0.6 })
		local got = `+{Format.number(summary.weeklyCoral)} coral, {summary.weeklyShells or 0} shells`
		if typeof(summary.weeklySkin) == "string" then
			got ..= ` · the {shadeName(summary.weeklySkin)} skin for your {speciesName(summary.species)}`
		end
		banner(
			"CATCH OF THE WEEK",
			`{string.upper(if rare then rare.name else "")} {string.upper(prey)}`,
			got,
			if rare then rare.color else Ui.color.haul
		)
	end
end

function CatchController.start()
	gui = Ui.screen("Catches", Players.LocalPlayer:WaitForChild("PlayerGui"), 7)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local caught = remotes:WaitForChild("Caught") :: RemoteEvent
	caught.OnClientEvent:Connect(onCaught)
end

return CatchController
