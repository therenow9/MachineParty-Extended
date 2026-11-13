"""Builds the More Cosmetics render decision page from an xc_render run.

  python tools/cosmetics/render_page.py --renders <dir> --result <result_xc_render.txt> --out <page.html> --batch "<label>"

The renders are game screenshots: the page goes outside the repo (it refuses
a path inside it) and is published, never committed. It embeds our own item textures and reads each
item's triangle count and size from its .glb, from the mod's items or, for a
candidate, from --candidates. The markup is render_page.html beside this file.
Standard library only.
"""
import argparse
import base64
import json
import math
import os
import re
import struct

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ITEMS = os.path.join(REPO, "mods", "more_cosmetics", "items")
CANDIDATES = os.path.join(os.environ.get("TEMP", ""), "machine-party-tests", "xc_render", "candidates")
ANGLES = {"000": "face", "045": "side", "180": "back", "090": "side"}


def far(renders, item):
    """xc_render's far shots of item, captioned with the character's height."""
    out = []
    for k, v in shots(renders, "far_" + item):
        px, yaw = k.split("px_")
        out.append(["%d px tall, %s" % (int(px), ANGLES.get(yaw, yaw)), v])
    return out


def data_uri(path):
    kind = {"webp": "image/webp", "jpg": "image/jpeg", "png": "image/png"}[path.rsplit(".", 1)[1]]
    with open(path, "rb") as f:
        return "data:%s;base64,%s" % (kind, base64.b64encode(f.read()).decode())


def glb_facts(path):
    """(triangles, [x, y, z] extent in Godot axes) of a .glb."""
    with open(path, "rb") as f:
        blob = f.read()
    length = struct.unpack_from("<I", blob, 12)[0]
    gltf = json.loads(blob[20:20 + length])
    total, lo, hi = 0, [math.inf] * 3, [-math.inf] * 3
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            total += gltf["accessors"][prim["indices"]]["count"] // 3
            pos = gltf["accessors"][prim["attributes"]["POSITION"]]
            lo = [min(a, b) for a, b in zip(lo, pos["min"])]
            hi = [max(a, b) for a, b in zip(hi, pos["max"])]
    return total, [round(b - a, 3) for a, b in zip(lo, hi)]


def item_file(item, ext, candidates):
    path = os.path.join(ITEMS, item + ext)
    return path if os.path.exists(path) else os.path.join(candidates, item + ext)


def shots(renders, prefix):
    """(suffix, data uri) for every render named <prefix>_<suffix>.<ext>, sorted.
    The suffix is xc_render's yaw, gib time, rest shot or far shot's height, so one id's prefix
    never picks up another's (xc_sombrero, xc_sombrero_small)."""
    out = []
    for name in sorted(os.listdir(renders)):
        stem, _ = os.path.splitext(name)
        if stem.startswith(prefix + "_") and re.fullmatch(r"(\d+ms_|rest_|\d{3}px_)?\d{3}", stem[len(prefix) + 1:]):
            out.append((stem[len(prefix) + 1:], data_uri(os.path.join(renders, name))))
    return out


def section(lines, title):
    body, inside = [], False
    for line in lines:
        if line.startswith("=== "):
            inside = line[4:].startswith(title)
            continue
        if inside and line.strip() and not line.startswith(("PASS", "FAIL", "DONE")):
            body.append(line.strip())
    return body


def build(renders, result, batch, candidates):
    with open(result, encoding="utf-8") as f:
        lines = f.read().splitlines()
    stands_in = dict(m.groups() for m in (re.match(r"candidate_item (\S+) (\S+)$", line) for line in lines) if m)
    pairs = []
    for line in lines:
        m = re.match(r"pair (\S+) (\S+)$", line)
        if m:
            ours, ref = m.groups()
            tris, size = glb_facts(item_file(ours, ".glb", candidates))
            pairs.append({
                "ours": ours, "ref": ref, "candidateFor": stands_in.get(ours),
                "tris": tris, "size": size,
                "texture": data_uri(item_file(ours, ".png", candidates)),
                "oursShots": [[ANGLES.get(k, k), v] for k, v in shots(renders, "item_" + ours)],
                "refShots": [[ANGLES.get(k, k), v] for k, v in shots(renders, "item_" + ref)],
                "oursFar": far(renders, ours), "refFar": far(renders, ref),
            })
    # A rework's shipped build, rendered as <id>_before, is shown in its item's
    # card rather than as a candidate to pick.
    before = {p["ours"][:-len("_before")]: p["oursShots"] for p in pairs if p["ours"].endswith("_before")}
    pairs = [dict(p, beforeShots=before.get(p["ours"])) for p in pairs if not p["ours"].endswith("_before")]
    combos = []
    for line in lines:
        m = re.match(r"combo (\S+)\+(\S+)$", line)
        if m:
            combos.append({"hat": m.group(1), "glasses": m.group(2),
                           "shots": [[ANGLES.get(k, k), v] for k, v in shots(renders, "combo_%s+%s" % m.groups())]})
    gibs = []
    for line in lines:
        m = re.match(r"gib (\S+) 1-(\d+) s: lowest point min (-?[\d.]+) vs the floor, below it in (\d+) of (\d+) frames; "
                     r"at \d+ s speed ([\d.]+), spin ([\d.]+)", line)
        if m:
            gid = m.group(1)
            gibs.append({
                "id": gid, "ours": gid.startswith("xc_"), "until": int(m.group(2)),
                "deepest": float(m.group(3)), "below": int(m.group(4)), "frames": int(m.group(5)),
                "speed": float(m.group(6)), "spin": float(m.group(7)),
                "shots": [[k.replace("ms_045", " ms").replace("rest_000", "rest, front").replace("rest_090", "rest, side"), v]
                          for k, v in shots(renders, "gib_" + gid)],
            })
    vanilla = [[line.split()[-1], dict(shots(renders, "suit_" + line.split()[-1])).get("000")]
               for line in lines if line.startswith("suit vanilla ")]
    colors = {}
    for line in lines:
        m = re.match(r"candidate (\S+) (\d) #([0-9a-f]{6})$", line)
        if m:
            cid, k, hexv = m.groups()
            colors.setdefault(cid, []).append({"k": int(k), "hex": hexv,
                                               "src": dict(shots(renders, "suit_%s_%s" % (cid, k))).get("000")})
    return {
        "batch": batch, "pairs": pairs, "combos": combos, "gibs": gibs, "vanilla": vanilla,
        "colors": [{"id": cid, "candidates": c} for cid, c in colors.items()],
        "timing": section(lines, "timing"), "scene": section(lines, "scene change"),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--renders", required=True)
    ap.add_argument("--result", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--batch", required=True, help='shown above the title, e.g. "second art batch"')
    ap.add_argument("--candidates", default=CANDIDATES, help="where xc_render's candidate items are (default: %(default)s)")
    a = ap.parse_args()
    out = os.path.realpath(a.out)
    if os.path.commonpath([out, os.path.realpath(REPO)]) == os.path.realpath(REPO):
        raise SystemExit("--out is inside the repo; the page embeds game screenshots and must stay out of it")
    data = build(a.renders, a.result, a.batch, a.candidates)
    with open(os.path.join(os.path.dirname(__file__), "render_page.html"), encoding="utf-8") as f:
        page = f.read()
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(page.replace("/*%%DATA%%*/null", json.dumps(data)))
    print("wrote", out, "%.1f MB" % (os.path.getsize(out) / 1e6))


main()
