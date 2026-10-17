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
| `whalefall_glb` | WhaleFall (GLB; the Whale Fall's carcass, 2026-10-15; lengthwise along its Z, head at +Z in the GLB; normal map stripped, colours made safe, screened) | `ReplicatedStorage.WorldProps.WhaleFall` |
| `vendors_glb` | KeeperOutfitter, KeeperMason, KeeperCharms, KeeperDyer, KeeperTrophies (GLB; the five shopkeepers, from `assets/concepts/Vendors.jpg`; v2 colors made safe by `tools/props/safe_colors.py` and screened 2026-10-11) | `ReplicatedStorage.WorldProps.Keeper<VendorId>` |
| `furniture_glb` | the 38 den furniture pieces of batch 1, `furniture/<Name>.glb` (GLB; cut off `assets/concepts/Furn*.jpg` by `tools/props/furniture_crops.py`, Tripo image_to_model; normal maps taken out by `tools/props/strip_normals.py`, colors made safe by `safe_colors.py`, all 76 images screened 2026-10-13; front faces +X) | `ReplicatedStorage.WorldProps.<Name>` |
| `shade_patch_v9` | `<Fish>_ShadesPatch.glb` ×6: CatchCrystal on every fish, Magma on the MorayEel (2026-10-16 retextures; only these quads) | the same folders; `organize_shades.luau` replaces only these skins |
| `shade_patch_v10` | `<Fish>_ShadesPatch.glb` ×6 in `assets/shades/patch10`: CatchGolden, WeekWave, WeekWreck and PassAbyssalCurrent on every fish, Thunder and CudaChrome on the Cuda, MorRibbon on the MorayEel, ShkScarred on the ReefShark (2026-10-16, the PC's SK2 notes; 9-13 images a GLB) | the same folders; import after v9 |
| `shade_patch_v11` | `<Fish>_ShadesPatch.glb` ×6 in `assets/shades/patch11`: WeekWave and WeekWreck on every fish, lighter for the water, each with a faint even glow map (2026-10-17, K1 of the round-2 report; 6 images a GLB) | the same folders; import after v10 |
| `shade_skins` | `<Fish>_Shades.glb` ×6: each fish's skins (27 quads each: its own 12-skin line plus the 15 universal skins, and a Natural quad on the four toothed fish; color, finish/metal and glow maps, never a normal map; tools/shades v8.2, bone-white teeth) | `ReplicatedStorage.ShadeSkins.<Fish>.<Shade>` (organize_shades.luau) |
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
`skins.json` (which maps each shade has), and no normal map (`NORMALS = False` since
v10: none ships, and the screen flags each one). Texels the bake never reached (atlas gaps)
are filled from their neighbours with a skin-tone guard. Fins are found per fish by
`blades()` (settings in `FISH`). `render_shades.py` shows them all wired up, in line
order (`pair` adds a second view from the left and below; no normal map, as they
ship; `water=0.35` grades the render the way the shallows do, OceanController's tint
then the teal haze, which is where a gold turns olive; `strength=0.65` shows a glow
map at the game's EmissiveStrength 1 instead of the default 3);
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
then checked by hand in `eyes.json`); the mouth and the Angler's lure are kept from
the fish's own texture.

**Teeth are always bone white** (owner, 2026-10-14: "All fish should always have bone
white teeth"; the Angler's and 'Cuda's had taken the skin's colour). `tools/shades/teeth.json`
marks each toothed fish's mouth on the bake's head views (boxes in the 512 px `faces`)
with a colour `rule` for its painted teeth (`pale_warm` the Angler's beige fangs, `warm`
the 'Cuda's peach teeth, `pale` the Moray's); `_teeth` takes the matching texels seen in
a box and grows them to each tooth's whole piece of the atlas. The Reef Shark's teeth
are a pixel or two in those views, so its rule is `slot`: `bake_mouth.py` renders
close-ups of the mouth at teeth.json's `mouth` (centre in the bake's body frame and
radius) to `assets/shades/maps/<Fish>.mouth.npz`, once per fish:

```
python3.11 tools/shades/bake_mouth.py -- assets/tripo/species/ReefShark.glb assets/shades/maps/ReefShark.mouth.npz -0.035,-0.42,-0.10 0.08
```

and the teeth are the light bits inside the mouth's dark slot (lavender texels many
views land on). Every skin then paints the teeth `BONE` (0.92, 0.92, 0.91; neutral on
purpose: a warmer bone white reads as pale cream to `screen_shades.py` and got two Reef
Shark skins flagged), shaded a
little by their own paint, satin, with no glow or metal on them. Nothing glows within
`MOUTH_DARK` of them either (0.006-0.016 body lengths in 3D, `Fish.mouth_zone`: the gums
and the inside of the mouth between the teeth, which the teeth mask leaves to the skin;
v10, after Thunder's arcs glowed along the 'Cuda's gums and read as lightning over its
teeth), and Thunder's arcs stop short of the mouth. Each toothed fish also
gets a **Natural** skin (its own texture, white teeth, the Angler's lure glowing), which
`Cosmetics` wears when the fish has no shade (or a shade not imported yet, tinted).
A moving sheen (a Texture, which can't be masked) skips the face a toothed fish's head
points out of, so the teeth stay white from the front. The screen's base for each fish
is its own texture: the baked `<Fish>.npz` in the cloud, or the colour image inside
`assets/fbx/species/<Fish>.fbx` on the PC (`fbx_base`, the same pixels), found without
`--base`. The Nibbler and Puffer have no teeth. After adding a fish with teeth, mark it in
teeth.json and check the mask (`eyes_debug.png` in its skins folder shows the teeth in orange) and a
close render (`tools/marketing/render_fish.py`).

In Studio: File → Import 3D, one `assets/shades/glb/<Fish>_Shades.glb` at a time
(wait a few minutes between them for moderation), then run
`tools/studio/organize_shades.luau` in the Command Bar and save the place.

**Patch packs (2026-10-16):** a retexture of a few skins ships as
`<Fish>_ShadesPatch.glb` holding only those quads, so only their images are uploaded:
`pack_shades.py ... assets/shades/patch/<Fish>_ShadesPatch.glb --only=Shade,Shade`
(it refuses `--only` under a `_Shades` name, since a partial full pack would empty
the fish's folder, and a `_ShadesPatch` name without `--only`). `organize_shades.luau`
files a patch's skins without clearing the rest. Import patches after the full packs,
never in the same organize run. The v9 patch (`shade_patch_v9`) is CatchCrystal on
every fish and Magma on the MorayEel. The v10 patch (`shade_patch_v10`, packed to
`assets/shades/patch10` so v9's files stay as they were) answers the PC's SK2 notes
(docs/playtests/2026-10-16-pc.md): Golden is an orange-leaning gold with a faint even
glow map (made for the default EmissiveStrength 1) so the water's blue-green no longer
turns it olive; WeekWave, WeekWreck, Abyssal Current, Ribbon, Chrome and Scarred are
lifted to read from the side; Thunder's arcs stop short of the 'Cuda's mouth. Before/after
sheets, studio light and in water: `assets/shades/previews/v10_<Fish>_compare.jpg`
(and `v10_Cuda_Thunder_mouth.jpg`). Import it after v9. The v11 patch
(`shade_patch_v11`, in `assets/shades/patch11`) answers K1 of the round-2 report
(docs/playtests/2026-10-16-pc-2.md: WeekWave and WeekWreck still read dark in the
water): WeekWave is a light-to-mid cerulean sky over a mid turquoise sea with brighter
crests, WeekWreck a lighter, purer teal hull over a lighter cobalt bottom, and both get
a faint even glow map (half the colour, less on the lines), as Golden did. Measured as
the mean luminance of the fish in the `water=0.35 strength=0.65` render, they went from
0.28-0.32 (Wave) and 0.25-0.27 (Wreck) to 0.42-0.45 and 0.39-0.41, beside v10's Golden
at 0.41-0.44. The classifier is touchy about light teal: a hull of (0.23, 0.71, 0.61)
scored 0.19 on the Nibbler once JPEG-packed, (0.12, 0.71, 0.62) 0.04, so score the
packed image of a light field (the screen does) before settling on it. Sheets:
`assets/shades/previews/v11_<Fish>_compare.jpg`. Import it after v10.

**Sheens** (`tools/shades/make_sheens.py [name ...]`, python3.11 + scipy): tiling
512² layers in `assets/textures/`, uploaded as Images and keyed in
`Config/Textures`. Their colour fills the whole image and alpha says where they
show, so the classifier sees a coloured field; screen them with
`screen_shades.py assets/textures/sheen_<name>.png` (exit 0, classifier on). The v9
five (lava, caustic, facets, current, bolt) scored 0.000–0.002.

## Toon materials (tools/textures, 2026-10-16)

Every stock material the world uses is swapped game-wide for a flat, cel-shaded
tile (owner: walls "too much like garrymod textures"):

```
python3.11 tools/textures/make_toon_materials.py [Name ...]       # assets/textures/toon_<Name>.png
python3.11 tools/textures/preview_toon_materials.py <dir> [Name ...]  # lit renders + a contact sheet
python3.11 tools/shades/screen_shades.py assets/textures/toon_*.png   # classifier on; must exit 0
```

The maps are grey (R = G = B, mean ~0.8) so the world's colours tint them;
CrackedLava keeps its own cracks. Keep the sparse `flecks()` layer in any grey stone
map: without it, large smooth grey areas with soft curved lines scored up to 0.42
on the classifier. Upload the PNGs as Images (Asset Manager → Import), paste each id
into `src/shared/Config/Materials.luau`, then run `tools/studio/make_toon_materials.luau`
in Studio's Command Bar (edit mode) and save the place: it makes the `Toon<Name>`
MaterialVariants (colour map only, never a normal map) and the base-material
overrides. WorldService lifts the Terrain's colours to match while they're on.

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
