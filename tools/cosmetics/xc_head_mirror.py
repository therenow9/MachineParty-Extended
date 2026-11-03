"""xc_head_mirror: a doctor's head mirror on a headband, centred on the forehead.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_head_mirror.py [-- --preview DIR]

Blender axes in the top hat's mesh space: z up the hat, +x the face, -y the
character's right. The band rides just outside the head's measured radius,
across the forehead and lower at the back; the concave mirror, with its sight
hole, stands off the band on a short arm, tilted down, above the eyes.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_head_mirror"
SEGMENTS = 40
BAND, MIRROR, HOUSING, METAL = range(4)
BAND_WIDTH = 0.042
RADIUS = 0.11
CENTER = Vector((0.31, 0.0, -0.075))
NORMAL = Vector((math.cos(math.radians(15)), 0.0, -math.sin(math.radians(15))))
# Round the mirror's edge and through its hole: (radius, depth along NORMAL, material of the strip toward the next).
SECTION = [(0.012, -0.012, MIRROR), (0.045, -0.009, MIRROR), (0.080, -0.004, MIRROR), (RADIUS, 0.0, HOUSING),
           (RADIUS + 0.006, -0.007, HOUSING), (RADIUS, -0.015, HOUSING), (0.060, -0.025, HOUSING),
           (0.014, -0.029, HOUSING), (0.012, -0.012, MIRROR)]


def middle(t):
    """The band's centre line: on the forehead at the face, lower at the back."""
    return -0.12 - 0.03 * (1 - math.cos(t))


def band():
    # Toward the character's left as i grows, so the faces point out of the head.
    angles = [-2 * math.pi * i / SEGMENTS for i in range(SEGMENTS)]
    w = BAND_WIDTH / 2
    rows = [(-w, 0.004), (-w, 0.012), (w, 0.012), (w, 0.004), (-w, 0.004)]
    rings = [[common.around_tophat_head(middle(t) + dh, t, out) for t in angles] for dh, out in rows]
    return common.rings_mesh("band", rings, [BAND] * 4)


def mirror():
    up = Vector((0.0, 0.0, 1.0))
    a = (up - NORMAL * up.dot(NORMAL)).normalized()
    b = a.cross(NORMAL)  # this way round the faces point out of the dish
    n = 24
    rings = [[tuple(CENTER + NORMAL * d + a * (r * math.cos(2 * math.pi * k / n)) + b * (r * math.sin(2 * math.pi * k / n)))
              for k in range(n)] for r, d, _ in SECTION]
    return common.rings_mesh("mirror", rings, [m for *_, m in SECTION[:-1]])


def arm():
    """From a plate on the band's front to a ball joint behind the mirror."""
    x, y, z = common.around_tophat_head(middle(0.0), 0.0, 0.014)
    plate = Vector((x, y, z))
    ball = CENTER - NORMAL * 0.034
    return [
        common.ellipsoid("plate", tuple(plate + Vector((0.004, 0, 0))), (0.008, 0.024, 0.018), 10, 4, METAL),
        common.tube("arm", [tuple(plate), tuple(ball)], 0.007, 6, METAL),
        common.ellipsoid("ball", tuple(ball), (0.013, 0.013, 0.013), 8, 4, METAL),
    ]


def main():
    opts = common.args()
    common.reset()
    parts = [band(), mirror()] + arm()
    materials = [
        common.worn("band", "262422", "4d4840", grime=0.3, grain=0.1, pattern=("1a1918", 260.0, "WAVE")),
        common.worn("mirror", "c3c6c6", "5d5a55", grime=0.35, grime_scale=7.0, grain=0.04),
        common.worn("housing", "3c3b39", "1f1d1b", grime=0.3, grain=0.08, edge_hex="8a877f", edge=0.7),
        common.worn("metal", "7a776f", "33302b", grime=0.3, grain=0.06, edge_hex="b3afa5", edge=0.5),
    ]
    ob = common.assemble(ID, parts, materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "tophat", "tophat", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
