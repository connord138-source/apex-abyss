Apex Abyss — PC brief (2026-10-15): the Whale Fall carcass model. Connor said the part-built whale "looks very rough". Run this after the follow-up brief (`2026-10-14-pc-followup-brief.md`). If that brief hasn't published yet, do this first so both go out in one publish.

## What changed (cloud, `claude/world`)

- **New model.** `WorldProps.WhaleFall` comes from the new bundle `whalefall_glb` (sha256 starts `d3ac4436`). It holds one file, `props/WhaleFall.glb`:
  - A chunky low-poly humpback resting on the floor, eye shut, with barnacles.
  - Two bites in its flank show bone-white ribs over a dark hollow. No blood.
- **Already cleaned in the cloud.** The normal map was stripped, the colours were made safe, and both images (colour and ORM) cleared the classifier screen (0.000 and 0.046). There's nothing for you to screen.
- **How the game uses it.** `ChumController.carcass` fits the model to 60 studs long and turns it onto X, with its middle on the cloud's centre so the belly rests a little into the sand. The part-built carcass stays as the fallback.
- **Import list.** `organize_imports.luau` now files `WhaleFall` into `WorldProps`.

## Steps

1. **Sync.**
   - Merge `origin/claude/world` into `claude/core-systems`, then `rokit install`.
   - Run `rojo serve` on port **34873** and connect the plugin.
   - Format with `stylua --line-endings Windows src --glob "!**/Packages/**"`.
2. **Fetch.** Run `python tools/fetch_assets.py`.
   - It should print `fetched whalefall_glb: 1 file(s) ... (sha256 d3ac4436)`.
   - If it refuses the bundle over a sha256 mismatch, stop and report it.
3. **Import.**
   - In **`ApexAbyss.rbxl`**, use File → Import 3D on `assets/glb/props/WhaleFall.glb`. Import that file only.
   - Paste `tools/studio/organize_imports.luau` into the Command Bar and Run.
   - `ReplicatedStorage.WorldProps.WhaleFall` should exist. Save with Ctrl+S.
4. **Checks.** Play, keep the Output open, and use the admin panel. Take screenshots named by check ID.
   - **W1 Model.** Press "Whale Fall now" twice: the first announces it, the second makes it sink in 5 s.
     - The model sinks instead of the part-built blobs.
     - It is about 60 studs long, flippers out, ribs showing.
     - Take one screenshot from the side and one from above.
   - **W2 Sinking.** While it sinks, the **head** dips a little. If the tail dips instead, write "tail first".
   - **W3 Resting.** Once it's down:
     - The belly rests a little into the sand, neither floating over it nor buried past the flippers.
     - The chunks ring round it, not inside the body.
     - Check this in the Kelp Shallows, the Sunken Ruins (still on open sand, never under a lintel), the Open Blue's floor and the Trench (lit enough to see).
   - **W4 Texture.** Every surface shows its texture, with no white or grey faces.
     - If the whale reads much darker than its surroundings, set its SurfaceAppearance's `MetalnessMap` to "" in `WorldProps.WhaleFall`, save, and note that you did.
   - **W5 Output.** No errors from `ChumController`.
5. **Report and publish.**
   - Put the W1–W5 results in the follow-up report (`2026-10-14-pc-followup.md`, section "Whale model"), or in `2026-10-15-pc-whale.md` if that report is already pushed. Push `claude/core-systems`.
   - Publish only on the follow-up brief's terms: File → Publish As → Update existing experience → **Apex Abyss** → Overwrite, keep it **private**. If the permission check refuses it, stop and say so.
