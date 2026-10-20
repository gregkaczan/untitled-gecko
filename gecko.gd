# Gecko: the player body for the movement spike. A chain body hovers at
# ride height over the cave bitmap and four feet hold anchors on it. The
# gecko clings while a surface is in reach and at least MIN_FEET feet are
# planted; otherwise it falls under gravity until it meets a surface again,
# at any angle. Input is projected onto the surface tangent, so the key
# pressed always moves the gecko that way on screen: right on the ceiling
# walks right, up on a wall climbs. Jump pushes away along the normal.
#
# Legs are two pairs, front (shoulder) and back (hip), each with a near
# foot drawn over the body and a far foot drawn behind it. Feet step in a
# trot: a foot whose diagonal partner is mid-step lifts early, a foot whose
# same-end partner is mid-step waits, so two feet stay planted. Body and
# legs are all metaballs in the blob layer, so the legs read as soft
# appendages of one slug-like body.
extends Node2D

signal ticked                  # The end of a physics tick: body, chain and blobs are this tick's (the camera follows on it)
# Events for the sounds and the ambience (sound.gd, ambience.gd).
signal stepped(at: Vector2, front: bool)   # A foot planted at the end of a step: where, and whether a front foot
signal bit(at: Vector2)        # A bite landed there
signal swallowed               # A piece went down
signal tongue_shot             # The tongue left the mouth
signal tongue_hit(at: Vector2) # The tip met something solid (stuck or struck)
signal splashed(at: Vector2)   # Into the water
signal landed(speed: float)    # Onto a surface from the air or the water, at that speed
signal jumped
signal slipped                 # Dropped off a surface: moss, hot rock, a drop's hit
signal crumbled(at: Vector2)   # Rock gave way under a foot there
signal blasted                 # A gas burst threw the gecko

const Chain = preload("res://chain.gd")

const WALK_SPEED := 130.0
const WALK_ACCEL := 1600.0
const RIDE_H := 16.0           # Body centre height above the nearest solid
const NUDGE_MAX := 4.0         # Most the ride-height nudge moves the body in one tick (px): settling, never a hop
const NUDGE_DEAD := 1.0        # Ride height this close to its target is left alone, so a whole-pixel reading cannot rock the body
const BODY_R := 9.0            # Clearance the body centre always keeps from rock
const LIFT := 2.5              # Px the body rises per tick to get over a low obstacle
const LIFT_LOW := 12.0         # A blocking cell no higher than this over the floor under the body is low enough to step over
const LIFT_TICKS := 5          # Ticks of lifting with no way forward before the obstacle counts as a wall
const LIFT_TURN_MAX := 0.04    # No lifting while up turns faster than this per tick (radians): a corner, not a bump
const STEP_CLIMB := 32.0       # A wall no taller than this over the floor is a step: pressing into it climbs it
const STEP_TURN_DOT := -0.6    # A step's blocking normal may lean this far past square (cosine to up) and still be climbed
const GRAB_MIN_S := 0.15       # Least input along a blocking surface that turns the body onto it (a curved face tilts it)
const CHEW_R := 11.0           # Mean radius of one bite; each bite varies around it
const CHEW_REACH := 19.0       # Bite centre distance ahead of the body centre
const CHEW_PERIOD := 0.4       # Seconds per bite: the jaw opens through the cycle and the bite lands as it shuts
const CHEW_SNAP := 0.25        # The last part of the cycle, over which the jaw shuts
const CHEW_MOUTH := 3.0        # Px the mouth mark opens per bite: the lips part, the head keeps its shape
const DIG_SPEED := 45.0        # Walking speed while chewing, so a tunnel is eaten through, not run through
# The surfaces that will not be held (_surface_rules): off a floor
# (up.y above SLICK_UP) a planted foot on moss drops the gecko, a
# falling drop within DROP_CELLS of the body knocks it off, HOT_HOLD
# seconds of a foot within HOT_CELLS of lava lift it, CRUMBLE_HOLD of a
# foot on crumbling rock brings CRUMBLE_R of it down, and planted feet
# on a loose heap steeper than SCREE_UP wake the grains under them.
const SLICK_UP := -0.7
const DROP_CELLS := 3
const HOT_CELLS := 5
const HOT_HOLD := 1.0
const CRUMBLE_HOLD := 1.0
const CRUMBLE_R := 10.0
const SCREE_UP := -0.85
const SCREE_R := 6.0
const SLIP_NO_CLING := 0.35    # After a slip, no cling for this long: the fall is seen and the same cells are not caught again at once
const BLAST_SNUFF := 4.0       # Seconds the glow is out after a gas burst
const BURROW_SLOW := 0.3       # Walking speed through loose grains (a bed of sand), as a fraction of the walk
const PUSH_R_FRONT := 8.0      # Radius of the body's push on loose grains, head to mid-body (sim_map.gd)
const PUSH_R_BACK := 5.0       # And mid-body to the tail's root
const DIG_DEAD := 10.0         # A cursor closer than this to the body centre gives no dig direction
const LEVEL_SNAP := 0.26       # A dig direction within ~15 degrees of a world axis snaps to it
const DIG_LOOK := 44.0         # Rock within this along the dig direction means the body turns onto it (past a bite's reach)
const DIG_GRAB_ANGLE := 0.35   # A dig turn bigger than this (radians) is a commitment, like a wall grab
const PROBE_R := 32.0          # Reach of the body's surface search
const SURF_TURN := 14.0        # Up vector turn rate toward the surface normal (rad/s)
const LOSE_SURFACE_D := 26.0   # Nearest solid farther than this = nothing to hold
const RAY_HALF := 12.0         # Half the span between the two surface rays
const RAY_LEN := 34.0          # How far down each surface ray looks
const BRIDGE := 36.0           # A gap with ground this far ahead at the same level is crossed, not entered
const BRIDGE_HOLD := 4         # Ticks the gap test may fail before bridging ends (the edge flickers it)
const BRIDGE_LEVEL := 6.0      # Px the far side of a bridged gap may sit below ride height
const JUMP_SPEED := 340.0
const GRAVITY := 900.0
const AIR_ACCEL := 600.0
const AIR_MAX := 220.0
const NO_CLING_TIME := 0.18    # Grace after a jump or a drop before clinging again
const FEET_GRACE := 0.2        # Time with too few feet planted before dropping
const MIN_FEET := 2
const HEAD_LEAD := 15.0        # Head sits this far ahead of the body centre
const BOB_SMOOTH := 0.15       # Per-tick blend of the drawn body's across-surface bounce
const BOB_MAX := 12.0          # Largest across-surface lag the drawn body may carry
const HEAD_SPEED := 360.0      # How fast the head swings round on a turn, or draws back and forward at a wall (6 px a tick)
const RADII := [7.0, 8.5, 8.5, 7.5, 5.5, 4.0, 3.2, 2.6, 2.2, 1.9]
const LINK := 8.0
const MAX_BEND := 1.0
const BODY_GAP := 2.0          # Clearance a chain point keeps past its radius
const BODY_HUG := 20.0         # How far past its radius a chain point looks for the surface
const HUG_K := 0.5             # Fraction of the way a trailing point is pulled onto the surface per tick
const SNOUT := 4.0             # Snout blob offset ahead of the head along the look direction
const LOOK_LIMIT := 1.8        # Radians the head can turn off the body line to look at the mouse
const FRONT_HIP := 1
const BACK_HIP := 3
const FOOT_SPREAD := 11.0      # Foot rest distance from its hip along the tangent
const FOOT_LEAD := 10.0        # Extra rest offset in the walking direction at full speed
const LEG_REACH := 16.0        # Farthest a foot searches for an anchor from its rest spot
const MAX_LEG := 28.0          # Hip to anchor distance that forces a planted foot to let go (rest spot is ~26 at full speed)
const STEP_LEN := 20.0         # Anchor drift from the rest spot that triggers a step
const STEP_TIME := 0.1
const STEP_HEIGHT := 7.0
const FOOT_SETTLE := 360.0     # Speed an unplanted foot closes on its rest spot (px/s): fast, never a snap
const KNEE_OUT := 5.0          # Knee lift away from the surface
const KNEE_BACK := 3.0         # Knee set back against the leg's end (front legs bend back)
const LEG_R := 3.4             # Upper leg blob radius; the lower leg tapers from it
const FOOT_LIFT := 4.5         # Drawn foot height over its anchor (a cell centre, 2 px inside the rock): the sole rests on the surface
const BODY_LIFT := 2.0         # The drawn body rides this much higher than the body centre, so the belly clears the ground
const REACH := 24.0            # How far past the body clearance a wall beside the gecko can be grabbed
const GRAB_PULL := 90.0        # Speed the body closes on a wall it is turning onto (px/s)
const MAX_TURN_DOT := -0.35    # No turn onto a surface more than ~110 degrees from up (no flips)
const SQUEEZE_D := 20.0        # Rock this close on both sides along the tangent = wedged in a crevice
const SQUEEZE_MIN := 11.0      # Narrowest passage the body squeezes through (px between its walls; cells are 4)
const SQUEEZE_MAX := 19.0      # Widest passage that is a squeeze; from 20 px the body walks at its full clearance
const SQUEEZE_RECOVER := 0.5   # Px a tick the clearance grows back after a squeeze, so the body eases out, never pops
const SQUEEZE_LOOK := 28.0     # How far across the walking line the passage scan looks
const SQUEEZE_DEPTH := 16.0    # A passage must run at least this far to be entered (a dent is not a passage)
const SQUEEZE_SLOW := 0.4      # Walking speed in a squeeze, as a fraction of the walk
const SQUEEZE_RELEASE := 6     # Ticks the passage must read wide, with the body inside it, before the squeeze ends
const SQUEEZE_GIVEUP := 40     # Ticks a squeeze may wait at a mouth without the body getting in
const SLOT_SCAN := 20.0        # How far along the surface a press into it looks for a slot to enter
const SLOT_CENTRE := 2.5       # Px a tick the body is centred over a slot it is entering (about the walk)
const THIN_SMOOTH := 0.15      # Per-tick blend of a drawn body point's radius toward the passage it is in
const THIN_STEP := 0.25        # Most a drawn body point moves toward a passage's middle in one tick
const THIN_DEAD := 0.5         # A point this close to the middle stays put (the spans are whole pixels)
const THIN_MARGIN := 2.0       # Px between a thinned point's drawn edge and the passage wall: a pixel of air, so the edge never sits on a pixel boundary and flickers
const NORMAL_SMOOTH := 0.35    # Per-tick blend of the surface normal target (jagged ground flickers)
const NORMAL_SMOOTH_FINE := 0.08  # The blend for small changes: rough walls and edges wobble the normal every tick
const NORMAL_SMOOTH_WOBBLE := 0.04  # The blend once the raw normal has turned back and forth two ticks running: a stair-stepped wall
const NORMAL_FINE_DOT := 0.9   # A change under ~25 degrees counts as small
const AWAY_LOOK := 200.0       # How far along a steep surface the away rule looks for its inside corner
const HEAD_RECOVER := 180.0    # Speed the snout comes forward again after a wall held it back (px/s)
const HEAD_RETRACT := 240.0    # Speed the snout draws back at a wall (px/s); the push-out covers the rest
const FLIP_CONFIRM := 4        # Ticks a big change of surface normal must persist before the body follows it
const FLIP_DOT := 0.7          # A normal this far from the target (cosine, ~45 degrees) is a big change
const HOLD_AFTER_GRAB := 15    # Ticks after a grab lands during which big changes of normal are ignored
const LEG_BLOB_GAP := 4.5      # Largest spacing of the blobs along a leg, so a stretched leg stays one shape
const HOLD_TIME := 0.12        # Left button held this long with the tongue landed: a grapple, not a strike
const TONGUE_SPEED := 900.0
const TONGUE_MAX := 160.0
const PULL_SPEED := 360.0      # The body reeled in on the tongue (the grapple)
const PULL_ACCEL := 2400.0
const STRIKE_R := 4.0          # Dent a tongue strike leaves in the ground: a cell or so (was 8: it ate the ground)
const STRIKE_BREAK_R := 10.0   # Round the tip of a strike on a lump, its bonds break
const PULL_MAX_CELLS := 320    # Biggest piece the tongue drags in (cells of 2 px, a turned lump fills more); a bigger one holds it
const EAT_MAX_CELLS := 64      # Biggest piece swallowed when it reaches the mouth
const EAT_REACH := 16.0        # A dragged piece this close to the mouth is swallowed, or let go
const EAT_R := 28.0            # How far round the mouth the swallow reaches
const CHUNK_PULL_SPEED := 150.0
const PUSH_LUMP_SPEED := 60.0  # Speed a shoved lump is moved at, as one, ahead of the walk
const PUSH_SPEED := 50.0       # Walking speed kept up behind a lump being shoved
const PUSH_TRIES := 30         # Ticks of shoving a lump that does not move before it counts as a wall
const PEBBLE_CELLS := 24       # A lump of this many cells or fewer is stepped over, not shoved
const BRACE_BACK := 5.0        # Snout drawn back while the gecko strains on its tongue
const GULP_TIME := 0.5         # Seconds a swallowed piece takes to travel down the body
const EAT_OPEN := 0.09         # Seconds the mouth takes to open for a piece coming in
const EAT_AGAPE := 0.1         # Seconds it stays open after the swallow
const EAT_CLOSE := 0.07        # Seconds it takes to close
const GAPE_LEAD := 12.0        # A piece this far beyond EAT_REACH already opens the mouth
const SWIM_SPEED := 80.0       # Mean speed; the kick peaks above it (1.7x), the glide falls below (was 120: too quick a swimmer)
const SWIM_ACCEL := 700.0
const SWIM_DRAG := 300.0
const SWIM_PERIOD := 0.7       # One kick and glide
const SWIM_KICK := 0.35        # Fraction of the period the legs push
const BODY_COLOR := Color(0.56, 0.63, 0.40)
const TONGUE_COLOR := Color(0.80, 0.42, 0.48)
const FAR_LEG_COLOR := Color(0.34, 0.40, 0.24)
const EYE_COLOR := Color.BLACK
const MOUTH_COLOR := Color(0.24, 0.08, 0.10)
const LIFT_EASE := 1.0         # Px a tick the drawn body's lift moves between its lifted line and a passage's middle
const IDLE_AFTER := 2.0        # Seconds of nothing happening before the idle animations begin
const IDLE_GAP_MIN := 1.5      # Seconds between one idle animation and the next
const IDLE_GAP_MAX := 3.5
const BLINK_TICKS := [2, 6, 2]   # Lid closing, shut, opening
const LICK_TICKS := [6, 6, 6]    # Tongue out to the eye, on it, back
const YAWN_TICKS := [5, 16, 4]   # Mouth opening, agape, closing
const YAWN_GAPE := 6.0           # Px the jaw drops at the widest
const LICK_SAMPLES := 20         # Marks along the tongue's curve at full stretch
const THIN_RELEASE := 1.0        # Most a point whose drawn radius is still growing back from a thinning is pushed off rock in one tick


class Foot:
	var hip := 1              # Chain point the leg hangs from
	var end := 1.0            # +1 front, -1 back
	var side := 1.0           # +1 near (drawn over the body), -1 far
	var planted := false
	var anchor := Vector2.ZERO
	var pos := Vector2.ZERO
	var stepping := false
	var step_from := Vector2.ZERO
	var step_to := Vector2.ZERO
	var step_t := 0.0


var map: Node2D
var blobs: Node2D
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var up := Vector2.UP
var facing := 1.0
var speed_along := 0.0
var clinging := false
var no_cling := 0.0
var feet_short := 0.0
var chain: Chain
var feet: Array[Foot] = []
var look := Vector2.RIGHT      # Where the head points: toward the mouse, within LOOK_LIMIT of the body line
var _pos_s := Vector2.ZERO     # Body centre with its across-surface bounce filtered out, for the drawn body
var input_override = null      # Vector2 from the demo pilot, null for real input
var jump_override := false
var chew_override := false
var lmb_override := false      # Demo pilot's left button
var aim_override := Vector2.ZERO  # Demo pilot's cursor, relative to the body
var chewing := false
var _bite := Vector2.ZERO
var swimming := false
var _swim_phase := 0.0         # 0..1 through the kick cycle
var tongue_out := false
var tongue_anchored := false
var tongue_retracting := false
var tongue_tip := Vector2.ZERO
var tongue_dir := Vector2.ZERO
var tongue_chunk := -1         # The lump the tongue is stuck to, -1 for the ground
var tongue_mode := 0           # Stuck: 0 undecided (a tap or a hold), 1 grapple (the body reeled in), 2 drag (both buttons)
var pulling := false           # This tick the tongue dragged a lump in (trace)
var straining := false         # Stuck to something that will not come (trace, brace)
var debug := false             # F1: overlay with up vector, probe reach, feet and bite
var mouse_blocked := false     # The mouse is over the debug panel: no tongue or chew from it
var _lmb := false              # This tick's left button
var _lmb_was := false          # Last tick's, for the press edge
var _press_t := 0.0            # Seconds the left button has been held since the shot
var _gulp := 0.0               # Seconds left of a swallow travelling down the body
var _gape := 0.0               # Px the mouth is open
var _gape_want := false        # This tick a piece is coming in: the mouth opens
var _gape_chew := false        # The gape is a bite's: drawn as parted lips, not the yawn's dropped jaw
var extra_blobs: Array = []    # Blobs drawn with the body's by the blob layer: the slugs (main.gd sets it before the tick)
var glow_boost := 0.0          # Seconds left of the brighter glow a swallowed slug gives (main.gd reads it)
var glow_snuff := 0.0          # Seconds left with the glow out after a gas burst
var _heat := 0.0               # Seconds a foot has been on hot rock
var _crumble_load := 0.0       # Seconds a foot has been on crumbling rock
var _agape := 0.0              # Seconds left of holding the mouth open after a swallow
var _block_cell = null         # The cell that stopped this tick's walk, null when none
var _push_ticks := 0           # Ticks in a row the walk has been shoving the same lump
var _n_target := Vector2.UP    # Smoothed surface normal the up vector turns toward
var _grab_n := Vector2.ZERO    # Normal of the surface the gecko is turning onto, zero when none

var _debug_layer: Node2D
var _under: Node2D             # Drawn beneath the body: the tongue, so it emerges from the snout
var _last_probe := {}
var _block_normal := Vector2.ZERO
var _bridging := false         # Crossing a gap shorter than the body: keep the line, no nudge, no drop
var _blocked := false          # This tick's walk was stopped by rock (trace)
var _squeezed_f := false       # This tick the body was wedged in a crevice (trace)
var _s := 0.0                  # This tick's input scalar along the surface (trace)
var _n_dbg := Vector2.ZERO     # This tick's chosen surface normal (trace)
var _jumped := false           # This tick began a jump (trace)
var _lift_ticks := 0           # Ticks spent lifting over the same low obstacle
var _s_dead := false           # The input scalar is in its dead band (hysteresis, so it does not flicker)
var _away_s := 0.0             # The away rule's choice of direction, held while the input holds
var _away_w := Vector2.ZERO    # That choice as a world direction, to tell a bulge from a corner turned
var _last_inp := Vector2.ZERO  # Last tick's input, to tell a held press from a new one
var _press_stop := false       # The held press ran against itself on a bulge: stopped until it changes
var _step_climb := false       # Pressing into a short step: the press means up its face and over
var _climb_dir := Vector2.UP   # World direction of the step's free end, the body's up when it met the step
var _head_back := 0.0          # How far the snout is held back from its lead by a wall
var _flip_ticks := 0           # Consecutive ticks the surface normal has disagreed with the target by a lot
var _hold_ticks := 0           # Ticks left of holding the surface a grab just landed on
var _up_rate := 0.0            # Radians the up vector turned last tick
var _lifting := false          # This tick the walk lifted the body over a low obstacle
var _bridge_miss := 0          # Ticks in a row the gap-ahead test has failed while bridging
var _n_raw := Vector2.ZERO     # Last tick's raw surface normal
var _n_streak := 0             # Ticks the raw normal has kept turning the same way
var _n_sign := 0.0
var _n_alt := 0                # Ticks the raw normal has alternated its turn direction
var _dig_aim := Vector2.ZERO   # Unit dig direction while chewing after the cursor, zero otherwise
var _chew_t := 0.0             # Seconds into the bite cycle while chewing
var _digging := false          # Chewing with rock within DIG_LOOK of the bite: the walk slows to the dig
var _burrowing := false        # This tick the walk went on through loose grains (sand, clay)
var _squeeze := false          # In a passage narrower than the body: less clearance, slow, the body thinned
var _sq_r := BODY_R            # The clearance while squeezing
var _sq_in := false            # The body centre has been inside the passage
var _sq_wide := 0              # Ticks in a row the passage has read wide
var _sq_wait := 0              # Ticks at the mouth without getting in
var _sq_enter := false         # Turning nose first into a slot below: no wall pull, the body centred over the slot
var _sq_target := Vector2.ZERO # World point the body is centred on while entering a slot
var _sq_n := Vector2.ZERO      # The slot's wall normal the entry committed to
var _sq_up := Vector2.UP       # The squeeze's frame: up snapped to a world axis, held through the passage
var _sq_line := Vector2.ZERO   # A world point on the passage's middle line: the mouth's at first, then the body's own column
var _draw_r := PackedFloat32Array()  # Drawn radius per chain point: thinned where the point is in a narrow passage
var _thin_on := PackedByteArray()    # Per chain point: between two walls closer than its body (hysteresis)
var _lift := BODY_LIFT         # The drawn body's lift off the body centre's line: BODY_LIFT, or in a passage the way to its middle
var _idle_t := 0.0             # Seconds of nothing happening: clinging, no keys, no buttons
var _anim := ""                # The idle animation playing: blink, lick, yawn; empty for none
var _anim_tick := 0            # Ticks into it
var _anim_gap := 0.0           # Seconds of idling left before the next one
var _anim_bag: Array = []      # The animations still to play this round, shuffled
var _rng := RandomNumberGenerator.new()  # The face's own generator, so the suite's seeded bites and steps are untouched
var _tick := 0
var _trace := OS.get_environment("GECKO_TRACE") != ""
var _inp := Vector2.ZERO       # This tick's input vector (trace)


func _ready() -> void:
	z_index = 6
	chain = Chain.new(Vector2.ZERO, RADII, LINK, MAX_BEND)
	_draw_r = PackedFloat32Array(RADII)
	_thin_on.resize(RADII.size())
	_thin_on.fill(0)
	var seed_env := OS.get_environment("GECKO_SEED")
	if seed_env != "":
		_rng.seed = int(seed_env)
	else:
		_rng.randomize()
	for end in [1.0, -1.0]:
		for side in [1.0, -1.0]:
			var f := Foot.new()
			f.hip = FRONT_HIP if end > 0.0 else BACK_HIP
			f.end = end
			f.side = side
			feet.append(f)
	_under = Node2D.new()
	_under.z_index = -2
	_under.draw.connect(_draw_under)
	add_child(_under)
	_debug_layer = Node2D.new()
	_debug_layer.z_index = 14
	_debug_layer.draw.connect(_draw_debug)
	add_child(_debug_layer)


# Puts the gecko at rest on a surface whose normal is up_dir (the floor
# by default; the test scenes also start it on walls and ceilings).
func spawn(at: Vector2, up_dir := Vector2.UP) -> void:
	pos = at
	vel = Vector2.ZERO
	up = up_dir
	facing = 1.0
	speed_along = 0.0
	clinging = true
	no_cling = 0.0
	feet_short = 0.0
	look = Vector2.RIGHT
	_pos_s = at
	swimming = false
	tongue_out = false
	tongue_anchored = false
	tongue_retracting = false
	tongue_chunk = -1
	pulling = false
	straining = false
	_gulp = 0.0
	_gape = 0.0
	_gape_chew = false
	_agape = 0.0
	_chew_t = 0.0
	_digging = false
	_burrowing = false
	_push_ticks = 0
	_n_target = up_dir
	_grab_n = Vector2.ZERO
	_end_squeeze()
	_sq_r = BODY_R
	_lift = BODY_LIFT
	_anim = ""
	_idle_t = 0.0
	var fwd := _tangent()
	look = fwd
	chain.reset(pos + fwd * HEAD_LEAD, fwd)
	for f in feet:
		f.planted = false
		f.stepping = false
		f.pos = chain.points[f.hip]


var tick_us := 0               # The last tick's time in microseconds, for GECKO_TIMING (main.gd)


func _physics_process(dt: float) -> void:
	var _tick_t0 := Time.get_ticks_usec()
	var inp := _read_input()
	var jump := _read_jump()
	_blocked = false
	_lifting = false
	_squeezed_f = false
	_s = 0.0
	_n_dbg = Vector2.ZERO
	_jumped = false
	pulling = false
	straining = false
	_block_cell = null
	no_cling = maxf(no_cling - dt, 0.0)
	_gulp = maxf(_gulp - dt, 0.0)
	glow_boost = maxf(glow_boost - dt, 0.0)
	glow_snuff = maxf(glow_snuff - dt, 0.0)
	_dig_aim = Vector2.ZERO
	if not _squeeze:
		_sq_r = move_toward(_sq_r, BODY_R, SQUEEZE_RECOVER)
	_update_mouse(dt)
	# The mouth is busy while the tongue is out or the left button is down.
	chewing = _read_chew() and not tongue_out and not _lmb
	if chewing:
		var aim := _aim_dir()
		var dir: Vector2
		if aim == Vector2.ZERO:
			# No cursor (a gamepad, or the demo pilot without an aim): bite
			# the way the input points, straight ahead with none.
			dir = inp.normalized() if inp.length() > 0.2 else _tangent() * facing
		else:
			# The mouth follows the cursor. With no key held the body creeps
			# after the bite, so a held button and a pointed cursor tunnel
			# there on their own; a held key still steers the body.
			if inp.length() <= 0.2 and _cursor().distance_to(pos) > CHEW_REACH:
				inp = aim
			_dig_aim = aim
			dir = _within_look(aim)
		# One bite a CHEW_PERIOD: the jaw opens through the cycle
		# (_update_gape) and the bite lands as it shuts, so digging is
		# eating, bite by bite, and no faster than the jaw. With rock in
		# reach of the bites the walk slows to the dig (DIG_SPEED); in
		# the open the chew key costs nothing.
		_chew_t += dt
		if _chew_t >= CHEW_PERIOD:
			_chew_t -= CHEW_PERIOD
			_chew(dir)
		_digging = map.ray_hit(pos, dir, DIG_LOOK) != null
	else:
		_chew_t = 0.0
		_digging = false
	var in_water: bool = map.water_near(pos, 1)
	if in_water and not clinging and not swimming and not tongue_anchored:
		swimming = true
		splashed.emit(pos)
		vel *= 0.4
	elif swimming and not in_water:
		swimming = false
	if tongue_anchored and not clinging:
		_update_pull(dt)
	elif swimming:
		_update_swimming(inp, dt)
	elif clinging:
		if tongue_anchored:
			# Braced on the tongue: the feet stay planted, nothing else moves.
			inp = Vector2.ZERO
			jump = false
		_update_clinging(inp, jump, dt)
		_surface_rules(dt)
	else:
		_update_airborne(inp, dt)
	_update_tongue(dt)
	_update_gape(dt)
	_update_chain(dt)
	_push_body()
	_update_look(dt)
	_update_feet(dt)
	_update_idle(inp, dt)
	_tick += 1
	_inp = inp
	if _trace:
		_print_trace()
	_push_blobs()
	queue_redraw()
	_under.queue_redraw()
	_debug_layer.queue_redraw()
	tick_us = Time.get_ticks_usec() - _tick_t0
	ticked.emit()


# The body's push on loose grains: two capsules along the drawn chain,
# head to mid-body and mid-body to the tail's root, so sand poured on
# the gecko piles on its back and a burrowing body shoves the grains
# aside (sim_map.gd; the bitmap has no grains).
func _push_body() -> void:
	var pts := chain.points
	map.body_capsules(pts[0], pts[3], PUSH_R_FRONT, pts[3], pts[6], PUSH_R_BACK)


# The drawn body's base: what the camera follows, since the body centre
# can shift a fraction of a pixel on jiggling ground while this stays.
func draw_pos() -> Vector2:
	return _pos_s if clinging else pos


func _read_input() -> Vector2:
	if input_override != null:
		return input_override
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


# One line per physics tick, key=value fields, for tools/analyze.py.
# Feet are x,y,planted,stepping per foot, front near, front far, back
# near, back far. cp is the chain, head first: offset along the
# tangent, offset along up, drawn radius, thinned.
func _print_trace() -> void:
	var hd := chain.head()
	var state := "cling" if clinging else ("swim" if swimming else "air")
	if tongue_anchored and not clinging:
		state = "pull"
	var fs := ""
	for f in feet:
		fs += "%.1f,%.1f,%d,%d;" % [f.pos.x, f.pos.y, 1 if f.planted else 0, 1 if f.stepping else 0]
	var cp := ""
	for i in chain.size():
		cp += "%.1f/%.1f/%.1f/%d;" % [(chain.points[i] - pos).dot(_tangent()), (chain.points[i] - pos).dot(up), _draw_r[i], _thin_on[i]]
	print("t%d pos=%.2f,%.2f draw=%.2f,%.2f head=%.2f,%.2f up=%.3f,%.3f dist=%.1f spd=%.1f state=%s facing=%d inp=%.2f,%.2f s=%.2f blk=%d grab=%d bridge=%d sq=%d chew=%d jump=%d n=%.2f,%.2f bn=%.2f,%.2f sc=%d sqz=%d ps=%d an=%s tng=%s tip=%.1f,%.1f cp=%s feet=%s" % [
		_tick, pos.x, pos.y, _pos_s.x, _pos_s.y, hd.x, hd.y, up.x, up.y,
		_last_probe.get("dist", -1.0), speed_along, state, int(facing), _inp.x, _inp.y, _s,
		1 if _blocked else 0, 1 if _grab_n != Vector2.ZERO else 0, 1 if _bridging else 0,
		1 if _squeezed_f else 0, 1 if chewing else 0, 1 if _jumped else 0, _n_dbg.x, _n_dbg.y,
		_block_normal.x, _block_normal.y, 1 if _step_climb else 0, 1 if _squeeze else 0, 1 if _press_stop else 0,
		_anim if _anim != "" else "-", _tongue_state(), tongue_tip.x, tongue_tip.y, cp, fs])


# in, out, stuck, grapple, drag, strain, back: what the tongue is doing (trace, panel).
func _tongue_state() -> String:
	if not tongue_out:
		return "in"
	if tongue_retracting:
		return "back"
	if pulling:
		return "drag"
	if straining:
		return "strain"
	if tongue_anchored:
		return "grapple" if tongue_mode == 1 else "stuck"
	return "out"


func _read_jump() -> bool:
	if input_override != null:
		var j := jump_override
		jump_override = false
		return j
	return Input.is_action_just_pressed("jump")


func _read_chew() -> bool:
	if input_override != null:
		return chew_override
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not Input.is_key_pressed(KEY_CTRL) and not mouse_blocked:
		return true
	return Input.is_action_pressed("chew")


# One bite CHEW_REACH ahead of the body centre in dir. Its height is
# anchored to the row the gecko stands on, within reach of the body's own
# level, so a level tunnel keeps its floor and the body always fits
# through the hole it chews.
func _chew(dir: Vector2) -> void:
	var floor_pt = map.ray_hit(pos, -up, RAY_LEN)
	var base: Vector2 = floor_pt if floor_pt != null else pos - up * RIDE_H
	var play := CHEW_R - BODY_R - 1.0
	var h := clampf((base + up * (CHEW_R + 3.0) - pos).dot(up), -play, play)
	_bite = pos + up * h + dir * CHEW_REACH
	# Each bite lands a little off and a little different in size, so a
	# tunnel comes out ragged like something chewed, not drilled.
	var jitter := Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
	map.erase_circle(_bite + jitter, randf_range(CHEW_R - 2.5, CHEW_R + 0.5))
	bit.emit(_bite)
	# Wedged against its own tunnel's wall, where the bite ahead cannot
	# reach back to a ragged bit at the shoulder: a bite round the body
	# itself frees it.
	if map.solid_within(pos + dir * 2.0, BODY_R):
		map.erase_circle(pos + dir * 3.0, BODY_R + 2.0)


# The dig direction from the cursor: body centre to cursor, snapped to a
# world axis when nearly on one (a flat tunnel stays flat, a shaft stays
# straight). Zero without a cursor (the demo pilot with no aim) or with
# the cursor on top of the body.
func _aim_dir() -> Vector2:
	if input_override != null and aim_override == Vector2.ZERO:
		return Vector2.ZERO
	var to := _cursor() - pos
	if to.length() < DIG_DEAD:
		return Vector2.ZERO
	var dir := to.normalized()
	if absf(dir.x) < LEVEL_SNAP:
		dir = Vector2(0.0, signf(dir.y))
	elif absf(dir.y) < LEVEL_SNAP:
		dir = Vector2(signf(dir.x), 0.0)
	return dir


# While chewing after the cursor into rock, the normal that lays the
# walking line along the bite. Zero when not chewing that way, or when
# the dig line finds no rock (open cave: the body walks the surface it
# is on). Straight into or away from the surface, the gecko pitches
# forward, nose first.
func _dig_normal() -> Vector2:
	if _dig_aim == Vector2.ZERO:
		return Vector2.ZERO
	if map.ray_hit(pos, _dig_aim, DIG_LOOK) == null:
		return Vector2.ZERO
	var a := Vector2(-_dig_aim.y, _dig_aim.x)
	var da := up.dot(a)
	if absf(da) < 0.05:
		# Square to the body: the side nearer the world's up, so a level
		# tunnel out of a shaft is walked on its floor, and nose first when
		# that is square too (a shaft straight down from a floor, or
		# straight up at a ceiling): the up that lays the walking line,
		# the way the gecko faces, along the dig.
		da = Vector2.UP.dot(a)
		if absf(da) < 0.05:
			return Vector2(_dig_aim.y, -_dig_aim.x) * facing
	return a if da > 0.0 else -a


# dir pulled inside the head's look cone, so the mouth never bites back
# through the body: a cursor behind the gecko means turn round first.
func _within_look(dir: Vector2) -> Vector2:
	var off := chain.heading.angle_to(dir)
	if absf(off) > LOOK_LIMIT:
		return chain.heading.rotated(signf(off) * LOOK_LIMIT)
	return dir


func _tangent() -> Vector2:
	return Vector2(-up.y, up.x)


# The way along a steep surface to its nearer inside corner, where the
# next surface runs out along up, which is the way the player pressed.
# A face with no inside corner in reach (a pillar's side) is walked
# down, toward the floor.
func _away_dir(tangent: Vector2) -> float:
	var best := 0.0
	var best_k := INF
	for sgn in [1.0, -1.0]:
		var d: Vector2 = tangent * sgn
		var k := BODY_R
		while k <= AWAY_LOOK:
			var q: Vector2 = pos + d * k
			if map.solid_within(q, BODY_R - 1.0):
				if k < best_k:
					best_k = k
					best = sgn
				break
			if map.ray_hit(q, -up, RAY_LEN) == null:
				break
			k += 4.0
	if best != 0.0:
		return best
	return signf(tangent.y)


# On the ground, loose lumps are not terrain to the senses (the surface
# rays, the probe, the gap and wall tests): a lump ahead stops the walk
# as a thing in the way and is shoved, not read as a slope and climbed.
# They are terrain again standing on one, and after half a second of
# shoving one that will not budge, which is then climbed like rock.
# Collision (the walk's own steps) sees lumps either way.
func _update_clinging(inp: Vector2, jump: bool, dt: float) -> void:
	var floor_pt = map.ray_hit(pos, -up, RAY_LEN)
	var on_lump: bool = floor_pt != null and map.chunk_at_world(floor_pt) >= 0
	map.ignore_chunks = not on_lump and _push_ticks < PUSH_TRIES
	_cling_step(inp, jump, dt)
	map.ignore_chunks = false


func _cling_step(inp: Vector2, jump: bool, dt: float) -> void:
	var tangent := _tangent()
	var s := 0.0
	if inp.length() > 0.2:
		var raw := clampf(inp.dot(tangent) * sqrt(2.0), -1.0, 1.0)
		var away := inp.dot(up) > 0.5 and absf(tangent.y) > 0.5
		var held := inp == _last_inp
		# The step climb ends with the press, or once the body has turned
		# onto the step's face and left it (the surface is flat again).
		if not held or (_grab_n == Vector2.ZERO and absf(tangent.y) <= 0.5):
			_step_climb = false
		if not held:
			_press_stop = false
		if _press_stop:
			s = 0.0
		elif _away_s != 0.0 and held and away and absf(raw) < 0.7:
			# The away rule's choice holds while the press holds and the
			# surface is still steep and faced away from, so a leaning wall
			# that wobbles the projection cannot argue with it.
			s = _away_s
		elif _away_s != 0.0 and held and (tangent * raw).dot(_away_w) < -0.5:
			# The surface curled over (a bump on the wall): the press, read
			# on it now, leads back the way the away rule sent the body.
			# Stop, as at a wall, rather than reverse and loop between the
			# two readings; a new press decides afresh. A corner turned
			# onto a new surface (up a wall, then left along the floor
			# above) is across that way, not against it, and walks on.
			s = 0.0
			_away_s = 0.0
			_press_stop = true
		else:
			_away_s = 0.0
			s = raw
			# The dead band has hysteresis, so an input near its edge on a
			# surface that wobbles a degree or two does not start and stop
			# the gecko every tick.
			if absf(s) < (0.4 if _s_dead else 0.2):
				s = 0.0
			_s_dead = s == 0.0
			if s == 0.0 and _step_climb and inp.dot(up) < -0.5:
				# Pressing into a short step: along its face toward the free
				# end, which is the way up was pointing when the step blocked
				# the walk (world down for a step in the ceiling).
				s = signf(tangent.dot(_climb_dir))
			elif s == 0.0 and away:
				# Pressing away from a steep surface. A gecko already going
				# somewhere under this press keeps going (a leaning wall
				# that turned vertical under it); a fresh press from rest
				# walks toward the inside corner whose far surface runs the
				# pressed way: down a wall to the floor, up a ceiling step.
				if held and absf(speed_along) > 20.0:
					s = signf(speed_along)
				else:
					s = _away_dir(tangent)
				_away_s = s
				_away_w = tangent * s
		if _away_s != 0.0 and (tangent * s).dot(inp) < -0.5:
			# The way chosen for this press now runs against it: the surface
			# curled back (a bulge). Stop here, as at a wall, and do not
			# reverse, which would loop; a new press decides afresh.
			s = 0.0
			_away_s = 0.0
			_press_stop = true
	else:
		_away_s = 0.0
		_press_stop = false
	_last_inp = inp
	if absf(s) > 0.3:
		facing = signf(s)
	_s = s
	var top := WALK_SPEED * (SQUEEZE_SLOW if _squeeze else 1.0)
	if _digging:
		top = minf(top, DIG_SPEED)
	if _burrowing:
		top = minf(top, WALK_SPEED * BURROW_SLOW)
	speed_along = move_toward(speed_along, s * top, WALK_ACCEL * dt)
	# The walk's collision sees lumps whatever the senses do.
	var ignoring: bool = map.ignore_chunks
	map.ignore_chunks = false
	var blocked := not _step(tangent * speed_along * dt)
	# Loose grains (a bed of sand, a bank of clay) are no wall: a move
	# they alone block goes on through them, slowed, the body's push
	# shoving them aside (sim_map.gd). Rock beyond them still stops it.
	_burrowing = false
	if blocked and _block_cell != null and s != 0.0 and map.loose_at_world(_block_cell):
		map.ignore_loose = true
		blocked = not _step(tangent * speed_along * dt)
		map.ignore_loose = false
		_burrowing = not blocked
	map.ignore_chunks = ignoring
	_blocked = blocked
	# Stopped by a loose lump: shove it along, the whole lump moved as
	# one the way the walk points (a push on its near particles alone
	# rolls it up over the body, or flattens it), keeping a slow walk up
	# behind it, for a while before treating it as a wall (a lump
	# wedged against rock is climbed like one).
	var shoving := false
	var lump: int = map.chunk_at_world(_block_cell) if (blocked and _block_cell != null) else -1
	if lump >= 0 and s != 0.0 and _push_ticks < PUSH_TRIES:
		_push_ticks += 1
		map.pull_chunk(lump, pos, tangent * facing, PUSH_LUMP_SPEED)
		shoving = true
	elif not blocked:
		_push_ticks = 0
	if blocked:
		speed_along = s * PUSH_SPEED if shoving else 0.0
		# Stopped by the lip of a passage narrower than the body, the way
		# the press points: squeeze into it. The clearance drops to fit
		# and the nudge below brings the body down (or up) to its middle.
		if not _squeeze and not chewing and not shoving and s != 0.0:
			_passage_ahead()
	var p: Dictionary = map.probe(pos, PROBE_R)
	_last_probe = p
	# A body centre inside rock (a spawn in a wall, a brush fill, a bite
	# that missed) is pushed out along the probe normal before anything
	# else is decided, squeezed or not. Not out of loose grains: a buried
	# body keeps its place, the body's push clearing the grains round
	# it, where this nudge would float it up through sand pouring in.
	if p.found and p.dist < _clear_r() - 1.0 and not map.loose_at_world(p.nearest):
		# Rock all round (a passage) cancels the probe normal: then away
		# from the nearest cell, never blindly along up into the far wall.
		var out_dir: Vector2 = p.normal
		if out_dir == Vector2.ZERO:
			out_dir = (pos - p.nearest).normalized() if p.dist > 0.01 else up
		pos += out_dir * (_clear_r() - p.dist) * 0.5
	# A hole the gecko is chewing after the cursor is the way, not a gap.
	# Bridging ends only after the gap test has failed a few ticks in a
	# row: at the gap's edge the front ray hits and misses by turns.
	var gap := _gap_ahead() and _dig_aim == Vector2.ZERO and not _squeeze and not _sq_enter
	# A bridge that has carried the body away from any rock was wrong.
	if _bridging and p.found and p.dist > RIDE_H + 8.0:
		gap = false
		_bridge_miss = BRIDGE_HOLD
	if gap:
		_bridging = true
		_bridge_miss = 0
	elif _bridging:
		_bridge_miss += 1
		if _bridge_miss >= BRIDGE_HOLD:
			_bridging = false
	else:
		_bridging = false
	if (not p.found or p.dist > LOSE_SURFACE_D) and not _bridging:
		_drop()
		return
	# Blocked by rock ahead: turn up toward that rock's normal, so walking
	# into a wall ends standing on the wall, and up means climb. Chewing
	# through it instead, the gecko holds still and waits for the hole.
	# A turn onto another surface (a wall that blocked the move, or one
	# within reach that the input points along) is a commitment: up keeps
	# turning toward that surface's normal until it gets there, so a
	# tilted body half way round cannot talk itself out of it.
	# Wedged in a crevice, with rock close on both sides: no new grabs and
	# no nudge. The nearest rock flips sides every tick there, and anything
	# that follows it makes the gecko dance. It still follows the surface
	# under it and slides along its tangent, so it sits still or backs out.
	var squeezed := _squeezed()
	_squeezed_f = squeezed
	# A press straight into the surface over a slot in it (a crack in the
	# floor, narrower than the body is long) enters the slot nose first.
	if not _squeeze and not _sq_enter and not chewing and _grab_n == Vector2.ZERO \
			and s == 0.0 and inp.length() > 0.2 and inp.dot(up) < -0.5:
		_try_slot_entry(tangent)
	var n: Vector2
	var dig_n := _dig_normal()
	if _grab_n != Vector2.ZERO and absf(up.angle_to(_grab_n)) < 0.12:
		_grab_n = Vector2.ZERO
		_sq_enter = false
		_hold_ticks = HOLD_AFTER_GRAB
	_hold_ticks = maxi(_hold_ticks - 1, 0)
	if _grab_n != Vector2.ZERO:
		n = _grab_n
		speed_along = 0.0
		if _sq_enter:
			# Nose first into a slot: there is no wall to pull to yet, so
			# the body is centred over the slot's mouth instead.
			var off := (_sq_target - pos).dot(_sq_n)
			_move(_sq_n * clampf(off, -SLOT_CENTRE, SLOT_CENTRE))
		else:
			_move(-_grab_n * GRAB_PULL * dt)
	elif dig_n != Vector2.ZERO:
		# Chewing off the surface line into rock: up turns so the walking
		# line follows the bite, and the gecko climbs into the hole it
		# chews, head first down a shaft, up a wall it bites into.
		n = dig_n
		if absf(up.angle_to(n)) > DIG_GRAB_ANGLE:
			_grab_n = n
	elif blocked and (chewing or shoving):
		n = Vector2.ZERO
	elif blocked and not _squeeze:
		n = _obstacle_normal(inp)
		_grab_n = n
	else:
		n = _reach_for_wall(inp) if (not chewing and not squeezed and not _squeeze and inp.length() > 0.2) else Vector2.ZERO
		if n != Vector2.ZERO:
			_grab_n = n
			speed_along = 0.0
		else:
			n = _surface_normal(p)
	_n_dbg = n
	var up_before := up
	if n != Vector2.ZERO:
		# Whether the raw normal keeps turning the same way (a corner being
		# rounded) or turns back and forth (rough ground, an edge where
		# two readings take turns).
		var turn := _n_raw.angle_to(n) if _n_raw != Vector2.ZERO else 0.0
		var sgn := signf(turn) if absf(turn) > 0.01 else 0.0
		_n_streak = _n_streak + 1 if (sgn != 0.0 and sgn == _n_sign) else 0
		# Small alternating turns are a stair-stepped wall read by turns;
		# big ones are two surfaces taking turns (a crevice), followed.
		_n_alt = _n_alt + 1 if (sgn != 0.0 and _n_sign != 0.0 and sgn == -_n_sign and absf(turn) < 0.2) else 0
		if sgn != 0.0:
			_n_sign = sgn
		_n_raw = n
		# A big change of normal (another surface in the probe) must
		# persist a few ticks before it is followed, unless it is a
		# committed grab: at a corner where two surfaces take turns being
		# nearest, following each at once turns the body back and forth.
		var big := n.dot(_n_target) < FLIP_DOT
		_flip_ticks = _flip_ticks + 1 if (big and _hold_ticks == 0) else 0
		if _grab_n != Vector2.ZERO or _squeeze or (big and _flip_ticks >= FLIP_CONFIRM):
			# A grab, or a squeeze (the passage's frame, taken at once so
			# a tilt from the lip's pull does not steer the walk into it).
			_n_target = n
			_flip_ticks = 0
		elif big:
			pass
		else:
			# A steady turn (a corner) is followed fast; a wobble (rough
			# ground, an edge) blends in slowly, so the body neither
			# shivers on a ragged wall nor lags behind a corner.
			var k := NORMAL_SMOOTH if (_n_streak >= 2 or n.dot(_n_target) < NORMAL_FINE_DOT) else (NORMAL_SMOOTH_WOBBLE if _n_alt >= 2 else NORMAL_SMOOTH_FINE)
			_n_target = _n_target.slerp(n, k).normalized()
		up = _turn_toward(up, _n_target, SURF_TURN * dt)
	_up_rate = absf(up_before.angle_to(up))
	# Ride-height nudge, away from (or toward) the nearest rock rather
	# than along up, so a body squeezed against a side wall can get clear.
	# Ride-height nudge against the surface under the body only. Side
	# rock never pushes the body (the collision check already stops it
	# there), so a notch does not shove the gecko back and forth. Over an
	# edge, where no surface is under it, it pulls toward the nearest
	# rock instead, which is what wraps it round the corner.
	# Not while a lift or a grab pull is already moving the body across.
	# In a squeeze the body keeps to the middle of the passage instead,
	# and the squeeze ends once the passage has opened out round it.
	if _squeeze:
		if _grab_n == Vector2.ZERO:
			_squeeze_nudge()
		_update_squeeze()
	elif not squeezed and not _bridging and not _lifting and _grab_n == Vector2.ZERO:
		var floor_pt = _ray_fine(pos, -up, RAY_LEN)
		if floor_pt != null:
			var d: float = (pos - floor_pt).dot(up)
			var want := RIDE_H - 1.5
			# Under a low ceiling the body rides halfway between floor and
			# ceiling, so a tunnel its own height does not wedge it.
			var ceil_pt = _ray_fine(pos, up, RAY_LEN)
			if ceil_pt != null:
				want = minf(want, (d + (ceil_pt - pos).dot(up)) * 0.5)
			# Within the dead band the body is left where it is: in the
			# particle world the cells under it jiggle by a pixel, and
			# chasing them would rock the body (and the camera) for ever.
			if absf(want - d) > NUDGE_DEAD:
				_move(up * clampf((want - d) * minf(1.0, 20.0 * dt), -NUDGE_MAX, NUDGE_MAX))
		else:
			# Over an edge: toward the nearest rock, which wraps the body
			# round the corner, but never backward against the walk.
			var away: Vector2 = (pos - p.nearest).normalized() if p.dist > 0.01 else up
			var pull: Vector2 = away * clampf((RIDE_H - p.dist) * minf(1.0, 20.0 * dt), -NUDGE_MAX, NUDGE_MAX)
			var fwd: Vector2 = tangent * facing
			var back := pull.dot(fwd)
			if back < 0.0 and absf(speed_along) > 1.0:
				pull -= fwd * back
			_move(pull)
	if jump:
		_jumped = true
		_jump()
		return
	var planted := 0
	for f in feet:
		if f.planted:
			planted += 1
	if planted < MIN_FEET and not _bridging:
		feet_short += dt
	else:
		feet_short = 0.0
	if feet_short > FEET_GRACE:
		if p.found and p.dist <= RIDE_H + 2.0:
			# Too few feet planted but the surface is right here: let the
			# feet step again rather than drop and land on the spot.
			_unplant()
			feet_short = 0.0
		else:
			_drop()


func _update_airborne(inp: Vector2, dt: float) -> void:
	vel.y += GRAVITY * dt
	if absf(inp.x) > 0.2:
		vel.x = move_toward(vel.x, inp.x * AIR_MAX, AIR_ACCEL * dt)
	var blocked := not _move(vel * dt)
	var p: Dictionary = map.probe(pos, PROBE_R)
	_last_probe = p
	if not p.found:
		return
	var n: Vector2 = p.normal
	if n == Vector2.ZERO:
		n = (pos - p.nearest).normalized()
	if blocked:
		var into := vel.dot(n)
		if into < 0.0:
			vel -= n * into
	if no_cling <= 0.0 and p.dist <= RIDE_H + 2.0 and vel.dot(n) <= 0.0:
		_land(n)
		return
	var min_d := RIDE_H * 0.8
	if p.dist < min_d:
		pos += n * (min_d - p.dist)
		var vn := vel.dot(n)
		if vn < 0.0:
			vel -= n * vn


# In water the gecko swims like a frog: a kick that pushes it the way the
# input points, then a glide under drag, no gravity. It cannot rise
# through the surface; it leaves the water by pushing into rock and
# clinging to it, or on the tongue.
func _update_swimming(inp: Vector2, dt: float) -> void:
	if inp.length() > 0.2:
		_swim_phase = fmod(_swim_phase + dt / SWIM_PERIOD, 1.0)
		if _swim_phase < SWIM_KICK:
			vel = vel.move_toward(inp.normalized() * SWIM_SPEED * 1.7, SWIM_ACCEL * 2.0 * dt)
		else:
			vel = vel.move_toward(Vector2.ZERO, SWIM_DRAG * 0.4 * dt)
		if absf(inp.x) > 0.3:
			facing = signf(inp.x)
	else:
		vel = vel.move_toward(Vector2.ZERO, SWIM_DRAG * dt)
		if _swim_phase > 0.0:
			_swim_phase = minf(_swim_phase + dt / SWIM_PERIOD, 1.0)
			if _swim_phase >= 1.0:
				_swim_phase = 0.0
	if vel.y < 0.0 and not map.water_near(pos + Vector2(0.0, -RIDE_H), 1):
		vel.y = 0.0
	# A current carries the swimmer with the water, on top of the swim:
	# the kick's mean of 120 px/s makes no way against a faster flow.
	var flow: Vector2 = map.current_at(pos)
	if not _move((vel + flow) * dt):
		vel = Vector2.ZERO
	var p: Dictionary = map.probe(pos, PROBE_R)
	_last_probe = p
	up = _turn_toward(up, Vector2.UP, 6.0 * dt)
	if p.found and p.dist <= RIDE_H + 2.0 and inp.length() > 0.2:
		var n: Vector2 = (pos - p.nearest).normalized()
		if inp.normalized().dot(-n) > 0.3:
			swimming = false
			_land(n)


# What the surface under the feet does to the hold: see the constants.
func _surface_rules(dt: float) -> void:
	if not clinging:
		return
	var off_floor := up.y > SLICK_UP
	var hot := false
	var crumb_at := Vector2.INF
	for f in feet:
		if not f.planted:
			continue
		# Moss off a floor drops the gecko, unless it is chewing: the jaws
		# in the rock hold it, so a mossy wall is climbed by eating the
		# coat off ahead of the feet, slowly, and not by walking.
		if off_floor and not chewing and map.slick_world(f.pos):
			_drop(SLIP_NO_CLING)
			slipped.emit()
			return
		if map.lava_near(f.pos, HOT_CELLS):
			hot = true
		if map.crumble_world(f.pos):
			crumb_at = f.pos
		if up.y > SCREE_UP and map.loose_at_world(f.pos):
			map.wake(f.pos, SCREE_R)
	if off_floor and not swimming and map.drop_near(pos, DROP_CELLS):
		_drop(SLIP_NO_CLING)
		slipped.emit()
		return
	_heat = _heat + dt if hot else maxf(_heat - dt, 0.0)
	if _heat >= HOT_HOLD:
		_heat = 0.0
		_drop(SLIP_NO_CLING)
		slipped.emit()
		return
	_crumble_load = _crumble_load + dt if crumb_at != Vector2.INF else maxf(_crumble_load - dt * 2.0, 0.0)
	if _crumble_load >= CRUMBLE_HOLD:
		_crumble_load = 0.0
		map.crumble(crumb_at, CRUMBLE_R)
		crumbled.emit(crumb_at)
		_drop(SLIP_NO_CLING)


# A gas burst from a point (main.gd): thrown away from it, the hold
# lost, the glow out for a while.
func blast(from: Vector2, speed: float) -> void:
	_drop()
	swimming = false
	var away := (pos - from).normalized()
	if away == Vector2.ZERO:
		away = Vector2.UP
	vel = away * speed
	glow_snuff = BLAST_SNUFF
	blasted.emit()


# The mouth is at the snout's tip, on its underside, well away from the eye.
func _mouth() -> Vector2:
	return chain.head() + look * (SNOUT + 4.0) - up * 2.5


func _cursor() -> Vector2:
	if input_override != null:
		return pos + aim_override
	return get_global_mouse_position()


# The tongue. A press of the left button shoots it at the cursor, and
# where it lands it sticks while the button is down. A tap (released
# before the tongue has been held HOLD_TIME, landed or not) strikes: a
# dent in the ground, a lump broken where it is hit, and straight back.
# Held longer alone, it is the grapple: the gecko lets go and is reeled
# in to the anchor, and clings where it arrives. With the right button
# (or the chew key) held as well it drags: the gecko braces on its
# planted feet, a lump it can drag (PULL_MAX_CELLS) comes in and is
# swallowed at the mouth if small enough, or let go there; the ground,
# or a lump too big, holds the tongue taut until a button is released.
# Airborne or swimming there is nothing to brace on, so the tongue
# reels the gecko in whichever buttons are down.
func _update_mouse(dt: float) -> void:
	_lmb = lmb_override if input_override != null else (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not mouse_blocked)
	var pressed := _lmb and not _lmb_was
	_lmb_was = _lmb
	_press_t = 0.0 if pressed else _press_t + dt
	if pressed and not tongue_out:
		_shoot_tongue()
	if not tongue_anchored:
		return
	var rmb := _read_chew()
	if not _lmb:
		# A tap that landed: the strike happens as the button comes up.
		if tongue_mode == 0:
			_strike()
		_release_tongue()
	elif tongue_mode == 2 and not rmb:
		_release_tongue()
	elif tongue_mode == 0:
		if rmb:
			tongue_mode = 2
		elif _press_t >= HOLD_TIME:
			tongue_mode = 1
			if clinging:
				clinging = false
				_unplant()


func _shoot_tongue() -> void:
	tongue_shot.emit()
	tongue_out = true
	tongue_anchored = false
	tongue_retracting = false
	tongue_chunk = -1
	tongue_mode = 0
	tongue_tip = _mouth()
	tongue_dir = (_cursor() - tongue_tip).normalized()
	if tongue_dir == Vector2.ZERO:
		tongue_dir = look


# For a slug caught on the tip (slug.gd): the tongue comes back.
func release_tongue() -> void:
	_release_tongue()


# A slug at the mouth: swallowed, the bulge runs down, and the glow
# brightens for a while.
func gulp_slug() -> void:
	_gulp = GULP_TIME
	_agape = EAT_AGAPE
	glow_boost = 20.0
	swallowed.emit()


# Letting go: the tip flies back to the mouth before the tongue is gone.
func _release_tongue() -> void:
	tongue_anchored = false
	tongue_chunk = -1
	tongue_retracting = tongue_out


# The tip flies out in 2 px steps until it meets something solid or
# runs out of tongue, then sticks while the button is down, or strikes.
func _update_tongue(dt: float) -> void:
	if not tongue_out:
		return
	if tongue_retracting:
		var mouth := _mouth()
		var step := TONGUE_SPEED * dt
		if tongue_tip.distance_to(mouth) <= step + 3.0:
			tongue_out = false
			tongue_retracting = false
		else:
			tongue_tip += (mouth - tongue_tip).normalized() * step
		return
	if tongue_anchored:
		_hold_tongue()
		return
	var travelled := 0.0
	var step := TONGUE_SPEED * dt
	while travelled < step:
		var inc := minf(2.0, step - travelled)
		var next := tongue_tip + tongue_dir * inc
		if map.is_solid_world(next):
			tongue_tip = next
			tongue_hit.emit(next)
			if _lmb:
				tongue_anchored = true
				tongue_chunk = map.chunk_at_world(next)
				swimming = false
			else:
				_strike()
				_release_tongue()
			return
		tongue_tip = next
		travelled += inc
		if tongue_tip.distance_to(_mouth()) > TONGUE_MAX:
			_release_tongue()
			return


# The tip lands: a dent in the ground, or a lump broken where it is hit.
func _strike() -> void:
	if map.chunk_at_world(tongue_tip) >= 0:
		map.break_circle(tongue_tip, STRIKE_BREAK_R)
	else:
		map.erase_circle(tongue_tip, STRIKE_R)


# Stuck, with the gecko on the ground (airborne, _update_pull has the
# tongue): waiting on a tap or a hold, or dragging. The tip rides the
# lump's cells as it comes in.
func _hold_tongue() -> void:
	if not clinging:
		return
	if tongue_chunk < 0:
		if not map.solid_near(tongue_tip, 1):
			_release_tongue()
		elif tongue_mode == 2:
			straining = true
		return
	var piece: PackedVector2Array = map.chunk_piece(tongue_chunk, tongue_tip)
	if piece.is_empty():
		_release_tongue()
		return
	if tongue_mode != 2:
		return
	var mouth := _mouth()
	var near_tip := tongue_tip
	var best_tip := INF
	var near_mouth := INF
	for c in piece:
		var d := c.distance_squared_to(tongue_tip)
		if d < best_tip:
			best_tip = d
			near_tip = c
		near_mouth = minf(near_mouth, c.distance_to(mouth))
	tongue_tip = near_tip
	if piece.size() > PULL_MAX_CELLS:
		straining = true
		return
	if piece.size() <= EAT_MAX_CELLS:
		# A piece small enough to swallow: the mouth opens as it nears,
		# and once it is open and the piece at it, the piece is gone.
		if near_mouth <= EAT_REACH + GAPE_LEAD:
			_gape_want = true
			if near_mouth <= EAT_REACH and _gape >= YAWN_GAPE - 0.01:
				map.eat_chunk(tongue_chunk, mouth, EAT_R)
				_gulp = GULP_TIME
				swallowed.emit()
				_agape = EAT_AGAPE
				_release_tongue()
				return
	elif near_mouth <= EAT_REACH:
		_release_tongue()
		return
	var dir := (mouth - tongue_tip).normalized()
	if dir != Vector2.ZERO:
		map.pull_chunk(tongue_chunk, tongue_tip, dir, CHUNK_PULL_SPEED)
		pulling = true


# The mouth opens at EAT_OPEN's pace while a piece is coming in, stays
# open EAT_AGAPE after the swallow, and closes at EAT_CLOSE's.
func _update_gape(dt: float) -> void:
	_agape = maxf(_agape - dt, 0.0)
	var want := _gape_want or _agape > 0.0
	if chewing and not want:
		# Chewing: the jaw opens over the bite cycle and shuts over its
		# last CHEW_SNAP, the bite landing as it closes.
		var u := _chew_t / CHEW_PERIOD
		var open := u / (1.0 - CHEW_SNAP) if u < 1.0 - CHEW_SNAP else (1.0 - u) / CHEW_SNAP
		_gape = YAWN_GAPE * clampf(open, 0.0, 1.0)
		_gape_chew = true
	else:
		_gape = move_toward(_gape, YAWN_GAPE if want else 0.0, YAWN_GAPE / (EAT_OPEN if want else EAT_CLOSE) * dt)
		# A bite's gape closing after the chew key is let go keeps its
		# look until shut; a swallow's is the yawn's from the start.
		if want or _gape <= 0.0:
			_gape_chew = false
	_gape_want = false


# Reeling in: the body flies at the anchor and clings where it arrives.
# An anchor whose rock gets destroyed lets go.
func _update_pull(dt: float) -> void:
	if not map.solid_near(tongue_tip, 1):
		_release_tongue()
		return
	var to := tongue_tip - pos
	var d := to.length()
	var p: Dictionary = map.probe(pos, PROBE_R)
	_last_probe = p
	if d <= RIDE_H + 3.0 and p.found:
		_land((pos - p.nearest).normalized())
		_release_tongue()
		return
	vel = vel.move_toward(to / maxf(d, 0.001) * PULL_SPEED, PULL_ACCEL * dt)
	if not _move(vel * dt):
		if p.found:
			_land((pos - p.nearest).normalized())
			_release_tongue()
			return
		vel = Vector2.ZERO
	no_cling = 0.1
	up = _turn_toward(up, Vector2.UP, 4.0 * dt)


func _land(n: Vector2) -> void:
	landed.emit(vel.length())
	clinging = true
	up = n
	_n_target = n
	_grab_n = Vector2.ZERO
	_end_squeeze()
	# Feet re-seat under the body at once; their airborne positions were
	# relative to the old up and would stick out until the first step.
	var t := _tangent()
	for f in feet:
		f.planted = false
		f.stepping = false
		f.pos = chain.points[f.hip] + t * f.end * facing * FOOT_SPREAD - up * (RIDE_H - 3.0)
	speed_along = clampf(vel.dot(_tangent()), -WALK_SPEED, WALK_SPEED)
	if absf(speed_along) > 1.0:
		facing = signf(speed_along)
	vel = Vector2.ZERO
	feet_short = 0.0


# Lets go of the surface (the feet lost, or a surface that will not
# be held, _surface_rules): a fall that keeps the walk's speed, with
# no cling for a while so the drop is seen.
func _drop(no_cling_for := NO_CLING_TIME) -> void:
	clinging = false
	_grab_n = Vector2.ZERO
	_end_squeeze()
	vel = _tangent() * speed_along
	speed_along = 0.0
	no_cling = no_cling_for
	_unplant()


func _jump() -> void:
	jumped.emit()
	clinging = false
	_grab_n = Vector2.ZERO
	_end_squeeze()
	vel = up * JUMP_SPEED + _tangent() * speed_along
	speed_along = 0.0
	no_cling = NO_CLING_TIME
	_unplant()


func _unplant() -> void:
	for f in feet:
		f.planted = false
		f.stepping = false


# A walking move. Blocked by something low (a loose pixel, a small
# ledge: rock below the body's middle), the body lifts LIFT this tick
# and tries again, so it climbs over in a few ticks instead of stopping
# or hopping. Rock at body height is a wall and the move is blocked;
# so is a low obstacle that LIFT_TICKS of lifting have not cleared.
func _step(delta: Vector2) -> bool:
	var start := pos
	if _move(delta):
		_lift_ticks = 0
		return true
	# The failed move may have kept a part step: the lift starts over.
	pos = start
	if delta.length() < 0.01:
		return false
	var cell = map.blocking_cell(pos, pos + delta, _clear_r())
	var floor_pt = map.ray_hit(pos, -up, RAY_LEN)
	if cell == null or floor_pt == null or _lift_ticks >= LIFT_TICKS:
		return false
	# A loose lump is shoved, not climbed, unless it is a pebble or has
	# not budged under half a second of shoving.
	var lump: int = map.chunk_at_world(cell)
	if lump >= 0 and _push_ticks < PUSH_TRIES \
			and map.chunk_piece(lump, cell, PEBBLE_CELLS + 1).size() > PEBBLE_CELLS:
		return false
	# Mid-turn (an inside corner, an edge) the surface logic is already
	# carrying the body round: no lifting on top of it.
	if _up_rate > LIFT_TURN_MAX:
		return false
	# Height over the ground under the body, not over the body centre: a
	# tilted body must not read a wall's foot as a bump.
	if (cell - floor_pt).dot(up) > LIFT_LOW:
		return false
	var save := pos
	if _move(up * LIFT) and map.ray_hit(pos, -up, RIDE_H + LIFT * LIFT_TICKS + 4.0) != null:
		_lift_ticks += 1
		_lifting = true
		_move(delta)
		return true
	pos = save
	return false


# Moves pos by delta in 1 px sub-steps and stops at the first step that
# would bring the body centre within the clearance (BODY_R, less in a
# squeeze) of rock. Stuck beats tunnelling: the gecko never passes
# through ground. A body already inside rock (buried by the brush) is
# let move so it can be pushed out.
func _move(delta: Vector2) -> bool:
	# Collision sees loose lumps whatever the senses are ignoring.
	var ignoring: bool = map.ignore_chunks
	map.ignore_chunks = false
	var ok := _move_seeing_all(delta)
	map.ignore_chunks = ignoring
	return ok


func _move_seeing_all(delta: Vector2) -> bool:
	var length := delta.length()
	if length < 0.001:
		return true
	var r := _clear_r()
	if map.solid_within(pos, r):
		pos += delta
		return true
	var dir := delta / length
	var moved := 0.0
	while moved < length:
		var step := minf(1.0, length - moved)
		var next: Vector2 = pos + dir * step
		if map.solid_within(next, r):
			var cell = map.blocking_cell(pos, next, r)
			_block_normal = (next - cell).normalized() if cell != null else -dir
			_block_cell = cell
			return false
		pos = next
		moved += step
	return true


# Normal of the rock that blocked the move, as the new up, but only when
# the held input, read on that rock's surface, would carry the body away
# from the surface it is on now: up into a wall or an overhang turns and
# climbs; right into a wall stops at it (right would point into the
# rock), right into an overhang stays too (it would lead back down into
# the floor, and the gecko would rock between the two for ever).
func _obstacle_normal(inp: Vector2) -> Vector2:
	var n := _block_normal
	if n == Vector2.ZERO:
		return Vector2.ZERO
	var t_new := Vector2(-n.y, n.x)
	var s_new := inp.dot(t_new)
	# More or less square into the rock. A short step is climbed: the body
	# turns onto its face and the press carries it up and over. The step's
	# corner can tilt the blocking normal a little, which is no reason not
	# to climb it. A wall square ahead stops.
	if absf(s_new) < 0.5 and n.dot(up) >= STEP_TURN_DOT and _short_wall_ahead():
		_step_climb = true
		_climb_dir = up
		return n
	if absf(s_new) < GRAB_MIN_S:
		return Vector2.ZERO
	if n.dot(up) < MAX_TURN_DOT:
		return Vector2.ZERO
	if (t_new * signf(s_new)).dot(up) < -0.2:
		return Vector2.ZERO
	return n


# Rock ahead at body height that ends within STEP_CLIMB over the floor.
func _short_wall_ahead() -> bool:
	var ahead: Vector2 = pos + _tangent() * facing * (BODY_R + 3.0)
	if not map.is_solid_world(ahead):
		return false
	# Over a gap (bridging) there is no floor under the body: the step is
	# measured from where the floor would be, ride height below.
	var floor_pt = map.ray_hit(pos, -up, RAY_LEN)
	if floor_pt == null:
		floor_pt = pos - up * (RIDE_H - 1.5)
	var k := 0.0
	while k <= STEP_CLIMB:
		var q: Vector2 = ahead + up * k
		if not map.is_solid_world(q):
			return (q - floor_pt).dot(up) <= STEP_CLIMB + 6.0
		k += 2.0
	return false


# The clearance the body centre keeps from rock: BODY_R, less in a
# squeeze, where the passage is narrower than that allows, and growing
# back at SQUEEZE_RECOVER after one.
func _clear_r() -> float:
	return _sq_r


# The map's ray, which samples every 2 px, refined to the pixel: the
# ride height read from it must not jump 2 px as the body creeps a
# fraction of one, or the nudge chasing it rocks the body for ever.
func _ray_fine(p: Vector2, dir: Vector2, length: float):
	var hit = map.ray_hit(p, dir, length)
	if hit == null:
		return null
	var back: Vector2 = hit - dir
	if (back - p).dot(dir) >= 0.0 and map.is_solid_world(back):
		return back
	return hit


# Distance along dir from p to the first rock, in 1 px steps, or INF.
func _free_span(p: Vector2, dir: Vector2, max_len: float) -> float:
	var n := int(max_len)
	for i in range(n + 1):
		if map.is_solid_world(p + dir * i):
			return float(i)
	return INF


# The run of air along up through at: the one containing at, or the
# nearest to it within SQUEEZE_LOOK either way. h is its length in px,
# mid its middle as an offset along up from at, line a world point on
# that middle (between the pixel centres of the run's two ends, since
# the scan reads whole pixels); open means it reaches the end of the
# scan (not a passage but the open cave).
func _narrow_run(at_raw: Vector2, u: Vector2) -> Dictionary:
	var at := at_raw.round()
	var n := int(SQUEEZE_LOOK)
	var best := {"air": false, "h": 0.0, "mid": 0.0, "open": false, "line": Vector2.ZERO}
	var best_d := INF
	var k := -n
	while k <= n:
		if map.is_solid_world(at + u * k):
			k += 1
			continue
		var k0 := k
		while k <= n and not map.is_solid_world(at + u * k):
			k += 1
		var k1 := k - 1
		var d := 0.0 if (k0 <= 0 and 0 <= k1) else minf(absf(float(k0)), absf(float(k1)))
		if d < best_d:
			best_d = d
			best = {"air": true, "h": float(k1 - k0 + 1), "mid": (k0 + k1) * 0.5, "open": k0 == -n or k1 == n,
				"line": at + u * ((k0 + k1) * 0.5) + Vector2(0.5, 0.5)}
	return best


# The world axis nearest v. Passages in the cell world run along the
# axes, and a body tilted by a corner it is approaching must not scan
# them askew.
static func _axis(v: Vector2) -> Vector2:
	if absf(v.x) >= absf(v.y):
		return Vector2(signf(v.x), 0.0)
	return Vector2(0.0, signf(v.y))


func _squeeze_r(h: float) -> float:
	# The passage's walls are cells whose centres sit a cell / 2 outside
	# its air; the centre of the passage is (h + a cell) / 2 from each, and
	# the clearance leaves a pixel and a half of play, since the body is
	# centred from whole-pixel scans. Never less than the narrowest
	# passage allows: a crevice closing further is not squeezed into.
	return clampf((maxf(h, SQUEEZE_MIN) + map.CELL) * 0.5 - 1.5, 0.0, BODY_R)


func _begin_squeeze(h: float, u: Vector2, line: Vector2) -> void:
	_squeeze = true
	_sq_up = u
	_sq_line = line
	_sq_in = false
	_sq_wide = 0
	_sq_wait = 0
	_sq_r = _squeeze_r(h)


func _end_squeeze() -> void:
	_squeeze = false
	_sq_enter = false
	_sq_in = false
	_sq_wide = 0
	_sq_wait = 0


# A passage ahead along the walk, narrower than the body's clearance
# allows but wide enough to squeeze through, running on at least
# SQUEEZE_DEPTH: the squeeze begins. Called when the walk was blocked.
func _passage_ahead() -> bool:
	var u := _axis(up)
	var fwd := Vector2(-u.y, u.x) * facing
	var at := pos + fwd * (BODY_R + 2.0)
	var r := _narrow_run(at, u)
	if not r.air or r.open or r.h < SQUEEZE_MIN or r.h > SQUEEZE_MAX:
		return false
	if absf(r.mid) > RIDE_H + 8.0:
		return false
	var mouth: Vector2 = at + u * r.mid
	if _free_span(mouth, fwd, SQUEEZE_DEPTH) < SQUEEZE_DEPTH:
		return false
	# Still a passage further in, not a crevice closing to nothing: the
	# gecko is not wedged deeper and deeper into a V. Open cave there
	# instead is a hole through a thin wall (a door), squeezed through
	# all the same.
	var deeper := _narrow_run(at + fwd * SQUEEZE_DEPTH, u)
	if not deeper.air or (not deeper.open and (deeper.h < SQUEEZE_MIN or deeper.h > SQUEEZE_MAX + 4.0)):
		return false
	_begin_squeeze(r.h, u, r.line)
	return true


# A press into the surface over a slot in it: columns along the surface
# either side of the body are sounded along -up; a run of deep ones
# between shallow ones, at least SQUEEZE_MIN wide and narrower than a
# bridged gap, is a slot. The body turns nose first into it, as a wall
# grab onto its side, centred over its mouth, squeezing if it is narrow.
func _try_slot_entry(tangent: Vector2) -> void:
	var n := int(SLOT_SCAN)
	var deep: Array[bool] = []
	for k in range(-n, n + 1):
		deep.append(_free_span(pos + tangent * k, -up, RIDE_H + 24.0) > RIDE_H + 20.0)
	var best_k0 := 0
	var best_k1 := -1
	var best_d := INF
	var i := 0
	while i < deep.size():
		if not deep[i]:
			i += 1
			continue
		var i0 := i
		while i < deep.size() and deep[i]:
			i += 1
		var k0 := i0 - n
		var k1 := i - 1 - n
		if k0 == -n or k1 == n:
			continue
		var d := 0.0 if (k0 <= 0 and 0 <= k1) else minf(absf(float(k0)), absf(float(k1)))
		if d < best_d:
			best_d = d
			best_k0 = k0
			best_k1 = k1
	if best_k1 < best_k0:
		return
	var w := float(best_k1 - best_k0 + 1)
	if w < SQUEEZE_MIN or w >= BRIDGE:
		return
	_sq_enter = true
	_sq_target = pos + tangent * ((best_k0 + best_k1) * 0.5)
	_sq_n = _axis(tangent * facing)
	_grab_n = _sq_n
	_bridging = false
	speed_along = 0.0
	if w <= SQUEEZE_MAX:
		_begin_squeeze(w, _sq_n, _sq_target)


# In a squeeze the body keeps to the middle of the passage: the one it
# is in, or at the mouth, the one ahead.
func _squeeze_nudge() -> void:
	# Not while up is still turning, or still tilted from the passage's
	# frame (a corner's pull being undone): the nudge is across the
	# passage, and across a tilted frame it reads as a step back along
	# the walk.
	if _up_rate > LIFT_TURN_MAX or up.dot(_sq_up) < 0.98:
		return
	# The middle averaged over the columns here and a body length ahead
	# (those that read as the passage), so a ragged wall does not bob
	# the body from cell to cell, and at the mouth the body lines up
	# with the first columns, not one further in.
	var fwd := Vector2(-_sq_up.y, _sq_up.x) * facing
	var mid := 0.0
	var n := 0
	for k in [0.0, 4.0, 8.0, 12.0]:
		var a := _narrow_run(pos + fwd * k, _sq_up)
		if a.air and not a.open and a.h <= SQUEEZE_MAX + 4.0:
			mid += a.mid
			n += 1
	# A dead band above the scan's half-pixel steps, or the body rocks a
	# fraction of a pixel each tick chasing a middle that is not there.
	if n == 0 or absf(mid / n) < 0.75:
		return
	_move(_sq_up * clampf(mid / n * 0.5, -NUDGE_MAX, NUDGE_MAX))


# The squeeze ends once the passage round the body has read wide for
# SQUEEZE_RELEASE ticks, or when the body never got in.
func _update_squeeze() -> void:
	var fwd := Vector2(-_sq_up.y, _sq_up.x) * facing
	var r := _narrow_run(pos, _sq_up)
	var here: bool = r.air and not r.open and r.h <= SQUEEZE_MAX + 2.0
	if here and r.h < SQUEEZE_MIN - 1.0:
		# Pinched: the passage has closed past what the body can squeeze
		# through. The clearance grows back and pushes it out.
		_end_squeeze()
		return
	# The clearance fits the narrowest column of the passage over the
	# next body length (and here, once inside), so a narrowing step, or
	# one cell of a ragged wall standing proud, is passed rather than
	# stopped at, at the mouth as much as inside.
	var h: float = r.h if here else INF
	for k in [4.0, 8.0, 12.0]:
		var ahead := _narrow_run(pos + fwd * k, _sq_up)
		if ahead.air and not ahead.open and ahead.h >= SQUEEZE_MIN - 1.0 and ahead.h <= SQUEEZE_MAX + 2.0:
			h = minf(h, ahead.h)
	if h < INF:
		_sq_r = _squeeze_r(h)
	if here:
		_sq_in = true
		_sq_wide = 0
		_sq_wait = 0
		_sq_line = r.line
	elif _sq_in:
		_sq_wide += 1
		if _sq_wide >= SQUEEZE_RELEASE:
			_end_squeeze()
	else:
		_sq_wait += 1
		if _sq_wait >= SQUEEZE_GIVEUP:
			_end_squeeze()


func _squeezed() -> bool:
	var t := _tangent()
	var a = map.ray_hit(pos, t, SQUEEZE_D)
	var b = map.ray_hit(pos, -t, SQUEEZE_D)
	return a != null and b != null


# A wall within reach on either side of the body, as a new up, under the
# same rule as a blocking wall: only when the held input would then move
# the body along it and away from the surface it is on now. Without this
# a floor dipping toward a wall walks the gecko backward on up, since up
# projects on the slope as uphill.
func _reach_for_wall(inp: Vector2) -> Vector2:
	var t := _tangent()
	for side in [1.0, -1.0]:
		# Never a wall the input points away from: walking off a slab's
		# foot, its corner tilts the probe normal enough for the press
		# to read as along the face, and the gecko would grab the wall
		# behind it.
		if inp.dot(t * side) < -0.2:
			continue
		var hit = map.ray_hit(pos, t * side, BODY_R + REACH)
		if hit == null:
			continue
		# A loose lump is no wall to climb: the walk shoves it instead.
		if map.chunk_at_world(hit) >= 0:
			continue
		var q: Dictionary = map.probe(hit - t * side * 3.0, 10.0)
		var n: Vector2 = q.normal if q.found and q.normal != Vector2.ZERO else -t * side
		if n.dot(up) > 0.75 or n.dot(up) < MAX_TURN_DOT:
			continue
		var t_new := Vector2(-n.y, n.x)
		var s_new := inp.dot(t_new)
		if absf(s_new) < 0.3:
			continue
		if (t_new * signf(s_new)).dot(up) < -0.2:
			continue
		return n
	return Vector2.ZERO


# Surface normal from two rays cast down from ahead of and behind the
# body: the slope between their hits, so a bump beside the gecko does not
# tilt it. Falls back to the probe's centroid normal when a ray misses or
# starts inside rock, which happens at corners, where the centroid is
# what swings the gecko round smoothly.
func _surface_normal(p: Dictionary) -> Vector2:
	if _bridging:
		return up
	if _squeeze:
		# The passage's own frame: a corner's pull on the way in tilted
		# the body, and the squeeze straightens it.
		return _sq_up
	var t := _tangent()
	var sa := pos + t * RAY_HALF
	var sb := pos - t * RAY_HALF
	var a = map.ray_hit(sa, -up, RAY_LEN)
	var b = map.ray_hit(sb, -up, RAY_LEN)
	if a != null and a.distance_to(sa) < 1.0:
		a = null
	if b != null and b.distance_to(sb) < 1.0:
		b = null
	# A ray down a slot narrower than the body (a crack in the floor) is
	# not an edge: the surface goes on beyond it at the same level, and
	# the body is read on that, not tilted into the crack by the
	# centroid of the rock about it.
	if a == null and b != null:
		a = _past_gap(sa, t, b)
	elif b == null and a != null:
		b = _past_gap(sb, -t, a)
	if a != null and b != null:
		var along: Vector2 = a - b
		if along.length() > 1.0:
			var n := Vector2(along.y, -along.x).normalized()
			if n.dot(up) < 0.0:
				n = -n
			return n
	return p.normal


# The surface beyond a narrow gap under a ray that missed: the first of
# a few rays cast further along dir that hits at about the level of the
# other ray's hit, or null when the ground does not come back (an edge).
func _past_gap(from: Vector2, dir: Vector2, other: Vector2):
	for k in [6.0, 12.0, 18.0]:
		var q: Vector2 = from + dir * k
		var hit = map.ray_hit(q, -up, RAY_LEN)
		if hit != null and absf((hit - other).dot(up)) <= 6.0:
			return hit
	return null


# A gap shorter than the body: no ground under the front ray, ground
# under the back ray, and ground again BRIDGE ahead at about the same
# level. The gecko spans it instead of following the surface down into it.
func _gap_ahead() -> bool:
	var t := _tangent() * facing
	var front = map.ray_hit(pos + t * RAY_HALF, -up, RAY_LEN)
	if front != null:
		return false
	var back = map.ray_hit(pos - t * RAY_HALF, -up, RAY_LEN)
	if back == null:
		return false
	# Ground beyond at about the same level: within a few px of ride height,
	# not merely somewhere down the ray (a step in the ceiling, a lower far
	# side, are not bridged).
	var far = map.ray_hit(pos + t * BRIDGE, -up, RAY_LEN)
	return far != null and (pos + t * BRIDGE - far).dot(up) <= RIDE_H + BRIDGE_LEVEL


static func _turn_toward(a: Vector2, b: Vector2, max_angle: float) -> Vector2:
	var ang := a.angle_to(b)
	return a.rotated(clampf(ang, -max_angle, max_angle)).normalized()


# The head leads the chain. Clinging, it sits ahead of the body centre in
# the facing direction, and slides round to the other side on a turn so
# the body folds into a U behind it; the body is then laid along the
# surface behind it. Airborne, it points along the velocity and the body
# trails freely, only pushed out of rock.
func _update_chain(dt: float) -> void:
	# The drawn body hangs off a base that follows the body centre exactly
	# along the surface but only slowly across it, so bumps in the ground
	# do not bob the head: a chicken's head on its gyro.
	var target: Vector2
	if clinging:
		var t := _tangent()
		var d := pos - _pos_s
		var across := d.dot(up)
		_pos_s += t * d.dot(t) + up * across * BOB_SMOOTH
		across = (pos - _pos_s).dot(up)
		if absf(across) > BOB_MAX:
			_pos_s += up * (across - signf(across) * BOB_MAX)
		# At a wall the snout stops at the rock, drawn back along the body
		# line, instead of being shoved aside by the push-out; it comes
		# forward again at HEAD_RECOVER, not in one go. Stuck on the
		# tongue, the snout is held back as well: the gecko leaning back
		# on its feet, bracing.
		var brace := BRACE_BACK if (tongue_anchored and clinging) else 0.0
		var back := move_toward(_head_back, brace, (HEAD_RETRACT if brace > _head_back else HEAD_RECOVER) * dt)
		var back_max := minf(HEAD_LEAD - 4.0, maxf(back, _head_back + HEAD_RETRACT * dt))
		# The drawn body rides BODY_LIFT above the body centre's line, except
		# in a passage, where it lies on the passage's middle at the head: the
		# lift eases between the two, never jumps. A head targeted at the
		# lifted line in a passage sat inside the wall's clearance and was
		# pushed off the nearest wall cell every tick, with an along-passage
		# component that swept across each cell column and flipped at its
		# edge, so the head sawed back and forth as the body crept along.
		var want_lift := BODY_LIFT
		if _squeeze:
			# The middle at the head's own column once the head is in; the
			# squeeze's line (the mouth's, then the body's column) before,
			# so the head heads for the passage from the moment the squeeze
			# begins rather than being shoved in off the lip.
			var run := _narrow_run(chain.head(), _sq_up)
			var line: Vector2 = run.line if (run.air and not run.open and run.h <= SQUEEZE_MAX + 2.0) else _sq_line
			want_lift = (line - _pos_s).dot(up)
		_lift = move_toward(_lift, want_lift, LIFT_EASE)
		var base := _pos_s + up * _lift
		target = base + t * facing * (HEAD_LEAD - back)
		# The snout stops at rock ahead. In a passage the walls beside it are
		# always within the body's clearance, so the test there is the
		# squeeze's own, or the head would draw in the whole way through.
		var head_clear := _sq_r if _squeeze else chain.radii[0] + BODY_GAP
		while back < back_max and map.solid_within(target, head_clear):
			back = minf(back + 2.0, back_max)
			target = base + t * facing * (HEAD_LEAD - back)
		_head_back = back
	else:
		_pos_s = pos
		var dir := vel.normalized() if vel.length() > 20.0 else Vector2(facing, 0.0)
		target = pos + dir * HEAD_LEAD
	var head := chain.head()
	var to := target - head
	var dir := Vector2.ZERO
	var new_head := head
	if to.length() > 0.001:
		new_head = head + to.normalized() * minf(to.length(), HEAD_SPEED * dt)
	if to.length() > 2.0:
		dir = to.normalized()
		# The snout drawing back from a wall moves against the facing; that
		# is not a turn, and laying the body behind a backward heading
		# folds it up the wall. The body stays laid the way it faces. In a
		# passage the head is held between the walls and its travel reads
		# as mostly across, which would lay the body at a slant: there the
		# heading is the passage's own.
		if clinging and (_squeeze or dir.dot(_tangent() * facing) < -0.3):
			dir = _tangent() * facing
	elif clinging:
		dir = _tangent() * facing
	if clinging:
		_resolve_body(new_head, dir)
		return
	chain.set_head(new_head, dir)
	for i in chain.size():
		var r: float = chain.radii[i]
		var q: Dictionary = map.probe(chain.points[i], r + BODY_GAP)
		if q.found and q.dist < r + BODY_GAP:
			var away: Vector2 = (chain.points[i] - q.nearest).normalized() if q.dist > 0.01 else up
			chain.points[i] += away * (r + BODY_GAP - q.dist)


# Lays the body behind the head along the surface, one link at a time.
# Each link keeps the direction it trailed in last tick (so the body
# folds into a U on a turn), bent at most MAX_BEND from the link before;
# then the point is kept BODY_GAP off the nearest rock and the link
# length restored, before the next link starts from it. Link by link,
# the body turns an inside corner as an L instead of bunching up in it.
func _resolve_body(new_head: Vector2, dir: Vector2) -> void:
	if dir.length() > 0.001:
		chain.heading = dir.normalized()
	var old := chain.points.duplicate()
	var q0: Dictionary = map.probe(new_head, chain.radii[0] + BODY_GAP)
	# Between two walls closer than its clearance (a passage) the head is
	# centred by the thinning, like the body's points, not pushed off
	# whichever wall is nearer.
	if q0.found and q0.dist < chain.radii[0] + BODY_GAP and not _thin_on[0]:
		var away0: Vector2 = (new_head - q0.nearest).normalized() if q0.dist > 0.01 else up
		new_head += away0 * _push_len(0, chain.radii[0] + BODY_GAP - q0.dist)
	new_head = _thin_point(0, new_head, q0)
	chain.points[0] = new_head
	var prev_dir := -chain.heading
	for i in range(1, chain.size()):
		var anchor: Vector2 = chain.points[i - 1]
		var trail: Vector2 = old[i] - anchor
		var desired: Vector2 = trail.normalized() if trail.length() > 0.001 else prev_dir
		var ang := prev_dir.angle_to(desired)
		if absf(ang) > MAX_BEND:
			desired = prev_dir.rotated(signf(ang) * MAX_BEND)
		var p: Vector2 = anchor + desired * LINK
		var r: float = chain.radii[i]
		var q: Dictionary = map.probe(p, r + BODY_HUG)
		if q.found:
			var away: Vector2 = (p - q.nearest).normalized() if q.dist > 0.01 else up
			# Laid higher than its clearance, like the head, by BODY_LIFT
			# for the body and a pixel for the tail's tip, which drags
			# along the ground behind the lifted body.
			var want := r + BODY_GAP + lerpf(1.0, BODY_LIFT, clampf((r - 2.0) / 5.0, 0.0, 1.0))
			p = _thin_point(i, p, q)
			if _thin_on[i]:
				pass
			elif q.dist < want:
				p += away * _push_len(i, want - q.dist)
			else:
				p += away * (want - q.dist) * HUG_K
			p = anchor + (p - anchor).normalized() * LINK
		else:
			_thin_point(i, p, q)
		chain.points[i] = p
		prev_dir = (p - anchor).normalized()


# How far a point is pushed off rock within its clearance this tick: all
# the way, unless its drawn radius is still growing back from a
# thinning (leaving a passage), when the push is eased, so a point
# coming out of a mouth, between the floor and the lip's corner, does
# not pop from one to the other.
func _push_len(i: int, overlap: float) -> float:
	if _draw_r[i] < chain.radii[i] - 0.5:
		return minf(overlap, THIN_RELEASE)
	return overlap


# A chain point with rock on both sides closer than its radius allows (a
# passage narrower than the body) is centred between the two walls and
# its drawn radius thinned to the passage, instead of being pushed off
# one wall into the other every tick. Elsewhere the drawn radius
# recovers. Returns the point, moved only when it is in such a passage.
# The walls are looked for along the slant to the nearest cell, and in
# a squeeze along the passage's axis and its diagonals too, the
# narrowest line taken: at a mouth a point sits between the floor and
# the lip's corner, which are not opposite each other, and read along
# the line to whichever is nearer by turns it was pushed off the floor
# one tick and centred under the lip the next.
func _thin_point(i: int, p: Vector2, q: Dictionary) -> Vector2:
	var r: float = chain.radii[i]
	var want := r + BODY_GAP
	var target := r
	var out := p
	var narrow := false
	if q.found and q.dist < want + 2.0:
		var away: Vector2 = (p - q.nearest).normalized() if q.dist > 0.01 else up
		# Spans from the point's whole pixel, so the middle they give is
		# a fixed line the point settles on, not one that shifts half a
		# pixel with the point's own fraction and keeps it rocking.
		var base := p.round()
		var dirs: Array[Vector2] = []
		if _squeeze:
			var ax: Vector2 = _sq_up * (signf(away.dot(_sq_up)) if absf(away.dot(_sq_up)) > 0.01 else 1.0)
			var fwd := Vector2(-ax.y, ax.x)
			dirs = [ax, (ax + fwd).normalized(), (ax - fwd).normalized()]
		dirs.append(away)
		var span := INF
		var dir := away
		var d_near := 0.0
		var d_far := 0.0
		for d in dirs:
			var dn := _free_span(base, -d, want * 2.0)
			var df := _free_span(base, d, want * 2.0)
			if dn < INF and df < INF and dn + df < span:
				span = dn + df
				dir = d
				d_near = dn
				d_far = df
		if span < INF:
			# Narrow when both walls would be within the point's clearance
			# of its centred position, so the push-out off one wall could
			# not settle and would rock it between the two. With
			# hysteresis, so a passage about that width does not read
			# narrow and wide by turns.
			narrow = span < (2.0 * want + 4.0 if _thin_on[i] else 2.0 * want + 1.0)
			if narrow:
				# Toward the middle, settling within THIN_DEAD of it: the
				# spans are whole pixels, so chasing the exact middle
				# would rock the point a pixel each tick.
				var off := (base + dir * (d_far - d_near) * 0.5 - p).dot(dir)
				if absf(off) > THIN_DEAD:
					out = p + dir * signf(off) * minf(absf(off) - THIN_DEAD, THIN_STEP)
				target = minf(r, maxf(span * 0.5 - THIN_MARGIN, 2.0))
	_thin_on[i] = 1 if narrow else 0
	_draw_r[i] = lerpf(_draw_r[i], target, THIN_SMOOTH)
	return out


# The head looks at the mouse, within LOOK_LIMIT of the body line, so the
# gecko never looks back through itself. The demo pilot has no mouse and
# looks where it goes.
func _update_look(dt: float) -> void:
	var want := chain.heading
	if input_override == null or aim_override != Vector2.ZERO:
		var to_mouse := _cursor() - chain.head()
		if to_mouse.length() > 4.0:
			want = _within_look(to_mouse.normalized())
	look = _turn_toward(look, want, 16.0 * dt)


func _partner(f: Foot) -> Foot:
	for g in feet:
		if g.end == f.end and g.side != f.side:
			return g
	return f


func _diagonal(f: Foot) -> Foot:
	for g in feet:
		if g.end != f.end and g.side != f.side:
			return g
	return f


func _update_feet(dt: float) -> void:
	var tangent := _tangent()
	var stepping := 0
	for f in feet:
		if f.stepping:
			stepping += 1
	for f in feet:
		var hip: Vector2 = chain.points[f.hip]
		if f.stepping:
			f.step_t += dt / STEP_TIME
			if f.step_t >= 1.0:
				f.stepping = false
				f.planted = true
				f.anchor = f.step_to
				f.pos = f.anchor
				# A step sounds only when the body is going somewhere: the
				# feet re-step against a wall too, and that is no walk.
				if absf(speed_along) > 20.0:
					stepped.emit(f.pos, f.end > 0.0)
			else:
				# The step's arc, no higher than the leg's drop: flat in a passage.
				var drop := (hip - f.step_to).dot(up) - FOOT_LIFT
				var arc := minf(STEP_HEIGHT * _leg_scale(f), maxf(drop, 1.0))
				f.pos = f.step_from.lerp(f.step_to, f.step_t) + up * arc * sin(PI * f.step_t)
			continue
		if f.planted:
			if map.solid_near(f.anchor, 1) and f.anchor.distance_to(hip) < MAX_LEG:
				f.pos = f.anchor
			else:
				f.planted = false
		if swimming:
			# Frog kick: legs sweep back and out fast, then tuck slowly.
			f.planted = false
			var fwd := vel.normalized() if vel.length() > 10.0 else chain.heading
			var perp := Vector2(-fwd.y, fwd.x)
			var k: float
			if _swim_phase < SWIM_KICK:
				var u := _swim_phase / SWIM_KICK
				k = 1.0 - (1.0 - u) * (1.0 - u)
			else:
				k = 1.0 - (_swim_phase - SWIM_KICK) / (1.0 - SWIM_KICK)
			var tucked := hip + fwd * 2.0 + perp * f.end * 2.0
			var extended := hip - fwd * 12.0 + perp * (f.end * 7.0 + f.side * 2.0)
			f.pos = f.pos.lerp(tucked.lerp(extended, k), minf(1.0, 25.0 * dt))
			continue
		if not clinging:
			f.planted = false
			var hang := hip - up * 6.0 + tangent * f.end * facing * 4.0
			if f.pos.distance_to(hang) > 20.0:
				f.pos = hang
			else:
				f.pos = f.pos.lerp(hang, minf(1.0, 30.0 * dt))
			continue
		var lead := speed_along / WALK_SPEED * FOOT_LEAD
		var rest := hip + tangent * (f.end * facing * FOOT_SPREAD + lead) - up * RIDE_H
		# In a passage the hip rides close to the floor and the rest spot
		# falls inside it: the foot wants the surface, not a cell deep in.
		var back := 0.0
		while back < RIDE_H - 4.0 and map.is_solid_world(rest + up * back):
			back += 2.0
		rest += up * back
		var q: Dictionary = map.probe(rest, LEG_REACH)
		if q.found and q.nearest.distance_to(hip) > MAX_LEG:
			q.found = false
		if not q.found:
			if not f.planted:
				f.pos = f.pos.move_toward(rest, FOOT_SETTLE * dt)
			continue
		var threshold := STEP_LEN * (0.5 if _diagonal(f).stepping else 1.0)
		if f.planted and f.anchor.distance_to(q.nearest) <= threshold:
			continue
		if _partner(f).stepping or (f.planted and stepping >= 2):
			# This foot waits its turn in the trot. One that is not planted
			# does not hang where it was left (a cliff top the body has
			# gone over, 50 px behind) but closes on its rest spot meanwhile.
			if not f.planted:
				f.pos = f.pos.move_toward(rest, FOOT_SETTLE * dt)
			continue
		f.stepping = true
		f.planted = false
		f.step_from = f.pos
		f.step_to = q.nearest
		f.step_t = 0.0
		stepping += 1


# How much the body is thinned at a foot's hip, 1 at full size: in a
# passage the legs flatten with the body, so the knees and the step's
# arc do not poke up through the thinned back.
func _leg_scale(f: Foot) -> float:
	return clampf(_draw_r[f.hip] / chain.radii[f.hip], 0.3, 1.0)


func _knee(f: Foot) -> Vector2:
	var hip: Vector2 = chain.points[f.hip]
	var foot := _foot_draw(f)
	var k := _leg_scale(f)
	# The knee rises at most half the leg's drop, so a leg folded flat
	# in a passage keeps its knee level with the hip, inside the body.
	var lift := minf(KNEE_OUT * k, maxf((hip - foot).dot(up), 0.0) * 0.5)
	return (hip + foot) * 0.5 + up * lift - _tangent() * f.end * facing * KNEE_BACK * k


# Where a foot is drawn. On a surface its position is a rock cell's
# centre (planted) or at that level (settling, or the end of a step), 2
# px inside the rock: the drawn foot is lifted onto the surface.
func _foot_draw(f: Foot) -> Vector2:
	return f.pos + (up * FOOT_LIFT if clinging else Vector2.ZERO)


# Far legs first, then the body, then the near legs: the colour layer
# keeps the last circle drawn, so far legs come out darker only where
# they show past the body, and near legs are the body's own colour.
func _push_blobs() -> void:
	var list: Array = []
	for b in extra_blobs:
		list.append(b)
	_leg_blobs(list, -1.0, FAR_LEG_COLOR)
	# A swallowed piece travels down the body as a bulge.
	var gulp_at := -1.0
	if _gulp > 0.0:
		gulp_at = (1.0 - _gulp / GULP_TIME) * 4.0
	for i in chain.size():
		var r_i: float = _draw_r[i]
		if gulp_at >= 0.0:
			r_i += 3.5 * maxf(0.0, 1.0 - absf(i - gulp_at))
		list.append([chain.points[i], r_i, BODY_COLOR])
		if i == 0:
			continue
		if _thin_on[i] or _thin_on[i - 1]:
			# A segment thinned to a passage is drawn as a tube: blobs
			# every 2 px, so its edge is straight rather than scalloped,
			# and does not flicker pixel by pixel as the body creeps along.
			for k in range(1, 4):
				var t := k / 4.0
				list.append([chain.points[i - 1].lerp(chain.points[i], t), lerpf(_draw_r[i - 1], _draw_r[i], t), BODY_COLOR])
		elif _draw_r[i] < 4.5:
			# Thin tail segments get filler blobs between them, so the tail
			# renders as a line rather than a row of dots; the thinnest get
			# two, so a stretched tail tip does not break into specks.
			var r_mid: float = (_draw_r[i - 1] + _draw_r[i]) * 0.5
			if _draw_r[i] < 3.0:
				for k in range(1, 4):
					list.append([chain.points[i - 1].lerp(chain.points[i], k / 4.0), r_mid, BODY_COLOR])
			else:
				list.append([chain.points[i - 1].lerp(chain.points[i], 0.5), r_mid, BODY_COLOR])
	var marks := _face(list)
	_leg_blobs(list, 1.0, BODY_COLOR)
	blobs.set_blobs(list)
	blobs.set_marks(marks)


func _leg_blobs(list: Array, side: float, color: Color) -> void:
	for f in feet:
		if f.side != side:
			continue
		var hip: Vector2 = chain.points[f.hip]
		var knee := _knee(f)
		var foot := _foot_draw(f)
		var leg_r := LEG_R * _leg_scale(f)
		# Blobs close enough along each segment that a stretched leg still
		# renders as one limb, not a row of specks; closer still for a
		# leg thinned with its body, whose blobs are smaller.
		var gap := LEG_BLOB_GAP * _leg_scale(f)
		var n1 := clampi(ceili(hip.distance_to(knee) / gap), 3, 16)
		for k in range(1, n1 + 1):
			var t := float(k) / n1
			list.append([hip.lerp(knee, t), leg_r, color])
		var n2 := clampi(ceili(knee.distance_to(foot) / gap), 3, 16)
		for k in range(1, n2 + 1):
			var t := float(k) / n2
			list.append([knee.lerp(foot, t), lerpf(leg_r, leg_r * 0.85, t), color])


# The face: the snout blob, and marks on the blob layer's pixel grid,
# drawn over the body by the layer itself so they are as crisp as its
# pixels: the eye, a black disc 4 px across a cell below the head's rim, and what
# the idle animation adds. A blink or a lick shuts the eye to a 4 by 2
# line on its lower side. A yawn lifts the snout, drops a jaw blob
# (added to list) below it and opens the dark inside of the mouth
# between them, the eye shut while it gapes. A lick runs the tongue
# from the mouth round the snout's tip to the eye and back.
func _face(list: Array) -> Array:
	var marks: Array = []
	var eye := chain.points[0] + look * 3.5 + up * 1.0
	var ax := _axis(up)
	var across := ax.abs()
	var along := Vector2.ONE - across
	var shut := false
	var gape := 0.0
	var lick := 0.0
	var ph := _anim_phase()
	var k := _anim_frac()
	var swell := k if ph == 0 else (1.0 if ph == 1 else 1.0 - k)
	match _anim:
		"blink":
			shut = ph == 1
		"lick":
			lick = swell
			shut = ph == 1
		"yawn":
			gape = YAWN_GAPE * swell
			shut = ph == 1
	# A swallow opens the mouth as the yawn does (_update_gape). A bite
	# only parts the lips: the snout stays put and no jaw blob drops,
	# so the head keeps its shape through the chew (the yawn's lifted
	# snout and dropped jaw swelled it with every bite, which read as a
	# swallow's bulge); the bite shows as the mouth mark opening and
	# shutting, to CHEW_MOUTH at the widest.
	var chew := _gape_chew and _gape >= gape
	gape = maxf(gape, _gape)
	list.append([chain.head() + look * SNOUT + up * (0.0 if chew else gape * 0.5), 5.0, BODY_COLOR])
	if gape > 0.0:
		# The mouth goes under the eye: at its widest its top row can
		# share the eye's row on the pixel grid.
		if not chew:
			list.append([chain.head() + look * (SNOUT + 0.5) - up * (3.0 + gape * 0.5), 3.5, BODY_COLOR])
		var h := minf(gape, CHEW_MOUTH) if chew else gape
		var size := along * 6.0 + across * (h + 1.0)
		marks.append([chain.head() + look * (SNOUT + 1.5) - up * 2.5 - size * 0.5, size, MOUTH_COLOR])
	if shut:
		marks.append([eye - ax - along * 2.0 - across, along * 4.0 + across * 2.0, EYE_COLOR])
	else:
		marks.append([eye + Vector2(-2.0, -2.0), 4.0, EYE_COLOR, true])
	if lick > 0.0:
		var m := _mouth()
		var ctrl := chain.head() + look * (SNOUT + 8.0) + up * 3.0
		var n := maxi(int(ceil(lick * LICK_SAMPLES)), 1)
		for i in range(n + 1):
			var s := minf(float(i) / LICK_SAMPLES, lick)
			var pt := m.lerp(ctrl, s).lerp(ctrl.lerp(eye, s), s)
			marks.append([pt - Vector2.ONE, 2.0, TONGUE_COLOR])
		var tip := m.lerp(ctrl, lick).lerp(ctrl.lerp(eye, lick), lick)
		marks.append([tip - Vector2(2.0, 2.0), 4.0, TONGUE_COLOR])
	return marks


func _anim_ticks() -> Array:
	match _anim:
		"blink":
			return BLINK_TICKS
		"lick":
			return LICK_TICKS
		"yawn":
			return YAWN_TICKS
	return []


# Which of the animation's three phases (out, hold, back) the tick is in.
func _anim_phase() -> int:
	var t := _anim_tick
	var ticks := _anim_ticks()
	for i in ticks.size():
		if t < ticks[i]:
			return i
		t -= ticks[i]
	return ticks.size()


# How far through its phase the tick is, 1.0 on the phase's last tick.
func _anim_frac() -> float:
	var t := _anim_tick
	var ticks := _anim_ticks()
	for i in ticks.size():
		if t < ticks[i]:
			return float(t + 1) / ticks[i]
		t -= ticks[i]
	return 1.0


func _anim_total() -> int:
	var n := 0
	for v in _anim_ticks():
		n += v
	return n


# Interrupted (a key, a button): straight to the closing phase, which
# is quick, rather than a snap shut.
func _anim_cancel() -> void:
	var ticks := _anim_ticks()
	if ticks.size() == 3:
		_anim_tick = maxi(_anim_tick, ticks[0] + ticks[1])


# Idle animations. After IDLE_AFTER seconds of nothing happening
# (clinging, no keys, no buttons, the tongue in) the gecko blinks,
# licks its eye or yawns, one every IDLE_GAP seconds, drawn from a
# shuffled bag of two blinks, a lick and a yawn, so none repeats for
# long and all turn up. The head keeps following the cursor meanwhile.
func _update_idle(inp: Vector2, dt: float) -> void:
	var idle := clinging and not swimming and not chewing and not tongue_out and _grab_n == Vector2.ZERO \
			and inp.length() <= 0.2 and not _lmb and absf(speed_along) < 1.0
	if idle:
		_idle_t += dt
	else:
		_idle_t = 0.0
		if _anim != "":
			_anim_cancel()
	if _anim != "":
		_anim_tick += 1
		if _anim_tick >= _anim_total():
			_anim = ""
			_anim_gap = _rng.randf_range(IDLE_GAP_MIN, IDLE_GAP_MAX)
	elif idle and _idle_t >= IDLE_AFTER:
		_anim_gap -= dt
		if _anim_gap <= 0.0:
			_anim = _next_anim()
			_anim_tick = 0


func _next_anim() -> String:
	if _anim_bag.is_empty():
		_anim_bag = ["blink", "blink", "lick", "yawn"]
		for i in range(_anim_bag.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var t: String = _anim_bag[i]
			_anim_bag[i] = _anim_bag[j]
			_anim_bag[j] = t
	return _anim_bag.pop_back()


func _draw() -> void:
	if chewing and debug:
		draw_arc(_bite, CHEW_R, 0.0, TAU, 20, Color(1.0, 0.8, 0.5, 0.6), 1.5)


# The tongue tapers from the mouth to its tip.
func _draw_under() -> void:
	if tongue_out:
		var mouth := _mouth()
		var mid := mouth.lerp(tongue_tip, 0.5)
		_under.draw_line(mouth, mid, TONGUE_COLOR, 3.0)
		_under.draw_line(mid, tongue_tip, TONGUE_COLOR, 2.0)


func _draw_debug() -> void:
	if not debug:
		return
	var c := _debug_layer
	c.draw_line(pos, pos + up * 30.0, Color(0.3, 0.9, 1.0), 1.5)
	c.draw_arc(pos, PROBE_R, 0.0, TAU, 32, Color(0.3, 0.9, 1.0, 0.25), 1.0)
	if _last_probe.get("found", false):
		c.draw_circle(_last_probe.nearest, 2.5, Color(1.0, 0.5, 0.2))
	for f in feet:
		var col := Color(0.2, 1.0, 0.3) if f.planted else (Color(1.0, 0.9, 0.2) if f.stepping else Color(1.0, 0.2, 0.2))
		c.draw_rect(Rect2(f.pos - Vector2(2.5, 2.5), Vector2(5.0, 5.0)), col, false, 1.0)


func debug_text() -> String:
	var planted := 0
	for f in feet:
		if f.planted:
			planted += 1
	var state := "cling" if clinging else ("swim" if swimming else "air")
	if tongue_anchored and not clinging:
		state = "pull"
	return "%s%s%s%s  tongue %s  feet %d/4  up (%.2f, %.2f)  speed %.0f  vel (%.0f, %.0f)" % [
		state, " chew" if chewing else "", " burrow" if _burrowing else "", " bridge" if _bridging else "", _tongue_state(), planted, up.x, up.y, speed_along, vel.x, vel.y]
