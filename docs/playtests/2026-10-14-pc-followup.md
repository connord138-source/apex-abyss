# Apex Abyss — PC follow-up test (2026-10-14)

Studio on `ApexAbyss.rbxl`, `claude/core-systems` fast-forwarded to `origin/claude/world` (3b4e945), Rojo 7.7.0 on 34873. Solo Play, Test → Server & Clients with 2 players, and the Device Simulator (iPhone 17 Pro). Studio has no DataStore here ("Roblox API services unavailable · data will not be saved"), so every Play starts from a fresh profile.

**Not published.** Every check passed (T1–T5, the Deep Pass, F1–F10) and no game script raised an error. File → Publish As was refused again by this session's permission check ("Create Public Surface"), so I stopped there. `ApexAbyss.rbxl` was saved at 14:10:33 with the v8.2 skins filed. To publish: File → Publish As → Update existing experience → Apex Abyss → Overwrite, and keep it private.

Screenshots: `apex-abyss-playtest-shots/2026-10-14-followup/` (72 files). The names below are those files without `.jpg`.

## Skins v8.2 (bone-white teeth)

### Fetch

`python tools/fetch_assets.py` printed `fetched shade_skins: 6 file(s) -> assets/shades/glb (sha256 feb731f3)`.

- It re-downloaded all 8 bundles, because the manifest's links and sha256 values have changed.
- The Nibbler and Puffer GLBs are byte-for-byte the same size as in v8.1.
- I wasn't allowed to delete the old `assets/shades/glb`, so it was renamed `assets/shades/glb_v81_old` (untracked). Delete it whenever you like.

### Screens

There is no `assets/shades/maps` on this PC (those are the cloud's baked `.npz` files). So the brief's command (`--base assets/shades/maps`) ran without a base and used the strict fallback rule. Two GLBs failed that way:

| GLB | Brief's command (no base) | Against the fish's own texture |
|---|---|---|
| Angler | exit 0, 64 screened | exit 0, 64 screened · highest PassRiptide_emit 0.125 · Natural 0.002, adds 0.0% |
| Cuda | **exit 1**: `Cuda_Shades.glb:Natural: pale 3.6% (> 2.0) (no base texture to compare: pass --base)` | exit 0, 49 · highest PassUndertow 0.103 · Natural 0.001, adds 0.1%, pale 0.0% |
| MorayEel | exit 0, 46 | exit 0, 46 · highest PassRiptide 0.172 · Natural 0.023 |
| ReefShark | **exit 1**: `ReefShark_Shades.glb:ShkBlacktip: pale 2.1% (> 2.0) (no base texture to compare: pass --base)` | exit 0, 45 · highest Natural 0.083 |

I stopped before importing and asked Connor; he said to import all four.

- The second column is the 10-11 method: each fish's own colour texture, taken from `assets/fbx/species/<Fish>.fbm`, as `--base`.
- That run matches the cloud's: 204 screened, highest 0.172, Natural 0.002–0.083.
- Each Natural skin is that same texture with only the teeth changed. The mean difference is 5–8 out of 255, and the texels that changed average near-neutral white.

### Import

File → Import 3D, one GLB at a time. Each went green in the Import Queue:

| GLB | Time | Quads | Maps (colour/metal/rough) | Normal maps | Loaded |
|---|---|---|---|---|---|
| Angler | 13:56 | 28 | 84 | 0 | all |
| Cuda | 14:01 | 28 | 84 | 0 | all |
| MorayEel | 14:05 | 28 | 84 | 0 | all |
| ReefShark | 14:09 | 28 | 84 | 0 | all |

- **Nothing was rejected or moderated.**
- The Angler upload logged one HTTP 502 (below) on AngSeadevil's colour map, and that map loaded fine a minute later.

### Organize and save

`organize_shades.luau` printed `[organize_shades] filed 112 skin(s) for 4 fish under ReplicatedStorage.ShadeSkins`.

- Before: 27 skins for every fish.
- After: Angler, Cuda, MorayEel and ReefShark 28 each, Natural included. Nibbler and Puffer 27.
- No `_Shades` models were left over.
- Saved at 14:10:33 (1,908,272 bytes).

### Teeth in every skin's texture

`teeth_texels.py` (scratchpad) used the texels Natural paints bone white as the teeth mask, then checked every skin:

- **Colour:** 216–229 per channel.
- **Glow:** ≤ 0.012, while the bodies go up to 0.32.
- **Metal:** ≤ 0.04, while the bodies go up to 0.64.

## Results

| Check | Result | Notes | Screenshots |
|---|---|---|---|
| 1 merge and sync | pass | Fast-forward to 3b4e945; `rokit install`; Rojo already serving and connected; StyLua clean; first Play Error 0, Warning 0. | |
| T1 Natural | pass | All four fish at LV 40 with no shade wear `Natural` (the worn SurfaceAppearance matches `ShadeSkins.<Fish>.Natural`). Teeth bone white, bodies in their usual colours, the Angler's lure glowing. The Angler's fangs look very bright because the lure's light hangs just above them; their glow texels are 0.000. | `T1-*` |
| T2 dark skins | pass | PassUndertow, PassAbyssalCurrent and AngMurk / CudaBlackfin / MorGreen / ShkGrey on each fish: teeth white, no glow or sheen on them. A slight blue cast on the Moray's and 'Cuda's teeth is the water light (it's the same in Natural). | `T2-*` |
| T3 bright skins | pass (one note) | CatchGolden, SunkenGold and CatchPrism on the Angler and 'Cuda, plus CudaChrome: teeth white, no metal (texels metal ≤ 0.03). On the 'Cuda in CatchGolden the teeth read pale cyan in the hub's blue light next to the gold (the texels are 229/228/222 with metal 0.02). SunkenGold's warm light makes them ivory. The sheen: see "For a decision". | `T3-*`, `T3x-*` |
| T4 others | pass | 2 clients. B sees A's Angler, then A's 'Cuda, with no shade wearing Natural with white teeth. B's watch on A's new fish: Angler skin on at 0.05 s, texture ready at 0.32 s, respawn 0.02 / 0.02 s; 'Cuda first sighting skin 0.03 s, texture 0.37 s; no frame drawn without a skin. No pale flash seen, but a texture can still be loading for up to ~0.35 s on a first sighting. | `T4-*` |
| T5 cards | pass | Fresh 2-player profile as the Angler: the Seadevil, Bioglow and Lanternfish shade cards show the Angler in that skin with white fangs. (The solo session had every shade granted, and owned shades are left out of rolls.) | `T5-*` |
| Deep Pass id | pass | Game Settings can't open on this file: Experience Settings says "Save to access Experience Settings · Save to Roblox" (PlaceId 0), which would upload it, so not clicked. Creator Hub in my browser isn't signed in. `MarketplaceService:GetProductInfo(3718493448, Product)` gives "Deep Pass", 399, Developer Product, for sale, and the description in `Config/Monetization` word for word. No change, no commit. | |
| Deep Pass panel | pass | DEEP PASS · R$ 399 gold and live. Studio: "Buy item · Deep Pass · 399 · This is a test purchase. Your account will not be charged." → Buy → "Purchase completed · You have successfully bought Deep Pass." The button goes, the row reads DEEP ✓, state `pass.paid = true`. +4,000 pass XP became 4,800 (×1.2) → tier 2, CLAIM ALL (4) → "Claimed: 100 coral · 20 shells · the Riptide skin (Nibbler) · 300 coral · 60 shells". | `DP-*` |
| F1 shaft lift | pass | Den level 5, shafts: Hall at z −29 (radius 7), Sanctum at z −62 (radius 8). LV 100 Nibbler, Pufferfish and Reef Shark (length 16.9). Space under each mouth rises straight on the axis (Sanctum −55 → −21, Hall −19 → 17/20); C over each mouth drops straight (−31 → −64, 4 → −30). Started 8.5–9.3 studs off the axis it eases on as it rises (x 9 → 3 → 0). W with the camera pitched up 52.8° lifts like Space. Swimming level past a mouth isn't pulled in (Hall at 22° pitch: y −29 → −15; main storey at 0.4°: y 5–7). Holding Space under the Sanctum mouth carries the fish along the Hall to the second shaft and up into the main room. No `[SpeedCheck]` line. | (positions in the log) |
| F2 Whale Fall | pass | 10 natural cycles (19:48–21:02): 120–121 s from a whale ending to the next announcement, every time. "Whale Fall now" while announced: "The Whale Fall in the Coral Reef sinks in 5 s" (sank 6 s later). While feeding: "Whale Fall in the Coral Reef in 5 s": the feeding whale ends ("warn done") and a new one sinks 6 s later. Sunken Ruins whale at (1141, −726): floor −426.0 = ground −426.0; from above it lies on open sand beside a ruin block, nothing over it. Also the Coral Reef ×2 and the Hydrothermal Vents, all on open floor; every natural whale had ground ≤ floor + 0.8. | `F2-*` |
| F3 tutorial and pressure | pass | LV 1 fish on tutorial step 2 on the Open Blue floor (y −400): "TOO DEEP FOR NOW · head back up above 460 ft", Pressure 1.00, PressureSafe true, health 115 for 14 s. After admin finish: "CRUSHING · too deep for your level · rise above 460 ft", 113 → 106 → 99 → 94 → 87 (~3%/s). The first try showed no meter at all because the Megalodon was up (no pressure within 500 studs of a boss); I sent it away. | `F3a-*`, `F3b-*` |
| F4 pillar backing | pass | Snap on. Hall back room pillars (22, −30) and (22, −42): Driftwood Table and Driftwood Shelf ghosts GREEN at x 17.7–17.8, turned 90° ("snapped"), placed. Sanctum nave pillars (20, −15) and (20, −25): the same, at x 15.7–15.8, placed. Walls: a Barrel Table at the apse's back wall snaps on, turned 0°, placed. Aiming through a pillar's deck hole lands the piece behind the pillar against the side wall; aiming on the deck in front works. | `F4-*` |
| F5 phone titles | pass | iPhone 17 Pro, Play restarted. Shop, Your Den, Wardrobe, Codes, Pass, Log and Daily: every title and subtitle starts right of Roblox's buttons (SHOP at x 385 against the chat button's ~360). The wide windows' panels still run under the buttons; only the text moved. | `F5-*` |
| F6 banners | pass | "Achievements: all done" only marks achievements and never sends a banner, so I used Achievements reset and then a bank: "+120 kg BANKED" from 21:21:41.437 to 44.343, then "ACHIEVEMENT · DEEP DIVER" at 44.648. Catch: a bank, then admin Catch of the Week 0.13 s later: Banked 21:22:45.281 → 48.195, "CATCH OF THE WEEK · GLOWING SNAPPER" at 48.484. Track unlocks use the same `banner()`; admin `trackAdd` sends no client banner. | `F6-*` |
| F7 Apex nametag | pass | 2 clients, A crowned Apex. From 72.6 studs B reads "Player1 / ★ APEX · 640 BOUNTY · EVEN FIGHT" in gold, and A has its gold outline. | `F7-*` |
| F8 chum lure | pass | 100 kg burst, cloud 379 studs from the hub, a Barracuda 108 studs away, my fish moved 120 studs aside. It reached the cloud in **7.7 s** (106 → 94 → 82 → 69 → 56 → 44 → 32 → 21 → 12) and then circled it at 11–25 studs. (A first try with my LV 62 shark 14 studs from the cloud got "BARRACUDA · INCOMING": it hunted me, so I didn't count it.) | |
| F9 bait | pass | LV 21 Reef Shark, Open Blue bait: "+46 kg bait · HOOKED!" (Haul 0 → 45.57 kg, 62% of the overnight +73 kg, which was also an Open Blue bait). Landed: "the fisherman kept 14 kg" (30%). | `F9-*` |
| F10 regressions | pass | **Tutorial** start to finish as a fresh LV 1 Nibbler: leave the hub, eat 10, bank, 5 shells, level 10 → "TUTORIAL COMPLETE · The 'Cuda is yours". **Banking** (F6). **A roll** (T5). **Treasure Wheel**: "YOU WON 40 SHELLS!". **Build snap** (F4). **L layout**: "Laid out 5 Kelp Cottage pieces" (5 → 10/125). **Pod join**: invite → "Player1 wants you in their pod" → JOIN → "You joined Player1's pod", POD 2, PODMATE on the tag. **Hook break-free**: 14 right-click mashes → "You broke free, and kept the bait!" 9.0 s after hooking. | `F10-*` |
| 5 publish | **not done** | Refused by the session's permission check (see top). | |
| X1 controller | not run | No real controller here. | |

## Output

- **Game scripts: no errors** in any session (solo 14:13–14:28, 17:30–21:34; 2 clients 14:28–14:33 and 21:34–21:38; phone 21:38–21:41).
- **During the Angler import** (Studio, 13:56):
  - `Unable to load Workspace.Angler_Shades.AngSeadevil_Node.AngSeadevil.SurfaceAppearance - ColorMap 'rbxassetid://82915556577902' (Error: HTTP 502).`
  - `Unable to generate 'Workspace.Angler_Shades.AngSeadevil_Node.AngSeadevil.SurfaceAppearance' due to some of the textures being unavailable. Change a TextureId property to retry.`
  - `[Roblox][AssetManager.AssetManager.Src.Controllers.PluginController] Could not fetch newly uploaded asset info. (x29)`
  - The map loaded a minute later.
- **Each test window (server and clients)** logged 4 × `Failed to apply StyleRule property 'CornerRadius' from '>> .RoundedCorner8 ::UICorner': Unable to cast string to UDim`. These are Studio's own UI; nothing in `src` uses StyleRules.

### [SpeedCheck] lines

- `21:33:38.078 [SpeedCheck] Dillionaire138 (10860839150) moved 152 studs in 1.0 s (allowed 106) · 3 strikes in 30 s · length 2.6`
  - This was my client-side teleports from shell to shell during the tutorial's shell step (LV 8 Nibbler). It's test noise.
  - None came from the shaft lifts, whales, hooks or the chum test.

## For a decision

1. **Bait from deep biomes is in reach of any fish.**
   - A bait is sized by the middle level of the biome under the boat, but it hangs 60–300 studs under the surface, above every crush line.
   - A LV 21 fish took a Trench bait: "+4.6 t bait", and broke free with it. A Vents bait gave +988 kg.
   - With ×2 Mass, new against old per biome:

     | Biome | Kelp | Wreck | Reef | Open Blue | Ruins | Vents | Trench |
     |---|---|---|---|---|---|---|---|
     | New | 0.8 | 2.7 | 12.6 | 45.6 | 212 | 988 | 4,603 kg |
     | Old | 1.3 | 4.3 | 20.2 | 72.9 | 340 | 1,581 | 7,364 kg |

   - Options:
     - Size bait by the depth it hangs at.
     - Size it by the taker's level.
     - Cap it at a few levels' worth.
2. **The Nebula sheen turns the Reef Shark's teeth violet.**
   - The sheen layers slide over the whole mesh, teeth included (the brief expected this).
   - On the shark's tiny teeth, seen from the front, they read purple rather than white.
   - On the Moray in Void they read white with a lavender cast, which is fine.
   - If teeth must always be bone white, the sheen needs a teeth-free mask or less strength at the mouth.
3. **The teeth brief's screen command can't run on the PC as written.**
   - `--base assets/shades/maps` only exists in the cloud, so without it the Cuda and Shark GLBs fail the strict fallback.
   - Options:
     - Ship the bases.
     - Let `screen_shades.py` read the `.fbm` colour textures (`--base assets/fbx/species`).
     - Name the base in future briefs.

## Feel and balance

- **Chum lure:** 7.7 s from 108 studs (it was ~15 s).
- **Bait:** +46 kg in the Open Blue (it was +73).
- **Predator targets:** a Barracuda goes for a fish over a chum cloud next to it, as expected.
- **CatchGolden teeth:** pale blue against the gold in the hub's light (T3).
- **Treasure Wheel:** while the win shows, the spinner's chip reads "E JOIN THE LINE (5)".
- **Studio input:** the game only took keys right after a click in it, and short taps were dropped (holds of 0.12 s worked). That's Studio plus automation, not the game.

## Not covered

- **X1:** no real controller.
- **A catch-track unlock arriving within 3 s of a bank:**
  - Not reachable in a test: the pool is in the den and rare prey are outside, and admin `trackAdd` sends no banner.
  - The Catch of the Week banner goes through the same `banner()` and waited correctly.
- **Game Settings → Developer Products:** can't be opened on the local file, so the id was checked through the product API instead.
