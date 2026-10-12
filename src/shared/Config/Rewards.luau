--!strict
-- The shape of a reward bundle, shared by Config/Daily, Config/Playtime and
-- Config/Pass (and paid out by RewardsService.grant, described by Shared/Reward).
-- Only the type lives here, so config modules can share it without a cycle.
export type Reward = {
	coral: number?,
	shells: number?,
	wraps: number?, -- Kelp Wraps (up to the carry cap)
	charms: { [string]: number }?, -- Config/Shop charm id → count
	map: string?, -- a Config/Treasure tier
	spins: number?, -- Treasure Wheel spins (Config/Wheel)
	skin: string?, -- a Config/Shades id, for the fish you're swimming as
	title: string?, -- a title (worn at once if none is)
	den: string?, -- a Config/Dens item, owned for free
	xp: number?, -- Tide Pass XP
	big: boolean?, -- the one a ladder builds to (drawn larger)
}

return {}
