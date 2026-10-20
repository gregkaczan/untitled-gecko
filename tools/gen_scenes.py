#!/usr/bin/env python3
"""Writes tests/scenes.json: the movement suite's scenes and scripts.

Coordinates are world px (1920x1080, 4 px cells). The "room" base is a
chamber with its floor at y=800 and ceiling at y=160, rock below and
above, so digs have rock to go into and ceilings are reachable.
Run from the repo root: python3 tools/gen_scenes.py
"""
import json
import math
import os

F = 800          # Floor line of the room base
C = 160          # Ceiling line of the room base
R = [1, 0]
L = [-1, 0]
U = [0, -1]
D = [0, 1]
Z = [0, 0]


def step(secs, inp, jump=False, chew=False, lmb=False, aim=None):
    s = [secs, inp, jump, chew, lmb]
    if aim is not None:
        s.append(aim)
    return s


SCRIPTS = {
    "walk_right": [step(5.0, R)],
    "walk_left": [step(5.0, L)],
    "traverse": [step(4.5, R), step(4.5, L)],
    "traverse_left": [step(4.5, L), step(4.5, R)],
    "traverse_diag": [step(4.5, [1, -1]), step(4.5, [-1, 1])],
    "traverse_diag_left": [step(4.5, [-1, 1]), step(4.5, [1, -1])],
    "traverse_long": [step(9.0, R), step(9.0, L)],
    "bounce": [step(1.0, R), step(1.0, L)] * 3,
    "climb_over": [step(1.5, R), step(3.0, U), step(2.5, R), step(3.0, D), step(1.5, R)],
    "wall_ceiling": [step(2.0, R), step(6.0, U), step(4.0, L), step(2.0, R)],
    "box_round": [step(2.0, R), step(2.5, U), step(3.0, L), step(3.0, D), step(2.0, R)],
    "slot": [step(1.4, R), step(2.5, D), step(1.0, R), step(2.5, U), step(2.0, R)],
    "funnel": [step(1.2, R), step(1.5, [1, 1]), step(1.0, D), step(1.0, L), step(2.0, U), step(1.5, [-1, -1]), step(1.5, L)],
    "jump_right": [step(1.0, R), step(0.4, R, jump=True), step(3.0, R)],
    # Into the hole down its near wall and along the bottom (3.2 s covers
    # 200 px of floor, 120 px of wall and the bottom), up the far wall,
    # over its edge, and the same back.
    "gap_cross": [step(3.2, R), step(2.0, U), step(1.5, R), step(3.2, L), step(2.0, U), step(1.5, L)],
    "boulder_big": [step(1.6, R), step(1.0, U), step(3.0, R), step(3.0, L), step(1.0, U), step(3.0, L)],
    "jump_up": [step(0.5, Z), step(0.5, Z, jump=True), step(2.0, Z)],
    "cliff_jump": [step(1.3, R), step(0.3, R, jump=True), step(3.0, R)],
    "shaft": [step(3.0, D), step(3.0, U)],
    # Over the slot, down into it nose first, back up it and on.
    "slot_dive": [step(1.0, R), step(3.0, D), step(2.5, U), step(2.0, R)],
    "swim_across": [step(6.0, R), step(2.5, U), step(1.5, R)],
    "dig_45": [step(0.4, Z), step(3.0, Z, chew=True, aim=[120, 120]), step(1.0, Z)],
    "dig_shaft": [step(0.4, Z), step(3.0, Z, chew=True, aim=[0, 140]), step(1.0, Z)],
    "dig_level": [step(0.4, Z), step(3.0, Z, chew=True, aim=[140, 0]), step(1.0, Z)],
    "dig_turns": [step(0.4, Z), step(2.0, Z, chew=True, aim=[120, 120]), step(2.0, Z, chew=True, aim=[140, -60]),
                  step(2.0, Z, chew=True, aim=[0, 140]), step(2.0, Z, chew=True, aim=[-140, 0]), step(0.5, Z)],
}

BASES = {
    "room": [["blank"], ["room", 0, C, 1920, F - C]],
    "solid": [["blank"]],
}

scenes = {}


def add(name, terrain, spawn, scripts, base="room", end=None, state=None, note=None, reach=None):
    sc = {"base": base, "terrain": terrain, "spawn": spawn, "scripts": scripts}
    if end:
        sc["end"] = end
    if reach:
        sc["reach"] = reach
    if state:
        sc["state"] = state
    if note:
        sc["note"] = note
    scenes[name] = sc


# 1. Flat floor
add("flat", [], ["floor", 500, 700], ["traverse", "bounce"], end=[300, 700, 700, 900], state="cling")

# 2. Slopes, up from the floor and down from the plateau
for ang in (10, 20, 30, 45, 60, 75):
    run = {10: 800, 20: 700, 30: 600, 45: 400, 60: 230, 75: 100}[ang]
    rise = round(run * math.tan(math.radians(ang)))
    top = F - rise
    terrain = [["below", 700, F, 700 + run, top], ["fill", 700 + run, top, 1920 - 700 - run, rise + 300]]
    # 4.5 s of walking covers about 580 px: the long shallow slopes are
    # not climbed to the top, so the target is 300 px up them at most.
    part = min(round(run * 0.6), 200)
    # A plain right press projects to a third of walking speed on a 75
    # degree face, by design (input along the surface), so the steep
    # slopes are walked with a diagonal press, as a player would.
    steep = ang >= 60
    add("slope_up_%d" % ang, terrain, ["floor", 500, 700], ["traverse_diag" if steep else "traverse"], state="cling",
        reach=[700 + part, 0, 1920, 1080])
    add("slope_down_%d" % ang, terrain, ["floor", 700 + run + 200, top - 200], ["traverse_diag_left" if steep else "traverse_left"],
        state="cling", reach=[0, 0, 700 + run - part, 1080],
        note="spawned 200 px up the plateau, so the walk left goes down the slope and back up it")

# 3. Steps up and down
for h in (4, 8, 12, 16, 24, 32, 48):
    terrain = [["fill", 900, F - h, 1020, h]]
    reach_up = [950, 0, 1920, 1080] if h <= 32 else None
    add("step_up_%d" % h, terrain, ["floor", 700, 700], ["traverse"], state="cling", reach=reach_up,
        note=None if h <= 32 else "a wall, not a step: pressing right stops at it by design, up climbs it")
    add("step_down_%d" % h, terrain, ["floor", 1100, 700], ["traverse_left"], state="cling", reach=[0, 0, 850, 1080])

# 4. Bumps, specks and notches
PAST = [1100, 0, 1920, 1080]
add("specks_floor", [["specks", 3, 600, 1400, F - 2, 14]], ["floor", 500, 700], ["traverse"], state="cling", reach=[1000, 0, 1920, 1080])
add("notch_1", [["erase", 1000, F, 4, 4]], ["floor", 800, 700], ["traverse"], state="cling", reach=PAST)
add("notch_2", [["erase", 1000, F, 8, 4]], ["floor", 800, 700], ["traverse"], state="cling", reach=PAST)
add("notch_deep", [["erase", 1000, F, 4, 12]], ["floor", 800, 700], ["traverse"], state="cling", reach=PAST)
add("notch_wide_deep", [["erase", 1000, F, 12, 12]], ["floor", 800, 700], ["traverse"], state="cling", reach=PAST)
add("bump_2x2", [["fill", 1000, F - 8, 8, 8]], ["floor", 800, 700], ["traverse"], state="cling", reach=PAST)
add("bump_row", [["fill", 1000, F - 4, 4, 4], ["fill", 1016, F - 8, 4, 8], ["fill", 1040, F - 4, 8, 4]],
    ["floor", 800, 700], ["traverse"], state="cling", reach=PAST)

# 5. Convex corners
add("pillar", [["fill", 1000, 500, 120, 300]], ["floor", 800, 700], ["climb_over"], state="cling",
    end=[1130, 700, 1700, 900])
add("pillar_thin", [["fill", 1000, 560, 24, 240]], ["floor", 800, 700], ["climb_over"], state="cling", reach=[1060, 0, 1920, 1080])
# A boulder whose side leans back within the step height is climbed by
# a plain walk; the 120 px one recedes less than a cell over that height
# and counts as a wall, so its script presses up at it, as a player would.
for r in (30, 70, 120):
    add("boulder_%d" % r, [["disc", 1000, F, r]], ["floor", 700, 700], ["traverse" if r < 120 else "boulder_big"], state="cling",
        reach=[1000 + r + 40, 0, 1920, 1080])
add("shelf_lip", [["fill", 1000, 600, 920, 40]], ["floor", 1500, 500], ["traverse_left"], state="cling",
    note="walks off the shelf edge, round the lip onto the underside, and back")

# 6. Concave corners
add("corner_climb", [], ["floor", 1700, 700], ["wall_ceiling"], state="cling", note="floor to wall to ceiling", reach=[0, 0, 1920, 220])
add("box", [["room", 700, 500, 300, 300], ["fill", 700, 500, 300, 20], ["fill", 700, 500, 20, 300], ["fill", 980, 500, 20, 300],
            ["fill", 0, C, 1920, F - C], ["room", 720, 520, 260, 260]],
    ["floor", 800, 600], ["box_round"], base="solid", state="cling", note="an enclosed box, all four walls", reach=[720, 520, 980, 560])

# 7. Overhangs and dead ends
add("overhang_wedge", [["above", 1100, F, 1500, C]], ["floor", 700, 700], ["traverse"], state="cling",
    note="a ceiling slanting down to the floor: a dead end, the gecko must stop without dancing")
add("overhang_shelf_under", [["fill", 900, 700, 1020, 24]], ["floor", 700, 760], ["traverse"], state="cling",
    note="a low shelf 76 px over the floor", reach=[1250, 0, 1920, 1080])

# 8. Gaps
# Gaps up to 32 px are bridged with a plain walk; wider ones are entered,
# and the 120 px far wall needs an up press to climb out, so those get
# the gap_cross script.
for w in (8, 16, 24, 32, 40, 48, 64):
    add("gap_%d" % w, [["erase", 1000, F, w, 120]], ["floor", 800, 700], ["traverse" if w <= 32 else "gap_cross"], state="cling",
        reach=[1000 + w + 40, 0, 1920, 1080])
for w in (16, 32, 48):
    # A far side 24 px lower is out of the bridge's reach: the hole is
    # entered and its far wall climbed with an up press.
    add("gap_lower_%d" % w, [["erase", 1000, F, w, 120], ["erase", 1000 + w, F, 920, 24]], ["floor", 800, 700],
        ["traverse" if w <= 16 else "gap_cross"], state="cling", reach=[1000 + w + 40, 0, 1920, 1080])
    add("gap_higher_%d" % w, [["erase", 1000, F, w, 120], ["fill", 1000 + w, F - 16, 920, 16]], ["floor", 800, 700],
        ["traverse" if w <= 32 else "gap_cross"], state="cling", reach=[1000 + w + 40, 0, 1920, 1080])

# 9. Crevices and slots
for w in (40, 60, 90):
    add("funnel_%d" % w, [["funnel", 1000, F, w, 100]], ["floor", 900, 700], ["funnel"], state="cling")
for w in (20, 24, 28, 36):
    add("slot_%d" % w, [["erase", 1000, F, w, 120]], ["floor", 900, 700], ["slot"], state="cling", reach=[1000 + w + 40, 0, 1920, 1080])

# 10. Ceilings
add("ceiling_walk", [], ["ceiling", 800, 300], ["traverse", "bounce"], state="cling")
add("ceiling_specks", [["specks", 5, 600, 1400, C + 2, 14]], ["ceiling", 500, 300], ["traverse"], state="cling", reach=[1000, 0, 1920, 1080])
add("ceiling_step_up", [["erase", 1000, C - 60, 920, 60]], ["ceiling", 800, 300], ["traverse"], state="cling",
    note="the ceiling recedes to the right: a convex corner upside down", reach=PAST)
add("ceiling_step_down", [["fill", 1000, C, 920, 24]], ["ceiling", 800, 300], ["traverse"], state="cling",
    note="the ceiling comes down 24 px to the right: a step, upside down", reach=PAST)

# 11. Tunnels
add("tunnel_level", [["tunnel", 500, 600, 1500, 600, 11]], ["floor", 560, 600], ["traverse"], base="solid", state="cling", reach=[1100, 0, 1920, 1080])
add("tunnel_ragged", [["ragged", 500, 600, 1500, 600, 11, 7]], ["floor", 560, 600], ["traverse"], base="solid", state="cling", reach=[1100, 0, 1920, 1080])
add("tunnel_45", [["tunnel", 500, 400, 1000, 900, 11]], ["floor", 520, 420], ["traverse"], base="solid", state="cling", reach=[0, 800, 1920, 1080])
add("tunnel_45_ragged", [["ragged", 500, 400, 1000, 900, 11, 11]], ["floor", 520, 420], ["traverse"], base="solid", state="cling", reach=[0, 800, 1920, 1080])
add("tunnel_shaft", [["tunnel", 1000, 300, 1000, 900, 11], ["tunnel", 1000, 900, 1300, 900, 11]],
    ["at", 1000, 330, 1, 0], ["shaft"], base="solid", state="cling", note="a 22 px shaft, spawned on its left wall", reach=[0, 650, 1920, 1080])
add("tunnel_bend", [["tunnel", 500, 600, 900, 600, 11], ["tunnel", 900, 600, 1200, 900, 11], ["tunnel", 1200, 900, 1600, 900, 11]],
    ["floor", 560, 600], ["traverse_long"], base="solid", state="cling", reach=[1450, 0, 1920, 1080])
add("tunnel_up_bend", [["tunnel", 500, 800, 900, 800, 11], ["tunnel", 900, 800, 1200, 500, 11], ["tunnel", 1200, 500, 1600, 500, 11]],
    ["floor", 560, 800], ["traverse_long"], base="solid", state="cling", reach=[1450, 0, 1920, 560])

# 12. Landings and drops
add("jump_flat", [], ["floor", 700, 700], ["jump_right", "jump_up"], state="cling")
add("jump_wall", [["fill", 1100, 300, 200, 500]], ["floor", 900, 700], ["jump_right"], state="cling", reach=[1060, 0, 1920, 760])
add("cliff_walk", [["erase", 1000, F, 920, 200]], ["floor", 800, 700], ["traverse"], state="cling",
    note="the floor ends: the gecko wraps the edge, walks down the face and along the lower floor, then back up", reach=[1010, 950, 1920, 1080])
add("cliff_jump", [["erase", 1000, F, 920, 200]], ["floor", 800, 700], ["cliff_jump"], state="cling", reach=[1010, 950, 1920, 1080])
add("drop_funnel", [["funnel", 1200, F, 90, 100]], ["floor", 1000, 700], ["cliff_jump"], state="cling")

# 13. Water
add("pool", [["erase", 1000, F, 400, 100], ["water", 1000, F, 400, 100]], ["floor", 800, 700], ["swim_across"], state="cling",
    note="walk in, swim across, climb out on the far wall", reach=[1420, 0, 1920, 1080])
add("pool_bank_slope", [["erase", 1000, F, 400, 100], ["below", 1300, F + 100, 1400, F], ["water", 1000, F, 400, 100]],
    ["floor", 800, 700], ["swim_across"], state="cling", reach=[1420, 0, 1920, 1080])

# 14. Generated caves
for sd in (1, 2, 3, 4, 5, 6):
    add("cave_%d" % sd, [["cave", sd]], ["floor", 960, 540], ["traverse_long"], base="solid")

# 15. Digging after the cursor
add("dig_45", [], ["floor", 700, 700], ["dig_45"], note="45 degrees down-right from the floor", reach=[0, 900, 1920, 1080])
add("dig_shaft", [], ["floor", 700, 700], ["dig_shaft"], note="straight down from the floor", reach=[0, 900, 1920, 1080])
add("dig_level_wall", [["fill", 900, 300, 1020, 500]], ["floor", 700, 700], ["dig_level"], note="level into a wall", reach=[1000, 0, 1920, 1080])
add("dig_turns", [], ["floor", 600, 700], ["dig_turns"], note="down-right, up-right, down, back left")

# 16. Squeezes: passages narrower than the body
for h in (12, 16):
    # A slab from the ceiling to h above the floor, 100 px thick: the only
    # way on is the passage h tall under it.
    add("squeeze_low_%d" % h, [["fill", 1000, C, 100, F - C - h]], ["floor", 800, 700], ["traverse"], state="cling",
        reach=[1140, 0, 1920, 1080], note="a passage %d px tall under a slab, squeezed through and back" % h)
for w in (12, 16):
    # A slot w wide through 60 px of floor into a 60 px shaft below it,
    # flush on the left, with a floor: a down press over the slot enters
    # it nose first, up climbs back out through it.
    add("squeeze_slot_%d" % w, [["erase", 1000, F, w, 60], ["erase", 1000, F + 60, 60, 60]], ["floor", 890, 700], ["slot_dive"],
        state="cling", reach=[1000, F + 90, 1060, F + 120], end=[1020, F - 60, 1400, F],
        note="a %d px slot in the floor entered with a down press, to the shaft floor below, and back out" % w)

# A chewed passage: bites of 5.5 to 8.5 px radius along a line, so the
# air is 11 to 20 px tall and its walls ragged, like one the player
# erased with the smallest brush. Squeezed through and back.
add("squeeze_ragged", [["ragged", 500, 600, 660, 600, 8, 5], ["room", 300, 540, 200, 68], ["room", 660, 540, 300, 68]],
    ["floor", 400, 600], ["traverse"], base="solid", state="cling", reach=[690, 0, 1920, 1080],
    note="a ragged chewed passage 11 to 20 px tall at floor level between two rooms, 160 px long")

out = {"bases": BASES, "scripts": SCRIPTS, "scenes": scenes}
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(root, "tests", "scenes.json")
with open(path, "w") as f:
    json.dump(out, f, indent=1)
print("%d scenes, %d scripts -> %s" % (len(scenes), len(SCRIPTS), path))
