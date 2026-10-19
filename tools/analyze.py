#!/usr/bin/env python3
"""Turns the movement suite's traces into a report.

    tools/analyze.py runs/                 report.md and report.json in runs/
    tools/analyze.py runs/ --baseline b.json   also marks regressions
    tools/analyze.py --list                the scene:script specs to run

A run is one scene and one script. Its trace has one `t<n>` line per
physics tick (see gecko.gd _print_trace) and one `F<frame> x y tick`
line per drawn frame. Each metric below turns the ticks into events
(tick, value); a run passes when every scored metric has no events and
the scene's expected outcome holds. Thresholds are at the top; they are
calibrated so the flat floor produces nothing.
"""
import argparse
import json
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENES = os.path.join(ROOT, "tests", "scenes.json")

# Thresholds
WALK_STEP = 130.0 / 60.0   # px per tick at walk speed
DRAW_JUMP = 4.0            # drawn body centre, px per tick while clinging (walk is 2.2; a corner sweep reaches 3.5)
BODY_JUMP = 3.5            # physics centre (informational)
HEAD_JUMP = 6.0            # px per tick of the head in the body's frame (a corner wrap swings it by design)
UP_FLIP = 0.35             # rad in one tick outside a committed grab
UP_OSC_MIN = 0.035         # rad, an up increment that counts for oscillation
UP_OSC_N = 4               # alternations within UP_OSC_WIN ticks
UP_OSC_WIN = 30
DANCE_WIN = 10             # ticks
DANCE_N = 2                # sign changes of along-surface motion under a held input
DANCE_MIN = 0.3            # px per tick that counts as motion
FLICK_WIN = 10             # ticks: two state changes inside this is a flicker
STALL_WIN = 30             # ticks of held input along the surface with no rock ahead ...
STALL_PX = 15.0            # ... and less progress than this
FOOT_TOGGLE_WIN = 8        # ticks: a step is 6 ticks of lift, so three toggles inside 8 is a flicker
FOOT_TOGGLE_N = 3          # planted toggles inside the window
FOOT_SLIDE = 2.0           # px a planted foot may move per tick
FOOT_JUMP = 12.0           # px per tick for a foot that is not stepping
SINK_D = 8.5               # nearest rock closer than this = body inside rock
FLOAT_D = 24.0             # nearest rock farther than this while clinging = floating
SINK_TICKS = 10
TURN_GRACE = 20            # ticks after a facing flip: the head swings round by design
LAND_GRACE = 4             # ticks after landing: feet re-seat, body settles
SPAWN_GRACE = 12           # first ticks: the gecko settles onto its spawn

SCORED = ["draw_jump", "head_jump", "dance", "up_flip", "up_osc", "state_flicker", "stall",
          "foot_toggle", "foot_slide", "foot_jump", "sink", "float"]
INFO = ["body_jump", "stuck"]


def vec(s):
    a, b = s.split(",")
    return (float(a), float(b))


def parse(path):
    """The trace's ticks. A tick number that does not follow the last one
    means two processes wrote the file (or a line was cut): the run is
    marked corrupt rather than scored."""
    ticks = []
    parse.corrupt = 0
    with open(path) as f:
        for line in f:
            if not line.startswith("t"):
                continue
            parts = line.split()
            try:
                n = int(parts[0][1:])
            except ValueError:
                continue
            d = {}
            for kv in parts[1:]:
                k, _, v = kv.partition("=")
                d[k] = v
            if "pos" not in d or "feet" not in d:
                parse.corrupt += 1
                continue
            if ticks and n != ticks[-1]["tick"] + 1:
                parse.corrupt += 1
            feet = []
            for ft in d.get("feet", "").split(";"):
                if not ft:
                    continue
                x, y, p, s = ft.split(",")
                feet.append({"pos": (float(x), float(y)), "planted": p == "1", "stepping": s == "1"})
            ticks.append({
                "tick": n, "pos": vec(d["pos"]), "draw": vec(d["draw"]), "head": vec(d["head"]),
                "up": vec(d["up"]), "dist": float(d["dist"]), "spd": float(d["spd"]), "state": d["state"],
                "facing": int(d["facing"]), "inp": vec(d["inp"]), "s": float(d["s"]),
                "blk": d["blk"] == "1", "grab": d["grab"] == "1", "bridge": d["bridge"] == "1",
                "sq": d["sq"] == "1", "chew": d["chew"] == "1", "jump": d["jump"] == "1",
                "n": vec(d["n"]), "feet": feet,
            })
    return ticks


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def angle_between(a, b):
    return math.atan2(a[0] * b[1] - a[1] * b[0], a[0] * b[0] + a[1] * b[1])


def tangent(up):
    return (-up[1], up[0])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def head_rel(tk):
    """The head in the body's frame: along the surface, and out from it."""
    d = (tk["head"][0] - tk["pos"][0], tk["head"][1] - tk["pos"][1])
    return (dot(d, tangent(tk["up"])), dot(d, tk["up"]))


def grace_sets(ticks):
    """Ticks to skip per reason: after a facing flip, after landing, after a jump, at spawn."""
    turn, land, jumped = set(), set(), set()
    for i in range(1, len(ticks)):
        if ticks[i]["facing"] != ticks[i - 1]["facing"]:
            turn.update(range(i, min(len(ticks), i + TURN_GRACE)))
        if ticks[i]["state"] == "cling" and ticks[i - 1]["state"] != "cling":
            land.update(range(i, min(len(ticks), i + LAND_GRACE)))
        if ticks[i]["jump"]:
            jumped.update(range(i, min(len(ticks), i + 3)))
    spawn = set(range(0, min(len(ticks), SPAWN_GRACE)))
    return turn, land, jumped, spawn


def metrics(ticks):
    ev = {k: [] for k in SCORED + INFO}
    if len(ticks) < 2:
        return ev
    turn, land, jumped, spawn = grace_sets(ticks)
    for i in range(1, len(ticks)):
        a, b = ticks[i - 1], ticks[i]
        t = b["tick"]
        both_cling = a["state"] == "cling" and b["state"] == "cling"
        skip = i in land or i in jumped or i in spawn
        if both_cling and not skip:
            d = dist(a["pos"], b["pos"])
            if d > BODY_JUMP:
                ev["body_jump"].append((t, round(d, 2)))
            dd = dist(a["draw"], b["draw"])
            if dd > DRAW_JUMP:
                ev["draw_jump"].append((t, round(dd, 2)))
            if i not in turn and not b["grab"]:
                dh = dist(head_rel(a), head_rel(b))
                if dh > HEAD_JUMP:
                    ev["head_jump"].append((t, round(dh, 2)))
            if not a["grab"] and not b["grab"]:
                da = abs(angle_between(a["up"], b["up"]))
                if da > UP_FLIP:
                    ev["up_flip"].append((t, round(math.degrees(da), 1)))
        # Feet (a turn swings the legs round by design, like the head)
        if not skip and both_cling and i not in turn:
            for k, (fa, fb) in enumerate(zip(a["feet"], b["feet"])):
                df = dist(fa["pos"], fb["pos"])
                if fa["planted"] and fb["planted"] and df > FOOT_SLIDE:
                    ev["foot_slide"].append((t, round(df, 2), "foot %d" % k))
                elif not fa["stepping"] and not fb["stepping"] and df > FOOT_JUMP:
                    ev["foot_jump"].append((t, round(df, 2), "foot %d" % k))
    # Windows
    n = len(ticks)
    # State flicker: back to an earlier state inside FLICK_WIN (cling, air,
    # cling). A progression (cling, air, swim: walking into water) is not.
    changes = [i for i in range(1, n) if ticks[i]["state"] != ticks[i - 1]["state"]]
    last_flag = -FLICK_WIN
    for j in range(1, len(changes)):
        i, k = changes[j - 1], changes[j]
        if k - i < FLICK_WIN and ticks[k]["state"] == ticks[i - 1]["state"] and k - last_flag >= FLICK_WIN:
            ev["state_flicker"].append((ticks[k]["tick"], k - i))
            last_flag = k
    # Dance: sign changes of along-surface motion under a held input
    along = [0.0] * n
    for i in range(1, n):
        tg = tangent(ticks[i]["up"])
        along[i] = dot((ticks[i]["pos"][0] - ticks[i - 1]["pos"][0], ticks[i]["pos"][1] - ticks[i - 1]["pos"][1]), tg)
    last_flag = -DANCE_WIN
    for i in range(DANCE_WIN, n):
        w = range(i - DANCE_WIN + 1, i + 1)
        inp = ticks[i]["inp"]
        if abs(inp[0]) < 0.2 and abs(inp[1]) < 0.2:
            continue
        if any(ticks[j]["inp"] != inp or ticks[j]["state"] != "cling" or ticks[j]["grab"] or ticks[j]["chew"] for j in w):
            continue
        if any(j in spawn or j in land for j in w):
            continue
        signs = [1 if along[j] > DANCE_MIN else (-1 if along[j] < -DANCE_MIN else 0) for j in w]
        signs = [s for s in signs if s != 0]
        flips = sum(1 for j in range(1, len(signs)) if signs[j] != signs[j - 1])
        if flips >= DANCE_N and i - last_flag >= DANCE_WIN:
            ev["dance"].append((ticks[i]["tick"], flips))
            last_flag = i
    # Up oscillation: alternating up increments
    inc = [0.0] * n
    for i in range(1, n):
        inc[i] = angle_between(ticks[i - 1]["up"], ticks[i]["up"])
    last_flag = -UP_OSC_WIN
    for i in range(UP_OSC_WIN, n):
        w = range(i - UP_OSC_WIN + 1, i + 1)
        if any(ticks[j]["grab"] or ticks[j]["state"] != "cling" for j in w):
            continue
        signs = [1 if inc[j] > UP_OSC_MIN else (-1 if inc[j] < -UP_OSC_MIN else 0) for j in w]
        signs = [s for s in signs if s != 0]
        alt = sum(1 for j in range(1, len(signs)) if signs[j] != signs[j - 1])
        if alt >= UP_OSC_N and i - last_flag >= UP_OSC_WIN:
            ev["up_osc"].append((ticks[i]["tick"], alt))
            last_flag = i
    # Stall and stuck: held input along the surface, no progress
    last_stall = -STALL_WIN
    last_stuck = -STALL_WIN
    for i in range(STALL_WIN, n):
        w = range(i - STALL_WIN + 1, i + 1)
        if any(ticks[j]["state"] != "cling" or abs(ticks[j]["s"]) < 0.3 or ticks[j]["chew"] or ticks[j]["grab"] for j in w):
            continue
        if any(j in spawn or j in land for j in w):
            continue
        inp = ticks[i]["inp"]
        if any(ticks[j]["inp"] != inp for j in w):
            continue
        prog = dist(ticks[i]["pos"], ticks[i - STALL_WIN + 1]["pos"])
        if prog >= STALL_PX:
            continue
        blocked = sum(1 for j in w if ticks[j]["blk"])
        if blocked > STALL_WIN // 2:
            if i - last_stuck >= STALL_WIN:
                ev["stuck"].append((ticks[i]["tick"], round(prog, 1)))
                last_stuck = i
        elif i - last_stall >= STALL_WIN:
            ev["stall"].append((ticks[i]["tick"], round(prog, 1)))
            last_stall = i
    # Foot toggles
    for k in range(len(ticks[0]["feet"])):
        tog = [i for i in range(1, n) if ticks[i]["feet"][k]["planted"] != ticks[i - 1]["feet"][k]["planted"]
               and i not in land and i not in spawn and i not in jumped and i not in turn]
        last_flag = -FOOT_TOGGLE_WIN
        for j in range(FOOT_TOGGLE_N - 1, len(tog)):
            if tog[j] - tog[j - FOOT_TOGGLE_N + 1] < FOOT_TOGGLE_WIN and tog[j] - last_flag >= FOOT_TOGGLE_WIN:
                ev["foot_toggle"].append((ticks[tog[j]]["tick"], FOOT_TOGGLE_N, "foot %d" % k))
                last_flag = tog[j]
    # Sink and float
    run_sink = run_float = 0
    for i in range(n):
        tk = ticks[i]
        cling = tk["state"] == "cling" and i not in spawn and i not in land
        run_sink = run_sink + 1 if cling and tk["dist"] < SINK_D else 0
        run_float = run_float + 1 if cling and not tk["bridge"] and tk["dist"] > FLOAT_D else 0
        if run_sink == SINK_TICKS:
            ev["sink"].append((tk["tick"], tk["dist"]))
        if run_float == SINK_TICKS:
            ev["float"].append((tk["tick"], tk["dist"]))
    return ev


def outcome(ticks, scene):
    if not ticks:
        return {"ok": False, "why": "no trace"}
    last = ticks[-1]
    why = []
    if "state" in scene and last["state"] != scene["state"]:
        why.append("ends %s, expected %s" % (last["state"], scene["state"]))
    if "end" in scene:
        x0, y0, x1, y1 = scene["end"]
        px, py = last["pos"]
        if not (x0 <= px <= x1 and y0 <= py <= y1):
            why.append("ends at (%.0f, %.0f), expected x %d..%d y %d..%d" % (px, py, x0, x1, y0, y1))
    return {"ok": not why, "why": "; ".join(why)}


def load_scenes():
    with open(SCENES) as f:
        return json.load(f)


def specs(data):
    out = []
    for name, sc in data["scenes"].items():
        if "script" in sc:
            out.append("%s:inline" % name)
        for s in sc.get("scripts", []):
            out.append("%s:%s" % (name, s))
    return out


def analyze(runs_dir, baseline_path=None):
    data = load_scenes()
    base = None
    if baseline_path and os.path.exists(baseline_path):
        with open(baseline_path) as f:
            base = json.load(f)["runs"]
    results = {}
    for spec in specs(data):
        scene_name, script = spec.split(":")
        path = os.path.join(runs_dir, scene_name, script, "trace.log")
        if not os.path.exists(path):
            continue
        ticks = parse(path)
        scene = data["scenes"][scene_name]
        ev = metrics(ticks)
        allow = set(scene.get("allow", []))
        oc = outcome(ticks, scene)
        if parse.corrupt:
            oc = {"ok": False, "why": "corrupt trace (%d bad lines): re-run it" % parse.corrupt}
        failing = [m for m in SCORED if ev[m] and m not in allow]
        results[spec] = {
            "ticks": len(ticks),
            "metrics": {m: {"count": len(ev[m]), "worst": max((e[1] for e in ev[m]), default=0),
                            "events": ev[m][:12]} for m in SCORED + INFO},
            "outcome": oc,
            "failing": failing,
            "pass": not failing and oc["ok"],
            "allow": sorted(allow),
        }
    # Report
    total = len(results)
    passing = sum(1 for r in results.values() if r["pass"])
    cols = SCORED + INFO
    short = {"draw_jump": "draw", "head_jump": "head", "dance": "dance", "up_flip": "upflip", "up_osc": "uposc",
             "state_flicker": "state", "stall": "stall", "foot_toggle": "ftog", "foot_slide": "fslide",
             "foot_jump": "fjump", "sink": "sink", "float": "float", "body_jump": "body*", "stuck": "stuck*"}
    lines = ["# Movement suite report", "",
             "Runs: %d, passing: %d, failing: %d. Columns are event counts; * marks informational metrics." % (total, passing, total - passing), ""]
    if base is not None:
        lines.append("Compared against baseline %s." % os.path.basename(baseline_path))
        lines.append("")
    lines.append("| run | result | " + " | ".join(short[c] for c in cols) + " | outcome |")
    lines.append("|---|---|" + "---|" * len(cols) + "---|")
    reg, imp = [], []
    for spec, r in sorted(results.items(), key=lambda kv: (kv[1]["pass"], kv[0])):
        cells = []
        for c in cols:
            cnt = r["metrics"][c]["count"]
            cell = str(cnt) if cnt else ""
            if base is not None and spec in base:
                b = base[spec]["metrics"].get(c, {}).get("count", 0)
                if cnt > b:
                    cell += " (+%d)" % (cnt - b)
                    if c in SCORED and c not in r["allow"]:
                        reg.append((spec, c, b, cnt))
                elif cnt < b:
                    cell += " (-%d)" % (b - cnt)
                    if c in SCORED:
                        imp.append((spec, c, b, cnt))
            cells.append(cell)
        res = "pass" if r["pass"] else "FAIL"
        oc = "ok" if r["outcome"]["ok"] else r["outcome"]["why"]
        lines.append("| %s | %s | %s | %s |" % (spec, res, " | ".join(cells), oc))
    if base is not None:
        lines += ["", "## Against the baseline", ""]
        lines.append("Regressions: %d. Improvements: %d." % (len(reg), len(imp)))
        for spec, c, b, cnt in reg:
            lines.append("- REGRESSION %s %s: %d -> %d" % (spec, c, b, cnt))
        for spec, c, b, cnt in imp:
            lines.append("- improved %s %s: %d -> %d" % (spec, c, b, cnt))
    lines += ["", "## Failing runs", ""]
    for spec, r in sorted(results.items()):
        if r["pass"]:
            continue
        lines.append("### %s" % spec)
        if not r["outcome"]["ok"]:
            lines.append("- outcome: %s" % r["outcome"]["why"])
        for m in r["failing"]:
            mm = r["metrics"][m]
            evs = ", ".join("t%d (%s)" % (e[0], ", ".join(str(x) for x in e[1:])) for e in mm["events"][:8])
            lines.append("- %s: %d events, worst %s: %s" % (m, mm["count"], mm["worst"], evs))
        lines.append("")
    report = "\n".join(lines) + "\n"
    with open(os.path.join(runs_dir, "report.md"), "w") as f:
        f.write(report)
    with open(os.path.join(runs_dir, "report.json"), "w") as f:
        json.dump({"runs": results}, f, indent=1)
    print("runs %d, passing %d, failing %d -> %s" % (total, passing, total - passing, os.path.join(runs_dir, "report.md")))
    if base is not None:
        print("regressions %d, improvements %d" % (len(reg), len(imp)))
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("runs", nargs="?", default="runs")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--baseline")
    args = ap.parse_args()
    if args.list:
        for s in specs(load_scenes()):
            print(s)
        return
    analyze(args.runs, args.baseline)


if __name__ == "__main__":
    main()
