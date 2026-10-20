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
-- where the whale really is.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Biomes = require(ReplicatedStorage.Shared.Biomes)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Giants = require(ReplicatedStorage.Shared.Giants)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Net = require(script.Parent.Parent.Net)
local BossService = require(script.Parent.BossService)
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

-- A bite off a passing humpback (Config/Ambient `whale.feed`; the client sends the
-- lane): a whale on that lane now (or a moment ago, as the biter saw it) with its
-- skin in reach of the mouth, not sooner than a bite allows, while no boss is up (the
-- giants hide then), out of the hub and the dens. Each bite is a mouthful worth
-- `bite` of the fish's own full Haul, up to `hauls` full Hauls from one whale's pass.
local WHALE_SLACK = 6 -- studs: the client's reach allowance and its view's lag
local lastWhaleBite: { [Player]: number } = {}
local whaleFed: { [Player]: { pass: string, taken: number, told: boolean } } = {}

local function onBiteWhale(player: Player, lane: any)
	local settings = Config.Ambient.giants
	if typeof(lane) ~= "number" or lane % 1 ~= 0 or lane < 1 or lane > settings.lanes then
		return
	end
	local now = Timing.clock()
	if BossService.active() or now - (lastWhaleBite[player] or 0) < Config.Tuning.swim.biteCooldown * 0.8 then
		return
	end
	local mouth, length, slack = HuntService.mouth(player)
	if mouth == nil or Layout.inHub(mouth) or Layout.denAt(mouth) then
		return
	end
	local pass = Giants.pass(lane, now)
	if pass.kind ~= "whale" then
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
	local key = `{lane}:{pass.slot}`
	local fed = whaleFed[player]
	if fed == nil or fed.pass ~= key then
		fed = { pass = key, taken = 0, told = false }
		whaleFed[player] = fed
	end
	local full = HuntService.fullHaul(player)
	local take = math.min(full * feed.bite, math.max(full * feed.hauls - fed.taken, 0))
	if take <= 1e-6 then
		if not fed.told then
			fed.told = true
			Net.notify(player, "You're full of whale! Leave the rest for the others", "info")
		end
		return
	end
	-- (in Haul, then ×2 Mass and Server Frenzy, like the Whale Fall's chunks; nothing
	-- past a full Haul)
	local added = HuntService.gain(player, take, "rated")
	-- (the first mouthful of a pass says so; the Haul's own pops show the rest)
	if added > 0 and fed.taken <= 0 then
		Net.notify(
			player,
			`A mouthful of whale · +{Format.haul(HuntService.shown(player, added))} a bite`,
			"good"
		)
	end
	fed.taken += added
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
	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		turtleAgain[player] = nil
		rayAgain[player] = nil
		lastWhaleBite[player] = nil
		whaleFed[player] = nil
	end)
end

return CompanionService
