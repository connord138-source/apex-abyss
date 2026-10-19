-- Dumps the ambient creatures' poses through their cycles (Shared/AmbientRigs) for
-- ambient_render.py: each joint's turn (bones) and every stand-in part where that pose
-- puts it, as JSON on stdout. Run by run_ambient.sh with the Roblox shims.
local AmbientRigs = require("./AmbientRigs")
local Ambient = require("./Ambient")

local function middle(range: { number }?): number
	return if range then (range[1] + range[2]) / 2 else 4
end

local CREATURES = {
	{ name = "Stingray", rig = "stingray", kind = Ambient.kinds.ray },
	{ name = "Manta", rig = "manta", kind = Ambient.kinds.manta },
	{ name = "Turtle", rig = "turtle", kind = Ambient.kinds.turtle },
	{ name = "Humpback", rig = "whale", kind = Ambient.giants.whale },
	{ name = "Crab", rig = "crab", kind = Ambient.kinds.crab },
}

local out = {}
local function emit(s: string)
	table.insert(out, s)
end
local function num(x: number): string
	return string.format("%.5f", x)
end
local function vec(v: any): string
	return "[" .. num(v.X) .. "," .. num(v.Y) .. "," .. num(v.Z) .. "]"
end
-- (position, then the right, up and back columns)
local function frame(c: any): string
	local r, u, b = c.RightVector, c.UpVector, -c.LookVector
	return "[" .. table.concat({ vec(c.Position), vec(r), vec(u), vec(b) }, ",") .. "]"
end

emit("[")
for ci, creature in CREATURES do
	local beat = middle(creature.kind.beat)
	local plan = AmbientRigs.plan(creature.rig)
	-- Five moments through a beat, then one turning hard to the right; the stingray's
	-- last two settled in the sand (one just landed, fluttering) and the crab's last
	-- three at rest, picking with its claws
	local samples = {}
	for k = 0, 4 do
		table.insert(samples, { t = beat * k / 5, bank = 0, turn = 0, rest = 0, settled = -1, moving = true })
	end
	table.insert(samples, { t = beat * 0.3, bank = 0.3, turn = 0.8, rest = 0, settled = -1, moving = true })
	if creature.rig == "stingray" then
		samples[5] = { t = beat * 0.8, bank = 0, turn = 0, rest = 1, settled = 0.3, moving = true }
		samples[6] = { t = beat * 0.3, bank = 0, turn = 0, rest = 1, settled = 4, moving = true }
	elseif creature.rig == "crab" then
		samples[4] = { t = 1.3, bank = 0, turn = 0, rest = 0, settled = -1, moving = false }
		samples[5] = { t = 2.4, bank = 0, turn = 0, rest = 0, settled = -1, moving = false }
		samples[6] = { t = 6.7, bank = 0, turn = 0, rest = 0, settled = -1, moving = false }
	end
	emit((if ci > 1 then "," else "") .. "{")
	emit(string.format('"name":"%s","rig":"%s","measure":"%s","beat":%s,"look":{', creature.name, creature.rig, plan.measure, num(beat)))
	local first = true
	for role, colour in creature.kind.look :: any do
		emit((if first then "" else ",") .. string.format('"%s":[%s,%s,%s]', role, num(colour.R), num(colour.G), num(colour.B)))
		first = false
	end
	emit('},"samples":[')
	for si, s in samples do
		local pose = {}
		local motion = {
			t = s.t,
			phase = 0,
			period = beat,
			bank = s.bank,
			turn = s.turn,
			rest = s.rest,
			settled = s.settled,
			moving = s.moving,
		}
		local lift = AmbientRigs.pose(creature.rig, motion, pose)
		emit((if si > 1 then "," else "") .. string.format('{"t":%s,"label":"%s","lift":%s,"pose":{', num(s.t), 
			if s.turn ~= 0 then "turning right" elseif s.settled >= 0 then "settled" elseif not s.moving then "resting" else string.format("%.0f%% of a beat", s.t / beat * 100), frame(lift)))
		local firstJoint = true
		for name, turn in pose do
			emit((if firstJoint then "" else ",") .. string.format('"%s":%s', name, frame(turn)))
			firstJoint = false
		end
		emit('},"parts":[')
		for pi, p in AmbientRigs.parts(plan, pose, 1) do
			emit((if pi > 1 then "," else "") .. string.format('{"shape":"%s","role":"%s","size":%s,"cf":%s}', p.shape, p.role, vec(p.size), frame(p.cframe)))
		end
		emit("]}")
	end
	emit("]}")
end
emit("]")
print(table.concat(out, "\n"))
