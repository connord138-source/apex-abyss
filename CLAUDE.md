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
- Division of work: Claude does the building (code and Studio). Connor does the
  playtesting and reports the Output window or screenshots.
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
    - It's built with the AI predators.
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
- **Monetization:**
  - **Second Chance:** keep your Haul when eaten.
  - **Double Haul** (the owner's idea): offered at banking above a minimum, one tap, no
    countdown. Small/Big/Huge versions by haul size. A rewarded ad doubles small hauls
    up to a cap. It doubles after other multipliers, and `lastHaul` in the save makes
    the receipt pay exactly once.
  - **Server Frenzy:** ×2 growth for the whole server.
  - **Passes:** VIP, ×2 Mass, extra den slots.
  - **Pearl crates:** odds shown before buying.
  - **Rule:** sell growth and safety, never bite damage.
- **Controls (owner, 2026-10-07):**
  - **PC stays as built** (the owner likes it): WASD swims relative to the camera (A/D
    slide sideways), the mouse aims, Space/C go up and down.
  - **Controller and phone** use the left stick as throttle and rudder: up swims along
    the aim (further is faster), sideways turns the aim, down brakes and backs up
    still facing forward. The right stick, or a drag on the screen, aims (up and down
    included).
  - **Phones get one stick** (it appears under the left thumb) plus BITE and DASH; the
    UP/DOWN buttons are gone.
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
- **Purchases:** `MonetizationService` owns ProcessReceipt (to be built).
  `DataService.processPurchase` grants once per PurchaseId and confirms after a save.
- **Remotes:** `src/server/Net.luau`. Client requests are rate-limited, and every
  argument is untrusted.
- **Loops:** wrap server loops in `Guard.loop` or `Guard.run`, so one bad record can't
  kill a loop for the whole server.
- **Service start order** in `init.server.luau` matters: each service connects to
  `DataService.loaded` inside its `start()`, and DataService starts last.

## Code map (graybox feel prototype, 2026-10-06)

- **Server** (`src/server/Services`):
  - `WorldService`: builds the graybox map (seabed and trench, surface ceiling, walls, hub ring with 12 dens, Haul Pools, 4 tunnels and the oculus, kelp, rocks, arches, coral, light shafts) and the base lighting. Gravity is 0.
  - `FishService`: custom fish characters (a ball collider `HumanoidRootPart`, a Humanoid with `EvaluateStateMachine = false`, and a `FishBuilder` body), den assignment, respawns.
  - `HuntService`: validates prey eats, player eats and bites; the Haul; banking at your own den's pool; the hub safe zone, spawn protection and healing. It also exposes `mouth` and `feed` for other food sources.
  - `ForageService`: starfish and shrimp spots (placed by raycast) and server-checked eats.
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
    `SwimController` swims the throttle along the aim and backs up on a pulled
    stick; `CameraController` turns the aim by the steer at the fish's turn rate
    (`camera.steerScale`).
  - `Spring`.
  - `Ui`: the design system (BuilderSans, palette, panels, bars).
  - `Controllers/`:
    - `SwimController`: momentum swim, banking into turns, the Dash (`dashCharge`), lunge.
    - `ForageController`: draws starfish and hopping shrimp, eats them with suction.
    - `CameraController`: the spring camera, mouse lock, wheel zoom. It pulls the
      look-at point out of rock, then limits the distance with a ray plus a swept
      near-plane-sized box. Never rely on a sweep alone: Spherecast/Blockcast ignore
      whatever they start touching (that let it through a den roof). Stopped by a
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
    - `BiomeController`: biome banner, level chip, under-level warning.
    - `HudController`.
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
      Shop", Y on a controller, tap on phones) shows within `Shop.hintReach` of a
      counter (`Layout.counterPosition`); there are no ProximityPrompts.
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
  - MonetizationService, Double Haul, the Robux Second Chance and Shell packs
  - chum clouds, Pods and the Apex bounty
  - boats and hooks, depth pressure
  - real models, audio, caustics (needs a texture upload)
  - server-side speed checks
  - The progression numbers are placeholders: one full dive banks about 16 levels.

## Playtests

- Reports go in `docs/playtests/` (`2026-10-06-pc.md`, `2026-10-06-pc-retest.md`,
  `2026-10-07-pc.md`).
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
