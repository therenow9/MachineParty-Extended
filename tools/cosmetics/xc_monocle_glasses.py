"""xc_monocle_glasses: a polished gold monocle on the right eye, its chain hanging loose.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_monocle_glasses.py [-- --preview DIR]

Built in Godot axes in the sunglasses' mesh space (up is -x, the face looks
along +y, z is across, +z the character's right) and converted for export. The
rim sits in the eye socket, turned out with the face like the eyepatch; the
chain leaves its lower outer edge and hangs down the cheek, just off the head's
measured radius. The lens is opaque in the game, so it is painted as glare.
Large, bright and heavy so it reads from across the room.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_monocle_glasses"
BRASS, GLASS, CHAIN = range(3)
# The sunglasses' right lens centre, set back to the face, as the eyepatch's EYE.
EYE = Vector((0.004, 0.012, 0.098))
TILT = math.radians(22)  # the face turns away from the nose at the eye
NORMAL = Vector((0.0, math.cos(TILT), math.sin(TILT)))
UP = Vector((-1.0, 0.0, 0.0))
ACROSS = NORMAL.cross(UP)  # toward the right temple
CENTER = EYE + NORMAL * 0.016
RIM = 0.058
RIM_TUBE = 0.008
LINKS = 15
LINK = 0.014
LINK_WIDTH = 0.0058
WIRE = 0.0026
DROP = 0.21  # how far the chain falls down the cheek
CLIP = 0.008


def g(v):
    return common.to_blender(*v)


def rim_point(a, r=RIM, depth=0.0):
    """On the rim's circle at angle a from the top, turning toward the temple."""
    return CENTER + NORMAL * depth + UP * (r * math.cos(a)) + ACROSS * (r * math.sin(a))


def rim():
    path = [g(rim_point(2 * math.pi * k / 24)) for k in range(24)]
    return common.tube("rim", path, RIM_TUBE, 6, BRASS, closed=True, up=tuple(g(NORMAL)))


def lens():
    """A shallow lens, bulging forward a little, fanned from its centre."""
    n = 24
    ring = [g(rim_point(2 * math.pi * k / n, RIM - 0.002, 0.0)) for k in range(n)]
    verts = ring + [g(CENTER + NORMAL * 0.005)]
    c = len(verts) - 1
    # Fanned this way round the face points out, along NORMAL.
    faces = [(k, (k + 1) % n, c) for k in range(n)]
    return common.mesh_object("lens", verts, faces, [GLASS] * n)


def chain():
    """Links alternately flat and edge-on along a path that drops from the rim's
    lower outer edge and bows out over the cheek."""
    start = rim_point(math.radians(145), RIM + 0.004)
    pts = [start]
    for i in range(1, 40):
        f = i / 39
        x = start.x + DROP * f
        t = math.atan2(start.z, start.y - common.HEAD_AXIS_Y) + 0.22 * f
        p = common.around_sunglasses_head(x, t, 0.014 + 0.012 * math.sin(math.pi * f))
        pts.append(start.lerp(p, min(1.0, f * 6)))
    # Resample to links of equal length.
    out, walked, want = [pts[0]], 0.0, LINK
    for a, b in zip(pts, pts[1:]):
        seg = (b - a).length
        while walked + seg >= want and len(out) <= LINKS:
            out.append(a.lerp(b, (want - walked) / seg))
            want += LINK
        walked += seg
    parts = []
    for i, (a, b) in enumerate(zip(out, out[1:])):
        d = (b - a).normalized()
        side = d.cross(NORMAL if i % 2 == 0 else d.cross(NORMAL)).normalized()
        mid = (a + b) / 2
        loop = [g(mid + d * (LINK * 0.62 * math.cos(2 * math.pi * k / 6)) + side * (LINK_WIDTH * math.sin(2 * math.pi * k / 6)))
                for k in range(6)]
        parts.append(common.tube("link", loop, WIRE, 4, CHAIN, closed=True, up=tuple(g(side.cross(d)))))
    parts.append(common.ellipsoid("clip", tuple(g(out[-1] + (out[-1] - out[-2]).normalized() * 0.008)), (CLIP, CLIP, CLIP), 6, 3, CHAIN))
    return parts


def glass_material():
    """Pale glass under a broad white flash, painted in since nothing in the
    game reflects."""
    mat, nodes, links, color = common.diffuse_material("glass")
    coord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Rotation"].default_value = (0.0, 0.0, math.radians(35))
    mapping.inputs["Scale"].default_value = (9.0, 9.0, 9.0)
    links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    sheen = nodes.new("ShaderNodeTexGradient")
    links.new(mapping.outputs["Vector"], sheen.inputs["Vector"])
    wave = nodes.new("ShaderNodeMath")
    wave.operation = "PINGPONG"
    wave.inputs[1].default_value = 0.5
    links.new(sheen.outputs["Fac"], wave.inputs[0])
    band = nodes.new("ShaderNodeMapRange")
    band.inputs["From Min"].default_value = 0.30
    band.inputs["From Max"].default_value = 0.42
    links.new(wave.outputs[0], band.inputs["Value"])
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    links.new(band.outputs["Result"], mix.inputs["Factor"])
    mix.inputs["A"].default_value = common.srgb("aebcc0")
    mix.inputs["B"].default_value = common.srgb("fbfdfd")
    links.new(mix.outputs["Result"], color)
    return mat


def main():
    opts = common.args()
    common.reset()
    parts = [rim(), lens()] + chain()
    materials = [
        # Polished gold, worn only at the edges, so the ring catches the light.
        common.worn("brass", "c9a046", "6a5222", grime=0.18, grain=0.05, edge_hex="f6e3a0", edge=0.9),
        glass_material(),
        common.worn("chain", "8a6c36", "3a2c16", grime=0.4, grain=0.06, edge_hex="c9a862", edge=0.6),
    ]
    ob = common.assemble(ID, parts, materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID, ao_floor=0.55, ao_distance=0.05))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "sunglasses", "sunglasses", common.UP_IN_SUNGLASSES, common.FACE_IN_SUNGLASSES)


main()
