Apex Abyss — PC session brief: the 2026-10-09 fix round

Your monetization report (55835d0) and your five fixes are merged into claude/world. This round:
- the R1–R3 retests you didn't get to (you merged before db9d0aa landed);
- the fixes for your report's builder list (G1–G7).

Work in C:\Users\neos1\Desktop\apex-abyss on claude/core-systems.

## 1. Merge and sync

1. git fetch origin claude/world
2. git merge origin/claude/world. It should fast-forward or be a clean merge; CLAUDE.md was hand-merged on this side.
3. stylua --line-endings Windows src --glob "!**/Packages/**"
4. rojo serve on port 34873, connect, Play Solo. Expect "Server started" and "Client ready" with no errors.
   - The once-a-minute AdService warning should be gone: Ads.luau no longer polls in Studio.

## 2. Retests from the last round (R1–R3)

- **R1 Vents:**
  - Each chimney's orange VentGlow ball now sits on its lava cap's top, found by raycast.
  - Count how many of the 26 are inside terrain (occupancy > 0.5). Expect 0.
  - From 45 and 64 studs at a −540 basin, the orange throat shows. Screenshot it.
- **R2 Megalodon flank bites:**
  - The push-out now puts the fish back on the body's surface and removes only its speed into the body; it adds no push. The server also allows for the boss's own movement.
  - Place the fish 20 studs off the axis and log its distance at 0.1/0.2/0.3/0.4 s. Expect ~24–26, not 37–42.
  - Press F against the flank 12 times while it swims. Count the hits; expect most of them.
  - Check for no jitter and no ending up inside it.
- **R3 Roll cards:**
  - About 3 s after spawning, a nearly invisible 160×120 viewport in the bottom-right corner draws every shade card once, then goes away.
  - Wait 5 s after spawning, then roll 10+ times. Every shade card should be textured from its first frame: no empty discs, no white fish. Note any exceptions with the time from roll start.
  - Roll right after a species switch: a card may stay faint for up to 1.5 s, but it must never show white.
  - Part and variant cards (Sail Fin, Narwhal Horn, Sawblade Snout, Hammerhead) should show the whole fish side-on, not a close-up. They come up as filler cards in the reel.

## 3. This round's fixes (G1–G7)

- **G1 Coral Garden bed on the floor.** Half a second after the den is built, it sits on the Terrain floor found by raycast (the highest of 5 rays, minus 0.15).
  - At Nook, Burrow, Hall and Grotto, measure the bed's top against the floor around it. The bed should be visible, with its stone rim resting on the floor and not floating more than ~1 stud.
  - Upgrade a level while watching: it snaps onto the new floor within about 0.5 s.
  - Screenshot each level.
- **G2 Den Expansion X3/X4:** moved to (±10.3, 8, 6), between the W spots and the doorway.
  - Put a Banner in X4 and X3 at Nook and Grotto. Check the centre voxel occupancy and that neither clips the rock nor W1/W2's items.
- **G3 Phone layout** (iPhone 14 in the Device Simulator):
  - DAILY and SHOP sit at the end of the HUD button row (after FISH/MAPS); on PC they stay beside the wallet.
  - The growth note (×2 MASS, FRENZY ×2 · mm:ss, ×4 GROWTH · mm:ss) is now inside the Haul card's top-right corner on every platform. Check that it doesn't cover the HAUL title or value.
  - Show the TOO DANGEROUS and TUTORIAL COMPLETE banners: nothing should run across DAILY/SHOP.
  - The treasure sonar sits left of the biome chip, not on it (follow a map in the Open Blue).
  - The HEAL button shows "HEAL ×N", or "HEAL 12s" while cooling (dimmed). There's no Kelp Wraps chip on phones any more, so nothing crosses BITE.
  - The YOUR DEN / SHOP stall button sits higher (clear of HEAL) and hides while an offer card is open. It comes back when the card closes.
  - PC 1280×720: the Kelp Wraps chip, sonar and Shop buttons are unchanged.
- **G4 Daily panel:**
  - Claiming shows "Day N claimed: 300 coral" in the footer (gold, 4 s) with the Bank sound. No toast should cover the footer.
  - Before the first ever claim, the subtitle reads "Claim Day 1 to start your streak".
  - Day 7 reads "2,500 coral" with a comma.
- **G5 Tidecharm Trader:** holding more Second Chances than its cap now reads "Have 2", not "Have 2 / 1".
- **G6 Regression:**
  - One bank card and one eaten card on keyboard, controller and phone.
  - Shop and Daily on the controller (they open on their first button).
  - Coral Garden payouts and WELCOME BACK.
  - VIP nametag.
- **G7 Output:** 0 game errors and no AdService warning.

## 4. Before going live (Connor decides; just list status)

- The place file isn't published to universe 10769954850 yet (use "Update existing experience"). Don't publish without Connor's go-ahead.
- A pass purchase still needs a non-owner account. Note it as open; don't use another account yourself.
- Rewarded ads stay ineligible until the experience is public with 2K monthly users.

## 5. Report

Write docs/playtests/2026-10-09-pc-fixes.md:
- R1–R3 and G1–G7 pass/fail
- screenshots: the garden at all four levels, the X3/X4 banners, the phone HUD with banners, the sonar and HEAL, the Daily footer
- any Output errors, verbatim

Commit and push to claude/core-systems.
