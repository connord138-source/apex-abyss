--!strict
-- Image assets the client draws with, by key: the id of each once it's uploaded
-- to the owner's account as an Image (Decal), 0 until then (a look that needs one
-- falls back to what it did before). The files are in assets/textures/.
--
--   sheen*: tiling layers that slide across the top skins (tools/shades/
--           make_sheens.py; Shared/Cosmetics `sheen`)
--   mapChart: the real seafloor from above, behind the maps (MapDraw)
--   rug*:   top-down rug art, a Decal on each rug (Shared/DenItems)
--   stars:  the Hatch & Snatch galaxy starfield, already on the owner's account
--           (an Image works in every experience its uploader owns)
return {
	sheenPrismatic = 121725548181831, -- assets/textures/sheen_prismatic.png
	sheenSparkle = 120522622169733, -- assets/textures/sheen_sparkle.png
	sheenGold = 70886974600925, -- assets/textures/sheen_gold.png
	sheenVeil = 91311902351808, -- assets/textures/sheen_veil.png
	-- v9 (2026-10-16): coloured layers for the Rare+ skins
	sheenLava = 77584183834097, -- assets/textures/sheen_lava.png
	sheenCaustic = 70603076372832, -- assets/textures/sheen_caustic.png
	sheenFacets = 102847350858119, -- assets/textures/sheen_facets.png
	sheenCurrent = 75408604446814, -- assets/textures/sheen_current.png
	sheenBolt = 136653557283341, -- assets/textures/sheen_bolt.png
	stars = 129645056585841, -- hatch-and-snatch assets/textures/galaxy_sky.png
	-- fx*: particle images for the skin effects and boost trails (Shared/Fx;
	-- tools/shades/make_fx.py); 0 = Roblox's own particle images
	fxSwirl = 73493788115178, -- assets/textures/fx_swirl.png
	fxMist = 128648421420337, -- assets/textures/fx_mist.png
	fxBubble = 131664697618697, -- assets/textures/fx_bubble.png
	fxStar = 103216324017752, -- assets/textures/fx_star.png
	fxFlame = 82338604318401, -- assets/textures/fx_flame.png
	-- The sky as water (owner, 2026-10-28: "way to get rid of the skybox?"): six faces
	-- of lit water over, a deep-blue gradient round and navy under
	-- (OceanController.waterSky); 0 keeps Roblox's default sky. The sky and surface are
	-- the PC chat's: set these only with the owner's go-ahead
	skyUp = 0, -- assets/textures/sky_water_up.png
	skySide = 0, -- assets/textures/sky_water_side.png
	skyDown = 0, -- assets/textures/sky_water_down.png
	fxSpark = 123443623099259, -- assets/textures/fx_spark.png
	-- the APEX TIDE logo over the start screen in place of the lettering
	-- (tools/marketing/compose.py; StartController); 0 = the lettering
	logo = 129818407566312, -- marketing/logo.png
	-- the sea chart behind the minimap and the full map (tools/map/make_chart.py;
	-- src/client/MapDraw)
	mapChart = 102792114289670, -- assets/textures/map_chart.png
	-- rug*: the den rugs' top-down art (tools/props/rug_textures.py; Shared/DenItems)
	rugBraidedKelpRug = 135571701796831, -- assets/textures/rug_BraidedKelpRug.png
	rugCoralRug = 73878696309005, -- assets/textures/rug_CoralRug.png
	rugWaveMosaicRug = 79461762014413, -- assets/textures/rug_WaveMosaicRug.png
	rugPlanktonRug = 132153678493833, -- assets/textures/rug_PlanktonRug.png
}
