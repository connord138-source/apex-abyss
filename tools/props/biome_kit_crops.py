"""Cuts each prop off the approved biome kit sheets (assets/tripo/biome_concepts/<Biome>Kit.png,
tools/tripo_jobs_biome_concepts.json; boards in assets/concepts/biome_detail/) into its own
square reference on the sheet's flat teal, for Tripo image_to_model
(tools/tripo_jobs_biome_<biome>.json).

    python3.11 tools/props/biome_kit_crops.py

Writes assets/tripo/biome_models/refs/<Name>.png. The boxes were found by segmenting each
sheet (pixels far from the border's median colour, closed and filled, as components).
"""

import pathlib

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
SHEETS = ROOT / "assets/tripo/biome_concepts"
OUT = ROOT / "assets/tripo/biome_models/refs"

# (sheet, box (x0, y0, x1, y1) on the 1024 sheet, name)
CROPS = [
    ("Wreck", (29, 128, 392, 392), "WreckCannon"),
    ("Wreck", (419, 98, 710, 443), "WreckAnchor"),
    ("Wreck", (756, 89, 985, 447), "WreckFigurehead"),
    ("Wreck", (39, 526, 324, 931), "WreckWheelBell"),
    ("Wreck", (376, 640, 774, 922), "WreckBarrels"),
    ("Trench", (66, 42, 322, 364), "TrenchCrystals"),
    ("Trench", (426, 53, 651, 362), "TrenchGlowTubes"),
    ("Trench", (778, 57, 933, 357), "GlassSponge"),
    ("Trench", (64, 401, 467, 724), "LeviathanSkull"),
    ("Trench", (74, 732, 452, 973), "GlowEggs"),
    ("Trench", (565, 699, 972, 969), "BoneHeap"),
    ("Kelp", (49, 48, 452, 448), "LobsterTrap"),
    ("Kelp", (546, 58, 992, 306), "SunkenRowboat"),
    ("Kelp", (621, 327, 957, 591), "SeaOtter"),
    ("Kelp", (29, 626, 385, 907), "UrchinRock"),
    ("Kelp", (421, 565, 622, 979), "KelpBuoy"),
    ("Kelp", (687, 587, 994, 970), "SeaGrass"),
    ("Reef", (22, 82, 340, 346), "TableCoral"),
    ("Reef", (377, 93, 661, 332), "GiantClam"),
    ("Reef", (699, 77, 1003, 349), "GardenEels"),
    ("Reef", (407, 666, 634, 966), "PillarCoral"),
    ("Reef", (23, 679, 348, 953), "DomeCoral"),
    ("Reef", (714, 665, 1000, 963), "BranchFan"),
    ("Blue", (21, 102, 557, 366), "WhaleSkeleton"),
    ("Blue", (597, 54, 961, 351), "Sargassum"),
    ("Blue", (572, 369, 986, 578), "JellyChain"),
    ("Blue", (65, 606, 324, 974), "CoralPinnacle"),
]

SIZE = 768
MARGIN = 0.14


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sheets: dict[str, Image.Image] = {}
    for sheet, box, name in CROPS:
        if sheet not in sheets:
            sheets[sheet] = Image.open(SHEETS / f"{sheet}Kit.png").convert("RGB").resize((1024, 1024))
        image = sheets[sheet]
        pixels = np.asarray(image).astype(np.float32)
        border = np.concatenate(
            [pixels[:8].reshape(-1, 3), pixels[-8:].reshape(-1, 3), pixels[:, :8].reshape(-1, 3), pixels[:, -8:].reshape(-1, 3)]
        )
        background = tuple(int(v) for v in np.median(border, axis=0))
        x0, y0, x1, y1 = box
        pad = 6
        crop = image.crop((max(x0 - pad, 0), max(y0 - pad, 0), min(x1 + pad, 1024), min(y1 + pad, 1024)))
        side = int(max(crop.width, crop.height) * (1 + MARGIN * 2))
        square = Image.new("RGB", (side, side), background)
        square.paste(crop, ((side - crop.width) // 2, (side - crop.height) // 2))
        square.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / f"{name}.png")
        print("wrote", name)


if __name__ == "__main__":
    main()
