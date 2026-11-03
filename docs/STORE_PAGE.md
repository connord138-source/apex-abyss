# Store page (Creator Hub)

The experience is "Apex Tide 🦈 Eat & Grow" (universe 10769954850, place 83646578075996;
named "Apex Abyss" until 2026-10-20), private until Connor makes it public. Everything to upload is in `marketing/` (committed); rebuild it with
`python3 tools/marketing/compose.py` (see the script's header for the whole pipeline).

## Files

| File | Where it goes | What it shows |
|---|---|---|
| `icon_512.png` | Experience icon (512×512) | The Nibbler fleeing a Megalodon's jaws: eat or be eaten |
| `icon_512_alt.png` | Runner-up icon | The Nibbler chomping at you, a shark's shadow behind |
| `thumb_1_eat.jpg` | Thumbnail 1 (lead) | Logo; the Nibbler gulping a minnow, the Megalodon looming. "EAT. GROW. BECOME THE APEX!" |
| `thumb_2_boss.jpg` | Thumbnail 2 | Six player fish biting the Megalodon. "WORLD BOSSES!" |
| `thumb_3_dark.jpg` | Thumbnail 3 | The Giant Squid in the pitch-dark Trench, a lure and a lantern. "HUNT IN THE DARK!" |
| `thumb_4_grow.jpg` | Thumbnail 4 | Fry to apex, each eating the one before. "START SMALL. EAT BIG!" |
| `thumb_5_shades.jpg` | Thumbnail 5 | Prismatic, Ghost, Magma, Nebula, Divine. "RARE SHADES!" |
| `thumb_6_treasure.jpg` | Thumbnail 6 | A chest dug up in the shipwrecks, the map beside it. "TREASURE MAPS!" |
| `thumb_7_biomes.jpg` | Thumbnail 7 | Kelp, reef arches and wrecks side by side. "EXPLORE 7 BIOMES!" |
| `thumb_8_den.jpg` | Thumbnail 8 | In-game: a furnished Grotto, the full Coral Garden. "BUILD YOUR DEN!" |
| `thumb_9_megalodon.jpg` | Thumbnail 9 | In-game: the Megalodon's jaws. "FIGHT THE MEGALODON!" Provisional: retake it after the open-water rework (it's murky and staged) |
| `thumb_10_reveal.jpg` | Thumbnail 10 | In-game: the roll reveal landing on Nebula. "ROLL RARE SHADES!" |
| `logo.png` | Anywhere (transparent); also the start screen's title (`Config/Textures` `logo`) | APEX TIDE, a foam crest between the lines |
| `logo_alt.png` | Runner-up logo | APEX TIDE with a wave curling round TIDE |

**Hold back `thumb_6_treasure.jpg`:** the colour screen flags its parchment map and sand
as a 5.6% skin-tone region (over 5.0; the classifier scores it 0.00). The rest pass
(2026-10-20, `screen_shades.py` on the logos, icon and thumbnails).

Roblox shows up to 10 thumbnails; the lead one matters most. Everything shown is in the game
(bosses, the Trench, growth stages, the shades named, treasure maps, the seven biomes).

## Pass and product icons

Made 2026-11-02 the way the Deep Pass icon was: real renders of the game's models on that
card (navy glass, gold frame, the UI's gold lettering), with no image model involved and
every word set by the script. Rebuild them with `python tools/marketing/product_icons.py all
<dir>` (the renders go in `<dir>`; about 7 minutes of CPU; the script's header explains
each step), then run `python tools/shades/screen_shades.py marketing/icon_*_512.png`. All
twelve pass (classifier 0.001 to 0.120, skin tone 2.5 to 7.6%, pale 0.5% at most). Each one
is uploaded as that item's icon in Creator Hub → the experience → Monetization → **Passes**
or **Developer Products** → the item → its image (512×512 PNG). The Store tab shows a pass's
icon in a circle, so the four pass icons keep their title and subject inside it. The Deep
Pass product keeps `deep_pass_512.png` (`tools/marketing/pass_icon.py`).

| File | Item (id) | What it shows |
|---|---|---|
| `icon_2023286343_512.png` | Pass: ×2 Mass | "×2 MASS": the Nibbler big, a small copy of it behind, teal growth rings |
| `icon_2021282363_512.png` | Pass: VIP | "VIP": the Reef Shark in gold rays and glints |
| `icon_2022452343_512.png` | Pass: Den Expansion | "BIGGER DEN": a den doorway of Grotto stones with brass lanterns; the Sponge Sofa, Coral Lamp, Angler Lamp and Pearl Pedestal on a rug; a gold +25 badge |
| `icon_2022290332_512.png` | Pass: Deep Garden | "DEEP GARDEN": the den's Coral Garden bed (stones over its teal glow) grown full of the reef's corals |
| `icon_3717380340_512.png` | Product: Second Chance | "SECOND CHANCE": the Nibbler wearing the red and white life ring |
| `icon_3717380401_512.png` | Product: Server Frenzy | "FRENZY": all six playable fish bursting out from a gold ×2 badge |
| `icon_3717380436_512.png` | Product: Double Haul | "DOUBLE HAUL": one haul (three prey tied with a kelp band), a gold ×2 badge, a SMALL HAUL tag |
| `icon_3717380455_512.png` | Product: Double Haul (Big) | The same with two hauls, BIG HAUL |
| `icon_3717380479_512.png` | Product: Double Haul (Huge) | The same with three hauls, HUGE HAUL |
| `icon_3717380541_512.png` | Product: Double Haul (ad) | The small one (the same image: the ad doubles a small Haul) |
| `icon_3717380495_512.png` | Product: Shell Pouch | "100 SHELLS": a net pouch full of pearl and golden shells, a few spilled at its foot |
| `icon_3717380526_512.png` | Product: Shell Chest | "600 SHELLS": the Treasure Chest heaped with shells |

## How the art was made (2026-10-09)

- Key art: Nano Banana Pro through the Tripo API (`tools/tripo_jobs_marketing.json`, 10
  credits each, 130 credits in all), each with a reference sheet of 2–3 approved concepts
  for the style (`compose.py refs`). The API only returns 1024×1024, so each scene was
  painted in a 16:9 strip of the square, cropped out and upscaled 2× with EDSR
  (`compose.py sr`). The hero image (`HeroWide`) has no strip; a band round its subjects is
  cropped.
- All text is set by `compose.py` (Luckiest Guy and Lilita One), never by the model.
- The logo was painted on magenta and keyed (`key_magenta`): its colours are white, aqua,
  blue and navy, which a green screen would have eaten into. The APEX TIDE logo
  (2026-10-20, `tools/tripo_jobs_logo_tide.json`) is an edit of the APEX ABYSS one with
  that logo as the reference: the APEX line kept, TIDE drawn in its style. The model left
  a faint blocky band near the top of the screen, which `key_magenta` drops.
- Lessons: the image API ignores an aspect setting; asking for "a calm corner for the
  title" painted a hard black box into the scene (the first squid), so ask for a letterboxed
  16:9 strip with plain navy above and below instead.

## In-game captures (thumbnails 8–10)

Taken in Studio by the PC session, saved as PNG in `marketing/raw/` at 1920×1080 or larger,
with the HUD, nametags and Roblox's own UI hidden (no text in the shot; the script adds it):

| File | Shot |
|---|---|
| `shot_8_den.png` | An upgraded den (Grotto) with furniture, glowing lamps and banners, the trophy wall and a full Coral Garden; your fish in front, lit, from a low three-quarter angle |
| `shot_9_megalodon.png` | The Megalodon in the Open Blue, mouth open, with two or three player fish beside it for scale, low and dramatic |
| `shot_10_reveal.png` | The roll reveal landing on a rare shade (Mythic or Legendary), the reel and the card's glow (this one keeps the reveal's own UI) |

## Description (Roblox allows 1,000 characters; ~940 here)

Rewritten 2026-11-02 for the game as it is now: players are never swallowed (every fight is
bitten out, since 2026-10-20), plus rare catches and the Catch Log, schooling and the Apex
bounty, the den's aquarium and hearts, and boost trails. Paste it into Creator Hub →
the experience → Basic Info → Description.

```
🦈 Start as a tiny fish. Eat your way to the top of the food chain!

🐟 EAT & GROW: swallow smaller fish whole, then swim home to your den to bank your Haul. Get eaten on the way and it bursts into chum!
⚔️ FIGHT: players are never swallowed, every fight is bitten out. School up with friends to take down a bigger fish, or hunt the Apex for its bounty.
✨ RARE CATCHES: Silver, Golden, Glowing, Crystal and Prism fish swim in the schools. Fill your Catch Log to unlock skins.
🌊 TIDES: the sea changes every 20 minutes. Golden Hour, Blood Tide, Sardine Run, Bioluminescent Night and the rare Prism Tide.
🦈 WORLD BOSSES: the Megalodon and the Giant Squid.
🗺️ 7 BIOMES, from the Kelp Shallows to the Abyssal Trench.
🐠 6 FISH TO PLAY, each with its own ability.
🎨 Roll skins, rare parts and variants. Earn boost trails.
🏠 Build your den, fill its aquarium, win hearts from visitors.
🎁 Daily rewards, playtime gifts and a free Tide Pass.
```

## Badges, invites and notifications (Creator Hub setup, 2026-11-03)

The game's side is built (`src/shared/Config/Social.luau`, see CLAUDE.md "Getting
seen"). Each needs a few things made in Creator Hub → Creations → Apex Tide (the
TideBite Studios community's), and the ids sent back to go in `Config/Social.luau`.
Until then each is simply off.

### Badges (Engagement → Badges → Create a Badge)

Roblox gives 5 free a day, so make 1–5 first and 6–10 the next day (more cost 100
Robux each). Upload the image, paste the name and description, create, then copy the
badge's id. Every image passed the moderation screen (nsfw 0.05 at most).

| # | Image | Name | Description |
|---|---|---|---|
| 1 | `badge_welcome_512.png` | Welcome to Apex Tide | You dived into Apex Tide. Eat, grow and become the apex! |
| 2 | `badge_graduate_512.png` | Tutorial Graduate | Finished the tutorial: hunted, banked, spun the wheel and rolled. |
| 3 | `badge_golden_512.png` | Golden Catch | Caught a Golden fish. |
| 4 | `badge_boss_512.png` | Boss Hunter | Helped bring down the Megalodon or the Giant Squid. |
| 5 | `badge_level25_512.png` | Rising Predator | Reached level 25 with any fish. |
| 6 | `badge_friend_512.png` | School's In | A friend you invited finished the tutorial. |
| 7 | `badge_treasure_512.png` | X Marks the Spot | Dug up a treasure chest. |
| 8 | `badge_apex_512.png` | Apex Hunter | Ate the Apex and claimed its bounty. |
| 9 | `badge_crystal_512.png` | Crystal Clear | Caught a Crystal fish. |
| 10 | `badge_level100_512.png` | Top of the Food Chain | Reached level 100 with any fish. |

Players who did these before a badge existed get it on their next visit. Rebuild the
images with `python tools/marketing/badge_icons.py all <dir>` (see its header).

### Friend invites: the reward banner (Engagement → Referral Rewards → Add Reward Details)

Roblox shows this banner on top of the invite prompt (the Shop's and the Pod window's
INVITE). The game has to have been live a day first. Icon `badge_friend_512.png`;
reward name "A gift for you and your friend"; description "Your friend gets 500
coral, 50 shells and a wheel spin. You get 100 shells and a spin when they finish the
tutorial."; limit 10 rewards per inviter; no end date. Save, then Publish. Nothing to
send back.

### Notifications

1. **Three notification strings** (Engagement → Notifications → Create a Notification
   String). For each, a name for us and the message below exactly (the `{...}` words
   are filled in by the game), then ⋯ → Copy Asset ID and send it:
   - `garden`: `Your Coral Garden is full: {coral} coral is waiting in your den!`
   - `spins`: `Your free Treasure Wheel spins are back. Come spin for a rare skin!`
   - `friend`: `{friend} finished the tutorial from your invite. Your reward is waiting!`
2. **An Open Cloud API key** (Creator Hub → Open Cloud → API Keys → Create API Key,
   made from the TideBite Studios community's dashboard so it belongs to the
   community): add the **user-notification** API with **write**, for the Apex Tide
   experience; leave **Restrict IP addresses** off (Roblox's servers call it) and no
   expiry. Copy the key (it shows once). Roblox switches a key off after 60 days
   unused; the notifications keep it in use.
3. **The Secret** (the experience → Secrets → Create Secret): name `Notifications`,
   the key as the secret, domain `apis.roblox.com`. Never paste the key anywhere else.
4. **Allow HTTP Requests** (Studio → File → Experience Settings → Security → on, then
   save; or Creator Hub's settings for the experience).

Roblox delivers at most one a day per experience, only to players 13+ who allowed
them, and only once the game has 100 visits. The game asks players first with its own
card (after a few banks), then Roblox's prompt.
