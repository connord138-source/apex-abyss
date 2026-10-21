--!strict
-- Feel and balance numbers. Everything here is a first guess for the graybox
-- prototype; the economy sim settles the progression ones later.
return {
	size = {
		lengthScale = 2, -- raw length in studs = lengthScale × mass^(1/3)
		-- The drawn length grows the same each level (owner, 2026-10-20: "the growth
		-- is linear"; Shared/Size `length`): 2 studs at LV 1, ~0.15 more a level, to
		-- `lengthTop` at LV 100, then a soft cap at `lengthCap` (owner, 2026-10-14:
		-- "Each den should be large enough that a max size player can fit in it ...
		-- max size for fish should all be relatively the same but not ridiculously
		-- large"). LV 10 3.4 studs, 25 5.6, 50 9.4, 75 13.1. The Reef Shark predator
		-- is 14. Size ratios and swim speed still use the raw length (Size `raw`).
		lengthTop = 16.9,
		lengthCap = 17,
		startMass = 1, -- a brand-new fish (2 studs long)
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
		-- ...up to `speedKnee` raw studs (about LV 33, 31.8 studs/s), then it eases
		-- toward `speedCap` (owner, 2026-10-18: "Speed also scales far too high from
		-- level 1 to lvl 100. A lvl 100 cuda can make it across the map in like 5
		-- seconds ... I do like how the bigger a fish is the easier they catch smaller
		-- prey though"). A Nibbler: LV 1 20, LV 30 30, LV 60 41, LV 80 46, LV 100 49
		-- (was 83), a full Haul at LV 100 50: ~61 s across the 3,000-stud map (was 36).
		-- Under the knee nothing changed; every size is still faster than any smaller.
		speedKnee = 6,
		speedCap = 56,
		-- Easier handling (owner, 2026-10-16: "some adjustments need to be made to make
		-- movement a tad easier"): quicker to answer (accel 2.6 → 3.1), stops sooner
		-- when you let go (drag 1.7 → 2.3), carves a little tighter at speed
		-- (`cruiseTurn`), and a camera tipped only a little up or down swims level
		-- (`levelZone`), so the fish no longer drifts up or down while you look about
		accel = 3.1, -- reaches top speed in about 1/accel seconds
		turnRate = 4.4, -- radians/s the heading can swing for a 1-stud fish
		turnExponent = -0.32, -- big fish turn slower
		-- Easier navigating (owner, 2026-10-17: "Still a bit difficult to navigate the
		-- fish"; SwimController, measured with tools/tests/run_swim.sh):
		-- * Letting go glides, then settles: drag plus a steady brake (`stopBrake` ×
		--   top speed a second) ends the slow creep that overshot a shell. From full
		--   speed it stops in ~0.9 s (was 1.3–1.9 s) and coasts ~25% less.
		drag = 2.0, -- per second, coasting with no input (was 2.3, with no brake)
		stopBrake = 0.35,
		-- * Turning comes from speed: still it pivots (`pivotTurn`), at speed it carves
		--   (`cruiseTurn`), blended between `pivotBelow` and `carveAbove` of top speed
		--   (it was a hard step at 25%, where the rate halved).
		pivotTurn = 2.6,
		cruiseTurn = 1.2, -- turn rate at speed, × the fish's own (it was 1)
		dashTurn = 0.75, -- mid-Dash
		pivotBelow = 0.15,
		carveAbove = 0.75,
		-- * A hard turn sheds speed, the way a fish does: aiming more than `brakeFrom`
		--   off the way it swims eases it toward `turnBrake` × top speed (at
		--   `brakeTo`), shedding at `decel`, so a U-turn at speed pivots round tight
		--   instead of swinging wide: it carries on 35–70% less past the turn and
		--   comes round 10–45% sooner (with `bigTurn`; most for the biggest fish).
		turnBrake = 0.35,
		brakeFrom = math.rad(35),
		brakeTo = math.rad(150),
		decel = 6, -- shedding speed within top speed (a turn's brake, easing off a stick)
		-- * The heading eases into a new aim over its last few degrees (×this a second)
		--   instead of stopping dead at the turn's full rate
		turnSettle = 25,
		-- * Bodies past the size knee are drawn shorter than their raw length (Size),
		--   but speed and turning followed the raw length, so a LV 100 fish carved 3.4
		--   body lengths wide (LV 1–60: 1.7–2.4). Turning gains (raw ÷ drawn)^bigTurn:
		--   ×1.46 at LV 100, ×1.06 at LV 60, nothing below the knee.
		bigTurn = 0.3,
		-- * Indoors (the hub's cavern and tunnels, the dens) top speed is at most this
		--   (studs/s; a Dash still doubles it): a LV 100 fish (83 before the speed
		--   curve eased, 2026-10-18) crossed its 60-stud Nook in 0.7 s. Now a Nibbler
		--   under ~LV 90 (a 'Cuda under ~LV 50) never reaches it, and outside nothing
		--   changes.
		indoorSpeed = 48,
		-- * Level swimming: an aim tipped within `levelZone` of level swims level, and
		--   by `levelFull` the fish swims exactly where you look (the old ease took the
		--   whole 12° zone off every aim: aiming 26.6° down at a shell dived at 15° and
		--   swam 2.4 studs over it)
		levelZone = math.rad(8),
		levelFull = math.rad(30),
		-- * Rock glides by: the fish feels ahead (a cast the collider's size) and eases
		--   its speed into rock over its last `wallEase` seconds (never under
		--   `wallContact` × top, so it still arrives); within `wallSkin` studs none of
		--   it goes in, and what's left slides along, facing the way it slides. Pressed
		--   head-on it slows enough to pivot away. (The physics stopped the fish, but
		--   the swim still thought it was at full speed into the rock: it faced the
		--   wall, slid at half speed and carved round slowly.)
		wallEase = 0.12,
		wallContact = 0.12,
		wallSkin = 0.08,
		verticalShare = 0.85, -- how much of top speed the up/down keys give (straight up or down, alone)
		-- A stick pulled back (controller, phone): brake at this rate, then back up at
		-- this share of top speed
		brake = 5,
		reverseShare = 0.3,
		-- A stick pushed only sideways cruises along the aim at up to this share of top
		-- speed, so the fish carves round with the camera (owner, 2026-10-07)
		turnCruise = 0.35,
		-- The Nibbler's Dash (owner, 2026-10-06: its only ability, "a small boost swim
		-- that recharges"): a short burst of speed with a tail flick, then a recharge
		boostMultiplier = 2.1, -- Dash speed, × top speed (also the server's eat slack)
		dashSeconds = 0.5,
		dashRecharge = 3.5, -- seconds to recharge (Quick Recovery shortens it)
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
		-- ...where the length is the banked length to this power plus this share of
		-- a dive's live growth. 1.0 keeps a grown fish's share of the screen about
		-- the same (owner, 2026-10-18: "As the fish grows the FOV needs to be slightly
		-- moved back so the fish isnt taking up more of the screen"; at 0.85 a
		-- 17-stud fish filled ~1.85× the screen a new one did); the bank's growth
		-- sequence shows the growth instead
		growFraming = 1.0,
		growHaul = 0.3,
		-- and the lens widens by up to this many degrees as the fish grows to the
		-- size cap (it sees more round a big fish)
		growFov = 6,
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
		lagKnee = 0.5, -- ...easing toward it past this share of it (it hit the limit dead)
		-- Against a roof or the seabed the camera slides along the rock, by how flat it
		-- is: none under this much of the normal's height, all of it from `slideFull`
		-- (it was all or nothing at 0.6: on a den's arched vault it popped in and out)
		slideFrom = 0.45,
		slideFull = 0.75,
		distanceSpring = 4, -- how quickly the camera pulls back as you grow
		mouseSensitivity = 0.0032, -- radians per pixel
		touchSensitivity = 0.0055,
		gamepadSpeed = 3.4, -- radians/s at full stick
		-- Stick shaping (owner, 2026-10-17: "Still a bit difficult to navigate"; Input):
		-- the right stick's tilt past its dead zone to `gamepadCurve`, so a light push
		-- aims finely and full tilt is unchanged (half tilt 1.4 → 0.75 rad/s); the left
		-- stick's (and phone stick's) steer ignores a sideways wobble under
		-- `steerDeadZone` × the throttle and eases in to `steerCurve`, so pushing ahead
		-- doesn't slowly turn the view; the phone stick gets a dead zone of its own
		gamepadCurve = 1.7,
		steerDeadZone = 0.12,
		steerCurve = 1.25,
		touchDeadZone = 0.1,
		-- A stick's sideways push turns the aim: the fish's own turn rate × steerScale,
		-- within these (radians/s), so the camera and the fish turn together
		steerScale = 0.75,
		steerMin = 0.9,
		steerMax = 2.0, -- 2.6 (149°/s) spun a small fish's view too fast (playtest 2026-10-07)
		minPitch = math.rad(-80),
		maxPitch = math.rad(80),
	},

	-- How fast eating grows you. A full Haul holds a set amount of food (kg of fish
	-- eaten) and banks a set number of levels, both by the fish's banked level
	-- (Shared/Size `haulFood`, `haulLevels`, `haulCap`, `haulRate`), between the points
	-- as straight lines (the food's in log space). History: 2026-10-18 "You should
	-- level up a lot slower" (a full Haul was +12 levels in 16 s); 2026-10-19 the
	-- first retune held a full Haul to 0.75 of a level of tiny grams (LV 100 in ~22 h);
	-- then the owner, the same day: "No reason that a full haul for nibbler should
	-- start at .2kg and only go up by .01 a level ... The first fish you eat are worth
	-- far too little food right now. A full haul should take 15-20 fish first time and
	-- hold more each time allowing them to level up faster and faster while taking
	-- more risk with a larger haul."
	-- * `food`: kg of food a full Haul holds. What the Haul card and the pops show is
	--   food (a 0.4 kg Garibaldi: "+0.4 kg"); it never drops from one level to the
	--   next (the biome's fish set the count: a tuna is 35 kg, a Rattail 6). Everyday
	--   food (prey, filler food, chum, slicks, bait, whale chunks, kills,
	--   predator loot) stops at a full Haul: MAX SIZE, swim home and bank. Rewards (a
	--   boss's Haul, a treasure's, the admin's) go on top, and a Second Chance gives
	--   back what was lost.
	-- * `cap`: levels a full Haul banks: 5, the first one too (Config/Tutorial
	--   HAUL_LEVELS: LV 1 → 6) and every one after (owner, 2026-10-20: "a full load
	--   from lvl one ... sends you to level 8 but then it takes two more full loads to
	--   get to level 10 ... the growth is linear. Less than one to one level per load
	--   is far too low"; it was 7 for a new fish, then 1 at LV 8 rising to 2). With the
	--   drawn length linear in level (`size.lengthTop`) every full Haul grows a fish
	--   ~0.7 ft. The food a full Haul holds still climbs, so later Hauls are bigger
	--   and riskier: ~18 fish at first, ~35 at LV 11, ~90 at LV 25, ~150 at LV 40,
	--   ~220 at LV 55, ~300 at LV 70, ~440 at LV 100 (fewer where the fish are big:
	--   the Open Blue's tuna).
	-- The growth a kg of food gives (`haulRate`) is the cap's kg over the food.
	-- Measured by tools/tests/run_progress_sim.sh (MODE=design suggests points for a
	-- count of fish a Haul and levels a bank; rerun after changing these, Config/Prey,
	-- Config/Forage, the biomes' levels or the size and speed curves).
	-- What a bank pays (coral, Tide Pass XP, the map chance) is reckoned from the food
	-- (HuntService Session `worth`).
	growth = {
		food = {
			-- (refitted 2026-10-20 to the fuller sea, Config/Prey `fill`: with ~2.3× the
			-- fish a hunter finds bigger ones sooner, so the same kg took fewer fish)
			{ 1, 1.9 }, -- the tutorial: ~20 of the kelp's fish (2.1 until the wider fish sizes, 2026-10-20)
			{ 8, 6.9 },
			{ 10, 10.4 },
			{ 12, 25 },
			{ 15, 41.5 },
			{ 18, 63.5 },
			{ 21, 121 },
			{ 25, 180 },
			{ 30, 353 },
			{ 35, 560 },
			{ 40, 1130 },
			{ 45, 3750 },
			{ 50, 5000 },
			{ 55, 5600 },
			{ 60, 6000 },
			{ 65, 6650 },
			{ 70, 13000 },
			{ 80, 15000 },
			{ 90, 16800 },
			{ 100, 17500 },
		} :: { { number } },
		cap = {
			{ 1, 5 },
			{ 100, 5 },
		} :: { { number } },
		-- Food in a biome below the fish counts for less (× this on the Haul; HuntService,
		-- prey and filler food): past the top level of the biome the fish is in
		-- (Config/Biomes `maxLevel`) it drops by `slope` a level, to no less than
		-- `floor` (Shared/Size `overLevel`), and the HUD says "Too easy here". So a fish
		-- keeps moving deeper with its level (the Open Blue's tuna would carry a fish to
		-- LV 100; run_progress_sim.sh STAY=OpenBlue).
		overLevel = { slope = 0.1, floor = 0.15 },
	},

	hunt = {
		swallowRatio = 0.7, -- swallow anything shorter than this × your length
		preyGain = 1, -- Haul per kg of prey eaten
		playerHaulShare = 0.5, -- of an eaten player's Haul goes to the eater...
		-- ...plus this many of the eaten fish's full Hauls (Size.haulCap; it was 15% of
		-- its banked mass × the Haul rate), × how near its size was (HuntService)
		playerBaseHauls = 0.25,
		mouthOffset = 0.5, -- the mouth sits this many lengths ahead of the center
		reach = 0.42, -- eat reach around the mouth, in lengths (generous: eating should feel easy)
		biteDamage = 24, -- a bite from an equal-sized fish
		-- Health never comes back on its own (owner, 2026-10-11: "Health should not
		-- regenerate that is the whole point of kelp wraps"): Kelp Wraps, eating prey
		-- (heal.eatBase/eatPerKg) and a respawn are the only ways back up
		health = 100,
		spawnProtection = 6, -- seconds of safety after respawning
		leaveHubProtection = 4, -- seconds of safety after swimming out of the hub
		respawnSeconds = 3,
		bankMultiplier = 1, -- the den's Haul Chamber will raise this
		-- Server slack for eats: the server sees your fish a little in the past
		latencySeconds = 0.35,
		reachSlack = 4,
	},

	-- Prey that outsize a player turn on them (owner, 2026-10-07: "the fish that the
	-- player cannot eat yet because they are too small need to briefly chase the
	-- player at a slow speed and hurt them if they get too close"). AggroService
	-- starts a short chase on the shared path; the fish darts at the player and nips
	-- if it reaches them. Nothing here one-shots.
	aggro = {
		ratio = 1.15, -- a prey fish this many times the player's length (or more) is a threat
		range = 24, -- studs from the fish's path position to the player to start a chase
		seconds = 2.4, -- the whole chase, out and back
		lungeAt = 1.25, -- when in the chase the nip lands (seconds)
		reach = 2.5, -- studs past the fish's half-length the nip reaches
		fraction = 0.07, -- of the player's max health, plus...
		perKg = 0.003, -- ...this per kg of the fish, capped at
		maxFraction = 0.2,
		cooldown = 7, -- seconds before the same fish chases again
		playerCooldown = 3.5, -- seconds before the same player is chased again
	},

	-- Light in the pitch dark of the Trench (owner, 2026-10-09: "there should still be
	-- about 5-10% visibility with no light, and visibility with a light source scales
	-- with how rare the light source is"). OceanController keeps `ambient` (and the
	-- plankton's `plankton` where it's thickest) when the light goes out, and the haze
	-- turns `water`, so rock and fish read as dim shapes; LampController lights each
	-- fish by its best source. Raised a step (owner, 2026-10-09: "the abyss can't be
	-- completely black how the hell will anyone fight anything in pitch black or low
	-- visibility let alone a boss"); near a boss the dark lifts much further
	-- (OceanController.setBossLight).
	-- The Trench is creepy, not black (owner, 2026-10-11: "Let's just go with a creepy
	-- vibe for the trench and keep it darker but not pitch black people aren't going
	-- to want to go there. The light affects will still make a difference"): the
	-- dark keeps a dim, cold, drained light (`ambient`, more where the plankton is
	-- thick), a sliver of the light from far above (`sun`, `environment`), and the
	-- water is a murky green-teal (`water`, `decay`, `density`) that things loom out
	-- of, never a black void; `grade` tints and drains it a little and adds contrast.
	-- A fish's own light still lifts the dark round it by its rarity (`sources`).
	light = {
		ambient = Color3.fromRGB(58, 76, 80),
		plankton = Color3.fromRGB(64, 96, 98),
		sun = 0.14, -- share of the sun left
		environment = 0.3, -- share of the environment's light left
		water = Color3.fromRGB(20, 44, 48),
		decay = Color3.fromRGB(7, 20, 24),
		-- (0.7 until 2026-10-18: a little clearer with the rest of the sea, still the
		-- murkiest water in it; the deep biomes' floors are 0.59–0.65)
		density = 0.66,
		exposure = 0.1,
		grade = { tint = Color3.fromRGB(206, 228, 220), saturation = -0.22, contrast = 0.1 },
		-- Each light source, rarest last: the glow's range and brightness, the forward
		-- beam's brightness (0 = none: a glowing skin shines all round), and how much
		-- of the dark it lifts from its holder's own view. A fish uses its best one.
		-- `lantern` is the Deep Lantern (350 coral), `lure` the Anglerfish's lure (a
		-- Trench species); the rest are glowing shades by tier (Config/Shades
		-- `emissive`, and the spectral Ghost).
		sources = {
			Common = { range = 24, brightness = 1.3, beam = 0, reveal = 0.05 },
			Uncommon = { range = 26, brightness = 1.35, beam = 0, reveal = 0.07 },
			lantern = { range = 30, brightness = 1.6, beam = 2.2, reveal = 0.1 },
			Rare = { range = 28, brightness = 1.4, beam = 0, reveal = 0.1 },
			Epic = { range = 36, brightness = 1.9, beam = 0, reveal = 0.16 },
			lure = { range = 46, brightness = 2.6, beam = 3.6, reveal = 0.24 },
			Legendary = { range = 48, brightness = 2.6, beam = 0, reveal = 0.26 },
			Mythic = { range = 60, brightness = 3.2, beam = 0, reveal = 0.34 },
			Trophy = { range = 60, brightness = 3.6, beam = 0, reveal = 0.38 },
			Abyssal = { range = 60, brightness = 3.6, beam = 0, reveal = 0.38 },
		} :: { [string]: { range: number, brightness: number, beam: number, reveal: number } },
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
		bankCoral = 7, -- (was 6: a fish now stays smaller mid-dive, so it reaches richer prey later)
		eatPlayerCoral = 20, -- for eating a player your size (less for smaller)
		-- DNA (unlocks species): prey this heavy or heavier always carry some (1 per
		-- this many kg); smaller prey carry 1 at this chance; forage at forageDnaChance
		dnaBigMass = 2,
		dnaChance = 0.25,
		forageDnaChance = 0.04,
	},
}
