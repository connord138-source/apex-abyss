USE_PROPS = true -- the keepers, the crystal and the oculus lanterns are imported in game
-- run_hub.sh's default builder: the hub's parts as WorldService builds them
-- (dens' doors, the plaza, the stalls, the tunnels' boards and lanterns, the
-- Treasure Wheel), with a few dens owned: den 1 by a 20-character name at Nook,
-- den 2 empty, den 3 a short name at Sanctum, den 12 a mid-length name at Hall.
-- The rock face over a tunnel is taken at the cavern's radius (WorldService finds
-- it by raycast).
local World = Config.World
local hub = World.hub
local root = Instance.new("Folder")
root.Name = "World"
local hubFolder = Instance.new("Folder")
hubFolder.Name = "Hub"
hubFolder.Parent = root
local denIndex = 0
for segment = 1, hub.segments do
	local kind = Layout.segmentKind(segment)
	if kind == "den" then
		denIndex += 1
		local den = Instance.new("Model")
		den.Name = `Den{denIndex}`
		DenDoor.front(den, denIndex)
		den.Parent = hubFolder
	elseif kind == "tunnel" then
		local angle = Layout.segmentAngle(segment)
		-- (over the tunnel's crown, Cave.TUNNEL_TOP; an older Cave has none)
		local crown = (Cave :: any).TUNNEL_TOP
		local boardY = (if crown then crown else (hub.tunnelHeight / 2 - 2) * 2 + 1) + 4.6
		local board = Plaza.tunnelBoard(hubFolder, angle, hub.radius - 0.6, boardY)
		for side = -1, 1, 2 do
			Decor.lantern(hubFolder, board * CFrame.new(side * 13.6, -0.6, -1.2), -side, true, 26, Color3.fromRGB(110, 220, 235))
		end
	end
end
Plaza.build(hubFolder)
Plaza.vendors(hubFolder)
DenDoor.setSign(1, "xXDillionaire1380Xx_", "Nook")
DenDoor.setSign(3, "Bob", "Sanctum")
DenDoor.setSign(12, "Dillionaire138", "Hall")
DenDoor.setSign(11, "Mia Ocean", "Burrow")
local wheelAngle = math.rad(Config.Wheel.angle)
local wheelAt = hub.center + Vector3.new(math.cos(wheelAngle), 0, math.sin(wheelAngle)) * Config.Wheel.radius
TreasureWheel.build(hubFolder, Vector3.new(wheelAt.X, Plaza.WHEEL_GROUND, wheelAt.Z), hub.center, Config.Wheel.segments, {
	{ left = "Every 4 hours", right = "+1" },
	{ left = "Bounty Chest", right = "+1" },
	{ left = "Catch of the Week", right = "+2" },
	{ left = "Daily streak days 3 and 6", right = "+1" },
}, "Free spins come online or off, up to 3 waiting. Busy? Spin anyway to join the line.")
local t, c, q, s = countParts(root)
print(string.format("C|%d|%d|%d|%d", t, c, q, s))
dumpParts(root)
