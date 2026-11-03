"""Draws mods/couch_lobby/glasses_selection.png.

Matches the game's 26x26 local-lobby picker icons (hat_selection.png,
suit_selection2.png): a white frame and a white glyph, each with a 1px
black drop shadow down-right, on a transparent background.
"""
from pathlib import Path
from PIL import Image

SIZE = 26
WHITE = (255, 255, 255, 255)
BLACK = (0, 0, 0, 255)
OUT = Path(__file__).resolve().parent.parent / "mods" / "couch_lobby" / "glasses_selection.png"


def rect(mask, x0, y0, x1, y1):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            mask.add((x, y))


def frame():
    m = set()
    rect(m, 0, 0, 24, 0)
    rect(m, 0, 24, 24, 24)
    rect(m, 0, 0, 0, 24)
    rect(m, 24, 0, 24, 24)
    return m


def sunglasses():
    m = set()
    rect(m, 3, 9, 22, 10)    # brow bar + temple stubs
    rect(m, 5, 11, 11, 14)   # left lens
    rect(m, 6, 15, 10, 15)
    rect(m, 14, 11, 20, 14)  # right lens
    rect(m, 15, 15, 19, 15)
    return m


def draw(img, mask):
    px = img.load()
    for x, y in mask:
        sx, sy = x + 1, y + 1
        if (sx, sy) not in mask and sx < SIZE and sy < SIZE and px[sx, sy] != WHITE:
            px[sx, sy] = BLACK
    for x, y in mask:
        px[x, y] = WHITE


def main():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw(img, frame())
    draw(img, sunglasses())
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
