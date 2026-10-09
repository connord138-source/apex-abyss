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
- **How it's taught (owner, 2026-10-09: "needs to be clear mechanics on how to
  actually bite fish"):** swallowing needs no button (swim into it, like shells and
  shrimp); BITE (F / click, RB / X, the BITE button) is for fish your size, AI
  predators and bosses. The start screen's EAT / BITE / BANK cards, the tutorial's Eat
  step, the controls hint and short in-play hints (EAT, BITE, DANGER, TOO BIG) say
  so at the moment it matters.

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

### Species and progression (owner, 2026-10-06)

**Owner decisions:**

- **Everyone starts as the same small googly-eyed fish**, the starter (working name
  **Nibbler**).
  - A tutorial levels it up before any other species can be picked.
  - The starter stays upgradeable as it grows. It's the all-rounder: equal at
    everything, while the other species each specialize in a playstyle.
- **Every species levels up separately**, like Hungry Shark. More to grind and more
  playtime.
- **Every species has its own upgrade tree.** It has a few ability options to pick
  between, so each fish can be customized.
- **At least 4–5 playable species in the first version.** The shark, the pufferfish
  and the others are unlocked.
- **Biomes unlock species:** each biome's fish lead to a species you can play.
- **Two kinds of food:**
  - calm, relaxed fish to eat
  - aggressive AI predators (not players) that fight back and are worth more
  Every biome has its own fish.
- **Lots of rare color pulls and body-part changes.**

**Proposed by Claude and approved by the owner ("Love it!", 2026-10-06)**, with
these changes:

- The Nibbler's only ability is a small **Dash** that recharges (no options). It's
  built: Shift, Q or RT; the touch DASH button.
- A newly unlocked species starts at level 1 (tunable).
- The **safe zone** is the dens plus the vendor plaza. A banner says when you leave it
  ("LEAVING THE SAFE ZONE", with a protection countdown) and when you're back. Built.
- **Filler food:** starfish and shrimp on the seabed for low-level XP. Built
  (`Config/Forage.luau`).

The approved details:

- Six species at launch (the starter plus five specialists), each unlocked from its
  own biome.
- Tree points come from levels, and three abilities per species are picked in the
  tree.
- Rolled body parts are looks only; functional changes come from the species trees.
- A second concept round: `assets/concepts/SpeciesRoster` and `NibblerGrowth`.
- **Sunken Ruins approved** (owner, 2026-10-06) to replace Frozen Shelf.

| Species | Role | Unlocked from | Ability options (pick one in the tree) |
|---|---|---|---|
| **Nibbler** (starter) | all-rounder | start | **Dash only** (a short burst that recharges; its tree upgrades the Dash) |
| **Pufferfish** | tank / defense | Coral Reef | Puff Up (can't be swallowed 3 s) · Spike Burst · Toxic Cloud |
| **Moray Eel** | speed / ambush; slips through gaps | Shipwreck Graveyard | Strike (long lunge) · Burrow (hide in rock) · Shock |
| **'Cuda** (a barracuda; replaced the Squid, owner 2026-10-06) | speed / hit-and-run: the fastest straight-line swimmer, wider turns | Kelp Shallows (the tutorial's reward) | Torpedo (a long charged sprint) · Razor Bite (bites make the target bleed) · Silver Flash (blinds a target briefly) |
| **Reef Shark** | aggression / bite | Open Blue | Frenzy · Blood Sense · Ram |
| **Anglerfish** | lure hunter of the dark | Abyssal Trench | Lure (pulls prey in) · Lantern Flash (stun) · Deep Sight |

- **Per species:**
  - its own banked size, level (1–100), stages (Fry → Juvenile → Adult → Apex) and
    tree
  - base stats: speed, turn, health, bite and boost
  - a new species starts at level 1
- **Upgrade trees:**
  - Every level gives that species one Growth Point.
  - The tree has three branches (for example Speed / Toughness / Jaws); deeper nodes
    also cost coral.
  - Tree upgrades change the look too (bigger spikes, bigger teeth), so a build reads
    at a glance.
  - Respecs cost coral.
- **Unlocking a specialist:**
  - Swim to its biome (depth pressure needs a high enough level on some fish).
  - Collect that biome's **DNA**, dropped by its fish.
  - Pay a coral fee at the Old Hermit. His stall becomes the species shop: a hermit
    crab trading shells, which fits.
  - Account-wide upgrades (Fins, Gills, Jaw) move into the species trees.
- **Built 2026-10-06:**
  - per-species levels
  - graybox bodies for all six species
  - species stats on swimming, health and bites
  - DNA drops
  - switching in the safe zone, and DNA-plus-coral unlocks (the FISH menu)
  - the tutorial: steps 1–4 and 7 below, with markers
  Steps 5 (barracuda) and 6 (Growth Point) come with the predators and the trees.
- **The tutorial (about 5–8 minutes, as the Nibbler):**
  1. Swim out of your den.
  2. Eat 10 small fish.
  3. Bank your Haul.
  4. Pick up shells.
  5. Dodge a barracuda.
  6. Spend your first Growth Point.
  7. Reach level 10. Species select opens, and the 'Cuda unlocks as the tutorial's
     reward.
- **Body parts from rolls are looks only.**
  - Rolls will be sold for Robux (Shell packs), so functional rolled parts would mean
    paying to win PvP, and dozens of parts across six species couldn't be balanced.
  - Power comes from the species trees, which also show on the fish.
  - Exotic variants become species-specific (Shark: Hammerhead, Goblin; Puffer:
    Crowned; Eel: Ribbon; ...), so a roll never turns one species into another.

### The food chain (owner: calm fish plus aggressive AI predators worth more)

- **Calm fish** are schools and grazers on shared paths (cheap, as built now). They
  scatter a little when you charge them.
- **Aggressive predators:**
  - A handful per biome, simulated on the server and streamed to clients.
  - They patrol a territory, chase fish smaller than themselves, bite, and retreat when
    hurt.
  - Worth 2–3× their mass in Haul, plus DNA, coral and a shell chance.

| Biome | Calm fish | Aggressive predators |
|---|---|---|
| Kelp Shallows | krill swarms, minnows, sardines, kelp wrasse, sea turtle (big grazer) | barracuda, kelp crab |
| Coral Reef | clownfish, tangs, parrotfish, seahorses | lionfish (venom), ambush grouper |
| Shipwreck Graveyard | silversides, snapper, hermit crabs | moray (hides in hulls), giant grouper |
| Open Blue | tuna, flying fish, jellyfish (sting) | mako shark, swordfish |
| Abyssal Trench | lanternfish, hatchetfish, glass squid | gulper eel, viperfish, giant squid (mini-boss) |

- **The first version needs these five biomes** for the six species. Frozen Shelf and
  Hydrothermal Vents come later (orca, magma eel).
- **Model budget:**
  - Six species × 4 stages = 24 models.
  - About 25 calm and predator fish, plus the vendors.
  - At about 30 Tripo credits a model, that's roughly 1,500 credits. 1,450 were left
    after the concept rounds, so a top-up will be needed.

### Lines, evolutions and art

- **Lines grow in stages:** Fry → Juvenile → Adult → Apex, by banked XP.
- **Hard evolutions** branch off at Apex and need a condition. The Megalodon and the
  Kraken are world bosses, never playable (owner, 2026-10-06). They show as ??? in the
  Index until unlocked. Examples:
  - Moray → **Leviathan Eel** (reach a set depth)
  - Manta → **Void Manta** (requires a mutation)
- **Art (changed 2026-10-06):** stylized, chunky low-poly, like *Schedule I* mixed
  with *Abzû*.
  - Flat-shaded facets, bold saturated colors, readable silhouettes and simple eyes.
  - Small fish are cute and a little goofy; big ones are powerful and menacing.
  - The owner offered a Schedule I-style cartoony look, and Claude chose it: it stands
    out on Roblox, reads at a glance (size and threat), stays light enough for hundreds
    of fish on phones, and suits Tripo. It also keeps Apex Abyss looking different
    from Hatch & Snatch.
  - The first concepts are in `assets/concepts/`: StyleSheet, ShadeSheet, Vendors and
    HubPlaza. They are waiting for the owner's approval before any 3D conversion.
  - Element fusions (magma eel, ice orca, lightning jelly, void angler) still fit as
    themes.
- **Rig:** a spine chain plus fin and jaw bones, with a procedural sine swim. That's
  far simpler than the quadruped legs in Hatch & Snatch. Tentacled lines (squid,
  jelly) add tentacle chains.

### Rolls, shades and exotics (owner, 2026-10-06; built)

This replaced the finish and mutation plan.

- **Shells** are the roll currency.
  - 150 shell spots are spread over the Kelp Shallows, and 14 golden shells (worth 5)
    lie on the trench floor.
  - Every player has their own copy of each shell, so there's no racing. A shell you
    pick up comes back for you after 4 minutes.
  - Big prey sometimes carry 1–4 (`Config/Shells.luau`).
  - Shells are never lost when you're eaten.
- **50 Shells = 1 roll**, from the HUD's ROLL button. The reveal is a case-opening
  reel, and it lasts longer and lands bigger the rarer the result. Every card is a
  studio photo (owner, 2026-10-08: "photos for the rolls need to be dialed way up"):
  your own fish in the shade, lit, on a spotlit backdrop in the tier's color, with a
  nameplate, foil from Epic up and a holo edge from Mythic up (`CardPhoto`).
- **The roll table** (`Config/Rolls.luau`, `Shades.luau`, `Exotics.luau`;
  `Shared/RollOdds.luau`). Exact odds per roll, which add up to exactly 100%
  (`tools/tests/run_odds.sh`):

| Outcome | Tier | Chance |
|---|---|---|
| Coral: Handful 25 / Pouch 60 / Chest 150 / Jackpot 600 | Coral | 82.5% of a fresh fish's roll in all (70/22/6.5/1.5 of it); more as the fish collects shades |
| 8 commons (Seafoam, Sunset, Ink, Sandbar, Ember, Lilac, Moss, Ocean) | Common | 1 in 100 each |
| 6 bolder commons (Tiger, Bumblebee, Neon Tetra, Leopard, Rust, Toxic) | Common | 1 in 140 each |
| Lunar / Glowspot / Tidepool / Mandarin / Lanternfish | Rare | 1 in 120 / 160 / 180 / 200 / 220 |
| Diamond / Magma / Glacier / X-Ray | Epic | 1 in 250 / 300 / 320 / 350 |
| Divine / Aurora / Thunder | Legendary | 1 in 500 / 650 / 700 |
| Exotic / Prismatic / Nebula / Void | Mythic | 1 in 900 / 1,500 / 1,800 / 2,200 |
| Body parts: Angler Lure, Narwhal Horn, Sawblade Snout, Sail Fin, Veil Tail | Abyssal | 1 in 4,000 to 1 in 6,000 each |
| Exotic variants: Puffer, Hammerhead | Abyssal | 1 in 8,000 / 1 in 10,000 |

- **Luck:**
  - A Lucky Charm doubles every non-coral chance on the next roll.
  - Coral never drops below 50% of a roll.
  - The odds panel shows the luck that applies.
- **Duplicates** turn into coral: 120 for a tint, up to 12,000 for Prismatic and
  15,000–30,000 for an Abyssal outcome.
- **Announcements:** Rare and rarer results are announced to the whole server once
  the roller's reveal has landed.
- **Shades are real skins, each its own look (owner, 2026-10-08, asked twice: "much
  much more variance and depth than just a slight reshape to the existing colors"):**
  every shade is a texture made for each fish from its own texture (`tools/shades`),
  and no two share a pattern: foam rings, an ink wash, sand ripples, flames, lichen
  and trailing algae, velvet fuzz, rust flaking off gunmetal, poison-frog blotches,
  a cratered moon face, blinking spots, ripples, the mandarinfish maze, rows of light
  organs, cut facets, lava cracks, ice strata, a glowing skeleton, gold filigree,
  aurora curtains, lightning, a parrotfish mosaic, nebula gas clouds, an accretion
  spiral, Kraken skin.
  - **Surface depth:** every skin also ships a finish (matte, satin, wet gloss or
    mirror roughness), real metal where the shade is metal (Divine's gilding, Sunken
    Gold, Rust's iron, the Lanternfish's silver) and, for 14 shades, a glow map
    (SurfaceAppearance emissive; the Angler's lure glows in every skin).
  - **Living depth:** in game the glow moves: each glowing shade pulses its own way (a
    breath, a heartbeat, a flicker, a wave, blinking, lightning flashes, a scan), and
    shades shed their own aura (embers, frost, sparks, stars, motes, bubbles, ink),
    more of it the rarer the shade (`Config/Shades` `emissive`, `pulse`, `aura`;
    `Cosmetics`).
  - The fish's painted strokes, eyes, teeth and mouth are kept. 33 shades × 6 fish =
    198 skins, screened for moderation before upload and imported as
    `ReplicatedStorage.ShadeSkins`.
- **Shades are per fish (owner, 2026-10-08):** a shade works on every fish, but each
  fish unlocks it for itself, and once a fish has a shade it never rolls again for
  that fish (its chance goes to coral; the odds panel shows that fish's table).
- **Wearing them:**
  - Shades are owned per fish; parts and variants per player. Worn from the Wardrobe
    or straight from the reveal.
  - A fish wears one shade, one variant and one part per slot (Head, Back, Tail).
  - The server sets the character's Shade, Parts and Variant attributes, and every
    client dresses the fish from them (`Shared/Cosmetics.luau`).
- **Adding more:** new shades and exotics are table entries (plus geometry in
  Cosmetics), and the odds re-balance themselves.
- **Paid rolls (later):** Shell packs, sold with the odds panel shown before buying and
  hidden for `ArePaidRandomItemsRestricted` players.
- **Moderation warning (from Hatch & Snatch):** pale or pinkish unwrapped skin atlases
  got an account suspended. Screen every texture before upload.

### Treasure maps (owner, 2026-10-07; built)

The owner's ask: "treasure maps players randomly earn... a map to a location where
they dig up a treasure for a random reward, whether a large kelp haul or a super rare
skin at a low drop rate. Like clue scrolls in RuneScape. Only the player holding the
map can uncover it. The map is in their inventory."

- **Getting one:** prey carry a chance that scales with their mass (a Minnow ~0.06%,
  a Grouper 4.5%); every shell 1.2%, a golden shell 12%; banking a Haul of 4 kg or
  more 4%. You hold at most 3; more don't drop until one is dug up. A found map is
  followed automatically if nothing else is.
- **Tiers:** Tattered (170–460 studs from the hub), Weathered (460–830), Captain's
  (700–1,150, out past the drop-off onto the deep floor). Small prey and plain shells mostly give Tattered;
  big prey, golden shells and big banks skew to Weathered and Captain's.
- **The satchel** (MAPS on the wallet row): each map with its tier and a hint ("About
  320 studs north-east of the hub, among the boulders"), FOLLOW/STOP, the treasure
  tally, and what each tier's chest can hold with exact odds.
- **The hunt:** following a map puts a sonar card on the HUD: a ring beats faster the
  closer you get and reads FREEZING → COLD → WARM → HOT → BURNING (plus ABOVE/BELOW).
  Inside 150 studs an arrow points the way; inside 45 an X glows on the seabed that
  only the holder sees (the site lives in the holder's own state). Hold E (Y on a
  pad, DIG on touch) on the X for 2.5–3.5 s, with a progress bar and sand kicking up.
  The server checks the map is the digger's and that they're really at the X, at the
  start and the end of the hold.
- **The chest** opens through the roll reveal, with that tier's loot on the reel.
  Weights per tier are in `Config/Treasure.luau`: coral hoards (120/320/900), shell
  caches (15/35/60), a Kelp Haul worth 1.5/2.5/4 levels dumped straight into the dive,
  a DNA vial for the biome dug in, a Lucky Charm, a Shade Roll (Rare+ from Weathered,
  Epic+ from Captain's), and only in Captain's chests the treasure-only shades
  **Sunken Gold** (Mythic) and **Drowned Pearl** (Legendary) at 3% each. Duplicates
  refund coral. Epic+ shade finds are announced to the server.
- Later: map tiers in the other biomes (Reef, Wreck, Trench sites), riddle-style
  clues for Captain's maps, a treasure-hunter title at 25 finds.

### Coral and vendors (owner, 2026-10-06; built)

- **Coral** is the currency.
  - **Earned from:**
    - Rolls: about 45 coral a roll on average.
    - Banking a Haul: 6 × √kg banked.
    - Eating players: 20 × the size-ratio penalty.
    - Duplicate refunds.
  - **Spent at** four vendors' stalls round the hub plaza, close to every den. Swim up
    and press E (Y on a controller):

| Vendor (keeper) | Sells |
|---|---|
| **Fin & Gill Outfitter** (Old Hermit) | 5-level upgrades: Strong Fins +4% speed, Deep Gills +12% boost, Shell Sense +20% pickup reach, Iron Jaw +6% bite. 150–11,000 coral a level. |
| **Den Mason** (Octavio) | Haul Chamber: +6% to every banked Haul per level, 300–15,000 |
| **Tidecharm Trader** (Old Tortuga) | Lucky Charm 800 (hold 3), Second Chance 1,200 (keep your Haul once), Shell Magnet 250 (×2 reach, 10 min), Feast Charm 400 (+25% Haul, 10 min); 10 Shells for 400, 5 times a day |
| **Shade Dyer** (Puff) | The 14 common shades at 1,500 each, previewed on your fish. Rare shades only come from rolls. |

- **Later ways to spend coral:** den decor and the Den Designer, riptide currents
  (fast travel), bounties, and coral-only cosmetic rolls.

## 8. World

### How the world gets built (plan, 2026-10-06)

The world isn't generated as one AI scene. AI 3D tools make single objects (around
8,000 faces each), and one huge mesh couldn't collide, stream or run well on phones.
Instead it's built in four layers:

1. **Landforms: Roblox Terrain sculpted by code.**
   - Each biome has its own seeded generator: dunes and rock fields, reef shelves and a
     lagoon, a wreck valley of mud and canyons, an open-blue cliff edge falling into the
     void, the trench's chasm and caves, ice shelves, volcanic vents.
   - Each biome gets its own terrain materials and colors: Sand; Limestone and Pavement;
     Mud and Ground; Rock; Slate and Basalt; Glacier and Snow; Basalt and CrackedLava.
   - It lives in git, rebuilds the same every time, and is previewed from the cloud (top
     and side renders, as Hatch & Snatch's island previews were).
   - It can also be baked into the place file in Studio so servers start faster.
2. **Hero props: Tripo models**, about 6–8 per biome:
   - Kelp: giant kelp, boulders.
   - Reef: brain coral, fan coral, tube sponges, anemones.
   - Wreck: hulls, masts, anchors, cannons, lanterns.
   - Open Blue: a whale skeleton, cliff chunks.
   - Trench: crystals, tube worms, giant ribs.
   - Frozen Shelf: ice spires, brinicles.
   - Vents: black smokers.
   Code places them by per-biome scatter rules, reusing each with rotation, scale and
   tint. Graybox stand-ins show until a model is imported (the Hatch & Snatch
   `Props.luau` pattern).
3. **Atmosphere per biome:**
   - fog color and density, light, color grade and caustics
   - particles: sun shafts and spores; bright bubbles; murky silt; open-water rays;
     bioluminescent plankton; ice crystals; embers
   - an ambient sound bed
   OceanController blends between biomes by where you are, not only by depth.
4. **Layout:** the hub seamount sits in the middle, with biomes as sectors around and
   below it (like the Hatch & Snatch island ring):
   - Kelp Shallows ring the hub near the surface.
   - Coral Reef is east, Shipwreck Graveyard west, and Open Blue north (a drop-off into
     open water).
   - Abyssal Trench is south and deepest.
   - Sunken Ruins and Vents come later; Frozen Shelf is dropped for now.
   Each sector is about 800 studs across, with blended edges, and depth pressure gates
   the deeper ones. StreamingEnabled comes on for the big map (phone memory), and props
   get level-of-detail.

**Look targets:** `assets/concepts/Biome*.jpg`, one per biome. The owner approved the
looks and the layout on 2026-10-06, as long as areas are gated by suggested level.

- **Frozen Shelf is dropped for now** (owner: "I don't see much sealife being there").
  It may come back in an update.
- **Its replacement is the Sunken Ruins:** an ancient sunken city teeming with
  octopuses, rays and groupers (`BiomeSunkenRuins.jpg`, proposed).
- **Level gating:**
  - Every biome has a suggested level range (`Config/Biomes.luau`).
  - Entering a biome shows its name and levels.
  - Entering one above your fish's level shows a red "TOO DANGEROUS FOR NOW"
    warning: your fish's level, and to come back stronger.
  - A chip under the depth gauge shows where you are. Built (`BiomeController`).
  - Depth pressure (damage when far too deep) can come on top later.
- **Sectors** (degrees round the hub, 0 = east):
  - Kelp Shallows ring the hub out to 420 studs.
  - From 420 to 1,100 studs: Coral Reef east, Abyssal Trench south, Shipwreck
    Graveyard west, Open Blue north.
  - Later, from 1,100 to 1,600 studs: Sunken Ruins beyond the Reef, Hydrothermal Vents
    beyond the Trench. The
vents concept shows open flames, which can't happen underwater; it'll use glow and
embers instead.

**Tripo budget** (2,450 credits after the owner's top-up; 2,380 after the biome
concepts):

| Item | Count | Credits |
|---|---|---|
| Species models (6 × 4 stages) | 24 | ~720 |
| Calm fish, predators, filler food | ~28 | ~650 |
| Vendors | 4 | ~120 |
| Biome hero props (5 biomes × 7, text-to-3D) | ~35 | ~700 |
| Total | | ~2,190 (leaves ~190 spare) |

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
| Sunken Ruins (replaces Frozen Shelf) | 50–70 | octopuses, eagle rays, groupers | collapsing arches, tight doorways |
| Hydrothermal Vents | 65–85 | magma creatures | scalding vents |
| Abyssal Trench | 80–100 | anglers, giant squid | darkness: you see only bioluminescence and sonar |

- **Depth pressure** gates biomes instead of walls: a fish below the biome's level takes
  crush damage that grows the deeper it goes.
- **The surface** is the ceiling of the map. Boats sit up there and drop hooks.

### World boss events (owner, 2026-10-06)

Owner: "a giant squid that roams the map as well, they could be world events."

- **Bosses are world events, not permanent residents:**
  - About every 30 minutes, one boss rises and is announced to the whole server two
    minutes ahead.
  - It roams its home waters until it's killed or gives up and leaves (about 15
    minutes).
  - The two bosses take turns, so there's always a reason to come back.
- **The bosses:**
  - The **Megalodon** roams the Open Blue (below).
  - The **Giant Squid** rises from the Abyssal Trench and the deep edges (below).
- **"Leviathan Rising"** in the tide events becomes these boss events.

**Boss rules (owner, 2026-10-07):** "designed to be taken on as a team, very hard but
not impossible to defeat solo; attacks and separate phases; different attacks for
different bosses; solo in 8–10 minutes is fine; nothing should be one-shot; a healing
element players can use in boss fights, PvP and PvE; no minions in boss fights yet;
cartoonish Schedule I vibes, but the undersea horror aspect for the bosses."

- **Team-first, soloable:** health scales with attackers but not one for one. Base
  health is tuned so a maxed solo fish wins in about 8–10 minutes of clean play; each
  extra attacker (anyone who hit it in the last 20 s) adds +60% health, so teams
  finish faster per head and solo stays possible.
- **Solo is hard because of survival, not damage:** every attack has a 1–1.5 s tell
  (visual, sound, HUD) and one correct answer. Alone you must answer all of them; a
  team takes turns.
- **No one-shots.** Boss damage is a share of the victim's max health, so two
  mistakes in a row kill and a heal buys a third: Megalodon bite 55%, charge 35% plus
  knockback, tail sweep 20% plus knockback, breach shockwave 30%; Squid grab 15% per
  second held (up to 4 s), beak slam 45%, siphon blast 25% plus knockback. Being
  killed by a boss costs the Haul like any death; Second Chance applies.
- **Soft spots and Schooling:** gills, eye and tentacles take double damage, and
  Schooling pools the mass of fish within ~20 studs, so six juveniles bite like one
  adult. A **stagger meter** fills from soft-spot hits; full, the boss stalls 4 s with
  its weak point wide open. Teams earn staggers; solo players get the same windows
  from phase changes.
- **Escape clock:** it roams 15 minutes and dives to escape at low health; finish it
  or it heals and leaves.
- **No minions** (owner): the fights are the boss alone, for now.
- **Look:** stylized and chunky like everything else (the concepts already are), with
  the horror in the presentation: the water darkens and loses color within ~300
  studs, the music drops to a drone and a heartbeat, you see a silhouette through the
  murk before the body, eyes and suckers glow in the dark, the camera shakes as it
  passes, red APEX PREDATOR tags, "SOMETHING STIRS BELOW". Menace from scale, light
  and sound; no gore.

### Den bases (owner, 2026-10-07; v1 built)

"I was also envisioning the dens being an upgradable base that gets bigger and
deeper as it upgrades. Other players can go in and check out your base but can't
take or do anything. You can display trophies from large fish killed/bosses killed
and set up furniture so that it's your den. Upgrades and furniture/colors would cost
currency. Coral lamps, etc."

- **Levels:** Nook (start) → Burrow (2,500 coral: the room runs 6 studs further back,
  two wall spots) → Hall (12,000: 12 back, a chamber 10 deep under the floor, three
  chamber spots) → Grotto (45,000: 18 back, the chamber 14 deep and wider, two more
  wall spots and one chamber spot). The sign reads "<NAME>'S GROTTO".
- **Furniture:** 12 spots in all (4 floor, 4 wall, 4 chamber). Fourteen pieces, 150 to
  1,200 coral, bought once and moved freely after: Coral Lamp, Kelp Bed, Shell Pile,
  Anemone Garden, Brain Coral, Tube Sponges, Driftwood Table, Pearl Pedestal,
  Treasure Chest, Bubble Column, Crystal Shard, Sea Glass Lantern, Sea Fan, Banner.
- **Colors:** a glow color for the den's lamps, banners and trophy trims: Teal free,
  Gold, Rose, Violet, Lime, Ice and Ember 300 each.
- **Trophy wall:** three plaques on the back wall fill themselves: BIGGEST CATCH (the
  heaviest prey ever eaten, its model mounted above), MEGALODON (teeth taken) and
  GIANT SQUID (beaks taken); the worn title hangs over the door.
- **Visiting:** anyone can swim into any den (dens stay safe zones) and look; only the
  holder can bank there or change anything.
- Later: free placement, den items won from bosses (the jaw arch, the Kraken-eye
  lantern), more pieces and themes.

### The shelf layout (owner, 2026-10-07; built)

The owner: "biomes need to be spread out and clearly different biomes with some
dependent on depth off of a ocean shelf that would be at the end of the lower level
zones and begin the higher level zones. coral zone being the last of the shallower
zones." As built (`Config/World.luau`, `Config/Biomes.luau`, `Shared/Seafloor.luau`,
`src/server/Shelf.luau`):

Scaled up 2026-10-08 (owner: "the entirety of the map is still too small ... each
biome made larger ... MUCH MUCH more depth too. Far too shallow of a map"; "the lower
areas are far too underdeveloped"; the reef "just a bunch of scattered coral"; the
Open Blue "a large black wasteland"): the map's radius went 1,000 → 1,500, the surface
300 → 440 over the shelf, the deep floor −170 → −430, the Trench floor −420 → −920.

- **The shelf** (radius 850, sand at 0, 440 studs under the surface): the Kelp
  Shallows ring round the hub (150–480, LV 1–10; open sand, kelp forests, boulder
  fields, arches: the open biome by design), the Shipwreck Graveyard in the west bay
  (480–850, 135–225°, LV 10–25; fourteen listing hulls, dark rocks, kelp fringe), and
  the Coral Reef as the outer band everywhere else (LV 25–40; 44 reef heads with
  tunnels bored through and hollows under them, 14 long reef ridges with
  swim-throughs, 26 big stone arches, reef flats, and corals growing on and round
  every one of those rocks plus 60 gardens between). It ends at the **drop-off**, a
  90-stud rock cliff 430 studs tall with bulges, bays, notches, buttresses, ledges and
  eight sand chutes down to the deep floor at −430.
- **Below the drop-off** (850–1,500 out): the Open Blue north (LV 35–55; deep blue
  water over a blue-grey floor with ridges, knolls and seven rock pinnacles up to 280
  tall; shark water: the Reef Shark predators and the shark, grouper and snapper
  schools live here, and the Megalodon patrols it), the Sunken Ruins east (50–70;
  mounds, column stubs, broken walls, temples with statues and teal lanterns, and a
  temple ring), the Hydrothermal Vents south-west (65–85; ten basins sunk to −540
  with 26 basalt chimneys, glowing caps, black smoke), and the **Abyssal Trench**
  south (80–100): a winding canyon 440 long and 210 wide at the floor, three stepped
  cuts from the rim at −430 down to −920 (`Seafloor.trenchAxis`), slate rims, bitten
  walls, ledges, basalt pillars, 130 bioluminescent specks, and pitch dark unless you
  carry a light.
- The map's wall is at 1,500; the seafloor runs 700 further so it fades into the
  water. The deep floor is a 30-stud mud slab with rock only under the canyon and
  the basins, and the shelf is a hollow drum, so the Terrain stays light at this size.
- **Visibility by depth** (`OceanController` grades): the water thickens and darkens
  from the surface (sight ~420) to the shelf (~300), the deep floor (~210) and the
  Trench (~120), so no depth ever sees every other; the deep floor is deep blue, never
  black. The sky and surface look belong to the other (PC) chat.
- **Prey zones** (`Config/Prey` `zones`): a prey can list several places (band,
  sector, school count, depth); predators can keep to a sector (`angles`).
- `Seafloor.y(x, z)` is the nominal floor height anywhere; schools, shells, forage,
  treasure sites, predators and bosses all place from it (heights are above the local
  floor), so the layout numbers live in one place.
- Preview: `bash tools/preview/run_world.sh <dir>`.

### Light in the dark (owner, 2026-10-07; built)

"Clearly need a light source for abyssal trench too which needs to be noted to the
player ... That could be the perk of the angler fish." The Trench is `dark`: below the
deep floor the light goes out (no sun, ambient or reflections), so all you see is what
glows or is lit: your lamp's pool of light, glowing shades, the plankton, the glow
clusters on the canyon walls, and the bosses' own eerie glow (playtest 2026-10-08:
done with fog and exposure instead, it was pure black even with a lantern). The Anglerfish's lure is
a lamp (its species perk), and the Tidecharm Trader sells a Deep Lantern (350 coral,
10 minutes). Lamps light the dark for everyone round the fish. The biome banner and
chip warn PITCH DARK · bring a light.

**Deep bioluminescence (owner, 2026-10-08: "deepest depths should have light
luminescense such as photoplankton etc to give very very faint light"; built).** Below
the shelf the water holds glowing plankton: faint blue-green specks twinkle round you,
thickening from the drop-off's foot to the Trench floor, and any fish swimming through
leaves a brief sparkling wake, the way real plankton flashes when disturbed. Patches
of glowing plankton sit on the deep floors (Trench, Vents, Open Blue, Ruins), and the
pitch dark gets a very faint teal light.

**A little light to see by, and lights by rarity (owner, 2026-10-09: "players need at
least a bit of visibility ... there should still be about 5-10% visibility with no
light, and visibility with a light source scales with how rare the light source is";
built).** With no light the Trench keeps a dim blue ambient (about 10%, more where the
plankton is thick) and a very deep blue haze, so rock walls and fish read as dim
shapes. Glow gardens (clumps of glowing tube anemones, each casting a pool of light)
are scattered along the canyon floor, every plankton patch there is lit, and the wall
clusters still glow. A light source lights further and clears more of its holder's
view the rarer it is:

| Source | Range | Holder's view |
|---|---|---|
| Common glowing shade (Ember, Ink, Neon Tetra) | 18 | 5% clearer |
| Deep Lantern (350 coral) | 30 + beam | 10% |
| Rare glowing shade | 28 | 10% |
| Epic glowing shade | 36 | 16% |
| Anglerfish lure (Trench species) | 46 + beam | 24% |
| Legendary glowing shade | 48 | 26% |
| Mythic glowing shade | 60 | 34% |
| Boss trophy / Abyssal shade (Ghost, Abyss Ink) | 60 | 38% |

A fish uses its best source, and everyone round it sees its light. A glowing shade's
light comes up as the water darkens (it's a skin, not a lamp), measured before its
holder's own light clears the view, and deep colours (violet) are brightened so they
light as much as their tier says. `Config/Tuning` `light`.

### Healing (owner, 2026-10-07; built)

"We need a healing element for players that they can use for boss fights as well as
PvP and PvE fights."

- **Kelp Wrap** (consumable): heals 40% of max health over 4 s, 18 s cooldown, carry up
  to 5. Using one is a 0.6 s wrap (the fish glows green) and you swim 30% slower while
  it heals, which is the counterplay in PvP: the attacker can catch you. Hotkey H on
  keyboard, LB on a pad, a HEAL button on touch.
- **Sources:** glowing medkelp fronds in the kelp forests (eaten like forage, one wrap
  each, per player, back in 2 min), the Tidecharm Trader (120 coral, "safety" is
  sellable), an occasional drop from prey, and a stack of three in Tattered and
  Weathered treasure chests. Never sold for Robux (the rule: growth and safety for
  coral, never bite damage).
- **Eat to heal:** eating prey heals 2% plus 0.5% per kg, so snacking on the schools
  around a boss arena matters in a long fight.
- The den and the plaza keep their full regen.

### AI predators (built 2026-10-07)

The owner's "aggressive AI predators worth more" are the base the bosses stand on.
`Config/Predators.luau` lists them; `PredatorService` simulates them on the server
(10 Hz) and streams positions to every client, which interpolate them.

- **Barracuda** (9 studs, 140 hp, 3 alive, 220–400 studs out, 8–90 deep): fast, bites
  20% of max health every 2.2 s after a 0.9 s tell; ignores fish under a quarter of
  its length unless they bite it. Loot 6 kg Haul, 3 DNA, 40 coral.
- **Reef Shark** (14 studs, 320 hp, 2 alive, 300–420 out, 10–110 deep): slower, bites
  30% every 2.8 s after a 1.1 s tell. Loot 18 kg, 6 DNA, 120 coral.
- **Behaviour:** roam waypoints in their band; hunt the biggest worthwhile fish in
  aggro range (not safe, not in the hub), leading it a little; inside bite reach the
  jaw flashes red for the tell (the target's screen says INCOMING), then the bite
  lands if the fish is still in reach, else it coasts past and comes round. A
  provoked predator chases 1.7× further.
- **Fighting back:** the bite button on a predator in reach bites it for
  `biteDamage × (your length ÷ its length)^1.5` (clamped 0.08–1.2), ×(1 + 0.35 per
  other player who bit it in the last 2.5 s), × upgrades and species. Everyone who
  dealt damage gets a share of the loot (at least 10%; the killer +10%).
- **Respawn** 90 s / 150 s after a kill, somewhere else in the band.

### World boss: the Megalodon (owner, 2026-10-06; built 2026-10-07)

The owner asked for "a massive megalodon that roams the map, mostly in deep blue.
Killing it rewards something extreme but it is a very hard and scary boss." The
details below are Claude's proposal (concept: `assets/concepts/Megalodon.jpg`).

- **Size:** about 80 studs long, bigger than any player can grow, so every player is
  food to it.
- **Where it roams:**
  - A long patrol through the Open Blue, sometimes sweeping the edges of the Reef and
    the Wreck.
  - It never enters the hub or the Kelp Shallows ring. Shallows players can still see
    its silhouette pass along the edge.
- **Dread before you see it:**
  - Within about 300 studs, a low drone and a heartbeat swell under the music, and the
    water darkens.
  - A HUD warning, "MEGALODON NEARBY", points toward it.
  - The camera shakes as it passes, and its tag reads APEX PREDATOR in red.
- **Danger:**
  - Its bite takes 55% of any fish's max health (owner, 2026-10-07: nothing is a
    one-shot); two bites kill, a Kelp Wrap buys a third.
  - It hunts the biggest fish around and mostly ignores tiny ones, so small players
    can school round it. That's the headline twist.
- **The fight** takes the whole server:
  - Its health scales with how many players are attacking.
  - Bites hurt it, the school bonus applies, and its gills and tail take double
    damage.
  - Every attack is telegraphed: its jaw opens with a red glint before a bite, and its
    eyes flash before a charge.
  - Three phases:
    1. **Hunting** (100–60%): **Charge** (eyes flash red, a straight rush at the
       biggest fish nearby; dodge sideways or up) and **Bite** (the jaw opens with a
       red glint, a short lunge).
    2. **Frenzy** (60–25%): faster. **Tail sweep**, a 360° knockback when three or more
       fish bunch behind it, so nobody stacks. **Blood cloud** hides it; only sonar
       pings show where it is. **Marked for death**: it locks onto the biggest fish
       for 8 s with repeated short charges; the mark breaks when the stagger meter
       fills, so the team's soft-spot hits save that player. (No minions, owner.)
    3. **Last stand** (under 25%): it dives for the Trench on a 60 s clock. **Breach**:
       it rockets up and crashes down with a shockwave ring (go vertical to dodge),
       then lies exhausted 5 s with its gills glowing at triple damage, the solo kill
       window. Catch it before it escapes, or it heals and comes back later.
- **Rewards** (owner, 2026-10-06: no playable Megalodon; "specific skins unlocked from
  beating them... a pale green ghost skin or a certain item for their base. The reward
  needs to be something worth fighting it for"). Everyone who dealt at least 1% of the
  damage gets:
  - **Megalodon Teeth:** 1 each, plus 1 for the top three and 1 for the killing bite.
    The Teeth buy its trophies at the **Trophy Hunter**, a fifth stall in the plaza, so
    dedicated hunters always get there.
  - **Trophies:**
    - the **Ghost** shade: pale green, see-through and shimmering (built in
      `Config/Shades.luau`)
    - a Megalodon Jaw body part
    - a giant **jaw arch** for your den's entrance
    - a mounted tooth for the trophy wall
  - **A chance at a trophy straight from the kill** (about 1 in 15, doubled for the top
    damage dealer).
  - A huge Haul you still have to carry home, a coral jackpot (5,000+), a
    Rare-or-better roll, and a Megalodon Slayer title.
- **Tech:** a server-simulated boss on the same system as the aggressive predators
  (positions streamed about 10 times a second, clients interpolate, attacks checked on
  the server). It gets one hero Tripo model with the procedural spine swim. It's built
  alongside the predators and the Open Blue.
- **As built (2026-10-07, `Config/Bosses.luau`, `BossService`):** the event clock
  raises it every 30 min (4 in Studio) with a 2 min warning; it patrols the Open
  Blue (north, 330–620 studs out, 25–170 deep) and hunts the biggest fish within 200
  studs, ignoring fish under 3.5% of its length. 6,000 hp, +60% per attacker beyond
  the first (anyone who bit it in the last 20 s). Phases at 60% and 25%. Charge: 1.2 s
  eye flash, then 2.2 s at ×2.2 speed, 35% to anything within 13 studs of its body,
  9 s cooldown, used from 35–170 studs. Bite: 1.2 s jaw tell, 55%, 4 s cooldown.
  Frenzy: ×1.3 speed, a 10 s blood cloud (its tag hides), Tail sweep when 3+ fish are
  within 40 studs behind it (1 s tell, 20%, a 60 stud/s shove, 12 s cooldown), Marked
  for death every 24 s (8 s, ×1.45 speed at the mark, a 0.5 s-tell lunge every 2.2 s
  for 25%). Last stand: a 60 s clock toward the Trench, a Breach every 13 s (2.2 s
  tell as it sinks, 1.3 s rocket, 0.9 s crash, a 48 stud ring 30% + shove to fish
  within 16 studs of its depth, then 5 s exhausted at triple damage). Soft spots:
  gills (60–80% along the body) and tail (0–22%) take double damage and fill a
  700-point stagger meter; full → 4 s stagger at triple damage (18 s cooldown), which
  breaks the mark. Rewards for everyone with ≥1% of the damage: Teeth 1 (+1 top three,
  +1 killer), Haul 120 kg by share (min 10%), coral 5,000 by share (min 500), a Rare+
  shade roll, the Megalodon Slayer title, a 1/15 (×2 for the top dealer) drop of the
  Ghost shade. The Trophy Hunter stall sells Ghost for 12 Teeth. On escape it heals
  and returns in 15 min.

### World boss: the Giant Squid (owner, 2026-10-06; Claude's proposal; built 2026-10-07)

Concept: `assets/concepts/GiantSquid.jpg`.

- **Size:** about 70 studs, plus tentacles. It rises from the Trench and prowls the
  deep edges of the Open Blue and the Wreck.
- **Dread:**
  - The lights dim and glowing suckers appear in the dark.
  - The HUD warns "SOMETHING STIRS BELOW".
  - It attacks from underneath.
- **Danger:**
  - **Tentacle grab:** a tentacle lights up 1 s before it strikes, wraps a fish and
    drags it toward the beak, 15% of max health a second for up to 4 s. Mash to
    break free, or a teammate bites the tentacle to free you (no one-shot, owner).
  - **Ink cloud:** blinds everyone in it and hides the squid.
  - **Jet:** it vanishes and reappears somewhere else.
- **The fight,** three phases:
  1. **Lurker** (100–65%): it stays in the dark: grabs, ink, jets. Its eight tentacles
     have their own health; biting one off removes a grab and pays bonus Beaks.
  2. **Enraged** (65–30%): two grabs at once. **Whirlpool**: it jets water to pull
     everyone toward the beak for 3 s; swim hard against it or get behind a rock. Its
     eye lights before each grab and takes double damage then.
  3. **Mantle** (under 30%): it rises into open water where everyone can see it,
     exposed but fast: **beak slam** (45%) and a **siphon blast** cone that knocks
     fish back. It sinks to escape after 90 s.
  - Its health scales with attackers the same way as the Megalodon's.
- **Rewards** follow the same rules as the Megalodon (no playable Kraken). Everyone who
  dealt at least 1% of the damage gets:
  - **Kraken Beaks**, spent at the Trophy Hunter.
  - **Trophies:**
    - the **Abyss Ink** shade: Kraken skin, ink pigment with glowing veins and sucker rings (built)
    - Kraken Tentacles body part
    - a glowing **Kraken-eye lantern** for your den
  - A chance at a trophy straight from the kill.
  - Bonus Beaks for every tentacle you bit off.
  - A huge Haul, a coral jackpot, a Rare-or-better roll, and a Kraken Slayer title.

- **As built (2026-10-07, `kit = "squid"` in `Config/Bosses.luau`):** 70 studs, 5,500 hp
  (+60% per attacker), south patrol 280–560 studs out, lurking 10–55 up off the
  floor. Lurker: tentacle grab (1 s tell, 60 stud range, 15%/s up to 4 s; the fish
  is dragged to the beak; mash BITE/DASH 6 times, or 3 teammate bites on the squid,
  break it; the biters earn a Kraken Beak), ink (6 s, 55 studs, blinds the camera
  inside, hides its tag) then a jet 120 studs away; it also jets when two or more
  are biting it. Enraged under 65%: two grabs, half the grab cooldown, whirlpool
  (1.2 s tell, 3 s pull within 70 studs). Mantle under 30%: up to 90–140 off the
  floor, beak slam (1.3 s tell, 45%) and siphon blast (1 s tell, 15% + a shove in a
  cone), sinks away after 90 s. Soft spots: the eye and the tentacles (double
  damage, stagger meter 650). Rewards: Kraken Beaks (1, +1 top three, +1 killer),
  120 kg Haul and 5,000 coral by share, a Rare+ shade roll, Kraken Slayer, a 1/15
  Abyss Ink drop; Abyss Ink costs 12 Beaks at the Trophy Hunter. The eight
  individual tentacles with their own health are not modelled yet: biting the
  tentacle zone is the soft spot, and bites free held fish.

### Tide events (the role the Moon Egg plays in Hatch & Snatch)

- **Blood Tide:** bites hit harder and chum spawns everywhere.
- **Sardine Run:** a huge bait ball, so food floods in.
- **Whale Fall:** a dead whale sinks into a random biome and the whole server races to it.
- **World boss events** (Megalodon and Giant Squid) took Leviathan Rising's place; see
  §8 "World boss events".
- **Bioluminescent Night:** a dark sea, and glowing skins can drop.

## 9. Monetization

Rule: **sell growth and safety, never bite damage**, so PvP stays fair. Kelp Wraps
are never sold for Robux. Built 2026-10-09 (`Config/Monetization.luau`,
`MonetizationService`, ported from Hatch & Snatch); every item has id 0 until it's
created in Creator Hub, and a live game hides id-0 items.

| Item | Kind | Price | What it does |
|---|---|---|---|
| **×2 Mass** | pass | 399 | Every Haul gain counts double (prey, forage, players, predators, bosses, treasure) |
| **VIP** | pass | 299 | Gold VIP tag on the nametag, +10% coral from play |
| **Den Expansion** | pass | 149 | Four more furniture spots (X1–X4: two floor, two wall), at any den level |
| **Deep Garden** | pass | 129 | The Coral Garden grows 50% faster and holds 16 h instead of 8 |
| **Second Chance** | product | 39 | Bought on the eaten screen: the Haul just lost comes back (once, within 3 min). Bought any other time: a Second Chance charm (hold up to 5) |
| **Double Haul** Small / Big / Huge | product | 19 / 49 / 99 | Doubles the Haul just banked; the tier is the Haul's size (≤ 60 kg, ≤ 2.5 t, more) |
| **Server Frenzy** | product | 99 | ×2 growth for the whole server for 15 min, announced; buying again adds 15 min (up to 2 h ahead) |
| **Shell Pouch** / **Shell Chest** | product | 49 / 199 | 100 / 600 shells (2 / 12 rolls). Paid random items: hidden where policy restricts them, with ODDS one tap away |
| Double Haul (ad) | ad reward | — | A watched rewarded video doubles a Haul up to 60 kg |

- **Double Haul:** offered on the bank screen after the tutorial when doubling would
  add at least 2 levels (a Haul of ~30% of your banked mass or more). One tap, WATCH
  AD for small Hauls, SKIP; **no countdown**. It doubles the banked amount after ×2
  Mass and Server Frenzy. `lastHaul` (with its species) is in the save, so a late
  receipt doubles exactly that haul once, capped at the tier that was paid for; a
  second receipt for the same haul becomes a Second Chance charm (a purchase is never
  lost).
- **Second Chance:** the eaten screen offers it (after the tutorial) when the lost
  Haul is at least 25% of your banked mass. `lostHaul` is in the save.
- **Coral multipliers** (VIP 1.1, Premium 1.1, group 1.05) apply to coral earned from
  play (`EconomyService.earnCoral`: banking, eating players, predators, bosses, the
  Coral Garden), not to fixed rewards that show their amount (rolls, treasure, daily).
- **Free perks:** Roblox Premium (+10% coral, more Premium playtime for Premium
  Payouts), the Roblox group (id 0 until it exists: +5% coral, 100 shells once),
  rewarded ads.
- **Shop:** SHOP (beside the wallet) or the View button on a controller: Daily reward,
  Boosts, Game passes, Free perks. Purchases open Roblox's own prompts.
- **Not sold:** coral (it buys Iron Jaw), Kelp Wraps, anything that adds bite damage.
- **Later:** codes, Pearl crates, a season pass.

### Daily login streak (owner, 2026-10-09; built)

One claim a UTC day (`Config/Daily.luau`, `RewardsService`). The panel opens by itself
once a session when a reward waits (after the tutorial); DAILY on the HUD glows until
it's claimed. Missing a day starts again at Day 1. The seven days loop, and each
finished week adds +25% coral and shells (up to +100%).

| Day | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| Reward | 300 coral | 50 shells | 600 coral + Kelp Wrap | 100 shells | 1,000 coral + Lucky Charm | 150 shells + Second Chance | 2,500 coral + 100 shells + Captain's map |

## 10. Den

- **Haul Chamber:** raises the banking multiplier.
- **Trophy wall:** the jaws of your biggest kills.
- **Aquarium:** your collected skins swim around it.
- **Coral Garden** (owner, 2026-10-09: "an afk aspect of the game to earn something
  to keep players coming back"; built): every den has a garden bed under the trophy
  plaques that grows coral and shells over real time, online or off, up to 8 hours'
  worth (16 with Deep Garden). Per hour by den level: Nook 60 coral + 4 shells,
  Burrow 100 + 6, Hall 160 + 9, Grotto 250 + 12 (Deep Garden ×1.5). Resting in your
  own den grows it ×2 and collects it every minute (AFK income); swimming in
  collects it, and a returning player (who spawns in the den) sees WELCOME BACK with
  what grew while away. Its corals grow as it fills and sparkle once full; a sign
  over it shows the amount and the time to full. `Config/Dens` `garden`,
  `Shared/Garden`, `GardenService`, `DenBuilder.garden`, `GardenController`.
- **Dive buffs:** start bigger, swim faster, longer sonar range, deeper depth rating.
- **Den Designer:** the Castle Designer idea from Hatch & Snatch, with coral, crystal,
  magma, ice and bioluminescent themes, and the most wanted looks on a rebirth ladder.

## 11. Servers

12 players per server (owner, 2026-10-06).

## 11a. Start screen (owner, 2026-10-09; built)

"A start screen when players load into the server. Just hit any button to start and
then it pushes them straight to the den and tutorial. Starter screen should have motion
and some fish swimming by with maybe some kelp." It covers the game while it loads: a
lit underwater scene (swaying kelp, the playable fish and a sardine school swimming
past, minnows and the Megalodon's shadow far off in hazed water, light shafts, marine
snow, rising bubbles), the APEX ABYSS title, and three cards on how to play (EAT, BITE,
BANK). Once the fish is in its den the prompt reads PRESS ANY KEY (PRESS ANY BUTTON on
a controller, TAP TO START on a phone); any input dives in and the water clears onto
the fish in its den, where the tutorial step pops (or the Daily panel and WELCOME BACK
show for a returning player).

## 12. Quality bar ("very fluid, extremely professional")

1. **Movement**
   - The fish has momentum and drag, and velocity never snaps.
   - Turn rate scales with size: small fish dart, big fish feel heavy.
   - The fish rolls into turns, and boosting is a tail-flick burst.
   - Your own fish runs on your device at full frame rate with no input lag; the server
     only checks it.
   - The spine ripples procedurally with speed, the head leads and the tail follows,
     and fins flare on turns.
   - **Controls (owner, 2026-10-07):** PC as built (WASD relative to the camera, mouse
     aims, Space/C up and down). Controller and phone: the left stick is throttle and
     rudder (up swims along the aim, further is faster, sideways turns, down backs
     up facing forward) and the right stick or a screen drag aims. Phones have one
     stick plus BITE and DASH.
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
