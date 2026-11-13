"""xc_snow_glasses: white snow goggles after the owner's photos, a slit for each
eye in one piece across both, in three styles: "band", the Inuit carved bone
band (a narrow band, a notch over the nose, incised lines, a dark cord); "shell",
a moulded white shell (two rounded lobes, an arch over the nose, a wide white
elastic strap with a black buckle); and "mix", halfway between the two.

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/cosmetics/xc_snow_glasses.py [-- --preview DIR] [--style band|shell|mix --white HEX --slit HALF --slit_span K --out DIR]

Built in Godot axes in the sunglasses' mesh space (up is -x, the face looks
along +y, z is across, +z the character's right) and converted for export. The
piece is a ring strip along angle t round the head's vertical axis: at each t its
back stands OFF the head's measured radius over its own height, so it wraps the
face and rides over the nose bridge.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common  # noqa: E402
from mathutils import Vector  # noqa: E402

ID = "xc_snow_glasses"
BODY, SLIT, LINE, STRAP, BUCKLE = range(5)
# The owner's pick: the mix, with the band's brown strap.
STYLE = "mix"
# 0 is the band, 1 the shell.
BLEND = {"band": 0.0, "mix": 0.5, "shell": 1.0}
# The piece's centre line, 0.016 above the eyes' (x -0.016, as the tanning
# goggles' cups): it stands off the brow and cheekbones, and the game's cameras
# look down at it, so on the eyes' own line it reads below them.
EYE_X = -0.032
EYE_T = 0.38
RINGS, SECTION = 37, 10
# Each slit's half height and its length as a share of the band's, picked from
# the local lobby's Polaroids (owner): thinner ones vanish at that size.
SLIT_HALF, SLIT_SPAN = 0.009, 1.2


def lerp(a, b, s):
    return a + (b - a) * s


def g(v):
    return common.to_blender(*v)


class Shape:
    def __init__(self, s):
        self.s = s
        self.end_t = lerp(1.2, 1.12, s)
        self.thick = lerp(0.014, 0.012, s)
        self.off = lerp(0.005, 0.012, s)
        # Squarer in height for the shell's flat front.
        self.square = lerp(0.5, 0.3, s)

    def band_heights(self, t):
        """Narrow, full at the eyes, tapering to the ends, notched over the nose."""
        f = min(1.0, max(0.0, (abs(t) - EYE_T) / (self.end_t - EYE_T)))
        h = 0.038 + (0.024 - 0.038) * f * f
        return h, h - 0.018 * max(0.0, 1 - (t / 0.2) ** 2) ** 1.5

    def shell_heights(self, t):
        """A flat top, a rounded lobe under each eye, an arch over the nose, and
        round ends."""
        f = min(1.0, max(0.0, (abs(t) - (self.end_t - 0.35)) / 0.35))
        rnd = math.sqrt(max(0.0, 1 - f * f))
        up = 0.056 * (0.35 + 0.65 * rnd)
        down = 0.058 * (0.35 + 0.65 * rnd) - 0.062 * max(0.0, 1 - (t / 0.19) ** 2) ** 0.7
        return up, down

    def heights(self, t):
        a, b = self.band_heights(t), self.shell_heights(t)
        return lerp(a[0], b[0], self.s), lerp(a[1], b[1], self.s)

    def radius(self, t):
        """The back: the head's outermost radius over the piece's height at t and
        either side of it, plus off."""
        up, down = self.heights(t)
        r = 0.0
        for dt in (-0.06, -0.03, 0.0, 0.03, 0.06):
            for k in range(5):
                x = EYE_X - up + (up + down) * k / 4
                r = max(r, (common.around_sunglasses_head(x, t + dt) - Vector((x, common.HEAD_AXIS_Y, 0))).length)
        return r + self.off


def point(x, t, r):
    return Vector((x, common.HEAD_AXIS_Y + r * math.cos(t), r * math.sin(t)))


def body(sh):
    ts = [-sh.end_t + 2 * sh.end_t * i / (RINGS - 1) for i in range(RINGS)]
    raw = [sh.radius(t) for t in ts]
    # Smoothed, so the nose's step is a curve.
    rs = [sum(raw[min(len(raw) - 1, max(0, i + d))] for d in (-2, -1, 0, 1, 2)) / 5 for i in range(len(raw))]
    rings = []
    for i, t in enumerate(ts):
        up, down = sh.heights(t)
        end = 1.0 if 0 < i < RINGS - 1 else 0.15
        cx = EYE_X + (down - up) / 2
        hh = (up + down) / 2 * end
        r0 = rs[i] + sh.thick / 2
        ring = []
        for k in range(SECTION):
            a = 2 * math.pi * k / SECTION
            c, s = math.cos(a), math.sin(a)
            v = math.copysign(abs(c) ** sh.square, c) * hh
            w = math.copysign(abs(s) ** 0.8, s) * sh.thick / 2 * end
            ring.append(g(point(cx + v, t, r0 + w)))
        rings.append(ring)
    return common.rings_mesh("body", rings, [BODY] * RINGS), rs, ts


def front(sh, rs, ts, t, x_off=0.0, out=0.0, back=False):
    """A point on the front face (or the back, with back) at angle t, x_off below
    the centre line."""
    i = min(len(ts) - 2, max(0, int((t + sh.end_t) / (2 * sh.end_t) * (len(ts) - 1))))
    k = (t - ts[i]) / (ts[i + 1] - ts[i])
    r = rs[i] + (rs[i + 1] - rs[i]) * k
    up, down = sh.heights(t)
    return point(EYE_X + (down - up) / 2 + x_off, t, (r if back else r + sh.thick) + out)


def slits(sh, rs, ts):
    parts = []
    span = lerp(0.13, 0.17, sh.s) * SLIT_SPAN
    for side in (1, -1):
        pts = [g(front(sh, rs, ts, side * (EYE_T + span * d), 0.002, 0.0005)) for d in (-1, -0.5, 0, 0.5, 1)]
        parts.append(common.tube("slit", pts, SLIT_HALF, 6, SLIT, flat=0.35, up=g(Vector((0, 1, 0)))))
    return parts


def lines(sh, rs, ts):
    """Two shallow arcs per side crossing at each slit, as the carving in the
    photos: from the nose's top to the outer lower edge, and from the nose's foot
    to the outer upper edge."""
    parts = []
    for side in (1, -1):
        for sign in (1, -1):
            pts = []
            for k in range(9):
                f = k / 8
                t = side * (0.1 + (sh.end_t - 0.22) * f)
                up, down = sh.heights(t)
                x_off = sign * (-(up * 0.7) + (up * 0.7 + down * 0.7) * f)
                pts.append(g(front(sh, rs, ts, t, x_off, 0.0003)))
            parts.append(common.tube("line", pts, 0.0016, 4, LINE, flat=0.3, up=g(Vector((0, 1, 0)))))
    return parts


def strap(sh, rs, ts):
    """From one end round the back of the head to the other: a round cord for the
    band, widening to a flat elastic strap for the shell, its flat side on the
    head. Returns it and the point where the shell's buckle sits."""
    a = sh.end_t - 0.04
    width, thick = lerp(0.0035, 0.013, sh.s), lerp(0.0035, 0.003, sh.s)
    rings, along = [], []
    n = 30
    for k in range(n + 1):
        t = a + (2 * math.pi - 2 * a) * k / n
        if k in (0, n):
            p = front(sh, rs, ts, t if k == 0 else -a, 0, 0.0, back=True)
            t = t if k == 0 else -a
        else:
            p = common.around_sunglasses_head(EYE_X, t, lerp(0.006, 0.008, sh.s))
            along.append((t, p))
        out = Vector((0, math.cos(t), math.sin(t)))
        down = Vector((1, 0, 0))
        rings.append([g(p + down * (width * math.cos(2 * math.pi * j / 6)) + out * (thick * math.sin(2 * math.pi * j / 6)))
                      for j in range(6)])
    return common.rings_mesh("strap", rings, [STRAP] * len(rings)), along[4]


def buckle(at):
    t, p = at
    out = Vector((0, math.cos(t), math.sin(t)))
    along = Vector((0, -math.sin(t), math.cos(t)))
    c = p + out * 0.009
    basis = (g(Vector((1, 0, 0))), g(along), g(out))
    return [common.ellipsoid("buckle", g(c), (0.02, 0.03, 0.008), 8, 4, BUCKLE, basis=basis)]


def main():
    global STYLE, SLIT_HALF, SLIT_SPAN
    opts = common.args()
    STYLE = opts.get("style") or STYLE
    SLIT_HALF = float(opts.get("slit") or SLIT_HALF)
    SLIT_SPAN = float(opts.get("slit_span") or SLIT_SPAN)
    if STYLE not in BLEND:
        raise SystemExit("--style is band, shell or mix")
    sh = Shape(BLEND[STYLE])
    common.reset()
    white = opts.get("white") or ("ece9e1" if sh.s < 0.75 else "f2f1ee")
    piece, rs, ts = body(sh)
    band, at = strap(sh, rs, ts)
    parts = [piece, band] + slits(sh, rs, ts)
    if sh.s < 0.75:
        parts += lines(sh, rs, ts)
    else:
        parts += buckle(at)
    strap_mat = (common.worn("strap", "3a2a1e", "1f1711", grime=0.25, grain=0.2, pattern=("4a3726", 260.0, "WAVE")) if sh.s < 0.75
                 else common.worn("strap", "e8e6e0", "a8a59c", grime=0.15, grain=0.1, pattern=("cfccc4", 90.0, "WAVE")))
    materials = [
        # Carved bone, worn smooth and a little yellowed in the hollows; the
        # shell's moulded plastic shows less of it.
        common.worn("body", white, "8f8a7c", grime=lerp(0.18, 0.08, sh.s), grime_scale=7.0, grain=lerp(0.05, 0.02, sh.s),
                    edge_hex="ffffff", edge=0.4, scratches=lerp(0.05, 0.02, sh.s)),
        common.worn("slit", "0b0a0a", "1a1818", grime=0.1, grain=0.02),
        common.worn("line", "8d887c", "6a655a", grime=0.2, grain=0.05),
        strap_mat,
        common.worn("buckle", "141414", "262626", grime=0.1, grain=0.03, edge_hex="3a3a3a", edge=0.3),
    ]
    ob = common.assemble(ID, parts, materials)
    n = common.check_budget(ob, ID)
    print(ID, STYLE, n, "triangles")
    print("wrote", common.bake(ob, ID, ao_floor=0.6, ao_distance=0.04))
    print("wrote", common.export(ob, ID))
    if opts["preview"]:
        common.preview(ob, ID, opts["preview"], "sunglasses", "sunglasses", common.UP_IN_SUNGLASSES, common.FACE_IN_SUNGLASSES)


main()
