--!strict
-- Sea life that helps (Config/Companions; owner, 2026-10-20: "fish that are not edible
-- such as turtles and stingrays manta rays need to have some kind of function whether
-- it is a buff where they swim with you and provide a bonus or something similar").
-- The turtles, rays and mantas live only on each client (AmbientLifeController), so a
-- client tells us when a turtle joined it or it flushed a ray (`Companion`), and we
-- check what we can: a live fish out of the hub and the dens, in a biome that kind
-- lives in, near the floor for a ray, and the cooldowns. A turtle sets the character's
-- `Escort` attribute (the clock it leaves at): every client draws it at that fish's
-- side (CompanionController) and HuntService scales what bites do by `bite`. A ray
-- pays a few shells. The manta's draft is a speed the client takes for itself, which
-- SpeedService allows. The humpbacks crossing the Open Blue are edible (owner,
-- 2026-10-20: "whales should be edible too"): their passes are the same here as on
-- every client (Shared/Giants), so a bite on one (`BiteWhale`) is checked against
-- where the whale really is. Since 2026-10-28 they're hunted (owner: "whales should be
-- big prey points that would draw in multiple high level players. Low level fish and
-- non predator players shouldnt be able to hurt the whale"): only a hunter fish
-- (Config/Species `predator`) at Config/Ambient `whale.hunt.minLevel` or above hurts
-- one; brought down, it becomes the Whale Fall where it died (ChumService.whaleKilled).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Biomes = require(ReplicatedStorage.Shared.Biomes)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Giants = require(ReplicatedStorage.Shared.Giants)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
local BossService = require(script.Parent.BossService)
local ChumService = require(script.Parent.ChumService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FishService = require(script.Parent.FishService)
local HuntService = require(script.Parent.HuntService)

local Companions = Config.Companions
local Kinds = Config.Ambient.kinds

local CompanionService = {}

-- When each player may have a turtle join, or flush a ray, again (the clock)
local turtleAgain: { [Player]: number } = {}
local rayAgain: { [Player]: number } = {}

local function livesHere(kind: string, position: Vector3): boolean
	local biome = Biomes.at(position)
	if biome == nil then
		return false
	end
	for _, id in Kinds[kind].biomes do
		if id == biome.id then
			return true
		end
	end
	return false
end

local function onRequest(player: Player, kind: any)
	if kind ~= "turtle" and kind ~= "ray" then
		return
	end
	local character, root = FishService.character(player)
	if character == nil or root == nil then
		return
	end
	local at = root.Position
	if Layout.inHub(at) or Layout.denAt(at) or not livesHere(kind, at) then
		return
	end
	local now = Timing.clock()
	if kind == "turtle" then
		local tune = Companions.turtle
		if now < (turtleAgain[player] or 0) then
			return
		end
		-- (a little short of the client's own timer: latency)
		turtleAgain[player] = now + tune.lasts + tune.cooldown * 0.9
		character:SetAttribute("Escort", now + tune.lasts)
		Net.notify(player, "A sea turtle swims with you · bites hurt less", "good")
	else
		local tune = Companions.ray
		if now < (rayAgain[player] or 0) then
			return
		end
		-- low over the sand (a little slack over the client's check)
		if at.Y - Ground.y(at.X, at.Z) > tune.over + 6 then
			return
		end
		rayAgain[player] = now + tune.cooldown * 0.9
		EconomyService.addShells(player, tune.shells)
		Net.notify(player, `+{tune.shells} shells · the ray stirred them up`, "good")
	end
end

-- A bite on a passing humpback (Config/Ambient `whale.feed` and `whale.hunt`; the
-- client sends the lane): a whale on that lane now (or a moment ago, as the biter saw
-- it) with its skin in reach of the mouth, not sooner than a bite allows, while no
-- boss is up (the giants hide then), out of the hub and the dens. Only a hunter fish at
-- `hunt.minLevel` or above hurts it: its bite does what it would to a plain predator of
-- `hunt.level` (Config/Predators `fight`) and tears off a mouthful worth `feed.bite` of
-- its own full Haul, up to `feed.hauls` full Hauls a pass. Anyone else's bite glances
-- off (told once a pass): they feed on the Whale Fall once the hunters bring it down.
local WHALE_SLACK = 6 -- studs: the client's reach allowance and its view's lag
local lastWhaleBite: { [Player]: number } = {}
local whaleFed: { [Player]: { pass: string, taken: number, told: boolean } } = {}

-- Each lane's hunt this pass (by lane; a new pass starts afresh)
type Hunt = {
	slot: number,
	health: number,
	max: number,
	hurt: { [Player]: number }, -- damage done
	last: { [Player]: number }, -- clock of each hunter's last bite
	diedAt: number?,
}
local hunts: { [number]: Hunt } = {}
local calledAt = -math.huge -- the server was last told a whale is being hunted
local giants: Folder? = nil

local fight = Config.Predators.fight
local growth = Config.Tuning.size.levelGrowth

local function publish(lane: number, hunt: Hunt?)
	local folder = giants
	if folder == nil then
		return
	end
	if hunt == nil then
		folder:SetAttribute(`Lane{lane}`, nil)
		return
	end
	folder:SetAttribute(
		`Lane{lane}`,
		Vector3.new(hunt.slot, math.clamp(hunt.health / hunt.max, 0, 1), hunt.diedAt or 0)
	)
end

-- Whether this fish can hurt a whale, and if not, what to tell it
local function hunterOf(player: Player, data: DataService.PlayerData): (boolean, string?)
	local species = Progress.species(data)
	local level = Size.level(Progress.mass(data))
	local tune = Config.Ambient.giants.whale.hunt
	if not species.predator then
		return false,
			`A {species.name} can't hurt a whale · hunters ('Cuda, Moray Eel, Reef Shark, Anglerfish) bring them down from LV {tune.minLevel}`
	end
	if level < tune.minLevel then
		return false, `Too small to hurt a whale · hunters bring them down from LV {tune.minLevel}`
	end
	return true, nil
end

-- A brought-down whale pays everyone who hurt it by their share of the damage (at
-- least `minShare`), and after its roll it's the Whale Fall where it sank to
local function bringDown(lane: number, hunt: Hunt, pass: Giants.Pass, now: number)
	hunt.diedAt = now
	hunt.health = 0
	publish(lane, hunt)
	local tune = Config.Ambient.giants.whale.hunt
	local total = 0
	for _, damage in hunt.hurt do
		total += damage
	end
	local at = Giants.at(lane, pass.from, pass.to, now)
	for player, damage in hunt.hurt do
		if player.Parent == nil then
			continue
		end
		local share = math.max(damage / math.max(total, 1), tune.minShare)
		local added = HuntService.hauls(player, tune.loot.hauls * share, "sized")
		local coral = EconomyService.earnCoral(player, math.floor(tune.loot.coral * share + 0.5))
		HuntService.giveDna(player, at, math.max(1, math.floor(tune.loot.dna * share + 0.5)))
		Net.notify(
			player,
			`You brought down a humpback! +{Format.haul(HuntService.shown(player, added))} · +{coral} coral`,
			"rare"
		)
	end
	Net.notifyAll("A humpback was brought down in the Open Blue · it's sinking as a WHALE FALL", "rare")
	local heading = (pass.to - pass.from) * Vector3.new(1, 0, 1)
	local yaw = math.atan2(-heading.Z, heading.X)
	task.delay(tune.roll, function()
		local frame = Giants.deadFrame(lane, pass.from, pass.to, now, now + tune.roll)
		ChumService.whaleKilled(frame.Position, yaw)
	end)
end

local function onBiteWhale(player: Player, lane: any)
	local settings = Config.Ambient.giants
	if typeof(lane) ~= "number" or lane % 1 ~= 0 or lane < 1 or lane > settings.lanes then
		return
	end
	local now = Timing.clock()
	if BossService.active() or now - (lastWhaleBite[player] or 0) < Config.Tuning.swim.biteCooldown * 0.8 then
		return
	end
	local data = DataService.get(player)
	local mouth, length, slack = HuntService.mouth(player)
	if data == nil or mouth == nil or Layout.inHub(mouth) or Layout.denAt(mouth) then
		return
	end
	local pass = Giants.pass(lane, now)
	if pass.kind ~= "whale" then
		return
	end
	local found: Hunt? = hunts[lane]
	if found and found.slot ~= pass.slot then
		hunts[lane] = nil
		publish(lane, nil)
		found = nil
	end
	if found and found.diedAt then
		return
	end
	local heading = (pass.to - pass.from).Unit
	local reach = Size.reach(length) + length * 0.6 + 2 + slack + WHALE_SLACK
	local near = false
	for _, back in { 0, 0.4 } do
		local at, u = Giants.at(lane, pass.from, pass.to, now - back)
		if u > 0.04 and u < 0.96 and (Giants.gap(at, heading, pass.size, mouth)) <= reach then
			near = true
		end
	end
	if not near then
		return
	end
	lastWhaleBite[player] = now
	local feed = settings.whale.feed
	local tune = settings.whale.hunt
	local key = `{lane}:{pass.slot}`
	local fed = whaleFed[player]
	if fed == nil or fed.pass ~= key then
		fed = { pass = key, taken = 0, told = false }
		whaleFed[player] = fed
	end
	local able, why = hunterOf(player, data)
	if not able then
		if not fed.told then
			fed.told = true
			Net.notify(player, why or "You can't hurt a whale", "info")
		end
		return
	end
	-- The hunt: what this bite does, the whale's health growing with its hunters
	local hunt: Hunt
	if found then
		hunt = found
	else
		hunt =
			{ slot = pass.slot, health = tune.health, max = tune.health, hurt = {}, last = {}, diedAt = nil }
		hunts[lane] = hunt
	end
	hunt.last[player] = now
	local hunters, school = 0, 0
	for other, at in hunt.last do
		if now - at < tune.window then
			hunters += 1
			if other ~= player and now - at < Config.Predators.schoolWindow then
				school += 1
			end
		end
	end
	local want = tune.health * (1 + tune.perExtra * math.max(hunters - 1, 0))
	if want > hunt.max + 1 then
		hunt.health *= want / hunt.max
		hunt.max = want
	end
	local level = Size.level(Progress.mass(data))
	local ratio = math.clamp(growth ^ ((level - tune.level) * fight.power), fight.yours.min, fight.yours.max)
	local damage = Config.Tuning.hunt.biteDamage
		* ratio
		* (1 + Config.Predators.schoolBonus * school)
		* Perks.bite(data.upgrades)
		* Progress.species(data).stats.bite
	hunt.hurt[player] = (hunt.hurt[player] or 0) + damage
	hunt.health -= damage
	if now - calledAt >= tune.callEvery then
		calledAt = now
		Net.notifyAll(
			"Hunters are on a humpback in the Open Blue · join the hunt or wait for the Whale Fall",
			"info"
		)
	end
	-- A mouthful too (in Haul, then ×2 Mass and Server Frenzy, like the Whale Fall's
	-- chunks; nothing past a full Haul)
	local full = HuntService.fullHaul(player)
	local take = math.min(full * feed.bite, math.max(full * feed.hauls - fed.taken, 0))
	if take > 1e-6 then
		local added = HuntService.gain(player, take, "rated")
		fed.taken += added
	end
	if hunt.health <= 0 then
		bringDown(lane, hunt, pass, now)
	else
		publish(lane, hunt)
	end
end

-- Admin (a test of the hunt): the humpback crossing nearest `near` drops to `share`
-- of its health, so a hunter's few bites bring it down. Says where it is.
function CompanionService.hurtWhale(near: Vector3, share: number): string
	local now = Timing.clock()
	local settings = Config.Ambient.giants
	local best: number?, bestAway = nil, math.huge
	for lane = 1, settings.lanes do
		local pass = Giants.pass(lane, now)
		local at, u = Giants.at(lane, pass.from, pass.to, now)
		if pass.kind == "whale" and u > 0.06 and u < 0.9 and (at - near).Magnitude < bestAway then
			best, bestAway = lane, (at - near).Magnitude
		end
	end
	local lane = best
	if lane == nil then
		return "No humpback is crossing the Open Blue right now; try again in a minute"
	end
	local pass = Giants.pass(lane, now)
	local tune = settings.whale.hunt
	local found = hunts[lane]
	local hunt: Hunt
	if found and found.slot == pass.slot and found.diedAt == nil then
		hunt = found
	else
		hunt =
			{ slot = pass.slot, health = tune.health, max = tune.health, hurt = {}, last = {}, diedAt = nil }
		hunts[lane] = hunt
	end
	hunt.health = hunt.max * math.clamp(share, 0.01, 1)
	publish(lane, hunt)
	local _, u = Giants.at(lane, pass.from, pass.to, now)
	return `Humpback on lane {lane} at {math.floor(share * 100 + 0.5)}%, {math.floor(bestAway)} studs away, {math.floor(
		(1 - u) * settings.period
	)} s left of its pass`
end

-- A turtle joins this fish now, whatever its place and cooldown (the admin panel's
-- test: a fish needn't find one first)
function CompanionService.join(player: Player): boolean
	local character = FishService.character(player)
	if character == nil then
		return false
	end
	local now = Timing.clock()
	character:SetAttribute("Escort", now + Companions.turtle.lasts)
	turtleAgain[player] = now + Companions.turtle.lasts
	return true
end

function CompanionService.start()
	Net.onRequest("Companion", onRequest)
	Net.onRequest("BiteWhale", onBiteWhale)
	local folder = Instance.new("Folder")
	folder.Name = "Giants"
	folder.Parent = workspace
	giants = folder
	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		turtleAgain[player] = nil
		rayAgain[player] = nil
		lastWhaleBite[player] = nil
		whaleFed[player] = nil
		for _, hunt in hunts do
			hunt.last[player] = nil
			hunt.hurt[player] = nil
		end
	end)
end

return CompanionService
