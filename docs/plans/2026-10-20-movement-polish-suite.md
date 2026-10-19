# Movement polish suite: plan

Date: 2026-10-20. Status: proposed, not started.

## Goal

Find and fix every terrain hiccup in the gecko's movement (sudden body
shifts, back-and-forth flips, foot flicker, stalls) with a hands-off,
repeatable suite: scripted scenes times scripted inputs give per-tick
traces and frames, a script turns those into metrics and a ranked
report, each fix re-runs the whole suite, and the suite stays as the
regression gate for later movement work (digging, creatures).

## What exists today

- `GECKO_DEMO=<name>` runs a scripted input (`DEMOS` in `main.gd`: steps
  of seconds, input vector, jump, chew, left button, aim). Scene tweaks
  per demo live in `_reset()` (climb pillar, gap holes, crevice funnel).
- `GECKO_TRACE=1` prints one `t<n>` line per physics tick (pos, head,
  hip, up, nearest rock distance, speed, state, and a debug string with
  blk/surf, grab, squeezed, the normal n and the input scalar s) and one
  `F<n>` line per drawn frame with the gecko's screen position.
- `GECKO_WORLD=bitmap` is the CPU map, runs headless, and has
  `generate(seed)`, `fill_rect`, `fill_circle`, `erase_circle`.
- Movie mode at a fixed fps, `tools/strip.sh` for contact sheets.
- Physics runs at 60 Hz. Movie runs so far used 30 fps, so one frame is
  two ticks. The suite records at `--fixed-fps 60`: one frame per tick.

## Part 1: scene library

A scene is terrain plus a spawn point plus an input script, all data in
one file (`tests/scenes.gd`, a dictionary) and picked with
`GECKO_SCENE=<name>`. Terrain starts from a blank slab (new
`CaveMap.blank()`: all rock, one big room carved out) and is built with
primitives: `fill_rect`, `erase_rect`, `fill_circle`, `erase_circle`,
`slope` (a filled polygon), `stairs` (n steps of h px), `specks` (seeded
loose cells), `cave(seed)` for the generated room. Cells are 4 px, so
steps and bumps come in multiples of 4.

Groups, each swept over sizes:

1. Flat floor: walk, turn round, stop and start. The baseline that must
   produce zero flags.
2. Slopes: 10, 20, 30, 45, 60, 75 degrees, up and down, both facings.
3. Steps: 4, 8, 12, 16 px, up and down.
4. Bumps and specks: single loose cells on a floor and a ceiling, one
   and two cell notches.
5. Convex corners: floor to wall, wall to ceiling, over a pillar top,
   over a boulder (circle).
6. Concave corners: floor into wall (climb), ceiling into wall, inside
   a box.
7. Overhangs: a shelf lip, a boulder underside (a dead end by design),
   a cave mouth.
8. Gaps: 8, 16, 24, 32, 40, 48 px, far side level, lower, higher.
9. Crevices and notches: funnels of several widths, slots just wider
   than the body (20, 24, 28 px), dead-end slots.
10. Ceilings: walk, ceiling with bumps, ceiling edge drop.
11. Tunnels: pre-dug level, 45 degree and vertical tunnels, walked both
    ways; ragged chewed walls (dig first, then walk back).
12. Landings: jumps onto flat, slope, wall, into a crevice; drops from
    edges onto each.
13. Water edges: walk in, climb out at banks of several slopes.
14. Generated caves: seeds 1 to N with a traverse script, as the random
    soak.

Input scripts reuse the demo step format, with canned ones: `walk_right`,
`walk_left`, `traverse` (right then left), `bounce` (alternating every
second), `climb`, diagonal holds, a jump at a given time, chew segments.
A scene names one or more scripts.

Scale: around 80 scene and script pairs at 6 s each. Trace-only
headless runs take a second or two each, so the whole suite is a few
minutes. Frames at 60 fps cost about 26 ms each to encode, so 360
frames add 10 s per run; record frames only for flagged runs, or on
demand with `FRAMES=1`.

## Part 2: harness

- `tools/suite.sh [filter]` runs every scene (or those matching the
  filter) headless on the bitmap with `GECKO_SCENE` and `GECKO_TRACE`,
  saving `runs/<scene>/<script>/trace.log`. With `FRAMES=1` it also
  writes movie frames at 60 fps next to the trace.
- `tools/analyze.py runs/` parses traces, computes the metrics below,
  writes `runs/report.md` (one row per run: metric hits with the worst
  tick, outcome pass or fail, sheet link) and `runs/report.json` for
  diffing. `--baseline <json>` marks regressions and improvements.
- `tools/sheet.sh <run> <tick> [span]` renders a contact sheet around a
  flagged tick from that run's frames, recording them first if missing.
- Trace extension in `gecko.gd`: add facing, the input scalar, grab and
  bridging flags, the four feet (pos, planted, stepping) and the chain
  heading to the `t` line. Print the tick number on the `F` line so the
  frame to tick mapping is exact.
- Determinism: bites and some foot choices use `randf`. Seed the RNG per
  run from `GECKO_SEED` so a flagged run reproduces exactly.

## Part 3: metrics

All from the trace, per tick. Thresholds start at the values below and
are calibrated so the flat floor and gentle slope scenes produce zero
flags before any other flag is trusted.

- Body jump: a clinging tick that moves the body centre more than 1.5
  times the walk step (walk speed over 60 Hz is about 2.2 px), outside
  a jump or landing tick.
- Back and forth: the along-surface velocity changes sign more than once
  in 10 ticks while the input holds one direction. This is the dance.
- Up flip: the up vector turns more than 20 degrees in one tick outside
  a committed grab; and up oscillation, the turn direction alternating
  more than three times in 30 ticks.
- State flicker: cling, air or swim toggling within 10 ticks.
- Stall: input held, no rock within one step along the tangent, and
  progress under 0.5 px per tick for 30 ticks.
- Foot flicker: a foot's planted flag toggling more than twice in 20
  ticks, or a foot moving more than 12 px in a tick while not stepping.
- Head jump: the chain head moving more than 6 px in a tick while
  clinging.
- Sink or float: the body centre closer than its radius to rock below,
  or farther than ride height plus 8 px, for more than 10 ticks while
  clinging.
- Frame flicker (only when frames exist): the pixel difference of the
  gecko crop between consecutive frames, centred on the traced screen
  position, normalised by body motion. Spikes mean legs, eye or blob
  popping, which the trace cannot see.
- Outcome: every scene states what should happen (crosses the gap,
  climbs the pillar, stops under the boulder, ends in region R). A run
  that does not reach it fails regardless of the other metrics.

## Part 4: iteration loop

1. Build the scenes and the harness, run the suite, commit the baseline
   report.
2. Take the worst metric class across all scenes (history says corners,
   notches and steps come first), read the trace and the sheet around
   the worst tick, find the mechanism, fix it in `gecko.gd`.
3. Re-run the whole suite, not just the scene. Accept the fix only when
   no other run regresses against the baseline.
4. Repeat until every run passes. Then tighten the thresholds once and
   repeat.
5. From then on the suite runs before any movement change is committed.

## Part 5: look-ahead heuristic

The suspicion is right: most back-and-forth comes from per-tick
decisions on noisy local data, where the nearest rock flips sides or a
ray misses by a pixel. The code already commits in places (the wall
grab, bridging, the crevice squeeze, the smoothed normal). The general
version:

- Sample the terrain ahead along the intended path: probe points every
  4 px out to 48 px along the tangent, each with a floor ray, and
  classify the shape ahead: flat, step up or down of h, slope, wall,
  gap of width w with the far floor height, overhang, dead end.
- Map the class and the held input to a movement mode: walk, step over
  (up to 8 px), climb, bridge, drop, wrap the corner, stop.
- Hysteresis: a mode holds for a minimum number of ticks or until its
  exit condition (the body has passed the feature), and switching needs
  the new class to persist for several consecutive ticks. That is what
  kills the dance.

Build it only after the suite shows which flips are mode flips. The
suite then measures the gain, and the stall metric shows whether the
hysteresis added lag.

## Order of work

1. Trace extension, 60 fps frame alignment, RNG seeding. Small.
2. Scene data format, `GECKO_SCENE` loader, blank slab and primitives.
3. The first 20 scenes: flat, slopes, steps, bumps, corners, gaps.
4. `suite.sh` and `analyze.py` with the trace metrics and the report.
   Run the baseline and look at sheets of flagged ticks to calibrate.
5. The remaining groups: crevices, overhangs, ceilings, tunnels,
   landings, water, cave seeds.
6. The frame flicker metric.
7. The fix loop, worst first, one commit per fix with the report delta.
8. The look-ahead heuristic, if the flip metrics point at mode flips.

## Notes and risks

- Rendering flicker (blob grid, feet drawing) and movement flicker are
  different problems. The frame metric catches both, the trace metrics
  tell them apart.
- The particle world cannot run headless. The suite runs on the bitmap,
  which is the same 4 px grid. A final smoke pass of a few scenes on the
  sim in movie mode closes the gap.
- The current digging work (cursor digging, the dig turn) is uncommitted.
  Commit it before the baseline so the baseline is on a known commit.
