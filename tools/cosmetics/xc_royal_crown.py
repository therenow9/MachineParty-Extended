"""xc_royal_crown: a royal crown after the owner's pictures: a roll of ermine
(white fur, black tail spots) round the head, a gold band set with red, green,
blue and clear stones, crosses and fleurs-de-lis round its rim, two arches
set with small stones swelling out over a puffed purple velvet cap, and a
jewelled cross on an orb where they cross.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_royal_crown.py [-- --preview DIR]

Blender axes in the top hat's mesh space: z up the hat, +x the face, -y the
character's right. The crown sits level on the head (common.level_point): the
fur at the hat line, everything above it round the head's measured radius plus
GAP. The arches rise from behind the four crosses' tops, swell out past the
band and dip a little where they cross.
The stones are painted, since nothing in the game glows.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_royal_crown"
FUR, GOLD, VELVET, RED, GREEN, BLUE, CLEAR = range(7)
STONES = [RED, BLUE, GREEN, CLEAR]
SEGMENTS = 24
GAP = 0.012
HAT_LINE = -0.14  # the ears' tops are near -0.19, the brow near -0.23
FUR_R, FUR_H = 0.03, 0.042  # the roll's half-depth out from the head and half-height
BAND_LO, BAND_HI, FLARE = 0.036, 0.11, 0.12  # the gold band, and how far it leans out per unit up
# Above the hat line: an arch leaves its cross at ARCH_FOOT, is widest at
# SHOULDER, and rounds over on a quarter ellipse to DOME, dipping DIP where
# the arches cross.
ARCH_FOOT, SHOULDER, DOME, DIP = 0.17, 0.225, 0.385, 0.008
ARCH_TOP = DOME - DIP
UP, FACE, LEFT = common.LEVEL_UP, common.LEVEL_FACE, common.LEVEL_LEFT


def at(r, phi, c):
    return Vector(common.level_point(HAT_LINE, r, phi, c))


def out_dir(phi):
    return FACE * math.cos(phi) + LEFT * math.sin(phi)


def side_dir(phi):
    return FACE * -math.sin(phi) + LEFT * math.cos(phi)


def head_r(c, phi):
    return common.level_head_radius(HAT_LINE + c, phi)


def smooth(e):
    e = min(max(e, 0.0), 1.0)
    return e * e * (3 - 2 * e)


def open_r(phi):
    """The head's radius just above the hat line, plus GAP."""
    return max(head_r(c, phi) for c in (0.0, 0.03, 0.06)) + GAP


def band_r(phi, c):
    return open_r(phi) + 0.018 + FLARE * (c - BAND_LO)


PHIS = [2 * math.pi * i / SEGMENTS for i in range(SEGMENTS)]


def fur():
    """The ermine: a closed roll round the head at the hat line."""
    path = [tuple(at(open_r(p) + FUR_R - 0.004, p, 0.0)) for p in PHIS]
    return common.tube("fur", path, FUR_R, 6, FUR, closed=True, flat=FUR_H / FUR_R, up=tuple(UP))


def band():
    """The gold band on the fur, leaning out, with a lip folding in at its top."""
    rings = [[tuple(at(band_r(p, c) + dr, p, c)) for p in PHIS]
             for c, dr in ((BAND_LO, 0.0), (BAND_HI, 0.0), (BAND_HI + 0.004, -0.008), (BAND_HI, -0.014))]
    return common.rings_mesh("band", rings, [GOLD] * len(rings))


def gem(name, c, out, up, size, depth, sides, mat):
    """A cut stone: a flat bipyramid, its table facing out."""
    side = up.cross(out).normalized()
    verts = [tuple(c - out * depth * 0.4)]
    for k in range(sides):
        a = 2 * math.pi * k / sides + math.pi / sides
        verts.append(tuple(c + (side * math.cos(a) + up * math.sin(a)) * size))
    verts.append(tuple(c + out * depth))
    tip = len(verts) - 1
    faces = [(0, 1 + (k + 1) % sides, 1 + k) for k in range(sides)] + [(1 + k, 1 + (k + 1) % sides, tip) for k in range(sides)]
    ob = common.mesh_object(name, verts, faces, [mat] * len(faces))
    if sum(q.normal.dot(q.center - c) for q in ob.data.polygons) < 0:
        ob.data.flip_normals()
    return ob


def band_stones():
    """Eight stones round the band, between the ornaments above."""
    parts = []
    c_mid = (BAND_LO + BAND_HI) / 2
    for k in range(8):
        p = 2 * math.pi * (k + 0.5) / 8
        o = out_dir(p)
        lean = (UP - o * FLARE).normalized()
        c = at(band_r(p, c_mid) + 0.003, p, c_mid)
        parts.append(gem("stone%d" % k, c, o, lean, 0.026, 0.014, 6, STONES[k % 4]))
    return parts


def flat_shape(name, outline, c, out, up, size, thick, mat):
    """A flat outline (x across, y up, base at y 0) stood on c, facing out, given thickness."""
    side = up.cross(out).normalized()
    n = len(outline)
    front = [tuple(c + side * (x * size) + up * (y * size) + out * (thick / 2)) for x, y in outline]
    back = [tuple(c + side * (x * size) + up * (y * size) - out * (thick / 2)) for x, y in outline]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    faces += [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    ob = common.mesh_object(name, front + back, faces, [mat] * len(faces))
    # Faces point out of the solid: the front face along out.
    if ob.data.polygons[0].normal.dot(out) < 0:
        ob.data.flip_normals()
    return ob


def cross_outline(cy=0.5, inner=0.1, arm=0.5, flare=0.3):
    """A cross pattee round (0, cy): four arms flaring from the middle."""
    pts = []
    for dx, dy in ((0, 1), (1, 0), (0, -1), (-1, 0)):
        px, py = dy, -dx  # the arm's own right
        pts.append((-px * flare + dx * arm, cy - py * flare + dy * arm))
        pts.append((px * flare + dx * arm, cy + py * flare + dy * arm))
        pts.append(((dx + px) * inner, cy + (dy + py) * inner))
    return pts


FLEUR_RIGHT = [(0.0, 1.0), (0.12, 0.72), (0.09, 0.44), (0.2, 0.54), (0.34, 0.63), (0.42, 0.5), (0.34, 0.35),
               (0.2, 0.29), (0.2, 0.18), (0.1, 0.17), (0.15, 0.0)]


def fleur_outline():
    right = FLEUR_RIGHT
    return right + [(-x, y) for x, y in reversed(right[1:])]


def rim():
    """Crosses front, back and sides, fleurs-de-lis between, each with a stone."""
    parts = []
    for k in range(8):
        p = 2 * math.pi * k / 8
        o = out_dir(p)
        lean = (UP + o * FLARE).normalized()
        c = at(band_r(p, BAND_HI) - 0.004, p, BAND_HI - 0.004)
        if k % 2 == 0:
            parts.append(flat_shape("cross%d" % k, cross_outline(), c, o, lean, 0.085, 0.008, GOLD))
            parts.append(gem("crossstone%d" % k, c + lean * (0.5 * 0.085) + o * 0.004, o, lean, 0.011, 0.007, 4, STONES[(k // 2 + 1) % 4]))
        else:
            parts.append(flat_shape("fleur%d" % k, fleur_outline(), c, o, lean, 0.075, 0.008, GOLD))
    return parts


def arch_path(phi, n=11):
    """One half-arch, from behind the top of the cross at phi, swelling out past
    the band, then in to where the arches cross, a little below their highest."""
    r0 = band_r(phi, BAND_HI) - 0.008
    a, b = r0 + 0.04, DOME - SHOULDER
    ctrl = [(r0, ARCH_FOOT)] + [(a * math.cos(math.radians(t)), SHOULDER + b * math.sin(math.radians(t))) for t in (0, 35, 62, 80)]
    ctrl.append((0.0, ARCH_TOP))
    ext = [ctrl[0]] + ctrl + [ctrl[-1]]
    pts = []
    segs = len(ctrl) - 1
    for k in range(n):
        q = k / (n - 1) * segs
        i = min(int(q), segs - 1)
        t = q - i
        p0, p1, p2, p3 = ext[i:i + 4]
        pts.append(tuple(0.5 * (2 * p1[d] + (p2[d] - p0[d]) * t + (2 * p0[d] - 5 * p1[d] + 4 * p2[d] - p3[d]) * t * t
                                + (3 * p1[d] - p0[d] - 3 * p2[d] + p3[d]) * t ** 3) for d in range(2)))
    return pts


def arches():
    """Four gold half-arches, each set with two small stones on its outer side."""
    parts = []
    for k in range(4):
        p = math.pi / 2 * k
        path = [at(r, p, c) for r, c in arch_path(p)]
        parts.append(common.tube("arch%d" % k, [tuple(q) for q in path], 0.013, 4, GOLD, flat=0.55, up=tuple(out_dir(p)), cap=False))
        for j, i in enumerate((4, 7)):
            along = (path[i + 1] - path[i - 1]).normalized()
            n = along.cross(side_dir(p)).normalized()
            if n.dot(out_dir(p) + UP) < 0:
                n = -n
            parts.append(gem("archstone%d_%d" % (k, j), path[i] + n * 0.006, n, along, 0.012, 0.008, 4, STONES[(k + j) % 4]))
    return parts


def velvet():
    """The cap: from inside the band up behind the rim, then out under the arches,
    puffed out between them."""
    rings = []
    profile = arch_path(0.0, 7)[:-1]
    r_ref = profile[0][0]
    rows = [(None, BAND_LO + 0.01), (None, BAND_HI + 0.028)] + profile
    for j, (r_a, c_a) in enumerate(rows):
        f = j / len(rows)
        ring = []
        for p in PHIS:
            if r_a is None:
                base = band_r(p, c_a - 0.018) - (0.012 if j == 0 else 0.016)
            else:
                base = r_a / r_ref * (band_r(p, BAND_HI) - 0.02)
            puff = math.sin(2 * p) ** 2 * smooth((f - 0.15) / 0.5)
            r = base * (1.0 + 0.1 * puff)
            c = c_a - 0.018 + 0.03 * puff * f
            if j > 0:
                r = max(r, head_r(c, p) + GAP)
            if r_a is None:
                r, c = base, c_a - 0.018
            ring.append(tuple(at(r, p, c)))
        rings.append(ring)
    top = ARCH_TOP - 0.02
    if top < common.LEVEL_HEAD_TOP - HAT_LINE + GAP:
        raise SystemExit("the velvet's top %.3f is inside the head" % top)
    return common.rings_mesh("velvet", rings, [VELVET] * len(rings), cap=tuple(at(0.0, 0.0, top)))


def topper():
    """A gold orb where the arches cross, a jewelled cross on it."""
    c = at(0.0, 0.0, ARCH_TOP + 0.035)
    parts = [common.ellipsoid("orb", tuple(c), (0.036, 0.036, 0.034), 8, 5, GOLD, (tuple(FACE), tuple(LEFT), tuple(UP)))]
    band_ring = [tuple(c + (FACE * math.cos(a) + LEFT * math.sin(a)) * 0.037) for a in (2 * math.pi * k / 8 for k in range(8))]
    parts.append(common.tube("orbband", band_ring, 0.005, 3, GOLD, closed=True, up=tuple(UP)))
    base = c + UP * 0.03
    parts.append(flat_shape("topcross", cross_outline(), base, FACE, UP, 0.075, 0.01, GOLD))
    parts.append(gem("topstone", base + UP * (0.5 * 0.075) + FACE * 0.005, FACE, UP, 0.012, 0.008, 4, RED))
    parts.append(gem("topstone_back", base + UP * (0.5 * 0.075) - FACE * 0.005, -FACE, UP, 0.012, 0.008, 4, RED))
    return parts


def stone_material(name, hex_rgb, dark_hex):
    """A stone's colour, darker on its lower facets, a white glint on those facing up."""
    mat, nodes, links, color = common.diffuse_material(name)
    geo = nodes.new("ShaderNodeNewGeometry")
    dot = nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    links.new(geo.outputs["Normal"], dot.inputs[0])
    dot.inputs[1].default_value = tuple(UP)

    def mapped(lo, hi):
        m = nodes.new("ShaderNodeMapRange")
        m.inputs["From Min"].default_value = lo
        m.inputs["From Max"].default_value = hi
        links.new(dot.outputs["Value"], m.inputs["Value"])
        return m.outputs["Result"]

    body = nodes.new("ShaderNodeMix")
    body.data_type = "RGBA"
    links.new(mapped(-0.4, 0.5), body.inputs["Factor"])
    body.inputs["A"].default_value = common.srgb(dark_hex)
    body.inputs["B"].default_value = common.srgb(hex_rgb)
    glint = nodes.new("ShaderNodeMix")
    glint.data_type = "RGBA"
    links.new(mapped(0.55, 0.75), glint.inputs["Factor"])
    links.new(body.outputs["Result"], glint.inputs["A"])
    glint.inputs["B"].default_value = common.srgb("fbf8f4")
    links.new(glint.outputs["Result"], color)
    return mat


def fur_material():
    """White fur with a soft grey grain, and two staggered rows of black tail spots."""
    mat = common.worn("fur", "f1efe8", "b8b4aa", grime=0.25, grime_scale=6.0, grain_scale=500.0, grain=0.3)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    color = nodes["Diffuse BSDF"].inputs["Color"]
    worn = color.links[0].from_socket
    coord = nodes.new("ShaderNodeTexCoord")
    rel = nodes.new("ShaderNodeVectorMath")
    rel.operation = "SUBTRACT"
    links.new(coord.outputs["Object"], rel.inputs[0])
    rel.inputs[1].default_value = tuple(at(0.0, 0.0, 0.0))

    def dot(v):
        d = nodes.new("ShaderNodeVectorMath")
        d.operation = "DOT_PRODUCT"
        links.new(rel.outputs["Vector"], d.inputs[0])
        d.inputs[1].default_value = tuple(v)
        return d.outputs["Value"]

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

    def band(v, lo, hi):
        r = nodes.new("ShaderNodeMapRange")
        r.inputs["From Min"].default_value = lo
        r.inputs["From Max"].default_value = hi
        links.new(v, r.inputs["Value"])
        return r.outputs["Result"]

    theta = op("ARCTAN2", dot(LEFT), dot(FACE))
    height = dot(UP)
    spots = None
    for row, (lo, hi) in enumerate(((0.004, 0.03), (-0.03, -0.004))):
        a = op("ADD", op("MULTIPLY", theta, 14 / (2 * math.pi)), 0.5 * row)
        d = op("ABSOLUTE", op("SUBTRACT", a, op("ROUND", a)))
        # A tail: narrow, a little wider at its top.
        w = op("ADD", 0.06, op("MULTIPLY", band(height, lo, hi), 0.06))
        across = band(op("SUBTRACT", w, d), 0.0, 0.02)
        along = op("MULTIPLY", band(height, lo, lo + 0.004), band(height, hi, hi - 0.004))
        one = op("MULTIPLY", across, along)
        spots = one if spots is None else op("MAXIMUM", spots, one)
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    links.new(spots, mix.inputs["Factor"])
    links.new(worn, mix.inputs["A"])
    mix.inputs["B"].default_value = common.srgb("17140f")
    links.new(mix.outputs["Result"], color)
    return mat


def main():
    opts = common.args()
    item_id = ID
    common.reset()
    parts = [fur(), band(), velvet()] + band_stones() + rim() + arches() + topper()
    materials = [
        fur_material(),
        common.worn("gold", "d6a640", "7a5a22", grime=0.2, grain=0.05, edge_hex="f4dc8c", edge=0.8),
        # Deep, so it holds its colour under the lobby's key light.
        common.worn("velvet", "3c0478", "1a0234", grime=0.3, grime_scale=6.0, grain_scale=300.0, grain=0.2),
        stone_material("red", "d4142a", "4a0410"),
        stone_material("green", "12a046", "03301a"),
        stone_material("blue", "1e46d8", "081448"),
        stone_material("clear", "e6ecf2", "7a8698"),
    ]
    ob = common.assemble(item_id, parts, materials)
    n = common.check_budget(ob, item_id)
    print(item_id, n, "triangles")
    print("wrote", common.bake(ob, item_id, ao_floor=0.5, ao_distance=0.06))
    print("wrote", common.export(ob, item_id, smooth_angle=40))
    if opts["preview"]:
        common.preview(ob, item_id, opts["preview"], "tophat", "tophat", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
