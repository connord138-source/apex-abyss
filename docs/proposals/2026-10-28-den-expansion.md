# Den expansion and a passive den (proposal, 2026-10-28)

**For the owner's approval. Nothing here is built yet.**

The owner asked: "a coral upgrade that extends the size of your den", "maybe choice of different rooms, open layout, we could add a passive element to the den as well. Tons of roblox games have passive elements that keep players coming back."

## Where dens stand

- **Five levels:** Nook, then Burrow (1,000 coral), Hall (12,000), Grotto (45,000) and Sanctum (150,000), holding 24 / 48 / 80 / 125 / 180 things.
- **The passive element:** the Coral Garden grows coral and shells for up to 8 hours.
- **The problem:** past Sanctum, coral has nothing big left to buy at the end of the game.

## Recommendation: all three, built in this order

### 1. Wings: rooms you choose (the size upgrade, with choices)

Past Sanctum, the den grows sideways. Each den has **4 wing doorways**, two on each side of the main storeys. Each wing is a room you pick and buy with coral, built onto the doorway you choose. You can swap a wing later for half its price back.

| Wing | What it is | Price |
|---|---|---|
| **Aquarium Hall** | A long gallery of display tanks: the passive element (2) | 250,000 |
| **Trophy Gallery** | Boss trophies, titles and your best catches on plinths. Visitors see your records | 250,000 |
| **Grotto Pool** | A sunken pool room with a second Haul Pool (bank closer to the back) and a waterfall of bubbles | 400,000 |
| **Observatory** | A glass-domed room looking out into a deep-sea diorama with whales and jellies passing; a quiet spot for screenshots | 600,000 |
| **Great Hall** | Simply big: double capacity (+90 things) and a high vault for tall pieces | 900,000 |

Each wing also adds capacity (+40, or +90 for the Great Hall). Wings are the late-game coral sink: about 20–60 hours of top-level income for the set.

**Open layout:** an **Open Plan** upgrade at the Den Mason (75,000) knocks the walls out between the main rooms on each storey, so the Nook, Burrow and Hall become one wide hall. It's a switch: take it, and Build mode places across the open floor. It can be undone.

### 2. The Aquarium: a passive income that grows with the Catch Log

The Aquarium Hall's tanks, plus **2 starter tanks on the Nook's back wall at every level** so everyone gets the loop early, each show one rare fish you've caught: any species at any rarity from your Catch Log. A tank earns coral every hour, online or off, up to 12 hours, by the fish's rarity:

| Rarity | Coral / hour | Shells / hour |
|---|---|---|
| Silver | 15 | 0.5 |
| Golden | 45 | 1 |
| Glowing | 120 | 2 |
| Crystal | 300 | 4 |
| Prism | 700 | 8 |

- **Tanks:** 2 to start, +1 each den level (7 at Sanctum), +8 with the Aquarium Hall.
- **Why it brings players back:**
  - Every rarer catch upgrades a tank's earnings.
  - The 12-hour cap brings players back twice a day.
  - A full Prism aquarium is a flex visitors can see.
- **Fit with existing loops:**
  - It doesn't compete with the Garden: the Garden is level-based, the Aquarium is catch-based.
  - It feeds the reason to hunt rare fish, which now spawn twice as often.
- **Collecting:** swim past the tanks (like the Garden), or a COLLECT ALL at the den menu.
- **Feeding (optional):** feed the tanks once a day for ×1.5 earnings that day, which builds a daily-login habit. Costs 1 Kelp DNA per tank.

### 3. Den visits that count (the social loop)

- Visitors can **admire** a den once a day: a heart at the den's sign.
- Hearts make a weekly **Best Dens** leaderboard. The top 3 get a title and a sign frame.
- The den sign shows the heart count.
- Owners get a toast when someone admires their den, and a small coral tip (25).

## Costs and what's needed

- **Wings:** about 5 room shells built with DenCarve (the same tools as today's storeys), placed at the wing doorways. No new Terrain systems.
- **New models (Tripo, about 30 credits each):**
  - **Aquarium:** a glass display tank in 2 sizes (wall and floor) and a tank sign. The fish inside are the prey models, drawn like the reef clouds.
  - **Observatory:** a dome window frame. The diorama reuses the giants and jellies.
  - **Trophy Gallery:** plinths, which can be part-built.
- **Save data:** `den.wings` (doorway → wing id), `den.open` (open plan) and `den.tanks` (slot → { prey, rarity, since }). Old saves are untouched.
- **Pacing check:** rerun the economy numbers once the rates are agreed. The Aquarium at 7 Golden tanks is about 315 coral an hour, roughly the Garden's at Sanctum.

## Decisions needed

1. Wings as listed (prices, the five rooms)?
2. The Aquarium rates and tank counts, and whether to have daily feeding?
3. Open Plan, yes or no?
4. Den hearts and the Best Dens board?
