--!strict
-- Aggressive AI predators (owner, 2026-10-06: "aggressive AI fish, not controlled by
-- players, worth more than the smaller or calmer fish"). They're simulated on the
-- server (PredatorService): each roams a band of water round the hub, hunts fish big
-- enough to be worth it, telegraphs every bite, and can be bitten back. Killing one
-- pays a Haul, DNA and coral to everyone who helped, by damage share. The world
-- bosses (GDD §8) run on the same system with phases on top.
--
-- Damage to players is a share of the victim's max health: nothing one-shots (owner,
-- 2026-10-07).
export type PredatorDef = {
	id: string,
	name: string,
	model: string, -- ReplicatedStorage.PreyModels.<model> (static mesh), else a part body
	tag: string?, -- the tag's first line (default PREDATOR)
	length: number, -- studs
	health: number,
	speed: number, -- studs/s hunting (roaming is slower)
	turnRate: number, -- radians/s
	aggroRange: number, -- studs: fish inside get hunted
	biteReach: number, -- studs past the mouth
	biteFraction: number, -- of the victim's max health
	biteCooldown: number, -- seconds between bites
	telegraph: number, -- seconds the jaw shows before it bites (the tell)
	ignoreBelow: number, -- fish shorter than this × its length are left alone unless they bite it
	band: { number }, -- distance from the hub's center it roams in (min, max)
	angles: { number }?, -- the sector it keeps to (degrees from +X toward +Z, clockwise; nil = all round)
	depth: { number }, -- height above the local floor it roams in (min, max; Shared/Seafloor)
	count: number, -- alive at once
	respawn: number, -- seconds after a kill
	loot: { haulKg: number, dna: number, coral: number },
	back: Color3, -- part-body colors while the model is missing
	belly: Color3,
}

local list: { PredatorDef } = {
	{
		id = "Barracuda",
		name = "Barracuda",
		model = "Barracuda",
		length = 9,
		health = 140,
		speed = 26,
		turnRate = 2.2,
		aggroRange = 60,
		biteReach = 3,
		biteFraction = 0.2,
		biteCooldown = 2.2,
		telegraph = 0.9,
		ignoreBelow = 0.25,
		band = { 300, 820 },
		depth = { 8, 120 },
		count = 4,
		respawn = 90,
		loot = { haulKg = 6, dna = 3, coral = 40 },
		back = Color3.fromRGB(176, 192, 204),
		belly = Color3.fromRGB(248, 250, 252),
	},
	{
		id = "ReefShark",
		name = "Reef Shark",
		model = "ReefShark",
		length = 14,
		health = 320,
		speed = 24,
		turnRate = 1.6,
		aggroRange = 80,
		biteReach = 4,
		biteFraction = 0.3,
		biteCooldown = 2.8,
		telegraph = 1.1,
		ignoreBelow = 0.3,
		band = { 980, 1440 },
		angles = { 228, 312 }, -- the Open Blue is shark water (owner, 2026-10-08)
		depth = { 40, 330 },
		count = 4,
		respawn = 150,
		loot = { haulKg = 18, dna = 6, coral = 120 },
		back = Color3.fromRGB(110, 124, 138),
		belly = Color3.fromRGB(230, 236, 240),
	},
}

local byId: { [string]: PredatorDef } = {}
for _, def in list do
	byId[def.id] = def
end

return {
	list = list,
	byId = byId,
	tickSeconds = 0.1, -- the server simulates and streams at this rate
	roamSpeed = 0.55, -- × speed while roaming
	schoolBonus = 0.35, -- + per other fish that bit it in the last schoolWindow
	schoolWindow = 2.5,
	-- A player's bite on a predator: biteDamage × (their length / its length) ^ 1.5,
	-- clamped, so small fish chip and big fish chunk
	biteRatioPower = 1.5,
	biteRatioMin = 0.08,
	biteRatioMax = 1.2,
	loseRange = 1.7, -- × aggroRange: a target this far away is dropped
	interpolationDelay = 0.15, -- clients draw this far behind the stream
}
