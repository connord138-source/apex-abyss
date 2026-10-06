--!strict
-- Rarity tiers for roll outcomes and cosmetics: their names, colors and order.
-- Abyssal (body parts and exotic variants) is the rarest.
export type Tier = {
	id: string,
	name: string,
	color: Color3,
	order: number,
}

local list: { Tier } = {
	{ id = "Coral", name = "Coral", color = Color3.fromRGB(255, 146, 110), order = 0 },
	{ id = "Common", name = "Common", color = Color3.fromRGB(200, 216, 224), order = 1 },
	{ id = "Rare", name = "Rare", color = Color3.fromRGB(96, 176, 255), order = 2 },
	{ id = "Epic", name = "Epic", color = Color3.fromRGB(190, 116, 255), order = 3 },
	{ id = "Legendary", name = "Legendary", color = Color3.fromRGB(255, 202, 76), order = 4 },
	{ id = "Mythic", name = "Mythic", color = Color3.fromRGB(255, 92, 146), order = 5 },
	{ id = "Abyssal", name = "Abyssal", color = Color3.fromRGB(84, 255, 214), order = 6 },
}

local byId: { [string]: Tier } = {}
for _, tier in list do
	byId[tier.id] = tier
end

return {
	list = list,
	byId = byId,
}
