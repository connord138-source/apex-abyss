Apex Abyss — PC session brief: Trench light by rarity, plus the fix round's leftovers (2026-10-09)

Your fix-round report (1a73398) and your roll-card fix (e5b291b) are merged into claude/world. Work in C:\Users\neos1\Desktop\apex-abyss on claude/core-systems.

Connor's ask for this round:
> "I still feel the trench is potentially too dark. Players need at least a bit of visibility ... Maybe some light fluorescence from plankton or a few scattered light spots on the floor ... there should still be about 5-10% visibility with no light, and visibility with a light source scales with how rare the light source is."

## 1. Merge and sync

1. git fetch origin claude/world
2. git merge origin/claude/world. It should fast-forward or merge cleanly.
3. stylua --line-endings Windows src --glob "!**/Packages/**"
4. rojo serve on port 34873, connect, Play Solo. Expect "Server started" and "Client ready" with no errors.

## 2. The Trench (keyboard first, then the Device Simulator phone)

- **T1 No light at all**
  - Wear a shade that doesn't glow, with no Deep Lantern, as the Nibbler or 'Cuda.
  - Teleport to the Trench bottom (Admin → Teleport to Abyssal Trench, then dive to y ≈ −900).
  - Expect roughly 5–10% visibility: canyon walls and nearby fish read as dim blue shapes about 30–50 studs out, never pure black.
  - Log `Lighting.Ambient` and `OutdoorAmbient` there. Expect about (24, 34, 50), rising toward (32, 58, 68) where the plankton is thickest.
  - Screenshot the same spot and view you used in C1 last time, so they can be compared.
- **T2 Light spots on the floor**
  - Count the PointLights under `Workspace.World.Biomes.TrenchGlow` whose parent is a `GlowTip` (glow gardens, up to 42) and the lit `PlanktonMats` in the Trench (all of them now).
  - Swim the canyon floor end to end: you should pass a glowing tube-anemone clump with a pool of light every so often.
  - Screenshot two gardens.
- **T3 Lights scale with rarity**
  - From one fixed spot at the Trench bottom, wear each source in turn and screenshot the same view.
  - For each, log the `Lamp` PointLight's Range and Brightness on your root, whether there's a `LampBeam`, and `Lighting.Ambient`. The holder's view gets clearer for rarer sources.
  - The sources, weakest first:
    1. a Common glowing shade (if one is owned; the Admin "Every shade" button gives them all)
    2. the Deep Lantern (Admin "Charm" → Deep Lantern): range 30, with a beam
    3. Glowspot or Lanternfish (Rare): range 28
    4. Magma (Epic): range 36
    5. the Anglerfish (Admin unlock, then switch in the den): range 46, with a beam
    6. Aurora (Legendary): range 48
    7. Nebula (Mythic): range 60
    8. Ghost or Abyss Ink (Trophy): range 60
  - With a Deep Lantern and a better glowing shade at once, the shade's light wins.
  - Local Server with 2 clients: player 2 sees player 1's light at the Trench bottom.
- **T4 Glowing shades in the shallows**
  - On the shelf, a glowing shade's Lamp brightness is about 20% of its Trench value, so it doesn't flood the light.
  - The Deep Lantern and the lure stay at full brightness everywhere (as before).
- **T5 Performance**
  - FPS at the Trench bottom next to a garden, on PC and in the phone simulator.
  - Report the average and the worst frame, as in C1.

## 3. The fix round's leftovers

- **F1 Vent at (−1161, −436, 174):** its throat now sits on top of the rock covering that chimney. Check that all 26 VentGlow balls have occupancy ≤ 0.5.
- **F2 Garden bed on sloping floors:** at Nook and Burrow, a stone footing under the bed fills the gap on the low side. Screenshot from the low side.
- **F3 Phone with a boss up:** the treasure sonar now sits beside the depth gauge's top, below the biome chip.
  - Check it's clear of the boss bar, biome chip, depth gauge, HEAL and the stall button.
  - Check the TOO DANGEROUS banner doesn't reach it.
- **F4 Phone offer card:** slightly lower and shorter. Check it's clear of the HUD row above and the health bar below.
- **F5 1280×720:** the Kelp Wraps chip sits under the biome chip, not over it.
- **F6 Regression:**
  - Deep Lantern from the Tidecharm Trader (its new blurb mentions rarer shades).
  - The PITCH DARK banner text names all three light kinds.
  - Roll cards still textured on first appearance.
  - Bank and eaten cards.
- **F7 Output:** 0 game errors.

## 4. Before going live (still Connor's call; just report the status)

- The place isn't published to universe 10769954850 yet.
- A pass purchase still needs a non-owner account.

## 5. Report

Write docs/playtests/2026-10-09-pc-trench.md:
- T1–T5 and F1–F7 pass/fail, with the logged values
- the T3 screenshots side by side if you can
- whether the no-light Trench now feels about 5–10% visible, and which light felt right or wrong for its rarity

Commit and push to claude/core-systems.
