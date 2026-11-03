"""xc_army_helmet: an M1 steel pot in chipped olive drab, chin straps hanging loose.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_army_helmet.py [-- --preview DIR]

Blender axes in the top hat's mesh space: z up the hat, +x the face, -y the
character's right. The shell stands GAP off the head's measured radius, with
the rim highest at the brow and lowest over the ears; the straps hang from
inside the rim at each side, unfastened.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_army_helmet"
SEGMENTS = 40
SHELL, RIM, STRAP, BUCKLE = range(4)
GAP = 0.042
DOME_FROM, TOP = -0.15, 0.088
AX = common.HEAD_AXIS_X_IN_TOPHAT


def rim(t):
    """Just above the brow at the face, lowest over the ears, a little higher at the back."""
    return -0.15 - 0.13 * math.sin(t) ** 2 - 0.05 * (1 - math.cos(t))


def footprint(t):
    """The shell's radius below the dome: the head's widest over the brow band,
    smoothed round the head so the steel stays one clean curve, plus GAP."""
    def widest(u):
        return max(math.hypot(x - AX, y) for x, y, _ in (common.around_tophat_head(h, u) for h in (-0.30, -0.25, -0.20, -0.15, -0.10)))
    return sum(widest(t + k * 0.12) for k in range(-4, 5)) / 9 + GAP


def at(t, h, out=0.0):
    """A point on the shell at angle t and height h: upright sides below
    DOME_FROM, then an elliptical dome up to TOP."""
    k = 1.0 if h <= DOME_FROM else math.sqrt(max(0.0, 1 - ((h - DOME_FROM) / (TOP - DOME_FROM)) ** 2))
    r = footprint(t) * k + out
    return (AX + r * math.cos(t), -r * math.sin(t), h)


def shell():
    # Toward the character's left as i grows, so the faces point out of the head.
    angles = [-2 * math.pi * i / SEGMENTS for i in range(SEGMENTS)]
    rings, mats = [], []
    # The rolled rim: inside, under the roll, its outer lip, then the shell.
    for lift, out, m in ((0.012, -0.012, RIM), (-0.016, 0.02, RIM), (-0.004, 0.028, RIM), (0.014, 0.002, SHELL)):
        rings.append([at(t, rim(t) + lift, out) for t in angles])
        mats.append(m)
    for s in (0.5, 1.0):
        rings.append([at(t, rim(t) + 0.014 + s * (DOME_FROM - rim(t) - 0.014)) for t in angles])
        mats.append(SHELL)
    for k in (1, 2, 3, 4, 5):
        h = DOME_FROM + (TOP - DOME_FROM) * math.sin(math.pi / 2 * k / 6)
        rings.append([at(t, h) for t in angles])
        mats.append(SHELL)
    return common.rings_mesh("shell", rings, mats[:-1] + [SHELL], cap=(AX, 0.0, TOP))


def strap(side):
    """side 1 is the character's right. Hangs from inside the rim, swings a little
    toward the face, and stays clear of the cheek."""
    t0 = side * math.pi / 2
    top = rim(t0) + 0.03
    path = []
    for i in range(9):
        f = i / 8
        t = t0 - side * 0.3 * f * f
        h = top - 0.23 * f
        x, y, _ = common.around_tophat_head(h, t, 0.03)
        r_hang = footprint(t0) - 0.016
        r = max(math.hypot(x - AX, y), r_hang + 0.012 * math.sin(math.pi * f))
        path.append((AX + r * math.cos(t), -r * math.sin(t), h))
    mid = path[len(path) // 2]
    radial = (mid[0] - AX, mid[1], 0.0)
    return common.tube("strap", path, 0.02, 4, STRAP, flat=0.14, up=radial), path[-1], radial


def buckle(at, radial):
    """An open wire buckle on the end of the right strap."""
    r = Vector(radial).normalized()
    side = r.cross(Vector((0, 0, 1))).normalized()
    c = Vector(at) - Vector((0, 0, 0.016))
    corners = [c + side * sx * 0.019 + Vector((0, 0, sz * 0.015)) for sx, sz in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
    return common.tube("buckle", [tuple(p) for p in corners], 0.0035, 5, BUCKLE, closed=True, up=tuple(r))


def main():
    opts = common.args()
    common.reset()
    parts = [shell()]
    right, end, radial = strap(1)
    left, _, _ = strap(-1)
    parts += [right, left, buckle(end, radial)]
    materials = [
        # Paint chipped to dark steel, mud and rust streaks, a sandy finish.
        common.worn("shell", "474c2e", "241c14", grime=0.75, grime_scale=3.5, grain_scale=220.0, grain=0.45, edge_hex="7a7468", edge=1.0, scratches=0.95),
        common.worn("rim", "3d4229", "1f1812", grime=0.7, grain_scale=220.0, grain=0.35, edge_hex="857a68", edge=1.0, scratches=0.95),
        common.worn("strap", "62593f", "2f281d", grime=0.6, grime_scale=4.0, edge_hex="7d735a", edge=0.6, pattern=("524a35", 300.0, "WAVE")),
        common.worn("buckle", "6a665d", "2e2822", grime=0.5, grain=0.08, edge_hex="7a5a3a", edge=0.8, scratches=0.5),
    ]
    ob = common.assemble(ID, parts, materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "tophat", "tophat", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
