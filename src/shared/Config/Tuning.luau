--!strict
-- Feel and balance numbers. Everything here is a first guess for the graybox
-- prototype; the economy sim settles the progression ones later.
return {
	size = {
		lengthScale = 2, -- body length in studs = lengthScale × mass^(1/3)
		startMass = 1, -- a brand-new fish (2 studs long)
		-- A dive grows you live up to this many times your banked length; the Haul
		-- keeps counting past it, but you have to bank to grow further
		haulLengthCap = 1.75,
		levelGrowth = 1.108, -- banked mass ×this per level (level 100 ≈ 26,000× start)
		maxLevel = 100,
		stages = {
			{ name = "Fry", level = 1 },
			{ name = "Juvenile", level = 10 },
			{ name = "Adult", level = 30 },
			{ name = "Apex", level = 60 },
		},
	},

	swim = {
		baseSpeed = 15, -- studs/s for a 1-stud fish; scales with length^speedExponent
		speedExponent = 0.42,
		accel = 2.6, -- reaches top speed in about 1/accel seconds
		turnRate = 4.4, -- radians/s the heading can swing for a 1-stud fish
		turnExponent = -0.32, -- big fish turn slower
		drag = 1.7, -- per second, coasting with no input
		verticalShare = 0.85, -- how much of top speed the up/down keys give
		-- A stick pulled back (controller, phone): brake at this rate, then back up at
		-- this share of top speed
		brake = 5,
		reverseShare = 0.3,
		-- The Nibbler's Dash (owner, 2026-10-06: its only ability, "a small boost swim
		-- that recharges"): a short burst of speed with a tail flick, then a recharge
		boostMultiplier = 2.1, -- Dash speed, × top speed (also the server's eat slack)
		dashSeconds = 0.5,
		dashRecharge = 3.5, -- seconds to recharge (Deep Gills shortens it)
		lungeSpeed = 1.7, -- a bite lunge's speed, × top speed
		lungeSeconds = 0.2,
		biteCooldown = 0.6,
		maxRoll = math.rad(42), -- bank angle into turns
		rollFromTurn = 0.32, -- bank radians per radian/s of turning
		maxPitch = math.rad(80),
		idleBob = 0.25, -- studs/s hover bob while idle
	},

	camera = {
		-- Studs behind a fish, plus perLength × its length. A new 2-stud Nibbler sits
		-- about 7 studs out (it was 13 and read as a dot, playtest 2026-10-06).
		baseDistance = 2,
		perLength = 2.4,
		zoomMin = 0.6, -- the mouse wheel scales the distance within these
		zoomMax = 1.8,
		zoomStep = 0.1,
		-- The camera stays this far off rock: × the fish's length, within the limits
		clearance = 0.15,
		clearanceMin = 0.25,
		clearanceMax = 2.5,
		height = 0.35, -- look-at point above the fish, × its length
		fov = 70,
		boostFov = 80,
		focusSpring = 11, -- how tightly the look-at point follows the fish (Hz-ish)
		maxLag = 0.8, -- the look-at point trails the fish by at most this × its length
		distanceSpring = 4, -- how quickly the camera pulls back as you grow
		mouseSensitivity = 0.0032, -- radians per pixel
		touchSensitivity = 0.0055,
		gamepadSpeed = 3.4, -- radians/s at full stick
		-- A stick's sideways push turns the aim: the fish's own turn rate × steerScale,
		-- within these (radians/s), so the camera and the fish turn together
		steerScale = 0.75,
		steerMin = 0.9,
		steerMax = 2.6,
		minPitch = math.rad(-80),
		maxPitch = math.rad(80),
	},

	hunt = {
		swallowRatio = 0.7, -- swallow anything shorter than this × your length
		preyGain = 1, -- Haul per kg of prey eaten
		playerHaulShare = 0.5, -- of an eaten player's Haul goes to the eater
		playerBaseShare = 0.15, -- of an eaten player's banked mass goes to the eater
		mouthOffset = 0.5, -- the mouth sits this many lengths ahead of the center
		reach = 0.42, -- eat reach around the mouth, in lengths (generous: eating should feel easy)
		biteDamage = 24, -- a bite from an equal-sized fish
		health = 100,
		regenDelay = 4, -- seconds after the last hit before healing starts
		regenPerSecond = 10,
		spawnProtection = 6, -- seconds of safety after respawning
		leaveHubProtection = 4, -- seconds of safety after swimming out of the hub
		respawnSeconds = 3,
		bankMultiplier = 1, -- the den's Haul Chamber will raise this
		-- Server slack for eats: the server sees your fish a little in the past
		latencySeconds = 0.35,
		reachSlack = 4,
	},

	-- Healing (owner, 2026-10-07: "a healing element for boss fights, PvP and PvE").
	-- Kelp Wraps are the consumable (Config/Shop sells them, medkelp fronds and prey
	-- drop them, chests hold them); eating prey heals a little too.
	heal = {
		wrapFraction = 0.4, -- of max health, over wrapSeconds
		wrapSeconds = 4,
		wrapCooldown = 18,
		wrapMax = 5, -- carried at once
		wrapSlow = 0.7, -- swim speed while a wrap heals (the PvP counterplay)
		eatBase = 0.02, -- eating prey heals this fraction of max health...
		eatPerKg = 0.005, -- ...plus this per kg of prey
		preyDropChance = 0.03, -- a wrap tucked in a prey fish
	},

	economy = {
		-- Coral for banking a Haul: bankCoral × √(kg banked), so it grows with you
		-- without running away late
		bankCoral = 6,
		eatPlayerCoral = 20, -- for eating a player your size (less for smaller)
		-- DNA (unlocks species): prey this heavy or heavier always carry some (1 per
		-- this many kg); smaller prey carry 1 at this chance; forage at forageDnaChance
		dnaBigMass = 2,
		dnaChance = 0.25,
		forageDnaChance = 0.04,
	},
}
