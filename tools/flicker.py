#!/usr/bin/env python3
"""Frame flicker: how much the gecko's drawn silhouette changes between
consecutive 60 fps frames of a recording, which the trace cannot see
(a leg blob popping, the eye jumping, a tail link vanishing).

    tools/flicker.py frames/            every recording under frames/
    tools/flicker.py frames/<scene>/<script>

Each frame is cropped round the gecko's traced screen position (so the
gecko stays centred and the scrolling cave does not count), the
gecko-coloured pixels make a mask, and the change is the share of mask
pixels that differ between a frame and the next, relative to the mask's
size. Legs stepping change a few percent; a pop is a spike. Writes
flicker.md and flicker.json next to the recordings, with every frame
over FLICKER as an event. Needs ImageMagick's convert.
"""
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

CROP_W, CROP_H = 200, 140
FLICKER = 0.20            # share of the silhouette that changes in one frame
MIN_MASK = 150            # px: smaller masks (gecko off screen or hidden) are skipped
JOBS = 7


def gecko_pixel(r, g, b):
    return g > r + 8 and g > b + 25 and g > 70


def crop_mask(frame, sx, sy):
    """The gecko mask of the crop round (sx, sy), shifted so the mask's
    centroid sits at the crop's centre: the gecko moves a few px per
    frame and the crop origin is a whole pixel, so without this the
    comparison would mostly measure that shift."""
    x = max(0, sx - CROP_W // 2)
    y = max(0, sy - CROP_H // 2)
    raw = subprocess.run(
        ["convert", frame, "-crop", "%dx%d+%d+%d" % (CROP_W, CROP_H, x, y), "+repage", "-depth", "8", "rgb:-"],
        capture_output=True, check=True).stdout
    w, h = CROP_W, CROP_H
    if len(raw) != w * h * 3:
        return None, 0
    rows = []
    cx = cy = cnt = 0
    for j in range(h):
        row = bytearray(w)
        base = j * w * 3
        for i in range(w):
            k = base + i * 3
            if gecko_pixel(raw[k], raw[k + 1], raw[k + 2]):
                row[i] = 1
                cx += i
                cy += j
                cnt += 1
        rows.append(row)
    if cnt == 0:
        return rows, 0
    dx = w // 2 - cx // cnt
    dy = h // 2 - cy // cnt
    out = []
    for j in range(h):
        src = j - dy
        if 0 <= src < h:
            row = rows[src]
            if dx >= 0:
                out.append(bytes(dx) + bytes(row[:w - dx]))
            else:
                out.append(bytes(row[-dx:]) + bytes(-dx))
        else:
            out.append(bytes(w))
    return out, cnt


def frame_positions(trace):
    """frame number -> (tick, sx, sy) from the F lines."""
    out = {}
    with open(trace) as f:
        for line in f:
            if line.startswith("F") and line[1:2].isdigit():
                parts = line.split()
                if len(parts) >= 4:
                    out[int(parts[0][1:])] = (int(parts[3]), int(parts[1]), int(parts[2]))
    return out


def analyze_run(run_dir):
    trace = os.path.join(run_dir, "trace.log")
    if not os.path.exists(trace):
        return None
    pos = frame_positions(trace)
    frames = sorted(int(f[1:9]) for f in os.listdir(run_dir) if f.startswith("f") and f.endswith(".png") and f[1:9].isdigit())
    frames = [k for k in frames if k in pos]
    if len(frames) < 2:
        return None

    def work(k):
        tick, sx, sy = pos[k]
        mask, n = crop_mask(os.path.join(run_dir, "f%08d.png" % k), sx, sy)
        return k, tick, mask, n

    with ThreadPoolExecutor(JOBS) as ex:
        masks = list(ex.map(work, frames))
    events = []
    changes = []
    for (k0, t0, m0, size0), (k1, t1, m1, size1) in zip(masks, masks[1:]):
        if m0 is None or m1 is None or min(size0, size1) < MIN_MASK:
            continue
        diff = 0
        for r0, r1 in zip(m0, m1):
            if r0 != r1:
                diff += sum(1 for a, b in zip(r0, r1) if a != b)
        change = diff / max(size0, 1)
        changes.append(change)
        if change > FLICKER:
            events.append((t1, round(change, 3)))
    changes.sort()
    med = changes[len(changes) // 2] if changes else 0.0
    p95 = changes[int(len(changes) * 0.95)] if changes else 0.0
    return {"frames": len(frames), "median": round(med, 3), "p95": round(p95, 3), "max": round(changes[-1], 3) if changes else 0.0,
            "events": events[:20], "count": len(events)}


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "frames"
    runs = []
    if os.path.exists(os.path.join(root, "trace.log")):
        runs = [root]
        out_dir = os.path.dirname(os.path.dirname(root))
    else:
        for scene in sorted(os.listdir(root)):
            sd = os.path.join(root, scene)
            if not os.path.isdir(sd):
                continue
            for script in sorted(os.listdir(sd)):
                rd = os.path.join(sd, script)
                if os.path.isdir(rd):
                    runs.append(rd)
        out_dir = root
    results = {}
    for rd in runs:
        r = analyze_run(rd)
        if r is None:
            continue
        name = "%s:%s" % (os.path.basename(os.path.dirname(rd)), os.path.basename(rd))
        results[name] = r
        print("%-36s frames %4d  median %.3f  p95 %.3f  max %.3f  events %d" % (name, r["frames"], r["median"], r["p95"], r["max"], r["count"]))
    lines = ["# Frame flicker report", "",
             "Silhouette change between consecutive frames, as a share of the gecko's pixels. Events are frames over %.2f." % FLICKER, "",
             "| run | frames | median | p95 | max | events |", "|---|---|---|---|---|---|"]
    for name, r in sorted(results.items(), key=lambda kv: -kv[1]["max"]):
        lines.append("| %s | %d | %.3f | %.3f | %.3f | %d |" % (name, r["frames"], r["median"], r["p95"], r["max"], r["count"]))
    lines += ["", "## Events", ""]
    for name, r in sorted(results.items()):
        if r["events"]:
            lines.append("- %s: %s" % (name, ", ".join("t%d (%.2f)" % e for e in r["events"])))
    with open(os.path.join(out_dir, "flicker.md"), "w") as f:
        f.write("\n".join(lines) + "\n")
    with open(os.path.join(out_dir, "flicker.json"), "w") as f:
        json.dump(results, f, indent=1)
    bad = sum(1 for r in results.values() if r["count"])
    print("runs %d, with flicker events %d -> %s" % (len(results), bad, os.path.join(out_dir, "flicker.md")))


if __name__ == "__main__":
    main()
