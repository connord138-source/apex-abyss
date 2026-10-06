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
		baseDistance = 7, -- studs behind a fish, plus perLength × its length
		perLength = 3.1,
		height = 0.35, -- look-at point above the fish, × its length
		fov = 70,
		boostFov = 80,
		focusSpring = 9, -- how tightly the look-at point follows the fish (Hz-ish)
		distanceSpring = 4, -- how quickly the camera pulls back as you grow
		mouseSensitivity = 0.0032, -- radians per pixel
		touchSensitivity = 0.0055,
		gamepadSpeed = 3.4, -- radians/s at full stick
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
