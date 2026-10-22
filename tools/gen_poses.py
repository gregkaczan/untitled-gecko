#!/usr/bin/env python3
"""Writes starting pose animations under poses/ for the pose editor to
take over: the wake-up (poses/wake.json, what the game plays) and the
meerkat stand (poses/meerkat.json). A pose is built from the head and
the direction of each link in degrees (y down, as on the screen: 0 is
right, 90 down, 180 left, 270 up), then slid so one point sits at an
anchor, so the coil or the hips stay put while the neck changes. The
frames are checked against the floor (y = 0): a point's blob bottom,
y plus its radius, over 0 is in the rock, at blend quarters too.

    python3 -I tools/gen_poses.py          writes both heads and a new version each
    python3 -I tools/gen_poses.py wake     one of them
"""
import json, math, os, glob

LINK = 8.0
RADII = [7.0, 8.5, 8.5, 7.5, 5.5, 4.0, 3.2, 2.6, 2.2, 1.9]
STAND = [[15.0, -18.0], [7.0, -15.1], [-1.0, -12.5], [-9.0, -11.5], [-17.0, -9.2], [-25.0, -7.4], [-33.0, -6.4], [-41.0, -5.7], [-49.0, -5.2], [-57.0, -4.9]]
STAND_FEET = [[18.0, -4.5], [16.0, -4.5], [-22.0, -4.5], [-18.0, -4.5]]
FOOT_Y = -4.5
FOLD_ANGLE = 2.6   # radians: a link turning more than this between frames is pulled through (pose_anim.gd)


def chain(head, angles):
    pts = [list(head)]
    for a in angles:
        r = math.radians(a)
        pts.append([pts[-1][0] + LINK * math.cos(r), pts[-1][1] + LINK * math.sin(r)])
    return pts


def anchored(angles, idx, at):
    pts = chain((0.0, 0.0), angles)
    dx, dy = at[0] - pts[idx][0], at[1] - pts[idx][1]
    return [[x + dx, y + dy] for x, y in pts]


def on_floor(pts, clear=0.5):
    """Slid up or down so the lowest blob bottom sits clear px over the floor."""
    low = max(y + r for (x, y), r in zip(pts, RADII))
    return [[x, y - low - clear] for x, y in pts]


def blend(a, b, k):
    pa, pb = a["points"], b["points"]
    pts = [[pa[0][0] + (pb[0][0] - pa[0][0]) * k, pa[0][1] + (pb[0][1] - pa[0][1]) * k]]
    for i in range(1, len(pa)):
        va = (pa[i][0] - pa[i - 1][0], pa[i][1] - pa[i - 1][1])
        vb = (pb[i][0] - pb[i - 1][0], pb[i][1] - pb[i - 1][1])
        aa, ab = math.atan2(va[1], va[0]), math.atan2(vb[1], vb[0])
        d = (ab - aa + math.pi) % (2 * math.pi) - math.pi
        la, lb = math.hypot(*va), math.hypot(*vb)
        L = la + (lb - la) * k
        if abs(d) > FOLD_ANGLE:   # pulled through, as PoseAnim.blend
            ang = aa if k < 0.5 else ab
            L *= abs(math.cos(math.pi * k))
        else:
            ang = aa + d * k
        pts.append([pts[-1][0] + math.cos(ang) * L, pts[-1][1] + math.sin(ang) * L])
    feet = [[fa[0] + (fb[0] - fa[0]) * k, fa[1] + (fb[1] - fa[1]) * k] for fa, fb in zip(a["feet"], b["feet"])]
    la, lb = math.atan2(a["look"][1], a["look"][0]), math.atan2(b["look"][1], b["look"][0])
    d = (lb - la + math.pi) % (2 * math.pi) - math.pi
    ang = la + d * k
    return {"points": pts, "feet": feet, "look": [math.cos(ang), math.sin(ang)]}


def frame(points, feet, look, dur, tension=1.0, shut=False):
    L = math.hypot(*look) or 1.0
    return {"points": [[round(x, 2), round(y, 2)] for x, y in points],
            "feet": [[round(x, 2), round(y, 2)] for x, y in feet],
            "look": [round(look[0] / L, 3), round(look[1] / L, 3)], "dur": dur, "tension": tension, "shut": shut}


def report(name, frames):
    print(name)
    for i, f in enumerate(frames):
        low = max(y + r for (x, y), r in zip(f["points"], RADII))
        xs = [x for x, y in f["points"]]
        ys = [y for x, y in f["points"]]
        print("  %d  dur %.2f  blob bottom %+.1f  x %.0f..%.0f  y %.0f..%.0f  head (%.0f, %.0f)%s" % (
            i, f["dur"], low, min(xs), max(xs), min(ys), max(ys), f["points"][0][0], f["points"][0][1], "  shut" if f["shut"] else ""))
        if i + 1 < len(frames):
            worst = max(max(y + r for (x, y), r in zip(blend(f, frames[i + 1], k)["points"], RADII)) for k in (0.25, 0.5, 0.75))
            if worst > 0.0:
                print("     blend to %d dips %.1f px into the floor" % (i + 1, worst))


def write(name, frames):
    doc = {"name": name, "saved_at": "generated", "kind": "saved", "frames": frames}
    os.makedirs(f"poses/{name}", exist_ok=True)
    n = 1 + max([int(os.path.basename(p)[1:5]) for p in glob.glob(f"poses/{name}/v*.json")] or [0])
    for path in (f"poses/{name}.json", f"poses/{name}/v%04d.json" % n):
        with open(path, "w") as f:
            json.dump(doc, f, indent=" ")
    print("  wrote poses/%s.json and v%04d" % (name, n))


# --- The wake-up ---
# Asleep, seen from the side: a low loaf. The head rests on the floor at
# the front, the back humps up behind it and comes down to the rump at
# the back, and the tail is tucked forward along the flank, inside the
# body's outline, where its rim shows it lying over the body
# (gecko.gd _over_points). Waking, the tail is pulled through to lie
# behind (the fold rule in the blend). The hump (point 3) stays put
# while the neck changes.
LOAF = [195, 205, 180, 155, 150, -30, -10, 0, 0]
loaf = on_floor(anchored(LOAF, 0, (0.0, 0.0)))
lx = sum(x for x, y in loaf[:6]) / 6.0
loaf = [[x - lx - 6.0, y] for x, y in loaf]      # the loaf's body centred 6 px behind the body centre's column
hump = loaf[3]
tucked = [[loaf[1][0] + 2.0, -5.5], [loaf[1][0], -6.0], [hump[0] - 4.0, -5.5], [hump[0] - 6.0, -6.0]]
w0 = frame(loaf, tucked, (0.9, 0.45), 0.5, shut=True)
# Stir: the chin comes up a little, the eye still shut.
w1 = frame(anchored([170] + LOAF[1:], 3, hump), tucked, (0.95, 0.3), 0.45, shut=True)
# The eye opens, the head lifts off the floor.
w2 = frame(anchored([140, 190] + LOAF[2:], 3, hump), tucked, (1.0, 0.0), 0.35)
# The head up on its neck, leaning forward over the hump's front.
up_neck = anchored([120, 150] + LOAF[2:], 3, hump)
w3 = frame(up_neck, tucked, (0.9, -0.45), 0.4)
# A look round: back over the body, then down at the ground ahead.
w4 = frame(up_neck, tucked, (-0.5, -0.85), 0.5)
w5 = frame(up_neck, tucked, (0.9, 0.45), 0.4)
# Uncurling: the head high at the front, the back still arched, the
# tail come down off the back onto the floor behind; the feet out
# under the body.
cat = on_floor(anchored([125, 150, 170, 180, 165, 160, 165, 170, 175], 0, (0.0, 0.0)), 1.0)
cat = [[x - cat[2][0] - 1.0, y] for x, y in cat]  # the chest over the body centre's column
w6 = frame(cat, [[cat[1][0] + 4.0, FOOT_Y], [cat[1][0] + 2.0, FOOT_Y], [cat[3][0] - 2.0, FOOT_Y], [cat[3][0] - 4.0, FOOT_Y]], (0.9, -0.35), 0.35)
# The stretch: standing with the back arched up a little and the head high.
arch = [[x, y - (5.0 * math.sin(math.pi * (i + 0.5) / 7.0) if i < 7 else 0.0)] for i, (x, y) in enumerate(STAND)]
arch[0] = [arch[0][0] - 1.0, arch[0][1] - 2.0]
arch = anchored([math.degrees(math.atan2(arch[i][1] - arch[i - 1][1], arch[i][0] - arch[i - 1][0])) for i in range(1, 10)], 0, arch[0])
w7 = frame(arch, STAND_FEET, (0.95, -0.2), 0.3)
w8 = frame(STAND, STAND_FEET, (1.0, 0.0), 0.15)
wake = [w0, w1, w2, w3, w4, w5, w6, w7, w8]

# --- The meerkat stand ---
# Up on the hind legs, the body straight up from the back hip, the tail
# along the floor behind as a prop, the front feet tucked at the chest.
hip = (-8.0, -13.0)
m0 = frame(STAND, STAND_FEET, (1.0, 0.0), 0.3)
# Gathering: the back feet come forward under the hip, the front rises a touch.
gather = anchored([150, 158, 168, 164, 167, 173, 175, 176, 178], 3, hip)
m1 = frame(gather, [[12.0, FOOT_Y], [10.0, FOOT_Y], [-10.0, FOOT_Y], [-12.0, FOOT_Y]], (1.0, -0.1), 0.3)
# Rearing: the front half at fifty degrees, the front feet off the ground.
rear = anchored([125, 128, 135, 158, 170, 175, 178, 180, 180], 3, (-8.0, -14.0))
m2 = frame(rear, [[6.0, -15.0], [4.0, -16.0], [-5.0, FOOT_Y], [-11.0, FOOT_Y]], (0.9, -0.45), 0.35)
# Upright: the body vertical over the hip, the head at the top.
tall = anchored([100, 95, 92, 122, 165, 175, 178, 180, 180], 3, (-8.0, -15.0))
tall_feet = [[-1.0, -24.0], [-3.0, -25.0], [-5.0, FOOT_Y], [-11.0, FOOT_Y]]
m3 = frame(tall, tall_feet, (1.0, -0.15), 0.6)
m4 = frame(tall, tall_feet, (-0.6, -0.8), 0.5)
m5 = frame(tall, tall_feet, (0.9, 0.3), 0.4)
m6 = frame(rear, [[6.0, -15.0], [4.0, -16.0], [-5.0, FOOT_Y], [-11.0, FOOT_Y]], (0.9, -0.3), 0.3)
m7 = frame(STAND, STAND_FEET, (1.0, 0.0), 0.15)
meerkat = [m0, m1, m2, m3, m4, m5, m6, m7]

report("wake", wake)
report("meerkat", meerkat)
import sys
for name in (sys.argv[1:] or ["wake", "meerkat"]):
    write(name, wake if name == "wake" else meerkat)
