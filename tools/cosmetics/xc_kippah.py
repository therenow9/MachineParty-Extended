"""xc_kippah: a black velvet kippah with a stitched rim, on top of the crown.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_kippah.py [-- --preview DIR]

Blender axes in the top hat's mesh space: z up the hat, +x the face, -y the
character's right. It is an even dome round the head's own up axis (which
leans forward here), centred just behind where that axis leaves the crown: the
rim is a flat circle fitted to the scalp under it, and the dome rises from it
just enough to clear the scalp everywhere, at least DOME at the centre, so it
reads as a round cap rather than a patch following every bump.
The table stops at y 0.0 and the crown peaks at about 0.026 (xc_recon's
guide), so above the table the top row's radius rounds off to CROWN.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_kippah"
SEGMENTS = 32
VELVET, RIM = range(2)
AX = common.HEAD_AXIS_X_IN_TOPHAT
CROWN = 0.03
BEHIND = 0.02
RADIUS = 0.18
OUT = 0.007
DOME = 0.012


def head_at(h, t):
    if h <= 0.0:
        return common.head_radius(common.HEAD_RADIUS_IN_TOPHAT, h, t)
    return common.head_radius(common.HEAD_RADIUS_IN_TOPHAT, 0.0, t) * math.sqrt(max(0.0, 1 - (h / CROWN) ** 2))


up = Vector(common.to_blender(*common.UP_IN_TOPHAT)).normalized()
face = Vector(common.to_blender(*common.FACE_IN_TOPHAT))
face = (face - up * face.dot(up)).normalized()
right = face.cross(up)


def inside(q):
    return math.hypot(q.x - AX, q.y) < head_at(q.z, math.atan2(-q.y, q.x - AX))


def drop(p):
    """p moved down the head's up axis onto the scalp."""
    q = p + up * 0.15
    for _ in range(300):
        if inside(q):
            break
        q -= up * 0.001
    return q


def crown():
    q = Vector((AX, 0.0, -0.3))
    while inside(q):
        q += up * 0.001
    return q - face * BEHIND


TOP = crown()


def scalp(q, t):
    """How far up the head's axis the scalp is, at q of RADIUS out from TOP toward t."""
    return (drop(TOP + (face * math.cos(t) + right * math.sin(t)) * q * RADIUS) - TOP).dot(up)


def ring_fit(q):
    """The scalp's heights round the ring q of RADIUS out, smoothed to a few
    harmonics so the ring is one even curve, and raised until none of it is
    under the scalp."""
    angles = [2 * math.pi * i / SEGMENTS for i in range(SEGMENTS)]
    heights = [scalp(q, t) for t in angles]
    terms = [lambda t: 1.0, math.cos, math.sin, lambda t: math.cos(2 * t), lambda t: math.sin(2 * t)]
    coef = [sum(h * f(t) for h, t in zip(heights, angles)) / len(angles) * (1 if k == 0 else 2) for k, f in enumerate(terms)]

    def smooth(t):
        return sum(c * f(t) for c, f in zip(coef, terms))
    coef[0] += max(h - smooth(t) for h, t in zip(heights, angles))
    return smooth


def point(q, t, lift):
    """q of RADIUS out from the centre toward t, on the even scalp, puffed up
    by DOME toward the middle, plus lift."""
    h = ring_fit(q)(t) if q > 0 else scalp(0.0, 0.0)
    return tuple(TOP + (face * math.cos(t) + right * math.sin(t)) * q * RADIUS
                 + up * (h + OUT + DOME * math.sqrt(1 - min(1.0, q) ** 2) + lift))


def main():
    opts = common.args()
    common.reset()
    # Toward the character's left as i grows, from the rim's underside in to the
    # centre, so the faces point out of the head.
    angles = [-2 * math.pi * i / SEGMENTS for i in range(SEGMENTS)]
    rings, mats = [], []
    for q, lift, m in ((0.975, -OUT - 0.004, RIM), (1.0, -0.002, RIM), (0.93, 0.002, VELVET)):
        rings.append([point(q, t, lift) for t in angles])
        mats.append(m)
    for q in (0.8, 0.62, 0.44, 0.26):
        rings.append([point(q, t, 0.0) for t in angles])
        mats.append(VELVET)
    ob = common.rings_mesh(ID, rings, mats, cap=point(0.0, 0.0, 0.0))
    materials = [
        # Black velvet: a low sheen where the pile catches the light, dust in the nap.
        common.worn("velvet", "0e0d10", "1e1c22", grime=0.3, grime_scale=6.0, grain_scale=320.0, grain=0.2, edge_hex="2c2932", edge=0.4),
        common.worn("rim", "0e0d10", "2a2830", grime=0.2, grain=0.1, edge_hex="56525e", edge=0.3, pattern=("4a4654", 160.0, "WAVE")),
    ]
    for mat in materials:
        ob.data.materials.append(mat)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "tophat", "tophat", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
