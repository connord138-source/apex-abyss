Apex Abyss — PC brief (2026-10-14): bone-white teeth, skins v8.2. Owner: "make sure the teeth are always teeth white and not the color of the skin. All fish should always have bone white teeth."

Run this after the overnight brief's last step (or between steps if the overnight run is waiting on something). It's an import plus a short look.

## What changed (cloud, `claude/world`)

- Every skin on the four toothed fish paints the teeth bone white. Before this, the Angler's fangs, the 'Cuda's teeth and the Reef Shark's small teeth took each skin's colour. The Moray's teeth were already white and stay white.
- Each toothed fish also has a **Natural** skin: its own texture with white teeth (the Angler's lure still glows).
  - `Cosmetics` wears Natural when the fish has no shade.
  - Under a shade that isn't imported yet, it wears Natural tinted.
- Other players' fish with no shade preload their Natural skin (`RollController` → `CardPhoto.preloadSkin`).
- The Nibbler and Puffer have no teeth and didn't change.
- `shade_skins` is now **v8.2** (sha256 starts `feb731f3`). Only four GLBs changed: `Angler_Shades.glb`, `Cuda_Shades.glb`, `MorayEel_Shades.glb` and `ReefShark_Shades.glb`.
  - They hold 28 quads each (27 skins plus Natural).
  - None carries a normal map.
  - Every one exited 0 on the classifier screen (highest 0.172, the Moray's PassRiptide; the four Natural skins 0.002–0.083).

## Steps

1. Merge `origin/claude/world` into `claude/core-systems`. Run `rokit install`, then `rojo serve` on port 34873, and connect the plugin.
2. Fetch the new bundle:
   - Delete `assets/shades/glb`.
   - Run `python tools/fetch_assets.py`. It fetches `shade_skins` because its link changed.
   - It should print `fetched shade_skins: 6 file(s) ... (sha256 feb731f3)`. The fetcher now checks each bundle against the manifest's sha256 and refuses a mismatch; if it does, stop and report it.
3. Screen the four changed GLBs one at a time (`python tools/shades/screen_shades.py assets/shades/glb/<Fish>_Shades.glb --base assets/shades/maps`). Each must exit 0. If any doesn't, stop and report it; don't import it.
4. Import into **`ApexAbyss.rbxl`** (File → Open from File):
   - Import the four GLBs with File → Import 3D, **one at a time**. Wait about 3 minutes between them for moderation.
   - Then run `tools/studio/organize_shades.luau` in the Command Bar.
   - It should print 28 skins for each of those fish (the Nibbler and Puffer keep 27). Save (Ctrl+S).
   - Don't re-import the Nibbler or Puffer GLBs.
5. Look (Play, admin panel). For each check, take a close screenshot of the open mouth, named by the check ID:
   - **T1 Natural.** Wear no shade (Wardrobe → take the shade off) as the Angler, 'Cuda, Moray and Reef Shark. The teeth should be bone white, the body its usual colours, and the Angler's lure glowing.
   - **T2 Dark skins.** Check the same four fish in PassUndertow, PassAbyssalCurrent and one dark line skin each (AngMurk, CudaBlackfin, MorGreen, ShkGrey). The teeth should be white, not the skin's colour, with no glow or sheen on them.
   - **T3 Bright skins.** Check CatchGolden, SunkenGold, CatchPrism and CudaChrome on the Angler and the 'Cuda (CudaChrome on the 'Cuda only). The teeth should be white, with no metal on them. The moving sheen on the top skins (the shark's Nebula, the Moray's Void) slides over the whole fish, teeth included; that's expected, but say if it reads badly.
   - **T4 Others.** Another player (2-player test) with no shade should show white teeth. Note any pale flash while it loads.
   - **T5 Cards.** In a roll reveal, the shade cards' fish should show white teeth.
6. Report the results as `docs/playtests/2026-10-14-pc-teeth.md` and push `claude/core-systems`. Include T1–T5 pass/fail with screenshots, the screen scores, the organize counts, and any errors. Publish only if the overnight brief's publish step allows it.
