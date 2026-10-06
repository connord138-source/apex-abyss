# Apex Abyss — Game Design Document

Live title: **Apex Abyss 🦈 Eat & Grow**. The logo and brand say **APEX ABYSS**, and the
"Eat & Grow" tag is there so Roblox search finds it for "shark", "eat" and "grow".

Status: design locked with the owner on 2026-10-06 (brainstorm in the Hatch & Snatch
session). Numbers marked *tunable* are first guesses for the economy sim to settle.

## 1. Pitch

A third-person underwater eat-and-grow game. You start as a small fish, eat your way
up to an apex predator, and bank what you've grown at your den in a cave hub. Other
players are food too, but small players can school together and take down a big one.

**Reference:** the Fortnite UEFN fish maps trending in 2026: **"Be a fish"** by
civistudios (8865-1817-4348) and **"BE FISH 🐟 FISH SIMULATOR"** by ickrisp
(4918-1000-0196). In those you eat to grow, eat other fish, avoid big fish, dodge
fishing hooks and unlock rare fish. Apex Abyss adds the twists below.

The name was checked on 2026-10-06. No Roblox game or group uses "Apex Abyss" (Roblox
omni-search and the group lookup), and no game elsewhere does either. The nearest
neighbours are a Roblox diving game called "Abyss" and Apex Legends.

## 2. Pillars

1. **Fluid.** Swimming has to feel as good as Abzû's. Nothing pops: velocity, growth,
   the camera and the UI all ease.
2. **Extremely professional.** It needs one coherent art direction, a custom UI design
   system, and no default-Roblox look anywhere.
3. **Fair PvP.** It's always on, with protections, so being big never makes you
   untouchable and being small is never hopeless.
4. **Collection depth.** Creature lines, hard evolutions, finishes and mutations give
   players reasons to return for months.

## 3. Core loop: Hunt & Haul

*"Hunt & Haul" is the working name for the owner's approved Dive & Molt design; the
owner disliked "Molt" and this was the recommended replacement.*

- **Permanent progress:**
  - your level (XP), the stage of your creature line, the evolutions you've unlocked,
    your skins and your den
  - your level sets the size you start each dive at
- **A dive:**
  - Leave the hub and hunt. Everything you eat adds to your **Haul**, the mass you're
    carrying, and the Haul grows you **live**, up to a cap above your starting size
    (*tunable*, ~2×).
  - HUD: "HAUL 12.4k — swim home to bank it".
- **Banking:** swim back into **your own den** to bank the Haul, which turns into XP.
  The den's Haul Chamber upgrade raises the banking multiplier.
- **Getting eaten:**
  - You lose the unbanked Haul. It bursts into a **chum** cloud (§5) and the eater
    gains a share.
  - You respawn in the hub at your starting size, and your permanent progress is never
    lost.
- **Why this model:** each dive becomes a tense "go deeper or head home?" decision,
  the hub always has a purpose, and PvP has real stakes without rage-quit wipes. It
  also gives Second Chance and Double Haul (§9) clear value.

## 4. Eating rules

| Target's size vs yours | Result |
|---|---|
| under ~70% | swallowed whole: it's sucked into your mouth, never vanishes |
| ~70% to ~130% | a bite fight: both have health and bites take chunks |
| over ~130% | it can eat you |

- **XP scaling:** XP from eating another player scales with that player's size
  relative to yours, so a whale farming new players earns almost nothing.
- **Feel:**
  - The jaw snaps with a 2–3 frame hit-stop and a small camera kick.
  - A number pops up for the mass gained.
  - Growth eases smoothly.

## 5. PvP, protections and twists

- **PvP is always on in the biomes.** The hub plaza and every den are safe.
- **Spawn protection:** a few seconds after leaving the hub (*tunable*).
- **Size-gated terrain:** kelp, wreck holes and cave tunnels are too tight for big
  fish. Small fish hide there and eels ambush from them.
- **Chum:** a player who gets eaten bursts into a cloud of their unbanked Haul, which
  sets off a frenzy among everyone nearby (and NPC predators come for it too).
- **Apex bounty:** the biggest player on the server glows on everyone's sonar, and
  whoever brings them down earns the bounty.
- **Hooks from above:** boat silhouettes on the surface drop baited hooks. The bait is
  a big meal, but a hooked fish has to mash to break free, or a podmate can bite the
  line.

## 6. Teams

- **Schooling (the headline twist):**
  - Small players who swim close together form a school.
  - The school's combined mass can bite a predator bigger than any one of them.
  - It keeps the top player from snowballing, and teams form without any lobby.
- **Pods of up to 3:**
  - You can't eat a podmate.
  - Swimming in a podmate's slipstream gives a speed boost.
  - Kill XP is shared.

## 7. Creatures

- **Lines grow in stages:** Fry → Juvenile → Adult → Apex, by banked XP.
- **Hard evolutions** branch off at Apex and need a condition. They show as ??? in the
  Index until unlocked. Examples:
  - Great White → **Megalodon** (eat an Apex during a Blood Tide)
  - Giant Squid → **Kraken** (hold an Abyssal Pearl from the trench boss)
  - Moray → **Leviathan Eel** (reach a set depth)
  - Manta → **Void Manta** (requires a mutation)
- **Art:** the Sonaria-inspired style approved for Hatch & Snatch. Semi-realistic,
  natural proportions, **realistic eyes**, faceted models with smooth shading, each
  creature fused with an element: magma eel, ice orca, lightning jelly, void angler,
  geode crab, coral ray. The Hatch & Snatch art lessons apply (no cartoon eyes, no toy
  proportions, no matching poses; prompt with 2–3 approved references).
- **Rig:** a spine chain plus fin and jaw bones, with a procedural sine swim. That's
  far simpler than the quadruped legs in Hatch & Snatch. Tentacled lines (squid,
  jelly) add tentacle chains.

### Skins

- **Finishes:** Gold → Chrome → Diamond → Molten → Galaxy → Prismatic.
- **Mutations:** Albino, Melanistic, **Bioluminescent**, **Glass** (see-through) and
  Iridescent.
- **Where they come from:** a roll on every bank-up stage and evolution, plus Pearl
  Clams out in the biomes.
- **Paid random items:** exact odds summing to 100% are shown before buying.
- **Moderation warning (from Hatch & Snatch):** pale or pinkish unwrapped skin atlases
  got an account suspended. Screen every texture before upload.

## 8. World

### The seamount hub

A cave hub inside a central seamount. Its tunnels come out at different depths: the top
exits open into the shallows and the bottom exits into the trench, so **depth is
progression**.

- **The plaza** (safe) holds the Evolution Shrine, the Pearl shop, the quest board, the
  daily chest, leaderboards and the event board.
- **12 dens** are carved into the cave walls in a ring around the plaza, one per player
  slot. They're **safe** (no raiding), and every trip home passes everyone else's den.

### Biomes

| Biome | Levels | Signature life | Hazard |
|---|---|---|---|
| Kelp Shallows | 1–10 | minnows, seahorses, crabs | hooks from boats |
| Coral Reef | 10–25 | barracuda, moray | stinging anemones |
| Shipwreck Graveyard | 20–40 | groupers, eels in hulls | tight tunnels |
| Open Blue | 35–55 | tuna, sharks | no cover at all |
| Frozen Shelf | 50–70 | orcas, narwhals | brinicles |
| Hydrothermal Vents | 65–85 | magma creatures | scalding vents |
| Abyssal Trench | 80–100 | anglers, giant squid | darkness: you see only bioluminescence and sonar |

- **Depth pressure** gates biomes instead of walls: a fish below the biome's level takes
  crush damage that grows the deeper it goes.
- **The surface** is the ceiling of the map. Boats sit up there and drop hooks.

### Tide events (the role the Moon Egg plays in Hatch & Snatch)

- **Blood Tide:** bites hit harder and chum spawns everywhere.
- **Sardine Run:** a huge bait ball, so food floods in.
- **Whale Fall:** a dead whale sinks into a random biome and the whole server races to it.
- **Leviathan Rising:** a server boss everyone fights together.
- **Bioluminescent Night:** a dark sea, and glowing skins can drop.

## 9. Monetization

Rule: **sell growth and safety, never bite damage**, so PvP stays fair.

- **Second Chance** (developer product): keep your Haul when you're eaten. This is the
  top earner in eat-and-grow games. A rewarded ad can grant it too, since a fixed reward
  is allowed.
- **Double Haul** (developer product; the owner's addition):
  - **When it's offered:** on the bank screen, only when the haul is over a minimum
    size. It's one tap with a Skip button and **no countdown**.
  - **Pricing:** 2–3 versions by haul size (Small / Big / Huge), since Roblox products
    have fixed prices. The economy sim sets the cut-offs.
  - **Rewarded ad:** doubles small hauls up to a cap, and bigger hauls need Robux.
  - **Stacking:** it doubles the final banked amount, after Server Frenzy and ×2 Mass.
  - **Paying exactly once:** each banked haul is written to the save (`lastHaul`), so a
    receipt that lands late or after a rejoin still pays exactly once.
- **Server Frenzy** (developer product): ×2 growth for the whole server for a while,
  like Server Luck in Hatch & Snatch.
- **Game passes:** VIP, ×2 Mass, extra den slots.
- **Pearl crates:** paid random items, with an odds panel before buying.
- **Free rewards:** codes, a Roblox group perk, a Premium perk and rewarded ads.

## 10. Den

- **Haul Chamber:** raises the banking multiplier.
- **Trophy wall:** the jaws of your biggest kills.
- **Aquarium:** your collected skins swim around it.
- **Kelp or plankton farm:** passive income.
- **Dive buffs:** start bigger, swim faster, longer sonar range, deeper depth rating.
- **Den Designer:** the Castle Designer idea from Hatch & Snatch, with coral, crystal,
  magma, ice and bioluminescent themes, and the most wanted looks on a rebirth ladder.

## 11. Servers

12 players per server (owner, 2026-10-06).

## 12. Quality bar ("very fluid, extremely professional")

1. **Movement**
   - The fish has momentum and drag, and velocity never snaps.
   - Turn rate scales with size: small fish dart, big fish feel heavy.
   - The fish rolls into turns, and boosting is a tail-flick burst.
   - Your own fish runs on your device at full frame rate with no input lag; the server
     only checks it.
   - The spine ripples procedurally with speed, the head leads and the tail follows,
     and fins flare on turns.
2. **Camera:** spring-damped with lag, pulls back smoothly as you grow, and widens its
   field of view slightly on boost.
3. **Look**
   - Lighting is graded by depth: turquoise with light shafts in the shallows, then deep
     blue, then black.
   - Caustics ripple across the seabed, with drifting particles and bubbles throughout.
   - Every biome has one consistent palette.
4. **UI**
   - One design system: a custom font, custom icon art instead of emoji, and consistent
     spacing.
   - Every transition is animated with springs.
   - The dive HUD stays minimal: size, Haul, depth and a sonar ring. Full menus only
     open in the hub.
   - Console and mobile are fully supported from day one.
5. **Audio**
   - Underwater sounds are muffled, each biome has its own ambient bed, and bites sound
     bigger on bigger fish.
   - Music swells when a predator is near.
   - Levels stay subtle.
6. **Performance**
   - Target 60 fps on mid-range phones.
   - Distant fish use simpler models and skip skeleton animation.
   - Each creature gets a polygon budget, and frame time is profiled every milestone.

## 13. Technical approach

- **The ocean is faked.** There's no Terrain water anywhere. The underwater look is fog
  and Atmosphere, ColorCorrection graded by depth, caustic textures and particles. The
  custom 6-direction swim controller works the same everywhere and is fully under our
  control.
- **Your own fish:**
  - Its physics runs on the owning client (network ownership).
  - The server checks speed per size, bite reach and depth.
- **NPC fish:**
  - Schools follow shared, time-based paths from a seed, the same idea as Hatch &
    Snatch's belt eggs. Each client animates them locally, the server only validates
    eats, and eaten fish respawn on a timer.
  - This is the biggest technical risk, so it's prototyped first.
- **Growth:** `Model:ScaleTo` driven by an eased value. The mouth hitbox and camera
  distance scale with it.
- **Server authority:** XP, Haul, banking, purchases, kills and evolutions.

## 14. Roadmap

1. **Graybox feel prototype:** swimming, the camera, eating, growth, about 200
   client-side fish, a Haul and a bank pad, with no art. The owner playtests and judges
   only the feel.
2. **Look target:** concept art for the hub cave and Kelp Shallows, plus HUD and menu
   mockups, for the owner's approval.
3. **Vertical slice at ship quality:**
   - 1 biome and 1 creature line with 4 stages
   - the den
   - Hunt & Haul with Double Haul
   - PvP and schooling
4. **Content:** the remaining biomes, lines, evolutions, skins and tide events.

## 15. Open questions

- The final roster: lines per biome and which evolutions are hidden.
- The Pearl economy and what rebirth does.
- Every number marked *tunable*, settled by the economy sim.
