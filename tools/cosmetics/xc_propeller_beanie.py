"""xc_propeller_beanie: a brimless four-panel cap with a plastic propeller.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_propeller_beanie.py [-- --preview DIR]

Blender axes in the top hat's mesh space: z up the hat, +x the face, -y the
character's right. The cap is round and level: one even circle round the head
from a hem above the ears, standing off the head's measured radius, then one
rounded curve over the crown.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402

ID = "xc_propeller_beanie"
SEGMENTS = 32
RED, YELLOW, BLUE, GREEN, PROP, METAL, HUB = range(7)
# Quarters from the face round toward the right: a seam faces front, red on
# the right of it and green on the left, so two colours show from the front.
PANELS = [RED, YELLOW, BLUE, GREEN]
OUT = 0.014
# The hem, level all round just above the ears (the table's ears run from about
# y -0.36 to -0.20); the brow is near -0.30.
HEM = -0.175
TOP = 0.055
TUCK = 0.008  # how far the hem curls in from the cap's widest
ROLL = 0.009  # the hem's rolled edge, a half round
STEM, BLADE = 0.075, 0.24
AX = common.HEAD_AXIS_X_IN_TOPHAT


def footprint(t):
    """The cap's radius below the dome: the head's widest between the hem and the
    dome, smoothed round the head so the hem is one even circle (the ears end
    just under it), plus OUT."""
    def widest(u):
        return max(math.hypot(x - AX, y) for x, y, _ in (common.around_tophat_head(h, u) for h in (HEM + 0.01, -0.14, -0.1, -0.06)))
    return sum(widest(t + k * 0.1) for k in range(-3, 4)) / 7 + OUT


def at(t, h, out=0.0):
    r = footprint(t) + out
    return (AX + r * math.cos(t), -r * math.sin(t), h)


def cap():
    rings = []
    # Toward the character's left as i grows, so the faces point out of the head.
    angles = [-2 * math.pi * i / SEGMENTS for i in range(SEGMENTS)]
    # The hem rolls under in a half round, tucked in a little, from inside the cap
    # round to its outside; every ring is level.
    for a in (180, 225, 270, 315, 0):
        lift = 0.008 + ROLL * math.sin(math.radians(a))
        out = -TUCK + ROLL * math.cos(math.radians(a))
        rings.append([at(t, HEM + lift, out) for t in angles])
    # Then one rounded curve from the hem to the top: full just above the hem,
    # turning over into the crown, never closer to the head than it stands at the hem.
    steps = 9
    for k in range(steps):
        a = math.pi / 2 * k / steps
        h = HEM + 0.016 + (TOP - HEM - 0.016) * math.sin(a)
        ring = []
        for t in angles:
            r = (footprint(t) - TUCK * (1 - math.sin(2 * a + 0.3))) * math.cos(a) ** 0.55
            if h < 0.03:
                hx, hy, _ = common.around_tophat_head(h, t, 0.008)
                r = max(r, math.hypot(hx - AX, hy))
            ring.append((AX + r * math.cos(t), -r * math.sin(t), h))
        rings.append(ring)
    ob = common.rings_mesh("cap", rings, cap=(AX, 0.0, TOP))
    # Each face takes the panel its centre lies in.
    mats = []
    for p in ob.data.polygons:
        c = p.center
        t = math.atan2(-c.y, c.x - AX)
        mats.append(PANELS[int((t % (2 * math.pi)) // (math.pi / 2))])
    ob.data.polygons.foreach_set("material_index", mats)
    return ob


def propeller():
    top = TOP + 0.004
    parts = [
        common.ellipsoid("button", (AX, 0, top), (0.028, 0.028, 0.014), 12, 5, RED),
        common.tube("stem", [(AX, 0, top), (AX, 0, top + STEM)], 0.009, 6, METAL),
        common.ellipsoid("hub", (AX, 0, top + STEM + 0.002), (0.022, 0.022, 0.016), 10, 4, HUB),
    ]
    # Long and broad enough to read as a propeller from across the room, and
    # turned 45 degrees so neither the front nor the side sees it edge-on.
    c, s = math.cos(math.pi / 4), math.sin(math.pi / 4)
    for side in (1, -1):
        path = []
        for f in (0.0, 0.25, 0.5, 0.75, 1.0):
            a, b = side * (0.016 + BLADE * f), 0.006 * side * f
            path.append((AX + a * c - b * s, a * s + b * c, top + STEM + 0.002 + 0.012 * f))
        parts.append(common.tube("blade", path, [0.02, 0.042, 0.048, 0.042, 0.02], 8, PROP, flat=0.2))
    return parts


def main():
    opts = common.args()
    common.reset()
    materials = [
        # Bold felt panels that read at a distance, still scuffed and grubby at the hem.
        common.worn("red", "b02a20", "40261c", grime=0.35, grime_scale=4.0, grain=0.22, edge_hex="c08a70", edge=0.5, scratches=0.2),
        common.worn("yellow", "d9a51c", "4a3a1c", grime=0.35, grime_scale=4.0, grain=0.22, edge_hex="e0c27a", edge=0.5, scratches=0.2),
        common.worn("blue", "2457a8", "22283a", grime=0.35, grime_scale=4.0, grain=0.22, edge_hex="7a95c0", edge=0.5, scratches=0.2),
        common.worn("green", "2f8a36", "24301e", grime=0.35, grime_scale=4.0, grain=0.22, edge_hex="80b07a", edge=0.5, scratches=0.2),
        common.worn("prop", "c8281c", "4a2a22", grime=0.3, grain=0.08, edge_hex="e8d0b0", edge=0.7, scratches=0.25),
        common.worn("metal", "7a766e", "2a2622", grime=0.4, grain=0.1, edge_hex="b09068", edge=0.7, scratches=0.4),
        common.worn("hub", "e0b020", "4a3a1c", grime=0.3, grain=0.08, edge_hex="f0dca0", edge=0.6, scratches=0.2),
    ]
    ob = common.assemble(ID, [cap()] + propeller(), materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "tophat", "tophat", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
