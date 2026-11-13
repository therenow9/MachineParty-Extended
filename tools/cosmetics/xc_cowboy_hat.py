"""xc_cowboy_hat: a gunslinger's cowboy hat after the owner's pictures of Red
in Red Dead Revolver: weathered charcoal felt, a rounded crown with a soft
dent, a wide flat brim drooping front and back, a dark leather band with
silver diamond studs.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_cowboy_hat.py [-- --preview DIR]

Blender axes in the top hat's mesh space: z up the hat, +x the face, -y the
character's right. The hat sits level on the head, so it is built in the head's
own frame (common.level_point): heights along common.UP_IN_TOPHAT from the
hat line, just above the ears' tops, round an axis through the head's middle
there. The crown's opening is the head's measured radius plus GAP.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_cowboy_hat"
FELT, BAND, METAL = range(3)
SEGMENTS = 28
GAP = 0.012
HAT_LINE = -0.17  # the ears' tops are near -0.19, the brow near -0.23
# The crown's height over the hat line, the top's rounding, the crease's depth
# and half-width, the front pinches' depth, the brim's reach past the opening
# (front-back, sides), the side curl, the front-back dip, the band's height,
# and the felt (base, dust, edge wear), deep because the lobby's key light
# washes felt out.
S = dict(height=0.25, round=0.055, crease=0.035, crease_w=0.07, pinch=0.012, reach=(0.27, 0.26),
         curl=0.025, dip=0.05, band=0.05, felt=("222120", "47433c", "56524a"), band_hex="1a120d")


def at(r, phi, c):
    return common.level_point(HAT_LINE, r, phi, c)


def head_r(c, phi):
    return common.level_head_radius(HAT_LINE + c, phi)


def smooth(e):
    e = min(max(e, 0.0), 1.0)
    return e * e * (3 - 2 * e)


PHIS = [2 * math.pi * i / SEGMENTS for i in range(SEGMENTS)]
# The opening: the head above the hat line, plus GAP.
OPEN = [max(head_r(c, p) for c in (0.0, 0.02, 0.04, 0.06)) + GAP for p in PHIS]


def wall_r(i, u, s):
    """The crown's radius at angle PHIS[i], u of the way up the wall: a little
    tapered, pinched in at the front near the top."""
    p = PHIS[i]
    r = OPEN[i] * (1.0 + 0.04 * math.sin(math.pi * u) - 0.08 * u)
    for side in (1, -1):
        d = math.remainder(p - side * math.radians(38), 2 * math.pi)
        r -= s["pinch"] * math.exp(-(d / 0.42) ** 2) * smooth((u - 0.35) / 0.65)
    return r


def dent(i, frac, s):
    """How far the crease presses the top down at angle PHIS[i], frac of the way
    out from the middle: along the hat's length, deepest at the front."""
    p = PHIS[i]
    lateral = abs(math.sin(p)) * frac * OPEN[i]
    along = 0.8 + 0.2 * math.cos(p)
    return s["crease"] * along * math.exp(-(lateral / s["crease_w"]) ** 2)


def crown(s):
    """The wall from the brim up, the top's rounded edge, the creased top to its middle."""
    h = s["height"]
    rings = []
    for u in (0.0, 0.08, 0.2, 0.4, 0.6, 0.78, 0.9, 1.0):
        rings.append([at(wall_r(i, u, s), p, h * u - (dent(i, 1.0, s) * 0.7 * smooth((u - 0.7) / 0.3))) for i, p in enumerate(PHIS)])
    for frac in (0.88, 0.68, 0.45, 0.22):
        lift = s["round"] * math.sqrt(1 - frac * frac)
        rings.append([at(wall_r(i, 1.0, s) * frac, p, h + lift - dent(i, frac, s)) for i, p in enumerate(PHIS)])
    top = h + s["round"] - s["crease"]
    if top < common.LEVEL_HEAD_TOP - HAT_LINE + GAP:
        raise SystemExit("the crease's bottom %.3f is inside the head (%.3f)" % (top, common.LEVEL_HEAD_TOP - HAT_LINE))
    return common.rings_mesh("crown", rings, [FELT] * len(rings), cap=at(0.0, 0.0, top))


# Two small pieces missing from the brim's edge on the wearer's right, as on
# Red's hat: (angle, half-width, depth). The brim gets extra angles round each.
NOTCHES = [(math.radians(-60), math.radians(6), 0.075), (math.radians(-125), math.radians(5), 0.06)]
BRIM_PHIS = sorted(PHIS + [(n + w * k) % (2 * math.pi) for n, w, _ in NOTCHES for k in (-1.0, -0.5, 0.0, 0.5, 1.0)])


def open_r(p):
    return max(head_r(c, p) for c in (0.0, 0.02, 0.04, 0.06)) + GAP


def notch(p):
    """How far the brim's edge is cut back at angle p: a V at each notch."""
    return max([d * max(0.0, 1 - abs(math.remainder(p - n, 2 * math.pi)) / w) for n, w, d in NOTCHES])


def brim_c(f, p, s):
    """The brim's top at angle p, f of the way out: curled up a little at the sides, drooping front and back."""
    return s["curl"] * math.sin(p) ** 2 * smooth((f - 0.3) / 0.7) ** 1.6 - s["dip"] * math.cos(p) ** 2 * f ** 1.6


def brim(s):
    """From under the brim at the crown out to the edge and back over the top, so
    the faces point out of the felt. Where a notch cuts the edge back, the
    brim's outer half is drawn in toward the cut, so no face loses its area."""
    t = 0.013
    under = [(0.0, -t), (0.25, -t), (0.5, -t), (0.75, -t), (0.93, -t), (1.0, -t * 0.55)]
    top = [(1.0, -t * 0.25), (0.97, 0.0), (0.88, 0.0), (0.7, 0.0), (0.45, 0.0), (0.2, 0.0), (0.0, 0.0)]
    rows = under + top
    rings = []
    for f, dz in rows:
        ring = []
        for p in BRIM_PHIS:
            reach = math.hypot(s["reach"][0] * math.cos(p), s["reach"][1] * math.sin(p))
            fe = f - notch(p) / reach * smooth((f - 0.5) / 0.5)
            ring.append(at(open_r(p) + fe * reach, p, brim_c(fe, p, s) + dz))
        rings.append(ring)
    return common.rings_mesh("brim", rings, [FELT] * len(rings))


def band(s):
    """A band round the crown's foot, standing off the wall."""
    h, out = s["band"], 0.005
    rings = [[at(wall_r(i, u, s) + out * k, p, u * s["height"]) for i, p in enumerate(PHIS)]
             for u, k in ((0.004, 0.0), (0.012, 1.0), (h / s["height"], 1.0), (h / s["height"] + 0.006, 0.0))]
    return [common.rings_mesh("band", rings, [BAND] * len(rings))]


def studs(s):
    """Silver diamonds round the band, each a low pyramid on the leather."""
    parts = []
    mid = s["band"] / 2 + 0.003
    for k in range(10):
        p = 2 * math.pi * k / 10
        i = round(p / (2 * math.pi) * SEGMENTS) % SEGMENTS
        r = wall_r(i, mid / s["height"], s) + 0.006
        c = Vector(at(r, p, mid))
        out = (common.LEVEL_FACE * math.cos(p) + common.LEVEL_LEFT * math.sin(p))
        side = common.LEVEL_FACE * -math.sin(p) + common.LEVEL_LEFT * math.cos(p)
        a, b = common.LEVEL_UP * (s["band"] * 0.46), side * 0.024
        rim = [tuple(c + a), tuple(c + b), tuple(c - a), tuple(c - b)]
        tip = tuple(c + out * 0.007)
        verts = rim + [tip]
        faces = [(1, 0, 4), (2, 1, 4), (3, 2, 4), (0, 3, 4)]
        ob = common.mesh_object("stud%d" % k, verts, faces, [METAL] * 4)
        if sum(q.normal.dot(out) for q in ob.data.polygons) < 0:
            ob.data.flip_normals()
        parts.append(ob)
    return parts


def main():
    opts = common.args()
    common.reset()
    s = S
    base, dirt, wear = s["felt"]
    parts = [crown(s), brim(s)] + band(s) + studs(s)
    materials = [
        common.worn("felt", base, dirt, grime=0.4, grime_scale=4.0, grain_scale=260.0, grain=0.2, edge_hex=wear, edge=0.5, scratches=0.15),
        common.worn("band", s["band_hex"], "120c08", grime=0.3, grain_scale=200.0, grain=0.2),
        common.worn("metal", "c9ccd0", "6c6e72", grime=0.2, grain=0.05, edge_hex="f4f6f8", edge=0.8),
    ]
    ob = common.assemble(ID, parts, materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID))
    print("wrote", common.export(ob, ID, smooth_angle=40))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "tophat", "tophat", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
