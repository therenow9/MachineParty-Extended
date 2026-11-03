"""Builds the More Cosmetics online-screen review page from two xc_screen runs.

  python tools/cosmetics/screen_page.py --shots <dir> --out <page.html>

<dir> holds one folder per setup (mp8/, fork/, vanilla/), each with an
xc_screen --windowed run's .webp shots and its result.txt; a missing folder is
left off the page. The grid's tile size and the brightened tiles are read from
online_picker.gd. The shots are game
screenshots: the page goes outside the repo (it refuses a path inside it) and
is published, never committed. The markup is screen_page.html beside this file.
Standard library only.
"""
import argparse
import base64
import json
import os
import re

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SETUPS = {"mp8": "8 Player Support", "fork": "Overtime", "vanilla": "Without Overtime"}
PICKER = os.path.join(REPO, "mods", "more_cosmetics", "online_picker.gd")
SHOTS = ["saved", "built_ours", "built_game"]


def data_uri(path):
    with open(path, "rb") as f:
        return "data:image/webp;base64," + base64.b64encode(f.read()).decode()


def facts(result):
    text = open(result, encoding="utf-8").read()
    win = re.search(r"window size=\((\d+), (\d+)\) content_scale_size=\((\d+), (\d+)\)", text)
    boxes = re.search(r"PASS built_ours: (\d+) boxes, no overlaps", text)
    if not win or not boxes or "DONE fails=0" not in text:
        raise SystemExit("%s: not a clean xc_screen --windowed run" % result)
    w, h, cw, ch = map(int, win.groups())
    tiles = [{"id": m[0], "cover": float(m[1]), "luma": float(m[2]), "dx": float(m[3]), "dy": float(m[4])} for m in
             re.findall(r"tile (\w+) size=\d+x\d+ cover=([\d.]+) luma=([\d.]+) offset=\(([-+\d.]+),([-+\d.]+)\)", text)]
    # The item grid's bounds on the canvas, from the saved screen's tile rects.
    rects = [tuple(map(float, m)) for m in re.findall(
        r'box saved \["rect\d+", \[P: \(([\d.]+), ([\d.]+)\), S: \(([\d.]+), ([\d.]+)\)\]\]', text)]
    grid = [min(r[0] for r in rects), min(r[1] for r in rects),
            max(r[0] + r[2] for r in rects), max(r[1] + r[3] for r in rects)]
    # content_scale_mode 2 (viewport), aspect keep: the canvas scales by the smaller ratio.
    return {"window": [w, h], "canvas": [cw, ch], "scale": min(w / cw, h / ch), "boxes": int(boxes.group(1)), "tiles": tiles,
            "grid": grid}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shots", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    out = os.path.realpath(a.out)
    if os.path.commonpath([out, os.path.realpath(REPO)]) == os.path.realpath(REPO):
        raise SystemExit("--out is inside the repo; the page embeds game screenshots and must stay out of it")
    src = open(PICKER, encoding="utf-8").read()
    grid = {"tile": float(re.search(r"^const TILE := ([\d.]+)$", src, re.M).group(1)),
            "columns": int(re.search(r"^const COLUMNS := (\d+)$", src, re.M).group(1)),
            "lifted": re.findall(r'"(\w+)": [\d.]+', re.search(r"^const TILE_LIFT := \{(.*)\}$", src, re.M).group(1))}
    data = {"grid": grid, "setups": {}}
    for setup, label in SETUPS.items():
        d = os.path.join(a.shots, setup)
        if not os.path.isdir(d):
            continue
        data["setups"][setup] = {"label": label, "facts": facts(os.path.join(d, "result.txt")),
                       "shots": {s: data_uri(os.path.join(d, s + ".webp")) for s in SHOTS}}
        # Each tile's own preview, as xc_screen saved it beside the shots.
        data["setups"][setup]["tiles"] = {t["id"]: data_uri(os.path.join(d, "tile_%s.webp" % t["id"]))
                                          for t in data["setups"][setup]["facts"]["tiles"]}
    with open(os.path.join(os.path.dirname(__file__), "screen_page.html"), encoding="utf-8") as f:
        page = f.read()
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(page.replace("/*%%DATA%%*/null", json.dumps(data)))
    print("wrote", out, "%.1f MB" % (os.path.getsize(out) / 1e6))


main()
