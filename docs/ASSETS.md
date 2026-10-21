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
| `species_fbx` | Nibbler, Cuda, Puffer, MorayEel, ReefShark, Angler (rigged FBX; the Cuda and ReefShark have a Jaw bone since 2026-10-19, see "Jaws and fins" below) | `ReplicatedStorage.FishModels.<SpeciesId>` |
| `prey_fbx` | Minnow, Sardine, Wrasse, Snapper, Grouper (rigged FBX, 4 spine segments: their bones swim) | `ReplicatedStorage.PreyModels.<PreyId>` |
| `prey2_fbx` | Garibaldi, WreckCod, Parrotfish, YellowfinTuna, MahiMahi, Lionfish, GhostShrimp, Lanternfish (2026-10-18, the second prey batch from the approved PreySheetA concept; rigged FBX like `prey_fbx`, 4 spine segments; normal maps stripped, colours made safe, the 8 embedded colour maps screened, highest 0.025; see "The second prey batch" below) | `ReplicatedStorage.PreyModels.<PreyId>` |
| `prey3_fbx` | Butterflyfish, Triggerfish, Swordfish, OceanSunfish, Coelacanth, VentEelpout, GulperEel, Oarfish (2026-10-19, the third prey batch from the approved PreySheetB concept; rigged FBX like `prey_fbx`: 4 spine segments, the Sunfish 2, the Eelpout 5, the Gulper Eel 6, the Oarfish 7; normal maps stripped, colours made safe, the 8 embedded colour maps screened, highest 0.094; see "The third prey batch" below) | `ReplicatedStorage.PreyModels.<PreyId>` |
| `prey4_fbx` | Opaleye, KelpBass, BlueTang, Lingcod, Rattail, Viperfish, Hatchetfish, HumpheadWrasse (2026-10-19, the fourth prey batch from the approved PreySheetC concept; rigged FBX like `prey_fbx`: 4 spine segments, the Lingcod 5, the Rattail and Viperfish 6, the Hatchetfish 2; normal maps stripped, colours made safe, the 8 embedded colour maps screened, highest 0.002; see "The fourth prey batch" below) | `ReplicatedStorage.PreyModels.<PreyId>` |
| `predators_fbx` | SeaLion, GoliathGrouper, GiantTrevally, MakoShark, SixgillShark, WolfEel, GoblinShark, BlackDragonfish (2026-10-21, the eight new AI predators from the approved PredatorsBoard; rigged FBX with a Jaw bone on each, 4–7 spine segments; normal maps stripped, colours made safe, the 8 embedded colour maps screened, highest 0.026; see "The new predators" below) | `ReplicatedStorage.PreyModels.<Id>` |
| `ambient_fbx` | `ambient/<Name>.fbx`: Turtle, Manta, Stingray, Humpback, Crab (2026-10-19, the sea life; rigged by `tools/blender/rig_ambient.py`: flippers, wings, disc edges, flukes, legs and claws; normal maps stripped, colours made safe, the 5 embedded colour maps screened, highest 0.006; see "Sea life" below) | `ReplicatedStorage.AmbientModels.<Name>` |
| `prey_glb` | the older static GLB prey (still drawn if that's what is imported; turned round in code) | `ReplicatedStorage.PreyModels.<PreyId>` |
| `props_glb` | GiantKelp, KelpClump, BoulderRound, BoulderJagged, BrainCoral, FanCoral, StaghornCoral, TubeSponge, Anemone, Shrimp, Starfish, Shell, Lantern, CrystalCluster, MarketStall (GLB) | `ReplicatedStorage.WorldProps.<Name>` |
| `props2_glb` | TreasureChest (GLB; the treasure map dig site's chest) | `ReplicatedStorage.WorldProps.TreasureChest` |
| `whalefall_glb` | WhaleFall (GLB; the Whale Fall's carcass, 2026-10-15; lengthwise along its Z, head at +Z in the GLB; normal map stripped, colours made safe, screened) | `ReplicatedStorage.WorldProps.WhaleFall` |
| `vendors_glb` | KeeperOutfitter, KeeperMason, KeeperCharms, KeeperDyer, KeeperTrophies (GLB; the five shopkeepers, from `assets/concepts/Vendors.jpg`; v2 colors made safe by `tools/props/safe_colors.py` and screened 2026-10-11) | `ReplicatedStorage.WorldProps.Keeper<VendorId>` |
| `furniture_glb` | the 38 den furniture pieces of batch 1, `furniture/<Name>.glb` (GLB; cut off `assets/concepts/Furn*.jpg` by `tools/props/furniture_crops.py`, Tripo image_to_model; normal maps taken out by `tools/props/strip_normals.py`, colors made safe by `safe_colors.py`, all 76 images screened 2026-10-13; front faces +X) | `ReplicatedStorage.WorldProps.<Name>` |
| `den_props2_glb` | the 12 den props of batch 2, `den_props2/<Name>.glb`: DriftwoodTable, KelpBed, PearlPedestal, BubbleColumn, SpongeSofa, ShipwreckBookshelf, JellyLamp, SeaGlassLantern, CoralLamp, Banner, ConchGramophone, TreasureChart (GLB; 2026-10-19, from `assets/concepts/DenPropsA.jpg` / `DenPropsB.jpg`; normal maps stripped, squared up and recoloured by `tools/props/den_props2_prep.py`, colours made safe, all 24 images screened, highest 0.115; see "The den props, batch 2" below) | `ReplicatedStorage.WorldProps.<Name>` |
| `ruins_glb` | RuinHead, RuinHand, RuinGuardian, RuinUrn, RuinCapital, RuinStele, `props/<Name>.glb` (GLB; the Sunken Ruins' hero props, 2026-10-18, Tripo text_to_model from `tools/tripo_jobs_ruins_props.json` in the BiomeSunkenRuins concept's marble; normal maps stripped, colours made safe, all 12 images screened, highest 0.056; the head and the stele face +X, the guardian +Z) | `ReplicatedStorage.WorldProps.<Name>` |
| `shade_patch_v9` | `<Fish>_ShadesPatch.glb` ×6: CatchCrystal on every fish, Magma on the MorayEel (2026-10-16 retextures; only these quads) | the same folders; `organize_shades.luau` replaces only these skins |
| `shade_patch_v10` | `<Fish>_ShadesPatch.glb` ×6 in `assets/shades/patch10`: CatchGolden, WeekWave, WeekWreck and PassAbyssalCurrent on every fish, Thunder and CudaChrome on the Cuda, MorRibbon on the MorayEel, ShkScarred on the ReefShark (2026-10-16, the PC's SK2 notes; 9-13 images a GLB) | the same folders; import after v9 |
| `shade_patch_v11` | `<Fish>_ShadesPatch.glb` ×6 in `assets/shades/patch11`: WeekWave and WeekWreck on every fish, lighter for the water, each with a faint even glow map (2026-10-17, K1 of the round-2 report; 6 images a GLB) | the same folders; import after v10 |
| `shade_patch_v12` | `<Fish>_ShadesPatch.glb` ×6 in `assets/shades/patch12`: every skin on the Nibbler, Puffer, MorayEel and Angler (the whole eye kept, skins v12), Bumblebee and Lilac redesigned on the Nibbler, and WeekWreck ("Barnacled"), WeekWave, PassUndertow and PassRiptide redesigned on every fish (2026-10-17; 228 images: Nibbler 48, Puffer 46, MorayEel 49, Angler 63, Cuda 11, ReefShark 11) | the same folders; import after v11 |
| `shade_patch_v13` | `<Fish>_ShadesPatch.glb` ×6 in `assets/shades/patch13`: CatchGolden on every fish (polished: reflection bands, a semi-gloss) and X-Ray on the Cuda (an anatomical skeleton) (2026-10-18; 21 images: 3 a GLB, 6 on the Cuda) | the same folders; import after v12 |
| `shade_patch_v14` | `<Fish>_ShadesPatch.glb` ×6 in `assets/shades/patch14`: CatchSilver, the new Silver catch skin, on every fish (polished silver: reflection bands over mirror scales, steel-blue creases, a semi-gloss) (2026-10-18; 18 images: 3 a GLB) | the same folders; import after v13 |
| `shade_skins` | `<Fish>_Shades.glb` ×6: each fish's skins (27 quads each: its own 12-skin line plus the 15 universal skins, and a Natural quad on the four toothed fish; color, finish/metal and glow maps, never a normal map; tools/shades v8.2, bone-white teeth) | `ReplicatedStorage.ShadeSkins.<Fish>.<Shade>` (organize_shades.luau) |
| `boss_fbx` | Megalodon (7 spine segments, a Jaw and FinL/FinR since 2026-10-19), GiantSquid (6; the arms trail) (rigged FBX; the world bosses) | `ReplicatedStorage.FishModels.<Id>` |

Not yet made: species growth stages (Fry/Juvenile/Apex), the other biomes' props.
The Barracuda and Reef Shark predators (and prey schools) are the rigged 'Cuda and
Reef Shark species models, copied into `PreyModels` by `organize_imports`. The Tripo
balance is about 425 credits (2026-10-19, after the fourth prey batch;
`python tools/tripo.py balance`).

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

### The Sunken Ruins' hero props (`ruins_glb`, 2026-10-18)

`src/server/Ruins.luau` builds the whole drowned city from parts and fits these six
models over their part-built stand-ins once they're in `WorldProps` (`Props.dress`,
solid, the camera kept out): the colossal head toppled by the temple's stair, a giant
hand rising from the sand (and a smaller one by a colossus's feet), the sea-dragon
guardians on the avenue, urns, the capitals at the ends of fallen columns, and the
glyph steles. Until they're imported the stand-ins show; nothing else changes.

1. `python tools/fetch_assets.py` (fetches `ruins_glb` into `assets/glb/props/`).
2. **File → Import 3D**, select the six `Ruin*.glb` in `assets/glb/props/` (no rig),
   **Import All**. A row named "Scene" gets its file name first.
3. Paste `tools/studio/organize_imports.luau` into the Command Bar (it knows the six
   names), then **save the place**.
4. Play: the server prints `[Ruins] ... N hero props (0 part-built stand-ins)`. In the
   Sunken Ruins (east, LV 50+; Admin "teleport to a biome"), check that the head lies
   on its side with its face toward the avenue, the guardians face across the avenue,
   the steles face their braziers, and nothing floats or sinks out of sight. If a
   model faces the wrong way, the turn is `GLB_FRONT` in `Ruins.luau` (the head and
   the stele take it; the guardian faces its frame's look without it).

The Terrain under the ruins changed (a sand plain, drifts and the sunken courtyard's
pit; the old column stubs, plinths, walls and temple ring are parts now), so the map
chart is regenerated (`assets/textures/map_chart.png`, screened): upload it as an
Image and paste its id into `Config/Textures` `mapChart`.

### The second prey batch (`prey2_fbx`, 2026-10-18)

Eight prey from the approved concept sheet `assets/tripo/prey_concepts/PreySheetA.png`,
one for each biome (`Config/Prey`, ids as below; the Ghost Shrimp has a few swarms in
the kelp too): Garibaldi (Kelp), WreckCod (Shipwreck Graveyard), Parrotfish (Coral
Reef), YellowfinTuna and MahiMahi (Open Blue), Lionfish (Sunken Ruins, venomous: it
stings when swallowed), GhostShrimp (Hydrothermal Vents) and Lanternfish (Abyssal
Trench).

How they were made (repeatable, outputs in the gitignored `assets/tripo/`):

1. `python3 tools/props/prey_refs.py`: each fish's crop of the concept sheet, large,
   over a strip of `StyleRef.png`, as one reference image (`assets/tripo/prey2_refs/`).
2. `python tools/tripo.py run tools/tripo_jobs_prey2_sheets.json`: a clean side-on
   model sheet each (Nano Banana, 5 credits). Two copied the style strip under the
   fish; `prey_refs.py --tops WreckCod YellowfinTuna` cut them above it instead of
   redrawing.
3. `python tools/tripo.py run tools/tripo_jobs_prey2_models.json`: image_to_model
   (30 credits each).
4. `tools/props/strip_normals.py` (every GLB had one), `tools/props/safe_colors.py`
   (skin-tone texels: Lionfish 66%, WreckCod 43%, MahiMahi 35%, YellowfinTuna 12%,
   Garibaldi 6%, all to 0%; the Ghost Shrimp stays cool blue-grey), then
   `python3.11 tools/blender/rig_fish.py <safe>.glb assets/fbx/prey/<Id>.fbx --segments 4`
   and `tools/blender/fish_check.py` (every head on the left).
5. Each FBX embeds only its colour map (no ORM, no normal map;
   `fbx_strip_normals.py` drops nothing). The eight embedded images were extracted
   and screened with `screen_shades.py` and the classifier: exit 0, none flagged,
   highest 0.025 (Lanternfish).

Import on the PC:

1. `python tools/fetch_assets.py` (fetches `prey2_fbx` into `assets/fbx/prey/`, beside
   the first five).
2. **File → Import 3D**, the eight new files in `assets/fbx/prey/`
   (`"Garibaldi.fbx" "WreckCod.fbx" "Parrotfish.fbx" "YellowfinTuna.fbx" "MahiMahi.fbx"
   "Lionfish.fbx" "GhostShrimp.fbx" "Lanternfish.fbx"`), rig on and textures on like
   the first prey, **Import All**.
3. Paste `tools/studio/organize_imports.luau` into the Command Bar (it knows the eight
   names and keeps each rigged Model in `ReplicatedStorage.PreyModels.<Id>`), then
   **save the place**.

What the code does with them: `SchoolController` draws them like every rigged prey
(scaled to each fish's length, the spine wave on their bones). Until a model is
imported the fish is the part-built ellipsoid in its `back` colour with a few extra
parts in its own colours (`SHAPES`: a belly, fins, the Lionfish's dark bands, spine
crest and fanned fins, the Parrotfish's pale beak). Whether imported or not, the
Lanternfish wears eight small Neon light spots along its lower flanks (within 60
studs of the camera) and the Ghost Shrimp glowing teal tips on its tail fan, legs
and antennae (within 45), never a see-through body (`GLOWS`); the three nearest
Lanternfish carry a faint cyan PointLight (range 7). The spots sit on the body's
outline from its bounding box, so if they float off or sink into an imported
Lanternfish, nudge `at` in `GLOWS` (x across, y up, z along the body, in half-extents).

### The third prey batch (`prey3_fbx`, 2026-10-19)

Eight prey from the approved concept sheet `assets/concepts/PreySheetB.jpg` (the
working copy is `assets/tripo/prey_concepts/PreySheetB_grid.png`), natives for the
reef, the wrecks and the deep biomes (`Config/Prey`, ids as below): Butterflyfish
(Coral Reef), Triggerfish (Shipwreck Graveyard), Swordfish and OceanSunfish (Open
Blue), Coelacanth (Sunken Ruins), VentEelpout (Hydrothermal Vents), GulperEel and
Oarfish (Abyssal Trench).

How they were made (repeatable, outputs in the gitignored `assets/tripo/`):

1. `python3 tools/props/prey_refs.py --batch B`: each fish's crop of the sheet, mirrored
   to face left (the sheet's fish face right), large, over the style strip
   (`assets/tripo/prey3_refs/`). The Oarfish's and the Gulper Eel's tails curl on the
   concept, and Nano Banana copied the curl twice however the prompt asked for a
   straight body, so their references are straightened (`BATCHES["B"]["straighten"]`:
   the curl cut off and the body's last stretch run on straight, tapering).
2. `python tools/tripo.py run tools/tripo_jobs_prey3_sheets.json`: a clean side-on
   model sheet each (Nano Banana, 5 credits; 60 with the two redos). Six copied the
   style strip under the fish; `prey_refs.py --batch B --tops <Names>` cut them above it.
3. `python tools/tripo.py run tools/tripo_jobs_prey3_models.json`: image_to_model
   (30 credits each, 240; 300 in all).
4. `tools/props/strip_normals.py` (one each), then `tools/props/safe_colors.py`
   (skin-tone texels: Butterflyfish 31.1%, VentEelpout 3.9%, Triggerfish 2.8%, Oarfish
   1.3%, all to 0%). Two new options: `--vivid` for the Butterflyfish (its pale lemon
   turned grey-white under the bright rule; yellows get more chroma instead) and
   `--crimson` for the Oarfish (its orange-red fins over the pale blue-silver body
   scored **0.99** on the classifier with no skin tone in them; a truer red, a little
   darker, scored 0.03). Watch for this on any new pale fish with orange-red parts.
5. `python3.11 tools/blender/rig_fish.py <safe>.glb assets/fbx/prey/<Id>.fbx --segments N`
   with N = 4 (Butterflyfish, Triggerfish, Swordfish, Coelacanth), 2 (OceanSunfish, a
   stiff disc), 5 (VentEelpout), 6 (GulperEel) and 7 with `--head 0.14` for the Oarfish
   (`--head` is new: the share of the length the stiff Head bone takes, 0.28 by default;
   the Oarfish's head is small, so more of its ribbon waves). `SchoolController` waves
   however many `SpineN` bones a rig has. `tools/blender/fish_check.py`: every head on
   the left, once the Swordfish and the OceanSunfish were rigged again with `--flip`
   (the deep-end guess took the thin sword and the Sunfish's round head for tails; their
   tail fin and scalloped back edge are the deeper ends).
6. Each FBX embeds only its colour map (no ORM, no normal map; `fbx_strip_normals.py`
   drops nothing). The eight embedded images were extracted and screened with
   `screen_shades.py` and the classifier: exit 0, none flagged, highest 0.094
   (Triggerfish; Oarfish 0.036).

Import on the PC:

1. `python tools/fetch_assets.py` (fetches `prey3_fbx` into `assets/fbx/prey/`, beside
   the others).
2. **File → Import 3D**, the eight new files in `assets/fbx/prey/`
   (`"Butterflyfish.fbx" "Triggerfish.fbx" "Swordfish.fbx" "OceanSunfish.fbx"
   "Coelacanth.fbx" "VentEelpout.fbx" "GulperEel.fbx" "Oarfish.fbx"`), rig on and
   textures on like the first prey, **Import All**.
3. Paste `tools/studio/organize_imports.luau` into the Command Bar (it knows the eight
   names), then **save the place**.

Until a model is imported, the fish is the part-built ellipsoid with `SHAPES` extras:
the Butterflyfish's eye band, eyespots and snout, the Triggerfish's white belly, yellow
back and orange beak, the Swordfish's sword and tall dorsal, the Sunfish's tall fins
and scalloped back edge, the Coelacanth's blotches and lobed fins, the Eelpout's big
head and ember specks, the Gulper's pouch mouth and whip tail, the Oarfish's red back
fin, crest and streamers. None of them has `GLOWS` (the Eelpout's specks are painted
on its texture).

### The fourth prey batch (`prey4_fbx`, 2026-10-19)

Eight prey from the approved concept sheet `assets/concepts/PreySheetC.jpg` (the
working copy is `assets/tripo/prey_concepts/PreySheetC_grid.png`; its hatchetfish was
redrawn on its own, `PreySheetC_Hatchetfish.png`): real natives for the kelp, the reef,
the wrecks and the Ruins, and more for the deep (`Config/Prey`, ids as below): Opaleye
and KelpBass (Kelp Shallows), BlueTang (Coral Reef), Lingcod (Shipwreck Graveyard),
HumpheadWrasse (Sunken Ruins), Rattail (Hydrothermal Vents), Viperfish and Hatchetfish
(Abyssal Trench).

How they were made (repeatable, outputs in the gitignored `assets/tripo/`):

1. `python3 tools/props/prey_refs.py --batch C`: each fish's crop of the sheet, mirrored
   to face left, over the style strip (`assets/tripo/prey4_refs/`); the Hatchetfish's
   from its own redraw (`sources`).
2. `python tools/tripo.py run tools/tripo_jobs_prey4_sheets.json`: a clean side-on
   model sheet each with a closed mouth (Nano Banana, 5 credits; 40 in all, no redos).
   Three copied the style strip under the fish: `prey_refs.py --batch C --tops BlueTang
   Lingcod Rattail`. Then `prey_refs.py --batch C --fix Opaleye KelpBass Lingcod
   Viperfish Hatchetfish` touched five up (`FIXES`, -> `<Name>_fix.png`): the Opaleye's
   back spots cut to two (the concept notes: one or two, not a speckle) and a stray
   mark painted out; the Kelp Bass's, Lingcod's, Viperfish's and Hatchetfish's maroon
   or pink-beige mouth lining to a navy-grey; the Hatchetfish's glowing dots moved from
   the middle of its belly onto the keel's edge and its pupils turned to look up (Nano
   Banana copied the reference's dots and gaze whatever the prompt said).
3. `python tools/tripo.py run tools/tripo_jobs_prey4_models.json`: image_to_model
   (30 credits each, 240; 280 in all).
4. `tools/props/strip_normals.py` (one each), then `tools/props/safe_colors.py`
   (skin-tone texels: Rattail 4.4%, its dull orange fin edges to a vivid ember orange;
   pale: Kelp Bass 0.7%, Lingcod and Viperfish 0.1%; all to 0%), with `--vivid` for the
   Blue Tang (its yellow tail stays lemon) and the new `--plum` for the Hatchetfish:
   Tripo painted the inside of its mouth plum-maroon, (110, 43, 73), 17,000 texels,
   though its sheet's mouth was closed; `--plum` turns plum, maroon and crimson-pink to
   a navy-grey of the same brightness. Check every new prey's colour map for a plum
   mouth (red well over green, blue over green) before rigging.
5. `python3.11 tools/blender/rig_fish.py <safe>.glb assets/fbx/prey/<Id>.fbx --segments N`
   with N = 4 (Opaleye, KelpBass, BlueTang, HumpheadWrasse), 5 (Lingcod), 6 (Rattail,
   Viperfish: long and tapering) and 2 (Hatchetfish, a stiff disc like the Sunfish).
   `tools/blender/fish_check.py`: every head on the left, no `--flip` needed.
6. Each FBX embeds only its colour map (no ORM, no normal map; `fbx_strip_normals.py`
   drops nothing). The eight embedded images were extracted and screened with
   `screen_shades.py` and the classifier: exit 0, none flagged, highest 0.002
   (Viperfish; the Hatchetfish 0.001 after `--plum`).

Import on the PC:

1. `python tools/fetch_assets.py` (fetches `prey4_fbx` into `assets/fbx/prey/`, beside
   the others).
2. **File → Import 3D**, the eight new files in `assets/fbx/prey/`
   (`"Opaleye.fbx" "KelpBass.fbx" "BlueTang.fbx" "Lingcod.fbx" "Rattail.fbx"
   "Viperfish.fbx" "Hatchetfish.fbx" "HumpheadWrasse.fbx"`), rig on and textures on like
   the first prey, **Import All**.
3. Paste `tools/studio/organize_imports.luau` into the Command Bar (it knows the eight
   names), then **save the place**.

Until a model is imported, the fish is the part-built ellipsoid with `SHAPES` extras:
the Opaleye's two back spots and soft dorsal, the Kelp Bass's blotches, spiny dorsal and
jaw, the Blue Tang's black palette marking and yellow tail, the Lingcod's dark blotches,
long back fin and big jaw, the Rattail's big head, rat tail and ember fin edges, the
Viperfish's fangs, the Hatchetfish's silver belly and tail stalk, the Humphead's forehead
hump and lips. The Viperfish and the Hatchetfish wear `GLOWS` whether imported or not:
Neon spots on the imported model's own painted rows (the Viperfish's two rows along its
lower flank, the front two thirds of them, within 60 studs; the Hatchetfish's row along
its keel's edge, chin to point, within 45), measured on the models (each colour map's
cyan dots found on the mesh through its UVs, checked on a render with the spots on);
the three nearest Viperfish carry the faint cyan light like the Lanternfish. On the
part-built stand-in those spots sit inside the body, and `SHAPES` paints cyan dots on
its outline instead. If a spot floats off or sinks into an imported fish, nudge `at`
in `viperSpots` / `hatchetSpots` (x across, y up, z along, in half-extents of the box).

### The new predators (`predators_fbx`, 2026-10-21)

Eight AI predators from the approved board `assets/concepts/PredatorsBoard.jpg` (concept
sheets `assets/tripo/predator_concepts/PredatorSheet{A,B}.png`, from
`tools/tripo_jobs_predator_concepts.json`), one or two for every biome: SeaLion (Kelp
Shallows), GoliathGrouper (Shipwreck Graveyard), GiantTrevally (Coral Reef), MakoShark
(Open Blue), SixgillShark (Sunken Ruins), WolfEel (Hydrothermal Vents), GoblinShark and
BlackDragonfish (Abyssal Trench).

How they were made (repeatable, outputs in the gitignored `assets/tripo/`):

1. `python3.11 tools/props/predator_refs.py`: each creature's crop of its concept sheet,
   mirrored to face left, over the prey style strip (`assets/tripo/predator_refs/`).
2. `python tools/tripo.py run tools/tripo_jobs_predator_sheets.json`: a clean side-on model
   sheet each, mouth a little open (Nano Banana, 5 credits). Nano Banana copied the sea
   lion's sitting pose, so it was redrawn swimming (`SeaLionSwim`, Nano Banana Pro, 10).
   Every open mouth came out mauve inside, (70, 48, 53) to (117, 81, 89), whatever the
   prompt said, and the goblin shark's thrust-out jaws pale mauve-grey:
   `predator_refs.py --fix GoliathGrouper GiantTrevally MakoShark SixgillShark GoblinShark
   SeaLionSwim` turns them navy-grey at the same brightness (`FIXES`; the sea lion's only in
   its mouth and ear, since its fur's mauve shadows would turn blue). The dragonfish's lure
   hangs from a chin barbel, so it doesn't read as the playable Anglerfish.
3. `python tools/tripo.py run tools/tripo_jobs_predator_models.json`: image_to_model
   (30 credits each, 240; 290 in all).
4. `tools/props/strip_normals.py` (one each), then `tools/props/safe_colors.py --plum`
   (`--olive` too for the grouper: skin-tone texels GoliathGrouper 5.8%, SeaLion 3.4%; pale
   WolfEel 3.3%, MakoShark 2.4%, GoblinShark 2.1%; all to 0%, and no plum left).
5. `python3.11 tools/blender/rig_fish.py <safe>.glb assets/fbx/predators/<Id>.fbx --segments N --jaw`
   with N = 5 (SeaLion `--head 0.3`, MakoShark, SixgillShark, GoblinShark `--head 0.34`: the
   long snout), 4 (GoliathGrouper, GiantTrevally), 7 (WolfEel `--head 0.2`), 6
   (BlackDragonfish `--head 0.22`). `fish_check.py`: every head on the left, no `--flip`;
   `jaw_check.py`: every jaw opens cleanly (the sea lion's whiskers and the dragonfish's
   barbel go with the jaw, as they grow from it).
6. Each FBX embeds only its colour map (`fbx_strip_normals.py --noop` drops nothing); the 8
   embedded images were extracted and screened with `screen_shades.py` and the classifier:
   exit 0, none flagged, highest 0.026 (SeaLion).

Their shapes, for the code (once imported each faces -Z, Y up; width : height : length, and
the jaw's hinge from the nose as a share of the length):

| Id | W : H : L | Jaw hinge | Notes |
|---|---|---|---|
| SeaLion | 0.95 : 0.26 : 1 | 0.11 | the front flippers spread wide; the body itself ~0.25 wide |
| GoliathGrouper | 0.45 : 0.54 : 1 | 0.22 | deep, a cavernous mouth |
| GiantTrevally | 0.54 : 0.59 : 1 | 0.14 | a deep slab |
| MakoShark | 0.59 : 0.45 : 1 | 0.22 | wide pectorals |
| SixgillShark | 0.48 : 0.35 : 1 | 0.22 | |
| WolfEel | 0.32 : 0.32 : 1 | 0.20 | 7 spine segments |
| GoblinShark | 0.41 : 0.33 : 1 | 0.33 | the snout runs a third of the length ahead of the mouth |
| BlackDragonfish | 0.26 : 0.64 : 1 | 0.17 | the chin barbel hangs ~0.4 below the body (~0.22 tall); its bulb is cyan |

Import on the PC:

1. `python tools/fetch_assets.py` (fetches `predators_fbx` into `assets/fbx/predators/`).
2. **File → Import 3D**, the eight files in `assets/fbx/predators/`, rig on and textures on
   like the prey, **Import All**.
3. Paste `tools/studio/organize_imports.luau` into the Command Bar (it knows the eight
   names: they go to `ReplicatedStorage.PreyModels.<Id>` with their bones), then **save
   the place**.

### Sea life (`ambient_fbx`, 2026-10-19)

The owner: "the sea turtles and manta rays/stingrays need to be dialed up they're
essentially just circles put together", then "Crabs were another animal that needs more
detail like the turtles. Crabs should be edible too". Five Tripo models (sheets
`tools/tripo_jobs_ambient_sheets.json` from `tools/props/ambient_refs.py`, then
image_to_model, `tools/tripo_jobs_ambient_models.json`; outputs in the gitignored
`assets/tripo/ambient/`): an olive-green sea turtle, a dark manta with cephalic fins, a
teal-green blue-spotted stingray, a pale blue-grey humpback and a scarlet crab.

1. `tools/props/strip_normals.py assets/tripo/ambient/*.glb --out assets/glb/ambient_nonormals`
   (one each), then `tools/props/safe_colors.py ... --out assets/glb/ambient_safe`
   (skin tone: the Crab's orange-red edges 2.0%; pale: the Stingray's eye whites 0.1%;
   both to 0%). The humpback's pale grey and the manta's pale marks are cool and
   mid-toned and stay. No mouth is plum (the crab's red-over-green-and-blue texels are
   its deep crimson shell creases, a true red).
2. `python3.11 tools/blender/rig_ambient.py assets/glb/ambient_safe/<Name>.glb assets/fbx/ambient/<Name>.fbx [--weights <png>]`:
   a skeleton per kind, named for `src/shared/AmbientRigs.luau` (the turtle's rigid
   Shell, Neck, Head, three-bone front flippers, two-bone hind flippers, Tail; the
   manta's three-bone wings, cephalic fins and tail; the stingray's two bones at three
   stations along each disc edge and a three-bone tail; the humpback's spine to its
   flukes and two-bone pectorals; the crab's arms and claws, three legs a side (the
   model has three walking legs a side) and eye stalks). Head at -Y in Blender, so -Z
   in Roblox like every rigged fish.
3. `bash tools/preview/run_ambient.sh <dir>` (with `LUAU=`): every creature posed
   through its motion in Blender, the model beside its part-built stand-in, plus
   `CrabKinds.png` (each edible crab kind tinted or painted, carrying its extras).
4. Each FBX embeds only its colour map (`fbx_strip_normals.py` drops nothing); the five
   images were screened with `screen_shades.py` and the classifier: exit 0, none
   flagged, highest 0.006 (Turtle; Crab 0.002, Stingray 0.001, Manta and Humpback 0.000).

Import on the PC: `python tools/fetch_assets.py` (fetches `ambient_fbx` into
`assets/fbx/ambient/`), **File → Import 3D** the five files with the rig and textures on,
**Import All**, paste `tools/studio/organize_imports.luau` into the Command Bar (it files
them into `ReplicatedStorage.AmbientModels` and gives a model textured by a TextureID a
SurfaceAppearance instead, so the game can tint the crab per kind), then **save the
place**. Until then every creature is its part-built stand-in (`AmbientRigs` plans,
built by `src/client/AmbientBody.luau`).

### Jaws and fins (`boss_fbx`, `species_fbx`, 2026-10-19)

The owner: the Megalodon's "mouth doesn't move and his actual movements are very
stiff ... Same with other predator fish". `tools/blender/rig_fish.py` gained `--jaw` (a
Jaw bone, a child of Head, hinged at the corner of the mouth; the mouth is found by
rays up through the head, the lower jaw weighted by a harmonic field along the welded
surface, so the corners and throat hand over smoothly and every tooth goes with its
gum) and `--fins` (FinL/FinR on the pectorals, the same way). Re-rigged from the
original Tripo GLBs (`assets/tripo/bosses`, `assets/tripo/species`):

    python3.11 tools/blender/rig_fish.py assets/tripo/bosses/Megalodon.glb <out>/Megalodon.fbx --segments 7 --jaw --fins
    python3.11 tools/blender/rig_fish.py assets/tripo/species/ReefShark.glb <out>/ReefShark.fbx --jaw
    python3.11 tools/blender/rig_fish.py assets/tripo/species/Cuda.glb <out>/Cuda.fbx --jaw
    python3.11 -I tools/props/fbx_strip_normals.py --out <clean> <out>/*.fbx

The rig is deterministic: the mesh, UVs and colour map come out byte-identical to the
screened 2026-10-14 files (only the bones and weights change), so no image is new.
`--fins` is only on the Megalodon: the Reef Shark's long swept pectorals kinked and
pulled its gill slits out under a tilt. Check a rig with
`tools/blender/jaw_check.py <fbx> <png> [--view side|three|front]` (the jaw shut, at
rest and open; the fins tilted) and `tools/blender/pose_check.py <fbx> <png> [--top]`
(the poses PredatorController drives: cruise, burst-turn, tell, snap, charge, breach).

Import on the PC: `python tools/fetch_assets.py`, then File → Import 3D the three
files (`assets/fbx/bosses/Megalodon.fbx`, `assets/fbx/species/ReefShark.fbx`,
`assets/fbx/species/Cuda.fbx`) with the rig and textures on, Import All, run
`tools/studio/organize_imports.luau` (it prints which came in with a Jaw and fins, and
copies the new 'Cuda and Reef Shark into `PreyModels.Barracuda` / `.ReefShark`), save
the place. Without the new files everything still works: no Jaw bone, no jaw motion.
`FishAnimator` drives a `Jaw` bone by name, so the players' 'Cuda and Reef Shark snap
their jaws on a bite too.

### The den props, batch 2 (`den_props2_glb`, 2026-10-19)

The owner asked for the buyable den props to be "MUCH much better" and approved two
boards, `assets/concepts/DenPropsA.jpg` (Driftwood Table, Kelp Bed, Pearl Pedestal,
Bubble Column, Sponge Sofa, Shipwreck Bookshelf) and `DenPropsB.jpg` (Jellyfish Lamp,
Sea Glass Lantern, Coral Lamp, Banner, Conch Gramophone, Treasure Chart). The eight
first pieces keep their ids in `Config/Dens` (placed copies in saves stay) and the four
new ones (SpongeSofa, ShipwreckBookshelf, ConchGramophone, TreasureChart) are bought in
the den shop from the start. Each item's `prop` is its own id.

How they were made (repeatable, outputs in the gitignored `assets/tripo/` and
`assets/glb/`):

1. `python3.11 tools/props/den_props2_refs.py`: each piece cut off its board on the
   board's own teal, large (`assets/tripo/den_props2_refs/`).
2. `python tools/tripo.py run tools/tripo_jobs_den_props2_sheets.json`: a clean
   three-quarter model sheet each (Nano Banana, 5 credits), then
   `python tools/tripo.py run tools/tripo_jobs_den_props2_models.json` (image_to_model,
   30 credits). 420 credits in all, no redos.
3. `tools/props/strip_normals.py assets/tripo/den_props2/*.glb --out assets/glb/den_props2_nonormals`.
4. `python3.11 tools/props/den_props2_prep.py prep assets/glb/den_props2_nonormals/*.glb --out assets/glb/den_props2_prep`:
   names each scene, node and mesh after the piece; squares three up in plan, baked
   into the vertices (TreasureChart +31 degrees: Tripo kept the concept's turn, and a
   wall thing must lie flat on the rock; PearlPedestal -9, KelpBed -5); recolours four
   (the jellyfish bells' pale tan to amber gold, the coral lamp's salmon fans to deep
   orange, the bed's tan rope to olive kelp rope, the table's warm patches to
   driftwood grey: `safe_colors.py` alone made the rope copper and the table's top
   blotchy orange); and sprinkles flecks over the pedestal's grey stone, whose colour
   map scored 0.62 on the classifier without them (the toon materials' lesson).
5. `tools/props/safe_colors.py assets/glb/den_props2_prep/*.glb --out assets/glb/den_props2_safe`
   (skin-tone texels to 0.0% on every map; the gramophone horn's cream to cool white).
6. `python3.11 tools/props/den_props2_prep.py cloth assets/glb/den_props2_safe/Banner.glb --out assets/glb/den_props2_cloth`:
   the banner's colour map becomes a 1024 RGBA PNG whose teal cloth is alpha 0.2 (its
   colours untouched). The 12 GLBs (Banner from step 6) are the bundle.
7. Screened: every image extracted (Color and ORM, 24) and run through
   `screen_shades.py` with the classifier: exit 0, none flagged, highest 0.115
   (PearlPedestal ORM; colour maps at most 0.021).

Facing in the GLB: +Z for most (`front` unset), -Z for DriftwoodTable (`front = 180`),
+X for ShipwreckBookshelf, SeaGlassLantern, Banner and TreasureChart (`front = 90`). The
boxes in `Config/Dens` are each model's own proportions at its size, so a wall thing
sits on the rock with no gap. Until a model is imported, `Shared/DenItems` builds a
part-built stand-in of the same design (`STAND_INS`), so the den shop's photos, Build
mode's ghost and the placed thing look like the concept either way.

The banner's cloth follows the den's glow: `DenItems` colours its MeshPart in the glow
and leaves the texture untinted, and the SurfaceAppearance in **Overlay** mode shows
that colour where the colour map's alpha is low. Only a plugin or the Command Bar can
set `AlphaMode`, so `organize_imports.luau` sets it on `WorldProps.Banner` (it prints
`Banner: AlphaMode Overlay set`). If the cloth shows see-through, the importer left it
in Transparency mode; run the script again.

Import on the PC:

1. `python tools/fetch_assets.py` (fetches `den_props2_glb` into `assets/glb/den_props2/`).
2. **File → Import 3D**, the 12 files in `assets/glb/den_props2/` (no rig), **Import
   All**. A row named "Scene" gets its file name first.
3. Paste `tools/studio/organize_imports.luau` into the Command Bar (it knows the 12
   names, files them in `ReplicatedStorage.WorldProps` and sets the banner's Overlay
   mode), then **save the place**.
4. Check the facing in a den (Build mode, or the den shop's photos): every piece's front
   toward you in its photo; the lantern, banner and chart flat on the rock, standing
   out from it; the bookshelf's back against the wall when snapped. A piece facing the
   wrong way is its `front` in `Config/Dens` (90 for a GLB facing +X, 180 for -Z).

### Rolled parts and variants (`parts_glb`, `variants_fbx`, 2026-10-21)

The approved boards (`assets/concepts/PartsBoard.jpg`, sheet B; `VariantsBoard.jpg`)
as real models: five parts (AnglerLure, NarwhalHorn, SawSnout, SailFin, VeilTail) and
every fish's variant (Puffball, Sabrecuda, Porcupine, DragonMoray, Hammerhead,
Deepfang).

How they were made (repeatable, outputs in the gitignored `assets/tripo/`):

1. `python3 tools/props/parts_variants_refs.py`: each part's crop of PartsSheetB, large
   (`assets/tripo/parts_refs/`), and each variant's crop over its species' own model
   sheet (`variant_refs/`).
2. `python tools/tripo.py run tools/tripo_jobs_parts_sheets.json` and
   `..._variant_sheets.json` (Nano Banana, 5 credits each): the part alone, no fish (the
   lure, sail and tail took a redo: a lamp base, a plank and a whole betta), each
   variant side-on and straight (the Dragon Moray redone for its horns and crest).
   `parts_variants_refs.py --fix` touches up two: the Sabrecuda's sheet drew the fish
   twice (top copy cut out), the Veil Tail's stem came out terracotta (recoloured).
3. `..._parts_models.json`, `..._variant_models.json`: image_to_model (30 each).
4. `tools/props/strip_normals.py` (one each), `safe_colors.py` (Deepfang and DragonMoray
   with `--plum`, the Porcupine with the new `--olive`: its tan body went vivid orange
   and read as the Puffball).
5. Parts: `python3.11 tools/props/parts_prep.py <safe> <out>` squares each up (front,
   toward the fish's nose, on Blender +Y = glTF -Z; up +Z; centred on its box), adds an
   emissive map from its cyan texels and writes `parts.json` (each one's box and
   attach point, in units of its longest side, the game's frame), which
   `Cosmetics` `PART_MODELS` copies. Variants: `rig_fish.py` like the species
   (`--jaw` Hammerhead, `--jaw --flip` Sabrecuda, `--segments 7` DragonMoray), checked
   with `fish_check.py` and `jaw_check.py`.
6. Screened: 14 part images (Color, ORM, Emissive) and 6 variant colour maps, as
   packed, with the classifier: none flagged, highest 0.035.

Import on the PC:

1. `python tools/fetch_assets.py` (`parts_glb` into `assets/glb/parts/`, `variants_fbx`
   into `assets/fbx/variants/`).
2. **File → Import 3D**: the five GLBs (no rig), then the six FBX with the rig and
   textures on, **Import All**.
3. Paste `tools/studio/organize_imports.luau` into the Command Bar: parts go to
   `ReplicatedStorage.PartModels.<PartId>` (the MeshPart, `Facing` "+Z"), variants to
   `ReplicatedStorage.VariantModels.<VariantId>`; it prints each. **Save the place.**

What the code does with them: `Cosmetics` hangs a part's model on its anchor (Head,
Body1, Stalk) by its attach point, riding the bone like the part-built pieces, and
turns a "+Z" model round; until it's imported the part-built piece is drawn. A
variant with a model replaces the body's mesh on every client (the species' mesh comes
back when it's taken off); a shade tints the variant's own texture (the shade skins are
made per species texture). Facing check: a horn or saw pointing back, or a sail whose
tall end trails, is a model whose `Facing` should be "-Z" (set it on the MeshPart in
`PartModels`).

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

**Skins v12** (`shade_patch_v12`, in `assets/shades/patch12`; owner, 2026-10-17: "Every
single skin on nibbler glitches into the eye", and "too many of them are obviously just
mesh slapped onto the fish"):

- **The whole eye, on every skin.** Up to v11 an eye was the pale or dark texels inside a
  sphere round each pick, and only the pieces holding a pupil were kept (v8, against the
  Nibbler's cream crescent). An eye's sclera spans several UV islands, so the islands
  with no pupil on them were painted with the skin: a stair-stepped chunk bitten out of
  the Nibbler's sclera on every skin, part of the Puffer's iris, the Moray's grey ring
  and the Angler's teal socket. Now eyes.json holds each fish's eye palette (`eye`: the
  eye's painted colours; `skin`: the skin round it, the Nibbler's cream band among them);
  `Fish._eyes` keeps every texel nearer an eye colour than a skin colour, in whole pieces
  lying mostly inside the eye's sphere, fills small holes, unmixes the edge from the
  texture's own anti-aliasing (no fringe of the old skin colour; `Fish.kept` is the eye's
  own colour there) and keeps it unblurred; the atlas gaps round an eye are padded from
  the nearest eye texel, so no seam line crosses it at a distance. Check with
  `python3.11 tools/shades/render_eyes.py -- assets/tripo/species/<Fish>.glb assets/shades/skins <dir> [Shade ...]`
  (each eye side-on and the face from the front three-quarter). The Cuda's and Reef
  Shark's eyes were whole already (only a faint grey crescent moved), so they were not
  re-shipped for it.
- **Redesigns** drawn on the body's form (smooth frame, countershading, fins as fins:
  `fin_reach` measures out from the body's core, so a fin margin is a clean line where
  blades()'s reach left blotches): Bumblebee (Nibbler, a bumblebee goby), Lilac (Nibbler,
  a lavender morph with iridescent scales), WeekWreck as "Barnacled" (a weathered
  slate-green wreck-dweller with barnacle clusters, coralline crusts and kelp), WeekWave
  (breaking-wave crest bands with pale-blue foam), PassUndertow (bold teal whirlpools,
  drawn round a point on the skin with `surface_polar` so they stay round on a round
  fish) and PassRiptide (one glowing rip current with streamlines). lines.json has each
  one's look. Barnacles keep clear of the eyes and their openings are diamond slits:
  round dark holes beside the Moray's small eye read as more eyes. Barnacled is kept
  light for the water like v11 (mean luminance in the `water=0.35` preview about 0.39).
- **NibMaroon is a brighter garnet** (0.36, 0, 0.10) over (0.60, 0.02, 0.14): with the
  whole eye kept, the sclera's own UV islands sit pale on the wine in the atlas, and the
  old wine scored 0.31 on the classifier once JPEG-packed (0.13 now).

What the patch holds and its screen are in tools/assets_manifest.json `shade_patch_v12`.
Sheets: `assets/shades/previews/v12_<Fish>_compare.jpg` (before | after, in the water) and
`v12_<Fish>_eyes.jpg` (eye close-ups before | after). Import it after v11.

**Skins v13** (`shade_patch_v13`, in `assets/shades/patch13`; owner, 2026-10-18: "The
gold skin needs more of a gold sheen" and "X ray needs to be an actual skeleton too
this looks rough"):

- **Golden** (every fish) reads as polished metal: reflection bands from which way the
  skin faces (a bright streak along the upper flank, an amber horizon band under it, a
  warm bounce lower down), brushed along the body, on a semi-gloss (its own roughness
  map, 0.48, 0.38 in the streak) so the game's lights lay real highlights on it, and its
  glow map stronger in the streak. Every tone stays as orange as v10's gold (green at
  most 0.64 of red, no blue): through the shallows' haze a yellower highlight went lime
  and a darker shadow olive, and a full gloss mirrored the teal water at the edges. The
  moving part is the game's: Config/Shades `FX` gives it SkinFx `sheen` (a band of warm
  light, a light riding it and gold sparks running head to tail every 2.5 s, fine
  glitter). Measured in the `water=0.35 strength=0.65` preview: the median hue as warm
  as v10's or warmer on every fish, the brightest 5% lifted (0.53-0.57 -> 0.58-0.62),
  the mean unchanged. The bands leave bigger even fields than v10's, so the brushed
  grain is stronger, with a finer third octave: at v10's strength the Reef Shark's
  packed image scored 0.23 on the classifier (one tile, round its eye), now 0.03.
- **X-Ray** (the Cuda's Epic) is an anatomical skeleton (`xray` and its helpers
  `outline`, `curve`, `bones_along`, `fin_rays`): laid out on the body's own side
  silhouette (the midpoint of its top and bottom, fins left out, so the column runs
  straight where the old frame wandered with the fins), placed from the fish's own
  landmarks (the eye, the teeth, the painted gill line, each fin's root): braincase,
  eye ring, skull floor, jaws to the jaw joint, preopercle, gill cover edge,
  branchiostegal rays, shoulder girdle with rods to the paired fins, about 30
  spool-shaped vertebrae with dark joints, neural spines, ribs round the belly cavity
  (a faint swim bladder), haemal spines, supports under the dorsal and anal fins, and
  rays in every fin fanning in the fin's own plane. Ice-cyan bones with a wide soft
  blue glow on a mid-toned deep blue that is lighter where the body is thickest;
  `render_shades.py ... side` shoots both flanks square on to check it.

Sheets: `assets/shades/previews/v13_<Fish>_golden.jpg` (v12 | v13, in studio light
and in the water) and `v13_Cuda_xray.jpg`. What the patch holds and its screen are in
tools/assets_manifest.json `shade_patch_v13`. Import it after v12.

On the PC:

```
git pull
python tools/fetch_assets.py                                    # shade_patch_v13 -> assets/shades/patch13
python tools/shades/screen_shades.py assets/shades/patch13/Nibbler_ShadesPatch.glb
python tools/shades/screen_shades.py assets/shades/patch13/Cuda_ShadesPatch.glb
...                                                             # one fish at a time; each must exit 0
```

Then in Studio (`ApexAbyss.rbxl`): File → Import 3D, one
`assets/shades/patch13/<Fish>_ShadesPatch.glb` at a time (a few minutes apart, for
moderation), run `tools/studio/organize_shades.luau` in the Command Bar once they're
all in, and save the place. Check: the Golden skin on any fish shows the shine running
down it every 2.5 s; the Cuda in X-Ray shows its skeleton side-on.

**Skins v14** (`shade_patch_v14`, in `assets/shades/patch14`; 2026-10-18): **Silver**
(`CatchSilver`, Common), the skin of the new Silver catch rarity (Config/Catch), the
commonest. It is Golden's polish in silver (`catch_silver`, made the way v13's Golden is)
and works on every fish:

- **Polished silver from back to belly**, read by its reflections: a bright streak along
  the upper flank, a deep steel-blue horizon band under it, a cool bounce lower down.
  That keeps it apart from the plain silvery prey (a dark back over a light belly) and
  from the Cuda's Chrome (dark gunmetal with blue-violet streaks).
- **Mirror scales** (`mirror_scales`): big overlapping scales laid round the body in its
  own girth, rows nose to tail. Each scale's front lies under the scale ahead, so each
  shows its free back edge. Each scale is a flat mirror tilted its own way, so the
  reflection bands step from scale to scale, a few scales flash bright, and each scale
  lightens toward its edge. There are no scales on the face or the fins.
- **Steel-blue in the creases**: behind each scale's free edge, in the fish's own painted
  creases, and in its pattern, engraved as Golden's is.
- **Finish**: a brushed grain nose to tail, its own semi-gloss roughness (0.42, 0.32 in
  the streak), an even metal of 0.25, and a faint glow map that is stronger in the streak
  and on the flashing scales.

It stays mid-toned and cool for the screen. Blue is above green and green above red
everywhere, with Cr − Cb about −18 on average, so it has no cream or beige. The mean
luminance is 0.54–0.63, about Golden's, and the brightest flash is a blue-white well
under white. Through the `water=0.35` haze it reads light steel-blue with its bands; in
studio light (`strength=0.65`) it reads polished silver. Every packed image scored
0.005 or less on the classifier.

The moving part is the game's: Config/Shades `FX` gives it SkinFx `sheen`, Golden's
shine in a cool silver-white. The shine's colours come from the shade (`color`,
`color2`, and `light` for the flare in a viewport, PreviewFx). Sheet:
`assets/shades/previews/v14_CatchSilver.jpg`, with each fish's own look in the water,
then Silver in studio light, then Silver in the water. What the patch holds and its
screen are in tools/assets_manifest.json `shade_patch_v14`. Import it after v13.

On the PC: `python tools/fetch_assets.py` (shade_patch_v14 → assets/shades/patch14).
Screen each `assets/shades/patch14/<Fish>_ShadesPatch.glb` one at a time; each run
must exit 0. Then File → Import 3D one GLB at a time, a few minutes apart, run
`organize_shades.luau`, and save the place. Check: the Silver skin on any fish shows a
cool silver shine running down it every 2.5 s.

**Skins v14.1** (`shade_patch_v14_1`, in `assets/shades/patch14_1`; 2026-10-19): the
Anglerfish's Silver only. On the PC (playtest SV1) it read "very bright, almost glowing
pale blue-white": the Angler is a dark fish whose lure lamp is always lit
(LampController `lure`), and v14's faint body glow was most of its atlas. `catch_silver`
now takes its tones from `SILVER`, with a fish's own in `SILVER_FISH`. The Angler's
silver is a step darker (mean luminance 0.54, was 0.60), its horizon band, scale
creases, painted creases and engraving are deeper, and its body has no glow. Its glow
map holds only the lure, as in every Angler skin. In the `water=0.35` preview it now
reads as mid-toned polished silver, a little under the other five, which are unchanged.
In studio light the bands still step and the streak still shines. Sheet:
`assets/shades/previews/v14_1_Angler_silver.jpg` (v14.1 against v14, in the water and
in studio light, then the other five fish's Silver in the water). The screen is in the
manifest. Import it after v14.

On the PC: `python tools/fetch_assets.py` (shade_patch_v14_1 →
assets/shades/patch14_1), then
`python tools/shades/screen_shades.py assets/shades/patch14_1/Angler_ShadesPatch.glb`
(must exit 0). Then File → Import 3D that one GLB, run `organize_shades.luau`, and save
the place.

**Skins v15** (`shade_patch_v15`, in `assets/shades/patch15`; 2026-10-20): the
Nibbler's Diamond only (the one fish whose line holds it). On the PC (playtest DM) it
read nearly white in the den and dark navy in the Reef: v8's finish was a mirror
(roughness 0.14, metal 0.35), so it showed its surroundings, not its colour, and the
game's ice-blue window layer couldn't change that. `diamond` is now a gloss (0.3) with
no metal, a deeper ice blue (facets from pale ice to a cold sapphire, the bevels'
highlights blue-white well under white, the dispersion fire kept) and a faint, even
ice-blue glow map (a blue field over the whole body, never thin lines on black), with
no `emissive` in Config/Shades, so EmissiveStrength stays 1 and it isn't a lamp. Sheet:
`assets/shades/previews/v15_Nibbler_diamond.jpg` (v8 above, v15 below; studio light,
then the water at 0.35 and 0.6). Blender's even lighting can't show the mirror
problem, so judge it in game, in the den and in the Reef. The screen is in the manifest.
Import it after v14.1.

On the PC: `python tools/fetch_assets.py` (shade_patch_v15 → assets/shades/patch15),
then `python tools/shades/screen_shades.py assets/shades/patch15/Nibbler_ShadesPatch.glb`
(must exit 0). Then File → Import 3D that one GLB, run `organize_shades.luau`, and save
the place.

**FX particle textures** (`tools/shades/make_fx.py`, python3.11 + scipy):
`assets/textures/fx_{swirl,mist,bubble,star,flame,spark}.png`, 512² RGBA, for the skins'
in-game particles (the swirls over Undertow, mist, bubbles, glints, flames, sparks). Like
the sheens, one tint fills every pixel (a light cyan; the flame a saturated warm yellow
with toon-hard edges) and alpha alone draws the shape; the spark is a streak along the
image's vertical (for VelocityParallel). Screen them with `screen_shades.py
assets/textures/fx_*.png` (classifier on, exit 0) before uploading them as Images, and a
copy composited over black and over white too: on white a paler cyan-white star scored
0.23 and a soft yellow flame edge read as cream (v12: all six at most 0.13 composited,
0.003 as files).

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
