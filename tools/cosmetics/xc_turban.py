"""xc_turban: a wound cloth turban after the owner's photo, its layers
crossing over the forehead, with a red oval jewel in a gold setting where they
cross and a dark feather rising behind it.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_turban.py [-- --preview DIR]

Blender axes in the top hat's mesh space: z up the hat, +x the face, -y the
character's right. The hem rises to a point at the middle of the forehead,
where a dark under-cloth shows, and comes down over the ears' tops. From it
the cloth stands out WIDTH past the head's measured radius, near-vertical, to
a rounded top. Its layers are shallow rolls laid along contours that rise to
a peak where they cross over the forehead and fall away toward the ears;
behind, they sweep down round a smooth oval of cloth and gather at the nape.
The crease under each roll's edge is painted from a per-vertex weight. The jewel
is painted, since nothing in the game glows.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_turban"
CLOTH, GOLD, JEWEL, PLUME, UNDER = range(5)
AX = common.HEAD_AXIS_X_IN_TOPHAT
K = common.UP_IN_TOPHAT[0] / common.UP_IN_TOPHAT[1]
UPV = Vector((common.UP_IN_TOPHAT[0], 0.0, common.UP_IN_TOPHAT[1])).normalized()
SEGMENTS = 24
OUT = 0.014
TOP, WIDTH = 0.19, 0.05  # the top's height, and how far past the head the cloth is at its widest
# The layers: how many, how far each roll stands out, how far they rise to
# where they cross over the forehead, and the top of the last one. Behind
# BACK_FROM they gather toward the nape, leaving the smooth oval above them.
BACK_FROM, GATHER = math.radians(110), 0.92
BANDS, FOLD, PEAK = 5, 0.012, 0.09
BAND_TOP = TOP - 0.06
JEWEL_U = 0.5  # how far up the front's outline the jewel sits


def hem_level(t):
    """Up to a point at the middle of the forehead, down over the ears' tops, a little lower behind."""
    d = abs(math.remainder(t, 2 * math.pi))
    return -0.135 - 0.2 * min(d / (math.pi / 2), 1.0) ** 0.85 - 0.06 * max(d - math.pi / 2, 0.0) / (math.pi / 2)


def at_level(lv, t, out):
    z = lv - K * 0.1
    for _ in range(4):
        p = common.around_tophat_head(z, t, out)
        z = lv - K * p[0]
    return common.around_tophat_head(z, t, out)


def head_r(z, t):
    hx, hy, _ = common.around_tophat_head(z, t, OUT)
    return math.hypot(hx - AX, hy)


_outlines = {}


def outline(t):
    """The cloth's outline at angle t: (r, z, arc fraction) from the hem to the top,
    a spline through the hem, the full lower roll, the widest point and the crown."""
    if t not in _outlines:
        z0 = at_level(hem_level(t), t, OUT)[2]
        w = head_r(-0.10, t) + WIDTH
        ctrl = [(head_r(z0, t), z0), (head_r(z0 + 0.05, t) + 0.04, z0 + 0.05), (w, -0.04), (w * 0.72, TOP - 0.035), (0.0, TOP)]
        ext = [ctrl[0]] + ctrl + [ctrl[-1]]
        pts = []
        for i in range(1, len(ext) - 2):
            p0, p1, p2, p3 = ext[i - 1:i + 3]
            for k in range(16):
                q = k / 16
                pts.append(tuple(0.5 * (2 * p1[d] + (p2[d] - p0[d]) * q + (2 * p0[d] - 5 * p1[d] + 4 * p2[d] - p3[d]) * q * q
                                        + (3 * p1[d] - p0[d] - 3 * p2[d] + p3[d]) * q ** 3) for d in range(2)))
        pts.append(ctrl[-1])
        out = []
        for r, z in pts:
            z = max(z, out[-1][1] + 1e-5) if out else z
            r = max(r, head_r(z, t)) if z < 0.03 else max(r, 0.0)
            out.append((r, z))
        arc = [0.0]
        for a, b in zip(out, out[1:]):
            arc.append(arc[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
        _outlines[t] = [(r, z, a / arc[-1]) for (r, z), a in zip(out, arc)]
    return _outlines[t]


def along(t, key, value):
    """(r, z) on the outline where its height (key 1) or arc fraction (key 2) is value."""
    pts = outline(t)
    for a, b in zip(pts, pts[1:]):
        if b[key] >= value:
            f = (value - a[key]) / ((b[key] - a[key]) or 1.0)
            return a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f
    return pts[-1][0], pts[-1][1]


def point(u, t, extra=0.0):
    """The cloth's outline u of the way along it from the hem to the top, at angle t."""
    r, z = along(t, 2, u)
    r += extra
    return (AX + r * math.cos(t), -r * math.sin(t), z)


def contour(g, t):
    """The height of a layer g of the way from the hem to the last one, at angle t:
    the hem's point fades out going up, the layers peak over the forehead, and
    behind they close up toward the hem, so all of them meet at the nape."""
    z0 = outline(t)[0][1]
    d = abs(math.remainder(t, 2 * math.pi))
    e = min(max((d - BACK_FROM) / (math.pi - BACK_FROM), 0.0), 1.0)
    gather = GATHER * (e * e * (3 - 2 * e)) ** 0.8
    return z0 + ((BAND_TOP - z0) * g + PEAK * math.sin(math.pi * g) * max(0.0, 1 - d / 1.2)) * (1 - gather)


# Across one layer, from its lower edge up: where each ring sits, how far it
# stands out (of FOLD), and how dark its crease paint is. The first and last
# share a height, so each crease is a shallow step under a roll's edge.
ROLL = [(0.0, 0.75, 0.5), (0.22, 1.0, 0.0), (0.62, 0.5, 0.0), (1.0, 0.0, 0.7)]


def cloth():
    """The cloth: rings along the layers, a smooth crown (and the oval behind)
    above the last, each vertex's crease paint in the 'crease' attribute."""
    # Toward the character's left as i grows, so the faces point out of the head.
    angles = [-2 * math.pi * i / SEGMENTS for i in range(SEGMENTS)]
    rings, weights = [[point(0.0, t) for t in angles]], [0.0] * SEGMENTS
    for b in range(BANDS):
        for frac, out, dark in ROLL:
            ring = []
            for t in angles:
                r, z = along(t, 1, contour((b + frac) / BANDS, t))
                r += FOLD * out
                ring.append((AX + r * math.cos(t), -r * math.sin(t), z))
            rings.append(ring)
            # The last layer's top edge meets the crown, not another roll.
            weights += [0.0 if b == BANDS - 1 and frac == 1.0 else dark] * SEGMENTS
    for k in range(1, 6):
        ring = []
        for t in angles:
            top = contour(1.0, t)
            u0 = next(p[2] for p in outline(t) if p[1] >= top)
            ring.append(point(u0 + (0.975 - u0) * k / 5, t))
        rings.append(ring)
        weights += [0.0] * SEGMENTS
    ob = common.rings_mesh("cloth", rings, [CLOTH] * len(rings), cap=(AX, 0.0, TOP))
    weights.append(0.0)
    attr = ob.data.color_attributes.new("crease", "FLOAT_COLOR", "POINT")
    for i, w in enumerate(weights):
        attr.data[i].color = (w, w, w, 1.0)
    return ob


def under_cloth():
    """The dark cloth showing in the hem's point over the forehead, tucked under it."""
    ts = [0.34 * (1 - 2 * k / 8) for k in range(9)]
    low = outline(0.34)[0][1]
    top = [common.around_tophat_head(outline(t)[0][1] + 0.01, t, OUT - 0.006) for t in ts]
    bottom = [common.around_tophat_head(low, t, OUT - 0.006) for t in ts]
    n = len(ts)
    faces = [(k, k + 1, n + k + 1, n + k) for k in range(n - 1)]
    ob = common.mesh_object("under", top + bottom, faces, [UNDER] * len(faces))
    if sum(1 if q.normal.x > 0 else -1 for q in ob.data.polygons) < 0:
        ob.data.flip_normals()
    return ob


def jewel():
    """An oval stone proud of the front, ringed by a gold setting."""
    on = Vector(point(JEWEL_U, 0.0))
    below, above = Vector(point(JEWEL_U - 0.06, 0.0)), Vector(point(JEWEL_U + 0.06, 0.0))
    up = (above - below).normalized()
    out = Vector((0.0, 1.0, 0.0)).cross(up).normalized()
    if out.x < 0:
        out = -out
    side = up.cross(out)
    c = on + out * 0.02
    basis = (tuple(out), tuple(side), tuple(up))
    parts = [common.ellipsoid("jewel", tuple(c), (0.016, 0.03, 0.04), 12, 6, JEWEL, basis)]
    ring = [tuple(c - out * 0.004 + side * 0.035 * math.cos(2 * math.pi * k / 14) + up * 0.046 * math.sin(2 * math.pi * k / 14))
            for k in range(14)]
    parts.append(common.tube("setting", ring, 0.007, 6, GOLD, closed=True, up=tuple(out)))
    # A gold drop under the stone and a knob above it, as a brooch's mount.
    parts.append(common.ellipsoid("drop", tuple(c - up * 0.06 - out * 0.002), (0.009, 0.01, 0.014), 8, 4, GOLD, basis))
    parts.append(common.ellipsoid("knob", tuple(c + up * 0.057 - out * 0.002), (0.008, 0.012, 0.01), 8, 4, GOLD, basis))
    return parts, c, up, out


def plume(c, out):
    """A dark feather standing up from the setting's knob, kept off the cloth,
    curving a little back at its tip."""
    spine = [c + (UPV * 0.06)]
    for i in range(1, 8):
        p = spine[-1] + (UPV * 0.92 + out * 0.08).normalized() * 0.04 - out * (0.0015 * i * i)
        # Never closer to the head's axis than the cloth at that height, plus a gap.
        u = 0.0
        while u < 0.97 and point(u, 0.0)[2] < p.z:
            u += 0.01
        if u < 0.97:
            p.x = max(p.x, point(u, 0.0, 0.012)[0])
        spine.append(p)
    radii = [0.008, 0.02, 0.028, 0.032, 0.03, 0.026, 0.018, 0.005]
    return [common.tube("feather", [tuple(p) for p in spine], radii, 6, PLUME, flat=0.2, up=tuple(out)),
            common.tube("quill", [tuple(p) for p in spine], 0.004, 4, GOLD)]


def cloth_material(base_hex, dirt_hex, crease_hex):
    """Cotton with light grime and grain, darkened along each layer's crease."""
    mat = common.worn("cloth", base_hex, dirt_hex, grime=0.12, grime_scale=4.0, grain_scale=220.0, grain=0.12)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    color = nodes["Diffuse BSDF"].inputs["Color"]
    worn = color.links[0].from_socket
    weight = nodes.new("ShaderNodeVertexColor")
    weight.layer_name = "crease"
    line = nodes.new("ShaderNodeMix")
    line.data_type = "RGBA"
    links.new(weight.outputs["Color"], line.inputs["Factor"])
    links.new(worn, line.inputs["A"])
    line.inputs["B"].default_value = common.srgb(crease_hex)
    links.new(line.outputs["Result"], color)
    return mat


def jewel_material(c, up, out):
    """Deep red, darker to its edge, under a broad white glint up and to one side."""
    mat, nodes, links, color = common.diffuse_material("jewel")
    coord = nodes.new("ShaderNodeTexCoord")

    def dist_fac(p, r0, r1):
        d = nodes.new("ShaderNodeVectorMath")
        d.operation = "DISTANCE"
        links.new(coord.outputs["Object"], d.inputs[0])
        d.inputs[1].default_value = tuple(p)
        m = nodes.new("ShaderNodeMapRange")
        m.inputs["From Min"].default_value = r0
        m.inputs["From Max"].default_value = r1
        links.new(d.outputs["Value"], m.inputs["Value"])
        return m.outputs["Result"]

    body = nodes.new("ShaderNodeMix")
    body.data_type = "RGBA"
    links.new(dist_fac(c + out * 0.016, 0.0, 0.04), body.inputs["Factor"])
    body.inputs["A"].default_value = common.srgb("e0202c")
    body.inputs["B"].default_value = common.srgb("5c050c")
    glint = nodes.new("ShaderNodeMix")
    glint.data_type = "RGBA"
    side = up.cross(out)
    links.new(dist_fac(c + out * 0.014 + up * 0.016 + side * 0.01, 0.013, 0.006), glint.inputs["Factor"])
    links.new(body.outputs["Result"], glint.inputs["A"])
    glint.inputs["B"].default_value = common.srgb("fff4f2")
    links.new(glint.outputs["Result"], color)
    return mat


def main():
    opts = common.args()
    common.reset()
    stone, c, up, out = jewel()
    parts = [cloth(), under_cloth()] + stone + plume(c, out)
    materials = [
        # Cotton, pushed a little grey so its folds hold under the lobby's key light.
        cloth_material("c4c1b8", "86837a", "5a5750"),
        common.worn("gold", "d6a640", "7a5a22", grime=0.2, grain=0.05, edge_hex="f4dc8c", edge=0.8),
        jewel_material(c, up, out),
        common.worn("plume", "141012", "060505", grime=0.3, grain_scale=400.0, grain=0.4, pattern=("2a2228", 70.0, "WAVE")),
        common.worn("under", "1c1b20", "0c0b0e", grime=0.2, grain=0.2),
    ]
    ob = common.assemble(ID, parts, materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID, ao_floor=0.5, ao_distance=0.06))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "tophat", "tophat", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
