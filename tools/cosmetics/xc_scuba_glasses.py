"""xc_scuba_glasses: a two-lens dive mask after the owner's photo: blue rims
joined by a bridge, a clear silicone skirt back to the face, a nose pocket, and
a wide clear strap round the back of the head.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_scuba_glasses.py [-- --preview DIR]
  ... -- --out DIR --id <id> [--lens open|painted] [--strap yes|no]   # a review candidate

Built in Godot axes in the sunglasses' mesh space (up is -x, the face looks
along +y, z is across, +z the character's right) and converted for export. The
rims lie on a front that curves back toward the temples. The game draws every
item with an opaque material, so an open lens is a hole that shows the eyes,
and a painted one is dark glass with a sheen. The skirt runs from each rim back
to just off the head's measured surface; the pocket covers the nose (its tip
is at x 0.05 to 0.075, y 0.087).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_scuba_glasses"
FRAME, GLASS, SKIRT, STRAP = range(4)
EYE_X = -0.016  # the eyes' centre, about 0.02 above the sunglasses' lens centre
LENS_Z = 0.098  # each lens's centre across
FRONT, CURVE = 0.075, 0.9  # the rims' front at the middle, and how fast it curves back (y = FRONT - CURVE z^2)
# A lens's edge, (toward the temple, up) from its centre, before smoothing:
# squared off, with the inner bottom corner cut away for the nose.
OUTLINE = [(0.076, 0.064), (-0.07, 0.064), (-0.072, 0.0), (-0.04, -0.062), (0.076, -0.062)]
EDGE = 20
RIM = 0.015
STRAP_WIDTH = 0.045


def g(v):
    return common.to_blender(*v)


def outline():
    """OUTLINE rounded by one Chaikin pass, which keeps it squared, resampled to
    EDGE points evenly spaced along it."""
    pts = OUTLINE
    for _ in range(1):
        pts = [p for a, b in zip(pts, pts[1:] + pts[:1])
               for p in ((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]),
                         (0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))]
    seg = [math.dist(a, b) for a, b in zip(pts, pts[1:] + pts[:1])]
    total, out, i, walked = sum(seg), [], 0, 0.0
    for k in range(EDGE):
        want = total * k / EDGE
        while walked + seg[i] < want:
            walked += seg[i]
            i += 1
        f = (want - walked) / seg[i]
        a, b = pts[i], pts[(i + 1) % len(pts)]
        out.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
    return out


def on_front(side, u, v, back=0.0, scale=1.0, scale_v=None):
    """The lens point (u toward the temple, v up) on the curved front, set back by
    back, scaled from the lens's centre (scale_v up and down, if given)."""
    z = side * (LENS_Z + u * scale)
    return Vector((EYE_X - v * (scale if scale_v is None else scale_v), FRONT - CURVE * z * z - back, z))


def face_y(x, z):
    """How far forward the head's surface is at (x, z)."""
    r = 0.25
    for _ in range(3):
        t = math.asin(max(-1.0, min(1.0, z / r)))
        r = common.head_radius(common.HEAD_RADIUS_IN_SUNGLASSES, x, t)
    return common.HEAD_AXIS_Y + math.sqrt(max(0.0, r * r - z * z))


def outward(build, rings, center):
    """build(rings), rebuilt with each ring reversed if most of its faces point
    back toward center: the AO bake darkens faces that point in."""
    ob = build(rings)
    if sum((p.normal.dot(p.center - center) > 0) * 2 - 1 for p in ob.data.polygons) >= 0:
        return ob
    bpy.data.objects.remove(ob)
    return build([list(reversed(r)) for r in rings])


def lens(side, painted):
    """One lens: its rim, its skirt back to the face, and painted glass if asked."""
    edge = outline() if side > 0 else [(u, v) for u, v in reversed(outline())]
    rim = [g(on_front(side, u, v, -0.004)) for u, v in edge]
    parts = [common.tube("rim", rim, RIM, 6, FRAME, closed=True, flat=0.7, up=g(Vector((0, 1, 0))))]
    front = [on_front(side, u, v, 0.006, 1.05) for u, v in edge]
    back = []
    for u, v in edge:
        p = on_front(side, u, v, 0.0, 1.28, 1.1)
        back.append(Vector((p.x, min(face_y(p.x, p.z) + 0.004, p.y - 0.012), p.z)))
    parts.append(outward(lambda pts: common.rings_mesh("skirt", pts, [SKIRT, SKIRT]),
                         [[g(p) for p in front], [g(p) for p in back]], Vector(g(on_front(side, 0.0, 0.0)))))
    if painted:
        glass = [g(on_front(side, u, v, 0.002, 0.95)) for u, v in edge]
        parts.append(common.rings_mesh("glass", [glass], [GLASS], cap=g(on_front(side, 0.0, 0.0, 0.002))))
    return parts


def bridge():
    """The frame between the lenses over the nose, with a round boss on it."""
    top = EYE_X - 0.03
    path = [g(Vector((top, FRONT + 0.004 - CURVE * z * z, z))) for z in (-0.04, -0.014, 0.014, 0.04)]
    return [common.tube("bridge", path, 0.026, 6, FRAME, flat=0.55, up=g(Vector((0, 1, 0)))),
            common.ellipsoid("boss", g(Vector((top, FRONT + 0.02, 0.0))), (0.016, 0.016, 0.008), 10, 4, FRAME,
                             basis=(g(Vector((1, 0, 0))), g(Vector((0, 0, 1))), g(Vector((0, 1, 0)))))]


def pocket():
    """The skirt's nose pocket, under the bridge."""
    return common.ellipsoid("pocket", g(Vector((0.045, 0.07, 0.0))), (0.06, 0.03, 0.055), 12, 6, SKIRT,
                            basis=(g(Vector((1, 0, 0))), g(Vector((0, 0, 1))), g(Vector((0, 1, 0)))))


def strap():
    """A flat band from behind each side of the skirt round the back of the head.
    Its section runs so the faces point out of the band: the AO bake darkens faces
    that point in."""
    rings = []
    start = math.radians(42)
    for i in range(29):
        t = start + (2 * math.pi - 2 * start) * i / 28
        w = STRAP_WIDTH / 2
        r = max(common.head_radius(common.HEAD_RADIUS_IN_SUNGLASSES, EYE_X + d, t) for d in (-w, 0.0, w)) + 0.005
        rings.append([g(Vector((EYE_X + l, common.HEAD_AXIS_Y + (r + o) * math.cos(t), (r + o) * math.sin(t))))
                      for o, l in ((0, w), (0.006, w), (0.006, -w), (0, -w))])
    return common.rings_mesh("strap", rings, [STRAP] * 28)


def glass_material():
    """Dark glass with a diagonal sheen painted in, since nothing reflects."""
    mat, nodes, links, color = common.diffuse_material("glass")
    coord = nodes.new("ShaderNodeTexCoord")
    sheen = nodes.new("ShaderNodeTexGradient")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Rotation"].default_value = (0.0, 0.0, math.radians(35))
    mapping.inputs["Scale"].default_value = (14.0, 14.0, 14.0)
    links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], sheen.inputs["Vector"])
    wave = nodes.new("ShaderNodeMath")
    wave.operation = "PINGPONG"
    wave.inputs[1].default_value = 0.5
    links.new(sheen.outputs["Fac"], wave.inputs[0])
    band = nodes.new("ShaderNodeMapRange")
    band.inputs["From Min"].default_value = 0.38
    band.inputs["From Max"].default_value = 0.5
    links.new(wave.outputs[0], band.inputs["Value"])
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    links.new(band.outputs["Result"], mix.inputs["Factor"])
    mix.inputs["A"].default_value = common.srgb("1a262c")
    mix.inputs["B"].default_value = common.srgb("7a929c")
    links.new(mix.outputs["Result"], color)
    return mat


def main():
    opts = common.args()
    lens_kind, strap_kind = opts.get("lens", "open"), opts.get("strap", "yes")
    if lens_kind not in ("open", "painted") or strap_kind not in ("yes", "no"):
        raise SystemExit("--lens open|painted, --strap yes|no")
    item_id = opts.get("id", ID)
    common.reset()
    parts = lens(1, lens_kind == "painted") + lens(-1, lens_kind == "painted") + bridge() + [pocket()]
    if strap_kind == "yes":
        parts.append(strap())
    materials = [
        # Blue moulded frame (owner, round 3).
        common.worn("frame", "1f4f9c", "15243a", grime=0.25, grain=0.06, edge_hex="5a8ad0", edge=0.6, scratches=0.2),
        glass_material(),
        # Clear silicone, which can only be painted (owner, round 3): pale blue-white
        # with bright glassy streaks where light would catch it. The strap is the same (round 4).
        common.worn("skirt", "c3d3dc", "8597a3", grime=0.25, grime_scale=6.0, grain=0.04, edge_hex="f2fbff", edge=0.9,
                    pattern=("e9f4fa", 9.0, "WAVE")),
        common.worn("strap", "c3d3dc", "8597a3", grime=0.2, grain=0.04, edge_hex="f2fbff", edge=0.9,
                    pattern=("e9f4fa", 9.0, "WAVE")),
    ]
    ob = common.assemble(item_id, parts, materials)
    n = common.check_budget(ob, item_id)
    print(item_id, n, "triangles")
    print("wrote", common.bake(ob, item_id, ao_floor=0.6, ao_distance=0.05))
    print("wrote", common.export(ob, item_id))
    if opts["preview"]:
        common.preview(ob, item_id, opts["preview"], "sunglasses", "sunglasses", common.UP_IN_SUNGLASSES, common.FACE_IN_SUNGLASSES)


main()
