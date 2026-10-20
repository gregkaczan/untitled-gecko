#!/usr/bin/env python3
"""Writes levels/clutch.json: the first cave, its stations and their checks.

The clutch is one hand-laid cave the size of the world (1920x1080 px,
4 px cells), played from a sealed pocket at the bottom left to a crack
of light at the top. It is one scene in the suite's format (a base of
terrain ops, a spawn, scripts) plus two fields of its own: "lumps",
the loose stones, clay and sand the particle world spawns after the
terrain is built (the bitmap world has none), and "exit", the rect the
body centre must enter to finish. Each station is a further scene on
the same base with its own spawn, script and reach region, so the
headless suite checks the route the station is meant to be passed by.
Stations that need lumps (the roll, the plug) run in the particle
world only; their scripts are here for tools/record.sh.

Run from the repo root: python3 tools/gen_clutch.py
"""
import json
import os

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


def room(x0, y0, x1, y1):
    return ["room", x0, y0, x1 - x0, y1 - y0]


def fill(x0, y0, x1, y1):
    return ["fill", x0, y0, x1 - x0, y1 - y0]


def copper(x0, y0, x1, y1):
    return ["copper", x0, y0, x1 - x0, y1 - y0]


def water(x0, y0, x1, y1):
    return ["water", x0, y0, x1 - x0, y1 - y0]


def decor(name, x, y, where="floor"):
    """A stamp (tests/scene_builder.gd DECOR) on the first floor below
    (x, y), or hanging from the first ceiling above it."""
    return ["decor", name, x, y, where]


# The route, an S: the bottom band runs right, the middle band left,
# the top band right. World px, every edge on the 4 px grid.
#
# Bottom band: the hatch pocket, a thin wall, the hall, the shaft up.
HATCH = (100, 896, 244, 984)
HALL = (260, 804, 1100, 984)
SHAFT = (1072, 712, 1100, 804)
# Middle band: the landing and roll corridor (52 px tall: a boulder up
# to 48 px rolls, and leaves no room over it), the pit, the 32 px
# passage out of it with the cork 40 px in (a stone of about 40 cells:
# the tongue drags it out across the pit from the corridor and it falls
# in; walked into from the pit it is shoved along and drops into the
# dip, 24 px down, and is walked over there; a strike dents it, no
# more), the dip, the pinch, the turning chamber.
ROLL = (600, 660, 1156, 712)
PIT = (540, 664, 600, 776)
PLUG_IN = (460, 680, 540, 712)
PLUG = (380, 664, 460, 736)
PLUG_ON = (300, 680, 380, 712)
PINCH = (180, 696, 300, 712)
TURN = (60, 424, 180, 712)
SAND_POCKET = (400, 616, 440, 648)
# Top band: the corridor, the trough with its stepping stone (a jump
# from the bank with the key held flies about 167 px and lands on it;
# without the key, 100 px, into the water), a dead end up off the
# corridor's ceiling, the gulf, the crack (16 px: a squeeze entered
# nose first from the ceiling; a bite into the ceiling one hangs from
# takes the handhold away and drops the gecko in the particle world),
# the pocket of light.
TOP = (60, 344, 1500, 424)
TROUGH = (500, 424, 760, 524)
STONE = (620, 424, 700, 524)
DEAD_END_NECK = (800, 264, 840, 344)
DEAD_END = (740, 184, 900, 264)
GULF = (1000, 284, 1500, 424)
CRACK = (1240, 224, 1256, 284)
LIGHT = (1190, 164, 1310, 224)

TERRAIN = [
    ["blank"],
    room(*HATCH),
    ["hole", 130, 940, 36], ["hole", 214, 940, 36],
    room(*HALL),
    ["hole", 300, 844, 40], ["hole", 300, 944, 40],
    ["disc", 520, 984, 28],                     # a dome on the floor, a step
    fill(760, 952, 860, 984),                   # a shelf, 32 px: a step
    ["disc", 420, 804, 22], ["disc", 700, 804, 18], ["disc", 960, 804, 24],  # stalactites
    ["disc", 990, 984, 20],                     # another dome, clear of the shelf's foot
    copper(600, 792, 680, 804),                 # a vein along the ceiling
    room(*SHAFT),
    room(*ROLL),
    room(*PIT),
    room(*PLUG_IN),
    room(*PLUG),
    room(*PLUG_ON),
    room(*PINCH),
    room(*TURN),
    ["hole", 120, 464, 44],
    room(*SAND_POCKET),
    room(*TOP),
    ["disc", 300, 344, 24], ["disc", 820, 424, 20], ["disc", 1120, 284, 20], ["disc", 1400, 284, 24],
    room(*TROUGH),
    fill(*STONE),
    water(500, 432, 760, 524),
    copper(760, 480, 776, 504),                 # a vein under the water
    room(*DEAD_END_NECK),
    room(*DEAD_END),
    ["hole", 760, 224, 30], ["hole", 880, 224, 30],
    copper(740, 200, 752, 248),                 # the vein that leads nowhere
    room(*GULF),
    room(*CRACK),
    room(*LIGHT),
    # Dripstone, procedural from a seed (tests/scene_builder.gd): short
    # stalactites off the hall's and the gulf's ceilings, small
    # stalagmites on the hall's floor (stepped over), a column in the
    # dead end. None on the lines the stations run.
    ["stalactites", 300, 1000, 804, 5, 3, 16, 44],
    ["stalagmites", 560, 740, 984, 3, 4, 4, 8],
    ["stalactites", 1020, 1480, 284, 4, 5, 12, 32],
    ["column", 876, 184, 264, 20, 6],
    # Surfaces that will not be held: moss on the hall's left wall (the
    # first thing climbed, and it drops you: the lesson) and on the
    # turning chamber's right wall, so the left wall is the climb; a
    # curtain of drops down the turning chamber's right side from the
    # corridor's ceiling; the dead end's neck walls crumble, so the
    # lamp that leads nowhere drops you back; a gas pocket in the rock
    # between the hall and the roll corridor, where a straight dig up
    # from the hall would go.
    ["moss", 256, 804, 12, 100],
    ["moss", 180, 440, 12, 260],
    ["drips", 100, 170, 344, 1.5],
    ["crumble", 796, 268, 8, 72], ["crumble", 840, 268, 8, 72],
    ["gas", 820, 736, 56, 36],
    # Glowshrooms: lamps along the route (the sim's light pass), decor
    # that is ground to the gecko and goes with a bite. Off the lines
    # the stations walk at speed, or small where on them.
    decor("shroom_cluster", 330, 940),          # the hall, by the first holes
    decor("shroom_s", 890, 940),                # on the shelf
    decor("shroom_s", 800, 820, "ceiling"),     # hanging from the hall's ceiling
    decor("shroom_m", 570, 740),                # the pit's bottom
    decor("shroom_cluster", 100, 690),          # the turning chamber's floor
    decor("shroom_m", 300, 400),                # the top corridor
    decor("shroom_s", 560, 360, "ceiling"),     # hanging over the trough, lighting the water
    decor("shroom_cluster", 1320, 400),         # the gulf's floor
    decor("shroom_cluster", 770, 240),          # the dead end: a lamp that leads nowhere (clear of the neck below 800-840)
]

# Glow slugs (slug.gd): start points, each put on the nearest surface.
# Off the lines the tongue stations shoot along.
SLUGS = [
    [650, 810],                                           # the hall's ceiling
    [1000, 970],                                          # the hall's floor, by the far dome
    [70, 560],                                            # the turning chamber's left wall
    [1040, 290],                                          # the gulf's ceiling, left of the grapple's line
]

# ["boulder" | "clay" | "sand", x, y, r]: a lump of radius r resting on
# the first floor below (x, y), sand as a heap about (x, y).
LUMPS = [
    ["clay", 124, 940, 7], ["clay", 220, 940, 7],          # the other eggs
    ["boulder", 420, 940, 4], ["boulder", 600, 940, 5],   # pebbles, stepped over
    ["boulder", 700, 940, 8],                             # a stone, swallowed
    ["clay", 820, 940, 12],                               # a clump on the shelf, shoved off it, dragged and torn
    ["boulder", 950, 690, 18],                            # the roll: shoved into the pit
    ["boulder", 500, 690, 13],                            # the cork, in the passage across the pit
    ["sand", 420, 632, 24],                               # the pocket over the dip
    # Vines: hanging from the first ceiling above (x, y), length px;
    # climbable, shoved aside by a walk, and a hang of more than a
    # second or so snaps the anchor (main.gd). The gulf's reach down
    # toward the floor: another way up toward the crack.
    ["vine", 480, 830, 56],                               # the hall's ceiling
    ["vine", 920, 830, 40],
    ["vine", 1180, 300, 104],                             # the gulf, down to 388 (the floor is 424)
    ["vine", 1060, 300, 60],
    ["vine", 600, 360, 48],                               # over the trough
]

SPAWN = ["floor", 172, 940]
EXIT = list(LIGHT[:2]) + [LIGHT[2] - LIGHT[0], LIGHT[3] - LIGHT[1]]

SCRIPTS = {
    "idle": [step(13.0, Z)],
    # Out of the pocket: bites to the right through the wall, then on.
    "cl_hatch": [step(0.5, Z), step(2.5, R, chew=True), step(3.0, R)],
    "cl_hall": [step(9.0, R)],
    # To the hall's right wall, up the shaft, out onto the landing.
    "cl_shaft": [step(1.5, R), step(3.5, U), step(2.0, L)],
    # Along the corridor shoving the boulder into the pit, then on.
    "cl_roll": [step(0.5, Z), step(10.0, L)],
    # Down into the pit, across, up and into the passage.
    "cl_pit": [step(3.5, L), step(1.5, U), step(4.0, L)],
    # From the corridor at the pit's edge: both buttons on the cork
    # across the pit drag it out of the passage, and it falls in; then
    # down, over it, up the far wall with an up press (a left press at
    # its foot stops there) and into the passage.
    "cl_cork": [step(0.5, Z), step(4.0, Z, chew=True, lmb=True, aim=[-120, -4]), step(0.5, Z),
                step(3.5, L), step(1.5, U), step(4.0, L)],
    # Or two taps on it, which dent it; then the same way round, and the
    # cork is shoved along the passage into the dip and walked over.
    "cl_cork_strike": [step(0.5, Z), step(0.05, Z, lmb=True, aim=[-120, -4]), step(1.0, Z, aim=[-120, -4]),
                       step(0.05, Z, lmb=True, aim=[-120, 4]), step(1.0, Z),
                       step(3.5, L), step(1.5, U), step(6.0, L)],
    "cl_pinch": [step(5.0, L)],
    # To the chamber's left wall, up it to the corridor, along.
    "cl_turn": [step(1.0, L), step(4.0, U), step(3.0, R)],
    # Into the trough, along its bottom, up and over the stone, along
    # the far basin's bottom to its wall, up it and out.
    "cl_pool": [step(7.0, R), step(2.0, U), step(2.0, R)],
    # A leap from the bank onto the stone, a second from the stone to
    # the far bank; a short one lands in the water, and the swim to the
    # far wall and a press up the wall gets out all the same.
    "cl_leap": [step(0.5, R), step(0.3, R, jump=True), step(1.1, R), step(0.3, R, jump=True), step(2.5, R), step(2.0, U), step(2.0, R)],
    # The slow way to the crack: the gulf's far wall and its ceiling.
    "cl_gulf_climb": [step(3.5, R), step(2.0, U), step(2.5, L)],
    # The fast way: a held button on the ceiling beside the crack reels
    # the gecko up to it; a press up into the ceiling over the crack
    # enters it nose first, and the squeeze ends in the light.
    "cl_gulf_grapple": [step(0.5, Z), step(2.5, Z, lmb=True, aim=[-20, -140]), step(0.5, Z),
                        step(3.5, U), step(1.0, Z)],
    # From the ceiling beside the crack: the press up into it.
    "cl_exit": [step(0.5, Z), step(3.5, U), step(1.0, Z)],
}

scenes = {}


def add(name, spawn, scripts, reach=None, note=None, sim_only=False):
    sc = {"base": "clutch", "spawn": spawn, "scripts": scripts, "lumps": LUMPS, "exit": EXIT, "slugs": SLUGS}
    if reach:
        sc["reach"] = reach
    if note:
        sc["note"] = note
    if sim_only:
        sc["sim_only"] = True
    scenes[name] = sc


def inside(box, inset=0):
    x0, y0, x1, y1 = box
    return [x0 + inset, y0, x1 - inset, y1]


add("clutch", SPAWN, ["idle"], note="the first cave, played from the hatch pocket to the light")
add("clutch_hatch", SPAWN, ["cl_hatch"], reach=inside(HALL, 40), note="the pocket is sealed: bites through the 16 px wall into the hall")
add("clutch_hall", ["floor", 300, 940], ["cl_hall"], reach=[HALL[2] - 100, HALL[1], HALL[2], HALL[3]],
    note="the hall's floor: a dome, a shelf, stones and clay in the particle world")
add("clutch_shaft", ["floor", 1036, 940], ["cl_shaft"], reach=[SHAFT[0] - 100, ROLL[1], SHAFT[0], ROLL[3]],
    note="up the hall's right wall into the 28 px shaft and out onto the landing")
add("clutch_roll", ["floor", 1110, 700], ["cl_roll"], reach=inside(PIT), sim_only=True,
    note="the boulder in the corridor is shoved along into the pit, and the walk goes on over it")
add("clutch_pit", ["floor", 660, 700], ["cl_pit"], reach=inside(PLUG_ON, 10),
    note="the pit is 60 px wide: down its near wall, across, up the far one with an up press, into the 32 px passage, through the dip")
add("clutch_cork", ["floor", 620, 700], ["cl_cork"], reach=inside(PLUG, 10), sim_only=True,
    note="a stone corking the passage across the pit: dragged out on the tongue, it falls into the pit")
add("clutch_cork_strike", ["floor", 620, 700], ["cl_cork_strike"], reach=inside(PLUG_ON, 10), sim_only=True,
    note="or struck, which dents it, then shoved along into the dip and walked over")
add("clutch_pinch", ["floor", 360, 700], ["cl_pinch"], reach=inside(TURN, 10),
    note="a 16 px passage, 120 px long, squeezed through into the turning chamber")
add("clutch_turn", ["floor", 120, 700], ["cl_turn"], reach=[TOP[0], TOP[1], 400, TOP[3]],
    note="up the chamber's left wall, 288 px, onto the top corridor")
add("clutch_pool", ["floor", 440, 400], ["cl_pool"], reach=[TROUGH[2] + 40, TOP[1], GULF[0], TOP[3]],
    note="the trough: in from the bank, along the bottom under water, over the stone, up the far bank")
add("clutch_leap", ["floor", 440, 400], ["cl_leap"], reach=[TROUGH[2] + 40, TOP[1], GULF[0], TOP[3]],
    note="the trough is 260 px with a stone 120 px out: a running jump lands on it, a second clears the last 60 px; a short one swims")
add("clutch_gulf_climb", ["floor", 1100, 400], ["cl_gulf_climb"], reach=[CRACK[0] - 40, GULF[1], CRACK[2] + 40, GULF[1] + 30],
    note="the gulf's far wall and ceiling to the crack, the slow way")
add("clutch_gulf_grapple", ["floor", 1250, 400], ["cl_gulf_grapple"], reach=inside(LIGHT),
    note="a grapple to the ceiling beside the crack from the floor under it, a press up into the crack, the squeeze into the light")
# Spawned in place: a ceiling spawn under the crack would climb its air
# to the pocket. The slot scan is 20 px either side of the body and a
# slot touching the scan's end is passed over, so the body must be
# within about 10 px of the crack's middle.
add("clutch_exit", ["at", 1250, 300, 0, 1], ["cl_exit"], reach=inside(LIGHT),
    note="from the ceiling under the 16 px crack: a press up enters it nose first, the squeeze ends in the light")

out = {"bases": {"clutch": TERRAIN}, "scripts": SCRIPTS, "scenes": scenes}
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(root, "levels", "clutch.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(out, f, indent=1)
print("%d scenes, %d scripts -> %s" % (len(scenes), len(SCRIPTS), path))
