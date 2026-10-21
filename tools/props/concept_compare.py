"""A landmark's approved concept beside its preview render, for judging how close the
build reads (owner, 2026-10-21: "look how much different your hole looks from the
mockup").

    python3 tools/props/concept_compare.py <concept.png> <render.png> <out.jpg> [label]

Both are cropped to the same aspect (the concept is square; the render's middle is
taken) and set side by side at the same height.
"""

import sys

from PIL import Image, ImageDraw, ImageFont


def square(image: Image.Image, size: int) -> Image.Image:
    w, h = image.size
    side = min(w, h)
    box = ((w - side) // 2, (h - side) // 2, (w + side) // 2, (h + side) // 2)
    return image.crop(box).resize((size, size), Image.LANCZOS)


def main():
    concept, render, out = sys.argv[1], sys.argv[2], sys.argv[3]
    label = sys.argv[4] if len(sys.argv) > 4 else ""
    size = 640
    a = square(Image.open(concept).convert("RGB"), size)
    b = square(Image.open(render).convert("RGB"), size)
    sheet = Image.new("RGB", (size * 2 + 12, size + 40), (16, 32, 44))
    sheet.paste(a, (0, 40))
    sheet.paste(b, (size + 12, 40))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("tools/marketing/fonts/LilitaOne-Regular.ttf", 26)
    except OSError:
        font = ImageFont.load_default()
    draw.text((10, 6), "CONCEPT", font=font, fill=(255, 205, 92))
    draw.text((size + 22, 6), f"BUILD {label}".strip(), font=font, fill=(120, 236, 220))
    sheet.save(out, quality=90)
    print("wrote", out)


if __name__ == "__main__":
    main()
