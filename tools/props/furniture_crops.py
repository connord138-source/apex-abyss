"""Cuts each furniture piece off its board on a clean background (its own mask,
dilated, the rest painted the board's flat colour), padded square and upscaled to
768 for Tripo image_to_model (tools/tripo_jobs_furniture_models.json), plus a
contact sheet. Run furniture_segment.py first.

    python tools/props/furniture_crops.py . assets/tripo/furniture_crops
"""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

here = os.path.dirname(os.path.abspath(sys.argv[0]))
repo = sys.argv[1]
outdir = sys.argv[2]
os.makedirs(outdir, exist_ok=True)
NAMES = {
    "FurnKelpCottage": ["KelpArmchair", "KelpHammock", "ScallopLamp", "DriftwoodShelf", "BarrelTable", "BraidedKelpRug"],
    "FurnReefPalace": ["CoralThrone", "ClamBed", "BrainOttoman", "StaghornChandelier", "FanCoralScreen", "CoralRug"],
    "FurnShipwreck": ["CaptainsDesk", "ShipsWheel", "ShipLantern", "BronzeCannon", "CargoStack", "ShipAnchor"],
    "FurnSunkenTemple": ["RuneThrone", "ColumnPlanter", "TealBrazier", "GlyphTablet", "GrouperStatue", "WaveMosaicRug"],
    "FurnVentForge": ["LavaFirePit", "ObsidianTable", "LavaLamp", "SulfurCrystals", "VentCauldron", "TubeWormPlanter"],
    "FurnAbyssGlow": ["JellyChandelier", "AnglerLamp", "GlowCoralBed", "VoidThrone", "PlanktonRug", "KrakenEyePedestal"],
    "FurnTrophies": ["MegalodonJawArch", "KrakenEyeLantern", "SharkToothPlaque", "BronzeTentacle", "TreasurePile", "ReefGlobe"],
}
boxes = json.load(open(os.path.join(here, "furniture_boxes.json")))
tiles = []
for path, info in boxes.items():
    board = os.path.splitext(os.path.basename(path))[0]
    im = np.asarray(Image.open(os.path.join(repo, path)).convert("RGB")).astype(np.float32)
    bg = np.array(info["bg"], dtype=np.float32)
    d = np.sqrt(((im - bg) ** 2).sum(axis=2))
    mask = d > 38
    mask = ndimage.binary_closing(mask, iterations=6)
    mask = ndimage.binary_fill_holes(mask)
    mask = ndimage.binary_opening(mask, iterations=2)
    lab, _ = ndimage.label(mask)
    for name, b in zip(NAMES[board], info["boxes"]):
        own = ndimage.binary_dilation(lab == b["label"], iterations=12)
        # Soft edge so the cut isn't a hard line
        soft = ndimage.gaussian_filter(own.astype(np.float32), 3)[..., None]
        clean = im * soft + bg * (1 - soft)
        x0, y0, x1, y1 = b["x0"], b["y0"], b["x1"], b["y1"]
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        side = max(x1 - x0, y1 - y0) * 1.18 + 24
        canvas = Image.new("RGB", (int(side), int(side)), tuple(int(v) for v in bg))
        src = Image.fromarray(clean.clip(0, 255).astype(np.uint8))
        crop = src.crop((int(cx - side / 2), int(cy - side / 2), int(cx + side / 2), int(cy + side / 2)))
        # Outside the board (crop past the edge) shows black: paint it background
        arr = np.asarray(crop).copy()
        L, T = int(cx - side / 2), int(cy - side / 2)
        for yy in range(arr.shape[0]):
            for xx in (range(arr.shape[1]) if (T + yy < 0 or T + yy >= im.shape[0]) else []):
                arr[yy, xx] = bg
        if L < 0:
            arr[:, : -L] = bg
        if L + arr.shape[1] > im.shape[1]:
            arr[:, im.shape[1] - L :] = bg
        crop = Image.fromarray(arr).resize((768, 768), Image.LANCZOS)
        crop.save(os.path.join(outdir, f"{name}.png"))
        tiles.append((name, crop))
# Contact sheet
cols = 6
sheet = Image.new("RGB", (cols * 256, (len(tiles) + cols - 1) // cols * 276), (30, 30, 30))
dr = ImageDraw.Draw(sheet)
for i, (name, crop) in enumerate(tiles):
    x, y = i % cols * 256, i // cols * 276
    sheet.paste(crop.resize((256, 256)), (x, y))
    dr.text((x + 4, y + 258), name, fill=(255, 255, 255))
sheet.save(os.path.join(outdir, "_contact.jpg"), quality=85)
print(len(tiles))
