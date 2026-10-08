# 3D assets: import guide

The models the game uses are generated with Tripo (`tools/tripo.py`, job files
`tools/tripo_jobs_*.json`), reviewed from the cloud, rigged or squared up in Blender,
zipped and hosted on a durable link. **`tools/assets_manifest.json`** lists the bundles.

The code runs without any of them: every fish and prop falls back to its graybox
parts until its model is imported (`FishBuilder.meshTemplate`, `Props.dress`,
`PropParts.make`, `SchoolController.preyTemplate`).

## What exists (Tripo batch 1, 2026-10-07)

| Bundle | Files | Goes to |
|---|---|---|
| `species_fbx` | Nibbler, Cuda, Puffer, MorayEel, ReefShark, Angler (rigged FBX) | `ReplicatedStorage.FishModels.<SpeciesId>` |
| `prey_fbx` | Minnow, Sardine, Wrasse, Snapper, Grouper (rigged FBX, 4 spine segments: their bones swim) | `ReplicatedStorage.PreyModels.<PreyId>` |
| `prey_glb` | the older static GLB prey (still drawn if that's what is imported; turned round in code) | `ReplicatedStorage.PreyModels.<PreyId>` |
| `props_glb` | GiantKelp, KelpClump, BoulderRound, BoulderJagged, BrainCoral, FanCoral, StaghornCoral, TubeSponge, Anemone, Shrimp, Starfish, Shell, Lantern, CrystalCluster, MarketStall (GLB) | `ReplicatedStorage.WorldProps.<Name>` |
| `props2_glb` | TreasureChest (GLB; the treasure map dig site's chest) | `ReplicatedStorage.WorldProps.TreasureChest` |
| `vendors_glb` | KeeperOutfitter, KeeperMason, KeeperCharms, KeeperDyer, KeeperTrophies (GLB; the five shopkeepers, from `assets/concepts/Vendors.jpg`) | `ReplicatedStorage.WorldProps.Keeper<VendorId>` |
| `boss_fbx` | Megalodon (7 spine segments), GiantSquid (6; the arms trail) (rigged FBX; the world bosses) | `ReplicatedStorage.FishModels.<Id>` |

Not yet made: species growth stages (Fry/Juvenile/Apex), the other biomes' props.
The Barracuda and Reef Shark predators (and prey schools) are the rigged 'Cuda and
Reef Shark species models, copied into `PreyModels` by `organize_imports`. The Tripo
balance is about 1,360 credits (`python tools/tripo.py balance`).

## Import into Studio (owner's PC)

Needs Python 3. Blender is not needed: the FBXs are already rigged.

```
git pull
python tools/fetch_assets.py
```

1. `fetch_assets.py` downloads the bundles into `assets/fbx/` and `assets/glb/` (gitignored).
2. **File → Import 3D**, select **all** files in `assets/fbx/species/`, keep the rig
   (skinning) on and textures on, then **Import All**. Do the same for the two
   files in `assets/fbx/bosses/`.
3. Import `assets/fbx/prey/` with the rig on (like the species), then all files in
   `assets/glb/props/` (no rig). The static `assets/glb/prey/` set is no longer needed.
4. **View → Command Bar**, paste the contents of `tools/studio/organize_imports.luau`,
   press Enter. It moves every import into the folder the code reads and sets each
   model's PrimaryPart. It also copies the 'Cuda and Reef Shark into `PreyModels` for
   the Barracuda and ReefShark prey schools.
5. **Save the place** (Ctrl+S). These folders live in the place file, not in Rojo.

Don't scale or position anything; the code does it:

| Model | What the code does |
|---|---|
| Species | `FishBuilder.buildMesh` welds the skinned MeshPart to the fish's root, nose on -Z, and scales it with `ScaleTo` to the fish's length (growth re-scales it). `FishAnimator` waves the `Spine1..N` and `Tail` bones and nods `Head`. A shade tints the texture (`Cosmetics`); rolled parts and variants show on part bodies only for now. |
| Prey | One MeshPart each, scaled to the fish's length, moved with `BulkMoveTo`, with a small yaw wiggle. |
| Keepers | `WorldService.keeper` fits `WorldProps.Keeper<VendorId>` over the placeholder ball behind each counter (the ball and eyes hide), turned to face the beacon like the stall (a GLB prop's front is +Z). |
| Props | `Props.dress` fits a copy over its placeholder part (kelp, boulders, coral, the beacon, stalls, lanterns) and hides the part. Shrimp, starfish and shells go through `PropParts` and keep the client's bulk movement. |

## Checks

- **Facing in code:** a rigged Model (bones) faces -Z and is never turned. A bare
  MeshPart from a static GLB faces +Z, so `organize_imports` stamps it `Facing = "+Z"`
  and the drawers turn it round (`SwimWave.needsFlip`). The Barracuda and Reef Shark
  predators swam backwards (owner, 2026-10-08) because `PredatorController` pulled
  the MeshPart out of their rigged Model and turned it; predators now draw rigged
  `PreyModels` like the bosses do.
- **Facing:** a rigged fish must swim nose first. `tools/blender/rig_fish.py` finds the
  head as the deep, wide end (a tail fin is thin) and puts it at -Y for FBX (Blender's
  exporter maps -Y onto the -Z we ask for) or +Y for `--static` GLBs (glTF maps +Y onto
  -Z). If one swims backwards in Studio, re-run it with `--flip` and re-import.
  `tools/blender/fish_check.py <fbx> <png>` renders the rest pose and a bent copy
  side-on from +X: the head should be on the LEFT.
- **Bend axis:** `FishAnimator` yaws the bones about their Y. If a fish bends up and
  down instead of side to side after import, the importer re-oriented the bones; swap
  the axis in `setTransform`'s callers (one place) rather than re-rigging.
- **Prey import unit:** Studio may import a 1-unit GLB at 1 stud; the code rescales
  by the MeshPart's Size, so the import unit doesn't matter.
- **Textures:** Tripo PBR textures import as a SurfaceAppearance. A metalness map can
  darken a model under a dim sky (a Hatch & Snatch lesson); if a prop comes in too
  dark, delete its SurfaceAppearance's metalness (set `MetalnessMap` to "") in Studio.

## Regenerating

- `python tools/tripo.py run tools/tripo_jobs_<set>.json [--only A,B] [--redo A,B]`.
  Jobs that already succeeded are skipped unless listed in `--redo`.
- Species: a clean single-fish model sheet first (`tripo_jobs_species_sheets.json`,
  Nano Banana Pro from `assets/concepts/StyleSheet.jpg` as the style reference, body
  STRAIGHT for long fish), then `image_to_model` (`tripo_jobs_species_models.json`).
- Props and prey: `text_to_model` with the style phrase in `tripo_jobs_props1.json`.
  Name colors loudly (the first fan coral came out black); say "spiral conch" rather
  than "shell" (the first was a blob).
- Rig: `python3.11 tools/blender/rig_fish.py in.glb out.fbx [--segments 7]` (the eel
  uses 7), or `--static` for a squared-up GLB. Needs `pip install bpy numpy`.
- Host: zip each group, upload with the Higgsfield `media_upload` tool (general file,
  `If-None-Match: *` on the PUT, then `media_confirm` type `file`), paste the
  CloudFront URL into the manifest.
