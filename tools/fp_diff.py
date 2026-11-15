"""Compare two cl_playtest fingerprints (MP_LAUNCH "...;fp=1"): a run on Extended against one on the game alone
at the same seat count. Prints each FP key as same or different, with both values when they differ.

    python tools/fp_diff.py <extended result.txt> <game result.txt> [--allow key ...]

The inputs are cl_playtest's result files (FP lines). Exit 0 when every key not allowed matches, 1 otherwise.
`character_spots` depends on the spawn shuffle: it passes when every Extended spot is one the game's run could
have drawn, i.e. the two runs' spots lie on the same markers (checked against the game's `markers`).
"""
import json
import sys


def read(path):
    out = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            at = line.find("FP ")
            if at < 0:
                continue
            key, _, value = line[at + 3:].partition(" ")
            try:
                out[key] = json.loads(value)
            except json.JSONDecodeError:
                out[key] = value
    return out


def spots_ok(ext, game):
    # Each spot is "[x, y, z, yaw]" as JSON text. The spawn shuffle picks which markers; compare positions only.
    def pos(s):
        v = json.loads(s)
        return tuple(v[:3])
    allowed = {pos(s) for s in game.get("character_spots", [])}
    for spots in game.get("markers", {}).values():
        allowed |= {tuple(json.loads(s)) for s in spots}
    return all(pos(s) in allowed for s in ext.get("character_spots", []))


def main(argv):
    allow = set()
    if "--allow" in argv:
        i = argv.index("--allow")
        allow = set(argv[i + 1:])
        argv = argv[:i]
    if len(argv) != 2:
        print(__doc__)
        return 2
    ext, game = read(argv[0]), read(argv[1])
    if not ext or not game:
        print("no FP lines in %s" % (argv[0] if not ext else argv[1]))
        return 2
    bad = 0
    for key in sorted(set(ext) | set(game)):
        a, b = ext.get(key, "<missing>"), game.get(key, "<missing>")
        if key == "character_spots":
            same = a == b or spots_ok(ext, game)
        else:
            same = a == b
        tag = "same" if same else ("allowed" if key in allow else "DIFF")
        print("%-8s %s" % (tag, key))
        if not same:
            print("    extended: %s" % json.dumps(a))
            print("    game:     %s" % json.dumps(b))
            if key not in allow:
                bad += 1
    print("keys differing: %d" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
