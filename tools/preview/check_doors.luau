-- run_hub.sh builder: checks that nothing solid the doorways' dressing adds
-- (DenDoor.front: arch and jamb stones, threshold, steps; a stone collides as its
-- block, whatever its sphere mesh) reaches into the way a LV 100 fish (collider
-- radius 6.8) swims into a doorway: spheres along the door's axis from 40 studs
-- out to the portal's trigger (8 in front of it), and 2.5 studs off the axis each
-- way. Also checks the in-den exits the same way. Prints one line per den and a
-- verdict; run with DUMP_ONLY=1 and read hub_parts.txt.
local FISH = 6.8
local World = Config.World
local hub = World.hub
local failures = 0
local function sphereHitsBox(center, radius, part)
	local p = part.CFrame:PointToObjectSpace(center)
	local h = part.Size / 2
	local q = Vector3.new(math.clamp(p.X, -h.X, h.X), math.clamp(p.Y, -h.Y, h.Y), math.clamp(p.Z, -h.Z, h.Z))
	return (p - q).Magnitude < radius
end
local function check(label, frame, model, reach)
	local solid = {}
	for _, d in model:GetDescendants() do
		if d.IsPart and d.CanCollide ~= false then
			table.insert(solid, d)
		end
	end
	local worst = math.huge
	local blocked = nil
	for z = -40, -reach, 0.5 do
		for _, off in { Vector3.new(0, 0, 0), Vector3.new(2.5, 0, 0), Vector3.new(-2.5, 0, 0), Vector3.new(0, 2.5, 0), Vector3.new(0, -2.5, 0) } do
			local center = frame * (off + Vector3.new(0, 0, z))
			for _, part in solid do
				if sphereHitsBox(center, FISH, part) then
					blocked = blocked or string.format("%s at z %.1f off (%.1f, %.1f)", part.Name, z, off.X, off.Y)
				end
				local p = part.CFrame:PointToObjectSpace(center)
				local h = part.Size / 2
				local q = Vector3.new(math.clamp(p.X, -h.X, h.X), math.clamp(p.Y, -h.Y, h.Y), math.clamp(p.Z, -h.Z, h.Z))
				worst = math.min(worst, (p - q).Magnitude - FISH)
			end
		end
	end
	if blocked then
		failures += 1
	end
	print(string.format("D|%s|%d solid|clearance %.2f|%s", label, #solid, worst, blocked or "clear"))
end
for index = 1, Layout.DEN_COUNT do
	local den = Instance.new("Model")
	DenDoor.front(den, index)
	-- every doorway style (Config/Dens `doors`), on every doorway
	for _, style in DenDoor.styles() do
		DenDoor.restyle(index, style)
		check(`den {index} doorway {style}`, Layout.doorFrame(index), den, 8)
	end
	-- the way out inside the den wears the same styles (DenDoor.restyle dressed it
	-- above; it's built on its own model)
	local inside = Instance.new("Model")
	DenDoor.exit(inside, index)
	for _, style in DenDoor.styles() do
		DenDoor.restyle(index, "Stone")
		DenDoor.restyle(index, style)
		check(`den {index} exit {style}`, Layout.exitFrame(index), inside, 8)
	end
end
print(if failures == 0 then "D|all doorways clear for a LV 100 fish" else `D|{failures} BLOCKED`)
