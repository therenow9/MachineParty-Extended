"""Prints a head-radius table for common.py from xc_recon's fit guides.

  bash tools/run_selftest.sh xc_recon                            # writes the guides to %TEMP%
  python tools/cosmetics/head_radius.py [--space sunglasses|tophat|crown|shoulders|level]  # paste the rows into common.py

For each height and angle, the head's outermost radius round the space's
vertical axis, over points spread across each triangle so a sparse mesh
leaves no gaps. Plain Python, no Blender.
- sunglasses (HEAD_RADIUS_IN_SUNGLASSES): height is x (up is -x), the axis is
  y = AXIS, z = 0, and angles run from the face (+y) toward +z.
- tophat (HEAD_RADIUS_IN_TOPHAT): height is y, the axis is x = AXIS, z = 0, and
  angles run from the face (+x) toward +z.
- crown (xc_party_hat.py's CROWN): tophat's frame round the party hat's
  centre, finer, over the crown above the tophat table's top row.
- shoulders (xc_pharaoh_headdress.py's BODY_TOP): not a radius but the body's
  top in tophat space, the highest point below the head over a grid of x and
  |y| (both sides folded together), -1.0 where the grid misses the body. The
  neck's open top reads low: nothing is meant to rest inside it.
- level (HEAD_RADIUS_LEVEL): tophat's guide in the head's own frame,
  for a hat that sits level on it: height along common.UP_IN_TOPHAT, the axis
  along it through x = -0.03 moved FORWARD along the face (to the head's middle
  at the hat line), and angles from the face toward +z.
"""
import argparse
import math
import os

GUIDES = os.path.join(os.environ.get("TEMP", ""), "machine-party-tests", "xc_recon")
# slab is half the height band each row samples, spread the points per triangle edge.
SPACES = {
    "sunglasses": {"axis": -0.225, "heights": [-0.15 + 0.025 * i for i in range(13)], "angles": 24, "slab": 0.0125, "spread": 6},
    "tophat": {"axis": -0.03, "heights": [-0.56 + 0.04 * i for i in range(15)], "angles": 24, "slab": 0.0125, "spread": 6},
    "crown": {"axis": -0.008, "heights": [-0.02 + 0.005 * i for i in range(9)] + [0.024], "angles": 12, "slab": 0.0025,
              "spread": 14, "guide": "tophat"},
    "shoulders": {"xs": [-0.5 + 0.05 * i for i in range(15)], "ys": [0.05 * j for j in range(13)], "cell": 0.025,
                  "spread": 6, "guide": "tophat", "part": "body"},
    "level": {"axis": -0.03, "heights": [-0.20 + 0.02 * i for i in range(13)], "angles": 24, "slab": 0.01,
              "spread": 6, "guide": "tophat"},
}
UP, FACE = (0.220, 0.975, -0.038), (0.996, -0.092, -0.003)  # common.UP_IN_TOPHAT, FACE_IN_TOPHAT
FORWARD = 0.07


def level_frame():
    """The head's up, its face square to that, and the side toward +z, as unit vectors."""
    def unit(a):
        n = math.sqrt(sum(x * x for x in a))
        return tuple(x / n for x in a)
    u = unit(UP)
    d = sum(a * b for a, b in zip(FACE, u))
    f = unit(tuple(a - d * b for a, b in zip(FACE, u)))
    return u, f, (f[1] * u[2] - f[2] * u[1], f[2] * u[0] - f[0] * u[2], f[0] * u[1] - f[1] * u[0])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--space", choices=sorted(SPACES), default="sunglasses")
    space = ap.parse_args().space
    s = SPACES[space]
    spread, frame = s["spread"], s.get("guide", space)
    guide = os.path.join(GUIDES, "fit_%s_%s.obj" % (frame, s.get("part", "head")))
    if not os.path.exists(guide):
        raise SystemExit("no fit guide at %s; run xc_recon first" % guide)
    with open(guide) as f:
        lines = f.read().splitlines()
    # The guide is in Blender axes (x, -z, y); back to Godot's.
    v = [(bx, bz, -by) for bx, by, bz in (tuple(map(float, l.split()[1:])) for l in lines if l.startswith("v "))]
    faces = [tuple(int(i) - 1 for i in l.split()[1:]) for l in lines if l.startswith("f ")]
    points = list(v)
    for a, b, c in faces:
        for i in range(spread + 1):
            for j in range(spread + 1 - i):
                k = spread - i - j
                points.append(tuple((v[a][d] * i + v[b][d] * j + v[c][d] * k) / spread for d in range(3)))
    if space == "shoulders":
        for x in s["xs"]:
            row = []
            for y in s["ys"]:
                tops = [py for px, py, pz in points if abs(px - x) <= s["cell"] and abs(abs(pz) - y) <= s["cell"]]
                row.append("%.3f" % (max(tops) if tops else -1.0))
            print("    (%.3f, [%s])," % (x, ", ".join(row)))
        return
    axis, heights, angles, slab = s["axis"], s["heights"], s["angles"], s["slab"]
    # (height, forward, across) for each point in this space.
    if space == "level":
        u, f, sd = level_frame()
        q = [(x - axis, y, z) for x, y, z in points]
        hfa = [(sum(a * b for a, b in zip(p, u)), sum(a * b for a, b in zip(p, f)) - FORWARD, sum(a * b for a, b in zip(p, sd)))
               for p in q]
    elif frame == "sunglasses":
        hfa = [(x, y - axis, z) for x, y, z in points]
    else:
        hfa = [(y, x - axis, z) for x, y, z in points]
    for h in heights:
        row = []
        for j in range(angles):
            t = 2 * math.pi * j / angles
            best = 0.0
            for hh, fw, ac in hfa:
                if abs(hh - h) > slab:
                    continue
                if abs((math.atan2(ac, fw) - t + math.pi) % (2 * math.pi) - math.pi) > math.pi / angles:
                    continue
                best = max(best, math.hypot(fw, ac))
            row.append("%.3f" % best)
        print("    (%.3f, [%s])," % (h, ", ".join(row)))


main()
