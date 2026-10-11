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
| `vendors_glb` | KeeperOutfitter, KeeperMason, KeeperCharms, KeeperDyer, KeeperTrophies (GLB; the five shopkeepers, from `assets/concepts/Vendors.jpg`; v2 colors made safe by `tools/props/safe_colors.py` and screened 2026-10-11) | `ReplicatedStorage.WorldProps.Keeper<VendorId>` |
| `shade_skins` | `<Fish>_Shades.glb` ×6: each fish's skins (23 quads each: its own 12-skin line plus the 11 universal skins, with color, finish/metal and glow maps; tools/shades v5, screened 2026-10-11) | `ReplicatedStorage.ShadeSkins.<Fish>.<Shade>` (organize_shades.luau) |
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
   A GLB whose root node is unnamed comes into the Import Queue as **"Scene"**:
   double-click its row and set **Name** to its file name before Start Import, or the
   organize script can't file it. (The file dialog takes several quoted names in its
   File name box: `"Minnow.fbx" "Sardine.fbx" ...`.)
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
| Keepers | `WorldService.keeper` stands `WorldProps.Keeper<VendorId>` on the plaza beside its counter (on the right as you face the stall), full height, facing the plaza and turned 25° toward the counter, and hides the placeholder ball and eyes behind the counter. Like the stall it gets `GLB_FRONT` (see Facing). |
| Props | `Props.dress` fits a copy over its placeholder part (kelp, boulders, coral, the beacon, stalls, lanterns) and hides the part. Shrimp, starfish and shells go through `PropParts` and keep the client's bulk movement. |

## Shade skins (tools/shades)

Every shade is a texture per fish, made offline from the fish's own texture
(owner, 2026-10-08: shades need "much much more variance and depth"). Since
2026-10-10 each fish makes only its own list: `tools/shades/lines.json` (read by
`shade_lines.py` for every tool) gives each fish its 12-skin line and the universal
skins every fish has (catch track, weekly, boss, treasure), 23 a fish; a skin not on
a fish's list is pruned from its folder. To change or add one, edit `lines.json`, its
recipe in `tools/shades/make_shades.py` (`RECIPES`) and its entry in
`Config/Shades.luau` (`LINES` for a line skin), then from the repo root (Python 3.11 with bpy, numpy,
scipy, pillow; torch and transformers for the screen):

```
python3.11 tools/shades/bake_maps.py -- assets/tripo/species/<Fish>.glb assets/shades/maps/<Fish>.npz   # once per fish
python3.11 tools/shades/make_shades.py assets/shades/maps assets/shades/skins [Fish ...] [--only=Shade,Shade]
python3.11 tools/shades/render_shades.py -- assets/tripo/species/<Fish>.glb assets/shades/skins <renders> [Shade ...]
python3.11 tools/shades/contact_sheet.py <renders> sheet.jpg <Fish>
python3.11 tools/shades/pack_shades.py -- assets/tripo/species/<Fish>.glb assets/shades/skins/<Fish> assets/shades/glb/<Fish>_Shades.glb
python3.11 tools/shades/screen_shades.py assets/shades/glb/<Fish>_Shades.glb --base assets/shades/maps
```

`make_shades.py` writes, per fish, `<Shade>.png` (color), `<Shade>_emit.png` (glow,
for glowing shades), `<Shade>_metal.png` and `<Shade>_rough.png` (metal shades),
`finish_<matte|satin|gloss|mirror>.png` (the roughness every other shade shares) and
`skins.json` (which maps each shade has). Texels the bake never reached (atlas gaps)
are filled from their neighbours with a skin-tone guard. Fins are found per fish by
`blades()` (settings in `FISH`). `render_shades.py` shows them all wired up, in line
order (`pair` adds a second view from the left and below);
`pack_shades.py` turns them into glTF materials (green roughness, blue metal, the
glow as the emissive texture, which Studio's importer turns into the
SurfaceAppearance's glow mask). How bright a skin glows in game, and how it pulses,
is `Config/Shades.luau` (`emissive`, `pulse`), not the texture.

Upload only GLBs whose screen exits 0 (one fish at a time; it ran out of memory on
all six at once). The screen sees every image in the GLB: colors, glow maps and the
roughness/metal maps (packed with no red, so they never read as orange). A soft blend of orange or gold into white comes out peach or
beige and is flagged as skin tone: use hard edges and golds with no blue. Near-white
shades on fish with dark parts (the Angler's teeth) can trip the classifier: keep
pale shades mid-toned. Thin near-white or cyan lines on black (lightning, an x-ray
skeleton, a glow map that is mostly black) score high on the NSFW classifier even
with no skin tone in them (0.23-0.49 in v3): tint them blue or violet and give them
a wide soft glow, which brought them under 0.12. Large smooth fields of a warm gold or orange score
high once JPEG-packed even when the PNG passes (the Reef Shark's warmer Golden: 0.11 as PNG, 0.72 in
the GLB, 2026-10-11): give them a fine grain or texture (a brushed grain brought it to 0.01), and
always screen the packed GLB, not only the PNGs. An edge drawn on the body frame (`ez`, `up`, the fins'
outline, the flank height) steps at every one of its 48 slices, a staircase on the
render (playtest 2026-10-10: Tiger, Tetra, Void, Aurora): a new or reworked recipe
starts with `m = smooth(m)` (the fits interpolated between slices; `flatten` for a
line that should run straight down a lumpy body) and draws hard edges with `crisp()`
(an anti-aliased ramp at least a texel and a half wide). Older skins keep the stepped
frame so they don't change. Eyes are picked on the side face renders (`find_eyes.py`,
then checked by hand in `eyes.json`); the teeth, mouth and the Angler's lure are
kept from the fish's own texture.

In Studio: File → Import 3D, one `assets/shades/glb/<Fish>_Shades.glb` at a time
(wait a few minutes between them for moderation), then run
`tools/studio/organize_shades.luau` in the Command Bar and save the place.

## Checks

- **Facing in code:** a rigged Model (bones) faces -Z and is never turned. A bare
  MeshPart from a static GLB faces +Z, so `organize_imports` stamps it `Facing = "+Z"`
  and the drawers turn it round (`SwimWave.needsFlip`). The Barracuda and Reef Shark
  predators swam backwards (owner, 2026-10-08) because `PredatorController` pulled
  the MeshPart out of their rigged Model and turned it; predators now draw rigged
  `PreyModels` like the bosses do.
- **Tripo props face +X in the GLB** (the MarketStall and the five keepers; check a new
  one with a render from +X and +Z). Roblox's importer turns a GLB half round (a prey
  GLB with its nose on -Z comes in facing +Z), so they arrive facing -X, and
  `WorldService` `GLB_FRONT` (a quarter turn) puts their fronts on -Z. Until
  2026-10-11 the stall was turned half round instead and stood side-on to the plaza.
  `Props.place` fits the model's own axes to the box, so a quarter-turned prop's box
  is given as (depth, height, width).
- **Colors before upload:** a prop's texture goes through the same moderation screen as
  the skins (`tools/shades/screen_shades.py` on its extracted images, with the
  classifier). Warm creatures fail its color checks (Tripo paints them in salmon,
  peach and cream); `tools/props/safe_colors.py` moves those texels out (vivid, cool
  white, greige or darker) and the result is screened again before hosting.
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
