-- Fake services for running PredatorService in the luau CLI (run_predators.sh). The
-- test sets `sim.now`, `sim.groundY`, `sim.sessions`, `sim.characters` and reads
-- `sim.events` and `sim.hits`.
local rbx = require("./sim_rbx")
local Vector3 = rbx.Vector3

local sim = {
	now = 0,
	groundY = function(_x: number, _z: number): number
		return 0
	end,
	sees = function(_from: Vector3, _to: Vector3): boolean
		return true
	end,
	sessions = {} :: { [any]: any },
	characters = {} :: { [any]: { character: any, root: any } },
	events = {} :: { { kind: string, index: number, payload: any, at: number } },
	hits = {} :: { { player: any, fraction: number, at: number } },
	shoves = {} :: { { player: any, push: Vector3, at: number } },
}

local function noop() end
local function signal()
	return { fire = noop, connect = noop, Connect = noop, Fire = noop }
end

sim.Signal = { new = signal }
sim.Ground = {
	y = function(x: number, z: number): number
		return sim.groundY(x, z)
	end,
	sees = function(from: Vector3, to: Vector3, _short: number?): boolean
		return sim.sees(from, to)
	end,
	clear = noop,
}
sim.Perks = {
	bite = function()
		return 1
	end,
}
sim.Tides = {
	at = function()
		return {}
	end,
}
sim.Timing = {
	clock = function()
		return sim.now
	end,
	unix = function()
		return sim.now
	end,
	now = function()
		return sim.now
	end,
	isStudio = function()
		return false
	end,
}
sim.Events = setmetatable({}, {
	__index = function()
		return signal()
	end,
})
sim.Guard = {
	run = function(_name: string, f: () -> ())
		f()
	end,
	loop = noop,
}
sim.Net = {
	predatorEvent = function(kind: string, index: number, payload: any)
		table.insert(sim.events, { kind = kind, index = index, payload = payload, at = sim.now })
	end,
	predatorStateTo = noop,
	onRequest = noop,
	notify = noop,
	-- (the world bosses: boss_sim.luau)
	notifyAll = noop,
	bossState = noop,
	bossStateTo = noop,
	bossReward = noop,
	shove = function(player: any, push: Vector3)
		table.insert(sim.shoves, { player = player, push = push, at = sim.now })
	end,
}
sim.Progress = {
	species = function()
		return { stats = { bite = 1 } }
	end,
	shades = function()
		return {}
	end,
	speciesId = function()
		return "Nibbler"
	end,
	grantShade = function()
		return true
	end,
}
sim.ChumService = {
	nearest = function()
		return nil
	end,
}
sim.DataService = {
	releasing = signal(),
	loaded = signal(),
	get = function()
		return {}
	end,
	markDirty = noop,
	save = noop,
}
sim.EconomyService = { earnCoral = noop, addCoral = noop }
sim.FishService = {
	character = function(player: any)
		local entry = sim.characters[player]
		if entry == nil then
			return nil, nil
		end
		return entry.character, entry.root
	end,
}
sim.HuntService = {
	sessions = function()
		return sim.sessions
	end,
	damage = function(player: any, fraction: number)
		table.insert(sim.hits, { player = player, fraction = fraction, at = sim.now })
	end,
	feed = function()
		return 0
	end,
	hauls = function()
		return 0
	end,
	shown = function(_player: any, kg: number)
		return kg
	end,
	giveDna = noop,
	mouth = function()
		return nil, 0, 0
	end,
}

-- A fake fish: a character with a Length attribute and a root part
function sim.fish(length: number, position: Vector3)
	local attributes = { Length = length }
	local character = {
		GetAttribute = function(_, name: string)
			return attributes[name]
		end,
		SetAttribute = function(_, name: string, value: any)
			attributes[name] = value
		end,
	}
	local root = { Position = position, AssemblyLinearVelocity = Vector3.zero }
	return character, root
end

return sim
