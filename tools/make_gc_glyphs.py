"""Draws the GameCube prompt glyphs for mods/gamecube_support/glyphs/.

Four art sets, one PNG per GameCube button (glyphs/<art>/<button>.png, plus
<button>_wide.png and Dpad_<left|right>_wide.png for the 256x128 Duck Hunt
prompt). The mod decides which vanilla texture shows which button, so a remap
never needs new art.
  classic    the default: vanilla's thin white outline look with the
             GameCube face layout (prompted button filled, like vanilla's
             lit diamond dot) and GameCube letters on the shoulders
  outline    GameCube shapes (big A, small B, kidney X/Y, Z pill) as bold
             white outlines with letters
  authentic  the same shapes in GameCube colours (green A, red B, purple Z)
  letters    a white circle per face button with its letter

Everything is our own vector art: shapes and a small stroke font are drawn
at SS-times size and downsampled. No game pixels or font files are used.

  python tools/make_gc_glyphs.py                      # every set into the mod
  python tools/make_gc_glyphs.py --preview out.html   # also a comparison page
"""
import argparse
import base64
import io
import math
from pathlib import Path
from PIL import Image, ImageDraw

SS = 8
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "mods" / "gamecube_support" / "glyphs"

CLEAR = (0, 0, 0, 0)
WHITE = (255, 255, 255, 255)
INK = (20, 21, 28, 255)          # outline around coloured shapes
GREEN = (34, 164, 93, 255)
RED = (216, 49, 46, 255)
PALE = (214, 215, 222, 255)      # X / Y / L / R plastic
PALE_INK = (43, 44, 54, 255)
PURPLE = (106, 79, 196, 255)
DARK = (74, 75, 88, 255)         # fully clicked trigger
STICK = (92, 94, 108, 255)

SMALL_KEYS = ["A", "B", "X", "Y", "Lclick", "Z", "L", "R", "stick"]
WIDE_KEYS = ["Lclick", "Z"]
VANILLA_STICK_ARTS = {"letters"}  # these keep the game's own stick glyph

# Vanilla texture (relative to res://textures/ui/control/) -> glyph key, as
# the mod maps them by default (main.gd SLOTS). Used for the preview page.
TARGETS = {
    "controller_button_south.png": "A",
    "controller_button_east.png": "B",
    "controller_button_west.png": "X",
    "controller_button_north.png": "Y",
    "controller_left_shoulder.png": "Lclick",
    "controller_right_shoulder.png": "Z",
    "controller_left_trigger.png": "L",
    "controller_right_trigger.png": "R",
    "controller_analog_alt.png": "stick",
    "hires/controller_left_shoulder_button_wide_2x.png": "Lclick",
    "hires/controller_right_shoulder_button_wide_2x.png": "Z",
}
STICK_SLOTS = {rel for rel, k in TARGETS.items() if k == "stick"}


class Canvas:
    """Draws in target-pixel units onto an SS-times bigger RGBA image."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w * SS, h * SS), CLEAR)
        self.d = ImageDraw.Draw(self.img)

    def s(self, v):
        return v * SS

    def circle(self, cx, cy, r, fill):
        r = self.s(r)
        cx, cy = self.s(cx), self.s(cy)
        self.d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)

    def ring(self, cx, cy, r, width, fill):
        """Circle outline centred on radius r."""
        ro = self.s(r + width / 2)
        cx, cy = self.s(cx), self.s(cy)
        self.d.ellipse((cx - ro, cy - ro, cx + ro, cy + ro), outline=fill, width=round(self.s(width)))

    def rrect(self, x0, y0, x1, y1, rad, fill=None, outline=None, width=0):
        box = tuple(self.s(v) for v in (x0, y0, x1, y1))
        self.d.rounded_rectangle(box, radius=self.s(rad), fill=fill, outline=outline,
                                 width=round(self.s(width)) if outline else 0)

    def band(self, cx, cy, r, width, a0, a1, fill):
        """Thick arc with round caps: the kidney-shaped X / Y buttons."""
        steps = 48
        angles = [math.radians(a0 + (a1 - a0) * i / steps) for i in range(steps + 1)]
        outer = [(cx + (r + width / 2) * math.cos(t), cy + (r + width / 2) * math.sin(t)) for t in angles]
        inner = [(cx + (r - width / 2) * math.cos(t), cy + (r - width / 2) * math.sin(t)) for t in reversed(angles)]
        self.poly(outer + inner, fill=fill)
        for a in (a0, a1):
            t = math.radians(a)
            self.circle(cx + r * math.cos(t), cy + r * math.sin(t), width / 2, fill)

    def poly(self, pts, fill=None, outline=None, width=0):
        pts = [(self.s(x), self.s(y)) for x, y in pts]
        if fill:
            self.d.polygon(pts, fill=fill)
        if outline:
            self.d.line(pts + [pts[0]], fill=outline, width=round(self.s(width)), joint="curve")

    def stroke(self, pts, width, fill):
        sp = [(self.s(x), self.s(y)) for x, y in pts]
        self.d.line(sp, fill=fill, width=round(self.s(width)), joint="curve")
        for x, y in (pts[0], pts[-1]):
            self.circle(x, y, width / 2, fill)

    def arc(self, cx, cy, rx, ry, a0, a1, width, fill):
        hw = width / 2
        box = (self.s(cx - rx - hw), self.s(cy - ry - hw), self.s(cx + rx + hw), self.s(cy + ry + hw))
        self.d.arc(box, a0, a1, fill=fill, width=round(self.s(width)))
        for a in (a0, a1):
            t = math.radians(a)
            self.circle(cx + rx * math.cos(t), cy + ry * math.sin(t), hw, fill)

    def done(self):
        return self.img.resize((self.w, self.h), Image.LANCZOS)


# Stroke font: glyph paths in a box 0..0.68 wide, 0..1 tall.
LW = 0.68
FONT = {
    "A": [("l", [(0, 1), (0.34, 0), (0.68, 1)]), ("l", [(0.13, 0.64), (0.55, 0.64)])],
    "B": [("l", [(0.38, 0.48), (0, 0.48), (0, 0), (0.36, 0)]), ("a", 0.36, 0.24, 0.24, 0.24, -90, 90),
          ("l", [(0, 0.48), (0, 1), (0.4, 1)]), ("a", 0.4, 0.74, 0.26, 0.26, -90, 90)],
    "X": [("l", [(0, 0), (0.68, 1)]), ("l", [(0.68, 0), (0, 1)])],
    "Y": [("l", [(0, 0), (0.34, 0.5), (0.68, 0)]), ("l", [(0.34, 0.5), (0.34, 1)])],
    "Z": [("l", [(0, 0), (0.68, 0), (0, 1), (0.68, 1)])],
    "L": [("l", [(0, 0), (0, 1), (0.6, 1)])],
    "R": [("l", [(0, 1), (0, 0), (0.36, 0)]), ("a", 0.36, 0.25, 0.25, 0.25, -90, 90),
          ("l", [(0.36, 0.5), (0, 0.5)]), ("l", [(0.28, 0.5), (0.66, 1)])],
    "T": [("l", [(0, 0), (0.68, 0)]), ("l", [(0.34, 0), (0.34, 1)])],
}


def text(c, s, cx, cy, h, sw, fill, gap=0.28):
    """Draws string s centred on (cx, cy), cap height h, stroke width sw."""
    total = len(s) * LW * h + (len(s) - 1) * gap * h
    x0 = cx - total / 2
    y0 = cy - h / 2
    for ch in s:
        for part in FONT[ch]:
            if part[0] == "l":
                c.stroke([(x0 + x * h, y0 + y * h) for x, y in part[1]], sw, fill)
            else:
                _, ax, ay, rx, ry, a0, a1 = part
                c.arc(x0 + ax * h, y0 + ay * h, rx * h, ry * h, a0, a1, sw, fill)
        x0 += (LW + gap) * h


def trigger_shape(c, x0, y0, x1, y1, top, bottom, grow, fill):
    """GameCube-style trigger: big round top corners, small bottom ones."""
    x0, y0, x1, y1 = x0 - grow, y0 - grow, x1 + grow, y1 + grow
    mid = (y0 + y1) / 2
    c.rrect(x0, y0, x1, mid + top, top + grow, fill=fill)
    c.rrect(x0, mid - bottom, x1, y1, bottom + grow, fill=fill)


def trigger_outline(c, x0, y0, x1, y1, top, bottom, width, fill):
    trigger_shape(c, x0, y0, x1, y1, top, bottom, width / 2, fill)
    trigger_shape(c, x0, y0, x1, y1, top, bottom, -width / 2, CLEAR)


def octagon(cx, cy, r):
    return [(cx + r * math.cos(math.radians(22.5 + 45 * i)), cy + r * math.sin(math.radians(22.5 + 45 * i)))
            for i in range(8)]


# --- 32x32 glyphs -----------------------------------------------------------
O = 1.25  # ink outline around authentic shapes


def kidney(key):
    """X / Y bean: radius 22, span +-21 deg, 13 wide, ~31px long, ~15.5 across.
    Returns arc centre, angles and letter position."""
    if key == "X":  # curls around A, which sits to its left
        return -5, 16, -21, 21, 16.4, 16
    return 16, 37, 249, 291, 16, 15.6  # Y curls over A, which sits below it


def authentic_32(key):
    c = Canvas(32, 32)
    if key == "A":
        c.circle(16, 16, 14.5 + O, INK)
        c.circle(16, 16, 14.5, GREEN)
        text(c, "A", 16, 16.3, 13, 2.7, WHITE)
    elif key == "B":
        c.circle(16, 16, 12.5 + O, INK)
        c.circle(16, 16, 12.5, RED)
        text(c, "B", 16.4, 16, 11, 2.5, WHITE)
    elif key in ("X", "Y"):
        cx, cy, a0, a1, lx, ly = kidney(key)
        c.band(cx, cy, 22, 13 + 2 * O, a0, a1, INK)
        c.band(cx, cy, 22, 13, a0, a1, PALE)
        text(c, key, lx, ly, 9, 2.1, PALE_INK)
    elif key == "Z":
        c.rrect(2 - O, 7 - O, 30 + O, 25 + O, 9 + O, fill=INK)
        c.rrect(2, 7, 30, 25, 9, fill=PURPLE)
        text(c, "Z", 16, 16, 11, 2.5, WHITE)
    elif key in ("L", "R"):
        trigger_shape(c, 5, 3, 27, 29, 10, 3, O, INK)
        trigger_shape(c, 5, 3, 27, 29, 10, 3, 0, PALE)
        text(c, key, 16.5 if key == "L" else 16, 17, 13, 2.7, PALE_INK)
    elif key == "Lclick":
        trigger_shape(c, 5, 3, 27, 29, 10, 3, O, INK)
        trigger_shape(c, 5, 3, 27, 29, 10, 3, 0, DARK)
        text(c, "L", 16.5, 12.5, 10, 2.6, WHITE)
        c.rrect(9, 23.5, 23, 26, 1.2, fill=WHITE)  # "pressed to the floor" bar
    elif key == "stick":
        c.poly(octagon(16, 16, 15), fill=INK)
        c.poly(octagon(16, 16, 13.6), fill=STICK)
        c.circle(16, 16, 8 + O, INK)
        c.circle(16, 16, 8, PALE)
        c.ring(16, 16, 5, 1.2, (170, 172, 182, 255))
    return c.done()


# GameCube face cluster, proportioned from the real pad with A's diameter
# D as the unit: B is 0.55 D across; X and Y are 0.5 D wide, about 1.4 D long
# end to end, and hug A with a 0.2 D gap; B sits ~1.03 D from A's centre at
# half past seven. _fit() picks the largest D that fits the 32px icon.
THIN = 1.5  # vanilla-weight line


def _cluster(d, ax, ay):
    bean_w = 0.5 * d
    bean_r = d / 2 + 0.2 * d + bean_w / 2   # centreline radius around A
    span = math.degrees((1.4 * d - bean_w) / bean_r)
    bd, bt = 1.03 * d, math.radians(135)
    return {
        "A": ("circle", ax, ay, d / 2),
        "B": ("circle", ax + bd * math.cos(bt), ay + bd * math.sin(bt), 0.275 * d),
        "X": ("bean", ax, ay, bean_r, -5 - span / 2, -5 + span / 2, bean_w),    # right of A
        "Y": ("bean", ax, ay, bean_r, 245 - span / 2, 245 + span / 2, bean_w),  # over A
    }


def _extent(shapes):
    """Bounding box of the cluster (lines are drawn inside the shapes)."""
    xs, ys = [], []
    for shape in shapes.values():
        if shape[0] == "circle":
            _, x, y, r = shape
            pad = r
            pts = [(x, y)]
        else:
            _, x, y, r, a0, a1, w = shape
            pad = w / 2
            pts = [(x + r * math.cos(math.radians(a0 + (a1 - a0) * i / 40)),
                    y + r * math.sin(math.radians(a0 + (a1 - a0) * i / 40))) for i in range(41)]
        xs += [px - pad for px, _ in pts] + [px + pad for px, _ in pts]
        ys += [py - pad for _, py in pts] + [py + pad for _, py in pts]
    return min(xs), min(ys), max(xs), max(ys)


def _fit(size=32, margin=1.0):
    d = 16.0
    while True:
        x0, y0, x1, y1 = _extent(_cluster(d, 0, 0))
        if max(x1 - x0, y1 - y0) <= size - 2 * margin:
            break
        d -= 0.05
    return _cluster(d, size / 2 - (x0 + x1) / 2, size / 2 - (y0 + y1) / 2), d


CLUSTER, CLUSTER_D = _fit()
def classic_32(key):
    """Vanilla look, GameCube layout: the face cluster in thin white outlines
    with the prompted button filled, like vanilla's lit diamond dot; thin
    bumper / trigger outlines with GameCube letters for the shoulders."""
    c = Canvas(32, 32)
    if key in CLUSTER:
        for k, shape in CLUSTER.items():
            filled = k == key
            # Lines sit inside each shape, so the gaps between buttons stay true.
            if shape[0] == "circle":
                _, x, y, r = shape
                if filled:
                    c.circle(x, y, r, WHITE)
                else:
                    c.ring(x, y, r - THIN / 2, THIN, WHITE)
            else:
                _, x, y, r, a0, a1, w = shape
                c.band(x, y, r, w, a0, a1, WHITE)
                if not filled:
                    c.band(x, y, r, w - 2 * THIN, a0, a1, CLEAR)
    elif key == "Z":
        c.rrect(2, 8, 30, 24, 7, outline=WHITE, width=1.6)
        text(c, "Z", 16, 16, 9, 1.8, WHITE)
    elif key in ("L", "R"):
        trigger_outline(c, 6, 3, 26, 29, 9, 3, 1.6, WHITE)
        text(c, key, 16.5 if key == "L" else 16, 17, 10, 1.8, WHITE)
    elif key == "Lclick":
        trigger_outline(c, 6, 3, 26, 29, 9, 3, 1.6, WHITE)
        text(c, "L", 16.5, 13, 9, 1.8, WHITE)
        c.rrect(10, 22.5, 22, 24, 0.75, fill=WHITE)  # "pressed to the floor" bar
    elif key == "stick":  # octagonal gate
        c.poly(octagon(16, 16, 13), outline=WHITE, width=1.6)
        c.ring(16, 16, 6, 1.6, WHITE)
    return c.done()


def classic_wide(key):
    c = Canvas(256, 128)
    if key == "Z":
        c.rrect(12, 18, 244, 110, 46, outline=WHITE, width=8)
        text(c, "Z", 128, 64, 48, 9, WHITE)
    else:
        trigger_outline(c, 14, 8, 242, 120, 50, 14, 8, WHITE)
        text(c, "L", 131, 52, 44, 9, WHITE)
        c.rrect(88, 92, 168, 99, 3.5, fill=WHITE)
    return c.done()


def outline_32(key):
    """GameCube shapes as white outlines, like the vanilla prompts."""
    c = Canvas(32, 32)
    w = 2.0
    if key == "A":
        c.ring(16, 16, 14, w, WHITE)
        text(c, "A", 16, 16.3, 12.5, 2.5, WHITE)
    elif key == "B":  # smaller, like the real B
        c.ring(16, 16, 11, w, WHITE)
        text(c, "B", 16.3, 16, 10, 2.3, WHITE)
    elif key in ("X", "Y"):
        cx, cy, a0, a1, lx, ly = kidney(key)
        c.band(cx, cy, 22, 13 + w, a0, a1, WHITE)
        c.band(cx, cy, 22, 13 - w, a0, a1, CLEAR)
        text(c, key, lx, ly, 7.6, 2.0, WHITE)
    elif key == "Z":
        c.rrect(2, 7, 30, 25, 9, outline=WHITE, width=w)
        text(c, "Z", 16, 16, 10.5, 2.3, WHITE)
    elif key in ("L", "R"):
        trigger_outline(c, 5, 3, 27, 29, 10, 3, w, WHITE)
        text(c, key, 16.5 if key == "L" else 16, 17, 12, 2.4, WHITE)
    elif key == "Lclick":
        trigger_outline(c, 5, 3, 27, 29, 10, 3, w, WHITE)
        text(c, "L", 16.5, 12.5, 10, 2.4, WHITE)
        c.rrect(9.5, 22.5, 22.5, 24.5, 1, fill=WHITE)  # "pressed to the floor" bar
    elif key == "stick":
        c.poly(octagon(16, 16, 14), outline=WHITE, width=w)
        c.ring(16, 16, 6.5, w, WHITE)
    return c.done()


def letters_32(key):
    c = Canvas(32, 32)
    w = 2.0
    if key in ("A", "B", "X", "Y"):
        c.ring(16, 16, 13.5, w, WHITE)
        text(c, key, 16.2 if key == "B" else 16, 16, 12, 2.4, WHITE)
    elif key == "Z":
        c.rrect(2, 7, 30, 25, 9, outline=WHITE, width=w)
        text(c, "Z", 16, 16, 10.5, 2.3, WHITE)
    elif key in ("L", "R"):
        trigger_outline(c, 5, 3, 27, 29, 10, 3, w, WHITE)
        text(c, key, 16.5 if key == "L" else 16, 17, 12, 2.4, WHITE)
    elif key == "Lclick":  # filled = pressed, like vanilla
        trigger_shape(c, 5, 3, 27, 29, 10, 3, w / 2, WHITE)
        text(c, "L", 16.5, 12.5, 10, 2.6, CLEAR)
        c.rrect(9, 23.5, 23, 25.5, 1, fill=CLEAR)
    elif key == "stick":
        c.poly(octagon(16, 16, 14), outline=WHITE, width=w)
        c.ring(16, 16, 6.5, w, WHITE)
    return c.done()


# --- 256x128 wide glyphs (Duck Hunt "adjust look speed" prompt) -------------
def authentic_wide(key):
    c = Canvas(256, 128)
    o = 5
    if key == "Z":
        c.rrect(12 - o, 18 - o, 244 + o, 110 + o, 46 + o, fill=INK)
        c.rrect(12, 18, 244, 110, 46, fill=PURPLE)
        text(c, "Z", 128, 64, 56, 12, WHITE)
    else:
        trigger_shape(c, 14, 8, 242, 120, 50, 14, o, INK)
        trigger_shape(c, 14, 8, 242, 120, 50, 14, 0, DARK)
        text(c, "L", 131, 50, 46, 12, WHITE)
        c.rrect(84, 92, 172, 102, 5, fill=WHITE)
    return c.done()


def outline_wide(key):
    c = Canvas(256, 128)
    w = 8
    if key == "Z":
        c.rrect(12, 18, 244, 110, 46, outline=WHITE, width=w)
        text(c, "Z", 128, 64, 52, 11, WHITE)
    else:
        trigger_outline(c, 14, 8, 242, 120, 50, 14, w, WHITE)
        text(c, "L", 131, 50, 46, 11, WHITE)
        c.rrect(86, 90, 170, 99, 4.5, fill=WHITE)
    return c.done()


def letters_wide(key):
    c = Canvas(256, 128)
    w = 8
    if key == "Z":
        c.rrect(12, 18, 244, 110, 46, outline=WHITE, width=w)
        text(c, "Z", 128, 64, 52, 11, WHITE)
    else:
        trigger_shape(c, 14, 8, 242, 120, 50, 14, w / 2, WHITE)
        text(c, "L", 131, 50, 46, 12, CLEAR)
        c.rrect(84, 92, 172, 102, 5, fill=CLEAR)
    return c.done()


# --- D-pad glyphs for the same prompt ----------------------------------------
# A GameCube hunter steps look speed with D-pad Left / Right, so their prompt
# shows the cross with that arm filled.
DPAD_KEYS = ["Dpad_left_wide", "Dpad_right_wide"]
DPAD_LINE = {"classic": 6, "outline": 8, "letters": 8, "authentic": 5}


def _cross(c, cx, cy, arm, half, grow, fill):
    """Plus-shaped D-pad: arm is centre to tip, half is half an arm's width."""
    r = half * 0.3 + max(grow, 0)
    c.rrect(cx - arm - grow, cy - half - grow, cx + arm + grow, cy + half + grow, r, fill=fill)
    c.rrect(cx - half - grow, cy - arm - grow, cx + half + grow, cy + arm + grow, r, fill=fill)


def dpad_wide(art, side):
    c = Canvas(256, 128)
    cx, cy, arm, half = 128, 64, 54, 18
    s = -1 if side == "left" else 1
    w = DPAD_LINE[art]
    if art == "authentic":
        _cross(c, cx, cy, arm, half, w, INK)
        _cross(c, cx, cy, arm, half, 0, PALE)
        pressed = DARK
    else:
        _cross(c, cx, cy, arm, half, w / 2, WHITE)
        _cross(c, cx, cy, arm, half, -w / 2, CLEAR)
        pressed = WHITE
    x0, x1 = sorted((cx + s * half, cx + s * arm))
    c.rrect(x0, cy - half, x1, cy + half, half * 0.3, fill=pressed)
    return c.done()


ARTS = {
    "classic": (classic_32, classic_wide),
    "outline": (outline_32, outline_wide),
    "authentic": (authentic_32, authentic_wide),
    "letters": (letters_32, letters_wide),
}


def render(art, rel):
    small, wide = ARTS[art]
    key = TARGETS[rel]
    return wide(key) if rel.startswith("hires/") else small(key)


def write_set(art, out):
    small, wide = ARTS[art]
    jobs = [(k, small) for k in SMALL_KEYS] + [(k + "_wide", lambda k2, f=wide: f(k2[:-5])) for k in WIDE_KEYS]
    jobs += [(k, lambda k2, a=art: dpad_wide(a, k2.split("_")[1])) for k in DPAD_KEYS]
    for name, draw in jobs:
        if name == "stick" and art in VANILLA_STICK_ARTS:
            continue
        p = out / art / f"{name}.png"
        p.parent.mkdir(parents=True, exist_ok=True)
        draw(name).save(p)
        print(f"wrote {p.relative_to(ROOT) if p.is_relative_to(ROOT) else p}")


# --- comparison page --------------------------------------------------------
def vanilla_ref(rel):
    """Our own redraw of the vanilla style, for side-by-side comparison only."""
    wide = rel.startswith("hires/")
    c = Canvas(256, 128) if wide else Canvas(32, 32)
    key = TARGETS[rel]
    if wide:
        c.rrect(12, 18, 244, 110, 46, outline=WHITE, width=8)
        text(c, "LB" if key == "Lclick" else "RB", 128, 64, 48, 9, WHITE, gap=0.2)
        return c.done()
    if key in ("A", "B", "X", "Y"):
        lit = {"A": (16, 25), "B": (25, 16), "X": (7, 16), "Y": (16, 7)}[key]
        for p in ((16, 7), (25, 16), (16, 25), (7, 16)):
            if p == lit:
                c.circle(*p, 4.5, WHITE)
            else:
                c.ring(*p, 3.8, 1.4, WHITE)
    elif key == "stick":
        c.ring(16, 16, 13, 2, WHITE)
        c.ring(16, 16, 6, 2, WHITE)
    else:
        label = {"Lclick": "LB", "Z": "RB", "L": "LT", "R": "RT"}[key]
        if label.endswith("B"):
            c.rrect(2, 8, 30, 24, 7, outline=WHITE, width=1.6)
        else:
            trigger_outline(c, 6, 3, 26, 29, 9, 3, 1.6, WHITE)
        text(c, label, 16, 16 if label.endswith("B") else 17, 8, 1.7, WHITE, gap=0.22)
    return c.done()


def b64(img):
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


ROWS = [
    # rel, game slot label, GameCube button, what it does in game
    ("controller_button_south.png", "South face", "A", "Confirm, action 1"),
    ("controller_button_east.png", "East face", "B", "Action 2, unready"),
    ("controller_button_west.png", "West face", "X", "Action 3"),
    ("controller_button_north.png", "North face", "Y", "Action 4"),
    ("controller_left_shoulder.png", "LB", "L, full click", "Left shoulder, playlist remove"),
    ("controller_right_shoulder.png", "RB", "Z", "Right shoulder, playlist add"),
    ("controller_left_trigger.png", "LT", "L, analog", "Left trigger, playlist down"),
    ("controller_right_trigger.png", "RT", "R, analog", "Right trigger, playlist up"),
    ("controller_analog_alt.png", "Stick", "Control stick", "Move"),
]
WIDE = [
    ("hires/controller_left_shoulder_button_wide_2x.png", "LB (wide)", "L, full click"),
    ("hires/controller_right_shoulder_button_wide_2x.png", "RB (wide)", "Z"),
]


def preview(path):
    imgs = {}
    for rel in TARGETS:
        imgs[("vanilla", rel)] = b64(vanilla_ref(rel))
        for art in ARTS:
            if art in VANILLA_STICK_ARTS and rel in STICK_SLOTS:
                imgs[(art, rel)] = imgs[("vanilla", rel)]
            else:
                imgs[(art, rel)] = b64(render(art, rel))

    def cell(art, rel):
        u = imgs[(art, rel)]
        return (f'<div class="sizes"><img class="s16" src="{u}" alt="">'
                f'<img class="s32" src="{u}" alt=""><img class="s4x" src="{u}" alt=""></div>')

    def wcell(art, rel):
        u = imgs[(art, rel)]
        return f'<div class="sizes"><img class="w24" src="{u}" alt=""><img class="w64" src="{u}" alt=""></div>'

    rows = "\n".join(
        f'<tr><th scope="row"><span class="slot">{slot}</span><span class="gc">{gc}</span>'
        f'<span class="does">{does}</span></th>'
        f'<td>{cell("vanilla", rel)}</td><td class="chosen">{cell("classic", rel)}</td><td>{cell("outline", rel)}</td><td>{cell("authentic", rel)}</td>'
        f'<td>{cell("letters", rel)}{"<span class=note>keeps vanilla</span>" if rel in STICK_SLOTS else ""}</td></tr>'
        for rel, slot, gc, does in ROWS)
    wide_rows = "\n".join(
        f'<tr><th scope="row"><span class="slot">{slot}</span><span class="gc">{gc}</span></th>'
        f'<td>{wcell("vanilla", rel)}</td><td class="chosen">{wcell("classic", rel)}</td><td>{wcell("outline", rel)}</td><td>{wcell("authentic", rel)}</td><td>{wcell("letters", rel)}</td></tr>'
        for rel, slot, gc in WIDE)

    def mock(art, title):
        g = lambda rel: f'<img class="mi" src="{imgs[(art, rel)]}" alt="">'
        stick, a, b, x, y = (g("controller_analog_alt.png"), g("controller_button_south.png"),
                             g("controller_button_east.png"), g("controller_button_west.png"),
                             g("controller_button_north.png"))
        lt, rt, lb, rb = (g("controller_left_trigger.png"), g("controller_right_trigger.png"),
                          g("controller_left_shoulder.png"), g("controller_right_shoulder.png"))
        wl = f'<img class="mw" src="{imgs[(art, WIDE[0][0])]}" alt="">'
        wr = f'<img class="mw" src="{imgs[(art, WIDE[1][0])]}" alt="">'
        return f"""<figure class="mock">
  <figcaption>{title}</figcaption>
  <div class="stage">
    <p class="brief-h">CONTROLS</p>
    <ul class="brief">
      <li><span class="ic">{stick}</span>Move</li>
      <li><span class="ic">{a}</span>Jump</li>
      <li><span class="ic">{b}</span>Grab</li>
      <li><span class="ic">{x}{y}</span>Throw</li>
      <li><span class="ic">{lt}{rt}</span>Scope [x2]</li>
      <li><span class="ic">{lb}{rb}</span>Shove</li>
    </ul>
    <p class="duck">ADJUST LOOK SPEED WITH {wl}{wr}</p>
  </div>
</figure>"""

    page = TEMPLATE.format(
        mocks=mock("classic", "Classic (default)") + mock("vanilla", "Vanilla style (redrawn)") + mock("outline", "Outline") + mock("authentic", "Authentic colours") + mock("letters", "Letters only"),
        rows=rows, wide_rows=wide_rows)
    Path(path).write_text(page, encoding="utf-8")
    print(f"wrote {path}")


TEMPLATE = """<title>GameCube Glyph Picker</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Chakra+Petch:wght@500;600;700&family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>
/* Layout: a spec sheet. In-game mocks first, then a button-by-button table, then the mapping notes. */
:root {{
  --bg: #f2f1f6; --surface: #ffffff; --fg: #1c1a28; --muted: #5d5970; --line: #dad7e5;
  --accent: #5442b0; --accent-soft: #e7e3f8;
  --stage: #17181f; --stage-fg: #e9e9ef;
  --display: "Chakra Petch", "Segoe UI", system-ui, sans-serif;
  --body: "IBM Plex Sans", "Segoe UI", system-ui, sans-serif;
  --mono: "IBM Plex Mono", ui-monospace, Consolas, monospace;
  --zoom: 2;
}}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{
  --bg: #121119; --surface: #1b1a24; --fg: #ebeaf3; --muted: #a39fb6; --line: #2d2b3a;
  --accent: #a898ff; --accent-soft: #2a2545; color-scheme: dark; }} }}
:root[data-theme="dark"] {{
  --bg: #121119; --surface: #1b1a24; --fg: #ebeaf3; --muted: #a39fb6; --line: #2d2b3a;
  --accent: #a898ff; --accent-soft: #2a2545; color-scheme: dark; }}
body {{ background: var(--bg); color: var(--fg); font: 15px/1.55 var(--body); }}
.wrap {{ max-width: 1080px; margin: 0 auto; padding-inline: 16px; padding-block: 32px 64px; display: grid; gap: 40px; }}
h1, h2 {{ font-family: var(--display); text-wrap: balance; margin: 0; letter-spacing: .01em; }}
h1 {{ font-size: clamp(28px, 4.5vw, 40px); font-weight: 700; line-height: 1.1; }}
h2 {{ font-size: 21px; font-weight: 600; }}
p {{ margin: 0; max-width: 68ch; }}
.lede {{ color: var(--muted); font-size: 16px; }}
header {{ display: grid; gap: 12px; }}
.eyebrow {{ font: 500 12px/1 var(--mono); letter-spacing: .12em; text-transform: uppercase; color: var(--accent); }}
section {{ display: grid; gap: 16px; }}
code {{ font-family: var(--mono); font-size: .92em; background: var(--accent-soft); padding: 1px 5px; border-radius: 4px; }}

.controls {{ display: flex; flex-wrap: wrap; gap: 8px 20px; align-items: center; }}
.seg {{ display: inline-flex; border: 1px solid var(--line); border-radius: 8px; overflow: hidden; background: var(--surface); }}
.seg button {{ font: 500 13px var(--body); color: var(--fg); background: none; border: 0; padding: 6px 12px; cursor: pointer; }}
.seg button + button {{ border-left: 1px solid var(--line); }}
.seg button[aria-pressed="true"] {{ background: var(--accent); color: #fff; }}
.seg button:focus-visible {{ outline: 2px solid var(--accent); outline-offset: -2px; }}
.lbl {{ font: 500 12px var(--mono); color: var(--muted); text-transform: uppercase; letter-spacing: .08em; }}

.mocks {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 240px), 1fr)); gap: 16px; }}
.mock {{ margin: 0; display: grid; gap: 8px; min-width: 0; }}
.mock figcaption {{ font: 600 14px var(--display); letter-spacing: .02em; }}
.stage {{ background: var(--stage); color: var(--stage-fg); border-radius: 10px; padding: 18px 20px; display: grid; gap: 12px; overflow-x: auto; transition: background .2s; }}
.brief-h {{ font: 700 13px var(--display); letter-spacing: .18em; opacity: .7; }}
.brief {{ list-style: none; margin: 0; padding: 0; display: grid; gap: calc(6px * var(--zoom)); font: 600 calc(9px * var(--zoom)) var(--display); letter-spacing: .04em; }}
.brief li {{ display: flex; align-items: center; gap: calc(6px * var(--zoom)); }}
.ic {{ display: inline-flex; gap: calc(2px * var(--zoom)); min-width: calc(34px * var(--zoom)); }}
.mi {{ width: calc(16px * var(--zoom)); height: calc(16px * var(--zoom)); }}
.duck {{ font: 600 calc(8px * var(--zoom)) var(--display); letter-spacing: .06em; display: flex; flex-wrap: wrap; align-items: center; gap: calc(3px * var(--zoom)); }}
.mw {{ height: calc(14px * var(--zoom)); width: calc(28px * var(--zoom)); }}

.table-wrap {{ overflow-x: auto; border: 1px solid var(--line); border-radius: 10px; background: var(--surface); }}
table {{ border-collapse: collapse; width: 100%; min-width: 640px; }}
th, td {{ padding: 10px 14px; text-align: left; vertical-align: middle; border-top: 1px solid var(--line); }}
thead th {{ border-top: 0; font: 500 12px var(--mono); text-transform: uppercase; letter-spacing: .08em; color: var(--muted); background: var(--surface); }}
tbody th {{ display: grid; gap: 1px; font-weight: 400; min-width: 150px; }}
.slot {{ font: 500 12px var(--mono); color: var(--muted); }}
.gc {{ font: 600 15px var(--display); }}
.does {{ font-size: 12px; color: var(--muted); }}
td {{ background: var(--stage); }}
td.chosen {{ box-shadow: inset 0 0 0 2px var(--accent); }}
.sizes {{ display: flex; align-items: center; gap: 14px; }}
.s16 {{ width: 16px; height: 16px; }}
.s32 {{ width: 32px; height: 32px; }}
.s4x {{ width: 96px; height: 96px; image-rendering: pixelated; }}
.w24 {{ width: 48px; height: 24px; }}
.w64 {{ width: 128px; height: 64px; }}
.note {{ display: block; font: 500 11px var(--mono); color: #a7a7b6; margin-top: 4px; }}
.legend {{ font-size: 13px; color: var(--muted); }}

.facts {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr)); gap: 16px; }}
.fact {{ background: var(--surface); border: 1px solid var(--line); border-radius: 10px; padding: 16px 18px; display: grid; gap: 8px; align-content: start; }}
.fact h3 {{ margin: 0; font: 600 15px var(--display); }}
.fact p {{ font-size: 14px; color: var(--muted); }}
.pick {{ border: 2px solid var(--accent); background: var(--accent-soft); border-radius: 12px; padding: 18px 20px; display: grid; gap: 8px; }}
.pick h2 {{ color: var(--accent); }}
@media (prefers-reduced-motion: reduce) {{ .stage {{ transition: none; }} }}
</style>

<div class="wrap">
  <header>
    <span class="eyebrow">Machine Party · GameCube Controller Support mod · art proposal</span>
    <h1>GameCube Glyph Picker</h1>
    <p class="lede">The GameCube Controller Support mod swaps these glyphs in for the game's own when a GameCube pad is in use. The default is <strong>Classic</strong>: the game's own thin white-outline look, with the GameCube face layout. The prompted button is filled in, just as vanilla fills one dot of its diamond. The outline, coloured and letters-only sets ship too, and <code>gc art</code> switches between them.</p>
  </header>

  <section aria-labelledby="ctx">
    <h2 id="ctx">In the game</h2>
    <p class="legend">The intermission controls page draws each 32&thinsp;px glyph at half size (16&thinsp;px) with smooth filtering. How big that ends up on your screen depends on your resolution, so try the zoom levels. The rows below are examples, not a real minigame.</p>
    <div class="controls">
      <span class="lbl">Zoom</span>
      <div class="seg" id="zoom" role="group" aria-label="Zoom">
        <button type="button" id="z1" data-v="1" aria-pressed="false">1×</button>
        <button type="button" id="z2" data-v="2" aria-pressed="true">2×</button>
        <button type="button" id="z3" data-v="3" aria-pressed="false">3×</button>
      </div>
      <span class="lbl">Backdrop</span>
      <div class="seg" id="bg" role="group" aria-label="Backdrop">
        <button type="button" id="b1" data-v="#17181f" aria-pressed="true">Dark</button>
        <button type="button" id="b2" data-v="#5a6172" aria-pressed="false">Mid</button>
        <button type="button" id="b3" data-v="#d8dbe2" aria-pressed="false">Light</button>
      </div>
    </div>
    <div class="mocks">
{mocks}
    </div>
  </section>

  <section aria-labelledby="btns">
    <h2 id="btns">Button by button</h2>
    <p class="legend">Each cell shows the glyph at 16&thinsp;px (in-game size), 32&thinsp;px (file size) and 3× with hard pixels. The vanilla column is our own redraw of the game's style, for reference. For the face buttons, vanilla lights one dot of a diamond. On a GameCube pad that dot points the wrong way for B and X.</p>
    <div class="table-wrap">
      <table>
        <thead><tr><th>Game slot → GameCube</th><th>Vanilla style</th><th>Classic (default)</th><th>Outline</th><th>Authentic colours</th><th>Letters only</th></tr></thead>
        <tbody>
{rows}
{wide_rows}
        </tbody>
      </table>
    </div>
  </section>

  <section aria-labelledby="notes">
    <h2 id="notes">What to know before choosing</h2>
    <div class="facts">
      <div class="fact"><h3>L has two jobs</h3><p>The game's LB is the full click at the bottom of L. Its LT is the analog pull. The L with a bar under it means "squeeze all the way".</p></div>
      <div class="fact"><h3>Z stands in for RB</h3><p>The Mayflash adapter reports Z as the right shoulder, so anywhere the game says RB you'll see Z.</p></div>
      <div class="fact"><h3>Mapping not yet confirmed</h3><p>B and X sit where the adapter's Godot controller mapping puts them. The hardware probe confirms that before release. If it differs, only the mapping changes, not the art.</p></div>
      <div class="fact"><h3>Auto switching</h3><p>Prompts follow the last pad that pressed a button, switching at most once a second. 8BitDo pads keep the vanilla glyphs.</p></div>
    </div>
  </section>

  <section class="pick" aria-labelledby="choose">
    <h2 id="choose">Chosen: Classic</h2>
    <p>Classic is the default. To switch in game, type <code>gc art outline</code>, <code>gc art authentic</code> or <code>gc art letters</code> in the <code>~</code> console, or set <code>"art"</code> in <code>gamecube_support.json</code>.</p>
  </section>
</div>

<script>
(function () {{
  function wire(groupId, apply) {{
    var group = document.getElementById(groupId);
    group.addEventListener('click', function (e) {{
      var btn = e.target.closest('button');
      if (!btn) return;
      group.querySelectorAll('button').forEach(function (b) {{ b.setAttribute('aria-pressed', String(b === btn)); }});
      apply(btn.dataset.v);
    }});
  }}
  wire('zoom', function (v) {{ document.documentElement.style.setProperty('--zoom', v); }});
  wire('bg', function (v) {{
    document.querySelectorAll('.stage').forEach(function (s) {{
      s.style.background = v;
      s.style.color = v === '#d8dbe2' ? '#1c1a28' : '';
    }});
  }});
}})();
</script>
"""


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--art", choices=[*ARTS, "all"], default="all")
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--preview", type=Path, help="also write a comparison HTML page here")
    ap.add_argument("--no-glyphs", action="store_true", help="only write the preview")
    a = ap.parse_args()
    if not a.no_glyphs:
        for art in (ARTS if a.art == "all" else [a.art]):
            write_set(art, a.out)
    if a.preview:
        preview(a.preview)


if __name__ == "__main__":
    main()
