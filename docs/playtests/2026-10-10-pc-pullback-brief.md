Apex Abyss — PC session brief: the pull-back loop (rare catches, Catch Log, Tide Clock, bounties, Catch of the Week, leaderboards) and skins per fish (2026-10-10)

Finish and push the boss see-through round first (docs/playtests/2026-10-10-pc-brief.md), then do this one. Work in C:\Users\neos1\Desktop\apex-abyss on claude/core-systems.

Connor's asks this round:
> "I still feel like we're missing a factor that pulls people back over and over. I do want to add random rarities of fish that can be eaten for more towards the haul or like 10 total unlocks a skin. I also want the skins to be different for each playable fish. Common skins should be similar to original just with realistic fish reshades and the rarer they get the wilder they get."

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
- **Tide Clock:**
  - The tide changes every 20 minutes on one world clock: Calm, Golden Hour, Blood Tide, Sardine Run (bait balls) and Bioluminescent Night.
  - The Prism Tide comes at 03:00, 09:00, 15:00 and 21:00 UTC.
  - Shown by a chip at the top, a banner, a faint tint in the water and a forecast.
- **Daily bounties:** three a day, each paying when done, plus the Bounty Chest when all three are finished.
- **Catch of the Week:** this week (week 1) is the Crystal Grouper, ×3 as common, with a limited skin.
- **Weekly leaderboards:** Rare Catches, Biggest Haul and Boss Damage. Each shows this server and all servers, and last week's top 100 earn titles.
- **LOG** button (beside DAILY): tabs for Catch Log, Bounties, Weekly and Tides.
- **Skins per fish:**
  - Each fish has its own 12: 4 realistic Commons (sold by the Dyer), then Uncommon, Rare, Epic, Legendary and Mythic.
  - Every fish can also earn the catch-track skins, the weekly skins and the trophy and treasure skins.
  - The new skin textures aren't imported yet: until they are, a new skin shows as its tint.
- **Admin** has a new section, TIDES · RARE CATCHES · BOUNTIES · WEEKLY, for all of the above.

## 1. Merge and sync

1. git fetch origin claude/world, then git merge origin/claude/world (it should fast-forward).
2. stylua --line-endings Windows src --glob "!**/Packages/**"
3. rojo serve on port 34873, connect, Play Solo. Expect "Server started" and "Client ready", no errors.

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
  - The grid has 7 prey × 5 columns (Plain, Golden, Glowing, Crystal, Prism), with counts where caught.
  - First catches show "NEW IN THE CATCH LOG · … +N coral".
  - Screenshot it.
- **C2 Unlock:**
  - Admin "Catch track: add catches", Golden ×9, then eat one Golden fish.
  - The SKIN UNLOCKED banner reads "GOLDEN NIBBLER".
  - The Wardrobe shows Golden unlocked; wear it.
  - Switch to the 'Cuda: its Golden track is 0/10 (per fish).
- **C3 Row:** for one prey, catch every rarity (use Admin turns, and the Prism Tide below for Prism). "CATCH LOG ROW DONE" pays 3,000 coral and 60 shells.

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
- **B3** Admin Bounties "Finish all three": each pays, then "BOUNTY CHEST · 1,000 coral, 50 shells, 1 Lucky Charm".
- **B4** Admin "Draw new ones" gives a fresh three. A rejoin keeps the same three for the day.

## 6. Catch of the Week and leaderboards

- **W1** LOG → WEEKLY shows the CRYSTAL GROUPER: ×3 all week, the rewards, the Great Wave skin, "NOT YET", and ends in ….
- **W2** Admin "Catch of the Week: catch it":
  - the CATCH OF THE WEEK banner;
  - +5,000 coral and 100 shells;
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
  - Then Golden, Glowing, Crystal and Prism (the catch track: "catch 10 Golden fish as this fish (the LOG's catch track)"), then Ghost and Abyss Ink (bosses) and Sunken Gold and Drowned Pearl (treasure). A week's skin shows only once you have it.
  - Switch to the 'Cuda: a different 12 (Great, Yellowtail, Chevron, Blackfin … Comet). Repeat for each unlocked fish.
- **K2 Dyer:** it sells only the current fish's 4 Commons.
- **K3 Odds:** ODDS lists the fish's 12 skins plus coral and parts. The total is 100%, coral is 82.5% for a fresh fish, and no other fish's skins appear.
- **K4 Roll:** roll 20 times (Admin shells). Only this fish's skins come up, and the reel's filler cards are this fish's too.
- **K5 Old skins:** if your Studio save had shades that now belong to another fish's line, they turned into coral on join. Note your coral before and after the merge.
- **K6 Looks:** until the new skin bundle is imported, the new skins show as tints. Say whether any tint looks wrong (it's only the swatch).

## 8. Layout and performance

- **L1** PC 1280×720 and the iPhone 14 simulator: the LOG button sits with DAILY and SHOP (at the end of the HUD row on the phone), with nothing overlapping. The LOG window fits, and its tabs and rows read.
- **L2** The tide chip doesn't cover the boss bar, the biome banner or the safe-zone banner. The tide banner and a biome banner at once don't overlap.
- **L3 FPS:** in the Shallows during a forced Golden Hour (many golden fish with lights), log average and worst frame on PC and the phone.

## 9. Output

0 game errors.

## 10. Report

Write docs/playtests/2026-10-10-pc-pullback.md:
- R1–R4, C1–C3, T1–T3, B1–B4, W1–W3, K1–K6, L1–L3 and Output: pass/fail with the logged values
- screenshots: each rare look (close and far), the LOG's four tabs, each tide's banner and water, the skin unlock banner, the Catch of the Week banner, the Wardrobe for two fish
- your verdict: does this make you want to come back (for a tide, a bounty, a rare fish, the board)? What feels thin?
- any Output errors, verbatim

Commit and push to claude/core-systems.
