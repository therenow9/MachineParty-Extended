"""Prints a head-radius table for common.py from xc_recon's fit guides.

  bash tools/run_selftest.sh xc_recon                            # writes the guides to %TEMP%
  python tools/cosmetics/head_radius.py [--space sunglasses|tophat]  # paste the rows into common.py

For each height and angle, the head's outermost radius round the space's
vertical axis, over points spread across each triangle so a sparse mesh
leaves no gaps. Plain Python, no Blender.
- sunglasses (HEAD_RADIUS_IN_SUNGLASSES): height is x (up is -x), the axis is
  y = AXIS, z = 0, and angles run from the face (+y) toward +z.
- tophat (HEAD_RADIUS_IN_TOPHAT): height is y, the axis is x = AXIS, z = 0, and
  angles run from the face (+x) toward +z.
"""
import argparse
import math
import os

GUIDES = os.path.join(os.environ.get("TEMP", ""), "machine-party-tests", "xc_recon")
SPACES = {
    "sunglasses": {"axis": -0.225, "heights": [-0.15 + 0.025 * i for i in range(13)]},
    "tophat": {"axis": -0.03, "heights": [-0.56 + 0.04 * i for i in range(15)]},
}
ANGLES = 24
SLAB = 0.0125  # half the height band each row samples
SPREAD = 6  # points per triangle edge


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--space", choices=sorted(SPACES), default="sunglasses")
    space = ap.parse_args().space
    axis, heights = SPACES[space]["axis"], SPACES[space]["heights"]
    guide = os.path.join(GUIDES, "fit_%s_head.obj" % space)
    if not os.path.exists(guide):
        raise SystemExit("no fit guide at %s; run xc_recon first" % guide)
    with open(guide) as f:
        lines = f.read().splitlines()
    # The guide is in Blender axes (x, -z, y); back to Godot's.
    v = [(bx, bz, -by) for bx, by, bz in (tuple(map(float, l.split()[1:])) for l in lines if l.startswith("v "))]
    faces = [tuple(int(i) - 1 for i in l.split()[1:]) for l in lines if l.startswith("f ")]
    points = list(v)
    for a, b, c in faces:
        for i in range(SPREAD + 1):
            for j in range(SPREAD + 1 - i):
                k = SPREAD - i - j
                points.append(tuple((v[a][d] * i + v[b][d] * j + v[c][d] * k) / SPREAD for d in range(3)))
    # (height, forward, across) for each point in this space.
    if space == "sunglasses":
        hfa = [(x, y - axis, z) for x, y, z in points]
    else:
        hfa = [(y, x - axis, z) for x, y, z in points]
    for h in heights:
        row = []
        for j in range(ANGLES):
            t = 2 * math.pi * j / ANGLES
            best = 0.0
            for hh, fw, ac in hfa:
                if abs(hh - h) > SLAB:
                    continue
                if abs((math.atan2(ac, fw) - t + math.pi) % (2 * math.pi) - math.pi) > math.pi / ANGLES:
                    continue
                best = max(best, math.hypot(fw, ac))
            row.append("%.3f" % best)
        print("    (%.3f, [%s])," % (h, ", ".join(row)))


main()
