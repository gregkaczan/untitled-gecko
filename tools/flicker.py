#!/usr/bin/env python3
"""Frame flicker: how much the gecko's drawn silhouette changes between
consecutive 60 fps frames of a recording, and whether it breaks into
fragments, which the trace cannot see (a leg blob popping, a stray
speck off a stretched leg, a tail link vanishing).

    tools/flicker.py frames/            every recording under frames/
    tools/flicker.py frames/<scene>/<script>

Each frame is cropped round the gecko's traced screen position, the
gecko-coloured pixels make a mask, the mask is aligned on its centroid
and then on the best of a few one-pixel shifts against the previous
frame's, and the change is the share of mask pixels that differ.
Legs stepping change a few percent; a pop is a spike. Fragments are
the pixels of the mask that are not connected to its largest piece.
Writes flicker.md and flicker.json next to the recordings, with every
frame over FLICKER or with FRAGMENT px of fragments as an event. Needs
ImageMagick's convert.
"""
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

CROP_W, CROP_H = 200, 140
FLICKER = 0.35            # share of the silhouette that changes in one frame, outside a turn (legs stepping is ~0.12)
TURN_GRACE = 20           # ticks after a facing flip where the body folds round by design
SPAWN_GRACE = 12          # first ticks: the gecko settles onto its spawn
LAND_GRACE = 12           # ticks after a landing: the feet re-seat and the chain catches up
TURN_RATE = 0.12          # radians of up turn in a tick (about 7 degrees) that counts as the body rounding a corner
FRAGMENT = 8              # px of silhouette not attached to its largest piece
SHIFTS = range(-2, 3)     # px of extra alignment searched each way
MIN_MASK = 150            # px: smaller masks (gecko off screen or hidden) are skipped
JOBS = 7


def gecko_pixel(r, g, b):
    """Body, far legs and their shader-darkened rims are all greens with
    g well over r and b; rock, cave and water never are."""
    if g > r + 5 and g > b + 15 and g > 40:
        return True
    # The eye, drawn over the blob layer in (20, 18, 15): part of the head,
    # or the sliver of head above it reads as a detached piece.
    return abs(r - 20) <= 3 and abs(g - 18) <= 3 and abs(b - 15) <= 3


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


def fragments(rows):
    """Pixels of the mask outside its largest 4-connected piece."""
    w, h = len(rows[0]), len(rows)
    seen = bytearray(w * h)
    sizes = []
    for j in range(h):
        row = rows[j]
        for i in range(w):
            if not row[i] or seen[j * w + i]:
                continue
            stack = [(i, j)]
            seen[j * w + i] = 1
            size = 0
            while stack:
                x, y = stack.pop()
                size += 1
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < w and 0 <= ny < h and rows[ny][nx] and not seen[ny * w + nx]:
                        seen[ny * w + nx] = 1
                        stack.append((nx, ny))
            sizes.append(size)
    return sum(sizes) - max(sizes) if sizes else 0


def best_change(m0, m1, size0):
    """Differing pixels between the masks at the best of a few shifts, as a
    share of the first mask. Masks as one big integer each: a shift of
    dx, dy is a shift by 8 * (dy * w + dx) bits (the crop's empty margins
    swallow the row wrap)."""
    w = len(m0[0])
    a = int.from_bytes(b"".join(m0), "big")
    b = int.from_bytes(b"".join(m1), "big")
    best = None
    for dy in SHIFTS:
        for dx in SHIFTS:
            bits = 8 * (dy * w + dx)
            shifted = b << bits if bits >= 0 else b >> -bits
            diff = (a ^ shifted).bit_count()
            if best is None or diff < best:
                best = diff
    return best / max(size0, 1)


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


def turn_ticks(trace):
    """Ticks where a big silhouette change is by design: the grace after
    a facing flip (the body folds round), the first ticks (settling onto
    the spawn), every tick in the air (the body stretches, the legs
    hang) and the grace after a landing (feet re-seat, the chain catches
    up), from the t lines."""
    out = set(range(0, SPAWN_GRACE + 1))
    last = None
    last_state = None
    last_up = None
    with open(trace) as f:
        for line in f:
            if not (line.startswith("t") and line[1:2].isdigit()):
                continue
            parts = line.split()
            tick = int(parts[0][1:])
            facing = None
            state = None
            up = None
            for kv in parts[1:]:
                if kv.startswith("facing="):
                    facing = kv[7:]
                elif kv.startswith("state="):
                    state = kv[6:]
                elif kv.startswith("up="):
                    a, b = kv[3:].split(",")
                    up = (float(a), float(b))
            if last is not None and facing != last:
                out.update(range(tick, tick + TURN_GRACE))
            if state != "cling":
                out.add(tick)
                out.add(tick + 1)
            elif last_state is not None and last_state != "cling":
                out.update(range(tick, tick + LAND_GRACE))
            # The body rounding a corner at its set rate reshapes the whole
            # silhouette in a frame; that is the turn, not a flicker.
            if up is not None and last_up is not None:
                import math
                turn = abs(math.atan2(last_up[0] * up[1] - last_up[1] * up[0], last_up[0] * up[0] + last_up[1] * up[1]))
                if turn > TURN_RATE:
                    out.update(range(tick, tick + 3))
            last = facing
            last_state = state
            last_up = up
    return out


def analyze_run(run_dir):
    trace = os.path.join(run_dir, "trace.log")
    if not os.path.exists(trace):
        return None
    pos = frame_positions(trace)
    turning = turn_ticks(trace)
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
    frag_events = []
    changes = []
    for (k0, t0, m0, size0), (k1, t1, m1, size1) in zip(masks, masks[1:]):
        if m0 is None or m1 is None or min(size0, size1) < MIN_MASK:
            continue
        change = best_change(m0, m1, size0)
        changes.append(change)
        if change > FLICKER and t1 not in turning:
            events.append((t1, round(change, 3)))
        fr = fragments(m1)
        if fr >= FRAGMENT and t1 not in turning:
            frag_events.append((t1, fr))
    changes.sort()
    med = changes[len(changes) // 2] if changes else 0.0
    p95 = changes[int(len(changes) * 0.95)] if changes else 0.0
    return {"frames": len(frames), "median": round(med, 3), "p95": round(p95, 3), "max": round(changes[-1], 3) if changes else 0.0,
            "events": events[:20], "count": len(events), "fragments": frag_events[:20], "fragment_count": len(frag_events)}


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
        print("%-36s frames %4d  median %.3f  p95 %.3f  max %.3f  events %d  fragments %d" % (
            name, r["frames"], r["median"], r["p95"], r["max"], r["count"], r["fragment_count"]))
    lines = ["# Frame flicker report", "",
             "Silhouette change between consecutive frames, as a share of the gecko's pixels, after alignment. "
             "Change events are frames over %.2f; fragment events are frames with %d px or more of silhouette "
             "not attached to its largest piece." % (FLICKER, FRAGMENT), "",
             "| run | frames | median | p95 | max | change events | fragment events |", "|---|---|---|---|---|---|---|"]
    for name, r in sorted(results.items(), key=lambda kv: (-(kv[1]["count"] + kv[1]["fragment_count"]), -kv[1]["max"])):
        lines.append("| %s | %d | %.3f | %.3f | %.3f | %d | %d |" % (
            name, r["frames"], r["median"], r["p95"], r["max"], r["count"], r["fragment_count"]))
    lines += ["", "## Events", ""]
    for name, r in sorted(results.items()):
        if r["events"]:
            lines.append("- %s change: %s" % (name, ", ".join("t%d (%.2f)" % e for e in r["events"])))
        if r["fragments"]:
            lines.append("- %s fragments: %s" % (name, ", ".join("t%d (%d px)" % e for e in r["fragments"])))
    with open(os.path.join(out_dir, "flicker.md"), "w") as f:
        f.write("\n".join(lines) + "\n")
    with open(os.path.join(out_dir, "flicker.json"), "w") as f:
        json.dump(results, f, indent=1)
    bad = sum(1 for r in results.values() if r["count"] or r["fragment_count"])
    print("runs %d, with flicker events %d -> %s" % (len(results), bad, os.path.join(out_dir, "flicker.md")))


if __name__ == "__main__":
    main()
