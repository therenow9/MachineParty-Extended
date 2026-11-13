"""xc_pharaoh_headdress: a pharaoh's nemes striped in gold and lapis, a gold
brow band with a red and a blue stripe, a cobra and a vulture on the brow, the
lappets down to the shoulders and the cloth gathered into a tail at the back,
after the owner's pictures.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_pharaoh_headdress.py [-- --preview DIR]

Blender axes in the top hat's mesh space: z up the hat, +x the face, -y the
character's right. The head's own up leans toward the face (common.UP_IN_TOPHAT),
so heights are taken along it (level()): the band and the stripes sit level on
the head and the cloth hangs straight down from it. The hood stands off the
head's measured radius from the band up; the wings hang from its hem round the
sides and back, never inside the head above them, and come to rest on the
body's measured top (BODY_TOP), as does the tail. Near the face
the wings turn forward into the lappets.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_pharaoh_headdress"
CLOTH, GOLD, BAND, INLAY = range(4)
AX = common.HEAD_AXIS_X_IN_TOPHAT
# The head's up, Blender axes: a height along it is z + K x.
K = common.UP_IN_TOPHAT[0] / common.UP_IN_TOPHAT[1]
UPV = Vector((common.UP_IN_TOPHAT[0], 0.0, common.UP_IN_TOPHAT[1])).normalized()
FWD = Vector((UPV.z, 0.0, -UPV.x))
SEGMENTS = 24
OUT = 0.016  # the hood's and the wings' least gap to the head
GAP = 0.012  # to the body
TOP = 0.058  # the head peaks at y 0.026
# The band across the brow (the eyes are near y -0.37, the brow -0.30), as levels.
BAND_LO, BAND_HI = -0.222, -0.152
T_FACE = math.radians(64)  # the wings' front edge, behind the eyes
# The lappets' front, where the wings turn forward: how far across, and its x.
LAP_IN, LAP_OUT, LAP_X = 0.215, 0.37, 0.06
STRIPE = 0.052  # one gold and one lapis stripe
# The body's top below the head, rows of x from -0.5 by 0.05, entries of |y|
# from 0 by 0.05; -1.0 where there is none (head_radius.py --space shoulders).
BODY_TOP = [
    (-0.500, [-0.556, -0.555, -0.553, -0.551, -0.549, -0.548, -0.554, -0.569, -0.585, -0.597, -0.613, -0.624, -0.647]),
    (-0.450, [-0.505, -0.504, -0.502, -0.500, -0.498, -0.497, -0.519, -0.538, -0.567, -0.582, -0.597, -0.609, -0.615]),
    (-0.400, [-0.441, -0.440, -0.448, -0.461, -0.492, -0.491, -0.513, -0.534, -0.563, -0.577, -0.593, -0.606, -0.612]),
    (-0.350, [-0.402, -0.401, -0.405, -0.427, -0.452, -0.475, -0.508, -0.532, -0.557, -0.574, -0.591, -0.603, -0.610]),
    (-0.300, [-0.394, -0.393, -0.394, -0.397, -0.420, -0.455, -0.506, -0.545, -0.564, -0.581, -0.598, -0.612, -0.618]),
    (-0.250, [-2.095, -2.040, -0.407, -0.397, -0.400, -0.449, -0.532, -0.552, -0.585, -0.605, -0.623, -0.635, -0.643]),
    (-0.200, [-1.970, -1.957, -0.526, -0.427, -0.413, -0.448, -0.538, -0.583, -0.627, -0.645, -0.671, -0.691, -0.726]),
    (-0.150, [-1.848, -1.808, -1.745, -0.478, -0.444, -0.452, -0.542, -0.662, -0.707, -0.752, -0.810, -1.000, -1.000]),
    (-0.100, [-1.674, -1.612, -0.552, -0.531, -0.500, -0.483, -0.544, -0.761, -1.351, -1.000, -1.000, -1.000, -1.000]),
    (-0.050, [-0.610, -0.609, -0.561, -0.578, -0.548, -0.523, -0.540, -1.000, -1.000, -1.000, -1.000, -1.000, -1.000]),
    (0.000, [-0.829, -0.817, -0.746, -0.669, -0.623, -0.606, -0.784, -1.000, -1.000, -1.000, -1.000, -1.000, -1.000]),
    (0.050, [-1.000, -0.868, -0.815, -0.723, -0.708, -0.693, -1.000, -1.000, -1.000, -1.000, -1.000, -1.000, -1.000]),
    (0.100, [-1.000, -1.000, -1.000, -1.000, -1.000, -1.000, -1.000, -1.000, -1.000, -1.000, -1.000, -1.000, -1.000]),
]


def body_top(x, y):
    fx = min(max((x - BODY_TOP[0][0]) / 0.05, 0.0), len(BODY_TOP) - 1.001)
    fy = min(max(abs(y) / 0.05, 0.0), len(BODY_TOP[0][1]) - 1.001)
    i, j = int(fx), int(fy)
    a, b = fx - i, fy - j
    row0, row1 = BODY_TOP[i][1], BODY_TOP[i + 1][1]
    return ((row0[j] * (1 - b) + row0[j + 1] * b) * (1 - a) + (row1[j] * (1 - b) + row1[j + 1] * b) * a)


def rest_on_body(p, gap=GAP):
    x, y, z = p
    return (x, y, max(z, body_top(x, y) + gap))


def level(p):
    return p[2] + K * p[0]


def smooth(e):
    e = min(max(e, 0.0), 1.0)
    return e * e * (3 - 2 * e)


def at_level(lv, t, out):
    """The point round the head at angle t, out off its radius, whose level is lv."""
    z = lv - K * 0.1
    for _ in range(4):
        p = common.around_tophat_head(z, t, out)
        z = lv - K * p[0]
    return common.around_tophat_head(z, t, out)


def hanging_floor(z, t, z_hem):
    """The head's widest radius between z and the hem, so cloth hangs outside the ears."""
    r, k = 0.0, z
    while k <= z_hem + 0.02:
        r = max(r, max(common.head_radius(common.HEAD_RADIUS_IN_TOPHAT, max(k, -0.48), t + d) for d in (-0.26, 0.0, 0.26)))
        k += 0.02
    return r + OUT


def hood():
    """From the band's top over the crown, a little full at the temples."""
    # Toward the character's left as i grows, so the faces point out of the head.
    angles = [-2 * math.pi * i / SEGMENTS for i in range(SEGMENTS)]
    hem = [at_level(BAND_HI, t, OUT) for t in angles]
    rings = [hem]
    steps = 7
    for k in range(1, steps):
        a = math.pi / 2 * k / steps
        ring = []
        for t, (x, y, z0) in zip(angles, hem):
            h = z0 + (TOP - z0) * math.sin(a)
            r = math.hypot(x - AX, y) * math.cos(a) * (1 + 0.05 * math.sin(2 * a))
            hx, hy, _ = common.around_tophat_head(h, t, OUT)
            r = max(r, math.hypot(hx - AX, hy)) if h < 0.03 else r
            ring.append((AX + r * math.cos(t), -r * math.sin(t), h))
        rings.append(ring)
    return common.rings_mesh("hood", rings, [CLOTH] * len(rings), cap=(AX - 0.01, 0.0, TOP))


def wing_bottom(d):
    """The level the cloth hangs to, by angle from the face: the lappets lowest,
    the wings behind them on the shoulders, the back gathered at the nape."""
    lap = 1 - smooth((d - math.radians(88)) / math.radians(14))
    nape = smooth((d - math.radians(118)) / math.radians(52))
    return -0.585 - 0.07 * lap + 0.22 * nape


def wings():
    """Round the sides and back from under the hood's hem, flaring toward the
    shoulders; near the face the lower cloth turns to face forward."""
    cols, rows = 26, 9
    verts, faces = [], []
    for j in range(cols + 1):
        t = -T_FACE - (2 * math.pi - 2 * T_FACE) * j / cols
        d = abs(math.remainder(t, 2 * math.pi))
        side = 1.0 if math.sin(-t) > 0 else -1.0  # +1 on the character's left
        top = at_level(BAND_HI + 0.012, t, OUT - 0.005)
        z_hem = top[2]
        r_top = math.hypot(top[0] - AX, top[1])
        r_bot = 0.47 - 0.16 * smooth((d - math.radians(110)) / math.radians(70))
        lv_bot = wing_bottom(d)
        front = 1 - smooth((d - T_FACE) / math.radians(30))
        column = []
        for k in range(rows + 1):
            v = k / rows
            r = r_top + (r_bot - r_top) * v ** 1.15
            lv = BAND_HI + 0.012 + (lv_bot - BAND_HI - 0.012) * v
            z = lv - K * (AX + r * math.cos(t))
            x = AX + r * math.cos(t) - K * (z_hem - z)
            y = -r * math.sin(t)
            turn = front * smooth((v - 0.22) / 0.42)
            if turn > 0:
                fy = side * (LAP_IN + (LAP_OUT - LAP_IN) * (1 - front))
                fx = LAP_X - 0.04 * (1 - front) ** 2 - K * (z_hem - z)
                x, y = x + (fx - x) * turn, y + (fy - y) * turn
            rr = math.hypot(x - AX, y)
            need = hanging_floor(z, t, z_hem)
            if rr < need:
                x, y = AX + (x - AX) * need / rr, y * need / rr
            column.append(rest_on_body((x, y, z)))
        # Bottom first, so the rows run up like the hood's rings and face the same way.
        verts.extend(reversed(column))
    n = rows + 1
    for j in range(cols):
        for k in range(rows):
            a, b = j * n + k, (j + 1) * n + k
            faces.append((a, b, b + 1, a + 1))
    return common.mesh_object("wings", verts, faces, [CLOTH] * len(faces))


def band():
    """Gold across the brow, rounded out at its middle, ending under the wings' front edges."""
    cols = 16
    lift = [(BAND_LO, 0.012), (BAND_LO + 0.02, 0.03), (BAND_HI - 0.016, 0.03), (BAND_HI, 0.014), (BAND_HI + 0.008, 0.002)]
    rings = []
    for lv, out in lift:
        rings.append([at_level(lv, T_FACE - 2 * T_FACE * j / cols, OUT - 0.016 + out) for j in range(cols + 1)])
    verts = [p for ring in rings for p in ring]
    n = cols + 1
    faces = [(r * n + j, r * n + j + 1, (r + 1) * n + j + 1, (r + 1) * n + j) for r in range(len(rings) - 1) for j in range(cols)]
    return common.mesh_object("band", verts, faces, [BAND] * len(faces))


def brow_point(t, lv=BAND_LO + 0.02):
    return Vector(at_level(lv, t, OUT + 0.016))


def cobra(t):
    """Rearing from the band: a hooded neck, a small head, the body coiling back over the hood."""
    base = brow_point(t)
    neck = [base + FWD * f + UPV * u for f, u in ((0.0, 0.0), (0.016, 0.04), (0.022, 0.08), (0.025, 0.12), (0.028, 0.15))]
    parts = [common.tube("cobra_neck", [tuple(p) for p in neck], [0.014, 0.014, 0.013, 0.011, 0.01], 6, GOLD)]
    side = Vector((0.0, 1.0, 0.0))
    parts.append(common.ellipsoid("cobra_hood", tuple(base + FWD * 0.036 + UPV * 0.09), (0.01, 0.038, 0.058),
                                  10, 5, INLAY, (tuple(FWD), tuple(side), tuple(UPV))))
    parts.append(common.ellipsoid("cobra_head", tuple(base + FWD * 0.042 + UPV * 0.153), (0.024, 0.016, 0.013),
                                  8, 4, GOLD, (tuple(FWD), tuple(side), tuple(UPV))))
    coil = [Vector(at_level(lv, t + 0.06 * math.sin(i * 1.7), OUT + 0.006)) for i, lv in enumerate((-0.15, -0.11, -0.07, -0.03, 0.0))]
    coil = [base + UPV * 0.02] + coil
    parts.append(common.tube("cobra_coil", [tuple(p) for p in coil], [0.011, 0.011, 0.01, 0.009, 0.007, 0.005], 6, GOLD))
    return parts


def vulture(t):
    """The vulture's head beside the cobra, on a curved neck, with a hooked beak."""
    base = brow_point(t)
    side = Vector((0.0, 1.0, 0.0))
    neck = [base + FWD * f + UPV * u for f, u in ((0.0, 0.0), (0.02, 0.04), (0.028, 0.075))]
    parts = [common.tube("vulture_neck", [tuple(p) for p in neck], [0.016, 0.014, 0.013], 6, GOLD)]
    head = base + FWD * 0.042 + UPV * 0.095
    parts.append(common.ellipsoid("vulture_head", tuple(head), (0.029, 0.017, 0.02), 8, 4, GOLD,
                                  (tuple(FWD), tuple(side), tuple(UPV))))
    beak = [head + FWD * f + UPV * u for f, u in ((0.02, 0.0), (0.037, -0.003), (0.047, -0.014), (0.048, -0.026))]
    parts.append(common.tube("vulture_beak", [tuple(p) for p in beak], [0.01, 0.007, 0.004, 0.0015], 5, GOLD))
    return parts


def tail():
    """The cloth's gathered end, wrapped, lying down the back of the suit's collar."""
    path, radii = [], []
    for i in range(6):
        f = i / 5
        x = -0.345 - 0.17 * f
        rad = 0.05 - 0.016 * f
        path.append(rest_on_body((x, 0.0, -0.33 - 0.26 * f), rad + 0.008))
        radii.append(rad)
    return [common.tube("tail", path, radii, 8, CLOTH)]


def stripes(name, gold_hex, lapis_hex):
    """Gold and lapis in level bands, a soft edge between them, light grime and grain."""
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

    lv = op("ADD", xyz.outputs["Z"], op("MULTIPLY", xyz.outputs["X"], K))
    wave = op("SINE", op("MULTIPLY", lv, 2 * math.pi / STRIPE))
    fac = op("MULTIPLY", op("ADD", op("MULTIPLY", wave, 6.0), 0.5), 1.0, clamp=True)
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    links.new(fac, mix.inputs["Factor"])
    mix.inputs["A"].default_value = common.srgb(lapis_hex)
    mix.inputs["B"].default_value = common.srgb(gold_hex)
    grime = nodes.new("ShaderNodeTexNoise")
    grime.inputs["Scale"].default_value = 5.0
    grime.inputs["Detail"].default_value = 6.0
    links.new(coord.outputs["Object"], grime.inputs["Vector"])
    dirty = nodes.new("ShaderNodeMix")
    dirty.data_type = "RGBA"
    links.new(op("MULTIPLY", op("SUBTRACT", grime.outputs["Fac"], 0.5, clamp=True), 0.6), dirty.inputs["Factor"])
    links.new(mix.outputs["Result"], dirty.inputs["A"])
    dirty.inputs["B"].default_value = common.srgb("3a2c18")
    links.new(dirty.outputs["Result"], color)
    return mat


def band_material():
    """Gold with a thin red and a thin blue stripe along its middle, by level."""
    mat, nodes, links, color = common.diffuse_material("band")
    coord = nodes.new("ShaderNodeTexCoord")
    xyz = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coord.outputs["Object"], xyz.inputs["Vector"])
    lv = nodes.new("ShaderNodeMath")
    lv.operation = "MULTIPLY_ADD"
    links.new(xyz.outputs["X"], lv.inputs[0])
    lv.inputs[1].default_value = K
    links.new(xyz.outputs["Z"], lv.inputs[2])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    mid = (BAND_LO + BAND_HI) / 2
    span = BAND_HI - BAND_LO
    stops = [(0.0, "b8861e"), (0.40, "a3241c"), (0.48, "b8861e"), (0.52, "0f2470"), (0.60, "b8861e")]
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], common.srgb(stops[0][1])
    els[1].position, els[1].color = stops[1][0], common.srgb(stops[1][1])
    for pos, hex_rgb in stops[2:]:
        e = els.new(pos)
        e.color = common.srgb(hex_rgb)
    scale = nodes.new("ShaderNodeMapRange")
    scale.inputs["From Min"].default_value = mid - span / 2
    scale.inputs["From Max"].default_value = mid + span / 2
    links.new(lv.outputs[0], scale.inputs["Value"])
    links.new(scale.outputs["Result"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], color)
    return mat


def main():
    opts = common.args()
    common.reset()
    parts = [hood(), wings(), band()] + tail() + cobra(-0.1) + vulture(0.11)
    materials = [
        stripes("cloth", "b8861e", "0f2470"),
        common.worn("gold", "c08a24", "6a4a16", grime=0.2, grain=0.05, edge_hex="f4dc8c", edge=0.8),
        band_material(),
        common.worn("inlay", "0f2470", "0e1d4f", grime=0.2, grain=0.05, pattern=("b8861e", 90.0, "VORONOI")),
    ]
    ob = common.assemble(ID, parts, materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID, ao_floor=0.55, ao_distance=0.08))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "tophat", "maska_helmet", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
