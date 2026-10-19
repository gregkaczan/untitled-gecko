# untitled-gecko

Movement spike for the gecko game. The design document lives in Claude Docs:
https://claude.ai/artifact/HeBpi84hMyeL581NWrvdvB

This repo answers the first question in that document's next steps: is
moving the gecko around a cave fun on its own? The world is a CPU bitmap
(`cave_map.gd`) on the same 4 px grid the GPU particle sim renders at, so
the live sim's readback can replace it later without touching the gecko.
`chain.gd`, `blob_layer.gd` and the metaball shader come from
untitled-idle-shooter.

## Rules the gecko follows

- The body centre never enters rock. Every move is sub-stepped 1 px and
  stops at the first step that would bring it within 9 px of a cell.
  Stuck beats teleporting or over-correcting.
- Surface up comes from two rays cast down from the front and back of the
  body (the slope under it). At an edge, where a ray misses, the centroid
  of nearby rock takes over and swings the gecko round the corner.
- Walking into a wall turns up toward the wall's normal, so up then means
  climb. An overhang leaning back over the body is not climbed into.
- Input is projected onto the surface tangent: the key pressed moves the
  gecko that way on screen. Jump pushes away along the normal.
- Four feet, two per end, hold anchors on the rock; a trot keeps two
  planted. Fewer than two for 0.2 s and the gecko drops.
- Chewing bites a 13 px circle ahead in the input direction, anchored to
  the row the gecko stands on, so a tunnel comes out level.

## Controls

WASD or arrows move, Space jumps, E or Shift chews. Mouse: left erases,
right fills, wheel sizes the brush. R makes a new chamber, F1 toggles the
debug overlay.

## Checking it without a hand on the keys

`GECKO_DEMO=climb` or `GECKO_DEMO=tunnel` replaces the keyboard with a
scripted run (see `main.gd`). `GECKO_TRACE=1` prints the body state per
physics tick and the gecko's screen position per frame; `tools/strip.sh`
turns movie-mode frames into a contact sheet cropped around the gecko.
