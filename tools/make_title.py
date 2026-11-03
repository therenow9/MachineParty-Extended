"""Draw the title screen's EXTENDED word for Machine Party: Extended (8 Player Support).

Our own block letters, no font file, in the proportions of the game's logo (logo bw7.png: stroke 0.2 of
the cap height, a soft shadow 0.045 below). Each PNG is drawn at the logo's source scale and shown at the
logo's scale (LOGO_SCALE), so the game filters both alike. Candidates go to a folder with candidates.json,
which tools/selftest/mp8_render (MP8_RENDER=title) places on the live main menu.

    python tools/make_title.py [--dir <folder>]   # default %TEMP%/machine-party-tests/title_art
    python tools/make_title.py --out extended/mpml/mp8_support/title_extended.png   # the shipped one
"""
import argparse
import json
import os
import random

from PIL import Image, ImageDraw, ImageFilter

LOGO_SCALE = 0.19857289  # main_menu.tscn, MainMenuScene/logo
SS = 4  # supersampling
STROKE = 0.2
GAP = 0.09
SHADOW_DY = 0.045
SHADOW_DX = -0.01
WHITE = (255, 255, 255, 255)
GREEN = (190, 255, 190, 255)  # a pale core; the halo is the racks' green (0, 1, 0)
GLOW = (0, 255, 0)
WORD = "EXTENDED"

# Logo letters in the 960x540 menu: MACHINE y 35-91, PARTY y 107-181, the byline y 197-214, x 60-302.
PARTY_BOTTOM = 181.0
LOGO_RIGHT = 302.0


ROUND_RIGHT = (False, True, True, False)  # a "round" shape's corners (tl, tr, br, bl) when it names none


def glyph(c, h, stroke=STROKE):
    """Polygons and rounded rects for one character of cap height h, at origin; returns (shapes, width).

    Shapes are painted in order: ("poly", points[, None]) and ("round", box, radius, fill[, corners]), where
    a None fill cuts the shape out of what is painted before it. tools/make_lettering.py builds the font from
    the same list, so both paint them alike. The trailer's lettering (D124) is every character here."""
    s = stroke * h
    shapes = []
    rect = lambda x0, y0, x1, y1: shapes.append(("poly", [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]))
    cut = lambda x0, y0, x1, y1: shapes.append(("poly", [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], None))
    poly = lambda *pts: shapes.append(("poly", list(pts)))
    rr = lambda x0, y0, x1, y1, r, corners=(True,) * 4: shapes.append(("round", (x0, y0, x1, y1), r, WHITE, corners))
    hole = lambda x0, y0, x1, y1, r, corners=(True,) * 4: shapes.append(("round", (x0, y0, x1, y1), r, None, corners))
    # A slanted stroke from (xa, ya) to (xb, yb), d wide along x.
    slant = lambda xa, ya, xb, yb, d: poly((xa, ya), (xa + d, ya), (xb + d, yb), (xb, yb))
    R, ri = 0.3 * h, 0.12 * h  # the D's outer and inner corners, the bowls' throughout

    def ring(x0, y0, x1, y1, r=R, corners=(True,) * 4):
        rr(x0, y0, x1, y1, r, corners)
        hole(x0 + s, y0 + s, x1 - s, y1 - s, ri, corners)

    if c == "E":
        w = 0.5 * h
        rect(0, 0, s, h)
        rect(0, 0, w, s)
        rect(0, h / 2 - s / 2, w * 0.86, h / 2 + s / 2)
        rect(0, h - s, w, h)
    elif c == "T":
        w = 0.56 * h
        rect(0, 0, w, s)
        rect(w / 2 - s / 2, 0, w / 2 + s / 2, h)
    elif c == "X":
        w = 0.6 * h
        d = s * 1.2
        shapes.append(("poly", [(0, 0), (d, 0), (w, h), (w - d, h)]))
        shapes.append(("poly", [(w - d, 0), (w, 0), (d, h), (0, h)]))
    elif c == "N":
        w = 0.6 * h
        d = s * 1.15
        rect(0, 0, s, h)
        rect(w - s, 0, w, h)
        shapes.append(("poly", [(0, 0), (d, 0), (w, h), (w - d, h)]))
    elif c == "D":
        w = 0.6 * h
        shapes.append(("round", (0, 0, w, h), 0.3 * h, WHITE))
        shapes.append(("round", (s, s, w - s, h - s), 0.12 * h, None))
    elif c == "A":
        # The logo's A: a flat top 0.23 of the cap height, legs one stroke wide across, the bar low.
        w, top, d = 0.66 * h, 0.23 * h, s * 0.95
        xl = (w - top) / 2
        poly((0, h), (xl, 0), (w - xl, 0), (w, h))
        left = lambda y: d + xl * (1 - y / h)
        right = lambda y: w - d - xl * (1 - y / h)
        apex = h * (1 - (w - 2 * d) / (2 * xl))
        bar0, bar1 = 0.62 * h, 0.62 * h + 0.85 * s
        shapes.append(("poly", [(left(bar0), bar0), ((left(apex) + right(apex)) / 2, apex), (right(bar0), bar0)], None))
        shapes.append(("poly", [(left(bar1), bar1), (right(bar1), bar1), (w - d, h + 1), (d, h + 1)], None))
    elif c == "B":
        w = 0.56 * h
        ring(0, 0, w * 0.92, h / 2 + s / 2, R * 0.8, ROUND_RIGHT)
        ring(0, h / 2 - s / 2, w, h, R, ROUND_RIGHT)
    elif c in "CG":
        w = 0.56 * h
        ring(0, 0, w, h)
        if c == "C":
            cut(w / 2, 0.36 * h, w + 1, 0.64 * h)
        else:
            cut(w / 2, 0.3 * h, w + 1, 0.5 * h)
            rect(w * 0.48, 0.5 * h, w, 0.5 * h + s)
    elif c == "F":
        w = 0.48 * h
        rect(0, 0, s, h)
        rect(0, 0, w, s)
        rect(0, h / 2 - s / 2, w * 0.86, h / 2 + s / 2)
    elif c == "H":
        w = 0.56 * h
        rect(0, 0, s, h)
        rect(w - s, 0, w, h)
        rect(0, h / 2 - s / 2, w, h / 2 + s / 2)
    elif c == "I":
        w = s
        rect(0, 0, s, h)
    elif c == "J":
        w = 0.5 * h
        rect(w - s, 0, w, 0.7 * h)
        rr(0, 0.5 * h, w, h, R, (False, False, True, True))
        hole(s, 0.5 * h - 1, w - s, h - s, ri, (False, False, True, True))
    elif c == "K":
        w, d = 0.58 * h, s * 1.2
        rect(0, 0, s, h)
        slant(s * 0.5, 0.66 * h, w - d, 0, d)
        slant(s + 0.06 * h, 0.4 * h, w - d, h, d)
    elif c == "L":
        w = 0.48 * h
        rect(0, 0, s, h)
        rect(0, h - s, w, h)
    elif c == "M":
        # The logo's M: straight sides, the V stopping above the baseline.
        w, d, vy = 0.68 * h, s * 1.1, 0.62 * h
        rect(0, 0, s, h)
        rect(w - s, 0, w, h)
        poly((0, 0), (d, 0), (w / 2 + d / 2, vy), (w / 2 - d / 2, vy))
        poly((w - d, 0), (w, 0), (w / 2 + d / 2, vy), (w / 2 - d / 2, vy))
    elif c in "O0Q":
        w = 0.56 * h if c != "0" else 0.54 * h
        ring(0, 0, w, h)
        if c == "Q":
            slant(w * 0.42, 0.66 * h, w - s * 1.1, h, s * 1.1)
    elif c in "PR":
        w = 0.56 * h if c == "P" else 0.58 * h
        rect(0, 0, s, h)
        ring(0, 0, w if c == "P" else w * 0.97, 0.56 * h, R, ROUND_RIGHT)
        if c == "R":
            slant(s * 1.1, 0.56 * h - s, w - s * 1.1, h, s * 1.1)
    elif c == "S":
        w = 0.54 * h
        # Square where each side runs into the spine, so the bowls' corners don't notch it.
        ring(0, 0, w, h / 2 + s / 2, R * 0.85, (True, True, False, True))
        cut(w / 2, 0.24 * h, w + 1, h / 2 - s / 2)
        ring(0, h / 2 - s / 2, w, h, R * 0.85, (False, True, True, True))
        cut(-1, h / 2 + s / 2, w / 2, 0.76 * h)
    elif c == "U":
        w = 0.56 * h
        rr(0, 0, w, h, R, (False, False, True, True))
        hole(s, -1, w - s, h - s, ri, (False, False, True, True))
    elif c == "V":
        w, d = 0.62 * h, s * 1.1
        poly((0, 0), (d, 0), (w / 2 + d / 2, h), (w / 2 - d / 2, h))
        poly((w - d, 0), (w, 0), (w / 2 + d / 2, h), (w / 2 - d / 2, h))
    elif c == "W":
        # Two V's, overlapping where the middle strokes meet at the top.
        w, d = 0.9 * h, s * 1.05
        v = w * 0.56
        for x0 in (0, w - v):
            poly((x0, 0), (x0 + d, 0), (x0 + v / 2 + d / 2, h), (x0 + v / 2 - d / 2, h))
            poly((x0 + v - d, 0), (x0 + v, 0), (x0 + v / 2 + d / 2, h), (x0 + v / 2 - d / 2, h))
    elif c == "Y":
        w, d, vy = 0.62 * h, s * 1.1, 0.55 * h
        poly((0, 0), (d, 0), (w / 2 + s / 2, vy), (w / 2 - s / 2, vy))
        poly((w - d, 0), (w, 0), (w / 2 + s / 2, vy), (w / 2 - s / 2, vy))
        rect(w / 2 - s / 2, vy - 1, w / 2 + s / 2, h)
    elif c == "Z":
        w, d = 0.54 * h, s * 1.2
        rect(0, 0, w, s)
        rect(0, h - s, w, h)
        poly((w - d, s), (w, s), (d, h - s), (0, h - s))
    elif c == "1":
        w = 0.36 * h
        rect(w - s, 0, w, h)
        poly((0, 0.2 * h), (w - s, 0), (w - s, s), (0, 0.2 * h + s))
    elif c in "2?":
        w = 0.54 * h if c == "2" else 0.5 * h
        ring(0, 0, w, 0.56 * h)
        if c == "2":
            cut(-1, 0.26 * h, w - s, 0.56 * h + 1)
            poly((w - s, 0.4 * h), (w, 0.47 * h), (s * 1.25, h - s), (0, h - s))
            rect(0, h - s, w, h)
        else:
            # The hook comes back along the bowl's foot to the middle, and the stem drops from there.
            cut(-1, 0.26 * h, w / 2 - s / 2, 0.56 * h + 1)
            rect(w / 2 - s / 2, 0.56 * h - s, w / 2 + s / 2, 0.74 * h)
            rect(w / 2 - s / 2, h - s, w / 2 + s / 2, h)
    elif c == "3":
        w = 0.54 * h
        # The openings run to each bowl's right stroke, as the 2's: one 0.3 w deep stays inside a 0.37 w stroke and
        # reads as 8. The upper bowl is inset 0.04 w, so its opening stops 0.04 w sooner.
        ring(w * 0.04, 0, w * 0.96, h / 2 + s / 2, R * 0.85)
        ring(0, h / 2 - s / 2, w, h)
        cut(-1, 0.24 * h, w * 0.96 - s, h / 2 - s / 2)
        cut(-1, h / 2 + s / 2, w - s, 0.76 * h)
        cut(-1, h / 2 - s / 2 - 1, w * 0.3, h / 2 + s / 2 + 1)
    elif c == "4":
        w = 0.58 * h
        sx, bar = w - s * 1.4, 0.66 * h
        poly((sx, 0), (sx + s, 0), (s * 1.2, bar), (0, bar))
        rect(0, bar, w, bar + s * 0.9)
        rect(sx, 0, sx + s, h)
    elif c == "5":
        w = 0.54 * h
        rect(0, 0, w, s)
        rect(0, 0, s, 0.5 * h)
        ring(0, 0.38 * h, w, h, R, (False, True, True, True))
        cut(-1, 0.38 * h + s, w / 2, 0.74 * h)
    elif c in "69":
        w = 0.54 * h
        ring(0, 0, w, 0.75 * h)
        cut(w / 2, 0.28 * h, w + 1, 0.75 * h + 1)
        ring(0, 0.42 * h, w, h)
        if c == "9":
            shapes[:] = rot180(shapes, w, h)
    elif c == "7":
        w, d = 0.52 * h, s * 1.15
        rect(0, 0, w, s)
        poly((w - d, s), (w, s), (w * 0.22 + d, h), (w * 0.22, h))
    elif c == "8":
        w = 0.54 * h
        ring(w * 0.04, 0, w * 0.96, h / 2 + s / 2, R * 0.85)
        ring(0, h / 2 - s / 2, w, h)
    elif c == ".":
        w = s
        rect(0, h - s, s, h)
    elif c == ",":
        w = s
        rect(0, h - s, s, h)
        poly((s * 0.3, h), (s, h), (s * 0.45, h + 0.8 * s), (0, h + 0.8 * s))
    elif c in ":;":
        w = s
        rect(0, 0.36 * h, s, 0.36 * h + s)
        rect(0, h - s, s, h)
        if c == ";":
            poly((s * 0.3, h), (s, h), (s * 0.45, h + 0.8 * s), (0, h + 0.8 * s))
    elif c == "!":
        w = s
        rect(0, 0, s, 0.7 * h)
        rect(0, h - s, s, h)
    elif c in "'\"":
        w = 0.8 * s if c == "'" else 2.2 * s
        rect(0, 0, 0.8 * s, 0.3 * h)
        if c == '"':
            rect(1.4 * s, 0, 2.2 * s, 0.3 * h)
    elif c == "-":
        w = 0.36 * h
        rect(0, h / 2 - 0.45 * s, w, h / 2 + 0.45 * s)
    elif c == "+":
        w = 0.5 * h
        rect(0, h / 2 - 0.45 * s, w, h / 2 + 0.45 * s)
        rect(w / 2 - 0.45 * s, h / 2 - w / 2, w / 2 + 0.45 * s, h / 2 + w / 2)
    elif c == "·":
        w = s
        rect(0, h / 2 - s / 2, s, h / 2 + s / 2)
    elif c == "…":
        w = 4 * s
        for x0 in (0, 1.5 * s, 3 * s):
            rect(x0, h - s, x0 + s, h)
    elif c == "/":
        w, d = 0.4 * h, s * 1.1
        poly((w - d, 0), (w, 0), (d, h), (0, h))
    elif c == "%":
        # Square dots 0.25 h either side of the slash's stroke: 0.11 h clear of it at the default stroke.
        w, d, q = 0.7 * h, s * 1.1, 0.25 * h
        poly((w - d, 0), (w, 0), (d, h), (0, h))
        rect(0, 0, q, q)
        rect(w - q, h - q, w, h)
    elif c in "()":
        w = 0.3 * h
        rr(0, 0, w + R, h, R, (True, False, False, True))
        hole(s, 0.5 * s, w + R + 1, h - 0.5 * s, ri, (True, False, False, True))
        cut(w, -1, w + R + 2, h + 1)
        if c == ")":
            shapes[:] = mirror(shapes, w)
    elif c == "&":
        # A small loop over a larger open one, and the stroke from the loop's foot to the bottom right.
        w, d = 0.66 * h, s * 1.15
        ring(0, 0.4 * h, w * 0.76, h, R)
        cut(w * 0.76 - s - 1, 0.4 * h - 1, w * 0.76 + 1, 0.62 * h)
        ring(w * 0.1, 0, w * 0.62, 0.46 * h, R * 0.7)
        slant(w * 0.16, 0.38 * h, w - d, h, d)
        rect(w * 0.62, 0.56 * h, w, 0.56 * h + s * 0.9)
    elif c == " ":
        w = 0.3 * h
    else:
        raise ValueError(c)
    return shapes, w


def _corners(sh):
    return sh[4] if len(sh) > 4 else ROUND_RIGHT


def rot180(shapes, w, h):
    """The shapes turned half a turn inside a w x h box (6 into 9)."""
    out = []
    for sh in shapes:
        if sh[0] == "poly":
            out.append(("poly", [(w - x, h - y) for x, y in sh[1]]) + sh[2:])
        else:
            x0, y0, x1, y1 = sh[1]
            tl, tr, br, bl = _corners(sh)
            out.append(("round", (w - x1, h - y1, w - x0, h - y0), sh[2], sh[3], (br, bl, tl, tr)))
    return out


def mirror(shapes, w):
    """The shapes flipped left to right inside a box w wide (( into ))."""
    out = []
    for sh in shapes:
        if sh[0] == "poly":
            out.append(("poly", [(w - x, y) for x, y in sh[1]]) + sh[2:])
        else:
            x0, y0, x1, y1 = sh[1]
            tl, tr, br, bl = _corners(sh)
            out.append(("round", (w - x1, y0, w - x0, y1), sh[2], sh[3], (tr, tl, bl, br)))
    return out


def word_width(h, text=WORD):
    return sum(glyph(c, h)[1] for c in text) + GAP * h * (len(text) - 1)


def draw_word(h, fill, text=WORD, specks=True, glow=False, seed=7):
    """The word at cap height h (source px), padded evenly so the image's centre is the letters' centre."""
    pad = int(0.25 * h) + 4
    w = word_width(h, text)
    W, H = int(w + 2 * pad), int(h + 2 * pad)
    mask = Image.new("L", (W * SS, H * SS), 0)
    d = ImageDraw.Draw(mask)
    x = pad
    for c in text:
        shapes, cw = glyph(c, h)
        for sh in shapes:
            if sh[0] == "poly":
                d.polygon([((x + px) * SS, (pad + py) * SS) for px, py in sh[1]],
                          fill=0 if len(sh) > 2 and sh[2] is None else 255)
            else:
                x0, y0, x1, y1 = sh[1]
                box = [(x + x0) * SS, (pad + y0) * SS, (x + x1) * SS, (pad + y1) * SS]
                d.rounded_rectangle(box, radius=sh[2] * SS, fill=255 if sh[3] else 0, corners=_corners(sh))
        x += cw + GAP * h
    mask = mask.resize((W, H), Image.LANCZOS)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    if glow:
        halo = mask.filter(ImageFilter.GaussianBlur(0.14 * h))
        out.paste(Image.new("RGBA", (W, H), GLOW + (255,)), (0, 0), halo.point(lambda v: min(255, int(v * 1.6))))
    else:
        shadow = Image.new("L", (W, H), 0)
        shadow.paste(mask, (int(SHADOW_DX * h), int(SHADOW_DY * h)))
        shadow = shadow.filter(ImageFilter.GaussianBlur(0.008 * h + 0.5))
        out.paste(Image.new("RGBA", (W, H), (0, 0, 0, 255)), (0, 0), shadow)
    face = mask
    if specks:
        rng = random.Random(seed)
        worn = Image.new("L", (W, H), 255)
        wd = ImageDraw.Draw(worn)
        for _ in range(int(w * h / 900)):
            cx, cy = rng.uniform(pad, pad + w), rng.uniform(pad, pad + h)
            r = rng.uniform(0.004, 0.014) * h
            wd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=0)
        face = Image.composite(mask, Image.new("L", (W, H), 0), worn)
        out.paste(Image.new("RGBA", (W, H), (0, 0, 0, 255)), (0, 0),
                  Image.composite(mask, Image.new("L", (W, H), 0), worn.point(lambda v: 255 - v)))
    out.paste(Image.new("RGBA", (W, H), fill), (0, 0), face)
    return out


def stacked(h, fill, glow, pitch):
    """One letter per row, centred, for the column beside the logo."""
    letters = [draw_word(h, fill, c, specks=not glow, glow=glow, seed=i) for i, c in enumerate(WORD)]
    W = max(im.width for im in letters)
    step = int(pitch / LOGO_SCALE)
    H = step * (len(letters) - 1) + letters[0].height
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for i, im in enumerate(letters):
        out.alpha_composite(im, ((W - im.width) // 2, i * step))
    return out


# Each placement in menu pixels: the letters' cap height, the centre of the letters, and a rotation.
def placements():
    p = {}
    cap = 36.0
    p["beside_half"] = (cap, (314 + word_width(cap) / 2, PARTY_BOTTOM - cap / 2), 0)
    cap = 74.0
    p["beside_full"] = (cap, (314 + word_width(cap) / 2, PARTY_BOTTOM - cap / 2), 0)
    cap = 11.0
    p["below_gap"] = (cap, (LOGO_RIGHT - word_width(cap) / 2, 184.5 + cap / 2), 0)
    cap = 16.0
    p["below_byline"] = (cap, (LOGO_RIGHT - word_width(cap) / 2, 219 + cap / 2), 0)
    cap = 145.0 / word_width(1.0)
    p["side_vertical"] = (cap, (314 + cap / 2, 35 + 145 / 2), -90)
    p["side_letters"] = (14.0, (322, 35 + 145 / 2), 0)
    for a in (10, 20):
        cap = 26.0
        p["stamp_%d" % a] = (cap, (318 + word_width(cap) / 2, 40), -a)
    return p


# The owner's pick (D106): green, one letter per row down the logo's right edge. Its centre is the wrapper's
# TITLE_CENTRE (mpml/mp8_support/main.gd), measured from the logo's top left.
SHIPPED = ("green", "side_letters")

TERMINAL_SIZE = {"beside_half": 48, "beside_full": 96, "below_gap": 16, "below_byline": 16,
                 "side_vertical": 32, "side_letters": 16, "stamp_10": 32, "stamp_20": 32}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(os.environ.get("TEMP", "."), "machine-party-tests", "title_art"))
    ap.add_argument("--out", help="write only the shipped word to this file")
    args = ap.parse_args()
    if args.out:
        style, name = SHIPPED
        cap, centre, rot = placements()[name]
        stacked(cap / LOGO_SCALE, GREEN, True, 145 / 7.6).save(args.out)
        print("%s_%s -> %s, centre %s" % (style, name, args.out, centre))
        return
    os.makedirs(args.dir, exist_ok=True)
    cands = []
    for name, (cap, centre, rot) in placements().items():
        h = cap / LOGO_SCALE
        for style, fill, glow in (("logo", WHITE, False), ("green", GREEN, True)):
            if name == "side_letters":
                im = stacked(h, fill, glow, 145 / 7.6)
            else:
                im = draw_word(h, fill, specks=not glow, glow=glow)
            file = "%s_%s.png" % (style, name)
            im.save(os.path.join(args.dir, file))
            cands.append({"name": "%s_%s" % (style, name), "file": file, "scale": LOGO_SCALE,
                          "centre": [round(centre[0], 1), round(centre[1], 1)], "rot": rot})
        text = "\n".join(WORD) if name == "side_letters" else WORD
        cands.append({"name": "terminal_" + name, "text": text, "font_size": TERMINAL_SIZE[name],
                      "centre": [round(centre[0], 1), round(centre[1], 1)], "rot": rot})
    with open(os.path.join(args.dir, "candidates.json"), "w") as f:
        json.dump(cands, f, indent=1)
    print("%d candidates in %s" % (len(cands), args.dir))


if __name__ == "__main__":
    main()
