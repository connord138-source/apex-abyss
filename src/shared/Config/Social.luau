--!strict
-- Getting the game seen (owner, 2026-11-03: "integrate all 4 of your build recs ...
-- spend as little as possible but I want the game to be seen/played"): friend
-- invites with rewards, Roblox badges and opt-in notifications. The tutorial's
-- funnel is in Server/Funnel. Ids and message ids are 0 / "" until they're made in
-- Creator Hub; anything still at 0 is skipped, never an error.
local Rewards = require(script.Parent.Rewards)

-- Friend invites (Roblox's friend referral system, `Player:GetJoinData()`
-- `ReferredByPlayerId`): a new player who came from an invite gets a welcome gift,
-- and once they finish the tutorial the player who invited them gets `inviter`
-- (online or not: it waits for them, ReferralService). A player who had already
-- played gets nothing for joining from an invite, and each friend counts once.
local referral = {
	invitee = { coral = 500, shells = 50, spins = 1 } :: Rewards.Reward,
	inviter = { shells = 100, spins = 1 } :: Rewards.Reward,
	rewarded = 10, -- friends paid for, at most (more still count for the badge and title)
	title = { friends = 3, title = "Tide Caller" },
	-- The invite prompt's own line (Roblox shows it with the game's name)
	message = "Come swim with me in Apex Tide!",
	-- The invite rows' notes, matching the rewards above: the Shop's (two lines) and
	-- the narrower Pod window's
	blurb = "Friends who finish the tutorial get you 100 shells and a spin. They get a welcome gift too.",
	short = "100 shells and a spin for you when they finish the tutorial",
}

-- Roblox badges (Creator Hub → the experience → Engagement → Badges; 5 free a day,
-- so they go in by this order). Each is measured from the save like an achievement
-- (BadgesService), so a player who did it before the badge existed gets it on their
-- next visit. `id` 0: not made yet.
export type BadgeMeasure =
	"joined" -- played once
	| "tutorial" -- finished the tutorial
	| "catches" -- rare catches of `rarity`, any prey
	| "bossKills" -- world boss fights won
	| "level" -- the best level of any fish
	| "friends" -- invited friends who finished the tutorial
	| "treasures" -- treasure chests dug up
	| "apexKills" -- Apex bounties claimed

export type Badge = {
	key: string, -- saved in `data.badges`
	id: number, -- the Roblox badge id
	name: string, -- as made in Creator Hub
	description: string,
	measure: BadgeMeasure,
	rarity: string?, -- for "catches"
	goal: number,
	icon: string, -- marketing/badge_<icon>_512.png
}

local badges: { Badge } = {
	{
		key = "Welcome",
		id = 0,
		name = "Welcome to Apex Tide",
		description = "You dived into Apex Tide. Eat, grow and become the apex!",
		measure = "joined",
		goal = 1,
		icon = "welcome",
	},
	{
		key = "Graduate",
		id = 0,
		name = "Tutorial Graduate",
		description = "Finished the tutorial: hunted, banked, spun the wheel and rolled.",
		measure = "tutorial",
		goal = 1,
		icon = "graduate",
	},
	{
		key = "Golden",
		id = 0,
		name = "Golden Catch",
		description = "Caught a Golden fish.",
		measure = "catches",
		rarity = "Golden",
		goal = 1,
		icon = "golden",
	},
	{
		key = "BossHunter",
		id = 0,
		name = "Boss Hunter",
		description = "Helped bring down the Megalodon or the Giant Squid.",
		measure = "bossKills",
		goal = 1,
		icon = "boss",
	},
	{
		key = "Level25",
		id = 0,
		name = "Rising Predator",
		description = "Reached level 25 with any fish.",
		measure = "level",
		goal = 25,
		icon = "level25",
	},
	{
		key = "Friend",
		id = 0,
		name = "School's In",
		description = "A friend you invited finished the tutorial.",
		measure = "friends",
		goal = 1,
		icon = "friend",
	},
	{
		key = "Treasure",
		id = 0,
		name = "X Marks the Spot",
		description = "Dug up a treasure chest.",
		measure = "treasures",
		goal = 1,
		icon = "treasure",
	},
	{
		key = "ApexHunter",
		id = 0,
		name = "Apex Hunter",
		description = "Ate the Apex and claimed its bounty.",
		measure = "apexKills",
		goal = 1,
		icon = "apex",
	},
	{
		key = "Crystal",
		id = 0,
		name = "Crystal Clear",
		description = "Caught a Crystal fish.",
		measure = "catches",
		rarity = "Crystal",
		goal = 1,
		icon = "crystal",
	},
	{
		key = "Level100",
		id = 0,
		name = "Top of the Food Chain",
		description = "Reached level 100 with any fish.",
		measure = "level",
		goal = 100,
		icon = "level100",
	},
}

-- Notifications (Roblox experience notifications, sent through Open Cloud from the
-- server, NotifyService): one a player leaves for when their Coral Garden is full or
-- their free wheel spins are back, and one when a friend they invited finishes the
-- tutorial. Roblox delivers at most one a day per experience, only to players 13+
-- who allowed them. Each message is a notification string made in Creator Hub
-- (Engagement → Notifications, 99 characters at most) whose asset id goes in `id`;
-- the text to make it with is `text`. Nothing is sent while an id is "".
local notify = {
	-- The experience Secret (Creator Hub → the experience → Secrets) holding an Open
	-- Cloud API key with `user.user-notification:write` for this experience
	secret = "Notifications",
	universe = 10769954850,
	messages = {
		garden = {
			id = "",
			text = "Your Coral Garden is full: {coral} coral is waiting in your den!",
			category = "Coral Garden full",
		},
		spins = {
			id = "",
			text = "Your free Treasure Wheel spins are back. Come spin for a rare skin!",
			category = "Wheel spins back",
		},
		friend = {
			id = "",
			text = "{friend} finished the tutorial from your invite. Your reward is waiting!",
			category = "Invited friend",
		},
	},
	-- Never sooner than this after leaving, and never later than `latest`
	soonest = 2 * 3600,
	latest = 3 * 24 * 3600,
	-- Our own card asking whether they'd like a ping (before Roblox's prompt, which
	-- shows at most once in 30 days): after this many banks, then not again for 30 days
	askAfterBanks = 4,
	askAgain = 30 * 24 * 3600,
}

local badgesByKey: { [string]: Badge } = {}
for _, badge in badges do
	badgesByKey[badge.key] = badge
end

return {
	referral = referral,
	badges = badges,
	badgesByKey = badgesByKey,
	notify = notify,
}
