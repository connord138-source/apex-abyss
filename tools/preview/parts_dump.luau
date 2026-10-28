-- Prints, as JSON for parts_preview.py, how Shared/PartFit hangs and tints every
-- rolled part's model on every body plan's mesh (run_parts.sh copies the modules
-- beside it and puts the Roblox shims in them). Per plan and part: the frame its
-- attach point sits at in the fish's unit box (position, then the right, up and back
-- columns), its model's scale per axis (its length times its stretch), the attach
-- point, whether it hangs reversed, the colour its SurfaceAppearance is multiplied by
-- (the fish wearing no shade) and its transparency.
local Vector3 = require("./parts_rbx").Vector3
local PartFit = require("./PartFit")
local Species = require("./Config/Species")
local DIMS = require("./dims")

local function num(x: number): string
	return string.format("%.5f", x)
end
local function vec(v): string
	return `[{num(v.X)},{num(v.Y)},{num(v.Z)}]`
end
local function frame(c): string
	local p, r, u, b = c.Position, c.RightVector, c.UpVector, -c.LookVector
	return `[{num(p.X)},{num(p.Y)},{num(p.Z)},{num(r.X)},{num(r.Y)},{num(r.Z)},{num(u.X)},{num(u.Y)},{num(u.Z)},{num(
		b.X
	)},{num(b.Y)},{num(b.Z)}]`
end

local plans = {}
for _, species in Species.list do
	local plan = species.plan
	local dims = DIMS[plan]
	if dims == nil then
		continue
	end
	-- (the fish wearing no shade: its model's own colours, as Cosmetics tints a mesh fish's parts)
	local look = PartFit.LOOKS[plan] or { back = species.back, belly = species.belly, fin = species.fin }
	local parts = {}
	local ids = {}
	for id in PartFit.MODELS do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local model = PartFit.MODELS[id]
		local shape = model.plans[plan]
		if shape == nil then
			continue
		end
		local scale = (shape.stretch or Vector3.one) * shape.length
		local tint = PartFit.tint(model, look)
		table.insert(
			parts,
			`"{id}":\{"frame":{frame(shape.at)},"scale":{vec(scale)},"attach":{vec(model.attach)},"reversed":{if model.reversed
				then "true"
				else "false"},"tint":[{num(tint.R)},{num(tint.G)},{num(tint.B)}],"transparency":{num(
				model.transparency or 0
			)}\}`
		)
	end
	table.insert(plans, `"{plan}":\{{table.concat(parts, ",")}\}`)
end
print(`\{"title":"after: fitted to each fish (Shared/PartFit)","plans":\{{table.concat(plans, ",")}\}\}`)
