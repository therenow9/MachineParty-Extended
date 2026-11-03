"""xc_eyepatch_glasses: a cut leather patch over the left eye on a diagonal strap.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_eyepatch_glasses.py [-- --preview DIR]

Built in Godot axes in the sunglasses' mesh space (up is -x, the face looks
along +y, z is across, +z the character's right) and converted for export. The strap
crosses behind the patch and rides just outside the head's measured radius: low
under the patch-side ear, across the brow above the other eye, and round the
back. It is built on the left, not mirrored, because the head isn't symmetric.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_eyepatch_glasses"
LEATHER, STRAP = 0, 1
# The lens centre of the sunglasses (mid-height, half their half-width across),
# set back from the lens to the face; checked against the fit guide.
EYE = Vector((0.004, 0.012, -0.098))
# The patch's edge, (toward the temple, up) from the eye, before smoothing: flat
# along the brow, widest at the temple, tapering to a rounded point under the eye.
OUTLINE = [(0.092, 0.0), (0.088, 0.046), (0.0, 0.052), (-0.072, 0.040), (-0.070, 0.0), (-0.050, -0.040),
           (0.0, -0.066), (0.060, -0.046)]
EDGE = 24
TILT = math.radians(22)  # the face turns away from the nose at the eye
STRAP_OFFSET = 0.004
STRAP_WIDTH = 0.028
SAMPLES = 36


def g(v):
    return common.to_blender(*v)


def strap_height(t):
    """How far above the eye the strap runs at angle t round the head (0 is the
    face, the patch at t = -0.38): a tilted plane through the patch's centre,
    0.07 above the other eye and 0.05 above it at the back."""
    return 0.0422 - 0.0078 * math.cos(t) + 0.0944 * math.sin(t)


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


def strap_point(t, out=0.0, lift=0.0):
    x = -(strap_height(t) + lift)
    r = common.head_radius(common.HEAD_RADIUS_IN_SUNGLASSES, x, t) + STRAP_OFFSET + out
    return Vector((x, common.HEAD_AXIS_Y + r * math.cos(t), r * math.sin(t)))


def strap():
    rings = []
    for i in range(SAMPLES + 1):
        t = 2 * math.pi * (i % SAMPLES) / SAMPLES
        w = STRAP_WIDTH / 2
        rings.append([g(strap_point(t, o, l)) for o, l in ((0, -w), (0.006, -w), (0.006, w), (0, w))])
    return common.rings_mesh("strap", rings, [STRAP] * SAMPLES)


def patch():
    normal = Vector((0, math.cos(TILT), -math.sin(TILT)))
    up = Vector((-1, 0, 0))
    # Toward the left temple; this basis is left-handed, so the outline runs
    # backwards to keep the faces pointing out.
    across = up.cross(normal)
    profile = [(1.0, -0.004), (1.0, 0.006), (0.85, 0.013), (0.5, 0.017)]
    edge = outline()[::-1]
    rings = [[g(EYE + normal * depth + across * (x * scale) + up * (y * scale)) for x, y in edge] for scale, depth in profile]
    return common.rings_mesh("patch", rings, [LEATHER] * 4, cap=g(EYE + normal * 0.019))


def leather(nodes, links, color, base_hex, scuff_hex, scale):
    coord = nodes.new("ShaderNodeTexCoord")
    grain = nodes.new("ShaderNodeTexVoronoi")
    grain.inputs["Scale"].default_value = scale * 6
    scuffs = nodes.new("ShaderNodeTexNoise")
    scuffs.inputs["Scale"].default_value = scale
    scuffs.inputs["Detail"].default_value = 8.0
    for tex in (grain, scuffs):
        links.new(coord.outputs["Object"], tex.inputs["Vector"])
    edge = nodes.new("ShaderNodeAmbientOcclusion")
    edge.inside = True
    edge.inputs["Distance"].default_value = 0.01
    wear = nodes.new("ShaderNodeMapRange")
    wear.inputs["From Min"].default_value = 0.55
    wear.inputs["From Max"].default_value = 0.8
    links.new(scuffs.outputs["Fac"], wear.inputs["Value"])
    # Thin leather rubs pale where it is thin: the rim and the strap's edges.
    rub = nodes.new("ShaderNodeMath")
    rub.operation = "MAXIMUM"
    links.new(wear.outputs["Result"], rub.inputs[0])
    thin = nodes.new("ShaderNodeMapRange")
    thin.inputs["From Min"].default_value = 0.6
    thin.inputs["From Max"].default_value = 0.2
    thin.inputs["To Max"].default_value = 0.6
    links.new(edge.outputs["AO"], thin.inputs["Value"])
    links.new(thin.outputs["Result"], rub.inputs[1])
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    links.new(rub.outputs[0], mix.inputs["Factor"])
    mix.inputs["A"].default_value = common.srgb(base_hex)
    mix.inputs["B"].default_value = common.srgb(scuff_hex)
    pores = nodes.new("ShaderNodeMix")
    pores.data_type = "RGBA"
    pores.blend_type = "MULTIPLY"
    pore = nodes.new("ShaderNodeMapRange")
    pore.inputs["From Min"].default_value = 0.0
    pore.inputs["From Max"].default_value = 0.25
    pore.inputs["To Min"].default_value = 0.35
    pore.inputs["To Max"].default_value = 0.0
    links.new(grain.outputs["Distance"], pore.inputs["Value"])
    links.new(pore.outputs["Result"], pores.inputs["Factor"])
    links.new(mix.outputs["Result"], pores.inputs["A"])
    pores.inputs["B"].default_value = (0.0, 0.0, 0.0, 1.0)
    links.new(pores.outputs["Result"], color)


def main():
    opts = common.args()
    common.reset()
    parts = [strap(), patch()]
    materials = []
    for name, base, scuff, scale in (("leather", "201b17", "5a4c40", 40.0), ("strap", "2b231d", "5e4d3d", 25.0)):
        mat, nodes, links, color = common.diffuse_material(name)
        leather(nodes, links, color, base, scuff, scale)
        materials.append(mat)
    # Join keeps a face's material only through its object's slots.
    for part in parts:
        for mat in materials:
            part.data.materials.append(mat)
    ob = common.join(parts)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID, ao_floor=0.55, ao_distance=0.05))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "sunglasses", "sunglasses", common.UP_IN_SUNGLASSES, common.FACE_IN_SUNGLASSES)


main()
