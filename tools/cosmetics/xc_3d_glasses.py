"""xc_3d_glasses: retro paper 3D glasses after the owner's photo: an off-white
card front with a red lens over the left eye and a cyan one over the right, a
notch for the nose, and flat paper arms hooked behind the ears.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_3d_glasses.py [-- --preview DIR]
  ... -- --out DIR --id <id>   # a review candidate

Built in Godot axes in the sunglasses' mesh space (up is -x, the face looks
along +y, z is across, +z the character's right) and converted for export. The
front is drawn flat, (u across, v up), filled with its two lens holes, sliced
into columns and laid on a shallow curve across the face, pushed out only
where the head's measured surface would cut it. Each lens fills its hole in
the same surface, so nothing overlaps; the card is a single sheet, like paper,
which the game shows from both sides.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bmesh  # noqa: E402
import bpy  # noqa: E402
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_3d_glasses"
PAPER, RED, CYAN = range(3)
EYE_V = 0.016  # the eyes' centre, about 0.02 above the sunglasses' lens centre
LENS_U = 0.098
LENS_HALF = (0.050, 0.030)
LENS_CORNER = 0.012
TOP = EYE_V + 0.050
BOTTOM = EYE_V - 0.045
END = 0.205  # the card's ends, where the arms fold back
END_BOTTOM = EYE_V - 0.021
TAPER = 0.035  # the ends' lower corners cut back over this width
NOTCH, NOTCH_TOP = 0.042, EYE_V - 0.014
FRONT, CURVE = 0.055, 1.4  # the card's front at the middle, and its curve back (y = FRONT - CURVE u^2)
GAP = 0.008
COLUMN = 0.014
ARM_X = -0.045  # above the ears, whose tops are near x -0.035
# Behind the ear, then down it: (x, y, |z|), as the cyclops visor's arms.
EAR = [(ARM_X, -0.36, 0.218), (-0.02, -0.385, 0.212), (0.012, -0.392, 0.2)]


def g(v):
    return common.to_blender(*v)


def bottom(u):
    a = abs(u)
    if a < NOTCH:
        return BOTTOM + (NOTCH_TOP - BOTTOM) * (1 - (a / NOTCH) ** 2) ** 0.6
    if a > END - TAPER:
        return BOTTOM + (END_BOTTOM - BOTTOM) * (a - (END - TAPER)) / TAPER
    return BOTTOM


def head_front(x, z):
    """The y of the head's surface at height x, z across, on the face's side."""
    r = 0.24
    for _ in range(4):
        if abs(z) >= r:
            return None
        r = common.head_radius(common.HEAD_RADIUS_IN_SUNGLASSES, x, math.asin(z / r))
    return common.HEAD_AXIS_Y + math.sqrt(max(0.0, r * r - z * z))


def front_y(u):
    y = FRONT - CURVE * u * u
    lo = bottom(u)
    for k in range(7):
        h = head_front(-(TOP + (lo - TOP) * k / 6), u)
        if h is not None:
            y = max(y, h + GAP)
    return y


def on_front(u, v):
    return Vector((-v, front_y(u), u))


def card_outline():
    pts = [(-END + 0.008, TOP), (END - 0.008, TOP), (END, TOP - 0.008), (END, END_BOTTOM)]
    pts += [(END - TAPER, BOTTOM)]
    pts += [(u, bottom(u)) for u in (NOTCH * (1 - 2 * k / 12) for k in range(13))]
    pts += [(-(END - TAPER), BOTTOM), (-END, END_BOTTOM), (-END, TOP - 0.008)]
    return pts


def lens_outline(side):
    """A rounded rectangle round the eye, anticlockwise from its top right."""
    cu, (hw, hh), rc = side * LENS_U, LENS_HALF, LENS_CORNER
    pts = []
    for corner, (sx, sy) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1))):
        cx, cy = cu + sx * (hw - rc), EYE_V + sy * (hh - rc)
        for k in range(6):
            a = math.pi / 2 * (corner + k / 5)
            pts.append((cx + rc * math.cos(a), cy + rc * math.sin(a)))
    return pts


def sheet(name, loops, mat):
    """loops filled flat (inner loops are holes), sliced into columns COLUMN
    wide and laid on the front."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "2D"
    cu.fill_mode = "BOTH"
    for loop in loops:
        sp = cu.splines.new("POLY")
        sp.points.add(len(loop) - 1)
        for p, (u, v) in zip(sp.points, loop):
            p.co = (u, v, 0.0, 1.0)
        sp.use_cyclic_u = True
    flat = bpy.data.objects.new(name + "_flat", cu)
    bpy.context.scene.collection.objects.link(flat)
    me = bpy.data.meshes.new_from_object(flat.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(flat)
    bm = bmesh.new()
    bm.from_mesh(me)
    n = int(END * 2 / COLUMN)
    for k in range(1, n):
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-7, plane_co=(-END + k * COLUMN, 0.0, 0.0), plane_no=(1.0, 0.0, 0.0))
    for vert in bm.verts:
        vert.co = Vector(g(on_front(vert.co.x, vert.co.y)))
    bm.normal_update()
    # Facing out, along +y in Godot (Blender +z), for the bake's normals.
    if sum(f.normal.z for f in bm.faces) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    me.polygons.foreach_set("material_index", [mat] * len(me.polygons))
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def arm(side):
    """A flat paper strip from the card's end straight back above the ear,
    sampled so any point the head would cut is pushed just outside it, then the
    hook down behind the ear."""
    start = on_front(side * END, -ARM_X) - Vector((0.0, 0.004, 0.0))
    end = Vector((EAR[0][0], EAR[0][1], side * EAR[0][2]))
    path = []
    for i in range(7):
        p = start.lerp(end, i / 6)
        t = math.atan2(p.z, p.y - common.HEAD_AXIS_Y)
        r = math.hypot(p.y - common.HEAD_AXIS_Y, p.z)
        r = max(r, common.head_radius(common.HEAD_RADIUS_IN_SUNGLASSES, p.x, t) + 0.006)
        path.append(Vector((p.x, common.HEAD_AXIS_Y + r * math.cos(t), r * math.sin(t))))
    path += [Vector((x, y, side * z)) for x, y, z in EAR[1:]]
    # Wide at the fold, narrowing toward the ear, as a cut card arm does.
    radii = [0.0026 - 0.0006 * i / (len(path) - 1) for i in range(len(path))]
    return ribbon("arm", path, side, radii, 6, PAPER, 5.0)


def ribbon(name, path, side, radii, sides, mat, flat):
    """common.tube's flattened tube along path (Godot points), its thin side
    always facing out from the head's side, so the strip lies flat round the
    hook; tube's single up turns it edge-on to the head where the path drops."""
    out = Vector((0.0, 0.0, side))
    n = len(path)
    rings = []
    for i, p in enumerate(path):
        d = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
        thin = (out - d * out.dot(d)).normalized()
        wide = thin.cross(d)
        rings.append([g(p + wide * (radii[i] * flat * math.cos(2 * math.pi * k / sides))
                        + thin * (radii[i] * math.sin(2 * math.pi * k / sides))) for k in range(sides)])
    verts = [v for ring in rings for v in ring]
    faces = []
    for r in range(n - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            faces.append((r * sides + k, r * sides + k2, (r + 1) * sides + k2, (r + 1) * sides + k))
    faces.append(tuple(range(sides))[::-1])
    faces.append(tuple((n - 1) * sides + k for k in range(sides)))
    return common.mesh_object(name, verts, faces, [mat] * len(faces))


def main():
    opts = common.args()
    item_id = opts.get("id", ID)
    common.reset()
    card = sheet("card", [card_outline(), lens_outline(-1), lens_outline(1)], PAPER)
    # Red over the left eye (-z), cyan over the right, as the photo and the convention have it.
    parts = [card, sheet("red", [lens_outline(-1)], RED), sheet("cyan", [lens_outline(1)], CYAN), arm(1), arm(-1)]
    materials = [
        common.worn("paper", "dcd7c9", "8c8474", grime=0.35, grime_scale=6.0, grain=0.08),
        common.worn("red", "c4261e", "5e1410", grime=0.2, grime_scale=3.0, grain=0.03, pattern=("e8735f", 6.0, "WAVE")),
        common.worn("cyan", "1aa6b6", "0c4f58", grime=0.2, grime_scale=3.0, grain=0.03, pattern=("86e0ea", 6.0, "WAVE")),
    ]
    ob = common.assemble(item_id, parts, materials)
    n = common.check_budget(ob, item_id)
    print(item_id, n, "triangles")
    print("wrote", common.bake(ob, item_id, ao_floor=0.6, ao_distance=0.05))
    print("wrote", common.export(ob, item_id))
    if opts["preview"]:
        common.preview(ob, item_id, opts["preview"], "sunglasses", "sunglasses", common.UP_IN_SUNGLASSES, common.FACE_IN_SUNGLASSES)


main()
