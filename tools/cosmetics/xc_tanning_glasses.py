"""xc_tanning_glasses: yellow tanning goggles, two plastic cups with a peep hole
each and a thin bridge, sitting in the eye sockets, and a black elastic cord
round the head.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_tanning_glasses.py [-- --preview DIR]

Built in Godot axes in the sunglasses' mesh space (up is -x, the face looks
along +y, z is across, +z the character's right) and converted for export. Each
cup sits in its eye socket, turned out a little with the face; the cord runs
from a tab on each cup's outer end round the back of the head, just off its
measured radius.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_tanning_glasses"
PLASTIC, HOLE, CORD = range(3)
# The eyes sit about 0.02 above the sunglasses' lens centre (x 0.004, z 0.098)
# in the game's renders; the cups are centred on them, set into the sockets.
EYE_X, EYE_Z, CUP_Y = -0.016, 0.098, 0.006
TILT = math.radians(15)
CUP = (0.041, 0.03, 0.063)  # half height, depth, half width
CORD_X = -0.02


def g(v):
    return common.to_blender(*v)


def axes(side):
    """Down, out of the cup, and across toward the temple, for the cup on side."""
    normal = Vector((0, math.cos(TILT), side * math.sin(TILT)))
    across = Vector((0, -side * math.sin(TILT), math.cos(TILT))) * side
    return Vector((1, 0, 0)), normal, across


def cup(side):
    down, normal, across = axes(side)
    c = Vector((EYE_X, CUP_Y, side * EYE_Z))
    basis = (g(down), g(across), g(normal))
    parts = [common.ellipsoid("cup", g(c), (CUP[0], CUP[2], CUP[1]), 18, 8, PLASTIC, basis=basis)]
    # The peep hole: a dark plug through the cup's front, ringed by a raised lip.
    front = c + normal * CUP[1]
    parts.append(common.tube("hole", [g(front - normal * 0.012), g(front + normal * 0.003)], 0.016, 12, HOLE, up=g(down)))
    lip = [g(front - normal * 0.002 + (down * math.cos(a) + across * math.sin(a)) * 0.019) for a in (2 * math.pi * k / 12 for k in range(12))]
    parts.append(common.tube("lip", lip, 0.0045, 5, PLASTIC, closed=True, up=g(normal)))
    # The tab on the outer end that holds the cord.
    tab = c + across * (CUP[2] + 0.008) - normal * 0.006
    parts.append(common.ellipsoid("tab", g(tab), (0.012, 0.016, 0.005), 8, 4, PLASTIC, basis=basis))
    return parts, tab


def bridge():
    """A thin arch over the nose between the cups' inner ends."""
    pts = []
    for k in range(7):
        f = k / 6 * 2 - 1
        z = f * (EYE_Z - CUP[2] * 0.75)
        pts.append(g(Vector((EYE_X - 0.012 - 0.01 * (1 - f * f), CUP_Y + 0.03 + 0.008 * (1 - f * f), z))))
    return common.tube("bridge", pts, 0.006, 6, PLASTIC, flat=0.6, up=g(Vector((0, 1, 0))))


def cord(tab_right, tab_left):
    """From the right tab back round the head to the left one."""
    start = math.atan2(tab_right.z, tab_right.y - common.HEAD_AXIS_Y)
    end = math.atan2(tab_left.z, tab_left.y - common.HEAD_AXIS_Y) + 2 * math.pi
    pts = [g(tab_right)]
    for k in range(1, 30):
        t = start + (end - start) * k / 30
        pts.append(g(common.around_sunglasses_head(CORD_X, t, 0.006)))
    pts.append(g(tab_left))
    return common.tube("cord", pts, 0.004, 4, CORD)


def main():
    opts = common.args()
    common.reset()
    right, tab_r = cup(1)
    left, tab_l = cup(-1)
    parts = right + left + [bridge(), cord(tab_r, tab_l)]
    materials = [
        # Yellow moulded plastic, scuffed and a little cloudy with use.
        common.worn("plastic", "e0b01e", "6a5412", grime=0.25, grime_scale=6.0, grain=0.06, edge_hex="f6dc72", edge=0.6, scratches=0.15),
        common.worn("hole", "0c0b0b", "1c1a1a", grime=0.2, grain=0.02),
        common.worn("cord", "141313", "2e2b29", grime=0.2, grain=0.15, pattern=("26231f", 260.0, "WAVE")),
    ]
    ob = common.assemble(ID, parts, materials)
    n = common.check_budget(ob, ID)
    print(ID, n, "triangles")
    print("wrote", common.bake(ob, ID, ao_floor=0.55, ao_distance=0.05))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "sunglasses", "sunglasses", common.UP_IN_SUNGLASSES, common.FACE_IN_SUNGLASSES)


main()
