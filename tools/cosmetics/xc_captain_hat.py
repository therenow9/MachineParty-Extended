"""xc_captain_hat: a ship captain's cap, white crown, black visor, gold braid and anchor.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_captain_hat.py [-- --preview DIR]

Blender axes in the top hat's mesh space: z up the hat, +x the face, -y the
character's right. The band sits on the chef's hat's measured ellipse (the top
hat's crown); the crown flares over it, higher at the front, and the visor
leaves the band's lower edge at the face.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_captain_hat"
SEGMENTS = 36
CROWN, BAND, VISOR, GOLD = range(4)
CENTER = (-0.01, 0.0)
# (z, half-width along x, half-width along y, front lift, material of the strip above).
PROFILE = [
    (-0.225, 0.292, 0.268, 0.0, BAND),
    (-0.140, 0.296, 0.272, 0.0, CROWN),
    (-0.090, 0.318, 0.294, 0.010, CROWN),
    (-0.020, 0.362, 0.338, 0.030, CROWN),
    (0.012, 0.374, 0.350, 0.040, CROWN),
    (0.030, 0.360, 0.336, 0.040, CROWN),
    (0.042, 0.300, 0.280, 0.034, CROWN),
    (0.050, 0.180, 0.168, 0.026, CROWN),
]
TOP = 0.054
REACH = 0.085  # how far the bill reaches ahead of the band at the middle


def ring(z, ax, ay, lift):
    """The front rises by lift, falling off toward the back like a saddle."""
    return [(CENTER[0] + ax * math.cos(t), CENTER[1] + ay * math.sin(t), z + lift * max(0.0, math.cos(t)) ** 2)
            for t in (2 * math.pi * i / SEGMENTS for i in range(SEGMENTS))]


def crown():
    rings = [ring(z, ax, ay, lift) for z, ax, ay, lift, _ in PROFILE]
    return common.rings_mesh("crown", rings, [m for *_, m in PROFILE[:-1]] + [CROWN], cap=(*CENTER, TOP + 0.02))


def visor():
    """A short crescent bill pointing straight ahead: its inner edge follows the
    band's lower edge across the front 110 degrees, its outer edge reaches REACH
    ahead at the middle and rounds back into the band at both ends, and it
    angles down; two layers so it has an edge."""
    z0, ax, ay = PROFILE[0][0], PROFILE[0][1], PROFILE[0][2]
    span = [math.radians(-55 + 110 * i / 12) for i in range(13)]
    inner = [(CENTER[0] + ax * math.cos(t), CENTER[1] + ay * math.sin(t)) for t in span]
    # The outer edge: straight ahead of the inner by REACH times a rounded taper
    # that is 1 at the middle and 0 at the ends, so there are no corners.
    outer = [(x + REACH * math.cos(t / math.radians(55) * math.pi / 2) ** 0.6, y) for (x, y), t in zip(inner, span)]
    rows = []
    for f, drop, thick in ((0.0, 0.0, 0.0), (0.5, 0.022, 0.0), (1.0, 0.05, 0.0), (1.0, 0.05, -0.008), (0.0, 0.0, -0.008)):
        rows.append([(i[0] + (o[0] - i[0]) * f, i[1] + (o[1] - i[1]) * f, z0 + 0.004 - drop + thick) for i, o in zip(inner, outer)])
    verts = [p for row in rows for p in row]
    n = len(span)
    faces = []
    for r in range(len(rows) - 1):
        for i in range(n - 1):
            faces.append((r * n + i, (r + 1) * n + i, (r + 1) * n + i + 1, r * n + i + 1))
    return common.mesh_object("visor", verts, faces, [VISOR] * len(faces))


def braid():
    """A twisted gold cord across the front of the band, ending in a button each side."""
    z = PROFILE[0][0] + 0.052
    ax, ay = PROFILE[0][1] + 0.008, PROFILE[0][2] + 0.008
    path = []
    for i in range(15):
        t = math.radians(-62 + 124 * i / 14)
        path.append((CENTER[0] + ax * math.cos(t), CENTER[1] + ay * math.sin(t), z + 0.004 * math.sin(i * 1.7)))
    parts = [common.tube("braid", path, 0.008, 6, GOLD)]
    for t in (math.radians(-64), math.radians(64)):
        c = (CENTER[0] + (ax + 0.002) * math.cos(t), CENTER[1] + (ay + 0.002) * math.sin(t), z)
        parts.append(common.ellipsoid("button", c, (0.012, 0.012, 0.012), 8, 4, GOLD))
    return parts


def anchor():
    """A small anchor badge in gold on the crown's front, above the band: shank,
    stock, ring and a curved pair of arms, each a short bar standing off the cloth."""
    front = Vector((1.0, 0.0, 0.0))
    base = Vector((CENTER[0] + 0.322 + 0.006, 0.0, -0.075))
    up = Vector((0.6, 0.0, 1.0)).normalized()  # the crown leans out as it rises
    side = Vector((0.0, 1.0, 0.0))

    def p(u, v):
        return tuple(base + side * u + up * v + front * 0.004)
    bars = [
        [p(0, -0.035), p(0, 0.03)],                                   # shank
        [p(-0.022, 0.018), p(0.022, 0.018)],                          # stock
        [p(-0.03, -0.012), p(-0.024, -0.03), p(-0.01, -0.04), p(0, -0.042),
         p(0.01, -0.04), p(0.024, -0.03), p(0.03, -0.012)],          # arms
    ]
    parts = [common.tube("anchor", bar, 0.0045, 5, GOLD, up=tuple(front)) for bar in bars]
    ring_pts = [p(0.009 * math.sin(a), 0.039 + 0.009 * math.cos(a)) for a in (2 * math.pi * i / 8 for i in range(8))]
    parts.append(common.tube("ring", ring_pts, 0.003, 4, GOLD, closed=True, up=tuple(front)))
    return parts


def main():
    opts = common.args()
    common.reset()
    parts = [crown(), visor()] + braid() + anchor()
    materials = [
        # Sea-worn: salt stains and yellowed cloth, a cracked bill, tarnished braid.
        common.worn("crown", "cfc8b6", "6f624c", grime=0.65, grime_scale=3.5, grain=0.18, edge_hex="9a8f78", edge=0.6, scratches=0.35),
        common.worn("band", "1d1b1a", "4a443a", grime=0.5, grain=0.2, edge_hex="5a554b", edge=0.7, scratches=0.3),
        common.worn("visor", "141312", "3d3a35", grime=0.35, grain=0.08, edge_hex="6a655b", edge=1.0, scratches=0.5),
        common.worn("gold", "9c7a34", "3f2f16", grime=0.55, grain=0.12, edge_hex="d6b56c", edge=0.7, scratches=0.3),
    ]
    ob = common.assemble(ID, parts, materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "tophat", "tophat", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
