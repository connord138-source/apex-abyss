--!strict
-- Sea life that helps (owner, 2026-10-20: "fish that are not edible such as turtles
-- and stingrays manta rays need to have some kind of function whether it is a buff
-- where they swim with you and provide a bonus or something similar"). The creatures
-- are Config/Ambient's, drawn on each client (AmbientLifeController); the server checks
-- what it can of a claim (CompanionService: out of the hub, in a biome they live in,
-- near the floor for a ray, cooldowns) and keeps every reward small and timed.
--
--   turtle  swim beside a sea turtle for `join` s and it swims with you for `lasts` s
--           (everyone sees it at your side): bites on you hurt ×`bite` (players,
--           predators, bosses; not the crushing deep). It leaves for `cooldown` s.
--   manta   ride in a manta's wake (behind it within `behind` × its span, inside
--           `width` × its span of its line, swimming its way) for `ride` s and its
--           current carries you: ×`speed` top speed for `carry` s, renewed while you
--           stay in it (like a podmate's slipstream; SpeedService allows it). A manta
--           cruises at 4–6.5 studs/s, slower than any fish, so a buff only while
--           inside its wake was gone the moment you passed it (PC 2026-10-20: never
--           held long enough to measure).
--   ray     skim low (within `over` studs) over a stingray resting on the sand and it
--           bursts away in a cloud of sand, stirring up `shells` shells; one every
--           `cooldown` s, and that ray's gone from your view for `hidden` s.
return {
	turtle = {
		join = 2,
		reach = 1.8, -- × the turtle's length, from its middle
		lasts = 300, -- (owner, 2026-10-20: "sea turtle buffs should last for 5 minutes"; was 90)
		cooldown = 240,
		bite = 0.8,
		-- Where it swims beside you (× your drawn length, then its own), and how fast
		-- it catches up (a spring rate, per second)
		side = 0.9,
		back = 0.35,
		follow = 3.5,
	},
	manta = {
		speed = 1.3,
		behind = 3,
		width = 1,
		align = 0.3, -- the cosine your heading must reach with its heading
		ride = 0.4,
		carry = 8,
	},
	ray = {
		over = 9,
		reach = 0.75, -- × the ray's span, flat from its middle
		shells = 8, -- (owner, 2026-10-20: "stingrays should definitely stir up more than 2 shells"; was 2)
		cooldown = 90,
		hidden = 60,
	},
}
