# untitled-gecko

Movement spike for the gecko game. The design document lives in Claude Docs:
https://claude.ai/artifact/HeBpi84hMyeL581NWrvdvB

This repo answers the first question in that document's next steps: is
moving the gecko around a cave fun on its own? The world is the GPU
particle sim from untitled-idle-shooter (`sim.gd`, `shaders/*.glsl`),
read back every tick as one cell class per 2 px render pixel (air,
water, static solid, lava, loose grain, a lump's id) into the same
960x540 grid the gecko's queries run on (`sim_map.gd`). The CPU bitmap stand-in (`cave_map.gd`) is still
there behind `GECKO_WORLD=bitmap`: it starts instantly, runs headless,
and the particle world is built from its generator. `chain.gd`,
`blob_layer.gd` and the metaball shader also come from the shooter.

Sim notes: every particle covers the full 1920x1080 (the shooter started
at a ground line), so the shaders carry offsets different from the
shooter's; `sim.gd` asserts the cell-class and bond offsets. Chewing
and the brush are melt capsules (particles deleted on the GPU), a fill
spawns particles. A carve takes the cells whose centres lie within its
radius, so its opening is the radius plus half a cell: on 2 px cells
every carve (a bite, a strike, a crumble, a scene's tunnel) is widened
by the half cell lost against the 4 px cells the gecko's numbers were
set on (`CARVE_PAD` in `sim.gd` and `cave_map.gd`), and a bite opens
what it did. Loose lumps (boulders, stones, clumps of clay) are
chunks: one particle per cell, each bonded to its eight lattice
neighbours by a distance constraint (a bond record per particle at the
buffer's tail, solved with the density constraints in `pbd_delta.glsl`,
mates holding each other by their bonds alone and never drawn into
what they touch). A lump sleeps until a mate moves, falls as one,
comes apart where bonds are broken or stretched past their limit (clay
sooner than stone), and its cells read back as 16 + the chunk id, so
the CPU can tell a lump from the ground and trace the piece the tongue
is stuck to. The tongue's drag and the walk's shove (a pull on a whole
chunk), a swallow and a strike's break are capsule slots of their own,
and so is the body: two capsules along the drawn chain that shove
loose grains out of their way every tick, so sand poured on the gecko
piles on its back instead of passing through it.
The local rendering
device does not exist headless, so sim runs need the window (movie
mode is fine, on a virtual display too).

Materials (`sim.gd`'s table, the shooter's with two slots renamed):
sand and clay are loose grains, rock, hard rock, copper and bedrock
are static (held in place by their yield), stone is the loose stuff of
lumps, water and lava liquids. Each has a give, the chance a bite
takes a particle: all of rock, two fifths of hard rock (a hole takes
several bites), none of bedrock; the brush takes anything. A grain at
rest sleeps, and wakes when the cell under it reads open, or when it
could slide (the cell beside it and the one under that both open), so
a bed of sand stays put until it is undermined, then pours and slumps
to the cells' diagonal (`pbd_predict.glsl`); without this the solver,
which moves only what is awake, left sand hanging over a bite. Loose
grains read back as their own class, so the rule that stops loose
matter entering static solid (`pbd_finalize.glsl`) lets a heap flow,
and the gecko can tell sand from rock: ground to its senses (walked
on, climbed, bitten), and no wall to its walk, which goes on through
grains at a third of its speed with the body's push shoving them
aside (burrowing: a buried gecko digs itself out by walking). The
bitmap stand-in has every kind as a cell (`cave_map.gd`), sand and
clay as ground like rock, lava as a drawn pool, so the headless suite
is untouched; the scenes lay them as rects (`sand`, `clay`, `lava`,
`hard`, `bedrock`) and discs. The gecko does nothing about lava yet.

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
- Chewing is eating: a bite every 0.4 s, the mouth opening through the
  cycle and the bite (a circle of about 11 px, a little off and a
  little different each time) landing as it shuts, toward the cursor.
  A bite only parts the lips (the mouth mark opens to 3 px): the snout
  stays put and no jaw drops, so the head keeps its shape through the
  chew. The yawn's lifted snout and dropped jaw, used for the bite at
  first, swelled the head every 0.4 s, which read as a swallow's
  bulge; the gecko chews rock, it does not swallow it, and the bulge
  down the body is the tongue's swallow alone.
  With rock in reach of the bites the walk slows to 45 px/s, so a
  tunnel is eaten through at about a third of walking speed, slower
  through hard rock (each bite takes two fifths of it) and not at all
  through bedrock; in the open the chew key costs nothing. With no key
  held the body creeps after the bite, turning its up vector so its
  walking line follows the bite when the bite line finds rock (head
  first down a shaft). The aim snaps to a world axis within 15
  degrees. Gamepad and the demo pilot bite in the input direction,
  anchored to the row the gecko stands on, so a tunnel comes out level.
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
- Loose grains (a bed or heap of sand, a bank of clay: N drops a heap
  at the cursor and held pours one) are ground to the senses, walked
  on, climbed and bitten like rock, but no wall to the walk: a move
  that only grains block goes on through them at a third of walking
  speed, the body's push shoving them aside. Sand poured on the gecko
  piles on its back and buries it, and it walks out.
- Crumbs: a bit of matter of at most a few cells (the debug panel's
  "crumbs pushed", 4 by default, 0 for none: the cells eight-connected
  to each within its 5x5, marked on the GPU in `cell_post.glsl`) is air
  to the senses, and its static particles come loose as stone when the
  body's pushers touch them, so a speck afloat in the air or lying in a
  crevice is shoved aside and falls instead of stopping the walk or
  catching a cling. A speck touching a wall is part of it and a convex
  corner is nine cells or more, so walls and steps are untouched. The
  senses themselves run on the sim's 2 px cells or on a 2x2 fold of
  them to 4 px (`cell_fold.glsl`, the panel's "Senses"); the fold
  keeps the gecko's tick at 1.4 ms against 3.9 at 2 px on the RTX 4080,
  the sim's tick being 3 ms either way.
- Loose lumps (B and C drop a boulder or a clump of clay at the cursor;
  the generated
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
  walks along the bottom; jump to swim. Swimming is sensed from the
  water cells within one of the body centre, so the body's pusher
  capsules in the particle world leave water (and lava) alone: when
  they shoved the water out of the body, the centre read air, the swim
  dropped to the air state and back every other tick, and the gecko
  sank to the bottom. The `pool_drop` scene (a jump into deep water,
  then no input) guards it: the gecko floats in the top half, state
  swim, headless on the bitmap and recorded on the sim's water.
- The head looks at the cursor, within about 100 degrees of the body line.
- The drawn body rides on a base that follows the body centre exactly
  along the surface and only slowly across it, so bumps do not bob the
  head. The snout stops at rock instead of being shoved aside, and
  comes forward again at a set speed.
- The camera follows that base, after the gecko's tick. Up to 220 px/s
  it scrolls exactly with the base's move, so an ordinary walk or climb
  keeps the body on the same screen pixels and the small unevenness of
  its speed goes into the scroll, where the eye does not see it; what
  lag is left (a fall, a landing's jolt, a long move in one tick) eases
  out at 16 per second. It sits on whole screen pixels (half a world
  pixel at the 2x zoom), held inside the world's edges, so the world
  scrolls a screen pixel at a time and every edge stays crisp. The
  body's own 2 px pixel grid is anchored on the base's seat, the base
  rounded to the screen's pixels relative to the camera and kept until
  the lag has left it by a whole screen pixel, so the body is drawn
  with the same pixels tick after tick and moves on the screen only as
  the lag changes, a screen pixel at a time. Before, the camera was
  rounded to the body's 2 px grid and the body to the world's: the two
  crossed pixel boundaries at different moments and the body shook a
  pixel back and forth as it walked (6821 shake events over the suite,
  24054 camera jerks), while the world scrolled in 2 px steps. This is
  the framing-transposer idea from Cinemachine (a target followed in
  screen space with per-axis damping, a dead zone where it may move
  without moving the camera, and the target's clock respected) cut to
  what matters here, with the pixel seat in place of Unity's pixel
  perfect camera's sprite snapping. The camera still moves once per
  physics tick; a display not at 60 Hz shows that as a beat, which an
  interpolated follow per drawn frame would remove (the blob layer
  would have to be shifted by the same interpolation).
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
  and up the body walks at its full clearance, unless it is stopped at
  the lip of one up to 24 px, which ragged walls make narrower than
  the one column scanned) is squeezed through. Stopped at its lip, the
  gecko scans across the walk for the run of air, and enters it if it
  goes on at least 16 px without closing, or opens into cave or a
  wider pocket beyond (a hole through a thin wall, a door; a throat
  into a chamber): the clearance drops to fit the corridor the body
  has, the overlap of the air columns read at every cell over the next
  body length (every column may be tall enough and the corridor still
  narrow where a chewed passage's middle wobbles up and down), the
  walk slows to 40 percent, the body is nudged to that corridor's
  middle (within a quarter pixel while the walk is blocked, since a
  body a pixel off it can be the one a bump stops), and its drawn
  points thin to the
  passage where they are between its walls and spring back as they
  leave it. A press straight into the surface over a slot in it (a
  crack in the floor, a slot in the ceiling overhead, a hole in the
  wall being climbed) enters the slot nose first, as a wall grab onto
  its side, centred over its mouth. The squeeze keeps its own
  axis-aligned frame, ends once the passage has opened out round the
  body, and never follows a crevice that closes below 11 px.
  Afterwards the clearance grows back half a pixel a tick, so the body
  eases out rather than pops. A body chewing its way in squeezes
  through what it chews, the bites' cusps included.
- In a passage the drawn body lies on the passage's middle line, not
  its usual 2 px above the body centre: the lift eases between the two
  at a pixel a tick from the moment the squeeze begins, so the head
  heads for the passage rather than being shoved in off the lip. The
  head keeps its full lead (the snout test uses the squeeze's own
  clearance, or the walls beside it would draw it in the whole way
  through) and, between two walls, is centred by the thinning like the
  body's points instead of being pushed off whichever wall is nearer:
  targeted at the lifted line it sat inside the wall's clearance and
  the push off the nearest cell, with an along-passage part that swept
  across each cell column and flipped at its edge, sawed it back and
  forth 2 px every five ticks. The thinning looks for the two walls
  along the passage's axis, its diagonals and the slant to the nearest
  cell, and takes the narrowest: at a mouth a point sits between the
  floor and the lip's corner, which are not opposite, and read along
  the line to whichever is nearer by turns it was pushed off the floor
  one tick and centred under the lip the next. A point whose drawn
  radius is still growing back from a thinning is pushed off rock no
  more than a pixel a tick.
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
- The face is drawn by the blob layer as marks on its own pixel grid,
  over the body, so they are as crisp as the body: the eye, a black disc 4 px
  across one cell below the head's rim (any higher and its top row
  takes the rim's place and reads as a notch), and what the idle
  animations add (below).
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

## Idle animations

After two seconds of nothing happening (clinging, no keys, no buttons,
the tongue in) the gecko blinks, licks its eye or yawns, one every 1.5
to 3.5 seconds, drawn from a shuffled bag of two blinks, a lick and a
yawn, so none repeats for long and all turn up. The head keeps
following the cursor meanwhile. A blink shuts the eye to its lower row
for a tenth of a second. A lick runs the tongue from the mouth round
the snout's tip to the eye (shut while the tongue is on it) and back,
as 2 px marks along a curve with a 4 px tip. A yawn lifts the snout,
drops a jaw blob below it and opens the dark inside of the mouth
between them, quick to open, held a quarter second, quick to close,
the eye shut while it gapes. A key or a button interrupts any of them
at its closing phase. The face has its own random generator, seeded
from `GECKO_SEED`, so the suite's seeded bites and steps are untouched
and a seeded run repeats.

## The first cave

`levels/clutch.json` (written by `tools/gen_clutch.py`) is the cave the
game opens on: one world, the sim's whole 1920x1080 buffer, played from
a sealed pocket at the bottom left to a crack of light at the top, in
an S: the bottom band runs right, the middle band left, the top band
right. It is a scene in the suite's format (a base of terrain ops, a
spawn, scripts) with two fields of its own: `lumps`, the loose stones,
clay and sand spawned after the terrain in the particle world (the
bitmap world has none), and `exit`, the rect the body centre enters to
finish, on which the camera lets go of the gecko and pulls back over
the whole cave; R starts it again. Every station can be chewed past,
as the design document's openness rule wants (the rock is all one
kind so far, so a straight chew up is the fast route; a harder layer
is the fix the document names), and each is laid out so one verb is
the plain way through:

- The hatch pocket: sealed, two clay eggs beside the gecko, a 16 px
  wall between it and the hall. The only way out is a bite.
- The hall: a dome and a 32 px shelf to step over, pebbles stepped
  over, a stone small enough to swallow, a clump of clay to drag and
  tear, a copper vein glowing along the ceiling, a 28 px shaft up the
  right wall.
- The roll: a 52 px corridor with a boulder of up to 48 px in it, no
  room over it. Walked into, it is shoved along to the pit at the
  corridor's end and drops in, and the walk goes on over it. The pit
  is 60 px wide: walked down and up, into a 32 px passage.
- The cork: a stone of about 40 cells 40 px into the 32 px passage
  out of the pit, too big to pass and too big to swallow. From the
  corridor across the pit the tongue drags it out and it falls in;
  walked into from the pit it is shoved along the passage, drops into
  a dip 24 px deep and is walked over there. A strike only dents it:
  the bonds within 10 px of the hit break, but the loose stone stays
  packed where it lies. A boulder filling a pocket was tried first and
  does not work either: a confined lump stays packed when struck, and
  the piece the tongue holds is traced through cells, so the drag sees
  the whole lump and strains. A sealed pocket of sand sits in the rock
  over the dip, so a bite up there pours sand into it. At the foot of
  the pit's far wall a left press stops; up climbs it.
- The pinch: 16 px tall and 120 px long, a squeeze into the turning
  chamber, whose left wall is the 288 px climb to the top corridor.
- The trough: 260 px of water with a stone 120 px out whose top is at
  the bank. Walked into, the bottom is walked under water, the stone
  climbed over, and the far basin's wall climbed out of with an up
  press (a right press at its foot stops there); or a running jump
  lands on the stone and a second clears the last 60 px, and a short
  one swims. A copper vein glows under the water.
- A dead end up off the corridor's ceiling, with a vein at its end.
- The gulf: 140 px tall. A held left button on the ceiling beside the
  crack reels the gecko up to it; the far wall and the ceiling are
  the slow way. The crack is a 16 px slot: a press up into the ceiling
  under it enters it nose first, and the squeeze ends in the pocket
  of light. Not a bite: a bite into the ceiling one hangs from takes
  the handhold away, and in the particle world (whose bite reaches a
  few pixels further than the bitmap's) the nearest rock passes the
  26 px that count as nothing to hold, and the gecko drops.

Copper is a cell class of its own (`CELL_COPPER`): rock to walk on and
chew that the bitmap draws bright and the sim builds as copper, held
in place as rock is (a yield of 5 or more in the material table).
Eating it does nothing yet.

The stations are scenes on the level's base with a spawn, a script and
a reach region, so `tools/suite.sh clutch` checks each one's intended
route headless. The two that need lumps (`sim_only`: the roll and the
plug) are left out of the headless list and recorded in the particle
world with `tools/record.sh scene:script`, which writes frames and a
trace under `frames/` as the suite's `FRAMES=1` does.
`GECKO_DUMP_MAP=file.png` writes the bitmap world's cells as a PNG and
quits, for a look at the layout.

## The cave's dress

What the first slice adds on top of the movement, each a first version
(2026-10-21), all in the particle world unless said otherwise.

- Light: the sim has a light pass (`light_seed.glsl`, `light_spread.glsl`,
  `light_out.glsl`), three regions at the tail of its buffer. Each
  tick the seed takes last tick's light decayed by 0.8, the emission
  the particles wrote (copper a little, lava a lot, glowshrooms green
  with a slow breath, `render_write.glsl`), daylight on the open cells
  of the exit's rect, and the glows (the gecko's head, warm and small;
  each slug's); nineteen spread passes carry it a cell at a time, the
  brightest neighbour times what the cell lets through (air 0.9925,
  water 0.964, loose grains 0.775, solid 0.671, so a rock face lights a
  few cells deep), at 16 bits a channel so it fades out instead of
  sticking. The result is read back as a 960x540 texture and
  multiplied over the particles and the backdrop with an ambient floor
  (`light_overlay.gdshader`), under the gecko, whose whole body is
  drawn the same brightness (a shaded gecko read as a different
  creature). `GECKO_LIGHT=0` turns it off. Godot's compute barrier
  re-applies the last push constant to whatever it re-binds, so no
  barrier follows the output pass.
- Sound, kept light (`sound.gd`): one-shots on the gecko's signals
  (a foot planting at the end of a step, a bite, a swallow, the tongue
  leaving and landing, the splash into water, a landing above 120
  px/s), a cave drone, and a daylight hum placed at the exit so it
  grows as the gecko climbs. The sounds are synthesised by
  `tools/gen_sounds.py` into `sounds/*.wav` (no numpy, no licences):
  placeholders with a lo-fi character, regenerated by a parameter
  tweak; each play gets a little pitch variety from the bank's own
  random generator (the gecko's bites draw on the global one, which
  the suite seeds). `GECKO_SOUND=0` silences it.
- Ambience (`ambience.gd`): drops of water fall from the ceiling over
  the pools (the sim's own water, a drip sound when they land), a bite
  throws up a puff of dust, a swimming gecko blows bubbles (both the
  shooter's smoke particles, short-lived).
- Decor as stamps: `["decor", name, x, y, "floor" | "ceiling"]` in a
  scene's terrain sets a pattern of cells on the first floor below the
  point or hanging from the first ceiling above it, from a table of
  cell patterns (`tests/scene_builder.gd` DECOR). The glowshrooms are
  the first: material 12 in the sim (the shooter's purple ore slot made
  static, pale green and a light), cell kind 9 in the bitmap, ground
  to the gecko, gone with a bite. The intent is that drawn parts (small
  images with a palette that maps colours to cell kinds) replace the
  tables, placed by hand in the level's list now and by a map editor
  later, and destructible for free because they become cells.
- Dripstone, procedural from a seed: `["stalactites" | "stalagmites",
  x0, x1, y, n, seed, hmin, hmax]` grows n cones of rock off a ceiling
  or floor line, `["column", x, y0, y1, w, seed]` a stalagnate with a
  waist. In the clutch: off the hall's and the gulf's ceilings, small
  on the hall's floor, a column in the dead end.
- Vines: `["vine", x, y, length]` in a scene's lumps hangs a chain of
  clay cells from the first ceiling above (x, y), its top cell rock so
  it holds, bonded like a lump, drawn green-brown. It swings, is shoved
  aside by a walk, parts where bitten or stretched past clay's limit,
  and can be clung to; a hang of more than 1.2 s on one (a planted
  foot on its cells) breaks its anchor and it comes down, gecko and all
  (`main.gd` VINE_HOLD). Particle world only.
- Backdrop (`backdrop.gd`): a far wall of darker rock noise, larger
  than the world, moving at 0.15 of the camera, under the particles;
  and a near layer of dark dripstone silhouettes hung from the cell
  map's ceilings and raised from its floors, in front of everything at
  1.25 of the camera, both on the camera's pixel grid every tick.
- Glow slugs (`slug.gd`): `["slugs"]` points in the level. A slug
  creeps along the nearest surface at 12 px/s, turns back where it is
  blocked and now and then on its own, falls when it loses the surface,
  glows green (a light source), and is drawn as three blobs by the
  gecko's blob layer. The tongue's tip touching one catches it: it
  rides the tip to the mouth, is swallowed (the bulge runs down), and
  the gecko's glow is brighter and greener for twenty seconds. Hunting
  and lighting the way are the same act.

## Surfaces that will not be held

Ways the cave resists free climbing and digging straight through, all
first versions (2026-10-21), with no failure state: the gecko is
dropped, thrown, slowed or left in the dark, never hurt. The decisions
left open: a failure model (lava, falls), a full gut (a meter), a
general grip model (dry moss that holds better, steep wet rock that
slides) and how much is laid by hand against grown by rule.

- Thorns: a sharp plant on a rock face, pale and bony (cell kind 13;
  in the sim rock in a fraction band of its own, cell class 7). Solid
  to everything, but no foot holds it and a touch, by a foot or by the
  body stopped against it in any state, throws the body back at 140
  px/s with 0.35 s of no cling, so a patch is neither stood on nor
  climbed past; a bite takes it. The `thorn` and `thorn_s` stamps go on
  floors, ceilings and walls (`["decor", "thorn", x, y, "wall_right"]`;
  the editor picks the nearest surface). Scenes: `thorn_wall` (the
  climb ends below the patch), `thorn_floor` (the walk never passes).
- Slippery moss: a coat of cells on rock faces (cell kind 10; in the
  sim rock in its top fraction band, cell class 5). Solid to everything,
  but off a floor (the body's up more than 45 degrees from straight up)
  a planted foot on it drops the gecko, with 0.35 s of no cling so the
  slip is seen. A bite takes it and leaves a hold. `["moss", x, y, w,
  h]` coats the rock faces in a rect. In the clutch: the hall's left
  wall (the first thing climbed, so the lesson is early and harmless)
  and the turning chamber's right wall, so the left wall is the climb.
- Drops: a falling water cell within three cells of a gecko on a wall
  or ceiling knocks it off. The ambience's drips do it over pools, and
  `["drips", x0, x1, y, rate]` hangs a curtain from a ceiling segment
  (the turning chamber's right side, from the corridor's ceiling).
- Hot rock: a second of a planted foot within five cells of lava lifts
  the feet. Lava itself is not entered on purpose yet; standing in it
  hops.
- Crumbling rock (kind 11, class 6): a second's hold on it brings down
  10 px round the foot, to air in the bitmap and to a pour of sand in
  the sim, and the gecko with it. `["crumble", x, y, w, h]` turns the
  rock in a rect. In the clutch: the dead end's neck walls, so the lamp
  that leads nowhere drops you back into the corridor.
- Scree: planted feet on a loose heap steeper than about 30 degrees
  nudge the grains under them awake (capsule mode -5), so the heap
  flows from under the climber. Sim only.
- Gas pockets (kind 12, air with a tint): a sealed pocket whose wall a
  bite or a strike opens (a cell on the ring round it reads open)
  bursts: the gecko is thrown from its centre at 480 px/s, its hold
  lost and its glow out for four seconds; the sim gets a blast and a
  puff. `["gas", x, y, w, h]`. In the clutch: between the hall and the
  roll corridor, where a straight dig up from the hall would go.
- Currents: `["current", x, y, w, h, dx, dy, speed]` runs the water in
  a rect; the sim's water is drawn to the flow and a swimming gecko is
  carried with it on top of its kicks (mean about 170 px/s), so a flow
  faster than that cannot be swum against. Two at most.

Scenes guard each: `moss_wall` (the climb drops and ends on the floor),
`moss_bitten` (a coat one bite tall is bitten off and the climb goes
on), `notch_climb` (the same bites on bare rock), `crumble_wall`,
`pool_current` and `gas_pocket`.

## The map editor

F2 opens the editor (`editor.gd`), a panel down the left: paints (every
cell kind), stamps (the decor table's glowshrooms, a stalactite or
stalagmite of the brush's size, a vine of four times the brush's
length, a slug), the spawn point and the exit (dragged), the brush size
(the wheel too), and Save, Load and Blank by name. The left button
paints, the right erases. Every edit goes to the live world (the
particle sim: an erase this tick and a fill the next, once the readback
shows the cells empty; or the bitmap) and to an authoring cell map, the
CPU map the sim was built from, kept for this. Save writes
`levels/<name>.cells.png` (one pixel a cell, its kind in the red
channel, exact) and `levels/<name>.json`: a base of those cells and one
scene on it with the spawn, the exit, the vines and lumps, and the
slugs. Every `levels/*.json` loads like the clutch (Tab cycles them,
the suite runs any with scripts), so a painted level is a level.
Painted gas pockets are found from the cells. `GECKO_EDIT_TEST=1`
runs a headless round trip of save and load.

## Controls

WASD or arrows move, Space jumps, E or Shift chews. Left mouse shoots
the tongue: a tap strikes, a hold grapples, and with the right button
held as well it sticks and drags. Right mouse chews at the cursor. Ctrl+right erases (anything,
bedrock too), middle
fills, wheel sizes the brush; B, C and N drop a boulder, a clump of
clay or a heap of sand at the cursor, half the brush's size, and N
held pours sand there. R starts
the cave again (a fresh chamber when in a generated one), 1 and 2
pick the gecko's pixel grid.
Tab loads the next scene from the movement suite (built in whichever
world is running, the keys driving the gecko) and Shift+Tab goes back
to the first cave. F1 is debug mode: the gecko's overlay (up
vector, probe reach, feet, bite) and a panel down the right of the
screen with the scene list to click into, main cave and reload, the
cave seed and New cave for a generated chamber, the brush radius, the
time scale, pause and a single-tick
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
body, the drawn body, the head, up, the feet, the decision flags, the
idle animation, and `cp`, the chain head first as offset along the
tangent, offset along up, drawn radius and thinned) and, per frame,
the gecko's screen position, the tick, the camera's centre as shown,
the drawn body's seat on the screen and in the world, and whether the
camera has let go of the gecko at the exit; `tools/strip.sh` turns
movie-mode frames into a contact sheet cropped around the gecko.

The movement suite is the regression gate for any movement change:

- `tests/scenes.json` (written by `tools/gen_scenes.py`) holds 106 scenes
  built from terrain primitives on the bitmap map, each with a spawn and
  scripted input: flat floor, slopes, steps, bumps, corners, overhangs,
  gaps, crevices, ceilings, tunnels, landings, water (a pool swum
  across, a deep pool jumped into and floated in), generated caves,
  cursor digs, squeezes (low passages, slots, a chewed passage, holes
  at the floor through walls 12 and 24 px thick, a hole 40 px up a wall
  entered from the climb), an idle stand on the flat for the idle
  animations, and three for the particle world only (`sim_only`, run
  with `tools/record.sh`): `sand_bed`, a bed of sand on the floor and
  a trench of it on bedrock, walked over and back and dug into;
  `sand_hopper`, a hopper of sand over a low pocket whose plate is
  bitten open from below, the sand pouring over the gecko, which
  burrows out; `materials`, every material in a row (sand, clay,
  water, lava, hard rock, bedrock, copper, a stone and a clump of
  clay) for the brush and the keys to try. `GECKO_SCENE=name[:script]`
  runs one and quits when the
  script ends; `GECKO_SEED` fixes the random bites and steps.
- `tools/suite.sh [filter]` runs every scene headless at fixed fps
  (about twelve seconds for the lot, `JOBS` in parallel) into `runs/`
  and scores them with `tools/analyze.py`: drawn body and head jumps,
  back-and-forth under a held input, up flips and oscillation, state
  flicker, stalls, foot flicker and sinking, and from the per-frame
  lines the camera: a camera step that changes by 4 screen px or more
  while the body's own step is steady (`cam_jerk`: a camera on a
  coarse grid, or on another clock than the body), the drawn body's
  seat reversing on the screen while its world motion does not
  (`shake`: body and camera rounded to pixels independently), and a
  camera still moving long after the body has stopped (`cam_creep`,
  informational), plus each scene's expected outcome.
  `BASELINE=tests/baseline.json` marks regressions against the
  committed baseline (a metric the baseline predates is not compared).
  A run passes with no events at all.
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
Windows and macOS release builds into `build/` (Linux when enabled;
export templates for Godot 4.6.1 must be installed under
`~/.local/share/godot/export_templates/`) and, only with `ITCH_PUSH=1`
and `butler` logged in, pushes them to itch.io as
`kwakuuuu/gecko:windows` and `:osx` (and `:linux` when enabled). The
macOS app is a universal binary, ad-hoc signed by Godot's own signer
(no Apple identity, no notarization), so Gatekeeper calls it unverified
on first launch: right-click, Open, or `xattr -dr com.apple.quarantine
gecko.app` after unzipping. The sim's compute shaders run on Metal
there; untested on a Mac so far. A web build would have to run the
bitmap world: the particle sim needs compute shaders, which the web
export does not have.
