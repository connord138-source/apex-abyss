# Apex Abyss — PC overnight test (2026-10-14)

Studio on `ApexAbyss.rbxl`, `claude/core-systems` with `origin/claude/world` merged (fast-forward to a3bf9a2), Rojo 7.7.0 on 34873. Solo Play, Test → Server & Clients with 2 and then 3 players, the Controller Emulator and the Device Simulator (iPhone 17 Pro). Studio has no DataStore here ("Roblox API services unavailable · data will not be saved"), so every Play starts from a fresh profile.

**Not published.** The publish conditions held (S1 and M1 pass, no game-script errors in any Output, none of the new systems badly broken), but File → Publish As was refused by this session's permission check, so the experience is unchanged. The place was saved to `ApexAbyss.rbxl` at 04:10:59 with every fix below synced in. Publishing is one step for Connor: File → Publish As → Update existing experience → Apex Abyss → Overwrite (keep it private).

The Deep Pass product id is still needed (`Config/Monetization` `DeepPass.id`).

Screenshots: `apex-abyss-playtest-shots/2026-10-14/` (the names below are the files without `.jpg`).

## Map image

`assets/textures/map_chart.png` uploaded through the Asset Manager at 00:11: **AssetId 117869098488158**, now in `Config/Textures` `mapChart` (61caa1a). No other image was uploaded, no model bundle was re-imported and no normal map was uploaded. (The Asset Manager also lists an image "Developer…" 118145242983246 uploaded at 00:06 — not mine.)

## Results

| Check | Result | Notes | Screenshots |
|---|---|---|---|
| 0 merge and sync | pass | Merge fast-forwarded; StyLua clean; Rojo connected; first Play: Error 0, Warning 0, minimap chart renders, POD on the HUD row. | `0-play-start-hud-pod-button-minimap-chart`, `0-output-after-play-start-0-errors-0-warnings` |
| 1 upload | pass | See "Map image". | `UPLOAD-asset-manager-map_chart-117869098488158` |
| S1 max fish in the den | pass (notes) | LV 100 Nibbler (model 14.3 × 13.7 × 16.9, root 6.8), Reef Shark (9.6 × 7.7 × 16.9) and Pufferfish (14.9 × 12.0 × 16.9) all fit the doorway, Nook, Burrow, Hall shaft down and up, Hall, Grotto, Sanctum shaft down, Sanctum, and turn round in each. **Sanctum shaft up is hard for a big fish:** rising straight up from below with W or Space slides along the vault and stops at y −56; an off-centre start (Reef Shark) or a pitched approach from behind the shaft (Pufferfish, which went up both shafts in one go into the Nook) works. At the Burrow's back wall the default camera went into the rock once (Nibbler). Open sea beside a Reef Shark predator. | `S1-nibbler-LV100-*`, `S1-shark-LV100-*`, `S1-puffer-LV100-*`, `S1-nibbler-LV100-burrow-back-wall-camera-in-rock`, `S1-nibbler-LV100-beside-reef-shark-predator-open-sea`, `S1-output-*` |
| S2 sizes | pass | `Size.length`: LV 1 2.00, 10 2.72, 20 3.83, 30 5.39, 40 7.48, 60 12.26, 80 15.73, 100 16.91. A LV 100 fish is 1.21× a Reef Shark predator (14). | `S2-puffer-LV30/60/80/100-plaza-fixed-camera`, `S2-output-size-curve-and-reef-shark-14` |
| S3 balance at LV 60 | pass | Sardines swallowed (Haul 13 kg); Reef Shark predator bites take 30.0% ×3; our bites land (its bar 1.000 → 0.920). At LV 30 a Reef Shark prey reads "REEF SHARK · TOO BIG TO EAT · SWIM!" with a 20% nip. 2 clients: P1 LV 60 (12.16) swallows P2 LV 20 (6.68, "PREY" tag) → "You ate Player2!", Haul +30.6 kg. | `S3-*`, `S3-2c-P1-LV60-near-P2-LV20-prey-tag`, `S3-2c-P1-ate-Player2-haul-31kg` |
| M1 seafloor map | pass after fix | Minimap and full map match the world (hub arrow in the seamount, tunnel mouths, wreck bay W, drop-off E, Trench rim S); legend W / ★ / teal dot. HYDROTHERMAL VENTS sat on the Shipwreck Graveyard's level line → fixed (e50f847), re-tested clear. | `M1-*`, `M1-full-map-label-overlap-vents-on-wreck-level-and-whale-fall-toast`, `M1-retest-vents-label-clear` |
| N1 den notes | pass after fix | Sconce on the floor refused ("Put it on the floor, or on top of something"); lamp on a table allowed; a joint aim lands the Kelp Bed on the deck, snapped; the pool shows one hint; the Abyss Glow set stays open after dropping back to LV 1. Locked set rows cut their piece lists at the 4th piece → fixed (2cf2ac3), re-tested full lists. | `N1-*`, `N1-retest-locked-rows-full-list-1/2` |
| B1 snapping | pass, one partial | R/F turns 0 → 45 → 90 → 45 with snap; G SNAP OFF gives 60/75, G back rounds to 90. A lamp aligns to a table's x (−7.4 → −8.00, "snapped"). Shelves back onto the Sanctum wall and the Hall's curved wall. Wall lanterns snap to a neighbour's height. **Pillar backing:** the backed spot lands in the pillar's deck hole ("That's not on your floor"); 1 stud further out there is no snap (not fixed — see "For a decision"). | `B1-*`, `B1-pillar-backing-refused-not-on-your-floor`, `B1-pillar-1-stud-further-no-snap` |
| B2 starter layouts | pass after fixes | All seven sets laid out with L ("Laid out N … pieces · move any of them as you like"): Kelp Cottage (Nook, 5), Reef Palace twice side by side (Hall, 5 + 5), Shipwreck (Hall back, 4), Sunken Temple (Grotto wing, 5), Vent Forge (Grotto deep, 6), Abyss Glow (Sanctum nave, 5), Trophies (Sanctum apse, 4); wall and ceiling pieces stay in the tray. Moving and putting away layout pieces work. Full Nook: "Not enough open floor here · aim at a roomier spot". At 122/125, L lays out 3 of the 6 Vent Forge pieces; at 125/125: "Your den holds 125 things · upgrade it for more". **Fixed:** L's refusal text was wiped the next frame (6b42fc9); L on an aimed placed piece did nothing (ddf4dba). Both re-tested. | `B2-set-*`, `B2-moving-*`, `B2-put-away-treasure-hoard-47of125`, `B2-not-enough-room-nook`, `B2-capacity-*`, `B2-retest-*` |
| B3 controller and phone | pass | Controller Emulator: D-pad up toggles SNAP ON/OFF; D-pad down lays out the aimed set (4 Reef Palace pieces). Phone: the 7 buttons (PLACE, TURN, SNAP, LAY OUT, PUT AWAY, DROP, DONE) fit without overlap and all work; the tray sits above the HAUL card. | `B3-controller-*`, `B3-phone-*` |
| C1 codes | pass after fix | Shop → Free Perks → Codes → REDEEM opens the box. APEX: 1,000 coral, 50 shells. deepdive: 60 shells, 1 wheel spin. MEGA LODON: 750 coral, 1 Lucky Charm. NIBBLER: 100 shells. Again: "You've already used that code". Junk: "That code doesn't work". Admin Codes reset, then NIBBLER pays again. Enter submits. The Roblox Premium row's blurb was cut at "Coral Garden and a" → fixed (d2b1efd), re-tested. | `C1-*`, `C1-retest-premium-row-full-blurb` |
| C2 controller codes | pass | View opens the Shop; D-pad reaches Codes → REDEEM; A opens the box and focuses the field; typing works (Studio shows no on-screen keyboard for a pad); B closes. D-pad down from REDEEM leaves the window for the ADMIN button. | `C2-*` |
| CH1 chum from a death | pass | Solo: Haul 100 kg, eaten in the Kelp → a cloud of red chunks and murk sinking where the fish died, gone after 45.1 s; swimming through: "CHUM +x", Haul 0 → 40 kg (the 40% share). 2 clients: P1 eats P2 (Haul 50) → 14 chunks (20 kg) where P2 died, 66 s in a Blood Tide; P2 respawned, swam back and ate them: Haul 0 → 20 kg. | `CH1-*`, `CH1-2c-*` |
| CH2 chum in front | pass (slow lure) | 20 kg ahead: all chunks sucked in within ~1.5 s, feels like shrimp. 100 kg burst near a Barracuda (94 studs, r 294): it reached the cloud at ~15–17 s and then circled it. Not ~10 s: the lure is only checked when a roaming predator picks its next waypoint (every 6–12 s). Chum near the hub doesn't lure, by design. | `CH2-*` |
| CH3 Blood Tide | pass | Banner "THE TIDE TURNS · BLOOD TIDE · … chum in the water …"; the top chip shows only "BLOOD TIDE" and the timer. Slicks every 20 s (5.1, 25.4, 45.3, 65.7 s), 87–96 studs from me, 7 chunks, 40 s. | `CH3-*` |
| CH4 Whale Fall | pass (notes) | Natural: first at 90 s, then every 6 min, never two at once. Toasts "A WHALE FALL is coming down in the …" then "The whale is sinking into the … · feed while it lasts!"; pulsing W on the minimap and full map. Trench whale: 18 chunks; eaten ones back in 13.0–13.8 s; gone at 5 min and the W cleared. Coral Reef whale settled on the sand. Admin "Whale Fall now" during one: "A Whale Fall is already coming or under way". In a fresh server it works ("Whale Fall in the Sunken Ruins in 5 s"). Issues: see "For a decision". | `CH4-*` |
| P1 pods | pass | POD on the HUD row; invite → POD ! gold; JOIN / DECLINE with a countdown; decline, run-out, join and LEAVE all work. In a pod: PODMATE nametag and teal map dot; no swallow, bites do nothing, no PREY/DANGER. Slipstream: "SLIPSTREAM +15% SPEED", 37.6 vs 33 studs/s, the gap closed 11.1 → 1.7 in ~3 s. Pad: Shop → Pod row → POD menu with the D-pad, B closes. | `P1-*`, `X1-pod-menu-via-shop-pad` |
| P2 shared kills | pass | 3 clients. A (LV 40) eats C (LV 10, Haul 30) with podmate B 88.5 studs away: B gets "Pod kill by Player1 · +4.8 kg Haul" (half A's gain). | `P2-A-ate-C`, `P2-B-pod-kill-toast-plus-4.8kg` |
| SC1 schooling | pass (by log); hint not confirmed | 3 clients, C LV 60, A and B LV 30. A alone: −2.9; B biting 0.8 s after A: −5.4 to −6.8, and B's client receives "SCHOOL BITE ×2" each time (logged from the Notify remote; my shots kept missing the 3 s toast). The 2-client SCHOOL hint did not show in ~6 s (a BITE hint was up first; hints are capped). | `SC1-*` |
| A1 the Apex | pass | Crowned within seconds: toast to everyone, gold ★ on both maps, gold outline and "★ APEX · 500 BOUNTY" nametag, "YOU ARE THE APEX" chip. Bounty +150/min out of the hub, flat in the hub. A clearly heavier fish takes the crown. Fresh Apex eaten: "Its reign was too short for a bounty". Admin-crowned Apex eaten: 500 coral paid, "New title: Apex Hunter", toast to all. Same pair again: "No bounty: you two traded the crown too recently". Creature kill: no payout. ★ shows on the full map with the Apex 1,100 studs away. | `A1-*` |
| D1 pressure | pass | LV 1 at 474 ft: "PRESSURE BUILDING · rise above 460 ft" fills over 6 s, then "CRUSHING", −3%/s; rising clears it. Edge darkening is faint in screenshots; creaks not checkable here. | `D1-*` |
| D2 bands | pass | LV 25 fine at y −150, crushed below −330 ("rise above 708 ft"); LV 40 fine on the Ruins floor, crushed in the Vents basin; LV 70 fine on the Trench floor. | `D2-*` |
| D3 never there | pass, one question | Hub and den (Sanctum, y −63): no pressure. The tutorial's own targets stay on the shelf, but there is **no tutorial exemption**: a tutorial fish taken off the shelf is crushed. | `D3-*` |
| D3b bosses and maps | pass after fix | No pressure within 500 studs of the Giant Squid in the Trench (crushing again 701 studs away). Three Captain's maps for a LV 10 fish: all sites above its line (y 2, −18, 2). Satchel chest-odds rows were cut at "…" → fixed (3921469), re-tested. | `D3b-*` |
| D4 Pressure Hide | pass | Outfitter row "Pressure Hide · Dive as if 4 levels higher per level (depth pressure)", 400 coral; LV 21 + level 1 is fine at y −100 and crushed at −340 (the LV 25 line). | `D4-*` |
| H1 boats | pass | 5 boats 544–1,299 studs from the hub; dark hulls from below; silver bait and "BAIT · it's on a hook" tag; lines up and down again every 20–36 s. | `H1-*` |
| H2 hooked | pass | "+73 kg bait · HOOKED! Mash BITE or DASH to break free", HOOKED panel and bar, dragged up; 12 mashes → "You broke free, and kept the bait!". 20 requests in 1 s counted 6 (rate cap works). | `H2-*`, `H2b-*` |
| H3 landed | pass | 9.8 s on the line → "Landed! The fisherman kept 44 kg of your Haul" (exactly 30%). | `H3-landed-fisherman-kept-44kg`, `H2b-H3-log-0.60-and-30pct` |
| H4 podmate cuts the line | pass | 2 clients in a pod. P2 hooked; P1 15.4 studs away bites the line: P1 "You bit Player2's line!", P2 "Your podmate bit the line. You're free!" 1.6 s after the hook, bait kept. The bite went through the BiteLine request (what the BITE button sends when a hooked podmate is near); a first try with right-click did nothing because P1's Daily window was open. | `H4-*` |
| H5 boss grab | pass | Squid "GRABBED · mash BITE to break free" → 6 mashes, free in 1.3 s, swimming normally after; a second grab broken by right-click mashing. Hook + grab at once not set up (no boat over the squid). | `H5-*` |
| SP1 speed checks | pass | No line from dash spam, Teleport to ×5, respawns, Megalodon hits, hook drag, a podmate cutting the line or slipstream. Every line all night came from my own client-side test teleports (below). | `SP1-*` |
| R1 regressions | pass | Tutorial played through (one card overlap fixed, 108b550); banking and the Double Haul offer; treasure dig; Treasure Wheel; Daily and playtime gift; Tide Pass panel; roll; wardrobe; Megalodon fight (last stand, exhausted, staggered, killing bite, shade reward); squid grab and mash. | `R1-*` |
| X1 controller | pass, one inconclusive | Pod menu via Shop, Codes window, Build snap/layout, B closes. The HOOKED panel switches to "Mash RB or RT"; with the emulator only ~6 of 16 taps counted once and 0 of 12 the next time, so the hook landed. Both buttons call the same struggle code; needs a real pad. | `X1-*` |
| X2 phone | pass after fixes | POD on the HUD row; PRESSURE panel clear of BITE/DASH/HEAL and HAUL; Apex chip clear. Fixed: HOOKED panel over the HAUL card and ITEMS (335c066), biome chip behind the minimap (2a4049b), Codes box hidden by the keyboard (f299763), hint chip over the HOOKED/PRESSURE panels (d311de6). All re-tested. SLIPSTREAM chip on the phone not checked (needs a podmate). | `X2-*` |
| PF1 performance | pass | See "Frame rate". Nothing stuttered. | `PF1-*` |
| 15 publish | **not done** | Conditions held; blocked by the session's permission check (see top). |  |

## Frame rate

| Where | FPS |
|---|---|
| PC: Kelp Shallows, calm | 36.8 over 8 s |
| PC: Vents Whale Fall feeding + two 100 kg chum bursts + Blood Tide | 60.0 over 10 s |
| PC: under the boats (one of five on screen; they're 280–1,300 studs apart, so never all in view) | 60.0 over 8 s |
| Phone simulator (iPhone 17 Pro): Kelp Shallows | 55.3 over 8 s |

Counted on RenderStepped. The kelp forest is the heavier view, not the new effects.

## Output errors (verbatim)

No error from a game script in any session. The rest:

- My own command-bar probes, e.g. `CommandBar:1: invalid argument #2 to 'insert' (number expected, got string)` (01:42:48 ×2), `CommandBar:1: attempt to index nil with 'HumanoidRootPart'` (02:41:38, 02:58:23, 03:13:37), `CommandBar:1: attempt to index nil with 'GetAttribute'` (03:09:21), `Hooks is not a valid member of Workspace "Workspace"` (03:38:10), `CommandBar:1: attempt to index nil with 'FindFirstChild'` (03:38:13), `CommandBar:1: Expected identifier when parsing expression, got '117869098488158'` (02:45:39, a clipboard mix-up).
- Roblox's own CoreGui in the second client of the 2-player session, 02:31:02 (14 errors, 2 warnings): `[Roblox][CoreGui.RobloxGui.Modules.PlayerList.Components.Presentation.PlayerListApp] Requested module experienced an error while loading` (and the same for PlayerListSwitcher, PlayerListController, PlayerListManager, TopBar.Components.GamepadConnector, TopBar.Components.TopBarScrim, TopBar, CoreScripts/InspectAndBuy), `[Roblox][Script Context.StarterScript] Script Context.StarterScript:507: Invalid value for enum CreatorType`, warnings `Failure to Start CoreScript module TopBar.` and `Failure to Start CoreScript module PlayerListManager.` That client's chat window then covered our HUD row.

## [SpeedCheck] lines (verbatim)

All five came from my client-side test teleports (moving the fish by setting its CFrame), not from play:

- `01:30:40.695 [SpeedCheck] Dillionaire138 (10860839150) moved 850 studs in 1.0 s (allowed 114) · 3 strikes in 30 s · length 5.4` — M1, jumping the fish between map landmarks.
- `03:37:23.515 [SpeedCheck] Dillionaire138 (10860839150) moved 295 studs in 1.0 s (allowed 122) · 3 strikes in 30 s · length 4.0` — D4, from y −340 back up to −45.
- `03:38:40.378 [SpeedCheck] Dillionaire138 (10860839150) moved 132 studs in 1.0 s (allowed 122) · 3 strikes in 30 s · length 4.0` — H1, moving camera spots under a boat.
- `04:09:16.822 [SpeedCheck] Dillionaire138 (10860839150) moved 513 studs in 1.1 s (allowed 132) · 3 strikes in 30 s · length 4.4` — re-test, from the den pool to a bait.
- `04:15:50.507 [SpeedCheck] Player1 (-1) moved 1349 studs in 1.0 s (allowed 98) · 3 strikes in 30 s · length 2.0` — H4, jumping Player1 from the hub to its hooked podmate.

All from `Server - SpeedService:88`.

## Fixes (claude/core-systems)

| Commit | Check | What |
|---|---|---|
| 61caa1a | 1 | Map chart image id in `Config/Textures`. |
| e50f847 | M1 | Full map: the Hydrothermal Vents name moved off the Shipwreck Graveyard's level line. |
| 2cf2ac3 | N1 | A locked set row shows its whole piece list (three lines). |
| 6b42fc9 | B2 | Build mode holds L's refusal message instead of wiping it the next frame. |
| ddf4dba | B2 | L on an aimed placed piece lays out its set round that piece. |
| d2b1efd | C1 | The Shop's Roblox Premium row shows its whole blurb. |
| 3921469 | D3b | The Satchel's chest-odds rows show every reward (two lines). |
| 108b550 | R1 | Tutorial key-cap captions sit under their cap instead of running into the next one. |
| 2a4049b | X2 | Phones: the biome chip sits under the minimap instead of behind it. |
| 335c066 | X2 | Phones: the HOOKED panel sits where the pressure meter does, clear of the HAUL card and ITEMS. |
| f299763 | X2 | Phones: the Codes window opens at the top, above the on-screen keyboard. |
| d311de6 | X2 | No hint chip while hooked, grabbed or under pressure. |

Each was re-tested in a later Play session.

## For a decision (not fixed)

- **Sanctum shaft up for big fish (S1).** A LV 100 fish can't rise straight up the Sanctum shaft; it slides along the vault. It works with a pitched approach. A wider shaft mouth or a gentler vault edge would fix it.
- **Pillar backing (B1).** Backing a piece onto a pillar puts it in the pillar's deck hole ("That's not on your floor"); one stud further out there's no snap.
- **Whale Fall now in Studio (CH4).** It's refused almost all the time: in Studio the next whale is announced 1 s after the last one ends, so one is always coming or under way. Options: Studio cadence 8 min, or let the admin button replace an announced whale.
- **Ruins whale (CH4).** A whale in the Sunken Ruins settled under a ruin lintel among pillars (`ChumService.floorUnder` only sees terrain), hidden from above.
- **Tutorial and pressure (D3).** A tutorial fish taken off the shelf is crushed. Its targets stay on the shelf, so this only happens if a new player wanders.
- **Captain's map fallback (D3b).** After 40 misses `TreasureService.pickSite` falls back to `World.seabedY` and ignores the crush depth. It never happened in three tries.
- **Chum lure speed (CH2).** Predators reach a burst in ~15 s, not ~10 s.
- **Phone window titles (X2).** Every menu window's title sits under Roblox's top-left buttons on a phone.
- **Two centre banners (R1).** An achievement banner drew on top of the bank celebration.
- **Earned titles.** "New title: Apex Hunter" is only a toast; no screen lists titles.
- **Apex nametag line (A1).** "★ APEX · BOUNTY" is small and dim at 70 studs; readable at 30.
- **Emulator RB/RT mashing (X1)** needs a real controller check.

## Feel and balance

- **Size growth flattens late:** LV 80 → 100 adds only 7.5% length (15.73 → 16.91). Fine for the den, but the last 20 levels barely show.
- **Hooks are generous:** one bait was +73 kg for a LV 21 fish with 7.8 kg banked (×2 Mass in Studio). Breaking free keeps it all, so a bait is worth more than most fish. Landing takes 30%, which feels fair.
- **Chum gives the victim a way back:** P2 respawned and ate back its own 20 kg chum. Good, but a fast victim recovers 40% of what it lost.
- **Megalodon hits hard:** 55% then 35% of a LV 70 fish in two hits.
- **Pressure** feels right: 6 s of warning, then about 33 s to death at 3%/s.
- **Apex bounty** grows 150/min, so 500 → ~1,000 in under 4 minutes of reign. A bigger fish takes the crown within a 2 s tick, so short reigns are common; the 2-minute minimum stops instant farming.
- **Slipstream** at +15% closes a 10-stud gap in about 3 s. It's noticeable without being strong.

## Not covered

- A hook during a boss grab (no boat line over the squid; the boats stay 280–1,300 studs from the hub).
- The SLIPSTREAM chip on a phone, and a real controller for hook mashing.
- The Giant Squid kill and its rewards (the Megalodon's were checked).
