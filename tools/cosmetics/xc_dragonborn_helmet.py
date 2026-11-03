"""xc_dragonborn_helmet: a horned iron helmet after the owner's photo of the
Dragonborn helmet from Skyrim: a dark scuffed iron cap with a riveted crest
band front to back and a riveted brow band round it, two angular eye openings
either side of the nose guard, a face plate over the nose and cheeks to
the jaw, and two ridged bone horns curling out and down from the temples.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_dragonborn_helmet.py [-- --preview DIR]

Built in a frame on the head (f toward the face, s to the side, +s the
character's left, u up the head; the head's up leans forward in the top hat's
space), then placed in the top hat's mesh space. The shell is an egg over the
skull that runs straight down below its equator, measured against xc_recon's
fit guide (the skull spans about f -0.25..0.26, s -0.23..0.23 at the ears, and
peaks at u 0.32; the brow ridge is near u 0.04..0.10, the mouth -0.16, the
chin -0.27). The eyes are near u 0.0: a gauge of coloured bars at known u,
worn in game, put them there. The eye openings are real holes, so the eyes
show through.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_dragonborn_helmet"
IRON, BAND, HORN, RIVET = range(4)
AX = common.HEAD_AXIS_X_IN_TOPHAT
U0 = 0.02  # the shell's equator, up the head from the frame's origin
A, B, C = 0.305, 0.27, 0.32
WALL = 0.22  # how far the straight sides run below the equator
CLEAR = 0.014  # the least gap to the head's measured radius
# One side's column angles from the face; the eye openings run between
# EYE_IN and EYE_OUT, which must be columns.
HALF = [0, 6, 12, 19, 26, 34, 42, 52, 64, 78, 95, 112, 130, 148, 165]
EYE_IN, EYE_OUT = 12, 42
# The openings' top and bottom along the meridian (m 0 is the top, 0.6 the
# equator, 1 the lowest edge): level, from u 0.075 to -0.035 before recess()
# (the dip lowers the bottom about 0.01), so the eyes sit a little below their
# middle.
M_BROW, M_EYE_BOTTOM = 0.534, 0.6996
BAND_W = 0.022  # half the bands' width
# The brow band's centre line: BAND_W and a small gap above the openings'
# top. Centred on their edge, it hangs into them and hides the eyes.
M_BAND = 0.6 * math.acos((C * math.cos(math.pi / 2 * M_BROW / 0.6) + BAND_W + 0.003) / C) / (math.pi / 2)
# How far the shell dips in round the openings: the eyes are deep-set, and a
# slit standing well off them lines up only from straight on. clear() still
# keeps it off the head.
EYE_INSET = 0.045

up = Vector(common.to_blender(*common.UP_IN_TOPHAT)).normalized()
face = Vector(common.to_blender(*common.FACE_IN_TOPHAT))
face = (face - up * face.dot(up)).normalized()
side = up.cross(face)
lo, size = common.HEAD_IN_TOPHAT
origin = Vector(common.to_blender(*[a + b / 2 for a, b in zip(lo, size)]))
middle = origin + up * U0


def at(f, s, du):
    return origin + face * f + side * s + up * (U0 + du)


def meridian(phi, m):
    """The shell at angle phi and m from the top (0) to the lowest edge (1):
    the dome to the equator over m 0..0.6, then the sides, flaring a little,
    most at the back."""
    if m <= 0.6:
        th = math.pi / 2 * m / 0.6
        du, k = C * math.cos(th), math.sin(th)
    else:
        du = -WALL * (m - 0.6) / 0.4
        # The neck guard flares out further than the cheek guards.
        back = min(1.0, max(0.0, (abs(math.remainder(phi, 2 * math.pi)) - math.radians(100)) / math.radians(60)))
        k = 1 + (0.06 + 0.12 * back) * ((m - 0.6) / 0.4) ** 2
    return clear(recess(at(A * k * math.cos(phi), B * k * math.sin(phi), du), phi, m))


def window(v, a, b, c, d):
    """0 below a and above d, 1 from b to c, smooth in between."""
    if v <= a or v >= d:
        return 0.0
    x = min(1.0, (v - a) / (b - a), (d - v) / (d - c))
    return x * x * (3 - 2 * x)


def recess(p, phi, m):
    """p moved EYE_INSET in toward the top hat's axis round the eye openings,
    fading out over the nose guard, the temples and the cheeks. It starts at
    the openings' top, so the step lies inside them: a step above them faces
    down, away from the cameras, and is culled."""
    a = abs(math.degrees(math.remainder(phi, 2 * math.pi)))
    w = window(a, 4, EYE_IN, EYE_OUT + 2, EYE_OUT + 12) * window(m, M_BROW, (M_BROW + M_EYE_BOTTOM) / 2, M_EYE_BOTTOM + 0.01, M_EYE_BOTTOM + 0.06)
    if w == 0.0:
        return p
    x, y, h = p
    r = math.hypot(x - AX, y)
    k = (r - w * EYE_INSET) / r
    return Vector((AX + (x - AX) * k, y * k, h))


def clear(p):
    """p pushed out from the top hat's axis until it clears the head at its height."""
    x, y, h = p
    if h > 0.0:
        return p
    t = math.atan2(-y, x - AX)
    r = math.hypot(x - AX, y)
    hx, hy, _ = common.around_tophat_head(h, t, CLEAR)
    need = math.hypot(hx - AX, hy)
    if r >= need:
        return p
    k = need / r
    return Vector((AX + (x - AX) * k, y * k, h))


def outward(p, out):
    """p moved out from the frame's up axis, level with itself."""
    n = p - (middle + up * (p - middle).dot(up))
    return p + n.normalized() * out


def edge(phi):
    """Where the shell stops: the face plate comes down over the nose to about
    its tip (m 0.8, u -0.09), angles back along the cheeks to the jaw, leaving
    the mouth and chin bare, and the neck guard runs round the back."""
    a = abs(math.remainder(phi, 2 * math.pi))
    x = min(1.0, a / math.radians(70))
    return 0.80 + 0.17 * x * x * (3 - 2 * x) - 0.04 * max(0.0, (a - 1.9) / 1.24)


def rows(phi):
    """Each column's m from its edge up to near the top: the face plate, the
    eye band (two rows) from its bottom to M_BROW, then the cap."""
    e, b = edge(phi), M_EYE_BOTTOM
    return [b + (e - b) * j / 4 for j in (4, 3, 2, 1)] + [b, (b + M_BROW) / 2, M_BROW] + \
        [M_BROW * k / 6 for k in (5, 4, 3, 2, 1)]


def columns():
    return [math.radians(a) for a in [-a for a in reversed(HALF[1:])] + HALF + [180]]


def in_eye(phi_a, phi_b):
    a, b = math.degrees(phi_a), math.degrees(phi_b)
    return a * b > 0 and EYE_IN <= min(abs(a), abs(b)) and max(abs(a), abs(b)) <= EYE_OUT


def shell(phis):
    # Toward the character's left as i grows and from the edge up, so the faces
    # point out; the eye band's cells between EYE_IN and EYE_OUT are left open.
    n = len(phis)
    table = [rows(p) for p in phis]
    nrows = len(table[0])
    verts = [tuple(meridian(phis[i], table[i][k])) for k in range(nrows) for i in range(n)]
    faces = []
    for k in range(nrows - 1):
        for i in range(n):
            j = (i + 1) % n
            if k in (4, 5) and in_eye(phis[i], phis[j]):
                continue
            faces.append((k * n + i, k * n + j, (k + 1) * n + j, (k + 1) * n + i))
    verts.append(tuple(at(0, 0, C)))
    top = len(verts) - 1
    base = (nrows - 1) * n
    faces += [(base + i, base + (i + 1) % n, top) for i in range(n)]
    return common.mesh_object("shell", verts, faces, [IRON] * len(faces))


def ribbon(name, centre, across, mat, closed=False):
    """A flat band along centre, BAND_W either side along across (one vector
    per point), its faces turned away from the head: the AO bake darkens
    faces that point in."""
    n = len(centre)
    verts = [tuple(p + a * BAND_W) for p, a in zip(centre, across)] + [tuple(p - a * BAND_W) for p, a in zip(centre, across)]
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n if closed else n - 1)]
    ob = common.mesh_object(name, verts, faces, [mat] * len(faces))
    if sum((p.normal.dot(p.center - middle) > 0) * 2 - 1 for p in ob.data.polygons) < 0:
        bpy.data.objects.remove(ob)
        ob = common.mesh_object(name, verts, [tuple(reversed(f)) for f in faces], [mat] * len(faces))
    return ob


def bands(phis):
    """The brow band round the head above the openings, and the crest band
    from the nose guard's foot over the top to the nape."""
    brow = [outward(meridian(p, M_BAND), 0.006) for p in phis]
    parts = [ribbon("brow", brow, [up] * len(brow), BAND, closed=True)]
    front = [edge(0.0), (edge(0.0) + M_EYE_BOTTOM) / 2, M_EYE_BOTTOM, (M_EYE_BOTTOM + M_BROW) / 2, M_BROW, 0.4, 0.3, 0.2, 0.1]
    crest = [meridian(0.0, m) for m in front] + [at(0, 0, C)] + [meridian(math.pi, m) for m in [0.1, 0.2, 0.3, 0.4, M_BROW, 0.7, edge(math.pi)]]
    crest = [p + (p - middle).normalized() * 0.006 for p in crest]
    parts.append(ribbon("crest", crest, [side] * len(crest), BAND))
    return parts


def eye_trims():
    """A raised iron lip round each opening."""
    cols = [math.radians(a) for a in HALF if EYE_IN <= a <= EYE_OUT]
    parts = []
    for sgn in (1, -1):
        loop = [(sgn * p, M_BROW + 0.012) for p in cols] + [(sgn * cols[-1], (M_BROW + M_EYE_BOTTOM) / 2)] + \
            [(sgn * p, M_EYE_BOTTOM - 0.004) for p in reversed(cols)] + [(sgn * cols[0], (M_BROW + M_EYE_BOTTOM) / 2)]
        parts.append(common.tube("eye", [tuple(outward(meridian(p, m), 0.004)) for p, m in loop], 0.008, 4, BAND,
                                 closed=True, up=tuple(up)))
    return parts


def rivet(p):
    n = (p - middle).normalized()
    a = n.cross(up if abs(n.dot(up)) < 0.9 else face).normalized()
    return common.ellipsoid("rivet", tuple(p + n * 0.008), (0.011, 0.011, 0.006), 5, 3, RIVET,
                            basis=(tuple(a), tuple(n.cross(a)), tuple(n)))


def rivets():
    """Along the brow band every 20 degrees, clear of the nose guard and the
    eye openings, and down the crest front and back."""
    parts = [rivet(outward(meridian(math.radians(a), M_BAND), 0.006)) for a in range(-170, 190, 20) if abs(a) > EYE_OUT]
    parts += [rivet(meridian(phi, m) + (meridian(phi, m) - middle).normalized() * 0.006)
              for phi in (0.0, math.pi) for m in (0.12, 0.24, 0.36, 0.46)]
    return parts


def horn(sgn):
    """From high on the side of the dome, out and a little up, then curling
    down and forward to a tip beside the eyes, tapering, ridged: a groove
    between each pair of points."""
    base = meridian(sgn * math.radians(95), 0.3)
    s = side * sgn
    k = 1.25
    path = [base - s * 0.01, base + (s * 0.07 + up * 0.06) * k, base + (s * 0.15 + up * 0.07 - face * 0.01) * k,
            base + (s * 0.22 + up * 0.03 - face * 0.02) * k, base + (s * 0.25 - up * 0.05) * k,
            base + (s * 0.24 - up * 0.13 + face * 0.03) * k, base + (s * 0.2 - up * 0.19 + face * 0.08) * k,
            base + (s * 0.15 - up * 0.21 + face * 0.13) * k]
    radii = [0.075, 0.07, 0.062, 0.052, 0.041, 0.03, 0.018, 0.006]
    ridged, ridged_radii = [], []
    for i in range(len(path) - 1):
        ridged += [path[i], path[i].lerp(path[i + 1], 0.5)]
        ridged_radii += [radii[i], (radii[i] + radii[i + 1]) / 2 * 0.86]
    ridged.append(path[-1])
    ridged_radii.append(radii[-1])
    return common.tube("horn", [tuple(p) for p in ridged], ridged_radii, 8, HORN, up=tuple(face))


def main():
    opts = common.args()
    common.reset()
    phis = columns()
    parts = [shell(phis)] + bands(phis) + eye_trims() + rivets() + [horn(1), horn(-1)]
    materials = [
        # Old iron like the game's Maska: rough and mottled, rust-brown grime in
        # every hollow, rubbed bright on the edges and scratched across.
        common.worn("iron", "7a7670", "2e241c", grime=0.85, grime_scale=4.5, grain_scale=160.0, grain=0.45,
                    edge_hex="c4c2bc", edge=1.0, scratches=0.25),
        common.worn("band", "5e5a54", "241c16", grime=0.85, grime_scale=5.0, grain_scale=160.0, grain=0.45,
                    edge_hex="b9b7b1", edge=1.0, scratches=0.3),
        # Bone horn, grooved round and darker in the grooves.
        common.worn("horn", "d6cdb3", "5e5444", grime=0.6, grime_scale=6.0, grain_scale=220.0, grain=0.35, pattern=("9e9479", 40.0, "WAVE")),
        common.worn("rivet", "6e6a64", "241c16", grime=0.6, grain=0.2, edge_hex="c4c2bc", edge=0.8),
    ]
    ob = common.assemble(ID, parts, materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "tophat", "maska_helmet", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
