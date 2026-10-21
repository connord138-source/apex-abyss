Apex Tide — PC brief (2026-10-21): the five biome landmarks the owner approved (the boards in `assets/concepts/biome_detail/`), with named places and their play. Built on `claude/world`. Import, test, report. Do §1 → §4 in order.

## How to run it

- Work in `C:\Users\neos1\Desktop\apex-abyss` on `claude/core-systems`, in **`ApexAbyss.rbxl`**. Rojo runs on port **34873**.
- If the Output fills with "Authentication required to access Asset", Studio's login has lapsed: close Studio, log out and back in, reopen the place. Never save while those errors show.
- **Fixes:** fix clear bugs in what you test, one commit per fix, push each. Leave design calls and looks for the report.
- **Report:** `docs/playtests/2026-10-21-biomes.md`, a row per item id (PASS / FAIL / NOTE). Screenshots in `docs/playtests/shots/2026-10-21-biomes/`.

## What changed

- **Shipwreck Graveyard** (`src/server/Wrecks.luau`): the Broken Galleon in the middle of the bay (two halves to swim between, the stern's cabin lit, anchors on chains, cannons, barrels, the figurehead, the wheel-and-bell post behind the stern), the Fallen Lighthouse at 196°, a steamer and a trawler, the Bay Cannon at the bay's inner end, and the bay's 14 scattered wrecks as real hulls, sterns, steamers and debris fields.
- **Abyssal Trench** (`TrenchDress.luau`): the Leviathan's Spine (seven rib arches down the canyon from r 1100, a horned skull, bone heaps), the Squid's Lair (a cave in the canyon wall with glowing eggs; the Giant Squid now rises in front of it), crystal clusters, glow tubes, glass sponges and a trail of glowing worm tufts.
- **Kelp Shallows** (`KelpDress.luau`, rebuilt the same day to read like `assets/tripo/biome_concepts/KelpScene.png`: the first cathedral read as one kelp tower from outside): the Kelp Cathedral is a wide open nave (~165 studs across) in a grove of three loose rings of slim giant kelp stepping down outward (220–300, 150–240 and 90–160 tall, two gaps to swim in by, one facing the hub), the tallest ring's crowns fanning in over the nave as a leafy roof with its middle open and five light shafts; young kelp and kelp clumps round its edge; on its floor sea-grass patches, sand ripples, grey rocks with purple urchins and orange starfish, a lobster trap at the way in, a sunken rowboat whose red float hangs on its chain over it, two otters at the surface. Otter Meadow: a dense sea-grass meadow, an urchin barren on a pavement of low grey boulders, starfish, otters floating at the surface, a red buoy. A trail of lobster traps and rowboats toward the Wreck bay, and 40 patches of sea grass with urchin rocks and starfish across the rest of the Kelp Shallows' floor.
- **Coral Reef** (`ReefDress.luau`, rebuilt the same day to read like `assets/tripo/biome_concepts/ReefScene.png`: the owner's "look how much different your hole looks from the mockup"): the Blue Hole (near 37°, about 640 out) is a wide sinkhole (132 across, 248 deep) whose deep blue walls step down in bands with overhangs, alcoves and ledges (a new Terrain material, Glacier, on the toon rock plates), a raised crater lip with a thin pale stone edge, and a tunnel from its floor out through the drop-off's face, the shortcut down. A sandy highway 32 wide winds 190 studs up to it from the hub side between walls of reef. Its rim is packed three rows deep with coral in colour districts (fire red and orange on the left, blue and violet on the right, yellow and green across), the highway's walls rise from the sand with big brain corals along its edge, plate corals grow on the ledges, a clam and garden eels sit by the road, light shafts come down, a glow lights the floor and the tunnel. The Clam Garden (seven giant clams with glowing pearls) is ringed three deep with coral, tufts between the clams; garden eel patches.
- **Open Blue** (`BlueDress.luau`): the Whale's Rest (a great whale's skeleton on the floor far below), Hammerhead Pinnacle (a coral spire at the sector's far edge with hammerheads circling), golden sargassum rafts at the surface with little fish under them, glowing jelly chains drifting mid-water.
- **Named places** (`Config/Places`, `LandmarkService`): 14, two a biome (the Ruins' Great Temple and Sunken Theatre, the Vents' Forge and Brine Pool too). The first visit toasts "Discovered … (n/14)" and pays coral and shells; all 14 pay 5,000 coral, 100 shells and 2 spins more. The LOG has a **Places** tab; the maps mark found places (names on the full map); the minimap's name bar names the place you're in.
- **Play:** BITE the galleon's bell (it rings for everyone near); swim into the Bay Cannon's muzzle (it fires you over the bay); BITE a clam's pearl (120 coral, 6 shells; gone for you for 15 minutes); a Weathered or Captain's map may bury its chest under the galleon's lit cabin windows (30%); eels duck as you swim over; otters, the buoy and the rafts bob; jelly chains drift.
- Every model has a part-built stand-in, so everything works before the import. Each landmark clears the biome's random scatter (rocks, corals, kelp, seeps) off its ground.
- **Terrain changed** (the Blue Hole, the Squid's Lair, the Trench pillars cleared from the spine): the map chart is regenerated and needs a re-upload.

## 1. Sync and import

1. Merge `origin/claude/world` into `claude/core-systems`, `rokit install`, `rojo serve`, connect the plugin.
2. Format with `stylua --line-endings Windows src --glob "!**/Packages/**"`.
3. `python tools/fetch_assets.py` (fetches `biome_wreck_glb`, `biome_trench_glb`, `biome_kelp_glb`, `biome_reef_glb`, `biome_reef2_glb`, `biome_blue_glb` into `assets/glb/props/`). Every image in them was screened with the classifier (highest 0.023); no normal maps.
4. **File → Import 3D**, no rig, **Import All**, these 30 GLBs from `assets/glb/props/` (in small batches, one biome at a time, waiting for each to finish):
   1. Wreck: GalleonBow, GalleonStern, IronSteamer, ToppledLighthouse, WreckCannon, WreckAnchor, WreckFigurehead, WreckWheelBell, WreckBarrels.
   2. Trench: LeviathanRibs, LeviathanSkull, TrenchCrystals, TrenchGlowTubes, GlassSponge, GlowEggs, BoneHeap.
   3. Kelp: LobsterTrap, SunkenRowboat, SeaOtter, UrchinRock, KelpBuoy, SeaGrass (skip KelpCanopy: it isn't used).
   4. Reef: TableCoral, GiantClam, GardenEels, PillarCoral, and from `biome_reef2_glb` 14 more on top of the count above (colourways: every image screened, highest 0.004): DomeCoralRed, DomeCoralOrange, DomeCoralYellow, DomeCoralGreen, BranchFanRed, BranchFanOrange, BranchFanYellow, BranchFanViolet, TableCoralOrange, TableCoralRed, TableCoralBlue, TableCoralViolet, PillarCoralOrange, PillarCoralBlue.
   5. Blue: WhaleSkeleton, Sargassum, JellyChain, CoralPinnacle.
5. Paste `tools/studio/organize_imports.luau` into the Command Bar. Each should be filed as `ReplicatedStorage.WorldProps.<Name>`; note anything it leaves in Workspace.
   Then paste `tools/studio/make_toon_materials.luau` (edit mode): `Config/Materials` has a new toon entry, **Glacier** (the Blue Hole's walls, Rock's plate image in deep blue). WorldService warns at start if it's missing.
6. **Map chart:** screen `assets/textures/map_chart.png` (`python tools/shades/screen_shades.py assets/textures --quiet`, exit 0), upload it, and paste the new id into `src/shared/Config/Textures.luau` `mapChart`. Commit that.
7. **Save the place.** Play once. The Output should have, with no errors:
   - `[Wrecks] the bay: … models and 0 stand-ins …`
   - `[Trench] the Leviathan's Spine: … 0 stand-ins …`
   - `[Kelp] landmarks: …`, `[Reef] landmarks: …`, `[Blue] landmarks: …`, each with `0 stand-ins` and how many scattered pieces were cleared.
   Copy those lines into the report.

## 2. Test

Use the admin panel's biome teleport to get round; screenshot every landmark from a fish's view and from a little way off.

**BW — Shipwreck Graveyard.**
1. The galleon's two halves lie on the sand (not floating, not buried past their hulls); swim through the break between them.
2. The stern's cabin windows glow warm; the anchors' chains reach the sand.
3. The Fallen Lighthouse lies along the sand (not standing, not floating, its lamp end clear of the sand).
4. BITE the bell on the post behind the stern: it rings (a low chime, bubbles). A second player nearby hears it (Test → Clients and Servers, 2 players) if you can.
5. Swim into the Bay Cannon's muzzle (its two lanterns mark it): a boom, and you're fired over the bay toward the galleon for ~1.3 s. No `[SpeedCheck]` lines in the Output after.
6. Admin: give Captain's maps (5–6, using each); about one in three should read "Under the lit windows of the Broken Galleon's stern" and dig there. Note how many tries it took.

**BT — Abyssal Trench.**
1. The rib arches stand across the canyon one after another; swim down the ribcage under them. No invisible walls in the arches' openings, no basalt pillars through them.
2. The skull lies at the head end; the bone heaps trail off the other way.
3. The Squid's Lair: a cave in the canyon wall with glowing eggs and a teal light.
4. Summon the Giant Squid (`_G.ApexBoss.summon()` until it's the squid's turn, or the admin panel): it rises in front of the lair.
5. Crystals, glow tubes and sponges glow on the floor; the worm-tuft trail runs down the middle.

**BK — Kelp Shallows.**
Compare with `assets/tripo/biome_concepts/KelpScene.png`.
1. The Kelp Cathedral (45°, about 345 studs out): from outside, a grove of tall slim kelp of different heights rising toward the nave, not one solid tower. Screenshot it from ~300 studs.
2. Swim in by the gap facing the hub: the trap and two urchin rocks at the way in, then the open nave (~165 across): sea grass in patches, sand ripples, rocks with urchins and starfish, the rowboat with its red float on the chain above it, kelp of different heights all round, the crowns roofing it with the middle open and light coming down. Screenshot the scene's view: low on the floor by the way in, looking across and a little up.
3. The kelp sways like other kelp and gives way when you push through; the young kelp too. Note KelpController's ms/s in the nave (PF).
4. Otter Meadow (300°): a dense sea-grass meadow, an urchin barren on grey boulders beside it; otters on their backs at the surface bob; the buoy bobs; the urchin rocks and boulders are solid.
5. The trap-and-rowboat trail leads off toward the Wreck bay, grass round each.
6. Swim the rest of the Kelp Shallows: sea-grass patches, urchin rocks and starfish on the floor between the forests; nothing floating or buried, nothing inside a boulder or a kelp stalk's base.

**BR — Coral Reef.**
Compare with `assets/tripo/biome_concepts/ReefScene.png`.
1. The Blue Hole (near 37°, about 640 out): follow the sandy highway from the hub side up to the rim. Screenshot the scene's view: over the highway ~90 studs back from the rim, ~45 up, looking down into the hole (its far wall filling the opening, the coral ring round it, the highway's walls either side).
2. The rim: coral three rows deep in colour districts (fire on the left, blue and violet on the right, yellow and green across); the highway's walls with big brain corals along the sand; a clam and garden eels by the road. Nothing floating or buried.
3. The walls are deep blue from the rim down (if they're plain grey-blue stone, the Glacier toon material wasn't made: §1 step 5), with ledges carrying corals. Swim to the floor and back up: no snags; a glow on the floor.
4. The tunnel: from the hole's floor it runs out through the drop-off's face to the deep water. Swim it both ways: open all the way, lit along its floor.
5. No reef head or random coral stands inside the hole, on its rim or on the highway.
6. The Clam Garden (near 320°, about 660 out): three rings of coral and tufts between the clams. BITE a pearl. A toast, +120 coral and +6 shells, and that pearl disappears for you. BITE the same spot again: nothing. Admin **Places: unfind every named place, regrow the pearls** brings it back.
7. Garden eel patches by the hole and the clams duck into the sand as you swim low over them and rise again after.

**BB — Open Blue.**
1. The Whale's Rest (268°, about 1,120 out, on the deep floor): the skeleton lies on the floor, a light shaft above it.
2. Hammerhead Pinnacle (296°, about 1,455 out, past the Megalodon's patrol band): the spire stands on the floor, solid; four hammerheads circle it at different heights. Note whether they read as hammerheads.
3. Sargassum rafts at the surface bob; little fish circle under each when you're near.
4. Jelly chains drift slowly mid-water.

**PL — Named places.**
1. Swim to each of the 14 places (the 10 above plus the Great Temple, Sunken Theatre, the Forge and the Brine Pool). Each pays once with "Discovered … (n/14)". Note any that didn't trigger.
2. LOG → **Places**: found ones show their name and story with FOUND ✓, the rest ??? with their biome and reward; the count is right.
3. The full map (M) marks every found place with its name; the minimap marks them too. The name bar under the minimap reads the place's name while you're in it.
4. Finding the 14th pays the bonus (5,000 coral, 100 shells, 2 spins).
5. Rejoin: found places stay found, a pearl taken stays gone until it grows back.

**PF — Frame time.** Stand in each landmark (the cathedral's nave, the galleon's break, the hole's rim, the ribcage, the pinnacle) and read FPS and the Script Profiler's `LandmarkController` and `KelpController`. Note anything over ~5 ms/s.

## 3. Report

Finish the report with your fixes and recommendations (looks the owner should see: the cathedral from inside and out, the galleon, the hole, the ribcage, the pinnacle's sharks). Commit it with the screenshots and push `claude/core-systems`.

## 4. Publish

Only if Connor asks in this round; otherwise leave publishing to him.
