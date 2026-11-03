"""xc_trapper_hat: a red buffalo-check trapper with tan fur, the front folded up
and the ear flaps down, after the owner's reference photo.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_trapper_hat.py [-- --preview DIR]

Blender axes in the top hat's mesh space: z up the hat, +x the face, -y the
character's right. The padded crown stands OUT off the head's measured radius
from just above the brow (the eyes are near y -0.37, the brow -0.30). The flaps
run round the sides and back from under the crown's hem; below the table's
measured head (the sides end near y -0.48) they hang straight down from the
widest point above them.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
import bpy  # noqa: E402

ID = "xc_trapper_hat"
SEGMENTS = 28
PLAID, FUR = range(2)
AX = common.HEAD_AXIS_X_IN_TOPHAT
OUT = 0.022
TOP = 0.058  # the head peaks at y 0.026
PUFF = 0.006  # the padded crown stands this much further out at its hem
# The folded-up front, either side of the face: it stops short of the ears
# (near 90 degrees), whose bulge would push its ends out.
FRONT_SPAN = math.radians(60)
FRONT_H = 0.16  # its height, most of the crown's front
FLAP_FROM = math.radians(62)  # the hanging flaps start here and run round the back


def hem(t):
    return -0.25 + 0.03 * math.cos(t)


def flap_bottom(t):
    """Long, round-bottomed ear flaps; the back cut short between them."""
    off = abs(math.remainder(t, 2 * math.pi)) - math.pi / 2
    return -0.33 - 0.15 * math.exp(-(off / 0.45) ** 2)


def hanging(h, t, out):
    """A point outside the head at height h, never inside any part of the head
    between h and the hem: the flap hangs straight from the widest point above."""
    table = common.HEAD_RADIUS_IN_TOPHAT
    r = 0.0
    k = h
    while k <= hem(t) + 0.02:
        r = max(r, max(common.head_radius(table, max(k, -0.48), t + d) for d in (-0.26, 0.0, 0.26)))
        k += 0.02
    r += out
    return (AX + r * math.cos(t), -r * math.sin(t), h)


def crown():
    """One padded dome from the hem to the top: full at the shoulders, never
    closer to the head than OUT."""
    # Toward the character's left as i grows, so the faces point out of the head.
    angles = [-2 * math.pi * i / SEGMENTS for i in range(SEGMENTS)]
    rings = [[common.around_tophat_head(hem(t) + 0.016, t, OUT - 0.02) for t in angles]]
    steps = 8
    for k in range(steps):
        a = math.pi / 2 * k / steps
        ring = []
        for t in angles:
            x, y, _ = common.around_tophat_head(hem(t), t, OUT + PUFF)
            h = hem(t) + (TOP - hem(t)) * math.sin(a)
            r = math.hypot(x - AX, y) * math.cos(a) * (1 + 0.02 * math.sin(2 * a))
            hx, hy, _ = common.around_tophat_head(h, t, OUT)
            r = max(r, math.hypot(hx - AX, hy)) if h < 0.03 else r
            ring.append((AX + r * math.cos(t), -r * math.sin(t), h))
        rings.append(ring)
    return common.rings_mesh("crown", rings, [PLAID] * len(rings), cap=(AX, 0.0, TOP))


def loft(name, sections, mats_by_edge):
    """Closed sections joined along a path; face (strip, edge) takes
    mats_by_edge[edge]. Normals are made to face out of each closed section."""
    ob = common.rings_mesh(name, sections)
    n = len(sections[0])
    ob.data.polygons.foreach_set("material_index", [mats_by_edge[p.index % n] for p in ob.data.polygons])
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def front_flap():
    """The front, folded up: one thick, lumpy roll of fur round the face,
    rounded in section and tapering to rounded ends."""
    steps, sides = 18, 8
    sections = []
    for j in range(steps + 1):
        f = j / steps * 2 - 1
        t = FRONT_SPAN * f
        e = max(0.15, math.cos(math.pi / 2 * f) ** 0.6)
        half = FRONT_H / 2 * e
        thick = 0.03 * e * (1 + 0.12 * math.sin(j * 2.3))
        mid = hem(t) - 0.01 + half
        sections.append([common.around_tophat_head(mid + half * math.sin(2 * math.pi * k / sides), t,
                                                   OUT + 0.006 + thick * (1 + math.cos(2 * math.pi * k / sides)))
                         for k in range(sides)])
    return [loft("front", sections, [FUR] * sides)]


def side_flaps():
    """Round the sides and back, from under the crown's hem: plaid outside with
    a slight bulge, fur inside, with fur along the bottom and up both front edges."""
    steps = 30
    sections, bottom = [], []
    for j in range(steps + 1):
        t = FLAP_FROM + (2 * math.pi - 2 * FLAP_FROM) * j / steps
        h0, h1 = hem(t) + 0.02, flap_bottom(t)
        sections.append([hanging(h0, t, 0.012), hanging(h1, t, 0.012), hanging(h1 - 0.008, t, 0.023), hanging(h1, t, 0.034),
                         hanging((h0 + h1) / 2, t, 0.042), hanging(h0, t, 0.034)])
        bottom.append(hanging(h1 - 0.002, t, 0.023))
    # Edges: inside (fur), round the bottom (fur), outside (plaid), the top under the hem.
    parts = [loft("flaps", sections, [FUR, FUR, FUR, PLAID, PLAID, PLAID])]
    radii = [0.025 * (1 + 0.22 * math.sin(i * 2.7)) for i in range(len(bottom))]
    parts.append(common.tube("bottom_trim", bottom, radii, 6, FUR))
    for t in (FLAP_FROM, 2 * math.pi - FLAP_FROM):
        edge = [hanging(hem(t) - 0.01 + (flap_bottom(t) - hem(t) + 0.01) * f, t, 0.025) for f in (0.0, 0.33, 0.66, 1.0)]
        parts.append(common.tube("edge_trim", edge, 0.022, 6, FUR))
    return parts


def plaid(name):
    """Buffalo check: red, black where a dark stripe each way crosses, and a
    dark weave where only one does; wool grain and grime over it."""
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

    k = math.pi / 0.065  # one check about 6.5 cm across, a quarter of the head's width
    # Vertical stripes from the plan, so every side shows them; horizontal from the height.
    across = op("GREATER_THAN", op("MULTIPLY", op("SINE", op("MULTIPLY", xyz.outputs["X"], k)), op("SINE", op("MULTIPLY", xyz.outputs["Y"], k))), 0.0)
    down = op("GREATER_THAN", op("SINE", op("MULTIPLY", xyz.outputs["Z"], k)), 0.0)
    dark = op("MULTIPLY", op("ADD", across, down), 0.5)
    check = nodes.new("ShaderNodeMix")
    check.data_type = "RGBA"
    links.new(dark, check.inputs["Factor"])
    check.inputs["A"].default_value = common.srgb("a3241c")
    check.inputs["B"].default_value = common.srgb("161112")
    grime = nodes.new("ShaderNodeTexNoise")
    grime.inputs["Scale"].default_value = 4.0
    grime.inputs["Detail"].default_value = 8.0
    links.new(coord.outputs["Object"], grime.inputs["Vector"])
    dirty = nodes.new("ShaderNodeMix")
    dirty.data_type = "RGBA"
    links.new(op("MULTIPLY", op("SUBTRACT", grime.outputs["Fac"], 0.45, clamp=True), 1.2), dirty.inputs["Factor"])
    links.new(check.outputs["Result"], dirty.inputs["A"])
    dirty.inputs["B"].default_value = common.srgb("2e2420")
    wool = nodes.new("ShaderNodeTexNoise")
    wool.inputs["Scale"].default_value = 300.0
    wool.inputs["Detail"].default_value = 2.0
    links.new(coord.outputs["Object"], wool.inputs["Vector"])
    grain = nodes.new("ShaderNodeMix")
    grain.data_type = "RGBA"
    grain.blend_type = "MULTIPLY"
    links.new(op("MULTIPLY", wool.outputs["Fac"], 0.35), grain.inputs["Factor"])
    links.new(dirty.outputs["Result"], grain.inputs["A"])
    grain.inputs["B"].default_value = common.srgb("4a463f")
    links.new(grain.outputs["Result"], color)
    return mat


def main():
    opts = common.args()
    common.reset()
    parts = [crown()] + front_flap() + side_flaps()
    materials = [
        plaid("plaid"),
        # Rabbit fur, tan with pale tips and darker roots, matted with handling.
        common.worn("fur", "a88c68", "5a4632", grime=0.5, grime_scale=9.0, grain_scale=600.0, grain=0.55, pattern=("cdb594", 140.0, "VORONOI")),
    ]
    ob = common.assemble(ID, parts, materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "tophat", "maska_helmet", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
