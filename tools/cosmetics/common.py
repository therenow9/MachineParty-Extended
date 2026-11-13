"""Shared by the more_cosmetics generators, one script per item id.

Run a generator under Blender (it is not an add-on):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/<id>.py [-- --preview DIR]

An item is modelled in its anchor mesh's local space (mods/more_cosmetics/models.gd
copies the anchor's transforms), and only its .glb geometry and its .png reach the
game: the game draws it with a copy of the anchor's material, so colour, wear and
metal are painted into the texture. --preview writes a contact sheet to DIR; the
fit guides it draws come from xc_recon's headless run and stay in %TEMP%.
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(REPO, "mods", "more_cosmetics", "items")
GUIDES = os.path.join(os.environ.get("TEMP", ""), "machine-party-tests", "xc_recon")
TEXTURE = 512
TRIANGLES = (400, 2000)

# Godot axes, (position, size): the anchor meshes' AABBs from the recon dump,
# and the rest-pose head from xc_recon's "=== fit" section.
TOPHAT = ((-0.502, -0.261, -0.398), (0.996, 0.586, 0.795))
SUNGLASSES = ((-0.070, -0.373, -0.208), (0.150, 0.423, 0.415))
HEAD_IN_TOPHAT = ((-0.315, -0.617, -0.225), (0.567, 0.644, 0.466))
# The head's outermost radius round a vertical axis, one row per height, 24
# angles from the face toward +z; printed by head_radius.py from xc_recon's fit
# guides. In sunglasses space (up is -x) the axis is y = HEAD_AXIS_Y, z = 0, from
# above the brow to the mouth.
HEAD_AXIS_Y = -0.225
HEAD_RADIUS_IN_SUNGLASSES = [
    (-0.150, [0.234, 0.229, 0.217, 0.216, 0.201, 0.188, 0.185, 0.200, 0.225, 0.239, 0.252, 0.256, 0.253, 0.257, 0.253, 0.240, 0.227, 0.201, 0.184, 0.186, 0.195, 0.211, 0.212, 0.226]),
    (-0.125, [0.241, 0.237, 0.222, 0.220, 0.203, 0.194, 0.189, 0.205, 0.225, 0.252, 0.263, 0.270, 0.269, 0.270, 0.264, 0.253, 0.226, 0.206, 0.189, 0.189, 0.197, 0.212, 0.218, 0.232]),
    (-0.100, [0.247, 0.242, 0.229, 0.226, 0.205, 0.194, 0.192, 0.211, 0.224, 0.251, 0.262, 0.269, 0.267, 0.269, 0.262, 0.252, 0.226, 0.212, 0.191, 0.190, 0.198, 0.217, 0.226, 0.240]),
    (-0.075, [0.251, 0.246, 0.237, 0.227, 0.206, 0.194, 0.191, 0.210, 0.228, 0.250, 0.259, 0.266, 0.264, 0.266, 0.260, 0.250, 0.229, 0.210, 0.190, 0.190, 0.201, 0.220, 0.234, 0.243]),
    (-0.050, [0.249, 0.244, 0.239, 0.229, 0.208, 0.194, 0.192, 0.210, 0.225, 0.246, 0.258, 0.263, 0.261, 0.264, 0.258, 0.247, 0.225, 0.210, 0.191, 0.191, 0.203, 0.223, 0.235, 0.240]),
    (-0.025, [0.266, 0.230, 0.232, 0.224, 0.210, 0.195, 0.209, 0.249, 0.237, 0.247, 0.252, 0.257, 0.255, 0.258, 0.253, 0.248, 0.237, 0.250, 0.208, 0.192, 0.206, 0.214, 0.221, 0.221]),
    (0.000, [0.282, 0.237, 0.222, 0.219, 0.210, 0.197, 0.208, 0.251, 0.244, 0.243, 0.244, 0.251, 0.248, 0.251, 0.244, 0.246, 0.244, 0.251, 0.207, 0.195, 0.208, 0.220, 0.224, 0.237]),
    (0.025, [0.298, 0.250, 0.228, 0.223, 0.210, 0.199, 0.212, 0.251, 0.252, 0.239, 0.239, 0.243, 0.241, 0.243, 0.239, 0.239, 0.252, 0.251, 0.212, 0.200, 0.209, 0.222, 0.231, 0.257]),
    (0.050, [0.311, 0.266, 0.235, 0.226, 0.210, 0.203, 0.211, 0.248, 0.253, 0.235, 0.234, 0.238, 0.236, 0.238, 0.234, 0.235, 0.252, 0.248, 0.211, 0.205, 0.211, 0.227, 0.238, 0.274]),
    (0.075, [0.312, 0.274, 0.238, 0.228, 0.213, 0.204, 0.211, 0.245, 0.231, 0.231, 0.230, 0.233, 0.230, 0.233, 0.230, 0.232, 0.237, 0.246, 0.211, 0.205, 0.213, 0.230, 0.240, 0.285]),
    (0.100, [0.269, 0.262, 0.239, 0.228, 0.214, 0.206, 0.210, 0.234, 0.202, 0.226, 0.225, 0.230, 0.228, 0.231, 0.225, 0.226, 0.201, 0.233, 0.210, 0.209, 0.216, 0.230, 0.241, 0.261]),
    (0.125, [0.270, 0.260, 0.240, 0.226, 0.209, 0.203, 0.202, 0.187, 0.197, 0.221, 0.221, 0.228, 0.224, 0.227, 0.221, 0.221, 0.197, 0.186, 0.185, 0.204, 0.211, 0.229, 0.244, 0.266]),
    (0.150, [0.271, 0.262, 0.239, 0.221, 0.204, 0.202, 0.182, 0.185, 0.192, 0.215, 0.215, 0.224, 0.221, 0.224, 0.214, 0.214, 0.192, 0.185, 0.183, 0.198, 0.206, 0.228, 0.244, 0.266]),
]
# In top hat space (up is +y) the axis is x = HEAD_AXIS_X_IN_TOPHAT, z = 0, from
# the jaw to the crown. 0.000 is where the guide has no head (the neck's cut).
HEAD_AXIS_X_IN_TOPHAT = -0.03
HEAD_RADIUS_IN_TOPHAT = [
    (-0.560, [0.163, 0.169, 0.164, 0.151, 0.142, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.096, 0.102, 0.097, 0.109, 0.132, 0.148, 0.165]),
    (-0.520, [0.176, 0.181, 0.172, 0.168, 0.165, 0.164, 0.166, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.146, 0.140, 0.136, 0.138, 0.144, 0.152, 0.160, 0.172]),
    (-0.480, [0.197, 0.199, 0.186, 0.185, 0.181, 0.177, 0.182, 0.191, 0.198, 0.248, 0.000, 0.000, 0.000, 0.000, 0.245, 0.212, 0.172, 0.161, 0.153, 0.152, 0.162, 0.169, 0.176, 0.190]),
    (-0.440, [0.262, 0.254, 0.198, 0.200, 0.192, 0.195, 0.196, 0.203, 0.216, 0.248, 0.272, 0.291, 0.287, 0.277, 0.252, 0.212, 0.186, 0.175, 0.172, 0.173, 0.170, 0.180, 0.189, 0.219]),
    (-0.400, [0.260, 0.247, 0.207, 0.210, 0.205, 0.210, 0.204, 0.207, 0.222, 0.244, 0.266, 0.282, 0.277, 0.269, 0.249, 0.218, 0.200, 0.178, 0.180, 0.187, 0.182, 0.192, 0.198, 0.211]),
    (-0.360, [0.253, 0.236, 0.212, 0.215, 0.211, 0.208, 0.215, 0.220, 0.224, 0.251, 0.263, 0.278, 0.273, 0.266, 0.247, 0.224, 0.197, 0.208, 0.186, 0.186, 0.190, 0.199, 0.203, 0.207]),
    (-0.320, [0.258, 0.255, 0.241, 0.224, 0.217, 0.207, 0.215, 0.240, 0.251, 0.246, 0.259, 0.272, 0.268, 0.268, 0.244, 0.220, 0.236, 0.222, 0.195, 0.186, 0.196, 0.205, 0.223, 0.238]),
    (-0.280, [0.270, 0.268, 0.254, 0.246, 0.220, 0.205, 0.217, 0.252, 0.260, 0.249, 0.249, 0.259, 0.255, 0.252, 0.238, 0.225, 0.247, 0.237, 0.198, 0.184, 0.199, 0.217, 0.243, 0.256]),
    (-0.240, [0.277, 0.274, 0.259, 0.246, 0.223, 0.206, 0.222, 0.260, 0.263, 0.243, 0.241, 0.247, 0.241, 0.241, 0.231, 0.230, 0.235, 0.242, 0.204, 0.188, 0.204, 0.225, 0.246, 0.264]),
    (-0.200, [0.282, 0.279, 0.265, 0.251, 0.225, 0.207, 0.224, 0.251, 0.216, 0.235, 0.233, 0.235, 0.230, 0.228, 0.224, 0.225, 0.203, 0.235, 0.188, 0.190, 0.208, 0.232, 0.255, 0.269]),
    (-0.160, [0.280, 0.278, 0.263, 0.247, 0.226, 0.208, 0.201, 0.209, 0.214, 0.229, 0.223, 0.225, 0.219, 0.221, 0.217, 0.220, 0.201, 0.200, 0.190, 0.193, 0.209, 0.233, 0.254, 0.269]),
    (-0.120, [0.277, 0.276, 0.262, 0.244, 0.220, 0.201, 0.200, 0.206, 0.211, 0.223, 0.217, 0.218, 0.213, 0.214, 0.212, 0.217, 0.204, 0.196, 0.189, 0.188, 0.208, 0.228, 0.254, 0.268]),
    (-0.080, [0.264, 0.260, 0.250, 0.226, 0.206, 0.194, 0.191, 0.198, 0.201, 0.214, 0.206, 0.207, 0.202, 0.206, 0.204, 0.208, 0.194, 0.190, 0.185, 0.180, 0.195, 0.215, 0.243, 0.255]),
    (-0.040, [0.238, 0.239, 0.229, 0.206, 0.185, 0.170, 0.176, 0.178, 0.188, 0.201, 0.195, 0.197, 0.191, 0.193, 0.192, 0.192, 0.179, 0.168, 0.169, 0.162, 0.176, 0.193, 0.221, 0.234]),
    (0.000, [0.190, 0.191, 0.183, 0.160, 0.146, 0.139, 0.140, 0.140, 0.152, 0.160, 0.148, 0.145, 0.142, 0.146, 0.148, 0.145, 0.144, 0.132, 0.133, 0.133, 0.139, 0.146, 0.165, 0.186]),
]
# Unit vectors, Godot axes: the head's up and the way the face looks.
UP_IN_TOPHAT, FACE_IN_TOPHAT = (0.220, 0.975, -0.038), (0.996, -0.092, -0.003)
UP_IN_SUNGLASSES, FACE_IN_SUNGLASSES = (-0.975, -0.222, -0.005), (0.185, 0.983, -0.005)
# For a hat that sits level on the head, in top hat space: the head's radius
# round its own up (UP_IN_TOPHAT), the axis through x = HEAD_AXIS_X_IN_TOPHAT
# moved LEVEL_FORWARD along the face to the head's middle at the hat line; rows
# of heights along the up, 24 angles from the face toward the character's right
# (head_radius.py --space level). Its crown peaks at LEVEL_HEAD_TOP.
LEVEL_FORWARD = 0.07
LEVEL_HEAD_TOP = 0.034
HEAD_RADIUS_LEVEL = [
    (-0.200, [0.252, 0.249, 0.236, 0.227, 0.208, 0.194, 0.191, 0.247, 0.224, 0.246, 0.245, 0.250, 0.248, 0.250, 0.245, 0.247, 0.225, 0.249, 0.191, 0.192, 0.203, 0.221, 0.233, 0.245]),
    (-0.180, [0.252, 0.249, 0.234, 0.227, 0.208, 0.196, 0.192, 0.209, 0.219, 0.247, 0.246, 0.251, 0.249, 0.251, 0.247, 0.248, 0.220, 0.210, 0.192, 0.192, 0.203, 0.219, 0.230, 0.244]),
    (-0.160, [0.251, 0.248, 0.233, 0.227, 0.208, 0.196, 0.192, 0.210, 0.220, 0.248, 0.247, 0.252, 0.250, 0.252, 0.248, 0.249, 0.221, 0.211, 0.192, 0.192, 0.203, 0.219, 0.229, 0.243]),
    (-0.140, [0.250, 0.247, 0.233, 0.231, 0.208, 0.195, 0.193, 0.210, 0.220, 0.249, 0.247, 0.252, 0.250, 0.253, 0.248, 0.250, 0.222, 0.212, 0.193, 0.192, 0.202, 0.222, 0.229, 0.243]),
    (-0.120, [0.246, 0.244, 0.230, 0.228, 0.204, 0.193, 0.190, 0.208, 0.218, 0.237, 0.246, 0.250, 0.248, 0.251, 0.246, 0.247, 0.219, 0.209, 0.190, 0.190, 0.202, 0.222, 0.227, 0.239]),
    (-0.100, [0.240, 0.238, 0.224, 0.222, 0.201, 0.188, 0.185, 0.205, 0.215, 0.234, 0.244, 0.248, 0.246, 0.249, 0.245, 0.236, 0.217, 0.207, 0.188, 0.187, 0.198, 0.217, 0.222, 0.233]),
    (-0.080, [0.234, 0.232, 0.221, 0.220, 0.199, 0.186, 0.182, 0.198, 0.213, 0.232, 0.241, 0.246, 0.244, 0.247, 0.243, 0.234, 0.215, 0.199, 0.183, 0.185, 0.194, 0.212, 0.217, 0.231]),
    (-0.060, [0.231, 0.229, 0.216, 0.214, 0.192, 0.176, 0.172, 0.191, 0.200, 0.218, 0.227, 0.231, 0.229, 0.232, 0.227, 0.228, 0.201, 0.193, 0.175, 0.179, 0.188, 0.207, 0.212, 0.226]),
    (-0.040, [0.217, 0.214, 0.205, 0.200, 0.177, 0.167, 0.164, 0.179, 0.188, 0.206, 0.213, 0.216, 0.215, 0.217, 0.212, 0.214, 0.189, 0.181, 0.165, 0.165, 0.179, 0.199, 0.203, 0.211]),
    (-0.020, [0.207, 0.204, 0.192, 0.187, 0.168, 0.157, 0.154, 0.168, 0.176, 0.198, 0.197, 0.201, 0.200, 0.202, 0.198, 0.200, 0.177, 0.170, 0.156, 0.156, 0.165, 0.185, 0.190, 0.202]),
    (0.000, [0.187, 0.184, 0.173, 0.169, 0.147, 0.137, 0.135, 0.148, 0.152, 0.169, 0.168, 0.171, 0.170, 0.172, 0.169, 0.170, 0.154, 0.150, 0.136, 0.137, 0.146, 0.165, 0.179, 0.182]),
    (0.020, [0.165, 0.162, 0.152, 0.145, 0.126, 0.117, 0.114, 0.124, 0.128, 0.140, 0.139, 0.141, 0.140, 0.142, 0.140, 0.141, 0.129, 0.126, 0.116, 0.117, 0.126, 0.145, 0.151, 0.161]),
]


def to_blender(x, y, z):
    # The glTF exporter turns Blender's Z-up into Y-up: Godot (x, y, z) = Blender (x, z, -y).
    return (x, -z, y)


def args():
    """Every "--key value" after Blender's "--". Any option that changes the build
    (a generator's own, such as --brim or --id) needs --out, which redirects the
    .glb and .png and must be outside the repo: a candidate never lands in mods/
    and ships, and never overwrites the shipped item."""
    global OUT
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"preview": None, "out": None}
    for i in range(0, len(argv) - 1, 2):
        if argv[i].startswith("--"):
            opts[argv[i][2:]] = argv[i + 1]
    if not opts["out"] and set(opts) - {"preview", "out"}:
        raise SystemExit("%s change the build; give --out outside the repo" % ", ".join("--" + k for k in sorted(set(opts) - {"preview", "out"})))
    if opts["out"]:
        out = os.path.realpath(opts["out"])
        if os.path.commonpath([out, os.path.realpath(REPO)]) == os.path.realpath(REPO):
            raise SystemExit("--out is inside the repo; a candidate must stay out of mods/")
        os.makedirs(out, exist_ok=True)
        OUT = out
    return opts


def head_radius(table, h, t):
    """The head's outermost radius at height h and angle t from a HEAD_RADIUS_IN_*
    table, interpolated; heights outside the table clamp to its ends."""
    h = min(max(h, table[0][0]), table[-1][0])
    i = min(len(table) - 2, max(0, next(k for k in range(len(table)) if table[k][0] >= h) - 1))
    kh = (h - table[i][0]) / (table[i + 1][0] - table[i][0])
    n = len(table[0][1])
    f = (t / (2 * math.pi) * n) % n
    # For an angle a hair below zero the modulo rounds up to n itself.
    j, kt = int(f) % n, f - int(f)

    def at(row):
        return row[j] + (row[(j + 1) % n] - row[j]) * kt
    return at(table[i][1]) + (at(table[i + 1][1]) - at(table[i][1])) * kh


def _level_frame():
    up = Vector(UP_IN_TOPHAT).normalized()
    face = Vector(FACE_IN_TOPHAT)
    face = (face - up * face.dot(up)).normalized()
    right = face.cross(up)
    origin = Vector((HEAD_AXIS_X_IN_TOPHAT, 0.0, 0.0)) + face * LEVEL_FORWARD
    return tuple(Vector(to_blender(*v)) for v in (up, face, -right, origin))


LEVEL_UP, LEVEL_FACE, LEVEL_LEFT, _LEVEL_ORIGIN = _level_frame()


def level_point(hat_line, r, phi, c):
    """A Blender point r out from the level axis at angle phi (from the face toward
    the character's left) and c above hat_line along the head's up."""
    return tuple(_LEVEL_ORIGIN + LEVEL_UP * (hat_line + c) + (LEVEL_FACE * math.cos(phi) + LEVEL_LEFT * math.sin(phi)) * r)


def level_head_radius(h, phi):
    """The head's radius at height h along its up and angle phi (toward the left)
    round the level axis, the largest within 15 degrees either side."""
    # The table's angles run toward the right.
    return max(head_radius(HEAD_RADIUS_LEVEL, h, -phi + d) for d in (-0.26, 0.0, 0.26))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def srgb(hex_rgb):
    """A linear colour for shader nodes from an sRGB hex string."""
    c = [int(hex_rgb[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c) + (1.0,)


def rings_mesh(name, rings, materials=None, cap=None):
    """Quad strips between consecutive rings of equally many (x, y, z) points,
    closed around; materials[i] is the material index of strip i. With a cap
    point, the last ring fans to it."""
    n = len(rings[0])
    verts = [p for ring in rings for p in ring]
    faces, mats = [], []
    for r in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            faces.append((r * n + i, r * n + j, (r + 1) * n + j, (r + 1) * n + i))
            mats.append(materials[r] if materials else 0)
    if cap is not None:
        verts.append(tuple(cap))
        c = len(verts) - 1
        base = (len(rings) - 1) * n
        for i in range(n):
            faces.append((base + i, base + (i + 1) % n, c))
            mats.append(materials[-1] if materials else 0)
    return mesh_object(name, verts, faces, mats)


def mesh_object(name, verts, faces, mats=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    if mats:
        me.polygons.foreach_set("material_index", mats)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def join(objects):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


def triangles(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def check_budget(ob, item_id):
    n = triangles(ob)
    if not TRIANGLES[0] <= n <= TRIANGLES[1]:
        raise SystemExit("%s: %d triangles, outside %d..%d" % (item_id, n, *TRIANGLES))
    return n


def diffuse_material(name):
    """A material whose Diffuse BSDF colour is what the bake paints; returns
    (material, nodes, links, colour socket to feed)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfDiffuse")
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat, nodes, links, bsdf.inputs["Color"]


def bake(ob, item_id, ao_floor=0.45, ao_distance=0.15):
    """Unwraps ob, bakes its materials' colour times ambient occlusion into one
    512x512 RGB PNG, then leaves ob with one material showing that texture."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.seed = 0
    if scene.world is None:
        scene.world = bpy.data.worlds.new("world")
    scene.world.light_settings.distance = ao_distance
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    def bake_pass(kind, samples):
        img = bpy.data.images.new("%s_%s" % (item_id, kind.lower()), TEXTURE, TEXTURE, alpha=False)
        for slot in ob.material_slots:
            nodes = slot.material.node_tree.nodes
            node = nodes.new("ShaderNodeTexImage")
            node.image = img
            nodes.active = node
        scene.cycles.samples = samples
        if kind == "DIFFUSE":
            bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=8, margin_type="EXTEND")
        else:
            bpy.ops.object.bake(type="AO", margin=8, margin_type="EXTEND")
        for slot in ob.material_slots:
            nodes = slot.material.node_tree.nodes
            nodes.remove(nodes.active)
        return np.array(img.pixels[:], dtype=np.float32).reshape(TEXTURE, TEXTURE, 4)

    color = bake_pass("DIFFUSE", 4)
    ao = bake_pass("AO", 64)[:, :, :1]
    rgb = color[:, :, :3] * (ao_floor + (1.0 - ao_floor) * ao)
    out = bpy.data.images.new(item_id, TEXTURE, TEXTURE, alpha=False)
    out.pixels.foreach_set(np.dstack([rgb, np.ones((TEXTURE, TEXTURE, 1), np.float32)]).ravel())
    path = os.path.join(OUT, item_id + ".png")
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()

    ob.data.materials.clear()
    mat = bpy.data.materials.new(item_id)
    mat.use_nodes = True
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = out
    tex.interpolation = "Closest"
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    ob.data.materials.append(mat)
    ob.data.polygons.foreach_set("material_index", [0] * len(ob.data.polygons))
    return path


def export(ob, item_id, smooth_angle=35):
    """Triangulated, one surface, normals split at smooth_angle so the facets show."""
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(smooth_angle))
    ob.modifiers.new("tri", "TRIANGULATE")
    path = os.path.join(OUT, item_id + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_materials="NONE", export_yup=True, export_apply=True)
    return path


def preview(ob, item_id, out_dir, space, reference, cam_up, face, size=320):
    """Contact sheet: 4 views around the head's up axis (face, side, back, side)
    of the item alone, the item on the head, and the vanilla reference on the
    head. Guides that aren't in %TEMP% are left out."""
    up = Vector(to_blender(*cam_up)).normalized()
    front = Vector(to_blender(*face))
    front = (front - up * front.dot(up)).normalized()
    side = up.cross(front)

    def guide(name, rgba):
        path = os.path.join(GUIDES, "fit_%s_%s.obj" % (space, name))
        if not os.path.exists(path):
            return None
        bpy.ops.wm.obj_import(filepath=path, forward_axis="Y", up_axis="Z")
        g = bpy.context.selected_objects[0]
        m = bpy.data.materials.new("guide_" + name)
        m.diffuse_color = rgba
        g.data.materials.append(m)
        return g

    head = guide("head", (0.55, 0.45, 0.40, 1.0))
    ref = guide(reference, (0.35, 0.40, 0.55, 1.0))
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_cavity = False
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.view_settings.view_transform = "Standard"
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.type = "ORTHO"

    shown = [o for o in (ob, head, ref) if o is not None]
    pts = [o.matrix_world @ Vector(c) for o in shown for c in o.bound_box]
    center = sum(pts, Vector()) / len(pts)
    cam.data.ortho_scale = max((p - center).length for p in pts) * 2.1
    rows = [[ob], [ob, head], [ref, head]]
    sheet = np.zeros((size * len(rows), size * 4, 4), np.float32)
    for r, row in enumerate(rows):
        for o in shown:
            o.hide_render = o not in row
        for k in range(4):
            a = k * math.pi / 2
            d = (front * math.cos(a) + side * math.sin(a) + up * 0.25).normalized()
            cam.location = center + d * 10
            back = d
            right = up.cross(back).normalized()
            cam.matrix_world = Matrix.Translation(cam.location) @ Matrix((right, back.cross(right), back)).transposed().to_4x4()
            scene.render.filepath = os.path.join(out_dir, "_shot.png")
            bpy.ops.render.render(write_still=True)
            shot = bpy.data.images.load(scene.render.filepath, check_existing=False)
            px = np.array(shot.pixels[:], np.float32).reshape(size, size, 4)
            bpy.data.images.remove(shot)
            y0 = (len(rows) - 1 - r) * size
            sheet[y0:y0 + size, k * size:(k + 1) * size] = px
    os.remove(os.path.join(out_dir, "_shot.png"))
    img = bpy.data.images.new("sheet_" + item_id, size * 4, size * len(rows), alpha=True)
    img.pixels.foreach_set(sheet.ravel())
    img.filepath_raw = os.path.join(out_dir, "%s_preview.png" % item_id)
    img.file_format = "PNG"
    img.save()
    print("preview", img.filepath_raw)


def assemble(name, parts, materials):
    """Joins parts into one object. A face's material_index counts in materials:
    join keeps an index only through its object's slots, so every part gets all."""
    for part in parts:
        for mat in materials:
            part.data.materials.append(mat)
    ob = join(parts)
    ob.name = name
    return ob


def tube(name, path, radius, sides=8, mat=0, closed=False, flat=1.0, up=(0.0, 0.0, 1.0), cap=True):
    """A tube along path (Blender points). radius is a number or one per point;
    flat squashes the section along the side facing up, which makes a ribbon."""
    pts = [Vector(p) for p in path]
    n = len(pts)
    radii = radius if isinstance(radius, (list, tuple)) else [radius] * n
    ref = Vector(up).normalized()
    rings = []
    for i, p in enumerate(pts):
        if closed:
            d = pts[(i + 1) % n] - pts[i - 1]
        else:
            d = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        d.normalize()
        a = ref - d * ref.dot(d)
        if a.length < 1e-6:
            a = d.orthogonal()
        a.normalize()
        b = d.cross(a)
        rings.append([tuple(p + a * (radii[i] * flat * math.cos(2 * math.pi * k / sides))
                            + b * (radii[i] * math.sin(2 * math.pi * k / sides))) for k in range(sides)])
    verts = [v for ring in rings for v in ring]
    faces = []
    for r in range(n if closed else n - 1):
        r2 = (r + 1) % n
        for k in range(sides):
            k2 = (k + 1) % sides
            faces.append((r * sides + k, r * sides + k2, r2 * sides + k2, r2 * sides + k))
    if cap and not closed:
        faces.append(tuple(range(sides))[::-1])
        faces.append(tuple((n - 1) * sides + k for k in range(sides)))
    return mesh_object(name, verts, faces, [mat] * len(faces))


def ellipsoid(name, center, radii, segments=12, rings=6, mat=0, basis=None):
    """A UV ellipsoid; basis is three Blender axes (default x, y, z) that radii follow."""
    ax = [Vector(v).normalized() for v in (basis or ((1, 0, 0), (0, 1, 0), (0, 0, 1)))]
    c = Vector(center)
    verts = [tuple(c - ax[2] * radii[2])]
    for r in range(1, rings):
        phi = math.pi * r / rings
        for s in range(segments):
            th = 2 * math.pi * s / segments
            verts.append(tuple(c + ax[0] * (radii[0] * math.sin(phi) * math.cos(th))
                               + ax[1] * (radii[1] * math.sin(phi) * math.sin(th))
                               - ax[2] * (radii[2] * math.cos(phi))))
    verts.append(tuple(c + ax[2] * radii[2]))
    top = len(verts) - 1
    faces = [(0, 1 + (s + 1) % segments, 1 + s) for s in range(segments)]
    for r in range(rings - 2):
        for s in range(segments):
            a, b = 1 + r * segments + s, 1 + r * segments + (s + 1) % segments
            faces.append((a, b, b + segments, a + segments))
    base = 1 + (rings - 2) * segments
    faces += [(base + s, base + (s + 1) % segments, top) for s in range(segments)]
    return mesh_object(name, verts, faces, [mat] * len(faces))


def around_tophat_head(h, t, out=0.0):
    """A Blender point at height h (Godot y) and angle t (from the face toward
    the character's right) just outside the head in top hat space. The radius
    is the largest within 15 degrees either side, so ears and nose are cleared."""
    r = max(head_radius(HEAD_RADIUS_IN_TOPHAT, h, t + d) for d in (-0.26, 0.0, 0.26)) + out
    return (HEAD_AXIS_X_IN_TOPHAT + r * math.cos(t), -r * math.sin(t), h)


def around_sunglasses_head(x, t, out=0.0):
    """The same in sunglasses space, in Godot axes (x is down, the face +y)."""
    r = max(head_radius(HEAD_RADIUS_IN_SUNGLASSES, x, t + d) for d in (-0.26, 0.0, 0.26)) + out
    return Vector((x, HEAD_AXIS_Y + r * math.cos(t), r * math.sin(t)))


def worn(name, base_hex, dirt_hex, grime=0.35, grime_scale=5.0, grain_scale=120.0, grain=0.15,
         edge_hex=None, edge=0.0, pattern=None, scratches=0.0):
    """A painted, worn surface for the bake: base colour, blotchy dirt, a fine
    grain, and optionally pale or bare edges (edge_hex, by inside AO) and wear
    scattered over the faces too (scratches, also in edge_hex). pattern is
    (hex, scale, kind) for a second colour laid in bands ("WAVE") or cells
    ("VORONOI"), such as embroidery or weave."""
    mat, nodes, links, color = diffuse_material(name)
    coord = nodes.new("ShaderNodeTexCoord")

    def noise(scale, detail):
        n = nodes.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        links.new(coord.outputs["Object"], n.inputs["Vector"])
        return n

    def mix(a, b, fac, blend="MIX"):
        m = nodes.new("ShaderNodeMix")
        m.data_type = "RGBA"
        m.blend_type = blend
        for sock, v in (("A", a), ("B", b), ("Factor", fac)):
            if isinstance(v, (tuple, list)):
                m.inputs[sock].default_value = v
            elif isinstance(v, float):
                m.inputs[sock].default_value = v
            else:
                links.new(v, m.inputs[sock])
        return m.outputs["Result"]

    def ramp(src, lo, hi, scale):
        r = nodes.new("ShaderNodeMapRange")
        r.inputs["From Min"].default_value = lo
        r.inputs["From Max"].default_value = hi
        r.inputs["To Max"].default_value = scale
        links.new(src, r.inputs["Value"])
        return r.outputs["Result"]

    base = srgb(base_hex)
    if pattern:
        phex, pscale, kind = pattern
        if kind == "WAVE":
            p = nodes.new("ShaderNodeTexWave")
            p.inputs["Scale"].default_value = pscale
            p.inputs["Distortion"].default_value = 6.0
            p.inputs["Detail"].default_value = 2.0
            fac = ramp(p.outputs["Fac"], 0.55, 0.62, 1.0)
        else:
            p = nodes.new("ShaderNodeTexVoronoi")
            p.inputs["Scale"].default_value = pscale
            fac = ramp(p.outputs["Distance"], 0.32, 0.24, 1.0)
        links.new(coord.outputs["Object"], p.inputs["Vector"])
        out = mix(base, srgb(phex), fac)
    else:
        out = base
    out = mix(out, srgb(dirt_hex), ramp(noise(grime_scale, 8.0).outputs["Fac"], 0.42, 0.72, grime))
    if edge_hex and edge > 0:
        ao = nodes.new("ShaderNodeAmbientOcclusion")
        ao.inside = True
        ao.inputs["Distance"].default_value = 0.01
        chips = ramp(noise(grime_scale * 6, 4.0).outputs["Fac"], 0.45, 0.6, 1.0)
        thin = ramp(ao.outputs["AO"], 0.6, 0.2, 1.0)
        both = nodes.new("ShaderNodeMath")
        both.operation = "MULTIPLY"
        both.use_clamp = True
        links.new(thin, both.inputs[0])
        links.new(chips, both.inputs[1])
        amount = nodes.new("ShaderNodeMath")
        amount.operation = "MULTIPLY"
        amount.inputs[1].default_value = edge
        links.new(both.outputs[0], amount.inputs[0])
        out = mix(out, srgb(edge_hex), amount.outputs[0])
    if edge_hex and scratches > 0:
        out = mix(out, srgb(edge_hex), ramp(noise(grime_scale * 14, 6.0).outputs["Fac"], 0.6, 0.66, scratches))
    out = mix(out, srgb("4a463f"), ramp(noise(grain_scale, 2.0).outputs["Fac"], 0.0, 1.0, grain), "MULTIPLY")
    links.new(out, color)
    return mat
