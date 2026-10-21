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
    "walk_long": [step(10.0, R)],      # A squeeze walks at 52 px/s: 10 s covers 500 px of it
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
    # From under a hanging ball up its right side to the ceiling, back
    # under it and up its left side, and back once more.
    "ball_round": [step(2.5, R), step(5.0, L), step(3.0, R)],
    "jump_up": [step(0.5, Z), step(0.5, Z, jump=True), step(2.0, Z)],
    "cliff_jump": [step(1.3, R), step(0.3, R, jump=True), step(3.0, R)],
    "shaft": [step(3.0, D), step(3.0, U)],
    # Over the slot, down into it nose first, back up it and on.
    "slot_dive": [step(1.0, R), step(3.0, D), step(2.5, U), step(2.0, R)],
    # Up a wall to a hole in it, a press into the wall to enter the hole, out the far side.
    "window": [step(2.0, R), step(0.35, U), step(3.5, R), step(1.0, Z)],
    # Nothing at all: the idle animations play.
    "idle": [step(13.0, Z)],
    "swim_across": [step(6.0, R), step(2.5, U), step(1.5, R)],
    # Off the bank with a jump into deep water, then nothing: the gecko
    # must float where it is, not sink to the bottom.
    "float": [step(1.3, R), step(0.3, R, jump=True), step(0.4, R), step(6.0, Z)],
    # To a wall and up it, as long as the wall will have it.
    "climb_wall": [step(2.0, R), step(3.5, U), step(1.0, Z)],
    # To the wall, a bite at its foot (the aim within CHEW_REACH, so the
    # body does not creep after it), then the climb.
    "bite_climb": [step(1.6, R), step(0.5, Z, chew=True, aim=[12, -14]), step(3.5, U), step(0.5, Z)],
    # A jump into the pool and a swim to the right against whatever runs there.
    "swim_right": [step(1.3, R), step(0.3, R, jump=True), step(0.4, R), step(5.0, R)],
    # Across the pool, out on the far bank, then nothing; or back down to the water's edge, then nothing.
    "swim_out_rest": [step(6.0, R), step(2.5, U), step(1.5, R), step(4.0, Z)],
    "swim_out_back": [step(6.0, R), step(2.5, U), step(1.5, R), step(1.2, L), step(4.0, Z)],
    # A jump into the pool (a walk in clings to its floor), a swim to the
    # far bank, out onto it with an up-right press, then nothing; or back
    # down to the water's edge, then nothing.
    "swim_out": [step(1.3, R), step(0.3, R, jump=True), step(0.4, R), step(4.5, R), step(2.0, [1, -1]), step(0.5, R), step(3.0, Z)],
    # Cave 5: five seconds for the particle world's water to settle, left
    # from the spawn to the pool at the bottom left, a jump in, a swim,
    # then out to the right onto the pool's right bank and a wait at the
    # water's edge (the user's head jitter there, 2026-10-21).
    "pool_right": [step(5.0, Z), step(1.8, L), step(0.3, L, jump=True), step(1.5, L), step(3.0, R), step(1.0, [1, -1]), step(6.0, Z)],
    "swim_out_edge": [step(1.3, R), step(0.3, R, jump=True), step(0.4, R), step(4.5, R), step(2.0, [1, -1]), step(0.5, R), step(1.2, L), step(3.0, Z)],
    # A dig straight down, into whatever is sealed under the floor.
    "dig_pocket": [step(0.4, Z), step(2.4, Z, chew=True, aim=[0, 140]), step(2.0, Z)],
    # Digging is a bite every 0.4 s and a creep of 45 px/s behind it,
    # so a 100 px dig takes a few seconds.
    "dig_45": [step(0.4, Z), step(6.0, Z, chew=True, aim=[120, 120]), step(1.0, Z)],
    "dig_shaft": [step(0.4, Z), step(6.0, Z, chew=True, aim=[0, 140]), step(1.0, Z)],
    "dig_level": [step(0.4, Z), step(6.0, Z, chew=True, aim=[140, 0]), step(1.0, Z)],
    "dig_turns": [step(0.4, Z), step(4.0, Z, chew=True, aim=[120, 120]), step(4.0, Z, chew=True, aim=[140, -60]),
                  step(4.0, Z, chew=True, aim=[0, 140]), step(4.0, Z, chew=True, aim=[-140, 0]), step(0.5, Z)],
    # Over the sand bed to the trench, a dig down into it, a wait for
    # the sand to pour in round the body.
    "sand_dig": [step(7.5, R), step(4.0, Z, chew=True, aim=[0, 140]), step(3.0, Z)],
    # Under the hopper: a bite up into its plate (the cursor 18 px up,
    # within CHEW_REACH, so the body does not creep after it), a wait
    # while the sand pours over the body, then a walk out to the left.
    "hopper": [step(0.5, Z), step(1.0, Z, chew=True, aim=[0, -18]), step(6.0, Z), step(5.0, L), step(1.0, Z)],
}

BASES = {
    "room": [["blank"], ["room", 0, C, 1920, F - C]],
    "solid": [["blank"]],
}

scenes = {}


def add(name, terrain, spawn, scripts, base="room", end=None, state=None, note=None, reach=None, lumps=None, sim_only=False, end_up=None):
    sc = {"base": base, "terrain": terrain, "spawn": spawn, "scripts": scripts}
    if end:
        sc["end"] = end
    if end_up:
        # The surface the run must end on, as the body's up.
        sc["end_up"] = end_up
    if reach:
        sc["reach"] = reach
    if state:
        sc["state"] = state
    if note:
        sc["note"] = note
    if lumps:
        sc["lumps"] = lumps
    if sim_only:
        # Needs the particle world (loose grains, lava): the headless
        # suite skips it, tools/record.sh runs it.
        sc["sim_only"] = True
    scenes[name] = sc


def bed(kind, x0, x1, h):
    """A bed of kind (sand, clay) on the floor from x0 to x1, h px tall,
    its ends sloped a cell a row, so a heap of grains starts at rest."""
    ops = []
    for i in range(h // 4):
        inset = 4 * i
        ops.append([kind, x0 + inset, F - 4 * (i + 1), (x1 - x0) - 2 * inset, 4])
    return ops


# 1. Flat floor
add("flat", [], ["floor", 500, 700], ["traverse", "bounce", "idle"], end=[300, 700, 700, 900], state="cling")

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
# Single cells of rock in the air at body and head height along the walk, and
# scattered through a tunnel the body only just fits: crumbs, which the
# senses pass through and the body loosens (sim.gd's crumb threshold; in
# the bitmap world they are specks like any other).
add("crumbs_air", [["cell", x, F - 10 - (8 if (x // 40) % 2 else 0), 1] for x in range(700, 1320, 40)],
    ["floor", 500, 700], ["traverse"], state="cling", reach=[1000, 0, 1920, 1080], sim_only=True)
add("crumbs_tunnel", [["tunnel", 500, 600, 1500, 600, 11]] + [["cell", x, 600 + dy, 1] for x in range(700, 1320, 36) for dy in ((-6,), (0,), (6,))[(x // 36) % 3]],
    ["floor", 560, 600], ["traverse"], base="solid", state="cling", reach=[1100, 0, 1920, 1080], sim_only=True)
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
# A ball hanging from the ceiling, walked round on its underside: all
# convex, from the ceiling down one side, under it and up the other, and
# back. Filmed 2026-10-21: the body bunched into a folded lump on the way
# from the underside onto a side.
add("ball_hang", [["disc", 1000, 215, 70]], ["ceiling", 1000, 320], ["ball_round", "bounce"], state="cling",
    reach=[1060, 0, 1920, 240], note="a ball hanging from the ceiling, walked round from under it")
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


def ragged_run(y, x0, radii, seg, seed):
    """A chewed tunnel along y from x0 in segments of seg px, each ragged at its own radius."""
    return [["ragged", x0 + i * seg, y, x0 + (i + 1) * seg, y, r, seed + i] for i, r in enumerate(radii)]


# Jagged tunnels: throats the body must squeeze through opening into
# wider pockets and closing again, so the squeeze has to let go and take
# hold by turns (a straight ragged tunnel never asks that of it). A
# squeeze walks at 52 px/s, so the walk is long and the mark 360 px in:
# past two throats and two pockets.
add("tunnel_jagged", ragged_run(600, 500, [8, 14, 8, 14, 8, 14, 8, 8], 100, 21), ["floor", 540, 600], ["walk_long"], base="solid", state="cling", reach=[900, 0, 1920, 1080],
    note="throats 11 to 17 px tall and pockets 23 to 29 px, 100 px each, chewed")
add("tunnel_jagged_wide", ragged_run(600, 500, [8, 20, 8, 20, 8, 20, 8, 8], 100, 31), ["floor", 540, 600], ["walk_long"], base="solid", state="cling", reach=[900, 0, 1920, 1080],
    note="throats 11 to 17 px tall opening into chambers about 40 px tall, 100 px each, chewed")
add("tunnel_jagged_fine", ragged_run(600, 500, [8, 12] * 10, 40, 41), ["floor", 540, 600], ["walk_long"], base="solid", state="cling", reach=[900, 0, 1920, 1080],
    note="the radius alternating every 40 px between 8 and 12: walls of bumps the body rubs along")
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
add("pool", [["erase", 1000, F, 400, 100], ["water", 1000, F, 400, 100]], ["floor", 800, 700], ["swim_across", "swim_out"], state="cling",
    note="walk in, swim across, climb out on the far wall", reach=[1420, 0, 1920, 1080])
add("pool_bank_slope", [["erase", 1000, F, 400, 100], ["below", 1300, F + 100, 1400, F], ["water", 1000, F, 400, 100]],
    ["floor", 800, 700], ["swim_across", "swim_out_rest", "swim_out_back", "swim_out", "swim_out_edge"], state="cling", reach=[1300, 0, 1920, 1080],
    note="a pool with a sloping far bank: swim across and climb out on the slope (the user's water exit folded the body into a loop, 2026-10-21); swim_out_rest stops on the bank and waits, swim_out_back walks back down to the water's edge and waits (the head jittered there)")
# Deep water: a jump off the bank lands the gecko in it and it floats
# there, state swim, in the top half of a 160 px pool, instead of
# sinking to the bottom and clinging (the particle world's body pusher
# once shoved the water out of the body, so the swim read air and
# dropped the gecko tick by tick). Headless on the bitmap's still pool;
# tools/record.sh pool_drop:float runs it on the sim's water.
add("pool_drop", [["erase", 1000, F, 400, 160], ["water", 1000, F, 400, 160]], ["floor", 800, 700], ["float"], state="swim",
    end=[1000, F - 20, 1400, F + 80], note="a jump into deep water, then no input: floats in the top half of the pool, never the bottom")

# 13b. Surfaces that will not be held
add("moss_wall", [["fill", 1100, 300, 200, 500], ["moss", 1096, 560, 12, 200]], ["floor", 900, 700], ["climb_wall"],
    end=[880, 700, 1120, 800], note="a wall coated with moss from 560 to 760: the climb reaches the coat and drops; it ends on the floor")
# Thorns: a sharp plant on a rock face no foot holds, and a touch throws
# the body off (gecko.gd _prick): on a wall the climb ends below the
# patch, on a floor the walk never passes it.
add("thorn_wall", [["fill", 1100, 300, 200, 500], ["decor", "thorn", 1090, 640, "wall_right"]], ["floor", 900, 700], ["climb_wall"],
    end=[880, 660, 1130, 800], note="thorns on the wall at 640: the climb is thrown off them and ends below")
add("thorn_floor", [["decor", "thorn", 1000, 790, "floor"]], ["floor", 700, 700], ["walk_right"],
    end=[600, 700, 990, 800], note="thorns on the floor at 1000: the walk is thrown back and never passes")
add("moss_bitten", [["fill", 1100, 300, 200, 500], ["moss", 1096, 760, 12, 16]], ["floor", 900, 700], ["bite_climb"],
    reach=[1040, 0, 1120, 540], note="a wall with a coat of moss at its foot, one bite tall: the bite takes it and the climb goes on past it")
add("notch_climb", [["fill", 1100, 300, 200, 500]], ["floor", 900, 700], ["bite_climb"], reach=[1040, 0, 1120, 540],
    note="the bare wall with the same bites at its foot: the climb out of the notch they leave, and on up")
add("crumble_wall", [["fill", 1100, 300, 200, 500], ["crumble", 1100, 560, 8, 240]], ["floor", 900, 700], ["climb_wall"],
    end=[880, 700, 1130, 800], note="a wall whose lower face crumbles after a second's hold: the climber comes down with it")
add("pool_current", [["erase", 1000, F, 400, 160], ["water", 1000, F, 400, 160], ["current", 1000, F, 400, 160, -1, 0, 230]],
    ["floor", 800, 700], ["swim_right"], end=[1000, F - 20, 1200, F + 160],
    note="a pool running left at 230 px/s, faster than the swim's kick: a swim to the right gets nowhere")
add("gas_pocket", [["gas", 940, 840, 80, 40]], ["floor", 980, 700], ["dig_pocket"], reach=[880, 0, 1080, 720],
    note="a sealed pocket of gas under the floor: the dig down opens it and the burst throws the gecko up, its glow out")

# 14. Generated caves
for sd in (1, 2, 3, 4, 5, 6):
    add("cave_%d" % sd, [["cave", sd]], ["floor", 960, 540], ["traverse_long"] + (["pool_right"] if sd == 5 else []), base="solid")

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

# A hole at floor level through a wall 12 or 24 px thick: a door, not a
# tunnel. The passage opens straight into the room beyond.
for thick in (12, 24):
    for h in (12, 16):
        add("squeeze_door_%d_%d" % (thick, h), [["fill", 1000, C, thick, F - C - h]], ["floor", 800, 700], ["traverse"],
            state="cling", reach=[1000 + thick + 40, 0, 1920, 1080],
            note="a hole %d px tall at the floor through a wall %d px thick, squeezed through and back" % (h, thick))
# A hole 12 px tall through a 12 px wall with its sill 40 px up: climbed
# to, entered with a press into the wall, left on the far side.
add("squeeze_window_jagged", [["fill", 1000, C, 16, F - C], ["ragged", 988, F - 48, 1028, F - 48, 7, 13]], ["floor", 800, 700], ["window"],
    state="cling", reach=[1052, 0, 1920, 1080],
    note="a chewed hole 9 to 15 px tall through a 16 px wall, 48 px above the floor, its edges ragged: up the wall, a press into it enters the hole, out the far side")
add("squeeze_window_12", [["fill", 1000, C, 12, F - C - 52], ["fill", 1000, F - 40, 12, 40]], ["floor", 800, 700], ["window"],
    state="cling", reach=[1052, 0, 1920, 1080],
    note="a 12 px hole through a 12 px wall, 40 px above the floor: up the wall, a press into it enters the hole, out the far side")

# A chewed passage: bites of 5.5 to 8.5 px radius along a line, so the
# air is 11 to 20 px tall and its walls ragged, like one the player
# erased with the smallest brush. Squeezed through and back.
add("squeeze_ragged", [["ragged", 500, 600, 660, 600, 8, 5], ["room", 300, 540, 200, 68], ["room", 660, 540, 300, 68]],
    ["floor", 400, 600], ["traverse"], base="solid", state="cling", reach=[690, 0, 1920, 1080],
    note="a ragged chewed passage 11 to 20 px tall at floor level between two rooms, 160 px long")

# 17. A tunnel dug with the tongue: taps at a wall, each strike a
# 4 px dent (STRIKE_R plus the carve pad), the aim moved up and down a
# little as a player's cursor wanders, so the passage comes out ragged
# and about as tall as a strike is wide. Then a walk in to its end and
# a walk back out: the player got in only after widening the mouth and
# was stuck going out (2026-10-21).
TAP = 0.3        # Seconds a tap cycle takes: the tongue out, the strike, and back (900 px/s over up to 120 px)


def tap_dig(n, aims):
    out = []
    for i in range(n):
        a = aims[i % len(aims)]
        out.append(step(0.016, Z, lmb=True, aim=a))
        out.append(step(TAP - 0.016, Z, aim=a))
    return out


# The tongue fans out from the mouth, so the dents land within a pixel
# of each other at the wall's face and spread deeper in: the mouth is
# the narrowest part, a strike's own 10 px, however the aim wanders.
# The "mouth" variants add taps aimed short, which widen the mouth the
# way the player did.
MOUTH = {"": [], "mouth": [[40, -3], [40, 1]], "mouth_wide": [[40, -5], [40, 3], [40, -3], [40, 1]]}
for name, aims, tall in (("level", [[120, -3], [120, 0], [120, 3]], "10 at the mouth, 14 to 18 inside"),
                         ("low", [[120, 3], [120, 6], [120, 9]], "10 at the mouth, 12 to 16 inside"),
                         ("thin", [[120, 0], [120, 2]], "10 to 12"), ("wide", [[120, -5], [120, 0], [120, 5]], "10 at the mouth, 14 to 20 inside"),
                         # Rising and falling, as a player's tunnel does (the one of 2026-10-21 rose to the right).
                         ("rise", [[120, -16], [120, -13], [120, -10]], "10 to 16, rising a cell every 15"),
                         ("steep", [[120, -28], [120, -25], [120, -22]], "10 to 16, rising a cell every 8"),
                         ("fall", [[120, 12], [120, 15], [120, 18]], "10 to 16, falling a cell every 14")):
    for m, extra in MOUTH.items():
        sn = "tap_dig_" + name + ("_" + m if m else "")
        SCRIPTS[sn] = tap_dig(24, aims) + tap_dig(len(extra), extra) + [step(5.0, R), step(6.0, L), step(0.5, Z)]
        add("tongue_tunnel_" + name + ("_" + m if m else ""), [["fill", 1000, C, 920, F - C]], ["floor", 950, 700], [sn], state="cling",
            reach=[1060, 0, 1920, 1080], end=[0, 0, 990, 1080],
            note="a wall at 1000 dug into with 24 tongue taps, the aim over three heights, a passage %s px tall%s: walked in to its end and back out"
                 % (tall, ", its mouth widened by %d short taps" % len(extra) if extra else ""))

# 18. Idle on a wall and under a ledge, nothing pressed: the drawn body
# must hold its pixels (the player saw the body and head flick a pixel
# now and then while clinging to a wall with no input, 2026-10-21).
# Headless on the bitmap and, with tools/record.sh, on the sim's cells,
# which jiggle under the probe.
add("idle_wall", [["fill", 1000, 300, 300, 500]], ["wall_right", 980, 600], ["idle"], state="cling", end=[960, 560, 1000, 640],
    note="spawned on the left face of a wall, nothing pressed for 13 s: the body stays put, pixel for pixel")
add("idle_ledge", [["fill", 1000, 300, 300, 300], ["fill", 1000, 600, 60, 200]], ["wall_right", 980, 560], ["idle"], state="cling", end=[960, 520, 1000, 600],
    note="on a wall's face just above where a ledge steps back under it, nothing pressed for 13 s")
add("idle_rim", [["fill", 1000, 300, 300, 500]], ["wall_right", 980, 322], ["idle"], state="cling", end=[960, 290, 1000, 360],
    note="on a wall's face with the head just under its top corner (the screencast's pose), nothing pressed for 13 s")
# Into the 16 px slot of squeeze_slot_16, down to its shaft and part way
# back up, then nothing for 8 s with the body in the slot: the head just
# under the lip (slot_lip) and poking out above it (slot_out), the poses
# the player filmed the flicker in (2026-10-21).
SCRIPTS["slot_lip"] = [step(1.0, R), step(3.0, D), step(1.35, U), step(8.0, Z)]
SCRIPTS["slot_out"] = [step(1.0, R), step(3.0, D), step(1.6, U), step(8.0, Z)]
add("idle_slot", [["erase", 1000, F, 16, 60], ["erase", 1000, F + 60, 60, 60]], ["floor", 890, 700], ["slot_lip", "slot_out"], state="cling",
    reach=[1000, F + 90, 1060, F + 120], note="the 16 px slot: down it, back up to the lip or just past it, then nothing pressed for 8 s")
# A crack dug straight down with tongue taps (the mouth sits 15 px
# ahead of the body, so the aim is offset to keep the line vertical),
# entered with a down press, climbed back up to its lip, then nothing
# for 8 s: the player's crack, dug the same way.
for name, up_s in (("a", 1.2), ("b", 1.5), ("c", 1.8)):
    SCRIPTS["tap_shaft_" + name] = tap_dig(24, [[15, 120], [18, 120], [12, 120]]) + [step(0.12, R), step(0.4, Z), step(3.0, D), step(up_s, U), step(8.0, Z)]
    add("tongue_shaft_" + name, [], ["floor", 950, 700], ["tap_shaft_" + name], state="cling", reach=[930, F + 20, 1000, F + 120],
        note="a crack tapped straight down from the floor, entered with a down press, climbed back %.1f s toward its lip, then nothing pressed" % up_s)

# 14. Loose matter and the other materials, in the particle world only
# (sim_only: in the bitmap, sand is ground like rock). Sand and clay
# are loose grains that sleep until undermined, then pour; the gecko
# walks on them as on rock, bites into them, is buried by them, and
# burrows through them. Hard rock takes several bites, bedrock none.
add("sand_bed", bed("sand", 700, 1200, 64) + [["erase", 1300, F, 240, 100], ["sand", 1300, F, 240, 100], ["bedrock", 1300, F + 100, 240, 16]],
    ["floor", 500, 700], ["traverse_long", "sand_dig"], state="cling", sim_only=True, reach=[1500, 0, 1920, 1080],
    note="a bed of sand 64 px tall on the floor, then a trench of sand level with the floor on a plate of bedrock: walked over and back; sand_dig bites down into the trench and waits for the sand to pour in")
# The plate is one row of rock: a bite from the pocket's floor reaches
# 36 px up, its centre on that row, so the hole is the bite's width.
add("sand_hopper", [["fill", 820, 500, 360, 268], ["sand", 900, 548, 200, 216]],
    ["floor", 1000, 790], ["hopper"], state="cling", sim_only=True, reach=[0, 0, 800, 1080],
    note="a hopper of sand in a rock block over a 32 px pocket, a 4 px plate under it: a bite up from the pocket's floor opens the plate, the sand pours over the gecko, which burrows out to the left")
# A pool with a bank of sand on its far side (the particle world only:
# in the bitmap sand is rock): a jump in, a swim across, out onto the
# sand, back down to the water's edge, then nothing. The user's gecko
# jittered its head at a pool's edge in cave 5 once the water settled
# (2026-10-21); grains shifting under the feet are the suspect.
add("pool_sand_edge", [["erase", 1000, F, 400, 100], ["water", 1000, F, 400, 100]] + bed("sand", 1400, 1700, 40),
    ["floor", 800, 700], ["swim_out_edge", "swim_out"], state="cling", sim_only=True, reach=[1300, 0, 1920, 1080],
    note="a pool, then a bank of sand 40 px tall: swim across, out onto the sand, back to the water's edge, nothing pressed")
add("materials", bed("sand", 300, 560, 48) + bed("clay", 640, 900, 48)
    + [["erase", 980, F, 160, 60], ["water", 980, F, 160, 60],
       ["erase", 1220, F, 160, 60], ["lava", 1220, F, 160, 60],
       ["hard", 1460, F - 80, 80, 80], ["bedrock", 1600, F - 80, 80, 80],
       ["copper", 1760, F - 60, 24, 60], ["bedrock", 0, F + 160, 1920, 120]],
    ["floor", 150, 700], ["idle", "traverse_long"], state="cling", sim_only=True,
    lumps=[["boulder", 1850, 700, 10], ["clay", 1880, 700, 7]],
    note="every material in a row: a bed of sand, a bank of clay, a pool of water, a pool of lava (nothing to the gecko yet: it falls in and stands on the bottom), a block of hard rock, a block of bedrock, a vein of copper, a stone and a clump of clay, bedrock 160 px under the floor; the brush and the keys try them")

# 19. The switch between a floor and the ceiling over it (2026-10-21): a
# press straight away from the surface, with the other one within a
# leg's reach of the body centre (28 px), flips the body onto it where
# it stands, the feet stepping across. Bored tunnels 30 and 40 px tall
# (the user's passages were 28 to 34), and one 60 px tall, where the
# ceiling is out of reach and the press does nothing. The held press
# must not flip the body back and forth: once on the ceiling it points
# into the surface.
SCRIPTS["switch_up"] = [step(0.5, Z), step(0.3, U), step(1.5, Z)]
SCRIPTS["switch_up_hold"] = [step(0.5, Z), step(2.0, U)]
SCRIPTS["switch_back"] = [step(0.5, Z), step(0.3, U), step(1.0, Z), step(0.3, D), step(1.5, Z)]
SCRIPTS["switch_walk"] = [step(0.5, Z), step(0.3, U), step(0.5, Z), step(3.0, R), step(0.5, Z)]
SCRIPTS["switch_down"] = [step(0.5, Z), step(0.3, D), step(1.5, Z)]
for tall in (30, 40):
    bore = [["tunnel", 500, 600, 1500, 600, tall // 2]]
    add("switch_%d" % tall, bore, ["floor", 700, 600], ["switch_up", "switch_up_hold", "switch_walk"], base="solid", state="cling",
        end_up=[0, 1], reach=[700, 0, 1920, 1080],
        note="a bored tunnel %d px tall: a press up from its floor puts the gecko on its ceiling (held, it stays there; switch_walk walks on along the ceiling)" % tall)
    add("switch_%d_back" % tall, bore, ["floor", 700, 600], ["switch_back"], base="solid", state="cling", end_up=[0, -1], end=[650, 560, 750, 640],
        note="up to the ceiling, then down to the floor again")
    add("switch_%d_ceiling" % tall, bore, ["ceiling", 700, 600], ["switch_down"], base="solid", state="cling", end_up=[0, -1], end=[650, 560, 750, 640],
        note="spawned on the ceiling: a press down puts the gecko on the floor")
add("switch_60", [["tunnel", 500, 600, 1500, 600, 30]], ["floor", 700, 600], ["switch_up", "switch_up_hold"], base="solid", state="cling", end_up=[0, -1],
    end=[650, 560, 750, 680], note="a tunnel 60 px tall: the ceiling is out of reach, a press up does nothing")
# The settle latch (2026-10-21): a walk stopped in a jagged tunnel, then
# nothing pressed for 6 s. The body rattled there (the head 2 px along
# the tunnel every tick, the body laid behind it) and must come to rest.
SCRIPTS["walk_rest"] = [step(10.0, R), step(3.0, Z), step(0.5, R), step(3.0, Z), step(0.5, R), step(3.0, Z)]
add("rest_jagged", ragged_run(600, 500, [8, 14, 8, 14, 8, 14, 8, 8], 100, 21), ["floor", 540, 600], ["walk_rest"], base="solid", state="cling",
    reach=[1200, 0, 1920, 1080], note="walked 10 s into the jagged tunnel (where the head sawed 2 px a tick at rest), then nothing pressed for 3 s, twice more half a second on: the body comes to rest each time")

# Drops and jumps from height (2026-10-21: the user saw the body glide,
# land upside down off a big height and freeze in one pose in water).
# A tall chamber, floor at 960, a block from x 200 to 700 whose top is h
# over the floor; the gecko walks to its edge and jumps, then either
# steers on (leap_on) or lets go of the keys (leap_still), or steps off
# the edge with a jump straight up held at the lip (hop_off). The pool
# versions have deep water under the block's edge.
SCRIPTS["leap_on"] = [step(1.0, R), step(0.3, R, jump=True), step(4.0, R)]
SCRIPTS["leap_still"] = [step(1.0, R), step(0.3, R, jump=True), step(5.0, Z)]
SCRIPTS["leap_back"] = [step(1.0, R), step(0.3, R, jump=True), step(0.6, L), step(3.5, Z)]
TALL = [["erase", 60, 40, 1800, 920]]
for h in (64, 200, 440, 760):
    top = 960 - h
    add("drop_%d" % h, TALL + [["fill", 200, top, 500, h]], ["floor", 560, top - 40], ["leap_on", "leap_still"],
        base="solid", state="cling", end_up=[0, -1], reach=[720, 900, 1860, 1000],
        note="a block %d px over the floor: a jump off its edge, steered on, let go, or steered back toward the block; it lands feet first on the floor" % h)
    add("drop_%d_back" % h, TALL + [["fill", 200, top, 500, h]], ["floor", 560, top - 40], ["leap_back"], base="solid", state="cling",
        note="a block %d px over the floor: a jump off its edge, steered back toward the block mid-air; it catches the block's face or lands on the floor" % h)
    add("drop_%d_pool" % h, TALL + [["fill", 200, top, 500, h], ["erase", 700, 960, 900, 100], ["water", 700, 960, 900, 100]],
        ["floor", 560, top - 40], ["leap_still", "leap_on"], base="solid", state="swim",
        end=[700, 860, 1600, 1010] if h <= 200 else None,
        note="a block %d px over a deep pool: a jump off its edge into the water, then nothing or a swim on; let be it floats up, into the top half of the pool" % h)

out = {"bases": BASES, "scripts": SCRIPTS, "scenes": scenes}
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(root, "tests", "scenes.json")
with open(path, "w") as f:
    json.dump(out, f, indent=1)
print("%d scenes, %d scripts -> %s" % (len(scenes), len(SCRIPTS), path))
