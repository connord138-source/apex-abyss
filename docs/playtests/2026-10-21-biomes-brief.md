Apex Tide — PC brief (2026-10-21): the five biome landmarks the owner approved (the boards in `assets/concepts/biome_detail/`), with named places and their play. Built on `claude/world`. Import, test, report. Do §1 → §4 in order.

## How to run it

- Work in `C:\Users\neos1\Desktop\apex-abyss` on `claude/core-systems`, in **`ApexAbyss.rbxl`**. Rojo runs on port **34873**.
- If the Output fills with "Authentication required to access Asset", Studio's login has lapsed: close Studio, log out and back in, reopen the place. Never save while those errors show.
- **Fixes:** fix clear bugs in what you test, one commit per fix, push each. Leave design calls and looks for the report.
- **Report:** `docs/playtests/2026-10-21-biomes.md`, a row per item id (PASS / FAIL / NOTE). Screenshots in `docs/playtests/shots/2026-10-21-biomes/`.

## What changed

- **Shipwreck Graveyard** (`src/server/Wrecks.luau`): the Broken Galleon in the middle of the bay (two halves to swim between, the stern's cabin lit, anchors on chains, cannons, barrels, the figurehead, the wheel-and-bell post behind the stern), the Fallen Lighthouse at 196°, a steamer and a trawler, the Bay Cannon at the bay's inner end, and the bay's 14 scattered wrecks as real hulls, sterns, steamers and debris fields.
- **Abyssal Trench** (`TrenchDress.luau`): the Leviathan's Spine (seven rib arches down the canyon from r 1100, a horned skull, bone heaps), the Squid's Lair (a cave in the canyon wall with glowing eggs; the Giant Squid now rises in front of it), crystal clusters, glow tubes, glass sponges and a trail of glowing worm tufts.
- **Kelp Shallows** (`KelpDress.luau`): the Kelp Cathedral (24 giant kelp twice the forests' height round an open nave, their fronds a roof with the middle open, light shafts down it), Otter Meadow (sea grass, an urchin barren, otters floating at the surface, a red buoy), and a trail of lobster traps and rowboats toward the Wreck bay.
- **Coral Reef** (`ReefDress.luau`): the Blue Hole (a sinkhole through the reef's sand with a three-colour coral rim, plate corals down its wall, a glow at the bottom) and the Clam Garden (seven giant clams with glowing pearls), garden eel patches.
- **Open Blue** (`BlueDress.luau`): the Whale's Rest (a great whale's skeleton on the floor far below), Hammerhead Pinnacle (a coral spire at the sector's far edge with hammerheads circling), golden sargassum rafts at the surface with little fish under them, glowing jelly chains drifting mid-water.
- **Named places** (`Config/Places`, `LandmarkService`): 14, two a biome (the Ruins' Great Temple and Sunken Theatre, the Vents' Forge and Brine Pool too). The first visit toasts "Discovered … (n/14)" and pays coral and shells; all 14 pay 5,000 coral, 100 shells and 2 spins more. The LOG has a **Places** tab; the maps mark found places (names on the full map); the minimap's name bar names the place you're in.
- **Play:** BITE the galleon's bell (it rings for everyone near); swim into the Bay Cannon's muzzle (it fires you over the bay); BITE a clam's pearl (120 coral, 6 shells; gone for you for 15 minutes); a Weathered or Captain's map may bury its chest under the galleon's lit cabin windows (30%); eels duck as you swim over; otters, the buoy and the rafts bob; jelly chains drift.
- Every model has a part-built stand-in, so everything works before the import. Each landmark clears the biome's random scatter (rocks, corals, kelp, seeps) off its ground.
- **Terrain changed** (the Blue Hole, the Squid's Lair, the Trench pillars cleared from the spine): the map chart is regenerated and needs a re-upload.

## 1. Sync and import

1. Merge `origin/claude/world` into `claude/core-systems`, `rokit install`, `rojo serve`, connect the plugin.
2. Format with `stylua --line-endings Windows src --glob "!**/Packages/**"`.
3. `python tools/fetch_assets.py` (fetches `biome_wreck_glb`, `biome_trench_glb`, `biome_kelp_glb`, `biome_reef_glb`, `biome_blue_glb` into `assets/glb/props/`). Every image in them was screened with the classifier (highest 0.023); no normal maps.
4. **File → Import 3D**, no rig, **Import All**, these 30 GLBs from `assets/glb/props/` (in small batches, one biome at a time, waiting for each to finish):
   1. Wreck: GalleonBow, GalleonStern, IronSteamer, ToppledLighthouse, WreckCannon, WreckAnchor, WreckFigurehead, WreckWheelBell, WreckBarrels.
   2. Trench: LeviathanRibs, LeviathanSkull, TrenchCrystals, TrenchGlowTubes, GlassSponge, GlowEggs, BoneHeap.
   3. Kelp: LobsterTrap, SunkenRowboat, SeaOtter, UrchinRock, KelpBuoy, SeaGrass (skip KelpCanopy: it isn't used).
   4. Reef: TableCoral, GiantClam, GardenEels, PillarCoral.
   5. Blue: WhaleSkeleton, Sargassum, JellyChain, CoralPinnacle.
5. Paste `tools/studio/organize_imports.luau` into the Command Bar. Each should be filed as `ReplicatedStorage.WorldProps.<Name>`; note anything it leaves in Workspace.
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
1. The Kelp Cathedral (45°, about 345 studs out): a ring of kelp much taller than the forest round it. Swim into the nave: open floor, sea grass, light coming down the middle, the fronds roofing it in.
2. The ring sways like other kelp and gives way when you push through.
3. Otter Meadow (300°): otters on their backs at the surface bob; the buoy bobs; the urchin rocks are solid.
4. The trap-and-rowboat trail leads off toward the Wreck bay.

**BR — Coral Reef.**
1. The Blue Hole (near 40°, about 640 out): a round sinkhole, rim corals in three colours, plate corals down its wall, a faint glow at the bottom. Swim to the bottom and back up: no snags.
2. No reef head or random coral stands inside the hole or on its rim's path.
3. The Clam Garden (near 320°, about 660 out): BITE a pearl. A toast, +120 coral and +6 shells, and that pearl disappears for you. BITE the same spot again: nothing. Admin **Places: unfind every named place, regrow the pearls** brings it back.
4. Garden eel patches by the hole and the clams duck into the sand as you swim low over them and rise again after.

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
