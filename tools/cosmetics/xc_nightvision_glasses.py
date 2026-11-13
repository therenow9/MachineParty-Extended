"""xc_nightvision_glasses: trifocal night-vision goggles after the owner's
Splinter Cell pictures: three tubes in a flat triangle, two over the eyes and
one between them a little higher, their lenses lit green, in a dark housing
over the eyes, held by a webbing strap round the back of the head.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_nightvision_glasses.py [-- --preview DIR]
  ... -- --out DIR --id <id>   # a review candidate

Built in Godot axes in the sunglasses' mesh space (up is -x, the face looks
along +y, z is across, +z the character's right) and converted for export.
The housing's outline is drawn flat (u across, v up) round the three tubes,
its front on a shallow curve across the face and its back edge just off the
head's measured surface. Nothing in the game glows, so the lenses are painted
lit: a near-white core in bright green, darkening to the rim (the owner).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_nightvision_glasses"
HOUSING, TUBE, LENS, STRAP = range(4)
EYE_V = 0.016  # the eyes' centre, about 0.02 above the sunglasses' lens centre
# Each tube's centre (u, v): two over the eyes and the third between them
# above, as on the pictures' goggles, everything under v 0.09: the traffic
# cone's base comes down to x -0.093 in front of the face (its xc_recon guide).
TUBES = [(-0.09, EYE_V - 0.022), (0.09, EYE_V - 0.022), (0.0, EYE_V + 0.018)]
TUBE_R = 0.04
SIDES = 16
# Along each tube from the housing's front, (forward, radius): the barrel, a
# knurled focus ring, then a lip round the lens, nearly flush so the bake's
# occlusion doesn't darken it.
PROFILE = [(-0.006, 1.0), (0.014, 1.0), (0.016, 1.1), (0.036, 1.1), (0.038, 1.0), (0.05, 1.0),
           (0.052, 1.07), (0.057, 1.07), (0.058, 0.88), (0.057, 0.88)]
KNURL = (2, 3)  # PROFILE's rings that alternate in and out
LENS_R = TUBE_R * 0.88
# The housing's edge round the tubes, (u, v), anticlockwise from the top right,
# with a notch for the nose; rounded and resampled by outline().
OUTLINE = [(0.05, 0.086), (-0.05, 0.086), (-0.062, 0.064), (-0.14, 0.05), (-0.15, -0.006), (-0.12, -0.058),
           (-0.036, -0.058), (-0.022, -0.02), (0.022, -0.02), (0.036, -0.058), (0.12, -0.058), (0.15, -0.006),
           (0.14, 0.05), (0.062, 0.064)]
EDGE = 28
FRONT, CURVE = 0.08, 1.1  # the housing's front at the middle, and its curve back (y = FRONT - CURVE u^2)
CLEAR = 0.026  # the front's least distance off the face
STRAP_X, STRAP_WIDTH = -0.024, 0.036  # level with the housing, over the ears' tops (the owner's pick)


def g(v):
    return common.to_blender(*v)


def face_y(x, z):
    """How far forward the head's surface is at (x, z)."""
    r = 0.25
    for _ in range(3):
        t = math.asin(max(-1.0, min(1.0, z / r)))
        r = common.head_radius(common.HEAD_RADIUS_IN_SUNGLASSES, x, t)
    return common.HEAD_AXIS_Y + math.sqrt(max(0.0, r * r - z * z))


def front_y(u, v):
    return max(FRONT - CURVE * u * u, face_y(-v, u) + CLEAR)


def outline():
    """OUTLINE rounded by two Chaikin passes, resampled to EDGE points evenly
    spaced along it."""
    pts = OUTLINE
    for _ in range(2):
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


def outward(build, rings, center):
    """build(rings), rebuilt with each ring reversed if most of its faces point
    back toward center: the AO bake darkens faces that point in."""
    ob = build(rings)
    if sum((p.normal.dot(p.center - center) > 0) * 2 - 1 for p in ob.data.polygons) >= 0:
        return ob
    bpy.data.objects.remove(ob)
    return build([list(reversed(r)) for r in rings])


def housing():
    """A shell from just off the face to a bevelled front, its front domed a
    little toward the middle (0, mid_v)."""
    mid_v = 0.015
    edge = outline()

    def at(f, back):
        """The outline scaled by f toward the middle, on the front set back by back."""
        pts = []
        for u, v in edge:
            u2, v2 = u * f, mid_v + (v - mid_v) * f
            pts.append(Vector((-v2, front_y(u2, v2) - back, u2)))
        return pts

    back = []
    for u, v in edge:
        y = front_y(u, v)
        back.append(Vector((-v, min(face_y(-v, u) + 0.004, y - 0.014), u)))
    rings = [back, at(1.0, 0.008), at(0.93, 0.0), at(0.5, -0.004)]
    middle = Vector((-mid_v, front_y(0.0, mid_v) + 0.006, 0.0))
    head = Vector(g(Vector((-0.02, common.HEAD_AXIS_Y, 0.0))))
    return outward(lambda rs: common.rings_mesh("housing", [[g(p) for p in r] for r in rs], [HOUSING] * 3, cap=g(middle)),
                   rings, head)


def tube(u, v):
    """One tube straight out of the housing's front, its lens at the end."""
    base = Vector((-v, front_y(u, v), u))
    rings = []
    # Round from +z toward +x, so the barrel's faces point out.
    for k, (fwd, r) in enumerate(PROFILE):
        ring = []
        for i in range(SIDES):
            a = 2 * math.pi * i / SIDES
            rr = TUBE_R * r * (0.95 if k in KNURL and i % 2 else 1.0)
            ring.append(g(base + Vector((rr * math.sin(a), fwd, rr * math.cos(a)))))
        rings.append(ring)
    # Domed, so the smoothed normals of its upper half turn up to the light.
    lens_c = base + Vector((0.0, PROFILE[-1][0] + 0.01, 0.0))
    body = common.rings_mesh("tube", rings, [TUBE] * (len(rings) - 1))
    # Fanned this way round the lens faces forward, along +y.
    n = SIDES
    glass = common.mesh_object("lens", [rings[-1][i] for i in range(n)] + [g(lens_c)],
                               [(i, (i + 1) % n, n) for i in range(n)], [LENS] * n)
    return [body, glass], lens_c


def strap():
    """A flat webbing band from inside the housing's sides round the back of
    the head, as the scuba mask's; its faces point out of the band."""
    rings = []
    start = math.radians(30)
    for i in range(29):
        t = start + (2 * math.pi - 2 * start) * i / 28
        w = STRAP_WIDTH / 2
        r = max(common.head_radius(common.HEAD_RADIUS_IN_SUNGLASSES, STRAP_X + d, t) for d in (-w, 0.0, w)) + 0.005
        rings.append([g(Vector((STRAP_X + l, common.HEAD_AXIS_Y + (r + o) * math.cos(t), (r + o) * math.sin(t))))
                      for o, l in ((0, w), (0.005, w), (0.005, -w), (0, -w))])
    return common.rings_mesh("strap", rings, [STRAP] * 28)


def buckles():
    """An adjuster block on the strap behind each temple."""
    out = []
    for side in (1, -1):
        t = side * math.radians(62)
        p = common.around_sunglasses_head(STRAP_X, t, 0.013)
        along = Vector((0.0, -math.sin(t), math.cos(t))) * side
        radial = Vector((0.0, math.cos(t), math.sin(t)))
        out.append(common.ellipsoid("buckle", g(p), (0.024, 0.02, 0.007), 8, 4, TUBE,
                                    basis=(g(along), g(Vector((1.0, 0.0, 0.0))), g(radial))))
    return out


def lens_material(centres):
    """Painted lit: a near-white core, bright green, darker toward the rim,
    and a small glint above and toward the nose. Each point is coloured by its
    nearest lens."""
    mat, nodes, links, color = common.diffuse_material("lens")
    coord = nodes.new("ShaderNodeTexCoord")

    def op(kind, a, b=None):
        m = nodes.new("ShaderNodeMath")
        m.operation = kind
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, float):
                m.inputs[i].default_value = v
            else:
                links.new(v, m.inputs[i])
        return m.outputs[0]

    def nearest(points):
        best = None
        for p in points:
            d = nodes.new("ShaderNodeVectorMath")
            d.operation = "DISTANCE"
            links.new(coord.outputs["Object"], d.inputs[0])
            d.inputs[1].default_value = g(p)
            best = d.outputs["Value"] if best is None else op("MINIMUM", best, d.outputs["Value"])
        return op("DIVIDE", best, LENS_R)

    def band(v, lo, hi):
        r = nodes.new("ShaderNodeMapRange")
        r.inputs["From Min"].default_value = lo
        r.inputs["From Max"].default_value = hi
        links.new(v, r.inputs["Value"])
        return r.outputs["Result"]

    def paint(src, fac, hex_rgb):
        m = nodes.new("ShaderNodeMix")
        m.data_type = "RGBA"
        links.new(fac, m.inputs["Factor"])
        if isinstance(src, tuple):
            m.inputs["A"].default_value = src
        else:
            links.new(src, m.inputs["A"])
        m.inputs["B"].default_value = common.srgb(hex_rgb)
        return m.outputs["Result"]

    # Saturated nearly to the rim: lit from above, a forward-facing pale lens
    # reads grey in the lobby, where green holds.
    f = nearest(centres)
    out = common.srgb("127a1a")
    out = paint(out, band(f, 1.0, 0.88), "2ee830")
    out = paint(out, band(f, 0.7, 0.45), "5cff3e")
    out = paint(out, band(f, 0.26, 0.14), "c4ff9c")
    glint = nearest([c + Vector((-0.4 * LENS_R, 0.0, 0.0)) + Vector((0.0, 0.0, -0.35 * LENS_R)) * (1 if c.z > 0.01 else -1 if c.z < -0.01 else 0)
                     for c in centres])
    out = paint(out, band(glint, 0.16, 0.1), "ffffff")
    links.new(out, color)
    return mat


def main():
    opts = common.args()
    item_id = opts.get("id", ID)
    common.reset()
    parts, centres = [housing()], []
    for u, v in TUBES:
        made, c = tube(u, v)
        parts += made
        centres.append(c)
    parts += [strap()] + buckles()
    materials = [
        # Gunmetal over black, worn pale at the edges.
        common.worn("housing", "2c3033", "111315", grime=0.35, grain=0.08, edge_hex="70777c", edge=0.6, scratches=0.25),
        common.worn("tube", "1e2022", "0c0d0e", grime=0.3, grain=0.08, edge_hex="62686d", edge=0.7, scratches=0.2),
        lens_material(centres),
        common.worn("strap", "1f1f1e", "0e0e0d", grime=0.25, grain=0.1, pattern=("33332f", 90.0, "WAVE")),
    ]
    ob = common.assemble(item_id, parts, materials)
    n = common.check_budget(ob, item_id)
    print(item_id, n, "triangles")
    print("wrote", common.bake(ob, item_id, ao_floor=0.6, ao_distance=0.05))
    print("wrote", common.export(ob, item_id))
    if opts["preview"]:
        common.preview(ob, item_id, opts["preview"], "sunglasses", "sunglasses", common.UP_IN_SUNGLASSES, common.FACE_IN_SUNGLASSES)


main()
