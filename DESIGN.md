# untitled-gecko

Movement spike for the gecko game. The design document lives in Claude Docs:
https://claude.ai/artifact/HeBpi84hMyeL581NWrvdvB

This repo answers the first question in that document's next steps: is
moving the gecko around a cave fun on its own? The world is the GPU
particle sim from untitled-idle-shooter (`sim.gd`, `shaders/*.glsl`),
read back every tick as one cell class per 4 px render pixel (air,
water, solid, lava) into the same 480x270 grid the gecko's queries run
on (`sim_map.gd`). The CPU bitmap stand-in (`cave_map.gd`) is still
there behind `GECKO_WORLD=bitmap`: it starts instantly, runs headless,
and the particle world is built from its generator. `chain.gd`,
`blob_layer.gd` and the metaball shader also come from the shooter.

Sim notes: every particle covers the full 1920x1080 (the shooter started
at a ground line), so the shaders carry offsets different from the
shooter's; `sim.gd` asserts the cell-class offset. Chewing and the brush
are melt capsules (particles deleted on the GPU), spit is a sim
explosion, a fill spawns particles. The local rendering device does not
exist headless, so sim runs need the window (movie mode is fine).

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
- The drawn body rides on a base that follows the body centre exactly
  along the surface and only slowly across it, so bumps do not bob the
  head.
- A blocked walking move retries from up to 9 px higher (a step over a
  loose pixel or a small ledge), but only if the ground is still right
  under the body afterward.
- Pressing away from a steep surface walks down it.
- Turns are decided from the cell that actually blocked the step, never
  from the cell the body rests on.

## Controls

WASD or arrows move, Space jumps, E or Shift chews. Left mouse: tap to
spit, hold for the tongue. Right mouse erases, middle fills, wheel sizes
the brush. R makes a new chamber, F1 toggles the debug overlay.

## Checking it without a hand on the keys

`GECKO_DEMO=climb|tunnel|swim|tongue|notch|crevice|traverse` replaces
the keyboard and mouse with a scripted run (see `main.gd`; climb builds
a test pillar, crevice a funnel). `GECKO_TRACE=1` prints the body state per
physics tick and the gecko's screen position per frame; `tools/strip.sh`
turns movie-mode frames into a contact sheet cropped around the gecko.
