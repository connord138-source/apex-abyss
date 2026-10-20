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

## Description (draft; Roblox allows 1,000 characters)

```
🦈 Start as a tiny fish. Eat your way to the top of the food chain!

🐟 EAT & GROW: swim into smaller fish to swallow them, bite fish your size, and dodge anything big enough to swallow YOU.
🏠 BANK YOUR HAUL: swim home to your den to keep what you ate. Get eaten and it's gone!
🌊 RIDE THE TIDES: every 20 minutes the tide turns. Golden Hour, Blood Tide, Sardine Run, Bioluminescent Night and the rare Prism Tide.
🦈 WORLD BOSSES: team up against the Megalodon and the Giant Squid for exclusive trophies and shades.
🗺️ 7 BIOMES: Kelp Shallows, Coral Reef, Shipwreck Graveyard, Open Blue, Sunken Ruins, Hydrothermal Vents and the dark Abyssal Trench.
🐠 6 FISH TO PLAY: Nibbler, 'Cuda, Pufferfish, Moray Eel, Reef Shark and Anglerfish.
✨ RARE SHADES: collect shells and roll, from Neon Tetra to Prismatic.
💰 TREASURE MAPS: follow the sonar and dig up chests.
🪸 YOUR DEN: build it, furnish it, show off your trophies.
🎁 Daily rewards and a free Tide Pass.
```
