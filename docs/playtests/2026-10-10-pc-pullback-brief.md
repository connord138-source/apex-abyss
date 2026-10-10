Apex Abyss — PC session brief: the pull-back loop (rare catches, Catch Log with biggest catches, Tide Clock, bounties, Catch of the Week, leaderboards, Treasure Wheel) and skins per fish (2026-10-10)

Finish and push the boss see-through round first (docs/playtests/2026-10-10-pc-brief.md), then do this one. Work in C:\Users\neos1\Desktop\apex-abyss on claude/core-systems.

Connor's asks this round:
> "I still feel like we're missing a factor that pulls people back over and over. I do want to add random rarities of fish that can be eaten for more towards the haul or like 10 total unlocks a skin. I also want the skins to be different for each playable fish. Common skins should be similar to original just with realistic fish reshades and the rarer they get the wilder they get."

Then:
> "On the ten total unlocks per skin we still don't want the most elite skins obtained that way that'll be rng and bosses/treasure chests. Also do want a spin wheel again if that's not implemented yet. I want the catch log to track their biggest eat of each species and rarity of species too"

He picked all four pull-back pieces, 12 skins per fish, and catch tracks per fish per rarity. Details are in GDD §8 "The pull-back loop" and §7 "Rolls, shades and exotics".

What's new:

- **Rare catches:**
  - Any prey can swim Golden (1 in 35, Haul ×3), Glowing (1 in 180, ×6), Crystal (1 in 900, ×12) or Prism (Prism Tide only, ×25).
  - Each rare fish also pays coral and DNA.
  - Looks: gold foil, a teal glow, clear crystal, or a shifting rainbow, each with sparkles and a small light.
  - Crystal and Prism catches are announced, and a Prism fish is announced when it appears.
- **Catch Log and catch tracks:**
  - The Log has every prey × rarity. A first catch pays, and so does a finished row.
  - Catches count for the fish you swim as: 10 Golden, 10 Glowing, 5 Crystal and 3 Prism unlock that rarity's skin for it.
  - **Earned skins stop at Epic:** Golden is Uncommon, Glowing Rare, Crystal and Prism Epic, and the weekly skins Epic. Legendary and Mythic come only from rolls, the wheel's jackpot, bosses and treasure.
  - **Biggest catches:** every school fish now has its own size (0.82–1.18 of its species, and 1 in 25 a trophy at 1.25–1.5), and its mass and Haul go with it. The Log keeps your heaviest of each species at each rarity. A record on a rare or trophy-sized fish toasts NEW BIGGEST.
- **Tide Clock:**
  - The tide changes every 20 minutes on one world clock: Calm, Golden Hour, Blood Tide, Sardine Run (bait balls) and Bioluminescent Night.
  - The Prism Tide comes at 03:00, 09:00, 15:00 and 21:00 UTC.
  - Shown by a chip at the top, a banner, a faint tint in the water and a forecast.
- **Daily bounties:** three a day, each paying when done, plus the Bounty Chest when all three are finished.
- **Catch of the Week:** this week (week 1) is the Crystal Grouper, ×3 as common, with a limited skin.
- **Weekly leaderboards:** Rare Catches, Biggest Haul and Boss Damage. Each shows this server and all servers, and last week's top 100 earn titles.
- **LOG** button (beside DAILY): tabs for Catch Log, Bounties, Weekly and Tides.
- **Treasure Wheel** (Hatch & Snatch's Luck Wheel, ported and re-themed teal and brass): on the hub plaza at 240°, 62 studs from the beacon.
  - E spins at the big red button (Y on a controller, SPIN on a phone), and T (ALL) is Spin all. A second spinner joins the line.
  - 8 slices: 300 coral, a treasure map, 40 shells, Feast Charm, +2 spins, 2 Kelp Wraps, Lucky Charm, and a 4% JACKPOT of a Rare-or-better skin from your fish's line.
  - Spins are never sold. One is free every 4 h, online or off, up to 3 waiting. A new save starts with one. The Bounty Chest gives 1, the Catch of the Week 2, and daily days 3 and 6 one each.
- **Skins per fish:**
  - Each fish has its own 12: 4 realistic Commons (sold by the Dyer), then Uncommon, Rare, Epic, Legendary and Mythic.
  - Every fish can also earn the catch-track skins, the weekly skins and the trophy and treasure skins.
  - The skin textures are made (v4: 23 a fish, 138 in all, every GLB cleared by the moderation screen). Import them in section 1b. A skin that isn't imported shows as its tint.
- **Admin** has new sections, TIDES · RARE CATCHES · BOUNTIES · WEEKLY and TREASURE WHEEL (give spins, rig the next slice), for all of the above.

## 1. Merge and sync

1. git fetch origin claude/world, then git merge origin/claude/world (it should fast-forward).
2. stylua --line-endings Windows src --glob "!**/Packages/**"
3. rojo serve on port 34873, connect, Play Solo. Expect "Server started" and "Client ready", no errors.

## 1b. Import the new skins (edit mode, before testing)

The account was suspended once over an uploaded texture, so go slowly:
1. python tools/fetch_assets.py (it downloads the changed `shade_skins` bundle into assets/shades/glb).
2. In edit mode, File → Import 3D the six assets/shades/glb/<Fish>_Shades.glb files **one at a time**, waiting about 3 minutes between them. If Roblox rejects or moderates any image, stop and report it. Don't retry and don't upload from another account.
3. Run tools/studio/organize_shades.luau in the Command Bar. Expect "[organize_shades] filed 138 skin(s) for 6 fish". Each ReplicatedStorage.ShadeSkins.<Fish> holds 23 (the folder is cleared first, so the old 33 are gone), and no _Shades models are left in the Workspace.
4. Save the place (Ctrl+S).

## 2. Rare catches (keyboard; LV 15+ Nibbler, then a 'Cuda)

- **R1 Looks.** Swim into the Kelp Shallows. Admin "Turn the 10 nearest fish" to Golden, then Glowing, Crystal and Prism in turn.
  - Each looks like its rarity: gold foil, teal glow, crystal glass, rainbow cycling. Each has sparkles and a small light.
  - Each reads from 100+ studs away.
  - Screenshot each, close and far.
  - Say whether any looks cheap or unreadable, or makes a fish's shape a blob.
- **R2 Eating one.** Swim into a Golden fish:
  - the HUD pop reads GOLDEN +x in gold;
  - a toast reads "GOLDEN MINNOW · +N coral · Golden skin 1/10";
  - the Haul goes up about 3× a plain fish's.
  - Do the same for Glowing, Crystal (a server toast "<you> caught a CRYSTAL …") and Prism.
  - Log the Haul gained for a plain and a rare fish of the same species.
- **R3 Natural spawns.** With no Admin, swim the Shallows and Reef for 5 minutes.
  - Count the Golden fish you see. Expect a few per minute of swimming.
  - Note any rare fish that pops in or out of its look in front of you. The server only re-rolls fish more than 260 studs from everyone.
- **R4 Respawn.** Eat a rare fish; it comes back after its respawn time as a fresh roll (usually plain).

## 3. Catch Log and catch tracks

- **C1 LOG → CATCH LOG:**
  - The track rows show your fish's 4 catch skins with counts.
  - The grid has 7 prey × 5 columns (Plain, Golden, Glowing, Crystal, Prism). Each caught cell shows how many and your biggest (kg), and each row shows that species' biggest.
  - First catches show "NEW IN THE CATCH LOG · … +N coral".
  - Screenshot it.
- **C2 Unlock:**
  - Admin "Catch track: add catches", Golden ×9, then eat one Golden fish.
  - The SKIN UNLOCKED banner reads "GOLDEN NIBBLER", and the skin is Uncommon (Glowing is Rare, Crystal and Prism Epic).
  - The Wardrobe shows Golden unlocked; wear it.
  - Switch to the 'Cuda: its Golden track is 0/10 (per fish).
- **C3 Row:** for one prey, catch every rarity (use Admin turns, and the Prism Tide below for Prism). "CATCH LOG ROW DONE" pays 3,000 coral and 60 shells.
- **C4 Biggest catches:**
  - Look at a school up close: the fish differ in size, and now and then one is clearly bigger (a trophy).
  - Eat 20 plain Minnows. The Minnow row's Plain cell shows the heaviest, to two decimals under 1 kg.
  - Turn some fish Golden and eat them. A new heaviest Golden toasts "NEW BIGGEST · … (was …)". A trophy-sized plain fish that beats your record says it too.
  - The den's trophy wall shows your heaviest catch by its real mass.
  - Log 5 masses for one species to show the spread.

## 4. Tide Clock

- **T1 Chip:**
  - A small chip at the top centre names the tide and its time left (m:ss).
  - Within the hour before a Prism Tide, a second line counts down to it.
  - With a boss up (Admin SUMMON), the chip sits under the boss bar.
  - Screenshot it, with and without a boss.
- **T2 Each tide.** Admin "Force a tide" through each one (10 minutes, this server). For each, check:
  - The banner: THE TIDE TURNS, the name and what it does.
  - The water's tint: subtle, never garish.
  - The chip changes.
  - Golden Hour: within 1–2 minutes there are many more Golden fish (×5).
  - Blood Tide: the Barracuda and Reef Sharks are faster and notice you from further off. Log the aggro distance from a few tries.
  - Sardine Run: big tight bait balls appear in the Kelp Shallows and over the reef. Eat some. Force Calm and they vanish (from a distance, not a pop in your face).
  - Bioluminescent Night: the sea dims a little, and there are more Glowing fish (more in the deep).
  - Prism Tide: Prism fish appear within about 2 minutes, announced "A PRISM … shimmers in …".
  - "Back to the clock" restores the real tide.
  - Screenshot each tide's banner and water.
- **T3 Forecast.** LOG → TIDES:
  - The tide now and the next nine, each with "in h:mm:ss · local time".
  - The ★ PRISM TIDE ★ sits at its UTC times.
  - The chip and the forecast agree.

## 5. Bounties

- **B1** LOG → BOUNTIES shows three different bounties for your level, the chest row, and "new ones in …".
- **B2** Play one to completion (e.g. "Eat 60 fish"). The toast reads "BOUNTY DONE · … · reward", and the reward lands.
- **B3** Admin Bounties "Finish all three": each pays, then "BOUNTY CHEST · 1,000 coral, 50 shells, 1 Lucky Charm, 1 wheel spin". The wheel's spin count goes up by 1.
- **B4** Admin "Draw new ones" gives a fresh three. A rejoin keeps the same three for the day.

## 6. Catch of the Week and leaderboards

- **W1** LOG → WEEKLY shows the CRYSTAL GROUPER: ×3 all week, the rewards, the Great Wave skin, "NOT YET", and ends in ….
- **W2** Admin "Catch of the Week: catch it":
  - the CATCH OF THE WEEK banner;
  - +5,000 coral, 100 shells and 2 wheel spins;
  - the Great Wave skin unlocked for your current fish;
  - a server toast;
  - the tab now says ✓ CAUGHT.
  - A second catch pays only the normal rare rewards.
- **W3** Boards:
  - Rare Catches goes up as you catch rare fish (Golden +1, Glowing +5 …).
  - Biggest Haul is your biggest bank this week.
  - Boss Damage is your bites on a boss.
  - THIS SERVER shows both clients (Local Server).
  - ALL SERVERS in Studio says it needs the published game, and shows this server.
  - Admin "Leaderboard: add to my score" moves you up.
  - Screenshot each board.

## 7. Skins per fish

- **K1 Wardrobe:**
  - As the Nibbler, the Shades tab lists its 12 in order: Percula, Tomato, Maroon, Midnight (Common), then Bumblebee, Lilac, Seafoam (Uncommon) … Prismatic (Mythic).
  - Then Golden, Glowing, Crystal and Prism (the catch track: "catch 10 Golden fish as this fish (the LOG's catch track)"), with the tiers Uncommon, Rare, Epic and Epic. Then Ghost and Abyss Ink (bosses), and Sunken Gold and Drowned Pearl (treasure). A week's skin shows only once you have it.
  - Switch to the 'Cuda: a different 12 (Great, Yellowtail, Chevron, Blackfin … Comet). Repeat for each unlocked fish.
- **K2 Dyer:** it sells only the current fish's 4 Commons.
- **K3 Odds:** ODDS lists the fish's 12 skins plus coral and parts. The total is 100%, coral is 82.5% for a fresh fish, and no other fish's skins appear.
- **K4 Roll:** roll 20 times (Admin shells). Only this fish's skins come up, and the reel's filler cards are this fish's too.
- **K5 Old skins:** if your Studio save had shades that now belong to another fish's line, they turned into coral on join. Note your coral before and after the merge.
- **K6 Looks:** with the skins imported, wear each fish's 12 plus the catch and weekly skins (Admin "Every shade, part and variant"). Compare them with assets/shades/previews/<Fish>_sheet.jpg.
  - Each matches its sheet.
  - The glowing ones glow and pulse: Comet, Sunburst, Jade, Bioglow, Glass Veins, Abyss Eye, Lantern King, Starfall, Glowing and Prism.
  - No skin shows white or untextured after a few seconds.
  - Screenshot each fish in its Mythic, and the 4 Commons side by side for one fish.
  - Say which look cheap, stair-stepped (the Cuda's Chrome and Sunset edges), or too alike (the Angler's dark Commons, the shark's grey Commons).

## 8. Treasure Wheel

- **S1 Placement:** the wheel stands on the hub plaza at 240° (between stalls; it shouldn't block a stall, a den door, a tunnel or the beacon). It stands on the floor with no gap and isn't buried.
  - Screenshot it from the plaza, by day and with a boss up.
  - Say whether it reads as a game-show wheel and fits the cave, or looks cheap.
- **S2 Hint:** swim up to the red button. A chip reads "E · SPIN (1)" with "next free spin in …" under it.
  - It shows Y on a controller and SPIN / ALL buttons on the phone.
  - It goes away a few studs from the button.
  - The stall hint (E · Shop) and the wheel never both take E: swim slowly from the Tidecharm Trader's counter (the nearest stall) to the button. One hint hands over to the other, never both at once, and E opens whichever is showing.
- **S3 Spin:** press E. The wheel turns for about 5.5 s with ticks off the pegs, the flapper swings, and the bulbs chase.
  - It stops with the flapper hanging straight in the middle of a slice, and the prize matches that slice.
  - The banner reads "YOU WON …", and the prize lands (coral, shells, wraps, charm, map in the SATCHEL, or +2 spins).
  - A second client sees the same spin and stop.
- **S4 Line:** with two clients, spin on both. The second gets "You're #1 in line" and spins after the first's result.
- **S5 Spin all:** Admin "Wheel: give spins" 10, then press T. It keeps spinning until you're out, then "Spin all done". Press T mid-way and Spin all goes off.
- **S6 Jackpot:** Admin "Wheel: the next spin lands on" JACKPOT · SKIN, then spin.
  - You get a Rare-or-better skin from the current fish's line, never a Common or Uncommon, or another fish's skin.
  - It's announced to the server, and Spin all pauses on it.
  - Wear it from the Wardrobe.
  - Rig it on a fish that owns every Rare+ skin (Admin every shade): 2,500 coral instead.
- **S7 Free spins:** a fresh save has 1 spin. Use it; the hint says the next free one is about 4 h away. Rejoin: the count and timer hold.
- **S8 Other sources:** the Bounty Chest (B3), the Catch of the Week (W2) and daily streak days 3 and 6 (Admin "Daily: set the streak" to 2 and 5, then claim) each add spins.

## 9. Layout and performance

- **L1** PC 1280×720 and the iPhone 14 simulator: the LOG button sits with DAILY and SHOP (at the end of the HUD row on the phone), with nothing overlapping. The LOG window fits, and its tabs and rows read (the cells' counts and kg too). The wheel's SPIN / ALL buttons don't cover BITE, DASH or the stall button.
- **L2** The tide chip doesn't cover the boss bar, the biome banner or the safe-zone banner. The tide banner and a biome banner at once don't overlap.
- **L3 FPS:** in the Shallows during a forced Golden Hour (many golden fish with lights), log average and worst frame on PC and the phone.

## 10. Output

0 game errors.

## 11. Report

Write docs/playtests/2026-10-10-pc-pullback.md:
- R1–R4, C1–C4, T1–T3, B1–B4, W1–W3, K1–K6, S1–S8, L1–L3 and Output: pass/fail with the logged values
- screenshots: each rare look (close and far), the LOG's four tabs, each tide's banner and water, the skin unlock banner, the Catch of the Week banner, the Wardrobe for two fish, the wheel (plaza, mid-spin, the jackpot result)
- your verdict: does this make you want to come back (for a tide, a bounty, a rare fish, a free spin, the board)? What feels thin?
- any Output errors, verbatim

Commit and push to claude/core-systems.
