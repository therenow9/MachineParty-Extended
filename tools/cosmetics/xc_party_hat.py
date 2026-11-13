"""xc_party_hat: a paper party cone printed with balloons and confetti after
the owner's photo, its rim rolled, held on by a thin elastic under the chin.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_party_hat.py [-- --preview DIR]
  ... -- --out DIR --id <id>   # a review candidate

Blender axes in the top hat's mesh space: z up the hat, +x the face, -y the
character's right. The rim is an oval, as paper squeezes to the head, lowered
onto the crown until it meets the head's measured surface, so it rests there,
upright. The print is painted on the cone unrolled flat (the slant distance
from the tip, and the angle round the axis scaled to the flat sector, the oval
taken as round), so the balloons stay round on the cone.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_party_hat"
PRINT, RIM, ELASTIC = range(3)
AX = common.HEAD_AXIS_X_IN_TOPHAT
SEGMENTS = 28
RADIUS, ACROSS = 0.17, 0.145  # the rim's half widths along the face and across, as the crown's
HEIGHT = 0.46  # from the rim's centre to the tip, as the photo's proportions
SLANT = math.hypot(RADIUS, HEIGHT)
CENTER = (-0.008, 0.0)  # over the crown's middle
OUT = 0.006
# The crown's radius from CENTER, 12 angles from the face toward the
# character's right, the widest within 15 degrees of each: printed by
# head_radius.py --space crown, finer than HEAD_RADIUS_IN_TOPHAT, which ends at 0.000.
CROWN = [
    (-0.020, [0.187, 0.189, 0.156, 0.160, 0.184, 0.186, 0.183, 0.183, 0.174, 0.145, 0.150, 0.182]),
    (-0.015, [0.179, 0.182, 0.153, 0.152, 0.181, 0.183, 0.179, 0.175, 0.171, 0.139, 0.142, 0.172]),
    (-0.010, [0.169, 0.171, 0.146, 0.145, 0.173, 0.175, 0.171, 0.169, 0.163, 0.133, 0.131, 0.163]),
    (-0.005, [0.159, 0.160, 0.134, 0.138, 0.166, 0.167, 0.163, 0.164, 0.153, 0.127, 0.122, 0.154]),
    (0.000, [0.150, 0.150, 0.124, 0.132, 0.157, 0.163, 0.155, 0.155, 0.142, 0.120, 0.111, 0.144]),
    (0.005, [0.121, 0.121, 0.118, 0.124, 0.148, 0.150, 0.146, 0.143, 0.133, 0.114, 0.103, 0.106]),
    (0.010, [0.088, 0.103, 0.104, 0.117, 0.135, 0.140, 0.136, 0.132, 0.122, 0.108, 0.090, 0.089]),
    (0.015, [0.049, 0.087, 0.091, 0.109, 0.125, 0.126, 0.121, 0.118, 0.112, 0.085, 0.075, 0.058]),
    (0.020, [0.029, 0.042, 0.070, 0.090, 0.114, 0.112, 0.107, 0.106, 0.100, 0.068, 0.057, 0.030]),
    (0.024, [0.013, 0.018, 0.054, 0.067, 0.105, 0.102, 0.098, 0.096, 0.057, 0.038, 0.024, 0.014]),
]
X, LEFT, UP = Vector((1.0, 0.0, 0.0)), Vector((0.0, 1.0, 0.0)), Vector((0.0, 0.0, 1.0))
# The elastic leaves the rim at these angles from the face, runs down in front
# of the ear to the jaw on the head's measured surface, then under the chin,
# where the head table ends (y -0.56): (height, degrees from the face, radius
# from the head's axis), placed from the head's bottom at -0.617.
ELASTIC_T, JAW, JAW_T = math.radians(78), -0.52, math.radians(55)
CHIN = [(-0.56, 42, 0.172), (-0.592, 28, 0.158), (-0.612, 13, 0.145)]
CHIN_MIDDLE = (-0.62, 0, 0.14)
# Deeper than the photo's: the lobby's light washes saturated colours out.
PALETTE = {"red": "c00c10", "orange": "e05a00", "yellow": "e8b400", "lime": "52a80c",
           "teal": "008a80", "blue": "0c5cc0", "purple": "561c96"}
# Painted in order, so a later balloon overlaps an earlier one: (degrees round
# the cone from the face toward the character's right, slant distance from the
# tip to the balloon's centre, half width, colour, sprinkled with confetti).
# Large and close, as the photo's, so they read from across the room.
BALLOONS = [
    (-135, 0.405, 0.074, "blue", False), (-75, 0.415, 0.076, "lime", False), (-15, 0.41, 0.076, "orange", True),
    (45, 0.41, 0.074, "purple", True), (105, 0.415, 0.076, "yellow", False), (165, 0.405, 0.074, "red", True),
    (-165, 0.27, 0.058, "teal", False), (-105, 0.275, 0.059, "red", True), (-45, 0.265, 0.06, "yellow", False),
    (15, 0.275, 0.059, "red", True), (75, 0.27, 0.058, "teal", False), (135, 0.275, 0.059, "lime", False),
    (-90, 0.15, 0.04, "purple", False), (30, 0.145, 0.04, "blue", False), (150, 0.15, 0.04, "orange", False),
]
STRING = 0.085


def rim_point(c, t, f=1.0, grow=0.0):
    """On the rim's oval, scaled by f and grown by grow, at angle t from the
    face toward the character's right."""
    return c + X * ((RADIUS * f + grow) * math.cos(t)) - LEFT * ((ACROSS * f + grow) * math.sin(t))


def clears(p):
    """p is OUT outside the head, or above its crown (y 0.026)."""
    if p.z > CROWN[-1][0]:
        return True
    if p.z >= CROWN[0][0]:
        dx, dy = p.x - CENTER[0], p.y - CENTER[1]
        return math.hypot(dx, dy) >= common.head_radius(CROWN, p.z, math.atan2(-dy, dx)) + OUT
    t = math.atan2(-p.y, p.x - AX)
    need = max(common.head_radius(common.HEAD_RADIUS_IN_TOPHAT, p.z, t + d) for d in (-0.26, 0.0, 0.26)) + OUT
    return math.hypot(p.x - AX, p.y) >= need


def rest():
    """The rim's centre, lowered 2 mm at a time until it would touch the head."""
    c = Vector((CENTER[0], CENTER[1], 0.06))
    while c.z > -0.2:
        lower = c - Vector((0.0, 0.0, 0.002))
        if not all(clears(rim_point(lower, 2 * math.pi * k / 64)) for k in range(64)):
            break
        c = lower
    return c


def cone(c):
    # Round the other way from rim_point's angle, so the faces point out.
    rings = []
    for k in range(8):
        f = k / 8
        rings.append([tuple(rim_point(c + UP * (HEIGHT * f), -2 * math.pi * i / SEGMENTS, 1 - f))
                      for i in range(SEGMENTS)])
    return common.rings_mesh("cone", rings, [PRINT] * 7, cap=tuple(c + UP * HEIGHT))


def roll(c):
    """The rim's rolled paper edge."""
    path = [tuple(rim_point(c, 2 * math.pi * i / SEGMENTS, grow=0.002)) for i in range(SEGMENTS)]
    return common.tube("roll", path, 0.0065, 5, RIM, closed=True, up=tuple(UP))


def strand(c, side):
    """One side of the elastic, from the rim down to under the chin; side +1 is
    the character's right."""
    p = rim_point(c, side * ELASTIC_T)
    top = math.atan2(-p.y, p.x - AX)
    pts = [p]
    for i in range(1, 10):
        f = i / 9
        pts.append(Vector(common.around_tophat_head(p.z + (JAW - p.z) * f, top + (side * JAW_T - top) * f, 0.004)))
    for h, t, r in CHIN:
        t = side * math.radians(t)
        pts.append(Vector((AX + r * math.cos(t), -r * math.sin(t), h)))
    return pts


def elastic(c):
    h, _, r = CHIN_MIDDLE
    path = strand(c, -1) + [Vector((AX + r, 0.0, h))] + list(reversed(strand(c, 1)))
    return common.tube("elastic", [tuple(p) for p in path], 0.0032, 4, ELASTIC)


def print_material(tip):
    """The photo's print: balloons with a highlight, a knot and a string, some
    sprinkled with confetti, over confetti dots on white paper with a seam at
    the back."""
    mat, nodes, links, color = common.diffuse_material("print")
    coord = nodes.new("ShaderNodeTexCoord")
    xyz = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coord.outputs["Object"], xyz.inputs["Vector"])

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
        """0 below lo, rising to 1 at hi (or falling, if hi < lo)."""
        r = nodes.new("ShaderNodeMapRange")
        r.inputs["From Min"].default_value = lo
        r.inputs["From Max"].default_value = hi
        links.new(v, r.inputs["Value"])
        return r.outputs["Result"]

    def paint(src, fac, colour):
        m = nodes.new("ShaderNodeMix")
        m.data_type = "RGBA"
        links.new(fac, m.inputs["Factor"])
        for sock, v in (("A", src), ("B", colour)):
            if isinstance(v, tuple):
                m.inputs[sock].default_value = v
            else:
                links.new(v, m.inputs[sock])
        return m.outputs["Result"]

    def confetti(vec, scale, size, share):
        """Round dots, one in some cells, each in a palette colour: (factor, colour)."""
        cells = nodes.new("ShaderNodeTexVoronoi")
        cells.voronoi_dimensions = "2D"
        cells.inputs["Scale"].default_value = scale
        links.new(vec, cells.inputs["Vector"])
        rgb = nodes.new("ShaderNodeSeparateColor")
        links.new(cells.outputs["Color"], rgb.inputs["Color"])
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "CONSTANT"
        hexes = list(PALETTE.values())
        while len(ramp.color_ramp.elements) < len(hexes):
            ramp.color_ramp.elements.new(0.5)
        for k, (e, h) in enumerate(zip(ramp.color_ramp.elements, hexes)):
            e.position = k / len(hexes)
            e.color = common.srgb(h)
        links.new(rgb.outputs["Red"], ramp.inputs["Fac"])
        fac = op("MULTIPLY", band(cells.outputs["Distance"], size, size * 0.7), band(rgb.outputs["Green"], 1 - share, 1.02 - share))
        return fac, ramp.outputs["Color"]

    # From the tip, with the oval stretched across to round.
    dx = op("SUBTRACT", xyz.outputs["X"], tip.x)
    qy = op("MULTIPLY", op("SUBTRACT", xyz.outputs["Y"], tip.y), RADIUS / ACROSS)
    dz = op("SUBTRACT", xyz.outputs["Z"], tip.z)
    s = op("SQRT", op("ADD", op("ADD", op("MULTIPLY", dx, dx), op("MULTIPLY", qy, qy)), op("MULTIPLY", dz, dz)))
    t = op("ARCTAN2", op("MULTIPLY", qy, -1.0), dx)
    psi = op("MULTIPLY", t, RADIUS / SLANT)
    fx = op("MULTIPLY", s, op("COSINE", psi))
    fy = op("MULTIPLY", s, op("SINE", psi))
    flat = nodes.new("ShaderNodeCombineXYZ")
    links.new(fx, flat.inputs["X"])
    links.new(fy, flat.inputs["Y"])

    out = common.srgb("f2eee4")
    fac, dots = confetti(flat.outputs["Vector"], 48.0, 0.2, 0.5)
    out = paint(out, fac, dots)
    sprinkles = confetti(flat.outputs["Vector"], 150.0, 0.24, 0.6)
    for deg, dist, rw, name, sprinkled in BALLOONS:
        rh = rw * 1.18
        p = math.radians(deg) * RADIUS / SLANT
        cx, cy = dist * math.cos(p), dist * math.sin(p)
        # Across the balloon (toward the character's right) and down it, toward the rim.
        ox, oy = op("SUBTRACT", fx, cx), op("SUBTRACT", fy, cy)
        across = op("ADD", op("MULTIPLY", ox, -math.sin(p)), op("MULTIPLY", oy, math.cos(p)))
        down = op("ADD", op("MULTIPLY", ox, math.cos(p)), op("MULTIPLY", oy, math.sin(p)))

        def ellipse(u0, v0, ru, rv):
            u = op("MULTIPLY", op("SUBTRACT", across, u0), 1 / ru)
            v = op("MULTIPLY", op("SUBTRACT", down, v0), 1 / rv)
            return op("ADD", op("MULTIPLY", u, u), op("MULTIPLY", v, v))

        e = ellipse(0.0, 0.0, rw, rh)
        body = op("MAXIMUM", band(e, 1.0, 0.9), band(ellipse(0.0, rh + 0.003, 0.0065, 0.006), 1.0, 0.8))
        wiggle = op("SUBTRACT", across, op("MULTIPLY", op("SINE", op("MULTIPLY", down, 70.0)), 0.004))
        string = op("MULTIPLY", band(op("ABSOLUTE", wiggle), 0.0028, 0.0016),
                    op("MULTIPLY", band(down, rh, rh + 0.004), band(down, rh + STRING, rh + STRING - 0.006)))
        base = common.srgb(PALETTE[name])
        out = paint(out, string, common.srgb("2b2d4a"))
        out = paint(out, body, base)
        out = paint(out, op("MULTIPLY", op("MULTIPLY", band(e, 0.5, 1.0), body), 0.45), tuple(v * 0.35 for v in base[:3]) + (1.0,))
        if sprinkled:
            out = paint(out, op("MULTIPLY", sprinkles[0], band(e, 0.9, 0.8)), sprinkles[1])
        out = paint(out, op("MULTIPLY", band(ellipse(rw * 0.42, -rh * 0.38, rw * 0.13, rh * 0.3), 1.0, 0.7), body), common.srgb("fbfaf5"))
    # The seam up the back, where the paper overlaps.
    seam = band(op("MULTIPLY", op("SUBTRACT", math.pi, op("ABSOLUTE", t)), op("MULTIPLY", s, RADIUS / SLANT)), 0.003, 0.0015)
    out = paint(out, seam, common.srgb("b9b2a3"))
    grime = nodes.new("ShaderNodeTexNoise")
    grime.inputs["Scale"].default_value = 6.0
    grime.inputs["Detail"].default_value = 8.0
    links.new(coord.outputs["Object"], grime.inputs["Vector"])
    out = paint(out, op("MULTIPLY", band(grime.outputs["Fac"], 0.45, 0.75), 0.3), common.srgb("6e6758"))
    links.new(out, color)
    return mat


def main():
    opts = common.args()
    item_id = opts.get("id", ID)
    common.reset()
    c = rest()
    tip = c + UP * HEIGHT
    print("rim centre %.3f %.3f %.3f, tip %.3f %.3f %.3f" % (*c, *tip))
    parts = [cone(c), roll(c), elastic(c)]
    materials = [
        print_material(tip),
        common.worn("rim", "f2eee4", "8c8474", grime=0.3, grime_scale=6.0, grain=0.08),
        common.worn("elastic", "2a2723", "121110", grime=0.2, grain=0.05, edge_hex="5a554c", edge=0.4),
    ]
    ob = common.assemble(item_id, parts, materials)
    n = common.check_budget(ob, item_id)
    print(item_id, n, "triangles")
    print("wrote", common.bake(ob, item_id, ao_floor=0.6, ao_distance=0.06))
    print("wrote", common.export(ob, item_id))
    if opts["preview"]:
        common.preview(ob, item_id, opts["preview"], "tophat", "tophat", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
