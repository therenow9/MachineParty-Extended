"""xc_cyclops_glasses: a visor, one red lens slot in a white frame, on straight arms.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_cyclops_glasses.py [-- --preview DIR]

Built in Godot axes in the sunglasses' mesh space (up is -x, the face looks
along +y, z is across, +z the character's right) and converted for export. The
visor runs level across the eyes on one smooth curve: an ellipse from the
nose's clearance to the cheeks', so it curves over the nose rather than peaking
at it. From each end a straight arm runs back above the ear and hooks behind it,
pushed out only where the head would cut it.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_cyclops_glasses"
FRAME, LENS = range(2)
EYE_LINE = -0.028  # a little above the eyes' centre (about -0.016)
HALF_HEIGHT = 0.044
SPAN = math.radians(64)  # the visor's ends, either side of the face
STEPS = 24
LENS_SPAN = math.radians(52)
GAP = 0.004
# Round the visor's section, closed: (fraction of the half height, out from the outline).
SECTION = [(-1.0, 0.0), (-1.0, 0.014), (-0.6, 0.016), (-0.48, 0.008), (0.48, 0.008), (0.6, 0.016),
           (1.0, 0.014), (1.0, 0.0)]
LENS_STRIP = 3  # the strip from SECTION[3] to SECTION[4]
ARM_X = -0.045  # above the ears, whose tops are near x -0.035
# Behind the ear, then down it: (x, y, |z|).
EAR = [(ARM_X, -0.36, 0.218), (-0.02, -0.385, 0.212), (0.012, -0.392, 0.2)]


def half_height(t):
    """Full height across the eyes, narrowing toward the ends where the arms start."""
    k = min(1.0, max(0.0, (abs(t) - math.radians(46)) / (SPAN - math.radians(46))))
    return HALF_HEIGHT * (1 - 0.4 * k * k * (3 - 2 * k))


def widest(t):
    h = half_height(t)
    return max(common.head_radius(common.HEAD_RADIUS_IN_SUNGLASSES, EYE_LINE + h * f, t) for f in (-1.0, -0.5, 0.0, 0.5, 1.0))


def outline(t):
    front = max(widest(u) for u in (-0.3, -0.15, 0.0, 0.15, 0.3)) + GAP
    side = max(widest(math.copysign(SPAN, t)), widest(math.copysign(math.pi / 2, t))) + GAP
    c, s = math.cos(t), math.sin(t)
    return max(widest(t) + GAP, 1 / math.sqrt((c / front) ** 2 + (s / side) ** 2))


def point(t, r, x):
    return Vector((x, common.HEAD_AXIS_Y + r * math.cos(t), r * math.sin(t)))


def visor():
    # From +SPAN down to -SPAN, so with SECTION's order the faces point out.
    angles = [SPAN - 2 * SPAN * j / STEPS for j in range(STEPS + 1)]
    sections = []
    for t in angles:
        r, h = outline(t), half_height(t)
        sections.append([common.to_blender(*point(t, r + out, EYE_LINE + u * h)) for u, out in SECTION])
    ob = common.rings_mesh("visor", sections)
    n = len(SECTION)
    mats = []
    for p in ob.data.polygons:
        j, strip = divmod(p.index, n)
        t = (angles[j] + angles[j + 1]) / 2
        mats.append(LENS if strip == LENS_STRIP and abs(t) < LENS_SPAN else FRAME)
    ob.data.polygons.foreach_set("material_index", mats)
    return ob


def arm(side):
    """A straight line from the visor's end to behind the ear, sampled so any
    point the head would cut is pushed just outside it, then the hook."""
    t0 = side * SPAN
    start = point(t0, outline(t0) + 0.008, ARM_X)
    end = Vector((EAR[0][0], EAR[0][1], side * EAR[0][2]))
    path = []
    for i in range(7):
        p = start.lerp(end, i / 6)
        t = math.atan2(p.z, p.y - common.HEAD_AXIS_Y)
        r = math.hypot(p.y - common.HEAD_AXIS_Y, p.z)
        r = max(r, common.head_radius(common.HEAD_RADIUS_IN_SUNGLASSES, p.x, t) + 0.008)
        path.append(point(t, r, p.x))
    path += [Vector((x, y, side * z)) for x, y, z in EAR[1:]]
    return common.tube("arm", [common.to_blender(*p) for p in path], 0.008, 6, FRAME, flat=2.1,
                       up=common.to_blender(-1.0, 0.0, 0.0))


def main():
    opts = common.args()
    common.reset()
    materials = [
        common.worn("frame", "d6d2c6", "7a7264", grime=0.4, grime_scale=6.0, grain=0.06, edge_hex="9c968a", edge=0.5),
        common.worn("lens", "c42a20", "5a1410", grime=0.2, grime_scale=3.0, grain=0.04),
    ]
    ob = common.assemble(ID, [visor(), arm(1), arm(-1)], materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID, ao_floor=0.55, ao_distance=0.05))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "sunglasses", "sunglasses", common.UP_IN_SUNGLASSES, common.FACE_IN_SUNGLASSES)


main()
