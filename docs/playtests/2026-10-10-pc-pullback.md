# Playtest — Windows PC, 2026-10-10: the pull-back loop and skins per fish (claude/world 0c69adf)

- **Build:** `claude/core-systems` with `origin/claude/world` merged (`0c69adf`, merge `355446a`), plus this round's fixes (below). Pushed.
- **Where:** Connor's PC, Studio, Rojo 7.7.0 on port 34873.
  - Play Solo with the HD 1080 device at "Fit to window"; HD 720 and the iPhone 14 simulator for L1/L3.
  - A Local Server with 2 clients for S3, S4, W3 and the kelp lean.
- **Passes:** the first pass and part of the second ran before the fix round (`2026-10-10-pc-fixes.md`); the rest (K1, K6, L1, L3, T1, 9b, C4, S3/S4/W3 with two clients, the fix checks) ran after it.
- **Screenshots:** `C:\Users\neos1\Desktop\apex-abyss-playtest-shots\2026-10-10-pullback\` (107 shots, named by check; also in `apex-abyss-playtest-2026-10-10-pullback.zip`).

## Fixed this round (all pushed to claude/core-systems)

| Commit | Fix | Checked in game |
|---|---|---|
| `0364a5a` | L2: the SAFE ZONE / PROTECTED chip, zone banner and controls hint stack under the tide chip (the tide chip drew over them) | Yes: SAFE ZONE sits just under the tide chip on PC, HD 720 and the phone |
| `ab2accb` | T2: a bait ball near you shrinks away over 1.5 s when the Sardine Run ends (it vanished in your face) and can't be eaten while it shrinks | Yes: see T2 |
| `a9946b2` | B3/W2: the Bounty Chest row, the weekly text and the Catch of the Week banner now name the wheel spins | Yes (chest and weekly text) |
| `d73661f` | New: TUTORIAL COMPLETE and a tide's banner drew on top of each other. Centre banners now take turns: a tide banner waits for the tutorial or catch banner, and those clear a tide banner | Yes: tutorial banner 0.47–6.08 s, then the Calm banner 6.20–10.95 s, never both |
| `13f4ab9` | S8: the Daily panel's day 3 and day 6 cards didn't show their wheel spin | Yes |
| `746b1e1` | New, C4: the den's trophy wall was buried in the rock (see C4) | Yes: all three plaques in view |

## Read this first: which place file has the skins

The 1b import was saved to **`ApexAbyss.rbxl`** in the repo folder (23 v4 skins a fish; checked this round by reading the file: `NibPercula`, `CudaChrome` and the rest are in it). By the second pass, though, the document open in Studio was the cloud copy, **"Apex Abyss" (version 5)**, which was published before the import and still has the old 33 v3 skins a fish. I found this in K6 when the Nibbler's folder held `Thunder`, `Mandarin`, `Xray`… and no `NibPercula` (edit mode too: 33 a fish, none of the new names).
- I reopened `ApexAbyss.rbxl` for everything after that (K6, K1, L1, L3, T1, 9b, C4 and the 2-client session).
- **For Connor:** publish from `ApexAbyss.rbxl` (File → Open from File, then publish to the existing experience). Publishing the cloud copy as it is would ship the old skins and leave the new line skins as tints.
- Effect on earlier checks: S6's jackpot reveals and the Wardrobe previews in the second pass ran on the cloud copy. The skins they showed (Glowspot, Tidepool, Diamond, Divine) were the v3 textures, so those checks still hold for the logic, not for the v4 looks. K6 below is the real look check.

## The short version

| # | Result |
|---|---|
| 1b Import | **PASS.** Six GLBs, one at a time, 3–4 min apart; no rejection or moderation; organize filed 138 (23 a fish). |
| R1 Looks | **PASS up close, FAIL from 100 studs for small prey** (retune). |
| R2 Eating | **PASS.** Golden ×3, Glowing ×6, Crystal ×12, Prism ×25, exact. |
| R3 Natural | **PASS** (about 2 Golden a 5-minute loop at Sardine Run odds). |
| R4 Respawn | **PASS** (back plain after 9 s). |
| C1–C3 | **PASS.** |
| C4 Biggest | **PASS** for sizes and toasts. **Trophy wall FAIL → fixed** (`746b1e1`). |
| T1 Chip | **PASS** (under the boss bar too). The Prism countdown line wasn't seen. |
| T2 Tides | **PASS.** Bait-ball pop fixed (`ab2accb`) and checked. |
| T3 Forecast | **PASS.** |
| B1–B3 | **PASS.** B4 redraw PASS; the rejoin part can't be tested in Studio. |
| W1–W3 | **PASS** (two clients on THIS SERVER). |
| K1–K4 | **PASS.** K5: not testable (Studio doesn't save). |
| K6 Looks | **PASS:** all 138 textured skins match their sheets. Notes: the water's blue light shifts colours, a few skins look alike, four have stair-stepped edges, a first-seen skin is pale for a few seconds, and two Pufferfish skins share the name "Golden". |
| S1–S8 | **PASS.** One wording nit in S5. |
| L1 | **PASS.** |
| L2 | **FAIL → fixed** (`0364a5a`) and checked. |
| L3 | **PASS.** 60 fps on PC and the phone simulator during Golden Hour. |
| 9b | **PASS.** Breaches 13.2–13.6 s apart; Abyss Ink's lamp is the brightest. |
| Output | **0 game errors.** |

## 1b. Import the skins — PASS

- `python tools/fetch_assets.py`: `shade_skins`, 6 files (Angler 5.05 MB, Cuda 4.97, MorayEel 4.95, Nibbler 4.62, Puffer 4.99, ReefShark 4.31).
- File → Import 3D, one fish at a time: Angler 13:57, Cuda 14:06, MorayEel 14:10, Nibbler 14:14, Puffer 14:18, ReefShark 14:23. Every one went green in the Import Queue; **nothing was rejected or moderated.**
  - The importer's only note, on the glowing skins: "Roblox transforms emissive map textures into a grayscale mask texture and modifies the imported color map…" (information).
  - The preview logged `MeshContentProvider failed to process <hash> because 'could not fetch'` 5 times at 13:56:13 (during a preview).
- Moderation check: an enlarged swatch grid of every fish's 23 quads; all textured, none blank (the Angler rechecked about 32 minutes later). This round, every Pufferfish texture I queried reads `Success` for its colour, normal, roughness, metal and glow maps.
- `organize_shades.luau`: before, ShadeSkins held 33 per fish and the six `_Shades` models sat in the Workspace. It printed `[organize_shades] filed 138 skin(s) for 6 fish under ReplicatedStorage.ShadeSkins`; after, 23 per fish and no `_Shades` left. Saved to `ApexAbyss.rbxl` at 14:27 (the old file is backed up in my scratchpad).

## 2. Rare catches

**R1 Looks — PASS up close; FAIL from 100 studs for small prey (retune).** Kelp Shallows, LV 15 Nibbler.
- **Golden:** gold Foil, reads clearly up close (a Minnow is 0.4 × 0.45 × 1.1 studs); its sparkles are faint.
- **Glowing:** a bright teal Neon silhouette with teal sparkles. The strongest of the four, but flat: no detail on the fish.
- **Crystal:** pale-blue Glass, see-through. Head-on it's close to a blob.
- **Prism:** SmoothPlastic whose hue cycles slowly through pastels (teal, purple). It reads as one soft colour at a time.
- **From far off:** a Golden Minnow is a 2–3 pixel speck at 60 studs and invisible at 100–110. A Glowing one is invisible at 100. The haze then: Atmosphere Density 0.74, Offset 0.2, Haze 2.8.
  - **Retune suggestion:** give small prey a bigger light (range 6–18 by rarity) or larger sparkles, so "reads from 100+" holds.
- Screenshots: `R1-golden-close`, `R1-golden-far-60`, `R1-golden-far-110`, `R1-glowing-close`, `R1-glowing-far-100`, `R1-crystal-close`, `R1-crystal-far`, `R1-prism-a/b`.

**R2 Eating one — PASS.** Logged under the Sardine Run (small-fish Haul ×1.5, so a plain fish is 3.0 per kg):

| Sardine | Mass | Haul gained | Per kg | Multiplier |
|---|---|---|---|---|
| Plain | 0.4366 kg | +1.310 | 3.0 | ×1 |
| Golden | 0.2583 kg | +2.324 | 9.0 | ×3 |
| Glowing | 0.1933 kg | +3.479 | 18.0 | ×6 |
| Crystal | 0.2431 kg | +8.752 | 36.0 | ×12 |
| Prism | 0.3518 kg | +26.380 | 75.0 | ×25 |

- Toasts: "GOLDEN SARDINE · +11 coral · Golden skin 3/10"; "GLOWING SARDINE · +44 coral · Glowing skin 1/10" and "NEW IN THE CATCH LOG · Glowing Sardine · +400 coral".
- Crystal: the server toast "Dillionaire138 caught a CRYSTAL SARDINE!", then "CRYSTAL SARDINE · +165 coral · Crystal skin 1/5" and "NEW IN THE CATCH LOG · Crystal Sardine · +1,500 coral".
- Prism: "Dillionaire138 caught a PRISM SARDINE!", "PRISM SARDINE · +550 coral · Prism skin 1/3" and "NEW IN THE CATCH LOG · Prism Sardine · +5,000 coral".
- The HUD pop read "GLOWING +3.9" in teal. The first plain Minnow paid its 25-coral first catch.
- A rare fish 165 studs away didn't count when I jumped to it: the server refuses the jump. That's right.

**R3 Natural spawns — PASS.** No Admin; a 5-minute loop (radius 120 round (−340, 60, 0)) with the Sardine Run's Golden ×1.5 up.
- Unique rare fish within 80 studs: Golden 1, Glowing 2. The loop passes about 51 prey a minute but keeps crossing the same water (about 60 different fish in all), so about 2 Golden were expected at 1 in 35 × 1.5.
- Look changes: 37, none in front of me. The closest was a Sardine turning Foil at 232 studs, which was a respawn.

**R4 Respawn — PASS.** I ate a Golden Sardine (track 7; NEW BIGGEST 0.696 kg over 0.361). It was back after 9 s as a plain Plastic fish.

## 3. Catch Log and catch tracks

**C1 — PASS.** LOG → CATCH LOG (`C1-log-catchlog`, `C1-catchlog-grid-a/b`):
- Track rows: Golden 0/10, Glowing 0/10, Crystal 0/5, Prism 0/3 ("only in the Prism Tide").
- "CATCH LOG · 0/35 found", with columns PLAIN GOLDEN GLOWING CRYSTAL PRISM and 7 prey rows.
- After catching: the Sardine row ✓, biggest 0.70 kg: Plain ×16 0.44, Golden ×8 0.70, Glowing ×6 0.29, Crystal ×3 0.31, Prism ×4 0.44. The Minnow row 0.13 kg; the rest "not caught yet".
- The RARE FISH key: Golden 1 in 35, Haul ×3, coral and DNA ×2; Glowing 1 in 180, ×6, ×3; Crystal 1 in 900, ×12, ×5; Prism only in the Prism Tide, about 1 in 150, ×25, ×8.

**C2 Unlock — PASS.** Admin added Golden ×2 (7 → 9), then I ate one: the banner read "SKIN UNLOCKED · GOLDEN NIBBLER · 10 Golden catches as your Nibbler · wear it in the WARDROBE" (`C2-skin-unlocked-banner`).
- The Wardrobe shows "Golden · Uncommon · WEAR"; worn, the preview turned gold and the button read TAKE OFF (`C2-wardrobe-golden-worn`).
- The next rows read "Rare · catch 10 Glowing fish as this fish" and "Epic · catch 5 Crystal fish". Unowned skins show as "??? Common · roll to find · 1 in 32" (Uncommon 1 in 100, Legendary 1 in 700, Mythic 1 in 1,500).
- The 'Cuda's tracks read 0/10, 0/10, 0/5, 0/3 (per fish).

**C3 Row — PASS.** "CATCH LOG ROW DONE · every Sardine · +3,000 coral, 60 shells".

**C4 Biggest catches — PASS; trophy wall FAIL → fixed.**
- Sizes: 12 Sardine masses (the species' base is 0.3 kg): 0.2413, 0.3517, 0.4366, 0.2583, 0.1933, 0.2889, 0.2431, 0.2435, 0.3518, 0.4428, 0.4172 and 0.6958 (a trophy, 2.3× the base).
- Toasts: "NEW BIGGEST · 0.29 kg Glowing Sardine (was 0.26 kg)" and "NEW BIGGEST · 0.44 kg Prism Sardine (was 0.35 kg)". Plain records were noted (0.3517 over 0.2413, then 0.4366) without a toast, as designed for a plain fish that isn't trophy-sized.
- **The den's trophy wall was hidden in the rock.** The carved back wall bulges in at plaque height. In my Nook, measured from in front of each plaque, the rock stood in front of the face by:
  - BIGGEST CATCH 0.9–3.8 studs;
  - GIANT SQUID 0.2–5.5 studs;
  - MEGALODON 0.04–0.54 studs.
  - From the room you saw bare rock (`C4-trophy-wall-before-*`).
- **Fix (`746b1e1`):** half a second after the den is built (Terrain carved that frame doesn't answer a raycast until later), a grid of 15 rays over each plaque and its trim finds the rock nearest the room. That column (plaque, trim, and the mounted catch, tooth or beak) moves forward to clear it by 0.2 studs, at most 8.
  - After: every plaque is in front of the rock and fully readable: GIANT SQUID "No kill yet", MEGALODON "No kill yet", BIGGEST CATCH "Nothing yet" (`C4-trophy-wall-after-fix`). The side plaques now stand a little forward of the middle one, following the bulge.
  - Before the fix, with a catch, the plaque read "BIGGEST CATCH · Sardine · 0.4 kg", its real mass.

## 4. Tide Clock

**T1 Chip — PASS.** The chip at the top centre names the tide and its time left (e.g. "CALM WATERS 9:45", "GOLDEN HOUR 3:11").
- With the Megalodon up, it sits directly under the boss bar ("MEGALODON · APEX PREDATOR · HUNTING"), with "MEGALODON NEARBY · 116 ft" below it (`T1-chip-under-boss-bar`). With a countdown up, it sits under "THE MEGALODON RISES IN 1:27".
- **Not seen:** the Prism countdown line. I didn't have the chip on screen in the hour before a Prism Tide (the nearest was 17:00 local, 21:00 UTC). A forced Prism Tide showed "PRISM FISH ARE OUT" on that line.

**T2 Each tide — PASS.** Every banner reads "THE TIDE TURNS", the name and a line:
- **Golden Hour:** "Golden fish ×5 · coral from rare catches ×1.5". Golden fish on the map went 28 → 50 in 90 s.
- **Blood Tide:** "Rare fish ×2 · Haul ×1.25 · hunters faster and hungrier".
  - A Barracuda noticed me at 89 studs (60 × 1.5) and roamed at 17.2 studs/s (26 × 0.55 × 1.2).
  - Under Calm: noticed at 58, roaming at 14.0–14.9.
  - The 'Cuda LV 1 (2.25 studs) is ignored, as it should be: ignoreBelow 0.25 × length 9.
- **Sardine Run:** "Bait balls flood the shallows · small fish Haul ×1.5". 320 sardines in view; 8 bait-ball schools of 36. One spread up to 30.6 studs, so a loose cloud rather than a tight ball, and several sat inside dense kelp where they're hard to see.
- **Calm:** "A quiet sea. Rare fish at their usual odds."
  - First pass: a bait ball 18 studs away vanished at once (0 visible by 0.9 s). **FAIL**, fixed in `ab2accb`.
  - **Checked this round:** at ball #76, 28 sardines; on Calm their total scale went 36.8 → 35.0 (0.17 s) → 28.5 (0.50) → 19.2 (0.98) → 10.0 (1.45) → 7.8 (1.61 s). Then they're hidden (Transparency 1). A smooth 1.5 s shrink, no pop.
- **Bioluminescent Night:** "Glowing fish ×3 (×5 out in the deep) · the sea goes dark". Exposure −0.19 → −0.44; Glowing fish 4 → 6 in 90 s.
- **Prism Tide:** "Prism fish swim · every rare fish ×2"; the chip's second line read "PRISM FISH ARE OUT". "A PRISM SNAPPER shimmers in the Open Blue!" came within 3 s.
- **Back to the clock:** "Tides back on the clock", and the chip went to Blood 7:29.
- **Water tints** (OceanGrade TintColor): Golden (200, 220, 222), Blood (198, 203, 220), Sardine (190, 224, 244), Calm (190, 223, 242), Biolum (181, 224, 240), Prism (202, 209, 241). All subtle and never garish; the Blood Tide is barely red.
- A tide banner and the biome banner at once don't overlap (KELP SHALLOWS above, THE TIDE TURNS below).
- Screenshots: `T2-golden-hour-*`, `T2-blood-*`, `T2-sardine-*`, `T2-calm-*`, `T2-biolum-*`, `T2-prism-a`, `T2-prism-announce-log`.
- Also found: schools beyond the draw distance sit at their built position, the origin, hidden inside the beacon rock. Harmless; noted only.

**T3 Forecast — PASS.** LOG → TIDES (`C1-log-tides-a/b`): "now GOLDEN HOUR ends in 4:10", matching the chip's 4:10.
- The list: 14:40 Sardine, 15:00 Blood, 15:20 Sardine, 15:40 Blood, 16:00 Biolum, 16:20 Blood, 16:40 Calm, 17:00 ★ PRISM TIDE ★, 17:20 Calm.
- Footer: "Prism Tide rises at 03:00, 09:00, 15:00 and 21:00 UTC" (17:00 local is 21:00 UTC).

## 5. Bounties

- **B1 — PASS** (`C1-log-bounties`). At LV 15: Catch a Glowing fish (40 shells) 0/1; Eat 30 fish while a tide is up (a Weathered map) 0/30; Bank 4 Hauls (600 coral) 0/4. The chest row and "new ones in 5:24:32" (UTC midnight).
- **B2 — PASS.** "BOUNTY DONE · Catch a Glowing fish · 40 shells". "BOUNTY DONE · Eat 30 fish while a tide is up · a treasure map", then "You found a Weathered Treasure Map! Open MAPS to see it".
- **B3 — PASS.** Admin finish: "BOUNTY DONE · Bank 4 Hauls at your den · 600 coral", then "BOUNTY CHEST · 1,000 coral, 50 shells, 1 Lucky Charm, 1 wheel spin". Wheel spins 1 → 2; Lucky Charm 1. The chest row lacked the spin; fixed in `a9946b2`.
- **B4 — PASS / not testable.** Redraw gave Glowing ×3, Treasure ×1 and Shells ×25. The rejoin part can't be tested: Studio doesn't save.

## 6. Catch of the Week and leaderboards

- **W1 — PASS** (`C1-log-weekly`). CRYSTAL GROUPER, "It swims Crystal ×3 as often all week. The first one you catch pays 5,000 coral, 100 shells, 2 wheel spins and the Great Wave skin…", NOT YET, ends in 1d 5h. (The spins were missing from the text; fixed in `a9946b2`.)
- **W2 — PASS** (`W2-catch-of-the-week-banner-a/b`). The banner read "CATCH OF THE WEEK · CRYSTAL GROUPER · +5,000 coral, 100 shells · the Great Wave skin for your 'Cuda".
  - Server toasts: "Dillionaire138 caught a CRYSTAL GROUPER!" and "Dillionaire138 caught this week's CRYSTAL GROUPER!"
  - Spins 2 → 4, shells +100, coral +6,852 (5,000 + 352 for the Crystal catch + 1,500 for its first catch). The tab read ✓ CAUGHT.
  - A second catch paid only +352 coral; shells and spins didn't change.
  - The banner's spins line was added in `a9946b2` (code checked; I didn't re-catch the week's fish after the fix).
- **W3 — PASS, two clients** (`W3-this-server-two-clients`).
  - Rare Catches, THIS SERVER: "#1 Player2 155 pts", "#2 Player1 100 pts" (Admin "add to my score": everyone +100, Player2 +55). "yours this week: 155 pts".
  - Biggest Haul: #1 Player1 40 kg, #2 Player2 40 kg. Boss Damage: #1 Player2 900 dmg.
  - ALL SERVERS right after adding read "No scores yet this week. Be the first!" (`W3-all-servers`); points are written within a minute. In the single-client first pass, ALL SERVERS showed this server's "#1 Dillionaire138 654 pts" after the write, under the note "(live boards need the published game)".

## 7. Skins per fish

**K1 Wardrobe — PASS.** 24 rows a fish (its 12, then the shared 12), listed from the Wardrobe's own rows:
- **Nibbler:** Percula, Tomato, Maroon, Midnight (Common); Bumblebee, Lilac, Seafoam (Uncommon); Tidepool, Glowspot (Rare); Diamond (Epic); Divine (Legendary); Prismatic (Mythic). Then Golden (Uncommon), Glowing (Rare), Crystal (Epic), Prism (Epic), Great Wave, Living Reef, Shipwreck, Sea Glass (Epic), Ghost and Abyss Ink (Boss Trophy), Sunken Gold (Mythic) and Drowned Pearl (Legendary).
- **'Cuda:** Great, Yellowtail, Chevron, Blackfin (Common); Tiger, Sunset, Ocean (Uncommon); Lunar, Chrome (Rare); X-Ray (Epic); Thunder (Legendary); Comet (Mythic); then the shared 12 (`K1-wardrobe-cuda`).
- **Anglerfish:** Seadevil, Humpback, Warty, Footballfish (Common); Murk, Driftwood, Bioglow (Uncommon); Lanternfish, Glassveins (Rare); Abyss Eye (Epic); Lantern King (Legendary); Starfall (Mythic); then the shared 12 (`K1-wardrobe-anglerfish`).
- I wore the Angler's jackpot-tier Starfall from the Wardrobe: the button turned to TAKE OFF and the preview updated (`K1-wardrobe-anglerfish-starfall-worn`).
- Every fish's own 12 also showed in K6 (Pufferfish, Moray Eel, Reef Shark below).

**K2 Dyer — PASS.** On the 'Cuda: Great 1,500, Yellowtail (owned), Chevron 1,500, Blackfin (wearing). Only its 4 Commons.

**K3 Odds — PASS.** Nibbler and 'Cuda at luck 1: total 1.0000, coral 82.50%, parts 0.12%, 12 skins each, only their own line. With a Lucky Charm (luck 2), coral is 65%.
- 'Cuda: Sunset, Ocean, Tiger, Lunar, Xray, Thunder, CudaGreat, CudaYellowtail, CudaChevron, CudaBlackfin, CudaChrome, CudaComet.
- Nibbler: Mint (Seafoam), Lilac, Bumblebee, Glowspot, Tidepool, Diamond, Divine, Prismatic, NibPercula, NibTomato, NibMaroon, NibMidnight.

**K4 Roll — PASS.** 20 rolls on the 'Cuda: Handful ×10, Pouch ×6, Chest ×1, CudaChrome (Rare, NEW, "1 in 150"), CudaYellowtail and CudaBlackfin.
- The reel's filler cards were the 'Cuda's own skins (Blackfin, Thunder, Sunset), coral, and parts and variants (Sawblade Snout, Hammerhead Variant, Sail Fin, Veil Tail).

**K5 Old skins — not testable.** Studio doesn't save ("[ProfileStore]: Roblox API services unavailable - data will not be saved"), so every Play starts a fresh save.

**K6 Looks — PASS, with notes.** In `ApexAbyss.rbxl`, I laid out all 24 of each fish's skins as side-on copies of my fish in the Kelp Shallows (mid-water, Calm), with Cosmetics applying each skin. I compared them with `assets/shades/previews/<Fish>_sheet.jpg`, then wore the glowing ones.
- **Every one of the 138 textured skins matches its sheet**, and Ghost is its spectral self on every fish. Screenshots: `K6-<fish>-1-12`, `K6-<fish>-13-24`, each fish's Mythic (`K6-nibbler-mythic-prismatic`, `K6-cuda-mythic-comet`, `K6-puffer-mythic-exotic`, `K6-moray-mythic-void`, `K6-reefshark-mythic-nebula`, `K6-angler-mythic-starfall`), and the 4 Commons side by side for the Nibbler (`K6-nibbler-commons`) and the Pufferfish (`K6-puffer-commons`).
- **Glow and pulse — PASS.** Worn on the fish, each skin's glow strength / light brightness sampled every 0.25 s:
  - Glowing (breathe): 1.24 → 1.13 → 0.97 → 0.81 → 0.66 → 0.56 → 0.52 → 0.54.
  - Glowspot (twinkle): 0.72 → 0.66 → 0.66 → 0.68 → 0.74 → 0.70 → 0.69 → 0.98 (light 0.86–1.28).
  - Prismatic (breathe): 0.75 → 0.63 → 0.52 → 0.44 → 0.40 → 0.42 → 0.49 → 0.59.
  - Abyss Ink (wave): 0.64 → 0.61 → 0.79 → 1.08 → 1.36 → 1.50 → 1.44 → 1.22.
  - Comet, Sunburst, Jade Dragon, Bioglow, Glassveins, Abyss Eye, Lantern King and Starfall all glow in the grids, and the Angler's lure glows in all 24.
- **No skin stays white.** Three drew pale for a few seconds the first time they appeared, until their texture arrived: the Pufferfish's Green Spotted and Neon Tetra (still pale after about 3 s) and the Moray's Glowing (about 9 s). Their fetch status is `Success`, so this is download time, not moderation. Up close a moment later all three were right (`K6-puffer-neon-tetra`, `K6-moray-glowing`).
  - **Suggestion:** preload every ShadeSkins texture id at join, as `CardPhoto.warm` does for card photos, so another player's new skin doesn't flash pale.
- **Colours in the water (report, by design?):** the shallows' light is blue (Ambient (26, 58, 82), OutdoorAmbient (56, 108, 136), atmosphere colour (36, 115, 150)). Turning off the colour grade and bloom changed almost nothing; the blue is the light itself.
  - Under it, yellow reads lime: Golden and Bumblebee both look lime-green. Purple reads blue: Lilac and Tidepool both look royal blue. Maroon reads navy.
  - Lit white (a test light), every skin matches its sheet's colour (`K6-nibbler-1-12-whitelit`, `K6-nibbler-13-24-whitelit`).
  - If Golden should read gold in the shallows, it needs a warmer, brighter gold (or a touch of its own glow).
- **Too alike:**
  - Reef Shark Blacktip, Grey Reef and Whitetip are nearly the same grey (on the sheet too).
  - The Angler's Seadevil, Humpback, Warty and Footballfish are all near-black.
  - The 'Cuda's Blackfin, Chevron and Great are all silver with dark marks; Chrome and Lunar are both pale silver-blue.
  - The Pufferfish's Golden (Common) and Golden (Uncommon, the catch skin) look alike and **share the name "Golden"**, so its Wardrobe lists "Golden" twice. Suggest renaming the Common (for example "Gold Puffer").
- **Stair-stepped edges:** the 'Cuda's Tiger (the belly line), the Pufferfish's Neon Tetra (the cyan stripe), the Moray's Void (the swirl) and the Reef Shark's Aurora (the stripes). The 'Cuda's Sunset reads fine in game (`K6-cuda-sunset-tiger-stairstep`).
- **In a grid only:** Diamond, Divine and Drowned Pearl blew out into white because six skin lights sat side by side. Worn alone, Diamond is a clear pale-blue mosaic (`K6-nibbler-diamond-worn`).
- **Sheet label:** the sheets label Drowned Pearl "Mythic"; the game has it Legendary.

## 8. Treasure Wheel

**S1 Placement — PASS.** The wheel stands on a round stage on the plaza floor at 240°, 62.3 studs from the beacon, at (−31, 15, −54), 42 × 41.7 × 35.6 studs. Its button is at (−26, 7.5, −45).
- It sits between the den 9 and den 10 tunnels, with the Tidecharm Trader's stall front-left (its counter at (−24, 6, −24)). It blocks no stall, door, tunnel or the beacon.
- It reads as a game-show wheel and fits the cave (`S1-wheel-plaza`, `S1-wheel-face`).
- **Details pass — PASS.**
  - Each slice has its big word near the rim over its small word (300 CORAL, MAP TREASURE, 40 SHELLS, FEAST CHARM, +2 SPINS, KELP 2 WRAPS, LUCKY CHARM, SKIN JACKPOT). No word crosses a gold divider or touches the hub, at rest or mid-spin.
  - The hub is a pale pearl dome ringed by gold collars, with no pink jewel.
  - The bulbs are small and warm, with only a slight white bloom.
  - PRIZES & ODDS has 8 rows, each a swatch, the prize and its %: 300 CORAL 24%, TREASURE MAP 10%, 40 SHELLS 18%, FEAST CHARM 12%, +2 SPINS 10%, 2 KELP WRAPS 12%, LUCKY CHARM 10%, JACKPOT · SKIN 4%, then the footnote.
  - FREE SPINS has 4 rows (Every 4 hours +1, Bounty Chest +1, Catch of the Week +2, Daily streak days 3 and 6 +1) and a footnote. Nothing runs off either board.
  - Screenshots: `S1-wheel-square-on-*`, `S1-wheel-close`, `S1-board-free-spins`, `S1-board-prizes-odds`.

**S2 Hint — PASS.** At the button, a chip at the bottom centre above the Haul card reads "[E] SPIN (1)" and "next free in 3h 56m" in grey. With 2+ spins it adds "[T] SPIN ALL"; with 3 it says "free spins full" (`S2-hint-chip`, `L1-hd1080-wheel`).
- It comes on at 6 studs and goes at 10.
- From the Tidecharm Trader's counter to the button, the stall hint and the wheel hint handed over cleanly (both on at once: 0 frames).
- On the phone, it's SPIN (3) / ALL buttons (`L1-iphone14-wheel`). I didn't test the controller's Y.

**S3 Spin — PASS, one client and two.**
- One client: the sign read "Dillionaire138 is spinning..."; the wheel turned for 5.5 s and stopped with the flapper centred on the 40 slice. "YOU WON 40 SHELLS! +40 shells", shells 5 → 45; the lit slice under the flapper was SpinIndex 3 (`S3-first-pass-mid`, `S3-first-pass-stop`).
- Second pass: the words stayed inside their slices mid-spin. It stopped on KELP. The compact card at the left, under the HUD buttons, read "YOU WON 2 KELP WRAPS! +2 Kelp Wraps"; the sign read "Dillionaire138 won 2 KELP WRAPS!"
- **Two clients:** Player2, watching from the plaza, saw "Player1 is spinning..." on the sign and the wheel turning (`S3-player2-sees-player1-spinning`). Player1 got its left card "TREASURE WHEEL · YOU WON FEAST CHARM! · Feast Charm: on now" (`S3-player1-left-card`).

**S4 Line — PASS, two clients.** Player1 spun, then Player2 asked to spin. Player2 got "You're #1 in line: the wheel is turning." The sign read "Player1 is spinning... · 1 in line" and Player2's chip "[E] JOIN THE LINE (1)" (`S4-player2-in-line`).
- After Player1's result, Player2's spin started on its own ("Player2 is spinning..."). It paid "Player2 won 2 KELP WRAPS!" with Player2's own left card (`S4-player2-result`).

**S5 Spin all — PASS, one wording nit.** With 10 spins, T ran spin after spin; T mid-way printed "Spin all off." (the spin in progress finished, Feast Charm "on now", and it stopped with 8 left). Run to the end, it printed "Spin all done: you're out of spins."
- A jackpot paused it: "Spin all paused: you hit the jackpot!" There were three natural jackpots in 16 spins (luck).
- **Nit:** when the very last spin is the jackpot, it says "paused" rather than "done".

**S6 Jackpot — PASS.** Rigged and natural jackpots on the Nibbler gave Glowspot (Rare), Tidepool (Rare), Diamond (Epic) and Divine (Legendary). All were its own line, Rare or better, each announced to the server (`S6-jackpot-a/b`).
- With every skin owned, the rigged jackpot paid "Your fish has every rare skin: +2,500 coral" (801 → 3,301) (`S6-all-skins-2500-coral-*`).
- Wearing a jackpot skin from the Wardrobe: done with the Angler's Starfall (K1).

**S7 Free spins — PASS.** A fresh save had 1 spin, and nextFreeAt was about 4 h after joining. The rejoin part can't be tested: Studio doesn't save.

**S8 Other sources — PASS.**
- Day 3 claim: "600 coral, 1 Kelp Wrap, 1 wheel spin" (spins 0 → 1). Day 6: "150 shells, 1 Second Chance, 1 wheel spin" (1 → 2).
- The Bounty Chest +1 (B3) and the Catch of the Week +2 (W2).
- The Daily panel's day 3 and day 6 cards didn't list the spin; fixed in `13f4ab9`.

## 9. Layout and performance

**L1 — PASS.**
- **HD 1080 and HD 720:** LOG, DAILY and SHOP sit beside the wallet card, and the wheel chip sits above the Haul card. Nothing overlaps (`L1-hd1080-wheel`, `L1-hd720-wheel`).
- **iPhone 14, started as a phone:** the level card starts below Roblox's top-bar buttons, and LOG, DAILY! and SHOP are at the end of the HUD row (`L1-iphone14-start`). The stick, BITE, DASH, HEAL and YOUR DEN don't overlap anything.
  - At the wheel, ALL / SPIN (3) sit on the right, under the depth gauge and above HEAL/BITE/DASH, covering none of them (`L1-iphone14-wheel`).
- **Studio-only note:** switching the device to a phone *mid-session* leaves the left column where the desktop put it, so Roblox's buttons overlap the level card's top by about 10 px. The shift is decided when the HUD is built. A real phone starts as a phone, so it never sees this. That's what my earlier "top-bar icons overlap the LV card" note was.
- The LOG window fits at all three sizes, and its tabs and rows read.

**L2 — FAIL → fixed (`0364a5a`).** The tide chip drew over the SAFE ZONE chip and the PROTECTED Ns chip. They now stack under it, checked on PC, HD 720 and the phone. The boss bar: see T1.

**L3 FPS — PASS.** Golden Hour, Kelp Shallows, 10 s each:

| Device | Average | Worst frame |
|---|---|---|
| PC, HD 1080 | 60.0 fps | 24.1 ms |
| iPhone 14 simulator (750 × 389) | 60.0 fps | 27.1 ms |

## 9b. From the boss round

**Breach timing — PASS.** Admin summon, then hurt 0.8 (the Megalodon at 20%, Last stand). From the client's PredatorEvent stream, seconds after the hurt:

| Breach | Tell | Rocket | Crash |
|---|---|---|---|
| 1 | 4.4 | 6.7 | 8.0 |
| 2 | 17.6 | 19.9 | 21.3 |
| 3 | 31.2 | 33.4 | 34.8 |
| 4 | 44.4 | 46.6 | 48.1 |
| 5 | 57.9 | — | — |

- Start to start: 13.2, 13.6, 13.2 and 13.5 s (they were about 24). It escaped at 60.2 s ("gone"), as the Last stand clock says.
- `_G.ApexBoss` wasn't reachable from the Server command bar in this Studio build, so I used the Admin panel's summonBoss and hurtBoss, which do the same.

**Abyss Ink's light — PASS.** At the T2 Trench spot (−133, −890, 1167), 1,224 ft, after 6 s to settle:

| Fish and skin | Lamp brightness | Range | Colour |
|---|---|---|---|
| 'Cuda, Abyss Ink | 5.13 | 60 | (170, 120, 255) |
| Moray Eel, Abyss Ink | 5.13 | 60 | (170, 120, 255) |
| Reef Shark, Nebula | 3.80 | 60 | (170, 110, 255) |
| Moray Eel, Void | 3.84 | 60 | (150, 70, 255) |

- Abyss Ink is the brightest and the lightest violet; by eye too, its glowing cracks read clearly in the dark (`9b-*`).

## 10. Output

**0 game errors** in every session.
- **Play Solo** (from `ApexAbyss.rbxl`): "Server started", "Client ready". The only notice is ProfileStore's expected warning: `[ProfileStore]: Roblox API services unavailable - data will not be saved`.
- **Play Solo on the cloud copy** (first and second pass): Studio's DataStore errors, because that copy is published and Studio's API access is off:
  - `DataStoreService: StudioAccessToApisNotAllowed: Cannot write to DataStore from studio if API access is not enabled. API: SetAsync, Data Store: ____PS`
  - `DataStoreService: StudioAccessToApisNotAllowed: Studio access to APIs is not allowed. API: GetSortedAsync, Data Store: Weekly_v1_RareCatches_2961`
- **Local Server, 2 clients** (LogService history at the end):
  - The server and Player2: 0 errors, 0 warnings.
  - Player1: 15 lines, all from Roblox's own CoreScripts, none from the game. Among them:
    - `[Roblox][Script Context.StarterScript] Failure to Start CoreScript module PlayerListManager. Requested module experienced an error while loading`
    - `[Roblox][Script Context.StarterScript] Failure to Start CoreScript module TopBar. Requested module experienced an error while loading`
    - `[Roblox][CoreGui.RobloxGui.CoreScripts/InspectAndBuy] Requested module experienced an error while loading`
    - `[Roblox][Script Context.StarterScript] Script Context.StarterScript:507: Invalid value for enum CreatorType`
- **Caused by my test, not the game:** `Invalid CFrame. Must contain finite values. - Client - CameraController:100` every frame, after my K6 helper cloned the fish's Body.
  - The clone kept the Body's Motor6D to the real HumanoidRootPart, so 12 anchored clones pulled the fish to NaN.
  - I removed the clones, reset the fish and dropped outside joints from the helper. No player can do this.

## Verdict

Yes, this pulls me back.
- **The tide clock** is the strongest hook: the chip always says what's on and what's next. Golden Hour visibly fills the water with gold, and the Prism Tide at fixed hours is a reason to log in at a time.
- **The wheel's free spin every 4 h, the three bounties a day and the weekly board** are small daily reasons that stack well. The wheel itself now looks the part and the line works with two players.
- **Rare catches** feel great to eat (the ×3 to ×25 Haul jumps are big, and the toasts are clear).

What feels thin:
- **Rare fish are hard to spot unless they're close.** A Golden Minnow vanishes past about 60 studs (R1), so a Golden Hour mostly rewards swimming through schools rather than hunting a glint.
- **Skins shift colour in the water:** Golden reads lime in the shallows, and Lilac and Tidepool both read blue. Some Commons are near twins: the shark's greys, the Angler's blacks, and two "Golden"s on the Pufferfish.
- **The boards can't be seen live in Studio**, so the weekly race is the least felt part here.

## Not done or not testable

- K5, B4's rejoin and S7's rejoin: Studio doesn't save.
- T1's Prism countdown line: not on screen in the hour before a Prism Tide.
- S2 on a controller (Y): not tested this round.
- The store page uploads stay with Connor (see `2026-10-10-pc.md`).
