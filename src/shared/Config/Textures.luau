--!strict
-- Image assets the client draws with, by key: the id of each once it's uploaded
-- to the owner's account as an Image (Decal), 0 until then (a look that needs one
-- falls back to what it did before). The files are in assets/textures/.
--
--   sheen*: tiling layers that slide across the top skins (tools/shades/
--           make_sheens.py; Shared/Cosmetics `sheen`)
--   stars:  the Hatch & Snatch galaxy starfield, already on the owner's account
--           (an Image works in every experience its uploader owns)
return {
	sheenPrismatic = 121725548181831, -- assets/textures/sheen_prismatic.png
	sheenSparkle = 120522622169733, -- assets/textures/sheen_sparkle.png
	sheenGold = 70886974600925, -- assets/textures/sheen_gold.png
	sheenVeil = 91311902351808, -- assets/textures/sheen_veil.png
	stars = 129645056585841, -- hatch-and-snatch assets/textures/galaxy_sky.png
}
