-- Checks the rare catches' pure rules (run_catch.sh): the skin goals (Shared/Catch
-- `goal`: N of a rarity from each of S prey species), the old saves (a catch skin one
-- fish earned on the old per-fish track becomes every fish's, nothing is taken away),
-- the Catch Log rows with Silver in them, and that the spawn and reward numbers in
-- Config/Catch are sane. How often players meet rare fish: run_catch_sim.sh.
local Catch = require("./Catch")
local Config = require("./Config")

local CatchConfig = Config.Catch

local failures = 0
local function check(ok: boolean, text: string)
	if not ok then
		failures += 1
		print("FAIL: " .. text)
	end
end

local function has(list: { string }, value: string): boolean
	return table.find(list, value) ~= nil
end

-- The goal: `each` of a rarity from each of `species` species
local golden = CatchConfig.byId.Golden
local each, species = golden.unlock.each, golden.unlock.species
local log: { [string]: { [string]: number } } = {}
local done, counted, met = Catch.goal(log, "Golden")
check(done == 0 and #counted == 0 and not met, "an empty log meets nothing")
local names = { "Minnow", "Sardine", "Wrasse", "Snapper", "Grouper", "Barracuda" }
for i = 1, species - 1 do
	log[names[i]] = { Normal = 40, Golden = each + i, Silver = 3 }
end
log[names[species]] = { Normal = 5, Golden = each - 1 }
done, counted, met = Catch.goal(log, "Golden")
check(done == species - 1 and not met, `one short: {done} species`)
check(counted[1] == names[species - 1], "the most caught species first")
local _, _, _, counts = Catch.goal(log, "Golden")
check(counts[names[species]] == each - 1, "a species short of the goal still shows its count")
log[names[species]].Golden = each
done, _, met = Catch.goal(log, "Golden")
check(done == species and met, "the goal is met at the last species")
check(has(Catch.met(log), "Golden"), "Catch.met names the goal")
check(not has(Catch.met(log), "Silver"), "other rarities' catches don't count (3 Silver each)")
-- Plenty of one species is still one species
local one = { Minnow = { Golden = each * 10 } }
done, _, met = Catch.goal(one, "Golden")
check(done == 1 and not met, "many of one species is one species")
-- A goal with bad rows or an unknown rarity
check(select(1, Catch.goal({ Minnow = {} }, "Golden")) == 0, "an empty row")
check(select(3, Catch.goal(log, "Nope")) == false, "an unknown rarity")

-- Old saves: a catch skin earned on one fish's old track goes on every fish, the
-- goals met go on too, and nothing is taken away
local owned: { [string]: { [string]: boolean }? } = {
	Nibbler = { CatchGlowing = true, Lilac = true },
	Cuda = nil,
	Puffer = {},
}
local skins = Catch.accountSkins({}, owned)
check(#skins == 1 and skins[1] == "CatchGlowing", "an old track's skin becomes every fish's")
skins = Catch.accountSkins(log, owned)
check(has(skins, "CatchGlowing") and has(skins, golden.skin), "an old skin and a met goal")
check(not has(skins, "Lilac"), "only catch skins")
check(not has(skins, CatchConfig.byId.Crystal.skin), "an unmet goal gives nothing")
local seen: { [string]: boolean } = {}
for _, skin in skins do
	check(not seen[skin], `{skin} twice`)
	seen[skin] = true
end

-- The Catch Log's rows: plain and every rarity, Silver too
local row: { [string]: number } = { Normal = 1 }
for _, rarity in CatchConfig.rarities do
	row[rarity.id] = 1
end
check(Catch.rowDone(row), "a full row")
row.Silver = 0
check(not Catch.rowDone(row), "a row without Silver isn't done (one paid before stays paid)")
row.Silver, row.Normal = 1, 0
check(not Catch.rowDone(row), "a row needs a plain catch")

-- The numbers
local previous: CatchConfig.Rarity? = nil
for i, rarity in CatchConfig.rarities do
	check(CatchConfig.codes[rarity.id] == i, `{rarity.id}'s wire code`)
	check(rarity.rate > 0 and rarity.life > 0 and rarity.every > 0, `{rarity.id}: rate, life, every`)
	check(rarity.unlock.each >= 1 and rarity.unlock.species >= 1, `{rarity.id}: its goal`)
	check(rarity.unlock.species <= #Config.Prey.list, `{rarity.id}: more species than there are`)
	check((CatchConfig.firstCatch :: any)[rarity.id] ~= nil, `{rarity.id}: a first-catch reward`)
	-- Each player has a handful of rare fish swimming round them at most (a calm sea,
	-- Silver the most: ~7.5 since 2026-10-28, owner: "still need more silver and gold
	-- fish"), and the rarer swim less often, pay more and score more
	local swimming = rarity.rate * rarity.life / 60
	check(swimming > 0 and swimming < 10, `{rarity.id}: {swimming} swimming round each player`)
	if previous and not rarity.tide then
		check(rarity.rate < previous.rate, `{rarity.id} spawns more often than {previous.id}`)
		check(rarity.every > previous.every, `{rarity.id} is met more often than {previous.id}`)
		check(rarity.haul > previous.haul and rarity.points > previous.points, `{rarity.id} pays less`)
	end
	-- Earned skins stop at Epic (owner, 2026-10-10)
	local shade = Config.Shades.byId[rarity.skin]
	if shade then
		check(
			shade.tier == "Common" or shade.tier == "Uncommon" or shade.tier == "Rare" or shade.tier == "Epic",
			`{rarity.skin} is {shade.tier}: earned skins stop at Epic`
		)
		check(shade.catch == rarity.id, `{rarity.skin} is the {rarity.id} skin`)
	else
		print(`(note: {rarity.skin} isn't in Config/Shades yet)`)
	end
	if not rarity.tide then
		previous = rarity
	end
end
check(
	CatchConfig.byId.Silver.tier ~= nil and CatchConfig.rarities[1].id == "Silver",
	"Silver is the commonest"
)
local spawn = CatchConfig.spawn
check(spawn.clearance >= 240 + 60, "a rare fish never turns rare inside its glint's reach (240 + the camera)")
check(spawn.near >= spawn.clearance and spawn.far > spawn.near, "spawned between near and far, out of sight")
check(spawn.cap >= 2, "the cap leaves room")
check(CatchConfig.weekly.rate > 0 and CatchConfig.weekly.every > 0, "the week's stream")
for _, week in CatchConfig.weekly.list do
	check(Config.Prey.byId[week.prey] ~= nil and CatchConfig.byId[week.rarity] ~= nil, `week {week.prey}`)
end

if failures == 0 then
	print("catch_test: OK")
else
	error(`catch_test: {failures} failures`)
end
