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
- Turning onto another surface (a wall that blocked the move, or one
  within 33 px that the held input points along) happens only when the
  input, read on that surface, would carry the body away from the one it
  is on, and never more than about 110 degrees at once. So up at a wall
  climbs it, right at a wall stops at it, and a boulder's underside is a
  dead end (jump onto it or chew). Once begun, a turn runs to completion.
- The body is laid along the surface link by link behind the head, so an
  inside corner bends it into an L instead of bunching it up.
- Input is projected onto the surface tangent: the key pressed moves the
  gecko that way on screen. Jump pushes away along the normal.
- Four feet, two per end, hold anchors on the rock; a trot keeps two
  planted. Fewer than two for 0.2 s and the gecko drops.
- Chewing bites a 13 px circle ahead in the input direction, anchored to
  the row the gecko stands on, so a tunnel comes out level.
- Tongue: held left button shoots it at the cursor, up to 320 px; on rock
  it anchors and reels the body in, which clings where it arrives.
  Release lets go. A tap instead spits a lobbed shot that blows a 20 px
  crater where it lands.
- Water (a still pool in the bitmap until the sim's readback brings its
  own): the gecko drifts where the input points with no gravity, cannot
  rise through the surface, and leaves by pushing into rock and clinging,
  or on the tongue. Walking in from the floor keeps it clinging, so it
  walks along the bottom; jump to swim.
- The head looks at the cursor, within about 100 degrees of the body line.

## Controls

WASD or arrows move, Space jumps, E or Shift chews. Left mouse: tap to
spit, hold for the tongue. Right mouse erases, middle fills, wheel sizes
the brush. R makes a new chamber, F1 toggles the debug overlay.

## Checking it without a hand on the keys

`GECKO_DEMO=climb|tunnel|swim|tongue` replaces the keyboard and mouse
with a scripted run (see `main.gd`; climb also builds a test pillar). `GECKO_TRACE=1` prints the body state per
physics tick and the gecko's screen position per frame; `tools/strip.sh`
turns movie-mode frames into a contact sheet cropped around the gecko.
