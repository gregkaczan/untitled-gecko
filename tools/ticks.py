#!/usr/bin/env python3
"""Prints a tick range of a suite run's trace as a table.

    tools/ticks.py runs/<scene>/<script> <from> <to> [field,field,...]

Fields: pos draw head rel up dist spd state facing inp s blk grab bridge
sq chew jump n feet, plus the per-tick deltas dpos ddraw drel (px moved
by the body, the drawn body, and the head in the body's frame) and dup
(degrees the up vector turned). Default: tick dpos ddraw drel dup up
dist spd state blk grab sq n.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from analyze import parse, head_rel, dist, angle_between  # noqa: E402

DEFAULT = "tick dpos ddraw drel dup up dist spd state blk grab sq n".split()


def fmt(v):
    if isinstance(v, tuple):
        return "%.1f,%.1f" % v
    if isinstance(v, float):
        return "%.1f" % v
    if isinstance(v, bool):
        return "1" if v else "0"
    return str(v)


def main():
    run, lo, hi = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    fields = sys.argv[4].split(",") if len(sys.argv) > 4 else DEFAULT
    ticks = parse(os.path.join(run, "trace.log"))
    by = {t["tick"]: (i, t) for i, t in enumerate(ticks)}
    print(" ".join("%-10s" % f for f in fields))
    for n in range(lo, hi + 1):
        if n not in by:
            continue
        i, t = by[n]
        p = ticks[i - 1] if i > 0 else t
        row = []
        for f in fields:
            if f == "dpos":
                row.append(dist(p["pos"], t["pos"]))
            elif f == "ddraw":
                row.append(dist(p["draw"], t["draw"]))
            elif f == "drel":
                row.append(dist(head_rel(p), head_rel(t)))
            elif f == "rel":
                row.append(head_rel(t))
            elif f == "dup":
                row.append(math.degrees(angle_between(p["up"], t["up"])))
            elif f == "feet":
                row.append(" ".join("%s%s%.0f,%.0f" % ("P" if ft["planted"] else ("S" if ft["stepping"] else "-"), "", *ft["pos"]) for ft in t["feet"]))
            else:
                row.append(t[f])
        print(" ".join("%-10s" % fmt(v) for v in row))


if __name__ == "__main__":
    main()
