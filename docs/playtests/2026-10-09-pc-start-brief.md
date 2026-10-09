Apex Abyss — PC session brief: the start screen, eat vs bite hints, and the Trench report's fixes (2026-10-09)

Your Trench report (d9e470d) is merged into claude/world. Work in C:\Users\neos1\Desktop\apex-abyss on claude/core-systems.

Connor's asks this round:
> "I'd also like to add a start screen when players load into the server. Just hit any button to start and then it pushes them straight to the den and tutorial. Starter screen should have motion and some fish swimming by with maybe some kelp. Also needs to be clear mechanics on how to actually bite fish."

## 1. Merge and sync

1. git fetch origin claude/world
2. git merge origin/claude/world. It should fast-forward.
3. stylua --line-endings Windows src --glob "!**/Packages/**"
4. rojo serve on port 34873, connect, Play Solo. Expect "Server started" and "Client ready" with no errors.
   - From now on every Play Solo opens on the start screen: press any key to get in.

## 2. Start screen (keyboard, then controller, then the iPhone 14 simulator)

- **S1 Look and motion**
  - From the first frame: a blue underwater scene with light shafts, drifting specks and rising bubbles.
  - In it: kelp swaying on both sides, the Nibbler, 'Cuda and Pufferfish swimming past, a sardine school, minnows and a big shark shadow far off in hazy water.
  - The APEX ABYSS title springs in with a moving shine. Under it: "EAT · GROW · BECOME THE APEX", then three cards: EAT, BITE, BANK.
  - Screenshot it. Note:
    - any fish swimming backwards or sideways;
    - fish that glide with no tail motion (bones may not move inside a ViewportFrame);
    - parts floating apart;
    - anything off-screen or clipped on the phone.
- **S2 Prompt**
  - "LOADING THE REEF..." until your fish has spawned (at least 2.4 s).
  - Then it reads PRESS ANY KEY (keyboard), PRESS ANY BUTTON (controller) or TAP TO START (phone), and pulses.
  - The BITE card names your device's key: "Click or F", "RB or X", or "the BITE button".
- **S3 Dive in**
  - Any letter key, a mouse click, a controller button or a tap starts. Escape doesn't (it opens Roblox's menu).
  - The scene rushes forward, bubbles burst, and within about 1 s the game shows your fish in its den.
  - That first press must not also bite or dash.
  - While the screen is up the fish doesn't move: hold W, move the mouse, push the sticks.
  - The mouse is free while it's up and locks for looking after the dive.
  - Chat and the player list are hidden while it's up and come back after.
- **S4 After the dive**
  - New player (Admin: restart the tutorial, then rejoin): the tutorial panel pops with a sound, and the controls hint shows for 14 s.
  - Returning player with a Coral Garden harvest (Admin "Coral Garden: grow hours" 2, then rejoin): WELCOME BACK shows after the dive, not under the screen.
  - Daily reward waiting (Admin daily reset, then rejoin): the Daily panel opens about 1.5 s after the dive.
  - Respawning after being eaten never shows the start screen again.
- **S5 Performance:** FPS on the start screen, PC and phone, average and worst frame.

## 3. Eat vs bite hints

The rule: anything under ~70% of your length (prey, shrimp, starfish, small players) is swallowed just by swimming into it, like shells. Fish your size, AI predators and bosses need BITE.

- **H1 EAT:** leave the hub as a new player and eat nothing for 4 s.
  - A chip appears above the health bar: [EAT] "Swim into smaller fish, shrimp and starfish to swallow them. No button needed."
  - It goes once you've swallowed 3 things, and comes back at most 3 times a session.
- **H2 TOO BIG:** swim your mouth into a prey fish too big to swallow (a Snapper or Grouper at a low level). You should see [TOO BIG] "Too big to swallow yet...".
- **H3 BITE:** get your mouth near an AI predator (Barracuda or Reef Shark). You should see [BITE] "Press F / CLICK to bite..." (RB on a controller, BITE on a phone).
  - With 2 clients (Local Server): with player 2 at about your size (Admin set level), get close and check for [BITE].
  - With player 2 much bigger, check for [DANGER] "That fish is big enough to swallow you...".
- **H4 Wording:**
  - The tutorial's Eat step reads "Swim into 10 small fish, shrimp or starfish to swallow them".
  - The Haul card's hint out of the hub reads "Swim into smaller fish to swallow them".
  - The controls hint mentions eating by swimming in and biting fish your size, on all three devices. Check it still fits on one line on PC and two on the phone.
- **H5 Layout:** the hint chip doesn't cover the Haul card, health bar or boost bar, on PC 1280×720 or the phone, and never shows in the hub or under a menu.

## 4. The Trench report's fixes

- **T1 No self-dimming:** at the Trench bottom, wear Aurora, Nebula, Ghost and Abyss Ink in turn. Log the Lamp's brightness on your own client:
  - Aurora 2.60
  - Nebula ≈ 3.81 (3.2 × a 1.19 colour boost)
  - Ghost 3.40
  - Abyss Ink ≈ 5.17 (3.4 × 1.52)
  - Void ≈ 5.12
  - Magma 1.90
- **T2 Colour vs strength:** from the same spot and view as last time, re-rank by eye: Magma (Epic) < Aurora (Legendary) < Nebula (Mythic) ≤ Abyss Ink / Ghost (Trophy). Say which still feel out of order.
- **T3 Common glowing shades:** Ember, Ink and Neon Tetra are the Common ones. Your report missed them; the Admin "Every shade" gives them.
  - Wear each at the Trench bottom: Lamp range 18, brightness 1.0.
  - Colours: Ember orange, Ink pale blue, Tetra cyan.
  - The Deep Lantern beats them.
- **T4 Phone offer card** (iPhone 14): it now sizes itself into the gap between the HUD button row and the health bar.
  - Measure the bank card and the eaten card. Expect ≥ 3 px clear above (HUD row) and below (health bar).
  - Check the title, line and buttons all fit inside it.
- **T5 Phone banners with a boss up:** summon the Megalodon (`_G.ApexBoss.summon()`).
  - Leave the hub: LEAVING THE SAFE ZONE should sit below the boss bar.
  - Enter the Open Blue: its title should sit below the boss bar.
  - Also with the countdown up (before it rises).
- **T6 Garden footing:** at Nook and Burrow, the footing goes only as deep as the floor drops, with rubble stones on the low side, and no gap from any side. Screenshot it from the low side.
- **T7 Output:** 0 game errors.

## 5. Before going live (Connor's call; just report the status)

- The place isn't published to universe 10769954850 yet.
- A pass purchase still needs a non-owner account.

## 6. Report

Write docs/playtests/2026-10-09-pc-start.md:
- S1–S5, H1–H5 and T1–T7 pass/fail, with the logged values
- screenshots: the start screen (PC and phone), the dive mid-way, each hint chip, the T2 re-rank
- any Output errors, verbatim

Commit and push to claude/core-systems.
