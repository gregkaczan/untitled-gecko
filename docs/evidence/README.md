# Movement suite evidence, 2026-10-20

The state of the gecko's movement after the suite's fix loop, on commit
1700d55. Everything here comes from `tools/suite.sh` and the tools next
to it; nothing is hand-picked beyond the choice of which scenes to show.

## The suite

- `tests/report.md`: the headless run of all 95 scene-and-script pairs.
  Every run passes: no drawn-body or head jumps, no back-and-forth
  under a held press, no up flips or oscillation, no state flicker, no
  stalls, no foot flicker, no sinking, and every scene's reach region
  and end state met. Informational columns: `body*` (physics centre
  jumps the drawn body smooths over) and `stuck*` (a press into the
  rock that blocks the body, a wall by design).
- `tests/flicker.md`: the frame flicker report over the 60 fps
  recordings of the same 95 runs, one frame per physics tick. It
  measures how much the drawn silhouette changes between consecutive
  frames after alignment, and whether it breaks into fragments. Legs
  stepping change about 11 percent of the silhouette a frame; the
  report flags frames over 35 percent outside a turn, a jump or a
  landing, and frames with 8 px or more of silhouette detached from the
  rest. 83 of the 95 runs have no flagged frame at all. The other 12
  have one to five flagged frames each, of two kinds: the whole body
  reshaping in a frame at a corner it is rounding (the dead end of the
  bent tunnel, the dig's pitch down a shaft, a ceiling corner, a
  landing one frame past the grace), and the tail tip or a far foot
  drawn detached for one or two frames while the body rears up a wall
  or squeezes through a ragged tunnel. Both are listed under Events in
  the report with their ticks.
- `tests/baseline.json`: the first run of the suite, before any fix,
  which the reports diff against (31 of 95 passing then).

## The sheets

Each sheet is a whole run, one frame every 30 ticks (half a second),
cropped round the gecko at 2x, reading left to right and top to bottom.

| sheet | what it shows |
|---|---|
| flat_traverse | walking, turning round, walking back |
| slope_up_45_traverse | up a 45 degree slope head-first and back down it |
| slope_down_75_traverse_diag_left | over an edge, down a 75 degree face, back up it |
| step_up_24_traverse | a 24 px step walked up and back down |
| step_down_32_traverse_left | a 32 px step walked down, then climbed as a step |
| bump_row_traverse | a row of one and two cell bumps |
| boulder_70_traverse | reared up onto a boulder's side, over it, and back |
| pillar_climb_over | up a pillar's face, over its top, down the far face |
| box_box_round | floor, wall, ceiling and wall inside a closed box |
| gap_32_traverse | a 32 px gap bridged both ways |
| gap_48_gap_cross | a 48 px hole entered, its far wall climbed, and back |
| slot_24_slot | a 24 px slot: bridged, not entered (see below) |
| funnel_60_funnel | into a funnel to its narrow bottom and out again |
| ceiling_walk_traverse | walking on a ceiling both ways |
| ceiling_step_up_traverse | a ceiling that recedes: a convex corner upside down |
| tunnel_bend_traverse_long | a bored tunnel with a 45 degree bend, to its dead end, turned round, and back |
| tunnel_shaft_shaft | a 22 px shaft descended and climbed head-first |
| tunnel_45_ragged_traverse | a chewed 45 degree tunnel both ways |
| cliff_walk_traverse | over a cliff edge, down its face, along the floor, and back up |
| pool_swim_across | into a pool, along its bottom, out up the far wall, and back |
| cave_3_traverse_long | a generated cave: ridges, walls, a pool |
| dig_turns_dig_turns | chewing after the cursor: down-right, up-right, down, left |
| overhang_wedge_traverse | a ceiling slanting to the floor: a stop, no dance |
| corner_climb_wall_ceiling | floor to wall to ceiling in one motion |

## Known limits, by design

- A sheer wall taller than 32 px stops a sideways press; up climbs it.
  The scenes that need it press up.
- A slot narrower than the bridge width (36 px) is stepped over, never
  entered. Entering one takes a jump or a dig.
- A press square to a flat surface (up on a floor) does nothing, and
  neither does a press into the surface the gecko clings to.
- The 120 px boulder recedes less than a cell over the step height and
  reads as a wall; its scene presses up at it.

## Thresholds

The metrics flag anything beyond the body's set speeds: 4 px a tick for
the drawn body (the walk is 2.2), 6.5 for the head in the drawn body's
frame (its set speed is 6, and the frame turning under it adds a
little), 20 degrees a tick for up outside a committed turn, and so on;
see the top of `tools/analyze.py`. Two were raised during calibration
and are disclosed here: the drawn-body threshold from 3.5 to 4, since a
corner sweep legitimately reaches 3.5, and the head threshold from 6 to
6.5 for the reason above.
