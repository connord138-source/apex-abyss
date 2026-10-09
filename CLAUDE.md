# APEX ABYSS — Roblox game (read this first)

A third-person underwater eat-and-grow game. You start as a small fish, eat your way up
to an apex predator, and bank your growth at your den in a cave hub. PvP is always on,
and small players can school together to take down a big one. The full design is in
`docs/GDD.md`.

Repo: `connord138-source/apex-abyss`. It is a sister game to Hatch & Snatch
(`connord138-source/hatch-and-snatch`), made by the same owner and team. Only
game-agnostic plumbing was ported from there (save data, purchase receipts, remotes,
guarded loops, state sync). Everything about this game is new.

## Owner's machine

- Local clone: `C:\Users\neos1\Desktop\apex-abyss` on Connor's Windows PC (the same
  layout as Hatch & Snatch).
- Work branch: `claude/core-systems`. `main` holds the initial setup.
- Start syncing from that folder with `rokit install`, then `rojo serve`, and connect
  the Rojo plugin in Studio.
- Division of work: Claude does the building (code and Studio). Since 2026-10-07
  (owner) a Claude session on Connor's PC both builds and play-tests (keyboard,
  Controller Emulator, Device Simulator) and writes the reports.
- Instructions for the owner's PC session must be written as a **paste-ready prompt**.
- The owner prefers compact, decision-focused replies and keeping conversation context.

## Decisions already made (do not re-litigate)

Every decision below was made with the owner on 2026-10-06. The details are in `docs/GDD.md`.

- **Title:** Apex Abyss. The live title is "Apex Abyss 🦈 Eat & Grow", and the brand is
  a clean APEX ABYSS. The name was checked unused on Roblox (games and groups) and the
  web. The owner also liked "Frenzy Depths" as the runner-up.
- **Reference:** the trending Fortnite UEFN fish maps "Be a fish" (civistudios) and
  "BE FISH" (ickrisp). We add twists, never copies.
- **Core loop: Hunt & Haul** (the owner approved the design and disliked its first name,
  "Dive & Molt"):
  - Permanent progress: level, stage, evolutions, skins and the den.
  - The mass you eat on a dive is your **Haul**, which grows you live up to a cap.
  - Swim home to **your own den** to bank it as XP.
  - Getting eaten loses the unbanked Haul, which bursts into chum, and the eater gains
    a share. Permanent progress is never lost.
- **Eating:**
  - Under ~70% of your size: swallowed whole, sucked into the mouth.
  - ~70–130%: a bite fight with health.
  - Over 130%: it eats you.
  - XP from eating a player scales with the size ratio, so farming new players pays
    almost nothing.
- **PvP:** always on in the biomes, with protections.
  - The hub plaza and the dens are safe, and there's spawn protection.
  - Size-gated terrain gives small fish places to hide.
  - Chum clouds, an Apex bounty on the biggest player, and baited hooks dropped by boats.
- **Teams:**
  - **Schooling:** nearby small players' combined mass can bite a bigger predator. This
    is the headline twist.
  - **Pods of up to 3:** no friendly fire, a slipstream speed boost and shared kill XP.
- **Servers:** 12 players.
- **Species (owner, 2026-10-06):**
  - **Everyone starts as the same small googly-eyed fish** (working name Nibbler).
    - A tutorial levels it up before other species can be picked.
    - The starter stays upgradeable as an all-rounder; the other species each
      specialize.
  - **Each species levels up separately.**
  - **Each species has its own upgrade tree**, with a few ability options to pick in it.
  - **At least 4–5 playable species in the first version**, unlocked through the
    biomes.
  - **Food:** calm fish plus aggressive AI predators worth more, different per biome.
  - **Lots of rare color pulls and body-part changes.**
  - **Claude's proposal was approved ("Love it!")** and is in GDD §7:
    - six species
    - their abilities
    - DNA unlocks at the Old Hermit
    - the tutorial steps, with the **'Cuda** (a barracuda) as the tutorial's reward. It
      replaced the playable Squid (owner, 2026-10-06), and the Giant Squid stays a boss
      only.
    - looks-only rolled parts; power comes from the species trees
    - species-specific exotic variants
    - the per-biome food chain
  - **The Nibbler's only ability is a recharging Dash** (owner). It's built; it replaced
    the old held boost.
  - **Safe zone = the dens plus the vendor plaza.** A banner shows on leaving or
    entering it, with a protection countdown (built).
  - **Filler food:** starfish and shrimp on the seabed (built).
  - **World building:** see GDD §8 "How the world gets built".
    - Code-sculpted Terrain per biome.
    - Tripo hero props placed by scatter rules.
    - Per-biome atmosphere.
    - Sectors round the hub.
    - Not one AI-generated scene.
    - Every biome must look different (owner); the look targets are
      `assets/concepts/Biome*.jpg`. **The owner approved the looks and the layout**
      (Reef east, Wreck west, Open Blue north, Trench south).
  - **Megalodon world boss (owner, 2026-10-06):** "a massive megalodon that roams the
    map, mostly in deep blue... a very hard and scary boss" with an extreme reward.
    - Claude's design is in GDD §8: Open Blue patrol, swallows any player, telegraphed
      attacks, three phases, a whole-server fight.
    - **Rewards (owner): no playable Megalodon or Kraken.** Bosses give exclusive skins
      and den items "worth fighting for".
      - Megalodon: the pale green **Ghost** shade (ForceField shimmer), a Jaw part, a
        den jaw arch and a tooth trophy.
      - Giant Squid: the **Abyss Ink** shade, Tentacles, a den Kraken-eye lantern.
      - Teeth or Beaks from each kill buy them at a fifth stall, the **Trophy Hunter**,
        and there's a chance of a direct drop.
      - Plus a huge Haul, a coral jackpot, a Rare-or-better roll and a title.
      - Boss shades have `boss` set in `Config/Shades.luau` and are kept out of the roll
        odds.
    - It's built with the AI predators (not built yet, 2026-10-07).
  - **Boss rules (owner, 2026-10-07):** team-first but soloable (solo in 8–10 min is
    fine; health +60% per extra attacker), **nothing one-shots** (boss damage is a
    share of max health: Megalodon bite 55%, Squid grab 15%/s), separate phases with
    different attacks per boss, **no minions** in boss fights yet, and a **healing
    element** for boss fights, PvP and PvE: Kelp Wraps (40% over 4 s, 18 s cooldown,
    slower while healing; from medkelp fronds, the Tidecharm Trader for coral, prey
    drops and chests; never Robux) plus eat-to-heal on prey. Look: Schedule I
    stylization with undersea horror in the presentation (darkening water, drone,
    silhouettes, glowing eyes; no gore). GDD §8 "Boss rules" and "Healing".
  - **Giant Squid world boss (owner):** "a giant squid that roams the map as well, they
    could be world events".
    - **Bosses are world events:** about every 30 minutes one rises, announced two
      minutes ahead. The Megalodon (Open Blue) and the Giant Squid (Trench and deep
      edges) take turns.
    - The squid's tentacle grabs break free by mashing or by others biting the
      tentacle. Its ink blinds, and tentacles can be bitten off.
    - Its Kraken Beaks buy its trophies. Details in GDD §8.
  - **Level gating (owner):** biomes have suggested levels. Entering one above your
    fish's level shows a "too dangerous, come back stronger" warning (built:
    `Config/Biomes.luau`, `Shared/Biomes.luau`, `BiomeController`).
  - **Frozen Shelf is dropped for now** (owner: not much sea life; maybe a later
    update). The **Sunken Ruins replace it** (owner approved).
- **Creatures:**
  - Lines grow Fry → Juvenile → Adult → Apex.
  - Hard evolutions branch off at Apex with conditions and show as ??? in the Index
    (Megalodon, Kraken, Leviathan Eel, Void Manta).
  - **Art is stylized, chunky low-poly, Schedule I meets Abzû** (owner, 2026-10-06:
    "cartoony feel similar to schedule 1 if that helps"; Claude chose it).
    - Flat-shaded facets, bold colors, simple eyes; small fish cute and goofy, big ones
      menacing.
    - The concepts are in `assets/concepts/`, waiting for the owner's approval before
      3D conversion.
    - This replaces the Sonaria-style plan.
- **Rolls (owner, 2026-10-06):**
  - Collect **Shells** around the sea. Each player has their own copy of each, they
    respawn for you after 4 minutes, golden ones in the trench are worth 5, and big
    prey can drop them.
  - **50 Shells = 1 roll**, mostly **Coral**.
  - Rare **shades**: tints, then Lunar 1/120, Diamond 1/250, Divine 1/500, Exotic 1/900,
    Prismatic 1/1,500.
  - Very rare **Abyssal** body parts (1/4,000–6,000) and exotic variants (Puffer,
    Hammerhead).
  - Duplicates turn into coral, Lucky Charms give ×2, and rare rolls are announced.
  - The exact odds add up to 100% (`Shared/RollOdds`, tested by
    `tools/tests/run_odds.sh`).
  - Add more shades and exotics as we build (table entries plus Cosmetics geometry).
  - **Shades are per fish (owner, 2026-10-08: "the shades will also apply to all fish
    interchangeably. They will just need to be unlocked again for that fish. Once a
    shade is unlocked for a playable fish it will not roll again"):** each species
    record holds its own `shades` set and the `shade` it wears (`Server/Progress`
    `shades/ownsShade/grantShade/wearShade/syncShade`); a switch puts on that fish's
    own shade. Rolls, the Dyer, the Trophy Hunter, boss drops and treasure all unlock
    for the fish you're swimming as. `RollOdds.table(luck, owned)` leaves the fish's
    shades out and gives their share to coral, so every other chance stays the same
    and the odds panel (this fish's table) still sums to 100%
    (`tools/tests/run_odds.sh` checks it). Boss and treasure shade rolls skip owned
    ones too. The wardrobe names a shade another of your fish has ("unlock it again
    for this one", `state.otherShades`). Old saves: the global `data.shades` was
    copied to every unlocked fish and emptied.
- **Coral and vendors (owner, 2026-10-06):** Coral is the currency. Four vendor stalls
  round the hub plaza, near the dens, sell with it:
  - Outfitter: upgrades.
  - Den Mason: the Haul Chamber.
  - Tidecharm Trader: Lucky, Second Chance, Magnet and Feast charms, plus 10 shells for
    400 coral 5 times a day.
  - Shade Dyer: tints.
  - More ways to spend coral come later (den decor, currents, bounties).
- **World:**
  - A hub cave inside a central seamount, with 12 safe dens ringed around a plaza.
  - Tunnels lead out at different depths, so depth is progression.
  - Biomes: Kelp Shallows, Coral Reef, Shipwreck Graveyard, Open Blue, Sunken Ruins
    (replaces Frozen Shelf), Hydrothermal Vents, Abyssal Trench.
  - **Depth pressure** gates biomes, not walls.
  - The whole map is underwater, and the surface is the ceiling.
- **Tide events:** Blood Tide, Sardine Run, Whale Fall, Leviathan Rising and
  Bioluminescent Night.
- **Monetization (built 2026-10-09; owner: "ready for monetization"):**
  `Config/Monetization.luau` (names, prices, descriptions, Creator Hub ids, tuning),
  `MonetizationService` (ported from Hatch & Snatch: passes checked with Roblox on join
  and after a purchase, ProcessReceipt → `DataService.processPurchase`, PolicyService,
  rewarded ads), `Store` + `OfferController` + `MenuController.openStore` on the client.
  **Every id is 0 until the owner creates it in Creator Hub**: a live game hides id-0
  items, Studio shows them greyed out, and the admin panel grants passes and runs
  product effects without Robux. Full table in GDD §9.
  - **Rule:** sell growth and safety, never bite damage. Coral (it buys Iron Jaw) and
    Kelp Wraps are never sold for Robux.
  - **Passes:** ×2 Mass 399 (every Haul gain ×2), VIP 299 (gold nametag tag, +10%
    coral), Den Expansion 149 (the "extra den slots": spots X1–X4 at any level, `pass`
    on a `Config/Dens` slot), Deep Garden 129 (Coral Garden ×1.5 and 16 h).
  - **Second Chance** 39: bought on the eaten screen it returns the Haul just lost
    (`data.lostHaul`, once, within 3 min of being eaten); otherwise it's a charm (hold up to 5).
  - **Double Haul** (the owner's idea) 19/49/99 by the Haul's size (≤ 60 kg, ≤ 2.5 t,
    more): offered on the bank screen after the tutorial when doubling adds ≥ 2 levels;
    one tap, WATCH AD for ≤ 60 kg, SKIP, **no countdown**. It doubles after ×2 Mass and
    Server Frenzy. `lastHaul` (with its species) makes a late receipt double that haul
    once, capped at the tier paid for; a second receipt becomes a Second Chance charm.
  - **Server Frenzy** 99: ×2 growth for the server, 15 min a purchase (up to 2 h
    ahead), announced; `Workspace` attributes `Frenzy`/`FrenzyUntil` drive the HUD chip.
  - **Shell packs** 49/199 (100/600 shells): paid random items (shells buy rolls), so
    hidden for `ArePaidRandomItemsRestricted` players and with ODDS on the row.
  - Every Haul gain goes through `HuntService` `addHaul` × `MonetizationService.growth`
    (`HuntService.feed` returns what was added). Coral from play goes through
    `EconomyService.earnCoral` (VIP 1.1 × Premium 1.1 × group 1.05); fixed rewards that
    show their amount (rolls, treasure, daily, admin) use `addCoral`.
  - Cards (Double Haul, Second Chance) free the cursor, B or SKIP closes, and they go
    away when you swim out of the hub. SHOP and DAILY sit beside the wallet card; the View button
    opens the Shop on a controller.
  - **Later:** codes, Pearl crates, the Roblox group (id 0 in `tuning.group`).
- **Daily login streak (owner, 2026-10-09; built):** `Config/Daily.luau`,
  `RewardsService`, `MenuController.openDaily`. One claim a UTC day; a missed day
  restarts at Day 1; seven days loop (300 coral → … → Day 7: 2,500 coral, 100 shells
  and a Captain's map) with +25% per finished week (up to +100%). The panel opens by
  itself once a session when a reward waits (after the tutorial); DAILY glows.
- **AFK income: the Coral Garden (owner, 2026-10-09: "an afk aspect of the game to earn
  something to keep players coming back"; built):** a garden bed in every den, under
  the trophy plaques, grows coral and shells over real time, online or off, up to 8 h
  (16 with Deep Garden). Per hour by den level: 60/100/160/250 coral and 4/6/9/12
  shells. Resting in your own den grows it ×2 and collects every minute; swimming in
  collects it; a returning player spawns in the den and sees WELCOME BACK.
  `Config/Dens` `garden`, `Shared/Garden` (rates, grow, fill; luau-testable),
  `GardenService`, `DenBuilder.garden` (corals grow as it fills, sparkle when full),
  `GardenController` (the sign, payout pops, the welcome banner). Admin: "Coral
  Garden: grow hours".
- **Controls (owner, 2026-10-07):**
  - **PC stays as built** (the owner likes it): WASD swims relative to the camera (A/D
    slide sideways), the mouse aims, Space/C go up and down.
  - **Controller and phone** use the left stick as throttle and rudder: up swims along
    the aim (further is faster), sideways turns the aim, down brakes and backs up
    still facing forward. The right stick, or a drag on the screen, aims (up and down
    included).
  - **A sideways-only push also turns the fish** (owner, 2026-10-07): it cruises
    gently into the turn at about a third of top speed, so fish and camera swing
    round together.
  - **Phones get one stick** (it appears under the left thumb) plus BITE and DASH; the
    UP/DOWN buttons are gone.
- **Treasure maps (owner, 2026-10-07):** "randomly earn them... a treasure map to a
  location where they dig up a treasure for a random reward, a large kelp haul or a
  super rare skin at a low drop rate. Like clue scrolls. Only the player holding the
  map can uncover it. Map in their inventory." Built: maps drop from prey (by mass),
  shells (golden ones often) and big banks; three tiers (Tattered → Weathered →
  Captain's) set the dig site's distance band and the loot; the SATCHEL (MAPS button)
  lists them with a hint; FOLLOW gives a hot/cold sonar, an arrow inside 150 studs
  and an X only the holder sees inside 45; hold E / Y / DIG on the X to dig; the roll
  reveal opens the chest (coral, shells, a Haul worth levels, DNA, Lucky Charm, a
  shade roll, and from Captain's chests the treasure-only Sunken Gold and Drowned
  Pearl shades at ~3% each). `Config/Treasure.luau`, `TreasureService`,
  `TreasureController`, `MenuController.openSatchel`. GDD §7.
- **Bosses and fights (owner, 2026-10-07):** bosses are team-first but soloable in
  8–10 min, "nothing should be one shot", "no minions in boss fights yet", separate
  phases and different attacks per boss, cartoonish Schedule I look with "that undersea
  horror aspect". Rules and both boss designs are in GDD §8.
  - **Healing (owner: "a healing element ... for boss fights as well as PvP and PvE"):**
    built. **Kelp Wraps** heal 40% over 4 s (18 s cooldown, carry 5, swim 30% slower
    while healing, green glow everyone sees); from glowing medkelp fronds in the kelp
    (eaten like forage), the Tidecharm Trader (120 coral), a 3% prey drop and treasure
    chests; H / LB / HEAL. Eating prey heals 2% + 0.5%/kg. `Config/Tuning.luau`
    `heal`, `HuntService.giveWrap/useWrap/damage/kill`, `HealController`. Never sold
    for Robux.
  - **AI predators (owner, 2026-10-06: aggressive AI fish worth more):** built as the
    base the bosses extend. `Config/Predators.luau` (Barracuda, Reef Shark) and
    `PredatorService`: simulated at 10 Hz, roam a band round the hub, hunt the biggest
    worthwhile fish in range, telegraph every bite (0.9–1.1 s jaw flash and an INCOMING
    warning for the target), bite for a share of max health; players bite back
    (`BitePredator`, damage scaled by the length ratio, +35% per other biter in 2.5 s);
    a kill pays Haul, DNA and coral by damage share. Positions stream over an
    UnreliableRemoteEvent; `PredatorController` interpolates 0.15 s behind, draws the
    `PreyModels` mesh (parts until imported) with a red PREDATOR tag and health bar.
    A predator with `custom` set skips the plain behaviour (bosses drive it).
  - **Megalodon (built 2026-10-07):** `Config/Bosses.luau` + `BossService` on top of the
    predators. A world event about every 30 min (4 min in Studio; 2 min warning,
    `_G.ApexBoss.summon()` / `.hurt(0.5)` from the Server command bar), patrolling the
    Open Blue (north, 330–620 out). 80 studs, 6,000 hp +60% per extra attacker (20 s
    window). Three phases: Hunting (Charge 35%, Bite 55%, both telegraphed),
    Frenzy under 60% (×1.3 speed, blood cloud hides the tag, Tail sweep 20% + a shove
    when 3+ fish bunch behind it, Marked for death: 8 s of short lunges at one fish),
    Last stand under 25% (makes for the Trench on a 60 s clock, Breach every 13 s:
    sinks, rockets up, crashes with a shockwave 30% + shove, then 5 s exhausted at
    triple damage; escapes when the clock runs out and returns in 15 min). Gills and
    tail take double damage and fill the stagger meter (700); full → 4 s stagger at
    triple damage, breaks the mark. Rewards for everyone with ≥1% of the damage:
    Megalodon Teeth (1, +1 top three, +1 killer), a Haul (120 kg by share, min 10%),
    coral (5,000 by share, min 500), a Rare+ shade roll, the Megalodon Slayer title
    (worn on the nametag), and a 1/15 (×2 for the top dealer) direct drop of the
    Ghost shade. The **Trophy Hunter** (fifth stall, angle 90) sells Ghost for 12
    Teeth and Abyss Ink for 12 Kraken Beaks (`Config/Shop.luau` `trophies`,
    `data.trophies`). Client: `BossController` (countdown, boss bar with stagger
    meter and Last stand clock, dread: darker water + heartbeat contrast, NEARBY
    arrow, camera shake; reward card then the shade reveal), `PredatorController`
    draws the rigged `FishModels.Megalodon` with a spine wave and the tells (red jaw,
    amber eyes for charge/sweep/breach, gold stagger, blood cloud, shockwave ring).
    Pushes go through `Net.shove` → `SwimController.shove`.
  - **Giant Squid (built 2026-10-07):** the second boss on the same service (`kit =
    "squid"` in `Config/Bosses.luau`; the bosses take turns, `rotation`). 70 studs,
    5,500 hp, lurks deep (10–55 up off the floor) in the south, patrol band 280–560.
    Lurker: **tentacle grab** (1 s tell, range 60, 15%/s for up to 4 s; the victim's
    fish is dragged to the beak: server sets `HeldBy`/`HeldUntil` on the character,
    the client's SwimController.hold overrides the swim; mash BITE or DASH sends
    `Struggle`, 6 breaks it; 3 bites on the squid by teammates break it too and pay
    them a Kraken Beak each; hunting, it rises to meet its prey up to 260 studs off
    the floor, since clamped to its lurk band it sank away from everyone and never
    grabbed, playtest 2026-10-08; aggro 280 so it notices fish well above it; a grab
    lets go after taking 45% (`grab.maxShare`) and a fish just let go can't be
    grabbed again for 10 s (`grab.recover`): two grabs back to back killed a full
    fish, retest 2026-10-08), **ink** (6 s black cloud, 55 studs; the camera inside
    goes blind, `OceanController.setBlind`; its tag hides) straight into a **jet**
    (120 studs away). Enraged under 65%: two grabs at once, half the grab cooldown,
    **whirlpool** (1.2 s tell, 3 s pull of 30 stud/s² within 70 studs). Mantle under
    30%: rises to 90–140 up, **beak slam** (1.3 s tell, 45%, reach 14) and **siphon
    blast** (1 s tell, 15% + an 85 stud/s shove to everything in a 57° cone within 48
    studs); sinks away after 90 s. Soft spots: the eye (52–70% along the body) and
    the tentacles (0–25%). Rewards mirror the Megalodon's with Kraken Beaks, the
    Kraken Slayer title and a 1/15 drop of Abyss Ink (12 Beaks at the Trophy Hunter).
    Model: `FishModels.GiantSquid` (rigged, 6 segments, mantle forward).
  - **Oversized prey fight back (owner, 2026-10-07):** `AggroService` + `Config/Tuning`
    `aggro`: a prey fish at least 1.15× the player's length within 24 studs starts a
    2.4 s chase (one per player at a time, 7 s per-fish cooldown): every client draws
    the dart on the shared path (`Schools.chaseBlend/chasePosition`, a red outline,
    a "TOO BIG TO EAT · SWIM!" warning for the target) and at 1.25 s the server nips
    for 7% + 0.3%/kg of max health (cap 20%) if the fish reached them.
- **The world is an ocean shelf (owner, 2026-10-07: "a giant gaping hole", "biomes need
  to be spread out and clearly different ... some dependent on depth off of a ocean
  shelf that would be at the end of the lower level zones and begin the higher level
  zones. coral zone being the last of the shallower zones", "far too open"; scaled up
  2026-10-08: "the entirety of the map is still too small ... each biome made larger
  ... MUCH MUCH more depth too. Far too shallow of a map", "the lower areas are far too
  underdeveloped"):** the hub seamount stands on a shallow sand SHELF (radius 850,
  440 studs under the surface) that ends in a rock DROP-OFF (90 wide, 430 tall) to a
  deep floor at −430. Shallow biomes on the shelf: Kelp Shallows ring (150–480, LV
  1–10, the open one), Shipwreck Graveyard in the west bay (480–850 @ 135–225°, LV
  10–25), Coral Reef as the shelf's outer band everywhere else (LV 25–40, the last
  shallow zone; owner: "more larger rock structures and arches to go under", so 44
  reef heads with tunnels, 14 ridges with swim-throughs and 26 arches, with the corals
  growing on and round them, `Features.reefRocks`). Deep biomes beyond (850–1,500):
  Open Blue north (LV 35–55; owner: "a deep blue ocean that is mainly traversed for the
  megalodon and sharks with some other good haul fish like grouper and snapper", so a
  blue-grey floor, knolls and seven pinnacles, the Reef Shark predators and the
  shark/grouper/snapper schools keep to its sector), Sunken Ruins east (50–70, plus a
  temple ring), Hydrothermal Vents south-west (65–85; ten basins at −540 placed by
  `Seafloor.ventBasins`, 26 chimneys), Abyssal Trench south (80–100): a winding canyon
  in three stepped cuts from −430 down to −920 (`Seafloor.trenchAxis` and
  `trenchHalfWidths` drive both the Terrain and the nominal floor, so fish never swim
  in its walls), with ledges and basalt pillars, pitch dark. Map radius 1,500; the
  terrain runs 700 further so the floor fades into the water instead of showing an
  edge. The deep floor is a 30-stud mud slab with rock only under the canyon and the
  basins, and the shelf is a hollow drum, so the Terrain stays light. `Config/World.luau`,
  `Config/Biomes.luau` (sectors + `deep`/`dark`), `Shared/Seafloor.luau` (the nominal
  floor height anywhere; every placement and creature uses it), `src/server/Shelf.luau`
  (the Terrain fill ops). `WorldService.buildBiomes` dresses each biome on the Terrain
  by raycast. Preview from the cloud: `LUAU=<luau> bash tools/preview/run_world.sh
  <dir>` (aerial, north, south, east). Prey `zones` (band, sector, schools, depth) and
  predator `angles` put fish where a biome wants them; depths are heights above the
  local floor. Shells, forage and treasure sites raycast the Terrain only (a shell on
  a kelp blade "floated above the sea floor", owner 2026-10-08).
- **Fish facing and swim (owner, 2026-10-07: "swimming backwards", "more fluid and
  natural like a fish, not the entire body swaying"):** the static GLB prey meshes
  faced +Z and are turned round in code (`MESH_FLIP`); prey are now rigged FBX too
  (`prey_fbx` bundle, 4 spine segments; `SchoolController` swims their bones;
  `organize_imports` keeps the Models). `Shared/SwimWave.luau` is the one swim shape
  for players, prey, predators and bosses: the head holds still, the wave's amplitude
  grows as t^1.9 toward the tail, two thirds of a wavelength along the body.
  - **The rule (2026-10-08, after the Barracuda and Reef Shark predators still swam
    backwards):** a rigged Model faces -Z and is never turned; only a bare static
    MeshPart is turned, and only when it isn't stamped `Facing = "-Z"`
    (`SwimWave.needsFlip`; `organize_imports` stamps static GLB prey `+Z`). Predators
    draw rigged `PreyModels` (the 'Cuda and Reef Shark species models, copied there
    by `organize_imports`) the way bosses draw `FishModels`. Never pull the MeshPart
    out of a rigged Model and flip it.
- **Massive bosses (owner):** the Megalodon is 130 studs, the Giant Squid 95; reaches
  and radii scaled with them (`Config/Bosses.luau`). **Bosses are solid** (playtest
  2026-10-08: the Megalodon and fish phased through each other): your own fish is
  pushed out of a boss's body capsule on the client (`PredatorController` `solid`),
  set back onto the capsule's surface with only its speed into the body taken away
  (no push added, so it rests against the flank; retest 2026-10-09: a push added to
  the velocity carried on and threw fish 37–42 studs off the axis, past bite reach).
  The capsule is the same body radius biting measures to (`BODY_RADIUS`, 18% of
  length): sized from the model's full width it held fish ~40 studs off a
  Megalodon's axis (retest 2026-10-08). The server's bite check allows for the
  creature's own movement over the stream delay plus latency (`PredatorService`
  `drift`), since the biter sees it where it was a moment ago.
- **The Trench is pitch dark (owner: "clearly need a light source for abyssal trench
  ... could be the perk of the angler fish"):** `Biomes` `dark`; `OceanController.setDark`
  (BiomeController sets it below the deep floor in a dark biome). **The dark is the
  light going out, never fog or exposure** (playtest 2026-10-08: Atmosphere density
  1.0 and exposure −3.6 made it pure black even with a lantern, hiding glow skins and
  plankton): in the dark the client fades `Lighting.Brightness`, `Ambient`,
  `OutdoorAmbient` and the environment scales to near zero (the server's values are
  kept and put back), turns the haze black, and **adds no colour grade or exposure
  cut on top** (the grade goes neutral, exposure eases to +0.25) while the water thins
  to density 0.6 (`DARK_DENSITY`), so lamps, glowing skins, plankton and the walls'
  glow clusters (plain Neon, never `Props.dress`ed) all read (retest 2026-10-08: a
  ×0.5 tint and −1 exposure on top still left it black). Lamps (`LampController`)
  are a PointLight at Roblox's 60-stud maximum range (the 80–90 asked for before was
  clamped) plus a forward SpotLight beam, bright, since in the dark they're the only
  light. The Vents grade is thinner (0.84) and every chimney has a Neon glowing
  throat (`VentGlow`), since a light alone didn't read across a basin; it's seated on
  the lava cap's real top by raycast (at the nominal top 25 of 26 sat buried inside
  the cap, retest 2026-10-09). Bosses glow faintly in the
  dark (`PredatorController` `DARK_GLOW`, violet for the squid) so they're
  silhouettes, not invisible. A lamp holder's view is 15% less dark. The Anglerfish's
  lure is a lamp (`Lamp = "lure"` attribute
  from WardrobeService) and the Tidecharm Trader sells a **Deep Lantern** (350 coral,
  10 min, `Lamp = "lantern"`); `LampController` hangs PointLights on lit fish for
  everyone; the biome banner and chip say PITCH DARK · bring a light.
- **Deep bioluminescence (owner, 2026-10-08: "deepest depths should have light
  luminescense such as photoplankton etc to give very very faint light"):**
  `PlanktonController` fills the water round the camera with faint twinkling
  blue-green specks below the drop-off's foot (none on the shelf, 55% on the deep
  floor, all of it at the Trench's bottom; `glowAt`), every fish swimming through
  leaves a brief sparkling wake (by speed, within 260 studs), and
  `OceanController.setGlow` gives the pitch dark a very faint teal ambient light
  (`GLOW_AMBIENT`). WorldService lays glowing plankton mats on the deep floors
  (`PlanktonMats`: Trench 46, Vents 18, Open Blue 16, Ruins 12; every other one a dim
  PointLight). A lamp is still the real light; this only keeps the deep from being
  dead black.
- **Treasure chest (owner: "a chest partially sticking out of the ground"):** the dig
  site's X is now a chest half out of a sand mound (part-built planks and brass, or the
  `WorldProps.TreasureChest` Tripo prop, `props2_glb`), seam glowing in the map's tier
  color; the lid swings open and gold spills out when the dig completes
  (`TreasureController`).
- **Admin panel (owner, 2026-10-07; like Hatch & Snatch):** `src/server/Admin.luau`
  (who: the experience's owner or group owner, `ADMIN_USER_IDS`, anyone in Studio;
  re-checked on every call), `AdminActions.luau` (coral add/set, shells, set level,
  Haul, DNA, boss trophies, Kelp Wraps, charms, unlock species, every shade, treasure
  maps, heal, get eaten, title, restart or finish the tutorial (testers: species
  select at once), teleport to a biome, summon/hurt/dismiss a boss), `AdminController` (ADMIN button bottom-left, target me/everyone/
  next player). The `Admin` RemoteFunction answers a line of text.
- **Den bases (owner, 2026-10-07: "an upgradable base that gets bigger and deeper as
  it upgrades. Other players can go in and check out your base but can't take or do
  anything. You can display trophies ... set up furniture ... Upgrades and
  furniture/colors would cost currency. Coral lamps, etc"):** built as v1.
  `Config/Dens.luau`: four levels (Nook → Burrow 2,500 → Hall 12,000 → Grotto 45,000
  coral) that carve the room 6/12/18 studs further back into the seamount and, from
  Hall, sink a lower chamber under the floor (10 then 14 deep); 12 furniture slots
  (floor, wall, chamber) unlocked by level; a catalog of 14 pieces (Coral Lamp, Kelp
  Bed, Shell Pile, Anemone Garden, corals and sponges, Driftwood Table, Pearl
  Pedestal, a decor Treasure Chest, Bubble Column, Crystal Shard, Sea Glass Lantern,
  Sea Fan, Banner; 150–1,200 coral, bought once then free to move) and seven glow
  colors (Teal free, the rest 300) that light the lamps, banners and trophy trims.
  The record (`data.den`: level, furniture by slot, owned, glow) is in the save and
  follows the player to whichever den they hold; `DenService` (requests DenUpgrade,
  DenPlace, DenColor; only the holder can change it) builds it with `DenBuilder`
  (Terrain carve: the rock is refilled first so a freed den goes back to a Nook; parts
  with `Props.dress` for the Tripo props) when the den is assigned or changed. The
  **trophy wall** on the back wall fills itself: the biggest catch (a mounted prey
  model and its mass, `data.stats.bestPrey/bestPreyMass` from HuntService), Megalodon
  teeth and Kraken beaks taken, and the worn title over the door
  (`Events.trophies`). Visitors can swim in (dens are safe) and only look; banking
  stays owner-only. The whole carved room is safe however far it was upgraded back
  (`Layout.denAt`, used by `Layout.inHub`; the back of a Burrow was outside the safe
  zone, playtest 2026-10-08). Menu: the stall hint shows YOUR DEN at your own Haul Pool
  (`MenuController.openDen`: upgrade, glow, slots → pick list). The seamount's foot
  was widened (Cave terrace +36, down to −26) so upgraded dens stay inside the rock.
- **Roll reveal cards are photos (owner, 2026-10-07: "better designs for the random
  rolls"; 2026-10-08: "photos for the rolls need to be dialed way up and look much
  more professional"):** every reel card is a lit 3D shot (`src/client/CardPhoto.luau`
  in a ViewportFrame): a shade is your own current fish wearing it (the real skin),
  a part or variant a fish wearing that (`FishBuilder.build(..., partBody)`), coral
  a still life of sprigs (a chest and coins for the big amounts), and the treasure
  outcomes shells, a bundle of prey, a DNA helix, Kelp Wraps or a Lucky Charm
  (imported props used where they exist). Cards are 168×228: a backdrop fading into
  the tier's color, a spotlight, a floor shadow, a nameplate with a tier gem, a
  hairline, a foil sweep from Epic up and a holographic edge from Mythic up; losers
  dim. Subjects are built once per reel and cloned; a card gets its shot only when it
  nears the window (`attachPhoto`). **Skins are ready before the first roll**
  (`CardPhoto.warm`, on spawn): it preloads every skin texture by id, then draws
  every shade card's fish once in a tiny 98.5%-transparent corner viewport so the
  textures are decoded too. A texture counts as `ready` 0.7 s after it has both
  downloaded and been in front of a camera (retest 2026-10-09: a folder preload
  fetched nothing, so every card sat empty for its 1.2 s wait; with the ids
  preloaded, a downloaded texture still drew white for 0.3–0.5 s). A card whose skin
  isn't ready stays 98.5% transparent (so it's drawn) for at most 1.5 s, then fades
  in. Parts and variants are shot nearly side-on, a card's fish is posed with one
  `PivotTo`, and the camera frames `solvedBounds`: the box of every visible part
  where its Motor6D puts it (outside the Workspace the joints aren't solved until the
  viewport draws, so a part body framed by `GetBoundingBox` was a close-up of its
  root: the Sawblade, Sail Fin and Narwhal Horn cards).
  A boss reward's reveal (`from`) rolls a reel of Rare+ shades and says "won from the
  Megalodon", not "dug up from treasure"; a fish that already has every Rare+
  shade gets half the boss's coral instead, shown as a Coral Jackpot. The result shows a shade's swatches and Rare+
  wins burst motes.
- **Shades are real skins, each its own look (owner, 2026-10-08, asked twice: "All of
  the shades in general need much much more variance and depth than just a slight
  reshape to the existing colors"):** 33 shades (v3), no two sharing a pattern:
  Seafoam foam rings (id `Mint`), Sunset, Ink wash, Sandbar ripples, Ember flames,
  Lilac, Moss lichen, Ocean, Tiger, Bumblebee fuzz, Neon Tetra, Leopard, Rust, Toxic;
  Rare Lunar moon face, Glowspot, Tidepool, Mandarin maze, Lanternfish; Epic Diamond,
  Magma, Glacier strata, X-Ray skeleton; Legendary Divine, Aurora, Thunder; Mythic
  Exotic parrotfish mosaic, Prismatic, Nebula gas clouds, Void spiral; plus the
  trophy and treasure shades. Every skin ships a finish (matte/satin/gloss/mirror
  roughness), metal where the shade is metal, and a glow map for 14 shades (the
  Angler's lure glows in all); in game `Cosmetics` drives the glow
  (`EmissiveStrength`, `Config/Shades` `emissive`), pulses it (`pulse`: breathe,
  heartbeat, flicker, wave, twinkle, strobe, scan; with the shade's light) and sheds
  an `aura` (embers, frost, sparks, stars, motes, bubbles, ink, glints). A new shade
  needs a recipe with its own pattern, an entry and, if it glows, a pulse. Each is a
  texture per fish made offline from the fish's own texture
  (`tools/shades`: `bake_maps.py` bakes every texel's 3D place on the body,
  `find_eyes.py` + hand-checked `eyes.json`, `make_shades.py` recipes, 
  `render_shades.py` + `contact_sheet.py` previews, `pack_shades.py` one GLB per
  fish, `screen_shades.py` the moderation gate ported from Hatch & Snatch).
  `Cosmetics` wears `ReplicatedStorage.ShadeSkins.<Fish>.<Shade>` on a mesh fish
  (its own texture held aside) and falls back to the old tint until imported
  (`tools/studio/organize_shades.luau` files them). The skins ship as the
  `shade_skins` bundle (gitignored like the models). Rules learned: a soft blend of
  orange or gold into white makes peach or beige (flagged as skin tone), so use hard
  edges and golds without blue; a near-white shade on a fish with dark parts (the
  Angler) trips the classifier, so keep pale shades mid-toned; thin near-white
  lines on black (lightning, a skeleton, a mostly black glow map) trip it too, so
  tint them blue or violet with a wide soft glow. Never upload a skin
  that a full `screen_shades.py` run didn't clear.
- **Visibility by depth (owner, 2026-10-08: "swimming to the surface allows you to see
  all the way down ... you shouldn't be able to see all depths at once ... similar to
  the underwater feel of Subnautica"; "the open blue is just a large black
  wasteland"):** `OceanController`'s grades thicken and darken the water with depth
  (Atmosphere density 0.68 at the surface → 0.76 on the shelf → 0.88 on the deep floor
  and in the Trench, exposure down to −0.75; the Trench's black is the dark, above, plus classic fog with a `sight` per
  grade in case the Atmosphere ever goes), and the deep floor grade is a deep blue
  (the Mud material is blue-grey), never black; only the Trench's `dark` goes
  near-black. The sky, surface and upper atmosphere are the other (PC) chat's
  (owner: "I have the other chat working on the sky/upper atmosphere"); don't touch
  `setupLighting`'s Sky or the Surface sheet from this branch.
- **Exits (owner, 2026-10-08: "a flashing blue box that says EXIT in black on every
  exit ... needs to be more subtle and built in"):** each tunnel mouth has a carved
  slate lintel with EXIT on it and a teal lantern either side, and four lanterns ring
  the oculus (`WorldService` `exitDressing`, tag `ExitLight`). They're placed by
  raycast on the real rock face (`wallAt`) after `awaitTerrain`: at a fixed radius
  the lintel sank into the ragged cave wall and the lanterns sat in the next dens'
  doorways (playtest 2026-10-08). The tutorial's
  find-the-exit step breathes those lanterns brighter (`TutorialController`
  `pulseExits`) instead of drawing chips, and its remaining marker (BANK HERE) is thin
  text with a short line, breathing slowly, no box.
- **Underwater look (owner, 2026-10-08: "still has that sky look, it needs to look like
  it's underwater"):** nothing above the water may read as a sky. The Surface sheet is
  opaque pale water (seen from below), four deep-blue Horizon walls box the map far
  past the barrier, an `OceanSky` with no sun, moon or stars replaces the default
  skybox, and the atmosphere is thicker and bluer (server `setupLighting` and the
  client's `OceanController` grades, which drive it every frame). If the sky ever
  shows again, it's a gap in that box, not a lighting setting.
- **Underwater presence (owner, 2026-10-08: "there's no feeling that you're
  underwater. Something needs to be added"):** sound and motion.
  - **Audio:** one synthesized pack, `assets/audio/apex_sfx.ogg` from
    `tools/audio/make_sfx.py` (numpy, scipy, soundfile; nothing sampled or licensed),
    uploaded once; its id goes in `Config/Sounds.luau` `id` (the script rewrites the
    regions). `src/client/Sfx.luau` plays each stretch (`PlaybackRegion`) and loops the
    beds (`Sfx.loop`); while the id is 0 the game is quiet apart from pinged fallbacks
    for a few cues. `AmbienceController` crossfades three beds by camera depth
    (shallow wash, deep drone, cavern drips; a boss near brings the drone up). Cues are
    played where they happen: Dash, Snap/Bite/Chomp/Hurt/Eaten, Bank and LevelUp,
    Shell/GoldenShell, Forage, Dig/ChestOpen, the roll reel's Reel, Tick and a
    `Roll<Tier>` stinger, Warning (a predator's tell on you), TooBig, Banner, Heal,
    Boss Warning/Rise/Phase/Defeat, Breach, Grab, Ink. Every sound is low-passed
    ("heard through water"). Add a sound: a maker in `make_sfx.py`, rerun, re-upload,
    paste the new id.
  - **Motion:** `Bubbles.luau` is the one bubble look (bursts and mouth streams);
    `BubbleController` streams bubbles off every fish's mouth by speed; vents and ~37
    seeps on the shelf and deep floor send bubble columns up (`WorldService`
    `bubbleColumn`); `KelpController` sways the kelp (in `World.Biomes.Kelp`) within
    180 studs of the camera (one BulkMoveTo a frame). It collects plants as they
    come into reach, never once at the start: with streaming a plant's Model arrives
    before its parts (retest 2026-10-08: the first start swayed nothing). Each part's
    rest pose is kept (`KelpRest`), so re-collecting mid-sway can't drift.
- **Ghost is spectral (owner, 2026-10-08: "the whole fish needs a similar to ghost from
  sea of thieves glow ... a very rare skin"):** a shade with `spectral = true` turns
  the whole fish ghostly, not just its edges: ForceField see-through body, a breathing
  Highlight fill and rim, rising wisps, glowing eyes, a brighter light; on a mesh fish
  the texture is held aside (`HeldAppearance`) and put back when the shade changes
  (`Cosmetics` `haunt`, `animate`).
- **Distances read in feet (owner, 2026-10-08: "instead of studs it should say ft"):**
  `Format.distance` (1 stud ≈ 0.92 ft; depth uses it too). Never show "studs" or
  meters to players.
- **Quality bar (owner: "very very fluid ... EXTREMELY professional")**: see GDD §12.
  - Abzû-level swimming: momentum, roll into turns, size-scaled handling.
  - A spring camera.
  - A procedural spine swim.
  - Suction eats with hit-stop.
  - Depth-graded lighting.
  - One custom UI design system with springy transitions and no emoji icons.
  - 60 fps on mid-range phones.
  - Nothing ever pops.
- **Roadmap:**
  1. A graybox feel prototype, judged on feel alone.
  2. Look-target concepts and UI mockups.
  3. A ship-quality vertical slice: 1 biome, 1 line.
  4. Content.

## Tech

- Rojo 7 (`default.project.json`) with Luau `--!strict`.
- Tool versions are pinned in `rokit.toml`. Lint with selene and format with StyLua
  2.0.2 (newer versions reformat).
- Config is data-driven in `src/shared/Config/*`. New content means editing tables, not
  code.
- **The server is authoritative** for XP, Haul, banking, kills, evolutions and purchases.
  - Each player's fish runs on their own client, for zero input lag.
  - The server checks every eat (distance, size ratio, the prey's position at that
    time) and checks swim speed per size.
- **The ocean is faked:** no Terrain water. Gravity is cancelled per fish, and the
  underwater look is lighting, fog, ColorCorrection, caustics and particles.
- **NPC fish never replicate as instances.** Schools follow shared, time-based paths
  (`src/shared/Schools.luau`) that every client animates locally. The server keeps only
  which fish are eaten and validates eats against the path. The same idea kept the
  Hatch & Snatch conveyor cheap.
- **Player data:** ProfileStore, vendored at `src/server/Packages` (Apache-2.0). Studio
  sessions use `PlayerData_Studio_v1`, so Studio testing never touches live saves. Team
  Test servers probably report `IsStudio() == false` and would use the live store.
- **Purchases:** `MonetizationService` owns ProcessReceipt. A product's effect is
  registered with `MonetizationService.onProduct(key, fn)` by the service that owns it
  (Double Haul and Second Chance: HuntService; shell packs: EconomyService; Server
  Frenzy: MonetizationService), and `fn` may only change that player's data (plus
  things fine to repeat). `DataService.processPurchase` grants once per PurchaseId and
  confirms after a save. Check passes with `MonetizationService.hasPass(player, key)`.
- **Remotes:** `src/server/Net.luau`. Client requests are rate-limited, and every
  argument is untrusted.
- **Loops:** wrap server loops in `Guard.loop` or `Guard.run`, so one bad record can't
  kill a loop for the whole server.
- **Service start order** in `init.server.luau` matters: each service connects to
  `DataService.loaded` inside its `start()`, and DataService starts last.

## World and assets (2026-10-07)

- **The hub cavern is Roblox Terrain** (owner: "needs to actually resemble a
  cave/cavern, not straight flat edges"). `src/server/Cave.luau` lists fill ops (a
  terraced seamount with faceted blocks, the carved cavern with a dome, bays, drips
  and a ragged oculus, 12 den rooms with round doorways, 4 tunnels, floors put back)
  and `WorldService.buildHub` applies them with `Terrain:Fill*`; material colors are
  `Cave.COLORS`. Only pools, lamps, signs, sconces, plaza, beacon and light shafts
  are still parts. Layout numbers are unchanged, so Layout/HuntService/FishService
  still agree. Preview from the cloud: `LUAU=<luau> bash tools/preview/run_cave.sh
  <dir>` (voxelizes the ops, marching cubes, Cycles on the CPU; no EGL here).
- **Vendors (owner, 2026-10-08: "still just spheres with eyes"):** the five
  shopkeepers are models now, `vendors_glb` (`WorldProps.Keeper<VendorId>`): the
  hermit crab Outfitter, octopus Den Mason, sea turtle Tidecharm Trader, pufferfish
  Shade Dyer and "Scar", the scarred grouper Trophy Hunter, from the approved
  `assets/concepts/Vendors.jpg` (sheets `tripo_jobs_vendor_sheets.json`, models
  `tripo_jobs_vendor_models.json`, 200 credits). `WorldService.keeper` dresses each
  over its placeholder ball, facing the beacon. Balance ~1,360.
- **Models come from Tripo, batch 1 done** (580 credits; balance ~1,660): 6 species
  (clean single-fish sheets from `assets/concepts/StyleSheet.jpg`, then
  image_to_model), 7 prey, 15 props/food. Reviews: contact sheets of
  `assets/tripo/*/_preview.webp`. The owner's direction: Schedule I look with a
  touch more realism; the sheets and models matched it first time except the eel
  (needed a STRAIGHT body) and two props (color/shape named louder).
- **Pipeline** (docs/ASSETS.md): `tools/blender/rig_fish.py` (spine chain
  Root/Head/Spine1..N/Tail; head at -Y for FBX, +Y for `--static` GLB),
  `fish_check.py`, zips hosted on Higgsfield CloudFront, `tools/assets_manifest.json`
  bundles, `tools/fetch_assets.py`, `tools/studio/organize_imports.luau`. Folders the
  code reads: `ReplicatedStorage.FishModels.<SpeciesId>` (rigged),
  `PreyModels.<PreyId>` (static MeshPart), `WorldProps.<Name>`. Everything falls back
  to graybox parts when a model is missing (`FishBuilder.meshTemplate`, `Props.dress`,
  `PropParts.make`, `SchoolController.preyTemplate`).
- **Branches:** world and asset work lands on `claude/world` while the PC chat
  owns `claude/core-systems` (controls and UI fixes); merge `claude/world` into
  `claude/core-systems` once the PC chat's fixes are pushed.

## Code map (graybox feel prototype, 2026-10-06)

- **Server** (`src/server/Services`):
  - `WorldService`: builds the map (the Terrain seafloor from `Shelf.luau`, the surface ceiling, walls, the hub cavern from `Cave.luau` with 12 dens, Haul Pools, 4 tunnels and the oculus, and every biome's dressing) and the base lighting. Gravity is 0.
  - `FishService`: custom fish characters (a ball collider `HumanoidRootPart`, a Humanoid with `EvaluateStateMachine = false`, and a `FishBuilder` body), den assignment, respawns.
  - `HuntService`: validates prey eats, player eats and bites; the Haul; banking at your own den's pool; the hub safe zone, spawn protection and healing. It also exposes `mouth` and `feed` for other food sources.
  - `ForageService`: starfish and shrimp spots (placed by raycast) and server-checked eats.
  - `MonetizationService` (passes, receipts, Server Frenzy, ads, PolicyService),
    `GardenService` (the den's Coral Garden), `RewardsService` (daily streak, group
    perk). Client: `Store` (Roblox prompts), `Ads`, `OfferController` (SHOP/DAILY,
    growth chip, Double Haul and Second Chance cards), `GardenController`.
- **Shared** (`src/shared`):
  - `Config/` (Tuning, Prey, World).
  - `Size`: mass ↔ length, levels and stages, speed and turn rate.
  - `Layout`: hub geometry.
  - `Schools`: the deterministic prey paths.
  - `FishBuilder`: the graybox fish, unit-scaled with named Motor6Ds.
  - `Format`.
- **Client** (`src/client`):
  - `Input`: every device. `moveVector()` is the keyboard (camera-relative) and
    `drive()` the sticks (throttle, steer); it never waits on Roblox's `PlayerModule`,
    which isn't inserted for this game (playtest 2026-10-06). Mouse wheel zooms.
    The sticks are zeroed on `InputEnded` and also re-read from the pad's own
    `GetGamepadState` every frame (render step `ApexSticks`): Studio's Controller
    Emulator sends no near-zero `InputChanged` on release, which left the fish
    swimming on its own (playtest 2026-10-07). Roblox's own touch controls are
    off (`GuiService.TouchControlsEnabled = false`); the HUD draws the stick.
    `SwimController` swims the throttle along the aim and backs up on a pulled
    stick, and cruises along the aim on a sideways-only push (`swim.turnCruise`);
    `CameraController` turns the aim by the steer at the fish's turn rate
    (`camera.steerScale`, at most `camera.steerMax` 2.0 rad/s).
  - `Spring`.
  - `Ui`: the design system (BuilderSans, palette, panels, bars). On phones,
    `Ui.belowTopBar` moves the top-left column (level card, wallet, HUD buttons,
    tutorial panel) down below Roblox's top bar.
  - `Controllers/`:
    - `SwimController`: momentum swim, banking into turns, the Dash (`dashCharge`), lunge.
    - `ForageController`: draws starfish and hopping shrimp, eats them with suction.
    - `CameraController`: the spring camera, mouse lock, wheel zoom. It pulls the
      look-at point out of rock, then limits the distance with a ray plus a swept
      near-plane-sized box. Never rely on a sweep alone: Spherecast/Blockcast ignore
      whatever they start touching (that let it through a den roof), and so do
      rays: a Space tap can poke the fish into a ceiling, so a look-at point
      hidden inside rock from last frame's camera spot is pushed out along the
      face's normal first. Stopped by a
      ceiling or the seabed, it slides along the rock and looks back at the fish
      instead of collapsing into it; very close up, your own fish fades
      (`LocalTransparencyModifier`, skipping parts Cosmetics hid at 1). The look-at
      point trails the fish by at most `maxLag` × its length, shake rotates, and
      thin species sit closer (`Config/Species` `camera`).
    - `ForageController`: filler food is eaten from a generous reach
      (`Forage.REACH_SCALE`/`REACH_BONUS`) with a suction pull (`PULL`), and the
      server allows for both.
    - `FishAnimator`: the spine wave, jaw and growth easing.
    - `SchoolController`: draws the prey and eats them with suction.
    - `HuntController`: player eats, bites and hit effects.
    - `NametagController`: threat colors.
    - `OceanController`: depth grading and marine snow.
    - `BiomeController`: biome banner, level chip (under the depth gauge; above it
      on phones, clear of BITE), under-level warning.
    - `HudController`. On phones it draws the one swim stick: the touch zone
      (lower-left 40% × 60%) sits in the `Hud` ScreenGui under the HUD buttons, and
      the ring on its own `SwimStickRing` layer above the HUD panels. Touch
      positions and `AbsolutePosition` both count from below the top bar, even in
      an `IgnoreGuiInset` ScreenGui, so no inset is added (adding it drew the ring
      58 px under the thumb, playtest 2026-10-07).
- **Rolls and shops (2026-10-06):**
  - Server: `EconomyService` (coral and shells), `ShellService` (spots, per-player
    pickups), `RollService`, `ShopService` (stalls via `WorldService.vendorPosition`),
    `WardrobeService` (equip, character attributes).
  - Shared: `Perks` (what upgrades and charms do, for both sides), `RollOdds`,
    `Cosmetics` (shades, parts and variants on a body).
  - Client:
    - `ShellController`.
    - `RollController`: wallet, Roll / Odds / Wardrobe buttons, the reveal.
    - `MenuController`: shops, Wardrobe, odds; B closes. Its own stall hint ("E ·
      Shop", Y on a controller) shows within `Shop.hintReach` of a counter
      (`Layout.counterPosition`); there are no ProximityPrompts. Phones get a
      screen "SHOP · vendor" button above BITE instead of the world chip.
    - HUD buttons (ROLL, ODDS, WARDROBE, FISH) aren't selectable; the D-pad opens
      them (up Fish, left Wardrobe, right Odds, down Roll).
    - `FishPreview`: a ViewportFrame fish.
- **Species and the tutorial (2026-10-06):**
  - `Config/Species` (six species: stats, colors, body plan, home biome, unlock rule),
    `Config/Abilities` (names), `Config/Tutorial` (steps and the reward).
  - `Shared/FishPlans`: a graybox body per species, normalized to 1 stud, with joints
    at real pivots and the same core part names.
  - Server:
    - `Progress`: per-species banked mass (`data.species[id].mass`, current species
      `data.current`). `data.mass` is retired and migrated into the Nibbler.
    - `Events`: signals that services fire and the tutorial listens to.
    - `SpeciesService`: switch species in the safe zone with no Haul aboard (respawns
      you in your den); unlock with home-biome DNA plus coral.
    - `TutorialService`: five steps. Finishing gives the 'Cuda, 50 shells and 500
      coral, and opens species select.
  - DNA drops: big prey always, small prey 25%, forage 4%, credited to the biome you
    ate in.
  - Client:
    - `MenuController.openSpecies` (the FISH button).
    - `TutorialController`: the step panel, plus EXIT and BANK HERE markers.
    - The animator waves each plan's own spine. Swimming uses the species' speed and
      turn.
    - Exotic variants apply only on their own species.
- **Tripo:** `tools/tripo.py` (key in `TRIPO_API_KEY`); jobs files are
  `tools/tripo_jobs_*.json`, outputs go to `assets/tripo/` (gitignored), and approved
  concepts are copied to `assets/concepts/`. The owner topped up to 2,450 on
  2026-10-06, and 2,350 were left after the biome and boss concepts. The budget plan is in GDD
  §8.
- **Not built yet:**
  - codes, Pearl crates, the Roblox group perk (id 0), pass and product icons
  - chum clouds, Pods and the Apex bounty
  - boats and hooks, depth pressure
  - models for the growth stages and the other biomes;
    rolled parts and variants on mesh fish; caustics (needs a texture upload)
  - den decor beyond v1: free placement, more pieces, den items from bosses (jaw arch, Kraken-eye lantern)
  - the UI dial-up pass (owner, 2026-10-07: "menus and UI could be dialed up")
  - server-side speed checks
  - The progression numbers are placeholders: one full dive banks about 16 levels.

## Playtests

- Reports go in `docs/playtests/` (`2026-10-06-pc.md`, `2026-10-06-pc-retest.md`,
  `2026-10-07-pc.md`, `2026-10-07-pc-retest.md`, `2026-10-07-pc-fixes.md`,
  `2026-10-08-pc.md`, which also covers the two world rounds before it,
  `2026-10-08-pc-retest.md`, `2026-10-09-pc.md`; briefs for the PC session sit
  beside them as `*-brief.md`).
- A game script can't read `SurfaceAppearance.ColorMap` (it needs Plugin
  capability, and the read throws); read `ColorMapContent.Uri` in a pcall
  (2026-10-09). `ContentProvider:PreloadAsync` on a folder of SurfaceAppearances
  fetches nothing (fetch status stays None); preload the texture ids themselves.
- Boss `Struggle` requests are rate-limited to one per 0.05 s (it was 0.12 s, which
  dropped real fast mashing, retest 2026-10-08).
- Engine limits the world hit (playtest 2026-10-08):
  - `Workspace.FallenPartsDestroyHeight` is −2000, set in `default.project.json`
    and the saved place. The default −500 sits above the Vents (−540) and the
    Trench (−920), and a fish taken there lost its replication.
  - Terrain filled in a frame doesn't answer raycasts until a later one
    (`WorldService` `awaitTerrain`).
  - An UnreliableRemoteEvent drops a packet over its size limit whole, so the
    predator stream goes out 4 creatures a packet.
- Uploading assets from Studio:
  - The sound pack went up through Studio's own importer (Asset Manager →
    Import → Import Queue → Start Import, which shows a rights-and-fee dialog).
  - The Import Queue row's right-click → Copy AssetId gives the id.
  - Shade-skin GLBs come in through File → Import; right after upload a texture can
    fail with `HttpError: NetFail` and then load fine.
- On the owner's PC, format with `stylua --line-endings Windows src --glob
  "!**/Packages/**"` (the clone checks out CRLF, so a plain check flags every file).
- Studio testing lessons: the command bar `require`s its own copy of a
  ModuleScript, so calling a service from it changes nothing in the running game;
  in the Device Simulator, typing into the command bar flips `KeyboardEnabled` on
  until the next touch, so `Input.isTouch()` reads false meanwhile. Studio's
  2026-10-08 build has a multi-line command bar: Enter adds a line and the Run
  button executes (it moves up when the script is long). Its Rojo panel
  defaults to port 34872, so set 34873 before connecting.
- Toasts have their own ScreenGui above the menus, so refusals from menu buttons
  show. ROLL also has R on keyboards.
- On the owner's PC, Rojo for this game runs on **port 34873** until the stale Hatch
  & Snatch `rojo serve` on 34872 is closed. Never connect the plugin to the
  HatchAndSnatch project from this place.
- Keep Studio's Controller Emulator panel closed for keyboard tests.
- Custom fish character lessons: Roblox's `PlayerModule` is not inserted (so the
  move vector comes from `Input`), and ProximityPrompts never showed or triggered
  for it (so interactions use our own distance checks and hints).

## Lessons carried over from Hatch & Snatch

- A server `PivotTo` on a character can be undone by the client's own physics. Move
  players with `Net.teleport`, which repeats the move on the client.
- Set an Attachment's `WorldPosition` only after parenting it. Set while unparented,
  it's stored as a local offset.
- Place an anchor part where it goes before welding a model to it outside the Workspace
  (a WeldConstraint takes its offset when the parts reach the Workspace).
- The place template leaves a Bloom, SunRays, DepthOfField and Atmosphere in Lighting
  that stack on ours. The lighting code deletes any effect that isn't its own and looks
  up its own effects by name, never `FindFirstChildOfClass`.
- UI text: ✦ and ▾/▴ render as empty boxes in Roblox fonts. For a professional look,
  use image icons rather than emoji anyway.
- Music must stay subtle: give each track its own volume level. Never ship an audio id
  the owner's account can't use.
- **Skin uploads:** automated image moderation once suspended the owner's account over a
  pale, pinkish unwrapped texture atlas. Screen textures before upload, import in small
  batches, and never upload from another account while one is suspended.
- **Paid random items** (crates, eggs) need exact odds summing to 100% shown before
  buying, and must be hidden for `ArePaidRandomItemsRestricted` players.
- luau-lsp quirk: maps keyed by a singleton union type raise false errors when indexed
  with values from other modules, so use `string` keys.

## Verifying from a cloud session (no Studio)

`TOOLS=<dir with the binaries> bash tools/verify.sh` runs all three checks:

```
rojo sourcemap default.project.json -o /tmp/sourcemap.json
luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=/tmp/sourcemap.json --ignore="**/Packages/**" src
stylua --check src --glob '!**/Packages/**'
```

- Binaries: get Rojo 7.7.0, StyLua 2.0.2, luau-lsp and the Luau CLI from their GitHub
  releases. `globalTypes.d.luau` comes from the luau-lsp repo's `scripts/` folder.
- selene can't fetch the Roblox API dump from the sandbox.
- Pure logic modules (`src/shared/*` with no Roblox globals) run in the plain `luau` CLI
  through the test shims in `tools/tests/`.
