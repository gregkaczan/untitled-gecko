#!/usr/bin/env python3
"""Turns the movement suite's traces into a report.

    tools/analyze.py runs/                 report.md and report.json in runs/
    tools/analyze.py runs/ --baseline b.json   also marks regressions
    tools/analyze.py --list                the scene:script specs to run
    tools/analyze.py --list-sim            the same with the sim_only scenes

A run is one scene and one script. Its trace has one `t<n>` line per
physics tick (see gecko.gd _print_trace) and one `F<frame> x y tick cx
cy bx by wx wy won` line per drawn frame (main.gd _process: the body
centre on the screen, the tick, the camera's centre in the world, the
drawn body's base on the screen where the pixel grid seats it, that
base in the world, and whether the gecko is out and the camera has let
go of it). Each metric below turns the ticks, or the frames, into
events (tick, value); a run passes when every scored metric has no
events and the scene's expected outcome holds. Thresholds are at the
top; they are calibrated so the flat floor produces nothing.
"""
import argparse
import glob
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
HEAD_JUMP = 6.5            # px per tick of the head in the drawn body frame: its set speed is 6, and the frame turning adds a little
FREE_LAG = 30.0            # px: off the surface (air, water) the drawn head this far from the body centre has been left behind (HEAD_LEAD is 15): a fall outran the drawn body, which came down after its own landing (2026-10-21)
CHAIN_BUNCH = 0.7          # the drawn body from point 1 to point 7, laid a link (8) apart, measured along its points: shorter than this share of its length (34 of 48 px), it has bunched into a lump (the walk round a ball, 2026-10-21); a fold doubles the body over by design and is skipped
CHAIN_JUMP = 10.5          # px per tick of any drawn body point, in the world: the body lies along the base's track behind a straight neck, so a point moves at most as fast as the head (6) and the base (2.2) together, plus its sag easing (2); a snap was 65 to 130
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
IDLE_TAIL = 15             # ticks at the end of a stall window judged for a press that does nothing by design
FOOT_TOGGLE_WIN = 8        # ticks: a step is 6 ticks of lift, so three toggles inside 8 is a flicker
FOOT_TOGGLE_N = 3          # planted toggles inside the window
FOOT_SLIDE = 2.0           # px a planted foot may move per tick
FOOT_JUMP = 12.0           # px per tick for a foot that is not stepping
SINK_D = 8.5               # nearest rock closer than this = body inside rock
FLOAT_D = 24.0             # nearest rock farther than this while clinging = floating
SINK_TICKS = 10
TURN_GRACE = 20            # ticks after a facing flip: the head swings round by design
LAND_GRACE = 12            # ticks after landing: feet re-seat, the chain catches up at its set speed
SPAWN_GRACE = 12           # first ticks: the gecko settles onto its spawn
# Camera (from the F lines, screen px; the window shows the world at ZOOM)
ZOOM = 2.0
CAM_JERK = 4.0             # change of the camera's per-frame step while the body's own step is steady: a camera on a coarse grid steps 0, 4, 8; its rounding to the screen pixel alone can change a step by 2
CAM_STEADY = 0.6           # world px: the body's step may change this much and still count as steady
SHAKE_MIN = 1.0            # screen px: a reversal of the drawn body's screen motion smaller than this is nothing
CREEP_WIN = 12             # frames the body has been still before a moving camera counts as creeping

SCORED = ["draw_jump", "head_jump", "chain_jump", "chain_bunch", "free_lag", "dance", "up_flip", "up_osc", "state_flicker", "stall",
          "foot_toggle", "foot_slide", "foot_jump", "sink", "float", "cam_jerk", "shake", "tube_full"]
INFO = ["body_jump", "stuck", "cam_creep", "settle"]


def vec(s):
    a, b = s.split(",")
    return (float(a), float(b))


def parse(path):
    """The trace's ticks, and its frames in parse.frames (empty for a
    trace from before the camera fields). A tick number that does not
    follow the last one means two processes wrote the file (or a line
    was cut): the run is marked corrupt rather than scored."""
    ticks = []
    frames = []
    parse.corrupt = 0
    parse.frames = frames
    with open(path) as f:
        for line in f:
            if line.startswith("F") and line[1:2].isdigit():
                parts = line.split()
                if len(parts) >= 10:
                    try:
                        frames.append({"tick": int(parts[3]), "cam": (float(parts[4]), float(parts[5])),
                                       "body": (float(parts[6]), float(parts[7])), "world": (float(parts[8]), float(parts[9])),
                                       "won": len(parts) > 10 and parts[10] == "1"})
                    except ValueError:
                        parse.corrupt += 1
                continue
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
                "facing": int(d["facing"]), "cf": int(d.get("cf", d["facing"])), "inp": vec(d["inp"]), "s": float(d["s"]),
                "blk": d["blk"] == "1", "grab": d["grab"] == "1", "bridge": d["bridge"] == "1",
                "sq": d["sq"] == "1", "chew": d["chew"] == "1", "jump": d["jump"] == "1",
                "n": vec(d["n"]), "bn": vec(d.get("bn", "0,0")), "sc": d.get("sc", "0") == "1",
                "sqz": d.get("sqz", "0") == "1", "ps": d.get("ps", "0") == "1", "feet": feet,
                "cw": float(d.get("cw", "-1")), "sqin": d.get("sqin", "0") == "1", "tube": int(d.get("tube", "0")),
                "set": d.get("set", "0") == "1", "rev": int(d.get("rev", "0")), "sw": d.get("sw", "0") == "1",
                "hb": float(d.get("hb", "0")), "lift": float(d.get("lift", "0")), "fd": float(d.get("fd", "0")),
                "chain": chain_points(d),
            })
    return ticks


def chain_points(d):
    """The drawn body's points in the world, from the trace's cp field
    (along/across/radius/thinned per point, in the body's frame)."""
    pos = vec(d["pos"])
    up = vec(d["up"])
    t = (-up[1], up[0])
    pts = []
    for e in d.get("cp", "").split(";"):
        if not e:
            continue
        al, ac = (float(x) for x in e.split("/")[:2])
        pts.append((pos[0] + t[0] * al + up[0] * ac, pos[1] + t[1] * al + up[1] * ac))
    return pts


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def angle_between(a, b):
    return math.atan2(a[0] * b[1] - a[1] * b[0], a[0] * b[0] + a[1] * b[1])


def tangent(up):
    return (-up[1], up[0])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def head_rel(tk):
    """The head in the drawn body's frame (what is seen): along the surface, and out from it."""
    d = (tk["head"][0] - tk["draw"][0], tk["head"][1] - tk["draw"][1])
    return (dot(d, tangent(tk["up"])), dot(d, tk["up"]))


def grace_sets(ticks):
    """Ticks to skip per reason: after a facing flip, after landing, after a jump, at spawn."""
    turn, land, jumped = set(), set(), set()
    for i in range(1, len(ticks)):
        # The head swings round when the drawn body's facing (cf) flips: at
        # once in the open, or once a body backing out of a passage is out.
        if ticks[i]["facing"] != ticks[i - 1]["facing"] or ticks[i]["cf"] != ticks[i - 1]["cf"]:
            turn.update(range(i, min(len(ticks), i + TURN_GRACE)))
        if ticks[i]["state"] == "cling" and ticks[i - 1]["state"] != "cling":
            land.update(range(i, min(len(ticks), i + LAND_GRACE)))
        if ticks[i]["jump"]:
            jumped.update(range(i, min(len(ticks), i + 3)))
    spawn = set(range(0, min(len(ticks), SPAWN_GRACE)))
    return turn, land, jumped, spawn


def camera_metrics(ev, ticks, frames):
    """From the frames: the camera's step changing while the body's own
    step is steady (cam_jerk: a camera rounded to a coarse grid, or one
    that moves on another clock than the body), the drawn body's screen
    motion reversing while its world motion does not (shake: the body
    and the camera rounded to pixels independently), and the camera
    still moving long after the body has stopped (cam_creep). Frames
    whose ticks are not consecutive (two frames of one tick, a frame
    skipped) are not compared, nor the grace ticks after a change of
    state (a landing, the water, the tongue: each jolts the body's
    motion by design), a turn or a jump, nor the spawn, nor the
    camera's pull-back once the gecko is out. A camera that stops dead,
    or starts, while the body goes on moving is one held at the world's
    edge, not a jerk."""
    if len(frames) < 3 or not ticks:
        return
    turn, land, jumped, spawn = grace_sets(ticks)
    index = {tk["tick"]: i for i, tk in enumerate(ticks)}
    skip = turn | land | jumped | spawn
    for i in range(1, len(ticks)):
        if ticks[i]["state"] != ticks[i - 1]["state"]:
            skip.update(range(i, min(len(ticks), i + LAND_GRACE)))

    def steps(k, i):
        a, b = frames[i - 1], frames[i]
        return ((b["cam"][k] - a["cam"][k]) * ZOOM, b["body"][k] - a["body"][k], b["world"][k] - a["world"][k])

    still = 0
    for i in range(2, len(frames)):
        f0, f1, f2 = frames[i - 2], frames[i - 1], frames[i]
        t = f2["tick"]
        if f1["tick"] != f0["tick"] + 1 or t != f1["tick"] + 1 or f2["won"]:
            continue
        if any(index.get(x, -1) in skip or x not in index for x in (f0["tick"], f1["tick"], t)):
            continue
        moved = dist(f2["world"], f1["world"]) > 0.05
        still = 0 if moved else still + 1
        for k, axis in ((0, "x"), (1, "y")):
            c1, b1, w1 = steps(k, i - 1)
            c2, b2, w2 = steps(k, i)
            pinned = (c2 == 0.0 and abs(w2) > 0.5) or (c1 == 0.0 and abs(w1) > 0.5)
            if abs(c2 - c1) >= CAM_JERK and abs(w2 - w1) < CAM_STEADY and not pinned:
                ev["cam_jerk"].append((t, round(abs(c2 - c1), 1), axis))
            if b1 * b2 < 0 and min(abs(b1), abs(b2)) >= SHAKE_MIN and w1 * w2 >= 0:
                ev["shake"].append((t, round(abs(b2 - b1), 1), axis))
            if still > CREEP_WIN and abs(c2) >= 1.0:
                ev["cam_creep"].append((t, round(abs(c2), 1), axis))


def metrics(ticks, frames=()):
    ev = {k: [] for k in SCORED + INFO}
    if len(ticks) < 2:
        return ev
    camera_metrics(ev, ticks, frames)
    turn, land, jumped, spawn = grace_sets(ticks)
    for i in range(1, len(ticks)):
        a, b = ticks[i - 1], ticks[i]
        t = b["tick"]
        both_cling = a["state"] == "cling" and b["state"] == "cling"
        if b["state"] in ("air", "swim"):
            lag = dist(b["head"], b["pos"])
            if lag > FREE_LAG:
                ev["free_lag"].append((t, round(lag, 1)))
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
            # The drawn body's points, in the world, with no grace for a
            # turn: a turn-around must not snap the body either (the tail
            # moved 130 px in a tick on a facing flip, 2026-10-21).
            if a["chain"] and b["chain"]:
                dc = max((dist(pa, pb), k) for k, (pa, pb) in enumerate(zip(a["chain"], b["chain"])))
                if dc[0] > CHAIN_JUMP:
                    ev["chain_jump"].append((t, round(dc[0], 2), "point %d" % dc[1]))
                # The body drawn shorter than its links allow,
                # outside a fold (fd: the track doubled back behind the
                # base) and the turn that begins one.
                if i not in turn and a["fd"] == 0 and b["fd"] == 0 and len(b["chain"]) > 8:
                    run = sum(dist(b["chain"][k], b["chain"][k + 1]) for k in range(1, 7))
                    if run < CHAIN_BUNCH * 6 * 8.0:
                        ev["chain_bunch"].append((t, round(run, 1)))
            # A switch between a floor and its ceiling turns up round by
            # design (gecko.gd _switch_surface).
            if not a["grab"] and not b["grab"] and not b["sw"]:
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
    # Stall and stuck: a held press, no progress. Stuck (informational)
    # is a press into the rock that blocks the body, a wall by design.
    # A press square to a flat surface (up on a floor) does nothing by
    # design too. Anything else is a stall: the press is ignored.
    last_stall = -STALL_WIN
    last_stuck = -STALL_WIN
    for i in range(STALL_WIN, n):
        w = range(i - STALL_WIN + 1, i + 1)
        if any(ticks[j]["state"] != "cling" or ticks[j]["chew"] or ticks[j]["grab"] for j in w):
            continue
        if any(j in spawn or j in land for j in w):
            continue
        inp = ticks[i]["inp"]
        if abs(inp[0]) < 0.2 and abs(inp[1]) < 0.2:
            continue
        if any(ticks[j]["inp"] != inp for j in w):
            continue
        prog = dist(ticks[i]["pos"], ticks[i - STALL_WIN + 1]["pos"])
        if prog >= STALL_PX:
            continue
        def into(j):
            return ticks[j]["blk"] and dot(inp, ticks[j]["bn"]) < -0.3
        into_rock = sum(1 for j in w if into(j))
        # A press into the surface the body clings to attempts no step at
        # all (no block is recorded), and does nothing by design.
        rest = range(i - IDLE_TAIL + 1, i + 1)
        into_surface = all(dot(inp, ticks[j]["up"]) < -0.5 for j in rest)
        # A press stopped at a bump the surface curls over (the way chosen
        # for it turned against it) stays stopped until the press changes,
        # by design: the alternative is reversing in a loop.
        press_stop = all(ticks[j]["ps"] for j in rest)
        idle_ok = into_surface or press_stop or all(abs(dot(inp, tangent(ticks[j]["up"]))) < 0.3 and abs(tangent(ticks[j]["up"])[1]) <= 0.5 for j in rest)
        # A squeeze walks slowly (26 px a window), so a window that ends
        # at a wall holds too little progress before half of it is
        # blocked: a tail of blocked ticks is the wall all the same.
        into_rock_tail = sum(1 for j in rest if into(j))
        if into_rock > STALL_WIN // 2 or into_rock_tail >= IDLE_TAIL * 2 // 3:
            if i - last_stuck >= STALL_WIN:
                ev["stuck"].append((ticks[i]["tick"], round(prog, 1)))
                last_stuck = i
        elif not idle_ok and i - last_stall >= STALL_WIN:
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
        # In a squeeze the body rides closer to rock by design.
        run_sink = run_sink + 1 if cling and not tk["sqz"] and tk["dist"] < SINK_D else 0
        run_float = run_float + 1 if cling and not tk["bridge"] and tk["dist"] > FLOAT_D else 0
        if run_sink == SINK_TICKS:
            ev["sink"].append((tk["tick"], tk["dist"]))
        if run_float == SINK_TICKS:
            ev["float"].append((tk["tick"], tk["dist"]))
    # A body segment drawn as a tube of splats with neither end thinned a
    # pixel: the tube renders fatter than one blob of the radius, and a
    # body read as narrow but barely thinned (a 22 px passage, squeezed
    # into from a blocked walk) swelled past the walls. gecko.gd draws
    # no such tube now (the trace's tube count), so one is a regression.
    last_tube = -SINK_TICKS
    for i, tk in enumerate(ticks):
        if tk["tube"] and i - last_tube >= SINK_TICKS:
            ev["tube_full"].append((tk["tick"], tk["tube"]))
            last_tube = i
    # The settle latch taking hold (informational): at rest a drawn point
    # or a foot reversed its motion twice, and the body was held still.
    # The player sees one rattle; the loop behind it is still there, and
    # this column says where to look for it.
    for i in range(1, n):
        if ticks[i]["set"] and not ticks[i - 1]["set"]:
            ev["settle"].append((ticks[i]["tick"], ticks[i]["rev"]))
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
    if "reach" in scene:
        x0, y0, x1, y1 = scene["reach"]
        if not any(x0 <= tk["pos"][0] <= x1 and y0 <= tk["pos"][1] <= y1 for tk in ticks):
            why.append("never reaches x %d..%d y %d..%d" % (x0, x1, y0, y1))
    if "end_up" in scene:
        # The surface the body must end on, as its up (within 45 degrees).
        ux, uy = scene["end_up"]
        if dot(last["up"], (ux, uy)) < 0.7:
            why.append("ends with up (%.2f, %.2f), expected (%d, %d)" % (last["up"][0], last["up"][1], ux, uy))
    return {"ok": not why, "why": "; ".join(why)}


def load_scenes():
    with open(SCENES) as f:
        data = json.load(f)
    # The levels (levels/*.json, tools/gen_clutch.py) are scenes too.
    for path in sorted(glob.glob(os.path.join(ROOT, "levels", "*.json"))):
        with open(path) as f:
            level = json.load(f)
        for key in ("bases", "scripts", "scenes"):
            data.setdefault(key, {}).update(level.get(key, {}))
    return data


def specs(data, headless=False):
    # A station that needs the particle world's lumps (sim_only) is not
    # in the headless suite's list; tools/record.sh runs it.
    out = []
    for name, sc in data["scenes"].items():
        if headless and sc.get("sim_only"):
            continue
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
        frames = parse.frames
        scene = data["scenes"][scene_name]
        ev = metrics(ticks, frames)
        allow = set(scene.get("allow", []))
        oc = outcome(ticks, scene)
        if parse.corrupt:
            oc = {"ok": False, "why": "corrupt trace (%d bad lines): re-run it" % parse.corrupt}
        failing = [m for m in SCORED if ev[m] and m not in allow]
        travel = sum(dist(ticks[i - 1]["pos"], ticks[i]["pos"]) for i in range(1, len(ticks)))
        results[spec] = {
            "ticks": len(ticks),
            "travel": round(travel),
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
    short = {"draw_jump": "draw", "head_jump": "head", "chain_jump": "chain", "chain_bunch": "bunch", "free_lag": "lag", "dance": "dance", "up_flip": "upflip", "up_osc": "uposc",
             "state_flicker": "state", "stall": "stall", "foot_toggle": "ftog", "foot_slide": "fslide",
             "foot_jump": "fjump", "sink": "sink", "float": "float", "cam_jerk": "cjerk", "shake": "shake",
             "tube_full": "tube", "body_jump": "body*", "stuck": "stuck*", "cam_creep": "creep*", "settle": "settle*"}
    lines = ["# Movement suite report", "",
             "Runs: %d, passing: %d, failing: %d. Columns are event counts; * marks informational metrics; "
             "travel is the body's path length in px, a check that the scene was exercised." % (total, passing, total - passing), ""]
    if base is not None:
        lines.append("Compared against baseline %s." % os.path.basename(baseline_path))
        lines.append("")
    lines.append("| run | result | " + " | ".join(short[c] for c in cols) + " | travel | outcome |")
    lines.append("|---|---|" + "---|" * len(cols) + "---|---|")
    reg, imp = [], []
    for spec, r in sorted(results.items(), key=lambda kv: (kv[1]["pass"], kv[0])):
        cells = []
        for c in cols:
            cnt = r["metrics"][c]["count"]
            cell = str(cnt) if cnt else ""
            # A metric the baseline predates (the camera's) is not compared.
            if base is not None and spec in base and c in base[spec]["metrics"]:
                b = base[spec]["metrics"][c].get("count", 0)
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
        lines.append("| %s | %s | %s | %d | %s |" % (spec, res, " | ".join(cells), r["travel"], oc))
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
    ap.add_argument("--list-sim", action="store_true", help="the specs with the sim_only scenes too (SIM=1 tools/suite.sh)")
    ap.add_argument("--baseline")
    args = ap.parse_args()
    if args.list or args.list_sim:
        for s in specs(load_scenes(), headless=not args.list_sim):
            print(s)
        return
    analyze(args.runs, args.baseline)


if __name__ == "__main__":
    main()
