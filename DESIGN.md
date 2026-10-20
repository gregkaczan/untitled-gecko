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
shooter's; `sim.gd` asserts the cell-class and bond offsets. Chewing
and the brush are melt capsules (particles deleted on the GPU), a fill
spawns particles. Loose lumps (boulders, stones, clumps of clay) are
chunks: one particle per cell, each bonded to its eight lattice
neighbours by a distance constraint (a bond record per particle at the
buffer's tail, solved with the density constraints in `pbd_delta.glsl`,
mates holding each other by their bonds alone and never drawn into
what they touch). A lump sleeps until a mate moves, falls as one,
comes apart where bonds are broken or stretched past their limit (clay
sooner than stone), and its cells read back as 16 + the chunk id, so
the CPU can tell a lump from the ground and trace the piece the tongue
is stuck to. The tongue's drag and the walk's shove (a pull on a whole
chunk), a swallow and a strike's break are capsule slots of their own.
The local rendering
device does not exist headless, so sim runs need the window (movie
mode is fine, on a virtual display too).

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
  climbs it, right at a sheer wall stops at it, and a boulder's underside
  is a dead end (jump onto it or chew). Once begun, a turn runs to
  completion, and the surface it lands on is held for a quarter second
  against any other reading.
- A wall no taller than 32 px over the floor, or a face that leans back
  within that height (a boulder's side), is a step: pressing into it
  turns the body onto its face and the press carries it up and over,
  toward the step's free end, which is world down for a step in a
  ceiling.
- The surface normal is followed fast while it keeps turning the same
  way (a corner being rounded) and blended in slowly while it wobbles
  (rough ground, an edge where two readings take turns). A change of
  more than 45 degrees must persist four ticks before the body follows
  it, so two surfaces taking turns being nearest cannot rock it.
- A gap shorter than the body (36 px) with ground at about the same
  level beyond it is bridged, not entered; bridging ends only after the
  gap test has failed a few ticks in a row, and at once if it has
  carried the body away from any rock.
- The body is laid along the surface link by link behind the head, so an
  inside corner bends it into an L instead of bunching it up.
- Input is projected onto the surface tangent: the key pressed moves the
  gecko that way on screen. Jump pushes away along the normal.
- Four feet, two per end, hold anchors on the rock; a trot keeps two
  planted. Fewer than two for 0.2 s and the gecko drops, unless the
  surface is right under it, in which case the feet step again. An
  unplanted foot closes on its rest spot at a set speed, never in one
  snap, and a stretched leg keeps enough blobs along it to stay one limb.
- Chewing bites a 13 px circle toward the cursor; with no key held the
  body creeps after the bite, turning its up vector so its walking line
  follows the bite when the bite line finds rock (head first down a
  shaft). The aim snaps to a world axis within 15 degrees. Gamepad and
  the demo pilot bite in the input direction, anchored to the row the
  gecko stands on, so a tunnel comes out level.
- Under a ceiling low enough to touch, the body rides halfway between
  floor and ceiling, so a tunnel its own height does not wedge it. A
  body centre that ends up inside rock is pushed out before anything
  else is decided.
- Tongue: a press of the left button shoots it at the cursor, up to
  160 px, as a tapering line with no tip, and where it lands it sticks
  while the button is down. A tap (the button up before the tongue has
  been held 0.12 s, landed or not) strikes: an 8 px dent in the ground,
  or the bonds broken within 10 px of where it hits a lump, and it
  comes straight back. Held longer alone it is the grapple: the gecko
  lets go, is reeled in to the anchor, and clings where it arrives.
  With the right button (or the chew key) held as well it drags: the
  gecko braces on its planted feet, the snout drawn back, and a piece
  of up to 80 cells is dragged in at 150 px/s, the tip riding its
  cells; at the mouth it is swallowed if it is 16 cells or fewer (the
  mouth opens as the yawn's does while it nears, the piece vanishes
  into it, and a bulge runs down the body) or let go; the ground, or a bigger piece,
  holds the tongue taut until a button is released. Airborne or
  swimming there is nothing to brace on, so the tongue reels the gecko
  in whichever buttons are down. Chewing waits while the tongue is
  out. There is no spit.
- Loose lumps (B and C drop a boulder or a clump of clay at the cursor,
  N a heap of sand, which is plain loose sand and flows; the generated
  cave has a few of each) are solid to stand on, stepped over when
  they are pebbles (6 cells or fewer) and climbed when wedged; on the
  ground the gecko's senses (the surface rays, the probe, the gap and
  wall tests) do not read a lump as terrain, only its collision does,
  so a lump ahead is a thing in the way, and standing on one it is
  terrain again. Walking
  into one shoves it: the whole lump is moved as one at 60 px/s the way
  the walk points (a push on its near particles alone rolls it up over
  the body, or flattens it), the walk keeps up behind it at 50 px/s,
  and only after half a second against a lump that does not move does
  it count as a wall. The wall
  reach never grabs a lump. A lump rolls as it is dragged or shoved,
  and its turned lattice is drawn without holes (each particle paints
  every cell within a lattice half-diagonal), so its cells count a
  little high when turned.
- Water (a still pool in the bitmap until the sim's readback brings its
  own): the gecko drifts where the input points with no gravity, cannot
  rise through the surface, and leaves by pushing into rock and clinging,
  or on the tongue. Walking in from the floor keeps it clinging, so it
  walks along the bottom; jump to swim.
- The head looks at the cursor, within about 100 degrees of the body line.
- The drawn body rides on a base that follows the body centre exactly
  along the surface and only slowly across it, so bumps do not bob the
  head. The snout stops at rock instead of being shoved aside, and
  comes forward again at a set speed.
- A walking move blocked by rock low over the floor (a loose pixel, a
  ledge up to 12 px) lifts the body 2.5 px a tick and tries again, so
  it climbs over in a few ticks instead of stopping or hopping; never
  mid-turn, and never more than five ticks before the obstacle counts as
  a wall. The ride-height nudge moves at most 4 px a tick, skips a tick
  that lifted or pulled the body, and over an edge never pulls backward
  against the walk.
- The input dead band has hysteresis. Pressing away from a steep
  surface keeps a moving gecko moving under the same press, and sends a
  gecko at rest toward the nearer inside corner (down a wall to the
  floor, up a ceiling step to the higher ceiling). When the way chosen
  for a press turns against it (a bulge whose underside and upper slope
  read a press as opposite ways) the gecko stops, as at a wall, until the
  press changes; it never reverses in a loop.
- Turns are decided from the cell that actually blocked the step, never
  from the cell the body rests on.
- A passage narrower than the body (11 to 19 px between its walls; 20
  and up the body walks at its full clearance) is squeezed through.
  Stopped at its lip, the gecko scans across the walk for the run of
  air, and enters it if it goes on at least 16 px without closing: the
  clearance drops to fit, the walk slows to 40 percent, the body is
  nudged to the passage's middle, and its drawn points thin to the
  passage where they are between its walls and spring back as they
  leave it. A press straight into the surface over a slot in it (a
  crack in the floor, a slot in the ceiling overhead) enters the slot
  nose first, as a wall grab onto its side, centred over its mouth. The
  squeeze keeps its own axis-aligned frame, ends once the passage has
  opened out round the body, and never follows a crevice that closes
  below 11 px. Afterwards the clearance grows back half a pixel a tick,
  so the body eases out rather than pops.
- The drawn body rides 2 px above the body centre's line, the tail's
  tip 1 px, so the belly clears the ground and the tail drags on it. A
  planted foot is drawn on the rock's surface rather than at its
  anchor, which is a cell's centre 2 px inside it. A foot waiting its
  turn in the trot that is not planted closes on its rest spot
  meanwhile instead of hanging where the body left it. In a passage
  the legs flatten with the body (knee lift and step arc no more than
  the leg's drop) and the feet rest on the floor's surface, so nothing
  pokes through the thinned back, and thinned segments are drawn as
  tubes rather than rows of circles, so the back's edge is straight and
  does not flicker pixel by pixel as the body creeps along.
- The eye is drawn by the blob layer as a 4 px square on its own pixel
  grid, over the body, so it is as crisp as the body and clipped by it.
- A ray cast down a crack narrower than the body (a slot in the floor)
  reads the surface beyond the crack at the same level rather than
  missing, so the body is not tilted into the crack by the centroid of
  the rock about it, and a press square to the floor there stays
  square.
- The away rule's choice for a press is remembered as a world
  direction; when the surface curls over (a bump on a wall) and the
  press, read on it, leads back against that direction, the gecko stops
  as at a wall instead of reversing and looping between the two
  readings. A corner turned onto a new surface runs across it, not
  against, and walks on. The wall reach never grabs a wall the input
  points away from (a slab's foot behind the gecko).

## Controls

WASD or arrows move, Space jumps, E or Shift chews. Left mouse shoots
the tongue: a tap strikes, a hold grapples, and with the right button
held as well it sticks and drags. Right mouse chews at the cursor. Ctrl+right erases, middle
fills, wheel sizes the brush; B, C and N drop a boulder, a clump of
clay or a heap of sand at the cursor, half the brush's size. R makes a
new chamber, 1 and 2
pick the gecko's pixel grid.
Tab loads the next scene from the movement suite (built in whichever
world is running, the keys driving the gecko) and Shift+Tab goes back
to the generated cave. F1 is debug mode: the gecko's overlay (up
vector, probe reach, feet, bite) and a panel down the right of the
screen with the scene list to click into, main cave and reload, the
cave seed, the brush radius, the time scale, pause and a single-tick
step, the pixel grid and the overlay toggle, and the gecko's state.
The world's mouse actions ignore the mouse while it is over the panel.

## Checking it without a hand on the keys

`GECKO_DEMO=climb|tunnel|swim|tongue|pull|strike|notch|crevice|traverse|dig`
replaces the keyboard and mouse with a scripted run (see `main.gd`;
climb builds a test pillar, crevice a funnel, dig chews after a
scripted cursor; tongue, pull and strike run in a flat room of their
own in the particle world: a grapple to the ceiling on a held button,
a stone dragged in and swallowed then a boulder dragged to the mouth
and walked along, a strike on the floor and on a boulder).
`GECKO_TRACE=1` prints the body state per physics tick (key=value: the
body, the drawn body, the head, up, the feet, the decision flags) and
the gecko's screen position and tick per frame; `tools/strip.sh` turns
movie-mode frames into a contact sheet cropped around the gecko.

The movement suite is the regression gate for any movement change:

- `tests/scenes.json` (written by `tools/gen_scenes.py`) holds 92 scenes
  built from terrain primitives on the bitmap map, each with a spawn and
  scripted input: flat floor, slopes, steps, bumps, corners, overhangs,
  gaps, crevices, ceilings, tunnels, landings, water, generated caves
  and cursor digs. `GECKO_SCENE=name[:script]` runs one and quits when
  the script ends; `GECKO_SEED` fixes the random bites and steps.
- `tools/suite.sh [filter]` runs every scene headless at fixed fps
  (about twelve seconds for the lot, `JOBS` in parallel) into `runs/`
  and scores them with `tools/analyze.py`: drawn body and head jumps,
  back-and-forth under a held input, up flips and oscillation, state
  flicker, stalls, foot flicker and sinking, plus each scene's expected
  outcome. `BASELINE=tests/baseline.json` marks regressions against the
  committed baseline. A run passes with no events at all.
- `FRAMES=1 tools/suite.sh [filter]` records 60 fps frames (one per
  tick) under `frames/`, on a virtual display (`xvfb-run`) with
  software Vulkan, the game's own renderer, so no window opens;
  `ONSCREEN=1` records on the real display and GPU instead (the frames
  then differ by a colour step on some rock pixels, nothing more).
  The project window is 1920x1000 with no canvas stretch, so it fits a
  1080 px screen's work area and both the screen and the recorded
  frames are one pixel per pixel: a 1080 px window gets shortened by
  the compositor, and the movie frame then holds the content at a
  half-pixel offset, which blends every edge and reads as flicker;
  `tools/flicker.py frames/`
  measures the drawn silhouette's change between frames and any
  fragments it breaks into; `tools/sheet.sh scene:script tick` makes a
  contact sheet round a tick, and `tools/ticks.py` dumps a tick range of
  a trace as a table.

Fixes come from reading the trace and the sheet round a flagged tick,
then re-running the whole suite: a fix is accepted only when no other
run regresses.

## Building and publishing

Code: https://github.com/gregkaczan/untitled-gecko. `./build.sh` exports
Windows and Linux release builds into `build/` (export templates for
Godot 4.6.1 must be installed under `~/.local/share/godot/export_templates/`)
and, only with `ITCH_PUSH=1` and `butler` logged in, pushes them to
itch.io as `kwakuuuu/gecko:windows` (and `:linux` when enabled). A web build would have to
run the bitmap world: the particle sim needs compute shaders, which the
web export does not have.
