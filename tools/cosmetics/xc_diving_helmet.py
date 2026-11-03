"""xc_diving_helmet: an old copper diving bonnet with brass fittings, gone green,
after the owner's reference photo of a Mark V.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_diving_helmet.py [-- --preview DIR]

It rides the hat bone like every hat, so it stops at a neck flange above the
shoulders: a breastplate would cut through them whenever the head turns. Built
in a frame on the head (f toward the face, s to the side, +s the character's
left, u up the head), then placed in the top hat's mesh space. The glass is
painted, since the material the game gives it is opaque.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_diving_helmet"
COPPER, BRASS, GLASS, BAND = range(4)
SEGMENTS = 24
# The shell is an ellipsoid down to the jaw; its half-axes clear the head by
# about 4%, measured against xc_recon's fit guide.
A, B, C = 0.345, 0.300, 0.370
# (u, radius along f) below the ellipsoid: skirt, then the flange.
SKIRT = [(-0.200, 0.325), (-0.270, 0.310), (-0.320, 0.295), (-0.335, 0.315), (-0.360, 0.335), (-0.385, 0.335), (-0.385, 0.290)]
SKIRT_MATERIALS = [COPPER, COPPER, BRASS, BRASS, BRASS, BRASS]

up = Vector(common.to_blender(*common.UP_IN_TOPHAT)).normalized()
face = Vector(common.to_blender(*common.FACE_IN_TOPHAT))
face = (face - up * face.dot(up)).normalized()
side = up.cross(face)
lo, size = common.HEAD_IN_TOPHAT
origin = Vector(common.to_blender(*[a + b / 2 for a, b in zip(lo, size)])) + face * 0.02


def at(f, s, u):
    return tuple(origin + face * f + side * s + up * u)


def frame(d):
    """Two unit vectors perpendicular to d (f, s, u)."""
    d = Vector(d).normalized()
    e1 = d.cross(Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))).normalized()
    return d, e1, d.cross(e1)


def angles(n):
    return [2 * math.pi * i / n for i in range(n)]


def surface(w, d):
    """How far along d from the offset w the ray leaves the shell's ellipsoid."""
    m = Vector((1 / A ** 2, 1 / B ** 2, 1 / C ** 2))
    a = sum(d[i] * d[i] * m[i] for i in range(3))
    b = 2 * sum(w[i] * d[i] * m[i] for i in range(3))
    c = sum(w[i] * w[i] * m[i] for i in range(3)) - 1
    return (-b + math.sqrt(max(0.0, b * b - 4 * a * c))) / (2 * a)


def shell():
    rings = []
    steps = [0.365, 0.34, 0.30, 0.245, 0.17, 0.09, 0.0, -0.10]
    for u in steps:
        k = math.sqrt(max(0.0, 1 - (u / C) ** 2))
        rings.append([at(A * k * math.cos(t), B * k * math.sin(t), u) for t in angles(SEGMENTS)])
    for u, r in SKIRT:
        rings.append([at(r * math.cos(t), r * B / A * math.sin(t), u) for t in angles(SEGMENTS)])
    rings.reverse()
    mats = list(reversed(SKIRT_MATERIALS)) + [COPPER] * (len(steps) - 1) + [COPPER]
    return common.rings_mesh("shell", rings, mats, cap=at(0, 0, C))


def fitting(name, direction, profile, segments, mats):
    """A round fitting standing out of the shell along direction. profile is
    (distance past the shell's centre-line hit, radius) per ring; its first ring
    starts just inside the shell wherever it curves away, so a wide fitting is
    seated rather than floating. mats has one entry per ring, the last for the cap."""
    d, e1, e2 = frame(direction)
    hit = surface(Vector(), d)
    rings = []
    for k, (along, r) in enumerate(profile):
        ring = []
        for t in angles(segments):
            w = (e1 * math.cos(t) + e2 * math.sin(t)) * r
            a = surface(w, d) - 0.012 if k == 0 else hit + along
            ring.append(at(*(w + d * a)))
        rings.append(ring)
    cap = d * (hit + profile[-1][0])
    return common.rings_mesh(name, rings, mats, cap=at(*cap)), d, e1, e2, hit


def stud(center, direction, radius=0.018, height=0.025):
    d, e1, e2 = frame(direction)
    c = Vector(center)
    rings = [[at(*(c + d * h + (e1 * math.cos(t) + e2 * math.sin(t)) * radius)) for t in angles(6)] for h in (-0.01, height)]
    return common.rings_mesh("stud", rings, [BRASS, BRASS], cap=at(*(c + d * (height + 0.006))))


def rod(a, b, radius, sides, mat, flat=1.0, up_hint=(0, 0, 1)):
    """A tube between two frame points."""
    hint = Vector(at(*up_hint)) - Vector(at(0, 0, 0))
    return common.tube("rod", [at(*a), at(*b)], radius, sides, mat, flat=flat, up=tuple(hint))


def front_port():
    """The faceplate: a deep brass collar, its flat face the engraved band, a
    raised ring round the glass, and bolts round the band."""
    r = 0.15
    profile = [(0.0, r * 1.42), (0.035, r * 1.42), (0.035, r * 1.16), (0.055, r * 1.12), (0.055, r * 0.98), (0.03, r * 0.95)]
    ob, d, e1, e2, hit = fitting("front_port", (1, 0, 0.10), profile, SEGMENTS, [BRASS, BAND, BRASS, BRASS, BRASS, GLASS])
    parts = [ob]
    for k in range(6):
        t = 2 * math.pi * (k + 0.25) / 6
        parts.append(stud(d * (hit + 0.03) + (e1 * math.cos(t) + e2 * math.sin(t)) * r * 1.29, d, 0.014, 0.02))
    return parts


def side_port(s):
    r = 0.1
    profile = [(0.0, r * 1.25), (0.035, r * 1.25), (0.04, r * 1.12), (0.04, r * 0.86), (0.015, r * 0.84)]
    return fitting("side_port", (0.12, s, 0.05), profile, 16, [BRASS, BRASS, BRASS, BRASS, GLASS])[0]


def exhaust_valve():
    """On the character's left, as the photo shows it from the front: the round
    valve body high on the shell, and below it a spindle with a T handle."""
    body, *_ = fitting("valve_body", (0.55, 0.6, 0.55), [(0.0, 0.055), (0.045, 0.055), (0.05, 0.047)], 10, [BRASS, BRASS, BRASS])
    spindle, d, e1, e2, hit = fitting("spindle", (0.85, 1, -0.3), [(0.0, 0.032), (0.05, 0.032), (0.05, 0.012), (0.095, 0.012)], 8, [BRASS] * 4)
    cross = Vector((0, 0, 1)) - d * d.z
    cross.normalize()
    tip = d * (hit + 0.095)
    return [body, spindle, rod(tuple(tip - cross * 0.055), tuple(tip + cross * 0.055), 0.011, 6, BRASS)]


def air_inlet():
    """On the character's right: a squared boss with a wing nut across its end."""
    boss, d, e1, e2, hit = fitting("inlet", (0.85, -1, -0.3), [(0.0, 0.045), (0.05, 0.045), (0.05, 0.016), (0.075, 0.016)], 4, [BRASS] * 4)
    cross = Vector((0, 0, 1)) - d * d.z
    cross.normalize()
    tip = d * (hit + 0.07)
    return [boss, rod(tuple(tip - cross * 0.05), tuple(tip + cross * 0.05), 0.02, 4, BRASS, flat=0.3, up_hint=tuple(d))]


def top_fitting():
    """The fitting on the crown, a little behind the top."""
    ob, *_ = fitting("top", (-0.12, 0, 1), [(0.0, 0.055), (0.03, 0.055), (0.03, 0.04), (0.05, 0.04), (0.055, 0.03)], 8, [BRASS] * 5)
    return ob


def copper(nodes, links, color):
    """Bright worked copper with brown tarnish, under pale verdigris that lies in
    patches, thickest low on the bonnet and in every crevice."""
    coord = nodes.new("ShaderNodeTexCoord")
    ao = nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.08
    mottle = noise(nodes, links, coord, 9.0, 6.0)
    streaks = noise(nodes, links, coord, 3.0, 4.0, stretch=(1.0, 1.0, 6.0))
    patches = noise(nodes, links, coord, 4.5, 8.0)
    base = mix(nodes, links, ramp(nodes, links, mottle, 0.35, 0.75), "7a4a2c", "b57a4c")
    tarnish = mix(nodes, links, ramp(nodes, links, streaks, 0.45, 0.80), None, "3e2a1c", base, 0.6)
    low = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coord.outputs["Object"], low.inputs["Vector"])
    lower = ramp(nodes, links, low.outputs["Z"], -0.05, -0.55)
    patch = mul(nodes, links, ramp(nodes, links, patches, 0.38, 0.56), add(nodes, links, lower, 0.55))
    green = maximum(nodes, links, ramp(nodes, links, ao.outputs["AO"], 0.85, 0.45), patch)
    pale = mix(nodes, links, ramp(nodes, links, mottle, 0.3, 0.7), "2f6a4c", "5f9a78")
    links.new(mix(nodes, links, green, None, None, tarnish, b_socket=pale), color)


def brass(nodes, links, color, band=False):
    """Yellow brass, rubbed bright on the edges, green in the crevices; the band
    carries rows of dark engraved strokes."""
    coord = nodes.new("ShaderNodeTexCoord")
    ao = nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.05
    wear = noise(nodes, links, coord, 14.0, 6.0)
    base = mix(nodes, links, ramp(nodes, links, wear, 0.30, 0.75), "5e4a22", "a08646")
    out = mix(nodes, links, ramp(nodes, links, ao.outputs["AO"], 0.9, 0.5), None, "5e7f6a", base, 0.85)
    # The neck ring has gone green like the bonnet's lower half.
    low = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coord.outputs["Object"], low.inputs["Vector"])
    patch = mul(nodes, links, ramp(nodes, links, noise(nodes, links, coord, 4.5, 8.0), 0.40, 0.60), add(nodes, links, ramp(nodes, links, low.outputs["Z"], -0.3, -0.6), 0.25))
    out = mix(nodes, links, patch, None, "4f8a68", out)
    if band:
        strokes = nodes.new("ShaderNodeTexWave")
        strokes.wave_type = "RINGS"
        strokes.inputs["Scale"].default_value = 28.0
        strokes.inputs["Distortion"].default_value = 9.0
        strokes.inputs["Detail"].default_value = 3.0
        links.new(coord.outputs["Object"], strokes.inputs["Vector"])
        out = mix(nodes, links, ramp(nodes, links, strokes.outputs["Fac"], 0.62, 0.7), None, "2e2616", out, 0.8)
    links.new(out, color)


def glass(nodes, links, color):
    """Dark glass with a diagonal sheen painted in, since nothing reflects."""
    coord = nodes.new("ShaderNodeTexCoord")
    sheen = nodes.new("ShaderNodeTexGradient")
    sheen.gradient_type = "LINEAR"
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Rotation"].default_value = (0.0, 0.0, math.radians(35))
    mapping.inputs["Scale"].default_value = (9.0, 9.0, 9.0)
    links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], sheen.inputs["Vector"])
    wave = nodes.new("ShaderNodeMath")
    wave.operation = "PINGPONG"
    wave.inputs[1].default_value = 0.5
    links.new(sheen.outputs["Fac"], wave.inputs[0])
    links.new(mix(nodes, links, ramp(nodes, links, wave.outputs[0], 0.38, 0.5), "121a19", "5a6862"), color)


def noise(nodes, links, coord, scale, detail, stretch=None):
    n = nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    if stretch:
        m = nodes.new("ShaderNodeMapping")
        m.inputs["Scale"].default_value = stretch
        links.new(coord.outputs["Object"], m.inputs["Vector"])
        links.new(m.outputs["Vector"], n.inputs["Vector"])
    else:
        links.new(coord.outputs["Object"], n.inputs["Vector"])
    return n.outputs["Fac"]


def ramp(nodes, links, fac, a, b):
    """fac remapped so a -> 0 and b -> 1, clamped."""
    m = nodes.new("ShaderNodeMapRange")
    m.inputs["From Min"].default_value = a
    m.inputs["From Max"].default_value = b
    links.new(fac, m.inputs["Value"])
    return m.outputs["Result"]


def math_node(nodes, links, op, a, b):
    m = nodes.new("ShaderNodeMath")
    m.operation = op
    m.use_clamp = True
    for i, v in enumerate((a, b)):
        if isinstance(v, float):
            m.inputs[i].default_value = v
        else:
            links.new(v, m.inputs[i])
    return m.outputs[0]


def mul(nodes, links, a, b):
    return math_node(nodes, links, "MULTIPLY", a, b)


def add(nodes, links, a, b):
    return math_node(nodes, links, "ADD", a, b)


def maximum(nodes, links, a, b):
    return math_node(nodes, links, "MAXIMUM", a, b)


def mix(nodes, links, fac, a_hex, b_hex, a_socket=None, amount=1.0, b_socket=None):
    m = nodes.new("ShaderNodeMix")
    m.data_type = "RGBA"
    if amount != 1.0:
        fac = mul(nodes, links, fac, amount)
    links.new(fac, m.inputs["Factor"])
    if a_socket is not None:
        links.new(a_socket, m.inputs["A"])
    else:
        m.inputs["A"].default_value = common.srgb(a_hex)
    if b_socket is not None:
        links.new(b_socket, m.inputs["B"])
    else:
        m.inputs["B"].default_value = common.srgb(b_hex)
    return m.outputs["Result"]


def main():
    opts = common.args()
    common.reset()
    parts = [shell()] + front_port() + [side_port(1), side_port(-1), top_fitting()] + exhaust_valve() + air_inlet()
    for k in range(6):
        t = 2 * math.pi * (k + 0.5) / 6
        parts.append(stud(Vector((0.335 * math.cos(t), 0.335 * B / A * math.sin(t), -0.37)), (0, 0, -1), 0.022, 0.026))
    materials = []
    for name, build in (("copper", copper), ("brass", brass), ("glass", glass), ("band", lambda n, l, c: brass(n, l, c, band=True))):
        mat, nodes, links, color = common.diffuse_material(name)
        build(nodes, links, color)
        materials.append(mat)
    ob = common.assemble(ID, parts, materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID, ao_floor=0.5))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "tophat", "maska_helmet", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
