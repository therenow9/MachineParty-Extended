"""Draws mods/couch_lobby/glasses_selection.png and name_new.png (the saved names' pencil).

The glasses match the game's 26x26 local-lobby picker icons (hat_selection.png,
suit_selection2.png): a white frame and a white glyph, each with a 1px black
drop shadow down-right, on a transparent background. The pencil is the same
white with its shadow, without a frame, cropped to 37x10: the name list
stretches its shaft across the list's bar.
"""
from pathlib import Path
from PIL import Image

SIZE = 26
WHITE = (255, 255, 255, 255)
BLACK = (0, 0, 0, 255)
DIR = Path(__file__).resolve().parent.parent / "mods" / "couch_lobby"
WIDE = 44


def rect(mask, x0, y0, x1, y1):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            mask.add((x, y))


def frame(w=SIZE):
    m = set()
    r = w - 2
    rect(m, 0, 0, r, 0)
    rect(m, 0, 24, r, 24)
    rect(m, 0, 0, 0, 24)
    rect(m, r, 0, r, 24)
    return m


def sunglasses():
    m = set()
    rect(m, 3, 9, 22, 10)    # brow bar + temple stubs
    rect(m, 5, 11, 11, 14)   # left lens
    rect(m, 6, 15, 10, 15)
    rect(m, 14, 11, 20, 14)  # right lens
    rect(m, 15, 15, 19, 15)
    return m


# A pencil lying flat, point to the left, drawn on a WIDE canvas.
# Rows 8-16: the cone runs x 4-11 (solid at the point), the shaft 12-31 with its facet line,
# the ferrule 32-34, the eraser 35-39.
def pencil():
    m = set()
    for x in range(4, 12):
        half = (x - 4) * 4 // 7
        for y in range(12 - half, 12 + half + 1):
            if x <= 6 or abs(y - 12) == half:
                m.add((x, y))
    for x in range(12, 40):
        for y in range(8, 17):
            if (x, y) in ((39, 8), (39, 16)):
                continue
            if y in (8, 16) or x in (12, 31, 32, 33, 34, 35, 39) or (x < 32 and y == 12):
                m.add((x, y))
    return m


def draw(img, mask):
    px = img.load()
    for x, y in mask:
        sx, sy = x + 1, y + 1
        if (sx, sy) not in mask and sx < img.width and sy < img.height and px[sx, sy] != WHITE:
            px[sx, sy] = BLACK
    for x, y in mask:
        px[x, y] = WHITE


# The pencil alone, cropped to it and its shadow (37x10). Columns 10-26 are all the same, so
# name_panel.gd makes a pencil of any length by repeating column 10 (its SHAFT_FROM, PENCIL_ENDS).
def bare_pencil():
    img = Image.new("RGBA", (WIDE, SIZE), (0, 0, 0, 0))
    draw(img, pencil())
    return img.crop((4, 8, 41, 18))


def main():
    DIR.mkdir(parents=True, exist_ok=True)
    glasses = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw(glasses, frame())
    draw(glasses, sunglasses())
    for name, img in (("glasses_selection.png", glasses), ("name_new.png", bare_pencil())):
        img.save(DIR / name)
        print(f"wrote {DIR / name}")


if __name__ == "__main__":
    main()
