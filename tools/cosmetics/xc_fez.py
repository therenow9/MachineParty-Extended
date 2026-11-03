"""xc_fez: a red felt fez with a gold trim band, and a gold cord from the top
down its side to a tassel hanging below the brim, after the owner's photo.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_fez.py [-- --preview DIR]

Blender axes in the top hat's mesh space: z up the hat, +x the face, -y the
character's right. It sits down on the head but clear of the forehead (the
eyes are near height -0.37, the brow -0.30): the band hugs the head's measured
radius, tipped back a touch, and the felt tapers straight up to a flat top,
about as tall as the base is half wide and the top three quarters of the
base's width. The cord runs from a button in the top's centre over the edge
and down the character's left side, along the felt.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402

ID = "xc_fez"
SEGMENTS = 32
FELT, TOP, GOLD, TRIM = range(4)
AX = common.HEAD_AXIS_X_IN_TOPHAT
OUT = 0.012  # the band's and the felt's least gap to the head
BAND_Z = -0.185  # the bottom edge's height at the sides
# The flat top: its height and radius, centred a little behind the head's axis.
TOP_Z, TOP_R, TOP_X = 0.135, 0.19, AX - 0.015
TRIM_H = 0.024
CORD_T = math.radians(80)  # toward the character's left, a little behind the side


def band(t):
    """The bottom edge: above the brow at the face, lower at the back, so the fez sits tipped back."""
    return BAND_Z + 0.02 * math.cos(t)


def clear(p, t):
    """p pushed out from the axis until it clears the head at its height: the
    forehead slopes back more slowly than the felt tapers."""
    x, y, h = p
    r = math.hypot(x - AX, y)
    hx, hy, _ = common.around_tophat_head(h, t, OUT)
    need = math.hypot(hx - AX, hy)
    if r >= need or h > 0.03:
        return p
    k = need / r
    return (AX + (x - AX) * k, y * k, h)


def lerp(b, c, s, push=0.0):
    """The point s of the way from b to c, pushed out from the top's axis by push."""
    x, y, h = (b[k] + (c[k] - b[k]) * s for k in range(3))
    r = math.hypot(x - TOP_X, y)
    k = (r + push) / r
    return (TOP_X + (x - TOP_X) * k, y * k, h)


def body():
    # Toward the character's left as i grows, so the faces point out of the head.
    angles = [-2 * math.pi * i / SEGMENTS for i in range(SEGMENTS)]
    rings = []
    # The trim turned under, its band standing proud of the felt, then the felt up to the top's edge.
    rings.append([common.around_tophat_head(band(t) + 0.014, t, OUT - 0.008) for t in angles])
    bottom = [common.around_tophat_head(band(t), t, OUT) for t in angles]
    rings.append(bottom)
    top = [(TOP_X + TOP_R * math.cos(t), -TOP_R * math.sin(t), TOP_Z) for t in angles]
    trim = TRIM_H / (TOP_Z - band(0.0))
    rings.append([clear(lerp(b, c, trim), t) for b, c, t in zip(bottom, top, angles)])
    for s in (trim, 0.3, 0.6, 0.9, 1.0):
        rings.append([clear(lerp(b, c, s, -0.005 if s == trim else 0.0), t) for b, c, t in zip(bottom, top, angles)])
    # A slight rolled edge onto the flat top.
    rings.append([(TOP_X + (TOP_R - 0.012) * math.cos(t), -(TOP_R - 0.012) * math.sin(t), TOP_Z + 0.006) for t in angles])
    mats = [TRIM, TRIM, TRIM] + [FELT] * (len(rings) - 5) + [TOP, TOP]
    return common.rings_mesh("fez", rings, mats, cap=(TOP_X, 0.0, TOP_Z + 0.008))


def tassel():
    """The button, the cord over the edge and down the felt, and a tassel that
    hangs below the brim, bound at its head and spreading toward its end."""
    top = TOP_Z + 0.008
    parts = [common.ellipsoid("button", (TOP_X, 0.0, top + 0.004), (0.018, 0.018, 0.01), 10, 4, GOLD)]
    c, s = math.cos(CORD_T), math.sin(CORD_T)
    path = [(TOP_X, 0.0, top + 0.006)]
    for f in (0.4, 0.8):
        path.append((TOP_X + TOP_R * c * f, TOP_R * s * f, top + 0.006))
    path.append((TOP_X + (TOP_R + 0.008) * c, (TOP_R + 0.008) * s, TOP_Z - 0.004))
    # Down the felt, just off it: the cone's radius at each height, plus the cord.
    bx, by, bz = common.around_tophat_head(band(-CORD_T), -CORD_T, OUT)
    base_r = math.hypot(bx - TOP_X, by)
    for f in (0.25, 0.5, 0.75, 1.0):
        r = TOP_R + (base_r - TOP_R) * f + 0.012
        path.append((TOP_X + r * c, r * s, TOP_Z + (bz - TOP_Z) * f))
    end = (path[-1][0], path[-1][1], bz - 0.035)
    path.append(end)
    parts.append(common.tube("cord", path, 0.008, 6, GOLD))
    tuft = [(end[0], end[1], end[2] - 0.12 * k) for k in (0.0, 0.1, 0.18, 0.5, 0.85, 1.0)]
    parts.append(common.tube("tuft", tuft, [0.013, 0.019, 0.015, 0.024, 0.036, 0.03], 10, GOLD))
    return parts


def main():
    opts = common.args()
    common.reset()
    materials = [
        # Pressed wool felt, a deep red gone dusty, darker where the band is handled.
        common.worn("felt", "8f1f1a", "3a1814", grime=0.45, grime_scale=4.0, grain_scale=260.0, grain=0.3, edge_hex="b04a3e", edge=0.4, scratches=0.15),
        common.worn("top", "861c18", "3a1814", grime=0.35, grime_scale=4.0, grain_scale=260.0, grain=0.3, edge_hex="a8463a", edge=0.5),
        common.worn("gold", "c99a32", "5a4220", grime=0.35, grain_scale=300.0, grain=0.35, edge_hex="e8c870", edge=0.5, pattern=("8a6420", 380.0, "WAVE")),
        common.worn("trim", "d0a830", "5a4220", grime=0.3, grain_scale=400.0, grain=0.3, edge_hex="ecd27a", edge=0.4),
    ]
    ob = common.assemble(ID, [body()] + tassel(), materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "tophat", "tophat", common.UP_IN_TOPHAT, common.FACE_IN_TOPHAT)


main()
