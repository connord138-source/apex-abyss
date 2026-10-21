# APEX TIDE — Roblox game (read this first)

Formerly **Apex Abyss** (renamed 2026-10-20). The repo (`apex-abyss`), the local folder and
`ApexAbyss.rbxl` keep the old name; no DataStore name holds the game's name.

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
- **Show the owner images by sending the files themselves** (attached so they open in the
  app), never as a repo path or link: a link opens GitHub's code view, which shows no
  picture (owner, 2026-10-20). On the PC, the same files are in the local clone.

## Decisions already made (do not re-litigate)

Every decision below was made with the owner on 2026-10-06. The details are in `docs/GDD.md`.

- **Title: Apex Tide** (owner, 2026-10-20: "Go with Apex Tide"; it was Apex Abyss from
  2026-10-06 until the game stopped being about the abyss). The live title is "Apex Tide
  🦈 Eat & Grow", and the brand is APEX TIDE. Checked 2026-10-19: no Roblox game or
  group by the name (omni-search and group search), and no web, app or trademark hit.
  "Abyss" alone is crowded on Roblox (18+ games, among them Deep Spirit Games' ocean game
  Abyss, ~87M plays), and the direct rivals are Be Fish, Be a Shark, SharkBite, Fish Eat
  Fish and DEVOUR. The name ties to the Tide Clock and the Tide Pass. Runners-up:
  Tidebite, Food Chain (Frenzy Depths before). **The logo** (`marketing/logo.png`; B,
  a curling wave, is `logo_alt.png`) keeps the old logo's APEX line by an image edit
  (`tools/tripo_jobs_logo_tide.json`, LogoTideA/B; `compose.py` keys it and drops the
  model's faint noise band); every thumbnail carries it. The start screen shows it once
  `Config/Textures` `logo` holds its id (StartController, sized for the letterbox), the
  lettering APEX TIDE until then. **Community or individual** (Connor asked 2026-10-20):
  Claude recommended a studio community for both games, with this experience moved
  into it before launch (Creator Hub's free user-to-community transfer keeps the game,
  place ids and URL); Connor to decide.
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
  - Prey and filler food under ~70% of your size: swallowed whole, sucked into the
    mouth.
  - **Players are never swallowed whole** (owner, 2026-10-20: "bigger fish should never
    auto eat another player it needs to be a fight. obviously bigger fish will be
    stronger though ... it goes by level not haul size"): every player fight is bitten
    out. A bite's strength is the biters' banked mass (their level; the Haul aboard
    doesn't count) against the target's, ^⅔, ×0.04–2 (`Config/Pvp` `fight`): ~×1.07 a
    level, so a fish 10+ levels up bites at ×2 (3 bites eat anyone). Nametags read
    LV n · STRONGER / WEAKER / EVEN FIGHT, `edge` 6 levels apart (the `FishLevel`
    character attribute, `HuntController.standing`); the `EatPlayer` request is gone.
  - What eating a player pays scales with the level ratio, so farming new players
    pays almost nothing.
- **PvP:** always on in the biomes, with protections.
  - The hub plaza and the dens are safe, and there's spawn protection.
  - Size-gated terrain gives small fish places to hide.
  - Chum clouds, an Apex bounty on the biggest player, and baited hooks dropped by boats
    (all built 2026-10-14, below).
- **Teams:**
  - **Schooling:** nearby small players' combined mass can bite a bigger predator. This
    is the headline twist.
  - **Pods of up to 3:** no friendly fire, a slipstream speed boost and shared kill XP.
- **The PvP round (owner, 2026-10-14: "I want to knock out as much as we can this
  round"; every approved twist built, GDD §5/§6):** tuning in `Config/Pvp.luau`,
  `Config/Chum.luau`, `Config/Hooks.luau`.
  - **Chum** (`ChumService`, `Shared/Chum`, `ChumController`): an eaten fish (by a
    player or a creature) bursts 40% of its lost Haul into 4–14 chunks that sink
    slowly where it died (45 s); any fish swallows a chunk by swimming into it, its kg
    straight onto the Haul (`HuntService.gain`, raw: that Haul was grown with ×2 Mass
    and Frenzy already, so kills don't compound; slick and whale chunks are new food
    and get them); clients send at most 12 a batch; chunks ride shared clock paths, so the
    server checks each eat and clients draw them (`EatChum`). AI predators within 320
    studs swim to a cloud (`ChumService.nearest`) inside their own band and sector
    (`PredatorService` `inRange`). HuntService fires `Events.burst`
    (no require cycle).
  - **Blood Tide chum** (`Config/Tides` `chum`): a slick of 7 chunks appears near a
    random player out in the biomes every 20 s, and clouds linger ×1.5.
  - **Whale Fall** (the tide event): about every 26 min (6 in Studio, first 13 min /
    90 s after start; one at a time) a dead whale sinks into a random biome, announced a minute
    ahead with a W on the map; it settles and feeds everyone for 5 min, 18 chunks
    growing back 14 s after eaten, sized ×3 the biome's chunk (`biomeChunk` 0.05 ×
    the banked mass at the biome's middle level). **The carcass is a model**
    (owner, 2026-10-15: the part-built one "looks very rough"): `WorldProps.WhaleFall`
    (`whalefall_glb`), a chunky low-poly humpback resting on the floor, eye shut,
    barnacles, two bites showing bone-white ribs over a dark hollow, no blood (concept
    `tools/tripo_jobs_whalefall_sheet.json` WhaleFallA, then image_to_model; normal
    map stripped, screened 0.000). It lies lengthwise along its own Z, so
    `ChumController.carcass` fits it by length (60 studs) and turns it onto X, its
    middle on the cloud's centre; part-built until imported. **Clear of the
    dressing (PC 2026-10-15: ~3 of 18 chunks inside the body, reef sponges and
    staghorns through the flukes):** the server picks the carcass's turn with its
    spot (`cloud.yaw`, `Chum.yaw`); its chunks ring it in an oval 4–12 studs past
    its ends and 14–22 beside it, turned with it (`Chum.offsets`); a spot is scored
    over the whole footprint (`ChumService` `blocked`: Ground columns every 6 studs
    plus every piece of dressing in its box) and the first open one or the least
    blocked of 40 wins; each client hides small corals and boulders whose middle
    lies under a settled carcass (`ChumController` `crush`, LocalTransparencyModifier,
    put back when it goes). On the deep floors its light is range 60, brightness 1,
    and since no light reaches through the haze there (PC 2026-10-15 round 2: a
    faint shape past ~50 studs) it wears a faint cool outline (`WhaleRim`, a
    Highlight, Occluded) from 40 to 200 studs. The sand under the footprint must be
    level within `LEVEL` 3 studs (PC fix 4e0a67d: a dune buried the flukes, a hump
    left the tail in the water), and a deep biome's whale lies on its deep floor,
    never on the shelf's lip above the drop-off. Admin "Whale Fall on reef coral"
    (`whaleCoral`) puts one on level reef sand among small corals to show the hiding.
  - **Pods** (`PodService`, POD on the HUD row, the Shop's Pod row for controllers,
    `MenuController.openPod`): invite, JOIN/DECLINE within 30 s, LEAVE. The `Pod`
    player attribute is the source of truth for the server (`HuntService` `podmates`
    in `targetOf`: no eat, no bite) and clients (nametag PODMATE, teal map dot, no
    auto-eat). Slipstream ×1.15 within 18 studs behind a podmate swimming your way
    (`SwimController` `slipstreamOf`); a podmate's player kill gives podmates within
    220 studs half its gain (`Events.atePlayer`).
  - **Schooling:** a bite counts every other biter of the same fish in the last 2.5 s
    within 40 studs: their combined banked mass (levels, since 2026-10-20) against the
    target's sets the damage ((mass ratio)^⅔, clamped 0.04–2), +15% per extra biter; the biter sees SCHOOL
    BITE ×N. `HintController` shows SCHOOL (not DANGER) when another small fish is near.
  - **Apex bounty** (`ApexService`): the heaviest live fish (LV 10+, 2+ players) is
    the Apex: Workspace attributes `ApexUserId`/`ApexBounty`, a gold ★ on every map,
    a gold outline and a ★ APEX line on its nametag (seen to 900 studs), its own chip.
    Bounty 500 coral + 150/min while it's out of the hub (cap 6,000); the player who
    eats it gets it (+ the Apex Hunter title the first time, `stats.apexKills`), but
    only after a 2-minute reign out of the hub and never twice between the same two
    players within 20 min (`minReign`, `pairCooldown`; review 2026-10-14: two friends
    trading kills farmed ~80k coral an hour). A creature kill or leaving ends the reign
    unpaid. The crown moves only to a fish 10% heavier. Its position is published
    (`ApexAt`) so the ★ shows beyond the streaming radius. Admin can crown (kept even
    solo, eligible at once) and add bounty.
  - **Depth pressure** (`PressureService`, `Shared/Pressure`): bands 10 levels under
    the biomes they guard: below y −60 needs LV 25, −330 LV 40, −480 LV 55, −640 LV
    70. Too deep, the `Pressure` attribute fills over 6 s (meter, blue squeeze at the
    screen's edges, creaks, "rise above N ft"), then 3% max health a second. Never in
    the hub or the dens, nor within 500 studs of a world boss that's up (the Giant
    Squid lurks below the deepest band; a boss fight is for everyone). Treasure dig
    sites are picked above the holder's crush depth (`TreasureService.give`). The
    Outfitter's **Pressure Hide** (5 levels, 400 → 15,000 coral) counts 4 levels each
    (`Perks.depth`).
  - **Hooks** (`HookService`, `HookController`): 5 boats drift 280–1,300 studs out
    (dark hulls under the surface) and every 20–45 s drop a line 60–300 studs down with
    a silver bait fish (BAIT tag). Swallowing it gives a big meal (`bait` 0.4 × the
    biome's middle-level mass) and hooks you (`HookedBy` attribute): reeled up at 7
    studs/s; 10 mashes of BITE/DASH (`StruggleHook`, 0.15 s apart, after 3 s on the
    line) break free with the bait, a
    podmate's BITE within 26 studs cuts the line (`BiteLine`), landed after 9 s the
    fisherman keeps 30% of your Haul (`HuntService.takeHaul`). `SwimController.holdBy`
    takes holds from more than one source ("creature" for boss grabs, "hook"), and
    `SwimController.struggle` sends the mash to whichever holds you.
  - **Speed checks** (`SpeedService`, log-only): a fish moving more than its fastest
    possible (Fins, species, a Dash throughout, slipstream) ×1.5 + 25 studs in a second,
    three times in 30 s, writes `[SpeedCheck] ...` to the Output. `Net.teleport` and
    `Net.shove` stamp a `MovedAt` player attribute and a respawn resets the baseline.
    Enforce only after playtests show no false positives.
  - **Overnight follow-ups (PC report 2026-10-14, every system passed; fixes on
    `claude/world`):** after a whale ends the water stays quiet `rest` 120 s before
    the next is announced (in Studio one was always coming or under way), the
    admin's "Whale Fall now" makes an announced whale sink in 5 s or ends a feeding
    one and brings a fresh one, and a whale settles only on open floor
    (`ChumService` `openFloor`: no dressing over the spot or 27 studs round it, by
    `Shared/Ground`; one in the Ruins came to rest under a lintel), else on top of
    the dressing. A fish still in the tutorial is warned by the pressure meter
    (TOO DEEP FOR NOW, `PressureSafe` attribute) but never crushed. AI predators
    look for chum every second while roaming (`lureAt`; ~15 s to arrive before, as
    it was only checked at a new waypoint). A Captain's map that finds no site in
    40 tries falls back to the shelf's sand inside its edge, above every crush
    depth. Bait is 0.25 of the biome's middle mass (was 0.4: +73 kg for a LV 21 fish
    with ×2 Mass), and never more than `baitLevels` 3 levels' worth for the fish
    that takes it (PC follow-up 2026-10-14: bait hangs near the surface whatever
    the biome, and a LV 21 fish took a 4.6 t Trench bait; a fish at the biome's
    middle level gets ~2 levels, so only fish under the biome are capped; since
    2026-10-19 bait is ½ the taker's full Haul, see "Pace"). The Apex's nametag line is heavier, bigger and gold-edged (dim at
    70 studs). The middle of the screen is one stage (`Ui.holdStage` /
    `Ui.stageWait`): the bank celebration holds it 3 s and the catch and
    achievement banners wait their turn. On phones a window's title and subtitle
    start right of Roblox's top-left buttons while its header is in the top bar's
    band (`Ui.window`).
- **Redeem codes (2026-10-14; GDD §9 "Later: codes"):** `Config/Codes.luau` (APEX,
  DEEPDIVE, MEGALODON, NIBBLER; rewards that always fit, never wraps a full carry would
  swallow; matched without case or spaces; `ends` Unix time), once
  per player (`data.codes`), paid by `RewardsService.grant`, through the `RedeemCode`
  RemoteFunction; the Shop's Free Perks has a Codes row whose REDEEM opens its own
  window (the Shop redraws every second, which would clear a text box). Admin: Codes:
  use them again.
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
      only. **Since 2026-10-17 the 'Cuda is earned** (owner: "should take a bit longer
      to get cuda than just finishing the tutorial ... Nobody would ever play as the
      nibbler"): Nibbler LV 15, 40 Kelp Shallows DNA and 1,500 coral (`Config/Species`
      `unlock.level`); the tutorial pays 50 shells and 500 coral.
    - looks-only rolled parts; power comes from the species trees
    - species-specific exotic variants
    - the per-biome food chain
  - **The Nibbler's only ability is a recharging Dash** (owner). It's built; it replaced
    the old held boost.
  - **Safe zone = the dens plus the vendor plaza.** A banner shows on leaving or
    entering it, with a protection countdown (built).
  - **Filler food:** starfish and shrimp on the seabed (built). **Thick near the hub
    (owner, 2026-10-10: "needs a lot more smaller fish and starter food laying
    around. far too scarce"):** `Config/Forage` `bands` (studs from the hub, count
    each): ~1,680 spots, about one every 20 studs within 330 of the hub; a spot is
    skipped when anything solid is round it (`ForageService` `reachable`). Minnows
    are 42 schools (22 near the hub, 4–45 over the sand) and sardines 24
    (`Config/Prey` `zones`); prey past 160 studs from the camera keep their path but
    not the spine wave (`SchoolController` `WAVE_DISTANCE`).
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
  - **Bodies ease off toward 17 studs** (since 2026-10-20 the drawn length is linear
    in level, see "The 2026-10-20 owner batch"; owner, 2026-10-14: "Each den should be
    large enough that a max size player can fit in it ... full grown shark should
    be a bit larger than an actual shark and max size for fish should all be
    relatively the same but not ridiculously large"): `Size.length` follows the raw
    curve (2 × mass^⅓) to `lengthKnee` 6, then eases toward `lengthCap` 17 (LV 60
    12, LV 80 15.7, LV 100 16.9; a full Haul never passes 17; collider ≤ 6.8, 8.5
    for the Puffer). Size ratios (`Size.canSwallow`, `Size.ratio`: swallowing,
    player bites and XP, aggro, predator damage and interest) and swim speed use
    `Size.raw`, so the balance didn't move. Compare sizes with those, never with
    drawn lengths.
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
    for the fish you're swimming as. **Since 2026-10-20 (owner: "Ive done about 20
    rolls and gotten coral everytime ... Every skin needs to be rollable other than the
    boss skins and achievement skins ... drop rates scale with rarity")** an owned
    skin's share goes to the unowned skins of its tier (`RollOdds` `tierBoosts`), so
    each tier's odds hold until the fish has all of it, and only a finished tier's
    share is coral; the treasure shades roll on every fish at their tier's line odds
    (Drowned Pearl 1 in 700, Sunken Gold 1 in 1,500; `Config/Shades.rollable`: all
    but boss, catch, weekly and Tide Pass skins). Admin "Skins: take every skin off
    the current fish" (`clearShades`) for testing rolls. Before that, `RollOdds.table(luck, owned)` left the fish's
    shades out and gave their share to coral, so every other chance stayed the same
    and the odds panel (this fish's table) still sums to 100%
    (`tools/tests/run_odds.sh` checks it). Boss and treasure shade rolls skip owned
    ones too. The wardrobe names a shade another of your fish has ("unlock it again
    for this one", `state.otherShades`). Old saves: the global `data.shades` was
    copied to every unlocked fish and emptied.
  - **Every fish has its own skin line (owner, 2026-10-10: "skins to be different for
    each playable fish. Common skins should be similar to original just with
    realistic fish reshades and the rarer they get the wilder they get"; 12 per
    fish):** `Config/Shades` `LINES`: 4 Common realistic morphs of the real species
    (the Shade Dyer sells them), 3 Uncommon (a new tier), 2 Rare, Epic, Legendary,
    Mythic, at 1 in 32/100/150/300/700/1,500 (coral stays 82.5% of a fresh fish's
    roll). The 30 v3 shades fill wilder places; 42 skins are new
    (`tools/shades/lines.json` lists every one with its look). A line skin rolls,
    sells and shows only on its own fish (`Shades.fits`, `Shades.rollable`,
    `RollOdds.table(luck, owned, species)`); every fish can also have the boss
    trophies, treasure shades, its catch-track skins and the weekly ones. Old saves:
    a skin now on another fish's line turned into its coral (DataService load).
    **The textures are made (v4, 2026-10-10):** 23 skins a fish (its line plus the
    11 universal), 138 in all, every GLB cleared by `screen_shades.py` with the
    classifier (highest 0.19); contact sheets in `assets/shades/previews/`; the
    `shade_skins` bundle in `tools/assets_manifest.json`. Pale or soft colours that
    scored high were moved (Maroon to garnet, Jade to teal, Shipwreck's red hull to
    dark iron; line-art metal maps to even metal). **v5 (2026-10-11, playtest
    2026-10-10):** the twin Commons read apart (shark bronze / charcoal / steel blue,
    Angler black / umber / olive-ochre / slate, 'Cuda bronze-olive Chevron and
    steel-blue Blackfin), Chrome is dark gunmetal, Golden is a warmer brushed gold
    with less metal (mirror gold reflecting the blue water read lime), the Puffer's
    Common Golden is "Canary", and stair-stepped edges are gone (`smooth(m)`: the
    body frame jumped between its fitted slices). Warm gold or orange in large
    smooth areas can pass as a PNG and fail once JPEG-packed: screen the GLBs too.
    All six v5 GLBs exit 0 (highest 0.154). **v6 (2026-10-11, playtest nits):** the
    Puffer's Neon Tetra stripe is measured from one straight line fitted through the
    body's middles (on the smooth frame it still kinked behind the pectoral fin) and
    the 'Cuda's Blackfin is deep navy over silver (Great's twin from afar); only the
    Puffer and 'Cuda GLBs changed; the bundle is hosted (sha256 87721930...).
    **v7 (2026-10-12):** the four Tide Pass skins on every fish (27 a fish, 162;
    sha256 72895dd2...); Undertow's spirals are teal under a wide halo on a
    mid-toned violet, since thin pale lines on its dark body scored 0.21–0.24.
    Every worn skin is fetched ahead when another player wears it (player
    attributes `WornShade`/`WornSpecies` → `CardPhoto.preloadSkin`). **v8
    (2026-10-12):** relief normal maps on every skin, the Nibbler eye-mask fix and
    the Diamond and Prismatic retextures (see "The 2026-10-12 batch"); all six GLBs
    changed.
- **The pull-back loop (owner, 2026-10-10: "I still feel like we're missing a factor
  that pulls people back over and over. I do want to add random rarities of fish that
  can be eaten for more towards the haul or like 10 total unlocks a skin"; of the four
  proposed, "All four please!"; built, GDD §8 "The pull-back loop"):**
  - **Rare catches** (`Config/Catch`, `Shared/Catch`, `Shared/RareSpawn`,
    `CatchService`): any prey can swim Silver (Haul ×2, since 2026-10-18), Golden
    (×3), Glowing (×6), Crystal (×12) or Prism (Prism Tide only, ×25), with coral and
    DNA. **Rates are per player, not per fish** (owner, 2026-10-18: "I caught three
    crystal fish in about 5 minutes ... rerun the spawn rates"; the old per-fish odds
    over ~4,100 fish gave a hunter a Crystal every ~5 min and 5–10 Golden a minute):
    each player out in the biomes has a stream per rarity (`RareSpawn`, the same code
    in the server and the sim) that turns a fish rare in their own biome, 340–750
    studs off, on a fish they can swallow, never within 320 studs of anyone (no pop
    in view); species picked evenly, then a school, then a fish; it lives 2–7 min by
    rarity and turns plain only out of everyone's sight; a crowded biome with nowhere
    out of sight brings an eaten fish back rare. Tides multiply the rate (×3 in their
    first 2 min); the Catch of the Week has its own `weekly.rate` stream on its
    species. Measured by `tools/tests/run_catch_sim.sh` (the school layout, a hunter
    chasing glints and a casual player taking only what's within 60 studs of their
    path; checks `every` within ±30%; rerun it after changing rates, lives, `spawn`,
    `Config/Prey` or `Config/Tides`): a hunter's minutes per catch Silver 0.8, Golden
    1.9, Glowing 10, Crystal ~31, Prism ~2.6 a Prism Tide; a casual player a third to a
    half of that (owner, 2026-10-20: "i havent seen a single gold or crystal fish
    spawn today": Golden, Glowing and Crystal rates ×2.7/×2.3/×3.4 and lives longer;
    were Golden 5, Glowing 25, Crystal ~100). Skin goals in one biome: Golden ~2.5–3 h,
    Glowing ~6–8 h, Crystal ~7–9 h. Shell spots doubled the same day (300 on the
    shelf, 28 golden in the Trench). The server streams which
    are rare (`PreyRarity`, `GetRarities`) and
    `SchoolController` draws them (foil, Neon teal, Glass, rainbow; sparkles and a
    light; their texture held aside), each with a **glint** (playtest 2026-10-10: a
    Golden Minnow was gone by 100 studs): a four-point star at a fixed 15–21 px out
    to 240 studs, fading in past 18, only on fish drawn that frame. It draws on top
    of the haze (`AlwaysOnTop`; depth-tested, the haze fogged it out past ~100 studs,
    playtest 2026-10-11), and rock hides it by ray instead: 6 rays a frame from the
    camera, round the stars in reach, against Terrain and the collidable parts of
    `Workspace.World`, easing it out and in (`glintBlocked`, `glintVis`). `HuntService` takes a fish's rarity as it's
    eaten (`CatchService.take`) and fires `Events.caught`.
  - **The Catch Logbook and skin goals** (owner, 2026-10-18: "a catch logbook that
    shows the largest they have caught and they can track total gold/crystal/silver
    etc that they have for each fish. They will need atleast 10 gold of 5 different
    species to unlock the skin. Once the skin is unlocked, it is unlocked for all of
    their fish"): the LOG's Catch Log is an entry per prey species (from
    `Config/Prey`, so new prey show by themselves; `PreyPhoto` lazy photos, a dark
    ??? silhouette until caught) with its biggest (overall and per rarity) and its
    totals per rarity, and the five goals on top with your fish in the skin and FOR
    EVERY FISH. A goal is N of a rarity from each of S prey species (`Config/Catch`
    `unlock`, `Catch.goal`/`met`, counted from the lifetime `data.catchLog`): Silver
    10 × 5, Golden 10 × 5, Glowing 5 × 5, Crystal 2 × 5, Prism 1 × 5; a met goal
    unlocks the skin for every playable fish, locked ones too
    (`CatchService.grantEveryFish`), re-checked on join, and a catch skin one fish
    earned on the old per-fish tracks became every fish's (`data.catchTracks` stays,
    unused). Sim hours of hunting in one biome: Silver ~1–1.5, Golden ~7 (Kelp ~10),
    Glowing ~15–22, Crystal ~25–30 (Reef ~60), Prism 2–6 Prism Tides. Catch Log rows
    include Silver (rows already paid keep `logRows`). Admin "Catch Log: add catches"
    (`catchAdd`: a rarity, N species, × count). Tests: `run_catch.sh`.
  - **Tide Clock** (`Config/Tides`, `Shared/Tides`, `TideService`, `TideController`):
    20-minute tides on Unix time, the same on every server, never one twice in a row:
    Calm, Golden Hour, Blood Tide (hunters faster, `PredatorService`), Sardine Run
    (bait-ball schools, `Config/Prey` `tideZones`, built after the others with their
    own seed so no school moved), Bioluminescent Night; the Prism Tide at 03/09/15/21
    UTC. Chip at the top, banner, a faint water tint (`OceanController.setTide`),
    forecast. Admin can force one (`TideOverride` Workspace attributes).
  - **Daily bounties** (`Config/Bounties`, `BountyService`), **Catch of the Week**
    (`Config/Catch` `weekly`, week 1 = 2026-10-05; a limited skin each week) and
    **weekly leaderboards** (`Config/Leaderboards`, `LeaderboardService`:
    OrderedDataStores `Weekly_v1_<board>_<week>`, a Studio fallback to this server;
    last week's top 100 titles).
  - **The LOG** (beside DAILY; `MenuController.openLog`): Catch Log, Bounties, Weekly,
    Tides. `CatchController` toasts catches and announces unlocks. Tests:
    `tools/tests/run_tides.sh`.
  - **Earned skins stop at Epic (owner, 2026-10-10: "we still don't want the most
    elite skins obtained that way that'll be rng and bosses/treasure chests"):** catch
    goals give Silver Common, Golden Uncommon, Glowing Rare, Crystal and Prism Epic; the weekly
    skins are Epic. Legendary and Mythic only roll (rolls, the wheel's jackpot,
    bosses, treasure). Keep any new earned skin at Epic or below.
  - **Biggest catches (owner: "track their biggest eat of each species and rarity of
    species too"):** every school fish has its own size (`Schools` `size` 0.82–1.18,
    4% trophies 1.25–1.5; mass and Haul go with size³); `data.catchBest[prey][rarity]`
    holds the heaviest, shown per cell and per row in the Catch Log, with a NEW
    BIGGEST toast for rare or trophy-sized records.
  - **Treasure Wheel (owner: "do want a spin wheel again"):** Hatch & Snatch's Luck
    Wheel ported (`Config/Wheel`, `TreasureWheel.luau` builds it, `WheelService`,
    `TreasureWheelController`), on the hub plaza at 240°. E / Y / SPIN spins, T / ALL
    is Spin all, a line for a second spinner; 8 slices, a 4% jackpot of a Rare+ skin
    from the current fish's line. Spins are never sold: one free every 4 h (online or
    off, up to 3), plus the Bounty Chest, the Catch of the Week and daily days 3 and
    6 (`data.wheel`). Admin: give spins, rig the next slice. **Details pass (owner,
    2026-10-10: "looks pretty cruddy. word overlap etc ... the setup is fine its just
    the details"):** each slice's two words sit in bands sized to the wedge's width
    at their inner edge (`sliceText`, `BIG_BAND`/`SUB_BAND`, capped letter heights;
    keep `big` ≤ 5 letters and `sub` ≤ 8), a pearl hub with a gold collar, warm
    smaller bulbs, boards drawn as rows (swatch, prize, %; `BoardRow`), the hint
    chip in the HUD's hint place above the health bar, and the win card at the left
    under the HUD column, never over the wheel.
- **Coral and vendors (owner, 2026-10-06):** Coral is the currency. Four vendor stalls
  round the hub plaza, near the dens, sell with it:
  - Outfitter: upgrades.
  - Den Mason: the Haul Chamber.
  - Tidecharm Trader: Lucky, Second Chance, Magnet and Feast charms, plus 10 shells for
    400 coral 5 times a day.
  - **The Outfitter's upgrades fit every fish** (owner, 2026-10-21: it "sells dash for
    all of them when not all fish can dash"): Deep Gills (a faster Dash only) is
    **Quick Recovery**, every fish's own ability recharging 12% faster a level
    (`Perks.boost`: the Dash in SwimController, the rest in AbilityController and
    AbilityService); the row names the current fish's ability (`{ability}` in the
    blurb). The id stays `Gills`, so saved levels carry over.
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
  Bioluminescent Night. (Whale Fall is a world event since 2026-10-14, see the PvP
  round; Leviathan Rising became the boss events.)
- **Monetization (built 2026-10-09; owner: "ready for monetization"):**
  `Config/Monetization.luau` (names, prices, descriptions, Creator Hub ids, tuning),
  `MonetizationService` (ported from Hatch & Snatch: passes checked with Roblox on join
  and after a purchase, ProcessReceipt → `DataService.processPurchase`, PolicyService,
  rewarded ads), `Store` + `OfferController` + `MenuController.openStore` on the client.
  **The ids are real since 2026-10-09** (all 4 passes and 8 products, created in
  Creator Hub under the private experience "Apex Abyss", universe 10769954850, place
  83646578075996; publish this place there with "Update existing experience"). An id
  of 0 is hidden in a live game and greyed out in Studio, and the admin panel grants
  passes and runs product effects without Robux. Full table in GDD §9.
  - Studio test purchases of products work even in the unpublished place file. A
    pass's creator owns it, so on the owner's account every pass shows Owned and a
    pass purchase can only be tested by someone else.
  - Rewarded video ads: the experience isn't eligible yet (ID-verified 13+ owner,
    2-Step Verification, public, the maturity questionnaire, 2K monthly users).
  - **Rule:** sell growth and safety, never bite damage. Coral (it buys Iron Jaw) and
    Kelp Wraps are never sold for Robux.
  - **Passes:** ×2 Mass 399 (every Haul gain ×2), VIP 299 (gold nametag tag, +10%
    coral), Den Expansion 149 (the "extra den slots": 25 more things placed at any level, `Config/Dens` `expansionCapacity`), Deep Garden 129 (Coral Garden ×1.5 and 16 h).
  - **Second Chance** 39: bought on the eaten screen it returns the Haul just lost
    (`data.lostHaul`, once, within 3 min of being eaten); otherwise it's a charm (hold up to 5).
  - **Double Haul** (the owner's idea) 19/49/99 by the Haul's size (≤ 60 kg, ≤ 2.5 t,
    more; since 2026-10-19 ≤ 0.6 kg / ≤ 12 kg / more, ad ≤ 0.6 kg): offered on the bank
    screen after the tutorial on a Haul at least `minFull` 75% full;
    one tap, WATCH AD, SKIP, **no countdown**. It doubles after ×2 Mass and
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
    away when you swim out of the hub; the phone's stall/den button hides while one is
    up (`MenuController.stallButtonHidden`). SHOP and DAILY sit beside the wallet card
    on PC and console, and at the end of the HUD button row on phones (the centre
    banners' second lines ran across them there); the View button opens the Shop on
    a controller. The growth note (×2 MASS, FRENZY ×2 · 14:03) is in the Haul card's
    top-right corner on every screen. `Ads.luau` doesn't poll in Studio (Studio
    never serves ads, and each check logged a warning).
  - **Later:** codes, Pearl crates, the Roblox group (id 0 in `tuning.group`).
- **Creator Rewards round (owner, 2026-10-12: "We need monetizable assets that pay
  based on play time as well with rewards"; built):** Roblox's Creator Rewards (July
  2025, replacing Premium Payouts) pay 5 Robux each time an Active Spender (≥ $9.99
  spent in 60 days) plays ≥ 10 minutes in a day, for their first three games that
  day, plus 35% of a new player's first $100. Built for it (GDD §9 "Creator Rewards"):
  - **Playtime gifts** (`Config/Playtime`, `PlaytimeService`, `data.playtime`): a
    ladder at 5/10/15/25/40/60/90 minutes played today (UTC), counted every 5 s for
    every player in the server; claimed one at a time from the DAILY panel (a gift
    strip under the streak, CLAIM GIFT); the DAILY button reads GIFT m:ss, GIFT !
    (gold, breathing) or DAILY ! (the streak wins). Each gift gives Tide Pass XP.
  - **Premium perks** (`Config/Monetization` `tuning.premium`): ×1.5 gift coral and
    shells, 1 free wheel spin a day (first tick of the day), +4 h Coral Garden
    (`Garden.rates` third argument) and a `Premium` character attribute → a pale
    blue ◆ before the name (`NametagController`). GET PREMIUM sits beside CLAIM GIFT
    for non-members and in the Shop's Free Perks row; never a wall.
  - **The Tide Pass** (`Config/Pass`, `PassService`, `MenuController.openPass`,
    PASS button, `data.pass`): 4-week seasons on `Tides.week` from 2026-10-12, 40
    tiers × 1,500 XP (30 × 2,000 until 2026-10-17); XP from `Events.banked/caught/bounty/bossKill/treasure/passXp`
    (new signals `bounty`, `bossKill`, `passXp`); free row + the **Deep Pass**
    developer product (399 R$, id 3718493448, `shop = false`, bought from the
    panel; `data.pass.paid`, per season, ×1.2 XP); CLAIM ALL claims everything
    unlocked; Overtide 500 coral per tier's XP past the last; a season turning claims
    what was unlocked and resets. Season 1 "Riptide" skins: PassTideglass (Rare,
    free 26), PassRiptide (Epic, paid 1), PassUndertow (Epic, paid 20),
    PassAbyssalCurrent (Epic, paid 40), `pass = 1` in `Config/Shades` (never
    rolled; recipes `pass_*` in make_shades.py; the universal list in lines.json).
    Pass rewards stay ≤ Epic. **The Deep Pass icon** (`marketing/deep_pass_512.png`,
    `_alt` the shark alone; owner, 2026-10-14, of generated key art: "nothing to do
    with deep pass and ... clearly AI") is built from the game itself: real renders
    of the models in the three Season 1 skins (`tools/marketing/render_fish.py`) on
    a card drawn in the UI palette and fonts (`tools/marketing/pass_icon.py`);
    screened 0.16 / 0.05. Make product and pass art this way, not with image models.
  - **Shared reward bundles:** `Config/Rewards.luau` holds the `Reward` type (coral,
    shells, wraps, charms, map, spins, skin, title, den, xp); `Shared/Reward.lines`
    describes one for a tile; `RewardsService.grant(player, data, reward, bonus)`
    pays one out (daily, gifts, pass all use it). Admin: playtime minutes/reset,
    pass XP, Deep Pass on/off, pass restart.
- **The 2026-10-12 batch (owner: "The UI's look cheap", the mouse "scroll[s] off of
  the screen onto my other screen", "Controls need to be more obvious during the
  tutorial and tutorial needs to be more directed", "too many buttons that boost the
  fish. Should only be left click to boost right click to bite", the Nibbler's
  "yellow part that shows up on all skins", rare skins "need to be dialed up a LOT
  ... full retextures. prismatic needs to be moving across the fish", skins "look
  pasted on the fish ... The designs need much more depth", "parts need to be actual
  physical parts ... Variants should also be different/upgrades ... For all playable
  models", "need a map/mini map"; all built):**
  - **Controls:** LEFT CLICK dashes, RIGHT CLICK bites; Shift, Q and F are gone
    (pad RT / RB and the touch buttons stay). Smaller fish are still swallowed by
    swimming into them. `Input.biteKey()` / `dashKey()` name them for every hint.
    The mouse lock is asserted every frame (the input render step), on every mouse
    move and when the window regains focus (`Input.holdMouseLock`); a PC with a
    touch screen keeps it. **A freed pointer (menus, Alt) can't be fenced:** Roblox
    has no confine-to-window mode, so in a menu the cursor can still cross to a
    second monitor; the lock only ever drops for menus now. Alt frees the cursor
    (Tab did too until 2026-10-13: in a game it opens Roblox's player list); **M opens the map** (it no longer
    toggles the cursor); R3 on a pad.
  - **Directed tutorial** (`Config/Tutorial` `controls`/`guide`, `TutorialController`):
    the card shows each step's keys as key caps (`Ui.keycap`) for the device, a
    trail of neon beads leads from the fish to the step's target (nearest exit,
    nearest food via `SchoolController.nearestEdible` + `ForageController.nearest`,
    the den's pool, `ShellController.nearest`) with the distance and an arrow on the
    card, and a line tells how to free the cursor. BANK HERE had stopped showing
    since the den record took `state.den`: the den's index is `state.denIndex`.
  - **Map:** `src/client/MapDraw.luau` draws the real seafloor from above
    (owner, 2026-10-14: "needs to be an actual accurate mini map not dots"):
    `tools/map/make_chart.py` rasterizes the Terrain fill ops (run_world.sh's
    dump) into a depth-shaded, relief-lit chart with contours
    (`assets/textures/map_chart.png`, `Config/Textures` `mapChart`; re-run and
    re-upload after any Terrain change), the biomes' borders dotted over it; the old
    sonar chart (biome dot fields) until the id is in. `MapController` keeps a minimap that slides under the fish (PC bottom-right,
    phone top-right) with the den ◆, a followed treasure X, the boss ● and other
    fish •, and opens the full map (click/tap it, M, R3) with every biome named and
    levelled, a legend and where you are. `BossController.position()` feeds it.
  - **UI design system v2** (`Ui.luau`): panels are layered glass (a vertical
    gradient, a hairline of light along the top, a stroke; a panel given a list or
    grid layout drops its hairline, which would take a slot sized from the panel:
    the Treasure Wheel's auto-sized chip grew to 1,309 px, PC 2026-10-15), buttons are gradients
    with a shaded foot, a rim and a hover lift, windows have a header band with an
    accent line, plus `Ui.heading`, `Ui.keycap`, `Ui.chip`. Everything comes through
    these helpers, so new UI must too.
  - **Parts and variants on mesh fish** (`Cosmetics`): a mesh body has no
    Head/Body1/Stalk parts, so those names are anchors in the fish's unit box
    (`ANCHORS` per body plan, `UnitW`/`UnitH` from the model) tied to bones (Head,
    Spine1, Tail); each piece is a Motor6D-jointed part under the Mesh model whose
    C0 is rewritten every frame from its bone's animated pose (`Cosmetics.follow`
    from FishAnimator), so a veil tail swings with the tail. Pieces live under the
    Mesh model so ScaleTo grows them. A variant's `meshScale` draws the fish bigger
    (`FishBuilder.applyScale`, `Applied` = the drawn length). **One variant per fish**
    (Sabrecuda, Porcupine Puffer, Dragon Moray, Deepfang Angler joined Puffball and
    Hammerhead), each rolling only for its fish (`RollOdds.excluded`); the Wardrobe
    orders them by fish; roll cards photograph parts on the real fish. These are
    part-built pieces on the Tripo mesh; real variant models can replace them later.
    **Fit to the body (playtest 2026-10-12: the Moray Eel's Sail Fin and Veil Tail
    floated a body height over its back; the Hammerhead was "a flat paddle laid on
    the snout"):** rolled parts are sized for the round graybox body, so `ANCHORS`
    carries a `partScale` for slender fish (Eel 0.55, Cuda 0.65, Shark 0.8) and
    head/back heights measured from the rigged FBX (snout middle, back top), set so a
    sail stands a third deep in the back; back pieces ride the spine bone nearest
    them. The Hammerhead is a bridge round the snout and two thick swept lobes with
    the eyes at their tips.
  - **Moving sheens** (`Config/Shades` `sheen`, `Config/Textures.luau`,
    `tools/shades/make_sheens.py` → `assets/textures/sheen_*.png`): Prismatic,
    Diamond, Divine, Aurora, Exotic, Nebula and Void carry a tiling image projected
    from all six faces of the mesh as Textures that `Cosmetics.animate` slides along
    the body (sized to the fish as it grows). The four are uploaded; Nebula reuses
    the H&S galaxy image (129645056585841), which the same account owns. Since
    2026-10-16 every Rare+ skin has one (see "The 2026-10-16 batch").
  - **Blood Sense (owner, 2026-10-13: "it should highlight players through
    surfaces as a flashing red thermal to show where the other players and
    predators are"):** `AbilityController` routes the ability button (left click,
    RT, the touch button, relabelled SENSE) by species: the Reef Shark gets Blood
    Sense, everyone else Dash. For 7 s (24 s cooldown) every other player's fish
    and every drawn predator (`PredatorController.drawn()`) wears a Highlight in
    `AlwaysOnTop` throbbing red → yellow at 2.5 Hz, with a red, drained
    ColorCorrection cast over the water; nearest first, within Roblox's cap of 31
    Highlights. Since 2026-10-18 it goes through the server (`Sensing`; see the
    2026-10-18 owner batch: faster, a wider swallow, prey marked too); the HUD's ability bar
    shows the reveal in red, then the recharge.
  - **Skins v8 (depth):** v8 shipped a normal map of each skin's relief
    (`relief_normal`, blended over the fish's own at pack time). **The account was
    terminated over one on 2026-10-13** (the Nibbler Living Reef relief map, asset
    133593810809027, a flat lilac image our screen scored 0.000); every appeal was
    accepted and it was reinstated. **v8.1 has no normal maps at all**
    (`pack_shades.py` `NORMALS = False`, the fish's own included) and
    `screen_shades.py` flags any image whose mean colour reads as a normal map
    (B ≥ 240 with a spread ≤ 10, R and G within 20 of 128). Never upload a normal map; put depth in
    the colour map. The creases are never quieted below `DETAIL_FLOOR` 0.8 of
    their strength. The
    Nibbler's yellow crescent on every skin was the cream band behind the eye
    counted as eye (kept from the base texture): `_eyes` keeps only components
    holding pupil pixels inside a smaller sphere. Diamond is a cut-gem retexture
    (bevelled facets with dispersion fire, mirror, relief 1.6) and Prismatic a
    holographic foil (diffraction lines, hue-shifted cells, pearl, metal). Bundle
    v8.1: sha256 9a523a58… (285 images, no normal maps, highest classifier 0.127;
    v8, 6e4ab557…, carries normal maps: never import it).
  - **Bone-white teeth (owner, 2026-10-14: "make sure the teeth are always teeth
    white and not the color of the skin. All fish should always have bone white
    teeth"; skins v8.2):** the Angler's fangs and the 'Cuda's teeth had taken each
    skin's colour, and the Reef Shark's tiny teeth too. `tools/shades/teeth.json`
    marks each toothed fish's mouth (boxes on the head views and a colour rule; the
    shark's `slot` rule reads `bake_mouth.py` close-ups), and every skin paints those
    texels `BONE` (0.92, 0.92, 0.91), satin, no glow or metal (a warmer bone,
    0.93/0.92/0.88, counts as pale cream on the screen, Cr − Cb ≥ 3, and two shark
    skins were flagged for it: keep teeth neutral white). Each toothed fish
    (Angler, Cuda, MorayEel, ReefShark) also packs a **Natural** skin, its own
    texture with white teeth, that `Cosmetics.paintMesh` wears with no shade (and,
    tinted, under a shade not imported yet); `CardPhoto.preloadSkin` fetches it for
    other players with no shade. A moving sheen can't be masked, so on a toothed
    fish (one with a Natural skin) it leaves out the face its head points out of
    (`Cosmetics` `headFace`; PC follow-up 2026-10-14: Nebula turned the Reef
    Shark's teeth violet from the front). The PC's screen reads each fish's own
    texture from `assets/fbx/species/<Fish>.fbx` (`screen_shades.py` `fbx_base`,
    identical to the cloud's .npz bases), so no `--base` is needed there. The
    Nibbler and Puffer have no teeth. A new fish
    with teeth gets a teeth.json entry (docs/ASSETS.md "Teeth are always bone white").
    Bundle v8.2: sha256 feb731f3… (the four toothed fish's GLBs changed, 28 quads
    each; Nibbler and Puffer byte-identical to v8.1; 204 images screened, none
    flagged, highest 0.172).
- **The 2026-10-16 batch (owner: the Wardrobe fish "facing the wrong direction",
  "you only made 2-3 skins interactive. The one where its lava should have texture
  that looks like lava gaps and crystal should have a crystal texture ... Still too
  many flat models", "left click is dash and right click is just a weaker dash", "a
  free verson of the deep pass ... and a visual showing the unlock tree/pass ...
  its just locked", "Map needs a name of the location", Build mode "should set them
  in a locked screen where they can edit the den and drag parts there", movement "a
  tad easier"; all built):**
  - **Wardrobe pose:** `FishPreview` turns the fish 118° (± a slow sway), head left
    and toward the viewer like the roll cards (at −70° it faced right and away).
  - **Bite is a snap, not a dash:** `HuntController` looks for a target first
    (a player fish in reach, else `PredatorController.nearest`); only then does
    `SwimController.lunge(true)` dart. Into open water it's the jaw snap alone.
  - **Pass panel:** FREE PASS (everyone) and DEEP PASS cards with what each gives,
    OPEN / LOCKED with a drawn padlock (the Deep card buys it), a track with a node
    per tier, and every reward as a lit 3D photo (`CardPhoto`: the skin on your
    fish, coral, shells, wraps, charm) or a badge (den, title, map, spin); the Deep
    row is padlocked until bought. The free row was already every player's.
  - **Map name:** the minimap's bar under it names where you are: YOUR DEN, THE
    HUB, the biome, or OPEN WATER (`MapController` `placeName`).
  - **Build mode editor view:** Build mode takes the screen (`Input.editing`: the
    fish holds still, the cursor stays free; `CameraController.override` hands the
    camera to `BuildController` `viewCFrame`). The camera orbits a focus on the
    storey's deck: right-drag orbits, WASD/arrows pan (kept inside that storey's
    rooms), wheel zooms 10–72, Space/C (PageUp/PageDown) change storey; zoomed out
    it lowers toward the floor instead of pressing into the ceiling (each storey
    has ~22 studs), and a ray from the focus keeps it out of rock. Click places;
    press on a placed thing and drag it, let go to put it down (a quick click
    picks it up for the next click; dropped somewhere refused, it goes back);
    drag a thing straight out of the tray. Pad: left stick pans, right stick
    orbits, RT places at the screen's middle, A changes storey. Phone: drag orbits,
    pinch zooms, a tap places or picks up, FLOOR changes storey. The aim reaches 200.
  - **Easier swimming** (`Config/Tuning` `swim`): accel 2.6 → 3.1, drag 1.7 → 2.3
    (stops sooner), `cruiseTurn` 1.2 (tighter at speed) and `levelZone` 12°: a
    camera tipped less than that swims level, past it the climb eases in (straight
    up is still straight up), so looking about no longer drifts the fish.
  - **Moving layers on every Rare+ skin** (off since 2026-10-17: they read as a
    pattern pasted on; effects replaced them, see "The 2026-10-17 owner batch")
    (`Config/Shades` `LAYERS`, `AURAS`): each
    Rare and better skin (and the Golden catch skin) slides a layer that suits it,
    and gets an aura where it had none. Five new coloured layers
    (`tools/shades/make_sheens.py`, python3.11 + scipy): `sheenLava` (molten veins
    under a crust: Magma), `sheenCaustic` (sunlit ripples: Tidepool, sea glass,
    reefs, wrecks, coral, Scarred), `sheenFacets` (crystal glints: Crystal,
    Glacier), `sheenCurrent` (streaks raking back: Chrome, Riptide, Undertow, Abyssal
    Current, Mandarin, Ribbon, Wave, X-Ray, Abyss Ink) and `sheenBolt` (live arcs:
    Thunder); the uploaded ones are reused (gold on gold skins, tinted sparkle on
    glow and pearl skins, stars on space, prismatic on Prism). Their colour is set
    everywhere and alpha says where they show, so the classifier sees a coloured
    field, not bright lines on black (screened 0.000–0.002). Ids 0 until the PC
    uploads the five PNGs.
  - **Skins v9 retextures (patch packs):** Magma (Moray) is ~115 cool basalt plates,
    each its own tone with pits and a lit rim, split by recessed lava rivers that run
    white-yellow to deep red with a strong glow map; Catch Crystal (every fish) is
    clusters of long prism shards with lit and shaded faces, a milky veil, rainbow
    sparks at some tips, a druzy crust between and frosted fins (gloss, 0.2 metal).
    They ship as `<Fish>_ShadesPatch.glb` (bundle `shade_patch_v9`, sha256
    db7d971c…, highest classifier 0.021), packed with `pack_shades.py --only`
    and filed by `organize_shades.luau` without clearing the fish's other skins.
- **The 2026-10-16 report's decisions (owner: "Go with all of your recs"; built):**
  - **Pad:** pass tiles are selectable (a transparent `Select` button on each), and
    the strip follows the selected tier (`openPass` `followed`); the Shop has a Log
    row (OPEN → `MenuController.openLog`) beside the Tide Pass row.
  - **Pass tiles claim:** a tap (or A) on a READY tile sends `ClaimPass` (tiers are
    claimed in order, so everything unlocked before it comes too); on the locked Deep
    row it buys the pass. The Deep card's UNLOCKED stays (not OPEN).
  - **Phone Build mode:** a slim full-width bar along the bottom
    (`BuildController.layoutTray`), its tray folding away (TRAY ▼/▲; it folds by
    itself when a thing is picked), the help line at the top (`touchHint`), and the
    swimming HUD hidden while editing (`HIDE_ON_TOUCH` ScreenGuis: Hud, the stick
    ring, Heal, ItemWheel, Wallet, Offers, Map, ...; put back on DONE). Every device
    aims only at the storey being viewed (a tap down a shaft placed on the deck
    below).
  - **Turning beats snapping:** after R / F, LB / RB or TURN (`handTurned`, cleared
    on a new pick), snapping still backs a piece onto a wall but keeps its turn,
    measuring its turned footprint.
  - **Stacks settle:** `DenSpace.settle` (run by `DenService` `placedChanged` on
    every change) drops raised things with nothing under them onto the highest top
    below (or the deck), lowest first, so a stack follows its base; one that can't
    stand there goes back to the tray with a note. Tested in `dens_test.luau`.
  - **Second Chance** has its own photo, a life ring (`CardPhoto` `lifeRing`,
    outcome id `secondChance`).
  - **Phone toasts:** with a menu window or the Build bar up, toasts go to a thin
    strip under the top bar (`HudController` `placeToasts`).
  - **Whale Fall visibility:** every carcass wears the `WhaleRim` (was deep floors
    only) and sends up a plume of chum 40–90 studs (`ChumController` `plume`), so it
    shows over the kelp and the reef.
  - **Stronger layers** on the skins that read dark or flat (CatchGolden, CudaChrome,
    ShkScarred, MorRibbon, WeekWreck, WeekWave, PassAbyssalCurrent: lower
    `transparency` in `LAYERS`), plus **skins v10** retextures in a patch pack
    (`shade_patch_v10`, `assets/shades/patch10`, sha256 73929747…, 63 images,
    highest classifier 0.090): CatchGolden warmer (hue 33–37°, metal 0.15, a faint
    even glow map, so it reads gold, not olive, in the water), the three universal
    Week/Pass skins and Ribbon, Chrome (gunmetal, lighter, metal 0.2: metal shows
    the dark water, not its colour) and Scarred lifted. **Teeth:** the gums between
    the teeth took Thunder's bolts and glow; `Fish.mouth_zone()` now clears glow
    near the teeth on every skin of every toothed fish (`MOUTH_DARK`) and Thunder's
    bolts fade out before the mouth. `make_shades.py` no longer writes normal maps;
    `render_shades.py` `water=0.35` previews a skin in the game's haze.
  - Unchanged on purpose: a pad enters Build from the den menu (B means back), and
    panning out of the door can't happen in a private den.
- **The 2026-10-16 round-2 report's decisions (owner: "Go with all of your recs, roll
  it into one"; built):**
  - **Whale plume** (`ChumController` `plume`): dense (9/s), big (12→46), pale silt,
    faintly self-lit (`LightEmission` 0.35, `Brightness` 1.6), rising ~150 studs;
    dark particles were lost in the haze.
  - **Build camera:** your own fish is hidden while editing
    (`CameraController.hideFish`), the view starts in the middle of the fish's room
    at zoom 60, and zooming out raises the lowest pitch toward `VIEW_TOPDOWN` 58° and
    keeps the camera under the vault along its line of sight; the zoom left over
    widens the lens up to `VIEW_FOV_MAX` 96 (`CameraController.overrideFov`).
  - **The HUD is hidden in Build mode on every device** (`HIDE_WHILE_BUILDING`): on
    PC its chips covered the view and swallowed clicks. A placement with no answer
    within 1.2 s says "<thing> didn't go down · try again" (`expectAnswer`).
  - **Den walls:** the dens' rock is Limestone (`DenCarve` `DEN_ROCK`), a material
    nothing else uses, wearing Rock's toon plates (the same image id,
    `Config/Materials` `Limestone`) in the dens' tan (`Cave.COLORS`); Sandstone's
    bands read as wood grain. Run `make_toon_materials.luau` again after a sync that
    adds a toon entry. Mosaic and Marble floors are toned down; Basalt is lifted to
    (88, 98, 110) so the Vents' floor shows its tile.
  - **Skins wait for their textures** (`src/client/SkinLoader.luau`):
    FishAnimator's dress key carries `SkinLoader.state` (loaded / waiting / trying);
    while waiting the fish shows the stand-in (`Cosmetics.apply`'s `skinReady`), a
    failed texture is fetched again (backoff up to 30 s, 8 tries), after 12 s the
    skin goes on anyway, and once everything loads it's put on afresh.
  - **Depth in a den** reads a fish in front of its doorway (`Layout.hubExitFrame`).
  - **Stacks:** moving a base carries everything on it, turned with it
    (`DenSpace.stackOn`, `DenSpace.carry`, `DenService` move; a carried thing that
    can't stand goes to the tray); a second click within 0.6 s on a just-picked
    stacked piece picks the one under it (`STEP_DOWN`); a tray tile stays in place,
    greyed at ×0, for the rest of the Build session (`shownThisSession`).
  - **Phone messages** with a menu window up show on the window's subtitle line for
    3 s (`HudController` `noteInWindow`); in Build mode on a phone, under the help
    line.
  - **Treasure Wheel E:** within its reach E is the wheel's unless a counter is
    within `Config/Wheel` `stallClose` 6 studs and nearer.
  - **Menu rows don't rebuild under a held press** (`MenuController` `rerender`
    waits for a pad A or the left mouse button to be let go).
  - **Lamp cords** end at the real rock (a ray up, half a second after building).
  - **Admin "Den: simulate an old save"** (`DenService.simulateOldSave`): puts the
    den's things at their storeys' old heights, clears the layout mark and runs the
    relayout an old save gets.
  - **Skins v11:** WeekWave and WeekWreck retextured lighter with a faint glow map on
    every fish (patch pack, see docs/ASSETS.md).
- **The 2026-10-17 report's decisions (owner: "Go with all of your recs, roll it into
  one"; built):**
  - **Whale plume, murky not glowing** (`ChumController` `plume`; PC: "a bright,
    smooth white column ... smoke or a beam of light"): sandy to olive-grey silt
    (`LightEmission` 0.08, `LightInfluence` 0.75), a wispy core with a slow sideways
    drift, plus a second emitter of small dark chum flecks; still ~150 studs tall.
  - **The Vents' floor has its own light** (`WorldService` `ventFissures`): six
    jagged Neon lava cracks per basin seated by raycast, each with a warm PointLight
    (range 30) pooled round it, and the Vents grade is lighter and warmer (exposure
    −0.32, tint (198, 200, 222)); lifting the basalt colour alone didn't reach the
    eye at 50 studs.
  - **Admin "Skins: pretend my worn skin's download fails (18 s)"**
    (`SkinFailTest` player attribute → `SkinLoader.claimTest`): the local fish's
    worn skin shows the stand-in, logs `[SkinLoader] test:` retries, goes on at 12 s
    and is put on afresh at 18 s.
  - **Messages in Build mode** go to the bar's status line on every device
    (`HudController.buildNote`, set by BuildController); the boss countdown shrinks to
    a thin strip at the top while editing.
  - **No den lamp in a shaft's mouth** (DenBuilder skips spots within the shaft's
    radius + 4 on the storey it opens into).
  - Left as is: the Puffer's WeekWave crests read a little pink (they passed the
    screen).
- **The 2026-10-17 owner batch (owner: two messages of den, UI, skin and control
  notes, then "Read both messges and make recs and changes"; built):**
  - **Skin effects, not layers** (owner: "When I say the skin needs movement or glow
    I mean the skin needs EFFECTS. not just a ripple effect running over the design",
    "too many of them are obviously just mesh slapped onto the fish"): the six-face
    projected layers are off (the `sheen` mechanism stays in Cosmetics, unused).
    `Config/Shades` `FX` gives 25 skins an effect set built by `Shared/SkinFx` from
    `Shared/Fx` presets: every Tide Pass skin (Undertow's swirls spiral head to tail),
    every Legendary and Mythic (Divine's halo and rays, Aurora's curtains, Thunder's
    crawling arcs, Sunburst's turning rays, Void's accretion ring and vortex, Comet's
    tail, Prismatic's rainbow rim and ribbon, ...), Ghost, Abyss Ink, the treasure
    skins and the chased Epics (Magma, Diamond, Crystal, Prism, Glacier). An effect set
    replaces the skin's aura. Ribbons sway on their own so they draw on a still fish;
    nothing draws in a ViewportFrame. Particle images come from `Config/Textures`
    `fx*` once uploaded (`assets/textures/fx_*.png`), Roblox's own until then.
  - **Ghost is spectral green** (owner: "doesnt need to literally be invisible, it
    should be spectral green with some mist coming off of it"): the fish's own look
    under a breathing green Highlight fill and a bright rim, mist and wisps; no
    ForceField, no see-through.
  - **Boost trails** (owner: "boost effects, such as bubbles, rainbow, glitter, fire,
    etc as an earnable customization"): `Config/Trails` (Bubble Stream, Glitter, Ink
    Cloud, Fire Wake, Frost Wake, Rainbow Wake, Storm Wake, Stardust), every fish's,
    worn one at a time (`data.trails`, `data.trail`, the character's `Trail`
    attribute, the Wardrobe's TRAILS tab, `Equip` kind "trail"); `TrailController`
    sheds them off the tail from 60% of top speed, full on a dash. Earned on the Tide
    Pass (`trail` rewards), never sold. Admin "Every shade, part, variant and boost
    trail".
  - **Tide Pass 40 tiers** (owner: "extend the pass to 40-50 and add some in with some
    other smaller items like maps and more coral"): 40 × 1,500 XP (the same 60,000 a
    season), eight trails (free 6/18/32, paid 4/11/16/27/36), a Tattered map, more
    coral. **Pass skins are every fish's** (owner: the Deep Pass "needs to let
    players know that the skins earned work on all fish"): `RewardsService.grant`
    unlocks a `pass` skin for every species; the cards, subtitle and Index say so.
  - **INDEX** (owner: "an index or something to show them how they are to get all of
    the harder skins, parts, what the parts do"; "more direction for players starting
    out"): the HUD's ODDS became INDEX (D-pad right); `MenuController.openIndex`:
    GUIDE (Next for you: tutorial step, the 'Cuda's gate, the next biome, rolls ready,
    the den's next dig; How it works), SKINS (this fish's line, then every fish's,
    each with how it's got, progress and its effects), PARTS (looks only; the Angler
    Lure part now lights dark water like the lure), VARIANTS, FISH (unlock rules,
    stats), TRAILS, and ROLL ODDS.
  - **Den shop** (owner: "I dont see a shop at all where you buy den items"; "E does
    nothing in my den"): E / Y opens the den menu anywhere in your own den (the chip
    shows at the pool: DEN & SHOP · B BUILD); Build mode has SHOP (top-right of the
    bar, Y on a pad, in the phone row) opening `MenuController.openDenShop` over the
    editor (the bar steps aside and the view holds still until it closes).
  - **Den travel loading** (owner: leaving a den "it takes about 20 seconds for the
    safe zone to load and you see everything else and through the floor ... a loading
    screen is fine"): within 36 studs of a portal the client asks `Prestream` and the
    server streams the far side in (`RequestStreamAroundAsync`, 10 s); after a move
    the wash stays up, holding the fish still, as a loading screen (SWIMMING OUT TO
    THE HUB and a tip from `Config/Tutorial` `tips`) until rock is under and round the
    fish and the doorway's model is there, held 0.4 s, at most 25 s.
  - **'Cuda earned, Golden 100** (see the species and catch-track notes above).
  - **Barnacled** (owner: "what the hell is a shipwreck skin doing"): WeekWreck's name
    and look; the id stays.
  - **Easier navigating** (owner: "Still need some better control function I think.
    Still a bit difficult to navigate the fish"; `Config/Tuning` `swim`/`camera`,
    `tools/tests/run_swim.sh` simulates the step and must be kept in step with it):
    the swim steers by `SwimController.aim` (CameraController sets it before any roof
    slide or shake); a wall glide (the collider cast ahead: speed into rock eases off
    by `wallEase`, the rest slides along, facing along the wall) plus `feedback` (what
    the physics didn't deliver comes off the swim); turning blends `pivotTurn` 2.6 →
    `cruiseTurn` 1.2 between 15% and 75% of top speed (`dashTurn` 0.75), eases in
    (`turnSettle`), brakes through hard turns (`turnBrake` 0.35 × top by 150°), and
    fish past the size knee turn by their drawn length (`bigTurn` 0.3); letting go
    stops in ~0.9 s (`drag` 2.0 + `stopBrake` 0.35); the level zone ramps 8° → 30°;
    Space / C go straight up and down; **`indoorSpeed` 48** caps top speed in the hub,
    tunnels and dens (a Dash still doubles it); pad look `gamepadCurve` 1.7, steer dead
    zone, phone `touchDeadZone` 0.1; the roof slide fades in (`slideFrom`/`slideFull`).
  - **Open floor only** (owner: "ensure that no shells or shrimp or fish spawn in or
    under items that the player cannot access"): `Ground.open(x, z, radius, minUp,
    room)` keeps a spot only where the surface ray's first hit is the Terrain, a
    1.25-stud ball can come straight down onto it and nothing solid is round it;
    ShellService, ForageService and TreasureService dig sites use it (each logs a
    count at start). Prey schools are lifted over the real ground along their loops
    once the world is built (`Ground.y`, ramps, never under an overhang), published
    as the Workspace attribute `SchoolLifts` so the server's checks and the clients'
    drawing agree (`tools/tests/run_schools.sh`). Relies on WorldService finishing
    its dressing before ShellService and ForageService start.
  - **Predators land their bites** (owner: "horrible aim ... even sitting still they
    cant hit me"): the tell starts ~15 (Barracuda) / 18 (Reef Shark) studs out, it
    brakes and glides in during the tell (≤ 0.55× speed) so the jaw ends just off
    the fish, it turns tight close in, hunts right down to the floor, and can't tell
    or bite through rock (`Ground.sees`: arches and reef tunnels hide you).
    `Config/Predators` `strike`; `tools/tests/run_predators.sh`: a still or slow fish
    ~100% (was 0–21%), a Dash during the tell escapes.
  - **Bigger swallow reach** (owner: "if you dont directly hit the fish it doesnt
    eat it"): 1.15× the old reach + 0.35 + the prey's radius, with a suction pull
    (`Config/Prey` `eat`; HuntService allows the same): a 2-stud fish eats a Minnow
    from 1.86 studs (was 1.12), a 12-stud fish a Snapper from 8.1 (was 5.85).
  - **Signature abilities** (owner: "each different fish should have their own
    limitations/advantages ... You decide how that plays"): `Config/Species`
    `signature` is the ability on each fish's button (`Config/Abilities` holds the
    numbers; the other listed options wait for the upgrade trees): Nibbler Dash (the
    quickest recharge), 'Cuda **Torpedo** (1.4 s straight sprint at Dash speed,
    turning ×0.2, 7 s; outruns anything in a line, can't dodge), Pufferfish **Puff
    Up** (4 s: drawn ×1.45, can't be swallowed, bites do half and cost the biter 10%
    of their health, a predator takes recoil and flinches; swims at 45%; 16 s),
    Moray **Burrow** (against rock, wreck or seabed within 0.9 of its length: it
    hides until it moves 4 studs, presses again or 30 s pass; predators ignore it,
    other players see it faded with no name tag; its next bite within 1.5 s is an
    AMBUSH ×1.6; 8 s after), Reef Shark Blood Sense, Anglerfish **Lantern Flash**
    (predators within 48 studs stunned 2.5 s, nearby players' screens whited out by
    how much they face it; 18 s). `AbilityService` (requests `UseAbility`,
    `EndAbility`) sets the character attributes `Puffed`, `Burrowed`,
    `BurrowStrike`, `FlashAt`; HuntService, PredatorService and the clients read them
    (`AbilityController`, FishAnimator's puff scale, NametagController). The Torpedo
    stays within SpeedService's Dash allowance.
  - **Aggressive and accurate (owner, 2026-10-20: "predator fish need to be a lot more
    aggressive and more accurate as well. Easily killed a barracuda at lvl 16 by just
    going back and forth at it. It wouldnt attack unless I sat still"):** an ambusher
    within its tell distance snaps at once (no burst needed), a `whip` hunter turns on
    a fish beside or behind it instead of swimming off (Barracuda ×3.2, Reef Shark
    ×1.8), bursts lead the fish (`burstLead` 0.7) and line up at `burstFacing` 0.75,
    and past `commit` of its tell (Barracuda 0.6, Shark 0.7) it lunges on its line, so
    a well-timed juke escapes about half the time. Barracuda: telegraph 0.7, bite every
    1.4 s, winded 1.2 s, aggro 90, trigger 44, gives a fish up after 6 failed bursts
    for 8 s. Reef Shark: telegraph 0.8, bite every 2 s, aggro 110, turns 0.6 at speed,
    lines up at 0.75. Sim (`run_predators.sh`, new `harass` fish darting in and out):
    Barracuda bites the harasser 99% of tells (was never), a juke 56%, a still fish
    96%; a Dash, doubling back at its burst, hiding, burrowing and a LV 40 'Cuda's
    straight run still escape. Shark: harasser 42%, juke 47%, a loop as it closes 0%.
  - **Predator styles** (owner: "shark should be able to catch fish with speed but
    each different fish should have their own limitations/advantages";
    `Config/Predators` `style`): the **Barracuda** (`ambush`) lurks low by cover,
    stalks at 14, and within 32 studs bursts at ~49 studs/s for 1.6 s (a tell
    started in the burst keeps the speed); it barely turns in a burst, is winded 3 s
    after (slow, no tell, no bite) and leaves a fish alone 25 s after 2 failed bursts.
    The **Reef Shark** (`tracker`) cruises at 44 (46 until the 2026-10-18 speed curve), keeps a chase to 240 studs
    and notices a fish under half health from twice as far; it turns wide, brakes
    weakly in its tell and won't follow into kelp. Both bite only a fish in front of
    the jaws (a sideways juke beats both), start the tell from their real braking
    distance and swim out to come round at a fish inside their turning circle;
    clients show BURSTING AT YOU · JUKE SIDEWAYS and STUNNED. Sim
    (`run_predators.sh`): a still or slow fish is bitten nearly every time, the
    'Cuda outruns both at its level, a juke at the warning escapes, a loop must
    come as the shark closes. Hooks: `Burrowed` fish aren't prey (bosses still
    hunt them), `PredatorService.stun(position, radius, seconds)`, a bite on a
    `Puffed` fish does `puffDamage` 0.5 and the predator takes `puffRecoil` 0.12 and
    flinches `puffFlinch` 2.5 s; `PredatorService.biteScale(player)` halves boss
    damage on a puffed fish.
  - **The hub, dialled up** (owner: den names "look rough", "more of an entrance ...
    not just a hole with light coming out", the starter zone's ground "rough", the
    wheel and stalls "fuzzy, cheap" after the toon rock): the fuzz was the toon
    MaterialVariants, which override a base material game-wide on parts too (8–16
    stud tiles show as one blurry plate on a small part): the wheel's Marble and
    Slate, the stalls' Wood, the signs' Slate, Foil and Metal grain. **Rule: small
    built pieces use SmoothPlastic (and Neon accents), never an overridden
    material.** New modules: `src/server/Decor.luau` (part helpers and palette),
    `DenDoor.luau` (doorway fronts: a rounded stone arch on jamb stones, brass
    lanterns lit when someone lives there, a stepped threshold, coral and kelp at the
    feet, the portal a dark pane in a brass collar with a ForceField shimmer and a
    rising bubble curtain; a lacquered nameplate "NAME'S" over the level in gold,
    single-line scaled labels with non-breaking spaces so a 22-character name fits;
    EMPTY DEN / VACANT on a slate plaque; the in-den way out TO THE HUB in the same
    style) and `Plaza.luau` (flagstone rings, a two-tier dais and compass rose under
    the beacon, a brass-inlaid curb, paths to every door and tunnel, seven planter
    beds with decor starfish fixed to the curb, lamp posts, brass wall lanterns,
    EXIT boards per tunnel naming that way's biomes and levels, and part-built stalls:
    counter, striped awning in the vendor's colour, sign, lanterns, shelves and
    goods; the MarketStall import is no longer used). The wheel is SmoothPlastic
    colour blocking with Neon bulbs, a scallop crest, pearl finials and a chest on
    its stage; every name TreasureWheelController reads is unchanged. `Config/World`
    `hub.paving` 1.1; Cave's sand drifts are gone and its wall bulges sit higher.
    About +1,950 parts in the hub (anchored, CanTouch off, decor CanQuery off).
    Previews: `bash tools/preview/run_hub.sh` (the cavern voxelized plus the parts,
    lights, particles and SurfaceGui text in Cycles); `check_doors.luau` checks every
    doorway and exit clears a LV 100 fish.
  - **Skins v12** (patch pack `shade_patch_v12`, `assets/shades/patch12`, sha256
    d94abb99…, 228 images, no normal maps, highest classifier 0.172): **whole eyes**
    (owner: "Every single skin on nibbler glitches into the eye"): an eye's sclera
    sits on several UV islands and `_eyes` dropped the ones with no pupil, painting
    them with the skin; now `eyes.json` holds each fish's hand-sampled `eye` and
    `skin` palettes, a texel nearer an eye colour is eye, each piece mostly inside the
    eye sphere is kept whole with its holes filled, the edge is unmixed from the
    texture's anti-aliasing and atlas gaps are padded (`tools/shades/render_eyes.py`
    renders eye close-ups). Every skin of the Nibbler, Puffer, Moray and Angler
    re-shipped. Redesigns that follow the body (`fin_reach`, `surface_polar`):
    Bumblebee (a bumblebee goby's wrapping velvet-black bands), Lilac (lilac to violet,
    fine iridescent scales, no spots), **Barnacled** (WeekWreck: slate-green hide,
    barnacle clusters kept clear of the eyes, violet coralline, kelp fronds), WeekWave
    (S-shaped crest bands with scalloped foam), PassUndertow (bold teal whirlpools on
    violet), PassRiptide (one glowing rip current head to tail); NibMaroon is a
    brighter garnet (the wine scored 0.31). Flagged as still reading pasted-on:
    PassTideglass, Prismatic, Divine. The six `fx_*.png` particle images are made
    (one tint, alpha draws the shape; ≤ 0.13 over black and white): ids go in
    `Config/Textures` `fx*`.
- **The 2026-10-17 round-2 report's fixes (PC report `2026-10-17-pc-2.md`: the fx ids
  are in, a2d4d1c; built on `claude/world`):**
  - **SK4:** the admin skin-fail test had never been committed; it is now
    (`SkinLoader.claimTest`, above). FishAnimator's dress key carries the skin's
    whole `SkinLoader.state`, so a skin worn anyway is put on afresh once it loads.
  - **Whale plume that carries** (`ChumController`): three stacked stretches of
    murky silt (sources 4 / 92 / 168 studs, darker and bigger higher up, glow
    0.06 / 0.03 / 0) to ~250 studs, meandering; built while the camera is within
    900 studs; fades 17 s after the whale. A boxless **WHALE FALL marker** (flukes
    glyph, distance in ft, AlwaysOnTop) over a settled whale from 90 to 620 studs
    (`Config/Chum` `whale.marker`), dimmed behind rock, hidden under menus, in Build
    mode, on the start screen and in the hub. The old silt rose only ~90 studs
    (Drag 0.1) and pale silt was lost against pale haze.
  - **A lit Vents floor** (`WorldService` `ventFissures`): 4–6 branching fissure
    systems a basin (tapered Neon cores over deep-red rims), one range-60 light
    each (brightness 2.2), embers and a low warm heat haze; `VENTS_GRADE` in
    OceanController by biome (exposure −0.15, red-brown haze, density 0.76), so the
    Trench at the same depth is unchanged.
  - **Effects that read in a still:** bigger, denser, brighter crystal, glints,
    gold, embers, drips, tropical, bubbles, starfall, stardust; lit ink; Aurora's
    curtains; Prismatic's saturated rainbow outline plus `shimmer`. Lantern King's
    crown has its own seat on the Angler's head (its box top is the lure stalk's
    arch); the gold on its back is the skin's painted spines. Ribbons shorten above
    top speed (Undertow's swirls zig-zagged on a dash). **SkinFx frames off the
    fish's root:** the body Model has no PrimaryPart, so its pivot never turned.
  - **Boost trails twice as present:** particles 1.3–2.2× a skin's, ribbons 1.4×
    wider, 20% → 120% rate from the threshold to a dash; Fire Wake blended
    yellow → orange-red (additive orange read grey-blue over blue water when thin);
    Storm draws two lightning arcs; Ink Cloud glows violet-indigo.
  - **Phone text:** the Index names this device's buttons (`byDevice`); the Coral
    Garden row and the Tide Pass subtitle are shorter on phones; the stall button
    keeps TextScaled with non-breaking spaces (turning TextWrapped off turns
    TextScaled off, HB1). Leaving a den, the wash waits for the doorway's lantern
    lights and settles 0.6 s.
- **The 2026-10-18 report's decisions (PC report `2026-10-18-pc.md`; Connor's standing
  "go with all of your recs"; built):**
  - **Leaving a den takes ~4.1 s** (was 1.3), the price of a lit plaza (PC fixes
    9dcba3f, 76b770a): the camera turns behind the fish on a teleport (it kept the
    den's heading, ~110° off), and the wash holds 3.4 s coming out on the plaza,
    since Roblox first draws newly arrived Terrain at low detail (a dark blue
    "wall" over the doorway's arch for 1.5–3.6 s) and can't report when it's done.
  - **Effect skins shed only their effects** (`Cosmetics` `aura` returns for a
    shade with `fx`): 13 of them still shed the old sparkle glints on top.
  - **Lantern King** wears no effect crown (its painted gold spines are its crown;
    the two read as two crowns): embers and glints. **Aurora** is two softer
    curtains (brightness 1.15, more transparent; three at 1.6 read loud).
  - **Trails:** your own fish's trail never reaches your camera (each emitter's and
    ribbon's lifetime is cut to `BEHIND` 0.75 of the time the following camera
    takes to reach where it was shed; Fire Wake's flames filled the screen from
    behind). Fire Wake is orange (255, 120, 30) → red (210, 44, 14) with a brief
    yellow core and no pinkish-grey end; Ink Cloud lighter and glowing more;
    Stardust bigger.
  - **Vents:** a thinner, lighter warm murk (density 0.68, haze (112, 62, 44)) so
    the far floor's silhouette reads, a near-neutral tint (230, 222, 218) and a
    less red fissure light (255, 138, 72) (Lilac read magenta-pink), and a heat haze
    big enough to see (9 → 22 studs, 0.74). The plume seen straight down is end-on;
    the WHALE FALL marker carries it (left as is).
  - **The stand-in** for a skin not loaded is tinted 88% toward the shade (it looked
    like the plain fish). **Unlock notes** mark each condition met with ✓ and list
    what's left (`MenuController` `unlockNote`, FISH and the Index's goal).
- **The 2026-10-18 owner batch (owner: "level up a lot slower", "a whale fall should
  never fall right outside the kelp shallows", catch skins "100 eaten", "Tutorial ... a
  full cycle", den "bigger", props "MUCH much better", "change the actual entrance to
  our den", den shop "pics", "Sharks frenzy ... faster ... magnet ... highlight",
  "perks ... and drawbacks", "how is a player supposed to use a kelp wrap", "animation
  when they drop the haul off", "gold sheen", "X ray ... actual skeleton", "Wardrobe ui
  needs to be stepped up entirely", "skins should also exactly match" the preview,
  "Trail ... right in your face", "the fish isnt taking up more of the screen",
  "Sunken ruins need an extreme update", "Megalodon ... seen from further out", "Speed
  ... scales far too high", "so much more fish", "Visibility needs to be turned up ...
  Think Subnautica", "we dont want to see the map barrier"; then "Go with all of your
  recs, roll it into one"; built):**
  - **Slower levelling** (superseded the next day by "Pace (2026-10-19b)" below; what
    stays is the one choke point, `HuntService.addHaul(kind)`: "food" (× rate, then ×2 Mass and
    Frenzy: prey, forage, slick chunks, bait, predator and boss loot), "rated"
    (whale share, kill and pod gains), "sized" (treasure, admin: no rate), "raw"
    (chum, Second Chance). Pay that comes from the Haul uses its `worth` before the
    rate (`Events.banked` 4th argument: Pass XP, map chance; bank coral 7 × √worth),
    so a dive pays as before). The creator owns ×2 Mass, so the owner levels faster.
  - **Pace (2026-10-19b; its levels per Haul, food table and hours were superseded on
    2026-10-20, see "The 2026-10-20 owner batch"; owner, after playing the 22 h curve: "No reason that a full
    haul for nibbler should start at .2kg and only go up by .01 a level ... The first
    fish you eat are worth far too little food right now. A full haul should take
    15-20 fish first time and hold more each time allowing them to level up faster
    and faster while taking more risk with a larger haul"):** `Config/Tuning`
    `growth` `food` (kg of food a full Haul holds, log-interpolated by banked level:
    4.4 at LV 1, 5.2 at 8, 15 at 15, 85 at 25, 230 at 35, 1,150 at 45, 1,500 at 55,
    2,400 at 70, 4,000 at 85, 5,000 at 100) and `cap` (levels a full Haul banks: 7 up
    to LV 3 for the tutorial's 1 → 8, then 1 at LV 8 rising to 2 at LV 100). The
    growth per kg of food is derived (`Size.haulRate` = `haulCap` ÷ `haulFood`). **The
    Haul shows as food:** the Haul card, pops, the tutorial's count and every toast
    (bait, kills, pod, boss, treasure, Second Chance, Double Haul, the fisherman)
    show `Size.haulShown` (growth ÷ rate; `HuntService.shown(player, kg)` on the
    server), so a 0.4 kg Garibaldi reads "+0.4 kg" and a full Haul "5.2 kg" at LV 8,
    "85 kg" at LV 25, "1.5 t" at LV 55; the server still stores growth (`liveMass`,
    chum, kills, banking unchanged). Fish a full Haul (sim, prey only): the
    tutorial 16, LV 8–15 25, 15–25 25, 25–40 53, 40–55 52 (the Open Blue's tuna are
    big), 55–70 99, 70–85 166, 85–100 206; dives 1.4 → 8.7 min; hours to LV
    15/25/40/55/70/85/100: 10 min/23 min/44 min/1.2/2.0/3.2/4.1 (was 22 h). **The cap
    is real** (`HuntService` `addHaul`): everyday food stops at a full Haul (MAX SIZE
    = full; eating still heals and counts catches, DNA and coral). Rewards go on top:
    `sized` (boss, treasure, admin) and `restore` (Second Chance); Double Haul banks
    directly. Bonus meals are shares of the eater's full Haul (`HuntService.hauls`):
    bait `baitHaul` ½, whale `chunkHaul` ⅙ with at most `hauls` 2 a whale, slick
    ¹⁄₃₀, predator `loot.hauls` 0.3/0.6, a kill ½ their Haul + `playerBaseHauls` ¼ of
    their full Haul, boss `hauls` 1.5 + `haulsShare` × share, treasure 1/1.5/2.5.
    **Food below you counts for less:** past the top level of the biome a fish is in
    (`Config/Biomes` `maxLevel`), prey and filler food go on at ×(1 − 0.1 per level
    over), floor ×0.2 (`growth.overLevel`, `Size.overLevel`, by `Biomes.at` of the
    fish; worth unchanged); the Haul card says "Too easy here: deeper water feeds
    you better" (a fish staying in the Open Blue reaches LV 100 in 4.7 h, following
    the biomes 4.1). `tools/tests/run_progress_sim.sh` checks the tutorial's Haul
    takes 15–25 fish, each band's fish a Haul near `FISH` and never fewer than the
    band before, levels a bank near `cap`, and no biome-stayer fast lane;
    `MODE=design` turns `FISH`/`LEVELS` targets into `food`/`cap` points; rerun after
    `growth`, `Config/Prey`, `Config/Forage`, biome levels or size/speed changes.
    Double Haul `minFull` 0.75, tiers 1.2/63 kg of growth (Small to ~LV 22, Big to
    ~LV 58), ad 1.2 kg; Second Chance `minShare` ½ a full Haul. ×2 Mass and Frenzy
    fill the Haul twice as fast. **Treasure maps from prey** are capped at
    `drops.preyPerHour` 7 a player (an allowance holding `preyBurst` 2;
    `TreasureService`). `haulLengthCap` is retired.
  - **The smallest prey are longer (owner, 2026-10-19: "The smallest fish like minnows
    etc need to be slightly larger. They're a hard target and they're small. I think
    making them larger will make the scene fuller"):** `Config/Prey` `look` × the
    length from mass (Minnow 1.25, Sardine 1.15, Ghost Shrimp and Hatchetfish 1.2,
    Lanternfish 1.12, Garibaldi and Opaleye 1.08; `Shared/Schools` `length` and the eat
    `radius` follow, so they're drawn, hit and swallowed that long), their kg and their
    schools' spread unchanged, so schools read fuller and nothing moved. Kept under
    the swallow ratio of the level that hunts them: a LV 1 fish still eats every
    normal Minnow, the LV 5 Kelp hunter keeps its 5 species (run_catch_sim), the
    tutorial's Haul is 23 fish (run_progress_sim).
  - **Whale Fall** never in the Kelp Shallows nor within 520 of the hub (`Config/Chum`
    `whale.never`, `minRadius`); one fish takes at most 2 full Hauls from
    one whale (since 2026-10-19; was 4 levels' worth) ("You're full of whale!", `WhaleFull` attribute; its chunks stay for
    others).
  - **Catch tracks 100 each** (superseded the same day by the account-wide skin goals
    and per-player rare streams; see "The Catch Logbook and skin goals").
  - **Blood Sense frenzy** (server: `AbilityService` `Sensing`, `Perks.sense`): 7 s
    of ×1.25 top speed (SpeedService allows it), ×2 swallow reach and suction (client
    and server), and amber Highlights on the nearest edible prey within 120 after the
    red players and predators (28 at most; `SchoolController.edibleNear`).
  - **Speed curve flattened** (`Size.topSpeed`: the old curve to `swim.speedKnee`
    raw 6, ~LV 33, then easing to `speedCap` 56): LV 100 cruise Nibbler ~49, 'Cuda
    ~62, Puffer ~39 (were 83/104/67); crossing the 3,000-stud map ~60 s (Nibbler) /
    ~50 s ('Cuda) cruising, ~33 s for a maxed 'Cuda chaining Torpedo; Strong Fins
    +3% a level (was 4%); Reef Shark 44. The Megalodon's charge (75) now outruns
    every fish.
  - **Camera:** `growFraming` 1.0 and `growFov` 6 (a grown fish keeps its share of
    the screen; the bank's growth sequence shows the growth).
  - **Clearer, per-biome water** (`OceanController` depth grades for light and
    density + `Config/Biomes` `water` per biome for haze, tint and offsets, blended
    over ~90 studs): Kelp green-teal, Wreck grey-green, Reef turquoise, Open Blue clear
    deep blue, Ruins teal-cyan, Vents warm murk, Trench creepy teal; shelf density
    ~0.50–0.57 (was 0.64–0.68), deep ~0.55–0.62 (was 0.80–0.88), Trench dark 0.66.
    **The map's edge never shows:** the water thickens to 0.72 over the last 380
    studs inside the barrier, and the Horizon walls take the camera's haze colour every
    frame. Megalodon `sight` 500 / 290, fight light 240, dread 680.
  - **A fuller ocean:** 406 schools (was 113, ~4,100 fish), new zone shapes
    (`spread`, `round` bait balls, `pathRadius`, `trench`); `SchoolController` builds
    a school only near the camera (3 ms a frame), each fish drawn to 180 + 55 ×
    length (≤ 520) and faded at the edge, ranges easing to 0.7× on slow devices
    (`Workspace.Prey` attributes `Detail`/`Built`/`Drawn`; `tools/tests/run_density.sh`).
    **Ambient life** (`AmbientLifeController`, `Config/Ambient`, client-only, seeded
    per 96-stud cell on the shared clock): jellyfish, rays, crabs, turtles, reef-fish
    clouds round coral, far whales and mantas in the Open Blue; all fade near a boss.
    **Prey batch 2** (owner approved the concepts 2026-10-18; `prey2_fbx`, sha256
    cc9d695c…, rigged FBX with colour maps only, highest classifier 0.025): Garibaldi
    (Kelp 0.4 kg), WreckCod (1.5), Parrotfish (Reef 4), YellowfinTuna (Open Blue 35,
    fast tight schools), MahiMahi (22), Lionfish (Ruins 10), GhostShrimp (Vents and
    low in the kelp, 0.2, swarms), Lanternfish (Trench 0.5). They took schools over
    from Minnow, Sardine and Wrasse, so the sea stays ~4,100 fish (446 schools); every
    biome has 5+ species a fish of its level can eat. `Config/Prey` entries carry
    `biome` (the Catch Log's), and `venom` makes the **Lionfish sting** when swallowed
    (`HuntService`: 6% of max health, less for a fish 2.5× its length, never below
    5% health, never in the hub or under spawn protection, toast STUNG · venomous
    spines). Zones can set `vents = true` (`Schools.build`). `SchoolController`
    `GLOWS` gives Lanternfish spots and Ghost Shrimp tips as Neon parts plus 3 faint
    lights near the camera; `SHAPES` are the part-built looks until imported. Tuna
    and Mahi-mahi drop shells (`Config/Shells` `preyDrops`). A prey model sheet is
    made from the concept crop over the style strip (`tools/props/prey_refs.py`).
    **Prey sheet B and den prop boards A/B** (`tools/tripo_jobs_prey_concepts2.json`,
    `tripo_jobs_den_concepts.json`; Butterflyfish, Triggerfish, Swordfish, Ocean
    Sunfish, Coelacanth, Vent Eelpout, Gulper Eel, Oarfish; Driftwood Table, Kelp
    Bed, Pearl Pedestal, Bubble Column, Sponge Sofa, Shipwreck Bookshelf, Jellyfish
    Lamp, Sea Glass Lantern, Coral Lamp, Banner, Conch Gramophone, Treasure Chart)
    were approved by the owner on 2026-10-19 ("Approve all concepts").
    **Prey batch 3** (sheet B; `prey3_fbx`, sha256 7f4731cf…, colour maps only,
    highest classifier 0.094): Butterflyfish (Reef 1.2 kg), Triggerfish (Wrecks 2.2),
    Swordfish (Open Blue 55, fast), OceanSunfish (Open Blue 80, slow), Coelacanth
    (Ruins 14), VentEelpout (Vents 4), GulperEel (Trench 4), Oarfish (Trench 120, 3 of
    them). They took schools from the shelf's Minnows, Wrasse, Sardines, Snappers and
    Groupers (~4,000 fish, 482 schools), so the Vents and Trench have natives; every
    biome keeps 5+ species a fish of its level can eat. `calm` prey (the Sunfish and
    Oarfish) never chase a smaller fish (AggroService). Big ones drop shells.
    Pipeline: `prey_refs.py --batch B` mirrors crops to face left and can straighten a
    curled tail in the reference (Nano Banana copies a curl whatever the prompt
    says); `rig_fish.py --head F` sets the stiff head's share (the Oarfish 0.14);
    `--flip` for a bill or a round head (Swordfish, Sunfish: the deep-end guess
    fails); SchoolController waves however many `SpineN` bones a rig has.
    **Moderation lesson:** orange-red fins over a pale silver body (the Oarfish)
    scored 0.99 with no skin tone in it: `safe_colors.py --crimson` (true red) took
    it to 0.036, and `--vivid` keeps a yellow fish yellow. Schools lift
    `CLEAR_STUDS` 2 (a low fish 5+ studs long needs `pathRadius` ~14+ or it pitches
    into rock). Changing an early prey's school count reshuffles the whole layout
    and moved pace ±10%: rerun `run_progress_sim.sh` and check the Kelp hunter's 5
    species in `run_catch_sim.sh`.
    **Den props batch 2** (boards `assets/concepts/DenPropsA.jpg`/`B.jpg`;
    `den_props2_glb`, sha256 a8241c01…, highest classifier 0.115): the 8 starter
    pieces kept their ids and became Tripo models at real scale (Driftwood Table 14 ×
    7.2 × 7.1, Kelp Bed 12.4 × 6.2 × 16 headboard at the back, Pearl Pedestal, Bubble
    Column, Jellyfish Lamp on the ceiling, Sea Glass Lantern 1.5 × 5 × 3.2 on a
    wall, Coral Lamp, Banner); new: Sponge Sofa 750, Shipwreck Bookshelf 800, Conch
    Gramophone 1,100, Treasure Chart 450 (standalone, no set). `DenItems` `STAND_INS`
    are part-built versions of the same designs until imported. Lamps light in their
    own `lamp` colour (no longer the den's glow); the Banner's cloth follows the glow
    through SurfaceAppearance Overlay (alpha 0.2 on the cloth in its colour map,
    `DenItems` colours the MeshPart, `organize_imports` sets Overlay since a game
    script can't). `front = 180` keeps width and depth. Pipeline:
    `den_props2_refs.py` → sheets → models → `strip_normals` → `den_props2_prep.py
    prep` (squares up, recolours, flecks) → `safe_colors` → `den_props2_prep.py
    cloth`. A smooth carved-stone colour map scored 0.62 until it got flecks. **Prey
    sheet C** (Opaleye, Kelp Bass, Blue Tang, Lingcod, Rattail, Viperfish,
    Hatchetfish, Humphead Wrasse; `tools/tripo_jobs_prey_concepts3.json`) was approved
    by the owner on 2026-10-19 after a Tripo top-up. **Prey batch 4** (`prey4_fbx`,
    sha256 4197ef6c…, colour maps only, highest classifier 0.002): Opaleye (Kelp 0.4
    kg), KelpBass (Kelp 0.8), BlueTang (Reef 1.5), Lingcod (Wrecks 3.2, lone), Rattail
    (Vents 6), Viperfish (Trench 1.8) and Hatchetfish (Trench 0.25), both with
    `GLOWS` (spots measured on the model's own texture dots through its UVs), and
    HumpheadWrasse (Ruins 25, `calm`, drops shells). They took schools from the
    Kelp's Minnows and Sardines, the Reef's and Ruins' Wrasse, lone Groupers and the
    deep Snappers: ~3,950 fish in 492 schools; the LV 5 Kelp hunter keeps 5 species
    (the Opaleye replaced the Wrasse). Pace held: LV 15/25/40/55/70/85/100 at
    0.58/1.5/4.0/6.6/10.5/15.4/21.4 h; Crystal ~111 min a hunter. 31 prey species in
    all. `prey_refs.py --batch C --fix` touches up model sheets (mouth linings,
    spots, keel dots, gaze). **Moderation lesson:** Tripo can paint a hidden mouth's
    inside plum even when the sheet's mouth is closed: check each new prey's colour
    map for plum (red well over green, blue over green) and use `safe_colors.py
    --plum`. Tripo balance 425 (2026-10-19).
  - **Tutorial: the full loop, nine steps** (`Config/Tutorial`, `TutorialService`
    rewritten, `tutorial.v`): leave the hub, eat 5 (10 until 2026-10-20), 5 shells, fill the Haul
    (`HAUL_LEVELS` 7 levels' worth), bank, spin the wheel (a spin granted), ROLL
    (shells topped to 50), use a Kelp Wrap (one granted), open the INDEX (I key);
    new `Events.spun/rolled/usedItem`, `TutorialSaw`.
  - **Item bar** (`ItemBarController`): a slot per carried item left of the Haul card
    (photo, count, key, status, cooldown); keys 1–4 (H still wraps), LB, tap; all
    through `UseItem`.
  - **Bank growth sequence** (`BankController`, `FishAnimator.showGrowth`): side-on
    camera, the fish dips to its pre-dive size and pops to the new one, ring and
    sparkles, a card "1.8 ft → 2.3 ft", levels and coral; ~3.7 s, skippable
    (`Ui.releaseStage`).
  - **Perks and drawbacks** per fish (`Config/Species` `perks`/`drawbacks`) in FISH
    and the Index. **Daily panel** redrawn (streak flame, photo tiles, CLAIM on today,
    gifts with a progress bar).
  - **Wardrobe** (`src/client/Wardrobe.luau`): a big try-on stage (hover/D-pad tries
    on), a photo card grid with tier, status, tags and a how-to-get on locked cards,
    filters, counts, a details panel (how to get, effects in words, "Comes with a
    trail:" for ribbon kinds, light in the dark) and WEAR / TAKE OFF / LOCKED with a
    link; LB/RB tabs on a pad. `FishPreview` gained `dress` (no rebuild) and
    `setTurn("sway"|"spin"|"still")`.
  - **Skins v13** (`shade_patch_v13`, sha256 947f0900…, 6 GLBs, no normal maps,
    highest classifier 0.03): Golden glossier with painted reflection bands plus a
    `sheen` effect (a warm band running head to tail every 2.5 s with a riding light
    and sparks; gold particles use Roblox's white sparkle, the cyan `fx` images had
    turned them olive); X-Ray (the 'Cuda's) an anatomical skeleton. **Previews match
    the game** (`PreviewFx`: glow ×1.6, the skin's light as a backdrop, 2D effect
    sparkles, Golden's sweep). **Ribbons** sit on the tail fin's line (Prism,
    Prismatic, Comet, Riptide) and, on your own fish, are cut short of the camera and
    fade when seen end-on.
  - **Skins v14: Silver** (`shade_patch_v14`, sha256 e718efcc…, 6 GLBs, 18 images, no
    normal maps, highest classifier 0.005): `CatchSilver` (Common), the Silver catch
    goal's skin, every fish's. Golden's polish in silver (`catch_silver`): reflection
    bands over `mirror_scales` (overlapping scales each a flat mirror tilted its own
    way, so the bands step and a few scales flash), steel-blue creases, its pattern
    engraved, semi-gloss 0.42, metal 0.25, a faint glow; cool and mid-toned (Cr − Cb
    ~−18, mean 0.54–0.63). `Config/Shades` FX gives it `sheen` in silver (SkinFx's
    `sheen` takes the shade's colours); an FX `light` (`Shade.fxLight`) sets the
    preview's flare colour (nil = Golden's warm white). A new `sheen` skin gets an FX
    `light` and, if it isn't gold, a Wardrobe `SKIN_EFFECT_WORDS` entry. Bounties now
    Silver10, Golden5, Glowing2 (Golden8 and Glowing3 took ~40 / ~75 min of hunting
    at the new rates); Silver is 8 Pass XP and 0.2 leaderboard points, ×2 in the
    Blood and Prism Tides.
  - **Dens:** rooms 1.22× (deck ~1.5×), capacities 24/48/80/125/180; things at real
    scale (floor ×1.9, rugs 18–24 studs, wall lanterns small) and clusters built from
    pieces (`cluster`, `DenItems.piece`: Anemone Garden, Tube Sponges, Shell Pile, …);
    **doorway styles** (`Config/Dens` `doors`: Stone, Kelp Curtain, Coral Arch, Brass
    Porthole, Whalebone Gate, Crystal Grotto, Abyssal Gate, Megalodon Jaws; coral and
    den level or achievements; `data.den.door`/`doors`, `DenDoor` request); a **YOUR
    DEN** ring, light column and tag only you see; den shop and tray **photos**
    (`ItemPhoto`); the plaza exit hold 5 s. Weakest props for a Tripo batch: Driftwood
    Table, Pearl Pedestal, Jellyfish Lamp, Banner, Sea Glass Lantern, Bubble Column,
    Coral Lamp, Kelp Bed (concept boards first).
  - **The Sunken Ruins rebuilt** (`src/server/Ruins.luau`, `Config/Ruins`, called at
    the end of `WorldService.buildBiomes`; the old `ruin()` temples, plinths and
    temple ring are gone from WorldService and `Shelf.luau`): a drowned city at 2°,
    r 1,230 between the drop-off's sand chutes (a three-tier great temple with 16
    fluted Ionic columns, fallen pediment, inner chamber, the god's broken legs; a
    toppled colossal head and a giant hand; a paved avenue of columns, sea-dragon
    guardians and glowing obelisks from a triple-arch gateway; a theatre; a sunken
    courtyard pit 18 deep; a back quarter of houses and steles) plus 15 outlying
    ruins and 34 boulders, overgrown, with faint cyan rune glyphs (not Latin letters,
    no "+"). ~3,340 parts (~2,840 with the props), 12–16 lights; stone solid and in
    `World.Biomes.Ruins` (so `Ground` covers it), decor non-colliding; big stones the
    toon Marble/Slate, small pieces SmoothPlastic. Six Tripo hero props
    (`ruins_glb`: RuinHead, RuinHand, RuinGuardian, RuinUrn, RuinCapital, RuinStele;
    sha256 b28a74fe…, normals stripped, safe_colors, highest classifier 0.056) with
    part-built stand-ins; `GLB_FRONT` in Ruins.luau for facing. Removing the old
    ruins shifted the shared random sequence after it (Vents rubble, Trench glow,
    plankton mats, seeps, light shafts moved). The map chart was regenerated
    (`assets/textures/map_chart.png`, needs a re-upload). Preview:
    `bash tools/preview/run_ruins.sh`.
- **The 2026-10-19 report's decisions (PC report `2026-10-19-pc.md`; Connor's standing
  "go with all of your recs"; built on `claude/world`):**
  - **Pacing:** see "Pace (2026-10-19b)" below (the Haul cap in levels, the rate by
    level, rewards past the cap, bonus meals as shares of a full Haul).
  - **Ruins head:** `RuinHead`'s GLB is an upright bust (face +X, crown +Y, neck −Y;
    box = depth, height, width); it had lain inside a pediment half, which hid its
    face. It lies on the back of its skull at T0 (−46, −121), face 40° up gazing down
    the way, crown across it (`statueHead(gaze, crown)` → `CFrame.lookAt`), `HEAD_SINK`
    0.52; `HEAD_TURN` settles its facing in one place. Outlying ruins that can't find
    room retry looser (`LOOSER`: 0.85× then 0.7× spacing), and the `[Ruins]` line
    names hero props as models and stand-ins and any ruin left out. The preview's hero
    count (47) differs from the game's (~40–42): its stand-in `Random` isn't Roblox's.
    Close-ups: `PROPS=1 VIEWS=headway,headtop,headgaze,hand,capital bash
    tools/preview/run_ruins.sh` (reads `assets/glb/props`).
  - **Forced tides** last one tide from the moment they're set (opening boost and all)
    and TideService clears `TideOverride` when one ends (it lapsed at 10 min while
    still named). **Prism** rate 0.08 (was 0.10) and no Silver boost in the Prism Tide
    (the sim: ~1.8 a tide).
  - **Water:** the Open Blue clear deep blue (biome water density −0.08, exposure
    +0.2; it read dark navy at 0.58 / −0.39) and the Ruins clearer (−0.05 / +0.14);
    the map-edge haze ramp 240 studs (was 380: the Megalodon fights 1,000–1,440 out),
    and a boss's fight light thins the water 20% (was 12%).
  - **Stand-in** (a skin still loading): the fish flat in the shade's `back` colour,
    texture held aside (`Cosmetics` `waiting`); a multiplied tint can only darken
    (an orange Nibbler read maroon under Lilac). A shade not imported still tints.
  - **Silver:** **skins v14.1** (`shade_patch_v14_1`, sha256 0b518607…, highest
    classifier 0.021): the Angler's Silver only, a step darker with deeper bands and
    a lure-only glow map (`catch_silver` colours from `SILVER`, a fish's own from
    `SILVER_FISH`); import after v14. **Silver prey** (`SchoolController`): a
    SmoothPlastic whiter cool silver (Foil, a metal, showed the dark water), its own
    light over its back (`SilverLight`, range length × 1.8) and a staggered mirror
    flash every 1.25–2 s (`silverFlash`: colour to white, light 1.5 → 6, Neon white at
    the peak past `SILVER_NEAR` 24 studs, the glint swelling). A light inside a body
    lights none of its own skin: put a body's own light outside it.
  - **UI:** stage holds are per holder (`Ui.holdStage(s, owner?)`,
    `Ui.releaseStage(owner?)`); every centre banner goes through
    `Ui.stageBanner(owner, seconds, fade, show)` (waits its turn, holds the stage,
    steps aside for the bank sequence and comes back); `Ui.centreBannerUp()` is true
    while anything holds the stage. Not on it yet: BiomeController's biome title,
    TideController (waits up to 8 s), GardenController's WELCOME BACK. The full map is
    its own ScreenGui `MapWindow` at DisplayOrder 10 (the HUD drew over its title); M
    does nothing in Build mode. On phones the tutorial card's distance line sits under
    its header (`layoutCard`, 174 tall) and the idle stick ring rests at (100, H−74);
    a step done within 1 s of showing (or never shown) shows DONE for 2.5 s with a
    line saying what happened (`recapNote`). Daily gift tiles list one reward a line.
  - **Trails:** Ink Cloud brighter and thicker; Storm's arcs wider, each with a glow.
  - Left as is: Lilac reads warm in the Vents (warm light on violet); the school
    lift takes ~1 s at server start (446 schools).
- **The 2026-10-19 round-2 report's decisions (PC report `2026-10-19-pc-2.md`, PC
  fixes 42bd411 and 3e91542 merged into `claude/world`):**
  - **DP3:** a ceiling-only thing (the Jellyfish Lamp) aimed at the floor or a wall
    rises to the vault above (`BuildController` `findSpot`; the editor view never
    looks up).
  - **PR7, kept:** a fish's sway is its length but never more studs than its speed
    (`Schools.fishFrame`; the Ocean Sunfish and Oarfish slid tail first a third of
    the time). `progress_sim.luau`'s inlined path follows it.
  - **The slower Kelp fill** (155 s at LV 10 after batch 4) is moot: the Haul is food
    since "Pace (2026-10-19b)".
  - **The Sunfish bends less** (fewer bones, the same wave strength): left as is; a
    sunfish barely bends.
  - **The Banner on Gold and Violet:** the cloth is the glow made deeper and richer
    (`DenItems` `clothOf`: saturation ×1.15 + 0.1, value ×0.62; Gold (158, 117, 26),
    Violet (96, 39, 158)), so the gold emblem and trim stand out on every glow and
    Violet no longer reads lilac; the part-built stand-in matches.
  - Still owed: SP2 (needs two players in a pod).
- **The 2026-10-19 world-and-life batch (owner: the cliff "just bulbous spheres off
  the edge ... should have coral etc on it"; turtles and rays "essentially just circles
  put together"; crabs "need more detail like the turtles ... should be edible too";
  the start screen "rolling shots of different fish around the different biomes"; "the
  vents part of the map needs more substance"; the Megalodon's "mouth doesn't move ...
  movements are very stiff ... If he misses the player he just slowly turns around ...
  Same with other predator fish. Needs to be fun to fight them not robotic"; built):**
  - **The reef wall** (`Shelf.luau` `dropOff`, `src/server/Cliff.luau`): the drop-off
    is strata bands of flattened pebble slabs with grooves, 44 spurs, an undercut
    sandstone lip, crevices, 12 caves, fluted columns, 48 ledges, a crest of rounded
    rock with 70 reef heads, talus and sand fans; its own Random (`CLIFF_SEED` 19) with
    the shared sequence's old draws burned, so no other op moved; nothing more than
    `REACH` 25 studs out of the face (`FACE` 890). ~4,500 of the world's ~9,400 ops.
    `Cliff.build` (WorldService, after the Vents) dresses it by raycast: reef patches
    on the lip and heads, growth hanging from the undercuts, fans, plates and whips on
    the face, gardens on band tops and ledges, sparse cool growth matched to the deep
    biome below, barnacles and sponges in the wreck bay (135–225°); ~2,450 instances
    with `cliff_glb` imported (PlateCoral, BarrelSponge, SeaWhips, LaceFan; sha256
    51e843ee…, highest classifier 0.023), ~3,500 before. "Cliff" is in `Ground`'s
    solids and `ChumService`'s dressing. Preview: `bash tools/preview/run_cliff.sh`.
    Known nit: from far off the bands read mostly horizontal.
  - **The Vents field** (`src/server/VentsPlan.luau` lays it out, its own Random, every
    solid top under the lowest school loop over it; `Shelf.luau` builds it last so it
    sees all the rock; `src/server/Vents.luau` dresses it): **the Forge**, a ~175-stud
    vent mountain with a broken rim, a crater lava lake under a glare, glowing runnels
    to lava pools and an ash column, plus a shoulder cone; black-smoker complexes,
    columnar hex basalt causeways and outcrops (stepping up away from the hub), rimstone
    mineral terraces, a brine pool, three tube-worm forests (mid-grey tubes, crimson
    tufts), mussel beds, pillow lava and crust between the basins, the old chimneys
    dressed to match. ~2,000–2,800 parts (`PARTS_CAP` 2,900), 13–14 lights, ~920 ops;
    boulders cleared off landmarks. Preview: `bash tools/preview/run_vents.sh`.
  - **Sea life** (`ambient_fbx`, sha256 58e7aef4…, highest classifier 0.006): Turtle,
    Manta, Stingray (blue-spotted), Humpback and Crab rigged by
    `tools/blender/rig_ambient.py` into `ReplicatedStorage.AmbientModels`;
    `src/client/AmbientBody.luau` draws the model or a part-built stand-in (faceted
    turtle, WedgePart manta, spotted disc, jointed crab) and `Shared/AmbientRigs` poses
    them (lagging manta wingtips, rippling stingray edges that settle on the sand with
    a puff, turtle strokes and glides, fluke strokes, banking); joint work LOD-limited
    (380 a frame). `Workspace.AmbientLife` `PoseMs`/`Joints`.
  - **Edible crabs** are filler food now (out of ambient life, so every crab is edible):
    `Config/Forage` six kinds (Shore 0.1 kg Kelp, Rock 0.7 Wrecks, Decorator 1.5 Reef,
    Stone 8 Ruins, Yeti 5 Vents painted grey, King 12 Trench; edible from LV
    1/8/16/34/27/57), `Shared/Crabs` a sideways dash-and-pause round each spot on the
    shared clock, ForageService places them on open floor beside rock and allows the
    scuttle in its eat check; a crab too big for you squares up, claws raised.
    `Workspace.Forage.Crabs` `Built`/`CrabMs`. Pace unchanged.
  - **The start screen's attract mode** (`Config/Start`, `Shared/StartShots`,
    `StartService`, `StartController`): rolling shots of real schools (kelp Garibaldi,
    reef Parrotfish, a wreck's Triggerfish, Open Blue tuna, Ruins fish before the
    temple, Vent Eelpouts, Trench Lanternfish, a rising Ocean Sunfish), framed on the
    school's own fish, a documentary lower third ("Yellowfin Tuna · Open Blue · LV
    35–55"), letterbox, murk-dip or bubble cuts every ~6.5 s, never the same biome
    twice; the server prestreams each shot (validated, rate-limited, only on the start
    screen); paths checked by ray in the background. Gameplay UI, tags and markers
    stay hidden; ambience follows the shot. Re-check the paths after any Terrain
    change: `DUMP_ONLY=1 LUAU=<luau> bash tools/preview/run_start.sh <dir>` (exit 1 if
    a shot has no clear plan). **No see-through cuts (owner, 2026-10-20: "it shows
    through the map for a few seconds until it loads, thats very unacceptable"):**
    `RequestStreamAroundAsync` only sends a spot's min radius once (a prefetch, GC'd
    after ~5 s) and Roblox meshes Terrain only round the camera, so the server now puts
    a replication focus at each shot (`Player:AddReplicationFocus` on a part in
    `Workspace.StartFoci`; two at most, the shot on screen and the next; released on
    `StartDone`) and answers with the parts round the school (`StartShots.partsNear`),
    and every cut is held under an opaque murk with the camera already at the new spot
    until those parts are 90% in, the downloads queue ≤ 10 and `mesh` 2.6 s have
    passed (`holdMax` 6 s, logged as `[StartShots] ... still loading`); the first shot
    is held the same way under the backdrop. The old ViewportFrame intro scene is gone
    (owner): a plain water backdrop (shafts, snow, bubbles) shows until a shot is in.
  - **Predators that hunt like predators:** a Jaw bone (`rig_fish.py --jaw`) on the
    Megalodon (plus FinL/FinR), Reef Shark and 'Cuda (`boss_fbx` 3477e8c2…,
    `species_fbx` a13009ba…, the same screened colour maps); `SwimWave` takes bone rest
    frames from the mesh part (the FBX Root's half turn had inverted every pitch, so a
    jaw would have opened upward). `PredatorController`: jaw slightly open cruising,
    gaping through a tell, snapping shut with a head shake, chomping in the frenzy;
    burst-and-glide tail beats; a C-bend into turns, bank, pitch, fins; the squid's
    arms close on each mantle pulse. Hunting: a miss comes round in ~2 s (the
    Megalodon 3–5 s after any pass, 3.2 rad/s turns) by banked loops, `wheelOut` from
    a pivot trap, circling, rising from below, feints; the Megalodon's bite commits
    its head 40% into the tell (`BITE_COMMIT`) and reaches 1.6× ahead, 0.7× aside, so
    a sideways dodge escapes; no charge at a surface-hugger it can't reach; `sated`
    pauses after a landed bite keep still-fish hit rates where they were. **The
    Megalodon is 175 studs** (every reach ×1.35, sight 560/330, fight light 300, dread
    760). Sims: `run_predators.sh` (predators and bosses). The players' own fish bend
    into turns too (`FishAnimator`: the bend is the yaw rate's opposite).
- **The 2026-10-20 owner batch (owner: "make a community logo in the game's style",
  "the loading screen back to the hub from the den ends before the hub finishes
  loading", reef "little groups of fish ... that are just spheres", "tutorial needs to
  be more prominent its a bit smal", "biting also needs a sound queue", "the growth is
  linear. Less than one to one level per load is far too low", turtles, stingrays and
  mantas "need to have some kind of function ... a buff where they swim with you", "den
  exit needs to be more pronounced like the entrance too", the Wardrobe "listed from
  common ascending down to mythic ... hidden until unlocked", "nebula should be moving
  across the shark ... a few skins that actually have movement similar to ... the
  chowder skin style in hatch and snatch", the Vents' "spheres that are all over the
  place that were clearly placeholders", "so much more prey fish volume ... Too
  sparce", "a lvl 100 fish can absolutely decimate an ecosystem too so the fish need a
  high respawn rate"; built on `claude/world`; the PC session tests and publishes it):**
  - **Linear growth:** every full Haul banks `growth.cap` 5 levels (the tutorial's
    `HAUL_LEVELS` 5: LV 1 → 6), and the drawn length is a straight line in level
    (`Size.length`/`Size.raw` from `size.lengthTop` 16.9 at LV 100, soft cap from 16.6
    to `lengthCap` 17): ~+0.15 studs (0.14 ft) a level, ~0.7 ft a load. Raw length (the
    ratios, speed, swallowing) is unchanged. `growth.food` was refitted twice (to 5
    levels a load, then to the fuller sea): LV 1 2.1 kg, 8 6.9, 15 41.5, 25 180, 40
    1,130, 55 5,600, 70 13,000, 100 17,500. Sim: LV 100 in ~2.1 h following the
    biomes, 4.4 h staying in the Open Blue; fish a full Haul 22 / 22 / 50 / 109 / 138 /
    281 / 331 / 435 by band. Double Haul tiers 5.8 / 230 kg of growth, ad 5.8.
  - **A fuller sea** (`Config/Prey` `fill`, applied by `Schools.build`; the entries keep
    the old numbers): every zone's schools ×1.4 (×1.9 past the drop-off, in the canyon
    and over the vents), every school of more than one fish ×1.5 up to `perSchoolMax`
    30 (lone hunters stay alone): ~8,560 fish in ~824 schools (was ~3,660 in ~484).
    Spines past `WAVE_HALF` 60 studs wave every other frame (`SchoolController`); the
    server's school lift yields between schools in its own thread (`Schools.settle`
    `pause`, ~3 s in the CLI, 25k characters). run_density: a client moves ≤ ~650,
    waves ≤ ~300 and keeps ≤ ~1,080 fish built at the busiest spot.
  - **Fast respawns:** every prey's `respawn` ~⅓ (Minnow 3 s, Snapper 5, Reef Shark 12,
    Oarfish 60). A fish coming back swims in from behind its school as it grows
    (`RETURN_SECONDS` 1.1 from `RETURN_LENGTHS` 6 lengths back), edible from
    `RETURN_EDIBLE` 0.8 (off its path the server wouldn't find it).
  - **Reef-fish clouds** are small copies of the biome's own reef prey from `PreyModels`
    (`Config/Ambient` `cloudPrey`; part-built body, tail and fin until imported) and
    scatter when your fish swims through.
  - **Bite feedback:** a snap sound with bubbles and a camera kick on every bite, a
    crunch when it lands, and a jaws marker at the screen's middle (two fangs close; a
    red ring bursts on a hit; `HuntController.snapped`, `HudController` `snapJaws`).
  - **Leaving a den waits for the plaza:** the server publishes `World.Hub`
    `PlazaParts` (`Layout.hubParts`); the wash holds until 96% of them have streamed
    in, the content queue is nearly empty and 3.5 s have passed, showing SWIMMING OUT
    TO THE HUB · N%.
  - **The den's way out is a real doorway** (`Config/Dens` `exit` y 11, back 9, alcove
    10.5): DenCarve cuts an alcove into the front wall like the plaza's (Cave.denDoor),
    the portal at its back; DenDoor builds it in the den's own doorway style (restyle
    dresses both sides) with a threshold, TO THE HUB · THE PLAZA, always lit, a
    brighter portal light; a tall style's nameplate is kept under the vault
    (`underVault`). The den's title board hangs over the trophy wall now. The den block
    reaches 6 further forward (`Layout.DEN_EXTENT`). `check_doors.luau` tries every
    style on the exit too; `exit_build.luau` previews it.
  - **Tutorial, bigger:** each step has a `title` (SWIM OUT OF THE HUB, ...), the card
    is ×1.2 (×1.05 on phones) and taller, and a new step shows a centre banner
    (TUTORIAL · STEP n OF 9, `Ui.stageBanner`).
  - **Wardrobe:** cards Common first down to Mythic (owned first within a tier); a
    locked skin is a dark silhouette on its card and on the stage, its name, tier,
    how-to-get and details still shown (LOCKED · UNLOCK TO SEE IT).
  - **Window skins** (Hatch & Snatch's Galaxy look): `Config/Shades` `WINDOWS` gives
    three or so skins a fish a pattern that holds still on screen while the fish moves
    through it (`Cosmetics` `WINDOW_AXES`: each face's tiling Texture offset by the
    part's place against the camera, plus a slow drift): Nebula, Void, Comet and
    Starfall (stars), Diamond and Glacier (facets), Divine, Aurora and Abyss Eye (veil),
    Prismatic and Exotic, Chrome, Thunder, Magma, Coral Bloom, Jade, Sunburst, Lantern
    King. The toothed fish leave out the face their head points from. **Smoothed
    (owner, 2026-10-20: "a bit glitchy once moving"):** the pattern is laid on the two
    flanks only (`sideFaces`; the six projections' seams slid along the back, belly,
    head and tail), placed after the camera moves each frame (`Cosmetics.windows`,
    bound at Camera + 2; it was a frame behind), its offsets eased 0.05 s, and it fades
    up to 85% while the fish turns or banks hard (0.9 → 2.6 rad/s).
  - **Sea-life companions** (`Config/Companions`, `CompanionService`,
    `CompanionController`, AmbientLifeController's `interact`): swim beside a turtle 2 s
    and it joins you for 300 s (5 min since 2026-10-20; was 90) at your side, seen by everyone (character attribute
    `Escort`; admin "Sea turtle: one joins the target now", `CompanionService.join`),
    bites on you ×0.8 (not the crushing deep), back in 4 min; ride a manta's
    wake 0.4 s and its current carries you at ×1.3 top speed for 8 s, renewed while
    you stay in it (`SwimController.draft`, a toast, a client-side `Draft` character
    attribute for tests; SpeedService allows the faster of it and the slipstream; a
    manta cruises at 4–6.5 studs/s, so a buff only inside the wake never held); skim low over a resting ray and it bursts off the sand
    stirring up 8 shells (2 until 2026-10-20; one every 90 s; it's gone from your view a minute). The
    server checks a live fish out of the hub and dens, a biome that kind lives in, near
    the floor for a ray, and the cooldowns.
  - **The Vents' spheres are gone:** every sphere-mesh lump in `Vents.luau` is a cut,
    flat-faced piece (drip streaks, polygon ledges, sulfide prisms, faceted chips, flat
    lava pools, a draped flowstone sheet, flat-topped rimstone lobes, clam halves,
    mussel lozenges, red worm brushes), and every vent throat (smokers, side throats,
    the basins' chimneys) is a hot disc with a dark rim. ~2,960 parts (`PARTS_CAP`
    3,300). **Rule: no sphere-mesh lumps in built scenery.**
  - **Community logo:** `marketing/community_{a,b,c}_512.png` (A recommended; screened
    0.17 / 0.15 / 0.05). Connor creates the community and sends its id for
    `tuning.group` in both games.
- **The 2026-10-20 report's decisions (PC report `2026-10-20-pc.md`, published as v15;
  PC fixes e95679d…3b45f4a merged into `claude/world`; Connor's standing "go with all of
  your recs"):**
  - **FPS** (Studio Play, PC: Kelp 41, Reef 45, Open Blue 43, Ruins 49, Vents 51, Trench
    39; phone sim Kelp 44, Open Blue 46): a built fish past its draw range is looked at
    only every 4th frame (`SchoolController` `CULL_EVERY`; Kelp had 472 built, 119
    drawn, each one's path worked out every frame), and the draw-range floor on a slow
    device is 0.6 (`DETAIL_MIN`, was 0.7). The `fill` stays until a real phone and the
    Script Profiler say where the time goes (next brief).
  - **Tutorial:** step 2 eats 5 things (ten of the shallows' fish filled a LV 1 fish's
    2.1 kg Haul, so step 4 was done on sight).
  - **Phone tutorial card:** its key caps line up from the card's right
    (`TutorialController` `showControls`), and the stick ring rests at (92, H−70)
    over the card's empty lower-left corner.
  - **Diamond's window** is a deeper ice blue (140, 196, 255) at 0.6 transparency (was
    near-white at 0.35: the Nibbler read white).
  - **Manta:** ride then carry (above), with the `Draft` attribute.
  - **Den vault:** the carved roof hangs up to `Config/Dens` `vaultSag` 4 studs under
    `DenSpace.vaultAt`; the way out's nameplate keeps that clear (DenDoor `underVault`),
    and the PC's raycast still seats it on the real rock (6b17c05).
- **The 2026-10-20 round-2 report's decisions (PC report `2026-10-20-pc-2.md`, PC fix
  f4bf771 merged: the tutorial's Haul step waits for a full Haul, so the first bank is
  LV 1 → 6; not published, the old live editing session blocked it):**
  - **Where the frame goes** (Script Profiler, Studio stats): render prepare ~11 ms of
    ~23 (CPU-bound; the GPU has time to spare), client scripts ~5.5 ms. Prepare grows
    with moving instances and draw calls, so cut those first. In the Kelp the kelp sway
    cost as much as all the prey (59 ms/s, most of it BulkMoveTo); in the Trench the
    prey were the biggest script cost (105 ms/s) and the shadow pass took 484 of 1,014
    draw calls under a sun faded to 14%.
  - **Kelp sway** reaches 120 studs (`REACH`, was 180; `BLEND` 40), and past
    `HALF_RATE` 60 a plant no fish is pushing is posed every other frame.
  - **No shadows in the dark:** `OceanController` turns `Lighting.GlobalShadows` off on
    the client once the water's own dark passes 0.6 and puts back the server's value
    under 0.35.
  - **The prey `fill` stays** (the PC's advice: trim only the Trench and canyon, ×1.9 →
    ~×1.4, if it's still slow after these two).
  - **Diamond, skins v15** (`shade_patch_v15`): the Nibbler's Diamond was a mirror
    (roughness 0.14, metal 0.35) that showed the den white and the Reef navy; it's a
    gloss with no metal now, a deeper ice blue with a faint even ice-blue glow map (no
    `emissive` in Config/Shades, so it isn't a lamp). Config `back`/`belly`/`fin` are
    ice blue for the stand-in, `reflectance` 0.12. A skin that reads as its
    surroundings needs its finish changed, never a stronger window layer.
  - **Publishing:** a publish leaves Studio in the experience's live editing session,
    and that session blocks the next publish until it's closed (this round it hung on
    "Applying script changes"). Everything in it is in git and `ApexAbyss.rbxl`, so
    the PC closes that window right after publishing and reopens the file.
- **The 2026-10-20 round-3 report (PC report `2026-10-20-pc-3.md`; published as v17
  from 2db727c; no fixes needed):**
  - **Measured:** Kelp 41 → 42 → 45 FPS over the three rounds, Reef 45 → 43 → 46,
    Trench 39 → 43 → 43 (phone sim 43). KelpController 59 → 19 ms/s, instances moved a
    frame 576 → 192–320; in the Trench the shadow switch took the shadow draw calls 484
    → 0 and render prepare 11.9 → 5.7 ms. The sway's edge doesn't show, and turning
    shadows off costs one ~40 ms frame on the way down (left as is). In the Kelp the
    prey (SchoolController 70 ms/s, ForageController 36) are now the biggest script
    costs, and render prepare (9–11 ms) is still the CPU bottleneck there.
  - **The Trench `fill` stays ×1.9:** a trim would buy ~1 ms. **Studio Play no longer
    shows render savings as FPS** (it runs the server too; the Trench stood at 18 ms a
    frame standing still), so judge any further render or prey cut on a real phone.
  - **Diamond v15** reads ice blue in the den, pale ice blue in the Trench (no light of
    its own) and mid sapphire in the Reef. Left as is; if the Reef should match the
    den, raise its roughness or its glow a touch.
  - **Every publish ends the same way:** Close Place hangs on "Applying script changes"
    (`CommitInProgress`) even with no edits, so the PC closes once, ends that Studio
    window if it hangs, and reopens `ApexAbyss.rbxl` (its Rojo panel shows 34872 again:
    set 34873).
  - **Old normal maps:** 1,804 SurfaceAppearances in the place carry a NormalMap, all
    on Tripo props imported before the 2026-10-13 rule (garden corals, shells, …).
    They stay until a model needs replacing; nothing new carries one.
- **Rolled parts and variants, real models and bonuses (owner, 2026-10-21: the parts
  board's legendary sheet B and the variants board approved; built):**
  - **Models:** `parts_glb` (sha256 0e448695…: AnglerLure, NarwhalHorn, SawSnout,
    SailFin, VeilTail; squared up by `tools/props/parts_prep.py`, front on glTF -Z so
    they import facing +Z, emissive maps on the cyan bits) and `variants_fbx` (sha256
    ea4f358e…: Puffball, Sabrecuda, Porcupine, DragonMoray, Hammerhead, Deepfang,
    rigged like the species; Sabrecuda and Hammerhead with a Jaw). Pipeline in
    docs/ASSETS.md; references by `tools/props/parts_variants_refs.py`; every image
    cleared by the classifier (highest 0.035). `safe_colors.py --olive` (new) turns tan
    and beige olive-khaki instead of vivid orange (the Porcupine). `organize_imports`
    files `PartModels.<PartId>` (MeshPart, `Facing` "+Z") and `VariantModels.<VariantId>`.
  - **Code:** `Cosmetics` `PART_MODELS` hangs a part's model by its attach point
    (`box`/`attach` from `parts.json`; `FishPlans` `mesh`, `FishBuilder.partModel`),
    the part-built pieces until imported; a variant with a model swaps the body's mesh
    (`swapMesh`, `FishBuilder.variantTemplate`; MeshPlan = the variant, so species
    skins don't fit it: a shade tints its own texture) and `Cosmetics.apply` returns
    true so FishAnimator re-reads the bones (`rigOf`).
  - **Bonuses** (`Config/Exotics` `bonus`, read by `Perks.exotic(character)` from the
    server-set Parts/Variant attributes, so client and server agree; never bite
    damage): Angler Lure +25% swallow reach (HuntService/ForageService suction, the
    clients' eats) and its light; Narwhal Horn Dash/Torpedo ×1.2 long (SwimController);
    Sawblade Snout shell reach and the treasure arrow/X ×1.5 (`Perks.shellReach`
    `find`, ShellService); Sail Fin +5% top speed (SpeedService allows it); Veil Tail
    turns ×1.15; Puffball Dash recharge ×1.2; Sabrecuda Torpedo ×1.25 long; Porcupine
    Puff Up ×1.25 long (AbilityService); Dragon Moray Burrow recharge ×1.25
    (AbilityService `cooldownOf`); Hammerhead Blood Sense prey range ×1.25; Deepfang
    Lantern Flash stun and dazzle reach ×1.25. Shown in the Wardrobe and the Index.
- **The biome landmarks (owner, 2026-10-21: the five boards in
  `assets/concepts/biome_detail/`, "all of that works for me", the Open Blue pinnacle
  included):** a landmark and a prop kit for each of the Graveyard, Trench, Kelp, Reef and
  Open Blue, each its own builder module on its own Random (shared helpers
  `src/server/LandmarkKit.luau`: parts, rods, chains, lanterns, `hero` = a model over its
  part-built stand-in, `keepColliders` for arches). Models: kit crops off the boards'
  kit sheets (`tools/props/biome_kit_crops.py`) through image_to_model, heroes
  text_to_model (`tools/tripo_jobs_biome_<biome>.json`), then strip_normals, safe_colors,
  `tools/props/biome_tint.py` where the classifier flags, the screen; bundles
  `biome_<biome>_glb`. Named places: `Config/Places` (14, two a biome, the Ruins' temple
  and theatre and the Vents' Forge and brine pool too); builders publish where each ended
  up as Vector3 attributes on `Workspace.Places` (`PlaceMarks.set`). Preview:
  `PROPS=1 bash tools/preview/run_biome.sh <Wreck|Trench|Kelp|Reef|Blue> <dir>`.
  - **Shipwreck Graveyard** (`src/server/Wrecks.luau`): the Broken Galleon at 180°, r 650
    (bow listing and stern nose-down 24 studs apart, snapped ribs and planks between, the
    stern's lit cabin with a warm light and the dig spot `BrokenGalleon_Dig` under its
    windows, anchors out on part-built chains, cannons and barrels spilled, the figurehead
    fallen, the wheel-and-bell post behind the stern, lanterns on broken posts), the Fallen
    Lighthouse at 196° (the GLB's tower leans 42°: `CFrame.fromAxisAngle` lays its line
    level), a steamer and a trawler, and the Bay Cannon at 151° aimed over the bay at the
    galleon (`Wrecks.cannons`). WorldService's `wreck` still takes its 44 draws on the
    shared Random and hands each spot to `Wrecks.scatter` (hulls, sterns, steamers,
    debris fields; never within 120 studs of a set piece). ~120 parts with the models in,
    46 models, 7 lights.
  - **Abyssal Trench** (`src/server/TrenchDress.luau`, under `World.Biomes.Rocks.Trench`):
    the Leviathan's Spine down the canyon's middle from r 1100 (seven LeviathanRibs arches
    130 → 72 across, 0.2 of a span apart, so it reads as one ribcage to swim down; each
    keeps its stand-in's rods as invisible colliders, `keepColliders`; glowing worm tufts
    on them, a light every other arch), the horned skull 90 long at the head end, bone
    heaps for a tail; Shelf.luau's `landmarkOps` clears the basalt pillars standing in
    its way (r 1010–1410, ±76 across; their draws are kept). The Squid's Lair: a cave Shelf
    bites into the wall at r 1330 (`Features.lair`), eggs, bones, beaks, a teal light;
    the squid rises in front of it (`PlaceMarks` `SquidLair_Rise`, BossService
    `summon`). Crystal clusters, glow tubes and glass sponges on the floor, a trail of
    worm tufts down the middle. WorldService's old Neon ball specks are crystal shards
    (`TrenchDress.speck`, same draws) and the glow gardens' tips flat caps. ~350 parts
    with the models in, 44 models, 18 lights.
  - **Kelp Shallows** (`src/server/KelpDress.luau`): the Kelp Cathedral at 45°, r 345: 24
    giant kelp 210 tall in a ring 80 across round an open nave (ordinary `Kelp` models in
    World.Biomes.Kelp, so they sway), their crowns' fronds reaching in as a roof with the
    middle open, three light shafts (`Kit.shaft`), sea grass. A tall plant is two GiantKelp
    stacked: the model is half as wide as tall, so one fitted to 210 drew a plant half as
    tall. KelpCanopy is in the bundle but unused (from below it read as a spiky tuft).
    Otter Meadow at 300°: grass, a solid urchin barren, otters and a buoy at the surface
    (tag `Bobbing`); a lobster-trap and rowboat trail toward the Wreck bay.
  - **Coral Reef** (`ReefDress.luau`, under `Coral.ReefLandmarks`): the Blue Hole Shelf
    sinks in the reef's most open stretch near 40°, r 640 (scored against the reef heads
    and `Features.outcrops`): a coral rim in three colour districts, plate corals down its
    wall, a glow at the bottom. The Clam Garden near 320°, r 660 (the most open spot): 7
    solid GiantClams, each a Neon pearl (`ClamPearl`, `Pearl` index, `PlaceMarks`
    `Pearl<n>`); garden eel patches (`GardenEels`).
  - **Open Blue** (`BlueDress.luau`, under `Rocks.OpenBlue`): the Whale's Rest (a skeleton
    120 long on the floor at 268°, r 1120, a light shaft); Hammerhead Pinnacle (a solid
    240-stud CoralPinnacle at 296°, r 1455, past the Megalodon's patrol band); 9 sargassum
    rafts at the surface (`Bobbing`, `Sargassum`) and 7 jelly chains (`Drifting`).
  - **Clearings:** each builder marks its landmarks' ground (`Kit.clearing`) and
    WorldService takes the biome's random scatter (rocks, corals, kelp, seeps, plankton
    mats) out of it afterwards (`LandmarkKit.clearAround`), so no boulder stands in the
    nave or the hole. `Kit.hero` sets each holder's `WorldPivot` to its box.
  - **The play** (`LandmarkService`, `LandmarkController`, `Config/Places`): named places
    found by swimming within their `radius` (checked once a second, `data.places`, paid by
    `RewardsService.grant`, all 14 pay `allFound`; state `places`); the LOG's Places tab;
    found places marked on both maps (names on the full one) and named on the minimap's
    bar. BITE the galleon's bell (`Bell<n>` mark; rings for everyone, `Net.landmark`) or a
    pearl (120 coral, 6 shells, gone for that fish 15 min, `data.pearls` in Unix time,
    state `pearls`) through `HuntController.findLandmark`; the Bay Cannon (`Cannon<n>`,
    `Cannon<n>Aim`) fires a fish at its muzzle 95 studs/s for 1.3 s, the client driving the
    flight while the server stamps `MovedAt` each second (SpeedService resets on it). A
    Weathered or Captain's map buries its chest at `BrokenGalleon_Dig` 30% of the time
    (`TreasureService` `placeSite`, the place's `digHint`). The client bobs, drifts, ducks
    the eels, builds fish under rafts near the camera and circles 4 hammerheads
    (VariantModels.Hammerhead or part-built) round the pinnacle. Admin "Places: unfind
    every named place, regrow the pearls". PC brief: `docs/playtests/2026-10-21-biomes-brief.md`.
- **Daily login streak (owner, 2026-10-09; built):** `Config/Daily.luau`,
  `RewardsService`, `MenuController.openDaily`. One claim a UTC day; a missed day
  restarts at Day 1; seven days loop (300 coral → … → Day 7: 2,500 coral, 100 shells
  and a Captain's map) with +25% per finished week (up to +100%). The panel opens by
  itself once a session when a reward waits (after the tutorial, and never over an
  open offer card); DAILY glows. A claim shows in the panel's own footer (a toast
  covered it) with the Bank sound.
- **AFK income: the Coral Garden (owner, 2026-10-09: "an afk aspect of the game to earn
  something to keep players coming back"; built):** a garden bed in every den, under
  the trophy plaques, grows coral and shells over real time, online or off, up to 8 h
  (16 with Deep Garden). Per hour by den level: 60/100/160/250 coral and 4/6/9/12
  shells. Resting in your own den grows it ×2 and collects every minute; swimming in
  collects it; a returning player spawns in the den and sees WELCOME BACK.
  `Config/Dens` `garden`, `Shared/Garden` (rates, grow, fill; luau-testable),
  `GardenService`, `DenBuilder.garden` (corals grow as it fills, sparkle when full;
  the bed sits on the Terrain floor found by raycast, `floorUnder`, half a second
  after the den is carved, since the voxel floor rises 0.6–4.6 studs above the den's
  nominal floor and a bed at the nominal height was buried, playtest 2026-10-09; it
  rests on the floor's high side with a 4-stud stone footing under it, so a sloping
  floor shows no gap),
  `GardenController` (the sign, payout pops, the welcome banner). Admin: "Coral
  Garden: grow hours".
- **Controls (owner, 2026-10-07):**
  - **PC stays as built** (the owner likes it): WASD swims relative to the camera (A/D
    slide sideways), the mouse aims, Space/C go up and down. **Since 2026-10-12 the
    mouse buttons are the fish's only buttons: LEFT CLICK dashes, RIGHT CLICK bites**
    (see "The 2026-10-12 batch"); M opens the map.
  - **Freeing the cursor (owner, 2026-10-10: "need a way to pull up the cursor since
    the cursor is tied to swimming"):** tap Alt to free it for the HUD and panels (`Input.cursorToggled`, the HUD's
    CURSOR FREE chip); tap again, or click the game (that click doesn't dash or
    bite), to lock it (a click on a HUD panel keeps it free). Holding Alt frees it
    only while held; menus free it while open. The tutorial card tells new players.
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
    (eaten like forage; a fish carrying the most swims through them, leaving them for
    others, owner 2026-10-20), the Tidecharm Trader (120 coral), a 3% prey drop and treasure
    chests; H / LB / HEAL. Eating prey heals 2% + 0.5%/kg. `Config/Tuning.luau`
    `heal`, `HuntService.giveWrap/useWrap/damage/kill`, `HealController`. Never sold
    for Robux. **No regeneration** (owner, 2026-10-11: "Health should not regenerate
    that is the whole point of kelp wraps"): only a wrap, eating prey or a respawn
    brings health back. **The item wheel** (owner, 2026-10-11: wraps "in user
    inventory wheel to be used when needed and not immediately, same for kelp wraps
    won from the spin wheel"): Kelp Wraps and the timed charms (Feast, Shell Magnet,
    Deep Lantern; carry 3 each) always go into `data.charms` however they come
    (bought, won on the Treasure Wheel, treasure, bounties, admin) and start only when
    picked: hold G (point, let go; a tap leaves it open to click), hold LB (point with
    a stick; a tap of LB still uses a wrap), or the phone's ITEMS button
    (`ItemWheelController`, `ItemService` `UseItem`, `Config/Shop` `items`). A wheel
    prize that doesn't fit is paid in coral.
  - **AI predators (owner, 2026-10-06: aggressive AI fish worth more):** built as the
    base the bosses extend. **None comes near the starter cave** (owner, 2026-10-11:
    "Starter cave should never have predator fish or anything that can hurt you in
    it"): `PredatorService.steer` keeps every creature (bosses too) `Predators.hubKeepOut`
    210 studs plus half its length from the hub's centre, and a fish inside that is
    never a target (damage there was already blocked by the safe zone). `Config/Predators.luau` (Barracuda, Reef Shark) and
    `PredatorService`: simulated at 10 Hz, roam a band round the hub, hunt the biggest
    worthwhile fish in range, telegraph every bite (0.9–1.1 s jaw flash and an INCOMING
    warning for the target), bite for a share of max health; players bite back
    (`BitePredator`, damage scaled by the length ratio, +35% per other biter in 2.5 s);
    a kill pays Haul, DNA and coral by damage share. Positions stream over an
    UnreliableRemoteEvent; `PredatorController` interpolates 0.15 s behind, draws the
    `PreyModels` mesh (parts until imported) with a red PREDATOR tag and health bar.
    A predator with `custom` set skips the plain behaviour (bosses drive it).
    **Every shelf biome has its own (owner, 2026-10-21: "we need more predator fish
    too that felt pretty scattered"; there were 8 in all):** a def's `also` lists more
    waters, each its own group of the same fish (`Predators.groups`, one spawn group
    per water): since the eight below, Barracuda 6 in the Wreck bay (respawn 60 s) and
    Reef Shark 5 in the Open Blue (LV 45) and 4 cruising the Reef's outer half (LV 34;
    respawn 100 s). Each player is streamed only the creatures
    within `streamRange` 700 studs of their fish, any hunting them and every boss
    (`Net.predatorStateTo`); a client hides one it hasn't heard of for `STALE` 1.5 s and
    starts its path afresh when it's back. The ambusher's lurk spots keep to its
    sector. New species for every biome are on `assets/concepts/PredatorsBoard.jpg`
    (sheets `tools/tripo_jobs_predator_concepts.json`; owner, 2026-10-21: "I like those new
    predators"). **Their models are made** (`predators_fbx`, sha256 30600df5…; rigged with a
    Jaw, every colour map cleared, highest 0.026): SeaLion, GoliathGrouper, GiantTrevally,
    MakoShark, SixgillShark, WolfEel, GoblinShark, BlackDragonfish, filed into
    `PreyModels.<Id>` by `organize_imports`; their shapes and jaw hinges are in docs/ASSETS.md
    "The new predators". Every Tripo sheet paints an open mouth mauve inside: recolour it
    (`tools/props/predator_refs.py --fix`) before 3D, and run `safe_colors.py --plum` after.
    **The eight in code (owner, 2026-10-21: "Ensure ease of eating them scales with
    levels as well", "the world should feel full"):** 53 plain predators: Kelp 5 Sea
    Lions (the kelp-edge Barracuda went), Wreck 6 Barracuda + 3 Goliath Groupers, Reef 3
    Giant Trevally packs of 3 + 4 Reef Sharks, Open Blue 5 Reef Sharks + 3 Makos, Ruins 4
    Sixgills, Vents 6 Wolf Eels, Trench 3 Goblin Sharks + 5 Black Dragonfish.
    - **Fights go by level, like PvP** (`Config/Predators` `fight`): every group has a
      `level` (a Water can set its own). A player's bite on a plain predator is ×
      1.108^((their banked level − its level) × ⅔), clamped `yours` 0.05–4 (24 × that a
      bite; health = 24 × the bites an even fight takes): 10 up takes ~5 bites, 20 up
      (`swallow`) swallows it whole in one, still paying its loot; 10 down ~16. Its bite on
      a player goes the other way, `theirs` 0.15–1.5 × its `biteFraction`. It won't hunt
      a fish more than `shy` 12 levels over it (it keeps clear, unless that fish bit it in
      the last 8 s), and a fish above it gets its loot × (its strength against the fish)
      ^ `pay` 1.5 (floor `payMin` 0.05), so farming low predators doesn't pay.
      Bosses keep `bitten`. The stream's 13th field is the group's level; the tag's
      second line reads LV n · STRONGER / WEAKER / EVEN FIGHT (Config/Pvp `edge`), and a
      roamer 12+ levels under you reads WARY OF YOU. The Index's GUIDE and FISH say so.
    - **Each its own way** (`Style`: `pack`, `gulp`, `tether`, `lure`, `trench`,
      `spareLearners`, `warn`): the **Sea Lion** (LV 6) harries with light nips and never
      hunts a fish in the tutorial; the **Goliath Grouper** (LV 18) lurks low and its
      tell sucks the fish in (`gulp` 34 studs/s² within 26) until the fish swims off
      faster than 1.4 × its top speed (a Dash); **Giant Trevally** (LV 32) hunt in packs
      of 3 (the leader drives, the others keep station and swing out to its flanks,
      sharing its target; a dead one respawns at its station); the **Mako** (LV 45)
      comes up from below (`under` 0.75) and commits 60% into its tell, so a juke as its
      jaw flashes beats it and a late one doesn't; the **Sixgill** (LV 60) is a slow,
      heavy patroller with glowing green eyes; the **Wolf Eel** (LV 75) holds a hole
      (`home`, the best cover near its spawn) and lunges from it, never straying past
      `tether` 36 studs (a fish 80 out is safe); the **Goblin Shark** (LV 90) throws its
      jaws (a long snap, commit 0.4: a sideways dodge early in the tell escapes); the
      **Black Dragonfish** (LV 88) draws the fish it stalks in with its lure (9 studs/s²
      within 45) and bursts. Trench hunters keep to the canyon (`trenchWaypoint`).
      Server pulls go through `Net.shove` every tick, like the whirlpool.
    - **Client** (`PredatorController`): each draws its rigged `PreyModels.<Id>` (Jaw
      bone; `DRAW_SHIFT` moves the dragonfish's mesh up off its barbel's box) or a
      part-built stand-in from its own proportions (`STAND_INS`: body, tail, head, fins,
      snout, eyes; `rig` pieces such as the dragonfish's cyan lure also go on the model).
      Bodies are measured by `girth` (height and length, never the sea lion's flippers or
      the dragonfish's barbel). Tells: water streams into a grouper's open mouth
      (`suction`), the goblin's jaws shoot forward (`JawRange.throw`), the lure breathes
      and brightens as it hunts; warnings in words from `warn` (GULP · DASH OUT, JAW
      THROW · DODGE SIDEWAYS, PACK · HIDE IN THE ARCHES, ...), ITS LURE IS PULLING YOU IN,
      PACK HUNTING YOU; a predator swallowed whole goes in a big burst and a chomp.
    - Sim (`run_predators.sh`, with level cases and each species' escape): Barracuda
      bites ×1.5 a LV 10, ×1 a LV 18, ×0.5 a LV 28, and takes 16/8/5/1 bites from LV
      8/18/28/38; a LV 35 fish isn't hunted. Sea Lion: a juke at the tell escapes 99%
      (late, 2%); Grouper: a Dash out of the gulp 100%; Trevally: hiding 100%, a Dash
      97%; Mako: a timely juke 100% (late 40%); Sixgill: outswum; Wolf Eel: past its
      tether; Goblin: an early dodge 100% (late 0%); Dragonfish: a Dash at the tell ~60%.
    **Real ground and fluid swimming (owner, 2026-10-13: "the predator fish will
    phase through the sand in the ground ... Their tracking should also be more
    fluid and realistic"):** `Shared/Ground.luau` gives the real ground's top in a
    column (a ray down from the surface against the Terrain and the solid parts of
    `World.Biomes` Rocks/Coral/Wrecks/Ruins/Vents, cached per 4-stud cell; a miss
    answers `Seafloor.y` uncached). `PredatorService.steer` reads it under the body
    and 1.4 s ahead: it climbs over reef heads before reaching them, the belly never
    goes below the ground + `BODY_HALF` × length + 1.5, and the nose can't point
    into it. Waypoints sit over it, and the hunt aims over it. A plain predator
    swims along its heading (turns ease in and slow with speed, it slows in a hard
    turn, accelerates briskly), weaves lazily while roaming, leads its target by the
    time to close, cruises in and sprints the last 35 studs, carries through a
    strike and peels off to one side to loop back. Bosses keep their direct velocity
    model and their old height off the nominal floor. The client draws a
    Catmull-Rom curve through the samples, banks into turns and never draws a body
    below the ground.
  - **Megalodon (built 2026-10-07):** `Config/Bosses.luau` + `BossService` on top of the
    predators. A world event about every 30 min (4 min in Studio; 2 min warning,
    `_G.ApexBoss.summon()` / `.hurt(0.5)` from the Server command bar), patrolling the
    Open Blue (north, 1,000–1,440 out, 170–470 studs over the floor). 6,000 hp +60% per extra attacker (20 s
    window). Three phases: Hunting (Charge 35%, Bite 55%, both telegraphed),
    Frenzy under 60% (×1.3 speed, blood cloud hides the tag, Tail sweep 20% + a shove
    when 3+ fish bunch behind it, Marked for death: 8 s of short lunges at one fish),
    Last stand under 25% (makes for the open ocean, the far edge of the Open Blue, on a 60 s clock; Breach every 13 s:
    sinks, rockets up, crashes with a shockwave 30% + shove, then 5 s exhausted at
    triple damage; escapes when the clock runs out and returns in 15 min). Gills and
    tail take double damage and fill the stagger meter, a notch a bite (12 bites, the
    Squid 10; owner, 2026-10-20: "far too many bites to stagger", it was 700 damage);
    full → 4 s stagger at triple damage, breaks the mark. Player bites on a boss scale
    by `bitten` (×2.2 × (raw length ÷ 175)^0.5, the Squid ×0.9 ÷ 95; was the plain
    ^1.5, so every fish hit the 0.08 floor, ~1.9 a bite): ~12 a bite at LV 45, about
    9 min solo. Rewards for everyone with ≥1% of the damage:
    Megalodon Teeth (1, +1 top three, +1 killer), a Haul (1.5 full Hauls + the damage share × 1 more, since 2026-10-19; was 120 kg by share),
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
    5,500 hp, lurks deep (10–55 up off the floor) in the Trench's canyon: it rises,
    patrols and jets inside it (`patrol.trench`, `Seafloor.trenchPoint`) and gives up
    a chase that leads it 160 studs out (`patrol.leash`; it rose in the Ruins and
    roamed 4,700 studs out, playtest 2026-10-10). No predator leaves the map
    (`PredatorService.steer` holds them inside `boundsRadius`).
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
  megalodon and sharks with some other good haul fish like grouper and snapper", and
  2026-10-09 "just open ocean", so open water over a blue-grey floor far below with
  knolls and low spires; the Reef Shark predators and the shark/grouper/snapper
  schools keep to its sector, mid-water), Sunken Ruins east (50–70, plus a
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
  local floor. Shells, forage and treasure sites land only on open floor (`Ground.open`
  since 2026-10-17; they once raycast the Terrain only, and a shell on
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
- **The Megalodon comes out of the deep blue (owner, 2026-10-09: "an eerie figure
  that sort of appears from the deep blue ... not for deepest darkest ocean just deep
  blue where there's no ground or anything just open ocean ... unseen until he slowly
  fades into view of players. Once he is upon them he needs to be seeable to be
  fightable"):** it roams the Open Blue's open water (`patrol.depth` 170–470 over the
  floor); the Open Blue's fish and Reef Sharks keep to 140–430, and its old 150–280
  stud pinnacles are 37–70 stud spires on the floor far below (`Shelf.luau`).
  `Config/Bosses` `sight` (studs from its body): unseen beyond `far` 500, solid by
  `near` 290 (280/170 until 2026-10-18's clearer water; dread from 680) (`PredatorController` fades the body's transparency by camera distance,
  eased; tag, boss bar and NEARBY once it's 35% opaque). **A body is fully opaque or
  plainly fading, never a hair see-through** (owner, playtest 2026-10-10: "boss has
  holes and see through glitches"): the eased fade sat at 0.995 for the whole fight,
  and any Transparency above 0 draws a mesh in the transparent pass, which doesn't
  sort its own faces, so fins and the jaw showed through; the opacity snaps to 1
  above 0.97 and to 0 below 0.02. Within `light` 190 the fight light
  (`OceanController.setBossLight`: exposure +0.35, haze ×0.78, and in the dark the dark
  ×0.4) plus a faint cool Highlight rim. The dread (range 460) never darkens the
  picture any more (it made the Open Blue near-black, playtest 2026-10-09): colder,
  greyer water, a heartbeat in the contrast and a vignette of the screen's edges
  (`BossController`); while it's unseen the warning reads SOMETHING CIRCLES IN THE
  BLUE with no arrow or distance. The squid has no fade (the dark is its own) but the
  same fight light.
- **Massive bosses (owner):** the Megalodon is 175 studs (130 until 2026-10-19), the Giant Squid 95; reaches
  and radii scaled with them (`Config/Bosses.luau`). **The surface is a ceiling for
  the whole body** (playtest 2026-10-10: chasing a fish at the surface, the
  Megalodon's back and fin broke through the surface sheet): `PredatorService.steer`
  keeps a creature's middle `max(12, 0.3 × length)` under the surface and limits its
  tilt there so nose and tail stay under; it still reaches a fish hugging the
  surface (its mouth rises to ~16 studs under). **Bosses are solid** (playtest
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
  the cap, retest 2026-10-09), or on top of rock covering the chimney (a basin's
  rubble). Bosses glow faintly in the
  dark (`PredatorController` `DARK_GLOW`, violet for the squid) so they're
  silhouettes, not invisible. **Not black, and lights by rarity (owner, 2026-10-09:
  "about 5-10% visibility with no light, and visibility with a light source scales
  with how rare the light source is"):** the dark keeps `Config/Tuning` `light.ambient`
  (24, 34, 50), up to `light.plankton` where the plankton is thick, with a very deep
  blue haze (`light.water`), so rock and fish read as dim shapes; 42 glow gardens
  (glowing tube anemones, each a PointLight of range 28) sit along the canyon floor
  and every Trench plankton mat is lit. `LampController` gives each fish its best
  source from `light.sources`: the `Lamp` attribute (`lantern` from the Deep Lantern
  charm, 350 coral, the weakest; `lure` for the Anglerfish) or a glowing shade
  (`emissive` or `spectral`) by its tier, Common → Rare → Epic → Legendary → Mythic →
  Trophy/Abyssal. Range, brightness, beam and `reveal` (how much of the dark it lifts
  from the holder's own view, `OceanController.setReveal`) all grow with rarity; a
  shade's light comes up with the water's own darkness (`OceanController.darkness`,
  before the holder's reveal: scaled after it, a rare shade dimmed itself on its
  wearer's screen, playtest 2026-10-09). A deep-coloured light gets up to ×1.6
  brightness by luminance (Abyss Ink, Void, Nebula read weaker than their tier).
  Common glowing shades: Ember, Ink and Neon Tetra (`light` in `Config/Shades` gives
  the colour when there's no `glow`). The Trench reads the plankton level nearly
  everywhere at its bottom; the base shows higher up. The biome banner and chip say
  PITCH DARK · bring a light (DARK WATERS since 2026-10-11). **Retuned after the owner's "the abyss can't be
  completely black how the hell will anyone fight anything in pitch black or low
  visibility let alone a boss" (2026-10-09):** `light.ambient` (32, 46, 66),
  `plankton` (44, 74, 88); the deep-colour boost tops out at ×1.2 (×1.6 made the
  purples outshine everything); `lampBoost` in `Config/Shades` lifts Aurora (×1.15) and
  Ghost (×1.25), which read weak on the teal floor; Common is range 24, brightness
  1.3; Trophy 3.6. Every predator shows the eerie rim in the dark (non-bosses at 60%),
  and near a boss the fight light lifts the dark (above). **Creepy, not black
  (owner, 2026-10-11: "Let's just go with a creepy vibe for the trench and keep it
  darker but not pitch black people aren't going to want to go there. The light
  affects will still make a difference"):** the dark keeps `light.ambient` (58, 76,
  80), `plankton` (64, 96, 98), 14% of the sun (`sun`) and 30% of the environment's
  light (`environment`); the haze is a murky green-teal (`water` (20, 44, 48),
  `decay` (7, 20, 24), `density` 0.7) that rock, fish and the squid loom out of; a
  cold, drained grade (`grade`: tint (206, 228, 220), saturation −0.22, contrast
  +0.1) and exposure +0.1. Lamps and glowing shades still lift the dark by rarity.
  The banner says DARK WATERS · a light helps, the chip DARK.
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
- **Den bases v2 (owner, 2026-10-13: "The dens need to be larger and have much more
  depth so players can build in them and show them off. It's meant to be like the
  players house/base. We will have furniture, rugs, lamps, and tons of items that
  will be rolled in"; the garden was "just sticks with spheres on the table"; built,
  GDD §6 "Den bases"; v1 was 2026-10-07: "an upgradable base that gets bigger and
  deeper ... Other players can go in and check out your base but can't take or do
  anything ... trophies ... furniture ... Coral lamps"):**
  - **Private interiors (v3, owner, 2026-10-16: "Dens also still need to be
    substantially bigger"; of three ways offered, "Private interiors"):** a den isn't
    dug into the hub's ring any more (twelve 30° wedges capped its width). Each den is
    its own block of rock on a 4×3 grid far outside the play area at the hub's height
    (`Config/Dens` `interior`: x 5,200 + 640 a column, z −640 + 640 a row;
    `Layout.denOrigin`), so it's lit like the hub and only streams to fish inside it.
    On the plaza each doorway is a shallow round alcove (`Cave.denDoor`) with a bubble
    portal 9 studs in (`Layout.doorFrame`, `WorldService` `portal`; the sign above it,
    the `Owner` attribute on `Hub.Den<i>`); inside, the way out is a portal on the
    Nook's front wall (`Layout.exitFrame`, sign TO THE HUB). Swimming within 8 studs of
    a portal (`Layout.doorAt`/`exitAt`; a big fish's middle stops ~7 off the rock)
    washes the screen with bubbles (`DenDoorController`) and sends `EnterDen(index)`
    / `LeaveDen`: `DenService` checks the fish is there, `RequestStreamAroundAsync`,
    then `Net.teleport` (to `Layout.spawnFrame`, over the Haul Pool, or
    `Layout.hubExitFrame`, 16 in front of the doorway). Anyone may visit a den someone
    lives in; an empty den's portal stays shut ("No one lives in this den yet"); when
    the owner leaves, visitors are put back on the plaza (`evict`) and the block is
    cleared (`DenCarve.clear`). Spawning streams the den in first (`FishService`).
    You arrive over your pool, so swimming home banks the Haul. `Layout.denAt` tests
    the grid (O(1)) and `Layout.inHub` counts den interiors, so they're safe, unpressured
    and hub-graded (`OceanController`, `AmbienceController` and the depth gauge read a
    den as the hub's floor height; `SwimController` skips the map's edge there); the map
    shows a fish in a den at its doorway (`Layout.mapPosition`); the tutorial's trail
    leads through the doorway, then to the pool, and "find the exit" in a den is its
    portal. Old saves: lower-storey placements move down with their decks once, and
    whatever no longer fits returns to the tray (`DenService` `relayout`,
    `data.den.layout`, kept out of the save template so Reconcile can't skip it).
  - **The levels:** Nook → Burrow 1,000 (a second great room runs back) → Hall
    12,000 (a shaft to a vaulted hall below) → Grotto 45,000 (wings, a deep back) →
    Sanctum 150,000 (a second shaft to the deepest storey), holding 24/48/80/125/180
    things (+25 Den Expansion). Rooms 1.22× wider and longer since 2026-10-18 (a 74 × 72
    Nook, 39 studs tall; deck ~1.5× the 3,056 / 6,416 / 17,384 / 25,712 / 46,432 square
    studs before; shafts z −70 / −110, r 10 / 11; pool z 14, r 9; old saves moved once,
    `den.layout` 4, `DenSpace.grow`). `Config/Dens` `rooms` (bands across
    the den's axis), `storeys` (deck, floor, ceiling, `wall`: decks 1 / −54 / −114,
    floors −4 / −60 / −120 on 4-stud voxel lines, ceilings 40 / −12 / −68), `shafts`
    (Hall z −58 r 9, Sanctum z −90 r 10), `gardenSpots`, `pool` (z 12, r 8), `exit`.
    Every room has upright walls `wall` high under a shallow arch: `DenCarve` cuts a
    cylinder along the room whose chord at the walls' top is its width
    (`DenSpace.archRadius`), puts back what it cut beside the walls and under the
    floor (clipped to the block), cuts the room from the rock floor up to the walls'
    top, bulges alcoves out of the walls, then the shafts (Air ops twice).
    `DenSpace.vaultAt` is that ceiling's height. `Shared/DenSpace` (both sides): decks
    as a 2-stud grid merged into flagstone tiles, holes (pool, shafts, garden,
    pillars), `check` (may a thing go there). `DenBuilder` carves only when the level
    changes, builds the shell (decks in a floor style, curbs, pillars, orb lamps every
    20 studs down each storey, three across in rooms wider than 40), keeps placed
    things in step by uid, seats the trophy wall both ways, the title over the way
    out, and the Coral Garden (a planter on the back wall, then a bed in the Hall's
    nave, Tripo corals or part-built staghorn/fan/brain/sponge/anemone growing one by
    one).
  - **Build mode** (`BuildController`, `DenService`): B in your own den or BUILD in
    the den menu. Since 2026-10-16 it's an editor view (the fish holds still, the
    camera orbits the floor, the cursor is free: see "The 2026-10-16 batch"); before
    that you swam and aimed with the camera. A ghost shows green or red with
    the reason; things go on decks, walls or ceilings (`kinds`) or on each other;
    aim at a placed thing to pick it up or X to put it away; R/F turn 15°, Q/E pick
    from the tray; pad RT/LT/LB/RB/D-pad/X/B, phone buttons. `Input.building` stops
    bite and dash meanwhile. Requests DenBuy, DenPlace, DenMove, DenStore (0 = all),
    DenFloor, DenColor, DenUpgrade, each checked again on the server. Record
    `data.den`: level, glow, floor, owned (glows and floors), items (copies),
    placed {uid, id, x, y, z, r, s}, nextUid; old slot furniture moves into
    `placed` once (`DenService.migrate`), old owned things become tray copies.
  - Six floor styles (Flagstone free → Glowing Obsidian 12,000), 16 things (new:
    Woven Kelp Rug, Jellyfish Lamp on the ceiling), seven glows.
  - Checks from the cloud: `LUAU=<luau> bash tools/tests/run_dens.sh` (rooms well
    inside the block, rock between storeys on voxel lines, shafts open into a room
    on both storeys, tiles cover the decks once, holes, placement answers) and
    `LEVEL=5 LUAU=<luau> bash tools/preview/run_dens.sh <dir>` (one interior
    voxelized in open water: enclosed with 6+ studs of rock, one cave joined by the
    shafts, every room open over its deck, rock between storeys; slices). Run both
    after any change to `Config/Dens`, `DenCarve` or `DenSpace`, and `check_exits.py`
    after `Cave` (the doorways' alcoves).
  - **Rock floors and shafts (PC report 2026-10-13: both shafts solid, no
    flagstones on the main storey):** Roblox's Air fills take occupancy away rather
    than clearing it (one pass over fresh rock left 0.21), so every den Air op is
    applied twice (`DenCarve` `twice`), the shafts are cut `SHAFT_CUT` 3 studs wider
    than their opening (`radius`: Hall 7, Sanctum 8) and 6 into the vault below, and
    each storey's rock floor is 5–6 studs under its deck on a voxel line (Terrain drew
    the surface up to ~4.6 over its fill, through the flagstones); the decks are slabs
    down to it. Storeys (v2): deck 1 / −34 / −70, floor −4 / −40 / −76. The Haul Pool sits
    in a stone basin with a rim. A thing standing on another may hang over a hole's
    edge if deck is within 2 studs (`DenSpace.nearDeck`); raised off the deck it
    must stand on top of a placed floor thing, inside its turned footprint
    (`DenSpace.resting`, checked by the server on place and move and by the ghost).
    An aim through a joint between flagstones lifts onto the deck.
  - **Shaft lift (PC report 2026-10-14: a LV 100 fish couldn't rise straight up the
    Sanctum shaft; it slid along the vault):** the swim's pitch limit (80°) turns
    straight up into 80° along the heading, so a fish under a mouth drifted off it.
    Under or in a shaft (within its radius + 6 of the axis, from 14 below the lower
    storey's ceiling to 6 over the upper deck) and swimming mostly up or down,
    `SwimController` moves the fish straight and eases it onto the axis
    (`shaftAxis`; the den's level is the `Level` attribute DenBuilder sets on
    `Hub.DenBase<i>`). Backing a piece onto a pillar left it in the pillar's deck
    hole, refused: Build mode now nudges a backed spot straight out until it fits
    (`snapFloor` returns the way out).
  - **Furniture batch 1 (owner, 2026-10-13: "Approve all, players will need to
    complete achievements to unlock the ability to purchase each set with coral.
    Once a set is unlocked, pieces are individually bought, not the entire set";
    built, GDD §6 "Den furniture, batch 1"):** seven sets of six (`Config/Dens`
    `sets`, items with `set`), each opened by one achievement (`Config/Achievements`,
    `AchievementService`: lifetime tallies, marked once in `data.achievements`, a
    banner, `state.achievements`); pieces are bought one at a time with coral in the
    den menu (DenService refuses a locked set). 38 Tripo models (`furniture_glb`,
    cut off the boards by `tools/props/furniture_crops.py`), four rugs drawn as
    Decals (`assets/textures/rug_*.png`, ids in `Config/Textures`). Pieces with
    their own light carry `lamp`; Tripo props face +X in the GLB (`front = 90`).
    Pass and reward den pieces go into `den.items` (the Build tray), never
    `den.owned`.
  - **Snapping and starter layouts (owner, 2026-10-14: free placement plus "the
    snapping and starter layouts"):** snapping is on by default (G / D-pad up / SNAP
    toggles it; header SNAP ON/OFF): turns go in 45° steps (15° off), a floor thing
    lines up with a neighbour's x or z within 0.8 studs, and with rock or a pillar
    within 2.5 studs behind it backs onto that wall facing out (4 rays in the den's
    frame against Terrain + Shell); a wall thing matches a neighbour's height within
    1.2 (else whole studs). A snapped spot is used only if it passes the same checks.
    `Config/Dens` `layouts`: each set's floor pieces as an arrangement round a spot;
    with a set's piece picked or aimed at, L / D-pad down / LAY OUT lays out every one
    in the tray round the floor spot aimed at, facing the camera
    (`DenSpace.fitLayout`: the spot, then rings 2 studs apart to 24, each way round;
    rugs only clash with rugs; `DenLayout` request). `run_dens.sh` checks every layout
    fits an empty Nook/Burrow and Hall and that a second keeps clear of the first.
  - The trophy wall, visitors (look only, the whole house is safe: `Layout.denAt`)
    and the sign ("<NAME>'S SANCTUM") work as in v1. The camera looks past den
    furniture (tag `DenItems`).
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
  (superseded 2026-10-18 by clearer, per-biome water: see that owner batch; before it,
  Atmosphere density 0.68 at the surface → 0.76 on the shelf → 0.88 on the deep floor
  and in the Trench, exposure down to −0.75; the Trench's black is the dark, above, plus classic fog with a `sight` per
  grade in case the Atmosphere ever goes), and the deep floor grade is a deep blue
  (the Mud material is blue-grey), never black; only the Trench's `dark` goes
  near-black. **The shallows' light is half as blue as it was** (playtest
  2026-10-10: gold skins read lime, lilac read royal blue): base Ambient (40, 56, 68)
  and OutdoorAmbient (78, 104, 118), and the shelf's grade tints keep more red
  (×0.84–0.87); the haze and deeper grades carry the blue. **The shallow haze is
  thinner and less green** (owner, 2026-10-11, after Golden and Bumblebee read olive
  from ~16 studs and Lilac blue): surface/mid/shelf density 0.64/0.66/0.68 (were
  0.68/0.72/0.76), colours bluer; the deep grades are unchanged. The sky, surface and upper atmosphere are the other (PC) chat's
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
- **Start screen (owner, 2026-10-09: "a start screen when players load into the
  server. Just hit any button to start and then it pushes them straight to the den
  and tutorial. Starter screen should have motion and some fish swimming by with maybe
  some kelp"; built):** `StartController` covers the game from the first frame: a
  lit underwater scene in two ViewportFrames (far: hazed floor, kelp, a minnow school
  and the Megalodon's shadow; near: swaying part-built kelp, the Nibbler, 'Cuda and
  Pufferfish swimming past with the SwimWave, a sardine school), light shafts, marine
  snow, rising bubbles, the APEX TIDE title with a shine (the logo once uploaded), and three how-to-play cards
  (EAT, BITE with the device's key, BANK). LOADING THE REEF until the fish has spawned
  and the state arrived (at least 2.4 s), then PRESS ANY KEY / BUTTON / TAP TO START
  (the device is read when the screen opens and changes only on real input of another
  kind: the Device Simulator turns its keyboard flag on ~2 s in).
  Any key (not Escape), click, tap or pad button dives in: the cameras rush ahead,
  bubbles burst and the water clears onto the fish in its den. `Input.locked` holds the
  fish still meanwhile; chat and the player list are hidden. Join-time UI waits with
  `StartController.afterStart`: the controls hint, WELCOME BACK, the Daily panel
  (1.5 s after) and a pop of the tutorial panel. Models come from `FishModels` /
  `PreyModels` (oriented by their main mesh), with ellipsoid fish while not imported.
- **Store page art (owner, 2026-10-09: "generate our page photo and some
  thumbnails"; built):** `marketing/` (committed) holds the files to upload: the icon
  (`icon_512.png`, the Nibbler fleeing a Megalodon's jaws; `icon_512_alt.png`), the
  keyed `logo.png`, and thumbnails 1–7 from generated key art (eat/grow hero, world
  bosses, the dark Trench, growth, rare shades, treasure maps, seven biomes); 8–10 come
  from in-game captures (`marketing/raw/shot_*.png`, taken by the PC session). Key art:
  Nano Banana Pro through the Tripo API (`tools/tripo_jobs_marketing.json`, 10 credits
  each) with reference sheets of approved concepts; the API returns 1024² only (an
  aspect setting is ignored), so scenes are painted in a letterboxed 16:9 strip, cropped
  and upscaled 2× with EDSR (`tools/marketing/compose.py refs | sr | (default) |
  shots`). All text is set by the script; the logo is keyed off magenta. Asking the
  model for "a calm corner for the title" paints a hard box into the scene. The list,
  the shot list and the description draft are in `docs/STORE_PAGE.md`. Uploading and
  making the experience public stay Connor's call.
- **Eating vs biting made clear (owner, 2026-10-09: "needs to be clear mechanics on
  how to actually bite fish ... are the other fish the same way or do they need to be
  eaten by hitting a bite key?"):** anything under ~70% of your length (prey, shrimp,
  starfish) is swallowed just by swimming into it, like shells; other players (never
  swallowed since 2026-10-20), AI predators and bosses take BITE (F / click, RB / X, the BITE button);
  prey too big can't be eaten (oversized ones chase you). Said on the start screen's
  cards, the tutorial's Eat step ("Swim into 10 small fish ... to swallow them"), the
  Haul card hint, the controls hint and `HintController`: a chip above the health bar
  (EAT until you've swallowed 3 things, BITE when a fish your size or a predator is at
  your mouth, DANGER near a fish that can swallow you, TOO BIG when a prey fish at your
  mouth is too big, `SchoolController.tooBig`), each capped per session with a
  cooldown, never in the hub or under a menu.
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
    paste the new id. **No bells (v2, owner 2026-10-11: "The music is horrible too
    that needs to be changed it's just random bells it sounds like"):** there was no
    music; the v1 hub bed pinged a glockenspiel at random pitches every 1–2 s (68% of
    its energy above 1.2 kHz), and Shell, Banner, UiOpen, Heal, Bank, GoldenShell and
    LevelUp rang glock or FM-bell notes. v2 beds are noise, drones and low plops; the
    everyday cues are soft marimba, clicks, bubbles and pads; only the roll and boss
    stingers keep bright notes. Until v2's id is pasted into `Config/Sounds` `id`, the
    v1 pack plays from `legacy` with its hub bed skipped (`Sfx` `pack`/`regionOf`).
  - **Music (owner, 2026-10-11; built):** `Config/Music.luau` + `MusicController`
    (ported from Hatch & Snatch). Lists by place: `hub`, each biome (`biomes` map),
    `trench` (the Trench's dark), and `megalodon`/`squid` while a boss is near
    (`BossController` → `MusicController.setBoss`). Roblox's licensed APM library
    only (uploader @APMOfficial), mostly David Lindsay's album "Underwater Kingdom"
    (Kelp Forest, Great Barrier Reef, Infinite Expanse, Endless Sonar, Mariana
    Trench, ...) so the sea sounds of a piece. A place must hold 4 s before its music
    crossfades in (no flip-flop on a border), a place revisited within 2 min resumes
    its track, a track that won't load is skipped, and it ducks under the roll
    reveal. Levels stay subtle: each track's measured loudness goes in `loudness`,
    and it plays at Volume = its list's `target` ÷ that. No mute button yet.
  - **Motion:** `Bubbles.luau` is the one bubble look (bursts and mouth streams);
    `BubbleController` streams bubbles off every fish's mouth by speed; vents and ~37
    seeps on the shelf and deep floor send bubble columns up (`WorldService`
    `bubbleColumn`); `KelpController` sways the kelp (in `World.Biomes.Kelp`) within
    120 studs of the camera (180 until 2026-10-20) (one BulkMoveTo a frame). It collects plants as they
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

- **Toon materials** (owner, 2026-10-16: "Walls need to look more like schedule 1 or
  how to fish graphics. Looks too much like garrymod textures or semi realistic for
  our purposes"): every stock material the world uses (Rock, Slate, Basalt,
  Sandstone, Sand, Mud, CrackedLava, Pebble, Marble, WoodPlanks, Wood) is swapped
  game-wide, Terrain and parts alike, for a flat cel-shaded seamless tile
  (`tools/textures/make_toon_materials.py` → `assets/textures/toon_<Name>.png`; big
  plates, bands and planks, bold seams, a lit edge, sparse flecks). Grey (R = G = B,
  mean ~0.8) so the world's own colours tint them; CrackedLava carries its own
  glowing cracks. Large smooth grey areas with soft curved lines scored up to 0.42
  on the classifier until the flecks layer went in: keep it in any new grey stone
  map, and screen before uploading (highest now 0.098). `Config/Materials` holds each
  image id (0 = stock), tiling and pattern; `tools/studio/make_toon_materials.luau`
  makes the `Toon<Name>` MaterialVariants and base-material overrides in Studio and
  the place is saved (a script can't set a MaterialVariant's maps; the dens' rock is
  a twelfth, Limestone, reusing Rock's image, since 2026-10-17); while one is on,
  `Cave.paint` lifts that Terrain colour ×1.22 (`terrainLift`) and the lava's to
  white. Parts come out a little darker. WorldService warns about a variant missing.
- **Rocks are rounded, toon-style** (owner, 2026-10-11: "rocks are also still a bit
  too unnatural and jagged. Needs more of a toonish rounded off look"): every tilted
  block of rock is a pebble of capsules (`Cave.pebble`: cylinders with ball ends
  along the box's long side, side by side across its middle, thinner at the edges),
  in the seamount's shelf rocks and cap, the reef's outcrops, ridges and arch tops,
  the kelp's sandstone ridges and the Trench's ledges; the terraces have rounded lips
  and filled inside corners, notches are round bites, drips are balls; only the
  round boulder model is used. Carves (Air), floors and the ruins stay blocks. Use
  `Cave.pebble` for any new rock.
- **The exits are open** (owner, 2026-10-11: "ensure all exits from the den are
  clear and open"): the seamount's foot was widened to 165 for the dens but the
  tunnels were still carved to 163, so all four were plugged at the mouth. They run
  to 195 now (`World.hub.tunnelLength` 76) with a flared mouth. After any change to
  `Cave.luau` or `Shelf.luau` run `DUMP_ONLY=1 LUAU=<luau> bash
  tools/preview/run_world.sh <dir>` then `python3 tools/preview/check_exits.py
  <dir>/world_ops.jsonl` (the tunnels, the 12 den doorways and the oculus; exit 1
  if any is blocked). The previews load `Config/Dens` too (Layout reads it; without
  it the dump was empty from 2026-10-08 to 10-11).
- **The hub cavern is Roblox Terrain** (owner: "needs to actually resemble a
  cave/cavern, not straight flat edges"). `src/server/Cave.luau` lists fill ops (a
  terraced seamount with faceted blocks, the carved cavern with a dome, bays, drips
  and a ragged oculus, 12 den rooms with round doorways, 4 tunnels, floors put back)
  and `WorldService.buildHub` applies them with `Terrain:Fill*`; material colors are
  `Cave.COLORS`. Only pools, lamps, signs, sconces, plaza, beacon and light shafts
  are still parts. Layout numbers are unchanged, so Layout/HuntService/FishService
  still agree. Preview from the cloud: `LUAU=<luau> bash tools/preview/run_cave.sh
  <dir>` (voxelizes the ops, marching cubes, Cycles on the CPU; no EGL here).
- **Solid props (owner, 2026-10-10: "Cant get this shrimp because of an invisible
  wall. And a lot of the coral i can go right through"):** `Props.dress` `solid`
  makes the imported model what fish bump into and turns the placeholder's
  collision off (a boulder's placeholder was a tilted box, an invisible wall round
  the rock; `blocksCamera` keeps the camera out of rocks too). Boulders and hard
  corals (brain, staghorn, fan, tube sponge) are solid; anemones and kelp stay soft.
  Kelp gives way instead (`KelpController`): a fish brushing a plant nudges it
  aside and drags it a little along its swim through a damped spring (it eases over
  and wobbles back, never flips across the stalk), and it fades, eased, when the
  camera is inside it. **The kelp glitch (owner, 2026-10-11: "The kelp and other
  floating attached items still glitch while they move"):** the sway records sat
  in a weak table keyed by the plant's Model, and Luau drops an Instance key
  whenever no script holds that Instance (the plant was still there), so every
  garbage collection re-rolled each plant's phase and dropped its lean: the forest
  snapped to new poses (the 2026-10-10 readings jumped 5° → 1° → 4° in 0.15 s).
  Records are strong now (pruned when a plant goes), the sway is seeded from the
  plant's position (the same after streaming), sway eases out over the last 50
  studs of reach (no freeze mid-lean or pop back in), and a tall plant's top moves
  at most 24 studs from a push.
- **Vendors (owner, 2026-10-08: "still just spheres with eyes"):** the five
  shopkeepers are models now, `vendors_glb` (`WorldProps.Keeper<VendorId>`): the
  hermit crab Outfitter, octopus Den Mason, sea turtle Tidecharm Trader, pufferfish
  Shade Dyer and "Scar", the scarred grouper Trophy Hunter, from the approved
  `assets/concepts/Vendors.jpg` (sheets `tripo_jobs_vendor_sheets.json`, models
  `tripo_jobs_vendor_models.json`, 200 credits). Balance ~1,360. **No brief had
  asked for them to be imported** (owner, 2026-10-11: "The vendors are still just
  spheres w eyeballs"; the PC imports them in the 2026-10-11 round): `WorldService.keeper` stands each on the
  plaza beside its counter at full height, facing the plaza (behind the counter only
  its head would show), solid; the ball and eyes behind the counter are only the
  fallback. Tripo props face +X in the GLB and Roblox turns a GLB half round on
  import, so the stall and keepers get `GLB_FRONT` (a quarter turn; the stall had
  stood side-on). Four keepers' textures failed the colour screen (salmon, peach,
  cream atlases), so `tools/props/safe_colors.py` moved those colours out (vivid
  orange, cool white, greige, darker browns) before `vendors_glb` v2 was hosted;
  screen every new prop's textures before it's uploaded.
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
      thin species sit closer (`Config/Species` `camera`). **Growth shows on
      screen** (owner, 2026-10-11: "ensure that player fish are actually getting
      bigger as they grow"; the distance had followed the length one for one): it
      frames the banked length to the power `camera.growFraming` (0.85) plus
      `growHaul` (30%) of a dive's live growth (`framedLength`).
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
    - `TutorialService`: nine steps since 2026-10-18 (the full loop). Finishing gives 50 shells and 500 coral and opens
      species select (the 'Cuda is earned since 2026-10-17).
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
  - Pearl crates, the Roblox group perk (id 0), pass and product icons
  - enforcing the speed checks (log-only until playtests clear them)
  - models for the growth stages and the other biomes; Tripo models for the
    exotic variants (they're part-built pieces on the mesh for now); caustics
    (needs a texture upload)
  - den items from bosses (jaw arch, Kraken-eye lantern) as Trophy Hunter buys
  - Pacing: ~2.1 h of active play to LV 100 a fish since 2026-10-20 (5 levels a full
    Haul in a fuller sea; ~4 h after 2026-10-19b; the owner found
    the 22 h curve too slow; see "Pace (2026-10-19b)"); if the late game proves too
    quick, grow late Hauls (more fish, more risk) rather than slow the early game.

## Playtests

- Reports go in `docs/playtests/` (`2026-10-06-pc.md`, `2026-10-06-pc-retest.md`,
  `2026-10-07-pc.md`, `2026-10-07-pc-retest.md`, `2026-10-07-pc-fixes.md`,
  `2026-10-08-pc.md`, which also covers the two world rounds before it,
  `2026-10-08-pc-retest.md`, `2026-10-09-pc.md`, `2026-10-09-pc-monetization.md`,
  `2026-10-09-pc-fixes.md`, `2026-10-09-pc-trench.md`, `2026-10-09-pc-start.md`,
  `2026-10-09-pc-boss.md`, `2026-10-10-pc.md` (boss see-through),
  `2026-10-10-pc-fixes.md` (walls, coral, kelp, food, cursor),
  `2026-10-10-pc-pullback.md`, `2026-10-11-pc.md` (skins v5, glints, light),
  `2026-10-11-pc-2.md` (vendor models, exits, rounded rocks, safe cave, no regen, item
  wheel, growth, skins v6, glints, haze, publish)
  `2026-10-13-pc.md` (dens v2: shafts plugged, Build mode, garden, map),
  `2026-10-14-pc-overnight.md` (the PvP round, snapping and layouts, codes, map
  image id; 12 fixes on `claude/core-systems`, not published: Publish As was
  refused by the PC session's permission check, so Connor publishes),
  `2026-10-14-pc-followup.md` (teeth v8.2 imported, Deep Pass id checked, F1–F10
  pass; Publish As refused again, "Create Public Surface": **Connor publishes,
  briefs no longer ask the PC to**), `2026-10-15-pc.md` (whale model imported,
  bait cap, sheen off teeth, screen base; chunks inside the whale, reef coral
  through it, the wheel chip full width), `2026-10-15-pc-2.md` (chunks clear,
  chips fit, the PC's level-sand fix; deep whales still faint at 70 studs),
  `2026-10-16-pc*.md`, `2026-10-17-pc*.md`, `2026-10-20-pc*.md` (the 2026-10-20 owner
  batch and its follow-ups, rounds 1–3, published v15 and v17; the PC tests, then publishes), `2026-10-19-pc*.md` (pace, Ruins, prey batches,
  den props; round 3's brief covers the world-and-life batch; that round the PC publishes and Connor tests himself), `2026-10-18-pc.md` (SK4, the plume
  marker, the Vents floor, effects and trails, phone text; AB1 and TR1 on two
  clients via Test → Clients and Servers);
  briefs for the PC session sit beside them as `*-brief.md`).
- A BillboardGui's `StudsOffsetWorldSpace` is in the adornee's own frame: on a part
  turned on its side (the garden's Sand cylinder) "up" goes sideways. Convert with
  `part.CFrame:VectorToObjectSpace(Vector3.new(0, studs, 0))` (2026-10-09).
- A game script can't read `SurfaceAppearance.ColorMap` (it needs Plugin
  capability, and the read throws); read `ColorMapContent.Uri` in a pcall
  (2026-10-09). `ContentProvider:PreloadAsync` on a folder of SurfaceAppearances
  fetches nothing (fetch status stays None); preload the texture ids themselves.
  Even by id, `PreloadAsync` returns once the downloads are queued (still
  `Loading`), not when they finish: poll `GetAssetFetchStatus` to know when one
  has arrived (retest 2026-10-09).
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
- **Which place file:** imports (skins, models) are saved into the local
  `ApexAbyss.rbxl`; the cloud copy only has what was last published from it
  (2026-10-10: the cloud copy, version 5, still had the v3 skins). Test and publish
  from `ApexAbyss.rbxl`. A published place's Studio session logs DataStore errors
  with Studio API access off; the weekly boards skip DataStores in Studio.
- On the owner's PC, Rojo for this game runs on **port 34873** until the stale Hatch
  & Snatch `rojo serve` on 34872 is closed. Never connect the plugin to the
  HatchAndSnatch project from this place.
- Keep Studio's Controller Emulator panel closed for keyboard tests.
- Custom fish character lessons: Roblox's `PlayerModule` is not inserted (so the
  move vector comes from `Input`), and ProximityPrompts never showed or triggered
  for it (so interactions use our own distance checks and hints).

- **Never key a weak table (`__mode = "k"`) by an Instance** unless some script
  also holds that Instance: Luau collects the key though the Instance still
  exists, and the entry is gone (the kelp's sway records, 2026-10-11).

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
- **Every Tripo GLB carries a normal map** (`NormalGL_*.png`, found 2026-10-13, in the
  props, prey and vendor bundles imported before the rule too): run
  `tools/props/strip_normals.py` on every Tripo model before it's bundled, then
  `safe_colors.py`, then the screen. Never re-import an older bundle that still holds
  one. **All seven older bundles were cleaned and re-hosted 2026-10-14** (manifest
  `sha256` and `clean` per bundle): FBX through `tools/props/fbx_strip_normals.py`, a
  byte-level edit that drops only the normal map's Texture/Video/connections (a
  Blender re-export rotated the body and changed the bind matrices), colour maps the
  screen flagged through `safe_colors.py` (MarketStall's canvas atlas scored 0.97 with
  the classifier) and back into FBX with `tools/props/fbx_swap_color.py`. Re-import a
  bundle only when its model needs replacing; the cleaned images would be new uploads.
- **Never upload a normal map** (2026-10-13): Roblox's moderation terminated the account
  over a flat lilac relief normal map that every check we have scored at zero. All the
  appeals were accepted within minutes, but the account itself took longer. Skin GLBs
  carry colour, glow and roughness/metal maps only; `screen_shades.py` flags anything
  shaped like a normal map. Appeal texts are in `docs/appeals/`.
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
