--!strict
-- One shape for a bundle of rewards, shared by the daily streak (Config/Daily), the
-- playtime gifts (Config/Playtime) and the Tide Pass (Config/Pass): the server pays
-- it out (RewardsService.grant) and the menus describe it (Reward.lines).
local Config = require(script.Parent.Config)
local Rewards = require(script.Parent.Config.Rewards)

export type Reward = Rewards.Reward

local Reward = {}

local function plural(count: number, word: string): string
	return `{count} {word}{if count == 1 then "" else "S"}`
end

-- Short upper-case lines for a tile ("300 CORAL", "1 WHEEL SPIN"), with `bonus`
-- applied to the coral and shells (a streak week, Premium).
function Reward.lines(reward: Reward, bonus: number?): { string }
	local scale = bonus or 1
	local parts: { string } = {}
	local function number(value: number): string
		local rounded = math.floor(value * scale + 0.5)
		if rounded >= 1000 then
			local text = tostring(rounded)
			local out = ""
			while #text > 3 do
				out = `,{string.sub(text, -3)}{out}`
				text = string.sub(text, 1, -4)
			end
			return text .. out
		end
		return tostring(rounded)
	end
	if reward.skin then
		local shade = Config.Shades.byId[reward.skin]
		table.insert(parts, `{string.upper(if shade then shade.name else reward.skin)} SKIN`)
	end
	if reward.title then
		table.insert(parts, `"{string.upper(reward.title)}" TITLE`)
	end
	if reward.den then
		local item = Config.Dens.itemsById[reward.den]
		table.insert(parts, string.upper(if item then item.name else reward.den))
	end
	if reward.coral then
		table.insert(parts, `{number(reward.coral)} CORAL`)
	end
	if reward.shells then
		table.insert(parts, `{number(reward.shells)} SHELLS`)
	end
	if reward.wraps then
		table.insert(parts, plural(reward.wraps, "KELP WRAP"))
	end
	if reward.charms then
		for id, count in reward.charms do
			local charm = Config.Shop.charmsById[id]
			table.insert(parts, `{count} {string.upper(if charm then charm.name else id)}`)
		end
	end
	if reward.map then
		local tier = Config.Treasure.byId[reward.map]
		table.insert(parts, `{string.upper(if tier then tier.name else reward.map)} MAP`)
	end
	if reward.spins then
		table.insert(parts, plural(reward.spins, "WHEEL SPIN"))
	end
	if reward.xp then
		table.insert(parts, `{number(reward.xp / scale)} PASS XP`)
	end
	return parts
end

return Reward
