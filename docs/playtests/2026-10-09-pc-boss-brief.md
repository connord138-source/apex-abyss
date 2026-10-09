Apex Abyss — PC session brief: the Megalodon out of the deep blue, fights you can see, and the store page (2026-10-09)

Your start-screen report (8911301) and your five fixes are merged into claude/world (c2754ec or later). Work in C:\Users\neos1\Desktop\apex-abyss on claude/core-systems.

Connor's direction this round:
> "I want the megalodon to be a figure that sort of appears from the deep blue. It should be an eerie figure but is not for deepest darkest ocean just deep blue where there's no ground or anything just open ocean. Adds to the horror element. He should roam around the deep blue but the deep blue needs to be large enough that he is unseen until he slowly fades into view of players. Once he is upon them he needs to be seeable to be fightable. The deepest dark is for the giant squid and even this is a massive reason why the abyss can't be completely black — how will anyone fight anything in pitch black or low visibility let alone a boss."

What changed:
- **Open water.**
  - The Megalodon roams 170–470 studs over the Open Blue floor (about y −260 to +40).
  - The Open Blue's grouper, snapper, barracuda and shark schools and its Reef Sharks keep to 140–430.
  - The 150–280-stud pinnacles are now 37–70-stud spires on the floor below.
- **It fades in** (Config/Bosses `sight`, distances from its body, not its middle):
  - Unseen beyond 280 studs.
  - It materialises as it closes and is solid by 110.
  - Its tag and boss bar show only once it appears.
- **Felt before it's seen.** From 460 studs:
  - The screen's edges darken and pulse with a heartbeat, and the water turns cold and grey.
  - A warning reads SOMETHING CIRCLES IN THE BLUE, with no arrow and no distance.
  - The dread no longer darkens the picture at all.
  - Once it shows, the warning reads MEGALODON NEARBY · distance, with the arrow.
- **Fights you can see.**
  - Within 190 studs of a boss the water clears: exposure up to +0.35, haze ×0.78.
  - In the dark, the dark lifts by 60%.
  - A faint cool rim keeps the Megalodon's outline readable.
  - The Giant Squid doesn't fade (the dark is its own), but gets the same fight light.
- **The Trench:**
  - No-light ambient (32, 46, 66), plankton level (44, 74, 88): a step brighter.
  - Every hunter shows a faint eerie rim in the dark.
- **Lights from your re-rank:**
  - The deep-colour boost is capped at ×1.2.
  - Aurora gets ×1.15 and Ghost ×1.25 of their own.
  - Common shades: range 24, brightness 1.3. Trophy 3.6.
  - Ink is blue (80, 150, 255) and Neon Tetra cyan (30, 245, 230).
- **Start screen:** the device is read when the screen opens and changes only on real input of another kind, so the phone should read TAP TO START.
- **Store art:** thumbnails 8–10 are made from your captures. Thumbnail 9 is provisional; see §6.

## 1. Merge and sync

1. git fetch origin claude/world, then git merge origin/claude/world (it should fast-forward).
2. stylua --line-endings Windows src --glob "!**/Packages/**"
3. rojo serve on port 34873, connect, Play Solo. Expect "Server started" and "Client ready", no errors.

## 2. The Megalodon (keyboard first; Local Server with 2 clients for M3)

Summon it with the Admin panel's SUMMON (the command bar's `_G` doesn't reach the game here). Teleport to the Open Blue.

- **M1 Open water**
  - Log its Y a few times as it patrols. Expect 170–470 over the floor (about −260 to +40).
  - From its depth, looking down: no floor or spires in view, just blue.
  - The schools and Reef Sharks are mid-water.
  - Screenshot the open water.
- **M2 Emergence.** Start ~600 studs away and close in slowly, or let it come to you. Log the distance to its body at each point.
  - ~460: the warning reads SOMETHING CIRCLES IN THE BLUE, with no arrow and no distance.
    - The screen's edges darken and pulse; the centre doesn't get darker.
    - Log Lighting.ExposureCompensation and the OceanGrade's Brightness before the dread and at its height. Expect neither to go down.
  - ~280: the body starts to appear out of the blue (faintly see-through).
  - ~110: solid. The tag and the boss bar appear once it shows; the warning becomes MEGALODON NEARBY · distance, with the arrow.
  - Screenshots at about 400, 250, 150 and 80 studs.
  - Say whether it reads as "an eerie figure that fades into view", and whether the fade distances feel right (too early or late, too fast or slow).
- **M3 Fight visibility**
  - Within ~190 studs the water clears: log ExposureCompensation (up to +0.35 more) and the Atmosphere density (×0.78).
  - A faint pale-blue rim shows its outline.
  - Bite it for a minute with a second client nearby. Can both of you see it clearly the whole time, from in front, beside and behind?
  - Compare against last round's near-black (`30-megalodon-player-view-dread.jpg`).
- **M4 Leaving:**
  - Swim away: it fades back out as the distance grows.
  - Dismiss it with Admin while it's out of sight: it must never flash into view.
- **M5 Last stand into the Trench:**
  - Hurt it below 25% (Admin) and follow it down.
  - In the dark near it, the dark lifts (log Lighting.Ambient near it and 300 studs away), and it stays visible to fight.

## 3. The Giant Squid and the Trench

- **Q1 The no-light Trench.** At last round's T1 spot (−133, −890, 1167) with no lamp:
  - Log Ambient. Expect about (44, 74, 88) at the bottom.
  - Say how much you can see now (it was ~10%).
  - A Barracuda or Reef Shark in the dark should show a faint rim.
- **Q2 The squid fight.** SUMMON the Giant Squid (the next in the rotation, or dismiss the Megalodon first) and find it in the Trench.
  - From 300 studs to 50: the dark lifts as you close in (log Ambient and Lighting.Brightness at 300, 150 and 60 studs).
  - The squid is clearly visible, with its violet glow and rim.
  - Fight it for a minute: grabs, ink (the ink still blinds you inside the cloud) and the jet.
  - Screenshots at 150 and 60 studs.
- **Q3 Lights by rarity, re-ranked.** Same spot and camera as last round's T2. Log each Lamp's brightness and colour, and check the character's `Shade` attribute matches what you're wearing:

  | Shade | Range | Brightness | Colour |
  |---|---|---|---|
  | Ember | 24 | ≈1.3 | orange |
  | Ink | 24 | ≈1.3 | blue (80, 150, 255) |
  | Neon Tetra | 24 | ≈1.3 | cyan (30, 245, 230) |
  | Magma | 36 | 1.90 | |
  | Aurora | 48 | ≈2.99 | |
  | Nebula | 60 | ≈3.80 | |
  | Void | 60 | ≈3.84 | |
  | Abyss Ink | 60 | ≈4.32 | |
  | Ghost | 60 | ≈4.50 | |

  - Rank by eye again. The aim is Common < Rare < Magma < Aurora < Nebula/Void < Abyss Ink/Ghost.

## 4. Start screen on the phone

- **S2:** iPhone 14 simulator, a fresh session. The prompt reads TAP TO START and stays so after the simulator's keyboard flag turns on (~2 s in); the BITE card reads "the BITE button".
- A key press or a click changes it to PRESS ANY KEY, and a controller button to PRESS ANY BUTTON.

## 5. Output

0 game errors.

## 6. Store page

Connor is signing in to Roblox in your browser pane. Once he has, and once the tests above pass:

1. **Retake `marketing/raw/shot_9_megalodon.png`** at 1918×1080, as last time (HUD, nametags and CoreGui hidden):
   - the real Megalodon in open water, close and lit by the fight light;
   - with the second client's real fish beside it if you can, otherwise staged copies as before.
   - If Python with Pillow is installed, run `python tools/marketing/compose.py shots` to remake `marketing/thumb_9_megalodon.jpg`. Otherwise leave it, and the cloud session will remake it.
   - Commit the capture (and the thumbnail if you made it).
2. **Publish again** to the existing private experience "Apex Abyss" (universe 10769954850, place 83646578075996), with Update existing experience. Keep it private.
3. **In Creator Hub** (the experience's page):
   1. Read and report the published version number.
   2. Upload `marketing/icon_512.png` as the icon. Wait until moderation passes before the next step.
   3. Upload the thumbnails in order: `thumb_1_eat.jpg` … `thumb_10_reveal.jpg`. If thumbnail 9 wasn't remade, upload 1–8 and 10 and leave 9 for later.
   4. Paste the description from docs/STORE_PAGE.md (the block under "Description").
   5. Report anything moderation rejects. Never re-upload a rejected image.
- Don't make the experience public, and never use another account.

## 7. Report

Write docs/playtests/2026-10-09-pc-boss.md:
- M1–M5, Q1–Q3, S2 and Output: pass/fail with the logged values
- screenshots: the emergence sequence (400 / 250 / 150 / 80), the fight from two angles, the squid at 150 and 60, the light re-rank
- your verdict on the feel: does the Megalodon read as an eerie figure fading out of the deep blue, and can you fight both bosses comfortably?
- the published version, and what went up on the store page
- any Output errors, verbatim

Commit and push to claude/core-systems.
