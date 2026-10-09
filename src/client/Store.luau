--!strict
-- Robux purchases from the client: opens Roblox's own prompts for a game pass or a
-- developer product (Config/Monetization). The server grants everything
-- (MonetizationService). Items without a Creator Hub id yet are hidden in a live
-- game; Studio lists them greyed out and says so when pressed, so the layout and
-- flows can be checked before they exist (the admin panel runs their effects).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)

local Monetization = Config.Monetization

local Store = {
	-- (text) — something to tell the player (a toast)
	said = Signal.new(),
	-- (productKey, bought) — Roblox's product prompt closed
	productClosed = Signal.new(),
}

Store.SHOW_UNSET = RunService:IsStudio()

-- Whether an item with this id belongs in the Shop at all
function Store.listed(id: number): boolean
	return id ~= 0 or Store.SHOW_UNSET
end

function Store.price(price: number): string
	return `R$ {price}`
end

local function unset(name: string)
	Store.said:fire(`{name} isn't created in Creator Hub yet (Admin → Run a product's effect tests it)`)
end

function Store.buyProduct(key: string)
	local product = Monetization.productsByKey[key]
	if product == nil then
		return
	end
	if product.id == 0 then
		unset(product.name)
		return
	end
	MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.id)
end

function Store.buyPass(key: string)
	local pass = Monetization.passesByKey[key]
	if pass == nil then
		return
	end
	if pass.id == 0 then
		unset(pass.name)
		return
	end
	MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.id)
end

function Store.buyPremium()
	pcall(MarketplaceService.PromptPremiumPurchase, MarketplaceService, Players.LocalPlayer)
end

function Store.start()
	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, productId: number, bought: boolean)
			if userId ~= Players.LocalPlayer.UserId then
				return
			end
			for _, product in Monetization.products do
				if product.id == productId and product.id ~= 0 then
					Store.productClosed:fire(product.key, bought)
				end
			end
		end
	)
end

return Store
