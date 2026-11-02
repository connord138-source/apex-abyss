--!strict
-- Boost trails (owner, 2026-10-17: "I also want to add boost effects, such as bubbles,
-- rainbow, glitter, fire, etc as an earnable customization"): what streams off a
-- fish's tail while it dashes, and lightly while it swims fast. Worn one at a time
-- on every fish (they're the player's, not a species'), chosen in the Wardrobe's
-- TRAILS tab; earned on the Tide Pass (Config/Pass `trail` rewards) or as a Catch of
-- the Week's prize (`week`, Config/Catch `weekly`), never sold.
-- TrailController draws them on every fish from the character's `Trail` attribute.
--
--   style  what it's made of: "bubbles", "glitter", "flame", "rainbow", "storm",
--          "stardust", "frost" or "ink" (TrailController)
--   color / color2  its colours (a rainbow ignores them)
-- Where each is earned is read from the season's tiers (the Index, the Wardrobe).
export type Trail = {
	id: string,
	name: string,
	tier: string, -- Config/Tiers (looks only)
	style: string,
	color: Color3,
	color2: Color3,
	blurb: string,
	week: boolean?, -- a Catch of the Week's prize (Config/Catch `weekly` `trail`)
}

local C = Color3.fromRGB

local list: { Trail } = {
	{
		id = "Bubbles",
		name = "Bubble Stream",
		tier = "Common",
		style = "bubbles",
		color = C(220, 248, 255),
		color2 = C(170, 225, 255),
		blurb = "A fizzing stream of bubbles behind every dash.",
	},
	{
		id = "Glitter",
		name = "Glitter",
		tier = "Uncommon",
		style = "glitter",
		color = C(255, 230, 140),
		color2 = C(170, 220, 255),
		blurb = "Gold and silver glitter twinkling in your wake.",
	},
	{
		id = "Ink",
		name = "Ink Cloud",
		tier = "Rare",
		style = "ink",
		-- Lit violet-indigo, not dark: dark ink was lost in the blue water (playtest
		-- 2026-10-17). It glows `color2` as it's shed and deepens to `color`
		color = C(118, 92, 232),
		color2 = C(182, 158, 255),
		blurb = "Glowing indigo ink billowing out behind you.",
	},
	{
		id = "Fire",
		name = "Fire Wake",
		tier = "Rare",
		style = "flame",
		color = C(255, 120, 30),
		color2 = C(210, 44, 14),
		blurb = "Flames licking off your tail. Underwater. Somehow.",
	},
	{
		id = "Frost",
		name = "Frost Wake",
		tier = "Rare",
		style = "frost",
		color = C(200, 240, 255),
		color2 = C(120, 190, 255),
		blurb = "An icy ribbon and rime flakes that sink as they fall.",
	},
	{
		id = "Rainbow",
		name = "Rainbow Wake",
		tier = "Epic",
		style = "rainbow",
		color = C(255, 255, 255),
		color2 = C(255, 255, 255),
		blurb = "A full rainbow ribbon with sparkles running off it.",
	},
	{
		id = "Storm",
		name = "Storm Wake",
		tier = "Epic",
		style = "storm",
		color = C(140, 200, 255),
		color2 = C(235, 245, 255),
		blurb = "Crackling sparks and a charged ribbon behind every burst.",
	},
	{
		id = "Stardust",
		name = "Stardust",
		tier = "Epic",
		style = "stardust",
		color = C(190, 150, 255),
		color2 = C(110, 220, 255),
		blurb = "A trail of stars and violet nebula.",
	},
	-- The Catch of the Week's trails (weeks 5–8, 2026-11-02)
	{
		id = "SeaGlass",
		name = "Sea Glass Wake",
		tier = "Epic",
		style = "frost",
		color = C(150, 235, 205),
		color2 = C(90, 200, 190),
		blurb = "A ribbon of frosted sea glass and soft green flakes.",
		week = true,
	},
	{
		id = "ReefBloom",
		name = "Reef Bloom",
		tier = "Epic",
		style = "glitter",
		color = C(255, 150, 90),
		color2 = C(90, 230, 220),
		blurb = "Coral-orange and aqua glitter, like a reef in bloom.",
		week = true,
	},
	{
		id = "Venom",
		name = "Venom Cloud",
		tier = "Epic",
		style = "ink",
		color = C(110, 190, 50),
		color2 = C(190, 255, 120),
		blurb = "A glowing lime cloud, a lionfish's warning.",
		week = true,
	},
	{
		id = "Sunlit",
		name = "Sunlit Wake",
		tier = "Epic",
		style = "stardust",
		color = C(255, 210, 120),
		color2 = C(255, 248, 215),
		blurb = "Sun-gold motes drifting off your tail.",
		week = true,
	},
}

local byId: { [string]: Trail } = {}
for _, trail in list do
	byId[trail.id] = trail
end

return {
	list = list,
	byId = byId,
}
