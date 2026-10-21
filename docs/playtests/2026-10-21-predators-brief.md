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

## 4. Report

Write `docs/playtests/2026-10-21-predators.md`: a row per predator (PASS / FAIL / NOTE: facing, jaw, look, size against the board), your fixes (one commit each), and push `claude/core-systems`.
