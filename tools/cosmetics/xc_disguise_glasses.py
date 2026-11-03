"""xc_disguise_glasses: the novelty disguise, after the owner's reference photo:
thick black frames with fur eyebrows on top, a long nose and a short brush of
a mustache right under it.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_disguise_glasses.py [-- --preview DIR]

Built in Godot axes in the sunglasses' mesh space (up is -x, the face looks
along +y, z is across, +z the character's right) and converted for export. The
rims sit round the eyes and the brows on their top bars; the arms and mustache ride
just off the head's measured radius, and the nose covers the real one (its tip
is at x 0.05 to 0.075, y 0.087, from the table's face column).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_disguise_glasses"
FRAME, HAIR, NOSE, NOSTRIL = range(4)
EYE_X, EYE_Z = 0.004, 0.098  # the sunglasses' lens centres, as the eyepatch's EYE
FRONT = 0.056  # the frames' plane, in front of the eyes and the nose's bridge
TILT = math.radians(12)
RIM = (0.075, 0.059)  # half-width across, half-height: oversized, nearly meeting over the nose
# The rims' centre height: the eyes sit about 0.02 above the sunglasses' lens
# centre in the game's renders.
RIM_X = EYE_X - 0.02
# The nose, lofted from under the frames' bridge to its base: (x, centre y, half
# depth, half width). It narrows at the bridge, swells to a round tip and flares
# into nostril wings; it covers the real nose (tip at x 0.05 to 0.075, y 0.087).
NOSE_RINGS = [
    (-0.026, 0.072, 0.010, 0.014),
    (-0.004, 0.080, 0.015, 0.017),
    (0.020, 0.090, 0.021, 0.021),
    (0.045, 0.102, 0.029, 0.026),
    (0.068, 0.111, 0.035, 0.031),
    (0.084, 0.112, 0.035, 0.041),
    (0.098, 0.106, 0.029, 0.044),
    (0.107, 0.099, 0.020, 0.037),
]


def g(v):
    return common.to_blender(*v)


def rims():
    """A rounded rectangle round each eye, turned out a little with the face, and
    a bridge over the nose."""
    parts = []
    for side in (1, -1):
        normal = Vector((0, math.cos(TILT), side * math.sin(TILT)))
        across = Vector((0, -side * math.sin(TILT), math.cos(TILT)))
        c = Vector((RIM_X, FRONT, side * EYE_Z))
        pts = []
        for k in range(14):
            a = 2 * math.pi * k / 14
            # A squircle: nearly square, like the reference's frames.
            ca, sa = math.cos(a), math.sin(a)
            u = math.copysign(abs(ca) ** 0.35, ca) * RIM[0]
            v = math.copysign(abs(sa) ** 0.35, sa) * RIM[1]
            pts.append(g(c + across * u + Vector((-v, 0, 0))))
        parts.append(common.tube("rim", pts, 0.012, 6, FRAME, closed=True, up=tuple(g(normal))))
    bridge = [g(Vector((RIM_X - 0.016 - 0.006 * math.cos(z / 0.03 * math.pi / 2), FRONT + 0.006, z))) for z in (-0.03, -0.015, 0.0, 0.015, 0.03)]
    parts.append(common.tube("bridge", bridge, 0.008, 6, FRAME))
    return parts


def brows():
    """A block of fur on each rim's top bar, ragged along its length and a
    little taller at the outer end."""
    parts = []
    for side in (1, -1):
        normal = Vector((0, math.cos(TILT), side * math.sin(TILT)))
        across = Vector((0, -side * math.sin(TILT), math.cos(TILT)))
        c = Vector((RIM_X, FRONT, side * EYE_Z))
        path, radii = [], []
        for i in range(9):
            f = i / 8
            u = side * RIM[0] * (-0.85 + 1.8 * f)
            path.append(g(c + across * u + Vector((-(RIM[1] + 0.014 + 0.006 * f), 0, 0)) + normal * 0.004))
            radii.append((0.016 + 0.007 * f) * (1 + 0.22 * math.sin(i * 2.7)))
        parts.append(common.tube("brow", path, radii, 8, HAIR, flat=0.55, up=tuple(g(normal))))
    return parts


def arms():
    """From each rim's outer edge back along the head above the ear, then down
    behind it."""
    parts = []
    for side in (1, -1):
        path = [g(Vector((RIM_X - 0.01, FRONT - 0.012, side * (EYE_Z + RIM[0] + 0.002))))]
        for i in range(1, 9):
            f = i / 8
            t = side * (math.radians(38) + math.radians(68) * f)
            x = RIM_X - 0.012 + 0.07 * max(0.0, f - 0.75) / 0.25
            path.append(g(common.around_sunglasses_head(x, t, 0.008)))
        parts.append(common.tube("arm", path, 0.006, 5, FRAME, flat=1.6))
    return parts


def nose():
    """One lofted shape; rings run down the nose, each from the front toward +z,
    so the faces point out."""
    n = 16
    rings = [[g(Vector((x, cy + ry * math.cos(2 * math.pi * k / n), rz * math.sin(2 * math.pi * k / n)))) for k in range(n)]
             for x, cy, ry, rz in NOSE_RINGS]
    x, cy, ry, _ = NOSE_RINGS[-1]
    parts = [common.rings_mesh("nose", rings, [NOSE] * (len(rings) - 1), cap=g(Vector((x + 0.006, cy - ry * 0.3, 0.0))))]
    up = (g(Vector((1, 0, 0))), g(Vector((0, 1, 0))), g(Vector((0, 0, 1))))
    for side in (1, -1):
        parts.append(common.ellipsoid("nostril", tuple(g(Vector((0.108, 0.104, side * 0.019)))), (0.006, 0.011, 0.009), 8, 4, NOSTRIL, basis=up))
    return parts


def mustache():
    """A short, wide brush tucked right under the nose's base (which ends at x
    0.113), about twice the nose's width, blunt at the ends; ragged along its length."""
    path, radii = [], []
    for i in range(11):
        f = i / 10 * 2 - 1
        t = 0.38 * f
        x = 0.128 + 0.008 * f * f
        path.append(g(common.around_sunglasses_head(x, t, 0.024)))
        radii.append((0.025 - 0.006 * f * f) * (1 + 0.22 * math.sin(i * 2.9)))
    return [common.tube("mustache", path, radii, 9, HAIR, flat=0.7, up=tuple(g(Vector((0, 1, 0)))))]


def main():
    opts = common.args()
    common.reset()
    parts = rims() + brows() + arms() + nose() + mustache()
    materials = [
        common.worn("frame", "151413", "3e3a35", grime=0.25, grain=0.05, edge_hex="56524b", edge=0.6),
        common.worn("hair", "1c1814", "40382f", grime=0.3, grain=0.25, pattern=("0d0b0a", 420.0, "WAVE")),
        common.worn("nose", "c48a7c", "6e5048", grime=0.4, grime_scale=4.0, grain=0.06, edge_hex="d9a89a", edge=0.4),
        common.worn("nostril", "3a2420", "1a1210", grime=0.2, grain=0.02),
    ]
    ob = common.assemble(ID, parts, materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID, ao_floor=0.55, ao_distance=0.05))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "sunglasses", "sunglasses", common.UP_IN_SUNGLASSES, common.FACE_IN_SUNGLASSES)


main()
