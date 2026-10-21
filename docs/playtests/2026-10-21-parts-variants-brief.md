Apex Tide — PC brief (2026-10-21): rolled parts and variants as real models, with their bonuses. Built on `claude/world`. Import, test, report. Do §1 → §4 in order.

## How to run it

- Work in `C:\Users\neos1\Desktop\apex-abyss` on `claude/core-systems`, in **`ApexAbyss.rbxl`**. Rojo runs on port **34873**.
- If the Output fills with "Authentication required to access Asset", Studio's login has lapsed: close Studio, log out and back in, reopen the place. Never save while those errors show.
- **Fixes:** fix clear bugs in what you test, one commit per fix, push each. Leave design calls and feel for the report.
- **Report:** `docs/playtests/2026-10-21-parts-variants.md`, a row per item id (PASS / FAIL / NOTE). Screenshots in `docs/playtests/shots/2026-10-21-pv/`.

## What changed

- **Parts:** the five rolled parts (Angler Lure, Narwhal Horn, Sawblade Snout, Sail Fin, Veil Tail) are Tripo models in the legendary look the owner approved, with glowing cyan bits. Until imported, the old part-built pieces show.
- **Variants:** every fish's variant (Puffball, Sabrecuda, Porcupine Puffer, Dragon Moray, Hammerhead, Deepfang Angler) is its own rigged model. It replaces the fish's body while worn. A shade tints its texture (shade skins are made per species).
- **Bonuses**, small and never bite damage, shown in the Wardrobe and the Index:
  - Angler Lure: +25% swallow reach, plus its light.
  - Narwhal Horn: Dash and Torpedo carry 20% further.
  - Sawblade Snout: shells and the treasure arrow/X found from 50% further.
  - Sail Fin: +5% top speed.
  - Veil Tail: turns 15% tighter.
  - Puffball: Dash recharges 20% faster.
  - Sabrecuda: Torpedo lasts 25% longer.
  - Porcupine: Puff Up lasts 25% longer.
  - Dragon Moray: Burrow recharges 25% faster.
  - Hammerhead: Blood Sense marks prey 25% further.
  - Deepfang: Lantern Flash stuns and dazzles 25% further.

## 1. Sync and import

1. Merge `origin/claude/world` into `claude/core-systems`, `rokit install`, `rojo serve`, connect the plugin.
2. Format with `stylua --line-endings Windows src --glob "!**/Packages/**"`.
3. `python tools/fetch_assets.py` (fetches `parts_glb` and `variants_fbx`).
4. **File → Import 3D**:
   1. The five GLBs in `assets/glb/parts/`, no rig, **Import All**.
   2. The six FBX in `assets/fbx/variants/`, rig and textures on, **Import All**.
5. Paste `tools/studio/organize_imports.luau` into the Command Bar. It should print 5 `part` lines and 6 `rigged variant` lines (Sabrecuda and Hammerhead with `Jaw`).
6. **Save the place.** Play once: no errors in the Output.

## 2. Test

**PM — part models.** Admin **Every shade, part, variant and boost trail**. For each part, on the Nibbler, the 'Cuda and the Moray Eel:
1. Wear it in the Wardrobe and swim.
2. It should sit where it belongs: lure on top of the head with its crystal dangling in front of the mouth, horn and saw straight out of the snout, sail standing on the back with its tall end forward, veil flowing behind the tail.
3. It should move with the fish and point the right way.
4. The cyan bits should glow, most clearly in the Trench.
5. Screenshot each. If one points backwards, set its `Facing` attribute to "-Z" on the MeshPart in `ReplicatedStorage.PartModels` and note it.

**VM — variant models.** For each fish, wear its variant:
1. The body should become the new model.
2. It should swim nose first with a smooth spine wave; the Sabrecuda and Hammerhead jaws should snap on a bite.
3. Take it off: the normal fish comes back.
4. Wear a shade with the variant on: it tints, nothing breaks.
5. The roll card and the Wardrobe stage should show the variant model.
6. Screenshot each.

**PB — bonuses.**
1. Hover each part and variant in the Wardrobe and the Index: the bonus line shows.
2. Sail Fin: no `[SpeedCheck]` lines while swimming and dashing.
3. Narwhal Horn: the Dash visibly runs longer.
4. Sawblade Snout: shells are picked up from further.
5. Angler Lure: prey are swallowed from a little further.
6. Hammerhead: Blood Sense marks prey farther out.
7. Deepfang: a Barracuda at ~55 ft is stunned by the flash.
8. Porcupine: Puff Up lasts about 5 s.
9. Dragon Moray: Burrow is ready again after about 6.4 s.

## 3. Report

Finish the report with your fixes and recommendations (fit nudges as `PART_MODELS` `c0`/`length` values in `src/shared/Cosmetics.luau`). Commit it with the screenshots and push `claude/core-systems`.

## 4. Publish

Only if Connor asks in this round; otherwise leave publishing to him.
