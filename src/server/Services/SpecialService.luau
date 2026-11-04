--!strict
-- Every fish's special attack (Config/Specials). The server owns the meter: it fills as
-- the fish lands bites (`Events.biteLanded`) and swallows (`Events.ate`), resets with a
-- new fish, and is spent whole by `UseSpecial`. It shows on the character:
--   SpecialMeter  0..1
--   SpecialAt     server clock it was last used (with SpecialId, what it was): every
--                 client draws it from these
--   ThrashUntil   Nibbler: bites come faster (Perks.biteGap)
--   FrenzyUntil   Reef Shark: bites do more (Perks.biteBonus), and heal here
--   MawUntil      Anglerfish: prey is drawn in from far off (Perks.sense)
--   Rolling       Moray: it spins until then
--   RolledBy      on the fish a Moray has hold of: its client is dragged to that fish
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Size = require(ReplicatedStorage.Shared.Size)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Events = require(script.Parent.Parent.Events)
local Net = require(script.Parent.Parent.Net)
local Progress = require(script.Parent.Parent.Progress)
local DataService = require(script.Parent.DataService)
local FishService = require(script.Parent.FishService)
local HuntService = require(script.Parent.HuntService)
local PredatorService = require(script.Parent.PredatorService)

local Specials = Config.Specials
type Special = typeof(Config.Specials.bySpecies.Nibbler)

local SpecialService = {}

local meters: { [Player]: number } = {}

local function specialOf(player: Player): Special?
	local data = DataService.get(player)
	return if data then Specials.bySpecies[Progress.speciesId(data)] else nil
end

local function setMeter(player: Player, value: number)
	local before = meters[player] or 0
	local after = math.clamp(value, 0, 1)
	meters[player] = after
	local character = FishService.character(player)
	if character then
		character:SetAttribute("SpecialMeter", math.floor(after * 100 + 0.5) / 100)
	end
	if before < 1 and after >= 1 then
		local special = specialOf(player)
		if special then
			Net.notify(player, `{string.upper(special.name)} READY`, "good")
		end
	end
end

local function nearestOnSegment(a: Vector3, b: Vector3, point: Vector3): Vector3
	local ab = b - a
	local t = math.clamp((point - a):Dot(ab) / math.max(ab:Dot(ab), 1e-4), 0, 1)
	return a + ab * t
end

-- The other fish within `radius` of the line a to b (to their bodies, roughly)
local function fishNear(
	player: Player,
	a: Vector3,
	b: Vector3,
	radius: number
): { { player: Player, root: BasePart } }
	local found = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local character, root = FishService.character(other)
			if character and root then
				local length = character:GetAttribute("Length")
				local half = if typeof(length) == "number" then length * 0.45 else 1
				if (nearestOnSegment(a, b, root.Position) - root.Position).Magnitude <= radius + half then
					table.insert(found, { player = other, root = root })
				end
			end
		end
	end
	return found
end

-- Everything in `radius`: bitten at `scale`, then shoved along `away(position)`
local function blast(
	player: Player,
	special: Special,
	center: Vector3,
	radius: number,
	away: (Vector3) -> Vector3
)
	local scale = special.scale or 1
	for _, fish in fishNear(player, center, center, radius) do
		if HuntService.strike(player, fish.player.UserId, scale) then
			Net.shove(fish.player, away(fish.root.Position))
		end
	end
	for _, hit in PredatorService.touching(center, center, radius) do
		if PredatorService.strike(player, hit.predator, hit.at, scale) then
			PredatorService.drive(hit.predator, away(hit.predator.position), special.stun or 1)
		end
	end
end

local function spearCharge(player: Player, special: Special)
	local mouth = HuntService.mouth(player)
	if mouth == nil then
		return
	end
	local scale = special.scale or 1
	local stopAt = Timing.clock() + (special.seconds or 1)
	local bitten: { [any]: boolean } = {}
	local last: Vector3 = mouth
	while Timing.clock() < stopAt do
		task.wait(0.08)
		local now, length, slack = HuntService.mouth(player)
		if now == nil then
			return
		end
		local radius = Size.reach(length) + slack
		for _, fish in fishNear(player, last, now, radius) do
			if not bitten[fish.player] then
				bitten[fish.player] = true
				HuntService.strike(player, fish.player.UserId, scale)
			end
		end
		for _, hit in PredatorService.touching(last, now, radius) do
			if not bitten[hit.predator] then
				bitten[hit.predator] = true
				PredatorService.strike(player, hit.predator, hit.at, scale)
			end
		end
		last = now
	end
end

-- The Moray's grab: the nearest fish or creature in front of it, held and bitten until
-- it's done, one of them dies or they're pulled apart. False with nothing to grab.
local function deathRoll(player: Player, special: Special, character: Model): boolean
	local mouth, length, slack = HuntService.mouth(player)
	if mouth == nil then
		return false
	end
	local radius = Size.reach(length) + length * (special.reach or 1) + slack
	local fish: { player: Player, root: BasePart }? = nil
	local gap = math.huge
	for _, entry in fishNear(player, mouth, mouth, radius) do
		local distance = (entry.root.Position - mouth).Magnitude
		if distance < gap and not HuntService.safe(entry.player) then
			fish, gap = entry, distance
		end
	end
	local creature = nil
	for _, hit in PredatorService.touching(mouth, mouth, radius) do
		local distance = (hit.at - mouth).Magnitude
		if distance < gap then
			creature, fish, gap = hit, nil, distance
		end
	end
	if fish == nil and creature == nil then
		Net.notify(player, "Nothing to grab · get right up on something first", "info")
		return false
	end
	local ticks = special.ticks or 5
	local every = special.every or 0.4
	local scale = special.scale or 1
	local leash = length * (special.leash or 3) + slack
	local total = ticks * every
	local now = Timing.clock()
	character:SetAttribute("Rolling", now + total)
	local held: Model? = nil
	if fish then
		held = FishService.character(fish.player)
		if held then
			held:SetAttribute("RolledBy", player.UserId)
		end
	elseif creature then
		PredatorService.drive(creature.predator, Vector3.zero, total)
	end
	task.spawn(function()
		for _ = 1, ticks do
			task.wait(every)
			local at = HuntService.mouth(player)
			if at == nil then
				break
			end
			if fish then
				local _, root = FishService.character(fish.player)
				if root == nil or (root.Position - at).Magnitude > leash then
					break
				end
				if not HuntService.strike(player, fish.player.UserId, scale) then
					break
				end
			elseif creature then
				local predator = creature.predator
				if
					predator.mode == "dead"
					or (predator.position - at).Magnitude > leash + predator.def.length
				then
					break
				end
				if not PredatorService.strike(player, predator, predator.position, scale) then
					break
				end
			end
		end
		character:SetAttribute("Rolling", nil)
		if held and held.Parent then
			held:SetAttribute("RolledBy", nil)
		end
	end)
	return true
end

local function use(player: Player)
	local special = specialOf(player)
	local character, root = FishService.character(player)
	if special == nil or character == nil or root == nil then
		return
	end
	if (meters[player] or 0) < 1 or HuntService.safe(player) then
		return
	end
	local mouth, length = HuntService.mouth(player)
	if mouth == nil then
		return
	end
	local now = Timing.clock()
	local id = special.id
	if id == "DeathRoll" then
		if not deathRoll(player, special, character) then
			return -- (the meter stays full)
		end
	elseif id == "WildThrash" then
		character:SetAttribute("ThrashUntil", now + (special.seconds or 4))
	elseif id == "SpearCharge" then
		task.spawn(spearCharge, player, special)
	elseif id == "SpineBurst" then
		character:SetAttribute("Puffed", now + 0.6)
		local center = root.Position
		blast(
			player,
			special,
			center,
			(special.radius or 18) + length * (special.perLength or 2),
			function(at)
				local away = at - center
				return (if away.Magnitude > 1e-3 then away.Unit else Vector3.yAxis) * (special.push or 90)
			end
		)
	elseif id == "BloodFrenzy" then
		character:SetAttribute("FrenzyUntil", now + (special.seconds or 6))
	elseif id == "AbyssMaw" then
		character:SetAttribute("MawUntil", now + (special.seconds or 1.4))
		blast(player, special, mouth, (special.radius or 24) + length * (special.perLength or 3), function(at)
			local toward = mouth - at
			return (if toward.Magnitude > 1e-3 then toward.Unit else Vector3.zero) * (special.pull or 70)
		end)
	else
		return
	end
	character:SetAttribute("SpecialId", id)
	character:SetAttribute("SpecialAt", now)
	Net.notify(player, `{string.upper(special.name)}!`, "good")
	setMeter(player, 0)
end

-- Fills the meter (the admin panel)
function SpecialService.fill(player: Player)
	setMeter(player, 1)
end

function SpecialService.start()
	Net.onRequest("UseSpecial", use)
	Events.biteLanded:connect(function(player: Player)
		setMeter(player, (meters[player] or 0) + Specials.charge.perBite)
		-- A shark in its frenzy heals on every bite that lands
		local character = FishService.character(player)
		local frenzy = if character then character:GetAttribute("FrenzyUntil") else nil
		if typeof(frenzy) == "number" and frenzy > Timing.clock() then
			HuntService.heal(player, Specials.bySpecies.ReefShark.heal or 0)
		end
	end)
	Events.ate:connect(function(player: Player, count: number)
		setMeter(player, (meters[player] or 0) + Specials.charge.perSwallow * count)
	end)
	-- A new fish (eaten, a species switch) starts with an empty meter
	FishService.spawned:connect(function(player: Player)
		setMeter(player, 0)
	end)
	Players.PlayerRemoving:Connect(function(player)
		meters[player] = nil
	end)
end

return SpecialService
