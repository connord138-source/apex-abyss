# Playtest — Windows PC, 2026-10-09: monetization, daily streak, Coral Garden (claude/world e4f8477)

- **Build:** `claude/core-systems` merged `origin/claude/world` (`875862b`, after the C1–C8 report `57b198e`), plus my fixes below.
- **Where:** Connor's PC, Studio, Rojo 7.7.0 on port 34873.
  - Play Solo on keyboard, Controller Emulator (Generic Gamepad), Device Simulator (iPhone 14, 844×390, and HD 720 1280×720).
  - Local Server with 2 clients for VIP.
- **Screenshots:** `C:\Users\neos1\Desktop\apex-abyss-playtest-shots\2026-10-09-monetization\` (74 shots named by section, also in `apex-abyss-playtest-2026-10-09-monetization.zip`).
- **Icons:** none uploaded. Every pass and product uses Roblox's default image, ready for proper icons.

## The short version

| # | Item | Result |
|---|------|--------|
| 1 | Merge and sync | **PASS**. Merge `875862b`, StyLua clean. `[ApexAbyss] Server started` and `Client ready`, no errors. |
| A | Daily streak | **PASS** on keyboard and phone. **Controller: CLAIM wasn't selected** (X was): fixed `a18438c`. B closes it. |
| B | Coral Garden | **Logic PASS**: rates, resting ×2, a payout every minute, collect on entering, WELCOME BACK, den-level rates, Deep Garden. **Visuals FAIL: the bed is under the den floor at every level** (0.6 studs at Nook, 1.7–4.6 at Burrow/Hall/Grotto). The sign and pops were broken too; fixed `88a4f54`. |
| C | Shop | **PASS**: rows, greyed id-0 items, ODDS, Restricted on/off, View button on controller. |
| D | Passes | **PASS**: ×2 Mass, VIP (2 players), Deep Garden. **Den Expansion PASS**, except the X4 banner's edge sinks into the doorway rock at Nook and Grotto. |
| E | Products | **PASS**: Server Frenzy, shell packs, Second Chance charm with the trader showing FULL, Double Haul and "already doubled". |
| F | Offer cards | **PASS** on keyboard, controller and phone. Two bugs fixed: the Daily panel covered the eaten card (`a7c5b40`), and closing a menu over a card locked the mouse (`901be45`). The phone layout is clear for everything on the brief's list. |
| 3 | Creator Hub | **Done**, see the details below. |

Section 3 in brief:
- There was no Apex Abyss experience, so I created a private one from an empty baseplate. The place file is not published.
- The 4 passes and 8 products are created at the brief's prices, and the ids are committed (`62a4e9c`).
- Rewarded video ads are **ineligible**, so that step is skipped.
- Real Studio purchases of all 5 product flows complete and pay out.
- **Passes can't be bought on Connor's account:** the creator owns them automatically.

## 1. Merge and sync

- `git merge origin/claude/world` → `875862b`. StyLua clean.
- Rojo connected; Play Solo:
  - `[ProfileStore]: Roblox API services unavailable - data will not be saved - Server - ProfileStore:2015`
  - `[ApexAbyss] Server started - Server - Server:52`
  - `[ApexAbyss] Client ready - Client - Client:66`

## A. Daily streak

- **Auto-open:** after Admin FINISH it doesn't open at once. It opens 3 s after the next spawn, once a session (shot 02).
  - Seven tiles, Day 1 gold-outlined with TODAY, a wider Day 7, and CLAIM.
- **Claim:** toast "Day 1 reward: 300 coral", coral 502 → 802 (shot 03).
  - The tile reads ✓ CLAIMED, the footer says "Come back in 19h 52m for Day 2", and DAILY stops glowing.
- **Claim again today:** Day 2 becomes TODAY (shot 04).
- **Streak 6:** Day 7 becomes TODAY (shot 05).
  - Claimed: "Day 7 reward: 2500 coral, 100 shells, a treasure map", plus "You found a Captain's Treasure Map! Open MAPS to see it". Coral 802 → 3,302, and ROLL ×3 (shot 06).
  - MAPS lists "Captain's Treasure Map · About 662 ft north-east of the hub, where the sand meets the open blue" (shot 07).
- **Streak 7:** "Streak: 8 days · best 7 · week 2 bonus +25%". Day 1 = 375 coral, Day 7 = 3,125 coral and 125 shells (shot 08).
  - Claimed: "Day 8 reward: 375 coral", coral 3,304 → 3,679 (shot 09).
- **Miss a day:** "You missed a day, so the streak starts again at Day 1", with Day 1 claimable (shot 10).
- **Controller:** **FAIL, then fixed** (`a18438c`).
  - The panel opened with the window's **X** selected, not CLAIM (shot 11). `MenuController.selectFirst` takes the first button, and `Ui.window` builds X first, so A closed the panel. This affected every menu on a controller.
  - After the fix, Daily opens on CLAIM (`Menus.Window.Content.Claim`, shot 12) and the Shop on its Daily CLAIM.
  - B (`ButtonB`) closes the panel.
- **Phone:** tapping CLAIM works.
- **Nits:**
  - Before the first claim the subtitle reads "Streak: 1 day · best 0".
  - The Day 7 toast says "2500 coral" without the comma used elsewhere ("2,500").

## B. Coral Garden

### Logic: PASS

- **Resting in the Nook:** a payout `{"coral":2,"shells":0}` every minute (00:18:03.6, 00:19:03.7, 00:20:03.9, 00:21:04.0). About 2 coral a minute, as specified.
- **Grow 8 h in the den:** collected within about 1 s.
  - Payout `{"coral":480,"away":28800,"shells":32}`.
  - WELCOME BACK "Your Coral Garden grew while you were away (8h): +480 coral · +32 shells" (shot 17).
  - Wallet 513 → 993 coral, 0 → 32 shells.
- **Swim out, grow 3 h, swim back:** collects on entering (`{"coral":181,"away":10800,"shells":12}`), with pops.
  - A WELCOME BACK banner showed anyway. That's because the admin command's `GardenService.fastForward` counts the hours as time away.
  - **A real 70-second trip out and back** collects `{"coral":1,"shells":0}` with a pop and **no banner**. This is what the brief wanted to see.
- **The sign:** grows "0 coral → 181 · 12 → 241 · 16 → 480 · 32", and when full reads "Full: swim in to collect".
  - The corals grow, glow and fill in (shots 18–21: 3 h, 4 h = half, 8 h = full).
- **Den menu rates:**

  | Level | Coral / shells an hour | Holds |
  |---|---|---|
  | Nook | 60 / 4 | 0 / 480 |
  | Burrow | 100 / 6 | 800 |
  | Hall | 160 / 9 | 1,280 |
  | Grotto | 250 / 12 | 2,000 |
  | Grotto + Deep Garden | 375 / 18 | 16 h, 6,000 |

### Visuals: FAIL (for the builder)

- **The bed sits under the den floor at every level.** Its top is always y 5.30, but the terrain floor over it is:
  - Nook: 5.16–6.00 (centre 5.87)
  - Burrow: 7.23–9.91
  - Hall and Grotto: 7.02–7.22
- **What a player sees:**
  - In the Nook, only the polyp tips and grown corals poke through the floor (shots 13, 16, 18–21).
  - At Burrow and up, the bed isn't visible at all (shots 25–27).
  - Raised 1.5 studs (test only, session-local), it looks right: a stone bed, a glow rim, sand and coral buds (shot 14).
- `DenBuilder.garden` places it at a fixed height (`denSpot(floorFrame, 0, 0, z)`). It needs to sit on the terrain floor at its spot.
- The Hall/Grotto pit doesn't reach the garden; it's floor rock above the garden, not a gap.

### Fixed: the sign and pops (`88a4f54`)

- `StudsOffsetWorldSpace` is applied in the adornee's own frame, and the Sand is a cylinder turned on its side. So:
  - The "6.5 up" sign went 6.5 studs **sideways** at floor height, over the YOUR DEN hint, and was hidden in the floor (shot 14).
  - The pops also flew sideways.
- Both now use world-up converted into the Sand's space. The sign floats above the garden (shots 15, 16), and "+6 CORAL" rises straight up (shots 22, 23).
- The pop also faded with Quint-Out over the whole rise. It was 76% transparent after 0.4 s (logged), so it was barely seen. It now holds for 1 s, then fades.

## C. Shop: PASS

- **SHOP opens it** with "Growth and safety, never bite damage · everything here can be earned in play too" (shots 28, 29). The rows:
  - Daily reward: "Day 1 is ready! CLAIM".
  - BOOSTS: Second Chance (Have 0 / 5), Server Frenzy, Shell Pouch and Shell Chest (each with ODDS).
  - GAME PASSES: ×2 Mass 399, VIP 299, Den Expansion 149, Deep Garden 129.
  - FREE PERKS: Roblox Premium · GET PREMIUM.
  - Every id-0 item is greyed out.
- **ODDS** opens "Roll Odds · Every outcome of one roll for this fish; they add up to 100%" (shot 30).
- **Test as Restricted:** ON hides both shell packs (shot 31); OFF brings them back.
- **Controller:** View (`ButtonSelect`) opens the Shop; after `a18438c` it lands on the Daily CLAIM (shot 32).

## D. Passes

- **×2 Mass: PASS.**
  - The "×2 MASS" chip shows under DAILY/SHOP (shot 33).
  - A starfish (0.04 kg) pops "+0.08" (shot 34).
  - Admin Add Haul: 10 kg with the pass gave +20, without it +10.
  - Predator-kill toast: code-checked only (`PredatorService` toasts the amount `HuntService.feed` returns, which includes the pass). I didn't kill a predator.
- **VIP: PASS** (Local Server, 2 clients).
  - Player2 got VIP. Player1 sees "VIP Player2 · EVEN FIGHT" over Player2's fish, with "VIP" in gold (#FFCC5C, dimmed by the water fog at range; shots 40, 41).
  - Tag text: `<font color="#FFCC5C">VIP</font> Player2`. The character has the `VIP` attribute.
- **Den Expansion: PASS, one clip.**
  - The den menu lists Spot X1/X2 floor and X3/X4 wall ("Empty · Den Expansion", shot 35).
  - I placed a Crystal Shard (X1), Pearl Pedestal (X2), Sea Glass Lantern (X3) and Banner (X4) at Nook and at Grotto. The spots don't move with den level.

    | Item | Clearance |
    |---|---|
    | X1 Crystal Shard | Clear of rock; 8.1 studs from the garden at Nook |
    | X2 Pearl Pedestal | Clear |
    | X3 Sea Glass Lantern | Clear; it's a wall mount, so it touches the wall |
    | X4 Banner | **Its centre voxel is 0.72 solid; the outer edge sinks into the doorway rock** (shot 38) |

  - Nothing clips the Haul Pool, the garden or the trophy wall (shots 37, 38).
  - **Take the pass away:** the four items vanish (DenBase1 keeps only the Garden), and the menu shows "Den Expansion · Four more spots… · R$ 149" instead of X1–X4 (shot 36).
- **Deep Garden: PASS.** The menu shows "375 coral and 18 shells an hour, holds 16 h", and the R$ 129 button is gone (shot 39). "Grow hours" 16 fills it: "6,000 coral · 288 shells · Full".

## E. Products (Admin "Run a product's effect"): PASS

- **Server Frenzy:**
  - Announcement "Dillionaire138 started a SERVER FRENZY: ×2 growth for 15 min!".
  - With ×2 Mass the chip reads "×4 GROWTH · FRENZY 14:58", and a 2 kg feed added 8 kg (shot 42).
  - Without ×2 Mass: "SERVER FRENZY ×2 · 14:46".
- **Shell Pouch:** "+100 Shells! Thanks for the support." **Shell Chest:** "+600 Shells! Thanks for the support." (ROLL ×2 → ×4 → ×16, shot 43).
- **Second Chance with no recent death:** "Second Chance ready: the next time you're eaten, you keep your Haul." (shot 44). The brief expected "+1 charm"; this wording says the same.
  - The Tidecharm Trader shows Second Chance "Have 2 / 1 · **FULL**" (shot 45). Nit: "2 / 1" reads oddly once you hold more than the trader's cap.
- **Double Haul (Small)** after banking 8 kg: "HAUL DOUBLED · +8.0 kg · LEVEL 28 · JUVENILE" (LV 22 → 28, shot 46).
  - Run again: "That Haul was already doubled, so here's a Second Chance charm instead." (shot 47).

## F. Offer cards

- **Bank card:** banking 8 kg against 1.2 kg shows "DOUBLE THIS HAUL? · +8.0 kg more · 6 more levels · DOUBLE IT · R$ 19 / SKIP", with no timer (shot 48).
  - The cursor is free (`MouseBehavior` Default).
  - With id 0, DOUBLE IT shows "Double Haul isn't created in Creator Hub yet (Admin → Run a product's effect tests it)" (shot 49).
  - These close it: **SKIP** (mouse-look returns, `LockCenter`); **B** on the controller (`ButtonB` processed, card gone); **swimming out of the hub**.
- **Tiny bank:** +2.0 kg against ~27 kg banked shows no card.
- **Eaten with 20 kg:** after the respawn, "GET YOUR HAUL BACK? · You lost 20 kg · Second Chance returns all of it · GET IT BACK · R$ 39 / SKIP" (shot 50).
  - Admin Second Chance within 3 min: "Second Chance: your 20 kg Haul is back! Swim home to bank it." (shot 51). It banked at once because the fish was in the den.
  - Eaten again with 1 kg: no card.
- **Fixed:** on respawn, the Daily panel's auto-open drew **on top of** the eaten card and hid the 3-minute Second Chance offer (phone, shot 56). It now waits until the card is gone (`a7c5b40`; shots 58, 59).
- **Fixed:** closing a menu (the Daily panel, the Shop) or the roll reveal over a card set `cursorWanted = false`. The mouse re-locked and GET IT BACK couldn't be clicked; I hit this during the real purchase. The card now holds the cursor while it's open (`901be45`, verified: `MouseBehavior` Default after closing the Shop over a card).

### Phone (iPhone 14, 844×390) and 1280×720

- **PASS on the brief's list.** SHOP/DAILY and the growth chip don't overlap the level card, wallet, HUD row, tutorial panel, boss bar, treasure sonar or depth gauge (shots 52, 53, 60).
- The chip sits about 7 px above the HUD row. The cards' buttons are tappable: DOUBLE IT, SKIP, GET IT BACK, CLAIM.
- **Overlaps outside that list:**
  - The OPEN BLUE biome chip sits on the TATTERED MAP sonar (shot 54).
  - The centre banners' subtitles (TUTORIAL COMPLETE, "TOO DANGEROUS FOR NOW") run across DAILY/SHOP.
  - In the den, the "KELP WRAPS" bar crosses the BITE button, and the "YOUR DEN" button overlaps the eaten card's right edge (shot 57).
  - The Daily claim toast covers the "Come back in…" footer.

## 3. Creator Hub

### The experience

- Connor's account had no Apex Abyss experience, only "[🍀 2x LUCK] Hatch & Snatch 🥚" and "Dillionaire138's Place". This place file had never been published (`GameId` 0).
- **With Connor's OK** I created a private experience: File → New (an empty Baseplate) → Publish to Roblox → "Apex Abyss" (shot 61).
  - Team Create off, Data Sharing off.
  - **Universe 10769954850, place 83646578075996.**
- **ApexAbyss.rbxl was not published.**
- **When you publish:** use Publish to Roblox → "Update existing experience…" → Apex Abyss, so the ids below belong to the game.

### Ids pasted

All are in `Config/Monetization.luau`, committed as `62a4e9c` "Monetization: Creator Hub ids". The descriptions are copied from the config, and Managed pricing is off on all of them.

| Kind | Name | Price | Id |
|---|---|---|---|
| Pass | ×2 Mass | 399 | 2023286343 |
| Pass | VIP | 299 | 2021282363 |
| Pass | Den Expansion | 149 | 2022452343 |
| Pass | Deep Garden | 129 | 2022290332 |
| Product | Second Chance | 39 | 3717380340 |
| Product | Server Frenzy | 99 | 3717380401 |
| Product | Double Haul | 19 | 3717380436 |
| Product | Double Haul (Big) | 49 | 3717380455 |
| Product | Double Haul (Huge) | 99 | 3717380479 |
| Product | Shell Pouch | 49 | 3717380495 |
| Product | Shell Chest | 199 | 3717380526 |
| Product | Double Haul (ad) | 5 | 3717380541 |

- **Rewarded video ads:** under Monetization → Ads, Rewarded Video "Serving enabled" is greyed out with "This experience is not eligible to serve ads" (shots 64, 65).
  - Eligibility needs: ID verification, 2-Step Verification, a public experience, the Maturity & Compliance questionnaire, and 2K monthly active users.
  - **Skipped**, per the brief. WATCH AD stays hidden.

### Real Studio purchases (test purchases, "Your account will not be charged")

| Purchase | Result |
|---|---|
| Second Chance from the Shop (no recent death) | "Purchase completed" + "Second Chance ready: the next time you're eaten, you keep your Haul." (shots 67, 68) |
| Server Frenzy from the Shop | Completed; announcement; the chip "×4 GROWTH · FRENZY 14:56" (shot 69) |
| Shell Pouch from the Shop | Completed; "+100 Shells! Thanks for the support.", ROLL ×3 (shot 70) |
| Double Haul from the bank card | The card's DOUBLE IT · R$ 19 opens "Buy item · Double Haul · 19"; completed; HAUL DOUBLED +12 kg, LV 26 → 32 (shots 71, 72) |
| Second Chance from the eaten card | "You lost 16 kg" card, GET IT BACK · R$ 39; completed; "Second Chance: your 16 kg Haul is back! Swim home to bank it.", Haul bar at 16 kg (shots 73, 74) |
| Passes | **Can't be tested on Connor's account.** Roblox makes a pass's creator its owner, so all four show **Owned** in the Shop, and their effects are on at join (the ×2 MASS chip), on this join and after rejoining (shot 66). The "Thanks! X is yours." toast never fires for the owner. A live pass purchase needs a different buyer. I didn't use another account (house rule). |

- Purchases work in the unpublished place, because Studio test purchases don't check the universe.
- There's no WATCH AD on the bank card, since ads aren't available in Studio.

## Output

- **Errors from the game: 0** in every session.
  - The one error was my own command-bar slip: `CommandBar:1: Cannot use '...' outside of a vararg function - Studio`.
- **Warnings:** once the real ids were in, this line logged once a minute:
  - `AdService:GetAdAvailabilityNowAsync: ad system not initialized yet - Studio` (4 in about 4 minutes).
  - It comes from `src/client/Ads.luau`'s `pcall`-wrapped availability check. Studio's engine logs it; it isn't a script error.
- **No `[MonetizationService]` warnings.**
- **Always:** `[ProfileStore]: Roblox API services unavailable - data will not be saved - Server - ProfileStore:2015`.

## My fixes (all pushed to claude/core-systems)

- `88a4f54` Coral Garden sign and pops: straight up, and readable.
- `a18438c` Controller: menus start on their own first button, not the X.
- `a7c5b40` The Daily panel waits for an open offer card.
- `901be45` Offer cards keep the cursor free under a closing menu.
- `62a4e9c` Monetization: Creator Hub ids.

## For the cloud session

1. **Coral Garden bed:** sit it on the terrain floor at its spot. It's 0.6 studs under at Nook and 1.7–4.6 under at Burrow/Hall/Grotto.
2. **Den Expansion X4 (Banner):** move it off the doorway rock (its centre voxel is 0.72 solid at Nook and at Grotto).
3. **Phone HUD overlaps** (not monetization):
   - The biome chip sits on the treasure sonar.
   - Centre banner subtitles cross DAILY/SHOP.
   - The den's KELP WRAPS bar crosses BITE.
   - The YOUR DEN button overlaps the card's edge.
4. **Studio Output:**
   - `Ads.luau` polls `GetAdAvailabilityNowAsync` every minute; in Studio that logs a warning each time.
   - Skip the poll in Studio, or poll only until the first answer.
5. **Admin "Coral Garden: grow hours"** always counts as time away, so it always shows WELCOME BACK. A real short trip shows none.
6. **Nits:**
   - The Tidecharm Trader's "Have 2 / 1" once purchases pass its cap.
   - "Streak: 1 day · best 0" before the first claim.
   - "2500 coral" without a comma in the Day 7 toast.
7. **Before going live:**
   - Publish this place to the Apex Abyss experience (universe 10769954850).
   - Test one pass purchase with a non-owner.
   - Revisit rewarded video ads once the experience is eligible.
