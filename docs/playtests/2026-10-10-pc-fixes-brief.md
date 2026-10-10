Apex Abyss — PC session brief: walls, coral, kelp, food and the cursor (2026-10-10)

Do this short round first, then the pull-back round (docs/playtests/2026-10-10-pc-pullback-brief.md). Work in C:\Users\neos1\Desktop\apex-abyss on claude/core-systems.

Connor's asks:
> "Cant get this shrimp because of an invisible wall. And a lot of the coral i can go right through. The kelp and a lot of other items are phasing and glitching. needs a lot more smaller fish and starter food laying around. far too scarce"
> "also need a way to pull up the cursor since the cursor is tied to swimming there is no way to click on ui panels or screens"

What changed:

- **Invisible walls.** Each boulder's placeholder was a tilted box left collidable round the rounder rock model. Now the rock model itself is solid (and keeps the camera out), and the box doesn't collide (`Props.dress` `solid`).
- **Coral.** Brain coral, staghorn, fan coral and tube sponges are solid. Anemones stay soft to swim through, and the camera passes through all coral.
- **Kelp.** Kelp is still soft, but a plant now leans away from any fish swimming through it, far enough to clear the fish, then springs back. A plant the camera is inside fades out instead of flickering across the lens.
- **Food.** Shrimp, starfish and medkelp go from 420 spots over the whole shelf to about 1,680, thickest near the hub: about one every 20 studs within 330 of it.
  - No food is placed inside or under a rock or coral.
  - Minnows go from 14 schools at 20–120 studs up to 42 schools, 22 of them near the hub and only 4–45 studs over the sand. Sardines go from 14 schools to 24, the inner ones low too.
  - Prey further than 160 studs from the camera keep swimming their paths without the spine wave, so the extra fish cost less.
- **Cursor.** Tap **Alt** (or **M**, because Studio's own window can take an Alt tap) to free the cursor for the HUD buttons and panels.
  - A chip at the top says CURSOR FREE.
  - Tap again, or click the game itself (not a button), to lock it and swim. That click doesn't bite.
  - Holding Alt still frees it only while held.
  - The controls hint now ends "· Alt or M frees the cursor".

## 1. Merge and sync

1. git fetch origin claude/world, then git merge origin/claude/world.
2. stylua --line-endings Windows src --glob "!**/Packages/**"
3. rojo serve on port 34873, connect, Play Solo. Expect "Server started" and "Client ready", no errors.

## 2. Checks (keyboard, a fresh Nibbler, then LV 20+)

- **F1 Rocks.** In the Kelp Shallows near the hub, swim slowly into 10 boulders from every side, the top included.
  - The fish stops against the rock you can see, never short of it, and never passes into it.
  - No food sits under or against a rock where you can't reach it.
  - From the command bar, print each `ReplicatedStorage.WorldProps` boulder and coral MeshPart's `CollisionFidelity` and log them. If any rock still has a gap, name it and its fidelity.
- **F2 Coral.** In a coral garden (Kelp Shallows near the hub, and the Reef):
  - Brain, staghorn, fan coral and tube sponges stop your fish.
  - Anemones let it through.
  - The camera never snaps on coral.
- **F3 Kelp.** Swim through a kelp forest at different heights.
  - Plants lean out of your way and spring back over about a second.
  - Swing the camera inside a plant: it fades instead of flickering.
  - A second client watching sees the kelp lean for your fish too.
  - Log the FPS in a forest.
- **F4 Food.** Spawn as a fresh Nibbler and swim 30 s in a ring 150–330 studs from the hub, near the floor.
  - Count the shrimp and starfish you pass. Expect one roughly every 20 studs.
  - Count the minnow schools in view. Expect one or more most of the time, low over the sand.
  - Note how long the tutorial's "eat 10" step takes now.
  - Log the average and worst frame on PC and in the iPhone 14 simulator, near the hub and in the forest.
- **F5 Cursor.**
  - Tap Alt: the cursor shows, with the CURSOR FREE chip, and WASD still swims.
  - Click LOG, DAILY, SHOP, WARDROBE, FISH, MAPS and ODDS. Each opens.
  - Close the menu: the cursor stays free.
  - Click the water (not a button): the cursor locks, the chip goes, and there's no bite.
  - Repeat with M.
  - Hold Alt for 2 s, then let go: the cursor locks again.
  - Note whether Studio's Alt ever grabs focus (so M is the way in Studio).
  - The controls hint at join ends "· Alt or M frees the cursor".
- **F6 Output.** 0 game errors.

## 3. Report

Write docs/playtests/2026-10-10-pc-fixes.md:
- F1–F6: pass or fail, with the logged values (CollisionFidelity per prop, food counts, school counts, FPS).
- Screenshots: a boulder up close with the fish against it, a coral garden, a kelp plant leaning away, the CURSOR FREE chip, the seabed near the hub with food.

Commit and push to claude/core-systems, then go on to the pull-back brief.
