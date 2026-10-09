--!strict
-- Game passes and developer products (Config/Monetization, GDD §9), ported from
-- Hatch & Snatch. The rule: sell growth and safety, never bite damage.
--
--  * Passes: ownership is asked of Roblox when a player joins (and cached), plus
--    anything bought or granted this session (data.passes). Other services ask
--    MonetizationService.hasPass(player, key).
--  * Products: MarketplaceService.ProcessReceipt → DataService.processPurchase,
--    which grants each receipt exactly once and only confirms it to Roblox after
--    the save that records it. The service that owns each effect registers it with
--    MonetizationService.onProduct (Double Haul and Second Chance: HuntService;
--    shell packs: EconomyService).
--  * Server Frenzy: ×2 growth for the whole server with a timer, announced to
--    everyone (MonetizationService.frenzy); HuntService multiplies every Haul gain
--    by MonetizationService.growth(player).
--  * Rewarded video ads: the "AdDoubleHaul" product doubles a small Haul once the ad
--    has been watched to the end (Roblox grants ad rewards as a product receipt).
--  * Free perks: Roblox Premium (and the Roblox group, once it exists) earn more
--    coral (EconomyService.earnCoral).
--  * Paid random items: shells buy random rolls, so players whose policy restricts
--    paid random items (PolicyService) never see the shell packs (`paidRandom`). The
--    roll odds are shown to everyone before buying (the ODDS panel).
local AdService = game:GetService("AdService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)

type PlayerData = DataService.PlayerData

local Monetization = Config.Monetization
local Tuning = Monetization.tuning

local MonetizationService = {
	-- (player, passKey) — a pass became owned (bought, granted or found on join)
	passAdded = Signal.new(),
}

local owned: { [Player]: { [string]: boolean } } = {}
local groupMembers: { [Player]: boolean } = {}
-- Players whose policy allows paid random items. Everyone else counts as
-- restricted, including before the check answers and when it fails.
local randomAllowed: { [Player]: boolean } = {}
local debugPerks: { [Player]: { [string]: boolean } } = {} -- admin panel test perks
local watching: { [Player]: boolean } = {} -- an ad is showing

local frenzyUntil = 0 -- Workspace:GetServerTimeNow() when Server Frenzy runs out

-- Product effects: key → function(player, data) that changes the player's data.
-- Filled in by the services that own each effect (see MonetizationService.onProduct).
local productHandlers: { [string]: (Player, PlayerData) -> () } = {}

function MonetizationService.hasPass(player: Player, key: string): boolean
	local set = owned[player]
	if set and set[key] then
		return true
	end
	local data = DataService.get(player)
	return data ~= nil and data.passes[key] == true
end

-- Marks a pass owned (a purchase this session, an admin grant) and tells listeners.
function MonetizationService.grantPass(player: Player, key: string)
	if Monetization.passesByKey[key] == nil or MonetizationService.hasPass(player, key) then
		return
	end
	owned[player] = owned[player] or {}
	owned[player][key] = true
	local data = DataService.get(player)
	if data then
		data.passes[key] = true
		DataService.markDirty(player)
	end
	MonetizationService.passAdded:fire(player, key)
end

-- Takes a pass away again (admin panel, for testing what non-owners see).
function MonetizationService.revokePass(player: Player, key: string)
	if owned[player] then
		owned[player][key] = nil
	end
	local data = DataService.get(player)
	if data then
		data.passes[key] = nil
		DataService.markDirty(player)
	end
	MonetizationService.passAdded:fire(player, key)
end

local function debugPerk(player: Player, perk: string): boolean
	local perks = debugPerks[player]
	return perks ~= nil and perks[perk] == true
end

function MonetizationService.isPremium(player: Player): boolean
	return player.MembershipType == Enum.MembershipType.Premium or debugPerk(player, "premium")
end

-- Whether the player is in the game's Roblox group (as of the last check).
function MonetizationService.inGroup(player: Player): boolean
	return groupMembers[player] == true or debugPerk(player, "group")
end

-- Whether paid random items (the shell packs) are hidden from this player: true
-- where their policy restricts them, and until Roblox has answered.
function MonetizationService.paidRandomRestricted(player: Player): boolean
	return randomAllowed[player] ~= true or debugPerk(player, "restricted")
end

-- Asks Roblox for the player's policy (yields). A failed check keeps the player
-- restricted, the safe side.
local function checkPolicy(player: Player)
	for attempt = 1, 3 do
		local ok, policy = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
		if ok and typeof(policy) == "table" then
			if player.Parent == Players then
				randomAllowed[player] = policy.ArePaidRandomItemsRestricted == false
				DataService.markDirty(player)
			end
			return
		end
		if attempt < 3 and player.Parent == Players then
			task.wait(2 * attempt)
		end
	end
	warn(`[MonetizationService] {player.Name}: policy check failed; paid random items stay hidden`)
end

-- Testing: pretend the player has Premium ("premium"), is in the group ("group") or
-- lives where paid random items are restricted ("restricted").
function MonetizationService.setDebugPerk(player: Player, perk: string, on: boolean)
	debugPerks[player] = debugPerks[player] or {}
	debugPerks[player][perk] = on
	DataService.markDirty(player)
end

-- Asks Roblox whether the player is in the group now (yields). Returns the answer,
-- or nil when there's no group set up or the check failed.
function MonetizationService.checkGroup(player: Player): boolean?
	local groupId = Tuning.group.id
	if groupId == 0 then
		return nil
	end
	local ok, member = pcall(player.IsInGroupAsync, player, groupId)
	if not ok then
		return nil
	end
	if player.Parent == Players then
		groupMembers[player] = member
	end
	return member
end

-- Registers what a developer product does. `grant` runs once per receipt, inside
-- the save-confirmed purchase flow, so it must only change the player's data (and
-- things that are fine to repeat, like announcements and the live Haul).
function MonetizationService.onProduct(key: string, grant: (Player, PlayerData) -> ())
	productHandlers[key] = grant
end

-- Runs a product's effect without a purchase (admin panel testing).
function MonetizationService.grantProduct(player: Player, key: string): boolean
	local handler = productHandlers[key]
	local data = DataService.get(player)
	if handler == nil or data == nil then
		return false
	end
	handler(player, data)
	DataService.markDirty(player)
	return true
end

---------------------------------------------------------------------------
-- Growth: ×2 Mass and Server Frenzy
---------------------------------------------------------------------------

function MonetizationService.frenzyActive(): boolean
	return Workspace:GetServerTimeNow() < frenzyUntil
end

-- Every Haul gain is multiplied by this (HuntService).
function MonetizationService.growth(player: Player): number
	local growth = 1
	if MonetizationService.hasPass(player, "DoubleMass") then
		growth *= Tuning.doubleMass
	end
	if MonetizationService.frenzyActive() then
		growth *= Tuning.serverFrenzy.multiplier
	end
	return growth
end

-- Coral earned from play is multiplied by this (EconomyService.earnCoral).
function MonetizationService.coralMultiplier(player: Player): number
	local multiplier = 1
	if MonetizationService.hasPass(player, "VIP") then
		multiplier *= Tuning.vipCoral
	end
	if MonetizationService.isPremium(player) then
		multiplier *= Tuning.premiumCoral
	end
	if MonetizationService.inGroup(player) then
		multiplier *= Tuning.group.coral
	end
	return multiplier
end

local function publishFrenzy()
	Workspace:SetAttribute("FrenzyUntil", frenzyUntil)
	Workspace:SetAttribute(
		"Frenzy",
		if MonetizationService.frenzyActive() then Tuning.serverFrenzy.multiplier else 1
	)
end

-- Adds a Server Frenzy purchase: more time (up to the cap ahead), announced to all.
function MonetizationService.boostFrenzy(buyer: Player)
	local tune = Tuning.serverFrenzy
	local now = Workspace:GetServerTimeNow()
	frenzyUntil = math.min(math.max(frenzyUntil, now) + tune.minutes * 60, now + tune.maxMinutes * 60)
	publishFrenzy()
	local minutes = math.ceil((frenzyUntil - now) / 60)
	Net.notifyAll(
		`{buyer.DisplayName} started a SERVER FRENZY: ×{tune.multiplier} growth for {minutes} min!`,
		"rare"
	)
end

---------------------------------------------------------------------------
-- Rewarded video ads
---------------------------------------------------------------------------

local function watchAd(player: Player)
	local product = Monetization.productsByKey.AdDoubleHaul
	if product == nil or product.id == 0 or watching[player] then
		return
	end
	watching[player] = true
	local ok, result = pcall(function()
		local reward = AdService:CreateAdRewardFromDevProductId(product.id)
		return AdService:ShowRewardedVideoAdAsync(player, reward)
	end)
	watching[player] = nil
	if player.Parent ~= Players then
		return
	end
	-- A finished ad pays through ProcessReceipt (the AdDoubleHaul handler). Roblox
	-- reports most failures (no ad ready, an internal error) as a result, not an error.
	if ok and result == Enum.ShowAdResult.ShowCompleted then
		return
	elseif ok and result == Enum.ShowAdResult.ShowInterrupted then
		Net.notify(player, "The ad didn't finish, so your Haul stays as it was.", "bad")
	else
		Net.notify(player, "No ad to show right now. Try again later.", "bad")
	end
end

---------------------------------------------------------------------------
-- Purchases
---------------------------------------------------------------------------

local function productByAssetId(assetId: number): typeof(Monetization.products[1])?
	for _, product in Monetization.products do
		if product.id == assetId and product.id ~= 0 then
			return product
		end
	end
	return nil
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local product = productByAssetId(receipt.ProductId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if product == nil then
		warn(`[MonetizationService] receipt for unknown product {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local handler = productHandlers[product.key]
	if handler == nil then
		warn(`[MonetizationService] no handler for product {product.key}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- The data may still be loading if they bought right after joining
	local deadline = os.clock() + 20
	while DataService.get(player) == nil and player.Parent == Players and os.clock() < deadline do
		task.wait(0.25)
	end
	local decision = DataService.processPurchase(player, tostring(receipt.PurchaseId), function(data)
		handler(player, data)
	end)
	if decision == Enum.ProductPurchaseDecision.PurchaseGranted then
		DataService.markDirty(player)
	end
	return decision
end

-- Asks Roblox whether the player owns a pass: true / false, or nil if Roblox
-- couldn't answer after a few tries.
local function ownsOnRoblox(player: Player, passId: number): boolean?
	for attempt = 1, 3 do
		local ok, has =
			pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
		if ok then
			return has
		end
		if attempt < 3 and player.Parent == Players then
			task.wait(1.5 * attempt)
		end
	end
	return nil
end

-- On join, Roblox's answer wins: owned passes are granted, and a saved pass
-- Roblox says isn't owned (refunded) is removed. Saved passes are only trusted
-- when Roblox can't be reached.
local function checkPasses(player: Player)
	for _, pass in Monetization.passes do
		if pass.id ~= 0 then
			local owns = ownsOnRoblox(player, pass.id)
			local data = DataService.get(player)
			if owns == true then
				MonetizationService.grantPass(player, pass.key)
			elseif owns == false and data and data.passes[pass.key] and not RunService:IsStudio() then
				data.passes[pass.key] = nil
				DataService.markDirty(player)
			end
		end
	end
	local data = DataService.get(player)
	if data then
		for key in data.passes do
			if not (owned[player] and owned[player][key]) then
				owned[player] = owned[player] or {}
				owned[player][key] = true
				MonetizationService.passAdded:fire(player, key)
			end
		end
	end
end

local function onPassPurchased(player: Player, passId: number, purchased: boolean)
	if not purchased then
		return
	end
	for _, pass in Monetization.passes do
		if pass.id ~= passId or pass.id == 0 then
			continue
		end
		-- Confirm with Roblox first: this event alone isn't proof of purchase. (Studio
		-- test purchases never show up as owned, so Studio trusts them.) Only a "yes"
		-- grants it; if Roblox can't answer, try again a few times, and the next join
		-- checks too (Hatch & Snatch release audit 2026-10-05).
		task.spawn(function()
			if not RunService:IsStudio() then
				local owns = ownsOnRoblox(player, pass.id)
				for _ = 1, 3 do
					if owns ~= nil or player.Parent ~= Players then
						break
					end
					task.wait(20)
					owns = ownsOnRoblox(player, pass.id)
				end
				if owns ~= true then
					warn(
						`[MonetizationService] {player.Name}: purchase of {pass.key} not confirmed by Roblox`
					)
					if owns == nil and player.Parent == Players then
						Net.notify(
							player,
							`Roblox hasn't confirmed {pass.name} yet. It unlocks the next time you join.`,
							"info"
						)
					end
					return
				end
			end
			MonetizationService.grantPass(player, pass.key)
			Net.notify(player, `Thanks! {pass.name} is yours.`, "rare")
		end)
	end
end

-- The VIP tag over the fish (NametagController reads it)
local function tagVip(player: Player)
	local character = player.Character
	if character then
		character:SetAttribute("VIP", MonetizationService.hasPass(player, "VIP"))
	end
end

function MonetizationService.start()
	MonetizationService.onProduct("ServerFrenzy", function(player)
		MonetizationService.boostFrenzy(player)
	end)
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPurchased)
	Net.onRequest("WatchAd", watchAd)
	MonetizationService.passAdded:connect(function(player: Player, key: string)
		if key == "VIP" then
			tagVip(player)
		end
		DataService.markDirty(player)
	end)
	DataService.loaded:connect(function(player: Player)
		task.spawn(checkPasses, player)
		task.spawn(checkPolicy, player)
		player.CharacterAdded:Connect(function()
			tagVip(player)
		end)
		tagVip(player)
	end)
	Players.PlayerMembershipChanged:Connect(function(player)
		if MonetizationService.isPremium(player) then
			Net.notify(player, "Premium perk: +10% coral from everything you earn!", "rare")
		end
		DataService.markDirty(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		groupMembers[player] = nil
		randomAllowed[player] = nil
		debugPerks[player] = nil
		watching[player] = nil
	end)
	StateService.provide(function(player, _data, state)
		local passes: { [string]: boolean } = {}
		for _, pass in Monetization.passes do
			if MonetizationService.hasPass(player, pass.key) then
				passes[pass.key] = true
			end
		end
		state.passes = passes
		state.premium = MonetizationService.isPremium(player)
		state.inGroup = MonetizationService.inGroup(player)
		state.paidRandomRestricted = MonetizationService.paidRandomRestricted(player)
		state.massMultiplier = if passes.DoubleMass then Tuning.doubleMass else 1
		state.coralMultiplier = MonetizationService.coralMultiplier(player)
	end)
	publishFrenzy()
	-- Tell clients when Server Frenzy ends
	Guard.loop("MonetizationService.frenzy", 5, function()
		local now = if MonetizationService.frenzyActive() then Tuning.serverFrenzy.multiplier else 1
		if Workspace:GetAttribute("Frenzy") ~= now then
			publishFrenzy()
		end
	end)
end

return MonetizationService
