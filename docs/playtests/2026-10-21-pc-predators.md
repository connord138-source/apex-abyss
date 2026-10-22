# PC report: 2026-10-21 predators (brief `2026-10-21-predators-brief.md`)

Studio 0.744, `ApexAbyss.rbxl`. Screenshots: `docs/playtests/shots/2026-10-21-predators/`.

## Summary

- **One blocker, fixed in two commits (pushed, then published as v20):**
  - **The problem:** the Reef's **Giant Trevally packs (LV 32) roamed and hunted inside the Kelp
    Shallows.** I saw them at r 213–464 (their band is 520–840), and they killed my LV 1 and
    LV 8 fish at the Kelp Cathedral.
  - **f42d126:** hunters only take, and keep, a fish within 60 studs of their own water.
  - **2a619a0:** roaming waypoints stay round the ring, which stops the chords across the Kelp.
  - **After both:** over 2 min no pack came under r 509. In the Reef they still pack-hunt.
- **Wolf Eels never hunted.** Three of the four sit nose-down by a rock in "roam". Not a blocker,
  since they're harmless, but QR9 fails. Needs a look.
- **`run_predators.sh` wasn't run:** there's no luau CLI on the PC, so please run it in the cloud
  against the two fixes.

## 2–3. Import and models (PM)

**Import:** the 8 FBX went through the Import Queue and `organize_imports` filed them into
`PreyModels`. Each has Root, Head, Spine…, Tail and Jaw (Wolf Eel Spine1–7, Dragonfish Spine1–6).
I saved the place.

**How I measured:** for each one I sat the fish still ahead of it and logged:
- its mode changes;
- the widest angle its model's Jaw bone opened;
- its model's facing against its streamed heading (1.0 = nose along the heading).

| Predator | Water / level | Facing | Jaw on its tell | Look | Size (model) |
|---|---|---|---|---|---|
| Sea Lion | Kelp, LV 6 | 0.99 avg | 19.4° | PASS: dark brown sea lion | 6.0 |
| Goliath Grouper | Wreck bay, LV 18 | 0.97 | 31.3° (the gulp) | PASS: orange-brown, mottled | 33.2 |
| Giant Trevally | Reef, LV 32 | 0.94 | 20.6° | PASS: silver | — |
| Mako | Open Blue, LV 45 | 0.96 | 23.3° | PASS: blue-grey (red-lit in its tell) | 16.0 |
| Sixgill | Ruins, LV 60 | 0.98 | 25.5° | PASS: dark grey, heavy | 26.0 |
| Wolf Eel | Vents, LV 75 | 1.00 (it doesn't move) | 3.7° (never struck) | PASS: grey with dark spots | 22.0 |
| Goblin Shark | Trench, LV 90 | 0.98 | 39.6° (the jaw throw) | PASS: pale blue-grey, long snout | 22.0 |
| Black Dragonfish | Trench, LV 88 | 0.94 | 35.0° | PASS: dark with luminous dots, **cyan lure glowing below its chin** | — |

- **Mouths:** no pink mouths seen.
- **Swimming:** every one swims nose first. The few low minimum dots (0.3–0.7) were during
  turns.

## QR checks

| # | Result | Notes |
|---|---|---|
| QR1 | PASS | **Barracuda:** at LV 18 it read "LV 18 · EVEN FIGHT"; at LV 28, "LV 18 · WEAKER" in green; at LV 38, "WARY OF YOU". **Reef Shark:** "LV 34 · EVEN FIGHT" on the reef at LV 30, and "LV 45 · EVEN FIGHT" in the Open Blue. The STRONGER line at LV 10 wasn't checked. |
| QR2 | PASS | **Bites to kill a Barracuda (LV 18 fish):** at LV 18 about 8 landed bites ("You killed the Barracuda! +21 kg Haul"). At LV 28, 5 bites (+32 kg). At LV 38, **one**: "You swallowed the Barracuda whole! +36 kg Haul". **Pay:** no coral toast at any level. The Haul toasts show food in kg, which grows with level, so they don't show the pay cut. |
| QR3 | PASS (partly) | **Shy:** at LV 38 the Barracudas and Groupers read WARY OF YOU, and none started a hunt in 10 s. **Fight back:** not seen, because one bite swallowed it. |
| QR4 | PASS | **In the tutorial:** after admin resetTutorial, a Sea Lion with my fish 14 studs ahead only roamed for 15 s. **After it:** a nip at 3.0 s (7%) and 6.8 s, the toast "The Sea Lion has had its fun and leaves you be", then roaming for the 33 s left. The juke wasn't tried by hand. |
| QR5 | PASS (pull) | **Pull:** "GOLIATH GROUPER · GULP · DASH OUT". My free fish was drawn 11.9 studs into its mouth, and a gulp bite took 40–48%. **Dash:** escaping by Dash wasn't tried by hand. |
| QR6 | PASS | **Pack:** three together with "PACK · HIDE IN THE ARCHES" and PACK HUNTING YOU, attacking from different sides (−40°/+46°/+70°). **Hiding:** in the Blue Hole tunnel, none came within 200 studs. **After the fixes:** the packs still pack-hunt in the Reef. |
| QR7 | PASS (warning) | "MAKO SHARK · FROM BELOW · JUKE NOW" on every tell (3.2, 5.1, 9.6 s); a bite takes 30%. Juke timing wasn't tried by hand. |
| QR8 | PASS | Big (26 studs) and slow; each bite took 40%, 4–8 s apart. The model is imported, so there are no stand-in eyes to check. Outswimming it wasn't tried. |
| QR9 | **FAIL** | **No hunting:** four tries over ~50 s, my LV 75 fish 16–25 studs beside or ahead, 85 studs ahead once. Mode stayed "roam" and no LUNGE warning showed. **Pose:** 3 of the 4 eels have heading (0, −1, 0), nose straight down, drawn standing upright beside a rock (`wolfeel_upright`). That looks like being stuck at their `home`. The tether couldn't be tested. |
| QR10 | PASS (warning) | "GOBLIN SHARK · JAW THROW · DODGE SIDEWAYS" on every tell; its jaw opens 39.6°, the widest of any; a bite takes 61%. Dodging wasn't tried by hand. |
| QR11 | PASS (partly) | **Lure:** a cyan lure glows under its chin. **Warnings:** "ITS LURE IS PULLING YOU IN · SWIM OFF", then "IT'S A LURE · DASH OFF" on each burst. **Pull:** my still LV 89 fish moved only 0.4 studs (the dragonfish closed on it instead), so I couldn't see the pull. |
| QR12 | NOT TESTED | |
| QR13 | PASS | **Reef:** 55.3 FPS on the Blue Hole highway with a pack, 4 Reef Sharks and 5 Sea Lions streamed (round 3 ~46). **Trench:** 55.9 at the spine view and 50.6 in the ribcage (round 3 ~43). **Errors:** 0 `[Guard]` lines all session. |
| QR14 | PASS | **Index:** INDEX → GUIDE has a "Predators" entry: ten levels up bites it apart, twenty swallows it, twelve up it won't hunt you, read the warning. **FISH menu:** its subtitle reads "Each fish levels up on its own, and fights go by its level". |

## Fixes (pushed)

### f42d126 Predators keep to their own water when they hunt

- **What I saw:**
  - 02:01 local: pack #30–32 at r 213–231 (80–85°) and pack #24–26 at r 424–456.
  - 02:02: #30–32 HUNTING my LV 8 fish at the Kelp Cathedral's way in (r ~273), which they
    killed.
  - The Kelp Shallows is LV 1–10.
- **Cause:** `pickTarget` and `keepsHunting` checked only the leash (sense range × 2.2), so a
  pack followed a fish anywhere.
- **Fix:**
  - A plain hunter now takes and keeps only a fish within `CHASE_SLACK` 60 studs of its band and
    sector. `inRange` gains a slack argument.
  - Packmates join through `keepsHunting`, so they follow the same rule.
  - Bosses are unchanged.

### 2a619a0 Roaming predators keep round their ring

- **What I saw:** with the first fix in, the packs still swam through the Kelp (r 213–464), just
  without hunting.
- **Cause:** each roam waypoint was anywhere in the sector. The Reef's sector spans 270°, so
  straight swims between two waypoints cut chords across the middle, down to the hub's keep-out.
- **Fix:** the next waypoint lies within `ROAM_ARC` 50° of where the creature is, clamped into
  its sector (`pickAngle`). Spawns still pick anywhere.
- **Retest, fresh Play, 2 min:** every pack stayed at r 509–667.
- **Side note:** `randomWaypoint`'s fallback averages `angles` {225, 135} to 180°, which is the
  Wreck bay. That's wrong for a sector that wraps, but it only runs when 20 tries all land in the
  Trench.

## Recommendations

- **Wolf Eels:** check why they settle nose-down at their `home` and never take a target. A
  `home` against or inside rock may pin the steering.
- **Cloud check:** rerun `run_predators.sh` with both fixes. Its sim fish may leave a band
  while fleeing, which now ends the hunt.
- **Fights by feel:** play the juke and Dash escapes by hand (grouper, mako, goblin).
