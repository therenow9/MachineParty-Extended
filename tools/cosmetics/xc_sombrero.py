"""xc_sombrero: a forest green felt mariachi sombrero, tall crown, wide brim curled
up at the edge, after the owner's photo: white petals edged in gold round the
crown, gold thread and little gold flowers on the brim, a gold braid round it.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_sombrero.py [-- --preview DIR] [--brim 1.8 --id xc_sombrero_small --out DIR]

Blender axes in the top hat's mesh space: z up the hat, +x the face. The crown
sits on the chef's hat's measured ellipse. The brim is round, its diameter
BRIM times the head's front-to-back length (0.567, common.HEAD_IN_TOPHAT); a
candidate size goes to --out, outside the repo, under its own --id.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402

ID = "xc_sombrero"
BRIM = 2.3
HEAD_LENGTH = common.HEAD_IN_TOPHAT[1][0]
SEGMENTS = 36
FELT, TRIM, CORD, BRIM_TOP_PAINT = range(4)
CENTER = (-0.01, 0.0)
# (z, half-width along x, half-width along y, material of the strip above): band, then crown.
CROWN = [
    (-0.225, 0.292, 0.268, TRIM),
    (-0.150, 0.290, 0.267, FELT),
    (-0.040, 0.278, 0.256, FELT),
    (0.080, 0.248, 0.229, FELT),
    (0.190, 0.200, 0.185, FELT),
    (0.280, 0.140, 0.130, FELT),
    (0.345, 0.075, 0.069, FELT),
]
TOP = 0.372
# Out across the top of the brim and back under it: (fraction of the way from
# the crown to the edge, height, material of the strip toward the next).
BRIM_TOP = [(0.0, -0.225, BRIM_TOP_PAINT), (0.18, -0.236, BRIM_TOP_PAINT), (0.45, -0.246, BRIM_TOP_PAINT),
            (0.74, -0.226, BRIM_TOP_PAINT), (0.9, -0.17, BRIM_TOP_PAINT), (1.0, -0.105, FELT)]
BRIM_UNDER = [(1.0, -0.118, FELT), (0.9, -0.184, FELT), (0.74, -0.24, FELT), (0.45, -0.26, FELT),
              (0.18, -0.25, FELT), (0.0, -0.239, FELT)]


def ellipse(z, ax, ay):
    return [(CENTER[0] + ax * math.cos(t), CENTER[1] + ay * math.sin(t), z)
            for t in (2 * math.pi * i / SEGMENTS for i in range(SEGMENTS))]


def brim_ring(f, z, radius):
    ax, ay = CROWN[0][1], CROWN[0][2]
    return [(CENTER[0] + (ax + f * (radius - ax)) * math.cos(t), CENTER[1] + (ay + f * (radius - ay)) * math.sin(t), z)
            for t in (2 * math.pi * i / SEGMENTS for i in range(SEGMENTS))]


def build(radius):
    crown = common.rings_mesh("crown", [ellipse(z, ax, ay) for z, ax, ay, _ in CROWN],
                              [m for *_, m in CROWN[:-1]] + [FELT], cap=(*CENTER, TOP))
    # Built from under the brim round to its top, so the faces point out of the felt.
    rows = BRIM_TOP + BRIM_UNDER
    mats = [rows[k][2] for k in reversed(range(len(rows) - 1))]
    brim = common.rings_mesh("brim", [brim_ring(f, z, radius) for f, z, _ in reversed(rows)], mats)
    edge = brim_ring(1.0, -0.106, radius + 0.004)
    cord = common.tube("cord", edge, 0.009, 4, CORD, closed=True)
    return [crown, brim, cord]


def brim_paint(name, radius):
    """The brim's top after the owner's photo: forest green felt, eight white
    petals round the crown edged in gold, fans of gold thread between them,
    little gold flowers further out, and a gold looped braid up the curl.
    Painted from the angle and distance round the crown in the mesh's plan."""
    mat, nodes, links, color = common.diffuse_material(name)
    coord = nodes.new("ShaderNodeTexCoord")
    xyz = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coord.outputs["Object"], xyz.inputs["Vector"])

    def op(kind, a, b=None, clamp=False):
        m = nodes.new("ShaderNodeMath")
        m.operation = kind
        m.use_clamp = clamp
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

    dx = op("SUBTRACT", xyz.outputs["X"], CENTER[0])
    dy = op("SUBTRACT", xyz.outputs["Y"], CENTER[1])
    r = op("SQRT", op("ADD", op("MULTIPLY", dx, dx), op("MULTIPLY", dy, dy)))
    inner = (CROWN[0][1] + CROWN[0][2]) / 2
    f = op("DIVIDE", op("SUBTRACT", r, inner), radius - inner)
    theta = op("ARCTAN2", dy, dx)
    # Distance from the nearest petal's centre line, in petal widths (one per 45 degrees).
    a = op("MULTIPLY", theta, 4 / math.pi)
    d = op("ABSOLUTE", op("SUBTRACT", a, op("ROUND", a)))
    # A petal's half-width: wide at the crown, pointed at f 0.72.
    w = op("MULTIPLY", op("POWER", op("SUBTRACT", 1.0, op("DIVIDE", f, 0.72), clamp=True), 0.6), 0.5)
    e = op("SUBTRACT", w, d)
    petal = band(e, 0.0, 0.015)
    border = op("MULTIPLY", petal, band(e, 0.085, 0.07))
    swirl = op("MULTIPLY", op("MULTIPLY", band(e, 0.12, 0.13), band(e, 0.17, 0.16)), band(f, 0.52, 0.47))
    # Gold thread between the petals: fine radial lines out to f 0.68.
    lines = op("FRACT", op("MULTIPLY", theta, 128 / (2 * math.pi)))
    thread = band(op("ABSOLUTE", op("SUBTRACT", lines, 0.5)), 0.3, 0.45)
    fans = op("MULTIPLY", op("MULTIPLY", thread, op("SUBTRACT", 1.0, petal)), op("MULTIPLY", band(f, 0.04, 0.08), band(f, 0.68, 0.6)))
    # Little gold flowers in the plain felt further out.
    cells = nodes.new("ShaderNodeTexVoronoi")
    cells.inputs["Scale"].default_value = 9.0
    links.new(coord.outputs["Object"], cells.inputs["Vector"])
    dots = op("MULTIPLY", band(cells.outputs["Distance"], 0.16, 0.11), op("MULTIPLY", band(f, 0.72, 0.76), band(f, 0.87, 0.83)))
    # The braid: gold loops up the curl.
    loops = band(op("SINE", op("ADD", op("MULTIPLY", theta, 70.0), op("MULTIPLY", f, 30.0))), -0.3, 0.1)
    braid = op("MULTIPLY", loops, band(f, 0.87, 0.9))
    out = common.srgb("0b6a3e")
    out = paint(out, petal, "eee8d8")
    out = paint(out, op("ADD", border, op("MULTIPLY", swirl, petal), clamp=True), "e0aa22")
    out = paint(out, fans, "c8902a")
    out = paint(out, dots, "dcae3a")
    out = paint(out, braid, "e0aa22")
    grime = nodes.new("ShaderNodeTexNoise")
    grime.inputs["Scale"].default_value = 5.0
    grime.inputs["Detail"].default_value = 8.0
    links.new(coord.outputs["Object"], grime.inputs["Vector"])
    out = paint(out, op("MULTIPLY", band(grime.outputs["Fac"], 0.45, 0.75), 0.3), "3a3530")
    links.new(out, color)
    return mat


def main():
    opts = common.args()
    item_id = opts.get("id", ID)
    radius = float(opts.get("brim", BRIM)) * HEAD_LENGTH / 2
    common.reset()
    materials = [
        common.worn("felt", "0b6a3e", "05341f", grime=0.35, grime_scale=4.0, grain=0.2),
        # The band: white, worked in gold.
        common.worn("trim", "eee8d8", "8a8270", grime=0.3, grain=0.15, pattern=("e0aa22", 16.0, "WAVE")),
        common.worn("cord", "e0aa22", "6a5020", grime=0.3, grain=0.1, edge_hex="f2d27a", edge=0.5),
        brim_paint("brim_top", radius),
    ]
    ob = common.assemble(item_id, build(radius), materials)
    n = common.check_budget(ob, item_id)
    print(item_id, n, "triangles, brim diameter %.3f" % (2 * radius))
    print("wrote", common.bake(ob, item_id))
    print("wrote", common.export(ob, item_id))
    if opts["preview"]:
        common.preview(ob, item_id, opts["preview"], "tophat", "tophat", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
