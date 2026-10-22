# Apex Tide — Game Design Document

Live title: **Apex Tide 🦈 Eat & Grow** (renamed from Apex Abyss on 2026-10-20). The logo
and brand say **APEX TIDE**, and the
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
fishing hooks and unlock rare fish. Apex Tide adds the twists below.

The name was checked on 2026-10-19 (Roblox omni-search, the group lookup, the web and
trademarks): nothing uses "Apex Tide". "Apex Abyss" was free too, but "Abyss" alone is
crowded on Roblox (18+ games, among them Deep Spirit Games' ocean game Abyss) and the
game is no longer about the abyss. "Tide" ties to the Tide Clock and the Tide Pass.

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
    carrying, and the Haul grows you **live** up to a **full Haul** (MAX SIZE): 7
    levels' worth for a new fish, then 1 level at LV 8 rising to 2 (see Pacing below). Everyday
    food stops going on there; you swim home and bank it.
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

### Pacing (owner, 2026-10-18: "level up a lot slower"; retuned 2026-10-19 twice)

History: the first rules had a full Haul at +12 levels in 16–30 s (PC PG1). The first
retune held a full Haul to under a level of tiny grams (LV 100 in ~22 h); the owner
played it and asked for the opposite feel: "No reason that a full haul for nibbler
should start at .2kg and only go up by .01 a level ... The first fish you eat are
worth far too little food right now. A full haul should take 15-20 fish first time
and hold more each time allowing them to level up faster and faster while taking
more risk with a larger haul."

- **A full Haul is food:** it holds a set kg of fish eaten (`Config/Tuning` `growth`
  `food`, by banked level) and banks a set number of levels (`cap`). The Haul card,
  pops and toasts show food, so a 0.4 kg Garibaldi is "+0.4 kg" and a full Haul at
  LV 8 is 5.2 kg; underneath the server still stores the growth the Haul will bank
  (`Shared/Size` `haulShown`, `haulRate` = the cap's kg ÷ the food).
- **Targets** (one fish, an active hunter, swimming home to bank included): the
  tutorial's Haul is ~16 kelp fish (LV 1 → 8); then ~25 fish a Haul to LV 25, ~50 to
  LV 55, ~100 at LV 55–70, ~170–210 past LV 70 (the biome's fish set the count: a
  tuna is 35 kg, a Rattail 6); a bank is 1 level at LV 8 rising to 2 at LV 100. Dives
  run 1.4 min early to ~8 min late: a bigger Haul to carry home is more to lose.
  Hours to LV 15/25/40/55/70/85/100: 10 min, 23 min, 44 min, 1.2, 2.0, 3.2, 4.1. Each
  species levels on its own.
- **Bonus meals are shares of the eater's own full Haul**, so they're worth the same
  share of a dive at every level: bait ½ (`Config/Hooks` `baitHaul`), a whale chunk ⅙
  and at most 2 full Hauls from one whale (`Config/Chum` `whale.chunkHaul`,
  `whale.hauls`), a Blood Tide slick chunk 1/30, predator loot 0.3 (Barracuda) and 0.6
  (Reef Shark) split by damage, a player kill half its Haul plus a quarter of its full
  Haul (× how near its size was). All stop at the full Haul.
- **Rewards go on top of a full Haul:** a boss's Haul (1.5 full Hauls plus the damage
  share of another), a treasure chest's Kelp Haul (1 / 1.5 / 2.5 full Hauls by map
  tier), the admin's kg, a Second Chance given back. Double Haul banks again on top.
- **Food below you counts for less:** past the top level of the biome a fish is in,
  prey and filler food count ×(1 − 0.1 a level over), at least ×0.2.
- What a bank pays: coral 7 × √(kg eaten), Tide Pass XP 2 a kg eaten (20–300 a bank)
  plus 2 a fish.
- **Measured** by `tools/tests/run_progress_sim.sh` (a hunter on the real school
  layout and filler food, in the biome whose middle level is nearest its own, at 0.9×
  top speed like the PC's PG1 bot; `MODE=design` turns fish-a-Haul and levels-a-bank
  targets into `growth` points; rerun it after changing `growth`, `Config/Prey`,
  `Config/Forage`, the biomes' levels or the size and speed curves):

  | Band | Dives | Min a dive (hunt + swim) | Levels a dive | Fish a Haul | Haul (food) | Coral a min | Pass XP a min |
  |---|---|---|---|---|---|---|---|
  | 1–8 | 1 | 0.8 (0.2 + 0.6) | 7 | 16 | 4.4 kg | 18 | 65 |
  | 8–15 | 7 | 1.4 (0.5 + 0.9) | 1.07 | 25 | 8.8 kg | 15 | 52 |
  | 15–25 | 8 | 1.6 (0.5 + 1.1) | 1.22 | 25 | 38 kg | 27 | 80 |
  | 25–40 | 11 | 1.9 (1.1 + 0.8) | 1.37 | 53 | 200 kg | 51 | 197 |
  | 40–55 | 10 | 2.9 (2.0 + 0.9) | 1.52 | 52 | 1.1 t | 79 | 140 |
  | 55–70 | 9 | 5.4 (4.7 + 0.8) | 1.67 | 99 | 1.9 t | 56 | 93 |
  | 70–85 | 8 | 8.7 (8.0 + 0.7) | 1.82 | 166 | 3.1 t | 44 | 74 |
  | 85–100 | 8 | 7.0 (6.2 + 0.8) | 1.87 | 206 | 4.4 t | 67 | 103 |

  Hours to LV 15 / 25 / 40 / 55 / 70 / 85 / 100: 0.6 / 1.6 / 4.1 / 7.0 / 10.8 / 15.9 /
  21.9 (before: 2 min / 2 min / 6 min / 7 min / 15 min / 47 min / 2.7 h; the PC's
  "10–20 minutes" to LV 100 came from LV 10 and 25 dives, but prey kg stop growing
  with the fish past LV 50, so the old rules took ~2.7 h). The 'Cuda (×1.25 speed)
  reaches LV 100 in ~18.6 h.
- **Food below you counts for less** (2026-10-19 follow-up): past the top level of the
  biome a fish is in (`Config/Biomes` `maxLevel`), prey and filler food go on the Haul
  at ×(1 − 0.1 a level over), never under ×0.2 (`Config/Tuning` `growth`
  `overLevel`, `Shared/Size.overLevel`, `HuntService` by where the fish is; what a
  bank pays is unchanged), and the Haul card's hint reads "Too easy here: deeper water
  feeds you better" (the pops show the smaller gain). From LV ~45 the Open Blue's
  Yellowfin Tuna (35 kg, tight schools of 8) and Mahi-mahi make it 3–5× richer in kg
  a second than the Ruins, Vents and Trench (23–31 kg/s against 5–11): a fish that
  stayed there reached LV 70 / 85 / 100 in 8.4 / 10.3 / 13.1 h; with the falloff
  10.4 / 15.7 / 25.5 h, against 10.8 / 15.9 / 21.9 following the biomes (switching to
  the Trench at 85 gains nothing either). A fish lingering in the Kelp still reaches
  LV 15 on pace (the falloff starts at 11), but past 15 there a dive takes ~20 min.
  `run_progress_sim.sh` checks the Open Blue stayer every run.
- ×2 Mass and Server Frenzy double every gain, so a Haul fills in half the time; with
  the swim home the same, a fish grows ~1.7× as fast an hour (it was ×2 a dive).

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
- **Chum (built 2026-10-14):** a fish that gets eaten (by a player or a creature)
  bursts 40% of its lost Haul into a cloud of 4–14 chunks that sink slowly where it
  died for 45 s. Any fish swallows a chunk by swimming into it, its kg straight onto
  the Haul (up to a full Haul), so a kill sets off a frenzy; AI predators within 320
  studs come for the cloud too. During a Blood Tide, slicks of chum appear near
  players out in the biomes (each chunk 1/30 of the eater's full Haul) and clouds
  linger longer. (`Config/Chum`, `ChumService`.)
- **Apex bounty (built 2026-10-14):** the heaviest fish in the server (LV 10+, two or
  more players) is the Apex: a gold ★ on everyone's map, a gold outline and an APEX
  line on its nametag. Its bounty starts at 500 coral and grows 150 a minute while it
  swims out of the hub (cap 6,000); whoever eats it takes the bounty, and the first
  claim gives the Apex Hunter title. A bounty pays only after a 2-minute reign out of
  the hub and never twice between the same two players within 20 minutes, so friends
  can't trade the crown for coral. A creature kill just ends the reign. The crown only
  moves to a fish 10% heavier. (`Config/Pvp` `apex`, `ApexService`.)
- **Hooks from above (built 2026-10-14):** five boats drift over the sea, dark hulls
  against the surface, dropping a line every 20–45 s with a bait fish 60–300 studs
  down. The bait is a big meal (half a full Haul, `baitHaul`), but swallowing it hooks
  you: the line reels you up.
  Mash BITE or DASH (10 times, after at least 3 s on the line) to break free with the
  bait, or a podmate bites the line; landed after 9 s, the fisherman keeps 30% of your Haul. (`Config/Hooks`,
  `HookService`.)
- **Depth pressure (built 2026-10-14):** "depth pressure gates biomes, not walls."
  Four bands sit 10 levels under the biomes they guard: off the shelf below y −60
  needs LV 25 (Open Blue 35), the deep floor below −330 LV 40 (Ruins 50), the vent
  basins below −480 LV 55 (Vents 65), the Trench's depths below −640 LV 70 (Trench
  80). Too deep for your level, the pressure builds for 6 s (a meter, the screen's
  edges closing in, creaks), then costs 3% of max health a second until you rise. The
  hub and dens are exempt, and so is the water within 500 studs of a world boss (the
  fights are for everyone). Treasure maps put their X where the holder can dig. The Outfitter's Pressure Hide counts 4 levels per level (5
  levels). (`Config/Pvp` `pressure`, `PressureService`.)

## 6. Teams

- **Schooling (the headline twist; built 2026-10-14):**
  - Small players who swim close together form a school.
  - The school's combined mass can bite a predator bigger than any one of them: a
    bite counts everyone who bit the same fish in the last 2.5 s within 40 studs, and
    their combined live mass against the target's sets the damage, +15% per extra
    biter (SCHOOL BITE ×N).
  - It keeps the top player from snowballing, and teams form without any lobby. A
    SCHOOL hint says so when a fish that can swallow you is near and so is another
    small fish.
- **Pods of up to 3 (built 2026-10-14; POD on the HUD, or the Shop on a controller):**
  - Invite anyone in the server; they JOIN or DECLINE within 30 s; LEAVE any time.
  - You can't eat or bite a podmate (nametag PODMATE, teal on the map).
  - Swimming in a podmate's slipstream (within 18 studs behind one going your way)
    is 15% faster.
  - Kill XP is shared: when a podmate eats a player, podmates within 220 studs get
    half the Haul it gained.

## 7. Creatures

### Species and progression (owner, 2026-10-06)

**Owner decisions:**

- **Everyone starts as the same small googly-eyed fish**, the starter (working name
  **Nibbler**).
  - A tutorial levels it up before any other species can be picked.
  - The starter stays upgradeable as it grows. It's the all-rounder: equal at
    everything, while the other species each specialize in a playstyle.
- **Bodies stay a believable size** (owner, 2026-10-14: "Each den should be large
  enough that a max size player can fit in it ... full grown shark should be a bit
  larger than an actual shark and max size for fish should all be relatively the
  same but not ridiculously large"): a fish's drawn length follows its mass up to
  6 studs, then eases toward 17 (`Config/Tuning` `lengthKnee`, `lengthCap`): LV 30
  5.4 studs, LV 60 12, LV 80 15.7, LV 100 16.9 (15.6 ft); a full Haul never passes
  17. The Reef Shark predator is 14. Size ratios (swallowing, bites, aggro,
  predators) and swim speed use the raw length (`Size.raw`), so the balance is as
  it was; only bodies, colliders, mouths and the camera shrank.
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
  built: left click or RT; the touch DASH button (owner, 2026-10-12: only the two mouse buttons steer the fish: left click dashes, right click bites).
- A newly unlocked species starts at level 1 (tunable).
- The **safe zone** is the dens plus the vendor plaza. A banner says when you leave it
  ("LEAVING THE SAFE ZONE", with a protection countdown) and when you're back. Built.
- **Filler food:** starfish and shrimp on the seabed for low-level XP. Built
  (`Config/Forage.luau`). Thickest near the hub, where new fish start: about one
  every 20 studs within 330 of it (owner, 2026-10-10: "far too scarce"), never
  inside or under a rock or coral; minnow schools swim low over the sand there.

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
| **Reef Shark** | aggression / bite | Open Blue | Frenzy · Blood Sense (built 2026-10-13: for 7 s every fish and predator shows through rock and murk as a flashing red heat signature, 24 s cooldown; owner: "a flashing red thermal") · Ram |
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
- **The tutorial (about 5–8 minutes, as the Nibbler; directed since 2026-10-12,
  owner: "Controls need to be more obvious during the tutorial and tutorial needs
  to be more directed instead of just a floating Ui": each step's card shows its
  keys as key caps for the player's device, a trail of lights leads from the fish
  to the step's target with the distance and an arrow on the card, and the card
  says how to free the cursor):**
  1. Swim out of your den.
  2. Eat 5 small fish.
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
    of fish on phones, and suits Tripo. It also keeps Apex Tide looking different
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
| Exotic variants, one per fish: Puffball Nibbler, Hammerhead (Reef Shark), Sabrecuda, Porcupine Puffer, Dragon Moray, Deepfang Angler | Abyssal | 1 in 8,000 / 10,000 / 9,000 / 9,000 / 9,000 / 9,000, each only in its own fish's rolls |

- **Luck:**
  - A Lucky Charm doubles every non-coral chance on the next roll.
  - Coral never drops below 50% of a roll.
  - The odds panel shows the luck that applies.
- **Duplicates** turn into coral: 120 for a tint, up to 12,000 for Prismatic and
  15,000–30,000 for an Abyssal outcome.
- **Announcements:** Rare and rarer results are announced to the whole server once
  the roller's reveal has landed.
- **Parts and variants are real pieces on every fish (owner, 2026-10-12: "parts
  need to be actual physical parts that change the appearance of the fish as well.
  Right now they do nothing. Variants should also be different/upgrades from the
  original base fish as well. For all playable models"):** on the imported mesh
  fish a rolled part hangs from a bone (a Narwhal Horn turns with the head, a Veil
  Tail swings with the tail, a Sail Fin stands on the back), and every fish has an
  exotic variant of its own: the Puffball Nibbler (inflated, spiked), the
  Hammerhead Reef Shark, the Sabrecuda (two sabre fangs, a ridge of spines, a
  little longer), the Porcupine Puffer (long bone quills, puffed up), the Dragon
  Moray (horns and a frilled crest the length of its back) and the Deepfang Angler
  (a crown of three lures and fangs). A variant only rolls for its own fish. Looks
  only; power stays in the species trees.
- **Skins have depth (owner, 2026-10-12: "They just look pasted on the fish ... The
  designs need much more depth"):** every skin ships a normal map of its own
  pattern's relief (rivets, scales, coral, spirals and grout stand out or sink in)
  blended over the fish's own, and the fish's painted creases always show through.
  Diamond is a cut gem (bevelled facets, dispersion fire along the bevels, mirror)
  and Prismatic a holographic foil (diffraction lines, hue-shifted facets, pearl,
  chrome under it): full retextures, not recolours.
- **The top skins move (owner, 2026-10-12: "prismatic needs to be moving across the
  fish not just static. same with the other highest rarity skins"):** Prismatic,
  Diamond, Divine, Aurora, Exotic, Nebula and Void carry a sheen, a tiling layer
  that slides across the body over the skin: holographic bands, glitter, gold
  motes, aurora veils, drifting stars, a violet veil running backwards (`Config/
  Shades` `sheen`, the images in `assets/textures/`).
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
- **Shades are per fish (owner, 2026-10-08):** each fish unlocks its skins for itself,
  and once a fish has one it never rolls again for that fish (its chance goes to
  coral; the odds panel shows that fish's table).
- **Every fish has its own line (owner, 2026-10-10: "skins to be different for each
  playable fish. Common skins should be similar to original just with realistic fish
  reshades and the rarer they get the wilder they get"; 12 per fish):**
  `Config/Shades` `LINES`, made by `tools/shades` from `tools/shades/lines.json`.

  | Place | Tier | Chance per roll | Duplicate |
  |---|---|---|---|
  | 1–4 | Common: realistic morphs of the real species (also at the Shade Dyer, 1,500 coral) | 1 in 32 each | 120 coral |
  | 5–7 | Uncommon | 1 in 100 each | 300 |
  | 8–9 | Rare | 1 in 150 each | 1,000 |
  | 10 | Epic | 1 in 300 | 2,000 |
  | 11 | Legendary | 1 in 700 | 5,000 |
  | 12 | Mythic | 1 in 1,500 | 12,000 |

  - About 17.5% of a fresh fish's roll is a skin (coral 82.5%), as before.
  - The lines: Nibbler (Percula, Tomato, Maroon, Midnight clownfish morphs …
    Prismatic), 'Cuda (Great, Yellowtail, Chevron, Blackfin barracuda … Comet),
    Pufferfish (Guineafowl, Golden, Starry, Green Spotted … Exotic), Moray (Green,
    Zebra, Snowflake, Honeycomb … Void), Reef Shark (Blacktip, Whitetip, Grey Reef,
    Lemon … Nebula), Anglerfish (Seadevil, Humpback, Warty, Footballfish … Starfall).
    The 30 v3 shades fill the wilder places; 42 skins are new.
  - Every fish can also have: boss trophies (Ghost, Abyss Ink), treasure (Sunken Gold,
    Drowned Pearl), its catch-track skins (Golden, Glowing, Crystal, Prism; §7 "Rare
    catches") and the weekly skins.
  - Old saves: a skin a fish held that's now another fish's turned into its coral.
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
  a Grouper 4.5%), at most 7 maps an hour from prey (an allowance that refills,
  holding up to 2: `Config/Treasure` `drops.preyPerHour`, `preyBurst`; 2026-10-19,
  after the second prey batch's heavy fish made it 30–65 an hour from LV ~25, a map
  every minute or two, against ~6 an hour in the Kelp); every shell 1.2%, a golden
  shell 12%; banking a Haul of 4 kg or more 4%. You hold at most 3; more don't drop
  until one is dug up. A found map is followed automatically if nothing else is.
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
  caches (15/35/60), a Kelp Haul of 1/1.5/2.5 full Hauls dumped straight into the dive
  on top of what you carry (levels' worth until the 2026-10-19 pace),
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
| **Fin & Gill Outfitter** (Old Hermit) | 5-level upgrades: Strong Fins +4% speed, Quick Recovery: the fish's own ability (Dash, Torpedo, Puff Up, Burrow, Blood Sense, Lantern Flash) recharges 12% faster, Shell Sense +20% pickup reach, Iron Jaw +6% bite. 150–11,000 coral a level. |
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
- **The surface** is the ceiling of the map. Boats sit up there and drop hooks. It's a
  ceiling for whole bodies: a big creature's middle stays 30% of its length under it and
  it can't tilt its nose or tail through (`PredatorService.steer`).

### The map (owner, 2026-10-12: "need a map/mini map to show people where they are"; built)

**The real seafloor from above** (owner, 2026-10-14: "needs to be an actual
accurate mini map not dots"): `tools/map/make_chart.py` rasterizes the Terrain fill
ops the server applies and draws each column's top surface as a chart (depth
shading from the shelf to the Trench's floor, relief lit from the north-west,
contours every 40 studs, lava caps in orange; a cool palette, screened clean),
`assets/textures/map_chart.png` (1024 px for 3,200 studs), uploaded as
`Config/Textures` `mapChart`. The biomes' borders are dotted over it and the sea's
edge ringed, north up; until the id is in, the old sonar chart (biome dot fields)
shows. Re-run the tool after any change to the Terrain (`Shelf.luau`, `Cave.luau`)
and re-upload. The **minimap** sits in the HUD's corner and slides under
your fish (the arrow in the middle points where you swim); on it are your den
(◆), the treasure map you're following (X), a world boss while one is up (●) and
the other fish in the server (•). A click or tap on it, M on a keyboard or R3 on
a controller opens the **full map**: the whole sea with every biome named and
levelled, a legend, and where you are (biome, its level range, your depth).

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
  - The **Giant Squid** rises from the Abyssal Trench and keeps to its canyon (below):
    it patrols and jets inside it and gives up a chase that leads it 160 studs out.
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

### Den bases (owner, 2026-10-07; v2 built 2026-10-13)

"I was also envisioning the dens being an upgradable base that gets bigger and
deeper as it upgrades. Other players can go in and check out your base but can't
take or do anything. You can display trophies from large fish killed/bosses killed
and set up furniture so that it's your den. Upgrades and furniture/colors would cost
currency. Coral lamps, etc."

v2 (owner, 2026-10-13): "The middle of the dens also looks pretty crude and it's just
sticks with spheres on the table. The dens need to be larger and have much more depth
so players can build in them and show them off. It's meant to be like the players
house/base. We will have furniture, rugs, lamps, and tons of items that will be rolled
in once these steps are done."

- **A house dug down.** The hub stands on solid rock to y −80, so a den grows down
  into it. Five levels:
  - **Nook** (start): the main room (pool, garden planter, trophy wall), holds 15
    things.
  - **Burrow** (1,000 coral): the main room runs back to r 150, holds 30.
  - **Hall** (12,000): a shaft in the Burrow's floor drops to a vaulted hall at
    y −30 under the plaza ring, the Coral Garden moves to its middle; holds 50.
  - **Grotto** (45,000): the hall opens into wide wings and a deep grotto at the
    back; holds 75.
  - **Sanctum** (150,000): a second shaft to the deepest storey at y −66, the
    grandest room; holds 100.
  At the top level that is about 10,000 sq studs of floor over three storeys (a Nook
  had 384). Rooms are barrel vaults with alcoves, 5 studs of rock inside the line to
  the next den. The sign reads "<NAME>'S SANCTUM".
- **Decks:** every storey has a flat flagstone floor (tiles of mixed sizes with dark
  joints) to build on. Six floor styles: Flagstone (free), Driftwood Planks 800,
  Sandstone Tiles 1,500, Pearl Marble 4,000, Reef Mosaic 6,000, Glowing Obsidian
  12,000 (the den's glow in its joints).
- **Architecture:** stone curbs with a glowing lip round the shafts, pillars with
  sconces down the big rooms, orb lamps hanging down the vaults, all in the den's
  glow.
- **Build mode:** placing things is free-form. In your own den, press B (or BUILD in
  the den menu).
  - You keep swimming and aim with the camera. A ghost shows where the thing goes:
    green, or red with the reason.
  - Things go on decks, walls or ceilings, whichever they're made for, and can stand
    on each other (a lamp on a table, a table on a rug).
  - Aim at a placed thing to pick it up and move it, or put it back in the tray.
  - Turn in 15° steps.
  - Every thing bought goes into the Build tray (copies count).
  - Den Expansion adds 25 to the cap.
  - The server checks every request against the den's space (`Shared/DenSpace`).
- **Things:** 16 so far, 150 to 1,200 coral:
  - Floor: Coral Lamp, Kelp Bed, Woven Kelp Rug, Shell Pile, Anemone Garden, Brain
    Coral, Tube Sponges, Driftwood Table, Pearl Pedestal, Treasure Chest, Bubble
    Column, Crystal Shard (also walls).
  - Walls: Sea Glass Lantern, Sea Fan, Banner.
  - Ceiling: Jellyfish Lamp.
  The rolled furniture, rugs and lamps come next.
- **Colors:** a glow color for the den's lamps, banners, trims and seams: Teal free,
  Gold, Rose, Violet, Lime, Ice and Ember 300 each.
- **Coral Garden:** a stone planter along the main room's back wall (Nook, Burrow),
  then an oval bed ringed with stones in the middle of the Hall. Corals (staghorn,
  fan, brain, tube sponges, anemones; the Tripo reef props where imported) grow one
  by one as it fills, and it sparkles when full. A Sanctum grows 380 coral and 16
  shells an hour.
- **Trophy wall:** three plaques on the main room's back wall fill themselves:
  BIGGEST CATCH (the heaviest prey ever eaten, its model mounted above), MEGALODON
  (teeth taken) and GIANT SQUID (beaks taken); the worn title hangs over the door.
- **Visiting:** anyone can swim into any den (the whole house is a safe zone) and
  look; only the holder can bank there or change anything.
- Later: rolled furniture, rugs and lamps (Tripo models), den items won from bosses
  (the jaw arch, the Kraken-eye lantern), a visit button.

### Den furniture, batch 1 (approved and built 2026-10-13)

The owner: "We will have furniture, rugs, lamps, and tons of items that will be rolled
in once these steps are done", then on the seven boards: "Approve all, players will need
to complete achievements to unlock the ability to purchase each set with coral. Once a
set is unlocked, pieces are individually bought, not the entire set. This makes them
interchangeable if wanted." The boards are `assets/concepts/Furn*.jpg`.

| Set | Biome | Tier | Opened by (Config/Achievements) | Pieces (coral each) |
|---|---|---|---|---|
| Kelp Cottage | Kelp Shallows | Common | Settling In: bank 25 hauls | kelp armchair, kelp hammock, barrel table, scallop lamp, driftwood shelf, braided kelp rug (400–900) |
| Reef Palace | Coral Reef | Uncommon | Golden Touch: catch 25 Golden fish | coral throne, giant clam bed, brain coral ottoman, staghorn chandelier (ceiling), fan coral screen, coral rug (1,500–4,000) |
| Shipwreck Captain | Shipwreck Graveyard | Rare | Treasure Hunter: dig up 10 chests | captain's desk, ship's wheel (wall), ship's lantern (ceiling), bronze cannon, barrels and crate, anchor (3,500–6,500) |
| Sunken Temple | Sunken Ruins | Epic | Deep Diver: reach LV 50 | rune throne, column planter, teal brazier, glyph tablet (wall), grouper guardian, wave mosaic (6,000–14,000) |
| Vent Forge | Hydrothermal Vents | Epic | Glow Getter: catch 15 Glowing fish | lava fire pit, obsidian table, lava lamp, sulfur crystals, vent cauldron, tube worm planter (9,000–16,000) |
| Abyss Glow | Abyssal Trench | Legendary | Apex of the Abyss: reach LV 80 | jellyfish chandelier (ceiling), angler lure lamp, glow coral bed, void throne, plankton swirl rug, kraken eye orb (18,000–40,000) |
| Boss Trophies | world bosses | Trophy | Monster Hunter: help down 3 world bosses | Megalodon jaw arch (swim through), kraken-eye lantern (ceiling), shark tooth plaque (wall), bronze tentacle, treasure hoard, reef globe (20,000–60,000) |

- **Achievements** (`Config/Achievements`, `AchievementService`) are measured from the
  save's lifetime tallies (`stats.banks`, `catchLog`, `treasures.found`, the best level
  of any fish, `stats.bossKills`), so earlier play counts. Each is marked done once and
  for good (`data.achievements`), with an ACHIEVEMENT banner naming the set it opened;
  progress goes to the client as `state.achievements`.
- **Buying:** the den menu lists each set under its own heading: an open set's pieces
  with their prices, a locked set's achievement with progress and the pieces it holds.
  DenService refuses a locked set's piece. Bought pieces go into the Build tray like
  every other thing, so any piece stands beside any other set's.
- **Lights:** lamps and glowing pieces light in their own colour (`lamp`), not the
  den's glow.
- **3D:** each piece was cut off its board on a clean background
  (`tools/props/furniture_segment.py`, `furniture_crops.py`) and made with Tripo
  image_to_model (`tools/tripo_jobs_furniture_models.json`, 38 × 30 credits). Every
  normal map was taken out (`tools/props/strip_normals.py`), skin tones moved out
  (`safe_colors.py`; the Kraken eye repainted amber first), and all 76 images cleared
  by the screen with the classifier (`furniture_glb`). Fronts face +X in the GLB
  (`front = 90`). Rugs are top-down art unwarped off the boards
  (`tools/props/rug_textures.py`, `assets/textures/rug_*.png`), drawn as a Decal on a
  flat rug once their ids are in `Config/Textures`.
- **Placing (owner, 2026-10-14: free placement, plus "the snapping and starter
  layouts"):** things stay free to place anywhere they fit, with two helpers:
  - **Snapping** (on by default; G, D-pad up or SNAP turns it off): turns go in 45°
    steps (15° off); a floor thing lines up with a neighbour's x or z when within 0.8
    studs, and with rock or a pillar just behind it backs onto that wall facing out; a
    wall thing matches a neighbour's height. A snapped spot is used only when it's
    allowed; otherwise the free one.
  - **Starter layouts** (`Config/Dens` `layouts`): each set has an arrangement of its
    floor pieces (a rug with a chair and table on it, lamps and shelves round them).
    With a piece of the set picked or aimed at, L (D-pad down, LAY OUT) lays out every
    piece of that set in the tray round the floor spot aimed at, facing you. It finds
    room itself (the spot, then rings out to 24 studs, each way round) and keeps clear
    of what's there; rugs only clash with rugs. Every piece can be moved after; wall
    and ceiling pieces stay in the tray to hang by hand.
- **Later:** a second tier of each achievement could open a gilded or glowing finish of
  its set, and Tide Pass seasons can carry a den piece on the paid row (into
  `den.items`, never `den.owned`).

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
- **Below the drop-off** (850–1,500 out): the Open Blue north (LV 35–55; open ocean,
  owner 2026-10-09: "deep blue where there's no ground or anything just open ocean":
  its life keeps to the water 150–470 studs over a blue-grey floor that's lost in the
  blue far below, with ridges, knolls and low spires; shark water: the Reef Shark
  predators and the shark, grouper and snapper schools live here, and the Megalodon
  roams it), the Sunken Ruins east (50–70;
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
chip warn DARK WATERS · a light helps (it said PITCH DARK · bring a light until
2026-10-11).

**Creepy, not black (owner, 2026-10-11: "Let's just go with a creepy vibe for the
trench and keep it darker but not pitch black people aren't going to want to go
there. The light affects will still make a difference").** The Trench is the darkest
place in the sea but never a void: a dim, cold light stays (more where the plankton is
thick, and a sliver from far above), the water turns a murky green-teal that the canyon
walls, fish and the Giant Squid loom out of, and the picture goes cold and drained with
a little extra contrast. A light still matters: it lights a pool round its fish and
clears its holder's view by its rarity (below).

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
| Common glowing shade (Ember, Ink, Neon Tetra) | 24 | 5% clearer |
| Deep Lantern (350 coral) | 30 + beam | 10% |
| Rare glowing shade | 28 | 10% |
| Epic glowing shade | 36 | 16% |
| Anglerfish lure (Trench species) | 46 + beam | 24% |
| Legendary glowing shade | 48 | 26% |
| Mythic glowing shade | 60 | 34% |
| Boss trophy / Abyssal shade (Ghost, Abyss Ink) | 60 | 38% |

A fish uses its best source, and everyone round it sees its light. A glowing shade's
light comes up as the water darkens (it's a skin, not a lamp), measured before its
holder's own light clears the view; deep colours (violet) get up to ×1.2, and Aurora
and Ghost carry their own boost (green reads weak on the teal floor), so the order
by eye follows the tiers. `Config/Tuning` `light`.

**Fights are never fought in the dark (owner, 2026-10-09: "the abyss can't be
completely black how the hell will anyone fight anything in pitch black or low
visibility let alone a boss").** The no-light level was raised a step, every hunter
shows a faint eerie rim in the dark, and near a boss the dark lifts by more than half
and the water clears (`OceanController.setBossLight`), whatever light you carry: the
Giant Squid's bioluminescence lights the abyss round it.

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
- **No regeneration anywhere** (owner, 2026-10-11: "Health should not regenerate that
  is the whole point of kelp wraps"): only a wrap, eating prey or a respawn heals.
- **The item wheel** (owner, 2026-10-11): wraps and the timed charms (Feast, Shell
  Magnet, Deep Lantern) wait in your inventory however they come, the Treasure Wheel
  included, and start only when picked on the wheel (hold G / hold LB / ITEMS); H and
  a tap of LB still use a wrap at once.

### AI predators (built 2026-10-07)

The owner's "aggressive AI predators worth more" are the base the bosses stand on.
`Config/Predators.luau` lists them; `PredatorService` simulates them on the server
(10 Hz) and streams positions to every client, which interpolate them.

- **Barracuda** (9 studs, 140 hp, 3 alive, 220–400 studs out, 8–90 deep): fast, bites
  20% of max health every 2.2 s after a 0.9 s tell; ignores fish under a quarter of
  its length unless they bite it. Loot 0.3 of a full Haul, 3 DNA, 40 coral.
- **Reef Shark** (14 studs, 320 hp, 2 alive, 300–420 out, 10–110 deep): slower, bites
  30% every 2.8 s after a 1.1 s tell. Loot 0.6 of a full Haul, 6 DNA, 120 coral.
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
- **Spread out, no mobbing (owner, 2026-10-22: "Predators should be more spread out.
  And they shouldn't mob a player either"):** each of a group's creatures has its own
  patch of the group's water (the sector cut into one arc each, a little overlap) and
  roams, lurks and respawns there, easing off any other creature within 70 studs. At
  most two hunt one fish at once (a pack or a boss counts as one; a fish that bites
  one is always fair game for it); the rest keep 60 studs clear of a fish that's
  taken, and at most two go to one chum cloud.
- **Hunting like a real predator (owner, 2026-10-19: "If he misses the player he just
  slowly turns around and goes at them again. It needs to feel like a real predator
  ... Same with other predator fish. Needs to be fun to fight them not robotic"):**
  after a strike it carries through (`carry`), then banks round hard (`comeTurn` ×
  its turn rate) onto a loop a run-in's length out and turns in from a new angle once
  its bite is ready; a bite that lands sates it `sated` s longer (it swings wide with
  its mouthful), so a fish that sits still is bitten no faster than before while a
  miss comes round at once. The Reef Shark opens a hunt by circling in (40%),
  stalking up from below (35%) or straight in, and feints once a hunt in five; both
  cruise in burst-and-glide strokes (`glide`, `beat`). Sim (`run_predators.sh`): a
  missed pass comes round in ~2 s (was 2–4 s, a Barracuda after a dashing fish ~28
  s), the hit rates on still, fleeing, juking and looping fish unchanged.
- **The look, all on the client from how it moves (`PredatorController`, nothing more
  on the stream):** tail beats by speed and thrust, a C-bend into turns and an arch
  through climbs (the body concave toward the turn), a bank, a hunter's head eyeing
  its fish, and the jaw (rig_fish.py `--jaw`: a Jaw bone on the 'Cuda, Reef Shark and
  Megalodon): a little open as it cruises, a gape building through the tell, a snap
  shut on the bite and a head shake when it lands.

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
- **Out of the deep blue (owner, 2026-10-09: "an eerie figure ... not for deepest
  darkest ocean just deep blue where there's no ground or anything just open ocean ...
  he should roam around the deep blue ... unseen until he slowly fades into view of
  players. Once he is upon them he needs to be seeable to be fightable"; built):**
  - It roams the Open Blue's open water, 170–470 studs over the deep floor, which is
    lost in the blue below it.
  - **Felt before it's seen:** within ~460 studs a low drone and a heartbeat swell,
    the screen's edges darken and beat, the water turns cold and grey, and a warning
    reads SOMETHING CIRCLES IN THE BLUE (no arrow, no distance).
  - **It fades in:** from ~280 studs off its body it materialises out of the blue,
    solid by ~170, and the haze carries the rest of the emergence. Its tag, boss bar
    and MEGALODON NEARBY appear once it's a third of the way in. The body is never
    left a hair see-through: any transparency at all draws a mesh without sorting its
    own faces, so fins and the jaw showed through (playtest 2026-10-10).
  - **Seen to be fought:** within ~190 studs the water round it clears (no darkening
    ever), and a faint cool rim keeps its outline readable.
  - The camera shakes as it passes, and its tag reads APEX PREDATOR in red.
  - `Config/Bosses` `sight` and `dread`; `PredatorController` (the fade, the rim),
    `BossController` (dread, vignette, the fight light).
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
    3. **Last stand** (under 25%): it makes for the open ocean (the far edge of the
       Open Blue, the way it's facing) on a 60 s clock. **Breach**:
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
  for 25%). Last stand: a 60 s clock out toward the open ocean, a Breach every 13 s (2.2 s
  tell as it sinks, 1.3 s rocket, 0.9 s crash, a 48 stud ring 30% + shove to fish
  within 16 studs of its depth, then 5 s exhausted at triple damage). Soft spots:
  gills (60–80% along the body) and tail (0–22%) take double damage and fill a
  700-point stagger meter; full → 4 s stagger at triple damage (18 s cooldown), which
  breaks the mark. Rewards for everyone with ≥1% of the damage: Teeth 1 (+1 top three,
  +1 killer), a Haul of 1.5 full Hauls plus the damage share of another, on top of a
  full one (120 kg by share until 2026-10-19), coral 5,000 by share (min 500), a Rare+
  shade roll, the Megalodon Slayer title, a 1/15 (×2 for the top dealer) drop of the
  Ghost shade. The Trophy Hunter stall sells Ghost for 12 Teeth. On escape it heals
  and returns in 15 min.
- **Bigger and alive (owner, 2026-10-19: "his actual movements are very stiff ... he
  could definitely be made larger and needs more movement"):** 175 studs (was 130),
  every reach and radius ×1.35 (bite 21.5, trigger 43, charge 27 at 65–280, sweep 78,
  breach ring 84 ± 27, aggro 240), seen from 560 and solid by 330, the fight light
  300, the dread 760. It swims like a fish with momentum and a turning circle
  (`predator.swim`): slow strokes and long glides, a surge into a charge, a carry
  through a miss and a hard banked turn back (~2 s after a missed charge, 3–5 s after
  any pass; the old crawl took 15–40 s after some), circling a fish
  at 270 → 170 studs while its bite cools, and up from below at a far one. A fish
  beside its head or over its back (inside the circle its mouth sweeps) gets a pass:
  it swims on and wheels back instead of pivoting on the spot. **Its bite is
  dodgeable:** it swings its head onto the fish for the first 40% of the 1.2 s tell,
  then its head is set (`BITE_COMMIT`), and the jaws reach 1.6× ahead but 0.7× to the
  side, so a fish that swims off its jaws or slips aside at JAWS OPEN · SWIM CLEAR
  gets clear (sim: 20% of the bites dodged sideways land and 37% of those backed off
  from, a still fish's ~100%; before, 98–100% landed either way). No charge at a fish hugging the surface above where its body can rise.
  A landed bite adds 2.2 s to its cooldown (`sated`): it circles. On the client: the
  jaw (gape through the tell, snap, head shake, chomps in the Frenzy), pectoral fins
  (FinL/FinR, rig_fish.py `--fins`) flaring in a tell and tucked in a charge, the
  belly rolled out in a hard turn, onto its side in a breach's crash. The Giant
  Squid's arms writhe, close and trail on each pulse of its mantle and spread on the
  glide, curl up to reach in a grab's tell and stream behind a jet.

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
  the Megalodon's Haul (1.5 full Hauls + the share of another) and 5,000 coral by
  share, a Rare+ shade roll, Kraken Slayer, a 1/15
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
- These became the **Tide Clock** (2026-10-10, below): Blood Tide, the Sardine Run and
  Bioluminescent Night are tides now.
- **Whale Fall (built 2026-10-14):** a world event about every 26 minutes, between the
  bosses. A minute's warning ("A WHALE FALL is coming down in the Coral Reef") and a W
  on every map; the carcass sinks 150 studs to the floor and feeds the whole server for
  five minutes: 18 chunks round it, each growing back 14 s after it's eaten. Each puts
  a sixth of the eater's own full Haul on, and one fish takes at most two full Hauls
  from one whale (fill up, bank, come back), so it's the same windfall at every level
  (the chunks look bigger in deeper biomes). AI predators come for it too.
  (`Config/Chum` `whale`.)

### The pull-back loop (owner, 2026-10-10; built)

Owner: "I still feel like we're missing a factor that pulls people back over and over.
I do want to add random rarities of fish that can be eaten for more towards the haul or
like 10 total unlocks a skin." Claude proposed four pieces that feed each other; the
owner picked all four ("All four please!").

- **Rare catches** (`Config/Catch`, `Shared/Catch`, `Shared/RareSpawn`, `CatchService`):
  any prey fish can swim rare. **How often (owner, 2026-10-18: "I caught three crystal
  fish in about 5 minutes ... rerun the spawn rates to fit what you think is best that
  players dont get annoyed with the grind but they are also not done super quick"):**
  until then every fish rolled its rarity, so the rare fish alive at once grew with the
  ~4,100 fish (4–5 Crystals in the sea at any moment, glints seen from 240 studs; the
  sim gives a hunter a Crystal every ~5 min and 5–10 Golden a minute). Now each rarity
  has a spawn rate **per player out in the biomes**: a rare fish is set swimming on a
  fish that player can swallow, in their biome, 340–750 studs off and never within 320
  of anyone (so nothing turns rare in sight), the species picked evenly among the ones
  there (then a school, then a fish). It lives about its `life`, then turns plain once
  no one's within 320. So a player's encounters depend on neither the number of fish
  nor of players; twelve hunting one biome don't starve each other (each brings their
  own stream). In a crowded biome with nowhere out of sight, an eaten fish there comes
  back rare. A tide multiplies the rates (×3 in its first 2 minutes for what it
  boosts, so its fish show early). Tuned by `tools/tests/run_catch_sim.sh` (a hunter
  sees glints within 240 studs, a quarter hidden by rock, and detours; a casual player
  takes only what swims within 60 studs of its way), averaged over the normal tides:

  | Rarity | Tier | A hunter meets one | Casual | Haul | Coral | DNA | Skin goal | Skin |
  |---|---|---|---|---|---|---|---|---|
  | Silver | Uncommon | every 1 min | 3 min | ×2 | 3/kg, min 5 | ×1 | 10 × 5 species (~1–2 h) | Common |
  | Golden | Rare | every 5 min (Calm 11, Golden Hour 2) | 12 min | ×3 | 6/kg, min 10 | ×2 | 10 × 5 species (~6–9 h) | Uncommon |
  | Glowing | Epic | every 25 min (Calm 40, Biolum Night 10) | 52 min | ×6 | 15/kg, min 40 | ×3 | 5 × 5 species (~15–20 h) | Rare |
  | Crystal | Legendary | every 100 min (Blood Tide 58) | 170 min | ×12 | 40/kg, min 150 | ×5 | 2 × 5 species (~18–39 h) | Epic |
  | Prism | Mythic | 2 a Prism Tide | 1 a tide | ×25 | 100/kg, min 500 | ×8 | 1 × 5 species (3–5 Prism Tides) | Epic |

  - They look the part from a distance (`SchoolController`): polished silver that
    flashes white as it turns (so it reads apart from plain silvery minnows and
    sardines), gold foil, a teal glow, clear crystal, a shifting rainbow, each with
    sparkles, a small light and a four-point glint star to 240 studs.
  - A Crystal or Prism catch is announced; a Prism fish is announced when it appears
    (one announcement in 45 s at most).
- **The Catch Logbook** (the LOG's first tab; owner, 2026-10-18: "a catch logbook that
  shows the largest they have caught and they can track total gold/crystal/silver etc
  that they have for each fish"): an entry per prey species, straight from
  `Config/Prey`, with a lit photo (a dark ??? silhouette until it's caught), where it
  swims, its biggest, and a cell per rarity (plain, Silver, Golden, Glowing, Crystal,
  Prism) with how many, the biggest of that rarity and how it stands toward that skin.
  A first catch pays (25 / 60 / 120 / 400 / 1,500 / 5,000 coral), a finished species
  row 3,000 coral and 60 shells (Silver joined the row on 2026-10-18; a row paid before
  stays paid), and the whole log the Master Angler title.
  - **Biggest catches (owner: "track their biggest eat of each species and rarity of
    species too"):** every school fish has its own size (`Schools` `size`: 0.82–1.18
    of its species' length, and 1 in 25 a trophy at 1.25–1.5), so its mass, and what
    eating it is worth, goes with the cube of that. The log keeps your heaviest of
    each species at each rarity (`data.catchBest`). A new record on a rare or
    trophy-sized fish (≥1.9× the species' mass) says NEW BIGGEST.
- **Skin goals (owner, 2026-10-18: "They will need atleast 10 gold of 5 different
  species to unlock the skin. Once the skin is unlocked, it is unlocked for all of
  their fish"):** `unlock.each` catches of a rarity from each of `unlock.species` prey
  species (the lifetime Catch Log counts, any fish you swim as) unlock that rarity's
  skin for every playable fish, the ones not unlocked yet too, the way a Tide Pass
  skin is (`CatchService.grantEveryFish`). The goals sit at the top of the logbook:
  your fish in the skin, the species done and the nearest to counting. A biome's rare
  fish are its own species, so five usually means the Coral Reef or deeper (the Kelp
  Shallows has five for a small fish since the Garibaldi and Ghost Shrimp). Those skins
  are never rolled. (Until 2026-10-18 each fish had its own catch track: 100 of a
  rarity as that fish. On every join a save gets every goal its log meets and any
  catch skin one of its fish earned that way, on every fish; nothing is taken away;
  `data.catchTracks` stays in the save, unused.)
  - **Earned skins stop at Epic** (owner, 2026-10-10: "we still don't want the most
    elite skins obtained that way that'll be rng and bosses/treasure chests"): Silver
    is Common, Golden Uncommon, Glowing Rare, Crystal and Prism Epic, and the weekly
    skins Epic. Legendary and Mythic skins come only from rolls, the Treasure Wheel's
    jackpot, bosses and treasure chests.
- **The Tide Clock** (`Config/Tides`, `Shared/Tides`, `TideService`, `TideController`):
  the sea changes every 20 minutes, on the :00, :20 and :40, on one clock for every
  server (arithmetic on Unix time, so nothing is sent).

  | Tide | How often | What it does |
  |---|---|---|
  | Calm Waters | twice as often as the others | rare fish at their usual rates |
  | Golden Hour | | Golden ×5, coral from rare catches ×1.5 |
  | Blood Tide | | Golden, Glowing and Crystal ×2, Haul ×1.25, AI hunters ×1.2 speed and ×1.5 aggro |
  | Sardine Run | | bait balls of 36 sardines in the shallows and over the reef (`Config/Prey` `tideZones`), small fish Haul ×1.5 |
  | Bioluminescent Night | | Glowing ×3 (×5 in the deep), the sea dims |
  | Prism Tide | 03:00, 09:00, 15:00, 21:00 UTC | Prism fish swim; Golden, Glowing and Crystal ×2 |

  - Never the same tide twice in a row. A chip at the top names the tide and its time
    left, and counts down to a Prism Tide within the hour; a banner and a faint tint
    in the water mark each change; the LOG's TIDES tab forecasts the next nine.
- **Daily bounties** (`Config/Bounties`, `BountyService`): three a UTC day, different
  kinds, within the fish's level (catch Golden/Glowing fish, eat fish, bite hunters or
  a boss, bank Hauls, pick up shells, eat during a tide, dig up a chest); each pays the
  moment it's done, all three open the Bounty Chest (1,000 coral, 50 shells, a Lucky
  Charm, a Treasure Wheel spin).
- **Catch of the Week:** one prey and rarity a week (Monday 00:00 UTC; week 1 is
  2026-10-05: Crystal Grouper, then Glowing Snapper, Golden Barracuda, Crystal
  Wrasse), with a spawn stream of its own all week (`weekly.rate`, on its species only,
  where it swims near the player): a hunter there meets one in about 45 minutes. The
  first one caught pays big and unlocks that week's
  limited skin for the fish that caught it (Great Wave, Living Reef, Shipwreck, Sea
  Glass). The list cycles; add a week and a skin to keep it fresh.
- **Weekly leaderboards** (`Config/Leaderboards`, `LeaderboardService`): Rare Catches
  (Silver 0.2, Golden 1, Glowing 5, Crystal 25, Prism 100, Catch of the Week +50), Biggest Haul and
  Boss Damage; this server's live and every server's top 50 (OrderedDataStores per
  week). Last week's top 1, 10 and 100 earn a title on their next join.
- **The LOG** (HUD button beside DAILY): the Catch Logbook and its skin goals, Bounties, Weekly
  (Catch of the Week and the boards), Tides.
- **The Treasure Wheel** (owner, 2026-10-10: "do want a spin wheel again"; ported from
  Hatch & Snatch's Luck Wheel: `Config/Wheel`, `TreasureWheel.luau`, `WheelService`,
  `TreasureWheelController`): a game-show wheel of parts on the hub plaza (240°, 62
  studs from the beacon), teal and brass, with pegs, a flapper, marquee bulbs, a sign,
  an odds board and a big red button. Swim to the button and press E (Y on a
  controller, SPIN on a phone); T (ALL) is Spin all. Everyone in the hub sees it turn;
  a second spinner joins the line.

  | Slice | Odds |
  |---|---|
  | 300 coral | 24% |
  | 40 shells | 18% |
  | Feast Charm | 12% |
  | 2 Kelp Wraps | 12% |
  | Weathered treasure map | 10% |
  | +2 spins | 10% |
  | Lucky Charm | 10% |
  | Jackpot: a Rare-or-better skin from your fish's line (2,500 coral once it has them all) | 4% |

  - Spins are never sold. One comes free every 4 hours, online or off, up to 3
    waiting (a reason to come back), and a new save starts with one; the Bounty Chest
    gives 1, the Catch of the Week 2, and daily streak days 3 and 6 one each.

## 9. Monetization

Rule: **sell growth and safety, never bite damage**, so PvP stays fair. Kelp Wraps
are never sold for Robux. Built 2026-10-09 (`Config/Monetization.luau`,
`MonetizationService`, ported from Hatch & Snatch); every item has id 0 until it's
created in Creator Hub, and a live game hides id-0 items.

| Item | Kind | Price | What it does |
|---|---|---|---|
| **×2 Mass** | pass | 399 | Every Haul gain counts double (prey, forage, players, predators, bosses, treasure) |
| **VIP** | pass | 299 | Gold VIP tag on the nametag, +10% coral from play |
| **Den Expansion** | pass | 149 | 25 more things placed in the den, at any den level |
| **Deep Garden** | pass | 129 | The Coral Garden grows 50% faster and holds 16 h instead of 8 |
| **Second Chance** | product | 39 | Bought on the eaten screen: the Haul just lost comes back (once, within 3 min). Bought any other time: a Second Chance charm (hold up to 5) |
| **Double Haul** Small / Big / Huge | product | 19 / 49 / 99 | Doubles the Haul just banked; the tier is the Haul's size (≤ 0.6 kg, ≤ 12 kg, more: a full Haul up to ~LV 22, ~LV 58, past it) |
| **Server Frenzy** | product | 99 | ×2 growth for the whole server for 15 min, announced; buying again adds 15 min (up to 2 h ahead) |
| **Shell Pouch** / **Shell Chest** | product | 49 / 199 | 100 / 600 shells (2 / 12 rolls). Paid random items: hidden where policy restricts them, with ODDS one tap away |
| Double Haul (ad) | ad reward | — | A watched rewarded video doubles a Haul up to 0.6 kg |
| **Deep Pass** | product | 399 | This season's paid row of the Tide Pass (below): three skins, a title, three den pieces, far more coral, shells and spins, +20% pass XP. Bought from PASS, not the Shop |

- **Double Haul:** offered on the bank screen after the tutorial for a Haul of at
  least 75% of a full one (`minFull`; one more dive's worth, 3–5 minutes of hunting,
  since the 2026-10-19 pace). One tap, WATCH
  AD for small Hauls, SKIP; **no countdown**. It doubles the banked amount after ×2
  Mass and Server Frenzy. `lastHaul` (with its species) is in the save, so a late
  receipt doubles exactly that haul once, capped at the tier that was paid for; a
  second receipt for the same haul becomes a Second Chance charm (a purchase is never
  lost).
- **Second Chance:** the eaten screen offers it (after the tutorial) when the lost
  Haul is at least half a full Haul (`minShare`; it was 25% of the banked mass, which
  a full Haul is far under since 2026-10-19). `lostHaul` is in the save.
- **Coral multipliers** (VIP 1.1, Premium 1.1, group 1.05) apply to coral earned from
  play (`EconomyService.earnCoral`: banking, eating players, predators, bosses, the
  Coral Garden), not to fixed rewards that show their amount (rolls, treasure, daily).
- **Free perks:** Roblox Premium (below), the Roblox group (id 0 until it exists:
  +5% coral, 100 shells once), rewarded ads.
- **Shop:** SHOP (beside the wallet) or the View button on a controller: Daily reward,
  Boosts, Game passes, Free perks. Purchases open Roblox's own prompts.
- **Not sold:** coral (it buys Iron Jaw), Kelp Wraps, anything that adds bite damage.
- **Codes (built 2026-10-14):** the Shop's Free Perks has a Codes row; REDEEM opens a
  box. Each code (`Config/Codes`) pays a reward bundle once per player and can end at
  a set time. Launch codes: APEX (1,000 coral, 50 shells), DEEPDIVE (60 shells, a
  wheel spin), MEGALODON (750 coral, a Lucky Charm), NIBBLER (100 shells).
- **Later:** Pearl crates.

### Creator Rewards: pay for playtime (owner, 2026-10-12; built)

Owner: "We need monetizable assets that pay based on play time as well with rewards."
Roblox replaced Premium Payouts with **Creator Rewards** (July 2025): the Daily
Engagement Reward pays 5 Robux each time an *Active Spender* (≥ $9.99 spent on Roblox
in 60 days) plays **ten minutes or more** in a day, counted for the first three
experiences they open that day; the Audience Expansion Reward pays 35% of a new or
returning player's first $100. So the game rewards the minutes themselves, gives
paying players a long goal, and makes Premium worth having, without a wall:

- **Playtime gifts** (`Config/Playtime`, `PlaytimeService`): a ladder of gifts for
  minutes played today (UTC), claimed from the DAILY panel; the DAILY button counts
  down to the next gift and lights up (GIFT !) when one waits. The server counts the
  time every 5 s for every player in the server. Every gift also gives Tide Pass XP.

  | Minutes | 5 | 10 | 15 | 25 | 40 | 60 | 90 |
  |---|---|---|---|---|---|---|---|
  | Gift | 150 coral | 25 shells | 300 coral + Kelp Wrap | 40 shells + spin | 600 coral + Kelp Wrap | 1,000 coral + 75 shells + spin | 2,000 coral + Weathered map |
  | Pass XP | 40 | 80 | 80 | 120 | 160 | 250 | 300 |

- **Roblox Premium** (`Config/Monetization` `premium`): +10% coral from play (as
  before), ×1.5 coral and shells from playtime gifts, a free Treasure Wheel spin a day
  (on the first tick of each day), +4 h of Coral Garden room and a ◆ by the name.
  Convenience and cosmetics only, never bite power. The Premium purchase is offered
  from the Daily panel (beside CLAIM GIFT), the Shop's Free Perks row and nowhere as a
  wall.
- **The Tide Pass** (`Config/Pass`, `PassService`, `MenuController.openPass`, PASS on
  the HUD): seasons of four weeks on the Tide Clock's week numbers (season 1 starts
  Monday 2026-10-12 00:00 UTC), 30 tiers of 2,000 XP. XP comes from play: banking
  (2/kg, 20–300 a bank), catches (2 / 25 / 60 / 150 / 300 by rarity), bounties (150,
  chest 300), boss kills (400), treasure (100), the daily claim (200) and the
  playtime gifts. A player on for an hour a day makes ~2,200 a day and finishes in
  about four weeks; past tier 30 every 2,000 XP pays 500 coral (Overtide). Every tier
  has a free reward; the **Deep Pass** (399 R$, a developer product bought for the
  season) opens the paid row and earns ×1.2 XP. Rewards stay at Epic or below (the
  elite skins are RNG, bosses and treasure): season 1 "Riptide" gives the free row
  Tideglass (Rare, tier 20), the titles Tide Rider (10) and Riptide Veteran (30),
  spins, wraps, charms, coral and shells; the paid row Riptide (Epic, tier 1, so the
  Deep Pass pays at once), Undertow (Epic, 15), Abyssal Current (Epic, 30), the
  titles Riptide and Abyss Walker, the Sea Glass Lantern, Pearl Pedestal and Crystal
  Shard den pieces, two maps and far more coral, shells and spins. CLAIM ALL takes
  every unlocked reward; a skin goes to the fish you're swimming as (the per-fish
  rule). When a season ends, what a player had unlocked is claimed for them and the
  record starts again; the Deep Pass is per season.

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
snow, rising bubbles), the APEX TIDE title (the logo once uploaded), and three cards on how to play (EAT, BITE,
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
   - **Music by place (owner, 2026-10-11: "The music is horrible too ... it's just
     random bells"; built).** The "music" was the synthesized ambience: the hub's bed
     pinged a glockenspiel at random pitches. Now the beds and everyday cues have no
     bells, and real music plays from Roblox's licensed APM library, one album for
     the whole sea (David Lindsay, "Underwater Kingdom"):

     | Place | Tracks |
     |---|---|
     | Hub cavern, dens, start screen | Aquatic Atmosphere, Beneath The Waves (underscores) |
     | Kelp Shallows | Kelp Forest, Beneath The Waves, Aquatic Atmosphere |
     | Coral Reef | Great Barrier Reef, Ethereal Expedition |
     | Shipwreck Graveyard | Desolate Ocean, Underwater Kingdom (underscore) |
     | Open Blue | Infinite Expanse, Endless Sonar |
     | Sunken Ruins | Ethereal Expedition, Underwater Kingdom (underscores) |
     | Hydrothermal Vents | Deep Sea Descent, Abyssal Plain |
     | The Trench | Mariana Trench (underscore), The Deep Sea Dwellers, Nightmare of the Abyss |
     | Megalodon near | Dangerous Predator, Predator (a) |
     | Giant Squid near | The Kraken Lurks 2, Predator (a) |

     Crossfades between places (after 4 s, so a border doesn't flip it), resumes a
     track when you swim back within 2 minutes, and ducks under the roll reveal.
     Connor picks by ear; swaps come from the same album (`Config/Music`).
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
