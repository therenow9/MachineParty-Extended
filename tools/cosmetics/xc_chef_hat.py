"""xc_chef_hat: a pleated cotton toque, stained and greyed with kitchen wear.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_chef_hat.py [-- --preview DIR]

Blender axes in the top hat's mesh space: z up the hat, +x the face. The band
sits where the top hat's crown meets its brim, on the head's widest ring.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402

ID = "xc_chef_hat"
SEGMENTS = 36
CENTER = (-0.01, 0.0)
# (z, half-width along x, half-width along y, pleat depth, material): band, fold, body, puff.
PROFILE = [
    (-0.225, 0.292, 0.268, 0.0, 0),
    (-0.150, 0.294, 0.270, 0.0, 0),
    (-0.085, 0.297, 0.273, 0.0, 0),
    (-0.080, 0.306, 0.282, 0.015, 1),
    (0.000, 0.312, 0.288, 0.035, 1),
    (0.080, 0.322, 0.298, 0.045, 1),
    (0.140, 0.338, 0.314, 0.050, 1),
    (0.190, 0.372, 0.346, 0.050, 1),
    (0.225, 0.394, 0.368, 0.045, 1),
    (0.258, 0.388, 0.362, 0.040, 1),
    (0.285, 0.352, 0.328, 0.030, 1),
    (0.305, 0.282, 0.262, 0.022, 1),
    (0.318, 0.175, 0.162, 0.012, 1),
]
# No higher than the top hat's crown (0.325), the tallest vanilla hat it replaces.
TOP_DIP = 0.312


def ring(z, ax, ay, pleat):
    pts = []
    for i in range(SEGMENTS):
        t = 2 * math.pi * i / SEGMENTS
        # Every third vertex is a seam pulled in; the cloth between puffs out unevenly.
        k = 1 - pleat if i % 3 == 0 else 1 + pleat * 0.35 * (1 + math.sin(5 * t + z * 11))
        pts.append((CENTER[0] + ax * k * math.cos(t), CENTER[1] + ay * k * math.sin(t), z))
    return pts


def cloth(name, base_hex, dirt_hex, band):
    mat, nodes, links, color = common.diffuse_material(name)
    coord = nodes.new("ShaderNodeTexCoord")
    weave = nodes.new("ShaderNodeTexNoise")
    weave.inputs["Scale"].default_value = 180.0
    weave.inputs["Detail"].default_value = 2.0
    grime = nodes.new("ShaderNodeTexNoise")
    grime.inputs["Scale"].default_value = 5.0
    grime.inputs["Detail"].default_value = 8.0
    stains = nodes.new("ShaderNodeTexNoise")
    stains.inputs["Scale"].default_value = 3.5
    stains.inputs["Detail"].default_value = 6.0
    for tex in (weave, grime, stains):
        links.new(coord.outputs["Object"], tex.inputs["Vector"])
    grime_ramp = nodes.new("ShaderNodeValToRGB")
    grime_ramp.color_ramp.elements[0].position = 0.42
    grime_ramp.color_ramp.elements[1].position = 0.70
    links.new(grime.outputs["Fac"], grime_ramp.inputs["Fac"])
    stain_ramp = nodes.new("ShaderNodeValToRGB")
    stain_ramp.color_ramp.elements[0].position = 0.64
    stain_ramp.color_ramp.elements[1].position = 0.70
    links.new(stains.outputs["Fac"], stain_ramp.inputs["Fac"])
    # Dirt rises from the band: sweat and handling.
    height = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coord.outputs["Object"], height.inputs["Vector"])
    low = nodes.new("ShaderNodeMapRange")
    low.inputs["From Min"].default_value = -0.23 if band else -0.08
    low.inputs["From Max"].default_value = -0.05 if band else 0.25
    low.inputs["To Min"].default_value = 0.75 if band else 0.45
    low.inputs["To Max"].default_value = 0.25 if band else 0.0
    links.new(height.outputs["Z"], low.inputs["Value"])

    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["A"].default_value = common.srgb(base_hex)
    mix.inputs["B"].default_value = common.srgb(dirt_hex)
    dirt = nodes.new("ShaderNodeMath")
    dirt.operation = "MAXIMUM"
    grime_amount = nodes.new("ShaderNodeMath")
    grime_amount.operation = "MULTIPLY"
    grime_amount.inputs[1].default_value = 0.35
    links.new(grime_ramp.outputs["Color"], grime_amount.inputs[0])
    links.new(grime_amount.outputs[0], dirt.inputs[0])
    links.new(low.outputs["Result"], dirt.inputs[1])
    links.new(dirt.outputs[0], mix.inputs["Factor"])

    stain_mix = nodes.new("ShaderNodeMix")
    stain_mix.data_type = "RGBA"
    stain_amount = nodes.new("ShaderNodeMath")
    stain_amount.operation = "MULTIPLY"
    stain_amount.inputs[1].default_value = 0.45
    links.new(stain_ramp.outputs["Color"], stain_amount.inputs[0])
    links.new(stain_amount.outputs[0], stain_mix.inputs["Factor"])
    links.new(mix.outputs["Result"], stain_mix.inputs["A"])
    stain_mix.inputs["B"].default_value = common.srgb("8a7550")

    fibre = nodes.new("ShaderNodeMix")
    fibre.data_type = "RGBA"
    fibre.blend_type = "MULTIPLY"
    fibre_amount = nodes.new("ShaderNodeMapRange")
    fibre_amount.inputs["To Min"].default_value = 0.0
    fibre_amount.inputs["To Max"].default_value = 0.16
    links.new(weave.outputs["Fac"], fibre_amount.inputs["Value"])
    links.new(fibre_amount.outputs["Result"], fibre.inputs["Factor"])
    links.new(stain_mix.outputs["Result"], fibre.inputs["A"])
    fibre.inputs["B"].default_value = common.srgb("6b665c")
    links.new(fibre.outputs["Result"], color)
    return mat


def main():
    opts = common.args()
    common.reset()
    rings = [ring(z, ax, ay, p) for z, ax, ay, p, _ in PROFILE]
    ob = common.rings_mesh(ID, rings, [m for *_, m in PROFILE[:-1]] + [1], cap=(*CENTER, TOP_DIP))
    ob.data.materials.append(cloth("band", "cfc9b8", "6e6352", True))
    ob.data.materials.append(cloth("puff", "dedacd", "7d7462", False))
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "tophat", "tophat", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
