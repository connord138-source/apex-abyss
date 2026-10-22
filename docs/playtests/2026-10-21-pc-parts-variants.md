# PC report: 2026-10-21 parts and variants (brief `2026-10-21-parts-variants-brief.md`)

Studio 0.744, `ApexAbyss.rbxl`. Screenshots: `docs/playtests/shots/2026-10-21-pv/`.

## Import

Imported with the round's other bundles (`2026-10-21-pc.md` §1). `organize_imports` filed:
- `PartModels.<PartId>`: 5 MeshParts, Facing "+Z" (AnglerLure, NarwhalHorn, SawSnout, SailFin,
  VeilTail).
- `VariantModels.<VariantId>`: 6 rigged Models (Puffball, Sabrecuda, Porcupine, DragonMoray,
  Hammerhead, Deepfang). The Sabrecuda and Hammerhead have a Jaw bone.

No normal maps; my screen's highest score was 0.166.

## PM: part models

Admin "Every shade, part, variant and boost trail". I posed each fish at LV 30 in the den and
looked side-on. The head slot holds one part at a time, so I photographed lure + sail + veil
together, then the horn, then the saw.

| Fish | Lure | Sail | Veil | Horn | Saw |
|---|---|---|---|---|---|
| Nibbler | PASS: stalk on top of the head arching forward, glowing bulb in front of the mouth | PASS: on the back a little behind the middle, tall end forward | PASS: flowing behind the tail | PASS: straight out of the snout | PASS, NOTE: straight out of the snout, but thin (reads as a toothed rod) |
| 'Cuda | PASS | PASS: mid-back, tall end forward | PASS | PASS: from the snout tip | PASS |
| Moray Eel | PASS | NOTE: small, on the rear third of the back (eel `partScale` 0.55) | PASS: at the tail tip | PASS | PASS |

- **Facing:** every part points the right way, so no `Facing` change was needed.
- **Glow:** in the Trench at LV 89 (lure, sail and veil on the Nibbler), the lure bulb, the
  sail's spines and the veil's edges glow cyan-white. The lure lights the rock round the fish.
  Screenshot: `pm_trench_glow`.
- **Moving with the fish:** the posed fish keeps its swim wave and the parts ride it.
- **Rate limit:** Equip is limited to one every 0.15 s, so two quick Equips drop the second.
  Not a bug, just a note for scripted tests.

## VM: variant models

| Variant | Body swap (MeshId) | Swims and jaws | Off | Shade (CatchGolden) |
|---|---|---|---|---|
| Puffball (Nibbler) | 1868674252 → 4957229230: round, puffed, white spikes | PASS | PASS | PASS: tinted gold, the sheen sweeps |
| Sabrecuda ('Cuda) | 0706334391 → 4859532353: silver, long sabre fangs, spiny dorsal | PASS: two bites, Snap ×2, Jaw bone opened 20.4° | PASS | NOTE: flat yellow at 14 s, then textured pale gold at 17–22 s |
| Porcupine (Puffer) | swapped: long white quills | PASS | PASS | not photographed |
| Dragon Moray | 2320874136 → 3402260189: crest, horns, glowing spots | PASS | PASS | NOTE: flat yellow at 6 s, then textured gold at 16 s |
| Hammerhead (Reef Shark) | 3709903261 → 4030590741: hammer head | PASS: two bites, Snap ×2, Jaw 20.4° | PASS | NOTE: flat yellow at 14 s |
| Deepfang (Angler) | swapped: three glowing lures, big fangs | PASS | PASS | not photographed |

- **Shade on a variant:** nothing breaks, but the first seconds look wrong.
  - `ShadeSkins` has no variant folders (Nibbler, Cuda, Puffer, MorayEel, ReefShark, Angler).
    So `skinFor` returns nil, and `paintMesh` should tint the variant's own texture straight away.
  - Instead, it showed as a flat glowing yellow silhouette for 6–14 s first.
  - Worth a look in `Cosmetics.paintMesh` and the dress key.
- **Wardrobe stage:**
  - It shows the worn Hammerhead model, with its hammer visible.
  - The VARIANTS tab (6/6) cards each show the real model, and hovering tries each on the
    stage (`wardrobe_variants`).
- **Roll card:** not forced, because there's no admin rig for rolls.

## PB: bonuses

| # | Check | Result |
|---|---|---|
| 1 | Bonus line in the Wardrobe | PASS. **Parts:** Angler Lure "Lights dark water, and small prey drift into your mouth: +25% swallow reach"; Narwhal "Your Dash (or Torpedo) carries 20% further"; Sawblade "Rakes the sand: shells and treasure found from 50% further"; Sail "+5% top speed"; Veil "Turns 15% tighter". **Variants:** Hammerhead "Blood Sense reaches 25% further"; Puffball "Dash recharges 20% faster"; Sabrecuda "Torpedo lasts 25% longer"; Porcupine "Puff Up lasts 25% longer"; Dragon Moray "Burrow recharges 25% faster"; Deepfang "Lantern Flash reaches 25% further". I didn't check the Index's PARTS and VARIANTS tabs. |
| 2 | Sail Fin, no `[SpeedCheck]` | PASS by log: 0 `[SpeedCheck]` lines all session. I didn't do a dedicated swim and dash run with the sail on. |
| 3 | Narwhal Horn | PASS. Same dash peak (63.9 studs/s) both times: fast for **0.68 s** without the horn, **0.78 s** with it (+0.10 s, which is 0.5 s × 0.2). |
| 4 | Sawblade Snout | Not measured in play. |
| 5 | Angler Lure | Not measured in play. |
| 6 | Hammerhead Blood Sense | Not measured in play. |
| 7 | Deepfang | PASS. Lantern Flash on a Barracuda **55.8 studs (51 ft)** off: stunned for the whole 1.6 s sampled. The plain Angler with one 54.4 studs off: no stun. |
| 8 | Porcupine | PASS: Puff Up lasts **4.96 s**. |
| 9 | Dragon Moray | PASS. Burrow was accepted again **5.83 s** after it ended, vs **7.20 s** without the variant. The server runs ×0.85 of the client's cooldowns, so that's the client's 8 → 6.4 s. |

## Recommendations

- The **Sawblade Snout** is thin on a small Nibbler. It could take a `length` or girth nudge in
  `PART_MODELS`.
- The **Sail Fin on the Moray** is small and far back. A larger `partScale` for the back slot
  on the eel would make it read.
- Look at the **flat stand-in on shaded variants** (above).
