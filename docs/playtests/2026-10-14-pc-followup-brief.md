Apex Abyss — PC follow-up brief (2026-10-14, after the overnight run): the bone-white teeth import, a re-test of the cloud's fixes for the overnight report's "For a decision" list, the Deep Pass id, and publishing.

## How to run it

- Work in `C:\Users\neos1\Desktop\apex-abyss` on `claude/core-systems`, in **`ApexAbyss.rbxl`** (File → Open from File). Rojo on port **34873**.
- Run every check in order. Note pass / fail / partial / blocked for each, with screenshots named by check ID and Output lines word for word.
- Small, obvious fixes are yours: one commit per fix, its check ID in the message, re-tested. Report anything bigger and move on.

## 1. Merge and sync

Merge `origin/claude/world` into `claude/core-systems`. It already contains your twelve overnight fixes, so it should fast-forward. Then run `rokit install` and `rojo serve`, and connect the plugin. Format with `stylua --line-endings Windows src --glob "!**/Packages/**"`. Play once: the Output should have no errors.

## 2. Bone-white teeth (skins v8.2)

Run steps 2–5 of `docs/playtests/2026-10-14-pc-teeth-brief.md`:
- Fetch the bundle; it must print `sha256 feb731f3`.
- Screen the four changed GLBs one at a time. Each must exit 0.
- Import them one at a time, about 3 minutes apart, into `ApexAbyss.rbxl`.
- Run `organize_shades.luau`. Expect 28 skins each for the Angler, Cuda, MorayEel and ReefShark.
- Save, then run checks T1–T5.

Never upload an image that a screen didn't clear, and never re-import the Nibbler or Puffer GLBs.

## 3. Deep Pass id

The id is **3718493448** (from Connor), already in `src/shared/Config/Monetization.luau` (the `key = "DeepPass"` entry) on `claude/world`. Check it matches the **Deep Pass** row in Game Settings → Monetization → Developer Products. If it doesn't, put in the one Studio shows and commit ("Deep Pass product id").

- Check: open the PASS panel. The Deep Pass row is live, not greyed out.
- A Studio test purchase unlocks the paid row.

## 4. Re-test the fixes (cloud, `claude/world`)

- **F1 Shaft lift.** Use a LV 100 Nibbler, a LV 100 Pufferfish and a LV 100 Reef Shark, in a level-5 den.
  - Under the Sanctum shaft's mouth, hold **Space**: the fish rises straight up into the Hall without sliding along the vault.
  - Over the mouth in the Hall, hold **C**: the fish drops straight down.
  - Start 10 studs off the axis: the fish eases onto the axis as it rises.
  - Do the same at the Hall shaft. With the camera pitched up, **W** under a mouth also lifts.
  - Swimming level past a mouth must not pull the fish in.
  - Note any `[SpeedCheck]` line.
- **F2 Whale Fall** (Studio cadence).
  - After a whale ends, the water stays quiet for about 2 minutes before the next is announced.
  - Admin "Whale Fall now" while a whale is only announced: "… sinks in 5 s".
  - While one is feeding: it ends and a new one is announced.
  - Use the admin button until a whale falls in the **Sunken Ruins**. It should settle on open sand, visible from above, never under a lintel.
  - Do two more biomes as well.
- **F3 Tutorial and pressure.** A fresh fish still in the tutorial, teleported to the Open Blue's floor:
  - The meter reads **TOO DEEP FOR NOW · head back up above …** and never takes health.
  - After finishing the tutorial (admin), the same spot crushes as before.
- **F4 Pillar backing.** Snap on, in the Hall's pillared back room and the Sanctum:
  - Back a shelf and a table onto a pillar. The ghost goes green just clear of the pillar's base and places.
  - Walls still snap as before.
- **F5 Phone window titles.** Device Simulator (iPhone): open the Shop, Den menu, Wardrobe, Codes, Pass, Log and Daily windows. Every title and subtitle should sit right of Roblox's buttons, not under them.
- **F6 Banners.**
  - Bank a Haul, and right after it trigger an achievement banner (admin "Achievements: all done" just after the bank). The banner should come up after the bank celebration, not on top of it.
  - Do the same with a catch-track unlock if you can.
- **F7 Apex nametag.** 2 clients, with one fish crowned Apex (admin). From 70 studs the "★ APEX · … BOUNTY" line should be readable.
- **F8 Chum lure.** Burst 100 kg near a Barracuda about 100 studs away. Time how long it takes to reach the cloud; it should be about 10 s or less (it was ~15 s).
- **F9 Bait.** A LV 21 fish swallows a bait. Note the kg; expect about 60% of the overnight +73 kg with ×2 Mass.
- **F10 Regressions.** Tutorial start to finish, banking, a roll, the Treasure Wheel, Build mode snap and L layout, a pod join, a hook break-free.

## 5. Report and publish

- Write `docs/playtests/2026-10-14-pc-followup.md`: T1–T5, the Deep Pass id, F1–F10, the Output lines, and any `[SpeedCheck]` lines with what you were doing. Push `claude/core-systems`.
- **Publish** if T1–T5 and F1–F10 pass and no game script errors: File → Publish As → Update existing experience → **Apex Abyss** → Overwrite, keeping it **private**.
- If this session's permission check refuses it again, stop there and say so. Connor will publish from the saved `ApexAbyss.rbxl`.
- Optional, if a real controller is plugged in: X1 hook mashing (RB/RT), 10 taps to break free.
