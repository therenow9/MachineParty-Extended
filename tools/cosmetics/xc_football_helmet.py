"""xc_football_helmet: a vintage Ole Miss style football helmet, after the
owner's reference photo: blue with a red stripe down the middle, a white 24 on
each side, a grey two-bar face guard and a white chin strap.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_football_helmet.py [-- --preview DIR]

Built in a frame on the head (f toward the face, s to the side, +s the
character's left, u up the head; the head's up leans forward in the top hat's
space), then placed in the top hat's mesh space. The shell is an egg over the
skull that runs straight down below its equator, measured against xc_recon's
fit guide: the skull spans about f -0.25..0.26, s -0.23..0.23 at the ears, and
peaks at u 0.32. The face opening's top edge sits above the brow (u 0.08 to
0.10) and its sides drop in front of the ears to the jaw, so glasses fit under
it. The number is raised white strokes laid on the shell, read from the side.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_football_helmet"
SHELL, TRIM, GUARD, METAL, HOLE, WHITE = range(6)
AX = common.HEAD_AXIS_X_IN_TOPHAT
U0 = 0.02  # the shell's equator, up the head from the frame's origin
A, B, C = 0.315, 0.285, 0.325
WALL = 0.22  # how far the straight sides run below the equator
CLEAR = 0.014  # the least gap to the head's measured radius
ROWS = 10
# One side's column angles from the face; dense where the opening's edge drops.
HALF = [0, 12, 24, 34, 41, 46, 50, 54, 58, 62, 67, 74, 86, 100, 115, 130, 145, 162]
NUMBER = "24"
# Each digit's strokes in a box from -1 to 1 tall and about as wide, (across, up).
DIGITS = {
    "2": [[(-0.5, 0.55), (-0.3, 0.88), (0.05, 1.0), (0.38, 0.85), (0.5, 0.5), (0.3, 0.1), (-0.5, -0.95)],
          [(-0.55, -0.95), (0.6, -0.95)]],
    "4": [[(0.3, -1.0), (0.3, 1.0)], [(0.3, 1.0), (-0.6, -0.35)], [(-0.6, -0.35), (0.65, -0.35)]],
}
# Where the number sits on the shell: its centre, a digit's half-width (radians
# round the head) and half-height (along the meridian), and the digits' spacing.
NUMBER_PHI, NUMBER_M = math.radians(100), 0.45
DIGIT_W, DIGIT_H, DIGIT_GAP = 0.15, 0.088, 0.37

up = Vector(common.to_blender(*common.UP_IN_TOPHAT)).normalized()
face = Vector(common.to_blender(*common.FACE_IN_TOPHAT))
face = (face - up * face.dot(up)).normalized()
side = up.cross(face)
lo, size = common.HEAD_IN_TOPHAT
origin = Vector(common.to_blender(*[a + b / 2 for a, b in zip(lo, size)]))


def at(f, s, du):
    return origin + face * f + side * s + up * (U0 + du)


def meridian(phi, m):
    """The shell at angle phi and m from the top (0) to the lowest edge (1):
    the dome to the equator over m 0..0.6, then the sides, drawn in a little."""
    if m <= 0.6:
        th = math.pi / 2 * m / 0.6
        du, k = C * math.cos(th), math.sin(th)
    else:
        du = -WALL * (m - 0.6) / 0.4
        k = 1 - 0.15 * (du / 0.2) ** 2
    return clear(at(A * k * math.cos(phi), B * k * math.sin(phi), du))


def smooth(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def edge(phi):
    """Where the shell stops: above the brow at the face, rounding down in
    front of the ears to the jaw, a little higher at the nape."""
    a = math.degrees(abs(math.remainder(phi, 2 * math.pi)))
    brow = 0.6 * math.acos(0.09 / C) / (math.pi / 2)
    low = 0.964 - 0.073 * smooth((a - 100) / 60)
    return brow + (low - brow) * smooth((a - 44) / 22)


def clear(p):
    """p pushed out from the top hat's axis until it clears the head at its height."""
    x, y, h = p
    if h > 0.0:
        return p
    t = math.atan2(-y, x - AX)
    r = math.hypot(x - AX, y)
    hx, hy, _ = common.around_tophat_head(h, t, CLEAR)
    need = math.hypot(hx - AX, hy)
    if r >= need:
        return p
    k = need / r
    return Vector((AX + (x - AX) * k, y * k, h))


def columns():
    return [math.radians(a) for a in [-a for a in reversed(HALF[1:])] + HALF + [180]]


def shell():
    # Toward the character's left as i grows and from the edge up, so the faces point out.
    phis = columns()
    rings = [[tuple(meridian(p, edge(p) * (1 - k / ROWS))) for p in phis] for k in range(ROWS)]
    ob = common.rings_mesh("shell", rings, [SHELL] * ROWS, cap=tuple(at(0, 0, C)))
    return ob, phis


def trims(phis):
    """The edge rolled over: dark trim round the face opening down to the jaw,
    and a lip in the shell's paint round the bottom at the back."""
    def lip(p, out):
        q = meridian(p, edge(p) - 0.012)
        n = (q - at(0, 0, q.dot(up) - origin.dot(up) - U0)).normalized()
        return tuple(q + n * out)
    front = [p for p in phis if abs(p) <= math.radians(74)]
    front.sort()
    back = [p for p in phis if abs(p) >= math.radians(74)]
    back = sorted(back, key=lambda p: p % (2 * math.pi))
    return [common.tube("trim", [lip(p, 0.004) for p in front], 0.013, 6, TRIM, up=tuple(up)),
            common.tube("lip", [lip(p, 0.002) for p in back], 0.009, 5, SHELL, up=tuple(up))]


def bar(f_end, s_end, du_end, reach, du_mid, steps=12):
    """One bar of the guard, from one cheek round the front to the other."""
    pts = []
    for i in range(steps + 1):
        psi = -math.pi / 2 + math.pi * i / steps
        c = math.cos(psi)
        pts.append(tuple(at(f_end + (reach - f_end) * c, s_end * math.sin(psi), du_end + (du_mid - du_end) * c ** 0.7)))
    return pts


def guard():
    """Two bars from snaps low on the cheek pieces: the top one across the
    mouth, the bottom one under the chin, two struts between them."""
    du_end = -0.13
    m = 0.6 + 0.4 * -du_end / WALL
    end = meridian(math.radians(60), m) - origin - up * U0
    f_end, s_end = end.dot(face) + 0.01, end.dot(side) + 0.008
    top = bar(f_end, s_end, du_end, 0.335, -0.17)
    low = bar(f_end, s_end, du_end, 0.275, -0.30)
    parts = [common.tube("bar", top, 0.011, 6, GUARD, up=tuple(up)),
             common.tube("bar", low, 0.011, 6, GUARD, up=tuple(up))]
    for i in (5, 7):
        parts.append(common.tube("strut", [top[i], low[i]], 0.009, 6, GUARD, up=tuple(face)))
    for sgn in (1, -1):
        c = at(f_end, sgn * s_end, du_end)
        parts.append(common.ellipsoid("snap", tuple(c), (0.02, 0.02, 0.012), 8, 4, METAL,
                                      basis=(tuple(face), tuple(up), tuple(side * sgn))))
    # The chin strap, from snap to snap under the chin, and its cup.
    half = [(f_end, s_end, du_end), (f_end - 0.02, 0.85 * s_end, -0.22), (0.13, 0.5 * s_end, -0.31)]
    strap = [at(*p) for p in half] + [at(0.14, 0.0, -0.335)] + [at(f, -s, du) for f, s, du in reversed(half)]
    parts.append(common.tube("strap", [tuple(p) for p in strap], 0.012, 4, WHITE, flat=0.3, up=tuple(face)))
    parts.append(common.ellipsoid("cup", tuple(at(0.145, 0.0, -0.335)), (0.045, 0.03, 0.014), 8, 4, WHITE,
                                  basis=(tuple(side), tuple(face), tuple(up))))
    return parts


def number(sgn):
    """The number on one side, raised off the shell. Read from either side,
    left to right is the way phi grows: toward the back on the left, toward
    the face on the right."""
    centre = meridian(sgn * NUMBER_PHI, NUMBER_M)
    normal = (centre - at(0, 0, 0)).normalized()
    parts = []
    for j, digit in enumerate(NUMBER):
        u0 = (j - (len(NUMBER) - 1) / 2) * DIGIT_GAP
        for stroke in DIGITS[digit]:
            path = []
            for u, v in stroke:
                p = meridian(sgn * NUMBER_PHI + u0 + u * DIGIT_W, NUMBER_M - v * DIGIT_H)
                path.append(tuple(p + (p - at(0, 0, 0)).normalized() * 0.004))
            parts.append(common.tube("digit", path, 0.013, 4, WHITE, flat=0.25, up=tuple(normal)))
    return parts


def stripe(mat):
    """Paints the red stripe over the top, centred on the head, on the shell's paint."""
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == "BSDF_DIFFUSE")
    out = bsdf.inputs["Color"].links[0].from_socket
    coord = nodes.new("ShaderNodeTexCoord")
    sub = nodes.new("ShaderNodeVectorMath")
    sub.operation = "SUBTRACT"
    links.new(coord.outputs["Object"], sub.inputs[0])
    sub.inputs[1].default_value = tuple(origin)
    dot = nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    links.new(sub.outputs["Vector"], dot.inputs[0])
    dot.inputs[1].default_value = tuple(side)
    across = nodes.new("ShaderNodeMath")
    across.operation = "ABSOLUTE"
    links.new(dot.outputs["Value"], across.inputs[0])
    edge = nodes.new("ShaderNodeMapRange")
    edge.inputs["From Min"].default_value = 0.036
    edge.inputs["From Max"].default_value = 0.031
    links.new(across.outputs["Value"], edge.inputs["Value"])
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    links.new(edge.outputs["Result"], mix.inputs["Factor"])
    links.new(out, mix.inputs["A"])
    mix.inputs["B"].default_value = common.srgb("c3302f")
    links.new(mix.outputs["Result"], bsdf.inputs["Color"])
    return mat


def stud(phi, m, radius, mat, flat=0.35):
    """A round piece laid on the shell: a rivet head, or a painted ear hole."""
    p = meridian(phi, m)
    q = meridian(phi, m + 0.02)
    r = meridian(phi + 0.03, m)
    n = (r - p).cross(q - p).normalized()
    if n.dot(p - at(0, 0, 0)) < 0:
        n = -n
    a = (q - p).normalized()
    b = n.cross(a)
    return common.ellipsoid("stud", tuple(p + n * radius * flat * 0.3), (radius, radius, radius * flat), 8, 4, mat,
                            basis=(tuple(a), tuple(b), tuple(n)))


def main():
    opts = common.args()
    common.reset()
    ob, phis = shell()
    parts = [ob] + trims(phis) + guard() + number(1) + number(-1)
    ear = 0.6 + 0.4 * 0.01 / WALL
    for sgn in (1, -1):
        parts.append(stud(sgn * math.radians(95), ear, 0.026, HOLE, 0.12))
    materials = [
        # Glossy blue paint over scuffs and grime, scratched pale where it was hit.
        stripe(common.worn("shell", "234c8f", "0f203f", grime=0.35, grime_scale=4.0, grain=0.06, edge_hex="c9d3e0", edge=0.35, scratches=0.05)),
        common.worn("trim", "2a2c30", "141517", grime=0.4, grime_scale=6.0, grain_scale=300.0, grain=0.25),
        common.worn("guard", "8e9297", "4a4d52", grime=0.4, grime_scale=5.0, grain=0.05),
        common.worn("metal", "9c9a94", "3a3631", grime=0.3, grain=0.05),
        common.worn("hole", "0e0c0c", "1e1b1a", grime=0.2, grain=0.02),
        common.worn("white", "ebe8df", "9a968a", grime=0.3, grain=0.05),
    ]
    ob = common.assemble(ID, parts, materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "tophat", "maska_helmet", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
