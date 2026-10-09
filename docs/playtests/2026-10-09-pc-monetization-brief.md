Apex Abyss — PC session brief: monetization, daily streak, Coral Garden (2026-10-09)

The C1–C8 report is in (thanks). This round has two parts: retest the three fixes from that report (section 2, R1–R3), then monetization, the daily streak and the Coral Garden (A–F). Work in C:\Users\neos1\Desktop\apex-abyss on claude/core-systems. Read CLAUDE.md (the "Monetization", "Daily login streak" and "AFK income: the Coral Garden" entries) and GDD §9–10 before starting.

## 1. Merge and sync

1. git fetch origin claude/world
2. git merge origin/claude/world  (it fast-forwards: claude/world already contains your 57b198e report, then "Monetization, daily login streak and the Coral Garden" and the fix round for C2/C4/C6)
3. stylua --line-endings Windows src --glob "!**/Packages/**"
4. rojo serve on port 34873, connect the plugin, Play Solo. The Output must show "[ApexAbyss] Server started" and "Client ready" with no errors.

Every pass and product id is 0 for now. In Studio the Shop lists them greyed out, and the cards still appear. The admin panel's new MONETIZATION (NO ROBUX) and DAILY STREAK · CORAL GARDEN sections grant passes and run product effects without Robux.

## 2. Test in Studio (keyboard, then Controller Emulator, then Device Simulator phone)

R. Retest of the 2026-10-09 fixes (do these first)
- R1 Vents (C2): every chimney's orange VentGlow ball now sits on top of its lava cap, found by raycast.
  - Count how many of the 26 are inside terrain (occupancy > 0.5); expect 0.
  - From 45 and 64 studs at a −540 basin, the orange throat shows. Screenshot it.
- R2 Megalodon flank bites (C6): the push-out now sets the fish back onto the body's surface and only removes its speed into the body; it adds no push. The server also allows for the boss's own movement.
  - Place the fish 20 studs off the axis. Log its distance at 0.1/0.2/0.3/0.4 s: expect ~24–26 and no climbing to 37–42.
  - Press F against the flank 12 times while it swims; count the hits (expect most).
  - No jitter, and the fish never ends up inside it.
- R3 Roll cards (C4):
  - About 3 s after spawning, a 160×120 nearly invisible viewport in the bottom-right corner draws every shade card once, then goes away.
  - Wait 5 s after spawning, then roll 10+ times: every shade card should be textured from its first frame. No empty discs and no white fish. Note any you see, with the time from roll start.
  - Roll immediately after a species switch too: a card may sit faint for up to 1.5 s, but it must never show white.
  - Part cards (Sail Fin, Narwhal Horn, Sawblade Snout, Jaw if it comes up) and variant cards show the whole fish side-on, not a close-up. They pass through the reel as filler cards. Screenshot what you get.

Use Admin → "Finish the tutorial" first. The offers and the auto-opening Daily panel only start after the tutorial.

A. Daily streak
- On spawning, the Daily panel opens by itself once: seven tiles, today gold-outlined with TODAY, and a CLAIM button.
- Claim it. Expect a toast "Day N reward: ..." and the wallet to go up. The tile reads ✓ CLAIMED, the footer counts down to tomorrow, and DAILY (beside the wallet) stops breathing.
- Admin "Daily: claim again today" → the next day becomes claimable. Admin "Daily: set the streak" 6 → Day 7 (wider tile: 2,500 coral, 100 shells, a Captain's map). Claim it and check the map lands in MAPS.
- Set the streak to 7 and claim → Day 1 again with "week 2 bonus +25%" and 375 coral.
- Admin "Daily: miss a day" → the subtitle says the streak starts again, and Day 1 is claimable.
- Controller: CLAIM is selected when the panel opens, and B closes it.

B. Coral Garden (AFK income)
- In your den, under the trophy plaques, there's a round stone bed with sand, a glow-colored rim and small coral buds. A sign over it reads CORAL GARDEN, the amount, and "Resting here: ×2 growth, collected every minute".
- Rest in the den for 2 minutes. Small "+N CORAL" pops rise over the garden about every minute (Nook: ~2 coral a minute while resting).
- Admin "Coral Garden: grow hours" 8. Within ~5 s the corals grow full, glow and sparkle, then it collects: pops, a WELCOME BACK banner ("Your Coral Garden grew while you were away (8h): +480 coral · +32 shells"), and the wallet goes up.
- Swim out, Admin grow 3 h, swim back in. It collects on entering (pops, no banner below 10 min away).
- Upgrade the den to a Burrow (Admin coral). The garden moves back with the back wall, still under the plaques, not clipping rock. The den menu's Coral Garden row shows 100 coral / 6 shells an hour.
- Check the Hall and Grotto too. The pit opens under the floor there, so make sure the bed doesn't float over it or sink into the wall.
- Screenshot the garden empty, half-full and full.

C. Shop
- SHOP (gold, beside the wallet) and the controller's View button open it. Rows:
  - Daily reward
  - BOOSTS: Second Chance, Server Frenzy, Shell Pouch, Shell Chest (ODDS button on the shell rows opens the roll odds)
  - GAME PASSES: ×2 Mass, VIP, Den Expansion, Deep Garden
  - FREE PERKS: Roblox Premium
- In Studio everything with id 0 is greyed out.
- Admin "Test as" Restricted ON → the shell packs vanish. Restricted OFF → they're back.

D. Passes (Admin "Grant a pass" / "Take a pass away")
- ×2 Mass: a "×2 MASS" chip under SHOP/DAILY, eat pops show double, the Haul grows twice as fast. A predator kill toast shows the doubled kg.
- VIP: use Local Server with 2 players (Test tab → Clients and Servers). The other player sees a gold "VIP" before your name on your nametag.
- Den Expansion: the den menu lists spots X1–X4 (two floor at the back corners, two wall by the doorway). Place an item in each.
  - Check they don't clip the Haul Pool, the garden, the trophy wall or the rock, at Nook and at Grotto.
  - Take the pass away: those items disappear and the spots show the pass row again.
- Deep Garden: the den menu shows 16 h and ×1.5 rates. "Grow hours" 16 fills it.

E. Products (Admin "Run a product's effect")
- Server Frenzy: an announcement to everyone, a "SERVER FRENZY ×2 · 14:59" chip counting down, and doubled eat pops. With ×2 Mass too it reads "×4 GROWTH".
- Shell Pouch / Shell Chest: +100 / +600 shells and a toast.
- Second Chance with no recent death: "+1 charm" toast. Check the Tidecharm Trader shows FULL when holding 2+.
- Double Haul: bank anything, then run Double Haul (Small). Expect the "HAUL DOUBLED · +X" banner, mass and level up.
  - Run it again: "already doubled ... Second Chance charm instead".

F. Offer cards
- Admin "Add Haul" of about half your mass, then bank. After the BANKED banner, a card shows: "DOUBLE THIS HAUL?", "+X more · N more levels", and DOUBLE IT · R$ 19 / SKIP. There's no timer.
  - The cursor is free while it's up. DOUBLE IT shows a toast that it isn't created yet (id 0).
  - Check that each of these closes it: SKIP; B on a controller; swimming out of the hub.
  - Mouse-look comes back afterwards.
- A tiny bank (well under 30% of your mass) shows no card.
- Add a big Haul, leave the hub, then Admin "Get eaten". After respawning, a "GET YOUR HAUL BACK?" card shows "You lost X".
  - Within 3 minutes, Admin "Run a product's effect" → Second Chance. Expect "your X Haul is back" and the Haul bar refilled.
  - Get eaten again with a tiny Haul: no card.
- Phone (Device Simulator):
  - The cards' buttons are tappable.
  - SHOP/DAILY and the growth chip don't overlap the level card, wallet, HUD row, tutorial panel, boss bar, treasure sonar or depth gauge.
  - Same check at 1280×720 on PC.

## 3. Creator Hub (Connor's account, in the browser)

Do this only after section 2 passes.

1. Open the experience → Monetization.
2. Create the passes and products below with exactly these names, prices and descriptions (they're also in src/shared/Config/Monetization.luau).
   - Icons can wait: any clean 512×512 image or the default is fine for now. Say so in the report and I'll make proper icons.
3. Paste each id into the matching `id = 0` in Config/Monetization.luau.

Passes:
- ×2 Mass — 399 — "Everything you eat counts double toward your Haul. Grow twice as fast, forever."
- VIP — 299 — "A gold VIP tag over your fish and +10% coral from everything you earn."
- Den Expansion — 149 — "Four more furniture spots in your den (two on the floor, two on the walls), at any den level."
- Deep Garden — 129 — "Your den's Coral Garden grows 50% faster and holds 16 hours instead of 8."

Developer products:
- Second Chance — 39
- Server Frenzy — 99
- Double Haul — 19
- Double Haul (Big) — 49
- Double Haul (Huge) — 99
- Shell Pouch — 49
- Shell Chest — 199
- Double Haul (ad) — 5. This is the rewarded-ad reward. If Creator Hub has a rewarded video ads setting for the experience, turn it on; if not, skip it, and the WATCH AD button simply never shows.

Then in Studio, Play Solo and buy each one for real. Studio purchases are test purchases and cost nothing.
- Each pass: the "Thanks! X is yours." toast and its effect, both right away and after rejoining.
- Double Haul from the bank card.
- Second Chance from the eaten card, and from the Shop with no recent death (a charm).
- Server Frenzy and Shell Pouch from the Shop.

Check the Output for "[MonetizationService]" warnings. Commit the ids ("Monetization: Creator Hub ids") and push claude/core-systems.

Don't publish the place until I've reviewed the report.

## 4. Report

Write docs/playtests/2026-10-09-pc-monetization.md:
- R1–R3, each item A–F and section 3: pass/fail
- screenshots of the garden (empty/half/full), the Daily panel, the Shop, both cards and the phone layout
- any Output errors, verbatim
- the ids you pasted

Commit and push it to claude/core-systems, then tell Connor it's ready to send back to the cloud session.
