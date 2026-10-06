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
- **Creatures:**
  - Lines grow Fry → Juvenile → Adult → Apex.
  - Hard evolutions branch off at Apex with conditions and show as ??? in the Index
    (Megalodon, Kraken, Leviathan Eel, Void Manta).
  - Art is the Hatch & Snatch style: Sonaria-inspired, semi-realistic, realistic eyes,
    each creature fused with an element.
- **Skins:** finishes Gold → Chrome → Diamond → Molten → Galaxy → Prismatic; mutations
  Albino, Melanistic, Bioluminescent, Glass and Iridescent.
- **World:**
  - A hub cave inside a central seamount, with 12 safe dens ringed around a plaza.
  - Tunnels lead out at different depths, so depth is progression.
  - Biomes: Kelp Shallows, Coral Reef, Shipwreck Graveyard, Open Blue, Frozen Shelf,
    Hydrothermal Vents, Abyssal Trench.
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
