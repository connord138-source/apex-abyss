# Apex Tide: growth gameplan

Written 2026-11-10 from a five-part read-only audit of the code (first five minutes, touch
controls, pacing and death, return hooks, performance) plus the live numbers Connor sent on
11-08. This is Claude's working plan. Start every growth session by reading sections 4, 7 and 9.

Words used below:
- **Measured:** a number from the live game or a recorded test.
- **In code:** read in the source; I re-checked the lines marked ✔ myself.
- **Estimate:** worked out from config numbers; not timed.

## 1. Where the game stands (2026-11-10)

| | |
|---|---|
| Public numbers (measured) | 249 visits, 4 favourites, 1 like, 2 dislikes, 0 playing |
| New players so far (measured) | about 110, most from the $5-a-day ad |
| Day-1 retention (measured, 11-06 cohort of 77) | 0% |
| New-player session (measured) | 6.3 min; half are gone by about 3 min |
| Old funnel, 11-01 to 11-07 (measured) | 113 joined, 81 left the hub, 54 ate 5, 7 reached LV 15 |
| By device, to 11-08 (measured) | Phones and tablets are 61% of new players. Ate 5: computer 78%, phone 38%, tablet 28%. Banked: computer 61%, phone 11%, tablet 0% |
| Last publish | 11-08 (about v56): first dive starts in the sea, wheel last, touch UP/DOWN and aim help. No data read since |

## 2. What Roblox rewards

From Roblox's Discovery doc (read 2026-11-10). The Home page's "Recommended for You" ranks a
game on how the players it sends behave:

- **Most important:** play-through rate from the tile; **first-play bounce rate** (left within
  60 s, and within 61-180 s); **play days per user** (day 1, days 2-7, days 8-28); playtime
  per user (counted up to 60 min a day).
- **Important:** days played with friends, qualified sessions, days with a purchase, Robux
  spent.
- Players from ads, search and social **don't count** in that ranking. They can get the game
  considered, and they fill our own funnel so we can measure.
- A custom thumbnail is required (we have them).

So the order of work is: stop the bounce in the first 3 minutes, then give a reason to
return the next day, then friends, then spend. Ads and TikTok can't make up for a first
session that loses half its players.

## 3. What the audit found, along a new player's path

### A. Before the game even shows: the cold server (unmeasured, could be the biggest)

- In code ✔: the place file holds no world. Every server start builds the whole ocean
  (about 9,400 terrain fills, an estimated 35-45k instances) before any profile loads
  (`init.server.luau:54` World first, `:100` Data last).
- Measured once: 53 s in Studio on 10-11, before the cliff, Vents field, landmarks and
  deeper map were added. **Measured again 11-13 with Round 0's stamp: 6.5-7.9 s on
  Connor's PC** (`[ApexTide] Server started in N s`), so the 53 s wasn't the build alone.
  Roblox's servers are slower than this PC, so a live start may still be 15-25 s.
- With almost nobody online, nearly every join starts a new server. A player who quits on
  the loading screen never reaches our funnel's "Joined", so our numbers can't see them,
  but Roblox counts them as a bounce.
- Not yet known: how long it takes on a live server today.

### B. On a phone, the screen and controls work against the player

- Verified in the 11-08 phone screenshot ✔: nine menu buttons run across the middle of the
  screen just above the fish; the tutorial card sits under the steering thumb; its text is
  about 10 px.
- In code ✔: a vertical swipe leaves the camera tilted for good. Past 30° the aim help
  switches itself off, so the fish climbs or dives out of the food layer (food is in the
  bottom ~45 of 440 studs).
- In code: the stick zone sits inside the safe area, so a thumb in the notch strip becomes
  a camera drag. Stick travel is 41 pt. UP/DOWN are 41 pt and cancel aim help while held.
- In code ✔: eat messages are sent 0.06 s apart and the server drops any that arrive less
  than 0.05 s after the last, with no resend. On a jittery phone connection some eats pop
  and don't count (how often is unknown).
- In code: devices that report keyboard and touch get half the touch buttons. Console has
  no aim help.

### C. Nothing rewards the player before most of them leave

- In code ✔: the level and its bar read banked mass only. The first level-up happens at the
  first bank: Eat 5, then 5 shells, then a full 1.9 kg Haul (about 19 minnows), then the
  swim home through a tunnel to the right one of 12 doors.
- Estimate: about 3 min on a computer, 8 on a phone. Half are gone by 3.
- In code: a full Haul is a dead end for anyone who can't find home. Every further eat
  shows a grey FULL.
- In code ✔: banking exists only at the pool inside your own den.

### D. Small things that make the first minutes feel unfair

- A fifth of minnows are too big for a new fish (sizes up to 1.30 × look 1.25 = 1.51 studs
  against a 1.40 limit, in code ✔). About half the schools near spawn are other species
  that are all too big, and nothing marks which fish are edible. The TOO BIG hint shows
  three times, then never again.
- The bead trail hides when food is within 18 studs, which is the usual case at spawn.
- "ROLL FOR A NEW LOOK" gives a skin about 17% of the time; the commonest result is 25
  coral (found independently by two audits).
- The Shells step is a detour before any reward, and the Roll step tops shells up to 50
  anyway (in code ✔).
- Learners have no PvP shield, and an oversized prey's nip can't be dodged.
- At LV 11 the hint says "Too easy here: deeper water feeds you better" and sends the
  player into water that kills in 3-4 bites.

### E. Nothing asks the player back

- In code: every return hook waits for the tutorial's end. The daily panel opens itself
  only on a respawn after the tutorial. Bounties unlock then too. Nothing on screen says
  what tomorrow gives.
- In code ✔: the notification ask needs the tutorial done plus 4 banks. Only 7 of 113
  players reached LV 15 (about 3 banks), so almost nobody has been asked. The key and
  Secret have never been confirmed in the live game, and a missing Secret only warns in the
  server log.
- In code ✔: **the Tide Pass is still a preview that resets on 2026-11-16, and the 399 R$
  Deep Pass can be bought now and is wiped by that reset.**
- The first playtime gift is at 5 min. The first boss comes 30 min after a server starts,
  so no new player ever meets the Megalodon from the thumbnails.
- After the tutorial there is no next goal on screen. The 'Cuda needs LV 15, 40 DNA and
  1,500 coral (an estimated 20-30 min on a computer).

### F. Phones start at full quality

- In code ✔: draw detail starts at 1 and only drops after frames are already slow, to a
  floor of 0.6. Only schools and ambient life scale. Kelp sway, predators (animated every
  frame out to 700 studs), crabs, shadows and particles don't.
- The first dive has no load gate, and the start screen streams other biomes first.
- All 27-28 skins of the fish are preloaded 2 s after joining, before a new player can roll.
- In code ✔: the FrameRate event is sent once, after 60 s of play, so it misses everyone who
  quits early. No load time is logged.

### G. Nothing spreads it

- INVITE is at the bottom of the Shop. The inviter is paid only when the friend finishes
  all 8 tutorial steps. There is no bonus for playing with a friend.
- During the 16+ trial most invited friends can't join, so this waits.

### What is sound (don't re-audit)

- Saves: session-locked, a failed load kicks, saves on shutdown; purchases granted once.
- Death costs only the unbanked Haul; 3 s respawn; clear screen.
- Food is plentiful near spawn (about 460 minnows and 680 shrimp and starfish); prey don't flee.
- No popups or offers before the tutorial ends. Monetization is restrained.
- Client loops are budgeted; no leak found; remotes are rate-limited.
- One tap to start; no cinematic after it.

## 4. The rounds

One round = build → test on the PC → publish → measure. Each round has one aim and one
number that should move. Items marked **(owner)** change a dated decision in `CLAUDE.md`
and need Connor's yes first (section 8).

### Round 0: stop the leak we can't see, and fix the pass (before 11-16)

Aim: know the real load time and early frame rate; no purchase can be lost.

1. **Built 11-12.** Tide Pass: Season 1 starts 2026-11-12 (takes effect at the next
   publish), and a Deep Pass bought in the preview carries into it.
2. **Built 11-12.** Custom events (Analytics → Explore; each event is a Source there):
   - `JoinWait`: seconds a player waited for their save, cold or warm server, and the
     band of the server's whole start;
   - `LoadTime`: seconds from the client's scripts starting to TAP TO START, by device;
   - `FrameRateEarly`: frame rate over the first 10 s of play (`FrameRate` stays the
     first minute);
   - `StartError`: a service or controller that failed to start (each start is protected).
   - Not possible: seeing players who quit before their save loads. Compare Roblox's
     visits with the funnel's "Joined" instead.
3. Connor: time one phone join with a stopwatch, and run the admin Notifications test once
   in the live game.
4. To do on the PC: Studio test (see "Round 0 test list" in section 9), then publish.

### Round 1: the first three minutes

Aim: bounce. Number: share of new players who bank within 3 min (computer) and 6 min
(phone); "ate 5" on phones from 38% toward 70%.

Reward sooner:
1. **Built 11-12.** A centre pop for every level earned in the dive, under LV 15.
2. **Built 11-13 (owner: yes).** First bank after about 7 fish: tutorial `HAUL_LEVELS`
   5 → 2 (the Haul step reads GROW YOUR HAUL; the first bank is LV 1 → 3).
3. **Built 11-20.** The Shells step moves after the first bank, to the very end: Eat,
   Haul, Bank, Roll, Wrap, Index, Wheel, Shells. (Straight after the bank it would have
   been a trip out of the den before the button steps, which is where 31% stopped when
   the wheel stood there; at the end it is the way back out to sea.)
4. **Built 11-12.** The first roll ever is always a skin (Common or better).
5. **Covered by item 2.** At about 40% Haul, the card and trail already point home: the
   Haul step now ends at two levels' worth, about a third of a full Haul, and the Bank
   step's card and trail take over from there.

Make food obvious:
6. **Built 11-13 (owner: yes).** Minnow `look` 1.25 → 1.15 so a new fish can swallow
   every normal minnow.
7. **Built 11-20.** A ring on the trail's current target (it follows a fish as it
   swims). **Built 11-12:** TOO BIG keeps showing during the tutorial (every 8 s at
   most).
8. **Built 11-20.** Trail fixes: no beads into rock from the hub or den (the trail to
   food or shells goes by the den's way out and a tunnel); never target Medkelp.

Phones:
9. **Built 11-20.** During the tutorial, hide the menu row (ROLL and INDEX show on
   their steps only; the whole row is back from the step after the Index) and show the
   step as a large strip at the top instead of the card under the thumb.
10. **Built 11-20, learners only.** Camera pitch eases back to level after 1 s without a
    look touch while the stick is pushed (out of the hub and dens, UP/DOWN let go; after
    the tutorial a deliberate dive keeps its tilt).
11. **Built 11-20.** Find the stick by screen position (works in the notch strip); travel
    41 → 72 points.
12. **Built 11-20, smaller than planned.** UP/DOWN 56 → 60 (72 doesn't fit between SHOP,
    the biome chip, the depth gauge and the special button), and they stay in the den:
    DEN & SHOP, ADMIRE and SPIN now end left of them.
13. **Built 11-12.** A burst of 3 eat messages passes before the rate limit drops any.
14. **Built 11-20:** aim help for gamepads. **Not built:** full touch buttons on
    keyboard-plus-touch devices (eight controllers each build their phone button once at
    start; it needs a touch laptop or Chromebook to test, and such players have their
    keys).

Safety and smoothness:
15. **Built 11-12.** Bites on or by a fish still in the tutorial do nothing.
16. **Built 11-20:** touch devices start at detail 0.6; the floor can fall to 0.4 under
    25 FPS; detail also scales the kelp's sway reach and the crabs. **Not built:** far
    predators (no measurement says they cost much; wait for a phone profile), and
    shadows off on touch (**owner, 2026-11-24: "keep shadows".** Tried that day in the
    phone simulator, where the rocks and kelp went brighter and flatter, and undone).
17. **Built 11-12.** Skin previews load once a roll is half earned, not at join.
18. **Built 11-20.** The first dive waits for the sea floor to load (capped at 8 s).
    **Built 11-13 (owner: yes):** touch devices show only the backdrop on the start
    screen (it narrows the 10-19 attract mode to computers and consoles).

### Round 2: the cold start (order depends on Round 0's measurement)

If a live cold join takes more than about 20 s, this moves ahead of Round 1.

1. Stopgap: yield between world builders so the client's own start screen shows.
2. Bake the terrain into the place file and skip the terrain build when it's there.
3. Later, bake the dressing too.

### Round 3: a reason to come back tomorrow

Aim: day-1 retention from 0% to 10%, then 15%+. Number: day-1 retention; share of players
asked about notifications.

1. One "tomorrow" card after the first bank's growth sequence: Day 2 reward, free roll,
   wheel spins, with the notifications YES on it **(owner: moves the 10-09 "after the
   tutorial" rule)**. `askAfterBanks` 4 → 1.
2. A "Day 2 reward ready" notification (Connor creates the string in Creator Hub).
3. Playtime gifts at 2 and 4 min; gift and boss countdowns always visible.
4. After the tutorial, the card stays as a NEXT chip (the 'Cuda's gate, next biome).
5. 'Cuda DNA 40 → 20 **(owner)**; "too easy here" hint starts 3 levels later; predator
   bite cap ×1.5 → ×1.25 for fish under the biome's level **(owner)**.
6. Tide Pass tier 1 at about 300 XP so PASS lights after the first bank.
7. Toast the weekly rank at the bank (with ~110 players, anyone who banks is top 100).
8. A new server's first boss at about 8 min **(owner: bends "about every 30 minutes")**.
9. Daily reward on a rolling 18 h claim and 48 h break **(owner: changes the UTC-day rule)**.
10. Double Haul offer on one bank in three, not every bank.

### Round 4: friends (after the game opens to all ages)

1. INVITE on the HUD while the server has fewer than 3 players, and on a Rare+ reveal.
2. Pay the inviter at the friend's first bank.
3. +10% Haul while a friend is in the server.
4. Put the four codes in the store description.

### Round 5: content beats

1. The Giant Squid's look (texture, suckers, glowing eyes), then its reveal video and the
   hook reshoot from under the boat (agreed 11-10).
2. Season 1 for real, with a Roblox Experience Event on the game page.

## 5. Marketing track (runs alongside)

- **TikTok:** 3 clips a week, each with a different opening hook, real gameplay only. Read
  watch time and "watched full video", not likes. Claude cuts, Connor approves and posts.
- **No more ad money until Round 1 is live,** except a small run to fill a measurement
  window. Ad players don't count toward Roblox's ranking, but they are how we reach 250
  engaged plays for all ages and how we get enough players to read a funnel.
- **Game page:** upload video v2 (waiting on Connor); test thumbnails one at a time.
- **All ages:** the 250 engaged plays (or the 1,000 Robux route with 2 months of
  Premium) remain the gate for the big audience. Round 3 is what makes ad players "engaged".

## 6. Scorecard (read after each publish, from the publish date)

| Number | Where | Now | First target |
|---|---|---|---|
| Cold join, phone, tap Play → TAP TO START | stopwatch, then the load event | 11-19: the save loaded in 7.8 s on 28 cold joins (2.4 s on 21 warm), then TAP TO START 2-3 s after the client's scripts start on every device; two slow joins on 11-20 (20-39 s and 60-89 s) | under 20 s |
| Left within 3 min | Analytics → Retention / session curve | ~50% | under 35% |
| Ate 5, phone | Funnels by platform | 61% (19 of 31, 11-19; was 38%) | 70% |
| Banked once, phone / computer | Funnels by platform | 26% / 80% (8 of 31, 8 of 10, 11-19; were 11% / 61%) | 45% / 80% |
| Finished the tutorial | Funnels | 21% (12 of 56, 11-19; was 7%) | 35% |
| New-player session | Engagement | 6.3 min | 10 min |
| Day-1 retention | Retention | 0% | 10% |
| FPS at 10 s, phone / tablet | Explore → FrameRateEarly by device | phones 31 (30 reports, 11-19 and 11-20), tablets 47 (7); 10 of the 56 reports on all devices were under 20 | 30+ |
| Asked about notifications | Custom event (to add) | ~0 | half of bankers |

The targets are mine, set to be checkable; they are not Roblox benchmarks.

## 7. Claude's working routine

**Start of a session**
1. Read sections 4, 8 and 9 here, and the memory notes.
2. `git status` and `git log -3` on `claude/core-systems`.
3. If a measurement window has ended, read section 6's numbers in Creator Hub (the
   app's built-in browser is signed in since 11-18; read only, and ask Connor to sign in
   again if it shows the login page). Otherwise carry on with the current round.

**Building (no PC needed)**
1. One round at a time. Write the round's aim and number in section 9 before coding.
2. Code against the files named in the appendix; keep each change small and separate.
3. Run the repo's own checks that the change touches (`tools/tests/run_*.sh`), and
   `stylua` on changed files only.
4. Record every change and its owner-decision status in `CLAUDE.md` as usual.

**Testing (only when Connor says the PC is free)**
1. `rojo serve`, connect Studio, Play.
2. Walk the new-player path twice: keyboard, then the phone simulator. Use a fresh save
   (admin reset).
3. Check each change against a written pass/fail line. Fix and re-run until clean.
4. Phone-feel changes also need 5 minutes on Connor's real phone after publishing; the
   simulator can't judge thumbs, safe areas or frame rate.

**Publishing**
1. Only when Connor says so. Commit only when asked.
2. Record the version, date and commit in section 9.

**Measuring**
1. Read numbers only from the publish date on.
2. A step's rate needs about 100 new players to tell 40% from 60%. At ~16 a day that is a
   week, so: bundle related changes into one round, and ask Connor about a small ad run to
   fill the window.
3. Compare by platform every time.
4. Write the before and after in section 9, then keep, revert or adjust. One paragraph to
   Connor: what changed, the number, the next step.

**Rules that don't bend**
- A change that reverses a dated owner decision is asked first, with the date quoted.
- Never guess at a cause when a number can be logged instead; add the event.
- Everything in the project's standing rules still applies (no publish, commit, upload or
  PC control without Connor's word).

## 8. Owner decisions waiting

| # | Decision | My recommendation |
|---|---|---|
| 1 | Tide Pass before 11-16: start Season 1 at the next publish, or hide the Deep Pass button until then | **Done: Season 1 went live with the 11-13 publish** (Connor: "commit and publish") |
| 2 | First bank after ~7 fish instead of ~19 (tutorial only; changes the 10-19 and 10-20 notes) | **Decided 11-13: yes, built** |
| 3 | The "tomorrow" card and notification ask at the first bank, not after the tutorial and 4 banks | Yes |
| 4 | Phones show a plain backdrop on the start screen instead of the rolling shots | **Decided 11-13: yes, built** |
| 5 | A fresh server's first boss at ~8 min | Yes, once Round 1 is in |
| 6 | 'Cuda DNA 40 → 20; softer bites on under-levelled fish | Yes |
| 7 | Daily reward on a rolling clock instead of UTC days | Yes |
| 8 | First bank at the hub's entrance instead of the den | Hold; try #2 first |

## 9. Round log

| Round | Aim | Built | Tested | Published | Read on | Result |
|---|---|---|---|---|---|---|
| 0 | Measure load and early FPS; fix the pass | 11-12 | 11-13 ✔ | 11-13 (11d59d7, 01:01 UTC 11-14) | from 11-14 | 11-18: Season 1 live; cold joins 5-13 s, so round 2 stays where it is; load time and early FPS need the logging fix and more players |
| 1 | First three minutes | 11-12: items 1, 4, 7 (half), 13, 15, 17; 11-13: items 2, 6, 18 (backdrop) | 11-13 ✔ | 11-13 (same publish) | from 11-14 | 11-18: no verdict, only 5 new players since the ad stopped. **11-20: keep.** 56 new players on 11-19: banked 41% (was 17%), finished the tutorial 21% (was 7%); phones banked 26% (was 11%) |
| 1, third batch | First three minutes, phones first | 11-20: items 3, 7, 8, 9, 10, 11, 12, 14 (gamepads), 16 (most), 18 | 11-24 ✔ (Studio 0.748; two fixes found and made while testing) | 11-24, v59 | from 11-25 | |

**First read, 2026-11-18 (Creator Hub, read by Claude in the signed-in built-in browser;
Roblox showed a reporting-delay banner).**
- **Too few players to judge.** The ad stopped after 11-13 (impressions 5,323 → 10 → 0):
  new players a day went 7, 46, 50, 71, 75, 35 (11-08 to 11-13), then 1, 1, 2, 1. The new
  build had 14 joins and 5 new players by 11-17. Of the 5: all dived in, 2 ate five, and
  both finished every step through the wheel.
- **JoinWait, 14 joins:** 10 cold (they started a server) waited 5-13 s, average 8.6; 4
  warm about 0-1 s. Server starts: under 5 s ×5, 5-9 s ×4, 10-19 s ×5. Nothing over 20 s.
- **FrameRateEarly, 8 reports:** phones 2 (one 20-29, one 55+), tablet 60, gamepads 4
  (average 58), computer 102. **StartError:** none.
- **The baseline to beat** (the 11-08 build with the ad on, 11-09 to 11-13, 275 new
  players): Dived in 99%, Eat 63%, Shells 40%, Haul 25%, Bank 17%, Roll 14%, Wrap 10%,
  Index 9%, Wheel 7%, banked on their own 4.7%, LV 15 4%. Day-1 retention 0-3%, day-7 0.
  FPS after a minute: phones 36 (74 players), tablets 44 (42), gamepads 49 (47),
  computers 54 (18). 275 of 277 new users reached "Joined".
- **Logging bug found and fixed:** LoadTime had 3 events for 14 joins, all "warm".
  `Net.onRequest`'s rate limit treated "never asked" as clock 0, so a player's first
  LoadReport, DeviceReport or StartError was dropped while the server's clock was under
  the 30 s interval: every join that starts a server. Fixed in `Net.luau` ("never asked"
  = long ago). Numbers for those three events before the fix undercount cold joins.
- **Published 2026-11-18 as v58** (Connor: "commit and publish") from 20ba0db at 19:07
  UTC. A Studio Play just before it: server started in 7 s, `JoinWait 9 s, cold`,
  `LoadTime 3 s, computer, cold`, no script errors.
- **Next:** a few days of ad traffic (Connor's switch) to fill the window: about 100 new
  players reads a step's rate. Check Explore for the first "cold" LoadTime to confirm
  the fix on a live server, and read LoadTime, FrameRateEarly and StartError from
  2026-11-19 on.

**Studio test, 2026-11-13 (Studio 0.747, keyboard; the LEVEL pop on the phone simulator
too). Every line below passed.** Shots in `docs/playtests/shots/2026-11-13/`. Changed
while testing: the first player heard always counts from the server's start (in Studio
the first join is heard only after everything has started, so JoinWait read "0 s, warm");
TOO BIG hints shown in the tutorial don't use up the three after it; admin `passRestart`
takes "paid". No script errors in any log.
- Round 0: server started in 6.5-7.9 s; `JoinWait 7 s, cold`; `LoadTime 3 s`;
  `FrameRateEarly` 12 s after diving in and `FrameRate` at 62 s; PASS reads SEASON 1 ·
  RIPTIDE, "ends in 26d 5h", no preview line; a preview Deep Pass carried with its toast
  and the paid row unlocked (×1.2 XP); with `VendorController` and `CompanionService`
  broken on purpose the fish still swam and both were named in the Output and the
  `StartError` lines (both restored after).
- Round 1: LEVEL 2-6 each popped once over 16 eats; the first roll was Tomato Shade,
  "NEW · your first skin!"; bites did nothing in all three learner cases (8, 8 and 7
  bites, health 100 → 100) and five bites ate the other fish once both were done; TOO
  BIG showed 7 times in 50 s, 8 s apart; a test player with 0 shells had none of the 28
  Nibbler skins fetched at join and all 28 after 25 shells. The eat allowance's sums
  ran as written (3 let through, then one every 0.05 s); Studio has no network jitter,
  so its gain on phones is read from the live funnel's Eat step.
- Seen in passing: Connor's own account starts with 100 shells (the community's perk),
  so its skins warm at join; a new player's fish sits in the shallows while their start
  screen is still up (the learner shield now covers it); the BITE hint still shows a
  learner beside another player though that bite does nothing.

**Second batch, 2026-11-13 (Connor: "yes to all three": first bank after about 7 fish,
slightly shorter minnows, plain start backdrop on phones). Built and run in Studio the
same evening; all three passed, no script errors.**
- First bank: a fresh test player ate five starfish and shrimp (Haul 0.30 kg), picked up
  five shells, and the Haul step showed GROW YOUR HAUL · 0.30 kg / 0.65 kg. Two Minnows
  later the card moved to BANK IT AT HOME (LEVEL 2 and LEVEL 3 had popped on the way).
  The bank read "+0.74 kg BANKED · 1.8 ft → 2.2 ft · LEVEL 1 → 3 · +2 LEVELS", and the
  next Haul holds 2.9 kg. Funnel steps Eat, Shells, Haul and Bank logged in order.
- Minnows: 1,833 in the sea, 1,725 of normal size, the longest 1.388 studs against the
  1.40 a new fish swallows: none too big (a fifth were). 104 of the 108 trophies still
  are. Two of sizes 1.255 and 1.266, too big before, were swallowed by the LV 1 fish.
- Phone start screen (iPhone 17 Pro simulator): the plain backdrop a minute in, nothing
  asked of the server (`StartStreamed` nil, no `StartFoci`), TAP TO START dives in and
  the first step shows. `LoadTime 3 s, phone`. On the computer the shots still play
  (Vent Eelpout was the first).
- To read after publishing: the funnel's Bank step on phones and computers (was the
  biggest drop after Eat), and LoadTime and FrameRateEarly by device.

**Second read, 2026-11-20 (Creator Hub, read by Claude; the funnel's data ran to Nov 19,
11 PM).** Players came back on 11-19: 49 joins and 56 new players in the funnel for
11-19 and 11-20, against 1 or 2 a day since the ad stopped. Where from isn't in yet
(Acquisition ran only to 11-18, when Sponsored Ads showed 13 impressions again and Home
Recommendation had shown 155 the day before). This is the 11-13 build's first real
sample: rounds 0 and 1 as published then, without the third batch.
- **The funnel, 56 new players, against the 275 of 11-09 to 11-13:** Dived in 100% (99),
  Eat 75% (63), Shells 54% (40), Haul 46% (25), Bank 41% (17), Roll 34% (14), Wrap 29%
  (10), Index 25% (9), Wheel 21% (7), banked on their own 16% (4.7), LV 15 7% (4). The
  first bank more than doubled and three times as many finished the tutorial. One day
  and 56 players: the bank's rate is good to about 13 points either way.
- **By platform (new players; Bank):** phones 31, Eat 61%, Shells 42%, Haul 32%, Bank
  26%, Wheel 16%; computers 10, Bank 80%; consoles 8, Bank 63%; tablets 7, Bank 29%
  (11-01 to 11-07: phones 11%, computers 61%, consoles 45%, tablets 0%). Phones are
  still the leak: 12 of 31 never ate five things and 6 of the 19 who did stopped at the
  Shells step, the step the third batch moves out of the way.
- **Frame rate, first 10 s:** phones 31 FPS on average (30 reports), tablets 47 (7),
  gamepads 55 (9), computers 80 (10). Of all 56 reports, 10 were under 20 FPS and 3 more
  under 30. After a minute: phones 31 (22), tablets 42, gamepads 54, computers 75.
- **The wait:** JoinWait on 11-19: 28 cold joins 7.8 s on average, 21 warm 2.4 s; none
  over 20 s (19 under 5 s, 21 at 5-9, 9 at 10-19). On 11-20 two of 9 were slow: one
  20-39 s and one 60-89 s. LoadTime: all 58 under 5 s, 2.0-2.7 s by device. Round 2
  stays where it is, with the two slow joins to watch.
- **The logging fix works:** LoadTime now arrives marked cold (28 of 49 on 11-19; 0
  before v58), and FrameRateEarly came from 47 of 49 joins. **StartError:** none.
- **What it says for the third batch:** the Shells step is now the biggest drop after
  the first bite on every device but computers (Eat to Shells loses 29%), and 10 of 56
  devices start under 20 FPS (not split by device; most likely phones, whose average
  was 31), so items 3 and 16 are the ones to test and ship first.

**Round 1 third batch, built 2026-11-20 (Connor: "keep going on round 1"). Tested in
Studio on 2026-11-24 (results under its test list below), committed as f288e19 and
published the same day as v59 at 18:14 UTC (Connor: "commit and publish").** What
changed is in `CLAUDE.md` ("Gameplan round 1, third batch"). It moves
the funnel's steps: "Tutorial: Shells" is now the last tutorial step, so read each step
by name, and read rates from 2026-11-25 on (the first whole day). Left out on purpose: touch buttons on
keyboard-plus-touch devices, far predators by detail, and shadows off on phones
(Connor, 2026-11-24: "keep shadows").

**Round 1 third-batch test list (Studio Play, when the PC is free)**
Keyboard, fresh save (admin reset):
1. The card reads STEP 1 OF 8, EAT 5 SMALL THINGS; then GROW YOUR HAUL, BANK IT AT HOME,
   ROLL, WRAP, INDEX, the wheel, and PICK UP 5 SHELLS last. Funnel steps print in that
   order. Finishing on the Shells step pays the 50 shells and 500 coral out in the sea.
2. A cyan ring sits on the fish, shrimp or starfish the trail leads to, stays on a fish
   as it swims, and moves on when that one is eaten. On the Shells step it sits on a
   shell. No ring on the way home or to the wheel.
3. On the Haul step, swim into the hub: the trail leads to a tunnel's inner end, then
   its outer end, then to food; never into the cavern's wall. In the den it leads to the
   way out. On the Shells step from the wheel the same.
4. The trail never leads to a Medkelp frond (stand by one with no fish near).
5. Old saves carry on (command bar, `Config.Tutorial.carryOn` with `v = 3`): step 2
   (Shells) gives 2 (Haul) and false; step 3 (Haul) gives 2 and true; step 5 (Roll)
   gives 4 and true; step 8 (the wheel) gives 7 and true. Shells then comes round at
   the end for all of them.
6. Gamepad (Controller Emulator): pushing ahead over a shrimp a little below, the fish
   tilts down to it (the `AimHelp` attribute holds the point); A / B held stop it.
7. A first dive still clears about 2 s after TAP TO START (no `[Start] the dive cleared
   after` warning in the Output).
Phone simulator (iPhone), fresh save:
8. No card in the lower left. A strip at the top centre shows the step's title, a short
   line, the count and the distance with its arrow; the tide chip is gone while it's
   up and SAFE ZONE / PROTECTED sits under it. No controls line across it, and no step
   banner in the middle (LEVEL 2 still pops there).
9. The button row is gone on Eat, Haul and Bank; only ROLL on the Roll step (ringed);
   nothing on Wrap; only INDEX on the Index step; the whole row back on the wheel step
   and after the tutorial.
10. Swipe the view down past 30° and push the stick: after a second the view eases
    back to level and the fish swims level again. Not in the hub or den, not while UP
    or DOWN is held, and not once the tutorial is done.
11. The stick: a full push needs a longer drag than before (72 points) and the knob's
    centre stops at the ring's edge. UP and DOWN are a little bigger, and in your own
    den they stay on screen with DEN & SHOP to their left; at the wheel SPIN sits left
    of them too.
12. `workspace.Prey` `Detail` reads 0.6 on the start screen and at the dive, and climbs
    toward 1 after it on a fast machine. (0.4 needs a slow device: force it by loading
    the PC, or read it on a real phone.)

**Results, 2026-11-24 (Studio 0.748 Play on the PC: keyboard, Controller Emulator, Device
Simulator iPhone 17 Pro; six fresh Plays; shots in `docs/playtests/shots/2026-11-24/`).**
Every line that could be run passed; two faults turned up on the phone and were fixed and
re-tested the same day.
1. ✔ STEP 1 OF 8 EAT 5 SMALL THINGS, GROW YOUR HAUL (0.58 kg / 0.65 kg), BANK IT AT HOME,
   ROLL FOR A NEW LOOK, USE A KELP WRAP, OPEN THE INDEX, SPIN THE TREASURE WHEEL, PICK UP
   5 SHELLS (8 OF 8). Funnel: 1 Joined, 2 Dived in, 3 Eat, 4 Haul, 5 Bank, 6 Roll, 7 Wrap,
   8 Index, 9 Wheel, 10 Shells. TUTORIAL COMPLETE out in the sea, 253 studs from the hub's
   middle: coral 95 → 595, shells 45 → 95.
2. ✔ The ring sat on a starfish (0.3 studs off), then on a Minnow and stayed within 0.05
   studs of it over 3 s of half-second samples while the school swam; eaten, it was on
   another fish at the next sample. On the Shells step it sat on a shell. No ring on the
   Bank step, the wheel step, or while the trail led to a tunnel.
3. ✔ On the Eat step and on the Shells step: in the cavern (100 studs out, between two
   tunnels) the trail led to a tunnel's inner end ("79 ft to the tunnel out to sea"), at
   the inner end and half-way down the tunnel to its outer end, past the mouth to the
   food or shell with the ring; in the den to "your den's way out". The same code serves
   the Haul step, which the test fish passed in seconds.
4. ✔ Standing 4 studs from a Medkelp frond whose nearest other food was 22 studs off, with
   room for a wrap: the trail and ring led to a Minnow 32-36 studs from the frond.
5. ✔ `carryOn` with `v = 3`: step 1 → 1 (keeps its count), 2 → 2 Haul (fresh), 3 → 2
   (keeps), 4 → 3, 5 → 4, 6 → 5, 7 → 6, 8 → 7 (all keep).
6. ✔ With the emulated pad's stick held, `AimHelp` held a point and the swim tilted to it
   both ways (to +29° at a fish above and -24° at one below, the camera level at -7°
   throughout). A alone rose and B alone sank straight, with the point left alone. **Not
   run:** the stick and A or B held together (the test tool presses one key at a time);
   the gate is the same `Input.vertical()` line as a phone's UP and DOWN.
7. ✔ The HUD was back 2.66-2.68 s after the key or tap on six dives (keyboard and phone),
   and no `[Start]` warning.
8. ✔ No card; the strip showed each step's title, its short line, the count and the way,
   n / 8 in its corner; no tide chip while it was up (back after the tutorial), SAFE ZONE
   under it in the den and at the wheel, the biome title under it; no controls line; no
   step banner through three step changes; LEVEL 2 … popped under it.
9. ✔ Row empty on Eat, Haul and Bank; only ROLL on the Roll step, ringed; empty on Wrap
   (the item bar's Kelp Wrap ringed); only INDEX on the Index step, ringed; the whole row
   from the wheel step on and after the tutorial. The Index's first line reads "follow
   the strip at the top of the screen".
10. ✔ A swipe to 49° down, then the stick: the view held about a second, then eased to 7°
    down within two more, and the fish swam level. In the den the view stayed at 40° down;
    with the tutorial done it stayed at 40° down out at sea. **Not run:** UP or DOWN held
    with the stick (one pointer in the simulator).
11. ✔ A drag of 51 screen px gave 0.71 of a push and of top speed, 78 px a full one (the
    ring's radius is 40 px there; 72 px is a full push). UP and DOWN are 42 px (60 design)
    and stayed up in the den with DEN & SHOP ending 7 px left of them; at the wheel SPIN
    sat in the same place and the row's SHOP ended 9 px left of UP.
12. ✔ after a fix (below): 0.6 through the start screen and at the dive, then 0.73, 0.80,
    0.88 … 1.0 over about 15 s at 56 FPS.

**Fixed while testing (both in f288e19 with the batch):**
- **Draw detail climbed back to 1 on the start screen.** A phone's plain start screen
  draws almost nothing, so its fast frames took the detail from 0.6 to 1 before the first
  dive (it read 1 at the dive). Now, while the fish is held still (`Input.locked`: the
  start screen and the loading washes), fast frames bring the detail back only as far as
  the device started (0.6 on touch, 1 elsewhere); it still eases down there. A first try
  that simply stopped it rising left it at 0.43 after the load's slow first seconds, so it
  has to be able to come back to its start. Computers are unchanged (their start is 1).
- **A boss bar or countdown pushed the strip over the LEVEL pop.** The strip sits under
  the boss countdown when one is up, which put it across the level's title. The pop is now
  placed under the top centre's stack when the stack reaches that far (as the catch banner
  already was): with the Megalodon's countdown up it stood 6 px under the strip on four
  pops. On a computer it is where it was.

**Seen, left as they are:** the phone's minimap covers the top of the biome chip (it did on
2026-11-08 too); in a dense bait ball with a full Haul the aim help's point hops between
fish above and below and the fish wobbles (the same code as on touch since 11-08; with
room in the Haul it eats what it tilts to); on a computer the start screen's shots can
hold the detail at 0.6 until a few seconds after the dive (the 10-20 rule, not this
batch).

**Round 0 test list (Studio Play, when the PC is free)**
1. Output shows `[ApexTide] Server started in N s` and no `failed to start` line; the
   client prints `[ApexTide] Client ready`.
2. Output shows `[Funnel] <name>: JoinWait … cold`, then `LoadTime …` when TAP TO START
   shows, `FrameRateEarly …` about 10 s after diving in and `FrameRate …` at a minute.
3. PASS reads SEASON 1 · RIPTIDE with an end date (2026-12-10), no "Preview" line.
4. Admin: Deep Pass on, pass restart → the record settles to season 1 (restart clears
   paid by design). With a save left on the preview and paid, joining shows "Your Deep
   Pass is yours for Season 1".
5. Break one controller's start on purpose (a temporary `error()`), Play: the fish still
   swims, Output names it, `[Funnel] … client start failed: <name>`. Undo the break.

**Round 1 first-batch test list**
1. Fresh save: eating shows LEVEL 2, LEVEL 3 … in the middle of the screen, each once.
2. The tutorial's roll is a skin: "NEW · your first skin!" with WEAR IT.
3. Two players, one still in the tutorial: bites either way do nothing; both done, bites land.
4. Eating fast through a school counts every fish (no fish popping back).
5. TOO BIG shows again after 8 s during the tutorial; only 3 times after it.
6. No skin loading at join (memory steadier); the ROLL reveal still shows every card.

## Appendix: where each finding lives

Paths are under `src/`. ✔ = re-checked by Claude on 2026-11-10; the rest were read by the
audit and not re-checked.

**Cold start**
- `server/init.server.luau:54-102` ✔ start order; `server/Services/WorldService.luau:197, 1044-1105, 1572`
- `docs/playtests/2026-10-11-pc-2.md:40` ✔ the 53 s
- `client/Controllers/StartController.luau:65-67` ✔ 2.4 s minimum, 25 s cap; `shared/Config/Start.luau:244-249`

**First level-up and banking**
- `client/Controllers/HudController.luau:1052-1062` ✔ level reads banked mass; `:149-160` the "+N LV"; `:1288-1294` FULL
- `shared/Config/Tutorial.luau:62-121, 181` ✔ steps and `HAUL_LEVELS = 5`
- `shared/Config/Tuning.luau:249-273` ✔ food table and cap; `server/Services/HuntService.luau:217-221, 682-702` ✔ cap and den-pool bank
- `server/Services/TutorialService.luau:109-114` ✔ roll tops shells to 50; `:220-227, 243-248, 272`

**Food and trail**
- `shared/Schools.luau:120-125` ✔ sizes; `shared/Config/Prey.luau:93` ✔ `look`
- `client/Controllers/TutorialController.luau:73, 286-294, 415, 663, 762`; `client/Controllers/HintController.luau:42, 251`
- `shared/Config/Shades.luau:1238-1255`, `shared/Config/Rolls.luau:14-27`, `server/Services/RollService.luau:65-73`

**Touch**
- `client/Input.luau:197-202, 283-284, 341-354`; `client/Controllers/CameraController.luau:183-227`
- `client/Controllers/SwimController.luau:510-524` ✔ aim help weight; `client/Controllers/AimHelpController.luau:29-65` ✔
- `client/Controllers/HudController.luau:753-761, 798-871, 916-941`; `client/Ui.luau:104-114`
- `server/Net.luau:57-61, 354-367` ✔ and `client/Controllers/SchoolController.luau:118` ✔ the 0.05 / 0.06 s race
- `client/Controllers/RollController.luau:858-892` the menu row; screenshot `docs/playtests/shots/2026-11-08/phone_eat_step_updown.jpg` ✔

**Danger**
- `server/Services/HuntService.luau:584` no learner shield; `server/Services/AggroService.luau:74-116`
- `shared/Config/Tuning.luau:280`, `shared/Config/Predators.luau:172-389, 848`, `shared/Config/Biomes.luau:111-118`

**Return hooks**
- `shared/Config/Pass.luau:89` ✔, `server/Services/PassService.luau:104-123` ✔, `client/Controllers/MenuController.luau:4295, 4311` ✔
- `client/Controllers/OfferController.luau:396-510`; `server/Services/BountyService.luau:112, 207-210`
- `shared/Config/Social.luau:181` ✔ `askAfterBanks = 4`; `server/Services/NotifyService.luau:82-89, 212-240`; `CLAUDE.md:3342` ✔
- `shared/Config/Playtime.luau:15`; `server/Services/BossService.luau:1756-1757`; `shared/Config/Chum.luau:39`
- `server/Services/ReferralService.luau:35, 199-214`; `server/Services/LeaderboardService.luau:168-216`
- `server/Services/EconomyService.luau:63-65`, `server/Services/RewardsService.luau:42-48` UTC days

**Performance**
- `client/Controllers/SchoolController.luau:108-112, 198, 1652-1653` ✔ detail; `client/Controllers/KelpController.luau:62`
- `client/Controllers/PredatorController.luau:1571-1687`; `client/Controllers/OceanController.luau:569-575`
- `client/Controllers/DeviceReportController.luau:16, 38-49` ✔ one report after 60 s
- `client/Controllers/RollController.luau:927-931`, `client/CardPhoto.luau:703-790` skin warm-up
- `server/Services/FishService.luau:122-182`; `client/Controllers/DenDoorController.luau:57-88`
- `server/Services/PredatorService.luau:136, 1913-1958` stream volume
- `client/init.client.luau:63-120` unprotected controller starts
