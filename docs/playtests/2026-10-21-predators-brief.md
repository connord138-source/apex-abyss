Apex Tide — PC brief (2026-10-21): import the eight new predator models. Built on `claude/world`.

## How to run it

- Work in `C:\Users\neos1\Desktop\apex-abyss` on `claude/core-systems`, in **`ApexAbyss.rbxl`**. Rojo runs on port **34873**.
- If the Output fills with "Authentication required to access Asset", Studio's login has lapsed: close Studio, log out and back in, reopen `ApexAbyss.rbxl`. Never save while those errors show.
- Nothing here is uploaded by hand except the eight FBX imports (Studio uploads their colour maps). Every map was screened with the classifier (highest 0.026) and none is a normal map.

## 1. Sync

1. Merge `origin/claude/world` into `claude/core-systems`.
2. `rokit install`, then `rojo serve`, and connect the plugin (port 34873).
3. `python tools/fetch_assets.py` — it fetches `predators_fbx` into `assets/fbx/predators/` (sha256 30600df5…).

## 2. Import

1. **File → Import 3D**, select the eight files in `assets/fbx/predators/`:
   `"SeaLion.fbx" "GoliathGrouper.fbx" "GiantTrevally.fbx" "MakoShark.fbx" "SixgillShark.fbx" "WolfEel.fbx" "GoblinShark.fbx" "BlackDragonfish.fbx"`
   Rig on, textures on, like the prey. **Import All**.
2. Paste `tools/studio/organize_imports.luau` into the Command Bar and run it. It files each into `ReplicatedStorage.PreyModels.<Id>` with its bones. The Output should list the eight.
3. **Save the place.**

## 3. Check (PM)

1. In `ReplicatedStorage.PreyModels`, each of the eight is a Model with Bones `Root, Head, Spine1…, Tail, Jaw`.
2. Play. With admin, go to each one's water (Kelp edge, Wreck bay, Reef, Open Blue, Ruins, Vents, Trench) and look at one:
   - it swims head first (nose toward its heading), never tail first;
   - its jaw opens on its tell and snaps shut;
   - its colours match the board (no pink mouths; the dragonfish's lure glows cyan below its chin).
3. Screenshot each into `docs/playtests/shots/2026-10-21-predators/`.

## Code: the eight in game (QR)

The eight hunt in code too (same branch). Test with the models imported; anything that
reads wrong without them, note it. Admin's "set level" and "teleport to a biome" get you
to each. 53 plain predators in all: Kelp 5 Sea Lions, Wreck 6 Barracuda + 3 Groupers,
Reef 3 Trevally packs + 4 Reef Sharks, Open Blue 5 Reef Sharks + 3 Makos, Ruins 4
Sixgills, Vents 6 Wolf Eels, Trench 3 Goblin Sharks + 5 Black Dragonfish.

| # | Check | Pass when |
|---|---|---|
| QR1 | Level tags | Every predator's tag has a second line `LV n · STRONGER / WEAKER / EVEN FIGHT` against your fish: a Barracuda (LV 18) reads STRONGER (red) at LV 10, EVEN FIGHT at 18, WEAKER (green) at 26. A Reef Shark reads LV 34 on the reef and LV 45 in the Open Blue. |
| QR2 | Bites by level | Biting a Barracuda kills it in about 8 bites at LV 18, about 5 at LV 28, and **one** at LV 38: "You swallowed the Barracuda whole!", a big bubble burst and a chomp. The coral toast at LV 38 is a small fraction of LV 18's. |
| QR3 | Shy | At LV 31+ a Barracuda nearby reads WARY OF YOU and never starts a hunt on you. Bite it and it fights back for a few seconds. |
| QR4 | Sea Lion (kelp's outer ring, LV 6) | Admin: restart the tutorial. No Sea Lion hunts you during it. After it, a Sea Lion nips (`SEA LION · NIP · JUKE SIDEWAYS`), and a sideways juke as its jaw flashes makes it miss. Sit still: after its second nip it swims off with the toast "The Sea Lion has had its fun and leaves you be" and doesn't come back for 30 s. |
| QR5 | Goliath Grouper (Wreck bay, LV 18) | Sit near one: water streams into its open mouth and you're pulled in (`GULP · DASH OUT`). A Dash breaks the pull and gets you clear. |
| QR6 | Giant Trevally (Reef, LV 32) | Three swim together. One drives at you while the other two swing out to your flanks; their tags read PACK HUNTING YOU. Hiding under an arch or in a tunnel stops them. |
| QR7 | Mako (Open Blue, LV 45) | It comes up at you from below (`FROM BELOW · JUKE NOW`). A juke the moment its jaw flashes escapes; a late one doesn't. |
| QR8 | Sixgill (Ruins, LV 60) | Big, slow and heavy-biting; it's outswum. On the part-built stand-in the eyes glow green. |
| QR9 | Wolf Eel (Vents, LV 75) | It holds near its hole and lunges (`LUNGE · BACK OFF`). Back off about 80 studs and it stays at its hole. |
| QR10 | Goblin Shark (Trench, LV 90) | Late in its tell its jaws shoot forward on the bite (`JAW THROW · DODGE SIDEWAYS`). A sideways dodge early in the tell escapes. |
| QR11 | Black Dragonfish (Trench, LV 88) | A cyan lure glows under its chin and brightens as it hunts. `ITS LURE IS PULLING YOU IN · SWIM OFF` shows and you drift toward it; then it bursts (`IT'S A LURE · DASH OFF`). |
| QR12 | Body size | Your bite lands at each one's body, not at the sea lion's flipper tips or the dragonfish's barbel. A boss bumped into still stops you at its flank. |
| QR13 | Full, not slow | In the Reef with the packs, and in the Trench, FPS stays where round 3 had it (Reef ~46, Trench ~43). Any `[Guard]` error naming PredatorService goes in the report. |
| QR15 | Spread, no mob | Swim the Wreck bay and the Reef's outer half: predators turn up one or two at a time, spread round the water, not in clumps. Let one start on you in the bay and sit still: no more than **two** hunt you at once (a Trevally pack counts as one); the rest hang back about 60 studs. Bite a third one and it fights back (fair game). Note any clump of 3+ you see and where. |
| QR14 | Words | INDEX → GUIDE has a **Predators** entry, and FISH's subtitle says fights go by level. |

## 4. Report

Write `docs/playtests/2026-10-21-predators.md`: a row per predator (PASS / FAIL / NOTE: facing, jaw, look, size against the board) and a row per QR check, your fixes (one commit each), and push `claude/core-systems`.
