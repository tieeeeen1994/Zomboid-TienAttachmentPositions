"""Builds the mod's icon, poster and Workshop preview: the mod's name in a plain font, on a transparent background.

    python3 scripts/make_art.py      (py scripts/make_art.py on Windows)

Writes:
  Contents/mods/TienAttachmentPositions/42/icon.png      128x128
  Contents/mods/TienAttachmentPositions/42/poster.png    512x512
  preview.png                                            512x512
"""

import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
MOD = os.path.join(REPO, "Contents", "mods", "TienAttachmentPositions", "42")
FONTS = ["C:/Windows/Fonts/arial.ttf", "/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Helvetica.ttc"]
LINES = ["Tien's", "Attachment", "Positions"]
COLOUR = (255, 255, 255, 255)


def font(px):
    path = next(p for p in FONTS if os.path.exists(p))
    return ImageFont.truetype(path, px)


def text_image(size, margin):
    """The lines centred, at the largest font size whose widest line fits inside the margins."""
    room = size - margin * 2
    px = size
    while px > 6:
        f = font(px)
        widths = [f.getbbox(line)[2] - f.getbbox(line)[0] for line in LINES]
        ascent, descent = f.getmetrics()
        line_h = round((ascent + descent) * 1.05)
        if max(widths) <= room and line_h * len(LINES) <= room:
            break
        px -= 1
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    top = (size - line_h * len(LINES)) / 2
    for i, line in enumerate(LINES):
        d.text((size / 2, top + line_h * (i + 0.5)), line, font=f, fill=COLOUR, anchor="mm")
    return img


def main():
    os.makedirs(MOD, exist_ok=True)
    text_image(128, 6).save(os.path.join(MOD, "icon.png"))
    art = text_image(512, 32)
    art.save(os.path.join(MOD, "poster.png"))
    art.save(os.path.join(REPO, "preview.png"))
    print("Wrote icon.png, poster.png and preview.png")


if __name__ == "__main__":
    main()
