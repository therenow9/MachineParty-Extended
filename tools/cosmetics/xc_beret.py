"""xc_beret: an air force blue wool beret on a black leather band, the badge
over the left eye and the crown pulled down over the right, after the owner's
photo (in the owner's pick of colour).

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_beret.py [-- --preview DIR]

Blender axes in the top hat's mesh space: z up the hat, +x the face, -y the
character's right. The band is level all round just above the ears (the
table's ears run from about y -0.36 to -0.20), standing off the head's
measured radius. The crown is a wide disc tipped down to the right and a
little to the face with the head, joined to the band by puffed wool. The badge
is the owner's pick from the photo: a ring round a winged arm holding a sword.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_beret"
SEGMENTS = 32
WOOL, LEATHER, SILVER = range(3)
AX = common.HEAD_AXIS_X_IN_TOPHAT
OUT = 0.012
HEM, BAND = -0.185, 0.024
# The crown's disc: centre, radius, how far it drops per unit toward the right
# and toward the face, how far its middle puffs up off that plane, and how far
# its right half bends down further, draped over the ear.
DISC = Vector((AX - 0.02, -0.06, 0.0))
RADIUS = 0.30
DROP_RIGHT, DROP_FACE = 0.38, 0.15
PUFF = 0.085
DROOP = 0.12
BADGE_T = math.radians(-35)  # toward the character's left
BADGE_R = 0.046


def footprint(t):
    """The band's radius: the head's widest just above the ears, smoothed round
    the head so the band is one even curve, plus OUT."""
    def widest(u):
        return max(math.hypot(x - AX, y) for x, y, _ in (common.around_tophat_head(h, u) for h in (HEM + 0.01, -0.14, -0.1)))
    return sum(widest(t + k * 0.1) for k in range(-3, 4)) / 7 + OUT


def band_at(t, h, out=0.0):
    r = footprint(t) + out
    return Vector((AX + r * math.cos(t), -r * math.sin(t), h))


def plane(x, y):
    """The disc's height over (x, y): down to the right and to the face."""
    return DISC.z + DROP_RIGHT * (y - DISC.y) - DROP_FACE * (x - DISC.x)


def normal():
    return Vector((DROP_FACE, -DROP_RIGHT, 1.0)).normalized()


def disc_at(t, q, lift=0.0):
    """The point q of the way out from the disc's centre toward its rim at
    angle t, on the plane, puffed up toward the middle, plus lift."""
    x, y = DISC.x + RADIUS * q * math.cos(t), DISC.y - RADIUS * q * math.sin(t)
    p = Vector((x, y, plane(x, y) - DROOP * max(0.0, q * math.sin(t)) ** 2))
    return p + normal() * (PUFF * math.sqrt(max(0.0, 1 - q * q)) + lift)


def clear(p):
    """p pushed out from the top hat's axis until it clears the head at its height."""
    x, y, h = p
    if h > 0.04:
        return p
    t = math.atan2(-y, x - AX)
    r = math.hypot(x - AX, y)
    if h > 0.0:
        need = common.head_radius(common.HEAD_RADIUS_IN_TOPHAT, 0.0, t) * math.sqrt(max(0.0, 1 - (h / 0.04) ** 2)) + 0.012
    else:
        hx, hy, _ = common.around_tophat_head(h, t, 0.012)
        need = math.hypot(hx - AX, hy)
    if r >= need:
        return p
    k = need / r
    return Vector((AX + (x - AX) * k, y * k, h))


def wall(t, s):
    """The wool between the band's top (s 0) and just under the rim (s 1),
    bulging out in the middle."""
    a = band_at(t, HEM + BAND, 0.004)
    b = disc_at(t, 0.97, -0.014)
    p = a.lerp(b, s)
    out = Vector((p.x - DISC.x, p.y - DISC.y, 0.0)).normalized()
    return clear(p + out * 0.035 * math.sin(math.pi * s))


def beret():
    # Toward the character's left as i grows, from the band up, so the faces point out.
    angles = [-2 * math.pi * i / SEGMENTS for i in range(SEGMENTS)]
    rings, mats = [], []
    for h, out, m in ((HEM, -0.004, LEATHER), (HEM - 0.003, 0.006, LEATHER), (HEM + BAND, 0.006, LEATHER)):
        rings.append([tuple(band_at(t, h, out)) for t in angles])
        mats.append(m)
    for s in (0.0, 0.3, 0.6, 1.0):
        rings.append([tuple(wall(t, s)) for t in angles])
        mats.append(WOOL)
    # The rim rolls over, then the crown rises to the middle.
    for q, lift in ((1.0, -0.004), (0.96, 0.008), (0.82, 0.0), (0.62, 0.0), (0.4, 0.0), (0.2, 0.0)):
        rings.append([tuple(clear(disc_at(t, q, lift))) for t in angles])
        mats.append(WOOL)
    return common.rings_mesh("beret", rings, mats[:-1] + [WOOL], cap=tuple(disc_at(0.0, 0.0)))


def badge():
    """On the wool over the left eye: a ring, a sword pointing up and toward
    the face's middle, and a wing fanning back from the arm that holds it."""
    s, t = 0.42, BADGE_T
    p = wall(t, s)
    a = (wall(t, s + 0.05) - wall(t, s - 0.05)).normalized()
    n = a.cross(wall(t + 0.05, s) - wall(t - 0.05, s)).normalized()
    if n.dot(p - Vector((AX, 0.0, p.z))) < 0:
        n = -n
    b = n.cross(a)
    c = p + n * 0.006

    def on(u, v, lift=0.0):
        return tuple(c + b * (u * BADGE_R) + a * (v * BADGE_R) + n * lift)

    basis = (tuple(b), tuple(a), tuple(n))
    ring = [on(math.cos(2 * math.pi * k / 14), math.sin(2 * math.pi * k / 14)) for k in range(14)]
    parts = [common.tube("ring", ring, 0.0045, 5, SILVER, closed=True, flat=0.6, up=tuple(n))]
    # The sword, from the pommel low on the right to its point up on the left.
    parts.append(common.tube("blade", [on(0.45, -0.55), on(0.05, 0.05), on(-0.5, 0.72)], [0.006, 0.0055, 0.001], 4, SILVER,
                             flat=0.4, up=tuple(n)))
    parts.append(common.tube("guard", [on(0.12, -0.38), on(0.5, -0.12)], 0.0032, 4, SILVER, up=tuple(n)))
    parts.append(common.ellipsoid("fist", on(0.38, -0.36, 0.002), (0.011, 0.009, 0.004), 6, 3, SILVER, basis=basis))
    # The wing: feathers fanning from the arm toward the badge's back edge.
    for k in range(5):
        ang = math.radians(-30 + 28 * k)
        u, v = 0.3 + 0.38 * math.cos(ang), -0.3 + 0.38 * math.sin(ang)
        d = Vector((math.cos(ang), math.sin(ang), 0.0))
        fb = (b * d.x + a * d.y).normalized()
        parts.append(common.ellipsoid("feather", on(u, v, 0.001), (0.0055, 0.014, 0.0025), 6, 3, SILVER,
                                      basis=(tuple(n.cross(fb)), tuple(fb), tuple(n))))
    return parts


def main():
    opts = common.args()
    common.reset()
    parts = [beret()] + badge()
    materials = [
        # Felted wool, darker in the folds and where it is handled.
        common.worn("wool", "1b3478", "0a1640", grime=0.45, grime_scale=4.0, grain_scale=500.0, grain=0.35),
        common.worn("leather", "1c1a19", "0b0a0a", grime=0.25, grain=0.1, edge_hex="5c5650", edge=0.5, scratches=0.08),
        common.worn("silver", "cfcdc3", "5f5e58", grime=0.45, grime_scale=12.0, grain=0.05, edge_hex="f2f1ea", edge=0.6),
    ]
    ob = common.assemble(ID, parts, materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "tophat", "tophat", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
