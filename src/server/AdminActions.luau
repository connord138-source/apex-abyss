--!strict
-- What the admin panel can do (Admin.luau checks who is asking). Every action takes
-- the asking admin, the target players and the panel's arguments (untrusted: checked
-- here), changes their saved data through the owning services, and answers with a
-- line of text for the panel. Nothing here touches other players' data except the
-- targets'.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catch = require(ReplicatedStorage.Shared.Catch)
local Config = require(ReplicatedStorage.Shared.Config)
local Seafloor = require(ReplicatedStorage.Shared.Seafloor)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Events)
local Net = require(script.Parent.Net)
local Progress = require(script.Parent.Progress)
local BossService = require(script.Parent.Services.BossService)
local BountyService = require(script.Parent.Services.BountyService)
local CatchService = require(script.Parent.Services.CatchService)
local LeaderboardService = require(script.Parent.Services.LeaderboardService)
local DataService = require(script.Parent.Services.DataService)
local EconomyService = require(script.Parent.Services.EconomyService)
local FishService = require(script.Parent.Services.FishService)
local GardenService = require(script.Parent.Services.GardenService)
local HuntService = require(script.Parent.Services.HuntService)
local MonetizationService = require(script.Parent.Services.MonetizationService)
local TreasureService = require(script.Parent.Services.TreasureService)
local TutorialService = require(script.Parent.Services.TutorialService)
local WardrobeService = require(script.Parent.Services.WardrobeService)

type PlayerData = DataService.PlayerData
type Handler = (Player, { Player }, ...any) -> string

local AdminActions = {}

local function amountOf(value: any, min: number): number?
	if typeof(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return nil
	end
	return math.max(min, math.floor(value))
end

local function each(targets: { Player }, fn: (Player, PlayerData) -> ()): number
	local count = 0
	for _, player in targets do
		local data = DataService.get(player)
		if data then
			fn(player, data)
			DataService.markDirty(player)
			count += 1
		end
	end
	return count
end

local function names(targets: { Player }): string
	if #targets == 1 then
		return targets[1].DisplayName
	end
	return `{#targets} players`
end

-- Coral and shells
local function addCoral(_admin: Player, targets: { Player }, amount: any): string
	local n = amountOf(amount, -1e12)
	if n == nil then
		return "Give an amount"
	end
	local count = each(targets, function(player, data)
		if n >= 0 then
			EconomyService.addCoral(player, n)
		else
			data.coral = math.max(0, data.coral + n)
		end
	end)
	return `Coral {if n >= 0 then "+" else ""}{n} for {count} player(s)`
end

local function setCoral(_admin: Player, targets: { Player }, amount: any): string
	local n = amountOf(amount, 0)
	if n == nil then
		return "Give an amount"
	end
	each(targets, function(_, data)
		data.coral = n
	end)
	return `Coral set to {n} for {names(targets)}`
end

local function addShells(_admin: Player, targets: { Player }, amount: any): string
	local n = amountOf(amount, 1)
	if n == nil then
		return "Give an amount"
	end
	each(targets, function(player)
		EconomyService.addShells(player, n)
	end)
	return `+{n} shells for {names(targets)}`
end

-- Level: sets the current species' banked mass to that level and respawns the fish
local function setLevel(_admin: Player, targets: { Player }, level: any): string
	local n = amountOf(level, 1)
	if n == nil then
		return "Give a level"
	end
	n = math.min(n, Config.Tuning.size.maxLevel)
	each(targets, function(player, data)
		local record = Progress.record(data)
		record.mass = Size.massForLevel(n)
		record.bestMass = math.max(record.bestMass, record.mass)
		FishService.respawnIn(player, 0)
	end)
	return `Level {n} ({names(targets)}): respawning at that size`
end

local function feed(_admin: Player, targets: { Player }, kg: any): string
	local n = amountOf(kg, 1)
	if n == nil then
		return "Give a mass in kg"
	end
	for _, player in targets do
		HuntService.feed(player, n)
	end
	return `+{n} kg Haul for {names(targets)}`
end

local function dna(_admin: Player, targets: { Player }, biomeId: any, amount: any): string
	local n = amountOf(amount, 1)
	if typeof(biomeId) ~= "string" or Config.Biomes.byId[biomeId] == nil or n == nil then
		return "Pick a biome and an amount"
	end
	each(targets, function(_, data)
		data.dna[biomeId] = (data.dna[biomeId] or 0) + n
	end)
	return `+{n} {Config.Biomes.byId[biomeId].name} DNA for {names(targets)}`
end

local function trophies(_admin: Player, targets: { Player }, currency: any, amount: any): string
	local n = amountOf(amount, 1)
	if typeof(currency) ~= "string" or n == nil then
		return "Pick a currency and an amount"
	end
	each(targets, function(_, data)
		data.trophies[currency] = (data.trophies[currency] or 0) + n
	end)
	-- "MegalodonTeeth" reads "Megalodon Teeth"
	local label = string.gsub(currency, "(%l)(%u)", "%1 %2")
	return `+{n} {label} for {names(targets)}`
end

local function wraps(_admin: Player, targets: { Player }, amount: any): string
	local n = amountOf(amount, 1)
	if n == nil then
		return "Give an amount"
	end
	for _, player in targets do
		local data = DataService.get(player)
		if data then
			data.charms.KelpWrap = math.min(Config.Tuning.heal.wrapMax, (data.charms.KelpWrap or 0) + n)
			DataService.markDirty(player)
		end
	end
	return `+{n} Kelp Wraps for {names(targets)} (carry cap applies)`
end

local function charm(_admin: Player, targets: { Player }, id: any, amount: any): string
	local def = if typeof(id) == "string" then Config.Shop.charmsById[id] else nil
	local n = amountOf(amount, 1) or 1
	if def == nil then
		return "Pick a charm"
	end
	each(targets, function(player, data)
		if def.seconds then
			data.boosts[def.id] = math.max(data.boosts[def.id] or 0, Timing.now()) + def.seconds * n
			WardrobeService.refresh(player)
		else
			data.charms[def.id] = (data.charms[def.id] or 0) + n
		end
	end)
	return `{def.name} ×{n} for {names(targets)}`
end

local function unlockSpecies(_admin: Player, targets: { Player }, id: any): string
	if id == "all" then
		each(targets, function(_, data)
			for _, species in Config.Species.list do
				data.unlocked[species.id] = true
			end
		end)
		return `Every species unlocked for {names(targets)}`
	end
	local species = if typeof(id) == "string" then Config.Species.byId[id] else nil
	if species == nil then
		return "Pick a species"
	end
	each(targets, function(_, data)
		data.unlocked[species.id] = true
	end)
	return `{species.name} unlocked for {names(targets)}`
end

local function allShades(_admin: Player, targets: { Player }): string
	each(targets, function(_, data)
		for _, species in Config.Species.list do
			for _, shade in Config.Shades.list do
				Progress.grantShade(data, shade.id, species.id)
			end
		end
		for _, part in Config.Exotics.parts do
			data.parts[part.id] = true
		end
		for _, variant in Config.Exotics.variants do
			data.variants[variant.id] = true
		end
	end)
	return `Every shade, part and variant for {names(targets)}`
end

local function giveMap(_admin: Player, targets: { Player }, tier: any): string
	if typeof(tier) ~= "string" or Config.Treasure.byId[tier] == nil then
		return "Pick a map tier"
	end
	local given = 0
	for _, player in targets do
		if TreasureService.give(player, tier) then
			given += 1
		end
	end
	return `{Config.Treasure.byId[tier].name} map for {given} player(s)`
end

local function heal(_admin: Player, targets: { Player }): string
	for _, player in targets do
		HuntService.healFull(player)
	end
	return `Healed {names(targets)}`
end

local function kill(_admin: Player, targets: { Player }): string
	for _, player in targets do
		HuntService.kill(player, "the Admin")
	end
	return `Ate {names(targets)}`
end

local function title(_admin: Player, targets: { Player }, text: any): string
	if typeof(text) ~= "string" or #text > 24 then
		return "Give a title (up to 24 letters)"
	end
	each(targets, function(player, data)
		data.title = text
		if text ~= "" then
			data.titles[text] = true
		end
		WardrobeService.refresh(player)
	end)
	return if text == "" then `Title taken off {names(targets)}` else `Title "{text}" for {names(targets)}`
end

local function resetTutorial(_admin: Player, targets: { Player }): string
	each(targets, function(_, data)
		data.tutorial = { step = 1, progress = 0, done = false }
	end)
	return `Tutorial restarted for {names(targets)}`
end

-- Testers: finish the tutorial now (its reward too), so species can be switched
local function finishTutorial(_admin: Player, targets: { Player }): string
	local finished = 0
	for _, player in targets do
		if TutorialService.complete(player) then
			finished += 1
		end
	end
	return if finished > 0 then `Tutorial finished for {names(targets)}` else "Already finished"
end

-- Teleport: to a biome's middle, up off its floor
local function goTo(_admin: Player, targets: { Player }, biomeId: any): string
	local biome = if typeof(biomeId) == "string" then Config.Biomes.byId[biomeId] else nil
	if biome == nil then
		return "Pick a biome"
	end
	local span = (biome.angleTo - biome.angleFrom) % 360
	local angle = math.rad(biome.angleFrom + (if span == 0 then 0 else span / 2))
	local r = (math.max(biome.radiusFrom, 200) + biome.radiusTo) / 2
	local x, z = math.cos(angle) * r, math.sin(angle) * r
	local y = Seafloor.y(x, z) + 30
	for _, player in targets do
		Net.teleport(player, CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(0, y, 0)))
	end
	return `Teleported {names(targets)} to {biome.name}`
end

-- Bosses
local function summonBoss(_admin: Player, _targets: { Player }, id: any): string
	if BossService.active() then
		return "A boss is already up"
	end
	BossService.summon(if typeof(id) == "string" and id ~= "" then id else nil)
	local boss = BossService.active()
	return if boss then `{boss.def.name} summoned` else "No boss summoned"
end

local function hurtBoss(_admin: Player, _targets: { Player }, fraction: any): string
	local boss = BossService.active()
	if boss == nil then
		return "No boss is up"
	end
	local f = if typeof(fraction) == "number" then math.clamp(fraction, 0.01, 1) else 0.25
	boss.predator.health = math.max(boss.predator.health - boss.predator.maxHealth * f, 1)
	return `{boss.def.name} at {math.floor(boss.predator.health / boss.predator.maxHealth * 100)}%`
end

local function endBoss(_admin: Player, _targets: { Player }): string
	local boss = BossService.active()
	if boss == nil then
		return "No boss is up"
	end
	BossService.dismiss()
	return `{boss.def.name} sent away`
end

-- Monetization testing (no Robux): grant or take a pass, run a product's effect,
-- pretend to have Premium or a restricted policy
local function grantPass(_admin: Player, targets: { Player }, key: any): string
	local pass = if typeof(key) == "string" then Config.Monetization.passesByKey[key] else nil
	if pass == nil then
		return "Pick a pass"
	end
	local count = each(targets, function(player)
		MonetizationService.grantPass(player, pass.key)
	end)
	return `{pass.name} granted to {count} player(s)`
end

local function revokePass(_admin: Player, targets: { Player }, key: any): string
	local pass = if typeof(key) == "string" then Config.Monetization.passesByKey[key] else nil
	if pass == nil then
		return "Pick a pass"
	end
	local count = each(targets, function(player)
		MonetizationService.revokePass(player, pass.key)
	end)
	return `{pass.name} taken from {count} player(s) (until they rejoin, if they own it on Roblox)`
end

local function runProduct(_admin: Player, targets: { Player }, key: any): string
	local product = if typeof(key) == "string" then Config.Monetization.productsByKey[key] else nil
	if product == nil then
		return "Pick a product"
	end
	local count = 0
	for _, player in targets do
		if MonetizationService.grantProduct(player, product.key) then
			count += 1
		end
	end
	return `Ran {product.name} for {count} player(s) (no purchase made)`
end

local function perk(_admin: Player, targets: { Player }, which: any): string
	local perks = { premium = true, restricted = true, group = true }
	if typeof(which) ~= "string" then
		return "Pick a perk"
	end
	local name, value = string.match(which, "^(%a+):(%a+)$")
	if name == nil or not perks[name] then
		return "Pick a perk"
	end
	local on = value == "on"
	local count = each(targets, function(player)
		MonetizationService.setDebugPerk(player, name :: string, on)
	end)
	return `{name} {if on then "on" else "off"} for {count} player(s)`
end

-- Daily streak and Coral Garden testing
local function dailyReset(_admin: Player, targets: { Player }): string
	local today = EconomyService.today()
	local count = each(targets, function(_player, data)
		-- As if the last claim was yesterday: the streak carries on and today's claim waits
		if data.daily.day >= today then
			data.daily.day = today - 1
		end
	end)
	return `Today's daily reward is claimable again for {count} player(s)`
end

local function dailyStreak(_admin: Player, targets: { Player }, streak: any): string
	local n = amountOf(streak, 0)
	if n == nil then
		return "Give a streak"
	end
	local today = EconomyService.today()
	local count = each(targets, function(_player, data)
		data.daily.day = today - 1
		data.daily.streak = n
		data.daily.best = math.max(data.daily.best, n)
	end)
	return `Streak set to {n} (today's claim makes it {n + 1}) for {count} player(s)`
end

local function dailyBreak(_admin: Player, targets: { Player }): string
	local today = EconomyService.today()
	local count = each(targets, function(_player, data)
		data.daily.day = today - 3
	end)
	return `Missed two days: the streak starts over for {count} player(s)`
end

local function gardenHours(_admin: Player, targets: { Player }, hours: any): string
	local n = if typeof(hours) == "number" and hours == hours then math.clamp(hours, 0, 48) else nil
	if n == nil then
		return "Give hours"
	end
	local count = 0
	for _, player in targets do
		GardenService.fastForward(player, n)
		count += 1
	end
	return `Coral Garden grown by {n} h for {count} player(s) (collected within a few seconds while in their den)`
end

-- The Tide Clock: force a tide on every server client for 10 minutes ("" = the clock)
local function forceTide(_admin: Player, _targets: { Player }, id: any): string
	if id == "" then
		workspace:SetAttribute("TideOverride", nil)
		workspace:SetAttribute("TideOverrideUntil", nil)
		return "Tides back on the clock"
	end
	if typeof(id) ~= "string" or Config.Tides.byId[id] == nil then
		return "Pick a tide"
	end
	workspace:SetAttribute("TideOverride", id)
	workspace:SetAttribute("TideOverrideUntil", Timing.unix() + 600)
	return `{Config.Tides.byId[id].name} for 10 minutes on this server`
end

-- Rare catches: the 10 prey fish nearest each target turn a rarity
local function rareNear(_admin: Player, targets: { Player }, rarityId: any): string
	if typeof(rarityId) ~= "string" or Config.Catch.byId[rarityId] == nil then
		return "Pick a rarity"
	end
	local made = 0
	for _, player in targets do
		local _, root = FishService.character(player)
		if root then
			made += CatchService.forceNear(root.Position, rarityId, 10)
		end
	end
	return `{made} fish turned {rarityId}`
end

local function trackAdd(_admin: Player, targets: { Player }, rarityId: any, amount: any): string
	local n = amountOf(amount, 1) or 1
	if typeof(rarityId) ~= "string" or Config.Catch.byId[rarityId] == nil then
		return "Pick a rarity"
	end
	local unlocked = 0
	for _, player in targets do
		local skin = CatchService.addTrack(player, rarityId, n)
		if skin and skin ~= "" then
			unlocked += 1
		end
	end
	return `+{n} {rarityId} catches on the current fish's track ({unlocked} skin(s) unlocked)`
end

local function weeklyCatch(_admin: Player, targets: { Player }): string
	local featured = Catch.weekly(Timing.unix())
	if featured == nil then
		return "No Catch of the Week yet (week 1 starts Monday 2026-10-12)"
	end
	local prey = Config.Prey.byId[featured.prey]
	for _, player in targets do
		local _, root = FishService.character(player)
		Events.caught:fire(
			player,
			featured.prey,
			featured.rarity,
			if root then root.Position else Vector3.zero,
			prey.mass
		)
	end
	return `Caught this week's {featured.rarity} {prey.name} for {names(targets)}`
end

local function bounties(_admin: Player, targets: { Player }, what: any): string
	for _, player in targets do
		if what == "finish" then
			BountyService.finishAll(player)
		else
			BountyService.redraw(player)
		end
	end
	return if what == "finish"
		then `Bounties finished for {names(targets)}`
		else `New bounties drawn for {names(targets)}`
end

local function boardPoints(_admin: Player, targets: { Player }, boardId: any, amount: any): string
	local n = amountOf(amount, 1) or 1
	if typeof(boardId) ~= "string" or Config.Leaderboards.byId[boardId] == nil then
		return "Pick a board"
	end
	for _, player in targets do
		LeaderboardService.add(player, boardId, n)
	end
	return `+{n} on {Config.Leaderboards.byId[boardId].name} for {names(targets)} (written within a minute)`
end

AdminActions.byName = {
	addCoral = addCoral :: Handler,
	setCoral = setCoral :: Handler,
	addShells = addShells :: Handler,
	setLevel = setLevel :: Handler,
	feed = feed :: Handler,
	dna = dna :: Handler,
	trophies = trophies :: Handler,
	wraps = wraps :: Handler,
	charm = charm :: Handler,
	unlockSpecies = unlockSpecies :: Handler,
	allShades = allShades :: Handler,
	giveMap = giveMap :: Handler,
	heal = heal :: Handler,
	kill = kill :: Handler,
	title = title :: Handler,
	resetTutorial = resetTutorial :: Handler,
	finishTutorial = finishTutorial :: Handler,
	goTo = goTo :: Handler,
	summonBoss = summonBoss :: Handler,
	hurtBoss = hurtBoss :: Handler,
	endBoss = endBoss :: Handler,
	grantPass = grantPass :: Handler,
	revokePass = revokePass :: Handler,
	runProduct = runProduct :: Handler,
	perk = perk :: Handler,
	dailyReset = dailyReset :: Handler,
	dailyStreak = dailyStreak :: Handler,
	dailyBreak = dailyBreak :: Handler,
	gardenHours = gardenHours :: Handler,
	forceTide = forceTide :: Handler,
	rareNear = rareNear :: Handler,
	trackAdd = trackAdd :: Handler,
	weeklyCatch = weeklyCatch :: Handler,
	bounties = bounties :: Handler,
	boardPoints = boardPoints :: Handler,
} :: { [string]: Handler }

return AdminActions
